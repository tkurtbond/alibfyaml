--  Exercises Libfyaml.Nodes.Path, the inverse of By_Path: given a
--  node, return its own structural address relative to the document
--  root (e.g. "/company/departments/0/teams/1"), in the same syntax
--  By_Path already accepts as input.
--
--  Deliberately independent of Location/Has_Location (test_location.
--  adb): Path works on a node of ANY kind -- mapping and sequence
--  nodes included, not just scalars -- since it's purely structural,
--  unlike a source Location, which needs a scalar token to hang a
--  line/column off of. A caller with both bindings available can use
--  either one alone or both together; nothing here requires the
--  other. See example_missing_field.adb for a worked "use both at
--  once" case (Location approximates a position via a nearby scalar
--  sibling, Path pinpoints the exact structural location of a
--  genuinely missing key that has no node/token of its own to report
--  a Location for).
--
--  All Path strings below were read out live against navigate.yaml
--  (not hand-derived from the header), including the document root's
--  own case -- see the comment on Libfyaml.Nodes.Path and
--  Libfyaml.Thin's fy_node_get_path for why that returns the real
--  string "/" rather than "", despite what the C header claims
--  ("NULL if fyn is the root").

with Ada.Text_IO;
with Libfyaml.Documents;
with Libfyaml.Nodes;

procedure Test_Path is

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

   procedure Check_Path (Label : String; N : Nod.Node; Expected : String) is
   begin
      Check (Label & ": Path = """ & Expected & """", N.Path = Expected);
   end Check_Path;

   D : constant Doc.Document := Doc.Parse_File ("navigate.yaml");

begin
   -----------------------------------------------------------------
   --  The document root itself: "/", not "" -- confirmed live,
   --  despite the C header's own claim that fy_node_get_path returns
   --  NULL for the root (Libfyaml.Thin's fy_node_get_path comment).
   -----------------------------------------------------------------
   Check_Path ("root", D.Root, "/");

   -----------------------------------------------------------------
   --  A top-level scalar field.
   -----------------------------------------------------------------
   Check_Path ("name", D.Root.By_Path ("/name"), "/name");

   -----------------------------------------------------------------
   --  A sequence element (0-indexed, matching By_Path's own syntax).
   -----------------------------------------------------------------
   Check_Path ("tags/0", D.Root.By_Path ("/tags/0"), "/tags/0");

   -----------------------------------------------------------------
   --  A mapping node, not a scalar -- Path works here; Location
   --  (test_location.adb) does not, since a mapping node has no
   --  scalar token of its own to report a source position for. This
   --  is the concrete case Path exists to cover that Location can't.
   -----------------------------------------------------------------
   declare
      Server : constant Nod.Node := D.Root.By_Path ("/server");
   begin
      Check ("server: Is_Mapping", Server.Is_Mapping);
      Check_Path ("server", Server, "/server");
   end;

   -----------------------------------------------------------------
   --  Four levels of nesting (sequence/mapping/sequence/mapping),
   --  same fixture path test_navigate.adb's own deep-access case
   --  uses -- confirms Path round-trips through real nesting, not
   --  just one level.
   -----------------------------------------------------------------
   Check_Path
     ("company/departments/0/teams/1",
      D.Root.By_Path ("/company/departments/0/teams/1"),
      "/company/departments/0/teams/1");

   -----------------------------------------------------------------
   --  A field inside one element of a sequence-of-mappings.
   -----------------------------------------------------------------
   Check_Path
     ("endpoints/1/name",
      D.Root.By_Path ("/endpoints/1/name"),
      "/endpoints/1/name");

   -----------------------------------------------------------------
   --  Round-trip: By_Path (Path (N)) = N, for a node reached two
   --  different ways (chained Value/Item vs. By_Path) -- confirms
   --  Path's output is genuinely usable as By_Path input, not just a
   --  similar-looking string.
   -----------------------------------------------------------------
   declare
      Lead : constant Nod.Node :=
        D.Root.Value ("company").Value ("departments").Item (1)
          .Value ("teams").Item (1).Value ("lead");
      Round_Tripped : constant Nod.Node := D.Root.By_Path (Lead.Path);
   begin
      Check
        ("round-trip By_Path (Path (N)) = N",
         Round_Tripped.Scalar_Value = Lead.Scalar_Value);
   end;

   Ada.Text_IO.New_Line;
   if Failures = 0 then
      Ada.Text_IO.Put_Line ("All checks passed.");
   else
      Ada.Text_IO.Put_Line (Integer'Image (Failures) & " check(s) failed.");
   end if;
end Test_Path;
