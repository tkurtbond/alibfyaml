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

   procedure Check (Label : String; Condition : Boolean) is
   begin
      if Condition then
         Ada.Text_IO.Put_Line ("ok   - " & Label);
      else
         Ada.Text_IO.Put_Line ("FAIL - " & Label);
         Failures := Failures + 1;
      end if;
   end Check;

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
   --  A parse error partway through a stream must raise
   --  Libfyaml.Parse_Error, not look like a clean end of stream.
   -----------------------------------------------------------------
   declare
      Text : constant String :=
        "---" & ASCII.LF & "name: ok" & ASCII.LF &
        "---" & ASCII.LF & "[unterminated flow sequence" & ASCII.LF;
      Stream : Streams.Document_Stream := Streams.Open_String (Text);
      Saw_First : Boolean := False;
      Raised_Parse_Error : Boolean := False;
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
         when Libfyaml.Parse_Error =>
            Raised_Parse_Error := True;
      end;
      Check ("first document of the bad stream still parsed fine", Saw_First);
      Check ("malformed second document -> Parse_Error, not silent end-of-stream",
             Raised_Parse_Error);
   exception
      when E : others =>
         Ada.Text_IO.Put_Line
           ("FAIL - bad-stream case raised " & Ada.Exceptions.Exception_Name (E) &
            " outside the expected place");
         Failures := Failures + 1;
   end;

   Ada.Text_IO.New_Line;
   if Failures = 0 then
      Ada.Text_IO.Put_Line ("All checks passed.");
   else
      Ada.Text_IO.Put_Line (Integer'Image (Failures) & " check(s) failed.");
   end if;
end Test_Streams;
