with Ada.Finalization;
with Ada.Streams;
with Interfaces;

private package Flyology_Serde_Generator.Build_Attestations.Local_Snapshots is
   type Root_Status is
     (Root_Succeeded,
      Root_Session_Foreign,
      Root_Owner_Not_Empty,
      Root_Invalid_Path,
      Root_Limit_Exceeded,
      Root_Open_Failed,
      Root_Identity_Failed,
      Root_Budget_Exhausted,
      Root_Budget_Failed,
      Root_Allocation_Failed,
      Root_Internal_Failure);

   type Root (Owner : not null access Budgets.Budget) is limited private;

   --  Path is an already validated absolute generator-root path. Ancestor components follow ordinary host
   --  resolution; the final component is opened without following a symlink and must be a directory. The
   --  retained descriptor, not Path, anchors every later Capture. Success publishes the owner only after the
   --  exact session, path limits, open, and initial identity observation succeed. Status must initially be
   --  Root_Succeeded; a different value is a zero-charge no-op. The zero-charge precedence is exact session,
   --  then Exhausted or Failed budget state, then nonempty Into. Input observation and reservation follow.
   --  Reserve denial maps to Root_Budget_Exhausted or Root_Budget_Failed. Every accepted charge remains
   --  consumed after a later failure. A failure preserves Into, and mandatory-close failure is primary only
   --  when no earlier failure exists.
   procedure Open_Root
     (Path                          : String;
      Session                       : Budgets.Session_Tag;
      Maximum_Path_Bytes            : Limit_Value;
      Maximum_Directory_Depth       : Limit_Value;
      Maximum_Source_Bytes_Per_File : Limit_Value;
      Maximum_Total_Source_Bytes    : Limit_Value;
      Into                          : in out Root;
      Status                        : in out Root_Status);

   type Capture_Status is
     (Capture_Succeeded,
      Capture_Session_Foreign,
      Capture_No_Root,
      Capture_Owner_Not_Empty,
      Capture_Invalid_Path,
      Capture_Path_Limit_Exceeded,
      Capture_Directory_Depth_Exceeded,
      Capture_Per_File_Limit_Exceeded,
      Capture_Aggregate_Limit_Exceeded,
      Capture_Open_Failed,
      Capture_Not_Regular,
      Capture_Identity_Failed,
      Capture_Read_Failed,
      Capture_Close_Failed,
      Capture_Changed,
      Capture_Budget_Exhausted,
      Capture_Budget_Failed,
      Capture_Allocation_Failed,
      Capture_Internal_Failure);

   type File_Snapshot (Owner : not null access Budgets.Budget) is limited private;

   --  Relative_Path must be borrowed directly from the retained Source_Lists owner in production. This
   --  defensive API validates only the closed portable grammar and cannot grant list membership. Every path
   --  component is opened relative to From's retained directory without following symlinks. The exact opened
   --  regular file is read through EOF, hashed from those same accepted bytes, checked for stable identity,
   --  and independently reopened from From before publication. From owns the aggregate accepted-byte count.
   --  Into must be empty; every failure preserves it. Status must initially be Capture_Succeeded; a different
   --  value is a zero-charge no-op. The remaining zero-charge precedence is unequal owner discriminants or
   --  foreign session; Exhausted or Failed budget state; then absent, stale, or invalid From and nonempty
   --  Into. Reserve denial maps to Capture_Budget_Exhausted or Capture_Budget_Failed. The one-Work path probe
   --  follows.
   --  The exact String-length Maximum_Path_Bytes check precedes path-byte reservation, materialization, and
   --  grammar validation. Every accepted charge remains consumed after a later failure. From's aggregate
   --  accepted-byte count changes atomically only with successful Into publication; a failed capture does not
   --  debit that aggregate. Successful publication requires successful close of every transient descriptor.
   --  Mandatory-close failure becomes primary only when no earlier failure exists. This operation creates no
   --  Checked_Stage or extraction/build authority.
   procedure Capture
     (From          : in out Root;
      Relative_Path : String;
      Session       : Budgets.Session_Tag;
      Into          : in out File_Snapshot;
      Status        : in out Capture_Status);

   type Query_Status is
     (Query_Succeeded,
      Query_Session_Foreign,
      Query_No_Snapshot,
      Query_Output_Too_Small,
      Query_End_Of_Bytes,
      Query_Invalid_Offset,
      Query_Budget_Exhausted,
      Query_Budget_Failed,
      Query_Internal_Failure);

   --  Every query is bound to the exact creating budget session. A prelatched status is a zero-charge no-op.
   --  Otherwise the zero-charge precedence is foreign session, Exhausted or Failed budget state, then missing
   --  or stale snapshot. Reserve denial maps to Query_Budget_Exhausted or Query_Budget_Failed. Every
   --  non-success preserves all data outputs. Written is always a lower-bound-independent count.
   procedure Read_Path_Length
     (From    : File_Snapshot;
      Session : Budgets.Session_Tag;
      Length  : in out Interfaces.Unsigned_64;
      Status  : in out Query_Status);

   procedure Copy_Path
     (From    : File_Snapshot;
      Session : Budgets.Session_Tag;
      Into    : in out String;
      Written : in out Interfaces.Unsigned_64;
      Status  : in out Query_Status);

   procedure Read_Byte_Length
     (From    : File_Snapshot;
      Session : Budgets.Session_Tag;
      Length  : in out Interfaces.Unsigned_64;
      Status  : in out Query_Status);

   --  Offset is zero based. Offset = retained length reports Query_End_Of_Bytes; a larger value reports
   --  Query_Invalid_Offset. A null buffer before the end reports Query_Output_Too_Small. Otherwise this
   --  copies the longest caller-buffer prefix and Complete is true exactly when that copy reaches the end.
   procedure Copy_Bytes
     (From     : File_Snapshot;
      Session  : Budgets.Session_Tag;
      Offset   : Interfaces.Unsigned_64;
      Into     : in out Ada.Streams.Stream_Element_Array;
      Written  : in out Interfaces.Unsigned_64;
      Complete : in out Boolean;
      Status   : in out Query_Status);

   procedure Read_Digest_Length
     (From    : File_Snapshot;
      Session : Budgets.Session_Tag;
      Length  : in out Interfaces.Unsigned_64;
      Status  : in out Query_Status);

   procedure Copy_Digest
     (From    : File_Snapshot;
      Session : Budgets.Session_Tag;
      Into    : in out String;
      Written : in out Interfaces.Unsigned_64;
      Status  : in out Query_Status);

private
   type Root_Payload;
   type Root_Payload_Access is access Root_Payload;

   type Root_Holder (Owner : not null access Budgets.Budget) is
     new Ada.Finalization.Limited_Controlled with record
      Value : Root_Payload_Access := null;
   end record;
   overriding procedure Finalize (Value : in out Root_Holder);

   type Root (Owner : not null access Budgets.Budget) is limited record
      Data : Root_Holder (Owner);
   end record;

   type Snapshot_Payload;
   type Snapshot_Payload_Access is access Snapshot_Payload;

   type Snapshot_Holder (Owner : not null access Budgets.Budget) is
     new Ada.Finalization.Limited_Controlled with record
      Value : Snapshot_Payload_Access := null;
   end record;
   overriding procedure Finalize (Value : in out Snapshot_Holder);

   type File_Snapshot (Owner : not null access Budgets.Budget) is limited record
      Data : Snapshot_Holder (Owner);
   end record;
end Flyology_Serde_Generator.Build_Attestations.Local_Snapshots;
