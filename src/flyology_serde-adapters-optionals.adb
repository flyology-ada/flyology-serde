package body Flyology_Serde.Adapters.Optionals is
   use type Errors.Error_Code;

   procedure Serialize_Value
     (Item  : Source_Type;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info)
   is
      Present : constant Boolean := Is_Present (Item);
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif not Serialization.Capabilities (Into).Lossless_Optionals then
         Errors.Fail (Error, Errors.Unsupported_Value);
         return;
      end if;

      Into.Begin_Optional (Present, Error);
      if Present and then Error.Code = Errors.No_Error then
         Serialize_Present (Item, Into, Error);
      end if;
      if Error.Code = Errors.No_Error then
         Into.End_Optional (Error);
      end if;
   end Serialize_Value;

   procedure Deserialize_Candidate
     (From   : in out Deserialization.Deserializer'Class;
      Target : in out Builder_Type;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info)
   is
      Present : Boolean;
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif not Deserialization.Capabilities (From).Lossless_Optionals then
         Errors.Fail (Error, Errors.Unsupported_Value);
         return;
      end if;

      From.Begin_Optional (Present, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Present then
         Deserialize_Present (From, Target, Policy, Error);
      else
         Set_Absent (Target, Error);
      end if;
      if Error.Code = Errors.No_Error then
         From.End_Optional (Error);
      end if;
   end Deserialize_Candidate;
end Flyology_Serde.Adapters.Optionals;
