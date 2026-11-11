separate (Hostkit_Shell_Cases)
procedure Test_Signal_Names_And_Numbers_Agree
  (T : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (T);
   Decoded : Hostkit.Signals.Signal;
begin
   for Item in Hostkit.Signals.Signal loop
      Assert (Hostkit.Signals.Name (Item)'Length > 0,
              "a signal has no name: " & Hostkit.Signals.Signal'Image (Item));

      if Hostkit.Signals.Is_Supported (Item) then
         Assert (Hostkit.Signals.Number (Item) > 0,
                 "a supported signal has no number: "
                 & Hostkit.Signals.Name (Item));

         --  Round trip. A wait status carries a number, and reporting the
         --  wrong signal for it is worse than reporting none.
         Assert (Hostkit.Signals.From_Number
                   (Hostkit.Signals.Number (Item), Decoded),
                 "a supported signal's number did not decode: "
                 & Hostkit.Signals.Name (Item));
         Assert (Decoded = Item,
                 "a signal number decoded to the wrong signal: "
                 & Hostkit.Signals.Name (Item) & " became "
                 & Hostkit.Signals.Name (Decoded));
      else
         Assert (Hostkit.Signals.Number (Item) = -1,
                 "an unsupported signal reported a number: "
                 & Hostkit.Signals.Name (Item));
      end if;
   end loop;
end Test_Signal_Names_And_Numbers_Agree;
