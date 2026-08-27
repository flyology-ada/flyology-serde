with Interfaces;
with System;

private package Flyology_Serde_Generator.Rendering_Test_Hooks is
   Enabled : constant Boolean := True;

   subtype Artifact_Identity is Interfaces.Unsigned_64;

   type Pause_Point is
     (After_Attachment,
      Before_Publication,
      Deferred_Publication,
      Cleanup_Detached);

   type Failure_Point is
     (After_Attachment_Failure,
      Before_Publication_Failure,
      Deferred_Publication_Failure,
      Cleanup_Pause_Timeout,
      Cleanup_Pause_Exception,
      Cleanup_Damage);

   procedure Arm (Point : Pause_Point);
   procedure Pause (Point : Pause_Point; Released : out Boolean);
   procedure Wait_For
     (Point   : Pause_Point;
      Timeout : Duration;
      Reached : out Boolean);
   procedure Release (Point : Pause_Point);

   procedure Note_Attached (Address : System.Address);
   procedure Begin_Free
     (Address  : System.Address;
      Identity : out Artifact_Identity;
      Found    : out Boolean);
   procedure Note_Freed (Identity : Artifact_Identity);
   procedure Note_Damaged (Identity : Artifact_Identity);
   procedure Counts
     (Attached      : out Natural;
      Freed         : out Natural;
      Last_Attached : out Artifact_Identity;
      Last_Freed    : out Artifact_Identity;
      Overflowed    : out Boolean);

   procedure Arm_Failure (Point : Failure_Point);
   procedure Take_Failure
     (Point : Failure_Point;
      Armed : out Boolean);
   procedure Reset;
end Flyology_Serde_Generator.Rendering_Test_Hooks;
