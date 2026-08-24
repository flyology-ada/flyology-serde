package Flyology_Serde_Generator.Lowered_Records is
   type Scalar_Kind is (Boolean_Scalar, Signed_64_Scalar, Unsigned_64_Scalar);

   type Runtime_Limit_Set is record
      Maximum_Nesting_Depth   : Natural;
      Maximum_Container_Items : Natural;
      Maximum_Text_Length     : Natural;
      Maximum_Byte_Length     : Natural;
      Maximum_Logical_Events  : Natural;
   end record;

   type Model is limited private;

   function Is_Valid (Value : Model) return Boolean;
   function Output_Unit (Value : Model) return String;
   function With_Unit_Count (Value : Model) return Natural;
   function With_Unit (Value : Model; Index : Positive) return String
   with Pre => Index <= With_Unit_Count (Value);
   function Record_Ada_Type (Value : Model) return String;
   function Logical_Type_Name (Value : Model) return String;
   function Field_Count (Value : Model) return Natural;
   function Field_Ada_Component (Value : Model; Index : Positive) return String
   with Pre => Index <= Field_Count (Value);
   function Field_Ada_Type (Value : Model; Index : Positive) return String
   with Pre => Index <= Field_Count (Value);
   function Field_Presentation_Name (Value : Model; Index : Positive) return String
   with Pre => Index <= Field_Count (Value);
   function Field_Scalar_Kind (Value : Model; Index : Positive) return Scalar_Kind
   with Pre => Index <= Field_Count (Value);
   function Runtime_Limits (Value : Model) return Runtime_Limit_Set;

private
   Text_Capacity      : constant := 128;
   Maximum_With_Units : constant := 2;
   Maximum_Fields     : constant := 4;

   type Bounded_Text is record
      Length : Natural range 0 .. Text_Capacity := 0;
      Data   : String (1 .. Text_Capacity) := [others => ASCII.NUL];
   end record;

   type With_Unit_Array is array (Positive range 1 .. Maximum_With_Units) of Bounded_Text;

   type Field_Data is record
      Ada_Component     : Bounded_Text;
      Ada_Type          : Bounded_Text;
      Presentation_Name : Bounded_Text;
      Kind              : Scalar_Kind := Boolean_Scalar;
   end record;

   type Field_Array is array (Positive range 1 .. Maximum_Fields) of Field_Data;

   type Model is limited record
      Valid             : Boolean := False;
      Unit_Name         : Bounded_Text;
      With_Count        : Natural range 0 .. Maximum_With_Units := 0;
      With_Units        : With_Unit_Array;
      Ada_Type          : Bounded_Text;
      Logical_Name      : Bounded_Text;
      Fields_Count      : Natural range 0 .. Maximum_Fields := 0;
      Fields            : Field_Array;
      Serialization_Limits : Runtime_Limit_Set := (others => 0);
   end record;

   procedure Set_Text (Target : out Bounded_Text; Value : String);
end Flyology_Serde_Generator.Lowered_Records;
