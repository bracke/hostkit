separate (Hostkit_Suite)
procedure Test_A_Kept_Id_Is_Left_As_It_Is
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type Hostkit.Metadata.Identity_Field;
   Path      : constant String := Ada.Directories.Compose (Scratch, "hostkit-kept-id");
   Owner     : Hostkit.Metadata.Account_Id;
   Group     : Hostkit.Metadata.Account_Id;
   Now_Owner : Hostkit.Metadata.Account_Id;
   Now_Group : Hostkit.Metadata.Account_Id;
   Available : Boolean;
   Result    : Hostkit.Metadata.Metadata_Update_Result;
   Bits      : Natural;

   procedure Remove is
      Ignored_Made_Plain : Boolean;
   begin
      if Ada.Directories.Exists (Path) then
         Ignored_Made_Plain := Hostkit.Metadata.Set_Exact_Permissions (Path, 8#644#);
         Ada.Directories.Delete_File (Path);
      end if;
   end Remove;
begin
   Remove;
   Write_File (Path, "owned");
   Hostkit.Metadata.File_Ownership (Path, Owner, Group, Available);
   Assert (Available, "the file's owner and group are read");

   --  The held-entry update: the group given, the user kept.
   Result := Hostkit.Metadata.Update_Entry_Metadata
     (Path, (others => <>), False, Hostkit.Metadata.Update_Ownership,
      Hostkit.Metadata.Keep_Id_Field, Hostkit.Metadata.Identity_Field (Group),
      Hostkit.Metadata.Identity_Field'Last);
   Assert (Result.Success, "giving the file its own group with the user kept succeeds");
   Assert (Result.Previous = Hostkit.Metadata.Identity_Field (Owner), "and reports the owner as it was");
   Hostkit.Metadata.File_Ownership (Path, Now_Owner, Now_Group, Available);
   Assert (Available and then Now_Owner = Owner and then Now_Group = Group,
           "the kept user is the file's owner still");

   --  Both kept: nothing to write, and nothing refused.
   Result := Hostkit.Metadata.Update_Entry_Metadata
     (Path, (others => <>), False, Hostkit.Metadata.Update_Ownership,
      Hostkit.Metadata.Keep_Id_Field, Hostkit.Metadata.Keep_Id_Field, Hostkit.Metadata.Identity_Field'Last);
   Assert (Result.Success, "an update that keeps both ids succeeds");
   Assert (Hostkit.Metadata.Set_Ownership (Path, Hostkit.Metadata.Keep_Id, Hostkit.Metadata.Keep_Id),
           "Set_Ownership keeping both ids succeeds");
   Assert (not Hostkit.Metadata.Set_Ownership
             (Path & "-missing", Hostkit.Metadata.Keep_Id, Hostkit.Metadata.Keep_Id),
           "but not for a file that is not there");

   if Hostkit.Host.Current = Hostkit.Host.Windows then
      --  A group set by name needs WRITE_OWNER there, which the test's own
      --  file need not grant; and the mode is drawn from the ACL, with no
      --  set-id bits for a chown to clear.
      Remove;
      Skip ("Test_A_Kept_Id_Is_Left_As_It_Is", "Windows sets a group through its SID, not a POSIX chown");
      return;
   end if;

   --  A chown that changes nothing still clears set-user-id: keeping both
   --  ids must not ask for one.
   Assert (Hostkit.Metadata.Set_Exact_Permissions (Path, 8#4755#), "the file is made set-user-id");
   Assert (Hostkit.Metadata.Set_Ownership (Path, Hostkit.Metadata.Keep_Id, Hostkit.Metadata.Keep_Id),
           "keeping both ids of a set-user-id file succeeds");
   Bits := Hostkit.Metadata.File_Permission_Bits (Path, Available);
   Assert (Available and then (Bits / 8#4000#) mod 2 = 1,
           "and leaves its set-user-id bit, as no chown was made");

   --  Only the group: (uid_t) -1 for the user, which an unprivileged
   --  process may ask for its own file and its own group, and which would
   --  be refused were the user taken as the id 4294967295.
   Assert (Hostkit.Metadata.Set_Exact_Permissions (Path, 8#644#), "the file is made plain again");
   Assert (Hostkit.Metadata.Set_Ownership (Path, Hostkit.Metadata.Keep_Id, Group),
           "setting only the group, with the user kept, succeeds");
   Hostkit.Metadata.File_Ownership (Path, Now_Owner, Now_Group, Available);
   Assert (Available and then Now_Owner = Owner and then Now_Group = Group,
           "and leaves the user as it was");
   Remove;
exception
   when others =>
      Remove;
      raise;
end Test_A_Kept_Id_Is_Left_As_It_Is;
