separate (Hostkit.Fs)
function Make_Private (Path : String) return Boolean is
   use type Ada.Directories.File_Kind;

   function C_Chmod (Path : Interfaces.C.Strings.chars_ptr; Mode : Interfaces.C.int)
     return Interfaces.C.int
     with Import => True, Convention => C, External_Name => "chmod";

   C_Path : Interfaces.C.Strings.chars_ptr;
   Result : Interfaces.C.int;
   Mode   : Interfaces.C.int;
begin
   if not Ada.Directories.Exists (Path) then
      return False;
   end if;

   case Ada.Directories.Kind (Path) is
      when Ada.Directories.Ordinary_File =>
         Mode := 8#600#;
      when Ada.Directories.Directory =>
         --  A directory the owner cannot enter is not private, it is unusable.
         Mode := 8#700#;
      when others =>
         return False;
   end case;

   C_Path := Interfaces.C.Strings.New_String (Path);
   Result := C_Chmod (C_Path, Mode);
   Interfaces.C.Strings.Free (C_Path);
   return Result = 0;
exception
   when others =>
      return False;
end Make_Private;
