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

end Hostkit.Host;
