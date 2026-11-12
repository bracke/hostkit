separate (Hostkit_Suite)
procedure Test_Windows_Programs_Are_Known_By_Extension
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   function Runs (Path : String) return Boolean renames Hostkit.Windows_Programs.Runs_By_Extension;
begin
   --  The rule is pure text, so it is checked on every host.
   Assert (Runs ("C:\Tools\setup.exe"), "an .exe runs");
   Assert (Runs ("build.CMD"), "the extension is read in any case");
   Assert
     (Runs ("a.com") and then Runs ("a.bat") and then Runs ("a.ps1") and then Runs ("a.msi"),
      "each extension Windows runs is known");
   Assert (not Runs ("archive.tar.gz"), "an archive is no program, whatever its ACL grants");
   Assert (not Runs ("README"), "a name without an extension is no program");
   Assert (not Runs ("C:\dir.exe\notes"), "only the last extension counts, not a folder's");
   Assert (not Runs ("program.exe.txt"), "a program renamed to text is text");
   Assert (not Runs (""), "nothing is no program");
end Test_Windows_Programs_Are_Known_By_Extension;
