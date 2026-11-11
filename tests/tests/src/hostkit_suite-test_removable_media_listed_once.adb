separate (Hostkit_Suite)
procedure Test_Removable_Media_Listed_Once
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
begin
   --  Removable media are Mounts.Volume_Places' (/run/media, per user):
   --  User_Places naming /run/media/<user> too made callers scan it twice.
   for Place of Hostkit.Fs.User_Places loop
      declare
         Path : constant String := To_String (Place.Path);
      begin
         Assert (Path'Length < 10 or else Path (Path'First .. Path'First + 9) /= "/run/media",
                 "user places leave removable media to the volume places");
      end;
   end loop;
end Test_Removable_Media_Listed_Once;
