with Ada.Characters.Handling;
with Ada.Strings.Fixed;

package body Hostkit.Windows_Programs is

   --  Tested without allocating: this was once an array of `access constant
   --  String` filled with `new String'(".exe")` and the rest -- six
   --  allocations nothing ever freed, made afresh on every call, to hold six
   --  literals known at compile time.
   function Runs_By_Extension (Path : String) return Boolean is
      Dot : constant Natural := Ada.Strings.Fixed.Index (Path, ".", Ada.Strings.Backward);

      Suffix : constant String :=
        (if Dot = 0 then "" else Ada.Characters.Handling.To_Lower (Path (Dot .. Path'Last)));
   begin
      return Suffix = ".exe" or else Suffix = ".com" or else Suffix = ".bat"
        or else Suffix = ".cmd" or else Suffix = ".ps1"
        or else Suffix = ".msi";
   end Runs_By_Extension;

end Hostkit.Windows_Programs;
