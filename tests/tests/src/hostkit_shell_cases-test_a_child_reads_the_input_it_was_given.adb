separate (Hostkit_Shell_Cases)
procedure Test_A_Child_Reads_The_Input_It_Was_Given
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   To_Child   : D.Pipe_Ends;
   From_Child : D.Pipe_Ends;
   Options    : Hostkit.Spawn.Options;
   Child      : Hostkit.Spawn.Process_Handle;
   Result     : Hostkit.Spawn.Status;
   --  Set by a call whose success is what is asserted, not its result.
   pragma Warnings (Off, Result);
   No_Args    : Hostkit.String_Vectors.Vector;
   Line       : constant Ada.Streams.Stream_Element_Array (1 .. 7) :=
     [104, 101, 108, 108, 111, 10, 10];
   Last       : Ada.Streams.Stream_Element_Offset;
   --  Set by a call whose success is what is asserted, not its result.
   pragma Warnings (Off, Last);
begin
   Assert (D.Create_Pipe (To_Child), "could not create the input pipe");
   Assert (D.Create_Pipe (From_Child), "could not create the output pipe");

   Assert (D.Set_Inheritable (To_Child.Read_End, True), "input end not inheritable");
   Assert (D.Set_Inheritable (From_Child.Write_End, True), "output end not inheritable");

   Options.Input  := To_Child.Read_End;
   Options.Output := From_Child.Write_End;

   Assert (Hostkit.Spawn.Start (Companion ("echoer"), No_Args, Options, Child)
           = Hostkit.Spawn.Spawn_Ok,
           "spawning the echoer failed");

   D.Close (To_Child.Read_End);
   D.Close (From_Child.Write_End);

   Assert (D.Write (To_Child.Write_End, Line, Last) = D.Transfer_Ok,
           "writing to the child failed");
   D.Close (To_Child.Write_End);

   declare
      Output : constant String := Drain (From_Child.Read_End);
   begin
      --  Two pipes at once, in both directions. This is the shape of every
      --  pipeline stage, and the test that would catch the ends being
      --  crossed.
      Assert (Contains (Output, "read:hello"),
              "the child did not read what it was given; got: " & Output);
   end;

   D.Close (From_Child.Read_End);

   Assert (Hostkit.Spawn.Wait (Child, Hostkit.Spawn.Wait_Block, Result),
           "waiting for the echoer failed");
end Test_A_Child_Reads_The_Input_It_Was_Given;
