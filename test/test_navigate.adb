--  Primarily a worked example, not a pass/fail test: shows how to walk
--  an alibfyaml document tree and read out typed values. The output is
--  meant to be read as documentation of the techniques below -- but a
--  final "Regression checks" section (Check/Failures, same pattern as
--  the other tests) spot-checks a handful of the values it demonstrates,
--  so a regression here fails a test run rather than only being visible
--  to someone diffing console output by eye.
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
--      Includes a deeply nested (4 levels) example, reached three
--      ways: chained Value/Item, a single By_Path call, and nested
--      Iterate over every element at each level.

with Ada.Text_IO;
with Libfyaml.Documents;
with Libfyaml.Nodes;

procedure Test_Navigate is

   package Doc renames Libfyaml.Documents;
   package Nod renames Libfyaml.Nodes;

   --  The walkthrough above stays exactly that -- a worked example, not
   --  restructured into assertions, so it reads clearly as usage
   --  documentation. This spot-checks a handful of the same values it
   --  prints, so a regression here fails a test run instead of only
   --  being visible to someone diffing console output by eye.
   Failures : Natural := 0;

   procedure Check (Label : String; Condition : Boolean) is
   begin
      if Condition then
         Ada.Text_IO.Put_Line ("ok   - " & Label);
      else
         Ada.Text_IO.Put_Line ("FAIL - " & Label);
         Failures := Failures + 1;
      end if;
   end Check;

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

      -----------------------------------------------------------------
      --  4 levels of nesting: company -> departments (sequence) ->
      --  department (mapping) -> teams (sequence) -> team (mapping).
      --  Three ways to reach the same deeply nested field.
      -----------------------------------------------------------------
      Ada.Text_IO.New_Line;
      Ada.Text_IO.Put_Line ("=== Deeply nested access (4 levels) ===");

      --  (a) Chained Value/Item calls, indexing down one level at a
      --  time -- Item is 1-based (see Libfyaml.Nodes).
      Ada.Text_IO.Put_Line
        ("chained: first team of first department, lead = " &
         D.Root.Value ("company").Value ("departments").Item (1)
           .Value ("teams").Item (1).String_Value ("lead"));

      --  (b) The same field via By_Path, in one call. libfyaml's
      --  native path syntax indexes sequences from 0, unlike Item.
      Ada.Text_IO.Put_Line
        ("By_Path: " &
         D.Root.By_Path ("/company/departments/0/teams/0/lead").Scalar_Value);

      --  (c) Nested Iterate: walk every department, and within each,
      --  every team, reading typed fields (String_Value, Integer_Value)
      --  at the bottom of the chain. This is the pattern for "process
      --  every X" rather than "reach one known field".
      declare
         Departments : constant Nod.Node :=
           D.Root.Value ("company").Value ("departments");

         procedure Visit_Team (Team : Nod.Node) is
         begin
            Ada.Text_IO.Put_Line
              ("    team " & Team.String_Value ("name") & ": size " &
               Team.Integer_Value ("size")'Image & ", lead " &
               Team.String_Value ("lead"));
         end Visit_Team;

         procedure Visit_Department (Department : Nod.Node) is
         begin
            Ada.Text_IO.Put_Line
              ("  department " & Department.String_Value ("name") & ":");
            Department.Value ("teams").Iterate (Visit_Team'Access);
         end Visit_Department;
      begin
         Ada.Text_IO.Put_Line
           ("nested Iterate over all departments/teams of " &
            D.Root.Value ("company").String_Value ("name") & ":");
         Departments.Iterate (Visit_Department'Access);
      end;

      -----------------------------------------------------------------
      --  Regression checks: spot-check a handful of the values the
      --  walkthrough above already printed, at each depth demonstrated
      --  (top-level scalar, sequence, nested mapping, sequence of
      --  mappings, and the 4-levels-deep case via both access paths).
      -----------------------------------------------------------------
      Ada.Text_IO.New_Line;
      Ada.Text_IO.Put_Line ("=== Regression checks ===");
      Check ("top-level name", D.Root.String_Value ("name") = "Sample Config");
      Check ("top-level version", D.Root.Integer_Value ("version") = 3);
      Check ("tags sequence: first tag",
             D.Root.Value ("tags").Item (1).Scalar_Value = "alpha");
      Check ("nested mapping: server.port",
             D.Root.Value ("server").Integer_Value ("port") = 8080);
      Check ("sequence of mappings: endpoints (1).name",
             D.Root.Value ("endpoints").Item (1).String_Value ("name") = "health");
      Check ("4 levels deep, chained Value/Item = By_Path",
             D.Root.Value ("company").Value ("departments").Item (1)
               .Value ("teams").Item (1).String_Value ("lead") =
             D.Root.By_Path ("/company/departments/0/teams/0/lead").Scalar_Value);
      Check ("4 levels deep, expected value",
             D.Root.By_Path ("/company/departments/0/teams/0/lead").Scalar_Value =
             "Ada Lovelace");

      Ada.Text_IO.New_Line;
      if Failures = 0 then
         Ada.Text_IO.Put_Line ("All checks passed.");
      else
         Ada.Text_IO.Put_Line (Integer'Image (Failures) & " check(s) failed.");
      end if;
   end;
end Test_Navigate;
