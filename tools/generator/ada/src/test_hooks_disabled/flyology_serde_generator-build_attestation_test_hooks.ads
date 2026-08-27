private package Flyology_Serde_Generator.Build_Attestation_Test_Hooks is
   Enabled : constant Boolean := False;

   type Transfer_Point is
     (Request_Allocation,
      Request_Publication,
      Dependency_Allocation,
      Dependency_Publication,
      Source_Path_Allocation,
      Source_Node_Allocation,
      Source_Node_Publication,
      Source_Payload_Allocation,
      Source_Payload_Publication,
      Source_Owner_Publication,
      Source_Visit_Latch,
      Source_Callback,
      Snapshot_After_Initial_Identity,
      Snapshot_After_Read,
      Snapshot_Root_Precommit,
      Snapshot_Capture_Precommit,
      Snapshot_Copy_Precommit);

   type Source_Failure_Point is
     (Source_Path_Storage,
      Source_Node_Storage,
      Source_Payload_Storage,
      Source_Internal,
      Source_Path_Release,
      Source_Node_Release,
      Source_Payload_Release,
      Source_Visit_Release);

   type Snapshot_Failure_Point is
     (Snapshot_Open_Interrupted,
      Snapshot_Open_Failed,
      Snapshot_Identity_Failed,
      Snapshot_Read_Interrupted,
      Snapshot_Read_Failed,
      Snapshot_Read_Short,
      Snapshot_Premature_EOF,
      Snapshot_Impossible_Positive_Result,
      Snapshot_Close_Failed,
      Snapshot_Block_Storage,
      Snapshot_Path_Storage,
      Snapshot_Payload_Storage,
      Snapshot_Block_Release,
      Snapshot_Path_Release,
      Snapshot_Payload_Release,
      Snapshot_Copy_Invariant,
      Snapshot_Copy_Storage);

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

   procedure Note_Source_Path_Allocated with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_attestation_source_path_allocated";
   procedure Note_Source_Path_Released with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_attestation_source_path_released";
   procedure Note_Source_Node_Allocated with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_attestation_source_node_allocated";
   procedure Note_Source_Node_Released with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_attestation_source_node_released";
   procedure Note_Source_Payload_Allocated with
     Import,
     Convention => Ada,
     External_Name => "flyology_serde_disabled_attestation_source_payload_allocated";
   procedure Note_Source_Payload_Released with
     Import,
     Convention => Ada,
     External_Name => "flyology_serde_disabled_attestation_source_payload_released";
   procedure Source_Allocation_Counts
     (Paths_Allocated    : out Natural;
      Paths_Released     : out Natural;
      Nodes_Allocated    : out Natural;
      Nodes_Released     : out Natural;
      Payloads_Allocated : out Natural;
      Payloads_Released  : out Natural) with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_attestation_source_counts";

   procedure Arm_Source_Failure (Point : Source_Failure_Point) with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_attestation_arm_source_failure";
   procedure Raise_If_Source_Failure (Point : Source_Failure_Point) with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_attestation_raise_source_failure";

   procedure Arm_Snapshot_Failure
     (Point      : Snapshot_Failure_Point;
      Occurrence : Positive := 1) with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_snapshot_arm_failure";
   procedure Reset_Snapshot_Failures with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_snapshot_reset_failures";
   function Snapshot_Failure_Remaining (Point : Snapshot_Failure_Point) return Natural with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_snapshot_failure_remaining";
   function Snapshot_Failures_Clear return Boolean with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_snapshot_failures_clear";
   procedure Take_Snapshot_Failure
     (Point : Snapshot_Failure_Point;
      Armed : out Boolean) with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_snapshot_take_failure";
   procedure Note_Snapshot_Descriptor_Attached with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_snapshot_descriptor_attached";
   procedure Note_Snapshot_Descriptor_Released with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_snapshot_descriptor_released";
   procedure Snapshot_Descriptor_Counts
     (Attached : out Natural;
      Released : out Natural) with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_snapshot_descriptor_counts";
   procedure Note_Snapshot_Block_Allocated with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_snapshot_block_allocated";
   procedure Note_Snapshot_Block_Released with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_snapshot_block_released";
   procedure Note_Snapshot_Path_Allocated with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_snapshot_path_allocated";
   procedure Note_Snapshot_Path_Released with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_snapshot_path_released";
   procedure Note_Snapshot_Payload_Allocated with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_snapshot_payload_allocated";
   procedure Note_Snapshot_Payload_Released with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_snapshot_payload_released";
   procedure Snapshot_Allocation_Counts
     (Blocks_Allocated   : out Natural;
      Blocks_Released    : out Natural;
      Paths_Allocated    : out Natural;
      Paths_Released     : out Natural;
      Payloads_Allocated : out Natural;
      Payloads_Released  : out Natural) with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_snapshot_counts";

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
