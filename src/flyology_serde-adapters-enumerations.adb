with Flyology_Serde.UTF_8;

package body Flyology_Serde.Adapters.Enumerations is
   use type Errors.Error_Code;

   subtype Literal_Index is Positive range 1 .. Maximum_Literals;
   subtype Alias_Count_Value is Natural range 0 .. Maximum_Aliases_Per_Literal;

   type Literal_Table is array (Literal_Index) of Value_Type;
   type Alias_Count_Table is array (Literal_Index) of Alias_Count_Value;

   function Declared_Name
     (Literals : Literal_Table;
      Index    : Literal_Index;
      Position : Natural) return String is
     (if Position = 0
      then Primary_Name (Literals (Index))
      else Alias_Name (Literals (Index), Position));

   procedure Prepare_Metadata
     (Literals : out Literal_Table;
      Aliases  : out Alias_Count_Table;
      Count    : out Natural;
      Error    : in out Errors.Error_Info)
   is
      Match_Count : Natural;
      Matched     : Literal_Index := Literal_Index'First;
   begin
      Literals := [others => Value_Type'First];
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

      for Value in Value_Type loop
         if Count = Maximum_Literals then
            Errors.Fail (Error, Errors.Capacity_Exceeded);
            return;
         end if;
         Count := Count + 1;
         Literals (Count) := Value;
      end loop;

      for Index in Literal_Index'First .. Count loop
         declare
            Actual_Count : constant Natural := Alias_Count (Literals (Index));
         begin
            if Actual_Count > Maximum_Aliases_Per_Literal then
               Errors.Fail (Error, Errors.Capacity_Exceeded);
               return;
            end if;
            Aliases (Index) := Actual_Count;
         end;
      end loop;

      for Index in Literal_Index'First .. Count loop
         for Position in 0 .. Aliases (Index) loop
            declare
               Name : constant String :=
                 Declared_Name (Literals, Index, Position);
            begin
               if Name'Length = 0
                 or else Name'Length > Maximum_Literal_Name_Length
               then
                  Errors.Fail (Error, Errors.Capacity_Exceeded);
                  return;
               elsif not Flyology_Serde.UTF_8.Is_Valid (Name) then
                  Errors.Fail (Error, Errors.Invalid_Text);
                  return;
               end if;

               Match_Count := 0;
               for Candidate in Literal_Index'First .. Count loop
                  if Matches_Literal (Literals (Candidate), Name) then
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
                               (Literals, Other, Other_Position);
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
     (Item  : Value_Type;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info)
   is
      Literals : Literal_Table;
      Aliases  : Alias_Count_Table;
      Count    : Natural;
   begin
      Prepare_Metadata (Literals, Aliases, Count, Error);
      if Error.Code = Errors.No_Error then
         Into.Put_Enumeration (Type_Name, Primary_Name (Item), Error);
      end if;
   end Serialize_Value;

   procedure Deserialize_Candidate
     (From   : in out Deserialization.Deserializer'Class;
      Target : in out Value_Type;
      Error  : in out Errors.Error_Info)
   is
      Literals    : Literal_Table;
      Aliases     : Alias_Count_Table;
      Count       : Natural;
      Name_Buffer : String (1 .. Maximum_Literal_Name_Length);
      Name_Length : Natural;
      Match_Count : Natural := 0;
      Matched     : Literal_Index := Literal_Index'First;
   begin
      Prepare_Metadata (Literals, Aliases, Count, Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;

      From.Read_Enumeration
        (Type_Name, Name_Buffer, Name_Length, Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;

      if Name_Length = 0 then
         for Index in Literal_Index'First .. Count loop
            if Matches_Literal (Literals (Index), "") then
               Match_Count := Match_Count + 1;
               Matched := Index;
            end if;
         end loop;
      else
         declare
            Name : constant String :=
              Name_Buffer
                (Name_Buffer'First
                 .. Name_Buffer'First + Name_Length - 1);
         begin
            for Index in Literal_Index'First .. Count loop
               if Matches_Literal (Literals (Index), Name) then
                  Match_Count := Match_Count + 1;
                  Matched := Index;
               end if;
            end loop;
         end;
      end if;

      if Match_Count = 0 then
         Errors.Fail (Error, Errors.Invalid_Value);
      elsif Match_Count > 1 then
         Errors.Fail (Error, Errors.Application_Error);
      else
         Target := Literals (Matched);
      end if;
   end Deserialize_Candidate;
end Flyology_Serde.Adapters.Enumerations;
