with Ada.Calendar;
with Ada.Strings.Unbounded;
with Ada.Strings.UTF_Encoding.Wide_Strings;

with Interfaces.C;

with System.Storage_Elements;
with System;

package body Hostkit.Native is
   use Ada.Strings.Unbounded;
   use type Ada.Calendar.Time;
   use type Hostkit.Process.Cancel_Check;
   use type Hostkit.Process.Poll_Hook;
   use type Hostkit.Process.Started_Hook;

   use type Interfaces.C.int;
   use type Interfaces.C.unsigned_long;
   use type System.Address;
   use type System.Storage_Elements.Integer_Address;

   subtype C_DWord is Interfaces.C.unsigned_long;

   Infinite     : constant C_DWord := 16#FFFF_FFFF#;
   Still_Active : constant C_DWord := 259;
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

   function Wait_For_Single_Object
     (Handle       : System.Address;
      Milliseconds : C_DWord)
      return C_DWord
     with Import => True, Convention => Stdcall, External_Name => "WaitForSingleObject";

   function Get_Exit_Code_Process
     (Process   : System.Address;
      Exit_Code : access C_DWord)
      return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "GetExitCodeProcess";

   function Close_Handle (Handle : System.Address) return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "CloseHandle";

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
     (Ada.Strings.UTF_Encoding.Wide_Strings.Decode (Value) & Wide_Character'Val (0));

   --  Windows has no zombie: a process that has exited is gone once its handles are
   --  closed, and everything here closes both before it returns.
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

   Generic_Write     : constant C_DWord := 16#4000_0000#;
   File_Share_Read   : constant C_DWord := 16#0000_0001#;
   Create_Always     : constant C_DWord := 2;
   File_Attr_Normal  : constant C_DWord := 16#0000_0080#;
   Start_Use_Handles : constant C_DWord := 16#0000_0100#;
   Invalid_Handle    : constant System.Address :=
     System.Storage_Elements.To_Address (-1);

   type Security_Attributes is record
      Length      : C_DWord := 0;
      Descriptor  : System.Address := System.Null_Address;
      Inheritable : Interfaces.C.int := 0;
   end record
     with Convention => C;

   function Create_File
     (Name       : System.Address;
      Access_Way : C_DWord;
      Share      : C_DWord;
      Security   : access Security_Attributes;
      Creation   : C_DWord;
      Attributes : C_DWord;
      Template   : System.Address)
      return System.Address
     with Import => True, Convention => Stdcall, External_Name => "CreateFileW";

   function Terminate_Process
     (Process   : System.Address;
      Exit_Code : Interfaces.C.unsigned)
      return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "TerminateProcess";

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
      Stdout_Path       : String;
      Stderr_Path       : String;
      Timeout_Ms        : Natural;
      Cancelled         : Hostkit.Process.Cancel_Check;
      Poll              : Hostkit.Process.Poll_Hook;
      Started_Notice    : Hostkit.Process.Started_Hook)
      return Hostkit.Process.Process_Outcome
   is
      --  CreateProcessW takes a command line, not a vector, so the arguments have to be
      --  quoted into one -- the C runtime rules, which is what every Windows program
      --  parses back out: wrap anything with a space, and double an embedded quote.
      function Quote (Value : String) return String is
         Result : Unbounded_String;
         Needs  : Boolean := Value = "";
      begin
         for Character_Value of Value loop
            if Character_Value = ' ' or else Character_Value = '"' then
               Needs := True;
            end if;
         end loop;

         if not Needs then
            return Value;
         end if;

         Append (Result, '"');
         for Character_Value of Value loop
            if Character_Value = '"' then
               Append (Result, """""");
            else
               Append (Result, Character_Value);
            end if;
         end loop;
         Append (Result, '"');
         return To_String (Result);
      end Quote;

      function Command_Line return String is
         Result : Unbounded_String := To_Unbounded_String (Quote (Program));
      begin
         for Argument of Arguments loop
            Append (Result, " ");
            Append (Result, Quote (To_String (Argument)));
         end loop;

         return To_String (Result);
      end Command_Line;

      function Capture (Path : String) return System.Address is
         Wide_Path : aliased Wide_String := Wide (Path);
         Security  : aliased Security_Attributes;
      begin
         if Path = "" then
            return Invalid_Handle;
         end if;

         Security.Length := C_DWord (Security_Attributes'Size / 8);
         Security.Inheritable := 1;

         return Create_File
                  (Name       => Wide_Path'Address,
                   Access_Way => Generic_Write,
                   Share      => File_Share_Read,
                   Security   => Security'Access,
                   Creation   => Create_Always,
                   Attributes => File_Attr_Normal,
                   Template   => System.Null_Address);
      end Capture;

      Wide_Command : aliased Wide_String := Wide (Command_Line);
      Wide_Dir     : aliased Wide_String := Wide (Working_Directory);

      Out_Handle : System.Address := Capture (Stdout_Path);
      Err_Handle : System.Address := Capture (Stderr_Path);

      Startup     : aliased Startup_Info;
      Information : aliased Process_Information;
      Exit_Code   : aliased C_DWord := 0;
      Started_At  : constant Ada.Calendar.Time := Ada.Calendar.Clock;
      Killed      : Boolean := False;
      Waited      : C_DWord;
      Ignored     : Interfaces.C.int;
      Result      : Hostkit.Process.Process_Outcome;

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
         if Out_Handle /= Invalid_Handle then
            Ignored := Close_Handle (Out_Handle);
            Out_Handle := Invalid_Handle;
         end if;

         if Err_Handle /= Invalid_Handle then
            Ignored := Close_Handle (Err_Handle);
            Err_Handle := Invalid_Handle;
         end if;
      end Close_Captures;
   begin
      Startup.Cb := C_DWord (Startup_Info'Size / 8);

      if Out_Handle /= Invalid_Handle or else Err_Handle /= Invalid_Handle then
         Startup.Flags := Start_Use_Handles;
         Startup.Std_Output := Out_Handle;
         Startup.Std_Error := Err_Handle;
      end if;

      if Create_Process
           (Application_Name   => System.Null_Address,
            Command_Line       => Wide_Command'Address,
            Process_Attributes => System.Null_Address,
            Thread_Attributes  => System.Null_Address,
            --  The capture handles are inheritable and this is what lets the child have
            --  them. Without it its output goes nowhere and the files stay empty.
            Inherit_Handles    => 1,
            Creation_Flags     => 0,
            Environment        => System.Null_Address,
            Current_Directory  =>
              (if Working_Directory = "" then System.Null_Address else Wide_Dir'Address),
            Startup            => Startup'Access,
            Information        => Information'Access) = 0
      then
         Close_Captures;
         return Result;
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
            --  Nothing to ask with here. TerminateProcess is the request and the answer.
            Ignored := Terminate_Process (Information.Process, 1);
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

      return Result;
   end Run_Captured;

   function Open_Native (Path : String) return Boolean is
      Wide_Path : aliased Wide_String := Wide (Path);
      Operation : aliased Wide_String := Wide ("open");
      Result    : System.Address;
   begin
      if Path = "" then
         return False;
      end if;

      Result :=
        Shell_Execute
          (Window     => System.Null_Address,
           Operation  => Operation'Address,
           File       => Wide_Path'Address,
           Parameters => System.Null_Address,
           Directory  => System.Null_Address,
           Show       => SW_Show_Normal);

      return System.Storage_Elements.To_Integer (Result) > 32;
   exception
      when others =>
         return False;
   end Open_Native;

end Hostkit.Native;
