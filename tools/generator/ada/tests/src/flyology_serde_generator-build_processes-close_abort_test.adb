with Interfaces.C;

with Flyology_Serde_Generator.Build_Process_ABI;
with Flyology_Serde_Generator.Build_Process_Test_Hooks;

procedure Flyology_Serde_Generator.Build_Processes.Close_Abort_Test is
   package ABI renames Flyology_Serde_Generator.Build_Process_ABI;
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

   Budget      : aliased Budgets.Budget;
   Initialized : Boolean := False;
   Session     : Budgets.Session_Tag;
   Command     : Build_Processes.Command (Budget'Access);
   Value       : Build_Processes.Result (Budget'Access);
   Status      : Run_Status := Ready_To_Run;
   System_Code : Interfaces.C.int := 0;
   Build_State : Build_Status := Build_Succeeded;
   Reached     : Boolean := False;
   Closed      : Integer := -1;
   Replacement : aliased ABI.Descriptor_Pair := [others => -1];

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
   Require (Initialized, "close-abort budget did not initialize");
   Session := Budgets.Current_Session (Budget);
   Initialize (Command, Session, Limits, "/bin/sh", Build_State);
   Add_Argument (Command, Session, "-c", Build_State);
   Add_Argument (Command, Session, "exit 0", Build_State);
   Add_Argument (Command, Session, "arg-zero", Build_State);
   Seal (Command, Session, Build_State);
   Require (Build_State = Build_Succeeded, "close-abort command did not build");

   Test_Hooks.Arm_Close_Commit_Pause;
   Runner.Start;
   Test_Hooks.Wait_For_Close_Committed (2.0, Reached);
   Require (Reached, "abort did not reach the close ownership commit");
   Test_Hooks.Last_Closed_Descriptor (Closed);
   Require (Closed >= 0, "close ownership hook retained no descriptor");
   Require (ABI.Pipe (Replacement'Address) = 0, "could not reuse a descriptor during close pause");
   Require
     (Integer (Replacement (0)) = Closed or else Integer (Replacement (1)) = Closed,
      "host did not reuse the closed descriptor needed by the regression test");
   abort Runner;
   Test_Hooks.Release_Close_Commit_Pause;
   for Attempt in 1 .. 2_000 loop
      exit when Runner'Terminated;
      delay 0.001;
   end loop;
   Require (Runner'Terminated, "close abort did not finish cleanup");
   Require
     (Descriptor_Is_Closed (Replacement (0)) = 0
      and then Descriptor_Is_Closed (Replacement (1)) = 0,
      "close abort closed a descriptor reused after ownership-slot invalidation");
   Require (ABI.Close (Replacement (0)) = 0, "close-abort test could not release replacement read end");
   Require (ABI.Close (Replacement (1)) = 0, "close-abort test could not release replacement write end");
end Flyology_Serde_Generator.Build_Processes.Close_Abort_Test;
