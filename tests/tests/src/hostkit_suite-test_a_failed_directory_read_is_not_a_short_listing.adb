with Hostkit.Directory_Reading_Probe;
separate (Hostkit_Suite)
procedure Test_A_Failed_Directory_Read_Is_Not_A_Short_Listing
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   package Probe renames Hostkit.Directory_Reading_Probe;
   Visited : Natural;
begin
   if not Probe.Available then
      Skip ("Test_A_Failed_Directory_Read_Is_Not_A_Short_Listing", "this host has no POSIX directory read");
      return;
   end if;
   Assert (Probe.Read (Probe.Clean_End, Visited) and then Visited = 1, "a read to its end is whole");
   Assert (not Probe.Read (Probe.Failed_Midway, Visited) and then Visited = 1,
           "a read that fails after an entry is a failed read, not a listing of one");
   Assert (Probe.Read (Probe.Stale_Errno_End, Visited) and then Visited = 1,
           "errno left over from before the last readdir is not taken for its failure");
   Assert (Probe.Read (Probe.Visit_Stops, Visited) and then Visited = 1,
           "a read its visitor stops is a whole read");
end Test_A_Failed_Directory_Read_Is_Not_A_Short_Listing;
