with Flyology_Serde.Fixed_Array_Test_Hooks;

package body Flyology_Serde.Adapters.Fixed_Arrays is
   use type Errors.Error_Code;

   package Test_Hooks renames Flyology_Serde.Fixed_Array_Test_Hooks;

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

   procedure Deserialize_Candidate
     (From   : in out Deserialization.Deserializer'Class;
      Target : in out Array_Type;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info)
   is
      Declared : Deserialization.Data_Model.Length_Information;
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif Target'Length > Natural'Last then
         Errors.Fail (Error, Errors.Unsupported_Value);
         return;
      elsif Target'Length > Policy.Limits.Maximum_Container_Items then
         Errors.Fail (Error, Errors.Capacity_Exceeded);
         return;
      end if;

      From.Begin_Sequence (Declared, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Declared.Known and then Declared.Length /= Target'Length then
         Errors.Fail (Error, Errors.Out_Of_Range);
         return;
      end if;

      if Test_Hooks.Enabled then
         Test_Hooks.Before_Candidate;
      end if;

      declare
         Candidate : Array_Type := Target;
         Available : Boolean := False;
         Position  : Natural := 0;
      begin
         for Index in Candidate'Range loop
            From.Next_Element (Available, Error);
            exit when Error.Code /= Errors.No_Error;
            if not Available then
               Errors.Push_Index (Error, Position);
               if Error.Code = Errors.No_Error then
                  Errors.Fail (Error, Errors.Out_Of_Range);
               end if;
               exit;
            end if;
            Errors.Push_Index (Error, Position);
            exit when Error.Code /= Errors.No_Error;
            Deserialize_Element (From, Candidate (Index), Policy, Error);
            exit when Error.Code /= Errors.No_Error;
            Errors.Pop (Error);
            Position := Position + 1;
         end loop;

         if Error.Code = Errors.No_Error then
            From.Next_Element (Available, Error);
         end if;
         if Error.Code = Errors.No_Error and then Available then
            Errors.Push_Index (Error, Position);
            if Error.Code = Errors.No_Error then
               Errors.Fail (Error, Errors.Out_Of_Range);
            end if;
         elsif Error.Code = Errors.No_Error then
            From.End_Sequence (Error);
         end if;
         if Error.Code = Errors.No_Error then
            Target := Candidate;
         end if;
      end;
   end Deserialize_Candidate;
end Flyology_Serde.Adapters.Fixed_Arrays;
