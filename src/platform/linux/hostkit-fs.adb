with Ada.Calendar;
with Ada.Environment_Variables;
with System;
with Ada.Directories;
with Ada.Text_IO;
with Ada.Characters.Latin_1;
with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Fixed;

with GNAT.OS_Lib;

with Interfaces.C.Strings;

with Hostkit.Filesystem_Rules;

with Hostkit.Host;
with Hostkit.Linux_Abi;

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

   --  O_DIRECTORY and O_NOFOLLOW differ on arm, powerpc and m68k; the x86
   --  values there are O_DIRECT and O_LARGEFILE, and a final link is followed.
   Machine_O_Directory : constant C_Int := Hostkit.Linux_Abi.O_Directory (Hostkit.Host.Machine_Name);
   Machine_O_Nofollow  : constant C_Int := Hostkit.Linux_Abi.O_Nofollow (Hostkit.Host.Machine_Name);

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
   function Is_Hidden (Path : String) return Boolean is
      pragma Unreferenced (Path);
   begin
      return False;
   end Is_Hidden;

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
   Fallback_Enosys     : constant := 38;
   Fallback_Eopnotsupp : constant := 95;

   function C_Link (From, To : Interfaces.C.Strings.chars_ptr) return Interfaces.C.int
     with Import => True, Convention => C, External_Name => "link";
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

   --  A filesystem without RENAME_NOREPLACE (NFS, most FUSE mounts): a
   --  non-directory moves by link and unlink, which never replaces. A
   --  directory, or a filesystem without hard links, falls back to a
   --  rename after checking the target is free -- what mv -n does there;
   --  only an entry created in between could be replaced.
   function Without_Native_No_Replace (From, To : Interfaces.C.Strings.chars_ptr) return Move_Outcome is
      Error : Integer;
   begin
      if C_Link (From, To) = 0 then
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
      elsif Error not in Fallback_Eperm | Fallback_Emlink | Fallback_Enosys | Fallback_Eopnotsupp then
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
      function C_Rename_At
        (Old_Dir  : Interfaces.C.int;
         Old_Path : Interfaces.C.Strings.chars_ptr;
         New_Dir  : Interfaces.C.int;
         New_Path : Interfaces.C.Strings.chars_ptr;
         Flags    : Interfaces.C.unsigned)
         return Interfaces.C.int
        with Import => True, Convention => C, External_Name => "renameat2";

      At_Fdcwd         : constant := -100;
      Rename_Noreplace : constant := 1;
      Exdev            : constant := 18;
      Einval           : constant := 22;
      Enosys           : constant := 38;
      Eopnotsupp       : constant := 95;

      function C_Rename (From, To : Interfaces.C.Strings.chars_ptr) return Interfaces.C.int is
        (C_Rename_At (At_Fdcwd, From, At_Fdcwd, To, Rename_Noreplace));

      C_Source : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Source);
      C_Target : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Target);
      Status   : Interfaces.C.int;
      Error    : Integer;
   begin
      Status := C_Rename (C_Source, C_Target);
      Error := GNAT.OS_Lib.Errno;
      if Status /= 0 and then (Error = Einval or else Error = Enosys or else Error = Eopnotsupp) then
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
      O_Directory : constant C_Int := Machine_O_Directory;
      O_Nofollow : constant C_Int := Machine_O_Nofollow;
      O_Cloexec : constant C_Int := 8#02000000#;
      At_Symlink_Nofollow : constant C_U32 := 16#100#;
      At_Empty_Path : constant C_U32 := 16#1000#;
      At_Removedir : constant C_Int := 16#200#;
      Statx_Type_Inode : constant C_U32 := 16#101#;
      File_Type_Mask : constant C_U16 := 8#170000#;
      Directory_Type : constant C_U16 := 8#040000#;

      type U16_Array is array (Positive range <>) of C_U16 with Convention => C;
      type U64_Array is array (Positive range <>) of C_U64 with Convention => C;
      type Statx_Timestamp is record
         Seconds : Interfaces.C.long;
         Nanoseconds, Reserved : C_U32;
      end record with Convention => C;
      type Statx_Record is record
         Mask, Block_Size : C_U32;
         Attributes : C_U64;
         Link_Count, User_Id, Group_Id : C_U32;
         Mode : C_U16;
         Spare_0 : U16_Array (1 .. 1);
         Inode, Size, Blocks, Attributes_Mask : C_U64;
         Access_Time, Birth_Time, Change_Time, Modified_Time : Statx_Timestamp;
         Device_Major, Device_Minor, File_Major, File_Minor : C_U32;
         Mount_Id : C_U64;
         Direct_Io_Memory_Align, Direct_Io_Offset_Align : C_U32;
         Spare_3 : U64_Array (1 .. 12);
      end record with Convention => C;
      type Identity is record
         Major, Minor : C_U32 := 0;
         Inode : C_U64 := 0;
         Mode : C_U16 := 0;
         Available : Boolean := False;
      end record;
      type Dirent is record
         Inode : C_U64;
         Offset : Interfaces.C.long;
         Record_Length : C_U16;
         Kind : Interfaces.C.unsigned_char;
         Name : Interfaces.C.char_array (0 .. 255);
      end record with Convention => C;

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
        with Import, Convention => C, External_Name => "fdopendir";
      function C_Readdir (Directory : System.Address) return System.Address
        with Import, Convention => C, External_Name => "readdir";
      function C_Closedir (Directory : System.Address) return C_Int
        with Import, Convention => C, External_Name => "closedir";
      function C_Unlinkat
        (Fd : C_Int; Name : Interfaces.C.Strings.chars_ptr; Flags : C_Int) return C_Int
        with Import, Convention => C, External_Name => "unlinkat";
      function C_Statx
        (Fd : C_Int; Name : Interfaces.C.Strings.chars_ptr; Flags, Mask : C_U32;
         Info : access Statx_Record) return C_Int
        with Import, Convention => C, External_Name => "statx";
      function Errno_Location return System.Address
        with Import, Convention => C, External_Name => "__errno_location";

      function Errno return C_Int is
         Value : C_Int with Import, Address => Errno_Location;
      begin
         return Value;
      end Errno;
      procedure Clear_Errno is
         Value : C_Int with Import, Address => Errno_Location;
      begin
         Value := 0;
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

      function Info_At (Fd : C_Int; Name : String; Flags : C_U32) return Identity is
         C_Name : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Name);
         Info : aliased Statx_Record;
         Result : Identity;
      begin
         if C_Statx (Fd, C_Name, Flags, Statx_Type_Inode, Info'Access) = 0
           and then (Info.Mask and Statx_Type_Inode) = Statx_Type_Inode
         then
            Result := (Info.File_Major, Info.File_Minor, Info.Inode, Info.Mode, True);
         end if;
         Free (C_Name);
         return Result;
      exception
         when others =>
            Free (C_Name);
            return Result;
      end Info_At;
      function Info_Of (Fd : C_Int) return Identity is
        (Info_At (Fd, "", At_Empty_Path));
      function Same (Left, Right : Identity) return Boolean is
        (Left.Available and then Right.Available
         and then Left.Major = Right.Major and then Left.Minor = Right.Minor
         and then Left.Inode = Right.Inode);
      function Is_Directory (Item : Identity) return Boolean is
        (Item.Available and then (Item.Mode and File_Type_Mask) = Directory_Type);

      function Read_Names (Held : C_Int; Names : in out Name_Vectors.Vector) return Boolean is
         Scan : C_Int := C_Dup (Held);
         Directory : System.Address := System.Null_Address;
         Pointer : System.Address;
         Name_Bytes : Natural := 0;
         Ignored : C_Int;
      begin
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
                     return False;
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

      function Delete_Held
        (Held : in out C_Int; Held_Info : Identity; Own_Name : String;
         Expected_Parent : Identity; Depth : Natural) return Boolean
      is
         Names : Name_Vectors.Vector;
         Ok : Boolean;
      begin
         if Depth > Max_Depth or else not Read_Names (Held, Names) then
            Close (Held);
            return False;
         end if;
         for Name of Names loop
            declare
               Observed : constant Identity := Info_At (Held, Name, At_Symlink_Nofollow);
               C_Name : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Name);
               Child : C_Int := -1;
            begin
               if not Observed.Available then
                  Ok := False;
               elsif not Is_Directory (Observed) then
                  Ok := C_Unlinkat (Held, C_Name, 0) = 0;
               else
                  Child := C_Openat (Held, C_Name, O_Rdonly + O_Directory + O_Nofollow + O_Cloexec);
                  declare
                     Child_Info : constant Identity := Info_Of (Child);
                  begin
                     Ok := Child >= 0 and then Is_Directory (Child_Info) and then Same (Observed, Child_Info);
                     if Ok then
                        Close (Held);
                        Ok := Delete_Held (Child, Child_Info, Name, Held_Info, Depth + 1);
                        Held := Child;
                        if Ok then
                           Ok := Same (Held_Info, Info_Of (Held));
                        end if;
                     else
                        Close (Child);
                     end if;
                  end;
               end if;
               Free (C_Name);
               if not Ok then
                  Close (Held);
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
         declare
            Dotdot : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String ("..");
            Parent : C_Int := C_Openat (Held, Dotdot, O_Rdonly + O_Directory + O_Cloexec);
            Current : constant Identity := Info_At (Parent, Own_Name, At_Symlink_Nofollow);
            C_Own : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Own_Name);
         begin
            Free (Dotdot);
            Ok := Parent >= 0 and then Same (Expected_Parent, Info_Of (Parent))
              and then Is_Directory (Current) and then Same (Held_Info, Current);
            Close (Held);
            if Ok then
               Ok := C_Unlinkat (Parent, C_Own, At_Removedir) = 0;
            end if;
            Free (C_Own);
            if not Ok then
               Close (Parent);
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

      function Delete_At (Parent : in out C_Int; Name : String) return Boolean is
         Observed : constant Identity := Info_At (Parent, Name, At_Symlink_Nofollow);
         C_Name : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Name);
         Child : C_Int := -1;
         Ok : Boolean;
      begin
         if not Observed.Available then
            Ok := False;
         elsif not Is_Directory (Observed) then
            Ok := C_Unlinkat (Parent, C_Name, 0) = 0;
         else
            Child := C_Openat (Parent, C_Name, O_Rdonly + O_Directory + O_Nofollow + O_Cloexec);
            declare
               Child_Info : constant Identity := Info_Of (Child);
               Parent_Info : constant Identity := Info_Of (Parent);
            begin
               Ok := Child >= 0 and then Is_Directory (Child_Info)
                 and then Same (Observed, Child_Info) and then Parent_Info.Available;
               if Ok then
                  Close (Parent);
                  Ok := Delete_Held (Child, Child_Info, Name, Parent_Info, 0);
                  Parent := Child;
               else
                  Close (Child);
               end if;
            end;
         end if;
         Free (C_Name);
         Close (Parent);
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
      O_Nonblock  : constant C_Int := 8#4000#;
      O_Directory : constant C_Int := Machine_O_Directory;
      O_Nofollow  : constant C_Int := Machine_O_Nofollow;
      O_Cloexec   : constant C_Int := 8#02000000#;
      E_Intr      : constant C_Int := 4;
      E_Noent     : constant C_Int := 2;
      E_Notdir    : constant C_Int := 20;
      E_Loop      : constant C_Int := 40;
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
        with Import, Convention => C, External_Name => "__errno_location";

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

      At_Empty_Path       : constant C_Unsigned := 16#1000#;
      At_Symlink_Nofollow : constant C_Unsigned := 16#100#;
      Statx_Type          : constant C_Unsigned := 16#1#;
      Statx_Size          : constant C_Unsigned := 16#200#;

      --  Whether a name in a held directory is a link, not followed.
      function Is_Link_At (Fd : C_Int; Name : Interfaces.C.Strings.chars_ptr) return Boolean is
         Info : aliased Statx_Record;
      begin
         return Statx (Fd, Name, At_Symlink_Nofollow, Statx_Type, Info'Access) = 0
           and then (Info.Mode and Type_Mask) = Symlink;
      end Is_Link_At;

      --  A held descriptor's type and size.
      function Held_Info (Fd : C_Int; Mode : out C_U16; Size : out Long_Long_Integer) return Boolean is
         Info  : aliased Statx_Record;
         Empty : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String ("");
         Done  : constant Boolean :=
           Statx (Fd, Empty, At_Empty_Path, Statx_Type + Statx_Size, Info'Access) = 0;
      begin
         Interfaces.C.Strings.Free (Empty);
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
      Link   : constant String := "/proc/self/exe";
      Target : Ada.Strings.Unbounded.Unbounded_String;
   begin
      --  The kernel's own answer, and it is the resolved path already --
      --  save that a program replaced on disk while it runs is named with
      --  " (deleted)" after it. The path is the one a new copy lies at, so
      --  starting itself again starts that, not a name that is no file.
      if not Read_Link_Target (Link, Target) then
         return "";
      end if;
      declare
         Path    : constant String := Ada.Strings.Unbounded.To_String (Target);
         Deleted : constant String := " (deleted)";
      begin
         if Path'Length > Deleted'Length
           and then Path (Path'Last - Deleted'Length + 1 .. Path'Last) = Deleted
         then
            return Path (Path'First .. Path'Last - Deleted'Length);
         end if;
         return Path;
      end;
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

   function Home_Directory_Of (User : String) return String is
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
         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, "/proc/self/mountinfo", Form => "shared=no");
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

end Hostkit.Fs;
