with Interfaces.C.Strings;
with Interfaces.C;

package body Hostkit.Pty is

   use type Interfaces.C.int;
   use type Interfaces.C.Strings.chars_ptr;

   subtype C_Int is Interfaces.C.int;

   --  macOS values. O_NOCTTY is 0x20000 here and 0o400 on Linux; opening the
   --  device side with the Linux number would set O_SHLOCK instead and leave
   --  the terminal free to become this process's controlling one -- so a shell
   --  would start taking the Ctrl-C meant for the child it just made it for.
   O_Rdwr   : constant C_Int := 16#0002#;
   O_Noctty : constant C_Int := 16#2_0000#;

   --  posix_openpt and friends rather than openpty. openpty is in libutil and
   --  would put a -lutil in every consumer's link line for one call; these four
   --  are POSIX, live in libc on Linux and macOS alike, and say plainly what
   --  each step is for.
   function Posix_Openpt (Flags : C_Int) return C_Int
     with Import => True, Convention => C, External_Name => "posix_openpt";
   function Grantpt (Fd : C_Int) return C_Int
     with Import => True, Convention => C, External_Name => "grantpt";
   function Unlockpt (Fd : C_Int) return C_Int
     with Import => True, Convention => C, External_Name => "unlockpt";
   function Ptsname (Fd : C_Int) return Interfaces.C.Strings.chars_ptr
     with Import => True, Convention => C, External_Name => "ptsname";
   function C_Open
     (Path  : Interfaces.C.Strings.chars_ptr;
      Flags : C_Int;
      Mode  : Interfaces.C.unsigned) return C_Int
     with Import => True, Convention => C, External_Name => "open";
   function C_Close (Fd : C_Int) return C_Int
     with Import => True, Convention => C, External_Name => "close";
   function C_Fcntl (Fd : C_Int; Command : C_Int; Argument : C_Int) return C_Int
     with Import => True, Convention => C, External_Name => "fcntl";

   F_Setfd    : constant C_Int := 2;
   FD_Cloexec : constant C_Int := 1;

   function Make_Private (Fd : C_Int) return Boolean
   is (C_Fcntl (Fd, F_Setfd, FD_Cloexec) = 0);
   --  Non-inheritable, matching every other descriptor this crate produces:
   --  inheritance is opted into per child, never inherited by default.

   ------------------
   -- Is_Supported --
   ------------------

   function Is_Supported return Boolean is
   begin
      return True;
   end Is_Supported;

   ----------
   -- Open --
   ----------

   function Open (Item : out Pair) return Boolean is
      Controller : C_Int;
      Device     : C_Int;
      Name       : Interfaces.C.Strings.chars_ptr;
      Ignored    : C_Int;
   begin
      Item := (Controller => Hostkit.Descriptors.Invalid,
               Device     => Hostkit.Descriptors.Invalid);

      --  O_NOCTTY: opening a terminal would otherwise make it this process's
      --  controlling terminal, and a shell acquiring the pseudo-terminal it
      --  just made for a child would then take Ctrl-C meant for that child.
      Controller := Posix_Openpt (O_Rdwr + O_Noctty);

      if Controller < 0 then
         return False;
      end if;

      --  grantpt sets the device side's ownership and permissions to this user,
      --  and unlockpt is what makes it openable at all. Skipping either gives a
      --  device side that exists and cannot be opened, which reads as a
      --  permissions problem somewhere else entirely.
      if Grantpt (Controller) /= 0 or else Unlockpt (Controller) /= 0 then
         Ignored := C_Close (Controller);
         return False;
      end if;

      Name := Ptsname (Controller);

      if Name = Interfaces.C.Strings.Null_Ptr then
         Ignored := C_Close (Controller);
         return False;
      end if;

      Device := C_Open (Name, O_Rdwr + O_Noctty, 0);

      if Device < 0 then
         Ignored := C_Close (Controller);
         return False;
      end if;

      if not Make_Private (Controller) or else not Make_Private (Device) then
         Ignored := C_Close (Controller);
         Ignored := C_Close (Device);
         return False;
      end if;

      Item :=
        (Controller =>
           Hostkit.Descriptors.From_Native_Value (Long_Long_Integer (Controller)),
         Device     =>
           Hostkit.Descriptors.From_Native_Value (Long_Long_Integer (Device)));

      return True;
   end Open;

   -----------------
   -- Device_Name --
   -----------------

   function Device_Name (Item : Pair) return String is
      Name : Interfaces.C.Strings.chars_ptr;
   begin
      if not Hostkit.Descriptors.Is_Valid (Item.Controller) then
         return "";
      end if;

      --  Asked of the controller, not remembered from Open. ptsname returns a
      --  pointer into storage the C library may reuse, so keeping the pointer
      --  would be a name that changes underneath the caller; this copies it
      --  into an Ada String at the moment it is asked for.
      Name := Ptsname
        (C_Int (Hostkit.Descriptors.Native_Value (Item.Controller)));

      if Name = Interfaces.C.Strings.Null_Ptr then
         return "";
      end if;

      return Interfaces.C.Strings.Value (Name);
   end Device_Name;

   -----------
   -- Close --
   -----------

   procedure Close (Item : in out Pair) is
   begin
      Hostkit.Descriptors.Close (Item.Controller);
      Hostkit.Descriptors.Close (Item.Device);
   end Close;

   --------------
   -- Set_Size --
   --------------

   function Set_Size
     (Item : Pair;
      To   : Hostkit.Terminal_Control.Window_Size) return Boolean
   is
   begin
      --  Set on the controller. Setting it there is what makes the host raise
      --  the window-change signal on the far side, which is how the program
      --  under the pseudo-terminal learns to redraw.
      return Hostkit.Terminal_Control.Set_Size (Item.Controller, To);
   end Set_Size;

end Hostkit.Pty;
