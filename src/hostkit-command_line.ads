--  The arguments this process was actually started with.
--
--  What this is for: on Windows the arguments a program receives have already
--  been through the C runtime, which parses one command-line *string* back
--  into a vector -- and, depending on how the runtime was built, expands a
--  wildcard in it against the current directory first. A tool whose arguments
--  are patterns rather than file names is then answering a question nobody
--  asked: `grep foo "*.txt"` arrives as the names of the .txt files in the
--  directory the command ran in, so a pattern that should match across
--  directories matches only that one. git carries its own defence against
--  this (compat/mingw.c turns the runtime's expansion off); the knobs it uses
--  are not honoured by every runtime a program can be built against.
--
--  So: ask the operating system for the command line and split it here. On
--  Windows that is GetCommandLineW plus CommandLineToArgvW, which implements
--  the same quoting rules the runtime does and performs no expansion.
--  Everywhere else the kernel already hands over a vector and nothing has
--  touched it, so Ada.Command_Line is the answer.
--
--  The result is the same on every host for the same invocation, which is the
--  whole point: a consumer reads its arguments once, through here, and does
--  not have to know that one host rewrote them.
package Hostkit.Command_Line is

   function Argument_Count return Natural;
   --  How many arguments follow the program name.

   function Argument (Index : Positive) return String;
   --  Argument number Index, counted from 1 as Ada.Command_Line does.
   --  Raises Constraint_Error when Index is above Argument_Count.

end Hostkit.Command_Line;
