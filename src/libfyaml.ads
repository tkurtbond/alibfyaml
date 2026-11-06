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
   --  when Map has no such key.  The message starts with Map's path
   --  (Libfyaml.Nodes.Path): `/1/stats/0: missing required key "points"`.

   Data_Error : exception;
   --  Raised by a Libfyaml.Nodes typed accessor when a scalar is present
   --  but cannot be resolved as the requested type (e.g. Integer_Value
   --  on a node holding "banana"), or, in a (Map, Key) form, when the
   --  key's value isn't a scalar.  The message starts with the value's
   --  path, and before that the line and column of the bad scalar (or,
   --  for a value that isn't a scalar, of its key) when it has them:
   --  `5:42: /1/stats/0/points: not a valid integer: "banana"`.  A
   --  node built in memory has none.

   --  Missing_Key and Data_Error messages, then, are
   --  "[LINE:COLUMN: ]PATH: TEXT", PATH starting with '/'.

   function Has_Location (Message : String) return Boolean is
     (Message'Length > 0 and then Message (Message'First) in '0' .. '9');
   --  Message (a Missing_Key or Data_Error message) starts with a
   --  line and column.

   function In_File (File : String; Message : String) return String is
     (if Has_Location (Message) then File & ":" & Message
      else File & ": " & Message);
   --  Message with File before it, gcc-style:
   --  `FILE:5:42: /1/stats/0/points: not a valid integer: "banana"`,
   --  or `FILE: /1/stats/0: missing required key "points"`.

   function Without_Location (Message : String) return String;
   --  Message with any leading "LINE:COLUMN: " removed, for a caller
   --  that reports the location its own way.

   Resolve_Error : exception;
   --  Raised by Libfyaml.Documents.Resolve when resolving anchors,
   --  aliases, and merge keys fails (e.g. a merge-key cycle).

end Libfyaml;
