--  Libfyaml.Thin - direct Interfaces.C imports over libfyaml's core API
--
--  This is a 1:1 low-level binding: opaque handles are System.Address-sized
--  values, strings are C strings with explicit lengths, and no ownership or
--  error-checking policy is imposed. Build the idiomatic Ada API in
--  Libfyaml.Documents / Libfyaml.Nodes on top of this package rather than
--  using it directly.
--
--  Only the non-variadic core (parser/document/node/emitter/diag) surface is
--  covered. libfyaml also has a generics layer (fy_generic, built mostly on
--  C11 _Generic/variadic macros with no direct C-callable equivalent) and a
--  reflection layer (typed C-struct serdes driven by libclang or packed
--  metadata) that are out of scope here.

with Interfaces.C;
with Interfaces.C.Strings;
with System;

package Libfyaml.Thin is

   package C renames Interfaces.C;
   package CS renames Interfaces.C.Strings;

   use type C.unsigned;

   --------------------
   --  Opaque handles --
   --------------------

   type Fy_Document is new System.Address;
   type Fy_Node     is new System.Address;
   type Fy_Node_Pair is new System.Address;
   type Fy_Diag     is new System.Address;
   type Fy_Parser   is new System.Address;
   type Fy_Token    is new System.Address;

   Null_Fy_Document  : constant Fy_Document  := Fy_Document (System.Null_Address);
   Null_Fy_Node      : constant Fy_Node      := Fy_Node (System.Null_Address);
   Null_Fy_Node_Pair : constant Fy_Node_Pair := Fy_Node_Pair (System.Null_Address);
   Null_Fy_Diag      : constant Fy_Diag      := Fy_Diag (System.Null_Address);
   Null_Fy_Parser    : constant Fy_Parser    := Fy_Parser (System.Null_Address);
   Null_Fy_Token     : constant Fy_Token     := Fy_Token (System.Null_Address);

   -----------------------
   --  fy_node_type enum --
   -----------------------

   type Fy_Node_Type is (FYNT_SCALAR, FYNT_SEQUENCE, FYNT_MAPPING);
   for Fy_Node_Type use (FYNT_SCALAR => 0, FYNT_SEQUENCE => 1, FYNT_MAPPING => 2);
   for Fy_Node_Type'Size use C.int'Size;
   pragma Convention (C, Fy_Node_Type);

   -----------------------------------
   --  fy_node_walk_flags (bitmask) --
   -----------------------------------

   FYNWF_DONT_FOLLOW : constant C.unsigned := 0;
   FYNWF_FOLLOW       : constant C.unsigned := 1;
   --  Path syntax selection bits (default is YAML-pointer-ish native path
   --  syntax used throughout the examples, value 0).
   FYNWF_PTR_YAML     : constant C.unsigned := 0;

   -------------------------------------
   --  fy_parse_cfg_flags (bitmask)   --
   -------------------------------------

   FYPCF_RESOLVE_DOCUMENT : constant C.unsigned := 2#0100#;
   --  Bit 2: resolve anchors/aliases/merge keys while building a
   --  document (see fy_document_resolve). Used by
   --  Libfyaml.Documents.Parse_String/Parse_File's Resolve_Anchors
   --  parameter.

   -----------------------------
   --  fy_node_style enum     --
   -----------------------------

   type Fy_Node_Style is
     (FYNS_ANY, FYNS_FLOW, FYNS_BLOCK, FYNS_PLAIN, FYNS_SINGLE_QUOTED,
      FYNS_DOUBLE_QUOTED, FYNS_LITERAL, FYNS_FOLDED, FYNS_ALIAS);
   for Fy_Node_Style use
     (FYNS_ANY => -1, FYNS_FLOW => 0, FYNS_BLOCK => 1, FYNS_PLAIN => 2,
      FYNS_SINGLE_QUOTED => 3, FYNS_DOUBLE_QUOTED => 4, FYNS_LITERAL => 5,
      FYNS_FOLDED => 6, FYNS_ALIAS => 7);
   for Fy_Node_Style'Size use C.int'Size;
   pragma Convention (C, Fy_Node_Style);

   -------------------------------------
   --  fy_emitter_cfg_flags (bitmask) --
   -------------------------------------

   FYECF_SORT_KEYS         : constant C.unsigned := 2#0000_0001#;
   FYECF_OUTPUT_COMMENTS   : constant C.unsigned := 2#0000_0010#;
   FYECF_STRIP_LABELS      : constant C.unsigned := 2#0000_0100#;
   FYECF_STRIP_TAGS        : constant C.unsigned := 2#0000_1000#;
   FYECF_STRIP_DOC         : constant C.unsigned := 2#0001_0000#;
   FYECF_NO_ENDING_NEWLINE : constant C.unsigned := 2#0010_0000#;

   --  Mode is a 4-bit field starting at bit 8 (see FYECF_MODE_SHIFT in the
   --  C header); width is a further field. We only expose the named modes
   --  actually used by the thick binding.
   FYECF_MODE_SHIFT : constant := 8;

   FYECF_MODE_ORIGINAL     : constant C.unsigned := 0 * 2 ** FYECF_MODE_SHIFT;
   FYECF_MODE_BLOCK        : constant C.unsigned := 1 * 2 ** FYECF_MODE_SHIFT;
   FYECF_MODE_FLOW         : constant C.unsigned := 2 * 2 ** FYECF_MODE_SHIFT;
   FYECF_MODE_FLOW_ONELINE : constant C.unsigned := 3 * 2 ** FYECF_MODE_SHIFT;
   FYECF_MODE_JSON         : constant C.unsigned := 4 * 2 ** FYECF_MODE_SHIFT;

   --  Width field: bits 16..23, value 255 means "infinite" (see header).
   FYECF_WIDTH_SHIFT : constant := 16;
   FYECF_WIDTH_INF   : constant C.unsigned := 255 * 2 ** FYECF_WIDTH_SHIFT;

   FYECF_DEFAULT : constant C.unsigned :=
     FYECF_WIDTH_INF or FYECF_MODE_ORIGINAL;

   ------------------------
   --  struct fy_parse_cfg --
   ------------------------

   type Fy_Parse_Cfg is record
      Search_Path : CS.chars_ptr := CS.Null_Ptr;
      Flags       : C.unsigned := 0;
      Userdata    : System.Address := System.Null_Address;
      Diag        : Fy_Diag := Null_Fy_Diag;
   end record
     with Convention => C;

   -------------------------
   --  struct fy_diag_error --
   -------------------------

   type Fy_Diag_Error is record
      Err_Type : C.int;
      Module   : C.int;
      Fyt      : System.Address;
      Msg      : CS.chars_ptr;
      File     : CS.chars_ptr;
      Line     : C.int;
      Column   : C.int;
   end record
     with Convention => C;

   type Fy_Diag_Error_Access is access all Fy_Diag_Error;
   pragma Convention (C, Fy_Diag_Error_Access);

   ---------------------
   --  Document lifecycle --
   ---------------------

   function fy_document_build_from_string
     (Cfg : access constant Fy_Parse_Cfg;
      Str : CS.chars_ptr;
      Len : C.size_t) return Fy_Document
     with Import, Convention => C, External_Name => "fy_document_build_from_string";

   function fy_document_build_from_file
     (Cfg : access constant Fy_Parse_Cfg;
      File : CS.chars_ptr) return Fy_Document
     with Import, Convention => C, External_Name => "fy_document_build_from_file";

   -----------------------------------------------------------------
   --  Streaming parser: multiple documents from one input
   --  (Libfyaml.Documents.Streams.Document_Stream). Distinct from
   --  fy_document_build_from_string/_file above, which build
   --  exactly one document.
   -----------------------------------------------------------------

   function fy_parser_create (Cfg : access constant Fy_Parse_Cfg) return Fy_Parser
     with Import, Convention => C, External_Name => "fy_parser_create";

   procedure fy_parser_destroy (Fyp : Fy_Parser)
     with Import, Convention => C, External_Name => "fy_parser_destroy";

   function fy_parser_set_string
     (Fyp : Fy_Parser; Str : CS.chars_ptr; Len : C.size_t) return C.int
     with Import, Convention => C, External_Name => "fy_parser_set_string";

   function fy_parser_set_input_file
     (Fyp : Fy_Parser; File : CS.chars_ptr) return C.int
     with Import, Convention => C, External_Name => "fy_parser_set_input_file";

   function fy_parse_load_document (Fyp : Fy_Parser) return Fy_Document
     with Import, Convention => C, External_Name => "fy_parse_load_document";

   function fy_parser_set_diag (Fyp : Fy_Parser; Diag : Fy_Diag) return C.int
     with Import, Convention => C, External_Name => "fy_parser_set_diag";
   --  Replaces Fyp's diagnostic object with Diag. Per libfyaml's header:
   --  the previous diag is unref'ed (freed if that drops its refcount to
   --  0), and Diag itself gains a reference from the parser -- the
   --  caller's own reference to Diag (from fy_diag_create) is untouched
   --  and still needs its own fy_diag_destroy. Used by
   --  Libfyaml.Documents.Streams to swap in a fresh Diag after a parse
   --  error, since fy_diag_got_error is a sticky flag and
   --  fy_diag_errors_iterate's collected-errors list is cumulative --
   --  neither is cleared by libfyaml itself, and there is no
   --  clear-collected-errors call, so the only way to stop a past error
   --  from being misreported against later, unrelated documents is to
   --  hand the parser a brand new Diag.

   procedure fy_document_destroy (Fyd : Fy_Document)
     with Import, Convention => C, External_Name => "fy_document_destroy";

   function fy_document_root (Fyd : Fy_Document) return Fy_Node
     with Import, Convention => C, External_Name => "fy_document_root";

   function fy_document_set_root
     (Fyd : Fy_Document; Fyn : Fy_Node) return C.int
     with Import, Convention => C, External_Name => "fy_document_set_root";

   function fy_document_insert_at
     (Fyd  : Fy_Document;
      Path : CS.chars_ptr;
      Path_Len : C.size_t;
      Fyn  : Fy_Node) return C.int
     with Import, Convention => C, External_Name => "fy_document_insert_at";

   function fy_document_get_diag (Fyd : Fy_Document) return Fy_Diag
     with Import, Convention => C, External_Name => "fy_document_get_diag";

   function fy_document_resolve (Fyd : Fy_Document) return C.int
     with Import, Convention => C, External_Name => "fy_document_resolve";
   --  Resolves anchors, aliases, and merge keys in place: 0 on success,
   --  -1 on error (e.g. a merge-key cycle).

   ---------------------
   --  Node predicates --
   ---------------------

   function fy_node_get_type (Fyn : Fy_Node) return Fy_Node_Type
     with Import, Convention => C, External_Name => "fy_node_get_type";

   --  fy_node_is_scalar/_sequence/_mapping are "static inline" convenience
   --  wrappers around fy_node_get_type in the C header (not exported
   --  library symbols), so they are not bindable via pragma Import; the
   --  thick Libfyaml.Nodes package reimplements them by comparing
   --  fy_node_get_type's result instead.

   function fy_node_is_null (Fyn : Fy_Node) return C.C_bool
     with Import, Convention => C, External_Name => "fy_node_is_null";

   function fy_node_get_style (Fyn : Fy_Node) return Fy_Node_Style
     with Import, Convention => C, External_Name => "fy_node_get_style";

   --  fy_node_is_alias is likewise a "static inline" convenience wrapper
   --  (fy_node_get_type(fyn) == FYNT_SCALAR && fy_node_get_style(fyn) ==
   --  FYNS_ALIAS), not an exported symbol; Libfyaml.Nodes.Is_Alias
   --  reimplements it the same way as Is_Scalar/Is_Sequence/Is_Mapping.

   function fy_node_get_tag
     (Fyn : Fy_Node; Lenp : access C.size_t) return CS.chars_ptr
     with Import, Convention => C, External_Name => "fy_node_get_tag";

   ------------------------------------
   --  struct fy_mark / token marks  --
   ------------------------------------

   type Fy_Mark is record
      Input_Pos : C.size_t;
      Line      : C.int;
      Column    : C.int;
   end record
     with Convention => C;
   --  Line/Column are 0-index based (confirmed against the header's own
   --  "@line: Line position (0 index based)" and live against a known
   --  fixture) -- unlike Fy_Diag_Error.Line/Column above, which are
   --  1-indexed (confirmed the same way: a 2-line file with a trailing
   --  newline and an unclosed flow sequence reports error line 3,
   --  column 1, matching 1-based counting into the file's implicit
   --  third, empty, EOF line). libfyaml is not internally consistent
   --  between these two error-reporting subsystems; Libfyaml.Nodes.
   --  Location converts to 1-indexed to match Fy_Diag_Error's
   --  convention (and ordinary editor/human expectations) rather than
   --  passing 0-indexed values through.

   type Fy_Mark_Access is access constant Fy_Mark;
   pragma Convention (C, Fy_Mark_Access);

   function fy_node_get_scalar_token (Fyn : Fy_Node) return Fy_Token
     with Import, Convention => C, External_Name => "fy_node_get_scalar_token";
   --  NULL if Fyn is not a scalar node (aliases count as scalars here,
   --  per the header: "if this call is issued on an alias node the
   --  return shall be of an alias token"). Confirmed live: an ordinary
   --  scalar, an empty/omitted scalar ("key:" with nothing after), and
   --  an alias node all return a real token; a mapping/sequence node
   --  returns NULL.

   function fy_token_start_mark (Fyt : Fy_Token) return Fy_Mark_Access
     with Import, Convention => C, External_Name => "fy_token_start_mark";
   --  NULL is documented as possible ("permissable for some token
   --  types to have no start marker because they are without
   --  content") but not observed live for any scalar token case
   --  above -- Libfyaml.Nodes.Has_Location still checks for it rather
   --  than assuming.

   ------------------------
   --  Scalar node access --
   ------------------------

   function fy_node_get_scalar
     (Fyn : Fy_Node; Lenp : access C.size_t) return CS.chars_ptr
     with Import, Convention => C, External_Name => "fy_node_get_scalar";

   function fy_node_create_scalar_copy
     (Fyd : Fy_Document; Data : CS.chars_ptr; Size : C.size_t) return Fy_Node
     with Import, Convention => C, External_Name => "fy_node_create_scalar_copy";

   function fy_node_create_sequence (Fyd : Fy_Document) return Fy_Node
     with Import, Convention => C, External_Name => "fy_node_create_sequence";

   function fy_node_create_mapping (Fyd : Fy_Document) return Fy_Node
     with Import, Convention => C, External_Name => "fy_node_create_mapping";

   ----------------------------
   --  Sequence node access  --
   ----------------------------

   function fy_node_sequence_item_count (Fyn : Fy_Node) return C.int
     with Import, Convention => C, External_Name => "fy_node_sequence_item_count";

   function fy_node_sequence_get_by_index
     (Fyn : Fy_Node; Index : C.int) return Fy_Node
     with Import, Convention => C, External_Name => "fy_node_sequence_get_by_index";

   function fy_node_sequence_append
     (Fyn_Seq : Fy_Node; Fyn : Fy_Node) return C.int
     with Import, Convention => C, External_Name => "fy_node_sequence_append";

   function fy_node_sequence_iterate
     (Fyn : Fy_Node; Prevp : access System.Address) return Fy_Node
     with Import, Convention => C, External_Name => "fy_node_sequence_iterate";

   ----------------------------
   --  Mapping node access   --
   ----------------------------

   function fy_node_mapping_item_count (Fyn : Fy_Node) return C.int
     with Import, Convention => C, External_Name => "fy_node_mapping_item_count";

   function fy_node_mapping_lookup_value_by_string
     (Fyn : Fy_Node; Key : CS.chars_ptr; Len : C.size_t) return Fy_Node
     with Import, Convention => C, External_Name => "fy_node_mapping_lookup_value_by_string";

   function fy_node_mapping_append
     (Fyn_Map : Fy_Node; Fyn_Key : Fy_Node; Fyn_Value : Fy_Node) return C.int
     with Import, Convention => C, External_Name => "fy_node_mapping_append";

   function fy_node_mapping_iterate
     (Fyn : Fy_Node; Prevp : access System.Address) return Fy_Node_Pair
     with Import, Convention => C, External_Name => "fy_node_mapping_iterate";

   function fy_node_pair_key (Fynp : Fy_Node_Pair) return Fy_Node
     with Import, Convention => C, External_Name => "fy_node_pair_key";

   function fy_node_pair_value (Fynp : Fy_Node_Pair) return Fy_Node
     with Import, Convention => C, External_Name => "fy_node_pair_value";

   -----------------
   --  Path access --
   -----------------

   function fy_node_by_path
     (Fyn   : Fy_Node;
      Path  : CS.chars_ptr;
      Len   : C.size_t;
      Flags : C.unsigned) return Fy_Node
     with Import, Convention => C, External_Name => "fy_node_by_path";

   ------------
   --  Emit  --
   ------------

   function fy_emit_document_to_string
     (Fyd : Fy_Document; Flags : C.unsigned) return CS.chars_ptr
     with Import, Convention => C, External_Name => "fy_emit_document_to_string";

   function fy_emit_document_to_file
     (Fyd : Fy_Document; Flags : C.unsigned; Filename : CS.chars_ptr) return C.int
     with Import, Convention => C, External_Name => "fy_emit_document_to_file";

   ------------
   --  Diag  --
   ------------

   function fy_diag_create (Cfg : System.Address) return Fy_Diag
     with Import, Convention => C, External_Name => "fy_diag_create";

   procedure fy_diag_destroy (Diag : Fy_Diag)
     with Import, Convention => C, External_Name => "fy_diag_destroy";

   procedure fy_diag_set_collect_errors
     (Diag : Fy_Diag; Collect_Errors : C.C_bool)
     with Import, Convention => C, External_Name => "fy_diag_set_collect_errors";

   function fy_diag_got_error (Diag : Fy_Diag) return C.C_bool
     with Import, Convention => C, External_Name => "fy_diag_got_error";

   function fy_diag_errors_iterate
     (Diag : Fy_Diag; Prevp : access System.Address) return Fy_Diag_Error_Access
     with Import, Convention => C, External_Name => "fy_diag_errors_iterate";

   ------------------------------
   --  libc helper (ownership) --
   ------------------------------

   procedure C_Free (Ptr : CS.chars_ptr)
     with Import, Convention => C, External_Name => "free";

end Libfyaml.Thin;
