with Ada.Streams;
with Interfaces.C;

with System.Storage_Elements;
with System;

package body Hostkit.Terminal_Control is

   use type Interfaces.C.int;
   use type Interfaces.C.unsigned_long;
   use type Interfaces.C.short;

   subtype C_DWord is Interfaces.C.unsigned_long;

   --  Console modes. Raw here means clearing the input flags the console host
   --  applies -- line assembly, echo, and the translation of Ctrl-C into a
   --  control event -- and enabling virtual-terminal input so that arrow keys
   --  arrive as escape sequences rather than as key records a caller would have
   --  to decode separately.
   Enable_Processed_Input        : constant C_DWord := 16#0001#;
   Enable_Line_Input             : constant C_DWord := 16#0002#;
   Enable_Echo_Input             : constant C_DWord := 16#0004#;
   Enable_Virtual_Terminal_Input : constant C_DWord := 16#0200#;

   --  On the output handle: interpret control sequences rather than printing
   --  them. Required before any cursor movement or erase reaches the screen.
   Enable_Virtual_Terminal_Processing : constant C_DWord := 16#0004#;

   function Get_Console_Mode
     (Handle : System.Address; Mode : access C_DWord) return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "GetConsoleMode";

   function Set_Console_Mode
     (Handle : System.Address; Mode : C_DWord) return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "SetConsoleMode";

   --  COORD, SMALL_RECT and CONSOLE_SCREEN_BUFFER_INFO. All shorts, so the
   --  layout is the same on 32- and 64-bit Windows alike.
   type Coord is record
      X : Interfaces.C.short := 0;
      Y : Interfaces.C.short := 0;
   end record
     with Convention => C;

   type Small_Rect is record
      Left   : Interfaces.C.short := 0;
      Top    : Interfaces.C.short := 0;
      Right  : Interfaces.C.short := 0;
      Bottom : Interfaces.C.short := 0;
   end record
     with Convention => C;

   type Console_Screen_Buffer_Info is record
      Size              : Coord;
      Cursor_Position   : Coord;
      Attributes        : Interfaces.C.unsigned_short := 0;
      Window            : Small_Rect;
      Maximum_Window    : Coord;
   end record
     with Convention => C;

   pragma Compile_Time_Error
     (Console_Screen_Buffer_Info'Size /= 22 * 8,
      "CONSOLE_SCREEN_BUFFER_INFO layout does not match the Win32 one");

   function Get_Console_Screen_Buffer_Info
     (Handle : System.Address;
      Info   : access Console_Screen_Buffer_Info) return Interfaces.C.int
     with Import => True, Convention => Stdcall,
          External_Name => "GetConsoleScreenBufferInfo";

   function To_Handle (Item : Hostkit.Descriptors.Descriptor) return System.Address
   is (System.Storage_Elements.To_Address
         (System.Storage_Elements.Integer_Address
            (Hostkit.Descriptors.Native_Value (Item))));

   --  The Mode buffer holds one console mode word here, where the POSIX bodies
   --  keep a struct termios. Same contract: opaque bytes out of Save_Mode and
   --  back into Restore_Mode, never interpreted by a consumer.
   function Stored_Mode (From : Mode) return C_DWord;
   procedure Store_Mode (Value : C_DWord; Into : out Mode);

   -----------------
   -- Stored_Mode --
   -----------------

   function Stored_Mode (From : Mode) return C_DWord is
      Result : C_DWord := 0;
   begin
      for Index in reverse 1 .. 4 loop
         Result := Result * 256 + C_DWord (From.Bytes (Index));
      end loop;

      return Result;
   end Stored_Mode;

   ----------------
   -- Store_Mode --
   ----------------

   procedure Store_Mode (Value : C_DWord; Into : out Mode) is
      Remaining : C_DWord := Value;
   begin
      Into := (Bytes => [others => 0], Valid => True);

      for Index in 1 .. 4 loop
         Into.Bytes (Index) := Interfaces.Unsigned_8 (Remaining mod 256);
         Remaining := Remaining / 256;
      end loop;
   end Store_Mode;

   -------------------------------
   -- Supports_Foreground_Group --
   -------------------------------

   function Supports_Foreground_Group return Boolean is
   begin
      --  Windows has no process groups in the POSIX sense and therefore no
      --  foreground one. A console does have an attached process list, but
      --  membership of it is not ownership and nothing is stopped by not being
      --  in it -- reporting True and mapping onto it would be the confident
      --  wrong answer this crate exists to prevent.
      return False;
   end Supports_Foreground_Group;

   ----------------------
   -- Foreground_Group --
   ----------------------

   function Foreground_Group
     (Terminal : Hostkit.Descriptors.Descriptor;
      Group    : out Integer) return Boolean
   is
      pragma Unreferenced (Terminal);
   begin
      Group := -1;
      return False;
   end Foreground_Group;

   --------------------------
   -- Set_Foreground_Group --
   --------------------------

   function Set_Foreground_Group
     (Terminal : Hostkit.Descriptors.Descriptor;
      Group    : Integer) return Boolean
   is
      pragma Unreferenced (Terminal, Group);
   begin
      return False;
   end Set_Foreground_Group;

   ---------------
   -- Save_Mode --
   ---------------

   function Save_Mode
     (Terminal : Hostkit.Descriptors.Descriptor;
      Into     : out Mode) return Boolean
   is
      Current : aliased C_DWord := 0;
   begin
      Into := (Bytes => [others => 0], Valid => False);

      if not Hostkit.Descriptors.Is_Valid (Terminal) then
         return False;
      end if;

      if Get_Console_Mode (To_Handle (Terminal), Current'Access) = 0 then
         return False;
      end if;

      Store_Mode (Current, Into);
      return True;
   end Save_Mode;

   ------------------
   -- Restore_Mode --
   ------------------

   function Restore_Mode
     (Terminal : Hostkit.Descriptors.Descriptor;
      From     : Mode) return Boolean
   is
   begin
      if not From.Valid or else not Hostkit.Descriptors.Is_Valid (Terminal) then
         return False;
      end if;

      return Set_Console_Mode (To_Handle (Terminal), Stored_Mode (From)) /= 0;
   end Restore_Mode;

   -------------
   -- Set_Raw --
   -------------

   function Set_Raw (Terminal : Hostkit.Descriptors.Descriptor) return Boolean is
      Current : aliased C_DWord := 0;
      Wanted  : C_DWord;
   begin
      if not Hostkit.Descriptors.Is_Valid (Terminal) then
         return False;
      end if;

      --  Read then modify, as the POSIX bodies do: starting from zero would
      --  discard flags this console has that raw mode has no opinion about.
      if Get_Console_Mode (To_Handle (Terminal), Current'Access) = 0 then
         return False;
      end if;

      Wanted := Current
        - (Current and Enable_Line_Input)
        - (Current and Enable_Echo_Input)
        - (Current and Enable_Processed_Input);

      --  Arrow keys and the rest arrive as escape sequences, which is the same
      --  thing a caller reads on POSIX and means one decoder rather than two.
      Wanted := Wanted or Enable_Virtual_Terminal_Input;

      return Set_Console_Mode (To_Handle (Terminal), Wanted) /= 0;
   end Set_Raw;

   ----------
   -- Size --
   ----------

   function Size
     (Terminal : Hostkit.Descriptors.Descriptor;
      Into     : out Window_Size) return Boolean
   is
      Info : aliased Console_Screen_Buffer_Info;
   begin
      Into := (Rows => 0, Columns => 0);

      if not Hostkit.Descriptors.Is_Valid (Terminal) then
         return False;
      end if;

      if Get_Console_Screen_Buffer_Info (To_Handle (Terminal), Info'Access) = 0 then
         return False;
      end if;

      --  The window, not the buffer. The screen buffer is usually far taller
      --  than the window onto it -- that is what makes a console scroll back --
      --  and a caller laying out for the buffer height would draw a prompt
      --  hundreds of lines below what the user can see.
      if Info.Window.Right < Info.Window.Left
        or else Info.Window.Bottom < Info.Window.Top
      then
         return False;
      end if;

      Into := (Rows    => Natural (Info.Window.Bottom - Info.Window.Top) + 1,
               Columns => Natural (Info.Window.Right - Info.Window.Left) + 1);

      return Into.Rows > 0 and then Into.Columns > 0;
   end Size;

   --------------
   -- Set_Size --
   --------------

   function Set_Size
     (Terminal : Hostkit.Descriptors.Descriptor;
      To       : Window_Size) return Boolean
   is
      pragma Unreferenced (Terminal, To);
   begin
      --  Refused rather than approximated. Resizing a real console means
      --  SetConsoleScreenBufferSize and SetConsoleWindowInfo in an order that
      --  depends on whether the window is growing or shrinking, and getting it
      --  wrong fails or truncates the user's scrollback. The call exists for
      --  pseudo-terminals, which this host does not have -- so there is nothing
      --  here it would legitimately be used for.
      return False;
   end Set_Size;

   ------------------------------
   -- Supports_Cursor_Control --
   ------------------------------

   function Supports_Cursor_Control
     (Terminal : Hostkit.Descriptors.Descriptor) return Boolean
   is
      Current : aliased C_DWord := 0;
   begin
      if not Hostkit.Descriptors.Is_Valid (Terminal)
        or else not Hostkit.Descriptors.Is_Terminal (Terminal)
      then
         return False;
      end if;

      --  A console only understands control sequences once it has been told
      --  to. Older console hosts refuse, and on those this is honestly False
      --  rather than a caller writing escape bytes that get printed.
      if Get_Console_Mode (To_Handle (Terminal), Current'Access) = 0 then
         return False;
      end if;

      if (Current and Enable_Virtual_Terminal_Processing) /= 0 then
         return True;
      end if;

      return Set_Console_Mode
               (To_Handle (Terminal),
                Current or Enable_Virtual_Terminal_Processing) /= 0;
   end Supports_Cursor_Control;

   -------------
   -- Control --
   -------------

   function Control
     (Terminal : Hostkit.Descriptors.Descriptor;
      Action   : Cursor_Action;
      Count    : Natural := 1) return Boolean
   is
      --  The same sequences as on POSIX: a virtual-terminal console speaks
      --  them. The duplication is the price of hostkit's rule that a host body
      --  is complete on its own.
      Escape : constant Character := Character'Val (16#1B#);

      function Number (Value : Natural) return String;

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
