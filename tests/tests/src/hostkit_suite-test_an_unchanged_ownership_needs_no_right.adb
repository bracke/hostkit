separate (Hostkit_Suite)
procedure Test_An_Unchanged_Ownership_Needs_No_Right
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type Hostkit.Metadata.Identity_Field;
   Path      : constant String := Ada.Directories.Compose (Scratch, "hostkit-same-owner");
   Owner     : Natural;
   Group     : Natural;
   Available : Boolean;
   Result    : Hostkit.Metadata.Metadata_Update_Result;
begin
   if Ada.Directories.Exists (Path) then
      Assert (Hostkit.Metadata.Set_Exact_Permissions (Path, 8#644#), "a leftover is made deletable");
      Ada.Directories.Delete_File (Path);
   end if;
   Write_File (Path, "owned");
   Hostkit.Metadata.File_Ownership (Path, Owner, Group, Available);
   Assert (Available, "the file's owner and group are read");
   if Hostkit.Host.Current = Hostkit.Host.Windows then
      --  Everyone may read, and nothing else is granted: the owner keeps
      --  only what owning gives (reading and writing the DACL), not
      --  WRITE_OWNER.
      Result := Hostkit.Metadata.Update_Entry_Metadata
        (Path, (others => <>), False, Hostkit.Metadata.Update_Permissions, 0, 0, 0,
         Access_Text => "D:P(A;;FR;;;WD)");
      Assert (Result.Success, "the file is given an access that grants no WRITE_OWNER");
   end if;
   Result := Hostkit.Metadata.Update_Entry_Metadata
     (Path, (others => <>), False, Hostkit.Metadata.Update_Ownership,
      Hostkit.Metadata.Identity_Field (Owner), Hostkit.Metadata.Identity_Field (Group),
      Hostkit.Metadata.Identity_Field'Last);
   Assert (Result.Success, "giving it the owner and group it has succeeds");
   Assert
     (Result.Previous = Hostkit.Metadata.Identity_Field (Owner)
      and then Result.Previous_Group = Hostkit.Metadata.Identity_Field (Group),
      "and reports them as they were");
   Assert (Hostkit.Metadata.Set_Exact_Permissions (Path, 8#644#), "the file is made deletable");
   Ada.Directories.Delete_File (Path);
end Test_An_Unchanged_Ownership_Needs_No_Right;
