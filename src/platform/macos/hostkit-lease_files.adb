with Interfaces.C;
with Interfaces.C.Strings;
with System;

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

   type Timespec is record
      Seconds, Nanoseconds : C_S64 := 0;
   end record with Convention => C;
   type Spare_Array is array (1 .. 2) of C_S64 with Convention => C;
   type Stat_Record is record
      Device : C_Int := 0;
      Mode, Link_Count : C_U16 := 0;
      Inode : C_U64 := 0;
      User_Id, Group_Id : C_U32 := 0;
      Raw_Device, Padding : C_Int := 0;
      Access_Time, Modified_Time, Change_Time, Birth_Time : Timespec;
      File_Size, Blocks : C_S64 := 0;
      Block_Size : C_Int := 0;
      Flags, Generation : C_U32 := 0;
      Long_Spare : C_Int := 0;
      Quad_Spare : Spare_Array := [others => 0];
   end record with Convention => C;
   pragma Compile_Time_Error
     (Stat_Record'Size /= 144 * 8, "Darwin struct stat must be 144 bytes");

   O_Rdonly : constant C_Int := 0;
   O_Rdwr : constant C_Int := 2;
   O_Creat : constant C_Int := 16#0200#;
   O_Excl : constant C_Int := 16#0800#;
   O_Nofollow : constant C_Int := 16#0100#;
   O_Cloexec : constant C_Int := 16#100_0000#;
   Lock_Shared : constant C_Int := 1;
   Lock_Exclusive : constant C_Int := 2;
   Lock_Unlock : constant C_Int := 8;
   Lock_Nonblocking : constant C_Int := 4;
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
   function C_Fsync (Fd : C_Int) return C_Int
     with Import, Convention => C, External_Name => "fsync";
   function C_Fchmod (Fd : C_Int; Mode : C_U32) return C_Int
     with Import, Convention => C, External_Name => "fchmod";
   function C_Fstat (Fd : C_Int; Info : access Stat_Record) return C_Int
     with Import, Convention => C, External_Name => "fstat$INODE64";
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
   function Errno_Location return System.Address
     with Import, Convention => C, External_Name => "__error";

   function Errno return C_Int is
      Value : C_Int with Import, Address => Errno_Location;
   begin
      return Value;
   end Errno;

   procedure Reset (Item : out Lease) is
   begin
      Item.Handle := -1;
      Item.Held := False;
   end Reset;

   function Is_Valid (Info : Stat_Record) return Boolean is
     ((Info.Mode and Type_Mask) = Regular_Type
      and then Info.User_Id = C_Geteuid and then Info.Link_Count = 1);

   function Take_Lock (Fd : C_Int; Kind : Lock_Kind) return Open_Outcome is
      Result : C_Int;
      Code : C_Int;
   begin
      Result := C_Flock
        (Fd, (if Kind = Exclusive then Lock_Exclusive else Lock_Shared)
         + Lock_Nonblocking);
      if Result = 0 then
         return Opened;
      end if;
      Code := Errno;
      if Code = 35 or else Code = 13 then
         return Busy;
      elsif Code = 77 or else Code = 45 or else Code = 102 then
         return Unsupported;
      else
         return Error;
      end if;
   end Take_Lock;

   function Create (Path : String; Item : out Lease) return Open_Outcome is
      C_Path : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      Fd : C_Int := -1;
      Info : aliased Stat_Record;
      Outcome : Open_Outcome;
      Code : C_Int;
      Ignored : C_Int;
   begin
      Reset (Item);
      Fd := C_Open
        (C_Path, O_Rdwr + O_Creat + O_Excl + O_Cloexec + O_Nofollow, 8#600#);
      if Fd < 0 then
         Code := Errno;
         Interfaces.C.Strings.Free (C_Path);
         return (if Code = 17 or else Code = 62 then Refused else Error);
      end if;
      if C_Fstat (Fd, Info'Access) /= 0 or else not Is_Valid (Info)
        or else C_Fchmod (Fd, 8#600#) /= 0
      then
         Ignored := C_Close (Fd);
         Fd := -1;
         Interfaces.C.Strings.Free (C_Path);
         return Refused;
      end if;
      Outcome := Take_Lock (Fd, Shared);
      if Outcome /= Opened then
         Ignored := C_Close (Fd);
         Fd := -1;
         Interfaces.C.Strings.Free (C_Path);
         return Outcome;
      end if;
      Interfaces.C.Strings.Free (C_Path);
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
   end Create;

   function Open
     (Path : String; Kind : Lock_Kind; Writable : Boolean;
      Item : out Lease) return Open_Outcome
   is
      C_Path : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      Fd : C_Int := -1;
      Info : aliased Stat_Record;
      Outcome : Open_Outcome;
      Code : C_Int;
      Ignored : C_Int;
   begin
      Reset (Item);
      Fd := C_Open
        (C_Path, (if Writable then O_Rdwr else O_Rdonly) + O_Cloexec + O_Nofollow, 0);
      if Fd < 0 then
         Code := Errno;
         Interfaces.C.Strings.Free (C_Path);
         return (if Code = 2 or else Code = 62 then Refused else Error);
      end if;
      Interfaces.C.Strings.Free (C_Path);
      if C_Fstat (Fd, Info'Access) /= 0 or else not Is_Valid (Info) then
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
      Info : aliased Stat_Record;
   begin
      if not Item.Held or else C_Fstat (C_Int (Item.Handle), Info'Access) /= 0
        or else Info.File_Size < 0
      then
         return -1;
      end if;
      return Long_Long_Integer (Info.File_Size);
   exception
      when others => return -1;
   end Size;

   function Identity (Item : Lease) return Lease_Identity is
      Info : aliased Stat_Record;
   begin
      if not Item.Held or else C_Fstat (C_Int (Item.Handle), Info'Access) /= 0 then
         return (others => <>);
      end if;
      return
        (Available => True,
         Volume => Interfaces.Unsigned_64 (Info.Device),
         Low => Interfaces.Unsigned_64 (Info.Inode), High => 0);
   exception
      when others => return (others => <>);
   end Identity;

   function Path_Matches (Item : Lease; Path : String) return Boolean is
      C_Path : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      Fd : C_Int := -1;
      Held_Info, Path_Info : aliased Stat_Record;
      Ignored : C_Int;
      Matches : Boolean;
   begin
      if not Item.Held then
         Interfaces.C.Strings.Free (C_Path);
         return False;
      end if;
      Fd := C_Open (C_Path, O_Rdonly + O_Cloexec + O_Nofollow, 0);
      Interfaces.C.Strings.Free (C_Path);
      Matches := Fd >= 0
        and then C_Fstat (C_Int (Item.Handle), Held_Info'Access) = 0
        and then C_Fstat (Fd, Path_Info'Access) = 0
        and then Is_Valid (Path_Info)
        and then Held_Info.Device = Path_Info.Device
        and then Held_Info.Inode = Path_Info.Inode;
      if Fd >= 0 then
         Ignored := C_Close (Fd);
      end if;
      return Matches;
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
