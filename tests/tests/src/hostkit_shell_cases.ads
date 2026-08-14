with AUnit;
with AUnit.Test_Cases;

--  The shell primitives: descriptors, pipes, spawning, signals.
--
--  These are the parts of the crate a shell needs and nothing else does, and
--  they are the parts whose failures are least visible. A pipe end left
--  inheritable does not fail -- it hangs, later, under load. A child that
--  inherited an ignored SIGINT does not fail either; it just cannot be
--  interrupted. So the tests here assert the properties that are otherwise
--  invisible, not only that the calls return True.
package Hostkit_Shell_Cases is

   type Case_Type is new AUnit.Test_Cases.Test_Case with null record;

   --  Name shown by the reporter.
   --
   --  @param T Test case instance.
   --  @return Case name.
   overriding function Name (T : Case_Type) return AUnit.Message_String;

   --  Says which routine is starting, on standard error, flushed.
   --
   --  AUnit reports when the whole suite ends, so a suite that hangs prints
   --  nothing at all. Windows reached the end of the other case's routines and
   --  stopped somewhere in these, which is all a killed run could say until
   --  this existed.
   --
   --  @param T Test case instance.
   overriding procedure Set_Up (T : in out Case_Type);

   --  Register the routines of this case.
   --
   --  @param T Test case instance.
   overriding procedure Register_Tests (T : in out Case_Type);

end Hostkit_Shell_Cases;
