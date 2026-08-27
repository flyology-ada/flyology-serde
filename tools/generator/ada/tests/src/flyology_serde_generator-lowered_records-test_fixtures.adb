with Ada.Unchecked_Deallocation;
with Flyology_Serde_Generator.Graph_Work;
with Flyology_Serde_Generator.Rendering;

package body Flyology_Serde_Generator.Lowered_Records.Test_Fixtures is
   use Flyology_Serde_Generator.Diagnostics;
   use Flyology_Serde_Generator.Overlays;
   use Flyology_Serde_Generator.Requests;

   Unpublished_Graphs : Natural := 0;

   function Live_Unpublished_Graphs return Natural
   is (Unpublished_Graphs);

   Expected_Type_IR_Commit   : constant String :=
     "78e6726a80d02b22f573fed3f65538cafd89fc0d";
   Expected_Type_IR_Semantic : constant String :=
     "e5f5da08e77e057960fe9ab987b3400e5557a017ae62fcdaa8d4e376042d7f76";
   Expected_Type_IR_Source   : constant String :=
     "92aa85c19c3d0dcfd531f42b75743559efd4f80919942a9acce5f5e15d323c4a";
   Expected_Output_Unit      : constant String := "Flyology.Generated";
   Expected_With_Unit        : constant String := "Wire_Shape";
   Expected_Record_ID        : constant String :=
     "decl:wire_shape.public_record#public";
   Expected_Record_Type      : constant String := "Wire_Shape.Public_Record";

   function Expected_Component_ID (Index : Positive) return String
   is (case Index is
         when 1      => "decl:wire_shape.public_record.enabled#public",
         when 2      => "decl:wire_shape.public_record.signed#public",
         when 3      => "decl:wire_shape.public_record.unsigned#public",
         when others => "");

   function Expected_Ada_Component (Index : Positive) return String
   is (case Index is
         when 1      => "Enabled",
         when 2      => "Signed",
         when 3      => "Unsigned",
         when others => "");

   function Expected_Ada_Type (Index : Positive) return String
   is (case Index is
         when 1      => "Boolean",
         when 2      => "Wire_Shape.Signed_16",
         when 3      => "Wire_Shape.Unsigned_16",
         when others => "");

   type Text_Selector is
     (Output_Unit_Text,
      Type_IR_Commit_Text,
      Type_IR_Semantic_Text,
      Type_IR_Source_Text,
      With_Unit_Text,
      Record_Ada_Type_Text,
      Record_ID_Text,
      Record_Logical_Name_Text,
      Field_Ada_Component_Text,
      Field_Ada_Type_Text,
      Field_Component_ID_Text,
      Field_Presentation_Name_Text);

   type Text_Array is array (Positive range <>) of Bounded_Text;

   type Scratch_Data is record
      Unit_Name            : Bounded_Text;
      With_Unit            : Bounded_Text;
      Ada_Type             : Bounded_Text;
      Record_ID            : Bounded_Text;
      Logical_Name         : Bounded_Text;
      Type_IR_Commit       : Bounded_Text;
      Type_IR_Semantic     : Bounded_Text;
      Type_IR_Source       : Bounded_Text;
      Fields               : Field_Array;
      Component_IDs        : Text_Array (1 .. 3);
      Serialization_Limits : Runtime_Limit_Set := (others => 0);
   end record;

   function Text_Equals (Left : Bounded_Text; Right : String) return Boolean
   is (Left.Length = Right'Length
       and then (Left.Length = 0
                 or else Left.Data (1 .. Left.Length) = Right));

   procedure Read_Text
     (Overlay    : Overlay_Document;
      Selector   : Text_Selector;
      Index      : Positive;
      Budget     : in out Operation_Budget;
      Into       : in out Bounded_Text;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
      Length  : Natural := 0;
      Written : Natural := 0;
      Copied  : Boolean := False;
   begin
      if Code (Diagnostic) /= No_Error then
         return;
      end if;

      case Selector is
         when Output_Unit_Text             =>
            Read_Output_Unit_Length (Overlay, Budget, Length, Diagnostic);

         when Type_IR_Commit_Text          =>
            Read_Type_IR_Commit_Length (Overlay, Budget, Length, Diagnostic);

         when Type_IR_Semantic_Text        =>
            Read_Type_IR_Semantic_Fingerprint_Length
              (Overlay, Budget, Length, Diagnostic);

         when Type_IR_Source_Text          =>
            Read_Type_IR_Source_SHA256_Length
              (Overlay, Budget, Length, Diagnostic);

         when With_Unit_Text               =>
            Read_With_Unit_Length (Overlay, Index, Budget, Length, Diagnostic);

         when Record_Ada_Type_Text         =>
            Read_Record_Ada_Type_Length (Overlay, Budget, Length, Diagnostic);

         when Record_ID_Text               =>
            Read_Record_Declaration_ID_Length
              (Overlay, Budget, Length, Diagnostic);

         when Record_Logical_Name_Text     =>
            Read_Record_Logical_Type_Name_Length
              (Overlay, Budget, Length, Diagnostic);

         when Field_Ada_Component_Text     =>
            Read_Field_Ada_Component_Length
              (Overlay, Index, Budget, Length, Diagnostic);

         when Field_Ada_Type_Text          =>
            Read_Field_Ada_Type_Length
              (Overlay, Index, Budget, Length, Diagnostic);

         when Field_Component_ID_Text      =>
            Read_Field_Component_ID_Length
              (Overlay, Index, Budget, Length, Diagnostic);

         when Field_Presentation_Name_Text =>
            Read_Field_Presentation_Name_Length
              (Overlay, Index, Budget, Length, Diagnostic);
      end case;

      if Code (Diagnostic) /= No_Error then
         return;
      elsif Length > Text_Capacity then
         Set (Diagnostic, Unsupported_Lowered_Model);
         return;
      end if;

      case Selector is
         when Output_Unit_Text             =>
            Copy_Output_Unit
              (Overlay, Budget, Into.Data, Written, Copied, Diagnostic);

         when Type_IR_Commit_Text          =>
            Copy_Type_IR_Commit
              (Overlay, Budget, Into.Data, Written, Copied, Diagnostic);

         when Type_IR_Semantic_Text        =>
            Copy_Type_IR_Semantic_Fingerprint
              (Overlay, Budget, Into.Data, Written, Copied, Diagnostic);

         when Type_IR_Source_Text          =>
            Copy_Type_IR_Source_SHA256
              (Overlay, Budget, Into.Data, Written, Copied, Diagnostic);

         when With_Unit_Text               =>
            Copy_With_Unit
              (Overlay, Index, Budget, Into.Data, Written, Copied, Diagnostic);

         when Record_Ada_Type_Text         =>
            Copy_Record_Ada_Type
              (Overlay, Budget, Into.Data, Written, Copied, Diagnostic);

         when Record_ID_Text               =>
            Copy_Record_Declaration_ID
              (Overlay, Budget, Into.Data, Written, Copied, Diagnostic);

         when Record_Logical_Name_Text     =>
            Copy_Record_Logical_Type_Name
              (Overlay, Budget, Into.Data, Written, Copied, Diagnostic);

         when Field_Ada_Component_Text     =>
            Copy_Field_Ada_Component
              (Overlay, Index, Budget, Into.Data, Written, Copied, Diagnostic);

         when Field_Ada_Type_Text          =>
            Copy_Field_Ada_Type
              (Overlay, Index, Budget, Into.Data, Written, Copied, Diagnostic);

         when Field_Component_ID_Text      =>
            Copy_Field_Component_ID
              (Overlay, Index, Budget, Into.Data, Written, Copied, Diagnostic);

         when Field_Presentation_Name_Text =>
            Copy_Field_Presentation_Name
              (Overlay, Index, Budget, Into.Data, Written, Copied, Diagnostic);
      end case;

      if Code (Diagnostic) = No_Error then
         if not Copied or else Written /= Length then
            Set (Diagnostic, Internal_Error);
         else
            Into.Length := Length;
         end if;
      end if;
   end Read_Text;

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

   function Lower_Wire_Record
     (Overlay    : Overlay_Document;
      Budget     : in out Operation_Budget;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
      return Model
   is
      Scratch     : Scratch_Data;
      Fixture     : Boolean := False;
      With_Count  : Natural := 0;
      Field_Count : Natural := 0;
      Limits      : Serialization_Limits := (others => 0);
      Accepted    : Boolean;
   begin
      return Result : Model do
         begin
            if Code (Diagnostic) = No_Error then
               Read_Fixture_Only (Overlay, Budget, Fixture, Diagnostic);
               Read_Runtime_Limits (Overlay, Budget, Limits, Diagnostic);
               Read_With_Unit_Count (Overlay, Budget, With_Count, Diagnostic);
               Read_Field_Count (Overlay, Budget, Field_Count, Diagnostic);
               Read_Text
                 (Overlay,
                  Output_Unit_Text,
                  1,
                  Budget,
                  Scratch.Unit_Name,
                  Diagnostic);
               Read_Text
                 (Overlay,
                  Type_IR_Commit_Text,
                  1,
                  Budget,
                  Scratch.Type_IR_Commit,
                  Diagnostic);
               Read_Text
                 (Overlay,
                  Type_IR_Semantic_Text,
                  1,
                  Budget,
                  Scratch.Type_IR_Semantic,
                  Diagnostic);
               Read_Text
                 (Overlay,
                  Type_IR_Source_Text,
                  1,
                  Budget,
                  Scratch.Type_IR_Source,
                  Diagnostic);

               if Code (Diagnostic) = No_Error and then With_Count = 1 then
                  Read_Text
                    (Overlay,
                     With_Unit_Text,
                     1,
                     Budget,
                     Scratch.With_Unit,
                     Diagnostic);
               elsif Code (Diagnostic) = No_Error then
                  Set (Diagnostic, Unsupported_Lowered_Model);
               end if;

               Read_Text
                 (Overlay,
                  Record_Ada_Type_Text,
                  1,
                  Budget,
                  Scratch.Ada_Type,
                  Diagnostic);
               Read_Text
                 (Overlay,
                  Record_ID_Text,
                  1,
                  Budget,
                  Scratch.Record_ID,
                  Diagnostic);
               Read_Text
                 (Overlay,
                  Record_Logical_Name_Text,
                  1,
                  Budget,
                  Scratch.Logical_Name,
                  Diagnostic);

               if Code (Diagnostic) = No_Error and then Field_Count = 3 then
                  for Index in 1 .. 3 loop
                     Read_Text
                       (Overlay,
                        Field_Ada_Component_Text,
                        Index,
                        Budget,
                        Scratch.Fields (Index).Ada_Component,
                        Diagnostic);
                     Read_Text
                       (Overlay,
                        Field_Ada_Type_Text,
                        Index,
                        Budget,
                        Scratch.Fields (Index).Ada_Type,
                        Diagnostic);
                     Read_Text
                       (Overlay,
                        Field_Component_ID_Text,
                        Index,
                        Budget,
                        Scratch.Component_IDs (Index),
                        Diagnostic);
                     Read_Text
                       (Overlay,
                        Field_Presentation_Name_Text,
                        Index,
                        Budget,
                        Scratch.Fields (Index).Presentation_Name,
                        Diagnostic);
                  end loop;
               elsif Code (Diagnostic) = No_Error then
                  Set (Diagnostic, Unsupported_Lowered_Model);
               end if;

               if Code (Diagnostic) = No_Error
                 and then (not Fixture
                           or else not Text_Equals
                                         (Scratch.Type_IR_Commit,
                                          Expected_Type_IR_Commit)
                           or else not Text_Equals
                                         (Scratch.Type_IR_Semantic,
                                          Expected_Type_IR_Semantic)
                           or else not Text_Equals
                                         (Scratch.Type_IR_Source,
                                          Expected_Type_IR_Source)
                           or else not Text_Equals
                                         (Scratch.Unit_Name,
                                          Expected_Output_Unit)
                           or else not Text_Equals
                                         (Scratch.With_Unit,
                                          Expected_With_Unit)
                           or else not Text_Equals
                                         (Scratch.Record_ID,
                                          Expected_Record_ID)
                           or else not Text_Equals
                                         (Scratch.Ada_Type,
                                          Expected_Record_Type))
               then
                  Set (Diagnostic, Unsupported_Lowered_Model);
               end if;

               if Code (Diagnostic) = No_Error then
                  for Index in 1 .. 3 loop
                     if not Text_Equals
                              (Scratch.Fields (Index).Ada_Component,
                               Expected_Ada_Component (Index))
                       or else not Text_Equals
                                     (Scratch.Fields (Index).Ada_Type,
                                      Expected_Ada_Type (Index))
                       or else not Text_Equals
                                     (Scratch.Component_IDs (Index),
                                      Expected_Component_ID (Index))
                     then
                        Set (Diagnostic, Unsupported_Lowered_Model);
                        exit;
                     end if;
                  end loop;
               end if;

               if Code (Diagnostic) = No_Error then
                  for Index in 0 .. 3 loop
                     Charge_Work (Budget, 1, Accepted);
                     if not Accepted then
                        Set (Diagnostic, Resource_Exhausted);
                        exit;
                     end if;
                  end loop;
               end if;

               if Code (Diagnostic) = No_Error then
                  Scratch.Fields (1).Kind := Boolean_Scalar;
                  Scratch.Fields (2).Kind := Signed_64_Scalar;
                  Scratch.Fields (3).Kind := Unsigned_64_Scalar;
                  Scratch.Serialization_Limits :=
                    (Maximum_Nesting_Depth   => Limits.Maximum_Nesting_Depth,
                     Maximum_Container_Items => Limits.Maximum_Container_Items,
                     Maximum_Text_Length     => Limits.Maximum_Text_Length,
                     Maximum_Byte_Length     => Limits.Maximum_Byte_Length,
                     Maximum_Logical_Events  => Limits.Maximum_Logical_Events);

                  Result.Unit_Name := Scratch.Unit_Name;
                  Result.With_Count := 1;
                  Result.With_Units (1) := Scratch.With_Unit;
                  Result.Ada_Type := Scratch.Ada_Type;
                  Result.Logical_Name := Scratch.Logical_Name;
                  Result.Fields_Count := 3;
                  Result.Fields := Scratch.Fields;
                  Result.Serialization_Limits := Scratch.Serialization_Limits;
                  Result.Valid := True;
               end if;
            end if;
         exception
            when Storage_Error =>
               Poison (Budget);
               if Code (Diagnostic) = No_Error then
                  Set (Diagnostic, Resource_Exhausted);
               end if;
            when others =>
               Poison (Budget);
               if Code (Diagnostic) = No_Error then
                  Set (Diagnostic, Internal_Error);
               end if;
         end;
      end return;
   end Lower_Wire_Record;

   function Malformed (Kind : Malformation) return Model is
   begin
      return Result : Model do
         Populate (Result);
         case Kind is
            when Invalid_Output_Unit         =>
               Set_Text (Result.Unit_Name, "Bad__Unit");

            when Duplicate_With_Unit         =>
               Result.With_Count := 2;
               Set_Text (Result.With_Units (2), "wire_shape");

            when Duplicate_Presentation_Name =>
               Set_Text (Result.Fields (2).Presentation_Name, "enabled");

            when Duplicate_Ada_Component     =>
               Set_Text (Result.Fields (2).Ada_Component, "enabled");

            when Invalid_Field_Ada_Type      =>
               Set_Text (Result.Fields (2).Ada_Type, "Bad__Type");

            when Invalid_Logical_Name        =>
               Set_Text (Result.Logical_Name, "");

            when Overlong_Presentation_Name  =>
               Set_Text
                 (Result.Fields (1).Presentation_Name,
                  "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx");

            when Invalid_Runtime_Limits      =>
               Result.Serialization_Limits.Maximum_Nesting_Depth := 257;

            when No_Fields                   =>
               Result.Fields_Count := 0;

            when Too_Many_Fields             =>
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
        (Target : out Bounded_Text; Item : Character; Count : Positive)
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
               Set_Repeated
                 (Result.Fields (2).Ada_Component,
                  'S',
                  (if Exceeds then 22 else 21));

            when Presentation_Line     =>
               Set_Repeated
                 (Result.Fields (1).Presentation_Name,
                  'p',
                  (if Exceeds then 57 else 56));
         end case;
      end return;
   end Boundary;

   function Production_Shape_Work (Kind : Graph_Malformation) return Natural is
      Members       : constant Natural :=
        (if Kind in Redirected_Defining_With | Unused_With_Unit
         then 17
         else 16);
      Base_Text     : constant := 237;
      Text          : constant Natural :=
        Base_Text
        + (case Kind is
             when Redirected_Defining_With | Unused_With_Unit => 10,
             when Ignored_Array_Logical_Name                  => 1,
             when Overlong_Generated_Line                     => 55,
             when others                                      => 0);
      Work          : Natural := 0;
      Representable : Boolean := False;
   begin
      Flyology_Serde_Generator.Graph_Work.Compute
        (Members, Text, Work, Representable);
      pragma Assert (Representable);
      return Work;
   end Production_Shape_Work;

   procedure Compute_Graph_Work
     (Members       : Natural;
      Text_Bytes    : Natural;
      Work          : out Natural;
      Representable : out Boolean) is
   begin
      Flyology_Serde_Generator.Graph_Work.Compute
        (Members, Text_Bytes, Work, Representable);
   end Compute_Graph_Work;

   function Production_Shapes
     (Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic;
      Kind       : Graph_Malformation := Valid_Graph;
      Failure    : Graph_Failure := No_Failure) return Model
   is
      Type_Count         : constant := 4;
      Field_Count        : constant := 2;
      Literal_Count      : constant := 6;
      Alias_Count        : constant := 3;
      With_Count         : constant Natural :=
        (if Kind in Redirected_Defining_With | Unused_With_Unit then 2 else 1);
      Structural_Count   : constant Natural :=
        Type_Count + Field_Count + Literal_Count + With_Count;
      Overlay_Count      : constant := 2 + 1 + 3 + Alias_Count + Field_Count;
      Member_Count       : constant Natural :=
        Type_Count + Field_Count + Literal_Count + Alias_Count + With_Count;
      Maximum_Text_Bytes : constant := 26;

      Candidate : Graph_Data_Access := null;

      procedure Free_Graph is new
        Ada.Unchecked_Deallocation
          (Object => Graph_Data,
           Name   => Graph_Data_Access);

      procedure Discard_Candidate is
      begin
         if Candidate /= null then
            pragma Assert (Unpublished_Graphs > 0);
            Unpublished_Graphs := Unpublished_Graphs - 1;
            Free_Graph (Candidate);
         end if;
      end Discard_Candidate;

      function Retained_Text_Bytes return Natural is
         Total : Natural := 0;

         procedure Add (Value : String) is
         begin
            Total := Total + Value'Length;
         end Add;
      begin
         Add ("Production_Shapes_Serde");
         Add ("Production_Shapes");
         if Kind in Redirected_Defining_With | Unused_With_Unit then
            Add ("Other_Unit");
         end if;
         Add ("Production_Shapes.Position");
         Add ("Production_Shapes.Color");
         Add ("production.color");
         Add ("Production_Shapes.Palette");
         Add ("Production_Shapes.Packet");
         Add ("production.packet");
         Add ("First");
         Add ("Middle");
         Add ("Last");
         Add ("Red");
         Add ("red");
         Add ("Green");
         Add ("green");
         Add ("Blue");
         Add ("blue");
         Add ("r");
         Add ("g");
         Add ("b");
         Add ("Shade");
         Add ("shade");
         Add ("Samples");
         Add ("samples");
         return Total;
      end Retained_Text_Bytes;

      Text_Bytes : constant Natural :=
        Retained_Text_Bytes
        + (case Kind is
             when Ignored_Array_Logical_Name => 1,
             when Overlong_Generated_Line    => 55,
             when others                     => 0);
      Work       : Natural;
      Accepted   : Boolean := False;
      Limits     : constant Generation_Limits := Budget_Limits (Budget);
   begin
      return Result : Model do
         if Code (Diagnostic) /= No_Error then
            return;
         elsif Is_Poisoned (Budget) then
            Set (Diagnostic, Resource_Exhausted);
            return;
         elsif Limit_Value (Structural_Count) > Limits.Maximum_Type_IR_Nodes
           or else Limit_Value (Overlay_Count) > Limits.Maximum_Overlay_Nodes
           or else Limit_Value (Text_Bytes)
                   > Limits.Maximum_Decoded_String_Bytes
           or else Limit_Value (Maximum_Text_Bytes)
                   > Limits.Maximum_Decoded_String_Bytes
         then
            Set (Diagnostic, Unsupported_Lowered_Model);
            return;
         end if;

         Compute_Graph_Work (Member_Count, Text_Bytes, Work, Accepted);
         if not Accepted then
            Set (Diagnostic, Unsupported_Lowered_Model);
            return;
         end if;
         Charge_Work (Budget, Work, Accepted);
         if not Accepted then
            Set (Diagnostic, Resource_Exhausted);
            return;
         end if;

         begin
            begin
               if Failure = Allocation_Storage_Failure then
                  raise Storage_Error;
               end if;
               Candidate :=
                 new Graph_Data
                       (Types_Count => Type_Count,
                        Fields_Count => Field_Count,
                        Literals_Count => Literal_Count,
                        Aliases_Count => Alias_Count,
                        With_Count => With_Count);
               Unpublished_Graphs := Unpublished_Graphs + 1;
            exception
               when Storage_Error =>
                  Poison (Budget);
                  Set (Diagnostic, Resource_Exhausted);
            end;

            if Candidate = null then
               return;
            end if;

            case Failure is
               when No_Failure | Allocation_Storage_Failure =>
                  null;

               when Post_Allocation_Storage_Failure         =>
                  raise Storage_Error;

               when Post_Allocation_Internal_Failure        =>
                  raise Program_Error;

               when Post_Transfer_Internal_Failure          =>
                  null;
            end case;

            Set_Text (Candidate.Unit_Name, "Production_Shapes_Serde");
            Set_Text (Candidate.With_Units (1), "Production_Shapes");
            if With_Count = 2 then
               Set_Text (Candidate.With_Units (2), "Other_Unit");
            end if;

            Candidate.Types (1).Kind := Enumeration_Node;
            Candidate.Types (1).Defining_With := 1;
            Set_Text
              (Candidate.Types (1).Ada_Type, "Production_Shapes.Position");
            Candidate.Types (1).Literal_First := 1;
            Candidate.Types (1).Literal_Count := 3;

            Candidate.Types (2).Kind := Enumeration_Node;
            Candidate.Types (2).Defining_With := 1;
            Set_Text (Candidate.Types (2).Ada_Type, "Production_Shapes.Color");
            Set_Text (Candidate.Types (2).Logical_Name, "production.color");
            Candidate.Types (2).Literal_First := 4;
            Candidate.Types (2).Literal_Count := 3;

            Candidate.Types (3).Kind := Fixed_Array_Node;
            Candidate.Types (3).Defining_With := 1;
            Set_Text
              (Candidate.Types (3).Ada_Type, "Production_Shapes.Palette");
            Candidate.Types (3).Index_Node := 1;
            Candidate.Types (3).Element_Node := 2;

            Candidate.Types (4).Kind := Record_Node;
            Candidate.Types (4).Defining_With := 1;
            Set_Text
              (Candidate.Types (4).Ada_Type, "Production_Shapes.Packet");
            Set_Text (Candidate.Types (4).Logical_Name, "production.packet");
            Candidate.Types (4).Field_First := 1;
            Candidate.Types (4).Field_Count := 2;

            Set_Text (Candidate.Literals (1).Ada_Name, "First");
            Set_Text (Candidate.Literals (2).Ada_Name, "Middle");
            Set_Text (Candidate.Literals (3).Ada_Name, "Last");

            Set_Text (Candidate.Literals (4).Ada_Name, "Red");
            Set_Text (Candidate.Literals (4).Primary_Name, "red");
            Candidate.Literals (4).Alias_First := 1;
            Candidate.Literals (4).Alias_Count := 1;
            Set_Text (Candidate.Literals (5).Ada_Name, "Green");
            Set_Text (Candidate.Literals (5).Primary_Name, "green");
            Candidate.Literals (5).Alias_First := 2;
            Candidate.Literals (5).Alias_Count := 1;
            Set_Text (Candidate.Literals (6).Ada_Name, "Blue");
            Set_Text (Candidate.Literals (6).Primary_Name, "blue");
            Candidate.Literals (6).Alias_First := 3;
            Candidate.Literals (6).Alias_Count := 1;
            Set_Text (Candidate.Aliases (1), "r");
            Set_Text (Candidate.Aliases (2), "g");
            Set_Text (Candidate.Aliases (3), "b");

            Set_Text (Candidate.Fields (1).Ada_Component, "Shade");
            Set_Text (Candidate.Fields (1).Presentation_Name, "shade");
            Candidate.Fields (1).Type_Node := 2;
            Set_Text (Candidate.Fields (2).Ada_Component, "Samples");
            Set_Text (Candidate.Fields (2).Presentation_Name, "samples");
            Candidate.Fields (2).Type_Node := 3;

            case Kind is
               when Valid_Graph                =>
                  null;

               when Structure_Invalid          =>
                  Candidate.Fields (2).Type_Node := 0;

               when Self_Array_Index           =>
                  Candidate.Types (3).Index_Node := 3;

               when Forward_Array_Index        =>
                  Candidate.Types (3).Index_Node := 4;

               when Disconnected_Node          =>
                  Candidate.Fields (2).Type_Node := 2;

               when Duplicate_Enumeration_Name =>
                  Set_Text (Candidate.Aliases (2), "r");

               when Runtime_Unit_Collision     =>
                  Set_Text (Candidate.Unit_Name, "Flyology_Serde.Bad_Unit");

               when Missing_Defining_With      =>
                  Candidate.Types (2).Defining_With := 0;

               when Redirected_Defining_With   =>
                  Candidate.Types (2).Defining_With := 2;

               when Unused_With_Unit           =>
                  null;

               when Ignored_Array_Logical_Name =>
                  Set_Text (Candidate.Types (3).Logical_Name, "x");

               when Overlong_Generated_Line    =>
                  Set_Text
                    (Candidate.Fields (1).Ada_Component,
                     "SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS");
            end case;

            Candidate.Root := 4;
            Candidate.Work_Units := Work;
            Candidate.Serialization_Limits :=
              (Maximum_Nesting_Depth   => 8,
               Maximum_Container_Items => 16,
               Maximum_Text_Length     => 64,
               Maximum_Byte_Length     => 64,
               Maximum_Logical_Events  => 64);
            if not Graph_Structure_Is_Valid (Candidate.all) then
               Set (Diagnostic, Unsupported_Lowered_Model);
               Discard_Candidate;
            else
               Result.Graph := Candidate;
               Candidate := null;
               if Failure = Post_Transfer_Internal_Failure then
                  raise Program_Error;
               end if;
               if not Flyology_Serde_Generator.Rendering.Preflight_Unpublished
                        (Result)
               then
                  Candidate := Result.Graph;
                  Result.Graph := null;
                  pragma Assert (Unpublished_Graphs > 0);
                  Unpublished_Graphs := Unpublished_Graphs - 1;
                  Free_Graph (Candidate);
                  Set (Diagnostic, Unsupported_Lowered_Model);
               else
                  Result.Graph.Valid := True;
                  pragma Assert (Unpublished_Graphs > 0);
                  Unpublished_Graphs := Unpublished_Graphs - 1;
               end if;
            end if;
         exception
            when Storage_Error =>
               if Result.Graph /= null then
                  Result.Graph.Valid := False;
                  Candidate := Result.Graph;
                  Result.Graph := null;
                  pragma Assert (Unpublished_Graphs > 0);
                  Unpublished_Graphs := Unpublished_Graphs - 1;
                  Free_Graph (Candidate);
               end if;
               Discard_Candidate;
               Poison (Budget);
               Set (Diagnostic, Internal_Error);
            when others =>
               if Result.Graph /= null then
                  Result.Graph.Valid := False;
                  Candidate := Result.Graph;
                  Result.Graph := null;
                  pragma Assert (Unpublished_Graphs > 0);
                  Unpublished_Graphs := Unpublished_Graphs - 1;
                  Free_Graph (Candidate);
               end if;
               Discard_Candidate;
               Poison (Budget);
               Set (Diagnostic, Internal_Error);
         end;
      end return;
   end Production_Shapes;
end Flyology_Serde_Generator.Lowered_Records.Test_Fixtures;
