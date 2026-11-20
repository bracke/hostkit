separate (Hostkit.Metadata)
function File_Permission_Bits
  (Path      : String;
   Available : out Boolean) return Natural
is
   C_Path : aliased Wide_String := Wide (Path);

   Owner      : aliased System.Address := System.Null_Address;
   Group      : aliased System.Address := System.Null_Address;
   Dacl       : aliased System.Address := System.Null_Address;
   Sacl       : aliased System.Address := System.Null_Address;
   Descriptor : aliased System.Address := System.Null_Address;

   Status : C_DWord;
   Mode   : Natural := 0;

   Everyone      : aliased Sid_Buffer := [others => Interfaces.C.nul];
   Everyone_Size : aliased C_DWord := C_DWord (Sid_Buffer'Length);
   procedure Free_Descriptor is
      Freed : System.Address;
      pragma Unreferenced (Freed);
   begin
      if Descriptor /= System.Null_Address then
         Freed := Local_Free (Descriptor);
         Descriptor := System.Null_Address;
      end if;
   end Free_Descriptor;
begin
   Available := False;

   Status :=
     Get_Named_Security_Info
       (C_Path'Address, Se_File_Object,
        Owner_Information or Group_Information or Dacl_Information,
        Owner'Access, Group'Access, Dacl'Access, Sacl'Access,
        Descriptor'Access);

   if Status /= Success then
      return 0;
   end if;

   Remember (Owner, Identity_Of (Owner));
   Remember (Group, Identity_Of (Group));

   declare
      World : constant System.Address :=
        (if Create_Well_Known_Sid
              (Win_World_Sid, System.Null_Address, Everyone (1)'Address, Everyone_Size'Access) /= 0
         then Everyone (1)'Address
         else System.Null_Address);
   begin
      --  Execute bits only where Windows would run the file, or for a
      --  folder: its execute bit means it can be entered, as the DACL
      --  grants.
      Mode := Mode_Of (Dacl, Owner, Group, World, Runnable_At (Path));
   end;

   Free_Descriptor;
   Available := True;
   return Mode;

exception
   when others =>
      Free_Descriptor;
      Available := False;
      return 0;
end File_Permission_Bits;
