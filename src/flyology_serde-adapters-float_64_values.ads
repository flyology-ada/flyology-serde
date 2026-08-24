with Flyology_Serde.Data_Model;
with Flyology_Serde.Deserialization;
with Flyology_Serde.Errors;
with Flyology_Serde.Serialization;

package Flyology_Serde.Adapters.Float_64_Values is
   procedure Serialize_Value
     (Item  : Data_Model.Float_64_Value;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info);

   procedure Deserialize_Candidate
     (From   : in out Deserialization.Deserializer'Class;
      Target : in out Data_Model.Float_64_Value;
      Error  : in out Errors.Error_Info);
end Flyology_Serde.Adapters.Float_64_Values;
