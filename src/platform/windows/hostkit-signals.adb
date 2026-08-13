with Interfaces.C;

package body Hostkit.Signals is

   --  Windows has no signals, and can still tell a program about Ctrl-C.
   --
   --  Those are two different statements, and this body makes both. Everything
   --  that treats a signal as a value -- numbering it, sending it, giving it a
   --  disposition -- refuses, because none of it exists here. What does exist
   --  is a console control handler, which answers exactly one of the questions
   --  Hostkit.Signals asks: did the user ask to interrupt? So Can_Record says
   --  yes for Signal_Interrupt and no for everything else, while Is_Supported
   --  keeps saying no across the board.
   --
   --  The mechanism is genuinely different from a POSIX handler and the
   --  difference matters. SetConsoleCtrlHandler runs the routine on a *thread
   --  Windows creates for it*, not between two instructions of the interrupted
   --  one. That makes it less constrained than a POSIX handler in what it may
   --  call, and more constrained in what it may assume: nothing is paused
   --  while it runs. Setting one atomic flag is correct under both readings,
   --  which is the whole reason the recorded-signal contract is a flag.
   --
   --  Returning TRUE from the routine is what stops Windows terminating the
   --  process, so recording and surviving are the same act here. Ctrl-Break is
   --  deliberately left alone: it still terminates, which keeps one way out of
   --  a program that has stopped listening on a host with no kill.
   --
   --  Not "has them under another name": it has no mechanism by which one
   --  process asks another to stop in a way the other may decline, no process
   --  groups in the POSIX sense, and nothing a shell could ignore in order to
   --  survive Ctrl-C while its foreground job receives it. The C runtime's
   --  signal() exists, but it delivers only what this same process raises, and
   --  SIGINT there is a console control event on another thread rather than a
   --  signal -- which is a different contract, not a partial one.
   --
   --  So sending refuses, and Is_Supported says so before a consumer builds
   --  anything on it. What Windows can do instead is terminate a process
   --  outright, which is Hostkit.Process.Request_Stop, and a consumer that
   --  needs job control has to degrade to that explicitly rather than discover
   --  it here.
   --
   --  Refusing is the point. Returning True from Set_Disposition would let a
   --  shell believe it had disarmed SIGPIPE and go on to lose itself to the
   --  first truncated pipeline -- except that on this host there is no SIGPIPE
   --  to lose it to, which is exactly the sort of near-miss reasoning that
   --  produces a wrong answer later. False here, and the consumer decides.

   function Is_Supported (Item : Signal) return Boolean is
      pragma Unreferenced (Item);
   begin
      return False;
   end Is_Supported;

   function Number (Item : Signal) return Integer is
      pragma Unreferenced (Item);
   begin
      --  -1 rather than a plausible POSIX number: a consumer printing a number
      --  this host does not have would be inventing one.
      return -1;
   end Number;

   function From_Number (Value : Integer; Item : out Signal) return Boolean is
      pragma Unreferenced (Value);
   begin
      Item := Signal_Terminate;
      return False;
   end From_Number;

   --  Names are host-independent identifiers rather than the host's spelling,
   --  so they are answerable even here. A message that has to say how a job
   --  ended still works on a host that cannot have ended it that way.
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

   function Send_To_Process (Process_Id : Integer; Item : Signal) return Boolean is
      pragma Unreferenced (Process_Id, Item);
   begin
      --  Deliberately not "terminate it anyway". Hostkit.Process.Request_Stop
      --  is where that lives, under a name that says it cannot be declined; a
      --  Send_To_Process that quietly killed would make Signal_Continue and
      --  Signal_Window_Change lethal.
      return False;
   end Send_To_Process;

   function Send_To_Group (Group_Id : Integer; Item : Signal) return Boolean is
      pragma Unreferenced (Group_Id, Item);
   begin
      return False;
   end Send_To_Group;

   subtype C_Int is Interfaces.C.int;
   subtype C_DWord is Interfaces.C.unsigned_long;

   use type C_Int;
   use type C_DWord;

   --  What the console sends. Only the first is claimed; see the note above on
   --  why Ctrl-Break keeps its default.
   Control_C_Event : constant C_DWord := 0;

   --  True from the moment Windows reports Ctrl-C until Clear.
   --
   --  Atomic because the routine that sets it runs on a thread of Windows'
   --  making while this one runs on, and a plain Boolean written by one thread
   --  and read by another is not something either compiler owes an answer for.
   Interrupt_Arrived : Boolean := False;
   pragma Atomic (Interrupt_Arrived);

   --  Whether this process has added the routine, and whether it has asked for
   --  Ctrl-C to be ignored. Windows keeps a list rather than a slot: adding the
   --  same routine twice means removing it twice, so the state is tracked here
   --  instead of asked for later.
   Installed : Boolean := False;
   Ignoring  : Boolean := False;

   type Handler_Routine is
     access function (Control_Type : C_DWord) return C_Int
     with Convention => Stdcall;

   function Set_Console_Ctrl_Handler
     (Handler : Handler_Routine; Add : C_Int) return C_Int
     with Import, Convention => Stdcall,
          External_Name => "SetConsoleCtrlHandler";

   function Console_Handler (Control_Type : C_DWord) return C_Int
     with Convention => Stdcall;

   --  Sets one flag and returns. Nothing else belongs here: this runs on a
   --  thread created for it, concurrently with whatever the program was doing,
   --  so anything it touched would need to be safe to touch concurrently.
   --
   --  1 means handled, which is also what stops Windows ending the process.
   --  0 passes the event on, and for anything but Ctrl-C that is what should
   --  happen -- a close or a logoff is not an interrupt and must not be
   --  recorded as one, nor silently swallowed.
   function Console_Handler (Control_Type : C_DWord) return C_Int is
   begin
      if Control_Type = Control_C_Event then
         Interrupt_Arrived := True;
         return 1;
      end if;

      return 0;
   end Console_Handler;

   ----------------
   -- Can_Record --
   ----------------

   function Can_Record (Item : Signal) return Boolean is
   begin
      return Item = Signal_Interrupt;
   end Can_Record;

   ---------------------
   -- Set_Disposition --
   ---------------------

   function Set_Disposition (Item : Signal; To : Disposition) return Boolean is
      Result : C_Int;
   begin
      --  Every other signal is absent, not merely unhandled.
      if Item /= Signal_Interrupt then
         return False;
      end if;

      --  Ignoring is a separate mechanism from handling -- a null routine,
      --  which Windows documents as "discard Ctrl-C" -- so leaving one state
      --  always means undoing it before entering the other. Doing it first,
      --  and refusing if it fails, keeps this from reporting success while
      --  Ctrl-C is still being discarded.
      if Ignoring and then To /= Disposition_Ignore then
         Result := Set_Console_Ctrl_Handler (null, 0);

         if Result = 0 then
            return False;
         end if;

         Ignoring := False;
      end if;

      case To is
         when Disposition_Record =>
            if Installed then
               return True;
            end if;

            Result := Set_Console_Ctrl_Handler (Console_Handler'Access, 1);

            if Result = 0 then
               return False;
            end if;

            Installed := True;
            return True;

         when Disposition_Ignore =>
            if Ignoring then
               return True;
            end if;

            Result := Set_Console_Ctrl_Handler (null, 1);

            if Result = 0 then
               return False;
            end if;

            Ignoring := True;
            return True;

         when Disposition_Default =>
            if not Installed then
               return True;
            end if;

            Result := Set_Console_Ctrl_Handler (Console_Handler'Access, 0);

            if Result = 0 then
               return False;
            end if;

            Installed := False;
            return True;
      end case;
   end Set_Disposition;

   -------------
   -- Arrived --
   -------------

   function Arrived (Item : Signal) return Boolean is
   begin
      --  False for the rest because nothing can record them, not because none
      --  arrived. A caller that wants to know which is which asks Can_Record.
      return Item = Signal_Interrupt and then Interrupt_Arrived;
   end Arrived;

   -----------
   -- Clear --
   -----------

   procedure Clear (Item : Signal) is
   begin
      if Item = Signal_Interrupt then
         Interrupt_Arrived := False;
      end if;
   end Clear;

   -------------------------
   -- Current_Disposition --
   -------------------------

   function Current_Disposition (Item : Signal; To : out Disposition) return Boolean is
   begin
      --  Answerable for the interrupt because this body set it. Windows has no
      --  call that reports the current console handler, so what is returned is
      --  what was installed from here -- true for a program that goes through
      --  Hostkit, and knowably not true for one that also calls the API
      --  directly. Every other signal is unknown because it does not exist.
      if Item /= Signal_Interrupt then
         To := Disposition_Default;
         return False;
      end if;

      To :=
        (if Ignoring then Disposition_Ignore
         elsif Installed then Disposition_Record
         else Disposition_Default);
      return True;
   end Current_Disposition;

end Hostkit.Signals;
