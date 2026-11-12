with Hostkit.Errors;
with Hostkit.Windows_Errors;
with Hostkit.Windows_Paths;
with Interfaces;
with Interfaces.C;

package body Hostkit.Durability is

   use type Interfaces.C.int;

   subtype C_Int is Interfaces.C.int;

   --  The C runtime's own: _commit is FlushFileBuffers on the descriptor,
   --  which needs it open for writing -- O_RDWR, and O_BINARY so nothing
   --  is translated on the way.
   O_Rdwr   : constant C_Int := 16#0002#;
   O_Binary : constant C_Int := 16#8000#;

   --  The wide open: the narrow _open reads the path in the ANSI code page,
   --  so any path with a byte past ASCII could not be opened and was never
   --  synced -- a write to it was never published, a move across drives of
   --  a tree holding such a name always failed.
   function open (Path : System.Address; Flags : C_Int) return C_Int
     with Import, Convention => C_Variadic_1, External_Name => "_wopen";

   subtype C_DWord is Interfaces.C.unsigned_long;
   use type C_DWord;
   Read_Only          : constant C_DWord := 16#0001#;
   Invalid_Attributes : constant C_DWord := 16#FFFF_FFFF#;

   function Get_File_Attributes_W (Path : System.Address) return C_DWord
     with Import, Convention => Stdcall, External_Name => "GetFileAttributesW";
   function Set_File_Attributes_W (Path : System.Address; Attributes : C_DWord) return C_Int
     with Import, Convention => Stdcall, External_Name => "SetFileAttributesW";

   function Get_Last_Error return C_DWord
     with Import, Convention => Stdcall, External_Name => "GetLastError";

   --  What a failed open is worth waiting out: someone else holding the file
   --  without sharing writes (ERROR_SHARING_VIOLATION, ERROR_LOCK_VIOLATION).
   --  Anything else -- access denied, read-only, not found -- stays so.
   function Transient (Error : C_DWord) return Boolean is (Error in 32 | 33);

   function commit (FD : C_Int) return C_Int
     with Import, Convention => C, External_Name => "_commit";

   --  _commit, its refusal kept as itself: the runtime's own sets errno to
   --  EBADF whatever FlushFileBuffers said, so a full disk -- which often
   --  shows only here -- read as a bad descriptor.
   function Committed (FD : C_Int) return Boolean is
   begin
      if commit (FD) = 0 then
         return True;
      end if;
      Hostkit.Errors.Set_Errno_From_Last_Error;
      return False;
   end Committed;

   --  The last error of an open just refused, put into errno as well. Read
   --  first: setting errno may itself call into the system.
   function Refusal return C_DWord is
      Error : constant C_DWord := Get_Last_Error;
   begin
      Hostkit.Windows_Errors.Set_Errno_From (Interfaces.Unsigned_32 (Error));
      return Error;
   end Refusal;

   function close (FD : C_Int) return C_Int
     with Import, Convention => C, External_Name => "_close";

   function Sync_File (Path : String) return Outcome is
      --  UTF-16, whole: Wide_Strings.Decode refuses code points past U+FFFF.
      Name   : aliased constant Wide_String :=
        Hostkit.Windows_Paths.Native (Path);
      FD     : C_Int := open (Name'Address, O_Rdwr + O_Binary);
      Error  : C_DWord := (if FD < 0 then Refusal else 0);
      Result : Outcome := Failed;
   begin
      --  A file just written may be held a moment by someone else (a virus
      --  scanner) that did not share writing; try again briefly -- but only
      --  then: a read-only file (handled below) or a denied one no retry opens.
      for Attempt in 1 .. 10 loop
         exit when FD >= 0 or else not Transient (Error);
         delay Duration (Attempt) * 0.02;
         FD := open (Name'Address, O_Rdwr + O_Binary);
         Error := (if FD < 0 then Refusal else 0);
      end loop;
      --  A read-only file cannot be opened for writing, and only a writer
      --  may flush it: drop the attribute for the flush and put it back.
      if FD < 0 then
         declare
            Attributes : constant C_DWord := Get_File_Attributes_W (Name'Address);
         begin
            if Attributes /= Invalid_Attributes
              and then (Attributes and Read_Only) /= 0
              and then Set_File_Attributes_W (Name'Address, Attributes - Read_Only) /= 0
            then
               FD := open (Name'Address, O_Rdwr + O_Binary);
               if FD < 0 then
                  Hostkit.Errors.Set_Errno_From_Last_Error;
               else
                  if Committed (FD) then
                     Result := Synced;
                  end if;
                  if close (FD) /= 0 then
                     Result := Failed;
                  end if;
               end if;
               if Set_File_Attributes_W (Name'Address, Attributes) = 0 then
                  Result := Failed;
               end if;
               return Result;
            end if;
         end;
         return Failed;
      end if;
      if Committed (FD) then
         Result := Synced;
      end if;
      if close (FD) /= 0 then
         Result := Failed;
      end if;
      return Result;
   end Sync_File;

   --  _commit is FlushFileBuffers on the descriptor's handle.
   function Sync_Descriptor (Descriptor : Integer) return Outcome is
     (if Committed (C_Int (Descriptor)) then Synced else Failed);

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
