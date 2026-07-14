with Ada.Calendar;
with Ada.Strings.Unbounded;

with GNAT.OS_Lib;

with Interfaces.C.Strings;
with Interfaces.C;

with System;

package body Hostkit.Native is
   use Ada.Strings.Unbounded;
   use type Ada.Calendar.Time;
   use type Hostkit.Process.Cancel_Check;
   use type Hostkit.Process.Poll_Hook;
   use type Hostkit.Process.Started_Hook;
   use type Interfaces.C.int;
   use type GNAT.OS_Lib.Process_Id;
   use type GNAT.OS_Lib.String_Access;

   WNOHANG : constant Interfaces.C.int := 1;

   --  waitpid (-1, NULL, WNOHANG): any child, and do not block. It returns the pid of
   --  a child it collected, 0 when children exist but none have finished, and -1 when
   --  there are none at all -- so this drains what is ready and stops.
   function Waitpid
     (Pid     : Interfaces.C.int;
      Status  : System.Address;
      Options : Interfaces.C.int)
      return Interfaces.C.int
     with Import => True, Convention => C, External_Name => "waitpid";

   procedure Reap_Finished_Children is
      Collected : Interfaces.C.int;
   begin
      loop
         Collected := Waitpid (-1, System.Null_Address, WNOHANG);
         exit when Collected <= 0;
      end loop;
   exception
      when others =>
         null;
   end Reap_Finished_Children;

   --  sh takes "-c" and the command as ordinary vector elements, and nothing rewrites
   --  them on the way. There is nothing for a raw command line to fix.
   function Supports_Raw_Command_Line return Boolean is
   begin
      return False;
   end Supports_Raw_Command_Line;

   function Run_Command_Line
     (Command     : String;
      Wait        : Boolean;
      Exit_Status : out Integer)
      return Boolean
   is
      pragma Unreferenced (Command, Wait);
   begin
      Exit_Status := -1;
      return False;
   end Run_Command_Line;

   --  Run a program with its output captured, under a deadline.
   --
   --  fork, then in the child: redirect stdout and stderr to the capture files, change
   --  into the working directory, and exec. In the parent: poll with waitpid WNOHANG so
   --  that a deadline or a cancellation can be noticed, and when one is, ask the child to
   --  stop (SIGTERM) and then make it (SIGKILL). A blocking wait could not do that -- a
   --  compiler that never returns would hold the caller forever.
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
      use type Interfaces.C.Strings.chars_ptr;

      subtype C_Int is Interfaces.C.int;

      type C_Argv is array (Natural range <>) of aliased Interfaces.C.Strings.chars_ptr
        with Convention => C;

      function Fork return C_Int
        with Import => True, Convention => C, External_Name => "fork";
      function C_Open
        (Path  : Interfaces.C.Strings.chars_ptr;
         Flags : C_Int;
         Mode  : Interfaces.C.unsigned)
         return C_Int
        with Import => True, Convention => C, External_Name => "open";
      function Dup2 (Old_Fd, New_Fd : C_Int) return C_Int
        with Import => True, Convention => C, External_Name => "dup2";
      function C_Close (Fd : C_Int) return C_Int
        with Import => True, Convention => C, External_Name => "close";
      function Chdir (Path : Interfaces.C.Strings.chars_ptr) return C_Int
        with Import => True, Convention => C, External_Name => "chdir";
      function Execvp
        (File : Interfaces.C.Strings.chars_ptr;
         Argv : System.Address)
         return C_Int
        with Import => True, Convention => C, External_Name => "execvp";
      function Kill (Pid : C_Int; Signal : C_Int) return C_Int
        with Import => True, Convention => C, External_Name => "kill";
      procedure Underscore_Exit (Status : C_Int)
        with Import => True, Convention => C, External_Name => "_exit";

      O_Wronly : constant C_Int := 1;
      O_Creat  : constant C_Int := 64;
      O_Trunc  : constant C_Int := 512;
      Sigterm  : constant C_Int := 15;
      Sigkill  : constant C_Int := 9;

      Count     : constant Natural := Natural (Arguments.Length);
      Argv      : C_Argv (0 .. Count + 1);
      Program_C : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Program);

      Child      : C_Int;
      Status     : aliased C_Int := 0;
      Collected  : C_Int;
      Started_At : constant Ada.Calendar.Time := Ada.Calendar.Clock;
      Killed     : Boolean := False;
      Ignored    : C_Int;
      Result     : Hostkit.Process.Process_Outcome;

      procedure Free_Argv is
      begin
         for Index in Argv'Range loop
            if Argv (Index) /= Interfaces.C.Strings.Null_Ptr then
               Interfaces.C.Strings.Free (Argv (Index));
            end if;
         end loop;

         if Program_C /= Interfaces.C.Strings.Null_Ptr then
            Interfaces.C.Strings.Free (Program_C);
         end if;
      end Free_Argv;

      --  Deadline or cancellation: both mean "stop waiting and end it".
      function Should_Stop return Boolean is
         Elapsed : constant Duration := Ada.Calendar.Clock - Started_At;
      begin
         if Cancelled /= null and then Cancelled.all then
            return True;
         end if;

         return Timeout_Ms > 0
           and then Elapsed * 1000.0 >= Duration (Timeout_Ms);
      end Should_Stop;

      --  The child's exit code, out of the wait status. A process killed by a signal has
      --  no exit code of its own, and 128 + signal is the shell's convention for saying so.
      function Exit_Code (Raw : C_Int) return Integer is
         Value  : constant Integer := Integer (Raw);
         Signal : constant Integer := Value mod 128;
      begin
         if Signal = 0 then
            return (Value / 256) mod 256;
         end if;

         return 128 + Signal;
      end Exit_Code;

      procedure Redirect (Path : String; Target_Fd : C_Int) is
         Path_C  : Interfaces.C.Strings.chars_ptr :=
           Interfaces.C.Strings.New_String (Path);
         Opened  : constant C_Int :=
           C_Open (Path_C, O_Wronly + O_Creat + O_Trunc, 8#644#);
         Ignored : C_Int;
      begin
         Interfaces.C.Strings.Free (Path_C);

         if Opened >= 0 then
            Ignored := Dup2 (Opened, Target_Fd);
            Ignored := C_Close (Opened);
         end if;
      end Redirect;
   begin
      Argv (0) := Interfaces.C.Strings.New_String (Program);
      for Index in 1 .. Count loop
         Argv (Index) :=
           Interfaces.C.Strings.New_String (To_String (Arguments.Element (Index)));
      end loop;
      Argv (Count + 1) := Interfaces.C.Strings.Null_Ptr;

      Child := Fork;

      if Child < 0 then
         Free_Argv;
         return Result;
      end if;

      if Child = 0 then
         --  The child. Nothing here may return: on any failure it must _exit, or two
         --  copies of the caller would carry on running.
         if Stdout_Path /= "" then
            Redirect (Stdout_Path, 1);
         end if;

         if Stderr_Path /= "" then
            Redirect (Stderr_Path, 2);
         end if;

         if Working_Directory /= "" then
            declare
               Dir_C   : Interfaces.C.Strings.chars_ptr :=
                 Interfaces.C.Strings.New_String (Working_Directory);
               Changed : constant C_Int := Chdir (Dir_C);
            begin
               Interfaces.C.Strings.Free (Dir_C);

               if Changed /= 0 then
                  Underscore_Exit (127);
               end if;
            end;
         end if;

         if Execvp (Program_C, Argv (0)'Address) /= 0 then
            Underscore_Exit (127);
         end if;

         Underscore_Exit (127);
      end if;

      --  The parent.
      Result.Started := True;

      if Started_Notice /= null then
         Started_Notice.all (Integer (Child));
      end if;

      loop
         Collected := Waitpid (Child, Status'Address, WNOHANG);

         if Collected = Child then
            Result.Exit_Status := Exit_Code (Status);
            Result.Timed_Out := Killed;
            exit;
         end if;

         if Collected < 0 then
            --  It is gone and we cannot say how.
            Result.Timed_Out := Killed;
            exit;
         end if;

         if not Killed and then Should_Stop then
            Killed := True;
            Ignored := Kill (Child, Sigterm);
            delay 0.05;

            --  Asking did not work; now it is not a request.
            if Waitpid (Child, Status'Address, WNOHANG) /= Child then
               Ignored := Kill (Child, Sigkill);
            end if;
         end if;

         if Poll /= null then
            Poll.all;
         end if;

         delay 0.005;
      end loop;

      Free_Argv;
      return Result;
   end Run_Captured;

   function Native_Backend_Label return String is
   begin
      return "POSIX/fork-exec-waitpid-kill";
   end Native_Backend_Label;

   function Open_Native (Path : String) return Boolean is
      --  xdg-open is the freedesktop way to hand a path to whatever handles it.
      Opener   : constant String := "xdg-open";
      Located  : GNAT.OS_Lib.String_Access := GNAT.OS_Lib.Locate_Exec_On_Path (Opener);
      Argument : aliased String := Path;
      Args     : constant GNAT.OS_Lib.Argument_List :=
        [1 => Argument'Unchecked_Access];
      Started  : GNAT.OS_Lib.Process_Id;
   begin
      if Located = null then
         return False;
      end if;

      Started := GNAT.OS_Lib.Non_Blocking_Spawn (Located.all, Args);
      GNAT.OS_Lib.Free (Located);

      if Started = GNAT.OS_Lib.Invalid_Pid then
         return False;
      end if;

      Reap_Finished_Children;
      return True;
   exception
      when others =>
         if Located /= null then
            GNAT.OS_Lib.Free (Located);
         end if;
         return False;
   end Open_Native;

end Hostkit.Native;
