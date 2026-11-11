with Ada.Directories;
with Ada.Streams.Stream_IO;
with Hostkit.Environment;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with GNAT.OS_Lib;

with Hostkit.Fs;
with Hostkit.Host;
with Hostkit.Native;
with Hostkit.Shell;
with Hostkit.Windows_Command_Line;

package body Hostkit.Process is
   use type Ada.Directories.File_Kind;
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
      Exit_Status : Integer;
   begin
      if Program = "" then
         return False;
      end if;

      --  GNAT's Non_Blocking_Spawn argument-vector path is not reliable on
      --  native Windows.  Use the same directly quoted CreateProcessW seam as
      --  captured and shell launches there; closing its handles still gives
      --  the detached semantics promised by this operation.
      if Hostkit.Native.Supports_Raw_Command_Line then
         return Hostkit.Native.Run_Command_Line
           (Hostkit.Windows_Command_Line.Build (Program, Arguments),
            Wait => False, Exit_Status => Exit_Status);
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

   function Become
     (Program   : String;
      Arguments : String_Vectors.Vector)
      return Boolean
   is
   begin
      return Hostkit.Native.Become_Program (Program, Arguments);
   end Become;

   function Locate (Program : String) return String is
      use type GNAT.OS_Lib.String_Access;
      Found : GNAT.OS_Lib.String_Access :=
        GNAT.OS_Lib.Locate_Exec_On_Path (Program);
   begin
      if Found = null then
         return "";
      end if;

      declare
         Result : constant String := Found.all;
      begin
         GNAT.OS_Lib.Free (Found);
         return Result;
      end;
   exception
      when others =>
         return "";
   end Locate;

   function Is_Runnable (Program : String) return Boolean is
   begin
      if Program = "" then
         return False;
      elsif (for some C of Program => Hostkit.Fs.Is_Separator (C)) then
         return Ada.Directories.Exists (Program)
           and then Ada.Directories.Kind (Program) = Ada.Directories.Ordinary_File
           and then Hostkit.Fs.Is_Executable (Program);
      end if;
      return Locate (Program) /= "";
   exception
      when others =>
         return False;
   end Is_Runnable;

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

   function Run_Captured
     (Program           : String;
      Arguments         : String_Vectors.Vector;
      Working_Directory : String := "";
      Stdin_Path        : String := "";
      Stdout_Path       : String := "";
      Stderr_Path       : String := "";
      Timeout_Ms        : Natural := 0;
      Cancelled         : Cancel_Check := null;
      Poll              : Poll_Hook := null;
      Started           : Started_Hook := null;
      Whole_Group       : Boolean := False;
      Clean_Wrapper     : Boolean := False)
      return Process_Outcome
   is
      Nothing : Process_Outcome;

      --  Asked here rather than in the four bodies so that every host answers
      --  the same way. A body left to discover it has nowhere to read from is
      --  already inside its own spawn, where POSIX can only end the child and
      --  Windows can only decline -- two different stories for one mistake.
      function Input_Is_Readable return Boolean is
         File : Ada.Streams.Stream_IO.File_Type;
      begin
         Ada.Streams.Stream_IO.Open
           (File, Ada.Streams.Stream_IO.In_File, Stdin_Path, Form => "shared=no");
         Ada.Streams.Stream_IO.Close (File);
         return True;
      exception
         when others =>
            return False;
      end Input_Is_Readable;
   begin
      if Program = "" then
         return Nothing;
      end if;

      if Stdin_Path /= "" and then not Input_Is_Readable then
         return Nothing;
      end if;

      return Hostkit.Native.Run_Captured
               (Program, Arguments, Working_Directory, Stdin_Path,
                Stdout_Path, Stderr_Path, Timeout_Ms, Cancelled, Poll, Started,
                Whole_Group, Clean_Wrapper);
   exception
      when others =>
         return Nothing;
   end Run_Captured;

   function Request_Stop (Process_Id : Integer) return Boolean is
   begin
      if Process_Id <= 0 then
         return False;
      end if;

      return Hostkit.Native.Request_Stop (Process_Id);
   exception
      when others =>
         return False;
   end Request_Stop;

   function Presence_Of (Process_Id : Integer) return Presence is
   begin
      if Process_Id <= 0 then
         return Unknown;
      end if;

      return Hostkit.Native.Presence_Of (Process_Id);
   exception
      when others =>
         return Unknown;
   end Presence_Of;

   function Identity_Of (Process_Id : Integer) return String is
      --  The first line of a file, or "" where it will not read.
      function First_Line (Path : String) return String is
         File : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path, Form => "shared=no");
         declare
            Line : constant String := Ada.Text_IO.Get_Line (File);
         begin
            Ada.Text_IO.Close (File);
            return Line;
         end;
      exception
         when others =>
            if Ada.Text_IO.Is_Open (File) then
               Ada.Text_IO.Close (File);
            end if;
            return "";
      end First_Line;

      Image : constant String := Ada.Strings.Fixed.Trim (Integer'Image (Process_Id), Ada.Strings.Both);
   begin
      if Process_Id <= 0 then
         return "";
      end if;
      declare
         Stat : constant String := First_Line ("/proc/" & Image & "/stat");
         Boot : constant String := First_Line ("/proc/sys/kernel/random/boot_id");
         --  Past the name in parentheses, which may hold spaces and
         --  parentheses of its own: the fields after the last ')'.
         Close : constant Natural := Ada.Strings.Fixed.Index (Stat, ")", Ada.Strings.Backward);
         Field : Natural := 2;
         Start : Natural;
      begin
         if Stat = "" or else Boot = "" or else Close = 0 then
            return "";
         end if;
         --  The start time is the 22nd field: the 20th after the name.
         Start := Close + 2;
         for Index in Close + 2 .. Stat'Last + 1 loop
            if Index > Stat'Last or else Stat (Index) = ' ' then
               Field := Field + 1;
               if Field = 22 then
                  return Boot & ":" & Stat (Start .. Index - 1);
               end if;
               Start := Index + 1;
            end if;
         end loop;
         return "";
      end;
   exception
      when others =>
         return "";
   end Identity_Of;

   function Wait_FD
     (FD         : Integer;
      For_Write  : Boolean;
      Timeout_MS : Integer)
      return Wait_Outcome is
   begin
      return Hostkit.Native.Wait_FD (FD, For_Write, Timeout_MS);
   exception
      when others =>
         return Wait_Error;
   end Wait_FD;

   function Native_Backend_Label return String is
   begin
      return Hostkit.Native.Native_Backend_Label;
   end Native_Backend_Label;

   function Current_User_Account (User_Id : out Hostkit.Metadata.Account_Id) return Boolean is
   begin
      return Hostkit.Native.Current_User_Id (User_Id);
   exception
      when others =>
         User_Id := 0;
         return False;
   end Current_User_Account;

   function Current_Group_Account (Group_Id : out Hostkit.Metadata.Account_Id) return Boolean is
   begin
      return Hostkit.Native.Current_Group_Id (Group_Id);
   exception
      when others =>
         Group_Id := 0;
         return False;
   end Current_Group_Account;

   function Current_User_Id (User_Id : out Natural) return Boolean is
      Id : Hostkit.Metadata.Account_Id;
   begin
      User_Id := 0;
      if Current_User_Account (Id) and then Hostkit.Metadata.Fits_Natural (Id) then
         User_Id := Natural (Id);
         return True;
      end if;
      return False;
   end Current_User_Id;

   function Current_Group_Id (Group_Id : out Natural) return Boolean is
      Id : Hostkit.Metadata.Account_Id;
   begin
      Group_Id := 0;
      if Current_Group_Account (Id) and then Hostkit.Metadata.Fits_Natural (Id) then
         Group_Id := Natural (Id);
         return True;
      end if;
      return False;
   end Current_Group_Id;

   function Current_Supplementary_Group_Ids
     (Groups : out Group_Id_List;
      Last   : out Natural)
      return Boolean
   is
   begin
      return Hostkit.Native.Current_Supplementary_Group_Ids (Groups, Last);
   exception
      when others =>
         for Index in Groups'Range loop
            Groups (Index) := 0;
         end loop;
         Last := 0;
         return False;
   end Current_Supplementary_Group_Ids;

   function User_Group_Ids
     (User_Name : String;
      Groups    : out Group_Id_List;
      Last      : out Natural)
      return Boolean
   is
   begin
      return Hostkit.Native.User_Group_Ids (User_Name, Groups, Last);
   exception
      when others =>
         for Index in Groups'Range loop
            Groups (Index) := 0;
         end loop;
         Last := 0;
         return False;
   end User_Group_Ids;

   function Environment_Value
     (Name  : String;
      Value : out UString)
      return Boolean
   is
   begin
      declare
         Found : Boolean;
         Text  : constant String := Hostkit.Environment.Value (Name, Found);
      begin
         Value := To_Unbounded_String (Text);
         return Found;
      end;
   exception
      when others =>
         Value := Null_Unbounded_String;
         return False;
   end Environment_Value;

   procedure Portable_Default_Opener
     (Path_Token : String;
      Program    : out UString;
      Arguments  : out String_Vectors.Vector) is
   begin
      Arguments := String_Vectors.Empty_Vector;
      case Hostkit.Host.Current is
         when Hostkit.Host.Windows =>
            --  start's empty first argument is the window title it would
            --  otherwise take the quoted path for.
            Program := To_Unbounded_String ("cmd");
            Arguments.Append (To_Unbounded_String ("/c"));
            Arguments.Append (To_Unbounded_String ("start"));
            Arguments.Append (Null_Unbounded_String);
         when Hostkit.Host.MacOS =>
            Program := To_Unbounded_String ("open");
         when Hostkit.Host.Linux | Hostkit.Host.Unsupported =>
            Program := To_Unbounded_String ("xdg-open");
      end case;
      Arguments.Append (To_Unbounded_String (Path_Token));
   end Portable_Default_Opener;

   function Is_Shell_Start
     (Program   : String;
      Arguments : String_Vectors.Vector)
      return Boolean
   is
      use type Hostkit.Host.Kind;
   begin
      return Hostkit.Host.Current = Hostkit.Host.Windows and then Has_Shell_Start_Shape (Program, Arguments);
   end Is_Shell_Start;

   function Has_Shell_Start_Shape
     (Program   : String;
      Arguments : String_Vectors.Vector)
      return Boolean
   is
      use type Ada.Containers.Count_Type;

      function Lower (Text : String) return String is
         Result : String := Text;
      begin
         for C of Result loop
            if C in 'A' .. 'Z' then
               C := Character'Val (Character'Pos (C) + 32);
            end if;
         end loop;
         return Result;
      end Lower;

      Name : constant String := Lower (Program);
   begin
      return Arguments.Length = 4
        and then (Name in "cmd" | "cmd.exe"
                  or else (Name'Length > 8 and then Name (Name'Last - 7 .. Name'Last) in "\cmd.exe" | "/cmd.exe"))
        and then Lower (To_String (Arguments (1))) = "/c"
        and then Lower (To_String (Arguments (2))) = "start"
        and then To_String (Arguments (3)) = ""
        and then To_String (Arguments (4)) /= "";
   end Has_Shell_Start_Shape;

   function Default_Opener
     (Mime_Type  : String;
      Path_Token : String;
      Program    : out UString;
      Arguments  : out String_Vectors.Vector)
      return Boolean
   is
      use type Hostkit.Host.Kind;

      Smart_Open_Script : constant String :=
        "mime=""$1""; count=""$2""; shift 2; for file in ""$@""; do :; done; "
        & "if [ -z ""$mime"" ] && command -v file >/dev/null 2>&1; then "
        & "mime=$(file --brief --mime-type -- ""$file"" 2>/dev/null); "
        & "fi; "
        & "desktop=""""; "
        & "if [ -n ""$mime"" ]; then "
        & "desktop=$(xdg-mime query default ""$mime"" 2>/dev/null); "
        & "fi; "
        & "if [ -n ""$desktop"" ]; then "
        & "seen=0; "
        & "for base in ""$@""; do "
        & "seen=$((seen + 1)); "
        & "if [ ""$seen"" -gt ""$count"" ]; then break; fi; "
        & "dir=""$base/applications""; "
        & "if [ -r ""$dir/$desktop"" ]; then "
        & "if command -v gio >/dev/null 2>&1; then "
        & "exec gio launch ""$dir/$desktop"" ""$file""; "
        & "fi; "
        & "if command -v gtk-launch >/dev/null 2>&1; then "
        & "exec gtk-launch ""${desktop%.desktop}"" ""$file""; "
        & "fi; "
        & "fi; "
        & "done; "
        & "fi; "
        & "exec xdg-open ""$file""";

      procedure Add (Value : String) is
      begin
         Arguments.Append (To_Unbounded_String (Value));
      end Add;
   begin
      Program := Null_Unbounded_String;
      Arguments := String_Vectors.Empty_Vector;
      --  The host comes from the body the build chose: COMSPEC is set on
      --  Linux machines running Wine, and /usr/bin/open on Linux is
      --  util-linux's, which means something else entirely.
      if Hostkit.Host.Current = Hostkit.Host.Windows then
         --  cmd is on PATH even where COMSPEC was cleared.
         Program := To_Unbounded_String
           (if Hostkit.Environment.Value ("COMSPEC", "") /= ""
            then Hostkit.Environment.Value ("COMSPEC", "")
            else "cmd");
         Add ("/c");
         Add ("start");
         Add ("");
         Add (Path_Token);
         return True;
      elsif Hostkit.Host.Current = Hostkit.Host.MacOS then
         if Locate ("open") = "" then
            return False;
         end if;
         Program := To_Unbounded_String ("open");
         Add (Path_Token);
         return True;
      elsif Locate ("xdg-open") /= "" or else Locate ("gio") /= "" then
         Program := To_Unbounded_String ("/bin/sh");
         Add ("-c");
         Add (Smart_Open_Script);
         Add ("--");
         Add (Mime_Type);
         --  Where the desktop keeps its entries, as files' "Open with" finds
         --  them: the XDG data folders, not three fixed ones. Counted, so the
         --  file still comes last.
         declare
            Bases : constant Hostkit.Fs.Path_List := Hostkit.Fs.Application_Data_Directories;
         begin
            Add (Ada.Strings.Fixed.Trim (Natural'Image (Bases'Length), Ada.Strings.Left));
            for Base of Bases loop
               Add (To_String (Base));
            end loop;
         end;
         Add (Path_Token);
         return True;
      end if;
      return False;
   end Default_Opener;

   function Default_Terminal return String is
      type Terminal_List is array (Positive range <>) of UString;

      Configured : constant String := Hostkit.Environment.Value ("TERMINAL", Default => "");

      --  Most to least preferred. Each is a bare name looked up on PATH, so
      --  one the host lacks costs nothing.
      Posix_Candidates : constant Terminal_List :=
        [To_Unbounded_String ("x-terminal-emulator"),
         To_Unbounded_String ("gnome-terminal"),
         To_Unbounded_String ("konsole"),
         To_Unbounded_String ("xfce4-terminal"),
         To_Unbounded_String ("tilix"),
         To_Unbounded_String ("terminator"),
         To_Unbounded_String ("alacritty"),
         To_Unbounded_String ("kitty"),
         To_Unbounded_String ("wezterm"),
         To_Unbounded_String ("ghostty"),
         To_Unbounded_String ("foot"),
         To_Unbounded_String ("urxvt"),
         To_Unbounded_String ("xterm")];

      --  Windows Terminal ships with Windows 11; PowerShell 7 is the modern
      --  shell; Windows PowerShell and cmd are always there.
      Windows_Candidates : constant Terminal_List :=
        [To_Unbounded_String ("wt"),
         To_Unbounded_String ("pwsh"),
         To_Unbounded_String ("powershell"),
         To_Unbounded_String ("cmd")];

      function First_Available (Candidates : Terminal_List) return String is
      begin
         for Candidate of Candidates loop
            if Is_Runnable (To_String (Candidate)) then
               return To_String (Candidate);
            end if;
         end loop;
         return "";
      end First_Available;
   begin
      if Configured /= "" and then Is_Runnable (Configured) then
         return Configured;
      end if;
      case Hostkit.Host.Current is
         when Hostkit.Host.Windows =>
            return First_Available (Windows_Candidates);
         when Hostkit.Host.MacOS =>
            --  A macOS terminal is an application bundle, not a program on
            --  PATH: `open` starts it, and Terminal.app comes with the system.
            return (if Is_Runnable ("open") then "open" else "");
         when Hostkit.Host.Linux | Hostkit.Host.Unsupported =>
            return First_Available (Posix_Candidates);
      end case;
   exception
      when others =>
         return "";
   end Default_Terminal;

   function Terminal_Command (Terminal : String; Directory : String) return String is
      --  A terminal that has to be told the directory, with Options before it.
      function Told (Program : String; Options : String_Vectors.Vector) return String is
         Arguments : String_Vectors.Vector := Options;
      begin
         Arguments.Append (To_Unbounded_String (Directory));
         return Hostkit.Shell.Command_Line (Program, Arguments);
      end Told;
   begin
      case Hostkit.Host.Current is
         when Hostkit.Host.MacOS =>
            --  Terminal.app has no working directory of its own to inherit:
            --  `open` hands it the folder, and it opens a window there.
            if Terminal = "open" then
               return Told ("open", [To_Unbounded_String ("-a"), To_Unbounded_String ("Terminal")]);
            end if;
         when Hostkit.Host.Windows =>
            --  Windows Terminal ignores the directory it was started in for
            --  its profile's (usually home); -d tells it otherwise.
            if Terminal = "wt" then
               return Told ("wt", [To_Unbounded_String ("-d")]);
            end if;
         when Hostkit.Host.Linux | Hostkit.Host.Unsupported =>
            null;
      end case;
      --  The others start where they are started. "cd /d" on cmd, because a
      --  plain cd does not cross to another drive.
      return
        (if Hostkit.Shell.Is_Command_Shell then "cd /d " else "cd ")
        & Hostkit.Shell.Quote (Directory)
        & " && " & Hostkit.Shell.Quote (Terminal);
   end Terminal_Command;

   function Open_Native (Path : String) return Boolean is
   begin
      return Hostkit.Native.Open_Native (Path) = Opened;
   end Open_Native;

   function Open_Native_Outcome (Path : String) return Open_Outcome is
   begin
      return Hostkit.Native.Open_Native (Path);
   end Open_Native_Outcome;

   ---------------
   -- End_Now --
   ---------------

   procedure End_Now (Status : Integer) is
   begin
      --  The host's own way out, which does not unwind and does not run an
      --  Ada finalizer. See the note in the specification for why a caller
      --  whose output has gone cannot afford the ordinary one.
      GNAT.OS_Lib.OS_Exit (Status);
   end End_Now;

end Hostkit.Process;
