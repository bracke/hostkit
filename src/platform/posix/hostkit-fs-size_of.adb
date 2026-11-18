separate (Hostkit.Fs)
function Size_Of (Path : String; Follow_Links : Boolean := True) return Ada.Directories.File_Size is
   Info : constant Entry_Record := Stat_Entry (Path, Follow_Links, Want_Type + Want_Size);
   Kind : constant C_U16 := Info.Mode and File_Type_Mask;
begin
   if Kind /= S_IFREG and then (Follow_Links or else Kind /= S_IFLNK) then
      raise Ada.Directories.Name_Error with Path & ": no ordinary file";
   end if;
   return Ada.Directories.File_Size (Info.Size);
end Size_Of;
