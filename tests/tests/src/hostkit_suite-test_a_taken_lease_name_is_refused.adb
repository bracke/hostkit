separate (Hostkit_Suite)
procedure Test_A_Taken_Lease_Name_Is_Refused
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   use type Hostkit.Lease_Files.Open_Outcome;
   Path  : constant String := Ada.Directories.Compose (Scratch, "hk-taken-lease");
   Plain : constant String := Ada.Directories.Compose (Scratch, "hk-taken-plain");
   First, Second : Hostkit.Lease_Files.Lease;
   Outcome : Hostkit.Lease_Files.Open_Outcome;

   Racers : constant := 8;
   type Outcome_List is array (1 .. Racers) of Hostkit.Lease_Files.Open_Outcome;
   Raced : Outcome_List := [others => Hostkit.Lease_Files.Error];
   Held  : array (1 .. Racers) of Hostkit.Lease_Files.Lease;

   --  The temporaries a create makes beside its lease: none may be left.
   function Leftovers return Natural is
      Search : Ada.Directories.Search_Type;
      Item   : Ada.Directories.Directory_Entry_Type;
      Count  : Natural := 0;
   begin
      Ada.Directories.Start_Search (Search, Scratch, ".hostkit-lease-*");
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Item);
         Count := Count + 1;
      end loop;
      Ada.Directories.End_Search (Search);
      return Count;
   end Leftovers;

   procedure Remove (Name : String) is
   begin
      if Ada.Directories.Exists (Name) then
         Ada.Directories.Delete_File (Name);
      end if;
   end Remove;
begin
   Remove (Path);
   Remove (Plain);
   Outcome := Hostkit.Lease_Files.Create (Path, First);
   if Outcome = Hostkit.Lease_Files.Unsupported then
      Skip ("Test_A_Taken_Lease_Name_Is_Refused", "the scratch volume carries no locks");
      return;
   end if;
   Assert (Outcome = Hostkit.Lease_Files.Opened, "a fresh lease is created");
   Assert (Hostkit.Lease_Files.Create (Path, Second) = Hostkit.Lease_Files.Refused,
           "a second create of a held lease's name is refused, as a taken name");
   Assert (not Hostkit.Lease_Files.Is_Held (Second), "a refused create holds nothing");
   Hostkit.Lease_Files.Release (First);
   Assert (Hostkit.Lease_Files.Create (Path, Second) = Hostkit.Lease_Files.Refused,
           "a released lease's name is still taken");
   Assert (not Hostkit.Lease_Files.Is_Held (Second), "and the refused create holds nothing");
   Assert (Hostkit.Lease_Files.Open (Path, Hostkit.Lease_Files.Exclusive, True, Second)
             = Hostkit.Lease_Files.Opened,
           "the lease a refused create met is left as it was");
   Hostkit.Lease_Files.Release (Second);

   Write_File (Plain, "x");
   Assert (Hostkit.Lease_Files.Create (Plain, Second) = Hostkit.Lease_Files.Refused,
           "a name an ordinary file has is refused");
   Assert (First_Line (Plain) = "x", "and that file is not replaced");
   Remove (Plain);
   Remove (Path);

   --  Many creates of one name at once: exactly one wins.
   declare
      task type Racer is
         entry Go (Index : Positive);
      end Racer;

      task body Racer is
         Mine : Positive;
      begin
         accept Go (Index : Positive) do
            Mine := Index;
         end Go;
         Raced (Mine) := Hostkit.Lease_Files.Create (Path, Held (Mine));
      end Racer;

      Field : array (1 .. Racers) of Racer;
   begin
      for Index in Field'Range loop
         Field (Index).Go (Index);
      end loop;
   end;

   declare
      Winners : Natural := 0;
   begin
      for Index in Raced'Range loop
         if Raced (Index) = Hostkit.Lease_Files.Opened then
            Winners := Winners + 1;
         else
            Assert (Raced (Index) = Hostkit.Lease_Files.Refused,
                    "a create that lost the race is refused, not failed: "
                    & Hostkit.Lease_Files.Open_Outcome'Image (Raced (Index)));
         end if;
         Hostkit.Lease_Files.Release (Held (Index));
      end loop;
      Assert (Winners = 1, "exactly one of" & Racers'Image & " racing creates wins:" & Winners'Image);
   end;
   Assert (Leftovers = 0, "no create leaves a temporary behind");
   Remove (Path);
end Test_A_Taken_Lease_Name_Is_Refused;
