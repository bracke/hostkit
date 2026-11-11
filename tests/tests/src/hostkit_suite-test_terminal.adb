separate (Hostkit_Suite)
procedure Test_Terminal (T : in out AUnit.Test_Cases.Test_Case'Class) is
   pragma Unreferenced (T);
   Saved : constant String := Hostkit.Environment.Value ("TERMINAL", Default => "");
   Had   : constant Boolean := Ada.Environment_Variables.Exists ("TERMINAL");
   Self  : constant String := Ada.Directories.Full_Name (Ada.Command_Line.Command_Name);
begin
   --  TERMINAL wins when it names something runnable, and is passed over
   --  when it does not.
   Hostkit.Environment.Set ("TERMINAL", Self);
   Assert (Hostkit.Process.Default_Terminal = Self, "TERMINAL naming a runnable program is the terminal");
   Hostkit.Environment.Set ("TERMINAL", "hostkit-no-such-terminal-anywhere");
   Assert
     (Hostkit.Process.Default_Terminal /= "hostkit-no-such-terminal-anywhere",
      "TERMINAL naming nothing runnable is ignored");
   if Had then
      Hostkit.Environment.Set ("TERMINAL", Saved);
   else
      Hostkit.Environment.Clear ("TERMINAL");
   end if;

   --  A terminal that starts where it is started is started in the folder.
   declare
      Folder  : constant String := Ada.Directories.Compose (Scratch, "a folder");
      Command : constant String := Hostkit.Process.Terminal_Command ("xterm", Folder);
   begin
      Assert
        (Ada.Strings.Fixed.Index (Command, Hostkit.Shell.Quote (Folder)) > 0
         and then Ada.Strings.Fixed.Tail (Command, Hostkit.Shell.Quote ("xterm")'Length)
           = Hostkit.Shell.Quote ("xterm"),
         "the command changes into the folder, then starts the terminal: " & Command);
   end;
   --  The ones that must be told the folder are told it.
   if Hostkit.Host.Current = Hostkit.Host.Windows then
      Assert
        (Ada.Strings.Fixed.Index (Hostkit.Process.Terminal_Command ("wt", "C:\x"), "-d") > 0,
         "Windows Terminal is given the folder with -d");
   elsif Hostkit.Host.Current = Hostkit.Host.MacOS then
      Assert
        (Ada.Strings.Fixed.Index (Hostkit.Process.Terminal_Command ("open", "/x"), "Terminal") > 0,
         "on macOS open -a Terminal is handed the folder");
   end if;
end Test_Terminal;
