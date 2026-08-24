package body Flyology_Serde_Generator.Build_Process_Test_Hooks is
   protected Control is
      procedure Arm_Exceptional_Release;
      procedure Arm_Spawned_Release;
      procedure Arm_Spawn_Cleanup;
      procedure Take_Spawn_Cleanup (Armed : out Boolean);
      procedure Arm_Post_Primary;
      procedure Check_Post_Primary;
      procedure Arm_Close;
      procedure Take_Close (Armed : out Boolean);
      procedure Arm_Duplicate;
      procedure Take_Duplicate (Armed : out Boolean);
      procedure Arm_Nonblocking;
      procedure Take_Nonblocking (Armed : out Boolean);
      procedure Check_Materialization;
      procedure Check_Release;

      procedure Arm_Materialization_Pause;
      procedure C_String_Allocated;
      procedure C_String_Released;
      procedure Materialization_Reached;
      entry Wait_Materialization;
      entry Wait_Materialization_Release;
      procedure Release_Materialization;
      procedure Read_Materialization_Counts (Allocated : out Natural; Released : out Natural);

      procedure Arm_Spawn_Pause;
      procedure Spawn_Published (Child : Integer);
      entry Wait_Spawn;
      entry Wait_Spawn_Release;
      procedure Release_Spawn;
      procedure Read_Last_Spawn (Child : out Integer);

      procedure Arm_Pipe_Pause;
      procedure Gate_Attempt;
      procedure Raw_Pipe_Open (Read_End : Integer; Write_End : Integer);
      procedure Read_Last_Raw_Pipe (Read_End : out Integer; Write_End : out Integer);
      entry Wait_Two_Attempts;
      entry Wait_Pipe_Open;
      entry Wait_Pipe_Release;
      procedure Release_Pipe;

      procedure Arm_Gate_Grant_Pause;
      procedure Gate_Granted;
      entry Wait_Gate_Granted;
      entry Wait_Gate_Grant_Release;
      procedure Release_Gate_Grant;

      procedure Arm_Pipe_Transfer_Pause;
      procedure Pipe_Transferred
        (Input_Read   : Integer;
         Input_Write  : Integer;
         Output_Read  : Integer;
         Output_Write : Integer;
         Error_Read   : Integer;
         Error_Write  : Integer);
      entry Wait_Pipe_Transferred;
      entry Wait_Pipe_Transfer_Release;
      procedure Release_Pipe_Transfer;
      procedure Read_Transferred_Pipes
        (Input_Read   : out Integer;
         Input_Write  : out Integer;
         Output_Read  : out Integer;
         Output_Write : out Integer;
         Error_Read   : out Integer;
         Error_Write  : out Integer);

      procedure Arm_Command_Commit_Pause;
      procedure Command_Committed;
      entry Wait_Command_Committed;
      entry Wait_Command_Commit_Release;
      procedure Release_Command_Commit;

      procedure Arm_Result_Commit_Pause;
      procedure Result_Committed;
      entry Wait_Result_Committed;
      entry Wait_Result_Commit_Release;
      procedure Release_Result_Commit;

      procedure Arm_Close_Commit_Pause;
      procedure Close_Committed (Descriptor : Integer);
      entry Wait_Close_Committed;
      entry Wait_Close_Commit_Release;
      procedure Release_Close_Commit;
      procedure Read_Last_Close (Descriptor : out Integer);

      procedure Arm_Duplicate_Transfer_Pause;
      procedure Duplicate_Transferred (Read_End : Integer; Write_End : Integer);
      entry Wait_Duplicate_Transferred;
      entry Wait_Duplicate_Transfer_Release;
      procedure Release_Duplicate_Transfer;
      procedure Read_Transferred_Duplicates (Read_End : out Integer; Write_End : out Integer);
   private
      Fail_Materialization : Boolean := False;
      Fail_Release         : Boolean := False;
      Fail_Spawn_Cleanup   : Boolean := False;
      Fail_Post_Primary    : Boolean := False;
      Fail_Close           : Boolean := False;
      Fail_Duplicate       : Boolean := False;
      Fail_Nonblocking     : Boolean := False;
      Materialization_Reached_Flag : Boolean := False;
      Materialization_Released     : Boolean := True;
      C_Strings_Allocated          : Natural := 0;
      C_Strings_Released           : Natural := 0;
      Spawn_Reached                : Boolean := False;
      Spawn_Released               : Boolean := True;
      Spawned_Child                : Integer := -1;
      Gate_Attempts        : Natural := 0;
      Pipe_Open            : Boolean := False;
      Pipe_Released        : Boolean := True;
      Raw_Read_End         : Integer := -1;
      Raw_Write_End        : Integer := -1;
      Gate_Granted_Flag    : Boolean := False;
      Gate_Grant_Released  : Boolean := True;
      Pipe_Transferred_Flag : Boolean := False;
      Pipe_Transfer_Released : Boolean := True;
      Transferred_Input_Read   : Integer := -1;
      Transferred_Input_Write  : Integer := -1;
      Transferred_Output_Read  : Integer := -1;
      Transferred_Output_Write : Integer := -1;
      Transferred_Error_Read   : Integer := -1;
      Transferred_Error_Write  : Integer := -1;
      Command_Committed_Flag : Boolean := False;
      Command_Commit_Released : Boolean := True;
      Result_Committed_Flag : Boolean := False;
      Result_Commit_Released : Boolean := True;
      Close_Committed_Flag : Boolean := False;
      Close_Commit_Released : Boolean := True;
      Closed_Descriptor : Integer := -1;
      Duplicate_Transferred_Flag : Boolean := False;
      Duplicate_Transfer_Released : Boolean := True;
      Transferred_Duplicate_Read : Integer := -1;
      Transferred_Duplicate_Write : Integer := -1;
   end Control;

   protected body Control is
      procedure Arm_Exceptional_Release is
      begin
         Fail_Materialization := True;
         Fail_Release := True;
      end Arm_Exceptional_Release;

      procedure Arm_Spawned_Release is
      begin
         Fail_Materialization := False;
         Fail_Release := True;
      end Arm_Spawned_Release;

      procedure Arm_Spawn_Cleanup is
      begin
         Fail_Spawn_Cleanup := True;
      end Arm_Spawn_Cleanup;

      procedure Take_Spawn_Cleanup (Armed : out Boolean) is
      begin
         Armed := Fail_Spawn_Cleanup;
         Fail_Spawn_Cleanup := False;
      end Take_Spawn_Cleanup;

      procedure Arm_Post_Primary is
      begin
         Fail_Post_Primary := True;
      end Arm_Post_Primary;

      procedure Check_Post_Primary is
         Fail : constant Boolean := Fail_Post_Primary;
      begin
         Fail_Post_Primary := False;
         if Fail then
            raise Program_Error with "injected post-primary process failure";
         end if;
      end Check_Post_Primary;

      procedure Arm_Close is
      begin
         Fail_Close := True;
      end Arm_Close;

      procedure Take_Close (Armed : out Boolean) is
      begin
         Armed := Fail_Close;
         Fail_Close := False;
      end Take_Close;

      procedure Arm_Duplicate is
      begin
         Fail_Duplicate := True;
      end Arm_Duplicate;

      procedure Take_Duplicate (Armed : out Boolean) is
      begin
         Armed := Fail_Duplicate;
         Fail_Duplicate := False;
      end Take_Duplicate;

      procedure Arm_Nonblocking is
      begin
         Fail_Nonblocking := True;
      end Arm_Nonblocking;

      procedure Take_Nonblocking (Armed : out Boolean) is
      begin
         Armed := Fail_Nonblocking;
         Fail_Nonblocking := False;
      end Take_Nonblocking;

      procedure Check_Materialization is
         Fail : constant Boolean := Fail_Materialization;
      begin
         Fail_Materialization := False;
         if Fail then
            raise Program_Error with "injected build-process materialization failure";
         end if;
      end Check_Materialization;

      procedure Check_Release is
         Fail : constant Boolean := Fail_Release;
      begin
         Fail_Release := False;
         if Fail then
            raise Program_Error with "injected build-process release failure";
         end if;
      end Check_Release;

      procedure Arm_Materialization_Pause is
      begin
         Materialization_Reached_Flag := False;
         Materialization_Released := False;
         C_Strings_Allocated := 0;
         C_Strings_Released := 0;
      end Arm_Materialization_Pause;

      procedure C_String_Allocated is
      begin
         C_Strings_Allocated := C_Strings_Allocated + 1;
      end C_String_Allocated;

      procedure C_String_Released is
      begin
         C_Strings_Released := C_Strings_Released + 1;
      end C_String_Released;

      procedure Materialization_Reached is
      begin
         Materialization_Reached_Flag := True;
      end Materialization_Reached;

      entry Wait_Materialization when Materialization_Reached_Flag is
      begin
         null;
      end Wait_Materialization;

      entry Wait_Materialization_Release when Materialization_Released is
      begin
         null;
      end Wait_Materialization_Release;

      procedure Release_Materialization is
      begin
         Materialization_Released := True;
      end Release_Materialization;

      procedure Read_Materialization_Counts (Allocated : out Natural; Released : out Natural) is
      begin
         Allocated := C_Strings_Allocated;
         Released := C_Strings_Released;
      end Read_Materialization_Counts;

      procedure Arm_Spawn_Pause is
      begin
         Spawn_Reached := False;
         Spawn_Released := False;
         Spawned_Child := -1;
      end Arm_Spawn_Pause;

      procedure Spawn_Published (Child : Integer) is
      begin
         Spawned_Child := Child;
         Spawn_Reached := True;
      end Spawn_Published;

      entry Wait_Spawn when Spawn_Reached is
      begin
         null;
      end Wait_Spawn;

      entry Wait_Spawn_Release when Spawn_Released is
      begin
         null;
      end Wait_Spawn_Release;

      procedure Release_Spawn is
      begin
         Spawn_Released := True;
      end Release_Spawn;

      procedure Read_Last_Spawn (Child : out Integer) is
      begin
         Child := Spawned_Child;
      end Read_Last_Spawn;

      procedure Arm_Pipe_Pause is
      begin
         Gate_Attempts := 0;
         Pipe_Open := False;
         Pipe_Released := False;
         Raw_Read_End := -1;
         Raw_Write_End := -1;
      end Arm_Pipe_Pause;

      procedure Gate_Attempt is
      begin
         Gate_Attempts := Gate_Attempts + 1;
      end Gate_Attempt;

      procedure Raw_Pipe_Open (Read_End : Integer; Write_End : Integer) is
      begin
         Raw_Read_End := Read_End;
         Raw_Write_End := Write_End;
         Pipe_Open := True;
      end Raw_Pipe_Open;

      procedure Read_Last_Raw_Pipe (Read_End : out Integer; Write_End : out Integer) is
      begin
         Read_End := Raw_Read_End;
         Write_End := Raw_Write_End;
      end Read_Last_Raw_Pipe;

      entry Wait_Two_Attempts when Gate_Attempts >= 2 is
      begin
         null;
      end Wait_Two_Attempts;

      entry Wait_Pipe_Open when Pipe_Open is
      begin
         null;
      end Wait_Pipe_Open;

      entry Wait_Pipe_Release when Pipe_Released is
      begin
         null;
      end Wait_Pipe_Release;

      procedure Release_Pipe is
      begin
         Pipe_Released := True;
      end Release_Pipe;

      procedure Arm_Gate_Grant_Pause is
      begin
         Gate_Granted_Flag := False;
         Gate_Grant_Released := False;
      end Arm_Gate_Grant_Pause;

      procedure Gate_Granted is
      begin
         Gate_Granted_Flag := True;
      end Gate_Granted;

      entry Wait_Gate_Granted when Gate_Granted_Flag is
      begin
         null;
      end Wait_Gate_Granted;

      entry Wait_Gate_Grant_Release when Gate_Grant_Released is
      begin
         null;
      end Wait_Gate_Grant_Release;

      procedure Release_Gate_Grant is
      begin
         Gate_Grant_Released := True;
      end Release_Gate_Grant;

      procedure Arm_Pipe_Transfer_Pause is
      begin
         Pipe_Transferred_Flag := False;
         Pipe_Transfer_Released := False;
         Transferred_Input_Read := -1;
         Transferred_Input_Write := -1;
         Transferred_Output_Read := -1;
         Transferred_Output_Write := -1;
         Transferred_Error_Read := -1;
         Transferred_Error_Write := -1;
      end Arm_Pipe_Transfer_Pause;

      procedure Pipe_Transferred
        (Input_Read   : Integer;
         Input_Write  : Integer;
         Output_Read  : Integer;
         Output_Write : Integer;
         Error_Read   : Integer;
         Error_Write  : Integer)
      is
      begin
         Transferred_Input_Read := Input_Read;
         Transferred_Input_Write := Input_Write;
         Transferred_Output_Read := Output_Read;
         Transferred_Output_Write := Output_Write;
         Transferred_Error_Read := Error_Read;
         Transferred_Error_Write := Error_Write;
         Pipe_Transferred_Flag := True;
      end Pipe_Transferred;

      entry Wait_Pipe_Transferred when Pipe_Transferred_Flag is
      begin
         null;
      end Wait_Pipe_Transferred;

      entry Wait_Pipe_Transfer_Release when Pipe_Transfer_Released is
      begin
         null;
      end Wait_Pipe_Transfer_Release;

      procedure Release_Pipe_Transfer is
      begin
         Pipe_Transfer_Released := True;
      end Release_Pipe_Transfer;

      procedure Read_Transferred_Pipes
        (Input_Read   : out Integer;
         Input_Write  : out Integer;
         Output_Read  : out Integer;
         Output_Write : out Integer;
         Error_Read   : out Integer;
         Error_Write  : out Integer)
      is
      begin
         Input_Read := Transferred_Input_Read;
         Input_Write := Transferred_Input_Write;
         Output_Read := Transferred_Output_Read;
         Output_Write := Transferred_Output_Write;
         Error_Read := Transferred_Error_Read;
         Error_Write := Transferred_Error_Write;
      end Read_Transferred_Pipes;

      procedure Arm_Command_Commit_Pause is
      begin
         Command_Committed_Flag := False;
         Command_Commit_Released := False;
      end Arm_Command_Commit_Pause;

      procedure Command_Committed is
      begin
         Command_Committed_Flag := True;
      end Command_Committed;

      entry Wait_Command_Committed when Command_Committed_Flag is
      begin
         null;
      end Wait_Command_Committed;

      entry Wait_Command_Commit_Release when Command_Commit_Released is
      begin
         null;
      end Wait_Command_Commit_Release;

      procedure Release_Command_Commit is
      begin
         Command_Commit_Released := True;
      end Release_Command_Commit;

      procedure Arm_Result_Commit_Pause is
      begin
         Result_Committed_Flag := False;
         Result_Commit_Released := False;
      end Arm_Result_Commit_Pause;

      procedure Result_Committed is
      begin
         Result_Committed_Flag := True;
      end Result_Committed;

      entry Wait_Result_Committed when Result_Committed_Flag is
      begin
         null;
      end Wait_Result_Committed;

      entry Wait_Result_Commit_Release when Result_Commit_Released is
      begin
         null;
      end Wait_Result_Commit_Release;

      procedure Release_Result_Commit is
      begin
         Result_Commit_Released := True;
      end Release_Result_Commit;

      procedure Arm_Close_Commit_Pause is
      begin
         Close_Committed_Flag := False;
         Close_Commit_Released := False;
         Closed_Descriptor := -1;
      end Arm_Close_Commit_Pause;

      procedure Close_Committed (Descriptor : Integer) is
      begin
         Closed_Descriptor := Descriptor;
         Close_Committed_Flag := True;
      end Close_Committed;

      entry Wait_Close_Committed when Close_Committed_Flag is
      begin
         null;
      end Wait_Close_Committed;

      entry Wait_Close_Commit_Release when Close_Commit_Released is
      begin
         null;
      end Wait_Close_Commit_Release;

      procedure Release_Close_Commit is
      begin
         Close_Commit_Released := True;
      end Release_Close_Commit;

      procedure Read_Last_Close (Descriptor : out Integer) is
      begin
         Descriptor := Closed_Descriptor;
      end Read_Last_Close;

      procedure Arm_Duplicate_Transfer_Pause is
      begin
         Duplicate_Transferred_Flag := False;
         Duplicate_Transfer_Released := False;
         Transferred_Duplicate_Read := -1;
         Transferred_Duplicate_Write := -1;
      end Arm_Duplicate_Transfer_Pause;

      procedure Duplicate_Transferred (Read_End : Integer; Write_End : Integer) is
      begin
         Transferred_Duplicate_Read := Read_End;
         Transferred_Duplicate_Write := Write_End;
         Duplicate_Transferred_Flag := True;
      end Duplicate_Transferred;

      entry Wait_Duplicate_Transferred when Duplicate_Transferred_Flag is
      begin
         null;
      end Wait_Duplicate_Transferred;

      entry Wait_Duplicate_Transfer_Release when Duplicate_Transfer_Released is
      begin
         null;
      end Wait_Duplicate_Transfer_Release;

      procedure Release_Duplicate_Transfer is
      begin
         Duplicate_Transfer_Released := True;
      end Release_Duplicate_Transfer;

      procedure Read_Transferred_Duplicates
        (Read_End : out Integer; Write_End : out Integer)
      is
      begin
         Read_End := Transferred_Duplicate_Read;
         Write_End := Transferred_Duplicate_Write;
      end Read_Transferred_Duplicates;
   end Control;

   procedure Arm_Exceptional_Release_Failure is
   begin
      Control.Arm_Exceptional_Release;
   end Arm_Exceptional_Release_Failure;

   procedure Arm_Spawned_Release_Failure is
   begin
      Control.Arm_Spawned_Release;
   end Arm_Spawned_Release_Failure;

   procedure Arm_Spawn_Cleanup_Failure is
   begin
      Control.Arm_Spawn_Cleanup;
   end Arm_Spawn_Cleanup_Failure;

   procedure Consume_Spawn_Cleanup_Failure (Armed : out Boolean) is
   begin
      Control.Take_Spawn_Cleanup (Armed);
   end Consume_Spawn_Cleanup_Failure;

   procedure Arm_Post_Primary_Failure is
   begin
      Control.Arm_Post_Primary;
   end Arm_Post_Primary_Failure;

   procedure Raise_If_Post_Primary_Failure is
   begin
      Control.Check_Post_Primary;
   end Raise_If_Post_Primary_Failure;

   procedure Arm_Close_Failure is
   begin
      Control.Arm_Close;
   end Arm_Close_Failure;

   procedure Consume_Close_Failure (Armed : out Boolean) is
   begin
      Control.Take_Close (Armed);
   end Consume_Close_Failure;

   procedure Arm_Duplicate_Failure is
   begin
      Control.Arm_Duplicate;
   end Arm_Duplicate_Failure;

   procedure Consume_Duplicate_Failure (Armed : out Boolean) is
   begin
      Control.Take_Duplicate (Armed);
   end Consume_Duplicate_Failure;

   procedure Arm_Nonblocking_Failure is
   begin
      Control.Arm_Nonblocking;
   end Arm_Nonblocking_Failure;

   procedure Consume_Nonblocking_Failure (Armed : out Boolean) is
   begin
      Control.Take_Nonblocking (Armed);
   end Consume_Nonblocking_Failure;

   procedure Raise_If_Materialization_Failure is
   begin
      Control.Check_Materialization;
   end Raise_If_Materialization_Failure;

   procedure Raise_If_Release_Failure is
   begin
      Control.Check_Release;
   end Raise_If_Release_Failure;

   procedure Arm_Materialization_Pause is
   begin
      Control.Arm_Materialization_Pause;
   end Arm_Materialization_Pause;

   procedure Note_C_String_Allocated is
   begin
      Control.C_String_Allocated;
   end Note_C_String_Allocated;

   procedure Note_C_String_Released is
   begin
      Control.C_String_Released;
   end Note_C_String_Released;

   procedure Note_Materialization is
   begin
      Control.Materialization_Reached;
   end Note_Materialization;

   procedure Wait_For_Materialization (Timeout : Duration; Reached : out Boolean) is
   begin
      select
         Control.Wait_Materialization;
         Reached := True;
      or
         delay Timeout;
         Reached := False;
      end select;
   end Wait_For_Materialization;

   procedure Wait_For_Materialization_Release (Timeout : Duration; Reached : out Boolean) is
   begin
      select
         Control.Wait_Materialization_Release;
         Reached := True;
      or
         delay Timeout;
         Reached := False;
      end select;
   end Wait_For_Materialization_Release;

   procedure Release_Materialization_Pause is
   begin
      Control.Release_Materialization;
   end Release_Materialization_Pause;

   procedure Materialization_Counts (Allocated : out Natural; Released : out Natural) is
   begin
      Control.Read_Materialization_Counts (Allocated, Released);
   end Materialization_Counts;

   procedure Arm_Spawn_Publish_Pause is
   begin
      Control.Arm_Spawn_Pause;
   end Arm_Spawn_Publish_Pause;

   procedure Note_Spawn_Published (Child : Integer) is
   begin
      Control.Spawn_Published (Child);
   end Note_Spawn_Published;

   procedure Wait_For_Spawn_Published (Timeout : Duration; Reached : out Boolean) is
   begin
      select
         Control.Wait_Spawn;
         Reached := True;
      or
         delay Timeout;
         Reached := False;
      end select;
   end Wait_For_Spawn_Published;

   procedure Wait_For_Spawn_Release (Timeout : Duration; Reached : out Boolean) is
   begin
      select
         Control.Wait_Spawn_Release;
         Reached := True;
      or
         delay Timeout;
         Reached := False;
      end select;
   end Wait_For_Spawn_Release;

   procedure Release_Spawn_Pause is
   begin
      Control.Release_Spawn;
   end Release_Spawn_Pause;

   procedure Last_Spawned_Child (Child : out Integer) is
   begin
      Control.Read_Last_Spawn (Child);
   end Last_Spawned_Child;

   procedure Arm_Raw_Pipe_Pause is
   begin
      Control.Arm_Pipe_Pause;
   end Arm_Raw_Pipe_Pause;

   procedure Note_Gate_Attempt is
   begin
      Control.Gate_Attempt;
   end Note_Gate_Attempt;

   procedure Note_Raw_Pipe_Open (Read_End : Integer; Write_End : Integer) is
   begin
      Control.Raw_Pipe_Open (Read_End, Write_End);
   end Note_Raw_Pipe_Open;

   procedure Last_Raw_Pipe (Read_End : out Integer; Write_End : out Integer) is
   begin
      Control.Read_Last_Raw_Pipe (Read_End, Write_End);
   end Last_Raw_Pipe;

   procedure Wait_For_Two_Gate_Attempts (Timeout : Duration; Reached : out Boolean) is
   begin
      select
         Control.Wait_Two_Attempts;
         Reached := True;
      or
         delay Timeout;
         Reached := False;
      end select;
   end Wait_For_Two_Gate_Attempts;

   procedure Wait_For_Raw_Pipe_Open (Timeout : Duration; Reached : out Boolean) is
   begin
      select
         Control.Wait_Pipe_Open;
         Reached := True;
      or
         delay Timeout;
         Reached := False;
      end select;
   end Wait_For_Raw_Pipe_Open;

   procedure Wait_For_Raw_Pipe_Release (Timeout : Duration; Reached : out Boolean) is
   begin
      select
         Control.Wait_Pipe_Release;
         Reached := True;
      or
         delay Timeout;
         Reached := False;
      end select;
   end Wait_For_Raw_Pipe_Release;

   procedure Release_Raw_Pipe_Pause is
   begin
      Control.Release_Pipe;
   end Release_Raw_Pipe_Pause;

   procedure Arm_Gate_Grant_Pause is
   begin
      Control.Arm_Gate_Grant_Pause;
   end Arm_Gate_Grant_Pause;

   procedure Note_Gate_Granted is
   begin
      Control.Gate_Granted;
   end Note_Gate_Granted;

   procedure Wait_For_Gate_Granted (Timeout : Duration; Reached : out Boolean) is
   begin
      select
         Control.Wait_Gate_Granted;
         Reached := True;
      or
         delay Timeout;
         Reached := False;
      end select;
   end Wait_For_Gate_Granted;

   procedure Wait_For_Gate_Grant_Release (Timeout : Duration; Reached : out Boolean) is
   begin
      select
         Control.Wait_Gate_Grant_Release;
         Reached := True;
      or
         delay Timeout;
         Reached := False;
      end select;
   end Wait_For_Gate_Grant_Release;

   procedure Release_Gate_Grant_Pause is
   begin
      Control.Release_Gate_Grant;
   end Release_Gate_Grant_Pause;

   procedure Arm_Pipe_Transfer_Pause is
   begin
      Control.Arm_Pipe_Transfer_Pause;
   end Arm_Pipe_Transfer_Pause;

   procedure Note_Pipe_Transferred
     (Input_Read   : Integer;
      Input_Write  : Integer;
      Output_Read  : Integer;
      Output_Write : Integer;
      Error_Read   : Integer;
      Error_Write  : Integer)
   is
   begin
      Control.Pipe_Transferred
        (Input_Read, Input_Write, Output_Read, Output_Write, Error_Read, Error_Write);
   end Note_Pipe_Transferred;

   procedure Wait_For_Pipe_Transferred (Timeout : Duration; Reached : out Boolean) is
   begin
      select
         Control.Wait_Pipe_Transferred;
         Reached := True;
      or
         delay Timeout;
         Reached := False;
      end select;
   end Wait_For_Pipe_Transferred;

   procedure Wait_For_Pipe_Transfer_Release (Timeout : Duration; Reached : out Boolean) is
   begin
      select
         Control.Wait_Pipe_Transfer_Release;
         Reached := True;
      or
         delay Timeout;
         Reached := False;
      end select;
   end Wait_For_Pipe_Transfer_Release;

   procedure Release_Pipe_Transfer_Pause is
   begin
      Control.Release_Pipe_Transfer;
   end Release_Pipe_Transfer_Pause;

   procedure Last_Transferred_Pipes
     (Input_Read   : out Integer;
      Input_Write  : out Integer;
      Output_Read  : out Integer;
      Output_Write : out Integer;
      Error_Read   : out Integer;
      Error_Write  : out Integer)
   is
   begin
      Control.Read_Transferred_Pipes
        (Input_Read, Input_Write, Output_Read, Output_Write, Error_Read, Error_Write);
   end Last_Transferred_Pipes;

   procedure Arm_Command_Commit_Pause is
   begin
      Control.Arm_Command_Commit_Pause;
   end Arm_Command_Commit_Pause;

   procedure Note_Command_Committed is
   begin
      Control.Command_Committed;
   end Note_Command_Committed;

   procedure Wait_For_Command_Committed (Timeout : Duration; Reached : out Boolean) is
   begin
      select
         Control.Wait_Command_Committed;
         Reached := True;
      or
         delay Timeout;
         Reached := False;
      end select;
   end Wait_For_Command_Committed;

   procedure Wait_For_Command_Commit_Release (Timeout : Duration; Reached : out Boolean) is
   begin
      select
         Control.Wait_Command_Commit_Release;
         Reached := True;
      or
         delay Timeout;
         Reached := False;
      end select;
   end Wait_For_Command_Commit_Release;

   procedure Release_Command_Commit_Pause is
   begin
      Control.Release_Command_Commit;
   end Release_Command_Commit_Pause;

   procedure Arm_Result_Commit_Pause is
   begin
      Control.Arm_Result_Commit_Pause;
   end Arm_Result_Commit_Pause;

   procedure Note_Result_Committed is
   begin
      Control.Result_Committed;
   end Note_Result_Committed;

   procedure Wait_For_Result_Committed (Timeout : Duration; Reached : out Boolean) is
   begin
      select
         Control.Wait_Result_Committed;
         Reached := True;
      or
         delay Timeout;
         Reached := False;
      end select;
   end Wait_For_Result_Committed;

   procedure Wait_For_Result_Commit_Release (Timeout : Duration; Reached : out Boolean) is
   begin
      select
         Control.Wait_Result_Commit_Release;
         Reached := True;
      or
         delay Timeout;
         Reached := False;
      end select;
   end Wait_For_Result_Commit_Release;

   procedure Release_Result_Commit_Pause is
   begin
      Control.Release_Result_Commit;
   end Release_Result_Commit_Pause;

   procedure Arm_Close_Commit_Pause is
   begin
      Control.Arm_Close_Commit_Pause;
   end Arm_Close_Commit_Pause;

   procedure Note_Close_Committed (Descriptor : Integer) is
   begin
      Control.Close_Committed (Descriptor);
   end Note_Close_Committed;

   procedure Wait_For_Close_Committed (Timeout : Duration; Reached : out Boolean) is
   begin
      select
         Control.Wait_Close_Committed;
         Reached := True;
      or
         delay Timeout;
         Reached := False;
      end select;
   end Wait_For_Close_Committed;

   procedure Wait_For_Close_Commit_Release (Timeout : Duration; Reached : out Boolean) is
   begin
      select
         Control.Wait_Close_Commit_Release;
         Reached := True;
      or
         delay Timeout;
         Reached := False;
      end select;
   end Wait_For_Close_Commit_Release;

   procedure Release_Close_Commit_Pause is
   begin
      Control.Release_Close_Commit;
   end Release_Close_Commit_Pause;

   procedure Last_Closed_Descriptor (Descriptor : out Integer) is
   begin
      Control.Read_Last_Close (Descriptor);
   end Last_Closed_Descriptor;

   procedure Arm_Duplicate_Transfer_Pause is
   begin
      Control.Arm_Duplicate_Transfer_Pause;
   end Arm_Duplicate_Transfer_Pause;

   procedure Note_Duplicate_Transferred (Read_End : Integer; Write_End : Integer) is
   begin
      Control.Duplicate_Transferred (Read_End, Write_End);
   end Note_Duplicate_Transferred;

   procedure Wait_For_Duplicate_Transferred (Timeout : Duration; Reached : out Boolean) is
   begin
      select
         Control.Wait_Duplicate_Transferred;
         Reached := True;
      or
         delay Timeout;
         Reached := False;
      end select;
   end Wait_For_Duplicate_Transferred;

   procedure Wait_For_Duplicate_Transfer_Release
     (Timeout : Duration; Reached : out Boolean)
   is
   begin
      select
         Control.Wait_Duplicate_Transfer_Release;
         Reached := True;
      or
         delay Timeout;
         Reached := False;
      end select;
   end Wait_For_Duplicate_Transfer_Release;

   procedure Release_Duplicate_Transfer_Pause is
   begin
      Control.Release_Duplicate_Transfer;
   end Release_Duplicate_Transfer_Pause;

   procedure Last_Transferred_Duplicates (Read_End : out Integer; Write_End : out Integer) is
   begin
      Control.Read_Transferred_Duplicates (Read_End, Write_End);
   end Last_Transferred_Duplicates;

   procedure Raise_Fail_Stop (Location : Positive; Code : Integer) is
   begin
      raise Program_Error with
        "injected observation of build-process fail-stop"
        & Positive'Image (Location)
        & Integer'Image (Code);
   end Raise_Fail_Stop;
end Flyology_Serde_Generator.Build_Process_Test_Hooks;
