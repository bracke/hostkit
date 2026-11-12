--  What Windows runs, as Windows decides it: by the extension.
--
--  Windows does not decide what runs from an ACL. Every ordinary file is
--  granted FILE_EXECUTE in its DACL, so reading that bit said everything was
--  executable -- and a file manager duly classified a .tar.gz as a program.
--  Hostkit.Fs.Is_Executable and the mode Hostkit.Metadata reads both ask
--  this one list, so the two cannot disagree. The rule is pure text, so it
--  lives in the shared source and is tested on every platform.
package Hostkit.Windows_Programs is

   --  Does Path end in an extension Windows runs (.exe, .com, .bat, .cmd,
   --  .ps1, .msi), in any case? Only the text is read; nothing is asked of
   --  the file system, and a folder so named answers True as well.
   --
   --  @param Path A path or a bare name.
   --  @return True when the extension after Path's last '.' is one of them.
   function Runs_By_Extension (Path : String) return Boolean;

end Hostkit.Windows_Programs;
