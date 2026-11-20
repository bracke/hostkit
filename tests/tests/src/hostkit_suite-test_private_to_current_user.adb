separate (Hostkit_Suite)
procedure Test_Private_To_Current_User
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Folder  : constant String := Ada.Directories.Compose (Scratch, "hostkit-private-to-me");
   Mine    : constant String := Ada.Directories.Compose (Folder, "mine");
   Shared  : constant String := Ada.Directories.Compose (Folder, "shared");
   Link    : constant String := Ada.Directories.Compose (Folder, "link");
   Private_Folder : constant String := Ada.Directories.Compose (Folder, "private-folder");
   Missing : constant String := Ada.Directories.Compose (Folder, "missing");
   use type Hostkit.Private_Paths.Create_Outcome;
begin
   if Ada.Directories.Exists (Folder) then
      Ada.Directories.Delete_Tree (Folder);
   end if;
   Ada.Directories.Create_Path (Folder);
   Assert (not Hostkit.Metadata.Private_To_Current_User (Missing), "nothing there is nobody's");

   --  A folder made private by Hostkit.Private_Paths is, on every host.
   Assert
     (Hostkit.Private_Paths.Create_Directory (Private_Folder) = Hostkit.Private_Paths.Created,
      "a private folder is made");
   Assert
     (Hostkit.Metadata.Private_To_Current_User (Private_Folder),
      "and it is this user's alone");

   if Hostkit.Host.Current /= Hostkit.Host.Windows then
      Write_File (Mine, "mine");
      Write_File (Shared, "shared");
      Assert (Hostkit.Metadata.Set_Permissions (Mine, 8#600#), "a file is made 0600");
      Assert (Hostkit.Metadata.Set_Permissions (Shared, 8#644#), "another 0644");
      Assert (Hostkit.Metadata.Private_To_Current_User (Mine), "a 0600 file of one's own is private");
      Assert (not Hostkit.Metadata.Private_To_Current_User (Shared), "a 0644 one is not: others may read it");
      Assert (Hostkit.Metadata.Set_Permissions (Shared, 8#620#), "the group may write it");
      Assert (not Hostkit.Metadata.Private_To_Current_User (Shared), "which is no more private");
   end if;

   --  A link is not followed: even one naming a private entry answers False.
   if Hostkit.Fs.Create_Link (Private_Folder, Link) then
      Assert (not Hostkit.Metadata.Private_To_Current_User (Link), "a link is nobody's private file");
      Assert (Hostkit.Fs.Delete_Link (Link), "the link goes");
   else
      Links_Refused ("Private_To_Current_User, a link");
   end if;
   Ada.Directories.Delete_Tree (Folder);
end Test_Private_To_Current_User;
