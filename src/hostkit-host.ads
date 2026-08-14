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

   --  Which locale is this host itself configured for?
   --
   --  Windows and macOS each keep one and will say: GetUserDefaultLocaleName
   --  reads the user's regional setting, CFLocaleCopyCurrent the user's
   --  preferred locale. The identifier comes back in the host's own spelling --
   --  "en-GB" from Windows, "en_GB" from macOS -- and is returned as given,
   --  because normalising it is the caller's convention, not the host's fact.
   --
   --  POSIX has no such call. The locale there is an environment convention
   --  (LC_ALL, LC_MESSAGES, LANG) that any process can set for itself, plus
   --  whatever files the desktop environment keeps, and reading those is the
   --  caller's business rather than a fact this crate can state -- so Linux
   --  answers with the empty string, meaning "ask the environment", not "no
   --  locale".
   --
   --  @return The host's locale identifier, or "" where the host has none to
   --          give.
   function Native_Locale return String;

   --  The path of the running executable, resolved.
   --
   --  Ada.Command_Line.Command_Name gives back whatever the caller typed: a
   --  bare name found on PATH, a relative path from a directory since changed,
   --  a symbolic link. A program that wants to find data installed beside
   --  itself needs the real location, and every host keeps it somewhere else --
   --  /proc/self/exe, _NSGetExecutablePath, GetModuleFileName.
   --
   --  Empty when the host will not say, which is a real answer: the caller
   --  should fall back to the command name rather than treat it as a failure.
   function Executable_Path return String;

   --  Which process this is.
   --
   --  Wanted whenever a program has to name itself to something that takes a
   --  process id: sending itself a signal, writing a lock or pid file, telling
   --  a supervisor what to watch.
   --
   --  @return This process's identifier, or -1 on a host that cannot say. A
   --          refusal rather than zero, which is a real process id on POSIX
   --          and would be believed.
   function Own_Process_Id return Integer;

   --  Operating-system name for uname-style reporting. Empty means unavailable.
   function System_Name return String;

   --  Network node name for uname-style reporting. Empty means unavailable.
   function Node_Name return String;

   --  Attempt to change the network node name.
   --
   --  This is a privileged operation on the hosts that support it. False means
   --  the host refused it, the name is not representable for the native call,
   --  or this Hostkit body does not know how to perform it.
   function Set_Node_Name (Name : String) return Boolean;

   --  Operating-system release for uname-style reporting. Empty means unavailable.
   function Release_Name return String;

   --  Operating-system version for uname-style reporting. Empty means unavailable.
   function Version_Name return String;

   --  Hardware or processor class for uname-style reporting. Empty means unavailable.
   function Machine_Name return String;

   --  Login name for the user associated with this session, for logname-style
   --  reporting. Empty means unavailable; callers that need an environment
   --  convention such as LOGNAME should apply that policy themselves.
   function Login_Name return String;

   --  A standard stream a program may be sharing with a person.
   type Stream_Kind is (Standard_Input, Standard_Output, Standard_Error);

   --  Report whether a standard stream is attached to a terminal.
   --
   --  A program answers this to decide whether to colour its output, draw a
   --  progress line, or hold a conversation -- all of which are noise when
   --  the stream is a file or a pipe. It is a question about the stream and
   --  not about the program: standard output may be redirected while standard
   --  error is still a terminal, and both are ordinary.
   --
   --  The hosts do not agree on how to ask. POSIX has isatty on a descriptor;
   --  Windows has GetConsoleMode on a handle and spells the C name _isatty,
   --  so a program importing isatty by that name builds on one and not the
   --  other. False when the host will not say, because treating an unknown
   --  destination as a terminal is what puts escape sequences in a log file.
   --
   --  @param Stream Which standard stream to ask about.
   --  @return True when that stream is a terminal.
   function Is_Terminal (Stream : Stream_Kind) return Boolean;

end Hostkit.Host;
