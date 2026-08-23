with Ada.Streams;
with Flyology_Serde.Deserialization_Adapters;

--  Standard-heap snapshot facade for one synchronous CBOR root transaction.

generic
   with package Adapter is new Flyology_Serde.Deserialization_Adapters (<>);
package Flyology_Serde.Deserializers.CBOR.Copied_Input is
   procedure Deserialize
     (Input  : Ada.Streams.Stream_Element_Array;
      Target : in out Adapter.Builder;
      Error  : in out Errors.Error_Info);
end Flyology_Serde.Deserializers.CBOR.Copied_Input;
