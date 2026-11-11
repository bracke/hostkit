with Ada.Calendar.Formatting;
with Ada.Characters.Handling;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Strings.UTF_Encoding;
with Ada.Containers.Vectors;

with Hostkit.Errors;
with Hostkit.Fs;
with Hostkit.Path_Text;
with Hostkit.Windows_Errors;
with Hostkit.Windows_Paths;
with Interfaces.C;
with System;
with System.Storage_Elements;

with Hostkit.Metadata.Natural_Ids;

package body Hostkit.Metadata is
   use type Hostkit.Fs.Entry_Kind;

   use Ada.Strings.Unbounded;
   use type Ada.Calendar.Time;
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned;
   use type Interfaces.C.unsigned_char;
   use type Interfaces.C.unsigned_short;
   use type Interfaces.C.unsigned_long;
   use type Interfaces.C.unsigned_long_long;
   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_64;
   use type System.Address;

   subtype C_Int is Interfaces.C.int;
   subtype C_DWord is Interfaces.C.unsigned_long;
   subtype C_U64 is Interfaces.C.unsigned_long_long;

   --  Windows has no POSIX mode bits and no uid/gid. It has an ACL and SIDs, so
   --  that is what this reads and writes: the effective rights of the owner, the
   --  primary group and Everyone are evaluated and folded into the rwx triplets
   --  the neutral interface speaks, and setting permissions builds a fresh DACL
   --  granting exactly those rights back. A SID is identified to the caller by
   --  a stable hash of all its bytes, and the SID itself is remembered so a name
   --  can be recovered from that number later.

   Success : constant C_DWord := 0;
   Invalid_Handle_Value : constant System.Address :=
     System.Storage_Elements.To_Address (System.Storage_Elements.Integer_Address'Last);

   Se_File_Object : constant C_Int := 1;

   Owner_Information : constant C_DWord := 16#0000_0001#;
   Group_Information : constant C_DWord := 16#0000_0002#;
   Dacl_Information  : constant C_DWord := 16#0000_0004#;

   Trustee_Is_Sid     : constant C_Int := 0;
   Trustee_Is_Unknown : constant C_Int := 0;
   Grant_Access       : constant C_Int := 1;
   No_Inheritance     : constant C_DWord := 0;

   File_Generic_Read    : constant C_DWord := 16#0012_0089#;
   File_Generic_Write   : constant C_DWord := 16#0012_0116#;
   File_Generic_Execute : constant C_DWord := 16#0012_00A0#;
   File_Read_Data       : constant C_DWord := 16#0000_0001#;
   File_Write_Data      : constant C_DWord := 16#0000_0002#;
   File_Execute_Access  : constant C_DWord := 16#0000_0020#;
   Delete_Access        : constant C_DWord := 16#0001_0000#;
   Read_Control         : constant C_DWord := 16#0002_0000#;
   Write_Dac            : constant C_DWord := 16#0004_0000#;
   Write_Owner          : constant C_DWord := 16#0008_0000#;

   Win_World_Sid : constant C_Int := 1;
   --  WinWorldSid: the "Everyone" group, which stands in for the POSIX "other".

   Read_Only_Volume : constant C_DWord := 16#0008_0000#;
   File_Read_Attributes  : constant C_DWord := 16#0000_0080#;
   File_Write_Attributes : constant C_DWord := 16#0000_0100#;
   File_Share_Read       : constant C_DWord := 16#0000_0001#;
   File_Share_Write      : constant C_DWord := 16#0000_0002#;
   File_Share_Delete     : constant C_DWord := 16#0000_0004#;
   Open_Existing         : constant C_DWord := 3;
   File_Attribute_Normal : constant C_DWord := 16#0000_0080#;
   File_Flag_Backup_Semantics : constant C_DWord := 16#0200_0000#;
   File_Flag_Open_Reparse_Point : constant C_DWord := 16#0020_0000#;
   File_Attribute_Reparse_Point  : constant C_DWord := 16#0000_0400#;
   File_Basic_Info_Class : constant C_Int := 0;
   File_Id_Info_Class    : constant C_Int := 18;

   type Trustee_Record is record
      Multiple_Trustee : System.Address := System.Null_Address;
      Multiple_Operation : C_Int := 0;
      Form : C_Int := 0;
      Kind : C_Int := 0;
      Padding : C_Int := 0;
      Name : System.Address := System.Null_Address;
   end record
     with Convention => C;

   type Explicit_Access_Record is record
      Permissions : C_DWord := 0;
      Mode        : C_Int := 0;
      Inheritance : C_DWord := 0;
      Padding     : C_Int := 0;
      Trustee     : aliased Trustee_Record;
   end record
     with Convention => C;

   type Explicit_Access_Array is
     array (1 .. 3) of aliased Explicit_Access_Record
     with Convention => C;

   type Filetime is record
      Low  : C_DWord := 0;
      High : C_DWord := 0;
   end record
     with Convention => C;

   type Attribute_Data is record
      Attributes     : C_DWord := 0;
      Creation_Time  : Filetime;
      Access_Time    : Filetime;
      Modified_Time  : Filetime;
      Size_High      : C_DWord := 0;
      Size_Low       : C_DWord := 0;
   end record
     with Convention => C;

   type By_Handle_File_Information is record
      Attributes      : C_DWord := 0;
      Creation_Time   : Filetime;
      Access_Time     : Filetime;
      Modified_Time   : Filetime;
      Volume_Serial   : C_DWord := 0;
      Size_High       : C_DWord := 0;
      Size_Low        : C_DWord := 0;
      Link_Count      : C_DWord := 0;
      File_Index_High : C_DWord := 0;
      File_Index_Low  : C_DWord := 0;
   end record
     with Convention => C;

   type Identifier_Array is array (Natural range 0 .. 15) of Interfaces.Unsigned_8
     with Convention => C;

   type File_Id_Info is record
      Volume_Serial : Identity_Field := 0;
      Identifier    : Identifier_Array := [others => 0];
   end record
     with Convention => C;

   type File_Basic_Info is record
      Creation_Time : Interfaces.Integer_64 := 0;
      Access_Time   : Interfaces.Integer_64 := 0;
      Modified_Time : Interfaces.Integer_64 := 0;
      Change_Time   : Interfaces.Integer_64 := 0;
      Attributes    : C_DWord := 0;
   end record
     with Convention => C;
   for File_Basic_Info'Size use 40 * 8;

   --  Getting a layout wrong here does not fail loudly; it reads the wrong field
   --  and reports plausible nonsense. Pin the sizes, so the compiler catches any
   --  drift on any host.
   pragma Compile_Time_Error
     (Trustee_Record'Size /= 32 * 8, "Win32 TRUSTEE_A must be 32 bytes on x64");
   pragma Compile_Time_Error
     (Explicit_Access_Record'Size /= 48 * 8,
      "Win32 EXPLICIT_ACCESS_A must be 48 bytes on x64");
   pragma Compile_Time_Error
     (Attribute_Data'Size /= 36 * 8,
      "Win32 WIN32_FILE_ATTRIBUTE_DATA must be 36 bytes");

   function Get_Named_Security_Info
     (Object_Name : System.Address;
      Object_Type : C_Int;
      Information : C_DWord;
      Owner       : access System.Address;
      Group       : access System.Address;
      Dacl        : access System.Address;
      Sacl        : access System.Address;
      Descriptor  : access System.Address) return C_DWord
     with Import, Convention => Stdcall,
          External_Name => "GetNamedSecurityInfoW";

   function Set_Named_Security_Info
     (Object_Name : System.Address;
      Object_Type : C_Int;
      Information : C_DWord;
      Owner       : System.Address;
      Group       : System.Address;
      Dacl        : System.Address;
      Sacl        : System.Address) return C_DWord
     with Import, Convention => Stdcall,
          External_Name => "SetNamedSecurityInfoW";

   function Get_Security_Info
     (Handle      : System.Address;
      Object_Type : C_Int;
      Information : C_DWord;
      Owner       : access System.Address;
      Group       : access System.Address;
      Dacl        : access System.Address;
      Sacl        : access System.Address;
      Descriptor  : access System.Address) return C_DWord
     with Import, Convention => Stdcall,
          External_Name => "GetSecurityInfo";

   function Set_Security_Info
     (Handle      : System.Address;
      Object_Type : C_Int;
      Information : C_DWord;
      Owner       : System.Address;
      Group       : System.Address;
      Dacl        : System.Address;
      Sacl        : System.Address) return C_DWord
     with Import, Convention => Stdcall,
          External_Name => "SetSecurityInfo";

   --  The low-level calls below set a DACL on the one object named. The
   --  SetNamedSecurityInfo and SetSecurityInfo family also push inheritance
   --  down to what a directory holds: a directory's fresh, non-inheritable
   --  DACL there strips its children of the ACEs they inherited, and a child
   --  with no others is left readable by no one.
   Security_Descriptor_Revision : constant C_DWord := 1;
   --  SE_DACL_PROTECTED. Without it the new DACL is merged with whatever the
   --  parent directory hands down, so revoking a right does not revoke it: an
   --  inherited ACE keeps granting it, and a mode set to 0600 reads back with
   --  the group and Everyone bits still on.
   Se_Dacl_Protected : constant Interfaces.C.unsigned_short := 16#1000#;

   --  An absolute SECURITY_DESCRIPTOR: 20 bytes on 32-bit, 40 on 64-bit.
   type Descriptor_Buffer is array (1 .. 8) of Interfaces.Unsigned_64
     with Convention => C;

   function Initialize_Security_Descriptor
     (Descriptor : System.Address;
      Revision   : C_DWord) return C_Int
     with Import, Convention => Stdcall,
          External_Name => "InitializeSecurityDescriptor";

   function Set_Security_Descriptor_Dacl
     (Descriptor : System.Address;
      Present    : C_Int;
      Dacl       : System.Address;
      Defaulted  : C_Int) return C_Int
     with Import, Convention => Stdcall,
          External_Name => "SetSecurityDescriptorDacl";

   function Set_Security_Descriptor_Control
     (Descriptor : System.Address;
      Interest   : Interfaces.C.unsigned_short;
      Set        : Interfaces.C.unsigned_short) return C_Int
     with Import, Convention => Stdcall,
          External_Name => "SetSecurityDescriptorControl";

   function Set_File_Security
     (File_Name   : System.Address;
      Information : C_DWord;
      Descriptor  : System.Address) return C_Int
     with Import, Convention => Stdcall,
          External_Name => "SetFileSecurityW";

   function Set_Kernel_Object_Security
     (Handle      : System.Address;
      Information : C_DWord;
      Descriptor  : System.Address) return C_Int
     with Import, Convention => Stdcall,
          External_Name => "SetKernelObjectSecurity";

   --  SE_DACL_AUTO_INHERITED: the DACL's inherited ACEs came by automatic
   --  inheritance, so a later change to the parent knows them for its own.
   Se_Dacl_Auto_Inherited : constant Interfaces.C.unsigned_short := 16#0400#;

   --  The control bits a DACL written here carries over: whether it is
   --  protected, and whether its inherited ACEs are automatic ones.
   Dacl_Control_Bits : constant Interfaces.C.unsigned_short := Se_Dacl_Protected or Se_Dacl_Auto_Inherited;

   --  Set Dacl on the object named by the NUL-terminated wide Path, or else
   --  open as Handle, with Control's protection and auto-inheritance bits
   --  (Dacl_Control_Bits) -- by default protected from what the parent hands
   --  down. The object alone: nothing is handed down anew to what a folder
   --  holds. Whether it was set.
   function Set_Own_Dacl
     (Path    : System.Address;
      Handle  : System.Address;
      Dacl    : System.Address;
      Control : Interfaces.C.unsigned_short := Se_Dacl_Protected) return Boolean
   is
      Descriptor : aliased Descriptor_Buffer := [others => 0];
   begin
      if Initialize_Security_Descriptor
           (Descriptor'Address, Security_Descriptor_Revision) = 0
        or else Set_Security_Descriptor_Dacl
                  (Descriptor'Address, 1, Dacl, 0) = 0
        or else Set_Security_Descriptor_Control
                  (Descriptor'Address, Dacl_Control_Bits,
                   Control and Dacl_Control_Bits) = 0
      then
         Hostkit.Errors.Set_Errno_From_Last_Error;
         return False;
      elsif (if Path /= System.Null_Address
             then Set_File_Security (Path, Dacl_Information, Descriptor'Address) /= 0
             else Set_Kernel_Object_Security (Handle, Dacl_Information, Descriptor'Address) /= 0)
      then
         return True;
      end if;
      Hostkit.Errors.Set_Errno_From_Last_Error;
      return False;
   end Set_Own_Dacl;

   procedure Build_Trustee_With_Sid
     (Trustee : access Trustee_Record;
      Sid     : System.Address)
     with Import, Convention => Stdcall,
          External_Name => "BuildTrusteeWithSidA";

   function Get_Effective_Rights_From_Acl
     (Acl     : System.Address;
      Trustee : access Trustee_Record;
      Rights  : access C_DWord) return C_DWord
     with Import, Convention => Stdcall,
          External_Name => "GetEffectiveRightsFromAclA";

   function Set_Entries_In_Acl
     (Count   : C_DWord;
      Entries : System.Address;
      Old_Acl : System.Address;
      New_Acl : access System.Address) return C_DWord
     with Import, Convention => Stdcall,
          External_Name => "SetEntriesInAclA";

   function Lookup_Account_Sid_Wide
     (System_Name : System.Address;
      Sid         : System.Address;
      Name        : System.Address;
      Name_Size   : access C_DWord;
      Domain      : System.Address;
      Domain_Size : access C_DWord;
      Use_Kind    : access C_Int) return C_Int
     with Import, Convention => Stdcall,
          External_Name => "LookupAccountSidW";

   function Lookup_Account_Name_Wide
     (System_Name : System.Address;
      Account     : System.Address;
      Sid         : System.Address;
      Sid_Size    : access C_DWord;
      Domain      : System.Address;
      Domain_Size : access C_DWord;
      Use_Kind    : access C_Int) return C_Int
     with Import, Convention => Stdcall,
          External_Name => "LookupAccountNameW";

   function Get_Length_Sid (Sid : System.Address) return C_DWord
     with Import, Convention => Stdcall, External_Name => "GetLengthSid";

   function Copy_Sid
     (Length      : C_DWord;
      Destination : System.Address;
      Source      : System.Address) return C_Int
     with Import, Convention => Stdcall, External_Name => "CopySid";

   function Create_Well_Known_Sid
     (Kind       : C_Int;
      Domain_Sid : System.Address;
      Sid        : System.Address;
      Size       : access C_DWord) return C_Int
     with Import, Convention => Stdcall,
          External_Name => "CreateWellKnownSid";

   function Local_Free (Item : System.Address) return System.Address
     with Import, Convention => Stdcall, External_Name => "LocalFree";

   function Get_File_Attributes_Ex
     (Name  : System.Address;
      Level : C_Int;
      Data  : access Attribute_Data) return C_Int
     with Import, Convention => Stdcall,
          External_Name => "GetFileAttributesExW";

   function Get_Disk_Free_Space_Ex
     (Directory       : System.Address;
      Free_To_Caller  : access C_U64;
      Total           : access C_U64;
      Total_Free      : access C_U64) return C_Int
     with Import, Convention => Stdcall,
          External_Name => "GetDiskFreeSpaceExW";

   function Get_Volume_Information
     (Root         : System.Address;
      Name         : System.Address;
      Name_Size    : C_DWord;
      Serial       : access C_DWord;
      Component    : access C_DWord;
      Flags        : access C_DWord;
      System_Name  : System.Address;
      System_Size  : C_DWord) return C_Int
     with Import, Convention => Stdcall,
          External_Name => "GetVolumeInformationW";

   function Get_Final_Path_Name
     (File   : System.Address;
      Path   : System.Address;
      Length : C_DWord;
      Flags  : C_DWord) return C_DWord
     with Import, Convention => Stdcall,
          External_Name => "GetFinalPathNameByHandleW";

   function Create_File_Wide
     (Name        : System.Address;
      Access_Mode : C_DWord;
      Share       : C_DWord;
      Security    : System.Address;
      Disposition : C_DWord;
      Flags       : C_DWord;
      Template    : System.Address) return System.Address
     with Import, Convention => Stdcall, External_Name => "CreateFileW";

   function Get_File_Information
     (File : System.Address;
      Info : access By_Handle_File_Information) return C_Int
     with Import, Convention => Stdcall, External_Name => "GetFileInformationByHandle";

   function Get_File_Information_Ex
     (File  : System.Address;
      Kind  : C_Int;
      Info  : System.Address;
      Bytes : C_DWord) return C_Int
     with Import, Convention => Stdcall, External_Name => "GetFileInformationByHandleEx";

   function Close_Handle (Item : System.Address) return C_Int
     with Import, Convention => Stdcall, External_Name => "CloseHandle";

   function Set_File_Time
     (File          : System.Address;
      Creation_Time : System.Address;
      Access_Time   : access Filetime;
      Modified_Time : access Filetime) return C_Int
     with Import, Convention => Stdcall, External_Name => "SetFileTime";

   --------------------------------------------------------------------------
   --  SID identity
   --------------------------------------------------------------------------

   type Sid_Buffer is array (1 .. 256) of aliased Interfaces.C.char;

   type Known_Sid is record
      Id     : Natural := 0;
      Length : Natural := 0;
      Bytes  : Sid_Buffer := [others => Interfaces.C.nul];
   end record;

   package Sid_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Known_Sid);

   --  A SID has no small integer identity of its own. Hash the complete SID,
   --  rather than using only its last relative identifier: accounts from two
   --  domains can legitimately have the same RID. The SID itself is kept here
   --  so the number can be turned back into a name.
   Seen_Sids : Sid_Vectors.Vector;

   procedure Remember (Sid : System.Address; Id : Natural);
   function Recall (Id : Natural; Into : out Sid_Buffer) return Boolean;
   function Identity_Of (Sid : System.Address) return Natural;
   function Name_Of (Sid : System.Address) return String;
   function Wide (Value : String) return Wide_String;

   function Identity_Of (Sid : System.Address) return Natural is
      Length : C_DWord;
      Hash   : Interfaces.Unsigned_64 := 16#CBF2_9CE4_8422_2325#;
   begin
      if Sid = System.Null_Address then
         return 0;
      end if;
      Length := Get_Length_Sid (Sid);
      if Length = 0 or else Natural (Length) > Sid_Buffer'Length then
         return 0;
      end if;
      declare
         type Byte_Array is array (Natural range <>) of Interfaces.Unsigned_8
           with Convention => C;
         Bytes : Byte_Array (0 .. Natural (Length) - 1)
           with Import, Address => Sid;
      begin
         for Byte of Bytes loop
            Hash := (Hash xor Interfaces.Unsigned_64 (Byte))
              * 1_099_511_628_211;
         end loop;
      end;
      return Natural
        (Hash mod Interfaces.Unsigned_64 (Natural'Last - 1)) + 1;

   exception
      when others =>
         return 0;
   end Identity_Of;

   procedure Remember (Sid : System.Address; Id : Natural) is
      Length : C_DWord;
   begin
      if Sid = System.Null_Address or else Id = 0 then
         return;
      end if;

      for Item of Seen_Sids loop
         if Item.Id = Id then
            return;
         end if;
      end loop;

      Length := Get_Length_Sid (Sid);
      if Length = 0 or else Natural (Length) > Sid_Buffer'Length then
         return;
      end if;

      declare
         Item   : Known_Sid;
         Copied : C_Int;
      begin
         Item.Id := Id;
         Item.Length := Natural (Length);
         Copied := Copy_Sid (Length, Item.Bytes (1)'Address, Sid);
         if Copied /= 0 then
            Seen_Sids.Append (Item);
         end if;
      end;

   exception
      when others =>
         null;
   end Remember;

   function Recall (Id : Natural; Into : out Sid_Buffer) return Boolean is
   begin
      Into := [others => Interfaces.C.nul];

      for Item of Seen_Sids loop
         if Item.Id = Id then
            Into := Item.Bytes;
            return True;
         end if;
      end loop;

      return False;
   end Recall;

   function Name_Of (Sid : System.Address) return String is
      Name_Size   : aliased C_DWord := 0;
      Domain_Size : aliased C_DWord := 0;
      Use_Kind    : aliased C_Int := 0;
      Ignored     : C_Int;
   begin
      if Sid = System.Null_Address then
         return "";
      end if;

      Ignored := Lookup_Account_Sid_Wide
        (System.Null_Address, Sid, System.Null_Address, Name_Size'Access,
         System.Null_Address, Domain_Size'Access, Use_Kind'Access);
      if Name_Size = 0 then
         return "";
      end if;

      declare
         Name : aliased Wide_String (1 .. Natural (Name_Size)) :=
           [others => Wide_Character'Val (0)];
         Domain : aliased Wide_String
           (1 .. Natural'Max (1, Natural (Domain_Size))) :=
             [others => Wide_Character'Val (0)];

         function Text_Of (Value : Wide_String) return String is
            Last : Integer := Value'Last;
         begin
            for Index in Value'Range loop
               if Value (Index) = Wide_Character'Val (0) then
                  Last := Index - 1;
                  exit;
               end if;
            end loop;
            return
              (if Last < Value'First then ""
               else Hostkit.Windows_Paths.To_UTF_8
                 (Value (Value'First .. Last)));
         end Text_Of;
      begin
         if Lookup_Account_Sid_Wide
           (System.Null_Address, Sid, Name'Address, Name_Size'Access,
            Domain'Address, Domain_Size'Access, Use_Kind'Access) = 0
         then
            return "";
         end if;
         declare
            Account : constant String := Text_Of (Name);
            Realm   : constant String := Text_Of (Domain);
         begin
            return (if Realm = "" then Account else Realm & '\' & Account);
         end;
      end;

   exception
      when others =>
         return "";
   end Name_Of;

   --------------------------------------------------------------------------

   function Runs_On_Windows (Path : String) return Boolean;

   function Runs_On_Windows (Path : String) return Boolean is
      --  Windows does not decide what runs from an ACL. Every ordinary file is
      --  granted FILE_EXECUTE in its DACL, so folding that bit into the mode said
      --  that everything is executable -- and the file manager duly classified a
      --  .tar.gz as a program. What runs here is decided by the extension,
      --  and tested without allocating one.
      --
      --  This was an array of `access constant String` filled with `new
      --  String'(".exe")` and the rest: six allocations that nothing ever
      --  frees, made afresh on every call, to hold six literals known at
      --  compile time. GNAT warns about the anonymous access allocator, and it
      --  is right to.
      Dot : constant Natural :=
        Ada.Strings.Fixed.Index (Path, ".", Ada.Strings.Backward);

      Suffix : constant String :=
        (if Dot = 0 then ""
         else Ada.Characters.Handling.To_Lower (Path (Dot .. Path'Last)));
   begin
      return Suffix = ".exe" or else Suffix = ".com" or else Suffix = ".bat"
        or else Suffix = ".cmd" or else Suffix = ".ps1"
        or else Suffix = ".msi";
   end Runs_On_Windows;

   function Rights_To_Triplet (Rights : C_DWord) return Natural;

   function Rights_To_Triplet (Rights : C_DWord) return Natural is
      Result : Natural := 0;
   begin
      if (Rights and File_Read_Data) /= 0 then
         Result := Result + 4;
      end if;
      if (Rights and File_Write_Data) /= 0 then
         Result := Result + 2;
      end if;
      if (Rights and File_Execute_Access) /= 0 then
         Result := Result + 1;
      end if;
      return Result;
   end Rights_To_Triplet;

   function Triplet_To_Rights (Triplet : Natural) return C_DWord;

   function Triplet_To_Rights (Triplet : Natural) return C_DWord is
      Result : C_DWord := 0;
   begin
      if (Triplet / 4) mod 2 = 1 then
         Result := Result or File_Generic_Read;
      end if;
      if (Triplet / 2) mod 2 = 1 then
         Result := Result or File_Generic_Write or Delete_Access;
      end if;
      if Triplet mod 2 = 1 then
         Result := Result or File_Generic_Execute;
      end if;
      return Result;
   end Triplet_To_Rights;

   function File_Creation_Time
     (Path      : String;
      Available : out Boolean) return Ada.Calendar.Time
   is
      C_Path : aliased Wide_String := Wide (Path);
      Data   : aliased Attribute_Data;
      Result : C_Int;
      --  The Unix epoch, in UTC: Ada.Calendar.Time_Of would read it as local
      --  midnight and shift every time by the zone's 1970 offset.
      Epoch  : constant Ada.Calendar.Time := Ada.Calendar.Formatting.Time_Of (1970, 1, 1, 0.0, Time_Zone => 0);
   begin
      Available := False;

      Result := Get_File_Attributes_Ex (C_Path'Address, 0, Data'Access);

      if Result = 0 then
         return Ada.Calendar.Time_Of (1901, 1, 1);
      end if;

      declare
         --  FILETIME counts 100-nanosecond ticks from 1601; Unix time starts
         --  11644473600 seconds later.
         Ticks : constant C_U64 :=
           C_U64 (Data.Creation_Time.High) * 2 ** 32
           + C_U64 (Data.Creation_Time.Low);
         Unix  : constant Long_Long_Integer :=
           Long_Long_Integer (Ticks / 10_000_000) - 11_644_473_600;
      begin
         if Unix <= 0 then
            return Ada.Calendar.Time_Of (1901, 1, 1);
         end if;

         Available := True;
         return Epoch + Duration (Unix);
      end;

   exception
      when others =>
         Available := False;
         return Ada.Calendar.Time_Of (1901, 1, 1);
   end File_Creation_Time;

   function File_Access_Time
     (Path      : String;
      Available : out Boolean) return Ada.Calendar.Time
   is
      C_Path : aliased Wide_String := Wide (Path);
      Data   : aliased Attribute_Data;
      Result : C_Int;
      --  The Unix epoch, in UTC: Ada.Calendar.Time_Of would read it as local
      --  midnight and shift every time by the zone's 1970 offset.
      Epoch  : constant Ada.Calendar.Time := Ada.Calendar.Formatting.Time_Of (1970, 1, 1, 0.0, Time_Zone => 0);
   begin
      Available := False;

      Result := Get_File_Attributes_Ex (C_Path'Address, 0, Data'Access);

      if Result = 0 then
         return Ada.Calendar.Time_Of (1901, 1, 1);
      end if;

      declare
         Ticks : constant C_U64 :=
           C_U64 (Data.Access_Time.High) * 2 ** 32
           + C_U64 (Data.Access_Time.Low);
         Unix  : constant Long_Long_Integer :=
           Long_Long_Integer (Ticks / 10_000_000) - 11_644_473_600;
      begin
         if Unix <= 0 then
            return Ada.Calendar.Time_Of (1901, 1, 1);
         end if;

         Available := True;
         return Epoch + Duration (Unix);
      end;

   exception
      when others =>
         Available := False;
         return Ada.Calendar.Time_Of (1901, 1, 1);
   end File_Access_Time;

   function Volume_Capacity_Of (Path : String) return Volume_Capacity is
      C_Path : aliased Wide_String := Wide (Path);

      Free_To_Caller : aliased C_U64 := 0;
      Total          : aliased C_U64 := 0;
      Total_Free     : aliased C_U64 := 0;

      Serial    : aliased C_DWord := 0;
      Component : aliased C_DWord := 0;
      Flags     : aliased C_DWord := 0;

      Answer : Volume_Capacity;
      Result : C_Int;
   begin
      Result :=
        Get_Disk_Free_Space_Ex
          (C_Path'Address, Free_To_Caller'Access, Total'Access, Total_Free'Access);

      if Result /= 0 then
         Answer.Available := True;
         Answer.Capacity_Bytes := Long_Long_Integer (Total);
         Answer.Free_Bytes := Long_Long_Integer (Free_To_Caller);
      end if;

      --  Windows keeps no inode count; the name limit and the read-only flag come
      --  from the volume rather than the file -- and GetVolumeInformation insists
      --  on the volume's ROOT, "C:\", not a directory anywhere inside it. Handed
      --  a path like C:\Users\... it simply fails, and the read-only flag and the
      --  name limit were reported as unknown for every volume.
      declare
         Root : aliased Wide_String :=
           Wide (if Path'Length >= 2 and then Path (Path'First + 1) = ':'
                 then Path (Path'First .. Path'First + 1) & "\"
                 else Path);
      begin
         Result :=
           Get_Volume_Information
             (Root'Address,
              System.Null_Address, 0,
              Serial'Access, Component'Access, Flags'Access,
              System.Null_Address, 0);
      end;

      if Result /= 0 then
         Answer.Name_Max := Natural (Component);
         Answer.Name_Max_Known := True;
         Answer.Read_Only := (Flags and Read_Only_Volume) /= 0;
         Answer.Read_Only_Known := True;
      end if;

      return Answer;

   exception
      when others =>
         return (others => <>);
   end Volume_Capacity_Of;

   function File_Permission_Bits
     (Path      : String;
      Available : out Boolean) return Natural
   is
      C_Path : aliased Wide_String := Wide (Path);

      Owner      : aliased System.Address := System.Null_Address;
      Group      : aliased System.Address := System.Null_Address;
      Dacl       : aliased System.Address := System.Null_Address;
      Sacl       : aliased System.Address := System.Null_Address;
      Descriptor : aliased System.Address := System.Null_Address;

      Status : C_DWord;
      Mode   : Natural := 0;

      function Rights_For (Sid : System.Address) return Natural;

      function Rights_For (Sid : System.Address) return Natural is
         Trustee : aliased Trustee_Record;
         Rights  : aliased C_DWord := 0;
      begin
         if Sid = System.Null_Address or else Dacl = System.Null_Address then
            return 0;
         end if;

         Build_Trustee_With_Sid (Trustee'Access, Sid);
         Trustee.Form := Trustee_Is_Sid;
         Trustee.Kind := Trustee_Is_Unknown;

         if Get_Effective_Rights_From_Acl
              (Dacl, Trustee'Access, Rights'Access) /= Success
         then
            return 0;
         end if;

         return Rights_To_Triplet (Rights);
      end Rights_For;

      Everyone      : aliased Sid_Buffer := [others => Interfaces.C.nul];
      Everyone_Size : aliased C_DWord := C_DWord (Sid_Buffer'Length);

      procedure Free_Descriptor is
         Freed : System.Address;
         pragma Unreferenced (Freed);
      begin
         if Descriptor /= System.Null_Address then
            Freed := Local_Free (Descriptor);
            Descriptor := System.Null_Address;
         end if;
      end Free_Descriptor;
   begin
      Available := False;

      Status :=
        Get_Named_Security_Info
          (C_Path'Address, Se_File_Object,
           Owner_Information or Group_Information or Dacl_Information,
           Owner'Access, Group'Access, Dacl'Access, Sacl'Access,
           Descriptor'Access);

      if Status /= Success then
         return 0;
      end if;

      Remember (Owner, Identity_Of (Owner));
      Remember (Group, Identity_Of (Group));

      Mode := Rights_For (Owner) * 64 + Rights_For (Group) * 8;

      if Create_Well_Known_Sid
           (Win_World_Sid, System.Null_Address,
            Everyone (1)'Address, Everyone_Size'Access) /= 0
      then
         Mode := Mode + Rights_For (Everyone (1)'Address);
      end if;

      Free_Descriptor;

      --  Strip the execute bits unless the file is one Windows would actually
      --  run. A directory keeps them: its execute bit means it can be entered,
      --  as the DACL grants.
      if not Runs_On_Windows (Path)
        and then Hostkit.Fs.Kind_Of (Path) /= Hostkit.Fs.Directory_Entry
      then
         declare
            Owner_Bits : constant Natural := (Mode / 64) mod 8;
            Group_Bits : constant Natural := (Mode / 8) mod 8;
            Other_Bits : constant Natural := Mode mod 8;

            function Without_Execute (Triplet : Natural) return Natural is
              (Triplet - (Triplet mod 2));
         begin
            Mode :=
              Without_Execute (Owner_Bits) * 64
              + Without_Execute (Group_Bits) * 8
              + Without_Execute (Other_Bits);
         end;
      end if;

      Available := True;
      return Mode;

   exception
      when others =>
         Free_Descriptor;
         Available := False;
         return 0;
   end File_Permission_Bits;

   --  A permission edit, the minimal kind: see Set_Permissions in the spec.

   Set_Access    : constant C_Int := 2;
   Deny_Access   : constant C_Int := 3;
   Revoke_Access : constant C_Int := 4;

   File_Append_Data         : constant C_DWord := 16#0000_0004#;
   File_Attribute_Directory : constant C_DWord := 16#0000_0010#;
   Sddl_Revision            : constant C_DWord := 1;

   function Get_Security_Descriptor_Control
     (Descriptor : System.Address;
      Control    : access Interfaces.C.unsigned_short;
      Revision   : access C_DWord) return C_Int
     with Import, Convention => Stdcall,
          External_Name => "GetSecurityDescriptorControl";

   function Convert_Descriptor_To_Text
     (Descriptor  : System.Address;
      Revision    : C_DWord;
      Information : C_DWord;
      Text        : access System.Address;
      Length      : access C_DWord) return C_Int
     with Import, Convention => Stdcall,
          External_Name => "ConvertSecurityDescriptorToStringSecurityDescriptorW";

   function Convert_Text_To_Descriptor
     (Text       : System.Address;
      Revision   : C_DWord;
      Descriptor : access System.Address;
      Size       : access C_DWord) return C_Int
     with Import, Convention => Stdcall,
          External_Name => "ConvertStringSecurityDescriptorToSecurityDescriptorW";

   function Equal_Sid (Left, Right : System.Address) return C_Int
     with Import, Convention => Stdcall, External_Name => "EqualSid";

   --  The rwx triplet Acl grants Sid, as File_Permission_Bits reads one; 0
   --  where there is no ACL to read or the host will not say.
   function Triplet_Of (Acl : System.Address; Sid : System.Address) return Natural is
      Trustee : aliased Trustee_Record;
      Rights  : aliased C_DWord := 0;
   begin
      if Sid = System.Null_Address or else Acl = System.Null_Address then
         return 0;
      end if;
      Build_Trustee_With_Sid (Trustee'Access, Sid);
      Trustee.Form := Trustee_Is_Sid;
      Trustee.Kind := Trustee_Is_Unknown;
      if Get_Effective_Rights_From_Acl (Acl, Trustee'Access, Rights'Access) /= Success then
         return 0;
      end if;
      return Rights_To_Triplet (Rights);
   end Triplet_Of;

   --  Triplet less its execute bit, unless execute means something here.
   function Shown (Triplet : Natural; Runnable : Boolean) return Natural is
     (if Runnable then Triplet else Triplet - Triplet mod 2);

   --  The mode Dacl gives the owner, the primary group and Everyone, as
   --  File_Permission_Bits reads it: execute only where Runnable (a program
   --  by its extension, or a folder).
   function Mode_Of
     (Dacl, Owner, Group, Everyone : System.Address;
      Runnable : Boolean) return Natural is
     (Shown (Triplet_Of (Dacl, Owner), Runnable) * 64
      + Shown (Triplet_Of (Dacl, Group), Runnable) * 8
      + Shown (Triplet_Of (Dacl, Everyone), Runnable));

   --  The bits of triplet Left that triplet Right lacks.
   function Without (Left, Right : Natural) return Natural is
      type Bit_List is array (1 .. 3) of Positive;
      Bits   : constant Bit_List := [4, 2, 1];
      Result : Natural := 0;
   begin
      for Bit of Bits loop
         if (Left / Bit) mod 2 = 1 and then (Right / Bit) mod 2 = 0 then
            Result := Result + Bit;
         end if;
      end loop;
      return Result;
   end Without;

   --  Just the rights a triplet's bits stand for, to deny: not the generic
   --  sets Triplet_To_Rights grants, whose READ_CONTROL and SYNCHRONIZE a
   --  deny would take away with them.
   function Rights_To_Deny (Triplet : Natural) return C_DWord is
     ((if (Triplet / 4) mod 2 = 1 then File_Read_Data else 0)
      or (if (Triplet / 2) mod 2 = 1 then File_Write_Data or File_Append_Data else 0)
      or (if Triplet mod 2 = 1 then File_Execute_Access else 0));

   --  The DACL a permission edit from Old_Mode to New_Mode leaves (see
   --  Set_Permissions in the spec): Dacl with the explicit ACEs of each of
   --  the owner, the group and Everyone whose bits change replaced
   --  (SetEntriesInAcl keeps every other ACE, the inherited ones too, in
   --  canonical order), then a deny for what the owner could still do past
   --  its new bits. Result is a LocalAlloc'd ACL for the caller to free, or
   --  null when no bit changes. False when the host would not build it.
   function Edited_Dacl
     (Dacl, Owner, Group, Everyone : System.Address;
      Old_Mode, New_Mode           : Natural;
      Runnable                     : Boolean;
      Result                       : out System.Address) return Boolean
   is
      type Sid_List is array (1 .. 3) of System.Address;
      type Shift_List is array (1 .. 3) of Positive;
      Sids     : constant Sid_List := [Owner, Group, Everyone];
      Shifts   : constant Shift_List := [64, 8, 1];
      Entries  : aliased Explicit_Access_Array;
      Count    : Natural := 0;
      Replaced : aliased System.Address := System.Null_Address;
      Denied   : aliased System.Address := System.Null_Address;
      Status   : C_DWord;
      Freed    : System.Address;
      pragma Unreferenced (Freed);
   begin
      Result := System.Null_Address;
      for Index in Sids'Range loop
         declare
            Old_Bits : constant Natural := (Old_Mode / Shifts (Index)) mod 8;
            New_Bits : constant Natural := Shown ((New_Mode / Shifts (Index)) mod 8, Runnable);
         begin
            --  An owner that is also the primary group is edited as the
            --  owner: the group's bits cannot differ from its own, and
            --  editing them apart would take the owner's ACE with them.
            if Old_Bits /= New_Bits
              and then Sids (Index) /= System.Null_Address
              and then (Index /= 2 or else Owner = System.Null_Address or else Equal_Sid (Group, Owner) = 0)
            then
               Count := Count + 1;
               Build_Trustee_With_Sid (Entries (Count).Trustee'Access, Sids (Index));
               Entries (Count).Permissions := Triplet_To_Rights (New_Bits);
               --  SET_ACCESS replaces the trustee's explicit allow and deny
               --  ACEs; with no bits left, REVOKE_ACCESS just removes them.
               Entries (Count).Mode := (if New_Bits = 0 then Revoke_Access else Set_Access);
               Entries (Count).Inheritance := No_Inheritance;
               Entries (Count).Trustee.Form := Trustee_Is_Sid;
               Entries (Count).Trustee.Kind := Trustee_Is_Unknown;
            end if;
         end;
      end loop;
      if Count = 0 then
         return True;
      end if;
      Status := Set_Entries_In_Acl (C_DWord (Count), Entries (1)'Address, Dacl, Replaced'Access);
      if Status /= Success or else Replaced = System.Null_Address then
         Hostkit.Windows_Errors.Set_Errno_From (Interfaces.Unsigned_32 (Status));
         return False;
      end if;
      declare
         Left : constant Natural :=
           Without (Shown (Triplet_Of (Replaced, Owner), Runnable), Shown ((New_Mode / 64) mod 8, Runnable));
      begin
         if Left = 0 or else Owner = System.Null_Address then
            Result := Replaced;
            return True;
         end if;
         Entries := [others => <>];
         Build_Trustee_With_Sid (Entries (1).Trustee'Access, Owner);
         Entries (1).Permissions := Rights_To_Deny (Left);
         Entries (1).Mode := Deny_Access;
         Entries (1).Inheritance := No_Inheritance;
         Entries (1).Trustee.Form := Trustee_Is_Sid;
         Entries (1).Trustee.Kind := Trustee_Is_Unknown;
         Status := Set_Entries_In_Acl (1, Entries (1)'Address, Replaced, Denied'Access);
         Freed := Local_Free (Replaced);
         if Status /= Success or else Denied = System.Null_Address then
            Hostkit.Windows_Errors.Set_Errno_From (Interfaces.Unsigned_32 (Status));
            return False;
         end if;
         Result := Denied;
         return True;
      end;
   end Edited_Dacl;

   --  Descriptor's DACL as SDDL, with whether it is protected ("P") and
   --  inherits automatically ("AI"): "D:AI(A;;FA;;;S-1-5-...)(A;ID;...)".
   --  "" when the host will not write it.
   function Dacl_Text (Descriptor : System.Address) return String is
      Text   : aliased System.Address := System.Null_Address;
      Length : aliased C_DWord := 0;
      Freed  : System.Address;
      pragma Unreferenced (Freed);
   begin
      if Descriptor = System.Null_Address then
         return "";
      elsif Convert_Descriptor_To_Text
              (Descriptor, Sddl_Revision, Dacl_Information, Text'Access, Length'Access) = 0
        or else Text = System.Null_Address
      then
         Hostkit.Errors.Set_Errno_From_Last_Error;
         return "";
      end if;
      declare
         Units : constant Wide_String (1 .. Natural (Length)) with Import, Address => Text;
         Last  : Natural := 0;
      begin
         --  The length may count the terminating NUL.
         while Last < Units'Last and then Units (Last + 1) /= Wide_Character'Val (0) loop
            Last := Last + 1;
         end loop;
         declare
            Result : constant String := Hostkit.Windows_Paths.To_UTF_8 (Units (1 .. Last));
         begin
            Freed := Local_Free (Text);
            return Result;
         end;
      end;
   end Dacl_Text;

   --  The DACL of the entry open as File, as Dacl_Text writes it.
   function Dacl_Text_Of (File : System.Address) return String is
      Owner, Group, Dacl, Sacl : aliased System.Address := System.Null_Address;
      Descriptor : aliased System.Address := System.Null_Address;
      Freed      : System.Address;
      pragma Unreferenced (Freed);
   begin
      if Get_Security_Info
           (File, Se_File_Object, Dacl_Information, Owner'Access, Group'Access, Dacl'Access, Sacl'Access,
            Descriptor'Access) /= Success
      then
         return "";
      end if;
      declare
         Result : constant String := Dacl_Text (Descriptor);
      begin
         Freed := Local_Free (Descriptor);
         return Result;
      end;
   end Dacl_Text_Of;

   --  Put the DACL Text describes (Dacl_Text) back on the entry open as
   --  File exactly: its ACEs, inherited ones as they were, and whether it
   --  is protected. The entry alone, as Set_Own_Dacl.
   function Set_Dacl_Text (File : System.Address; Text : String) return Boolean is
      Wide_Text  : aliased constant Wide_String := Hostkit.Windows_Paths.From_UTF_8 (Text) & Wide_Character'Val (0);
      Descriptor : aliased System.Address := System.Null_Address;
      Size       : aliased C_DWord := 0;
      Applied    : Boolean;
      Freed      : System.Address;
      pragma Unreferenced (Freed);
   begin
      if Convert_Text_To_Descriptor (Wide_Text'Address, Sddl_Revision, Descriptor'Access, Size'Access) = 0
        or else Descriptor = System.Null_Address
      then
         Hostkit.Errors.Set_Errno_From_Last_Error;
         return False;
      end if;
      Applied := Set_Kernel_Object_Security (File, Dacl_Information, Descriptor) /= 0;
      if not Applied then
         Hostkit.Errors.Set_Errno_From_Last_Error;
      end if;
      Freed := Local_Free (Descriptor);
      return Applied;
   exception
      when Ada.Strings.UTF_Encoding.Encoding_Error =>
         --  Not text Dacl_Text wrote.
         return False;
   end Set_Dacl_Text;

   function Set_Permissions
     (Path : String;
      Mode : Natural) return Boolean
   is
      C_Path : aliased Wide_String := Wide (Path);

      Owner      : aliased System.Address := System.Null_Address;
      Group      : aliased System.Address := System.Null_Address;
      Dacl       : aliased System.Address := System.Null_Address;
      Sacl       : aliased System.Address := System.Null_Address;
      Descriptor : aliased System.Address := System.Null_Address;
      New_Acl    : System.Address := System.Null_Address;
      Control    : aliased Interfaces.C.unsigned_short := 0;
      Revision   : aliased C_DWord := 0;
      Status     : C_DWord;

      Everyone      : aliased Sid_Buffer := [others => Interfaces.C.nul];
      Everyone_Size : aliased C_DWord := C_DWord (Sid_Buffer'Length);

      procedure Free_Allocations is
         Freed : System.Address;
         pragma Unreferenced (Freed);
      begin
         if New_Acl /= System.Null_Address then
            Freed := Local_Free (New_Acl);
            New_Acl := System.Null_Address;
         end if;
         if Descriptor /= System.Null_Address then
            Freed := Local_Free (Descriptor);
            Descriptor := System.Null_Address;
         end if;
      end Free_Allocations;
   begin
      if Mode > 8#7777# then
         return False;
      end if;
      Status :=
        Get_Named_Security_Info
          (C_Path'Address, Se_File_Object,
           Owner_Information or Group_Information or Dacl_Information,
           Owner'Access, Group'Access, Dacl'Access, Sacl'Access,
           Descriptor'Access);
      if Status /= Success then
         Hostkit.Windows_Errors.Set_Errno_From (Interfaces.Unsigned_32 (Status));
         return False;
      end if;
      if Create_Well_Known_Sid
           (Win_World_Sid, System.Null_Address, Everyone (1)'Address, Everyone_Size'Access) = 0
        or else Get_Security_Descriptor_Control (Descriptor, Control'Access, Revision'Access) = 0
      then
         Hostkit.Errors.Set_Errno_From_Last_Error;
         Free_Allocations;
         return False;
      end if;
      declare
         Runnable : constant Boolean :=
           Runs_On_Windows (Path) or else Hostkit.Fs.Kind_Of (Path) = Hostkit.Fs.Directory_Entry;
         Applied  : Boolean :=
           Edited_Dacl
             (Dacl, Owner, Group, Everyone (1)'Address,
              Mode_Of (Dacl, Owner, Group, Everyone (1)'Address, Runnable), Mode, Runnable, New_Acl);
      begin
         if Applied and then New_Acl /= System.Null_Address then
            Applied := Set_Own_Dacl (C_Path'Address, System.Null_Address, New_Acl, Control);
         end if;
         Free_Allocations;
         return Applied;
      end;
   exception
      when others =>
         Free_Allocations;
         return False;
   end Set_Permissions;

   function Set_Exact_Permissions
     (Path : String;
      Mode : Natural) return Boolean
   is
      C_Path : aliased Wide_String := Wide (Path);

      Owner      : aliased System.Address := System.Null_Address;
      Group      : aliased System.Address := System.Null_Address;
      Dacl       : aliased System.Address := System.Null_Address;
      Sacl       : aliased System.Address := System.Null_Address;
      Descriptor : aliased System.Address := System.Null_Address;

      Entries  : aliased Explicit_Access_Array;
      New_Acl  : aliased System.Address := System.Null_Address;
      Status   : C_DWord;

      Everyone      : aliased Sid_Buffer := [others => Interfaces.C.nul];
      Everyone_Size : aliased C_DWord := C_DWord (Sid_Buffer'Length);

      --  Get_Named_Security_Info hands back a LocalAlloc'd descriptor the caller
      --  owns; every exit after it succeeds must release it, not just the happy
      --  path.
      procedure Free_Allocations is
         Freed : System.Address;
         pragma Unreferenced (Freed);
      begin
         if New_Acl /= System.Null_Address then
            Freed := Local_Free (New_Acl);
            New_Acl := System.Null_Address;
         end if;
         if Descriptor /= System.Null_Address then
            Freed := Local_Free (Descriptor);
            Descriptor := System.Null_Address;
         end if;
      end Free_Allocations;
   begin
      Status :=
        Get_Named_Security_Info
          (C_Path'Address, Se_File_Object,
           Owner_Information or Group_Information or Dacl_Information,
           Owner'Access, Group'Access, Dacl'Access, Sacl'Access,
           Descriptor'Access);

      if Status /= Success then
         Hostkit.Windows_Errors.Set_Errno_From (Interfaces.Unsigned_32 (Status));
         return False;
      end if;

      if Create_Well_Known_Sid
           (Win_World_Sid, System.Null_Address,
            Everyone (1)'Address, Everyone_Size'Access) = 0
      then
         Free_Allocations;
         return False;
      end if;

      --  A fresh DACL granting the owner, the primary group and Everyone exactly
      --  the rights the three POSIX triplets ask for.
      Build_Trustee_With_Sid (Entries (1).Trustee'Access, Owner);
      Entries (1).Permissions := Triplet_To_Rights ((Mode / 64) mod 8);
      Entries (1).Mode := Grant_Access;
      Entries (1).Inheritance := No_Inheritance;
      Entries (1).Trustee.Form := Trustee_Is_Sid;
      Entries (1).Trustee.Kind := Trustee_Is_Unknown;

      Build_Trustee_With_Sid (Entries (2).Trustee'Access, Group);
      Entries (2).Permissions := Triplet_To_Rights ((Mode / 8) mod 8);
      Entries (2).Mode := Grant_Access;
      Entries (2).Inheritance := No_Inheritance;
      Entries (2).Trustee.Form := Trustee_Is_Sid;
      Entries (2).Trustee.Kind := Trustee_Is_Unknown;

      Build_Trustee_With_Sid (Entries (3).Trustee'Access, Everyone (1)'Address);
      Entries (3).Permissions := Triplet_To_Rights (Mode mod 8);
      Entries (3).Mode := Grant_Access;
      Entries (3).Inheritance := No_Inheritance;
      Entries (3).Trustee.Form := Trustee_Is_Sid;
      Entries (3).Trustee.Kind := Trustee_Is_Unknown;

      Status :=
        Set_Entries_In_Acl
          (3, Entries (1)'Address, System.Null_Address, New_Acl'Access);

      if Status /= Success or else New_Acl = System.Null_Address then
         Free_Allocations;
         return False;
      end if;

      declare
         Applied : constant Boolean :=
           Set_Own_Dacl (C_Path'Address, System.Null_Address, New_Acl);
      begin
         Free_Allocations;
         return Applied;
      end;

   exception
      when others =>
         Free_Allocations;
         return False;
   end Set_Exact_Permissions;

   --  The header every ACL starts with, and every ACE.
   type Acl_Header is record
      Revision  : Interfaces.C.unsigned_char;
      Padding_1 : Interfaces.C.unsigned_char;
      Size      : Interfaces.C.unsigned_short;
      Count     : Interfaces.C.unsigned_short;
      Padding_2 : Interfaces.C.unsigned_short;
   end record with Convention => C;
   type Ace_Header is record
      Kind  : Interfaces.C.unsigned_char;
      Flags : Interfaces.C.unsigned_char;
      Size  : Interfaces.C.unsigned_short;
   end record with Convention => C;

   function Get_Ace
     (Acl : System.Address; Index : C_DWord; Ace : access System.Address) return C_Int
     with Import, Convention => Stdcall, External_Name => "GetAce";
   function Initialize_Acl
     (Acl : System.Address; Size : C_DWord; Revision : C_DWord) return C_Int
     with Import, Convention => Stdcall, External_Name => "InitializeAcl";
   function Add_Ace
     (Acl : System.Address; Revision : C_DWord; Start : C_DWord;
      Aces : System.Address; Size : C_DWord) return C_Int
     with Import, Convention => Stdcall, External_Name => "AddAce";

   function Inherit_From_Parent (Path : String) return Boolean is
      Inherited_Ace : constant Interfaces.C.unsigned_char := 16#10#;
      --  UNPROTECTED_DACL_SECURITY_INFORMATION: inherit from the parent.
      Unprotected_Dacl_Information : constant C_DWord := 16#2000_0000#;
      Append_At_End : constant C_DWord := 16#FFFF_FFFF#;
      Acl_Header_Size : constant := 8;

      C_Path     : aliased Wide_String := Wide (Path);
      Owner      : aliased System.Address := System.Null_Address;
      Group      : aliased System.Address := System.Null_Address;
      Dacl       : aliased System.Address := System.Null_Address;
      Sacl       : aliased System.Address := System.Null_Address;
      Descriptor : aliased System.Address := System.Null_Address;
      Status     : C_DWord;

      procedure Free_Descriptor is
         Freed : System.Address;
         pragma Unreferenced (Freed);
      begin
         if Descriptor /= System.Null_Address then
            Freed := Local_Free (Descriptor);
            Descriptor := System.Null_Address;
         end if;
      end Free_Descriptor;

      --  Whether ACE Index of Dacl was set on Path itself; its address and
      --  size when so.
      function Explicit_Ace
        (Index : Natural; Ace : out System.Address; Size : out Natural) return Boolean
      is
         Found : aliased System.Address := System.Null_Address;
      begin
         Ace := System.Null_Address;
         Size := 0;
         if Get_Ace (Dacl, C_DWord (Index), Found'Access) = 0 then
            raise Program_Error;
         end if;
         declare
            Header : constant Ace_Header with Import, Address => Found;
         begin
            Ace := Found;
            Size := Natural (Header.Size);
            return (Header.Flags and Inherited_Ace) = 0;
         end;
      end Explicit_Ace;
   begin
      --  The security calls follow a link: its target is not what moved.
      if Hostkit.Fs.Is_Link (Path) then
         return True;
      end if;
      Status :=
        Get_Named_Security_Info
          (C_Path'Address, Se_File_Object, Dacl_Information,
           Owner'Access, Group'Access, Dacl'Access, Sacl'Access, Descriptor'Access);
      if Status /= Success then
         Hostkit.Windows_Errors.Set_Errno_From (Interfaces.Unsigned_32 (Status));
         return False;
      end if;
      if Dacl = System.Null_Address then
         --  No ACL: a volume that keeps none, or an entry open to all.
         Free_Descriptor;
         return True;
      end if;
      declare
         Header : constant Acl_Header with Import, Address => Dacl;
         Ace    : System.Address;
         Size   : Natural;
         Needed : Natural := Acl_Header_Size;
      begin
         for Index in 0 .. Natural (Header.Count) - 1 loop
            if Explicit_Ace (Index, Ace, Size) then
               Needed := Needed + Size;
            end if;
         end loop;
         declare
            --  An ACL is DWORD-aligned.
            Kept : aliased array (1 .. (Needed + 3) / 4) of Interfaces.Unsigned_32 := [others => 0];
         begin
            if Initialize_Acl (Kept'Address, C_DWord (Needed), C_DWord (Header.Revision)) = 0 then
               Hostkit.Errors.Set_Errno_From_Last_Error;
               Free_Descriptor;
               return False;
            end if;
            for Index in 0 .. Natural (Header.Count) - 1 loop
               if Explicit_Ace (Index, Ace, Size)
                 and then Add_Ace (Kept'Address, C_DWord (Header.Revision), Append_At_End, Ace, C_DWord (Size)) = 0
               then
                  Hostkit.Errors.Set_Errno_From_Last_Error;
                  Free_Descriptor;
                  return False;
               end if;
            end loop;
            --  The explicit ACEs, unprotected: Windows adds what the parent
            --  hands down and carries it on to the children.
            Status :=
              Set_Named_Security_Info
                (C_Path'Address, Se_File_Object, Dacl_Information or Unprotected_Dacl_Information,
                 System.Null_Address, System.Null_Address, Kept'Address, System.Null_Address);
         end;
      end;
      Free_Descriptor;
      Hostkit.Windows_Errors.Set_Errno_From (Interfaces.Unsigned_32 (Status));
      return Status = Success;
   exception
      when others =>
         Free_Descriptor;
         return False;
   end Inherit_From_Parent;

   function Set_File_Times
     (Path          : String;
      Access_Time   : Long_Long_Integer;
      Modified_Time : Long_Long_Integer)
      return Boolean
   is
      function To_Filetime (Seconds : Long_Long_Integer) return Filetime is
         Ticks : constant C_U64 := C_U64 (Seconds + 11_644_473_600) * 10_000_000;
      begin
         return
           (Low  => C_DWord (Ticks mod 2 ** 32),
            High => C_DWord (Ticks / 2 ** 32));
      end To_Filetime;

      C_Path : aliased Wide_String := Wide (Path);
      File   : System.Address := System.Null_Address;
      Access_Filetime   : aliased Filetime := To_Filetime (Access_Time);
      Modified_Filetime : aliased Filetime := To_Filetime (Modified_Time);
      Result : C_Int;
   begin
      File :=
        Create_File_Wide
          (C_Path'Address,
           File_Read_Attributes or File_Write_Attributes,
           File_Share_Read or File_Share_Write or File_Share_Delete,
           System.Null_Address,
           Open_Existing,
           File_Attribute_Normal or File_Flag_Backup_Semantics,
           System.Null_Address);

      if File = System.Null_Address or else File = Invalid_Handle_Value then
         Hostkit.Errors.Set_Errno_From_Last_Error;
         return False;
      end if;

      Result :=
        Set_File_Time
          (File,
           System.Null_Address,
           Access_Filetime'Access,
           Modified_Filetime'Access);
      if Result = 0 then
         Hostkit.Errors.Set_Errno_From_Last_Error;
      end if;
      declare
         Ignored : constant C_Int := Close_Handle (File);
      begin
         null;
      end;
      return Result /= 0;

   exception
      when others =>
         if File /= System.Null_Address and then File /= Invalid_Handle_Value then
            declare
               Ignored : constant C_Int := Close_Handle (File);
            begin
               null;
            end;
         end if;
         return False;
   end Set_File_Times;

   function Permissions_Supported return Boolean is
   begin
      return True;
   end Permissions_Supported;

   procedure File_Ownership
     (Path      : String;
      User_Id   : out Account_Id;
      Group_Id  : out Account_Id;
      Available : out Boolean)
   is
      C_Path : aliased Wide_String := Wide (Path);

      --  The ids minted for SIDs are Natural (Identity_Of); they fit.
      User_Number  : Natural;
      Group_Number : Natural;

      Owner      : aliased System.Address := System.Null_Address;
      Group      : aliased System.Address := System.Null_Address;
      Dacl       : aliased System.Address := System.Null_Address;
      Sacl       : aliased System.Address := System.Null_Address;
      Descriptor : aliased System.Address := System.Null_Address;

      Status : C_DWord;

      procedure Free_Descriptor is
         Freed : System.Address;
         pragma Unreferenced (Freed);
      begin
         if Descriptor /= System.Null_Address then
            Freed := Local_Free (Descriptor);
            Descriptor := System.Null_Address;
         end if;
      end Free_Descriptor;
   begin
      User_Id := 0;
      Group_Id := 0;
      Available := False;

      Status :=
        Get_Named_Security_Info
          (C_Path'Address, Se_File_Object,
           Owner_Information or Group_Information,
           Owner'Access, Group'Access, Dacl'Access, Sacl'Access,
           Descriptor'Access);

      if Status /= Success then
         Free_Descriptor;
         return;
      end if;

      User_Number := Identity_Of (Owner);
      Group_Number := Identity_Of (Group);
      Remember (Owner, User_Number);
      Remember (Group, Group_Number);
      User_Id := Account_Id (User_Number);
      Group_Id := Account_Id (Group_Number);
      Available := True;

      Free_Descriptor;

   exception
      when others =>
         Free_Descriptor;
         User_Id := 0;
         Group_Id := 0;
         Available := False;
   end File_Ownership;

   procedure File_Mode_And_Ownership
     (Path                : String;
      Mode_Bits           : out Natural;
      Mode_Available      : out Boolean;
      User_Id             : out Account_Id;
      Group_Id            : out Account_Id;
      Ownership_Available : out Boolean) is
   begin
      Mode_Bits := File_Permission_Bits (Path, Mode_Available);
      File_Ownership (Path, User_Id, Group_Id, Ownership_Available);
   end File_Mode_And_Ownership;

   function Wide (Value : String) return Wide_String renames Hostkit.Windows_Paths.Native;

   function Open_Entry (Path : String; Access_Mode : C_DWord) return System.Address is
      Wide_Path : aliased Wide_String := Wide (Path);
   begin
      return Create_File_Wide
        (Wide_Path'Address, Access_Mode,
         File_Share_Read or File_Share_Write or File_Share_Delete,
         System.Null_Address, Open_Existing,
         File_Flag_Backup_Semantics or File_Flag_Open_Reparse_Point,
         System.Null_Address);
   exception
      when others =>
         return Invalid_Handle_Value;
   end Open_Entry;

   procedure Close_Entry (File : in out System.Address) is
   begin
      if File /= Invalid_Handle_Value and then File /= System.Null_Address then
         declare
            Ignored : constant C_Int := Close_Handle (File);
         begin
            null;
         end;
         File := Invalid_Handle_Value;
      end if;
   end Close_Entry;

   function Identifier_Part (Value : Identifier_Array; First : Natural) return Identity_Field is
      Result : Identity_Field := 0;
   begin
      for Offset in 0 .. 7 loop
         Result := Result or Interfaces.Shift_Left (Identity_Field (Value (First + Offset)), Offset * 8);
      end loop;
      return Result;
   end Identifier_Part;

   function Valid_Identifier (Value : Identifier_Array) return Boolean is
      Nonzero     : Boolean := False;
      Not_All_Ones : Boolean := False;
   begin
      for Byte of Value loop
         Nonzero := Nonzero or else Byte /= 0;
         Not_All_Ones := Not_All_Ones or else Byte /= Interfaces.Unsigned_8'Last;
      end loop;
      return Nonzero and Not_All_Ones;
   end Valid_Identifier;

   function Entry_Identity_Of (Path : String) return Entry_Identity is
      File   : System.Address := Open_Entry (Path, 0);
      Legacy : aliased By_Handle_File_Information;
      Id     : aliased File_Id_Info;
      Number : Identity_Field;
   begin
      if File = Invalid_Handle_Value or else Get_File_Information (File, Legacy'Access) = 0 then
         Close_Entry (File);
         return (others => <>);
      end if;
      if Get_File_Information_Ex
        (File, File_Id_Info_Class, Id'Address, C_DWord (File_Id_Info'Size / 8)) /= 0
        and then Valid_Identifier (Id.Identifier)
      then
         declare
            Result : constant Entry_Identity :=
              (Available       => True,
               Volume          => Id.Volume_Serial,
               File_Number     => Identifier_Part (Id.Identifier, 0),
               Generation_High => Identifier_Part (Id.Identifier, 8),
               Generation_Low  => 0);
         begin
            Close_Entry (File);
            return Result;
         end;
      end if;
      Number := Interfaces.Shift_Left (Identity_Field (Legacy.File_Index_High), 32)
        or Identity_Field (Legacy.File_Index_Low);
      --  Off NTFS (FAT, exFAT) the index names the directory entry: stable
      --  while the entry stays put, as Linux's vfat inode numbers are, and
      --  enough for the checks a copy makes. Refusing it failed every copy
      --  onto a USB stick.
      if Number = 0 or else Number = Identity_Field'Last then
         Close_Entry (File);
         return (others => <>);
      end if;
      declare
         Result : constant Entry_Identity :=
           (Available       => True,
            Volume          => Identity_Field (Legacy.Volume_Serial),
            File_Number     => Number,
            Generation_High => 0,
            Generation_Low  => 0);
      begin
         Close_Entry (File);
         return Result;
      end;
   exception
      when others =>
         Close_Entry (File);
         return (others => <>);
   end Entry_Identity_Of;

   function Update_Entry_Metadata
     (Path           : String;
      Expected       : Entry_Identity;
      Check_Expected : Boolean;
      Kind           : Metadata_Update_Kind;
      Value          : Identity_Field;
      Group          : Identity_Field;
      Max_Previous   : Identity_Field;
      Owner_Name     : String := "";
      Group_Name     : String := "";
      Access_Text    : String := "") return Metadata_Update_Result
   is
      function Identity_From_Handle
        (File : System.Address;
         Info : access By_Handle_File_Information) return Entry_Identity
      is
         Id     : aliased File_Id_Info;
         Number : Identity_Field;
      begin
         if Get_File_Information (File, Info) = 0 then
            return (others => <>);
         end if;
         if Get_File_Information_Ex
           (File, File_Id_Info_Class, Id'Address,
            C_DWord (File_Id_Info'Size / 8)) /= 0
           and then Valid_Identifier (Id.Identifier)
         then
            return
              (Available       => True,
               Volume          => Id.Volume_Serial,
               File_Number     => Identifier_Part (Id.Identifier, 0),
               Generation_High => Identifier_Part (Id.Identifier, 8),
               Generation_Low  => 0);
         end if;
         Number := Interfaces.Shift_Left
           (Identity_Field (Info.File_Index_High), 32)
           or Identity_Field (Info.File_Index_Low);
         --  As Entry_Identity_Of: off NTFS the index still names the entry.
         if Number = 0 or else Number = Identity_Field'Last then
            return (others => <>);
         end if;
         return
           (Available       => True,
            Volume          => Identity_Field (Info.Volume_Serial),
            File_Number     => Number,
            Generation_High => 0,
            Generation_Low  => 0);
      end Identity_From_Handle;

      function Resolve_Account
        (Name     : String;
         Expected_Id : Identity_Field;
         Sid      : out Sid_Buffer) return Boolean
      is
         Wide_Name   : aliased Wide_String := Wide (Name);
         Sid_Size    : aliased C_DWord := 0;
         Domain_Size : aliased C_DWord := 0;
         Use_Kind    : aliased C_Int := 0;
         Ignored     : C_Int;
      begin
         Sid := [others => Interfaces.C.nul];
         if Name = "" or else Expected_Id > Identity_Field (Natural'Last) then
            return False;
         end if;
         Ignored := Lookup_Account_Name_Wide
           (System.Null_Address, Wide_Name'Address,
            System.Null_Address, Sid_Size'Access,
            System.Null_Address, Domain_Size'Access, Use_Kind'Access);
         if Sid_Size = 0 or else Natural (Sid_Size) > Sid_Buffer'Length then
            return False;
         end if;
         declare
            Domain : aliased Wide_String
              (1 .. Natural'Max (1, Natural (Domain_Size))) :=
                [others => Wide_Character'Val (0)];
            Actual_Sid_Size : aliased C_DWord := Sid_Size;
            Actual_Domain_Size : aliased C_DWord := Domain_Size;
         begin
            if Lookup_Account_Name_Wide
              (System.Null_Address, Wide_Name'Address, Sid (1)'Address,
               Actual_Sid_Size'Access, Domain'Address,
               Actual_Domain_Size'Access, Use_Kind'Access) = 0
            then
               return False;
            end if;
         end;
         return Identity_Field (Identity_Of (Sid (1)'Address)) = Expected_Id;
      exception
         when others =>
            return False;
      end Resolve_Account;

      Access_Mode : constant C_DWord := Read_Control or
        (if Kind = Update_Ownership then Write_Owner else Write_Dac);
      File       : System.Address := Open_Entry (Path, Access_Mode);
      Info       : aliased By_Handle_File_Information;
      Answer     : Metadata_Update_Result;
      Owner      : aliased System.Address := System.Null_Address;
      Primary_Group : aliased System.Address := System.Null_Address;
      Dacl       : aliased System.Address := System.Null_Address;
      Sacl       : aliased System.Address := System.Null_Address;
      Descriptor : aliased System.Address := System.Null_Address;
      New_Acl    : aliased System.Address := System.Null_Address;

      procedure Free_Local (Item : in out System.Address) is
         Freed : System.Address;
         pragma Unreferenced (Freed);
      begin
         if Item /= System.Null_Address then
            Freed := Local_Free (Item);
            Item := System.Null_Address;
         end if;
      end Free_Local;

      procedure Clean is
      begin
         Free_Local (New_Acl);
         Free_Local (Descriptor);
         Close_Entry (File);
      end Clean;
   begin
      if File = Invalid_Handle_Value then
         return Answer;
      end if;
      Answer.Identity := Identity_From_Handle (File, Info'Access);
      if not Answer.Identity.Available
        or else (Info.Attributes and File_Attribute_Reparse_Point) /= 0
        or else (Check_Expected and then Answer.Identity /= Expected)
      then
         Clean;
         return Answer;
      end if;
      if Get_Security_Info
        (File, Se_File_Object,
         Owner_Information or Group_Information or Dacl_Information,
         Owner'Access, Primary_Group'Access, Dacl'Access, Sacl'Access,
         Descriptor'Access) /= Success
      then
         Clean;
         return Answer;
      end if;

      if Kind = Update_Ownership then
         Answer.Previous := Identity_Field (Identity_Of (Owner));
         Answer.Previous_Group := Identity_Field (Identity_Of (Primary_Group));
         Remember (Owner, Natural (Answer.Previous));
         Remember (Primary_Group, Natural (Answer.Previous_Group));
         if Answer.Previous <= Max_Previous
           and then Answer.Previous_Group <= Max_Previous
           and then Value <= Identity_Field (Natural'Last)
           and then Group <= Identity_Field (Natural'Last)
         then
            declare
               Owner_Sid : aliased Sid_Buffer := [others => Interfaces.C.nul];
               Group_Sid : aliased Sid_Buffer := [others => Interfaces.C.nul];
               Borrow_Owner : constant Boolean := Answer.Previous = Value;
               Borrow_Group : constant Boolean := Answer.Previous_Group = Group;
               Have_Owner : constant Boolean := Borrow_Owner or else
                 Resolve_Account (Owner_Name, Value, Owner_Sid);
               Have_Group : constant Boolean := Borrow_Group or else
                 Resolve_Account (Group_Name, Group, Group_Sid);
               New_Owner : constant System.Address :=
                 (if Borrow_Owner then Owner else Owner_Sid (1)'Address);
               New_Group : constant System.Address :=
                 (if Borrow_Group then Primary_Group else Group_Sid (1)'Address);
            begin
               if Have_Owner and then Have_Group then
                  declare
                     Status : constant C_DWord := Set_Security_Info
                       (File, Se_File_Object,
                        Owner_Information or Group_Information,
                        New_Owner, New_Group, System.Null_Address,
                        System.Null_Address);
                  begin
                     Hostkit.Windows_Errors.Set_Errno_From (Interfaces.Unsigned_32 (Status));
                     Answer.Success := Status = Success;
                  end;
               end if;
            end;
         end if;
      else
         --  The edit Set_Permissions makes, on the held entry; or, given an
         --  access record an earlier update reported, that record exactly.
         declare
            Everyone      : aliased Sid_Buffer := [others => Interfaces.C.nul];
            Everyone_Size : aliased C_DWord := C_DWord (Sid_Buffer'Length);
            Control       : aliased Interfaces.C.unsigned_short := 0;
            Revision      : aliased C_DWord := 0;
            Runnable      : constant Boolean :=
              Runs_On_Windows (Path) or else (Info.Attributes and File_Attribute_Directory) /= 0;
            Old_Mode      : Natural;
         begin
            if Create_Well_Known_Sid
                 (Win_World_Sid, System.Null_Address, Everyone (1)'Address, Everyone_Size'Access) /= 0
              and then Get_Security_Descriptor_Control (Descriptor, Control'Access, Revision'Access) /= 0
            then
               Old_Mode := Mode_Of (Dacl, Owner, Primary_Group, Everyone (1)'Address, Runnable);
               Answer.Previous := Identity_Field (Old_Mode);
               Answer.Previous_Access := To_Unbounded_String (Dacl_Text (Descriptor));
               if Access_Text /= "" then
                  Answer.Success := Set_Dacl_Text (File, Access_Text);
               elsif Value <= 8#7777#
                 and then Edited_Dacl
                   (Dacl, Owner, Primary_Group, Everyone (1)'Address, Old_Mode, Natural (Value), Runnable, New_Acl)
               then
                  Answer.Success :=
                    New_Acl = System.Null_Address or else Set_Own_Dacl (System.Null_Address, File, New_Acl, Control);
               end if;
               if Answer.Success then
                  Answer.Applied_Access := To_Unbounded_String (Dacl_Text_Of (File));
               end if;
            else
               Hostkit.Errors.Set_Errno_From_Last_Error;
            end if;
         end;
      end if;
      Clean;
      return Answer;
   exception
      when others =>
         Clean;
         return (others => <>);
   end Update_Entry_Metadata;

   function Entry_Revision_Of (Path : String) return Entry_Revision is
      File   : System.Address := Open_Entry (Path, File_Read_Attributes);
      Legacy : aliased By_Handle_File_Information;
      Basic  : aliased File_Basic_Info;
   begin
      if File = Invalid_Handle_Value
        or else Get_File_Information (File, Legacy'Access) = 0
        or else Get_File_Information_Ex
          (File, File_Basic_Info_Class, Basic'Address, C_DWord (File_Basic_Info'Size / 8)) = 0
      then
         Close_Entry (File);
         return (others => <>);
      end if;
      declare
         Result : constant Entry_Revision :=
           (Available            => True,
            Modified_Seconds     => Identity_Field (Basic.Modified_Time),
            Modified_Nanoseconds => 0,
            Changed_Seconds      => Identity_Field (Basic.Change_Time),
            Changed_Nanoseconds  => 0,
            Size                 => Interfaces.Shift_Left (Identity_Field (Legacy.Size_High), 32)
              or Identity_Field (Legacy.Size_Low),
            Mode                 => Identity_Field (Legacy.Attributes),
            User_Id              => 0,
            Group_Id             => 0);
      begin
         Close_Entry (File);
         return Result;
      end;
   exception
      when others =>
         Close_Entry (File);
         return (others => <>);
   end Entry_Revision_Of;

   --  The same words as POSIX gives: modification and change times as
   --  seconds since 1970 and nanoseconds, size, file number. FILE_BASIC_INFO
   --  keeps both times in 100 ns ticks since 1601; NTFS moves ChangeTime on
   --  every write and every change of the entry, and nothing sets it back.
   --  The link is followed, as stat follows it.
   function Change_Stamp
     (Path      : String;
      Available : out Boolean)
      return String
   is
      use type Interfaces.Integer_64;
      Wide_Path : aliased Wide_String := Wide (Path);
      File      : System.Address :=
        Create_File_Wide
          (Wide_Path'Address, File_Read_Attributes,
           File_Share_Read or File_Share_Write or File_Share_Delete,
           System.Null_Address, Open_Existing, File_Flag_Backup_Semantics,
           System.Null_Address);
      Legacy    : aliased By_Handle_File_Information;
      Basic     : aliased File_Basic_Info;

      Ticks_A_Second : constant := 10_000_000;
      Epoch_Seconds  : constant := 11_644_473_600;

      function Time_Words (Ticks : Interfaces.Integer_64) return String is
        (Interfaces.Integer_64'Image (Ticks / Ticks_A_Second - Epoch_Seconds) & "."
         & Interfaces.Integer_64'Image ((Ticks mod Ticks_A_Second) * 100));
   begin
      Available := False;
      if File = Invalid_Handle_Value
        or else Get_File_Information (File, Legacy'Access) = 0
        or else Get_File_Information_Ex
          (File, File_Basic_Info_Class, Basic'Address, C_DWord (File_Basic_Info'Size / 8)) = 0
      then
         Close_Entry (File);
         return "";
      end if;
      Close_Entry (File);
      Available := True;
      return Time_Words (Basic.Modified_Time) & Time_Words (Basic.Change_Time)
        & Interfaces.Unsigned_64'Image
            (Interfaces.Shift_Left (Interfaces.Unsigned_64 (Legacy.Size_High), 32)
             or Interfaces.Unsigned_64 (Legacy.Size_Low))
        & Interfaces.Unsigned_64'Image
            (Interfaces.Shift_Left (Interfaces.Unsigned_64 (Legacy.File_Index_High), 32)
             or Interfaces.Unsigned_64 (Legacy.File_Index_Low));
   exception
      when others =>
         Close_Entry (File);
         Available := False;
         return "";
   end Change_Stamp;

   function Same_File (Left : String; Right : String) return Boolean is
      --  Windows filesystems are case-insensitive, so two paths that normalise
      --  to the same absolute string ignoring case name the same file. Made
      --  absolute as text: GNAT's Full_Name refuses a path past 260
      --  characters.
      function Normalized (Path : String) return String is
        (Ada.Characters.Handling.To_Lower
           (Hostkit.Path_Text.Absolute (Path, Hostkit.Fs.Current_Directory)));

      --  The volume and file index of what Path names, through any link, as
      --  stat's device and inode are elsewhere: they tell two hard links to
      --  one file apart from two files.
      function Identify (Path : String; Info : access By_Handle_File_Information) return Boolean is
         Wide_Path : aliased Wide_String := Wide (Path);
         File      : System.Address :=
           Create_File_Wide
             (Wide_Path'Address, 0,
              File_Share_Read or File_Share_Write or File_Share_Delete,
              System.Null_Address, Open_Existing, File_Flag_Backup_Semantics,
              System.Null_Address);
         Found     : Boolean;
      begin
         if File = Invalid_Handle_Value then
            return False;
         end if;
         Found := Get_File_Information (File, Info) /= 0;
         Close_Entry (File);
         return Found;
      end Identify;

      Left_Info  : aliased By_Handle_File_Information;
      Right_Info : aliased By_Handle_File_Information;
   begin
      if Identify (Left, Left_Info'Access) and then Identify (Right, Right_Info'Access) then
         return Left_Info.Volume_Serial = Right_Info.Volume_Serial
           and then Left_Info.File_Index_High = Right_Info.File_Index_High
           and then Left_Info.File_Index_Low = Right_Info.File_Index_Low;
      end if;

      return Hostkit.Fs.Kind_Of (Left) /= Hostkit.Fs.Missing_Entry
        and then Hostkit.Fs.Kind_Of (Right) /= Hostkit.Fs.Missing_Entry
        and then Normalized (Left) = Normalized (Right);
   exception
      when others =>
         return False;
   end Same_File;

   function Device_Id
     (Path      : String;
      Available : out Boolean)
      return Long_Long_Integer
   is
      --  Absolute as text, GNAT's Full_Name refusing a path past 260
      --  characters, and in the form a caller writes rather than the long
      --  one, so a path given either way hashes alike.
      Absolute : constant String := Hostkit.Path_Text.Absolute (Path, Hostkit.Fs.Current_Directory);
      Plain    : constant String :=
        (if Absolute'Length >= 8 and then Absolute (Absolute'First .. Absolute'First + 7) = "\\?\UNC\"
         then "\\" & Absolute (Absolute'First + 8 .. Absolute'Last)
         elsif Absolute'Length >= 4 and then Absolute (Absolute'First .. Absolute'First + 3) = "\\?\"
         then Absolute (Absolute'First + 4 .. Absolute'Last)
         else Absolute);
      Full     : constant String := Ada.Characters.Handling.To_Lower (Plain);
      Last : Natural := Full'First - 1;
      Hash : C_U64 := 14_695_981_039_346_656;
   begin
      Available := Hostkit.Fs.Kind_Of (Path) /= Hostkit.Fs.Missing_Entry;
      if not Available then
         return 0;
      end if;

      if Full'Length >= 3
        and then Full (Full'First + 1) = ':'
        and then Full (Full'First + 2) in '\' | '/'
      then
         Last := Full'First + 1;
      elsif Full'Length >= 5
        and then Full (Full'First) in '\' | '/'
        and then Full (Full'First + 1) in '\' | '/'
      then
         Last := Full'First + 1;
         for I in Full'First + 2 .. Full'Last loop
            Last := I;
            exit when Full (I) in '\' | '/';
         end loop;
         if Last < Full'Last then
            for I in Last + 1 .. Full'Last loop
               Last := I;
               exit when Full (I) in '\' | '/';
            end loop;
         end if;
      else
         Last := Full'Last;
      end if;

      for I in Full'First .. Last loop
         Hash := (Hash xor C_U64 (Character'Pos (Full (I)))) * 1_099_511_628_211;
      end loop;
      return Long_Long_Integer (Hash mod C_U64 (Long_Long_Integer'Last));
   exception
      when others =>
         Available := False;
         return 0;
   end Device_Id;

   function Lookup_Identity
     (Name  : String;
      Found : out Boolean) return Natural;

   function Lookup_Identity
     (Name  : String;
      Found : out Boolean) return Natural
   is
      Wide_Name   : aliased Wide_String := Wide (Name);
      Sid         : aliased Sid_Buffer := [others => Interfaces.C.nul];
      Sid_Size    : aliased C_DWord := 0;
      Domain_Size : aliased C_DWord := 0;
      Use_Kind    : aliased C_Int := 0;
      Ignored     : C_Int;
      Id          : Natural;
   begin
      Found := False;
      Ignored := Lookup_Account_Name_Wide
        (System.Null_Address, Wide_Name'Address,
         System.Null_Address, Sid_Size'Access,
         System.Null_Address, Domain_Size'Access, Use_Kind'Access);
      if Sid_Size = 0 or else Natural (Sid_Size) > Sid_Buffer'Length then
         return 0;
      end if;
      declare
         Domain : aliased Wide_String
           (1 .. Natural'Max (1, Natural (Domain_Size))) :=
             [others => Wide_Character'Val (0)];
         Actual_Sid_Size : aliased C_DWord := Sid_Size;
         Actual_Domain_Size : aliased C_DWord := Domain_Size;
      begin
         if Lookup_Account_Name_Wide
           (System.Null_Address, Wide_Name'Address, Sid (1)'Address,
            Actual_Sid_Size'Access, Domain'Address,
            Actual_Domain_Size'Access, Use_Kind'Access) = 0
         then
            return 0;
         end if;
      end;
      Id := Identity_Of (Sid (1)'Address);
      Remember (Sid (1)'Address, Id);
      Found := Id /= 0;
      return Id;

   exception
      when others =>
         Found := False;
         return 0;
   end Lookup_Identity;

   function User_Id_For_Name
     (Name  : String;
      Found : out Boolean) return Account_Id is
   begin
      return Account_Id (Lookup_Identity (Name, Found));
   end User_Id_For_Name;

   function Group_Id_For_Name
     (Name  : String;
      Found : out Boolean) return Account_Id is
   begin
      return Account_Id (Lookup_Identity (Name, Found));
   end Group_Id_For_Name;

   function User_Name_For_Id (Id : Account_Id) return String is
      Sid : Sid_Buffer;
   begin
      --  Every id minted here is Natural; a larger one was never handed out.
      if not Fits_Natural (Id) or else not Recall (Natural (Id), Sid) then
         return "";
      end if;

      declare
         Copy : aliased Sid_Buffer := Sid;
      begin
         return Name_Of (Copy (1)'Address);
      end;

   exception
      when others =>
         return "";
   end User_Name_For_Id;

   function Group_Name_For_Id (Id : Account_Id) return String is
   begin
      return User_Name_For_Id (Id);
   end Group_Name_For_Id;

   function Set_Ownership
     (Path     : String;
      User_Id  : Account_Id;
      Group_Id : Account_Id) return Boolean
   is
      C_Path : aliased Wide_String := Wide (Path);

      Owner_Sid : aliased Sid_Buffer;
      Group_Sid : aliased Sid_Buffer;
      --  Every id minted here is Natural; a larger one was never handed out.
      Have_Owner : constant Boolean :=
        Fits_Natural (User_Id) and then Recall (Natural (User_Id), Owner_Sid);
      Have_Group : constant Boolean :=
        Fits_Natural (Group_Id) and then Recall (Natural (Group_Id), Group_Sid);

      Information : C_DWord := 0;
      Status      : C_DWord;
   begin
      --  Only a SID this process has already seen can be named again: the
      --  identity the caller holds is a relative identifier, not a SID.
      if not Have_Owner and then not Have_Group then
         return False;
      end if;

      if Have_Owner then
         Information := Information or Owner_Information;
      end if;
      if Have_Group then
         Information := Information or Group_Information;
      end if;

      Status :=
        Set_Named_Security_Info
          (C_Path'Address, Se_File_Object, Information,
           (if Have_Owner then Owner_Sid (1)'Address else System.Null_Address),
           (if Have_Group then Group_Sid (1)'Address else System.Null_Address),
           System.Null_Address, System.Null_Address);

      Hostkit.Windows_Errors.Set_Errno_From (Interfaces.Unsigned_32 (Status));
      return Status = Success;

   exception
      when others =>
         return False;
   end Set_Ownership;

   --  False: the mode is rendered from the file's ACL, not stored by the
   --  filesystem. See the spec.
   function Mode_Bits_Are_Native return Boolean is
   begin
      return False;
   end Mode_Bits_Are_Native;

   function Ownership_Supported return Boolean is
   begin
      return True;
   end Ownership_Supported;

   procedure File_Ownership
     (Path      : String;
      User_Id   : out Natural;
      Group_Id  : out Natural;
      Available : out Boolean) renames Natural_Ids.File_Ownership;

   procedure File_Mode_And_Ownership
     (Path                : String;
      Mode_Bits           : out Natural;
      Mode_Available      : out Boolean;
      User_Id             : out Natural;
      Group_Id            : out Natural;
      Ownership_Available : out Boolean) renames Natural_Ids.File_Mode_And_Ownership;

   function User_Id_For_Name
     (Name  : String;
      Found : out Boolean)
      return Natural renames Natural_Ids.User_Id_For_Name;

   function Group_Id_For_Name
     (Name  : String;
      Found : out Boolean)
      return Natural renames Natural_Ids.Group_Id_For_Name;

end Hostkit.Metadata;
