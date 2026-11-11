separate (Hostkit_Suite)
procedure Test_A_Permission_Edit_Keeps_Inherited_Access
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type Hostkit.Metadata.Identity_Field;
   Path      : constant String := Ada.Directories.Compose (Scratch, "hk-permission-edit");
   Available : Boolean;
   Before    : Natural;
   Edited    : Natural;
   First     : Hostkit.Metadata.Metadata_Update_Result;
   Back      : Hostkit.Metadata.Metadata_Update_Result;
   Probe     : Hostkit.Metadata.Metadata_Update_Result;

   function Update
     (Mode : Natural; Access_Text : String := "") return Hostkit.Metadata.Metadata_Update_Result is
     (Hostkit.Metadata.Update_Entry_Metadata
        (Path, (others => <>), False, Hostkit.Metadata.Update_Permissions,
         Hostkit.Metadata.Identity_Field (Mode), 0, Hostkit.Metadata.Identity_Field (Natural'Last),
         Access_Text => Access_Text));

   --  How many ACEs an SDDL DACL says were inherited.
   function Inherited (Text : String) return Natural is (Ada.Strings.Fixed.Count (Text, ";ID;"));

   --  Whether an SDDL DACL is protected from inheritance: "D:P..." or
   --  "D:PAI...".
   function Is_Protected (Text : String) return Boolean is
     (Text'Length >= 3 and then Text (Text'First .. Text'First + 2) = "D:P");
begin
   if not Hostkit.Metadata.Permissions_Supported then
      Skip ("Test_A_Permission_Edit_Keeps_Inherited_Access", "this host keeps no permissions");
      return;
   end if;
   if Ada.Directories.Exists (Path) then
      Assert (Hostkit.Metadata.Set_Exact_Permissions (Path, 8#644#), "a leftover is made writable again");
      Ada.Directories.Delete_File (Path);
   end if;
   Write_File (Path, "edited");
   Before := Hostkit.Metadata.File_Permission_Bits (Path, Available);
   Assert (Available, "the fixture's mode can be read");
   --  Everyone's read bit, turned the other way: one bit of one account.
   Edited := (if (Before / 4) mod 2 = 1 then Before - 4 else Before + 4);

   First := Update (Edited);
   Assert (First.Success, "the edit is applied");
   Assert (First.Previous = Hostkit.Metadata.Identity_Field (Before), "and reports the mode it replaced");

   if Hostkit.Host.Current /= Hostkit.Host.Windows then
      --  The mode is the whole record: nothing else is kept or reported.
      Assert
        (Length (First.Previous_Access) = 0 and then Length (First.Applied_Access) = 0,
         "a POSIX host reports no access record beside the mode");
      Assert (Hostkit.Metadata.File_Permission_Bits (Path, Available) = Edited, "the mode is the one asked for");
      Back := Update (Before, Access_Text => "D:P");
      Assert (Back.Success, "an access record is ignored where the mode is all there is");
      Assert (Hostkit.Metadata.File_Permission_Bits (Path, Available) = Before, "and the mode is applied");
      Ada.Directories.Delete_File (Path);
      return;
   end if;

   declare
      Original : constant String := To_String (First.Previous_Access);
      Applied  : constant String := To_String (First.Applied_Access);
   begin
      Assert (Original'Length > 2 and then Original (Original'First .. Original'First + 1) = "D:",
              "the DACL it had is reported as SDDL: " & Original);
      --  The scratch folder hands its ACEs down: a file made in it inherits.
      Assert (Inherited (Original) > 0, "the fixture inherits from its folder: " & Original);
      Assert
        (Inherited (Applied) = Inherited (Original),
         "every inherited ACE survives the edit: " & Original & " became " & Applied);
      Assert (Is_Protected (Applied) = Is_Protected (Original), "and the DACL inherits as it did: " & Applied);
      Assert (Applied /= Original, "the edit changed the DACL");

      --  The record puts back exactly the DACL the edit replaced.
      Back := Update (Before, Access_Text => Original);
      Assert (Back.Success, "the original access record is put back");
      Assert (To_String (Back.Previous_Access) = Applied, "over the edited DACL");
      Assert (To_String (Back.Applied_Access) = Original, "the DACL is the original, SDDL for SDDL: "
              & To_String (Back.Applied_Access));
      Assert
        (Hostkit.Metadata.File_Permission_Bits (Path, Available) = Before,
         "and so is the mode read from it");

      --  An edit by path keeps inheritance too; an update to the mode the
      --  entry has changes nothing and reads its DACL.
      Assert (Hostkit.Metadata.Set_Permissions (Path, Edited), "an edit by path is applied");
      Probe := Update (Hostkit.Metadata.File_Permission_Bits (Path, Available));
      Assert (Probe.Success, "the DACL can be read back");
      Assert
        (Inherited (To_String (Probe.Previous_Access)) = Inherited (Original)
         and then Is_Protected (To_String (Probe.Previous_Access)) = Is_Protected (Original),
         "an edit by path keeps every inherited ACE: " & To_String (Probe.Previous_Access));
      Assert
        (To_String (Probe.Applied_Access) = To_String (Probe.Previous_Access),
         "and an update to the mode the entry has leaves its DACL alone");
   end;
   Assert (Hostkit.Metadata.Set_Exact_Permissions (Path, 8#644#), "the fixture is made writable to remove it");
   Ada.Directories.Delete_File (Path);
end Test_A_Permission_Edit_Keeps_Inherited_Access;
