separate (Hostkit_Suite)
procedure Test_Where_This_Program_Is (T : in out AUnit.Test_Cases.Test_Case'Class) is
   pragma Unreferenced (T);

   Own : constant String := Hostkit.Fs.Own_Executable;
   Dir : constant String := Hostkit.Fs.Own_Executable_Directory;
begin
   if Hostkit.Host.Current = Hostkit.Host.Unsupported then
      Assert (Own = "", "a host with no body says so rather than guessing");
      return;
   end if;

   --  The point is that this does not come from argv[0]: the suite is run
   --  through alr, from a directory that is not its own, and the answer has
   --  to be the file on disk either way.
   Assert (Own /= "", "the host says where this program is");
   Assert
     (Ada.Directories.Exists (Own),
      "and it is a path that exists: " & Own);
   Assert
     (Hostkit.Fs.Is_Executable (Own),
      "and the thing at it is a program");
   Assert
     (Dir /= "" and then Ada.Directories.Exists (Dir),
      "and the directory holding it is where its neighbours would be");

   --  Same file as the one the suite was started as, whatever spelling the
   --  caller used to say it.
   Assert
     (Hostkit.Metadata.Same_File (Own, Ada.Command_Line.Command_Name)
        or else Ada.Command_Line.Command_Name = "",
      "and it is the program that is running");

   --  Data beside the program is found from there, not from the current
   --  directory: the program's own file at level zero, nothing for a name
   --  that is nowhere above it.
   declare
      Own_Name : constant String := Ada.Directories.Simple_Name (Own);
   begin
      Assert
        (Hostkit.Metadata.Same_File (Hostkit.Resources.Beside_Executable (Own_Name, Levels => 0), Own),
         "a file beside the program is found beside it");
      Assert
        (Hostkit.Resources.Beside_Executable ("no-such-hostkit-resource.dat") = "",
         "a file that is not there is not found");
      Assert
        (Hostkit.Resources.Beside_Executable ("") = "",
         "an empty name finds nothing");
   end;
end Test_Where_This_Program_Is;
