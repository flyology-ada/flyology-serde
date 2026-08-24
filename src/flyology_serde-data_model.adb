with Ada.Unchecked_Conversion;

package body Flyology_Serde.Data_Model is
   use type Interfaces.Unsigned_64;

   function Float_Bits is new Ada.Unchecked_Conversion
     (Interfaces.IEEE_Float_64, Interfaces.Unsigned_64);

   function Category (Item : Float_64_Value) return Float_64_Category
   is (Item.Kind);

   function Finite_Value
     (Item : Float_64_Value) return Interfaces.IEEE_Float_64
   is (Item.Value);

   function Is_Negative_Zero (Item : Float_64_Value) return Boolean
   is
     (Item.Kind = Finite_Float
      and then Float_Bits (Item.Value) = 16#8000_0000_0000_0000#);

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
