separate (Hostkit.Metadata)
function Set_Dacl_Text (File : System.Address; Text : String) return Boolean is
   Descriptor : aliased System.Address := System.Null_Address;
   Size       : aliased C_DWord := 0;
   Applied    : Boolean;
   Freed      : System.Address;
   pragma Unreferenced (Freed);
begin
   --  Converted here, not as a declaration, so the handler below sees
   --  text that is not UTF-8.
   declare
      Sddl : aliased constant Wide_String := Wide_Text (Text);
   begin
      if Convert_Text_To_Descriptor (Sddl'Address, Sddl_Revision, Descriptor'Access, Size'Access) = 0
        or else Descriptor = System.Null_Address
      then
         Hostkit.Errors.Set_Errno_From_Last_Error;
         return False;
      end if;
   end;
   --  An auto-inherited DACL ("D:AI...") keeps that mark only when the
   --  write asks for it; without, the restored DACL read back plainer
   --  than the one recorded.
   if Ada.Strings.Fixed.Index (Text, "D:AI") = Text'First
     or else Ada.Strings.Fixed.Index (Text, "D:PAI") = Text'First
   then
      Ignore_Result
        (Set_Security_Descriptor_Control
           (Descriptor, Dacl_Auto_Inherit_Req or Se_Dacl_Auto_Inherited,
            Dacl_Auto_Inherit_Req or Se_Dacl_Auto_Inherited));
   end if;
   Applied := Set_Kernel_Object_Security (File, Dacl_Information, Descriptor) /= 0;
   if not Applied then
      Hostkit.Errors.Set_Errno_From_Last_Error;
   end if;
   Freed := Local_Free (Descriptor);
   return Applied;
exception
   when Ada.Strings.UTF_Encoding.Encoding_Error =>
      --  Not text Dacl_Text wrote.
      Hostkit.Windows_Errors.Set_Errno_From (Error_Invalid_Parameter);
      return False;
end Set_Dacl_Text;
