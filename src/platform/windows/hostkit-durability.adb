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
      FD     : C_Int := open (Name, O_Rdwr + O_Binary);
      Result : Outcome := Failed;
   begin
      --  A file just written may be held a moment by someone else (a virus
      --  scanner) that did not share writing; try again briefly.
      for Attempt in 1 .. 10 loop
         exit when FD >= 0;
         delay Duration (Attempt) * 0.02;
         FD := open (Name, O_Rdwr + O_Binary);
      end loop;
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

   --  The C runtime offers no reservation that leaves the length alone;
   --  the room is not said to be had.
   function Reserve_Space (Path : String; Length : Long_Long_Integer) return Outcome is
      pragma Unreferenced (Path, Length);
   begin
      return Not_Supported;
   end Reserve_Space;

   ------------------
   -- Sync_Mapping --
   ------------------

   function Sync_Mapping
     (Start : System.Address; Length : Long_Long_Integer) return Outcome
   is
      use type System.Address;

      --  The view's pages into the file; Sync_File's FlushFileBuffers then
      --  puts the file on the device.
      function FlushViewOfFile
        (Base : System.Address; Bytes : Interfaces.C.size_t) return Interfaces.C.int
        with Import, Convention => Stdcall, External_Name => "FlushViewOfFile";
   begin
      if Start = System.Null_Address or else Length <= 0 then
         return Synced;
      end if;
      return (if FlushViewOfFile (Start, Interfaces.C.size_t (Length)) /= 0
              then Synced else Failed);
   end Sync_Mapping;

end Hostkit.Durability;
