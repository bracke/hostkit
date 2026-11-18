separate (Hostkit.Fs)
function Delete_Link (Path : String) return Boolean is
   function C_Unlink (Path : Interfaces.C.Strings.chars_ptr) return Interfaces.C.int
     with Import => True, Convention => C, External_Name => "unlink";
begin
   if not Is_Link (Path) then
      return False;
   end if;

   declare
      C_Path : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Path);
      Status : constant Interfaces.C.int := C_Unlink (C_Path);
   begin
      Interfaces.C.Strings.Free (C_Path);
      return Status = 0;
   end;
exception
   when others =>
      return False;
end Delete_Link;
