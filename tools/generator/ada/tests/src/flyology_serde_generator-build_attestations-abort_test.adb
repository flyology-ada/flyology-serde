with Ada.Real_Time;
with Flyology_Serde_Generator.Build_Attestation_Test_Hooks;
with Flyology_Serde_Generator.Build_Budgets;
with Interfaces;

procedure Flyology_Serde_Generator.Build_Attestations.Abort_Test is
   package Attestations renames Flyology_Serde_Generator.Build_Attestations;
   package Budgets renames Flyology_Serde_Generator.Build_Budgets;
   package Hooks renames Flyology_Serde_Generator.Build_Attestation_Test_Hooks;

   use type Ada.Real_Time.Time;

   Full_Limits : constant Attestations.Attestation_Limits :=
     (Maximum_Path_Bytes                         => 1_024,
      Maximum_Dependency_Name_Bytes              => 64,
      Maximum_Manifest_Bytes_Per_File            => 1_024,
      Maximum_Total_Manifest_Bytes               => 8_192,
      Maximum_Source_Files                       => 1_024,
      Maximum_Source_Bytes_Per_File              => 1_048_576,
      Maximum_Total_Source_Bytes                 => 16_777_216,
      Maximum_Discovered_Entries                 => 4_096,
      Maximum_Directory_Depth                    => 32,
      Maximum_Total_Discovered_Path_Bytes        => 1_048_576,
      Maximum_Dependencies                       => 8,
      Maximum_Dependency_Tree_Entries            => 4_096,
      Maximum_Distinct_Blobs                     => 4_096,
      Maximum_Tree_Listing_Bytes_Per_Dependency  => 1_048_576,
      Maximum_Total_Tree_Listing_Bytes           => 8_388_608,
      Maximum_Blob_Bytes_Per_Blob                => 1_048_576,
      Maximum_Total_Blob_Bytes                   => 16_777_216,
      Maximum_Canonical_Bytes_Per_Projection     => 1_048_576,
      Maximum_Total_Canonical_Bytes              => 8_388_608,
      Maximum_Total_Staged_Bytes                 => 33_554_432,
      Maximum_Git_Commands                       => 4_096,
      Maximum_Git_Observation_Milliseconds       => 60_000,
      Maximum_Tool_Bytes_Per_Executable          => 33_554_432,
      Maximum_Total_Tool_Bytes                   => 67_108_864,
      Process                                    =>
        (Maximum_Argument_Count                  => 32,
         Maximum_Argument_Bytes                  => 4_096,
         Maximum_Environment_Count               => 32,
         Maximum_Environment_Bytes               => 4_096,
         Maximum_Standard_Output_Bytes           => 1_048_576,
         Maximum_Standard_Error_Bytes            => 4_096,
         Timeout_Milliseconds                    => 10_000,
         Observation_Interval_Milliseconds       => 1,
         Maximum_Read_Chunk_Bytes                => 4_096));

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   procedure Initialize_Budget (Value : in out Budgets.Budget) is
      Initialized : Boolean := False;
   begin
      Budgets.Initialize
        ((Maximum_Input_Bytes => Interfaces.Unsigned_64'Last,
          Maximum_Work_Units  => Interfaces.Unsigned_64'Last),
         Value,
         Initialized);
      Require (Initialized, "abort-test budget initialization failed");
   end Initialize_Budget;

   procedure Initialize_Request
     (Value   : in out Attestations.Request;
      Session : Budgets.Session_Tag;
      Status  : in out Attestations.Request_Status) is
   begin
      Attestations.Initialize
        (Value, Session, Full_Limits, "/work/generator", "/tools/bin/git",
         "/tools", "/stage", "/work/alire.lock", Status);
   end Initialize_Request;

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

   type Count_Snapshot is record
      Requests_Allocated     : Natural;
      Requests_Released      : Natural;
      Dependencies_Allocated : Natural;
      Dependencies_Released  : Natural;
   end record;

   function Counts return Count_Snapshot is
      Result : Count_Snapshot;
   begin
      Hooks.Allocation_Counts
        (Result.Requests_Allocated,
         Result.Requests_Released,
         Result.Dependencies_Allocated,
         Result.Dependencies_Released);
      return Result;
   end Counts;

   procedure Require_Delta
     (Before              : Count_Snapshot;
      Request_Allocations : Natural;
      Request_Releases    : Natural;
      Node_Allocations    : Natural;
      Node_Releases       : Natural;
      Message             : String)
   is
      After : constant Count_Snapshot := Counts;
   begin
      Require
        (After.Requests_Allocated = Before.Requests_Allocated + Request_Allocations
         and then After.Requests_Released = Before.Requests_Released + Request_Releases
         and then After.Dependencies_Allocated = Before.Dependencies_Allocated + Node_Allocations
         and then After.Dependencies_Released = Before.Dependencies_Released + Node_Releases,
         Message);
   end Require_Delta;

begin
   declare
      Before : constant Count_Snapshot := Counts;
   begin
      declare
         Budget   : aliased Budgets.Budget;
         Request  : aliased Attestations.Request (Budget'Access);
         Session  : Budgets.Session_Tag;
         Returned : aliased Boolean := False with Atomic;

         task type Worker_Type (Target : not null access Attestations.Request) is
            entry Start (Value : Budgets.Session_Tag);
         end Worker_Type;

         task body Worker_Type is
            Local_Session : Budgets.Session_Tag;
            Status        : Attestations.Request_Status := Attestations.Request_Succeeded;
         begin
            accept Start (Value : Budgets.Session_Tag) do
               Local_Session := Value;
            end Start;
            Initialize_Request (Target.all, Local_Session, Status);
            Returned := True;
         end Worker_Type;

         Worker  : Worker_Type (Request'Access);
         Reached : Boolean;
         Status  : Attestations.Request_Status := Attestations.Request_Succeeded;

         function Worker_Terminated return Boolean is (Worker'Terminated);
      begin
         Initialize_Budget (Budget);
         Session := Budgets.Current_Session (Budget);
         Hooks.Arm (Hooks.Request_Allocation);
         Worker.Start (Session);
         Hooks.Wait_For (Hooks.Request_Allocation, 5.0, Reached);
         Require (Reached, "request-allocation pause was not reached");
         abort Worker;
         Hooks.Release (Hooks.Request_Allocation);
         Wait_Until_Terminated (Worker_Terminated'Access, "request-allocation abort did not terminate");
         Require (not Returned, "request-allocation abort returned through Initialize");
         Attestations.Add_Dependency (Request, Session, "json", "/deps/json", Status);
         Require (Status = Attestations.Request_Invalid, "aborted allocation published a request");
      end;
      Require_Delta (Before, 1, 1, 0, 0, "request-allocation abort leaked or double-freed");
   end;

   declare
      Before : constant Count_Snapshot := Counts;
   begin
      declare
         Budget   : aliased Budgets.Budget;
         Request  : aliased Attestations.Request (Budget'Access);
         Session  : Budgets.Session_Tag;
         Returned : aliased Boolean := False with Atomic;

         task type Worker_Type (Target : not null access Attestations.Request) is
            entry Start (Value : Budgets.Session_Tag);
         end Worker_Type;

         task body Worker_Type is
            Local_Session : Budgets.Session_Tag;
            Status        : Attestations.Request_Status := Attestations.Request_Succeeded;
         begin
            accept Start (Value : Budgets.Session_Tag) do
               Local_Session := Value;
            end Start;
            Initialize_Request (Target.all, Local_Session, Status);
            Returned := True;
         end Worker_Type;

         Worker  : Worker_Type (Request'Access);
         Reached : Boolean;
         Status  : Attestations.Request_Status := Attestations.Request_Succeeded;

         function Worker_Terminated return Boolean is (Worker'Terminated);
      begin
         Initialize_Budget (Budget);
         Session := Budgets.Current_Session (Budget);
         Hooks.Arm (Hooks.Request_Publication);
         Worker.Start (Session);
         Hooks.Wait_For (Hooks.Request_Publication, 5.0, Reached);
         Require (Reached, "request-publication pause was not reached");
         abort Worker;
         Hooks.Release (Hooks.Request_Publication);
         Wait_Until_Terminated (Worker_Terminated'Access, "request-publication abort did not terminate");
         Require (not Returned, "request-publication abort returned through Initialize");
         Attestations.Seal (Request, Session, Status);
         Require (Status = Attestations.Request_Succeeded, "published request was not safely retained");
      end;
      Require_Delta (Before, 1, 1, 0, 0, "request-publication abort leaked or double-freed");
   end;

   declare
      Before : constant Count_Snapshot := Counts;
   begin
      declare
         Budget   : aliased Budgets.Budget;
         Request  : aliased Attestations.Request (Budget'Access);
         Session  : Budgets.Session_Tag;
         Returned : aliased Boolean := False with Atomic;
         Status   : Attestations.Request_Status := Attestations.Request_Succeeded;

         task type Worker_Type (Target : not null access Attestations.Request) is
            entry Start (Value : Budgets.Session_Tag);
         end Worker_Type;

         task body Worker_Type is
            Local_Session : Budgets.Session_Tag;
            Local_Status  : Attestations.Request_Status := Attestations.Request_Succeeded;
         begin
            accept Start (Value : Budgets.Session_Tag) do
               Local_Session := Value;
            end Start;
            Attestations.Add_Dependency (Target.all, Local_Session, "json", "/deps/json", Local_Status);
            Returned := True;
         end Worker_Type;
      begin
         Initialize_Budget (Budget);
         Session := Budgets.Current_Session (Budget);
         Initialize_Request (Request, Session, Status);
         Require (Status = Attestations.Request_Succeeded, "dependency-abort request init failed");
         declare
            Worker  : Worker_Type (Request'Access);
            Reached : Boolean;
            function Worker_Terminated return Boolean is (Worker'Terminated);
         begin
            Hooks.Arm (Hooks.Dependency_Allocation);
            Worker.Start (Session);
            Hooks.Wait_For (Hooks.Dependency_Allocation, 5.0, Reached);
            Require (Reached, "dependency-allocation pause was not reached");
            abort Worker;
            Hooks.Release (Hooks.Dependency_Allocation);
            Wait_Until_Terminated
              (Worker_Terminated'Access, "dependency-allocation abort did not terminate");
            Require (not Returned, "dependency-allocation abort returned through Add_Dependency");
         end;
         Status := Attestations.Request_Succeeded;
         Attestations.Add_Dependency (Request, Session, "json", "/deps/json", Status);
         Require (Status = Attestations.Request_Succeeded, "aborted dependency allocation changed list");
      end;
      Require_Delta (Before, 1, 1, 2, 2, "dependency-allocation abort leaked or double-freed");
   end;

   declare
      Before : constant Count_Snapshot := Counts;
   begin
      declare
         Budget   : aliased Budgets.Budget;
         Request  : aliased Attestations.Request (Budget'Access);
         Session  : Budgets.Session_Tag;
         Returned : aliased Boolean := False with Atomic;
         Status   : Attestations.Request_Status := Attestations.Request_Succeeded;

         task type Worker_Type (Target : not null access Attestations.Request) is
            entry Start (Value : Budgets.Session_Tag);
         end Worker_Type;

         task body Worker_Type is
            Local_Session : Budgets.Session_Tag;
            Local_Status  : Attestations.Request_Status := Attestations.Request_Succeeded;
         begin
            accept Start (Value : Budgets.Session_Tag) do
               Local_Session := Value;
            end Start;
            Attestations.Add_Dependency (Target.all, Local_Session, "json", "/deps/json", Local_Status);
            Returned := True;
         end Worker_Type;
      begin
         Initialize_Budget (Budget);
         Session := Budgets.Current_Session (Budget);
         Initialize_Request (Request, Session, Status);
         Require (Status = Attestations.Request_Succeeded, "dependency-publish request init failed");
         declare
            Worker  : Worker_Type (Request'Access);
            Reached : Boolean;
            function Worker_Terminated return Boolean is (Worker'Terminated);
         begin
            Hooks.Arm (Hooks.Dependency_Publication);
            Worker.Start (Session);
            Hooks.Wait_For (Hooks.Dependency_Publication, 5.0, Reached);
            Require (Reached, "dependency-publication pause was not reached");
            abort Worker;
            Hooks.Release (Hooks.Dependency_Publication);
            Wait_Until_Terminated
              (Worker_Terminated'Access, "dependency-publication abort did not terminate");
            Require (not Returned, "dependency-publication abort returned through Add_Dependency");
         end;
         Status := Attestations.Request_Succeeded;
         Attestations.Add_Dependency (Request, Session, "json", "/deps/json", Status);
         Require (Status = Attestations.Request_Invalid, "published dependency was lost after abort");
      end;
      Require_Delta (Before, 1, 1, 1, 1, "dependency-publication abort leaked or double-freed");
   end;
end Flyology_Serde_Generator.Build_Attestations.Abort_Test;
