separate (Hostkit_Shell_Cases)
procedure Test_Every_Named_Limit_Is_Answered
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);

   use type Hostkit.Host.Kind;
begin
   for Item in Hostkit.Limits.Resource loop
      declare
         Known : constant Boolean := Hostkit.Limits.Applies (Item);

         Now, Ceiling : Hostkit.Limits.Amount;

         --  Read before the assertions rather than inside them: the
         --  arguments of one call are evaluated in whatever order the
         --  compiler likes, so a message that named the value the same
         --  call was writing would be a message about the value before it.
         Read_Soft : constant Boolean :=
           Hostkit.Limits.Limit (Item, Hostkit.Limits.Soft, Now);
         Read_Hard : constant Boolean :=
           Hostkit.Limits.Limit (Item, Hostkit.Limits.Hard, Ceiling);
      begin
         Assert (Known = (Hostkit.Host.Current /= Hostkit.Host.Windows),
                 "a POSIX host has "
                 & Hostkit.Limits.Resource'Image (Item)
                 & " and Windows has none");

         Assert (Read_Soft = Known,
                 "reading "
                 & Hostkit.Limits.Resource'Image (Item)
                 & " agrees with whether this host has it, and it said"
                 & Hostkit.Limits.Amount'Image (Now));

         Assert (Read_Hard = Known,
                 "and so does reading the ceiling of "
                 & Hostkit.Limits.Resource'Image (Item)
                 & ", which said"
                 & Hostkit.Limits.Amount'Image (Ceiling));
      end;
   end loop;
end Test_Every_Named_Limit_Is_Answered;
