separate (Hostkit.Metadata)
function Change_Stamp
  (Path      : String;
   Available : out Boolean)
   return String
is
   Wide_Path : aliased Wide_String := Wide (Path);
   File      : System.Address :=
     Create_File
       (Wide_Path'Address, File_Read_Attributes,
        File_Share_Read or File_Share_Write or File_Share_Delete,
        System.Null_Address, Open_Existing, File_Flag_Backup_Semantics,
        System.Null_Address);
   Legacy    : aliased By_Handle_File_Information;
   Basic     : aliased File_Basic_Info;

   Ticks_A_Second : constant := 10_000_000;
   Epoch_Seconds  : constant := 11_644_473_600;

   function Time_Words (Ticks : Interfaces.Integer_64) return String is
     (Interfaces.Integer_64'Image (Ticks / Ticks_A_Second - Epoch_Seconds) & "."
      & Interfaces.Integer_64'Image ((Ticks mod Ticks_A_Second) * 100));
begin
   Available := False;
   if File = Invalid_Handle_Value
     or else Get_File_Information (File, Legacy'Access) = 0
     or else Get_File_Information_Ex
       (File, File_Basic_Info_Class, Basic'Address, C_DWord (File_Basic_Info'Size / 8)) = 0
   then
      Close_Entry (File);
      return "";
   end if;
   Close_Entry (File);
   Available := True;
   return Time_Words (Basic.Modified_Time) & Time_Words (Basic.Change_Time)
     & Interfaces.Unsigned_64'Image
         (Interfaces.Shift_Left (Interfaces.Unsigned_64 (Legacy.Size_High), 32)
          or Interfaces.Unsigned_64 (Legacy.Size_Low))
     & Interfaces.Unsigned_64'Image
         (Interfaces.Shift_Left (Interfaces.Unsigned_64 (Legacy.File_Index_High), 32)
          or Interfaces.Unsigned_64 (Legacy.File_Index_Low));
exception
   when others =>
      Close_Entry (File);
      Available := False;
      return "";
end Change_Stamp;
