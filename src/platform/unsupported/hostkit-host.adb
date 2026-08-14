with Interfaces.C;
package body Hostkit.Host is

   function Current return Kind is
   begin
      return Unsupported;
   end Current;

   --  No body for this host means no way to ask. False here says "cannot tell",
   --  which is why the specification forbids using it to skip an attempt.
   function Is_Elevated return Boolean is
   begin
      return False;
   end Is_Elevated;

   --  POSIX has no call for this; the locale is an environment convention the
   --  caller reads for itself. See the spec: "" means ask the environment.
   function Native_Locale return String is
   begin
      return "";
   end Native_Locale;

   ------------------------
   -- Executable_Path --
   ------------------------

   function Executable_Path return String is ("");

   -----------------
   -- Is_Terminal --
   -----------------

   --  A host this build does not know is treated as not a terminal, so a
   --  program falls back to plain output rather than writing escape
   --  sequences somewhere they will be read as text.
   function Is_Terminal (Stream : Stream_Kind) return Boolean is
      pragma Unreferenced (Stream);
   begin
      return False;
   end Is_Terminal;

   function Own_Process_Id return Integer is
   begin
      --  A host this build does not know. -1 rather than 0, which is a real
      --  process id on POSIX and would be believed.
      return -1;
   end Own_Process_Id;

   function System_Name return String is ("");
   function Node_Name return String is ("");
   function Release_Name return String is ("");
   function Version_Name return String is ("");
   function Machine_Name return String is ("");
   function Login_Name return String is ("");

end Hostkit.Host;
