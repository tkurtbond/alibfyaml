with Interfaces.C;
with Interfaces.C.Strings;
with System;

package body Libfyaml.Documents.Streams is

   package C renames Interfaces.C;
   package CS renames Interfaces.C.Strings;

   use type C.int;
   use type Thin.Fy_Document;
   use type Thin.Fy_Diag;
   use type Thin.Fy_Parser;

   function Open_String (Text : String) return Document_Stream is
      C_Text : CS.chars_ptr := CS.New_String (Text);
      Diag   : constant Thin.Fy_Diag := Thin.fy_diag_create (System.Null_Address);
      Cfg    : aliased Thin.Fy_Parse_Cfg;
      Fyp    : Thin.Fy_Parser;
      Status : C.int;
   begin
      Thin.fy_diag_set_collect_errors (Diag, C.C_bool (True));
      Cfg.Diag := Diag;
      Fyp := Thin.fy_parser_create (Cfg'Access);
      if Fyp = Thin.Null_Fy_Parser then
         Thin.fy_diag_destroy (Diag);
         CS.Free (C_Text);
         raise Libfyaml.Parse_Error with "fy_parser_create failed";
      end if;
      Status := Thin.fy_parser_set_string (Fyp, C_Text, C.size_t (Text'Length));
      if Status /= 0 then
         Thin.fy_parser_destroy (Fyp);
         Thin.fy_diag_destroy (Diag);
         CS.Free (C_Text);
         raise Libfyaml.Parse_Error with "fy_parser_set_string failed";
      end if;
      --  C_Text is NOT freed here: like fy_document_build_from_string,
      --  fy_parser_set_string doesn't copy its input, and it must stay
      --  alive for as long as the parser is (i.e. for every document
      --  drawn from it, not just one) -- see Owned_Buffer in the spec.
      --  Ownership transfers to a fresh Buffer_Ref, count one; Next
      --  gives each Document drawn from this stream a shared copy.
      return Document_Stream'
        (Ada.Finalization.Limited_Controlled with
           Handle => Fyp, Diag => Diag,
           Owned_Buffer => Libfyaml.Documents.Make_Buffer_Ref (C_Text),
           Pending => Thin.Null_Fy_Document, Peeked => False,
           From_String => True);
   end Open_String;

   function Open_File (Path : String) return Document_Stream is
      C_Path : CS.chars_ptr := CS.New_String (Path);
      Diag   : constant Thin.Fy_Diag := Thin.fy_diag_create (System.Null_Address);
      Cfg    : aliased Thin.Fy_Parse_Cfg;
      Fyp    : Thin.Fy_Parser;
      Status : C.int;
   begin
      Thin.fy_diag_set_collect_errors (Diag, C.C_bool (True));
      Cfg.Diag := Diag;
      Fyp := Thin.fy_parser_create (Cfg'Access);
      if Fyp = Thin.Null_Fy_Parser then
         Thin.fy_diag_destroy (Diag);
         CS.Free (C_Path);
         raise Libfyaml.Parse_Error with "fy_parser_create failed";
      end if;
      Status := Thin.fy_parser_set_input_file (Fyp, C_Path);
      if Status /= 0 then
         Thin.fy_parser_destroy (Fyp);
         Thin.fy_diag_destroy (Diag);
         CS.Free (C_Path);
         raise Libfyaml.Parse_Error with
           "fy_parser_set_input_file failed for """ & Path & '"';
      end if;
      --  Unlike fy_document_build_from_file (a one-shot convenience
      --  that presumably reads the file immediately), the doc comment
      --  on fy_parser_set_input_file is explicit: "while the parser is
      --  in use the file[name] must be available" -- confirmed the
      --  hard way, by an actual use-after-free (the file is evidently
      --  opened lazily, per fy_parse_load_document call, using the
      --  filename pointer given here). C_Path is NOT freed: ownership
      --  transfers to a fresh Buffer_Ref (Owned_Buffer), same as
      --  Open_String's text buffer above -- though unlike that case,
      --  no Document ever gets a copy of this one (see From_String
      --  below), so this reference count never exceeds one in
      --  practice.
      return Document_Stream'
        (Ada.Finalization.Limited_Controlled with
           Handle => Fyp, Diag => Diag,
           Owned_Buffer => Libfyaml.Documents.Make_Buffer_Ref (C_Path),
           Pending => Thin.Null_Fy_Document, Peeked => False,
           From_String => False);
   end Open_File;

   --  Swap Stream's Diag for a brand new one. fy_diag_got_error is a
   --  sticky flag and fy_diag_errors_iterate's collected-errors list is
   --  cumulative -- libfyaml never clears either on its own, and there
   --  is no clear-collected-errors call, only fy_diag_reset_error (which
   --  clears the flag but not the stale error text). Since a
   --  Document_Stream keeps one Diag alive for its whole lifetime (see
   --  the Diag field comment in the spec), replacing it after each error
   --  is the only way to stop that error from being misreported against
   --  a later Fetch call -- confirmed live before this fix: every
   --  Has_Next/Next call after a parse error raised Libfyaml.Parse_Error
   --  again, quoting the earlier document's now-stale message, even once
   --  the underlying parser had genuinely reached a clean end of input.
   --
   --  This does NOT make the stream able to resume reading further
   --  documents *past* a malformed one, though -- confirmed separately
   --  that libfyaml's streaming parser cannot resync mid-stream after an
   --  error (fy_parse_load_document keeps returning NULL, and even an
   --  explicit fy_parser_reset does not restore usable input state: it
   --  leaves the parser reporting "out of tokens and failed to produce
   --  anymore"). That is a limitation of libfyaml's public streaming API
   --  itself, not something fixable from this binding. What this fix
   --  does is turn "keeps raising a stale, misleading Parse_Error
   --  forever" into an honest "Has_Next returns False" once the
   --  underlying parser has nothing left to give -- see test_streams.adb.
   procedure Replace_Diag (Stream : in out Document_Stream) is
      New_Diag : constant Thin.Fy_Diag := Thin.fy_diag_create (System.Null_Address);
   begin
      if New_Diag = Thin.Null_Fy_Diag then
         --  Best effort: couldn't allocate a replacement -- leave the
         --  old (now-stale) Diag in place rather than losing diagnostics
         --  entirely. A later Has_Next/Next may misreport as before.
         return;
      end if;
      Thin.fy_diag_set_collect_errors (New_Diag, C.C_bool (True));
      if Thin.fy_parser_set_diag (Stream.Handle, New_Diag) = 0 then
         Thin.fy_diag_destroy (Stream.Diag);
         Stream.Diag := New_Diag;
      else
         Thin.fy_diag_destroy (New_Diag);
      end if;
   end Replace_Diag;

   --  Common to Has_Next and Next: call fy_parse_load_document once,
   --  and turn a NULL result that's actually a parse error (as opposed
   --  to a clean end of stream) into Libfyaml.Parse_Error -- the two
   --  are indistinguishable from the raw NULL alone, only
   --  fy_diag_got_error tells them apart. Kept in one place so
   --  Has_Next's read-ahead and Next's own direct fetch (when called
   --  without Has_Next first) can't drift out of sync on this check.
   function Fetch (Stream : in out Document_Stream) return Thin.Fy_Document is
      Fyd : constant Thin.Fy_Document := Thin.fy_parse_load_document (Stream.Handle);
   begin
      if Fyd = Thin.Null_Fy_Document and then Boolean (Thin.fy_diag_got_error (Stream.Diag))
      then
         declare
            Text : constant String := Libfyaml.Documents.Collected_Errors
              (Stream.Diag,
               (if Stream.From_String then "(string-in-memory)" else ""));
         begin
            Replace_Diag (Stream);
            if Text'Length > 0 then
               raise Libfyaml.Parse_Error with Text;
            else
               raise Libfyaml.Parse_Error with "document failed to parse";
            end if;
         end;
      end if;
      return Fyd;
   end Fetch;

   function Has_Next (Stream : in out Document_Stream) return Boolean is
   begin
      if not Stream.Peeked then
         Stream.Pending := Fetch (Stream);
         Stream.Peeked := True;
      end if;
      return Stream.Pending /= Thin.Null_Fy_Document;
   end Has_Next;

   function Next (Stream : in out Document_Stream) return Document is
      Fyd : Thin.Fy_Document;
   begin
      if Stream.Peeked then
         Fyd := Stream.Pending;
         Stream.Peeked := False;
         Stream.Pending := Thin.Null_Fy_Document;
      else
         Fyd := Fetch (Stream);
      end if;
      if Fyd = Thin.Null_Fy_Document then
         raise Program_Error with
           "Document_Stream.Next: no document available (check Has_Next first)";
      end if;
      --  A stream opened via Open_String backs every Document drawn
      --  from it with the same zero-copy buffer (see Owned_Buffer's
      --  own comment) -- share it here, rather than leaving the
      --  returned Document with none, so it survives the stream
      --  being destroyed first. An Open_File-based stream has no
      --  such hazard (confirmed live), so its Documents get none.
      if Stream.From_String then
         return Document'(Ada.Finalization.Limited_Controlled with
                             Handle => Fyd, Owned_Buffer => Stream.Owned_Buffer);
      else
         return Document'(Ada.Finalization.Limited_Controlled with
                             Handle => Fyd, Owned_Buffer => <>);
      end if;
   end Next;

   overriding procedure Finalize (Stream : in out Document_Stream) is
   begin
      if Stream.Handle /= Thin.Null_Fy_Parser then
         Thin.fy_parser_destroy (Stream.Handle);
         Stream.Handle := Thin.Null_Fy_Parser;
      end if;
      if Stream.Diag /= Thin.Null_Fy_Diag then
         Thin.fy_diag_destroy (Stream.Diag);
         Stream.Diag := Thin.Null_Fy_Diag;
      end if;
      --  Stream.Owned_Buffer is a Buffer_Ref, a controlled component
      --  -- the language finalizes it automatically right after this
      --  procedure body completes. If any Document drawn via Next
      --  still holds a copy (Open_String case), the underlying text
      --  isn't actually freed until that Document is finalized too.
   end Finalize;

end Libfyaml.Documents.Streams;
