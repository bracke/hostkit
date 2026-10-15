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

   function posix_fallocate (FD : C_Int; Offset, Length : Interfaces.C.long) return C_Int
     with Import, Convention => C, External_Name => "posix_fallocate";

   function Reserve_Space (Path : String; Length : Long_Long_Integer) return Outcome is
      --  Read and write: where the file system has no fallocate of its own
      --  (NFSv3, CIFS, some FUSE), glibc reserves by reading each block
      --  and writing it back, and a descriptor open for writing alone made
      --  that fail.
      O_Rdwr     : constant C_Int := 8#2#;
      EINTR      : constant C_Int := 4;
      EINVAL     : constant C_Int := 22;
      ENOSYS     : constant C_Int := 38;
      EOPNOTSUPP : constant C_Int := 95;
      Name     : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      FD       : constant C_Int := open (Name, O_Rdwr + O_Cloexec);
      Result   : Outcome := Failed;
      Said     : C_Int := 0;
   begin
      Interfaces.C.Strings.Free (Name);
      if FD < 0 then
         return Failed;
      end if;
      --  It answers with the error itself, zero for none. A file system
      --  that cannot reserve at all says so, and that is not a refusal.
      if Length > 0 then
         loop
            Said := posix_fallocate (FD, 0, Interfaces.C.long (Length));
            exit when Said /= EINTR;
         end loop;
      end if;
      if Said = 0 then
         Result := Synced;
      elsif Said in EOPNOTSUPP | ENOSYS | EINVAL then
         Result := Not_Supported;
      end if;
      if close (FD) /= 0 then
         Result := Failed;
      end if;
      return Result;
   end Reserve_Space;

   ------------------
   -- Sync_Mapping --
   ------------------

   function Sync_Mapping
     (Start : System.Address; Length : Long_Long_Integer) return Outcome
   is
      use type System.Address;

      --  Linux numbers it four (asm-generic/mman-common.h).
      MS_SYNC : constant Interfaces.C.int := 4;

      function msync
        (Addr : System.Address; Len : Interfaces.C.size_t; Flags : Interfaces.C.int)
         return Interfaces.C.int
        with Import, Convention => C, External_Name => "msync";
   begin
      if Start = System.Null_Address or else Length <= 0 then
         return Synced;
      end if;
      return (if msync (Start, Interfaces.C.size_t (Length), MS_SYNC) = 0
              then Synced else Failed);
   end Sync_Mapping;

end Hostkit.Durability;
