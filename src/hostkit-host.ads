--  Which host is this program running on?
--
--  Asked here because the usual answers are wrong. OSTYPE is a shell variable that a
--  spawned process does not inherit, so a check for it reports "not macOS" on every
--  macOS that did not export it by hand. OS=Windows_NT exists only on one host, which
--  makes its absence mean both "POSIX" and "nobody set it". uname is a spawn away and
--  needs a PATH. Each of those has silently mis-identified a host and sent it down
--  another host's code path.
--
--  Nothing is detected at run time: the build already picked a body per operating
--  system, so each one answers for itself and cannot be fooled by an environment.
package Hostkit.Host is

   type Kind is (Linux, MacOS, Windows, Unsupported);

   --  The host this program was built for. Unsupported is a real answer: it means a
   --  host Hostkit has no body for, not a failure to look.
   function Current return Kind;

   --  Is this process running with administrative privileges -- root, or an
   --  elevated Windows token?
   --
   --  Use it to explain a failure, never to pre-empt an attempt. False means
   --  "not known to be privileged", which on a host Hostkit has no body for is
   --  all that can be said; a caller that skipped the operation on the strength
   --  of it would refuse to do something it might well have been allowed to do.
   --  Try, and if it fails, ask this why.
   --
   --  Per host because the question is: POSIX asks the effective user id,
   --  Windows asks the process token, and neither has any meaning on the other.
   function Is_Elevated return Boolean;

end Hostkit.Host;
