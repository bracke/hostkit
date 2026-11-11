separate (Hostkit_Suite)
procedure Test_Relative_Link_Is_Read_From_Its_Folder
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type Ada.Directories.File_Kind;
   Root      : constant String := Ada.Directories.Compose (Scratch, "hk-relative-link");
   Folder    : constant String := Ada.Directories.Compose (Root, "folder");
   To_Folder : constant String := Ada.Directories.Compose (Root, "to-folder");
   To_Inner  : constant String := Ada.Directories.Compose (Root, "to-inner");

   procedure Unlink (Link : String);

   procedure Unlink (Link : String) is
   begin
      if Hostkit.Fs.Is_Link (Link) and then Hostkit.Fs.Delete_Link (Link) then
         null;
      end if;
   end Unlink;
begin
   Delete_Tree_If_Present (Root);
   Ada.Directories.Create_Path (Folder);
   Write_File (Ada.Directories.Compose (Folder, "inner.txt"), "inner");

   --  The targets name nothing in the current directory: only from the
   --  link's own folder are they a folder and a file.
   if Hostkit.Fs.Create_Link ("folder", To_Folder) then
      Assert (Ada.Directories.Kind (To_Folder) = Ada.Directories.Directory, "a link to a folder is a folder");
      Assert (Ada.Directories.Exists (Ada.Directories.Compose (To_Folder, "inner.txt")),
              "and is followed into it");
      Assert (Hostkit.Fs.Create_Link ("folder/inner.txt", To_Inner), "a link through a folder");
      Assert (Ada.Directories.Kind (To_Inner) = Ada.Directories.Ordinary_File, "is followed to its file");
   else
      Links_Refused ("Create_Link, a relative link");
   end if;

   Unlink (To_Inner);
   Unlink (To_Folder);
   Delete_Tree_If_Present (Root);
exception
   when others =>
      Unlink (To_Inner);
      Unlink (To_Folder);
      Delete_Tree_If_Present (Root);
      raise;
end Test_Relative_Link_Is_Read_From_Its_Folder;
