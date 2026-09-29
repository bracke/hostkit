with Interfaces.C.Strings;

package body Hostkit.Durability is

   use type Interfaces.C.int;

   subtype C_Int is Interfaces.C.int;

   --  Linux, asm-generic/fcntl.h: O_RDONLY, and O_DIRECTORY in octal.
   O_Rdonly    : constant C_Int := 8#0#;
   O_Directory : constant C_Int := 8#200000#;
   O_Cloexec   : constant C_Int := 8#2000000#;

   function open (Path : Interfaces.C.Strings.chars_ptr; Flags : C_Int) return C_Int
     with Import, Convention => C_Variadic_1, External_Name => "open";

   function close (FD : C_Int) return C_Int
     with Import, Convention => C, External_Name => "close";

   function fsync (FD : C_Int) return C_Int
     with Import, Convention => C, External_Name => "fsync";

   --  The file's data on the device.
   function Flush (FD : C_Int) return C_Int is (fsync (FD));

   --  Open, flush, close.
   function Sync (Path : String; Flags : C_Int) return Outcome is
      Name   : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      FD     : constant C_Int := open (Name, Flags);
      Result : Outcome := Failed;
   begin
      Interfaces.C.Strings.Free (Name);
      if FD < 0 then
         return Failed;
      end if;
      if Flush (FD) = 0 then
         Result := Synced;
      end if;
      if close (FD) /= 0 then
         Result := Failed;
      end if;
      return Result;
   end Sync;

   function Sync_File (Path : String) return Outcome
   is (Sync (Path, O_Rdonly + O_Cloexec));

   function Sync_Directory (Path : String) return Outcome
   is (Sync (Path, O_Rdonly + O_Directory + O_Cloexec));

end Hostkit.Durability;
