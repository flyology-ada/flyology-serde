package body Flyology_Serde_Generator.Requests is
   use Ada.Strings.Unbounded;

   function Fits
     (Current : Budget_Count;
      Added   : Natural;
      Maximum : Limit_Value) return Boolean
   is
     (Current <= Budget_Count (Maximum)
      and then Budget_Count (Added) <= Budget_Count (Maximum) - Current);

   procedure Start_Budget
     (Limits : Generation_Limits;
      Into   : out Operation_Budget)
   is
   begin
      Into.Limits := Limits;
      Into.Input_Bytes := 0;
      Into.Overlay_Nodes := 0;
      Into.Rendered_Bytes := 0;
      Into.Artifact_Files := 0;
      Into.Work_Units := 0;
      Into.Failed := False;
   end Start_Budget;

   function Budget_Limits (Value : Operation_Budget) return Generation_Limits is
     (Value.Limits);

   procedure Charge_Input
     (Value    : in out Operation_Budget;
      Bytes    : Natural;
      Accepted : out Boolean)
   is
   begin
      Accepted :=
        not Value.Failed
        and then Fits (Value.Input_Bytes, Bytes, Value.Limits.Maximum_Total_Input_Bytes);
      if Accepted then
         Value.Input_Bytes := Value.Input_Bytes + Budget_Count (Bytes);
      else
         Value.Failed := True;
      end if;
   end Charge_Input;

   procedure Charge_Overlay_Node
     (Value    : in out Operation_Budget;
      Accepted : out Boolean)
   is
   begin
      Accepted :=
        not Value.Failed
        and then Fits (Value.Overlay_Nodes, 1, Value.Limits.Maximum_Overlay_Nodes);
      if Accepted then
         Value.Overlay_Nodes := Value.Overlay_Nodes + 1;
      else
         Value.Failed := True;
      end if;
   end Charge_Overlay_Node;

   procedure Charge_Work
     (Value    : in out Operation_Budget;
      Units    : Natural;
      Accepted : out Boolean)
   is
   begin
      Accepted :=
        not Value.Failed
        and then Fits (Value.Work_Units, Units, Value.Limits.Maximum_Work_Units);
      if Accepted then
         Value.Work_Units := Value.Work_Units + Budget_Count (Units);
      else
         Value.Failed := True;
      end if;
   end Charge_Work;

   procedure Start_Rendered_Artifact
     (Value    : in out Operation_Budget;
      Accepted : out Boolean)
   is
   begin
      Accepted :=
        not Value.Failed
        and then Fits (Value.Artifact_Files, 1, Value.Limits.Maximum_Artifact_Files);
      if Accepted then
         Value.Artifact_Files := Value.Artifact_Files + 1;
      else
         Value.Failed := True;
      end if;
   end Start_Rendered_Artifact;

   procedure Charge_Rendered_Chunk
     (Value    : in out Operation_Budget;
      File_Bytes : Natural;
      Bytes    : Natural;
      Accepted : out Boolean)
   is
   begin
      Accepted :=
        not Value.Failed
        and then Budget_Count (File_Bytes) <=
          Budget_Count (Value.Limits.Maximum_Rendered_Bytes_Per_File)
        and then Fits
          (Budget_Count (File_Bytes), Bytes, Value.Limits.Maximum_Rendered_Bytes_Per_File)
        and then Fits (Value.Rendered_Bytes, Bytes, Value.Limits.Maximum_Total_Rendered_Bytes)
        and then Fits (Value.Work_Units, Bytes, Value.Limits.Maximum_Work_Units);
      if Accepted then
         Value.Rendered_Bytes := Value.Rendered_Bytes + Budget_Count (Bytes);
         Value.Work_Units := Value.Work_Units + Budget_Count (Bytes);
      else
         Value.Failed := True;
      end if;
   end Charge_Rendered_Chunk;

   function Current_Usage (Value : Operation_Budget) return Budget_Usage is
     (Input_Bytes    => Value.Input_Bytes,
      Overlay_Nodes  => Value.Overlay_Nodes,
      Rendered_Bytes => Value.Rendered_Bytes,
      Artifact_Files => Value.Artifact_Files,
      Work_Units     => Value.Work_Units);

   function Is_Poisoned (Value : Operation_Budget) return Boolean is
     (Value.Failed);

   procedure Poison (Value : in out Operation_Budget) is
   begin
      Value.Failed := True;
   exception
      when others =>
         null;
   end Poison;

   function Fits_Path
     (Value  : String;
      Limits : Generation_Limits) return Boolean
   is
     (Value'Length > 0
      and then (for all Item of Value => Item /= ASCII.NUL)
      and then Limit_Value (Value'Length) <= Limits.Maximum_Path_Bytes);

   procedure Build_Fixture
     (Type_IR_Path : String;
      Overlay_Path : String;
      Output_Path  : String;
      Limits       : Generation_Limits;
      Into         : out Generation_Request;
      Diagnostic   : out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
      use Flyology_Serde_Generator.Diagnostics;
   begin
      Into.Valid := False;
      Into.Type_IR := Null_Unbounded_String;
      Into.Overlay := Null_Unbounded_String;
      Into.Output := Null_Unbounded_String;
      Into.Limits := Limits;
      Into.Limits_Set := True;
      Into.Test_Fixture := False;
      Clear (Diagnostic);

      if Type_IR_Path'Length = 0
        or else Overlay_Path'Length = 0
        or else Output_Path'Length = 0
        or else (for some Item of Type_IR_Path => Item = ASCII.NUL)
        or else (for some Item of Overlay_Path => Item = ASCII.NUL)
        or else (for some Item of Output_Path => Item = ASCII.NUL)
      then
         Set (Diagnostic, Invalid_Arguments);
      elsif not Fits_Path (Type_IR_Path, Limits)
        or else not Fits_Path (Overlay_Path, Limits)
        or else not Fits_Path (Output_Path, Limits)
      then
         Set (Diagnostic, Resource_Exhausted);
      else
         Into.Type_IR := To_Unbounded_String (Type_IR_Path);
         Into.Overlay := To_Unbounded_String (Overlay_Path);
         Into.Output := To_Unbounded_String (Output_Path);
         Into.Limits := Limits;
         Into.Test_Fixture := True;
         Into.Valid := True;
      end if;
   exception
      when Storage_Error =>
         Into.Valid := False;
         Into.Type_IR := Null_Unbounded_String;
         Into.Overlay := Null_Unbounded_String;
         Into.Output := Null_Unbounded_String;
         Set (Diagnostic, Resource_Exhausted);
      when others =>
         Into.Valid := False;
         Into.Type_IR := Null_Unbounded_String;
         Into.Overlay := Null_Unbounded_String;
         Into.Output := Null_Unbounded_String;
         if Code (Diagnostic) = No_Error then
            Set (Diagnostic, Internal_Error);
         end if;
   end Build_Fixture;

   function Is_Valid (Value : Generation_Request) return Boolean is
     (Value.Valid);

   function Has_Limits (Value : Generation_Request) return Boolean is
     (Value.Limits_Set);

   function Operation_Limits (Value : Generation_Request) return Generation_Limits is
     (Value.Limits);

   function Is_Fixture_Request (Value : Generation_Request) return Boolean is
     (Value.Test_Fixture);

   function Type_IR_Path (Value : Generation_Request) return String is
     (To_String (Value.Type_IR));

   function Overlay_Path (Value : Generation_Request) return String is
     (To_String (Value.Overlay));

   function Output_Path (Value : Generation_Request) return String is
     (To_String (Value.Output));
end Flyology_Serde_Generator.Requests;
