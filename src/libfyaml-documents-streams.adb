with Interfaces.C;
with System;

package body Libfyaml.Documents.Streams is

   package C renames Interfaces.C;
   package CS renames Interfaces.C.Strings;

   use type C.int;
   use type CS.chars_ptr;
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
      return Document_Stream'
        (Ada.Finalization.Limited_Controlled with
           Handle => Fyp, Diag => Diag, Owned_Buffer => C_Text,
           Pending => Thin.Null_Fy_Document, Peeked => False);
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
      --  transfers to the stream (Owned_Buffer), freed in Finalize,
      --  same as Open_String's text buffer above.
      return Document_Stream'
        (Ada.Finalization.Limited_Controlled with
           Handle => Fyp, Diag => Diag, Owned_Buffer => C_Path,
           Pending => Thin.Null_Fy_Document, Peeked => False);
   end Open_File;

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
            Text : constant String := Libfyaml.Documents.Collected_Errors (Stream.Diag);
         begin
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
      return Document'(Ada.Finalization.Limited_Controlled with
                          Handle => Fyd, Owned_Buffer => <>);
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
      if Stream.Owned_Buffer /= CS.Null_Ptr then
         CS.Free (Stream.Owned_Buffer);
      end if;
   end Finalize;

end Libfyaml.Documents.Streams;
