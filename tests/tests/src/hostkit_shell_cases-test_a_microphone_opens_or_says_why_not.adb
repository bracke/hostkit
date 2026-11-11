separate (Hostkit_Shell_Cases)
procedure Test_A_Microphone_Opens_Or_Says_Why_Not
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Device : Hostkit.Microphone.Device;
   Result : Hostkit.Microphone.Outcome;
   Reason : Unbounded_String;
   Chunk  : Ada.Streams.Stream_Element_Array (1 .. Hostkit.Microphone.Chunk_Bytes);
begin
   Hostkit.Microphone.Read (Device, Chunk, Result, Reason);
   Assert (Result = Hostkit.Microphone.Failed, "a device never opened read as though recorded");
   Hostkit.Microphone.Open (Device, "", Result, Reason);
   Assert (Hostkit.Microphone.Is_Open (Device) = (Result = Hostkit.Microphone.Done),
           "an open's answer and the device disagree");
   Assert ((Result = Hostkit.Microphone.Done) = (Length (Reason) = 0),
           "a refusal without a reason, or a reason without a refusal");
   if not Hostkit.Microphone.Is_Supported then
      Assert (Result = Hostkit.Microphone.Unsupported, "a host that cannot record did not say so");
   end if;
   if Result = Hostkit.Microphone.Done then
      Hostkit.Microphone.Read (Device, Chunk, Result, Reason);
      Assert (Result = Hostkit.Microphone.Done, "an open microphone did not read: " & To_String (Reason));
   end if;
   Hostkit.Microphone.Close (Device);
   Hostkit.Microphone.Close (Device);
   Assert (not Hostkit.Microphone.Is_Open (Device), "a closed microphone is open");

   --  A source the server does not have is not taken for its default:
   --  never said to be there, and refused, never opened.
   Assert (Hostkit.Microphone.Source_Present ("hostkit-test-no-such-source") /= Hostkit.Microphone.Present,
           "a source that is not there was said to be");
   Hostkit.Microphone.Open (Device, "hostkit-test-no-such-source", Result, Reason);
   Assert (Result /= Hostkit.Microphone.Done and then not Hostkit.Microphone.Is_Open (Device),
           "a source that is not there was opened");
   Assert (Length (Reason) > 0, "a source that is not there was refused without a reason");
   --  And the server's own name for its default is never said to be
   --  missing where there is a server to ask.
   Assert (Hostkit.Microphone.Source_Present ("") /= Hostkit.Microphone.Absent,
           "the default source was said not to be there");
end Test_A_Microphone_Opens_Or_Says_Why_Not;
