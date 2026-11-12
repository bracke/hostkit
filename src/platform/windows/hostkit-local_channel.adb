with Hostkit.Win32;
with Hostkit.Windows_Paths;

with Interfaces.C;

with System.Storage_Elements;
with System;

package body Hostkit.Local_Channel is

   use Hostkit.Win32;
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned_long;
   use type System.Address;

   subtype C_DWord is Interfaces.C.unsigned_long;

   function Wait_Named_Pipe
     (Name    : System.Address;
      Timeout : C_DWord)
      return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "WaitNamedPipeW";

   function Wide (Value : String) return Wide_String is
     (Hostkit.Windows_Paths.From_UTF_8 (Value) & Wide_Character'Val (0));

   function To_Handle (Item : Channel) return System.Address is
     (System.Storage_Elements.To_Address
        (System.Storage_Elements.Integer_Address (Item.Native)));

   function Connect (Path : String; Item : out Channel) return Boolean is
      Wide_Path : aliased Wide_String := Wide (Path);
      Handle    : System.Address;
      Ignored   : Interfaces.C.int;
   begin
      Item.Open := False;
      Item.Native := Invalid;

      if Path = "" then
         return False;
      end if;

      Handle :=
        Create_File
          (Name       => Wide_Path'Address,
           Access_Way => Generic_Read or Generic_Write,
           Share      => 0,
           Security   => System.Null_Address,
           Creation   => Open_Existing,
           Flags      => 0,
           Template   => System.Null_Address);

      --  Busy is the pipe's normal "all instances taken" state, not a failure. Wait briefly
      --  for a free instance and try once more before giving up.
      if Handle = Invalid_Handle_Value then
         Ignored := Wait_Named_Pipe (Wide_Path'Address, 2000);
         Handle :=
           Create_File
             (Name       => Wide_Path'Address,
              Access_Way => Generic_Read or Generic_Write,
              Share      => 0,
              Security   => System.Null_Address,
              Creation   => Open_Existing,
              Flags      => 0,
              Template   => System.Null_Address);
      end if;

      if Handle = Invalid_Handle_Value then
         return False;
      end if;

      Item.Open := True;
      Item.Native := Long_Integer (System.Storage_Elements.To_Integer (Handle));
      return True;
   exception
      when others =>
         return False;
   end Connect;

   function Connect_Abstract (Name : String; Item : out Channel) return Boolean is
      pragma Unreferenced (Name);
   begin
      Item.Open := False;
      Item.Native := Invalid;
      return False;
   end Connect_Abstract;

   function Is_Open (Item : Channel) return Boolean is
   begin
      return Item.Open;
   end Is_Open;

   function Wait_Readable
     (Item       : Channel;
      Timeout_MS : Integer)
      return Hostkit.Process.Wait_Outcome
   is
      Available : aliased C_DWord := 0;
      Waited    : Integer := 0;
      Slice     : constant Integer := 10;
   begin
      if not Item.Open then
         return Hostkit.Process.Wait_Error;
      end if;

      loop
         Available := 0;
         if Peek_Named_Pipe
              (To_Handle (Item), System.Null_Address, 0, null,
               Available'Access, null) = 0
         then
            return Hostkit.Process.Wait_Ready;
         end if;

         if Available > 0 then
            return Hostkit.Process.Wait_Ready;
         end if;

         exit when Timeout_MS >= 0 and then Waited >= Timeout_MS;
         Sleep (C_DWord (Slice));
         Waited := Waited + Slice;
      end loop;

      return Hostkit.Process.Wait_Timed_Out;
   exception
      when others =>
         return Hostkit.Process.Wait_Error;
   end Wait_Readable;

   function Wait_Writable
     (Item       : Channel;
      Timeout_MS : Integer)
      return Hostkit.Process.Wait_Outcome
   is
      pragma Unreferenced (Timeout_MS);
   begin
      if Item.Open then
         return Hostkit.Process.Wait_Ready;
      else
         return Hostkit.Process.Wait_Error;
      end if;
   exception
      when others =>
         return Hostkit.Process.Wait_Error;
   end Wait_Writable;

   function Send
     (Item : in out Channel;
      Data : Ada.Streams.Stream_Element_Array)
      return Boolean
   is
      use type Ada.Streams.Stream_Element_Offset;
      Handle  : constant System.Address := To_Handle (Item);
      From    : Ada.Streams.Stream_Element_Offset := Data'First;
      Written : aliased C_DWord;
   begin
      if not Item.Open then
         return False;
      end if;

      while From <= Data'Last loop
         Written := 0;
         if Write_File (Handle, Data (From)'Address,
                        C_DWord (Data'Last - From + 1), Written'Access,
                        System.Null_Address) = 0
           or else Written = 0
         then
            return False;
         end if;
         From := From + Ada.Streams.Stream_Element_Offset (Written);
      end loop;

      return True;
   exception
      when others =>
         return False;
   end Send;

   function Receive
     (Item : in out Channel;
      Data : out Ada.Streams.Stream_Element_Array)
      return Boolean
   is
      use type Ada.Streams.Stream_Element_Offset;
      Handle : constant System.Address := To_Handle (Item);
      Into   : Ada.Streams.Stream_Element_Offset := Data'First;
      Got    : aliased C_DWord;
   begin
      Data := [Data'Range => 0];

      if not Item.Open then
         return False;
      end if;

      while Into <= Data'Last loop
         Got := 0;
         if Read_File (Handle, Data (Into)'Address,
                       C_DWord (Data'Last - Into + 1), Got'Access,
                       System.Null_Address) = 0
           or else Got = 0
         then
            return False;
         end if;
         Into := Into + Ada.Streams.Stream_Element_Offset (Got);
      end loop;

      return True;
   exception
      when others =>
         return False;
   end Receive;

   function Receive_Some
     (Item : in out Channel;
      Data : out Ada.Streams.Stream_Element_Array)
      return Natural
   is
      Handle : constant System.Address := To_Handle (Item);
      Got    : aliased C_DWord := 0;
   begin
      Data := [Data'Range => 0];

      if not Item.Open or else Data'Length = 0 then
         return 0;
      end if;

      if Read_File (Handle, Data (Data'First)'Address,
                    C_DWord (Data'Length), Got'Access,
                    System.Null_Address) = 0
        or else Got = 0
      then
         return 0;
      end if;

      return Natural (Got);
   exception
      when others =>
         return 0;
   end Receive_Some;

   procedure Close (Item : in out Channel) is
      Ignored : Interfaces.C.int;
   begin
      if Item.Open then
         Ignored := Close_Handle (To_Handle (Item));
      end if;
      Item.Open := False;
      Item.Native := Invalid;
   exception
      when others =>
         Item.Open := False;
         Item.Native := Invalid;
   end Close;

end Hostkit.Local_Channel;
