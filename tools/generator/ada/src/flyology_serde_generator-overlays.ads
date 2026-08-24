with Ada.Finalization;
with Flyology_Serde_Generator.Diagnostics;
with Flyology_Serde_Generator.Requests;

package Flyology_Serde_Generator.Overlays is
   type Serialization_Limits is record
      Maximum_Byte_Length     : Natural;
      Maximum_Container_Items : Natural;
      Maximum_Logical_Events  : Natural;
      Maximum_Nesting_Depth   : Natural;
      Maximum_Text_Length     : Natural;
   end record;

   type Overlay_Document is limited private;

   procedure Load_Checked
     (Path       : String;
      Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
      Into       : in out Overlay_Document;
      Diagnostic : out Flyology_Serde_Generator.Diagnostics.Diagnostic);

   procedure Decode_Checked
     (Source     : String;
      Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
      Into       : in out Overlay_Document;
      Diagnostic : out Flyology_Serde_Generator.Diagnostics.Diagnostic);

   function Is_Valid (Value : Overlay_Document) return Boolean;
   function Is_Fixture_Only (Value : Overlay_Document) return Boolean;
   function Output_Unit (Value : Overlay_Document) return String;
   function Type_IR_Commit (Value : Overlay_Document) return String;
   function Type_IR_Semantic_Fingerprint (Value : Overlay_Document) return String;
   function Type_IR_Source_SHA256 (Value : Overlay_Document) return String;
   function Source_SHA256 (Value : Overlay_Document) return String;
   function Runtime_Limits (Value : Overlay_Document) return Serialization_Limits;

   function With_Unit_Count (Value : Overlay_Document) return Natural;
   function With_Unit (Value : Overlay_Document; Index : Positive) return String;

   function Record_Ada_Type (Value : Overlay_Document) return String;
   function Record_Declaration_ID (Value : Overlay_Document) return String;
   function Record_Logical_Type_Name (Value : Overlay_Document) return String;
   function Field_Count (Value : Overlay_Document) return Natural;
   function Field_Ada_Component (Value : Overlay_Document; Index : Positive) return String;
   function Field_Ada_Type (Value : Overlay_Document; Index : Positive) return String;
   function Field_Component_ID (Value : Overlay_Document; Index : Positive) return String;
   function Field_Presentation_Name (Value : Overlay_Document; Index : Positive) return String;

private
   type Overlay_Data;
   type Overlay_Data_Access is access Overlay_Data;

   type Overlay_Document is limited new Ada.Finalization.Limited_Controlled with record
      Data : Overlay_Data_Access := null;
   end record;

   overriding procedure Finalize (Value : in out Overlay_Document);
end Flyology_Serde_Generator.Overlays;
