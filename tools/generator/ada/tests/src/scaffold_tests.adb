with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology_Serde_Generator.Diagnostics;
with Flyology_Serde_Generator.Generation;
with Flyology_Serde_Generator.Hashing;
with Flyology_Serde_Generator.Overlays;
with Flyology_Serde_Generator.Requests;

procedure Scaffold_Tests is
   use type Flyology_Serde_Generator.Diagnostics.Error_Code;
   use type Flyology_Serde_Generator.Overlays.Serialization_Limits;
   use type Flyology_Serde_Generator.Requests.Limit_Value;
   use type Flyology_Serde_Generator.Requests.Used_Value;

   function Read_File (Path : String) return String is
      use Ada.Strings.Unbounded;
      File   : Ada.Text_IO.File_Type;
      Result : Unbounded_String;
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
      while not Ada.Text_IO.End_Of_File (File) loop
         Append (Result, Ada.Text_IO.Get_Line (File));
         Append (Result, ASCII.LF);
      end loop;
      Ada.Text_IO.Close (File);
      return To_String (Result);
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         raise;
   end Read_File;

   generic
      with
        procedure Read_Length
          (Value      : Flyology_Serde_Generator.Overlays.Overlay_Document;
           Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
           Length     : in out Natural;
           Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic);
      with
        procedure Copy
          (Value      : Flyology_Serde_Generator.Overlays.Overlay_Document;
           Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
           Into       : in out String;
           Written    : in out Natural;
           Copied     : in out Boolean;
           Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic);
   function Observed_Text
     (Value  : Flyology_Serde_Generator.Overlays.Overlay_Document;
      Budget : in out Flyology_Serde_Generator.Requests.Operation_Budget) return String;

   function Observed_Text
     (Value  : Flyology_Serde_Generator.Overlays.Overlay_Document;
      Budget : in out Flyology_Serde_Generator.Requests.Operation_Budget) return String
   is
      Length     : Natural := 0;
      Diagnostic : Flyology_Serde_Generator.Diagnostics.Diagnostic;
   begin
      Flyology_Serde_Generator.Diagnostics.Clear (Diagnostic);
      Read_Length (Value, Budget, Length, Diagnostic);
      return Result : String (5 .. 4 + Length) do
         declare
            Written : Natural := Natural'Last;
            Copied  : Boolean := False;
         begin
            Copy (Value, Budget, Result, Written, Copied, Diagnostic);
            pragma Assert (Copied and then Written = Length);
            pragma Assert
              (Flyology_Serde_Generator.Diagnostics.Code (Diagnostic) =
                 Flyology_Serde_Generator.Diagnostics.No_Error);
         end;
      end return;
   end Observed_Text;

   generic
      with
        procedure Read_Length
          (Value      : Flyology_Serde_Generator.Overlays.Overlay_Document;
           Index      : Positive;
           Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
           Length     : in out Natural;
           Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic);
      with
        procedure Copy
          (Value      : Flyology_Serde_Generator.Overlays.Overlay_Document;
           Index      : Positive;
           Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
           Into       : in out String;
           Written    : in out Natural;
           Copied     : in out Boolean;
           Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic);
   function Observed_Indexed_Text
     (Value  : Flyology_Serde_Generator.Overlays.Overlay_Document;
      Index  : Positive;
      Budget : in out Flyology_Serde_Generator.Requests.Operation_Budget) return String;

   function Observed_Indexed_Text
     (Value  : Flyology_Serde_Generator.Overlays.Overlay_Document;
      Index  : Positive;
      Budget : in out Flyology_Serde_Generator.Requests.Operation_Budget) return String
   is
      Length     : Natural := 0;
      Diagnostic : Flyology_Serde_Generator.Diagnostics.Diagnostic;
   begin
      Flyology_Serde_Generator.Diagnostics.Clear (Diagnostic);
      Read_Length (Value, Index, Budget, Length, Diagnostic);
      return Result : String (1 .. Length) do
         declare
            Written : Natural := 0;
            Copied  : Boolean := False;
         begin
            Copy (Value, Index, Budget, Result, Written, Copied, Diagnostic);
            pragma Assert (Copied and then Written = Length);
            pragma Assert
              (Flyology_Serde_Generator.Diagnostics.Code (Diagnostic) =
                 Flyology_Serde_Generator.Diagnostics.No_Error);
         end;
      end return;
   end Observed_Indexed_Text;

   function Observed_Output_Unit is new Observed_Text
     (Flyology_Serde_Generator.Overlays.Read_Output_Unit_Length,
      Flyology_Serde_Generator.Overlays.Copy_Output_Unit);
   function Observed_Type_IR_Commit is new Observed_Text
     (Flyology_Serde_Generator.Overlays.Read_Type_IR_Commit_Length,
      Flyology_Serde_Generator.Overlays.Copy_Type_IR_Commit);
   function Observed_Type_IR_Semantic_Fingerprint is new Observed_Text
     (Flyology_Serde_Generator.Overlays.Read_Type_IR_Semantic_Fingerprint_Length,
      Flyology_Serde_Generator.Overlays.Copy_Type_IR_Semantic_Fingerprint);
   function Observed_Type_IR_Source_SHA256 is new Observed_Text
     (Flyology_Serde_Generator.Overlays.Read_Type_IR_Source_SHA256_Length,
      Flyology_Serde_Generator.Overlays.Copy_Type_IR_Source_SHA256);
   function Observed_Source_SHA256 is new Observed_Text
     (Flyology_Serde_Generator.Overlays.Read_Source_SHA256_Length,
      Flyology_Serde_Generator.Overlays.Copy_Source_SHA256);
   function Observed_Record_Ada_Type is new Observed_Text
     (Flyology_Serde_Generator.Overlays.Read_Record_Ada_Type_Length,
      Flyology_Serde_Generator.Overlays.Copy_Record_Ada_Type);
   function Observed_Record_Declaration_ID is new Observed_Text
     (Flyology_Serde_Generator.Overlays.Read_Record_Declaration_ID_Length,
      Flyology_Serde_Generator.Overlays.Copy_Record_Declaration_ID);
   function Observed_Record_Logical_Type_Name is new Observed_Text
     (Flyology_Serde_Generator.Overlays.Read_Record_Logical_Type_Name_Length,
      Flyology_Serde_Generator.Overlays.Copy_Record_Logical_Type_Name);
   function Observed_With_Unit is new Observed_Indexed_Text
     (Flyology_Serde_Generator.Overlays.Read_With_Unit_Length,
      Flyology_Serde_Generator.Overlays.Copy_With_Unit);
   function Observed_Field_Ada_Component is new Observed_Indexed_Text
     (Flyology_Serde_Generator.Overlays.Read_Field_Ada_Component_Length,
      Flyology_Serde_Generator.Overlays.Copy_Field_Ada_Component);
   function Observed_Field_Ada_Type is new Observed_Indexed_Text
     (Flyology_Serde_Generator.Overlays.Read_Field_Ada_Type_Length,
      Flyology_Serde_Generator.Overlays.Copy_Field_Ada_Type);
   function Observed_Field_Component_ID is new Observed_Indexed_Text
     (Flyology_Serde_Generator.Overlays.Read_Field_Component_ID_Length,
      Flyology_Serde_Generator.Overlays.Copy_Field_Component_ID);
   function Observed_Field_Presentation_Name is new Observed_Indexed_Text
     (Flyology_Serde_Generator.Overlays.Read_Field_Presentation_Name_Length,
      Flyology_Serde_Generator.Overlays.Copy_Field_Presentation_Name);

   function Limits
     (Maximum_Path_Bytes       : Flyology_Serde_Generator.Requests.Limit_Value;
      Maximum_Diagnostic_Bytes : Flyology_Serde_Generator.Requests.Limit_Value)
      return Flyology_Serde_Generator.Requests.Generation_Limits
   is
     (Maximum_Path_Bytes       => Maximum_Path_Bytes,
      Maximum_Diagnostic_Bytes => Maximum_Diagnostic_Bytes,
     others                   => 1);

   Overlay_Limits : constant Flyology_Serde_Generator.Requests.Generation_Limits :=
     (Maximum_Path_Bytes              => 4_096,
      Maximum_Input_Bytes_Per_File    => 1_048_576,
      Maximum_Total_Input_Bytes       => 1_048_576,
      Maximum_Decoded_String_Bytes    => 4_096,
      Maximum_Number_Token_Bytes      => 32,
      Maximum_JSON_Nesting            => 8,
      Maximum_Object_Members          => 16,
      Maximum_Array_Elements          => 256,
      Maximum_Type_IR_Nodes           => 1,
      Maximum_Overlay_Nodes           => 4_096,
      Maximum_Rendered_Bytes_Per_File => 1,
      Maximum_Total_Rendered_Bytes    => 1,
      Maximum_Artifact_Files          => 1,
      Maximum_Diagnostics             => 16,
      Maximum_Diagnostic_Bytes        => 256,
      Maximum_Work_Units              => 1_052_672);

   Request    : Flyology_Serde_Generator.Requests.Generation_Request;
   Empty      : Flyology_Serde_Generator.Requests.Generation_Request;
   Diagnostic : Flyology_Serde_Generator.Diagnostics.Diagnostic;
