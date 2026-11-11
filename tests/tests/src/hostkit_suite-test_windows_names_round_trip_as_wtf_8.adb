with Ada.Strings.UTF_Encoding.Conversions;
separate (Hostkit_Suite)
procedure Test_Windows_Names_Round_Trip_As_WTF_8
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   package WP renames Hostkit.Windows_Paths;

   function W (Code : Natural) return Wide_Character is (Wide_Character'Val (Code));
   function B (Code : Natural) return Character is (Character'Val (Code));

   --  Whether From_UTF_8 refuses Text, which is not empty: what it does
   --  not refuse converts to some units.
   function Refused (Text : String) return Boolean is
   begin
      return WP.From_UTF_8 (Text) = "";
   exception
      when Ada.Strings.UTF_Encoding.Encoding_Error =>
         return True;
   end Refused;

   --  Text that is UTF-8 converts as Ada's own conversion does: plain ASCII,
   --  a Latin-1 letter, the euro sign, and an emoji as a surrogate pair.
   Valid : constant Wide_String :=
     "notes " & W (16#D6#) & W (16#20AC#) & W (16#D83D#) & W (16#DE00#) & ".txt";
begin
   Assert
     (WP.To_UTF_8 (Valid) = Ada.Strings.UTF_Encoding.Conversions.Convert (Valid),
      "well-formed UTF-16 becomes the UTF-8 Ada's conversion gives");
   Assert (WP.From_UTF_8 (WP.To_UTF_8 (Valid)) = Valid, "and comes back unchanged");
   Assert
     (WP.To_UTF_8 (W (16#D83D#) & W (16#DE00#)) = B (16#F0#) & B (16#9F#) & B (16#98#) & B (16#80#),
      "a surrogate pair is the four bytes of the character it encodes");

   --  The names NTFS keeps and UTF-8 cannot spell.
   Assert
     (WP.To_UTF_8 ("a" & W (16#D800#) & "b") = "a" & B (16#ED#) & B (16#A0#) & B (16#80#) & "b",
      "a lone high surrogate is its code point's three bytes");
   Assert
     (WP.To_UTF_8 ([1 => W (16#DC00#)]) = B (16#ED#) & B (16#B0#) & B (16#80#),
      "so is a lone low surrogate");
   Assert
     (WP.To_UTF_8 (W (16#DE00#) & W (16#D83D#))
      = B (16#ED#) & B (16#B8#) & B (16#80#) & B (16#ED#) & B (16#A0#) & B (16#BD#),
      "a pair in the wrong order is two lone surrogates");
   Assert
     (WP.From_UTF_8 ("a" & B (16#ED#) & B (16#A0#) & B (16#80#) & "b") = "a" & W (16#D800#) & "b",
      "and the three bytes come back as the surrogate");
   Assert
     (WP.From_UTF_8 (WP.To_UTF_8 (W (16#DE00#) & W (16#D83D#) & W (16#DBFF#)))
      = W (16#DE00#) & W (16#D83D#) & W (16#DBFF#),
      "lone surrogates round-trip, a trailing one too");

   --  A leading U+FEFF is part of a name, not a byte order mark to drop.
   Assert
     (WP.To_UTF_8 (W (16#FEFF#) & "x") = B (16#EF#) & B (16#BB#) & B (16#BF#) & "x",
      "a leading U+FEFF is kept");
   Assert (WP.From_UTF_8 (B (16#EF#) & B (16#BB#) & B (16#BF#) & "x") = W (16#FEFF#) & "x", "both ways");
   Assert (WP.To_UTF_8 ("") = "" and then WP.From_UTF_8 ("") = "", "nothing is nothing");
   Assert (WP.From_UTF_8 ("a" & B (0) & "b") = "a" & W (0) & "b", "a NUL is carried, as an environment block needs");

   --  What is neither UTF-8 nor an encoded surrogate is refused, as before.
   Assert (Refused ("bad" & B (16#FF#)), "a byte no UTF-8 sequence starts with is refused");
   Assert (Refused ([1 => B (16#80#)]), "a stray continuation byte is refused");
   Assert (Refused (B (16#C0#) & B (16#80#)), "an overlong two-byte sequence is refused");
   Assert (Refused (B (16#E0#) & B (16#80#) & B (16#80#)), "an overlong three-byte sequence is refused");
   Assert (Refused (B (16#F0#) & B (16#80#) & B (16#80#) & B (16#80#)), "an overlong four-byte sequence is refused");
   Assert (Refused (B (16#E2#) & B (16#82#)), "a cut-off sequence is refused");
   Assert (Refused (B (16#F4#) & B (16#90#) & B (16#80#) & B (16#80#)), "a code point past U+10FFFF is refused");
end Test_Windows_Names_Round_Trip_As_WTF_8;
