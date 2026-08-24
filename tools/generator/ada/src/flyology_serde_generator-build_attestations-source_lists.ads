with Ada.Finalization;
with Interfaces;

private package Flyology_Serde_Generator.Build_Attestations.Source_Lists is
   type Parse_Status is
     (Parse_Succeeded,
      Parse_Session_Foreign,
      Parse_Owner_Not_Empty,
      Parse_Malformed,
      Parse_Limit_Exceeded,
      Parse_Budget_Exhausted,
      Parse_Budget_Failed,
      Parse_Allocation_Failed,
      Parse_Internal_Failure);

   type Parsed_List (Owner : not null access Budgets.Budget) is limited private;

   --  Bytes are an already input-charged same-read snapshot.  This operation owns only the exact Work_Units
   --  charges in docs/reviews/2026-08-24-ada-provenance-list-parser-proposal.md.  Production calls must pass
   --  the exact three limits retained by the same sealed attestation request.  Independent values are
   --  test-only.
   procedure Parse
     (Bytes                      : String;
      Session                    : Budgets.Session_Tag;
      Maximum_Manifest_Bytes_Per_File : Limit_Value;
      Maximum_Path_Bytes         : Limit_Value;
      Maximum_Source_Files       : Limit_Value;
      Into                       : in out Parsed_List;
      Status                     : in out Parse_Status);

   type Visit_Action is (Continue, Stop);
   type Visit_Status is
     (Visit_Succeeded,
      Visit_Session_Foreign,
      Visit_No_List,
      Visit_Reentrant,
      Visit_Stopped,
      Visit_Budget_Exhausted,
      Visit_Budget_Failed,
      Visit_Internal_Failure);

   --  Path is borrowed only for the dynamic call.  Process must not retain any view or derived access value.
   --  It does not recharge the path observation, but owns all of its comparison, copy, hash, allocation, and
   --  candidate-mutation work.  Stop is ordinary and nonpoisoning.  Task abort propagates.
   procedure Visit
     (From    : in out Parsed_List;
      Session : Budgets.Session_Tag;
      Process : not null access procedure
        (Session : Budgets.Session_Tag;
         Path    : String;
         Action  : out Visit_Action);
      Status  : in out Visit_Status);

private
   type Path_Node;
   type Path_Node_Access is access Path_Node;

   type List_Payload is record
      Session  : Budgets.Session_Tag;
      First    : Path_Node_Access := null;
      Last     : Path_Node_Access := null;
      Count    : Interfaces.Unsigned_64 := 0;
      Visiting : Boolean := False;
   end record;
   type List_Payload_Access is access List_Payload;

   type List_Holder (Owner : not null access Budgets.Budget) is
     new Ada.Finalization.Limited_Controlled with record
      Value : List_Payload_Access := null;
   end record;
   overriding procedure Finalize (Value : in out List_Holder);

   type Parsed_List (Owner : not null access Budgets.Budget) is limited record
      Data : List_Holder (Owner);
   end record;
end Flyology_Serde_Generator.Build_Attestations.Source_Lists;
