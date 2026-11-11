separate (Hostkit_Suite)
procedure Test_Mode_And_Ownership_Agree_With_The_Separate_Calls
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Path : constant String := Ada.Directories.Compose (Scratch, "hk-meta-modes");

   Separate_Mode      : Natural;
   Separate_Mode_Ok   : Boolean;
   Separate_User      : Hostkit.Metadata.Account_Id;
   Separate_Group     : Hostkit.Metadata.Account_Id;
   Separate_Owner_Ok  : Boolean;

   Joint_Mode         : Natural;
   Joint_Mode_Ok      : Boolean;
   Joint_User         : Hostkit.Metadata.Account_Id;
   Joint_Group        : Hostkit.Metadata.Account_Id;
   Joint_Owner_Ok     : Boolean;

   Narrow_Mode        : Natural;
   Narrow_Mode_Ok     : Boolean;
   Narrow_User        : Natural;
   Narrow_Group       : Natural;
   Narrow_Owner_Ok    : Boolean;
begin
   Write_File (Path, "x");

   --  File_Mode_And_Ownership exists only to save a syscall. If it ever
   --  disagreed with the two calls it stands in for, it would be a silent
   --  wrong answer in the middle of a directory listing -- so this is the
   --  assertion that earns it.
   Separate_Mode := Hostkit.Metadata.File_Permission_Bits (Path, Separate_Mode_Ok);
   Hostkit.Metadata.File_Ownership (Path, Separate_User, Separate_Group, Separate_Owner_Ok);

   Hostkit.Metadata.File_Mode_And_Ownership
     (Path, Joint_Mode, Joint_Mode_Ok, Joint_User, Joint_Group, Joint_Owner_Ok);

   Assert (Joint_Mode_Ok = Separate_Mode_Ok, "both report mode availability the same way");
   Assert (Joint_Owner_Ok = Separate_Owner_Ok, "both report ownership availability the same way");

   if Separate_Mode_Ok then
      Assert (Joint_Mode = Separate_Mode, "the joint call reports the same mode bits");
   end if;

   if Separate_Owner_Ok then
      Assert (Joint_User = Separate_User, "the joint call reports the same owner");
      Assert (Joint_Group = Separate_Group, "the joint call reports the same group");
   end if;

   --  The Natural form kept for older callers answers the mode exactly as
   --  the Account_Id form does, whatever it makes of the ownership: an
   --  owner it cannot hand back as a Natural costs the ownership answer,
   --  never the permissions.
   Hostkit.Metadata.File_Mode_And_Ownership
     (Path, Narrow_Mode, Narrow_Mode_Ok, Narrow_User, Narrow_Group, Narrow_Owner_Ok);
   Assert (Narrow_Mode_Ok = Joint_Mode_Ok, "the Natural form reports mode availability the same way");
   if Joint_Mode_Ok then
      Assert (Narrow_Mode = Joint_Mode, "the Natural form reports the same mode bits");
   end if;
   Assert
     (Narrow_Owner_Ok
        = (Joint_Owner_Ok
           and then Hostkit.Metadata.Fits_Natural (Joint_User)
           and then Hostkit.Metadata.Fits_Natural (Joint_Group)),
      "the Natural form reports ownership exactly when the ids fit a Natural");
   if Narrow_Owner_Ok then
      Assert
        (Hostkit.Metadata.Account_Id (Narrow_User) = Joint_User,
         "the Natural form reports the same owner");
      Assert
        (Hostkit.Metadata.Account_Id (Narrow_Group) = Joint_Group,
         "the Natural form reports the same group");
   end if;

   --  A mode this host can set is a mode it reads back -- but only where the
   --  bits are real. Windows says Permissions_Supported because it can honour
   --  the request, not because it stores POSIX bits: it writes an ACL and
   --  synthesises the mode back out of one, and an ACL does not round-trip
   --  8#640# exactly (owner rights are implicit, inherited entries are not
   --  ours). Asserting exact equality there would be asserting POSIX on a
   --  host that never claimed it.
   if Hostkit.Metadata.Permissions_Supported then
      Assert (Hostkit.Metadata.Set_Permissions (Path, 8#640#), "the host sets a mode it supports");
      Separate_Mode := Hostkit.Metadata.File_Permission_Bits (Path, Separate_Mode_Ok);
      Assert (Separate_Mode_Ok, "and still reports the mode afterwards");

      if Hostkit.Host.Current /= Hostkit.Host.Windows then
         Assert
           (Separate_Mode = 8#640#,
            "and on a host with real mode bits, reads back exactly what it was given");
      end if;
   end if;

   Ada.Directories.Delete_File (Path);
end Test_Mode_And_Ownership_Agree_With_The_Separate_Calls;
