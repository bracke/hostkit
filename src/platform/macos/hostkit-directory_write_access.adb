with Ada.Directories;
with Interfaces.C.Strings;

with Hostkit.Darwin_Abi;
with Hostkit.Darwin_Symbols;
with Hostkit.Fs;

package body Hostkit.Directory_Write_Access is
   use Hostkit.Darwin_Abi;
   use type Ada.Directories.File_Kind;
   use type GNAT.OS_Lib.File_Descriptor;
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned;
   use type Interfaces.C.unsigned_short;
   use type Interfaces.C.Strings.chars_ptr;

   Owner_Write : constant C_U16 := 8#200#;
   Mode_Mask   : constant C_U16 := 8#7777#;

   function C_Open (Path : Interfaces.C.Strings.chars_ptr; Flags : C_Int) return C_Int
     with Import, Convention => C, External_Name => "open";
   function C_Fstat (Descriptor : C_Int; Info : access Stat_Record) return C_Int
     with Import, Convention => C, External_Name => Hostkit.Darwin_Symbols.Fstat;
   function C_Geteuid return C_U32
     with Import, Convention => C, External_Name => "geteuid";
   function C_Fchmod (Descriptor : C_Int; Mode : C_U16) return C_Int
     with Import, Convention => C, External_Name => "fchmod";

   function Prepare (Path : String; State : in out Context) return Boolean is
      Name : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.Null_Ptr;
      Info : aliased Stat_Record;
      Fd   : C_Int := -1;
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
      Fd := C_Open (Name, O_Evtonly + O_Directory + O_Nofollow + O_Cloexec);
      Interfaces.C.Strings.Free (Name);
      if Fd < 0 or else C_Fstat (Fd, Info'Access) /= 0 then
         if Fd >= 0 then
            GNAT.OS_Lib.Close (GNAT.OS_Lib.File_Descriptor (Fd));
            Fd := -1;
         end if;
         return False;
      end if;
      if Info.User_Id /= C_Geteuid or else (Info.Mode and Owner_Write) /= 0 then
         GNAT.OS_Lib.Close (GNAT.OS_Lib.File_Descriptor (Fd));
         Fd := -1;
         return True;
      end if;
      State.Descriptor := GNAT.OS_Lib.File_Descriptor (Fd);
      Fd := -1;
      State.Mode := C_U32 (Info.Mode and Mode_Mask);
      if C_Fchmod
        (C_Int (State.Descriptor), C_U16 (State.Mode) or Owner_Write) /= 0
      then
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
         Release (State);
         return False;
   end Prepare;

   function Finish (State : in out Context) return Boolean is
   begin
      if not State.Restore then
         return True;
      end if;
      if C_Fchmod (C_Int (State.Descriptor), C_U16 (State.Mode)) /= 0 then
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
