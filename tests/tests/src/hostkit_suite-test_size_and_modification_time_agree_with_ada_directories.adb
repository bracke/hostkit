separate (Hostkit_Suite)
procedure Test_Size_And_Modification_Time_Agree_With_Ada_Directories
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type Ada.Calendar.Time;
   use type Ada.Directories.File_Size;
   use type Hostkit.Fs.Delete_Tree_Outcome;
   Top         : constant String := Ada.Directories.Compose (Scratch, "hk-size-time");
   File        : constant String := Ada.Directories.Compose (Top, "f.txt");
   Folder      : constant String := Ada.Directories.Compose (Top, "d");
   File_Link   : constant String := Ada.Directories.Compose (Top, "f-link");
   Folder_Link : constant String := Ada.Directories.Compose (Top, "d-link");
   Dangling    : constant String := Ada.Directories.Compose (Top, "dangling");
   Missing     : constant String := Ada.Directories.Compose (Top, "missing");
   Posix       : constant Boolean := Hostkit.Host.Current /= Hostkit.Host.Windows;
   --  A previous run's leftovers; nothing there is the usual answer.
   Leftover    : constant Hostkit.Fs.Delete_Tree_Outcome := Hostkit.Fs.Delete_Tree_No_Follow (Top);
   pragma Unreferenced (Leftover);

   --  Whether asking about Path is refused as nothing there (Name_Error):
   --  Size_Of when Size, else Modification_Time_Of.
   function Refused (Path : String; Size : Boolean; Follow_Links : Boolean := True) return Boolean is
      Ignored_Size : Ada.Directories.File_Size;
      Ignored_Time : Ada.Calendar.Time;
   begin
      if Size then
         Ignored_Size := Hostkit.Fs.Size_Of (Path, Follow_Links);
      else
         Ignored_Time := Hostkit.Fs.Modification_Time_Of (Path, Follow_Links);
      end if;
      return False;
   exception
      when Ada.Directories.Name_Error =>
         return True;
   end Refused;

   --  The owner's read and write answers for Path are GNAT.OS_Lib's.
   procedure Owner_Agrees (Path : String; What : String) is
   begin
      Assert
        (Hostkit.Fs.Is_Owner_Readable (Path) = GNAT.OS_Lib.Is_Owner_Readable_File (Path),
         What & ": readable as GNAT says");
      Assert
        (Hostkit.Fs.Is_Owner_Writable (Path) = GNAT.OS_Lib.Is_Owner_Writable_File (Path),
         What & ": writable as GNAT says");
   end Owner_Agrees;
begin
   Ada.Directories.Create_Path (Folder);
   Write_File (File, "twelve bytes");

   Assert (Hostkit.Fs.Size_Of (File) = Ada.Directories.Size (File), "a file's size is Ada.Directories'");
   Assert (Hostkit.Fs.Size_Of (File) >= 12, "and holds what was written");
   Assert
     (Hostkit.Fs.Modification_Time_Of (File) = Ada.Directories.Modification_Time (File),
      "a file's modification time is Ada.Directories'");
   Assert
     (Hostkit.Fs.Modification_Time_Of (Folder) = Ada.Directories.Modification_Time (Folder),
      "so is a folder's");
   Assert (Refused (Folder, Size => True), "a folder has no size, as Ada.Directories.Size refuses one");
   Assert (Refused (Missing, Size => True), "nothing there has no size");
   Assert (Refused (Missing, Size => False), "nor a modification time");
   Assert (Refused ("", Size => True) and then Refused ("", Size => False), "nor has no path at all");

   Owner_Agrees (File, "a file");
   Owner_Agrees (Folder, "a folder");
   Assert (Hostkit.Fs.Is_Owner_Readable (File), "a new file is readable");
   Assert (Hostkit.Fs.Is_Owner_Writable (File), "and writable");
   Assert (not Hostkit.Fs.Is_Owner_Readable (Missing), "nothing there is not readable");
   Assert (not Hostkit.Fs.Is_Owner_Writable (Missing), "nor writable");
   GNAT.OS_Lib.Set_Read_Only (File);
   Assert (not Hostkit.Fs.Is_Owner_Writable (File), "a read-only file is not writable");
   Owner_Agrees (File, "a read-only file");
   GNAT.OS_Lib.Set_Writable (File);
   Assert (Hostkit.Fs.Is_Owner_Writable (File), "and writable once made so again");
   if Posix then
      --  Windows would deny reading with an ACL entry, which a test should
      --  not leave behind; POSIX clears a bit.
      GNAT.OS_Lib.Set_Non_Readable (File);
      Assert (not Hostkit.Fs.Is_Owner_Readable (File), "a file without the owner's read bit is not readable");
      Owner_Agrees (File, "an unreadable file");
      GNAT.OS_Lib.Set_Readable (File);
   end if;

   if Hostkit.Fs.Create_Link (File, File_Link)
     and then Hostkit.Fs.Create_Link (Folder, Folder_Link)
     and then Hostkit.Fs.Create_Link (Missing, Dangling)
   then
      Assert (Hostkit.Fs.Size_Of (File_Link) = Hostkit.Fs.Size_Of (File), "a link's size is its file's");
      Assert
        (Hostkit.Fs.Modification_Time_Of (File_Link) = Hostkit.Fs.Modification_Time_Of (File),
         "and so is its modification time");
      Assert
        (Hostkit.Fs.Modification_Time_Of (Folder_Link) = Hostkit.Fs.Modification_Time_Of (Folder),
         "a link to a folder has its folder's time");
      Assert (Refused (Folder_Link, Size => True), "but no size");
      Assert (Refused (Dangling, Size => True), "a dangling link followed has no size");
      Assert (Refused (Dangling, Size => False), "nor a modification time");
      Assert (not Refused (Dangling, Size => False, Follow_Links => False), "though the link itself has one");
      if Posix then
         --  GNAT follows a link on POSIX; on Windows it reads the link itself.
         Assert (Hostkit.Fs.Size_Of (File_Link) = Ada.Directories.Size (File_Link), "as Ada.Directories says");
         Assert
           (Hostkit.Fs.Modification_Time_Of (File_Link) = Ada.Directories.Modification_Time (File_Link),
            "both of them");
         Assert
           (Hostkit.Fs.Modification_Time_Of (Folder_Link) = Ada.Directories.Modification_Time (Folder_Link),
            "for a link to a folder too");
         Assert
           (Hostkit.Fs.Size_Of (Dangling, Follow_Links => False) = Ada.Directories.File_Size (Missing'Length),
            "a link itself holds its target's text");
         Owner_Agrees (File_Link, "a link to a file");
         Owner_Agrees (Folder_Link, "a link to a folder");
         Assert (not Hostkit.Fs.Is_Owner_Readable (Dangling), "a dangling link is not readable");
      end if;
   else
      Links_Refused ("Size_Of and Modification_Time_Of through links");
   end if;
   Assert (Hostkit.Fs.Delete_Tree_No_Follow (Top) = Hostkit.Fs.Tree_Deleted, "the folder is removed");
end Test_Size_And_Modification_Time_Agree_With_Ada_Directories;
