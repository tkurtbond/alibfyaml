--  Exercises Node/Document liveness enforcement, per PLAN.md's "Node/
--  Document liveness enforcement" section: a Node used after its owning
--  Document has been Finalized now fails Is_Valid (and hence, with
--  -gnata enabled, every Pre => Is_Valid (N) accessor raises a clean
--  Ada.Assertions.Assertion_Error) instead of reading freed memory.
--  Ported from the equivalent design in the sibling slibfyaml binding
--  (Chicken Scheme, ~/Repos/Scheme/Chicken/5/slibfyaml).

with Ada.Assertions;
with Ada.Text_IO;
with Libfyaml;
with Libfyaml.Documents;
with Libfyaml.Nodes;

procedure Test_Liveness is

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

   Root_After  : Nod.Node := Nod.Null_Node;
   Value_After : Nod.Node := Nod.Null_Node;

begin
   -----------------------------------------------------------------
   --  While the Document is alive, Nodes drawn from it (both the
   --  root itself and one reached by further navigation) are valid,
   --  same as always -- this feature must not disturb ordinary use.
   -----------------------------------------------------------------
   declare
      D : constant Doc.Document := Doc.Parse_File ("config.yaml");
      R : constant Nod.Node := D.Root;
      V : constant Nod.Node := R.By_Path ("/server/host");
   begin
      Check ("while Document is alive: root Node is valid", R.Is_Valid);
      Check ("while Document is alive: navigated Node is valid", V.Is_Valid);
      Check ("while Document is alive: navigated Node reads correctly",
             V.Scalar_Value = "localhost");

      --  Saved outside this block, deliberately, so it can be checked
      --  again after D is gone below.
      Root_After := R;
      Value_After := V;
   end;

   -----------------------------------------------------------------
   --  D has now been Finalized (the declare block above ended).
   --  Every Node drawn from it -- however it was obtained -- must
   --  report Is_Valid => False, not read freed memory.
   -----------------------------------------------------------------
   Check ("after Document is gone: root Node reports Is_Valid => False",
          not Root_After.Is_Valid);
   Check ("after Document is gone: navigated Node reports Is_Valid => False",
          not Value_After.Is_Valid);

   -----------------------------------------------------------------
   --  A Pre => Is_Valid (N) accessor on such a Node raises a clean
   --  Ada.Assertions.Assertion_Error (with -gnata enabled, as both
   --  this project's .gpr files do) rather than reading freed memory
   --  or crashing.
   -----------------------------------------------------------------
   declare
      Raised_Assertion_Error : Boolean := False;
   begin
      begin
         declare
            Unused : constant Boolean := Value_After.Is_Scalar;
         begin
            null;
         end;
      exception
         when Ada.Assertions.Assertion_Error =>
            Raised_Assertion_Error := True;
      end;
      Check ("Is_Scalar on a Node whose Document is gone raises " &
             "Assertion_Error (not a silent freed-memory read)",
             Raised_Assertion_Error);
   end;

   -----------------------------------------------------------------
   --  Null_Node itself is unaffected by any of this -- it never had
   --  an owning Document to begin with, and must keep reporting
   --  Is_Valid => False exactly as before this feature existed.
   -----------------------------------------------------------------
   Check ("Null_Node is still simply invalid, not a special liveness case",
          not Nod.Null_Node.Is_Valid);

   -----------------------------------------------------------------
   --  Two Nodes drawn from the SAME Document share one liveness
   --  flag: destroying the Document invalidates both together, not
   --  independently (confirms this is tracked per-Document, not
   --  per-Node).
   -----------------------------------------------------------------
   declare
      Root_Copy_A : Nod.Node;
      Root_Copy_B : Nod.Node;
   begin
      declare
         D : constant Doc.Document := Doc.Parse_File ("config.yaml");
      begin
         Root_Copy_A := D.Root;
         Root_Copy_B := D.Root.By_Path ("/database");
      end;
      Check ("shared owner: both Nodes drawn from one Document " &
             "become invalid together",
             not Root_Copy_A.Is_Valid and then not Root_Copy_B.Is_Valid);
   end;

   Ada.Text_IO.New_Line;
   if Failures = 0 then
      Ada.Text_IO.Put_Line ("All checks passed.");
   else
      Ada.Text_IO.Put_Line (Integer'Image (Failures) & " check(s) failed.");
   end if;
end Test_Liveness;
