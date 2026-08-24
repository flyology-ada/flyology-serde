package body Flyology_Serde.Adapters.Float_64_Values is
   use type Data_Model.Float_64_Category;
   use type Errors.Error_Code;

   procedure Serialize_Value
     (Item  : Data_Model.Float_64_Value;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info)
   is
   begin
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      declare
         Profile : constant Data_Model.Format_Capabilities := Into.Capabilities;
      begin
         if Data_Model.Category (Item) /= Data_Model.Finite_Float
           and then not Profile.Nonfinite_Float_64
         then
            Errors.Fail (Error, Errors.Unsupported_Value);
         elsif Data_Model.Is_Negative_Zero (Item)
           and then not Profile.Signed_Float_Zero
         then
            Errors.Fail (Error, Errors.Unsupported_Value);
         else
            Into.Put_Float_64 (Item, Error);
         end if;
      end;
   end Serialize_Value;

   procedure Deserialize_Candidate
     (From   : in out Deserialization.Deserializer'Class;
      Target : in out Data_Model.Float_64_Value;
      Error  : in out Errors.Error_Info)
   is
      Candidate : Data_Model.Float_64_Value;
   begin
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      From.Read_Float_64 (Candidate, Error);
      if Error.Code = Errors.No_Error then
         Target := Candidate;
      end if;
   end Deserialize_Candidate;
end Flyology_Serde.Adapters.Float_64_Values;
