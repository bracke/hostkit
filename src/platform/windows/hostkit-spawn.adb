with Ada.Strings.Unbounded;
with Ada.Strings.UTF_Encoding.Wide_Strings;

with Hostkit.Windows_Command_Line;

with Interfaces.C;

with System.Storage_Elements;
with System;

package body Hostkit.Spawn is

   use Ada.Strings.Unbounded;
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned_long;
   use type System.Address;
   use type Hostkit.Descriptors.Descriptor;

   subtype C_DWord is Interfaces.C.unsigned_long;

   Infinite     : constant C_DWord := 16#FFFF_FFFF#;
   Still_Active : constant C_DWord := 259;
   Wait_Failed  : constant C_DWord := 16#FFFF_FFFF#;
   Wait_Timeout : constant C_DWord := 16#0000_0102#;

   Startf_Use_Std_Handles : constant C_DWord := 16#0000_0100#;
   Create_Unicode_Environment : constant C_DWord := 16#0000_0400#;

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

   --  These layouts are a contract with the OS, not a description of our own
   --  records, so pin them: a field silently mis-sized is a corrupt call rather
   --  than a compile error. 104 and 24 are the x86-64 layouts.
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

   function Wait_For_Single_Object
     (Handle : System.Address; Milliseconds : C_DWord) return C_DWord
     with Import => True, Convention => Stdcall, External_Name => "WaitForSingleObject";

   function Get_Exit_Code_Process
     (Process : System.Address; Exit_Code : access C_DWord) return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "GetExitCodeProcess";

   function Close_Handle (Handle : System.Address) return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "CloseHandle";

   function Get_Last_Error return C_DWord
     with Import => True, Convention => Stdcall, External_Name => "GetLastError";

   function Wide (Value : String) return Wide_String
   is (Ada.Strings.UTF_Encoding.Wide_Strings.Decode (Value) & Wide_Character'Val (0));

   function To_Handle (Item : Hostkit.Descriptors.Descriptor) return System.Address
   is (System.Storage_Elements.To_Address
         (System.Storage_Elements.Integer_Address
            (Hostkit.Descriptors.Native_Value (Item))));

   --  The process handle is kept in the Id field, not the process id. Windows
   --  needs the handle to wait or to read an exit code, and a process id there
   --  is only a number -- reusable the moment the process goes, exactly like a
   --  POSIX pid. Process_Id below reports the handle for want of anywhere else
   --  to keep it, which is a wart this host forces and which is why the field
   --  is opaque.

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
      Wide_Dir     : aliased Wide_String :=
        Wide (To_String (With_Options.Working_Directory));

      Startup     : aliased Startup_Info;
      Information : aliased Process_Information;

      Environment_Block : Unbounded_String;
      Use_Environment   : constant Boolean :=
        With_Options.Replace_Environment
        and then not With_Options.Environment.Is_Empty;
   begin
      Item := Invalid_Process;

      --  Asked for something this host does not have. Refused rather than
      --  started without it: a child that could be interrupted through its
      --  terminal on one host and not on another is the difference this crate
      --  exists to make visible.
      if With_Options.Controlling_Terminal /= Hostkit.Descriptors.Invalid then
         return Spawn_Failed;
      end if;

      Startup.Cb := C_DWord (Startup_Info'Size / 8);

      --  STARTF_USESTDHANDLES is all or nothing: the child takes all three
      --  handles from here or none of them, so any stream the caller left
      --  Invalid is filled in with this process's own.
      if With_Options.Input /= Hostkit.Descriptors.Invalid
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
      --  POSIX.
      if Use_Environment then
         for Entry_Text of With_Options.Environment loop
            Append (Environment_Block, To_String (Entry_Text));
            Append (Environment_Block, Character'Val (0));
         end loop;
         Append (Environment_Block, Character'Val (0));
      end if;

      declare
         Wide_Environment : aliased Wide_String :=
           (if Use_Environment
            then Ada.Strings.UTF_Encoding.Wide_Strings.Decode
                   (To_String (Environment_Block))
            else "" & Wide_Character'Val (0));

         Flags : constant C_DWord :=
           (if Use_Environment then Create_Unicode_Environment else 0);

         Started : Interfaces.C.int;
      begin
         Started := Create_Process
           (Application_Name   => System.Null_Address,
            Command_Line       => Wide_Command'Address,
            Process_Attributes => System.Null_Address,
            Thread_Attributes  => System.Null_Address,

            --  True, and it is what makes a handed-over pipe end reach the
            --  child at all. Only handles marked inheritable travel, which is
            --  why Hostkit.Descriptors creates them unmarked and a caller opts
            --  each one in.
            Inherit_Handles    => 1,
            Creation_Flags     => Flags,
            Environment        =>
              (if Use_Environment then Wide_Environment'Address
               else System.Null_Address),
            Current_Directory  =>
              (if With_Options.Working_Directory = Null_Unbounded_String
               then System.Null_Address
               else Wide_Dir'Address),
            Startup            => Startup'Access,
            Information        => Information'Access);

         if Started = 0 then
            --  Windows reports why up front, so there is no need for the
            --  close-on-exec report pipe the POSIX bodies use: there is no fork
            --  and therefore no moment at which the failure is the child's.
            return Outcome_For_Error (Get_Last_Error);
         end if;
      end;

      --  The thread handle is of no use to a shell and would leak.
      declare
         Ignored : Interfaces.C.int;
      begin
         Ignored := Close_Handle (Information.Thread);
      end;

      Item.Id :=
        Interfaces.Integer_64 (System.Storage_Elements.To_Integer (Information.Process));
      Item.Group := Interfaces.Integer_64 (Information.Process_Id);

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
      Handle : constant System.Address :=
        System.Storage_Elements.To_Address
          (System.Storage_Elements.Integer_Address (Item.Id));
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
      Result.Exit_Code := Integer (Code);
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

end Hostkit.Spawn;
