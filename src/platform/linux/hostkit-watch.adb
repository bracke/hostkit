with Interfaces.C.Strings;
with System;

package body Hostkit.Watch is

   use Ada.Strings.Unbounded;
   use type Interfaces.C.int;
   use type Interfaces.C.long;
   use type Interfaces.C.unsigned;
   use type Interfaces.C.Strings.chars_ptr;
   use type Interfaces.Unsigned_32;

   --  IN_NONBLOCK, so a drain never stalls the render loop, and IN_CLOEXEC so a
   --  spawned child does not inherit the descriptor.
   Nonblock : constant Interfaces.C.int := 2_048;
   Cloexec  : constant Interfaces.C.int := 524_288;

   --  IN_MODIFY, IN_ATTRIB, IN_CLOSE_WRITE, IN_MOVED_FROM, IN_MOVED_TO,
   --  IN_CREATE, IN_DELETE, IN_DELETE_SELF, IN_MOVE_SELF and friends: every way
   --  the contents of a directory can change under us, a file growing in it
   --  included (IN_MODIFY was named here and missing from the mask).
   Event_Mask : constant Interfaces.C.unsigned :=
     16#00000002# or 16#00000004# or 16#00000008# or 16#00000040# or 16#00000080#
     or 16#00000100# or 16#00000200# or 16#00000400# or 16#00000800#
     or 16#00002000# or 16#00004000# or 16#01000000#;

   --  IN_DELETE_SELF, IN_MOVE_SELF, IN_UNMOUNT and IN_IGNORED: the watched
   --  directory itself was deleted, moved away from the path, or unmounted, and
   --  the kernel has dropped -- or is about to drop -- the watch. Nothing more
   --  will arrive on it, so the watch is released and the next Watch_Path on
   --  the same path, a folder made again there included, arms a fresh one.
   Gone_Mask : constant Interfaces.Unsigned_32 :=
     16#0000_0400# or 16#0000_0800# or 16#0000_2000# or 16#0000_8000#;

   --  What a read of the descriptor delivers: struct inotify_event records end
   --  to end, each a fixed part of four 32-bit words -- wd, mask, cookie and
   --  len -- and then len bytes of name, padded so the next record is aligned.
   --  Read as words, so the fixed part of each record is indexed directly.
   Header_Bytes : constant := 16;
   Mask_Word    : constant := 1;
   Length_Word  : constant := 3;

   type Event_Words is array (Natural range 0 .. 1_023) of Interfaces.Unsigned_32
     with Convention => C;

   function Inotify_Init1
     (Flags : Interfaces.C.int) return Interfaces.C.int
     with Import, Convention => C, External_Name => "inotify_init1";

   function Inotify_Add_Watch
     (FD       : Interfaces.C.int;
      Pathname : Interfaces.C.Strings.chars_ptr;
      Mask     : Interfaces.C.unsigned) return Interfaces.C.int
     with Import, Convention => C, External_Name => "inotify_add_watch";

   function Inotify_Rm_Watch
     (FD : Interfaces.C.int;
      WD : Interfaces.C.int) return Interfaces.C.int
     with Import, Convention => C, External_Name => "inotify_rm_watch";

   function C_Read
     (FD    : Interfaces.C.int;
      Buf   : System.Address;
      Count : Interfaces.C.size_t) return Interfaces.C.long
     with Import, Convention => C, External_Name => "read";

   function C_Close
     (FD : Interfaces.C.int) return Interfaces.C.int
     with Import, Convention => C, External_Name => "close";

   procedure Release (State : in out Watch_State) is
      Ignored : Interfaces.C.int;
   begin
      if State.Handle >= 0 and then State.Extra >= 0 then
         Ignored :=
           Inotify_Rm_Watch
             (Interfaces.C.int (State.Handle), Interfaces.C.int (State.Extra));
      end if;

      if State.Handle >= 0 then
         Ignored := C_Close (Interfaces.C.int (State.Handle));
      end if;
      pragma Unreferenced (Ignored);

      State.Handle := -1;
      State.Extra := -1;
      State.Path := Null_Unbounded_String;
   end Release;

   procedure Watch_Path (State : in out Watch_State; Path : String) is
      C_Path : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.Null_Ptr;
      FD     : Interfaces.C.int;
      WD     : Interfaces.C.int;
   begin
      if Path = "" then
         Release (State);
         return;
      end if;

      if State.Handle >= 0 and then To_String (State.Path) = Path then
         return;
      end if;

      Release (State);

      FD := Inotify_Init1 (Nonblock + Cloexec);
      if FD < 0 then
         return;
      end if;

      C_Path := Interfaces.C.Strings.New_String (Path);
      WD := Inotify_Add_Watch (FD, C_Path, Event_Mask);
      Interfaces.C.Strings.Free (C_Path);

      if WD < 0 then
         declare
            Ignored : constant Interfaces.C.int := C_Close (FD);
         begin
            pragma Unreferenced (Ignored);
         end;
         return;
      end if;

      State.Handle := Interfaces.C.ptrdiff_t (FD);
      State.Extra := Interfaces.C.ptrdiff_t (WD);
      State.Path := To_Unbounded_String (Path);

   exception
      when others =>
         if C_Path /= Interfaces.C.Strings.Null_Ptr then
            Interfaces.C.Strings.Free (C_Path);
         end if;
         Release (State);
   end Watch_Path;

   function Poll (State : in out Watch_State) return Boolean is
      Buffer  : aliased Event_Words := [others => 0];
      Count   : Interfaces.C.long;
      Changed : Boolean := False;
      Gone    : Boolean := False;
   begin
      if State.Handle < 0 then
         return False;
      end if;

      --  The descriptor is non-blocking, so this drains whatever has arrived
      --  and then returns rather than waiting.
      loop
         Count :=
           C_Read
             (Interfaces.C.int (State.Handle),
              Buffer'Address,
              Interfaces.C.size_t (Event_Words'Size / 8));
         exit when Count <= 0;
         Changed := True;
         State.Events := State.Events + 1;

         --  Every record is looked at, not only counted: one of them may say
         --  the directory itself is gone, and a watch that went on looking
         --  active after that would never report anything again.
         declare
            Length : constant Natural := Natural (Count);
            Offset : Natural := 0;
         begin
            while Offset + Header_Bytes <= Length loop
               if (Buffer (Offset / 4 + Mask_Word) and Gone_Mask) /= 0 then
                  Gone := True;
               end if;

               Offset := Offset + Header_Bytes + Natural (Buffer (Offset / 4 + Length_Word));
            end loop;
         end;

         exit when Gone;
      end loop;

      if Gone then
         Release (State);
      end if;

      return Changed;

   exception
      when others =>
         Release (State);
         return False;
   end Poll;

   function Is_Active (State : Watch_State) return Boolean is
   begin
      return State.Handle >= 0;
   end Is_Active;

   function Event_Count (State : Watch_State) return Natural is
   begin
      return State.Events;
   end Event_Count;

   --  IN_MODIFY is in the mask.
   function Sees_File_Writes return Boolean is (True);

end Hostkit.Watch;
