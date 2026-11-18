separate (Hostkit.Fs)
function Delete_File (Path : String) return Boolean is
begin
   if Path = "" or else (for some C of Path => C = ASCII.NUL) then
      return False;
   end if;
   declare
      C_Path : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      Status : constant C_Int := C_Unlink (C_Path);
   begin
      Interfaces.C.Strings.Free (C_Path);
      return Status = 0;
   end;
exception
   when others =>
      return False;
end Delete_File;
