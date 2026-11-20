separate (Hostkit.Metadata)
function Set_Permissions
  (Path : String;
   Mode : Natural) return Boolean
is
   C_Path : aliased Wide_String := Wide (Path);

   Owner      : aliased System.Address := System.Null_Address;
   Group      : aliased System.Address := System.Null_Address;
   Dacl       : aliased System.Address := System.Null_Address;
   Sacl       : aliased System.Address := System.Null_Address;
   Descriptor : aliased System.Address := System.Null_Address;
   Control    : aliased Interfaces.C.unsigned_short := 0;
   Revision   : aliased C_DWord := 0;
   Status     : C_DWord;

   Everyone      : aliased Sid_Buffer := [others => Interfaces.C.nul];
   Everyone_Size : aliased C_DWord := C_DWord (Sid_Buffer'Length);

   procedure Free_Allocations is
      Freed : System.Address;
      pragma Unreferenced (Freed);
   begin
      if Descriptor /= System.Null_Address then
         Freed := Local_Free (Descriptor);
         Descriptor := System.Null_Address;
      end if;
   end Free_Allocations;
begin
   if Mode > 8#7777# then
      Hostkit.Windows_Errors.Set_Errno_From (Error_Invalid_Parameter);
      return False;
   end if;
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
        (Win_World_Sid, System.Null_Address, Everyone (1)'Address, Everyone_Size'Access) = 0
     or else Get_Security_Descriptor_Control (Descriptor, Control'Access, Revision'Access) = 0
   then
      Hostkit.Errors.Set_Errno_From_Last_Error;
      Free_Allocations;
      return False;
   end if;
   declare
      Runnable : constant Boolean := Runnable_At (Path);
      Applied  : constant Boolean :=
        Apply_Permission_Edit
          (C_Path'Address, System.Null_Address, Dacl, Owner, Group, Everyone (1)'Address, Control,
           Mode_Of (Dacl, Owner, Group, Everyone (1)'Address, Runnable), Mode, Runnable);
   begin
      Free_Allocations;
      return Applied;
   end;
exception
   when others =>
      Free_Allocations;
      return False;
end Set_Permissions;
