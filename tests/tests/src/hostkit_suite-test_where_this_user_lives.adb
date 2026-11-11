separate (Hostkit_Suite)
procedure Test_Where_This_User_Lives (T : in out AUnit.Test_Cases.Test_Case'Class) is
   pragma Unreferenced (T);

   Home : constant String := Hostkit.Fs.Home_Directory;
   Data : constant String := Hostkit.Fs.Application_Data_Directory;
begin
   if Hostkit.Host.Current = Hostkit.Host.Unsupported then
      Skip ("Test_Where_This_User_Lives", "an unsupported host has no user directories");
      return;
   end if;

   Assert (Home /= "", "the host has a home directory for this user");
   Assert
     (Ada.Directories.Exists (Home),
      "and it is a directory that exists: " & Home);

   --  Not the same question: a program that writes per-user data into the
   --  home directory is wrong on two of the three hosts.
   Assert (Data /= "", "and a place for per-user application data");
   Assert
     (Data /= Home,
      "which is not simply the home directory");
end Test_Where_This_User_Lives;
