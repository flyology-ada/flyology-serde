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
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
      return Model
   with Pre => Flyology_Serde_Generator.Overlays.Is_Valid (Overlay);

   function Malformed (Kind : Malformation) return Model;

   type Line_Boundary is (Signed_Component_Line, Presentation_Line);
   function Boundary (Kind : Line_Boundary; Exceeds : Boolean) return Model;

   type Graph_Malformation is
     (Valid_Graph,
      Structure_Invalid,
      Self_Array_Index,
      Forward_Array_Index,
      Disconnected_Node,
      Duplicate_Enumeration_Name,
      Runtime_Unit_Collision,
      Missing_Defining_With,
      Redirected_Defining_With,
      Unused_With_Unit,
      Ignored_Array_Logical_Name,
      Overlong_Generated_Line);

   type Graph_Failure is
     (No_Failure,
      Allocation_Storage_Failure,
      Post_Allocation_Storage_Failure,
      Post_Allocation_Internal_Failure,
      Post_Transfer_Internal_Failure);

   function Production_Shape_Work (Kind : Graph_Malformation) return Natural;

   procedure Compute_Graph_Work
     (Members       : Natural;
      Text_Bytes    : Natural;
      Work          : out Natural;
      Representable : out Boolean);

   function Production_Shapes
     (Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic;
      Kind       : Graph_Malformation := Valid_Graph;
      Failure    : Graph_Failure := No_Failure) return Model;

   function Live_Unpublished_Graphs return Natural;
end Flyology_Serde_Generator.Lowered_Records.Test_Fixtures;