begin
   pragma Assert (Ada.Command_Line.Argument_Count = 1);
   pragma Assert
     (Flyology_Serde_Generator.Hashing.SHA_256 ("") =
        "e3b0c44298fc1c149afbf4c8996fb924" & "27ae41e4649b934ca495991b7852b855");

   declare
      Source  : constant String := Read_File (Ada.Command_Line.Argument (1));
      Overlay : Flyology_Serde_Generator.Overlays.Overlay_Document;
      Budget  : Flyology_Serde_Generator.Requests.Operation_Budget;

      type Limit_Dimension is
        (Input_Per_File, Total_Input, String_Bytes, Number_Bytes, Nesting, Members, Elements, Nodes, Work);

      procedure Expect_Limit
        (Dimension : Limit_Dimension;
         Maximum   : Flyology_Serde_Generator.Requests.Limit_Value;
         Expected  : Flyology_Serde_Generator.Diagnostics.Error_Code)
      is
         Attempt_Limits : Flyology_Serde_Generator.Requests.Generation_Limits := Overlay_Limits;
         Attempt_Budget : Flyology_Serde_Generator.Requests.Operation_Budget;
         Attempt        : Flyology_Serde_Generator.Overlays.Overlay_Document;
      begin
         case Dimension is
            when Input_Per_File => Attempt_Limits.Maximum_Input_Bytes_Per_File := Maximum;
            when Total_Input    => Attempt_Limits.Maximum_Total_Input_Bytes := Maximum;
            when String_Bytes   => Attempt_Limits.Maximum_Decoded_String_Bytes := Maximum;
            when Number_Bytes   => Attempt_Limits.Maximum_Number_Token_Bytes := Maximum;
            when Nesting        => Attempt_Limits.Maximum_JSON_Nesting := Maximum;
            when Members        => Attempt_Limits.Maximum_Object_Members := Maximum;
            when Elements       => Attempt_Limits.Maximum_Array_Elements := Maximum;
            when Nodes          => Attempt_Limits.Maximum_Overlay_Nodes := Maximum;
            when Work           => Attempt_Limits.Maximum_Work_Units := Maximum;
         end case;
         Flyology_Serde_Generator.Requests.Start_Budget (Attempt_Limits, Attempt_Budget);
         Flyology_Serde_Generator.Overlays.Decode_Checked
           (Source, Attempt_Budget, Attempt, Diagnostic);
         pragma Assert (Flyology_Serde_Generator.Diagnostics.Code (Diagnostic) = Expected);
         if Expected = Flyology_Serde_Generator.Diagnostics.Resource_Exhausted then
            pragma Assert (Flyology_Serde_Generator.Requests.Is_Poisoned (Attempt_Budget));
            Flyology_Serde_Generator.Overlays.Decode_Checked
              ("null", Attempt_Budget, Attempt, Diagnostic);
            pragma Assert
              (Flyology_Serde_Generator.Diagnostics.Code (Diagnostic) =
                 Flyology_Serde_Generator.Diagnostics.Resource_Exhausted);
         end if;
      end Expect_Limit;

      function Query_Limits
        (Maximum_Work : Flyology_Serde_Generator.Requests.Limit_Value)
         return Flyology_Serde_Generator.Requests.Generation_Limits
      is
         Result : Flyology_Serde_Generator.Requests.Generation_Limits := Overlay_Limits;
      begin
         Result.Maximum_Work_Units := Maximum_Work;
         return Result;
      end Query_Limits;

      procedure Check_Query_API
        (Value : Flyology_Serde_Generator.Overlays.Overlay_Document)
      is
         Expected : constant String := "Flyology.Generated";
      begin
         declare
            Query_Budget : Flyology_Serde_Generator.Requests.Operation_Budget;
            Query_Error  : Flyology_Serde_Generator.Diagnostics.Diagnostic;
            Fixture      : Boolean := False;
            Count        : Natural := Natural'Last;
            Usage        : Flyology_Serde_Generator.Requests.Budget_Usage;
         begin
            Flyology_Serde_Generator.Requests.Start_Budget (Query_Limits (8), Query_Budget);
            Flyology_Serde_Generator.Diagnostics.Clear (Query_Error);
            Flyology_Serde_Generator.Overlays.Read_Fixture_Only
              (Value, Query_Budget, Fixture, Query_Error);
            Flyology_Serde_Generator.Overlays.Read_Field_Count
              (Value, Query_Budget, Count, Query_Error);
            Usage := Flyology_Serde_Generator.Requests.Current_Usage (Query_Budget);
            pragma Assert (Fixture and then Count = 3);
            pragma Assert (Usage.Work_Units = 2);
         end;

         declare
            Query_Budget : Flyology_Serde_Generator.Requests.Operation_Budget;
            Query_Error  : Flyology_Serde_Generator.Diagnostics.Diagnostic;
            Length       : Natural := Natural'Last;
            Usage        : Flyology_Serde_Generator.Requests.Budget_Usage;
         begin
            Flyology_Serde_Generator.Requests.Start_Budget (Query_Limits (2), Query_Budget);
            Flyology_Serde_Generator.Diagnostics.Clear (Query_Error);
            Flyology_Serde_Generator.Overlays.Read_Output_Unit_Length
              (Value, Query_Budget, Length, Query_Error);
            Usage := Flyology_Serde_Generator.Requests.Current_Usage (Query_Budget);
            pragma Assert (Length = Expected'Length);
            pragma Assert (Usage.Work_Units = 1);
         end;

         declare
            Query_Budget : Flyology_Serde_Generator.Requests.Operation_Budget;
            Query_Error  : Flyology_Serde_Generator.Diagnostics.Diagnostic;
            Target       : String (5 .. 5) := "x";
            Written      : Natural := 42;
            Copied       : Boolean := True;
            Usage        : Flyology_Serde_Generator.Requests.Budget_Usage;
         begin
            Flyology_Serde_Generator.Requests.Start_Budget (Query_Limits (2), Query_Budget);
            Flyology_Serde_Generator.Diagnostics.Clear (Query_Error);
            Flyology_Serde_Generator.Overlays.Copy_Output_Unit
              (Value, Query_Budget, Target, Written, Copied, Query_Error);
            Usage := Flyology_Serde_Generator.Requests.Current_Usage (Query_Budget);
            pragma Assert
              (Flyology_Serde_Generator.Diagnostics.Code (Query_Error) =
                 Flyology_Serde_Generator.Diagnostics.No_Error);
            pragma Assert (not Copied and then Target = "x" and then Written = 42);
            pragma Assert (Usage.Work_Units = 1);
            pragma Assert (not Flyology_Serde_Generator.Requests.Is_Poisoned (Query_Budget));
         end;

         declare
            Query_Budget : Flyology_Serde_Generator.Requests.Operation_Budget;
            Query_Error  : Flyology_Serde_Generator.Diagnostics.Diagnostic;
            Target       : String (7 .. 6 + Expected'Length) := [others => '?'];
            Written      : Natural := 0;
            Copied       : Boolean := False;
            Usage        : Flyology_Serde_Generator.Requests.Budget_Usage;
         begin
            Flyology_Serde_Generator.Requests.Start_Budget
              (Query_Limits (Expected'Length + 1), Query_Budget);
            Flyology_Serde_Generator.Diagnostics.Clear (Query_Error);
            Flyology_Serde_Generator.Overlays.Copy_Output_Unit
              (Value, Query_Budget, Target, Written, Copied, Query_Error);
            Usage := Flyology_Serde_Generator.Requests.Current_Usage (Query_Budget);
            pragma Assert (Copied and then Written = Expected'Length and then Target = Expected);
            pragma Assert
              (Usage.Work_Units = Flyology_Serde_Generator.Requests.Used_Value (Expected'Length + 1));
         end;

         declare
            Query_Budget : Flyology_Serde_Generator.Requests.Operation_Budget;
            Query_Error  : Flyology_Serde_Generator.Diagnostics.Diagnostic;
            Target       : String (1 .. Expected'Length) := [others => '?'];
            Prior        : constant String := Target;
            Written      : Natural := 77;
            Copied       : Boolean := True;
         begin
            Flyology_Serde_Generator.Requests.Start_Budget (Query_Limits (1), Query_Budget);
            Flyology_Serde_Generator.Diagnostics.Clear (Query_Error);
            Flyology_Serde_Generator.Overlays.Copy_Output_Unit
              (Value, Query_Budget, Target, Written, Copied, Query_Error);
            pragma Assert
              (Flyology_Serde_Generator.Diagnostics.Code (Query_Error) =
                 Flyology_Serde_Generator.Diagnostics.Resource_Exhausted);
            pragma Assert (Target = Prior and then Written = 77 and then Copied);
            pragma Assert (Flyology_Serde_Generator.Requests.Is_Poisoned (Query_Budget));
         end;

         declare
            Query_Budget : Flyology_Serde_Generator.Requests.Operation_Budget;
            Query_Error  : Flyology_Serde_Generator.Diagnostics.Diagnostic;
            Target       : String (1 .. Expected'Length) := [others => '?'];
            Prior        : constant String := Target;
            Written      : Natural := 77;
            Copied       : Boolean := True;
            Accepted     : Boolean;
         begin
            Flyology_Serde_Generator.Requests.Start_Budget (Query_Limits (1), Query_Budget);
            Flyology_Serde_Generator.Requests.Charge_Work (Query_Budget, 1, Accepted);
            pragma Assert (Accepted);
            Flyology_Serde_Generator.Diagnostics.Clear (Query_Error);
            Flyology_Serde_Generator.Overlays.Copy_Output_Unit
              (Value, Query_Budget, Target, Written, Copied, Query_Error);
            pragma Assert
              (Flyology_Serde_Generator.Diagnostics.Code (Query_Error) =
                 Flyology_Serde_Generator.Diagnostics.Resource_Exhausted);
            pragma Assert (Target = Prior and then Written = 77 and then Copied);
         end;

         declare
            Query_Budget : Flyology_Serde_Generator.Requests.Operation_Budget;
            Query_Error  : Flyology_Serde_Generator.Diagnostics.Diagnostic;
            Length       : Natural := 99;
            Usage        : Flyology_Serde_Generator.Requests.Budget_Usage;
         begin
            Flyology_Serde_Generator.Requests.Start_Budget (Query_Limits (4), Query_Budget);
            Flyology_Serde_Generator.Diagnostics.Clear (Query_Error);
            Flyology_Serde_Generator.Overlays.Read_With_Unit_Length
              (Value, 2, Query_Budget, Length, Query_Error);
            Usage := Flyology_Serde_Generator.Requests.Current_Usage (Query_Budget);
            pragma Assert
              (Flyology_Serde_Generator.Diagnostics.Code (Query_Error) =
                 Flyology_Serde_Generator.Diagnostics.Internal_Error);
            pragma Assert (Length = 99 and then Usage.Work_Units = 0);

            Flyology_Serde_Generator.Diagnostics.Set
              (Query_Error, Flyology_Serde_Generator.Diagnostics.Invalid_Arguments);
            Flyology_Serde_Generator.Overlays.Read_With_Unit_Length
              (Value, 2, Query_Budget, Length, Query_Error);
            Usage := Flyology_Serde_Generator.Requests.Current_Usage (Query_Budget);
            pragma Assert
              (Flyology_Serde_Generator.Diagnostics.Code (Query_Error) =
                 Flyology_Serde_Generator.Diagnostics.Invalid_Arguments);
            pragma Assert (Length = 99 and then Usage.Work_Units = 0);

            Flyology_Serde_Generator.Diagnostics.Clear (Query_Error);
            Flyology_Serde_Generator.Requests.Poison (Query_Budget);
            Flyology_Serde_Generator.Overlays.Read_With_Unit_Length
              (Value, 2, Query_Budget, Length, Query_Error);
            pragma Assert
              (Flyology_Serde_Generator.Diagnostics.Code (Query_Error) =
                 Flyology_Serde_Generator.Diagnostics.Resource_Exhausted);
            pragma Assert (Length = 99);
         end;

         declare
            Query_Budget : Flyology_Serde_Generator.Requests.Operation_Budget;
            Query_Error  : Flyology_Serde_Generator.Diagnostics.Diagnostic;
            Target       : String (1 .. Expected'Length) := [others => '?'];
            Prior        : constant String := Target;
            Written      : Natural := 88;
            Copied       : Boolean := True;
            Usage        : Flyology_Serde_Generator.Requests.Budget_Usage;
         begin
            Flyology_Serde_Generator.Requests.Start_Budget (Query_Limits (4), Query_Budget);
            Flyology_Serde_Generator.Diagnostics.Set
              (Query_Error, Flyology_Serde_Generator.Diagnostics.Invalid_Arguments);
            Flyology_Serde_Generator.Overlays.Copy_Output_Unit
              (Value, Query_Budget, Target, Written, Copied, Query_Error);
            Usage := Flyology_Serde_Generator.Requests.Current_Usage (Query_Budget);
            pragma Assert
              (Flyology_Serde_Generator.Diagnostics.Code (Query_Error) =
                 Flyology_Serde_Generator.Diagnostics.Invalid_Arguments);
            pragma Assert (Target = Prior and then Written = 88 and then Copied);
            pragma Assert (Usage.Work_Units = 0);

            Flyology_Serde_Generator.Requests.Poison (Query_Budget);
            Flyology_Serde_Generator.Overlays.Copy_Output_Unit
              (Value, Query_Budget, Target, Written, Copied, Query_Error);
            Usage := Flyology_Serde_Generator.Requests.Current_Usage (Query_Budget);
            pragma Assert
              (Flyology_Serde_Generator.Diagnostics.Code (Query_Error) =
                 Flyology_Serde_Generator.Diagnostics.Invalid_Arguments);
            pragma Assert (Target = Prior and then Written = 88 and then Copied);
            pragma Assert (Usage.Work_Units = 0);
         end;
      end Check_Query_API;
   begin
      Flyology_Serde_Generator.Requests.Start_Budget (Overlay_Limits, Budget);
      Flyology_Serde_Generator.Overlays.Load_Checked
        (Ada.Command_Line.Argument (1), Budget, Overlay, Diagnostic);
      pragma Assert
        (Flyology_Serde_Generator.Diagnostics.Code (Diagnostic) =
           Flyology_Serde_Generator.Diagnostics.No_Error);
      pragma Assert (Flyology_Serde_Generator.Overlays.Is_Valid (Overlay));

      declare
         Usage : constant Flyology_Serde_Generator.Requests.Budget_Usage :=
           Flyology_Serde_Generator.Requests.Current_Usage (Budget);
         Last_Work : constant Flyology_Serde_Generator.Requests.Limit_Value :=
           Flyology_Serde_Generator.Requests.Limit_Value (Usage.Work_Units);
      begin
         pragma Assert
           (Usage.Input_Bytes = Flyology_Serde_Generator.Requests.Used_Value (Source'Length));
         pragma Assert (Usage.Overlay_Nodes = 36);
         Expect_Limit
           (Input_Per_File,
            Flyology_Serde_Generator.Requests.Limit_Value (Source'Length),
            Flyology_Serde_Generator.Diagnostics.No_Error);
         Expect_Limit
           (Input_Per_File,
            Flyology_Serde_Generator.Requests.Limit_Value (Source'Length - 1),
            Flyology_Serde_Generator.Diagnostics.Resource_Exhausted);
         Expect_Limit
           (Total_Input,
            Flyology_Serde_Generator.Requests.Limit_Value (Source'Length),
            Flyology_Serde_Generator.Diagnostics.No_Error);
         Expect_Limit
           (Total_Input,
            Flyology_Serde_Generator.Requests.Limit_Value (Source'Length - 1),
            Flyology_Serde_Generator.Diagnostics.Resource_Exhausted);
         Expect_Limit (String_Bytes, 64, Flyology_Serde_Generator.Diagnostics.No_Error);
         Expect_Limit (String_Bytes, 63, Flyology_Serde_Generator.Diagnostics.Resource_Exhausted);
         Expect_Limit (Number_Bytes, 2, Flyology_Serde_Generator.Diagnostics.No_Error);
         Expect_Limit (Number_Bytes, 1, Flyology_Serde_Generator.Diagnostics.Resource_Exhausted);
         Expect_Limit (Nesting, 5, Flyology_Serde_Generator.Diagnostics.No_Error);
         Expect_Limit (Nesting, 4, Flyology_Serde_Generator.Diagnostics.Resource_Exhausted);
         Expect_Limit (Members, 9, Flyology_Serde_Generator.Diagnostics.No_Error);
         Expect_Limit (Members, 8, Flyology_Serde_Generator.Diagnostics.Resource_Exhausted);
         Expect_Limit (Elements, 3, Flyology_Serde_Generator.Diagnostics.No_Error);
         Expect_Limit (Elements, 2, Flyology_Serde_Generator.Diagnostics.Resource_Exhausted);
         Expect_Limit (Nodes, 36, Flyology_Serde_Generator.Diagnostics.No_Error);
         Expect_Limit (Nodes, 35, Flyology_Serde_Generator.Diagnostics.Resource_Exhausted);
         Expect_Limit (Work, Last_Work, Flyology_Serde_Generator.Diagnostics.No_Error);
         Expect_Limit (Work, Last_Work - 1, Flyology_Serde_Generator.Diagnostics.Resource_Exhausted);
      end;

      declare
         Fixture_Only : Boolean := False;
         With_Count   : Natural := 0;
         Field_Count  : Natural := 0;
         Read_Limits  : Flyology_Serde_Generator.Overlays.Serialization_Limits := (others => 0);
      begin
         Flyology_Serde_Generator.Diagnostics.Clear (Diagnostic);
         Flyology_Serde_Generator.Overlays.Read_Fixture_Only
           (Overlay, Budget, Fixture_Only, Diagnostic);
         Flyology_Serde_Generator.Overlays.Read_Runtime_Limits
           (Overlay, Budget, Read_Limits, Diagnostic);
         Flyology_Serde_Generator.Overlays.Read_With_Unit_Count
           (Overlay, Budget, With_Count, Diagnostic);
         Flyology_Serde_Generator.Overlays.Read_Field_Count
           (Overlay, Budget, Field_Count, Diagnostic);
         pragma Assert
           (Flyology_Serde_Generator.Diagnostics.Code (Diagnostic) =
              Flyology_Serde_Generator.Diagnostics.No_Error);
         pragma Assert (Fixture_Only);
         pragma Assert (With_Count = 1);
         pragma Assert (Field_Count = 3);
         pragma Assert
           (Read_Limits =
              (Maximum_Byte_Length     => 64,
               Maximum_Container_Items => 16,
               Maximum_Logical_Events  => 64,
               Maximum_Nesting_Depth   => 8,
               Maximum_Text_Length     => 64));
         pragma Assert (Observed_Output_Unit (Overlay, Budget) = "Flyology.Generated");
         pragma Assert
           (Observed_Type_IR_Commit (Overlay, Budget) =
              "78e6726a80d02b22f573fed3f65538cafd89fc0d");
         pragma Assert
           (Observed_Type_IR_Semantic_Fingerprint (Overlay, Budget) =
              "e5f5da08e77e057960fe9ab987b3400e5557a017ae62fcdaa8d4e376042d7f76");
         pragma Assert
           (Observed_Type_IR_Source_SHA256 (Overlay, Budget) =
              "92aa85c19c3d0dcfd531f42b75743559efd4f80919942a9acce5f5e15d323c4a");
         pragma Assert
           (Observed_Source_SHA256 (Overlay, Budget) =
              Flyology_Serde_Generator.Hashing.SHA_256 (Source));
         pragma Assert (Observed_With_Unit (Overlay, 1, Budget) = "Wire_Shape");
         pragma Assert
           (Observed_Record_Ada_Type (Overlay, Budget) = "Wire_Shape.Public_Record");
         pragma Assert
           (Observed_Record_Declaration_ID (Overlay, Budget) =
              "decl:wire_shape.public_record#public");
         pragma Assert
           (Observed_Record_Logical_Type_Name (Overlay, Budget) = "wire_shape.public_record");
         pragma Assert (Observed_Field_Ada_Component (Overlay, 1, Budget) = "Enabled");
         pragma Assert (Observed_Field_Ada_Type (Overlay, 2, Budget) = "Wire_Shape.Signed_16");
         pragma Assert
           (Observed_Field_Component_ID (Overlay, 3, Budget) =
              "decl:wire_shape.public_record.unsigned#public");
         pragma Assert (Observed_Field_Presentation_Name (Overlay, 2, Budget) = "signed");
      end;
      Check_Query_API (Overlay);

      declare
         Tiny_Source : constant String := "{""a"":null,""bb"":null,""ccc"":null}" & ASCII.LF;
         Attempt     : Flyology_Serde_Generator.Requests.Operation_Budget;
         Rejected    : Flyology_Serde_Generator.Overlays.Overlay_Document;
         Usage       : Flyology_Serde_Generator.Requests.Budget_Usage;
      begin
         Flyology_Serde_Generator.Requests.Start_Budget (Overlay_Limits, Attempt);
         Flyology_Serde_Generator.Overlays.Decode_Checked
           (Tiny_Source, Attempt, Rejected, Diagnostic);
         pragma Assert
           (Flyology_Serde_Generator.Diagnostics.Code (Diagnostic) =
              Flyology_Serde_Generator.Diagnostics.Unsupported_Overlay);
         Usage := Flyology_Serde_Generator.Requests.Current_Usage (Attempt);
         pragma Assert
           (Usage.Work_Units =
              Flyology_Serde_Generator.Requests.Used_Value (2 * Tiny_Source'Length + 11));
      end;

      declare
         Rejected : Flyology_Serde_Generator.Overlays.Overlay_Document;
         Attempt  : Flyology_Serde_Generator.Requests.Operation_Budget;
      begin
         Flyology_Serde_Generator.Requests.Start_Budget (Overlay_Limits, Attempt);
         Flyology_Serde_Generator.Overlays.Decode_Checked
           (" " & Source, Attempt, Rejected, Diagnostic);
         pragma Assert
           (Flyology_Serde_Generator.Diagnostics.Code (Diagnostic) =
              Flyology_Serde_Generator.Diagnostics.Noncanonical_Overlay);
         pragma Assert (not Flyology_Serde_Generator.Overlays.Is_Valid (Rejected));
      end;

      declare
         Attempt : Flyology_Serde_Generator.Requests.Operation_Budget;
      begin
         Flyology_Serde_Generator.Requests.Start_Budget (Overlay_Limits, Attempt);
         Flyology_Serde_Generator.Overlays.Decode_Checked
           (" " & Source, Attempt, Overlay, Diagnostic);
         pragma Assert
           (Flyology_Serde_Generator.Diagnostics.Code (Diagnostic) =
              Flyology_Serde_Generator.Diagnostics.Noncanonical_Overlay);
         pragma Assert (Flyology_Serde_Generator.Overlays.Is_Valid (Overlay));
         pragma Assert (Observed_Output_Unit (Overlay, Budget) = "Flyology.Generated");
      end;

      declare
         Attempt : Flyology_Serde_Generator.Requests.Operation_Budget;
      begin
         Flyology_Serde_Generator.Requests.Start_Budget (Overlay_Limits, Attempt);
         Flyology_Serde_Generator.Overlays.Load_Checked
           (Ada.Command_Line.Argument (1) & ".missing", Attempt, Overlay, Diagnostic);
         pragma Assert
           (Flyology_Serde_Generator.Diagnostics.Code (Diagnostic) =
              Flyology_Serde_Generator.Diagnostics.Input_IO_Error);
         pragma Assert (Flyology_Serde_Generator.Overlays.Is_Valid (Overlay));
         pragma Assert (Observed_Output_Unit (Overlay, Budget) = "Flyology.Generated");
      end;

      declare
         Attempt : Flyology_Serde_Generator.Requests.Operation_Budget;
      begin
         Flyology_Serde_Generator.Requests.Start_Budget (Overlay_Limits, Attempt);
         Flyology_Serde_Generator.Overlays.Load_Checked ("", Attempt, Overlay, Diagnostic);
         pragma Assert
           (Flyology_Serde_Generator.Diagnostics.Code (Diagnostic) =
              Flyology_Serde_Generator.Diagnostics.Input_IO_Error);
         pragma Assert (Flyology_Serde_Generator.Overlays.Is_Valid (Overlay));
         Flyology_Serde_Generator.Overlays.Load_Checked
           (String'(1 => ASCII.NUL), Attempt, Overlay, Diagnostic);
         pragma Assert
           (Flyology_Serde_Generator.Diagnostics.Code (Diagnostic) =
              Flyology_Serde_Generator.Diagnostics.Input_IO_Error);
         pragma Assert (Flyology_Serde_Generator.Overlays.Is_Valid (Overlay));
      end;

      declare
         Small_Path : Flyology_Serde_Generator.Requests.Generation_Limits := Overlay_Limits;
         Attempt    : Flyology_Serde_Generator.Requests.Operation_Budget;
      begin
         Small_Path.Maximum_Path_Bytes := 1;
         Flyology_Serde_Generator.Requests.Start_Budget (Small_Path, Attempt);
         Flyology_Serde_Generator.Overlays.Load_Checked ("ii", Attempt, Overlay, Diagnostic);
         pragma Assert
           (Flyology_Serde_Generator.Diagnostics.Code (Diagnostic) =
              Flyology_Serde_Generator.Diagnostics.Resource_Exhausted);
         pragma Assert (Flyology_Serde_Generator.Requests.Is_Poisoned (Attempt));
         pragma Assert (Flyology_Serde_Generator.Overlays.Is_Valid (Overlay));
      end;

      declare
         Rejected : Flyology_Serde_Generator.Overlays.Overlay_Document;
         Attempt  : Flyology_Serde_Generator.Requests.Operation_Budget;
      begin
         Flyology_Serde_Generator.Requests.Start_Budget (Overlay_Limits, Attempt);
         Flyology_Serde_Generator.Overlays.Decode_Checked
           ("{""fixture_only"":true,""fixture_only"":false}" & ASCII.LF,
            Attempt,
            Rejected,
            Diagnostic);
         pragma Assert
           (Flyology_Serde_Generator.Diagnostics.Code (Diagnostic) =
              Flyology_Serde_Generator.Diagnostics.Invalid_Overlay_JSON);
      end;

      declare
         Rejected    : Flyology_Serde_Generator.Overlays.Overlay_Document;
         Small_Input : Flyology_Serde_Generator.Requests.Generation_Limits := Overlay_Limits;
         Attempt     : Flyology_Serde_Generator.Requests.Operation_Budget;
      begin
         Small_Input.Maximum_Input_Bytes_Per_File := 1;
         Flyology_Serde_Generator.Requests.Start_Budget (Small_Input, Attempt);
         Flyology_Serde_Generator.Overlays.Decode_Checked
           (Source, Attempt, Rejected, Diagnostic);
         pragma Assert
           (Flyology_Serde_Generator.Diagnostics.Code (Diagnostic) =
              Flyology_Serde_Generator.Diagnostics.Resource_Exhausted);
      end;

      declare
         Twice_Limits : Flyology_Serde_Generator.Requests.Generation_Limits := Overlay_Limits;
         Attempt      : Flyology_Serde_Generator.Requests.Operation_Budget;
         Replacement  : Flyology_Serde_Generator.Overlays.Overlay_Document;
      begin
         Twice_Limits.Maximum_Total_Input_Bytes :=
           Flyology_Serde_Generator.Requests.Limit_Value (2 * Source'Length - 1);
         Flyology_Serde_Generator.Requests.Start_Budget (Twice_Limits, Attempt);
         Flyology_Serde_Generator.Overlays.Decode_Checked
           (Source, Attempt, Replacement, Diagnostic);
         pragma Assert
           (Flyology_Serde_Generator.Diagnostics.Code (Diagnostic) =
              Flyology_Serde_Generator.Diagnostics.No_Error);
         Flyology_Serde_Generator.Overlays.Decode_Checked
           (Source, Attempt, Replacement, Diagnostic);
         pragma Assert
           (Flyology_Serde_Generator.Diagnostics.Code (Diagnostic) =
              Flyology_Serde_Generator.Diagnostics.Resource_Exhausted);
         pragma Assert (Flyology_Serde_Generator.Requests.Is_Poisoned (Attempt));
         pragma Assert (Flyology_Serde_Generator.Overlays.Is_Valid (Replacement));
         Flyology_Serde_Generator.Overlays.Decode_Checked
           ("null", Attempt, Replacement, Diagnostic);
         pragma Assert
           (Flyology_Serde_Generator.Diagnostics.Code (Diagnostic) =
              Flyology_Serde_Generator.Diagnostics.Resource_Exhausted);
         pragma Assert (Flyology_Serde_Generator.Overlays.Is_Valid (Replacement));
      end;

      declare
         Edge_Source : constant String (Integer'Last - 3 .. Integer'Last) := "null";
         Attempt     : Flyology_Serde_Generator.Requests.Operation_Budget;
         Rejected    : Flyology_Serde_Generator.Overlays.Overlay_Document;
      begin
         Flyology_Serde_Generator.Requests.Start_Budget (Overlay_Limits, Attempt);
         Flyology_Serde_Generator.Overlays.Decode_Checked
           (Edge_Source, Attempt, Rejected, Diagnostic);
         pragma Assert
           (Flyology_Serde_Generator.Diagnostics.Code (Diagnostic) =
              Flyology_Serde_Generator.Diagnostics.Unsupported_Overlay);
      end;
   end;

   Flyology_Serde_Generator.Generation.Generate (Empty, Diagnostic);
   pragma Assert
     (Flyology_Serde_Generator.Diagnostics.Code (Diagnostic) =
        Flyology_Serde_Generator.Diagnostics.Invalid_Arguments);

   Flyology_Serde_Generator.Requests.Build_Fixture
     ("i", Ada.Command_Line.Argument (1), "x", Overlay_Limits, Request, Diagnostic);
   pragma Assert (Flyology_Serde_Generator.Requests.Is_Valid (Request));
   pragma Assert (Flyology_Serde_Generator.Requests.Is_Fixture_Request (Request));
   pragma Assert
     (Flyology_Serde_Generator.Diagnostics.Code (Diagnostic) =
        Flyology_Serde_Generator.Diagnostics.No_Error);

   declare
      Query_Budget : Flyology_Serde_Generator.Requests.Operation_Budget;
      Query_Error  : Flyology_Serde_Generator.Diagnostics.Diagnostic;
      Path_Length  : Natural := 0;
      Usage        : Flyology_Serde_Generator.Requests.Budget_Usage;
   begin
      Flyology_Serde_Generator.Requests.Start_Budget (Overlay_Limits, Query_Budget);
      Flyology_Serde_Generator.Diagnostics.Clear (Query_Error);
      Flyology_Serde_Generator.Requests.Read_Overlay_Path_Length
        (Request, Query_Budget, Path_Length, Query_Error);
      declare
         Target  : String (9 .. 8 + Path_Length) := [others => '?'];
         Written : Natural := 0;
         Copied  : Boolean := False;
      begin
         Flyology_Serde_Generator.Requests.Copy_Overlay_Path
           (Request, Query_Budget, Target, Written, Copied, Query_Error);
         pragma Assert
           (Flyology_Serde_Generator.Diagnostics.Code (Query_Error) =
              Flyology_Serde_Generator.Diagnostics.No_Error);
         pragma Assert (Copied and then Written = Path_Length);
         pragma Assert (Target = Ada.Command_Line.Argument (1));
      end;
      Usage := Flyology_Serde_Generator.Requests.Current_Usage (Query_Budget);
      pragma Assert
        (Usage.Work_Units = Flyology_Serde_Generator.Requests.Used_Value (Path_Length + 2));
   end;

   declare
      Query_Budget : Flyology_Serde_Generator.Requests.Operation_Budget;
      Query_Error  : Flyology_Serde_Generator.Diagnostics.Diagnostic;
      Path_Length  : Natural := 0;
   begin
      Flyology_Serde_Generator.Requests.Start_Budget (Overlay_Limits, Query_Budget);
      Flyology_Serde_Generator.Diagnostics.Clear (Query_Error);
      Flyology_Serde_Generator.Requests.Read_Output_Path_Length
        (Request, Query_Budget, Path_Length, Query_Error);
      pragma Assert (Path_Length = 1);
      declare
         Target  : String (4 .. 3 + Path_Length) := [others => '?'];
         Written : Natural := 0;
         Copied  : Boolean := False;
      begin
         Flyology_Serde_Generator.Requests.Copy_Output_Path
           (Request, Query_Budget, Target, Written, Copied, Query_Error);
         pragma Assert (Copied and then Written = 1 and then Target = "x");
      end;
   end;

   declare
      Query_Budget : Flyology_Serde_Generator.Requests.Operation_Budget;
      Query_Error  : Flyology_Serde_Generator.Diagnostics.Diagnostic;
      Target       : String (1 .. 0);
      Written      : Natural := 73;
      Copied       : Boolean := True;
   begin
      Flyology_Serde_Generator.Requests.Start_Budget (Overlay_Limits, Query_Budget);
      Flyology_Serde_Generator.Diagnostics.Clear (Query_Error);
      Flyology_Serde_Generator.Requests.Copy_Output_Path
        (Request, Query_Budget, Target, Written, Copied, Query_Error);
      pragma Assert
        (Flyology_Serde_Generator.Diagnostics.Code (Query_Error) =
           Flyology_Serde_Generator.Diagnostics.No_Error);
      pragma Assert (not Copied and then Written = 73);
      pragma Assert (not Flyology_Serde_Generator.Requests.Is_Poisoned (Query_Budget));
   end;

   declare
      Query_Budget : Flyology_Serde_Generator.Requests.Operation_Budget;
      Query_Error  : Flyology_Serde_Generator.Diagnostics.Diagnostic;
      Target       : String (4 .. 4) := "?";
      Written      : Natural := 73;
      Copied       : Boolean := True;
      Accepted     : Boolean;
   begin
      Flyology_Serde_Generator.Requests.Start_Budget (Limits (1, 1), Query_Budget);
      Flyology_Serde_Generator.Requests.Charge_Work (Query_Budget, 1, Accepted);
      pragma Assert (Accepted);
      Flyology_Serde_Generator.Diagnostics.Clear (Query_Error);
      Flyology_Serde_Generator.Requests.Copy_Output_Path
        (Request, Query_Budget, Target, Written, Copied, Query_Error);
      pragma Assert
        (Flyology_Serde_Generator.Diagnostics.Code (Query_Error) =
           Flyology_Serde_Generator.Diagnostics.Resource_Exhausted);
      pragma Assert (Target = "?" and then Written = 73 and then Copied);
   end;

   declare
      Query_Budget : Flyology_Serde_Generator.Requests.Operation_Budget;
      Query_Error  : Flyology_Serde_Generator.Diagnostics.Diagnostic;
      Target       : String (4 .. 4) := "?";
      Written      : Natural := 73;
      Copied       : Boolean := True;
   begin
      Flyology_Serde_Generator.Requests.Start_Budget (Overlay_Limits, Query_Budget);
      Flyology_Serde_Generator.Diagnostics.Set
        (Query_Error, Flyology_Serde_Generator.Diagnostics.Invalid_Arguments);
      Flyology_Serde_Generator.Requests.Copy_Output_Path
        (Request, Query_Budget, Target, Written, Copied, Query_Error);
      pragma Assert
        (Flyology_Serde_Generator.Diagnostics.Code (Query_Error) =
           Flyology_Serde_Generator.Diagnostics.Invalid_Arguments);
      pragma Assert (Target = "?" and then Written = 73 and then Copied);
      pragma Assert
        (Flyology_Serde_Generator.Requests.Current_Usage (Query_Budget).Work_Units = 0);

      Flyology_Serde_Generator.Requests.Poison (Query_Budget);
      Flyology_Serde_Generator.Requests.Copy_Output_Path
        (Request, Query_Budget, Target, Written, Copied, Query_Error);
      pragma Assert
        (Flyology_Serde_Generator.Diagnostics.Code (Query_Error) =
           Flyology_Serde_Generator.Diagnostics.Invalid_Arguments);
      pragma Assert (Target = "?" and then Written = 73 and then Copied);
   end;

   declare
      Query_Budget : Flyology_Serde_Generator.Requests.Operation_Budget;
      Query_Error  : Flyology_Serde_Generator.Diagnostics.Diagnostic;
      Target       : String (1 .. Ada.Command_Line.Argument (1)'Length) := [others => '?'];
      Prior        : constant String := Target;
      Written      : Natural := 91;
      Copied       : Boolean := True;
   begin
      Flyology_Serde_Generator.Requests.Start_Budget (Limits (1, 1), Query_Budget);
      Flyology_Serde_Generator.Diagnostics.Clear (Query_Error);
      Flyology_Serde_Generator.Requests.Copy_Overlay_Path
        (Request, Query_Budget, Target, Written, Copied, Query_Error);
      pragma Assert
        (Flyology_Serde_Generator.Diagnostics.Code (Query_Error) =
           Flyology_Serde_Generator.Diagnostics.Resource_Exhausted);
      pragma Assert (Target = Prior and then Written = 91 and then Copied);
      pragma Assert (Flyology_Serde_Generator.Requests.Is_Poisoned (Query_Budget));
   end;

   Flyology_Serde_Generator.Generation.Generate (Request, Diagnostic);
   pragma Assert
     (Flyology_Serde_Generator.Diagnostics.Code (Diagnostic) =
        Flyology_Serde_Generator.Diagnostics.Type_IR_API_Unavailable);
   pragma Assert (Flyology_Serde_Generator.Diagnostics.Message (Diagnostic, 1)'Length = 1);
   pragma Assert
     (Flyology_Serde_Generator.Diagnostics.Code (Diagnostic) =
        Flyology_Serde_Generator.Diagnostics.Type_IR_API_Unavailable);

   Flyology_Serde_Generator.Requests.Build_Fixture
     ("ii", "o", "x", Limits (1, 1), Request, Diagnostic);
   pragma Assert (not Flyology_Serde_Generator.Requests.Is_Valid (Request));
   pragma Assert (Flyology_Serde_Generator.Requests.Has_Limits (Request));
   pragma Assert
     (Flyology_Serde_Generator.Diagnostics.Code (Diagnostic) =
        Flyology_Serde_Generator.Diagnostics.Resource_Exhausted);

   Flyology_Serde_Generator.Requests.Build_Fixture
     ("i" & ASCII.NUL, "o", "x", Overlay_Limits, Request, Diagnostic);
   pragma Assert (not Flyology_Serde_Generator.Requests.Is_Valid (Request));
   pragma Assert
     (Flyology_Serde_Generator.Diagnostics.Code (Diagnostic) =
        Flyology_Serde_Generator.Diagnostics.Invalid_Arguments);

   declare
      Opaque_Path  : constant String := "x" & Character'Val (16#E9#);
      Query_Budget : Flyology_Serde_Generator.Requests.Operation_Budget;
      Query_Error  : Flyology_Serde_Generator.Diagnostics.Diagnostic;
      Path_Length  : Natural := 0;
   begin
      Flyology_Serde_Generator.Requests.Build_Fixture
        (Opaque_Path, "o", "x", Overlay_Limits, Request, Diagnostic);
      pragma Assert (Flyology_Serde_Generator.Requests.Is_Valid (Request));
      Flyology_Serde_Generator.Requests.Start_Budget (Overlay_Limits, Query_Budget);
      Flyology_Serde_Generator.Diagnostics.Clear (Query_Error);
      Flyology_Serde_Generator.Requests.Read_Type_IR_Path_Length
        (Request, Query_Budget, Path_Length, Query_Error);
      declare
         Target  : String (3 .. 2 + Path_Length) := [others => '?'];
         Written : Natural := 0;
         Copied  : Boolean := False;
      begin
         Flyology_Serde_Generator.Requests.Copy_Type_IR_Path
           (Request, Query_Budget, Target, Written, Copied, Query_Error);
         pragma Assert (Copied and then Written = Path_Length and then Target = Opaque_Path);
      end;
   end;

   Flyology_Serde_Generator.Requests.Build_Fixture
     ("i", Ada.Command_Line.Argument (1), "x", Overlay_Limits, Request, Diagnostic);
   pragma Assert (Flyology_Serde_Generator.Requests.Is_Valid (Request));
end Scaffold_Tests;
