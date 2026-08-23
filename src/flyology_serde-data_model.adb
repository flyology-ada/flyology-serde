package body Flyology_Serde.Data_Model is
   function Category (Item : Float_64_Value) return Float_64_Category
   is (Item.Kind);

   function Finite_Value
     (Item : Float_64_Value) return Interfaces.IEEE_Float_64
   is (Item.Value);

   function Make_Finite
     (Value : Interfaces.IEEE_Float_64) return Float_64_Value
   is ((Kind => Finite_Float, Value => Value));

   function Positive_Infinity_Value return Float_64_Value
   is ((Kind => Positive_Infinity, Value => 0.0));

   function Negative_Infinity_Value return Float_64_Value
   is ((Kind => Negative_Infinity, Value => 0.0));

   function Not_A_Number_Value return Float_64_Value
   is ((Kind => Not_A_Number, Value => 0.0));
end Flyology_Serde.Data_Model;
