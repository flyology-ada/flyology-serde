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

   procedure Read_Fixture_Only
     (Value      : Overlay_Document;
      Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
      Result     : in out Boolean;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   with Pre => Is_Valid (Value);

   procedure Read_Runtime_Limits
     (Value      : Overlay_Document;
      Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
      Result     : in out Serialization_Limits;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   with Pre => Is_Valid (Value);

   procedure Read_With_Unit_Count
     (Value      : Overlay_Document;
      Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
      Result     : in out Natural;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   with Pre => Is_Valid (Value);

   procedure Read_Field_Count
     (Value      : Overlay_Document;
      Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
      Result     : in out Natural;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   with Pre => Is_Valid (Value);

   procedure Read_Output_Unit_Length
     (Value      : Overlay_Document;
      Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
      Length     : in out Natural;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   with Pre => Is_Valid (Value);

   procedure Copy_Output_Unit
     (Value      : Overlay_Document;
      Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
      Into       : in out String;
      Written    : in out Natural;
      Copied     : in out Boolean;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   with Pre => Is_Valid (Value);

   procedure Read_Type_IR_Commit_Length
     (Value      : Overlay_Document;
      Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
      Length     : in out Natural;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   with Pre => Is_Valid (Value);

   procedure Copy_Type_IR_Commit
     (Value      : Overlay_Document;
      Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
      Into       : in out String;
      Written    : in out Natural;
      Copied     : in out Boolean;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   with Pre => Is_Valid (Value);

   procedure Read_Type_IR_Semantic_Fingerprint_Length
     (Value      : Overlay_Document;
      Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
      Length     : in out Natural;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   with Pre => Is_Valid (Value);

   procedure Copy_Type_IR_Semantic_Fingerprint
     (Value      : Overlay_Document;
      Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
      Into       : in out String;
      Written    : in out Natural;
      Copied     : in out Boolean;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   with Pre => Is_Valid (Value);

   procedure Read_Type_IR_Source_SHA256_Length
     (Value      : Overlay_Document;
      Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
      Length     : in out Natural;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   with Pre => Is_Valid (Value);

   procedure Copy_Type_IR_Source_SHA256
     (Value      : Overlay_Document;
      Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
      Into       : in out String;
      Written    : in out Natural;
      Copied     : in out Boolean;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   with Pre => Is_Valid (Value);

   procedure Read_Source_SHA256_Length
     (Value      : Overlay_Document;
      Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
      Length     : in out Natural;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   with Pre => Is_Valid (Value);

   procedure Copy_Source_SHA256
     (Value      : Overlay_Document;
      Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
      Into       : in out String;
      Written    : in out Natural;
      Copied     : in out Boolean;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   with Pre => Is_Valid (Value);

   procedure Read_With_Unit_Length
     (Value      : Overlay_Document;
      Index      : Positive;
      Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
      Length     : in out Natural;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   with Pre => Is_Valid (Value);

   procedure Copy_With_Unit
     (Value      : Overlay_Document;
      Index      : Positive;
      Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
      Into       : in out String;
      Written    : in out Natural;
      Copied     : in out Boolean;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   with Pre => Is_Valid (Value);

   procedure Read_Record_Ada_Type_Length
     (Value      : Overlay_Document;
      Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
      Length     : in out Natural;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   with Pre => Is_Valid (Value);

   procedure Copy_Record_Ada_Type
     (Value      : Overlay_Document;
      Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
      Into       : in out String;
      Written    : in out Natural;
      Copied     : in out Boolean;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   with Pre => Is_Valid (Value);

   procedure Read_Record_Declaration_ID_Length
     (Value      : Overlay_Document;
      Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
      Length     : in out Natural;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   with Pre => Is_Valid (Value);

   procedure Copy_Record_Declaration_ID
     (Value      : Overlay_Document;
      Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
      Into       : in out String;
      Written    : in out Natural;
      Copied     : in out Boolean;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   with Pre => Is_Valid (Value);

   procedure Read_Record_Logical_Type_Name_Length
     (Value      : Overlay_Document;
      Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
      Length     : in out Natural;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   with Pre => Is_Valid (Value);

   procedure Copy_Record_Logical_Type_Name
     (Value      : Overlay_Document;
      Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
      Into       : in out String;
      Written    : in out Natural;
      Copied     : in out Boolean;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   with Pre => Is_Valid (Value);

   procedure Read_Field_Ada_Component_Length
     (Value      : Overlay_Document;
      Index      : Positive;
      Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
      Length     : in out Natural;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   with Pre => Is_Valid (Value);

   procedure Copy_Field_Ada_Component
     (Value      : Overlay_Document;
      Index      : Positive;
      Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
      Into       : in out String;
      Written    : in out Natural;
      Copied     : in out Boolean;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   with Pre => Is_Valid (Value);

   procedure Read_Field_Ada_Type_Length
     (Value      : Overlay_Document;
      Index      : Positive;
      Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
      Length     : in out Natural;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   with Pre => Is_Valid (Value);

   procedure Copy_Field_Ada_Type
     (Value      : Overlay_Document;
      Index      : Positive;
      Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
      Into       : in out String;
      Written    : in out Natural;
      Copied     : in out Boolean;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   with Pre => Is_Valid (Value);

   procedure Read_Field_Component_ID_Length
     (Value      : Overlay_Document;
      Index      : Positive;
      Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
      Length     : in out Natural;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   with Pre => Is_Valid (Value);

   procedure Copy_Field_Component_ID
     (Value      : Overlay_Document;
      Index      : Positive;
      Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
      Into       : in out String;
      Written    : in out Natural;
      Copied     : in out Boolean;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   with Pre => Is_Valid (Value);

   procedure Read_Field_Presentation_Name_Length
     (Value      : Overlay_Document;
      Index      : Positive;
      Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
      Length     : in out Natural;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   with Pre => Is_Valid (Value);

   procedure Copy_Field_Presentation_Name
     (Value      : Overlay_Document;
      Index      : Positive;
      Budget     : in out Flyology_Serde_Generator.Requests.Operation_Budget;
      Into       : in out String;
      Written    : in out Natural;
      Copied     : in out Boolean;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   with Pre => Is_Valid (Value);

   --  Every checked v1 overlay text is printable ASCII, so each reported
   --  length is both String elements and UTF-8 octets. Scalar, count, and
   --  length queries charge one work unit. Copy charges one probe unit and,
   --  when Into is large enough, exactly the text length before copying at
   --  Into'First. A latched diagnostic causes no budget, diagnostic, or result
   --  mutation; selecting a retained immutable component is not an observable
   --  query result. A clean poisoned or denied budget latches
   --  Resource_Exhausted and preserves every result. Undersize changes only
   --  Copied to False. Indexed range checks are uncharged programming checks
   --  after diagnostic and poison precedence; an invalid index latches
   --  Internal_Error without changing results.

private
   type Overlay_Data;
   type Overlay_Data_Access is access Overlay_Data;

   type Overlay_Document is limited new Ada.Finalization.Limited_Controlled with record
      Data : Overlay_Data_Access := null;
   end record;

   overriding procedure Finalize (Value : in out Overlay_Document);
end Flyology_Serde_Generator.Overlays;
