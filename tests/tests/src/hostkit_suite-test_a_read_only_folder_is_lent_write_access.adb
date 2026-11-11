separate (Hostkit_Suite)
procedure Test_A_Read_Only_Folder_Is_Lent_Write_Access
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Folder    : constant String := Ada.Directories.Compose (Scratch, "hk-write-access");
   State     : Hostkit.Directory_Write_Access.Context;
   Mode      : Natural;
   Available : Boolean;
begin
   if not Ada.Directories.Exists (Folder) then
      Ada.Directories.Create_Directory (Folder);
   end if;

   if Hostkit.Host.Current not in Hostkit.Host.Linux | Hostkit.Host.MacOS then
      Assert
        (Hostkit.Directory_Write_Access.Prepare (Folder, State),
         "a host without the rule has nothing to lend and is ready");
      Assert (Hostkit.Directory_Write_Access.Finish (State), "and nothing to give back");
      Ada.Directories.Delete_Directory (Folder);
      return;
   end if;

   Assert (Hostkit.Metadata.Set_Permissions (Folder, 8#555#), "make the folder read-only");
   Assert (Hostkit.Directory_Write_Access.Prepare (Folder, State), "write access is lent");
   Mode := Hostkit.Metadata.File_Permission_Bits (Folder, Available);
   Assert (Available, "the lent mode can be read");
   Assert (Mode = 8#755#, "the owner write bit, and only it, is added");
   Assert (Hostkit.Directory_Write_Access.Finish (State), "the mode is given back");
   Mode := Hostkit.Metadata.File_Permission_Bits (Folder, Available);
   Assert (Available, "the restored mode can be read");
   Assert (Mode = 8#555#, "the folder is read-only again");

   Assert (Hostkit.Metadata.Set_Permissions (Folder, 8#755#), "make the folder writable");
   Assert (Hostkit.Directory_Write_Access.Prepare (Folder, State), "an owner-writable folder is ready");
   Assert (Hostkit.Directory_Write_Access.Finish (State), "with nothing to restore");
   Mode := Hostkit.Metadata.File_Permission_Bits (Folder, Available);
   Assert (Available and then Mode = 8#755#, "and its mode untouched");

   Ada.Directories.Delete_Directory (Folder);
exception
   when others =>
      Hostkit.Directory_Write_Access.Release (State);
      if Hostkit.Metadata.Set_Permissions (Folder, 8#755#) then
         Ada.Directories.Delete_Directory (Folder);
      end if;
      raise;
end Test_A_Read_Only_Folder_Is_Lent_Write_Access;
