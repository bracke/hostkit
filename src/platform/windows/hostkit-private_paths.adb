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
   Owner_Security_Information  : constant C_DWord := 16#0000_0001#;
   Dacl_Security_Information   : constant C_DWord := 16#0000_0004#;
   Protected_Dacl_Information : constant C_DWord := 16#8000_0000#;
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

   --  Whether the volume Handle is on keeps access control lists: NTFS and
   --  ReFS do; FAT and exFAT -- a USB stick, a memory card -- keep none, and
   --  every entry there is open to whoever can reach the volume. When the
   --  volume will not say, it is taken to keep them.
   function Keeps_Access_Control (Handle : System.Address) return Boolean is
      File_Persistent_Acls : constant C_DWord := 16#0000_0008#;
      Serial, Max_Component, Flags : aliased C_DWord := 0;
   begin
      return Get_Volume_Information_By_Handle
          (Handle, System.Null_Address, 0, Serial'Access, Max_Component'Access, Flags'Access,
           System.Null_Address, 0) = 0
        or else (Flags and File_Persistent_Acls) /= 0;
   end Keeps_Access_Control;

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

   --  Whether the entry open as Handle is owned by this process's token
   --  owner. False, with errno set, when it is not or cannot be told.
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
      Ok := Security_Status = 0;
      if not Ok then
         Hostkit.Windows_Errors.Set_Errno_From (Interfaces.Unsigned_32 (Security_Status));
      else
         Ok := Open_Process_Token (Get_Current_Process, Token_Query, Token'Access) /= 0
           and then Get_Token_Information
             (Token, Token_Owner_Class, Buffer'Address,
              C_DWord (Buffer'Length), Needed'Access) /= 0;
         if not Ok then
            Hostkit.Errors.Set_Errno_From_Last_Error;
         elsif Equal_Sid (Owner, Token_Owner) = 0 then
            Hostkit.Windows_Errors.Set_Errno_From (Error_Privilege_Not_Held);
            Ok := False;
         end if;
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
         Hostkit.Windows_Errors.Set_Errno_From (Error_Invalid_Parameter);
         return False;
   end Owned_By_Current_Token;

   --  Make the entry open as Handle its owner's alone. On a volume that
   --  keeps no access control there is nothing to restrict and no owner to
   --  check: it is as private as that volume lets anything be, as a POSIX
   --  host's vfat mount gives every file the mode its mount options say.
   function Set_Private (Handle : System.Address) return Boolean is
      Text : aliased constant Wide_String := Wide_Text (Private_Sddl);
      Descriptor, Dacl : aliased System.Address := System.Null_Address;
      Present, Defaulted : aliased C_Int := 0;
      Ok : Boolean;
      Ignored : System.Address;
   begin
      if not Keeps_Access_Control (Handle) then
         return True;
      end if;
      --  Each refusal says why through errno: Owned_By_Current_Token's
      --  its own, the others the call's that failed.
      Ok := Owned_By_Current_Token (Handle);
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

   --  A LocalAlloc'd security descriptor carrying Private_Sddl, for the
   --  caller to free; null, with errno set, when the host will not build it.
   function Private_Descriptor return System.Address is
      Text : aliased constant Wide_String := Wide_Text (Private_Sddl);
      Descriptor : aliased System.Address := System.Null_Address;
   begin
      if Convert_Sddl
        (Text'Address, Sddl_Revision_1, Descriptor'Access,
         System.Null_Address) = 0
      then
         Hostkit.Errors.Set_Errno_From_Last_Error;
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
