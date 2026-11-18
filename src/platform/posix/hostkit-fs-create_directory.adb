separate (Hostkit.Fs)
function Create_Directory (Path : String) return Boolean is
   function C_Mkdir (Path : Interfaces.C.Strings.chars_ptr; Mode : C_Mode) return C_Int
     with Import => True, Convention => C, External_Name => "mkdir";
begin
   if Path = "" or else (for some C of Path => C = ASCII.NUL) then
      return False;
   end if;
   declare
      C_Path : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      Status : constant C_Int := C_Mkdir (C_Path, 8#777#);
   begin
      Interfaces.C.Strings.Free (C_Path);
      return Status = 0;
   end;
exception
   when others =>
      return False;
end Create_Directory;
