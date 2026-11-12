package body Hostkit.Linux_Abi is
   use type Interfaces.C.unsigned;
   use type Interfaces.Unsigned_64;

   function Crosses_Mount (Parent, Child : Statx_Record) return Boolean is
     (if (Parent.Mask and Child.Mask and Statx_Mnt_Id) /= 0
      then Parent.Mount_Id /= Child.Mount_Id
      else Parent.Device_Major /= Child.Device_Major or else Parent.Device_Minor /= Child.Device_Minor);

   function Uses_Alternate_Open_Flags (Machine : String) return Boolean is
      function Starts (Prefix : String) return Boolean is
        (Machine'Length >= Prefix'Length
         and then Machine (Machine'First .. Machine'First + Prefix'Length - 1) = Prefix);
   begin
      return Starts ("arm") or else Starts ("aarch64") or else Starts ("ppc")
        or else Starts ("powerpc") or else Starts ("m68k");
   end Uses_Alternate_Open_Flags;

end Hostkit.Linux_Abi;
