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
      Stdin_Path        : String;
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

      O_Rdonly : constant C_Int := 0;
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

      --  The child's standard input, out of a file. Unlike the capture
      --  redirections this one must not fail quietly: a program that cannot
      --  open the file it was told to read would go on to read the caller's
      --  terminal instead, and a prompt for a password would sit there for
      --  ever rather than fail.
      procedure Feed (Path : String) is
         Path_C  : Interfaces.C.Strings.chars_ptr :=
           Interfaces.C.Strings.New_String (Path);
         Opened  : constant C_Int := C_Open (Path_C, O_Rdonly, 0);
         Ignored : C_Int;
      begin
         Interfaces.C.Strings.Free (Path_C);

         if Opened < 0 then
            Underscore_Exit (127);
         end if;

         Ignored := Dup2 (Opened, 0);
         Ignored := C_Close (Opened);
      end Feed;

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
         if Stdin_Path /= "" then
            Feed (Stdin_Path);
         end if;

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

   function Become_Program
     (Program   : String;
      Arguments : String_Vectors.Vector)
      return Boolean
   is
      use Interfaces.C.Strings;
      use type Interfaces.C.size_t;

      --  execvp rather than execv: a shell's `exec` takes a name as readily as
      --  a path, and the search is the host's to do -- ours would have to
      --  re-derive the rules for an executable bit and a search path that this
      --  host already knows.
      function C_Execvp
        (File : chars_ptr; Argv : chars_ptr_array) return Interfaces.C.int
        with Import, Convention => C, External_Name => "execvp";

      Count : constant Natural := Natural (Arguments.Length);

      --  Argument zero is the program's own name, which is what every program
      --  expects to find there and what `ps` shows. Then the arguments, then
      --  the null the host reads as the end.
      Argv : chars_ptr_array (0 .. Interfaces.C.size_t (Count) + 1) :=
        [others => Null_Ptr];

      Ignored : Interfaces.C.int;
   begin
      if Program = "" then
         return False;
      end if;

      Argv (0) := New_String (Program);

      for Index in 1 .. Count loop
         Argv (Interfaces.C.size_t (Index)) :=
           New_String
             (Ada.Strings.Unbounded.To_String (Arguments.Element (Index)));
      end loop;

      Ignored := C_Execvp (Argv (0), Argv);

      --  Only reachable because the call failed: on success this process is
      --  the other program by now and there is nothing here to run. Freed
      --  anyway, because a caller may go on to report the refusal and then do
      --  something else.
      for Index in Argv'Range loop
         if Argv (Index) /= Null_Ptr then
            Free (Argv (Index));
         end if;
      end loop;

      return False;
   end Become_Program;

   function Request_Stop (Process_Id : Integer) return Boolean is
      Sigterm : constant Interfaces.C.int := 15;

      function Kill (Pid : Interfaces.C.int; Signal : Interfaces.C.int) return Interfaces.C.int
        with Import => True, Convention => C, External_Name => "kill";
   begin
      return Kill (Interfaces.C.int (Process_Id), Sigterm) = 0;
   exception
      when others =>
         return False;
   end Request_Stop;

   --  poll() one descriptor for readability or writability, with a timeout in milliseconds
   --  (negative waits indefinitely). This is what an SSH or git helper's pipe is waited on.
   function Wait_FD
     (FD         : Integer;
      For_Write  : Boolean;
      Timeout_MS : Integer)
      return Hostkit.Process.Wait_Outcome
   is
      Poll_In  : constant Interfaces.C.short := 16#0001#;
      Poll_Out : constant Interfaces.C.short := 16#0004#;

      type Poll_FD is record
         FD      : Interfaces.C.int;
         Events  : Interfaces.C.short;
         Revents : Interfaces.C.short := 0;
      end record
        with Convention => C;

      function C_Poll
        (FDs : access Poll_FD; NFDs : Interfaces.C.unsigned_long; Timeout : Interfaces.C.int)
        return Interfaces.C.int
        with Import => True, Convention => C, External_Name => "poll";

      Item : aliased Poll_FD :=
        (FD      => Interfaces.C.int (FD),
         Events  => (if For_Write then Poll_Out else Poll_In),
         Revents => 0);
      Result : Interfaces.C.int;
   begin
      if FD < 0 then
         return Hostkit.Process.Wait_Error;
      end if;

      Result := C_Poll (Item'Access, 1, Interfaces.C.int (Timeout_MS));

      if Result > 0 then
         return Hostkit.Process.Wait_Ready;
      elsif Result = 0 then
         return Hostkit.Process.Wait_Timed_Out;
      else
         return Hostkit.Process.Wait_Error;
      end if;
   exception
      when others =>
         return Hostkit.Process.Wait_Error;
   end Wait_FD;

   function Native_Backend_Label return String is
   begin
      return "POSIX/fork-exec-waitpid-kill";
   end Native_Backend_Label;

   function Current_User_Id (User_Id : out Natural) return Boolean is
      function Getuid return Interfaces.C.unsigned
        with Import => True, Convention => C, External_Name => "getuid";
   begin
      User_Id := Natural (Getuid);
      return True;
   exception
      when others =>
         User_Id := 0;
         return False;
   end Current_User_Id;

   function Current_Group_Id (Group_Id : out Natural) return Boolean is
      function Getgid return Interfaces.C.unsigned
        with Import => True, Convention => C, External_Name => "getgid";
   begin
      Group_Id := Natural (Getgid);
      return True;
   exception
      when others =>
         Group_Id := 0;
         return False;
   end Current_Group_Id;

   function Current_Supplementary_Group_Ids
     (Groups : out Hostkit.Process.Group_Id_List;
      Last   : out Natural)
      return Boolean
   is
      type C_Group_Id_List is array (Positive range <>) of Interfaces.C.unsigned;

      function Getgroups
        (Size : Interfaces.C.int;
         List : System.Address)
         return Interfaces.C.int
      with Import => True, Convention => C, External_Name => "getgroups";

      Native_Groups : aliased C_Group_Id_List (1 .. Groups'Length) := [others => 0];
      Count         : Interfaces.C.int;
   begin
      for Index in Groups'Range loop
         Groups (Index) := 0;
      end loop;
      Last := 0;

      Count := Getgroups (Interfaces.C.int (Groups'Length), Native_Groups'Address);
      if Count < 0 then
         return False;
      end if;

      Last := Natural (Count);
      if Last > 0 then
         for Offset in 0 .. Last - 1 loop
            Groups (Groups'First + Offset) := Natural (Native_Groups (Native_Groups'First + Offset));
         end loop;
      end if;
      return True;
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
      Groups    : out Hostkit.Process.Group_Id_List;
      Last      : out Natural)
      return Boolean
   is
      type C_Group_Id_List is array (Positive range <>) of Interfaces.C.unsigned;

      type Passwd is record
         Pw_Name   : System.Address;
         Pw_Passwd : System.Address;
         Pw_Uid    : Interfaces.C.unsigned;
         Pw_Gid    : Interfaces.C.unsigned;
         Pw_Gecos  : System.Address;
         Pw_Dir    : System.Address;
         Pw_Shell  : System.Address;
      end record
        with Convention => C;

      function Getpwnam (Name : Interfaces.C.char_array) return access Passwd
        with Import => True, Convention => C, External_Name => "getpwnam";

      function Getgrouplist
        (User   : Interfaces.C.char_array;
         Group  : Interfaces.C.unsigned;
         List   : System.Address;
         Count  : access Interfaces.C.int)
         return Interfaces.C.int
      with Import => True, Convention => C, External_Name => "getgrouplist";

      C_Name        : constant Interfaces.C.char_array :=
        Interfaces.C.To_C (User_Name);
      Passwd_Entry  : constant access Passwd := Getpwnam (C_Name);
      Native_Groups : aliased C_Group_Id_List (1 .. Groups'Length) := [others => 0];
      Count         : aliased Interfaces.C.int := Interfaces.C.int (Groups'Length);
      Found         : Natural := 0;

      procedure Append_Group (Id : Natural) is
      begin
         for Index in 1 .. Found loop
            if Groups (Index) = Id then
               return;
            end if;
         end loop;
         if Found < Groups'Length then
            Found := Found + 1;
            Groups (Found) := Id;
         end if;
      end Append_Group;
   begin
      for Index in Groups'Range loop
         Groups (Index) := 0;
      end loop;
      Last := 0;

      if User_Name = "" or else Passwd_Entry = null then
         return False;
      end if;

      Append_Group (Natural (Passwd_Entry.Pw_Gid));
      if Getgrouplist
        (C_Name, Passwd_Entry.Pw_Gid, Native_Groups'Address, Count'Access) < 0
      then
         Last := Found;
         return Found > 0;
      end if;

      for Offset in 0 .. Natural (Count) - 1 loop
         exit when Offset >= Native_Groups'Length;
         Append_Group (Natural (Native_Groups (Native_Groups'First + Offset)));
      end loop;

      Last := Found;
      return Last > 0;
   exception
      when others =>
         for Index in Groups'Range loop
            Groups (Index) := 0;
         end loop;
         Last := 0;
         return False;
   end User_Group_Ids;

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
