--  Performance regression check: stream MANY small separate documents
--  (see gen_manydocs.py) from one file, doing a little work with each and
--  letting it go out of scope immediately -- stresses Document creation/
--  destruction (one Owner_Liveness alloc + Mark_Dead per document), the
--  other path affected by the Owner_Liveness refcounting added for
--  Node/Document liveness enforcement (PLAN.md's "Node/Document liveness
--  enforcement" section, which also records the last measured numbers).
--  Uses only the public API, so this same source compiles unmodified
--  against any commit's library build -- see AGENTS.md's Benchmarking
--  section for the git-worktree recipe used to compare two commits.

with Ada.Command_Line;
with Ada.Real_Time;
with Ada.Text_IO;
with Libfyaml.Documents;
with Libfyaml.Documents.Streams;
with Libfyaml.Nodes;

procedure Bench_Streams is
   package Doc renames Libfyaml.Documents;
   package Streams renames Libfyaml.Documents.Streams;
   package Nod renames Libfyaml.Nodes;

   use type Ada.Real_Time.Time;

   Path : constant String :=
     (if Ada.Command_Line.Argument_Count >= 1
      then Ada.Command_Line.Argument (1)
      else "manydocs.yaml");

   Checksum   : Long_Long_Integer := 0;
   Doc_Count  : Natural := 0;

   Start_Time, End_Time : Ada.Real_Time.Time;
begin
   Start_Time := Ada.Real_Time.Clock;
   declare
      Stream : Streams.Document_Stream := Streams.Open_File (Path);
   begin
      while Stream.Has_Next loop
         declare
            D : constant Doc.Document := Stream.Next;
            R : constant Nod.Node := D.Root;
            Id   : constant Integer := R.Integer_Value ("id");
            Name : constant String := R.String_Value ("name", "");
         begin
            Doc_Count := Doc_Count + 1;
            Checksum := Checksum + Long_Long_Integer (Id) + Long_Long_Integer (Name'Length);
         end;
      end loop;
   end;
   End_Time := Ada.Real_Time.Clock;

   Ada.Text_IO.Put_Line ("bench_streams: docs=" & Doc_Count'Image &
                          " checksum=" & Checksum'Image);
   Ada.Text_IO.Put_Line ("bench_streams: elapsed_seconds=" &
     Duration'Image (Ada.Real_Time.To_Duration (End_Time - Start_Time)));
end Bench_Streams;
