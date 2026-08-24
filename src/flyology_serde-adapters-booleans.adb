package body Flyology_Serde.Adapters.Booleans is
   use type Errors.Error_Code;

   procedure Serialize_Value
     (Item  : Boolean;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
   begin
      if Error.Code = Errors.No_Error then
         Into.Put_Boolean (Item, Error);
      end if;
   end Serialize_Value;

   procedure Deserialize_Candidate
     (From   : in out Deserialization.Deserializer'Class;
      Target : in out Boolean;
      Error  : in out Errors.Error_Info)
   is
      Candidate : Boolean;
   begin
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      From.Read_Boolean (Candidate, Error);
      if Error.Code = Errors.No_Error then
         Target := Candidate;
      end if;
   end Deserialize_Candidate;
end Flyology_Serde.Adapters.Booleans;
