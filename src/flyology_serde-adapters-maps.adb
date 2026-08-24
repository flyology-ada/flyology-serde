package body Flyology_Serde.Adapters.Maps is
   use type Errors.Error_Code;

   procedure Serialize_Value
     (Item  : Source_Type;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info)
   is
      Length : Natural;
   begin
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Length := Entry_Count (Item);
      if not Keys_Use_Restricted_Kinds
        and then not Into.Capabilities.Arbitrary_Map_Keys
      then
         Errors.Fail (Error, Errors.Unsupported_Value);
         return;
      elsif Length > Maximum_Entries then
         Errors.Fail (Error, Errors.Capacity_Exceeded);
         return;
      end if;
      Into.Begin_Map (Serialization.Data_Model.Known_Length (Length), Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      if Length > 0 then
         for Position in 0 .. Length - 1 loop
            Errors.Push_Index (Error, Position);
            exit when Error.Code /= Errors.No_Error;
            Serialize_Entry (Item, Position, Into, Error);
            exit when Error.Code /= Errors.No_Error;
            Errors.Pop (Error);
         end loop;
      end if;
      if Error.Code = Errors.No_Error then
         Into.End_Map (Error);
      end if;
   end Serialize_Value;

   procedure Deserialize_Candidate
     (From   : in out Deserialization.Deserializer'Class;
      Target : in out Builder_Type;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info)
   is
      Declared  : Deserialization.Data_Model.Length_Information;
      Available : Boolean := False;
      Position  : Natural := 0;
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif not Keys_Use_Restricted_Kinds
        and then not From.Capabilities.Arbitrary_Map_Keys
      then
         Errors.Fail (Error, Errors.Unsupported_Value);
         return;
      end if;
      From.Begin_Map (Declared, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Declared.Known
        and then (Declared.Length > Maximum_Entries
                  or else Declared.Length > Policy.Limits.Maximum_Container_Items)
      then
         Errors.Fail (Error, Errors.Capacity_Exceeded);
         return;
      end if;
      Begin_Candidate (Target, Declared, Policy, Error);

      while Error.Code = Errors.No_Error loop
         From.Next_Map_Entry (Available, Error);
         exit when Error.Code /= Errors.No_Error or else not Available;
         if Position = Natural'Last
           or else Position >= Maximum_Entries
           or else Position >= Policy.Limits.Maximum_Container_Items
         then
            Errors.Push_Index (Error, Position);
            if Error.Code = Errors.No_Error then
               Errors.Fail (Error, Errors.Capacity_Exceeded);
            end if;
            exit;
         end if;
         Errors.Push_Index (Error, Position);
         exit when Error.Code /= Errors.No_Error;
         Deserialize_Entry (From, Target, Position, Policy, Error);
         exit when Error.Code /= Errors.No_Error;
         Errors.Pop (Error);
         Position := Position + 1;
      end loop;

      if Error.Code = Errors.No_Error
        and then Declared.Known
        and then Position /= Declared.Length
      then
         Errors.Fail (Error, Errors.Invalid_Value);
      elsif Error.Code = Errors.No_Error then
         From.End_Map (Error);
      end if;
      if Error.Code = Errors.No_Error then
         Finish_Candidate (Target, Error);
      end if;
   end Deserialize_Candidate;
end Flyology_Serde.Adapters.Maps;
