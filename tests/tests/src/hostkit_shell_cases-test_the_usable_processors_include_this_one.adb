separate (Hostkit_Shell_Cases)
procedure Test_The_Usable_Processors_Include_This_One
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Set   : Hostkit.Host.Processor_Set;
   Count : Natural := 0;
begin
   if not Hostkit.Host.Usable_Processors (Set) then
      Assert (not (for some Usable of Set => Usable),
              "an unknown set named processors");
      Ada.Text_IO.Put_Line ("note: this host does not say which processors are usable");
      return;
   end if;
   for Usable of Set loop
      if Usable then
         Count := Count + 1;
      end if;
   end loop;
   --  At least the one running this, and no more than the host has.
   Assert (Count >= 1, "no processor was usable");
   Assert (Count <= Hostkit.Host.Most_Processors, "more processors than the set holds");
end Test_The_Usable_Processors_Include_This_One;
