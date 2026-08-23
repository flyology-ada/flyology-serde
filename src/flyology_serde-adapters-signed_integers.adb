with Interfaces;

package body Flyology_Serde.Adapters.Signed_Integers is
   use type Errors.Error_Code;

   procedure Serialize_Value
     (Item  : Value_Type;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif Value_Type'Pos (Item)
        < Interfaces.Integer_64'Pos (Interfaces.Integer_64'First)
        or else Value_Type'Pos (Item)
                > Interfaces.Integer_64'Pos (Interfaces.Integer_64'Last)
      then
         Errors.Fail (Error, Errors.Unsupported_Value);
      else
         Into.Put_Signed
           (Interfaces.Integer_64'Val (Value_Type'Pos (Item)), Error);
      end if;
   end Serialize_Value;

   procedure Deserialize_Candidate
     (From   : in out Deserialization.Deserializer'Class;
      Target : in out Value_Type;
      Error  : in out Errors.Error_Info)
   is
      Value : Interfaces.Integer_64;
   begin
      From.Read_Signed (Value, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Interfaces.Integer_64'Pos (Value)
        < Value_Type'Pos (Value_Type'First)
        or else Interfaces.Integer_64'Pos (Value)
                > Value_Type'Pos (Value_Type'Last)
      then
         Errors.Fail (Error, Errors.Out_Of_Range);
      else
         Target := Value_Type'Val (Interfaces.Integer_64'Pos (Value));
      end if;
   end Deserialize_Candidate;
end Flyology_Serde.Adapters.Signed_Integers;
