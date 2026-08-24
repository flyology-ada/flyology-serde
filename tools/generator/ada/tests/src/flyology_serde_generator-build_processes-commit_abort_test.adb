with Interfaces;
with Interfaces.C;

with Flyology_Serde_Generator.Build_Process_Test_Hooks;

procedure Flyology_Serde_Generator.Build_Processes.Commit_Abort_Test is
   package Test_Hooks renames Flyology_Serde_Generator.Build_Process_Test_Hooks;
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

   Budget      : aliased Budgets.Budget;
   Initialized : Boolean := False;
   Session     : Budgets.Session_Tag;
   Command     : Build_Processes.Command (Budget'Access);
   Value       : Build_Processes.Result (Budget'Access);
   Build_State : Build_Status := Build_Succeeded;
   Run_State   : Run_Status := Ready_To_Run;
   System_Code : Interfaces.C.int := 0;
   Reached     : Boolean := False;

   task Command_Builder is
      entry Start;
   end Command_Builder;

   task body Command_Builder is
   begin
      accept Start;
      Initialize (Command, Session, Limits, "/bin/sh", Build_State);
   end Command_Builder;

   task Runner is
      entry Start;
   end Runner;

   task body Runner is
   begin
      accept Start;
      Run (Command, Session, Value, Run_State, System_Code);
   end Runner;
begin
   Budgets.Initialize (Budget_Limits, Budget, Initialized);
   Require (Initialized, "commit-abort budget did not initialize");
   Session := Budgets.Current_Session (Budget);

   Initialize (Command, Session, Limits, "/bin/sh", Build_State);
   Add_Argument (Command, Session, "-c", Build_State);
   Add_Argument (Command, Session, "printf old", Build_State);
   Add_Argument (Command, Session, "arg-zero", Build_State);
   Seal (Command, Session, Build_State);
   Require (Build_State = Build_Succeeded, "prior command did not build");
   Run (Command, Session, Value, Run_State, System_Code);
   Require (Run_State = Run_Completed, "prior result did not complete");

   Test_Hooks.Arm_Command_Commit_Pause;
   Command_Builder.Start;
   Test_Hooks.Wait_For_Command_Committed (2.0, Reached);
   Require (Reached, "abort did not reach the command commit window");
   abort Command_Builder;
   Test_Hooks.Release_Command_Commit_Pause;
   for Attempt in 1 .. 2_000 loop
      exit when Command_Builder'Terminated;
      delay 0.001;
   end loop;
   Require (Command_Builder'Terminated, "command-commit abort did not finish ownership move");
   Require (Build_State = Build_Succeeded, "command-commit abort did not publish one candidate");

   Add_Argument (Command, Session, "-c", Build_State);
   Add_Argument (Command, Session, "printf committed", Build_State);
   Add_Argument (Command, Session, "arg-zero", Build_State);
   Seal (Command, Session, Build_State);
   Require (Build_State = Build_Succeeded, "committed command was not usable after abort");

   Run_State := Ready_To_Run;
   System_Code := 0;
   Reached := False;
   Test_Hooks.Arm_Result_Commit_Pause;
   Runner.Start;
   Test_Hooks.Wait_For_Result_Committed (2.0, Reached);
   Require (Reached, "abort did not reach the result commit window");
   abort Runner;
   Test_Hooks.Release_Result_Commit_Pause;
   for Attempt in 1 .. 2_000 loop
      exit when Runner'Terminated;
      delay 0.001;
   end loop;
   Require (Runner'Terminated, "result-commit abort did not finish ownership move");
   declare
      Length : Interfaces.Unsigned_64 := 0;
      Query  : Query_Status := Query_Succeeded;
      Buffer : String (1 .. 9);
      Written : Natural := 0;
   begin
      Standard_Output_Length (Value, Session, Length, Query);
      Copy_Standard_Output (Value, Session, Buffer, Written, Query);
      Require
        (Query = Query_Succeeded
         and then Length = 9
         and then Written = 9
         and then Buffer = "committed",
         "result commit left duplicate or dangling ownership after abort");
   end;
end Flyology_Serde_Generator.Build_Processes.Commit_Abort_Test;
