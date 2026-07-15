with System;
with Interfaces;
with Ada.Directories;

with GNAT.OS_Lib;

with Interfaces.C.Strings;

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

end Hostkit.Fs;
