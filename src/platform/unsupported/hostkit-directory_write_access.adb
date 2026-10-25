package body Hostkit.Directory_Write_Access is
   function Prepare (Path : String; State : in out Context) return Boolean is
      pragma Unreferenced (Path, State);
   begin
      return True;
   end Prepare;

   function Finish (State : in out Context) return Boolean is
      pragma Unreferenced (State);
   begin
      return True;
   end Finish;

   procedure Release (State : in out Context) is
      pragma Unreferenced (State);
   begin
      null;
   end Release;
end Hostkit.Directory_Write_Access;
