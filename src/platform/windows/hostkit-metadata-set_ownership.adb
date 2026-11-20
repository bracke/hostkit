separate (Hostkit.Metadata)
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
   --  Keep_Id for both: nothing to write, as long as there is a file.
   --  Keep_Id for one is not Natural, so it names no SID and that half
   --  is left out of the write below.
   if User_Id = Keep_Id and then Group_Id = Keep_Id then
      declare
         Ignored_User, Ignored_Group : Account_Id;
         Readable : Boolean;
      begin
         File_Ownership (Path, Ignored_User, Ignored_Group, Readable);
         return Readable;
      end;
   end if;

   --  Only a SID this process has already seen can be named again: the
   --  identity the caller holds is a relative identifier, not a SID.
   --  A Keep_Id beside an id never handed out is not a request either.
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
