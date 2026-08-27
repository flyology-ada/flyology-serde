with Ada.Command_Line;
with Ada.Streams;
with Ada.Task_Identification;
with Interfaces;

with Flyology_Serde_Generator.Build_Attestation_Test_Hooks;

procedure Flyology_Serde_Generator.Build_Attestations.Local_Snapshots.Abort_Test is
   package Hooks renames Flyology_Serde_Generator.Build_Attestation_Test_Hooks;

   use type Budgets.Budget_State;

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   procedure Initialize
     (Value   : aliased in out Budgets.Budget;
      Session : out Budgets.Session_Tag)
   is
      Ready : Boolean := False;
   begin
      Budgets.Initialize
        ((Maximum_Input_Bytes => Interfaces.Unsigned_64'Last,
          Maximum_Work_Units  => Interfaces.Unsigned_64'Last),
         Value, Ready);
      Require (Ready, "abort-test budget initialization failed");
      Session := Budgets.Current_Session (Value);
   end Initialize;

   procedure Wait_And_Abort
     (Point  : Hooks.Transfer_Point;
      Target : Ada.Task_Identification.Task_Id)
   is
      Reached : Boolean := False;
   begin
      Hooks.Wait_For (Point, 2.0, Reached);
      Require (Reached, "snapshot abort pause was not reached:" & Point'Image);
      Ada.Task_Identification.Abort_Task (Target);
      Hooks.Release (Point);
   end Wait_And_Abort;

   type Ownership_Counts is record
      Descriptors_Attached : Natural;
      Descriptors_Released : Natural;
      Blocks_Allocated     : Natural;
      Blocks_Released      : Natural;
      Paths_Allocated      : Natural;
      Paths_Released       : Natural;
      Payloads_Allocated   : Natural;
      Payloads_Released    : Natural;
   end record;

   procedure Read_Ownership_Counts (Into : out Ownership_Counts) is
   begin
      Hooks.Snapshot_Descriptor_Counts
        (Into.Descriptors_Attached, Into.Descriptors_Released);
      Hooks.Snapshot_Allocation_Counts
        (Into.Blocks_Allocated, Into.Blocks_Released,
         Into.Paths_Allocated, Into.Paths_Released,
         Into.Payloads_Allocated, Into.Payloads_Released);
   end Read_Ownership_Counts;

   procedure Require_Balanced_Delta
     (Before : Ownership_Counts;
      After  : Ownership_Counts;
      Message : String) is
   begin
      Require
        (After.Descriptors_Attached - Before.Descriptors_Attached =
           After.Descriptors_Released - Before.Descriptors_Released
         and then After.Blocks_Allocated - Before.Blocks_Allocated =
           After.Blocks_Released - Before.Blocks_Released
         and then After.Paths_Allocated - Before.Paths_Allocated =
           After.Paths_Released - Before.Paths_Released
         and then After.Payloads_Allocated - Before.Payloads_Allocated =
           After.Payloads_Released - Before.Payloads_Released,
         Message);
   end Require_Balanced_Delta;

   procedure Wait_For_Termination
     (Terminated : not null access function return Boolean;
      Message    : String) is
   begin
      for Attempt in 1 .. 200 loop
         exit when Terminated.all;
         delay 0.01;
      end loop;
      Require (Terminated.all, Message);
   end Wait_For_Termination;

   Root_Path : constant String := Ada.Command_Line.Argument (1);
begin
   Require (Ada.Command_Line.Argument_Count = 1, "snapshot abort test requires its fixture root");

   declare
      Budget  : aliased Budgets.Budget;
      Session : Budgets.Session_Tag;
      Before, After : Ownership_Counts;
   begin
      Hooks.Reset_Snapshot_Failures;
      Read_Ownership_Counts (Before);
      Initialize (Budget, Session);
      declare
         Root_Value : Root (Budget'Access);
         State      : Root_Status := Root_Succeeded;
         task Worker is
            entry Start;
         end Worker;
         task body Worker is
         begin
            accept Start;
            Open_Root
              (Root_Path, Session, 4_096, 32, 1_048_576, 2_097_152,
               Root_Value, State);
         end Worker;
      begin
         declare
            function Worker_Terminated return Boolean is (Worker'Terminated);
         begin
            Hooks.Arm (Hooks.Snapshot_Root_Precommit);
            Worker.Start;
            Wait_And_Abort (Hooks.Snapshot_Root_Precommit, Worker'Identity);
            Wait_For_Termination
              (Worker_Terminated'Access, "root snapshot worker did not terminate after abort");
         end;
      end;
      Require (Budgets.Current_State (Budget) = Budgets.Active,
               "root snapshot abort poisoned its matching budget");
      Read_Ownership_Counts (After);
      Require_Balanced_Delta (Before, After, "root snapshot abort leaked ownership");
      Require (Hooks.Snapshot_Failures_Clear, "root abort left a snapshot failure armed");
   end;

   declare
      Budget  : aliased Budgets.Budget;
      Session : Budgets.Session_Tag;
      Before, After : Ownership_Counts;
   begin
      Hooks.Reset_Snapshot_Failures;
      Read_Ownership_Counts (Before);
      Initialize (Budget, Session);
      declare
         Root_Value   : Root (Budget'Access);
         Snapshot     : File_Snapshot (Budget'Access);
         Root_State   : Root_Status := Root_Succeeded;
         Capture_State : Capture_Status := Capture_Succeeded;
         task Worker is
            entry Start;
         end Worker;
         task body Worker is
         begin
            accept Start;
            Capture (Root_Value, "large.bin", Session, Snapshot, Capture_State);
         end Worker;
      begin
         declare
            function Worker_Terminated return Boolean is (Worker'Terminated);
         begin
            Open_Root
              (Root_Path, Session, 4_096, 32, 1_048_576, 2_097_152,
               Root_Value, Root_State);
            Require (Root_State = Root_Succeeded, "capture-abort root setup failed");
            Hooks.Arm (Hooks.Snapshot_Capture_Precommit);
            Worker.Start;
            Wait_And_Abort (Hooks.Snapshot_Capture_Precommit, Worker'Identity);
            Wait_For_Termination
              (Worker_Terminated'Access, "capture snapshot worker did not terminate after abort");
         end;
      end;
      Require (Budgets.Current_State (Budget) = Budgets.Active,
               "capture snapshot abort poisoned its matching budget");
      Read_Ownership_Counts (After);
      Require_Balanced_Delta (Before, After, "capture snapshot abort leaked ownership");
      Require (Hooks.Snapshot_Failures_Clear, "capture abort left a snapshot failure armed");
   end;

   declare
      Budget  : aliased Budgets.Budget;
      Session : Budgets.Session_Tag;
      Before, After : Ownership_Counts;
   begin
      Hooks.Reset_Snapshot_Failures;
      Read_Ownership_Counts (Before);
      Initialize (Budget, Session);
      declare
         Root_Value   : Root (Budget'Access);
         Snapshot     : File_Snapshot (Budget'Access);
         Root_State   : Root_Status := Root_Succeeded;
         Capture_State : Capture_Status := Capture_Succeeded;
         Output       : Ada.Streams.Stream_Element_Array (1 .. 10) := [others => 0];
         Written      : Interfaces.Unsigned_64 := 0;
         Complete     : Boolean := False;
         Query        : Query_Status := Query_Succeeded;
         task Worker is
            entry Start;
         end Worker;
         task body Worker is
         begin
            accept Start;
            Copy_Bytes (Snapshot, Session, 0, Output, Written, Complete, Query);
         end Worker;
      begin
         declare
            function Worker_Terminated return Boolean is (Worker'Terminated);
         begin
            Open_Root
              (Root_Path, Session, 4_096, 32, 1_048_576, 2_097_152,
               Root_Value, Root_State);
            Capture (Root_Value, "large.bin", Session, Snapshot, Capture_State);
            Require
              (Root_State = Root_Succeeded and then Capture_State = Capture_Succeeded,
               "copy-abort setup failed");
            Hooks.Arm (Hooks.Snapshot_Copy_Precommit);
            Worker.Start;
            Wait_And_Abort (Hooks.Snapshot_Copy_Precommit, Worker'Identity);
            Wait_For_Termination
              (Worker_Terminated'Access, "copy snapshot worker did not terminate after abort");
         end;
      end;
      Require (Budgets.Current_State (Budget) = Budgets.Active,
               "copy snapshot abort poisoned its matching budget");
      Read_Ownership_Counts (After);
      Require_Balanced_Delta (Before, After, "copy snapshot abort leaked retained ownership");
      Require (Hooks.Snapshot_Failures_Clear, "copy abort left a snapshot failure armed");
   end;
end Flyology_Serde_Generator.Build_Attestations.Local_Snapshots.Abort_Test;
