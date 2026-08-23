package body Flyology_Serde.Serialization_Adapters is
   procedure Serialize
     (Item  : Source;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
   begin
      Serialize_Value (Item, Into, Error);
   end Serialize;
end Flyology_Serde.Serialization_Adapters;
