package body Hostkit.Win32 is
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned_long;

   function Is_Held_Link (Object : HANDLE; Attributes : DWORD; Error : out DWORD) return Boolean is
      Tag_Info : aliased Attribute_Tag_Info;
   begin
      Error := 0;
      if (Attributes and File_Attribute_Reparse_Point) = 0 then
         return False;
      elsif Get_File_Information_Ex
              (Object, File_Attribute_Tag_Info_Class, Tag_Info'Address, DWORD (Attribute_Tag_Info'Size / 8)) = 0
      then
         Error := Get_Last_Error;
         return True;
      elsif Is_Link_Tag (Tag_Info.Reparse_Tag) then
         Error := Error_Stopped_On_Symlink;
         return True;
      end if;
      return False;
   end Is_Held_Link;

end Hostkit.Win32;
