with Ada.Strings.UTF_Encoding.Wide_Strings;

with Interfaces.C;

with System.Storage_Elements;
with System;

package body Hostkit.Local_Channel is

   use type Interfaces.C.int;
   use type Interfaces.C.unsigned_long;
   use type System.Storage_Elements.Integer_Address;

   subtype C_DWord is Interfaces.C.unsigned_long;

   Generic_Read       : constant C_DWord := 16#8000_0000#;
   Generic_Write      : constant C_DWord := 16#4000_0000#;
   Open_Existing      : constant C_DWord := 3;
   Invalid_Handle_Int : constant System.Storage_Elements.Integer_Address :=
     System.Storage_Elements.Integer_Address'Last;  --  (HANDLE) -1

   function Create_File
     (Name       : System.Address;
      Access_Way : C_DWord;
      Share      : C_DWord;
      Security   : System.Address;
      Creation   : C_DWord;
      Attributes : C_DWord;
      Template   : System.Address)
      return System.Address
     with Import => True, Convention => Stdcall, External_Name => "CreateFileW";

   function Write_File
     (Handle       : System.Address;
      Buffer       : System.Address;
      To_Write     : C_DWord;
      Written      : access C_DWord;
      Overlapped   : System.Address)
      return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "WriteFile";

   function Read_File
     (Handle     : System.Address;
      Buffer     : System.Address;
      To_Read    : C_DWord;
      Read       : access C_DWord;
      Overlapped : System.Address)
      return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "ReadFile";

   function Close_Handle (Handle : System.Address) return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "CloseHandle";

   function Wait_Named_Pipe
     (Name    : System.Address;
      Timeout : C_DWord)
      return Interfaces.C.int
     with Import => True, Convention => Stdcall, External_Name => "WaitNamedPipeW";

   function Wide (Value : String) return Wide_String is
     (Ada.Strings.UTF_Encoding.Wide_Strings.Decode (Value) & Wide_Character'Val (0));

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
           Attributes => 0,
           Template   => System.Null_Address);

      --  Busy is the pipe's normal "all instances taken" state, not a failure. Wait briefly
      --  for a free instance and try once more before giving up.
      if System.Storage_Elements.To_Integer (Handle) = Invalid_Handle_Int then
         Ignored := Wait_Named_Pipe (Wide_Path'Address, 2000);
         Handle :=
           Create_File
             (Name       => Wide_Path'Address,
              Access_Way => Generic_Read or Generic_Write,
              Share      => 0,
              Security   => System.Null_Address,
              Creation   => Open_Existing,
              Attributes => 0,
              Template   => System.Null_Address);
      end if;

      if System.Storage_Elements.To_Integer (Handle) = Invalid_Handle_Int then
         return False;
      end if;

      Item.Open := True;
      Item.Native := Long_Integer (System.Storage_Elements.To_Integer (Handle));
      return True;
   exception
      when others =>
         return False;
   end Connect;

   function Is_Open (Item : Channel) return Boolean is
   begin
      return Item.Open;
   end Is_Open;

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
