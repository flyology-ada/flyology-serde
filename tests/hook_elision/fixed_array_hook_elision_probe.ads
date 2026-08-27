with Flyology_Serde.Deserialization;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;

package Fixed_Array_Hook_Elision_Probe is
   type Position is (First, Second);
   type Pair is array (Position) of Integer;

   procedure Decode
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out Pair;
      Policy : Flyology_Serde.Policies.Decode_Policy;
      Error  : in out Flyology_Serde.Errors.Error_Info);
end Fixed_Array_Hook_Elision_Probe;
