private package Flyology_Serde_Generator.Build_Attestation_Test_Hooks is
   Enabled : constant Boolean := True;

   type Transfer_Point is
     (Request_Allocation,
      Request_Publication,
      Dependency_Allocation,
      Dependency_Publication);

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
