separate (Hostkit_Suite)
procedure Test_Create_Temporary_Directory
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   use type Ada.Directories.File_Kind;

   pragma Unreferenced (T);

   Directory : constant String := Hostkit.Fs.Create_Temporary_Directory ("hk-temp");
begin
   begin
      Assert (Directory /= "", "a temporary directory path is returned");
      Assert (Ada.Directories.Exists (Directory), "the temporary directory exists");
      Assert
        (Ada.Directories.Kind (Directory) = Ada.Directories.Directory,
         "the temporary path is a directory");
   exception
      when others =>
         Delete_Tree_If_Present (Directory);
         raise;
   end;

   Delete_Tree_If_Present (Directory);
end Test_Create_Temporary_Directory;
