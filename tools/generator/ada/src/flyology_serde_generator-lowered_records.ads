with Ada.Finalization;

package Flyology_Serde_Generator.Lowered_Records is
   type Scalar_Kind is (Boolean_Scalar, Signed_64_Scalar, Unsigned_64_Scalar);

   type Type_Node_Kind is
     (Boolean_Node,
      Signed_64_Node,
      Unsigned_64_Node,
      Enumeration_Node,
      Fixed_Array_Node,
      Record_Node);

   type Runtime_Limit_Set is record
      Maximum_Nesting_Depth   : Natural;
      Maximum_Container_Items : Natural;
      Maximum_Text_Length     : Natural;
      Maximum_Byte_Length     : Natural;
      Maximum_Logical_Events  : Natural;
   end record;

   type Model is tagged limited private;

   function Is_Valid (Value : Model) return Boolean;
   function Has_Type_Graph (Value : Model) return Boolean;
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
   function Field_Presentation_Name
     (Value : Model; Index : Positive) return String
   with Pre => Index <= Field_Count (Value);
   function Field_Scalar_Kind
     (Value : Model; Index : Positive) return Scalar_Kind
   with
     Pre => Index <= Field_Count (Value) and then not Has_Type_Graph (Value);
   function Runtime_Limits (Value : Model) return Runtime_Limit_Set;

   function Type_Node_Count (Value : Model) return Natural
   with Pre => Has_Type_Graph (Value);
   function Node_Kind (Value : Model; Index : Positive) return Type_Node_Kind
   with
     Pre => Has_Type_Graph (Value) and then Index <= Type_Node_Count (Value);
   function Node_Ada_Type (Value : Model; Index : Positive) return String
   with
     Pre => Has_Type_Graph (Value) and then Index <= Type_Node_Count (Value);
   function Node_Logical_Name (Value : Model; Index : Positive) return String
   with
     Pre => Has_Type_Graph (Value) and then Index <= Type_Node_Count (Value);
   function Node_Defining_With (Value : Model; Index : Positive) return Natural
   with
     Pre => Has_Type_Graph (Value) and then Index <= Type_Node_Count (Value);

   function Enumeration_Literal_Count
     (Value : Model; Node : Positive) return Natural
   with
     Pre =>
       Has_Type_Graph (Value)
       and then Node <= Type_Node_Count (Value)
       and then Node_Kind (Value, Node) = Enumeration_Node;
   function Enumeration_Literal_Ada_Name
     (Value : Model; Node : Positive; Position : Positive) return String
   with Pre => Position <= Enumeration_Literal_Count (Value, Node);
   function Enumeration_Literal_Primary_Name
     (Value : Model; Node : Positive; Position : Positive) return String
   with Pre => Position <= Enumeration_Literal_Count (Value, Node);
   function Enumeration_Literal_Alias_Count
     (Value : Model; Node : Positive; Position : Positive) return Natural
   with Pre => Position <= Enumeration_Literal_Count (Value, Node);
   function Enumeration_Literal_Alias_Name
     (Value : Model; Node : Positive; Position : Positive; Alias : Positive)
      return String
   with
     Pre => Alias <= Enumeration_Literal_Alias_Count (Value, Node, Position);

   function Array_Index_Node (Value : Model; Node : Positive) return Positive
   with
     Pre =>
       Has_Type_Graph (Value)
       and then Node <= Type_Node_Count (Value)
       and then Node_Kind (Value, Node) = Fixed_Array_Node;
   function Array_Element_Node (Value : Model; Node : Positive) return Positive
   with
     Pre =>
       Has_Type_Graph (Value)
       and then Node <= Type_Node_Count (Value)
       and then Node_Kind (Value, Node) = Fixed_Array_Node;

   function Field_Type_Node (Value : Model; Index : Positive) return Positive
   with Pre => Has_Type_Graph (Value) and then Index <= Field_Count (Value);
   function Root_Node (Value : Model) return Positive
   with Pre => Has_Type_Graph (Value);
   function Graph_Work_Units (Value : Model) return Positive
   with Pre => Has_Type_Graph (Value);

