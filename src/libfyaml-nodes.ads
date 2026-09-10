--  Libfyaml.Nodes - a non-owning handle onto a node in a parsed or
--  in-progress-of-being-built YAML document tree.
--
--  Node values are cheap, non-owning handles: they stay valid for as long
--  as the owning Libfyaml.Documents.Document is alive, and are invalidated
--  by Finalize on that document. Nodes are created either by parsing
--  (Libfyaml.Documents.Root and the lookup/navigation functions below) or
--  by explicit construction (Libfyaml.Documents.Create_Scalar / _Sequence /
--  _Mapping), and are attached into the tree with Append / Append_Pair /
--  Libfyaml.Documents.Set_Root / Insert_At.
--
--  That one rule ("valid as long as its Document is") is the whole
--  lifetime contract a caller needs -- deliberately, not as a
--  simplification that glosses over something. libfyaml's core layer
--  is zero-copy wherever it can be: a Scalar_Value/Tag reading back a
--  plain (unquoted, unescaped) scalar or a raw tag is a `const char *`
--  + length span directly into whatever buffer holds the original
--  source text, not a copy -- for a scalar built from an escaped or
--  quoted source, or a block scalar, libfyaml does copy, since the
--  decoded value can't be represented as a plain span of the source
--  bytes (see Libfyaml.Documents.Create_Scalar's own doc comment for
--  the analogous copying-vs-not distinction at construction time).
--  Rather than expose that copied-or-not distinction to callers as
--  something they need to reason about per accessor, this binding
--  keeps every input buffer a Node's data might reference alive for
--  exactly as long as any Document could still need it -- regardless
--  of which of Parse_String, Parse_File, Libfyaml.Documents.Streams.
--  Document_Stream.Open_String, or ...Open_File produced that
--  Document. Confirmed live (and fixed) that this used to fail in one
--  specific case: a Document drawn from Document_Stream.Next, from a
--  stream opened via Open_String, shared its scalars' backing buffer
--  with the *stream* rather than owning a reference to it itself --
--  destroying the stream while such a Document was still in use was
--  a genuine (silent, no crash) use-after-free. Fixed by giving the
--  buffer a small reference count (Buffer_Ref, in Libfyaml.Documents'
--  private part) shared between the stream and every Document drawn
--  from it, freed only once the last holder is gone -- see PLAN.md's
--  "Document_Stream buffer lifetime" section for the full writeup.

with Libfyaml.Thin;

