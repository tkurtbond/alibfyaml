with Ada.Strings.Unbounded;
with Interfaces.C.Strings;
with System;

package body Libfyaml.Documents is

   package CS renames Interfaces.C.Strings;
   use type C.int;
   use type CS.chars_ptr;
   use type Thin.Fy_Document;
   use type Thin.Fy_Diag_Error_Access;

   function Collected_Errors (Diag : Thin.Fy_Diag) return String is
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
              (if Err.File /= CS.Null_Ptr then CS.Value (Err.File) else "<input>");
            Text : constant String :=
              (if Err.Msg /= CS.Null_Ptr then CS.Value (Err.Msg) else "");
         begin
            Append (Msg, File);
            Append (Msg, ":" & Err.Line'Image & ":" & Err.Column'Image & ": " & Text & ASCII.LF);
         end;
      end loop;
      return To_String (Msg);
   end Collected_Errors;

   function Parse_Common
     (Build : not null access function
        (Cfg : access constant Thin.Fy_Parse_Cfg) return Thin.Fy_Document)
      return Document
   is
      Diag : constant Thin.Fy_Diag := Thin.fy_diag_create (System.Null_Address);
      Cfg  : aliased Thin.Fy_Parse_Cfg;
   begin
      Thin.fy_diag_set_collect_errors (Diag, C.C_bool (True));
      Cfg.Diag := Diag;
      declare
         Handle : constant Thin.Fy_Document := Build (Cfg'Access);
      begin
         if Handle = Thin.Null_Fy_Document then
            declare
               Text : constant String := Collected_Errors (Diag);
            begin
               Thin.fy_diag_destroy (Diag);
               if Text'Length > 0 then
                  raise Libfyaml.Parse_Error with Text;
               else
                  raise Libfyaml.Parse_Error with "document failed to parse";
               end if;
            end;
         end if;
         Thin.fy_diag_destroy (Diag);
         return Document'(Ada.Finalization.Limited_Controlled with Handle => Handle);
      end;
   end Parse_Common;

   function Parse_String (Text : String) return Document is
      C_Text : CS.chars_ptr := CS.New_String (Text);

      function Build
        (Cfg : access constant Thin.Fy_Parse_Cfg) return Thin.Fy_Document
      is (Thin.fy_document_build_from_string (Cfg, C_Text, C.size_t (Text'Length)));

   begin
      return Result : constant Document := Parse_Common (Build'Access) do
         CS.Free (C_Text);
      end return;
   exception
      when others =>
         CS.Free (C_Text);
         raise;
   end Parse_String;

   function Parse_File (Path : String) return Document is
      C_Path : CS.chars_ptr := CS.New_String (Path);

      function Build
        (Cfg : access constant Thin.Fy_Parse_Cfg) return Thin.Fy_Document
      is (Thin.fy_document_build_from_file (Cfg, C_Path));

   begin
      return Result : constant Document := Parse_Common (Build'Access) do
         CS.Free (C_Path);
      end return;
   exception
      when others =>
         CS.Free (C_Path);
         raise;
   end Parse_File;

   function Root (Doc : Document) return Nodes.Node is
     (Nodes.Wrap (Thin.fy_document_root (Doc.Handle)));

   procedure Set_Root (Doc : in out Document; N : Nodes.Node) is
      Status : constant C.int := Thin.fy_document_set_root (Doc.Handle, Nodes.Raw (N));
   begin
      if Status /= 0 then
         raise Program_Error with "fy_document_set_root failed";
      end if;
   end Set_Root;

   procedure Insert_At (Doc : in out Document; Path : String; N : Nodes.Node) is
      C_Path : CS.chars_ptr := CS.New_String (Path);
      Status : C.int;
   begin
      Status := Thin.fy_document_insert_at
        (Doc.Handle, C_Path, C.size_t (Path'Length), Nodes.Raw (N));
      CS.Free (C_Path);
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
   end Finalize;

end Libfyaml.Documents;
