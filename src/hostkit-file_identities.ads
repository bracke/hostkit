with Interfaces;

--  The small identity value shared by pathname metadata and held descriptors.
--  Keeping it below both packages prevents the low-level descriptor layer
--  from depending on all filesystem metadata merely to return one record.
package Hostkit.File_Identities is
   subtype Identity_Field is Interfaces.Unsigned_64;

   type Entry_Identity is record
      Available       : Boolean := False;
      Volume          : Identity_Field := 0;
      File_Number     : Identity_Field := 0;
      Generation_High : Identity_Field := 0;
      Generation_Low  : Identity_Field := 0;
   end record;
end Hostkit.File_Identities;
