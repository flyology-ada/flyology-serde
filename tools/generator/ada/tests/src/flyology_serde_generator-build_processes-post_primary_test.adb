with Interfaces.C;

with Flyology_Serde_Generator.Build_Process_Test_Hooks;

procedure Flyology_Serde_Generator.Build_Processes.Post_Primary_Test is
   package Test_Hooks renames Flyology_Serde_Generator.Build_Process_Test_Hooks;
   use type Budgets.Budget_State;
   use type Interfaces.C.int;

   Base_Limits : constant Process_Limits :=
     (Maximum_Argument_Count            => 8,
      Maximum_Argument_Bytes            => 1_024,
      Maximum_Environment_Count         => 1,
      Maximum_Environment_Bytes         => 64,
      Maximum_Standard_Output_Bytes     => 16,
      Maximum_Standard_Error_Bytes      => 16,
      Timeout_Milliseconds              => 2_000,
      Observation_Interval_Milliseconds => 1,
      Maximum_Read_Chunk_Bytes          => 16);
   Fault_Limits : constant Process_Limits :=
     (Base_Limits with delta Maximum_Standard_Output_Bytes => 0);
   Budget_Limits : constant Budgets.Limits :=
     (Maximum_Input_Bytes => 1_024, Maximum_Work_Units => 100_000);

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   procedure Build
     (Into    : in out Command;
      Session : Budgets.Session_Tag;
      Limits  : Process_Limits;
      Script  : String)
   is
      Status : Build_Status := Build_Succeeded;
   begin
      Initialize (Into, Session, Limits, "/bin/sh", Status);
      Add_Argument (Into, Session, "-c", Status);
      Add_Argument (Into, Session, Script, Status);
      Add_Argument (Into, Session, "arg-zero", Status);
      Seal (Into, Session, Status);
      Require (Status = Build_Succeeded, "post-primary command did not build");
   end Build;

   Budget        : aliased Budgets.Budget;
   Initialized   : Boolean := False;
   Session       : Budgets.Session_Tag;
   Prior_Command : Command (Budget'Access);
   Fault_Command : Command (Budget'Access);
   Value         : Result (Budget'Access);
   Prior_Pointer : Result_Payload_Access;
   Status        : Run_Status := Ready_To_Run;
   System_Code   : Interfaces.C.int := 0;
begin
   Budgets.Initialize (Budget_Limits, Budget, Initialized);
   Require (Initialized, "post-primary budget did not initialize");
   Session := Budgets.Current_Session (Budget);

   Build (Prior_Command, Session, Base_Limits, "printf prior");
   Run (Prior_Command, Session, Value, Status, System_Code);
   Require (Status = Run_Completed, "post-primary prior result did not complete");
   Prior_Pointer := Value.Data.Value;
   Require (Prior_Pointer /= null, "post-primary prior result was not published");

   Build (Fault_Command, Session, Fault_Limits, "printf x");
   Test_Hooks.Arm_Post_Primary_Failure;
   Status := Ready_To_Run;
   System_Code := -1;
   Run (Fault_Command, Session, Value, Status, System_Code);
   Require
     (Status = Run_Standard_Output_Limit
      and then System_Code = 0
      and then Budgets.Current_State (Budget) = Budgets.Failed
      and then Value.Data.Value = Prior_Pointer,
      "post-primary exception replaced the primary or published a candidate");
end Flyology_Serde_Generator.Build_Processes.Post_Primary_Test;
