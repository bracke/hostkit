with Ada.Characters.Handling;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Strings.UTF_Encoding.Conversions;
with Ada.Containers.Vectors;

with Interfaces.C.Strings;
with System;
with System.Storage_Elements;

package body Hostkit.Metadata is
   use Ada.Strings.Unbounded;
   use type Ada.Calendar.Time;
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned;
   use type Interfaces.C.unsigned_char;
   use type Interfaces.C.unsigned_short;
   use type Interfaces.C.unsigned_long;
   use type Interfaces.C.unsigned_long_long;
   use type Interfaces.C.Strings.chars_ptr;
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

   --  PROTECTED_DACL_SECURITY_INFORMATION. Without it the new DACL is merged
   --  with whatever the parent directory hands down, so revoking a right does not
   --  revoke it: an inherited ACE keeps granting it, and a mode set to 0600 reads
   --  back with the group and Everyone bits still on.
   Protected_Dacl : constant C_DWord := 16#8000_0000#;

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
     (Object_Name : Interfaces.C.Strings.chars_ptr;
      Object_Type : C_Int;
      Information : C_DWord;
      Owner       : access System.Address;
      Group       : access System.Address;
      Dacl        : access System.Address;
      Sacl        : access System.Address;
      Descriptor  : access System.Address) return C_DWord
     with Import, Convention => Stdcall,
          External_Name => "GetNamedSecurityInfoA";

   function Set_Named_Security_Info
     (Object_Name : Interfaces.C.Strings.chars_ptr;
      Object_Type : C_Int;
      Information : C_DWord;
      Owner       : System.Address;
      Group       : System.Address;
      Dacl        : System.Address;
      Sacl        : System.Address) return C_DWord
     with Import, Convention => Stdcall,
          External_Name => "SetNamedSecurityInfoA";

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
     (Name  : Interfaces.C.Strings.chars_ptr;
      Level : C_Int;
      Data  : access Attribute_Data) return C_Int
     with Import, Convention => Stdcall,
          External_Name => "GetFileAttributesExA";

   function Get_Disk_Free_Space_Ex
     (Directory       : Interfaces.C.Strings.chars_ptr;
      Free_To_Caller  : access C_U64;
      Total           : access C_U64;
      Total_Free      : access C_U64) return C_Int
     with Import, Convention => Stdcall,
          External_Name => "GetDiskFreeSpaceExA";

   function Get_Volume_Information
     (Root         : Interfaces.C.Strings.chars_ptr;
      Name         : System.Address;
      Name_Size    : C_DWord;
      Serial       : access C_DWord;
      Component    : access C_DWord;
      Flags        : access C_DWord;
      System_Name  : System.Address;
      System_Size  : C_DWord) return C_Int
     with Import, Convention => Stdcall,
          External_Name => "GetVolumeInformationA";

   function Get_Final_Path_Name
     (File   : System.Address;
      Path   : System.Address;
      Length : C_DWord;
      Flags  : C_DWord) return C_DWord
     with Import, Convention => Stdcall,
          External_Name => "GetFinalPathNameByHandleA";

   function Create_File
     (Name        : Interfaces.C.Strings.chars_ptr;
      Access_Mode : C_DWord;
      Share       : C_DWord;
      Security    : System.Address;
      Disposition : C_DWord;
      Flags       : C_DWord;
      Template    : System.Address) return System.Address
     with Import, Convention => Stdcall, External_Name => "CreateFileA";

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

   function Get_Volume_Information_By_Handle
     (File             : System.Address;
      Volume_Name      : System.Address;
      Volume_Name_Size : C_DWord;
      Serial           : System.Address;
      Maximum_Name     : System.Address;
      Flags            : System.Address;
      File_System_Name : System.Address;
      File_System_Size : C_DWord) return C_Int
     with Import, Convention => Stdcall, External_Name => "GetVolumeInformationByHandleW";

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
               else Ada.Strings.UTF_Encoding.Conversions.Convert
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

   procedure Safe_Free (Item : in out Interfaces.C.Strings.chars_ptr);

   procedure Safe_Free (Item : in out Interfaces.C.Strings.chars_ptr) is
   begin
      if Item /= Interfaces.C.Strings.Null_Ptr then
         Interfaces.C.Strings.Free (Item);
      end if;
   end Safe_Free;

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
      C_Path : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Path);
      Data   : aliased Attribute_Data;
      Result : C_Int;
      Epoch  : constant Ada.Calendar.Time := Ada.Calendar.Time_Of (1970, 1, 1);
   begin
      Available := False;

      Result := Get_File_Attributes_Ex (C_Path, 0, Data'Access);
      Interfaces.C.Strings.Free (C_Path);

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
      C_Path : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Path);
      Data   : aliased Attribute_Data;
      Result : C_Int;
      Epoch  : constant Ada.Calendar.Time := Ada.Calendar.Time_Of (1970, 1, 1);
   begin
      Available := False;

      Result := Get_File_Attributes_Ex (C_Path, 0, Data'Access);
      Interfaces.C.Strings.Free (C_Path);

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
      C_Path : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Path);

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
          (C_Path, Free_To_Caller'Access, Total'Access, Total_Free'Access);

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
         Root : Interfaces.C.Strings.chars_ptr :=
           Interfaces.C.Strings.Null_Ptr;
      begin
         if Path'Length >= 2 and then Path (Path'First + 1) = ':' then
            Root :=
              Interfaces.C.Strings.New_String
                (Path (Path'First .. Path'First + 1) & "\");
         else
            Root := Interfaces.C.Strings.New_String (Path);
         end if;

         Result :=
           Get_Volume_Information
             (Root,
              System.Null_Address, 0,
              Serial'Access, Component'Access, Flags'Access,
              System.Null_Address, 0);

         Interfaces.C.Strings.Free (Root);
      end;

      if Result /= 0 then
         Answer.Name_Max := Natural (Component);
         Answer.Name_Max_Known := True;
         Answer.Read_Only := (Flags and Read_Only_Volume) /= 0;
         Answer.Read_Only_Known := True;
      end if;

      Interfaces.C.Strings.Free (C_Path);
      return Answer;

   exception
      when others =>
         Safe_Free (C_Path);
         return (others => <>);
   end Volume_Capacity_Of;

   function File_Permission_Bits
     (Path      : String;
      Available : out Boolean) return Natural
   is
      C_Path : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Path);

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
          (C_Path, Se_File_Object,
           Owner_Information or Group_Information or Dacl_Information,
           Owner'Access, Group'Access, Dacl'Access, Sacl'Access,
           Descriptor'Access);
      Interfaces.C.Strings.Free (C_Path);

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

      --  Strip the execute bits unless the file is one Windows would actually run.
      if not Runs_On_Windows (Path) then
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
         Safe_Free (C_Path);
         Free_Descriptor;
         Available := False;
         return 0;
   end File_Permission_Bits;

   function Set_Permissions
     (Path : String;
      Mode : Natural) return Boolean
   is
      C_Path : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Path);

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
          (C_Path, Se_File_Object,
           Owner_Information or Group_Information or Dacl_Information,
           Owner'Access, Group'Access, Dacl'Access, Sacl'Access,
           Descriptor'Access);

      if Status /= Success then
         Interfaces.C.Strings.Free (C_Path);
         return False;
      end if;

      if Create_Well_Known_Sid
           (Win_World_Sid, System.Null_Address,
            Everyone (1)'Address, Everyone_Size'Access) = 0
      then
         Interfaces.C.Strings.Free (C_Path);
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
         Interfaces.C.Strings.Free (C_Path);
         Free_Allocations;
         return False;
      end if;

      Status :=
        Set_Named_Security_Info
          (C_Path, Se_File_Object, Dacl_Information or Protected_Dacl,
           System.Null_Address, System.Null_Address,
           New_Acl, System.Null_Address);

      Interfaces.C.Strings.Free (C_Path);

      Free_Allocations;

      return Status = Success;

   exception
      when others =>
         Safe_Free (C_Path);
         Free_Allocations;
         return False;
   end Set_Permissions;

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

      C_Path : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Path);
      File   : System.Address := System.Null_Address;
      Access_Filetime   : aliased Filetime := To_Filetime (Access_Time);
      Modified_Filetime : aliased Filetime := To_Filetime (Modified_Time);
      Result : C_Int;
   begin
      File :=
        Create_File
          (C_Path,
           File_Read_Attributes or File_Write_Attributes,
           File_Share_Read or File_Share_Write or File_Share_Delete,
           System.Null_Address,
           Open_Existing,
           File_Attribute_Normal or File_Flag_Backup_Semantics,
           System.Null_Address);
      Interfaces.C.Strings.Free (C_Path);

      if File = System.Null_Address or else File = Invalid_Handle_Value then
         return False;
      end if;

      Result :=
        Set_File_Time
          (File,
           System.Null_Address,
           Access_Filetime'Access,
           Modified_Filetime'Access);
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
         if C_Path /= Interfaces.C.Strings.Null_Ptr then
            Interfaces.C.Strings.Free (C_Path);
         end if;
         return False;
   end Set_File_Times;

   function Permissions_Supported return Boolean is
   begin
      return True;
   end Permissions_Supported;

   procedure File_Ownership
     (Path      : String;
      User_Id   : out Natural;
      Group_Id  : out Natural;
      Available : out Boolean)
   is
      C_Path : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Path);

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
          (C_Path, Se_File_Object,
           Owner_Information or Group_Information,
           Owner'Access, Group'Access, Dacl'Access, Sacl'Access,
           Descriptor'Access);
      Interfaces.C.Strings.Free (C_Path);

      if Status /= Success then
         Free_Descriptor;
         return;
      end if;

      User_Id := Identity_Of (Owner);
      Group_Id := Identity_Of (Group);
      Remember (Owner, User_Id);
      Remember (Group, Group_Id);
      Available := True;

      Free_Descriptor;

   exception
      when others =>
         Safe_Free (C_Path);
         Free_Descriptor;
         User_Id := 0;
         Group_Id := 0;
         Available := False;
   end File_Ownership;

   procedure File_Mode_And_Ownership
     (Path                : String;
      Mode_Bits           : out Natural;
      Mode_Available      : out Boolean;
      User_Id             : out Natural;
      Group_Id            : out Natural;
      Ownership_Available : out Boolean) is
   begin
      Mode_Bits := File_Permission_Bits (Path, Mode_Available);
      File_Ownership (Path, User_Id, Group_Id, Ownership_Available);
   end File_Mode_And_Ownership;

   function Wide (Value : String) return Wide_String is
     (Ada.Strings.UTF_Encoding.Conversions.Convert (Value) & Wide_Character'Val (0));

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

   function Is_NTFS (File : System.Address) return Boolean is
      Name : aliased Wide_String (1 .. 16) := [others => Wide_Character'Val (0)];
   begin
      return Get_Volume_Information_By_Handle
        (File, System.Null_Address, 0, System.Null_Address, System.Null_Address,
         System.Null_Address, Name'Address, C_DWord (Name'Length)) /= 0
        and then Name (1) in 'N' | 'n'
        and then Name (2) in 'T' | 't'
        and then Name (3) in 'F' | 'f'
        and then Name (4) in 'S' | 's'
        and then Name (5) = Wide_Character'Val (0);
   end Is_NTFS;

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
      if not Is_NTFS (File) or else Number = 0 or else Number = Identity_Field'Last then
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
      Group_Name     : String := "") return Metadata_Update_Result
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
         if not Is_NTFS (File)
           or else Number = 0
           or else Number = Identity_Field'Last
         then
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
                  Answer.Success := Set_Security_Info
                    (File, Se_File_Object,
                     Owner_Information or Group_Information,
                     New_Owner, New_Group, System.Null_Address,
                     System.Null_Address) = Success;
               end if;
            end;
         end if;
      else
         declare
            function Rights_For (Sid : System.Address) return Natural is
               Trustee : aliased Trustee_Record;
               Rights  : aliased C_DWord := 0;
            begin
               if Sid = System.Null_Address
                 or else Dacl = System.Null_Address
               then
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

            Everyone : aliased Sid_Buffer := [others => Interfaces.C.nul];
            Everyone_Size : aliased C_DWord := C_DWord (Sid_Buffer'Length);
            Entries : aliased Explicit_Access_Array;
            Mode : Natural;
            Status : C_DWord;
         begin
            if Create_Well_Known_Sid
              (Win_World_Sid, System.Null_Address, Everyone (1)'Address,
               Everyone_Size'Access) /= 0
            then
               Mode := Rights_For (Owner) * 64
                 + Rights_For (Primary_Group) * 8
                 + Rights_For (Everyone (1)'Address);
               if not Runs_On_Windows (Path) then
                  Mode := Mode - ((Mode / 64) mod 2) * 64
                    - ((Mode / 8) mod 2) * 8 - (Mode mod 2);
               end if;
               Answer.Previous := Identity_Field (Mode);

               Build_Trustee_With_Sid
                 (Entries (1).Trustee'Access, Owner);
               Entries (1).Permissions := Triplet_To_Rights
                 (Natural (Value / 64 mod 8));
               Entries (1).Mode := Grant_Access;
               Entries (1).Inheritance := No_Inheritance;
               Entries (1).Trustee.Form := Trustee_Is_Sid;
               Entries (1).Trustee.Kind := Trustee_Is_Unknown;

               Build_Trustee_With_Sid
                 (Entries (2).Trustee'Access, Primary_Group);
               Entries (2).Permissions := Triplet_To_Rights
                 (Natural (Value / 8 mod 8));
               Entries (2).Mode := Grant_Access;
               Entries (2).Inheritance := No_Inheritance;
               Entries (2).Trustee.Form := Trustee_Is_Sid;
               Entries (2).Trustee.Kind := Trustee_Is_Unknown;

               Build_Trustee_With_Sid
                 (Entries (3).Trustee'Access, Everyone (1)'Address);
               Entries (3).Permissions := Triplet_To_Rights
                 (Natural (Value mod 8));
               Entries (3).Mode := Grant_Access;
               Entries (3).Inheritance := No_Inheritance;
               Entries (3).Trustee.Form := Trustee_Is_Sid;
               Entries (3).Trustee.Kind := Trustee_Is_Unknown;

               Status := Set_Entries_In_Acl
                 (3, Entries (1)'Address, System.Null_Address,
                  New_Acl'Access);
               if Status = Success and then New_Acl /= System.Null_Address then
                  Answer.Success := Set_Security_Info
                    (File, Se_File_Object, Dacl_Information or Protected_Dacl,
                     System.Null_Address, System.Null_Address, New_Acl,
                     System.Null_Address) = Success;
               end if;
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

   --  No stamp this fine is read here yet: unknown, never a guess.
   function Change_Stamp
     (Path      : String;
      Available : out Boolean)
      return String
   is
      pragma Unreferenced (Path);
   begin
      Available := False;
      return "";
   end Change_Stamp;

   function Same_File (Left : String; Right : String) return Boolean is
      --  Windows filesystems are case-insensitive, so two paths that normalise
      --  to the same absolute string ignoring case name the same file.
      function Normalized (Path : String) return String is
        (Ada.Characters.Handling.To_Lower (Ada.Directories.Full_Name (Path)));
   begin
      return Ada.Directories.Exists (Left)
        and then Ada.Directories.Exists (Right)
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
      Full : constant String := Ada.Characters.Handling.To_Lower (Ada.Directories.Full_Name (Path));
      Last : Natural := Full'First - 1;
      Hash : C_U64 := 14_695_981_039_346_656;
   begin
      Available := Ada.Directories.Exists (Path);
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
      Found : out Boolean) return Natural is
   begin
      return Lookup_Identity (Name, Found);
   end User_Id_For_Name;

   function Group_Id_For_Name
     (Name  : String;
      Found : out Boolean) return Natural is
   begin
      return Lookup_Identity (Name, Found);
   end Group_Id_For_Name;

   function User_Name_For_Id (Id : Natural) return String is
      Sid : Sid_Buffer;
   begin
      if not Recall (Id, Sid) then
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

   function Group_Name_For_Id (Id : Natural) return String is
   begin
      return User_Name_For_Id (Id);
   end Group_Name_For_Id;

   function Set_Ownership
     (Path     : String;
      User_Id  : Natural;
      Group_Id : Natural) return Boolean
   is
      C_Path : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Path);

      Owner_Sid : aliased Sid_Buffer;
      Group_Sid : aliased Sid_Buffer;
      Have_Owner : constant Boolean := Recall (User_Id, Owner_Sid);
      Have_Group : constant Boolean := Recall (Group_Id, Group_Sid);

      Information : C_DWord := 0;
      Status      : C_DWord;
   begin
      --  Only a SID this process has already seen can be named again: the
      --  identity the caller holds is a relative identifier, not a SID.
      if not Have_Owner and then not Have_Group then
         Interfaces.C.Strings.Free (C_Path);
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
          (C_Path, Se_File_Object, Information,
           (if Have_Owner then Owner_Sid (1)'Address else System.Null_Address),
           (if Have_Group then Group_Sid (1)'Address else System.Null_Address),
           System.Null_Address, System.Null_Address);

      Interfaces.C.Strings.Free (C_Path);
      return Status = Success;

   exception
      when others =>
         Safe_Free (C_Path);
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

end Hostkit.Metadata;
