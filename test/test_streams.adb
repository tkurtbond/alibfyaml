--  Exercises Libfyaml.Documents.Streams.Document_Stream: reading every
--  document out of a multi-document YAML file/string, confirming
--  Parse_File (single-document) only ever sees the first one, and
--  confirming a parse error partway through a stream raises
--  Libfyaml.Parse_Error rather than looking like a clean end of stream.

with Ada.Text_IO;
with Ada.Exceptions;
with Libfyaml;
with Libfyaml.Documents;
with Libfyaml.Documents.Streams;

procedure Test_Streams is

   package Doc renames Libfyaml.Documents;
   package Streams renames Libfyaml.Documents.Streams;

   Failures : Natural := 0;

   function Has_Prefix (S, Prefix : String) return Boolean is
     (S'Length >= Prefix'Length
      and then S (S'First .. S'First + Prefix'Length - 1) = Prefix);

   procedure Check (Label : String; Condition : Boolean) is
   begin
      if Condition then
         Ada.Text_IO.Put_Line ("ok   - " & Label);
      else
         Ada.Text_IO.Put_Line ("FAIL - " & Label);
         Failures := Failures + 1;
      end if;
   end Check;

   --  A Document drawn from an Open_String-based stream, outliving
   --  that stream: the stream (and its Owned_Buffer) is finalized
   --  when this function returns, before the caller ever touches the
   --  returned Document -- confirmed live with valgrind, before the
   --  fix this file's own use motivated, that reading it afterward
   --  was a genuine use-after-free (the Document's scalars are a
   --  zero-copy span directly into the stream's buffer). See
   --  Buffer_Ref in Libfyaml.Documents.
   function Doc_Outliving_Its_Stream return Doc.Document is
      Stream : Streams.Document_Stream := Streams.Open_String ("name: widget");
   begin
      return Streams.Next (Stream);
   end Doc_Outliving_Its_Stream;

begin
   -----------------------------------------------------------------
   --  Parse_File only ever sees the first document of streams.yaml.
   -----------------------------------------------------------------
   declare
      D : constant Doc.Document := Doc.Parse_File ("streams.yaml");
   begin
      Check ("Parse_File sees only the first document",
             D.Root.String_Value ("name") = "first");
   end;

   -----------------------------------------------------------------
   --  Document_Stream reads all three, in order, each a real,
   --  independently usable Document.
   -----------------------------------------------------------------
   declare
      function Expected_Name (N : Positive) return String is
        (case N is
           when 1 => "first",
           when 2 => "second",
           when 3 => "third",
           when others => "?");

      Stream : Streams.Document_Stream := Streams.Open_File ("streams.yaml");
      Count  : Natural := 0;
   begin
      while Streams.Has_Next (Stream) loop
         Count := Count + 1;
         declare
            D : constant Doc.Document := Streams.Next (Stream);
            Name : constant String := D.Root.String_Value ("name");
         begin
            Check
              ("Open_File document" & Count'Image & " name = """ & Name & """",
               Count <= 3 and then Name = Expected_Name (Count));
            Check
              ("Open_File document" & Count'Image & " value = " & Count'Image,
               D.Root.Integer_Value ("value") = Count);
         end;
      end loop;
      Check ("Open_File yielded exactly 3 documents", Count = 3);
      Check ("Has_Next stays False once exhausted", not Streams.Has_Next (Stream));
   end;

   -----------------------------------------------------------------
   --  Same thing via Open_String, to exercise the owned-buffer path.
   -----------------------------------------------------------------
   declare
      Text : constant String :=
        "---" & ASCII.LF & "name: a" & ASCII.LF &
        "---" & ASCII.LF & "name: b" & ASCII.LF;
      Stream : Streams.Document_Stream := Streams.Open_String (Text);
      Count  : Natural := 0;
   begin
      while Streams.Has_Next (Stream) loop
         Count := Count + 1;
         declare
            D : constant Doc.Document := Streams.Next (Stream);
         begin
            Check
              ("Open_String document" & Count'Image,
               D.Root.String_Value ("name") = (if Count = 1 then "a" else "b"));
         end;
      end loop;
      Check ("Open_String yielded exactly 2 documents", Count = 2);
   end;

   -----------------------------------------------------------------
   --  Boundary: an empty stream (no documents at all) reports
   --  Has_Next = False immediately, not an error.
   -----------------------------------------------------------------
   declare
      Stream : Streams.Document_Stream := Streams.Open_String ("");
   begin
      Check ("Open_String ("""") has no documents", not Streams.Has_Next (Stream));
   end;

   -----------------------------------------------------------------
   --  Boundary: a stream containing exactly one document behaves the
   --  same as Parse_String would for that one document, then reports
   --  a clean end.
   -----------------------------------------------------------------
   declare
      Stream : Streams.Document_Stream :=
        Streams.Open_String ("---" & ASCII.LF & "name: only" & ASCII.LF);
      Count  : Natural := 0;
   begin
      while Streams.Has_Next (Stream) loop
         Count := Count + 1;
         declare
            D : constant Doc.Document := Streams.Next (Stream);
         begin
            Check ("single-document stream: document" & Count'Image & " name",
                   D.Root.String_Value ("name") = "only");
         end;
      end loop;
      Check ("single-document stream yielded exactly 1 document", Count = 1);
   end;

   -----------------------------------------------------------------
   --  A parse error partway through a stream must raise
   --  Libfyaml.Parse_Error, not look like a clean end of stream -- and
   --  calling Has_Next *again* afterward must not raise a second, stale
   --  Parse_Error quoting the same old message (fy_diag_got_error is a
   --  sticky flag, and libfyaml has no way to clear its cumulative
   --  collected-errors list; Fetch used to re-raise Parse_Error for
   --  every later Has_Next/Next call as a result -- confirmed live
   --  before this fix). It should instead report a clean end of stream:
   --  libfyaml's streaming parser cannot resync past a malformed
   --  document to reach further ones in the same stream (confirmed
   --  separately -- even an explicit parser reset does not restore
   --  usable input state), so "no more documents" is the honest answer,
   --  not a design goal recovered here -- only the misleading repeated
   --  exception is what this fixes. A third, well-formed document is
   --  included below specifically to prove it's genuinely unreachable
   --  after the error, not just untested.
   -----------------------------------------------------------------
   declare
      Text : constant String :=
        "---" & ASCII.LF & "name: ok" & ASCII.LF &
        "---" & ASCII.LF & "[unterminated flow sequence" & ASCII.LF &
        "---" & ASCII.LF & "name: third" & ASCII.LF;
      Stream : Streams.Document_Stream := Streams.Open_String (Text);
      Saw_First : Boolean := False;
      Raised_Parse_Error : Boolean := False;
      Reports_As_String : Boolean := False;
      Has_Next_After_Error : Boolean := True;
   begin
      if Streams.Has_Next (Stream) then
         declare
            D : constant Doc.Document := Streams.Next (Stream);
         begin
            Saw_First := D.Root.String_Value ("name") = "ok";
         end;
      end if;
      begin
         if Streams.Has_Next (Stream) then
            declare
               Unused : constant Doc.Document := Streams.Next (Stream);
               pragma Unreferenced (Unused);
            begin
               null;
            end;
         end if;
      exception
         when E : Libfyaml.Parse_Error =>
            Raised_Parse_Error := True;
            --  Open_String has no real filename, same as Parse_String
            --  -- confirmed live that libfyaml's own fallback here is
            --  a useless, run-varying "<memory-@ADDR-ADDR>" label;
            --  Document_Stream.Open_String overrides it to the fixed
            --  "(string-in-memory)" the same way Parse_String does.
            Reports_As_String :=
              Has_Prefix (Ada.Exceptions.Exception_Message (E),
                          "(string-in-memory):");
      end;
      Has_Next_After_Error := Streams.Has_Next (Stream);
      Check ("first document of the bad stream still parsed fine", Saw_First);
      Check ("malformed second document -> Parse_Error, not silent end-of-stream",
             Raised_Parse_Error);
      Check ("Open_String's Parse_Error reports ""(string-in-memory)"", " &
             "not libfyaml's own synthetic memory-address label",
             Reports_As_String);
      Check ("Has_Next after the error reports a clean end, not another " &
             "(stale) Parse_Error -- the third, well-formed document is " &
             "genuinely unreachable, but the stream stops honestly instead " &
             "of raising Parse_Error again with the earlier document's " &
             "stale message", not Has_Next_After_Error);
   exception
      when E : others =>
         Ada.Text_IO.Put_Line
           ("FAIL - bad-stream case raised " & Ada.Exceptions.Exception_Name (E) &
            " outside the expected place");
         Failures := Failures + 1;
   end;

   -----------------------------------------------------------------
   --  A Document drawn from Open_String must remain correctly
   --  readable after the Document_Stream it came from is destroyed
   --  -- see Doc_Outliving_Its_Stream's own comment above.
   -----------------------------------------------------------------
   declare
      D : constant Doc.Document := Doc_Outliving_Its_Stream;
   begin
      Check ("a Document drawn from Open_String reads correctly " &
             "after its Document_Stream is destroyed",
             D.Root.String_Value ("name") = "widget");
   end;

   Ada.Text_IO.New_Line;
   if Failures = 0 then
      Ada.Text_IO.Put_Line ("All checks passed.");
   else
      Ada.Text_IO.Put_Line (Integer'Image (Failures) & " check(s) failed.");
   end if;
end Test_Streams;
