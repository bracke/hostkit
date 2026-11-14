with Interfaces.C;
with System.Storage_Elements;

with Hostkit.Windows_Paths;

--  Windows: the share mode of CreateFileW, and the read-only attribute.
package body Hostkit_Test_Native is

   use type System.Address;

   subtype C_DWord is Interfaces.C.unsigned_long;
   use type C_DWord;

   Generic_Read          : constant C_DWord := 16#8000_0000#;
   File_Share_Read       : constant C_DWord := 16#0000_0001#;
   Generic_Write         : constant C_DWord := 16#4000_0000#;
   Create_New            : constant C_DWord := 1;
   Open_Existing         : constant C_DWord := 3;
   File_Attribute_Normal : constant C_DWord := 16#0000_0080#;
   Attribute_Read_Only   : constant C_DWord := 16#0000_0001#;
   Invalid_Attributes    : constant C_DWord := 16#FFFF_FFFF#;

   --  INVALID_HANDLE_VALUE, (HANDLE) -1: every bit set.
   Invalid_Handle : constant System.Address :=
     System.Storage_Elements.To_Address (System.Storage_Elements.Integer_Address'Last);

   function Create_File_W
     (Name        : System.Address;
      Desired     : C_DWord;
      Share       : C_DWord;
      Security    : System.Address;
      Disposition : C_DWord;
      Flags       : C_DWord;
      Template    : System.Address) return System.Address
     with Import, Convention => Stdcall, External_Name => "CreateFileW";

   function Close_Handle (Handle : System.Address) return Interfaces.C.int
     with Import, Convention => Stdcall, External_Name => "CloseHandle";

   function Get_Handle_Information (Handle : System.Address; Flags : access C_DWord) return Interfaces.C.int
     with Import, Convention => Stdcall, External_Name => "GetHandleInformation";

   Handle_Flag_Inherit : constant C_DWord := 16#0000_0001#;

   function Get_File_Attributes_W (Path : System.Address) return C_DWord
     with Import, Convention => Stdcall, External_Name => "GetFileAttributesW";

   function Hold_Against_Writers (Path : String; Held : out Exclusive_Hold) return Boolean is
      Name   : aliased constant Wide_String := Hostkit.Windows_Paths.Native (Path);
      Handle : constant System.Address :=
        Create_File_W
          (Name'Address, Generic_Read, File_Share_Read, System.Null_Address, Open_Existing,
           File_Attribute_Normal, System.Null_Address);
   begin
      if Handle = Invalid_Handle or else Handle = System.Null_Address then
         Held.Handle := System.Null_Address;
         return False;
      end if;
      Held.Handle := Handle;
      return True;
   end Hold_Against_Writers;

   procedure Release (Held : in out Exclusive_Hold) is
   begin
      if Held.Handle /= System.Null_Address then
         declare
            --  A failed close leaves nothing to do but forget the handle.
            Closed : constant Interfaces.C.int := Close_Handle (Held.Handle);
            pragma Unreferenced (Closed);
         begin
            Held.Handle := System.Null_Address;
         end;
      end if;
   end Release;

   function Is_Read_Only (Path : String) return Boolean is
      Name       : aliased constant Wide_String := Hostkit.Windows_Paths.Native (Path);
      Attributes : constant C_DWord := Get_File_Attributes_W (Name'Address);
   begin
      return Attributes /= Invalid_Attributes and then (Attributes and Attribute_Read_Only) /= 0;
   end Is_Read_Only;

   function Create_With_Units (Folder : String; Leaf : Wide_String) return Boolean is
      use type Interfaces.C.int;
      Base   : constant Wide_String := Hostkit.Windows_Paths.Native (Folder);
      --  Native ends in a NUL; the leaf goes before it.
      Name   : aliased constant Wide_String :=
        Base (Base'First .. Base'Last - 1) & "\" & Leaf & Wide_Character'Val (0);
      Handle : constant System.Address :=
        Create_File_W
          (Name'Address, Generic_Write, 0, System.Null_Address, Create_New, File_Attribute_Normal,
           System.Null_Address);
   begin
      if Handle = Invalid_Handle or else Handle = System.Null_Address then
         return False;
      end if;
      return Close_Handle (Handle) /= 0;
   end Create_With_Units;

   function Handle_Inheritance (Handle : Interfaces.Integer_64; Inheritable : out Boolean) return Boolean is
      use type Interfaces.C.int;
      use type Interfaces.Integer_64;
      Flags : aliased C_DWord := 0;
   begin
      Inheritable := False;
      if Handle < 0 then
         return False;
      end if;
      if Get_Handle_Information
           (System.Storage_Elements.To_Address (System.Storage_Elements.Integer_Address (Handle)), Flags'Access) = 0
      then
         return False;
      end if;
      Inheritable := (Flags and Handle_Flag_Inherit) /= 0;
      return True;
   end Handle_Inheritance;

   function Drop_Backup_Privileges return Boolean is
      use type Interfaces.C.int;
      type Luid_And_Attributes is record
         Low        : C_DWord;
         High       : Interfaces.C.long;
         Attributes : C_DWord;
      end record
        with Convention => C;
      type Privilege_List is array (1 .. 2) of Luid_And_Attributes
        with Convention => C;
      type Token_Privileges is record
         Count      : C_DWord;
         Privileges : Privilege_List;
      end record
        with Convention => C;

      function Get_Current_Process return System.Address
        with Import, Convention => Stdcall, External_Name => "GetCurrentProcess";
      function Open_Process_Token
        (Process : System.Address; Desired : C_DWord; Token : access System.Address) return Interfaces.C.int
        with Import, Convention => Stdcall, External_Name => "OpenProcessToken";
      function Lookup_Privilege_Value
        (System_Name : System.Address; Name : System.Address; Luid : System.Address) return Interfaces.C.int
        with Import, Convention => Stdcall, External_Name => "LookupPrivilegeValueW";
      function Adjust_Token_Privileges
        (Token : System.Address; Disable_All : Interfaces.C.int; New_State : System.Address;
         Length : C_DWord; Previous : System.Address; Return_Length : System.Address) return Interfaces.C.int
        with Import, Convention => Stdcall, External_Name => "AdjustTokenPrivileges";

      Token_Adjust_Privileges : constant C_DWord := 16#0020#;
      Token_Query             : constant C_DWord := 16#0008#;
      Backup  : aliased constant Wide_String := "SeBackupPrivilege" & Wide_Character'Val (0);
      Restore : aliased constant Wide_String := "SeRestorePrivilege" & Wide_Character'Val (0);
      Token   : aliased System.Address := System.Null_Address;
      State   : aliased Token_Privileges := (Count => 2, Privileges => [others => (0, 0, 0)]);
      Ok      : Boolean;
      Ignored : Interfaces.C.int;
   begin
      if Open_Process_Token (Get_Current_Process, Token_Adjust_Privileges + Token_Query, Token'Access) = 0 then
         return False;
      end if;
      --  Attributes 0: disabled.
      Ok := Lookup_Privilege_Value (System.Null_Address, Backup'Address, State.Privileges (1)'Address) /= 0
        and then Lookup_Privilege_Value (System.Null_Address, Restore'Address, State.Privileges (2)'Address) /= 0
        and then Adjust_Token_Privileges
          (Token, 0, State'Address, 0, System.Null_Address, System.Null_Address) /= 0;
      Ignored := Close_Handle (Token);
      return Ok;
   end Drop_Backup_Privileges;

   --  Windows keeps a process's exit code for anyone holding its handle;
   --  there is no reaping to avoid, and no waitid to wait with.
   function Await_Exit_Uncollected (Process_Id : Integer) return Exit_Wait is
      pragma Unreferenced (Process_Id);
   begin
      return Cannot_Wait;
   end Await_Exit_Uncollected;

end Hostkit_Test_Native;
