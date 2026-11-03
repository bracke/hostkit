--  macOS: the microphone through AudioToolbox's audio queues, the framework
--  opened by name at the first Open, never linked.
--
--  An input queue is made for sixteen kilohertz, one channel of signed
--  sixteen-bit samples, packed -- Core Audio converts to that from the
--  default input -- with three buffers of a tenth of a second. With no run
--  loop given, the queue calls back on a thread of its own each time a
--  buffer is full. That thread is none of the Ada run time's, so the
--  callback does nothing but copy the bytes into a ring and hand the buffer
--  back to the queue: no protected object, no allocation, no exception. The
--  ring's two counters -- bytes written, bytes read -- are each written by
--  one side only and are atomic; Read waits for a tenth of a second to be
--  there, a few milliseconds at a time, and gives up after three seconds
--  with nothing (a machine whose microphone the user has not allowed this
--  program delivers no buffers at all).
--
--  Only the default input is recorded: naming a source is not done here,
--  and a named one is refused rather than taken for the default.
--
--  The structures passed are AudioStreamBasicDescription (forty bytes) and
--  the queue's AudioQueueBuffer, of which mAudioData (offset 8) and
--  mAudioDataByteSize (offset 16) are read.
with Ada.Unchecked_Conversion;
with Ada.Unchecked_Deallocation;
with Interfaces.C.Strings;
with System.Storage_Elements;

