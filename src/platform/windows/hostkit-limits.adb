package body Hostkit.Limits is

   --  Windows has no per-process resource limits of this kind. What it has is
   --  a job object, which is a different thing with a different shape: it is
   --  attached to a set of processes rather than inherited by them, several of
   --  its limits have no POSIX equivalent, and a process cannot lower its own
   --  the way `ulimit` does. Answering out of it -- reporting a job's memory
   --  cap as an address-space limit, say -- would give a caller a number it
   --  could not then set, so this refuses instead. A caller that wants to cap
   --  a child on Windows wants a job object, and that is a different question
   --  than this one.
   function Applies (Item : Resource) return Boolean is
      pragma Unreferenced (Item);
   begin
      return False;
   end Applies;

   function Limit
     (Item  : Resource;
      Which : Bound;
      Value : out Amount) return Boolean
   is
      pragma Unreferenced (Item, Which);
   begin
      Value := 0;
      return False;
   end Limit;

   function Set_Limit
     (Item  : Resource;
      Which : Bound;
      Value : Amount) return Boolean
   is
      pragma Unreferenced (Item, Which, Value);
   begin
      return False;
   end Set_Limit;

end Hostkit.Limits;
