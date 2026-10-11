with Ada.Strings.UTF_Encoding.Wide_Strings;
with Interfaces.C;
with System;
with System.Storage_Elements;

package body Hostkit.Metadata_Copy is
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned_long;
   use type Interfaces.Unsigned_64;
   use type System.Address;
   use type System.Storage_Elements.Integer_Address;

   subtype C_Int is Interfaces.C.int;
   subtype C_DWord is Interfaces.C.unsigned_long;

   type Filetime is record
      Low, High : C_DWord;
   end record with Convention => C;

   type By_Handle_File_Information is record
      Attributes : C_DWord;
      Creation, Accessed, Modified : Filetime;
      Volume_Serial, Size_High, Size_Low, Link_Count : C_DWord;
      File_Index_High, File_Index_Low : C_DWord;
   end record with Convention => C;

   Invalid_Handle : constant System.Address :=
     System.Storage_Elements.To_Address (-1);
   File_Read_Attributes  : constant C_DWord := 16#0000_0080#;
   File_Write_Attributes : constant C_DWord := 16#0000_0100#;
   File_Share_All : constant C_DWord := 7;
   Open_Existing : constant C_DWord := 3;
   File_Flag_Backup_Semantics : constant C_DWord := 16#0200_0000#;
   File_Flag_Open_Reparse_Point : constant C_DWord := 16#0020_0000#;

   function Wide (Value : String) return Wide_String is
     (Ada.Strings.UTF_Encoding.Wide_Strings.Decode (Value)
        & Wide_Character'Val (0));

   function Create_File_W
     (Name : System.Address; Access_Mode, Share : C_DWord;
      Security : System.Address; Disposition, Flags : C_DWord;
      Template : System.Address) return System.Address
     with Import, Convention => Stdcall, External_Name => "CreateFileW";
   function Close_Handle (Handle : System.Address) return C_Int
     with Import, Convention => Stdcall, External_Name => "CloseHandle";
   function Get_File_Time
     (Handle : System.Address; Created : System.Address;
      Accessed, Modified : access Filetime) return C_Int
     with Import, Convention => Stdcall, External_Name => "GetFileTime";
   function Set_File_Time
     (Handle : System.Address; Created : System.Address;
      Accessed, Modified : access Filetime) return C_Int
     with Import, Convention => Stdcall, External_Name => "SetFileTime";
   function Get_File_Information
     (Handle : System.Address;
      Info : access By_Handle_File_Information) return C_Int
     with Import, Convention => Stdcall,
          External_Name => "GetFileInformationByHandle";

   function Open_Entry (Path : String; Access_Mode : C_DWord)
      return System.Address
   is
      Name : aliased Wide_String := Wide (Path);
   begin
      return Create_File_W
        (Name'Address, Access_Mode, File_Share_All, System.Null_Address,
         Open_Existing,
         File_Flag_Backup_Semantics + File_Flag_Open_Reparse_Point,
         System.Null_Address);
   exception
      when others =>
         return Invalid_Handle;
   end Open_Entry;

   function Value (Item : Filetime) return Interfaces.Integer_64 is
      Raw : constant Interfaces.Unsigned_64 :=
        Interfaces.Unsigned_64 (Item.High) * 2 ** 32
        + Interfaces.Unsigned_64 (Item.Low);
   begin
      return Interfaces.Integer_64 (Raw);
   end Value;

   function File_Time (Value : Interfaces.Integer_64) return Filetime is
      Raw : constant Interfaces.Unsigned_64 := Interfaces.Unsigned_64 (Value);
   begin
      return
        (Low => C_DWord (Raw and 16#FFFF_FFFF#),
         High => C_DWord (Raw / 2 ** 32));
   end File_Time;

   function Capture_Times
     (Path : String; Times : out Entry_Times) return Boolean
   is
      Handle : constant System.Address := Open_Entry (Path, File_Read_Attributes);
      Accessed, Modified : aliased Filetime;
      Ok : Boolean := Handle /= Invalid_Handle
        and then Get_File_Time
          (Handle, System.Null_Address, Accessed'Access, Modified'Access) /= 0;
      Ignored : C_Int;
   begin
      Times := [others => 0];
      if Ok then
         Times := [Value (Accessed), 0, Value (Modified), 0];
      end if;
      if Handle /= Invalid_Handle then
         Ignored := Close_Handle (Handle);
      end if;
      return Ok;
   exception
      when others =>
         Times := [others => 0];
         return False;
   end Capture_Times;

   function Apply_Times
     (Path : String; Times : Entry_Times) return Boolean
   is
      Handle : constant System.Address := Open_Entry (Path, File_Write_Attributes);
      Accessed : aliased Filetime := File_Time (Times (1));
      Modified : aliased Filetime := File_Time (Times (3));
      Ok : Boolean := Handle /= Invalid_Handle
        and then Set_File_Time
          (Handle, System.Null_Address, Accessed'Access, Modified'Access) /= 0;
      Ignored : C_Int;
   begin
      if Handle /= Invalid_Handle then
         Ignored := Close_Handle (Handle);
      end if;
      return Ok;
   exception
      when others =>
         return False;
   end Apply_Times;

   function Capture (Path : String) return Snapshot is
      Handle : constant System.Address := Open_Entry (Path, File_Read_Attributes);
      Info : aliased By_Handle_File_Information;
      Accessed, Modified : aliased Filetime;
      Result : Snapshot;
      Ignored : C_Int;
   begin
      Result.Available := Handle /= Invalid_Handle
        and then Get_File_Time
          (Handle, System.Null_Address, Accessed'Access, Modified'Access) /= 0
        and then Get_File_Information (Handle, Info'Access) /= 0;
      if Result.Available then
         Result.Times := [Value (Accessed), 0, Value (Modified), 0];
         Result.Links := Interfaces.Unsigned_64 (Info.Link_Count);
      end if;
      if Handle /= Invalid_Handle then
         Ignored := Close_Handle (Handle);
      end if;
      return Result;
   exception
      when others =>
         return No_Snapshot;
   end Capture;

   function Is_Available (Item : Snapshot) return Boolean is (Item.Available);
   function Link_Count (Item : Snapshot) return Interfaces.Unsigned_64 is (Item.Links);

   procedure Set_Times (Item : in out Snapshot; Times : Entry_Times) is
   begin
      Item.Times := Times;
   end Set_Times;

   function Apply
     (Item : Snapshot; Path : String; Preserve_Ownership : Boolean)
      return Boolean
   is
      pragma Unreferenced (Preserve_Ownership);
   begin
      return Item.Available and then Apply_Times (Path, Item.Times);
   end Apply;
end Hostkit.Metadata_Copy;
