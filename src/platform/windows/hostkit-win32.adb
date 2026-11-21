with Ada.Unchecked_Deallocation;

with Hostkit.Errors;
with Hostkit.Windows_Errors;

package body Hostkit.Win32 is
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned_long;
   use type Interfaces.C.unsigned_long_long;
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

   subtype C_Size_T is Interfaces.C.unsigned_long_long;

   --  PROC_THREAD_ATTRIBUTE_HANDLE_LIST and PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE.
   --  The numbers are assembled from each attribute's index and flags by a
   --  macro in the Windows headers; written out, as there is no macro to
   --  expand, and they are a contract with the OS either way.
   Attribute_Handle_List    : constant C_Size_T := 16#0002_0002#;
   Attribute_Pseudo_Console : constant C_Size_T := 16#0002_0016#;

   function Initialize_Attribute_List
     (List  : System.Address;
      Count : DWORD;
      Flags : DWORD;
      Size  : access C_Size_T) return BOOL
     with Import => True, Convention => Stdcall, External_Name => "InitializeProcThreadAttributeList";

   function Update_Attribute
     (List      : System.Address;
      Flags     : DWORD;
      Attribute : C_Size_T;
      Value     : System.Address;
      Size      : C_Size_T;
      Previous  : System.Address;
      Returned  : System.Address) return BOOL
     with Import => True, Convention => Stdcall, External_Name => "UpdateProcThreadAttribute";

   procedure Delete_Attribute_List (List : System.Address)
     with Import => True, Convention => Stdcall, External_Name => "DeleteProcThreadAttributeList";

   procedure Free is new Ada.Unchecked_Deallocation (Room_Array, Room_Access);

   function Own_Standard_Handles return Handle_List is
     [Get_Std_Handle (16#FFFF_FFF6#),   --  STD_INPUT_HANDLE, (DWORD) -10
      Get_Std_Handle (16#FFFF_FFF5#),   --  STD_OUTPUT_HANDLE, -11
      Get_Std_Handle (16#FFFF_FFF4#)];  --  STD_ERROR_HANDLE, -12

   overriding procedure Finalize (Item : in out Child_Attributes) is
   begin
      if Item.Ready then
         Delete_Attribute_List (Item.Room.all'Address);
         Item.Ready := False;
      end if;
      Free (Item.Room);
      Item.Handles := [others => System.Null_Address];
      Item.Count := 0;
   end Finalize;

   function Prepare
     (Item           : in out Child_Attributes;
      Inherited      : Handle_List;
      Pseudo_Console : HANDLE := System.Null_Address) return Boolean
   is
      Needed : aliased C_Size_T := 0;
      Count  : DWORD;
      Sizing : BOOL;
      pragma Unreferenced (Sizing);
   begin
      Finalize (Item);

      for Candidate of Inherited loop
         declare
            Flags : aliased DWORD := 0;
         begin
            if Candidate /= System.Null_Address
              and then Candidate /= Invalid_Handle_Value
              and then Item.Count < Item.Handles'Length
              and then (for all Index in 1 .. Item.Count => Item.Handles (Index) /= Candidate)
              and then Get_Handle_Information (Candidate, Flags'Access) /= 0
              and then (Flags and Handle_Flag_Inherit) /= 0
            then
               Item.Count := Item.Count + 1;
               Item.Handles (Item.Count) := Candidate;
            end if;
         end;
      end loop;

      --  Room for one attribute at the least, so the list is a valid one even
      --  when it carries nothing.
      Count := DWORD'Max
        (1, (if Item.Count > 0 then 1 else 0) + (if Pseudo_Console /= System.Null_Address then 1 else 0));

      --  Always fails, and is documented to: the first call is how the host
      --  says how much room the list needs.
      Sizing := Initialize_Attribute_List (System.Null_Address, Count, 0, Needed'Access);
      if Needed = 0 then
         return False;
      end if;

      --  An array of addresses rather than of bytes, because the host writes
      --  pointers into it: a byte array is aligned to one, and a misaligned
      --  attribute list is a fault on some hosts and a silent corruption on
      --  the rest.
      Item.Room := new Room_Array'(1 .. (Natural (Needed) + 7) / 8 => System.Null_Address);
      if Initialize_Attribute_List (Item.Room.all'Address, Count, 0, Needed'Access) = 0 then
         return False;
      end if;
      Item.Ready := True;

      if Item.Count > 0
        and then Update_Attribute
                   (Item.Room.all'Address, 0, Attribute_Handle_List, Item.Handles'Address,
                    C_Size_T (Item.Count * (System.Address'Size / 8)),
                    System.Null_Address, System.Null_Address) = 0
      then
         return False;
      end if;

      --  The console handle itself is the value, not a pointer to it. Most
      --  attributes take the address of the thing they are about; this one
      --  takes the handle, and passing its address instead is a call that
      --  succeeds and attaches the child to nothing.
      if Pseudo_Console /= System.Null_Address
        and then Update_Attribute
                   (Item.Room.all'Address, 0, Attribute_Pseudo_Console, Pseudo_Console,
                    System.Address'Size / 8, System.Null_Address, System.Null_Address) = 0
      then
         return False;
      end if;

      return True;
   end Prepare;

   function Attribute_List (Item : Child_Attributes) return System.Address is
     (if Item.Ready then Item.Room.all'Address else System.Null_Address);

   function Inherit_Handles (Item : Child_Attributes) return BOOL is
     (if Item.Count > 0 then 1 else 0);

end Hostkit.Win32;
