private package Flyology_Serde_Generator.Build_Attestation_Test_Hooks is
   Enabled : constant Boolean := True;

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

   procedure Arm (Point : Transfer_Point);
   procedure Pause (Point : Transfer_Point; Released : out Boolean);
   procedure Wait_For (Point : Transfer_Point; Timeout : Duration; Reached : out Boolean);
   procedure Release (Point : Transfer_Point);

   procedure Note_Request_Allocated;
   procedure Note_Request_Released;
   procedure Note_Dependency_Allocated;
   procedure Note_Dependency_Released;
   procedure Allocation_Counts
     (Requests_Allocated     : out Natural;
      Requests_Released      : out Natural;
      Dependencies_Allocated : out Natural;
      Dependencies_Released  : out Natural);
   procedure Note_Source_Path_Allocated;
   procedure Note_Source_Path_Released;
   procedure Note_Source_Node_Allocated;
   procedure Note_Source_Node_Released;
   procedure Note_Source_Payload_Allocated;
   procedure Note_Source_Payload_Released;
   procedure Source_Allocation_Counts
     (Paths_Allocated    : out Natural;
      Paths_Released     : out Natural;
      Nodes_Allocated    : out Natural;
      Nodes_Released     : out Natural;
      Payloads_Allocated : out Natural;
      Payloads_Released  : out Natural);

   procedure Arm_Source_Failure (Point : Source_Failure_Point);
   procedure Raise_If_Source_Failure (Point : Source_Failure_Point);

   procedure Arm_Snapshot_Failure
     (Point : Snapshot_Failure_Point;
      Occurrence : Positive := 1);
   procedure Reset_Snapshot_Failures;
   function Snapshot_Failure_Remaining (Point : Snapshot_Failure_Point) return Natural;
   function Snapshot_Failures_Clear return Boolean;
   procedure Take_Snapshot_Failure
     (Point : Snapshot_Failure_Point;
      Armed : out Boolean);
   procedure Note_Snapshot_Descriptor_Attached;
   procedure Note_Snapshot_Descriptor_Released;
   procedure Snapshot_Descriptor_Counts
     (Attached : out Natural;
      Released : out Natural);
   procedure Note_Snapshot_Block_Allocated;
   procedure Note_Snapshot_Block_Released;
   procedure Note_Snapshot_Path_Allocated;
   procedure Note_Snapshot_Path_Released;
   procedure Note_Snapshot_Payload_Allocated;
   procedure Note_Snapshot_Payload_Released;
   procedure Snapshot_Allocation_Counts
     (Blocks_Allocated   : out Natural;
      Blocks_Released    : out Natural;
      Paths_Allocated    : out Natural;
      Paths_Released     : out Natural;
      Payloads_Allocated : out Natural;
      Payloads_Released  : out Natural);

   procedure Arm_Request_Storage_Failure;
   procedure Raise_If_Request_Storage_Failure;
   procedure Arm_Request_Internal_Failure;
   procedure Raise_If_Request_Internal_Failure;
   procedure Arm_Dependency_Storage_Failure;
   procedure Raise_If_Dependency_Storage_Failure;
   procedure Arm_Dependency_Internal_Failure;
   procedure Raise_If_Dependency_Internal_Failure;
   procedure Arm_Request_Release_Failure;
   procedure Raise_If_Request_Release_Failure;
end Flyology_Serde_Generator.Build_Attestation_Test_Hooks;
