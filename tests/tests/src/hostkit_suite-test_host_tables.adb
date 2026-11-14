separate (Hostkit_Suite)
procedure Test_Host_Tables (T : in out AUnit.Test_Cases.Test_Case'Class) is
   pragma Unreferenced (T);
   Program   : Ada.Strings.Unbounded.Unbounded_String;
   Arguments : Hostkit.String_Vectors.Vector;
begin
   for Item in Hostkit.Errors.Cause loop
      Assert (Hostkit.Errors.Code_Of (Item) >= 0, "an errno is never negative");
   end loop;
   if Hostkit.Host.Current = Hostkit.Host.Linux then
      Assert (Hostkit.Errors.Code_Of (Hostkit.Errors.Name_Too_Long) = 36, "ENAMETOOLONG is 36 on Linux");
      Assert (Hostkit.Errors.Code_Of (Hostkit.Errors.Quota_Exceeded) = 122, "EDQUOT is 122 on Linux");
   elsif Hostkit.Host.Current = Hostkit.Host.MacOS then
      Assert (Hostkit.Errors.Code_Of (Hostkit.Errors.Name_Too_Long) = 63, "ENAMETOOLONG is 63 on macOS");
   elsif Hostkit.Host.Current = Hostkit.Host.Windows then
      Assert (Hostkit.Errors.Code_Of (Hostkit.Errors.Quota_Exceeded) = 0, "Windows has no EDQUOT");
   end if;

   Assert (Hostkit.Mounts.Is_Pseudo ("proc") and then Hostkit.Mounts.Is_Pseudo ("TMPFS")
           and then Hostkit.Mounts.Is_Pseudo (""), "proc, tmpfs and no type are internal");
   Assert (not Hostkit.Mounts.Is_Pseudo ("ext4"), "ext4 holds files");
   Assert (Hostkit.Mounts.Is_Network ("nfs4") and then Hostkit.Mounts.Is_Network ("CIFS"),
           "nfs4 and cifs are networked");
   Assert (not Hostkit.Mounts.Is_Network ("vfat"), "vfat is local");
   declare
      Places : constant Hostkit.Mounts.Volume_Place_List := Hostkit.Mounts.Volume_Places;
   begin
      case Hostkit.Host.Current is
         when Hostkit.Host.Linux =>
            Assert (Places'Length = 3 and then Ada.Strings.Unbounded.To_String (Places (1).Path) = "/mnt",
                    "Linux mounts volumes under /mnt, /media and /run/media");
         when Hostkit.Host.MacOS =>
            Assert (Ada.Strings.Unbounded.To_String (Places (1).Path) = "/Volumes", "macOS under /Volumes");
         when Hostkit.Host.Windows =>
            --  The drives Windows has, not every letter.
            Assert (Places'Length in 1 .. 26, "Windows lists the roots of the drives it has");
            for Place of Places loop
               Assert
                 (Ada.Strings.Unbounded.Length (Place.Path) = 3
                  and then Ada.Strings.Unbounded.Slice (Place.Path, 2, 3) = ":\",
                  "each Windows volume place is a drive's root");
            end loop;
         when Hostkit.Host.Unsupported =>
            null;
      end case;
   end;

   Hostkit.Process.Portable_Default_Opener ("{path}", Program, Arguments);
   Assert (Ada.Strings.Unbounded.To_String (Arguments.Last_Element) = "{path}", "the file comes last");
   Assert (Hostkit.Process.Is_Shell_Start (Ada.Strings.Unbounded.To_String (Program), Arguments)
           = (Hostkit.Host.Current = Hostkit.Host.Windows),
           "the portable opener is the shell's start shape exactly on Windows");

   --  The shell-start shape, read the same on every host.
   declare
      function Args (A, B, C, D : String := ""; Count : Natural := 4) return Hostkit.String_Vectors.Vector is
         Result : Hostkit.String_Vectors.Vector;
         procedure Add (Text : String) is
         begin
            if Natural (Result.Length) < Count then
               Result.Append (Ada.Strings.Unbounded.To_Unbounded_String (Text));
            end if;
         end Add;
      begin
         Add (A);
         Add (B);
         Add (C);
         Add (D);
         return Result;
      end Args;
      function Shape (Program : String; Arguments : Hostkit.String_Vectors.Vector) return Boolean
        renames Hostkit.Process.Has_Shell_Start_Shape;
   begin
      Assert (Shape ("cmd", Args ("/c", "start", "", "x&calc")), "cmd /c start, an empty title, a file");
      Assert (Shape ("CMD.EXE", Args ("/C", "START", "", "f")), "any case");
      Assert (Shape ("C:\Windows\System32\cmd.exe", Args ("/c", "start", "", "f")), "cmd by its path");
      Assert (not Shape ("cmd", Args ("/c", "start", "title", "f")), "a title is not the shape");
      Assert (not Shape ("cmd", Args ("/c", "start", "", "f", Count => 3)), "three arguments are not");
      Assert (not Shape ("cmd", Args ("/c", "start", "", "")), "an empty file is not");
      Assert (not Shape ("notcmd.exe", Args ("/c", "start", "", "f")), "another program is not");
      Assert (not Shape ("cmd", Args ("/k", "start", "", "f")), "/k is not");

      --  The file the shape opens, wherever it sits in the arguments.
      declare
         Path : Ada.Strings.Unbounded.Unbounded_String;
      begin
         Assert (Hostkit.Process.Has_Shell_Start_Shape ("cmd", Args ("/c", "start", "", "x&calc"), Path)
                 and then Ada.Strings.Unbounded.To_String (Path) = "x&calc",
                 "the shape's file is its last argument");
         Assert (not Hostkit.Process.Has_Shell_Start_Shape ("cmd", Args ("/c", "start", "title", "f"), Path)
                 and then Ada.Strings.Unbounded.To_String (Path) = "",
                 "no shape, no file");
         Assert (Hostkit.Process.Shell_Start_Target ("cmd", Args ("/c", "start", "", "f"), Path)
                 = (Hostkit.Host.Current = Hostkit.Host.Windows),
                 "the opener's file is taken from it only on Windows");
         Assert (Ada.Strings.Unbounded.To_String (Path)
                 = (if Hostkit.Host.Current = Hostkit.Host.Windows then "f" else ""),
                 "the file is the shape's own on Windows, nothing elsewhere");
         Assert (not Hostkit.Process.Shell_Start_Target ("xdg-open", Args ("f", Count => 1), Path)
                 and then Ada.Strings.Unbounded.To_String (Path) = "",
                 "another opener is not the shell's start");
      end;
   end;

   Assert (Hostkit.Fs.Drive_Root_Length ("C:\Users") = 3 and then Hostkit.Fs.Drive_Root_Length ("D:/") = 3,
           "a drive root is three bytes");
   Assert (Hostkit.Fs.Drive_Root_Length ("/home") = 0 and then Hostkit.Fs.Drive_Root_Length ("C:") = 0,
           "a POSIX path or a bare drive letter has no drive root");
   Assert (Hostkit.Fs.Has_Windows_Root ("\\server\share") and then Hostkit.Fs.Has_Windows_Root ("c:\"),
           "a share and a drive are Windows roots");
   Assert (not Hostkit.Fs.Has_Windows_Root ("/c:/x"), "a POSIX path is not");
end Test_Host_Tables;
