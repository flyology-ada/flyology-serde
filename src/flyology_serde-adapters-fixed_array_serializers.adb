package body Flyology_Serde.Adapters.Fixed_Array_Serializers is
   use type Errors.Error_Code;

   procedure Serialize_Value
     (Item  : Array_Type;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info)
   is
      Position : Natural := 0;
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif Item'Length > Natural'Last then
         Errors.Fail (Error, Errors.Unsupported_Value);
         return;
      end if;

      Into.Begin_Sequence
        (Serialization.Data_Model.Known_Length (Item'Length), Error);
      for Index in Item'Range loop
         exit when Error.Code /= Errors.No_Error;
         Errors.Push_Index (Error, Position);
         exit when Error.Code /= Errors.No_Error;
         Serialize_Element (Item (Index), Into, Error);
         exit when Error.Code /= Errors.No_Error;
         Errors.Pop (Error);
         Position := Position + 1;
      end loop;
      if Error.Code = Errors.No_Error then
         Into.End_Sequence (Error);
      end if;
   end Serialize_Value;
end Flyology_Serde.Adapters.Fixed_Array_Serializers;
