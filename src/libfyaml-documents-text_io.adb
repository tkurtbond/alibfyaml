with Ada.Finalization;
with Ada.Text_IO.C_Streams;
with Interfaces.C;
with Libfyaml.Nodes;
with Libfyaml.Thin;
with System;

package body Libfyaml.Documents.Text_IO is

   package C renames Interfaces.C;

   function File_Label (File : Ada.Text_IO.File_Type) return String is
     (Ada.Text_IO.Name (File));
   --  Ada.Text_IO.Name gives a real path for an ordinary opened file, and
   --  "*stdin" for Standard_Input/Current_Input (confirmed live, GNAT) --
   --  both are genuinely informative, unlike Parse_String's synthetic
   --  memory-address fallback, so unlike Parse_String this is used as-is
   --  rather than overridden with a fixed placeholder.

   function Parse
     (File : Ada.Text_IO.File_Type; Resolve_Anchors : Boolean := True)
      return Document
   is
      Fp : constant System.Address := Ada.Text_IO.C_Streams.C_Stream (File);

      function Build
        (Cfg : access constant Thin.Fy_Parse_Cfg) return Thin.Fy_Document
      is (Thin.fy_document_build_from_fp (Cfg, Fp));

      Flags : constant C.unsigned :=
        (if Resolve_Anchors then Thin.FYPCF_RESOLVE_DOCUMENT else 0);

      Handle : constant Thin.Fy_Document :=
        Parse_Common (Build'Access, Flags, File_Label (File));
   begin
      --  No Owned_Buffer to set: see this package's own doc comment on
      --  Parse -- a FILE*-backed input is read into a buffer libfyaml
      --  allocates and owns itself, not a span into anything Ada-owned.
      return Document'(Ada.Finalization.Limited_Controlled with
                          Handle => Handle, Owned_Buffer => <>,
                          Owner => Nodes.New_Owner_Liveness);
   end Parse;

end Libfyaml.Documents.Text_IO;
