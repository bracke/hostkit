separate (Hostkit_Suite)
procedure Test_Delete_Tree_Stays_On_Its_Mount
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type Hostkit.Fs.Delete_Tree_Outcome;
   package Abi renames Hostkit.Linux_Abi;
   --  EACCES and EXDEV are 13 and 18 on Linux and macOS alike.
   E_Acces : constant := 13;
   E_Xdev  : constant := 18;
   Root    : constant String := Ada.Directories.Compose (Scratch, "hk-delete-locked");
   Locked  : constant String := Ada.Directories.Compose (Root, "locked");
   Parent  : Abi.Statx_Record;
   Child   : Abi.Statx_Record;
begin
   --  The rule the Linux walk applies to each entry, pure, so on every host.
   --  Without mount ids (before Linux 5.8): the device that holds the entry
   --  (stx_dev), never the one a device file stands for (stx_rdev).
   Parent.Device_Major := 8;
   Parent.Device_Minor := 1;
   Child := Parent;
   Assert (not Abi.Crosses_Mount (Parent, Child), "an entry on its folder's device stays on the mount");
   Child.Special_Device_Major := 1;
   Child.Special_Device_Minor := 3;
   Assert (not Abi.Crosses_Mount (Parent, Child), "a device file is on its folder's mount, whatever it stands for");
   Child := Parent;
   Child.Device_Minor := 2;
   Assert (Abi.Crosses_Mount (Parent, Child), "an entry on another device is another mount");
   Parent.Mount_Id := 3;
   Child.Mount_Id := 3;
   Assert (Abi.Crosses_Mount (Parent, Child), "mount ids a kernel did not give are not read");
   --  With them, they decide.
   Parent.Mask := Abi.Statx_Mnt_Id;
   Child.Mask := Abi.Statx_Mnt_Id;
   Assert
     (not Abi.Crosses_Mount (Parent, Child),
      "a device of its own on the folder's mount (a btrfs subvolume, an overlayfs file) is on that mount");
   Child.Device_Minor := 1;
   Child.Mount_Id := 7;
   Assert (Abi.Crosses_Mount (Parent, Child), "a bind mount, the same device mounted again, is another mount");

   --  /proc is always a filesystem mounted on its own: refused before
   --  anything in it is touched, the tree's own root held to the rule too.
   if Hostkit.Host.Current = Hostkit.Host.Linux then
      GNAT.OS_Lib.Set_Errno (0);
      Assert
        (Hostkit.Fs.Delete_Tree_No_Follow ("/proc") = Hostkit.Fs.Tree_Delete_Failed,
         "a tree on another mount than its folder is refused");
      Assert
        (GNAT.OS_Lib.Errno = E_Xdev,
         "and the refusal is EXDEV:" & Integer'Image (GNAT.OS_Lib.Errno));
   end if;

   --  A folder in the tree that the walk may not open (mode 0): the delete
   --  fails with open's EACCES. Whoever bypasses permissions opens it anyway,
   --  so that half is for an ordinary user, and Windows has no mode 0 to
   --  refuse a delete with.
   if Hostkit.Host.Current in Hostkit.Host.Linux | Hostkit.Host.MacOS
     and then not Hostkit.Host.Is_Elevated
   then
      if Ada.Directories.Exists (Locked) then
         Chmod (Locked, 8#755#);
      end if;
      Delete_Tree_If_Present (Root);
      Ada.Directories.Create_Path (Locked);
      Write_File (Ada.Directories.Compose (Locked, "inside.txt"), "kept");
      Chmod (Locked, 0);
      GNAT.OS_Lib.Set_Errno (0);
      Assert
        (Hostkit.Fs.Delete_Tree_No_Follow (Root) = Hostkit.Fs.Tree_Delete_Failed,
         "a tree holding a folder that may not be opened is not deleted");
      Assert
        (GNAT.OS_Lib.Errno = E_Acces,
         "and the refusal is the open's EACCES, not EBADF:" & Integer'Image (GNAT.OS_Lib.Errno));
      Chmod (Locked, 8#755#);
      Assert
        (Hostkit.Fs.Delete_Tree_No_Follow (Root) = Hostkit.Fs.Tree_Deleted,
         "once the folder may be opened, the tree goes");
      Assert (not Ada.Directories.Exists (Root), "all of it");
   end if;
exception
   when others =>
      if Ada.Directories.Exists (Locked) then
         Chmod (Locked, 8#755#);
      end if;
      Delete_Tree_If_Present (Root);
      raise;
end Test_Delete_Tree_Stays_On_Its_Mount;
