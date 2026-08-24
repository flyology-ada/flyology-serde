package body Flyology_Serde_Generator.Lowered_Records is
   function Text (Value : Bounded_Text) return String is
     (if Value.Length = 0 then "" else Value.Data (1 .. Value.Length));

   procedure Set_Text (Target : out Bounded_Text; Value : String) is
   begin
      Target := (Length => 0, Data => [others => ASCII.NUL]);
      if Value'Length > Text_Capacity then
         raise Constraint_Error with "lowered-record text exceeds its intrinsic capacity";
      end if;
      Target.Length := Value'Length;
      if Value'Length > 0 then
         Target.Data (1 .. Value'Length) := Value;
      end if;
   end Set_Text;

   function Is_Valid (Value : Model) return Boolean is (Value.Valid);

   function Output_Unit (Value : Model) return String is (Text (Value.Unit_Name));

   function With_Unit_Count (Value : Model) return Natural is (Value.With_Count);

   function With_Unit (Value : Model; Index : Positive) return String is
     (Text (Value.With_Units (Index)));

   function Record_Ada_Type (Value : Model) return String is (Text (Value.Ada_Type));

   function Logical_Type_Name (Value : Model) return String is (Text (Value.Logical_Name));

   function Field_Count (Value : Model) return Natural is (Value.Fields_Count);

   function Field_Ada_Component (Value : Model; Index : Positive) return String is
     (Text (Value.Fields (Index).Ada_Component));

   function Field_Ada_Type (Value : Model; Index : Positive) return String is
     (Text (Value.Fields (Index).Ada_Type));

   function Field_Presentation_Name (Value : Model; Index : Positive) return String is
     (Text (Value.Fields (Index).Presentation_Name));

   function Field_Scalar_Kind (Value : Model; Index : Positive) return Scalar_Kind is
     (Value.Fields (Index).Kind);

   function Runtime_Limits (Value : Model) return Runtime_Limit_Set is
     (Value.Serialization_Limits);
end Flyology_Serde_Generator.Lowered_Records;
