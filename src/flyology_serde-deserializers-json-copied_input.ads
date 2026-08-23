with Flyology_Serde.Deserialization_Adapters;

--  Standard-heap snapshot facade for one synchronous JSON root transaction.

generic
   with package Adapter is new Flyology_Serde.Deserialization_Adapters (<>);
package Flyology_Serde.Deserializers.JSON.Copied_Input is
   procedure Deserialize
     (Input  : String;
      Target : in out Adapter.Builder;
      Error  : in out Errors.Error_Info);
end Flyology_Serde.Deserializers.JSON.Copied_Input;
