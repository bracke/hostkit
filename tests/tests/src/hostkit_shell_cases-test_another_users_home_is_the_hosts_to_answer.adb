separate (Hostkit_Shell_Cases)
procedure Test_Another_Users_Home_Is_The_Hosts_To_Answer
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);

   use type Hostkit.Host.Kind;
begin
   Assert (Hostkit.Fs.Home_Directory_Of
             ("hostkit-no-such-account-anywhere") = "",
           "a user this host does not have has no home directory");

   Assert (Hostkit.Fs.Home_Directory_Of ("") = "",
           "a nameless user has no home directory");

   if Hostkit.Host.Current = Hostkit.Host.Windows then
      Assert (Hostkit.Fs.Home_Directory_Of ("Administrator") = "",
              "Windows answers about no account but the one logged in");
      return;
   end if;

   --  root is the one account every POSIX host has, and the database is
   --  what is being asked -- not HOME, which is this process's own.
   Assert (Hostkit.Fs.Home_Directory_Of ("root") /= "",
           "a POSIX host knows where root lives");
end Test_Another_Users_Home_Is_The_Hosts_To_Answer;
