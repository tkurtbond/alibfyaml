--  Exercises Libfyaml.Documents.Insert_At's two outcomes for the N
--  parameter it takes "in out": on success, N remains a valid handle but
--  its content may have been moved into the target by libfyaml's merge
--  rules; on failure, libfyaml frees the node outright and this binding
--  nulls N out to close the resulting use-after-free hazard (confirmed
--  live during development: without this, a caught Program_Error left
--  the caller holding a Node pointing at freed memory).

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
   --  Insert_At replacing an existing scalar with another scalar: N
   --  remains a valid (not freed) handle afterward, and the new value
   --  is reachable at Path -- but N itself no longer reliably reads
   --  back its own pre-call content (confirmed: even this
   --  scalar-overwrites-scalar case, not just a sequence/mapping
   --  merge, can leave N's own content detached from what ends up
   --  attached at Path). Matches the doc comment on Insert_At: N stays
   --  safe to touch, but don't assume it still holds what you built --
   --  re-fetch via By_Path for the attached result.
   --  (Insert_At needs Path to already resolve to something -- it's
   --  "insert/replace at Path", not "create Path from nothing"; see
   --  fy_document_insert_at's own doc.)
   -----------------------------------------------------------------
   declare
      D : Doc.Document := Doc.Parse_String ("greeting: old");
      Fresh : Nod.Node := Doc.Create_Scalar (D, "hello");
   begin
      Doc.Insert_At (D, "/greeting", Fresh);
      Check ("Insert_At replacing a scalar: N remains valid (not freed)",
             Fresh.Is_Valid);
      Check ("Insert_At replacing a scalar: the value is reachable by path",
             D.Root.By_Path ("/greeting").Scalar_Value = "hello");
   end;

   -----------------------------------------------------------------
   --  Insert_At merging a mapping into an existing mapping: N remains
   --  Is_Valid (not freed) but is left empty, since its pairs were
   --  moved into the target -- libfyaml's own fy_node_insert merge
   --  behavior, not a defect in this binding, but worth pinning down
   --  so a future change to Insert_At doesn't silently start freeing N
   --  here too (that would be a regression toward the original bug).
   -----------------------------------------------------------------
   declare
      D : Doc.Document := Doc.Parse_String ("server: {host: localhost}");
      Patch : Nod.Node := Doc.Create_Mapping (D);
   begin
      Patch.Append_Pair (Doc.Create_Scalar (D, "port"), Doc.Create_Scalar (D, "8080"));
      Doc.Insert_At (D, "/server", Patch);
      Check ("Insert_At merging into an existing mapping: N remains valid " &
             "(not freed)", Patch.Is_Valid);
      Check ("Insert_At merging into an existing mapping: N's own pairs " &
             "were moved into the target (N is left empty)",
             Patch.Is_Valid and then Patch.Length = 0);
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
