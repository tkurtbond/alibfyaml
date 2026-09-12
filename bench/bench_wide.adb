--  Performance regression check: parse ONE large document (a top-level
--  sequence of many small mappings, see gen_wide.py) and navigate every
--  entity in it -- stresses Node creation/navigation (Value/Iterate, each
--  a Wrap call) within a single Document. This is the path most affected
--  by the Owner_Liveness refcounting added for Node/Document liveness
--  enforcement (PLAN.md's "Node/Document liveness enforcement" section,
--  which also records the last measured numbers). Uses only the public
--  API, so this same source compiles unmodified against any commit's
--  library build -- see AGENTS.md's Benchmarking section for the
--  git-worktree recipe used to compare two commits.

with Ada.Command_Line;
with Ada.Real_Time;
with Ada.Text_IO;
with Libfyaml.Documents;
with Libfyaml.Nodes;

procedure Bench_Wide is
   package Doc renames Libfyaml.Documents;
   package Nod renames Libfyaml.Nodes;

   use type Ada.Real_Time.Time;

   Path : constant String :=
     (if Ada.Command_Line.Argument_Count >= 1
      then Ada.Command_Line.Argument (1)
      else "wide.yaml");

   Checksum   : Long_Long_Integer := 0;
   Item_Count : Natural := 0;

   procedure Visit (Item : Nod.Node) is
      Id     : constant Integer := Item.Integer_Value ("id");
      Name   : constant String := Item.String_Value ("name", "");
      Value  : constant Float := Item.Float_Value ("value");
      Active : constant Boolean := Item.Boolean_Value ("active");
   begin
      Item_Count := Item_Count + 1;
      Checksum := Checksum + Long_Long_Integer (Id) + Long_Long_Integer (Name'Length);
      if Active then
         Checksum := Checksum + Long_Long_Integer (Value);
      end if;
   end Visit;

   Start_Time, End_Time : Ada.Real_Time.Time;
begin
   Start_Time := Ada.Real_Time.Clock;
   declare
      D : constant Doc.Document := Doc.Parse_File (Path);
      R : constant Nod.Node := D.Root;
   begin
      R.Iterate (Visit'Access);
   end;
   End_Time := Ada.Real_Time.Clock;

   Ada.Text_IO.Put_Line ("bench_wide: items=" & Item_Count'Image &
                          " checksum=" & Checksum'Image);
   Ada.Text_IO.Put_Line ("bench_wide: elapsed_seconds=" &
     Duration'Image (Ada.Real_Time.To_Duration (End_Time - Start_Time)));
end Bench_Wide;
