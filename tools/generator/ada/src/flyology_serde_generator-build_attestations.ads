with Ada.Finalization;
with Interfaces;

with Flyology_Serde_Generator.Build_Budgets;
with Flyology_Serde_Generator.Build_Processes;
with Flyology_Serde_Generator.Build_SHA_256;

private package Flyology_Serde_Generator.Build_Attestations is
   package Budgets renames Flyology_Serde_Generator.Build_Budgets;
   package Processes renames Flyology_Serde_Generator.Build_Processes;
   package SHA_256 renames Flyology_Serde_Generator.Build_SHA_256;

   subtype Limit_Value is Interfaces.Unsigned_64 range 1 .. Interfaces.Unsigned_64'Last;

   --  Every byte limit counts octets.  Per-file limits apply independently to each accepted file.  Total
   --  limits aggregate all observations in that category without refund.  Manifest files are exactly
   --  provenance-files-v2.txt, dependency-identities-v2.json, dependency-source-selection-v1.json,
   --  alire.toml, and the active lock.  A tree listing and its canonical projection are per dependency.
   --  Source_Files and Total_Source_Bytes aggregate accepted generator files.  Discovered_Entries and
   --  Total_Discovered_Path_Bytes aggregate every entry observation across both closed-set discovery passes.
   --  Path_Bytes applies independently to each caller-supplied, manifest, and discovered path;
   --  Directory_Depth applies to each traversal.  Total_Staged_Bytes includes generator, dependency, and
   --  internally generated project, identity-body, and ready-manifest bytes.
   --  Dependencies counts claims; Dependency_Tree_Entries and Distinct_Blobs aggregate all dependencies.
   --  Git_Commands and Git_Observation_Milliseconds aggregate all invocations.  Total_Tool_Bytes includes
   --  every initial and revalidation tool observation; the per-executable cap aggregates those same reads.
   type Attestation_Limits is record
      Maximum_Path_Bytes                    : Limit_Value;
      Maximum_Dependency_Name_Bytes         : Limit_Value;
      Maximum_Manifest_Bytes_Per_File       : Limit_Value;
      Maximum_Total_Manifest_Bytes          : Limit_Value;
      Maximum_Source_Files                  : Limit_Value;
      Maximum_Source_Bytes_Per_File         : Limit_Value;
      Maximum_Total_Source_Bytes            : Limit_Value;
      Maximum_Discovered_Entries            : Limit_Value;
      Maximum_Directory_Depth               : Limit_Value;
      Maximum_Total_Discovered_Path_Bytes   : Limit_Value;
      Maximum_Dependencies                  : Limit_Value;
      Maximum_Dependency_Tree_Entries       : Limit_Value;
      Maximum_Distinct_Blobs                : Limit_Value;
      Maximum_Tree_Listing_Bytes_Per_Dependency : Limit_Value;
      Maximum_Total_Tree_Listing_Bytes      : Limit_Value;
      Maximum_Blob_Bytes_Per_Blob           : Limit_Value;
      Maximum_Total_Blob_Bytes              : Limit_Value;
      Maximum_Canonical_Bytes_Per_Projection : Limit_Value;
      Maximum_Total_Canonical_Bytes         : Limit_Value;
      Maximum_Total_Staged_Bytes            : Limit_Value;
      Maximum_Git_Commands                  : Limit_Value;
      Maximum_Git_Observation_Milliseconds  : Limit_Value;
      Maximum_Tool_Bytes_Per_Executable     : Limit_Value;
      Maximum_Total_Tool_Bytes              : Limit_Value;
      Process                               : Processes.Process_Limits;
   end record;

   type Request_Status is
     (Request_Succeeded,
      Request_Session_Foreign,
      Request_Invalid,
      Request_Limit_Exceeded,
      Request_Budget_Exhausted,
      Request_Budget_Failed,
      Request_Allocation_Failed,
      Request_Internal_Failure);

   type Request (Owner : not null access Budgets.Budget) is limited private;

   --  Request_Succeeded is the only enabled input status for every request operation and remains the
   --  status after success.  Every other input status is latched: the operation performs no work, charges
   --  nothing, and preserves every object and output.  After the status gate, precedence is session/owner,
   --  budget state, retained-state validity, then input validation and charging.  A rejected Initialize or
   --  Add_Dependency preserves the complete prior request.  Any retained payload must carry the same active
   --  session before another payload field is observed.  Only a successful Seal freezes it.
   --  Every path is absolute, contains no NUL, and is retained privately.  Git_Executable must be below
   --  Toolchain_Root.  Staging_Parent is an existing trusted, quiescent directory, not a stage itself.
   procedure Initialize
     (Into             : in out Request;
      Session          : Budgets.Session_Tag;
      Limits           : Attestation_Limits;
      Generator_Root   : String;
      Git_Executable   : String;
      Toolchain_Root   : String;
      Staging_Parent   : String;
      Active_Lock      : String;
      Status           : in out Request_Status);

   --  Crate is the exact canonical dependency name and is bounded by Maximum_Dependency_Name_Bytes before
   --  retention.  Active_Prefix is the absolute active-solution prefix.  Duplicate crates and a claim after
   --  Seal are Request_Invalid.
   procedure Add_Dependency
     (Into          : in out Request;
      Session       : Budgets.Session_Tag;
      Crate         : String;
      Active_Prefix : String;
      Status        : in out Request_Status);

   procedure Seal
     (Into    : in out Request;
      Session : Budgets.Session_Tag;
      Status  : in out Request_Status);

   type Stage_Status is
     (Stage_Succeeded,
      Stage_Session_Foreign,
      Stage_Invalid_Request,
      Stage_Attestation_Unavailable,
      Stage_Malformed_Provenance_List,
      Stage_Malformed_Dependency_Identity,
      Stage_Malformed_Source_Selection,
      Stage_Malformed_Manifest,
      Stage_Malformed_Active_Lock,
      Stage_Closed_Set_Mismatch,
      Stage_Active_Solution_Mismatch,
      Stage_Dependency_Tree_Mismatch,
      Stage_Source_IO_Failed,
      Stage_Staging_IO_Failed,
      Stage_Git_Rejected,
      Stage_Process_Failed,
      Stage_Cleanup_Failed,
      Stage_Limit_Exceeded,
      Stage_Budget_Exhausted,
      Stage_Budget_Failed,
      Stage_Allocation_Failed,
      Stage_Internal_Failure);

   type Checked_Stage (Owner : not null access Budgets.Budget) is limited private;

   --  Stage_Succeeded is the only enabled input status.  Every other status is a zero-charge no-op.
   --  Session matching has precedence over retained request/stage checks: Session must match both owners,
   --  and From.Owner and Into.Owner must designate the same Budget before either payload is observed or
   --  charged.  Precedence is status, exact owner/session match, budget state, then sealed-request and
   --  retained-stage validity, retained payload-session match, input observation, and charging.  Cleanup
   --  damage remains secondary to the first failure.
   --  Success transactionally replaces an earlier unpublished stage owned by the same session.  Failure
   --  preserves it and publishes neither a digest nor a candidate path.
   procedure Create_Checked_Stage
     (From    : Request;
      Session : Budgets.Session_Tag;
      Into    : in out Checked_Stage;
      Status  : in out Stage_Status);

   type Query_Status is
     (Query_Succeeded,
      Query_Session_Foreign,
      Query_No_Stage,
      Query_Budget_Exhausted,
      Query_Budget_Failed,
      Query_Internal_Failure);

   --  Query_Succeeded is the only enabled input status; every other status is a zero-charge no-op.  After
   --  the status gate, precedence is session/owner, budget state, then retained-stage validity.  A valid
   --  stage must also carry the active session before another payload field is observed.  A valid query
   --  reserves one Work_Units probe and then 64 Work_Units before copying.  Either denial reports the
   --  matching budget status, performs no later reservation, and preserves Into.  This fixed digest is the
   --  only successful observation before publication.  Every non-success preserves Into.
   procedure Read_Generator_Identity
     (From     : Checked_Stage;
      Session  : Budgets.Session_Tag;
      Into     : in out SHA_256.Hex_Digest;
      Status   : in out Query_Status);

   type Publish_Status is
     (Publish_Succeeded,
      Publish_Session_Foreign,
      Publish_No_Stage,
      Publish_Invalid_Path,
      Publish_Output_Exists,
      Publish_Stage_Changed,
      Publish_IO_Failed,
      Publish_Cleanup_Failed,
      Publish_Limit_Exceeded,
      Publish_Budget_Exhausted,
      Publish_Budget_Failed,
      Publish_Allocation_Failed,
      Publish_Internal_Failure);

   --  Publish_Succeeded is the only enabled input status; every other status is a zero-charge no-op.  After
   --  the status gate, precedence is session/owner, budget state, retained-stage validity, then path
   --  validation and charging.  A retained stage must carry the active session before another payload field
   --  is observed.  Every failure preserves the unpublished Checked_Stage.
   --  Published_Path is an absolute nonexistent path on the retained staging filesystem.  Success closes
   --  every writable descriptor, revalidates exact bytes and identities, publishes the ready manifest last,
   --  and enters one abort-deferred transaction containing the atomic no-replace rename, Checked_Stage
   --  detach, and cleanup-ownership transfer.  No fallible work follows the rename.  The ready manifest and
   --  published path are sufficient recovery authority if abort is delivered immediately after transfer.
   --  No stage path is observable before success; success leaves Checked_Stage empty and detached.
   procedure Publish_For_Build
     (Into           : in out Checked_Stage;
      Session        : Budgets.Session_Tag;
      Published_Path : String;
      Status         : in out Publish_Status);

