separate (Hostkit_Suite)
procedure Test_A_Mode_0_Entry_Is_Still_Seen
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type Hostkit.Fs.Delete_Tree_Outcome;
   use type Hostkit.Fs.Entry_Kind;
   Folder : constant String := Ada.Directories.Compose (Scratch, "hostkit-mode-0");
   Path   : constant String := Ada.Directories.Compose (Folder, "unreadable");
   Moved  : constant String := Ada.Directories.Compose (Folder, "moved");
   Edited : constant String := Ada.Directories.Compose (Folder, "edited");
begin
   if Hostkit.Fs.Kind_Of (Folder) /= Hostkit.Fs.Missing_Entry then
      Assert (Hostkit.Fs.Delete_Tree_No_Follow (Folder) = Hostkit.Fs.Tree_Deleted, "a leftover is removed");
   end if;
   Ada.Directories.Create_Directory (Folder);
   Write_File (Path, "private");
   --  On Windows mode 0 is a DACL granting no data right to anyone.
   Assert (Hostkit.Metadata.Set_Permissions (Path, 0), "the file is made mode 0");
   Assert (Hostkit.Metadata.Entry_Identity_Of (Path).Available, "a mode-0 file can still be looked at, as stat can");
   Assert (Hostkit.Fs.Move_No_Replace (Path, Moved), "its folder lets it be renamed");
   --  An entry whose access is its own (no inherited ACE left to edit) takes
   --  the minimal edit to mode 0, which must not leave it no ACE at all.
   Write_File (Edited, "private");
   Assert (Hostkit.Metadata.Set_Exact_Permissions (Edited, 8#644#), "a second file is given a mode of its own");
   Assert (Hostkit.Metadata.Set_Permissions (Edited, 0), "and is then made mode 0");
   Assert (Hostkit.Metadata.Entry_Identity_Of (Edited).Available, "that file can still be looked at");
   Assert (Hostkit.Fs.Move_No_Replace (Edited, Path), "and renamed");
   Assert (Hostkit.Fs.Delete_Tree_No_Follow (Folder) = Hostkit.Fs.Tree_Deleted, "and deleted");
end Test_A_Mode_0_Entry_Is_Still_Seen;
