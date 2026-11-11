separate (Hostkit_Suite)
procedure Test_Delete_Tree_Large_Folder
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type Hostkit.Fs.Delete_Tree_Outcome;
   Root : constant String := Ada.Directories.Compose (Scratch, "hk-delete-large");
   Count : constant := 100_001;
begin
   Delete_Tree_If_Present (Root);
   Ada.Directories.Create_Path (Root);
   for Index in 1 .. Count loop
      declare
         Image : constant String := Index'Image;
         Fd : constant GNAT.OS_Lib.File_Descriptor :=
           GNAT.OS_Lib.Create_New_File
             (Ada.Directories.Compose (Root, "f" & Image (Image'First + 1 .. Image'Last)),
              GNAT.OS_Lib.Binary);
      begin
         GNAT.OS_Lib.Close (Fd);
      end;
   end loop;
   Assert
     (Hostkit.Fs.Delete_Tree_No_Follow (Root) = Hostkit.Fs.Tree_Deleted,
      "a folder of" & Count'Image & " entries is deleted");
   Assert (not Ada.Directories.Exists (Root), "and is gone");
exception
   when others =>
      Delete_Tree_If_Present (Root);
      raise;
end Test_Delete_Tree_Large_Folder;
