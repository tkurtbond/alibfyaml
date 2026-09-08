with Ada.Text_IO;
with Libfyaml.Documents;
with Libfyaml.Nodes;

procedure Test_Sequence is
   package Doc renames Libfyaml.Documents;
   package Nod renames Libfyaml.Nodes;

   procedure Show (N : Nod.Node) is
   begin
      Ada.Text_IO.Put_Line ("  - " & N.Scalar_Value);
   end Show;

begin
   declare
      D : constant Doc.Document := Doc.Parse_File ("config.yaml");
      Origins : constant Nod.Node := Doc.Root (D).By_Path ("/allowed_origins");
   begin
      Ada.Text_IO.Put_Line ("Length:" & Origins.Length'Image);
      for I in 1 .. Origins.Length loop
         Ada.Text_IO.Put_Line ("Item" & I'Image & ": " & Origins.Item (I).Scalar_Value);
      end loop;
      Ada.Text_IO.Put_Line ("Iterate:");
      Origins.Iterate (Show'Access);
   end;
end Test_Sequence;
