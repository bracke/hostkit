separate (Hostkit.Fs)
function Entry_Is_Absent (Path : String) return Boolean is
begin
   declare
      Unused : constant Entry_Record := Stat_Entry (Path, False, Want_Type);
   begin
      return False;
   end;
exception
   when Ada.Directories.Name_Error =>
      return True;
end Entry_Is_Absent;
