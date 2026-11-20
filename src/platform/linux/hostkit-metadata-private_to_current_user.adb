separate (Hostkit.Metadata)
function Private_To_Current_User (Path : String) return Boolean is
   function Geteuid return Interfaces.C.unsigned
     with Import => True, Convention => C, External_Name => "geteuid";
   --  S_IFMT's nibble, and S_IFLNK's value in it.
   Type_Unit : constant := 8#10000#;
   Link_Type : constant := 8#12#;
   --  The group's and others' permission bits: 8#077#.
   Others_Unit : constant := 8#100#;
   Status : constant Entry_Status := Entry_Status_Of (Path);
begin
   return Status.Available
     and then (Status.Mode / Type_Unit) mod 8#20# /= Link_Type
     and then Status.Mode mod Others_Unit = 0
     and then Status.User_Id = Account_Id (Geteuid);
exception
   when others =>
      return False;
end Private_To_Current_User;
