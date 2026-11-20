separate (Hostkit.Metadata)
function Private_To_Current_User (Path : String) return Boolean is
   --  TOKEN_INFORMATION_CLASS: TokenUser and TokenOwner.
   Token_User_Class  : constant C_Int := 1;
   Token_Owner_Class : constant C_Int := 4;
   --  WELL_KNOWN_SID_TYPE: WinCreatorOwnerRightsSid, OWNER RIGHTS (S-1-3-4),
   --  the trustee of Hostkit.Private_Paths' one ACE, "D:P(A;OICI;FA;;;OW)".
   Win_Creator_Owner_Rights_Sid : constant C_Int := 71;
   --  Where an ACE's SID starts: past its header and its access mask.
   Ace_Sid_Offset : constant := 8;

   --  TOKEN_USER and TOKEN_OWNER, each led by its SID's address, with the
   --  SID after it; eight-byte words, so that address is aligned.
   type Token_Buffer is array (0 .. 255) of Interfaces.Unsigned_64
     with Convention => C;
   User_Buffer  : aliased Token_Buffer := [others => 0];
   Owner_Buffer : aliased Token_Buffer := [others => 0];
   User_Sid : System.Address
     with Import, Address => User_Buffer'Address;
   Default_Owner_Sid : System.Address
     with Import, Address => Owner_Buffer'Address;

   Owner_Rights      : aliased Sid_Buffer := [others => Interfaces.C.nul];
   Owner_Rights_Size : aliased C_DWord := C_DWord (Sid_Buffer'Length);
   Name       : aliased Wide_String := Wide (Path);
   Handle     : System.Address := Invalid_Handle_Value;
   Token      : aliased System.Address := System.Null_Address;
   Owner      : aliased System.Address := System.Null_Address;
   Dacl       : aliased System.Address := System.Null_Address;
   Descriptor : aliased System.Address := System.Null_Address;
   Info       : aliased By_Handle_File_Information;
   Needed     : aliased C_DWord := 0;
   Result     : Boolean := False;
   Ignored_Int     : C_Int;
   Ignored_Address : System.Address;

   --  Whether Sid is this process's user or its default owner.
   function Names_Self (Sid : System.Address) return Boolean is
     (Equal_Sid (Sid, User_Sid) /= 0 or else Equal_Sid (Sid, Default_Owner_Sid) /= 0);

   --  Whether every access-allowed ACE of the DACL names this process's
   --  user, its default owner or OWNER RIGHTS, and every other ACE is a
   --  deny.
   function Dacl_Private return Boolean is
      Header : constant Acl_Header
        with Import, Address => Dacl;
   begin
      for Index in 0 .. Natural (Header.Count) - 1 loop
         declare
            Ace  : constant System.Address := Ace_At (Dacl, Index);
            Head : constant Ace_Header
              with Import, Address => Ace;
            Sid  : constant System.Address := System.Storage_Elements."+" (Ace, Ace_Sid_Offset);
         begin
            if Head.Kind = Access_Allowed_Ace then
               if not Names_Self (Sid) and then Equal_Sid (Sid, Owner_Rights (1)'Address) = 0 then
                  return False;
               end if;
            elsif Head.Kind /= Access_Denied_Ace then
               return False;
            end if;
         end;
      end loop;
      return True;
   end Dacl_Private;

   --  Let go of whatever was opened or handed out.
   procedure Release is
   begin
      if Token /= System.Null_Address then
         Ignored_Int := Close_Handle (Token);
         Token := System.Null_Address;
      end if;
      if Descriptor /= System.Null_Address then
         Ignored_Address := Local_Free (Descriptor);
         Descriptor := System.Null_Address;
      end if;
      if Handle /= Invalid_Handle_Value then
         Ignored_Int := Close_Handle (Handle);
         Handle := Invalid_Handle_Value;
      end if;
   end Release;
begin
   --  The entry itself, never what a link names: a link answers False. A
   --  reparse point that is no link (a cloud placeholder) is the file it
   --  shows as. A volume without ACLs (FAT, exFAT) hands back no owner and
   --  no DACL, and answers False.
   Handle := Create_File
     (Name'Address, Read_Control + File_Read_Attributes,
      File_Share_Read + File_Share_Write + File_Share_Delete, System.Null_Address, Open_Existing,
      File_Flag_Backup_Semantics + File_Flag_Open_Reparse_Point, System.Null_Address);
   if Handle /= Invalid_Handle_Value
     and then Get_File_Information (Handle, Info'Access) /= 0
     and then ((Info.Attributes and File_Attribute_Reparse_Point) = 0 or else not Hostkit.Fs.Is_Link (Path))
     and then Get_Security_Info
       (Handle, Se_File_Object, Owner_Information + Dacl_Information,
        Owner'Address, System.Null_Address, Dacl'Address, System.Null_Address,
        Descriptor'Access) = Success
     and then Owner /= System.Null_Address
     and then Dacl /= System.Null_Address
     and then Open_Process_Token (Get_Current_Process, Token_Query, Token'Access) /= 0
     and then Get_Token_Information
       (Token, Token_User_Class, User_Buffer'Address, C_DWord (Token_Buffer'Size / 8), Needed'Access) /= 0
     and then Get_Token_Information
       (Token, Token_Owner_Class, Owner_Buffer'Address, C_DWord (Token_Buffer'Size / 8), Needed'Access) /= 0
     and then Create_Well_Known_Sid
       (Win_Creator_Owner_Rights_Sid, System.Null_Address, Owner_Rights (1)'Address, Owner_Rights_Size'Access) /= 0
     and then Names_Self (Owner)
   then
      Result := Dacl_Private;
   end if;
   Release;
   return Result;
exception
   when others =>
      Release;
      return False;
end Private_To_Current_User;
