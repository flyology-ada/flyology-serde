with Interfaces;

private package Flyology_Serde_Generator.Requests.Atomic_Ledgers is
   type Category is (Input_Bytes, Work_Units);
   subtype Charge_Amount is
     Interfaces.Unsigned_64 range 1 .. Interfaces.Unsigned_64'Last;
   type Reserve_Result is (Reserved, Denied, Bridge_Failed);

   procedure Try_Reserve
     (Value  : in out Operation_Budget;
      Kind   : Category;
      Amount : Charge_Amount;
      Result : out Reserve_Result);
end Flyology_Serde_Generator.Requests.Atomic_Ledgers;
