with Ada.Streams;
with Ada.Strings.Unbounded;
with System;

--  Recording from the host's default microphone (or a named one), as one
--  channel of signed 16-bit little-endian samples at a fixed rate.
--
--  Why this is here: how a program records differs entirely by host. Linux
--  records through its sound server -- PipeWire or PulseAudio, which both
--  speak PulseAudio's protocol -- macOS through Core Audio, Windows through
--  WASAPI. The caller wants the same thing from all of them: a stream of
--  samples at the rate it names, the server converting whatever the device
--  records, and a refusal it can show when there is no microphone.
--
--  What each host does:
--
--  * Linux: PulseAudio's "simple" library (libpulse-simple.so.0), opened by
--    name at the first Open, never linked -- a host without it runs
--    everything else and refuses here with Unsupported. pipewire-pulse
--    answers the same calls. The stream is asked to deliver a tenth of a
--    second at a time, so a Read returns that often. PipeWire's pulse
--    server records the default source where it is asked for one it does
--    not have, so a source named is looked for first, through libpulse's
--    introspection, and Open refuses one the server does not have -- and
--    one it cannot tell about.
--  * Windows: winmm's waveIn, through the wave mapper or the input device
--    whose name a source gives; four buffers of a tenth of a second.
--  * macOS: AudioToolbox's input queue on the default input, the framework
--    opened by name; a source named is refused, naming one not being done
--    there, and a machine where the user has not allowed the microphone
--    delivers nothing, which a Read reports after three seconds.
--
--  A Read on every host gives up after three seconds of nothing arriving,
--  answering Failed rather than waiting for ever.
--
--  Nothing recorded is written anywhere: the samples go to the caller's
--  buffer and nowhere else.
--
--  Task safety: a Device belongs to one task. Finding the library is done
--  once, under a lock.
package Hostkit.Microphone is

   --  The rate a stream records at, and its channels.
   Rate     : constant := 16_000;
   Channels : constant := 1;

   --  Bytes one Read fills: a tenth of a second.
   Chunk_Bytes : constant := Rate / 10 * 2;

   --  What an Open or a Read came to.
   type Outcome is
     (Done,
      --  This host, or this build on it, cannot record: the library is not
      --  there, or the host is one not yet done.
      Unsupported,
      --  The sound server answered no: no such source, no server, no
      --  permission. Reason says what it said.
      Refused,
      --  A read failed part way: the device unplugged, the server gone.
      Failed);

   --  Report whether this host can record at all: the library found.
   --
   --  @return True when an Open can succeed.
   function Is_Supported return Boolean;

   --  Whether the sound server has a source of a name.
   type Source_Answer is (Present, Absent, Unknown);

   --  Ask the sound server whether it has a source. Unknown where there is
   --  no server, no library, or no answer within two seconds, and on macOS
   --  -- never Present for not knowing.
   --
   --  @param Name The source's name, as the server gives it; "" for the
   --    server's default.
   --  @return What the server said.
   function Source_Present (Name : String) return Source_Answer;

   type Device is limited private;

   --  Open a microphone.
   --
   --  @param Item The device; closed first.
   --  @param Source The server's name for the source, or "" for its default.
   --  @param Result Done, Unsupported or Refused.
   --  @param Reason Why not, in the server's words; empty when Done.
   procedure Open
     (Item   : in out Device;
      Source : String;
      Result : out Outcome;
      Reason : out Ada.Strings.Unbounded.Unbounded_String);

   --  Read a tenth of a second, waiting until it is recorded.
   --
   --  @param Item An open device.
   --  @param Into Receives Chunk_Bytes of samples.
   --  @param Result Done or Failed.
   --  @param Reason Why not; empty when Done.
   procedure Read
     (Item   : in out Device;
      Into   : out Ada.Streams.Stream_Element_Array;
      Result : out Outcome;
      Reason : out Ada.Strings.Unbounded.Unbounded_String)
   with Pre => Into'Length = Chunk_Bytes;

   --  Close the device. Idempotent.
   --
   --  @param Item The device.
   procedure Close (Item : in out Device);

   --  @param Item A device.
   --  @return Whether it is open.
   function Is_Open (Item : Device) return Boolean;

private

   type Device is limited record
      Stream : System.Address := System.Null_Address;
   end record;

end Hostkit.Microphone;
