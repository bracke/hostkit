with Hostkit.Process;

package body Hostkit.Spawn.Supervision is

   function Stop_Now (Item : Process_Handle) return Boolean is
   begin
      return Hostkit.Signals.Send_To_Process (Process_Id (Item), Hostkit.Signals.Signal_Kill)
        or else Hostkit.Process.Request_Stop (Process_Id (Item));
   end Stop_Now;

   function Has_Ended (Item : Process_Handle; Result : out Status) return Boolean is
   begin
      if not Wait (Item, Wait_Poll, Result) then
         Result.State := Wait_Lost;
      end if;
      return Result.State in Wait_Exited | Wait_Signalled | Wait_Lost;
   end Has_Ended;

   function Has_Ended (Item : Process_Handle) return Boolean is
      Result : Status;
   begin
      return Has_Ended (Item, Result);
   end Has_Ended;

end Hostkit.Spawn.Supervision;
