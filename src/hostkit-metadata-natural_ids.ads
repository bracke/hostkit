--  The Natural forms of the ownership calls, written once over the Account_Id
--  forms that each host body implements. Each host body completes its
--  Natural declarations by renaming these.
private package Hostkit.Metadata.Natural_Ids is

   procedure File_Ownership
     (Path      : String;
      User_Id   : out Natural;
      Group_Id  : out Natural;
      Available : out Boolean);

   procedure File_Mode_And_Ownership
     (Path                : String;
      Mode_Bits           : out Natural;
      Mode_Available      : out Boolean;
      User_Id             : out Natural;
      Group_Id            : out Natural;
      Ownership_Available : out Boolean);

   function User_Id_For_Name
     (Name  : String;
      Found : out Boolean)
      return Natural;

   function Group_Id_For_Name
     (Name  : String;
      Found : out Boolean)
      return Natural;

end Hostkit.Metadata.Natural_Ids;
