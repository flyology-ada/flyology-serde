with Flyology_Serde.Deserialization;
with Flyology_Serde.Errors;
with Flyology_Serde.Serialization;

package Flyology_Serde.Adapters.Text is
   procedure Serialize_Value
     (Item  : String;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info);

   procedure Deserialize_Candidate
     (From   : in out Deserialization.Deserializer'Class;
      Target : out String;
      Length : out Natural;
      Error  : in out Errors.Error_Info);
end Flyology_Serde.Adapters.Text;
