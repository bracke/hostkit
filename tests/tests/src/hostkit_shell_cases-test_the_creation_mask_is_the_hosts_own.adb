separate (Hostkit_Shell_Cases)
procedure Test_The_Creation_Mask_Is_The_Hosts_Own
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);

   Held     : Natural;
   Previous : Natural;
   Restored : Natural;

   use type Hostkit.Host.Kind;
begin
   if Hostkit.Host.Current = Hostkit.Host.Windows then
      Assert (not Hostkit.Fs.Creation_Mask (Held),
              "Windows has no creation mask and must say so");
      Assert (not Hostkit.Fs.Set_Creation_Mask (8#022#, Previous),
              "and must refuse to set one rather than pretend");
      return;
   end if;

   Assert (Hostkit.Fs.Creation_Mask (Held),
           "a POSIX host has a creation mask");

   Assert (Hostkit.Fs.Set_Creation_Mask (8#027#, Previous),
           "and it can be set");
   Assert (Previous = Held,
           "setting it answers with what it was:" & Natural'Image (Previous)
           & " for" & Natural'Image (Held));

   declare
      Now : Natural;
   begin
      Assert (Hostkit.Fs.Creation_Mask (Now),
              "and it can be read again");
      Assert (Now = 8#027#,
              "what was set is what is there:" & Natural'Image (Now));
   end;

   --  Put back, so the rest of this suite writes the files it expects.
   Assert (Hostkit.Fs.Set_Creation_Mask (Held, Restored),
           "and it can be put back");
   Assert (Restored = 8#027#,
           "putting it back answers with what this test had set:"
           & Natural'Image (Restored));
end Test_The_Creation_Mask_Is_The_Hosts_Own;
