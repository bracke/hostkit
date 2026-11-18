separate (Hostkit_Suite)
procedure Test_Canonical_Path_Answers_Only_What_Is_There
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type Hostkit.Fs.Delete_Tree_Outcome;
   use type Hostkit.Fs.Entry_Kind;
   Folder   : constant String := Ada.Directories.Compose (Scratch, "hostkit-canonical");
   Inner    : constant String := Ada.Directories.Compose (Folder, "inner");
   Link     : constant String := Ada.Directories.Compose (Folder, "link");
   Dangling : constant String := Ada.Directories.Compose (Folder, "dangling");
   Loop_A   : constant String := Ada.Directories.Compose (Folder, "loop-a");
   Loop_B   : constant String := Ada.Directories.Compose (Folder, "loop-b");
begin
   if Hostkit.Fs.Kind_Of (Folder) /= Hostkit.Fs.Missing_Entry then
      Assert (Hostkit.Fs.Delete_Tree_No_Follow (Folder) = Hostkit.Fs.Tree_Deleted, "a leftover is removed");
   end if;
   Ada.Directories.Create_Path (Inner);
   declare
      Real : constant String := Hostkit.Fs.Canonical_Path (Inner);
   begin
      Assert (Real /= "", "a folder that is there has a canonical path");
      Assert (Real = Hostkit.Fs.Real_Path (Inner), "the same one Real_Path gives");
      Assert (Hostkit.Fs.Canonical_Path (Ada.Directories.Compose (Inner, "missing")) = "",
              "a missing leaf has none, on every host");
      Assert (Hostkit.Fs.Canonical_Path ("") = "", "nor has no path at all");
      if Hostkit.Fs.Create_Link (Inner, Link) then
         Assert (Hostkit.Fs.Canonical_Path (Link) = Real, "a link is followed to what it names");
         Assert (Hostkit.Fs.Create_Link (Ada.Directories.Compose (Folder, "nowhere"), Dangling),
                 "a dangling link is made");
         Assert (Hostkit.Fs.Canonical_Path (Dangling) = "", "a dangling link has none");
         Assert (Hostkit.Fs.Create_Link (Loop_B, Loop_A) and then Hostkit.Fs.Create_Link (Loop_A, Loop_B),
                 "a loop of links is made");
         Assert (Hostkit.Fs.Canonical_Path (Loop_A) = "", "a loop of links has none");
      else
         Links_Refused ("Test_Canonical_Path_Answers_Only_What_Is_There");
      end if;
   end;
   Assert (Hostkit.Fs.Delete_Tree_No_Follow (Folder) = Hostkit.Fs.Tree_Deleted, "the folder is removed");
end Test_Canonical_Path_Answers_Only_What_Is_There;
