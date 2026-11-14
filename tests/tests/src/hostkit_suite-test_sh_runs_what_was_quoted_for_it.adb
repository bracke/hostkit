separate (Hostkit_Suite)
procedure Test_Sh_Runs_What_Was_Quoted_For_It
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Room       : constant String := Hostkit.Fs.Create_Temporary_Directory ("hostkit-sh-quoted");
   Had_Shell  : Boolean;
   Saved      : constant String := Hostkit.Environment.Value ("SHELL", Had_Shell);
   --  A backslash and a space: text sh keeps inside single quotes and that
   --  fish, nushell and tcsh each read their own way. Windows has the
   --  backslash for a separator, so only the space there.
   Leaf       : constant String :=
     (if Hostkit.Shell.Is_Command_Shell then "with space" else "back\slash and space");

   procedure Restore is
   begin
      if Had_Shell then
         Hostkit.Environment.Set ("SHELL", Saved);
      else
         Hostkit.Environment.Clear ("SHELL");
      end if;
   end Restore;

   --  Run the where_started companion through the shell, told a file whose
   --  name needs quoting, with SHELL naming Odd_Shell.
   procedure Run_With (Odd_Shell : String; Marker : String) is
      Target    : constant String := Hostkit.Fs.Join (Room, Leaf & " " & Marker);
      Arguments : Hostkit.String_Vectors.Vector;
      Status    : Integer := -1;
      Ran       : Boolean;
   begin
      Hostkit.Environment.Set ("SHELL", Odd_Shell);
      Arguments.Append (To_Unbounded_String (Target));
      Ran := Hostkit.Process.Run_Shell_Command
        (Hostkit.Shell.Command_Line (Companion ("where_started"), Arguments), Wait => True, Exit_Status => Status);
      Assert (Ran and then Status = 0,
              "with SHELL=" & Odd_Shell & " the quoted command still ran; exit was" & Status'Image);
      Assert (Ada.Directories.Exists (Target & ".done"),
              "and its argument arrived whole, backslash and space and all: " & Target);
   end Run_With;
begin
   --  A program that is no shell at all, and one that is not there: neither
   --  is what runs a command quoted for sh.
   Run_With (Companion ("failing"), "a");
   Run_With ("/nonexistent/hostkit-odd-shell", "b");

   if not Hostkit.Shell.Is_Command_Shell then
      Assert (Hostkit.Shell.Executable = "/bin/sh", "sh's quoting is run by /bin/sh");
      Assert (Hostkit.Shell.Interactive_Executable = "/nonexistent/hostkit-odd-shell",
              "while a person's own shell is still SHELL");
   end if;
   Restore;
   Ada.Directories.Delete_Tree (Room);
exception
   when others =>
      Restore;
      if Ada.Directories.Exists (Room) then
         Ada.Directories.Delete_Tree (Room);
      end if;
      raise;
end Test_Sh_Runs_What_Was_Quoted_For_It;
