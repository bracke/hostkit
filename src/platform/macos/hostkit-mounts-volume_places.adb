separate (Hostkit.Mounts)
function Volume_Places return Volume_Place_List is
   use Ada.Strings.Unbounded;
begin
   return
     [(To_Unbounded_String ("/Volumes"), Volumes_Folder),
      (To_Unbounded_String ("/System/Volumes"), Volumes_Folder)];
end Volume_Places;
