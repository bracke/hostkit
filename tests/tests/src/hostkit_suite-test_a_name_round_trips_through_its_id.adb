separate (Hostkit_Suite)
procedure Test_A_Name_Round_Trips_Through_Its_Id
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Path      : constant String := Ada.Directories.Compose (Scratch, "hk-meta-owner");
   User_Id   : Hostkit.Metadata.Account_Id;
   Group_Id  : Hostkit.Metadata.Account_Id;
   Available : Boolean;
begin
   if not Hostkit.Metadata.Ownership_Supported then
      --  Windows has no uid/gid pair; the host says so once, here, rather than
      --  every one of these answering with a plausible 0.
      Assert
        (Hostkit.Metadata.User_Name_For_Id (Hostkit.Metadata.Account_Id'(0)) = "",
         "a host without ownership resolves no names");
      return;
   end if;

   Write_File (Path, "x");
   Hostkit.Metadata.File_Ownership (Path, User_Id, Group_Id, Available);
   Assert (Available, "a file this process just created has ownership to report");

   declare
      Name  : constant String := Hostkit.Metadata.User_Name_For_Id (User_Id);
      Found : Boolean;
      Back  : Hostkit.Metadata.Account_Id;
   begin
      Assert (Name /= "", "the owning user id resolves to a name");

      --  The id IS the identity on POSIX: it resolves to a name and that name
      --  resolves back to the same id. Windows has no uid -- the number is
      --  derived from an owner SID for callers that want one -- so neither
      --  half of that round trip is something it promises, and asserting it
      --  would be asserting POSIX again.
      if Hostkit.Host.Current /= Hostkit.Host.Windows then
         Back := Hostkit.Metadata.User_Id_For_Name (Name, Found);
         Assert (Found, "and that name resolves back to an id");
         Assert (Back = User_Id, "which is the id it came from");
      end if;
   end;

   declare
      Name  : constant String := Hostkit.Metadata.Group_Name_For_Id (Group_Id);
      Found : Boolean;
      Back  : Hostkit.Metadata.Account_Id;
   begin
      if Name /= "" and then Hostkit.Host.Current /= Hostkit.Host.Windows then
         Back := Hostkit.Metadata.Group_Id_For_Name (Name, Found);
         Assert (Found, "the owning group name resolves back to an id");
         Assert (Back = Group_Id, "which is the id it came from");
      end if;
   end;

   --  Setting the ownership a file already has must be accepted. It is the
   --  round trip that matters -- an id this package reported, handed back to
   --  it -- and it is the one case that needs no privilege, so it is
   --  checkable as an unprivileged CI user on every host.
   --
   --  This is why Set_Ownership is not Hostkit.Fs.Set_Owner: that one
   --  declines on Windows, because a uid from elsewhere means nothing there.
   --  Routing this through it made "change owner" a silent no-op on Windows,
   --  which is what this assertion exists to stop happening again.
   Assert
     (Hostkit.Metadata.Set_Ownership (Path, User_Id, Group_Id),
      "a file's own ownership can be set back onto it");

   Ada.Directories.Delete_File (Path);
end Test_A_Name_Round_Trips_Through_Its_Id;
