separate (Hostkit_Suite)
procedure Test_An_Absent_Entry_Is_Told_From_A_Refusal
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type Hostkit.Fs.Delete_Tree_Outcome;
   use type Hostkit.Fs.Entry_Kind;
   Folder   : constant String := Ada.Directories.Compose (Scratch, "hostkit-absent");
   Closed   : constant String := Ada.Directories.Compose (Folder, "closed");
   File     : constant String := Ada.Directories.Compose (Folder, "file");
   Dangling : constant String := Ada.Directories.Compose (Folder, "dangling");
   Inside   : constant String := Ada.Directories.Compose (Closed, "inside");
   Refused  : Boolean := False;
begin
   if Hostkit.Fs.Kind_Of (Folder) /= Hostkit.Fs.Missing_Entry then
      Assert (Hostkit.Fs.Delete_Tree_No_Follow (Folder) = Hostkit.Fs.Tree_Deleted, "a leftover is removed");
   end if;
   Ada.Directories.Create_Path (Closed);
   Write_File (File, "here");
   Write_File (Inside, "here");
   Assert (Hostkit.Fs.Entry_Is_Absent (Ada.Directories.Compose (Folder, "nothing")), "nothing there is absent");
   Assert (Hostkit.Fs.Entry_Is_Absent (""), "no path at all names nothing");
   --  A name longer than any entry can bear names nothing; a path past
   --  PATH_MAX made of ordinary names is one the host will not look up, not
   --  proof that nothing is there. Windows reads both through \\?\.
   Assert
     (Hostkit.Fs.Entry_Is_Absent (Ada.Directories.Compose (Folder, [1 .. 300 => 'n'])),
      "a name longer than NAME_MAX is absent");
   if Hostkit.Host.Current /= Hostkit.Host.Windows then
      declare
         Long_Path : Ada.Strings.Unbounded.Unbounded_String :=
           Ada.Strings.Unbounded.To_Unbounded_String (Folder);
         Refused_Long : Boolean := False;
      begin
         while Ada.Strings.Unbounded.Length (Long_Path) <= 5_000 loop
            Ada.Strings.Unbounded.Append (Long_Path, "/" & [1 .. 200 => 'd']);
         end loop;
         begin
            declare
               Answer : constant Boolean :=
                 Hostkit.Fs.Entry_Is_Absent (Ada.Strings.Unbounded.To_String (Long_Path));
            begin
               Assert (not Answer, "a path past PATH_MAX is not taken for absence");
            end;
         exception
            when Ada.Directories.Use_Error =>
               Refused_Long := True;
         end;
         Assert (Refused_Long, "a path past PATH_MAX is a lookup the host will not make");
      end;
   end if;
   Assert (not Hostkit.Fs.Entry_Is_Absent (File), "a file is not absent");
   Assert (not Hostkit.Fs.Entry_Is_Absent (Folder), "nor is a folder");
   if Hostkit.Fs.Create_Link (Ada.Directories.Compose (Folder, "missing-target"), Dangling) then
      Assert (not Hostkit.Fs.Entry_Is_Absent (Dangling), "a dangling link is something there");
   end if;
   --  A folder that may not be searched: its entries cannot be asked about.
   --  POSIX refuses a lookup there (EACCES); Windows reads attributes past
   --  traverse checks, and a privileged account passes, so this part runs
   --  where the refusal is real.
   if Hostkit.Host.Current /= Hostkit.Host.Windows
     and then Hostkit.Metadata.Set_Permissions (Closed, 0)
   then
      begin
         declare
            Unused : constant Ada.Directories.File_Size := Hostkit.Fs.Size_Of (Inside);
         begin
            null;
         end;
      exception
         when Ada.Directories.Use_Error =>
            Refused := True;
      end;
      if Refused then
         begin
            declare
               Answer : constant Boolean := Hostkit.Fs.Entry_Is_Absent (Inside);
            begin
               Assert (Hostkit.Metadata.Set_Permissions (Closed, 8#755#), "the folder is opened again");
               Assert (False, "a refused lookup answered" & Boolean'Image (Answer) & " instead of raising");
            end;
         exception
            when Ada.Directories.Use_Error =>
               null;
         end;
      end if;
      Assert (Hostkit.Metadata.Set_Permissions (Closed, 8#755#), "the folder is opened again");
   end if;
   Assert (Hostkit.Fs.Delete_Tree_No_Follow (Folder) = Hostkit.Fs.Tree_Deleted, "and everything is removed");
end Test_An_Absent_Entry_Is_Told_From_A_Refusal;
