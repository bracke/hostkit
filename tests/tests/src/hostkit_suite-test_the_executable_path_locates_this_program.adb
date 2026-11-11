separate (Hostkit_Suite)
procedure Test_The_Executable_Path_Locates_This_Program
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Path : constant String := Hostkit.Host.Executable_Path;
begin
   if Hostkit.Host.Current = Hostkit.Host.Unsupported then
      --  A host with no way to ask says so rather than guessing, and the
      --  caller falls back to the command name.
      Assert (Path = "", "a host that cannot answer says so rather than guessing");
      return;
   end if;

   --  It has to name a file that exists, which the command name does not
   --  have to: that is the whole reason this exists.
   Assert (Path /= "", "this host can name its own executable, got nothing");
   Assert (Ada.Directories.Exists (Path),
           "the executable path names nothing that exists: '" & Path & "'");
   Assert (Ada.Directories.Simple_Name (Path)'Length > 0,
           "the executable path has no file part: '" & Path & "'");
end Test_The_Executable_Path_Locates_This_Program;
