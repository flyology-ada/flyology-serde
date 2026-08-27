package body Flyology_Serde_Generator.Requests.Atomic_Ledgers is
   use type Interfaces.Unsigned_64;

   procedure Try_Reserve
     (Value  : in out Operation_Budget;
      Kind   : Category;
      Amount : Charge_Amount;
      Result : out Reserve_Result)
   is
      Current   : Budget_Count;
      Maximum   : Budget_Count;
      Added     : Budget_Count;
      Candidate : Budget_Count;
   begin
      Result := Bridge_Failed;
      if Value.Failed then
         return;
      end if;

      case Kind is
         when Input_Bytes =>
            Current := Value.Input_Bytes;
            Maximum := Budget_Count (Value.Limits.Maximum_Total_Input_Bytes);

         when Work_Units  =>
            Current := Value.Work_Units;
            Maximum := Budget_Count (Value.Limits.Maximum_Work_Units);
      end case;

      if Current > Maximum then
         return;
      elsif Amount > Interfaces.Unsigned_64 (Budget_Count'Last) then
         Result := Denied;
         return;
      end if;

      Added := Budget_Count (Amount);
      if Added > Maximum - Current then
         Result := Denied;
         return;
      end if;
      Candidate := Current + Added;

      case Kind is
         when Input_Bytes =>
            Value.Input_Bytes := Candidate;

         when Work_Units  =>
            Value.Work_Units := Candidate;
      end case;
      Result := Reserved;
   exception
      when others =>
         Result := Bridge_Failed;
   end Try_Reserve;
end Flyology_Serde_Generator.Requests.Atomic_Ledgers;
