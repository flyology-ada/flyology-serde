with Ada.Containers;

package body Flyology_Serde.Adapters.Allocating_Sequences is
   use type Errors.Error_Code;

   procedure Serialize_Value
     (Item  : Value;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info)
   is
      Position : Natural := 0;
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif Ada.Containers.Count_Type'Pos (Item.Length)
        > Natural'Pos (Natural'Last)
      then
         Errors.Fail (Error, Errors.Unsupported_Value);
         return;
      end if;

      Into.Begin_Sequence
        (Serialization.Data_Model.Known_Length (Natural (Item.Length)), Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;

      for Element of Item loop
         Errors.Push_Index (Error, Position);
         exit when Error.Code /= Errors.No_Error;
         Serialize_Element (Element, Into, Error);
         exit when Error.Code /= Errors.No_Error;
         Errors.Pop (Error);
         Position := Position + 1;
      end loop;
      if Error.Code = Errors.No_Error then
         Into.End_Sequence (Error);
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
      end if;

      From.Begin_Sequence (Declared, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Declared.Known
        and then
          (Declared.Length > Policy.Limits.Maximum_Container_Items
           or else Natural'Pos (Declared.Length)
             > Ada.Containers.Count_Type'Pos (Ada.Containers.Count_Type'Last))
      then
         Errors.Fail (Error, Errors.Capacity_Exceeded);
         return;
      end if;

      declare
         Candidate : Value;
      begin
         if Declared.Known then
            begin
               Candidate.Reserve_Capacity
                 (Ada.Containers.Count_Type (Declared.Length));
            exception
               when Ada.Containers.Capacity_Error =>
                  Errors.Fail (Error, Errors.Capacity_Exceeded);
            end;
         end if;

         while Error.Code = Errors.No_Error loop
            From.Next_Element (Available, Error);
            exit when Error.Code /= Errors.No_Error or else not Available;
            if Position = Natural'Last
              or else Position >= Policy.Limits.Maximum_Container_Items
              or else Natural'Pos (Position)
                >= Ada.Containers.Count_Type'Pos
                     (Ada.Containers.Count_Type'Last)
            then
               Errors.Push_Index (Error, Position);
               if Error.Code = Errors.No_Error then
                  Errors.Fail (Error, Errors.Capacity_Exceeded);
               end if;
               exit;
            end if;

            declare
               Element : Element_Type;
            begin
               Errors.Push_Index (Error, Position);
               exit when Error.Code /= Errors.No_Error;
               Deserialize_Element (From, Element, Policy, Error);
               exit when Error.Code /= Errors.No_Error;
               begin
                  Candidate.Append (Element);
               exception
                  when Ada.Containers.Capacity_Error =>
                     Errors.Fail (Error, Errors.Capacity_Exceeded);
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
            From.End_Sequence (Error);
         end if;
         if Error.Code = Errors.No_Error then
            Vectors.Move (Target, Candidate);
         end if;
      end;
   end Deserialize_Candidate;
end Flyology_Serde.Adapters.Allocating_Sequences;
