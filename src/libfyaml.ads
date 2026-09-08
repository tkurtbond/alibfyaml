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

end Libfyaml;
