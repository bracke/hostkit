with Hostkit.Errors;
with Hostkit.Win32;
with Hostkit.Windows_Errors;
with Hostkit.Windows_Paths;
with Interfaces;
with Interfaces.C;
with System;

package body Hostkit.Private_Paths is
   use Hostkit.Win32;
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned_long;
   use type System.Address;

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

   type Byte_Buffer is array (Natural range <>) of aliased Interfaces.Unsigned_8
     with Convention => C;

   File_Share_All               : constant C_DWord := 7;
   Read_Control                 : constant C_DWord := 16#0002_0000#;
   Write_Dac                    : constant C_DWord := 16#0004_0000#;
   Write_Owner                  : constant C_DWord := 16#0008_0000#;
   Owner_Security_Information  : constant C_DWord := 16#0000_0001#;
   Dacl_Security_Information   : constant C_DWord := 16#0000_0004#;
   Protected_Dacl_Information : constant C_DWord := 16#8000_0000#;
   --  TOKEN_INFORMATION_CLASS: TokenUser and TokenOwner.
   Token_User_Class  : constant C_Int := 1;
   Token_Owner_Class : constant C_Int := 4;
   Sddl_Revision_1 : constant C_DWord := 1;
   Error_File_Exists    : constant C_DWord := 80;
   Error_Already_Exists : constant C_DWord := 183;

   --  Windows system error codes for a refusal no Win32 call reported, put
   --  into errno through Hostkit.Windows_Errors.Set_Errno_From:
   --  ERROR_FILE_NOT_FOUND (ENOENT; the CRT has no ESTALE) for a name that
   --  no longer leads to the entry held, ERROR_DIRECTORY (ENOTDIR) for an
   --  entry that is no folder, ERROR_INVALID_PARAMETER (EINVAL) for data
   --  the host handed back unusable, and ERROR_PRIVILEGE_NOT_HELD (EPERM,
   --  as chmod answers anyone but the owner) for an entry this process
   --  does not own.
   Error_File_Not_Found     : constant Interfaces.Unsigned_32 := 2;
   Error_Invalid_Parameter  : constant Interfaces.Unsigned_32 := 87;
   Error_Directory          : constant Interfaces.Unsigned_32 := 267;
   Error_Privilege_Not_Held : constant Interfaces.Unsigned_32 := 1314;

   --  The DACL a private entry is given: its owner alone, with full access,
   --  handed down to what a folder holds; protected from its parent's.
   Private_Sddl : constant String := "D:P(A;OICI;FA;;;OW)";

   function Wide (Value : String) return Wide_String renames Hostkit.Windows_Paths.Native;

   --  Text that names no file -- SDDL -- as UTF-16 with a terminating NUL:
   --  none of the path rules Wide (Windows_Paths.Native) applies.
   function Wide_Text (Value : String) return Wide_String is
     (Hostkit.Windows_Paths.From_UTF_8 (Value) & Wide_Character'Val (0));

   function Create_Directory_W
     (Name : System.Address;
      Attributes : access Security_Attributes) return C_Int
     with Import, Convention => Stdcall, External_Name => "CreateDirectoryW";

   --  For an open that failed: its last error put into errno; always False.
   function Refused return Boolean is
   begin
      Hostkit.Errors.Set_Errno_From_Last_Error;
      return False;
   end Refused;

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
   function Equal_Sid (Left, Right : System.Address) return C_Int
     with Import, Convention => Stdcall, External_Name => "EqualSid";
   --  ConvertSidToStringSidW: the SID as "S-1-5-21-...", LocalAlloc'd.
   function Convert_Sid_To_String (Sid : System.Address; Text : access System.Address) return C_Int
     with Import, Convention => Stdcall, External_Name => "ConvertSidToStringSidW";
   --  ReOpenFile: a second handle on the entry Original holds, with other
   --  access; INVALID_HANDLE_VALUE on failure.
   function Re_Open_File
     (Original : System.Address; Desired, Share, Flags : C_DWord) return System.Address
     with Import, Convention => Stdcall, External_Name => "ReOpenFile";

   --  Whether Left and Right are one entry: by the 128-bit file ID, or on a
   --  volume that has none (FAT, exFAT) by volume serial and file index.
   function Same_File (Left, Right : System.Address) return Boolean is
      Left_Id, Right_Id : aliased File_Id_Info;
      Left_Info, Right_Info : aliased By_Handle_File_Information;
   begin
      if Get_File_Information_Ex
          (Left, File_Id_Info_Class, Left_Id'Address, C_DWord (File_Id_Info'Size / 8)) /= 0
        and then Get_File_Information_Ex
          (Right, File_Id_Info_Class, Right_Id'Address, C_DWord (File_Id_Info'Size / 8)) /= 0
      then
         return Left_Id = Right_Id;
      end if;
      return Get_File_Information (Left, Left_Info'Access) /= 0
        and then Get_File_Information (Right, Right_Info'Access) /= 0
        and then Left_Info.Volume_Serial = Right_Info.Volume_Serial
        and then Left_Info.File_Index_High = Right_Info.File_Index_High
        and then Left_Info.File_Index_Low = Right_Info.File_Index_Low;
   end Same_File;

   --  TOKEN_USER or TOKEN_OWNER, led by its SID's address with the SID
   --  after it; eight-byte words, so that address is aligned.
   type Token_Buffer is array (0 .. 255) of Interfaces.Unsigned_64
     with Convention => C;

   --  Read the process token's information of Class (TokenUser or
   --  TokenOwner) into Buffer. False, with errno set, when the token will
   --  not say.
   function Read_Token (Class : C_Int; Buffer : System.Address) return Boolean is
      Token : aliased System.Address := System.Null_Address;
      Needed : aliased C_DWord := 0;
      Ok : Boolean;
      Ignored : C_Int;
   begin
      Ok := Open_Process_Token (Get_Current_Process, Token_Query, Token'Access) /= 0
        and then Get_Token_Information
          (Token, Class, Buffer, C_DWord (Token_Buffer'Size / 8), Needed'Access) /= 0;
      if not Ok then
         Hostkit.Errors.Set_Errno_From_Last_Error;
      end if;
      if Token /= System.Null_Address then
         Ignored := Close_Handle (Token);
      end if;
      return Ok;
   end Read_Token;

   --  Whether the entry open as Handle is this process's own: owned by the
   --  token's user (User, its SID), or by the token's default owner -- which
   --  for an elevated administrator is BUILTIN\Administrators, the owner
   --  every entry such a process creates is given. Owner_Is_User tells which.
   --  False, with errno set, when it is neither or cannot be told.
   function Owned_By_Current_Token
     (Handle : System.Address; User : System.Address; Owner_Is_User : out Boolean) return Boolean
   is
      Owner, Descriptor : aliased System.Address := System.Null_Address;
      Security_Status : C_DWord;
      Buffer : aliased Token_Buffer := [others => 0];
      Token_Owner : System.Address
        with Import, Address => Buffer'Address;
      Ok : Boolean;
      Ignored_Address : System.Address;
   begin
      Owner_Is_User := False;
      Security_Status := Get_Security_Info
        (Handle, Se_File_Object, Owner_Security_Information,
         Owner'Address, System.Null_Address, System.Null_Address,
         System.Null_Address, Descriptor'Access);
      Ok := Security_Status = 0;
      if not Ok then
         Hostkit.Windows_Errors.Set_Errno_From (Interfaces.Unsigned_32 (Security_Status));
      else
         Owner_Is_User := Equal_Sid (Owner, User) /= 0;
         if not Owner_Is_User then
            Ok := Read_Token (Token_Owner_Class, Buffer'Address);
            if Ok and then Equal_Sid (Owner, Token_Owner) = 0 then
               Hostkit.Windows_Errors.Set_Errno_From (Error_Privilege_Not_Held);
               Ok := False;
            end if;
         end if;
      end if;
      if Descriptor /= System.Null_Address then
         Ignored_Address := Local_Free (Descriptor);
      end if;
      return Ok;
   exception
      when others =>
         if Descriptor /= System.Null_Address then
            Ignored_Address := Local_Free (Descriptor);
         end if;
         Hostkit.Windows_Errors.Set_Errno_From (Error_Invalid_Parameter);
         return False;
   end Owned_By_Current_Token;

   --  Hand the entry open as Handle to User (a SID) as its owner. Handle
   --  holds no WRITE_OWNER, so a second handle on the same entry asks for
   --  it -- which the private DACL, full access for OWNER RIGHTS, already
   --  grants the current owner. The errno of the call that failed.
   function Give_To (Handle : System.Address; User : System.Address) return Boolean is
      Writer : constant System.Address := Re_Open_File
        (Handle, Write_Owner, File_Share_All, File_Flag_Backup_Semantics + File_Flag_Open_Reparse_Point);
      Status : C_DWord;
      Ignored : C_Int;
   begin
      if Writer = Invalid_Handle_Value then
         return Refused;
      end if;
      Status := Set_Security_Info
        (Writer, Se_File_Object, Owner_Security_Information,
         User, System.Null_Address, System.Null_Address, System.Null_Address);
      Ignored := Close_Handle (Writer);
      Hostkit.Windows_Errors.Set_Errno_From (Interfaces.Unsigned_32 (Status));
      return Status = 0;
   end Give_To;

   --  Make the entry open as Handle its owner's alone, the owner being this
   --  process's user: given Private_Sddl's DACL, and, when it was owned by
   --  the token's default owner instead (an elevated process's
   --  Administrators), handed to that user, so that
   --  Hostkit.Metadata.Private_To_Current_User calls it private. On a volume
   --  that keeps no access control there is nothing to restrict and no owner
   --  to check: it is as private as that volume lets anything be, as a POSIX
   --  host's vfat mount gives every file the mode its mount options say.
   function Set_Private (Handle : System.Address) return Boolean is
      Text : aliased constant Wide_String := Wide_Text (Private_Sddl);
      Descriptor, Dacl : aliased System.Address := System.Null_Address;
      Present, Defaulted : aliased C_Int := 0;
      User_Buffer : aliased Token_Buffer := [others => 0];
      User : System.Address
        with Import, Address => User_Buffer'Address;
      Owner_Is_User : Boolean := False;
      Ok : Boolean;
      Ignored : System.Address;
   begin
      if not Keeps_Access_Control (Handle) then
         return True;
      end if;
      --  Each refusal says why through errno: Read_Token's and
      --  Owned_By_Current_Token's their own, the others the call's that
      --  failed.
      Ok := Read_Token (Token_User_Class, User_Buffer'Address)
        and then Owned_By_Current_Token (Handle, User, Owner_Is_User);
      if Ok then
         Ok := Convert_Sddl
           (Text'Address, Sddl_Revision_1, Descriptor'Access,
            System.Null_Address) /= 0;
         if not Ok then
            Hostkit.Errors.Set_Errno_From_Last_Error;
         end if;
      end if;
      if Ok then
         Ok := Get_Descriptor_Dacl
           (Descriptor, Present'Access, Dacl'Access, Defaulted'Access) /= 0;
         if not Ok then
            Hostkit.Errors.Set_Errno_From_Last_Error;
         elsif Present = 0 then
            Hostkit.Windows_Errors.Set_Errno_From (Error_Invalid_Parameter);
            Ok := False;
         end if;
      end if;
      if Ok then
         declare
            Status : constant C_DWord := Set_Security_Info
              (Handle, Se_File_Object,
               Dacl_Security_Information + Protected_Dacl_Information,
               System.Null_Address, System.Null_Address, Dacl,
               System.Null_Address);
         begin
            Ok := Status = 0;
            Hostkit.Windows_Errors.Set_Errno_From (Interfaces.Unsigned_32 (Status));
         end;
      end if;
      --  After the DACL, which is what grants the owner WRITE_OWNER.
      if Ok and then not Owner_Is_User then
         Ok := Give_To (Handle, User);
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
         Hostkit.Windows_Errors.Set_Errno_From (Error_Invalid_Parameter);
         return False;
   end Set_Private;

   --  A LocalAlloc'd security descriptor carrying Private_Sddl and, as its
   --  owner, this process's user ("O:<its SID>"): without one the new entry
   --  would be owned by the token's default owner, an elevated process's
   --  Administrators. For the caller to free; null, with errno set, when
   --  the host will not build it.
   function Private_Descriptor return System.Address is
      User_Buffer : aliased Token_Buffer := [others => 0];
      User : System.Address
        with Import, Address => User_Buffer'Address;
      Sid_Text : aliased System.Address := System.Null_Address;
      Descriptor : aliased System.Address := System.Null_Address;
      Ignored : System.Address;
   begin
      if not Read_Token (Token_User_Class, User_Buffer'Address) then
         return System.Null_Address;
      elsif Convert_Sid_To_String (User, Sid_Text'Access) = 0 then
         Hostkit.Errors.Set_Errno_From_Last_Error;
         return System.Null_Address;
      end if;
      declare
         --  A SID's text is at most 184 characters; the walk stops at its NUL.
         type Wide_Characters is array (1 .. 256) of Wide_Character
           with Convention => C;
         Characters : constant Wide_Characters
           with Import, Address => Sid_Text;
         Last : Natural := 0;
      begin
         while Last < Characters'Last and then Characters (Last + 1) /= Wide_Character'Val (0) loop
            Last := Last + 1;
         end loop;
         declare
            Text : aliased constant Wide_String :=
              "O:" & Wide_String (Characters (1 .. Last)) & Wide_Text (Private_Sddl);
         begin
            Ignored := Local_Free (Sid_Text);
            if Convert_Sddl
              (Text'Address, Sddl_Revision_1, Descriptor'Access,
               System.Null_Address) = 0
            then
               Hostkit.Errors.Set_Errno_From_Last_Error;
               return System.Null_Address;
            end if;
         end;
      end;
      return Descriptor;
   exception
      when others =>
         Hostkit.Windows_Errors.Set_Errno_From (Error_Invalid_Parameter);
         return System.Null_Address;
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
      if not Ok then
         Hostkit.Errors.Set_Errno_From_Last_Error;
      end if;
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
         Handle : constant System.Address := Create_File
           (Name'Address, Read_Control + Write_Dac + File_Read_Attributes,
            File_Share_All, System.Null_Address, Open_Existing,
            File_Flag_Backup_Semantics + File_Flag_Open_Reparse_Point,
            System.Null_Address);
         Info : aliased By_Handle_File_Information;
         Opened : constant Boolean := Handle /= Invalid_Handle_Value or else Refused;
         Read : constant Boolean := Opened
           and then (Get_File_Information (Handle, Info'Access) /= 0 or else Refused);
         --  A file, or a link or junction where a folder was asked for, is
         --  no folder this makes private.
         Folder : constant Boolean := Read
           and then (Info.Attributes and File_Attribute_Directory) /= 0
           and then (Info.Attributes and File_Attribute_Reparse_Point) = 0;
         Ok : Boolean;
         Ignored : C_Int;
      begin
         if Read and then not Folder then
            Hostkit.Windows_Errors.Set_Errno_From (Error_Directory);
         end if;
         Ok := Folder and then Set_Private (Handle);
         if Handle /= Invalid_Handle_Value then
            Ignored := Close_Handle (Handle);
         end if;
         return Ok;
      end;
   exception
      when others =>
         return False;
   end Ensure_Directory;

   function Restrict_Open_File (Descriptor : Integer) return Boolean is
      Original : constant System.Address := Get_Osfhandle (C_Int (Descriptor));
      Count : C_DWord;
   begin
      --  _get_osfhandle has set errno (EBADF) itself.
      if Original = Invalid_Handle_Value then
         return False;
      end if;
      Count := Get_Final_Path_Name
        (Original, System.Null_Address, 0, 0);
      if Count = 0 then
         return Refused;
      end if;
      declare
         Name : aliased Wide_String (1 .. Natural (Count) + 1) :=
           [others => Wide_Character'Val (0)];
         Actual : constant C_DWord := Get_Final_Path_Name
           (Original, Name'Address, C_DWord (Name'Length), 0);
         Reopened : System.Address := Invalid_Handle_Value;
         Ok : Boolean := Actual > 0 and then Actual < C_DWord (Name'Length);
         Ignored : C_Int;
      begin
         --  Each refusal says why through errno: the call's that failed,
         --  or, for a name that now leads elsewhere, ENOENT.
         if not Ok then
            if Actual = 0 then
               Hostkit.Errors.Set_Errno_From_Last_Error;
            else
               --  The name grew longer between the two asks.
               Hostkit.Windows_Errors.Set_Errno_From (Error_Invalid_Parameter);
            end if;
         else
            Reopened := Create_File
              (Name'Address, Read_Control + Write_Dac + File_Read_Attributes,
               File_Share_All, System.Null_Address, Open_Existing,
               File_Flag_Open_Reparse_Point, System.Null_Address);
            if Reopened = Invalid_Handle_Value then
               Ok := Refused;
            elsif not Same_File (Original, Reopened) then
               Hostkit.Windows_Errors.Set_Errno_From (Error_File_Not_Found);
               Ok := False;
            else
               Ok := Set_Private (Reopened);
            end if;
         end if;
         if Reopened /= Invalid_Handle_Value then
            Ignored := Close_Handle (Reopened);
         end if;
         return Ok;
      end;
   exception
      when others =>
         Hostkit.Windows_Errors.Set_Errno_From (Error_Invalid_Parameter);
         return False;
   end Restrict_Open_File;

end Hostkit.Private_Paths;
