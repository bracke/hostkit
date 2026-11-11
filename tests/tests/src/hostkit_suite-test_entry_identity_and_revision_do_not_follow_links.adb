separate (Hostkit_Suite)
procedure Test_Entry_Identity_And_Revision_Do_Not_Follow_Links
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type Hostkit.Metadata.Identity_Field;
   Original : constant String := Ada.Directories.Compose (Scratch, "hk-entry-identity");
   Link     : constant String := Ada.Directories.Compose (Scratch, "hk-entry-identity-link");
   Missing  : constant String := Ada.Directories.Compose (Scratch, "hk-entry-identity-missing");

   function Same
     (Left, Right : Hostkit.Metadata.Entry_Identity) return Boolean is
     (Left.Available and then Right.Available
      and then Left.Volume = Right.Volume
      and then Left.File_Number = Right.File_Number
      and then Left.Generation_High = Right.Generation_High
      and then Left.Generation_Low = Right.Generation_Low);
begin
   if Hostkit.Fs.Is_Link (Link) then
      Assert (Hostkit.Fs.Delete_Link (Link), "remove an old identity-test link");
   end if;
   if Ada.Directories.Exists (Original) then
      Ada.Directories.Delete_File (Original);
   end if;
   Write_File (Original, "identity");

   declare
      Identity : constant Hostkit.Metadata.Entry_Identity :=
        Hostkit.Metadata.Entry_Identity_Of (Original);
      Revision : constant Hostkit.Metadata.Entry_Revision :=
        Hostkit.Metadata.Entry_Revision_Of (Original);
   begin
      Assert (Identity.Available, "a newly-created entry has a stable host identity");
      Assert (Revision.Available, "a newly-created entry has a no-follow revision");
      --  Put_Line ends the line with CR LF on Windows, so ask the file.
      Assert (Revision.Size = Hostkit.Metadata.Identity_Field (Ada.Directories.Size (Original)),
              "a newly-created entry's revision has its size");
      Assert (not Hostkit.Metadata.Entry_Identity_Of (Missing).Available,
              "a missing entry has no invented identity");
      Assert (not Hostkit.Metadata.Entry_Revision_Of (Missing).Available,
              "a missing entry has no invented revision");

      if Hostkit.Fs.Create_Link (Original, Link) then
         Assert
           (not Same (Identity, Hostkit.Metadata.Entry_Identity_Of (Link)),
            "a link's identity is its own, not its target's");
         Assert (Hostkit.Fs.Delete_Link (Link), "remove the identity-test link");
      else
         Links_Refused ("Entry_Identity_Of, a link");
      end if;
   end;
   Ada.Directories.Delete_File (Original);
end Test_Entry_Identity_And_Revision_Do_Not_Follow_Links;
