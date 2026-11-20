with Hostkit.Errors;
with Hostkit.Windows_Errors;

package body Hostkit.Win32 is
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned_long;
   use type System.Address;

   function Is_Held_Link (Object : HANDLE; Attributes : DWORD; Error : out DWORD) return Boolean is
      Tag_Info : aliased Attribute_Tag_Info;
   begin
      Error := 0;
      if (Attributes and File_Attribute_Reparse_Point) = 0 then
         return False;
      elsif Get_File_Information_Ex
              (Object, File_Attribute_Tag_Info_Class, Tag_Info'Address, DWORD (Attribute_Tag_Info'Size / 8)) = 0
      then
         Error := Get_Last_Error;
         return True;
      elsif Is_Link_Tag (Tag_Info.Reparse_Tag) then
         Error := Error_Stopped_On_Symlink;
         return True;
      end if;
      return False;
   end Is_Held_Link;

   function Keeps_Access_Control (Object : HANDLE) return Boolean is
      File_Persistent_Acls : constant DWORD := 16#0000_0008#;
      Serial, Max_Component, Flags : aliased DWORD := 0;
   begin
      return Get_Volume_Information_By_Handle
          (Object, System.Null_Address, 0, Serial'Access, Max_Component'Access, Flags'Access,
           System.Null_Address, 0) = 0
        or else (Flags and File_Persistent_Acls) /= 0;
   end Keeps_Access_Control;

   function Read_Token (Class : Interfaces.C.int; Buffer : aliased in out Token_Buffer) return Boolean is
      Token   : aliased HANDLE := System.Null_Address;
      Needed  : aliased DWORD := 0;
      Ok      : Boolean;
      Ignored : BOOL;
   begin
      Ok := Open_Process_Token (Get_Current_Process, Token_Query, Token'Access) /= 0
        and then Get_Token_Information
          (Token, Class, Buffer'Address, DWORD (Token_Buffer'Size / 8), Needed'Access) /= 0;
      --  The reason goes into errno before CloseHandle can overwrite it.
      if not Ok then
         Hostkit.Errors.Set_Errno_From_Last_Error;
      end if;
      if Token /= System.Null_Address then
         Ignored := Close_Handle (Token);
      end if;
      return Ok;
   end Read_Token;

   function Token_Sid (Buffer : aliased Token_Buffer) return System.Address is
      --  TOKEN_USER and TOKEN_OWNER both begin with the SID's address.
      Sid : constant System.Address
        with Import, Address => Buffer'Address;
   begin
      return Sid;
   end Token_Sid;

   function Current_User_Sid_Text return Wide_String is
      function Convert_Sid_To_String (Sid : System.Address; Text : access System.Address) return BOOL
        with Import, Convention => Stdcall, External_Name => "ConvertSidToStringSidW";
      --  ERROR_INVALID_PARAMETER, EINVAL through Set_Errno_From.
      Error_Invalid_Parameter : constant Interfaces.Unsigned_32 := 87;
      User_Buffer : aliased Token_Buffer := [others => 0];
      Text        : aliased System.Address := System.Null_Address;
      Ignored     : System.Address;
   begin
      if not Read_Token (Token_User_Class, User_Buffer) then
         return "";
      elsif Convert_Sid_To_String (Token_Sid (User_Buffer), Text'Access) = 0 then
         Hostkit.Errors.Set_Errno_From_Last_Error;
         return "";
      end if;
      declare
         --  A SID's text is at most 184 characters; the walk stops at its NUL.
         type Wide_Characters is array (1 .. 256) of Wide_Character
           with Convention => C;
         Characters : constant Wide_Characters
           with Import, Address => Text;
         Last : Natural := 0;
      begin
         while Last < Characters'Last and then Characters (Last + 1) /= Wide_Character'Val (0) loop
            Last := Last + 1;
         end loop;
         declare
            Result : constant Wide_String := Wide_String (Characters (1 .. Last));
         begin
            Ignored := Local_Free (Text);
            Text := System.Null_Address;
            return Result;
         end;
      end;
   exception
      when others =>
         if Text /= System.Null_Address then
            Ignored := Local_Free (Text);
         end if;
         Hostkit.Windows_Errors.Set_Errno_From (Error_Invalid_Parameter);
         return "";
   end Current_User_Sid_Text;

end Hostkit.Win32;
