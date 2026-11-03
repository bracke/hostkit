--  Windows: the microphone through winmm's waveIn, the oldest recording
--  interface the system keeps and the one every version has.
--
--  The stream is opened on the wave mapper -- the system's chosen input, or
--  the device whose name a source gives (waveInGetDevCapsW's szPname) -- at
--  sixteen kilohertz, one channel of sixteen-bit samples, which the mapper
--  converts to from whatever the device records. Four buffers of a tenth of
--  a second each are queued; Read waits for the next in turn to be marked
--  done, copies it out and queues it again. With no callback asked
--  (CALLBACK_NULL) the flag on each header is how a buffer is known to be
--  full, so Read polls it, a few milliseconds at a time, and gives up after
--  three seconds with nothing: a host with no sound arriving answers Failed
--  rather than waiting for ever.
--
--  The structures are WAVEFORMATEX (eighteen bytes, packed) and WAVEHDR, of
--  which lpData, dwBufferLength, dwBytesRecorded and dwFlags are read and
--  written, at their 64-bit offsets.
with Ada.Unchecked_Conversion;
with Ada.Unchecked_Deallocation;
with Interfaces.C;

package body Hostkit.Microphone is

   package C renames Interfaces.C;

   use Ada.Strings.Unbounded;
   use type System.Address;
   use type C.unsigned;
   use type Interfaces.Unsigned_32;
   use type Ada.Streams.Stream_Element_Offset;

   Wave_Mapper : constant C.unsigned := C.unsigned'Last;
   Done_Flag   : constant Interfaces.Unsigned_32 := 1;
   Buffers     : constant := 4;

   type Wave_Format is record
      Tag             : Interfaces.Unsigned_16 := 1;
      Channel_Count   : Interfaces.Unsigned_16 := Channels;
      Samples_Second  : Interfaces.Unsigned_32 := Rate;
      Bytes_Second    : Interfaces.Unsigned_32 := Rate * 2;
      Block_Align     : Interfaces.Unsigned_16 := 2;
      Bits            : Interfaces.Unsigned_16 := 16;
      Extra           : Interfaces.Unsigned_16 := 0;
   end record
     with Convention => C, Pack;

   type Wave_Header is record
      Data      : System.Address := System.Null_Address;
      Length    : Interfaces.Unsigned_32 := 0;
      Recorded  : Interfaces.Unsigned_32 := 0;
      User      : System.Address := System.Null_Address;
      Flags     : Interfaces.Unsigned_32 := 0;
      Loops     : Interfaces.Unsigned_32 := 0;
      Next      : System.Address := System.Null_Address;
      Reserved  : System.Address := System.Null_Address;
   end record
     with Convention => C;

   subtype Chunk_Room is Ada.Streams.Stream_Element_Array (1 .. Chunk_Bytes);
   type Header_Array is array (1 .. Buffers) of aliased Wave_Header;
   type Room_Array is array (1 .. Buffers) of aliased Chunk_Room;

   --  A stream's state, on the heap so the headers the system writes into
   --  do not move.
   type State is record
      Handle  : aliased System.Address := System.Null_Address;
      Headers : Header_Array;
      Rooms   : Room_Array;
      Next    : Positive := 1;
   end record;

   type State_Access is access State;
   procedure Free is new Ada.Unchecked_Deallocation (State, State_Access);
   function To_State is new Ada.Unchecked_Conversion (System.Address, State_Access);
   function To_Address is new Ada.Unchecked_Conversion (State_Access, System.Address);

   function Wave_In_Count return C.unsigned
     with Import, Convention => Stdcall, External_Name => "waveInGetNumDevs";

   --  WAVEINCAPSW: wMid, wPid, vDriverVersion, szPname[32], dwFormats,
   --  wChannels, wReserved1.
   type Caps is record
      Maker, Product : Interfaces.Unsigned_16;
      Version        : Interfaces.Unsigned_32;
      Name           : C.wchar_array (0 .. 31);
      Formats        : Interfaces.Unsigned_32;
      Channel_Count  : Interfaces.Unsigned_16;
      Reserved       : Interfaces.Unsigned_16;
   end record
     with Convention => C;

   function Wave_In_Caps (Device : C.unsigned; Into : access Caps; Size : C.unsigned) return C.unsigned
     with Import, Convention => Stdcall, External_Name => "waveInGetDevCapsW";

   function Wave_In_Open
     (Handle : access System.Address; Device : C.unsigned; Format : access constant Wave_Format;
      Callback, Instance : System.Address; Flags : Interfaces.Unsigned_32) return C.unsigned
     with Import, Convention => Stdcall, External_Name => "waveInOpen";

   function Wave_In_Prepare (Handle : System.Address; Header : access Wave_Header; Size : C.unsigned)
      return C.unsigned
     with Import, Convention => Stdcall, External_Name => "waveInPrepareHeader";

   function Wave_In_Unprepare (Handle : System.Address; Header : access Wave_Header; Size : C.unsigned)
      return C.unsigned
     with Import, Convention => Stdcall, External_Name => "waveInUnprepareHeader";

   function Wave_In_Add (Handle : System.Address; Header : access Wave_Header; Size : C.unsigned)
      return C.unsigned
     with Import, Convention => Stdcall, External_Name => "waveInAddBuffer";

   function Wave_In_Start (Handle : System.Address) return C.unsigned
     with Import, Convention => Stdcall, External_Name => "waveInStart";

   function Wave_In_Reset (Handle : System.Address) return C.unsigned
     with Import, Convention => Stdcall, External_Name => "waveInReset";

   function Wave_In_Close (Handle : System.Address) return C.unsigned
     with Import, Convention => Stdcall, External_Name => "waveInClose";

   Header_Size : constant C.unsigned := C.unsigned (Wave_Header'Size / 8);

   function Is_Supported return Boolean is (Wave_In_Count > 0);

   --  The device a name names, or the mapper for none; Found False where no
   --  device is named so.
   procedure Find (Name : String; Device : out C.unsigned; Found : out Boolean) is
      Count : constant C.unsigned := Wave_In_Count;
   begin
      Device := Wave_Mapper;
      Found := Name = "";
      if Found then
         return;
      end if;
      for Index in 0 .. Integer (Count) - 1 loop
         declare
            Info : aliased Caps;
         begin
            if Wave_In_Caps (C.unsigned (Index), Info'Access, C.unsigned (Caps'Size / 8)) = 0 then
               declare
                  Wide : constant Wide_String := C.To_Ada (Info.Name);
                  Text : String (Wide'Range);
               begin
                  for I in Wide'Range loop
                     Text (I) := (if Wide_Character'Pos (Wide (I)) < 256
                                  then Character'Val (Wide_Character'Pos (Wide (I))) else '?');
                  end loop;
                  if Text = Name then
                     Device := C.unsigned (Index);
                     Found := True;
                     return;
                  end if;
               end;
            end if;
         end;
      end loop;
   end Find;

   function Source_Present (Name : String) return Source_Answer is
      Device : C.unsigned;
      Found  : Boolean;
   begin
      if Wave_In_Count = 0 then
         return Unknown;
      end if;
      Find (Name, Device, Found);
      return (if Found then Present else Absent);
   end Source_Present;

   procedure Open
     (Item   : in out Device;
      Source : String;
      Result : out Outcome;
      Reason : out Unbounded_String)
   is
      Format  : aliased constant Wave_Format := (others => <>);
      Number  : C.unsigned;
      Found   : Boolean;
      Held    : State_Access;
      Code    : C.unsigned;
   begin
      Close (Item);
      Result := Done;
      Reason := Null_Unbounded_String;
      if Wave_In_Count = 0 then
         Result := Unsupported;
         Reason := To_Unbounded_String ("this machine has no recording device");
         return;
      end if;
      Find (Source, Number, Found);
      if not Found then
         Result := Refused;
         Reason := To_Unbounded_String ("no recording device is named " & Source);
         return;
      end if;
      Held := new State;
      Code := Wave_In_Open (Held.Handle'Access, Number, Format'Access, System.Null_Address, System.Null_Address, 0);
      if Code /= 0 then
         Free (Held);
         Result := Refused;
         Reason := To_Unbounded_String ("waveInOpen refused, error" & Code'Image);
         return;
      end if;
      for I in Held.Headers'Range loop
         Held.Headers (I).Data := Held.Rooms (I)'Address;
         Held.Headers (I).Length := Chunk_Bytes;
         Code := Wave_In_Prepare (Held.Handle, Held.Headers (I)'Access, Header_Size);
         if Code = 0 then
            Code := Wave_In_Add (Held.Handle, Held.Headers (I)'Access, Header_Size);
         end if;
         exit when Code /= 0;
      end loop;
      if Code = 0 then
         Code := Wave_In_Start (Held.Handle);
      end if;
      Item.Stream := To_Address (Held);
      if Code /= 0 then
         Close (Item);
         Result := Refused;
         Reason := To_Unbounded_String ("the recording would not start, error" & Code'Image);
      end if;
   end Open;

   procedure Read
     (Item   : in out Device;
      Into   : out Ada.Streams.Stream_Element_Array;
      Result : out Outcome;
      Reason : out Unbounded_String)
   is
      Held  : constant State_Access := To_State (Item.Stream);
      Waits : Natural := 0;
   begin
      Into := [others => 0];
      Result := Done;
      Reason := Null_Unbounded_String;
      if Held = null then
         Result := Failed;
         Reason := To_Unbounded_String ("not open");
         return;
      end if;
      declare
         Header : Wave_Header renames Held.Headers (Held.Next);
         Got    : Ada.Streams.Stream_Element_Offset;
      begin
         while (Header.Flags and Done_Flag) = 0 loop
            delay 0.005;
            Waits := Waits + 1;
            if Waits > 600 then
               Result := Failed;
               Reason := To_Unbounded_String ("no sound came for three seconds");
               return;
            end if;
         end loop;
         Got := Ada.Streams.Stream_Element_Offset (Interfaces.Unsigned_32'Min (Header.Recorded, Chunk_Bytes));
         Into (Into'First .. Into'First + Got - 1) := Held.Rooms (Held.Next) (1 .. Got);
         Header.Flags := Header.Flags and not Done_Flag;
         Header.Recorded := 0;
         if Wave_In_Add (Held.Handle, Header'Access, Header_Size) /= 0 then
            Result := Failed;
            Reason := To_Unbounded_String ("a buffer could not be queued again");
         end if;
         Held.Next := (if Held.Next = Buffers then 1 else Held.Next + 1);
      end;
   end Read;

   procedure Close (Item : in out Device) is
      Held    : State_Access := To_State (Item.Stream);
      Ignored : C.unsigned;
   begin
      if Held = null then
         return;
      end if;
      if Held.Handle /= System.Null_Address then
         Ignored := Wave_In_Reset (Held.Handle);
         for I in Held.Headers'Range loop
            Ignored := Wave_In_Unprepare (Held.Handle, Held.Headers (I)'Access, Header_Size);
         end loop;
         Ignored := Wave_In_Close (Held.Handle);
      end if;
      Free (Held);
      Item.Stream := System.Null_Address;
   end Close;

   function Is_Open (Item : Device) return Boolean is (Item.Stream /= System.Null_Address);

end Hostkit.Microphone;
