separate (Hostkit_Suite)
procedure Test_The_Host_Locale_Is_Asked_Of_The_Host
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Locale : constant String := Hostkit.Host.Native_Locale;
begin
   if Hostkit.Host.Current in Hostkit.Host.Windows | Hostkit.Host.MacOS then
      --  Both hosts keep one and will say. It is returned in the host's own
      --  spelling, so the only shape that can be asserted portably is that
      --  there is a language in it.
      Assert (Locale'Length >= 2, "this host names the locale it is set to, got '" & Locale & "'");
   else
      --  Not "no locale": the POSIX answer lives in the environment, which is
      --  the caller's to read, and saying "" is how this declines to guess.
      Assert (Locale = "", "a host with no locale API says so rather than guessing");
   end if;
end Test_The_Host_Locale_Is_Asked_Of_The_Host;
