separate (Hostkit_Suite)
procedure Test_Size_And_Modification_Time_Past_The_Path_Limit
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type Ada.Calendar.Time;
   use type Ada.Directories.File_Size;
   use type Hostkit.Fs.Delete_Tree_Outcome;
   Long_Name : constant String (1 .. 150) := [others => 's'];
   Top       : constant String := Ada.Directories.Compose (Scratch, "hk-long-size");
   Short_Top : constant String := Ada.Directories.Compose (Scratch, "hk-ls");
   Middle    : constant String := Ada.Directories.Compose (Short_Top, "a");
   Inner     : constant String := Ada.Directories.Compose (Middle, "b");
   Short     : constant String := Ada.Directories.Compose (Inner, "f.txt");
   Folder    : constant String := Hostkit.Fs.Join (Hostkit.Fs.Join (Top, Long_Name), Long_Name);
   Deep      : constant String := Hostkit.Fs.Join (Folder, "f.txt");
   --  A previous run's leftovers; nothing there is the usual answer.
   Leftover  : constant Hostkit.Fs.Delete_Tree_Outcome := Hostkit.Fs.Delete_Tree_No_Follow (Top);
   pragma Unreferenced (Leftover);
begin
   Delete_Tree_If_Present (Short_Top);
   Ada.Directories.Create_Path (Inner);
   Write_File (Short, "long");
   declare
      --  What GNAT says while the path is short; a rename keeps both.
      Size       : constant Ada.Directories.File_Size := Ada.Directories.Size (Short);
      Written    : constant Ada.Calendar.Time := Ada.Directories.Modification_Time (Short);
      Readable   : constant Boolean := GNAT.OS_Lib.Is_Owner_Readable_File (Short);
      Writable   : constant Boolean := GNAT.OS_Lib.Is_Owner_Writable_File (Short);
      Inner_Time : constant Ada.Calendar.Time := Ada.Directories.Modification_Time (Inner);
   begin
      Assert
        (Hostkit.Fs.Move_No_Replace (Inner, Hostkit.Fs.Join (Middle, Long_Name)),
         "the inner folder takes a long name");
      Assert
        (Hostkit.Fs.Move_No_Replace (Middle, Hostkit.Fs.Join (Short_Top, Long_Name)),
         "so does the folder holding it");
      Assert (Hostkit.Fs.Move_No_Replace (Short_Top, Top), "the outer folder moves on");
      Assert (Deep'Length > 300, "the file now lies past the old path limit");
      Assert (Hostkit.Fs.Size_Of (Deep) = Size, "a long file's size is what GNAT said of it short");
      Assert (Hostkit.Fs.Modification_Time_Of (Deep) = Written, "and so is its modification time");
      Assert
        (Hostkit.Fs.Modification_Time_Of (Folder) = Inner_Time,
         "a long folder's modification time is what GNAT said of it short");
      Assert (Hostkit.Fs.Is_Owner_Readable (Deep) = Readable, "a long file is readable as GNAT said");
      Assert (Hostkit.Fs.Is_Owner_Writable (Deep) = Writable, "and writable");
      Assert (Hostkit.Fs.Is_Owner_Readable (Deep) and then Hostkit.Fs.Is_Owner_Writable (Deep), "both of them");
      if Hostkit.Host.Current /= Hostkit.Host.Windows then
         --  POSIX has no such limit, so GNAT answers for the long path too.
         Assert (Hostkit.Fs.Size_Of (Deep) = Ada.Directories.Size (Deep), "as Ada.Directories says long");
         Assert
           (Hostkit.Fs.Modification_Time_Of (Deep) = Ada.Directories.Modification_Time (Deep),
            "both of them");
      end if;
   end;
   declare
      Ignored : Ada.Directories.File_Size;
   begin
      Ignored := Hostkit.Fs.Size_Of (Deep & "x");
      Assert (False, "a long path to nothing has no size");
   exception
      when Ada.Directories.Name_Error =>
         null;
   end;
   Assert (Hostkit.Fs.Delete_Tree_No_Follow (Top) = Hostkit.Fs.Tree_Deleted, "the deep tree is removed");
end Test_Size_And_Modification_Time_Past_The_Path_Limit;
