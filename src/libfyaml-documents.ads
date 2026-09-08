--  Libfyaml.Documents - parse, build, mutate and emit a YAML/JSON document.
--
--  A Document owns a tree of Libfyaml.Nodes.Node handles; it is a
--  controlled (RAII) type that frees the underlying libfyaml document, and
--  every Node handle obtained from it, when it goes out of scope.

with Ada.Finalization;
with Interfaces.C;
with Libfyaml.Nodes;
with Libfyaml.Thin;

package Libfyaml.Documents is

   package C renames Interfaces.C;

   type Document is tagged limited private;

   -----------
   --  Parse --
   -----------

   function Parse_String (Text : String) return Document;
   --  Parse Text as a standalone YAML/JSON document.
   --  Raises Libfyaml.Parse_Error on a syntax error.

   function Parse_File (Path : String) return Document;
   --  Parse the file at Path as a standalone YAML/JSON document.
   --  Raises Libfyaml.Parse_Error if the file cannot be read or parsed.

   -----------------------
   --  Tree access/build --
   -----------------------

   function Root (Doc : Document) return Nodes.Node;
   --  The document's root node, or Nodes.Null_Node if the document has
   --  none yet.

   procedure Set_Root (Doc : in out Document; N : Nodes.Node);
   --  Make N (typically freshly built via Create_Scalar / _Sequence /
   --  _Mapping below) the document's root node.

   procedure Insert_At (Doc : in out Document; Path : String; N : Nodes.Node);
   --  Insert/replace the node at Path (libfyaml native path syntax, e.g.
   --  "/server") with N.

   function Create_Scalar (Doc : in out Document; Value : String) return Nodes.Node;
   --  Build a new scalar node holding a copy of Value. The node is not
   --  yet attached to the tree; attach it with Set_Root, Insert_At,
   --  Libfyaml.Nodes.Append, or Libfyaml.Nodes.Append_Pair.

   function Create_Sequence (Doc : in out Document) return Nodes.Node;
   function Create_Mapping (Doc : in out Document) return Nodes.Node;

   ------------
   --  Emit  --
   ------------

   subtype Emit_Flags is C.unsigned;

   Emit_Default          : constant Emit_Flags := Thin.FYECF_DEFAULT;
   Emit_Sort_Keys        : constant Emit_Flags := Thin.FYECF_SORT_KEYS;
   Emit_Mode_Block        : constant Emit_Flags := Thin.FYECF_MODE_BLOCK;
   Emit_Mode_Flow         : constant Emit_Flags := Thin.FYECF_MODE_FLOW;
   Emit_Mode_Flow_Oneline : constant Emit_Flags := Thin.FYECF_MODE_FLOW_ONELINE;
   Emit_Mode_JSON          : constant Emit_Flags := Thin.FYECF_MODE_JSON;
   --  Combine with "or", e.g. Emit_Sort_Keys or Emit_Mode_Block.

   function To_YAML (Doc : Document; Flags : Emit_Flags := Emit_Default) return String;
   --  Emit Doc to a string. Raises Libfyaml.Emit_Error on failure.

   procedure Write_To_File
     (Doc : Document; Path : String; Flags : Emit_Flags := Emit_Default);
   --  Emit Doc to the file at Path (opened "wa"). Raises
   --  Libfyaml.Emit_Error on failure.

private

   type Document is new Ada.Finalization.Limited_Controlled with record
      Handle : Thin.Fy_Document := Thin.Null_Fy_Document;
   end record;

   overriding procedure Finalize (Doc : in out Document);

end Libfyaml.Documents;
