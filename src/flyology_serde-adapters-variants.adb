with Flyology_Serde.UTF_8;

package body Flyology_Serde.Adapters.Variants is
   use type Errors.Error_Code;
   use type Policies.Duplicate_Field_Action;
   use type Policies.Unknown_Field_Action;

   subtype Alternative_Index is Positive range 1 .. Maximum_Alternatives;
   subtype Field_Index is Positive range 1 .. Maximum_Total_Fields;
   subtype Alternative_Alias_Count_Value is
     Natural range 0 .. Maximum_Aliases_Per_Alternative;
   subtype Field_Alias_Count_Value is
     Natural range 0 .. Maximum_Aliases_Per_Field;

   type Alternative_Table is
     array (Alternative_Index) of Alternative_Ordinal;
   type Field_Table is array (Field_Index) of Field_Ordinal;
   type Alternative_Alias_Table is
     array (Alternative_Index) of Alternative_Alias_Count_Value;
   type Field_Alias_Table is
     array (Field_Index) of Field_Alias_Count_Value;
   type Field_Flag_Table is array (Field_Index) of Boolean;

   function Declared_Alternative_Name
     (Alternatives : Alternative_Table;
      Index        : Alternative_Index;
      Position     : Natural) return String is
     (if Position = 0
      then Alternative_Name (Alternatives (Index))
      else Alternative_Alias_Name (Alternatives (Index), Position));

   function Declared_Field_Name
     (Fields   : Field_Table;
      Index    : Field_Index;
      Position : Natural) return String is
     (if Position = 0
      then Field_Name (Fields (Index))
      else Field_Alias_Name (Fields (Index), Position));

   procedure Prepare_Metadata
     (Alternatives     : out Alternative_Table;
      Alternative_Aliases : out Alternative_Alias_Table;
      Alternative_Count   : out Natural;
      Fields           : out Field_Table;
      Field_Aliases    : out Field_Alias_Table;
      Field_Count      : out Natural;
      Error            : in out Errors.Error_Info)
   is
      Used        : Field_Flag_Table := [others => False];
      Match_Count : Natural;
      Matched_Alt : Alternative_Index := Alternative_Index'First;
      Matched     : Field_Index := Field_Index'First;
      Members     : Natural;
   begin
      Alternatives := [others => Alternative_Ordinal'First];
      Alternative_Aliases := [others => 0];
      Alternative_Count := 0;
      Fields := [others => Field_Ordinal'First];
      Field_Aliases := [others => 0];
      Field_Count := 0;
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
         if Alternative_Count = Maximum_Alternatives then
            Errors.Fail (Error, Errors.Capacity_Exceeded);
            return;
         end if;
         Alternative_Count := Alternative_Count + 1;
         Alternatives (Alternative_Count) := Alternative;
      end loop;
      for Field in Field_Ordinal loop
         if Field_Count = Maximum_Total_Fields then
            Errors.Fail (Error, Errors.Capacity_Exceeded);
            return;
         end if;
         Field_Count := Field_Count + 1;
         Fields (Field_Count) := Field;
      end loop;

      for Index in Alternative_Index'First .. Alternative_Count loop
         declare
            Count : constant Natural :=
              Alternative_Alias_Count (Alternatives (Index));
         begin
            if Count > Maximum_Aliases_Per_Alternative then
               Errors.Fail (Error, Errors.Capacity_Exceeded);
               return;
            end if;
            Alternative_Aliases (Index) := Count;
         end;
      end loop;
      for Index in Field_Index'First .. Field_Count loop
         declare
            Count : constant Natural :=
              Field_Alias_Count (Fields (Index));
         begin
            if Count > Maximum_Aliases_Per_Field then
               Errors.Fail (Error, Errors.Capacity_Exceeded);
               return;
            end if;
            Field_Aliases (Index) := Count;
         end;
      end loop;

      for Index in Alternative_Index'First .. Alternative_Count loop
         for Position in 0 .. Alternative_Aliases (Index) loop
            declare
               Name : constant String :=
                 Declared_Alternative_Name
                   (Alternatives, Index, Position);
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
               for Candidate in
                 Alternative_Index'First .. Alternative_Count
               loop
                  if Matches_Alternative
                       (Alternatives (Candidate), Name)
                  then
                     Match_Count := Match_Count + 1;
                     Matched_Alt := Candidate;
                  end if;
               end loop;
               if Match_Count /= 1 or else Matched_Alt /= Index then
                  Errors.Fail (Error, Errors.Application_Error);
                  return;
               end if;
               for Other in Index .. Alternative_Count loop
                  for Other_Position in
                    0 .. Alternative_Aliases (Other)
                  loop
                     if Other > Index or else Other_Position > Position then
                        if Name =
                          Declared_Alternative_Name
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

      for Index in Field_Index'First .. Field_Count loop
         for Position in 0 .. Field_Aliases (Index) loop
            declare
               Name : constant String :=
                 Declared_Field_Name (Fields, Index, Position);
            begin
               if Name'Length = 0
                 or else Name'Length > Maximum_Field_Name_Length
               then
                  Errors.Fail (Error, Errors.Capacity_Exceeded);
                  return;
               elsif not Flyology_Serde.UTF_8.Is_Valid (Name) then
                  Errors.Fail (Error, Errors.Invalid_Text);
                  return;
               end if;
            end;
         end loop;
      end loop;

      for Alternative in Alternative_Index'First .. Alternative_Count loop
         Members := 0;
         for Index in Field_Index'First .. Field_Count loop
            if Field_Belongs_To
                 (Alternatives (Alternative), Fields (Index))
            then
               if Members = Maximum_Fields_Per_Alternative then
                  Errors.Fail (Error, Errors.Capacity_Exceeded);
                  return;
               end if;
               Members := Members + 1;
               Used (Index) := True;

               for Position in 0 .. Field_Aliases (Index) loop
                  declare
                     Name : constant String :=
                       Declared_Field_Name (Fields, Index, Position);
                  begin
                     Match_Count := 0;
                     for Candidate in
                       Field_Index'First .. Field_Count
                     loop
                        if Field_Belongs_To
                             (Alternatives (Alternative), Fields (Candidate))
                          and then Matches_Field (Fields (Candidate), Name)
                        then
                           Match_Count := Match_Count + 1;
                           Matched := Candidate;
                        end if;
                     end loop;
                     if Match_Count /= 1 or else Matched /= Index then
                        Errors.Fail (Error, Errors.Application_Error);
                        return;
                     end if;

                     for Other in Index .. Field_Count loop
                        if Field_Belongs_To
                             (Alternatives (Alternative), Fields (Other))
                        then
                           for Other_Position in
                             0 .. Field_Aliases (Other)
                           loop
                              if Other > Index
                                or else Other_Position > Position
                              then
                                 if Name =
                                   Declared_Field_Name
                                     (Fields, Other, Other_Position)
                                 then
                                    Errors.Fail
                                      (Error, Errors.Application_Error);
                                    return;
                                 end if;
                              end if;
                           end loop;
                        end if;
                     end loop;
                  end;
               end loop;
            end if;
         end loop;
      end loop;

      for Index in Field_Index'First .. Field_Count loop
         if not Used (Index) then
            Errors.Fail (Error, Errors.Application_Error);
            return;
         end if;
      end loop;
   end Prepare_Metadata;

   function Member_Count
     (Alternative : Alternative_Ordinal;
      Fields      : Field_Table;
      Count       : Natural) return Natural
   is
      Result : Natural := 0;
   begin
      for Index in Field_Index'First .. Count loop
         if Field_Belongs_To (Alternative, Fields (Index)) then
            Result := Result + 1;
         end if;
      end loop;
      return Result;
   end Member_Count;

   procedure Serialize_Value
     (Item  : Source_Type;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info)
   is
      Alternatives       : Alternative_Table;
      Alternative_Aliases : Alternative_Alias_Table;
      Alternative_Count   : Natural;
      Fields              : Field_Table;
      Field_Aliases       : Field_Alias_Table;
      Field_Count         : Natural;
      Alternative         : Alternative_Ordinal := Alternative_Ordinal'First;
   begin
      Prepare_Metadata
        (Alternatives,
         Alternative_Aliases,
         Alternative_Count,
         Fields,
         Field_Aliases,
         Field_Count,
         Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Alternative := Select_Alternative (Item);
      declare
         Name : constant String := Alternative_Name (Alternative);
      begin
         Errors.Push_Alternative (Error, Name);
         if Error.Code = Errors.No_Error then
            Into.Begin_Variant
              (Type_Name,
               Name,
               Member_Count (Alternative, Fields, Field_Count),
               Error);
         end if;
      end;

      for Index in Field_Index'First .. Field_Count loop
         exit when Error.Code /= Errors.No_Error;
         if Field_Belongs_To (Alternative, Fields (Index)) then
            declare
               Name : constant String := Field_Name (Fields (Index));
            begin
               Errors.Push_Field (Error, Name);
               if Error.Code = Errors.No_Error then
                  Into.Put_Field (Name, Error);
               end if;
               if Error.Code = Errors.No_Error then
                  Serialize_Field
                    (Item,
                     Alternative,
                     Fields (Index),
                     Into,
                     Error);
               end if;
               if Error.Code = Errors.No_Error then
                  Errors.Pop (Error);
               end if;
            end;
         end if;
      end loop;
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
      Alternatives        : Alternative_Table;
      Alternative_Aliases : Alternative_Alias_Table;
      Alternative_Count   : Natural;
      Fields               : Field_Table;
      Field_Aliases        : Field_Alias_Table;
      Field_Count          : Natural;
      Seen                 : Field_Flag_Table := [others => False];
      Alternative_Buffer   : String (1 .. Maximum_Alternative_Name_Length);
      Alternative_Length   : Natural;
      Field_Buffer         : String (1 .. Maximum_Field_Name_Length);
      Field_Length         : Natural;
      Declared             : Deserialization.Data_Model.Length_Information;
      Available            : Boolean;
      Match_Count          : Natural := 0;
      Matched_Alternative  : Alternative_Index := Alternative_Index'First;
      Selected             : Alternative_Ordinal := Alternative_Ordinal'First;

      procedure Consume_Field (Incoming : String) is
         Field_Matches : Natural := 0;
         Matched_Field : Field_Index := Field_Index'First;
      begin
         for Index in Field_Index'First .. Field_Count loop
            if Field_Belongs_To (Selected, Fields (Index))
              and then Matches_Field (Fields (Index), Incoming)
            then
               Field_Matches := Field_Matches + 1;
               Matched_Field := Index;
            end if;
         end loop;
         Errors.Push_Field (Error, Incoming);
         if Error.Code /= Errors.No_Error then
            return;
         elsif Field_Matches > 1 then
            Errors.Fail (Error, Errors.Application_Error);
         elsif Field_Matches = 0 then
            if Policy.Records.Unknown_Fields = Policies.Reject_Unknown then
               Errors.Fail (Error, Errors.Unknown_Field);
            else
               From.Skip_Value (Error);
            end if;
         elsif Seen (Matched_Field) then
            case Policy.Records.Duplicate_Fields is
               when Policies.Reject_Duplicate =>
                  Errors.Fail (Error, Errors.Duplicate_Field);
               when Policies.Keep_First       =>
                  From.Skip_Value (Error);
               when Policies.Keep_Last        =>
                  Deserialize_Field
                    (From,
                     Target,
                     Selected,
                     Fields (Matched_Field),
                     True,
                     Policy,
                     Error);
            end case;
         else
            Deserialize_Field
              (From,
               Target,
               Selected,
               Fields (Matched_Field),
               False,
               Policy,
               Error);
            if Error.Code = Errors.No_Error then
               Seen (Matched_Field) := True;
            end if;
         end if;
         if Error.Code = Errors.No_Error then
            Errors.Pop (Error);
         end if;
      end Consume_Field;

      procedure Traverse_Selected (Incoming_Alternative : String) is
      begin
         Selected := Alternatives (Matched_Alternative);
         Errors.Push_Alternative (Error, Incoming_Alternative);
         if Error.Code = Errors.No_Error then
            Begin_Alternative (Target, Selected, Policy, Error);
         end if;

         while Error.Code = Errors.No_Error loop
            From.Next_Field
              (Field_Buffer, Field_Length, Available, Error);
            exit when Error.Code /= Errors.No_Error or else not Available;
            if Field_Length = 0 then
               Consume_Field ("");
            else
               Consume_Field
                 (Field_Buffer
                    (Field_Buffer'First
                     .. Field_Buffer'First + Field_Length - 1));
            end if;
         end loop;
         if Error.Code = Errors.No_Error then
            From.End_Variant (Error);
         end if;

         for Index in Field_Index'First .. Field_Count loop
            exit when Error.Code /= Errors.No_Error;
            if Field_Belongs_To (Selected, Fields (Index))
              and then not Seen (Index)
            then
               declare
                  Name    : constant String := Field_Name (Fields (Index));
                  Applied : Boolean := False;
               begin
                  Errors.Push_Field (Error, Name);
                  if Error.Code = Errors.No_Error then
                     Apply_Missing
                       (Target,
                        Selected,
                        Fields (Index),
                        Policy,
                        Applied,
                        Error);
                  end if;
                  if Error.Code = Errors.No_Error and then not Applied then
                     Errors.Fail (Error, Errors.Missing_Field);
                  end if;
                  if Error.Code = Errors.No_Error then
                     Seen (Index) := True;
                     Errors.Pop (Error);
                  end if;
               end;
            end if;
         end loop;
         if Error.Code = Errors.No_Error then
            Finish_Candidate (Target, Selected, Error);
         end if;
         if Error.Code = Errors.No_Error then
            Errors.Pop (Error);
         end if;
      end Traverse_Selected;
   begin
      Prepare_Metadata
        (Alternatives,
         Alternative_Aliases,
         Alternative_Count,
         Fields,
         Field_Aliases,
         Field_Count,
         Error);
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
         for Index in Alternative_Index'First .. Alternative_Count loop
            if Matches_Alternative (Alternatives (Index), "") then
               Match_Count := Match_Count + 1;
               Matched_Alternative := Index;
            end if;
         end loop;
      else
         declare
            Name : constant String :=
              Alternative_Buffer
                (Alternative_Buffer'First
                 .. Alternative_Buffer'First + Alternative_Length - 1);
         begin
            for Index in Alternative_Index'First .. Alternative_Count loop
               if Matches_Alternative (Alternatives (Index), Name) then
                  Match_Count := Match_Count + 1;
                  Matched_Alternative := Index;
               end if;
            end loop;
         end;
      end if;

      if Match_Count = 0 then
         if Alternative_Length = 0 then
            Errors.Push_Alternative (Error, "");
         else
            Errors.Push_Alternative
              (Error,
               Alternative_Buffer
                 (Alternative_Buffer'First
                  .. Alternative_Buffer'First + Alternative_Length - 1));
         end if;
         if Error.Code = Errors.No_Error then
            Errors.Fail (Error, Errors.Invalid_Value);
         end if;
      elsif Match_Count > 1 then
         if Alternative_Length = 0 then
            Errors.Push_Alternative (Error, "");
         else
            Errors.Push_Alternative
              (Error,
               Alternative_Buffer
                 (Alternative_Buffer'First
                  .. Alternative_Buffer'First + Alternative_Length - 1));
         end if;
         if Error.Code = Errors.No_Error then
            Errors.Fail (Error, Errors.Application_Error);
         end if;
      elsif Alternative_Length = 0 then
         Traverse_Selected ("");
      else
         Traverse_Selected
           (Alternative_Buffer
              (Alternative_Buffer'First
               .. Alternative_Buffer'First + Alternative_Length - 1));
      end if;
   end Deserialize_Candidate;
end Flyology_Serde.Adapters.Variants;
