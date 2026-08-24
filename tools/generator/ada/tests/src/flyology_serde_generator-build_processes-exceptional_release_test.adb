with Interfaces.C;

with Flyology_Serde_Generator.Build_Process_Test_Hooks;

procedure Flyology_Serde_Generator.Build_Processes.Exceptional_Release_Test is
   package Test_Hooks renames Flyology_Serde_Generator.Build_Process_Test_Hooks;
   use type Budgets.Budget_State;
   use type Budgets.Usage;
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
         "exceptional-release command status"
         & Build_Status'Image (Status)
         & Budgets.Budget_State'Image (Budgets.Current_State (Budget)));
   end Build;

   First_Budget  : aliased Budgets.Budget;
   Second_Budget : aliased Budgets.Budget;
   Initialized   : Boolean := False;
   First_Session : Budgets.Session_Tag;
   Second_Session : Budgets.Session_Tag;
   Prior_Command : Command (First_Budget'Access);
   Fault_Command : Command (First_Budget'Access);
   Probe_Command : Command (Second_Budget'Access);
   Prior_Result  : Result (First_Budget'Access);
   Probe_Result  : Result (Second_Budget'Access);
   Prior_Pointer : Result_Payload_Access;
   Status        : Run_Status := Ready_To_Run;
   System_Code   : Interfaces.C.int := -1;
   Before        : Budgets.Usage;
begin
   Budgets.Initialize (Budget_Limits, First_Budget, Initialized);
   Require (Initialized, "exceptional-release budget did not initialize");
   First_Session := Budgets.Current_Session (First_Budget);
   Build (First_Budget, First_Session, Prior_Command, "printf prior");
   Run (Prior_Command, First_Session, Prior_Result, Status, System_Code);
   Require (Status = Run_Completed, "exceptional-release prior result did not complete");
   Prior_Pointer := Prior_Result.Data.Value;
   Require (Prior_Pointer /= null, "exceptional-release prior result was empty");

   Build (First_Budget, First_Session, Fault_Command, "exit 0");
   Budgets.Initialize (Budget_Limits, Second_Budget, Initialized);
   Require (Initialized, "runner-poison probe budget did not initialize");
   Second_Session := Budgets.Current_Session (Second_Budget);
   Build (Second_Budget, Second_Session, Probe_Command, "exit 0");
   Before := Budgets.Current_Usage (Second_Budget);

   Test_Hooks.Arm_Exceptional_Release_Failure;
   Status := Ready_To_Run;
   System_Code := -1;
   Run (Fault_Command, First_Session, Prior_Result, Status, System_Code);
   Require
     (Status = Run_Internal_Failure
      and then System_Code = 0
      and then Budgets.Current_State (First_Budget) = Budgets.Failed
      and then Prior_Result.Data.Value = Prior_Pointer,
      "exceptional release did not poison and preserve its prior result");

   Status := Ready_To_Run;
   Run (Probe_Command, Second_Session, Probe_Result, Status, System_Code);
   Require
     (Status = Run_Runner_Poisoned
      and then Budgets.Current_Usage (Second_Budget) = Before,
      "exceptional release did not fail-stop later runner use");
end Flyology_Serde_Generator.Build_Processes.Exceptional_Release_Test;
