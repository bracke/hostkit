package body Hostkit.Signals is

   --  Windows has no signals.
   --
   --  Not "has them under another name": it has no mechanism by which one
   --  process asks another to stop in a way the other may decline, no process
   --  groups in the POSIX sense, and nothing a shell could ignore in order to
   --  survive Ctrl-C while its foreground job receives it. The C runtime's
   --  signal() exists, but it delivers only what this same process raises, and
   --  SIGINT there is a console control event on another thread rather than a
   --  signal -- which is a different contract, not a partial one.
   --
   --  So every operation refuses, and Is_Supported says so before a consumer
   --  builds anything on it. What Windows can do instead is terminate a process
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

   function Set_Disposition (Item : Signal; To : Disposition) return Boolean is
      pragma Unreferenced (Item, To);
   begin
      return False;
   end Set_Disposition;

   function Current_Disposition (Item : Signal; To : out Disposition) return Boolean is
      pragma Unreferenced (Item);
   begin
      To := Disposition_Default;
      return False;
   end Current_Disposition;

end Hostkit.Signals;
