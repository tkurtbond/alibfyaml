--  Exercises every typed scalar accessor in Libfyaml.Nodes against
--  test/scalars.yaml: per-node conversions and shape predicates; the
--  (Map, Key) required and optional-with-default forms of all of
--  Integer_Value/Long_Integer_Value/Long_Long_Integer_Value/
--  Float_Value/Long_Float_Value/Boolean_Value/String_Value, and
--  Required; and every documented failure mode (Missing_Key, and
--  Data_Error for malformed text, out-of-range numbers, and
--  non-scalar values) for both the required and optional forms.

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

   procedure Expect_Missing_Key
     (Label : String; Try : not null access procedure)
   is
   begin
      Try.all;
      Ada.Text_IO.Put_Line ("FAIL - " & Label & " (no exception raised)");
      Failures := Failures + 1;
   exception
      when Libfyaml.Missing_Key =>
         Ada.Text_IO.Put_Line ("ok   - " & Label);
      when E : others =>
         Ada.Text_IO.Put_Line
           ("FAIL - " & Label & " (wrong exception: " &
            Ada.Exceptions.Exception_Name (E) & ")");
         Failures := Failures + 1;
   end Expect_Missing_Key;

   procedure Expect_Data_Error
     (Label : String; Try : not null access procedure)
   is
   begin
      Try.all;
      Ada.Text_IO.Put_Line ("FAIL - " & Label & " (no exception raised)");
      Failures := Failures + 1;
   exception
      when Libfyaml.Data_Error =>
         Ada.Text_IO.Put_Line ("ok   - " & Label);
      when E : others =>
         Ada.Text_IO.Put_Line
           ("FAIL - " & Label & " (wrong exception: " &
            Ada.Exceptions.Exception_Name (E) & ")");
         Failures := Failures + 1;
   end Expect_Data_Error;

