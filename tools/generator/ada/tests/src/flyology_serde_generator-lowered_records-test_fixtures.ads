with Flyology_Serde_Generator.Diagnostics;
with Flyology_Serde_Generator.Overlays;
with Flyology_Serde_Generator.Requests;

package Flyology_Serde_Generator.Lowered_Records.Test_Fixtures is
   type Malformation is
     (Invalid_Output_Unit,
      Duplicate_With_Unit,
      Duplicate_Presentation_Name,
      Duplicate_Ada_Component,
      Invalid_Field_Ada_Type,
      Invalid_Logical_Name,
      Overlong_Presentation_Name,
      Invalid_Runtime_Limits,
      No_Fields,
      Too_Many_Fields);

   function Lower_Wire_Record
     (Overlay    : Flyology_Serde_Generator.Overlays.Overlay_Document;
      Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic) return Model
   with Pre => Flyology_Serde_Generator.Overlays.Is_Valid (Overlay);

   function Malformed (Kind : Malformation) return Model;

   type Line_Boundary is (Signed_Component_Line, Presentation_Line);
   function Boundary (Kind : Line_Boundary; Exceeds : Boolean) return Model;
end Flyology_Serde_Generator.Lowered_Records.Test_Fixtures;
