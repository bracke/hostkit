separate (Hostkit.Metadata)
function Apply_Permission_Edit
  (Path, Handle                 : System.Address;
   Dacl, Owner, Group, Everyone : System.Address;
   Control                      : Interfaces.C.unsigned_short;
   Old_Mode, Mode               : Natural;
   Runnable                     : Boolean) return Boolean
is
   Target  : constant Natural := Target_Mode (Owner, Group, Mode, Runnable);
   Built   : System.Address := System.Null_Address;
   Applied : Boolean := False;
   Freed   : System.Address;
   pragma Unreferenced (Freed);
begin
   if not Edited_Dacl (Dacl, Owner, Group, Everyone, Old_Mode, Mode, Runnable, Built) then
      return False;
   elsif Mode_Of ((if Built = System.Null_Address then Dacl else Built), Owner, Group, Everyone, Runnable)
     = Target
   then
      Applied := Built = System.Null_Address or else Set_Own_Dacl (Path, Handle, Built, Control);
      if Built /= System.Null_Address then
         Freed := Local_Free (Built);
      end if;
      return Applied;
   end if;
   if Built /= System.Null_Address then
      Freed := Local_Free (Built);
      Built := System.Null_Address;
   end if;

   if Dacl /= System.Null_Address then
      declare
         Converted : constant Acl_Words := Explicit_Dacl (Dacl, Owner, Group, Everyone, Target, Runnable);
      begin
         if Converted'Length > 0 and then Mode_Of (Converted'Address, Owner, Group, Everyone, Runnable) = Target
         then
            return Set_Own_Dacl (Path, Handle, Converted'Address, Control or Se_Dacl_Protected);
         end if;
      end;
   end if;

   if not Exact_Dacl (Owner, Group, Everyone, Mode, Built) then
      return False;
   end if;
   if Mode_Of (Built, Owner, Group, Everyone, Runnable) = Target then
      Applied := Set_Own_Dacl (Path, Handle, Built);
   else
      Hostkit.Windows_Errors.Set_Errno_From (Error_Not_Supported);
   end if;
   Freed := Local_Free (Built);
   return Applied;
end Apply_Permission_Edit;
