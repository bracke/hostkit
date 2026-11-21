with Ada.Strings.Unbounded;
with Interfaces.C;

--  The account database, asked in a way that is safe from more than one task
--  at once. getpwnam, getpwuid, getgrnam and getgrgid answer from one buffer
--  of the C library's, which the next lookup on any thread overwrites -- so
--  two tasks asking at once could read each other's answer, or a name that
--  was half replaced. These use the reentrant forms (getpwnam_r and the
--  rest) with a buffer of the caller's, and copy out what was found before
--  that buffer goes. The record layouts that differ between the hosts come
--  from Hostkit.Posix_Abi.
package Hostkit.Posix.Accounts is

   --  A user as the account database records it.
   type User_Entry is record
      --  Whether there is such a user. False too when the database could not
      --  be read: not knowing is not a user.
      Found    : Boolean := False;
      User_Id  : Interfaces.C.unsigned := 0;
      Group_Id : Interfaces.C.unsigned := 0;
      Name     : Ada.Strings.Unbounded.Unbounded_String;
      Home     : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  A group as the account database records it.
   type Group_Entry is record
      --  Whether there is such a group (False also when the database could
      --  not be read).
      Found    : Boolean := False;
      Group_Id : Interfaces.C.unsigned := 0;
      Name     : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  The user named Name.
   --
   --  @param Name A login name.
   --  @return The user; Found is False when there is none.
   function User_By_Name (Name : String) return User_Entry;

   --  The user with the id Id.
   --
   --  @param Id A user id.
   --  @return The user; Found is False when there is none.
   function User_By_Id (Id : Interfaces.C.unsigned) return User_Entry;

   --  The group named Name.
   --
   --  @param Name A group name.
   --  @return The group; Found is False when there is none.
   function Group_By_Name (Name : String) return Group_Entry;

   --  The group with the id Id.
   --
   --  @param Id A group id.
   --  @return The group; Found is False when there is none.
   function Group_By_Id (Id : Interfaces.C.unsigned) return Group_Entry;

end Hostkit.Posix.Accounts;
