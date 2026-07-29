with Ada.Characters.Handling;
with Ada.Directories;
with Ada.Strings.Unbounded;
with Ada.Containers.Vectors;

with Interfaces.C.Strings;
with System;

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
   use type System.Address;

   subtype C_Int is Interfaces.C.int;
   subtype C_DWord is Interfaces.C.unsigned_long;
   subtype C_U64 is Interfaces.C.unsigned_long_long;

   --  Windows has no POSIX mode bits and no uid/gid. It has an ACL and SIDs, so
   --  that is what this reads and writes: the effective rights of the owner, the
   --  primary group and Everyone are evaluated and folded into the rwx triplets
   --  the neutral interface speaks, and setting permissions builds a fresh DACL
   --  granting exactly those rights back. A SID is identified to the caller by
   --  its relative identifier -- the last sub-authority -- and the SID itself is
   --  remembered so a name can be recovered from that number later.

   Success : constant C_DWord := 0;

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

   Win_World_Sid : constant C_Int := 1;
   --  WinWorldSid: the "Everyone" group, which stands in for the POSIX "other".

   Read_Only_Volume : constant C_DWord := 16#0008_0000#;

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

   function Lookup_Account_Sid
     (System_Name : Interfaces.C.Strings.chars_ptr;
      Sid         : System.Address;
      Name        : System.Address;
      Name_Size   : access C_DWord;
      Domain      : System.Address;
      Domain_Size : access C_DWord;
      Use_Kind    : access C_Int) return C_Int
     with Import, Convention => Stdcall,
          External_Name => "LookupAccountSidA";

   function Lookup_Account_Name
     (System_Name : Interfaces.C.Strings.chars_ptr;
      Account     : Interfaces.C.Strings.chars_ptr;
      Sid         : System.Address;
      Sid_Size    : access C_DWord;
      Domain      : System.Address;
      Domain_Size : access C_DWord;
      Use_Kind    : access C_Int) return C_Int
     with Import, Convention => Stdcall,
          External_Name => "LookupAccountNameA";

   function Get_Sid_Sub_Authority_Count
     (Sid : System.Address) return System.Address
     with Import, Convention => Stdcall,
          External_Name => "GetSidSubAuthorityCount";

   function Get_Sid_Sub_Authority
     (Sid   : System.Address;
      Index : C_DWord) return System.Address
     with Import, Convention => Stdcall,
          External_Name => "GetSidSubAuthority";

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

   function Close_Handle (Item : System.Address) return C_Int
     with Import, Convention => Stdcall, External_Name => "CloseHandle";

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

   --  A SID has no small integer identity of its own, so the caller is given its
   --  relative identifier -- the last sub-authority, which is what distinguishes
   --  one account from another on a machine. The SID itself is kept here so the
   --  number can be turned back into a name.
   Seen_Sids : Sid_Vectors.Vector;

   procedure Remember (Sid : System.Address; Id : Natural);
   function Recall (Id : Natural; Into : out Sid_Buffer) return Boolean;
   function Identity_Of (Sid : System.Address) return Natural;
   function Name_Of (Sid : System.Address) return String;

   function Identity_Of (Sid : System.Address) return Natural is
      Count_Ptr : constant System.Address := Get_Sid_Sub_Authority_Count (Sid);
      Count     : Interfaces.C.unsigned_char
        with Import, Address => Count_Ptr;
   begin
      if Sid = System.Null_Address or else Count = 0 then
         return 0;
      end if;

      declare
         Last_Ptr : constant System.Address :=
           Get_Sid_Sub_Authority (Sid, C_DWord (Count) - 1);
         Last     : C_DWord with Import, Address => Last_Ptr;
      begin
         return Natural (Last mod C_DWord (Natural'Last));
      end;

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
      Name        : aliased Interfaces.C.char_array (1 .. 256) :=
        [others => Interfaces.C.nul];
      Domain      : aliased Interfaces.C.char_array (1 .. 256) :=
        [others => Interfaces.C.nul];
      Name_Size   : aliased C_DWord := 256;
      Domain_Size : aliased C_DWord := 256;
      Use_Kind    : aliased C_Int := 0;
      Result      : C_Int;
   begin
      if Sid = System.Null_Address then
         return "";
      end if;

      Result :=
        Lookup_Account_Sid
          (Interfaces.C.Strings.Null_Ptr,
           Sid,
           Name'Address, Name_Size'Access,
           Domain'Address, Domain_Size'Access,
           Use_Kind'Access);

      if Result = 0 then
         return "";
      end if;

      declare
         Text : String (1 .. Natural (Name_Size));
      begin
         for Index in Text'Range loop
            Text (Index) :=
              Character'Val
                (Interfaces.C.char'Pos
                   (Name (Interfaces.C.size_t (Index))));
         end loop;
         return Text;
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
      --  .tar.gz as a program. What runs here is decided by the extension.
      Runnable : constant array (1 .. 6) of access constant String :=
        [new String'(".exe"), new String'(".com"), new String'(".bat"),
         new String'(".cmd"), new String'(".ps1"), new String'(".msi")];
   begin
      for Suffix of Runnable loop
         declare
            Text : constant String := Suffix.all;
         begin
            if Path'Length >= Text'Length then
               declare
                  Tail : constant String :=
                    Path (Path'Last - Text'Length + 1 .. Path'Last);
                  Lower : String := Tail;
               begin
                  for Index in Lower'Range loop
                     if Lower (Index) in 'A' .. 'Z' then
                        Lower (Index) :=
                          Character'Val
                            (Character'Pos (Lower (Index)) + 32);
                     end if;
                  end loop;

                  if Lower = Text then
                     return True;
                  end if;
               end;
            end if;
         end;
      end loop;

      return False;
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

      if Descriptor /= System.Null_Address then
         declare
            Freed : constant System.Address := Local_Free (Descriptor);
            pragma Unreferenced (Freed);
         begin
            null;
         end;
      end if;

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
      procedure Free_Descriptor is
         Freed : System.Address;
         pragma Unreferenced (Freed);
      begin
         if Descriptor /= System.Null_Address then
            Freed := Local_Free (Descriptor);
         end if;
      end Free_Descriptor;
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
         Free_Descriptor;
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
         Free_Descriptor;
         return False;
      end if;

      Status :=
        Set_Named_Security_Info
          (C_Path, Se_File_Object, Dacl_Information or Protected_Dacl,
           System.Null_Address, System.Null_Address,
           New_Acl, System.Null_Address);

      Interfaces.C.Strings.Free (C_Path);

      declare
         Freed : System.Address;
         pragma Unreferenced (Freed);
      begin
         Freed := Local_Free (New_Acl);
      end;
      Free_Descriptor;

      return Status = Success;

   exception
      when others =>
         Safe_Free (C_Path);
         return False;
   end Set_Permissions;

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
         return;
      end if;

      User_Id := Identity_Of (Owner);
      Group_Id := Identity_Of (Group);
      Remember (Owner, User_Id);
      Remember (Group, Group_Id);
      Available := True;

      if Descriptor /= System.Null_Address then
         declare
            Freed : constant System.Address := Local_Free (Descriptor);
            pragma Unreferenced (Freed);
         begin
            null;
         end;
      end if;

   exception
      when others =>
         Safe_Free (C_Path);
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

   function Lookup_Identity
     (Name  : String;
      Found : out Boolean) return Natural;

   function Lookup_Identity
     (Name  : String;
      Found : out Boolean) return Natural
   is
      C_Name : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Name);

      Sid         : aliased Sid_Buffer := [others => Interfaces.C.nul];
      Sid_Size    : aliased C_DWord := C_DWord (Sid_Buffer'Length);
      Domain      : aliased Interfaces.C.char_array (1 .. 256) :=
        [others => Interfaces.C.nul];
      Domain_Size : aliased C_DWord := 256;
      Use_Kind    : aliased C_Int := 0;
      Result      : C_Int;
      Id          : Natural;
   begin
      Found := False;

      Result :=
        Lookup_Account_Name
          (Interfaces.C.Strings.Null_Ptr, C_Name,
           Sid (1)'Address, Sid_Size'Access,
           Domain'Address, Domain_Size'Access,
           Use_Kind'Access);
      Interfaces.C.Strings.Free (C_Name);

      if Result = 0 then
         return 0;
      end if;

      Id := Identity_Of (Sid (1)'Address);
      Remember (Sid (1)'Address, Id);
      Found := Id /= 0;
      return Id;

   exception
      when others =>
         Safe_Free (C_Name);
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

   function Ownership_Supported return Boolean is
   begin
      return True;
   end Ownership_Supported;

end Hostkit.Metadata;
