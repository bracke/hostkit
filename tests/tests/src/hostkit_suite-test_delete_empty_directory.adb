separate (Hostkit_Suite)
procedure Test_Delete_Empty_Directory
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Empty  : constant String := Ada.Directories.Compose (Scratch, "hostkit-empty-dir");
   Full   : constant String := Ada.Directories.Compose (Scratch, "hostkit-full-dir");
   Inside : constant String := Ada.Directories.Compose (Full, "kept");
   Link   : constant String := Ada.Directories.Compose (Scratch, "hostkit-dir-link");
   E_Not_Dir : constant := 20;
   --  ENOTDIR is 20 on Linux, macOS and in the Windows runtime alike.
begin
   Ada.Directories.Create_Path (Empty);
   Ada.Directories.Create_Path (Inside);
   Assert (Hostkit.Fs.Delete_Empty_Directory (Empty), "an empty directory is removed");
   Assert (not Ada.Directories.Exists (Empty), "and is gone");
   Assert (not Hostkit.Fs.Delete_Empty_Directory (Full), "a directory with something in it is refused");
   Assert (Ada.Directories.Exists (Inside), "and what is in it is untouched");
   Assert (not Hostkit.Fs.Delete_Empty_Directory (Empty), "a missing directory is refused, not raised");

   --  A link to an empty folder is no directory to remove, as rmdir says;
   --  on Windows RemoveDirectoryW would have taken the link.
   Ada.Directories.Create_Path (Empty);
   if Hostkit.Fs.Is_Link (Link) then
      Assert (Hostkit.Fs.Delete_Link (Link), "a leftover link is removed");
   end if;
   if Hostkit.Fs.Create_Link (Empty, Link) then
      GNAT.OS_Lib.Set_Errno (0);
      Assert (not Hostkit.Fs.Delete_Empty_Directory (Link), "a link to an empty directory is refused");
      Assert
        (GNAT.OS_Lib.Errno = E_Not_Dir,
         "and the refusal is ENOTDIR, as rmdir's is:" & Integer'Image (GNAT.OS_Lib.Errno));
      Assert (Hostkit.Fs.Is_Link (Link), "the link is still there");
      Assert (Ada.Directories.Exists (Empty), "and so is the folder it names");
      Assert (Hostkit.Fs.Delete_Link (Link), "the link goes as a link");
   else
      Links_Refused ("Delete_Empty_Directory, a link to a folder");
   end if;
   Assert (Hostkit.Fs.Delete_Empty_Directory (Empty), "the folder itself is removed");
   Ada.Directories.Delete_Tree (Full);
end Test_Delete_Empty_Directory;
