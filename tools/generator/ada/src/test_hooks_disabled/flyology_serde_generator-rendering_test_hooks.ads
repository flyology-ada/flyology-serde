with Interfaces;
with System;

private package Flyology_Serde_Generator.Rendering_Test_Hooks is
   Enabled : constant Boolean := False;

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

   procedure Arm (Point : Pause_Point) with
     Import,
     Convention => Ada,
     External_Name => "flyology_serde_disabled_rendering_arm";
   procedure Pause (Point : Pause_Point; Released : out Boolean) with
     Import,
     Convention => Ada,
     External_Name => "flyology_serde_disabled_rendering_pause";
   procedure Wait_For
     (Point   : Pause_Point;
      Timeout : Duration;
      Reached : out Boolean) with
     Import,
     Convention => Ada,
     External_Name => "flyology_serde_disabled_rendering_wait";
   procedure Release (Point : Pause_Point) with
     Import,
     Convention => Ada,
     External_Name => "flyology_serde_disabled_rendering_release";

   procedure Note_Attached (Address : System.Address) with
     Import,
     Convention => Ada,
     External_Name => "flyology_serde_disabled_rendering_attached";
   procedure Begin_Free
     (Address  : System.Address;
      Identity : out Artifact_Identity;
      Found    : out Boolean) with
     Import,
     Convention => Ada,
     External_Name => "flyology_serde_disabled_rendering_begin_free";
   procedure Note_Freed (Identity : Artifact_Identity) with
     Import,
     Convention => Ada,
     External_Name => "flyology_serde_disabled_rendering_freed";
   procedure Note_Damaged (Identity : Artifact_Identity) with
     Import,
     Convention => Ada,
     External_Name => "flyology_serde_disabled_rendering_damaged";
   procedure Counts
     (Attached      : out Natural;
      Freed         : out Natural;
      Last_Attached : out Artifact_Identity;
      Last_Freed    : out Artifact_Identity;
      Overflowed    : out Boolean) with
     Import,
     Convention => Ada,
     External_Name => "flyology_serde_disabled_rendering_counts";

   procedure Arm_Failure (Point : Failure_Point) with
     Import,
     Convention => Ada,
     External_Name => "flyology_serde_disabled_rendering_arm_failure";
   procedure Take_Failure
     (Point : Failure_Point;
      Armed : out Boolean) with
     Import,
     Convention => Ada,
     External_Name => "flyology_serde_disabled_rendering_take_failure";
   procedure Reset with
     Import,
     Convention => Ada,
     External_Name => "flyology_serde_disabled_rendering_reset";
end Flyology_Serde_Generator.Rendering_Test_Hooks;
