with Ada.Containers.Indefinite_Vectors;

--  Tests that cannot run on this host, said and counted.
--
--  AUnit has no skipped state: a test that returns early passes. So a test
--  that has nothing to check on this host calls Skip, which says so on
--  standard error and records it, and the runner holds the record against a
--  per-host list of the skips expected there (HOSTKIT_TEST_EXPECTED_SKIPS):
--  a test that quietly stopped running cannot pass unseen.
package Hostkit_Test_Skips is

   package Name_Vectors is new Ada.Containers.Indefinite_Vectors (Positive, String);

   --  Record that a test did not run here, and why.
   --
   --  @param Test The test routine's name, such as "Test_Clean_Wrapper".
   --  @param Reason Why this host cannot run it; the expected-skips lists
   --  name it word for word.
   procedure Skip (Test : String; Reason : String);

   --  How many times Skip was called.
   --
   --  @return The number of Skip calls.
   function Skip_Count return Natural;

   --  Did a test skip so?
   --
   --  @param Item "Test: Reason", the form an expected-skips list uses.
   --  @return True when Skip was called with that test and reason.
   function Has_Skipped (Item : String) return Boolean;

   --  Every skip so far, each as "Test: Reason", once.
   --
   --  @return The recorded skips.
   function Skips return Name_Vectors.Vector;

   --  Hold the skips against the list HOSTKIT_TEST_EXPECTED_SKIPS names.
   --
   --  The list has one "Test: Reason" per line; "--" starts a comment. A skip
   --  it does not list fails -- a listed test skipping for another reason
   --  too -- and so does a listed one that did not skip, so one cannot take
   --  the other's place. Without the variable nothing is checked.
   --
   --  @return True when the run's skips are exactly the expected ones, or
   --  no list was given.
   function Matches_Expected return Boolean;

end Hostkit_Test_Skips;
