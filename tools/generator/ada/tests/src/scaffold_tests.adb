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
   begin
      Flyology_Serde_Generator.Requests.Start_Budget (Overlay_Limits, Budget);
      Flyology_Serde_Generator.Overlays.Load_Checked
        (Ada.Command_Line.Argument (1), Budget, Overlay, Diagnostic);
      pragma Assert
        (Flyology_Serde_Generator.Diagnostics.Code (Diagnostic) =
           Flyology_Serde_Generator.Diagnostics.No_Error);
      pragma Assert (Flyology_Serde_Generator.Overlays.Is_Valid (Overlay));
      pragma Assert (Flyology_Serde_Generator.Overlays.Is_Fixture_Only (Overlay));
      pragma Assert (Flyology_Serde_Generator.Overlays.Output_Unit (Overlay) = "Flyology.Generated");
      pragma Assert (Flyology_Serde_Generator.Overlays.With_Unit_Count (Overlay) = 1);
      pragma Assert (Flyology_Serde_Generator.Overlays.With_Unit (Overlay, 1) = "Wire_Shape");
      pragma Assert (Flyology_Serde_Generator.Overlays.Field_Count (Overlay) = 3);
      pragma Assert
        (Flyology_Serde_Generator.Overlays.Field_Presentation_Name (Overlay, 2) = "signed");

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
         pragma Assert (Flyology_Serde_Generator.Overlays.Output_Unit (Overlay) = "Flyology.Generated");
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
         pragma Assert (Flyology_Serde_Generator.Overlays.Output_Unit (Overlay) = "Flyology.Generated");
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

   Flyology_Serde_Generator.Requests.Build_Fixture
     ("i", Ada.Command_Line.Argument (1), "x", Overlay_Limits, Request, Diagnostic);
   pragma Assert (Flyology_Serde_Generator.Requests.Is_Valid (Request));
end Scaffold_Tests;
