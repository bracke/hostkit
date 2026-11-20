separate (Hostkit.Metadata)
function Identity_From_Handle
  (File  : System.Address;
   Info  : access By_Handle_File_Information;
   Error : out Interfaces.Unsigned_32) return Entry_Identity
is
   Error_Not_Supported : constant Interfaces.Unsigned_32 := 50;
   Id     : aliased File_Id_Info;
   Number : Identity_Field;
begin
   Error := 0;
   if Get_File_Information (File, Info) = 0 then
      Error := Interfaces.Unsigned_32 (Get_Last_Error);
      return (others => <>);
   end if;
   if Get_File_Information_Ex
     (File, File_Id_Info_Class, Id'Address, C_DWord (File_Id_Info'Size / 8)) /= 0
     and then Valid_Identifier (Id.Identifier)
   then
      return
        (Available       => True,
         Volume          => Id.Volume_Serial,
         File_Number     => Identifier_Part (Id.Identifier, 0),
         Generation_High => Identifier_Part (Id.Identifier, 8),
         Generation_Low  => 0);
   end if;
   Number := Interfaces.Shift_Left (Identity_Field (Info.File_Index_High), 32)
     or Identity_Field (Info.File_Index_Low);
   --  Off NTFS (FAT, exFAT) the index names the directory entry: stable
   --  while the entry stays put, as Linux's vfat inode numbers are, and
   --  enough for the checks a copy makes. Refusing it failed every copy
   --  onto a USB stick.
   if Number = 0 or else Number = Identity_Field'Last then
      Error := Error_Not_Supported;
      return (others => <>);
   end if;
   return
     (Available       => True,
      Volume          => Identity_Field (Info.Volume_Serial),
      File_Number     => Number,
      Generation_High => 0,
      Generation_Low  => 0);
end Identity_From_Handle;
