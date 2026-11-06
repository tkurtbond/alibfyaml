package body Libfyaml is

   function Without_Location (Message : String) return String is
      Colons : Natural := 0;
   begin
      if not Has_Location (Message) then
         return Message;
      end if;
      for I in Message'Range loop
         case Message (I) is
            when '0' .. '9' =>
               null;
            when ':' =>
               Colons := Colons + 1;
               if Colons = 2 then
                  if I < Message'Last and then Message (I + 1) = ' ' then
                     return Message (I + 2 .. Message'Last);
                  end if;
                  return Message (I + 1 .. Message'Last);
               end if;
            when others =>
               return Message;
         end case;
      end loop;
      return Message;
   end Without_Location;

end Libfyaml;
