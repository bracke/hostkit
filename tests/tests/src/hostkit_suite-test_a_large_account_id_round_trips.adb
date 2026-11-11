separate (Hostkit_Suite)
procedure Test_A_Large_Account_Id_Round_Trips
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Nobody : constant Hostkit.Metadata.Account_Id := 4_294_967_294;
   Parsed : Hostkit.Metadata.Parsed_Account_Id;
begin
   Assert
     (Hostkit.Metadata.Account_Image (Nobody) = "4294967294",
      "a large id prints in full, with no sign and no leading blank");
   Parsed := Hostkit.Metadata.Parse_Account_Id ("4294967294");
   Assert (Parsed.Valid, "a large id reads back from its text");
   Assert (Parsed.Id = Nobody, "as the id it was printed from");

   Parsed := Hostkit.Metadata.Parse_Account_Id
     (Hostkit.Metadata.Account_Image (Hostkit.Metadata.Account_Id'Last));
   Assert (Parsed.Valid, "the largest id reads back");
   Assert (Parsed.Id = Hostkit.Metadata.Account_Id'Last, "as itself");

   Parsed := Hostkit.Metadata.Parse_Account_Id ("0");
   Assert (Parsed.Valid, "id 0 reads back");
   Assert (Parsed.Id = 0, "as 0");

   Assert
     (not Hostkit.Metadata.Parse_Account_Id ("4294967296").Valid,
      "an id past 32 bits is refused");
   Assert
     (not Hostkit.Metadata.Parse_Account_Id ("99999999999").Valid,
      "an eleven-digit id is refused");
   Assert (not Hostkit.Metadata.Parse_Account_Id ("").Valid, "empty text is refused");
   Assert (not Hostkit.Metadata.Parse_Account_Id ("-1").Valid, "a sign is refused");
   Assert (not Hostkit.Metadata.Parse_Account_Id (" 1").Valid, "a blank is refused");
   Assert (not Hostkit.Metadata.Parse_Account_Id ("16#FF#").Valid, "a based literal is refused");
   Assert (not Hostkit.Metadata.Parse_Account_Id ("1_000").Valid, "an underscore is refused");

   Assert
     (Hostkit.Metadata.Fits_Natural (Hostkit.Metadata.Account_Id (Natural'Last)),
      "the largest Natural id fits a Natural");
   Assert
     (not Hostkit.Metadata.Fits_Natural (Hostkit.Metadata.Account_Id (Natural'Last) + 1),
      "2**31 does not fit a Natural");
   Assert (not Hostkit.Metadata.Fits_Natural (Nobody), "nobody does not fit a Natural");
end Test_A_Large_Account_Id_Round_Trips;
