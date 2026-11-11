separate (Hostkit_Suite)
procedure Test_Elevation_Is_Asked_Not_Assumed
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);

   Elevated : constant Boolean := Hostkit.Host.Is_Elevated;
begin
   if Hostkit.Host.Current = Hostkit.Host.Windows then
      --  There is no cheap second opinion here: every way of asking Windows
      --  whether this token is elevated goes through the same call. The
      --  POSIX branch below is the one carrying the cross-check.
      Assert
        (Elevated or else not Elevated,
         "the elevation query answers rather than raising");
      return;
   end if;

   --  A second route to the same fact: geteuid(2) through the library, and
   --  id(1) through a program. An answer only one of them gives is an answer
   --  about our own code rather than about the host.
   declare
      Id        : constant String := Hostkit.Process.Locate ("id");
      Out_Path  : constant String :=
        Ada.Directories.Compose (Scratch, "hk-elevation.txt");
      Arguments : Hostkit.String_Vectors.Vector;
      Outcome   : Hostkit.Process.Process_Outcome;
   begin
      if Id = "" then
         Skip ("Test_Elevation_Is_Asked_Not_Assumed", "no id program to ask for a second opinion");
         return;
      end if;

      Arguments.Append (To_Unbounded_String ("-u"));
      Outcome :=
        Hostkit.Process.Run_Captured
          (Program     => Id,
           Arguments   => Arguments,
           Stdout_Path => Out_Path,
           Timeout_Ms  => 20_000);

      Assert (Outcome.Started and then Outcome.Exit_Status = 0, "id -u ran");

      --  The whole line, not a search for "0": every other user id on this
      --  host contains one somewhere.
      declare
         Reported : constant String := First_Line (Out_Path);
      begin
         Assert
           ((Reported = "0") = Elevated,
            "the library and id(1) agree about who this process is; id said "
            & Reported);
      end;
   end;
end Test_Elevation_Is_Asked_Not_Assumed;
