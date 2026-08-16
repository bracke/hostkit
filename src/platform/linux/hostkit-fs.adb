with Ada.Calendar;
with Ada.Environment_Variables;
with System;
with Ada.Directories;
with Ada.Text_IO;
with Ada.Characters.Latin_1;
with Ada.Strings.Fixed;

with GNAT.OS_Lib;

with Interfaces.C.Strings;

with Hostkit.Filesystem_Rules;

package body Hostkit.Fs is
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned;
   use type Interfaces.C.unsigned_short;
   use type Interfaces.C.unsigned_long;

   subtype C_Int is Interfaces.C.int;
   subtype C_Unsigned is Interfaces.C.unsigned;
   subtype C_U16 is Interfaces.C.unsigned_short;
   subtype C_U32 is Interfaces.C.unsigned;
   subtype C_U64 is Interfaces.C.unsigned_long;
   subtype C_S64 is Interfaces.C.long;

   type U16_Array is array (Positive range <>) of C_U16
     with Convention => C;

   type U64_Array is array (Positive range <>) of C_U64
     with Convention => C;

   type Statx_Timestamp is record
      Seconds     : C_S64;
      Nanoseconds : C_U32;
      Reserved    : C_U32;
   end record
     with Convention => C;

   type Statx_Record is record
      Mask            : C_U32;
      Block_Size      : C_U32;
      Attributes      : C_U64;
      Link_Count      : C_U32;
      User_Id         : C_U32;
      Group_Id        : C_U32;
      Mode            : C_U16;
      Spare_0         : U16_Array (1 .. 1);
      Inode           : C_U64;
      Size            : C_U64;
      Blocks          : C_U64;
      Attributes_Mask : C_U64;
      Access_Time     : Statx_Timestamp;
      Birth_Time      : Statx_Timestamp;
      Change_Time     : Statx_Timestamp;
      Modified_Time   : Statx_Timestamp;
      Device_Major    : C_U32;
      Device_Minor    : C_U32;
      File_Major      : C_U32;
      File_Minor      : C_U32;
      Mount_Id        : C_U64;
      Direct_Io_Memory_Align : C_U32;
      Direct_Io_Offset_Align : C_U32;
      Spare_3         : U64_Array (1 .. 12);
   end record
     with Convention => C;

   function Statx
     (Directory_Fd : C_Int;
      Pathname     : Interfaces.C.Strings.chars_ptr;
      Flags        : C_Unsigned;
      Mask         : C_Unsigned;
      Buffer       : access Statx_Record)
      return C_Int
     with Import, Convention => C, External_Name => "statx";

   At_FDCWD        : constant C_Int := -100;
   Statx_Mode      : constant C_Unsigned := 16#2#;
   Permission_Mask : constant C_U16 := 8#7777#;
   File_Type_Mask  : constant C_U16 := 8#170000#;
   S_IFIFO         : constant C_U16 := 8#010000#;
   S_IFCHR         : constant C_U16 := 8#020000#;
   S_IFBLK         : constant C_U16 := 8#060000#;
   S_IFSOCK        : constant C_U16 := 8#140000#;

   AF_UNIX     : constant C_Int := 1;
   SOCK_STREAM : constant C_Int := 1;

   type Sockaddr_Un is record
      Family : Interfaces.C.short := 0;
      Path   : Interfaces.C.char_array (0 .. 107) := [others => Interfaces.C.nul];
   end record
     with Convention => C;

   function Symlink
     (Target : Interfaces.C.Strings.chars_ptr;
      Link   : Interfaces.C.Strings.chars_ptr)
      return Interfaces.C.int
     with Import => True, Convention => C, External_Name => "symlink";

   --  On POSIX these two GNAT helpers are honest: there is an lstat behind the first,
   --  and the mode bits behind the second. It is only on Windows that they answer
   --  without being able to know.
   function Is_Link (Path : String) return Boolean is
   begin
      return GNAT.OS_Lib.Is_Symbolic_Link (Path);
   exception
      when others =>
         return False;
   end Is_Link;

   function Create_Link
     (Target    : String;
      Link_Path : String)
      return Boolean
   is
      use type Interfaces.C.Strings.chars_ptr;
      C_Target : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Target);
      C_Link   : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Link_Path);
      Status   : Interfaces.C.int;
   begin
      Status := Symlink (C_Target, C_Link);
      Interfaces.C.Strings.Free (C_Target);
      Interfaces.C.Strings.Free (C_Link);
      return Status = 0;
   exception
      when others =>
         if C_Target /= Interfaces.C.Strings.Null_Ptr then
            Interfaces.C.Strings.Free (C_Target);
         end if;
         if C_Link /= Interfaces.C.Strings.Null_Ptr then
            Interfaces.C.Strings.Free (C_Link);
         end if;
         return False;
   end Create_Link;

   --  A regular file, and a mode bit that says it runs. The regular-file half matters:
   --  a directory carries the execute bit too, and means something else entirely by it.
   function Is_Executable (Path : String) return Boolean is
      use type Ada.Directories.File_Kind;
   begin
      --  Kind alone, not Exists and then Kind: Kind raises Name_Error for a path
      --  that is not there, which the handler below already turns into False.
      --  The Exists call was a third stat of the same path for an answer the
      --  next one gives, and a directory listing pays this per file.
      return Ada.Directories.Kind (Path) = Ada.Directories.Ordinary_File
        and then GNAT.OS_Lib.Is_Executable_File (Path);
   exception
      when others =>
         return False;
   end Is_Executable;

   function Linux_Device_Number (Major, Minor : C_U32) return Interfaces.Unsigned_64 is
      use type Interfaces.Unsigned_64;
      Major_Value : constant Interfaces.Unsigned_64 := Interfaces.Unsigned_64 (Major);
      Minor_Value : constant Interfaces.Unsigned_64 := Interfaces.Unsigned_64 (Minor);
   begin
      return ((Major_Value and 16#00000FFF#) * 2 ** 8)
        or (Minor_Value and 16#000000FF#)
        or ((Minor_Value and not 16#000000FF#) * 2 ** 12)
        or ((Major_Value and not 16#00000FFF#) * 2 ** 32);
   end Linux_Device_Number;

   function Special_File_Info_Of (Path : String) return Special_File_Info is
      C_Path : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      Info   : aliased Statx_Record;
      Status : C_Int;
      Mode   : C_U16;
   begin
      Status := Statx (At_FDCWD, C_Path, 0, Statx_Mode, Info'Access);
      Interfaces.C.Strings.Free (C_Path);
      if Status /= 0 then
         return (Available => False, Kind => Not_Special, Device => 0, Mode => 0);
      end if;

      Mode := Info.Mode and File_Type_Mask;
      if Mode = S_IFIFO then
         return
           (Available => True,
            Kind      => FIFO,
            Device    => 0,
            Mode      => Natural (Info.Mode and Permission_Mask));
      elsif Mode = S_IFCHR then
         return
           (Available => True,
            Kind      => Special_File_Kind'(Character_Device),
            Device    => Linux_Device_Number (Info.File_Major, Info.File_Minor),
            Mode      => Natural (Info.Mode and Permission_Mask));
      elsif Mode = S_IFBLK then
         return
           (Available => True,
            Kind      => Special_File_Kind'(Block_Device),
            Device    => Linux_Device_Number (Info.File_Major, Info.File_Minor),
            Mode      => Natural (Info.Mode and Permission_Mask));
      elsif Mode = S_IFSOCK then
         return
           (Available => True,
            Kind      => Socket,
            Device    => 0,
            Mode      => Natural (Info.Mode and Permission_Mask));
      else
         return
           (Available => True,
            Kind      => Other_Special,
            Device    => 0,
            Mode      => Natural (Info.Mode and Permission_Mask));
      end if;
   exception
      when others =>
         return (Available => False, Kind => Not_Special, Device => 0, Mode => 0);
   end Special_File_Info_Of;

   --  Group or other having any permission at all: (st_mode and 8#077#) /= 0. Those six bits
   --  live in the lowest byte of st_mode, so this reads that one byte out of the stat buffer
   --  rather than reconstructing the whole field. Want keeps the two callers apart: a file's
   --  bits and a directory's do not mean the same thing, so neither answers for the other.
   function Exposed (Path : String; Want : Ada.Directories.File_Kind) return Boolean is
      use type Interfaces.Unsigned_8;
      use type Ada.Directories.File_Kind;

      --  struct stat is larger than this; stat writes only into what it needs and the mode
      --  sits near the front. Oversized so there is always room.
      Buffer : array (0 .. 255) of aliased Interfaces.Unsigned_8 := [others => 0];

      function C_Stat (Path : Interfaces.C.Strings.chars_ptr; Buf : System.Address)
        return Interfaces.C.int
        with Import => True, Convention => C, External_Name => "stat";

      C_Path : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      Result : Interfaces.C.int;
   begin
      if not Ada.Directories.Exists (Path)
        or else Ada.Directories.Kind (Path) /= Want
      then
         Interfaces.C.Strings.Free (C_Path);
         return False;
      end if;

      Result := C_Stat (C_Path, Buffer'Address);
      Interfaces.C.Strings.Free (C_Path);

      if Result /= 0 then
         return False;
      end if;

      --  st_mode's low byte holds the group and other permission bits. Its offset in the
      --  struct is 24 on this platform's LP64 layout.
      return (Buffer (24) and 8#077#) /= 0;
   exception
      when others =>
         return False;
   end Exposed;

   function Accessible_By_Others (Path : String) return Boolean is
   begin
      return Exposed (Path, Ada.Directories.Ordinary_File);
   end Accessible_By_Others;

   function Directory_Accessible_By_Others (Path : String) return Boolean is
   begin
      return Exposed (Path, Ada.Directories.Directory);
   end Directory_Accessible_By_Others;

   --  chmod(2), not a spawned chmod(1): no PATH to find, and a return code to check.

   function Set_Owner (Path : String; User : Integer; Group : Integer) return Boolean is
      function C_Chown
        (Path : Interfaces.C.Strings.chars_ptr;
         UID  : Interfaces.C.int;
         GID  : Interfaces.C.int) return Interfaces.C.int
        with Import => True, Convention => C, External_Name => "chown";

      C_Path : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Path);
      Status : Interfaces.C.int;
   begin
      Status :=
        C_Chown (C_Path, Interfaces.C.int (User), Interfaces.C.int (Group));
      Interfaces.C.Strings.Free (C_Path);
      return Status = 0;
   exception
      when others =>
         return False;
   end Set_Owner;

   function Set_Extended_Attribute
     (Path  : String;
      Name  : String;
      Value : Ada.Streams.Stream_Element_Array) return Boolean
   is
      function C_Setxattr
        (Path  : Interfaces.C.Strings.chars_ptr;
         Name  : Interfaces.C.Strings.chars_ptr;
         Value : System.Address;
         Size  : Interfaces.C.size_t;
         Flags : Interfaces.C.int) return Interfaces.C.int
        with Import => True, Convention => C, External_Name => "setxattr";

      C_Path : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Path);
      C_Name : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Name);
      Buffer : Ada.Streams.Stream_Element_Array := Value;
      Status : Interfaces.C.int;
   begin
      Status :=
        C_Setxattr
          (C_Path, C_Name, Buffer'Address,
           Interfaces.C.size_t (Value'Length), 0);
      Interfaces.C.Strings.Free (C_Path);
      Interfaces.C.Strings.Free (C_Name);
      return Status = 0;
   exception
      when others =>
         return False;
   end Set_Extended_Attribute;

   function Create_FIFO (Path : String; Mode : Natural) return Boolean is
      function C_Mkfifo
        (Path : Interfaces.C.Strings.chars_ptr;
         Mode : Interfaces.C.unsigned) return Interfaces.C.int
        with Import => True, Convention => C, External_Name => "mkfifo";

      C_Path : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Path);
      Status : Interfaces.C.int;
   begin
      Status := C_Mkfifo (C_Path, Interfaces.C.unsigned (Mode));
      Interfaces.C.Strings.Free (C_Path);
      return Status = 0;
   exception
      when others =>
         return False;
   end Create_FIFO;

   function Create_Socket (Path : String; Mode : Natural) return Boolean is
      function C_Socket (Domain, Kind, Protocol : C_Int) return C_Int
        with Import => True, Convention => C, External_Name => "socket";

      function C_Bind (FD : C_Int; Addr : System.Address; Len : C_Int) return C_Int
        with Import => True, Convention => C, External_Name => "bind";

      function C_Close (FD : C_Int) return C_Int
        with Import => True, Convention => C, External_Name => "close";

      function C_Chmod (Path : Interfaces.C.Strings.chars_ptr; Mode : Interfaces.C.int)
        return Interfaces.C.int
        with Import => True, Convention => C, External_Name => "chmod";

      FD     : C_Int;
      Addr   : aliased Sockaddr_Un;
      C_Path : Interfaces.C.Strings.chars_ptr;
      Status : C_Int;
   begin
      if Path'Length = 0 or else Path'Length > 107 then
         return False;
      end if;

      FD := C_Socket (AF_UNIX, SOCK_STREAM, 0);
      if FD < 0 then
         return False;
      end if;

      Addr.Family := Interfaces.C.short (AF_UNIX);
      for I in Path'Range loop
         Addr.Path (Interfaces.C.size_t (I - Path'First)) :=
           Interfaces.C.To_C (Path (I));
      end loop;

      Status := C_Bind (FD, Addr'Address, Sockaddr_Un'Size / 8);
      declare
         Ignored : constant C_Int := C_Close (FD);
      begin
         pragma Unreferenced (Ignored);
      end;

      if Status /= 0 then
         return False;
      end if;

      C_Path := Interfaces.C.Strings.New_String (Path);
      Status := C_Chmod (C_Path, Interfaces.C.int (Mode));
      Interfaces.C.Strings.Free (C_Path);
      return Status = 0;
   exception
      when others =>
         return False;
   end Create_Socket;

   function Create_Device
     (Path   : String;
      Kind   : Device_Kind;
      Device : Interfaces.Unsigned_64;
      Mode   : Natural) return Boolean
   is
      function C_Mknod
        (Path : Interfaces.C.Strings.chars_ptr;
         Mode : Interfaces.C.unsigned;
         Dev  : Interfaces.C.unsigned_long) return Interfaces.C.int
        with Import => True, Convention => C, External_Name => "mknod";

      S_IFCHR : constant Interfaces.C.unsigned := 8#020000#;
      S_IFBLK : constant Interfaces.C.unsigned := 8#060000#;

      C_Path : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Path);
      Full   : constant Interfaces.C.unsigned :=
        (if Kind = Character_Device then S_IFCHR else S_IFBLK)
        or Interfaces.C.unsigned (Mode);
      Status : Interfaces.C.int;
   begin
      Status :=
        C_Mknod (C_Path, Full, Interfaces.C.unsigned_long (Device));
      Interfaces.C.Strings.Free (C_Path);
      return Status = 0;
   exception
      when others =>
         return False;
   end Create_Device;

   function Create_Hard_Link (Target : String; Link_Path : String) return Boolean is
      function C_Link
        (Old_Path : Interfaces.C.Strings.chars_ptr;
         New_Path : Interfaces.C.Strings.chars_ptr) return Interfaces.C.int
        with Import => True, Convention => C, External_Name => "link";

      C_Target : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Target);
      C_Link_P : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Link_Path);
      Status   : Interfaces.C.int;
   begin
      Status := C_Link (C_Target, C_Link_P);
      Interfaces.C.Strings.Free (C_Target);
      Interfaces.C.Strings.Free (C_Link_P);
      return Status = 0;
   exception
      when others =>
         return False;
   end Create_Hard_Link;

   function Make_Private (Path : String) return Boolean is
      use type Ada.Directories.File_Kind;

      function C_Chmod (Path : Interfaces.C.Strings.chars_ptr; Mode : Interfaces.C.int)
        return Interfaces.C.int
        with Import => True, Convention => C, External_Name => "chmod";

      C_Path : Interfaces.C.Strings.chars_ptr;
      Result : Interfaces.C.int;
      Mode   : Interfaces.C.int;
   begin
      if not Ada.Directories.Exists (Path) then
         return False;
      end if;

      case Ada.Directories.Kind (Path) is
         when Ada.Directories.Ordinary_File =>
            Mode := 8#600#;
         when Ada.Directories.Directory =>
            --  A directory the owner cannot enter is not private, it is unusable.
            Mode := 8#700#;
         when others =>
            return False;
      end case;

      C_Path := Interfaces.C.Strings.New_String (Path);
      Result := C_Chmod (C_Path, Mode);
      Interfaces.C.Strings.Free (C_Path);
      return Result = 0;
   exception
      when others =>
         return False;
   end Make_Private;

   --  POSIX rename replaces an existing Target atomically, which is exactly what the
   --  lock-file-then-rename write wants and what Windows rename cannot do.
   function Replace_File
     (Source : String;
      Target : String)
      return Boolean
   is
      function C_Rename
        (Old_Path : Interfaces.C.Strings.chars_ptr;
         New_Path : Interfaces.C.Strings.chars_ptr)
         return Interfaces.C.int
        with Import => True, Convention => C, External_Name => "rename";

      C_Source : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Source);
      C_Target : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Target);
      Status   : Interfaces.C.int;
   begin
      Status := C_Rename (C_Source, C_Target);
      Interfaces.C.Strings.Free (C_Source);
      Interfaces.C.Strings.Free (C_Target);
      return Status = 0;
   exception
      when others =>
         return False;
   end Replace_File;

   --  POSIX readlink: read the link's own target, not the resolved path.
   function Read_Link_Target
     (Path   : String;
      Target : out Ada.Strings.Unbounded.Unbounded_String)
      return Boolean
   is
      use type Interfaces.C.long;

      function C_Readlink
        (Path : Interfaces.C.Strings.chars_ptr;
         Buf  : System.Address;
         Size : Interfaces.C.size_t)
         return Interfaces.C.long
        with Import => True, Convention => C, External_Name => "readlink";

      C_Path : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Path);
      Buffer : Interfaces.C.char_array (0 .. 4095);
      Count  : Interfaces.C.long;
   begin
      Target := Ada.Strings.Unbounded.Null_Unbounded_String;
      Count := C_Readlink (C_Path, Buffer'Address, 4096);
      Interfaces.C.Strings.Free (C_Path);
      if Count <= 0 then
         return False;
      end if;
      declare
         Result : String (1 .. Natural (Count));
      begin
         for Index in Result'Range loop
            Result (Index) :=
              Character'Val
                (Interfaces.C.char'Pos
                   (Buffer (Interfaces.C.size_t (Index - 1))));
         end loop;
         Target := Ada.Strings.Unbounded.To_Unbounded_String (Result);
      end;
      return True;
   exception
      when others =>
         return False;
   end Read_Link_Target;

   --  POSIX unlink removes the link and never follows one, and a link to a directory is
   --  a link here rather than a directory -- so one call covers both. The Is_Link guard
   --  is what keeps this from removing an ordinary file that happens to be named.
   function Delete_Link (Path : String) return Boolean is
      function C_Unlink (Path : Interfaces.C.Strings.chars_ptr) return Interfaces.C.int
        with Import => True, Convention => C, External_Name => "unlink";
   begin
      if not Is_Link (Path) then
         return False;
      end if;

      declare
         C_Path : Interfaces.C.Strings.chars_ptr :=
           Interfaces.C.Strings.New_String (Path);
         Status : constant Interfaces.C.int := C_Unlink (C_Path);
      begin
         Interfaces.C.Strings.Free (C_Path);
         return Status = 0;
      end;
   exception
      when others =>
         return False;
   end Delete_Link;

   --  POSIX realpath: resolve every symbolic link in Path and collapse "." and "..",
   --  returning the canonical absolute path. This is what Ada.Directories.Full_Name
   --  already did on POSIX; naming it here keeps callers off the Windows-lexical Full_Name.
   function Real_Path (Path : String) return String is
      use type System.Address;

      function C_Realpath
        (Path     : Interfaces.C.Strings.chars_ptr;
         Resolved : System.Address)
         return System.Address
        with Import => True, Convention => C, External_Name => "realpath";

      C_Path : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Path);
      Buffer : Interfaces.C.char_array (0 .. 4095) := [others => Interfaces.C.nul];
      Result : System.Address;
   begin
      Result := C_Realpath (C_Path, Buffer'Address);
      Interfaces.C.Strings.Free (C_Path);
      if Result = System.Null_Address then
         return "";
      end if;
      return Interfaces.C.To_Ada (Buffer, Trim_Nul => True);
   exception
      when others =>
         return "";
   end Real_Path;

   --  Shared by the three questions below: the directory part of a path.
   function Directory_Part (Path : String) return String is
   begin
      for Index in reverse Path'Range loop
         if Path (Index) = '/' then
            return (if Index = Path'First then "/" else Path (Path'First .. Index - 1));
         end if;
      end loop;
      return "";
   end Directory_Part;

   function Own_Executable return String is
      Link   : constant String := "/proc/self/exe";
      Target : Ada.Strings.Unbounded.Unbounded_String;
   begin
      --  The kernel's own answer, and it is the resolved path already.
      if not Read_Link_Target (Link, Target) then
         return "";
      end if;
      return Ada.Strings.Unbounded.To_String (Target);
   exception
      when others =>
         return "";
   end Own_Executable;

   function Own_Executable_Directory return String is
      Own : constant String := Own_Executable;
   begin
      return (if Own = "" then "" else Directory_Part (Own));
   end Own_Executable_Directory;

   --  HOME first, because a user who exports it means it. The password file is
   --  what the host itself records, and is there when HOME is not.
   function Home_Directory return String is
      function Getuid return Interfaces.C.unsigned
        with Import => True, Convention => C, External_Name => "getuid";

      type Passwd is record
         Name   : Interfaces.C.Strings.chars_ptr;
         Passwd : Interfaces.C.Strings.chars_ptr;
         Uid    : Interfaces.C.unsigned;
         Gid    : Interfaces.C.unsigned;
         Gecos  : Interfaces.C.Strings.chars_ptr;
         Dir    : Interfaces.C.Strings.chars_ptr;
         Shell  : Interfaces.C.Strings.chars_ptr;
      end record
        with Convention => C;
      type Passwd_Access is access all Passwd;

      function Getpwuid (Uid : Interfaces.C.unsigned) return Passwd_Access
        with Import => True, Convention => C, External_Name => "getpwuid";

      use type Interfaces.C.Strings.chars_ptr;
      Entry_Item : Passwd_Access;
   begin
      if Ada.Environment_Variables.Exists ("HOME")
        and then Ada.Environment_Variables.Value ("HOME") /= ""
      then
         return Ada.Environment_Variables.Value ("HOME");
      end if;

      Entry_Item := Getpwuid (Getuid);
      if Entry_Item = null or else Entry_Item.Dir = Interfaces.C.Strings.Null_Ptr then
         return "";
      end if;

      return Interfaces.C.Strings.Value (Entry_Item.Dir);
   exception
      when others =>
         return "";
   end Home_Directory;

   function Application_Data_Directory return String is
      Home : constant String := Home_Directory;
   begin
      if Ada.Environment_Variables.Exists ("XDG_DATA_HOME")
        and then Ada.Environment_Variables.Value ("XDG_DATA_HOME") /= ""
      then
         return Ada.Environment_Variables.Value ("XDG_DATA_HOME");
      end if;
      return (if Home = "" then "" else Home & "/.local/share");
   end Application_Data_Directory;

   function Cache_Directory return String is
      Home : constant String := Home_Directory;
   begin
      if Ada.Environment_Variables.Exists ("XDG_CACHE_HOME")
        and then Ada.Environment_Variables.Value ("XDG_CACHE_HOME") /= ""
      then
         return Ada.Environment_Variables.Value ("XDG_CACHE_HOME");
      end if;
      return (if Home = "" then "" else Home & "/.cache");
   end Cache_Directory;

   function Config_Directory return String is
      Home : constant String := Home_Directory;
   begin
      if Ada.Environment_Variables.Exists ("XDG_CONFIG_HOME")
        and then Ada.Environment_Variables.Value ("XDG_CONFIG_HOME") /= ""
      then
         return Ada.Environment_Variables.Value ("XDG_CONFIG_HOME");
      end if;
      return (if Home = "" then "" else Home & "/.config");
   end Config_Directory;

   function Temp_Directory return String is
   begin
      if Ada.Environment_Variables.Exists ("TMPDIR")
        and then Ada.Environment_Variables.Value ("TMPDIR") /= ""
      then
         return Ada.Environment_Variables.Value ("TMPDIR");
      end if;
      return "/tmp";
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
            Candidate : constant String :=
              Ada.Directories.Compose
                (Containing_Directory => Base,
                 Name => Safe_Prefix & "-" & Time_Image & "-" & Image (Attempt));
         begin
            Ada.Directories.Create_Directory (Candidate);
            return Candidate;
         exception
            when Ada.Directories.Name_Error | Ada.Directories.Use_Error =>
               null;
         end;
      end loop;
      return "";
   end Create_Temporary_Directory;

   function Uses_Dos_Filename_Rules (Path : String) return Boolean is
      use Ada.Strings.Unbounded;
      File    : Ada.Text_IO.File_Type;
      Content : Unbounded_String;
   begin
      declare
         Absolute : constant String := Ada.Directories.Full_Name (Path);
      begin
         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, "/proc/self/mountinfo");
         while not Ada.Text_IO.End_Of_File (File) loop
            Append (Content, Ada.Text_IO.Get_Line (File));
            Append (Content, Ada.Characters.Latin_1.LF);
         end loop;
         Ada.Text_IO.Close (File);

         return Hostkit.Filesystem_Rules.Dos_By_Type_Name
           (Hostkit.Filesystem_Rules.Filesystem_Type_For_Mount
              (To_String (Content), Absolute));
      end;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         return False;
   end Uses_Dos_Filename_Rules;

   ---------------
   -- Separator --
   ---------------

   function Separator return Character is ('/');

   ---------------------------
   -- Search_Path_Delimiter --
   ---------------------------

   function Search_Path_Delimiter return Character is
   begin
      return ':';
   end Search_Path_Delimiter;

   ------------------------
   -- Executable_Suffix --
   ------------------------

   function Executable_Suffix return String is
   begin
      return "";
   end Executable_Suffix;

   -----------------------
   -- Starts_When_Named --
   -----------------------

   --  The same question as Is_Executable here: a file the kernel will start is
   --  one with the bit set, and what it does with a `#!` line is its own
   --  business rather than the caller's.
   function Starts_When_Named (Path : String) return Boolean
   is (Is_Executable (Path));

   ------------------
   -- Null_Device --
   ------------------

   function Null_Device return String is
   begin
      --  A character device every POSIX host has, in the place every POSIX
      --  host keeps it.
      return "/dev/null";
   end Null_Device;

end Hostkit.Fs;
