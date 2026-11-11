private with System;

--  Fixture code only one host can link: the Windows API a test needs to set
--  up a state that hostkit's own calls must then cope with. Each host brings
--  its own body (tests/src/native/<host>); where a fixture is not the host's,
--  it says so rather than pretending.
package Hostkit_Test_Native is

   --  An open of a file that shares reading only.
   type Exclusive_Hold is limited private;

   --  Open Path for reading, sharing reads only, so that another open for
   --  writing fails with a sharing violation (ERROR_SHARING_VIOLATION) until
   --  Release -- what a virus scanner holding a just-written file does.
   --
   --  @param Path The file; it must exist.
   --  @param Held The open, for Release.
   --  @return True when the file is held; False on a host without such
   --    opens (every one but Windows) or when the open failed.
   function Hold_Against_Writers (Path : String; Held : out Exclusive_Hold) return Boolean;

   --  Close a hold; nothing where none is held.
   --
   --  @param Held The open Hold_Against_Writers made.
   procedure Release (Held : in out Exclusive_Hold);

   --  Whether the host keeps Path read-only: the read-only attribute on
   --  Windows, no write bit in the mode elsewhere.
   --
   --  @param Path The file.
   --  @return True when it is read-only; False when it is not, or cannot be
   --    asked.
   function Is_Read_Only (Path : String) return Boolean;

private

   type Exclusive_Hold is limited record
      Handle : System.Address := System.Null_Address;
   end record;

end Hostkit_Test_Native;
