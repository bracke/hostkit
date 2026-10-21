--  Finding the data files a program ships beside itself.
--
--  A program that reads its catalogues, fonts or icons from the current
--  directory shows raw message keys as soon as it is started from anywhere
--  else, and lets whatever directory it was launched in supply those files.
--  The answer is anchored at the program's own executable instead: an
--  installed program keeps its data in a share/ directory one level above
--  bin/, a build tree two levels above a tests/bin/ binary.
package Hostkit.Resources is

   --  The first existing path among Relative_Path beside this program's own
   --  executable, then beside each of its parent directories, up to Levels of
   --  them. Relative_Path names the file the caller needs, such as
   --  "share/launcher.catalog".
   --
   --  @param Relative_Path Path below the directories searched.
   --  @param Levels How many parent directories to try after the executable's own.
   --  @return The full path found, or "" when none exists or the host will
   --    not say where the program is.
   function Beside_Executable
     (Relative_Path : String;
      Levels        : Natural := 2)
      return String;

end Hostkit.Resources;
