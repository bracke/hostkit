separate (Hostkit_Shell_Cases)
procedure Test_A_Resource_Limit_Is_The_Hosts_Own
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);

   use type Hostkit.Host.Kind;
   use type Hostkit.Limits.Amount;

   Soft, Hard, Now : Hostkit.Limits.Amount;
begin
   if Hostkit.Host.Current = Hostkit.Host.Windows then
      Assert (not Hostkit.Limits.Applies (Hostkit.Limits.Open_Files),
              "Windows has no resource limits and must say so");
      Assert (not Hostkit.Limits.Limit
                    (Hostkit.Limits.Open_Files, Hostkit.Limits.Soft, Soft),
              "and must refuse to read one rather than invent a number");
      Assert (not Hostkit.Limits.Set_Limit
                    (Hostkit.Limits.Open_Files, Hostkit.Limits.Soft, 64),
              "and must refuse to set one");
      return;
   end if;

   Assert (Hostkit.Limits.Applies (Hostkit.Limits.Open_Files),
           "a POSIX host limits how many files may be open");

   Assert (Hostkit.Limits.Limit
             (Hostkit.Limits.Open_Files, Hostkit.Limits.Soft, Soft),
           "and the soft limit can be read");
   Assert (Hostkit.Limits.Limit
             (Hostkit.Limits.Open_Files, Hostkit.Limits.Hard, Hard),
           "and the hard limit can be read");

   --  A descriptor count, not a byte count: a host that answered Unbounded
   --  here would be a host that had stopped counting, and the number is
   --  read back below rather than compared against anything expected.
   Assert (Soft /= Hostkit.Limits.Unbounded,
           "how many files may be open is a number this host knows");
   Assert (Soft <= Hard or else Hard = Hostkit.Limits.Unbounded,
           "and the soft limit is not above the ceiling:"
           & Hostkit.Limits.Amount'Image (Soft) & " over"
           & Hostkit.Limits.Amount'Image (Hard));

   Assert (Hostkit.Limits.Set_Limit
             (Hostkit.Limits.Open_Files, Hostkit.Limits.Soft, Soft - 1),
           "and the soft limit can be lowered");

   Assert (Hostkit.Limits.Limit
             (Hostkit.Limits.Open_Files, Hostkit.Limits.Soft, Now),
           "and read again");
   Assert (Now = Soft - 1,
           "what was set is what is there:"
           & Hostkit.Limits.Amount'Image (Now) & " for"
           & Hostkit.Limits.Amount'Image (Soft - 1));

   --  The ceiling did not follow the soft limit down. Which is the whole
   --  reason Set_Limit reads before it writes: the host's call takes both
   --  numbers together, and writing the one a caller named would have
   --  silently written the other.
   declare
      Ceiling : Hostkit.Limits.Amount;
   begin
      Assert (Hostkit.Limits.Limit
                (Hostkit.Limits.Open_Files, Hostkit.Limits.Hard, Ceiling),
              "and the ceiling can be read after lowering the soft limit");
      Assert (Ceiling = Hard,
              "lowering the soft limit left the ceiling where it was:"
              & Hostkit.Limits.Amount'Image (Ceiling) & " for"
              & Hostkit.Limits.Amount'Image (Hard));
   end;

   Assert (Hostkit.Limits.Set_Limit
             (Hostkit.Limits.Open_Files, Hostkit.Limits.Soft, Soft),
           "and it can be put back");
end Test_A_Resource_Limit_Is_The_Hosts_Own;
