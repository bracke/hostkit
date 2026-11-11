separate (Hostkit_Suite)
procedure Test_Executability_Across_Modes (T : in out AUnit.Test_Cases.Test_Case'Class) is
   pragma Unreferenced (T);

   Path : constant String := Ada.Directories.Compose (Scratch, "hk-exec-modes");

   function At_Mode (Mode : Interfaces.C.int) return Boolean is
   begin
      Chmod (Path, Mode);
      return Hostkit.Fs.Is_Executable (Path);
   end At_Mode;
begin
   if Hostkit.Host.Current = Hostkit.Host.Windows then
      --  Windows decides by extension, not by mode; the matrix means nothing
      --  there and Test_A_Directory_Is_Not_Executable covers what does.
      Skip ("Test_Executability_Across_Modes", "Windows decides by extension, not by mode");
      return;
   end if;

   Write_File (Path, "#!/bin/sh" & ASCII.LF & "exit 0");

   Assert (not At_Mode (8#644#), "a plain readable file is not executable");
   Assert (At_Mode (8#755#), "the usual executable mode is");
   Assert (At_Mode (8#700#), "owner-only rwx is");
   Assert (At_Mode (8#100#), "owner execute alone is, with no read bit");
   Assert (not At_Mode (8#600#), "read and write without execute is not");

   --  The bit that separates "the owner may run it" from "somebody may":
   --  recorded rather than assumed, because a one-stat implementation has to
   --  test the same bit this one does.
   Assert
     (not At_Mode (8#011#),
      "execute for group and other, but not owner, is not executable to us");

   Chmod (Path, 8#644#);
   Ada.Directories.Delete_File (Path);

   Assert
     (not Hostkit.Fs.Is_Executable (Ada.Directories.Compose (Scratch, "hk-exec-absent")),
      "a path that does not exist is not executable");
   Assert
     (not Hostkit.Fs.Is_Executable (Scratch),
      "a directory is not executable however its bits are set");
end Test_Executability_Across_Modes;
