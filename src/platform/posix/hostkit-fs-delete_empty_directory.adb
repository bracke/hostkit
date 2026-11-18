separate (Hostkit.Fs)
function Delete_Empty_Directory (Path : String) return Boolean is
begin
   Ada.Directories.Delete_Directory (Path);
   return True;
exception
   when others =>
      return False;
end Delete_Empty_Directory;
