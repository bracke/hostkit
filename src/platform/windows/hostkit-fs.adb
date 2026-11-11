with Hostkit.Environment;
with Ada.Characters.Handling;
with Ada.Containers.Indefinite_Vectors;
with Ada.IO_Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Wide_Unbounded;

with GNAT.OS_Lib;

with Hostkit.Errors;
with Hostkit.Fs.Instants;
with Hostkit.Windows_Paths;
with Interfaces.C;
with Interfaces.C_Streams;

with System;
with System.Storage_Elements;

package body Hostkit.Fs is

   use type Interfaces.C.int;
   use type Interfaces.C.unsigned_long;

   subtype C_DWord is Interfaces.C.unsigned_long;

   Invalid_File_Attributes      : constant C_DWord := 16#FFFF_FFFF#;
   File_Attribute_Reparse_Point : constant C_DWord := 16#0000_0400#;
   File_Attribute_Directory     : constant C_DWord := 16#0000_0010#;

   Symbolic_Link_Allow_Unprivileged : constant C_DWord := 16#0000_0002#;
   Symbolic_Link_Directory          : constant C_DWord := 16#0000_0001#;

   --  Paths are UTF-8 here and UTF-16 to Windows: the "A" entry points would
   --  read them in the ANSI code page, so any non-ASCII path (a profile named
   --  Jürgen) would not be found.
   function Get_File_Attributes
     (Name : System.Address)
      return C_DWord
     with Import => True, Convention => Stdcall, External_Name => "GetFileAttributesW";

   function Get_Temp_Path
     (Buffer_Length : C_DWord;
      Buffer        : System.Address)
      return C_DWord
     with Import => True, Convention => Stdcall, External_Name => "GetTempPathW";

   --  WIN32_FIND_DATAW, of which only the reparse tag (dwReserved0, at byte 36
   --  for a reparse point) is read.
   type Find_Data is array (1 .. 592) of Interfaces.Unsigned_8 with Alignment => 8;

   function Find_First_File
     (Name : System.Address;
      Data : access Find_Data)
      return System.Address
     with Import => True, Convention => Stdcall, External_Name => "FindFirstFileW";

   function Find_Close (Handle : System.Address) return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "FindClose";

   Io_Reparse_Tag_Symlink     : constant Interfaces.Unsigned_32 := 16#A000_000C#;
   Io_Reparse_Tag_Mount_Point : constant Interfaces.Unsigned_32 := 16#A000_0003#;

   function Create_Symbolic_Link
     (Link   : System.Address;
      Target : System.Address;
      Flags  : C_DWord)
      return Interfaces.C.char
     with Import => True, Convention => Stdcall, External_Name => "CreateSymbolicLinkW";

   function Wide (Value : String) return Wide_String renames Hostkit.Windows_Paths.Native;

   --  Text that is not a path to open: a link's target is stored as given.
   function Wide_Text (Value : String) return Wide_String is
     (Hostkit.Windows_Paths.From_UTF_8 (Value) & Wide_Character'Val (0));

   --  A symbolic link and a junction are both reparse points, and this is how Windows
   --  says so. There is no lstat, which is why GNAT's Is_Symbolic_Link cannot answer
   --  here and says False instead.
   function Is_Hidden (Path : String) return Boolean is
      File_Attribute_Hidden : constant C_DWord := 16#0000_0002#;
      Wide_Path  : aliased Wide_String := Wide (Path);
      Attributes : constant C_DWord := Get_File_Attributes (Wide_Path'Address);
   begin
      return Attributes /= Invalid_File_Attributes and then (Attributes and File_Attribute_Hidden) /= 0;
   exception
      when others =>
         return False;
   end Is_Hidden;

   --  Whether Path names a device rather than a file on a disk, asked of
   --  the device itself; defined below, beside the calls it makes.
   function Is_Device (Path : String) return Boolean;

   --  GetFileAttributesW through the long form, which GNAT's own stat lacks.
   --  A device (NUL, CON, a \\.\ name) is asked first: GetFileAttributesW
   --  reads one as an ordinary file, or as nothing at all.
   function Kind_Of (Path : String) return Entry_Kind is
      Wide_Path  : aliased Wide_String := Wide (Path);
      Attributes : constant C_DWord := Get_File_Attributes (Wide_Path'Address);
   begin
      if Path = "" then
         return Missing_Entry;
      elsif Is_Device (Path) then
         return Special_File_Entry;
      elsif Attributes = Invalid_File_Attributes then
         return Missing_Entry;
      elsif (Attributes and File_Attribute_Directory) /= 0 then
         return Directory_Entry;
      end if;
      return Ordinary_File_Entry;
   exception
      when others =>
         return Missing_Entry;
   end Kind_Of;

   --  Only the symbolic-link and junction tags are links: OneDrive
   --  placeholders, deduplicated files and app-execution aliases are reparse
   --  points too, but ordinary files and folders to the user.
   function Is_Link (Path : String) return Boolean is
      use type Interfaces.Unsigned_32;
      use type System.Address;
      Wide_Path  : aliased Wide_String := Wide (Path);
      Attributes : constant C_DWord := Get_File_Attributes (Wide_Path'Address);
      Data       : aliased Find_Data := [others => 0];
      Handle     : System.Address;
      Tag        : Interfaces.Unsigned_32;
      Invalid_Handle : constant System.Address := System.Storage_Elements.To_Address
        (System.Storage_Elements.Integer_Address'Last);
   begin
      if Attributes = Invalid_File_Attributes
        or else (Attributes and File_Attribute_Reparse_Point) = 0
      then
         return False;
      end if;
      Handle := Find_First_File (Wide_Path'Address, Data'Access);
      if Handle = Invalid_Handle then
         --  The tag is unreadable: a reparse point is still safest treated
         --  as a link, which is never followed.
         return True;
      end if;
      if Find_Close (Handle) = 0 then
         null;
      end if;
      Tag := Interfaces.Unsigned_32 (Data (37))
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (38)), 8)
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (39)), 16)
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (40)), 24);
      return Tag = Io_Reparse_Tag_Symlink or else Tag = Io_Reparse_Tag_Mount_Point;
   exception
      when others =>
         return False;
   end Is_Link;

   --  CreateFileW's arguments for asking an entry about itself: no data
   --  access, every kind of sharing, and a folder opened as well as a file.
   File_Read_Attributes_Access : constant C_DWord := 16#0000_0080#;
   Read_Control_Access         : constant C_DWord := 16#0002_0000#;
   Share_Everything            : constant C_DWord := 7;
   Open_Existing_Only          : constant C_DWord := 3;
   Backup_Semantics_Flag       : constant C_DWord := 16#0200_0000#;
   Invalid_Handle_Value        : constant System.Address :=
     System.Storage_Elements.To_Address (System.Storage_Elements.Integer_Address'Last);

   --  WIN32_FILE_ATTRIBUTE_DATA: FILETIMEs are two DWORDs, low first.
   type Attribute_Data is record
      Attributes                : C_DWord := 0;
      Creation_Low, Creation_High : C_DWord := 0;
      Access_Low, Access_High   : C_DWord := 0;
      Write_Low, Write_High     : C_DWord := 0;
      Size_High, Size_Low       : C_DWord := 0;
   end record with Convention => C;

   --  BY_HANDLE_FILE_INFORMATION.
   type Handle_Information is record
      Attributes                : C_DWord := 0;
      Creation_Low, Creation_High : C_DWord := 0;
      Access_Low, Access_High   : C_DWord := 0;
      Write_Low, Write_High     : C_DWord := 0;
      Volume                    : C_DWord := 0;
      Size_High, Size_Low       : C_DWord := 0;
      Links                     : C_DWord := 0;
      Index_High, Index_Low     : C_DWord := 0;
   end record with Convention => C;

   function Get_File_Attributes_Ex
     (Name  : System.Address;
      Level : Interfaces.C.int;
      Data  : access Attribute_Data)
      return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "GetFileAttributesExW";

   function Open_Entry
     (Name        : System.Address;
      Access_Mode : C_DWord;
      Share       : C_DWord;
      Security    : System.Address;
      Disposition : C_DWord;
      Flags       : C_DWord;
      Template    : System.Address)
      return System.Address
     with Import => True, Convention => Stdcall, External_Name => "CreateFileW";

   function Close_Entry (Handle : System.Address) return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "CloseHandle";

   function Get_Handle_Information
     (Handle : System.Address;
      Info   : access Handle_Information)
      return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "GetFileInformationByHandle";

   function Last_Error return C_DWord
     with Import => True, Convention => Stdcall, External_Name => "GetLastError";

   function Get_File_Type (Handle : System.Address) return C_DWord
     with Import => True, Convention => Stdcall, External_Name => "GetFileType";

   --  A name the Win32 layer may turn into a device: the device namespace
   --  (\\.\NUL, \\.\pipe\...), or a last part DOS reserves -- NUL, CON,
   --  PRN, AUX, COM1 to COM9, LPT1 to LPT9, CONIN$, CONOUT$ -- with or
   --  without an extension, a trailing colon or trailing spaces. Only the
   --  text: whether a device answers is asked of it.
   function May_Name_Device (Path : String) return Boolean is
      Start : Natural := Path'First;
      Stop  : Natural;
   begin
      if Path'Length >= 4 and then Path (Path'First .. Path'First + 3) in "\\.\" | "//./" then
         return True;
      end if;
      for Index in Path'Range loop
         if Path (Index) in '\' | '/' | ':' and then Index < Path'Last then
            Start := Index + 1;
         end if;
      end loop;
      Stop := Start - 1;
      while Stop < Path'Last and then Path (Stop + 1) not in '.' | ':' | ' ' loop
         Stop := Stop + 1;
      end loop;
      declare
         Stem : constant String := Ada.Characters.Handling.To_Upper (Path (Start .. Stop));
      begin
         return Stem in "NUL" | "CON" | "PRN" | "AUX" | "CONIN$" | "CONOUT$"
           or else (Stem'Length = 4
                    and then Stem (Stem'First .. Stem'First + 2) in "COM" | "LPT"
                    and then Stem (Stem'Last) in '1' .. '9');
      end;
   end May_Name_Device;

   --  Opened, asking for no data, and asked its type: FILE_TYPE_CHAR (NUL,
   --  CON, a serial port), FILE_TYPE_PIPE or anything but FILE_TYPE_DISK is
   --  a device. A name that does not open as one is not one: where Windows
   --  no longer reserves a name inside a folder, that is an ordinary file.
   function Is_Device (Path : String) return Boolean is
      File_Type_Disk : constant C_DWord := 1;
      Handle         : System.Address;
      Kind           : C_DWord;
      Ignored        : Interfaces.C.int;
      use type System.Address;
   begin
      if not May_Name_Device (Path) then
         return False;
      end if;
      declare
         Native_Path : aliased constant Wide_String := Wide (Path);
      begin
         Handle := Open_Entry
           (Native_Path'Address, File_Read_Attributes_Access, Share_Everything, System.Null_Address,
            Open_Existing_Only, Backup_Semantics_Flag, System.Null_Address);
      end;
      if Handle = Invalid_Handle_Value then
         return False;
      end if;
      Kind := Get_File_Type (Handle);
      Ignored := Close_Entry (Handle);
      return Kind /= File_Type_Disk;
   exception
      when others =>
         return False;
   end Is_Device;

   function Joined (High : C_DWord; Low : C_DWord) return Interfaces.Unsigned_64 is
     (Interfaces."or" (Interfaces.Shift_Left (Interfaces.Unsigned_64 (High), 32), Interfaces.Unsigned_64 (Low)));

   --  What Size_Of and Modification_Time_Of read of an entry.
   type Entry_Facts is record
      Attributes : C_DWord := 0;
      Written    : Interfaces.Unsigned_64 := 0;
      Size       : Interfaces.Unsigned_64 := 0;
   end record;

   --  A failed ask as the spec's exceptions: a missing file, folder, drive
   --  or share, a name Windows cannot read and a link it cannot resolve are
   --  nothing there (Name_Error); anything else -- access denied, a sharing
   --  violation, a device not ready -- is the host not saying (Use_Error).
   procedure Refuse (Path : String; Error : C_DWord) with No_Return;

   procedure Refuse (Path : String; Error : C_DWord) is
      Error_File_Not_Found     : constant := 2;
      Error_Path_Not_Found     : constant := 3;
      Error_Invalid_Drive      : constant := 15;
      Error_Bad_Netpath        : constant := 53;
      Error_Bad_Net_Name       : constant := 67;
      Error_Invalid_Name       : constant := 123;
      Error_Bad_Pathname       : constant := 161;
      Error_Cant_Resolve_Name  : constant := 1921;
   begin
      if Error in Error_File_Not_Found | Error_Path_Not_Found | Error_Invalid_Drive | Error_Bad_Netpath
        | Error_Bad_Net_Name | Error_Invalid_Name | Error_Bad_Pathname | Error_Cant_Resolve_Name
      then
         raise Ada.Directories.Name_Error with Path & ": Windows error" & C_DWord'Image (Error);
      end if;
      raise Ada.Directories.Use_Error with Path & ": Windows error" & C_DWord'Image (Error);
   end Refuse;

   --  GetFileAttributesExW of the long form, which reads the entry itself;
   --  a symbolic link or junction to be followed is opened as what it points
   --  at (no FILE_FLAG_OPEN_REPARSE_POINT) and asked through the handle.
   --  Other reparse points (cloud placeholders, deduplicated files) are
   --  ordinary entries to the user, as Is_Link says, and read as they are.
   function Facts_Of (Path : String; Follow_Links : Boolean) return Entry_Facts is
      Native_Path : aliased constant Wide_String := Wide (Path);
      Data        : aliased Attribute_Data;
   begin
      if Path = "" or else (for some C of Path => C = ASCII.NUL) then
         raise Ada.Directories.Name_Error with "no entry at """ & Path & """";
      elsif Get_File_Attributes_Ex (Native_Path'Address, 0, Data'Access) = 0 then
         Refuse (Path, Last_Error);
      elsif Follow_Links
        and then (Data.Attributes and File_Attribute_Reparse_Point) /= 0
        and then Is_Link (Path)
      then
         declare
            use type System.Address;
            Handle  : constant System.Address :=
              Open_Entry
                (Native_Path'Address, File_Read_Attributes_Access, Share_Everything, System.Null_Address,
                 Open_Existing_Only, Backup_Semantics_Flag, System.Null_Address);
            Info    : aliased Handle_Information;
            Asked   : Boolean;
            Error   : C_DWord;
            Ignored : Interfaces.C.int;
         begin
            if Handle = Invalid_Handle_Value then
               Refuse (Path, Last_Error);
            end if;
            Asked := Get_Handle_Information (Handle, Info'Access) /= 0;
            Error := Last_Error;
            Ignored := Close_Entry (Handle);
            if not Asked then
               Refuse (Path, Error);
            end if;
            return
              (Attributes => Info.Attributes,
               Written    => Joined (Info.Write_High, Info.Write_Low),
               Size       => Joined (Info.Size_High, Info.Size_Low));
         end;
      end if;
      return
        (Attributes => Data.Attributes,
         Written    => Joined (Data.Write_High, Data.Write_Low),
         Size       => Joined (Data.Size_High, Data.Size_Low));
   end Facts_Of;

   function Size_Of (Path : String; Follow_Links : Boolean := True) return Ada.Directories.File_Size is
      Facts : constant Entry_Facts := Facts_Of (Path, Follow_Links);
   begin
      if (Facts.Attributes and File_Attribute_Directory) /= 0 then
         raise Ada.Directories.Name_Error with Path & ": no ordinary file";
      end if;
      return Ada.Directories.File_Size (Facts.Size);
   end Size_Of;

   function Modification_Time_Of (Path : String; Follow_Links : Boolean := True) return Ada.Calendar.Time is
     (Hostkit.Fs.Instants.From_Filetime (Facts_Of (Path, Follow_Links).Written));

   --  Whether the volume holding Path is a network one, where GNAT does not
   --  read the ACL (__gnat_can_use_acl): this process's token says nothing
   --  about the server's accounts.
   function On_Network_Volume (Path : String) return Boolean is
      use type Interfaces.C.unsigned;
      function Get_Volume_Path_Name
        (Name : System.Address; Root : System.Address; Length : C_DWord) return Interfaces.C.int
        with Import => True, Convention => Stdcall, External_Name => "GetVolumePathNameW";
      function Get_Drive_Type (Root : System.Address) return Interfaces.C.unsigned
        with Import => True, Convention => Stdcall, External_Name => "GetDriveTypeW";
      Drive_Remote : constant Interfaces.C.unsigned := 4;
      Native_Path  : aliased constant Wide_String := Wide (Path);
      Root         : aliased Wide_String (1 .. 32_768) := [others => Wide_Character'Val (0)];
   begin
      return Get_Volume_Path_Name (Native_Path'Address, Root'Address, Root'Length) /= 0
        and then Get_Drive_Type (Root'Address) = Drive_Remote;
   end On_Network_Volume;

   --  GNAT's __gnat_check_OWNER_ACL: the entry's owner, group and DACL
   --  checked against this process's own token for Wanted. GNAT reads the
   --  descriptor with GetFileSecurity, which has its path limit; here it is
   --  read through a handle opened on the long form, a link followed as
   --  GetFileSecurity follows one. An impersonation copy of the process
   --  token, as AccessCheck needs one, made with DuplicateToken rather than
   --  GNAT's ImpersonateSelf, which changes the calling thread meanwhile.
   function Token_Granted (Path : String; Wanted : C_DWord) return Boolean is
      use type System.Address;

      --  GENERIC_MAPPING, filled with the file object's own mapping.
      type Generic_Mapping is record
         Read, Write, Execute, All_Access : C_DWord;
      end record with Convention => C;
      File_Mapping : aliased constant Generic_Mapping :=
        (Read => 16#0012_0089#, Write => 16#0012_0116#, Execute => 16#0012_00A0#, All_Access => 16#001F_01FF#);

      --  PRIVILEGE_SET with room for more than the one entry its C type
      --  declares, so a check that used privileges is not refused for want
      --  of room.
      type Privilege_Buffer is array (1 .. 64) of Interfaces.Unsigned_32 with Convention => C;

      function Get_Security_Info
        (Handle      : System.Address;
         Object_Type : Interfaces.C.int;
         Wanted_Info : C_DWord;
         Owner       : System.Address;
         Group       : System.Address;
         Dacl        : System.Address;
         Sacl        : System.Address;
         Descriptor  : access System.Address)
         return C_DWord
        with Import => True, Convention => Stdcall, External_Name => "GetSecurityInfo";
      function Get_Current_Process return System.Address
        with Import => True, Convention => Stdcall, External_Name => "GetCurrentProcess";
      function Open_Process_Token
        (Process : System.Address; Desired : C_DWord; Token : access System.Address) return Interfaces.C.int
        with Import => True, Convention => Stdcall, External_Name => "OpenProcessToken";
      function Duplicate_Token
        (Existing : System.Address; Level : Interfaces.C.int; Duplicate : access System.Address)
         return Interfaces.C.int
        with Import => True, Convention => Stdcall, External_Name => "DuplicateToken";
      function Access_Check
        (Descriptor        : System.Address;
         Token             : System.Address;
         Desired           : C_DWord;
         Mapping           : access constant Generic_Mapping;
         Privileges        : System.Address;
         Privileges_Length : access C_DWord;
         Granted           : access C_DWord;
         Status            : access Interfaces.C.int)
         return Interfaces.C.int
        with Import => True, Convention => Stdcall, External_Name => "AccessCheck";
      function Local_Free (Item : System.Address) return System.Address
        with Import => True, Convention => Stdcall, External_Name => "LocalFree";

      Se_File_Object         : constant Interfaces.C.int := 1;
      Owner_Group_Dacl       : constant C_DWord := 16#1# + 16#2# + 16#4#;
      Token_Duplicate        : constant C_DWord := 16#2#;
      Token_Query            : constant C_DWord := 16#8#;
      Security_Impersonation : constant Interfaces.C.int := 2;

      Native_Path   : aliased constant Wide_String := Wide (Path);
      Descriptor    : aliased System.Address := System.Null_Address;
      Process_Token : aliased System.Address := System.Null_Address;
      Token         : aliased System.Address := System.Null_Address;
      Privileges    : aliased Privilege_Buffer := [others => 0];
      Length        : aliased C_DWord := Privilege_Buffer'Size / 8;
      Granted       : aliased C_DWord := 0;
      Status        : aliased Interfaces.C.int := 0;
      Answer        : Boolean := False;

      procedure Let_Go is
         Ignored_Close : Interfaces.C.int;
         Ignored_Free  : System.Address;
      begin
         if Token /= System.Null_Address then
            Ignored_Close := Close_Entry (Token);
         end if;
         if Process_Token /= System.Null_Address then
            Ignored_Close := Close_Entry (Process_Token);
         end if;
         if Descriptor /= System.Null_Address then
            Ignored_Free := Local_Free (Descriptor);
         end if;
      end Let_Go;
   begin
      declare
         Handle  : constant System.Address :=
           Open_Entry
             (Native_Path'Address, Read_Control_Access, Share_Everything, System.Null_Address,
              Open_Existing_Only, Backup_Semantics_Flag, System.Null_Address);
         Read    : C_DWord;
         Ignored : Interfaces.C.int;
      begin
         if Handle = Invalid_Handle_Value then
            return False;
         end if;
         Read := Get_Security_Info
           (Handle, Se_File_Object, Owner_Group_Dacl, System.Null_Address, System.Null_Address,
            System.Null_Address, System.Null_Address, Descriptor'Access);
         Ignored := Close_Entry (Handle);
         if Read /= 0 then
            Descriptor := System.Null_Address;
            return False;
         end if;
      end;
      if Open_Process_Token (Get_Current_Process, Token_Duplicate + Token_Query, Process_Token'Access) /= 0
        and then Duplicate_Token (Process_Token, Security_Impersonation, Token'Access) /= 0
        and then Access_Check
          (Descriptor, Token, Wanted, File_Mapping'Access, Privileges'Address, Length'Access, Granted'Access,
           Status'Access) /= 0
      then
         Answer := Status /= 0;
      end if;
      Let_Go;
      return Answer;
   exception
      when others =>
         Let_Go;
         return False;
   end Token_Granted;

   function Is_Owner_Readable (Path : String) return Boolean is
      File_Read_Data : constant C_DWord := 16#1#;
   begin
      if Path = "" then
         return False;
      elsif On_Network_Volume (Path) then
         declare
            Native_Path : aliased constant Wide_String := Wide (Path);
         begin
            return Get_File_Attributes (Native_Path'Address) /= Invalid_File_Attributes;
         end;
      end if;
      return Token_Granted (Path, File_Read_Data);
   exception
      when others =>
         return False;
   end Is_Owner_Readable;

   function Is_Owner_Writable (Path : String) return Boolean is
      File_Attribute_Readonly : constant C_DWord := 16#1#;
      File_Write_Data         : constant C_DWord := 16#2#;
      File_Append_Data        : constant C_DWord := 16#4#;
      Native_Path             : aliased constant Wide_String := Wide (Path);
      Attributes              : C_DWord;
   begin
      if Path = "" then
         return False;
      end if;
      Attributes := Get_File_Attributes (Native_Path'Address);
      if Attributes = Invalid_File_Attributes or else (Attributes and File_Attribute_Readonly) /= 0 then
         return False;
      end if;
      return On_Network_Volume (Path) or else Token_Granted (Path, File_Write_Data + File_Append_Data);
   exception
      when others =>
         return False;
   end Is_Owner_Writable;

   function Create_Link
     (Target    : String;
      Link_Path : String)
      return Boolean
   is
      function Native (Path : String) return String;
      function Seen_From_Link return String;

      --  Windows resolves a link's target only with its own separators.
      function Native (Path : String) return String is
         Result : String := Path;
      begin
         for Item of Result loop
            if Item = '/' then
               Item := '\';
            end if;
         end loop;

         return Result;
      end Native;

      --  A relative target is read from the link's folder, as following the
      --  link reads it, not from the current one.
      function Seen_From_Link return String is
      begin
         if Target'Length > 0
           and then (Target (Target'First) in '/' | '\'
                     or else (Target'Length > 1 and then Target (Target'First + 1) = ':'))
         then
            return Target;
         end if;

         for Index in reverse Link_Path'Range loop
            if Link_Path (Index) in '/' | '\' then
               return Link_Path (Link_Path'First .. Index) & Target;
            end if;
         end loop;

         return Target;
      end Seen_From_Link;

      Wide_Target : aliased Wide_String := Wide_Text (Native (Target));
      Wide_Link   : aliased Wide_String := Wide (Link_Path);

      --  Asked through the long form: GNAT's Kind refuses a target past
      --  260 characters, and the link was then made as a file link.
      Is_Directory : constant Boolean := Kind_Of (Seen_From_Link) = Directory_Entry;

      --  Windows will not make a link without either Developer Mode or the privilege,
      --  and refusing is a normal answer here rather than a fault.
      Flags : constant C_DWord :=
        Symbolic_Link_Allow_Unprivileged
        + (if Is_Directory then Symbolic_Link_Directory else 0);

      Created : constant Interfaces.C.char :=
        Create_Symbolic_Link (Wide_Link'Address, Wide_Target'Address, Flags);
   begin
      if Interfaces.C.char'Pos (Created) = 0 then
         Hostkit.Errors.Set_Errno_From_Last_Error;
         return False;
      end if;
      return True;
   exception
      when others =>
         return False;
   end Create_Link;

   --  Windows does not decide what runs from a mode bit. Every ordinary file is granted
   --  FILE_EXECUTE in its DACL, so folding that in said everything was executable -- and
   --  a file manager duly classified a .tar.gz as a program. What runs here is decided
   --  by the extension.
   function Is_Executable (Path : String) return Boolean is
      --  The extensions Windows runs, tested without allocating one.
      --
      --  This was an array of `access constant String` filled with `new
      --  String'(".exe")` and the rest: six allocations that nothing ever
      --  frees, made afresh on every call, to hold six literals known at
      --  compile time. GNAT warns about the anonymous access allocator, and it
      --  is right to.
      Dot : constant Natural :=
        Ada.Strings.Fixed.Index (Path, ".", Ada.Strings.Backward);

      Suffix : constant String :=
        (if Dot = 0 then ""
         else Ada.Characters.Handling.To_Lower (Path (Dot .. Path'Last)));

      Wide_Path  : aliased Wide_String := Wide (Path);
      Attributes : constant C_DWord := Get_File_Attributes (Wide_Path'Address);
   begin
      if Attributes = Invalid_File_Attributes
        or else (Attributes and File_Attribute_Directory) /= 0
      then
         return False;
      end if;

      return Suffix = ".exe" or else Suffix = ".com" or else Suffix = ".bat"
        or else Suffix = ".cmd" or else Suffix = ".ps1"
        or else Suffix = ".msi";
   exception
      when others =>
         return False;
   end Is_Executable;

   --  No mode bits on Windows; access is by ACL, and reading it is not done here. Answer
   --  False -- decline to guess rather than reject a key the profile ACL already protects.
   function Accessible_By_Others (Path : String) return Boolean is
      pragma Unreferenced (Path);
   begin
      return False;
   end Accessible_By_Others;

   --  No mode bits here; see the comment on the file-level answer.
   function Directory_Accessible_By_Others (Path : String) return Boolean is
      pragma Unreferenced (Path);
   begin
      return False;
   end Directory_Accessible_By_Others;

   --  No mode bits to set, and this does not write an ACL; see the spec.

   --  None of these exist on this host; see the spec for what each would mean.
   function Set_Owner (Path : String; User : Integer; Group : Integer) return Boolean is
      pragma Unreferenced (Path, User, Group);
   begin
      return False;
   end Set_Owner;

   function Set_Extended_Attribute
     (Path  : String;
      Name  : String;
      Value : Ada.Streams.Stream_Element_Array) return Boolean
   is
      pragma Unreferenced (Path, Name, Value);
   begin
      return False;
   end Set_Extended_Attribute;

   function Create_FIFO (Path : String; Mode : Natural) return Boolean is
      pragma Unreferenced (Path, Mode);
   begin
      return False;
   end Create_FIFO;

   function Create_Socket (Path : String; Mode : Natural) return Boolean is
      pragma Unreferenced (Path, Mode);
   begin
      return False;
   end Create_Socket;

   function Special_File_Info_Of (Path : String) return Special_File_Info is
      pragma Unreferenced (Path);
   begin
      return (Available => False, Kind => Not_Special, Device => 0, Mode => 0);
   end Special_File_Info_Of;

   function Create_Device
     (Path   : String;
      Kind   : Device_Kind;
      Device : Interfaces.Unsigned_64;
      Mode   : Natural) return Boolean
   is
      pragma Unreferenced (Path, Kind, Device, Mode);
   begin
      return False;
   end Create_Device;

   --  The one of these Windows does have. NTFS keeps a hard link; FAT does not,
   --  and the call fails there rather than pretending.
   function Create_Hard_Link (Target : String; Link_Path : String) return Boolean is
      function Create_Hard_Link_W
        (Link_Name     : System.Address;
         Existing_File : System.Address;
         Attributes    : System.Address) return Interfaces.C.int
        with Import => True, Convention => Stdcall,
             External_Name => "CreateHardLinkW";

      --  Both paths in long form: a hard link whose source lies past 260
      --  characters failed and failed the whole copy.
      Wide_Target : aliased Wide_String := Wide (Target);
      Wide_Link   : aliased Wide_String := Wide (Link_Path);
      Created     : constant Interfaces.C.int :=
        Create_Hard_Link_W
          (Wide_Link'Address, Wide_Target'Address, System.Null_Address);
   begin
      if Created = 0 then
         Hostkit.Errors.Set_Errno_From_Last_Error;
         return False;
      end if;
      return True;
   exception
      when others =>
         return False;
   end Create_Hard_Link;

   function Make_Private (Path : String) return Boolean is
      pragma Unreferenced (Path);
   begin
      return False;
   end Make_Private;

   --  MoveFileEx with MOVEFILE_REPLACE_EXISTING is the atomic replacing rename Windows
   --  offers; plain rename (and GNAT.OS_Lib.Rename_File) fails when the target exists.
   function Replace_File
     (Source : String;
      Target : String)
      return Boolean
   is
      Move_File_Replace_Existing : constant C_DWord := 16#0000_0001#;

      function Move_File_Ex
        (Existing : System.Address;
         New_Name : System.Address;
         Flags    : C_DWord)
         return Interfaces.C.int
        with Import => True, Convention => Stdcall, External_Name => "MoveFileExW";

      function Get_Last_Error return C_DWord
        with Import, Convention => Stdcall, External_Name => "GetLastError";

      Error_Access_Denied     : constant C_DWord := 5;
      Error_Sharing_Violation : constant C_DWord := 32;
      Error_Lock_Violation    : constant C_DWord := 33;

      Wide_Source : aliased Wide_String := Wide (Source);
      Wide_Target : aliased Wide_String := Wide (Target);
      Error       : C_DWord;
   begin
      --  A file just written is often held a moment by someone else (a
      --  virus scanner, the indexer) that did not share deletion; the move
      --  is refused until they let go. Try again, briefly, for that only.
      for Attempt in 1 .. 10 loop
         if Move_File_Ex (Wide_Source'Address, Wide_Target'Address, Move_File_Replace_Existing) /= 0 then
            return True;
         end if;
         Error := Get_Last_Error;
         Hostkit.Errors.Set_Errno_From_Last_Error;
         exit when Error not in Error_Access_Denied | Error_Sharing_Violation | Error_Lock_Violation;
         delay Duration (Attempt) * 0.02;
      end loop;
      return False;
   exception
      when others =>
         return False;
   end Replace_File;

   --  The host refuses an existing target in the same atomic move.
   function Move_No_Replace
     (Source : String;
      Target : String)
      return Boolean
   is (Move_No_Replace_Outcome (Source, Target) = Moved);

   function Move_Without_Native_No_Replace (Source : String; Target : String) return Move_Outcome is
      pragma Unreferenced (Source, Target);
   begin
      return Move_Unsupported;
   end Move_Without_Native_No_Replace;

   function Move_No_Replace_Outcome
     (Source : String;
      Target : String)
      return Move_Outcome
   is
      function Move_File_Ex
        (Existing : System.Address;
         New_Name : System.Address;
         Flags    : C_DWord)
         return Interfaces.C.int
        with Import => True, Convention => Stdcall, External_Name => "MoveFileExW";

      function Get_Last_Error return C_DWord
        with Import, Convention => Stdcall, External_Name => "GetLastError";

      Error_Not_Same_Device  : constant C_DWord := 17;
      Error_Invalid_Function  : constant C_DWord := 1;
      Error_Not_Supported    : constant C_DWord := 50;
      Error_Access_Denied     : constant C_DWord := 5;
      Error_Sharing_Violation : constant C_DWord := 32;
      Error_Lock_Violation    : constant C_DWord := 33;

      Wide_Source : aliased Wide_String := Wide (Source);
      Wide_Target : aliased Wide_String := Wide (Target);
      Error       : C_DWord;
   begin
      --  As Replace_File: someone holding the file a moment refuses the
      --  move; try again, briefly, for that only.
      for Attempt in 1 .. 10 loop
         if Move_File_Ex (Wide_Source'Address, Wide_Target'Address, 0) /= 0 then
            return Moved;
         end if;
         Error := Get_Last_Error;
         Hostkit.Errors.Set_Errno_From_Last_Error;
         exit when Error not in Error_Access_Denied | Error_Sharing_Violation | Error_Lock_Violation;
         delay Duration (Attempt) * 0.02;
      end loop;
      if Error = Error_Not_Same_Device then
         return Move_Cross_Device;
      elsif Error = Error_Invalid_Function or else Error = Error_Not_Supported then
         return Move_Unsupported;
      end if;
      return Move_Refused;
   exception
      when others =>
         return Move_Refused;
   end Move_No_Replace_Outcome;

   --  Windows has no readlink: a link is a reparse point. Open it without following it
   --  (FILE_FLAG_OPEN_REPARSE_POINT) and pull the target out of the reparse data. The
   --  print name is the human target ("real.txt"); the substitute name is a fallback.
   function Read_Link_Target
     (Path   : String;
      Target : out Ada.Strings.Unbounded.Unbounded_String)
      return Boolean
   is
      use type System.Address;

      Fsctl_Get_Reparse_Point : constant C_DWord := 16#0009_00A8#;
      Open_Existing           : constant C_DWord := 3;
      Flag_Backup_Semantics   : constant C_DWord := 16#0200_0000#;
      Flag_Open_Reparse_Point : constant C_DWord := 16#0020_0000#;
      Share_All               : constant C_DWord := 7;
      Tag_Symlink             : constant C_DWord := 16#A000_000C#;
      Tag_Mount_Point         : constant C_DWord := 16#A000_0003#;
      Invalid_Handle          : constant System.Address :=
        System.Storage_Elements.To_Address
          (System.Storage_Elements.Integer_Address'Last);

      function Create_File
        (Name       : System.Address;
         Access_Way : C_DWord;
         Share      : C_DWord;
         Security   : System.Address;
         Creation   : C_DWord;
         Flags      : C_DWord;
         Template   : System.Address)
         return System.Address
        with Import => True, Convention => Stdcall, External_Name => "CreateFileW";

      function Device_Io_Control
        (Handle     : System.Address;
         Code       : C_DWord;
         In_Buffer  : System.Address;
         In_Size    : C_DWord;
         Out_Buffer : System.Address;
         Out_Size   : C_DWord;
         Returned   : access C_DWord;
         Overlapped : System.Address)
         return Interfaces.C.int
        with Import => True, Convention => Stdcall,
             External_Name => "DeviceIoControl";

      function Close_Handle (Handle : System.Address) return Interfaces.C.int
        with Import => True, Convention => Stdcall, External_Name => "CloseHandle";

      Wide_Path : aliased Wide_String := Wide (Path);
      Buffer    : array (0 .. 16 * 1024 - 1) of aliased Interfaces.Unsigned_8 :=
        [others => 0];
      Handle    : System.Address;
      Returned  : aliased C_DWord := 0;
      Outcome   : Interfaces.C.int;
      Ignored   : Interfaces.C.int;

      function U16 (At_Index : Natural) return Natural is
        (Natural (Buffer (At_Index)) + Natural (Buffer (At_Index + 1)) * 256);

      function U32 (At_Index : Natural) return C_DWord is
        (C_DWord (Buffer (At_Index))
         + C_DWord (Buffer (At_Index + 1)) * 256
         + C_DWord (Buffer (At_Index + 2)) * 65_536
         + C_DWord (Buffer (At_Index + 3)) * 16_777_216);
   begin
      Target := Ada.Strings.Unbounded.Null_Unbounded_String;

      Handle := Create_File
        (Name       => Wide_Path'Address,
         Access_Way => 0,
         Share      => Share_All,
         Security   => System.Null_Address,
         Creation   => Open_Existing,
         Flags      => Flag_Backup_Semantics + Flag_Open_Reparse_Point,
         Template   => System.Null_Address);
      if Handle = Invalid_Handle then
         return False;
      end if;

      Outcome := Device_Io_Control
        (Handle     => Handle,
         Code       => Fsctl_Get_Reparse_Point,
         In_Buffer  => System.Null_Address,
         In_Size    => 0,
         Out_Buffer => Buffer'Address,
         Out_Size   => Buffer'Length,
         Returned   => Returned'Access,
         Overlapped => System.Null_Address);
      Ignored := Close_Handle (Handle);
      if Outcome = 0 then
         return False;
      end if;

      declare
         Tag           : constant C_DWord := U32 (0);
         Path_Buf_Base : Natural;
         Name_Off      : Natural;
         Name_Len      : Natural;   --  in bytes
      begin
         if Tag = Tag_Symlink then
            Path_Buf_Base := 20;
         elsif Tag = Tag_Mount_Point then
            Path_Buf_Base := 16;
         else
            return False;
         end if;

         Name_Off := U16 (12);   --  PrintNameOffset
         Name_Len := U16 (14);   --  PrintNameLength
         if Name_Len = 0 then
            Name_Off := U16 (8);    --  SubstituteNameOffset
            Name_Len := U16 (10);   --  SubstituteNameLength
         end if;
         if Name_Len = 0 then
            return False;
         end if;

         declare
            Start  : constant Natural := Path_Buf_Base + Name_Off;
            Chars  : constant Natural := Name_Len / 2;
            Wide_T : Wide_String (1 .. Chars);
         begin
            for Index in 0 .. Chars - 1 loop
               Wide_T (Index + 1) :=
                 Wide_Character'Val (U16 (Start + Index * 2));
            end loop;
            Target := Ada.Strings.Unbounded.To_Unbounded_String
              (Hostkit.Windows_Paths.To_UTF_8 (Wide_T));
         end;
      end;
      return True;
   exception
      when others =>
         return False;
   end Read_Link_Target;

   --  Which call removes a link here depends on what the link points at: a link to a
   --  directory carries FILE_ATTRIBUTE_DIRECTORY and only RemoveDirectoryW will take it,
   --  while DeleteFileW takes every other reparse point. Ada.Directories.Delete_File is
   --  DeleteFileW on both platforms, so a directory symlink refused it and came back as
   --  NAME_ERROR "does not exist".
   --
   --  GetFileAttributesW reports the link's own attributes rather than the target's, so
   --  neither the test nor the removal follows the link -- the target is left alone.
   function Delete_Link (Path : String) return Boolean is
      function Remove_Directory (Name : System.Address) return Interfaces.C.int
        with Import => True, Convention => Stdcall, External_Name => "RemoveDirectoryW";

      function Delete_File (Name : System.Address) return Interfaces.C.int
        with Import => True, Convention => Stdcall, External_Name => "DeleteFileW";

      Wide_Path  : aliased Wide_String := Wide (Path);
      Attributes : constant C_DWord := Get_File_Attributes (Wide_Path'Address);
   begin
      if Attributes = Invalid_File_Attributes
        or else (Attributes and File_Attribute_Reparse_Point) = 0
      then
         return False;
      end if;

      if (if (Attributes and File_Attribute_Directory) /= 0
          then Remove_Directory (Wide_Path'Address) /= 0
          else Delete_File (Wide_Path'Address) /= 0)
      then
         return True;
      end if;
      Hostkit.Errors.Set_Errno_From_Last_Error;
      return False;
   exception
      when others =>
         return False;
   end Delete_Link;

   function Delete_Tree_No_Follow (Path : String) return Delete_Tree_Outcome is
      use type Interfaces.Unsigned_64;
      use type Interfaces.Unsigned_32;
      use type Interfaces.C.unsigned_short;
      use type System.Address;
      use type System.Storage_Elements.Integer_Address;

      subtype C_U16 is Interfaces.C.unsigned_short;
      type U16_Array is array (Natural range <>) of aliased C_U16
        with Convention => C;
      type Byte_Array is array (Natural range <>) of aliased Interfaces.Unsigned_8
        with Convention => C;
      type Directory_Header is record
         Next_Offset : Interfaces.Unsigned_32;
         Name_Length : Interfaces.Unsigned_32;
         File_Id     : Interfaces.Unsigned_64;
      end record;
      for Directory_Header use record
         Next_Offset at 0 range 0 .. 31;
         Name_Length at 60 range 0 .. 31;
         File_Id     at 96 range 0 .. 63;
      end record;
      for Directory_Header'Size use 104 * 8;
      type Handle_Info is record
         Attributes : C_DWord;
         Creation_Low, Creation_High, Access_Low, Access_High : C_DWord;
         Write_Low, Write_High, Volume : C_DWord;
         Size_High, Size_Low, Links, Index_High, Index_Low : C_DWord;
      end record with Convention => C;
      type Disposition_Info is record
         Delete_File : Interfaces.C.int;
      end record with Convention => C;
      type Disposition_Info_Ex is record
         Flags : C_DWord;
      end record with Convention => C;
      type Attribute_Tag_Info is record
         Attributes : C_DWord;
         Reparse_Tag : Interfaces.Unsigned_32;
      end record with Convention => C;
      type Child (Length : Natural) is record
         Name : U16_Array (1 .. Length);
         Id   : Interfaces.Unsigned_64;
      end record;
      package Child_Vectors is new Ada.Containers.Indefinite_Vectors
        (Index_Type => Positive, Element_Type => Child);

      Max_Depth : constant := 2_048;
      Max_Entries : constant := 100_000;
      Max_Name_Bytes : constant := 64 * 1_024 * 1_024;
      Invalid_Handle : constant System.Address :=
        System.Storage_Elements.To_Address (-1);
      Delete_Access : constant C_DWord := 16#0001_0000#;
      File_List_Directory : constant C_DWord := 1;
      File_Read_Attributes : constant C_DWord := 16#80#;
      Share_All : constant C_DWord := 7;
      Open_Existing : constant C_DWord := 3;
      Backup_Semantics : constant C_DWord := 16#0200_0000#;
      Open_Reparse_Point : constant C_DWord := 16#0020_0000#;
      Id_Both_Directory_Info : constant Interfaces.C.int := 10;
      Id_Both_Directory_Restart_Info : constant Interfaces.C.int := 11;
      File_Disposition_Info : constant Interfaces.C.int := 4;
      File_Attribute_Tag_Info : constant Interfaces.C.int := 9;
      File_Disposition_Info_Ex : constant Interfaces.C.int := 21;
      --  FILE_DISPOSITION_FLAG_DELETE, _POSIX_SEMANTICS and
      --  _IGNORE_READONLY_ATTRIBUTE: a read-only file (git marks its objects
      --  so) is deleted like any other, as it is on POSIX hosts.
      Disposition_Delete_Flags : constant C_DWord := 16#1# + 16#2# + 16#10#;
      Error_No_More_Files : constant C_DWord := 18;

      function Create_File_W
        (Name : System.Address; Access_Mode, Share : C_DWord;
         Security : System.Address; Disposition, Flags : C_DWord;
         Template : System.Address) return System.Address
        with Import, Convention => Stdcall, External_Name => "CreateFileW";
      function Close_Handle (Handle : System.Address) return Interfaces.C.int
        with Import, Convention => Stdcall, External_Name => "CloseHandle";
      function Get_File_Information
        (Handle : System.Address; Info : access Handle_Info) return Interfaces.C.int
        with Import, Convention => Stdcall,
             External_Name => "GetFileInformationByHandle";
      function Get_File_Information_Ex
        (Handle : System.Address; Kind : Interfaces.C.int;
         Info : System.Address; Size : C_DWord) return Interfaces.C.int
        with Import, Convention => Stdcall,
             External_Name => "GetFileInformationByHandleEx";
      function Set_File_Information
        (Handle : System.Address; Kind : Interfaces.C.int;
         Info : System.Address; Size : C_DWord) return Interfaces.C.int
        with Import, Convention => Stdcall,
             External_Name => "SetFileInformationByHandle";
      function Get_Final_Path
        (Handle : System.Address; Name : System.Address;
         Size, Flags : C_DWord) return C_DWord
        with Import, Convention => Stdcall,
             External_Name => "GetFinalPathNameByHandleW";
      function Get_Last_Error return C_DWord
        with Import, Convention => Stdcall, External_Name => "GetLastError";

      --  Name opened to be deleted, never followed. Listing is asked for as
      --  well, for a folder to be emptied; an entry whose own DACL refuses
      --  reading (a mode-0 file) is opened again without it, since deleting
      --  needs no read: its folder's FILE_DELETE_CHILD grants the DELETE,
      --  as a POSIX folder's write bit lets an unreadable file go.
      function Open_For_Delete (Name : System.Address) return System.Address is
         Error_Access_Denied : constant C_DWord := 5;
         Handle : System.Address := Create_File_W
           (Name, Delete_Access + File_Read_Attributes + File_List_Directory,
            Share_All, System.Null_Address, Open_Existing,
            Backup_Semantics + Open_Reparse_Point, System.Null_Address);
      begin
         if Handle = Invalid_Handle and then Get_Last_Error = Error_Access_Denied then
            Handle := Create_File_W
              (Name, Delete_Access + File_Read_Attributes,
               Share_All, System.Null_Address, Open_Existing,
               Backup_Semantics + Open_Reparse_Point, System.Null_Address);
         end if;
         return Handle;
      end Open_For_Delete;

      function File_Index (Info : Handle_Info) return Interfaces.Unsigned_64 is
        (Interfaces.Unsigned_64 (Info.Index_High) * 2 ** 32
         + Interfaces.Unsigned_64 (Info.Index_Low));

      --  Read Directory's children from its start. Full is True when
      --  Max_Entries were read and more may follow: the caller deletes those,
      --  then reads again, so a folder of any size is deleted in batches.
      function Read_Children
        (Directory : System.Address; Items : in out Child_Vectors.Vector; Full : out Boolean)
         return Boolean
      is
         Buffer : aliased Byte_Array (0 .. 65_535);
         Kind : Interfaces.C.int := Id_Both_Directory_Restart_Info;
         Name_Bytes : Natural := 0;
      begin
         Full := False;
         loop
            if Get_File_Information_Ex
              (Directory, Kind, Buffer'Address, C_DWord (Buffer'Length)) = 0
            then
               return Get_Last_Error = Error_No_More_Files;
            end if;
            Kind := Id_Both_Directory_Info;
            declare
               Offset : Natural := 0;
            begin
               loop
                  declare
                     Header : Directory_Header
                       with Import, Address => Buffer (Offset)'Address;
                     Length : constant Natural := Natural (Header.Name_Length) / 2;
                     Item : Child (Length);
                     Dot : Boolean := False;
                  begin
                     if Offset + 104 + Natural (Header.Name_Length) > Buffer'Length then
                        return False;
                     end if;
                     for Index in 1 .. Length loop
                        declare
                           Unit : C_U16 with Import,
                             Address => Buffer (Offset + 104 + (Index - 1) * 2)'Address;
                        begin
                           Item.Name (Index) := Unit;
                        end;
                     end loop;
                     Dot := (Length = 1 and then Item.Name (1) = Character'Pos ('.'))
                       or else (Length = 2 and then Item.Name (1) = Character'Pos ('.')
                                and then Item.Name (2) = Character'Pos ('.'));
                     if not Dot then
                        if Natural (Items.Length) >= Max_Entries
                          or else Natural (Header.Name_Length) > Max_Name_Bytes - Name_Bytes
                        then
                           Full := True;
                           return True;
                        end if;
                        Item.Id := Header.File_Id;
                        Items.Append (Item);
                        Name_Bytes := Name_Bytes + Natural (Header.Name_Length);
                     end if;
                     exit when Header.Next_Offset = 0;
                     if Natural (Header.Next_Offset) > Buffer'Length - Offset then
                        return False;
                     end if;
                     Offset := Offset + Natural (Header.Next_Offset);
                  end;
               end loop;
            end;
         end loop;
      exception
         when others =>
            return False;
      end Read_Children;

      function Child_Path (Parent : System.Address; Name : U16_Array) return U16_Array is
         Length : constant C_DWord := Get_Final_Path
           (Parent, System.Null_Address, 0, 0);
      begin
         if Length = 0 then
            return [1 .. 0 => 0];
         end if;
         declare
            Result : U16_Array (0 .. Natural (Length) + Name'Length + 1) := [others => 0];
            Written : constant C_DWord := Get_Final_Path
              (Parent, Result'Address, Length + 1, 0);
            Next : Natural := Natural (Written);
         begin
            if Written = 0 or else Written > Length then
               return [1 .. 0 => 0];
            end if;
            if Next > 0 and then Result (Next - 1) /= Character'Pos ('\') then
               Result (Next) := Character'Pos ('\');
               Next := Next + 1;
            end if;
            for Unit of Name loop
               Result (Next) := Unit;
               Next := Next + 1;
            end loop;
            Result (Next) := 0;
            return Result (0 .. Next);
         end;
      end Child_Path;

      --  Whether the held entry is a link to leave alone rather than a
      --  folder to empty: only the symbolic-link and junction tags are, as
      --  in Is_Link. A OneDrive placeholder folder is a reparse point too,
      --  and its contents are the user's. An unreadable tag counts as a link.
      function Is_Held_Link (Held : System.Address; Info : Handle_Info) return Boolean is
         Tag_Info : aliased Attribute_Tag_Info;
      begin
         if (Info.Attributes and File_Attribute_Reparse_Point) = 0 then
            return False;
         end if;
         if Get_File_Information_Ex
           (Held, File_Attribute_Tag_Info, Tag_Info'Address, C_DWord (Attribute_Tag_Info'Size / 8)) = 0
         then
            return True;
         end if;
         return Tag_Info.Reparse_Tag = Io_Reparse_Tag_Symlink
           or else Tag_Info.Reparse_Tag = Io_Reparse_Tag_Mount_Point;
      end Is_Held_Link;

      function Delete_Held (Held : System.Address; Depth : Natural) return Boolean is
         Info : aliased Handle_Info;
         Items : Child_Vectors.Vector;
         Ok : Boolean := Depth <= Max_Depth
           and then Get_File_Information (Held, Info'Access) /= 0;
         Full : Boolean := True;
         Ignored : Interfaces.C.int;
      begin
         if Ok and then (Info.Attributes and File_Attribute_Directory) /= 0
           and then not Is_Held_Link (Held, Info)
         then
            while Ok and then Full loop
               Items.Clear;
               Ok := Read_Children (Held, Items, Full);
               for Item of Items loop
                  exit when not Ok;
                  declare
                     Name : constant U16_Array := Child_Path (Held, Item.Name);
                     Child_Handle : System.Address :=
                       (if Name'Length = 0 then Invalid_Handle else Open_For_Delete (Name'Address));
                     Child_Info : aliased Handle_Info;
                  begin
                     if Child_Handle = Invalid_Handle and then Name'Length /= 0 then
                        Hostkit.Errors.Set_Errno_From_Last_Error;
                     end if;
                     Ok := Child_Handle /= Invalid_Handle
                       and then Get_File_Information (Child_Handle, Child_Info'Access) /= 0
                       and then Child_Info.Volume = Info.Volume
                       and then File_Index (Child_Info) = Item.Id;
                     if Ok then
                        Ok := Delete_Held (Child_Handle, Depth + 1);
                        Child_Handle := Invalid_Handle;
                     elsif Child_Handle /= Invalid_Handle then
                        Ignored := Close_Handle (Child_Handle);
                     end if;
                  end;
               end loop;
            end loop;
         end if;
         if Ok then
            declare
               Disposition_Ex : aliased Disposition_Info_Ex := (Flags => Disposition_Delete_Flags);
               Disposition : aliased Disposition_Info := (Delete_File => 1);
            begin
               --  The extended form needs Windows 10 1809 and NTFS; elsewhere
               --  the plain one still deletes what is not read-only.
               Ok := Set_File_Information
                 (Held, File_Disposition_Info_Ex, Disposition_Ex'Address,
                  C_DWord (Disposition_Info_Ex'Size / 8)) /= 0
                 or else Set_File_Information
                   (Held, File_Disposition_Info, Disposition'Address,
                    C_DWord (Disposition_Info'Size / 8)) /= 0;
               if not Ok then
                  --  Why the plain form refused: a folder not empty, a file
                  --  held open without delete sharing, a refused right.
                  Hostkit.Errors.Set_Errno_From_Last_Error;
               end if;
            end;
         end if;
         Ignored := Close_Handle (Held);
         return Ok;
      exception
         when others =>
            Ignored := Close_Handle (Held);
            return False;
      end Delete_Held;

      Name : aliased Wide_String := Wide (Path);
      Held : System.Address;
   begin
      if Path = "" then
         return Tree_Delete_Failed;
      end if;
      Held := Open_For_Delete (Name'Address);
      if Held = Invalid_Handle then
         Hostkit.Errors.Set_Errno_From_Last_Error;
         return Tree_Delete_Failed;
      end if;
      return (if Delete_Held (Held, 0) then Tree_Deleted else Tree_Delete_Failed);
   exception
      when others =>
         return Tree_Delete_Failed;
   end Delete_Tree_No_Follow;

   --  Windows has no realpath. Open the path -- following links, so no
   --  FILE_FLAG_OPEN_REPARSE_POINT here -- and ask the kernel for the final, canonical
   --  name of what the handle actually refers to. GetFinalPathNameByHandleW returns it in
   --  the \\?\ (or \\?\UNC\) namespace; strip that prefix so callers see an ordinary path.
   --  Ada.Directories.Full_Name is GetFullPathName here: purely lexical, follows nothing.
   function Real_Path (Path : String) return String is
      use type System.Address;

      Open_Existing         : constant C_DWord := 3;
      Flag_Backup_Semantics : constant C_DWord := 16#0200_0000#;
      Share_All             : constant C_DWord := 7;
      Invalid_Handle        : constant System.Address :=
        System.Storage_Elements.To_Address
          (System.Storage_Elements.Integer_Address'Last);

      function Create_File
        (Name       : System.Address;
         Access_Way : C_DWord;
         Share      : C_DWord;
         Security   : System.Address;
         Creation   : C_DWord;
         Flags      : C_DWord;
         Template   : System.Address)
         return System.Address
        with Import => True, Convention => Stdcall, External_Name => "CreateFileW";

      function Get_Final_Path_Name_By_Handle
        (Handle : System.Address;
         Path   : System.Address;
         Count  : C_DWord;
         Flags  : C_DWord)
         return C_DWord
        with Import => True, Convention => Stdcall,
             External_Name => "GetFinalPathNameByHandleW";

      function Close_Handle (Handle : System.Address) return Interfaces.C.int
        with Import => True, Convention => Stdcall, External_Name => "CloseHandle";

      --  Resolve a single path that must exist, to its canonical long-name form (with
      --  the \\?\ / \\?\UNC\ prefix stripped). Returns "" when Target does not exist.
      function Resolve (Target : String) return String is
         Wide_Path : aliased Wide_String := Wide (Target);
         Wide_Buf  : aliased Wide_String (1 .. 32 * 1024) :=
           [others => Wide_Character'Val (0)];
         Handle    : System.Address;
         Length    : C_DWord;
         Ignored   : Interfaces.C.int;
      begin
         Handle := Create_File
           (Name       => Wide_Path'Address,
            Access_Way => 0,
            Share      => Share_All,
            Security   => System.Null_Address,
            Creation   => Open_Existing,
            Flags      => Flag_Backup_Semantics,
            Template   => System.Null_Address);
         if Handle = Invalid_Handle then
            return "";
         end if;

         --  Flags 0 == VOLUME_NAME_DOS or FILE_NAME_NORMALIZED. Length is the count of
         --  WCHARs written (excluding the terminating NUL); 0 on failure, or -- if it
         --  would not fit -- the required size including the NUL, treated as failure.
         Length := Get_Final_Path_Name_By_Handle
           (Handle => Handle,
            Path   => Wide_Buf'Address,
            Count  => Wide_Buf'Length,
            Flags  => 0);
         Ignored := Close_Handle (Handle);

         if Length = 0 or else Length > Wide_Buf'Length then
            return "";
         end if;

         declare
            Resolved : constant String :=
              Hostkit.Windows_Paths.To_UTF_8
                (Wide_Buf (1 .. Natural (Length)));
         begin
            --  \\?\UNC\server\share -> \\server\share ; \\?\C:\dir -> C:\dir.
            if Resolved'Length >= 8
              and then Resolved (Resolved'First .. Resolved'First + 7) = "\\?\UNC\"
            then
               return "\\" & Resolved (Resolved'First + 8 .. Resolved'Last);
            elsif Resolved'Length >= 4
              and then Resolved (Resolved'First .. Resolved'First + 3) = "\\?\"
            then
               return Resolved (Resolved'First + 4 .. Resolved'Last);
            else
               return Resolved;
            end if;
         end;
      end Resolve;

      --  Index of the last path separator in S, or 0 if there is none.
      function Last_Separator (S : String) return Natural is
      begin
         for Index in reverse S'Range loop
            if S (Index) = '\' or else S (Index) = '/' then
               return Index;
            end if;
         end loop;
         return 0;
      end Last_Separator;

      --  Re-attach a nonexistent leaf onto its resolved parent, so a path that does not
      --  exist still lands in the same long-name form as the roots it is compared against.
      function Parent_Compose (P : String) return String is
         Cut : constant Natural := Last_Separator (P);
      begin
         if Cut > P'First then
            declare
               Parent : constant String := Resolve (P (P'First .. Cut - 1));
            begin
               if Parent /= "" then
                  return Parent & "\" & P (Cut + 1 .. P'Last);
               end if;
            end;
         end if;
         return "";
      end Parent_Compose;

      --  Canonicalize P, following symbolic links even when their target does not exist.
      --  GetFinalPathNameByHandleW resolves an existing path directly; when it cannot
      --  (a broken or cyclic link) and P is itself a link, read the link's own target and
      --  resolve THAT -- matching POSIX, where Full_Name resolves a link to its target
      --  path even if the target is missing. Without this a broken-link input root stayed
      --  the link's own path while the followed target became a sibling, so the scanner's
      --  containment check read them as unrelated (SCAN_SYMLINK_TARGET_OUTSIDE_INPUT). A
      --  link cycle collapses to the lexically-smallest path in the chain, so every member
      --  maps to one representative and the scanner detects the revisit as a cycle.
      function Resolve_Chain
        (P : String; Depth : Natural; Min_So_Far : String) return String
      is
         Direct  : constant String := Resolve (P);
         New_Min : constant String :=
           (if Min_So_Far = "" or else P < Min_So_Far then P else Min_So_Far);
      begin
         if Direct /= "" then
            return Direct;
         end if;
         if Is_Link (P) then
            if Depth = 0 then
               return Parent_Compose (New_Min);
            end if;
            declare
               Target : Ada.Strings.Unbounded.Unbounded_String;
            begin
               if Read_Link_Target (P, Target) then
                  declare
                     T   : constant String :=
                       Ada.Strings.Unbounded.To_String (Target);
                     Cut : constant Natural := Last_Separator (P);
                     Abs_Target : constant String :=
                       (if T'Length >= 1
                          and then (T (T'First) = '\' or else T (T'First) = '/')
                        then T
                        elsif T'Length >= 2 and then T (T'First + 1) = ':'
                        then T
                        elsif Cut > P'First
                        then P (P'First .. Cut - 1) & "/" & T
                        else T);
                  begin
                     return Resolve_Chain (Abs_Target, Depth - 1, New_Min);
                  end;
               end if;
            end;
         end if;
         return Parent_Compose (P);
      end Resolve_Chain;
   begin
      return Resolve_Chain (Path, 40, "");
   exception
      when others =>
         return "";
   end Real_Path;

   procedure Read_Beneath
     (Root    : String;
      Path    : String;
      Most    : Natural;
      Text    : out Ada.Strings.Unbounded.Unbounded_String;
      Outcome : out Read_Beneath_Outcome)
   is
      use type System.Address;
      use type System.Storage_Elements.Integer_Address;

      package Part_Vectors is new Ada.Containers.Indefinite_Vectors
        (Index_Type => Positive, Element_Type => String);
      package Handle_Vectors is new Ada.Containers.Indefinite_Vectors
        (Index_Type => Positive, Element_Type => System.Address);

      type Handle_Info is record
         Attributes : C_DWord;
         Creation_Low, Creation_High, Access_Low, Access_High : C_DWord;
         Write_Low, Write_High, Volume : C_DWord;
         Size_High, Size_Low, Links, Index_High, Index_Low : C_DWord;
      end record with Convention => C;

      Invalid_Handle       : constant System.Address := System.Storage_Elements.To_Address (-1);
      Generic_Read         : constant C_DWord := 16#8000_0000#;
      File_Read_Attributes : constant C_DWord := 16#80#;
      --  A data right: a handle holding only attribute rights takes no part
      --  in the sharing check, so the folder it held could still be renamed
      --  away and a link put in its place while the walk went on below it.
      File_List_Directory  : constant C_DWord := 16#01#;
      --  Read and write, never delete: a directory held so cannot be
      --  renamed or replaced while the walk goes on below it.
      Share_No_Delete      : constant C_DWord := 3;
      Open_Existing        : constant C_DWord := 3;
      Backup_Semantics     : constant C_DWord := 16#0200_0000#;
      Open_Reparse_Point   : constant C_DWord := 16#0020_0000#;
      Error_File_Not_Found : constant C_DWord := 2;
      Error_Path_Not_Found : constant C_DWord := 3;
      Chunk                : constant := 65_536;

      function Create_File_W
        (Name : System.Address; Access_Mode, Share : C_DWord;
         Security : System.Address; Disposition, Flags : C_DWord;
         Template : System.Address) return System.Address
        with Import, Convention => Stdcall, External_Name => "CreateFileW";
      function Close_Handle (Handle : System.Address) return Interfaces.C.int
        with Import, Convention => Stdcall, External_Name => "CloseHandle";
      function Get_File_Information
        (Handle : System.Address; Info : access Handle_Info) return Interfaces.C.int
        with Import, Convention => Stdcall, External_Name => "GetFileInformationByHandle";
      function Get_Final_Path
        (Handle : System.Address; Name : System.Address; Size, Flags : C_DWord) return C_DWord
        with Import, Convention => Stdcall, External_Name => "GetFinalPathNameByHandleW";
      function Read_File
        (Handle : System.Address; Buffer : System.Address; Count : C_DWord;
         Got : access C_DWord; Overlapped : System.Address) return Interfaces.C.int
        with Import, Convention => Stdcall, External_Name => "ReadFile";
      function Get_Last_Error return C_DWord
        with Import, Convention => Stdcall, External_Name => "GetLastError";

      Held  : Handle_Vectors.Vector;
      Parts : Part_Vectors.Vector;
      Start : Positive := Path'First;

      procedure Let_Go is
         Ignored : Interfaces.C.int;
      begin
         for Handle of Held loop
            Ignored := Close_Handle (Handle);
         end loop;
         Held.Clear;
      end Let_Go;

      function Open (Name : Wide_String; Access_Mode, Flags : C_DWord) return System.Address is
         Terminated : aliased constant Wide_String := Name & Wide_Character'Val (0);
      begin
         return Create_File_W
           (Terminated'Address, Access_Mode, Share_No_Delete, System.Null_Address, Open_Existing, Flags,
            System.Null_Address);
      end Open;
   begin
      Text := Ada.Strings.Unbounded.Null_Unbounded_String;
      Outcome := Read_Failed;
      if Path'Length = 0 or else Path (Path'First) in '/' | '\' then
         Outcome := Read_Outside;
         return;
      end if;
      for Index in Path'First .. Path'Last + 1 loop
         if Index > Path'Last or else Path (Index) in '/' | '\' then
            declare
               Part : constant String := Path (Start .. Index - 1);
            begin
               if Part = ".." or else (for some C of Part => C in ':' | ASCII.NUL) then
                  Outcome := Read_Outside;
                  return;
               elsif Part /= "" and then Part /= "." then
                  Parts.Append (Part);
               end if;
            end;
            Start := Index + 1;
         end if;
      end loop;
      if Parts.Is_Empty then
         Outcome := Read_Not_File;
         return;
      end if;

      --  Root, links and all, held and named as it resolves: every part
      --  below is named from there. Root in the long form, without the
      --  terminator Open adds itself.
      declare
         Native_Root : constant Wide_String := Wide (if Root = "" then "." else Root);
         Root_Handle : constant System.Address :=
           Open (Native_Root (Native_Root'First .. Native_Root'Last - 1), File_Read_Attributes + File_List_Directory,
                 Backup_Semantics);
      begin
         if Root_Handle = Invalid_Handle then
            Outcome := Read_Missing;
            return;
         end if;
         Held.Append (Root_Handle);
      end;
      declare
         Length : constant C_DWord := Get_Final_Path (Held.First_Element, System.Null_Address, 0, 0);
      begin
         if Length = 0 then
            Let_Go;
            return;
         end if;
         declare
            Buffer  : aliased Wide_String (1 .. Natural (Length) + 1);
            Written : constant C_DWord := Get_Final_Path (Held.First_Element, Buffer'Address, Length + 1, 0);
            Current : Ada.Strings.Wide_Unbounded.Unbounded_Wide_String;
            Handle  : System.Address := Invalid_Handle;
            Info    : aliased Handle_Info;
         begin
            if Written = 0 or else Written > Length then
               Let_Go;
               return;
            end if;
            Current := Ada.Strings.Wide_Unbounded.To_Unbounded_Wide_String (Buffer (1 .. Natural (Written)));
            for Index in Parts.First_Index .. Parts.Last_Index loop
               declare
                  Last : constant Boolean := Index = Parts.Last_Index;
               begin
                  Ada.Strings.Wide_Unbounded.Append
                    (Current, "\" & Hostkit.Windows_Paths.From_UTF_8 (Parts (Index)));
                  --  The part as itself: a link or junction is opened, not
                  --  what it points at, and refused below.
                  Handle := Open
                    (Ada.Strings.Wide_Unbounded.To_Wide_String (Current),
                     File_Read_Attributes + (if Last then Generic_Read else File_List_Directory),
                     Backup_Semantics + Open_Reparse_Point);
                  if Handle = Invalid_Handle then
                     Outcome :=
                       (if Get_Last_Error in Error_File_Not_Found | Error_Path_Not_Found then Read_Missing
                        else Read_Failed);
                     Let_Go;
                     return;
                  end if;
                  Held.Append (Handle);
                  if Get_File_Information (Handle, Info'Access) = 0 then
                     Let_Go;
                     return;
                  elsif (Info.Attributes and File_Attribute_Reparse_Point) /= 0 then
                     Outcome := Read_Outside;
                     Let_Go;
                     return;
                  elsif Last = ((Info.Attributes and File_Attribute_Directory) /= 0) then
                     Outcome := (if Last then Read_Not_File else Read_Missing);
                     Let_Go;
                     return;
                  end if;
               end;
            end loop;
            if Info.Size_High /= 0 or else Long_Long_Integer (Info.Size_Low) > Long_Long_Integer (Most) then
               Outcome := Read_Too_Large;
               Let_Go;
               return;
            end if;
            declare
               Chunk_Of : aliased String (1 .. Chunk);
               Got      : aliased C_DWord;
               Total    : Natural := 0;
            begin
               loop
                  if Read_File (Handle, Chunk_Of'Address, Chunk, Got'Access, System.Null_Address) = 0 then
                     exit;
                  elsif Got = 0 then
                     Outcome := Read_Done;
                     exit;
                  elsif Natural (Got) > Most - Total then
                     Outcome := Read_Too_Large;
                     exit;
                  end if;
                  Total := Total + Natural (Got);
                  Ada.Strings.Unbounded.Append (Text, Chunk_Of (1 .. Natural (Got)));
               end loop;
            end;
         end;
      end;
      Let_Go;
      if Outcome /= Read_Done then
         Text := Ada.Strings.Unbounded.Null_Unbounded_String;
      end if;
   exception
      when others =>
         Let_Go;
         Text := Ada.Strings.Unbounded.Null_Unbounded_String;
         Outcome := Read_Failed;
   end Read_Beneath;

   --  The directory part of a Windows path, either separator.
   function Directory_Part (Path : String) return String is
   begin
      for Index in reverse Path'Range loop
         if Path (Index) = '\' or else Path (Index) = '/' then
            return Path (Path'First .. Index - 1);
         end if;
      end loop;
      return "";
   end Directory_Part;

   --  GetModuleFileNameW with a null module is this program's own image path.
   --  Wide, because a user profile with a non-Latin-1 name is ordinary here and
   --  the ANSI call would mangle it.
   function Own_Executable return String is
      function Get_Module_File_Name
        (Module : System.Address;
         Buffer : System.Address;
         Size   : C_DWord)
         return C_DWord
        with Import => True, Convention => Stdcall,
             External_Name => "GetModuleFileNameW";

      Buffer : aliased Wide_String (1 .. 32768) := [others => Wide_Character'Val (0)];
      Length : constant C_DWord :=
        Get_Module_File_Name
          (System.Null_Address, Buffer'Address, C_DWord (Buffer'Length));
   begin
      if Length = 0 or else Length >= C_DWord (Buffer'Length) then
         return "";
      end if;

      --  UTF-8, as every path here is: the name was cut to Latin-1 before,
      --  dropping any other character and leaving the rest unencoded.
      return Hostkit.Windows_Paths.To_UTF_8 (Buffer (1 .. Natural (Length)));
   exception
      when others =>
         return "";
   end Own_Executable;

   function Own_Executable_Directory return String is
      Own : constant String := Own_Executable;
   begin
      return (if Own = "" then "" else Directory_Part (Own));
   end Own_Executable_Directory;

   --  USERPROFILE is the profile folder, and HOMEDRIVE+HOMEPATH is what a
   --  domain login sets instead. HOME exists only where something POSIX-shaped
   --  put it there, which is why it is last rather than first.
   function Home_Directory return String is
      function Env (Name : String) return String is (Hostkit.Environment.Value (Name, ""));
   begin
      if Env ("USERPROFILE") /= "" then
         return Env ("USERPROFILE");
      elsif Env ("HOMEDRIVE") /= "" and then Env ("HOMEPATH") /= "" then
         return Env ("HOMEDRIVE") & Env ("HOMEPATH");
      else
         return Env ("HOME");
      end if;
   end Home_Directory;

   --  No answer here. A Windows profile folder belongs to whoever is logged
   --  in, and there is no supported way to ask where another account's lives
   --  without that account's credentials -- so this refuses rather than
   --  guessing at C:\\Users\\<name>, which is a convention rather than a rule
   --  and is wrong on a domain-joined machine.
   function Home_Directory_Of (User : String) return String is
      pragma Unreferenced (User);
   begin
      return "";
   end Home_Directory_Of;

   function User_Places return User_Place_List is
      use Ada.Strings.Unbounded;
      function Value (Name : String) return String is (Hostkit.Environment.Value (Name, ""));
      Drive  : constant String := Value ("HOMEDRIVE");
      Path   : constant String := Value ("HOMEPATH");
      System_Drive : constant String := Value ("SystemDrive");
      function Place (Folder : String; Kind : User_Place_Kind) return User_Place_List is
        (if Folder = "" then [] else [1 => (Path => To_Unbounded_String (Folder), Kind => Kind)]);
   begin
      return Place (Home_Directory, Home_Place)
        & Place ((if Drive = "" then "" else Drive & "\"), Drive_Place)
        & Place ((if Drive = "" or else Path = "" then "" else Drive & Path), Profile_Place)
        & Place ((if System_Drive = "" then "" else System_Drive & "\"), Drive_Place)
        & Place (Value ("HOMESHARE"), Network_Place)
        & Place (Value ("OneDrive"), Cloud_Place)
        & Place (Value ("OneDriveCommercial"), Cloud_Place)
        & Place (Value ("OneDriveConsumer"), Cloud_Place);
   end User_Places;

   --  Windows keeps no freedesktop application entries.
   function Application_Data_Directories return Path_List is ([]);

   --  The Fonts known folder, as the shell names it -- an administrator can
   --  move Windows elsewhere than C:\Windows -- else %WINDIR%\Fonts; then the
   --  folder a font installed for this user alone goes to (Windows 10 1809
   --  and later), under the non-roaming profile.
   function Font_Directories return Path_List is
      use Ada.Strings.Unbounded;

      type Guid is record
         Data_1 : Interfaces.C.unsigned_long;
         Data_2 : Interfaces.C.unsigned_short;
         Data_3 : Interfaces.C.unsigned_short;
         Data_4 : Interfaces.C.char_array (1 .. 8);
      end record with Convention => C;

      --  FOLDERID_Fonts, {FD228CB7-AE11-4AE3-864C-16F3910AB8FE}.
      Folder_Id_Fonts : aliased constant Guid :=
        (Data_1 => 16#FD22_8CB7#,
         Data_2 => 16#AE11#,
         Data_3 => 16#4AE3#,
         Data_4 =>
           [Interfaces.C.char'Val (16#86#), Interfaces.C.char'Val (16#4C#), Interfaces.C.char'Val (16#16#),
            Interfaces.C.char'Val (16#F3#), Interfaces.C.char'Val (16#91#), Interfaces.C.char'Val (16#0A#),
            Interfaces.C.char'Val (16#B8#), Interfaces.C.char'Val (16#FE#)]);

      function Get_Known_Folder_Path
        (Id     : access constant Guid;
         Flags  : C_DWord;
         Token  : System.Address;
         Result : access System.Address) return Interfaces.C.long
        with Import, Convention => Stdcall, External_Name => "SHGetKnownFolderPath";

      procedure Free (Block : System.Address)
        with Import, Convention => Stdcall, External_Name => "CoTaskMemFree";

      function Wide_Length (Text : System.Address) return Interfaces.C.int
        with Import, Convention => Stdcall, External_Name => "lstrlenW";

      function Known_Fonts return String is
         use type Interfaces.C.long;
         use type System.Address;
         Text   : aliased System.Address := System.Null_Address;
         Status : constant Interfaces.C.long :=
           Get_Known_Folder_Path (Folder_Id_Fonts'Access, 0, System.Null_Address, Text'Access);
      begin
         if Status /= 0 or else Text = System.Null_Address then
            Hostkit.Errors.Set_Errno_From_Last_Error;
            if Text /= System.Null_Address then
               Free (Text);
            end if;
            return "";
         end if;
         declare
            Length : constant Natural := Natural (Wide_Length (Text));
            Units  : constant Wide_String (1 .. Length) with Import, Address => Text;
            Folder : constant String := Hostkit.Windows_Paths.To_UTF_8 (Units);
         begin
            Free (Text);
            return Folder;
         end;
      end Known_Fonts;

      function Env (Name : String) return String is (Hostkit.Environment.Value (Name, ""));
      Known   : constant String := Known_Fonts;
      Windows : constant String := (if Env ("WINDIR") /= "" then Env ("WINDIR") else Env ("SystemRoot"));
      System_Fonts : constant String :=
        (if Known /= "" then Known elsif Windows /= "" then Windows & "\Fonts" else "");
      Local   : constant String := Cache_Directory;
      function Place (Folder : String) return Path_List is
        (if Folder = "" then [] else [1 => To_Unbounded_String (Folder)]);
   begin
      return Place (System_Fonts)
        & Place ((if Local = "" then "" else Local & "\Microsoft\Windows\Fonts"));
   end Font_Directories;

   function Application_Data_Directory return String is
      Home : constant String := Home_Directory;
   begin
      if Hostkit.Environment.Value ("APPDATA", "") /= "" then
         return Hostkit.Environment.Value ("APPDATA", "");
      end if;
      return (if Home = "" then "" else Home & "\AppData\Roaming");
   end Application_Data_Directory;

   function Cache_Directory return String is
      Home : constant String := Home_Directory;
   begin
      --  LOCALAPPDATA, the non-roaming half of the profile. See the spec.
      if Hostkit.Environment.Value ("LOCALAPPDATA", "") /= "" then
         return Hostkit.Environment.Value ("LOCALAPPDATA", "");
      end if;
      return (if Home = "" then "" else Home & "\AppData\Local");
   end Cache_Directory;

   --  The same place as the application data, and roaming on purpose: what the
   --  user chose should follow them to another machine.
   function Config_Directory return String is
   begin
      return Application_Data_Directory;
   end Config_Directory;

   function Temp_Directory return String is
      Buf : aliased Wide_String (1 .. 1024) := [others => Wide_Character'Val (0)];
      N   : constant C_DWord := Get_Temp_Path (C_DWord (Buf'Length), Buf'Address);
   begin
      --  GetTempPathW returns 0 on failure, or the length required if the
      --  buffer was too small; 1024 UTF-16 units hold any temp dir.
      if N = 0 or else N > C_DWord (Buf'Length) then
         return ".";
      end if;
      declare
         Raw : constant String := Hostkit.Windows_Paths.To_UTF_8 (Buf (1 .. Natural (N)));
      begin
         --  GetTempPathW always appends a trailing backslash; drop it so the
         --  result composes with "/" or "\" the way callers expect.
         if Raw'Length > 1 and then (Raw (Raw'Last) = '\' or else Raw (Raw'Last) = '/') then
            return Raw (Raw'First .. Raw'Last - 1);
         end if;
         return Raw;
      end;
   end Temp_Directory;

   function Create_Temporary_Directory (Prefix : String) return String is
      Base : constant String := Temp_Directory;

      function Image (Value : Natural) return String is
        (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Left));

      function Time_Image return String is
         Raw : constant String := Duration'Image (Ada.Calendar.Seconds (Ada.Calendar.Clock));
         Result : String := Raw;
      begin
         for C of Result loop
            if C = ' ' or else C = '.' then
               C := '-';
            end if;
         end loop;
         return Result;
      end Time_Image;

      function Safe_Prefix return String is
         Result : String := Prefix;
      begin
         for C of Result loop
            if not (C in 'A' .. 'Z' or else C in 'a' .. 'z'
                    or else C in '0' .. '9' or else C = '-' or else C = '_')
            then
               C := '-';
            end if;
         end loop;
         return (if Result = "" then "hostkit-temp" else Result);
      end Safe_Prefix;
   begin
      for Attempt in 1 .. 1000 loop
         declare
            Candidate : constant String := Join (Base, Safe_Prefix & "-" & Time_Image & "-" & Image (Attempt));
         begin
            if Create_Directory (Candidate) then
               return Candidate;
            end if;
         end;
      end loop;
      return "";
   end Create_Temporary_Directory;

   function Uses_Dos_Filename_Rules (Path : String) return Boolean is
      pragma Unreferenced (Path);
   begin
      --  Every local Windows volume is a DOS-family filesystem (NTFS, FAT,
      --  exFAT); a POSIX filesystem there needs a third-party driver and is
      --  vanishingly rare. Treat them all as DOS-ruled, which is also exactly the
      --  host-based behaviour this refines on the other platforms.
      return True;
   end Uses_Dos_Filename_Rules;

   function Folds_Name_Case (Directory : String) return Boolean is
      pragma Unreferenced (Directory);
   begin
      --  NTFS can be told per directory to tell case apart, but nothing
      --  Windows itself makes is; FAT and exFAT never do.
      return True;
   end Folds_Name_Case;

   ---------------
   -- Separator --
   ---------------

   --  Written as a backslash. Both are accepted by the file calls, which is
   --  why a path built with the wrong one goes unnoticed until it is shown
   --  to someone.
   --
   --  One backslash. Ada string and character literals carry no escapes, so
   --  a doubled one here is two characters where one is meant -- and in a
   --  character literal it is not a literal at all, which is what stopped
   --  every Windows build of this crate.
   function Separator return Character is ('\');

   ---------------------------
   -- Search_Path_Delimiter --
   ---------------------------

   function Search_Path_Delimiter return Character is
   begin
      return ';';
   end Search_Path_Delimiter;

   ------------------------
   -- Executable_Suffix --
   ------------------------

   function Executable_Suffix return String is
   begin
      return ".exe";
   end Executable_Suffix;

   -----------------------
   -- Starts_When_Named --
   -----------------------

   --  What CreateProcess starts from a name. A .exe and a .com it loads; a
   --  .bat and a .cmd it hands to the command interpreter, which it starts
   --  itself. A .ps1 and an .msi it does not: those are read by another shell
   --  and by the installer, and a caller that named one would meet a failed
   --  process creation reading as though the file were missing.
   function Starts_When_Named (Path : String) return Boolean is
      function Ends_With (Suffix : String) return Boolean
      is (Path'Length >= Suffix'Length
          and then Ada.Characters.Handling.To_Lower
                     (Path (Path'Last - Suffix'Length + 1 .. Path'Last))
                   = Suffix);
   begin
      return Is_Executable (Path)
        and then (Ends_With (".exe") or else Ends_With (".com")
                  or else Ends_With (".bat") or else Ends_With (".cmd"));
   end Starts_When_Named;

   -------------------
   -- Creation_Mask --
   -------------------

   --  Windows has none. Permissions come from the ACL a directory hands down,
   --  and there is no per-process subtraction to read or to write -- so this
   --  refuses rather than inventing a number a caller would then act on.
   function Creation_Mask (Value : out Natural) return Boolean is
   begin
      Value := 0;
      return False;
   end Creation_Mask;

   function Set_Creation_Mask
     (Value : Natural; Previous : out Natural) return Boolean
   is
      pragma Unreferenced (Value);
   begin
      Previous := 0;
      return False;
   end Set_Creation_Mask;

   ------------------
   -- Null_Device --
   ------------------

   function Null_Device return String is
   begin
      --  The name the loader knows rather than a path: it is not a file in a
      --  directory here, and "\\.\NUL" would be the same device named the
      --  long way round.
      return "NUL";
   end Null_Device;

   function Delete_Empty_Directory (Path : String) return Boolean is
      function Remove_Directory (Name : System.Address) return Interfaces.C.int
        with Import => True, Convention => Stdcall, External_Name => "RemoveDirectoryW";
      function Set_File_Attributes (Name : System.Address; Attributes : C_DWord) return Interfaces.C.int
        with Import => True, Convention => Stdcall, External_Name => "SetFileAttributesW";
      Read_Only  : constant C_DWord := 16#0001#;
      Wide_Path  : aliased Wide_String := Wide (Path);
      Attributes : constant C_DWord := Get_File_Attributes (Wide_Path'Address);
      Ignored    : Interfaces.C.int;
   begin
      if Attributes /= Invalid_File_Attributes and then (Attributes and Read_Only) /= 0 then
         Ignored := Set_File_Attributes (Wide_Path'Address, Attributes - Read_Only);
      end if;
      if Remove_Directory (Wide_Path'Address) = 0 then
         Hostkit.Errors.Set_Errno_From_Last_Error;
         return False;
      end if;
      return True;
   exception
      when others =>
         return False;
   end Delete_Empty_Directory;

   --  DeleteFileW through the long form. A link is removed as Delete_Link
   --  removes one -- RemoveDirectoryW for a link to a directory, which
   --  DeleteFileW refuses -- and a read-only file has the attribute cleared
   --  first, put back if the delete is refused anyway.
   function Delete_File (Path : String) return Boolean is
      function Delete_File_W (Name : System.Address) return Interfaces.C.int
        with Import => True, Convention => Stdcall, External_Name => "DeleteFileW";
      function Set_File_Attributes (Name : System.Address; Attributes : C_DWord) return Interfaces.C.int
        with Import => True, Convention => Stdcall, External_Name => "SetFileAttributesW";
      Read_Only : constant C_DWord := 16#0001#;
   begin
      if Path = "" or else (for some C of Path => C = ASCII.NUL) then
         return False;
      end if;
      declare
         Wide_Path  : aliased Wide_String := Wide (Path);
         Attributes : constant C_DWord := Get_File_Attributes (Wide_Path'Address);
         Ignored    : Interfaces.C.int;
      begin
         if Attributes = Invalid_File_Attributes then
            return False;
         elsif (Attributes and File_Attribute_Reparse_Point) /= 0 then
            return Delete_Link (Path);
         elsif (Attributes and File_Attribute_Directory) /= 0 then
            return False;
         elsif (Attributes and Read_Only) /= 0 then
            Ignored := Set_File_Attributes (Wide_Path'Address, Attributes - Read_Only);
            if Delete_File_W (Wide_Path'Address) /= 0 then
               return True;
            end if;
            Hostkit.Errors.Set_Errno_From_Last_Error;
            Ignored := Set_File_Attributes (Wide_Path'Address, Attributes);
            return False;
         elsif Delete_File_W (Wide_Path'Address) = 0 then
            Hostkit.Errors.Set_Errno_From_Last_Error;
            return False;
         end if;
         return True;
      end;
   exception
      when others =>
         return False;
   end Delete_File;

   --  CreateDirectoryW through the long form, with the ACL the parent hands
   --  down; an existing entry is ERROR_ALREADY_EXISTS.
   function Create_Directory (Path : String) return Boolean is
      function Create_Directory_W (Name : System.Address; Security : System.Address) return Interfaces.C.int
        with Import => True, Convention => Stdcall, External_Name => "CreateDirectoryW";
   begin
      if Path = "" or else (for some C of Path => C = ASCII.NUL) then
         return False;
      end if;
      declare
         Wide_Path : aliased constant Wide_String := Wide (Path);
      begin
         if Create_Directory_W (Wide_Path'Address, System.Null_Address) = 0 then
            Hostkit.Errors.Set_Errno_From_Last_Error;
            return False;
         end if;
         return True;
      end;
   exception
      when others =>
         return False;
   end Create_Directory;

   function Create_Path (Path : String) return Boolean is separate;

   --  GetCurrentDirectoryW, asked first how long the answer is: called with
   --  too small a buffer it returns the length it needs, terminator included.
   function Current_Directory return String is
      function Get_Current_Directory (Length : C_DWord; Buffer : System.Address) return C_DWord
        with Import => True, Convention => Stdcall, External_Name => "GetCurrentDirectoryW";
      Needed : C_DWord := Get_Current_Directory (0, System.Null_Address);
      Tries  : Natural := 0;
   begin
      --  It can change between the two calls; ask again when it grew.
      while Needed > 0 and then Tries < 4 loop
         Tries := Tries + 1;
         declare
            Buffer  : aliased Wide_String (1 .. Natural (Needed)) := [others => Wide_Character'Val (0)];
            Written : constant C_DWord := Get_Current_Directory (Needed, Buffer'Address);
         begin
            if Written = 0 then
               return "";
            elsif Written < Needed then
               return Hostkit.Windows_Paths.To_UTF_8 (Buffer (1 .. Natural (Written)));
            end if;
            Needed := Written;
         end;
      end loop;
      return "";
   exception
      when others =>
         return "";
   end Current_Directory;

   --  _wfopen of the long form: the C runtime's own stream, which GNAT's
   --  reads and writes as one of its own. Text picks the translated mode,
   --  't', as GNAT's Text_IO opens one here, else 'b'.
   function Wide_Fopen (Name : System.Address; Mode : System.Address) return Interfaces.C_Streams.FILEs
     with Import => True, Convention => C, External_Name => "_wfopen";

   --  The C stream for Path opened in fopen's Mode, for the stream and text
   --  subunits: Name_Error when nothing is there, Use_Error for any other
   --  refusal.
   function C_Stream_For (Path : String; Mode : String; Text : Boolean) return Interfaces.C_Streams.FILEs is
      use type System.Address;
      Wide_Mode : aliased constant Wide_String :=
        Hostkit.Windows_Paths.From_UTF_8 (Mode & (if Text then "t" else "b")) & Wide_Character'Val (0);
      Stream    : Interfaces.C_Streams.FILEs := Interfaces.C_Streams.NULL_Stream;
      Error     : Integer := 2;
   begin
      if Path /= "" and then (for all C of Path => C /= ASCII.NUL) then
         declare
            Wide_Path : aliased constant Wide_String := Wide (Path);
         begin
            Stream := Wide_Fopen (Wide_Path'Address, Wide_Mode'Address);
            Error := GNAT.OS_Lib.Errno;
         end;
      end if;
      if Stream /= Interfaces.C_Streams.NULL_Stream then
         return Stream;
      elsif Error = 2 then
         raise Ada.IO_Exceptions.Name_Error with Path & ": " & GNAT.OS_Lib.Errno_Message (Err => Error);
      end if;
      raise Ada.IO_Exceptions.Use_Error with Path & ": " & GNAT.OS_Lib.Errno_Message (Err => Error);
   end C_Stream_For;

   procedure Open_Stream
     (File : in out Ada.Streams.Stream_IO.File_Type;
      Mode : Ada.Streams.Stream_IO.File_Mode;
      Path : String) is separate;

   procedure Create_Stream
     (File : in out Ada.Streams.Stream_IO.File_Type;
      Mode : Ada.Streams.Stream_IO.File_Mode := Ada.Streams.Stream_IO.Out_File;
      Path : String) is separate;

   procedure Open_Text
     (File : in out Ada.Text_IO.File_Type;
      Mode : Ada.Text_IO.File_Mode;
      Path : String) is separate;

   procedure Create_Text
     (File : in out Ada.Text_IO.File_Type;
      Mode : Ada.Text_IO.File_Mode := Ada.Text_IO.Out_File;
      Path : String) is separate;

end Hostkit.Fs;
