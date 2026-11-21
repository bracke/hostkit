with Ada.Calendar.Formatting;
with Ada.Characters.Handling;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Strings.UTF_Encoding;
with Ada.Containers.Vectors;

with Hostkit.Directory_Listing;
with Hostkit.Errors;
with Hostkit.Fs;
with Hostkit.Path_Text;
with Hostkit.Win32;
with Hostkit.Windows_Errors;
with Hostkit.Windows_Paths;
with Hostkit.Windows_Programs;
with Interfaces.C;
with System;
with System.Storage_Elements;

with Hostkit.Metadata.Natural_Ids;

package body Hostkit.Metadata is
   use type Hostkit.File_Identities.Entry_Identity;
   use type Hostkit.Fs.Entry_Kind;
   use Hostkit.Win32;

   use Ada.Strings.Unbounded;
   use type Ada.Calendar.Time;
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned;
   use type Interfaces.C.unsigned_char;
   use type Interfaces.C.unsigned_short;
   use type Interfaces.C.unsigned_long;
   use type Interfaces.C.unsigned_long_long;
   use type Interfaces.Integer_64;
   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_64;
   use type System.Address;

   subtype C_Int is Interfaces.C.int;
   subtype C_DWord is Interfaces.C.unsigned_long;
   subtype C_U64 is Interfaces.C.unsigned_long_long;

   --  Windows has no POSIX mode bits and no uid/gid. It has an ACL and SIDs, so
   --  that is what this reads and writes: the effective rights of the owner, the
   --  primary group and Everyone are evaluated and folded into the rwx triplets
   --  the neutral interface speaks, and setting permissions edits the DACL
   --  until it reads back as those triplets (see Set_Permissions in the
   --  spec). A SID is identified to the caller by a stable hash of all its
   --  bytes, and the SID itself is remembered so a name can be recovered
   --  from that number later.

   Success : constant C_DWord := 0;

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
   File_Share_Delete     : constant C_DWord := 16#0000_0004#;
   File_Basic_Info_Class : constant C_Int := 0;

   --  Windows system error codes for a refusal no Win32 call reported, put
   --  into errno through Hostkit.Windows_Errors.Set_Errno_From:
   --  ERROR_FILE_NOT_FOUND (ENOENT; the CRT has no ESTALE) for an entry no
   --  longer the one asked about, ERROR_INVALID_PARAMETER (EINVAL) for a
   --  value out of range. A link refused is Hostkit.Win32's
   --  Error_Stopped_On_Symlink (ELOOP), which Is_Held_Link gives.
   Error_File_Not_Found     : constant Interfaces.Unsigned_32 := 2;
   Error_Invalid_Parameter  : constant Interfaces.Unsigned_32 := 87;

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
   --  so the number can be turned back into a name. Every task that reads
   --  an owner shares the list, so it is guarded.
   protected Seen_Sids is

      --  Is a SID with Id held?
      --
      --  @param Id A number Identity_Of minted.
      --  @return True when Add was given a SID with Id.
      function Holds (Id : Natural) return Boolean;

      --  Hold Item, unless a SID with its Id is held already.
      --
      --  @param Item The SID and its number.
      procedure Add (Item : Known_Sid);

      --  The SID held with Id.
      --
      --  @param Id A number Identity_Of minted.
      --  @param Into The SID's bytes; all NUL when none is held.
      --  @param Found Whether one is held.
      procedure Find (Id : Natural; Into : out Sid_Buffer; Found : out Boolean);

   private
      Items : Sid_Vectors.Vector;
   end Seen_Sids;

   protected body Seen_Sids is

      function Holds (Id : Natural) return Boolean is
      begin
         for Item of Items loop
            if Item.Id = Id then
               return True;
            end if;
         end loop;
         return False;
      end Holds;

      procedure Add (Item : Known_Sid) is
      begin
         if not Holds (Item.Id) then
            Items.Append (Item);
         end if;
      end Add;

      procedure Find (Id : Natural; Into : out Sid_Buffer; Found : out Boolean) is
      begin
         Into := [others => Interfaces.C.nul];
         Found := False;
         for Item of Items loop
            if Item.Id = Id then
               Into := Item.Bytes;
               Found := True;
               return;
            end if;
         end loop;
      end Find;

   end Seen_Sids;

   procedure Remember (Sid : System.Address; Id : Natural);
   function Recall (Id : Natural; Into : out Sid_Buffer) return Boolean;
   function Identity_Of (Sid : System.Address) return Natural;
   function Name_Of (Sid : System.Address) return String;
   function Wide (Value : String) return Wide_String;

   --  Text that names no file -- an account name, SDDL -- as UTF-16 with a
   --  terminating NUL, to pass by address to a wide API: none of the path
   --  rules Wide (Windows_Paths.Native) applies, which would read a name
   --  with a '/' or a "." as a path. Raises Encoding_Error on text that is
   --  not UTF-8, as From_UTF_8.
   function Wide_Text (Value : String) return Wide_String is
     (Hostkit.Windows_Paths.From_UTF_8 (Value) & Wide_Character'Val (0));

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
      if Sid = System.Null_Address or else Id = 0 or else Seen_Sids.Holds (Id) then
         return;
      end if;

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
            Seen_Sids.Add (Item);
         end if;
      end;

   exception
      when others =>
         null;
   end Remember;

   function Recall (Id : Natural; Into : out Sid_Buffer) return Boolean is
      Found : Boolean;
   begin
      Seen_Sids.Find (Id, Into, Found);
      return Found;
   end Recall;

   function Name_Of (Sid : System.Address) return String is separate;

   --------------------------------------------------------------------------

   --  Whether Windows runs Path, by its extension: the one list
   --  Hostkit.Fs.Is_Executable asks too.
   function Runs_On_Windows (Path : String) return Boolean
     renames Hostkit.Windows_Programs.Runs_By_Extension;

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

   --  Whatever the bits, the rights a POSIX stat needs none for: reading
   --  the attributes and the permissions, and synchronising. Without them
   --  a mode-0 entry could not even be looked at -- and so not renamed or
   --  deleted, which its folder allows -- for NTFS grants FILE_READ_ATTRIBUTES
   --  by no folder right.
   function Triplet_To_Rights (Triplet : Natural) return C_DWord is
      Synchronize : constant C_DWord := 16#0010_0000#;
      Result      : C_DWord := File_Read_Attributes or Read_Control or Synchronize;
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

   --  What the owner's ACE grants whatever its bits: WRITE_OWNER, so that the
   --  owner can still give the entry another group, as chgrp lets a POSIX
   --  owner. (Changing the DACL, chmod, is the owner's without an ACE.)
   Owner_Only_Rights : constant C_DWord := Write_Owner;

   --  The two times File_Creation_Time and File_Access_Time read, which
   --  GetFileAttributesExW hands back together.
   type Recorded_Time is (Creation, Last_Access);

   --  Which of Path's recorded times, as Ada time; Available False (and a
   --  time in 1901) when the host would not say or recorded none.
   function Recorded_Time_Of
     (Path      : String;
      Which     : Recorded_Time;
      Available : out Boolean) return Ada.Calendar.Time
   is separate;

   function File_Creation_Time
     (Path      : String;
      Available : out Boolean) return Ada.Calendar.Time is
   begin
      return Recorded_Time_Of (Path, Creation, Available);
   end File_Creation_Time;

   function File_Access_Time
     (Path      : String;
      Available : out Boolean) return Ada.Calendar.Time is
   begin
      return Recorded_Time_Of (Path, Last_Access, Available);
   end File_Access_Time;

   function Volume_Capacity_Of (Path : String) return Volume_Capacity is separate;

   --  A permission edit, the minimal kind: see Set_Permissions in the spec.

   Set_Access  : constant C_Int := 2;
   Deny_Access : constant C_Int := 3;

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

   --  ACE Index of Acl. Program_Error when GetAce will not give it: only an
   --  ACL that does not hold the count its header says does that.
   function Ace_At (Acl : System.Address; Index : Natural) return System.Address is
      Found : aliased System.Address := System.Null_Address;
   begin
      if Get_Ace (Acl, C_DWord (Index), Found'Access) = 0 then
         raise Program_Error;
      end if;
      return Found;
   end Ace_At;

   --  The rights Acl grants Sid, read the way the access check reads it --
   --  ACE by ACE, a right decided by the first allow or deny that names it --
   --  where an ACE names Sid, Everyone (S-1-1-0) or Member_Of. For the
   --  owner, Member_Of is the primary group, and Authenticated Users and
   --  BUILTIN\Users count too: the groups an account it is signed in as is
   --  in. Body below, by Specific_Rights.
   function Evaluated_Rights (Acl, Sid, Everyone, Member_Of : System.Address) return C_DWord;

   --  The rwx triplet Acl grants Sid, as File_Permission_Bits reads one; 0
   --  where there is no ACL to read. GetEffectiveRightsFromAcl answers it,
   --  and where it will not -- it fails outright when an ACE names a group
   --  whose members it cannot look up, as a deny for the primary group "None"
   --  on a machine outside a domain -- Evaluated_Rights does.
   function Triplet_Of
     (Acl, Sid, Everyone : System.Address;
      Member_Of          : System.Address := System.Null_Address) return Natural
   is
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
         Rights := Evaluated_Rights (Acl, Sid, Everyone, Member_Of);
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
     (Shown (Triplet_Of (Dacl, Owner, Everyone, Group), Runnable) * 64
      + Shown (Triplet_Of (Dacl, Group, Everyone), Runnable) * 8
      + Shown (Triplet_Of (Dacl, Everyone, Everyone), Runnable));

   --  Whether execute means something for the entry at Path: a program by
   --  its extension, or a folder, which can be entered. The one answer
   --  File_Permission_Bits reads a mode by and Set_Permissions edits one by.
   function Runnable_At (Path : String) return Boolean is
     (Runs_On_Windows (Path) or else Hostkit.Fs.Kind_Of (Path) = Hostkit.Fs.Directory_Entry);

   --  Path's mode as Mode_Of reads it, which is what Apply_Permission_Edit
   --  checks an edit against: reading it any other way could let the two
   --  drift, and an edit be judged by a mode the reader never shows.
   function File_Permission_Bits
     (Path      : String;
      Available : out Boolean) return Natural
   is separate;

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
   is separate;

   --  When the minimal edit does not give the mode asked for -- an ACE the
   --  entry inherits still grants a right the mode takes away -- the edit
   --  does what Explorer's "disable inheritance, convert inherited
   --  permissions into explicit permissions" and then a permission edit
   --  do: see Set_Permissions in the spec.

   Access_Allowed_Ace    : constant Interfaces.C.unsigned_char := 0;
   Access_Denied_Ace     : constant Interfaces.C.unsigned_char := 1;
   Object_Inherit_Ace    : constant Interfaces.C.unsigned_char := 16#01#;
   Container_Inherit_Ace : constant Interfaces.C.unsigned_char := 16#02#;
   No_Propagate_Ace      : constant Interfaces.C.unsigned_char := 16#04#;
   Inherit_Only_Ace      : constant Interfaces.C.unsigned_char := 16#08#;
   Ace_Inherited         : constant Interfaces.C.unsigned_char := 16#10#;
   Ace_Append_At_End     : constant C_DWord := 16#FFFF_FFFF#;

   Generic_Read_Access    : constant C_DWord := 16#8000_0000#;
   Generic_Write_Access   : constant C_DWord := 16#4000_0000#;
   Generic_Execute_Access : constant C_DWord := 16#2000_0000#;
   Generic_All_Access     : constant C_DWord := 16#1000_0000#;
   Specific_Access_Bits   : constant C_DWord := 16#0FFF_FFFF#;
   File_All_Access        : constant C_DWord := 16#001F_01FF#;
   File_Read_Ea           : constant C_DWord := 16#0000_0008#;
   File_Write_Ea          : constant C_DWord := 16#0000_0010#;
   File_Delete_Child      : constant C_DWord := 16#0000_0040#;

   Win_Authenticated_User_Sid : constant C_Int := 17;
   Win_Builtin_Users_Sid      : constant C_Int := 27;

   --  ERROR_NOT_SUPPORTED: no DACL this edit can write gives the mode.
   Error_Not_Supported : constant Interfaces.Unsigned_32 := 50;

   --  The class of a mode's triplets an ACE's trustee stands for. The owner
   --  and the primary group are their SIDs. "Other" is Everyone,
   --  Authenticated Users and BUILTIN\Users: the groups every account, or
   --  every one signed in, is in -- which is how an inherited ACE grants
   --  everybody a right. Every other trustee (SYSTEM, the Administrators,
   --  any named account) is no class: its ACEs are kept as they are.
   type Access_Class is (Owner_Class, Group_Class, Other_Class, No_Class);

   --  An ACL built here, DWORD-aligned as an ACL must be.
   type Acl_Words is array (Positive range <>) of Interfaces.Unsigned_32
     with Convention => C;

   --  Mask with its generic rights mapped to the file rights they stand for.
   function Specific_Rights (Mask : C_DWord) return C_DWord is
     ((Mask and Specific_Access_Bits)
      or (if (Mask and Generic_Read_Access) /= 0 then File_Generic_Read else 0)
      or (if (Mask and Generic_Write_Access) /= 0 then File_Generic_Write else 0)
      or (if (Mask and Generic_Execute_Access) /= 0 then File_Generic_Execute else 0)
      or (if (Mask and Generic_All_Access) /= 0 then File_All_Access else 0));

   function Evaluated_Rights (Acl, Sid, Everyone, Member_Of : System.Address) return C_DWord is separate;

   --  The rights an ACE carries for a triplet's bits: taken from an allow
   --  for a class that loses the bits, and from a deny for one that keeps
   --  them. Reading the attributes, the permissions and synchronising stay:
   --  POSIX lets anyone see a file's mode, whatever it says.
   function Rights_Of_Bits (Triplet : Natural) return C_DWord is
     ((if (Triplet / 4) mod 2 = 1 then File_Read_Data or File_Read_Ea else 0)
      or (if (Triplet / 2) mod 2 = 1
          then File_Write_Data or File_Append_Data or File_Write_Ea or File_Write_Attributes
               or File_Delete_Child or Delete_Access or Write_Dac or Write_Owner
          else 0)
      or (if Triplet mod 2 = 1 then File_Execute_Access else 0));

   --  The bits of either triplet.
   function Union (First, Second : Natural) return Natural is (First + Without (Second, First));

   --  The mode Mode_Of reads once Mode is applied: execute only where
   --  Runnable, nothing for an account the entry does not name, and the
   --  owner's bits for a group that is the owner itself -- one SID holds
   --  one triplet.
   function Target_Mode
     (Owner, Group : System.Address;
      Mode         : Natural;
      Runnable     : Boolean) return Natural
   is
      Owner_Bits : constant Natural :=
        (if Owner = System.Null_Address then 0 else Shown ((Mode / 64) mod 8, Runnable));
      Group_Bits : constant Natural :=
        (if Group = System.Null_Address then 0
         elsif Owner /= System.Null_Address and then Equal_Sid (Group, Owner) /= 0 then Owner_Bits
         else Shown ((Mode / 8) mod 8, Runnable));
   begin
      return Owner_Bits * 64 + Group_Bits * 8 + Shown (Mode mod 8, Runnable);
   end Target_Mode;

   --  Dacl (not null) converted to explicit ACEs and edited to read Target
   --  (Target_Mode): an empty list when the host would not build it.
   --
   --  Every ACE is kept, without its inherited flag, in the order it had:
   --  SYSTEM's, the Administrators', any other trustee's as they were. An
   --  allow for the owner, the group or "other" (Access_Class) loses the
   --  rights of the bits its class does not keep; a deny for one loses the
   --  rights its class is now given (by its own triplet, or the owner's and
   --  the group's it is part of). An ACE that also hands its rights down
   --  is split, so what a folder's children inherit does not change: the
   --  edited copy for the entry alone, and the original inherit-only.
   --
   --  Behind the explicit denies, before the explicit allows (where an edit
   --  puts them), come an allow for each class's bits and the denies the
   --  mode needs: one for what the owner would still get past its bits from
   --  a group it is in, and, after the owner's allow so the owner keeps
   --  what its own bits give, one for what the group would get past its bits
   --  -- from Everyone, when "other" has a bit the group lacks. A deny binds
   --  in order: the owner's allow before it has already decided the owner's
   --  rights, as POSIX decides the owner's access by the owner's bits alone.
   function Explicit_Dacl
     (Dacl, Owner, Group, Everyone : System.Address;
      Target                       : Natural;
      Runnable                     : Boolean) return Acl_Words is separate;

   --  A fresh DACL granting the owner, the primary group and Everyone
   --  exactly Mode's triplets and no one else: Set_Exact_Permissions' form.
   --  Result is a LocalAlloc'd ACL for the caller to free. False when the
   --  host would not build it.
   function Exact_Dacl
     (Owner, Group, Everyone : System.Address;
      Mode                   : Natural;
      Result                 : out System.Address) return Boolean
   is
      Sids    : constant array (1 .. 3) of System.Address := [Owner, Group, Everyone];
      Shifts  : constant array (Sids'Range) of Positive := [64, 8, 1];
      Entries : aliased Explicit_Access_Array;
      Built   : aliased System.Address := System.Null_Address;
      Status  : C_DWord;
   begin
      Result := System.Null_Address;
      for Index in Entries'Range loop
         Build_Trustee_With_Sid (Entries (Index).Trustee'Access, Sids (Index));
         Entries (Index).Permissions :=
           Triplet_To_Rights ((Mode / Shifts (Index)) mod 8) or (if Index = 1 then Owner_Only_Rights else 0);
         Entries (Index).Mode := Grant_Access;
         Entries (Index).Inheritance := No_Inheritance;
         Entries (Index).Trustee.Form := Trustee_Is_Sid;
         Entries (Index).Trustee.Kind := Trustee_Is_Unknown;
      end loop;
      Status := Set_Entries_In_Acl (3, Entries (1)'Address, System.Null_Address, Built'Access);
      if Status /= Success or else Built = System.Null_Address then
         Hostkit.Windows_Errors.Set_Errno_From (Interfaces.Unsigned_32 (Status));
         return False;
      end if;
      Result := Built;
      return True;
   end Exact_Dacl;

   --  Edit the access of the entry named by the NUL-terminated wide Path, or
   --  else open as Handle, from Old_Mode (Mode_Of its Dacl) to Mode, as
   --  Set_Permissions in the spec says. Control is the DACL's. Each form is
   --  tried in turn and written only when the mode it reads (Mode_Of, as
   --  File_Permission_Bits reads the entry once it is written) is the one
   --  asked for: the minimal edit, keeping inheritance; the DACL converted
   --  to explicit ACEs (Explicit_Dacl), protected; Exact_Dacl's three ACEs,
   --  protected. When none is, nothing is written: False, with errno set.
   function Apply_Permission_Edit
     (Path, Handle                 : System.Address;
      Dacl, Owner, Group, Everyone : System.Address;
      Control                      : Interfaces.C.unsigned_short;
      Old_Mode, Mode               : Natural;
      Runnable                     : Boolean) return Boolean
   is separate;

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
           (File, Se_File_Object, Dacl_Information, Owner'Address, Group'Address, Dacl'Address, Sacl'Address,
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

   --  SE_DACL_AUTO_INHERIT_REQ: a write that keeps SE_DACL_AUTO_INHERITED.
   Dacl_Auto_Inherit_Req : constant Interfaces.C.unsigned_short := 16#0100#;

   procedure Ignore_Result (Value : C_Int) is null;

   --  Put the DACL Text describes (Dacl_Text) back on the entry open as
   --  File exactly: its ACEs, inherited ones as they were, and whether it
   --  is protected. The entry alone, as Set_Own_Dacl.
   function Set_Dacl_Text (File : System.Address; Text : String) return Boolean is separate;

   function Set_Permissions
     (Path : String;
      Mode : Natural) return Boolean
   is separate;

   function Set_Exact_Permissions
     (Path : String;
      Mode : Natural) return Boolean
   is separate;

   function Inherit_From_Parent (Path : String) return Boolean is separate;

   function Set_File_Times
     (Path          : String;
      Access_Time   : Long_Long_Integer;
      Modified_Time : Long_Long_Integer)
      return Boolean
   is separate;

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

   function Open_Entry
     (Path         : String;
      Access_Mode  : C_DWord;
      Follow_Links : Boolean := False) return System.Address
   is
      Wide_Path : aliased Wide_String := Wide (Path);
   begin
      return Create_File
        (Wide_Path'Address, Access_Mode,
         File_Share_Read or File_Share_Write or File_Share_Delete,
         System.Null_Address, Open_Existing,
         File_Flag_Backup_Semantics
           or (if Follow_Links then 0 else File_Flag_Open_Reparse_Point),
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

   --  The identity of the entry open as File, with its attributes and the
   --  rest of BY_HANDLE_FILE_INFORMATION through Info: the 128-bit file id
   --  where the volume has one, else the 64-bit file index. Not Available,
   --  with Error the Windows error code that says why, when the host gives
   --  neither: GetLastError of the failed call, or ERROR_NOT_SUPPORTED for
   --  a volume that numbers no entry.
   function Identity_From_Handle
     (File  : System.Address;
      Info  : access By_Handle_File_Information;
      Error : out Interfaces.Unsigned_32) return Entry_Identity
   is separate;

   function Entry_Identity_Of (Path : String) return Entry_Identity is
      File          : System.Address := Open_Entry (Path, 0);
      Info          : aliased By_Handle_File_Information;
      Ignored_Error : Interfaces.Unsigned_32;
   begin
      if File = Invalid_Handle_Value then
         return (others => <>);
      end if;
      declare
         Result : constant Entry_Identity := Identity_From_Handle (File, Info'Access, Ignored_Error);
      begin
         Close_Entry (File);
         return Result;
      end;
   exception
      when others =>
         Close_Entry (File);
         return (others => <>);
   end Entry_Identity_Of;

   --  The SID of the account Name, into Sid, by LookupAccountNameW: asked
   --  first how much room the SID takes -- the call "fails" with
   --  ERROR_INSUFFICIENT_BUFFER and says, or fails for the reason there is
   --  no such account -- then for the SID. False when there is none, errno
   --  then set from the call's last error when Say_Why. Name not UTF-8
   --  raises, as converting it does.
   function Account_Sid
     (Name    : String;
      Sid     : out Sid_Buffer;
      Say_Why : Boolean) return Boolean
   is separate;

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
      Access_Text    : String := "";
      Beneath_Root   : String := "";
      Relative_Path  : String := "") return Metadata_Update_Result is separate;

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

   function Status_Of
     (Path         : String;
      Follow_Links : Boolean) return Entry_Status
   is separate;

   function Entry_Status_Of (Path : String) return Entry_Status is
     (Status_Of (Path, Follow_Links => False));

   function Private_To_Current_User (Path : String) return Boolean is separate;

   function File_Status_Of (Path : String) return Entry_Status is
     (Status_Of (Path, Follow_Links => True));

   --  The same words as POSIX gives: modification and change times as
   --  seconds since 1970 and nanoseconds, size, file number. FILE_BASIC_INFO
   --  keeps both times in 100 ns ticks since 1601; NTFS moves ChangeTime on
   --  every write and every change of the entry, and nothing sets it back.
   --  The link is followed, as stat follows it.
   function Change_Stamp
     (Path      : String;
      Available : out Boolean)
      return String
   is separate;

   --  BY_HANDLE_FILE_INFORMATION of what Path names, through any link, as
   --  stat reads an entry: its volume serial number and file index are
   --  stat's device and inode. False when it cannot be opened.
   function Followed_Information (Path : String; Info : access By_Handle_File_Information) return Boolean is
      Wide_Path : aliased Wide_String := Wide (Path);
      File      : System.Address :=
        Create_File
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
   end Followed_Information;

   function Same_File (Left : String; Right : String) return Boolean is
      --  Windows filesystems are case-insensitive, so two paths that normalise
      --  to the same absolute string ignoring case name the same file. Made
      --  absolute as text: GNAT's Full_Name refuses a path past 260
      --  characters.
      function Normalized (Path : String) return String is
        (Ada.Characters.Handling.To_Lower
           (Hostkit.Path_Text.Absolute (Path, Hostkit.Fs.Current_Directory)));

      Left_Info  : aliased By_Handle_File_Information;
      Right_Info : aliased By_Handle_File_Information;
   begin
      --  The volume and file index tell two hard links to one file apart
      --  from two files.
      if Followed_Information (Left, Left_Info'Access) and then Followed_Information (Right, Right_Info'Access) then
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

   --  The serial number of the volume holding what Path names, through any
   --  link, as stat's device follows one: read from the entry itself, and
   --  where it cannot be opened, from the root of its volume
   --  (GetVolumePathNameW), which reports the same number. Only where
   --  neither answers is the volume's root path hashed instead -- a drive
   --  letter or a share -- which still tells two volumes apart.
   function Device_Id
     (Path      : String;
      Available : out Boolean)
      return Long_Long_Integer
   is separate;

   function Lookup_Identity
     (Name  : String;
      Found : out Boolean) return Natural;

   function Lookup_Identity
     (Name  : String;
      Found : out Boolean) return Natural
   is
      Sid : aliased Sid_Buffer := [others => Interfaces.C.nul];
      Id  : Natural;
   begin
      Found := False;
      --  Converted in the call, not in a declaration here, so that a name
      --  that is not UTF-8 is a name not found rather than an exception to
      --  the caller.
      if not Account_Sid (Name, Sid, Say_Why => False) then
         return 0;
      end if;
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
   is separate;

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

   function Inherit_Rewrites_Change_Times return Boolean is (True);

end Hostkit.Metadata;
