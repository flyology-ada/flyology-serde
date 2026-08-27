with Flyology_Serde.Adapters.Fixed_Arrays;
with Flyology_Serde.Adapters.Signed_Integers;

package body Fixed_Array_Hook_Elision_Probe is
   package Integers is new Flyology_Serde.Adapters.Signed_Integers (Integer);

   procedure Decode_Element
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out Integer;
      Policy : Flyology_Serde.Policies.Decode_Policy;
      Error  : in out Flyology_Serde.Errors.Error_Info)
   is
      pragma Unreferenced (Policy);
   begin
      Integers.Deserialize_Candidate (From, Target, Error);
   end Decode_Element;

   package Pairs is new
     Flyology_Serde.Adapters.Fixed_Arrays
       (Index_Type          => Position,
        Element_Type        => Integer,
        Array_Type          => Pair,
        Serialize_Element   => Integers.Serialize_Value,
        Deserialize_Element => Decode_Element);

   procedure Decode
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out Pair;
      Policy : Flyology_Serde.Policies.Decode_Policy;
      Error  : in out Flyology_Serde.Errors.Error_Info) is
   begin
      Pairs.Deserialize_Candidate (From, Target, Policy, Error);
   end Decode;
end Fixed_Array_Hook_Elision_Probe;
