with Interfaces.C;
with System;
with System.Storage_Elements;

--  The Win32 types, constants and imports the Windows bodies share.
--
--  Each body used to declare its own copy of CreateFileW, CloseHandle,
--  GetLastError and the rest, and its own BY_HANDLE_FILE_INFORMATION; the
--  copies had drifted apart in names and spelling though never (yet) in
--  meaning. They live here once. A body still declares what only it calls.
--  This package is in the Windows source directory only, so no other host
--  ever sees it.
private package Hostkit.Win32 is

   --  A Win32 DWORD: 32 bits, as unsigned long is under LLP64.
   subtype DWORD is Interfaces.C.unsigned_long;

   --  A Win32 BOOL: nonzero for success.
   subtype BOOL is Interfaces.C.int;

   --  A Win32 HANDLE, kept as the pointer it is.
   subtype HANDLE is System.Address;

   --  INVALID_HANDLE_VALUE, (HANDLE) -1: what CreateFileW and FindFirstFileW
   --  return on failure, where most other calls return NULL.
   Invalid_Handle_Value : constant HANDLE :=
     System.Storage_Elements.To_Address (System.Storage_Elements.Integer_Address'Last);

   --  Access rights.

   --  GENERIC_READ.
   Generic_Read          : constant DWORD := 16#8000_0000#;
   --  GENERIC_WRITE.
   Generic_Write         : constant DWORD := 16#4000_0000#;
   --  FILE_APPEND_DATA.
   File_Append_Data      : constant DWORD := 16#0000_0004#;
   --  FILE_READ_ATTRIBUTES.
   File_Read_Attributes  : constant DWORD := 16#0000_0080#;
   --  FILE_WRITE_ATTRIBUTES.
   File_Write_Attributes : constant DWORD := 16#0000_0100#;
   --  TOKEN_QUERY.
   Token_Query           : constant DWORD := 16#0000_0008#;

   --  Sharing modes.

   --  FILE_SHARE_READ.
   File_Share_Read  : constant DWORD := 16#0000_0001#;
   --  FILE_SHARE_WRITE.
   File_Share_Write : constant DWORD := 16#0000_0002#;

   --  Creation dispositions.

   --  CREATE_NEW: fail if the file exists.
   Create_New    : constant DWORD := 1;
   --  OPEN_EXISTING: fail unless the file exists.
   Open_Existing : constant DWORD := 3;

   --  Attributes and flags.

   --  FILE_ATTRIBUTE_DIRECTORY.
   File_Attribute_Directory     : constant DWORD := 16#0000_0010#;
   --  FILE_ATTRIBUTE_NORMAL.
   File_Attribute_Normal        : constant DWORD := 16#0000_0080#;
   --  FILE_ATTRIBUTE_REPARSE_POINT.
   File_Attribute_Reparse_Point : constant DWORD := 16#0000_0400#;
   --  FILE_FLAG_OPEN_REPARSE_POINT: open a link itself, not what it names.
   File_Flag_Open_Reparse_Point : constant DWORD := 16#0020_0000#;
   --  FILE_FLAG_BACKUP_SEMANTICS: needed to open a directory at all.
   File_Flag_Backup_Semantics   : constant DWORD := 16#0200_0000#;

   --  Waits and processes.

   --  INFINITE: wait without a timeout.
   Infinite     : constant DWORD := 16#FFFF_FFFF#;
   --  STILL_ACTIVE: the exit code of a process that has not exited.
   Still_Active : constant DWORD := 259;

   --  Object and information classes.

   --  SE_FILE_OBJECT, for GetSecurityInfo.
   Se_File_Object     : constant Interfaces.C.int := 1;
   --  FileIdInfo, for GetFileInformationByHandleEx.
   File_Id_Info_Class : constant Interfaces.C.int := 18;
   --  FileAttributeTagInfo, for GetFileInformationByHandleEx.
   File_Attribute_Tag_Info_Class : constant Interfaces.C.int := 9;

   --  Reparse tags and the error a refused link gives.

   --  IO_REPARSE_TAG_MOUNT_POINT: a junction (or a volume mount point).
   Io_Reparse_Tag_Mount_Point : constant Interfaces.Unsigned_32 := 16#A000_0003#;
   --  IO_REPARSE_TAG_SYMLINK.
   Io_Reparse_Tag_Symlink     : constant Interfaces.Unsigned_32 := 16#A000_000C#;
   --  ERROR_STOPPED_ON_SYMLINK: Hostkit.Windows_Errors reads it as ELOOP.
   Error_Stopped_On_Symlink   : constant DWORD := 681;

   --  Whether a reparse tag is a link: only the symbolic-link and junction
   --  tags are. A OneDrive placeholder, a deduplicated file or an
   --  app-execution alias is a reparse point too, and an ordinary entry to
   --  the user, opened and listed like any other.
   --
   --  @param Tag A reparse tag.
   --  @return True for IO_REPARSE_TAG_SYMLINK and IO_REPARSE_TAG_MOUNT_POINT.
   function Is_Link_Tag (Tag : Interfaces.Unsigned_32) return Boolean is
     (Interfaces."=" (Tag, Io_Reparse_Tag_Symlink) or else Interfaces."=" (Tag, Io_Reparse_Tag_Mount_Point));

   --  A FILETIME: 100-nanosecond intervals since 1601, in two halves.
   type Filetime is record
      Low  : DWORD := 0;
      High : DWORD := 0;
   end record
     with Convention => C;

   --  BY_HANDLE_FILE_INFORMATION.
   type By_Handle_File_Information is record
      Attributes      : DWORD := 0;
      Creation_Time   : Filetime;
      Access_Time     : Filetime;
      Modified_Time   : Filetime;
      Volume_Serial   : DWORD := 0;
      Size_High       : DWORD := 0;
      Size_Low        : DWORD := 0;
      Link_Count      : DWORD := 0;
      File_Index_High : DWORD := 0;
      File_Index_Low  : DWORD := 0;
   end record
     with Convention => C;

   --  FILE_ATTRIBUTE_TAG_INFO.
   type Attribute_Tag_Info is record
      Attributes  : DWORD := 0;
      Reparse_Tag : Interfaces.Unsigned_32 := 0;
   end record
     with Convention => C;

   --  WIN32_FILE_ATTRIBUTE_DATA, as GetFileAttributesExW gives it.
   type Attribute_Data is record
      Attributes    : DWORD := 0;
      Creation_Time : Filetime;
      Access_Time   : Filetime;
      Modified_Time : Filetime;
      Size_High     : DWORD := 0;
      Size_Low      : DWORD := 0;
   end record
     with Convention => C;

   --  cFileName and cAlternateFileName of WIN32_FIND_DATAW: MAX_PATH and 14
   --  UTF-16 units, NUL-terminated within.
   type Find_Name is array (1 .. 260) of Wide_Character
     with Convention => C;
   type Find_Short_Name is array (1 .. 14) of Wide_Character
     with Convention => C;

   --  WIN32_FIND_DATAW. Reparse_Tag is dwReserved0, which holds the entry's
   --  reparse tag when its attributes have File_Attribute_Reparse_Point.
   type Find_Data is record
      Attributes     : DWORD := 0;
      Creation_Time  : Filetime;
      Access_Time    : Filetime;
      Write_Time     : Filetime;
      Size_High      : DWORD := 0;
      Size_Low       : DWORD := 0;
      Reparse_Tag    : Interfaces.Unsigned_32 := 0;
      Reserved_1     : DWORD := 0;
      File_Name      : Find_Name := [others => Wide_Character'Val (0)];
      Alternate_Name : Find_Short_Name := [others => Wide_Character'Val (0)];
   end record
     with Convention => C;

   --  Getting a layout wrong here does not fail loudly; it reads the wrong
   --  field and reports plausible nonsense. Pin the sizes, so the compiler
   --  catches any drift on any host.
   pragma Compile_Time_Error
     (Filetime'Size /= 8 * 8, "Win32 FILETIME must be 8 bytes");
   pragma Compile_Time_Error
     (By_Handle_File_Information'Size /= 52 * 8,
      "Win32 BY_HANDLE_FILE_INFORMATION must be 52 bytes");
   pragma Compile_Time_Error
     (Attribute_Tag_Info'Size /= 8 * 8,
      "Win32 FILE_ATTRIBUTE_TAG_INFO must be 8 bytes");
   pragma Compile_Time_Error
     (Attribute_Data'Size /= 36 * 8,
      "Win32 WIN32_FILE_ATTRIBUTE_DATA must be 36 bytes");
   pragma Compile_Time_Error
     (Find_Data'Size /= 592 * 8,
      "Win32 WIN32_FIND_DATAW must be 592 bytes");

   --  The calling thread's last error code.
   --
   --  @return GetLastError.
   function Get_Last_Error return DWORD
     with Import, Convention => Stdcall, External_Name => "GetLastError";

   --  CreateFileW: open or create a file, directory or device.
   --
   --  @param Name The path, NUL-terminated UTF-16.
   --  @param Access_Way The access rights wanted.
   --  @param Share What other openers may do meanwhile.
   --  @param Security A SECURITY_ATTRIBUTES, or null.
   --  @param Creation The creation disposition.
   --  @param Flags The attributes and FILE_FLAG_ flags.
   --  @param Template A template handle, or null.
   --  @return The handle, or Invalid_Handle_Value.
   function Create_File
     (Name       : System.Address;
      Access_Way : DWORD;
      Share      : DWORD;
      Security   : System.Address;
      Creation   : DWORD;
      Flags      : DWORD;
      Template   : System.Address)
      return HANDLE
     with Import, Convention => Stdcall, External_Name => "CreateFileW";

   --  CloseHandle.
   --
   --  @param Object The handle to close.
   --  @return Nonzero on success.
   function Close_Handle (Object : HANDLE) return BOOL
     with Import, Convention => Stdcall, External_Name => "CloseHandle";

   --  LocalFree: release what a Win32 call allocated for the caller.
   --
   --  @param Memory The block, or null.
   --  @return Null on success.
   function Local_Free (Memory : System.Address) return System.Address
     with Import, Convention => Stdcall, External_Name => "LocalFree";

   --  GetFileType.
   --
   --  @param Object The handle.
   --  @return FILE_TYPE_DISK, _CHAR, _PIPE or _UNKNOWN.
   function Get_File_Type (Object : HANDLE) return DWORD
     with Import, Convention => Stdcall, External_Name => "GetFileType";

   --  GetFileInformationByHandle.
   --
   --  @param Object The handle.
   --  @param Info Receives the information.
   --  @return Nonzero on success.
   function Get_File_Information
     (Object : HANDLE;
      Info   : access By_Handle_File_Information)
      return BOOL
     with Import, Convention => Stdcall, External_Name => "GetFileInformationByHandle";

   --  GetFileInformationByHandleEx.
   --
   --  @param Object The handle.
   --  @param Kind The FILE_INFO_BY_HANDLE_CLASS.
   --  @param Info Receives the information.
   --  @param Size Info's size in bytes.
   --  @return Nonzero on success.
   function Get_File_Information_Ex
     (Object : HANDLE;
      Kind   : Interfaces.C.int;
      Info   : System.Address;
      Size   : DWORD)
      return BOOL
     with Import, Convention => Stdcall, External_Name => "GetFileInformationByHandleEx";

   --  Whether the entry open as Object, whose attributes are Attributes, is
   --  a link -- a symbolic link or a junction, read from its reparse tag
   --  (FILE_ATTRIBUTE_TAG_INFO) -- rather than an ordinary entry. Any other
   --  reparse point is ordinary (Is_Link_Tag). One whose tag cannot be read
   --  is taken for a link, which is never followed.
   --
   --  @param Object The handle, opened with FILE_FLAG_OPEN_REPARSE_POINT or
   --    not; either way it is the entry the handle holds that is asked about.
   --  @param Attributes The handle's attributes, as GetFileInformationByHandle
   --    gave them.
   --  @param Error Zero when not a link; else the Windows error that says why
   --    it was refused: Error_Stopped_On_Symlink for a link, the failing
   --    call's own when the tag could not be read.
   --  @return True when the handle holds a link.
   function Is_Held_Link (Object : HANDLE; Attributes : DWORD; Error : out DWORD) return Boolean;

   --  GetFinalPathNameByHandleW.
   --
   --  @param Object The handle.
   --  @param Path Receives the path, UTF-16.
   --  @param Count Path's capacity in characters.
   --  @param Flags The FILE_NAME_ and VOLUME_NAME_ flags.
   --  @return The path's length, the length needed, or 0 on failure.
   function Get_Final_Path_Name
     (Object : HANDLE;
      Path   : System.Address;
      Count  : DWORD;
      Flags  : DWORD)
      return DWORD
     with Import, Convention => Stdcall, External_Name => "GetFinalPathNameByHandleW";

   --  GetFileAttributesW.
   --
   --  @param Name The path, NUL-terminated UTF-16.
   --  @return The attributes, or INVALID_FILE_ATTRIBUTES.
   function Get_File_Attributes (Name : System.Address) return DWORD
     with Import, Convention => Stdcall, External_Name => "GetFileAttributesW";

   --  SetFileAttributesW.
   --
   --  @param Name The path, NUL-terminated UTF-16.
   --  @param Attributes The attributes to set.
   --  @return Nonzero on success.
   function Set_File_Attributes (Name : System.Address; Attributes : DWORD) return BOOL
     with Import, Convention => Stdcall, External_Name => "SetFileAttributesW";

   --  GetFileAttributesExW.
   --
   --  @param Name The path, NUL-terminated UTF-16.
   --  @param Level The GET_FILEEX_INFO_LEVELS; 0 is GetFileExInfoStandard,
   --    which fills an Attribute_Data.
   --  @param Data Receives the attributes, times and size.
   --  @return Nonzero on success.
   function Get_File_Attributes_Ex
     (Name  : System.Address;
      Level : Interfaces.C.int;
      Data  : access Attribute_Data)
      return BOOL
     with Import, Convention => Stdcall, External_Name => "GetFileAttributesExW";

   --  FindFirstFileW.
   --
   --  @param Name The path or pattern, NUL-terminated UTF-16.
   --  @param Data Receives the first entry found.
   --  @return The search handle, or Invalid_Handle_Value.
   function Find_First_File (Name : System.Address; Data : access Find_Data) return HANDLE
     with Import, Convention => Stdcall, External_Name => "FindFirstFileW";

   --  FindNextFileW.
   --
   --  @param Object A FindFirstFileW handle.
   --  @param Data Receives the next entry found.
   --  @return Nonzero on success; zero with ERROR_NO_MORE_FILES at the end.
   function Find_Next_File (Object : HANDLE; Data : access Find_Data) return BOOL
     with Import, Convention => Stdcall, External_Name => "FindNextFileW";

   --  FindClose.
   --
   --  @param Object A FindFirstFileW handle.
   --  @return Nonzero on success.
   function Find_Close (Object : HANDLE) return BOOL
     with Import, Convention => Stdcall, External_Name => "FindClose";

   --  ReadFile, synchronous unless Overlapped is given.
   --
   --  @param Object The handle.
   --  @param Buffer Receives the bytes.
   --  @param To_Read How many bytes to read at most.
   --  @param Did_Read Receives how many were read.
   --  @param Overlapped An OVERLAPPED, or null.
   --  @return Nonzero on success.
   function Read_File
     (Object     : HANDLE;
      Buffer     : System.Address;
      To_Read    : DWORD;
      Did_Read   : access DWORD;
      Overlapped : System.Address)
      return BOOL
     with Import, Convention => Stdcall, External_Name => "ReadFile";

   --  WriteFile, synchronous unless Overlapped is given.
   --
   --  @param Object The handle.
   --  @param Buffer The bytes.
   --  @param To_Write How many bytes to write.
   --  @param Did_Write Receives how many were written.
   --  @param Overlapped An OVERLAPPED, or null.
   --  @return Nonzero on success.
   function Write_File
     (Object     : HANDLE;
      Buffer     : System.Address;
      To_Write   : DWORD;
      Did_Write  : access DWORD;
      Overlapped : System.Address)
      return BOOL
     with Import, Convention => Stdcall, External_Name => "WriteFile";

   --  PeekNamedPipe.
   --
   --  @param Pipe The pipe handle.
   --  @param Buffer Receives copied bytes, or null.
   --  @param Buffer_Size Buffer's size in bytes.
   --  @param Bytes_Read Receives how many were copied, or null.
   --  @param Total_Available Receives how many are waiting, or null.
   --  @param Bytes_Left Receives what is left of the current message, or null.
   --  @return Nonzero on success.
   function Peek_Named_Pipe
     (Pipe            : HANDLE;
      Buffer          : System.Address;
      Buffer_Size     : DWORD;
      Bytes_Read      : access DWORD;
      Total_Available : access DWORD;
      Bytes_Left      : access DWORD)
      return BOOL
     with Import, Convention => Stdcall, External_Name => "PeekNamedPipe";

   --  GetStdHandle.
   --
   --  @param Which STD_INPUT_HANDLE, STD_OUTPUT_HANDLE or STD_ERROR_HANDLE.
   --  @return The handle, null, or Invalid_Handle_Value.
   function Get_Std_Handle (Which : DWORD) return HANDLE
     with Import, Convention => Stdcall, External_Name => "GetStdHandle";

   --  GetConsoleMode; fails on anything but a console.
   --
   --  @param Object The handle.
   --  @param Mode Receives the mode.
   --  @return Nonzero on success.
   function Get_Console_Mode (Object : HANDLE; Mode : access DWORD) return BOOL
     with Import, Convention => Stdcall, External_Name => "GetConsoleMode";

   --  The CRT's _get_osfhandle: the handle behind a C descriptor.
   --
   --  @param Descriptor The descriptor.
   --  @return The handle, or Invalid_Handle_Value.
   function Get_Osfhandle (Descriptor : Interfaces.C.int) return HANDLE
     with Import, Convention => C, External_Name => "_get_osfhandle";

   --  GetCurrentProcess: a pseudo-handle that needs no closing.
   --
   --  @return The pseudo-handle.
   function Get_Current_Process return HANDLE
     with Import, Convention => Stdcall, External_Name => "GetCurrentProcess";

   --  WaitForSingleObject.
   --
   --  @param Object The handle to wait on.
   --  @param Milliseconds The timeout, or Infinite.
   --  @return WAIT_OBJECT_0, WAIT_TIMEOUT or WAIT_FAILED.
   function Wait_For_Single_Object (Object : HANDLE; Milliseconds : DWORD) return DWORD
     with Import, Convention => Stdcall, External_Name => "WaitForSingleObject";

   --  Sleep.
   --
   --  @param Milliseconds How long.
   procedure Sleep (Milliseconds : DWORD)
     with Import, Convention => Stdcall, External_Name => "Sleep";

   --  OpenProcessToken.
   --
   --  @param Process The process handle.
   --  @param Desired The access rights wanted.
   --  @param Token Receives the token handle.
   --  @return Nonzero on success.
   function Open_Process_Token
     (Process : HANDLE;
      Desired : DWORD;
      Token   : access HANDLE)
      return BOOL
     with Import, Convention => Stdcall, External_Name => "OpenProcessToken";

   --  GetTokenInformation.
   --
   --  @param Token The token handle.
   --  @param Class The TOKEN_INFORMATION_CLASS.
   --  @param Information Receives the information, or null.
   --  @param Length Information's size in bytes.
   --  @param Returned Receives the size used or needed.
   --  @return Nonzero on success.
   function Get_Token_Information
     (Token       : HANDLE;
      Class       : Interfaces.C.int;
      Information : System.Address;
      Length      : DWORD;
      Returned    : access DWORD)
      return BOOL
     with Import, Convention => Stdcall, External_Name => "GetTokenInformation";

   --  GetSecurityInfo. Each of Owner, Group, Dacl and Sacl is the address
   --  of a pointer to receive, or null.
   --
   --  @param Object The handle.
   --  @param Object_Type The SE_OBJECT_TYPE, Se_File_Object for a file.
   --  @param Information Which parts to read.
   --  @param Owner Receives the owner SID, or null.
   --  @param Group Receives the primary group SID, or null.
   --  @param Dacl Receives the DACL, or null.
   --  @param Sacl Receives the SACL, or null.
   --  @param Descriptor Receives the descriptor, to free with Local_Free.
   --  @return ERROR_SUCCESS or the error.
   function Get_Security_Info
     (Object      : HANDLE;
      Object_Type : Interfaces.C.int;
      Information : DWORD;
      Owner       : System.Address;
      Group       : System.Address;
      Dacl        : System.Address;
      Sacl        : System.Address;
      Descriptor  : access System.Address)
      return DWORD
     with Import, Convention => Stdcall, External_Name => "GetSecurityInfo";

   --  GetVolumePathNameW: the mount point a path is on.
   --
   --  @param Name The path, NUL-terminated UTF-16.
   --  @param Root Receives the mount point.
   --  @param Length Root's capacity in characters.
   --  @return Nonzero on success.
   function Get_Volume_Path_Name
     (Name   : System.Address;
      Root   : System.Address;
      Length : DWORD)
      return BOOL
     with Import, Convention => Stdcall, External_Name => "GetVolumePathNameW";

   --  GetVolumeInformationByHandleW.
   --
   --  @param Object A handle on the volume.
   --  @param Volume_Name Receives the label, or null.
   --  @param Volume_Name_Size Volume_Name's capacity in characters.
   --  @param Serial Receives the serial number, or null.
   --  @param Max_Component Receives the longest name, or null.
   --  @param Flags Receives the FILE_ flags, or null.
   --  @param File_System_Name Receives the file system's name, or null.
   --  @param File_System_Name_Size File_System_Name's capacity in characters.
   --  @return Nonzero on success.
   function Get_Volume_Information_By_Handle
     (Object                : HANDLE;
      Volume_Name           : System.Address;
      Volume_Name_Size      : DWORD;
      Serial                : access DWORD;
      Max_Component         : access DWORD;
      Flags                 : access DWORD;
      File_System_Name      : System.Address;
      File_System_Name_Size : DWORD)
      return BOOL
     with Import, Convention => Stdcall, External_Name => "GetVolumeInformationByHandleW";

   --  GetDriveTypeW.
   --
   --  @param Root The root, NUL-terminated UTF-16 with a trailing backslash.
   --  @return The DRIVE_ kind.
   function Get_Drive_Type (Root : System.Address) return Interfaces.C.unsigned
     with Import, Convention => Stdcall, External_Name => "GetDriveTypeW";

end Hostkit.Win32;
