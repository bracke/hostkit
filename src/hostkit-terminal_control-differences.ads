with Interfaces;

--  What a host did not put back, said precisely.
--
--  A saved Mode is an opaque buffer and stays one: nothing here reads a
--  setting out of it. What this answers is *where* two of them stop agreeing,
--  which is what a report about a host's terminal driver needs and is no use
--  for anything else.
--
--  It is a child rather than an operation of the parent because it is the same
--  on every host, and the parent has one body per OS. It is here rather than in
--  a consumer because the type is private here, so nobody outside can compare
--  two modes and say more than "not equal".
--
--  macOS is why it exists. There `tcsetattr` takes a saved mode, answers
--  success, and the terminal reads back as something else -- on both sides of a
--  pseudo-terminal, with `tcgetattr` stable across two reads. Saying which byte
--  is what turns that from a mystery into a bug report.
package Hostkit.Terminal_Control.Differences is

   --  Where two saved modes first differ, counted from one.
   --
   --  @param Left One saved mode.
   --  @param Right The other.
   --  @param Was The byte Left holds at the first difference.
   --  @param Became The byte Right holds there.
   --  @return Where they first differ, or zero when they hold the same bytes.
   function First_Difference
     (Left   : Mode;
      Right  : Mode;
      Was    : out Interfaces.Unsigned_8;
      Became : out Interfaces.Unsigned_8) return Natural;

end Hostkit.Terminal_Control.Differences;
