separate (Hostkit.Metadata)
function Set_Exact_Permissions
  (Path : String;
   Mode : Natural) return Boolean
is
   C_Path : aliased Wide_String := Wide (Path);

   Owner      : aliased System.Address := System.Null_Address;
   Group      : aliased System.Address := System.Null_Address;
   Dacl       : aliased System.Address := System.Null_Address;
   Sacl       : aliased System.Address := System.Null_Address;
   Descriptor : aliased System.Address := System.Null_Address;

   New_Acl  : System.Address := System.Null_Address;
   Status   : C_DWord;

   Everyone      : aliased Sid_Buffer := [others => Interfaces.C.nul];
   Everyone_Size : aliased C_DWord := C_DWord (Sid_Buffer'Length);

   --  Get_Named_Security_Info hands back a LocalAlloc'd descriptor the caller
   --  owns; every exit after it succeeds must release it, not just the happy
   --  path.
   procedure Free_Allocations is
      Freed : System.Address;
      pragma Unreferenced (Freed);
   begin
      if New_Acl /= System.Null_Address then
         Freed := Local_Free (New_Acl);
         New_Acl := System.Null_Address;
      end if;
      if Descriptor /= System.Null_Address then
         Freed := Local_Free (Descriptor);
         Descriptor := System.Null_Address;
      end if;
   end Free_Allocations;
begin
   Status :=
     Get_Named_Security_Info
       (C_Path'Address, Se_File_Object,
        Owner_Information or Group_Information or Dacl_Information,
        Owner'Access, Group'Access, Dacl'Access, Sacl'Access,
        Descriptor'Access);

   if Status /= Success then
      Hostkit.Windows_Errors.Set_Errno_From (Interfaces.Unsigned_32 (Status));
      return False;
   end if;

   if Create_Well_Known_Sid
        (Win_World_Sid, System.Null_Address,
         Everyone (1)'Address, Everyone_Size'Access) = 0
   then
      Hostkit.Errors.Set_Errno_From_Last_Error;
      Free_Allocations;
      return False;
   end if;

   --  A fresh DACL granting the owner, the primary group and Everyone exactly
   --  the rights the three POSIX triplets ask for.
   if not Exact_Dacl (Owner, Group, Everyone (1)'Address, Mode, New_Acl) then
      Free_Allocations;
      return False;
   end if;

   declare
      Applied : constant Boolean :=
        Set_Own_Dacl (C_Path'Address, System.Null_Address, New_Acl);
   begin
      Free_Allocations;
      return Applied;
   end;

exception
   when others =>
      Free_Allocations;
      return False;
end Set_Exact_Permissions;
