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

   --  A default object is Failed with zero usage and no implicit limits.
   --  Initialize is the only reset operation.
   procedure Initialize
     (With_Limits : Limits;
      Into        : out Budget);

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
   type Budget is limited record
      Ceiling_Input : Interfaces.Unsigned_64 := 0;
      Ceiling_Work  : Interfaces.Unsigned_64 := 0;
      Used_Input    : Interfaces.Unsigned_64 := 0;
      Used_Work     : Interfaces.Unsigned_64 := 0;
      State         : Budget_State := Failed;
   end record;
end Flyology_Serde_Generator.Build_Budgets;
