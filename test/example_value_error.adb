--  Example: parse a YAML file that is syntactically fine but has a
--  malformed value for a typed field, and report it in gcc's own
--  diagnostic format: "file:line:column: error: message".
--
--  Unlike a syntax error (example_syntax_error.adb), there IS a
--  parsed tree here -- the document parses fine; it's a specific
--  Node's content that's the wrong shape. Libfyaml.Data_Error's own
--  message (from the typed accessor, e.g. Integer_Value) carries only
--  the offending text, no location -- this is exactly the motivating
--  case for Libfyaml.Nodes.Location (see 000-todo.org's "Add
--  source-location access" entry): look up the Node *before* calling
--  the typed accessor on it, so its Location is still in scope to
--  report alongside Data_Error's message if that call fails.
--
--  Shows the same malformed value parsed two ways -- from a file
--  (Parse_File) and from an in-memory string (Parse_String) -- to
--  make the one real difference between them obvious: the "file"
--  field. Unlike the syntax-error case (example_syntax_error.adb),
--  Libfyaml.Nodes.Location has no file component at all -- it is
--  purely (Line, Column), the same either way (confirmed live) --
--  there is no library-supplied override to fall back on here;
--  "(string-in-memory)" below is this example's own choice of label
--  for the string case, not something Location or Data_Error hands
--  back.
--
--  Run as: ./example_value_error [file]  (defaults to value_error.yaml)

with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Libfyaml;
with Libfyaml.Documents;
with Libfyaml.Nodes;

procedure Example_Value_Error is

   package Doc renames Libfyaml.Documents;
   package Nod renames Libfyaml.Nodes;

   Input_File : constant String :=
     (if Ada.Command_Line.Argument_Count >= 1
      then Ada.Command_Line.Argument (1)
      else "value_error.yaml");

   --  Matches value_error.yaml's own content exactly, so both cases
   --  below report the same line/column for the same malformed
   --  value -- only the "file" label differs.
   Malformed_Text : constant String :=
     "name: widget" & ASCII.LF & "count: banana" & ASCII.LF;

   Saw_Error : Boolean := False;

   function Trimmed (N : Positive) return String is
     (Ada.Strings.Fixed.Trim (N'Image, Ada.Strings.Left));

   --  Report a Data_Error caught on N in gcc format, falling back to
   --  just "label: error: message" if N has no location (e.g. it was
   --  built via Libfyaml.Documents.Create_Scalar rather than parsed).
   procedure Report (File_Label : String; N : Nod.Node; Message : String) is
   begin
      if N.Has_Location then
         declare
            L : constant Nod.Node_Location := N.Location;
         begin
            Ada.Text_IO.Put_Line
              (File_Label & ":" & Trimmed (L.Line) & ":" & Trimmed (L.Column) &
               ": error: " & Message);
         end;
      else
         Ada.Text_IO.Put_Line (File_Label & ": error: " & Message);
      end if;
   end Report;

   --  Look up "/count" in D, report and record failure if it's
   --  missing or malformed, using File_Label to report it.
   procedure Check_Count (File_Label : String; D : Doc.Document) is
      Count : constant Nod.Node := D.Root.By_Path ("/count");
   begin
      if not Count.Is_Valid then
         Ada.Text_IO.Put_Line (File_Label & ": no ""count"" key");
         Saw_Error := True;
         return;
      end if;
      declare
         Value : constant Integer := Count.Integer_Value;
      begin
         Ada.Text_IO.Put_Line ("count = " & Value'Image);
      end;
   exception
      --  Count is still in scope here: an exception handler attached
      --  to this block can see its own declarative part's objects,
      --  which is exactly why Count is looked up *before* the call
      --  that might fail, rather than only from inside the handler.
      when E : Libfyaml.Data_Error =>
         Report (File_Label, Count, Ada.Exceptions.Exception_Message (E));
         Saw_Error := True;
   end Check_Count;

begin
   Ada.Text_IO.Put_Line ("=== Parsing from a file ===");
   Check_Count (Input_File, Doc.Parse_File (Input_File));

   Ada.Text_IO.New_Line;
   Ada.Text_IO.Put_Line ("=== Parsing the same text from a string ===");
   Check_Count ("(string-in-memory)", Doc.Parse_String (Malformed_Text));

   if Saw_Error then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Example_Value_Error;
