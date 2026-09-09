--  Regression test for a double-free in Libfyaml.Documents.Parse_Common
--  found while investigating source-location access (unrelated work --
--  found live, not by inspection): on a genuine parse failure, the
--  Handle = Null_Fy_Document branch destroyed Diag and then raised
--  Libfyaml.Parse_Error, which the function's own "defense in depth"
--  `when others => Thin.fy_diag_destroy (Diag); raise;` handler then
--  caught and destroyed *again* -- every single call to Parse_File or
--  Parse_String on malformed input hit this, corrupting the heap and
--  aborting the process (glibc's free() catching the double free)
--  instead of Libfyaml.Parse_Error ever reaching the caller. No
--  existing test exercised this: test_streams.adb's Parse_Error checks
--  go through Libfyaml.Documents.Streams, a different code path with a
--  different (and correct) Diag lifecycle, and test_quickstart.adb's
--  Parse_Error handler is only ever reached with valid input in
--  practice. Confirmed fixed live with valgrind (0 errors, all heap
--  blocks freed) for both Parse_File and Parse_String.

with Ada.Exceptions;
with Ada.Text_IO;
with Libfyaml;
with Libfyaml.Documents;

procedure Test_Parse_Errors is

   package Doc renames Libfyaml.Documents;

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
   --  Parse_File on malformed input: raises Parse_Error (not a
   --  process abort), with a non-empty message.
   -----------------------------------------------------------------
   declare
      Raised           : Boolean := False;
      Message_Nonempty : Boolean := False;
   begin
      begin
         declare
            Unused : Doc.Document := Doc.Parse_File ("malformed.yaml");
            pragma Unreferenced (Unused);
         begin
            null;
         end;
      exception
         when E : Libfyaml.Parse_Error =>
            Raised := True;
            Message_Nonempty := Ada.Exceptions.Exception_Message (E)'Length > 0;
      end;
      Check ("Parse_File on malformed input raises Parse_Error " &
             "(not a process abort)", Raised);
      Check ("Parse_File's Parse_Error carries a non-empty message",
             Message_Nonempty);
   end;

   -----------------------------------------------------------------
   --  Parse_String on malformed input: same double-free risk, same
   --  fix, exercised through Parse_Common's other caller.
   --
   --  Also checks the message's "file" field: libfyaml has no real
   --  filename for string input and falls back to a synthetic,
   --  useless "<memory-@ADDR-ADDR>" label (confirmed live) -- this
   --  binding overrides it to the fixed "(string-in-memory)" instead
   --  (Libfyaml.Documents.Parse_String passes that as
   --  Parse_Common's/Collected_Errors' File_Override).
   -----------------------------------------------------------------
   declare
      Raised           : Boolean := False;
      Reports_As_String : Boolean := False;
   begin
      begin
         declare
            Unused : Doc.Document := Doc.Parse_String ("bad: [1, 2");
            pragma Unreferenced (Unused);
         begin
            null;
         end;
      exception
         when E : Libfyaml.Parse_Error =>
            Raised := True;
            Reports_As_String :=
              Has_Prefix (Ada.Exceptions.Exception_Message (E),
                          "(string-in-memory):");
      end;
      Check ("Parse_String on malformed input raises Parse_Error " &
             "(not a process abort)", Raised);
      Check ("Parse_String's Parse_Error reports ""(string-in-memory)"", " &
             "not libfyaml's own synthetic memory-address label",
             Reports_As_String);
   end;

   -----------------------------------------------------------------
   --  A second, independent failure right after the first: Diag is
   --  created and destroyed fresh per call in Parse_Common (unlike
   --  Libfyaml.Documents.Streams, which keeps one Diag alive for a
   --  whole stream), so there is no cross-call state to corrupt --
   --  confirmed rather than assumed.
   -----------------------------------------------------------------
   declare
      Raised : Boolean := False;
   begin
      begin
         declare
            Unused : Doc.Document := Doc.Parse_String ("[1, 2");
            pragma Unreferenced (Unused);
         begin
            null;
         end;
      exception
         when Libfyaml.Parse_Error =>
            Raised := True;
      end;
      Check ("A second, independent parse failure also raises cleanly",
             Raised);
   end;

   -----------------------------------------------------------------
   --  Valid input after two failures still works normally --
   --  confirms the fix didn't leave Parse_Common unable to succeed.
   -----------------------------------------------------------------
   declare
      D : constant Doc.Document := Doc.Parse_String ("ok: 1");
   begin
      Check ("Valid input after failures still parses successfully",
             D.Root.By_Path ("/ok").Scalar_Value = "1");
   end;

   Ada.Text_IO.New_Line;
   if Failures = 0 then
      Ada.Text_IO.Put_Line ("All checks passed.");
   else
      Ada.Text_IO.Put_Line (Integer'Image (Failures) & " check(s) failed.");
   end if;
end Test_Parse_Errors;
