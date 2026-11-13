with Hostkit.Windows_Command_Line;
with Ada.Calendar;
with Ada.Strings.Wide_Unbounded;

with Hostkit.Fs;
with Hostkit.Shell_Paths;
with Hostkit.Win32;
with Hostkit.Windows_Paths;
with Interfaces.C;

with System.Storage_Elements;
with System;

package body Hostkit.Native is
   use type Ada.Calendar.Time;
   use type Hostkit.Process.Cancel_Check;
   use type Hostkit.Process.Poll_Hook;
   use type Hostkit.Process.Started_Hook;

   use Hostkit.Win32;
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned_long;
   use type System.Address;
   use type System.Storage_Elements.Integer_Address;

   subtype C_DWord is Interfaces.C.unsigned_long;

   Wait_Failed  : constant C_DWord := 16#FFFF_FFFF#;
   Wait_Timeout : constant C_DWord := 16#0000_0102#;

   SW_Show_Normal : constant Interfaces.C.int := 1;

   type Startup_Info is record
      Cb              : C_DWord := 0;
      Reserved        : System.Address := System.Null_Address;
      Desktop         : System.Address := System.Null_Address;
      Title           : System.Address := System.Null_Address;
      X               : C_DWord := 0;
      Y               : C_DWord := 0;
      X_Size          : C_DWord := 0;
      Y_Size          : C_DWord := 0;
      X_Count_Chars   : C_DWord := 0;
      Y_Count_Chars   : C_DWord := 0;
      Fill_Attribute  : C_DWord := 0;
      Flags           : C_DWord := 0;
      Show_Window     : Interfaces.C.unsigned_short := 0;
      Reserved2_Count : Interfaces.C.unsigned_short := 0;
      Reserved2       : System.Address := System.Null_Address;
      Std_Input       : System.Address := System.Null_Address;
      Std_Output      : System.Address := System.Null_Address;
      Std_Error       : System.Address := System.Null_Address;
   end record
     with Convention => C;

   type Process_Information is record
      Process    : System.Address := System.Null_Address;
      Thread     : System.Address := System.Null_Address;
      Process_Id : C_DWord := 0;
      Thread_Id  : C_DWord := 0;
   end record
     with Convention => C;

   --  These layouts are a contract with the OS, not a description of our own record,
   --  so pin them: a field silently mis-sized here is a corrupt call rather than a
   --  compile error. 104 and 24 are the x86-64 layouts.
   pragma Compile_Time_Error
     (Startup_Info'Size /= 104 * 8, "STARTUPINFOW layout does not match the Win32 one");
   pragma Compile_Time_Error
     (Process_Information'Size /= 24 * 8, "PROCESS_INFORMATION layout does not match the Win32 one");

   function Create_Process
     (Application_Name   : System.Address;
      Command_Line       : System.Address;
      Process_Attributes : System.Address;
      Thread_Attributes  : System.Address;
      Inherit_Handles    : Interfaces.C.int;
      Creation_Flags     : C_DWord;
      Environment        : System.Address;
      Current_Directory  : System.Address;
      Startup            : access Startup_Info;
      Information        : access Process_Information)
      return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "CreateProcessW";

   function Get_Exit_Code_Process
     (Process   : System.Address;
      Exit_Code : access C_DWord)
      return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "GetExitCodeProcess";

   --  Returns > 32 on success. The value is an HINSTANCE for historical reasons only
   --  and means nothing else.
   function Shell_Execute
     (Window     : System.Address;
      Operation  : System.Address;
      File       : System.Address;
      Parameters : System.Address;
      Directory  : System.Address;
      Show       : Interfaces.C.int)
      return System.Address
     with Import => True, Convention => Stdcall, External_Name => "ShellExecuteW";

   function Wide (Value : String) return Wide_String is
     (Hostkit.Windows_Paths.From_UTF_8 (Value) & Wide_Character'Val (0));

   --  ASSOCSTR_COMMAND: the command line a file type's verb runs.
   Assoc_Str_Command : constant Interfaces.C.int := 1;

   --  ASSOCF_NOTRUNCATE: fail rather than cut a command short to the buffer.
   Assoc_F_No_Truncate : constant C_DWord := 16#20#;

   --  Answers an HRESULT: 0 when the command was found and fits.
   function Assoc_Query_String
     (Flags         : C_DWord;
      Kind          : Interfaces.C.int;
      Association   : System.Address;
      Extra         : System.Address;
      Output        : System.Address;
      Output_Length : access C_DWord)
      return Interfaces.C.long
     with Import => True, Convention => Stdcall, External_Name => "AssocQueryStringW";

   --  Answers the units written, its NUL included; 0 on failure, and more
   --  than Size when the room was too small.
   function Expand_Environment_Strings
     (Source      : System.Address;
      Destination : System.Address;
      Size        : C_DWord)
      return C_DWord
     with Import => True, Convention => Stdcall, External_Name => "ExpandEnvironmentStringsW";

   --  Windows has no zombie: a process that has exited is gone once its handles are
   --  closed, and everything here closes both before it returns.
   procedure Note_Child (Process_Id : Integer) is
      pragma Unreferenced (Process_Id);
   begin
      null;
   end Note_Child;

   procedure Reap_Finished_Children is
   begin
      null;
   end Reap_Finished_Children;

   function Supports_Raw_Command_Line return Boolean is
   begin
      return True;
   end Supports_Raw_Command_Line;

   function Run_Command_Line
     (Command     : String;
      Wait        : Boolean;
      Exit_Status : out Integer)
      return Boolean
   is
      --  CreateProcessW is documented to be able to write to this buffer, so it has to
      --  be our own mutable copy.
      Wide_Command : aliased Wide_String := Wide (Command);

      Startup     : aliased Startup_Info;
      Information : aliased Process_Information;
      Exit_Code   : aliased C_DWord := 0;
      Waited      : C_DWord;
      Created     : Interfaces.C.int;
      Ignored     : Interfaces.C.int;
   begin
      Exit_Status := -1;
      Startup.Cb := C_DWord (Startup_Info'Size / 8);

      Created :=
        Create_Process
          (Application_Name   => System.Null_Address,
           Command_Line       => Wide_Command'Address,
           Process_Attributes => System.Null_Address,
           Thread_Attributes  => System.Null_Address,
           Inherit_Handles    => 0,
           Creation_Flags     => 0,
           Environment        => System.Null_Address,
           Current_Directory  => System.Null_Address,
           Startup            => Startup'Access,
           Information        => Information'Access);

      if Created = 0 then
         return False;
      end if;

      if not Wait then
         --  Closing our handles does not end the process; it only says we are not
         --  watching it, which is what a detached launch means.
         Ignored := Close_Handle (Information.Thread);
         Ignored := Close_Handle (Information.Process);
         return True;
      end if;

      Waited := Wait_For_Single_Object (Information.Process, Infinite);

      if Waited /= Wait_Failed
        and then Get_Exit_Code_Process (Information.Process, Exit_Code'Access) /= 0
        and then Exit_Code /= Still_Active
      then
         Exit_Status := Integer (Exit_Code);
      end if;

      Ignored := Close_Handle (Information.Thread);
      Ignored := Close_Handle (Information.Process);

      return Exit_Status /= -1;
   exception
      when others =>
         return False;
   end Run_Command_Line;

   Create_Always     : constant C_DWord := 2;
   Start_Use_Handles : constant C_DWord := 16#0000_0100#;

   type Security_Attributes is record
      Length      : C_DWord := 0;
      Descriptor  : System.Address := System.Null_Address;
      Inheritable : Interfaces.C.int := 0;
   end record
     with Convention => C;

   --  Whichever of the three the caller gave us no file for, the child gets
   --  ours; see the note where STARTF_USESTDHANDLES is set.
   Std_Input_Handle  : constant C_DWord := 16#FFFF_FFF6#;  --  (DWORD) -10
   Std_Output_Handle : constant C_DWord := 16#FFFF_FFF5#;  --  -11
   Std_Error_Handle  : constant C_DWord := 16#FFFF_FFF4#;  --  -12

   function Terminate_Process
     (Process   : System.Address;
      Exit_Code : Interfaces.C.unsigned)
      return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "TerminateProcess";

   --  A job is Windows' process group: every process started by one in it
   --  is in it too, and ending the job ends them all.
   function Create_Job_Object
     (Attributes : System.Address;
      Name       : System.Address)
      return System.Address
     with Import => True, Convention => Stdcall, External_Name => "CreateJobObjectW";

   function Assign_Process_To_Job_Object
     (Job     : System.Address;
      Process : System.Address)
      return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "AssignProcessToJobObject";

   function Terminate_Job_Object
     (Job       : System.Address;
      Exit_Code : Interfaces.C.unsigned)
      return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "TerminateJobObject";

   --  JOBOBJECT_EXTENDED_LIMIT_INFORMATION, for its LimitFlags alone; the
   --  rest stays zero, which sets no limit.
   type Io_Counters is array (1 .. 6) of Interfaces.Unsigned_64 with Convention => C;

   type Extended_Limit_Information is record
      Per_Process_User_Time_Limit : Interfaces.Integer_64 := 0;
      Per_Job_User_Time_Limit     : Interfaces.Integer_64 := 0;
      Limit_Flags                 : C_DWord := 0;
      Minimum_Working_Set_Size    : Interfaces.C.size_t := 0;
      Maximum_Working_Set_Size    : Interfaces.C.size_t := 0;
      Active_Process_Limit        : C_DWord := 0;
      Affinity                    : Interfaces.C.size_t := 0;
      Priority_Class              : C_DWord := 0;
      Scheduling_Class            : C_DWord := 0;
      Io_Info                     : Io_Counters := [others => 0];
      Process_Memory_Limit        : Interfaces.C.size_t := 0;
      Job_Memory_Limit            : Interfaces.C.size_t := 0;
      Peak_Process_Memory_Used    : Interfaces.C.size_t := 0;
      Peak_Job_Memory_Used        : Interfaces.C.size_t := 0;
   end record with Convention => C;

   --  A wrong layout is not refused: SetInformationJobObject checks only
   --  the length. Pin it, so drift fails the build.
   pragma Compile_Time_Error
     (Extended_Limit_Information'Size /= 144 * 8,
      "Win32 JOBOBJECT_EXTENDED_LIMIT_INFORMATION must be 144 bytes on x64");

   Job_Object_Extended_Limit_Information : constant Interfaces.C.int := 9;
   Job_Object_Limit_Kill_On_Job_Close    : constant C_DWord := 16#0000_2000#;

   function Set_Information_Job_Object
     (Job    : System.Address;
      Class  : Interfaces.C.int;
      Info   : System.Address;
      Length : C_DWord)
      return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "SetInformationJobObject";

   --  Make Job one whose last handle closing ends every process still in
   --  it: what the program started is then ended when the program ends --
   --  Run_Captured closes the job once it has -- and when the caller dies, as
   --  the system closes the caller's handles. Without it, closing the job
   --  lets them run on. A job that will not take the limit still stops the
   --  whole group on a deadline, so it is kept either way.
   procedure Kill_On_Close (Job : System.Address) is
      Limits  : aliased Extended_Limit_Information;
      Ignored : Interfaces.C.int;
   begin
      Limits.Limit_Flags := Job_Object_Limit_Kill_On_Job_Close;
      Ignored := Set_Information_Job_Object
        (Job, Job_Object_Extended_Limit_Information, Limits'Address,
         C_DWord (Extended_Limit_Information'Size / 8));
   end Kill_On_Close;

   function Resume_Thread (Thread : System.Address) return C_DWord
     with Import => True, Convention => Stdcall, External_Name => "ResumeThread";

   --  Started suspended, so that it is in its job before it can start
   --  anything of its own.
   Create_Suspended : constant C_DWord := 16#0000_0004#;

   --  Run a program with its output captured, under a deadline.
   --
   --  Windows has no fork: CreateProcessW takes the redirections up front, as handles in
   --  STARTUPINFO. They must be inheritable, and bInheritHandles must be true, or the
   --  child gets none of them and its output goes nowhere.
   --
   --  The wait is in slices rather than one INFINITE block, so that a cancellation is
   --  noticed while it is still worth noticing. A program that will not stop is stopped:
   --  there is no SIGTERM to ask politely with, so TerminateProcess is the whole of it.
   function Run_Captured
     (Program           : String;
      Arguments         : String_Vectors.Vector;
      Working_Directory : String;
      Stdin_Path        : String;
      Stdout_Path       : String;
      Stderr_Path       : String;
      Timeout_Ms        : Natural;
      Cancelled         : Hostkit.Process.Cancel_Check;
      Poll              : Hostkit.Process.Poll_Hook;
      Started_Notice    : Hostkit.Process.Started_Hook;
      Whole_Group       : Boolean := False;
      Clean_Wrapper     : Boolean := False)
      return Hostkit.Process.Process_Outcome
   is
      --  No shell stands for the group here: nothing to clean.
      pragma Unreferenced (Clean_Wrapper);
      --  CreateProcessW takes a command line, not a vector, so the arguments have
      --  to be quoted into one with the C runtime rules every Windows program
      --  parses back out. That quoting is pure text and easy to get subtly wrong,
      --  so it lives in Hostkit.Windows_Command_Line where it is unit-tested.
      function Command_Line return String is
        (Hostkit.Windows_Command_Line.Build (Program, Arguments));

      function Capture (Path : String) return System.Address is
         Wide_Path : aliased Wide_String := Hostkit.Windows_Paths.Native (Path);
         Security  : aliased Security_Attributes;
      begin
         if Path = "" then
            return Invalid_Handle_Value;
         end if;

         Security.Length := C_DWord (Security_Attributes'Size / 8);
         Security.Inheritable := 1;

         return Create_File
                  (Name       => Wide_Path'Address,
                   Access_Way => Generic_Write,
                   Share      => File_Share_Read,
                   Security   => Security'Address,
                   Creation   => Create_Always,
                   Flags      => File_Attribute_Normal,
                   Template   => System.Null_Address);
      end Capture;

      --  The other direction: a file the child reads, rather than one it
      --  writes. Opening it here rather than in the child is not a choice --
      --  Windows has no fork, so every redirection has to exist as a handle
      --  before CreateProcessW is called.
      function Feed (Path : String) return System.Address is
         Wide_Path : aliased Wide_String := Hostkit.Windows_Paths.Native (Path);
         Security  : aliased Security_Attributes;
      begin
         if Path = "" then
            return Invalid_Handle_Value;
         end if;

         Security.Length := C_DWord (Security_Attributes'Size / 8);
         Security.Inheritable := 1;

         return Create_File
                  (Name       => Wide_Path'Address,
                   Access_Way => Generic_Read,
                   Share      => File_Share_Read,
                   Security   => Security'Address,
                   Creation   => Open_Existing,
                   Flags      => File_Attribute_Normal,
                   Template   => System.Null_Address);
      end Feed;

      Wide_Command : aliased Wide_String := Wide (Command_Line);

      --  CreateProcessW takes no \\?\ form and no directory past 258
      --  characters: a longer one goes by its short (8.3) name.
      Dir_Usable        : Boolean;
      Ignored_Shortened : Boolean;
      Wide_Dir          : aliased constant Wide_String :=
        Hostkit.Shell_Paths.For_Shell
          (Working_Directory, Hostkit.Shell_Paths.Directory_Limit, Dir_Usable, Ignored_Shortened);

      In_Handle  : System.Address := Feed (Stdin_Path);
      Out_Handle : System.Address := Capture (Stdout_Path);

      --  One file for both is one handle: two would each write from their
      --  own place, over each other.
      Err_Handle : System.Address :=
        (if Stderr_Path /= "" and then Stderr_Path = Stdout_Path then Invalid_Handle_Value
         else Capture (Stderr_Path));
      Shared_Err : constant Boolean := Stderr_Path /= "" and then Stderr_Path = Stdout_Path;

      Startup     : aliased Startup_Info;
      Information : aliased Process_Information;
      Exit_Code   : aliased C_DWord := 0;
      Started_At  : constant Ada.Calendar.Time := Ada.Calendar.Clock;
      Killed      : Boolean := False;
      Waited      : C_DWord;
      Ignored     : Interfaces.C.int;
      Result      : Hostkit.Process.Process_Outcome;

      --  The job it and what it starts are in, where the whole of it is to
      --  be stopped; null otherwise, or where no job could be made.
      Job         : System.Address :=
        (if Whole_Group then Create_Job_Object (System.Null_Address, System.Null_Address)
         else System.Null_Address);

      function Should_Stop return Boolean is
         Elapsed : constant Duration := Ada.Calendar.Clock - Started_At;
      begin
         if Cancelled /= null and then Cancelled.all then
            return True;
         end if;

         return Timeout_Ms > 0 and then Elapsed * 1000.0 >= Duration (Timeout_Ms);
      end Should_Stop;

      procedure Close_Captures is
      begin
         if In_Handle /= Invalid_Handle_Value then
            Ignored := Close_Handle (In_Handle);
            In_Handle := Invalid_Handle_Value;
         end if;

         if Out_Handle /= Invalid_Handle_Value then
            Ignored := Close_Handle (Out_Handle);
            Out_Handle := Invalid_Handle_Value;
         end if;

         if Err_Handle /= Invalid_Handle_Value then
            Ignored := Close_Handle (Err_Handle);
            Err_Handle := Invalid_Handle_Value;
         end if;
      end Close_Captures;
   begin
      Startup.Cb := C_DWord (Startup_Info'Size / 8);
      if Job /= System.Null_Address then
         Kill_On_Close (Job);
      end if;

      --  Told to read a file and unable to open it: the child must not silently
      --  get ours instead. See the note on Stdin_Path in Hostkit.Process.
      if Stdin_Path /= "" and then In_Handle = Invalid_Handle_Value then
         Close_Captures;
         return Result;
      end if;

      --  A working directory with no form CreateProcessW takes (short names
      --  disabled on its volume) is refused rather than dropped: the child
      --  would run somewhere else.
      if Working_Directory /= "" and then not Dir_Usable then
         Close_Captures;
         if Job /= System.Null_Address then
            Ignored := Close_Handle (Job);
         end if;
         return Result;
      end if;

      if In_Handle /= Invalid_Handle_Value
        or else Out_Handle /= Invalid_Handle_Value
        or else Err_Handle /= Invalid_Handle_Value
      then
         --  STARTF_USESTDHANDLES is all or nothing: the child takes all three
         --  from here, so a stream we were given no file for has to be filled
         --  in with the one we have ourselves. Leaving it unset does not mean
         --  "inherit" -- it means the child gets no handle at all for that
         --  stream, and a program that writes to its standard error then
         --  writes to nothing.
         Startup.Flags := Start_Use_Handles;
         Startup.Std_Input :=
           (if In_Handle /= Invalid_Handle_Value then In_Handle
            else Get_Std_Handle (Std_Input_Handle));
         Startup.Std_Output :=
           (if Out_Handle /= Invalid_Handle_Value then Out_Handle
            else Get_Std_Handle (Std_Output_Handle));
         Startup.Std_Error :=
           (if Shared_Err and then Out_Handle /= Invalid_Handle_Value then Out_Handle
            elsif Err_Handle /= Invalid_Handle_Value then Err_Handle
            else Get_Std_Handle (Std_Error_Handle));
      end if;

      if Create_Process
           (Application_Name   => System.Null_Address,
            Command_Line       => Wide_Command'Address,
            Process_Attributes => System.Null_Address,
            Thread_Attributes  => System.Null_Address,
            --  The capture handles are inheritable and this is what lets the child have
            --  them. Without it its output goes nowhere and the files stay empty.
            Inherit_Handles    => 1,
            Creation_Flags     => (if Job /= System.Null_Address then Create_Suspended else 0),
            Environment        => System.Null_Address,
            Current_Directory  =>
              (if Working_Directory = "" then System.Null_Address else Wide_Dir'Address),
            Startup            => Startup'Access,
            Information        => Information'Access) = 0
      then
         Close_Captures;
         if Job /= System.Null_Address then
            Ignored := Close_Handle (Job);
         end if;
         return Result;
      end if;

      --  Into its job, then let go: a process that cannot be put in one
      --  runs as a lone process would, and is stopped alone.
      if Job /= System.Null_Address then
         if Assign_Process_To_Job_Object (Job, Information.Process) = 0 then
            Ignored := Close_Handle (Job);
            Job := System.Null_Address;
         end if;
         --  One that cannot be let go would wait for ever: ended now.
         if Resume_Thread (Information.Thread) = C_DWord'Last then
            Ignored := Terminate_Process (Information.Process, 1);
         end if;
      end if;

      Result.Started := True;

      if Started_Notice /= null then
         Started_Notice.all (Integer (Information.Process_Id));
      end if;

      --  Ours are closed straight away: the child has its own copies, and the file would
      --  otherwise stay open until we exited.
      Close_Captures;

      loop
         --  In slices, so a cancellation is noticed rather than waited out.
         Waited := Wait_For_Single_Object (Information.Process, 5);

         exit when Waited /= Wait_Timeout;

         if not Killed and then Should_Stop then
            Killed := True;
            --  Nothing to ask with here. TerminateProcess is the request and the answer;
            --  a job's end is its whole group's.
            if Job /= System.Null_Address then
               Ignored := Terminate_Job_Object (Job, 1);
            else
               Ignored := Terminate_Process (Information.Process, 1);
            end if;
         end if;

         if Poll /= null then
            Poll.all;
         end if;
      end loop;

      if Get_Exit_Code_Process (Information.Process, Exit_Code'Access) /= 0
        and then Exit_Code /= Still_Active
      then
         Result.Exit_Status := Integer (Exit_Code);
      end if;

      Result.Timed_Out := Killed;

      Ignored := Close_Handle (Information.Thread);
      Ignored := Close_Handle (Information.Process);
      if Job /= System.Null_Address then
         Ignored := Close_Handle (Job);
      end if;

      return Result;
   end Run_Captured;

   --  Windows has no signal to send. Open the process and end it: that is the whole of
   --  what "ask it to stop" can mean here.
   --  Windows has no call that replaces a running image. CreateProcess makes a
   --  *new* process, so anything built on it changes the process id and leaves
   --  the original waiting or gone -- which is what a caller reaching for this
   --  is trying to avoid. Refused rather than emulated.
   function Become_Program
     (Program   : String;
      Arguments : String_Vectors.Vector)
      return Boolean
   is
      pragma Unreferenced (Program, Arguments);
   begin
      return False;
   end Become_Program;

   function Request_Stop (Process_Id : Integer) return Boolean is
      Process_Terminate : constant C_DWord := 16#0001#;

      function Open_Process
        (Access_Way : C_DWord;
         Inherit    : Interfaces.C.int;
         Process_Id : C_DWord)
         return System.Address
        with Import => True, Convention => Stdcall, External_Name => "OpenProcess";

      Handle  : System.Address;
      Stopped : Interfaces.C.int;
      Ignored : Interfaces.C.int;
   begin
      Handle := Open_Process (Process_Terminate, 0, C_DWord (Process_Id));

      if Handle = System.Null_Address then
         return False;
      end if;

      Stopped := Terminate_Process (Handle, 1);
      Ignored := Close_Handle (Handle);

      return Stopped /= 0;
   exception
      when others =>
         return False;
   end Request_Stop;

   --  OpenProcess for the least it can ask, then its exit code: STILL_ACTIVE (259) while it
   --  runs. A process that is not there fails to open with ERROR_INVALID_PARAMETER (87); one
   --  we may not open fails with access denied (5), and is there.
   function Presence_Of (Process_Id : Integer) return Hostkit.Process.Presence is
      Query_Limited_Information : constant C_DWord := 16#1000#;
      Access_Denied             : constant C_DWord := 5;
      Invalid_Parameter         : constant C_DWord := 87;

      function Open_Process
        (Access_Way : C_DWord;
         Inherit    : Interfaces.C.int;
         Process_Id : C_DWord)
         return System.Address
        with Import => True, Convention => Stdcall, External_Name => "OpenProcess";

      function Get_Exit_Code_Process
        (Handle : System.Address; Code : access C_DWord) return Interfaces.C.int
        with Import => True, Convention => Stdcall, External_Name => "GetExitCodeProcess";

      Handle  : System.Address;
      Code    : aliased C_DWord := 0;
      Read    : Interfaces.C.int;
      Ignored : Interfaces.C.int;
   begin
      Handle := Open_Process (Query_Limited_Information, 0, C_DWord (Process_Id));
      if Handle = System.Null_Address then
         declare
            Error : constant C_DWord := Get_Last_Error;
         begin
            return (if Error = Invalid_Parameter then Hostkit.Process.Absent
                    elsif Error = Access_Denied then Hostkit.Process.Present
                    else Hostkit.Process.Unknown);
         end;
      end if;
      Read := Get_Exit_Code_Process (Handle, Code'Access);
      Ignored := Close_Handle (Handle);
      if Read = 0 then
         return Hostkit.Process.Unknown;
      end if;
      return (if Code = Still_Active then Hostkit.Process.Present else Hostkit.Process.Absent);
   exception
      when others =>
         return Hostkit.Process.Unknown;
   end Presence_Of;

   --  Windows cannot poll a pipe descriptor -- poll and select are for sockets. Turn the CRT
   --  descriptor into the pipe HANDLE and ask the pipe directly whether bytes are waiting
   --  (PeekNamedPipe), in a short loop until they are or the deadline passes. Write readiness
   --  is reported at once: a pipe write to a helper rarely blocks, and there is no cheap ask.
   function Wait_FD
     (FD         : Integer;
      For_Write  : Boolean;
      Timeout_MS : Integer)
      return Hostkit.Process.Wait_Outcome
   is
      Handle    : constant System.Address := Get_Osfhandle (Interfaces.C.int (FD));
      Available : aliased C_DWord := 0;
      Waited    : Integer := 0;
      Slice     : constant Integer := 10;  --  ms between peeks
   begin
      if FD < 0
        or else Handle = Invalid_Handle_Value
      then
         return Hostkit.Process.Wait_Error;
      end if;

      --  Nothing cheap to test for writability; a helper pipe write does not usually block.
      if For_Write then
         return Hostkit.Process.Wait_Ready;
      end if;

      loop
         Available := 0;
         if Peek_Named_Pipe
              (Handle, System.Null_Address, 0, null, Available'Access, null) = 0
         then
            --  The pipe is gone (the helper exited). That is a readable event -- the caller's
            --  next read returns end-of-file -- not a wait error.
            return Hostkit.Process.Wait_Ready;
         end if;

         if Available > 0 then
            return Hostkit.Process.Wait_Ready;
         end if;

         exit when Timeout_MS >= 0 and then Waited >= Timeout_MS;
         Sleep (C_DWord (Slice));
         Waited := Waited + Slice;
      end loop;

      return Hostkit.Process.Wait_Timed_Out;
   exception
      when others =>
         return Hostkit.Process.Wait_Error;
   end Wait_FD;

   function Native_Backend_Label return String is
   begin
      return "Windows/CreateProcess-TerminateProcess";
   end Native_Backend_Label;

   function Current_User_Id (User_Id : out Hostkit.Metadata.Account_Id) return Boolean is
   begin
      User_Id := 0;
      return False;
   end Current_User_Id;

   function Current_Group_Id (Group_Id : out Hostkit.Metadata.Account_Id) return Boolean is
   begin
      Group_Id := 0;
      return False;
   end Current_Group_Id;

   function Current_Supplementary_Group_Ids
     (Groups : out Hostkit.Process.Group_Id_List;
      Last   : out Natural)
      return Boolean
   is
   begin
      for Index in Groups'Range loop
         Groups (Index) := 0;
      end loop;
      Last := 0;
      return False;
   end Current_Supplementary_Group_Ids;

   function User_Group_Ids
     (User_Name : String;
      Groups    : out Hostkit.Process.Group_Id_List;
      Last      : out Natural)
      return Boolean
   is
      pragma Unreferenced (User_Name);
   begin
      for Index in Groups'Range loop
         Groups (Index) := 0;
      end loop;
      Last := 0;
      return False;
   end User_Group_Ids;

   --  The command line Path's type is associated with, Target standing for
   --  the file in it, or "" when there is none this can complete: no
   --  extension, no ASSOCSTR_COMMAND (a type a packaged app handles through
   --  DelegateExecute has none), or a placeholder other than the file's own
   --  (%1, %L, %V) and its arguments (%*) -- %I is an item ID list, which
   --  only ShellExecuteW can supply.
   function Associated_Command (Path : String; Target : Wide_String) return String is
      use type Interfaces.C.long;

      Dot : Natural := 0;
   begin
      for Index in reverse Path'Range loop
         exit when Path (Index) in '/' | '\';
         if Path (Index) = '.' then
            Dot := Index;
            exit;
         end if;
      end loop;
      if Dot = 0 or else Dot = Path'Last then
         return "";
      end if;

      declare
         Extension : aliased constant Wide_String := Wide (Path (Dot .. Path'Last));
         Verb      : aliased constant Wide_String := Wide ("open");
         Room      : aliased Wide_String (1 .. 4_096) := [others => Wide_Character'Val (0)];
         Size      : aliased C_DWord := Room'Length;
         Expanded  : aliased Wide_String (1 .. 8_192) := [others => Wide_Character'Val (0)];
         Written   : C_DWord;
      begin
         if Assoc_Query_String
              (Assoc_F_No_Truncate, Assoc_Str_Command, Extension'Address, Verb'Address, Room'Address, Size'Access)
           /= 0
         then
            return "";
         end if;
         --  REG_EXPAND_SZ commands name %SystemRoot% and the like.
         Written := Expand_Environment_Strings (Room'Address, Expanded'Address, Expanded'Length);
         if Written <= 1 or else Written > Expanded'Length then
            return "";
         end if;

         declare
            Template : constant Wide_String := Expanded (1 .. Natural (Written) - 1);
            Result   : Ada.Strings.Wide_Unbounded.Unbounded_Wide_String;
            Placed   : Boolean := False;
            Index    : Positive := Template'First;
         begin
            while Index <= Template'Last loop
               if Template (Index) = '%' and then Index < Template'Last then
                  case Template (Index + 1) is
                     when '1' | 'L' | 'l' | 'V' | 'v' =>
                        Ada.Strings.Wide_Unbounded.Append (Result, Target);
                        Placed := True;
                     when '*' =>
                        null;
                     when '%' =>
                        Ada.Strings.Wide_Unbounded.Append (Result, '%');
                     when others =>
                        return "";
                  end case;
                  Index := Index + 2;
               else
                  Ada.Strings.Wide_Unbounded.Append (Result, Template (Index));
                  Index := Index + 1;
               end if;
            end loop;
            if not Placed then
               Ada.Strings.Wide_Unbounded.Append (Result, " """ & Target & """");
            end if;
            return Hostkit.Windows_Paths.To_UTF_8 (Ada.Strings.Wide_Unbounded.To_Wide_String (Result));
         end;
      end;
   exception
      when others =>
         return "";
   end Associated_Command;

   function Open_Native (Path : String) return Hostkit.Process.Open_Outcome is
      use type Hostkit.Fs.Entry_Kind;

      Operation : aliased Wide_String := Wide ("open");
      Usable    : Boolean;
      Shortened : Boolean;
      Result    : System.Address;
   begin
      if Path = "" then
         return Hostkit.Process.Open_Failed;
      end if;

      declare
         --  ShellExecuteW takes no path past 259 characters and no \\?\ form:
         --  a longer one goes by its short (8.3) name, and without one
         --  (short names disabled on its volume) nothing can open it.
         Target : aliased constant Wide_String :=
           Hostkit.Shell_Paths.For_Shell (Path, Hostkit.Shell_Paths.Shell_Limit, Usable, Shortened);
      begin
         if not Usable then
            return Hostkit.Process.Open_Path_Too_Long;
         end if;

         --  The short name is a real path, but the shell may hand it on to a
         --  handler that resolves it back to the long one and fails there;
         --  the associated command, run directly, gets the short name
         --  itself. A folder, or a type with no such command, still goes
         --  through the shell.
         if Shortened and then Hostkit.Fs.Kind_Of (Path) /= Hostkit.Fs.Directory_Entry then
            declare
               Command        : constant String := Associated_Command (Path, Target (Target'First .. Target'Last - 1));
               Ignored_Status : Integer;
            begin
               if Command /= ""
                 and then Run_Command_Line (Command, Wait => False, Exit_Status => Ignored_Status)
               then
                  return Hostkit.Process.Opened;
               end if;
            end;
         end if;

         Result :=
           Shell_Execute
             (Window     => System.Null_Address,
              Operation  => Operation'Address,
              File       => Target'Address,
              Parameters => System.Null_Address,
              Directory  => System.Null_Address,
              Show       => SW_Show_Normal);
      end;

      return
        (if System.Storage_Elements.To_Integer (Result) > 32
         then Hostkit.Process.Opened
         else Hostkit.Process.Open_Failed);
   exception
      when others =>
         return Hostkit.Process.Open_Failed;
   end Open_Native;

end Hostkit.Native;
