with Ada.Environment_Variables;
with System;
with Interfaces;
with Ada.Directories;
with Ada.Streams;

with GNAT.OS_Lib;

with Interfaces.C.Strings;
with Ada.Strings.Unbounded;

package body Hostkit.Fs is
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned;

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

   --  Group or other having any permission at all: (st_mode and 8#077#) /= 0. Those six bits
   --  live in the lowest byte of st_mode, so this reads that one byte out of the stat buffer
   --  rather than reconstructing the whole field. Want keeps the two callers apart: a
   --  file's bits and a directory's do not mean the same thing, so neither answers for
   --  the other.
   function Exposed (Path : String; Want : Ada.Directories.File_Kind) return Boolean is
      use type Interfaces.C.int;
      use type Interfaces.Unsigned_8;
      use type Ada.Directories.File_Kind;

      --  struct stat is larger than this; stat writes only into what it needs and the mode
      --  sits near the front. Oversized so there is always room.
      Buffer : array (0 .. 255) of aliased Interfaces.Unsigned_8 := [others => 0];

      function C_Stat (Path : Interfaces.C.Strings.chars_ptr; Buf : System.Address)
        return Interfaces.C.int
        with Import => True, Convention => C, External_Name => "stat$INODE64";

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
      use type Interfaces.C.int;
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
      function NS_Get_Executable_Path
        (Buffer : System.Address; Size : access Interfaces.C.unsigned)
         return Interfaces.C.int
        with Import => True, Convention => C,
             External_Name => "_NSGetExecutablePath";

      Buffer : aliased String (1 .. 4096) := [others => ASCII.NUL];
      Size   : aliased Interfaces.C.unsigned := Buffer'Length;
      use type Interfaces.C.int;
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
      return (if Home = "" then "" else Home & "/Library/Application Support");
   end Application_Data_Directory;

   function Cache_Directory return String is
      Home : constant String := Home_Directory;
   begin
      return (if Home = "" then "" else Home & "/Library/Caches");
   end Cache_Directory;

   function Temp_Directory return String is
   begin
      if Ada.Environment_Variables.Exists ("TMPDIR")
        and then Ada.Environment_Variables.Value ("TMPDIR") /= ""
      then
         return Ada.Environment_Variables.Value ("TMPDIR");
      end if;
      return "/tmp";
   end Temp_Directory;

   function Uses_Dos_Filename_Rules (Path : String) return Boolean is
      pragma Unreferenced (Path);
   begin
      --  The native volumes (APFS, HFS+) are POSIX; a removable FAT/exFAT one is
      --  possible but its own rules are enforced by the OS at write time, so this
      --  declines to guess a restriction rather than binding statfs here.
      return False;
   end Uses_Dos_Filename_Rules;

end Hostkit.Fs;
