package body Hostkit.Metadata.Natural_Ids is

   procedure File_Ownership
     (Path      : String;
      User_Id   : out Natural;
      Group_Id  : out Natural;
      Available : out Boolean)
   is
      User  : Account_Id;
      Group : Account_Id;
   begin
      Hostkit.Metadata.File_Ownership (Path, User, Group, Available);
      Available := Available and then Fits_Natural (User) and then Fits_Natural (Group);
      User_Id := (if Available then Natural (User) else 0);
      Group_Id := (if Available then Natural (Group) else 0);
   end File_Ownership;

   procedure File_Mode_And_Ownership
     (Path                : String;
      Mode_Bits           : out Natural;
      Mode_Available      : out Boolean;
      User_Id             : out Natural;
      Group_Id            : out Natural;
      Ownership_Available : out Boolean)
   is
      User  : Account_Id;
      Group : Account_Id;
   begin
      Hostkit.Metadata.File_Mode_And_Ownership
        (Path, Mode_Bits, Mode_Available, User, Group, Ownership_Available);
      Ownership_Available :=
        Ownership_Available and then Fits_Natural (User) and then Fits_Natural (Group);
      User_Id := (if Ownership_Available then Natural (User) else 0);
      Group_Id := (if Ownership_Available then Natural (Group) else 0);
   end File_Mode_And_Ownership;

   function User_Id_For_Name
     (Name  : String;
      Found : out Boolean)
      return Natural
   is
      Id : constant Account_Id := Hostkit.Metadata.User_Id_For_Name (Name, Found);
   begin
      Found := Found and then Fits_Natural (Id);
      return (if Found then Natural (Id) else 0);
   end User_Id_For_Name;

   function Group_Id_For_Name
     (Name  : String;
      Found : out Boolean)
      return Natural
   is
      Id : constant Account_Id := Hostkit.Metadata.Group_Id_For_Name (Name, Found);
   begin
      Found := Found and then Fits_Natural (Id);
      return (if Found then Natural (Id) else 0);
   end Group_Id_For_Name;

end Hostkit.Metadata.Natural_Ids;
