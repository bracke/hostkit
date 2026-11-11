separate (Hostkit_Suite)
procedure Test_Environment_Value (T : in out AUnit.Test_Cases.Test_Case'Class) is
   pragma Unreferenced (T);
   Name  : constant String := "HOSTKIT_TEST_ENVIRONMENT_VALUE";
   Value : Hostkit.UString;
begin
   if Ada.Environment_Variables.Exists (Name) then
      Ada.Environment_Variables.Clear (Name);
   end if;

   Assert
     (not Hostkit.Process.Environment_Value (Name, Value),
      "a missing environment variable is reported as absent");
   Assert
     (To_String (Value) = "",
      "a missing environment variable leaves no stale value");

   --  A present empty variable, where the host has such a thing. Windows
   --  does not: setting one to "" removes it, and absent is the only
   --  answer left. Asserted per host rather than skipped, because what the
   --  host does is the thing worth pinning.
   Ada.Environment_Variables.Set (Name, "");

   if Hostkit.Host.Current = Hostkit.Host.Windows then
      Assert
        (not Hostkit.Process.Environment_Value (Name, Value),
         "setting a variable to nothing left it present on a host that "
         & "removes it");
   else
      Assert
        (Hostkit.Process.Environment_Value (Name, Value),
         "a present empty environment variable is still present");
      Assert
        (To_String (Value) = "",
         "a present empty environment variable returns an empty value");
   end if;

   Ada.Environment_Variables.Set (Name, "hostkit-value");
   Assert
     (Hostkit.Process.Environment_Value (Name, Value),
      "a present environment variable is reported as present");
   Assert
     (To_String (Value) = "hostkit-value",
      "the environment value is returned without consumer-side probing");

   Ada.Environment_Variables.Clear (Name);

   --  A value this process inherited with a non-ASCII letter in it, as a
   --  user profile path has one (C:\Users\Jürgen): it must come back as
   --  UTF-8, which every path call here takes, and not in a code page.
   --  CI sets the variable on every runner; a local run without it has
   --  nothing to compare.
   if Hostkit.Process.Environment_Value ("HOSTKIT_TEST_NON_ASCII", Value) then
      Assert
        (To_String (Value) = "J" & Character'Val (16#C3#) & Character'Val (16#BC#) & "rgen",
         "an inherited non-ASCII value comes back as UTF-8, got"
         & Natural'Image (Length (Value)) & " bytes");
   end if;

   --  And one this process sets itself: Set takes UTF-8 and Value gives
   --  the same bytes back (Windows' C runtime would pass them on in the
   --  ANSI code page), and Clear removes it.
   declare
      Jurgen : constant String := "J" & Character'Val (16#C3#) & Character'Val (16#BC#) & "rgen";
      Found  : Boolean;
   begin
      Hostkit.Environment.Set (Name, Jurgen);
      Assert
        (Hostkit.Environment.Value (Name, Found) = Jurgen and then Found,
         "a non-ASCII value set here is read back as the same UTF-8");
      Assert
        (Hostkit.Process.Environment_Value (Name, Value) and then To_String (Value) = Jurgen,
         "the process view of the environment reads it back the same");
      Hostkit.Environment.Clear (Name);
      Assert
        (Hostkit.Environment.Value (Name, Found) = "" and then not Found,
         "a cleared variable is gone");
      --  The C runtime's own copy follows, which Ada.Environment_Variables
      --  (and every getenv) reads.
      Hostkit.Environment.Set (Name, "hostkit-runtime-copy");
      Assert
        (Ada.Environment_Variables.Exists (Name)
         and then Ada.Environment_Variables.Value (Name) = "hostkit-runtime-copy",
         "a value set here is seen by Ada.Environment_Variables too");
      Hostkit.Environment.Clear (Name);
      Assert (not Ada.Environment_Variables.Exists (Name), "and so is its clearing");
   end;
end Test_Environment_Value;
