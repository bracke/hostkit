separate (Hostkit_Suite)
procedure Test_Only_A_Regular_File_Opens
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type GNAT.OS_Lib.File_Descriptor;
   File      : constant String := Ada.Directories.Compose (Scratch, "hk-regular-file");
   Folder    : constant String := Ada.Directories.Compose (Scratch, "hk-regular-folder");
   Link      : constant String := Ada.Directories.Compose (Scratch, "hk-regular-link");
   Supported : Boolean;
   Fd        : GNAT.OS_Lib.File_Descriptor;
begin
   Write_File (File, "x");
   if not Ada.Directories.Exists (Folder) then
      Ada.Directories.Create_Directory (Folder);
   end if;

   Fd := Hostkit.Regular_Files.Open_Read (File, False, Supported);
   if not Supported then
      Assert (Hostkit.Host.Current = Hostkit.Host.Unsupported, "only an unknown host lacks the primitive");
   else
      Assert (Fd /= GNAT.OS_Lib.Invalid_FD, "a regular file opens");
      GNAT.OS_Lib.Close (Fd);

      Fd := Hostkit.Regular_Files.Open_Read (Folder, True, Supported);
      Assert (Fd = GNAT.OS_Lib.Invalid_FD, "a folder is not a regular file");

      if Hostkit.Fs.Create_Link (File, Link) then
         Fd := Hostkit.Regular_Files.Open_Read (Link, False, Supported);
         Assert (Fd = GNAT.OS_Lib.Invalid_FD, "a link is refused when links are not followed");
         Fd := Hostkit.Regular_Files.Open_Read (Link, True, Supported);
         Assert (Fd /= GNAT.OS_Lib.Invalid_FD, "and opens its regular target when they are");
         GNAT.OS_Lib.Close (Fd);
         Assert (Hostkit.Fs.Delete_Link (Link), "remove the link");
      end if;
   end if;

   Ada.Directories.Delete_File (File);
   Ada.Directories.Delete_Directory (Folder);
end Test_Only_A_Regular_File_Opens;
