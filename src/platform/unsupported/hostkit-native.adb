package body Hostkit.Native is

   --  An unknown host: nothing is claimed, and nothing is pretended.
   procedure Reap_Finished_Children is
   begin
      null;
   end Reap_Finished_Children;

   function Supports_Raw_Command_Line return Boolean is
   begin
      return False;
   end Supports_Raw_Command_Line;

   function Run_Command_Line
     (Command     : String;
      Wait        : Boolean;
      Exit_Status : out Integer)
      return Boolean
   is
      pragma Unreferenced (Command, Wait);
   begin
      Exit_Status := -1;
      return False;
   end Run_Command_Line;

   function Open_Native (Path : String) return Boolean is
      pragma Unreferenced (Path);
   begin
      return False;
   end Open_Native;

end Hostkit.Native;
