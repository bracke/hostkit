with Ada.Strings;
with Ada.Strings.Fixed;
with Interfaces.C;
with Interfaces.C.Strings;
with System;

with Hostkit.Host;
with Hostkit.Linux_Abi;
with Hostkit.Posix;

package body Hostkit.Lease_Files is
   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.C.int;
   use type Interfaces.C.long;
   use type Interfaces.C.unsigned;
   use type Interfaces.C.unsigned_long;
   use type Interfaces.C.unsigned_short;
   use type Interfaces.C.Strings.chars_ptr;
   use type Interfaces.Unsigned_64;

   subtype C_Int is Interfaces.C.int;
   subtype C_U16 is Interfaces.C.unsigned_short;
   subtype C_U32 is Interfaces.C.unsigned;
   subtype C_U64 is Interfaces.C.unsigned_long;
   subtype C_S64 is Interfaces.C.long;

   --  struct statx, one layout for every Linux body (Hostkit.Linux_Abi).
   subtype Statx_Record is Hostkit.Linux_Abi.Statx_Record;

   O_Rdonly : constant C_Int := 0;
   O_Rdwr : constant C_Int := 2;
   O_Creat : constant C_Int := 16#40#;
   O_Excl : constant C_Int := 16#80#;
   --  Per machine: arm, powerpc and m68k have their own (Hostkit.Linux_Abi).
   O_Nofollow : constant C_Int := Hostkit.Linux_Abi.O_Nofollow (Hostkit.Host.Machine_Name);
   O_Cloexec : constant C_Int := 16#80_000#;
   Lock_Shared : constant C_Int := 1;
   Lock_Exclusive : constant C_Int := 2;
   Lock_Unlock : constant C_Int := 8;
   Lock_Nonblocking : constant C_Int := 4;
   At_Empty_Path : constant C_U32 := 16#1000#;
   At_Nofollow : constant C_U32 := 16#100#;
   Statx_Type : constant C_U32 := 16#1#;
   Statx_Mode : constant C_U32 := 16#2#;
   Statx_Links : constant C_U32 := 16#4#;
   Statx_Uid : constant C_U32 := 16#8#;
   Statx_Inode : constant C_U32 := 16#100#;
   Statx_Size : constant C_U32 := 16#200#;
   Statx_Wanted : constant C_U32 :=
     Statx_Type or Statx_Mode or Statx_Links or Statx_Uid
       or Statx_Inode or Statx_Size;
   Type_Mask : constant C_U16 := 16#F000#;
   Regular_Type : constant C_U16 := 16#8000#;

   function C_Open
     (Path : Interfaces.C.Strings.chars_ptr; Flags : C_Int;
      Mode : C_U32) return C_Int
     with Import, Convention => C, External_Name => "open";
   function C_Close (Fd : C_Int) return C_Int
     with Import, Convention => C, External_Name => "close";
   function C_Flock (Fd, Operation : C_Int) return C_Int
     with Import, Convention => C, External_Name => "flock";
   function C_Ftruncate (Fd : C_Int; Length : C_S64) return C_Int
     with Import, Convention => C, External_Name => "ftruncate";
   function C_Fsync (Fd : C_Int) return C_Int
     with Import, Convention => C, External_Name => "fsync";
   function C_Fchmod (Fd : C_Int; Mode : C_U32) return C_Int
     with Import, Convention => C, External_Name => "fchmod";
   function C_Pread
     (Fd : C_Int; Buffer : System.Address; Count : C_U64;
      Offset : C_S64) return C_S64
     with Import, Convention => C, External_Name => "pread";
   function C_Pwrite
     (Fd : C_Int; Buffer : System.Address; Count : C_U64;
      Offset : C_S64) return C_S64
     with Import, Convention => C, External_Name => "pwrite";
   function C_Geteuid return C_U32
     with Import, Convention => C, External_Name => "geteuid";
   function C_Statx
     (Fd : C_Int; Path : Interfaces.C.Strings.chars_ptr; Flags, Mask : C_U32;
      Info : access Statx_Record) return C_Int
     with Import, Convention => C, External_Name => "statx";
   function Errno return C_Int renames Hostkit.Posix.Errno;

   function C_Link (From, To : Interfaces.C.Strings.chars_ptr) return C_Int
     with Import, Convention => C, External_Name => "link";
   function C_Unlink (Path : Interfaces.C.Strings.chars_ptr) return C_Int
     with Import, Convention => C, External_Name => "unlink";
   function C_Getpid return C_Int
     with Import, Convention => C, External_Name => "getpid";

   --  renameat2 with RENAME_NOREPLACE.
   function C_Rename_At
     (Old_Dir : C_Int; Old_Path : Interfaces.C.Strings.chars_ptr;
      New_Dir : C_Int; New_Path : Interfaces.C.Strings.chars_ptr;
      Flags   : C_U32) return C_Int
     with Import, Convention => C, External_Name => "renameat2";
   function Rename_No_Replace (From, To : Interfaces.C.Strings.chars_ptr) return C_Int is
     (C_Rename_At (-100, From, -100, To, 1));
   --  EINVAL, ENOSYS and EOPNOTSUPP: the filesystem has no such rename.
   function Lacks_No_Replace_Rename (Code : C_Int) return Boolean is (Code in 22 | 38 | 95);

   --  Numbers the temporaries this process makes, so that two tasks creating
   --  leases in one folder at once never pick the same name.
   protected Temporaries is
      procedure Next (Number : out Natural);
   private
      Last : Natural := 0;
   end Temporaries;

   protected body Temporaries is
      procedure Next (Number : out Natural) is
      begin
         Last := (if Last = Natural'Last then 0 else Last + 1);
         Number := Last;
      end Next;
   end Temporaries;

   --  A name beside Path, in the same folder, that is this process's own: a
   --  lease is made under it and only takes Path's name once it is locked.
   function Temporary_Name (Path : String) return String is
      Slash  : Natural := 0;
      Number : Natural;
   begin
      for Index in reverse Path'Range loop
         if Path (Index) = '/' then
            Slash := Index;
            exit;
         end if;
      end loop;
      Temporaries.Next (Number);
      return Path (Path'First .. Slash) & ".hostkit-lease-"
        & Ada.Strings.Fixed.Trim (C_Int'Image (C_Getpid), Ada.Strings.Both) & "-"
        & Ada.Strings.Fixed.Trim (Natural'Image (Number), Ada.Strings.Both);
   end Temporary_Name;

   --  Give the locked temporary From the name To, never replacing anything
   --  there. The host's no-replace rename does it in one step; on a
   --  filesystem without one (NFS, most FUSE mounts) link and unlink do it,
   --  link failing with EEXIST as the rename does. Answers 0, or the errno
   --  of the step that failed -- and on failure From is still From and To is
   --  not this call's.
   function Publish (From, To : Interfaces.C.Strings.chars_ptr) return C_Int is
      Code    : C_Int;
      Ignored : C_Int;
   begin
      if Rename_No_Replace (From, To) = 0 then
         return 0;
      end if;
      Code := Errno;
      if not Lacks_No_Replace_Rename (Code) then
         return Code;
      end if;
      if C_Link (From, To) /= 0 then
         return Errno;
      end if;
      --  Two names for a moment; a lease is one, so the temporary goes. If it
      --  will not, the new name is taken back rather than leave a lease with
      --  two links, which Open refuses.
      if C_Unlink (From) /= 0 then
         Code := Errno;
         Ignored := C_Unlink (To);
         return (if Code = 0 then 5 else Code);
      end if;
      return 0;
   end Publish;

   procedure Reset (Item : out Lease) is
   begin
      Item.Handle := -1;
      Item.Held := False;
   end Reset;

   function Info_Of
     (Fd : C_Int; Info : access Statx_Record) return Boolean
   is
      Empty : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String ("");
      Result : C_Int;
   begin
      Result := C_Statx
        (Fd, Empty, At_Empty_Path or At_Nofollow, Statx_Wanted, Info);
      Interfaces.C.Strings.Free (Empty);
      return Result = 0 and then (Info.Mask and Statx_Wanted) = Statx_Wanted;
   exception
      when others =>
         if Empty /= Interfaces.C.Strings.Null_Ptr then
            Interfaces.C.Strings.Free (Empty);
         end if;
         return False;
   end Info_Of;

   function Is_Valid (Info : Statx_Record) return Boolean is
     ((Info.Mode and Type_Mask) = Regular_Type
      and then Info.User_Id = C_Geteuid and then Info.Link_Count = 1);

   --  glibc's encoding of dev_t. Keeping this representation preserves lease
   --  tokens written by the former fstat-based adapter across an upgrade.
   function Device_Number (Major, Minor : C_U32) return Interfaces.Unsigned_64 is
      M : constant Interfaces.Unsigned_64 := Interfaces.Unsigned_64 (Major);
      N : constant Interfaces.Unsigned_64 := Interfaces.Unsigned_64 (Minor);
   begin
      return (N and 16#FF#)
        or Interfaces.Shift_Left (M and 16#FFF#, 8)
        or Interfaces.Shift_Left (N and not 16#FF#, 12)
        or Interfaces.Shift_Left (M and not 16#FFF#, 32);
   end Device_Number;

   function Take_Lock (Fd : C_Int; Kind : Lock_Kind) return Open_Outcome is
      Result : C_Int;
   begin
      Result := C_Flock
        (Fd, (if Kind = Exclusive then Lock_Exclusive else Lock_Shared)
         + Lock_Nonblocking);
      if Result = 0 then
         return Opened;
      elsif Errno = 11 or else Errno = 13 then
         return Busy;
      elsif Errno = 37 or else Errno = 95 then
         return Unsupported;
      else
         return Error;
      end if;
   end Take_Lock;

   --  Made under a temporary name in the same folder, locked there, and only
   --  then given Path's name: a lease is never at Path unlocked, where another
   --  process's scavenger could take it, find what it guards absent and
   --  delete it before this one had locked it. A name already taken is
   --  Refused, as an O_EXCL open of it was.
   function Create (Path : String; Item : out Lease) return Open_Outcome is
      C_Path : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.Null_Ptr;
      C_Temp : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.Null_Ptr;
      Fd : C_Int := -1;
      Info : aliased Statx_Record;
      Outcome : Open_Outcome;
      Code : C_Int := 0;
      Ignored : C_Int;

      --  Close and remove the temporary, and free both names.
      procedure Abandon is
      begin
         if Fd >= 0 then
            Ignored := C_Close (Fd);
            Fd := -1;
         end if;
         if C_Temp /= Interfaces.C.Strings.Null_Ptr then
            Ignored := C_Unlink (C_Temp);
            Interfaces.C.Strings.Free (C_Temp);
         end if;
         if C_Path /= Interfaces.C.Strings.Null_Ptr then
            Interfaces.C.Strings.Free (C_Path);
         end if;
      end Abandon;
   begin
      Reset (Item);
      if Path = "" then
         return Error;
      end if;
      C_Path := Interfaces.C.Strings.New_String (Path);
      --  A temporary name left by an earlier process with this pid is passed
      --  over, never opened.
      for Attempt in 1 .. 16 loop
         C_Temp := Interfaces.C.Strings.New_String (Temporary_Name (Path));
         Fd := C_Open
           (C_Temp, O_Rdwr + O_Creat + O_Excl + O_Cloexec + O_Nofollow, 8#600#);
         exit when Fd >= 0;
         Code := Errno;
         Interfaces.C.Strings.Free (C_Temp);
         exit when Code /= 17;
      end loop;
      if Fd < 0 then
         Abandon;
         return (if Code = 40 then Refused else Error);
      end if;
      if not Info_Of (Fd, Info'Access) or else not Is_Valid (Info)
        or else C_Fchmod (Fd, 8#600#) /= 0
      then
         Abandon;
         return Refused;
      end if;
      Outcome := Take_Lock (Fd, Shared);
      if Outcome /= Opened then
         Abandon;
         return Outcome;
      end if;
      Code := Publish (C_Temp, C_Path);
      if Code /= 0 then
         Abandon;
         return (if Code = 17 or else Code = 40 then Refused else Error);
      end if;
      Interfaces.C.Strings.Free (C_Temp);
      Interfaces.C.Strings.Free (C_Path);
      Item.Handle := Interfaces.Integer_64 (Fd);
      Item.Held := True;
      return Opened;
   exception
      when others =>
         Abandon;
         Reset (Item);
         return Error;
   end Create;

   function Open
     (Path : String; Kind : Lock_Kind; Writable : Boolean;
      Item : out Lease) return Open_Outcome
   is
      C_Path : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Path);
      Fd : C_Int := -1;
      Info : aliased Statx_Record;
      Outcome : Open_Outcome;
      Code : C_Int;
      Ignored : C_Int;
   begin
      Reset (Item);
      Fd := C_Open
        (C_Path, (if Writable then O_Rdwr else O_Rdonly)
         + O_Cloexec + O_Nofollow, 0);
      if Fd < 0 then
         Code := Errno;
         Interfaces.C.Strings.Free (C_Path);
         return (if Code = 2 or else Code = 40 then Refused else Error);
      end if;
      Interfaces.C.Strings.Free (C_Path);
      if not Info_Of (Fd, Info'Access) or else not Is_Valid (Info) then
         Ignored := C_Close (Fd);
         Fd := -1;
         return Refused;
      end if;
      Outcome := Take_Lock (Fd, Kind);
      if Outcome /= Opened then
         Ignored := C_Close (Fd);
         Fd := -1;
         return Outcome;
      end if;
      Item.Handle := Interfaces.Integer_64 (Fd);
      Item.Held := True;
      return Opened;
   exception
      when others =>
         if Fd >= 0 then
            Ignored := C_Close (Fd);
         end if;
         if C_Path /= Interfaces.C.Strings.Null_Ptr then
            Interfaces.C.Strings.Free (C_Path);
         end if;
         Reset (Item);
         return Error;
   end Open;

   procedure Release (Item : in out Lease) is
      Ignored : C_Int;
   begin
      if Item.Held then
         Ignored := C_Flock (C_Int (Item.Handle), Lock_Unlock);
         Ignored := C_Close (C_Int (Item.Handle));
      end if;
      Item.Handle := -1;
      Item.Held := False;
   end Release;

   function Is_Held (Item : Lease) return Boolean is (Item.Held);

   function Write_At
     (Item : Lease; Data : Ada.Streams.Stream_Element_Array;
      Offset : Ada.Streams.Stream_Element_Offset := 0) return Boolean
   is
      Position : Ada.Streams.Stream_Element_Offset := 0;
      Written  : C_S64;
      Synced   : C_Int;
   begin
      if not Item.Held
        or else Offset < 0
        or else Offset > Ada.Streams.Stream_Element_Offset'Last
          - Ada.Streams.Stream_Element_Offset (Data'Length)
      then
         return False;
      end if;
      while Position < Ada.Streams.Stream_Element_Offset (Data'Length) loop
         Written := C_Pwrite
           (C_Int (Item.Handle), Data (Data'First + Position)'Address,
            C_U64 (Ada.Streams.Stream_Element_Offset (Data'Length) - Position),
            C_S64 (Offset + Position));
         if Written > 0
           and then Written <=
             C_S64 (Ada.Streams.Stream_Element_Offset (Data'Length) - Position)
         then
            Position := Position + Ada.Streams.Stream_Element_Offset (Written);
         elsif Written < 0 and then Errno = 4 then
            null;
         else
            return False;
         end if;
      end loop;
      loop
         Synced := C_Fsync (C_Int (Item.Handle));
         exit when Synced = 0 or else Errno /= 4;
      end loop;
      return Synced = 0;
   exception
      when others => return False;
   end Write_At;

   function Read_At
     (Item : Lease; Data : out Ada.Streams.Stream_Element_Array;
      Offset : Ada.Streams.Stream_Element_Offset := 0) return Boolean
   is
      Position : Ada.Streams.Stream_Element_Offset := 0;
      Read     : C_S64;
   begin
      if not Item.Held
        or else Offset < 0
        or else Offset > Ada.Streams.Stream_Element_Offset'Last
          - Ada.Streams.Stream_Element_Offset (Data'Length)
      then
         return False;
      end if;
      while Position < Ada.Streams.Stream_Element_Offset (Data'Length) loop
         Read := C_Pread
           (C_Int (Item.Handle), Data (Data'First + Position)'Address,
            C_U64 (Ada.Streams.Stream_Element_Offset (Data'Length) - Position),
            C_S64 (Offset + Position));
         if Read > 0
           and then Read <=
             C_S64 (Ada.Streams.Stream_Element_Offset (Data'Length) - Position)
         then
            Position := Position + Ada.Streams.Stream_Element_Offset (Read);
         elsif Read < 0 and then Errno = 4 then
            null;
         else
            return False;
         end if;
      end loop;
      return True;
   exception
      when others => return False;
   end Read_At;

   function Size (Item : Lease) return Long_Long_Integer is
      Info : aliased Statx_Record;
   begin
      if not Item.Held or else not Info_Of (C_Int (Item.Handle), Info'Access)
        or else Info.Size > Interfaces.Unsigned_64 (Long_Long_Integer'Last)
      then
         return -1;
      end if;
      return Long_Long_Integer (Info.Size);
   exception
      when others => return -1;
   end Size;

   function Truncate (Item : Lease; Length : Long_Long_Integer) return Boolean is
      Result : C_Int;
   begin
      if not Item.Held or else Length < 0 or else Length > Size (Item) then
         return False;
      end if;
      loop
         Result := C_Ftruncate (C_Int (Item.Handle), C_S64 (Length));
         exit when Result = 0 or else Errno /= 4;
      end loop;
      if Result /= 0 then
         return False;
      end if;
      loop
         Result := C_Fsync (C_Int (Item.Handle));
         exit when Result = 0 or else Errno /= 4;
      end loop;
      return Result = 0;
   exception
      when others => return False;
   end Truncate;

   function Identity (Item : Lease) return Lease_Identity is
      Info : aliased Statx_Record;
   begin
      if not Item.Held or else not Info_Of (C_Int (Item.Handle), Info'Access) then
         return (others => <>);
      end if;
      return
        (Available => True,
         Volume => Device_Number (Info.Device_Major, Info.Device_Minor),
         Low => Interfaces.Unsigned_64 (Info.Inode), High => 0);
   exception
      when others => return (others => <>);
   end Identity;

   function Path_Matches (Item : Lease; Path : String) return Boolean is
      C_Path : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Path);
      Fd : C_Int := -1;
      Info : aliased Statx_Record;
      Left, Right : Lease_Identity;
      Ignored : C_Int;
   begin
      if not Item.Held then
         Interfaces.C.Strings.Free (C_Path);
         return False;
      end if;
      Fd := C_Open (C_Path, O_Rdonly + O_Cloexec + O_Nofollow, 0);
      Interfaces.C.Strings.Free (C_Path);
      if Fd < 0 or else not Info_Of (Fd, Info'Access)
        or else not Is_Valid (Info)
      then
         if Fd >= 0 then
            Ignored := C_Close (Fd);
         end if;
         return False;
      end if;
      Left := Identity (Item);
      Right :=
        (Available => True,
         Volume => Device_Number (Info.Device_Major, Info.Device_Minor),
         Low => Interfaces.Unsigned_64 (Info.Inode), High => 0);
      Ignored := C_Close (Fd);
      return Left.Available and then Right.Available
        and then Left.Volume = Right.Volume and then Left.Low = Right.Low;
   exception
      when others =>
         if C_Path /= Interfaces.C.Strings.Null_Ptr then
            Interfaces.C.Strings.Free (C_Path);
         end if;
         if Fd >= 0 then
            Ignored := C_Close (Fd);
         end if;
         return False;
   end Path_Matches;
end Hostkit.Lease_Files;
