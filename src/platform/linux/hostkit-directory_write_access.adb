with Ada.Directories;
with Ada.Strings;
with Ada.Strings.Fixed;
with Interfaces.C.Strings;

with Hostkit.Fs;
with Hostkit.Host;
with Hostkit.Linux_Abi;

package body Hostkit.Directory_Write_Access is
   use Hostkit.Linux_Abi;
   use type Ada.Directories.File_Kind;
   use type GNAT.OS_Lib.File_Descriptor;
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned;
   use type Interfaces.C.unsigned_short;
   use type Interfaces.C.Strings.chars_ptr;

   Machine         : constant String := Hostkit.Host.Machine_Name;
   Open_Flags      : constant C_Int :=
     O_Path + O_Directory (Machine) + O_Nofollow (Machine) + O_Cloexec;
   Statx_Mode_User : constant C_U32 := Statx_Mode or Statx_Uid;
   Owner_Write     : constant C_U16 := 8#200#;
   Mode_Mask       : constant C_U16 := 8#7777#;

   function C_Open (Path : Interfaces.C.Strings.chars_ptr; Flags : C_Int) return C_Int
     with Import, Convention => C, External_Name => "open";
   function C_Statx
     (Descriptor : C_Int;
      Path       : Interfaces.C.Strings.chars_ptr;
      Flags      : C_Int;
      Mask       : C_U32;
      Info       : access Statx_Record) return C_Int
     with Import, Convention => C, External_Name => "statx";
   function C_Geteuid return C_U32
     with Import, Convention => C, External_Name => "geteuid";
   function C_Chmod (Path : Interfaces.C.Strings.chars_ptr; Mode : C_U32) return C_Int
     with Import, Convention => C, External_Name => "chmod";

   function Held_Path (Descriptor : GNAT.OS_Lib.File_Descriptor) return String is
     ("/proc/self/fd/" & Ada.Strings.Fixed.Trim
        (GNAT.OS_Lib.File_Descriptor'Image (Descriptor), Ada.Strings.Both));

   --  fchmod refuses an O_PATH descriptor, so change the mode through the
   --  descriptor's own /proc entry, which names the held directory and
   --  nothing a rename of the path could substitute.
   function Set_Mode (Descriptor : GNAT.OS_Lib.File_Descriptor; Mode : C_U32) return Boolean is
      Name   : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Held_Path (Descriptor));
      Status : C_Int;
   begin
      Status := C_Chmod (Name, Mode);
      Interfaces.C.Strings.Free (Name);
      return Status = 0;
   exception
      when others =>
         if Name /= Interfaces.C.Strings.Null_Ptr then
            Interfaces.C.Strings.Free (Name);
         end if;
         return False;
   end Set_Mode;

   function Prepare (Path : String; State : in out Context) return Boolean is
      Name  : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.Null_Ptr;
      Empty : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.Null_Ptr;
      Info  : aliased Statx_Record;
      Fd    : C_Int := -1;
   begin
      Release (State);
      if Hostkit.Fs.Is_Link (Path) then
         return True;
      end if;
      if not Ada.Directories.Exists (Path) then
         return False;
      end if;
      if Ada.Directories.Kind (Path) /= Ada.Directories.Directory then
         return True;
      end if;
      Name := Interfaces.C.Strings.New_String (Path);
      Empty := Interfaces.C.Strings.New_String ("");
      Fd := C_Open (Name, Open_Flags);
      Interfaces.C.Strings.Free (Name);
      if Fd < 0
        or else C_Statx (Fd, Empty, At_Empty_Path, Statx_Mode_User, Info'Access) /= 0
        or else (Info.Mask and Statx_Mode_User) /= Statx_Mode_User
      then
         if Fd >= 0 then
            GNAT.OS_Lib.Close (GNAT.OS_Lib.File_Descriptor (Fd));
            Fd := -1;
         end if;
         Interfaces.C.Strings.Free (Empty);
         return False;
      end if;
      Interfaces.C.Strings.Free (Empty);
      if Info.User_Id /= C_Geteuid or else (Info.Mode and Owner_Write) /= 0 then
         GNAT.OS_Lib.Close (GNAT.OS_Lib.File_Descriptor (Fd));
         Fd := -1;
         return True;
      end if;
      State.Descriptor := GNAT.OS_Lib.File_Descriptor (Fd);
      Fd := -1;
      State.Mode := C_U32 (Info.Mode and Mode_Mask);
      if not Set_Mode (State.Descriptor, State.Mode + C_U32 (Owner_Write)) then
         Release (State);
         return False;
      end if;
      State.Restore := True;
      return True;
   exception
      when others =>
         if Fd >= 0 then
            GNAT.OS_Lib.Close (GNAT.OS_Lib.File_Descriptor (Fd));
         end if;
         if Name /= Interfaces.C.Strings.Null_Ptr then
            Interfaces.C.Strings.Free (Name);
         end if;
         if Empty /= Interfaces.C.Strings.Null_Ptr then
            Interfaces.C.Strings.Free (Empty);
         end if;
         Release (State);
         return False;
   end Prepare;

   function Finish (State : in out Context) return Boolean is
   begin
      if not State.Restore then
         return True;
      end if;
      if not Set_Mode (State.Descriptor, State.Mode) then
         return False;
      end if;
      Release (State);
      return True;
   end Finish;

   procedure Release (State : in out Context) is
   begin
      if State.Descriptor /= GNAT.OS_Lib.Invalid_FD then
         GNAT.OS_Lib.Close (State.Descriptor);
      end if;
      State.Descriptor := GNAT.OS_Lib.Invalid_FD;
      State.Mode := 0;
      State.Restore := False;
   end Release;
end Hostkit.Directory_Write_Access;
