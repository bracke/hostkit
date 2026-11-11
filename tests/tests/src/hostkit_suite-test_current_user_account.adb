separate (Hostkit_Suite)
procedure Test_Current_User_Account (T : in out AUnit.Test_Cases.Test_Case'Class) is
   pragma Unreferenced (T);
   Account : Hostkit.Metadata.Account_Id;
   Id      : Natural;
   Known   : constant Boolean := Hostkit.Process.Current_User_Account (Account);
begin
   if Hostkit.Host.Current = Hostkit.Host.Windows then
      Assert (not Known, "Windows has no numeric user id to give");
      return;
   end if;
   Assert (Known, "a POSIX host gives the process's user id");
   Assert
     (not Hostkit.Process.Current_User_Id (Id) or else Hostkit.Metadata.Account_Id (Id) = Account,
      "the narrow and the full user id agree");
   --  A file this process makes is owned by it.
   declare
      Path      : constant String := Ada.Directories.Compose (Scratch, "hostkit-owned-by-me");
      File      : Ada.Text_IO.File_Type;
      Owner     : Hostkit.Metadata.Account_Id;
      Group     : Hostkit.Metadata.Account_Id;
      Available : Boolean;
   begin
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Close (File);
      Hostkit.Metadata.File_Ownership (Path, Owner, Group, Available);
      Ada.Directories.Delete_File (Path);
      Assert (Available and then Owner = Account, "a new file's owner is the current user account");
   end;
end Test_Current_User_Account;
