with Ada.Strings.Unbounded;
with Flyology_Serde_Generator.Diagnostics;

package Flyology_Serde_Generator.Requests is
   type Limit_Value is range 1 .. Long_Long_Integer'Last;

   type Generation_Limits is record
      Maximum_Path_Bytes              : Limit_Value;
      Maximum_Input_Bytes_Per_File    : Limit_Value;
      Maximum_Total_Input_Bytes       : Limit_Value;
      Maximum_Decoded_String_Bytes    : Limit_Value;
      Maximum_Number_Token_Bytes      : Limit_Value;
      Maximum_JSON_Nesting            : Limit_Value;
      Maximum_Object_Members          : Limit_Value;
      Maximum_Array_Elements          : Limit_Value;
      Maximum_Type_IR_Nodes           : Limit_Value;
      Maximum_Overlay_Nodes           : Limit_Value;
      Maximum_Rendered_Bytes_Per_File : Limit_Value;
      Maximum_Total_Rendered_Bytes    : Limit_Value;
      Maximum_Artifact_Files          : Limit_Value;
      Maximum_Diagnostics             : Limit_Value;
      Maximum_Diagnostic_Bytes        : Limit_Value;
      Maximum_Work_Units              : Limit_Value;
   end record;

   type Operation_Budget is limited private;

   procedure Start_Budget
     (Limits : Generation_Limits;
      Into   : out Operation_Budget);

   function Budget_Limits (Value : Operation_Budget) return Generation_Limits;

   procedure Charge_Input
     (Value    : in out Operation_Budget;
      Bytes    : Natural;
      Accepted : out Boolean);

   procedure Charge_Overlay_Node
     (Value    : in out Operation_Budget;
      Accepted : out Boolean);

   procedure Charge_Work
     (Value    : in out Operation_Budget;
      Units    : Natural;
      Accepted : out Boolean);

   type Used_Value is range 0 .. Long_Long_Integer'Last;

   type Budget_Usage is record
      Input_Bytes   : Used_Value;
      Overlay_Nodes : Used_Value;
      Work_Units    : Used_Value;
   end record;

   function Current_Usage (Value : Operation_Budget) return Budget_Usage;
   function Is_Poisoned (Value : Operation_Budget) return Boolean;
   procedure Poison (Value : in out Operation_Budget);

   type Generation_Request is limited private;

   procedure Build_Fixture
     (Type_IR_Path : String;
      Overlay_Path : String;
      Output_Path  : String;
      Limits       : Generation_Limits;
      Into         : out Generation_Request;
      Diagnostic   : out Flyology_Serde_Generator.Diagnostics.Diagnostic);

   function Is_Valid (Value : Generation_Request) return Boolean;
   function Has_Limits (Value : Generation_Request) return Boolean;
   function Operation_Limits (Value : Generation_Request) return Generation_Limits;

   --  This flag records a fixture request. It is not extraction or production authority.
   function Is_Fixture_Request (Value : Generation_Request) return Boolean;

   function Type_IR_Path (Value : Generation_Request) return String;
   function Overlay_Path (Value : Generation_Request) return String;
   function Output_Path (Value : Generation_Request) return String;

private
   subtype Budget_Count is Used_Value;

   type Operation_Budget is limited record
      Limits        : Generation_Limits := (others => 1);
      Input_Bytes   : Budget_Count := 0;
      Overlay_Nodes : Budget_Count := 0;
      Work_Units    : Budget_Count := 0;
      Failed        : Boolean := False;
   end record;

   type Generation_Request is limited record
      Valid        : Boolean := False;
      Type_IR      : Ada.Strings.Unbounded.Unbounded_String;
      Overlay      : Ada.Strings.Unbounded.Unbounded_String;
      Output       : Ada.Strings.Unbounded.Unbounded_String;
      Limits       : Generation_Limits := (others => 1);
      Limits_Set   : Boolean := False;
      Test_Fixture : Boolean := False;
   end record;
end Flyology_Serde_Generator.Requests;
