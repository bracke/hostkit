with Interfaces.C;

with System;

package body Hostkit.Signals is

   use type Interfaces.C.int;
   use type System.Address;

   subtype C_Int is Interfaces.C.int;

   --  Linux signal numbers, from asm/signal.h. These are the x86/ARM values,
   --  which is every Linux GNAT targets; the alpha/mips variants differ and are
   --  not supported here. macOS numbers its signals differently from 10 upward
   --  -- SIGUSR1 is 30 there, not 10 -- which is why this table is per host and
   --  not shared.
   SIGHUP    : constant C_Int := 1;
   SIGINT    : constant C_Int := 2;
   SIGQUIT   : constant C_Int := 3;
   SIGKILL   : constant C_Int := 9;
   SIGPIPE   : constant C_Int := 13;
   SIGTERM   : constant C_Int := 15;
   SIGCHLD   : constant C_Int := 17;
   SIGCONT   : constant C_Int := 18;
   SIGSTOP   : constant C_Int := 19;
   SIGTSTP   : constant C_Int := 20;
   SIGTTIN   : constant C_Int := 21;
   SIGTTOU   : constant C_Int := 22;
   SIGWINCH  : constant C_Int := 28;

   --  signal(2) dispositions. These are addresses, not integers: SIG_DFL is 0
   --  and SIG_IGN is 1, but both are compared and passed as function pointers.
   SIG_DFL : constant System.Address := System.Null_Address;
   SIG_IGN : constant System.Address := System'To_Address (1);
   SIG_ERR : constant System.Address := System'To_Address (-1);

   function C_Kill (Pid : C_Int; Sig : C_Int) return C_Int
     with Import => True, Convention => C, External_Name => "kill";

   --  signal(2) rather than sigaction(2). The difference that matters here is
   --  restart semantics for interrupted system calls, and this package only
   --  ever sets a handler to "default" or "ignore" -- neither of which has a
   --  handler to be interrupted into. For anything that installs a real
   --  handler, sigaction would be the right call.
   function C_Signal (Sig : C_Int; Handler : System.Address) return System.Address
     with Import => True, Convention => C, External_Name => "signal";

   function To_Number (Item : Signal) return C_Int;
   --  The host's number, or -1.

   ---------------
   -- To_Number --
   ---------------

   function To_Number (Item : Signal) return C_Int is
   begin
      case Item is
         when Signal_Interrupt        => return SIGINT;
         when Signal_Quit             => return SIGQUIT;
         when Signal_Terminate        => return SIGTERM;
         when Signal_Kill             => return SIGKILL;
         when Signal_Hangup           => return SIGHUP;
         when Signal_Stop             => return SIGSTOP;
         when Signal_Terminal_Stop    => return SIGTSTP;
         when Signal_Continue         => return SIGCONT;
         when Signal_Pipe             => return SIGPIPE;
         when Signal_Background_Read  => return SIGTTIN;
         when Signal_Background_Write => return SIGTTOU;
         when Signal_Window_Change    => return SIGWINCH;
         when Signal_Child            => return SIGCHLD;
      end case;
   end To_Number;

   ------------------
   -- Is_Supported --
   ------------------

   function Is_Supported (Item : Signal) return Boolean is
      pragma Unreferenced (Item);
   begin
      --  Linux defines every signal this enumeration names.
      return True;
   end Is_Supported;

   ------------
   -- Number --
   ------------

   function Number (Item : Signal) return Integer is
   begin
      return Integer (To_Number (Item));
   end Number;

   -----------------
   -- From_Number --
   -----------------

   function From_Number (Value : Integer; Item : out Signal) return Boolean is
   begin
      for Candidate in Signal loop
         if Integer (To_Number (Candidate)) = Value then
            Item := Candidate;
            return True;
         end if;
      end loop;

      --  A real signal this enumeration does not name -- SIGBUS, SIGSYS and the
      --  rest. Reported as unknown rather than mapped to something near it: a
      --  job that died of SIGSEGV must not be reported as terminated by
      --  SIGTERM.
      Item := Signal_Terminate;
      return False;
   end From_Number;

   ----------
   -- Name --
   ----------

   function Name (Item : Signal) return String is
   begin
      case Item is
         when Signal_Interrupt        => return "INTERRUPT";
         when Signal_Quit             => return "QUIT";
         when Signal_Terminate        => return "TERMINATE";
         when Signal_Kill             => return "KILL";
         when Signal_Hangup           => return "HANGUP";
         when Signal_Stop             => return "STOP";
         when Signal_Terminal_Stop    => return "TERMINAL_STOP";
         when Signal_Continue         => return "CONTINUE";
         when Signal_Pipe             => return "PIPE";
         when Signal_Background_Read  => return "BACKGROUND_READ";
         when Signal_Background_Write => return "BACKGROUND_WRITE";
         when Signal_Window_Change    => return "WINDOW_CHANGE";
         when Signal_Child            => return "CHILD";
      end case;
   end Name;

   ---------------------
   -- Send_To_Process --
   ---------------------

   function Send_To_Process (Process_Id : Integer; Item : Signal) return Boolean is
   begin
      if Process_Id <= 0 then
         --  kill(2) reads a non-positive pid as "a group" or "everything I may
         --  signal". A caller that passed a bad id means one process, and
         --  signalling every process it owns instead is not a near miss.
         return False;
      end if;

      return C_Kill (C_Int (Process_Id), To_Number (Item)) = 0;
   end Send_To_Process;

   -------------------
   -- Send_To_Group --
   -------------------

   function Send_To_Group (Group_Id : Integer; Item : Signal) return Boolean is
   begin
      if Group_Id <= 0 then
         --  Negating this would reach pid 0's group -- the shell's own -- and
         --  stop or kill the shell along with everything it started.
         return False;
      end if;

      --  kill(2) signals a group when given the negated group id.
      return C_Kill (-C_Int (Group_Id), To_Number (Item)) = 0;
   end Send_To_Group;

   ---------------------
   -- Set_Disposition --
   ---------------------

   function Set_Disposition (Item : Signal; To : Disposition) return Boolean is
      Handler  : constant System.Address :=
        (case To is
            when Disposition_Default => SIG_DFL,
            when Disposition_Ignore  => SIG_IGN);
      Previous : System.Address;
   begin
      --  POSIX makes these two unchangeable, and signal(2) reports EINVAL. Said
      --  here as well so the refusal does not depend on the C library agreeing.
      if Item = Signal_Kill or else Item = Signal_Stop then
         return False;
      end if;

      Previous := C_Signal (To_Number (Item), Handler);
      return Previous /= SIG_ERR;
   end Set_Disposition;

   -------------------------
   -- Current_Disposition --
   -------------------------

   function Current_Disposition (Item : Signal; To : out Disposition) return Boolean is
      Previous : System.Address;
   begin
      To := Disposition_Default;

      if Item = Signal_Kill or else Item = Signal_Stop then
         return False;
      end if;

      --  signal(2) has no read-only form, so this reads by setting and then
      --  putting back what was there. The window between the two is real: a
      --  signal arriving inside it is handled by the disposition we are about
      --  to undo. Acceptable because a shell asks this at startup, before it
      --  has children to be signalled about, and unacceptable anywhere else --
      --  which is why this is the only reader and it says so.
      Previous := C_Signal (To_Number (Item), SIG_DFL);

      if Previous = SIG_ERR then
         return False;
      end if;

      if C_Signal (To_Number (Item), Previous) = SIG_ERR then
         return False;
      end if;

      To := (if Previous = SIG_IGN then Disposition_Ignore else Disposition_Default);
      return True;
   end Current_Disposition;

end Hostkit.Signals;
