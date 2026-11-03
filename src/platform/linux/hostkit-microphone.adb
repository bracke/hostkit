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

   --  libpulse's introspection, for whether a source is there.
   type Mainloop_New_Function is access function return System.Address with Convention => C;
   type Address_Of_Function is access function (Item : System.Address) return System.Address with Convention => C;
   type Context_New_Function is access function
     (Api : System.Address; Name : C.Strings.chars_ptr) return System.Address with Convention => C;
   type Connect_Function is access function
     (Context : System.Address; Server : C.Strings.chars_ptr; Flags : C.int; Spawn : System.Address) return C.int
     with Convention => C;
   type State_Function is access function (Item : System.Address) return C.int with Convention => C;
   type Iterate_Function is access function
     (Loop_Item : System.Address; Block : C.int; Result : System.Address) return C.int with Convention => C;
   type Source_Callback is access procedure
     (Context : System.Address; Info : System.Address; Last : C.int; User : System.Address) with Convention => C;
   type By_Name_Function is access function
     (Context : System.Address; Name : C.Strings.chars_ptr; Callback : Source_Callback; User : System.Address)
      return System.Address with Convention => C;
   type Release_Function is access procedure (Item : System.Address) with Convention => C;

   function To_Mainloop_New is new Ada.Unchecked_Conversion (System.Address, Mainloop_New_Function);
   function To_Address_Of is new Ada.Unchecked_Conversion (System.Address, Address_Of_Function);
   function To_Context_New is new Ada.Unchecked_Conversion (System.Address, Context_New_Function);
   function To_Connect is new Ada.Unchecked_Conversion (System.Address, Connect_Function);
   function To_State is new Ada.Unchecked_Conversion (System.Address, State_Function);
   function To_Iterate is new Ada.Unchecked_Conversion (System.Address, Iterate_Function);
   function To_By_Name is new Ada.Unchecked_Conversion (System.Address, By_Name_Function);
   function To_Release is new Ada.Unchecked_Conversion (System.Address, Release_Function);

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

   Mainloop_New : Mainloop_New_Function;
   Mainloop_Api : Address_Of_Function;
   Mainloop_Iterate : Iterate_Function;
   Mainloop_Free : Release_Function;
   Context_New : Context_New_Function;
   Context_Connect : Connect_Function;
   Context_State : State_Function;
   Context_Disconnect, Context_Release : Release_Function;
   Source_By_Name : By_Name_Function;
   Operation_State : State_Function;
   Operation_Release : Release_Function;
   Introspects : Boolean := False;

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
            declare
               Found : constant array (1 .. 12) of System.Address :=
                 [Symbol (Pulse, "pa_mainloop_new"), Symbol (Pulse, "pa_mainloop_get_api"),
                  Symbol (Pulse, "pa_mainloop_iterate"), Symbol (Pulse, "pa_mainloop_free"),
                  Symbol (Pulse, "pa_context_new"), Symbol (Pulse, "pa_context_connect"),
                  Symbol (Pulse, "pa_context_get_state"), Symbol (Pulse, "pa_context_disconnect"),
                  Symbol (Pulse, "pa_context_unref"), Symbol (Pulse, "pa_context_get_source_info_by_name"),
                  Symbol (Pulse, "pa_operation_get_state"), Symbol (Pulse, "pa_operation_unref")];
            begin
               if (for all A of Found => A /= System.Null_Address) then
                  Mainloop_New := To_Mainloop_New (Found (1));
                  Mainloop_Api := To_Address_Of (Found (2));
                  Mainloop_Iterate := To_Iterate (Found (3));
                  Mainloop_Free := To_Release (Found (4));
                  Context_New := To_Context_New (Found (5));
                  Context_Connect := To_Connect (Found (6));
                  Context_State := To_State (Found (7));
                  Context_Disconnect := To_Release (Found (8));
                  Context_Release := To_Release (Found (9));
                  Source_By_Name := To_By_Name (Found (10));
                  Operation_State := To_State (Found (11));
                  Operation_Release := To_Release (Found (12));
                  Introspects := True;
               end if;
            end;
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

   --  What a lookup by name came to, written by the server's callback.
   type Lookup is record
      Found, Finished : Boolean := False;
   end record
     with Convention => C;

   type Lookup_Access is access all Lookup;
   function To_Lookup is new Ada.Unchecked_Conversion (System.Address, Lookup_Access);

   procedure On_Source (Context : System.Address; Info : System.Address; Last : C.int; User : System.Address)
     with Convention => C;

   procedure On_Source (Context : System.Address; Info : System.Address; Last : C.int; User : System.Address) is
      pragma Unreferenced (Context);
      Answer : constant Lookup_Access := To_Lookup (User);
   begin
      if Last /= 0 then
         Answer.Finished := True;
      elsif Info /= System.Null_Address then
         Answer.Found := True;
      end if;
   end On_Source;

   --  The context's ready, failed and terminated states, and an
   --  operation's running one.
   Context_Ready  : constant C.int := 4;
   Context_Failed : constant C.int := 5;
   Context_Ended  : constant C.int := 6;
   Operation_Running : constant C.int := 0;

   function Source_Present (Name : String) return Source_Answer is
      Answer  : aliased Lookup;
      Main    : System.Address;
      Context : System.Address := System.Null_Address;
      Result  : Source_Answer := Unknown;
      Text    : C.Strings.chars_ptr := C.Strings.New_String ("model_runner");
      --  The default is asked for by the server's own name for it.
      Wanted  : C.Strings.chars_ptr := C.Strings.New_String (if Name = "" then "@DEFAULT_SOURCE@" else Name);
      --  Two seconds of a hundredth each, never waiting on the server.
      Tries   : Natural := 200;
   begin
      Library.Ensure;
      if not Library.Found or else not Introspects then
         C.Strings.Free (Text);
         C.Strings.Free (Wanted);
         return Unknown;
      end if;
      Main := Mainloop_New.all;
      if Main /= System.Null_Address then
         Context := Context_New (Mainloop_Api (Main), Text);
      end if;
      if Context /= System.Null_Address
        and then Context_Connect (Context, C.Strings.Null_Ptr, 0, System.Null_Address) >= 0
      then
         while Tries > 0 and then Context_State (Context) not in Context_Ready | Context_Failed | Context_Ended loop
            if Mainloop_Iterate (Main, 0, System.Null_Address) < 0 then
               exit;
            end if;
            delay 0.01;
            Tries := Tries - 1;
         end loop;
         if Context_State (Context) = Context_Ready then
            declare
               Operation : constant System.Address :=
                 Source_By_Name (Context, Wanted, On_Source'Access, Answer'Address);
            begin
               if Operation /= System.Null_Address then
                  while Tries > 0 and then not Answer.Finished and then not Answer.Found
                    and then Operation_State (Operation) = Operation_Running
                  loop
                     exit when Mainloop_Iterate (Main, 0, System.Null_Address) < 0;
                     delay 0.01;
                     Tries := Tries - 1;
                  end loop;
                  if Answer.Found then
                     Result := Present;
                  elsif Answer.Finished then
                     Result := Absent;
                  end if;
                  Operation_Release (Operation);
               end if;
            end;
         end if;
         Context_Disconnect (Context);
      end if;
      if Context /= System.Null_Address then
         Context_Release (Context);
      end if;
      if Main /= System.Null_Address then
         Mainloop_Free (Main);
      end if;
      C.Strings.Free (Text);
      C.Strings.Free (Wanted);
      return Result;
   end Source_Present;

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
      elsif Source /= "" and then Source_Present (Source) /= Present then
         --  PipeWire would record the default source in its place.
         Result := Refused;
         Reason := To_Unbounded_String
           ((if Source_Present (Source) = Absent then "the sound server has no source "
             else "the sound server could not be asked for source ") & Source);
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
