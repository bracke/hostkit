with Ada.Calendar.Formatting;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Interfaces.C;

with Interfaces.C.Strings;

with GNAT.OS_Lib;

with Hostkit.Host;
with Hostkit.Posix;
with Hostkit.Posix.Accounts;
with Hostkit.Linux_Abi;
with Hostkit.Metadata.Natural_Ids;

package body Hostkit.Metadata is
   use type Hostkit.File_Identities.Entry_Identity;
   use Ada.Strings.Unbounded;
   use type Ada.Calendar.Time;
   use type Interfaces.C.int;
   use type Interfaces.C.long;
   use type Interfaces.C.unsigned;
   use type Interfaces.C.unsigned_long;
   use type Interfaces.C.unsigned_short;
   use type Interfaces.C.Strings.chars_ptr;
   use type Interfaces.Integer_64;
   use type Interfaces.Unsigned_64;

   subtype C_Int is Interfaces.C.int;
   subtype C_Unsigned is Interfaces.C.unsigned;
   subtype C_U16 is Interfaces.C.unsigned_short;
   subtype C_U32 is Interfaces.C.unsigned;
   subtype C_U64 is Interfaces.C.unsigned_long;
   subtype C_S64 is Interfaces.C.long;
   subtype C_ULong is Interfaces.C.unsigned_long;

   --  O_NOFOLLOW differs on arm, powerpc and m68k; the x86 value there is
   --  O_LARGEFILE, and the held entry would be a link's target.
   Machine_O_Nofollow : constant C_Int := Hostkit.Linux_Abi.O_Nofollow (Hostkit.Host.Machine_Name);
   Machine_O_Directory : constant C_Int := Hostkit.Linux_Abi.O_Directory (Hostkit.Host.Machine_Name);

   At_FDCWD : constant C_Int := -100;
   At_Symlink_Nofollow : constant C_Unsigned := 16#100#;
   Statx_Btime : constant C_Unsigned := 16#800#;
   Statx_Atime : constant C_Unsigned := 16#20#;
   Statvfs_Read_Only : constant C_ULong := 1;

   type U64_Array is array (Positive range <>) of C_U64
     with Convention => C;

   --  struct statx, one layout for every Linux body (Hostkit.Linux_Abi):
   --  Device_* there is stx_dev, the device that holds the entry -- the one
   --  to compare for "same file" or "same volume".
   subtype Statx_Record is Hostkit.Linux_Abi.Statx_Record;
   subtype Statx_S64 is Hostkit.Linux_Abi.C_S64;
   subtype Statx_U64 is Hostkit.Linux_Abi.C_U64;

   type Statvfs_Record is record
      Block_Size             : C_ULong;
      Fragment_Size          : C_ULong;
      Blocks                 : C_ULong;
      Blocks_Free            : C_ULong;
      Blocks_Available       : C_ULong;
      Files                  : C_ULong;
      Files_Free             : C_ULong;
      Files_Available        : C_ULong;
      Filesystem_Id          : C_ULong;
      Flags                  : C_ULong;
      Name_Max               : C_ULong;
      Spare                  : U64_Array (1 .. 6);
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

   function Statvfs
     (Pathname : Interfaces.C.Strings.chars_ptr;
      Buffer   : access Statvfs_Record)
      return C_Int
     with Import, Convention => C, External_Name => "statvfs";

   function Chown
     (Pathname : Interfaces.C.Strings.chars_ptr;
      Owner    : C_U32;
      Group    : C_U32)
      return C_Int
     with Import, Convention => C, External_Name => "chown";

   function Chmod
     (Pathname : Interfaces.C.Strings.chars_ptr;
      Mode     : C_Unsigned)
      return C_Int
     with Import, Convention => C, External_Name => "chmod";

   function C_Open
     (Pathname : Interfaces.C.Strings.chars_ptr;
      Flags    : C_Int) return C_Int
     with Import, Convention => C, External_Name => "open";

   function C_Openat
     (Fd       : C_Int;
      Pathname : Interfaces.C.Strings.chars_ptr;
      Flags    : C_Int) return C_Int
     with Import, Convention => C, External_Name => "openat";

   function C_Close (Fd : C_Int) return C_Int
     with Import, Convention => C, External_Name => "close";

   function C_Fchownat
     (Fd    : C_Int;
      Path  : Interfaces.C.Strings.chars_ptr;
      Owner : C_U32;
      Group : C_U32;
      Flags : C_Int) return C_Int
     with Import, Convention => C, External_Name => "fchownat";

   type Timeval is record
      Seconds      : C_S64;
      Microseconds : C_S64;
   end record
     with Convention => C;

   type Timeval_Array is array (Positive range 1 .. 2) of Timeval
     with Convention => C;

   function Utimes
     (Pathname : Interfaces.C.Strings.chars_ptr;
      Times    : access Timeval_Array)
      return C_Int
     with Import, Convention => C, External_Name => "utimes";

   Statx_Mode      : constant C_Unsigned := 16#2#;
   Permission_Mask : constant C_U16 := 8#7777#;

   procedure Safe_Free
     (Pointer : in out Interfaces.C.Strings.chars_ptr) is
   begin
      if Pointer /= Interfaces.C.Strings.Null_Ptr then
         begin
            Interfaces.C.Strings.Free (Pointer);
         exception
            when others =>
               null;
         end;
      end if;
   end Safe_Free;

   function File_Creation_Time
     (Path      : String;
      Available : out Boolean)
      return Ada.Calendar.Time
   is
      C_Path : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      Info   : aliased Statx_Record;
      Status : C_Int;
      --  The Unix epoch, in UTC: Ada.Calendar.Time_Of would read it as local
      --  midnight and shift every time by the zone's 1970 offset.
      Epoch  : constant Ada.Calendar.Time := Ada.Calendar.Formatting.Time_Of (1970, 1, 1, 0.0, Time_Zone => 0);
   begin
      Available := False;
      Status := Statx (At_FDCWD, C_Path, At_Symlink_Nofollow, Statx_Btime, Info'Access);
      Interfaces.C.Strings.Free (C_Path);

      if Status = 0 and then (Info.Mask and Statx_Btime) /= 0 and then Info.Birth_Time.Seconds >= 0 then
         Available := True;
         return Epoch + Duration (Info.Birth_Time.Seconds) + Duration (Info.Birth_Time.Nanoseconds) / 1_000_000_000.0;
      end if;

      return Ada.Calendar.Time_Of (1901, 1, 1);
   exception
      when others =>
         Safe_Free (C_Path);
         Available := False;
         return Ada.Calendar.Time_Of (1901, 1, 1);
   end File_Creation_Time;

   function File_Access_Time
     (Path      : String;
      Available : out Boolean)
      return Ada.Calendar.Time
   is
      C_Path : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      Info   : aliased Statx_Record;
      Status : C_Int;
      --  The Unix epoch, in UTC: Ada.Calendar.Time_Of would read it as local
      --  midnight and shift every time by the zone's 1970 offset.
      Epoch  : constant Ada.Calendar.Time := Ada.Calendar.Formatting.Time_Of (1970, 1, 1, 0.0, Time_Zone => 0);
   begin
      Available := False;
      Status := Statx (At_FDCWD, C_Path, 0, Statx_Atime, Info'Access);
      Interfaces.C.Strings.Free (C_Path);

      if Status = 0 and then (Info.Mask and Statx_Atime) /= 0 and then Info.Access_Time.Seconds >= 0 then
         Available := True;
         return Epoch + Duration (Info.Access_Time.Seconds) + Duration (Info.Access_Time.Nanoseconds) / 1_000_000_000.0;
      end if;

      return Ada.Calendar.Time_Of (1901, 1, 1);
   exception
      when others =>
         Safe_Free (C_Path);
         Available := False;
         return Ada.Calendar.Time_Of (1901, 1, 1);
   end File_Access_Time;

   function Volume_Capacity_Of (Path : String) return Volume_Capacity is
      --  The counts saturate (Hostkit.Posix): FUSE and network filesystems
      --  answer UINT64_MAX for what they do not count.
      function Saturating_Natural (Value : C_ULong) return Natural is
        (Hostkit.Posix.Saturating_Natural (Interfaces.Unsigned_64 (Value)));

      function Saturating_Long_Long (Value : C_ULong) return Long_Long_Integer is
        (Hostkit.Posix.Saturating_Count (Interfaces.Unsigned_64 (Value)));

      function Saturating_Byte_Count (Blocks : C_ULong; Fragment_Size : C_ULong) return Long_Long_Integer is
        (Hostkit.Posix.Saturating_Byte_Count (Interfaces.Unsigned_64 (Blocks), Interfaces.Unsigned_64 (Fragment_Size)));

      C_Path : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      Data   : aliased Statvfs_Record;
      Status : C_Int;
      Result : Volume_Capacity;
   begin
      Status := Statvfs (C_Path, Data'Access);
      Interfaces.C.Strings.Free (C_Path);
      if Status = 0 then
         Result.Read_Only := (Data.Flags and Statvfs_Read_Only) /= 0;
         Result.Read_Only_Known := True;
         if Data.Name_Max > 0 then
            Result.Name_Max := Saturating_Natural (Data.Name_Max);
            Result.Name_Max_Known := True;
         end if;
         if Data.Files > 0 then
            Result.Inode_Count := Saturating_Long_Long (Data.Files);
            Result.Free_Inode_Count := Saturating_Long_Long (Data.Files_Free);
            Result.Inodes_Known := True;
         end if;
         if Data.Fragment_Size > 0 and then Data.Blocks > 0 then
            Result.Capacity_Bytes := Saturating_Byte_Count (Data.Blocks, Data.Fragment_Size);
            Result.Free_Bytes := Saturating_Byte_Count (Data.Blocks_Available, Data.Fragment_Size);
            Result.Available := True;
         end if;
      end if;
      return Result;
   exception
      when others =>
         Safe_Free (C_Path);
         return (others => <>);
   end Volume_Capacity_Of;

   function File_Permission_Bits
     (Path      : String;
      Available : out Boolean)
      return Natural
   is
      C_Path : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      Info   : aliased Statx_Record;
      Status : C_Int;
   begin
      Available := False;
      Status := Statx (At_FDCWD, C_Path, 0, Statx_Mode, Info'Access);
      Interfaces.C.Strings.Free (C_Path);

      if Status = 0 then
         Available := True;
         return Natural (Info.Mode and Permission_Mask);
      end if;

      return 0;
   exception
      when others =>
         Safe_Free (C_Path);
         Available := False;
         return 0;
   end File_Permission_Bits;

   function Set_Permissions
     (Path : String;
      Mode : Natural)
      return Boolean
   is
      C_Path : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      Status : C_Int;
   begin
      Status := Chmod (C_Path, C_Unsigned (Mode mod 8#10000#));
      Interfaces.C.Strings.Free (C_Path);
      return Status = 0;
   exception
      when others =>
         Safe_Free (C_Path);
         return False;
   end Set_Permissions;

   --  Mode bits are the whole of access here: exactly what Set_Permissions
   --  sets.
   function Set_Exact_Permissions
     (Path : String;
      Mode : Natural)
      return Boolean is (Set_Permissions (Path, Mode));

   --  Access here is mode bits, which a rename leaves as they were.
   function Inherit_From_Parent (Path : String) return Boolean is
      pragma Unreferenced (Path);
   begin
      return True;
   end Inherit_From_Parent;

   function Set_File_Times
     (Path          : String;
      Access_Time   : Long_Long_Integer;
      Modified_Time : Long_Long_Integer)
      return Boolean
   is
      C_Path : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      Times  : aliased Timeval_Array :=
        [1 => (Seconds      => C_S64 (Access_Time),
               Microseconds => 0),
         2 => (Seconds      => C_S64 (Modified_Time),
               Microseconds => 0)];
      Status : C_Int;
   begin
      Status := Utimes (C_Path, Times'Access);
      Interfaces.C.Strings.Free (C_Path);
      return Status = 0;
   exception
      when others =>
         Safe_Free (C_Path);
         return False;
   end Set_File_Times;

   function Permissions_Supported return Boolean is
   begin
      return True;
   end Permissions_Supported;

   Statx_Uid : constant C_Unsigned := 16#8#;
   Statx_Gid : constant C_Unsigned := 16#10#;

   procedure File_Ownership
     (Path      : String;
      User_Id   : out Account_Id;
      Group_Id  : out Account_Id;
      Available : out Boolean)
   is
      C_Path : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      Info   : aliased Statx_Record;
      Status : C_Int;
   begin
      User_Id := 0;
      Group_Id := 0;
      Available := False;
      Status := Statx (At_FDCWD, C_Path, 0, Statx_Uid or Statx_Gid, Info'Access);
      Interfaces.C.Strings.Free (C_Path);

      if Status = 0 then
         Available := True;
         User_Id := Account_Id (Info.User_Id);
         Group_Id := Account_Id (Info.Group_Id);
      end if;
   exception
      when others =>
         Safe_Free (C_Path);
         User_Id := 0;
         Group_Id := 0;
         Available := False;
   end File_Ownership;

   Statx_Ino : constant C_Unsigned := 16#100#;

   Statx_Mtime : constant C_Unsigned := 16#40#;
   Statx_Ctime : constant C_Unsigned := 16#80#;
   Statx_Size  : constant C_Unsigned := 16#200#;

   function Change_Stamp
     (Path      : String;
      Available : out Boolean)
      return String
   is
      C_Path : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      Info   : aliased Statx_Record;
      Status : C_Int;
      Wanted : constant C_Unsigned := Statx_Mtime or Statx_Ctime or Statx_Size or Statx_Ino;
   begin
      Available := False;
      Status := Statx (At_FDCWD, C_Path, 0, Wanted, Info'Access);
      Interfaces.C.Strings.Free (C_Path);
      if Status /= 0 or else (C_Unsigned (Info.Mask) and Wanted) /= Wanted then
         return "";
      end if;
      Available := True;
      return Statx_S64'Image (Info.Modified_Time.Seconds) & "." & C_U32'Image (Info.Modified_Time.Nanoseconds)
        & Statx_S64'Image (Info.Change_Time.Seconds) & "." & C_U32'Image (Info.Change_Time.Nanoseconds)
        & Statx_U64'Image (Info.Size) & Statx_U64'Image (Info.Inode);
   exception
      when others =>
         Safe_Free (C_Path);
         Available := False;
         return "";
   end Change_Stamp;

   --  An entry's identity from its statx: the holding device and the inode,
   --  told apart from a reuse of that inode by the birth time where the
   --  filesystem keeps one. Where it does not (STATX_BTIME absent: ext2/3,
   --  older tmpfs, many network filesystems) the generation is zero on
   --  every read of every entry there, so two reads of one entry still
   --  compare equal; only the inode-reuse guard is lost on such a volume.
   function Identity_Of (Info : Statx_Record) return Entry_Identity is
     (Available       => True,
      Volume          => Interfaces.Shift_Left (Identity_Field (Info.Device_Major), 32)
        or Identity_Field (Info.Device_Minor),
      File_Number     => Identity_Field (Info.Inode),
      Generation_High =>
        (if (Info.Mask and Statx_Btime) /= 0 then Identity_Field'Mod (Info.Birth_Time.Seconds) else 0),
      Generation_Low  =>
        (if (Info.Mask and Statx_Btime) /= 0 then Identity_Field (Info.Birth_Time.Nanoseconds) else 0));

   function Entry_Identity_Of (Path : String) return Entry_Identity is
      C_Path : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      Info   : aliased Statx_Record;
      Status : C_Int;
   begin
      --  The birth time is asked for, not required.
      Status := Statx (At_FDCWD, C_Path, At_Symlink_Nofollow, Statx_Ino or Statx_Btime, Info'Access);
      Interfaces.C.Strings.Free (C_Path);
      if Status /= 0 or else (Info.Mask and Statx_Ino) /= Statx_Ino then
         return (others => <>);
      end if;
      return Identity_Of (Info);
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
      Group_Name     : String := "";
      Access_Text    : String := "";
      Beneath_Root   : String := "";
      Relative_Path  : String := "") return Metadata_Update_Result
   is
      --  The mode is the whole access record here.
      pragma Unreferenced (Owner_Name, Group_Name, Access_Text);
      O_Path        : constant C_Int := 16#20_0000#;
      O_Directory   : constant C_Int := Machine_O_Directory;
      O_Nofollow    : constant C_Int := Machine_O_Nofollow;
      O_Cloexec     : constant C_Int := 16#08_0000#;
      At_Empty_Path : constant C_Int := 16#1000#;
      File_Type     : constant C_U16 := 16#F000#;
      Link_Type     : constant C_U16 := 16#A000#;
      E_Noent       : constant := 2;
      E_Inval       : constant := 22;
      E_Loop        : constant := 40;
      E_Opnotsupp   : constant := 95;
      --  What the update needs; the birth time is asked for besides, for the
      --  identity, and is not required (Identity_Of).
      Wanted        : constant C_Unsigned :=
        Statx_Ino or Statx_Mode or Statx_Uid or Statx_Gid;
      C_Path        : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.Null_Ptr;
      Empty         : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String ("");
      Fd            : C_Int := -1;
      Info          : aliased Statx_Record;
      Answer        : Metadata_Update_Result;

      function Open_Beneath return C_Int is
         Held  : C_Int := -1;
         Start : Positive := Relative_Path'First;

         procedure Open_Part (Part : String; Last : Boolean) is
            C_Part : Interfaces.C.Strings.chars_ptr :=
              Interfaces.C.Strings.New_String (Part);
            Child  : C_Int;
            Error  : Integer;
            Ignored : C_Int;
         begin
            Child := C_Openat
              (Held, C_Part,
               O_Path + O_Nofollow + O_Cloexec
               + (if Last then 0 else O_Directory));
            Interfaces.C.Strings.Free (C_Part);
            if Child < 0 then
               Error := GNAT.OS_Lib.Errno;
               Ignored := C_Close (Held);
               Held := -1;
               GNAT.OS_Lib.Set_Errno (Error);
            else
               Ignored := C_Close (Held);
               Held := Child;
            end if;
         exception
            when others =>
               Safe_Free (C_Part);
               if Held >= 0 then
                  Ignored := C_Close (Held);
                  Held := -1;
               end if;
         end Open_Part;
      begin
         if (for some C of Beneath_Root => C = ASCII.NUL)
           or else (for some C of Relative_Path => C = ASCII.NUL)
         then
            GNAT.OS_Lib.Set_Errno (E_Inval);
            return -1;
         elsif Relative_Path'Length > 0
           and then Relative_Path (Relative_Path'First) = '/'
         then
            GNAT.OS_Lib.Set_Errno (E_Inval);
            return -1;
         end if;
         declare
            C_Root : Interfaces.C.Strings.chars_ptr :=
              Interfaces.C.Strings.New_String
                (if Beneath_Root = "" then "." else Beneath_Root);
         begin
            Held := C_Open
              (C_Root, O_Path + O_Nofollow + O_Cloexec
               + (if Relative_Path = "" then 0 else O_Directory));
            Interfaces.C.Strings.Free (C_Root);
         exception
            when others =>
               Safe_Free (C_Root);
               return -1;
         end;
         if Held < 0 or else Relative_Path = "" then
            return Held;
         end if;
         for Index in Relative_Path'First .. Relative_Path'Last + 1 loop
            if Index > Relative_Path'Last or else Relative_Path (Index) = '/' then
               declare
                  Part : constant String := Relative_Path (Start .. Index - 1);
                  Last : constant Boolean := Index > Relative_Path'Last;
               begin
                  if Part = ".." then
                     declare
                        Ignored : C_Int := C_Close (Held);
                        pragma Unreferenced (Ignored);
                     begin
                        Held := -1;
                     end;
                     GNAT.OS_Lib.Set_Errno (E_Inval);
                     return -1;
                  elsif Part /= "" and then Part /= "." then
                     Open_Part (Part, Last);
                     exit when Held < 0;
                  end if;
               end;
               Start := Index + 1;
            end if;
         end loop;
         return Held;
      end Open_Beneath;

      procedure Close is
         Ignored : C_Int;
      begin
         if Fd >= 0 then
            Ignored := C_Close (Fd);
            Fd := -1;
         end if;
      end Close;

      --  Let the entry go, errno then Error: the reason, kept over the close.
      procedure Refuse (Error : Integer) is
      begin
         Close;
         GNAT.OS_Lib.Set_Errno (Error);
      end Refuse;
   begin
      --  Each refusal says why through errno, as the open's and the statx's
      --  failures do: a link is ELOOP, as O_NOFOLLOW refuses one; another
      --  entry than Expected is ENOENT, the one asked about being gone from
      --  the path (Windows says the same); an id out of range is EINVAL.
      if Beneath_Root = "" then
         C_Path := Interfaces.C.Strings.New_String (Path);
         Fd := C_Open (C_Path, O_Path + O_Nofollow + O_Cloexec);
         Interfaces.C.Strings.Free (C_Path);
      else
         Fd := Open_Beneath;
      end if;
      if Fd < 0
        or else Statx
          (Fd, Empty, C_Unsigned (At_Empty_Path) or At_Symlink_Nofollow,
           Wanted or Statx_Btime, Info'Access) /= 0
      then
         declare
            Error : constant Integer := GNAT.OS_Lib.Errno;
         begin
            Interfaces.C.Strings.Free (Empty);
            Refuse (Error);
         end;
         return Answer;
      elsif (Info.Mask and Wanted) /= Wanted then
         Interfaces.C.Strings.Free (Empty);
         Refuse (E_Opnotsupp);
         return Answer;
      elsif (Info.Mode and File_Type) = Link_Type then
         Interfaces.C.Strings.Free (Empty);
         Refuse (E_Loop);
         return Answer;
      end if;

      Answer.Identity := Identity_Of (Info);
      if Check_Expected and then Answer.Identity /= Expected then
         Interfaces.C.Strings.Free (Empty);
         Refuse (E_Noent);
         return Answer;
      end if;

      if Kind = Update_Ownership then
         Answer.Previous := Identity_Field (Info.User_Id);
         Answer.Previous_Group := Identity_Field (Info.Group_Id);
         if Value > Identity_Field (C_U32'Last)
           or else Group > Identity_Field (C_U32'Last)
           or else Answer.Previous > Max_Previous
           or else Answer.Previous_Group > Max_Previous
         then
            Interfaces.C.Strings.Free (Empty);
            Refuse (E_Inval);
            return Answer;
         end if;
         --  Keep_Id_Field is (uid_t) -1 and (gid_t) -1, which fchownat leaves
         --  as they are; with both kept it is not called, since a chown that
         --  changes nothing still clears set-id bits and capabilities.
         Answer.Success :=
           (Value = Keep_Id_Field and then Group = Keep_Id_Field)
           or else C_Fchownat
             (Fd, Empty, C_U32 (Value), C_U32 (Group),
              At_Empty_Path + C_Int (At_Symlink_Nofollow)) = 0;
      else
         Answer.Previous := Identity_Field (Info.Mode and Permission_Mask);
         declare
            Held : Interfaces.C.Strings.chars_ptr :=
              Interfaces.C.Strings.New_String
                ("/proc/self/fd/" & Ada.Strings.Fixed.Trim
                   (C_Int'Image (Fd), Ada.Strings.Both));
         begin
            Answer.Success := Chmod
              (Held, C_Unsigned (Value mod 8#10000#)) = 0;
            Interfaces.C.Strings.Free (Held);
         exception
            when others =>
               Safe_Free (Held);
               raise;
         end;
      end if;
      Interfaces.C.Strings.Free (Empty);
      Close;
      return Answer;
   exception
      when others =>
         Safe_Free (C_Path);
         Safe_Free (Empty);
         Close;
         return (others => <>);
   end Update_Entry_Metadata;

   function Entry_Revision_Of (Path : String) return Entry_Revision is
      C_Path : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      Info   : aliased Statx_Record;
      Wanted : constant C_Unsigned :=
        Statx_Mode or Statx_Uid or Statx_Gid or Statx_Mtime or Statx_Ctime or Statx_Size;
      Status : C_Int;
   begin
      Status := Statx (At_FDCWD, C_Path, At_Symlink_Nofollow, Wanted, Info'Access);
      Interfaces.C.Strings.Free (C_Path);
      if Status /= 0 or else (Info.Mask and Wanted) /= Wanted then
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

   function Status_Of
     (Path         : String;
      Follow_Links : Boolean) return Entry_Status
   is
      C_Path : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Path);
      Info   : aliased Statx_Record;
      Wanted : constant C_Unsigned :=
        Statx_Mode or Statx_Uid or Statx_Gid or Statx_Mtime or Statx_Size;
      Status : C_Int;
   begin
      Status :=
        Statx
          (At_FDCWD,
           C_Path,
           (if Follow_Links then 0 else At_Symlink_Nofollow),
           Wanted,
           Info'Access);
      Interfaces.C.Strings.Free (C_Path);
      if Status /= 0 or else (Info.Mask and Wanted) /= Wanted then
         return (others => <>);
      end if;
      return
        (Available        => True,
         Size             => Identity_Field (Info.Size),
         Modified_Seconds => Long_Long_Integer (Info.Modified_Time.Seconds),
         Mode             => Natural (Info.Mode),
         User_Id          => Account_Id (Info.User_Id),
         Group_Id         => Account_Id (Info.Group_Id));
   exception
      when others =>
         Safe_Free (C_Path);
         return (others => <>);
   end Status_Of;

   function Entry_Status_Of (Path : String) return Entry_Status is
     (Status_Of (Path, Follow_Links => False));

   function File_Status_Of (Path : String) return Entry_Status is
     (Status_Of (Path, Follow_Links => True));

   function Private_To_Current_User (Path : String) return Boolean is separate;

   function Same_File (Left : String; Right : String) return Boolean is
      L_Path : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Left);
      R_Path : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Right);
      L_Info : aliased Statx_Record;
      R_Info : aliased Statx_Record;
      L_Status : C_Int;
      R_Status : C_Int;
   begin
      L_Status := Statx (At_FDCWD, L_Path, 0, Statx_Ino, L_Info'Access);
      R_Status := Statx (At_FDCWD, R_Path, 0, Statx_Ino, R_Info'Access);
      Interfaces.C.Strings.Free (L_Path);
      Interfaces.C.Strings.Free (R_Path);

      return L_Status = 0 and then R_Status = 0
        and then L_Info.Inode = R_Info.Inode
        and then L_Info.Device_Major = R_Info.Device_Major
        and then L_Info.Device_Minor = R_Info.Device_Minor;
   exception
      when others =>
         Safe_Free (L_Path);
         Safe_Free (R_Path);
         return False;
   end Same_File;

   function Device_Id
     (Path      : String;
      Available : out Boolean)
      return Long_Long_Integer
   is
      C_Path : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      Info   : aliased Statx_Record;
      Status : C_Int;
   begin
      Available := False;
      Status := Statx (At_FDCWD, C_Path, 0, Statx_Ino, Info'Access);
      Interfaces.C.Strings.Free (C_Path);
      if Status /= 0 then
         return 0;
      end if;

      Available := True;
      return Long_Long_Integer (Info.Device_Major) * 4_294_967_296
        + Long_Long_Integer (Info.Device_Minor);
   exception
      when others =>
         Safe_Free (C_Path);
         Available := False;
         return 0;
   end Device_Id;

   procedure File_Mode_And_Ownership
     (Path                : String;
      Mode_Bits           : out Natural;
      Mode_Available      : out Boolean;
      User_Id             : out Account_Id;
      Group_Id            : out Account_Id;
      Ownership_Available : out Boolean)
   is
      C_Path : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      Info   : aliased Statx_Record;
      Status : C_Int;
   begin
      Mode_Bits := 0;
      Mode_Available := False;
      User_Id := 0;
      Group_Id := 0;
      Ownership_Available := False;

      --  One statx fills the fields File_Permission_Bits and File_Ownership
      --  would each fetch with a separate call; the values are identical.
      Status := Statx (At_FDCWD, C_Path, 0, Statx_Mode or Statx_Uid or Statx_Gid, Info'Access);
      Interfaces.C.Strings.Free (C_Path);

      if Status = 0 then
         Mode_Bits := Natural (Info.Mode and Permission_Mask);
         Mode_Available := True;
         User_Id := Account_Id (Info.User_Id);
         Group_Id := Account_Id (Info.Group_Id);
         Ownership_Available := True;
      end if;
   exception
      when others =>
         --  The mode keeps whatever the statx above established: a failure on
         --  the ownership side never takes the permissions with it.
         Safe_Free (C_Path);
         User_Id := 0;
         Group_Id := 0;
         Ownership_Available := False;
   end File_Mode_And_Ownership;

   --  The account database through Hostkit.Posix.Accounts, which uses the
   --  reentrant lookups: getpwnam and the rest answer from one static buffer
   --  that a lookup on another task overwrites.
   function User_Id_For_Name
     (Name  : String;
      Found : out Boolean)
      return Account_Id
   is
      User : constant Hostkit.Posix.Accounts.User_Entry := Hostkit.Posix.Accounts.User_By_Name (Name);
   begin
      Found := User.Found;
      return (if User.Found then Account_Id (User.User_Id) else 0);
   exception
      when others =>
         Found := False;
         return 0;
   end User_Id_For_Name;

   function Group_Id_For_Name
     (Name  : String;
      Found : out Boolean)
      return Account_Id
   is
      Group : constant Hostkit.Posix.Accounts.Group_Entry := Hostkit.Posix.Accounts.Group_By_Name (Name);
   begin
      Found := Group.Found;
      return (if Group.Found then Account_Id (Group.Group_Id) else 0);
   exception
      when others =>
         Found := False;
         return 0;
   end Group_Id_For_Name;

   function User_Name_For_Id (Id : Account_Id) return String is
      User : constant Hostkit.Posix.Accounts.User_Entry :=
        Hostkit.Posix.Accounts.User_By_Id (Interfaces.C.unsigned (Id));
   begin
      return Ada.Strings.Unbounded.To_String (User.Name);
   exception
      when others =>
         return "";
   end User_Name_For_Id;

   function Group_Name_For_Id (Id : Account_Id) return String is
      Group : constant Hostkit.Posix.Accounts.Group_Entry :=
        Hostkit.Posix.Accounts.Group_By_Id (Interfaces.C.unsigned (Id));
   begin
      return Ada.Strings.Unbounded.To_String (Group.Name);
   exception
      when others =>
         return "";
   end Group_Name_For_Id;

   function Set_Ownership
     (Path     : String;
      User_Id  : Account_Id;
      Group_Id : Account_Id)
      return Boolean
   is
      C_Path : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      Status : C_Int;
   begin
      --  Keep_Id is (uid_t) -1 and (gid_t) -1, which chown leaves as they
      --  are. With both kept nothing is asked of chown at all: a chown that
      --  changes nothing still clears set-id bits (and capabilities on Linux).
      if User_Id = Keep_Id and then Group_Id = Keep_Id then
         Interfaces.C.Strings.Free (C_Path);
         declare
            Ignored_User, Ignored_Group : Account_Id;
            Readable : Boolean;
         begin
            File_Ownership (Path, Ignored_User, Ignored_Group, Readable);
            return Readable;
         end;
      end if;
      Status := Chown (C_Path, C_U32 (User_Id), C_U32 (Group_Id));
      Interfaces.C.Strings.Free (C_Path);
      return Status = 0;
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

   procedure File_Ownership
     (Path      : String;
      User_Id   : out Natural;
      Group_Id  : out Natural;
      Available : out Boolean) renames Natural_Ids.File_Ownership;

   procedure File_Mode_And_Ownership
     (Path                : String;
      Mode_Bits           : out Natural;
      Mode_Available      : out Boolean;
      User_Id             : out Natural;
      Group_Id            : out Natural;
      Ownership_Available : out Boolean) renames Natural_Ids.File_Mode_And_Ownership;

   function User_Id_For_Name
     (Name  : String;
      Found : out Boolean)
      return Natural renames Natural_Ids.User_Id_For_Name;

   function Group_Id_For_Name
     (Name  : String;
      Found : out Boolean)
      return Natural renames Natural_Ids.Group_Id_For_Name;

   function Inherit_Rewrites_Change_Times return Boolean is (False);

end Hostkit.Metadata;
