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
   --  True if N is the scalar YAML/JSON null (~, null, Null, NULL).

   --------------------------
   --  Scalar node access  --
   --------------------------

   function Scalar_Value (N : Node) return String
     with Pre => Is_Valid (N) and then Is_Scalar (N);
   --  The decoded scalar text (quotes/escapes already resolved).

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
