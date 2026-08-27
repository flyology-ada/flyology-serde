with Ada.Command_Line;
with Ada.Text_IO;
with Flyology_Serde_Generator.Diagnostics;
with Flyology_Serde_Generator.Lowered_Records;
with Flyology_Serde_Generator.Lowered_Records.Test_Fixtures;
with Flyology_Serde_Generator.Rendering;
with Flyology_Serde_Generator.Requests;

procedure Flyology_Serde_Generator.Production_Shape_Renderer_Tests is
   use type Flyology_Serde_Generator.Diagnostics.Error_Code;
   use type Flyology_Serde_Generator.Lowered_Records.Type_Node_Kind;
   use type Flyology_Serde_Generator.Requests.Used_Value;

   function Limits return Flyology_Serde_Generator.Requests.Generation_Limits
   is (Maximum_Path_Bytes              => 4_096,
       Maximum_Input_Bytes_Per_File    => 1_048_576,
       Maximum_Total_Input_Bytes       => 2_097_152,
       Maximum_Decoded_String_Bytes    => 4_096,
       Maximum_Number_Token_Bytes      => 32,
       Maximum_JSON_Nesting            => 8,
       Maximum_Object_Members          => 64,
       Maximum_Array_Elements          => 4_096,
       Maximum_Type_IR_Nodes           => 64,
       Maximum_Overlay_Nodes           => 64,
       Maximum_Rendered_Bytes_Per_File => 65_536,
       Maximum_Total_Rendered_Bytes    => 131_072,
       Maximum_Artifact_Files          => 2,
       Maximum_Diagnostics             => 16,
       Maximum_Diagnostic_Bytes        => 256,
       Maximum_Work_Units              => 262_144);

   procedure Write_Artifact
     (Value : Flyology_Serde_Generator.Rendering.Rendered_Artifacts;
      Kind  : Flyology_Serde_Generator.Rendering.Artifact_Kind;
      Root  : String)
   is
      Length  : constant Natural :=
        Flyology_Serde_Generator.Rendering.Payload_Length (Value, Kind);
      Buffer  : String (1 .. Length);
      Written : Natural := 0;
      Copied  : Boolean := False;
      File    : Ada.Text_IO.File_Type;
   begin
      Flyology_Serde_Generator.Rendering.Copy_Payload
        (Value, Kind, Buffer, Written, Copied);
      pragma Assert (Copied and then Written = Length);
      Ada.Text_IO.Create
        (File,
         Ada.Text_IO.Out_File,
         Root
         & "/"
         & Flyology_Serde_Generator.Rendering.File_Name (Value, Kind));
      Ada.Text_IO.Put (File, Buffer);
      Ada.Text_IO.Close (File);
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         raise;
   end Write_Artifact;

   function Model_Work
     (Value : Flyology_Serde_Generator.Lowered_Records.Model) return Natural
   is
      package Lowered renames Flyology_Serde_Generator.Lowered_Records;
      Members    : Natural :=
        Lowered.With_Unit_Count (Value)
        + Lowered.Type_Node_Count (Value)
        + Lowered.Field_Count (Value);
      Text_Bytes : Natural := Lowered.Output_Unit (Value)'Length;
   begin
      for Index in 1 .. Lowered.With_Unit_Count (Value) loop
         Text_Bytes := Text_Bytes + Lowered.With_Unit (Value, Index)'Length;
      end loop;
      for Node in 1 .. Lowered.Type_Node_Count (Value) loop
         Text_Bytes :=
           Text_Bytes
           + Lowered.Node_Ada_Type (Value, Node)'Length
           + Lowered.Node_Logical_Name (Value, Node)'Length;
         if Lowered.Node_Kind (Value, Node) = Lowered.Enumeration_Node then
            for Position in
              1 .. Lowered.Enumeration_Literal_Count (Value, Node)
            loop
               Members := Members + 1;
               Text_Bytes :=
                 Text_Bytes
                 + Lowered.Enumeration_Literal_Ada_Name
                     (Value, Node, Position)'Length
                 + Lowered.Enumeration_Literal_Primary_Name
                     (Value, Node, Position)'Length;
               for Alias in
                 1
                 .. Lowered.Enumeration_Literal_Alias_Count
                      (Value, Node, Position)
               loop
                  Members := Members + 1;
                  Text_Bytes :=
                    Text_Bytes
                    + Lowered.Enumeration_Literal_Alias_Name
                        (Value, Node, Position, Alias)'Length;
               end loop;
            end loop;
         end if;
      end loop;
      for Field in 1 .. Lowered.Field_Count (Value) loop
         Text_Bytes :=
           Text_Bytes
           + Lowered.Field_Ada_Component (Value, Field)'Length
           + Lowered.Field_Presentation_Name (Value, Field)'Length;
      end loop;
      return 1 + (Members + 1) * (Text_Bytes + Members + 1);
   end Model_Work;

   procedure Check_Malformed_Graph
     (Kind :
        Flyology_Serde_Generator
          .Lowered_Records
          .Test_Fixtures
          .Graph_Malformation)
   is
      package Fixtures renames
        Flyology_Serde_Generator.Lowered_Records.Test_Fixtures;
      Rejection_Budget     :
        Flyology_Serde_Generator.Requests.Operation_Budget;
      Rejection_Diagnostic : Flyology_Serde_Generator.Diagnostics.Diagnostic;
      Work                 : constant Natural :=
        Fixtures.Production_Shape_Work (Kind);
   begin
      Flyology_Serde_Generator.Requests.Start_Budget
        (Limits, Rejection_Budget);
      Flyology_Serde_Generator.Diagnostics.Clear (Rejection_Diagnostic);
      declare
         Rejected : constant Flyology_Serde_Generator.Lowered_Records.Model :=
           Fixtures.Production_Shapes
             (Rejection_Budget, Rejection_Diagnostic, Kind);
      begin
         pragma
           Assert
             (Flyology_Serde_Generator.Diagnostics.Code (Rejection_Diagnostic)
                = Flyology_Serde_Generator
                    .Diagnostics
                    .Unsupported_Lowered_Model);
         pragma
           Assert
             (not Flyology_Serde_Generator.Lowered_Records.Is_Valid
                    (Rejected));
         pragma
           Assert
             (not Flyology_Serde_Generator.Requests.Is_Poisoned
                    (Rejection_Budget));
         pragma
           Assert
             (Flyology_Serde_Generator.Requests.Current_Usage
                (Rejection_Budget)
                .Work_Units
                = Flyology_Serde_Generator.Requests.Used_Value (Work));
      end;
   end Check_Malformed_Graph;

   procedure Check_Injected_Failure
     (Failure  :
        Flyology_Serde_Generator.Lowered_Records.Test_Fixtures.Graph_Failure;
      Expected : Flyology_Serde_Generator.Diagnostics.Error_Code)
   is
      package Fixtures renames
        Flyology_Serde_Generator.Lowered_Records.Test_Fixtures;
      Failure_Budget     : Flyology_Serde_Generator.Requests.Operation_Budget;
      Failure_Diagnostic : Flyology_Serde_Generator.Diagnostics.Diagnostic;
      Work               : constant Natural :=
        Fixtures.Production_Shape_Work (Fixtures.Valid_Graph);
   begin
      pragma Assert (Fixtures.Live_Unpublished_Graphs = 0);
      Flyology_Serde_Generator.Requests.Start_Budget (Limits, Failure_Budget);
      Flyology_Serde_Generator.Diagnostics.Clear (Failure_Diagnostic);
      declare
         Rejected : constant Flyology_Serde_Generator.Lowered_Records.Model :=
           Fixtures.Production_Shapes
             (Failure_Budget, Failure_Diagnostic, Failure => Failure);
      begin
         pragma
           Assert
             (Flyology_Serde_Generator.Diagnostics.Code (Failure_Diagnostic)
                = Expected);
         pragma
           Assert
             (not Flyology_Serde_Generator.Lowered_Records.Is_Valid
                    (Rejected));
         pragma
           Assert
             (Flyology_Serde_Generator.Requests.Is_Poisoned (Failure_Budget));
         pragma
           Assert
             (Flyology_Serde_Generator.Requests.Current_Usage (Failure_Budget)
                .Work_Units
                = Flyology_Serde_Generator.Requests.Used_Value (Work));
         pragma Assert (Fixtures.Live_Unpublished_Graphs = 0);
      end;
   end Check_Injected_Failure;

   Budget     : aliased Flyology_Serde_Generator.Requests.Operation_Budget;
   Diagnostic : Flyology_Serde_Generator.Diagnostics.Diagnostic;
   Rendered   : Flyology_Serde_Generator.Rendering.Rendered_Artifacts;
