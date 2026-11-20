separate (Hostkit.Metadata)
function Set_File_Times
  (Path          : String;
   Access_Time   : Long_Long_Integer;
   Modified_Time : Long_Long_Integer)
   return Boolean
is
   function To_Filetime (Seconds : Long_Long_Integer) return Filetime is
      Ticks : constant C_U64 := C_U64 (Seconds + 11_644_473_600) * 10_000_000;
   begin
      return
        (Low  => C_DWord (Ticks mod 2 ** 32),
         High => C_DWord (Ticks / 2 ** 32));
   end To_Filetime;

   C_Path : aliased Wide_String := Wide (Path);
   File   : System.Address := System.Null_Address;
   Access_Filetime   : aliased Filetime := To_Filetime (Access_Time);
   Modified_Filetime : aliased Filetime := To_Filetime (Modified_Time);
   Result : C_Int;
begin
   File :=
     Create_File
       (C_Path'Address,
        File_Read_Attributes or File_Write_Attributes,
        File_Share_Read or File_Share_Write or File_Share_Delete,
        System.Null_Address,
        Open_Existing,
        File_Attribute_Normal or File_Flag_Backup_Semantics,
        System.Null_Address);

   if File = System.Null_Address or else File = Invalid_Handle_Value then
      Hostkit.Errors.Set_Errno_From_Last_Error;
      return False;
   end if;

   Result :=
     Set_File_Time
       (File,
        System.Null_Address,
        Access_Filetime'Access,
        Modified_Filetime'Access);
   if Result = 0 then
      Hostkit.Errors.Set_Errno_From_Last_Error;
   end if;
   declare
      Ignored : constant C_Int := Close_Handle (File);
   begin
      null;
   end;
   return Result /= 0;

exception
   when others =>
      if File /= System.Null_Address and then File /= Invalid_Handle_Value then
         declare
            Ignored : constant C_Int := Close_Handle (File);
         begin
            null;
         end;
      end if;
      return False;
end Set_File_Times;
