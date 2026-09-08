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
   --  1-based access to a sequence item; Index must be in 1 .. Length (N).

   procedure Append (Seq : Node; Item : Node)
     with Pre => Is_Valid (Seq) and then Is_Sequence (Seq) and then Is_Valid (Item);
   --  Append Item (typically freshly built via Libfyaml.Documents.Create_*)
   --  to the end of the Seq sequence.

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
   --  Libfyaml.Documents.Create_*, to the end of the Map mapping.

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
