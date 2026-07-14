with Ada.Strings.Unbounded;

with GNAT.OS_Lib;

with Hostkit.Native;
with Hostkit.Shell;

package body Hostkit.Process is
   use Ada.Strings.Unbounded;
   use type GNAT.OS_Lib.Argument_List_Access;
   use type GNAT.OS_Lib.Process_Id;

   --  Collecting finished children is housekeeping, so it happens off the caller's
   --  thread rather than in the middle of an open.
   --
   --  It never waits for a child. A task that blocked on one would keep the
   --  application from exiting -- the environment task waits for library-level tasks
   --  to finish -- so quitting while a launched editor is still open would hang on
   --  quit, which is the bug this whole design exists to avoid. It collects only
   --  children that have *already* finished, which returns at once.
   --
   --  The terminate alternative is what makes that a guarantee: when no one can call
   --  Note_Launch again, the task ends and the program is free to exit.
   task Reaper is
      entry Note_Launch;
   end Reaper;

   task body Reaper is
   begin
      loop
         select
            accept Note_Launch;
         or
            terminate;
         end select;

         Hostkit.Native.Reap_Finished_Children;
      end loop;
   end Reaper;

   function To_Argument_List
     (Arguments : String_Vectors.Vector)
      return GNAT.OS_Lib.Argument_List_Access
   is
      Count  : constant Natural := Natural (Arguments.Length);
      Result : constant GNAT.OS_Lib.Argument_List_Access :=
        new GNAT.OS_Lib.Argument_List (1 .. Count);
   begin
      for Index in 1 .. Count loop
         Result (Index) :=
           new String'(To_String (Arguments.Element (Positive (Index))));
      end loop;

      return Result;
   end To_Argument_List;

   function Launch
     (Program   : String;
      Arguments : String_Vectors.Vector)
      return Boolean
   is
      Args    : GNAT.OS_Lib.Argument_List_Access := null;
      Started : GNAT.OS_Lib.Process_Id;
   begin
      if Program = "" then
         return False;
      end if;

      Args := To_Argument_List (Arguments);

      --  Starts the process and returns without waiting for it.
      Started := GNAT.OS_Lib.Non_Blocking_Spawn (Program, Args.all);
      GNAT.OS_Lib.Free (Args);

      if Started = GNAT.OS_Lib.Invalid_Pid then
         return False;
      end if;

      Reaper.Note_Launch;
      return True;
   exception
      when others =>
         if Args /= null then
            GNAT.OS_Lib.Free (Args);
         end if;
         return False;
   end Launch;

   function Run
     (Program     : String;
      Arguments   : String_Vectors.Vector;
      Exit_Status : out Integer)
      return Boolean
   is
      Args : GNAT.OS_Lib.Argument_List_Access := null;
   begin
      Exit_Status := -1;

      if Program = "" then
         return False;
      end if;

      Args := To_Argument_List (Arguments);
      Exit_Status := GNAT.OS_Lib.Spawn (Program, Args.all);
      GNAT.OS_Lib.Free (Args);

      return Exit_Status = 0;
   exception
      when others =>
         if Args /= null then
            GNAT.OS_Lib.Free (Args);
         end if;
         Exit_Status := -1;
         return False;
   end Run;

   function Run_Shell_Command
     (Command     : String;
      Wait        : Boolean;
      Exit_Status : out Integer)
      return Boolean
   is
      Shell : constant String := Hostkit.Shell.Executable;
   begin
      Exit_Status := -1;

      if Command = "" or else Shell = "" then
         return False;
      end if;

      if Hostkit.Native.Supports_Raw_Command_Line then
         --  "/S /C" is the reliable form: with /S, cmd strips the first and last quote
         --  of everything after it and runs the rest verbatim. So the already-quoted
         --  command is wrapped in one more pair, which /S then removes, leaving exactly
         --  the line we built. Without /S, cmd applies a rule of its own -- with more
         --  than two quotes in the line it strips the first and the last -- which cuts
         --  through the middle of the quoting and spills an argument onto the line.
         return Hostkit.Native.Run_Command_Line
                  ("""" & Shell & """ /S /C """ & Command & """", Wait, Exit_Status);
      end if;

      declare
         Arguments : String_Vectors.Vector;
      begin
         Arguments.Append (To_Unbounded_String (Hostkit.Shell.Command_Option));
         Arguments.Append (To_Unbounded_String (Command));

         if Wait then
            return Run (Shell, Arguments, Exit_Status);
         end if;

         return Launch (Shell, Arguments);
      end;
   end Run_Shell_Command;

   function Open_Native (Path : String) return Boolean is
   begin
      return Hostkit.Native.Open_Native (Path);
   end Open_Native;

end Hostkit.Process;
