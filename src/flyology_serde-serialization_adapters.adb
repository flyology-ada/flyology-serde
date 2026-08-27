with Flyology_Serde.Serializers.Counting;

package body Flyology_Serde.Serialization_Adapters is
   use type Errors.Error_Code;
   use type Serialization.Serializer_State;

   procedure Serialize
     (Item  : Source;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info)
   is
      Validator : Serializers.Counting.Counter;
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif Into.State = Serialization.Active then
         Errors.Fail (Error, Errors.Invalid_State);
         Into.Abort_Document;
         return;
      elsif Into.State /= Serialization.Ready then
         Errors.Fail (Error, Errors.Invalid_State);
         return;
      end if;

      Serializers.Counting.Reset (Validator, Into.Capabilities, Limits);
      Serialize_Value (Item, Validator, Error);
      Validator.Finish_Document (Error);
      if Error.Code /= Errors.No_Error then
         Validator.Abort_Document;
         Into.Abort_Document;
         return;
      end if;

      Serialize_Value (Item, Into, Error);
      if Error.Code = Errors.No_Error then
         Into.Finish_Document (Error);
      end if;
      if Error.Code /= Errors.No_Error then
         Into.Abort_Document;
      end if;
   exception
      when others =>
         Validator.Abort_Document;
         Into.Abort_Document;
         Errors.Clear_Path (Error);
         raise;
   end Serialize;
end Flyology_Serde.Serialization_Adapters;
