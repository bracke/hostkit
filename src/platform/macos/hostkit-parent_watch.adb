with Interfaces.C;
with System;

--  No parent-death signal here: a detached thread looks at the parent every
--  half second and ends the process once it has changed -- an orphan is
--  adopted, so its parent is no longer the one there at the start. A thread
--  of its own, not an Ada task: a library-level task that never ends would
--  keep the program from ending. It calls nothing but C.
package body Hostkit.Parent_Watch is

   use type Interfaces.C.int;

   function C_Getppid return Interfaces.C.int
     with Import, Convention => C, External_Name => "getppid";
   function C_Usleep (Micros : Interfaces.C.unsigned) return Interfaces.C.int
     with Import, Convention => C, External_Name => "usleep";
   procedure C_Exit (Status : Interfaces.C.int)
     with Import, Convention => C, External_Name => "_exit";

   type Thread_Id is new Interfaces.C.unsigned_long;
   type Thread_Body is access function (Argument : System.Address) return System.Address
     with Convention => C;

   function C_Pthread_Create
     (Thread : access Thread_Id; Attributes : System.Address; Start : Thread_Body;
      Argument : System.Address) return Interfaces.C.int
     with Import, Convention => C, External_Name => "pthread_create";
   function C_Pthread_Detach (Thread : Thread_Id) return Interfaces.C.int
     with Import, Convention => C, External_Name => "pthread_detach";

   Parent_At_Start : constant Interfaces.C.int := C_Getppid;
   Started         : Boolean := False;

   function Watch (Argument : System.Address) return System.Address
     with Convention => C;

   function Watch (Argument : System.Address) return System.Address is
      pragma Unreferenced (Argument);
      Ignored : Interfaces.C.int;
   begin
      while C_Getppid = Parent_At_Start loop
         Ignored := C_Usleep (500_000);
      end loop;
      C_Exit (143);
      return System.Null_Address;
   end Watch;

   function End_With_Parent return Boolean is
      Thread : aliased Thread_Id;
   begin
      if not Started then
         if C_Pthread_Create (Thread'Access, System.Null_Address, Watch'Access, System.Null_Address) /= 0 then
            return False;
         end if;
         declare
            Detached : constant Interfaces.C.int := C_Pthread_Detach (Thread);
            pragma Unreferenced (Detached);
         begin
            Started := True;
         end;
      end if;
      return True;
   end End_With_Parent;

end Hostkit.Parent_Watch;
