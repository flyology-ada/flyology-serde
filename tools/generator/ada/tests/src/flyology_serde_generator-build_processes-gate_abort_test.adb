with Interfaces.C;

with Flyology_Serde_Generator.Build_Process_Test_Hooks;

procedure Flyology_Serde_Generator.Build_Processes.Gate_Abort_Test is
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
   First       : Build_Processes.Result (Budget'Access);
   Second      : Build_Processes.Result (Budget'Access);
   Status      : Run_Status := Ready_To_Run;
   Second_Status : Run_Status := Ready_To_Run;
   System_Code : Interfaces.C.int := 0;
   Second_Code : Interfaces.C.int := 0;
   Build_State : Build_Status := Build_Succeeded;
   Reached     : Boolean := False;

   task Runner is
      entry Start;
   end Runner;

   task body Runner is
   begin
      accept Start;
      Run (Command, Session, First, Status, System_Code);
   end Runner;
begin
   Budgets.Initialize (Budget_Limits, Budget, Initialized);
   Require (Initialized, "gate-abort budget did not initialize");
   Session := Budgets.Current_Session (Budget);
   Initialize (Command, Session, Limits, "/bin/sh", Build_State);
   Add_Argument (Command, Session, "-c", Build_State);
   Add_Argument (Command, Session, "exit 0", Build_State);
   Add_Argument (Command, Session, "arg-zero", Build_State);
   Seal (Command, Session, Build_State);
   Require (Build_State = Build_Succeeded, "gate-abort command did not build");

   Test_Hooks.Arm_Gate_Grant_Pause;
   Runner.Start;
   Test_Hooks.Wait_For_Gate_Granted (2.0, Reached);
   Require (Reached, "abort did not reach the gate ownership window");
   abort Runner;
   Test_Hooks.Release_Gate_Grant_Pause;
   for Attempt in 1 .. 2_000 loop
      exit when Runner'Terminated;
      delay 0.001;
   end loop;
   Require (Runner'Terminated, "gate abort did not finish guard finalization");
   Run (Command, Session, Second, Second_Status, Second_Code);
   Require
     (Second_Status = Run_Runner_Poisoned,
      "gate abort left an unreachable busy gate or admitted another child");
end Flyology_Serde_Generator.Build_Processes.Gate_Abort_Test;
