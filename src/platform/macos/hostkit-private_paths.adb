with Interfaces.C;
with Interfaces.C.Strings;
with System;

package body Hostkit.Private_Paths is
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned;
   use type Interfaces.C.unsigned_short;
   use type System.Address;

   subtype C_Int is Interfaces.C.int;
   subtype C_U16 is Interfaces.C.unsigned_short;
   subtype C_U32 is Interfaces.C.unsigned;
   subtype C_U64 is Interfaces.C.unsigned_long;
   subtype C_S32 is Interfaces.C.int;
   subtype C_S64 is Interfaces.C.long;

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

   pragma Compile_Time_Error
     (Stat_Record'Size /= 144 * 8,
      "Darwin struct stat (64-bit inode) must be 144 bytes");

   O_Rdonly    : constant C_Int := 16#0000#;
   O_Nofollow  : constant C_Int := 16#0100#;
   O_Directory : constant C_Int := 16#0010_0000#;
   O_Cloexec   : constant C_Int := 16#0100_0000#;
   File_Type_Mask : constant C_U16 := 8#170000#;
   Directory_Type : constant C_U16 := 8#040000#;
   Regular_Type   : constant C_U16 := 8#100000#;
   E_Exist : constant C_Int := 17;
   Acl_Type_Extended : constant C_Int := 16#100#;

   function C_Mkdir
     (Path : Interfaces.C.Strings.chars_ptr;
      Mode : Interfaces.C.unsigned) return C_Int
     with Import, Convention => C, External_Name => "mkdir";
   function C_Rmdir (Path : Interfaces.C.Strings.chars_ptr) return C_Int
     with Import, Convention => C, External_Name => "rmdir";
   function C_Open
     (Path : Interfaces.C.Strings.chars_ptr; Flags : C_Int) return C_Int
     with Import, Convention => C, External_Name => "open";
   function C_Close (Fd : C_Int) return C_Int
     with Import, Convention => C, External_Name => "close";
   function C_Fstat
     (Fd : C_Int; Info : access Stat_Record) return C_Int
     with Import, Convention => C, External_Name => "fstat$INODE64";
   function C_Geteuid return C_U32
     with Import, Convention => C, External_Name => "geteuid";
   function C_Fchmod
     (Fd : C_Int; Mode : Interfaces.C.unsigned) return C_Int
     with Import, Convention => C, External_Name => "fchmod";
   function C_Acl_Init (Count : C_Int) return System.Address
     with Import, Convention => C, External_Name => "acl_init";
   function C_Acl_Set_Fd
     (Fd : C_Int; Acl : System.Address; Kind : C_Int) return C_Int
     with Import, Convention => C, External_Name => "acl_set_fd_np";
   function C_Acl_Free (Acl : System.Address) return C_Int
     with Import, Convention => C, External_Name => "acl_free";
   function Errno_Location return System.Address
     with Import, Convention => C, External_Name => "__error";

   function Errno return C_Int is
      Value : C_Int with Import, Address => Errno_Location;
   begin
      return Value;
   end Errno;

   function Is_Owned_Kind (Fd : C_Int; Kind : C_U16) return Boolean is
      Info : aliased Stat_Record;
   begin
      return C_Fstat (Fd, Info'Access) = 0
        and then (Info.Mode and File_Type_Mask) = Kind
        and then Info.User_Id = C_Geteuid;
   end Is_Owned_Kind;

   function Remove_Extended_Acl (Fd : C_Int) return Boolean is
      Acl : constant System.Address := C_Acl_Init (0);
      Result : Boolean := False;
      Ignored : C_Int;
   begin
      if Acl /= System.Null_Address then
         Result := C_Acl_Set_Fd (Fd, Acl, Acl_Type_Extended) = 0;
         Ignored := C_Acl_Free (Acl);
      end if;
      return Result;
   end Remove_Extended_Acl;

   function Harden_Directory
     (Path : String; Remove_On_Failure : Boolean) return Boolean
   is
      C_Path : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Path);
      Fd : constant C_Int := C_Open
        (C_Path, O_Rdonly + O_Directory + O_Nofollow + O_Cloexec);
      Ignored : C_Int;
      Ok : Boolean := Fd >= 0 and then Is_Owned_Kind (Fd, Directory_Type);
   begin
      if Ok then
         Ok := C_Fchmod (Fd, 8#700#) = 0 and then Remove_Extended_Acl (Fd);
      end if;
      if Fd >= 0 then
         Ignored := C_Close (Fd);
      end if;
      if not Ok and then Remove_On_Failure then
         Ignored := C_Rmdir (C_Path);
      end if;
      Interfaces.C.Strings.Free (C_Path);
      return Ok;
   exception
      when others =>
         if Fd >= 0 then
            Ignored := C_Close (Fd);
         end if;
         if Remove_On_Failure then
            Ignored := C_Rmdir (C_Path);
         end if;
         Interfaces.C.Strings.Free (C_Path);
         return False;
   end Harden_Directory;

   function Create_Directory (Path : String) return Create_Outcome is
      C_Path : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Path);
      Status : C_Int;
      Error : C_Int;
   begin
      Status := C_Mkdir (C_Path, 8#700#);
      Error := Errno;
      Interfaces.C.Strings.Free (C_Path);
      if Status = 0 then
         return (if Harden_Directory (Path, True) then Created else Create_Error);
      elsif Error = E_Exist then
         return Already_Exists;
      else
         return Create_Error;
      end if;
   exception
      when others =>
         Interfaces.C.Strings.Free (C_Path);
         return Create_Error;
   end Create_Directory;

   function Ensure_Directory (Path : String) return Boolean is
   begin
      case Create_Directory (Path) is
         when Created => return True;
         when Already_Exists => return Harden_Directory (Path, False);
         when Create_Error => return False;
      end case;
   end Ensure_Directory;

   function Restrict_Open_File (Descriptor : Integer) return Boolean is
      Fd : constant C_Int := C_Int (Descriptor);
   begin
      return Is_Owned_Kind (Fd, Regular_Type)
        and then Remove_Extended_Acl (Fd)
        and then C_Fchmod (Fd, 8#600#) = 0;
   exception
      when others =>
         return False;
   end Restrict_Open_File;

end Hostkit.Private_Paths;
