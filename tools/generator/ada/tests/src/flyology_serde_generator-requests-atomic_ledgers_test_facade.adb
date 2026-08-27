with Flyology_Serde_Generator.Requests.Atomic_Ledgers;
with Interfaces;

package body Flyology_Serde_Generator.Requests.Atomic_Ledgers_Test_Facade is
   package Ledgers renames Flyology_Serde_Generator.Requests.Atomic_Ledgers;
   use type Interfaces.Unsigned_64;
   use type Ledgers.Reserve_Result;

   type Snapshot is record
      Usage    : Budget_Usage;
      Limits   : Generation_Limits;
      Poisoned : Boolean;
   end record;

   function Capture (Value : Operation_Budget) return Snapshot
   is (Usage    => Current_Usage (Value),
       Limits   => Budget_Limits (Value),
       Poisoned => Is_Poisoned (Value));

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   procedure Require_Unchanged
     (Before : Snapshot; Value : Operation_Budget; Message : String)
   is
      After : constant Snapshot := Capture (Value);
   begin
      Require (After.Usage = Before.Usage, Message & ": usage changed");
      Require (After.Limits = Before.Limits, Message & ": limits changed");
      Require (After.Poisoned = Before.Poisoned, Message & ": poison changed");
   end Require_Unchanged;

   function Limits_With
     (Input : Limit_Value; Work : Limit_Value) return Generation_Limits
   is
      Result : Generation_Limits := (others => 1);
   begin
      Result.Maximum_Total_Input_Bytes := Input;
      Result.Maximum_Work_Units := Work;
      return Result;
   end Limits_With;

   function Used
     (Value : Operation_Budget; Kind : Ledgers.Category) return Used_Value
   is
      Usage : constant Budget_Usage := Current_Usage (Value);
   begin
      case Kind is
         when Ledgers.Input_Bytes =>
            return Usage.Input_Bytes;

         when Ledgers.Work_Units  =>
            return Usage.Work_Units;
      end case;
   end Used;

   procedure Reserve
     (Value    : in out Operation_Budget;
      Kind     : Ledgers.Category;
      Amount   : Ledgers.Charge_Amount;
      Expected : Ledgers.Reserve_Result;
      Message  : String)
   is
      Result : Ledgers.Reserve_Result :=
        (case Expected is
           when Ledgers.Reserved      => Ledgers.Bridge_Failed,
           when Ledgers.Denied        => Ledgers.Reserved,
           when Ledgers.Bridge_Failed => Ledgers.Denied);
   begin
      Ledgers.Try_Reserve (Value, Kind, Amount, Result);
      Require (Result = Expected, Message);
   end Reserve;

   procedure Check_Category (Kind : Ledgers.Category) is
      Maximum      : constant Limit_Value := Limit_Value'Last;
      Wide_Maximum : constant Interfaces.Unsigned_64 :=
        Interfaces.Unsigned_64 (Budget_Count'Last);
      Value        : Operation_Budget;
      Before       : Snapshot;
   begin
      Start_Budget (Limits_With (3, 3), Value);
      Reserve
        (Value, Kind, 3, Ledgers.Reserved, "small exact reservation failed");
      Require
        (Used (Value, Kind) = 3, "small exact reservation had wrong usage");
      Before := Capture (Value);
      Reserve
        (Value,
         Kind,
         1,
         Ledgers.Denied,
         "small one-over reservation succeeded");
      Require_Unchanged (Before, Value, "small one-over denial");

      Start_Budget (Limits_With (Maximum, Maximum), Value);
      Reserve
        (Value,
         Kind,
         Ledgers.Charge_Amount (Wide_Maximum),
         Ledgers.Reserved,
         "signed-maximum reservation failed");
      Require
        (Used (Value, Kind) = Used_Value'Last,
         "signed-maximum reservation had wrong usage");

      Start_Budget (Limits_With (Maximum, Maximum), Value);
      Reserve
        (Value,
         Kind,
         Ledgers.Charge_Amount (Wide_Maximum - 1),
         Ledgers.Reserved,
         "one-byte maximum residual setup failed");
      Reserve
        (Value, Kind, 1, Ledgers.Reserved, "one-byte maximum residual failed");
      Before := Capture (Value);
      Reserve
        (Value, Kind, 1, Ledgers.Denied, "full maximum accepted another byte");
      Require_Unchanged (Before, Value, "full maximum denial");

      Start_Budget (Limits_With (Maximum, Maximum), Value);
      Before := Capture (Value);
      Reserve
        (Value,
         Kind,
         Ledgers.Charge_Amount (Wide_Maximum + 1),
         Ledgers.Denied,
         "signed-maximum plus one was accepted");
      Require_Unchanged (Before, Value, "signed-maximum plus one denial");
      Reserve
        (Value,
         Kind,
         1,
         Ledgers.Reserved,
         "budget was not reusable after wide denial");

      Start_Budget (Limits_With (Maximum, Maximum), Value);
      Before := Capture (Value);
      Reserve
        (Value,
         Kind,
         Interfaces.Unsigned_64'Last,
         Ledgers.Denied,
         "unsigned maximum was accepted");
      Require_Unchanged (Before, Value, "unsigned-maximum denial");
      Reserve
        (Value,
         Kind,
         1,
         Ledgers.Reserved,
         "budget was not reusable after U64 denial");

      Start_Budget (Limits_With (Maximum, Maximum), Value);
      Reserve
        (Value,
         Kind,
         Ledgers.Charge_Amount (Wide_Maximum - 2),
         Ledgers.Reserved,
         "maximum residual setup failed");
      Before := Capture (Value);
      Reserve
        (Value,
         Kind,
         3,
         Ledgers.Denied,
         "oversized residual reservation succeeded");
      Require_Unchanged (Before, Value, "residual denial");
      Reserve
        (Value, Kind, 2, Ledgers.Reserved, "exact residual reuse failed");
      Require
        (Used (Value, Kind) = Used_Value'Last,
         "exact residual reuse had wrong usage");
   end Check_Category;

   procedure Run is
      Value  : Operation_Budget;
      Before : Snapshot;
   begin
      Check_Category (Ledgers.Input_Bytes);
      Check_Category (Ledgers.Work_Units);

      Start_Budget (Limits_With (3, 5), Value);
      Reserve
        (Value,
         Ledgers.Input_Bytes,
         2,
         Ledgers.Reserved,
         "input independence failed");
      Reserve
        (Value,
         Ledgers.Work_Units,
         4,
         Ledgers.Reserved,
         "work independence failed");
      Require
        (Current_Usage (Value).Input_Bytes = 2
         and then Current_Usage (Value).Work_Units = 4,
         "categories did not retain independent usage");

      Poison (Value);
      for Kind in Ledgers.Category loop
         Before := Capture (Value);
         Reserve
           (Value,
            Kind,
            1,
            Ledgers.Bridge_Failed,
            "poison was not bridge failure");
         Require_Unchanged (Before, Value, "prepoisoned bridge call");
      end loop;

      Start_Budget (Limits_With (1, 1), Value);
      Value.Input_Bytes := 2;
      Before := Capture (Value);
      Reserve
        (Value,
         Ledgers.Input_Bytes,
         1,
         Ledgers.Bridge_Failed,
         "inconsistent input state was not bridge failure");
      Require_Unchanged (Before, Value, "inconsistent input state");

      Start_Budget (Limits_With (1, 1), Value);
      Value.Work_Units := 2;
      Before := Capture (Value);
      Reserve
        (Value,
         Ledgers.Work_Units,
         1,
         Ledgers.Bridge_Failed,
         "inconsistent work state was not bridge failure");
      Require_Unchanged (Before, Value, "inconsistent work state");
   end Run;
end Flyology_Serde_Generator.Requests.Atomic_Ledgers_Test_Facade;
