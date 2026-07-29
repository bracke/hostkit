with Interfaces.C.Strings;
with System;

package body Hostkit.Watch is

   use Ada.Strings.Unbounded;
   use type Interfaces.C.int;
   use type Interfaces.C.short;
   use type Interfaces.C.unsigned;
   use type Interfaces.C.unsigned_short;
   use type Interfaces.C.Strings.chars_ptr;

   --  macOS has no inotify. The portable BSD facility is kqueue: register the
   --  open directory as an EVFILT_VNODE source and ask for the changes that mean
   --  its contents moved under us. FSEvents would also work, but it needs a run
   --  loop, and this render loop has one of its own.

   O_Rdonly  : constant Interfaces.C.int := 0;
   O_Evtonly : constant Interfaces.C.int := 16#8000#;
   --  O_EVTONLY opens the directory for event delivery only, so holding it does
   --  not keep a volume from being ejected.

   Evfilt_Vnode : constant Interfaces.C.short := -4;

   Ev_Add    : constant Interfaces.C.unsigned_short := 16#0001#;
   Ev_Enable : constant Interfaces.C.unsigned_short := 16#0004#;
   Ev_Clear  : constant Interfaces.C.unsigned_short := 16#0020#;

   --  NOTE_DELETE, NOTE_WRITE, NOTE_EXTEND, NOTE_ATTRIB, NOTE_LINK,
   --  NOTE_RENAME, NOTE_REVOKE: every way a directory's contents can change.
   Note_Mask : constant Interfaces.C.unsigned :=
     16#0001# or 16#0002# or 16#0004# or 16#0008#
     or 16#0010# or 16#0020# or 16#0040#;

   type Kevent_Record is record
      Ident  : Interfaces.C.unsigned_long := 0;
      Filter : Interfaces.C.short := 0;
      Flags  : Interfaces.C.unsigned_short := 0;
      Fflags : Interfaces.C.unsigned := 0;
      Data   : Interfaces.C.ptrdiff_t := 0;
      Udata  : System.Address := System.Null_Address;
   end record
     with Convention => C;

   type Timespec is record
      Seconds     : Interfaces.C.long := 0;
      Nanoseconds : Interfaces.C.long := 0;
   end record
     with Convention => C;

   function C_Kqueue return Interfaces.C.int
     with Import, Convention => C, External_Name => "kqueue";

   function C_Kevent
     (KQ         : Interfaces.C.int;
      Changelist : System.Address;
      N_Changes  : Interfaces.C.int;
      Eventlist  : System.Address;
      N_Events   : Interfaces.C.int;
      Timeout    : System.Address) return Interfaces.C.int
     with Import, Convention => C, External_Name => "kevent";

   function C_Open
     (Pathname : Interfaces.C.Strings.chars_ptr;
      Flags    : Interfaces.C.int) return Interfaces.C.int
     with Import, Convention => C, External_Name => "open";

   function C_Close
     (FD : Interfaces.C.int) return Interfaces.C.int
     with Import, Convention => C, External_Name => "close";

   procedure Release (State : in out Watch_State) is
      Ignored : Interfaces.C.int;
   begin
      if State.Extra >= 0 then
         Ignored := C_Close (Interfaces.C.int (State.Extra));
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
      KQ     : Interfaces.C.int;
      Dir    : Interfaces.C.int;
   begin
      if Path = "" then
         Release (State);
         return;
      end if;

      if State.Handle >= 0 and then To_String (State.Path) = Path then
         return;
      end if;

      Release (State);

      KQ := C_Kqueue;
      if KQ < 0 then
         return;
      end if;

      C_Path := Interfaces.C.Strings.New_String (Path);
      Dir := C_Open (C_Path, O_Rdonly + O_Evtonly);
      Interfaces.C.Strings.Free (C_Path);

      if Dir < 0 then
         declare
            Ignored : constant Interfaces.C.int := C_Close (KQ);
         begin
            pragma Unreferenced (Ignored);
         end;
         return;
      end if;

      declare
         Change : aliased Kevent_Record :=
           (Ident  => Interfaces.C.unsigned_long (Dir),
            Filter => Evfilt_Vnode,
            Flags  => Ev_Add or Ev_Enable or Ev_Clear,
            Fflags => Note_Mask,
            Data   => 0,
            Udata  => System.Null_Address);
         Zero   : aliased Timespec := (0, 0);
         Result : Interfaces.C.int;
      begin
         --  Registering and polling are the same call; passing no event list
         --  registers without waiting.
         Result :=
           C_Kevent
             (KQ, Change'Address, 1, System.Null_Address, 0, Zero'Address);

         if Result < 0 then
            declare
               Ignored : Interfaces.C.int;
            begin
               Ignored := C_Close (Dir);
               Ignored := C_Close (KQ);
               pragma Unreferenced (Ignored);
            end;
            return;
         end if;
      end;

      State.Handle := Interfaces.C.ptrdiff_t (KQ);
      State.Extra := Interfaces.C.ptrdiff_t (Dir);
      State.Path := To_Unbounded_String (Path);

   exception
      when others =>
         if C_Path /= Interfaces.C.Strings.Null_Ptr then
            Interfaces.C.Strings.Free (C_Path);
         end if;
         Release (State);
   end Watch_Path;

   function Poll (State : in out Watch_State) return Boolean is
      Event   : aliased Kevent_Record;
      Zero    : aliased Timespec := (0, 0);
      Count   : Interfaces.C.int;
      Changed : Boolean := False;
   begin
      if State.Handle < 0 then
         return False;
      end if;

      --  A zero timeout makes this a poll rather than a wait.
      loop
         Count :=
           C_Kevent
             (Interfaces.C.int (State.Handle),
              System.Null_Address, 0,
              Event'Address, 1,
              Zero'Address);
         exit when Count <= 0;
         Changed := True;
         State.Events := State.Events + 1;
      end loop;

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

end Hostkit.Watch;
