separate (Hostkit_Suite)
procedure Test_The_Host_Is_Not_Guessed (T : in out AUnit.Test_Cases.Test_Case'Class) is
   pragma Unreferenced (T);
begin
   --  Two per-OS bodies, written independently, must agree about which host this is.
   --  An environment-sniffing answer is what this exists to replace, so the check is
   --  that the identity matches a fact of the host itself rather than a variable.
   Assert
     ((Hostkit.Host.Current = Hostkit.Host.Windows) = Hostkit.Shell.Is_Command_Shell,
      "the host kind agrees with the shell the host runs");

   if Hostkit.Host.Current /= Hostkit.Host.Unsupported then
      Assert (Hostkit.Host.System_Name /= "", "this host names its operating system");
      Assert (Hostkit.Host.Node_Name /= "", "this host names its network node");
      Assert (Hostkit.Host.Release_Name /= "", "this host names its operating system release");
      Assert (Hostkit.Host.Version_Name /= "", "this host names its operating system version");
      Assert (Hostkit.Host.Machine_Name /= "", "this host names its machine class");
   end if;

   declare
      Login : constant String := Hostkit.Host.Login_Name;
   begin
      Assert
        (Ada.Strings.Fixed.Index (Login, "" & Character'Val (10)) = 0,
         "the host login name does not contain LF");
   end;
end Test_The_Host_Is_Not_Guessed;
