--  Running a command line through the host's shell.
--
--  Three things have to agree: which shell, the flag that introduces its command, and
--  how that command's arguments are quoted. They were each derived separately once,
--  and the result was a shell chosen from COMSPEC -- cmd -- handed arguments quoted
--  for sh, in single quotes, which cmd does not understand and passes through as
--  ordinary text. So they are all answered from one place here, and the answer turns
--  on the host the build targets, never on the environment.
package Hostkit.Shell is

   --  Does this host's shell speak cmd, rather than sh? True on a Windows build and
   --  only there: COMSPEC is set on Linux machines that run Wine, so it cannot say.
   function Is_Command_Shell return Boolean;

   --  The shell that runs a command line built with Quote and Command_Line: on
   --  Windows COMSPEC where it is set, else cmd.exe; elsewhere /bin/sh, always.
   --
   --  Not SHELL: the quoting below is sh's, and a user's login shell need not speak
   --  it -- fish, nushell and tcsh each read a quoted backslash or a spliced quote
   --  their own way, so a command quoted for sh and run by SHELL ran something else.
   --  Empty only if the host will not admit to having one.
   function Executable return String;

   --  The shell a person would be given to type into: SHELL where it is set, else
   --  /bin/sh; on Windows what Executable names. For opening an interactive shell
   --  only -- never for running a command line Quote built, which is Executable's.
   function Interactive_Executable return String;

   --  The flag that introduces a command: "/C" for cmd, "-c" for sh.
   function Command_Option return String;

   --  Quote one argument for sh: single quotes, with an embedded ' spliced as '\''.
   --
   --  @param Value The argument's text.
   --  @return The quoted argument; "" when Value holds a NUL, which no command line
   --    can carry.
   function Sh_Quote (Value : String) return String;

   --  Quote one argument for cmd: double quotes, with an embedded " doubled --
   --  single quotes mean nothing to cmd and cannot group anything.
   --
   --  Some text cannot be quoted for cmd at all. cmd expands %NAME% on the command
   --  line inside quotes as well as out, and has no escape for % that works there
   --  (^% is literal inside quotes, and %% is literal only in a batch file), so an
   --  argument holding % would reach the program with a variable's value in place
   --  of its text; a line break ends the command, and the rest would run as one of
   --  its own. Such an argument is refused rather than quoted: Executable is not
   --  handed text it would change. A caller with such an argument starts the
   --  program directly (Hostkit.Process.Launch, Hostkit.Spawn), where no shell
   --  reads it.
   --
   --  @param Value The argument's text.
   --  @return The quoted argument; "" when Value holds %, a carriage return, a line
   --    feed or a NUL.
   function Cmd_Quote (Value : String) return String;

   --  Quote one argument so this host's shell sees exactly this text and not the
   --  words in it: Cmd_Quote where Is_Command_Shell, else Sh_Quote.
   --
   --  @param Value The argument's text.
   --  @return The quoted argument; "" when this host's shell cannot be handed Value
   --    unchanged (see Cmd_Quote). A quoted empty argument is never "".
   function Quote (Value : String) return String;

   --  Can Value be handed to this host's shell unchanged?
   --
   --  @param Value The argument's text.
   --  @return False exactly when Quote refuses it.
   function Can_Quote (Value : String) return Boolean is (Quote (Value) /= "");

   --  A whole command line: the program, quoted, followed by its quoted arguments.
   --
   --  @param Program The program to run.
   --  @param Arguments Its arguments.
   --  @return The command line; "" when Quote refuses the program or any argument,
   --    which Hostkit.Process.Run_Shell_Command refuses in turn, so the failure
   --    reaches the caller rather than a changed command reaching the shell.
   function Command_Line
     (Program   : String;
      Arguments : String_Vectors.Vector)
      return String;

end Hostkit.Shell;
