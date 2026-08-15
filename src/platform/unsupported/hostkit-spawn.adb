package body Hostkit.Spawn is

   --  A host this build does not know. Nothing can be started, and saying so
   --  is the whole contract -- a Spawn_Failed a caller can report beats a
   --  handle that refers to nothing.

   function Is_Valid (Item : Process_Handle) return Boolean is
   begin
      return Item.Id > 0;
   end Is_Valid;

   function Process_Id (Item : Process_Handle) return Integer is
   begin
      return Integer (Item.Id);
   end Process_Id;

   function Group_Id (Item : Process_Handle) return Integer is
   begin
      return Integer (Item.Group);
   end Group_Id;

   --  There is nothing to make a session on a host this build does not know,
   --  and nothing to start in one either.
   function Supports_Sessions return Boolean is (False);

   function Start
     (Program      : String;
      Arguments    : String_Vectors.Vector;
      With_Options : Options;
      Item         : out Process_Handle) return Spawn_Outcome
   is
      pragma Unreferenced (Program, Arguments, With_Options);
   begin
      Item := Invalid_Process;
      return Spawn_Failed;
   end Start;

   function Wait
     (Item   : Process_Handle;
      Mode   : Wait_Mode;
      Result : out Status) return Boolean
   is
      pragma Unreferenced (Item, Mode);
   begin
      Result := (State              => Wait_Lost,
                 Exit_Code          => -1,
                 Terminating_Signal => Hostkit.Signals.Signal_Terminate,
                 Signal_Known       => False,
                 Raw_Signal_Number  => 0);
      return False;
   end Wait;

   function Wait_Any
     (Mode   : Wait_Mode;
      Which  : out Process_Handle;
      Result : out Status) return Boolean
   is
      pragma Unreferenced (Mode);
   begin
      Which  := Invalid_Process;
      Result := (State              => Wait_Lost,
                 Exit_Code          => -1,
                 Terminating_Signal => Hostkit.Signals.Signal_Terminate,
                 Signal_Known       => False,
                 Raw_Signal_Number  => 0);
      return False;
   end Wait_Any;

end Hostkit.Spawn;
