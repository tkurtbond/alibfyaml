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

   function Parse_String
     (Text : String; Resolve_Anchors : Boolean := True) return Document;
   --  Parse Text as a standalone YAML/JSON document.
   --  Raises Libfyaml.Parse_Error on a syntax error.
   --
   --  Resolve_Anchors controls whether anchors (&foo), aliases (*foo),
   --  and merge keys (<<: *foo) are resolved as part of parsing (sets
   --  FYPCF_RESOLVE_DOCUMENT; see fy_document_resolve). Left
   --  unresolved, an alias node reads back via Scalar_Value as its own
   --  anchor-name text (e.g. "foo"), not the referenced content, and a
   --  merge key just leaves a literal "<<" key in the mapping instead
   --  of the merged-in pairs -- both silently, with no error. Defaults
   --  to True: alibfyaml has no released consumers to break, and a
   --  YAML-parsing library silently mis-decoding anchored input by
   --  default is the worse surprise for a new caller. Pass False to
   --  see the raw, unresolved tree instead (e.g. to inspect anchors/
   --  aliases themselves via Libfyaml.Nodes.Is_Alias/Tag), or resolve
   --  it explicitly afterward via Resolve below.

   function Parse_File
     (Path : String; Resolve_Anchors : Boolean := True) return Document;
   --  As Parse_String, but reading from the file at Path. Raises
   --  Libfyaml.Parse_Error if the file cannot be read or parsed.

   --  Note: Parse_String/Parse_File always mean "parse exactly one
   --  document" -- given input with more than one "---"-separated
   --  document, they silently parse only the first (this is what the
   --  underlying fy_document_build_from_string/_file do). For input
   --  that may hold more than one document, see the child package
   --  Libfyaml.Documents.Streams.

   procedure Resolve (Doc : in out Document);
   --  Resolve anchors, aliases, and merge keys in Doc in place (wraps
   --  fy_document_resolve) -- the same resolution Parse_String/
   --  Parse_File perform automatically when Resolve_Anchors is True,
   --  but usable on a document built programmatically (Create_*/
   --  Set_Root) or parsed with Resolve_Anchors => False. Raises
   --  Libfyaml.Resolve_Error on failure (e.g. a merge-key cycle); its
   --  header doesn't document what state Doc is left in on failure
   --  (partial resolution is possible), so treat Doc as unreliable
   --  afterward rather than assuming either full resolution or a
   --  clean rollback.

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
   --  outright). N is always consumed by this call -- libfyaml's header
   --  is explicit that the node is unconditionally unref'ed, on both
   --  success and failure, and freed outright if that drops its
   --  reference count to zero. A freshly-built N (Create_Scalar /
   --  _Sequence / _Mapping, not yet attached anywhere else) has no
   --  other reference, so this applies on success just as much as on
   --  failure -- confirmed live with valgrind: an earlier version of
   --  this binding only nulled N out on failure, and a "successful"
   --  merge left N pointing at memory libfyaml had already freed
   --  (masked without valgrind because the freed bytes happened to
   --  still look plausible).
   --
   --  This binding therefore always sets N to Nodes.Null_Node before
   --  returning or raising, regardless of Status: any further use of N
   --  after calling Insert_At fails a precondition (with -gnata
   --  enabled) instead of touching freed memory. If you need the
   --  attached result, re-fetch it from Path via Libfyaml.Nodes.By_Path
   --  -- never assume N itself still holds anything.

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
