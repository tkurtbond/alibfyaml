--  Libfyaml.Documents.Text_IO -- parse a YAML/JSON document out of an
--  already-open Ada.Text_IO.File_Type: an ordinary file the caller opened
--  itself, or one of the standard streams (Ada.Text_IO.Current_Input,
--  Standard_Input, Current_Output as a target for diagnostics, etc.).
--
--  This is a separate child package, rather than an overload living
--  alongside Parse_String/Parse_File in the parent, because it depends on
--  Ada.Text_IO.C_Streams -- a GNAT-specific extension (not portable Ada)
--  used to obtain the C `FILE *` underneath an open File_Type. A consumer
--  who never needs this input source (or who cares about compiler
--  portability) never pays for the dependency by simply not with-ing this
--  package -- the same reasoning that keeps multi-document streaming
--  (Libfyaml.Documents.Streams) in its own child package rather than the
--  parent.

with Ada.Text_IO;

package Libfyaml.Documents.Text_IO is

   function Parse
     (File : Ada.Text_IO.File_Type; Resolve_Anchors : Boolean := True)
      return Document;
   --  Parse File -- already open in In_File mode, positioned wherever the
   --  caller left it -- as a standalone YAML/JSON document. Same "first
   --  document only" semantics as Parse_String/Parse_File (see the note
   --  above Parse_File in the parent package): given input with more than
   --  one "---"-separated document, only the first is parsed. Raises
   --  Libfyaml.Parse_Error on a syntax error, with the same gcc-style
   --  "file:line:column: error: message" formatting Parse_String/Parse_File
   --  use -- the "file" label is whatever name libfyaml itself falls back
   --  to for a FILE*-backed input (confirmed live: the name passed to
   --  Ada.Text_IO.Open/Create if there is one, "<stdin>" for
   --  Standard_Input, or a "<stream-N>" fallback naming the underlying
   --  file descriptor otherwise -- libfyaml's own choice, not something
   --  this binding overrides, since unlike Parse_String's synthetic
   --  memory-address label none of these are actively misleading).
   --
   --  Resolve_Anchors: see Parse_String's own doc comment; same meaning,
   --  same default.
   --
   --  Ownership and lifetime, confirmed against libfyaml's own source
   --  (fy-input.c) rather than assumed from its header comments alone:
   --  a FILE*-backed input is read lazily via fread() into a buffer
   --  libfyaml allocates and owns itself -- unlike Parse_File's mmap of
   --  the whole file, and unlike Parse_String's zero-copy span directly
   --  into the caller's own buffer. The returned Document therefore holds
   --  no reference into anything Ada-owned (Owned_Buffer is never set),
   --  and File need not outlive it. libfyaml does NOT close File's
   --  underlying stream (confirmed: it only frees its own read buffer for
   --  this input kind) -- File remains open (Ada.Text_IO.Is_Open (File)
   --  is still True) when this returns, and closing it afterward is up
   --  to the caller.
   --
   --  Do NOT assume File is left positioned right after the one document
   --  that was parsed, though, and do NOT call Parse a second time on
   --  the same File expecting to get a second document out of it.
   --  Confirmed live: libfyaml's fread()-based reader pulls in whole
   --  chunks (its own internal buffering, independent of and larger
   --  than "one document's worth of bytes"), so for anything short
   --  enough to fit in one chunk -- most real files -- a single Parse
   --  call silently reads the *entire remaining file* out from under
   --  File, leaving it at end-of-file even though only the first
   --  document was actually parsed. A second Parse call on the same
   --  File in that case sees no more bytes at all, not the second
   --  document -- silently, not as an error. There is no way to avoid
   --  this using the one-shot build-from-fp entry point libfyaml
   --  provides (fy_document_build_from_fp): correctly streaming
   --  multiple documents out of one FILE* needs libfyaml's *other*,
   --  persistent-parser API (fy_parser_set_input_fp + repeated
   --  fy_parse_load_document on the same parser, the same shape
   --  Libfyaml.Documents.Streams.Open_File already uses for paths) --
   --  not implemented here; see 000-todo.org.
   --
   --  Treat a File passed to Parse as consumed by the call for any
   --  purpose beyond closing it afterward.

end Libfyaml.Documents.Text_IO;
