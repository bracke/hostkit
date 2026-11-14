with Interfaces;

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

   --  Create an empty file named Leaf in Folder through CreateFileW, the
   --  name's UTF-16 units given as they are -- a lone surrogate among them,
   --  which no UTF-8 text spells -- so that hostkit's own reading of the
   --  name is what a test checks.
   --
   --  @param Folder An existing folder.
   --  @param Leaf The new file's name, as UTF-16 units.
   --  @return True when the file was created; False on a host whose names
   --    are not UTF-16 (every one but Windows) or when the create failed.
   function Create_With_Units (Folder : String; Leaf : Wide_String) return Boolean;

   --  Whether a program started from now on would inherit the open file
   --  Handle names: its HANDLE_FLAG_INHERIT, as GetHandleInformation reads
   --  it.
   --
   --  @param Handle A Windows HANDLE, as an integer.
   --  @param Inheritable Whether the flag is set, when the result is True.
   --  @return True when the host answered; False on a host without such
   --    handles (every one but Windows) or when it would not say.
   function Handle_Inheritance (Handle : Interfaces.Integer_64; Inheritable : out Boolean) return Boolean;

   --  Switch off the backup and restore privileges this process holds. An
   --  administrator's MSYS2 bash -- the one CI runs the suite from -- turns
   --  them on and its children inherit them, and with them on CreateFileW
   --  and SetSecurityInfo pass over any DACL: every access test would then
   --  pass for a reason a user's process never has.
   --
   --  @return True when they are off, or on a host without them (every one
   --    but Windows).
   function Drop_Backup_Privileges return Boolean;

   --  What waiting for a child's exit, without collecting it, came to.
   --  Exited: it has exited and its status is still there for whoever
   --  collects it. Not_A_Child: there is no such child to wait for -- one
   --  already collected, by this process's own reaper or another waiter.
   --  Cannot_Wait: the host has no such wait (Windows), or it failed.
   type Exit_Wait is (Exited, Not_A_Child, Cannot_Wait);

   --  Wait until the child Process_Id has exited, leaving it uncollected:
   --  waitid (P_PID, Process_Id, WEXITED | WNOWAIT) on POSIX, so a test can
   --  know a child is done without taking the status a later wait is to
   --  find -- which waiting by Hostkit.Spawn.Wait would.
   --
   --  @param Process_Id The child.
   --  @return Exited, Not_A_Child or Cannot_Wait, as above.
   function Await_Exit_Uncollected (Process_Id : Integer) return Exit_Wait;

private

   type Exclusive_Hold is limited record
      Handle : System.Address := System.Null_Address;
   end record;

end Hostkit_Test_Native;
