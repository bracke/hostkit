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
