--  Example: report a MISSING required key three ways -- Location
--  alone, Path alone, and both together -- to show why a caller might
--  want either one independently, or both.
--
--  This is a genuinely different case from example_value_error.adb's
--  malformed-value one: there, the key exists and has a Node with its
--  own scalar token, so Location works directly. Here, the key is
--  simply absent -- there is no Node/token for it at all, so
--  Location has nothing to report a position for (Has_Location is
--  scalar-only, and there's no scalar to ask). Path has no such
--  problem: the *enclosing mapping's* own Path is always available
--  regardless of what keys it does or doesn't have, so appending the
--  missing key's name to it (e.g. "/1" + "/count") gives an exact,
--  unambiguous structural address -- something Location fundamentally
--  cannot do for an absent key.
--
--  "Location alone" below approximates a source position by using a
--  nearby sibling field's own Location instead (here, "name", which
--  every entry has) -- clearly labeled as an approximation ("near"),
--  since it's the sibling's position, not the missing key's own (which
--  doesn't exist to have one). A caller who only cares about *which
--  structural element* is broken, not what line it's roughly near,
--  can skip this and use Path alone; a caller who wants both prints
--  both. See test_path.adb / test_location.adb for these two bindings
--  exercised independently.
--
--  Run as: ./example_missing_field [file]  (defaults to
--  missing_field.yaml, which has two entries: "alpha" with a count,
--  "beta" without one)

with Ada.Command_Line;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Libfyaml.Documents;
with Libfyaml.Nodes;

procedure Example_Missing_Field is

   package Doc renames Libfyaml.Documents;
   package Nod renames Libfyaml.Nodes;

   Input_File : constant String :=
     (if Ada.Command_Line.Argument_Count >= 1
      then Ada.Command_Line.Argument (1)
      else "missing_field.yaml");

   Saw_Error : Boolean := False;

   function Trimmed (N : Positive) return String is
     (Ada.Strings.Fixed.Trim (N'Image, Ada.Strings.Left));

   --  Location alone: approximate, via a nearby sibling scalar
   --  ("name") that every entry is expected to have. Falls back to
   --  just "(unknown position)" if even that is missing or has no
   --  location of its own (e.g. a freshly-built node).
   procedure Report_By_Location (Item : Nod.Node; Key : String) is
      Sibling : constant Nod.Node := Item.Value ("name");
   begin
      Ada.Text_IO.Put ("[Location]  ");
      if Sibling.Is_Valid and then Sibling.Has_Location then
         declare
            L : constant Nod.Node_Location := Sibling.Location;
         begin
            Ada.Text_IO.Put
              ("line" & L.Line'Image & ", column" & L.Column'Image &
               " (near """ & Sibling.Scalar_Value & """)");
         end;
      else
         Ada.Text_IO.Put ("(unknown position)");
      end if;
      Ada.Text_IO.Put_Line (": missing required key """ & Key & """");
   end Report_By_Location;

   --  Path alone: exact, always available -- no approximation needed,
   --  since Item's own Path exists regardless of which keys it has.
   procedure Report_By_Path (Item : Nod.Node; Key : String) is
   begin
      Ada.Text_IO.Put_Line
        ("[Path]      " & Item.Path & "/" & Key &
         ": missing required key """ & Key & """");
   end Report_By_Path;

   --  Both together: Path pinpoints which element, Location gives a
   --  human a line to jump to in an editor -- neither alone gives you
   --  both of those.
   procedure Report_By_Both (Item : Nod.Node; Key : String) is
      Sibling : constant Nod.Node := Item.Value ("name");
   begin
      Ada.Text_IO.Put ("[Both]      " & Item.Path & "/" & Key & " (");
      if Sibling.Is_Valid and then Sibling.Has_Location then
         declare
            L : constant Nod.Node_Location := Sibling.Location;
         begin
            Ada.Text_IO.Put
              ("near line " & Trimmed (L.Line) & ", column " & Trimmed (L.Column));
         end;
      else
         Ada.Text_IO.Put ("position unknown");
      end if;
      Ada.Text_IO.Put_Line
        ("): missing required key """ & Key & """");
   end Report_By_Both;

   D : constant Doc.Document := Doc.Parse_File (Input_File);

begin
   for I in 1 .. D.Root.Length loop
      declare
         Item : constant Nod.Node := D.Root.Item (I);
      begin
         if not Item.Has_Key ("count") then
            Saw_Error := True;
            Report_By_Location (Item, "count");
            Report_By_Path (Item, "count");
            Report_By_Both (Item, "count");
         end if;
      end;
   end loop;

   if Saw_Error then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Example_Missing_Field;
