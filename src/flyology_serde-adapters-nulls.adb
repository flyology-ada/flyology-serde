package body Flyology_Serde.Adapters.Nulls is
   use type Errors.Error_Code;

   procedure Serialize_Value
     (Item  : Source_Type;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info)
   is
      pragma Unreferenced (Item);
   begin
      if Error.Code = Errors.No_Error then
         Into.Put_Null (Error);
      end if;
   end Serialize_Value;

   procedure Deserialize_Candidate
     (From   : in out Deserialization.Deserializer'Class;
      Target : in out Builder_Type;
      Error  : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      From.Read_Null (Error);
      if Error.Code = Errors.No_Error then
         Construct_Null (Target, Error);
      end if;
   end Deserialize_Candidate;
end Flyology_Serde.Adapters.Nulls;
