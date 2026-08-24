with Flyology_Serde.Deserialization;
with Flyology_Serde.Errors;
with Flyology_Serde.Serialization;

generic
   type Source_Type (<>) is limited private;
   type Builder_Type (<>) is limited private;
   with
     procedure Construct_Null
       (Target : in out Builder_Type; Error : in out Errors.Error_Info);
package Flyology_Serde.Adapters.Nulls is
   --  Every Source_Type value is treated as the same logical null.
   --  Construct_Null may stage only unpublished Builder_Type state.
   procedure Serialize_Value
     (Item  : Source_Type;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info);

   procedure Deserialize_Candidate
     (From   : in out Deserialization.Deserializer'Class;
      Target : in out Builder_Type;
      Error  : in out Errors.Error_Info);
end Flyology_Serde.Adapters.Nulls;
