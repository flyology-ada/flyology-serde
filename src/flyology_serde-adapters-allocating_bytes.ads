with Ada.Containers.Vectors;
with Ada.Streams;
with Flyology_Serde.Deserialization;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;
with Flyology_Serde.Serialization;

--  Standard-heap byte-vector candidate adapter. Decode scratch storage is
--  eagerly sized to the configured maximum byte length. A configured maximum
--  that the target Stream_Element_Offset cannot represent is rejected before
--  the candidate or input is touched.

package Flyology_Serde.Adapters.Allocating_Bytes is
   package Byte_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Ada.Streams.Stream_Element,
      "="          => Ada.Streams."=");

   subtype Value is Byte_Vectors.Vector;

   procedure Serialize_Value
     (Item  : Value;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info);

   procedure Deserialize_Candidate
     (From   : in out Deserialization.Deserializer'Class;
      Target : in out Value;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info);
end Flyology_Serde.Adapters.Allocating_Bytes;
