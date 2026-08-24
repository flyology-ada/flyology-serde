with Ada.Directories;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Interfaces;
with Interfaces.C;
with System;

with Flyology_Serde_Generator.Build_Budgets;
with Flyology_Serde_Generator.Build_Process_ABI;
with Flyology_Serde_Generator.Build_Process_Test_Hooks;
with Flyology_Serde_Generator.Build_Processes;

package body Flyology_Serde_Generator.Build_Processes_Test_Facade is
   package Budgets renames Flyology_Serde_Generator.Build_Budgets;
   package ABI renames Flyology_Serde_Generator.Build_Process_ABI;
   package Test_Hooks renames Flyology_Serde_Generator.Build_Process_Test_Hooks;
   package Processes renames Flyology_Serde_Generator.Build_Processes;
   package US renames Ada.Strings.Unbounded;
   use type Budgets.Budget_State;
   use type Budgets.Usage;
   use type Interfaces.C.int;
   use type Interfaces.Unsigned_64;
   use type Processes.Build_Status;
   use type Processes.Query_Status;
   use type Processes.Run_Status;
   use type Processes.Termination_Kind;
   use type Processes.Pipe_Result_Action;

   function Deviate_Sigchld_Ignored return Interfaces.C.int with
     Import, Convention => C, External_Name => "flyology_serde_test_deviate_sigchld_ignored";
   function Deviate_Sigchld_No_Child_Wait return Interfaces.C.int with
     Import,
     Convention    => C,
     External_Name => "flyology_serde_test_deviate_sigchld_no_child_wait";
   function Restore_Sigchld return Interfaces.C.int with
     Import, Convention => C, External_Name => "flyology_serde_test_restore_sigchld";
   function Create_Private_Directory
     (Path : System.Address; Capacity : Interfaces.C.size_t) return Interfaces.C.int with
     Import,
     Convention    => C,
     External_Name => "flyology_serde_test_create_private_directory";
   function Remove_Private_Directory (Path : System.Address) return Interfaces.C.int with
     Import,
     Convention    => C,
     External_Name => "flyology_serde_test_remove_private_directory";

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   Full_Budget : constant Budgets.Limits :=
     (Maximum_Input_Bytes => 1_000_000,
      Maximum_Work_Units  => 10_000_000);

   function Limits
     (Output_Bytes : Interfaces.Unsigned_64 := 4_096;
      Error_Bytes  : Interfaces.Unsigned_64 := 4_096;
      Timeout      : Interfaces.Unsigned_64 := 2_000;
      Chunk        : Interfaces.Unsigned_64 := 4) return Processes.Process_Limits
   is
     (Maximum_Argument_Count            => 16,
      Maximum_Argument_Bytes            => 4_096,
      Maximum_Environment_Count         => 16,
      Maximum_Environment_Bytes         => 4_096,
      Maximum_Standard_Output_Bytes     => Output_Bytes,
      Maximum_Standard_Error_Bytes      => Error_Bytes,
      Timeout_Milliseconds              => Timeout,
      Observation_Interval_Milliseconds => 1,
      Maximum_Read_Chunk_Bytes          => Chunk);

   procedure Build_Shell_Command
     (Budget      : aliased in out Budgets.Budget;
      Session     : Budgets.Session_Tag;
      Command     : in out Processes.Command;
      Script      : String;
      With_Limits : Processes.Process_Limits)
   is
      Status : Processes.Build_Status := Processes.Build_Succeeded;
   begin
      Processes.Initialize (Command, Session, With_Limits, "/bin/sh", Status);
      Processes.Add_Argument (Command, Session, "-c", Status);
      Processes.Add_Argument (Command, Session, Script, Status);
      Processes.Add_Argument (Command, Session, "arg-zero", Status);
      Processes.Add_Environment (Command, Session, "EXACT_ENV=value", Status);
      Processes.Seal (Command, Session, Status);
      Require
        (Status = Processes.Build_Succeeded,
         "shell command did not build" & Processes.Build_Status'Image (Status));
      Require (Budgets.Current_State (Budget) = Budgets.Active, "command poisoned its budget");
   end Build_Shell_Command;

   procedure Require_Text
     (Value      : Processes.Result;
      Session    : Budgets.Session_Tag;
      Is_Output  : Boolean;
      Expected   : String)
   is
      Status  : Processes.Query_Status := Processes.Query_Succeeded;
      Length  : Interfaces.Unsigned_64 := Interfaces.Unsigned_64'Last;
      Written : Natural := Natural'Last;
      Buffer  : String (7 .. 6 + Expected'Length);
   begin
      if Is_Output then
         Processes.Standard_Output_Length (Value, Session, Length, Status);
      else
         Processes.Standard_Error_Length (Value, Session, Length, Status);
      end if;
      Require
        (Status = Processes.Query_Succeeded,
         "result length query failed for '"
         & Expected
         & "'"
         & Processes.Query_Status'Image (Status));
      Require (Length = Interfaces.Unsigned_64 (Expected'Length), "result length changed");
      if Is_Output then
         Processes.Copy_Standard_Output (Value, Session, Buffer, Written, Status);
      else
         Processes.Copy_Standard_Error (Value, Session, Buffer, Written, Status);
      end if;
      Require (Status = Processes.Query_Succeeded, "result copy failed");
      Require (Written = Expected'Length and then Buffer = Expected, "captured text changed");
   end Require_Text;

   procedure Require_Termination
     (Value    : Processes.Result;
      Session  : Budgets.Session_Tag;
      Kind     : Processes.Termination_Kind;
      Code     : Interfaces.C.int)
   is
      Observed_Kind : Processes.Termination_Kind := Processes.Exited;
      Observed_Code : Interfaces.C.int := -1;
      Status        : Processes.Query_Status := Processes.Query_Succeeded;
   begin
      Processes.Read_Termination
        (Value, Session, Observed_Kind, Observed_Code, Status);
      Require (Status = Processes.Query_Succeeded, "termination query failed");
      Require (Observed_Kind = Kind and then Observed_Code = Code, "termination changed");
   end Require_Termination;

   procedure Test_Completed_Result_And_Exact_Environment is
      Budget      : aliased Budgets.Budget;
      Initialized : Boolean := False;
      Session     : Budgets.Session_Tag;
      Command     : Processes.Command (Budget'Access);
      Result      : Processes.Result (Budget'Access);
      Status      : Processes.Run_Status := Processes.Ready_To_Run;
      System_Code : Interfaces.C.int := -1;
   begin
      Budgets.Initialize (Full_Budget, Budget, Initialized);
      Require (Initialized, "result budget did not initialize");
      Session := Budgets.Current_Session (Budget);
      Build_Shell_Command
        (Budget,
         Session,
         Command,
         "printf '%s' ""$EXACT_ENV""; printf problem >&2; exit 7",
         Limits);
      Processes.Run (Command, Session, Result, Status, System_Code);
      Require (Status = Processes.Run_Completed, "nonzero child did not complete");
      Require (System_Code = 0, "completed run retained a system error");
      Require_Termination (Result, Session, Processes.Exited, 7);
      Require_Text (Result, Session, True, "value");
      Require_Text (Result, Session, False, "problem");
      declare
         Buffer      : String (Positive'Last - 4 .. Positive'Last);
         Written     : Natural := Natural'Last;
         Query_State : Processes.Query_Status := Processes.Query_Succeeded;
      begin
         Processes.Copy_Standard_Output (Result, Session, Buffer, Written, Query_State);
         Require
           (Query_State = Processes.Query_Succeeded
            and then Written = 5
            and then Buffer = "value",
            "maximum-bound output copy failed");
      end;
      declare
         Buffer      : String (11 .. 14) := "keep";
         Written     : Natural := 77;
         Query_State : Processes.Query_Status := Processes.Query_Succeeded;
         Before      : constant Budgets.Usage := Budgets.Current_Usage (Budget);
         After       : Budgets.Usage;
      begin
         Processes.Copy_Standard_Output (Result, Session, Buffer, Written, Query_State);
         Require
           (Query_State = Processes.Query_Output_Too_Small
            and then Written = 77
            and then Buffer = "keep",
            "undersized output copy changed its outputs");
         Query_State := Processes.Query_No_Result;
         Processes.Copy_Standard_Output (Result, Session, Buffer, Written, Query_State);
         After := Budgets.Current_Usage (Budget);
         Require
           (Query_State = Processes.Query_No_Result
            and then Written = 77
            and then Buffer = "keep"
            and then Before.Input_Bytes = After.Input_Bytes
            and then Before.Work_Units + 1 = After.Work_Units,
            "prelatched output query charged or changed outputs");
      end;
      declare
         Length      : Interfaces.Unsigned_64 := 99;
         Query_State : Processes.Query_Status := Processes.Query_Succeeded;
         Before      : Budgets.Usage;
         After       : Budgets.Usage;
      begin
         Budgets.Poison (Budget);
         Before := Budgets.Current_Usage (Budget);
         Processes.Standard_Output_Length (Result, Session, Length, Query_State);
         After := Budgets.Current_Usage (Budget);
         Require
           (Query_State = Processes.Query_Budget_Failed
            and then Length = 99
            and then Before = After,
            "failed query budget was misclassified or charged");
      end;
   end Test_Completed_Result_And_Exact_Environment;

   procedure Test_Exact_And_Exceeded_Output_Cap is
      Budget      : aliased Budgets.Budget;
      Initialized : Boolean := False;
      Session     : Budgets.Session_Tag;
      Exact       : Processes.Command (Budget'Access);
      Too_Small   : Processes.Command (Budget'Access);
      Too_Small_Error : Processes.Command (Budget'Access);
      Zero_Empty  : Processes.Command (Budget'Access);
      Zero_Byte   : Processes.Command (Budget'Access);
      Result      : Processes.Result (Budget'Access);
      Status      : Processes.Run_Status := Processes.Ready_To_Run;
      System_Code : Interfaces.C.int := 0;
   begin
      Budgets.Initialize (Full_Budget, Budget, Initialized);
      Session := Budgets.Current_Session (Budget);
      Build_Shell_Command (Budget, Session, Exact, "printf 1234", Limits (Output_Bytes => 4));
      Processes.Run (Exact, Session, Result, Status, System_Code);
      Require (Status = Processes.Run_Completed, "exact output cap failed");
      Require (Budgets.Current_State (Budget) = Budgets.Active, "exact output cap poisoned budget");
      Require_Text (Result, Session, True, "1234");

      Build_Shell_Command
        (Budget, Session, Too_Small, "printf 5678", Limits (Output_Bytes => 3));
      Status := Processes.Ready_To_Run;
      System_Code := 0;
      Processes.Run (Too_Small, Session, Result, Status, System_Code);
      Require
        (Status = Processes.Run_Standard_Output_Limit,
         "one-less output cap status" & Processes.Run_Status'Image (Status));
      Require (Budgets.Current_State (Budget) = Budgets.Active, "output limit poisoned budget");
      Require_Text (Result, Session, True, "1234");

      Build_Shell_Command
        (Budget,
         Session,
         Too_Small_Error,
         "printf 5678 >&2",
         Limits (Error_Bytes => 3));
      Status := Processes.Ready_To_Run;
      System_Code := -1;
      Processes.Run (Too_Small_Error, Session, Result, Status, System_Code);
      Require
        (Status = Processes.Run_Standard_Error_Limit,
         "one-less stderr cap status" & Processes.Run_Status'Image (Status));
      Require (System_Code = 0, "stderr limit retained a system code");
      Require (Budgets.Current_State (Budget) = Budgets.Active, "error limit poisoned budget");
      Require_Text (Result, Session, True, "1234");

      Build_Shell_Command
        (Budget,
         Session,
         Zero_Empty,
         "exit 0",
         Limits (Output_Bytes => 0, Error_Bytes => 0));
      Status := Processes.Ready_To_Run;
      Processes.Run (Zero_Empty, Session, Result, Status, System_Code);
      Require (Status = Processes.Run_Completed, "zero output caps rejected empty streams");
      Require (Budgets.Current_State (Budget) = Budgets.Active, "empty run poisoned budget");
      Require_Text (Result, Session, True, "");
      Require_Text (Result, Session, False, "");

      Build_Shell_Command
        (Budget, Session, Zero_Byte, "printf x", Limits (Output_Bytes => 0));
      Status := Processes.Ready_To_Run;
      Processes.Run (Zero_Byte, Session, Result, Status, System_Code);
      Require (Status = Processes.Run_Standard_Output_Limit, "zero cap accepted its first byte");
      Require (Budgets.Current_State (Budget) = Budgets.Active, "zero cap poisoned budget");
      Require_Text (Result, Session, True, "");
   end Test_Exact_And_Exceeded_Output_Cap;

   procedure Test_Signaled_Completion is
      Budget      : aliased Budgets.Budget;
      Initialized : Boolean := False;
      Session     : Budgets.Session_Tag;
      Command     : Processes.Command (Budget'Access);
      Result      : Processes.Result (Budget'Access);
      Status      : Processes.Run_Status := Processes.Ready_To_Run;
      System_Code : Interfaces.C.int := -1;
   begin
      Budgets.Initialize (Full_Budget, Budget, Initialized);
      Require (Initialized, "signal budget did not initialize");
      Session := Budgets.Current_Session (Budget);
      Build_Shell_Command (Budget, Session, Command, "kill -TERM $$", Limits);
      Processes.Run (Command, Session, Result, Status, System_Code);
      Require (Status = Processes.Run_Completed, "signaled child was a runner failure");
      Require (System_Code = 0, "signaled completion retained a system error");
      Require_Termination (Result, Session, Processes.Signaled, 15);
   end Test_Signaled_Completion;

   procedure Test_Fair_Capture_And_Spawn_Failure_Preservation is
      Budget      : aliased Budgets.Budget;
      Initialized : Boolean := False;
      Session     : Budgets.Session_Tag;
      Completed   : Processes.Command (Budget'Access);
      Missing     : Processes.Command (Budget'Access);
      Result      : Processes.Result (Budget'Access);
      Status      : Processes.Run_Status := Processes.Ready_To_Run;
      Build_State : Processes.Build_Status := Processes.Build_Succeeded;
      System_Code : Interfaces.C.int := 0;
      Executable  : constant String (7 .. 40) := "/flyology-serde/no-such-executable";
   begin
      Budgets.Initialize (Full_Budget, Budget, Initialized);
      Require (Initialized, "capture budget did not initialize");
      Session := Budgets.Current_Session (Budget);
      Build_Shell_Command
        (Budget,
         Session,
         Completed,
         "printf 12345678; printf abcdefgh >&2",
         Limits (Output_Bytes => 8, Error_Bytes => 8, Chunk => 2));
      Processes.Run (Completed, Session, Result, Status, System_Code);
      Require (Status = Processes.Run_Completed, "fair capture did not complete");
      Require_Text (Result, Session, True, "12345678");
      Require_Text (Result, Session, False, "abcdefgh");

      Processes.Initialize (Missing, Session, Limits, Executable, Build_State);
      Processes.Seal (Missing, Session, Build_State);
      Require (Build_State = Processes.Build_Succeeded, "missing command did not build");
      Status := Processes.Ready_To_Run;
      System_Code := 0;
      Processes.Run (Missing, Session, Result, Status, System_Code);
      Require (Status = Processes.Run_Spawn_Failed, "missing executable did not fail spawn");
      Require (System_Code /= 0, "spawn failure omitted its system code");
      Require_Text (Result, Session, True, "12345678");
      Require_Text (Result, Session, False, "abcdefgh");
   end Test_Fair_Capture_And_Spawn_Failure_Preservation;

   procedure Test_Pipe_Capacity_Fairness is
      Budget      : aliased Budgets.Budget;
      Initialized : Boolean := False;
      Session     : Budgets.Session_Tag;
      Command     : Processes.Command (Budget'Access);
      Result      : Processes.Result (Budget'Access);
      Status      : Processes.Run_Status := Processes.Ready_To_Run;
      System_Code : Interfaces.C.int := -1;
      Output_Size : Interfaces.Unsigned_64 := 0;
      Error_Size  : Interfaces.Unsigned_64 := 0;
      Query_State : Processes.Query_Status := Processes.Query_Succeeded;
   begin
      Budgets.Initialize (Full_Budget, Budget, Initialized);
      Require (Initialized, "saturation budget did not initialize");
      Session := Budgets.Current_Session (Budget);
      Build_Shell_Command
        (Budget,
         Session,
         Command,
         "i=0; while [ $i -lt 8192 ]; do "
         & "printf 0123456789abcdef; printf fedcba9876543210 >&2; i=$((i+1)); done",
         Limits (Output_Bytes => 131_072, Error_Bytes => 131_072, Timeout => 10_000, Chunk => 4_096));
      Processes.Run (Command, Session, Result, Status, System_Code);
      Require
        (Status = Processes.Run_Completed and then System_Code = 0,
         "pipe-capacity capture did not complete");
      Processes.Standard_Output_Length (Result, Session, Output_Size, Query_State);
      Processes.Standard_Error_Length (Result, Session, Error_Size, Query_State);
      Require
        (Query_State = Processes.Query_Succeeded
         and then Output_Size = 131_072
         and then Error_Size = 131_072,
         "pipe-capacity capture lost one stream");
   end Test_Pipe_Capacity_Fairness;

   procedure Test_Exact_Input_Denial is
      Budget      : aliased Budgets.Budget;
      Initialized : Boolean := False;
      Session     : Budgets.Session_Tag;
      Command     : Processes.Command (Budget'Access);
      Result      : Processes.Result (Budget'Access);
      Status      : Processes.Run_Status := Processes.Ready_To_Run;
      System_Code : Interfaces.C.int := -1;
      Used        : Budgets.Usage;
   begin
      Budgets.Initialize
        ((Maximum_Input_Bytes => 1, Maximum_Work_Units => 10_000), Budget, Initialized);
      Require (Initialized, "input-denial budget did not initialize");
      Session := Budgets.Current_Session (Budget);
      Build_Shell_Command
        (Budget, Session, Command, "printf AB", Limits (Output_Bytes => 2, Chunk => 2));
      Processes.Run (Command, Session, Result, Status, System_Code);
      Used := Budgets.Current_Usage (Budget);
      Require
        (Status = Processes.Run_Budget_Exhausted
         and then System_Code = 0
         and then Budgets.Current_State (Budget) = Budgets.Exhausted
         and then Used.Input_Bytes = 0,
         "atomic child-input denial trace changed");
   end Test_Exact_Input_Denial;

   procedure Test_Command_Validation_And_Arbitrary_Bounds is
      Budget      : aliased Budgets.Budget;
      Initialized : Boolean := False;
      Session     : Budgets.Session_Tag;
      Command     : Processes.Command (Budget'Access);
      Uninitialized : Processes.Command (Budget'Access);
      Relative      : Processes.Command (Budget'Access);
      Invalid_Env   : Processes.Command (Budget'Access);
      Counted       : Processes.Command (Budget'Access);
      Status      : Processes.Build_Status := Processes.Build_Succeeded;
      Executable  : constant String (7 .. 13) := "/bin/sh";
      Argument    : constant String (9 .. 10) := "-c";
      Script      : constant String (20 .. 25) := "exit 0";
      Environment : constant String (31 .. 40) := "NAME=value";
      Duplicate   : constant String (41 .. 50) := "NAME=other";
      Before      : Budgets.Usage;
      After       : Budgets.Usage;
   begin
      Budgets.Initialize (Full_Budget, Budget, Initialized);
      Require (Initialized, "validation budget did not initialize");
      Session := Budgets.Current_Session (Budget);
      Before := Budgets.Current_Usage (Budget);
      Processes.Seal (Uninitialized, Session, Status);
      After := Budgets.Current_Usage (Budget);
      Require (Status = Processes.Build_Invalid_Command, "uninitialized command was not invalid");
      Require
        (Before.Input_Bytes = After.Input_Bytes and then Before.Work_Units = After.Work_Units,
         "uninitialized command preflight charged work");

      Status := Processes.Build_Succeeded;
      Processes.Initialize (Relative, Session, Limits, "bin/sh", Status);
      Require (Status = Processes.Build_Invalid_Command, "relative executable was accepted");
      Status := Processes.Build_Succeeded;
      Processes.Initialize
        (Relative, Session, Limits, String'(1 => Character'Val (0)), Status);
      Require (Status = Processes.Build_Invalid_Command, "NUL executable was accepted");

      Status := Processes.Build_Succeeded;
      Processes.Initialize (Invalid_Env, Session, Limits, "/bin/sh", Status);
      Processes.Add_Environment (Invalid_Env, Session, "NAME", Status);
      Require (Status = Processes.Build_Invalid_Command, "environment without '=' was accepted");

      Status := Processes.Build_Succeeded;
      Processes.Initialize
        (Counted,
         Session,
         (Maximum_Argument_Count            => 2,
          Maximum_Argument_Bytes            => 32,
          Maximum_Environment_Count         => 1,
          Maximum_Environment_Bytes         => 1,
          Maximum_Standard_Output_Bytes     => 1,
          Maximum_Standard_Error_Bytes      => 1,
          Timeout_Milliseconds              => 100,
          Observation_Interval_Milliseconds => 1,
          Maximum_Read_Chunk_Bytes          => 1),
         "/bin/sh",
         Status);
      Processes.Add_Argument (Counted, Session, "-c", Status);
      Require (Status = Processes.Build_Succeeded, "exact argument count was rejected");
      Processes.Add_Argument (Counted, Session, "exit 0", Status);
      Require (Status = Processes.Build_Limit_Exceeded, "over-limit argument count was accepted");

      Status := Processes.Build_Succeeded;
      Processes.Initialize (Command, Session, Limits, Executable, Status);
      Processes.Add_Argument (Command, Session, Argument, Status);
      Processes.Add_Argument (Command, Session, Script, Status);
      Processes.Add_Environment (Command, Session, Environment, Status);
      Require (Status = Processes.Build_Succeeded, "arbitrary-bound command was rejected");
      Processes.Add_Environment (Command, Session, Duplicate, Status);
      Require (Status = Processes.Build_Invalid_Command, "duplicate environment name accepted");
   end Test_Command_Validation_And_Arbitrary_Bounds;

   procedure Test_Exact_Build_Charge_Trace is
      Exact_Budget : aliased Budgets.Budget;
      Denied_Budget : aliased Budgets.Budget;
      Environment_Budget : aliased Budgets.Budget;
      Initialized : Boolean := False;
      Exact_Session : Budgets.Session_Tag;
      Denied_Session : Budgets.Session_Tag;
      Environment_Session : Budgets.Session_Tag;
      Exact_Command : Processes.Command (Exact_Budget'Access);
      Denied_Command : Processes.Command (Denied_Budget'Access);
      Environment_Command : Processes.Command (Environment_Budget'Access);
      Exact_Result : Processes.Result (Exact_Budget'Access);
      Denied_Result : Processes.Result (Denied_Budget'Access);
      Build_State : Processes.Build_Status := Processes.Build_Succeeded;
      Run_State : Processes.Run_Status := Processes.Ready_To_Run;
      System_Code : Interfaces.C.int := -1;
      Used : Budgets.Usage;
   begin
      Budgets.Initialize
        ((Maximum_Input_Bytes => 1, Maximum_Work_Units => 65), Exact_Budget, Initialized);
      Require (Initialized, "exact trace budget did not initialize");
      Exact_Session := Budgets.Current_Session (Exact_Budget);
      Build_Shell_Command
        (Exact_Budget, Exact_Session, Exact_Command, "exit 0", Limits);
      Used := Budgets.Current_Usage (Exact_Budget);
      Require (Used.Work_Units = 65, "exact command-build charge trace changed");

      Budgets.Initialize
        ((Maximum_Input_Bytes => 1, Maximum_Work_Units => 136), Denied_Budget, Initialized);
      Require (Initialized, "denial trace budget did not initialize");
      Denied_Session := Budgets.Current_Session (Denied_Budget);
      Build_Shell_Command
        (Denied_Budget, Denied_Session, Denied_Command, "exit 0", Limits);
      Used := Budgets.Current_Usage (Denied_Budget);
      Processes.Run
        (Denied_Command, Denied_Session, Exact_Result, Run_State, System_Code);
      Require (Run_State = Processes.Run_Session_Foreign, "cross-owner result was accepted");
      Require (System_Code = 0, "non-system cross-owner error retained a system code");
      Require
        (Budgets.Current_Usage (Denied_Budget).Work_Units = Used.Work_Units,
         "cross-owner preflight charged work");
      Run_State := Processes.Ready_To_Run;
      System_Code := -1;
      Processes.Run
        (Denied_Command, Denied_Session, Denied_Result, Run_State, System_Code);
      Used := Budgets.Current_Usage (Denied_Budget);
      Require (Run_State = Processes.Run_Budget_Exhausted, "fixed setup denial was not bounded");
      Require (Used.Work_Units = 124, "pre-spawn denial charge trace changed");
      Require (System_Code = 0, "budget denial retained a system code");

      Budgets.Initialize
        ((Maximum_Input_Bytes => 1, Maximum_Work_Units => 22),
         Environment_Budget,
         Initialized);
      Require (Initialized, "environment denial budget did not initialize");
      Environment_Session := Budgets.Current_Session (Environment_Budget);
      Build_State := Processes.Build_Succeeded;
      Processes.Initialize
        (Environment_Command, Environment_Session, Limits, "/bin/sh", Build_State);
      Processes.Add_Environment
        (Environment_Command, Environment_Session, "A=x", Build_State);
      Processes.Add_Environment
        (Environment_Command, Environment_Session, "B=y", Build_State);
      Used := Budgets.Current_Usage (Environment_Budget);
      Require
        (Build_State = Processes.Build_Budget_Exhausted and then Used.Work_Units = 22,
         "existing-environment denial point changed");
   end Test_Exact_Build_Charge_Trace;

   procedure Test_Cloexec_Gate_Spans_Spawn is
      Concurrent_Budget : constant Budgets.Limits :=
        (Maximum_Input_Bytes => 1_000_000, Maximum_Work_Units => 100_000_000);
      Slow_Budget : aliased Budgets.Budget;
      Fast_Budget : aliased Budgets.Budget;
      Initialized : Boolean := False;
      Slow_Session : Budgets.Session_Tag;
      Fast_Session : Budgets.Session_Tag;
      Slow_Command : Processes.Command (Slow_Budget'Access);
      Fast_Command : Processes.Command (Fast_Budget'Access);
      Slow_Result : Processes.Result (Slow_Budget'Access);
      Fast_Result : Processes.Result (Fast_Budget'Access);
      Slow_Status : Processes.Run_Status := Processes.Ready_To_Run;
      Fast_Status : Processes.Run_Status := Processes.Ready_To_Run;
      Slow_Code : Interfaces.C.int := -1;
      Fast_Code : Interfaces.C.int := -1;
      Pause_Armed : Boolean := False;
      Reached : Boolean := False;

      task Slow_Task is
         entry Start;
         entry Await;
      end Slow_Task;

      task body Slow_Task is
      begin
         accept Start;
         Processes.Run (Slow_Command, Slow_Session, Slow_Result, Slow_Status, Slow_Code);
         accept Await;
      end Slow_Task;

      task Fast_Task is
         entry Start;
         entry Await;
      end Fast_Task;

      task body Fast_Task is
      begin
         accept Start;
         Processes.Run (Fast_Command, Fast_Session, Fast_Result, Fast_Status, Fast_Code);
         accept Await;
      end Fast_Task;

   begin
      Budgets.Initialize (Concurrent_Budget, Slow_Budget, Initialized);
      Require (Initialized, "slow concurrent budget did not initialize");
      Budgets.Initialize (Concurrent_Budget, Fast_Budget, Initialized);
      Require (Initialized, "fast concurrent budget did not initialize");
      Slow_Session := Budgets.Current_Session (Slow_Budget);
      Fast_Session := Budgets.Current_Session (Fast_Budget);

      Build_Shell_Command
        (Slow_Budget,
         Slow_Session,
         Slow_Command,
         "/bin/sleep 0.05",
         Limits (Output_Bytes => 1, Timeout => 1_000, Chunk => 1));
      Build_Shell_Command
        (Fast_Budget,
         Fast_Session,
         Fast_Command,
         "printf x",
         Limits (Output_Bytes => 1, Timeout => 100, Chunk => 1));

      Test_Hooks.Arm_Raw_Pipe_Pause;
      Pause_Armed := True;
      Slow_Task.Start;
      Test_Hooks.Wait_For_Raw_Pipe_Open (2.0, Reached);
      Require (Reached, "raw-pipe gate test did not open its first pipe");
      Fast_Task.Start;
      Test_Hooks.Wait_For_Two_Gate_Attempts (2.0, Reached);
      Require (Reached, "raw-pipe gate test did not observe its blocked second run");
      Test_Hooks.Release_Raw_Pipe_Pause;
      Pause_Armed := False;
      select
         Slow_Task.Await;
      or
         delay 2.0;
         raise Program_Error with "slow raw-pipe gate task did not finish";
      end select;
      select
         Fast_Task.Await;
      or
         delay 2.0;
         raise Program_Error with "fast raw-pipe gate task did not finish";
      end select;
      Require (Slow_Status = Processes.Run_Completed, "slow concurrent run failed");
      Require (Fast_Status = Processes.Run_Completed, "raw descriptor crossed a concurrent spawn");
      Require_Text (Fast_Result, Fast_Session, True, "x");
   exception
      when others =>
         if Pause_Armed then
            Test_Hooks.Release_Raw_Pipe_Pause;
         end if;
         abort Slow_Task;
         abort Fast_Task;
         raise;
   end Test_Cloexec_Gate_Spans_Spawn;

   procedure Test_Sigchld_Ownership_Policy is
      Budget      : aliased Budgets.Budget;
      Initialized : Boolean := False;
      Session     : Budgets.Session_Tag;
      Command     : Processes.Command (Budget'Access);
      Result      : Processes.Result (Budget'Access);
      Status      : Processes.Run_Status := Processes.Ready_To_Run;
      System_Code : Interfaces.C.int := 0;
      Deviation_Result : Interfaces.C.int;
      Deviated    : Boolean := False;
      Restored    : Boolean := False;

      procedure Require_Rejection is
      begin
         Processes.Run (Command, Session, Result, Status, System_Code);
         Require
           (Status = Processes.Run_Spawn_Failed
            and then System_Code = ABI.Errno_Invalid,
            "unsafe SIGCHLD ownership was not rejected by Ada");
      end Require_Rejection;
   begin
      Budgets.Initialize (Full_Budget, Budget, Initialized);
      Require (Initialized, "SIGCHLD policy budget did not initialize");
      Session := Budgets.Current_Session (Budget);
      Build_Shell_Command (Budget, Session, Command, "exit 0", Limits);

      Require (Deviate_Sigchld_Ignored = 0, "ignored SIGCHLD setup failed");
      Deviated := True;
      Require_Rejection;
      Require (Restore_Sigchld = 0, "ignored SIGCHLD restoration failed");
      Restored := True;

      Status := Processes.Ready_To_Run;
      System_Code := 0;
      Deviation_Result := Deviate_Sigchld_No_Child_Wait;
      if Deviation_Result = 0 then
         Deviated := True;
         Restored := False;
         Require_Rejection;
         Require (Restore_Sigchld = 0, "automatic child-discard restoration failed");
         Restored := True;
      else
         Require
           (Deviation_Result = -1,
            "automatic child-discard setup failed unexpectedly");
      end if;

      Status := Processes.Ready_To_Run;
      System_Code := -1;
      Processes.Run (Command, Session, Result, Status, System_Code);
      Require
        (Status = Processes.Run_Completed and then System_Code = 0,
         "safe SIGCHLD ownership did not recover after rejected calls");
   exception
      when others =>
         if Deviated and then not Restored then
            Require (Restore_Sigchld = 0, "SIGCHLD restoration failed during cleanup");
         end if;
         raise;
   end Test_Sigchld_Ownership_Policy;

   procedure Test_Timeout_And_Prelatched_No_Op is
      Directory_Buffer : aliased Interfaces.C.char_array (0 .. 127) :=
        [others => Interfaces.C.nul];
      Private_Directory : US.Unbounded_String;
      Descendant_Path : US.Unbounded_String;
      Budget      : aliased Budgets.Budget;
      Initialized : Boolean := False;
      Session     : Budgets.Session_Tag;
      Command     : Processes.Command (Budget'Access);
      Detached_Command : Processes.Command (Budget'Access);
      Result      : Processes.Result (Budget'Access);
      Status      : Processes.Run_Status := Processes.Run_Invalid_Command;
      System_Code : Interfaces.C.int := 77;
      Before      : Budgets.Usage;
      After       : Budgets.Usage;
      Descendant  : ABI.Process_ID := -1;

      procedure Cleanup_Descendant (Strict : Boolean) is
         Cleanup_Result : Interfaces.C.int := 0;
      begin
         if US.Length (Descendant_Path) > 0
           and then Ada.Directories.Exists (US.To_String (Descendant_Path))
         then
            Ada.Directories.Delete_File (US.To_String (Descendant_Path));
         end if;
         if US.Length (Private_Directory) > 0 then
            declare
               Directory_Name : aliased Interfaces.C.char_array :=
                 Interfaces.C.To_C (US.To_String (Private_Directory));
            begin
               Cleanup_Result := Remove_Private_Directory (Directory_Name'Address);
            end;
         end if;
         if Strict then
            Require
              (Cleanup_Result = 0
               and then not Ada.Directories.Exists (US.To_String (Private_Directory)),
               "descendant-test directory cleanup failed");
         end if;
      exception
         when others =>
            if Strict then
               raise;
            end if;
      end Cleanup_Descendant;
   begin
      Require
        (Create_Private_Directory
           (Directory_Buffer'Address, Interfaces.C.size_t (Directory_Buffer'Length)) = 0,
         "private descendant-test directory creation failed");
      Private_Directory := US.To_Unbounded_String (Interfaces.C.To_Ada (Directory_Buffer));
      Descendant_Path := US.To_Unbounded_String
        (US.To_String (Private_Directory) & "/descendant.pid");
      Budgets.Initialize (Full_Budget, Budget, Initialized);
      Session := Budgets.Current_Session (Budget);
      Build_Shell_Command
        (Budget,
         Session,
         Command,
         "/bin/sleep 30 & child=$!; printf '%s' ""$child"" > "
         & US.To_String (Descendant_Path)
         & "; exit 0",
         Limits (Timeout => 2_000));
      Before := Budgets.Current_Usage (Budget);
      Processes.Run (Command, Session, Result, Status, System_Code);
      After := Budgets.Current_Usage (Budget);
      Require (Status = Processes.Run_Invalid_Command, "prelatched status changed");
      Require (System_Code = 77, "prelatched system code changed");
      Require
        (Before.Input_Bytes = After.Input_Bytes and then Before.Work_Units = After.Work_Units,
         "prelatched run charged work");

      Status := Processes.Ready_To_Run;
      System_Code := 0;
      Processes.Run (Command, Session, Result, Status, System_Code);
      Require (Status = Processes.Run_Timed_Out, "pipe-holding descendant did not time out");
      declare
         File : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, US.To_String (Descendant_Path));
         Descendant := ABI.Process_ID'Value (Ada.Text_IO.Get_Line (File));
         Ada.Text_IO.Close (File);
      exception
         when others =>
            if Ada.Text_IO.Is_Open (File) then
               Ada.Text_IO.Close (File);
            end if;
            raise;
      end;
      for Attempt in 1 .. 200 loop
         exit when ABI.Kill (Descendant, 0) < 0 and then ABI.Current_Errno = ABI.Errno_No_Process;
         delay 0.001;
      end loop;
      Require
         (ABI.Kill (Descendant, 0) < 0 and then ABI.Current_Errno = ABI.Errno_No_Process,
         "timeout cleanup left its process-group descendant alive");

      Ada.Directories.Delete_File (US.To_String (Descendant_Path));
      Build_Shell_Command
        (Budget,
         Session,
         Detached_Command,
         "/bin/sleep 30 >/dev/null 2>&1 & child=$!; printf '%s' ""$child"" > "
         & US.To_String (Descendant_Path)
         & "; exit 0",
         Limits (Timeout => 2_000));
      Status := Processes.Ready_To_Run;
      System_Code := -1;
      Processes.Run (Detached_Command, Session, Result, Status, System_Code);
      Require
        (Status = Processes.Run_Completed and then System_Code = 0,
         "closed-stream descendant changed leader completion");
      declare
         File : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, US.To_String (Descendant_Path));
         Descendant := ABI.Process_ID'Value (Ada.Text_IO.Get_Line (File));
         Ada.Text_IO.Close (File);
      exception
         when others =>
            if Ada.Text_IO.Is_Open (File) then
               Ada.Text_IO.Close (File);
            end if;
            raise;
      end;
      for Attempt in 1 .. 200 loop
         exit when ABI.Kill (Descendant, 0) < 0 and then ABI.Current_Errno = ABI.Errno_No_Process;
         delay 0.001;
      end loop;
      Require
        (ABI.Kill (Descendant, 0) < 0 and then ABI.Current_Errno = ABI.Errno_No_Process,
         "successful run left its closed-stream process-group descendant alive");
      Cleanup_Descendant (Strict => True);
   exception
      when others =>
         Cleanup_Descendant (Strict => False);
         raise;
   end Test_Timeout_And_Prelatched_No_Op;

   procedure Test_Ownership_Classifiers is
      Busy_Gate  : Processes.Runner_Gate;
      Busy_Held  : Boolean := False;
      Busy_Queued_Granted : Boolean := True;
      Status      : Processes.Run_Status;
      System_Code : Interfaces.C.int;
      Poison      : Boolean;
      Cleanup     : Boolean;

      task Busy_Acquirer is
         entry Start;
         entry Await;
      end Busy_Acquirer;

      task body Busy_Acquirer is
      begin
         accept Start;
         Busy_Gate.Acquire (Busy_Queued_Granted);
         accept Await;
      end Busy_Acquirer;
   begin
      Require
        (Processes.Classify_Pipe_Result (0) = Processes.Pipe_Opened,
         "successful pipe result was rejected");
      Require
        (Processes.Classify_Pipe_Result (-1) = Processes.Pipe_System_Failure,
         "failed pipe result did not preserve errno classification");
      Require
        (Processes.Classify_Pipe_Result (1) = Processes.Pipe_ABI_Failure
         and then Processes.Classify_Pipe_Result (-2) = Processes.Pipe_ABI_Failure,
         "impossible pipe result consumed stale errno");
      Require
        (Processes.Positive_Read_Count_Is_Valid (4, 4)
         and then not Processes.Positive_Read_Count_Is_Valid (5, 4),
         "oversized positive read result was accepted");
      Require
        (Processes.Published_Child_Is_Valid (1)
         and then not Processes.Published_Child_Is_Valid (0)
         and then not Processes.Published_Child_Is_Valid (-1),
         "nonpositive spawned child identity reached ownership cleanup");
      Require
        (Processes.Observations_Match (Processes.Exited, 7, Processes.Exited, 7)
         and then not Processes.Observations_Match
           (Processes.Exited, 7, Processes.Exited, 8)
         and then not Processes.Observations_Match
           (Processes.Exited, 7, Processes.Signaled, 7),
         "cleanup observation mismatch was not rejected");
      Processes.Classify_Spawn_Release
        (2, 22, False, Status, System_Code, Poison, Cleanup);
      Require
        (Status = Processes.Run_Spawn_Failed
         and then System_Code = 2
         and then Poison
         and then not Cleanup,
         "spawn primary did not outrank spawn cleanup damage");
      Processes.Classify_Spawn_Release
        (0, 22, False, Status, System_Code, Poison, Cleanup);
      Require
        (Status = Processes.Run_Cleanup_Failed
         and then System_Code = 22
         and then Poison
         and then Cleanup,
         "successful spawn cleanup damage was not owned and reported");

      Busy_Gate.Acquire (Busy_Held);
      Require (Busy_Held, "busy poison-wakeup gate was not acquired");
      Busy_Acquirer.Start;
      for Attempt in 1 .. 100 loop
         exit when Busy_Gate.Waiting_Acquirers = 1;
         delay 0.001;
      end loop;
      Require (Busy_Gate.Waiting_Acquirers = 1, "busy gate acquisition did not queue");
      Busy_Gate.Poison;
      select
         Busy_Acquirer.Await;
      or
         delay 1.0;
         raise Program_Error with "poison did not wake an acquirer behind a busy gate";
      end select;
      Require (not Busy_Queued_Granted, "poisoned busy gate granted process ownership");
      Busy_Gate.Release (True);

   exception
      when others =>
         abort Busy_Acquirer;
         raise;
   end Test_Ownership_Classifiers;

   procedure Test_Stale_Result_Replacement is
      Budget      : aliased Budgets.Budget;
      Initialized : Boolean := False;
      First       : Budgets.Session_Tag;
      Second      : Budgets.Session_Tag;
      First_Command  : Processes.Command (Budget'Access);
      Second_Command : Processes.Command (Budget'Access);
      Result         : Processes.Result (Budget'Access);
      Run_State      : Processes.Run_Status := Processes.Ready_To_Run;
      Query_State    : Processes.Query_Status := Processes.Query_Succeeded;
      System_Code    : Interfaces.C.int := 0;
      Length         : Interfaces.Unsigned_64 := 99;
      Before         : Budgets.Usage;
      After          : Budgets.Usage;
   begin
      Budgets.Initialize (Full_Budget, Budget, Initialized);
      First := Budgets.Current_Session (Budget);
      Build_Shell_Command (Budget, First, First_Command, "printf old", Limits);
      Processes.Run (First_Command, First, Result, Run_State, System_Code);
      Require (Run_State = Processes.Run_Completed, "first stale-result run failed");

      Budgets.Initialize (Full_Budget, Budget, Initialized);
      Second := Budgets.Current_Session (Budget);
      Before := Budgets.Current_Usage (Budget);
      Processes.Standard_Output_Length (Result, First, Length, Query_State);
      After := Budgets.Current_Usage (Budget);
      Require
        (Query_State = Processes.Query_Session_Foreign
         and then Length = 99
         and then Before.Work_Units = After.Work_Units,
         "foreign query preflight charged or changed output");
      Query_State := Processes.Query_Succeeded;
      Processes.Standard_Output_Length (Result, Second, Length, Query_State);
      After := Budgets.Current_Usage (Budget);
      Require
        (Query_State = Processes.Query_Session_Foreign
         and then Length = 99
         and then After.Work_Units = Before.Work_Units + 1,
         "stale result query did not preserve output");
      Build_Shell_Command (Budget, Second, Second_Command, "printf new", Limits);
      Run_State := Processes.Ready_To_Run;
      Processes.Run (Second_Command, Second, Result, Run_State, System_Code);
      Require (Run_State = Processes.Run_Completed, "stale result blocked replacement");
      Require_Text (Result, Second, True, "new");
   end Test_Stale_Result_Replacement;

   procedure Run is
   begin
      Test_Completed_Result_And_Exact_Environment;
      Test_Exact_And_Exceeded_Output_Cap;
      Test_Signaled_Completion;
      Test_Fair_Capture_And_Spawn_Failure_Preservation;
      Test_Pipe_Capacity_Fairness;
      Test_Exact_Input_Denial;
      Test_Command_Validation_And_Arbitrary_Bounds;
      Test_Exact_Build_Charge_Trace;
      Test_Cloexec_Gate_Spans_Spawn;
      Test_Sigchld_Ownership_Policy;
      Test_Timeout_And_Prelatched_No_Op;
      Test_Ownership_Classifiers;
      Test_Stale_Result_Replacement;
   end Run;
end Flyology_Serde_Generator.Build_Processes_Test_Facade;
