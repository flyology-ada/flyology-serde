with Interfaces.C;

with Flyology_Serde_Generator.Build_Process_Test_Hooks;

procedure Flyology_Serde_Generator.Build_Processes.Duplicate_Transfer_Abort_Test is
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
   Read_End    : Integer := -1;
   Write_End   : Integer := -1;

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
   Require (Initialized, "duplicate-transfer abort budget did not initialize");
   Session := Budgets.Current_Session (Budget);
   Initialize (Command, Session, Limits, "/bin/sh", Build_State);
   Add_Argument (Command, Session, "-c", Build_State);
   Add_Argument (Command, Session, "exit 0", Build_State);
   Add_Argument (Command, Session, "arg-zero", Build_State);
   Seal (Command, Session, Build_State);
   Require (Build_State = Build_Succeeded, "duplicate-transfer abort command did not build");

   Test_Hooks.Arm_Duplicate_Transfer_Pause;
   Runner.Start;
   Test_Hooks.Wait_For_Duplicate_Transferred (2.0, Reached);
   Require (Reached, "abort did not reach duplicated-descriptor publication");
   Test_Hooks.Last_Transferred_Duplicates (Read_End, Write_End);
   Require (Read_End > 2 and then Write_End > 2, "duplicate-transfer hook retained invalid descriptors");
   abort Runner;
   Test_Hooks.Release_Duplicate_Transfer_Pause;
   for Attempt in 1 .. 2_000 loop
      exit when Runner'Terminated;
      delay 0.001;
   end loop;
   Require (Runner'Terminated, "duplicate-transfer abort did not finish cleanup");
   Require
     (Descriptor_Is_Closed (Interfaces.C.int (Read_End)) = 1
      and then Descriptor_Is_Closed (Interfaces.C.int (Write_End)) = 1,
      "duplicate-transfer abort lost the only published descriptor owner");
end Flyology_Serde_Generator.Build_Processes.Duplicate_Transfer_Abort_Test;
