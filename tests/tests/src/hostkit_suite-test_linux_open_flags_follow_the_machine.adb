separate (Hostkit_Suite)
procedure Test_Linux_Open_Flags_Follow_The_Machine
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type Hostkit.Linux_Abi.C_Int;

   procedure Check (Machine : String; Alternate : Boolean) is
   begin
      Assert
        (Hostkit.Linux_Abi.Uses_Alternate_Open_Flags (Machine) = Alternate,
         "'" & Machine & "' picks the " & (if Alternate then "machine's own" else "asm-generic") & " flags");
      Assert
        (Hostkit.Linux_Abi.O_Nofollow (Machine) = (if Alternate then 16#8000# else 16#2_0000#),
         "'" & Machine & "' O_NOFOLLOW");
      Assert
        (Hostkit.Linux_Abi.O_Directory (Machine) = (if Alternate then 16#4000# else 16#1_0000#),
         "'" & Machine & "' O_DIRECTORY");
   end Check;
begin
   Check ("x86_64", False);
   Check ("i686", False);
   Check ("riscv64", False);
   Check ("s390x", False);
   Check ("", False);
   Check ("aarch64", True);
   Check ("armv7l", True);
   Check ("ppc64le", True);
   Check ("powerpc", True);
   Check ("m68k", True);
end Test_Linux_Open_Flags_Follow_The_Machine;
