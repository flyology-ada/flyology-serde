package body Flyology_Serde.Adapters.Arrays is
   use type Errors.Error_Code;

   procedure Serialize_Value
     (Item  : Array_Type;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info)
   is
      Position : Natural := 0;
   begin
      if Item'Length > Natural'Last then
         Errors.Fail (Error, Errors.Unsupported_Value);
         return;
      end if;
      Into.Begin_Sequence
        (Serialization.Data_Model.Known_Length (Item'Length), Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;

      for Index in Item'Range loop
         Errors.Push_Index (Error, Position);
         if Error.Code /= Errors.No_Error then
            return;
         end if;
         Serialize_Element (Item (Index), Into, Error);
         if Error.Code /= Errors.No_Error then
            return;
         end if;
         Errors.Pop (Error);
         Position := Position + 1;
      end loop;
      Into.End_Sequence (Error);
   end Serialize_Value;

   procedure Deserialize_Candidate
     (From   : in out Deserialization.Deserializer'Class;
      Target : in out Builder_Type;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info)
   is
      Available : Boolean;
      Declared  : Deserialization.Data_Model.Length_Information;
      Position  : Natural := 0;
   begin
      From.Begin_Sequence (Declared, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Declared.Known then
         Begin_Candidate (Target, Declared.Length, Policy, Error);
      else
         Begin_Candidate (Target, 0, Policy, Error);
      end if;

      while Error.Code = Errors.No_Error loop
         From.Next_Element (Available, Error);
         exit when Error.Code /= Errors.No_Error or else not Available;
         if Position = Natural'Last then
            Errors.Fail (Error, Errors.Capacity_Exceeded);
            exit;
         end if;
         Errors.Push_Index (Error, Position);
         exit when Error.Code /= Errors.No_Error;
         Append_Element (From, Target, Position, Policy, Error);
         exit when Error.Code /= Errors.No_Error;
         Errors.Pop (Error);
         Position := Position + 1;
      end loop;

      if Error.Code = Errors.No_Error then
         if Declared.Known and then Position /= Declared.Length then
            Errors.Fail (Error, Errors.Invalid_Value);
         end if;
      end if;
      if Error.Code = Errors.No_Error then
         From.End_Sequence (Error);
      end if;
      if Error.Code = Errors.No_Error then
         Finish_Candidate (Target, Error);
      end if;
   end Deserialize_Candidate;
end Flyology_Serde.Adapters.Arrays;
