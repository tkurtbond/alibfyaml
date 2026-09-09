--  Exercises Libfyaml.Nodes.Has_Location/Location, added per
--  000-todo.org's "Add source-location access to alibfyaml": lets a
--  caller report a scalar node's own position in the source, e.g. for
--  the typed-scalar Data_Error cases (Integer_Value, Boolean_Value,
--  etc.), which today carry only the offending text.
--
--  Scoped to exactly what that motivates: a single (Line, Column)
--  start position for a scalar node's own value, via
--  fy_node_get_scalar_token + fy_token_start_mark. Two names in
--  000-todo.org's original wishlist don't correspond to anything real
--  in the libfyaml header actually linked here -- FYPCF_CREATE_MARKERS
--  (no such flag exists; ordinary parsing already produces marks, no
--  opt-in needed, confirmed live) and fy_node_get_start_token (the
--  real name is fy_node_get_scalar_token, scalar-only -- there is no
--  generic "start token of any node" for a sequence/mapping node).
--  fy_node_report and friends are variadic/va_list-based and stay out
--  of scope for the same reason README.md already excludes
--  fy_document_scanf/fy_node_buildf. A node's tag location
--  (fy_node_get_tag_token) and a token's *end* mark are natural,
--  cheap follow-ons if a concrete need shows up -- not built here,
--  since nothing currently needs them.
--
--  All Line/Column values below were read out live against these
--  exact fixtures (not hand-counted), including a re-derivation for
--  anchors.yaml's already-existing alias case.

with Ada.Text_IO;
with Libfyaml.Documents;
with Libfyaml.Nodes;

procedure Test_Location is

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

   procedure Check_Location
     (Label : String; N : Nod.Node; Line, Column : Positive)
   is
   begin
      Check (Label & ": Has_Location", N.Has_Location);
      if N.Has_Location then
         declare
            L : constant Nod.Node_Location := N.Location;
         begin
            Check (Label & ": Line =" & Line'Image, L.Line = Line);
            Check (Label & ": Column =" & Column'Image, L.Column = Column);
         end;
      end if;
   end Check_Location;

begin
   -----------------------------------------------------------------
   --  location.yaml:
   --    1  name: widget
   --    2  count: 42
   --    3  empty:
   --  1-indexed positions of each key's own scalar value.
   -----------------------------------------------------------------
   declare
      D : constant Doc.Document := Doc.Parse_File ("location.yaml");
   begin
      Check_Location ("name",  D.Root.By_Path ("/name"),  1, 7);
      Check_Location ("count", D.Root.By_Path ("/count"), 2, 8);
      --  An empty/omitted scalar ("key:" with nothing after it) still
      --  has a real, zero-width location -- not a missing one.
      Check_Location ("empty", D.Root.By_Path ("/empty"), 3, 6);
   end;

   -----------------------------------------------------------------
   --  anchors.yaml's alias node (already used by test_anchors.adb):
   --  "same: *b" on line 7. The location is of the anchor-name text
   --  ("b", column 8) -- not the "*" sigil at column 7 -- confirmed
   --  live, not assumed from the token's start.
   -----------------------------------------------------------------
   declare
      D : constant Doc.Document :=
        Doc.Parse_File ("anchors.yaml", Resolve_Anchors => False);
      Same : constant Nod.Node := D.Root.By_Path ("/same");
   begin
      Check ("alias node: Is_Alias", Same.Is_Alias);
      Check_Location ("alias node", Same, 7, 8);
   end;

   -----------------------------------------------------------------
   --  A freshly-built (not parsed) scalar node: Has_Location is
   --  True -- its token carries a synthetic all-zero mark rather
   --  than a NULL one, confirmed live -- but Location is the fixed
   --  (1, 1), not a real position in any source text. Documented on
   --  Has_Location's own doc comment; pinned down here so a future
   --  change to Create_Scalar's underlying libfyaml call can't
   --  silently start returning something else unnoticed.
   --
   --  Attached via Set_Root (rather than left dangling) so Document's
   --  Finalize actually owns and frees it -- a Create_Scalar node
   --  never attached anywhere is a genuine, if unsurprising, leak
   --  (confirmed live with valgrind while writing this test): nothing
   --  in the tree references it, so nothing frees it either.
   -----------------------------------------------------------------
   declare
      D     : Doc.Document := Doc.Parse_String ("{}");
      Fresh : constant Nod.Node := Doc.Create_Scalar (D, "x");
   begin
      Check_Location ("freshly-built scalar", Fresh, 1, 1);
      Doc.Set_Root (D, Fresh);
   end;

   Ada.Text_IO.New_Line;
   if Failures = 0 then
      Ada.Text_IO.Put_Line ("All checks passed.");
   else
      Ada.Text_IO.Put_Line (Integer'Image (Failures) & " check(s) failed.");
   end if;
end Test_Location;
