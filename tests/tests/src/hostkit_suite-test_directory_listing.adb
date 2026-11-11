separate (Hostkit_Suite)
procedure Test_Directory_Listing
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type Hostkit.Directory_Listing.Entry_Kind;
   Root    : constant String := Ada.Directories.Compose (Scratch, "hk-listing");
   Link    : constant String := Ada.Directories.Compose (Root, "link");
   Entries : Hostkit.Directory_Listing.Entry_Vectors.Vector;
   Seen    : Natural := 0;
begin
   Delete_Tree_If_Present (Root);
   Ada.Directories.Create_Path (Ada.Directories.Compose (Root, "sub"));
   Write_File (Ada.Directories.Compose (Root, "file.txt"), "text");
   declare
      Linked : constant Boolean :=
        Hostkit.Fs.Create_Link (Ada.Directories.Compose (Root, "sub"), Link);
   begin
      Assert (Hostkit.Directory_Listing.List (Root, Entries), "a directory is listed");
      for Item of Entries loop
         Assert (Item.Name /= "." and then Item.Name /= "..", ". and .. are left out");
         if Item.Name = "file.txt" then
            Seen := Seen + 1;
            Assert
              (Item.Kind in Hostkit.Directory_Listing.Regular_File | Hostkit.Directory_Listing.Unknown,
               "a file is a file, or unknown");
         elsif Item.Name = "sub" then
            Seen := Seen + 1;
            Assert
              (Item.Kind in Hostkit.Directory_Listing.Directory | Hostkit.Directory_Listing.Unknown,
               "a directory is a directory, or unknown");
         elsif Item.Name = "link" then
            Seen := Seen + 1;
            Assert
              (Item.Kind in Hostkit.Directory_Listing.Symbolic_Link | Hostkit.Directory_Listing.Unknown,
               "a link to a directory is a link, not followed");
         end if;
      end loop;
      Assert (Seen = (if Linked then 3 else 2), "every entry is listed");
      if not Linked then
         Links_Refused ("Directory_Listing, a link entry");
      end if;
   end;
   Assert
     (not Hostkit.Directory_Listing.List (Ada.Directories.Compose (Root, "missing"), Entries),
      "a missing directory is not listed");
   Assert (Entries.Is_Empty, "nothing is listed for it");
   if Hostkit.Fs.Is_Link (Link) then
      declare
         Ignored : constant Boolean := Hostkit.Fs.Delete_Link (Link);
      begin
         null;
      end;
   end if;
   Delete_Tree_If_Present (Root);
end Test_Directory_Listing;
