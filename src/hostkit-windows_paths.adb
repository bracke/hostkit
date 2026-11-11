with Ada.Strings.UTF_Encoding;
with Ada.Strings.Unbounded;
with Ada.Strings.Wide_Unbounded;

with Hostkit.Fs;
with Hostkit.Path_Text;

package body Hostkit.Windows_Paths is

   function Is_Separator (Item : Character) return Boolean is (Item in '\' | '/');

   function Long_Path_Form (Path : String) return String is
      Text : String := Path;

      function Has_Dot_Component return Boolean is
         Start : Positive := Text'First;
      begin
         for Index in Text'First .. Text'Last + 1 loop
            if Index > Text'Last or else Text (Index) = '\' then
               declare
                  Component : constant String := Text (Start .. Index - 1);
               begin
                  if Component = "." or else Component = ".." then
                     return True;
                  end if;
               end;
               Start := Index + 1;
            end if;
         end loop;
         return False;
      end Has_Dot_Component;
   begin
      if Path'Length < Long_Path_Threshold then
         return Path;
      end if;
      for Item of Text loop
         if Item = '/' then
            Item := '\';
         end if;
      end loop;
      if Text (Text'First .. Text'First + 3) in "\\?\" | "\\.\" then
         return Path;
      elsif Has_Dot_Component then
         return Path;
      elsif Text (Text'First) in 'A' .. 'Z' | 'a' .. 'z'
        and then Text (Text'First + 1) = ':'
        and then Is_Separator (Text (Text'First + 2))
      then
         return "\\?\" & Text;
      elsif Text (Text'First .. Text'First + 1) = "\\" and then not Is_Separator (Text (Text'First + 2)) then
         return "\\?\UNC\" & Text (Text'First + 2 .. Text'Last);
      else
         return Path;
      end if;
   end Long_Path_Form;

   function Is_Prefixed (Path : String) return Boolean is
     (Path'Length >= 4
      and then Is_Separator (Path (Path'First))
      and then Is_Separator (Path (Path'First + 1))
      and then Path (Path'First + 2) in '?' | '.'
      and then Is_Separator (Path (Path'First + 3)));

   function Native_Form (Path : String; Base : String) return String is
      Form : constant String := Long_Path_Form (Path);
   begin
      if Path'Length < Long_Path_Threshold or else Form /= Path or else Is_Prefixed (Path) then
         return Form;
      end if;
      --  Long, yet left unprefixed: relative, or with a dot component, or
      --  in no form the prefix applies to.
      declare
         Full : constant String := Hostkit.Path_Text.Absolute (Path, Base);
      begin
         return (if Full = "" or else Full = "." then Form else Long_Path_Form (Full));
      end;
   end Native_Form;

   function Native (Path : String) return Wide_String is
     (From_UTF_8
        (if Path'Length < Long_Path_Threshold then Path
         else Native_Form (Path, Hostkit.Fs.Current_Directory))
      & Wide_Character'Val (0));

   function To_UTF_8 (Units : Wide_String) return String is
      use Ada.Strings.Unbounded;
      Result : Unbounded_String;
      Index  : Natural := Units'First;

      procedure Put (Code : Natural) is
      begin
         Append (Result, Character'Val (Code));
      end Put;

      procedure Encode (Code : Natural) is
      begin
         if Code < 16#80# then
            Put (Code);
         elsif Code < 16#800# then
            Put (16#C0# + Code / 16#40#);
            Put (16#80# + Code mod 16#40#);
         elsif Code < 16#1_0000# then
            Put (16#E0# + Code / 16#1000#);
            Put (16#80# + (Code / 16#40#) mod 16#40#);
            Put (16#80# + Code mod 16#40#);
         else
            Put (16#F0# + Code / 16#4_0000#);
            Put (16#80# + (Code / 16#1000#) mod 16#40#);
            Put (16#80# + (Code / 16#40#) mod 16#40#);
            Put (16#80# + Code mod 16#40#);
         end if;
      end Encode;
   begin
      while Index <= Units'Last loop
         declare
            Unit : constant Natural := Wide_Character'Pos (Units (Index));
         begin
            if Unit in 16#D800# .. 16#DBFF#
              and then Index < Units'Last
              and then Wide_Character'Pos (Units (Index + 1)) in 16#DC00# .. 16#DFFF#
            then
               Encode
                 (16#1_0000# + (Unit - 16#D800#) * 16#400#
                  + (Wide_Character'Pos (Units (Index + 1)) - 16#DC00#));
               Index := Index + 2;
            else
               --  A lone surrogate, high or low, takes its own code point's
               --  three bytes.
               Encode (Unit);
               Index := Index + 1;
            end if;
         end;
      end loop;
      return To_String (Result);
   end To_UTF_8;

   function From_UTF_8 (Text : String) return Wide_String is
      use Ada.Strings.Wide_Unbounded;
      Result : Unbounded_Wide_String;
      Index  : Natural := Text'First;

      function Byte (At_Index : Positive) return Natural is (Character'Pos (Text (At_Index)));

      --  The continuation byte at At_Index's six bits, when it is one in
      --  Low .. High.
      function Continuation (At_Index : Positive; Low : Natural := 16#80#; High : Natural := 16#BF#) return Natural is
      begin
         if At_Index > Text'Last or else Byte (At_Index) not in Low .. High then
            raise Ada.Strings.UTF_Encoding.Encoding_Error
              with "not UTF-8 at byte" & Natural'Image (At_Index - Text'First + 1);
         end if;
         return Byte (At_Index) - 16#80#;
      end Continuation;

      procedure Add (Code : Natural) is
      begin
         if Code < 16#1_0000# then
            Append (Result, Wide_Character'Val (Code));
         else
            Append (Result, Wide_Character'Val (16#D800# + (Code - 16#1_0000#) / 16#400#));
            Append (Result, Wide_Character'Val (16#DC00# + (Code - 16#1_0000#) mod 16#400#));
         end if;
      end Add;
   begin
      while Index <= Text'Last loop
         declare
            Lead : constant Natural := Byte (Index);
         begin
            case Lead is
               when 16#00# .. 16#7F# =>
                  Add (Lead);
                  Index := Index + 1;
               when 16#C2# .. 16#DF# =>
                  Add ((Lead - 16#C0#) * 16#40# + Continuation (Index + 1));
                  Index := Index + 2;
               when 16#E0# .. 16#EF# =>
                  --  E0 needs A0 and up, or it is overlong; ED's A0 .. BF are
                  --  the surrogates, kept here as WTF-8 keeps them.
                  declare
                     Second : constant Natural :=
                       Continuation (Index + 1, Low => (if Lead = 16#E0# then 16#A0# else 16#80#));
                  begin
                     Add ((Lead - 16#E0#) * 16#1000# + Second * 16#40# + Continuation (Index + 2));
                  end;
                  Index := Index + 3;
               when 16#F0# .. 16#F4# =>
                  --  F0 needs 90 and up, or it is overlong; F4 stops at 8F,
                  --  or it passes U+10FFFF.
                  declare
                     Second : constant Natural :=
                       Continuation
                         (Index + 1,
                          Low  => (if Lead = 16#F0# then 16#90# else 16#80#),
                          High => (if Lead = 16#F4# then 16#8F# else 16#BF#));
                  begin
                     Add
                       ((Lead - 16#F0#) * 16#4_0000# + Second * 16#1000#
                        + Continuation (Index + 2) * 16#40# + Continuation (Index + 3));
                  end;
                  Index := Index + 4;
               when others =>
                  raise Ada.Strings.UTF_Encoding.Encoding_Error
                    with "not UTF-8 at byte" & Natural'Image (Index - Text'First + 1);
            end case;
         end;
      end loop;
      return To_Wide_String (Result);
   end From_UTF_8;

end Hostkit.Windows_Paths;
