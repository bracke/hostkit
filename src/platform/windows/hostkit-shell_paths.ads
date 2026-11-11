--  A path the Windows shell, and CreateProcessW's working directory, can take.
--
--  Neither can take a \\?\ path, and neither takes a path past MAX_PATH:
--  ShellExecuteW and the shell's parsing stop at 259 characters, and a
--  process's current directory at 258 (it is kept with a trailing backslash).
--  Hostkit.Windows_Paths lifts that limit for the file APIs only. What lifts it
--  here is the 8.3 short name every NTFS volume can give a path
--  (GetShortPathNameW of the long form) -- unless short names are disabled on
--  that volume, which an administrator may do, and then nothing does: the
--  caller must refuse with "path too long" rather than hand on a path that
--  fails somewhere less telling.
private package Hostkit.Shell_Paths is

   --  The longest path ShellExecuteW and the shell's item parsing take.
   Shell_Limit : constant := 259;

   --  The longest current directory CreateProcessW takes.
   Directory_Limit : constant := 258;

   --  Path as UTF-16 with a terminating NUL, in a form no longer than Limit:
   --  Path itself when it fits, else its short (8.3) form without the \\?\
   --  prefix.
   --
   --  @param Path The path, UTF-8.
   --  @param Limit The longest form the caller can pass on, NUL not counted.
   --  @param Usable False when neither form fits; the result is then just a NUL.
   --  @param Shortened True when the short form was needed.
   --  @return The path to pass by address.
   function For_Shell
     (Path      : String;
      Limit     : Positive;
      Usable    : out Boolean;
      Shortened : out Boolean)
      return Wide_String;

end Hostkit.Shell_Paths;