package Libfyaml.Nodes is

   type Node is tagged private;

   Null_Node : constant Node;
   --  The "no node" handle: returned by lookups that find nothing, and by
   --  Libfyaml.Documents.Root on a document with no root node yet.

   function Is_Valid (N : Node) return Boolean;
   --  True unless N is Null_Node.

   type Node_Kind is (Scalar_Node, Sequence_Node, Mapping_Node);

   function Kind (N : Node) return Node_Kind
     with Pre => Is_Valid (N);

   function Is_Scalar (N : Node) return Boolean
     with Pre => Is_Valid (N);
   function Is_Sequence (N : Node) return Boolean
     with Pre => Is_Valid (N);
   function Is_Mapping (N : Node) return Boolean
     with Pre => Is_Valid (N);
   function Is_Null_Value (N : Node) return Boolean
     with Pre => Is_Valid (N);
   --  True if N is an empty/omitted scalar (e.g. "key:" with nothing
   --  after it -- libfyaml's core layer resolves this case, since it's
   --  unambiguous at the grammar level) OR a scalar whose text is one
   --  of the YAML 1.2 core schema null spellings (~, null, Null, NULL).
   --  The latter is resolved here, in Ada, the same way as the other
   --  typed-scalar accessors below -- libfyaml's core layer does not
   --  resolve it (a quoted "" is a deliberate empty *string*, not
   --  null, and libfyaml's own empty-scalar check already handles the
   --  unquoted-omitted case correctly, so text equal to "" is
   --  deliberately not treated as a null spelling here).

   --------------------------
   --  Scalar node access  --
   --------------------------

   function Scalar_Value (N : Node) return String
     with Pre => Is_Valid (N) and then Is_Scalar (N);
   --  The decoded scalar text (quotes/escapes already resolved).

   -----------------------------
   --  Source location        --
   -----------------------------

   type Node_Location is record
      Line   : Positive;
      Column : Positive;
   end record;
   --  1-indexed, matching Libfyaml.Parse_Error's own message
   --  convention (and ordinary editor/human expectations) -- not
   --  libfyaml's own 0-indexed struct fy_mark, which this converts
   --  from. See the note on Fy_Mark in Libfyaml.Thin.

   function Has_Location (N : Node) return Boolean
     with Pre => Is_Valid (N) and then Is_Scalar (N);
   --  True if N's scalar token carries a start location. Confirmed
   --  True live for an ordinary scalar, an empty/omitted scalar
   --  ("key:" with nothing after), and an alias node; libfyaml's own
   --  header allows for a token with none ("permissable for some
   --  token types to have no start marker"), so this is still a real
   --  check, not a formality -- call it before Location rather than
   --  assuming.
   --
   --  Also True, surprisingly, for a Node built via
   --  Libfyaml.Documents.Create_Scalar rather than parsed -- confirmed
   --  live: its token carries a synthetic all-zero mark (Location
   --  (1, 1) after the 1-indexing conversion below), not a NULL one.
   --  Has_Location alone cannot tell "genuinely parsed at (1, 1)"
   --  apart from "freshly built, no real location" -- if that
   --  distinction matters to a caller, they need another way to know
   --  whether N came from parsing.

   function Location (N : Node) return Node_Location
     with Pre => Is_Valid (N) and then Is_Scalar (N) and then Has_Location (N);
   --  The start position of N's own scalar text in the source input
   --  (not, for an alias node, the position of the `*` sigil before
   --  it -- confirmed live that the token's own span starts at the
   --  anchor-name text). See the Has_Location note above for the
   --  freshly-built-node case -- (1, 1) does not by itself mean N was
   --  parsed from line 1, column 1 of real input.

   ----------------------------------
   --  Typed scalar node access    --
   ----------------------------------
   --
   --  libfyaml's core layer (the layer this binding covers) hands back
   --  scalars as plain text; it does not implicitly resolve "8" to an
   --  integer or "true" to a boolean the way, e.g., a YAML library with
   --  a schema-aware loader would. The functions below do that
   --  resolution on the Ada side, following YAML 1.2's core schema
   --  (https://yaml.org/spec/1.2.2/#103-core-schema): null (already
   --  covered by Is_Null_Value above), bool, int, and float. See the
   --  package body for the exact grammar accepted by each.

   function Is_Integer (N : Node) return Boolean
     with Pre => Is_Valid (N) and then Is_Scalar (N);
   function Is_Float (N : Node) return Boolean
     with Pre => Is_Valid (N) and then Is_Scalar (N);
   function Is_Boolean (N : Node) return Boolean
     with Pre => Is_Valid (N) and then Is_Scalar (N);
   --  Non-raising shape predicates, e.g. for deciding whether a list
   --  element is a plain string or some other scalar shape before
   --  committing to a conversion.

   function Integer_Value (N : Node) return Integer
     with Pre => Is_Valid (N) and then Is_Scalar (N);
   function Long_Integer_Value (N : Node) return Long_Integer
     with Pre => Is_Valid (N) and then Is_Scalar (N);
   function Long_Long_Integer_Value (N : Node) return Long_Long_Integer
     with Pre => Is_Valid (N) and then Is_Scalar (N);
   function Float_Value (N : Node) return Float
     with Pre => Is_Valid (N) and then Is_Scalar (N);
   function Long_Float_Value (N : Node) return Long_Float
     with Pre => Is_Valid (N) and then Is_Scalar (N);
   function Boolean_Value (N : Node) return Boolean
     with Pre => Is_Valid (N) and then Is_Scalar (N);
   --  Raise Libfyaml.Data_Error if the scalar text doesn't match the
   --  target type's grammar (including numeric-literal overflow for
   --  the integer/float forms).

   ----------------------------
   --  Sequence node access  --
   ----------------------------

   function Length (N : Node) return Natural
     with Pre => Is_Valid (N) and then (Is_Sequence (N) or else Is_Mapping (N));
   --  Item count of a sequence, or pair count of a mapping.

   function Item (N : Node; Index : Positive) return Node
     with Pre => Is_Valid (N) and then Is_Sequence (N);
   --  1-based access to a sequence item. Index is ordinarily in
   --  1 .. Length (N); if it exceeds Length (N), this returns Null_Node
   --  rather than raising (libfyaml's own out-of-range behavior for this
   --  lookup, passed through as-is).

   procedure Append (Seq : Node; Item : Node)
     with Pre => Is_Valid (Seq) and then Is_Sequence (Seq) and then Is_Valid (Item);
   --  Append Item (typically freshly built via Libfyaml.Documents.Create_*)
   --  to the end of the Seq sequence. Unlike
   --  Libfyaml.Documents.Insert_At, Item is attached outright, not
   --  merged: fy_node_sequence_append's own header documents no unref of
   --  it -- Item remains valid and reads back exactly what was built.

   procedure Iterate
     (Seq : Node; Visit : not null access procedure (Element : Node))
     with Pre => Is_Valid (Seq) and then Is_Sequence (Seq);
   --  Visit is an anonymous access-to-subprogram parameter (rather than a
   --  named access type) specifically so ordinary nested/local procedures
   --  can be passed directly, with no accessibility-level restriction.

   ----------------------------
   --  Mapping node access   --
   ----------------------------

   function Value (Map : Node; Key : String) return Node
     with Pre => Is_Valid (Map) and then Is_Mapping (Map);
   --  The value associated with the string-scalar key Key, or Null_Node
   --  if the mapping has no such key.

   function Has_Key (Map : Node; Key : String) return Boolean
     with Pre => Is_Valid (Map) and then Is_Mapping (Map);

   procedure Append_Pair (Map : Node; Key : Node; Value : Node)
     with Pre => Is_Valid (Map) and then Is_Mapping (Map)
       and then Is_Valid (Key) and then Is_Valid (Value);
   --  Append a (Key, Value) pair, typically freshly built via
   --  Libfyaml.Documents.Create_*, to the end of the Map mapping. Unlike
   --  Libfyaml.Documents.Insert_At, Key and Value are attached outright,
   --  not merged: fy_node_mapping_append's own header documents no unref
   --  of either -- both remain valid and read back exactly what was
   --  built.

   procedure Iterate
     (Map : Node; Visit : not null access procedure (Key, Value : Node))
     with Pre => Is_Valid (Map) and then Is_Mapping (Map);

   ----------------------------
   --  Typed mapping access  --
   ----------------------------
   --
   --  Collapses Value (Map, Key) + a typed accessor above into one call,
   --  with the "required" / "optional with default" split a real caller
   --  needs: a missing key and a malformed value are different failure
   --  modes, so an optional field's Default only substitutes for
   --  *absence* -- if Key is present but its text can't be resolved as
   --  the target type, Libfyaml.Data_Error is still raised.

   function Required (Map : Node; Key : String) return Node
     with Pre => Is_Valid (Map) and then Is_Mapping (Map);
   --  Like Value, but raises Libfyaml.Missing_Key instead of returning
   --  Null_Node when Map has no such Key.

   --  Required forms: raise Libfyaml.Missing_Key if Key is absent,
   --  Libfyaml.Data_Error if present but not resolvable as the target
   --  type.
   function Integer_Value (Map : Node; Key : String) return Integer
     with Pre => Is_Valid (Map) and then Is_Mapping (Map);
   function Long_Integer_Value (Map : Node; Key : String) return Long_Integer
     with Pre => Is_Valid (Map) and then Is_Mapping (Map);
   function Long_Long_Integer_Value
     (Map : Node; Key : String) return Long_Long_Integer
     with Pre => Is_Valid (Map) and then Is_Mapping (Map);
   function Float_Value (Map : Node; Key : String) return Float
     with Pre => Is_Valid (Map) and then Is_Mapping (Map);
   function Long_Float_Value (Map : Node; Key : String) return Long_Float
     with Pre => Is_Valid (Map) and then Is_Mapping (Map);
   function Boolean_Value (Map : Node; Key : String) return Boolean
     with Pre => Is_Valid (Map) and then Is_Mapping (Map);
   function String_Value (Map : Node; Key : String) return String
     with Pre => Is_Valid (Map) and then Is_Mapping (Map);

   --  Optional forms: Default is returned when Key is absent.
   function Integer_Value
     (Map : Node; Key : String; Default : Integer) return Integer
     with Pre => Is_Valid (Map) and then Is_Mapping (Map);
   function Long_Integer_Value
     (Map : Node; Key : String; Default : Long_Integer) return Long_Integer
     with Pre => Is_Valid (Map) and then Is_Mapping (Map);
   function Long_Long_Integer_Value
     (Map : Node; Key : String; Default : Long_Long_Integer)
      return Long_Long_Integer
     with Pre => Is_Valid (Map) and then Is_Mapping (Map);
   function Float_Value
     (Map : Node; Key : String; Default : Float) return Float
     with Pre => Is_Valid (Map) and then Is_Mapping (Map);
   function Long_Float_Value
     (Map : Node; Key : String; Default : Long_Float) return Long_Float
     with Pre => Is_Valid (Map) and then Is_Mapping (Map);
   function Boolean_Value
     (Map : Node; Key : String; Default : Boolean) return Boolean
     with Pre => Is_Valid (Map) and then Is_Mapping (Map);
   function String_Value
     (Map : Node; Key : String; Default : String) return String
     with Pre => Is_Valid (Map) and then Is_Mapping (Map);

   -----------------
   --  Path access --
   -----------------

   function By_Path (N : Node; Path : String) return Node
     with Pre => Is_Valid (N);
   --  Look up a descendant node by libfyaml's native path syntax, e.g.
   --  "/server/port". Returns Null_Node if the path cannot be resolved.

   function Path (N : Node) return String
     with Pre => Is_Valid (N);
   --  N's own path address relative to the document root, in the same
   --  syntax By_Path accepts (e.g. "/0/abilities/2") -- the inverse of
   --  By_Path. Unlike Location below, this works on a node of any
   --  kind, mapping/sequence included, not just scalars: a mapping
   --  item missing a required key has no node/token to report a
   --  Location for, but its own Path is always available and, paired
   --  with the missing key's name, unambiguously identifies where the
   --  problem is. The document root's own Path is "/" (confirmed
   --  live -- see the note on Fy_Mark's neighbor, fy_node_get_path,
   --  in Libfyaml.Thin for why this doesn't return "" instead, despite
   --  what the C header itself claims).

   -----------------------------------
   --  Anchors, aliases, and tags   --
   -----------------------------------

   function Is_Alias (N : Node) return Boolean
     with Pre => Is_Valid (N);
   --  True if N is an unresolved alias reference (*foo): a scalar-typed
   --  node whose style is FYNS_ALIAS, per libfyaml's own
   --  fy_node_is_alias (a "static inline" C header wrapper around
   --  fy_node_get_type/fy_node_get_style, not an exported symbol --
   --  reimplemented here the same way as Is_Scalar/Is_Sequence/
   --  Is_Mapping). Calling Scalar_Value on such a node returns the
   --  alias's own anchor-name text (e.g. "foo"), not the referenced
   --  content -- resolve it first, via the Resolve_Anchors parameter
   --  on Libfyaml.Documents.Parse_String/Parse_File or an explicit
   --  Libfyaml.Documents.Resolve call, to get the referenced content
   --  in its place instead.

   function Tag (N : Node) return String
     with Pre => Is_Valid (N);
   --  N's raw explicit YAML tag text (e.g. "tag:yaml.org,2002:str", or
   --  a custom "!mytag"), or "" if N has no explicit tag.

   ----------------------------------------------------------
   --  Binding-internal: bridges to/from the Thin C handle. --
   --  Used by Libfyaml.Documents; not needed by ordinary   --
   --  callers of this package.                             --
   ----------------------------------------------------------

   function Wrap (Handle : Thin.Fy_Node) return Node;
   function Raw (N : Node) return Thin.Fy_Node;

private

   type Node is tagged record
      Handle : Thin.Fy_Node := Thin.Null_Fy_Node;
   end record;

   Null_Node : constant Node := (Handle => Thin.Null_Fy_Node);

   function Wrap (Handle : Thin.Fy_Node) return Node is (Node'(Handle => Handle));
   function Raw (N : Node) return Thin.Fy_Node is (N.Handle);

end Libfyaml.Nodes;
