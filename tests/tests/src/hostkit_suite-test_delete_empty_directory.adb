separate (Hostkit_Suite)
procedure Test_Delete_Empty_Directory
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Empty  : constant String := Ada.Directories.Compose (Scratch, "hostkit-empty-dir");
   Full   : constant String := Ada.Directories.Compose (Scratch, "hostkit-full-dir");
   Inside : constant String := Ada.Directories.Compose (Full, "kept");
begin
   Ada.Directories.Create_Path (Empty);
   Ada.Directories.Create_Path (Inside);
   Assert (Hostkit.Fs.Delete_Empty_Directory (Empty), "an empty directory is removed");
   Assert (not Ada.Directories.Exists (Empty), "and is gone");
   Assert (not Hostkit.Fs.Delete_Empty_Directory (Full), "a directory with something in it is refused");
   Assert (Ada.Directories.Exists (Inside), "and what is in it is untouched");
   Assert (not Hostkit.Fs.Delete_Empty_Directory (Empty), "a missing directory is refused, not raised");
   Ada.Directories.Delete_Tree (Full);
end Test_Delete_Empty_Directory;
