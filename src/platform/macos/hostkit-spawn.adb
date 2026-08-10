with Ada.Strings.Unbounded;

with Interfaces.C.Strings;
with Interfaces.C;

with System;

package body Hostkit.Spawn is

   use Ada.Strings.Unbounded;
   use type Interfaces.C.int;
   use type Interfaces.C.long;
   use type Interfaces.C.Strings.chars_ptr;
   use type Interfaces.Integer_64;
   use type Hostkit.Descriptors.Descriptor;
   use type Hostkit.Signals.Signal;

   subtype C_Int is Interfaces.C.int;
   subtype C_Long is Interfaces.C.long;

   --  waitpid options, macOS. WUNTRACED and WCONTINUED are what make a stop and
   --  a resume visible at all; without them Ctrl-Z looks to the parent like
   --  nothing happened, and a shell cannot tell a suspended job from a running
   --  one. WCONTINUED is 0x10 here and 8 on Linux.
   WNOHANG    : constant C_Int := 1;
   WUNTRACED  : constant C_Int := 2;
   WCONTINUED : constant C_Int := 16#10#;

   --  errno values Start distinguishes, so that a shell can say which of the
   --  four things went wrong rather than "it did not run".
   E_Noent   : constant := 2;
   E_Acces   : constant := 13;
   E_Isdir   : constant := 21;
   E_Noexec  : constant := 8;
   E_Perm    : constant := 1;
   E_Notdir  : constant := 20;
   --  ELOOP and ENAMETOOLONG are 62 and 63 here, 40 and 36 on Linux.
   E_Loop    : constant := 62;
   E_Nametoolong : constant := 63;

   Exec_Failed_Status : constant C_Int := 127;

   type C_String_Array is
     array (Natural range <>) of aliased Interfaces.C.Strings.chars_ptr
     with Convention => C;

   function Fork return C_Int
     with Import => True, Convention => C, External_Name => "fork";
   function Setpgid (Pid, Pgid : C_Int) return C_Int
     with Import => True, Convention => C, External_Name => "setpgid";
   function Tcsetpgrp (Fd, Pgid : C_Int) return C_Int
     with Import => True, Convention => C, External_Name => "tcsetpgrp";
   function Chdir (Path : Interfaces.C.Strings.chars_ptr) return C_Int
     with Import => True, Convention => C, External_Name => "chdir";
   function Execvp (File : Interfaces.C.Strings.chars_ptr; Argv : System.Address) return C_Int
     with Import => True, Convention => C, External_Name => "execvp";
   procedure Underscore_Exit (Status : C_Int)
     with Import => True, Convention => C, External_Name => "_exit";
   function Waitpid (Pid : C_Int; Status : System.Address; Options : C_Int) return C_Int
     with Import => True, Convention => C, External_Name => "waitpid";
   function C_Write (Fd : C_Int; Buffer : System.Address; Count : C_Long) return C_Long
     with Import => True, Convention => C, External_Name => "write";
   function C_Read (Fd : C_Int; Buffer : System.Address; Count : C_Long) return C_Long
     with Import => True, Convention => C, External_Name => "read";
   function C_Signal (Sig : C_Int; Handler : System.Address) return System.Address
     with Import => True, Convention => C, External_Name => "signal";
   function Errno_Location return System.Address
     with Import => True, Convention => C, External_Name => "__error";
   function Getpgrp return C_Int
     with Import => True, Convention => C, External_Name => "getpgrp";

   --  The environment the next exec passes on, and -- because execvp reads
   --  PATH from it -- the PATH the lookup uses. That is the shell semantics a
   --  user who set PATH meant.
   --
   --  Not "extern char **environ" as on Linux. On macOS that symbol is not
   --  reliably reachable from anything but the main executable, and Apple
   --  documents _NSGetEnviron as the way to get at it; it returns the address
   --  of the pointer, so writing through it is what replaces the environment.
   function NS_Get_Environ return System.Address
     with Import => True, Convention => C, External_Name => "_NSGetEnviron";

   SIG_DFL : constant System.Address := System.Null_Address;

   function Errno return C_Int;
   function To_Native (Item : Hostkit.Descriptors.Descriptor) return C_Int;

   -----------
   -- Errno --
   -----------

   function Errno return C_Int is
      Value : C_Int with Import => True, Address => Errno_Location;
   begin
      return Value;
   end Errno;

   ---------------
   -- To_Native --
   ---------------

   function To_Native (Item : Hostkit.Descriptors.Descriptor) return C_Int is
   begin
      return C_Int (Hostkit.Descriptors.Native_Value (Item));
   end To_Native;

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
      return Integer (Item.Id);
   end Process_Id;

   --------------
   -- Group_Id --
   --------------

   function Group_Id (Item : Process_Handle) return Integer is
   begin
      return Integer (Item.Group);
   end Group_Id;

   ---------------------
   -- Decode_Status --
   ---------------------

   --  The wait status, taken apart. These are the W* macros from sys/wait.h,
   --  written out because a macro cannot be imported. The layout is the same on
   --  every macOS: the low seven bits are the terminating signal, 0x7f in them
   --  means stopped rather than terminated, and the next eight are the exit
   --  code or the stopping signal.
   procedure Decode_Status (Raw : C_Int; Result : out Status) is
      Low     : constant C_Int := Raw mod 256;
      Signal_Bits : constant C_Int := Raw mod 128;
      High    : constant C_Int := (Raw / 256) mod 256;
      Decoded : Hostkit.Signals.Signal;
   begin
      Result := (State              => Wait_Lost,
                 Exit_Code          => -1,
                 Terminating_Signal => Hostkit.Signals.Signal_Terminate,
                 Signal_Known       => False,
                 Raw_Signal_Number  => 0);

      if Low = 16#7F# and then High = 16#13# then
         --  WIFCONTINUED. BSD encodes it as a stop whose "signal" is 0x13,
         --  where Linux uses the whole status word 0xFFFF. Testing for the
         --  Linux form here would report every resumed job as stopped, and a
         --  shell would show a running job as suspended for ever.
         Result.State := Wait_Continued;
         return;
      end if;

      if Low = 16#7F# then
         --  WIFSTOPPED: the low byte is exactly 0x7f and the stopping signal is
         --  in the next one.
         Result.State := Wait_Stopped;
         Result.Raw_Signal_Number := Integer (High);
         Result.Signal_Known :=
           Hostkit.Signals.From_Number (Integer (High), Decoded);

         if Result.Signal_Known then
            Result.Terminating_Signal := Decoded;
         end if;

         return;
      end if;

      if Signal_Bits = 0 then
         --  WIFEXITED.
         Result.State := Wait_Exited;
         Result.Exit_Code := Integer (High);
         return;
      end if;

      --  WIFSIGNALED. Reported as such rather than folded into an exit code:
      --  128 + signal is a shell's way of *printing* this, not the kernel's way
      --  of recording it, and a program is entitled to exit 139 on purpose.
      Result.State := Wait_Signalled;
      Result.Raw_Signal_Number := Integer (Signal_Bits);
      Result.Signal_Known :=
        Hostkit.Signals.From_Number (Integer (Signal_Bits), Decoded);

      if Result.Signal_Known then
         Result.Terminating_Signal := Decoded;
      end if;
   end Decode_Status;

   -----------------------
   -- Outcome_For_Errno --
   -----------------------

   function Outcome_For_Errno (Code : Integer) return Spawn_Outcome is
   begin
      case Code is
         when E_Noent | E_Notdir | E_Nametoolong | E_Loop => return Spawn_Not_Found;
         when E_Acces | E_Perm                            => return Spawn_Denied;
         when E_Isdir | E_Noexec                          => return Spawn_Not_Executable;
         when others                                      => return Spawn_Failed;
      end case;
   end Outcome_For_Errno;

   -----------
   -- Start --
   -----------

   function Start
     (Program      : String;
      Arguments    : String_Vectors.Vector;
      With_Options : Options;
      Item         : out Process_Handle) return Spawn_Outcome
   is
      Count     : constant Natural := Natural (Arguments.Length);
      Argv      : C_String_Array (0 .. Count + 1);
      Program_C : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Program);

      Env_Count : constant Natural := Natural (With_Options.Environment.Length);
      Envp      : C_String_Array (0 .. Env_Count);

      Report  : Hostkit.Descriptors.Pipe_Ends;
      Child   : C_Int;
      Result  : Spawn_Outcome := Spawn_Failed;

      procedure Free_Vectors;
      procedure Child_Side;

      ------------------
      -- Free_Vectors --
      ------------------

      procedure Free_Vectors is
      begin
         for Index in Argv'Range loop
            if Argv (Index) /= Interfaces.C.Strings.Null_Ptr then
               Interfaces.C.Strings.Free (Argv (Index));
            end if;
         end loop;

         for Index in Envp'Range loop
            if Envp (Index) /= Interfaces.C.Strings.Null_Ptr then
               Interfaces.C.Strings.Free (Envp (Index));
            end if;
         end loop;

         if Program_C /= Interfaces.C.Strings.Null_Ptr then
            Interfaces.C.Strings.Free (Program_C);
         end if;
      end Free_Vectors;

      ----------------
      -- Child_Side --
      ----------------

      --  Everything between the fork and the exec. Nothing here may return: on
      --  any failure it reports the reason down the pipe and _exits, because a
      --  return would leave two copies of the caller running.
      procedure Child_Side is
         Failure : aliased C_Int := 0;
         Ignored : C_Long;
         Unused  : C_Int;

         procedure Fail_Now;

         procedure Fail_Now is
         begin
            Failure := Errno;

            --  The parent distinguishes "exec failed, and here is why" from
            --  "exec succeeded" by whether anything arrives before the pipe
            --  closes. A short write here would be indistinguishable from
            --  success, but the write is four bytes into an empty pipe and
            --  cannot be short.
            Ignored := C_Write (To_Native (Report.Write_End),
                                Failure'Address,
                                C_Long (C_Int'Size / 8));
            Underscore_Exit (Exec_Failed_Status);
         end Fail_Now;

      begin
         --  The child half of the group race. See the package header.
         case With_Options.Group is
            when Group_Inherit =>
               null;
            when Group_New =>
               Unused := Setpgid (0, 0);
            when Group_Join =>
               Unused := Setpgid (0, C_Int (With_Options.Join_Group));
         end case;

         --  Take the terminal, if this is a foreground job. Also done by the
         --  caller, for the same race.
         if With_Options.Foreground_Terminal /= Hostkit.Descriptors.Invalid
           and then With_Options.Group /= Group_Inherit
         then
            declare
               Group : constant C_Int :=
                 (if With_Options.Group = Group_New
                  then 0
                  else C_Int (With_Options.Join_Group));
            begin
               --  Group 0 means "my own", which after the setpgid above is this
               --  child. tcsetpgrp would raise SIGTTOU on a process that is not
               --  already in the foreground; the default disposition is restored
               --  below, after this, precisely so this call is not the one that
               --  stops us.
               Unused := Tcsetpgrp (To_Native (With_Options.Foreground_Terminal),
                                    (if Group = 0 then Getpgrp else Group));
            end;
         end if;

         --  Standard streams, before the signal reset: a failure here still has
         --  a working pipe to report down.
         if With_Options.Input /= Hostkit.Descriptors.Invalid
           and then not Hostkit.Descriptors.Assign
                          (With_Options.Input, Hostkit.Descriptors.Stream_Input)
         then
            Fail_Now;
         end if;

         if With_Options.Output /= Hostkit.Descriptors.Invalid
           and then not Hostkit.Descriptors.Assign
                          (With_Options.Output, Hostkit.Descriptors.Stream_Output)
         then
            Fail_Now;
         end if;

         if With_Options.Error_Output /= Hostkit.Descriptors.Invalid
           and then not Hostkit.Descriptors.Assign
                          (With_Options.Error_Output, Hostkit.Descriptors.Stream_Error)
         then
            Fail_Now;
         end if;

         if With_Options.Working_Directory /= Null_Unbounded_String then
            declare
               Dir : Interfaces.C.Strings.chars_ptr :=
                 Interfaces.C.Strings.New_String
                   (To_String (With_Options.Working_Directory));
               Changed : constant C_Int := Chdir (Dir);
            begin
               Interfaces.C.Strings.Free (Dir);

               if Changed /= 0 then
                  Fail_Now;
               end if;
            end;
         end if;

         --  Signal dispositions back to the host default. A child that inherits
         --  the shell's ignored SIGINT is a foreground program Ctrl-C cannot
         --  stop; see the package header.
         if With_Options.Reset_Signals then
            for Item in Hostkit.Signals.Signal loop
               if Item /= Hostkit.Signals.Signal_Kill
                 and then Item /= Hostkit.Signals.Signal_Stop
               then
                  declare
                     Ignored_Handler : System.Address;
                  begin
                     Ignored_Handler :=
                       C_Signal (C_Int (Hostkit.Signals.Number (Item)), SIG_DFL);
                  end;
               end if;
            end loop;
         end if;

         if With_Options.Replace_Environment then
            declare
               Slot : System.Address
                 with Import => True, Address => NS_Get_Environ;
            begin
               Slot := Envp (Envp'First)'Address;
            end;
         end if;

         Unused := Execvp (Program_C, Argv (Argv'First)'Address);

         --  Only reachable when exec failed.
         Fail_Now;
      end Child_Side;

   begin
      Item := Invalid_Process;

      --  The channel the child reports an exec failure down. Both ends are
      --  close-on-exec, which is the mechanism: a successful exec closes the
      --  write end and the parent's read returns end-of-file.
      if not Hostkit.Descriptors.Create_Pipe (Report) then
         Interfaces.C.Strings.Free (Program_C);
         return Spawn_Failed;
      end if;

      Argv (0) := Interfaces.C.Strings.New_String (Program);
      for Index in 1 .. Count loop
         Argv (Index) :=
           Interfaces.C.Strings.New_String (To_String (Arguments.Element (Index)));
      end loop;
      Argv (Count + 1) := Interfaces.C.Strings.Null_Ptr;

      for Index in 1 .. Env_Count loop
         Envp (Index - 1) :=
           Interfaces.C.Strings.New_String
             (To_String (With_Options.Environment.Element (Index)));
      end loop;
      Envp (Env_Count) := Interfaces.C.Strings.Null_Ptr;

      Child := Fork;

      if Child < 0 then
         Free_Vectors;
         Hostkit.Descriptors.Close (Report.Read_End);
         Hostkit.Descriptors.Close (Report.Write_End);
         return Spawn_Failed;
      end if;

      if Child = 0 then
         Hostkit.Descriptors.Close (Report.Read_End);
         Child_Side;
         Underscore_Exit (Exec_Failed_Status);
      end if;

      --  The parent.
      Hostkit.Descriptors.Close (Report.Write_End);

      --  The parent half of the group race.
      declare
         Unused : C_Int;
      begin
         case With_Options.Group is
            when Group_Inherit =>
               Item.Group := -1;
            when Group_New =>
               Unused := Setpgid (Child, Child);
               Item.Group := Interfaces.Integer_64 (Child);
            when Group_Join =>
               Unused := Setpgid (Child, C_Int (With_Options.Join_Group));
               Item.Group := Interfaces.Integer_64 (With_Options.Join_Group);
         end case;
      end;

      --  Did it exec, or did it fail? End-of-file means the pipe closed
      --  untouched, which only an exec does.
      declare
         Reported : aliased C_Int := 0;
         Got      : constant C_Long :=
           C_Read (To_Native (Report.Read_End),
                   Reported'Address,
                   C_Long (C_Int'Size / 8));
      begin
         Hostkit.Descriptors.Close (Report.Read_End);

         if Got > 0 then
            --  It failed. Reap the corpse so it does not become a zombie, then
            --  report why in the caller's terms.
            declare
               Ignored : C_Int;
               Discard : aliased C_Int := 0;
            begin
               Ignored := Waitpid (Child, Discard'Address, 0);
            end;

            Result := Outcome_For_Errno (Integer (Reported));
            Item := Invalid_Process;
         else
            Item.Id := Interfaces.Integer_64 (Child);
            Result := Spawn_Ok;
         end if;
      end;

      Free_Vectors;
      return Result;
   end Start;

   ----------
   -- Wait --
   ----------

   function Wait
     (Item   : Process_Handle;
      Mode   : Wait_Mode;
      Result : out Status) return Boolean
   is
      Raw       : aliased C_Int := 0;
      Options_C : constant C_Int :=
        (if Mode = Wait_Poll then WNOHANG else 0) + WUNTRACED + WCONTINUED;
      Collected : C_Int;
   begin
      Result := (State              => Wait_Running,
                 Exit_Code          => -1,
                 Terminating_Signal => Hostkit.Signals.Signal_Terminate,
                 Signal_Known       => False,
                 Raw_Signal_Number  => 0);

      if not Is_Valid (Item) then
         return False;
      end if;

      Collected := Waitpid (C_Int (Item.Id), Raw'Address, Options_C);

      if Collected = C_Int (Item.Id) then
         Decode_Status (Raw, Result);
         return True;
      end if;

      if Collected = 0 then
         --  Polling, and it has not changed state.
         Result.State := Wait_Running;
         return True;
      end if;

      --  Negative: no such child. Either it never existed or something else
      --  reaped it -- see the note about Hostkit.Process.Launch in the spec.
      Result.State := Wait_Lost;
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
      Raw       : aliased C_Int := 0;
      Options_C : constant C_Int :=
        (if Mode = Wait_Poll then WNOHANG else 0) + WUNTRACED + WCONTINUED;
      Collected : C_Int;
   begin
      Which  := Invalid_Process;
      Result := (State              => Wait_Running,
                 Exit_Code          => -1,
                 Terminating_Signal => Hostkit.Signals.Signal_Terminate,
                 Signal_Known       => False,
                 Raw_Signal_Number  => 0);

      Collected := Waitpid (-1, Raw'Address, Options_C);

      if Collected > 0 then
         Which.Id := Interfaces.Integer_64 (Collected);
         Decode_Status (Raw, Result);
         return True;
      end if;

      --  Zero means children exist but none has news; negative means there are
      --  none at all. Neither is something to report.
      return False;
   end Wait_Any;

end Hostkit.Spawn;
