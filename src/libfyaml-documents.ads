--  Libfyaml.Documents - parse, build, mutate and emit a YAML/JSON document.
--
--  A Document owns a tree of Libfyaml.Nodes.Node handles; it is a
--  controlled (RAII) type that frees the underlying libfyaml document, and
--  every Node handle obtained from it, when it goes out of scope.

with Ada.Finalization;
with Interfaces.C;
with Interfaces.C.Strings;
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

   --  Note: Parse_String/Parse_File always mean "parse exactly one
   --  document" -- given input with more than one "---"-separated
   --  document, they silently parse only the first (this is what the
   --  underlying fy_document_build_from_string/_file do). For input
   --  that may hold more than one document, see the child package
   --  Libfyaml.Documents.Streams.

   -----------------------
   --  Tree access/build --
   -----------------------

   function Root (Doc : Document) return Nodes.Node;
   --  The document's root node, or Nodes.Null_Node if the document has
   --  none yet.

   procedure Set_Root (Doc : in out Document; N : Nodes.Node);
   --  Make N (typically freshly built via Create_Scalar / _Sequence /
   --  _Mapping below) the document's root node. Unlike Insert_At, N is
   --  attached outright, not merged: fy_document_set_root's own header
   --  documents no unref of N (only that the *previous* root, if any, is
   --  freed) -- N remains valid and reads back exactly what was built.

   procedure Insert_At (Doc : in out Document; Path : String; N : in out Nodes.Node);
   --  Insert/replace the node at Path (libfyaml native path syntax, e.g.
   --  "/server") with N, following libfyaml's fy_node_insert merge rules
   --  (a scalar overwrites the target; a sequence/mapping N is appended
   --  into an existing sequence/mapping target rather than replacing it
   --  outright). N is always consumed by this call -- libfyaml
   --  unconditionally unrefs it, on both success and failure:
   --
   --  * On success, N remains Is_Valid and safe to touch, but its
   --    *content* may no longer be what you built: confirmed for both
   --    the merge case (a sequence/mapping N's items/pairs are moved
   --    into an existing sequence/mapping target, leaving N itself
   --    behind empty) and, more surprisingly, the plain-overwrite case
   --    (replacing an existing scalar with another scalar N can leave N
   --    no longer reading back its own pre-call text, even though the
   --    right value ends up attached at Path). This is libfyaml's own
   --    fy_node_insert behavior, not something this binding changes or
   --    can predict node-kind-by-node-kind. Never assume N still holds
   --    what it held before the call; re-fetch from Path via
   --    Libfyaml.Nodes.By_Path instead if you need the attached result.
   --  * On failure (Program_Error raised), N had nothing else
   --    referencing it, so libfyaml frees it outright -- a real
   --    use-after-free hazard if left unaddressed. This binding sets N
   --    to Nodes.Null_Node before the exception propagates specifically
   --    to close that hazard: any further use of N after a caught
   --    Program_Error fails a precondition (with -gnata enabled) instead
   --    of touching freed memory.

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
      Handle       : Thin.Fy_Document := Thin.Null_Fy_Document;
      Owned_Buffer : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.Null_Ptr;
      --  Only set by Parse_String: fy_document_build_from_string does not
      --  copy its input (libfyaml is zero-copy in its core parsing
      --  paths), so the source buffer must outlive the document. Freed
      --  in Finalize.
   end record;

   overriding procedure Finalize (Doc : in out Document);

   function Collected_Errors (Diag : Thin.Fy_Diag) return String;
   --  Format Diag's collected errors as "file:line:col: message" lines.
   --  Declared here (not just in the body) so the child package
   --  Libfyaml.Documents.Streams can reuse it instead of duplicating
   --  the same formatting logic.

end Libfyaml.Documents;
