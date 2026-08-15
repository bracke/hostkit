with Interfaces.C.Strings;
with Interfaces.C;

package body Hostkit.Pty is

   use type Interfaces.C.int;
   use type Interfaces.C.Strings.chars_ptr;

   subtype C_Int is Interfaces.C.int;

   O_Rdwr   : constant C_Int := 8#2#;
   O_Noctty : constant C_Int := 8#400#;

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
      Item := (others => <>);

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

      --  One bidirectional descriptor, so both of the parent's sides are it.
      --  A caller that writes to one and reads the other is right here and on
      --  the host where they are two ends of two pipes.
      Item :=
        (To_Child   =>
           Hostkit.Descriptors.From_Native_Value (Long_Long_Integer (Controller)),
         From_Child =>
           Hostkit.Descriptors.From_Native_Value (Long_Long_Integer (Controller)),
         Device     =>
           Hostkit.Descriptors.From_Native_Value (Long_Long_Integer (Device)),
         Console    => Hostkit.Spawn.No_Console);

      return True;
   end Open;

   -----------------
   -- Device_Name --
   -----------------

   function Device_Name (Item : Pair) return String is
      Name : Interfaces.C.Strings.chars_ptr;
   begin
      if not Hostkit.Descriptors.Is_Valid (Item.From_Child) then
         return "";
      end if;

      --  Asked of the controller, not remembered from Open. ptsname returns a
      --  pointer into storage the C library may reuse, so keeping the pointer
      --  would be a name that changes underneath the caller; this copies it
      --  into an Ada String at the moment it is asked for.
      Name := Ptsname
        (C_Int (Hostkit.Descriptors.Native_Value (Item.From_Child)));

      if Name = Interfaces.C.Strings.Null_Ptr then
         return "";
      end if;

      return Interfaces.C.Strings.Value (Name);
   end Device_Name;

   ------------
   -- Attach --
   ------------

   function Attach (Item : Pair; To : in out Hostkit.Spawn.Options)
                    return Boolean is
   begin
      --  Inheritable for the one child about to be started. Every descriptor
      --  this crate makes is close-on-exec, and this is the opt-in.
      if not Hostkit.Descriptors.Set_Inheritable (Item.Device, True) then
         return False;
      end if;

      --  The device side is the child's three streams, and the terminal it is
      --  to control. Without the last of those the child reads from a terminal
      --  it does not control, and a Ctrl-C typed at that terminal reaches
      --  nobody -- which is the whole reason a harness opens one of these.
      To.Input := Item.Device;
      To.Output := Item.Device;
      To.Error_Output := Item.Device;
      To.Controlling_Terminal := Item.Device;
      To.Foreground_Terminal := Item.Device;
      To.Group := Hostkit.Spawn.Group_New;

      return True;
   end Attach;

   -------------------
   -- Close_Device --
   -------------------

   procedure Close_Device (Item : in out Pair) is
   begin
      Hostkit.Descriptors.Close (Item.Device);
   end Close_Device;

   -----------
   -- Close --
   -----------

   procedure Close (Item : in out Pair) is
   begin
      --  Both of the parent's sides are the one descriptor here, so closing is
      --  one close and then a hand-back that says so.
      Hostkit.Descriptors.Close (Item.From_Child);
      Item.To_Child := Hostkit.Descriptors.Invalid;
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
      return Hostkit.Terminal_Control.Set_Size (Item.From_Child, To);
   end Set_Size;

end Hostkit.Pty;
