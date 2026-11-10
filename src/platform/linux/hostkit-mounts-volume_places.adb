separate (Hostkit.Mounts)
function Volume_Places return Volume_Place_List is
   use Ada.Strings.Unbounded;
begin
   --  The administrator's and udisks' mount folders; /run/media holds one
   --  folder of mounts per user.
   return
     [(To_Unbounded_String ("/mnt"), Volumes_Folder),
      (To_Unbounded_String ("/media"), Volumes_Folder),
      (To_Unbounded_String ("/run/media"), User_Volumes_Folder)];
end Volume_Places;
