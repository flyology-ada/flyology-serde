with Ada.Strings.Unbounded;
with Flyology_Serde.Deserialization;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;
with Flyology_Serde.Serialization;

--  Standard-heap UTF-8 candidate adapter. Decode scratch storage is eagerly
--  sized to the configured maximum text length.

package Flyology_Serde.Adapters.Allocating_Text is
   subtype Value is Ada.Strings.Unbounded.Unbounded_String;

   procedure Serialize_Value
     (Item  : Value;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info);

   procedure Deserialize_Candidate
     (From   : in out Deserialization.Deserializer'Class;
      Target : in out Value;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info);
end Flyology_Serde.Adapters.Allocating_Text;
