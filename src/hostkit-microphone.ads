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
--    second at a time, so a Read returns that often. A source named that
--    the server does not have is not refused by PipeWire's pulse server: it
--    records the default source instead, so a caller that must know which
--    source it records asks the server itself.
--  * macOS and Windows: not yet recorded. Open answers Unsupported. That is
--    a refusal, not a guess: nothing here pretends a microphone opened.
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
