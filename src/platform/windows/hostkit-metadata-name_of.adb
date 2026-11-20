separate (Hostkit.Metadata)
function Name_Of (Sid : System.Address) return String is
   Name_Size   : aliased C_DWord := 0;
   Domain_Size : aliased C_DWord := 0;
   Use_Kind    : aliased C_Int := 0;
   Ignored     : C_Int;
begin
   if Sid = System.Null_Address then
      return "";
   end if;

   Ignored := Lookup_Account_Sid_Wide
     (System.Null_Address, Sid, System.Null_Address, Name_Size'Access,
      System.Null_Address, Domain_Size'Access, Use_Kind'Access);
   if Name_Size = 0 then
      return "";
   end if;

   declare
      Name : aliased Wide_String (1 .. Natural (Name_Size)) :=
        [others => Wide_Character'Val (0)];
      Domain : aliased Wide_String
        (1 .. Natural'Max (1, Natural (Domain_Size))) :=
          [others => Wide_Character'Val (0)];

      function Text_Of (Value : Wide_String) return String is
         Last : Integer := Value'Last;
      begin
         for Index in Value'Range loop
            if Value (Index) = Wide_Character'Val (0) then
               Last := Index - 1;
               exit;
            end if;
         end loop;
         return
           (if Last < Value'First then ""
            else Hostkit.Windows_Paths.To_UTF_8
              (Value (Value'First .. Last)));
      end Text_Of;
   begin
      if Lookup_Account_Sid_Wide
        (System.Null_Address, Sid, Name'Address, Name_Size'Access,
         Domain'Address, Domain_Size'Access, Use_Kind'Access) = 0
      then
         return "";
      end if;
      declare
         Account : constant String := Text_Of (Name);
         Realm   : constant String := Text_Of (Domain);
      begin
         return (if Realm = "" then Account else Realm & '\' & Account);
      end;
   end;

exception
   when others =>
      return "";
end Name_Of;
