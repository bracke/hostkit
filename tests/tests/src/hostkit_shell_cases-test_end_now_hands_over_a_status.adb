separate (Hostkit_Shell_Cases)
procedure Test_End_Now_Hands_Over_A_Status
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);

   Asked   : Hostkit.String_Vectors.Vector;
   Options : Hostkit.Spawn.Options;
   Child   : Hostkit.Spawn.Process_Handle;
   Result  : Hostkit.Spawn.Status;

   Ends : Hostkit.Descriptors.Pipe_Ends;

   Said : Ada.Strings.Unbounded.Unbounded_String;

begin
   Asked.Append (Ada.Strings.Unbounded.To_Unbounded_String ("9"));

   Assert (D.Create_Pipe (Ends), "no pipe for the companion");
   Assert (D.Set_Inheritable (Ends.Write_End, True),
           "the companion's output would not travel to it");

   Options.Output := Ends.Write_End;

   Assert (Hostkit.Spawn.Start (Companion ("leaver"), Asked, Options, Child)
           = Hostkit.Spawn.Spawn_Ok,
           "the leaver would not start");

   D.Close (Ends.Write_End);

   loop
      declare
         Chunk : Ada.Streams.Stream_Element_Array (1 .. 256);
         Last  : Ada.Streams.Stream_Element_Offset;
      begin
         exit when D.Read (Ends.Read_End, Chunk, Last) /= D.Transfer_Ok;

         for Index in Chunk'First .. Last loop
            Ada.Strings.Unbounded.Append
              (Said, Character'Val (Natural (Chunk (Index))));
         end loop;
      end;
   end loop;

   D.Close (Ends.Read_End);

   Assert (Hostkit.Spawn.Wait (Child, Hostkit.Spawn.Wait_Block, Result),
           "the leaver was not waited for");

   Assert (Result.State = Hostkit.Spawn.Wait_Exited,
           "a program that ended through End_Now did not exit: "
           & Hostkit.Spawn.Wait_State'Image (Result.State));

   Assert (Result.Exit_Code = 9,
           "End_Now handed over the wrong status:"
           & Integer'Image (Result.Exit_Code));

   Assert (Ada.Strings.Fixed.Index
             (Ada.Strings.Unbounded.To_String (Said), "leaving") > 0,
           "the leaver stopped before it reached the call: ["
           & Ada.Strings.Unbounded.To_String (Said) & "]");
end Test_End_Now_Hands_Over_A_Status;
