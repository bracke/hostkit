with Ada.Strings.UTF_Encoding.Wide_Strings;
with Interfaces;
with Interfaces.C;
with System;
with System.Storage_Elements;

package body Hostkit.Private_Paths is
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned_long;
   use type System.Address;
   use type System.Storage_Elements.Integer_Address;

   subtype C_Int is Interfaces.C.int;
   subtype C_DWord is Interfaces.C.unsigned_long;
   subtype C_U64 is Interfaces.Unsigned_64;

   type Security_Attributes is record
      Length              : C_DWord;
      Security_Descriptor : System.Address;
      Inherit_Handle      : C_Int;
   end record
     with Convention => C;

   type File_Id_Bytes is array (0 .. 15) of Interfaces.Unsigned_8
     with Convention => C;
   type File_Id_Info is record
      Volume : C_U64;
      Id     : File_Id_Bytes;
   end record
     with Convention => C;

   type By_Handle_File_Information is record
      Attributes       : C_DWord;
      Creation_Low     : C_DWord;
      Creation_High    : C_DWord;
      Access_Low       : C_DWord;
      Access_High      : C_DWord;
      Write_Low        : C_DWord;
      Write_High       : C_DWord;
      Volume_Serial    : C_DWord;
      Size_High        : C_DWord;
      Size_Low         : C_DWord;
      Link_Count       : C_DWord;
      File_Index_High  : C_DWord;
      File_Index_Low   : C_DWord;
   end record
     with Convention => C;

   type Byte_Buffer is array (Natural range <>) of aliased Interfaces.Unsigned_8
     with Convention => C;

   Invalid_Handle : constant System.Address :=
     System.Storage_Elements.To_Address (-1);
   File_Attribute_Directory     : constant C_DWord := 16#0000_0010#;
   File_Attribute_Reparse_Point : constant C_DWord := 16#0000_0400#;
   File_Flag_Open_Reparse_Point : constant C_DWord := 16#0020_0000#;
   File_Flag_Backup_Semantics   : constant C_DWord := 16#0200_0000#;
   File_Share_All               : constant C_DWord := 7;
   Open_Existing                : constant C_DWord := 3;
   Read_Control                 : constant C_DWord := 16#0002_0000#;
   Write_Dac                    : constant C_DWord := 16#0004_0000#;
   File_Read_Attributes         : constant C_DWord := 16#0000_0080#;
   Owner_Security_Information  : constant C_DWord := 16#0000_0001#;
   Dacl_Security_Information   : constant C_DWord := 16#0000_0004#;
   Protected_Dacl_Information : constant C_DWord := 16#8000_0000#;
   Token_Query : constant C_DWord := 16#0000_0008#;
   Token_Owner_Class : constant C_Int := 4;
   Se_File_Object : constant C_Int := 1;
   Sddl_Revision_1 : constant C_DWord := 1;
   Error_File_Exists    : constant C_DWord := 80;
   Error_Already_Exists : constant C_DWord := 183;
   File_Id_Info_Class : constant C_Int := 18;

   function Wide (Value : String) return Wide_String is
     (Ada.Strings.UTF_Encoding.Wide_Strings.Decode (Value)
        & Wide_Character'Val (0));

   function Create_Directory_W
     (Name : System.Address;
      Attributes : access Security_Attributes) return C_Int
     with Import, Convention => Stdcall, External_Name => "CreateDirectoryW";
   function Get_Last_Error return C_DWord
     with Import, Convention => Stdcall, External_Name => "GetLastError";
   function Create_File_W
     (Name : System.Address; Access_Mode, Share : C_DWord;
      Security : System.Address; Disposition, Flags : C_DWord;
      Template : System.Address) return System.Address
     with Import, Convention => Stdcall, External_Name => "CreateFileW";
   function Close_Handle (Handle : System.Address) return C_Int
     with Import, Convention => Stdcall, External_Name => "CloseHandle";
   function Get_File_Information
     (Handle : System.Address;
      Info : access By_Handle_File_Information) return C_Int
     with Import, Convention => Stdcall,
          External_Name => "GetFileInformationByHandle";
   function Get_File_Information_Ex
     (Handle : System.Address; Kind : C_Int;
      Info : System.Address; Size : C_DWord) return C_Int
     with Import, Convention => Stdcall,
          External_Name => "GetFileInformationByHandleEx";
   function Get_Security_Info
     (Handle : System.Address; Object_Type : C_Int; Information : C_DWord;
      Owner, Group, Dacl, Sacl : System.Address;
      Descriptor : access System.Address) return C_DWord
     with Import, Convention => Stdcall, External_Name => "GetSecurityInfo";
   function Set_Security_Info
     (Handle : System.Address; Object_Type : C_Int; Information : C_DWord;
      Owner, Group, Dacl, Sacl : System.Address) return C_DWord
     with Import, Convention => Stdcall, External_Name => "SetSecurityInfo";
   function Convert_Sddl
     (Text : System.Address; Revision : C_DWord;
      Descriptor : access System.Address; Size : System.Address) return C_Int
     with Import, Convention => Stdcall,
          External_Name => "ConvertStringSecurityDescriptorToSecurityDescriptorW";
   function Get_Descriptor_Dacl
     (Descriptor : System.Address; Present : access C_Int;
      Dacl : access System.Address; Defaulted : access C_Int) return C_Int
     with Import, Convention => Stdcall,
          External_Name => "GetSecurityDescriptorDacl";
   function Local_Free (Value : System.Address) return System.Address
     with Import, Convention => Stdcall, External_Name => "LocalFree";
   function Get_Current_Process return System.Address
     with Import, Convention => Stdcall, External_Name => "GetCurrentProcess";
   function Open_Process_Token
     (Process : System.Address; Access_Mode : C_DWord;
      Token : access System.Address) return C_Int
     with Import, Convention => Stdcall, External_Name => "OpenProcessToken";
   function Get_Token_Information
     (Token : System.Address; Kind : C_Int; Buffer : System.Address;
      Size : C_DWord; Needed : access C_DWord) return C_Int
     with Import, Convention => Stdcall, External_Name => "GetTokenInformation";
   function Equal_Sid (Left, Right : System.Address) return C_Int
     with Import, Convention => Stdcall, External_Name => "EqualSid";
   function Get_Final_Path
     (Handle : System.Address; Buffer : System.Address;
      Size, Flags : C_DWord) return C_DWord
     with Import, Convention => Stdcall,
          External_Name => "GetFinalPathNameByHandleW";
   function Osfhandle (Descriptor : C_Int) return System.Address
     with Import, Convention => C, External_Name => "_get_osfhandle";

   function Same_File (Left, Right : System.Address) return Boolean is
      Left_Id, Right_Id : aliased File_Id_Info;
   begin
      return Get_File_Information_Ex
        (Left, File_Id_Info_Class, Left_Id'Address,
         C_DWord (File_Id_Info'Size / 8)) /= 0
        and then Get_File_Information_Ex
          (Right, File_Id_Info_Class, Right_Id'Address,
           C_DWord (File_Id_Info'Size / 8)) /= 0
        and then Left_Id = Right_Id;
   end Same_File;

   function Owned_By_Current_Token (Handle : System.Address) return Boolean is
      Owner, Descriptor, Token : aliased System.Address := System.Null_Address;
      Security_Status : C_DWord;
      Needed : aliased C_DWord := 0;
      Buffer : aliased Byte_Buffer (0 .. 2_047) := [others => 0];
      Token_Owner : System.Address
        with Import, Address => Buffer'Address;
      Ok : Boolean;
      Ignored_Int : C_Int;
      Ignored_Address : System.Address;
   begin
      Security_Status := Get_Security_Info
        (Handle, Se_File_Object, Owner_Security_Information,
         Owner'Address, System.Null_Address, System.Null_Address,
         System.Null_Address, Descriptor'Access);
      Ok := Security_Status = 0
        and then Open_Process_Token
          (Get_Current_Process, Token_Query, Token'Access) /= 0;
      if Ok then
         Ok := Get_Token_Information
           (Token, Token_Owner_Class, Buffer'Address,
            C_DWord (Buffer'Length), Needed'Access) /= 0
           and then Equal_Sid (Owner, Token_Owner) /= 0;
      end if;
      if Token /= System.Null_Address then
         Ignored_Int := Close_Handle (Token);
      end if;
      if Descriptor /= System.Null_Address then
         Ignored_Address := Local_Free (Descriptor);
      end if;
      return Ok;
   exception
      when others =>
         if Token /= System.Null_Address then
            Ignored_Int := Close_Handle (Token);
         end if;
         if Descriptor /= System.Null_Address then
            Ignored_Address := Local_Free (Descriptor);
         end if;
         return False;
   end Owned_By_Current_Token;

   function Set_Private (Handle : System.Address) return Boolean is
      Text : aliased Wide_String := Wide ("D:P(A;OICI;FA;;;OW)");
      Descriptor, Dacl : aliased System.Address := System.Null_Address;
      Present, Defaulted : aliased C_Int := 0;
      Ok : Boolean := Owned_By_Current_Token (Handle)
        and then Convert_Sddl
          (Text'Address, Sddl_Revision_1, Descriptor'Access,
           System.Null_Address) /= 0;
      Ignored : System.Address;
   begin
      if Ok then
         Ok := Get_Descriptor_Dacl
           (Descriptor, Present'Access, Dacl'Access, Defaulted'Access) /= 0
           and then Present /= 0;
      end if;
      if Ok then
         Ok := Set_Security_Info
           (Handle, Se_File_Object,
            Dacl_Security_Information + Protected_Dacl_Information,
            System.Null_Address, System.Null_Address, Dacl,
            System.Null_Address) = 0;
      end if;
      if Descriptor /= System.Null_Address then
         Ignored := Local_Free (Descriptor);
      end if;
      return Ok;
   exception
      when others =>
         if Descriptor /= System.Null_Address then
            Ignored := Local_Free (Descriptor);
         end if;
         return False;
   end Set_Private;

   function Private_Descriptor return System.Address is
      Text : aliased Wide_String := Wide ("D:P(A;OICI;FA;;;OW)");
      Descriptor : aliased System.Address := System.Null_Address;
   begin
      if Convert_Sddl
        (Text'Address, Sddl_Revision_1, Descriptor'Access,
         System.Null_Address) = 0
      then
         return System.Null_Address;
      end if;
      return Descriptor;
   end Private_Descriptor;

   function Create_Directory (Path : String) return Create_Outcome is
      Name : aliased Wide_String := Wide (Path);
      Descriptor : constant System.Address := Private_Descriptor;
      Attributes : aliased Security_Attributes :=
        (Length => C_DWord (Security_Attributes'Size / 8),
         Security_Descriptor => Descriptor,
         Inherit_Handle => 0);
      Ok : Boolean;
      Error : C_DWord;
      Ignored : System.Address;
   begin
      if Descriptor = System.Null_Address then
         return Create_Error;
      end if;
      Ok := Create_Directory_W (Name'Address, Attributes'Access) /= 0;
      Error := Get_Last_Error;
      Ignored := Local_Free (Descriptor);
      if Ok then
         return Created;
      elsif Error = Error_Already_Exists or else Error = Error_File_Exists then
         return Already_Exists;
      else
         return Create_Error;
      end if;
   exception
      when others =>
         return Create_Error;
   end Create_Directory;

   function Ensure_Directory (Path : String) return Boolean is
      Outcome : constant Create_Outcome := Create_Directory (Path);
   begin
      if Outcome = Created then
         return True;
      elsif Outcome = Create_Error then
         return False;
      end if;
      declare
         Name : aliased Wide_String := Wide (Path);
         Handle : constant System.Address := Create_File_W
           (Name'Address, Read_Control + Write_Dac + File_Read_Attributes,
            File_Share_All, System.Null_Address, Open_Existing,
            File_Flag_Backup_Semantics + File_Flag_Open_Reparse_Point,
            System.Null_Address);
         Info : aliased By_Handle_File_Information;
         Ok : Boolean := Handle /= Invalid_Handle
           and then Get_File_Information (Handle, Info'Access) /= 0
           and then (Info.Attributes and File_Attribute_Directory) /= 0
           and then (Info.Attributes and File_Attribute_Reparse_Point) = 0
           and then Set_Private (Handle);
         Ignored : C_Int;
      begin
         if Handle /= Invalid_Handle then
            Ignored := Close_Handle (Handle);
         end if;
         return Ok;
      end;
   exception
      when others =>
         return False;
   end Ensure_Directory;

   function Restrict_Open_File (Descriptor : Integer) return Boolean is
      Original : constant System.Address := Osfhandle (C_Int (Descriptor));
      Count : C_DWord;
   begin
      if Original = Invalid_Handle then
         return False;
      end if;
      Count := Get_Final_Path
        (Original, System.Null_Address, 0, 0);
      if Count = 0 then
         return False;
      end if;
      declare
         Name : aliased Wide_String (1 .. Natural (Count) + 1) :=
           [others => Wide_Character'Val (0)];
         Actual : constant C_DWord := Get_Final_Path
           (Original, Name'Address, C_DWord (Name'Length), 0);
         Reopened : System.Address := Invalid_Handle;
         Ok : Boolean := Actual > 0 and then Actual < C_DWord (Name'Length);
         Ignored : C_Int;
      begin
         if Ok then
            Reopened := Create_File_W
              (Name'Address, Read_Control + Write_Dac + File_Read_Attributes,
               File_Share_All, System.Null_Address, Open_Existing,
               File_Flag_Open_Reparse_Point, System.Null_Address);
            Ok := Reopened /= Invalid_Handle
              and then Same_File (Original, Reopened)
              and then Set_Private (Reopened);
         end if;
         if Reopened /= Invalid_Handle then
            Ignored := Close_Handle (Reopened);
         end if;
         return Ok;
      end;
   exception
      when others =>
         return False;
   end Restrict_Open_File;

end Hostkit.Private_Paths;
