--  Example: parse a YAML file that fails to parse at all (a syntax
--  error -- bad indentation, an unclosed bracket, etc.) and report it
--  in gcc's own diagnostic format: "file:line:column: error: message".
--
--  There is no document/tree/Node to query here -- the error is from
--  the parser itself, before any tree exists -- so this uses
--  Libfyaml.Parse_Error's own message directly, not
--  Libfyaml.Nodes.Location (which needs an existing Node from a
--  successfully-parsed tree; see example_value_error.adb for that
--  case instead). Parse_Error's message is already exactly gcc
--  format, one line per collected diagnostic, each already ending in
--  a newline -- see Libfyaml.Documents.Collected_Errors.
--
--  Shows the same malformed YAML text parsed two ways -- from a file
--  (Parse_File) and from an in-memory string (Parse_String) -- to
--  make the one real difference between them obvious: the "file"
--  field. From a file it's the real path; from a string, libfyaml
--  has no real filename to report and (confirmed live) falls back to
--  a synthetic, run-varying "<memory-@ADDR-ADDR>" label -- which
--  Libfyaml.Documents.Parse_String overrides to a fixed
--  "(string-in-memory)" instead. Everything else about the message
--  (line, column, the description) is identical either way, since
--  both parse the exact same bytes.
--
--  Run as: ./example_syntax_error [file]  (defaults to malformed.yaml)

with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Text_IO;
with Libfyaml;
with Libfyaml.Documents;

procedure Example_Syntax_Error is

   package Doc renames Libfyaml.Documents;

   Input_File : constant String :=
     (if Ada.Command_Line.Argument_Count >= 1
      then Ada.Command_Line.Argument (1)
      else "malformed.yaml");

   --  Matches malformed.yaml's own content exactly, so both cases
   --  below report the same line/column for the same underlying
   --  error -- only the "file" field differs.
   Malformed_Text : constant String :=
     "name: widget" & ASCII.LF & "bad: [1, 2" & ASCII.LF;

   Saw_Error : Boolean := False;

begin
   Ada.Text_IO.Put_Line ("=== Parsing from a file ===");
   begin
      declare
         Unused : constant Doc.Document := Doc.Parse_File (Input_File);
         pragma Unreferenced (Unused);
      begin
         Ada.Text_IO.Put_Line (Input_File & " parsed with no errors.");
      end;
   exception
      when E : Libfyaml.Parse_Error =>
         Ada.Text_IO.Put (Ada.Exceptions.Exception_Message (E));
         Saw_Error := True;
   end;

   Ada.Text_IO.New_Line;
   Ada.Text_IO.Put_Line ("=== Parsing the same text from a string ===");
   begin
      declare
         Unused : constant Doc.Document := Doc.Parse_String (Malformed_Text);
         pragma Unreferenced (Unused);
      begin
         Ada.Text_IO.Put_Line ("parsed with no errors.");
      end;
   exception
      when E : Libfyaml.Parse_Error =>
         Ada.Text_IO.Put (Ada.Exceptions.Exception_Message (E));
         Saw_Error := True;
   end;

   if Saw_Error then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Example_Syntax_Error;
