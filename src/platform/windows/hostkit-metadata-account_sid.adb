separate (Hostkit.Metadata)
function Account_Sid
  (Name    : String;
   Sid     : out Sid_Buffer;
   Say_Why : Boolean) return Boolean
is
   Wide_Name   : aliased constant Wide_String := Wide_Text (Name);
   Sid_Size    : aliased C_DWord := 0;
   Domain_Size : aliased C_DWord := 0;
   Use_Kind    : aliased C_Int := 0;
   Ignored     : C_Int;
begin
   Sid := [others => Interfaces.C.nul];
   Ignored := Lookup_Account_Name_Wide
     (System.Null_Address, Wide_Name'Address,
      System.Null_Address, Sid_Size'Access,
      System.Null_Address, Domain_Size'Access, Use_Kind'Access);
   if Sid_Size = 0 or else Natural (Sid_Size) > Sid_Buffer'Length then
      if Say_Why then
         Hostkit.Errors.Set_Errno_From_Last_Error;
      end if;
      return False;
   end if;
   declare
      Domain : aliased Wide_String
        (1 .. Natural'Max (1, Natural (Domain_Size))) :=
          [others => Wide_Character'Val (0)];
      Actual_Sid_Size : aliased C_DWord := Sid_Size;
      Actual_Domain_Size : aliased C_DWord := Domain_Size;
   begin
      if Lookup_Account_Name_Wide
        (System.Null_Address, Wide_Name'Address, Sid (1)'Address,
         Actual_Sid_Size'Access, Domain'Address,
         Actual_Domain_Size'Access, Use_Kind'Access) = 0
      then
         if Say_Why then
            Hostkit.Errors.Set_Errno_From_Last_Error;
         end if;
         return False;
      end if;
   end;
   return True;
end Account_Sid;
