--  Libfyaml - Ada binding to libfyaml's core parser/emitter/document API
--
--  This binding covers the classic "core" layer of libfyaml (event-driven
--  parsing, the document tree, path queries, and emission) as used by
--  examples/quick-start.c and examples/basic-parsing.c. It intentionally
--  does not cover:
--
--    * the generics layer (fy_generic): its ergonomic constructors
--      (fy_mapping(...), fy_sequence(...), fy_value(...)) are C11
--      _Generic/variadic macros with no C-callable equivalent to bind;
--    * the reflection layer: typed YAML <-> C struct serdes driven by
--      libclang or packed metadata, which doesn't have an Ada-struct
--      analogue to target;
--    * scanf/printf-style variadic entry points (fy_document_scanf,
--      fy_node_buildf, ...), which Ada cannot call generically either.
--
--  See Libfyaml.Documents and Libfyaml.Nodes for the idiomatic Ada API,
--  and Libfyaml.Thin for the underlying 1:1 C import layer.

package Libfyaml is

   Parse_Error : exception;
   --  Raised when a document fails to parse. The exception message carries
   --  the collected libfyaml diagnostic text (file:line:column: message),
   --  one entry per line, when available.

   Emit_Error : exception;
   --  Raised when emitting a document to a string or file fails.

   Missing_Key : exception;
   --  Raised by a required Libfyaml.Nodes typed accessor (Map, Key) form
   --  when Map has no such key.

   Data_Error : exception;
   --  Raised by a Libfyaml.Nodes typed accessor when a scalar is present
   --  but cannot be resolved as the requested type (e.g. Integer_Value
   --  on a node holding "banana").

   Resolve_Error : exception;
   --  Raised by Libfyaml.Documents.Resolve when resolving anchors,
   --  aliases, and merge keys fails (e.g. a merge-key cycle).

end Libfyaml;
