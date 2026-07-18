with System;
with Interfaces;
with Ada.Directories;

with GNAT.OS_Lib;

with Interfaces.C.Strings;
with Ada.Strings.Unbounded;

package body Hostkit.Fs is
   use type Interfaces.C.int;

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
      return Ada.Directories.Exists (Path)
        and then Ada.Directories.Kind (Path) = Ada.Directories.Ordinary_File
        and then GNAT.OS_Lib.Is_Executable_File (Path);
   exception
      when others =>
         return False;
   end Is_Executable;

   --  Group or other having any permission at all: (st_mode and 8#077#) /= 0. Those six bits
   --  live in the lowest byte of st_mode, so this reads that one byte out of the stat buffer
   --  rather than reconstructing the whole field. A regular file only -- a directory's bits
   --  mean something else.
   function Accessible_By_Others (Path : String) return Boolean is
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
        or else Ada.Directories.Kind (Path) /= Ada.Directories.Ordinary_File
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
   end Accessible_By_Others;

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

end Hostkit.Fs;
