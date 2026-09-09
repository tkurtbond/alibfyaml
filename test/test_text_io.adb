--  Exercises Libfyaml.Documents.Text_IO.Parse: building a Document out of
--  an already-open Ada.Text_IO.File_Type, including Current_Input (the
--  Set_Input trick below stands in for genuinely piped Standard_Input,
--  which needs a real OS pipe to exercise -- confirmed separately, live
--  under valgrind, with a throwaway probe piping into a small program via
--  the shell; not kept here since an automated test can't easily supply
--  piped stdin without a wrapper script).
--
--  Also confirms (see the first check below and Text_IO's own doc
--  comment on Parse) that File is not left usably positioned for a
--  second document afterward, even though it stays open -- found live
--  while writing this test, not assumed from any header comment.

with Ada.Exceptions;
with Ada.Text_IO;
with Libfyaml;
with Libfyaml.Documents;
with Libfyaml.Documents.Text_IO;

procedure Test_Text_IO is

   package Doc renames Libfyaml.Documents;
   package TIO renames Libfyaml.Documents.Text_IO;

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

begin
   -----------------------------------------------------------------
   --  Parse the first document out of an ordinary open File_Type --
   --  same "first document only" result Parse_File would give for
   --  the same path. File remains open afterward (libfyaml does not
   --  close it) -- but NOT usably positioned for reading a second
   --  document: confirmed live (see Text_IO's own doc comment on
   --  Parse) that libfyaml's chunked fread()-based reader typically
   --  consumes the *entire* remainder of a file this small in one
   --  internal read, silently past the first document's own bytes.
   --  Not asserting a specific position here as a result -- only
   --  what Parse actually promises: it doesn't close File.
   -----------------------------------------------------------------
   declare
      F : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, "streams.yaml");
      declare
         D : constant Doc.Document := TIO.Parse (F);
      begin
         Check ("Text_IO.Parse sees only the first document",
                D.Root.String_Value ("name") = "first");
      end;
      Check ("File remains open after Parse", Ada.Text_IO.Is_Open (F));
      Ada.Text_IO.Close (F);
   end;

   -----------------------------------------------------------------
   --  Current_Input: the same Parse works on whatever File_Type is
   --  current, not just one passed explicitly -- Ada.Text_IO.
   --  Current_Input is itself just the File_Type last given to
   --  Set_Input, so this genuinely exercises that path without
   --  needing a real piped stdin.
   -----------------------------------------------------------------
   declare
      F : Ada.Text_IO.File_Type;
      Saved_Input : constant Ada.Text_IO.File_Type := Ada.Text_IO.Current_Input;
   begin
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, "config.yaml");
      Ada.Text_IO.Set_Input (F);
      declare
         D : constant Doc.Document := TIO.Parse (Ada.Text_IO.Current_Input);
      begin
         Check ("Text_IO.Parse (Current_Input) reads config.yaml correctly",
                D.Root.By_Path ("/server/port").Scalar_Value = "8080");
      end;
      Ada.Text_IO.Set_Input (Saved_Input);
      Ada.Text_IO.Close (F);
   end;

   -----------------------------------------------------------------
   --  Malformed input via File_Type: Parse_Error, not a process
   --  abort (same double-free class this binding already fixed for
   --  Parse_File/Parse_String -- Text_IO.Parse reuses the same
   --  Parse_Common, so this also guards against a regression there),
   --  with a real filename in the message, not libfyaml's synthetic
   --  stream-name fallback (this binding passes Ada.Text_IO.Name
   --  through as Parse_Common's File_Override).
   -----------------------------------------------------------------
   declare
      F : Ada.Text_IO.File_Type;
      Raised : Boolean := False;
      Reports_Real_Name : Boolean := False;
   begin
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, "malformed.yaml");
      begin
         declare
            Unused : Doc.Document := TIO.Parse (F);
            pragma Unreferenced (Unused);
         begin
            null;
         end;
      exception
         when E : Libfyaml.Parse_Error =>
            Raised := True;
            Reports_Real_Name :=
              Has_Prefix (Ada.Exceptions.Exception_Message (E),
                          Ada.Text_IO.Name (F) & ":");
      end;
      Ada.Text_IO.Close (F);
      Check ("Text_IO.Parse on malformed input raises Parse_Error " &
             "(not a process abort)", Raised);
      Check ("Text_IO.Parse's Parse_Error reports the file's real name",
             Reports_Real_Name);
   end;

   Ada.Text_IO.New_Line;
   if Failures = 0 then
      Ada.Text_IO.Put_Line ("All checks passed.");
   else
      Ada.Text_IO.Put_Line (Integer'Image (Failures) & " check(s) failed.");
   end if;
end Test_Text_IO;
