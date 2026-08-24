with Ada.Real_Time;
with Interfaces;

with Flyology_Serde_Generator.Build_Attestation_Test_Hooks;

procedure Flyology_Serde_Generator.Build_Attestations.Source_Lists.Abort_Test is
   package Hooks renames Flyology_Serde_Generator.Build_Attestation_Test_Hooks;
   use type Ada.Real_Time.Time;
   use type Hooks.Transfer_Point;
   use type Interfaces.Unsigned_64;

   P1 : constant String := "alire.toml";
   P2 : constant String := "dependency-identities-v2.json";
   P3 : constant String := "flyology_serde_generator.gpr";
   P4 : constant String := "provenance-files-v2.txt";
   LF : constant Character := Character'Val (10);
   Minimal : constant String := P1 & LF & P2 & LF & P3 & LF & P4 & LF;

   function Comparison_Cost (Left, Right : String) return Interfaces.Unsigned_64 is
     (Interfaces.Unsigned_64 (Natural'Min (Left'Length, Right'Length)) + 2);

   First_Entry_Work : constant Interfaces.Unsigned_64 :=
     Interfaces.Unsigned_64 (P1'Length + 1) +
     Comparison_Cost (P1, P1) +
     Comparison_Cost (P1, P2) +
     Comparison_Cost (P1, P3) +
     Comparison_Cost (P1, P4);
   Parse_Work : constant Interfaces.Unsigned_64 :=
     Interfaces.Unsigned_64 (Minimal'Length) +
     Comparison_Cost (P1, P1) +
     Comparison_Cost (P1, P2) +
     Comparison_Cost (P1, P3) +
     Comparison_Cost (P1, P4) +
     Comparison_Cost (P1, P2) +
     Comparison_Cost (P2, P2) +
     Comparison_Cost (P2, P3) +
     Comparison_Cost (P2, P4) +
     Comparison_Cost (P2, P3) +
     Comparison_Cost (P3, P3) +
     Comparison_Cost (P3, P4) +
     Comparison_Cost (P3, P4) +
     Comparison_Cost (P4, P4);

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   procedure Initialize_Budget (Value : in out Budgets.Budget) is
      Initialized : Boolean;
   begin
      Budgets.Initialize
        ((Maximum_Input_Bytes => Interfaces.Unsigned_64'Last,
          Maximum_Work_Units  => Interfaces.Unsigned_64'Last),
         Value,
         Initialized);
      Require (Initialized, "source-list abort budget initialization failed");
   end Initialize_Budget;

   procedure Require_Work
     (Value    : Budgets.Budget;
      Expected : Interfaces.Unsigned_64;
      Message  : String)
   is
      Usage : constant Budgets.Usage := Budgets.Current_Usage (Value);
   begin
      Require
        (Usage.Input_Bytes = 0 and then Usage.Work_Units = Expected,
         Message & " retained the wrong charge trace");
   end Require_Work;

   procedure Wait_Until_Terminated
     (Terminated : not null access function return Boolean;
      Message    : String)
   is
      Deadline : constant Ada.Real_Time.Time :=
        Ada.Real_Time.Clock + Ada.Real_Time.To_Time_Span (5.0);
   begin
      while not Terminated.all loop
         if Ada.Real_Time.Clock >= Deadline then
            raise Program_Error with Message;
         end if;
         delay 0.001;
      end loop;
   end Wait_Until_Terminated;

   type Counts is record
      Paths_A    : Natural;
      Paths_R    : Natural;
      Nodes_A    : Natural;
      Nodes_R    : Natural;
      Payloads_A : Natural;
      Payloads_R : Natural;
   end record;

   function Snapshot return Counts is
      Result : Counts;
   begin
      Hooks.Source_Allocation_Counts
        (Result.Paths_A, Result.Paths_R, Result.Nodes_A, Result.Nodes_R,
         Result.Payloads_A, Result.Payloads_R);
      return Result;
   end Snapshot;

   procedure Require_Delta
     (Before   : Counts;
      Paths    : Natural;
      Nodes    : Natural;
      Payloads : Natural;
      Message  : String)
   is
      After : constant Counts := Snapshot;
   begin
      Require
        (After.Paths_A = Before.Paths_A + Paths
         and then After.Paths_R = Before.Paths_R + Paths
         and then After.Nodes_A = Before.Nodes_A + Nodes
         and then After.Nodes_R = Before.Nodes_R + Nodes
         and then After.Payloads_A = Before.Payloads_A + Payloads
         and then After.Payloads_R = Before.Payloads_R + Payloads,
         Message & " paths" & Natural'Image (After.Paths_A - Before.Paths_A) & "/" &
         Natural'Image (After.Paths_R - Before.Paths_R) & " nodes" &
         Natural'Image (After.Nodes_A - Before.Nodes_A) & "/" &
         Natural'Image (After.Nodes_R - Before.Nodes_R) & " payloads" &
         Natural'Image (After.Payloads_A - Before.Payloads_A) & "/" &
         Natural'Image (After.Payloads_R - Before.Payloads_R));
   end Require_Delta;

   procedure Run_Parse_Abort
     (Point              : Hooks.Transfer_Point;
      Published          : Boolean;
      Expected_Paths     : Natural;
      Expected_Nodes     : Natural;
      Expected_Payloads  : Natural;
      Expected_Work      : Interfaces.Unsigned_64;
      Label              : String)
   is
      Before : constant Counts := Snapshot;
   begin
      declare
         Budget   : aliased Budgets.Budget;
         Value    : aliased Parsed_List (Budget'Access);
         Session  : Budgets.Session_Tag;
         Returned : aliased Boolean := False with Atomic;

         task type Worker_Type (Target : not null access Parsed_List) is
            entry Start (Item : Budgets.Session_Tag);
         end Worker_Type;

         task body Worker_Type is
            Local_Session : Budgets.Session_Tag;
            Status        : Parse_Status := Parse_Succeeded;
         begin
            accept Start (Item : Budgets.Session_Tag) do
               Local_Session := Item;
            end Start;
            Parse
              (Minimal, Local_Session, Minimal'Length, 29, 4, Target.all, Status);
            Returned := True;
         end Worker_Type;

         Worker  : Worker_Type (Value'Access);
         Reached : Boolean;
         V_State : Visit_Status := Visit_Succeeded;

         procedure Stop_Visitor
           (Session : Budgets.Session_Tag;
            Path    : String;
            Action  : out Visit_Action)
         is
            pragma Unreferenced (Session, Path);
         begin
            Action := Stop;
         end Stop_Visitor;

         function Worker_Terminated return Boolean is (Worker'Terminated);
      begin
         Initialize_Budget (Budget);
         Session := Budgets.Current_Session (Budget);
         Hooks.Arm (Point);
         Worker.Start (Session);
         Hooks.Wait_For (Point, 5.0, Reached);
         Require (Reached, Label & " pause was not reached");
         abort Worker;
         Hooks.Release (Point);
         Wait_Until_Terminated (Worker_Terminated'Access, Label & " abort did not terminate");
         Require (not Returned, Label & " abort returned through Parse");
         Visit (Value, Session, Stop_Visitor'Access, V_State);
         Require
           (V_State = (if Published then Visit_Stopped else Visit_No_List),
            Label & " publication state changed");
         Require_Work
           (Budget,
            Expected_Work + (if Published then 1 + Interfaces.Unsigned_64 (P1'Length) else 0),
            Label);
      end;
      Require_Delta
        (Before, Expected_Paths, Expected_Nodes, Expected_Payloads,
         Label & " leaked or double-freed ownership");
   end Run_Parse_Abort;

begin
   Run_Parse_Abort
     (Hooks.Source_Path_Allocation, False, 1, 0, 0, First_Entry_Work, "path allocation");
   Run_Parse_Abort
     (Hooks.Source_Node_Allocation, False, 1, 1, 0, First_Entry_Work, "node allocation");
   Run_Parse_Abort
     (Hooks.Source_Node_Publication, False, 1, 1, 0, First_Entry_Work, "node publication");
   Run_Parse_Abort
     (Hooks.Source_Payload_Allocation, False, 4, 4, 1, Parse_Work, "payload allocation");
   Run_Parse_Abort
     (Hooks.Source_Payload_Publication, False, 4, 4, 1, Parse_Work, "payload publication");
   Run_Parse_Abort
     (Hooks.Source_Owner_Publication, True, 4, 4, 1, Parse_Work, "owner publication");

   declare
      Before : constant Counts := Snapshot;
   begin
      declare
         Budget   : aliased Budgets.Budget;
         Value    : aliased Parsed_List (Budget'Access);
         Session  : Budgets.Session_Tag;
         P_State  : Parse_Status := Parse_Succeeded;
         Returned : aliased Boolean := False with Atomic;
         Visit_Charges : Interfaces.Unsigned_64 := 0;

         task type Worker_Type (Target : not null access Parsed_List) is
            entry Start (Item : Budgets.Session_Tag; Point : Hooks.Transfer_Point);
         end Worker_Type;

         task body Worker_Type is
            Local_Session : Budgets.Session_Tag;
            Local_Point   : Hooks.Transfer_Point;
            Status        : Visit_Status := Visit_Succeeded;

            procedure Pausing_Visitor
              (Session : Budgets.Session_Tag;
               Path    : String;
               Action  : out Visit_Action)
            is
               pragma Unreferenced (Session, Path);
               Released : Boolean;
            begin
               if Local_Point = Hooks.Source_Callback then
                  Hooks.Pause (Hooks.Source_Callback, Released);
                  Require (Released, "callback pause timed out");
               end if;
               Action := Continue;
            end Pausing_Visitor;
         begin
            accept Start (Item : Budgets.Session_Tag; Point : Hooks.Transfer_Point) do
               Local_Session := Item;
               Local_Point := Point;
            end Start;
            Visit (Target.all, Local_Session, Pausing_Visitor'Access, Status);
            Returned := True;
         end Worker_Type;

         procedure Check_Visit_Abort (Point : Hooks.Transfer_Point; Label : String) is
            Worker  : Worker_Type (Value'Access);
            Reached : Boolean;
            V_State : Visit_Status := Visit_Succeeded;

            procedure Stop_Visitor
              (Session : Budgets.Session_Tag;
               Path    : String;
               Action  : out Visit_Action)
            is
               pragma Unreferenced (Session, Path);
            begin
               Action := Stop;
            end Stop_Visitor;

            function Worker_Terminated return Boolean is (Worker'Terminated);
         begin
            Returned := False;
            Hooks.Arm (Point);
            Worker.Start (Session, Point);
            Hooks.Wait_For (Point, 5.0, Reached);
            Require (Reached, Label & " pause was not reached");
            abort Worker;
            Hooks.Release (Point);
            Wait_Until_Terminated (Worker_Terminated'Access, Label & " abort did not terminate");
            Require (not Returned, Label & " abort returned through Visit");
            Visit (Value, Session, Stop_Visitor'Access, V_State);
            Require (V_State = Visit_Stopped, Label & " left the visit latch set");
            Visit_Charges :=
              Visit_Charges + 2 * (1 + Interfaces.Unsigned_64 (P1'Length));
            Require_Work
              (Budget, Parse_Work + Visit_Charges, Label);
         end Check_Visit_Abort;
      begin
         Initialize_Budget (Budget);
         Session := Budgets.Current_Session (Budget);
         Parse (Minimal, Session, Minimal'Length, 29, 4, Value, P_State);
         Require (P_State = Parse_Succeeded, "visit-abort setup parse failed");
         Check_Visit_Abort (Hooks.Source_Visit_Latch, "visit latch");
         Check_Visit_Abort (Hooks.Source_Callback, "callback");
      end;
      Require_Delta (Before, 4, 4, 1, "visit abort changed source-list ownership");
   end;
end Flyology_Serde_Generator.Build_Attestations.Source_Lists.Abort_Test;
