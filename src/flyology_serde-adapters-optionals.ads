with Flyology_Serde.Deserialization;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;
with Flyology_Serde.Serialization;

generic
   type Source_Type (<>) is limited private;
   type Builder_Type (<>) is limited private;
   with function Is_Present (Item : Source_Type) return Boolean;
   with
     procedure Serialize_Present
       (Item  : Source_Type;
        Into  : in out Serialization.Serializer'Class;
        Error : in out Errors.Error_Info);
   with
     procedure Set_Absent
       (Target : in out Builder_Type; Error : in out Errors.Error_Info);
   with
     procedure Deserialize_Present
       (From   : in out Deserialization.Deserializer'Class;
        Target : in out Builder_Type;
        Policy : Policies.Decode_Policy;
        Error  : in out Errors.Error_Info);
package Flyology_Serde.Adapters.Optionals is
   procedure Serialize_Value
     (Item  : Source_Type;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info);

   procedure Deserialize_Candidate
     (From   : in out Deserialization.Deserializer'Class;
      Target : in out Builder_Type;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info);
end Flyology_Serde.Adapters.Optionals;
