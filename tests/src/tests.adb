with Flyology_Serde.Budgets;
with Flyology_Serde.Errors;
with Flyology_Serde.Serialization;
with Flyology_Serde.Serializers.Counting;
with Interfaces;

procedure Tests is
   package Budgets renames Flyology_Serde.Budgets;
   package Errors renames Flyology_Serde.Errors;
   package Serialization renames Flyology_Serde.Serialization;
   package Counting renames Flyology_Serde.Serializers.Counting;
   use type Errors.Error_Code;
   use type Errors.Input_Offset_Unit;

   type Sample is record
      Identifier : Interfaces.Unsigned_64;
      Enabled    : Boolean;
   end record;

   procedure Serialize
     (Item  : Sample;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
   begin
      Into.Begin_Record ("Tests.Sample", 2, Error);
      Into.Put_Field ("identifier", Error);
      Into.Put_Unsigned (Item.Identifier, Error);
      Into.Put_Field ("enabled", Error);
      Into.Put_Boolean (Item.Enabled, Error);
      Into.End_Record (Error);
   end Serialize;

   Output     : Counting.Counter;
   Mismatch   : Counting.Counter;
   Bad_Count  : Counting.Counter;
   Bad_Field  : Counting.Counter;
   Deep       : Counting.Counter;
   None_Value : Counting.Counter;
   Some_Value : Counting.Counter;
   Bad_Some   : Counting.Counter;
   Budget     : Budgets.Decode_Budget;
   Error      : Errors.Error_Info;
begin
   Serialize ((Identifier => 42, Enabled => True), Output, Error);
   pragma Assert (Error.Code = Errors.No_Error);
   pragma Assert (Output.Event_Count = 6);
   pragma Assert (Output.Container_Depth = 0);

   Output.End_Record (Error);
   pragma Assert (Error.Code = Errors.Invalid_State);

   Errors.Reset (Error);
   Mismatch.Begin_Map ((Known => True, Length => 0), Error);
   Mismatch.End_Record (Error);
   pragma Assert (Error.Code = Errors.Invalid_State);

   Errors.Reset (Error);
   Bad_Count.Begin_Sequence ((Known => True, Length => 1), Error);
   Bad_Count.End_Sequence (Error);
   pragma Assert (Error.Code = Errors.Invalid_State);

   Errors.Reset (Error);
   Bad_Field.Begin_Record ("Tests.Empty", 0, Error);
   Bad_Field.Put_Field ("unexpected", Error);
   pragma Assert (Error.Code = Errors.Invalid_State);

   Errors.Reset (Error);
   for Index in 1 .. Errors.Maximum_Path_Depth loop
      Deep.Begin_Sequence ((Known => False, Length => 0), Error);
   end loop;
   Deep.Begin_Sequence ((Known => False, Length => 0), Error);
   pragma Assert (Error.Code = Errors.Depth_Exceeded);

   Errors.Reset (Error);
   for Index in 1 .. Errors.Maximum_Path_Depth loop
      Errors.Push_Index (Error, Index);
   end loop;
   Errors.Push_Field (Error, "overflow");
   pragma Assert (Error.Code = Errors.Depth_Exceeded);

   Errors.Reset (Error);
   Errors.Push_Field
     (Error,
      "a field name that is deliberately longer than sixty-four characters for truncation");
   pragma Assert (Error.Code = Errors.No_Error);
   pragma Assert (Error.Path (1).Name_Truncated);

   Errors.Reset (Error);
   Errors.Fail (Error, Errors.Syntax_Error, 12, Errors.Byte_Offset);
   pragma Assert (Error.Input_Offset = 12);
   pragma Assert (Error.Offset_Unit = Errors.Byte_Offset);

   Errors.Reset (Error);
   None_Value.Begin_Optional (False, Error);
   None_Value.End_Optional (Error);
   pragma Assert (Error.Code = Errors.No_Error);
   pragma Assert (None_Value.Event_Count = 2);

   Some_Value.Begin_Optional (True, Error);
   Some_Value.Put_Null (Error);
   Some_Value.End_Optional (Error);
   pragma Assert (Error.Code = Errors.No_Error);
   pragma Assert (Some_Value.Event_Count = 3);

   Bad_Some.Begin_Optional (True, Error);
   Bad_Some.End_Optional (Error);
   pragma Assert (Error.Code = Errors.Invalid_State);

   Errors.Reset (Error);
   Budgets.Initialize
     (Budget,
      (Maximum_Nesting_Depth   => 1,
       Maximum_Container_Items => 2,
       Maximum_Text_Length     => 3,
       Maximum_Byte_Length     => 4,
       Maximum_Input_Units     => 5,
       Maximum_Logical_Values  => 1));
   Budgets.Consume_Input (Budget, 5, Error);
   Budgets.Consume_Input (Budget, 1, Error);
   pragma Assert (Error.Code = Errors.Capacity_Exceeded);

   Errors.Reset (Error);
   Budgets.Consume_Value (Budget, Error);
   Budgets.Consume_Value (Budget, Error);
   pragma Assert (Error.Code = Errors.Capacity_Exceeded);

   Errors.Reset (Error);
   Budgets.Enter_Container (Budget, (Known => True, Length => 3), Error);
   pragma Assert (Error.Code = Errors.Capacity_Exceeded);

   Errors.Reset (Error);
   Budgets.Enter_Container (Budget, (Known => False, Length => 0), Error);
   Budgets.Consume_Container_Item (Budget, Error);
   Budgets.Consume_Container_Item (Budget, Error);
   Budgets.Consume_Container_Item (Budget, Error);
   pragma Assert (Error.Code = Errors.Capacity_Exceeded);
end Tests;
