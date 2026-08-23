package body Flyology_Serde.Budgets is
   use type Errors.Error_Code;

   procedure Charge
     (Current : in out Natural;
      Amount  : Natural;
      Maximum : Natural;
      Error   : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif Current > Maximum or else Amount > Maximum - Current then
         Errors.Fail (Error, Errors.Capacity_Exceeded);
      else
         Current := Current + Amount;
      end if;
   end Charge;

   procedure Initialize
     (Self : out Decode_Budget; Limits : Policies.Decode_Limits) is
   begin
      Self.Limits := Limits;
      Self.Current_Depth := 0;
      Self.Container_Items := [others => 0];
      Self.Values := 0;
      Self.Input := 0;
   end Initialize;

   procedure Consume_Input
     (Self  : in out Decode_Budget;
      Units : Natural;
      Error : in out Errors.Error_Info) is
   begin
      Charge (Self.Input, Units, Self.Limits.Maximum_Input_Units, Error);
   end Consume_Input;

   procedure Consume_Value
     (Self : in out Decode_Budget; Error : in out Errors.Error_Info) is
   begin
      Charge (Self.Values, 1, Self.Limits.Maximum_Logical_Values, Error);
   end Consume_Value;

   procedure Enter_Container
     (Self            : in out Decode_Budget;
      Declared_Length : Data_Model.Length_Information;
      Error           : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.Current_Depth = Natural (Self.Limits.Maximum_Nesting_Depth)
      then
         Errors.Fail (Error, Errors.Depth_Exceeded);
      elsif Declared_Length.Known
        and then Declared_Length.Length > Self.Limits.Maximum_Container_Items
      then
         Errors.Fail (Error, Errors.Capacity_Exceeded);
      else
         Self.Current_Depth := Self.Current_Depth + 1;
         Self.Container_Items (Self.Current_Depth) := 0;
      end if;
   end Enter_Container;

   procedure Consume_Container_Item
     (Self : in out Decode_Budget; Error : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.Current_Depth = 0 then
         Errors.Fail (Error, Errors.Invalid_State);
      else
         Charge
           (Self.Container_Items (Self.Current_Depth),
            1,
            Self.Limits.Maximum_Container_Items,
            Error);
      end if;
   end Consume_Container_Item;

   procedure Leave_Container
     (Self : in out Decode_Budget; Error : in out Errors.Error_Info) is
   begin
      if Self.Current_Depth = 0 then
         if Error.Code = Errors.No_Error then
            Errors.Fail (Error, Errors.Invalid_State);
         end if;
      else
         --  Unwind accounting even while preserving an earlier primary error.
         Self.Container_Items (Self.Current_Depth) := 0;
         Self.Current_Depth := Self.Current_Depth - 1;
      end if;
   end Leave_Container;

   procedure Check_Text_Length
     (Self : Decode_Budget; Length : Natural; Error : in out Errors.Error_Info)
   is
   begin
      if Error.Code = Errors.No_Error
        and then Length > Self.Limits.Maximum_Text_Length
      then
         Errors.Fail (Error, Errors.Capacity_Exceeded);
      end if;
   end Check_Text_Length;

   procedure Check_Byte_Length
     (Self : Decode_Budget; Length : Natural; Error : in out Errors.Error_Info)
   is
   begin
      if Error.Code = Errors.No_Error
        and then Length > Self.Limits.Maximum_Byte_Length
      then
         Errors.Fail (Error, Errors.Capacity_Exceeded);
      end if;
   end Check_Byte_Length;

   function Depth (Self : Decode_Budget) return Natural
   is (Self.Current_Depth);

   function Values_Consumed (Self : Decode_Budget) return Natural
   is (Self.Values);

   function Input_Consumed (Self : Decode_Budget) return Natural
   is (Self.Input);

   function Input_Remaining (Self : Decode_Budget) return Natural
   is (if Self.Input >= Self.Limits.Maximum_Input_Units
       then 0
       else Self.Limits.Maximum_Input_Units - Self.Input);
end Flyology_Serde.Budgets;
