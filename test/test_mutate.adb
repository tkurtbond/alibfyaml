--  Exercises Libfyaml.Documents.Insert_At's handling of the N parameter
--  it takes "in out": libfyaml unconditionally unrefs N, freeing it
--  outright once its reference count hits zero -- on success just as
--  much as on failure for a freshly-built N with no other reference.
--  This binding nulls N out unconditionally to close the resulting
--  use-after-free hazard (confirmed live with valgrind: an earlier
--  version only nulled N on failure, and a "successful" merge left the
--  caller holding a Node pointing at memory libfyaml had already
--  freed).

with Ada.Text_IO;
with Libfyaml;
with Libfyaml.Documents;
with Libfyaml.Nodes;

procedure Test_Mutate is

   package Doc renames Libfyaml.Documents;
   package Nod renames Libfyaml.Nodes;

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
   --  Insert_At replacing an existing scalar with another scalar: N is
   --  unref'ed by libfyaml and, having no other reference, freed --
   --  this binding nulls it out, so N reads back as not valid, while
   --  the new value is reachable at Path.
   --  (Insert_At needs Path to already resolve to something -- it's
   --  "insert/replace at Path", not "create Path from nothing"; see
   --  fy_document_insert_at's own doc.)
   -----------------------------------------------------------------
   declare
      D : Doc.Document := Doc.Parse_String ("greeting: old");
      Fresh : Nod.Node := Doc.Create_Scalar (D, "hello");
   begin
      Doc.Insert_At (D, "/greeting", Fresh);
      Check ("Insert_At replacing a scalar: N is nulled out (not left " &
             "dangling at freed memory)", not Fresh.Is_Valid);
      Check ("Insert_At replacing a scalar: the value is reachable by path",
             D.Root.By_Path ("/greeting").Scalar_Value = "hello");
   end;

   -----------------------------------------------------------------
   --  Insert_At merging a mapping into an existing mapping: the merge
   --  itself moves N's pairs into the target, but N is then unref'ed
   --  the same as any other case -- with no other reference, libfyaml
   --  frees it (confirmed live with valgrind: treating N as still
   --  Is_Valid here was reading already-freed memory). This binding
   --  nulls N out the same as for the failure case below.
   -----------------------------------------------------------------
   declare
      D : Doc.Document := Doc.Parse_String ("server: {host: localhost}");
      Patch : Nod.Node := Doc.Create_Mapping (D);
   begin
      Patch.Append_Pair (Doc.Create_Scalar (D, "port"), Doc.Create_Scalar (D, "8080"));
      Doc.Insert_At (D, "/server", Patch);
      Check ("Insert_At merging into an existing mapping: N is nulled " &
             "out (not left dangling at freed memory)", not Patch.Is_Valid);
      Check ("Insert_At merging into an existing mapping: the merged value " &
             "is reachable at the target",
             D.Root.By_Path ("/server/port").Scalar_Value = "8080" and then
             D.Root.By_Path ("/server/host").Scalar_Value = "localhost");
   end;

   -----------------------------------------------------------------
   --  Insert_At with a syntactically invalid path fails; N must be
   --  nulled out rather than left pointing at what libfyaml just
   --  freed. This is the core regression test for the fix.
   -----------------------------------------------------------------
   declare
      D : Doc.Document := Doc.Parse_String ("{}");
      Fresh : Nod.Node := Doc.Create_Scalar (D, "orphan");
      Raised_Program_Error : Boolean := False;
   begin
      begin
         Doc.Insert_At (D, "///not a valid path((", Fresh);
      exception
         when Program_Error =>
            Raised_Program_Error := True;
      end;
      Check ("Insert_At with an invalid path raises Program_Error",
             Raised_Program_Error);
      Check ("Insert_At with an invalid path nulls out N " &
             "(not left dangling at freed memory)",
             not Fresh.Is_Valid);
   end;

   Ada.Text_IO.New_Line;
   if Failures = 0 then
      Ada.Text_IO.Put_Line ("All checks passed.");
   else
      Ada.Text_IO.Put_Line (Integer'Image (Failures) & " check(s) failed.");
   end if;
end Test_Mutate;
