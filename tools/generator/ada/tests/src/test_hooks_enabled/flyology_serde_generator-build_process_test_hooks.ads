private package Flyology_Serde_Generator.Build_Process_Test_Hooks is
   Enabled : constant Boolean := True;

   procedure Arm_Exceptional_Release_Failure;
   procedure Arm_Spawned_Release_Failure;
   procedure Arm_Spawn_Cleanup_Failure;
   procedure Consume_Spawn_Cleanup_Failure (Armed : out Boolean);
   procedure Arm_Post_Primary_Failure;
   procedure Raise_If_Post_Primary_Failure;
   procedure Arm_Close_Failure;
   procedure Consume_Close_Failure (Armed : out Boolean);
   procedure Arm_Duplicate_Failure;
   procedure Consume_Duplicate_Failure (Armed : out Boolean);
   procedure Arm_Nonblocking_Failure;
   procedure Consume_Nonblocking_Failure (Armed : out Boolean);
   procedure Raise_If_Materialization_Failure;
   procedure Raise_If_Release_Failure;

   procedure Arm_Materialization_Pause;
   procedure Note_C_String_Allocated;
   procedure Note_C_String_Released;
   procedure Note_Materialization;
   procedure Wait_For_Materialization (Timeout : Duration; Reached : out Boolean);
   procedure Wait_For_Materialization_Release (Timeout : Duration; Reached : out Boolean);
   procedure Release_Materialization_Pause;
   procedure Materialization_Counts (Allocated : out Natural; Released : out Natural);

   procedure Arm_Spawn_Publish_Pause;
   procedure Note_Spawn_Published (Child : Integer);
   procedure Wait_For_Spawn_Published (Timeout : Duration; Reached : out Boolean);
   procedure Wait_For_Spawn_Release (Timeout : Duration; Reached : out Boolean);
   procedure Release_Spawn_Pause;
   procedure Last_Spawned_Child (Child : out Integer);

   procedure Arm_Raw_Pipe_Pause;
   procedure Note_Gate_Attempt;
   procedure Note_Raw_Pipe_Open (Read_End : Integer; Write_End : Integer);
   procedure Last_Raw_Pipe (Read_End : out Integer; Write_End : out Integer);
   procedure Wait_For_Two_Gate_Attempts (Timeout : Duration; Reached : out Boolean);
   procedure Wait_For_Raw_Pipe_Open (Timeout : Duration; Reached : out Boolean);
   procedure Wait_For_Raw_Pipe_Release (Timeout : Duration; Reached : out Boolean);
   procedure Release_Raw_Pipe_Pause;

   procedure Arm_Gate_Grant_Pause;
   procedure Note_Gate_Granted;
   procedure Wait_For_Gate_Granted (Timeout : Duration; Reached : out Boolean);
   procedure Wait_For_Gate_Grant_Release (Timeout : Duration; Reached : out Boolean);
   procedure Release_Gate_Grant_Pause;

   procedure Arm_Pipe_Transfer_Pause;
   procedure Note_Pipe_Transferred
     (Input_Read   : Integer;
      Input_Write  : Integer;
      Output_Read  : Integer;
      Output_Write : Integer;
      Error_Read   : Integer;
      Error_Write  : Integer);
   procedure Wait_For_Pipe_Transferred (Timeout : Duration; Reached : out Boolean);
   procedure Wait_For_Pipe_Transfer_Release (Timeout : Duration; Reached : out Boolean);
   procedure Release_Pipe_Transfer_Pause;
   procedure Last_Transferred_Pipes
     (Input_Read   : out Integer;
      Input_Write  : out Integer;
      Output_Read  : out Integer;
      Output_Write : out Integer;
      Error_Read   : out Integer;
      Error_Write  : out Integer);

   procedure Arm_Command_Commit_Pause;
   procedure Note_Command_Committed;
   procedure Wait_For_Command_Committed (Timeout : Duration; Reached : out Boolean);
   procedure Wait_For_Command_Commit_Release (Timeout : Duration; Reached : out Boolean);
   procedure Release_Command_Commit_Pause;

   procedure Arm_Result_Commit_Pause;
   procedure Note_Result_Committed;
   procedure Wait_For_Result_Committed (Timeout : Duration; Reached : out Boolean);
   procedure Wait_For_Result_Commit_Release (Timeout : Duration; Reached : out Boolean);
   procedure Release_Result_Commit_Pause;

   procedure Arm_Close_Commit_Pause;
   procedure Note_Close_Committed (Descriptor : Integer);
   procedure Wait_For_Close_Committed (Timeout : Duration; Reached : out Boolean);
   procedure Wait_For_Close_Commit_Release (Timeout : Duration; Reached : out Boolean);
   procedure Release_Close_Commit_Pause;
   procedure Last_Closed_Descriptor (Descriptor : out Integer);

   procedure Arm_Duplicate_Transfer_Pause;
   procedure Note_Duplicate_Transferred (Read_End : Integer; Write_End : Integer);
   procedure Wait_For_Duplicate_Transferred (Timeout : Duration; Reached : out Boolean);
   procedure Wait_For_Duplicate_Transfer_Release (Timeout : Duration; Reached : out Boolean);
   procedure Release_Duplicate_Transfer_Pause;
   procedure Last_Transferred_Duplicates (Read_End : out Integer; Write_End : out Integer);

   procedure Raise_Fail_Stop (Location : Positive; Code : Integer);
end Flyology_Serde_Generator.Build_Process_Test_Hooks;
