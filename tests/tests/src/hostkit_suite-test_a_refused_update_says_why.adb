separate (Hostkit_Suite)
procedure Test_A_Refused_Update_Says_Why
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   package HM renames Hostkit.Metadata;
   use type HM.Identity_Field;
   --  ENOENT and EINVAL are 2 and 22 on Linux, macOS and in the Windows
   --  runtime alike; ELOOP is each host's own (E_Loop).
   E_No_Ent : constant := 2;
   E_Inval  : constant := 22;
   File     : constant String := Ada.Directories.Compose (Scratch, "hk-update-refused");
   Link     : constant String := Ada.Directories.Compose (Scratch, "hk-update-refused-link");
   Held     : HM.Entry_Identity;
   Other    : HM.Entry_Identity;
   Updated  : HM.Metadata_Update_Result;

   function Update
     (Path     : String;
      Expected : HM.Entry_Identity;
      Kind     : HM.Metadata_Update_Kind;
      Value    : HM.Identity_Field) return HM.Metadata_Update_Result
   is
     (HM.Update_Entry_Metadata
        (Path           => Path,
         Expected       => Expected,
         Check_Expected => True,
         Kind           => Kind,
         Value          => Value,
         Group          => 0,
         Max_Previous   => HM.Identity_Field'Last));
begin
   if Hostkit.Fs.Is_Link (Link) then
      Assert (Hostkit.Fs.Delete_Link (Link), "a leftover link is removed");
   end if;
   if Ada.Directories.Exists (File) then
      Ada.Directories.Delete_File (File);
   end if;
   Write_File (File, "held");
   Held := HM.Entry_Identity_Of (File);
   Assert (Held.Available, "an ordinary file in the scratch folder has an identity");

   --  Another entry than the one asked about: gone from the path, ENOENT.
   Other := Held;
   Other.File_Number := Interfaces."xor" (Other.File_Number, 1);
   GNAT.OS_Lib.Set_Errno (0);
   Updated := Update (File, Other, HM.Update_Permissions, 8#644#);
   Assert (not Updated.Success, "an update bound to another entry is refused");
   Assert
     (GNAT.OS_Lib.Errno = E_No_Ent,
      "and says the entry asked about is gone, ENOENT:" & Integer'Image (GNAT.OS_Lib.Errno));
   Updated := Update (File, Held, HM.Update_Permissions, 8#644#);
   Assert (Updated.Success, "the entry asked about is updated, so the refusal was the mismatch");

   --  An owner id no POSIX host has: EINVAL. (Windows refuses it alike, after
   --  resolving names this fixture does not give.)
   if Hostkit.Host.Current in Hostkit.Host.Linux | Hostkit.Host.MacOS then
      GNAT.OS_Lib.Set_Errno (0);
      Updated := Update (File, Held, HM.Update_Ownership, 2 ** 40);
      Assert (not Updated.Success, "an owner id past 32 bits is refused");
      Assert
        (GNAT.OS_Lib.Errno = E_Inval,
         "and the refusal is EINVAL:" & Integer'Image (GNAT.OS_Lib.Errno));
   end if;

   --  A link is never updated through: ELOOP, as O_NOFOLLOW refuses one.
   if Hostkit.Fs.Create_Link (File, Link) then
      GNAT.OS_Lib.Set_Errno (0);
      Updated := Update (Link, HM.Entry_Identity_Of (Link), HM.Update_Permissions, 8#600#);
      Assert (not Updated.Success, "an update of a link is refused");
      Assert
        (GNAT.OS_Lib.Errno = E_Loop,
         "and the refusal is ELOOP:" & Integer'Image (GNAT.OS_Lib.Errno));
      Assert (Hostkit.Fs.Delete_Link (Link), "the link is removed");
   else
      Links_Refused ("Update_Entry_Metadata, a link");
   end if;

   Ada.Directories.Delete_File (File);
exception
   when others =>
      if Hostkit.Fs.Is_Link (Link) then
         declare
            Ignored : constant Boolean := Hostkit.Fs.Delete_Link (Link);
         begin
            null;
         end;
      end if;
      if Ada.Directories.Exists (File) then
         Ada.Directories.Delete_File (File);
      end if;
      raise;
end Test_A_Refused_Update_Says_Why;
