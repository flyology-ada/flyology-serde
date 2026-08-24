private package Flyology_Serde_Generator.Build_Process_Test_Hooks is
   Enabled : constant Boolean := False;

   procedure Arm_Exceptional_Release_Failure with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_arm_exceptional_release";
   procedure Arm_Spawned_Release_Failure with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_arm_spawned_release";
   procedure Arm_Spawn_Cleanup_Failure with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_arm_spawn_cleanup";
   procedure Consume_Spawn_Cleanup_Failure (Armed : out Boolean) with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_consume_spawn_cleanup";
   procedure Arm_Post_Primary_Failure with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_arm_post_primary";
   procedure Raise_If_Post_Primary_Failure with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_post_primary";
   procedure Arm_Close_Failure with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_arm_close_failure";
   procedure Consume_Close_Failure (Armed : out Boolean) with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_consume_close_failure";
   procedure Arm_Duplicate_Failure with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_arm_duplicate_failure";
   procedure Consume_Duplicate_Failure (Armed : out Boolean) with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_consume_duplicate_failure";
   procedure Arm_Nonblocking_Failure with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_arm_nonblocking_failure";
   procedure Consume_Nonblocking_Failure (Armed : out Boolean) with
     Import,
     Convention    => Ada,
     External_Name => "flyology_serde_disabled_process_consume_nonblocking_failure";
   procedure Raise_If_Materialization_Failure with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_materialization_failure";
   procedure Raise_If_Release_Failure with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_release_failure";

   procedure Arm_Materialization_Pause with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_arm_materialization_pause";
   procedure Note_C_String_Allocated with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_note_c_string_allocated";
   procedure Note_C_String_Released with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_note_c_string_released";
   procedure Note_Materialization with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_note_materialization";
   procedure Wait_For_Materialization
     (Timeout : Duration; Reached : out Boolean) with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_wait_materialization";
   procedure Wait_For_Materialization_Release
     (Timeout : Duration; Reached : out Boolean) with
     Import,
     Convention    => Ada,
     External_Name => "flyology_serde_disabled_process_wait_materialization_release";
   procedure Release_Materialization_Pause with
     Import,
     Convention    => Ada,
     External_Name => "flyology_serde_disabled_process_release_materialization_pause";
   procedure Materialization_Counts (Allocated : out Natural; Released : out Natural) with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_materialization_counts";

   procedure Arm_Spawn_Publish_Pause with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_arm_spawn_pause";
   procedure Note_Spawn_Published (Child : Integer) with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_note_spawn";
   procedure Wait_For_Spawn_Published (Timeout : Duration; Reached : out Boolean) with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_wait_spawn";
   procedure Wait_For_Spawn_Release (Timeout : Duration; Reached : out Boolean) with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_wait_spawn_release";
   procedure Release_Spawn_Pause with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_release_spawn_pause";
   procedure Last_Spawned_Child (Child : out Integer) with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_last_spawn";

   procedure Arm_Raw_Pipe_Pause with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_arm_raw_pipe_pause";
   procedure Note_Gate_Attempt with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_note_gate_attempt";
   procedure Note_Raw_Pipe_Open (Read_End : Integer; Write_End : Integer) with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_note_raw_pipe_open";
   procedure Last_Raw_Pipe (Read_End : out Integer; Write_End : out Integer) with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_last_raw_pipe";
   procedure Wait_For_Two_Gate_Attempts (Timeout : Duration; Reached : out Boolean) with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_wait_two_gate_attempts";
   procedure Wait_For_Raw_Pipe_Open (Timeout : Duration; Reached : out Boolean) with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_wait_raw_pipe_open";
   procedure Wait_For_Raw_Pipe_Release (Timeout : Duration; Reached : out Boolean) with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_wait_raw_pipe_release";
   procedure Release_Raw_Pipe_Pause with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_release_raw_pipe_pause";

   procedure Arm_Gate_Grant_Pause with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_arm_gate_grant_pause";
   procedure Note_Gate_Granted with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_note_gate_granted";
   procedure Wait_For_Gate_Granted (Timeout : Duration; Reached : out Boolean) with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_wait_gate_granted";
   procedure Wait_For_Gate_Grant_Release (Timeout : Duration; Reached : out Boolean) with
     Import,
     Convention    => Ada,
     External_Name => "flyology_serde_disabled_process_wait_gate_grant_release";
   procedure Release_Gate_Grant_Pause with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_release_gate_grant_pause";

   procedure Arm_Pipe_Transfer_Pause with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_arm_pipe_transfer_pause";
   procedure Note_Pipe_Transferred
     (Input_Read   : Integer;
      Input_Write  : Integer;
      Output_Read  : Integer;
      Output_Write : Integer;
      Error_Read   : Integer;
      Error_Write  : Integer) with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_note_pipe_transferred";
   procedure Wait_For_Pipe_Transferred (Timeout : Duration; Reached : out Boolean) with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_wait_pipe_transferred";
   procedure Wait_For_Pipe_Transfer_Release (Timeout : Duration; Reached : out Boolean) with
     Import,
     Convention    => Ada,
     External_Name => "flyology_serde_disabled_process_wait_pipe_transfer_release";
   procedure Release_Pipe_Transfer_Pause with
     Import,
     Convention    => Ada,
     External_Name => "flyology_serde_disabled_process_release_pipe_transfer_pause";
   procedure Last_Transferred_Pipes
     (Input_Read   : out Integer;
      Input_Write  : out Integer;
      Output_Read  : out Integer;
      Output_Write : out Integer;
      Error_Read   : out Integer;
      Error_Write  : out Integer) with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_last_transferred_pipes";

   procedure Arm_Command_Commit_Pause with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_arm_command_commit_pause";
   procedure Note_Command_Committed with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_note_command_committed";
   procedure Wait_For_Command_Committed (Timeout : Duration; Reached : out Boolean) with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_wait_command_committed";
   procedure Wait_For_Command_Commit_Release (Timeout : Duration; Reached : out Boolean) with
     Import,
     Convention    => Ada,
     External_Name => "flyology_serde_disabled_process_wait_command_commit_release";
   procedure Release_Command_Commit_Pause with
     Import,
     Convention    => Ada,
     External_Name => "flyology_serde_disabled_process_release_command_commit_pause";

   procedure Arm_Result_Commit_Pause with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_arm_result_commit_pause";
   procedure Note_Result_Committed with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_note_result_committed";
   procedure Wait_For_Result_Committed (Timeout : Duration; Reached : out Boolean) with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_wait_result_committed";
   procedure Wait_For_Result_Commit_Release (Timeout : Duration; Reached : out Boolean) with
     Import,
     Convention    => Ada,
     External_Name => "flyology_serde_disabled_process_wait_result_commit_release";
   procedure Release_Result_Commit_Pause with
     Import,
     Convention    => Ada,
     External_Name => "flyology_serde_disabled_process_release_result_commit_pause";

   procedure Arm_Close_Commit_Pause with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_arm_close_commit_pause";
   procedure Note_Close_Committed (Descriptor : Integer) with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_note_close_committed";
   procedure Wait_For_Close_Committed (Timeout : Duration; Reached : out Boolean) with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_wait_close_committed";
   procedure Wait_For_Close_Commit_Release (Timeout : Duration; Reached : out Boolean) with
     Import,
     Convention    => Ada,
     External_Name => "flyology_serde_disabled_process_wait_close_commit_release";
   procedure Release_Close_Commit_Pause with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_release_close_commit_pause";
   procedure Last_Closed_Descriptor (Descriptor : out Integer) with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_last_closed_descriptor";

   procedure Arm_Duplicate_Transfer_Pause with
     Import,
     Convention    => Ada,
     External_Name => "flyology_serde_disabled_process_arm_duplicate_transfer_pause";
   procedure Note_Duplicate_Transferred (Read_End : Integer; Write_End : Integer) with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_note_duplicate_transferred";
   procedure Wait_For_Duplicate_Transferred (Timeout : Duration; Reached : out Boolean) with
     Import,
     Convention    => Ada,
     External_Name => "flyology_serde_disabled_process_wait_duplicate_transferred";
   procedure Wait_For_Duplicate_Transfer_Release (Timeout : Duration; Reached : out Boolean) with
     Import,
     Convention    => Ada,
     External_Name => "flyology_serde_disabled_process_wait_duplicate_transfer_release";
   procedure Release_Duplicate_Transfer_Pause with
     Import,
     Convention    => Ada,
     External_Name => "flyology_serde_disabled_process_release_duplicate_transfer_pause";
   procedure Last_Transferred_Duplicates (Read_End : out Integer; Write_End : out Integer) with
     Import,
     Convention    => Ada,
     External_Name => "flyology_serde_disabled_process_last_transferred_duplicates";

   procedure Raise_Fail_Stop (Location : Positive; Code : Integer) with
     Import, Convention => Ada, External_Name => "flyology_serde_disabled_process_raise_fail_stop";
end Flyology_Serde_Generator.Build_Process_Test_Hooks;
