with Interfaces.C;
with GNAT.OS_Lib;

--  prctl (PR_SET_PDEATHSIG, SIGTERM): the kernel sends the signal when the
--  thread that started this process ends. A parent gone before the call is
--  caught by asking whether the parent is still the one there at the start.
package body Hostkit.Parent_Watch is

   use type Interfaces.C.int;

   PR_SET_PDEATHSIG : constant := 1;
   SIGTERM          : constant := 15;

   function C_Prctl
     (Option : Interfaces.C.int; Value : Interfaces.C.unsigned_long;
      A3, A4, A5 : Interfaces.C.unsigned_long := 0) return Interfaces.C.int
     with Import, Convention => C, External_Name => "prctl";
   function C_Getppid return Interfaces.C.int
     with Import, Convention => C, External_Name => "getppid";

   Parent_At_Start : constant Interfaces.C.int := C_Getppid;

   function End_With_Parent return Boolean is
   begin
      if C_Prctl (PR_SET_PDEATHSIG, SIGTERM) /= 0 then
         return False;
      end if;
      if C_Getppid /= Parent_At_Start then
         GNAT.OS_Lib.OS_Exit (143);
      end if;
      return True;
   end End_With_Parent;

end Hostkit.Parent_Watch;
