package body Hostkit.Watch is

   use Ada.Strings.Unbounded;

   --  No native notification facility. The watch never becomes active, so the
   --  caller falls back to its polling timer -- the directory listing still
   --  refreshes, just on a timer rather than the instant it changes.

   procedure Watch_Path (State : in out Watch_State; Path : String) is
      pragma Unreferenced (Path);
   begin
      State.Handle := -1;
      State.Extra := -1;
      State.Path := Null_Unbounded_String;
   end Watch_Path;

   procedure Release (State : in out Watch_State) is
   begin
      State.Handle := -1;
      State.Extra := -1;
      State.Path := Null_Unbounded_String;
   end Release;

   function Poll (State : in out Watch_State) return Boolean is
      pragma Unreferenced (State);
   begin
      return False;
   end Poll;

   function Is_Active (State : Watch_State) return Boolean is
      pragma Unreferenced (State);
   begin
      return False;
   end Is_Active;

   function Event_Count (State : Watch_State) return Natural is
   begin
      return State.Events;
   end Event_Count;

end Hostkit.Watch;
