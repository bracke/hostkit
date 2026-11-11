separate (Hostkit_Shell_Cases)
procedure Test_Presence_Follows_A_Process
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type Hostkit.Process.Presence;
   Options : Hostkit.Spawn.Options;
   Child   : Hostkit.Spawn.Process_Handle;
   Result  : Hostkit.Spawn.Status;
   Args    : Hostkit.String_Vectors.Vector;
   Stopped : Boolean;
   Id      : Integer;
   pragma Warnings (Off, Result);
   pragma Warnings (Off, Stopped);
begin
   if Hostkit.Process.Presence_Of (Hostkit.Host.Own_Process_Id) = Hostkit.Process.Unknown then
      Assert (Hostkit.Process.Presence_Of (1) = Hostkit.Process.Unknown,
              "a host that cannot look answered for another process");
      return;
   end if;
   Assert (Hostkit.Process.Presence_Of (Hostkit.Host.Own_Process_Id) = Hostkit.Process.Present,
           "this process is not there");
   Assert (Hostkit.Process.Presence_Of (0) = Hostkit.Process.Unknown,
           "no process id was answered for");

   Args.Append (To_Unbounded_String ("--hang"));
   Assert (Hostkit.Spawn.Start (Companion ("sleeper"), Args, Options, Child)
           = Hostkit.Spawn.Spawn_Ok,
           "spawning the hanging sleeper failed");
   Id := Hostkit.Spawn.Process_Id (Child);
   Assert (Hostkit.Process.Presence_Of (Id) = Hostkit.Process.Present,
           "a running child is not there");

   Stopped := Hostkit.Process.Request_Stop (Id);
   Assert (Hostkit.Spawn.Wait (Child, Hostkit.Spawn.Wait_Block, Result),
           "reaping the stopped sleeper failed");
   Assert (Hostkit.Process.Presence_Of (Id) = Hostkit.Process.Absent,
           "a reaped child is still there: "
           & Hostkit.Process.Presence'Image (Hostkit.Process.Presence_Of (Id)));
end Test_Presence_Follows_A_Process;
