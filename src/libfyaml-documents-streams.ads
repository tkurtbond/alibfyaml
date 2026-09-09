--  Libfyaml.Documents.Streams - multi-document YAML streaming, built
--  on libfyaml's separate streaming-parser API (fy_parser_create +
--  repeated fy_parse_load_document calls) rather than the
--  single-document fy_document_build_from_string/_file that
--  Libfyaml.Documents.Parse_String/Parse_File use. Those always mean
--  "parse exactly one document" and are unaffected by this package;
--  use this one instead for input that may hold more than one
--  "---"-separated document.
--
--  A child package, not part of Libfyaml.Documents itself: Ada
--  disallows a subprogram from being a dispatching primitive of two
--  different tagged types declared in the same immediate scope, and
--  Next below needs both Document_Stream (a parameter) and Document
--  (a result) in its profile. Document is declared in the parent,
--  Document_Stream here, so Next is only ever a primitive of
--  Document_Stream -- and being a child, this package still has full
--  visibility of Document's private representation, so Next can build
--  one directly, exactly the way Libfyaml.Documents' own Parse_String/
--  Parse_File do.

with Ada.Finalization;
with Libfyaml.Thin;

package Libfyaml.Documents.Streams is

   type Document_Stream is tagged limited private;

   function Open_String (Text : String) return Document_Stream;
   --  Open Text for streaming; use Has_Next/Next to read documents
   --  from it. Raises Libfyaml.Parse_Error if the parser itself can't
   --  be set up (this is about the *parser*, not any one document --
   --  a syntax error in the first document surfaces from Next/Has_Next,
   --  not here).

   function Open_File (Path : String) return Document_Stream;
   --  Open the file at Path for streaming; use Has_Next/Next to read
   --  documents from it. Raises Libfyaml.Parse_Error if the file can't
   --  be opened.

   function Has_Next (Stream : in out Document_Stream) return Boolean;
   --  True if there is at least one more document to read. "in out"
   --  because there is no side-effect-free way to peek libfyaml's
   --  stream: this may actually read the next document ahead of time,
   --  caching it for Next. May raise Libfyaml.Parse_Error itself, if
   --  that read-ahead is what encounters a malformed document.
   --
   --  Note: libfyaml's streaming parser cannot resync past a malformed
   --  document to reach further ones in the same stream. So after a
   --  Parse_Error (from this call or from Next), a further Has_Next call
   --  does not raise again (that part is fixed: it used to, misreporting
   --  the *next* document as failing too) but also does not find any
   --  more documents even if the underlying input textually contains
   --  more -- it returns False, same as a genuine clean end of stream.
   --  Treat a Document_Stream as exhausted after its first Parse_Error.

   function Next (Stream : in out Document_Stream) return Document
     with Pre => Has_Next (Stream);
   --  Consume and return the next document -- the one Has_Next found,
   --  if it was called first; Next performs its own fetch otherwise
   --  (the precondition is a usage contract, not something Next's
   --  correctness depends on). Raises Libfyaml.Parse_Error if that
   --  document fails to parse -- distinct from Has_Next returning
   --  False (clean end of stream): a parse error partway through the
   --  stream is not silently treated as "no more documents". See the
   --  note on Has_Next above, though: this only distinguishes the
   --  *first* parse error in a stream from a clean end -- once it has
   --  happened, the stream has nothing further to give either way.

private

   type Document_Stream is new Ada.Finalization.Limited_Controlled with record
      Handle       : Thin.Fy_Parser := Thin.Null_Fy_Parser;
      Diag         : Thin.Fy_Diag := Thin.Null_Fy_Diag;
      --  Kept alive for the whole stream (unlike Libfyaml.Documents'
      --  own Parse_Common, which creates and destroys a Diag per
      --  single-document call): Has_Next/Next need it after every
      --  fy_parse_load_document call, to tell a clean end of stream
      --  apart from a parse error -- both return NULL from libfyaml.
      Owned_Buffer : Buffer_Ref;
      --  Set by Open_String (the text) or Open_File (the filename) --
      --  both must stay alive for as long as the parser is in use.
      --  A Buffer_Ref (see Libfyaml.Documents), not a plain
      --  chars_ptr, specifically for the Open_String case: Next
      --  gives every Document drawn from such a stream its own copy
      --  of this same Buffer_Ref (see Next below), since the
      --  underlying text backs their scalars too, not just the
      --  stream's own parsing -- confirmed live with valgrind that a
      --  Document outliving the stream it came from was a genuine
      --  use-after-free before this existed. Open_File's Owned_Buffer
      --  (the filename) is never actually shared with a Document --
      --  confirmed live separately that no such hazard exists there
      --  -- but uses the same type for uniformity.
      Pending      : Thin.Fy_Document := Thin.Null_Fy_Document;
      Peeked       : Boolean := False;
      --  Has_Next's one-ahead read-ahead cache, consumed by Next.
      From_String  : Boolean := False;
      --  Set by Open_String, left False by Open_File: Fetch passes
      --  this to Collected_Errors' File_Override so a Parse_Error
      --  from a string-origin stream reports "(string-in-memory)"
      --  instead of libfyaml's own synthetic, useless
      --  "<memory-@ADDR-ADDR>" filename -- see Libfyaml.Documents.
      --  Parse_String, which has the identical issue for the same
      --  reason (fy_parser_set_string, like
      --  fy_document_build_from_string, has no real filename to
      --  report).
   end record;

   overriding procedure Finalize (Stream : in out Document_Stream);

end Libfyaml.Documents.Streams;
