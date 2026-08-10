package body Hostkit.Descriptors is

   use type Ada.Streams.Stream_Element_Offset;

   --  A host this build does not know. Every answer here is a refusal, and a
   --  deliberate one: "cannot tell" is not "fine". A consumer that stored one
   --  of these as success would rebuild, on its own side, the bug this crate
   --  exists to prevent.

   function Is_Valid (Item : Descriptor) return Boolean is
   begin
      return Item /= Invalid;
   end Is_Valid;

   function Create_Pipe (Ends : out Pipe_Ends) return Boolean is
   begin
      Ends := (Read_End => Invalid, Write_End => Invalid);
      return False;
   end Create_Pipe;

   procedure Close (Item : in out Descriptor) is
   begin
      Item := Invalid;
   end Close;

   function Duplicate (Item : Descriptor) return Descriptor is
      pragma Unreferenced (Item);
   begin
      return Invalid;
   end Duplicate;

   function Set_Inheritable (Item : Descriptor; Inheritable : Boolean) return Boolean is
      pragma Unreferenced (Item, Inheritable);
   begin
      return False;
   end Set_Inheritable;

   function Set_Non_Blocking (Item : Descriptor; Non_Blocking : Boolean) return Boolean is
      pragma Unreferenced (Item, Non_Blocking);
   begin
      return False;
   end Set_Non_Blocking;

   function Read
     (Item : Descriptor;
      Into : out Ada.Streams.Stream_Element_Array;
      Last : out Ada.Streams.Stream_Element_Offset) return Transfer_Outcome
   is
      pragma Unreferenced (Item);
   begin
      Into := [others => 0];
      Last := Into'First - 1;
      return Transfer_Error;
   end Read;

   function Write
     (Item : Descriptor;
      From : Ada.Streams.Stream_Element_Array;
      Last : out Ada.Streams.Stream_Element_Offset) return Transfer_Outcome
   is
      pragma Unreferenced (Item);
   begin
      Last := From'First - 1;
      return Transfer_Error;
   end Write;

   --  The three standard streams are the one thing that is answerable: every
   --  host this could be has them, and their numbers are the POSIX ones
   --  wherever the question means anything at all.
   function Standard_Input return Descriptor is
   begin
      return Descriptor (0);
   end Standard_Input;

   function Standard_Output return Descriptor is
   begin
      return Descriptor (1);
   end Standard_Output;

   function Standard_Error return Descriptor is
   begin
      return Descriptor (2);
   end Standard_Error;

   function Open_File
     (Path : String;
      Mode : Open_Mode;
      Item : out Descriptor) return Boolean
   is
      pragma Unreferenced (Path, Mode);
   begin
      Item := Invalid;
      return False;
   end Open_File;

   function Is_Terminal (Item : Descriptor) return Boolean is
      pragma Unreferenced (Item);
   begin
      --  False because this host cannot be asked, not because the answer is no.
      return False;
   end Is_Terminal;

   function Assign (Item : Descriptor; To : Standard_Stream) return Boolean is
      pragma Unreferenced (Item, To);
   begin
      return False;
   end Assign;

   function Native_Value (Item : Descriptor) return Long_Long_Integer is
   begin
      return Long_Long_Integer (Item);
   end Native_Value;

   function From_Native_Value (Value : Long_Long_Integer) return Descriptor is
   begin
      if Value < 0 then
         return Invalid;
      end if;

      return Descriptor (Value);
   end From_Native_Value;

end Hostkit.Descriptors;
