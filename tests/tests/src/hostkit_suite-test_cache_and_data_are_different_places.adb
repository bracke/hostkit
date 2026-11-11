separate (Hostkit_Suite)
procedure Test_Cache_And_Data_Are_Different_Places
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);

   Cache  : constant String := Hostkit.Fs.Cache_Directory;
   Data   : constant String := Hostkit.Fs.Application_Data_Directory;
   Config : constant String := Hostkit.Fs.Config_Directory;
begin
   if Hostkit.Host.Current = Hostkit.Host.Unsupported then
      Assert (Cache = "", "a host with no answer says so");
      Assert (Config = "", "for configuration too");
      return;
   end if;

   Assert (Cache /= "", "this host names a cache directory, got '" & Cache & "'");
   Assert (Data /= "", "and an application data directory");
   Assert (Config /= "", "and a configuration directory");
   Assert
     (Cache /= Data,
      "the cache and the data directory are not the same place, both were '" & Cache & "'");

   --  Configuration must never share the cache: a cache is deleted behind the
   --  program's back, and what the user chose is the one of the three that
   --  cannot be regenerated from anything.
   Assert
     (Config /= Cache,
      "configuration does not live in the cache, both were '" & Config & "'");

   --  Whether it shares the DATA directory is the host's business, and the
   --  answer differs -- which is the reason a caller must not work this out
   --  from ~/.config and hope.
   if Hostkit.Host.Current = Hostkit.Host.Linux then
      Assert
        (Config /= Data,
         "Linux separates configuration from data, both were '" & Config & "'");
   else
      Assert
        (Config = Data,
         "this host keeps configuration with its application data, got '"
         & Config & "' and '" & Data & "'");
   end if;
end Test_Cache_And_Data_Are_Different_Places;
