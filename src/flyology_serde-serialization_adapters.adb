package body Flyology_Serde.Serialization_Adapters is
   use type Errors.Error_Code;

   procedure Serialize
     (Item  : Source;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
   begin
      if Error.Code = Errors.No_Error then
         Serialize_Value (Item, Into, Error);
      end if;
   end Serialize;
end Flyology_Serde.Serialization_Adapters;
