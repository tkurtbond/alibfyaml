with Ada.Strings.Fixed;
with Interfaces.C.Strings;
with System;

package body Libfyaml.Nodes is

   package C renames Interfaces.C;
   package CS renames Interfaces.C.Strings;

   use type C.int;
   use type CS.chars_ptr;
   use type Thin.Fy_Node;
   use type Thin.Fy_Node_Pair;
   use type Thin.Fy_Node_Type;

   ------------------------------------------------------------------
   --  YAML 1.2 core schema scalar-shape validation, private to     --
   --  this body. See Libfyaml.Nodes' spec for the public accessors --
   --  that use these.                                              --
   ------------------------------------------------------------------

   function Trimmed (S : String) return String is
     (Ada.Strings.Fixed.Trim (S, Ada.Strings.Both));

   function Strip_Sign (S : String) return String is
     (if S'Length > 0 and then (S (S'First) = '+' or else S (S'First) = '-')
      then S (S'First + 1 .. S'Last)
      else S);

   type Digit_Predicate is not null access function (C : Character) return Boolean;

   function Is_Dec_Digit (C : Character) return Boolean is (C in '0' .. '9');
   function Is_Hex_Digit (C : Character) return Boolean is
     (C in '0' .. '9' | 'a' .. 'f' | 'A' .. 'F');
   function Is_Oct_Digit (C : Character) return Boolean is (C in '0' .. '7');
   function Is_Bin_Digit (C : Character) return Boolean is (C in '0' .. '1');

   --  Length of the maximal run starting at S (From) matching the
   --  grammar digit ('_' digit)* under the given digit predicate (0 if
   --  S (From) itself isn't a digit, or From is past S'Last). A single
   --  underscore is accepted only strictly between two digits -- never
   --  leading, trailing, or doubled -- which is exactly Ada's own
   --  numeral syntax (RM 2.1: numeral ::= digit {['_'] digit}), so the
   --  matched text (underscores included) can be handed to T'Value
   --  verbatim: this is what lets alibfyaml accept "1_000_000" or
   --  "0xFF_FF" as an extension (see README.md) without any separate
   --  underscore-stripping step.
   function Digit_Run_Length
     (S : String; From : Positive; Is_Digit : Digit_Predicate) return Natural
   is
      I : Positive := From;
   begin
      if I > S'Last or else not Is_Digit (S (I)) then
         return 0;
      end if;
      I := I + 1;
      loop
         exit when I > S'Last;
         if Is_Digit (S (I)) then
            I := I + 1;
         elsif S (I) = '_' and then I + 1 <= S'Last and then Is_Digit (S (I + 1)) then
            I := I + 2;
         else
            exit;
         end if;
      end loop;
      return I - From;
   end Digit_Run_Length;

   function Is_Digit_Run (S : String) return Boolean is
     (S'Length > 0
      and then Digit_Run_Length (S, S'First, Is_Dec_Digit'Access) = S'Length);

   function Is_Hex_Digit_Run (S : String) return Boolean is
     (S'Length > 0
      and then Digit_Run_Length (S, S'First, Is_Hex_Digit'Access) = S'Length);

   function Is_Octal_Digit_Run (S : String) return Boolean is
     (S'Length > 0
      and then Digit_Run_Length (S, S'First, Is_Oct_Digit'Access) = S'Length);

   function Is_Binary_Digit_Run (S : String) return Boolean is
     (S'Length > 0
      and then Digit_Run_Length (S, S'First, Is_Bin_Digit'Access) = S'Length);

   --  "0b" (binary) is a documented alibfyaml extension, not part of
   --  YAML 1.2 core schema -- see README.md. (libfyaml's own generics
   --  layer, which alibfyaml does not bind, also recognizes "0b" but
   --  only under an explicit YAML 1.1 schema selection.)
   function Is_Integer_Text (S : String) return Boolean is
      B : constant String := Strip_Sign (S);
   begin
      if B'Length >= 2 and then B (B'First .. B'First + 1) = "0x" then
         return Is_Hex_Digit_Run (B (B'First + 2 .. B'Last));
      elsif B'Length >= 2 and then B (B'First .. B'First + 1) = "0o" then
         return Is_Octal_Digit_Run (B (B'First + 2 .. B'Last));
      elsif B'Length >= 2 and then B (B'First .. B'First + 1) = "0b" then
         return Is_Binary_Digit_Run (B (B'First + 2 .. B'Last));
      else
         return Is_Digit_Run (B);
      end if;
   end Is_Integer_Text;

   --  YAML 1.2 core schema float grammar, restricted to the forms Ada's
   --  own real-literal syntax accepts directly (a digit is required both
   --  before and after any '.', so bare ".5" or trailing "3." are not
   --  accepted -- both are rare in practice and this keeps the
   --  implementation delegating straight to Float'Value/Long_Float'Value
   --  once the shape is confirmed, rather than reformatting the text).
   function Is_Float_Text (S : String) return Boolean is
      B                        : constant String := Strip_Sign (S);
      Pos                      : Positive;
      Int_Len, Frac_Len, Exp_Len : Natural;
   begin
      if B'Length = 0 then
         return False;
      end if;
      Pos := B'First;
      Int_Len := Digit_Run_Length (B, Pos, Is_Dec_Digit'Access);
      if Int_Len = 0 then
         return False;
      end if;
      Pos := Pos + Int_Len;

      if Pos <= B'Last and then B (Pos) = '.' then
         Pos := Pos + 1;
         Frac_Len := Digit_Run_Length (B, Pos, Is_Dec_Digit'Access);
         if Frac_Len = 0 then
            return False;
         end if;
         Pos := Pos + Frac_Len;
      end if;

      if Pos <= B'Last and then (B (Pos) = 'e' or else B (Pos) = 'E') then
         Pos := Pos + 1;
         if Pos <= B'Last and then (B (Pos) = '+' or else B (Pos) = '-') then
            Pos := Pos + 1;
         end if;
         Exp_Len := Digit_Run_Length (B, Pos, Is_Dec_Digit'Access);
         if Exp_Len = 0 then
            return False;
         end if;
         Pos := Pos + Exp_Len;
      end if;

      return Pos > B'Last;
   end Is_Float_Text;

   function Is_Boolean_Text (S : String) return Boolean is
     (S in "true" | "True" | "TRUE" | "false" | "False" | "FALSE");

   --  YAML 1.2 core schema null spellings. Deliberately excludes "":
   --  an explicit quoted "" is a deliberate empty *string*, not null;
   --  the unquoted-omitted case (e.g. "key:" with nothing after) is
   --  handled separately, by libfyaml's own fy_node_is_null, which
   --  distinguishes it correctly from an explicit "" at the token
   --  level rather than by text content.
   function Is_Null_Text (S : String) return Boolean is
     (S = "~" or else S = "null" or else S = "Null" or else S = "NULL");

   --  Rewrite a validated "0x.."/"0o.."/"0b.." integer literal into the
   --  Ada based-literal form (e.g. "0x1A" -> "16#1A#") that
   --  Integer'Value and friends accept; a plain decimal literal (with
   --  or without underscore separators -- Ada's own numeral syntax
   --  already accepts those) passes through as-is.
   function Integer_Literal_Text (S : String) return String is
      Sign : constant String :=
        (if S'Length > 0 and then (S (S'First) = '+' or else S (S'First) = '-')
         then S (S'First .. S'First)
         else "");
      Rest : constant String :=
        (if Sign'Length > 0 then S (S'First + 1 .. S'Last) else S);
   begin
      if Rest'Length >= 2 and then Rest (Rest'First .. Rest'First + 1) = "0x" then
         return Sign & "16#" & Rest (Rest'First + 2 .. Rest'Last) & "#";
      elsif Rest'Length >= 2 and then Rest (Rest'First .. Rest'First + 1) = "0o" then
         return Sign & "8#" & Rest (Rest'First + 2 .. Rest'Last) & "#";
      elsif Rest'Length >= 2 and then Rest (Rest'First .. Rest'First + 1) = "0b" then
         return Sign & "2#" & Rest (Rest'First + 2 .. Rest'Last) & "#";
      else
         return S;
      end if;
   end Integer_Literal_Text;

   function Is_Valid (N : Node) return Boolean is
     (N.Handle /= Thin.Null_Fy_Node);

   function Kind (N : Node) return Node_Kind is
   begin
      case Thin.fy_node_get_type (N.Handle) is
         when Thin.FYNT_SCALAR   => return Scalar_Node;
         when Thin.FYNT_SEQUENCE => return Sequence_Node;
         when Thin.FYNT_MAPPING  => return Mapping_Node;
      end case;
   end Kind;

   --  Expressed in terms of Kind (one fy_node_get_type call) rather than
   --  each repeating its own, to avoid a redundant FFI round-trip when a
   --  caller checks shape via these rather than Kind directly.
   function Is_Scalar (N : Node) return Boolean is (Kind (N) = Scalar_Node);

   function Is_Sequence (N : Node) return Boolean is (Kind (N) = Sequence_Node);

   function Is_Mapping (N : Node) return Boolean is (Kind (N) = Mapping_Node);

   function Scalar_Value (N : Node) return String is
      Len : aliased C.size_t;
      Ptr : constant CS.chars_ptr := Thin.fy_node_get_scalar (N.Handle, Len'Access);
   begin
      if Ptr = CS.Null_Ptr then
         return "";
      end if;
      return CS.Value (Ptr, Len);
   end Scalar_Value;

   function Is_Null_Value (N : Node) return Boolean is
     (Boolean (Thin.fy_node_is_null (N.Handle))
      or else (Is_Scalar (N) and then Is_Null_Text (Trimmed (Scalar_Value (N)))));

   function Is_Integer (N : Node) return Boolean is
     (Is_Integer_Text (Trimmed (Scalar_Value (N))));

   function Is_Float (N : Node) return Boolean is
     (Is_Float_Text (Trimmed (Scalar_Value (N))));

   function Is_Boolean (N : Node) return Boolean is
     (Is_Boolean_Text (Trimmed (Scalar_Value (N))));

   function Integer_Value (N : Node) return Integer is
      Text : constant String := Trimmed (Scalar_Value (N));
   begin
      if not Is_Integer_Text (Text) then
         raise Libfyaml.Data_Error with "not a valid integer: """ & Text & '"';
      end if;
      begin
         return Integer'Value (Integer_Literal_Text (Text));
      exception
         when Constraint_Error =>
            raise Libfyaml.Data_Error with "integer out of range: """ & Text & '"';
      end;
   end Integer_Value;

   function Long_Integer_Value (N : Node) return Long_Integer is
      Text : constant String := Trimmed (Scalar_Value (N));
   begin
      if not Is_Integer_Text (Text) then
         raise Libfyaml.Data_Error with "not a valid integer: """ & Text & '"';
      end if;
      begin
         return Long_Integer'Value (Integer_Literal_Text (Text));
      exception
         when Constraint_Error =>
            raise Libfyaml.Data_Error with "integer out of range: """ & Text & '"';
      end;
   end Long_Integer_Value;

   function Long_Long_Integer_Value (N : Node) return Long_Long_Integer is
      Text : constant String := Trimmed (Scalar_Value (N));
   begin
      if not Is_Integer_Text (Text) then
         raise Libfyaml.Data_Error with "not a valid integer: """ & Text & '"';
      end if;
      begin
         return Long_Long_Integer'Value (Integer_Literal_Text (Text));
      exception
         when Constraint_Error =>
            raise Libfyaml.Data_Error with "integer out of range: """ & Text & '"';
      end;
   end Long_Long_Integer_Value;

   function Float_Value (N : Node) return Float is
      Text : constant String := Trimmed (Scalar_Value (N));
   begin
      if not Is_Float_Text (Text) then
         raise Libfyaml.Data_Error with "not a valid float: """ & Text & '"';
      end if;
      begin
         declare
            Result : constant Float := Float'Value (Text);
         begin
            --  Float'Value does not raise Constraint_Error for a literal
            --  that overflows Float's finite range -- on this platform it
            --  silently produces an IEEE infinity instead, which 'Valid
            --  (unlike a bare range comparison) reliably detects. Checked
            --  here, before the result is returned anywhere, rather than
            --  relying on Constraint_Error being raised at some later,
            --  compiler/switch-dependent point.
            if not Result'Valid then
               raise Libfyaml.Data_Error with
                 "float out of range: """ & Text & '"';
            end if;
            return Result;
         end;
      exception
         when Constraint_Error =>
            raise Libfyaml.Data_Error with "float out of range: """ & Text & '"';
      end;
   end Float_Value;

   function Long_Float_Value (N : Node) return Long_Float is
      Text : constant String := Trimmed (Scalar_Value (N));
   begin
      if not Is_Float_Text (Text) then
         raise Libfyaml.Data_Error with "not a valid float: """ & Text & '"';
      end if;
      begin
         declare
            Result : constant Long_Float := Long_Float'Value (Text);
         begin
            if not Result'Valid then
               raise Libfyaml.Data_Error with
                 "float out of range: """ & Text & '"';
            end if;
            return Result;
         end;
      exception
         when Constraint_Error =>
            raise Libfyaml.Data_Error with "float out of range: """ & Text & '"';
      end;
   end Long_Float_Value;

   function Boolean_Value (N : Node) return Boolean is
      Text : constant String := Trimmed (Scalar_Value (N));
   begin
      if Text = "true" or else Text = "True" or else Text = "TRUE" then
         return True;
      elsif Text = "false" or else Text = "False" or else Text = "FALSE" then
         return False;
      else
         raise Libfyaml.Data_Error with "not a valid boolean: """ & Text & '"';
      end if;
   end Boolean_Value;

   function Length (N : Node) return Natural is
   begin
      if Is_Sequence (N) then
         return Natural (Thin.fy_node_sequence_item_count (N.Handle));
      else
         return Natural (Thin.fy_node_mapping_item_count (N.Handle));
      end if;
   end Length;

   function Item (N : Node; Index : Positive) return Node is
      Result : constant Thin.Fy_Node :=
        Thin.fy_node_sequence_get_by_index (N.Handle, C.int (Index) - 1);
   begin
      return Wrap (Result);
   end Item;

   procedure Append (Seq : Node; Item : Node) is
      Status : constant C.int :=
        Thin.fy_node_sequence_append (Seq.Handle, Raw (Item));
   begin
      if Status /= 0 then
         raise Program_Error with "fy_node_sequence_append failed";
      end if;
   end Append;

   procedure Iterate
     (Seq : Node; Visit : not null access procedure (Element : Node))
   is
      Prev : aliased System.Address := System.Null_Address;
      Cur  : Thin.Fy_Node;
   begin
      loop
         Cur := Thin.fy_node_sequence_iterate (Seq.Handle, Prev'Access);
         exit when Cur = Thin.Null_Fy_Node;
         Visit (Wrap (Cur));
      end loop;
   end Iterate;

   function Value (Map : Node; Key : String) return Node is
      C_Key  : CS.chars_ptr := CS.New_String (Key);
      Result : Thin.Fy_Node;
   begin
      Result := Thin.fy_node_mapping_lookup_value_by_string
        (Map.Handle, C_Key, C.size_t (Key'Length));
      CS.Free (C_Key);
      return Wrap (Result);
   end Value;

   function Has_Key (Map : Node; Key : String) return Boolean is
     (Is_Valid (Value (Map, Key)));

   procedure Append_Pair (Map : Node; Key : Node; Value : Node) is
      Status : constant C.int :=
        Thin.fy_node_mapping_append (Map.Handle, Raw (Key), Raw (Value));
   begin
      if Status /= 0 then
         raise Program_Error with "fy_node_mapping_append failed";
      end if;
   end Append_Pair;

   procedure Iterate
     (Map : Node; Visit : not null access procedure (Key, Value : Node))
   is
      Prev : aliased System.Address := System.Null_Address;
      Cur  : Thin.Fy_Node_Pair;
   begin
      loop
         Cur := Thin.fy_node_mapping_iterate (Map.Handle, Prev'Access);
         exit when Cur = Thin.Null_Fy_Node_Pair;
         Visit
           (Wrap (Thin.fy_node_pair_key (Cur)),
            Wrap (Thin.fy_node_pair_value (Cur)));
      end loop;
   end Iterate;

   function Required (Map : Node; Key : String) return Node is
      Result : constant Node := Value (Map, Key);
   begin
      if not Is_Valid (Result) then
         raise Libfyaml.Missing_Key with "missing required key """ & Key & '"';
      end if;
      return Result;
   end Required;

   --  Like Required, but also confirms the found value is a scalar,
   --  raising Libfyaml.Data_Error (not a Pre-condition failure) if it's
   --  a sequence/mapping instead -- used by the typed (Map, Key)
   --  accessors below, which promise Data_Error for any shape problem.
   function Required_Scalar (Map : Node; Key : String) return Node is
      Result : constant Node := Required (Map, Key);
   begin
      if not Is_Scalar (Result) then
         raise Libfyaml.Data_Error with
           "key """ & Key & """ is not a scalar value";
      end if;
      return Result;
   end Required_Scalar;

   function Integer_Value (Map : Node; Key : String) return Integer is
     (Integer_Value (Required_Scalar (Map, Key)));

   function Long_Integer_Value (Map : Node; Key : String) return Long_Integer is
     (Long_Integer_Value (Required_Scalar (Map, Key)));

   function Long_Long_Integer_Value
     (Map : Node; Key : String) return Long_Long_Integer is
     (Long_Long_Integer_Value (Required_Scalar (Map, Key)));

   function Float_Value (Map : Node; Key : String) return Float is
     (Float_Value (Required_Scalar (Map, Key)));

   function Long_Float_Value (Map : Node; Key : String) return Long_Float is
     (Long_Float_Value (Required_Scalar (Map, Key)));

   function Boolean_Value (Map : Node; Key : String) return Boolean is
     (Boolean_Value (Required_Scalar (Map, Key)));

   function String_Value (Map : Node; Key : String) return String is
     (Scalar_Value (Required_Scalar (Map, Key)));

   function Integer_Value
     (Map : Node; Key : String; Default : Integer) return Integer
   is
      V : constant Node := Value (Map, Key);
   begin
      if not Is_Valid (V) then
         return Default;
      end if;
      if not Is_Scalar (V) then
         raise Libfyaml.Data_Error with
           "key """ & Key & """ is not a scalar value";
      end if;
      return Integer_Value (V);
   end Integer_Value;

   function Long_Integer_Value
     (Map : Node; Key : String; Default : Long_Integer) return Long_Integer
   is
      V : constant Node := Value (Map, Key);
   begin
      if not Is_Valid (V) then
         return Default;
      end if;
      if not Is_Scalar (V) then
         raise Libfyaml.Data_Error with
           "key """ & Key & """ is not a scalar value";
      end if;
      return Long_Integer_Value (V);
   end Long_Integer_Value;

   function Long_Long_Integer_Value
     (Map : Node; Key : String; Default : Long_Long_Integer)
      return Long_Long_Integer
   is
      V : constant Node := Value (Map, Key);
   begin
      if not Is_Valid (V) then
         return Default;
      end if;
      if not Is_Scalar (V) then
         raise Libfyaml.Data_Error with
           "key """ & Key & """ is not a scalar value";
      end if;
      return Long_Long_Integer_Value (V);
   end Long_Long_Integer_Value;

   function Float_Value
     (Map : Node; Key : String; Default : Float) return Float
   is
      V : constant Node := Value (Map, Key);
   begin
      if not Is_Valid (V) then
         return Default;
      end if;
      if not Is_Scalar (V) then
         raise Libfyaml.Data_Error with
           "key """ & Key & """ is not a scalar value";
      end if;
      return Float_Value (V);
   end Float_Value;

   function Long_Float_Value
     (Map : Node; Key : String; Default : Long_Float) return Long_Float
   is
      V : constant Node := Value (Map, Key);
   begin
      if not Is_Valid (V) then
         return Default;
      end if;
      if not Is_Scalar (V) then
         raise Libfyaml.Data_Error with
           "key """ & Key & """ is not a scalar value";
      end if;
      return Long_Float_Value (V);
   end Long_Float_Value;

   function Boolean_Value
     (Map : Node; Key : String; Default : Boolean) return Boolean
   is
      V : constant Node := Value (Map, Key);
   begin
      if not Is_Valid (V) then
         return Default;
      end if;
      if not Is_Scalar (V) then
         raise Libfyaml.Data_Error with
           "key """ & Key & """ is not a scalar value";
      end if;
      return Boolean_Value (V);
   end Boolean_Value;

   function String_Value
     (Map : Node; Key : String; Default : String) return String
   is
      V : constant Node := Value (Map, Key);
   begin
      if not Is_Valid (V) then
         return Default;
      end if;
      if not Is_Scalar (V) then
         raise Libfyaml.Data_Error with
           "key """ & Key & """ is not a scalar value";
      end if;
      return Scalar_Value (V);
   end String_Value;

   function By_Path (N : Node; Path : String) return Node is
      C_Path : CS.chars_ptr := CS.New_String (Path);
      Result : Thin.Fy_Node;
   begin
      Result := Thin.fy_node_by_path
        (N.Handle, C_Path, C.size_t (Path'Length), Thin.FYNWF_DONT_FOLLOW);
      CS.Free (C_Path);
      return Wrap (Result);
   end By_Path;

end Libfyaml.Nodes;
