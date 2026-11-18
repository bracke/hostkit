with Ada.IO_Exceptions;
with Ada.Real_Time;
with Ada.Environment_Variables;
with System;
with Ada.Characters.Latin_1;
with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Fixed;

with GNAT.OS_Lib;

with Interfaces.C.Strings;
with Interfaces.C_Streams;

with Hostkit.Filesystem_Rules;

with Hostkit.Host;
with Hostkit.Fs.Instants;
with Hostkit.Linux_Abi;
with Hostkit.Posix;

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

   --  O_DIRECTORY and O_NOFOLLOW differ on arm, powerpc and m68k; the x86
   --  values there are O_DIRECT and O_LARGEFILE, and a final link is followed.
   Machine_O_Directory : constant C_Int := Hostkit.Linux_Abi.O_Directory (Hostkit.Host.Machine_Name);
   Machine_O_Nofollow  : constant C_Int := Hostkit.Linux_Abi.O_Nofollow (Hostkit.Host.Machine_Name);

   --  struct statx, one layout for every Linux body (Hostkit.Linux_Abi).
   subtype Statx_Record is Hostkit.Linux_Abi.Statx_Record;

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

   function Kind_Of (Path : String) return Entry_Kind is separate;

   S_IFREG : constant C_U16 := 8#100000#;
   S_IFDIR : constant C_U16 := 8#040000#;
   S_IFLNK : constant C_U16 := 8#120000#;

   --  Whether some component of Path is longer than any name can be
   --  (NAME_MAX, 255 bytes on Linux and macOS): no entry can bear it, so
   --  ENAMETOOLONG then says nothing is there. A whole path past PATH_MAX
   --  may still name an entry that the host will not look up by that path.
   function Has_Overlong_Component (Path : String) return Boolean is separate;

   --  What Stat_Entry asks the host for, and the record it answers in:
   --  statx(2), which says per field whether it answered.
   subtype Stat_Want is C_Unsigned;
   subtype Entry_Record is Statx_Record;

   Errno_Noent       : constant := 2;
   Errno_Notdir      : constant := 20;
   Errno_Nametoolong : constant := 36;
   Errno_Loop        : constant := 40;

   function Stat_Call
     (C_Path       : Interfaces.C.Strings.chars_ptr;
      Follow_Links : Boolean;
      Want         : Stat_Want;
      Info         : access Entry_Record)
      return C_Int
   is (Statx (At_FDCWD, C_Path, (if Follow_Links then 0 else 16#100#), Want, Info));

   function Answered (Info : Entry_Record; Want : Stat_Want) return Boolean is ((Info.Mask and Want) = Want);

   --  stat(2) of Path through the host's call (Stat_Call), a final link
   --  followed or not, asking for Want; the failures as the spec's
   --  Name_Error and Use_Error. ENOENT and ENOTDIR say nothing is reachable
   --  there, as do a name too long for any entry and a followed final link
   --  that loops; anything else (EACCES on a folder on the way, EIO, a path
   --  past PATH_MAX, an answer missing what was asked for) that the host
   --  would not say.
   function Stat_Entry (Path : String; Follow_Links : Boolean; Want : Stat_Want) return Entry_Record is separate;

   Want_Type  : constant Stat_Want := 16#1#;
   Want_Mtime : constant Stat_Want := 16#40#;
   Want_Size  : constant Stat_Want := 16#200#;
   Want_Mode  : constant Stat_Want := Statx_Mode;

   function Entry_Is_Absent (Path : String) return Boolean is separate;

   function Size_Of (Path : String; Follow_Links : Boolean := True) return Ada.Directories.File_Size is separate;

   function Modification_Time_Of (Path : String; Follow_Links : Boolean := True) return Ada.Calendar.Time is separate;

   --  The owner's bit of the mode, as GNAT's __gnat_stat_to_attr reads it
   --  (S_IRUSR, S_IWUSR of a stat that follows a link).
   function Owner_Bit (Path : String; Bit : C_U16) return Boolean is separate;

   function Is_Owner_Readable (Path : String) return Boolean is (Owner_Bit (Path, 8#400#));

   function Is_Owner_Writable (Path : String) return Boolean is (Owner_Bit (Path, 8#200#));

   function Is_Link (Path : String) return Boolean is separate;

   function Create_Link
     (Target    : String;
      Link_Path : String)
      return Boolean
   is separate;

   --  A regular file, and a mode bit that says it runs. The regular-file half matters:
   --  a directory carries the execute bit too, and means something else entirely by it.
   function Is_Executable (Path : String) return Boolean is separate;

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
            Device    => Linux_Device_Number (Info.Special_Device_Major, Info.Special_Device_Minor),
            Mode      => Natural (Info.Mode and Permission_Mask));
      elsif Mode = S_IFBLK then
         return
           (Available => True,
            Kind      => Special_File_Kind'(Block_Device),
            Device    => Linux_Device_Number (Info.Special_Device_Major, Info.Special_Device_Minor),
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

   --  The stat(2) symbol and where st_mode's low byte sits in its struct.
   Stat_Symbol   : constant String := "stat";
   Mode_Low_Byte : constant := 24;

   --  Group or other having any permission at all: (st_mode and 8#077#) /= 0. Those six bits
   --  live in the lowest byte of st_mode, so this reads that one byte out of the stat buffer
   --  rather than reconstructing the whole field. Want keeps the two callers apart: a file's
   --  bits and a directory's do not mean the same thing, so neither answers for the other.
   function Exposed (Path : String; Want : Ada.Directories.File_Kind) return Boolean is separate;

   function Accessible_By_Others (Path : String) return Boolean is separate;

   function Directory_Accessible_By_Others (Path : String) return Boolean is separate;

   --  chmod(2), not a spawned chmod(1): no PATH to find, and a return code to check.

   function Set_Owner (Path : String; User : Integer; Group : Integer) return Boolean is separate;

   function Set_Extended_Attribute
     (Path  : String;
      Name  : String;
      Value : Ada.Streams.Stream_Element_Array) return Boolean
   is separate;

   function Create_FIFO (Path : String; Mode : Natural) return Boolean is separate;

   function Create_Socket (Path : String; Mode : Natural) return Boolean is separate;

   function Create_Device
     (Path   : String;
      Kind   : Device_Kind;
      Device : Interfaces.Unsigned_64;
      Mode   : Natural) return Boolean
   is separate;

   function Create_Hard_Link (Target : String; Link_Path : String) return Boolean is separate;

   function Make_Private (Path : String) return Boolean is separate;

   --  POSIX rename replaces an existing Target atomically, which is exactly what the
   --  lock-file-then-rename write wants and what Windows rename cannot do.
   function Replace_File
     (Source : String;
      Target : String)
      return Boolean
   is separate;

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

   --  A hard link of the entry at From itself, never what it points at.
   function Link_Entry (From, To : Interfaces.C.Strings.chars_ptr) return Interfaces.C.int renames C_Link;

   --  The link errors that say the filesystem has no hard links here.
   function Link_Unsupported (Error : Integer) return Boolean is
     (Error in Fallback_Eperm | Fallback_Emlink | Fallback_Enosys | Fallback_Eopnotsupp);

   --  Whether anything, a dangling link included, is at Path.
   function Present (Path : Interfaces.C.Strings.chars_ptr) return Boolean is separate;

   --  A filesystem without RENAME_NOREPLACE (NFS, most FUSE mounts): a
   --  non-directory moves by link and unlink, which never replaces. A
   --  directory, or a filesystem without hard links, falls back to a
   --  rename after checking the target is free -- what mv -n does there;
   --  only an entry created in between could be replaced.
   function Without_Native_No_Replace (From, To : Interfaces.C.Strings.chars_ptr) return Move_Outcome is separate;

   function Move_Without_Native_No_Replace (Source : String; Target : String) return Move_Outcome is separate;

   --  rename(2) that refuses an existing target, as this host offers it:
   --  renameat2 with RENAME_NOREPLACE.
   function Rename_No_Replace (From, To : Interfaces.C.Strings.chars_ptr) return Interfaces.C.int is
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
   begin
      return C_Rename_At (At_Fdcwd, From, At_Fdcwd, To, Rename_Noreplace);
   end Rename_No_Replace;

   --  The errors that say the filesystem lacks that rename: EINVAL, ENOSYS
   --  and EOPNOTSUPP.
   function Lacks_No_Replace_Rename (Error : Integer) return Boolean is (Error in 22 | 38 | 95);

   function Move_No_Replace_Outcome
     (Source : String;
      Target : String)
      return Move_Outcome
   is separate;

   --  POSIX readlink: read the link's own target, not the resolved path.
   function Read_Link_Target
     (Path   : String;
      Target : out Ada.Strings.Unbounded.Unbounded_String)
      return Boolean
   is separate;

   --  POSIX unlink removes the link and never follows one, and a link to a directory is
   --  a link here rather than a directory -- so one call covers both. The Is_Link guard
   --  is what keeps this from removing an ordinary file that happens to be named.
   function Delete_Link (Path : String) return Boolean is separate;

   function Delete_Tree_No_Follow (Path : String) return Delete_Tree_Outcome is
      use Ada.Strings.Unbounded;
      use type Interfaces.C.Strings.chars_ptr;
      use type Interfaces.Unsigned_64;
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

      Statx_Wanted : constant C_U32 := Statx_Type_Inode or Hostkit.Linux_Abi.Statx_Mnt_Id;
      E_Xdev : constant C_Int := 18;

      --  What an entry was seen to be: its statx, when Available.
      --  Only what the walk compares, not the whole 256-byte statx: several
      --  are held in each level's frame, and the walk recurses up to
      --  Max_Depth levels on the caller's stack (1 MiB on a Windows-sized one).
      type Identity is record
         Mask         : C_U32 := 0;
         Mode         : C_U16 := 0;
         Inode        : Hostkit.Linux_Abi.C_U64 := 0;
         Device_Major : C_U32 := 0;
         Device_Minor : C_U32 := 0;
         Mount_Id     : Hostkit.Linux_Abi.C_U64 := 0;
         Available    : Boolean := False;
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
      function Errno return C_Int renames Hostkit.Posix.Errno;

      procedure Set_Errno (Code : C_Int) renames Hostkit.Posix.Set_Errno;
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

      --  The entry Name in Fd ("" with At_Empty_Path: Fd itself), not
      --  followed. Nothing is asked of a descriptor an open did not give.
      function Info_At (Fd : C_Int; Name : String; Flags : C_U32) return Identity is
         C_Name : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.Null_Ptr;
         Info   : aliased Statx_Record;
         Result : Identity;
      begin
         if Fd < 0 then
            return Result;
         end if;
         C_Name := Interfaces.C.Strings.New_String (Name);
         if C_Statx (Fd, C_Name, Flags, Statx_Wanted, Info'Access) = 0
           and then (Info.Mask and Statx_Type_Inode) = Statx_Type_Inode
         then
            Result :=
              (Mask         => Info.Mask,
               Mode         => Info.Mode,
               Inode        => Info.Inode,
               Device_Major => Info.Device_Major,
               Device_Minor => Info.Device_Minor,
               Mount_Id     => Info.Mount_Id,
               Available    => True);
         end if;
         Free (C_Name);
         return Result;
      exception
         when others =>
            Free (C_Name);
            return (others => <>);
      end Info_At;
      function Info_Of (Fd : C_Int) return Identity is
        (Info_At (Fd, "", At_Empty_Path));
      function Same (Left, Right : Identity) return Boolean is
        (Left.Available and then Right.Available
         and then Left.Device_Major = Right.Device_Major
         and then Left.Device_Minor = Right.Device_Minor
         and then Left.Inode = Right.Inode);
      function Is_Directory (Item : Identity) return Boolean is
        (Item.Available and then (Item.Mode and File_Type_Mask) = Directory_Type);
      --  Whether Child, seen in the held folder Parent, is on another mount.
      --  The walk stops there with EXDEV: a filesystem mounted inside the
      --  tree is not the tree's to empty, nor its mount point to remove.
      function Crosses_Mount (Parent, Child : Identity) return Boolean is
         function Record_Of (Item : Identity) return Statx_Record is
           (Statx_Record'
              (Mask         => Item.Mask,
               Device_Major => Item.Device_Major,
               Device_Minor => Item.Device_Minor,
               Mount_Id     => Item.Mount_Id,
               others       => <>));
      begin
         return Hostkit.Linux_Abi.Crosses_Mount (Record_Of (Parent), Record_Of (Child));
      end Crosses_Mount;

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
                  Observed : constant Identity := Info_At (Held, Name, At_Symlink_Nofollow);
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
            Current : constant Identity := Info_At (Parent, Own_Name, At_Symlink_Nofollow);
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
         Observed : constant Identity := Info_At (Parent, Name, At_Symlink_Nofollow);
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
   function Real_Path (Path : String) return String is separate;

   function Canonical_Path (Path : String) return String is separate;

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
      function Errno return C_Int renames Hostkit.Posix.Errno;

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
   function Directory_Part (Path : String) return String is separate;

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

   function Own_Executable_Directory return String is separate;

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

   function User_Places return User_Place_List is
      use Ada.Strings.Unbounded;
      Home    : constant String := Home_Directory;
      Runtime : constant String :=
        (if Ada.Environment_Variables.Exists ("XDG_RUNTIME_DIR")
         then Ada.Environment_Variables.Value ("XDG_RUNTIME_DIR") else "");
      function Place (Path : String; Kind : User_Place_Kind) return User_Place_List is
        (if Path = "" then [] else [1 => (Path => To_Unbounded_String (Path), Kind => Kind)]);
   begin
      --  Removable media (/run/media/<user>) are Mounts.Volume_Places'.
      return Place (Home, Home_Place)
        & Place ((if Runtime = "" then "" else Runtime & "/gvfs"), Desktop_Mounts_Parent);
   end User_Places;

   function Application_Data_Directories return Path_List is
      use Ada.Strings.Unbounded;
      function Value (Name : String) return String is
        (if Ada.Environment_Variables.Exists (Name) then Ada.Environment_Variables.Value (Name) else "");
      Home      : constant String := Home_Directory;
      Data_Home : constant String := Value ("XDG_DATA_HOME");
      Data_Dirs : constant String := Value ("XDG_DATA_DIRS");
      Search    : constant String :=
        (if Data_Home /= "" then Data_Home elsif Home /= "" then Home & "/.local/share" else "")
        & ':' & (if Data_Dirs /= "" then Data_Dirs else "/usr/local/share:/usr/share");
      Result    : Path_List (1 .. Search'Length);
      Last      : Natural := 0;
      First     : Positive := Search'First;

      procedure Add (Folder : String) is
      begin
         if Folder = "" or else Folder (Folder'First) /= '/' then
            return;
         end if;
         for Known of Result (1 .. Last) loop
            if To_String (Known) = Folder then
               return;
            end if;
         end loop;
         Last := Last + 1;
         Result (Last) := To_Unbounded_String (Folder);
      end Add;
   begin
      for Index in Search'Range loop
         if Search (Index) = ':' then
            Add (Search (First .. Index - 1));
            First := Index + 1;
         end if;
      end loop;
      Add (Search (First .. Search'Last));
      return Result (1 .. Last);
   end Application_Data_Directories;

   function Font_Directories return Path_List is
      use Ada.Strings.Unbounded;
      Home      : constant String := Home_Directory;
      Data_Home : constant String :=
        (if Ada.Environment_Variables.Exists ("XDG_DATA_HOME")
         then Ada.Environment_Variables.Value ("XDG_DATA_HOME") else "");
      User_Data : constant String :=
        (if Data_Home /= "" and then Data_Home (Data_Home'First) = '/' then Data_Home
         elsif Home /= "" then Home & "/.local/share"
         else "");
      function Place (Folder : String) return Path_List is
        (if Folder = "" then [] else [1 => To_Unbounded_String (Folder)]);
   begin
      return Place ("/usr/share/fonts") & Place ("/usr/local/share/fonts")
        & Place ((if User_Data = "" then "" else User_Data & "/fonts"))
        & Place ((if Home = "" then "" else Home & "/.fonts"));
   end Font_Directories;

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

   function Temp_Directory return String is separate;

   function Create_Temporary_Directory (Prefix : String) return String is separate;

   --  The mount table and when it was read: kept Mount_Table_Lifetime, so a
   --  loop of name checks (a search for a free name asks thousands of times)
   --  reads /proc/self/mountinfo once, not once a check.
   protected Mount_Table_Cache is
      procedure Get
        (Now     : Ada.Real_Time.Time;
         Fresh   : out Boolean;
         Content : out Ada.Strings.Unbounded.Unbounded_String);
      procedure Put (Now : Ada.Real_Time.Time; Content : Ada.Strings.Unbounded.Unbounded_String);
   private
      Held    : Ada.Strings.Unbounded.Unbounded_String;
      Read_At : Ada.Real_Time.Time := Ada.Real_Time.Time_First;
      Valid   : Boolean := False;
   end Mount_Table_Cache;

   protected body Mount_Table_Cache is
      procedure Get
        (Now     : Ada.Real_Time.Time;
         Fresh   : out Boolean;
         Content : out Ada.Strings.Unbounded.Unbounded_String)
      is
         use type Ada.Real_Time.Time;
         use type Ada.Real_Time.Time_Span;
      begin
         Fresh := Valid and then Now - Read_At <= Ada.Real_Time.To_Time_Span (Mount_Table_Lifetime);
         Content := (if Fresh then Held else Ada.Strings.Unbounded.Null_Unbounded_String);
      end Get;

      procedure Put (Now : Ada.Real_Time.Time; Content : Ada.Strings.Unbounded.Unbounded_String) is
      begin
         Held := Content;
         Read_At := Now;
         Valid := True;
      end Put;
   end Mount_Table_Cache;

   --  /proc/self/mountinfo, as Mount_Table_Cache keeps it. Raises when it
   --  cannot be read; a table that could not be read is not kept.
   function Mount_Table return String is
      use Ada.Strings.Unbounded;
      Now     : constant Ada.Real_Time.Time := Ada.Real_Time.Clock;
      Fresh   : Boolean;
      Content : Unbounded_String;
      File    : Ada.Text_IO.File_Type;
   begin
      Mount_Table_Cache.Get (Now, Fresh, Content);
      if Fresh then
         return To_String (Content);
      end if;
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, "/proc/self/mountinfo", Form => "shared=no");
      while not Ada.Text_IO.End_Of_File (File) loop
         Append (Content, Ada.Text_IO.Get_Line (File));
         Append (Content, Ada.Characters.Latin_1.LF);
      end loop;
      Ada.Text_IO.Close (File);
      Mount_Table_Cache.Put (Now, Content);
      return To_String (Content);
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         raise;
   end Mount_Table;

   --  The type of the filesystem holding Path, as the mount table names it
   --  (ext4, vfat, cifs); "" when it cannot be told. Path is taken through
   --  its links first, so a path under a link onto a stick is judged by the
   --  stick.
   function Filesystem_Type_Of (Path : String) return String is
      Resolved : constant String := (if Path = "" then "" else Real_Path (Path));

      --  udev's record of a block device ("8:17"), or "" when there is none
      --  to read: what it learned from the volume's superblock names the
      --  filesystem behind a "fuseblk" mount (Filesystem_Rules.Fuse_Block_Type).
      function Udev_Record (Device : String) return String is
         use Ada.Strings.Unbounded;
         Content : Unbounded_String;
         File    : Ada.Text_IO.File_Type;
      begin
         if Device = "" then
            return "";
         end if;
         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, "/run/udev/data/b" & Device, Form => "shared=no");
         while not Ada.Text_IO.End_Of_File (File) loop
            Append (Content, Ada.Text_IO.Get_Line (File));
            Append (Content, Ada.Characters.Latin_1.LF);
         end loop;
         Ada.Text_IO.Close (File);
         return To_String (Content);
      exception
         when others =>
            if Ada.Text_IO.Is_Open (File) then
               Ada.Text_IO.Close (File);
            end if;
            return "";
      end Udev_Record;
   begin
      if Path = "" then
         return "";
      end if;
      declare
         Table  : constant String := Mount_Table;
         Target : constant String := (if Resolved /= "" then Resolved else Ada.Directories.Full_Name (Path));
         Kind   : constant String := Hostkit.Filesystem_Rules.Filesystem_Type_For_Mount (Table, Target);
      begin
         if Kind /= "fuseblk" then
            return Hostkit.Filesystem_Rules.Fuse_Block_Type (Kind, "");
         end if;
         return Hostkit.Filesystem_Rules.Fuse_Block_Type
           (Kind, Udev_Record (Hostkit.Filesystem_Rules.Device_For_Mount (Table, Target)));
      end;
   exception
      when others =>
         return "";
   end Filesystem_Type_Of;

   function Uses_Dos_Filename_Rules (Path : String) return Boolean is
     (Hostkit.Filesystem_Rules.Dos_By_Type_Name (Filesystem_Type_Of (Path)));

   function Folds_Name_Case (Directory : String) return Boolean is
     (Hostkit.Filesystem_Rules.Folds_By_Type_Name (Filesystem_Type_Of (Directory)));

   function Leaf_Name_Limit_At (Directory : String) return Leaf_Name_Limit is
      --  <unistd.h> on Linux.
      PC_Name_Max : constant Interfaces.C.int := 3;

      function Pathconf (Path : Interfaces.C.char_array; Name : Interfaces.C.int) return Interfaces.C.long
        with Import, Convention => C, External_Name => "pathconf";
      use type Interfaces.C.long;
   begin
      if Hostkit.Filesystem_Rules.Utf16_By_Type_Name (Filesystem_Type_Of (Directory)) then
         return (Unit => Utf16_Units, Most => 255);
      elsif Directory = "" then
         return (others => <>);
      end if;
      declare
         Answer : constant Interfaces.C.long := Pathconf (Interfaces.C.To_C (Directory), PC_Name_Max);
      begin
         return (Unit => Bytes,
                 Most => (if Answer in 1 .. Interfaces.C.long (Positive'Last) then Positive (Answer) else 255));
      end;
   exception
      when others =>
         return (others => <>);
   end Leaf_Name_Limit_At;

   function Stored_Spelling (Path : String) return String is (Path);

   ---------------
   -- Separator --
   ---------------

   function Separator return Character is ('/');

   ---------------------------
   -- Search_Path_Delimiter --
   ---------------------------

   function Search_Path_Delimiter return Character is separate;

   ------------------------
   -- Executable_Suffix --
   ------------------------

   function Executable_Suffix return String is separate;

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

   function Creation_Mask (Value : out Natural) return Boolean is separate;

   function Set_Creation_Mask
     (Value : Natural; Previous : out Natural) return Boolean
   is separate;

   ------------------
   -- Null_Device --
   ------------------

   function Null_Device return String is separate;

   function Delete_Empty_Directory (Path : String) return Boolean is separate;

   --  mode_t on this host.
   subtype C_Mode is C_Unsigned;

   --  mkdir: the creation mask is taken from 0777, as for any new directory,
   --  and an entry already there -- a link to a directory included -- is
   --  refused.
   function Create_Directory (Path : String) return Boolean is separate;

   function Create_Path (Path : String) return Boolean is separate;

   --  unlink: the entry itself, a link and never what it points at; a
   --  directory is refused.
   function Delete_File (Path : String) return Boolean is separate;

   --  getcwd with no buffer allocates one as long as the answer needs.
   function Current_Directory return String is separate;

   --  fopen, which takes Path as it is: no limit but the host's own. POSIX
   --  translates nothing, so Text changes nothing here.
   function C_Fopen (Name : System.Address; Mode : System.Address) return Interfaces.C_Streams.FILEs
     with Import => True, Convention => C, External_Name => "fopen";

   --  The C stream for Path opened in fopen's Mode, for the stream and text
   --  subunits: Name_Error when nothing is there, Use_Error for any other
   --  refusal.
   function C_Stream_For (Path : String; Mode : String; Text : Boolean) return Interfaces.C_Streams.FILEs is separate;

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
