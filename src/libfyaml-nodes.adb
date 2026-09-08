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

   function Is_Scalar (N : Node) return Boolean is
     (Thin.fy_node_get_type (N.Handle) = Thin.FYNT_SCALAR);

   function Is_Sequence (N : Node) return Boolean is
     (Thin.fy_node_get_type (N.Handle) = Thin.FYNT_SEQUENCE);

   function Is_Mapping (N : Node) return Boolean is
     (Thin.fy_node_get_type (N.Handle) = Thin.FYNT_MAPPING);

   function Is_Null_Value (N : Node) return Boolean is
     (Boolean (Thin.fy_node_is_null (N.Handle)));

   function Scalar_Value (N : Node) return String is
      Len : aliased C.size_t;
      Ptr : constant CS.chars_ptr := Thin.fy_node_get_scalar (N.Handle, Len'Access);
   begin
      if Ptr = CS.Null_Ptr then
         return "";
      end if;
      return CS.Value (Ptr, Len);
   end Scalar_Value;

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
