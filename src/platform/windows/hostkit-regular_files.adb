with Ada.Strings.UTF_Encoding.Conversions;
with Interfaces.C;
with System;
with System.Storage_Elements;

package body Hostkit.Regular_Files is
   use type Interfaces.C.int;
   use type Interfaces.C.long_long;
   use type Interfaces.C.unsigned;
   use type System.Address;

   subtype C_Int is Interfaces.C.int;
   subtype C_DWord is Interfaces.C.unsigned;
   subtype C_Intptr is Interfaces.C.ptrdiff_t;
   subtype C_S64 is Interfaces.C.long_long;

   Generic_Read            : constant C_DWord := 16#8000_0000#;
   Share_All               : constant C_DWord := 7;
   Open_Existing           : constant C_DWord := 3;
   Flag_Sequential         : constant C_DWord := 16#0800_0000#;
   Flag_Open_Reparse_Point : constant C_DWord := 16#0020_0000#;
   Attribute_Directory     : constant C_DWord := 16#10#;
   Attribute_Reparse_Point : constant C_DWord := 16#400#;
   File_Type_Disk          : constant C_DWord := 1;
   Open_Binary             : constant C_Int := 16#8000#;
   Fsctl_Set_Sparse        : constant C_DWord := 16#0009_00C4#;
   Invalid_Handle          : constant System.Address :=
     System.Storage_Elements.To_Address (System.Storage_Elements.Integer_Address'Last);

   type File_Time is record
      Low  : C_DWord;
      High : C_DWord;
   end record with Convention => C;
   type File_Information is record
      Attributes      : C_DWord;
      Creation_Time   : File_Time;
      Access_Time     : File_Time;
      Modified_Time   : File_Time;
      Volume_Serial   : C_DWord;
      Size_High       : C_DWord;
      Size_Low        : C_DWord;
      Link_Count      : C_DWord;
      File_Index_High : C_DWord;
      File_Index_Low  : C_DWord;
   end record with Convention => C;

   function Create_File
     (Name       : System.Address;
      Access_Way : C_DWord;
      Share      : C_DWord;
      Security   : System.Address;
      Creation   : C_DWord;
      Flags      : C_DWord;
      Template   : System.Address) return System.Address
     with Import, Convention => Stdcall, External_Name => "CreateFileW";
   function Get_File_Information
     (Handle : System.Address; Info : access File_Information) return C_Int
     with Import, Convention => Stdcall, External_Name => "GetFileInformationByHandle";
   function Get_File_Type (Handle : System.Address) return C_DWord
     with Import, Convention => Stdcall, External_Name => "GetFileType";
   function Close_Handle (Handle : System.Address) return C_Int
     with Import, Convention => Stdcall, External_Name => "CloseHandle";
   function Open_Os_Handle (Handle : C_Intptr; Flags : C_Int) return C_Int
     with Import, Convention => C, External_Name => "_open_osfhandle";
   function Get_Os_Handle (Descriptor : C_Int) return C_Intptr
     with Import, Convention => C, External_Name => "_get_osfhandle";
   function Device_Io_Control
     (Handle     : System.Address;
      Code       : C_DWord;
      In_Buffer  : System.Address;
      In_Size    : C_DWord;
      Out_Buffer : System.Address;
      Out_Size   : C_DWord;
      Returned   : access C_DWord;
      Overlapped : System.Address) return C_Int
     with Import, Convention => Stdcall, External_Name => "DeviceIoControl";
   function Seek (Descriptor : C_Int; Offset : C_S64; Origin : C_Int) return C_S64
     with Import, Convention => C, External_Name => "_lseeki64";
   function Truncate (Descriptor : C_Int; Length : C_S64) return C_Int
     with Import, Convention => C, External_Name => "_chsize_s";

   --  UTF-16 for the wide Win32 calls. Wide_Strings.Decode raises for any
   --  code point above U+FFFF (it does not emit surrogates), which made every
   --  path holding an emoji or other non-BMP character unopenable.
   function Wide (Value : String) return Wide_String is
     (Ada.Strings.UTF_Encoding.Conversions.Convert (Value) & Wide_Character'Val (0));

   function Open_Read
     (Path         : String;
      Follow_Links : Boolean;
      Supported    : out Boolean) return GNAT.OS_Lib.File_Descriptor
   is
      Flags      : C_DWord := Flag_Sequential;
      Handle     : System.Address := Invalid_Handle;
      Info       : aliased File_Information;
      Descriptor : C_Int;
      Ignored    : C_Int;
   begin
      Supported := True;
      if not Follow_Links then
         Flags := Flags + Flag_Open_Reparse_Point;
      end if;
      declare
         Wide_Path : aliased Wide_String := Wide (Path);
      begin
         Handle := Create_File
           (Wide_Path'Address, Generic_Read, Share_All, System.Null_Address,
            Open_Existing, Flags, System.Null_Address);
         if Handle = Invalid_Handle then
            return GNAT.OS_Lib.Invalid_FD;
         end if;
         if Get_File_Information (Handle, Info'Access) = 0
           or else Get_File_Type (Handle) /= File_Type_Disk
           or else (Info.Attributes and (Attribute_Directory + Attribute_Reparse_Point)) /= 0
         then
            Ignored := Close_Handle (Handle);
            Handle := Invalid_Handle;
            return GNAT.OS_Lib.Invalid_FD;
         end if;
         Descriptor := Open_Os_Handle
           (C_Intptr (System.Storage_Elements.To_Integer (Handle)), Open_Binary);
         if Descriptor < 0 then
            Ignored := Close_Handle (Handle);
            Handle := Invalid_Handle;
            return GNAT.OS_Lib.Invalid_FD;
         end if;
         Handle := Invalid_Handle;
         return GNAT.OS_Lib.File_Descriptor (Descriptor);
      end;
   exception
      when others =>
         if Handle /= Invalid_Handle then
            Ignored := Close_Handle (Handle);
         end if;
         return GNAT.OS_Lib.Invalid_FD;
   end Open_Read;

   function Skip_Zeros
     (Descriptor : GNAT.OS_Lib.File_Descriptor;
      Count      : Integer) return Boolean
   is
      Returned : aliased C_DWord := 0;
      Handle   : constant System.Address := System.Storage_Elements.To_Address
        (System.Storage_Elements.Integer_Address (Get_Os_Handle (C_Int (Descriptor))));
   begin
      return Device_Io_Control
        (Handle, Fsctl_Set_Sparse, System.Null_Address, 0, System.Null_Address, 0,
         Returned'Access, System.Null_Address) /= 0
        and then Seek (C_Int (Descriptor), C_S64 (Count), 1) >= 0;
   end Skip_Zeros;

   function Finish_Sparse (Descriptor : GNAT.OS_Lib.File_Descriptor) return Boolean is
      Position : constant C_S64 := Seek (C_Int (Descriptor), 0, 1);
   begin
      return Position >= 0 and then Truncate (C_Int (Descriptor), Position) = 0;
   end Finish_Sparse;
end Hostkit.Regular_Files;
