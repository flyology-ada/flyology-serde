with Interfaces.C;

with Flyology_Serde_Generator.Build_Process_Test_Hooks;

procedure Flyology_Serde_Generator.Build_Processes.Materialization_Abort_Test is
   package Test_Hooks renames Flyology_Serde_Generator.Build_Process_Test_Hooks;

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

   Budget      : aliased Budgets.Budget;
   Initialized : Boolean := False;
   Session     : Budgets.Session_Tag;
   Command     : Build_Processes.Command (Budget'Access);
   Value       : Build_Processes.Result (Budget'Access);
   Status      : Run_Status := Ready_To_Run;
   System_Code : Interfaces.C.int := 0;
   Build_State : Build_Status := Build_Succeeded;
   Reached     : Boolean := False;
   Allocated   : Natural := 0;
   Released    : Natural := 0;

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
   Require (Initialized, "materialization-abort budget did not initialize");
   Session := Budgets.Current_Session (Budget);
   Initialize (Command, Session, Limits, "/bin/sh", Build_State);
   Add_Argument (Command, Session, "-c", Build_State);
   Add_Argument (Command, Session, "exit 0", Build_State);
   Add_Argument (Command, Session, "arg-zero", Build_State);
   Seal (Command, Session, Build_State);
   Require (Build_State = Build_Succeeded, "materialization-abort command did not build");

   Test_Hooks.Arm_Materialization_Pause;
   Runner.Start;
   Test_Hooks.Wait_For_Materialization (2.0, Reached);
   Require (Reached, "abort did not reach C-string ownership publication");
   abort Runner;
   Test_Hooks.Release_Materialization_Pause;
   for Attempt in 1 .. 2_000 loop
      exit when Runner'Terminated;
      delay 0.001;
   end loop;
   Require (Runner'Terminated, "materialization abort did not finish cleanup");
   Test_Hooks.Materialization_Counts (Allocated, Released);
   Require
     (Allocated > 0 and then Released = Allocated,
      "materialization abort counts"
      & Natural'Image (Allocated)
      & "/"
      & Natural'Image (Released));
end Flyology_Serde_Generator.Build_Processes.Materialization_Abort_Test;
