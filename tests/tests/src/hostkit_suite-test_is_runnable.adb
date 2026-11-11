separate (Hostkit_Suite)
procedure Test_Is_Runnable (T : in out AUnit.Test_Cases.Test_Case'Class) is
   pragma Unreferenced (T);
begin
   Assert (not Hostkit.Process.Is_Runnable (""), "nothing is not a program");
   Assert
     (not Hostkit.Process.Is_Runnable ("hostkit-no-such-program-anywhere"),
      "a name not on the search path is not runnable");
   --  A folder is not a program, whatever GNAT's own check says on Windows.
   Assert (not Hostkit.Process.Is_Runnable (Ada.Directories.Current_Directory), "a directory is not runnable");
   Assert
     (Hostkit.Process.Is_Runnable (Ada.Command_Line.Command_Name)
      or else not Ada.Directories.Exists (Ada.Command_Line.Command_Name),
      "the running test program, named by its path, is runnable");
   --  And a bare name found on the search path: the host's own shell.
   Assert
     (Hostkit.Process.Is_Runnable (if Hostkit.Host.Current = Hostkit.Host.Windows then "cmd" else "sh"),
      "the host's shell, named bare, is found and runnable");
end Test_Is_Runnable;
