package body Hostkit.Directory_Reading_Probe is

   function Available return Boolean is (False);

   function Read (How : Ending; Visited : out Natural) return Boolean is
      pragma Unreferenced (How);
   begin
      Visited := 0;
      return False;
   end Read;

end Hostkit.Directory_Reading_Probe;
