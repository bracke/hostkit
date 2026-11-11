separate (Hostkit_Suite)
procedure Test_Kind_Of_A_Long_Path
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type Hostkit.Fs.Delete_Tree_Outcome;
   use type Hostkit.Fs.Entry_Kind;
   --  Past GNAT's Windows limit of 256 characters a name, too.
   Long_Name : constant String (1 .. 255) := [others => 'k'];
   Top       : constant String := Ada.Directories.Compose (Scratch, "hk-long-kind");
   Short_Top : constant String := Ada.Directories.Compose (Scratch, "hk-lk");
   Folder    : constant String := Hostkit.Fs.Join (Top, Long_Name);
   Deep      : constant String := Hostkit.Fs.Join (Folder, Long_Name);
   Inner     : constant String := Ada.Directories.Compose (Short_Top, "a");
   --  A previous run's leftovers; nothing there is the usual answer.
   Leftover  : constant Hostkit.Fs.Delete_Tree_Outcome := Hostkit.Fs.Delete_Tree_No_Follow (Top);
   pragma Unreferenced (Leftover);
begin
   Delete_Tree_If_Present (Short_Top);
   Ada.Directories.Create_Path (Inner);
   Write_File (Ada.Directories.Compose (Inner, "f"), "kind");
   Assert
     (Hostkit.Fs.Move_No_Replace (Ada.Directories.Compose (Inner, "f"), Hostkit.Fs.Join (Inner, Long_Name)),
      "the file takes a long name");
   Assert (Hostkit.Fs.Move_No_Replace (Inner, Hostkit.Fs.Join (Short_Top, Long_Name)), "so does its folder");
   Assert (Hostkit.Fs.Move_No_Replace (Short_Top, Top), "the outer folder moves on");
   Assert (Deep'Length > 260, "the file now lies past the old path limit");
   Assert (Hostkit.Fs.Kind_Of (Deep) = Hostkit.Fs.Ordinary_File_Entry, "a long file is a file");
   Assert (Hostkit.Fs.Kind_Of (Folder) = Hostkit.Fs.Directory_Entry, "a long folder is a folder");
   Assert (Hostkit.Fs.Kind_Of (Deep & "x") = Hostkit.Fs.Missing_Entry, "a long path to nothing is missing");
   Assert (Hostkit.Fs.Kind_Of ("") = Hostkit.Fs.Missing_Entry, "so is no path at all");
   Assert (Hostkit.Fs.Delete_Tree_No_Follow (Top) = Hostkit.Fs.Tree_Deleted, "the deep tree is removed");
end Test_Kind_Of_A_Long_Path;
