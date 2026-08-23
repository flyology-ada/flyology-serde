with Flyology_Serde.Data_Model;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;

--  Overflow-safe accounting shared by bounded format backends and adapters.

package Flyology_Serde.Budgets
  with Preelaborate
is
   package Data_Model renames Flyology_Serde.Data_Model;
   package Errors renames Flyology_Serde.Errors;
   package Policies renames Flyology_Serde.Policies;

   type Decode_Budget is limited private;

   procedure Initialize
     (Self : out Decode_Budget; Limits : Policies.Decode_Limits);

   procedure Consume_Input
     (Self  : in out Decode_Budget;
      Units : Natural;
      Error : in out Errors.Error_Info);

   procedure Consume_Value
     (Self : in out Decode_Budget; Error : in out Errors.Error_Info);

   procedure Enter_Container
     (Self            : in out Decode_Budget;
      Declared_Length : Data_Model.Length_Information;
      Error           : in out Errors.Error_Info);

   procedure Consume_Container_Item
     (Self : in out Decode_Budget; Error : in out Errors.Error_Info);

   procedure Leave_Container
     (Self : in out Decode_Budget; Error : in out Errors.Error_Info);

   procedure Check_Text_Length
     (Self   : Decode_Budget;
      Length : Natural;
      Error  : in out Errors.Error_Info);

   procedure Check_Byte_Length
     (Self   : Decode_Budget;
      Length : Natural;
      Error  : in out Errors.Error_Info);

   function Depth (Self : Decode_Budget) return Natural;
   function Values_Consumed (Self : Decode_Budget) return Natural;
   function Input_Consumed (Self : Decode_Budget) return Natural;
   function Input_Remaining (Self : Decode_Budget) return Natural;

private
   type Container_Count_Array is
     array (Positive range 1 .. Policies.Maximum_Supported_Nesting) of Natural;

   type Decode_Budget is limited record
      Limits          : Policies.Decode_Limits;
      Current_Depth   : Natural := 0;
      Container_Items : Container_Count_Array := [others => 0];
      Values          : Natural := 0;
      Input           : Natural := 0;
   end record;
end Flyology_Serde.Budgets;