private
   Text_Capacity      : constant := 128;
   Maximum_With_Units : constant := 2;
   Maximum_Fields     : constant := 4;

   type Bounded_Text is record
      Length : Natural range 0 .. Text_Capacity := 0;
      Data   : String (1 .. Text_Capacity) := [others => ASCII.NUL];
   end record;

   type With_Unit_Array is
     array (Positive range 1 .. Maximum_With_Units) of Bounded_Text;

   type Field_Data is record
      Ada_Component     : Bounded_Text;
      Ada_Type          : Bounded_Text;
      Presentation_Name : Bounded_Text;
      Kind              : Scalar_Kind := Boolean_Scalar;
   end record;

   type Field_Array is
     array (Positive range 1 .. Maximum_Fields) of Field_Data;

   type Graph_Type_Data is record
      Kind          : Type_Node_Kind := Boolean_Node;
      Ada_Type      : Bounded_Text;
      Logical_Name  : Bounded_Text;
      Defining_With : Natural := 0;
      Literal_First : Natural := 0;
      Literal_Count : Natural := 0;
      Index_Node    : Natural := 0;
      Element_Node  : Natural := 0;
      Field_First   : Natural := 0;
      Field_Count   : Natural := 0;
   end record;

   type Graph_Literal_Data is record
      Ada_Name     : Bounded_Text;
      Primary_Name : Bounded_Text;
      Alias_First  : Natural := 0;
      Alias_Count  : Natural := 0;
   end record;

   type Graph_Field_Data is record
      Ada_Component     : Bounded_Text;
      Presentation_Name : Bounded_Text;
      Type_Node         : Natural := 0;
   end record;

   type Graph_Type_Array is array (Positive range <>) of Graph_Type_Data;
   type Graph_Literal_Array is array (Positive range <>) of Graph_Literal_Data;
   type Graph_Field_Array is array (Positive range <>) of Graph_Field_Data;
   type Graph_Text_Array is array (Positive range <>) of Bounded_Text;

   type Graph_Data
     (Types_Count    : Natural;
      Fields_Count   : Natural;
      Literals_Count : Natural;
      Aliases_Count  : Natural;
      With_Count     : Natural)
   is record
      Valid                : Boolean := False;
      Unit_Name            : Bounded_Text;
      With_Units           : Graph_Text_Array (1 .. With_Count);
      Types                : Graph_Type_Array (1 .. Types_Count);
      Fields               : Graph_Field_Array (1 .. Fields_Count);
      Literals             : Graph_Literal_Array (1 .. Literals_Count);
      Aliases              : Graph_Text_Array (1 .. Aliases_Count);
      Root                 : Natural := 0;
      Work_Units           : Natural := 0;
      Serialization_Limits : Runtime_Limit_Set := (others => 0);
   end record;

   type Graph_Data_Access is access Graph_Data;

   function Graph_Structure_Is_Valid (Value : Graph_Data) return Boolean;

   type Model is limited new Ada.Finalization.Limited_Controlled with record
      Valid                : Boolean := False;
      Unit_Name            : Bounded_Text;
      With_Count           : Natural range 0 .. Maximum_With_Units := 0;
      With_Units           : With_Unit_Array;
      Ada_Type             : Bounded_Text;
      Logical_Name         : Bounded_Text;
      Fields_Count         : Natural range 0 .. Maximum_Fields := 0;
      Fields               : Field_Array;
      Serialization_Limits : Runtime_Limit_Set := (others => 0);
      Graph                : Graph_Data_Access := null;
   end record;

   overriding
   procedure Finalize (Value : in out Model);

   procedure Set_Text (Target : out Bounded_Text; Value : String);
end Flyology_Serde_Generator.Lowered_Records;
