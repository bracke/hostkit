with Ada.IO_Exceptions;
with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Fixed;
with Ada.Environment_Variables;
with System;

with GNAT.OS_Lib;

with Interfaces.C.Strings;
with Interfaces.C_Streams;
with Hostkit.Darwin_Symbols;
with Hostkit.Fs.Instants;

package body Hostkit.Fs is
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned;
   use type Interfaces.C.unsigned_long;
   use type Interfaces.C.unsigned_short;

   subtype C_Int is Interfaces.C.int;
   subtype C_U16 is Interfaces.C.unsigned_short;
   subtype C_U32 is Interfaces.C.unsigned;
   subtype C_S32 is Interfaces.C.int;
   subtype C_S64 is Interfaces.C.long;

   type Timespec is record
      Seconds     : C_S64 := 0;
      Nanoseconds : C_S64 := 0;
   end record
     with Convention => C;

   type Spare_Array is array (1 .. 2) of C_S64
     with Convention => C;

   type Stat_Record is record
      Device        : C_S32 := 0;
      Mode          : C_U16 := 0;
      Link_Count    : C_U16 := 0;
      Inode         : Interfaces.C.unsigned_long := 0;
      User_Id       : C_U32 := 0;
      Group_Id      : C_U32 := 0;
      Raw_Device    : C_S32 := 0;
      Padding       : C_S32 := 0;
      Access_Time   : Timespec;
      Modified_Time : Timespec;
      Change_Time   : Timespec;
      Birth_Time    : Timespec;
      Size          : C_S64 := 0;
      Blocks        : C_S64 := 0;
      Block_Size    : C_S32 := 0;
      Flags         : C_U32 := 0;
      Generation    : C_U32 := 0;
      Long_Spare    : C_S32 := 0;
      Quad_Spare    : Spare_Array := [others => 0];
   end record
     with Convention => C;

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
   function Is_Hidden (Path : String) return Boolean is
      use type Interfaces.Unsigned_32;
      type Timespec is record
         Seconds     : Interfaces.Integer_64 := 0;
         Nanoseconds : Interfaces.Integer_64 := 0;
      end record with Convention => C;
      type Spare_Array is array (1 .. 2) of Interfaces.Integer_64 with Convention => C;
      --  Darwin struct stat with 64-bit inodes, as Hostkit.Private_Paths reads it.
      type Stat_Record is record
         Device        : Interfaces.Integer_32 := 0;
         Mode          : Interfaces.Unsigned_16 := 0;
         Link_Count    : Interfaces.Unsigned_16 := 0;
         Inode         : Interfaces.Unsigned_64 := 0;
         User_Id       : Interfaces.Unsigned_32 := 0;
         Group_Id      : Interfaces.Unsigned_32 := 0;
         Raw_Device    : Interfaces.Integer_32 := 0;
         Padding       : Interfaces.Integer_32 := 0;
         Access_Time   : Timespec;
         Modified_Time : Timespec;
         Change_Time   : Timespec;
         Birth_Time    : Timespec;
         Size          : Interfaces.Integer_64 := 0;
         Blocks        : Interfaces.Integer_64 := 0;
         Block_Size    : Interfaces.Integer_32 := 0;
         Flags         : Interfaces.Unsigned_32 := 0;
         Generation    : Interfaces.Unsigned_32 := 0;
         Long_Spare    : Interfaces.Integer_32 := 0;
         Quad_Spare    : Spare_Array := [others => 0];
      end record with Convention => C;
      pragma Compile_Time_Error (Stat_Record'Size /= 144 * 8, "Darwin struct stat must be 144 bytes");

      function C_Lstat
        (Name : Interfaces.C.Strings.chars_ptr; Buffer : access Stat_Record) return Interfaces.C.int
        with Import, Convention => C, External_Name => Hostkit.Darwin_Symbols.Lstat;

      Uf_Hidden : constant Interfaces.Unsigned_32 := 16#0000_8000#;
      C_Path    : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      Info      : aliased Stat_Record;
      Status    : constant Interfaces.C.int := C_Lstat (C_Path, Info'Access);
   begin
      Interfaces.C.Strings.Free (C_Path);
      return Status = 0 and then (Info.Flags and Uf_Hidden) /= 0;
   exception
      when others =>
         return False;
   end Is_Hidden;

   function Kind_Of (Path : String) return Entry_Kind is
   begin
      if Path = "" or else not Ada.Directories.Exists (Path) then
         return Missing_Entry;
      end if;
      case Ada.Directories.Kind (Path) is
         when Ada.Directories.Directory =>
            return Directory_Entry;
         when Ada.Directories.Ordinary_File =>
            return Ordinary_File_Entry;
         when Ada.Directories.Special_File =>
            return Special_File_Entry;
      end case;
   exception
      when others =>
         return Missing_Entry;
   end Kind_Of;

   --  stat and lstat, by the names this architecture links them under
   --  (Hostkit.Darwin_Symbols): neither is variadic, so arm64 passes their
   --  arguments as declared.
   function Darwin_Stat (Name : Interfaces.C.Strings.chars_ptr; Buffer : access Stat_Record) return C_Int
     with Import, Convention => C, External_Name => Hostkit.Darwin_Symbols.Stat;
   function Darwin_Lstat (Name : Interfaces.C.Strings.chars_ptr; Buffer : access Stat_Record) return C_Int
     with Import, Convention => C, External_Name => Hostkit.Darwin_Symbols.Lstat;

   S_IFREG : constant C_U16 := 8#100000#;
   S_IFDIR : constant C_U16 := 8#040000#;
   S_IFLNK : constant C_U16 := 8#120000#;

   --  stat(2), or lstat(2) for a final link not followed, of Path; the
   --  failures as the spec's Name_Error and Use_Error. ENOENT, ENOTDIR, ELOOP
   --  and ENAMETOOLONG say nothing is reachable there; anything else (EACCES
   --  on a folder on the way, EIO) that the host would not say.
   function Stat_Entry (Path : String; Follow_Links : Boolean) return Stat_Record is
      E_Noent       : constant := 2;
      E_Notdir      : constant := 20;
      E_Loop        : constant := 62;
      E_Nametoolong : constant := 63;
      Info          : aliased Stat_Record;
      C_Path        : Interfaces.C.Strings.chars_ptr;
      Status        : C_Int;
      Error         : Integer;
   begin
      if Path = "" or else (for some C of Path => C = ASCII.NUL) then
         raise Ada.Directories.Name_Error with "no entry at """ & Path & """";
      end if;
      C_Path := Interfaces.C.Strings.New_String (Path);
      Status := (if Follow_Links then Darwin_Stat (C_Path, Info'Access) else Darwin_Lstat (C_Path, Info'Access));
      Error := GNAT.OS_Lib.Errno;
      Interfaces.C.Strings.Free (C_Path);
      if Status /= 0 then
         if Error in E_Noent | E_Notdir | E_Nametoolong | E_Loop then
            raise Ada.Directories.Name_Error with Path & ": " & GNAT.OS_Lib.Errno_Message (Err => Error);
         end if;
         raise Ada.Directories.Use_Error with Path & ": " & GNAT.OS_Lib.Errno_Message (Err => Error);
      end if;
      return Info;
   end Stat_Entry;

   function Size_Of (Path : String; Follow_Links : Boolean := True) return Ada.Directories.File_Size is
      Info : constant Stat_Record := Stat_Entry (Path, Follow_Links);
      Kind : constant C_U16 := Info.Mode and File_Type_Mask;
   begin
      if Kind /= S_IFREG and then (Follow_Links or else Kind /= S_IFLNK) then
         raise Ada.Directories.Name_Error with Path & ": no ordinary file";
      end if;
      return Ada.Directories.File_Size (Info.Size);
   end Size_Of;

   function Modification_Time_Of (Path : String; Follow_Links : Boolean := True) return Ada.Calendar.Time is
      Info : constant Stat_Record := Stat_Entry (Path, Follow_Links);
      Kind : constant C_U16 := Info.Mode and File_Type_Mask;
   begin
      if Kind /= S_IFREG and then Kind /= S_IFDIR and then (Follow_Links or else Kind /= S_IFLNK) then
         raise Ada.Directories.Name_Error with Path & ": no file or directory";
      end if;
      return Hostkit.Fs.Instants.From_Unix
        (Interfaces.Integer_64 (Info.Modified_Time.Seconds), Interfaces.Integer_64 (Info.Modified_Time.Nanoseconds));
   end Modification_Time_Of;

   --  The owner's bit of the mode, as GNAT's __gnat_stat_to_attr reads it
   --  (S_IRUSR, S_IWUSR of a stat that follows a link).
   function Owner_Bit (Path : String; Bit : C_U16) return Boolean is
   begin
      return (Stat_Entry (Path, True).Mode and Bit) /= 0;
   exception
      when Ada.Directories.Name_Error | Ada.Directories.Use_Error =>
         return False;
   end Owner_Bit;

   function Is_Owner_Readable (Path : String) return Boolean is (Owner_Bit (Path, 8#400#));

   function Is_Owner_Writable (Path : String) return Boolean is (Owner_Bit (Path, 8#200#));

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

   function Special_File_Info_Of (Path : String) return Special_File_Info is
      function C_Stat
        (Path : Interfaces.C.Strings.chars_ptr;
         Buf  : access Stat_Record)
         return Interfaces.C.int
        with Import => True, Convention => C, External_Name => Hostkit.Darwin_Symbols.Stat;

      C_Path : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      Info   : aliased Stat_Record;
      Status : C_Int;
      Mode   : C_U16;
   begin
      Status := C_Stat (C_Path, Info'Access);
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
            Device    => Interfaces.Unsigned_64 (Info.Raw_Device),
            Mode      => Natural (Info.Mode and Permission_Mask));
      elsif Mode = S_IFBLK then
         return
           (Available => True,
            Kind      => Special_File_Kind'(Block_Device),
            Device    => Interfaces.Unsigned_64 (Info.Raw_Device),
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
   --  rather than reconstructing the whole field. Want keeps the two callers apart: a
   --  file's bits and a directory's do not mean the same thing, so neither answers for
   --  the other.
   function Exposed (Path : String; Want : Ada.Directories.File_Kind) return Boolean is
      use type Interfaces.Unsigned_8;
      use type Ada.Directories.File_Kind;

      --  struct stat is larger than this; stat writes only into what it needs and the mode
      --  sits near the front. Oversized so there is always room.
      Buffer : array (0 .. 255) of aliased Interfaces.Unsigned_8 := [others => 0];

      function C_Stat (Path : Interfaces.C.Strings.chars_ptr; Buf : System.Address)
        return Interfaces.C.int
        with Import => True, Convention => C, External_Name => Hostkit.Darwin_Symbols.Stat;

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
      --  struct is 4 on this platform's LP64 layout.
      return (Buffer (4) and 8#077#) /= 0;
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

   --  The host refuses an existing target in the same atomic move.
   function Move_No_Replace
     (Source : String;
      Target : String)
      return Boolean
   is (Move_No_Replace_Outcome (Source, Target) = Moved);

   --  Errno values the fallback below tells apart.
   Fallback_Eperm      : constant := 1;
   Fallback_Exdev      : constant := 18;
   Fallback_Emlink     : constant := 31;
   Fallback_Enotsup    : constant := 45;
   Fallback_Enosys     : constant := 78;
   Fallback_Eopnotsupp : constant := 102;

   --  link() follows a symbolic link at From on Darwin; linkat with no
   --  flags links the entry itself, as link() does on Linux, so a moved
   --  link stays a link.
   Fallback_At_Fdcwd : constant := -2;
   function C_Linkat
     (From_Dir : Interfaces.C.int; From : Interfaces.C.Strings.chars_ptr;
      To_Dir   : Interfaces.C.int; To   : Interfaces.C.Strings.chars_ptr;
      Flags    : Interfaces.C.int) return Interfaces.C.int
     with Import => True, Convention => C, External_Name => "linkat";
   function C_Unlink (Path : Interfaces.C.Strings.chars_ptr) return Interfaces.C.int
     with Import => True, Convention => C, External_Name => "unlink";
   function C_Plain_Rename (From, To : Interfaces.C.Strings.chars_ptr) return Interfaces.C.int
     with Import => True, Convention => C, External_Name => "rename";
   function C_Readlink
     (Path : Interfaces.C.Strings.chars_ptr; Buffer : out Interfaces.C.char_array; Size : Interfaces.C.size_t)
      return Interfaces.C.long
     with Import => True, Convention => C, External_Name => "readlink";
   function C_Access (Path : Interfaces.C.Strings.chars_ptr; Mode : Interfaces.C.int) return Interfaces.C.int
     with Import => True, Convention => C, External_Name => "access";

   --  Whether anything, a dangling link included, is at Path.
   function Present (Path : Interfaces.C.Strings.chars_ptr) return Boolean is
      use type Interfaces.C.long;
      Buffer : Interfaces.C.char_array (1 .. 1);
   begin
      return C_Readlink (Path, Buffer, 1) >= 0 or else C_Access (Path, 0) = 0;
   end Present;

   --  A filesystem without RENAME_EXCL (SMB, NFS, FUSE mounts): a
   --  non-directory moves by link and unlink, which never replaces. A
   --  directory, or a filesystem without hard links, falls back to a
   --  rename after checking the target is free -- what mv -n does there;
   --  only an entry created in between could be replaced.
   function Without_Native_No_Replace (From, To : Interfaces.C.Strings.chars_ptr) return Move_Outcome is
      Error : Integer;
   begin
      if C_Linkat (Fallback_At_Fdcwd, From, Fallback_At_Fdcwd, To, 0) = 0 then
         if C_Unlink (From) = 0 then
            return Moved;
         end if;
         if C_Unlink (To) /= 0 then
            null;
         end if;
         return Move_Refused;
      end if;
      Error := GNAT.OS_Lib.Errno;
      if Error = Fallback_Exdev then
         return Move_Cross_Device;
      elsif Error not in
        Fallback_Eperm | Fallback_Emlink | Fallback_Enotsup | Fallback_Enosys | Fallback_Eopnotsupp
      then
         --  The target is taken, or the move is refused for good.
         return Move_Refused;
      end if;
      if Present (To) then
         return Move_Refused;
      elsif C_Plain_Rename (From, To) = 0 then
         return Moved;
      elsif GNAT.OS_Lib.Errno = Fallback_Exdev then
         return Move_Cross_Device;
      end if;
      return Move_Refused;
   end Without_Native_No_Replace;

   function Move_Without_Native_No_Replace (Source : String; Target : String) return Move_Outcome is
      C_Source : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Source);
      C_Target : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Target);
      Outcome  : constant Move_Outcome := Without_Native_No_Replace (C_Source, C_Target);
   begin
      Interfaces.C.Strings.Free (C_Source);
      Interfaces.C.Strings.Free (C_Target);
      return Outcome;
   end Move_Without_Native_No_Replace;

   function Move_No_Replace_Outcome
     (Source : String;
      Target : String)
      return Move_Outcome
   is
      function C_Renamex
        (Old_Path : Interfaces.C.Strings.chars_ptr;
         New_Path : Interfaces.C.Strings.chars_ptr;
         Flags    : Interfaces.C.unsigned)
         return Interfaces.C.int
        with Import => True, Convention => C, External_Name => "renamex_np";

      Rename_Excl : constant := 4;
      Exdev       : constant := 18;
      Einval      : constant := 22;
      Enotsup     : constant := 45;
      Enosys      : constant := 78;

      function C_Rename (From, To : Interfaces.C.Strings.chars_ptr) return Interfaces.C.int is
        (C_Renamex (From, To, Rename_Excl));

      C_Source : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Source);
      C_Target : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Target);
      Status   : Interfaces.C.int;
      Error    : Integer;
   begin
      Status := C_Rename (C_Source, C_Target);
      Error := GNAT.OS_Lib.Errno;
      if Status /= 0 and then (Error = Einval or else Error = Enotsup or else Error = Enosys) then
         --  The filesystem lacks the no-replace rename itself.
         declare
            Outcome : constant Move_Outcome := Without_Native_No_Replace (C_Source, C_Target);
         begin
            Interfaces.C.Strings.Free (C_Source);
            Interfaces.C.Strings.Free (C_Target);
            return Outcome;
         end;
      end if;
      Interfaces.C.Strings.Free (C_Source);
      Interfaces.C.Strings.Free (C_Target);
      if Status = 0 then
         return Moved;
      elsif Error = Exdev then
         return Move_Cross_Device;
      end if;
      return Move_Refused;
   exception
      when others =>
         return Move_Refused;
   end Move_No_Replace_Outcome;

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

   function Delete_Tree_No_Follow (Path : String) return Delete_Tree_Outcome is
      use Ada.Strings.Unbounded;
      use type Interfaces.C.Strings.chars_ptr;
      use type System.Address;

      Max_Depth : constant := 2_048;
      Max_Entries : constant := 100_000;
      Max_Name_Bytes : constant := 64 * 1_024 * 1_024;
      O_Rdonly : constant C_Int := 0;
      O_Nofollow : constant C_Int := 16#100#;
      O_Directory : constant C_Int := 16#0010_0000#;
      O_Cloexec : constant C_Int := 16#0100_0000#;
      At_Symlink_Nofollow : constant C_Int := 16#20#;
      At_Removedir : constant C_Int := 16#80#;
      Directory_Type : constant C_U16 := 8#040000#;
      E_Xdev : constant C_Int := 18;

      type Dirent is record
         Inode, Seek_Offset : Interfaces.C.unsigned_long;
         Record_Length, Name_Length : C_U16;
         Kind : Interfaces.C.unsigned_char;
         Name : Interfaces.C.char_array (0 .. 1_023);
      end record with Convention => C;
      --  'Size omits the tail padding C's sizeof includes; 'Object_Size is the
      --  storage each array element takes, which is what sizeof means.
      pragma Compile_Time_Error
        (Dirent'Object_Size /= 1_048 * 8, "Darwin dirent must be 1048 bytes");

      type Identity is record
         Device : C_S32 := 0;
         Inode : Interfaces.C.unsigned_long := 0;
         Mode : C_U16 := 0;
         Available : Boolean := False;
      end record;
      package Name_Vectors is new Ada.Containers.Indefinite_Vectors
        (Index_Type => Positive, Element_Type => String);

      function C_Open (Name : Interfaces.C.Strings.chars_ptr; Flags : C_Int) return C_Int
        with Import, Convention => C, External_Name => "open";
      function C_Openat
        (Fd : C_Int; Name : Interfaces.C.Strings.chars_ptr; Flags : C_Int) return C_Int
        with Import, Convention => C, External_Name => "openat";
      function C_Close (Fd : C_Int) return C_Int
        with Import, Convention => C, External_Name => "close";
      function C_Dup (Fd : C_Int) return C_Int
        with Import, Convention => C, External_Name => "dup";
      function C_Fdopendir (Fd : C_Int) return System.Address
        with Import, Convention => C, External_Name => Hostkit.Darwin_Symbols.Fdopendir;
      function C_Readdir (Directory : System.Address) return System.Address
        with Import, Convention => C, External_Name => Hostkit.Darwin_Symbols.Readdir;
      function C_Closedir (Directory : System.Address) return C_Int
        with Import, Convention => C, External_Name => "closedir";
      function C_Fstat (Fd : C_Int; Info : access Stat_Record) return C_Int
        with Import, Convention => C, External_Name => Hostkit.Darwin_Symbols.Fstat;
      function C_Fstatat
        (Fd : C_Int; Name : Interfaces.C.Strings.chars_ptr;
         Info : access Stat_Record; Flags : C_Int) return C_Int
        with Import, Convention => C, External_Name => Hostkit.Darwin_Symbols.Fstatat;
      function C_Unlinkat
        (Fd : C_Int; Name : Interfaces.C.Strings.chars_ptr; Flags : C_Int) return C_Int
        with Import, Convention => C, External_Name => "unlinkat";
      function Errno_Location return System.Address
        with Import, Convention => C, External_Name => "__error";

      function Errno return C_Int is
         Value : C_Int with Import, Address => Errno_Location;
      begin
         return Value;
      end Errno;
      procedure Set_Errno (Code : C_Int) is
         Value : C_Int with Import, Address => Errno_Location;
      begin
         Value := Code;
      end Set_Errno;
      procedure Clear_Errno is
      begin
         Set_Errno (0);
      end Clear_Errno;
      procedure Close (Fd : in out C_Int) is
         Ignored : C_Int;
      begin
         if Fd >= 0 then
            Ignored := C_Close (Fd);
            Fd := -1;
         end if;
      end Close;
      procedure Free (Item : in out Interfaces.C.Strings.chars_ptr) is
      begin
         if Item /= Interfaces.C.Strings.Null_Ptr then
            Interfaces.C.Strings.Free (Item);
         end if;
      end Free;
      function To_Identity (Info : Stat_Record; Ok : Boolean) return Identity is
        ((if Ok then (Info.Device, Info.Inode, Info.Mode, True) else (others => <>)));
      function Info_Of (Fd : C_Int) return Identity is
         Info : aliased Stat_Record;
         Ok : Boolean;
      begin
         Ok := Fd >= 0 and then C_Fstat (Fd, Info'Access) = 0;
         return To_Identity (Info, Ok);
      end Info_Of;
      --  The entry Name in Fd, not followed. Nothing is asked of a
      --  descriptor an open did not give.
      function Info_At (Fd : C_Int; Name : String) return Identity is
         C_Name : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.Null_Ptr;
         Info : aliased Stat_Record;
         Ok : Boolean;
      begin
         if Fd < 0 then
            return (others => <>);
         end if;
         C_Name := Interfaces.C.Strings.New_String (Name);
         Ok := C_Fstatat (Fd, C_Name, Info'Access, At_Symlink_Nofollow) = 0;
         Free (C_Name);
         return To_Identity (Info, Ok);
      exception
         when others =>
            Free (C_Name);
            return (others => <>);
      end Info_At;
      function Same (Left, Right : Identity) return Boolean is
        (Left.Available and then Right.Available and then Left.Device = Right.Device
         and then Left.Inode = Right.Inode);
      function Is_Directory (Item : Identity) return Boolean is
        (Item.Available and then (Item.Mode and File_Type_Mask) = Directory_Type);
      --  Whether Child, seen in the held folder Parent, is on another device.
      --  The walk stops there with EXDEV: a filesystem mounted inside the
      --  tree is not the tree's to empty, nor its mount point to remove.
      function Crosses_Mount (Parent, Child : Identity) return Boolean is
        (Parent.Device /= Child.Device);

      function C_Lseek (Fd : C_Int; Offset : Interfaces.C.long; Whence : C_Int) return Interfaces.C.long
        with Import, Convention => C, External_Name => "lseek";

      --  Read Held's names from its start. Full is True when Max_Entries
      --  names were read and more may follow: the caller deletes those, then
      --  reads again, so a folder of any size is deleted in batches.
      function Read_Names
        (Held : C_Int; Names : in out Name_Vectors.Vector; Full : out Boolean) return Boolean
      is
         Scan : C_Int;
         Directory : System.Address := System.Null_Address;
         Pointer : System.Address;
         Name_Bytes : Natural := 0;
         Ignored : C_Int;
      begin
         Full := False;
         --  The duplicate shares Held's position: start it over, as the
         --  names read before were deleted.
         if Interfaces.C."<" (C_Lseek (Held, 0, 0), 0) then
            return False;
         end if;
         Scan := C_Dup (Held);
         if Scan < 0 then
            return False;
         end if;
         Directory := C_Fdopendir (Scan);
         if Directory = System.Null_Address then
            Close (Scan);
            return False;
         end if;
         Scan := -1;
         Clear_Errno;
         loop
            Pointer := C_Readdir (Directory);
            exit when Pointer = System.Null_Address;
            declare
               Item : Dirent with Import, Address => Pointer;
               Name : constant String := Interfaces.C.To_Ada (Item.Name);
            begin
               if Name /= "." and then Name /= ".." then
                  if Natural (Names.Length) >= Max_Entries
                    or else Name'Length > Max_Name_Bytes - Name_Bytes
                  then
                     Ignored := C_Closedir (Directory);
                     Full := True;
                     return True;
                  end if;
                  Names.Append (Name);
                  Name_Bytes := Name_Bytes + Name'Length;
               end if;
            end;
            Clear_Errno;
         end loop;
         declare
            Ok : constant Boolean := Errno = 0;
         begin
            Ignored := C_Closedir (Directory);
            return Ok;
         end;
      exception
         when others =>
            if Directory /= System.Null_Address then
               Ignored := C_Closedir (Directory);
            else
               Close (Scan);
            end if;
            return False;
      end Read_Names;

      --  Empty the held folder Held, seen as Held_Info, then remove it from
      --  its parent and hold that parent instead. On a failure Held is
      --  closed and errno says why: each failing call's errno is kept from
      --  before the clean-up, and nothing is asked of a descriptor an open
      --  did not give, which would answer EBADF over the open's EACCES.
      function Delete_Held
        (Held : in out C_Int; Held_Info : Identity; Own_Name : String;
         Expected_Parent : Identity; Depth : Natural) return Boolean
      is
         Names : Name_Vectors.Vector;
         Ok : Boolean;
         Full : Boolean := True;
      begin
         if Depth > Max_Depth then
            Close (Held);
            return False;
         end if;
         while Full loop
            Names.Clear;
            if not Read_Names (Held, Names, Full) then
               declare
                  Error : constant C_Int := Errno;
               begin
                  Close (Held);
                  Set_Errno (Error);
               end;
               return False;
            end if;
            for Name of Names loop
               declare
                  Observed : constant Identity := Info_At (Held, Name);
                  Error : C_Int := (if Observed.Available then 0 else Errno);
                  C_Name : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Name);
                  Child : C_Int := -1;
               begin
                  if not Observed.Available then
                     Ok := False;
                  elsif Crosses_Mount (Held_Info, Observed) then
                     Ok := False;
                     Error := E_Xdev;
                  elsif not Is_Directory (Observed) then
                     Ok := C_Unlinkat (Held, C_Name, 0) = 0;
                     if not Ok then
                        Error := Errno;
                     end if;
                  else
                     Child := C_Openat (Held, C_Name, O_Rdonly + O_Directory + O_Nofollow + O_Cloexec);
                     if Child < 0 then
                        Ok := False;
                        Error := Errno;
                     else
                        declare
                           Child_Info : constant Identity := Info_Of (Child);
                        begin
                           Ok := Is_Directory (Child_Info) and then Same (Observed, Child_Info);
                           if Ok then
                              Close (Held);
                              Ok := Delete_Held (Child, Child_Info, Name, Held_Info, Depth + 1);
                              if not Ok then
                                 Error := Errno;
                              end if;
                              Held := Child;
                              if Ok then
                                 Ok := Same (Held_Info, Info_Of (Held));
                              end if;
                           else
                              Close (Child);
                           end if;
                        end;
                     end if;
                  end if;
                  Free (C_Name);
                  if not Ok then
                     Close (Held);
                     if Error /= 0 then
                        Set_Errno (Error);
                     end if;
                     return False;
                  end if;
               exception
                  when others =>
                     Free (C_Name);
                     Close (Child);
                     Close (Held);
                     return False;
               end;
            end loop;
         end loop;
         declare
            Dotdot : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String ("..");
            Parent : C_Int := C_Openat (Held, Dotdot, O_Rdonly + O_Directory + O_Cloexec);
            Error : C_Int := (if Parent < 0 then Errno else 0);
            Current : constant Identity := Info_At (Parent, Own_Name);
            C_Own : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Own_Name);
         begin
            Free (Dotdot);
            Ok := Parent >= 0 and then Same (Expected_Parent, Info_Of (Parent))
              and then Is_Directory (Current) and then Same (Held_Info, Current);
            Close (Held);
            if Ok then
               Ok := C_Unlinkat (Parent, C_Own, At_Removedir) = 0;
               if not Ok then
                  Error := Errno;
               end if;
            end if;
            Free (C_Own);
            if not Ok then
               Close (Parent);
               if Error /= 0 then
                  Set_Errno (Error);
               end if;
               return False;
            end if;
            Held := Parent;
            return True;
         exception
            when others =>
               Free (Dotdot);
               Free (C_Own);
               Close (Held);
               Close (Parent);
               return False;
         end;
      end Delete_Held;

      --  Delete Name in the held folder Parent, which is closed after. The
      --  tree's own root is held to the same rule as each entry under it: on
      --  another mount than its folder, it is refused with EXDEV.
      function Delete_At (Parent : in out C_Int; Name : String) return Boolean is
         Parent_Info : constant Identity := Info_Of (Parent);
         Observed : constant Identity := Info_At (Parent, Name);
         Error : C_Int := (if Observed.Available and then Parent_Info.Available then 0 else Errno);
         C_Name : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Name);
         Child : C_Int := -1;
         Ok : Boolean;
      begin
         if not Observed.Available or else not Parent_Info.Available then
            Ok := False;
         elsif Crosses_Mount (Parent_Info, Observed) then
            Ok := False;
            Error := E_Xdev;
         elsif not Is_Directory (Observed) then
            Ok := C_Unlinkat (Parent, C_Name, 0) = 0;
            if not Ok then
               Error := Errno;
            end if;
         else
            Child := C_Openat (Parent, C_Name, O_Rdonly + O_Directory + O_Nofollow + O_Cloexec);
            if Child < 0 then
               Ok := False;
               Error := Errno;
            else
               declare
                  Child_Info : constant Identity := Info_Of (Child);
               begin
                  Ok := Is_Directory (Child_Info) and then Same (Observed, Child_Info);
                  if Ok then
                     Close (Parent);
                     Ok := Delete_Held (Child, Child_Info, Name, Parent_Info, 0);
                     if not Ok then
                        Error := Errno;
                     end if;
                     Parent := Child;
                  else
                     Close (Child);
                  end if;
               end;
            end if;
         end if;
         Free (C_Name);
         Close (Parent);
         if not Ok and then Error /= 0 then
            Set_Errno (Error);
         end if;
         return Ok;
      exception
         when others =>
            Free (C_Name);
            Close (Child);
            Close (Parent);
            return False;
      end Delete_At;

      Trimmed : Unbounded_String := To_Unbounded_String (Path);
   begin
      if Path = "" then
         return Tree_Delete_Failed;
      end if;
      while Length (Trimmed) > 1 and then Element (Trimmed, Length (Trimmed)) = '/' loop
         Delete (Trimmed, Length (Trimmed), Length (Trimmed));
      end loop;
      declare
         Value : constant String := To_String (Trimmed);
         Slash : constant Natural := Ada.Strings.Fixed.Index (Value, "/", Ada.Strings.Backward);
         Name : constant String := (if Slash = 0 then Value else Value (Slash + 1 .. Value'Last));
         Parent_Name : constant String :=
           (if Slash = 0 then "." elsif Slash = Value'First then "/" else Value (Value'First .. Slash - 1));
         C_Parent : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Parent_Name);
         Parent : C_Int := -1;
         Ok : Boolean;
      begin
         if Name = "" or else Name = "." or else Name = ".." then
            Free (C_Parent);
            return Tree_Delete_Failed;
         end if;
         Parent := C_Open (C_Parent, O_Rdonly + O_Directory + O_Cloexec);
         Free (C_Parent);
         Ok := Parent >= 0 and then Delete_At (Parent, Name);
         Close (Parent);
         return (if Ok then Tree_Deleted else Tree_Delete_Failed);
      exception
         when others =>
            Free (C_Parent);
            Close (Parent);
            return Tree_Delete_Failed;
      end;
   exception
      when others =>
         return Tree_Delete_Failed;
   end Delete_Tree_No_Follow;

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

   procedure Read_Beneath
     (Root    : String;
      Path    : String;
      Most    : Natural;
      Text    : out Ada.Strings.Unbounded.Unbounded_String;
      Outcome : out Read_Beneath_Outcome)
   is
      use type Interfaces.C.long;
      package Part_Vectors is new Ada.Containers.Indefinite_Vectors
        (Index_Type => Positive, Element_Type => String);

      O_Rdonly    : constant C_Int := 0;
      O_Nonblock  : constant C_Int := 16#4#;
      O_Directory : constant C_Int := 16#0010_0000#;
      O_Nofollow  : constant C_Int := 16#100#;
      O_Cloexec   : constant C_Int := 16#0100_0000#;
      E_Intr      : constant C_Int := 4;
      E_Noent     : constant C_Int := 2;
      E_Notdir    : constant C_Int := 20;
      E_Loop      : constant C_Int := 62;
      Type_Mask   : constant C_U16 := 8#170000#;
      Regular     : constant C_U16 := 8#100000#;
      Symlink     : constant C_U16 := 8#120000#;
      Chunk       : constant := 65_536;

      function C_Open (Name : Interfaces.C.Strings.chars_ptr; Flags : C_Int) return C_Int
        with Import, Convention => C, External_Name => "open";
      function C_Openat
        (Fd : C_Int; Name : Interfaces.C.Strings.chars_ptr; Flags : C_Int) return C_Int
        with Import, Convention => C, External_Name => "openat";
      function C_Close (Fd : C_Int) return C_Int
        with Import, Convention => C, External_Name => "close";
      function C_Read (Fd : C_Int; Buffer : System.Address; Count : Interfaces.C.size_t)
        return Interfaces.C.long
        with Import, Convention => C, External_Name => "read";
      function Errno_Location return System.Address
        with Import, Convention => C, External_Name => "__error";

      function Errno return C_Int is
         Value : C_Int with Import, Address => Errno_Location;
      begin
         return Value;
      end Errno;

      procedure Close (Fd : in out C_Int) is
         Ignored : C_Int;
      begin
         if Fd >= 0 then
            Ignored := C_Close (Fd);
            Fd := -1;
         end if;
      end Close;

      At_Symlink_Nofollow : constant C_Int := 16#20#;

      function C_Fstat (Fd : C_Int; Info : access Stat_Record) return C_Int
        with Import, Convention => C, External_Name => Hostkit.Darwin_Symbols.Fstat;
      function C_Fstatat
        (Fd : C_Int; Name : Interfaces.C.Strings.chars_ptr;
         Info : access Stat_Record; Flags : C_Int) return C_Int
        with Import, Convention => C, External_Name => Hostkit.Darwin_Symbols.Fstatat;

      --  Whether a name in a held directory is a link, not followed.
      function Is_Link_At (Fd : C_Int; Name : Interfaces.C.Strings.chars_ptr) return Boolean is
         Info : aliased Stat_Record;
      begin
         return C_Fstatat (Fd, Name, Info'Access, At_Symlink_Nofollow) = 0
           and then (Info.Mode and Type_Mask) = Symlink;
      end Is_Link_At;

      --  A held descriptor's type and size.
      function Held_Info (Fd : C_Int; Mode : out C_U16; Size : out Long_Long_Integer) return Boolean is
         Info : aliased Stat_Record;
         Done : constant Boolean := C_Fstat (Fd, Info'Access) = 0;
      begin
         Mode := Info.Mode;
         Size := Long_Long_Integer (Info.Size);
         return Done;
      end Held_Info;

      Parts : Part_Vectors.Vector;
      Held  : C_Int := -1;
      Start : Positive := Path'First;
   begin
      Text := Ada.Strings.Unbounded.Null_Unbounded_String;
      Outcome := Read_Failed;
      if Path'Length = 0 or else Path (Path'First) = '/' then
         Outcome := Read_Outside;
         return;
      end if;
      for Index in Path'First .. Path'Last + 1 loop
         if Index > Path'Last or else Path (Index) = '/' then
            declare
               Part : constant String := Path (Start .. Index - 1);
            begin
               if Part = ".." or else (for some C of Part => C = ASCII.NUL) then
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

      declare
         C_Root : Interfaces.C.Strings.chars_ptr :=
           Interfaces.C.Strings.New_String (if Root = "" then "." else Root);
      begin
         Held := C_Open (C_Root, O_Rdonly + O_Directory + O_Cloexec);
         Interfaces.C.Strings.Free (C_Root);
      end;
      if Held < 0 then
         Outcome := Read_Missing;
         return;
      end if;

      --  Each part looked up in the directory already held, never through
      --  a link: a part that is one fails to open rather than being taken.
      for Index in Parts.First_Index .. Parts.Last_Index loop
         declare
            Last   : constant Boolean := Index = Parts.Last_Index;
            C_Name : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Parts (Index));
            Next   : constant C_Int :=
              C_Openat (Held, C_Name, O_Rdonly + O_Nofollow + O_Cloexec
                                      + (if Last then O_Nonblock else O_Directory));
            Error  : constant C_Int := Errno;
         begin
            if Next < 0 then
               Outcome :=
                 (if Error = E_Noent then Read_Missing
                  elsif Error = E_Loop or else Is_Link_At (Held, C_Name) then Read_Outside
                  elsif Error = E_Notdir then Read_Missing
                  else Read_Failed);
               Interfaces.C.Strings.Free (C_Name);
               Close (Held);
               return;
            end if;
            Interfaces.C.Strings.Free (C_Name);
            Close (Held);
            Held := Next;
         end;
      end loop;

      declare
         Mode : C_U16;
         Size : Long_Long_Integer;
      begin
         if not Held_Info (Held, Mode, Size) then
            Close (Held);
            return;
         elsif (Mode and Type_Mask) = Symlink then
            Close (Held);
            Outcome := Read_Outside;
            return;
         elsif (Mode and Type_Mask) /= Regular then
            Close (Held);
            Outcome := Read_Not_File;
            return;
         elsif Size > Long_Long_Integer (Most) then
            Close (Held);
            Outcome := Read_Too_Large;
            return;
         end if;
      end;

      declare
         Buffer : aliased String (1 .. Chunk);
         Total  : Natural := 0;
         Got    : Interfaces.C.long;
      begin
         loop
            Got := C_Read (Held, Buffer'Address, Interfaces.C.size_t (Chunk));
            if Got < 0 then
               exit when Errno /= E_Intr;
            elsif Got = 0 then
               Outcome := Read_Done;
               exit;
            elsif Natural (Got) > Most - Total then
               Outcome := Read_Too_Large;
               exit;
            else
               Total := Total + Natural (Got);
               Ada.Strings.Unbounded.Append (Text, Buffer (1 .. Natural (Got)));
            end if;
         end loop;
      end;
      Close (Held);
      if Outcome /= Read_Done then
         Text := Ada.Strings.Unbounded.Null_Unbounded_String;
      end if;
   exception
      when others =>
         Close (Held);
         Text := Ada.Strings.Unbounded.Null_Unbounded_String;
         Outcome := Read_Failed;
   end Read_Beneath;

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
      function NS_Get_Executable_Path
        (Buffer : System.Address; Size : access Interfaces.C.unsigned)
         return Interfaces.C.int
        with Import => True, Convention => C,
             External_Name => "_NSGetExecutablePath";

      Buffer : aliased String (1 .. 4096) := [others => ASCII.NUL];
      Size   : aliased Interfaces.C.unsigned := Buffer'Length;
   begin
      if NS_Get_Executable_Path (Buffer'Address, Size'Access) /= 0 then
         return "";
      end if;

      for Index in Buffer'Range loop
         if Buffer (Index) = ASCII.NUL then
            --  Through the symlinks, so a program reached through one finds its
            --  own data rather than the link's neighbourhood.
            return Real_Path (Buffer (Buffer'First .. Index - 1));
         end if;
      end loop;
      return "";
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

      --  This host's own layout, which is not the one glibc uses: BSD keeps a
      --  change time and a login class between the group id and the gecos
      --  field, and an expiry after the shell. A record copied from the Linux
      --  body compiles, links and reads the wrong pointer -- which is how the
      --  first version of Home_Directory_Of answered nothing for root here
      --  while answering correctly on Linux, and it is exactly the kind of
      --  difference this crate exists to keep in one place per host.
      type Passwd is record
         Name    : Interfaces.C.Strings.chars_ptr;
         Passwd  : Interfaces.C.Strings.chars_ptr;
         Uid     : Interfaces.C.unsigned;
         Gid     : Interfaces.C.unsigned;
         Change  : Interfaces.C.long;
         Class   : Interfaces.C.Strings.chars_ptr;
         Gecos   : Interfaces.C.Strings.chars_ptr;
         Dir     : Interfaces.C.Strings.chars_ptr;
         Shell   : Interfaces.C.Strings.chars_ptr;
         Expires : Interfaces.C.long;
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

   function Home_Directory_Of (User : String) return String is
      --  This host's own layout, which is not the one glibc uses: BSD keeps a
      --  change time and a login class between the group id and the gecos
      --  field, and an expiry after the shell. A record copied from the Linux
      --  body compiles, links and reads the wrong pointer -- which is how the
      --  first version of Home_Directory_Of answered nothing for root here
      --  while answering correctly on Linux, and it is exactly the kind of
      --  difference this crate exists to keep in one place per host.
      type Passwd is record
         Name    : Interfaces.C.Strings.chars_ptr;
         Passwd  : Interfaces.C.Strings.chars_ptr;
         Uid     : Interfaces.C.unsigned;
         Gid     : Interfaces.C.unsigned;
         Change  : Interfaces.C.long;
         Class   : Interfaces.C.Strings.chars_ptr;
         Gecos   : Interfaces.C.Strings.chars_ptr;
         Dir     : Interfaces.C.Strings.chars_ptr;
         Shell   : Interfaces.C.Strings.chars_ptr;
         Expires : Interfaces.C.long;
      end record
        with Convention => C;
      type Passwd_Access is access all Passwd;

      function Getpwnam (Name : Interfaces.C.char_array) return Passwd_Access
        with Import => True, Convention => C, External_Name => "getpwnam";

      use type Interfaces.C.Strings.chars_ptr;

      Entry_Item : Passwd_Access;
   begin
      if User = "" then
         return "";
      end if;

      --  The database rather than HOME: HOME is this process's idea of its own
      --  home and says nothing about anybody else's.
      Entry_Item := Getpwnam (Interfaces.C.To_C (User));

      if Entry_Item = null
        or else Entry_Item.Dir = Interfaces.C.Strings.Null_Ptr
      then
         return "";
      end if;

      return Interfaces.C.Strings.Value (Entry_Item.Dir);
   exception
      when others =>
         return "";
   end Home_Directory_Of;

   function User_Places return User_Place_List is
      use Ada.Strings.Unbounded;
      Home : constant String := Home_Directory;
   begin
      --  Volumes appear in the mount table (/Volumes); the home is the place.
      return (if Home = "" then [] else [1 => (Path => To_Unbounded_String (Home), Kind => Home_Place)]);
   end User_Places;

   --  macOS keeps no freedesktop application entries.
   function Application_Data_Directories return Path_List is ([]);

   function Font_Directories return Path_List is
      use Ada.Strings.Unbounded;
      Home : constant String := Home_Directory;
      function Place (Folder : String) return Path_List is
        (if Folder = "" then [] else [1 => To_Unbounded_String (Folder)]);
   begin
      return Place ("/System/Library/Fonts") & Place ("/Library/Fonts")
        & Place ((if Home = "" then "" else Home & "/Library/Fonts"));
   end Font_Directories;

   function Application_Data_Directory return String is
      Home : constant String := Home_Directory;
   begin
      return (if Home = "" then "" else Home & "/Library/Application Support");
   end Application_Data_Directory;

   function Cache_Directory return String is
      Home : constant String := Home_Directory;
   begin
      return (if Home = "" then "" else Home & "/Library/Caches");
   end Cache_Directory;

   --  Application Support, not Preferences: see the spec.
   function Config_Directory return String is
   begin
      return Application_Data_Directory;
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
      pragma Unreferenced (Path);
   begin
      --  The native volumes (APFS, HFS+) are POSIX; a removable FAT/exFAT one is
      --  possible but its own rules are enforced by the OS at write time, so this
      --  declines to guess a restriction rather than binding statfs here.
      return False;
   end Uses_Dos_Filename_Rules;

   function Folds_Name_Case (Directory : String) return Boolean is
      --  <sys/unistd.h>: 1 when the volume tells case apart, 0 when it folds.
      PC_Case_Sensitive : constant Interfaces.C.int := 11;

      function Pathconf (Path : Interfaces.C.char_array; Name : Interfaces.C.int) return Interfaces.C.long
        with Import, Convention => C, External_Name => "pathconf";
      use type Interfaces.C.long;
      Answer : constant Interfaces.C.long := Pathconf (Interfaces.C.To_C (Directory), PC_Case_Sensitive);
   begin
      --  -1: the volume does not say; the native ones fold unless told not to.
      return Answer /= 1;
   end Folds_Name_Case;

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

   -------------------
   -- Creation_Mask --
   -------------------

   --  Read by setting and putting back, because POSIX has no way to ask. The
   --  window between the two calls is real and unavoidable: a process that
   --  created a file in it would get the mask this call is about to restore.
   --  Nothing here can close it, and pretending otherwise -- caching the last
   --  value this library set -- would answer confidently and wrongly about a
   --  mask something else changed.
   function C_Umask (Mask : Interfaces.C.unsigned) return Interfaces.C.unsigned
     with Import, Convention => C, External_Name => "umask";

   function Creation_Mask (Value : out Natural) return Boolean is
      Held : constant Interfaces.C.unsigned := C_Umask (0);
      Back : constant Interfaces.C.unsigned := C_Umask (Held);
   begin
      pragma Unreferenced (Back);
      Value := Natural (Held);
      return True;
   end Creation_Mask;

   function Set_Creation_Mask
     (Value : Natural; Previous : out Natural) return Boolean
   is
      Held : constant Interfaces.C.unsigned := C_Umask (Interfaces.C.unsigned (Value));
   begin
      Previous := Natural (Held);
      return True;
   end Set_Creation_Mask;

   ------------------
   -- Null_Device --
   ------------------

   function Null_Device return String is
   begin
      --  A character device every POSIX host has, in the place every POSIX
      --  host keeps it.
      return "/dev/null";
   end Null_Device;

   function Delete_Empty_Directory (Path : String) return Boolean is
   begin
      Ada.Directories.Delete_Directory (Path);
      return True;
   exception
      when others =>
         return False;
   end Delete_Empty_Directory;

   --  mkdir: the creation mask is taken from 0777, as for any new directory,
   --  and an entry already there -- a link to a directory included -- is
   --  refused.
   function Create_Directory (Path : String) return Boolean is
      function C_Mkdir (Path : Interfaces.C.Strings.chars_ptr; Mode : C_U16) return C_Int
        with Import => True, Convention => C, External_Name => "mkdir";
   begin
      if Path = "" or else (for some C of Path => C = ASCII.NUL) then
         return False;
      end if;
      declare
         C_Path : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
         Status : constant C_Int := C_Mkdir (C_Path, 8#777#);
      begin
         Interfaces.C.Strings.Free (C_Path);
         return Status = 0;
      end;
   exception
      when others =>
         return False;
   end Create_Directory;

   function Create_Path (Path : String) return Boolean is separate;

   --  unlink: the entry itself, a link and never what it points at; a
   --  directory is refused.
   function Delete_File (Path : String) return Boolean is
   begin
      if Path = "" or else (for some C of Path => C = ASCII.NUL) then
         return False;
      end if;
      declare
         C_Path : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
         Status : constant C_Int := C_Unlink (C_Path);
      begin
         Interfaces.C.Strings.Free (C_Path);
         return Status = 0;
      end;
   exception
      when others =>
         return False;
   end Delete_File;

   --  getcwd with no buffer allocates one as long as the answer needs.
   function Current_Directory return String is
      use type Interfaces.C.Strings.chars_ptr;
      function C_Getcwd (Buffer : System.Address; Size : Interfaces.C.size_t) return Interfaces.C.Strings.chars_ptr
        with Import => True, Convention => C, External_Name => "getcwd";
      procedure C_Free (Item : Interfaces.C.Strings.chars_ptr)
        with Import => True, Convention => C, External_Name => "free";
      Buffer : constant Interfaces.C.Strings.chars_ptr := C_Getcwd (System.Null_Address, 0);
   begin
      if Buffer = Interfaces.C.Strings.Null_Ptr then
         return "";
      end if;
      declare
         Result : constant String := Interfaces.C.Strings.Value (Buffer);
      begin
         C_Free (Buffer);
         return Result;
      end;
   end Current_Directory;

   --  fopen, which takes Path as it is: no limit but the host's own. POSIX
   --  translates nothing, so Text changes nothing here.
   function C_Fopen (Name : System.Address; Mode : System.Address) return Interfaces.C_Streams.FILEs
     with Import => True, Convention => C, External_Name => "fopen";

   --  The C stream for Path opened in fopen's Mode, for the stream and text
   --  subunits: Name_Error when nothing is there, Use_Error for any other
   --  refusal.
   function C_Stream_For (Path : String; Mode : String; Text : Boolean) return Interfaces.C_Streams.FILEs is
      pragma Unreferenced (Text);
      use type System.Address;
      C_Path : aliased constant String := Path & ASCII.NUL;
      C_Mode : aliased constant String := Mode & ASCII.NUL;
      Stream : Interfaces.C_Streams.FILEs := Interfaces.C_Streams.NULL_Stream;
      Error  : Integer := 2;
   begin
      if Path /= "" and then (for all C of Path => C /= ASCII.NUL) then
         Stream := C_Fopen (C_Path'Address, C_Mode'Address);
         Error := GNAT.OS_Lib.Errno;
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
