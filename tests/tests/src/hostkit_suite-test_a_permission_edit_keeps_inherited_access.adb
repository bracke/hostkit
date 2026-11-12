separate (Hostkit_Suite)
procedure Test_A_Permission_Edit_Keeps_Inherited_Access
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type Hostkit.Metadata.Identity_Field;
   Path      : constant String := Ada.Directories.Compose (Scratch, "hk-permission-edit");
   Folder    : constant String := Ada.Directories.Compose (Scratch, "hk-permission-convert");
   Inner     : constant String := Ada.Directories.Compose (Folder, "converted");
   Available : Boolean;
   Before    : Natural;
   Edited    : Natural;
   First     : Hostkit.Metadata.Metadata_Update_Result;
   Back      : Hostkit.Metadata.Metadata_Update_Result;
   Probe     : Hostkit.Metadata.Metadata_Update_Result;

   function Update
     (Mode : Natural; Access_Text : String := ""; Entry_Path : String := Path)
      return Hostkit.Metadata.Metadata_Update_Result is
     (Hostkit.Metadata.Update_Entry_Metadata
        (Entry_Path, (others => <>), False, Hostkit.Metadata.Update_Permissions,
         Hostkit.Metadata.Identity_Field (Mode), 0, Hostkit.Metadata.Identity_Field (Natural'Last),
         Access_Text => Access_Text));

   --  The bits of triplet Left that triplet Right lacks.
   function Missing (Left, Right : Natural) return Natural is
     ((if (Left / 4) mod 2 = 1 and then (Right / 4) mod 2 = 0 then 4 else 0)
      + (if (Left / 2) mod 2 = 1 and then (Right / 2) mod 2 = 0 then 2 else 0)
      + (if Left mod 2 = 1 and then Right mod 2 = 0 then 1 else 0));

   --  How many ACEs an SDDL DACL says were inherited.
   function Inherited (Text : String) return Natural is (Ada.Strings.Fixed.Count (Text, ";ID;"));

   --  Whether an SDDL DACL is protected from inheritance: "D:P..." or
   --  "D:PAI...".
   function Is_Protected (Text : String) return Boolean is
     (Text'Length >= 3 and then Text (Text'First .. Text'First + 2) = "D:P");

   --  Whether an SDDL DACL has an ACE for the trustee SDDL calls Alias
   --  ("SY" SYSTEM, "BA" the Administrators).
   function Names (Text : String; Alias : String) return Boolean is
     (Ada.Strings.Fixed.Index (Text, ";;;" & Alias & ")") > 0);

   --  Grant Everyone read on Folder, handed down to what it will hold, as
   --  a folder's own ACE: icacls, whose output lands in a scratch file.
   function Grant_Everyone_Read return Boolean is
      use type GNAT.OS_Lib.String_Access;
      Icacls  : GNAT.OS_Lib.String_Access := GNAT.OS_Lib.Locate_Exec_On_Path ("icacls.exe");
      Output  : constant String := Ada.Directories.Compose (Scratch, "hk-permission-icacls.txt");
      Args    : GNAT.OS_Lib.Argument_List :=
        [new String'(Folder), new String'("/grant"), new String'("*S-1-1-0:(OI)(CI)R")];
      Done    : Boolean := False;
      Code    : Integer := 1;
   begin
      if Icacls /= null then
         GNAT.OS_Lib.Spawn (Icacls.all, Args, Output, Done, Code);
         GNAT.OS_Lib.Free (Icacls);
      end if;
      for Item of Args loop
         GNAT.OS_Lib.Free (Item);
      end loop;
      if Ada.Directories.Exists (Output) then
         Ada.Directories.Delete_File (Output);
      end if;
      return Done and then Code = 0;
   end Grant_Everyone_Read;
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
   --  The group given the rights its owner has: an edit that only adds,
   --  which nothing the entry inherits can contradict. Everyone's read bit,
   --  turned the other way, where the group has them all already.
   declare
      Owner_Bits : constant Natural := (Before / 64) mod 8;
      Group_Bits : constant Natural := (Before / 8) mod 8;
      Widened    : constant Natural := Before + Missing (Owner_Bits, Group_Bits) * 8;
   begin
      if Hostkit.Host.Current = Hostkit.Host.Windows then
         Assert (Widened /= Before, "the fixture's group lacks a right its owner has:" & Before'Image);
      end if;
      Edited := (if Widened /= Before then Widened elsif (Before / 4) mod 2 = 1 then Before - 4 else Before + 4);
   end;

   First := Update (Edited);
   Assert (First.Success, "the edit is applied");
   Assert (First.Previous = Hostkit.Metadata.Identity_Field (Before), "and reports the mode it replaced");
   Assert (Hostkit.Metadata.File_Permission_Bits (Path, Available) = Edited, "the mode is the one asked for");

   if Hostkit.Host.Current /= Hostkit.Host.Windows then
      --  The mode is the whole record: nothing else is kept or reported.
      Assert
        (Length (First.Previous_Access) = 0 and then Length (First.Applied_Access) = 0,
         "a POSIX host reports no access record beside the mode");
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
      Assert (Hostkit.Metadata.File_Permission_Bits (Path, Available) = Edited, "and gives the mode asked for");
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

   --  An edit inheritance contradicts: the folder hands Everyone read down,
   --  and the edit takes read from the group and from "other". Leaving the
   --  inherited ACE would leave the read; the DACL is converted to
   --  explicit ACEs instead, as Explorer's "disable inheritance" does, and
   --  the record still puts back the original, inheritance and all.
   if Ada.Directories.Exists (Folder) then
      if Ada.Directories.Exists (Inner) then
         Assert (Hostkit.Metadata.Set_Exact_Permissions (Inner, 8#644#), "a leftover is made writable again");
      end if;
      Ada.Directories.Delete_Tree (Folder);
   end if;
   Ada.Directories.Create_Directory (Folder);
   Assert (Grant_Everyone_Read, "the folder is made to hand Everyone read down (icacls)");
   Write_File (Inner, "converted");
   declare
      Inherits : constant Natural := Hostkit.Metadata.File_Permission_Bits (Inner, Available);
      Asked    : constant Natural :=
        Inherits - (if (Inherits / 8 / 4) mod 2 = 1 then 8#040# else 0) - (if (Inherits / 4) mod 2 = 1 then 4 else 0);
      Read     : Natural;
   begin
      Assert (Available, "the converted fixture's mode can be read");
      Assert ((Inherits / 4) mod 2 = 1, "Everyone reads what the folder hands read down to:" & Inherits'Image);
      Probe := Update (Asked, Entry_Path => Inner);
      Assert (Probe.Success, "the edit inheritance contradicts is applied");
      Read := Hostkit.Metadata.File_Permission_Bits (Inner, Available);
      Assert
        (Read = Asked,
         "and takes effect: the group and Everyone no longer read (asked" & Asked'Image & ", read" & Read'Image & ")");
      declare
         Original : constant String := To_String (Probe.Previous_Access);
         Applied  : constant String := To_String (Probe.Applied_Access);
      begin
         Assert (Inherited (Original) > 0, "the fixture inherits from its folder: " & Original);
         Assert (Is_Protected (Applied), "the DACL no longer inherits: " & Applied);
         Assert (Inherited (Applied) = 0, "every ACE it inherited is now its own: " & Applied);
         Assert
           (Names (Original, "SY") or else Names (Original, "BA"),
            "the fixture's DACL names SYSTEM or the Administrators: " & Original);
         Assert
           ((not Names (Original, "SY") or else Names (Applied, "SY"))
            and then (not Names (Original, "BA") or else Names (Applied, "BA")),
            "SYSTEM's and the Administrators' access survives, now explicit: " & Original & " became " & Applied);

         Back := Update (Inherits, Access_Text => Original, Entry_Path => Inner);
         Assert (Back.Success, "the original access record is put back");
         Assert
           (To_String (Back.Applied_Access) = Original,
            "the DACL is the original, inheritance and all, SDDL for SDDL: " & To_String (Back.Applied_Access)
            & " for " & Original);
         Assert
           (Hostkit.Metadata.File_Permission_Bits (Inner, Available) = Inherits,
            "and so is the mode read from it");
      end;
   end;
   Ada.Directories.Delete_File (Inner);
   Ada.Directories.Delete_Directory (Folder);
end Test_A_Permission_Edit_Keeps_Inherited_Access;
