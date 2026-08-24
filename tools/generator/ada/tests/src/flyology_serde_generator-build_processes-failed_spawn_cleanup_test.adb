with Interfaces.C;

with Flyology_Serde_Generator.Build_Process_Test_Hooks;

procedure Flyology_Serde_Generator.Build_Processes.Failed_Spawn_Cleanup_Test is
   package Test_Hooks renames Flyology_Serde_Generator.Build_Process_Test_Hooks;
   use type Budgets.Budget_State;
   use type Interfaces.C.int;

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
   Child       : Integer := -2;
begin
   Budgets.Initialize (Budget_Limits, Budget, Initialized);
   Require (Initialized, "failed-spawn cleanup budget did not initialize");
   Session := Budgets.Current_Session (Budget);
   Initialize
     (Command, Session, Limits, "/flyology-serde/no-such-executable", Build_State);
   Seal (Command, Session, Build_State);
   Require (Build_State = Build_Succeeded, "failed-spawn cleanup command did not build");

   Test_Hooks.Arm_Spawn_Cleanup_Failure;
   Run (Command, Session, Value, Status, System_Code);
   Test_Hooks.Last_Spawned_Child (Child);
   Require
     (Status = Run_Spawn_Failed
      and then System_Code /= 0
      and then Budgets.Current_State (Budget) = Budgets.Failed
      and then Value.Data.Value = null
      and then Child = -1,
      "failed spawn did not preserve its primary or safely contain cleanup damage");
end Flyology_Serde_Generator.Build_Processes.Failed_Spawn_Cleanup_Test;
