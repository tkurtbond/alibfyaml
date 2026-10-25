with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Interfaces.C;
with System;

package body Libfyaml.Documents.Styled is

   package C renames Interfaces.C;

   use type Thin.Fy_Node;

   function Malloc (Size : C.size_t) return System.Address
     with Import, Convention => C, External_Name => "malloc";

   --  The document frees Str (malloc's) when it is destroyed.
   function Fy_Node_Build_From_Malloc_String
     (Doc : Thin.Fy_Document; Str : System.Address; Len : C.size_t) return Thin.Fy_Node
     with Import, Convention => C, External_Name => "fy_node_build_from_malloc_string";

   LF : constant Character := Character'Val (16#0A#);
   HT : constant Character := Character'Val (16#09#);
   CR : constant Character := Character'Val (16#0D#);
   DEL : constant Character := Character'Val (16#7F#);

   function Code (T : String; I : Positive) return Natural is (Character'Pos (T (I)));

   --  The length of a character at T (I) that a plain, quoted or block
   --  scalar can't hold as itself, where YAML 1.1 readers break lines
   --  or strip it: NEL (C2 85), LS and PS (E2 80 A8, A9), the BOM (EF
   --  BB BF); 0 if T (I) starts none.
   function Special (T : String; I : Positive) return Natural is
   begin
      if I + 1 <= T'Last and then Code (T, I) = 16#C2# and then Code (T, I + 1) = 16#85# then
         return 2;
      elsif I + 2 <= T'Last and then Code (T, I) = 16#E2# and then Code (T, I + 1) = 16#80#
        and then Code (T, I + 2) in 16#A8# | 16#A9#
      then
         return 3;
      elsif I + 2 <= T'Last and then Code (T, I) = 16#EF# and then Code (T, I + 1) = 16#BB#
        and then Code (T, I + 2) = 16#BF#
      then
         return 3;
      else
         return 0;
      end if;
   end Special;

   --  True if T is well-formed UTF-8: no stray continuation byte, no
   --  truncated or overlong sequence, nothing past U+10FFFF, no
   --  surrogate.  libfyaml refuses anything else, printing a
   --  diagnostic.
   function Valid_Utf8 (T : String) return Boolean is
      I : Integer := T'First;
      K : Natural;
      B, Lo, Hi : Natural;
   begin
      while I <= T'Last loop
         B := Code (T, I);
         Lo := 16#80#;
         Hi := 16#BF#;
         if B < 16#80# then
            K := 0;
         elsif B in 16#C2# .. 16#DF# then
            K := 1;
         elsif B in 16#E0# .. 16#EF# then
            K := 2;
            if B = 16#E0# then
               Lo := 16#A0#;
            elsif B = 16#ED# then
               Hi := 16#9F#;
            end if;
         elsif B in 16#F0# .. 16#F4# then
            K := 3;
            if B = 16#F0# then
               Lo := 16#90#;
            elsif B = 16#F4# then
               Hi := 16#8F#;
            end if;
         else
            return False;
         end if;
         for J in 1 .. K loop
            if I + J > T'Last then
               return False;
            end if;
            B := Code (T, I + J);
            if J = 1 then
               if B not in Lo .. Hi then
                  return False;
               end if;
            elsif B not in 16#80# .. 16#BF# then
               return False;
            end if;
         end loop;
         I := I + K + 1;
      end loop;
      return True;
   end Valid_Utf8;

   function Is_Digit (Ch : Character) return Boolean is (Ch in '0' .. '9');

   function Is_Alnum (Ch : Character) return Boolean is
     (Is_Digit (Ch) or else Ch in 'A' .. 'Z' | 'a' .. 'z');

   --  True if T is sure to read back as itself written plain, in block
   --  and in flow context: deliberately narrower than YAML's rule.  It
   --  starts with a letter, a digit, a non-ASCII character, or a sign or
   --  point and a digit (-5, .5); it is one line with no control
   --  character, no leading or trailing blank, no ": ", " #" or trailing
   --  ":", none of ",[]{}", and isn't null's spelling (null, Null, NULL;
   --  "~" fails the first test).
   function Plain_Safe (T : String) return Boolean is
      Ch : Character;
   begin
      if T'Length = 0 then
         return False;
      end if;
      Ch := T (T'First);
      if not (Is_Alnum (Ch)
              or else (Character'Pos (Ch) >= 16#80# and then Special (T, T'First) = 0)
              or else (Ch in '-' | '+' | '.' and then T'Length > 1
                       and then Is_Digit (T (T'First + 1))))
      then
         return False;
      end if;
      if T (T'Last) in ' ' | ':' then
         return False;
      end if;
      for I in T'Range loop
         Ch := T (I);
         if Ch < ' ' or else Ch = DEL or else Ch in ',' | '[' | ']' | '{' | '}'
           or else Special (T, I) > 0
           or else (Ch = ':' and then T (I + 1) = ' ')  --  T (T'Last) isn't ':'
           or else (Ch = '#' and then T (I - 1) = ' ')  --  T (T'First) isn't '#'
         then
            return False;
         end if;
      end loop;
      return T /= "null" and then T /= "Null" and then T /= "NULL";
   end Plain_Safe;

   --  True if T can be a literal block (|): some character other than a
   --  line feed, and no control character but line feed and tab.
   function Literal_Safe (T : String) return Boolean is
      Content : Boolean := False;
   begin
      for I in T'Range loop
         if (T (I) < ' ' and then T (I) /= LF and then T (I) /= HT) or else T (I) = DEL
           or else Special (T, I) > 0
         then
            return False;
         end if;
         if T (I) /= LF then
            Content := True;
         end if;
      end loop;
      return Content;
   end Literal_Safe;

   Hex : constant String := "0123456789ABCDEF";

   --  T as a double-quoted scalar.
   function Quoted_Source (T : String) return String is
      S : Unbounded_String := To_Unbounded_String ("""");
      I : Integer := T'First;
      K : Natural;
      Ch : Character;
   begin
      while I <= T'Last loop
         Ch := T (I);
         K := Special (T, I);
         if K > 0 then
            if Code (T, I) = 16#C2# then
               Append (S, "\N");
            elsif Code (T, I) = 16#EF# then
               Append (S, "﻿");
            elsif Code (T, I + 2) = 16#A8# then
               Append (S, "\L");
            else
               Append (S, "\P");
            end if;
            I := I + K;
         else
            if Ch = '"' then
               Append (S, "\""");
            elsif Ch = '\' then
               Append (S, "\\");
            elsif Ch = LF then
               Append (S, "\n");
            elsif Ch = HT then
               Append (S, "\t");
            elsif Ch = CR then
               Append (S, "\r");
            elsif Ch < ' ' or else Ch = DEL then
               Append (S, "\x");
               Append (S, Hex (Character'Pos (Ch) / 16 + 1));
               Append (S, Hex (Character'Pos (Ch) mod 16 + 1));
            else
               Append (S, Ch);
            end if;
            I := I + 1;
         end if;
      end loop;
      Append (S, '"');
      return To_String (S);
   end Quoted_Source;

   --  T (Literal_Safe) as a literal block.  The indentation is given
   --  (|2), so a first line starting with blanks keeps them; the
   --  chomping keeps T's trailing line feeds exactly: none (-), one
   --  (clip) or more (+).
   function Literal_Source (T : String) return String is
      S : Unbounded_String := To_Unbounded_String ("|2");
      K : Natural := 0;
      Line_Start : Boolean := True;
   begin
      while K < T'Length and then T (T'Last - K) = LF loop
         K := K + 1;
      end loop;
      if K = 0 then
         Append (S, '-');
      elsif K > 1 then
         Append (S, '+');
      end if;
      Append (S, LF);
      for I in T'Range loop
         if Line_Start and then T (I) /= LF then
            Append (S, "  ");
         end if;
         Append (S, T (I));
         Line_Start := T (I) = LF;
      end loop;
      if K = 0 then
         Append (S, LF);
      end if;
      return To_String (S);
   end Literal_Source;

   --  A node of Doc parsed from Source, or null.  libfyaml owns the
   --  buffer once its parser has it, freeing it with Doc, or with the
   --  parser if the text doesn't parse.
   function Build (Doc : Document; Source : String) return Thin.Fy_Node is
      Buffer : constant System.Address := Malloc (C.size_t (Source'Length));
   begin
      if System."=" (Buffer, System.Null_Address) then
         raise Storage_Error with "malloc failed";
      end if;
      declare
         Target : String (1 .. Source'Length) with Import, Address => Buffer;
      begin
         Target := Source;
      end;
      return Fy_Node_Build_From_Malloc_String (Doc.Handle, Buffer, C.size_t (Source'Length));
   end Build;

   function Create_Styled_Scalar (Doc : in out Document; Text : String; S : Style)
     return Nodes.Node
   is
      H : Thin.Fy_Node;
   begin
      if not Valid_Utf8 (Text) then
         return Doc.Create_Scalar (Text);
      end if;
      if S = Plain and then Plain_Safe (Text) then
         H := Build (Doc, Text);
         if H = Thin.Null_Fy_Node then  --  a plain text Plain_Safe passed that libfyaml won't parse: none is known
            H := Build (Doc, Quoted_Source (Text));
         end if;
      elsif S = Literal and then Literal_Safe (Text) then
         H := Build (Doc, Literal_Source (Text));
      else
         H := Build (Doc, Quoted_Source (Text));
      end if;
      pragma Assert (H /= Thin.Null_Fy_Node);  --  double-quoted well-formed UTF-8 always parses
      return Nodes.Wrap (H, Doc.Owner);
   end Create_Styled_Scalar;

end Libfyaml.Documents.Styled;
