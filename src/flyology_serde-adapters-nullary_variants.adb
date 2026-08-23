with Flyology_Serde.UTF_8;

package body Flyology_Serde.Adapters.Nullary_Variants is
   use type Errors.Error_Code;
   use type Policies.Unknown_Field_Action;

   subtype Alternative_Index is Positive range 1 .. Maximum_Alternatives;
   subtype Alias_Count_Value is
     Natural range 0 .. Maximum_Aliases_Per_Alternative;
   type Alternative_Table is
     array (Alternative_Index) of Alternative_Ordinal;
   type Alias_Table is array (Alternative_Index) of Alias_Count_Value;

   function Declared_Name
     (Alternatives : Alternative_Table;
      Index        : Alternative_Index;
      Position     : Natural) return String is
     (if Position = 0
      then Alternative_Name (Alternatives (Index))
      else Alternative_Alias_Name (Alternatives (Index), Position));

   procedure Prepare_Metadata
     (Alternatives : out Alternative_Table;
      Aliases      : out Alias_Table;
      Count        : out Natural;
      Error        : in out Errors.Error_Info)
   is
      Match_Count : Natural;
      Matched     : Alternative_Index := Alternative_Index'First;
   begin
      Alternatives := [others => Alternative_Ordinal'First];
      Aliases := [others => 0];
      Count := 0;
      if Error.Code /= Errors.No_Error then
         return;
      elsif Type_Name'Length = 0
        or else Type_Name'Length > Maximum_Type_Name_Length
      then
         Errors.Fail (Error, Errors.Capacity_Exceeded);
         return;
      elsif not Flyology_Serde.UTF_8.Is_Valid (Type_Name) then
         Errors.Fail (Error, Errors.Invalid_Text);
         return;
      end if;
      for Alternative in Alternative_Ordinal loop
         if Count = Maximum_Alternatives then
            Errors.Fail (Error, Errors.Capacity_Exceeded);
            return;
         end if;
         Count := Count + 1;
         Alternatives (Count) := Alternative;
      end loop;
      for Index in Alternative_Index'First .. Count loop
         declare
            Actual : constant Natural :=
              Alternative_Alias_Count (Alternatives (Index));
         begin
            if Actual > Maximum_Aliases_Per_Alternative then
               Errors.Fail (Error, Errors.Capacity_Exceeded);
               return;
            end if;
            Aliases (Index) := Actual;
         end;
      end loop;
      for Index in Alternative_Index'First .. Count loop
         for Position in 0 .. Aliases (Index) loop
            declare
               Name : constant String :=
                 Declared_Name (Alternatives, Index, Position);
            begin
               if Name'Length = 0
                 or else Name'Length > Maximum_Alternative_Name_Length
               then
                  Errors.Fail (Error, Errors.Capacity_Exceeded);
                  return;
               elsif not Flyology_Serde.UTF_8.Is_Valid (Name) then
                  Errors.Fail (Error, Errors.Invalid_Text);
                  return;
               end if;
               Match_Count := 0;
               for Candidate in Alternative_Index'First .. Count loop
                  if Matches_Alternative (Alternatives (Candidate), Name) then
                     Match_Count := Match_Count + 1;
                     Matched := Candidate;
                  end if;
               end loop;
               if Match_Count /= 1 or else Matched /= Index then
                  Errors.Fail (Error, Errors.Application_Error);
                  return;
               end if;
               for Other in Index .. Count loop
                  for Other_Position in 0 .. Aliases (Other) loop
                     if Other > Index or else Other_Position > Position then
                        if Name =
                          Declared_Name
                            (Alternatives, Other, Other_Position)
                        then
                           Errors.Fail (Error, Errors.Application_Error);
                           return;
                        end if;
                     end if;
                  end loop;
               end loop;
            end;
         end loop;
      end loop;
   end Prepare_Metadata;

   procedure Serialize_Value
     (Item  : Source_Type;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info)
   is
      Alternatives : Alternative_Table;
      Aliases      : Alias_Table;
      Count        : Natural;
      Selected     : Alternative_Ordinal := Alternative_Ordinal'First;
   begin
      Prepare_Metadata (Alternatives, Aliases, Count, Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Selected := Select_Alternative (Item);
      declare
         Name : constant String := Alternative_Name (Selected);
      begin
         Errors.Push_Alternative (Error, Name);
         if Error.Code = Errors.No_Error then
            Into.Begin_Variant (Type_Name, Name, 0, Error);
         end if;
      end;
      if Error.Code = Errors.No_Error then
         Into.End_Variant (Error);
      end if;
      if Error.Code = Errors.No_Error then
         Errors.Pop (Error);
      end if;
   end Serialize_Value;

   procedure Deserialize_Candidate
     (From   : in out Deserialization.Deserializer'Class;
      Target : in out Builder_Type;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info)
   is
      Alternatives      : Alternative_Table;
      Aliases           : Alias_Table;
      Count             : Natural;
      Alternative_Buffer : String (1 .. Maximum_Alternative_Name_Length);
      Alternative_Length : Natural;
      Field_Buffer      : String (1 .. Maximum_Incoming_Field_Name_Length);
      Field_Length      : Natural;
      Declared          : Deserialization.Data_Model.Length_Information;
      Available         : Boolean;
      Match_Count       : Natural := 0;
      Matched           : Alternative_Index := Alternative_Index'First;
      Selected          : Alternative_Ordinal := Alternative_Ordinal'First;

      procedure Traverse (Incoming : String) is
      begin
         Selected := Alternatives (Matched);
         Errors.Push_Alternative (Error, Incoming);
         if Error.Code = Errors.No_Error then
            Begin_Alternative (Target, Selected, Policy, Error);
         end if;
         while Error.Code = Errors.No_Error loop
            From.Next_Field
              (Field_Buffer, Field_Length, Available, Error);
            exit when Error.Code /= Errors.No_Error or else not Available;
            if Field_Length = 0 then
               Errors.Push_Field (Error, "");
            else
               Errors.Push_Field
                 (Error,
                  Field_Buffer
                    (Field_Buffer'First
                     .. Field_Buffer'First + Field_Length - 1));
            end if;
            exit when Error.Code /= Errors.No_Error;
            if Policy.Records.Unknown_Fields = Policies.Reject_Unknown then
               Errors.Fail (Error, Errors.Unknown_Field);
            else
               From.Skip_Value (Error);
            end if;
            if Error.Code = Errors.No_Error then
               Errors.Pop (Error);
            end if;
         end loop;
         if Error.Code = Errors.No_Error then
            From.End_Variant (Error);
         end if;
         if Error.Code = Errors.No_Error then
            Finish_Candidate (Target, Selected, Error);
         end if;
         if Error.Code = Errors.No_Error then
            Errors.Pop (Error);
         end if;
      end Traverse;
   begin
      Prepare_Metadata (Alternatives, Aliases, Count, Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      From.Begin_Variant
        (Type_Name,
         Alternative_Buffer,
         Alternative_Length,
         Declared,
         Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      if Alternative_Length = 0 then
         for Index in Alternative_Index'First .. Count loop
            if Matches_Alternative (Alternatives (Index), "") then
               Match_Count := Match_Count + 1;
               Matched := Index;
            end if;
         end loop;
      else
         declare
            Name : constant String :=
              Alternative_Buffer
                (Alternative_Buffer'First
                 .. Alternative_Buffer'First + Alternative_Length - 1);
         begin
            for Index in Alternative_Index'First .. Count loop
               if Matches_Alternative (Alternatives (Index), Name) then
                  Match_Count := Match_Count + 1;
                  Matched := Index;
               end if;
            end loop;
         end;
      end if;
      if Alternative_Length = 0 then
         Errors.Push_Alternative (Error, "");
      else
         Errors.Push_Alternative
           (Error,
            Alternative_Buffer
              (Alternative_Buffer'First
               .. Alternative_Buffer'First + Alternative_Length - 1));
      end if;
      if Error.Code /= Errors.No_Error then
         return;
      elsif Match_Count = 0 then
         Errors.Fail (Error, Errors.Invalid_Value);
      elsif Match_Count > 1 then
         Errors.Fail (Error, Errors.Application_Error);
      else
         Errors.Pop (Error);
         if Alternative_Length = 0 then
            Traverse ("");
         else
            Traverse
              (Alternative_Buffer
                 (Alternative_Buffer'First
                  .. Alternative_Buffer'First + Alternative_Length - 1));
         end if;
      end if;
   end Deserialize_Candidate;
end Flyology_Serde.Adapters.Nullary_Variants;
