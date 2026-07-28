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

end Hostkit.Host;
