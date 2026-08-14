with Ada.Streams;

with Interfaces.C;

with System;

package body Hostkit.Terminal_Control is

   use type Interfaces.C.int;
   use type Interfaces.C.unsigned_short;

   subtype C_Int is Interfaces.C.int;

   --  TIOCGWINSZ and TIOCSWINSZ, Linux. These are plain small numbers here; on
   --  macOS the same requests are encoded with direction and size bits and come
   --  out as 0x40087468 and 0x80087467, which is why the two hosts cannot share
   --  a table.
   TIOCGWINSZ : constant Interfaces.C.unsigned_long := 16#5413#;
   TIOCSWINSZ : constant Interfaces.C.unsigned_long := 16#5414#;

   --  tcsetattr's "when": TCSADRAIN waits for pending output to drain and
   --  leaves unread input alone. Draining matters on every mode change --
   --  output already written must not be reinterpreted under the new settings.
   --
   --  Not TCSAFLUSH, which would also discard input the user has already
   --  typed. That looks tidy and is data loss: a shell entering raw mode for
   --  each line would throw away everything typed ahead while the previous
   --  command was still running, and the user would have no way to know which
   --  of their keystrokes had been kept.
   TCSADRAIN : constant C_Int := 1;

   --  struct winsize. Four unsigned shorts on both Linux and macOS; this is one
   --  of the few structures the two agree about.
   type Window_Size_Native is record
      Rows       : Interfaces.C.unsigned_short := 0;
      Columns    : Interfaces.C.unsigned_short := 0;
      X_Pixels   : Interfaces.C.unsigned_short := 0;
      Y_Pixels   : Interfaces.C.unsigned_short := 0;
   end record
     with Convention => C;

   function Tcgetpgrp (Fd : C_Int) return C_Int
     with Import => True, Convention => C, External_Name => "tcgetpgrp";
   function Tcsetpgrp (Fd : C_Int; Group : C_Int) return C_Int
     with Import => True, Convention => C, External_Name => "tcsetpgrp";

   --  The terminal settings structure is never modelled here. Its fields differ
   --  in width and in count between hosts -- Linux's tcflag_t is 32 bits and
   --  macOS's is 64 -- and a consumer needs none of them. tcgetattr fills an
   --  opaque buffer, cfmakeraw rewrites it, tcsetattr applies it, and nothing on
   --  this side has to know the layout. Modelling it field by field is how a
   --  binding silently corrupts a terminal's settings after a libc update.
   function Tcgetattr (Fd : C_Int; Settings : System.Address) return C_Int
     with Import => True, Convention => C, External_Name => "tcgetattr";
   function Tcsetattr
     (Fd : C_Int; When_To : C_Int; Settings : System.Address) return C_Int
     with Import => True, Convention => C, External_Name => "tcsetattr";
   procedure Cfmakeraw (Settings : System.Address)
     with Import => True, Convention => C, External_Name => "cfmakeraw";

   function Ioctl
     (Fd : C_Int; Request : Interfaces.C.unsigned_long; Argument : System.Address)
      return C_Int
     with Import => True, Convention => C, External_Name => "ioctl";

   function To_Fd (Item : Hostkit.Descriptors.Descriptor) return C_Int
   is (C_Int (Hostkit.Descriptors.Native_Value (Item)));

   -------------------------------
   -- Supports_Foreground_Group --
   -------------------------------

   function Supports_Foreground_Group return Boolean is
   begin
      return True;
   end Supports_Foreground_Group;

   ----------------------
   -- Foreground_Group --
   ----------------------

   function Foreground_Group
     (Terminal : Hostkit.Descriptors.Descriptor;
      Group    : out Integer) return Boolean
   is
      Result : C_Int;
   begin
      Group := -1;

      if not Hostkit.Descriptors.Is_Valid (Terminal) then
         return False;
      end if;

      Result := Tcgetpgrp (To_Fd (Terminal));

      if Result < 0 then
         return False;
      end if;

      Group := Integer (Result);
      return True;
   end Foreground_Group;

   --------------------------
   -- Set_Foreground_Group --
   --------------------------

   function Set_Foreground_Group
     (Terminal : Hostkit.Descriptors.Descriptor;
      Group    : Integer) return Boolean
   is
   begin
      if not Hostkit.Descriptors.Is_Valid (Terminal) or else Group <= 0 then
         --  A non-positive group is not a near miss. tcsetpgrp would reject it,
         --  but refusing here keeps the meaning of the argument the same as
         --  everywhere else in this crate.
         return False;
      end if;

      --  SIGTTOU is raised on this call when the caller is not already in the
      --  foreground group. Deliberately not disarmed here: the disposition is
      --  process-wide and belongs to the consumer. See the package header.
      return Tcsetpgrp (To_Fd (Terminal), C_Int (Group)) = 0;
   end Set_Foreground_Group;

   ---------------
   -- Save_Mode --
   ---------------

   function Save_Mode
     (Terminal : Hostkit.Descriptors.Descriptor;
      Into     : out Mode) return Boolean
   is
   begin
      Into := (Bytes => [others => 0], Valid => False);

      if not Hostkit.Descriptors.Is_Valid (Terminal) then
         return False;
      end if;

      if Tcgetattr (To_Fd (Terminal), Into.Bytes'Address) /= 0 then
         return False;
      end if;

      Into.Valid := True;
      return True;
   end Save_Mode;

   ------------------
   -- Restore_Mode --
   ------------------

   function Restore_Mode
     (Terminal : Hostkit.Descriptors.Descriptor;
      From     : Mode) return Boolean
   is
      Settings : Mode_Storage := From.Bytes;
   begin
      --  A mode that was never saved is zeroes, and applying zeroes to a
      --  terminal is worse than leaving it raw: no baud rate, no character
      --  size, no control characters at all.
      if not From.Valid or else not Hostkit.Descriptors.Is_Valid (Terminal) then
         return False;
      end if;

      return Tcsetattr (To_Fd (Terminal), TCSADRAIN, Settings'Address) = 0;
   end Restore_Mode;

   -------------
   -- Set_Raw --
   -------------

   function Set_Raw (Terminal : Hostkit.Descriptors.Descriptor) return Boolean is
      Settings : Mode_Storage := [others => 0];
   begin
      if not Hostkit.Descriptors.Is_Valid (Terminal) then
         return False;
      end if;

      --  Read, then modify, then write. Starting from zeroes and setting only
      --  the flags raw mode cares about would discard the baud rate and the
      --  control characters this terminal actually has.
      if Tcgetattr (To_Fd (Terminal), Settings'Address) /= 0 then
         return False;
      end if;

      --  cfmakeraw rather than a hand-written set of flag clears. It is what
      --  the host itself considers raw, it is present on Linux and macOS alike,
      --  and it does not need this binding to know which bit is ICANON.
      Cfmakeraw (Settings'Address);

      return Tcsetattr (To_Fd (Terminal), TCSADRAIN, Settings'Address) = 0;
   end Set_Raw;

   ----------
   -- Size --
   ----------

   function Size
     (Terminal : Hostkit.Descriptors.Descriptor;
      Into     : out Window_Size) return Boolean
   is
      Native : aliased Window_Size_Native;
   begin
      Into := (Rows => 0, Columns => 0);

      if not Hostkit.Descriptors.Is_Valid (Terminal) then
         return False;
      end if;

      if Ioctl (To_Fd (Terminal), TIOCGWINSZ, Native'Address) /= 0 then
         --  A pipe has no size, and this is where that is reported. Zero rows
         --  is not the answer to "how big is it": a caller that stored it would
         --  divide by it.
         return False;
      end if;

      --  A terminal that reports zero is a terminal that does not know -- an
      --  unresized pseudo-terminal, most often. Refused for the same reason.
      if Native.Rows = 0 or else Native.Columns = 0 then
         return False;
      end if;

      Into := (Rows    => Natural (Native.Rows),
               Columns => Natural (Native.Columns));
      return True;
   end Size;

   --------------
   -- Set_Size --
   --------------

   function Set_Size
     (Terminal : Hostkit.Descriptors.Descriptor;
      To       : Window_Size) return Boolean
   is
      Native : aliased Window_Size_Native;
   begin
      if not Hostkit.Descriptors.Is_Valid (Terminal)
        or else To.Rows = 0
        or else To.Columns = 0
      then
         return False;
      end if;

      Native.Rows    := Interfaces.C.unsigned_short (To.Rows);
      Native.Columns := Interfaces.C.unsigned_short (To.Columns);

      --  The pixel fields stay zero. Almost nothing reads them, and inventing a
      --  cell size to fill them in would be a guess a consumer might believe.
      return Ioctl (To_Fd (Terminal), TIOCSWINSZ, Native'Address) = 0;
   end Set_Size;

   ------------------------------
   -- Supports_Cursor_Control --
   ------------------------------

   function Supports_Cursor_Control
     (Terminal : Hostkit.Descriptors.Descriptor) return Boolean
   is
   begin
      --  A terminal, and nothing else. Writing control sequences into a file or
      --  a pipe puts escape bytes in whatever is reading it.
      return Hostkit.Descriptors.Is_Valid (Terminal)
        and then Hostkit.Descriptors.Is_Terminal (Terminal);
   end Supports_Cursor_Control;

   -------------
   -- Control --
   -------------

   function Control
     (Terminal : Hostkit.Descriptors.Descriptor;
      Action   : Cursor_Action;
      Count    : Natural := 1) return Boolean
   is
      --  The escape sequences live here and nowhere else in the ecosystem.
      Escape : constant Character := Character'Val (16#1B#);

      function Number (Value : Natural) return String;
      --  The value without Ada's leading blank.

      function Number (Value : Natural) return String is
         Image : constant String := Natural'Image (Value);
      begin
         return Image (Image'First + 1 .. Image'Last);
      end Number;

      function Sequence return String;

      function Sequence return String is
      begin
         case Action is
            when Erase_To_End_Of_Line => return Escape & "[K";
            when Erase_Line           => return Escape & "[2K";
            when To_First_Column      => return Escape & "[G";
            when Move_Left            => return Escape & "[" & Number (Count) & "D";
            when Move_Right           => return Escape & "[" & Number (Count) & "C";
            when Move_Up              => return Escape & "[" & Number (Count) & "A";
            when Move_Down            => return Escape & "[" & Number (Count) & "B";
            when Hide_Cursor          => return Escape & "[?25l";
            when Show_Cursor          => return Escape & "[?25h";
         end case;
      end Sequence;

   begin
      if not Supports_Cursor_Control (Terminal) then
         return False;
      end if;

      --  Moving nothing is not a failure and is not a write. A caller that
      --  computed a distance of zero would otherwise emit "move left zero",
      --  which some terminals read as "move left one".
      if Count = 0
        and then Action in Move_Left | Move_Right | Move_Up | Move_Down
      then
         return True;
      end if;

      declare
         Text  : constant String := Sequence;
         Bytes : Ada.Streams.Stream_Element_Array
                   (1 .. Ada.Streams.Stream_Element_Offset (Text'Length));
         From  : Ada.Streams.Stream_Element_Offset := Bytes'First;
         Last  : Ada.Streams.Stream_Element_Offset;

         use type Ada.Streams.Stream_Element_Offset;
      begin
         for Index in Text'Range loop
            Bytes (Ada.Streams.Stream_Element_Offset (Index - Text'First + 1)) :=
              Ada.Streams.Stream_Element (Character'Pos (Text (Index)));
         end loop;

         --  Resume from Last + 1 on a short write. A control sequence that went
         --  out in halves is not a control sequence; the terminal would print
         --  the tail of it.
         while From <= Bytes'Last loop
            case Hostkit.Descriptors.Write (Terminal, Bytes (From .. Bytes'Last), Last) is
               when Hostkit.Descriptors.Transfer_Ok =>
                  exit when Last < From;
                  From := Last + 1;

               when Hostkit.Descriptors.Transfer_Interrupted =>
                  null;

               when others =>
                  return False;
            end case;
         end loop;

         return From > Bytes'Last;
      end;
   end Control;

end Hostkit.Terminal_Control;
