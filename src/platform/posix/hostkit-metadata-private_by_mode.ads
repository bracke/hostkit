--  The rule Hostkit.Metadata.Private_To_Current_User applies on Linux and on
--  macOS alike, written once: each host's subunit calls it, and macOS adds
--  only its extended-ACL test. This unit is in the POSIX source directory
--  only, so no other host ever sees it.
--
--  @param Path The entry to ask about, not followed.
--  @return True when the entry is no link, grants its group and others
--    nothing (mode bits 8#077# clear), and is owned by the effective user;
--    False for anything else, and when its status cannot be read.
private function Hostkit.Metadata.Private_By_Mode (Path : String) return Boolean;
