with Ada.Unchecked_Conversion;
with Adapter_Conformance_Tests;
with Allocating_Decode_Tests;
with Allocating_Map_Tests;
with Allocating_Sequence_Tests;
with CBOR_Reader_Conformance_Tests;
with CBOR_Reader_Tests;
with CBOR_Writer_Tests;
with Flyology_Serde.Budgets;
with Flyology_Serde.Adapters.Arrays;
with Flyology_Serde.Adapters.Optionals;
with Flyology_Serde.Adapters.Signed_Integers;
with Flyology_Serde.Adapters.Text;
with Flyology_Serde.Deserialization;
with Flyology_Serde.Data_Model;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;
with Flyology_Serde.Serialization;
with Flyology_Serde.Serialization_Adapters;
with Flyology_Serde.Serializers.Counting;
with Flyology_Serde.UTF_8;
with Interfaces;
with Enumeration_Adapter_Tests;
with JSON_Reader_Tests;
with JSON_Writer_Tests;
with Handwritten_Type_Tests;
with Optional_Parity_Tests;
with Record_Adapter_Tests;
with Scalar_Parity_Tests;
with Variant_Adapter_Tests;

procedure Tests is
   package Budgets renames Flyology_Serde.Budgets;
   package Data_Model renames Flyology_Serde.Data_Model;
   package Errors renames Flyology_Serde.Errors;
   package Serialization renames Flyology_Serde.Serialization;
   package Counting renames Flyology_Serde.Serializers.Counting;
   use type Errors.Error_Code;
   use type Errors.Input_Offset_Unit;
   use type Data_Model.Float_64_Category;
   use type Interfaces.IEEE_Float_64;
   use type Interfaces.Unsigned_64;

   Serialization_Limits : constant Serialization.Serialization_Limits :=
     (Maximum_Nesting_Depth   => 32,
      Maximum_Container_Items => 1_024,
      Maximum_Text_Length     => 1_024,
      Maximum_Byte_Length     => 1_024,
      Maximum_Logical_Events  => 4_096);

   function Float_Bits is new Ada.Unchecked_Conversion
     (Interfaces.IEEE_Float_64, Interfaces.Unsigned_64);

   package Integer_Adapter is new
     Flyology_Serde.Adapters.Signed_Integers (Integer);

   type Integer_Array is array (Positive range <>) of Integer;

   type Array_Builder is limited record
      Count : Natural := 0;
   end record;

   procedure Begin_Array
     (Target : in out Array_Builder;
      Length : Data_Model.Length_Information;
      Policy : Flyology_Serde.Policies.Decode_Policy;
      Error  : in out Errors.Error_Info)
   is
      pragma Unreferenced (Length, Policy, Error);
   begin
      Target.Count := 0;
   end Begin_Array;

   procedure Append_Integer
     (From     : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target   : in out Array_Builder;
      Position : Natural;
      Policy   : Flyology_Serde.Policies.Decode_Policy;
      Error    : in out Errors.Error_Info)
   is
      pragma Unreferenced (From, Position, Policy, Error);
   begin
      Target.Count := Target.Count + 1;
   end Append_Integer;

   procedure Finish_Array
     (Target : in out Array_Builder; Error : in out Errors.Error_Info)
   is
      pragma Unreferenced (Target, Error);
   begin
      null;
   end Finish_Array;

   package Integer_Arrays is new
     Flyology_Serde.Adapters.Arrays
       (Index_Type        => Positive,
        Element_Type      => Integer,
        Array_Type        => Integer_Array,
        Builder_Type      => Array_Builder,
        Maximum_Elements  => 16,
        Serialize_Element => Integer_Adapter.Serialize_Value,
        Begin_Candidate   => Begin_Array,
        Append_Element    => Append_Integer,
        Finish_Candidate  => Finish_Array);

   type Maybe_Integer is record
      Present : Boolean := False;
      Value   : Integer := 0;
   end record;

   function Has_Value (Item : Maybe_Integer) return Boolean
   is (Item.Present);

   procedure Serialize_Maybe_Value
     (Item  : Maybe_Integer;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
   begin
      Integer_Adapter.Serialize_Value (Item.Value, Into, Error);
   end Serialize_Maybe_Value;

   procedure Set_None
     (Target : in out Maybe_Integer; Error : in out Errors.Error_Info)
   is
      pragma Unreferenced (Error);
   begin
      Target := (Present => False, Value => 0);
   end Set_None;

   procedure Read_Some
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out Maybe_Integer;
      Policy : Flyology_Serde.Policies.Decode_Policy;
      Error  : in out Errors.Error_Info)
   is
      pragma Unreferenced (Policy);
   begin
      Integer_Adapter.Deserialize_Candidate (From, Target.Value, Error);
      if Error.Code = Errors.No_Error then
         Target.Present := True;
      end if;
   end Read_Some;

   package Maybe_Integers is new
     Flyology_Serde.Adapters.Optionals
       (Source_Type         => Maybe_Integer,
        Builder_Type        => Maybe_Integer,
        Is_Present          => Has_Value,
        Serialize_Present   => Serialize_Maybe_Value,
        Set_Absent          => Set_None,
        Deserialize_Present => Read_Some);

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

   package Sample_Serialization is new
     Flyology_Serde.Serialization_Adapters
       (Source_Type      => Sample,
        Limits           => Serialization_Limits,
        Serialize_Value => Serialize);

   Output         : Counting.Counter;
   Mismatch       : Counting.Counter;
   Bad_Count      : Counting.Counter;
   Bad_Field      : Counting.Counter;
   Deep           : Counting.Counter;
   None_Value     : Counting.Counter;
   Some_Value     : Counting.Counter;
   Bad_Some       : Counting.Counter;
   Adapter_Output : Counting.Counter;
   Float_Output   : Counting.Counter;
   Budget         : Budgets.Decode_Budget;
   Error          : Errors.Error_Info;
