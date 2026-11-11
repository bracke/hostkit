separate (Hostkit_Shell_Cases)
procedure Test_A_Write_To_A_Terminal_Nothing_Holds
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);

   Terminal : Hostkit.Pty.Pair;
   Options  : Hostkit.Spawn.Options;
   Child    : Hostkit.Spawn.Process_Handle;
   Result   : Hostkit.Spawn.Status;
   Ended    : Boolean := False;

   Nothing : Hostkit.String_Vectors.Vector;

   Byte : constant Ada.Streams.Stream_Element_Array := [1 => 65];
   Last : Ada.Streams.Stream_Element_Offset;

   Sent : D.Transfer_Outcome;
begin
   if not Hostkit.Pty.Is_Supported then
      --  Only a host this build does not know may lack one; on the
      --  others a missing terminal is a failure, not a pass.
      Assert (Hostkit.Host."=" (Hostkit.Host.Current, Hostkit.Host.Unsupported), "this host has pseudo-terminals");
      return;
   end if;

   Assert (Hostkit.Pty.Open (Terminal), "could not open a pseudo-terminal");
   Assert (Hostkit.Pty.Attach (Terminal, Options),
           "could not arrange to start a child on a terminal");

   --  The leaver writes a line and ends. What it leaves behind is the
   --  point: a terminal with a controller and no device side.
   Assert (Hostkit.Spawn.Start
             (Companion ("leaver"), Nothing, Options, Child)
           = Hostkit.Spawn.Spawn_Ok,
           "the leaver would not start on a terminal");

   --  The parent's copy, which would otherwise hold the device side open
   --  and make this measure nothing at all.
   Hostkit.Pty.Close_Device (Terminal);

   for Attempt in 1 .. 200 loop
      --  Drained while it ends: a program writing into a full terminal
      --  waits, and this one writes a line before it leaves.
      declare
         Buffer : Ada.Streams.Stream_Element_Array (1 .. 512);
         Taken  : Ada.Streams.Stream_Element_Offset;
         Ignored : D.Transfer_Outcome;
      begin
         Ignored := D.Read (Terminal.From_Child, Buffer, Taken);
      end;

      if Hostkit.Spawn.Wait (Child, Hostkit.Spawn.Wait_Poll, Result)
        and then Result.State /= Hostkit.Spawn.Wait_Running
      then
         Ended := True;
         exit;
      end if;

      delay 0.05;
   end loop;

   Assert (Ended, "the leaver would not leave");

   Sent := D.Write (Terminal.To_Child, Byte, Last);

   Ada.Text_IO.Put_Line
     ("write-to-a-terminal-nothing-holds: " & D.Transfer_Outcome'Image (Sent)
      & " host-says=" & Boolean'Image (Hostkit.Pty.Write_Fails_When_Unheld));

   --  A refusal is any outcome that did not take the byte. Which refusal it
   --  is differs -- one host has an errno this crate maps to an error and
   --  another could reasonably call it a broken pipe -- and the caller's
   --  question is not which, it is whether the byte went.
   declare
      Refused : constant Boolean :=
        Sent /= D.Transfer_Ok or else Last < Byte'First;
   begin
      Assert (Refused = Hostkit.Pty.Write_Fails_When_Unheld,
              "this host answers a write to a terminal nothing holds with "
              & D.Transfer_Outcome'Image (Sent)
              & ", and Pty.Write_Fails_When_Unheld says "
              & Boolean'Image (Hostkit.Pty.Write_Fails_When_Unheld));
   end;

   Hostkit.Pty.Close (Terminal);
end Test_A_Write_To_A_Terminal_Nothing_Holds;
