package body Hostkit.Limits is

   --  An unknown host: nothing is claimed, and nothing is pretended. A
   --  refusal here is what sends a caller down the path it would take on
   --  Windows, which is the only other host that has no answer.
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