package body Hostkit.Microphone is

   package C renames Interfaces.C;
   package SE renames System.Storage_Elements;

   use Ada.Strings.Unbounded;
   use type System.Address;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;
   use type Interfaces.Integer_32;
   use type SE.Integer_Address;

   RTLD_NOW : constant C.int := 2;

   function dlopen (Name : C.Strings.chars_ptr; Flags : C.int) return System.Address
     with Import, Convention => C, External_Name => "dlopen";

   function dlsym (Handle : System.Address; Name : C.Strings.chars_ptr) return System.Address
     with Import, Convention => C, External_Name => "dlsym";

   type Stream_Description is record
      Sample_Rate       : Interfaces.IEEE_Float_64 := Interfaces.IEEE_Float_64 (Rate);
      Format_Id         : Interfaces.Unsigned_32 := 16#6C70_636D#;  --  'lpcm'
      Format_Flags      : Interfaces.Unsigned_32 := 4 + 8;          --  signed integer, packed
      Bytes_Per_Packet  : Interfaces.Unsigned_32 := 2;
      Frames_Per_Packet : Interfaces.Unsigned_32 := 1;
      Bytes_Per_Frame   : Interfaces.Unsigned_32 := 2;
      Channel_Count     : Interfaces.Unsigned_32 := Channels;
      Bits              : Interfaces.Unsigned_32 := 16;
      Reserved          : Interfaces.Unsigned_32 := 0;
   end record
     with Convention => C;

   Ring_Bytes : constant := 2 * Rate * 2;  --  two seconds
   Buffers    : constant := 3;

   type Ring_Array is array (0 .. Ring_Bytes - 1) of Ada.Streams.Stream_Element
     with Volatile_Components;

   type Buffer_List is array (1 .. Buffers) of System.Address;

   --  A queue's state, on the heap: the callback is given its address.
   type State is record
      Queue       : aliased System.Address := System.Null_Address;
      Held        : Buffer_List := [others => System.Null_Address];
      Ring        : Ring_Array := [others => 0];
      Written     : Interfaces.Unsigned_64 := 0 with Atomic;
      Read_So_Far : Interfaces.Unsigned_64 := 0 with Atomic;
   end record;

   type State_Access is access all State;
   procedure Free is new Ada.Unchecked_Deallocation (State, State_Access);
   function To_State is new Ada.Unchecked_Conversion (System.Address, State_Access);

   type Input_Callback is access procedure
     (User, Queue, Buffer, Start_Time : System.Address; Packets : Interfaces.Unsigned_32;
      Descriptions : System.Address)
     with Convention => C;

   type New_Input_Function is access function
     (Format : access constant Stream_Description; Callback : Input_Callback; User : System.Address;
      Run_Loop, Mode : System.Address; Flags : Interfaces.Unsigned_32; Queue : access System.Address)
      return Interfaces.Integer_32
     with Convention => C;
   type Allocate_Function is access function
     (Queue : System.Address; Size : Interfaces.Unsigned_32; Buffer : access System.Address)
      return Interfaces.Integer_32
     with Convention => C;
   type Enqueue_Function is access function
     (Queue, Buffer : System.Address; Count : Interfaces.Unsigned_32; Descriptions : System.Address)
      return Interfaces.Integer_32
     with Convention => C;
   type Start_Function is access function (Queue, Time : System.Address) return Interfaces.Integer_32
     with Convention => C;
   type Stop_Function is access function (Queue : System.Address; Immediate : Interfaces.Unsigned_8)
      return Interfaces.Integer_32
     with Convention => C;

   function To_New_Input is new Ada.Unchecked_Conversion (System.Address, New_Input_Function);
   function To_Allocate is new Ada.Unchecked_Conversion (System.Address, Allocate_Function);
   function To_Enqueue is new Ada.Unchecked_Conversion (System.Address, Enqueue_Function);
   function To_Start is new Ada.Unchecked_Conversion (System.Address, Start_Function);
   function To_Stop is new Ada.Unchecked_Conversion (System.Address, Stop_Function);

   New_Input     : New_Input_Function;
   Allocate      : Allocate_Function;
   Enqueue       : Enqueue_Function;
   Start         : Start_Function;
   Stop, Dispose : Stop_Function;

   protected Library is
      procedure Ensure;
      function Found return Boolean;
   private
      Tried, Ready : Boolean := False;
   end Library;

   protected body Library is
      procedure Ensure is
         function Symbol (Handle : System.Address; Name : String) return System.Address is
            Text   : C.Strings.chars_ptr := C.Strings.New_String (Name);
            Result : constant System.Address := dlsym (Handle, Text);
         begin
            C.Strings.Free (Text);
            return Result;
         end Symbol;

         Path   : C.Strings.chars_ptr;
         Handle : System.Address;
      begin
         if Tried then
            return;
         end if;
         Tried := True;
         Path := C.Strings.New_String ("/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox");
         Handle := dlopen (Path, RTLD_NOW);
         C.Strings.Free (Path);
         if Handle = System.Null_Address then
            return;
         end if;
         declare
            Found : constant array (1 .. 6) of System.Address :=
              [Symbol (Handle, "AudioQueueNewInput"), Symbol (Handle, "AudioQueueAllocateBuffer"),
               Symbol (Handle, "AudioQueueEnqueueBuffer"), Symbol (Handle, "AudioQueueStart"),
               Symbol (Handle, "AudioQueueStop"), Symbol (Handle, "AudioQueueDispose")];
         begin
            if (for some A of Found => A = System.Null_Address) then
               return;
            end if;
            New_Input := To_New_Input (Found (1));
            Allocate := To_Allocate (Found (2));
            Enqueue := To_Enqueue (Found (3));
            Start := To_Start (Found (4));
            Stop := To_Stop (Found (5));
            Dispose := To_Stop (Found (6));
            Ready := True;
         end;
      end Ensure;

      function Found return Boolean is (Ready);
   end Library;

   --  The queue's own thread, a buffer full: its bytes into the ring, the
   --  buffer back to the queue. Nothing of the Ada run time is touched.
   procedure On_Buffer
     (User, Queue, Buffer, Start_Time : System.Address; Packets : Interfaces.Unsigned_32;
      Descriptions : System.Address)
     with Convention => C;

   procedure On_Buffer
     (User, Queue, Buffer, Start_Time : System.Address; Packets : Interfaces.Unsigned_32;
      Descriptions : System.Address)
   is
      pragma Unreferenced (Start_Time, Packets, Descriptions);
      Held : constant State_Access := To_State (User);
      Data : System.Address
        with Import, Address => SE.To_Address (SE.To_Integer (Buffer) + 8);
      Size : Interfaces.Unsigned_32
        with Import, Address => SE.To_Address (SE.To_Integer (Buffer) + 16);
      Count : constant Natural := Natural'Min (Natural (Size), Ring_Bytes);
      Bytes : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Count))
        with Import, Address => Data;
      At_Byte : Interfaces.Unsigned_64 := Held.Written;
      Ignored : Interfaces.Integer_32;
   begin
      for B of Bytes loop
         Held.Ring (Natural (At_Byte mod Ring_Bytes)) := B;
         At_Byte := At_Byte + 1;
      end loop;
      Held.Written := At_Byte;
      Ignored := Enqueue (Queue, Buffer, 0, System.Null_Address);
   end On_Buffer;

   function Is_Supported return Boolean is
   begin
      Library.Ensure;
      return Library.Found;
   end Is_Supported;

   function Source_Present (Name : String) return Source_Answer is
      pragma Unreferenced (Name);
   begin
      return Unknown;
   end Source_Present;

   procedure Open
     (Item   : in out Device;
      Source : String;
      Result : out Outcome;
      Reason : out Unbounded_String)
   is
      Format : aliased constant Stream_Description := (others => <>);
      Held   : State_Access;
      Code   : Interfaces.Integer_32;
   begin
      Close (Item);
      Result := Done;
      Reason := Null_Unbounded_String;
      if not Is_Supported then
         Result := Unsupported;
         Reason := To_Unbounded_String ("AudioToolbox could not be opened");
         return;
      end if;
      if Source /= "" then
         Result := Refused;
         Reason := To_Unbounded_String ("only the default input is recorded on macOS, not " & Source);
         return;
      end if;
      Held := new State;
      Code := New_Input (Format'Access, On_Buffer'Access, Held.all'Address, System.Null_Address,
                         System.Null_Address, 0, Held.Queue'Access);
      if Code /= 0 then
         Free (Held);
         Result := Refused;
         Reason := To_Unbounded_String ("AudioQueueNewInput refused, status" & Code'Image);
         return;
      end if;
      for I in Held.Held'Range loop
         declare
            Buffer : aliased System.Address := System.Null_Address;
         begin
            Code := Allocate (Held.Queue, Chunk_Bytes, Buffer'Access);
            if Code = 0 then
               Held.Held (I) := Buffer;
               Code := Enqueue (Held.Queue, Buffer, 0, System.Null_Address);
            end if;
         end;
         exit when Code /= 0;
      end loop;
      if Code = 0 then
         Code := Start (Held.Queue, System.Null_Address);
      end if;
      Item.Stream := Held.all'Address;
      if Code /= 0 then
         Close (Item);
         Result := Refused;
         Reason := To_Unbounded_String ("the recording would not start, status" & Code'Image);
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
      while Held.Written - Held.Read_So_Far < Chunk_Bytes loop
         delay 0.005;
         Waits := Waits + 1;
         if Waits > 600 then
            Result := Failed;
            Reason := To_Unbounded_String ("no sound came for three seconds; is the microphone allowed?");
            return;
         end if;
      end loop;
      --  Behind by more than the ring: the oldest is gone; read from what
      --  is left.
      if Held.Written - Held.Read_So_Far > Ring_Bytes then
         Held.Read_So_Far := Held.Written - Chunk_Bytes;
      end if;
      declare
         From : Interfaces.Unsigned_64 := Held.Read_So_Far;
      begin
         for I in Into'Range loop
            Into (I) := Held.Ring (Natural (From mod Ring_Bytes));
            From := From + 1;
         end loop;
         Held.Read_So_Far := From;
      end;
   end Read;

   procedure Close (Item : in out Device) is
      Held    : State_Access := To_State (Item.Stream);
      Ignored : Interfaces.Integer_32;
   begin
      if Held = null then
         return;
      end if;
      if Held.Queue /= System.Null_Address then
         Ignored := Stop (Held.Queue, 1);
         Ignored := Dispose (Held.Queue, 1);
      end if;
      Free (Held);
      Item.Stream := System.Null_Address;
   end Close;

   function Is_Open (Item : Device) return Boolean is (Item.Stream /= System.Null_Address);

end Hostkit.Microphone;
