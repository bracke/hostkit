--  A test's way to drive the POSIX directory read with a readdir that it
--  scripts itself, since no host lets a test make a real read fail
--  part-way on demand. The POSIX hosts bring the body that does it; a host
--  with no POSIX directory read says it cannot.
package Hostkit.Directory_Reading_Probe is

   --  How a scripted read ends after its one entry.
   type Ending is
     (Clean_End,        --  readdir answers NULL with errno left at 0
      Failed_Midway,    --  readdir answers NULL with errno set (EIO)
      Stale_Errno_End,  --  the entry's visit leaves errno set, then a clean end
      Visit_Stops);     --  the visit asks to stop at the entry

   --  Whether this host has the POSIX directory read to probe.
   --
   --  @return False where it has none.
   function Available return Boolean;

   --  Read a scripted directory of one entry that ends as How says.
   --
   --  @param How How the read ends.
   --  @param Visited How many entries the read handed over.
   --  @return What the read answered: True for a whole read.
   function Read (How : Ending; Visited : out Natural) return Boolean;

end Hostkit.Directory_Reading_Probe;
