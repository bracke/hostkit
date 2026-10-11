with Ada.Strings;
with Ada.Strings.Fixed;
with Interfaces.C;
with Interfaces.C.Strings;
with System;

package body Hostkit.Private_Paths is
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned;
   use type Interfaces.C.unsigned_short;

   subtype C_Int is Interfaces.C.int;
   subtype C_U16 is Interfaces.C.unsigned_short;
   subtype C_U32 is Interfaces.C.unsigned;
   subtype C_U64 is Interfaces.C.unsigned_long;
   subtype C_S64 is Interfaces.C.long;

   type U16_Array is array (Positive range <>) of C_U16
     with Convention => C;
   type U64_Array is array (Positive range <>) of C_U64
     with Convention => C;

   type Statx_Timestamp is record
      Seconds     : C_S64;
      Nanoseconds : C_U32;
      Reserved    : C_U32;
   end record
     with Convention => C;

   type Statx_Record is record
      Mask            : C_U32;
      Block_Size      : C_U32;
      Attributes      : C_U64;
      Link_Count      : C_U32;
      User_Id         : C_U32;
      Group_Id        : C_U32;
      Mode            : C_U16;
      Spare_0         : U16_Array (1 .. 1);
      Inode           : C_U64;
      Size            : C_U64;
      Blocks          : C_U64;
      Attributes_Mask : C_U64;
      Access_Time     : Statx_Timestamp;
      Birth_Time      : Statx_Timestamp;
      Change_Time     : Statx_Timestamp;
      Modified_Time   : Statx_Timestamp;
      Device_Major    : C_U32;
      Device_Minor    : C_U32;
      File_Major      : C_U32;
      File_Minor      : C_U32;
      Mount_Id        : C_U64;
      Direct_Io_Memory_Align : C_U32;
      Direct_Io_Offset_Align : C_U32;
      Spare_3         : U64_Array (1 .. 12);
   end record
     with Convention => C;

   O_Path      : constant C_Int := 8#10000000#;
   O_Directory : constant C_Int := 8#00200000#;
   O_Nofollow  : constant C_Int := 8#00400000#;
   O_Cloexec   : constant C_Int := 8#02000000#;
   At_Empty_Path : constant C_U32 := 16#1000#;
   Statx_Type_Uid : constant C_U32 := 16#0000_0009#;
   File_Type_Mask : constant C_U16 := 8#170000#;
   Directory_Type : constant C_U16 := 8#040000#;
   Regular_Type   : constant C_U16 := 8#100000#;
   E_Exist        : constant C_Int := 17;
   E_No_Data      : constant C_Int := 61;
   E_Not_Supported : constant C_Int := 95;

   function C_Mkdir
     (Path : Interfaces.C.Strings.chars_ptr;
      Mode : Interfaces.C.unsigned) return C_Int
     with Import, Convention => C, External_Name => "mkdir";
   function C_Rmdir (Path : Interfaces.C.Strings.chars_ptr) return C_Int
     with Import, Convention => C, External_Name => "rmdir";
   function C_Open
     (Path : Interfaces.C.Strings.chars_ptr;
      Flags : C_Int) return C_Int
     with Import, Convention => C, External_Name => "open";
   function C_Close (Fd : C_Int) return C_Int
     with Import, Convention => C, External_Name => "close";
   function C_Chmod
     (Path : Interfaces.C.Strings.chars_ptr;
      Mode : Interfaces.C.unsigned) return C_Int
     with Import, Convention => C, External_Name => "chmod";
   function C_Fchmod
     (Fd : C_Int; Mode : Interfaces.C.unsigned) return C_Int
     with Import, Convention => C, External_Name => "fchmod";
   function C_Removexattr
     (Path : Interfaces.C.Strings.chars_ptr;
      Name : Interfaces.C.Strings.chars_ptr) return C_Int
     with Import, Convention => C, External_Name => "removexattr";
   function C_Fremovexattr
     (Fd : C_Int; Name : Interfaces.C.Strings.chars_ptr) return C_Int
     with Import, Convention => C, External_Name => "fremovexattr";
   function C_Geteuid return C_U32
     with Import, Convention => C, External_Name => "geteuid";
   function C_Statx
     (Directory_Fd : C_Int;
      Pathname     : Interfaces.C.Strings.chars_ptr;
      Flags        : C_U32;
      Mask         : C_U32;
      Buffer       : access Statx_Record) return C_Int
     with Import, Convention => C, External_Name => "statx";
   function Errno_Location return System.Address
     with Import, Convention => C, External_Name => "__errno_location";

   function Errno return C_Int is
      Value : C_Int with Import, Address => Errno_Location;
   begin
      return Value;
   end Errno;

   function Entry_Info
     (Fd : C_Int; Wanted_Type : C_U16) return Boolean
   is
      Empty : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String ("");
      Info : aliased Statx_Record;
      Ok : Boolean;
   begin
      Ok := C_Statx
        (Fd, Empty, At_Empty_Path, Statx_Type_Uid, Info'Access) = 0
        and then (Info.Mask and Statx_Type_Uid) = Statx_Type_Uid
        and then (Info.Mode and File_Type_Mask) = Wanted_Type
        and then Info.User_Id = C_Geteuid;
      Interfaces.C.Strings.Free (Empty);
      return Ok;
   exception
      when others =>
         Interfaces.C.Strings.Free (Empty);
         return False;
   end Entry_Info;

   function Missing_Attribute (Status : C_Int) return Boolean is
      pragma Unreferenced (Status);
      Value : constant C_Int := Errno;
   begin
      return Value = E_No_Data or else Value = E_Not_Supported;
   end Missing_Attribute;

   function Harden_Directory
     (Path : String; Remove_On_Failure : Boolean) return Boolean
   is
      C_Path : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Path);
      Fd : constant C_Int := C_Open
        (C_Path, O_Path + O_Directory + O_Nofollow + O_Cloexec);
      Held_Path : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.Null_Ptr;
      Acl_Name : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.Null_Ptr;
      Status : C_Int;
      Ok : Boolean := Fd >= 0;
   begin
      if Ok then
         Ok := Entry_Info (Fd, Directory_Type);
      end if;
      if Ok then
         Held_Path := Interfaces.C.Strings.New_String
           ("/proc/self/fd/" & Ada.Strings.Fixed.Trim
              (C_Int'Image (Fd), Ada.Strings.Both));
         Ok := C_Chmod (Held_Path, 8#700#) = 0;
      end if;
      if Ok then
         Acl_Name := Interfaces.C.Strings.New_String
           ("system.posix_acl_default");
         Status := C_Removexattr (Held_Path, Acl_Name);
         Ok := Status = 0 or else Missing_Attribute (Status);
      end if;
      if Fd >= 0 then
         Status := C_Close (Fd);
      end if;
      if not Ok and then Remove_On_Failure then
         Status := C_Rmdir (C_Path);
      end if;
      Interfaces.C.Strings.Free (Acl_Name);
      Interfaces.C.Strings.Free (Held_Path);
      Interfaces.C.Strings.Free (C_Path);
      return Ok;
   exception
      when others =>
         if Fd >= 0 then
            Status := C_Close (Fd);
         end if;
         if Remove_On_Failure then
            Status := C_Rmdir (C_Path);
         end if;
         Interfaces.C.Strings.Free (Acl_Name);
         Interfaces.C.Strings.Free (Held_Path);
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
      Acl_Name : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String ("system.posix_acl_access");
      Status : C_Int;
      Ok : Boolean := Entry_Info (Fd, Regular_Type);
   begin
      if Ok then
         Status := C_Fremovexattr (Fd, Acl_Name);
         Ok := Status = 0 or else Missing_Attribute (Status);
      end if;
      if Ok then
         Ok := C_Fchmod (Fd, 8#600#) = 0;
      end if;
      Interfaces.C.Strings.Free (Acl_Name);
      return Ok;
   exception
      when others =>
         Interfaces.C.Strings.Free (Acl_Name);
         return False;
   end Restrict_Open_File;

end Hostkit.Private_Paths;
