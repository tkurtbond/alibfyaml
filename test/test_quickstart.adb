--  Ada re-implementation of examples/quick-start.c, to exercise the
--  binding end to end: parse a file, read nested scalar values, mutate
--  the tree via a mapping insert, and emit the result.

with Ada.Text_IO;
with Ada.Command_Line;
with Ada.Exceptions;
with Libfyaml;
with Libfyaml.Documents;
with Libfyaml.Nodes;

procedure Test_Quickstart is

   package Doc renames Libfyaml.Documents;
   package Nod renames Libfyaml.Nodes;

   Input_File : constant String :=
     (if Ada.Command_Line.Argument_Count >= 1
      then Ada.Command_Line.Argument (1)
      else "config.yaml");

begin
   declare
      D : Doc.Document := Doc.Parse_File (Input_File);
      Server, Host, Port, Timeout : Nod.Node;
   begin
      Server := Doc.Root (D).By_Path ("/server");
      if not Server.Is_Valid then
         Ada.Text_IO.Put_Line ("no /server section in " & Input_File);
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;

      Host := Server.Value ("host");
      Port := Server.Value ("port");

      Ada.Text_IO.Put_Line
        ("Current configuration: " & Host.Scalar_Value & ":" & Port.Scalar_Value);

      --  Mirror examples/quick-start.c: build a small mapping and merge it
      --  into /server with Insert_At (fy_node_insert semantics: existing
      --  keys are overwritten, new keys are added) rather than
      --  Nod.Append_Pair directly on Server, which rejects a key that is
      --  already present -- and examples/config.yaml already has a
      --  server.timeout entry.
      declare
         Patch : constant Nod.Node := Doc.Create_Mapping (D);
      begin
         Timeout := Doc.Create_Scalar (D, "45");
         Patch.Append_Pair (Doc.Create_Scalar (D, "timeout"), Timeout);
         Doc.Insert_At (D, "/server", Patch);
      end;

      Ada.Text_IO.Put_Line ("Updated timeout setting");
      Ada.Text_IO.Put_Line ("");
      Ada.Text_IO.Put_Line ("Updated configuration:");
      Ada.Text_IO.Put (Doc.To_YAML (D, Doc.Emit_Sort_Keys));
   end;

exception
   when E : Libfyaml.Parse_Error =>
      Ada.Text_IO.Put_Line ("Failed to parse " & Input_File & ":");
      Ada.Text_IO.Put_Line (Ada.Exceptions.Exception_Message (E));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Test_Quickstart;
