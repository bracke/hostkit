with Ada.Strings.Unbounded;

with Hostkit.Shell_Paths;
with Hostkit.Win32;
with Hostkit.Windows_Command_Line;
with Hostkit.Windows_Paths;

with Interfaces.C;

with System.Storage_Elements;
with System;

package body Hostkit.Spawn is

   use Ada.Strings.Unbounded;
   use Hostkit.Win32;
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned_long;
   use type System.Address;
   use type Hostkit.Descriptors.Descriptor;

   subtype C_DWord is Interfaces.C.unsigned_long;

   Wait_Failed  : constant C_DWord := 16#FFFF_FFFF#;
   Wait_Timeout : constant C_DWord := 16#0000_0102#;

   Startf_Use_Std_Handles : constant C_DWord := 16#0000_0100#;
   Create_Unicode_Environment : constant C_DWord := 16#0000_0400#;
   Create_Suspended           : constant C_DWord := 16#0000_0004#;

   --  CreateProcess failure codes worth telling apart, so that a shell can say
   --  which of the four mistakes a user made rather than "it did not run".
   Error_File_Not_Found    : constant C_DWord := 2;
   Error_Path_Not_Found    : constant C_DWord := 3;
   Error_Access_Denied     : constant C_DWord := 5;
   Error_Bad_Format        : constant C_DWord := 11;
   Error_Directory         : constant C_DWord := 267;
   Error_Invalid_Name      : constant C_DWord := 123;

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

   --  STARTUPINFOEXW: the ordinary one with a pointer to an attribute list
   --  after it. The attribute list is where a pseudo-console, and the list of
   --  handles the child inherits, are handed over.
   type Extended_Startup_Info is record
      Startup        : Startup_Info;
      Attribute_List : System.Address := System.Null_Address;
   end record
     with Convention => C;

   --  These layouts are a contract with the OS, not a description of our own
   --  records, so pin them: a field silently mis-sized is a corrupt call rather
   --  than a compile error. 104, 112 and 24 are the x86-64 layouts.
   pragma Compile_Time_Error
     (Startup_Info'Size /= 104 * 8, "STARTUPINFOW layout does not match the Win32 one");
   pragma Compile_Time_Error
     (Extended_Startup_Info'Size /= 112 * 8, "STARTUPINFOEXW layout does not match the Win32 one");
   pragma Compile_Time_Error
     (Process_Information'Size /= 24 * 8, "PROCESS_INFORMATION layout does not match the Win32 one");

   --  CreateProcessW, taking the extended startup record: every child is
   --  started with an attribute list naming what it inherits.
   function Create_Process_Extended
     (Application_Name   : System.Address;
      Command_Line       : System.Address;
      Process_Attributes : System.Address;
      Thread_Attributes  : System.Address;
      Inherit_Handles    : Interfaces.C.int;
      Creation_Flags     : C_DWord;
      Environment        : System.Address;
      Current_Directory  : System.Address;
      Startup            : access Extended_Startup_Info;
      Information        : access Process_Information)
      return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "CreateProcessW";

   --  A Job Object is Windows' process-tree primitive. Starting suspended and
   --  assigning before resume closes the race in which a child could create a
   --  descendant before it belongs to the tree.
   function Create_Job_Object
     (Attributes : System.Address;
      Name       : System.Address) return System.Address
     with Import => True, Convention => Stdcall, External_Name => "CreateJobObjectW";

   function Assign_Process_To_Job_Object
     (Job     : System.Address;
      Process : System.Address) return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "AssignProcessToJobObject";

   function Terminate_Job_Object
     (Job       : System.Address;
      Exit_Code : C_DWord) return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "TerminateJobObject";

   function Terminate_Process
     (Process   : System.Address;
      Exit_Code : C_DWord) return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "TerminateProcess";

   function Resume_Thread (Thread : System.Address) return C_DWord
     with Import => True, Convention => Stdcall, External_Name => "ResumeThread";

   --  An exit code as this host gives it, in the range Ada asks for.
   --
   --  Windows exit codes are unsigned and thirty-two bits wide, and the ones
   --  the system itself uses are at the top of that range: a process ended by
   --  the console control path exits with 0xC000013A. Converting that to
   --  Integer overflows and *raises*, which is not an answer -- and a wait
   --  that raises is a wait a caller cannot use to find out that its child is
   --  gone. Measured: a probe closing a pseudo-console got Constraint_Error
   --  out of this function rather than a status.
   --
   --  Read as two's complement, which is how every tool on this host shows
   --  those numbers -- 0xC000013A is -1073741510 -- so a caller comparing
   --  against what a Windows debugger or `echo %ERRORLEVEL%` said sees the
   --  same value.
   function Held (Code : C_DWord) return Integer;

   function Held (Code : C_DWord) return Integer is
   begin
      if Code <= C_DWord (Integer'Last) then
         return Integer (Code);
      end if;

      return Integer (Long_Long_Integer (Code) - 2 ** 32);
   end Held;

   function Get_Exit_Code_Process
     (Process : System.Address; Exit_Code : access C_DWord) return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "GetExitCodeProcess";

   function Wide (Value : String) return Wide_String
   is (Hostkit.Windows_Paths.From_UTF_8 (Value) & Wide_Character'Val (0));

   function To_Handle (Item : Hostkit.Descriptors.Descriptor) return System.Address
   is (System.Storage_Elements.To_Address
         (System.Storage_Elements.Integer_Address
            (Hostkit.Descriptors.Native_Value (Item))));

   --  The process handle is kept in the Id field, not the process id. Windows
   --  needs the handle to wait or to read an exit code, and a process id there
   --  is only a number -- reusable the moment the process goes, exactly like a
   --  POSIX pid. The real process id goes in the Group field, which this host
   --  has no other use for -- it has no process groups -- and Process_Id below
   --  reports it from there. That double duty is a wart this host forces, and
   --  is why the fields are opaque.

   function Outcome_For_Error (Code : C_DWord) return Spawn_Outcome;

   -----------------------
   -- Outcome_For_Error --
   -----------------------

   function Outcome_For_Error (Code : C_DWord) return Spawn_Outcome is
   begin
      if Code = Error_File_Not_Found
        or else Code = Error_Path_Not_Found
        or else Code = Error_Invalid_Name
      then
         return Spawn_Not_Found;
      elsif Code = Error_Access_Denied then
         return Spawn_Denied;
      elsif Code = Error_Bad_Format or else Code = Error_Directory then
         return Spawn_Not_Executable;
      else
         return Spawn_Failed;
      end if;
   end Outcome_For_Error;

   --------------
   -- Is_Valid --
   --------------

   function Is_Valid (Item : Process_Handle) return Boolean is
   begin
      return Item.Id > 0;
   end Is_Valid;

   ----------------
   -- Process_Id --
   ----------------

   function Process_Id (Item : Process_Handle) return Integer is
   begin
      return Integer (Item.Group);
   end Process_Id;

   --------------
   -- Group_Id --
   --------------

   function Group_Id (Item : Process_Handle) return Integer is
      pragma Unreferenced (Item);
   begin
      --  Windows has no process groups in the POSIX sense. -1 is a refusal, not
      --  a group nobody is in: a caller that passed it to
      --  Hostkit.Signals.Send_To_Group would be refused there too.
      return -1;
   end Group_Id;

   ------------------------
   -- Supports_Sessions --
   ------------------------

   --  There is nothing this shape here: a console is attached to a process
   --  rather than controlled by a session, and what a child gets is decided by
   --  how it was created rather than by an ioctl it can make afterwards. False
   --  is a refusal to guess, which is what a caller asks this in order to
   --  avoid.
   function Supports_Sessions return Boolean is (False);

   -----------
   -- Start --
   -----------

   function Start
     (Program      : String;
      Arguments    : String_Vectors.Vector;
      With_Options : Options;
      Item         : out Process_Handle) return Spawn_Outcome
   is
      --  CreateProcessW takes a command line, not a vector, and rebuilds the
      --  vector from it inside the child. Hostkit.Windows_Command_Line does the
      --  quoting that survives that round trip; doing it by hand here is how an
      --  argument with a quote or a trailing backslash arrives as two.
      Command : constant String :=
        Hostkit.Windows_Command_Line.Build (Program, Arguments);

      --  CreateProcessW is documented to be able to write to this buffer, so it
      --  has to be a variable of ours rather than a constant.
      Wide_Command : aliased Wide_String := Wide (Command);
      --  CreateProcessW takes no \\?\ form and no directory past 258
      --  characters: a longer one goes by its short (8.3) name.
      Dir_Usable        : Boolean;
      Ignored_Shortened : Boolean;
      Wide_Dir          : aliased constant Wide_String :=
        Hostkit.Shell_Paths.For_Shell
          (To_String (With_Options.Working_Directory), Hostkit.Shell_Paths.Directory_Limit,
           Dir_Usable, Ignored_Shortened);

      Startup     : aliased Startup_Info;
      Information : aliased Process_Information;

      Environment_Block : Unbounded_String;

      --  A replacement environment is passed whenever one is asked for, empty
      --  or not. A null block is not "no variables": CreateProcessW reads it as
      --  "inherit this process's", so an empty replacement used to hand the
      --  child the parent's whole environment -- the opposite of what was asked,
      --  and of what Linux and macOS do with the same request.
      Use_Environment : constant Boolean := With_Options.Replace_Environment;

      Job : System.Address :=
        (if With_Options.Group = Group_New
         then Create_Job_Object (System.Null_Address, System.Null_Address)
         else System.Null_Address);

      procedure Close_Job is
         Ignored : Interfaces.C.int;
         pragma Unreferenced (Ignored);
      begin
         if Job /= System.Null_Address then
            Ignored := Close_Handle (Job);
            Job := System.Null_Address;
         end if;
      end Close_Job;
   begin
      Item := Invalid_Process;

      if With_Options.Group = Group_New and then Job = System.Null_Address then
         return Spawn_Failed;
      end if;

      --  Asked for something this host does not have. Refused rather than
      --  started without it: a child that could be interrupted through its
      --  terminal on one host and not on another is the difference this crate
      --  exists to make visible.
      if With_Options.Controlling_Terminal /= Hostkit.Descriptors.Invalid then
         Close_Job;
         return Spawn_Failed;
      end if;

      --  A working directory with no form CreateProcessW takes -- past 258
      --  characters on a volume with short names disabled -- is the "working
      --  directory that does not exist" of Spawn_Failed: refused, rather than
      --  started somewhere else.
      if With_Options.Working_Directory /= Null_Unbounded_String and then not Dir_Usable then
         Close_Job;
         return Spawn_Failed;
      end if;

      Startup.Cb := C_DWord (Startup_Info'Size / 8);

      --  STARTF_USESTDHANDLES is all or nothing: the child takes all three
      --  handles from here or none of them, so any stream the caller left
      --  Invalid is filled in with this process's own.
      if Is_Attached (With_Options.Console) then
         --  A pseudo-console gives the child its handles, and what must not
         --  happen is the child keeping this process's: a child's standard
         --  handles are copied from its parent's before anything else decides
         --  them, and attaching to a console fills in only what is not already
         --  there. A parent whose own output is a pipe -- every parent under a
         --  build service -- would hand the child that pipe, and the child
         --  would write into it while the console it was given sat untouched.
         --
         --  Said here as three handles of nothing, which is what stops the
         --  copy. The other way is to take this process's own handles away for
         --  the length of the call and put them back afterwards, and that
         --  works too; what it also has is a window in which this process has
         --  no output of its own, and a thread writing during that window
         --  writes to nothing. This has no window.
         Startup.Flags := Startup.Flags + Startf_Use_Std_Handles;
         Startup.Std_Input := System.Null_Address;
         Startup.Std_Output := System.Null_Address;
         Startup.Std_Error := System.Null_Address;

      elsif With_Options.Input /= Hostkit.Descriptors.Invalid
        or else With_Options.Output /= Hostkit.Descriptors.Invalid
        or else With_Options.Error_Output /= Hostkit.Descriptors.Invalid
      then
         Startup.Flags := Startup.Flags + Startf_Use_Std_Handles;

         Startup.Std_Input :=
           To_Handle (if With_Options.Input /= Hostkit.Descriptors.Invalid
                      then With_Options.Input
                      else Hostkit.Descriptors.Standard_Input);
         Startup.Std_Output :=
           To_Handle (if With_Options.Output /= Hostkit.Descriptors.Invalid
                      then With_Options.Output
                      else Hostkit.Descriptors.Standard_Output);
         Startup.Std_Error :=
           To_Handle (if With_Options.Error_Output /= Hostkit.Descriptors.Invalid
                      then With_Options.Error_Output
                      else Hostkit.Descriptors.Standard_Error);
      end if;

      --  The environment block is one buffer of NAME=VALUE, each terminated by
      --  a NUL, with a second NUL at the end -- not an array of pointers as on
      --  POSIX. An empty block is still two NULs: the documented terminator is
      --  an empty string's NUL followed by the block's, and a lone NUL leaves
      --  the host reading past the end of the buffer for the second.
      if Use_Environment then
         for Entry_Text of With_Options.Environment loop
            Append (Environment_Block, To_String (Entry_Text));
            Append (Environment_Block, Character'Val (0));
         end loop;
         if With_Options.Environment.Is_Empty then
            Append (Environment_Block, Character'Val (0));
         end if;
         Append (Environment_Block, Character'Val (0));
      end if;

      declare
         Wide_Environment : aliased Wide_String :=
           (if Use_Environment
            then Hostkit.Windows_Paths.From_UTF_8
                   (To_String (Environment_Block))
            else "" & Wide_Character'Val (0));

         Flags : constant C_DWord :=
           (if Use_Environment then Create_Unicode_Environment else 0)
           + (if Job /= System.Null_Address then Create_Suspended else 0);

         Started : Interfaces.C.int;

         --  Exactly the handles this child is to inherit, in the attribute
         --  list of an extended startup record -- never "every inheritable
         --  handle this process has", which would hand it the pipe ends and
         --  files another task is just then giving its own child (Hostkit.Win32
         --  .Child_Attributes). A pseudo-console takes none: its handles reach
         --  the child through the console. Redirected streams are the three
         --  in the startup record. Otherwise the child takes this process's
         --  own standard handles, as an inheriting launch always gave it.
         --  Freed when this block is left, whichever way.
         Attributes : Child_Attributes;
         Inherited  : constant Handle_List :=
           (if Is_Attached (With_Options.Console) then Handle_List'(1 .. 0 => System.Null_Address)
            elsif (Startup.Flags and Startf_Use_Std_Handles) /= 0
            then [Startup.Std_Input, Startup.Std_Output, Startup.Std_Error]
            else Own_Standard_Handles);
         Console : constant System.Address :=
           (if Is_Attached (With_Options.Console)
            then System.Storage_Elements.To_Address
                   (System.Storage_Elements.Integer_Address (Native_Console (With_Options.Console)))
            else System.Null_Address);
         Extended : aliased Extended_Startup_Info;
      begin
         if not Prepare (Attributes, Inherited, Console) then
            Close_Job;
            return Spawn_Failed;
         end if;

         Extended.Startup := Startup;
         Extended.Startup.Cb := C_DWord (Extended_Startup_Info'Size / 8);
         Extended.Attribute_List := Attribute_List (Attributes);

         Started := Create_Process_Extended
           (Application_Name   => System.Null_Address,
            Command_Line       => Wide_Command'Address,
            Process_Attributes => System.Null_Address,
            Thread_Attributes  => System.Null_Address,
            --  TRUE only when the list names a handle: an empty handle list is
            --  refused, and TRUE without one is what hands over everything.
            Inherit_Handles    => Inherit_Handles (Attributes),
            Creation_Flags     => Flags + Extended_Startup_Info_Present,
            Environment        =>
              (if Use_Environment then Wide_Environment'Address
               else System.Null_Address),
            Current_Directory  =>
              (if With_Options.Working_Directory = Null_Unbounded_String
               then System.Null_Address
               else Wide_Dir'Address),
            Startup            => Extended'Access,
            Information        => Information'Access);

         if Started = 0 then
            --  Windows reports why up front, so there is no need for the
            --  close-on-exec report pipe the POSIX bodies use: there is no
            --  fork and therefore no moment at which the failure is the
            --  child's.
            declare
               Error_Code : constant C_DWord := Get_Last_Error;
            begin
               Close_Job;
               return Outcome_For_Error (Error_Code);
            end;
         end if;
      end;

      if Job /= System.Null_Address then
         if Assign_Process_To_Job_Object (Job, Information.Process) = 0
           or else Resume_Thread (Information.Thread) = C_DWord'Last
         then
            declare
               Ignored : Interfaces.C.int;
               pragma Unreferenced (Ignored);
            begin
               Ignored := Terminate_Process (Information.Process, 1);
               Ignored := Close_Handle (Information.Thread);
               Ignored := Close_Handle (Information.Process);
               Ignored := Close_Handle (Job);
            end;
            return Spawn_Failed;
         end if;
      end if;

      --  The thread handle is of no use to a shell and would leak.
      declare
         Ignored : Interfaces.C.int;
      begin
         Ignored := Close_Handle (Information.Thread);
      end;

      Item.Id :=
        Interfaces.Integer_64 (System.Storage_Elements.To_Integer (Information.Process));
      Item.Group := Interfaces.Integer_64 (Information.Process_Id);
      if Job /= System.Null_Address then
         Item.Tree := Interfaces.Integer_64 (System.Storage_Elements.To_Integer (Job));
      end if;

      return Spawn_Ok;
   end Start;

   ----------
   -- Wait --
   ----------

   function Wait
     (Item   : Process_Handle;
      Mode   : Wait_Mode;
      Result : out Status) return Boolean
   is
      --  Only a valid handle's id is an address: Invalid_Process's -1 has no
      --  Integer_Address, so it is converted once Is_Valid has said so.
      function Handle return System.Address is
        (System.Storage_Elements.To_Address (System.Storage_Elements.Integer_Address (Item.Id)));
      Waited : C_DWord;
      Code   : aliased C_DWord := 0;
   begin
      Result := (State              => Wait_Running,
                 Exit_Code          => -1,
                 Terminating_Signal => Hostkit.Signals.Signal_Terminate,
                 Signal_Known       => False,
                 Raw_Signal_Number  => 0);

      if not Is_Valid (Item) then
         return False;
      end if;

      Waited := Wait_For_Single_Object
        (Handle, (if Mode = Wait_Poll then 0 else Infinite));

      if Waited = Wait_Timeout then
         Result.State := Wait_Running;
         return True;
      end if;

      if Waited = Wait_Failed then
         Result.State := Wait_Lost;
         return True;
      end if;

      if Get_Exit_Code_Process (Handle, Code'Access) = 0 then
         Result.State := Wait_Lost;
         return True;
      end if;

      if Code = Still_Active then
         --  STILL_ACTIVE is 259, which a program is also entitled to exit with.
         --  The wait above having returned is what distinguishes the two, and
         --  this branch is only reachable in the race where it has not.
         Result.State := Wait_Running;
         return True;
      end if;

      --  Windows has no notion of a process killed by a signal, and no stopped
      --  or continued states either -- so Wait_Signalled, Wait_Stopped and
      --  Wait_Continued are never reported here. A consumer that needs job
      --  control has to degrade explicitly on this host rather than wait for a
      --  state that cannot arrive.
      Result.State := Wait_Exited;
      Result.Exit_Code := Held (Code);
      return True;
   end Wait;

   --------------
   -- Wait_Any --
   --------------

   function Wait_Any
     (Mode   : Wait_Mode;
      Which  : out Process_Handle;
      Result : out Status) return Boolean
   is
      pragma Unreferenced (Mode);
   begin
      Which  := Invalid_Process;
      Result := (State              => Wait_Running,
                 Exit_Code          => -1,
                 Terminating_Signal => Hostkit.Signals.Signal_Terminate,
                 Signal_Known       => False,
                 Raw_Signal_Number  => 0);

      --  There is no waitpid(-1) here. Answering it would mean this package
      --  keeping its own table of every process it started and polling each --
      --  which is a consumer's job, not a host adapter's, and which a consumer
      --  can do with Wait in Wait_Poll mode over the jobs it already tracks.
      --  Inventing a table here would also silently change which process a
      --  caller's handle refers to.
      return False;
   end Wait_Any;

   procedure Release (Item : in out Process_Handle) is
      Ignored : Interfaces.C.int;
      pragma Unreferenced (Ignored);
   begin
      if Item.Tree > 0 then
         declare
            Job : constant System.Address :=
              System.Storage_Elements.To_Address
                (System.Storage_Elements.Integer_Address (Item.Tree));
         begin
            Ignored := Terminate_Job_Object (Job, 1);
            Ignored := Close_Handle (Job);
         end;
      end if;
      if Is_Valid (Item) then
         Ignored := Close_Handle
           (System.Storage_Elements.To_Address (System.Storage_Elements.Integer_Address (Item.Id)));
      end if;
      Item := Invalid_Process;
   end Release;

end Hostkit.Spawn;
