separate (Hostkit_Shell_Cases)
procedure Test_A_Child_Can_Own_A_Terminal
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);

   Terminal : Hostkit.Pty.Pair;
   Options  : Hostkit.Spawn.Options;
   Child    : Hostkit.Spawn.Process_Handle;
   Result   : Hostkit.Spawn.Status;
   Ended    : Boolean := False;

   Ctrl_C : constant Ada.Streams.Stream_Element_Array :=
     [1 => Ada.Streams.Stream_Element (3)];
   Last   : Ada.Streams.Stream_Element_Offset;

   --  The sleeper writes its lines and then refuses to finish, which is
   --  what gives an interrupt something to interrupt.
   Hang : Hostkit.String_Vectors.Vector;
begin
   if not Hostkit.Pty.Is_Supported
     or else not Hostkit.Spawn.Supports_Sessions
     or else not Hostkit.Signals.Is_Supported
                   (Hostkit.Signals.Signal_Interrupt)
   then
      --  Windows: no pseudo-terminals, no sessions of this shape and no
      --  signals. Each is answered for separately because a host could
      --  gain one without the others.
      Skip ("Test_A_Child_Can_Own_A_Terminal", "no pseudo-terminal sessions and signals here");
      return;
   end if;

   Hang.Append (Ada.Strings.Unbounded.To_Unbounded_String ("--hang"));

   Assert (Hostkit.Pty.Open (Terminal), "could not open a pseudo-terminal");

   --  Its own session, with this terminal as the controlling one, and its
   --  own group in that terminal's foreground: the three together are what
   --  a keystroke needs to become a signal, and Attach is where they are
   --  arranged.
   Assert (Hostkit.Pty.Attach (Terminal, Options),
           "could not arrange to start a child on a terminal");

   Assert (Hostkit.Spawn.Start
             (Companion ("sleeper"), Hang, Options, Child)
           = Hostkit.Spawn.Spawn_Ok,
           "the sleeper would not start on a terminal");

   Hostkit.Pty.Close_Device (Terminal);

   --  It writes a line before it hangs, so waiting for that is waiting for
   --  a child that has reached its own code rather than for a fixed time.
   declare
      Seen : Boolean := False;
   begin
      for Attempt in 1 .. 100 loop
         declare
            Buffer : Ada.Streams.Stream_Element_Array (1 .. 512);
            Taken  : Ada.Streams.Stream_Element_Offset;
         begin
            if D.Read (Terminal.From_Child, Buffer, Taken) = D.Transfer_Ok
              and then Taken >= Buffer'First
            then
               Seen := True;
               exit;
            end if;
         end;

         delay 0.05;
      end loop;

      Assert (Seen, "the child never wrote to the terminal it was given");
   end;

   Assert (D.Write (Terminal.To_Child, Ctrl_C, Last) = D.Transfer_Ok,
           "could not type into the terminal");

   for Attempt in 1 .. 100 loop
      if Hostkit.Spawn.Wait (Child, Hostkit.Spawn.Wait_Poll, Result)
        and then Result.State /= Hostkit.Spawn.Wait_Running
      then
         Ended := True;
         exit;
      end if;

      delay 0.05;
   end loop;

   Assert (Ended and then Result.State = Hostkit.Spawn.Wait_Signalled,
           "Ctrl-C at the terminal did not reach the child: "
           & Hostkit.Spawn.Wait_State'Image (Result.State));

   Hostkit.Pty.Close (Terminal);
end Test_A_Child_Can_Own_A_Terminal;
