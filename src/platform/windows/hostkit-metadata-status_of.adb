separate (Hostkit.Metadata)
function Status_Of
  (Path         : String;
   Follow_Links : Boolean) return Entry_Status
is
   File   : System.Address :=
     Open_Entry
       (Path,
        File_Read_Attributes or Read_Control,
        Follow_Links => Follow_Links);
   Legacy : aliased By_Handle_File_Information;
   Basic  : aliased File_Basic_Info;

   Owner      : aliased System.Address := System.Null_Address;
   Group      : aliased System.Address := System.Null_Address;
   Dacl       : aliased System.Address := System.Null_Address;
   Sacl       : aliased System.Address := System.Null_Address;
   Descriptor : aliased System.Address := System.Null_Address;

   Everyone      : aliased Sid_Buffer := [others => Interfaces.C.nul];
   Everyone_Size : aliased C_DWord := C_DWord (Sid_Buffer'Length);
   Runnable_Name : Unbounded_String := To_Unbounded_String (Path);
   Runnable_Name_Available : Boolean := True;

   procedure Clean is
      Freed : System.Address;
      pragma Unreferenced (Freed);
   begin
      if Descriptor /= System.Null_Address then
         Freed := Local_Free (Descriptor);
         Descriptor := System.Null_Address;
      end if;
      Close_Entry (File);
   end Clean;

   --  Executability on Windows is a property of the resolved file name's
   --  extension.  When this query follows a link, derive that name from
   --  the same held handle as the rest of the status instead of from the
   --  link's alias.
   function Held_Path (Available : out Boolean) return String is
      Length : constant C_DWord :=
        Get_Final_Path_Name (File, System.Null_Address, 0, 0);
   begin
      Available := False;
      if Length = 0 then
         return "";
      end if;
      declare
         Buffer  : aliased Wide_String (1 .. Natural (Length) + 1);
         Written : constant C_DWord :=
           Get_Final_Path_Name (File, Buffer'Address, Length + 1, 0);
      begin
         if Written = 0 or else Written > Length then
            return "";
         end if;
         Available := True;
         return Hostkit.Windows_Paths.To_UTF_8
           (Buffer (1 .. Natural (Written)));
      end;
   exception
      when others =>
         Available := False;
         return "";
   end Held_Path;
begin
   if File = Invalid_Handle_Value
     or else Get_File_Information (File, Legacy'Access) = 0
     or else Get_File_Information_Ex
       (File,
        File_Basic_Info_Class,
        Basic'Address,
        C_DWord (File_Basic_Info'Size / 8)) = 0
     or else Get_Security_Info
       (File,
        Se_File_Object,
        Owner_Information or Group_Information or Dacl_Information,
        Owner'Address,
        Group'Address,
        Dacl'Address,
        Sacl'Address,
        Descriptor'Access) /= Success
   then
      Clean;
      return (others => <>);
   end if;

   if Follow_Links then
      Runnable_Name := To_Unbounded_String
        (Held_Path (Runnable_Name_Available));
      if not Runnable_Name_Available then
         Clean;
         return (others => <>);
      end if;
   end if;

   declare
      Is_Link : constant Boolean :=
        (Legacy.Attributes and File_Attribute_Reparse_Point) /= 0;
      Is_Directory : constant Boolean :=
        (Legacy.Attributes and File_Attribute_Directory) /= 0;
      World : constant System.Address :=
        (if Create_Well_Known_Sid
              (Win_World_Sid,
               System.Null_Address,
               Everyone (1)'Address,
               Everyone_Size'Access) /= 0
         then Everyone (1)'Address
         else System.Null_Address);
      Type_Bits : constant Natural :=
        (if Is_Link then 8#120000#
         elsif Is_Directory then 8#040000#
         else 8#100000#);
      Runnable : constant Boolean :=
        not Is_Link
        and then
          (Is_Directory
           or else Runs_On_Windows (To_String (Runnable_Name)));
      Result : constant Entry_Status :=
        (Available        => True,
         Size             =>
           Interfaces.Shift_Left
             (Identity_Field (Legacy.Size_High), 32)
           or Identity_Field (Legacy.Size_Low),
         Modified_Seconds =>
           Long_Long_Integer (Basic.Modified_Time / 10_000_000)
           - 11_644_473_600,
         Mode             =>
           Type_Bits + Mode_Of (Dacl, Owner, Group, World, Runnable),
         User_Id          => Account_Id (Identity_Of (Owner)),
         Group_Id         => Account_Id (Identity_Of (Group)));
   begin
      Remember (Owner, Natural (Result.User_Id));
      Remember (Group, Natural (Result.Group_Id));
      Clean;
      return Result;
   end;
exception
   when others =>
      Clean;
      return (others => <>);
end Status_Of;
