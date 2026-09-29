with Interfaces.C.Strings;

package body Hostkit.Durability is

   use type Interfaces.C.int;

   subtype C_Int is Interfaces.C.int;

   --  The C runtime's own: _commit is FlushFileBuffers on the descriptor,
   --  which needs it open for writing -- O_RDWR, and O_BINARY so nothing
   --  is translated on the way.
   O_Rdwr   : constant C_Int := 16#0002#;
   O_Binary : constant C_Int := 16#8000#;

   function open (Path : Interfaces.C.Strings.chars_ptr; Flags : C_Int) return C_Int
     with Import, Convention => C_Variadic_1, External_Name => "_open";

   function commit (FD : C_Int) return C_Int
     with Import, Convention => C, External_Name => "_commit";

   function close (FD : C_Int) return C_Int
     with Import, Convention => C, External_Name => "_close";

   function Sync_File (Path : String) return Outcome is
      Name   : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      FD     : constant C_Int := open (Name, O_Rdwr + O_Binary);
      Result : Outcome := Failed;
   begin
      Interfaces.C.Strings.Free (Name);
      if FD < 0 then
         return Failed;
      end if;
      if commit (FD) = 0 then
         Result := Synced;
      end if;
      if close (FD) /= 0 then
         Result := Failed;
      end if;
      return Result;
   end Sync_File;

   --  NTFS journals its directory entries itself; there is nothing to ask.
   function Sync_Directory (Path : String) return Outcome is
      pragma Unreferenced (Path);
   begin
      return Not_Supported;
   end Sync_Directory;

end Hostkit.Durability;
