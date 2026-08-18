with Interfaces;

--  What the host will let this process use, and what a process may give up.
--
--  POSIX calls these resource limits and every shell exposes them as `ulimit`,
--  because they are the one setting a shell can change on its own behalf that
--  a child then inherits: a script that is about to run something untrusted
--  lowers a limit first, and what it lowered stays lowered for everything it
--  starts.
--
--  Two numbers per resource. The soft limit is what the host enforces; the
--  hard limit is the ceiling the soft one may be raised to. A process may
--  lower either and may raise the soft one up to the hard one; raising the
--  hard one needs privilege, and this says so by refusing rather than by
--  raising an exception.
package Hostkit.Limits is

   --  The resources the hosts that have limits agree about.
   --
   --  Deliberately not every RLIMIT_ a host defines. The numbers behind these
   --  names differ between hosts -- RLIMIT_NPROC is 6 on Linux and 7 on macOS,
   --  and RLIMIT_AS shares its number with RLIMIT_RSS on macOS -- which is
   --  exactly why the mapping belongs in a body per host rather than in a
   --  consumer that read a header once.
   type Resource is
     (Open_Files,      --  How many descriptors at once.
      Processes,       --  How many processes this user may have.
      File_Size,       --  How large a file this process may write.
      Core_Size,       --  How large a core dump may be.
      Stack_Size,      --  How far the stack may grow.
      Data_Size,       --  How large the data segment may grow.
      Address_Space,   --  How much address space may be mapped at once.
      Locked_Memory,   --  How much memory may be held out of the pager.
      Processor_Time); --  How many seconds of processor time.

   --  Which of the two numbers is meant.
   type Bound is (Soft, Hard);

   --  A limit, as the host counts it: bytes for the sizes, seconds for
   --  Processor_Time, a count for the rest. No unit is applied here -- a shell
   --  that wants kilobytes because that is what its users type divides where
   --  the user can see it happen.
   subtype Amount is Interfaces.Unsigned_64;

   --  No limit at all.
   --
   --  The hosts spell infinity differently -- Linux uses every bit, macOS uses
   --  all but the sign -- so neither number reaches a caller. Each body maps
   --  its own to this one, and a caller compares against this rather than
   --  against a constant it copied out of a header.
   Unbounded : constant Amount := Amount'Last;

   --  What this limit is now.
   --
   --  @param Item Which resource.
   --  @param Which The soft limit or the hard one.
   --  @param Value The limit, or Unbounded.
   --  @return False where this host has no such limit to read.
   function Limit
     (Item  : Resource;
      Which : Bound;
      Value : out Amount) return Boolean;

   --  Set it.
   --
   --  Only the named bound moves: the other is read and written back
   --  unchanged, because the host's own call takes both together and a caller
   --  that meant to lower the soft limit did not mean to lower the ceiling
   --  with it.
   --
   --  False when the host refused -- a soft limit above the hard one, a hard
   --  limit raised without privilege, or a host with no limits at all. Which
   --  of those it was is not reported: the hosts do not agree on how they say
   --  so, and a caller can read the limit back and see.
   --
   --  @param Item Which resource.
   --  @param Which The soft limit or the hard one.
   --  @param Value The new limit, or Unbounded.
   --  @return False where this host would not, or has no such limit.
   function Set_Limit
     (Item  : Resource;
      Which : Bound;
      Value : Amount) return Boolean;

   --  Does this host have this limit at all?
   --
   --  Asked separately because a caller listing every limit -- which is what
   --  `ulimit -a` is -- needs to tell "this host does not have that one" from
   --  "that one could not be read just now", and a False from Limit says both.
   --
   --  @param Item Which resource.
   --  @return False where this host does not have it.
   function Applies (Item : Resource) return Boolean;

end Hostkit.Limits;
