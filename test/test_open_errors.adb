--  A file that can't be opened raises Ada.IO_Exceptions.Name_Error or
--  Use_Error with the OS's reason, from Parse_File and from
--  Document_Stream.Open_File, rather than a Libfyaml.Parse_Error with
--  none (libfyaml opens the file only when it starts parsing, and
--  reports a failure to open it as a parse failure). And the Name
--  given to Parse_String or Open_String is what parse errors in
--  string input are reported against.

with Ada.Exceptions;
with Ada.IO_Exceptions;
with Ada.Text_IO;
with Libfyaml;
with Libfyaml.Documents;
with Libfyaml.Documents.Streams;

procedure Test_Open_Errors is

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

   type Opener is (Parse_File, Open_File);

   --  Open Path with How, and return the name and message of the
   --  exception that raised, or "none".
   function Open_Result (How : Opener; Path : String) return String is
   begin
      case How is
         when Parse_File =>
            declare
               Unused : Doc.Document := Doc.Parse_File (Path);
               pragma Unreferenced (Unused);
            begin
               null;
            end;
         when Open_File =>
            declare
               Unused : Streams.Document_Stream := Streams.Open_File (Path);
               pragma Unreferenced (Unused);
            begin
               null;
            end;
      end case;
      return "none";
   exception
      when E : others =>
         return Ada.Exceptions.Exception_Name (E) & ": " &
           Ada.Exceptions.Exception_Message (E);
   end Open_Result;

   procedure Check_Open
     (How : Opener; Path : String; Id : Ada.Exceptions.Exception_Id; Message : String)
   is
      Want : constant String := Ada.Exceptions.Exception_Name (Id) & ": " & Message;
      Got  : constant String := Open_Result (How, Path);
   begin
      Check (How'Image & " (""" & Path & """) raises " & Want, Got = Want);
      if Got /= Want then
         Ada.Text_IO.Put_Line ("    got " & Got);
      end if;
   end Check_Open;

   --  Parse Text with Parse_String (or a stream from Open_String, if
   --  Stream) named Name, and return the Parse_Error message.
   function String_Error (Text, Name : String; Stream : Boolean) return String is
   begin
      if Stream then
         declare
            S : Streams.Document_Stream := Streams.Open_String (Text, Name => Name);
         begin
            while Streams.Has_Next (S) loop
               declare
                  Unused : Doc.Document := Streams.Next (S);
                  pragma Unreferenced (Unused);
               begin
                  null;
               end;
            end loop;
         end;
      else
         declare
            Unused : Doc.Document := Doc.Parse_String (Text, Name => Name);
            pragma Unreferenced (Unused);
         begin
            null;
         end;
      end if;
      return "no error";
   exception
      when E : Libfyaml.Parse_Error =>
         return Ada.Exceptions.Exception_Message (E);
   end String_Error;

begin
   for How in Opener loop
      Check_Open (How, "nosuch.yaml", Ada.IO_Exceptions.Name_Error'Identity,
                  "nosuch.yaml: No such file or directory");
      Check_Open (How, "nosuch/x.yaml", Ada.IO_Exceptions.Name_Error'Identity,
                  "nosuch/x.yaml: No such file or directory");
      Check_Open (How, "obj", Ada.IO_Exceptions.Use_Error'Identity,
                  "obj: Is a directory");
      Check_Open (How, "", Ada.IO_Exceptions.Name_Error'Identity,
                  "no file name given");
      Check (How'Image & " of a readable file raises nothing",
             Open_Result (How, "config.yaml") = "none");
   end loop;

   --  A malformed file is still a parse error, naming the file.
   Check ("Parse_File of malformed input still raises Parse_Error",
          Has_Prefix (Open_Result (Parse_File, "malformed.yaml"),
                      "LIBFYAML.PARSE_ERROR: malformed.yaml:"));

   Check ("Parse_String with a Name reports errors against it",
          Has_Prefix (String_Error ("- [a" & ASCII.LF, "<stdin>", False),
                      "<stdin>:2:1: error: "));
   Check ("Parse_String with no Name still says (string-in-memory)",
          Has_Prefix (String_Error ("- [a" & ASCII.LF, "", False),
                      "(string-in-memory):2:1: error: "));
   Check ("Open_String with a Name reports errors against it",
          Has_Prefix (String_Error ("- [a" & ASCII.LF, "<stdin>", True),
                      "<stdin>:2:1: error: "));
   Check ("Open_String with no Name still says (string-in-memory)",
          Has_Prefix (String_Error ("- [a" & ASCII.LF, "", True),
                      "(string-in-memory):2:1: error: "));

   Ada.Text_IO.New_Line;
   if Failures = 0 then
      Ada.Text_IO.Put_Line ("All checks passed.");
   else
      Ada.Text_IO.Put_Line (Failures'Image & " check(s) failed.");
   end if;
end Test_Open_Errors;
