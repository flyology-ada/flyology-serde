package body Flyology_Serde_Generator.Lowered_Records.Test_Fixtures is
   procedure Populate (Value : out Model) is
   begin
      Value.Valid := True;
      Set_Text (Value.Unit_Name, "Flyology.Generated");
      Value.With_Count := 1;
      Set_Text (Value.With_Units (1), "Wire_Shape");
      Set_Text (Value.Ada_Type, "Wire_Shape.Public_Record");
      Set_Text (Value.Logical_Name, "wire_shape.public_record");
      Value.Fields_Count := 3;
      Set_Text (Value.Fields (1).Ada_Component, "Enabled");
      Set_Text (Value.Fields (1).Ada_Type, "Boolean");
      Set_Text (Value.Fields (1).Presentation_Name, "enabled");
      Value.Fields (1).Kind := Boolean_Scalar;
      Set_Text (Value.Fields (2).Ada_Component, "Signed");
      Set_Text (Value.Fields (2).Ada_Type, "Wire_Shape.Signed_16");
      Set_Text (Value.Fields (2).Presentation_Name, "signed");
      Value.Fields (2).Kind := Signed_64_Scalar;
      Set_Text (Value.Fields (3).Ada_Component, "Unsigned");
      Set_Text (Value.Fields (3).Ada_Type, "Wire_Shape.Unsigned_16");
      Set_Text (Value.Fields (3).Presentation_Name, "unsigned");
      Value.Fields (3).Kind := Unsigned_64_Scalar;
      Value.Serialization_Limits :=
        (Maximum_Nesting_Depth   => 8,
         Maximum_Container_Items => 16,
         Maximum_Text_Length     => 64,
         Maximum_Byte_Length     => 64,
         Maximum_Logical_Events  => 64);
   end Populate;

   function Wire_Record return Model is
   begin
      return Result : Model do
         Populate (Result);
      end return;
   end Wire_Record;

   function Malformed (Kind : Malformation) return Model is
   begin
      return Result : Model do
         Populate (Result);
         case Kind is
            when Invalid_Output_Unit =>
               Set_Text (Result.Unit_Name, "Bad__Unit");
            when Duplicate_With_Unit =>
               Result.With_Count := 2;
               Set_Text (Result.With_Units (2), "wire_shape");
            when Duplicate_Presentation_Name =>
               Set_Text (Result.Fields (2).Presentation_Name, "enabled");
            when Duplicate_Ada_Component =>
               Set_Text (Result.Fields (2).Ada_Component, "enabled");
            when Invalid_Field_Ada_Type =>
               Set_Text (Result.Fields (2).Ada_Type, "Bad__Type");
            when Invalid_Logical_Name =>
               Set_Text (Result.Logical_Name, "");
            when Overlong_Presentation_Name =>
               Set_Text
                 (Result.Fields (1).Presentation_Name,
                  "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx");
            when Invalid_Runtime_Limits =>
               Result.Serialization_Limits.Maximum_Nesting_Depth := 257;
            when No_Fields =>
               Result.Fields_Count := 0;
            when Too_Many_Fields =>
               Result.Fields_Count := 4;
               Set_Text (Result.Fields (4).Ada_Component, "Extra");
               Set_Text (Result.Fields (4).Ada_Type, "Boolean");
               Set_Text (Result.Fields (4).Presentation_Name, "extra");
               Result.Fields (4).Kind := Boolean_Scalar;
         end case;
      end return;
   end Malformed;

   function Boundary (Kind : Line_Boundary; Exceeds : Boolean) return Model is
      procedure Set_Repeated
        (Target : out Bounded_Text;
         Item   : Character;
         Count  : Positive)
      is
         Text : constant String (1 .. Count) := [others => Item];
      begin
         Set_Text (Target, Text);
      end Set_Repeated;
   begin
      return Result : Model do
         Populate (Result);
         case Kind is
            when Signed_Component_Line =>
               Set_Repeated (Result.Fields (2).Ada_Component, 'S', (if Exceeds then 22 else 21));
            when Presentation_Line =>
               Set_Repeated (Result.Fields (1).Presentation_Name, 'p', (if Exceeds then 57 else 56));
         end case;
      end return;
   end Boundary;
end Flyology_Serde_Generator.Lowered_Records.Test_Fixtures;
