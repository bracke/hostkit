separate (Hostkit_Suite)
procedure Test_Host_Capabilities (T : in out AUnit.Test_Cases.Test_Case'Class) is
   pragma Unreferenced (T);
   use type Hostkit.Host.Kind;
   Windows : constant Boolean := Hostkit.Host.Current = Hostkit.Host.Windows;
   Posix   : constant Boolean := Hostkit.Host.Current in Hostkit.Host.Linux | Hostkit.Host.MacOS;
begin
   Assert (Hostkit.Lease_Files.Held_File_Removable = Posix,
           "a held lease file is removable on Linux and macOS, not on Windows");
   Assert (Hostkit.Metadata.Inherit_Rewrites_Change_Times = Windows,
           "only Windows rewrites change times when access is inherited");
   Assert (Hostkit.Trash.Has_Volume_Trash_Folders = Posix,
           "Linux and macOS let a program keep per-volume trash folders; Windows does not");
   Assert (Hostkit.Mounts.Filesystem_Root = (if Posix then "/" else ""),
           "the filesystem root is / on Linux and macOS, none on Windows");
   Assert (Hostkit.Mounts.Is_Network ("ext4", "//server/share")
             and then Hostkit.Mounts.Is_Network ("ntfs", "\\server\share")
             and then Hostkit.Mounts.Is_Network ("nfs", "/mnt/data")
             and then not Hostkit.Mounts.Is_Network ("ext4", "/mnt/data")
             and then not Hostkit.Mounts.Is_Network ("ext4", "/"),
           "a mount is a network one by its type or by a UNC mount point");

   --  A held lease's file goes when the host says it may.
   if Hostkit.Lease_Files.Held_File_Removable then
      declare
         use type Hostkit.Lease_Files.Open_Outcome;
         Path : constant String :=
           Ada.Directories.Compose (Scratch, "hostkit-held-lease-probe");
         Item : Hostkit.Lease_Files.Lease;
      begin
         if Ada.Directories.Exists (Path) then
            Ada.Directories.Delete_File (Path);
         end if;
         if Hostkit.Lease_Files.Create (Path, Item) = Hostkit.Lease_Files.Opened then
            Ada.Directories.Delete_File (Path);
            Assert (not Ada.Directories.Exists (Path), "a held lease file was removed");
         end if;
         Hostkit.Lease_Files.Release (Item);
      end;
   end if;
end Test_Host_Capabilities;
