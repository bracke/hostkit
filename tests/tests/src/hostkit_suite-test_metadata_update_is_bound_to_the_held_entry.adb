separate (Hostkit_Suite)
procedure Test_Metadata_Update_Is_Bound_To_The_Held_Entry
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type Hostkit.Metadata.Entry_Identity;
   use type Hostkit.Metadata.Identity_Field;
   Path : constant String :=
     Ada.Directories.Compose (Scratch, "hk-held-metadata");
   Root : constant String :=
     Ada.Directories.Compose (Scratch, "hk-held-metadata-root");
   Outside : constant String :=
     Ada.Directories.Compose (Scratch, "hk-held-metadata-outside");
   Linked_Outside : constant String :=
     Ada.Directories.Compose (Root, "outside");
   Inside_File : constant String :=
     Ada.Directories.Compose (Root, "file");
   Outside_File : constant String :=
     Ada.Directories.Compose (Outside, "file");
   Expected : Hostkit.Metadata.Entry_Identity;
   Wrong    : Hostkit.Metadata.Entry_Identity;
   Result   : Hostkit.Metadata.Metadata_Update_Result;
   Before   : Natural;
   After    : Natural;
   Available : Boolean;

   procedure Clean_Beneath is
   begin
      if Hostkit.Fs.Is_Link (Linked_Outside) then
         declare
            Ignored : constant Boolean :=
              Hostkit.Fs.Delete_Link (Linked_Outside);
         begin
            null;
         end;
      end if;
      Delete_Tree_If_Present (Root);
      Delete_Tree_If_Present (Outside);
   end Clean_Beneath;
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
   Clean_Beneath;
   Ada.Directories.Create_Directory (Root);
   Ada.Directories.Create_Directory (Outside);
   Write_File (Inside_File, "inside");
   Write_File (Outside_File, "outside");
   GNAT.OS_Lib.Set_Errno (0);
   Result := Hostkit.Metadata.Update_Entry_Metadata
     (Inside_File, (others => <>), False,
      Hostkit.Metadata.Update_Permissions, 8#600#, 0,
      Hostkit.Metadata.Identity_Field (Natural'Last),
      Beneath_Root => Root,
      Relative_Path => "file" & ASCII.NUL & "suffix");
   Assert
     (not Result.Success and then GNAT.OS_Lib.Errno = 22,
      "a NUL in a beneath path is rejected as EINVAL");
   if Hostkit.Fs.Create_Link (Outside, Linked_Outside) then
      GNAT.OS_Lib.Set_Errno (0);
      Result := Hostkit.Metadata.Update_Entry_Metadata
        (Linked_Outside & "/file", (others => <>), False,
         Hostkit.Metadata.Update_Permissions, 8#600#, 0,
         Hostkit.Metadata.Identity_Field (Natural'Last),
         Beneath_Root => Root, Relative_Path => "outside/file");
      Assert
        (not Result.Success,
         "a metadata update refuses a link in the path below its root");
      if Hostkit.Host.Current = Hostkit.Host.Windows then
         Assert
           (GNAT.OS_Lib.Errno = E_Loop,
            "a refused Windows beneath link reports ELOOP:"
            & Integer'Image (GNAT.OS_Lib.Errno));
      else
         Assert
           (GNAT.OS_Lib.Errno /= 0,
            "a refused beneath link retains its host error");
      end if;
   else
      Links_Refused
        ("Update_Entry_Metadata beneath a directory link");
   end if;
   Clean_Beneath;
exception
   when others =>
      Clean_Beneath;
      raise;
end Test_Metadata_Update_Is_Bound_To_The_Held_Entry;
