with Ada.Finalization;
with Interfaces;
with Interfaces.C;

with Flyology_Serde_Generator.Build_Budgets;

private package Flyology_Serde_Generator.Build_Processes is
   package Budgets renames Flyology_Serde_Generator.Build_Budgets;

   subtype Limit_Value is Interfaces.Unsigned_64 range 1 .. Interfaces.Unsigned_64'Last;
   subtype Count_Limit is Interfaces.Unsigned_64;

   type Process_Limits is record
      Maximum_Argument_Count       : Limit_Value;
      Maximum_Argument_Bytes       : Limit_Value;
      Maximum_Environment_Count    : Count_Limit;
      Maximum_Environment_Bytes    : Count_Limit;
      Maximum_Standard_Output_Bytes : Count_Limit;
      Maximum_Standard_Error_Bytes  : Count_Limit;
      Timeout_Milliseconds          : Limit_Value;
      Observation_Interval_Milliseconds : Limit_Value;
      Maximum_Read_Chunk_Bytes      : Limit_Value;
   end record;

   --  No field has a default.  Timeout_Milliseconds starts only after a successful
   --  spawn has published and validated its positive PID.  It covers parent-side
   --  descriptor handoff, capture, and normal child observation, but not gate wait,
   --  pipe setup, posix_spawn, or mandatory failure cleanup.  Cleanup never returns
   --  while the exact leader remains unreaped; an impossible ownership or ABI state
   --  deliberately fail-stops instead of releasing an unowned child.

   type Build_Status is
     (Build_Succeeded,
      Build_Session_Foreign,
      Build_Budget_Exhausted,
      Build_Budget_Failed,
      Build_Runner_Poisoned,
      Build_Invalid_Command,
      Build_Limit_Exceeded,
      Build_Allocation_Failed,
      Build_Internal_Failure);

   type Command (Owner : not null access Budgets.Budget) is limited private;

   --  Executable becomes argv[0].  Argument counts and bytes include argv[0];
   --  byte counts include one trailing C NUL for every argument or environment entry.
   procedure Initialize
     (Into       : in out Command;
      Session    : Budgets.Session_Tag;
      Limits     : Process_Limits;
      Executable : String;
      Status     : in out Build_Status);

   procedure Add_Argument
     (Into    : in out Command;
      Session : Budgets.Session_Tag;
      Value   : String;
      Status  : in out Build_Status);

   --  Value is one exact NAME=VALUE entry.  Names are nonempty, contain neither
   --  '=' nor NUL, and cannot be repeated.  No inherited environment is added.
   procedure Add_Environment
     (Into    : in out Command;
      Session : Budgets.Session_Tag;
      Value   : String;
      Status  : in out Build_Status);

   procedure Seal
     (Into    : in out Command;
      Session : Budgets.Session_Tag;
      Status  : in out Build_Status);

   type Run_Status is
     (Ready_To_Run,
      Run_Completed,
      Run_Session_Foreign,
      Run_Budget_Exhausted,
      Run_Budget_Failed,
      Run_Runner_Poisoned,
      Run_Invalid_Command,
      Run_Spawn_Failed,
      Run_Timed_Out,
      Run_Standard_Output_Limit,
      Run_Standard_Error_Limit,
      Run_System_Failed,
      Run_Cleanup_Failed,
      Run_Allocation_Failed,
      Run_Internal_Failure);

   type Termination_Kind is (Exited, Signaled);

   type Result (Owner : not null access Budgets.Budget) is limited private;

   --  A successful nonzero exit or signal is a complete Result.  Spawn, timeout,
   --  capture, budget, or cleanup failure preserves any prior Result.  Existing
   --  stale result identity never blocks replacement for the same Budget owner.
   --  The executable must not create descendants or change its process group, session,
   --  or credentials.  This package is the generator's only production spawn path;
   --  every unrelated descriptor must already be CLOEXEC.
   --  A prelatched Status preserves System_Code and performs no work.  After an
   --  accepted Ready_To_Run call, System_Code is zero except for Run_Spawn_Failed,
   --  Run_System_Failed, and Run_Cleanup_Failed, which publish the exact host error.
   procedure Run
     (What       : Command;
      Session    : Budgets.Session_Tag;
      Into       : in out Result;
      Status     : in out Run_Status;
      System_Code : in out Interfaces.C.int);

   type Query_Status is
     (Query_Succeeded,
      Query_Session_Foreign,
      Query_No_Result,
      Query_Budget_Exhausted,
      Query_Budget_Failed,
      Query_Output_Too_Small,
      Query_Internal_Failure);

   procedure Read_Termination
     (From        : Result;
      Session     : Budgets.Session_Tag;
      Kind        : in out Termination_Kind;
      Code        : in out Interfaces.C.int;
      Status      : in out Query_Status);

   procedure Standard_Output_Length
     (From    : Result;
      Session : Budgets.Session_Tag;
      Length  : in out Interfaces.Unsigned_64;
      Status  : in out Query_Status);

   procedure Standard_Error_Length
     (From    : Result;
      Session : Budgets.Session_Tag;
      Length  : in out Interfaces.Unsigned_64;
      Status  : in out Query_Status);

   procedure Copy_Standard_Output
     (From    : Result;
      Session : Budgets.Session_Tag;
      Into    : in out String;
      Written : in out Natural;
      Status  : in out Query_Status);

   procedure Copy_Standard_Error
     (From    : Result;
      Session : Budgets.Session_Tag;
      Into    : in out String;
      Written : in out Natural;
      Status  : in out Query_Status);

   --  Internal ownership-transition seam used by the generator's focused tests.
   type Pipe_Result_Action is (Pipe_Opened, Pipe_System_Failure, Pipe_ABI_Failure);

   function Classify_Pipe_Result (Result : Interfaces.C.int) return Pipe_Result_Action;

   procedure Classify_Spawn_Release
     (Spawn_Error      : Interfaces.C.int;
      Cleanup_Error    : Interfaces.C.int;
      Release_Damaged  : Boolean;
      Status           : out Run_Status;
      System_Code      : out Interfaces.C.int;
      Poison_Later_Use : out Boolean;
      Cleanup_Child    : out Boolean);

   function Positive_Read_Count_Is_Valid
     (Count     : Interfaces.C.long;
      Requested : Interfaces.C.long) return Boolean;

   function Published_Child_Is_Valid (Child : Interfaces.C.int) return Boolean;

   function Observations_Match
     (Left_Kind  : Termination_Kind;
      Left_Code  : Interfaces.C.int;
      Right_Kind : Termination_Kind;
      Right_Code : Interfaces.C.int) return Boolean;

   protected type Runner_Gate is
      entry Acquire (Granted : out Boolean);
      procedure Release (Safe : Boolean);
      procedure Poison;
      function Is_Poisoned return Boolean;
      function Waiting_Acquirers return Natural;
   private
      Busy    : Boolean := False;
      Damaged : Boolean := False;
   end Runner_Gate;

private
   type Command_Payload;
   type Command_Payload_Access is access Command_Payload;

   type Command_Holder is new Ada.Finalization.Limited_Controlled with record
      Value : Command_Payload_Access := null;
   end record;
   overriding procedure Finalize (Value : in out Command_Holder);

   type Command (Owner : not null access Budgets.Budget) is limited record
      Data : Command_Holder;
   end record;

   type Result_Payload;
   type Result_Payload_Access is access Result_Payload;

   type Result_Holder is new Ada.Finalization.Limited_Controlled with record
      Value : Result_Payload_Access := null;
   end record;
   overriding procedure Finalize (Value : in out Result_Holder);

   type Result (Owner : not null access Budgets.Budget) is limited record
      Data : Result_Holder;
   end record;

end Flyology_Serde_Generator.Build_Processes;
