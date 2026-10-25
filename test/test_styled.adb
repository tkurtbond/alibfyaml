--  Libfyaml.Documents.Styled: each text comes out in the style asked
--  for, or double-quoted where that style can't hold it, and reads back
--  as itself.  Create_Scalar would write every one of these plain.

with Ada.Text_IO;
with Libfyaml.Documents.Styled;
with Libfyaml.Nodes;

procedure Test_Styled is

   package Doc renames Libfyaml.Documents;
   package Styled renames Libfyaml.Documents.Styled;

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

   LF : constant Character := ASCII.LF;
   Q  : constant Character := '"';
   NEL : constant String := Character'Val (16#C2#) & Character'Val (16#85#);

   --  "k: " & Text in S, emitted, is "k: " & Expected & LF, and parses
   --  back to Text.  libfyaml writes an empty line in a block indented.
   procedure Emits (Label : String; Text : String; S : Styled.Style; Expected : String) is
      D : Doc.Document := Doc.Parse_String ("{}");
      M : constant Libfyaml.Nodes.Node := D.Root;
   begin
      Libfyaml.Nodes.Append_Pair (M, D.Create_Scalar ("k"), Styled.Create_Styled_Scalar (D, Text, S));
      declare
         Out_Text : constant String := Doc.To_YAML (D, Doc.Emit_Mode_Block);
         Back : constant Doc.Document := Doc.Parse_String (Out_Text);
      begin
         Check (Label & ": written as asked", Out_Text = "k: " & Expected & LF);
         if Out_Text /= "k: " & Expected & LF then
            Ada.Text_IO.Put_Line ("    got: " & Out_Text);
         end if;
         Check (Label & ": reads back as itself", Back.Root.Value ("k").Scalar_Value = Text);
      end;
   end Emits;

begin
   Emits ("plain text", "Hiro", Styled.Plain, "Hiro");
   Emits ("a number with a sign", "-5", Styled.Plain, "-5");
   Emits ("non-ASCII", "café", Styled.Plain, "café");
   Emits ("a leading #", "#1 fan", Styled.Plain, Q & "#1 fan" & Q);
   Emits ("a leading blank", " x", Styled.Plain, Q & " x" & Q);
   Emits ("a leading quote", "'x", Styled.Plain, Q & "'x" & Q);
   Emits ("a leading dash and blank", "- x", Styled.Plain, Q & "- x" & Q);
   Emits ("a colon and blank", "a: b", Styled.Plain, Q & "a: b" & Q);
   Emits ("a blank and #", "a #b", Styled.Plain, Q & "a #b" & Q);
   Emits ("null's spelling", "null", Styled.Plain, Q & "null" & Q);
   Emits ("flow punctuation", "a, b", Styled.Plain, Q & "a, b" & Q);
   Emits ("NEL, plain", "a" & NEL & "b", Styled.Plain, Q & "a\Nb" & Q);
   Emits ("Double_Quoted", "x", Styled.Double_Quoted, Q & "x" & Q);
   Emits ("quotes and backslashes escaped", "a""b\c", Styled.Double_Quoted, Q & "a\""b\\c" & Q);
   Emits ("a control character", "a" & ASCII.SOH & "b", Styled.Double_Quoted, Q & "a\x01b" & Q);
   Emits ("Literal, one trailing line feed", "a" & LF & "b" & LF, Styled.Literal,
          "|" & LF & "  a" & LF & "  b");
   Emits ("Literal, none", "a" & LF & "b", Styled.Literal,
          "|-" & LF & "  a" & LF & "  b");
   Emits ("Literal, two", "a" & LF & LF, Styled.Literal,
          "|+" & LF & "  a" & LF & "  ");
   Emits ("Literal, a first line with leading blanks", "  a" & LF & "b", Styled.Literal,
          "|2-" & LF & "    a" & LF & "  b");
   Emits ("Literal, only line feeds", LF & LF, Styled.Literal, Q & "\n\n" & Q);
   Emits ("Literal, a control character", "a" & ASCII.SOH & LF, Styled.Literal, Q & "a\x01\n" & Q);

   declare
      D : Doc.Document := Doc.Parse_String ("{}");
      Bad : constant String := "a" & Character'Val (16#FF#);
   begin
      --  Attached, as the document frees only the nodes in its tree.
      Libfyaml.Nodes.Append_Pair
        (D.Root, D.Create_Scalar ("k"), Styled.Create_Styled_Scalar (D, Bad, Styled.Plain));
      Check ("text that isn't UTF-8 is kept as it is", D.Root.Value ("k").Scalar_Value = Bad);
   end;

   Ada.Text_IO.New_Line;
   if Failures = 0 then
      Ada.Text_IO.Put_Line ("All checks passed.");
   else
      Ada.Text_IO.Put_Line (Integer'Image (Failures) & " check(s) failed.");
   end if;
end Test_Styled;
