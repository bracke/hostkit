with Hostkit.Errors;
with Hostkit.Windows_Errors;
with Hostkit.Windows_Paths;
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
   --  The wide open, with the permission argument it takes as a variadic one.
   function Wide_Open (Name : System.Address; Flags : C_Int; Permission : C_Int) return C_Int
     with Import, Convention => C_Variadic_2, External_Name => "_wopen";
   function Seek (Descriptor : C_Int; Offset : C_S64; Origin : C_Int) return C_S64
     with Import, Convention => C, External_Name => "_lseeki64";
   function Set_End_Of_File (Handle : System.Address) return C_Int
     with Import, Convention => Stdcall, External_Name => "SetEndOfFile";
   function Delete_File (Name : System.Address) return C_Int
     with Import, Convention => Stdcall, External_Name => "DeleteFileW";

   Generic_Write        : constant C_DWord := 16#4000_0000#;
   Create_New_File      : constant C_DWord := 1;
   Attribute_Normal     : constant C_DWord := 16#80#;
   Attribute_Sparse     : constant C_DWord := 16#200#;
   Attribute_Encrypted  : constant C_DWord := 16#4000#;
   Open_Write_Only      : constant C_Int := 16#0001#;
   Error_Not_Supported  : constant := 50;

   --  The Win32 handle under a C runtime descriptor.
   function Handle_Of (Descriptor : GNAT.OS_Lib.File_Descriptor) return System.Address is
     (System.Storage_Elements.To_Address
        (System.Storage_Elements.Integer_Address (Get_Os_Handle (C_Int (Descriptor)))));

   --  UTF-16 for the wide Win32 calls. Wide_Strings.Decode raises for any
   --  code point above U+FFFF (it does not emit surrogates), which made every
   --  path holding an emoji or other non-BMP character unopenable.
   function Wide (Value : String) return Wide_String renames Hostkit.Windows_Paths.Native;

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
            Hostkit.Errors.Set_Errno_From_Last_Error;
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

   --  An encrypted file is created by CreateFileW with
   --  FILE_ATTRIBUTE_ENCRYPTED (which _wopen cannot ask for), and checked to
   --  be encrypted before a byte is written to it: a volume without EFS may
   --  make it a plain file instead.
   function Create_Encrypted (Path : String) return GNAT.OS_Lib.File_Descriptor is
      Wide_Path  : aliased constant Wide_String := Wide (Path);
      Handle     : System.Address;
      Info       : aliased File_Information;
      Descriptor : C_Int;
      Ignored    : C_Int;
   begin
      --  No security attributes: the handle is not inherited.
      Handle := Create_File
        (Wide_Path'Address, Generic_Write, 0, System.Null_Address, Create_New_File,
         Attribute_Normal + Attribute_Encrypted, System.Null_Address);
      if Handle = Invalid_Handle then
         Hostkit.Errors.Set_Errno_From_Last_Error;
         return GNAT.OS_Lib.Invalid_FD;
      end if;
      if Get_File_Information (Handle, Info'Access) = 0
        or else (Info.Attributes and Attribute_Encrypted) = 0
      then
         Ignored := Close_Handle (Handle);
         Ignored := Delete_File (Wide_Path'Address);
         Hostkit.Windows_Errors.Set_Errno_From (Error_Not_Supported);
         return GNAT.OS_Lib.Invalid_FD;
      end if;
      Descriptor := Open_Os_Handle
        (C_Intptr (System.Storage_Elements.To_Integer (Handle)), Open_Write_Only + Open_Binary);
      if Descriptor < 0 then
         Ignored := Close_Handle (Handle);
         Ignored := Delete_File (Wide_Path'Address);
         return GNAT.OS_Lib.Invalid_FD;
      end if;
      return GNAT.OS_Lib.File_Descriptor (Descriptor);
   end Create_Encrypted;

   --  _O_WRONLY, _O_CREAT, _O_EXCL and _O_NOINHERIT, binary; the
   --  permission is _S_IREAD, with _S_IWRITE when Mode lets the owner write.
   function Create_New
     (Path      : String;
      Mode      : Natural := 8#644#;
      Encrypted : Boolean := False) return GNAT.OS_Lib.File_Descriptor
   is
      Write_Only : constant C_Int := 16#0001#;
      No_Inherit : constant C_Int := 16#0080#;
      Create     : constant C_Int := 16#0100#;
      Exclusive  : constant C_Int := 16#0400#;
      Readable   : constant C_Int := 16#0100#;
      Writable   : constant C_Int := 16#0080#;
      Owner_Write : constant Natural := 8#200#;
      E_No_Ent    : constant := 2;
      E_Acces     : constant := 13;
   begin
      if Path = "" or else (for some C of Path => C = ASCII.NUL) then
         return GNAT.OS_Lib.Invalid_FD;
      elsif Encrypted then
         return Create_Encrypted (Path);
      end if;
      declare
         Wide_Path  : aliased constant Wide_String := Wide (Path);
         Descriptor : constant C_Int := Wide_Open
           (Wide_Path'Address,
            Write_Only + Create + Exclusive + No_Inherit + Open_Binary,
            Readable + (if (Mode / Owner_Write) mod 2 = 1 then Writable else 0));
      begin
         if Descriptor >= 0 then
            return GNAT.OS_Lib.File_Descriptor (Descriptor);
         end if;
         --  _wopen reads CreateFileW's refusal through _dosmaperr, which
         --  folds a sharing violation and a write-protected medium into
         --  EACCES and a name too long into ENOENT. Those two came from
         --  CreateFileW, whose own reason is still the last error.
         if GNAT.OS_Lib.Errno in E_Acces | E_No_Ent then
            Hostkit.Errors.Set_Errno_From_Last_Error;
         end if;
         return GNAT.OS_Lib.Invalid_FD;
      end;
   exception
      when others =>
         return GNAT.OS_Lib.Invalid_FD;
   end Create_New;

   --  FSCTL_SET_SPARSE once per file: the attribute it sets says whether
   --  this file already had it.
   function Skip_Zeros
     (Descriptor : GNAT.OS_Lib.File_Descriptor;
      Count      : Integer) return Boolean
   is
      Returned : aliased C_DWord := 0;
      Info     : aliased File_Information;
      Handle   : constant System.Address := Handle_Of (Descriptor);
   begin
      if Get_File_Information (Handle, Info'Access) = 0 then
         Hostkit.Errors.Set_Errno_From_Last_Error;
         return False;
      end if;
      if (Info.Attributes and Attribute_Sparse) = 0
        and then Device_Io_Control
          (Handle, Fsctl_Set_Sparse, System.Null_Address, 0, System.Null_Address, 0,
           Returned'Access, System.Null_Address) = 0
      then
         Hostkit.Errors.Set_Errno_From_Last_Error;
         return False;
      end if;
      return Seek (C_Int (Descriptor), C_S64 (Count), 1) >= 0;
   end Skip_Zeros;

   --  _chsize_s extends a file by writing zeros, which would allocate the
   --  trailing hole; SetEndOfFile at the current position (where _lseeki64
   --  left the handle) extends a sparse file without allocating.
   function Finish_Sparse (Descriptor : GNAT.OS_Lib.File_Descriptor) return Boolean is
      Position : constant C_S64 := Seek (C_Int (Descriptor), 0, 1);
   begin
      if Position < 0 then
         return False;
      elsif Set_End_Of_File (Handle_Of (Descriptor)) = 0 then
         Hostkit.Errors.Set_Errno_From_Last_Error;
         return False;
      end if;
      return True;
   end Finish_Sparse;
end Hostkit.Regular_Files;
