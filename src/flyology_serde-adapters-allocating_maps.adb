with Ada.Containers;

package body Flyology_Serde.Adapters.Allocating_Maps is
   use type Ada.Containers.Count_Type;
   use type Errors.Error_Code;
   use type Maps.Cursor;
   use type Policies.Duplicate_Key_Action;

   procedure Serialize_Value
     (Item  : Value;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info)
   is
      Position : Natural := 0;

      procedure Serialize_One
        (Key : Key_Type; Element : Element_Type) is
      begin
         Serialize_Key (Key, Into, Error);
         if Error.Code = Errors.No_Error then
            Serialize_Element (Element, Into, Error);
         end if;
      end Serialize_One;
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif not Keys_Use_Restricted_Kinds
        and then not Into.Capabilities.Arbitrary_Map_Keys
      then
         Errors.Fail (Error, Errors.Unsupported_Value);
         return;
      elsif Ada.Containers.Count_Type'Pos (Item.Length)
        > Natural'Pos (Natural'Last)
      then
         Errors.Fail (Error, Errors.Unsupported_Value);
         return;
      end if;

      Into.Begin_Map
        (Serialization.Data_Model.Known_Length (Natural (Item.Length)), Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;

      for Cursor in Item.Iterate loop
         Errors.Push_Index (Error, Position);
         exit when Error.Code /= Errors.No_Error;
         Maps.Query_Element (Cursor, Serialize_One'Access);
         exit when Error.Code /= Errors.No_Error;
         Errors.Pop (Error);
         Position := Position + 1;
      end loop;
      if Error.Code = Errors.No_Error then
         Into.End_Map (Error);
      end if;
   end Serialize_Value;

   procedure Deserialize_Candidate
     (From   : in out Deserialization.Deserializer'Class;
      Target : in out Value;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info)
   is
      Available : Boolean;
      Declared  : Deserialization.Data_Model.Length_Information;
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
        and then Declared.Length > Policy.Limits.Maximum_Container_Items
      then
         Errors.Fail (Error, Errors.Capacity_Exceeded);
         return;
      end if;

      declare
         Candidate : Value;
      begin
         while Error.Code = Errors.No_Error loop
            From.Next_Map_Entry (Available, Error);
            exit when Error.Code /= Errors.No_Error or else not Available;
            if Position = Natural'Last
              or else Position >= Policy.Limits.Maximum_Container_Items
            then
               Errors.Push_Index (Error, Position);
               if Error.Code = Errors.No_Error then
                  Errors.Fail (Error, Errors.Capacity_Exceeded);
               end if;
               exit;
            end if;

            declare
               Key : Key_Type;
            begin
               Errors.Push_Index (Error, Position);
               exit when Error.Code /= Errors.No_Error;
               Deserialize_Key (From, Key, Policy, Error);
               exit when Error.Code /= Errors.No_Error;

               declare
                  Existing : constant Maps.Cursor := Candidate.Find (Key);
               begin
                  if Existing /= Maps.No_Element then
                     case Policy.Maps.Duplicate_Keys is
                        when Policies.Reject_Duplicate =>
                           Errors.Fail (Error, Errors.Duplicate_Key);

                        when Policies.Keep_First =>
                           From.Skip_Value (Error);

                        when Policies.Keep_Last =>
                           declare
                              Element : Element_Type;
                           begin
                              Deserialize_Element
                                (From, Element, Policy, Error);
                              if Error.Code = Errors.No_Error then
                                 Candidate.Replace_Element (Existing, Element);
                              end if;
                           end;
                     end case;
                  elsif Candidate.Length = Ada.Containers.Count_Type'Last then
                     Errors.Fail (Error, Errors.Capacity_Exceeded);
                  else
                     declare
                        Element : Element_Type;
                     begin
                        Deserialize_Element (From, Element, Policy, Error);
                        if Error.Code = Errors.No_Error then
                           Candidate.Insert (Key, Element);
                        end if;
                     end;
                  end if;
               end;

               exit when Error.Code /= Errors.No_Error;
               Errors.Pop (Error);
            end;
            Position := Position + 1;
         end loop;

         if Error.Code = Errors.No_Error
           and then Declared.Known
           and then Position /= Declared.Length
         then
            Errors.Fail (Error, Errors.Invalid_Value);
         end if;
         if Error.Code = Errors.No_Error then
            From.End_Map (Error);
         end if;
         if Error.Code = Errors.No_Error then
            Maps.Move (Target, Candidate);
         end if;
      end;
   end Deserialize_Candidate;
end Flyology_Serde.Adapters.Allocating_Maps;
