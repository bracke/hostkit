separate (Hostkit_Suite)
procedure Test_Metadata_Update_Is_Bound_To_The_Held_Entry
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type Hostkit.Metadata.Entry_Identity;
   use type Hostkit.Metadata.Identity_Field;
   Path : constant String :=
     Ada.Directories.Compose (Scratch, "hk-held-metadata");
   Expected : Hostkit.Metadata.Entry_Identity;
   Wrong    : Hostkit.Metadata.Entry_Identity;
   Result   : Hostkit.Metadata.Metadata_Update_Result;
   Before   : Natural;
   After    : Natural;
   Available : Boolean;
begin
   if not Hostkit.Metadata.Permissions_Supported then
      Skip ("Test_Metadata_Update_Is_Bound_To_The_Held_Entry", "this host keeps no permissions");
      return;
   end if;
   Write_File (Path, "held");
   Assert
     (Hostkit.Metadata.Set_Permissions (Path, 8#640#),
      "the fixture mode is set");
   Before := Hostkit.Metadata.File_Permission_Bits (Path, Available);
   Assert (Available, "the fixture mode is readable");
   Expected := Hostkit.Metadata.Entry_Identity_Of (Path);
   Assert (Expected.Available, "the entry has an identity to guard");

   Wrong := Expected;
   Wrong.File_Number := Wrong.File_Number + 1;
   Result := Hostkit.Metadata.Update_Entry_Metadata
     (Path, Wrong, True, Hostkit.Metadata.Update_Permissions,
      8#400#, 0, Hostkit.Metadata.Identity_Field (Natural'Last));
   Assert (not Result.Success, "a different expected entry is refused");
   After := Hostkit.Metadata.File_Permission_Bits (Path, Available);
   Assert (Available and then After = Before,
           "a refused update leaves the held entry unchanged");

   Result := Hostkit.Metadata.Update_Entry_Metadata
     (Path, Expected, True, Hostkit.Metadata.Update_Permissions,
      8#600#, 0, Hostkit.Metadata.Identity_Field (Natural'Last));
   Assert (Result.Success, "the expected held entry is updated");
   Assert (Result.Identity = Expected,
           "the result identifies the entry actually updated");
   Assert
     (Result.Previous = Hostkit.Metadata.Identity_Field (Before),
      "the previous mode comes from that same held entry");
   After := Hostkit.Metadata.File_Permission_Bits (Path, Available);
   Assert (Available, "the updated mode remains readable");
   if Hostkit.Host.Current /= Hostkit.Host.Windows then
      Assert (After = 8#600#, "the requested native mode was applied");
   end if;
   Ada.Directories.Delete_File (Path);
end Test_Metadata_Update_Is_Bound_To_The_Held_Entry;
