separate (Hostkit_Suite)
procedure Test_Run_Reports_Exit_Status (T : in out AUnit.Test_Cases.Test_Case'Class) is
   pragma Unreferenced (T);
   Empty  : Hostkit.String_Vectors.Vector;
   Status : Integer := -1;
   Ran    : Boolean;
begin
   Ran := Hostkit.Process.Run (Companion ("noop"), Empty, Status);
   Assert (Ran, "a program that succeeds is reported as having run");
   Assert (Status = 0, "and its exit status is zero; was " & Status'Image);

   Ran := Hostkit.Process.Run (Companion ("failing"), Empty, Status);
   Assert (not Ran, "a program that fails is not reported as successful");
   Assert (Status = 7, "and its own exit status is reported; was " & Status'Image);
end Test_Run_Reports_Exit_Status;
