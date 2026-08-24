with Interfaces.C;

with Flyology_Serde_Generator.Build_Process_Test_Hooks;

procedure Flyology_Serde_Generator.Build_Processes.Spawned_Release_Test is
   package Test_Hooks renames Flyology_Serde_Generator.Build_Process_Test_Hooks;
   use type Budgets.Budget_State;
   use type Interfaces.C.int;
   use type Interfaces.Unsigned_64;

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

   procedure Build
     (Budget  : aliased in out Budgets.Budget;
      Session : Budgets.Session_Tag;
      Into    : in out Command;
      Script  : String)
   is
      Status : Build_Status := Build_Succeeded;
   begin
      Initialize (Into, Session, Limits, "/bin/sh", Status);
      Add_Argument (Into, Session, "-c", Status);
      Add_Argument (Into, Session, Script, Status);
      Add_Argument (Into, Session, "arg-zero", Status);
      Seal (Into, Session, Status);
      Require
        (Status = Build_Succeeded and then Budgets.Current_State (Budget) = Budgets.Active,
         "spawned-release command status"
         & Build_Status'Image (Status)
         & Budgets.Budget_State'Image (Budgets.Current_State (Budget)));
   end Build;

   Budget        : aliased Budgets.Budget;
   Probe_Budget  : aliased Budgets.Budget;
   Initialized   : Boolean := False;
   Session       : Budgets.Session_Tag;
   Probe_Session : Budgets.Session_Tag;
   Prior_Command : Command (Budget'Access);
   Fault_Command : Command (Budget'Access);
   Probe_Command : Command (Probe_Budget'Access);
   Value         : Result (Budget'Access);
   Probe_Value   : Result (Probe_Budget'Access);
   Prior_Pointer : Result_Payload_Access;
   Status        : Run_Status := Ready_To_Run;
   System_Code   : Interfaces.C.int := -1;
   Before        : Budgets.Usage;
   After         : Budgets.Usage;
begin
   Budgets.Initialize (Budget_Limits, Budget, Initialized);
   Require (Initialized, "spawned-release budget did not initialize");
   Session := Budgets.Current_Session (Budget);
   Build (Budget, Session, Prior_Command, "printf prior");
   Run (Prior_Command, Session, Value, Status, System_Code);
   Require (Status = Run_Completed, "spawned-release prior result did not complete");
   Prior_Pointer := Value.Data.Value;
   Require (Prior_Pointer /= null, "spawned-release prior result was empty");

   Build (Budget, Session, Fault_Command, "/bin/sleep 30");
   Budgets.Initialize (Budget_Limits, Probe_Budget, Initialized);
   Require (Initialized, "spawned-release probe budget did not initialize");
   Probe_Session := Budgets.Current_Session (Probe_Budget);
   Build (Probe_Budget, Probe_Session, Probe_Command, "exit 0");
   Test_Hooks.Arm_Spawned_Release_Failure;
   Status := Ready_To_Run;
   System_Code := -1;
   Run (Fault_Command, Session, Value, Status, System_Code);
   Require
     (Status = Run_Internal_Failure
      and then System_Code = 0
      and then Budgets.Current_State (Budget) = Budgets.Failed
      and then Value.Data.Value = Prior_Pointer,
      "spawned release did not clean its child, poison, and preserve its prior result");

   Before := Budgets.Current_Usage (Probe_Budget);
   Status := Ready_To_Run;
   System_Code := -1;
   Run (Probe_Command, Probe_Session, Probe_Value, Status, System_Code);
   After := Budgets.Current_Usage (Probe_Budget);
   Require
     (Status = Run_Runner_Poisoned
      and then System_Code = 0
      and then Before.Input_Bytes = After.Input_Bytes
      and then Before.Work_Units = After.Work_Units,
      "spawned release damage did not poison later process-wide runner use");
end Flyology_Serde_Generator.Build_Processes.Spawned_Release_Test;
