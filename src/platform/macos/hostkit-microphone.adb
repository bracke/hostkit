--  macOS: not yet recorded. Every Open answers Unsupported -- a refusal,
--  not a guess -- and a Read on a device never opened answers Failed.
package body Hostkit.Microphone is

   use Ada.Strings.Unbounded;

   function Is_Supported return Boolean is (False);

   procedure Open
     (Item   : in out Device;
      Source : String;
      Result : out Outcome;
      Reason : out Unbounded_String)
   is
      pragma Unreferenced (Source);
   begin
      Item.Stream := System.Null_Address;
      Result := Unsupported;
      Reason := To_Unbounded_String ("recording through Core Audio is not done yet");
   end Open;

   procedure Read
     (Item   : in out Device;
      Into   : out Ada.Streams.Stream_Element_Array;
      Result : out Outcome;
      Reason : out Unbounded_String)
   is
      pragma Unreferenced (Item);
   begin
      Into := [others => 0];
      Result := Failed;
      Reason := To_Unbounded_String ("not open");
   end Read;

   procedure Close (Item : in out Device) is
   begin
      Item.Stream := System.Null_Address;
   end Close;

   function Is_Open (Item : Device) return Boolean is (False);

end Hostkit.Microphone;
