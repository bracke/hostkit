with Hostkit.Process;

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

   function Run_Captured
     (Program           : String;
      Arguments         : String_Vectors.Vector;
      Working_Directory : String;
      Stdin_Path        : String;
      Stdout_Path       : String;
      Stderr_Path       : String;
      Timeout_Ms        : Natural;
      Cancelled         : Hostkit.Process.Cancel_Check;
      Poll              : Hostkit.Process.Poll_Hook;
      Started_Notice    : Hostkit.Process.Started_Hook)
      return Hostkit.Process.Process_Outcome
   is
      pragma Unreferenced
        (Program, Arguments, Working_Directory, Stdin_Path, Stdout_Path, Stderr_Path,
         Timeout_Ms, Cancelled, Poll, Started_Notice);
      Nothing : Hostkit.Process.Process_Outcome;
   begin
      return Nothing;
   end Run_Captured;

   function Request_Stop (Process_Id : Integer) return Boolean is
      pragma Unreferenced (Process_Id);
   begin
      return False;
   end Request_Stop;

   function Wait_FD
     (FD         : Integer;
      For_Write  : Boolean;
      Timeout_MS : Integer)
      return Hostkit.Process.Wait_Outcome
   is
      pragma Unreferenced (FD, For_Write, Timeout_MS);
   begin
      return Hostkit.Process.Wait_Error;
   end Wait_FD;

   function Native_Backend_Label return String is
   begin
      return "none";
   end Native_Backend_Label;

   function Current_User_Id (User_Id : out Natural) return Boolean is
   begin
      User_Id := 0;
      return False;
   end Current_User_Id;

   function Current_Group_Id (Group_Id : out Natural) return Boolean is
   begin
      Group_Id := 0;
      return False;
   end Current_Group_Id;

   function Current_Supplementary_Group_Ids
     (Groups : out Hostkit.Process.Group_Id_List;
      Last   : out Natural)
      return Boolean
   is
   begin
      for Index in Groups'Range loop
         Groups (Index) := 0;
      end loop;
      Last := 0;
      return False;
   end Current_Supplementary_Group_Ids;

   function Open_Native (Path : String) return Boolean is
      pragma Unreferenced (Path);
   begin
      return False;
   end Open_Native;

end Hostkit.Native;
