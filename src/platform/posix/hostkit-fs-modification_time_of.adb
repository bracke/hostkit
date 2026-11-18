separate (Hostkit.Fs)
function Modification_Time_Of (Path : String; Follow_Links : Boolean := True) return Ada.Calendar.Time is
   Info : constant Entry_Record := Stat_Entry (Path, Follow_Links, Want_Type + Want_Mtime);
   Kind : constant C_U16 := Info.Mode and File_Type_Mask;
begin
   if Kind /= S_IFREG and then Kind /= S_IFDIR and then (Follow_Links or else Kind /= S_IFLNK) then
      raise Ada.Directories.Name_Error with Path & ": no file or directory";
   end if;
   return Hostkit.Fs.Instants.From_Unix
     (Interfaces.Integer_64 (Info.Modified_Time.Seconds), Interfaces.Integer_64 (Info.Modified_Time.Nanoseconds));
end Modification_Time_Of;
