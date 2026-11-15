with Ada.Containers.Indefinite_Vectors;
with Ada.Containers.Vectors;
with Ada.Strings.Wide_Unbounded;

--  The ownership or permission update of the entry Path names, held open
--  throughout: opened, checked to be the entry asked about, its security
--  read, then changed by one of the two steps below.
separate (Hostkit.Metadata)
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
   Relative_Path  : String := "") return Metadata_Update_Result
is
   --  The SID of the account Name, into Sid, when its number is
   --  Expected_Id; False, with errno set, when there is none.
   function Resolve_Account
     (Name        : String;
      Expected_Id : Identity_Field;
      Sid         : out Sid_Buffer) return Boolean
   is
   begin
      Sid := [others => Interfaces.C.nul];
      if Name = "" or else Expected_Id > Identity_Field (Natural'Last) then
         Hostkit.Windows_Errors.Set_Errno_From (Error_Invalid_Parameter);
         return False;
      elsif not Account_Sid (Name, Sid, Say_Why => True) then
         return False;
      end if;
      if Identity_Field (Identity_Of (Sid (1)'Address)) /= Expected_Id then
         --  Name is another account than the number says.
         Hostkit.Windows_Errors.Set_Errno_From (Error_Invalid_Parameter);
         return False;
      end if;
      return True;
   exception
      when others =>
         Hostkit.Windows_Errors.Set_Errno_From (Error_Invalid_Parameter);
         return False;
   end Resolve_Account;

   Access_Mode : constant C_DWord := Read_Control or
     (if Kind = Update_Ownership then Write_Owner else Write_Dac);
   File       : System.Address := Invalid_Handle_Value;
   Info       : aliased By_Handle_File_Information;
   Answer     : Metadata_Update_Result;
   Owner      : aliased System.Address := System.Null_Address;
   Primary_Group : aliased System.Address := System.Null_Address;
   Dacl       : aliased System.Address := System.Null_Address;
   Sacl       : aliased System.Address := System.Null_Address;
   Descriptor : aliased System.Address := System.Null_Address;

   package Part_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Positive, Element_Type => String);
   package Handle_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => System.Address);
   Parents : Handle_Vectors.Vector;

   procedure Close_Parents is
      Ignored : Interfaces.C.int;
   begin
      for Parent of Parents loop
         Ignored := Close_Handle (Parent);
      end loop;
      Parents.Clear;
   end Close_Parents;

   procedure Remember_Parent (Parent : System.Address) is
      Ignored : Interfaces.C.int;
   begin
      Parents.Append (Parent);
   exception
      when others =>
         Ignored := Close_Handle (Parent);
         raise;
   end Remember_Parent;

   function Open_Beneath (Desired_Access : C_DWord) return System.Address is
      use Ada.Strings.Wide_Unbounded;
      Parts : Part_Vectors.Vector;
      Start : Positive := Relative_Path'First;
      File_List_Directory : constant C_DWord := 1;
      Share_No_Delete : constant C_DWord := 3;
      Backup_Semantics : constant C_DWord := 16#0200_0000#;
      Open_Reparse_Point : constant C_DWord := 16#0020_0000#;
      Root_Wide : constant Wide_String := Wide
        (if Beneath_Root = "" then "." else Beneath_Root);
      Root_Terminated : aliased constant Wide_String := Root_Wide;
      Root_Handle : System.Address;
      Root_Info   : aliased By_Handle_File_Information;

      procedure Refuse
        (Error : C_DWord;
         Child : System.Address := Invalid_Handle_Value)
      is
         Ignored : Interfaces.C.int;
      begin
         if Child /= Invalid_Handle_Value then
            Ignored := Close_Handle (Child);
         end if;
         Close_Parents;
         Hostkit.Windows_Errors.Set_Errno_From
           (Interfaces.Unsigned_32 (Error));
      end Refuse;
   begin
      if (for some Char of Beneath_Root => Char = ASCII.NUL) then
         Hostkit.Windows_Errors.Set_Errno_From (Error_Invalid_Parameter);
         return Invalid_Handle_Value;
      elsif Relative_Path'Length > 0
        and then Relative_Path (Relative_Path'First) in '/' | '\'
      then
         Hostkit.Windows_Errors.Set_Errno_From (Error_Invalid_Parameter);
         return Invalid_Handle_Value;
      end if;
      for Index in Relative_Path'First .. Relative_Path'Last + 1 loop
         if Index > Relative_Path'Last
           or else Relative_Path (Index) in '/' | '\'
         then
            declare
               Part : constant String := Relative_Path (Start .. Index - 1);
            begin
               if Part = ".."
                 or else (for some Char of Part => Char in ':' | ASCII.NUL)
               then
                  Hostkit.Windows_Errors.Set_Errno_From
                    (Error_Invalid_Parameter);
                  return Invalid_Handle_Value;
               elsif Part /= "" and then Part /= "." then
                  Parts.Append (Part);
               end if;
            end;
            Start := Index + 1;
         end if;
      end loop;
      Root_Handle := Create_File
        (Root_Terminated'Address,
         File_Read_Attributes
           + (if Parts.Is_Empty then Desired_Access
              else File_List_Directory),
         Share_No_Delete, System.Null_Address, Open_Existing,
         Backup_Semantics + Open_Reparse_Point,
         System.Null_Address);
      if Root_Handle = Invalid_Handle_Value then
         Hostkit.Errors.Set_Errno_From_Last_Error;
         return Invalid_Handle_Value;
      elsif Parts.Is_Empty then
         return Root_Handle;
      elsif Get_File_Information (Root_Handle, Root_Info'Access) = 0 then
         declare
            Error : constant C_DWord := Get_Last_Error;
         begin
            Remember_Parent (Root_Handle);
            Refuse (Error);
         end;
         return Invalid_Handle_Value;
      elsif (Root_Info.Attributes and File_Attribute_Reparse_Point) /= 0 then
         Remember_Parent (Root_Handle);
         Refuse (Error_Stopped_On_Symlink);
         return Invalid_Handle_Value;
      end if;
      Remember_Parent (Root_Handle);
      declare
         Length : constant C_DWord := Get_Final_Path_Name
           (Root_Handle, System.Null_Address, 0, 0);
      begin
         if Length = 0 then
            Refuse (Get_Last_Error);
            return Invalid_Handle_Value;
         end if;
         declare
            Buffer : aliased Wide_String (1 .. Natural (Length) + 1);
            Written : constant C_DWord := Get_Final_Path_Name
              (Root_Handle, Buffer'Address, Length + 1, 0);
            Current : Unbounded_Wide_String;
            Handle : System.Address;
            Info : aliased By_Handle_File_Information;
         begin
            if Written = 0 or else Written > Length then
               Refuse (Get_Last_Error);
               return Invalid_Handle_Value;
            end if;
            Current := To_Unbounded_Wide_String
              (Buffer (1 .. Natural (Written)));
            for Index in Parts.First_Index .. Parts.Last_Index loop
               declare
                  Last : constant Boolean := Index = Parts.Last_Index;
                  Name : aliased constant Wide_String :=
                    To_Wide_String (Current) & "\"
                    & Hostkit.Windows_Paths.From_UTF_8 (Parts (Index))
                    & Wide_Character'Val (0);
               begin
                  Append
                    (Current, "\"
                     & Hostkit.Windows_Paths.From_UTF_8 (Parts (Index)));
                  Handle := Create_File
                    (Name'Address,
                     File_Read_Attributes
                       + (if Last then Desired_Access
                          else File_List_Directory),
                     Share_No_Delete, System.Null_Address, Open_Existing,
                     Backup_Semantics + Open_Reparse_Point,
                     System.Null_Address);
                  if Handle = Invalid_Handle_Value then
                     Refuse (Get_Last_Error);
                     return Invalid_Handle_Value;
                  elsif Get_File_Information (Handle, Info'Access) = 0 then
                     Refuse (Get_Last_Error, Handle);
                     return Invalid_Handle_Value;
                  elsif (Info.Attributes and File_Attribute_Reparse_Point) /= 0
                  then
                     Refuse (Error_Stopped_On_Symlink, Handle);
                     return Invalid_Handle_Value;
                  elsif Last then
                     return Handle;
                  end if;
                  Remember_Parent (Handle);
               end;
            end loop;
         end;
      end;
      Close_Parents;
      Hostkit.Windows_Errors.Set_Errno_From (Error_Invalid_Parameter);
      return Invalid_Handle_Value;
   exception
      when others =>
         Close_Parents;
         Hostkit.Windows_Errors.Set_Errno_From (Error_Invalid_Parameter);
         return Invalid_Handle_Value;
   end Open_Beneath;

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
      Free_Local (Descriptor);
      Close_Entry (File);
      Close_Parents;
   end Clean;

   --  Whether the entry open as File is refused: one whose identity cannot
   --  be read, a link, or -- when Check_Expected -- another entry than the
   --  one asked about. Answer.Identity is the identity read; a refusal says
   --  why through errno, as the open's does.
   function Held_Entry_Refused return Boolean is
      Error      : Interfaces.Unsigned_32;
      Link_Error : C_DWord;
      Refused    : Boolean := True;
   begin
      Answer.Identity := Identity_From_Handle (File, Info'Access, Error);
      if not Answer.Identity.Available then
         null;
      elsif Is_Held_Link (File, Info.Attributes, Link_Error) then
         --  ERROR_STOPPED_ON_SYMLINK, ELOOP as POSIX's O_NOFOLLOW gives.
         Error := Interfaces.Unsigned_32 (Link_Error);
      elsif Check_Expected and then Answer.Identity /= Expected then
         --  Path names another entry now than the one asked about.
         Error := Error_File_Not_Found;
      else
         Refused := False;
      end if;
      if Refused then
         Hostkit.Windows_Errors.Set_Errno_From (Error);
      end if;
      return Refused;
   end Held_Entry_Refused;

   --  Owner, Primary_Group, Dacl and Descriptor read from the entry open as
   --  File; False, with errno set, when the host would not say.
   function Security_Read return Boolean is
      Status : constant C_DWord :=
        Get_Security_Info
          (File, Se_File_Object,
           Owner_Information or Group_Information or Dacl_Information,
           Owner'Address, Primary_Group'Address, Dacl'Address, Sacl'Address,
           Descriptor'Access);
   begin
      if Status /= Success then
         Hostkit.Windows_Errors.Set_Errno_From (Interfaces.Unsigned_32 (Status));
         return False;
      end if;
      return True;
   end Security_Read;

   --  The ownership update: the previous owner and group into Answer, then
   --  Value and Group set as owner and primary group, each by the account
   --  its name resolves to, where it changes. Keep_Id_Field keeps that one
   --  as it is, as an id equal to the previous one does.
   procedure Change_Ownership is
      Keep_Owner : constant Boolean := Value = Keep_Id_Field;
      Keep_Group : constant Boolean := Group = Keep_Id_Field;
   begin
      Answer.Previous := Identity_Field (Identity_Of (Owner));
      Answer.Previous_Group := Identity_Field (Identity_Of (Primary_Group));
      Remember (Owner, Natural (Answer.Previous));
      Remember (Primary_Group, Natural (Answer.Previous_Group));
      if Answer.Previous > Max_Previous
        or else Answer.Previous_Group > Max_Previous
        or else (Value > Identity_Field (Natural'Last) and then not Keep_Owner)
        or else (Group > Identity_Field (Natural'Last) and then not Keep_Group)
      then
         --  An id no SID here was given, or a previous one the caller
         --  could not keep to undo with.
         Hostkit.Windows_Errors.Set_Errno_From (Error_Invalid_Parameter);
      else
         declare
            Owner_Sid : aliased Sid_Buffer := [others => Interfaces.C.nul];
            Group_Sid : aliased Sid_Buffer := [others => Interfaces.C.nul];
            Borrow_Owner : constant Boolean := Keep_Owner or else Answer.Previous = Value;
            Borrow_Group : constant Boolean := Keep_Group or else Answer.Previous_Group = Group;
            Have_Owner : constant Boolean := Borrow_Owner or else
              Resolve_Account (Owner_Name, Value, Owner_Sid);
            Have_Group : constant Boolean := Borrow_Group or else
              Resolve_Account (Group_Name, Group, Group_Sid);
            New_Owner : constant System.Address :=
              (if Borrow_Owner then Owner else Owner_Sid (1)'Address);
            New_Group : constant System.Address :=
              (if Borrow_Group then Primary_Group else Group_Sid (1)'Address);
         begin
            if Borrow_Owner and then Borrow_Group then
               Answer.Success := True;
            elsif Have_Owner and then Have_Group then
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
   end Change_Ownership;

   --  The permission update: the edit Set_Permissions makes, on the held
   --  entry; or, given an access record an earlier update reported, that
   --  record exactly. The previous mode and access record into Answer.
   procedure Change_Permissions is
      Everyone      : aliased Sid_Buffer := [others => Interfaces.C.nul];
      Everyone_Size : aliased C_DWord := C_DWord (Sid_Buffer'Length);
      Control       : aliased Interfaces.C.unsigned_short := 0;
      Revision      : aliased C_DWord := 0;
      Opened_Path   : constant String :=
        (if Beneath_Root = "" then Path
         elsif Relative_Path = "" then Beneath_Root
         else Relative_Path);
      Runnable      : constant Boolean :=
        Runs_On_Windows (Opened_Path)
        or else (Info.Attributes and File_Attribute_Directory) /= 0;
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
         elsif Value <= 8#7777# then
            Answer.Success :=
              Apply_Permission_Edit
                (System.Null_Address, File, Dacl, Owner, Primary_Group, Everyone (1)'Address, Control,
                 Old_Mode, Natural (Value), Runnable);
         else
            --  No mode: more bits than set-id, sticky and rwx.
            Hostkit.Windows_Errors.Set_Errno_From (Error_Invalid_Parameter);
         end if;
         if Answer.Success then
            Answer.Applied_Access := To_Unbounded_String (Dacl_Text_Of (File));
         end if;
      else
         Hostkit.Errors.Set_Errno_From_Last_Error;
      end if;
   end Change_Permissions;
begin
   File :=
     (if Beneath_Root = "" then Open_Entry (Path, Access_Mode)
      else Open_Beneath (Access_Mode));
   if File = Invalid_Handle_Value then
      --  An ownership left as it is needs no WRITE_OWNER, which an
      --  entry's owner need not hold: look, and write only what changes.
      if Kind = Update_Ownership then
         File :=
           (if Beneath_Root = "" then Open_Entry (Path, Read_Control)
            else Open_Beneath (Read_Control));
      end if;
      if File = Invalid_Handle_Value then
         if Beneath_Root = "" then
            Hostkit.Errors.Set_Errno_From_Last_Error;
         end if;
         return Answer;
      end if;
   end if;
   if Held_Entry_Refused or else not Security_Read then
      Clean;
      return Answer;
   end if;
   if Kind = Update_Ownership then
      Change_Ownership;
   else
      Change_Permissions;
   end if;
   Clean;
   return Answer;
exception
   when others =>
      Clean;
      return (others => <>);
end Update_Entry_Metadata;
