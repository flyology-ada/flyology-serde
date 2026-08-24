with Interfaces.C;

with Flyology_Serde_Generator.Build_Process_Test_Hooks;

procedure Flyology_Serde_Generator.Build_Processes.Pipe_Transfer_Abort_Test is
   package Test_Hooks renames Flyology_Serde_Generator.Build_Process_Test_Hooks;
   use type Interfaces.C.int;

   function Descriptor_Is_Closed (Descriptor : Interfaces.C.int) return Interfaces.C.int with
     Import, Convention => C, External_Name => "flyology_serde_test_descriptor_is_closed";

   Limits : constant Process_Limits :=
     (Maximum_Argument_Count            => 8,
      Maximum_Argument_Bytes            => 1_024,
      Maximum_Environment_Count         => 1,
      Maximum_Environment_Bytes         => 64,
      Maximum_Standard_Output_Bytes     => 16,
      Maximum_Standard_Error_Bytes      => 16,
      Timeout_Milliseconds              => 1_000,
      Observation_Interval_Milliseconds => 1,
      Maximum_Read_Chunk_Bytes          => 16);
   Budget_Limits : constant Budgets.Limits :=
     (Maximum_Input_Bytes => 1_024, Maximum_Work_Units => 100_000);

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   procedure Require_Closed (Descriptor : Integer) is
   begin
      if Descriptor >= 0 then
         Require
           (Descriptor_Is_Closed (Interfaces.C.int (Descriptor)) = 1,
            "pipe-transfer abort leaked a transferred descriptor");
      end if;
   end Require_Closed;

   Budget      : aliased Budgets.Budget;
   Initialized : Boolean := False;
   Session     : Budgets.Session_Tag;
   Command     : Build_Processes.Command (Budget'Access);
   Value       : Build_Processes.Result (Budget'Access);
   Status      : Run_Status := Ready_To_Run;
   System_Code : Interfaces.C.int := 0;
   Build_State : Build_Status := Build_Succeeded;
   Reached     : Boolean := False;
   Input_Read, Input_Write, Output_Read, Output_Write, Error_Read, Error_Write : Integer := -1;

   task Runner is
      entry Start;
   end Runner;

   task body Runner is
   begin
      accept Start;
      Run (Command, Session, Value, Status, System_Code);
   end Runner;
begin
   Budgets.Initialize (Budget_Limits, Budget, Initialized);
   Require (Initialized, "pipe-transfer abort budget did not initialize");
   Session := Budgets.Current_Session (Budget);
   Initialize (Command, Session, Limits, "/bin/sh", Build_State);
   Add_Argument (Command, Session, "-c", Build_State);
   Add_Argument (Command, Session, "exit 0", Build_State);
   Add_Argument (Command, Session, "arg-zero", Build_State);
   Seal (Command, Session, Build_State);
   Require (Build_State = Build_Succeeded, "pipe-transfer abort command did not build");

   Test_Hooks.Arm_Pipe_Transfer_Pause;
   Runner.Start;
   Test_Hooks.Wait_For_Pipe_Transferred (2.0, Reached);
   Require (Reached, "abort did not reach the pipe ownership-transfer window");
   Test_Hooks.Last_Transferred_Pipes
     (Input_Read, Input_Write, Output_Read, Output_Write, Error_Read, Error_Write);
   abort Runner;
   Test_Hooks.Release_Pipe_Transfer_Pause;
   for Attempt in 1 .. 2_000 loop
      exit when Runner'Terminated;
      delay 0.001;
   end loop;
   Require (Runner'Terminated, "pipe-transfer abort did not finish cleanup");
   Require_Closed (Input_Read);
   Require_Closed (Input_Write);
   Require_Closed (Output_Read);
   Require_Closed (Output_Write);
   Require_Closed (Error_Read);
   Require_Closed (Error_Write);
end Flyology_Serde_Generator.Build_Processes.Pipe_Transfer_Abort_Test;
