--  A worked example, not a pass/fail test: shows how to walk an
--  alibfyaml document tree and read out typed values.
--
--  Two complementary techniques, both against test/navigate.yaml:
--
--   1. Dump: a small generic recursive walker that visits every node
--      regardless of shape, dispatching on Node_Kind for
--      mappings/sequences and on the typed-scalar predicates
--      (Is_Null_Value/Is_Boolean/Is_Integer/Is_Float, falling back to
--      plain text) for scalars. Useful when you don't know a
--      document's shape ahead of time.
--
--   2. Targeted field access: chained Value(Key) lookups, By_Path, and
--      Item/Iterate on sequences, reading each field with the typed
--      accessor appropriate to what it's known to hold. This is the
--      shape most real programs actually use, once the document's
--      structure (a config file format, say) is known in advance.

with Ada.Text_IO;
with Libfyaml.Documents;
with Libfyaml.Nodes;

procedure Test_Navigate is

   package Doc renames Libfyaml.Documents;
   package Nod renames Libfyaml.Nodes;

   ---------------------------------------------------------------------
   --  1. Generic recursive walk, dispatching on node/scalar shape.
   ---------------------------------------------------------------------

   procedure Dump_Scalar (N : Nod.Node) is
   begin
      --  Checked in YAML's own core-schema precedence order: null,
      --  then bool, then int, then float, then (falling through)
      --  plain string. Is_Integer and Is_Float both accept
      --  integer-shaped text (see PLAN.md), so Is_Integer must be
      --  checked first to report "42" as an integer rather than a
      --  float that happens to have no fractional part.
      if N.Is_Null_Value then
         Ada.Text_IO.Put_Line ("null");
      elsif N.Is_Boolean then
         Ada.Text_IO.Put_Line ("boolean " & N.Boolean_Value'Image);
      elsif N.Is_Integer then
         Ada.Text_IO.Put_Line ("integer " & N.Long_Long_Integer_Value'Image);
      elsif N.Is_Float then
         Ada.Text_IO.Put_Line ("float " & N.Long_Float_Value'Image);
      else
         Ada.Text_IO.Put_Line ("string """ & N.Scalar_Value & """");
      end if;
   end Dump_Scalar;

   procedure Dump (N : Nod.Node; Depth : Natural) is
      Indent : constant String (1 .. Depth * 2) := (others => ' ');
   begin
      case N.Kind is
         when Nod.Mapping_Node =>
            declare
               procedure Visit (Key, Value : Nod.Node) is
               begin
                  Ada.Text_IO.Put (Indent & Key.Scalar_Value & ": ");
                  if Value.Is_Scalar then
                     Dump_Scalar (Value);
                  else
                     Ada.Text_IO.New_Line;
                     Dump (Value, Depth + 1);
                  end if;
               end Visit;
            begin
               N.Iterate (Visit'Access);
            end;

         when Nod.Sequence_Node =>
            declare
               procedure Visit (Element : Nod.Node) is
               begin
                  Ada.Text_IO.Put (Indent & "- ");
                  if Element.Is_Scalar then
                     Dump_Scalar (Element);
                  else
                     Ada.Text_IO.New_Line;
                     Dump (Element, Depth + 1);
                  end if;
               end Visit;
            begin
               N.Iterate (Visit'Access);
            end;

         when Nod.Scalar_Node =>
            Dump_Scalar (N);
      end case;
   end Dump;

begin
   declare
      D : constant Doc.Document := Doc.Parse_File ("navigate.yaml");
   begin
      Ada.Text_IO.Put_Line ("=== Full tree walk (Dump) ===");
      Dump (D.Root, 0);

      -----------------------------------------------------------------
      --  2. Targeted access: read specific, already-known fields.
      -----------------------------------------------------------------
      Ada.Text_IO.New_Line;
      Ada.Text_IO.Put_Line ("=== Targeted field access ===");

      --  Top-level scalars, each read with its type-appropriate
      --  accessor directly off the mapping.
      Ada.Text_IO.Put_Line ("name    = " & D.Root.String_Value ("name"));
      Ada.Text_IO.Put_Line ("version = " & D.Root.Integer_Value ("version")'Image);
      Ada.Text_IO.Put_Line ("pi      = " & D.Root.Float_Value ("pi")'Image);
      Ada.Text_IO.Put_Line ("enabled = " & D.Root.Boolean_Value ("enabled")'Image);
      Ada.Text_IO.Put_Line
        ("homepage is null?    = " &
         D.Root.Value ("homepage").Is_Null_Value'Image);
      Ada.Text_IO.Put_Line
        ("description is null? = " &
         D.Root.Value ("description").Is_Null_Value'Image);

      --  A sequence of scalars: indexed access and iteration.
      declare
         Tags : constant Nod.Node := D.Root.Value ("tags");

         procedure Show_Tag (Element : Nod.Node) is
         begin
            Ada.Text_IO.Put (Element.Scalar_Value & " ");
         end Show_Tag;
      begin
         Ada.Text_IO.Put_Line ("first tag (Item (1)) = " & Tags.Item (1).Scalar_Value);
         Ada.Text_IO.Put ("all tags (Iterate)   = ");
         Tags.Iterate (Show_Tag'Access);
         Ada.Text_IO.New_Line;
      end;

      --  A nested mapping: either chain Value(Key) calls, or use
      --  By_Path with libfyaml's native path syntax.
      Ada.Text_IO.Put_Line
        ("server.host (chained Value) = " &
         D.Root.Value ("server").String_Value ("host"));
      Ada.Text_IO.Put_Line
        ("server.port (By_Path)       = " &
         D.Root.By_Path ("/server/port").Integer_Value'Image);
      Ada.Text_IO.Put_Line
        ("server.timeout               = " &
         D.Root.Value ("server").Float_Value ("timeout")'Image);
      Ada.Text_IO.Put_Line
        ("server.ssl                   = " &
         D.Root.Value ("server").Boolean_Value ("ssl")'Image);

      --  A sequence of mappings: index into the sequence, then read
      --  typed fields out of each element.
      declare
         Endpoints : constant Nod.Node := D.Root.Value ("endpoints");
      begin
         for I in 1 .. Endpoints.Length loop
            declare
               Endpoint : constant Nod.Node := Endpoints.Item (I);
            begin
               Ada.Text_IO.Put_Line
                 ("endpoint" & I'Image & ": " &
                  Endpoint.String_Value ("name") & " " &
                  Endpoint.String_Value ("path") & " (public: " &
                  Endpoint.Boolean_Value ("public")'Image & ")");
            end;
         end loop;
      end;
   end;
end Test_Navigate;