begin
   pragma Assert (Ada.Command_Line.Argument_Count = 1);

   declare
      package Fixtures renames
        Flyology_Serde_Generator.Lowered_Records.Test_Fixtures;
      Work          : Natural := 0;
      Representable : Boolean := False;
   begin
      Fixtures.Compute_Graph_Work (0, 0, Work, Representable);
      pragma Assert (Representable and then Work = 2);
      Fixtures.Compute_Graph_Work (16, 237, Work, Representable);
      pragma Assert (Representable and then Work = 4_319);
      Fixtures.Compute_Graph_Work (0, Natural'Last - 2, Work, Representable);
      pragma Assert (Representable and then Work = Natural'Last);
      Fixtures.Compute_Graph_Work (0, Natural'Last - 1, Work, Representable);
      pragma Assert (not Representable and then Work = 0);
      Fixtures.Compute_Graph_Work (Natural'Last, 0, Work, Representable);
      pragma Assert (not Representable and then Work = 0);
   end;

   for Kind in
     Flyology_Serde_Generator
       .Lowered_Records
       .Test_Fixtures
       .Graph_Malformation'Succ
          (Flyology_Serde_Generator.Lowered_Records.Test_Fixtures.Valid_Graph)
     .. Flyology_Serde_Generator
          .Lowered_Records
          .Test_Fixtures
          .Graph_Malformation'Last
   loop
      Check_Malformed_Graph (Kind);
   end loop;

   Check_Injected_Failure
     (Flyology_Serde_Generator
        .Lowered_Records
        .Test_Fixtures
        .Allocation_Storage_Failure,
      Flyology_Serde_Generator.Diagnostics.Resource_Exhausted);
   Check_Injected_Failure
     (Flyology_Serde_Generator
        .Lowered_Records
        .Test_Fixtures
        .Post_Allocation_Storage_Failure,
      Flyology_Serde_Generator.Diagnostics.Internal_Error);
   Check_Injected_Failure
     (Flyology_Serde_Generator
        .Lowered_Records
        .Test_Fixtures
        .Post_Allocation_Internal_Failure,
      Flyology_Serde_Generator.Diagnostics.Internal_Error);
   Check_Injected_Failure
     (Flyology_Serde_Generator
        .Lowered_Records
        .Test_Fixtures
        .Post_Transfer_Internal_Failure,
      Flyology_Serde_Generator.Diagnostics.Internal_Error);

   declare
      package Fixtures renames
        Flyology_Serde_Generator.Lowered_Records.Test_Fixtures;
      Work                    : constant Natural :=
        Fixtures.Production_Shape_Work (Fixtures.Duplicate_Enumeration_Name);
      Denied_Limits           :
        Flyology_Serde_Generator.Requests.Generation_Limits := Limits;
      Denied_Budget           :
        Flyology_Serde_Generator.Requests.Operation_Budget;
      Latched_Budget          :
        Flyology_Serde_Generator.Requests.Operation_Budget;
      Poisoned_Budget         :
        Flyology_Serde_Generator.Requests.Operation_Budget;
      Latched_Poisoned_Budget :
        Flyology_Serde_Generator.Requests.Operation_Budget;
      Diagnostic              :
        Flyology_Serde_Generator.Diagnostics.Diagnostic;
   begin
      Denied_Limits.Maximum_Work_Units :=
        Flyology_Serde_Generator.Requests.Limit_Value (Work - 1);
      Flyology_Serde_Generator.Requests.Start_Budget
        (Denied_Limits, Denied_Budget);
      Flyology_Serde_Generator.Diagnostics.Clear (Diagnostic);
      declare
         Rejected : constant Flyology_Serde_Generator.Lowered_Records.Model :=
           Fixtures.Production_Shapes
             (Denied_Budget, Diagnostic, Fixtures.Duplicate_Enumeration_Name);
      begin
         pragma
           Assert
             (Flyology_Serde_Generator.Diagnostics.Code (Diagnostic)
                = Flyology_Serde_Generator.Diagnostics.Resource_Exhausted);
         pragma
           Assert
             (not Flyology_Serde_Generator.Lowered_Records.Is_Valid
                    (Rejected));
         pragma
           Assert
             (Flyology_Serde_Generator.Requests.Is_Poisoned (Denied_Budget));
         pragma
           Assert
             (Flyology_Serde_Generator.Requests.Current_Usage (Denied_Budget)
                .Work_Units
                = 0);
      end;

      Flyology_Serde_Generator.Requests.Start_Budget (Limits, Latched_Budget);
      Flyology_Serde_Generator.Diagnostics.Set
        (Diagnostic, Flyology_Serde_Generator.Diagnostics.Invalid_Arguments);
      declare
         Rejected : constant Flyology_Serde_Generator.Lowered_Records.Model :=
           Fixtures.Production_Shapes (Latched_Budget, Diagnostic);
      begin
         pragma
           Assert
             (Flyology_Serde_Generator.Diagnostics.Code (Diagnostic)
                = Flyology_Serde_Generator.Diagnostics.Invalid_Arguments);
         pragma
           Assert
             (not Flyology_Serde_Generator.Lowered_Records.Is_Valid
                    (Rejected));
         pragma
           Assert
             (Flyology_Serde_Generator.Requests.Current_Usage (Latched_Budget)
                .Work_Units
                = 0);
      end;

      Flyology_Serde_Generator.Requests.Start_Budget (Limits, Poisoned_Budget);
      Flyology_Serde_Generator.Requests.Poison (Poisoned_Budget);
      Flyology_Serde_Generator.Diagnostics.Clear (Diagnostic);
      declare
         Rejected : constant Flyology_Serde_Generator.Lowered_Records.Model :=
           Fixtures.Production_Shapes (Poisoned_Budget, Diagnostic);
      begin
         pragma
           Assert
             (Flyology_Serde_Generator.Diagnostics.Code (Diagnostic)
                = Flyology_Serde_Generator.Diagnostics.Resource_Exhausted);
         pragma
           Assert
             (not Flyology_Serde_Generator.Lowered_Records.Is_Valid
                    (Rejected));
         pragma
           Assert
             (Flyology_Serde_Generator.Requests.Current_Usage (Poisoned_Budget)
                .Work_Units
                = 0);
      end;

      Flyology_Serde_Generator.Requests.Start_Budget
        (Limits, Latched_Poisoned_Budget);
      Flyology_Serde_Generator.Requests.Poison (Latched_Poisoned_Budget);
      Flyology_Serde_Generator.Diagnostics.Set
        (Diagnostic, Flyology_Serde_Generator.Diagnostics.Invalid_Arguments);
      declare
         Rejected : constant Flyology_Serde_Generator.Lowered_Records.Model :=
           Fixtures.Production_Shapes (Latched_Poisoned_Budget, Diagnostic);
      begin
         pragma
           Assert
             (Flyology_Serde_Generator.Diagnostics.Code (Diagnostic)
                = Flyology_Serde_Generator.Diagnostics.Invalid_Arguments);
         pragma
           Assert
             (not Flyology_Serde_Generator.Lowered_Records.Is_Valid
                    (Rejected));
         pragma
           Assert
             (Flyology_Serde_Generator.Requests.Current_Usage
                (Latched_Poisoned_Budget)
                .Work_Units
                = 0);
      end;
   end;

   Flyology_Serde_Generator.Requests.Start_Budget (Limits, Budget);
   Flyology_Serde_Generator.Diagnostics.Clear (Diagnostic);
   declare
      Model : constant Flyology_Serde_Generator.Lowered_Records.Model :=
        Flyology_Serde_Generator
          .Lowered_Records
          .Test_Fixtures
          .Production_Shapes (Budget, Diagnostic);
   begin
      pragma
        Assert
          (Flyology_Serde_Generator.Diagnostics.Code (Diagnostic)
             = Flyology_Serde_Generator.Diagnostics.No_Error);
      pragma
        Assert (Flyology_Serde_Generator.Lowered_Records.Is_Valid (Model));
      pragma
        Assert
          (Flyology_Serde_Generator.Lowered_Records.Has_Type_Graph (Model));
      pragma
        Assert
          (Flyology_Serde_Generator.Lowered_Records.Type_Node_Count (Model)
             = 4);
      pragma
        Assert
          (Flyology_Serde_Generator.Lowered_Records.Node_Kind (Model, 1)
             = Flyology_Serde_Generator.Lowered_Records.Enumeration_Node);
      pragma
        Assert
          (Flyology_Serde_Generator.Lowered_Records.Node_Kind (Model, 3)
             = Flyology_Serde_Generator.Lowered_Records.Fixed_Array_Node);
      pragma
        Assert
          (Flyology_Serde_Generator.Lowered_Records.Array_Index_Node (Model, 3)
             = 1);
      pragma
        Assert
          (Flyology_Serde_Generator.Lowered_Records.Array_Element_Node
             (Model, 3)
             = 2);
      pragma
        Assert
          (Flyology_Serde_Generator.Lowered_Records.Root_Node (Model) = 4);

      declare
         Work  : constant Natural := 4_319;
         Usage : constant Flyology_Serde_Generator.Requests.Budget_Usage :=
           Flyology_Serde_Generator.Requests.Current_Usage (Budget);
      begin
         pragma Assert (Model_Work (Model) = Work);
         pragma
           Assert
             (Usage.Work_Units
                = Flyology_Serde_Generator.Requests.Used_Value (Work));

         declare
            Denied_Limits     :
              Flyology_Serde_Generator.Requests.Generation_Limits := Limits;
            Denied_Budget     :
              Flyology_Serde_Generator.Requests.Operation_Budget;
            Denied_Diagnostic :
              Flyology_Serde_Generator.Diagnostics.Diagnostic;
         begin
            Denied_Limits.Maximum_Work_Units :=
              Flyology_Serde_Generator.Requests.Limit_Value (Work - 1);
            Flyology_Serde_Generator.Requests.Start_Budget
              (Denied_Limits, Denied_Budget);
            Flyology_Serde_Generator.Diagnostics.Clear (Denied_Diagnostic);
            declare
               Rejected :
                 constant Flyology_Serde_Generator.Lowered_Records.Model :=
                   Flyology_Serde_Generator
                     .Lowered_Records
                     .Test_Fixtures
                     .Production_Shapes (Denied_Budget, Denied_Diagnostic);
            begin
               pragma
                 Assert
                   (Flyology_Serde_Generator.Diagnostics.Code
                      (Denied_Diagnostic)
                      = Flyology_Serde_Generator
                          .Diagnostics
                          .Resource_Exhausted);
               pragma
                 Assert
                   (not Flyology_Serde_Generator.Lowered_Records.Is_Valid
                          (Rejected));
               pragma
                 Assert
                   (Flyology_Serde_Generator.Requests.Is_Poisoned
                      (Denied_Budget));
               pragma
                 Assert
                   (Flyology_Serde_Generator.Requests.Current_Usage
                      (Denied_Budget)
                      .Work_Units
                      = 0);
            end;
         end;

         declare
            Denied_Limits     :
              Flyology_Serde_Generator.Requests.Generation_Limits := Limits;
            Denied_Budget     :
              aliased Flyology_Serde_Generator.Requests.Operation_Budget;
            Denied_Diagnostic :
              Flyology_Serde_Generator.Diagnostics.Diagnostic;
            Denied_Render     :
              Flyology_Serde_Generator.Rendering.Rendered_Artifacts;
         begin
            Denied_Limits.Maximum_Work_Units :=
              Flyology_Serde_Generator.Requests.Limit_Value (2 * Work - 1);
            Flyology_Serde_Generator.Requests.Start_Budget
              (Denied_Limits, Denied_Budget);
            Flyology_Serde_Generator.Diagnostics.Clear (Denied_Diagnostic);
            declare
               Candidate :
                 constant Flyology_Serde_Generator.Lowered_Records.Model :=
                   Flyology_Serde_Generator
                     .Lowered_Records
                     .Test_Fixtures
                     .Production_Shapes (Denied_Budget, Denied_Diagnostic);
            begin
               pragma
                 Assert
                   (Flyology_Serde_Generator.Lowered_Records.Is_Valid
                      (Candidate));
               Flyology_Serde_Generator.Rendering.Render_Payload
                 (Candidate, Denied_Budget, Denied_Render, Denied_Diagnostic);
               pragma
                 Assert
                   (Flyology_Serde_Generator.Diagnostics.Code
                      (Denied_Diagnostic)
                      = Flyology_Serde_Generator
                          .Diagnostics
                          .Resource_Exhausted);
               pragma
                 Assert
                   (not Flyology_Serde_Generator.Rendering.Is_Valid
                          (Denied_Render));
               pragma
                 Assert
                   (Flyology_Serde_Generator.Requests.Is_Poisoned
                      (Denied_Budget));
               pragma
                 Assert
                   (Flyology_Serde_Generator.Requests.Current_Usage
                      (Denied_Budget)
                      .Work_Units
                      = Flyology_Serde_Generator.Requests.Used_Value (Work));
            end;
         end;
      end;

      Flyology_Serde_Generator.Rendering.Render_Payload
        (Model, Budget, Rendered, Diagnostic);
      pragma
        Assert
          (Flyology_Serde_Generator.Diagnostics.Code (Diagnostic)
             = Flyology_Serde_Generator.Diagnostics.No_Error);
      pragma Assert (Flyology_Serde_Generator.Rendering.Is_Valid (Rendered));

      declare
         Length  : constant Natural :=
           Flyology_Serde_Generator.Rendering.Payload_Length
             (Rendered, Flyology_Serde_Generator.Rendering.Specification);
         Exact   : String (Positive'Last - Length + 1 .. Positive'Last) :=
           [others => '#'];
         Small   : String (Positive'Last .. Positive'Last) := [others => '#'];
         Written : Natural := 7;
         Copied  : Boolean := False;
      begin
         Flyology_Serde_Generator.Rendering.Copy_Payload
           (Rendered,
            Flyology_Serde_Generator.Rendering.Specification,
            Exact,
            Written,
            Copied);
         pragma Assert (Copied and then Written = Length);
         pragma Assert (Exact (Exact'Last) = ASCII.LF);

         Written := 7;
         Flyology_Serde_Generator.Rendering.Copy_Payload
           (Rendered,
            Flyology_Serde_Generator.Rendering.Specification,
            Small,
            Written,
            Copied);
         pragma Assert (not Copied and then Written = 7);
         pragma Assert (Small = "#");
      end;

      declare
         Work              : constant Natural := 4_319;
         Denied_Limits     :
           Flyology_Serde_Generator.Requests.Generation_Limits := Limits;
         Denied_Budget     :
           aliased Flyology_Serde_Generator.Requests.Operation_Budget;
         Prior_Spec_Length : constant Natural :=
           Flyology_Serde_Generator.Rendering.Payload_Length
             (Rendered, Flyology_Serde_Generator.Rendering.Specification);
         Prior_Body_Length : constant Natural :=
           Flyology_Serde_Generator.Rendering.Payload_Length
             (Rendered, Flyology_Serde_Generator.Rendering.Package_Body);
      begin
         Denied_Limits.Maximum_Work_Units :=
           Flyology_Serde_Generator.Requests.Limit_Value (Work - 1);
         Flyology_Serde_Generator.Requests.Start_Budget
           (Denied_Limits, Denied_Budget);
         Flyology_Serde_Generator.Rendering.Render_Payload
           (Model, Denied_Budget, Rendered, Diagnostic);
         pragma
           Assert
             (Flyology_Serde_Generator.Diagnostics.Code (Diagnostic)
                = Flyology_Serde_Generator.Diagnostics.Resource_Exhausted);
         pragma
           Assert (Flyology_Serde_Generator.Rendering.Is_Valid (Rendered));
         pragma
           Assert
             (Flyology_Serde_Generator.Rendering.Payload_Length
                (Rendered, Flyology_Serde_Generator.Rendering.Specification)
                = Prior_Spec_Length);
         pragma
           Assert
             (Flyology_Serde_Generator.Rendering.Payload_Length
                (Rendered, Flyology_Serde_Generator.Rendering.Package_Body)
                = Prior_Body_Length);
      end;

      declare
         Poisoned_Budget     :
           aliased Flyology_Serde_Generator.Requests.Operation_Budget;
         Poisoned_Diagnostic : Flyology_Serde_Generator.Diagnostics.Diagnostic;
         Prior_Spec_Length   : constant Natural :=
           Flyology_Serde_Generator.Rendering.Payload_Length
             (Rendered, Flyology_Serde_Generator.Rendering.Specification);
         Prior_Body_Length   : constant Natural :=
           Flyology_Serde_Generator.Rendering.Payload_Length
             (Rendered, Flyology_Serde_Generator.Rendering.Package_Body);
      begin
         Flyology_Serde_Generator.Requests.Start_Budget
           (Limits, Poisoned_Budget);
         Flyology_Serde_Generator.Requests.Poison (Poisoned_Budget);
         Flyology_Serde_Generator.Diagnostics.Clear (Poisoned_Diagnostic);
         Flyology_Serde_Generator.Rendering.Render_Payload
           (Model, Poisoned_Budget, Rendered, Poisoned_Diagnostic);
         pragma
           Assert
             (Flyology_Serde_Generator.Diagnostics.Code (Poisoned_Diagnostic)
                = Flyology_Serde_Generator.Diagnostics.Resource_Exhausted);
         pragma
           Assert (Flyology_Serde_Generator.Rendering.Is_Valid (Rendered));
         pragma
           Assert
             (Flyology_Serde_Generator.Rendering.Payload_Length
                (Rendered, Flyology_Serde_Generator.Rendering.Specification)
                = Prior_Spec_Length);
         pragma
           Assert
             (Flyology_Serde_Generator.Rendering.Payload_Length
                (Rendered, Flyology_Serde_Generator.Rendering.Package_Body)
                = Prior_Body_Length);
         pragma
           Assert
             (Flyology_Serde_Generator.Requests.Current_Usage (Poisoned_Budget)
                .Work_Units
                = 0);
      end;

      Write_Artifact
        (Rendered,
         Flyology_Serde_Generator.Rendering.Specification,
         Ada.Command_Line.Argument (1));
      Write_Artifact
        (Rendered,
         Flyology_Serde_Generator.Rendering.Package_Body,
         Ada.Command_Line.Argument (1));
   end;
end Flyology_Serde_Generator.Production_Shape_Renderer_Tests;
