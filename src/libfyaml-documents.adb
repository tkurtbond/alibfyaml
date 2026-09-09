with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Unchecked_Deallocation;
with System;

package body Libfyaml.Documents is

   package CS renames Interfaces.C.Strings;
   use type C.int;
   use type CS.chars_ptr;
   use type Thin.Fy_Document;
   use type Thin.Fy_Diag_Error_Access;

   procedure Free_Cell is new Ada.Unchecked_Deallocation
     (Buffer_Cell, Buffer_Cell_Access);

   overriding procedure Adjust (Buf : in out Buffer_Ref) is
   begin
      if Buf.Cell /= null then
         Buf.Cell.Count := Buf.Cell.Count + 1;
      end if;
   end Adjust;

   overriding procedure Finalize (Buf : in out Buffer_Ref) is
   begin
      if Buf.Cell /= null then
         Buf.Cell.Count := Buf.Cell.Count - 1;
         if Buf.Cell.Count = 0 then
            if Buf.Cell.Text /= CS.Null_Ptr then
               CS.Free (Buf.Cell.Text);
            end if;
            Free_Cell (Buf.Cell);
         end if;
         Buf.Cell := null;
      end if;
   end Finalize;

   function Make_Buffer_Ref
     (Text : CS.chars_ptr) return Buffer_Ref
   is
   begin
      return (Ada.Finalization.Controlled with
                Cell => new Buffer_Cell'(Count => 1, Text => Text));
   end Make_Buffer_Ref;

   function Collected_Errors
     (Diag : Thin.Fy_Diag; File_Override : String := "") return String
   is
      use Ada.Strings.Unbounded;
      Msg  : Unbounded_String;
      Prev : aliased System.Address := System.Null_Address;
      Err  : Thin.Fy_Diag_Error_Access;
   begin
      loop
         Err := Thin.fy_diag_errors_iterate (Diag, Prev'Access);
         exit when Err = null;
         declare
            File : constant String :=
              (if File_Override'Length > 0 then File_Override
               elsif Err.File /= CS.Null_Ptr then CS.Value (Err.File)
               else "<input>");
            Text : constant String :=
              (if Err.Msg /= CS.Null_Ptr then CS.Value (Err.Msg) else "");
            Line   : constant String :=
              Ada.Strings.Fixed.Trim (Err.Line'Image, Ada.Strings.Left);
            Column : constant String :=
              Ada.Strings.Fixed.Trim (Err.Column'Image, Ada.Strings.Left);
         begin
            --  gcc diagnostic format: "file:line:column: error: message"
            --  -- no space between the colons and the numbers (Err.Line/
            --  Column'Image, being signed, carries one for a non-negative
            --  value unless trimmed), and an explicit "error:" severity
            --  word. Every entry fy_diag_errors_iterate hands back here
            --  is a genuine error (that's what "collect errors" means,
            --  confirmed by the function's own naming and doc comment --
            --  libfyaml is not filtering a mix of severities down to this
            --  one collection), so hardcoding "error:" rather than mapping
            --  Err.Err_Type is not a simplification that loses anything.
            Append (Msg, File & ":" & Line & ":" & Column & ": error: " &
                    Text & ASCII.LF);
         end;
      end loop;
      return To_String (Msg);
   end Collected_Errors;

   function Parse_Common
     (Build : not null access function
        (Cfg : access constant Thin.Fy_Parse_Cfg) return Thin.Fy_Document;
      Flags : C.unsigned := 0;
      File_Override : String := "")
      return Document
   is
      Diag : constant Thin.Fy_Diag := Thin.fy_diag_create (System.Null_Address);
      Cfg  : aliased Thin.Fy_Parse_Cfg;
   begin
      Thin.fy_diag_set_collect_errors (Diag, C.C_bool (True));
      Cfg.Diag := Diag;
      Cfg.Flags := Flags;
      declare
         Handle : constant Thin.Fy_Document := Build (Cfg'Access);
      begin
         if Handle = Thin.Null_Fy_Document then
            declare
               Text : constant String := Collected_Errors (Diag, File_Override);
            begin
               --  Diag is NOT destroyed here: raising below is itself
               --  "anything else above" from the exception handler's
               --  point of view, so destroying it on this path too was
               --  a double fy_diag_destroy call on every single parse
               --  failure (confirmed live: glibc's free() detects the
               --  corruption and aborts the process rather than
               --  Parse_Error ever reaching the caller). The handler
               --  below is the only place Diag is destroyed on any
               --  failure path now, exactly once.
               if Text'Length > 0 then
                  raise Libfyaml.Parse_Error with Text;
               else
                  raise Libfyaml.Parse_Error with "document failed to parse";
               end if;
            end;
         end if;
         Thin.fy_diag_destroy (Diag);
         return Document'(Ada.Finalization.Limited_Controlled
                           with Handle => Handle, Owned_Buffer => <>);
      end;
   exception
      --  Reached both by a genuine parse failure (Parse_Error raised
      --  just above) and, defense in depth, if Build itself ever
      --  raised for some other reason: either way Diag has not been
      --  destroyed yet on this path, so there is exactly one
      --  fy_diag_destroy call for it here.
      when others =>
         Thin.fy_diag_destroy (Diag);
         raise;
   end Parse_Common;

   function Resolve_Flags (Resolve_Anchors : Boolean) return C.unsigned is
     (if Resolve_Anchors then Thin.FYPCF_RESOLVE_DOCUMENT else 0);

   function Parse_String
     (Text : String; Resolve_Anchors : Boolean := True) return Document
   is
      C_Text : CS.chars_ptr := CS.New_String (Text);

      function Build
        (Cfg : access constant Thin.Fy_Parse_Cfg) return Thin.Fy_Document
      is (Thin.fy_document_build_from_string (Cfg, C_Text, C.size_t (Text'Length)));

   begin
      --  C_Text is NOT freed here: fy_document_build_from_string doesn't
      --  copy the input, so the resulting document's scalars can point
      --  directly into this buffer. Ownership transfers to the Document
      --  (see Owned_Buffer in the spec) and it's freed in Finalize.
      return Result : Document :=
        Parse_Common
          (Build'Access, Resolve_Flags (Resolve_Anchors), "(string-in-memory)")
      do
         Result.Owned_Buffer := Make_Buffer_Ref (C_Text);
      end return;
   exception
      when others =>
         CS.Free (C_Text);
         raise;
   end Parse_String;

   function Parse_File
     (Path : String; Resolve_Anchors : Boolean := True) return Document
   is
      C_Path : CS.chars_ptr := CS.New_String (Path);

      function Build
        (Cfg : access constant Thin.Fy_Parse_Cfg) return Thin.Fy_Document
      is (Thin.fy_document_build_from_file (Cfg, C_Path));

   begin
      return Result : constant Document :=
        Parse_Common (Build'Access, Resolve_Flags (Resolve_Anchors))
      do
         CS.Free (C_Path);
      end return;
   exception
      when others =>
         CS.Free (C_Path);
         raise;
   end Parse_File;

   procedure Resolve (Doc : in out Document) is
      Status : constant C.int := Thin.fy_document_resolve (Doc.Handle);
   begin
      if Status /= 0 then
         raise Libfyaml.Resolve_Error with "fy_document_resolve failed";
      end if;
   end Resolve;

   function Root (Doc : Document) return Nodes.Node is
     (Nodes.Wrap (Thin.fy_document_root (Doc.Handle)));

   procedure Set_Root (Doc : in out Document; N : Nodes.Node) is
      Status : constant C.int := Thin.fy_document_set_root (Doc.Handle, Nodes.Raw (N));
   begin
      if Status /= 0 then
         raise Program_Error with "fy_document_set_root failed";
      end if;
   end Set_Root;

   procedure Insert_At (Doc : in out Document; Path : String; N : in out Nodes.Node) is
      C_Path : CS.chars_ptr := CS.New_String (Path);
      Status : C.int;
   begin
      Status := Thin.fy_document_insert_at
        (Doc.Handle, C_Path, C.size_t (Path'Length), Nodes.Raw (N));
      CS.Free (C_Path);
      --  fy_document_insert_at's header is explicit: "in any case the
      --  fyn node will be unref'ed ... if the reference is 0 the node
      --  will be freed" -- that's unconditional, not just on failure.
      --  A freshly-built N (Create_Scalar/_Sequence/_Mapping) has no
      --  other reference, so it is freed on success too. Null out N
      --  in both cases before doing anything else, so a caller can't
      --  go on to touch what libfyaml just freed -- confirmed live
      --  with valgrind: without this, reading N after a *successful*
      --  merge was an invalid read of already-freed memory that
      --  happened to still hold old bytes, silently returning a
      --  plausible-looking (but freed) result instead of failing
      --  loudly.
      N := Nodes.Null_Node;
      if Status /= 0 then
         raise Program_Error with "fy_document_insert_at failed for path """ & Path & '"';
      end if;
   end Insert_At;

   function Create_Scalar (Doc : in out Document; Value : String) return Nodes.Node is
      C_Value : CS.chars_ptr := CS.New_String (Value);
      Result  : constant Thin.Fy_Node :=
        Thin.fy_node_create_scalar_copy (Doc.Handle, C_Value, C.size_t (Value'Length));
   begin
      CS.Free (C_Value);
      return Nodes.Wrap (Result);
   end Create_Scalar;

   function Create_Sequence (Doc : in out Document) return Nodes.Node is
     (Nodes.Wrap (Thin.fy_node_create_sequence (Doc.Handle)));

   function Create_Mapping (Doc : in out Document) return Nodes.Node is
     (Nodes.Wrap (Thin.fy_node_create_mapping (Doc.Handle)));

   function To_YAML (Doc : Document; Flags : Emit_Flags := Emit_Default) return String is
      Ptr : constant CS.chars_ptr := Thin.fy_emit_document_to_string (Doc.Handle, Flags);
   begin
      if Ptr = CS.Null_Ptr then
         raise Libfyaml.Emit_Error with "fy_emit_document_to_string failed";
      end if;
      declare
         Result : constant String := CS.Value (Ptr);
      begin
         Thin.C_Free (Ptr);
         return Result;
      end;
   end To_YAML;

   procedure Write_To_File
     (Doc : Document; Path : String; Flags : Emit_Flags := Emit_Default)
   is
      C_Path : CS.chars_ptr := CS.New_String (Path);
      Status : constant C.int := Thin.fy_emit_document_to_file (Doc.Handle, Flags, C_Path);
   begin
      CS.Free (C_Path);
      if Status /= 0 then
         raise Libfyaml.Emit_Error with "fy_emit_document_to_file failed for """ & Path & '"';
      end if;
   end Write_To_File;

   overriding procedure Finalize (Doc : in out Document) is
   begin
      if Doc.Handle /= Thin.Null_Fy_Document then
         Thin.fy_document_destroy (Doc.Handle);
         Doc.Handle := Thin.Null_Fy_Document;
      end if;
      --  Doc.Owned_Buffer is a Buffer_Ref, a controlled component --
      --  the language finalizes it automatically right after this
      --  procedure body completes; see its own Finalize.
   end Finalize;

end Libfyaml.Documents;
