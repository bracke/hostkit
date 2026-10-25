with Hostkit.Metadata.Natural_Ids;

package body Hostkit.Metadata is

   function Entry_Identity_Of (Path : String) return Entry_Identity is
      pragma Unreferenced (Path);
   begin
      return (others => <>);
   end Entry_Identity_Of;

   function Entry_Revision_Of (Path : String) return Entry_Revision is
      pragma Unreferenced (Path);
   begin
      return (others => <>);
   end Entry_Revision_Of;

   function Update_Entry_Metadata
     (Path           : String;
      Expected       : Entry_Identity;
      Check_Expected : Boolean;
      Kind           : Metadata_Update_Kind;
      Value          : Identity_Field;
      Group          : Identity_Field;
      Max_Previous   : Identity_Field;
      Owner_Name     : String := "";
      Group_Name     : String := "") return Metadata_Update_Result
   is
      pragma Unreferenced
        (Path, Expected, Check_Expected, Kind, Value, Group, Max_Previous,
         Owner_Name, Group_Name);
   begin
      return (others => <>);
   end Update_Entry_Metadata;

   function File_Creation_Time
     (Path      : String;
      Available : out Boolean)
      return Ada.Calendar.Time
   is
      pragma Unreferenced (Path);
   begin
      Available := False;
      return Ada.Calendar.Time_Of (1901, 1, 1);
   end File_Creation_Time;

   function File_Access_Time
     (Path      : String;
      Available : out Boolean)
      return Ada.Calendar.Time
   is
      pragma Unreferenced (Path);
   begin
      Available := False;
      return Ada.Calendar.Time_Of (1901, 1, 1);
   end File_Access_Time;

   function Volume_Capacity_Of (Path : String) return Volume_Capacity is
      pragma Unreferenced (Path);
   begin
      return (others => <>);
   end Volume_Capacity_Of;

   function File_Permission_Bits
     (Path      : String;
      Available : out Boolean)
      return Natural
   is
      pragma Unreferenced (Path);
   begin
      Available := False;
      return 0;
   end File_Permission_Bits;

   function Set_Permissions
     (Path : String;
      Mode : Natural)
      return Boolean
   is
      pragma Unreferenced (Path, Mode);
   begin
      return False;
   end Set_Permissions;

   function Set_File_Times
     (Path          : String;
      Access_Time   : Long_Long_Integer;
      Modified_Time : Long_Long_Integer)
      return Boolean
   is
      pragma Unreferenced (Path, Access_Time, Modified_Time);
   begin
      return False;
   end Set_File_Times;

   function Permissions_Supported return Boolean is
   begin
      return False;
   end Permissions_Supported;

   procedure File_Ownership
     (Path      : String;
      User_Id   : out Account_Id;
      Group_Id  : out Account_Id;
      Available : out Boolean)
   is
      pragma Unreferenced (Path);
   begin
      User_Id := 0;
      Group_Id := 0;
      Available := False;
   end File_Ownership;

   procedure File_Mode_And_Ownership
     (Path                : String;
      Mode_Bits           : out Natural;
      Mode_Available      : out Boolean;
      User_Id             : out Account_Id;
      Group_Id            : out Account_Id;
      Ownership_Available : out Boolean) is
   begin
      Mode_Bits := File_Permission_Bits (Path, Mode_Available);
      File_Ownership (Path, User_Id, Group_Id, Ownership_Available);
   end File_Mode_And_Ownership;

   function Same_File (Left : String; Right : String) return Boolean is
   begin
      return Left /= "" and then Left = Right;
   end Same_File;

   function Device_Id
     (Path      : String;
      Available : out Boolean)
      return Long_Long_Integer
   is
      pragma Unreferenced (Path);
   begin
      Available := False;
      return 0;
   end Device_Id;

   function User_Id_For_Name
     (Name  : String;
      Found : out Boolean)
      return Account_Id
   is
      pragma Unreferenced (Name);
   begin
      Found := False;
      return 0;
   end User_Id_For_Name;

   function Group_Id_For_Name
     (Name  : String;
      Found : out Boolean)
      return Account_Id
   is
      pragma Unreferenced (Name);
   begin
      Found := False;
      return 0;
   end Group_Id_For_Name;

   function User_Name_For_Id (Id : Account_Id) return String is
      pragma Unreferenced (Id);
   begin
      return "";
   end User_Name_For_Id;

   function Group_Name_For_Id (Id : Account_Id) return String is
      pragma Unreferenced (Id);
   begin
      return "";
   end Group_Name_For_Id;

   function Set_Ownership
     (Path     : String;
      User_Id  : Account_Id;
      Group_Id : Account_Id)
      return Boolean
   is
      pragma Unreferenced (Path, User_Id, Group_Id);
   begin
      return False;
   end Set_Ownership;

   function Mode_Bits_Are_Native return Boolean is
   begin
      return False;
   end Mode_Bits_Are_Native;

   function Ownership_Supported return Boolean is
   begin
      return False;
   end Ownership_Supported;

   procedure File_Ownership
     (Path      : String;
      User_Id   : out Natural;
      Group_Id  : out Natural;
      Available : out Boolean) renames Natural_Ids.File_Ownership;

   procedure File_Mode_And_Ownership
     (Path                : String;
      Mode_Bits           : out Natural;
      Mode_Available      : out Boolean;
      User_Id             : out Natural;
      Group_Id            : out Natural;
      Ownership_Available : out Boolean) renames Natural_Ids.File_Mode_And_Ownership;

   function User_Id_For_Name
     (Name  : String;
      Found : out Boolean)
      return Natural renames Natural_Ids.User_Id_For_Name;

   function Group_Id_For_Name
     (Name  : String;
      Found : out Boolean)
      return Natural renames Natural_Ids.Group_Id_For_Name;

end Hostkit.Metadata;
