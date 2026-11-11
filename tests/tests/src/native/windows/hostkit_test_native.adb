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

end Hostkit_Test_Native;