private
   type Request_Payload;
   type Request_Payload_Access is access Request_Payload;

   type Request_Holder (Owner : not null access Budgets.Budget) is
     new Ada.Finalization.Limited_Controlled with record
      Value : Request_Payload_Access := null;
   end record;
   --  Finalization is nonraising, preserves an earlier primary status, never deletes through an unverified
   --  retained identity, and poisons the owning budget if cleanup state is damaged.
   overriding procedure Finalize (Value : in out Request_Holder);

   type Request (Owner : not null access Budgets.Budget) is limited record
      Data : Request_Holder (Owner);
   end record;

   type Stage_Payload;
   type Stage_Payload_Access is access Stage_Payload;

   type Stage_Holder (Owner : not null access Budgets.Budget) is
     new Ada.Finalization.Limited_Controlled with record
      Value : Stage_Payload_Access := null;
   end record;
   --  Finalization is nonraising and identity-safe.  It retains an ambiguous stage instead of deleting
   --  through a possibly replaced name, preserves an earlier primary status, and poisons the owner on damage.
   overriding procedure Finalize (Value : in out Stage_Holder);

   type Checked_Stage (Owner : not null access Budgets.Budget) is limited record
      Data : Stage_Holder (Owner);
   end record;
end Flyology_Serde_Generator.Build_Attestations;
