--  The process environment, as UTF-8 on every host.
--
--  Ada.Environment_Variables hands a Windows value over in the ANSI code
--  page: a profile under C:\Users\Jürgen came back as bytes no path call
--  here could use (every one takes UTF-8 and calls the wide API). Windows is
--  asked through GetEnvironmentVariableW instead; elsewhere the environment
--  already holds the bytes the filesystem takes.
package Hostkit.Environment is

   --  @param Name The variable.
   --  @param Found True when it is set (on Windows, set to something: a
   --    variable set to "" is removed there).
   --  @return Its value as UTF-8, or "" when not Found.
   function Value (Name : String; Found : out Boolean) return String;

   --  @param Name The variable.
   --  @return Its value as UTF-8, or Default when it is not set.
   function Value (Name : String; Default : String) return String;

end Hostkit.Environment;
