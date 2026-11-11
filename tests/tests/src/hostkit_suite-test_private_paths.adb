separate (Hostkit_Suite)
procedure Test_Private_Paths (T : in out AUnit.Test_Cases.Test_Case'Class) is
   pragma Unreferenced (T);
   use type GNAT.OS_Lib.File_Descriptor;
   use type Hostkit.Private_Paths.Create_Outcome;

   Directory : constant String :=
     Ada.Directories.Compose (Scratch, "hk-private-paths-dir");
   File_Path : constant String :=
     Ada.Directories.Compose (Scratch, "hk-private-paths-file");
   Descriptor : GNAT.OS_Lib.File_Descriptor := GNAT.OS_Lib.Invalid_FD;
   Available : Boolean;
   Mode : Natural;
begin
   Delete_Tree_If_Present (Directory);
   if Ada.Directories.Exists (File_Path) then
      Ada.Directories.Delete_File (File_Path);
   end if;

   Assert
     (Hostkit.Private_Paths.Create_Directory (Directory)
        = Hostkit.Private_Paths.Created,
      "an owner-only directory is created");
   Assert
     (Hostkit.Private_Paths.Create_Directory (Directory)
        = Hostkit.Private_Paths.Already_Exists,
      "a directory creation collision is reported separately");
   Assert
     (Hostkit.Private_Paths.Ensure_Directory (Directory),
      "an existing owned directory can be hardened");

   Descriptor := GNAT.OS_Lib.Create_New_File (File_Path, GNAT.OS_Lib.Binary);
   Assert (Descriptor /= GNAT.OS_Lib.Invalid_FD, "the file fixture is open");
   Assert
     (Hostkit.Private_Paths.Restrict_Open_File (Integer (Descriptor)),
      "an open regular file is restricted to its owner");
   GNAT.OS_Lib.Close (Descriptor);
   Descriptor := GNAT.OS_Lib.Invalid_FD;

   if Hostkit.Metadata.Permissions_Supported
     and then Hostkit.Metadata.Mode_Bits_Are_Native
   then
      Mode := Hostkit.Metadata.File_Permission_Bits (File_Path, Available);
      Assert (Available and then Mode = 8#600#, "the file mode is owner-only");
      Mode := Hostkit.Metadata.File_Permission_Bits (Directory, Available);
      Assert
        (Available and then Mode = 8#700#,
         "the directory mode is owner-only and traversable");
   end if;

   Ada.Directories.Delete_File (File_Path);
   Delete_Tree_If_Present (Directory);
exception
   when others =>
      if Descriptor /= GNAT.OS_Lib.Invalid_FD then
         GNAT.OS_Lib.Close (Descriptor);
      end if;
      if Ada.Directories.Exists (File_Path) then
         Ada.Directories.Delete_File (File_Path);
      end if;
      Delete_Tree_If_Present (Directory);
      raise;
end Test_Private_Paths;
