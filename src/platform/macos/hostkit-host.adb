with Interfaces.C;
with System;

package body Hostkit.Host is
   use type System.Address;

   type CF_Index is new Interfaces.C.long;
   type CF_String_Encoding is new Interfaces.C.unsigned;

   CF_String_Encoding_UTF8 : constant CF_String_Encoding := 16#0800_0100#;

   function CFLocaleCopyCurrent return System.Address
     with Import, Convention => C, External_Name => "CFLocaleCopyCurrent";

   function CFLocaleGetIdentifier
     (Locale : System.Address)
      return System.Address
     with Import, Convention => C, External_Name => "CFLocaleGetIdentifier";

   function CFStringGetCString
     (Text      : System.Address;
      Buffer    : System.Address;
      Buffer_Len : CF_Index;
      Encoding  : CF_String_Encoding)
      return Interfaces.C.int
     with Import, Convention => C, External_Name => "CFStringGetCString";

   procedure CFRelease
     (Object : System.Address)
     with Import, Convention => C, External_Name => "CFRelease";


   function Current return Kind is
   begin
      return MacOS;
   end Current;

   --  Effective, not real: a program run through sudo has the privileges of the
   --  effective id, and the real one still says who invoked it.
   function Is_Elevated return Boolean is
      use type Interfaces.C.unsigned;

      function Geteuid return Interfaces.C.unsigned
        with Import => True, Convention => C, External_Name => "geteuid";
   begin
      return Geteuid = 0;
   end Is_Elevated;

   function Native_Locale return String is
      Locale : System.Address := CFLocaleCopyCurrent;
      Buffer : aliased Interfaces.C.char_array (1 .. 128) := [others => Interfaces.C.nul];
      Success : Interfaces.C.int := 0;
   begin
      if Locale = System.Null_Address then
         return "";
      end if;

      declare
         Identifier : constant System.Address := CFLocaleGetIdentifier (Locale);
      begin
         if Identifier /= System.Null_Address then
            Success :=
              CFStringGetCString
                (Identifier,
                 Buffer'Address,
                 CF_Index (Buffer'Length),
                 CF_String_Encoding_UTF8);
         end if;
      end;

      CFRelease (Locale);
      --  Null the handle so the exception handler below cannot release it a
      --  second time if anything after this point (e.g. To_Ada) raises.
      Locale := System.Null_Address;

      if Success = 0 then
         return "";
      end if;

      return Interfaces.C.To_Ada (Buffer);
   exception
      when others =>
         if Locale /= System.Null_Address then
            CFRelease (Locale);
         end if;

         return "";
   end Native_Locale;

end Hostkit.Host;
