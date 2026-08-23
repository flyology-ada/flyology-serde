with Flyology_Serde.UTF_8;

package body Flyology_Serde.Adapters.Records is
   use type Errors.Error_Code;
   use type Policies.Duplicate_Field_Action;
   use type Policies.Unknown_Field_Action;

   subtype Field_Index is Positive range 1 .. Maximum_Fields;
   subtype Alias_Count_Value is Natural range 0 .. Maximum_Aliases_Per_Field;

   type Field_Table is array (Field_Index) of Field_Ordinal;
   type Alias_Count_Table is array (Field_Index) of Alias_Count_Value;
   type Seen_Table is array (Field_Index) of Boolean;

   function Declared_Name
     (Fields   : Field_Table;
      Index    : Field_Index;
      Position : Natural) return String is
     (if Position = 0
      then Primary_Name (Fields (Index))
      else Alias_Name (Fields (Index), Position));

   procedure Prepare_Metadata
     (Fields  : out Field_Table;
      Aliases : out Alias_Count_Table;
      Count   : out Natural;
      Error   : in out Errors.Error_Info)
   is
      Match_Count : Natural;
      Matched     : Field_Index := Field_Index'First;
   begin
      Fields := [others => Field_Ordinal'First];
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

      for Field in Field_Ordinal loop
         if Count = Maximum_Fields then
            Errors.Fail (Error, Errors.Capacity_Exceeded);
            return;
         end if;
         Count := Count + 1;
         Fields (Count) := Field;
      end loop;

      for Index in Field_Index'First .. Count loop
         declare
            Actual_Count : constant Natural := Alias_Count (Fields (Index));
         begin
            if Actual_Count > Maximum_Aliases_Per_Field then
               Errors.Fail (Error, Errors.Capacity_Exceeded);
               return;
            end if;
            Aliases (Index) := Actual_Count;
         end;
      end loop;

      for Index in Field_Index'First .. Count loop
         for Position in 0 .. Aliases (Index) loop
            declare
               Name : constant String :=
                 Declared_Name (Fields, Index, Position);
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

               Match_Count := 0;
               for Candidate in Field_Index'First .. Count loop
                  if Matches_Field (Fields (Candidate), Name) then
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
                        declare
                           Other_Name : constant String :=
                             Declared_Name
                               (Fields, Other, Other_Position);
                        begin
                           if Name = Other_Name then
                              Errors.Fail
                                (Error, Errors.Application_Error);
                              return;
                           end if;
                        end;
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
      Fields  : Field_Table;
      Aliases : Alias_Count_Table;
      Count   : Natural;
   begin
      Prepare_Metadata (Fields, Aliases, Count, Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Into.Begin_Record (Type_Name, Count, Error);

      for Index in Field_Index'First .. Count loop
         exit when Error.Code /= Errors.No_Error;
         declare
            Name : constant String := Primary_Name (Fields (Index));
         begin
            Errors.Push_Field (Error, Name);
            if Error.Code = Errors.No_Error then
               Into.Put_Field (Name, Error);
            end if;
            if Error.Code = Errors.No_Error then
               Serialize_Field (Item, Fields (Index), Into, Error);
            end if;
            if Error.Code = Errors.No_Error then
               Errors.Pop (Error);
            end if;
         end;
      end loop;

      if Error.Code = Errors.No_Error then
         Into.End_Record (Error);
      end if;
   end Serialize_Value;

   procedure Deserialize_Candidate
     (From   : in out Deserialization.Deserializer'Class;
      Target : in out Builder_Type;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info)
   is
      Fields      : Field_Table;
      Aliases     : Alias_Count_Table;
      Seen        : Seen_Table := [others => False];
      Count       : Natural;
      Declared    : Deserialization.Data_Model.Length_Information;
      Name_Buffer : String (1 .. Maximum_Field_Name_Length);
      Name_Length : Natural;
      Available   : Boolean;

      procedure Consume_Field (Incoming : String) is
         Match_Count : Natural := 0;
         Matched     : Field_Index := Field_Index'First;
      begin
         for Index in Field_Index'First .. Count loop
            if Matches_Field (Fields (Index), Incoming) then
               Match_Count := Match_Count + 1;
               Matched := Index;
            end if;
         end loop;

         Errors.Push_Field (Error, Incoming);
         if Error.Code /= Errors.No_Error then
            return;
         elsif Match_Count > 1 then
            Errors.Fail (Error, Errors.Application_Error);
            return;
         elsif Match_Count = 0 then
            if Policy.Records.Unknown_Fields = Policies.Reject_Unknown then
               Errors.Fail (Error, Errors.Unknown_Field);
            else
               From.Skip_Value (Error);
            end if;
         elsif Seen (Matched) then
            case Policy.Records.Duplicate_Fields is
               when Policies.Reject_Duplicate =>
                  Errors.Fail (Error, Errors.Duplicate_Field);
               when Policies.Keep_First       =>
                  From.Skip_Value (Error);
               when Policies.Keep_Last        =>
                  Deserialize_Field
                    (From,
                     Target,
                     Fields (Matched),
                     True,
                     Policy,
                     Error);
            end case;
         else
            Deserialize_Field
              (From,
               Target,
               Fields (Matched),
               False,
               Policy,
               Error);
            if Error.Code = Errors.No_Error then
               Seen (Matched) := True;
            end if;
         end if;

         if Error.Code = Errors.No_Error then
            Errors.Pop (Error);
         end if;
      end Consume_Field;
   begin
      Prepare_Metadata (Fields, Aliases, Count, Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      From.Begin_Record (Type_Name, Declared, Error);

      while Error.Code = Errors.No_Error loop
         From.Next_Field
           (Name_Buffer, Name_Length, Available, Error);
         exit when Error.Code /= Errors.No_Error or else not Available;
         if Name_Length = 0 then
            Consume_Field ("");
         else
            Consume_Field
              (Name_Buffer
                 (Name_Buffer'First
                  .. Name_Buffer'First + Name_Length - 1));
         end if;
      end loop;

      if Error.Code = Errors.No_Error then
         From.End_Record (Error);
      end if;

      for Index in Field_Index'First .. Count loop
         exit when Error.Code /= Errors.No_Error;
         if not Seen (Index) then
            declare
               Name    : constant String := Primary_Name (Fields (Index));
               Applied : Boolean := False;
            begin
               Errors.Push_Field (Error, Name);
               if Error.Code = Errors.No_Error then
                  Apply_Missing
                    (Target, Fields (Index), Policy, Applied, Error);
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
         Finish_Candidate (Target, Error);
      end if;
   end Deserialize_Candidate;
end Flyology_Serde.Adapters.Records;
