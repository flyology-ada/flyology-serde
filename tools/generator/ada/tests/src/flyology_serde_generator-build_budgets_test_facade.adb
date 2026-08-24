with Flyology_Serde_Generator.Build_Budgets;
with Interfaces;

package body Flyology_Serde_Generator.Build_Budgets_Test_Facade is
   package Budgets renames Flyology_Serde_Generator.Build_Budgets;
   use type Budgets.Budget_State;
   use type Interfaces.Unsigned_64;

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   procedure Require_Usage
     (Value : Budgets.Budget;
      Input : Interfaces.Unsigned_64;
      Work  : Interfaces.Unsigned_64)
   is
      Observed : constant Budgets.Usage := Budgets.Current_Usage (Value);
   begin
      Require (Observed.Input_Bytes = Input, "unexpected build input usage");
      Require (Observed.Work_Units = Work, "unexpected build work usage");
   end Require_Usage;

   procedure Run is
      Value   : Budgets.Budget;
      Granted : Boolean := True;
      Full    : constant Budgets.Limits :=
        (Maximum_Input_Bytes => Interfaces.Unsigned_64'Last,
         Maximum_Work_Units  => Interfaces.Unsigned_64'Last);
      Small   : constant Budgets.Limits :=
        (Maximum_Input_Bytes => 3,
         Maximum_Work_Units  => 5);
   begin
      Require (Budgets.Current_State (Value) = Budgets.Failed, "default budget was not failed");
      Require_Usage (Value, 0, 0);
      Budgets.Reserve (Value, Budgets.Input_Bytes, 1, Granted);
      Require (not Granted, "default budget granted input");
      Budgets.Poison (Value);
      Require (Budgets.Current_State (Value) = Budgets.Failed, "default poison changed state");

      Budgets.Initialize (Full, Value);
      Budgets.Reserve
        (Value, Budgets.Input_Bytes, Interfaces.Unsigned_64'Last - 1, Granted);
      Require (Granted, "large input reservation failed");
      Budgets.Reserve (Value, Budgets.Input_Bytes, 1, Granted);
      Require (Granted, "exact input boundary failed");
      Require_Usage (Value, Interfaces.Unsigned_64'Last, 0);
      Budgets.Reserve (Value, Budgets.Input_Bytes, 1, Granted);
      Require (not Granted, "input beyond U64 limit succeeded");
      Require (Budgets.Current_State (Value) = Budgets.Exhausted, "input denial did not exhaust");
      Budgets.Reserve (Value, Budgets.Work_Units, 1, Granted);
      Require (not Granted, "work succeeded after input denial");
      Budgets.Poison (Value);
      Require (Budgets.Current_State (Value) = Budgets.Exhausted, "poison replaced exhaustion");
      Require_Usage (Value, Interfaces.Unsigned_64'Last, 0);

      Budgets.Initialize (Full, Value);
      Require_Usage (Value, 0, 0);
      Budgets.Reserve (Value, Budgets.Work_Units, Interfaces.Unsigned_64'Last, Granted);
      Require (Granted, "exact work U64 boundary failed");
      Budgets.Reserve (Value, Budgets.Work_Units, 1, Granted);
      Require (not Granted, "work beyond U64 limit succeeded");
      Budgets.Reserve (Value, Budgets.Input_Bytes, 1, Granted);
      Require (not Granted, "input succeeded after work denial");
      Require_Usage (Value, 0, Interfaces.Unsigned_64'Last);

      Budgets.Initialize (Small, Value);
      Budgets.Reserve (Value, Budgets.Input_Bytes, 1, Granted);
      Require (Granted, "partial input reservation failed");
      Budgets.Reserve (Value, Budgets.Work_Units, 2, Granted);
      Require (Granted, "partial work reservation failed");
      Budgets.Reserve (Value, Budgets.Input_Bytes, 3, Granted);
      Require (not Granted, "oversized reservation with remainder succeeded");
      Require_Usage (Value, 1, 2);
      Budgets.Reserve (Value, Budgets.Work_Units, 1, Granted);
      Require (not Granted, "work succeeded after partial input denial");
      Require_Usage (Value, 1, 2);

      Budgets.Initialize (Small, Value);
      Budgets.Reserve (Value, Budgets.Input_Bytes, 3, Granted);
      Require (Granted, "small exact input reservation failed");
      Budgets.Reserve (Value, Budgets.Work_Units, 5, Granted);
      Require (Granted, "small exact work reservation failed");
      Require_Usage (Value, 3, 5);
      Budgets.Poison (Value);
      Require (Budgets.Current_State (Value) = Budgets.Failed, "active poison did not fail");
      Require_Usage (Value, 3, 5);

      Budgets.Initialize (Small, Value);
      Require (Budgets.Current_State (Value) = Budgets.Active, "initialize did not reactivate");
      Require_Usage (Value, 0, 0);
   end Run;
end Flyology_Serde_Generator.Build_Budgets_Test_Facade;
