--  Exercises the anchor/alias/merge-key resolution gap fixed per
--  PLAN.md's "Anchors, aliases, merge keys, and explicit tags"
--  section: an unresolved alias node used to read back via
--  Scalar_Value as its own anchor-name text, and an unresolved merge
--  key left an unreachable "<<" mapping entry instead of the merged
--  pairs -- both silently, no error. Covers:
--
--  - Parse_String/Parse_File's new Resolve_Anchors parameter
--    (defaults to True: anchors/aliases/merge keys resolved
--    automatically, confirmed both ways below).
--  - Libfyaml.Nodes.Is_Alias / Tag on the raw, unresolved tree.
--  - Libfyaml.Documents.Resolve, called explicitly on a document
--    parsed with Resolve_Anchors => False.
--  - Libfyaml.Resolve_Error on a genuine failure (a merge-key
--    reference loop).

with Ada.Text_IO;
with Libfyaml;
with Libfyaml.Documents;
with Libfyaml.Nodes;

procedure Test_Anchors is

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
   --  Default (Resolve_Anchors => True): the alias and the merge
   --  key are both resolved as part of parsing, with no separate
   --  call needed.
   -----------------------------------------------------------------
   declare
      D    : constant Doc.Document := Doc.Parse_File ("anchors.yaml");
      Same : constant Nod.Node := D.Root.By_Path ("/same");
   begin
      Check ("default parse: alias node is no longer Is_Alias",
             not Same.Is_Alias);
      Check ("default parse: alias resolves to the anchored mapping",
             Same.Is_Mapping and then
             Same.Value ("x").Scalar_Value = "1" and then
             Same.Value ("y").Scalar_Value = "2");
      Check ("default parse: merge key's own pairs are reachable",
             D.Root.By_Path ("/derived/x").Scalar_Value = "1" and then
             D.Root.By_Path ("/derived/y").Scalar_Value = "2");
      Check ("default parse: merge target's own pairs are kept too",
             D.Root.By_Path ("/derived/z").Scalar_Value = "3");
   end;

   -----------------------------------------------------------------
   --  Resolve_Anchors => False: the raw, unresolved tree. This is
   --  the gap PLAN.md describes -- confirmed here rather than just
   --  asserted, so a future change to the default can't silently
   --  break the case it exists to support (inspecting anchors/
   --  aliases themselves via Is_Alias/Tag before resolving).
   -----------------------------------------------------------------
   declare
      D    : Doc.Document :=
        Doc.Parse_File ("anchors.yaml", Resolve_Anchors => False);
      Same : constant Nod.Node := D.Root.By_Path ("/same");
   begin
      Check ("unresolved parse: alias node reports Is_Alias",
             Same.Is_Alias);
      Check ("unresolved parse: alias's own text is just the anchor name",
             Same.Scalar_Value = "b");
      Check ("unresolved parse: merge key's pairs are not yet reachable",
             not D.Root.By_Path ("/derived/x").Is_Valid);

      Doc.Resolve (D);
      Check ("after explicit Resolve: alias is no longer Is_Alias",
             not Same.Is_Alias);
      Check ("after explicit Resolve: alias resolves to the anchored " &
             "mapping", Same.Is_Mapping and then Same.Value ("x").Is_Valid);
      Check ("after explicit Resolve: merge key's pairs are now reachable",
             D.Root.By_Path ("/derived/x").Scalar_Value = "1");
   end;

   -----------------------------------------------------------------
   --  Explicit tags: Tag returns the raw tag text verbatim, or ""
   --  when a node has none.
   -----------------------------------------------------------------
   declare
      D : constant Doc.Document := Doc.Parse_File ("anchors.yaml");
   begin
      Check ("explicit tag: Tag returns the raw tag text",
             D.Root.By_Path ("/tagged").Tag = "!mytag");
      Check ("no explicit tag: Tag returns """"",
             D.Root.By_Path ("/untagged").Tag = "");
   end;

   -----------------------------------------------------------------
   --  Resolve_Error: a merge key that references its own anchor
   --  (a: &a { <<: *a, x: 1 }) is a genuine reference loop, not
   --  something Resolve can complete.
   --
   --  Note (not a defect in this binding): resolving this specific
   --  fixture leaks a small, fixed amount of memory (confirmed live
   --  with valgrind) entirely inside libfyaml's own ref-loop-
   --  detection diagnostic path (fy_document_resolve ->
   --  fy_check_ref_loop -> fy_document_diag_report ->
   --  fy_diag_vreport, against the libfyaml build linked here,
   --  package-labeled 0.8-9.fc44). Parsing the same fixture without
   --  calling Resolve, and resolving every other fixture in this
   --  file, are both confirmed leak-free -- only this exact failure
   --  path inside libfyaml itself leaks, so there is nothing on the
   --  Ada side to fix.
   -----------------------------------------------------------------
   declare
      D : Doc.Document :=
        Doc.Parse_File ("anchors_cycle.yaml", Resolve_Anchors => False);
      Raised_Resolve_Error : Boolean := False;
   begin
      begin
         Doc.Resolve (D);
      exception
         when Libfyaml.Resolve_Error =>
            Raised_Resolve_Error := True;
      end;
      Check ("Resolve on a merge-key reference loop raises Resolve_Error",
             Raised_Resolve_Error);
   end;

   Ada.Text_IO.New_Line;
   if Failures = 0 then
      Ada.Text_IO.Put_Line ("All checks passed.");
   else
      Ada.Text_IO.Put_Line (Integer'Image (Failures) & " check(s) failed.");
   end if;
end Test_Anchors;
