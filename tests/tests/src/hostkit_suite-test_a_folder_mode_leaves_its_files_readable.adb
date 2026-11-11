separate (Hostkit_Suite)
procedure Test_A_Folder_Mode_Leaves_Its_Files_Readable
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Folder : constant String :=
     Ada.Directories.Compose (Ada.Directories.Current_Directory, "hostkit-folder-mode");
   Inside : constant String := Ada.Directories.Compose (Folder, "inside");

   function Inside_Reads return Boolean is
      File : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Inside);
      declare
         Line : constant String := Ada.Text_IO.Get_Line (File);
      begin
         Ada.Text_IO.Close (File);
         return Line = "kept";
      end;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         return False;
   end Inside_Reads;

   procedure Clean is
      Ignored : Boolean;
   begin
      Ignored := Hostkit.Metadata.Set_Permissions (Folder, 8#755#);
      if Ada.Directories.Exists (Folder) then
         Ada.Directories.Delete_Tree (Folder);
      end if;
   end Clean;

   Result : Hostkit.Metadata.Metadata_Update_Result;
   File   : Ada.Text_IO.File_Type;
begin
   Clean;
   Ada.Directories.Create_Directory (Folder);
   Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Inside);
   Ada.Text_IO.Put_Line (File, "kept");
   Ada.Text_IO.Close (File);

   if not Hostkit.Metadata.Permissions_Supported then
      Clean;
      Skip ("Test_A_Folder_Mode_Leaves_Its_Files_Readable", "this host keeps no permissions");
      return;
   end if;

   Assert (Hostkit.Metadata.Set_Permissions (Folder, 8#555#), "make the folder read-only");
   Assert (Inside_Reads, "a file in a folder made read-only by path still reads");
   Assert (Hostkit.Metadata.Set_Permissions (Folder, 8#755#), "make the folder writable");

   Result := Hostkit.Metadata.Update_Entry_Metadata
     (Folder, (others => <>), False, Hostkit.Metadata.Update_Permissions,
      8#555#, 0, Hostkit.Metadata.Identity_Field (Natural'Last));
   Assert
     (not Result.Success or else Inside_Reads,
      "and one in a folder made read-only through a handle");

   Clean;
exception
   when others =>
      Clean;
      raise;
end Test_A_Folder_Mode_Leaves_Its_Files_Readable;
