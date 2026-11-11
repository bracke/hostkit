separate (Hostkit_Suite)
procedure Test_Same_File_Sees_Through_A_Second_Name
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Original : constant String := Ada.Directories.Compose (Scratch, "hk-same-original");
   Twin     : constant String := Ada.Directories.Compose (Scratch, "hk-same-twin");
   Other    : constant String := Ada.Directories.Compose (Scratch, "hk-same-other");

   procedure Remove (Path : String) is
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   end Remove;
begin
   Remove (Original);
   Remove (Twin);
   Remove (Other);

   Write_File (Original, "content");
   Write_File (Other, "content");

   Assert (Hostkit.Metadata.Same_File (Original, Original), "a file is the same file as itself");
   Assert
     (not Hostkit.Metadata.Same_File (Original, Other),
      "two files with identical contents are still two files");
   Assert
     (not Hostkit.Metadata.Same_File (Original, Ada.Directories.Compose (Scratch, "hk-same-absent")),
      "a path that does not exist is not the same file as one that does");

   --  Past here the hosts answer this differently, and both are right for the
   --  question they are actually being asked -- which is "would renaming Left
   --  to Right collide with a different file, or is it the same one".
   --
   --  POSIX identity is the inode, so two hard links to one file are one
   --  file. Windows identity is the path, compared case-insensitively,
   --  because that is what makes report.txt and Report.txt the same file
   --  there -- and two hard links, having two paths, are correctly NOT the
   --  same file under that rule. Asserting the inode property on Windows
   --  would be asserting POSIX of a host that never claimed it.
   if Hostkit.Host.Current /= Hostkit.Host.Windows then
      if Hostkit.Fs.Create_Hard_Link (Original, Twin) then
         Assert
           (Hostkit.Metadata.Same_File (Original, Twin),
            "two names for one file are the same file");
         Ada.Directories.Delete_File (Twin);
      else
         Links_Refused ("Same_File, a hard link");
      end if;
   else
      --  The rule that matters on this host, and the one a case-only rename
      --  depends on: the same file, spelled differently, is the same file.
      Assert
        (Hostkit.Metadata.Same_File
           (Original, Ada.Characters.Handling.To_Upper (Original)),
         "on a case-insensitive host, two spellings of one name are the same file");
   end if;

   Ada.Directories.Delete_File (Original);
   Ada.Directories.Delete_File (Other);
end Test_Same_File_Sees_Through_A_Second_Name;
