separate (Hostkit_Suite)
procedure Test_Mount_Table (T : in out AUnit.Test_Cases.Test_Case'Class) is
   pragma Unreferenced (T);
   Table : constant Hostkit.Mounts.Mount_Vectors.Vector := Hostkit.Mounts.Table;
   Found : Boolean;
   Known : Boolean;
   Root  : Hostkit.Mounts.Mount;
begin
   if Hostkit.Host.Current = Hostkit.Host.Linux then
      Root := Hostkit.Mounts.Find (Table, "/", Found);
      Assert (Found, "the root filesystem is in the table");
      Assert (Ada.Strings.Unbounded.Length (Root.Filesystem_Type) > 0, "with its type");
      for Item of Table loop
         Assert (Ada.Strings.Fixed.Index (Ada.Strings.Unbounded.To_String (Item.Mount_Point), "\040") = 0,
                 "mount points are decoded");
      end loop;
   else
      Assert (Table.Is_Empty, "a host without a mount table lists none");
   end if;
   Assert (not Hostkit.Mounts.Removable ("proc", Known) and then not Known,
           "a pseudo filesystem's source is no disk, and that is not known to be fixed");
end Test_Mount_Table;
