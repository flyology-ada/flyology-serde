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
      Source_Callback);

   type Source_Failure_Point is
     (Source_Path_Storage,
      Source_Node_Storage,
      Source_Payload_Storage,
      Source_Internal,
      Source_Path_Release,
      Source_Node_Release,
      Source_Payload_Release,
      Source_Visit_Release);

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
