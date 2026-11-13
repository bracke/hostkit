with Hostkit.Environment;
with Ada.Characters.Handling;
with Ada.IO_Exceptions;
with Ada.Strings.Fixed;

with GNAT.OS_Lib;

with Hostkit.Errors;
with Hostkit.Fs.Instants;
with Hostkit.Win32;
with Hostkit.Windows_Errors;
with Hostkit.Windows_Paths;
with Hostkit.Windows_Programs;
with Interfaces.C;
with Interfaces.C_Streams;

with System;

package body Hostkit.Fs is

   use Hostkit.Win32;
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned_long;

   subtype C_DWord is Interfaces.C.unsigned_long;

   Invalid_File_Attributes      : constant C_DWord := 16#FFFF_FFFF#;

   Symbolic_Link_Allow_Unprivileged : constant C_DWord := 16#0000_0002#;
   Symbolic_Link_Directory          : constant C_DWord := 16#0000_0001#;

   --  Paths are UTF-8 here and UTF-16 to Windows: the "A" entry points would
   --  read them in the ANSI code page, so any non-ASCII path (a profile named
   --  Jürgen) would not be found.
   function Get_Temp_Path
     (Buffer_Length : C_DWord;
      Buffer        : System.Address)
      return C_DWord
     with Import => True, Convention => Stdcall, External_Name => "GetTempPathW";

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
      use type System.Address;
      Wide_Path  : aliased Wide_String := Wide (Path);
      Attributes : constant C_DWord := Get_File_Attributes (Wide_Path'Address);
      --  Only the reparse tag of what FindFirstFileW finds is read.
      Data       : aliased Find_Data;
      Handle     : System.Address;
   begin
      if Attributes = Invalid_File_Attributes
        or else (Attributes and File_Attribute_Reparse_Point) = 0
      then
         return False;
      end if;
      Handle := Find_First_File (Wide_Path'Address, Data'Access);
      if Handle = Invalid_Handle_Value then
         --  The tag is unreadable: a reparse point is still safest treated
         --  as a link, which is never followed.
         return True;
      end if;
      if Find_Close (Handle) = 0 then
         null;
      end if;
      return Is_Link_Tag (Data.Reparse_Tag);
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
         Handle := Create_File
           (Native_Path'Address, File_Read_Attributes_Access, Share_Everything, System.Null_Address,
            Open_Existing_Only, Backup_Semantics_Flag, System.Null_Address);
      end;
      if Handle = Invalid_Handle_Value then
         return False;
      end if;
      Kind := Get_File_Type (Handle);
      Ignored := Close_Handle (Handle);
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
         Refuse (Path, Get_Last_Error);
      elsif Follow_Links
        and then (Data.Attributes and File_Attribute_Reparse_Point) /= 0
        and then Is_Link (Path)
      then
         declare
            use type System.Address;
            Handle  : constant System.Address :=
              Create_File
                (Native_Path'Address, File_Read_Attributes_Access, Share_Everything, System.Null_Address,
                 Open_Existing_Only, Backup_Semantics_Flag, System.Null_Address);
            Info    : aliased By_Handle_File_Information;
            Asked   : Boolean;
            Error   : C_DWord;
            Ignored : Interfaces.C.int;
         begin
            if Handle = Invalid_Handle_Value then
               Refuse (Path, Get_Last_Error);
            end if;
            Asked := Get_File_Information (Handle, Info'Access) /= 0;
            Error := Get_Last_Error;
            Ignored := Close_Handle (Handle);
            if not Asked then
               Refuse (Path, Error);
            end if;
            return
              (Attributes => Info.Attributes,
               Written    => Joined (Info.Modified_Time.High, Info.Modified_Time.Low),
               Size       => Joined (Info.Size_High, Info.Size_Low));
         end;
      end if;
      return
        (Attributes => Data.Attributes,
         Written    => Joined (Data.Modified_Time.High, Data.Modified_Time.Low),
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

      Owner_Group_Dacl       : constant C_DWord := 16#1# + 16#2# + 16#4#;
      Token_Duplicate        : constant C_DWord := 16#2#;
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
            Ignored_Close := Close_Handle (Token);
         end if;
         if Process_Token /= System.Null_Address then
            Ignored_Close := Close_Handle (Process_Token);
         end if;
         if Descriptor /= System.Null_Address then
            Ignored_Free := Local_Free (Descriptor);
         end if;
      end Let_Go;
   begin
      declare
         Handle  : constant System.Address :=
           Create_File
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
         Ignored := Close_Handle (Handle);
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
      Wide_Path  : aliased Wide_String := Wide (Path);
      Attributes : constant C_DWord := Get_File_Attributes (Wide_Path'Address);
   begin
      if Attributes = Invalid_File_Attributes
        or else (Attributes and File_Attribute_Directory) /= 0
      then
         return False;
      end if;

      return Hostkit.Windows_Programs.Runs_By_Extension (Path);
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
   --  print name is the human target ("real.txt"); the substitute name is a fallback,
   --  in the NT form (\??\C:\x, \??\UNC\server\share) that Win32 text never carries,
   --  so it is read back as C:\x and \\server\share. A failure sets errno, as
   --  readlink does: EINVAL for an entry that is no symbolic link or junction.
   function Read_Link_Target
     (Path   : String;
      Target : out Ada.Strings.Unbounded.Unbounded_String)
      return Boolean
   is
      use type System.Address;

      Fsctl_Get_Reparse_Point : constant C_DWord := 16#0009_00A8#;
      Flag_Backup_Semantics   : constant C_DWord := 16#0200_0000#;
      Flag_Open_Reparse_Point : constant C_DWord := 16#0020_0000#;
      Share_All               : constant C_DWord := 7;
      --  ERROR_NOT_A_REPARSE_POINT, ERROR_INVALID_REPARSE_DATA: no link to
      --  read here, which errno says as EINVAL.
      Error_Not_A_Reparse_Point  : constant Interfaces.Unsigned_32 := 4390;
      Error_Invalid_Reparse_Data : constant Interfaces.Unsigned_32 := 4392;

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

      Wide_Path : aliased Wide_String := Wide (Path);
      Buffer    : array (0 .. 16 * 1024 - 1) of aliased Interfaces.Unsigned_8 :=
        [others => 0];
      Handle    : System.Address;
      Returned  : aliased C_DWord := 0;
      Outcome   : Interfaces.C.int;
      Error     : C_DWord;
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
      if Handle = Invalid_Handle_Value then
         Hostkit.Errors.Set_Errno_From_Last_Error;
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
      Error := Get_Last_Error;
      Ignored := Close_Handle (Handle);
      if Outcome = 0 then
         Hostkit.Windows_Errors.Set_Errno_From (Interfaces.Unsigned_32 (Error));
         return False;
      end if;

      declare
         use type Interfaces.Unsigned_32;
         Tag           : constant Interfaces.Unsigned_32 := Interfaces.Unsigned_32 (U32 (0));
         Path_Buf_Base : Natural;
         Name_Off      : Natural;
         Name_Len      : Natural;   --  in bytes
      begin
         if Tag = Io_Reparse_Tag_Symlink then
            Path_Buf_Base := 20;
         elsif Tag = Io_Reparse_Tag_Mount_Point then
            Path_Buf_Base := 16;
         else
            --  A cloud placeholder, a deduplicated file: no link.
            Hostkit.Windows_Errors.Set_Errno_From (Error_Not_A_Reparse_Point);
            return False;
         end if;

         Name_Off := U16 (12);   --  PrintNameOffset
         Name_Len := U16 (14);   --  PrintNameLength
         if Name_Len = 0 then
            Name_Off := U16 (8);    --  SubstituteNameOffset
            Name_Len := U16 (10);   --  SubstituteNameLength
         end if;
         if Name_Len = 0 then
            Hostkit.Windows_Errors.Set_Errno_From (Error_Invalid_Reparse_Data);
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
            --  A substitute name is an NT \??\ name, which Win32 text
            --  never carries: Windows_Paths.Win32_Form reads it as C:\x,
            --  \\server\share, or -- a volume mount point -- \\?\Volume{...}\.
            Target := Ada.Strings.Unbounded.To_Unbounded_String
              (Hostkit.Windows_Paths.Win32_Form (Hostkit.Windows_Paths.To_UTF_8 (Wide_T)));
         end;
      end;
      return True;
   exception
      when others =>
         --  Reparse data whose offsets point past what was returned.
         Target := Ada.Strings.Unbounded.Null_Unbounded_String;
         Hostkit.Windows_Errors.Set_Errno_From (Error_Invalid_Reparse_Data);
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

   function Delete_Tree_No_Follow (Path : String) return Delete_Tree_Outcome is separate;

   --  Windows has no realpath. Open the path -- following links, so no
   --  FILE_FLAG_OPEN_REPARSE_POINT here -- and ask the kernel for the final, canonical
   --  name of what the handle actually refers to. GetFinalPathNameByHandleW returns it in
   --  the \\?\ (or \\?\UNC\) namespace; strip that prefix so callers see an ordinary path.
   --  Ada.Directories.Full_Name is GetFullPathName here: purely lexical, follows nothing.
   function Real_Path (Path : String) return String is
      use type System.Address;

      Flag_Backup_Semantics : constant C_DWord := 16#0200_0000#;
      Share_All             : constant C_DWord := 7;

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
         if Handle = Invalid_Handle_Value then
            return "";
         end if;

         --  Flags 0 == VOLUME_NAME_DOS or FILE_NAME_NORMALIZED. Length is the count of
         --  WCHARs written (excluding the terminating NUL); 0 on failure, or -- if it
         --  would not fit -- the required size including the NUL, treated as failure.
         Length := Get_Final_Path_Name
           (Object => Handle,
            Path   => Wide_Buf'Address,
            Count  => Wide_Buf'Length,
            Flags  => 0);
         Ignored := Close_Handle (Handle);

         if Length = 0 or else Length > Wide_Buf'Length then
            return "";
         end if;

         --  \\?\UNC\server\share -> \\server\share ; \\?\C:\dir -> C:\dir; a
         --  volume with no drive letter keeps its \\?\Volume{...}\ form.
         return Hostkit.Windows_Paths.Win32_Form (Hostkit.Windows_Paths.To_UTF_8 (Wide_Buf (1 .. Natural (Length))));
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
      Outcome : out Read_Beneath_Outcome) is separate;

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
      Read_Only  : constant C_DWord := 16#0001#;
      --  The UCRT's ENOTDIR.
      E_Not_Dir  : constant := 20;
      Wide_Path  : aliased Wide_String := Wide (Path);
      Attributes : constant C_DWord := Get_File_Attributes (Wide_Path'Address);
      Cleared    : constant Boolean :=
        Attributes /= Invalid_File_Attributes and then (Attributes and Read_Only) /= 0;
      Ignored    : Interfaces.C.int;
   begin
      --  A symbolic link to a folder or a junction is no directory to remove,
      --  as rmdir refuses one with ENOTDIR on POSIX; RemoveDirectoryW would
      --  take the link away. Delete_Link removes a link.
      if Attributes /= Invalid_File_Attributes
        and then (Attributes and File_Attribute_Reparse_Point) /= 0
        and then Is_Link (Path)
      then
         GNAT.OS_Lib.Set_Errno (E_Not_Dir);
         return False;
      end if;
      if Cleared then
         Ignored := Set_File_Attributes (Wide_Path'Address, Attributes - Read_Only);
      end if;
      if Remove_Directory (Wide_Path'Address) = 0 then
         --  As Delete_File: the reason first, before the attribute is put
         --  back and the last error with it overwritten.
         Hostkit.Errors.Set_Errno_From_Last_Error;
         if Cleared then
            Ignored := Set_File_Attributes (Wide_Path'Address, Attributes);
         end if;
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
            --  A file just written may be held a moment by someone else -- a
            --  virus scanner, the search indexer -- that did not share it
            --  (ERROR_SHARING_VIOLATION, ERROR_LOCK_VIOLATION); try again
            --  briefly, as Durability.Sync_File does. Nothing else is retried.
            for Attempt in 1 .. 10 loop
               Stream := Wide_Fopen (Wide_Path'Address, Wide_Mode'Address);
               exit when Stream /= Interfaces.C_Streams.NULL_Stream or else Get_Last_Error not in 32 | 33;
               delay Duration (Attempt) * 0.02;
            end loop;
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
