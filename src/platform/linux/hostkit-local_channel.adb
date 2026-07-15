with Interfaces.C;


with System;

package body Hostkit.Local_Channel is

   use type Interfaces.C.int;
   use type Interfaces.C.long;

   subtype C_Int is Interfaces.C.int;

   AF_UNIX     : constant C_Int := 1;
   SOCK_STREAM : constant C_Int := 1;

   --  struct sockaddr_un: a 2-byte family, then a 108-byte path. connect() reads the family
   --  and the NUL-terminated path out of it. Laid out by hand so no C header is needed.
   type Sockaddr_Un is record
      Family : Interfaces.C.short := 0;
      Path   : Interfaces.C.char_array (0 .. 107) := [others => Interfaces.C.nul];
   end record
     with Convention => C;

   function C_Socket (Domain, Kind, Protocol : C_Int) return C_Int
     with Import => True, Convention => C, External_Name => "socket";

   function C_Connect (FD : C_Int; Addr : System.Address; Len : C_Int) return C_Int
     with Import => True, Convention => C, External_Name => "connect";

   function C_Send (FD : C_Int; Buf : System.Address; Len : Interfaces.C.size_t; Flags : C_Int)
     return Interfaces.C.long
     with Import => True, Convention => C, External_Name => "send";

   function C_Recv (FD : C_Int; Buf : System.Address; Len : Interfaces.C.size_t; Flags : C_Int)
     return Interfaces.C.long
     with Import => True, Convention => C, External_Name => "recv";

   function C_Close (FD : C_Int) return C_Int
     with Import => True, Convention => C, External_Name => "close";

   function Connect (Path : String; Item : out Channel) return Boolean is
      FD   : C_Int;
      Addr : aliased Sockaddr_Un;
   begin
      Item.Open := False;
      Item.Native := Invalid;

      --  108 bytes minus the terminating NUL. A path longer than the struct can hold cannot
      --  be reached at all -- do not truncate it into connecting to the wrong endpoint.
      if Path'Length = 0 or else Path'Length > 107 then
         return False;
      end if;

      FD := C_Socket (AF_UNIX, SOCK_STREAM, 0);
      if FD < 0 then
         return False;
      end if;

      Addr.Family := Interfaces.C.short (AF_UNIX);
      for I in Path'Range loop
         Addr.Path (Interfaces.C.size_t (I - Path'First)) := Interfaces.C.To_C (Path (I));
      end loop;

      if C_Connect (FD, Addr'Address, Sockaddr_Un'Size / 8) /= 0 then
         declare
            Ignored : constant C_Int := C_Close (FD);
         begin
            pragma Unreferenced (Ignored);
            return False;
         end;
      end if;

      Item.Open := True;
      Item.Native := Long_Integer (FD);
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
      FD   : constant C_Int := C_Int (Item.Native);
      From : Ada.Streams.Stream_Element_Offset := Data'First;
      Sent : Interfaces.C.long;
   begin
      if not Item.Open then
         return False;
      end if;

      while From <= Data'Last loop
         Sent := C_Send (FD, Data (From)'Address,
                         Interfaces.C.size_t (Data'Last - From + 1), 0);
         if Sent <= 0 then
            return False;
         end if;
         From := From + Ada.Streams.Stream_Element_Offset (Sent);
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
      FD   : constant C_Int := C_Int (Item.Native);
      Into : Ada.Streams.Stream_Element_Offset := Data'First;
      Got  : Interfaces.C.long;
   begin
      Data := [Data'Range => 0];

      if not Item.Open then
         return False;
      end if;

      while Into <= Data'Last loop
         Got := C_Recv (FD, Data (Into)'Address,
                        Interfaces.C.size_t (Data'Last - Into + 1), 0);
         --  0 is the peer closing; anything read short of the whole is a broken channel.
         if Got <= 0 then
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
   begin
      if Item.Open then
         declare
            Ignored : constant C_Int := C_Close (C_Int (Item.Native));
         begin
            pragma Unreferenced (Ignored);
            null;
         end;
      end if;
      Item.Open := False;
      Item.Native := Invalid;
   exception
      when others =>
         Item.Open := False;
      Item.Native := Invalid;
   end Close;

end Hostkit.Local_Channel;
