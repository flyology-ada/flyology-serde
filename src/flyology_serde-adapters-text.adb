with Flyology_Serde.UTF_8;

package body Flyology_Serde.Adapters.Text is
   use type Errors.Error_Code;

   procedure Serialize_Value
     (Item  : String;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif not UTF_8.Is_Valid (Item) then
         Errors.Fail (Error, Errors.Invalid_Text);
      else
         Into.Put_Text (Item, Error);
      end if;
   end Serialize_Value;

   procedure Deserialize_Candidate
     (From   : in out Deserialization.Deserializer'Class;
      Target : out String;
      Length : out Natural;
      Error  : in out Errors.Error_Info) is
   begin
      From.Read_Text (Target, Length, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Length > Target'Length then
         Errors.Fail (Error, Errors.Invalid_State);
      elsif Length > 0
        and then not UTF_8.Is_Valid
                       (Target (Target'First .. Target'First + Length - 1))
      then
         Errors.Fail (Error, Errors.Invalid_Text);
      end if;
   end Deserialize_Candidate;
end Flyology_Serde.Adapters.Text;
