with Interfaces.C;

with Flyology_Serde_Generator.Build_Process_ABI;
with Flyology_Serde_Generator.Build_Process_Test_Hooks;

procedure Flyology_Serde_Generator.Build_Processes.Setup_Failure_Test is
   package ABI renames Flyology_Serde_Generator.Build_Process_ABI;
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
      Timeout_Milliseconds              => 2_000,
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
begin
   Budgets.Initialize (Budget_Limits, Budget, Initialized);
   Require (Initialized, "setup-failure budget did not initialize");
   Session := Budgets.Current_Session (Budget);
   Initialize (Command, Session, Limits, "/bin/sh", Build_State);
   Add_Argument (Command, Session, "-c", Build_State);
   Add_Argument (Command, Session, "printf ok", Build_State);
   Add_Argument (Command, Session, "arg-zero", Build_State);
   Seal (Command, Session, Build_State);
   Require (Build_State = Build_Succeeded, "setup-failure command did not build");

   Test_Hooks.Arm_Duplicate_Failure;
   Run (Command, Session, Value, Status, System_Code);
   Require
     (Status = Run_System_Failed
      and then System_Code = ABI.Errno_Invalid
      and then Budgets.Current_State (Budget) = Budgets.Active
      and then Value.Data.Value = null,
      "partial duplicate failure damaged ownership or runner reuse");

   Test_Hooks.Arm_Nonblocking_Failure;
   Status := Ready_To_Run;
   System_Code := -1;
   Run (Command, Session, Value, Status, System_Code);
   Require
     (Status = Run_System_Failed
      and then System_Code = ABI.Errno_Invalid
      and then Budgets.Current_State (Budget) = Budgets.Active
      and then Value.Data.Value = null,
      "partial nonblocking failure damaged ownership or runner reuse");

   Status := Ready_To_Run;
   System_Code := -1;
   Run (Command, Session, Value, Status, System_Code);
   Require
     (Status = Run_Completed
      and then System_Code = 0
      and then Budgets.Current_State (Budget) = Budgets.Active
      and then Value.Data.Value /= null,
      "runner did not remain reusable after clean setup failures");
end Flyology_Serde_Generator.Build_Processes.Setup_Failure_Test;
