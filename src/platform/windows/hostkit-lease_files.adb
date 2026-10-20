with Ada.Strings.UTF_Encoding.Conversions;
with Interfaces.C;
with System;
with System.Storage_Elements;

package body Hostkit.Lease_Files is
   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned_long;
   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_64;
   use type System.Address;

   subtype C_Int is Interfaces.C.int;
   subtype C_DWord is Interfaces.C.unsigned_long;
   subtype C_I64 is Interfaces.C.long_long;

   Invalid_Handle : constant System.Address :=
     System.Storage_Elements.To_Address
       (System.Storage_Elements.Integer_Address'Last);
   Generic_Read : constant C_DWord := 16#8000_0000#;
   Generic_Write : constant C_DWord := 16#4000_0000#;
   Share_Read : constant C_DWord := 1;
   Share_Write : constant C_DWord := 2;
   Create_New : constant C_DWord := 1;
   Open_Existing : constant C_DWord := 3;
   Hidden : constant C_DWord := 2;
   Open_Reparse_Point : constant C_DWord := 16#0020_0000#;
   Reparse_Point : constant C_DWord := 16#0000_0400#;
   Lock_Exclusive : constant C_DWord := 2;
   Lock_Immediate : constant C_DWord := 1;
   Error_Sharing : constant C_DWord := 32;
   Error_Lock : constant C_DWord := 33;
   Error_Not_Found : constant C_DWord := 2;
   Error_Path_Not_Found : constant C_DWord := 3;
   Error_Invalid_Name : constant C_DWord := 123;
   File_Begin : constant C_DWord := 0;
   File_Id_Info_Class : constant C_Int := 18;

   type Filetime is record
      Low, High : C_DWord := 0;
   end record with Convention => C;
   type File_Information is record
      Attributes : C_DWord := 0;
      Creation_Time, Access_Time, Modified_Time : Filetime;
      Volume_Serial, Size_High, Size_Low, Link_Count : C_DWord := 0;
      File_Index_High, File_Index_Low : C_DWord := 0;
   end record with Convention => C;
   type Identifier_Array is array (Natural range 0 .. 15) of Interfaces.Unsigned_8
     with Convention => C;
   type File_Id_Info is record
      Volume : Interfaces.Unsigned_64 := 0;
      Identifier : Identifier_Array := [others => 0];
   end record with Convention => C;
   type Overlapped is record
      Internal, Internal_High : System.Address := System.Null_Address;
      Offset, Offset_High : C_DWord := 0;
      Event : System.Address := System.Null_Address;
   end record with Convention => C;

   function Create_File
     (Name : System.Address; Access_Mode, Share_Mode : C_DWord;
      Security : System.Address; Disposition, Attributes : C_DWord;
      Template : System.Address) return System.Address
     with Import, Convention => Stdcall, External_Name => "CreateFileW";
   function Close_Handle (Handle : System.Address) return C_Int
     with Import, Convention => Stdcall, External_Name => "CloseHandle";
   function Lock_File_Ex
     (Handle : System.Address; Flags, Reserved, Bytes_Low, Bytes_High : C_DWord;
      Region : access Overlapped) return C_Int
     with Import, Convention => Stdcall, External_Name => "LockFileEx";
   function Unlock_File_Ex
     (Handle : System.Address; Reserved, Bytes_Low, Bytes_High : C_DWord;
      Region : access Overlapped) return C_Int
     with Import, Convention => Stdcall, External_Name => "UnlockFileEx";
   function Get_File_Information
     (Handle : System.Address; Info : access File_Information) return C_Int
     with Import, Convention => Stdcall, External_Name => "GetFileInformationByHandle";
   function Get_File_Information_Ex
     (Handle : System.Address; Kind : C_Int; Info : System.Address;
      Bytes : C_DWord) return C_Int
     with Import, Convention => Stdcall, External_Name => "GetFileInformationByHandleEx";
   function Get_Volume_Information
     (Handle : System.Address; Volume_Name : System.Address; Volume_Name_Size : C_DWord;
      Serial, Maximum_Name, Flags : System.Address; File_System : System.Address;
      File_System_Size : C_DWord) return C_Int
     with Import, Convention => Stdcall, External_Name => "GetVolumeInformationByHandleW";
   function Get_Last_Error return C_DWord
     with Import, Convention => Stdcall, External_Name => "GetLastError";
   function Set_File_Pointer
     (Handle : System.Address; Distance : C_I64; New_Position : System.Address;
      Method : C_DWord) return C_Int
     with Import, Convention => Stdcall, External_Name => "SetFilePointerEx";
   function Write_File
     (Handle, Buffer : System.Address; Bytes : C_DWord;
      Written : access C_DWord; Overlap : System.Address) return C_Int
     with Import, Convention => Stdcall, External_Name => "WriteFile";
   function Read_File
     (Handle, Buffer : System.Address; Bytes : C_DWord;
      Read_Count : access C_DWord; Overlap : System.Address) return C_Int
     with Import, Convention => Stdcall, External_Name => "ReadFile";
   function Flush_File_Buffers (Handle : System.Address) return C_Int
     with Import, Convention => Stdcall, External_Name => "FlushFileBuffers";
   function Get_File_Size (Handle : System.Address; Value : access C_I64) return C_Int
     with Import, Convention => Stdcall, External_Name => "GetFileSizeEx";

   function Wide (Value : String) return Wide_String is
     (Ada.Strings.UTF_Encoding.Conversions.Convert (Value)
      & Wide_Character'Val (0));
   function To_Handle (Item : Lease) return System.Address is
     (System.Storage_Elements.To_Address
        (System.Storage_Elements.Integer_Address (Item.Handle)));

   procedure Reset (Item : out Lease) is
   begin
      Item.Handle := -1;
      Item.Held := False;
   end Reset;

   function Valid_Id (Value : Identifier_Array) return Boolean is
      Nonzero, Not_Ones : Boolean := False;
   begin
      for Byte of Value loop
         Nonzero := Nonzero or else Byte /= 0;
         Not_Ones := Not_Ones or else Byte /= Interfaces.Unsigned_8'Last;
      end loop;
      return Nonzero and then Not_Ones;
   end Valid_Id;

   function Part (Value : Identifier_Array; First : Natural)
      return Interfaces.Unsigned_64
   is
      Result : Interfaces.Unsigned_64 := 0;
   begin
      for Offset in 0 .. 7 loop
         Result := Result or Interfaces.Shift_Left
           (Interfaces.Unsigned_64 (Value (First + Offset)), Offset * 8);
      end loop;
      return Result;
   end Part;

   function Is_NTFS (Handle : System.Address) return Boolean is
      Name : aliased Wide_String (1 .. 16) := [others => Wide_Character'Val (0)];
   begin
      return Get_Volume_Information
        (Handle, System.Null_Address, 0, System.Null_Address,
         System.Null_Address, System.Null_Address, Name'Address,
         C_DWord (Name'Length)) /= 0
        and then Name (1) in 'N' | 'n' and then Name (2) in 'T' | 't'
        and then Name (3) in 'F' | 'f' and then Name (4) in 'S' | 's'
        and then Name (5) = Wide_Character'Val (0);
   end Is_NTFS;

   function Identity_For (Handle : System.Address) return Lease_Identity is
      Id : aliased File_Id_Info;
      Info : aliased File_Information;
      Number : Interfaces.Unsigned_64;
   begin
      if Get_File_Information_Ex
        (Handle, File_Id_Info_Class, Id'Address,
         C_DWord (File_Id_Info'Size / 8)) /= 0
        and then Valid_Id (Id.Identifier)
      then
         return (True, Id.Volume, Part (Id.Identifier, 0),
                 Part (Id.Identifier, 8));
      end if;
      if Get_File_Information (Handle, Info'Access) = 0 or else not Is_NTFS (Handle) then
         return (others => <>);
      end if;
      Number := Interfaces.Shift_Left
        (Interfaces.Unsigned_64 (Info.File_Index_High), 32)
        or Interfaces.Unsigned_64 (Info.File_Index_Low);
      if Number = 0 or else Number = Interfaces.Unsigned_64'Last then
         return (others => <>);
      end if;
      return (True, Interfaces.Unsigned_64 (Info.Volume_Serial), Number, 0);
   end Identity_For;

   function Take_Lock
     (Handle : System.Address; Kind : Lock_Kind) return Open_Outcome
   is
      Region : aliased Overlapped;
      Flags : C_DWord := Lock_Immediate;
   begin
      Region.Offset := 16;
      if Kind = Exclusive then
         Flags := Flags or Lock_Exclusive;
      end if;
      if Lock_File_Ex (Handle, Flags, 0, 1, 0, Region'Access) /= 0 then
         return Opened;
      elsif Get_Last_Error in Error_Sharing | Error_Lock then
         return Busy;
      else
         return Error;
      end if;
   end Take_Lock;

   function Open_Handle
     (Path : String; Kind : Lock_Kind; Writable, New_File : Boolean;
      Item : out Lease) return Open_Outcome
   is
      Name : aliased Wide_String := Wide (Path);
      Handle : System.Address := Invalid_Handle;
      Info : aliased File_Information;
      Outcome : Open_Outcome;
      Code : C_DWord;
      Ignored : C_Int;
   begin
      Reset (Item);
      Handle := Create_File
        (Name'Address, Generic_Read + (if Writable then Generic_Write else 0),
         Share_Read + (if Writable then 0 else Share_Write),
         System.Null_Address, (if New_File then Create_New else Open_Existing),
         Open_Reparse_Point + (if New_File then Hidden else 0), System.Null_Address);
      if Handle = Invalid_Handle then
         Code := Get_Last_Error;
         if not New_File and then Code in Error_Not_Found | Error_Path_Not_Found | Error_Invalid_Name then
            return Refused;
         elsif Code in Error_Sharing | Error_Lock then
            return Busy;
         else
            return Error;
         end if;
      end if;
      if Get_File_Information (Handle, Info'Access) = 0
        or else (Info.Attributes and Reparse_Point) /= 0
      then
         Ignored := Close_Handle (Handle);
         return Refused;
      end if;
      Outcome := Take_Lock (Handle, Kind);
      if Outcome /= Opened then
         Ignored := Close_Handle (Handle);
         return Outcome;
      end if;
      Item.Handle := Interfaces.Integer_64
        (System.Storage_Elements.To_Integer (Handle));
      Item.Held := True;
      return Opened;
   exception
      when others =>
         if Handle /= Invalid_Handle then
            Ignored := Close_Handle (Handle);
         end if;
         Reset (Item);
         return Error;
   end Open_Handle;

   function Create (Path : String; Item : out Lease) return Open_Outcome is
     (Open_Handle (Path, Shared, True, True, Item));

   function Open
     (Path : String; Kind : Lock_Kind; Writable : Boolean;
      Item : out Lease) return Open_Outcome is
     (Open_Handle (Path, Kind, Writable, False, Item));

   procedure Release (Item : in out Lease) is
      Region : aliased Overlapped;
      Ignored : C_Int;
   begin
      if Item.Held then
         Region.Offset := 16;
         Ignored := Unlock_File_Ex (To_Handle (Item), 0, 1, 0, Region'Access);
         Ignored := Close_Handle (To_Handle (Item));
      end if;
      Item.Handle := -1;
      Item.Held := False;
   end Release;

   function Is_Held (Item : Lease) return Boolean is (Item.Held);

   function Write_At
     (Item : Lease; Data : Ada.Streams.Stream_Element_Array;
      Offset : Ada.Streams.Stream_Element_Offset := 0) return Boolean
   is
      Count : aliased C_DWord := 0;
      Position : Ada.Streams.Stream_Element_Offset := 0;
   begin
      if not Item.Held
        or else Offset < 0
        or else Data'Length > Natural (C_DWord'Last)
        or else Set_File_Pointer
          (To_Handle (Item), C_I64 (Offset), System.Null_Address, File_Begin) = 0
      then
         return False;
      end if;
      while Position < Ada.Streams.Stream_Element_Offset (Data'Length) loop
         Count := 0;
         if Write_File
           (To_Handle (Item), Data (Data'First + Position)'Address,
            C_DWord (Ada.Streams.Stream_Element_Offset (Data'Length) - Position),
            Count'Access, System.Null_Address) = 0
           or else Count = 0
           or else Count >
             C_DWord (Ada.Streams.Stream_Element_Offset (Data'Length) - Position)
         then
            return False;
         end if;
         Position := Position + Ada.Streams.Stream_Element_Offset (Count);
      end loop;
      return Flush_File_Buffers (To_Handle (Item)) /= 0;
   exception
      when others => return False;
   end Write_At;

   function Read_At
     (Item : Lease; Data : out Ada.Streams.Stream_Element_Array;
      Offset : Ada.Streams.Stream_Element_Offset := 0) return Boolean
   is
      Count : aliased C_DWord := 0;
      Position : Ada.Streams.Stream_Element_Offset := 0;
   begin
      if not Item.Held
        or else Offset < 0
        or else Data'Length > Natural (C_DWord'Last)
        or else Set_File_Pointer
          (To_Handle (Item), C_I64 (Offset), System.Null_Address, File_Begin) = 0
      then
         return False;
      end if;
      while Position < Ada.Streams.Stream_Element_Offset (Data'Length) loop
         Count := 0;
         if Read_File
           (To_Handle (Item), Data (Data'First + Position)'Address,
            C_DWord (Ada.Streams.Stream_Element_Offset (Data'Length) - Position),
            Count'Access, System.Null_Address) = 0
           or else Count = 0
           or else Count >
             C_DWord (Ada.Streams.Stream_Element_Offset (Data'Length) - Position)
         then
            return False;
         end if;
         Position := Position + Ada.Streams.Stream_Element_Offset (Count);
      end loop;
      return True;
   exception
      when others => return False;
   end Read_At;

   function Size (Item : Lease) return Long_Long_Integer is
      Value : aliased C_I64 := -1;
   begin
      if not Item.Held or else Get_File_Size (To_Handle (Item), Value'Access) = 0 then
         return -1;
      end if;
      return Long_Long_Integer (Value);
   exception
      when others => return -1;
   end Size;

   function Identity (Item : Lease) return Lease_Identity is
   begin
      return (if Item.Held then Identity_For (To_Handle (Item)) else (others => <>));
   end Identity;

   function Path_Matches (Item : Lease; Path : String) return Boolean is
      Name : aliased Wide_String := Wide (Path);
      Handle : System.Address := Invalid_Handle;
      Info : aliased File_Information;
      Left, Right : Lease_Identity;
      Ignored : C_Int;
   begin
      if not Item.Held then
         return False;
      end if;
      Handle := Create_File
        (Name'Address, Generic_Read, Share_Read + Share_Write,
         System.Null_Address, Open_Existing, Open_Reparse_Point,
         System.Null_Address);
      if Handle = Invalid_Handle then
         return False;
      end if;
      if Get_File_Information (Handle, Info'Access) = 0
        or else (Info.Attributes and Reparse_Point) /= 0
      then
         Ignored := Close_Handle (Handle);
         return False;
      end if;
      Left := Identity_For (To_Handle (Item));
      Right := Identity_For (Handle);
      Ignored := Close_Handle (Handle);
      return Left.Available and then Right.Available
        and then Left.Volume = Right.Volume and then Left.Low = Right.Low
        and then Left.High = Right.High;
   exception
      when others =>
         if Handle /= Invalid_Handle then
            Ignored := Close_Handle (Handle);
         end if;
         return False;
   end Path_Matches;
end Hostkit.Lease_Files;
