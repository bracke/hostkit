separate (Hostkit_Suite)
procedure Test_Directory_Accessible_By_Others
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);

   Private_Dir : constant String := Ada.Directories.Compose (Scratch, "hk-dir-0700");
   Open_Dir    : constant String := Ada.Directories.Compose (Scratch, "hk-dir-0755");
   A_File      : constant String := Ada.Directories.Compose (Scratch, "hk-dir-file");

   File : Ada.Text_IO.File_Type;
begin
   Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, A_File);
   Ada.Text_IO.Close (File);

   --  Only meaningful where mode bits mean something; on Windows this always answers
   --  False, and setting a POSIX mode there is a no-op, so there is nothing to assert.
   if not Hostkit.Shell.Is_Command_Shell then
      Ada.Directories.Create_Path (Private_Dir);
      Ada.Directories.Create_Path (Open_Dir);
      Chmod (Private_Dir, 8#700#);
      Chmod (Open_Dir, 8#755#);

      Assert
        (not Hostkit.Fs.Directory_Accessible_By_Others (Private_Dir),
         "a 0700 directory is not accessible by others");
      Assert
        (Hostkit.Fs.Directory_Accessible_By_Others (Open_Dir),
         "a 0755 directory is accessible by others");
   end if;

   Assert
     (not Hostkit.Fs.Directory_Accessible_By_Others (A_File),
      "a regular file is not judged by this -- directories only");
end Test_Directory_Accessible_By_Others;
