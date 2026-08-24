package body Flyology_Serde_Generator.Build_Budgets is
   use type Interfaces.Unsigned_64;

   procedure Initialize
     (With_Limits : Limits;
      Into        : out Budget)
   is
   begin
      Into.Ceiling_Input := With_Limits.Maximum_Input_Bytes;
      Into.Ceiling_Work := With_Limits.Maximum_Work_Units;
      Into.Used_Input := 0;
      Into.Used_Work := 0;
      Into.State := Active;
   end Initialize;

   procedure Reserve
     (Value   : in out Budget;
      Kind    : Category;
      Amount  : Charge_Amount;
      Granted : out Boolean)
   is
   begin
      Granted := False;
      if Value.State /= Active then
         return;
      end if;

      case Kind is
         when Input_Bytes =>
            if Value.Used_Input <= Value.Ceiling_Input
              and then Amount <= Value.Ceiling_Input - Value.Used_Input
            then
               Value.Used_Input := Value.Used_Input + Amount;
               Granted := True;
            else
               Value.State := Exhausted;
            end if;
         when Work_Units =>
            if Value.Used_Work <= Value.Ceiling_Work
              and then Amount <= Value.Ceiling_Work - Value.Used_Work
            then
               Value.Used_Work := Value.Used_Work + Amount;
               Granted := True;
            else
               Value.State := Exhausted;
            end if;
      end case;
   exception
      when others =>
         Value.State := Failed;
         Granted := False;
   end Reserve;

   procedure Poison (Value : in out Budget) is
   begin
      if Value.State = Active then
         Value.State := Failed;
      end if;
   exception
      when others =>
         null;
   end Poison;

   function Current_State (Value : Budget) return Budget_State is
     (Value.State);

   function Current_Usage (Value : Budget) return Usage is
     (Input_Bytes => Value.Used_Input,
      Work_Units  => Value.Used_Work);
end Flyology_Serde_Generator.Build_Budgets;
