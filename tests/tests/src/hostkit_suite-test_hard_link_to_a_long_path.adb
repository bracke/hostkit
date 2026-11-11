separate (Hostkit_Suite)
procedure Test_Hard_Link_To_A_Long_Path
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type Ada.Directories.File_Size;
   use type Hostkit.Fs.Delete_Tree_Outcome;
   Long_Name : constant String (1 .. 150) := [others => 'n'];
   Top       : constant String := Ada.Directories.Compose (Scratch, "hk-long-link");
   Short_Top : constant String := Ada.Directories.Compose (Scratch, "hk-ll");
   Link      : constant String := Ada.Directories.Compose (Scratch, "hk-long-link-twin.txt");
   Deep      : constant String :=
     Hostkit.Fs.Join (Hostkit.Fs.Join (Hostkit.Fs.Join (Top, Long_Name), Long_Name), "f.txt");
   Middle    : constant String := Ada.Directories.Compose (Short_Top, "a");
   Inner     : constant String := Ada.Directories.Compose (Middle, "b");
   File      : Ada.Text_IO.File_Type;
   --  A previous run's leftovers; nothing there is the usual answer.
   Leftover  : constant Hostkit.Fs.Delete_Tree_Outcome := Hostkit.Fs.Delete_Tree_No_Follow (Top);
   pragma Unreferenced (Leftover);
begin
   Delete_Tree_If_Present (Short_Top);
   if Ada.Directories.Exists (Link) then
      Ada.Directories.Delete_File (Link);
   end if;
   Ada.Directories.Create_Path (Inner);
   Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Ada.Directories.Compose (Inner, "f.txt"));
   Ada.Text_IO.Put (File, "long");
   Ada.Text_IO.Close (File);
   Assert
     (Hostkit.Fs.Move_No_Replace (Inner, Hostkit.Fs.Join (Middle, Long_Name)),
      "the inner folder takes a long name");
   Assert
     (Hostkit.Fs.Move_No_Replace (Middle, Hostkit.Fs.Join (Short_Top, Long_Name)),
      "so does the folder holding it");
   Assert (Hostkit.Fs.Move_No_Replace (Short_Top, Top), "the outer folder moves on");
   Assert (Deep'Length > 260, "the file now lies past the old path limit");
   if Hostkit.Fs.Create_Hard_Link (Deep, Link) then
      Assert (Ada.Directories.Size (Link) >= 4, "the link reaches the deep file's bytes");
      Ada.Directories.Delete_File (Link);
   else
      Links_Refused ("Create_Hard_Link to a long path");
   end if;
   Assert (Hostkit.Fs.Delete_Tree_No_Follow (Top) = Hostkit.Fs.Tree_Deleted, "the deep tree is removed");
end Test_Hard_Link_To_A_Long_Path;
