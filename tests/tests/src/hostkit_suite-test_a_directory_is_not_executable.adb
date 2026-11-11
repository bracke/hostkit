separate (Hostkit_Suite)
procedure Test_A_Directory_Is_Not_Executable (T : in out AUnit.Test_Cases.Test_Case'Class) is
   pragma Unreferenced (T);
begin
   --  GNAT.OS_Lib.Is_Executable_File says True here on Windows, and an open action
   --  pointing at a directory was duly launched.
   Assert
     (not Hostkit.Fs.Is_Executable (Ada.Directories.Current_Directory),
      "a directory is not something this host runs");
   Assert
     (Hostkit.Fs.Is_Executable (Companion ("noop")),
      "and a program that this host runs, is");
end Test_A_Directory_Is_Not_Executable;