begin
   Adapter_Conformance_Tests;
   Allocating_Decode_Tests;
   Allocating_Map_Tests;
   Allocating_Sequence_Tests;
   CBOR_Reader_Conformance_Tests;
   CBOR_Reader_Tests;
   CBOR_Writer_Tests;
   Enumeration_Adapter_Tests;

   declare
      Default : Data_Model.Float_64_Value;
   begin
      pragma Assert (Data_Model.Category (Default) = Data_Model.Finite_Float);
      pragma Assert (Data_Model.Finite_Value (Default) = 0.0);
      pragma Assert (Float_Bits (Data_Model.Finite_Value (Default)) = 0);
   end;

   pragma Assert
     (Data_Model.Category (Data_Model.Positive_Infinity_Value)
      = Data_Model.Positive_Infinity);
   pragma Assert
     (Data_Model.Category (Data_Model.Negative_Infinity_Value)
      = Data_Model.Negative_Infinity);
   pragma Assert
     (Data_Model.Category (Data_Model.Not_A_Number_Value)
      = Data_Model.Not_A_Number);
   pragma Assert (Float_Output.Capabilities.Nonfinite_Float_64);
   pragma Assert (Float_Output.Capabilities.Signed_Float_Zero);

   Float_Output.Begin_Sequence (Data_Model.Known_Length (4), Error);
   Float_Output.Put_Float_64 (Data_Model.Make_Finite (-0.0), Error);
   Float_Output.Put_Float_64 (Data_Model.Positive_Infinity_Value, Error);
   Float_Output.Put_Float_64 (Data_Model.Negative_Infinity_Value, Error);
   Float_Output.Put_Float_64 (Data_Model.Not_A_Number_Value, Error);
   Float_Output.End_Sequence (Error);
   pragma Assert (Error.Code = Errors.No_Error);
   pragma Assert (Float_Output.Event_Count = 6);

   JSON_Reader_Tests;
   JSON_Writer_Tests;
   Handwritten_Type_Tests;
   Optional_Parity_Tests;
   Record_Adapter_Tests;
   Scalar_Parity_Tests;
   Variant_Adapter_Tests;

   Sample_Serialization.Serialize
     ((Identifier => 42, Enabled => True), Output, Error);
   pragma Assert (Error.Code = Errors.No_Error);
   pragma Assert (Output.Event_Count = 6);
   pragma Assert (Output.Container_Depth = 0);

   Errors.Fail (Error, Errors.Application_Error);
   Sample_Serialization.Serialize
     ((Identifier => 99, Enabled => False), Output, Error);
   pragma Assert (Error.Code = Errors.Application_Error);
   pragma Assert (Output.Event_Count = 6);

   Errors.Reset (Error);
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
   Counting.Reset (Deep, Data_Model.All_Capabilities, Serialization_Limits);
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
   Budgets.Initialize
     (Budget,
      (Maximum_Nesting_Depth   => 2,
       Maximum_Container_Items => 1,
       Maximum_Text_Length     => 3,
       Maximum_Byte_Length     => 4,
       Maximum_Input_Units     => 5,
       Maximum_Logical_Values  => 2));
   Budgets.Enter_Container (Budget, (Known => False, Length => 0), Error);
   Budgets.Enter_Container (Budget, (Known => False, Length => 0), Error);
   Budgets.Consume_Container_Item (Budget, Error);
   Budgets.Consume_Container_Item (Budget, Error);
   pragma Assert (Error.Code = Errors.Capacity_Exceeded);
   Budgets.Leave_Container (Budget, Error);
   Budgets.Leave_Container (Budget, Error);
   pragma Assert (Budgets.Depth (Budget) = 0);

   Errors.Reset (Error);
   Budgets.Enter_Container (Budget, (Known => False, Length => 0), Error);
   pragma Assert (Error.Code = Errors.No_Error);
   Budgets.Leave_Container (Budget, Error);

   Integer_Arrays.Serialize_Value ([1, 2, 3], Adapter_Output, Error);
   pragma Assert (Error.Code = Errors.No_Error);
   pragma Assert (Adapter_Output.Event_Count = 5);

   Counting.Reset
     (Adapter_Output, Data_Model.All_Capabilities, Serialization_Limits);
   Maybe_Integers.Serialize_Value
     ((Present => True, Value => 7), Adapter_Output, Error);
   pragma Assert (Error.Code = Errors.No_Error);

   Counting.Reset
     (Adapter_Output, Data_Model.All_Capabilities, Serialization_Limits);
   Flyology_Serde.Adapters.Text.Serialize_Value
     ("valid UTF-8", Adapter_Output, Error);
   pragma Assert (Error.Code = Errors.No_Error);

   Errors.Reset (Error);
   Counting.Reset
     (Adapter_Output, Data_Model.All_Capabilities, Serialization_Limits);
   Flyology_Serde.Adapters.Text.Serialize_Value
     (String'[1 => Character'Val (16#C0#)], Adapter_Output, Error);
   pragma Assert (Error.Code = Errors.Invalid_Text);

   pragma
     Assert
       (not Flyology_Serde.UTF_8.Is_Valid
              (String'
                 [1 => Character'Val (16#E2#), 2 => Character'Val (16#82#)]));
   pragma
     Assert
       (not Flyology_Serde.UTF_8.Is_Valid
              (String'
                 [1 => Character'Val (16#ED#),
                  2 => Character'Val (16#A0#),
                  3 => Character'Val (16#80#)]));
   pragma
     Assert
       (not Flyology_Serde.UTF_8.Is_Valid
              (String'
                 [1 => Character'Val (16#F4#),
                  2 => Character'Val (16#90#),
                  3 => Character'Val (16#80#),
                  4 => Character'Val (16#80#)]));
   pragma
     Assert
       (Flyology_Serde.UTF_8.Is_Valid
          (String'[1 => Character'Val (16#C2#), 2 => Character'Val (16#A2#)]));
end Tests;
