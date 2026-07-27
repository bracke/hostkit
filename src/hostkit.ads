with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

--  The host's own way of doing things.
--
--  Everything here exists for one reason: the portable-looking helper answers
--  *wrong* on Windows rather than failing, which is far worse, because the code goes
--  on looking correct. GNAT.OS_Lib.Is_Symbolic_Link is always False there (it wants
--  an lstat, and there is none). Is_Executable_File is True for every file that
--  exists -- and for a directory. Set_Executable does nothing at all. Each of those
--  cost a real bug before anyone noticed, and each was then fixed separately, in more
--  than one crate.
--
--  GNAT is not the only source of a confident wrong answer. Two others have cost the
--  same kind of bug, and both look like ordinary portable code:
--
--  Asking the environment which host this is. OSTYPE is a shell variable, not part of
--  the environment a spawned process inherits, so a check for it calls every macOS a
--  Linux -- and goes on doing so, never failing, for as long as the code exists. A
--  consumer that read it reached for update-ca-certificates on a machine whose trust
--  store is the keychain, and its macOS adapter was never once selected. Hostkit.Host
--  answers from the body the build already chose, which no environment can spoof.
--
--  Shelling out to a POSIX tool. `stat -c %a` is GNU syntax; BSD stat wants -f %Lp,
--  and Windows has no stat at all. The command *is* there on macOS, so the call fails
--  in no way the caller notices: it exits non-zero, the caller reads back "cannot
--  tell", and a check on the permissions of a private key -- by then a no-op -- went
--  on reporting that all was well.
--
--  Which is the other half of the contract. "Cannot tell" is not "fine". Several
--  answers here are False on a host that cannot express the question:
--  Accessible_By_Others on Windows, where access is by ACL and this does not read it.
--  That is a refusal to guess, not a clean bill of health, and a caller that stores it
--  as one has rebuilt, on its own side, the bug this crate exists to prevent.
--
--  So each of these has a body per OS, and a comment saying what the host actually
--  does. A consumer asks Hostkit and gets the truth; it does not have to learn again
--  which of GNAT's helpers can be trusted where.
--
--  What belongs here: anything that exists only because the operating systems differ,
--  and that therefore has a per-OS body. What does not: policy, formats, domain rules
--  and anything to do with a user interface. The question to ask of a new subprogram
--  is "does this differ *because the host differs*?" If the answer is no, it belongs
--  to the consumer, not here.
package Hostkit is

   subtype UString is Ada.Strings.Unbounded.Unbounded_String;

   package String_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => UString,
      "="          => Ada.Strings.Unbounded."=");

end Hostkit;
