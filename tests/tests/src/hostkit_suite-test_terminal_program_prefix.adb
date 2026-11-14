separate (Hostkit_Suite)
procedure Test_Terminal_Program_Prefix (T : in out AUnit.Test_Cases.Test_Case'Class) is
   pragma Unreferenced (T);

   --  The prefix Terminal_Program_Prefix gives Terminal, joined with spaces,
   --  or "(none)" when it says the terminal cannot be handed a program.
   function Prefix_Of (Terminal : String) return String is
      Prefix : Hostkit.String_Vectors.Vector;
      Joined : Unbounded_String;
   begin
      if not Hostkit.Process.Terminal_Program_Prefix (Terminal, Prefix) then
         Assert (Prefix.Is_Empty, "a refused terminal leaves no prefix: " & Terminal);
         return "(none)";
      end if;
      for Item of Prefix loop
         if Length (Joined) > 0 then
            Append (Joined, " ");
         end if;
         Append (Joined, Item);
      end loop;
      return To_String (Joined);
   end Prefix_Of;

   procedure Check (Terminal : String; Expected : String) is
      Got : constant String := Prefix_Of (Terminal);
   begin
      Assert (Got = Expected, Terminal & " is handed a program with [" & Expected & "], not [" & Got & "]");
   end Check;
begin
   Check ("x-terminal-emulator", "-e");
   Check ("xterm", "-e");
   Check ("uxterm", "-e");
   Check ("konsole", "-e");
   Check ("alacritty", "-e");
   Check ("urxvt", "-e");
   Check ("rxvt", "-e");
   Check ("ghostty", "-e");
   Check ("tilix", "-e");
   Check ("terminology", "-e");
   Check ("xfce4-terminal", "-x");
   Check ("terminator", "-x");
   Check ("gnome-terminal", "--");
   Check ("kgx", "--");
   Check ("ptyxis", "--");
   Check ("foot", "--");
   Check ("wezterm", "start --");
   Check ("kitty", "");
   Check ("wt", "");
   Check ("cmd", "/k");

   --  Those that cannot be handed a program and its arguments, and those
   --  not known at all, are refused.
   Check ("pwsh", "(none)");
   Check ("powershell", "(none)");
   Check ("open", "(none)");
   Check ("hostkit-no-such-terminal", "(none)");
   Check ("", "(none)");

   --  A terminal is known by its program name alone: a folder, ".exe" and
   --  case do not change it, on any host.
   Check ("/usr/bin/kitty", "");
   Check ("/usr/local/bin/Tilix", "-e");
   Check ("C:\Windows\System32\CMD.EXE", "/k");
   Check ("C:\Users\me\AppData\Local\Microsoft\WindowsApps\wt.exe", "");
   Check ("WezTerm.exe", "start --");
   Check ("/opt/xterm/", "(none)");
end Test_Terminal_Program_Prefix;
