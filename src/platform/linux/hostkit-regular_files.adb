with Interfaces.C;
with Interfaces.C.Strings;

with Hostkit.Host;
with Hostkit.Linux_Abi;

package body Hostkit.Regular_Files is
   use Hostkit.Linux_Abi;
   use type Interfaces.C.int;
   use type Interfaces.C.long;
   use type Interfaces.C.unsigned;
   use type Interfaces.C.unsigned_short;
   use type Interfaces.C.Strings.chars_ptr;

   subtype File_Offset is Interfaces.C.long;

   No_Follow      : constant C_Int := O_Nofollow (Hostkit.Host.Machine_Name);
   File_Type_Mask : constant C_U16 := 8#170000#;
   Regular_File   : constant C_U16 := 8#100000#;

   function C_Open (Path : Interfaces.C.Strings.chars_ptr; Flags : C_Int) return C_Int
     with Import, Convention => C, External_Name => "open";
   function C_Statx
     (Descriptor : C_Int;
      Path       : Interfaces.C.Strings.chars_ptr;
      Flags      : C_Int;
      Mask       : C_U32;
      Info       : access Statx_Record) return C_Int
     with Import, Convention => C, External_Name => "statx";
   function C_Lseek
     (Descriptor : C_Int;
      Offset     : File_Offset;
      Origin     : C_Int) return File_Offset
     with Import, Convention => C, External_Name => "lseek";
   function C_Truncate
     (Descriptor : C_Int;
      Length     : File_Offset) return C_Int
     with Import, Convention => C, External_Name => "ftruncate";

   function Open_Read
     (Path         : String;
      Follow_Links : Boolean;
      Supported    : out Boolean) return GNAT.OS_Lib.File_Descriptor
   is
      Name  : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.Null_Ptr;
      Empty : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.Null_Ptr;
      Flags : C_Int := O_Nonblock + O_Cloexec;
      Result : C_Int := -1;
      Info   : aliased Statx_Record;
   begin
      Supported := True;
      Name := Interfaces.C.Strings.New_String (Path);
      Empty := Interfaces.C.Strings.New_String ("");
      if not Follow_Links then
         Flags := Flags + No_Follow;
      end if;
      Result := C_Open (Name, Flags + O_Noatime);
      if Result < 0 and then GNAT.OS_Lib.Errno in 1 | 22 | 95 then
         Result := C_Open (Name, Flags);
      end if;
      Interfaces.C.Strings.Free (Name);
      if Result < 0
        or else C_Statx (Result, Empty, At_Empty_Path, Statx_Mode, Info'Access) /= 0
        or else (Info.Mask and Statx_Mode) = 0
        or else (Info.Mode and File_Type_Mask) /= Regular_File
      then
         if Result >= 0 then
            GNAT.OS_Lib.Close (GNAT.OS_Lib.File_Descriptor (Result));
         end if;
         Interfaces.C.Strings.Free (Empty);
         return GNAT.OS_Lib.Invalid_FD;
      end if;
      Interfaces.C.Strings.Free (Empty);
      return GNAT.OS_Lib.File_Descriptor (Result);
   exception
      when others =>
         if Result >= 0 then
            GNAT.OS_Lib.Close (GNAT.OS_Lib.File_Descriptor (Result));
         end if;
         if Name /= Interfaces.C.Strings.Null_Ptr then
            Interfaces.C.Strings.Free (Name);
         end if;
         if Empty /= Interfaces.C.Strings.Null_Ptr then
            Interfaces.C.Strings.Free (Empty);
         end if;
         return GNAT.OS_Lib.Invalid_FD;
   end Open_Read;

   function Skip_Zeros
     (Descriptor : GNAT.OS_Lib.File_Descriptor;
      Count      : Integer) return Boolean is
     (C_Lseek (C_Int (Descriptor), File_Offset (Count), 1) >= 0);

   function Finish_Sparse (Descriptor : GNAT.OS_Lib.File_Descriptor) return Boolean is
      Position : constant File_Offset := C_Lseek (C_Int (Descriptor), 0, 1);
   begin
      return Position >= 0 and then C_Truncate (C_Int (Descriptor), Position) = 0;
   end Finish_Sparse;
end Hostkit.Regular_Files;
