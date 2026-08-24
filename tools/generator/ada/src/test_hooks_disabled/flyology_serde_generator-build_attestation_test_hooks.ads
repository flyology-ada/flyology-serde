private package Flyology_Serde_Generator.Build_Attestation_Test_Hooks is
   Enabled : constant Boolean := False;

   type Transfer_Point is
     (Request_Allocation,
      Request_Publication,
      Dependency_Allocation,
      Dependency_Publication);

   procedure Arm (Point : Transfer_Point) with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_attestation_arm";
   procedure Pause (Point : Transfer_Point; Released : out Boolean) with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_attestation_pause";
   procedure Wait_For
     (Point   : Transfer_Point;
      Timeout : Duration;
      Reached : out Boolean) with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_attestation_wait";
   procedure Release (Point : Transfer_Point) with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_attestation_release";

   procedure Note_Request_Allocated with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_attestation_request_allocated";
   procedure Note_Request_Released with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_attestation_request_released";
   procedure Note_Dependency_Allocated with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_attestation_dependency_allocated";
   procedure Note_Dependency_Released with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_attestation_dependency_released";
   procedure Allocation_Counts
     (Requests_Allocated   : out Natural;
      Requests_Released    : out Natural;
      Dependencies_Allocated : out Natural;
      Dependencies_Released  : out Natural) with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_attestation_counts";

   procedure Arm_Request_Storage_Failure with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_attestation_arm_storage";
   procedure Raise_If_Request_Storage_Failure with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_attestation_raise_storage";
   procedure Arm_Request_Internal_Failure with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_attestation_arm_internal";
   procedure Raise_If_Request_Internal_Failure with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_attestation_raise_internal";
   procedure Arm_Dependency_Storage_Failure with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_attestation_arm_node_storage";
   procedure Raise_If_Dependency_Storage_Failure with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_attestation_raise_node_storage";
   procedure Arm_Dependency_Internal_Failure with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_attestation_arm_node_internal";
   procedure Raise_If_Dependency_Internal_Failure with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_attestation_raise_node_internal";
   procedure Arm_Request_Release_Failure with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_attestation_arm_release";
   procedure Raise_If_Request_Release_Failure with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_attestation_raise_release";
end Flyology_Serde_Generator.Build_Attestation_Test_Hooks;
