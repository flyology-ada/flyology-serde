with Flyology_Serde.Deserialization;
with Flyology_Serde.Errors;
with Flyology_Serde.Serialization;

generic
   type Value_Type is range <>;
package Flyology_Serde.Adapters.Signed_Integers is
   procedure Serialize_Value
     (Item  : Value_Type;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info);

   procedure Deserialize_Candidate
     (From   : in out Deserialization.Deserializer'Class;
      Target : in out Value_Type;
      Error  : in out Errors.Error_Info);
end Flyology_Serde.Adapters.Signed_Integers;
