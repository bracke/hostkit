separate (Hostkit_Suite)
procedure Test_Locate (T : in out AUnit.Test_Cases.Test_Case'Class) is
   pragma Unreferenced (T);

   --  The host's own shell is the one program certain to be present, and
   --  Hostkit.Shell already knows where it is: locating its simple name has
   --  to find it again.
   Shell_Path : constant String := Hostkit.Shell.Executable;
   Simple     : constant String := Ada.Directories.Simple_Name (Shell_Path);
   Found      : constant String := Hostkit.Process.Locate (Simple);
begin
   Assert (Found /= "", "the host's own shell is found by name");
   Assert
     (Ada.Directories.Simple_Name (Found) = Simple,
      "locating a name returns that program, not another");
   Assert
     (Hostkit.Process.Locate ("hostkit-definitely-not-a-program") = "",
      "a name the host has no program for answers empty");
   Assert
     (Hostkit.Process.Locate ("") = "",
      "an empty name answers empty rather than something");
end Test_Locate;
