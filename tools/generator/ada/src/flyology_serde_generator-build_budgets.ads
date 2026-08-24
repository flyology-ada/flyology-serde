with Interfaces;

private package Flyology_Serde_Generator.Build_Budgets is
   subtype Limit_Value is Interfaces.Unsigned_64 range 1 .. Interfaces.Unsigned_64'Last;
   subtype Charge_Amount is Limit_Value;

   type Category is (Input_Bytes, Work_Units);

   type Limits is record
      Maximum_Input_Bytes : Limit_Value;
      Maximum_Work_Units  : Limit_Value;
   end record;

   type Usage is record
      Input_Bytes : Interfaces.Unsigned_64;
      Work_Units  : Interfaces.Unsigned_64;
   end record;

   type Budget_State is (Active, Exhausted, Failed);
   type Budget is limited private;
   type Session_Tag is private;

   --  A default object is Failed with zero usage and no implicit limits.
   --  Initialize is the only reset operation.  Success assigns a process-lifetime
   --  nonreusing owner identity on first use and advances the nonwrapping session
   --  generation.  If a required owner-token issuance fails or the budget's
   --  generation is exhausted, Initialized is False, State becomes Failed, the
   --  session becomes invalid, and ceilings, usage, and generation are preserved.
   procedure Initialize
     (With_Limits : Limits;
      Into        : in out Budget;
      Initialized : out Boolean);

   --  Current_Session mints no authority and returns an invalid tag unless Value is the
   --  active valid session.  Matches checks identity only, not Active, so cleanup can
   --  retain ownership after ordinary exhaustion or poison.  A copied tag cannot match
   --  a different Budget, including one later created at the same address.
   function Current_Session (Value : aliased Budget) return Session_Tag;
   function Matches (Value : aliased Budget; Expected : Session_Tag) return Boolean;

   --  Reserve is an all-or-nothing debit and state transition within this
   --  call. The owner must not use one Budget concurrently from multiple
   --  tasks; this package provides no synchronization.
   procedure Reserve
     (Value   : in out Budget;
      Kind    : Category;
      Amount  : Charge_Amount;
      Granted : out Boolean);

   --  Poison maps Active to Failed. Exhausted remains Exhausted so a later
   --  cleanup defect cannot replace the primary resource status.
   procedure Poison (Value : in out Budget);

   function Current_State (Value : Budget) return Budget_State;
   function Current_Usage (Value : Budget) return Usage;

private
   type Owner_Token is record
      High : Interfaces.Unsigned_64 := 0;
      Low  : Interfaces.Unsigned_64 := 0;
   end record;
   Invalid_Owner : constant Owner_Token := (High => 0, Low => 0);

   type Session_Tag is record
      Owner      : Owner_Token;
      Generation : Interfaces.Unsigned_64 := 0;
   end record;

   type Budget is limited record
      Ceiling_Input : Interfaces.Unsigned_64 := 0;
      Ceiling_Work  : Interfaces.Unsigned_64 := 0;
      Used_Input    : Interfaces.Unsigned_64 := 0;
      Used_Work     : Interfaces.Unsigned_64 := 0;
      State         : Budget_State := Failed;
      Owner         : Owner_Token;
      Generation    : Interfaces.Unsigned_64 := 0;
      Session_Valid : Boolean := False;
   end record;

   type Owner_Sequence_State is record
      Last_Issued : Owner_Token := Invalid_Owner;
      Exhausted   : Boolean := False;
   end record;

   --  These helpers contain the exact state transition used under the production
   --  protected minter.  They expose no live source and mint no process identity by
   --  themselves; descendants are already trusted with the parent's private state.
   procedure Advance_Owner_Sequence
     (Sequence : in out Owner_Sequence_State;
      Into     : out Owner_Token;
      Minted   : out Boolean);
   procedure Apply_Initialization
     (With_Limits    : Limits;
      Candidate      : Owner_Token;
      Owner_Available : Boolean;
      Into           : in out Budget;
      Initialized    : out Boolean);
end Flyology_Serde_Generator.Build_Budgets;
