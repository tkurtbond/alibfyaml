--  The emitter's flags: each Emit_Mode_* asks libfyaml for that mode,
--  and Emit_Default keeps a document's own styles, as libfyaml's
--  FYECF_DEFAULT does.  libfyaml packs the indent, the width and the
--  mode into fields of one word (FYECF_INDENT_SHIFT 8, FYECF_WIDTH_SHIFT
--  12, FYECF_MODE_SHIFT 20 in libfyaml.h), so a mode put in the wrong
--  field asks for an indent instead, and the document comes out in its
--  original style.

with Ada.Strings.Fixed;
with Ada.Text_IO;
with Interfaces.C;
with Libfyaml.Documents;

procedure Test_Emit is

   package Doc renames Libfyaml.Documents;
   use type Interfaces.C.unsigned;

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

   function Has (S, Part : String) return Boolean is (Ada.Strings.Fixed.Index (S, Part) > 0);

   LF : constant Character := ASCII.LF;

   Flow  : constant String := "{a: 1, b: [x, y]}";
   Block : constant String := "a: 1" & LF & "b:" & LF & "- x" & LF & "- y" & LF;

begin
   --  libfyaml.h: FYECF_DEFAULT = FYECF_WIDTH_INF | FYECF_MODE_ORIGINAL
   --  | FYECF_INDENT_DEFAULT = FYECF_WIDTH (255) = 255 << 12.
   --  The constants are static, so GNAT knows each answer.
   pragma Warnings (Off, "condition is always*");
   Check ("Emit_Default is libfyaml's FYECF_DEFAULT, 16#FF000#", Doc.Emit_Default = 16#FF000#);
   Check ("Emit_Mode_Block is FYECF_MODE (1), 1 << 20", Doc.Emit_Mode_Block = 16#10_0000#);
   Check ("Emit_Mode_Flow is FYECF_MODE (2)", Doc.Emit_Mode_Flow = 16#20_0000#);
   Check ("Emit_Mode_Flow_Oneline is FYECF_MODE (3)", Doc.Emit_Mode_Flow_Oneline = 16#30_0000#);
   Check ("Emit_Mode_JSON is FYECF_MODE (4)", Doc.Emit_Mode_JSON = 16#40_0000#);
   pragma Warnings (On, "condition is always*");

   declare
      D : constant Doc.Document := Doc.Parse_String (Flow);
      S : constant String := Doc.To_YAML (D, Doc.Emit_Mode_Block);
   begin
      Check ("Emit_Mode_Block: a flow mapping comes out in block style",
             S = "a: 1" & LF & "b:" & LF & "- x" & LF & "- y" & LF);
      if S /= "a: 1" & LF & "b:" & LF & "- x" & LF & "- y" & LF then
         Ada.Text_IO.Put_Line ("    got: " & S);
      end if;
   end;

   declare
      D : constant Doc.Document := Doc.Parse_String (Block);
      S : constant String := Doc.To_YAML (D, Doc.Emit_Mode_Flow_Oneline);
   begin
      Check ("Emit_Mode_Flow_Oneline: a block mapping comes out on one line, in flow style",
             S = "{a: 1, b: [x, y]}" & LF);
   end;

   declare
      D : constant Doc.Document := Doc.Parse_String (Block);
      S : constant String := Doc.To_YAML (D, Doc.Emit_Mode_Flow);
   begin
      Check ("Emit_Mode_Flow: a block mapping comes out in flow style", Has (S, "{") and then Has (S, "["));
   end;

   declare
      D : constant Doc.Document := Doc.Parse_String (Block);
      S : constant String := Doc.To_YAML (D, Doc.Emit_Mode_JSON);
   begin
      Check ("Emit_Mode_JSON: JSON, its keys quoted", Has (S, """a"": 1") and then Has (S, """x"""));
   end;

   declare
      F : constant Doc.Document := Doc.Parse_String (Flow);
      B : constant Doc.Document := Doc.Parse_String (Block);
   begin
      Check ("Emit_Default: a block mapping stays block", Doc.To_YAML (B) = Block);
      Check ("Emit_Default: a flow mapping stays flow", Has (Doc.To_YAML (F), "{"));
   end;

   declare
      D : constant Doc.Document := Doc.Parse_String (Flow);
      S : constant String := Doc.To_YAML (D, Doc.Emit_Sort_Keys or Doc.Emit_Mode_Block);
   begin
      Check ("flags combine with or: Emit_Sort_Keys or Emit_Mode_Block",
             S = "a: 1" & LF & "b:" & LF & "- x" & LF & "- y" & LF);
   end;

   Ada.Text_IO.New_Line;
   if Failures = 0 then
      Ada.Text_IO.Put_Line ("All checks passed.");
   else
      Ada.Text_IO.Put_Line (Integer'Image (Failures) & " check(s) failed.");
   end if;
end Test_Emit;
