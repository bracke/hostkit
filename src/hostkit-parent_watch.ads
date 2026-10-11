--  A child program that should not outlive the program that started it.
--
--  A process a test harness starts and then abandons -- its parent killed,
--  or stopped by a person who saw the answer they wanted -- is adopted by
--  the system and runs on, which for a sweep of conformance parts was an
--  hour of every core nobody asked for. A child that asks this at its start
--  ends when its parent does.
package Hostkit.Parent_Watch is

   --  Arrange for the calling process to end when its parent ends.
   --
   --  Linux: the kernel's parent-death signal (SIGTERM), set after checking
   --  the parent is still the one that started it. macOS: a task that looks
   --  at the parent every half second and ends the process when it has
   --  changed. Elsewhere nothing is arranged.
   --
   --  @return True where it is arranged; False where this host cannot.
   function End_With_Parent return Boolean;

end Hostkit.Parent_Watch;
