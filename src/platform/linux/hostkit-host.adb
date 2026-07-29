with Interfaces.C;

package body Hostkit.Host is

   function Current return Kind is
   begin
      return Linux;
   end Current;

   --  Effective, not real: a program run through sudo has the privileges of the
   --  effective id, and the real one still says who invoked it.
   function Is_Elevated return Boolean is
      use type Interfaces.C.unsigned;

      function Geteuid return Interfaces.C.unsigned
        with Import => True, Convention => C, External_Name => "geteuid";
   begin
      return Geteuid = 0;
   end Is_Elevated;

   --  POSIX has no call for this; the locale is an environment convention the
   --  caller reads for itself. See the spec: "" means ask the environment.
   function Native_Locale return String is
   begin
      return "";
   end Native_Locale;

end Hostkit.Host;
