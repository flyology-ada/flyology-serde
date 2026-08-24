with Ada.Finalization;
with Flyology_Serde_Generator.Diagnostics;
with Flyology_Serde_Generator.Lowered_Records;
with Flyology_Serde_Generator.Requests;

package Flyology_Serde_Generator.Rendering is
   type Artifact_Kind is (Specification, Package_Body);
   type Rendered_Artifacts is limited private;

   procedure Render_Payload
     (Value      : Flyology_Serde_Generator.Lowered_Records.Model;
      Budget     : aliased in out Flyology_Serde_Generator.Requests.Operation_Budget;
      Into       : in out Rendered_Artifacts;
      Diagnostic : out Flyology_Serde_Generator.Diagnostics.Diagnostic);

   function Is_Valid (Value : Rendered_Artifacts) return Boolean;
   function Artifact_Count (Value : Rendered_Artifacts) return Natural;
   function File_Name (Value : Rendered_Artifacts; Kind : Artifact_Kind) return String
   with Pre => Is_Valid (Value);
   function Payload_Length (Value : Rendered_Artifacts; Kind : Artifact_Kind) return Natural
   with Pre => Is_Valid (Value);

   procedure Copy_Payload
     (Value   : Rendered_Artifacts;
      Kind    : Artifact_Kind;
      Into    : in out String;
      Written : in out Natural;
      Copied  : out Boolean)
   with Pre => Is_Valid (Value);
   --  On success, Written is a count and bytes start at Into'First. If Into is
   --  too small, Copied is False and Into and Written remain unchanged.

private
   type Artifact_Data;
   type Artifact_Data_Access is access Artifact_Data;

   type Rendered_Artifacts is limited new Ada.Finalization.Limited_Controlled with record
      Data : Artifact_Data_Access := null;
   end record;

   overriding procedure Finalize (Value : in out Rendered_Artifacts);
end Flyology_Serde_Generator.Rendering;
