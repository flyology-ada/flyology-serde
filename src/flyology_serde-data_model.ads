with Interfaces;

--  Logical value kinds exchanged between Ada adapters and format backends.

package Flyology_Serde.Data_Model
  with Pure
is
   type Value_Kind is
     (Null_Value,
      Boolean_Value,
      Signed_Integer_Value,
      Unsigned_Integer_Value,
      Float_Value,
      Text_Value,
      Bytes_Value,
      Optional_Value,
      Sequence_Value,
      Map_Value,
      Record_Value,
      Enumeration_Value,
      Variant_Value);

   type Length_Information is record
      Known  : Boolean := False;
      Length : Natural := 0;
   end record;

   Unknown_Length : constant Length_Information :=
     (Known => False, Length => 0);

   function Known_Length (Length : Natural) return Length_Information
   is ((Known => True, Length => Length));

   type Float_64_Category is
     (Finite_Float, Positive_Infinity, Negative_Infinity, Not_A_Number);

   type Float_64_Value is private;

   function Category (Item : Float_64_Value) return Float_64_Category;

   function Finite_Value
     (Item : Float_64_Value) return Interfaces.IEEE_Float_64
   with Pre => Category (Item) = Finite_Float;

   function Is_Negative_Zero (Item : Float_64_Value) return Boolean;

   function Make_Finite
     (Value : Interfaces.IEEE_Float_64) return Float_64_Value
   with
     Pre  => Value'Valid,
     Post => Category (Make_Finite'Result) = Finite_Float;

   function Positive_Infinity_Value return Float_64_Value
   with Post => Category (Positive_Infinity_Value'Result) = Positive_Infinity;

   function Negative_Infinity_Value return Float_64_Value
   with Post => Category (Negative_Infinity_Value'Result) = Negative_Infinity;

   function Not_A_Number_Value return Float_64_Value
   with Post => Category (Not_A_Number_Value'Result) = Not_A_Number;

   type Format_Capabilities is record
      Unknown_Container_Lengths : Boolean := False;
      Byte_Values               : Boolean := False;
      Nonfinite_Float_64        : Boolean := False;
      Signed_Float_Zero         : Boolean := False;
      --  False accepts exactly Text_Value and Enumeration_Value as map keys.
      --  True accepts every logical Value_Kind losslessly as a map key.
      Arbitrary_Map_Keys        : Boolean := False;
      Lossless_Optionals        : Boolean := False;
   end record;

   All_Capabilities : constant Format_Capabilities := (others => True);

private
   type Float_64_Value is record
      Kind  : Float_64_Category := Finite_Float;
      Value : Interfaces.IEEE_Float_64 := 0.0;
   end record;
end Flyology_Serde.Data_Model;
