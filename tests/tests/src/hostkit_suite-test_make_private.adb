separate (Hostkit_Suite)
procedure Test_Make_Private (T : in out AUnit.Test_Cases.Test_Case'Class) is
   pragma Unreferenced (T);

   A_File  : constant String := Ada.Directories.Compose (Scratch, "hk-make-private-file");
   A_Dir   : constant String := Ada.Directories.Compose (Scratch, "hk-make-private-dir");
   Missing : constant String := Ada.Directories.Compose (Scratch, "hk-make-private-gone");

   File : Ada.Text_IO.File_Type;
begin
   Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, A_File);
   Ada.Text_IO.Close (File);
   Ada.Directories.Create_Path (A_Dir);
   Chmod (A_File, 8#644#);
   Chmod (A_Dir, 8#755#);

   if Hostkit.Shell.Is_Command_Shell then
      Assert
        (not Hostkit.Fs.Make_Private (A_File),
         "a host with no mode bits says it did not make the path private");
   else
      Assert (Hostkit.Fs.Make_Private (A_File), "a file is made private");
      Assert
        (not Hostkit.Fs.Accessible_By_Others (A_File),
         "a file made private is no longer accessible by others");

      Assert (Hostkit.Fs.Make_Private (A_Dir), "a directory is made private");
      Assert
        (not Hostkit.Fs.Directory_Accessible_By_Others (A_Dir),
         "a directory made private is no longer accessible by others");
      Assert
        (Ada.Directories.Exists (A_Dir),
         "a directory made private can still be entered by its owner");
   end if;

   Assert
     (not Hostkit.Fs.Make_Private (Missing),
      "a path that is not there is not reported as made private");
end Test_Make_Private;
