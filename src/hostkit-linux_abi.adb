package body Hostkit.Linux_Abi is

   function Uses_Alternate_Open_Flags (Machine : String) return Boolean is
      function Starts (Prefix : String) return Boolean is
        (Machine'Length >= Prefix'Length
         and then Machine (Machine'First .. Machine'First + Prefix'Length - 1) = Prefix);
   begin
      return Starts ("arm") or else Starts ("aarch64") or else Starts ("ppc")
        or else Starts ("powerpc") or else Starts ("m68k");
   end Uses_Alternate_Open_Flags;

end Hostkit.Linux_Abi;
