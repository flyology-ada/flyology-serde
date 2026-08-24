with Ada.Command_Line;
with Ada.Text_IO;

package body Flyology_Serde_Generator.CLI is
   procedure Parse
     (Result     : out Parse_Result;
      Request    : out Flyology_Serde_Generator.Requests.Generation_Request;
      Diagnostic : out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
      use type Flyology_Serde_Generator.Diagnostics.Error_Code;

      Type_IR_Index : Natural := 0;
      Overlay_Index : Natural := 0;
      Output_Index  : Natural := 0;
      Limits_Index  : Natural := 0;
      Fixture_Mode  : Boolean := False;
      Index         : Positive := 1;
      Parsed_Limits : Flyology_Serde_Generator.Requests.Generation_Limits := (others => 1);

      procedure Fail (Message : String) is
         pragma Unreferenced (Message);
      begin
         Result := Failed;
         Flyology_Serde_Generator.Diagnostics.Set
           (Diagnostic,
            Flyology_Serde_Generator.Diagnostics.Invalid_Arguments);
      end Fail;

      function Next_Value (Option : String) return Natural is
      begin
         if Index = Ada.Command_Line.Argument_Count then
            Fail (Option & " requires a value");
            return 0;
         end if;

         Index := Index + 1;
         return Index;
      end Next_Value;

      procedure Parse_Limits (Text : String; Valid : out Boolean) is
         use Flyology_Serde_Generator.Requests;

         First  : Natural := 0;
         Field  : Natural := 0;

         procedure Assign (Index : Positive; Value : Limit_Value) is
         begin
            case Index is
               when 1  => Parsed_Limits.Maximum_Path_Bytes := Value;
               when 2  => Parsed_Limits.Maximum_Input_Bytes_Per_File := Value;
               when 3  => Parsed_Limits.Maximum_Total_Input_Bytes := Value;
               when 4  => Parsed_Limits.Maximum_Decoded_String_Bytes := Value;
               when 5  => Parsed_Limits.Maximum_Number_Token_Bytes := Value;
               when 6  => Parsed_Limits.Maximum_JSON_Nesting := Value;
               when 7  => Parsed_Limits.Maximum_Object_Members := Value;
               when 8  => Parsed_Limits.Maximum_Array_Elements := Value;
               when 9  => Parsed_Limits.Maximum_Type_IR_Nodes := Value;
               when 10 => Parsed_Limits.Maximum_Overlay_Nodes := Value;
               when 11 => Parsed_Limits.Maximum_Rendered_Bytes_Per_File := Value;
               when 12 => Parsed_Limits.Maximum_Total_Rendered_Bytes := Value;
               when 13 => Parsed_Limits.Maximum_Artifact_Files := Value;
               when 14 => Parsed_Limits.Maximum_Diagnostics := Value;
               when 15 => Parsed_Limits.Maximum_Diagnostic_Bytes := Value;
               when 16 => Parsed_Limits.Maximum_Work_Units := Value;
               when others =>
                  raise Constraint_Error;
            end case;
         end Assign;
      begin
         Valid := False;
         if Text'Length = 0 or else Text'Length > 512 then
            return;
         end if;
         for Offset in 0 .. Text'Length loop
            if Offset = Text'Length
              or else Text (Text'First + Integer (Offset)) = ','
            then
               Field := Field + 1;
               if First = Offset or else Field > 16 then
                  return;
               end if;
               Assign
                 (Field,
                  Limit_Value'Value
                    (Text
                       (Text'First + Integer (First) ..
                        Text'First + Integer (Offset) - 1)));
               First := Offset + 1;
            end if;
         end loop;
         Valid := Field = 16;
      exception
         when Constraint_Error =>
            Valid := False;
      end Parse_Limits;
   begin
      Result := Parsed;
      Flyology_Serde_Generator.Diagnostics.Clear (Diagnostic);

      while Index <= Ada.Command_Line.Argument_Count and then Result = Parsed loop
         declare
            Argument : constant String := Ada.Command_Line.Argument (Index);
         begin
            if Argument = "--help" or else Argument = "-h" then
               Result := Help_Requested;
            elsif Argument = "--version" then
               Result := Version_Requested;
            elsif Argument = "--type-ir" then
               if Type_IR_Index /= 0 then
                  Fail ("--type-ir may be supplied only once");
               else
                  Type_IR_Index := Next_Value (Argument);
               end if;
            elsif Argument = "--overlay" then
               if Overlay_Index /= 0 then
                  Fail ("--overlay may be supplied only once");
               else
                  Overlay_Index := Next_Value (Argument);
               end if;
            elsif Argument = "--output" then
               if Output_Index /= 0 then
                  Fail ("--output may be supplied only once");
               else
                  Output_Index := Next_Value (Argument);
               end if;
            elsif Argument = "--limits" then
               if Limits_Index /= 0 then
                  Fail ("--limits may be supplied only once");
               else
                  Limits_Index := Next_Value (Argument);
               end if;
            elsif Argument = "--test-fixture-shape" then
               if Fixture_Mode then
                  Fail ("--test-fixture-shape may be supplied only once");
               else
                  Fixture_Mode := True;
               end if;
            else
               Fail ("unknown argument");
            end if;
         end;
         Index := Index + 1;
      end loop;

      if Result = Parsed then
         if Type_IR_Index = 0 then
            Fail ("--type-ir is required");
         elsif Overlay_Index = 0 then
            Fail ("--overlay is required");
         elsif Output_Index = 0 then
            Fail ("--output is required");
         elsif Limits_Index = 0 then
            Fail ("--limits is required");
         elsif not Fixture_Mode then
            Fail ("persisted Type IR generation requires --test-fixture-shape");
         else
            declare
               Limits_Valid : Boolean;
            begin
               Parse_Limits (Ada.Command_Line.Argument (Limits_Index), Limits_Valid);
               if not Limits_Valid then
                  Fail ("--limits requires sixteen positive decimal values");
               else
                  Flyology_Serde_Generator.Requests.Build_Fixture
                    (Ada.Command_Line.Argument (Type_IR_Index),
                     Ada.Command_Line.Argument (Overlay_Index),
                     Ada.Command_Line.Argument (Output_Index),
                     Parsed_Limits,
                     Request,
                     Diagnostic);
                  if Flyology_Serde_Generator.Diagnostics.Code (Diagnostic) /=
                    Flyology_Serde_Generator.Diagnostics.No_Error
                  then
                     Result := Failed;
                  end if;
               end if;
            end;
         end if;
      end if;
   end Parse;

   procedure Print_Usage is
   begin
      Ada.Text_IO.Put_Line
        ("usage: flyology_serde_generate --type-ir PATH --overlay PATH --output PATH " &
         "--limits V1,...,V16 --test-fixture-shape");
   end Print_Usage;

   procedure Print_Version is
   begin
      Ada.Text_IO.Put_Line (Flyology_Serde_Generator.Generator_Version);
   end Print_Version;
end Flyology_Serde_Generator.CLI;
