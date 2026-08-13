with Interfaces.C.Strings;
with Interfaces.C;

with System;

package body Hostkit.Locks is

   use type Interfaces.C.int;

   subtype C_Int is Interfaces.C.int;

   --  macOS values; O_CREAT is 0x200 here and 0o100 on Linux.
   O_Wronly : constant C_Int := 16#0001#;
   O_Creat  : constant C_Int := 16#0200#;

   --  flock(2) operations. flock rather than fcntl's F_SETLK: fcntl locks are
   --  the POSIX ones, but their struct flock differs between hosts and would
   --  have to be modelled field by field, and their ownership rule is worse for
   --  this purpose -- a fcntl lock is dropped when *any* descriptor on the file
   --  is closed, including one some unrelated part of the program opened and
   --  closed, which silently releases a lock nobody released.
   LOCK_SH : constant C_Int := 1;
   LOCK_EX : constant C_Int := 2;
   LOCK_UN : constant C_Int := 8;
   LOCK_NB : constant C_Int := 4;

   E_Wouldblock : constant C_Int := 35;   --  EAGAIN, and EWOULDBLOCK, on macOS
   E_Acces      : constant C_Int := 13;
   E_Nolck      : constant C_Int := 77;
   E_Opnotsupp  : constant C_Int := 102;
   E_Intr       : constant C_Int := 4;

   function C_Open
     (Path  : Interfaces.C.Strings.chars_ptr;
      Flags : C_Int;
      Mode  : Interfaces.C.unsigned) return C_Int
     with Import => True, Convention => C, External_Name => "open";
   function C_Close (Fd : C_Int) return C_Int
     with Import => True, Convention => C, External_Name => "close";
   function C_Flock (Fd : C_Int; Operation : C_Int) return C_Int
     with Import => True, Convention => C, External_Name => "flock";
   function Errno_Location return System.Address
     with Import => True, Convention => C, External_Name => "__error";

   function Errno return C_Int;
   --  The current thread's errno.

   -----------
   -- Errno --
   -----------

   function Errno return C_Int is
      Value : C_Int with Import => True, Address => Errno_Location;
   begin
      return Value;
   end Errno;

   -------------
   -- Acquire --
   -------------

   function Acquire
     (Path : String;
      Kind : Lock_Kind;
      Wait : Boolean;
      Item : out Lock) return Lock_Outcome
   is
      Path_C : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.New_String (Path);
      Opened : C_Int;
      Ignored : C_Int;
   begin
      Item.Handle := -1;
      Item.Held   := False;

      --  No O_TRUNC. A lock taken on the state file itself must not destroy the
      --  state it is protecting -- which is what a caller would get if this
      --  opened the file the way a writer does.
      Opened := C_Open (Path_C, O_Wronly + O_Creat, 8#600#);
      Interfaces.C.Strings.Free (Path_C);

      if Opened < 0 then
         return Lock_Error;
      end if;

      declare
         Operation : constant C_Int :=
           (if Kind = Lock_Exclusive then LOCK_EX else LOCK_SH)
           + (if Wait then 0 else LOCK_NB);
         Result : C_Int;
      begin
         loop
            Result := C_Flock (Opened, Operation);

            --  A blocking flock interrupted by a signal has not taken the lock
            --  and has not failed either. A shell that ignores nothing would
            --  see this every time a child exits.
            exit when Result = 0 or else Errno /= E_Intr;
         end loop;

         if Result = 0 then
            Item.Handle := Interfaces.Integer_64 (Opened);
            Item.Held   := True;
            return Lock_Ok;
         end if;

         declare
            Code : constant C_Int := Errno;
         begin
            Ignored := C_Close (Opened);

            if Code = E_Wouldblock or else Code = E_Acces then
               return Lock_Busy;
            elsif Code = E_Nolck or else Code = E_Opnotsupp then
               --  A filesystem that does not carry locks -- some network mounts.
               --  Reported apart from Lock_Error because retrying will not help
               --  and because nothing is protecting the file: a caller that
               --  treated this as success would have an unguarded write it
               --  believed was guarded.
               return Lock_Unsupported;
            else
               return Lock_Error;
            end if;
         end;
      end;
   end Acquire;

   -------------
   -- Release --
   -------------

   procedure Release (Item : in out Lock) is
      Ignored : C_Int;
   begin
      if not Item.Held then
         return;
      end if;

      --  Unlocked explicitly, then closed. The close alone would release it,
      --  but saying so makes the intent visible at the point it happens rather
      --  than as a side effect of the line below.
      Ignored := C_Flock (C_Int (Item.Handle), LOCK_UN);
      Ignored := C_Close (C_Int (Item.Handle));

      Item.Handle := -1;
      Item.Held   := False;
   end Release;

   -------------
   -- Is_Held --
   -------------

   function Is_Held (Item : Lock) return Boolean is
   begin
      return Item.Held;
   end Is_Held;

end Hostkit.Locks;
