with Ada.Streams;
with Flyology_Serde.Deserialization;
with Flyology_Serde.Errors;
with Flyology_Serde.Serialization;

package Flyology_Serde.Adapters.Bytes is
   procedure Serialize_Value
     (Item  : Ada.Streams.Stream_Element_Array;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info);

   procedure Deserialize_Candidate
     (From   : in out Deserialization.Deserializer'Class;
      Target : in out Ada.Streams.Stream_Element_Array;
      Length : out Natural;
      Error  : in out Errors.Error_Info);

   procedure Deserialize_Exact
     (From   : in out Deserialization.Deserializer'Class;
      Target : in out Ada.Streams.Stream_Element_Array;
      Error  : in out Errors.Error_Info);
end Flyology_Serde.Adapters.Bytes;