begin
   declare
      D   : constant Doc.Document := Doc.Parse_File ("scalars.yaml");
      Map : constant Nod.Node := D.Root;
   begin
      -----------------------------------------------------------------
      --  Per-node accessors and shape predicates
      -----------------------------------------------------------------
      declare
         N_Int  : constant Nod.Node := Map.Value ("int_dec");
         N_Bool : constant Nod.Node := Map.Value ("bool_true");
      begin
         Check ("Is_Integer (int_dec)", N_Int.Is_Integer);
         Check ("Is_Float (int_dec)", N_Int.Is_Float);
         Check ("not Is_Boolean (int_dec)", not N_Int.Is_Boolean);
         Check ("Integer_Value (int_dec node) = 42", N_Int.Integer_Value = 42);
         Check ("Long_Integer_Value (int_dec node) = 42",
                N_Int.Long_Integer_Value = 42);
         Check ("Long_Long_Integer_Value (int_dec node) = 42",
                N_Int.Long_Long_Integer_Value = 42);
         Check ("Float_Value (int_dec node) = 42.0", N_Int.Float_Value = 42.0);
         Check ("Long_Float_Value (int_dec node) = 42.0",
                N_Int.Long_Float_Value = 42.0);

         Check ("Is_Boolean (bool_true)", N_Bool.Is_Boolean);
         Check ("not Is_Integer (bool_true)", not N_Bool.Is_Integer);
         Check ("Boolean_Value (bool_true node) = True",
                N_Bool.Boolean_Value = True);
      end;

      -----------------------------------------------------------------
      --  Required (Map, Key) accessors: happy path
      -----------------------------------------------------------------
      Check ("Required (name) is a scalar",
             Map.Required ("name").Is_Scalar);
      Check ("Required (name) scalar text = ""widget""",
             Map.Required ("name").Scalar_Value = "widget");

      Check ("Integer_Value (int_dec) = 42", Map.Integer_Value ("int_dec") = 42);
      Check ("Integer_Value (int_neg) = -7", Map.Integer_Value ("int_neg") = -7);
      Check ("Integer_Value (int_hex) = 26", Map.Integer_Value ("int_hex") = 26);
      Check ("Integer_Value (int_oct) = 15", Map.Integer_Value ("int_oct") = 15);
      Check ("Integer_Value (int_zero) = 0", Map.Integer_Value ("int_zero") = 0);

      --  Extensions beyond YAML 1.2 core schema (see README.md):
      --  "0b" binary, and "_" as a digit separator in any base.
      Check ("Integer_Value (int_bin) = 10 (0b extension)",
             Map.Integer_Value ("int_bin") = 10);
      Check ("Integer_Value (int_underscore) = 1_000_000 (_ extension)",
             Map.Integer_Value ("int_underscore") = 1_000_000);
      Check ("Integer_Value (int_hex_underscore) = 65535 (0x + _ extension)",
             Map.Integer_Value ("int_hex_underscore") = 65535);
      Check ("Integer_Value (int_hex_neg) = -26 (sign + 0x prefix)",
             Map.Integer_Value ("int_hex_neg") = -26);

      Check ("Long_Integer_Value (int_dec) = 42",
             Map.Long_Integer_Value ("int_dec") = 42);
      Check ("Long_Long_Integer_Value (big_int) = 5_000_000_000",
             Map.Long_Long_Integer_Value ("big_int") = 5_000_000_000);

      Check ("Float_Value (float_val) = 3.5", Map.Float_Value ("float_val") = 3.5);
      Check ("Float_Value (float_exp) = 150.0",
             Map.Float_Value ("float_exp") = 150.0);
      Check ("Float_Value (float_neg) = -2.25",
             Map.Float_Value ("float_neg") = -2.25);
      Check ("Float_Value (float_underscore) = 1234.56 (_ extension)",
             Map.Float_Value ("float_underscore") = 1234.56);
      Check ("Long_Float_Value (float_overflow) > 1.0",
             Map.Long_Float_Value ("float_overflow") > 1.0);

      Check ("Boolean_Value (bool_true) = True",
             Map.Boolean_Value ("bool_true") = True);
      Check ("Boolean_Value (bool_True) = True",
             Map.Boolean_Value ("bool_True") = True);
      Check ("Boolean_Value (bool_TRUE) = True",
             Map.Boolean_Value ("bool_TRUE") = True);
      Check ("Boolean_Value (bool_false) = False",
             Map.Boolean_Value ("bool_false") = False);
      Check ("Boolean_Value (bool_False) = False",
             Map.Boolean_Value ("bool_False") = False);
      Check ("Boolean_Value (bool_FALSE) = False",
             Map.Boolean_Value ("bool_FALSE") = False);

      Check ("String_Value (name) = ""widget""",
             Map.String_Value ("name") = "widget");

      -----------------------------------------------------------------
      --  Missing_Key: required key absent
      -----------------------------------------------------------------
      declare
         procedure Try is
            Unused : constant Nod.Node := Map.Required ("does_not_exist");
            pragma Unreferenced (Unused);
         begin
            null;
         end Try;
      begin
         Expect_Missing_Key ("Required (does_not_exist) -> Missing_Key", Try'Access);
      end;

      declare
         procedure Try is
            Unused : constant Integer := Map.Integer_Value ("does_not_exist");
            pragma Unreferenced (Unused);
         begin
            null;
         end Try;
      begin
         Expect_Missing_Key
           ("Integer_Value (does_not_exist) -> Missing_Key", Try'Access);
      end;

      -----------------------------------------------------------------
      --  Data_Error: malformed text, for every required numeric/bool
      --  accessor -- String_Value, by contrast, accepts any text.
      -----------------------------------------------------------------
      declare
         procedure Try is
            Unused : constant Integer := Map.Integer_Value ("malformed");
            pragma Unreferenced (Unused);
         begin
            null;
         end Try;
      begin
         Expect_Data_Error ("Integer_Value (malformed) -> Data_Error", Try'Access);
      end;

      declare
         procedure Try is
            Unused : constant Long_Integer := Map.Long_Integer_Value ("malformed");
            pragma Unreferenced (Unused);
         begin
            null;
         end Try;
      begin
         Expect_Data_Error
           ("Long_Integer_Value (malformed) -> Data_Error", Try'Access);
      end;

      declare
         procedure Try is
            Unused : constant Long_Long_Integer :=
              Map.Long_Long_Integer_Value ("malformed");
            pragma Unreferenced (Unused);
         begin
            null;
         end Try;
      begin
         Expect_Data_Error
           ("Long_Long_Integer_Value (malformed) -> Data_Error", Try'Access);
      end;

      declare
         procedure Try is
            Unused : constant Float := Map.Float_Value ("malformed");
            pragma Unreferenced (Unused);
         begin
            null;
         end Try;
      begin
         Expect_Data_Error ("Float_Value (malformed) -> Data_Error", Try'Access);
      end;

      declare
         procedure Try is
            Unused : constant Long_Float := Map.Long_Float_Value ("malformed");
            pragma Unreferenced (Unused);
         begin
            null;
         end Try;
      begin
         Expect_Data_Error
           ("Long_Float_Value (malformed) -> Data_Error", Try'Access);
      end;

      declare
         procedure Try is
            Unused : constant Boolean := Map.Boolean_Value ("malformed");
            pragma Unreferenced (Unused);
         begin
            null;
         end Try;
      begin
         Expect_Data_Error ("Boolean_Value (malformed) -> Data_Error", Try'Access);
      end;

      Check ("String_Value (malformed) = ""banana"" (no error)",
             Map.String_Value ("malformed") = "banana");

      -----------------------------------------------------------------
      --  Data_Error: malformed digit-separator placement, and an
      --  invalid binary digit.
      -----------------------------------------------------------------
      declare
         procedure Try is
            Unused : constant Integer :=
              Map.Integer_Value ("bad_underscore_leading");
            pragma Unreferenced (Unused);
         begin
            null;
         end Try;
      begin
         Expect_Data_Error
           ("Integer_Value (bad_underscore_leading) -> Data_Error", Try'Access);
      end;

      declare
         procedure Try is
            Unused : constant Integer :=
              Map.Integer_Value ("bad_underscore_trailing");
            pragma Unreferenced (Unused);
         begin
            null;
         end Try;
      begin
         Expect_Data_Error
           ("Integer_Value (bad_underscore_trailing) -> Data_Error", Try'Access);
      end;

      declare
         procedure Try is
            Unused : constant Integer :=
              Map.Integer_Value ("bad_underscore_double");
            pragma Unreferenced (Unused);
         begin
            null;
         end Try;
      begin
         Expect_Data_Error
           ("Integer_Value (bad_underscore_double) -> Data_Error", Try'Access);
      end;

      declare
         procedure Try is
            Unused : constant Integer := Map.Integer_Value ("bad_binary");
            pragma Unreferenced (Unused);
         begin
            null;
         end Try;
      begin
         Expect_Data_Error
           ("Integer_Value (bad_binary) -> Data_Error", Try'Access);
      end;

      -----------------------------------------------------------------
      --  Data_Error: numeric range overflow (Integer/Float only --
      --  the wider Long_* accessors on the same text succeed above).
      -----------------------------------------------------------------
      declare
         procedure Try is
            Unused : constant Integer := Map.Integer_Value ("big_int");
            pragma Unreferenced (Unused);
         begin
            null;
         end Try;
      begin
         Expect_Data_Error
           ("Integer_Value (big_int) -> Data_Error (overflow)", Try'Access);
      end;

      declare
         procedure Try is
            Unused : constant Float := Map.Float_Value ("float_overflow");
            pragma Unreferenced (Unused);
         begin
            null;
         end Try;
      begin
         Expect_Data_Error
           ("Float_Value (float_overflow) -> Data_Error (overflow)", Try'Access);
      end;

      -----------------------------------------------------------------
      --  Data_Error: numeric range overflow at the *widest* accessors
      --  too -- big_int/float_overflow above are chosen to overflow
      --  only the narrower Integer/Float, while still fitting
      --  Long_Long_Integer/Long_Float; huge_int/huge_float exceed even
      --  those.
      -----------------------------------------------------------------
      declare
         procedure Try is
            Unused : constant Long_Long_Integer :=
              Map.Long_Long_Integer_Value ("huge_int");
            pragma Unreferenced (Unused);
         begin
            null;
         end Try;
      begin
         Expect_Data_Error
           ("Long_Long_Integer_Value (huge_int) -> Data_Error (overflow)",
            Try'Access);
      end;

      declare
         procedure Try is
            Unused : constant Long_Float := Map.Long_Float_Value ("huge_float");
            pragma Unreferenced (Unused);
         begin
            null;
         end Try;
      begin
         Expect_Data_Error
           ("Long_Float_Value (huge_float) -> Data_Error (overflow)", Try'Access);
      end;

      -----------------------------------------------------------------
      --  Data_Error: value present but not a scalar (a mapping) --
      --  both the required and optional-with-default forms must
      --  still raise; a default only substitutes for absence.
      -----------------------------------------------------------------
      Check ("Required (not_scalar) is a mapping",
             Map.Required ("not_scalar").Is_Mapping);

      declare
         procedure Try is
            Unused : constant Integer := Map.Integer_Value ("not_scalar");
            pragma Unreferenced (Unused);
         begin
            null;
         end Try;
      begin
         Expect_Data_Error
           ("Integer_Value (not_scalar) -> Data_Error", Try'Access);
      end;

      declare
         procedure Try is
            Unused : constant Boolean :=
              Map.Boolean_Value ("not_scalar", True);
            pragma Unreferenced (Unused);
         begin
            null;
         end Try;
      begin
         Expect_Data_Error
           ("Boolean_Value (not_scalar, default) -> Data_Error " &
            "(default doesn't hide a shape error)", Try'Access);
      end;

      -----------------------------------------------------------------
      --  Optional (Map, Key, Default): key absent -> Default
      -----------------------------------------------------------------
      Check ("Integer_Value (absent, 99) = 99",
             Map.Integer_Value ("absent", 99) = 99);
      Check ("Long_Integer_Value (absent, 99) = 99",
             Map.Long_Integer_Value ("absent", 99) = 99);
      Check ("Long_Long_Integer_Value (absent, 99) = 99",
             Map.Long_Long_Integer_Value ("absent", 99) = 99);
      Check ("Float_Value (absent, 9.5) = 9.5",
             Map.Float_Value ("absent", 9.5) = 9.5);
      Check ("Long_Float_Value (absent, 9.5) = 9.5",
             Map.Long_Float_Value ("absent", 9.5) = 9.5);
      Check ("Boolean_Value (absent, True) = True",
             Map.Boolean_Value ("absent", True) = True);
      Check ("String_Value (absent, ""fallback"") = ""fallback""",
             Map.String_Value ("absent", "fallback") = "fallback");

      -----------------------------------------------------------------
      --  Optional (Map, Key, Default): key present -> actual value,
      --  not Default.
      -----------------------------------------------------------------
      Check ("Integer_Value (int_dec, 0) = 42",
             Map.Integer_Value ("int_dec", 0) = 42);
      Check ("Long_Integer_Value (int_dec, 0) = 42",
             Map.Long_Integer_Value ("int_dec", 0) = 42);
      Check ("Long_Long_Integer_Value (big_int, 0) = 5_000_000_000",
             Map.Long_Long_Integer_Value ("big_int", 0) = 5_000_000_000);
      Check ("Float_Value (float_val, 0.0) = 3.5",
             Map.Float_Value ("float_val", 0.0) = 3.5);
      Check ("Long_Float_Value (float_overflow, 0.0) > 1.0",
             Map.Long_Float_Value ("float_overflow", 0.0) > 1.0);
      Check ("Boolean_Value (bool_true, False) = True",
             Map.Boolean_Value ("bool_true", False) = True);
      Check ("String_Value (name, ""x"") = ""widget""",
             Map.String_Value ("name", "x") = "widget");
   end;

   Ada.Text_IO.New_Line;
   if Failures = 0 then
      Ada.Text_IO.Put_Line ("All checks passed.");
   else
      Ada.Text_IO.Put_Line (Integer'Image (Failures) & " check(s) failed.");
   end if;
end Test_Scalars;
