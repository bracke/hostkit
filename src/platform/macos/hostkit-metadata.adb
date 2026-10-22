with Ada.Calendar.Formatting;
with Ada.Strings.Unbounded;
with Ada.Strings.Fixed;
with GNAT.OS_Lib;

with Interfaces.C.Strings;
with System;
with Hostkit.Darwin_Symbols;

package body Hostkit.Metadata is
   use Ada.Strings.Unbounded;
   use type Ada.Calendar.Time;
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
   subtype C_S32 is Interfaces.C.int;
   subtype C_S64 is Interfaces.C.long;
   subtype C_Char is Interfaces.C.char;

   --  macOS has no statx, so this uses stat(2). Since Darwin's 64-bit inode
   --  transition the x86_64 symbols carry an $INODE64 suffix: the unsuffixed
   --  names still exist but describe the older, narrower struct, and binding
   --  those against this record would silently misread every field. arm64 has
   --  only the 64-bit-inode names; Hostkit.Darwin_Symbols picks per arch.

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
      Inode         : C_U64 := 0;
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

   --  statfs, not statvfs: Darwin's statvfs counts blocks in 32 bits, which
   --  overflows on any volume worth reporting. statfs carries 64-bit counts.
   type Fsid is array (1 .. 2) of C_S32
     with Convention => C;
   type Name_Buffer is array (1 .. 16) of C_Char
     with Convention => C;
   type Path_Buffer is array (1 .. 1_024) of C_Char
     with Convention => C;
   type Reserved_Array is array (1 .. 8) of C_U32
     with Convention => C;

   type Statfs_Record is record
      Block_Size       : C_U32 := 0;
      Io_Size          : C_S32 := 0;
      Blocks           : C_U64 := 0;
      Blocks_Free      : C_U64 := 0;
      Blocks_Available : C_U64 := 0;
      Nodes            : C_U64 := 0;
      Nodes_Free       : C_U64 := 0;
      Filesystem_Id    : Fsid := [others => 0];
      Owner            : C_U32 := 0;
      Kind             : C_U32 := 0;
      Flags            : C_U32 := 0;
      Sub_Kind         : C_U32 := 0;
      Type_Name        : Name_Buffer := [others => Interfaces.C.nul];
      Mounted_On       : Path_Buffer := [others => Interfaces.C.nul];
      Mounted_From     : Path_Buffer := [others => Interfaces.C.nul];
      Reserved         : Reserved_Array := [others => 0];
   end record
     with Convention => C;

   --  A layout that is wrong by even one byte does not fail loudly -- it reads
   --  the wrong field and reports plausible nonsense. Pin the sizes so the
   --  compiler catches any drift, on any host, before it can reach a Mac.
   pragma Compile_Time_Error
     (Stat_Record'Size /= 144 * 8,
      "Darwin struct stat (64-bit inode, x86_64) must be 144 bytes");
   pragma Compile_Time_Error
     (Statfs_Record'Size /= 2_168 * 8,
      "Darwin struct statfs (64-bit inode, x86_64) must be 2168 bytes");

   Mount_Read_Only : constant C_U32 := 16#0000_0001#;
   Darwin_Name_Max : constant Natural := 255;
   Permission_Mask : constant C_U16 := 8#7777#;

   type Passwd_Record is record
      Name     : Interfaces.C.Strings.chars_ptr;
      Password : Interfaces.C.Strings.chars_ptr;
      User_Id  : C_U32;
      Group_Id : C_U32;
      Change   : C_S64;
      Class    : Interfaces.C.Strings.chars_ptr;
      Gecos    : Interfaces.C.Strings.chars_ptr;
      Home     : Interfaces.C.Strings.chars_ptr;
      Shell    : Interfaces.C.Strings.chars_ptr;
      Expire   : C_S64;
   end record
     with Convention => C;

   type Passwd_Access is access all Passwd_Record;

   type Group_Record is record
      Name     : Interfaces.C.Strings.chars_ptr;
      Password : Interfaces.C.Strings.chars_ptr;
      Group_Id : C_U32;
      Members  : System.Address;
   end record
     with Convention => C;

   type Group_Access is access all Group_Record;

   function C_Stat
     (Path   : Interfaces.C.Strings.chars_ptr;
      Buffer : access Stat_Record) return C_Int
     with Import, Convention => C, External_Name => Hostkit.Darwin_Symbols.Stat;

   function C_Lstat
     (Path   : Interfaces.C.Strings.chars_ptr;
      Buffer : access Stat_Record) return C_Int
     with Import, Convention => C, External_Name => Hostkit.Darwin_Symbols.Lstat;

   function C_Statfs
     (Path   : Interfaces.C.Strings.chars_ptr;
      Buffer : access Statfs_Record) return C_Int
     with Import, Convention => C, External_Name => Hostkit.Darwin_Symbols.Statfs;

   function C_Chmod
     (Path : Interfaces.C.Strings.chars_ptr;
      Mode : C_U16) return C_Int
     with Import, Convention => C, External_Name => "chmod";

   function C_Open
     (Path : Interfaces.C.Strings.chars_ptr;
      Flags : C_Int) return C_Int
     with Import, Convention => C, External_Name => "open";

   function C_Close (Fd : C_Int) return C_Int
     with Import, Convention => C, External_Name => "close";

   function C_Fstat
     (Fd : C_Int; Buffer : access Stat_Record) return C_Int
     with Import, Convention => C, External_Name => Hostkit.Darwin_Symbols.Fstat;

   function C_Fstatat
     (Fd : C_Int; Path : Interfaces.C.Strings.chars_ptr;
      Buffer : access Stat_Record; Flags : C_Int) return C_Int
     with Import, Convention => C, External_Name => Hostkit.Darwin_Symbols.Fstatat;

   function C_Fchmod (Fd : C_Int; Mode : C_U16) return C_Int
     with Import, Convention => C, External_Name => "fchmod";

   function C_Fchmodat
     (Fd : C_Int; Path : Interfaces.C.Strings.chars_ptr;
      Mode : C_U16; Flags : C_Int) return C_Int
     with Import, Convention => C, External_Name => "fchmodat";

   function C_Fchown (Fd : C_Int; Owner, Group : C_U32) return C_Int
     with Import, Convention => C, External_Name => "fchown";

   function C_Linkat
     (Old_Fd : C_Int; Old_Path : Interfaces.C.Strings.chars_ptr;
      New_Fd : C_Int; New_Path : Interfaces.C.Strings.chars_ptr;
      Flags : C_Int) return C_Int
     with Import, Convention => C, External_Name => "linkat";

   function C_Unlinkat
     (Fd : C_Int; Path : Interfaces.C.Strings.chars_ptr;
      Flags : C_Int) return C_Int
     with Import, Convention => C, External_Name => "unlinkat";

   function C_Rmdir (Path : Interfaces.C.Strings.chars_ptr) return C_Int
     with Import, Convention => C, External_Name => "rmdir";

   function C_Mkdtemp (Template : System.Address) return Interfaces.C.Strings.chars_ptr
     with Import, Convention => C, External_Name => "mkdtemp";

   type Timeval is record
      Seconds      : C_S64;
      Microseconds : C_S64;
   end record
     with Convention => C;

   type Timeval_Array is array (Positive range 1 .. 2) of Timeval
     with Convention => C;

   function C_Utimes
     (Path  : Interfaces.C.Strings.chars_ptr;
      Times : access Timeval_Array) return C_Int
     with Import, Convention => C, External_Name => "utimes";

   function C_Chown
     (Path     : Interfaces.C.Strings.chars_ptr;
      User_Id  : C_U32;
      Group_Id : C_U32) return C_Int
     with Import, Convention => C, External_Name => "chown";

   function C_Getpwnam
     (Name : Interfaces.C.Strings.chars_ptr) return Passwd_Access
     with Import, Convention => C, External_Name => "getpwnam";

   function C_Getpwuid (Id : C_U32) return Passwd_Access
     with Import, Convention => C, External_Name => "getpwuid";

   function C_Getgrnam
     (Name : Interfaces.C.Strings.chars_ptr) return Group_Access
     with Import, Convention => C, External_Name => "getgrnam";

   function C_Getgrgid (Id : C_U32) return Group_Access
     with Import, Convention => C, External_Name => "getgrgid";

   procedure Safe_Free (Item : in out Interfaces.C.Strings.chars_ptr);

   procedure Safe_Free (Item : in out Interfaces.C.Strings.chars_ptr) is
   begin
      if Item /= Interfaces.C.Strings.Null_Ptr then
         Interfaces.C.Strings.Free (Item);
      end if;
   end Safe_Free;

   function Stat_Of (Path : String; Buffer : access Stat_Record) return Boolean;

   function Stat_Of
     (Path : String; Buffer : access Stat_Record) return Boolean
   is
      C_Path : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Path);
      Result : C_Int;
   begin
      Result := C_Stat (C_Path, Buffer);
      Interfaces.C.Strings.Free (C_Path);
      return Result = 0;

   exception
      when others =>
         Safe_Free (C_Path);
         return False;
   end Stat_Of;

   function File_Creation_Time
     (Path      : String;
      Available : out Boolean) return Ada.Calendar.Time
   is
      Buffer : aliased Stat_Record;
      --  The Unix epoch, in UTC: Ada.Calendar.Time_Of would read it as local
      --  midnight and shift every time by the zone's 1970 offset.
      Epoch  : constant Ada.Calendar.Time := Ada.Calendar.Formatting.Time_Of (1970, 1, 1, 0.0, Time_Zone => 0);
   begin
      Available := False;

      if not Stat_Of (Path, Buffer'Access) then
         return Ada.Calendar.Time_Of (1901, 1, 1);
      end if;

      --  Unlike Linux, Darwin always records a birth time.
      if Buffer.Birth_Time.Seconds <= 0 then
         return Ada.Calendar.Time_Of (1901, 1, 1);
      end if;

      Available := True;
      return Epoch + Duration (Buffer.Birth_Time.Seconds);

   exception
      when others =>
         Available := False;
         return Ada.Calendar.Time_Of (1901, 1, 1);
   end File_Creation_Time;

   function File_Access_Time
     (Path      : String;
      Available : out Boolean) return Ada.Calendar.Time
   is
      Buffer : aliased Stat_Record;
      --  The Unix epoch, in UTC: Ada.Calendar.Time_Of would read it as local
      --  midnight and shift every time by the zone's 1970 offset.
      Epoch  : constant Ada.Calendar.Time := Ada.Calendar.Formatting.Time_Of (1970, 1, 1, 0.0, Time_Zone => 0);
   begin
      Available := False;

      if not Stat_Of (Path, Buffer'Access) then
         return Ada.Calendar.Time_Of (1901, 1, 1);
      end if;

      if Buffer.Access_Time.Seconds < 0 then
         return Ada.Calendar.Time_Of (1901, 1, 1);
      end if;

      Available := True;
      return Epoch + Duration (Buffer.Access_Time.Seconds);

   exception
      when others =>
         Available := False;
         return Ada.Calendar.Time_Of (1901, 1, 1);
   end File_Access_Time;

   function Volume_Capacity_Of (Path : String) return Volume_Capacity is
      C_Path : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Path);
      Buffer : aliased Statfs_Record;
      Result : C_Int;
      Answer : Volume_Capacity;
   begin
      Result := C_Statfs (C_Path, Buffer'Access);
      Interfaces.C.Strings.Free (C_Path);

      if Result /= 0 then
         return Answer;
      end if;

      Answer.Available := True;
      Answer.Capacity_Bytes :=
        Long_Long_Integer (Buffer.Blocks)
        * Long_Long_Integer (Buffer.Block_Size);
      Answer.Free_Bytes :=
        Long_Long_Integer (Buffer.Blocks_Available)
        * Long_Long_Integer (Buffer.Block_Size);

      Answer.Inode_Count := Long_Long_Integer (Buffer.Nodes);
      Answer.Free_Inode_Count := Long_Long_Integer (Buffer.Nodes_Free);
      Answer.Inodes_Known := True;

      --  statfs reports no per-volume name limit; every Darwin filesystem this
      --  application can reach uses the POSIX 255.
      Answer.Name_Max := Darwin_Name_Max;
      Answer.Name_Max_Known := True;

      Answer.Read_Only := (Buffer.Flags and Mount_Read_Only) /= 0;
      Answer.Read_Only_Known := True;

      return Answer;

   exception
      when others =>
         Safe_Free (C_Path);
         return (others => <>);
   end Volume_Capacity_Of;

   function File_Permission_Bits
     (Path      : String;
      Available : out Boolean) return Natural
   is
      Buffer : aliased Stat_Record;
   begin
      Available := False;

      if not Stat_Of (Path, Buffer'Access) then
         return 0;
      end if;

      Available := True;
      return Natural (Buffer.Mode and Permission_Mask);

   exception
      when others =>
         Available := False;
         return 0;
   end File_Permission_Bits;

   function Set_Permissions
     (Path : String;
      Mode : Natural) return Boolean
   is
      C_Path : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Path);
      Result : C_Int;
   begin
      Result := C_Chmod (C_Path, C_U16 (Mode mod 8#10000#));
      Interfaces.C.Strings.Free (C_Path);
      return Result = 0;

   exception
      when others =>
         Safe_Free (C_Path);
         return False;
   end Set_Permissions;

   function Set_File_Times
     (Path          : String;
      Access_Time   : Long_Long_Integer;
      Modified_Time : Long_Long_Integer)
      return Boolean
   is
      C_Path : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Path);
      Times  : aliased Timeval_Array :=
        [1 => (Seconds      => C_S64 (Access_Time),
               Microseconds => 0),
         2 => (Seconds      => C_S64 (Modified_Time),
               Microseconds => 0)];
      Result : C_Int;
   begin
      Result := C_Utimes (C_Path, Times'Access);
      Interfaces.C.Strings.Free (C_Path);
      return Result = 0;

   exception
      when others =>
         Safe_Free (C_Path);
         return False;
   end Set_File_Times;

   function Permissions_Supported return Boolean is
   begin
      return True;
   end Permissions_Supported;

   procedure File_Ownership
     (Path      : String;
      User_Id   : out Natural;
      Group_Id  : out Natural;
      Available : out Boolean)
   is
      Buffer : aliased Stat_Record;
   begin
      User_Id := 0;
      Group_Id := 0;
      Available := False;

      if not Stat_Of (Path, Buffer'Access) then
         return;
      end if;

      User_Id := Natural (Buffer.User_Id);
      Group_Id := Natural (Buffer.Group_Id);
      Available := True;

   exception
      when others =>
         User_Id := 0;
         Group_Id := 0;
         Available := False;
   end File_Ownership;

   procedure File_Mode_And_Ownership
     (Path                : String;
      Mode_Bits           : out Natural;
      Mode_Available      : out Boolean;
      User_Id             : out Natural;
      Group_Id            : out Natural;
      Ownership_Available : out Boolean) is
   begin
      Mode_Bits := File_Permission_Bits (Path, Mode_Available);
      File_Ownership (Path, User_Id, Group_Id, Ownership_Available);
   end File_Mode_And_Ownership;

   --  No stamp this fine is read here yet: unknown, never a guess.
   function Change_Stamp
     (Path      : String;
      Available : out Boolean)
      return String
   is
      pragma Unreferenced (Path);
   begin
      Available := False;
      return "";
   end Change_Stamp;

   function Entry_Identity_Of (Path : String) return Entry_Identity is
      C_Path : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      Info   : aliased Stat_Record;
      Status : C_Int;
   begin
      Status := C_Lstat (C_Path, Info'Access);
      Interfaces.C.Strings.Free (C_Path);
      if Status /= 0 then
         return (others => <>);
      end if;
      return
        (Available       => True,
         Volume          => Identity_Field (Info.Device),
         File_Number     => Identity_Field (Info.Inode),
         Generation_High => Identity_Field (Info.Birth_Time.Seconds),
         Generation_Low  => Identity_Field (Info.Birth_Time.Nanoseconds));
   exception
      when others =>
         Safe_Free (C_Path);
         return (others => <>);
   end Entry_Identity_Of;

   function Update_Entry_Metadata
     (Path           : String;
      Expected       : Entry_Identity;
      Check_Expected : Boolean;
      Kind           : Metadata_Update_Kind;
      Value          : Identity_Field;
      Group          : Identity_Field;
      Max_Previous   : Identity_Field;
      Owner_Name     : String := "";
      Group_Name     : String := "") return Metadata_Update_Result
   is
      pragma Unreferenced (Owner_Name, Group_Name);
      O_Rdonly    : constant C_Int := 0;
      O_Evtonly   : constant C_Int := 16#8000#;
      O_Nofollow  : constant C_Int := 16#0100#;
      O_Directory : constant C_Int := 16#10_0000#;
      O_Cloexec   : constant C_Int := 16#100_0000#;
      At_Fdcwd    : constant C_Int := -2;
      At_Nofollow : constant C_Int := 16#20#;
      File_Type   : constant C_U16 := 16#F000#;
      Link_Type   : constant C_U16 := 16#A000#;

      function Identity_Of (Info : Stat_Record) return Entry_Identity is
        (Available       => True,
         Volume          => Identity_Field (Info.Device),
         File_Number     => Identity_Field (Info.Inode),
         Generation_High => Identity_Field (Info.Birth_Time.Seconds),
         Generation_Low  => Identity_Field (Info.Birth_Time.Nanoseconds));

      function Link_Fallback
        (Fallback_Expected : Entry_Identity;
         Must_Match        : Boolean) return Metadata_Update_Result
      is
         Slash : constant Natural :=
           Ada.Strings.Fixed.Index (Path, "/", Ada.Strings.Backward);
         Parent : constant String :=
           (if Slash = 0 then "."
            elsif Slash = Path'First then "/"
            else Path (Path'First .. Slash - 1));
         Template : aliased Interfaces.C.char_array :=
           Interfaces.C.To_C (Parent & "/.hostkit-mode-XXXXXX");
         Created : Interfaces.C.Strings.chars_ptr;
         C_Temp : Interfaces.C.Strings.chars_ptr :=
           Interfaces.C.Strings.Null_Ptr;
         C_Path : Interfaces.C.Strings.chars_ptr :=
           Interfaces.C.Strings.New_String (Path);
         C_Inode : Interfaces.C.Strings.chars_ptr :=
           Interfaces.C.Strings.New_String ("inode");
         Directory : C_Int := -1;
         Linked : Boolean := False;
         Info : aliased Stat_Record;
         Answer : Metadata_Update_Result;
         Ignored : C_Int;

         procedure Clean is
         begin
            if Linked and then Directory >= 0 then
               Ignored := C_Unlinkat (Directory, C_Inode, 0);
               Linked := False;
            end if;
            if Directory >= 0 then
               Ignored := C_Close (Directory);
               Directory := -1;
            end if;
            if C_Temp /= Interfaces.C.Strings.Null_Ptr then
               Ignored := C_Rmdir (C_Temp);
            end if;
            Safe_Free (C_Temp);
            Safe_Free (C_Path);
            Safe_Free (C_Inode);
         end Clean;
      begin
         Created := C_Mkdtemp (Template'Address);
         if Created = Interfaces.C.Strings.Null_Ptr then
            Clean;
            return Answer;
         end if;
         C_Temp := Interfaces.C.Strings.New_String
           (Interfaces.C.Strings.Value (Created));
         Directory := C_Open
           (C_Temp, O_Rdonly + O_Directory + O_Cloexec);
         Linked := Directory >= 0 and then C_Linkat
           (At_Fdcwd, C_Path, Directory, C_Inode, 0) = 0;
         if not Linked
           or else C_Fstatat
             (Directory, C_Inode, Info'Access, At_Nofollow) /= 0
           or else (Info.Mode and File_Type) = Link_Type
         then
            Clean;
            return Answer;
         end if;
         Answer.Identity := Identity_Of (Info);
         if Must_Match and then Answer.Identity /= Fallback_Expected then
            Clean;
            return Answer;
         end if;
         Answer.Previous := Identity_Field (Info.Mode and Permission_Mask);
         Answer.Success := C_Fchmodat
           (Directory, C_Inode, C_U16 (Value mod 8#10000#), 0) = 0;
         Clean;
         return Answer;
      exception
         when others =>
            Clean;
            return (others => <>);
      end Link_Fallback;

      C_Path : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Path);
      Fd     : C_Int := -1;
      Info   : aliased Stat_Record;
      Answer : Metadata_Update_Result;
      Ignored : C_Int;

      procedure Close is
      begin
         if Fd >= 0 then
            Ignored := C_Close (Fd);
            Fd := -1;
         end if;
      end Close;
   begin
      Fd := C_Open (C_Path, O_Evtonly + O_Nofollow + O_Cloexec);
      Interfaces.C.Strings.Free (C_Path);
      if Fd < 0 then
         if Kind = Update_Permissions then
            return Link_Fallback (Expected, Check_Expected);
         end if;
         return Answer;
      end if;
      if C_Fstat (Fd, Info'Access) /= 0
        or else (Info.Mode and File_Type) = Link_Type
      then
         Close;
         return Answer;
      end if;
      Answer.Identity := Identity_Of (Info);
      if Check_Expected and then Answer.Identity /= Expected then
         Close;
         return Answer;
      end if;

      if Kind = Update_Ownership then
         Answer.Previous := Identity_Field (Info.User_Id);
         Answer.Previous_Group := Identity_Field (Info.Group_Id);
         if Value <= Identity_Field (C_U32'Last)
           and then Group <= Identity_Field (C_U32'Last)
           and then Answer.Previous <= Max_Previous
           and then Answer.Previous_Group <= Max_Previous
         then
            Answer.Success := C_Fchown
              (Fd, C_U32 (Value), C_U32 (Group)) = 0;
         end if;
      else
         Answer.Previous := Identity_Field (Info.Mode and Permission_Mask);
         Answer.Success := C_Fchmod
           (Fd, C_U16 (Value mod 8#10000#)) = 0;
         if not Answer.Success then
            declare
               Held : Interfaces.C.Strings.chars_ptr :=
                 Interfaces.C.Strings.New_String
                   ("/dev/fd/" & Ada.Strings.Fixed.Trim
                      (C_Int'Image (Fd), Ada.Strings.Both));
            begin
               Answer.Success := C_Chmod
                 (Held, C_U16 (Value mod 8#10000#)) = 0;
               Interfaces.C.Strings.Free (Held);
            exception
               when others =>
                  Safe_Free (Held);
            end;
         end if;
         if not Answer.Success then
            Answer := Link_Fallback (Answer.Identity, True);
         end if;
      end if;
      Close;
      return Answer;
   exception
      when others =>
         Safe_Free (C_Path);
         Close;
         return (others => <>);
   end Update_Entry_Metadata;

   function Entry_Revision_Of (Path : String) return Entry_Revision is
      C_Path : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      Info   : aliased Stat_Record;
      Status : C_Int;
   begin
      Status := C_Lstat (C_Path, Info'Access);
      Interfaces.C.Strings.Free (C_Path);
      if Status /= 0 then
         return (others => <>);
      end if;
      return
        (Available            => True,
         Modified_Seconds     => Identity_Field (Info.Modified_Time.Seconds),
         Modified_Nanoseconds => Identity_Field (Info.Modified_Time.Nanoseconds),
         Changed_Seconds      => Identity_Field (Info.Change_Time.Seconds),
         Changed_Nanoseconds  => Identity_Field (Info.Change_Time.Nanoseconds),
         Size                 => Identity_Field (Info.Size),
         Mode                 => Identity_Field (Info.Mode),
         User_Id              => Identity_Field (Info.User_Id),
         Group_Id             => Identity_Field (Info.Group_Id));
   exception
      when others =>
         Safe_Free (C_Path);
         return (others => <>);
   end Entry_Revision_Of;

   function Same_File (Left : String; Right : String) return Boolean is
      L_Buffer : aliased Stat_Record;
      R_Buffer : aliased Stat_Record;
   begin
      if not Stat_Of (Left, L_Buffer'Access)
        or else not Stat_Of (Right, R_Buffer'Access)
      then
         return False;
      end if;

      return L_Buffer.Inode = R_Buffer.Inode and then L_Buffer.Device = R_Buffer.Device;
   exception
      when others =>
         return False;
   end Same_File;

   function Device_Id
     (Path      : String;
      Available : out Boolean)
      return Long_Long_Integer
   is
      Buffer : aliased Stat_Record;
   begin
      if not Stat_Of (Path, Buffer'Access) then
         Available := False;
         return 0;
      end if;

      Available := True;
      return Long_Long_Integer (Buffer.Device);
   exception
      when others =>
         Available := False;
         return 0;
   end Device_Id;

   function User_Id_For_Name
     (Name  : String;
      Found : out Boolean) return Natural
   is
      C_Name : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Name);
      Item   : Passwd_Access;
   begin
      Found := False;
      Item := C_Getpwnam (C_Name);
      Interfaces.C.Strings.Free (C_Name);

      if Item = null then
         return 0;
      end if;

      Found := True;
      return Natural (Item.User_Id);

   exception
      when others =>
         Safe_Free (C_Name);
         Found := False;
         return 0;
   end User_Id_For_Name;

   function Group_Id_For_Name
     (Name  : String;
      Found : out Boolean) return Natural
   is
      C_Name : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Name);
      Item   : Group_Access;
   begin
      Found := False;
      Item := C_Getgrnam (C_Name);
      Interfaces.C.Strings.Free (C_Name);

      if Item = null then
         return 0;
      end if;

      Found := True;
      return Natural (Item.Group_Id);

   exception
      when others =>
         Safe_Free (C_Name);
         Found := False;
         return 0;
   end Group_Id_For_Name;

   function User_Name_For_Id (Id : Natural) return String is
      Item : constant Passwd_Access := C_Getpwuid (C_U32 (Id));
   begin
      if Item = null or else Item.Name = Interfaces.C.Strings.Null_Ptr then
         return "";
      end if;

      return Interfaces.C.Strings.Value (Item.Name);

   exception
      when others =>
         return "";
   end User_Name_For_Id;

   function Group_Name_For_Id (Id : Natural) return String is
      Item : constant Group_Access := C_Getgrgid (C_U32 (Id));
   begin
      if Item = null or else Item.Name = Interfaces.C.Strings.Null_Ptr then
         return "";
      end if;

      return Interfaces.C.Strings.Value (Item.Name);

   exception
      when others =>
         return "";
   end Group_Name_For_Id;

   function Set_Ownership
     (Path     : String;
      User_Id  : Natural;
      Group_Id : Natural) return Boolean
   is
      C_Path : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Path);
      Result : C_Int;
   begin
      Result := C_Chown (C_Path, C_U32 (User_Id), C_U32 (Group_Id));
      Interfaces.C.Strings.Free (C_Path);
      return Result = 0;

   exception
      when others =>
         Safe_Free (C_Path);
         return False;
   end Set_Ownership;

   function Mode_Bits_Are_Native return Boolean is
   begin
      return True;
   end Mode_Bits_Are_Native;

   function Ownership_Supported return Boolean is
   begin
      return True;
   end Ownership_Supported;

end Hostkit.Metadata;
