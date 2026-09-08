--  Exercises Libfyaml.Nodes' typed scalar accessors: valid conversions,
--  hex/octal/boolean-case variants, missing-vs-malformed error handling,
--  and optional-with-default behavior.

with Ada.Text_IO;
with Ada.Exceptions;
with Libfyaml;
with Libfyaml.Documents;
with Libfyaml.Nodes;

procedure Test_Scalars is

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

   procedure Check_Missing_Key (Label : String; Map : Nod.Node; Key : String) is
   begin
      declare
         Unused : constant Integer := Map.Integer_Value (Key);
      begin
         Ada.Text_IO.Put_Line
           ("FAIL - " & Label & " (expected Missing_Key, got " &
            Integer'Image (Unused) & ")");
         Failures := Failures + 1;
      end;
   exception
      when Libfyaml.Missing_Key =>
         Ada.Text_IO.Put_Line ("ok   - " & Label);
      when E : others =>
         Ada.Text_IO.Put_Line
           ("FAIL - " & Label & " (wrong exception: " &
            Ada.Exceptions.Exception_Name (E) & ")");
         Failures := Failures + 1;
   end Check_Missing_Key;

   procedure Check_Data_Error (Label : String; Map : Nod.Node; Key : String) is
   begin
      declare
         Unused : constant Integer := Map.Integer_Value (Key);
      begin
         Ada.Text_IO.Put_Line
           ("FAIL - " & Label & " (expected Data_Error, got " &
            Integer'Image (Unused) & ")");
         Failures := Failures + 1;
      end;
   exception
      when Libfyaml.Data_Error =>
         Ada.Text_IO.Put_Line ("ok   - " & Label);
      when E : others =>
         Ada.Text_IO.Put_Line
           ("FAIL - " & Label & " (wrong exception: " &
            Ada.Exceptions.Exception_Name (E) & ")");
         Failures := Failures + 1;
   end Check_Data_Error;

   YAML : constant String :=
     "int_dec: 42" & ASCII.LF &
     "int_neg: -7" & ASCII.LF &
     "int_hex: 0x1A" & ASCII.LF &
     "int_oct: 0o17" & ASCII.LF &
     "float_val: 3.5" & ASCII.LF &
     "float_exp: 1.5e2" & ASCII.LF &
     "bool_true: true" & ASCII.LF &
     "bool_TRUE: TRUE" & ASCII.LF &
     "bool_False: False" & ASCII.LF &
     "not_a_number: banana" & ASCII.LF &
     "name: widget" & ASCII.LF;

begin
   declare
      D   : constant Doc.Document := Doc.Parse_String (YAML);
      Map : constant Nod.Node := D.Root;
   begin
      --  Required, valid.
      Check ("int_dec = 42", Map.Integer_Value ("int_dec") = 42);
      Check ("int_neg = -7", Map.Integer_Value ("int_neg") = -7);
      Check ("int_hex = 26", Map.Integer_Value ("int_hex") = 26);
      Check ("int_oct = 15", Map.Integer_Value ("int_oct") = 15);
      Check ("int_dec as Long_Long_Integer = 42",
             Map.Long_Long_Integer_Value ("int_dec") = 42);
      Check ("float_val = 3.5", Map.Float_Value ("float_val") = 3.5);
      Check ("float_exp = 150.0", Map.Float_Value ("float_exp") = 150.0);
      Check ("int_dec as Float = 42.0", Map.Float_Value ("int_dec") = 42.0);
      Check ("bool_true = True", Map.Boolean_Value ("bool_true") = True);
      Check ("bool_TRUE = True", Map.Boolean_Value ("bool_TRUE") = True);
      Check ("bool_False = False", Map.Boolean_Value ("bool_False") = False);
      Check ("name = ""widget""", Map.String_Value ("name") = "widget");

      --  Non-raising shape predicates.
      Check ("Is_Integer (int_dec)", Map.Value ("int_dec").Is_Integer);
      Check ("not Is_Integer (name)", not Map.Value ("name").Is_Integer);
      Check ("Is_Float (float_val)", Map.Value ("float_val").Is_Float);
      Check ("Is_Boolean (bool_true)", Map.Value ("bool_true").Is_Boolean);
      Check ("not Is_Boolean (name)", not Map.Value ("name").Is_Boolean);

      --  Optional, present.
      Check ("int_dec optional = 42",
             Map.Integer_Value ("int_dec", 99) = 42);

      --  Optional, absent -> default.
      Check ("missing optional -> default",
             Map.Integer_Value ("does_not_exist", 99) = 99);
      Check ("missing optional string -> default",
             Map.String_Value ("does_not_exist", "fallback") = "fallback");

      --  Required, absent -> Missing_Key.
      Check_Missing_Key ("missing required -> Missing_Key",
                          Map, "does_not_exist");

      --  Required, present but malformed -> Data_Error.
      Check_Data_Error ("malformed int -> Data_Error", Map, "not_a_number");

      --  Optional, present but malformed -> Data_Error even with a
      --  default (absence and malformed-ness are different failures).
      declare
         Unused : Integer;
      begin
         Unused := Map.Integer_Value ("not_a_number", 99);
         Ada.Text_IO.Put_Line
           ("FAIL - malformed optional -> Data_Error (got " &
            Integer'Image (Unused) & ")");
         Failures := Failures + 1;
      exception
         when Libfyaml.Data_Error =>
            Ada.Text_IO.Put_Line ("ok   - malformed optional -> Data_Error");
      end;
   end;

   Ada.Text_IO.New_Line;
   if Failures = 0 then
      Ada.Text_IO.Put_Line ("All checks passed.");
   else
      Ada.Text_IO.Put_Line (Integer'Image (Failures) & " check(s) failed.");
   end if;
end Test_Scalars;
