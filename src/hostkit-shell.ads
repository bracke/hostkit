--  Running a command line through the host's shell.
--
--  Three things have to agree: which shell, the flag that introduces its command, and
--  how that command's arguments are quoted. They were each derived separately once,
--  and the result was a shell chosen from COMSPEC -- cmd -- handed arguments quoted
--  for sh, in single quotes, which cmd does not understand and passes through as
--  ordinary text. So they are all answered from one place here.
package Hostkit.Shell is

   --  Does this host's shell speak cmd, rather than sh? COMSPEC is how Windows says
   --  so, and it is what everything else below turns on.
   function Is_Command_Shell return Boolean;

   --  The shell to run: COMSPEC where it is set, else SHELL, else /bin/sh. Empty only
   --  if the host will not admit to having one.
   function Executable return String;

   --  The flag that introduces a command: "/C" for cmd, "-c" for sh.
   function Command_Option return String;

   --  Quote one argument so the shell sees exactly this text and not the words in it.
   --
   --  sh: single quotes, with an embedded ' spliced. cmd: double quotes, with an
   --  embedded " doubled -- single quotes mean nothing to cmd and cannot group
   --  anything, which is exactly the bug this replaced.
   function Quote (Value : String) return String;

   --  A whole command line: the program, quoted, followed by its quoted arguments.
   function Command_Line
     (Program   : String;
      Arguments : String_Vectors.Vector)
      return String;

end Hostkit.Shell;
