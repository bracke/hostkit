--  Linux: the microphone through PulseAudio's simple library, opened by name.
--
--  libpulse-simple for pa_simple_new, pa_simple_read and pa_simple_free,
--  and libpulse, which it depends on and so is already loaded once it is,
--  for pa_strerror. PipeWire's pipewire-pulse answers the same protocol, so
--  this is how a PipeWire host records too.
--
--  The structures passed are pa_sample_spec -- an int format, a uint32
--  rate, a uint8 channel count, twelve bytes with its padding -- and
--  pa_buffer_attr, five uint32s, of which only fragsize matters to a
--  recording: the server delivers that many bytes at a time, and a tenth
--  of a second is asked so that a read returns that often. Checked on Linux
--  with PipeWire 1.x's pipewire-pulse.
with Ada.Unchecked_Conversion;
with Interfaces;
with Interfaces.C.Strings;

package body Hostkit.Microphone is

   package C renames Interfaces.C;
   use Ada.Strings.Unbounded;

   use type System.Address;
   use type C.int;

   RTLD_NOW    : constant C.int := 2;
   RTLD_GLOBAL : constant C.int := 16#100#;

   function dlopen (Name : C.Strings.chars_ptr; Flags : C.int) return System.Address
     with Import, Convention => C, External_Name => "dlopen";

   function dlsym (Handle : System.Address; Name : C.Strings.chars_ptr) return System.Address
     with Import, Convention => C, External_Name => "dlsym";

   --  PA_STREAM_RECORD and PA_SAMPLE_S16LE.
   Record_Direction : constant C.int := 2;
   Signed_16_Little : constant C.int := 3;

   type Sample_Spec is record
      Format   : C.int;
      Rate     : Interfaces.Unsigned_32;
      Channels : Interfaces.Unsigned_8;
   end record
     with Convention => C;

   type Buffer_Attributes is record
      Max_Length, Target_Length, Pre_Buffer, Min_Request, Fragment : Interfaces.Unsigned_32;
   end record
     with Convention => C;

   type New_Function is access function
     (Server      : C.Strings.chars_ptr;
      Name        : C.Strings.chars_ptr;
      Direction   : C.int;
      Device_Name : C.Strings.chars_ptr;
      Stream_Name : C.Strings.chars_ptr;
      Spec        : access constant Sample_Spec;
      Map         : System.Address;
      Attributes  : access constant Buffer_Attributes;
      Error       : access C.int) return System.Address
     with Convention => C;

   type Read_Function is access function
     (Stream : System.Address;
      Data   : System.Address;
      Bytes  : C.size_t;
      Error  : access C.int) return C.int
     with Convention => C;

   type Free_Function is access procedure (Stream : System.Address)
     with Convention => C;

   type Error_Text_Function is access function (Error : C.int) return C.Strings.chars_ptr
     with Convention => C;

   function To_New is new Ada.Unchecked_Conversion (System.Address, New_Function);
   function To_Read is new Ada.Unchecked_Conversion (System.Address, Read_Function);
   function To_Free is new Ada.Unchecked_Conversion (System.Address, Free_Function);
   function To_Error_Text is new Ada.Unchecked_Conversion (System.Address, Error_Text_Function);

   --  The library's calls, found once.
   protected Library is
      procedure Ensure;
      function Found return Boolean;
   private
      Tried : Boolean := False;
      Ready : Boolean := False;
   end Library;

   Simple_New : New_Function;
   Simple_Read : Read_Function;
   Simple_Free : Free_Function;
   Error_Text : Error_Text_Function;

   protected body Library is
      procedure Ensure is
         function Symbol (Handle : System.Address; Name : String) return System.Address is
            Text   : C.Strings.chars_ptr := C.Strings.New_String (Name);
            Result : constant System.Address := dlsym (Handle, Text);
         begin
            C.Strings.Free (Text);
            return Result;
         end Symbol;

         function Load (Name : String) return System.Address is
            Text   : C.Strings.chars_ptr := C.Strings.New_String (Name);
            Result : constant System.Address := dlopen (Text, RTLD_NOW + RTLD_GLOBAL);
         begin
            C.Strings.Free (Text);
            return Result;
         end Load;

         Simple, Pulse : System.Address;
      begin
         if Tried then
            return;
         end if;
         Tried := True;
         Simple := Load ("libpulse-simple.so.0");
         Pulse := Load ("libpulse.so.0");
         if Simple = System.Null_Address or else Pulse = System.Null_Address then
            return;
         end if;
         declare
            New_At   : constant System.Address := Symbol (Simple, "pa_simple_new");
            Read_At  : constant System.Address := Symbol (Simple, "pa_simple_read");
            Free_At  : constant System.Address := Symbol (Simple, "pa_simple_free");
            Error_At : constant System.Address := Symbol (Pulse, "pa_strerror");
         begin
            if New_At = System.Null_Address or else Read_At = System.Null_Address
              or else Free_At = System.Null_Address or else Error_At = System.Null_Address
            then
               return;
            end if;
            Simple_New := To_New (New_At);
            Simple_Read := To_Read (Read_At);
            Simple_Free := To_Free (Free_At);
            Error_Text := To_Error_Text (Error_At);
            Ready := True;
         end;
      end Ensure;

      function Found return Boolean is (Ready);
   end Library;

   function Is_Supported return Boolean is
   begin
      Library.Ensure;
      return Library.Found;
   end Is_Supported;

   function Server_Reason (Code : C.int) return String is
      Text : constant C.Strings.chars_ptr := Error_Text (Code);
   begin
      return (if C.Strings."=" (Text, C.Strings.Null_Ptr) then "error" & Code'Image else C.Strings.Value (Text));
   end Server_Reason;

   procedure Open
     (Item   : in out Device;
      Source : String;
      Result : out Outcome;
      Reason : out Unbounded_String)
   is
      Spec       : aliased constant Sample_Spec := (Signed_16_Little, Rate, Channels);
      Attributes : aliased constant Buffer_Attributes :=
        (Max_Length => Interfaces.Unsigned_32'Last, Target_Length => Interfaces.Unsigned_32'Last,
         Pre_Buffer => Interfaces.Unsigned_32'Last, Min_Request => Interfaces.Unsigned_32'Last,
         Fragment => Chunk_Bytes);
      Error      : aliased C.int := 0;
      Name       : C.Strings.chars_ptr := C.Strings.New_String ("model_runner");
      Stream     : C.Strings.chars_ptr := C.Strings.New_String ("speech input");
      Device_Name : C.Strings.chars_ptr :=
        (if Source = "" then C.Strings.Null_Ptr else C.Strings.New_String (Source));
   begin
      Close (Item);
      Result := Done;
      Reason := Null_Unbounded_String;
      if not Is_Supported then
         Result := Unsupported;
         Reason := To_Unbounded_String ("libpulse-simple is not installed");
      else
         Item.Stream := Simple_New
           (C.Strings.Null_Ptr, Name, Record_Direction, Device_Name, Stream, Spec'Access, System.Null_Address,
            Attributes'Access, Error'Access);
         if Item.Stream = System.Null_Address then
            Result := Refused;
            Reason := To_Unbounded_String (Server_Reason (Error));
         end if;
      end if;
      C.Strings.Free (Name);
      C.Strings.Free (Stream);
      C.Strings.Free (Device_Name);
   end Open;

   procedure Read
     (Item   : in out Device;
      Into   : out Ada.Streams.Stream_Element_Array;
      Result : out Outcome;
      Reason : out Unbounded_String)
   is
      Error : aliased C.int := 0;
   begin
      Result := Done;
      Reason := Null_Unbounded_String;
      if Item.Stream = System.Null_Address then
         Into := [others => 0];
         Result := Failed;
         Reason := To_Unbounded_String ("not open");
         return;
      end if;
      if Simple_Read (Item.Stream, Into'Address, C.size_t (Into'Length), Error'Access) < 0 then
         Result := Failed;
         Reason := To_Unbounded_String (Server_Reason (Error));
      end if;
   end Read;

   procedure Close (Item : in out Device) is
   begin
      if Item.Stream /= System.Null_Address then
         Simple_Free (Item.Stream);
         Item.Stream := System.Null_Address;
      end if;
   end Close;

   function Is_Open (Item : Device) return Boolean is (Item.Stream /= System.Null_Address);

end Hostkit.Microphone;
