with Flyology_Serde_Generator.Build_Attestation_Test_Hooks;
with Flyology_Serde_Generator.Build_Attestations;
with Flyology_Serde_Generator.Build_Budgets;
with Interfaces;

package body Flyology_Serde_Generator.Build_Attestations_Test_Facade is
   package Attestations renames Flyology_Serde_Generator.Build_Attestations;
   package Budgets renames Flyology_Serde_Generator.Build_Budgets;
   package Hooks renames Flyology_Serde_Generator.Build_Attestation_Test_Hooks;

   use type Attestations.Publish_Status;
   use type Attestations.Query_Status;
   use type Attestations.Request_Status;
   use type Attestations.Stage_Status;
   use type Budgets.Budget_State;
   use type Interfaces.Unsigned_64;

   Generator_Root : constant String := "/work/generator";
   Git_Executable : constant String := "/tools/bin/git";
   Toolchain_Root : constant String := "/tools";
   Staging_Parent : constant String := "/stage";
   Active_Lock    : constant String := "/work/alire.lock";

   function Text_Cost (Value : String) return Interfaces.Unsigned_64 is
     (1 + Interfaces.Unsigned_64 (Value'Length));

   Initialize_Cost : constant Interfaces.Unsigned_64 :=
     Text_Cost (Generator_Root) +
     Text_Cost (Git_Executable) +
     Text_Cost (Toolchain_Root) +
     Text_Cost (Staging_Parent) +
     Text_Cost (Active_Lock);

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

   procedure Require_Work
     (Value    : Budgets.Budget;
      Expected : Interfaces.Unsigned_64)
   is
      Usage : constant Budgets.Usage := Budgets.Current_Usage (Value);
   begin
      Require (Usage.Input_Bytes = 0, "attestation request charged input bytes");
      Require (Usage.Work_Units = Expected, "unexpected attestation request work trace");
   end Require_Work;

   procedure Initialize_Budget
     (Value      : in out Budgets.Budget;
      Maximum_Work : Budgets.Limit_Value)
   is
      Initialized : Boolean := False;
   begin
      Budgets.Initialize
        ((Maximum_Input_Bytes => Interfaces.Unsigned_64'Last,
          Maximum_Work_Units  => Maximum_Work),
         Value,
         Initialized);
      Require (Initialized, "attestation test budget initialization failed");
   end Initialize_Budget;

   procedure Require_Add_Result
     (Crate           : String;
      Active_Prefix   : String;
      Maximum_Work    : Budgets.Limit_Value;
      Expected_Status : Attestations.Request_Status;
      Expected_Work   : Interfaces.Unsigned_64;
      Message         : String)
   is
      Budget  : aliased Budgets.Budget;
      Request : Attestations.Request (Budget'Access);
      Session : Budgets.Session_Tag;
      Status  : Attestations.Request_Status := Attestations.Request_Succeeded;
   begin
      Initialize_Budget (Budget, Maximum_Work);
      Session := Budgets.Current_Session (Budget);
      Attestations.Initialize
        (Request, Session, Full_Limits, Generator_Root, Git_Executable,
         Toolchain_Root, Staging_Parent, Active_Lock, Status);
      Require (Status = Attestations.Request_Succeeded, Message & " setup failed");
      Attestations.Add_Dependency (Request, Session, Crate, Active_Prefix, Status);
      Require (Status = Expected_Status, Message);
      Require_Work (Budget, Expected_Work);
   end Require_Add_Result;

   procedure Require_Dependency_Failure
     (Inject_Storage  : Boolean;
      Expected_Status : Attestations.Request_Status;
      Message         : String)
   is
      Budget  : aliased Budgets.Budget;
      Session : Budgets.Session_Tag;
      Req_A0  : Natural;
      Req_R0  : Natural;
      Dep_A0  : Natural;
      Dep_R0  : Natural;
      Req_A1  : Natural;
      Req_R1  : Natural;
      Dep_A1  : Natural;
      Dep_R1  : Natural;
   begin
      Hooks.Allocation_Counts (Req_A0, Req_R0, Dep_A0, Dep_R0);
      Initialize_Budget (Budget, Interfaces.Unsigned_64'Last);
      Session := Budgets.Current_Session (Budget);
      declare
         Request : Attestations.Request (Budget'Access);
         Status  : Attestations.Request_Status := Attestations.Request_Succeeded;
      begin
         Attestations.Initialize
           (Request, Session, Full_Limits, Generator_Root, Git_Executable,
            Toolchain_Root, Staging_Parent, Active_Lock, Status);
         Attestations.Add_Dependency (Request, Session, "json", "/deps/json", Status);
         Require (Status = Attestations.Request_Succeeded, Message & " setup failed");
         if Inject_Storage then
            Hooks.Arm_Dependency_Storage_Failure;
         else
            Hooks.Arm_Dependency_Internal_Failure;
         end if;
         Attestations.Add_Dependency (Request, Session, "sha2", "/deps/sha2", Status);
         Require (Status = Expected_Status, Message);
         Require (Budgets.Current_State (Budget) = Budgets.Failed, Message & " did not poison budget");
      end;
      Hooks.Allocation_Counts (Req_A1, Req_R1, Dep_A1, Dep_R1);
      Require (Req_A1 - Req_A0 = 1 and then Req_R1 - Req_R0 = 1, Message & " leaked request");
      Require (Dep_A1 - Dep_A0 = 1 and then Dep_R1 - Dep_R0 = 1, Message & " lost prior list");
   end Require_Dependency_Failure;

   procedure Run is
   begin
      declare
         Budget      : aliased Budgets.Budget;
         Other       : aliased Budgets.Budget;
         Request     : Attestations.Request (Budget'Access);
         Stage       : Attestations.Checked_Stage (Budget'Access);
         Foreign     : Attestations.Checked_Stage (Other'Access);
         Session     : Budgets.Session_Tag;
         Other_Tag   : Budgets.Session_Tag;
         Status      : Attestations.Request_Status := Attestations.Request_Succeeded;
         Stage_State : Attestations.Stage_Status := Attestations.Stage_Succeeded;
         Query_State : Attestations.Query_Status := Attestations.Query_Succeeded;
         Pub_State   : Attestations.Publish_Status := Attestations.Publish_Succeeded;
         Identity    : Attestations.SHA_256.Hex_Digest := [others => 'x'];
         Expected    : Interfaces.Unsigned_64 := Initialize_Cost;
         JSON_Name   : constant String (10 .. 13) := "json";
         JSON_Prefix : constant String (20 .. 29) := "/deps/json";
      begin
         Initialize_Budget (Budget, Interfaces.Unsigned_64'Last);
         Initialize_Budget (Other, Interfaces.Unsigned_64'Last);
         Session := Budgets.Current_Session (Budget);
         Other_Tag := Budgets.Current_Session (Other);

         Attestations.Initialize
           (Request, Session, Full_Limits, Generator_Root, Git_Executable,
            Toolchain_Root, Staging_Parent, Active_Lock, Status);
         Require (Status = Attestations.Request_Succeeded, "valid request initialization failed");
         Require_Work (Budget, Expected);

         Attestations.Add_Dependency (Request, Session, JSON_Name, JSON_Prefix, Status);
         Expected := Expected + Text_Cost (JSON_Name) + Text_Cost (JSON_Prefix);
         Require (Status = Attestations.Request_Succeeded, "first dependency failed");
         Require_Work (Budget, Expected);

         Attestations.Add_Dependency (Request, Session, "sha2", "/deps/sha2", Status);
         Expected := Expected + Text_Cost ("sha2") + Text_Cost ("/deps/sha2") + 6;
         Require (Status = Attestations.Request_Succeeded, "second dependency failed");
         Require_Work (Budget, Expected);

         Attestations.Add_Dependency (Request, Session, "json", "/duplicate", Status);
         Expected := Expected + Text_Cost ("json") + Text_Cost ("/duplicate") + 6;
         Require (Status = Attestations.Request_Invalid, "duplicate dependency succeeded");
         Require_Work (Budget, Expected);

         Status := Attestations.Request_Succeeded;
         Attestations.Seal (Request, Session, Status);
         Expected := Expected + 1;
         Require (Status = Attestations.Request_Succeeded, "request seal failed");
         Require_Work (Budget, Expected);

         Attestations.Add_Dependency (Request, Session, "later", "/deps/later", Status);
         Require (Status = Attestations.Request_Invalid, "sealed request accepted a dependency");
         Require_Work (Budget, Expected);

         Stage_State := Attestations.Stage_Succeeded;
         Attestations.Create_Checked_Stage (Request, Session, Stage, Stage_State);
         Require
           (Stage_State = Attestations.Stage_Attestation_Unavailable,
            "request foundation created or misclassified a stage");
         Require_Work (Budget, Expected);

         Query_State := Attestations.Query_Succeeded;
         Attestations.Read_Generator_Identity (Stage, Session, Identity, Query_State);
         Require (Query_State = Attestations.Query_No_Stage, "empty stage identity query misclassified");
         Require (Identity = [1 .. 64 => 'x'], "empty stage identity query changed output");
         Require_Work (Budget, Expected);

         Pub_State := Attestations.Publish_Succeeded;
         Attestations.Publish_For_Build (Stage, Session, "/published", Pub_State);
         Require (Pub_State = Attestations.Publish_No_Stage, "empty stage publication misclassified");
         Require_Work (Budget, Expected);

         Stage_State := Attestations.Stage_Succeeded;
         Attestations.Create_Checked_Stage (Request, Session, Foreign, Stage_State);
         Require (Stage_State = Attestations.Stage_Session_Foreign, "foreign stage owner was accepted");
         Require_Work (Budget, Expected);

         Stage_State := Attestations.Stage_Succeeded;
         Attestations.Create_Checked_Stage (Request, Other_Tag, Stage, Stage_State);
         Require (Stage_State = Attestations.Stage_Session_Foreign, "foreign session was accepted");
         Require_Work (Budget, Expected);

         Query_State := Attestations.Query_Succeeded;
         Attestations.Read_Generator_Identity (Stage, Other_Tag, Identity, Query_State);
         Require (Query_State = Attestations.Query_Session_Foreign, "foreign query was accepted");
         Require (Identity = [1 .. 64 => 'x'], "foreign query changed output");
         Require_Work (Budget, Expected);

         Pub_State := Attestations.Publish_Succeeded;
         Attestations.Publish_For_Build (Stage, Other_Tag, "/published", Pub_State);
         Require (Pub_State = Attestations.Publish_Session_Foreign, "foreign publish was accepted");
         Require_Work (Budget, Expected);
      end;

      declare
         Budget  : aliased Budgets.Budget;
         Request : Attestations.Request (Budget'Access);
         Session : Budgets.Session_Tag;
         Status  : Attestations.Request_Status := Attestations.Request_Succeeded;
      begin
         Initialize_Budget (Budget, Interfaces.Unsigned_64'Last);
         Session := Budgets.Current_Session (Budget);
         Attestations.Initialize
           (Request, Session, Full_Limits, "/work//generator", Git_Executable,
            Toolchain_Root, Staging_Parent, Active_Lock, Status);
         Require (Status = Attestations.Request_Invalid, "repeated path separator was accepted");
         Require_Work (Budget, Text_Cost ("/work//generator"));

         Status := Attestations.Request_Succeeded;
         Attestations.Initialize
           (Request, Session, Full_Limits, Generator_Root, Toolchain_Root,
            Toolchain_Root, Staging_Parent, Active_Lock, Status);
         Require (Status = Attestations.Request_Invalid, "tool root equality was accepted as containment");
         Require_Work (Budget, Text_Cost ("/work//generator") + Initialize_Cost - 8);
      end;

      declare
         Budget  : aliased Budgets.Budget;
         Request : Attestations.Request (Budget'Access);
         Session : Budgets.Session_Tag;
         Status  : Attestations.Request_Status := Attestations.Request_Succeeded;
      begin
         Initialize_Budget (Budget, Budgets.Limit_Value (Text_Cost (Generator_Root)));
         Session := Budgets.Current_Session (Budget);
         Attestations.Initialize
           (Request, Session, Full_Limits, Generator_Root, Git_Executable,
            Toolchain_Root, Staging_Parent, Active_Lock, Status);
         Require (Status = Attestations.Request_Budget_Exhausted, "one-less trace did not exhaust");
         Require (Budgets.Current_State (Budget) = Budgets.Exhausted, "denial did not latch exhaustion");
         Require_Work (Budget, Text_Cost (Generator_Root));
      end;

      declare
         Budget  : aliased Budgets.Budget;
         Request : Attestations.Request (Budget'Access);
         Session : Budgets.Session_Tag;
         Status  : Attestations.Request_Status := Attestations.Request_Succeeded;
      begin
         Initialize_Budget (Budget, Budgets.Limit_Value (Initialize_Cost));
         Session := Budgets.Current_Session (Budget);
         Attestations.Initialize
           (Request, Session, Full_Limits, Generator_Root, Git_Executable,
            Toolchain_Root, Staging_Parent, Active_Lock, Status);
         Require (Status = Attestations.Request_Succeeded, "exact initialize trace failed");
         Require_Work (Budget, Initialize_Cost);
      end;

      declare
         Budget  : aliased Budgets.Budget;
         Request : Attestations.Request (Budget'Access);
         Session : Budgets.Session_Tag;
         Status  : Attestations.Request_Status := Attestations.Request_Succeeded;
      begin
         Initialize_Budget (Budget, Budgets.Limit_Value (Initialize_Cost - 1));
         Session := Budgets.Current_Session (Budget);
         Attestations.Initialize
           (Request, Session, Full_Limits, Generator_Root, Git_Executable,
            Toolchain_Root, Staging_Parent, Active_Lock, Status);
         Require (Status = Attestations.Request_Budget_Exhausted, "full-minus-one init did not exhaust");
         Require_Work (Budget, Initialize_Cost - Interfaces.Unsigned_64 (Active_Lock'Length));
      end;

      declare
         Add_JSON : constant Interfaces.Unsigned_64 :=
           Text_Cost ("json") + Text_Cost ("/deps/json");
         Add_SHA2_Text : constant Interfaces.Unsigned_64 :=
           Text_Cost ("sha2") + Text_Cost ("/deps/sha2");
         Before_Comparison : constant Interfaces.Unsigned_64 :=
           Initialize_Cost + Add_JSON + Add_SHA2_Text;
         Budget  : aliased Budgets.Budget;
         Request : Attestations.Request (Budget'Access);
         Session : Budgets.Session_Tag;
         Status  : Attestations.Request_Status := Attestations.Request_Succeeded;
      begin
         Initialize_Budget (Budget, Budgets.Limit_Value (Before_Comparison));
         Session := Budgets.Current_Session (Budget);
         Attestations.Initialize
           (Request, Session, Full_Limits, Generator_Root, Git_Executable,
            Toolchain_Root, Staging_Parent, Active_Lock, Status);
         Attestations.Add_Dependency (Request, Session, "json", "/deps/json", Status);
         Attestations.Add_Dependency (Request, Session, "sha2", "/deps/sha2", Status);
         Require (Status = Attestations.Request_Budget_Exhausted, "comparison probe denial failed");
         Require_Work (Budget, Before_Comparison);
      end;

      declare
         Add_JSON : constant Interfaces.Unsigned_64 :=
           Text_Cost ("json") + Text_Cost ("/deps/json");
         Add_SHA2_Text : constant Interfaces.Unsigned_64 :=
           Text_Cost ("sha2") + Text_Cost ("/deps/sha2");
         Before_Comparison : constant Interfaces.Unsigned_64 :=
           Initialize_Cost + Add_JSON + Add_SHA2_Text;
         Budget  : aliased Budgets.Budget;
         Request : Attestations.Request (Budget'Access);
         Session : Budgets.Session_Tag;
         Status  : Attestations.Request_Status := Attestations.Request_Succeeded;
      begin
         Initialize_Budget (Budget, Budgets.Limit_Value (Before_Comparison + 5));
         Session := Budgets.Current_Session (Budget);
         Attestations.Initialize
           (Request, Session, Full_Limits, Generator_Root, Git_Executable,
            Toolchain_Root, Staging_Parent, Active_Lock, Status);
         Attestations.Add_Dependency (Request, Session, "json", "/deps/json", Status);
         Attestations.Add_Dependency (Request, Session, "sha2", "/deps/sha2", Status);
         Require (Status = Attestations.Request_Budget_Exhausted, "comparison byte denial failed");
         Require_Work (Budget, Before_Comparison + 1);
      end;

      Require_Add_Result
        ("json", "/deps/json", Budgets.Limit_Value (Initialize_Cost),
         Attestations.Request_Budget_Exhausted, Initialize_Cost,
         "dependency-name probe denial failed");
      Require_Add_Result
        ("json", "/deps/json", Budgets.Limit_Value (Initialize_Cost + 4),
         Attestations.Request_Budget_Exhausted, Initialize_Cost + 1,
         "dependency-name byte denial failed");
      Require_Add_Result
        ("json", "/deps/json", Budgets.Limit_Value (Initialize_Cost + Text_Cost ("json")),
         Attestations.Request_Budget_Exhausted, Initialize_Cost + Text_Cost ("json"),
         "dependency-prefix probe denial failed");
      Require_Add_Result
        ("json", "/deps/json", Budgets.Limit_Value (Initialize_Cost + Text_Cost ("json") + 9),
         Attestations.Request_Budget_Exhausted, Initialize_Cost + Text_Cost ("json") + 1,
         "dependency-prefix byte denial failed");
      Require_Add_Result
        ("", "/deps/json", Interfaces.Unsigned_64'Last,
         Attestations.Request_Invalid, Initialize_Cost + 1,
         "empty dependency name was accepted");
      Require_Add_Result
        ("json", "", Interfaces.Unsigned_64'Last,
         Attestations.Request_Invalid, Initialize_Cost + Text_Cost ("json") + 1,
         "empty dependency prefix was accepted");

      declare
         Budget   : aliased Budgets.Budget;
         Request  : Attestations.Request (Budget'Access);
         Session  : Budgets.Session_Tag;
         Status   : Attestations.Request_Status := Attestations.Request_Succeeded;
         Expected : Interfaces.Unsigned_64 := Initialize_Cost;
      begin
         Initialize_Budget (Budget, Interfaces.Unsigned_64'Last);
         Session := Budgets.Current_Session (Budget);
         Attestations.Initialize
           (Request, Session, Full_Limits, Generator_Root, Git_Executable,
            Toolchain_Root, Staging_Parent, Active_Lock, Status);
         Attestations.Add_Dependency (Request, Session, "json", "/deps/json", Status);
         Expected := Expected + Text_Cost ("json") + Text_Cost ("/deps/json");
         Attestations.Add_Dependency (Request, Session, "sha2", "/deps/sha2", Status);
         Expected := Expected + Text_Cost ("sha2") + Text_Cost ("/deps/sha2") + 6;
         Attestations.Add_Dependency (Request, Session, "sha2", "/duplicate", Status);
         Expected := Expected + Text_Cost ("sha2") + Text_Cost ("/duplicate") + 12;
         Require (Status = Attestations.Request_Invalid, "later duplicate dependency succeeded");
         Require_Work (Budget, Expected);
      end;

      declare
         Budget  : aliased Budgets.Budget;
         Request : Attestations.Request (Budget'Access);
         Session : Budgets.Session_Tag;
         Status  : Attestations.Request_Status := Attestations.Request_Succeeded;
      begin
         Initialize_Budget (Budget, Budgets.Limit_Value (Initialize_Cost));
         Session := Budgets.Current_Session (Budget);
         Attestations.Initialize
           (Request, Session, Full_Limits, Generator_Root, Git_Executable,
            Toolchain_Root, Staging_Parent, Active_Lock, Status);
         Attestations.Seal (Request, Session, Status);
         Require (Status = Attestations.Request_Budget_Exhausted, "seal denial failed");
         Require_Work (Budget, Initialize_Cost);
      end;

      declare
         Budget  : aliased Budgets.Budget;
         Request : Attestations.Request (Budget'Access);
         Session : Budgets.Session_Tag;
         Status  : Attestations.Request_Status := Attestations.Request_Succeeded;
      begin
         Initialize_Budget (Budget, Interfaces.Unsigned_64'Last);
         Session := Budgets.Current_Session (Budget);
         Attestations.Initialize
           (Request, Session, Full_Limits, Generator_Root, Git_Executable,
            Toolchain_Root, Staging_Parent, Active_Lock, Status);
         Attestations.Seal (Request, Session, Status);
         Require_Work (Budget, Initialize_Cost + 1);
         Status := Attestations.Request_Succeeded;
         Attestations.Seal (Request, Session, Status);
         Require (Status = Attestations.Request_Invalid, "repeated seal was not rejected");
         Require_Work (Budget, Initialize_Cost + 1);
         Status := Attestations.Request_Invalid;
         Attestations.Add_Dependency (Request, Session, "later", "/deps/later", Status);
         Attestations.Seal (Request, Session, Status);
         Require (Status = Attestations.Request_Invalid, "prelatched request status changed");
         Require_Work (Budget, Initialize_Cost + 1);
      end;

      declare
         Exact_Path_Limits : constant Attestations.Attestation_Limits :=
           (Full_Limits with delta Maximum_Path_Bytes => 16);
         Budget  : aliased Budgets.Budget;
         Request : Attestations.Request (Budget'Access);
         Session : Budgets.Session_Tag;
         Status  : Attestations.Request_Status := Attestations.Request_Succeeded;
      begin
         Initialize_Budget (Budget, Interfaces.Unsigned_64'Last);
         Session := Budgets.Current_Session (Budget);
         Attestations.Initialize
           (Request, Session, Exact_Path_Limits, Generator_Root, Git_Executable,
            Toolchain_Root, Staging_Parent, Active_Lock, Status);
         Require (Status = Attestations.Request_Succeeded, "exact path limit failed");
      end;

      declare
         Exact_Path_Limits : constant Attestations.Attestation_Limits :=
           (Full_Limits with delta Maximum_Path_Bytes => 16);
         Budget  : aliased Budgets.Budget;
         Request : Attestations.Request (Budget'Access);
         Session : Budgets.Session_Tag;
         Status  : Attestations.Request_Status := Attestations.Request_Succeeded;
      begin
         Initialize_Budget (Budget, Interfaces.Unsigned_64'Last);
         Session := Budgets.Current_Session (Budget);
         Attestations.Initialize
           (Request, Session, Exact_Path_Limits, "/1234567890123456", Git_Executable,
            Toolchain_Root, Staging_Parent, Active_Lock, Status);
         Require (Status = Attestations.Request_Limit_Exceeded, "path max-plus-one was accepted");
         Require_Work (Budget, 1);
      end;

      declare
         One_Dependency : constant Attestations.Attestation_Limits :=
           (Full_Limits with delta
              Maximum_Dependency_Name_Bytes => 4,
              Maximum_Dependencies          => 1);
         Budget  : aliased Budgets.Budget;
         Request : Attestations.Request (Budget'Access);
         Session : Budgets.Session_Tag;
         Status  : Attestations.Request_Status := Attestations.Request_Succeeded;
         Before  : Interfaces.Unsigned_64;
      begin
         Initialize_Budget (Budget, Interfaces.Unsigned_64'Last);
         Session := Budgets.Current_Session (Budget);
         Attestations.Initialize
           (Request, Session, One_Dependency, Generator_Root, Git_Executable,
            Toolchain_Root, Staging_Parent, Active_Lock, Status);
         Attestations.Add_Dependency (Request, Session, "json", "/deps/json", Status);
         Require (Status = Attestations.Request_Succeeded, "exact dependency limits failed");
         Before := Budgets.Current_Usage (Budget).Work_Units;
         Attestations.Add_Dependency (Request, Session, "sha2", "/deps/sha2", Status);
         Require (Status = Attestations.Request_Limit_Exceeded, "dependency max-plus-one was accepted");
         Require_Work (Budget, Before);
      end;

      declare
         Name_Limits : constant Attestations.Attestation_Limits :=
           (Full_Limits with delta Maximum_Dependency_Name_Bytes => 4);
         Budget  : aliased Budgets.Budget;
         Request : Attestations.Request (Budget'Access);
         Session : Budgets.Session_Tag;
         Status  : Attestations.Request_Status := Attestations.Request_Succeeded;
      begin
         Initialize_Budget (Budget, Interfaces.Unsigned_64'Last);
         Session := Budgets.Current_Session (Budget);
         Attestations.Initialize
           (Request, Session, Name_Limits, Generator_Root, Git_Executable,
            Toolchain_Root, Staging_Parent, Active_Lock, Status);
         Attestations.Add_Dependency (Request, Session, "jsonx", "/deps/json", Status);
         Require (Status = Attestations.Request_Limit_Exceeded, "name max-plus-one was accepted");
         Require_Work (Budget, Initialize_Cost + 1);
      end;

      declare
         Budget  : aliased Budgets.Budget;
         Other   : aliased Budgets.Budget;
         Request : Attestations.Request (Budget'Access);
         Session : Budgets.Session_Tag;
         Foreign : Budgets.Session_Tag;
         Status  : Attestations.Request_Status := Attestations.Request_Invalid;
      begin
         Initialize_Budget (Budget, Interfaces.Unsigned_64'Last);
         Initialize_Budget (Other, Interfaces.Unsigned_64'Last);
         Session := Budgets.Current_Session (Budget);
         Foreign := Budgets.Current_Session (Other);
         Attestations.Initialize
           (Request, Session, Full_Limits, Generator_Root, Git_Executable,
            Toolchain_Root, Staging_Parent, Active_Lock, Status);
         Require (Status = Attestations.Request_Invalid, "prelatched status was changed");
         Require_Work (Budget, 0);
         Status := Attestations.Request_Succeeded;
         Attestations.Initialize
           (Request, Foreign, Full_Limits, Generator_Root, Git_Executable,
            Toolchain_Root, Staging_Parent, Active_Lock, Status);
         Require (Status = Attestations.Request_Session_Foreign, "foreign init session was accepted");
         Require_Work (Budget, 0);
      end;

      declare
         Budget      : aliased Budgets.Budget;
         Request     : Attestations.Request (Budget'Access);
         Session     : Budgets.Session_Tag;
         Status      : Attestations.Request_Status := Attestations.Request_Succeeded;
         Initialized : Boolean;
      begin
         Initialize_Budget (Budget, Interfaces.Unsigned_64'Last);
         Session := Budgets.Current_Session (Budget);
         Budgets.Poison (Budget);
         Attestations.Initialize
           (Request, Session, Full_Limits, Generator_Root, Git_Executable,
            Toolchain_Root, Staging_Parent, Active_Lock, Status);
         Require (Status = Attestations.Request_Budget_Failed, "failed ledger was misclassified");
         Require_Work (Budget, 0);

         Budgets.Initialize
           ((Maximum_Input_Bytes => 1, Maximum_Work_Units => 1), Budget, Initialized);
         Require (Initialized, "stale-session budget reinitialize failed");
         Session := Budgets.Current_Session (Budget);
         Status := Attestations.Request_Succeeded;
         Attestations.Initialize
           (Request, Session, Full_Limits, Generator_Root, Git_Executable,
            Toolchain_Root, Staging_Parent, Active_Lock, Status);
         Require (Status = Attestations.Request_Budget_Exhausted, "small ledger denial was misclassified");
      end;

      declare
         Budget      : aliased Budgets.Budget;
         Request     : Attestations.Request (Budget'Access);
         Old_Session : Budgets.Session_Tag;
         New_Session : Budgets.Session_Tag;
         Status      : Attestations.Request_Status := Attestations.Request_Succeeded;
         Initialized : Boolean;
      begin
         Initialize_Budget (Budget, Interfaces.Unsigned_64'Last);
         Old_Session := Budgets.Current_Session (Budget);
         Attestations.Initialize
           (Request, Old_Session, Full_Limits, Generator_Root, Git_Executable,
            Toolchain_Root, Staging_Parent, Active_Lock, Status);
         Budgets.Initialize
           ((Maximum_Input_Bytes => Interfaces.Unsigned_64'Last,
             Maximum_Work_Units  => Interfaces.Unsigned_64'Last),
            Budget,
            Initialized);
         Require (Initialized, "stale-request budget reinitialize failed");
         New_Session := Budgets.Current_Session (Budget);
         Status := Attestations.Request_Succeeded;
         Attestations.Add_Dependency (Request, New_Session, "json", "/deps/json", Status);
         Require (Status = Attestations.Request_Session_Foreign, "stale request session was accepted");
         Status := Attestations.Request_Succeeded;
         Attestations.Initialize
           (Request, New_Session, Full_Limits, Generator_Root, Git_Executable,
            Toolchain_Root, Staging_Parent, Active_Lock, Status);
         Require (Status = Attestations.Request_Session_Foreign, "stale request was reinitialized");
         Status := Attestations.Request_Succeeded;
         Attestations.Seal (Request, New_Session, Status);
         Require (Status = Attestations.Request_Session_Foreign, "stale request was sealed");
         declare
            Stage       : Attestations.Checked_Stage (Budget'Access);
            Stage_State : Attestations.Stage_Status := Attestations.Stage_Succeeded;
         begin
            Attestations.Create_Checked_Stage (Request, New_Session, Stage, Stage_State);
            Require
              (Stage_State = Attestations.Stage_Session_Foreign,
               "stale request created an attestation stage");
         end;
         Require_Work (Budget, 0);
      end;

      declare
         Budget      : aliased Budgets.Budget;
         Request     : Attestations.Request (Budget'Access);
         Stage       : Attestations.Checked_Stage (Budget'Access);
         Session     : Budgets.Session_Tag;
         Stage_State : Attestations.Stage_Status := Attestations.Stage_Invalid_Request;
         Query_State : Attestations.Query_Status := Attestations.Query_No_Stage;
         Pub_State   : Attestations.Publish_Status := Attestations.Publish_No_Stage;
         Identity    : Attestations.SHA_256.Hex_Digest := [others => 'x'];
      begin
         Initialize_Budget (Budget, Interfaces.Unsigned_64'Last);
         Session := Budgets.Current_Session (Budget);
         Attestations.Create_Checked_Stage (Request, Session, Stage, Stage_State);
         Attestations.Read_Generator_Identity (Stage, Session, Identity, Query_State);
         Attestations.Publish_For_Build (Stage, Session, "/published", Pub_State);
         Require
           (Stage_State = Attestations.Stage_Invalid_Request, "prelatched stage status changed");
         Require (Query_State = Attestations.Query_No_Stage, "prelatched query status changed");
         Require (Pub_State = Attestations.Publish_No_Stage, "prelatched publish status changed");
         Require (Identity = [1 .. 64 => 'x'], "prelatched query changed output");
         Require_Work (Budget, 0);
      end;

      declare
         Budget      : aliased Budgets.Budget;
         Request     : Attestations.Request (Budget'Access);
         Stage       : Attestations.Checked_Stage (Budget'Access);
         Session     : Budgets.Session_Tag;
         Stage_State : Attestations.Stage_Status := Attestations.Stage_Succeeded;
         Query_State : Attestations.Query_Status := Attestations.Query_Succeeded;
         Pub_State   : Attestations.Publish_Status := Attestations.Publish_Succeeded;
         Identity    : Attestations.SHA_256.Hex_Digest := [others => 'x'];
         Granted     : Boolean;
      begin
         Initialize_Budget (Budget, 1);
         Session := Budgets.Current_Session (Budget);
         Budgets.Reserve (Budget, Budgets.Work_Units, 1, Granted);
         Require (Granted, "exhausted-stage setup reservation failed");
         Budgets.Reserve (Budget, Budgets.Work_Units, 1, Granted);
         Require (not Granted, "exhausted-stage setup denial failed");
         Attestations.Create_Checked_Stage (Request, Session, Stage, Stage_State);
         Attestations.Read_Generator_Identity (Stage, Session, Identity, Query_State);
         Attestations.Publish_For_Build (Stage, Session, "/published", Pub_State);
         Require
           (Stage_State = Attestations.Stage_Budget_Exhausted,
            "exhausted stage creation was misclassified");
         Require
           (Query_State = Attestations.Query_Budget_Exhausted,
            "exhausted stage query was misclassified");
         Require
           (Pub_State = Attestations.Publish_Budget_Exhausted,
            "exhausted stage publication was misclassified");
         Require (Identity = [1 .. 64 => 'x'], "exhausted query changed output");
         Require_Work (Budget, 1);
      end;

      declare
         Budget      : aliased Budgets.Budget;
         Request     : Attestations.Request (Budget'Access);
         Stage       : Attestations.Checked_Stage (Budget'Access);
         Session     : Budgets.Session_Tag;
         Stage_State : Attestations.Stage_Status := Attestations.Stage_Succeeded;
         Query_State : Attestations.Query_Status := Attestations.Query_Succeeded;
         Pub_State   : Attestations.Publish_Status := Attestations.Publish_Succeeded;
         Identity    : Attestations.SHA_256.Hex_Digest := [others => 'x'];
      begin
         Initialize_Budget (Budget, Interfaces.Unsigned_64'Last);
         Session := Budgets.Current_Session (Budget);
         Budgets.Poison (Budget);
         Attestations.Create_Checked_Stage (Request, Session, Stage, Stage_State);
         Attestations.Read_Generator_Identity (Stage, Session, Identity, Query_State);
         Attestations.Publish_For_Build (Stage, Session, "/published", Pub_State);
         Require
           (Stage_State = Attestations.Stage_Budget_Failed,
            "failed stage creation was misclassified");
         Require
           (Query_State = Attestations.Query_Budget_Failed,
            "failed stage query was misclassified");
         Require
           (Pub_State = Attestations.Publish_Budget_Failed,
            "failed stage publication was misclassified");
         Require (Identity = [1 .. 64 => 'x'], "failed query changed output");
         Require_Work (Budget, 0);
      end;

      declare
         Budget  : aliased Budgets.Budget;
         Request : Attestations.Request (Budget'Access);
         Session : Budgets.Session_Tag;
         Status  : Attestations.Request_Status := Attestations.Request_Succeeded;
         Root    : constant String (10 .. 24) := Generator_Root;
         Git     : constant String (30 .. 43) := Git_Executable;
         Tools   : constant String (50 .. 55) := Toolchain_Root;
         Stage   : constant String (60 .. 65) := Staging_Parent;
         Lock    : constant String (70 .. 85) := Active_Lock;
      begin
         Initialize_Budget (Budget, Interfaces.Unsigned_64'Last);
         Session := Budgets.Current_Session (Budget);
         Attestations.Initialize (Request, Session, Full_Limits, Root, Git, Tools, Stage, Lock, Status);
         Require (Status = Attestations.Request_Succeeded, "arbitrary-bound paths were rejected");
         Require_Work (Budget, Initialize_Cost);
      end;

      declare
         procedure Require_Invalid_Path (Path : String; Message : String) is
            Budget  : aliased Budgets.Budget;
            Request : Attestations.Request (Budget'Access);
            Session : Budgets.Session_Tag;
            Status  : Attestations.Request_Status := Attestations.Request_Succeeded;
         begin
            Initialize_Budget (Budget, Interfaces.Unsigned_64'Last);
            Session := Budgets.Current_Session (Budget);
            Attestations.Initialize
              (Request, Session, Full_Limits, Path, Git_Executable,
               Toolchain_Root, Staging_Parent, Active_Lock, Status);
            Require (Status = Attestations.Request_Invalid, Message);
            Require_Work (Budget, Text_Cost (Path));
         end Require_Invalid_Path;
      begin
         Require_Invalid_Path ("/work/./generator", "dot path component was accepted");
         Require_Invalid_Path ("/work/../generator", "dot-dot path component was accepted");
         Require_Invalid_Path ("/work/generator/", "trailing path separator was accepted");
         Require_Invalid_Path
           ("/work/" & Character'Val (0) & "generator", "NUL path octet was accepted");
      end;

      declare
         Budget  : aliased Budgets.Budget;
         Request : Attestations.Request (Budget'Access);
         Session : Budgets.Session_Tag;
         Status  : Attestations.Request_Status := Attestations.Request_Succeeded;
         type Name_Array is array (Positive range <>) of String (1 .. 5);
         Invalid_Names : constant Name_Array := ["Json ", "1json", "json-"];
      begin
         Initialize_Budget (Budget, Interfaces.Unsigned_64'Last);
         Session := Budgets.Current_Session (Budget);
         Attestations.Initialize
           (Request, Session, Full_Limits, "/work", "/git", "/", "/stage", "/lock", Status);
         Require (Status = Attestations.Request_Succeeded, "root toolchain child was rejected");
         for Name of Invalid_Names loop
            Status := Attestations.Request_Succeeded;
            Attestations.Add_Dependency (Request, Session, Name, "/deps/value", Status);
            Require (Status = Attestations.Request_Invalid, "invalid crate grammar was accepted");
         end loop;
         Status := Attestations.Request_Succeeded;
         Attestations.Add_Dependency (Request, Session, "j", "/deps/j", Status);
         Require (Status = Attestations.Request_Succeeded, "one-letter crate was rejected");
      end;

      declare
         Budget  : aliased Budgets.Budget;
         Request : Attestations.Request (Budget'Access);
         Session : Budgets.Session_Tag;
         Status  : Attestations.Request_Status := Attestations.Request_Succeeded;
      begin
         Initialize_Budget (Budget, Interfaces.Unsigned_64'Last);
         Session := Budgets.Current_Session (Budget);
         Hooks.Arm_Request_Storage_Failure;
         Attestations.Initialize
           (Request, Session, Full_Limits, Generator_Root, Git_Executable,
            Toolchain_Root, Staging_Parent, Active_Lock, Status);
         Require (Status = Attestations.Request_Allocation_Failed, "Storage_Error was misclassified");
         Require (Budgets.Current_State (Budget) = Budgets.Failed, "Storage_Error did not poison budget");
      end;

      declare
         Budget  : aliased Budgets.Budget;
         Request : Attestations.Request (Budget'Access);
         Session : Budgets.Session_Tag;
         Status  : Attestations.Request_Status := Attestations.Request_Succeeded;
      begin
         Initialize_Budget (Budget, Interfaces.Unsigned_64'Last);
         Session := Budgets.Current_Session (Budget);
         Hooks.Arm_Request_Internal_Failure;
         Attestations.Initialize
           (Request, Session, Full_Limits, Generator_Root, Git_Executable,
            Toolchain_Root, Staging_Parent, Active_Lock, Status);
         Require (Status = Attestations.Request_Internal_Failure, "internal failure was misclassified");
         Require (Budgets.Current_State (Budget) = Budgets.Failed, "internal failure did not poison budget");
      end;

      Require_Dependency_Failure
        (True, Attestations.Request_Allocation_Failed,
         "dependency Storage_Error was misclassified");
      Require_Dependency_Failure
        (False, Attestations.Request_Internal_Failure,
         "dependency internal failure was misclassified");

      declare
         Budget  : aliased Budgets.Budget;
         Session : Budgets.Session_Tag;
      begin
         Initialize_Budget (Budget, Interfaces.Unsigned_64'Last);
         Session := Budgets.Current_Session (Budget);
         declare
            Request : Attestations.Request (Budget'Access);
            Status  : Attestations.Request_Status := Attestations.Request_Succeeded;
         begin
            Attestations.Initialize
              (Request, Session, Full_Limits, Generator_Root, Git_Executable,
               Toolchain_Root, Staging_Parent, Active_Lock, Status);
            Require (Status = Attestations.Request_Succeeded, "release-failure setup failed");
            Hooks.Arm_Request_Release_Failure;
         end;
         Require (Budgets.Current_State (Budget) = Budgets.Failed, "cleanup failure did not poison budget");
      end;
   end Run;
end Flyology_Serde_Generator.Build_Attestations_Test_Facade;
