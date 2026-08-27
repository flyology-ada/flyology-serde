with Ada.Streams;
with Flyology.Reflection.Predefined_Types;
with Flyology.Reflection.Value_Views;
with Flyology_Serde.Data_Model;
with Flyology_Serde.Errors;
with Flyology_Serde.Serialization;
with Flyology_Serde.Serialization_Adapters;
with Flyology_Serde.Serializers.CBOR;
with Flyology_Serde.Serializers.JSON;
with Flyology_Serde_Reflection.Serialization_Adapters;
with Interfaces;
with Typed_Generated_Subjects;
with Typed_Generated_Subjects.Reflection.Values;

procedure Reflection_Serialization_Tests is
   package Errors renames Flyology_Serde.Errors;
   package Serialization renames Flyology_Serde.Serialization;
   package CBOR renames Flyology_Serde.Serializers.CBOR;
   package JSON renames Flyology_Serde.Serializers.JSON;
   package Subjects renames Typed_Generated_Subjects;
   package Views renames Typed_Generated_Subjects.Reflection.Values;
   use type Ada.Streams.Stream_Element_Array;
   use type Errors.Error_Code;
   use type Errors.Path_Element_Kind;
   use type Interfaces.Integer_64;
   use type Serialization.Serializer_State;
   use type Subjects.Offset;
   use type Subjects.Shade;

   Limits : constant Serialization.Serialization_Limits :=
     (Maximum_Nesting_Depth   => 8,
      Maximum_Container_Items => 32,
      Maximum_Text_Length     => 128,
      Maximum_Byte_Length     => 128,
      Maximum_Logical_Events  => 128);

   Assertion_Probe_Ran : Boolean := False;

   function Mark_Assertion_Execution return Boolean is
   begin
      Assertion_Probe_Ran := True;
      return True;
   end Mark_Assertion_Execution;

   package Shades is new
     Flyology_Serde_Reflection.Serialization_Adapters
       (Source_Type => Subjects.Shade,
        Limits      => Limits,
        Observe     => Views.Observe);

   package Offsets is new
     Flyology_Serde_Reflection.Serialization_Adapters
       (Source_Type => Subjects.Offset,
        Limits      => Limits,
        Observe     => Views.Observe);

   package Words is new
     Flyology_Serde_Reflection.Serialization_Adapters
       (Source_Type => Subjects.Word,
        Limits      => Limits,
        Observe     => Views.Observe);

   package Shade_Arrays is new
     Flyology_Serde_Reflection.Serialization_Adapters
       (Source_Type => Subjects.Shade_Array,
        Limits      => Limits,
        Observe     => Views.Observe);

   package Shade_Matrices is new
     Flyology_Serde_Reflection.Serialization_Adapters
       (Source_Type => Subjects.Shade_Matrix,
        Limits      => Limits,
        Observe     => Views.Observe);

   package Snapshots is new
     Flyology_Serde_Reflection.Serialization_Adapters
       (Source_Type => Subjects.Snapshot,
        Limits      => Limits,
        Observe     => Views.Observe);

   package Discriminated_Snapshots is new
     Flyology_Serde_Reflection.Serialization_Adapters
       (Source_Type => Subjects.Discriminated_Snapshot,
        Limits      => Limits,
        Observe     => Views.Observe);

   package Standard_Scalar_Records is new
     Flyology_Serde_Reflection.Serialization_Adapters
       (Source_Type => Subjects.Standard_Scalar_Record,
        Limits      => Limits,
        Observe     => Views.Observe);

   package Variants is new
     Flyology_Serde_Reflection.Serialization_Adapters
       (Source_Type => Subjects.Variant_Record,
        Limits      => Limits,
        Observe     => Views.Observe);

   procedure Serialize_Static_Shade
     (Item  : Subjects.Shade;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
   begin
      Into.Put_Enumeration
        ("Typed_Generated_Subjects.Shade",
         (case Item is
             when Subjects.Light  => "Light",
             when Subjects.Medium => "Medium",
             when Subjects.Dark   => "Dark"),
         Error);
   end Serialize_Static_Shade;

   procedure Serialize_Static_Snapshot_Value
     (Item  : Subjects.Snapshot;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
   begin
      Into.Begin_Record ("Typed_Generated_Subjects.Snapshot", 2, Error);
      Into.Put_Field ("Tone", Error);
      Serialize_Static_Shade (Item.Tone, Into, Error);
      Into.Put_Field ("Palette", Error);
      Into.Begin_Sequence
        (Flyology_Serde.Data_Model.Known_Length (Item.Palette'Length), Error);
      for Element of Item.Palette loop
         Serialize_Static_Shade (Element, Into, Error);
      end loop;
      Into.End_Sequence (Error);
      Into.End_Record (Error);
   end Serialize_Static_Snapshot_Value;

   package Static_Snapshots is new Flyology_Serde.Serialization_Adapters
     (Source_Type     => Subjects.Snapshot,
      Limits          => Limits,
      Serialize_Value => Serialize_Static_Snapshot_Value);

   procedure Serialize_Static_Variant_Value
     (Item  : Subjects.Variant_Record;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
   begin
      Into.Begin_Variant
        ("Typed_Generated_Subjects.Variant_Record",
         (if Item.Tone = Subjects.Light then "Light" else "others"),
         2,
         Error);
      Into.Put_Field ("Tone", Error);
      Serialize_Static_Shade (Item.Tone, Into, Error);
      case Item.Tone is
         when Subjects.Light =>
            Into.Put_Field ("Light_Value", Error);
            Serialize_Static_Shade (Item.Light_Value, Into, Error);

         when others         =>
            Into.Put_Field ("Dark_Value", Error);
            Serialize_Static_Shade (Item.Dark_Value, Into, Error);
      end case;
      Into.End_Variant (Error);
   end Serialize_Static_Variant_Value;

   package Static_Variants is new Flyology_Serde.Serialization_Adapters
     (Source_Type     => Subjects.Variant_Record,
      Limits          => Limits,
      Serialize_Value => Serialize_Static_Variant_Value);

   procedure Observe_Boolean
     (Item  : Boolean;
      Using : in out Flyology.Reflection.Value_Views.Value_Consumer'Class)
   is
      View : constant Flyology.Reflection.Predefined_Types.Boolean_View :=
        Flyology.Reflection.Predefined_Types.To_View (Item);
   begin
      Flyology.Reflection.Value_Views.Route (View, Using);
   end Observe_Boolean;

   package Booleans is new
     Flyology_Serde_Reflection.Serialization_Adapters
       (Source_Type => Boolean,
        Limits      => Limits,
        Observe     => Observe_Boolean);

   package Limited_Items is new
     Flyology_Serde_Reflection.Serialization_Adapters
       (Source_Type => Subjects.Limited_Item,
        Limits      => Limits,
        Observe     => Views.Observe);

   Item_Limits : constant Serialization.Serialization_Limits :=
     (Maximum_Nesting_Depth   => 8,
      Maximum_Container_Items => 0,
      Maximum_Text_Length     => 128,
      Maximum_Byte_Length     => 128,
      Maximum_Logical_Events  => 128);

   Depth_Limits : constant Serialization.Serialization_Limits :=
     (Maximum_Nesting_Depth   => 0,
      Maximum_Container_Items => 32,
      Maximum_Text_Length     => 128,
      Maximum_Byte_Length     => 128,
      Maximum_Logical_Events  => 128);

   Event_Limits : constant Serialization.Serialization_Limits :=
     (Maximum_Nesting_Depth   => 8,
      Maximum_Container_Items => 32,
      Maximum_Text_Length     => 128,
      Maximum_Byte_Length     => 128,
      Maximum_Logical_Events  => 1);

   Text_Limits : constant Serialization.Serialization_Limits :=
     (Maximum_Nesting_Depth   => 8,
      Maximum_Container_Items => 32,
      Maximum_Text_Length     => 3,
      Maximum_Byte_Length     => 128,
      Maximum_Logical_Events  => 128);

   Zero_Text_Limits : constant Serialization.Serialization_Limits :=
     (Maximum_Nesting_Depth   => 8,
      Maximum_Container_Items => 32,
      Maximum_Text_Length     => 0,
      Maximum_Byte_Length     => 128,
      Maximum_Logical_Events  => 128);

   package Item_Limited_Arrays is new
     Flyology_Serde_Reflection.Serialization_Adapters
       (Source_Type => Subjects.Shade_Array,
        Limits      => Item_Limits,
        Observe     => Views.Observe);

   package Depth_Limited_Snapshots is new
     Flyology_Serde_Reflection.Serialization_Adapters
       (Source_Type => Subjects.Snapshot,
        Limits      => Depth_Limits,
        Observe     => Views.Observe);

   package Event_Limited_Snapshots is new
     Flyology_Serde_Reflection.Serialization_Adapters
       (Source_Type => Subjects.Snapshot,
        Limits      => Event_Limits,
        Observe     => Views.Observe);

   package Text_Limited_Shades is new
     Flyology_Serde_Reflection.Serialization_Adapters
       (Source_Type => Subjects.Shade,
        Limits      => Text_Limits,
        Observe     => Views.Observe);

   procedure Observe_Character
     (Item  : Character;
      Using : in out Flyology.Reflection.Value_Views.Value_Consumer'Class)
   is
      View : constant Flyology.Reflection.Predefined_Types.Character_View :=
        Flyology.Reflection.Predefined_Types.To_View (Item);
   begin
      Flyology.Reflection.Value_Views.Route (View, Using);
   end Observe_Character;

   package Characters is new
     Flyology_Serde_Reflection.Serialization_Adapters
       (Source_Type => Character,
        Limits      => Limits,
        Observe     => Observe_Character);

   type Signed_Probe_Kind is
     (Canonical_Zero,
      Positive_Maximum,
      Negative_Minimum,
      Negative_Zero_Text,
      Positive_Overflow,
      Negative_Overflow,
      Invalid_Digit,
      No_Root_Callback,
      Two_Root_Callbacks,
      Raise_After_Root);

   type Signed_Probe_View (Kind : Signed_Probe_Kind) is
     new Flyology.Reflection.Value_Views.Value_View
     and Flyology.Reflection.Value_Views.Signed_Integer_View
   with null record;

   Signed_Probe_Observe_Calls : Natural := 0;

   overriding
   function Type_Of
     (Item : Signed_Probe_View)
      return Flyology.Reflection.Value_Views.Type_Reference;

   overriding
   procedure Dispatch
     (Item : Signed_Probe_View;
      To   : in out Flyology.Reflection.Value_Views.Value_Consumer'Class);

   overriding
   function Canonical_Decimal (Item : Signed_Probe_View) return String;

   overriding
   function Type_Of
     (Item : Signed_Probe_View)
      return Flyology.Reflection.Value_Views.Type_Reference
   is
      pragma Unreferenced (Item);
   begin
      return Flyology.Reflection.Predefined_Types.Integer_Type;
   end Type_Of;

   overriding
   procedure Dispatch
     (Item : Signed_Probe_View;
      To   : in out Flyology.Reflection.Value_Views.Value_Consumer'Class) is
   begin
      To.Consume (Item);
   end Dispatch;

   overriding
   function Canonical_Decimal (Item : Signed_Probe_View) return String
   is (case Item.Kind is
         when Canonical_Zero
            | No_Root_Callback
            | Two_Root_Callbacks
            | Raise_After_Root   => "0",
         when Positive_Maximum   => "9223372036854775807",
         when Negative_Minimum   => "-9223372036854775808",
         when Negative_Zero_Text => "-0",
         when Positive_Overflow  => "9223372036854775808",
         when Negative_Overflow  => "-9223372036854775809",
         when Invalid_Digit      => "1x");

   procedure Observe_Signed_Probe
     (Item  : Signed_Probe_Kind;
      Using : in out Flyology.Reflection.Value_Views.Value_Consumer'Class)
   is
      View : Signed_Probe_View (Item);
   begin
      Signed_Probe_Observe_Calls := Signed_Probe_Observe_Calls + 1;
      if Item = No_Root_Callback then
         return;
      end if;
      Flyology.Reflection.Value_Views.Route (View, Using);
      if Item = Two_Root_Callbacks then
         Flyology.Reflection.Value_Views.Route (View, Using);
      elsif Item = Raise_After_Root then
         raise Program_Error with "injected root observer failure";
      end if;
   end Observe_Signed_Probe;

   package Signed_Probes is new
     Flyology_Serde_Reflection.Serialization_Adapters
       (Source_Type => Signed_Probe_Kind,
        Limits      => Limits,
        Observe     => Observe_Signed_Probe);

   type Modular_Probe_Kind is
     (Modular_Maximum,
      Modular_Overflow,
      Modular_Leading_Zero,
      Modular_Negative);

   type Modular_Probe_View (Kind : Modular_Probe_Kind) is
     new Flyology.Reflection.Value_Views.Value_View
     and Flyology.Reflection.Value_Views.Modular_Integer_View
   with null record;

   overriding
   function Type_Of
     (Item : Modular_Probe_View)
      return Flyology.Reflection.Value_Views.Type_Reference;

   overriding
   procedure Dispatch
     (Item : Modular_Probe_View;
      To   : in out Flyology.Reflection.Value_Views.Value_Consumer'Class);

   overriding
   function Canonical_Decimal (Item : Modular_Probe_View) return String;

   overriding
   function Type_Of
     (Item : Modular_Probe_View)
      return Flyology.Reflection.Value_Views.Type_Reference
   is
      pragma Unreferenced (Item);
   begin
      return Flyology.Reflection.Predefined_Types.Integer_Type;
   end Type_Of;

   overriding
   procedure Dispatch
     (Item : Modular_Probe_View;
      To   : in out Flyology.Reflection.Value_Views.Value_Consumer'Class) is
   begin
      To.Consume (Item);
   end Dispatch;

   overriding
   function Canonical_Decimal (Item : Modular_Probe_View) return String
   is (case Item.Kind is
         when Modular_Maximum      => "18446744073709551615",
         when Modular_Overflow     => "18446744073709551616",
         when Modular_Leading_Zero => "01",
         when Modular_Negative     => "-1");

   procedure Observe_Modular_Probe
     (Item  : Modular_Probe_Kind;
      Using : in out Flyology.Reflection.Value_Views.Value_Consumer'Class)
   is
      View : Modular_Probe_View (Item);
   begin
      Flyology.Reflection.Value_Views.Route (View, Using);
   end Observe_Modular_Probe;

   package Modular_Probes is new
     Flyology_Serde_Reflection.Serialization_Adapters
       (Source_Type => Modular_Probe_Kind,
        Limits      => Limits,
        Observe     => Observe_Modular_Probe);

   type Bad_Supplement_View is
     new Flyology.Reflection.Value_Views.Value_View
     and Flyology.Reflection.Value_Views.Signed_Integer_View
     and Flyology.Reflection.Value_Views.Variant_View
   with null record;

   overriding
   function Type_Of
     (Item : Bad_Supplement_View)
      return Flyology.Reflection.Value_Views.Type_Reference;

   overriding
   procedure Dispatch
     (Item : Bad_Supplement_View;
      To   : in out Flyology.Reflection.Value_Views.Value_Consumer'Class);

   overriding
   function Canonical_Decimal (Item : Bad_Supplement_View) return String;

   overriding
   function Selected_Alternative_Count
     (Item : Bad_Supplement_View)
      return Flyology.Reflection.Value_Views.Cardinality;

   overriding
   procedure Observe_Selected_Alternatives
     (Item  : Bad_Supplement_View;
      Using : in out Flyology.Reflection.Value_Views.Variant_Consumer'Class);

   overriding
   function Type_Of
     (Item : Bad_Supplement_View)
      return Flyology.Reflection.Value_Views.Type_Reference
   is
      pragma Unreferenced (Item);
   begin
      return Flyology.Reflection.Predefined_Types.Integer_Type;
   end Type_Of;

   overriding
   procedure Dispatch
     (Item : Bad_Supplement_View;
      To   : in out Flyology.Reflection.Value_Views.Value_Consumer'Class) is
   begin
      To.Consume (Item);
   end Dispatch;

   overriding
   function Canonical_Decimal (Item : Bad_Supplement_View) return String is
      pragma Unreferenced (Item);
   begin
      return "0";
   end Canonical_Decimal;

   overriding
   function Selected_Alternative_Count
     (Item : Bad_Supplement_View)
      return Flyology.Reflection.Value_Views.Cardinality
   is
      pragma Unreferenced (Item);
   begin
      return Flyology.Reflection.Value_Views.Exact_Count (1);
   end Selected_Alternative_Count;

   overriding
   procedure Observe_Selected_Alternatives
     (Item  : Bad_Supplement_View;
      Using : in out Flyology.Reflection.Value_Views.Variant_Consumer'Class)
   is
      pragma Unreferenced (Item, Using);
   begin
      raise Program_Error with "a nonrecord variant must not be traversed";
   end Observe_Selected_Alternatives;

   procedure Observe_Bad_Supplement
     (Item  : Boolean;
      Using : in out Flyology.Reflection.Value_Views.Value_Consumer'Class)
   is
      pragma Unreferenced (Item);
      View : Bad_Supplement_View;
   begin
      Flyology.Reflection.Value_Views.Route (View, Using);
   end Observe_Bad_Supplement;

   package Bad_Supplements is new
     Flyology_Serde_Reflection.Serialization_Adapters
       (Source_Type => Boolean,
        Limits      => Limits,
        Observe     => Observe_Bad_Supplement);

   type Reflection_Failure_Kind is
     (Report_Malformed_View, Report_Traversal_Not_Available);

   procedure Observe_Reflection_Failure
     (Item  : Reflection_Failure_Kind;
      Using : in out Flyology.Reflection.Value_Views.Value_Consumer'Class)
   is
      pragma Unreferenced (Using);
   begin
      case Item is
         when Report_Malformed_View          =>
            raise Flyology.Reflection.Value_Views.Malformed_View;

         when Report_Traversal_Not_Available =>
            raise Flyology.Reflection.Value_Views.Traversal_Not_Available;
      end case;
   end Observe_Reflection_Failure;

   package Reflection_Failures is new
     Flyology_Serde_Reflection.Serialization_Adapters
       (Source_Type => Reflection_Failure_Kind,
        Limits      => Limits,
        Observe     => Observe_Reflection_Failure);

   type Bound_Probe_Kind is
     (Wrong_Bound_Identity, Invalid_Bound_Text, Overflowing_Bound_Text);

   type Bound_Probe_View (Kind : Bound_Probe_Kind) is
     new Flyology.Reflection.Value_Views.Value_View
     and Flyology.Reflection.Value_Views.Signed_Integer_View
   with null record;

   overriding
   function Type_Of
     (Item : Bound_Probe_View)
      return Flyology.Reflection.Value_Views.Type_Reference;

   overriding
   procedure Dispatch
     (Item : Bound_Probe_View;
      To   : in out Flyology.Reflection.Value_Views.Value_Consumer'Class);

   overriding function Canonical_Decimal (Item : Bound_Probe_View) return String;

   overriding
   function Type_Of
     (Item : Bound_Probe_View)
      return Flyology.Reflection.Value_Views.Type_Reference is
   begin
      if Item.Kind = Wrong_Bound_Identity then
         return Views.Offset_Type;
      else
         return Flyology.Reflection.Predefined_Types.Integer_Type;
      end if;
   end Type_Of;

   overriding
   procedure Dispatch
     (Item : Bound_Probe_View;
      To   : in out Flyology.Reflection.Value_Views.Value_Consumer'Class) is
   begin
      To.Consume (Item);
   end Dispatch;

   overriding function Canonical_Decimal
     (Item : Bound_Probe_View) return String
   is (case Item.Kind is
         when Wrong_Bound_Identity   => "1",
         when Invalid_Bound_Text     => "01",
         when Overflowing_Bound_Text => "9223372036854775808");

   type Malformed_Bound_View is
     new Flyology.Reflection.Value_Views.Value_View
     and Flyology.Reflection.Value_Views.Signed_Integer_View
     and Flyology.Reflection.Value_Views.Boolean_View
   with null record;

   overriding
   function Type_Of
     (Item : Malformed_Bound_View)
      return Flyology.Reflection.Value_Views.Type_Reference;

   overriding
   procedure Dispatch
     (Item : Malformed_Bound_View;
      To   : in out Flyology.Reflection.Value_Views.Value_Consumer'Class);

   overriding
   function Canonical_Decimal (Item : Malformed_Bound_View) return String;

   overriding function Boolean_Value (Item : Malformed_Bound_View) return Boolean;

   overriding
   function Type_Of
     (Item : Malformed_Bound_View)
      return Flyology.Reflection.Value_Views.Type_Reference
   is
      pragma Unreferenced (Item);
   begin
      return Flyology.Reflection.Predefined_Types.Integer_Type;
   end Type_Of;

   overriding
   procedure Dispatch
     (Item : Malformed_Bound_View;
      To   : in out Flyology.Reflection.Value_Views.Value_Consumer'Class) is
   begin
      To.Consume (Item);
   end Dispatch;

   overriding
   function Canonical_Decimal (Item : Malformed_Bound_View) return String is
      pragma Unreferenced (Item);
   begin
      return "1";
   end Canonical_Decimal;

   overriding function Boolean_Value
     (Item : Malformed_Bound_View) return Boolean is
      pragma Unreferenced (Item);
   begin
      return True;
   end Boolean_Value;

   type Supplemented_Bound_View is
     new Flyology.Reflection.Value_Views.Value_View
     and Flyology.Reflection.Value_Views.Signed_Integer_View
     and Flyology.Reflection.Value_Views.Variant_View
   with null record;

   overriding
   function Type_Of
     (Item : Supplemented_Bound_View)
      return Flyology.Reflection.Value_Views.Type_Reference;

   overriding
   procedure Dispatch
     (Item : Supplemented_Bound_View;
      To   : in out Flyology.Reflection.Value_Views.Value_Consumer'Class);

   overriding
   function Canonical_Decimal
     (Item : Supplemented_Bound_View) return String;

   overriding
   function Selected_Alternative_Count
     (Item : Supplemented_Bound_View)
      return Flyology.Reflection.Value_Views.Cardinality;

   overriding
   procedure Observe_Selected_Alternatives
     (Item  : Supplemented_Bound_View;
      Using : in out Flyology.Reflection.Value_Views.Variant_Consumer'Class);

   overriding
   function Type_Of
     (Item : Supplemented_Bound_View)
      return Flyology.Reflection.Value_Views.Type_Reference
   is
      pragma Unreferenced (Item);
   begin
      return Flyology.Reflection.Predefined_Types.Integer_Type;
   end Type_Of;

   overriding
   procedure Dispatch
     (Item : Supplemented_Bound_View;
      To   : in out Flyology.Reflection.Value_Views.Value_Consumer'Class) is
   begin
      To.Consume (Item);
   end Dispatch;

   overriding
   function Canonical_Decimal
     (Item : Supplemented_Bound_View) return String is
      pragma Unreferenced (Item);
   begin
      return "1";
   end Canonical_Decimal;

   overriding
   function Selected_Alternative_Count
     (Item : Supplemented_Bound_View)
      return Flyology.Reflection.Value_Views.Cardinality
   is
      pragma Unreferenced (Item);
   begin
      return Flyology.Reflection.Value_Views.Exact_Count (1);
   end Selected_Alternative_Count;

   overriding
   procedure Observe_Selected_Alternatives
     (Item  : Supplemented_Bound_View;
      Using : in out Flyology.Reflection.Value_Views.Variant_Consumer'Class)
   is
      pragma Unreferenced (Item, Using);
   begin
      raise Program_Error with "supplemented bound observer must not run";
   end Observe_Selected_Alternatives;

   type Array_Probe_Kind is
     (Zero_Elements,
      Two_Elements,
      Zero_First_Bounds,
      Two_First_Bounds,
      Zero_Last_Bounds,
      Two_Last_Bounds,
      Dimension_Count_Drift,
      Unrepresentable_Element_Count,
      Unrepresentable_Dimension_Length,
      Rank_Two,
      Malformed_Bound,
      Supplemented_Bound,
      Wrong_Bound_Type,
      Invalid_Bound_Canonical_Text,
      Overflowing_Bound_Canonical_Text);

   type Array_Probe_View (Kind : Array_Probe_Kind) is
     new Flyology.Reflection.Value_Views.Value_View
     and Flyology.Reflection.Value_Views.Array_View
   with null record;

   overriding
   function Type_Of
     (Item : Array_Probe_View)
      return Flyology.Reflection.Value_Views.Type_Reference;

   overriding
   procedure Dispatch
     (Item : Array_Probe_View;
      To   : in out Flyology.Reflection.Value_Views.Value_Consumer'Class);

   overriding
   function Element_Count
     (Item : Array_Probe_View)
      return Flyology.Reflection.Value_Views.Cardinality;

   overriding function Rank (Item : Array_Probe_View) return Positive;

   overriding
   function Dimension_Length
     (Item      : Array_Probe_View;
      Dimension : Positive)
      return Flyology.Reflection.Value_Views.Cardinality;

   overriding
   function Index_Subtype_Name
     (Item      : Array_Probe_View;
      Dimension : Positive) return String;

   overriding
   procedure Observe_First_Index
     (Item      : Array_Probe_View;
      Dimension : Positive;
      Using     : in out Flyology.Reflection.Value_Views.Value_Consumer'Class);

   overriding
   procedure Observe_Last_Index
     (Item      : Array_Probe_View;
      Dimension : Positive;
      Using     : in out Flyology.Reflection.Value_Views.Value_Consumer'Class);

   overriding
   procedure Observe_Elements
     (Item  : Array_Probe_View;
      Using : in out Flyology.Reflection.Value_Views.Element_Consumer'Class);

   overriding
   function Type_Of
     (Item : Array_Probe_View)
      return Flyology.Reflection.Value_Views.Type_Reference
   is
      pragma Unreferenced (Item);
   begin
      return Views.Shade_Array_Type;
   end Type_Of;

   overriding
   procedure Dispatch
     (Item : Array_Probe_View;
      To   : in out Flyology.Reflection.Value_Views.Value_Consumer'Class) is
   begin
      To.Consume (Item);
   end Dispatch;

   overriding
   function Element_Count
     (Item : Array_Probe_View)
      return Flyology.Reflection.Value_Views.Cardinality is
   begin
      if Item.Kind = Unrepresentable_Element_Count then
         return
           (Status =>
              Flyology.Reflection.Value_Views.Count_Not_Representable);
      else
         return Flyology.Reflection.Value_Views.Exact_Count (1);
      end if;
   end Element_Count;

   overriding function Rank (Item : Array_Probe_View) return Positive is
   begin
      return (if Item.Kind = Rank_Two then 2 else 1);
   end Rank;

   overriding
   function Dimension_Length
     (Item      : Array_Probe_View;
      Dimension : Positive)
      return Flyology.Reflection.Value_Views.Cardinality
   is
      pragma Unreferenced (Dimension);
   begin
      case Item.Kind is
         when Dimension_Count_Drift              =>
            return Flyology.Reflection.Value_Views.Exact_Count (2);

         when Unrepresentable_Dimension_Length   =>
            return
              (Status =>
                 Flyology.Reflection.Value_Views.Count_Not_Representable);

         when others                             =>
            return Flyology.Reflection.Value_Views.Exact_Count (1);
      end case;
   end Dimension_Length;

   overriding
   function Index_Subtype_Name
     (Item      : Array_Probe_View;
      Dimension : Positive) return String
   is
      pragma Unreferenced (Item, Dimension);
   begin
      return "Standard.Integer";
   end Index_Subtype_Name;

   overriding
   procedure Observe_First_Index
     (Item      : Array_Probe_View;
      Dimension : Positive;
      Using     : in out Flyology.Reflection.Value_Views.Value_Consumer'Class)
   is
      pragma Unreferenced (Dimension);
      Bound : constant Flyology.Reflection.Predefined_Types.Integer_View :=
        Flyology.Reflection.Predefined_Types.To_View (1);
   begin
      case Item.Kind is
         when Zero_First_Bounds                 =>
            null;

         when Two_First_Bounds                  =>
            Flyology.Reflection.Value_Views.Route (Bound, Using);
            Flyology.Reflection.Value_Views.Route (Bound, Using);

         when Malformed_Bound                   =>
            declare
               Malformed : Malformed_Bound_View;
            begin
               Flyology.Reflection.Value_Views.Route (Malformed, Using);
            end;

         when Supplemented_Bound                =>
            declare
               Supplemented : Supplemented_Bound_View;
            begin
               Flyology.Reflection.Value_Views.Route (Supplemented, Using);
            end;

         when Wrong_Bound_Type                  =>
            declare
               Wrong : Bound_Probe_View (Wrong_Bound_Identity);
            begin
               Flyology.Reflection.Value_Views.Route (Wrong, Using);
            end;

         when Invalid_Bound_Canonical_Text      =>
            declare
               Invalid : Bound_Probe_View (Invalid_Bound_Text);
            begin
               Flyology.Reflection.Value_Views.Route (Invalid, Using);
            end;

         when Overflowing_Bound_Canonical_Text  =>
            declare
               Overflow : Bound_Probe_View (Overflowing_Bound_Text);
            begin
               Flyology.Reflection.Value_Views.Route (Overflow, Using);
            end;

         when others                            =>
            Flyology.Reflection.Value_Views.Route (Bound, Using);
      end case;
   end Observe_First_Index;

   overriding
   procedure Observe_Last_Index
     (Item      : Array_Probe_View;
      Dimension : Positive;
      Using     : in out Flyology.Reflection.Value_Views.Value_Consumer'Class)
   is
      pragma Unreferenced (Dimension);
      Bound : constant Flyology.Reflection.Predefined_Types.Integer_View :=
        Flyology.Reflection.Predefined_Types.To_View (1);
   begin
      if Item.Kind /= Zero_Last_Bounds then
         Flyology.Reflection.Value_Views.Route (Bound, Using);
      end if;
      if Item.Kind = Two_Last_Bounds then
         Flyology.Reflection.Value_Views.Route (Bound, Using);
      end if;
   end Observe_Last_Index;

   overriding
   procedure Observe_Elements
     (Item  : Array_Probe_View;
      Using : in out Flyology.Reflection.Value_Views.Element_Consumer'Class)
   is
      Element : constant Flyology.Reflection.Predefined_Types.Boolean_View :=
        Flyology.Reflection.Predefined_Types.To_View (True);
   begin
      if Item.Kind /= Zero_Elements then
         Using.Visit_Element (Element);
      end if;
      if Item.Kind = Two_Elements then
         Using.Visit_Element (Element);
      end if;
   end Observe_Elements;

   procedure Observe_Array_Probe
     (Item  : Array_Probe_Kind;
      Using : in out Flyology.Reflection.Value_Views.Value_Consumer'Class)
   is
      View : Array_Probe_View (Item);
   begin
      Flyology.Reflection.Value_Views.Route (View, Using);
   end Observe_Array_Probe;

   package Array_Probes is new
     Flyology_Serde_Reflection.Serialization_Adapters
       (Source_Type => Array_Probe_Kind,
        Limits      => Limits,
        Observe     => Observe_Array_Probe);

   type Variant_Probe_Kind is
     (One_Alternative,
      Maximum_Alternative,
      Failing_Child,
      Zero_Alternatives,
      Two_Alternatives,
      Announced_Two,
      Unrepresentable_Alternatives,
      Overlong_Alternative,
      Invalid_UTF_8_Alternative);

   type Variant_Probe_View (Kind : Variant_Probe_Kind) is
     new Flyology.Reflection.Value_Views.Value_View
     and Flyology.Reflection.Value_Views.Record_View
     and Flyology.Reflection.Value_Views.Variant_View
   with null record;

   overriding
   function Type_Of
     (Item : Variant_Probe_View)
      return Flyology.Reflection.Value_Views.Type_Reference;

   overriding
   procedure Dispatch
     (Item : Variant_Probe_View;
      To   : in out Flyology.Reflection.Value_Views.Value_Consumer'Class);

   overriding
   function Active_Component_Count
     (Item : Variant_Probe_View)
      return Flyology.Reflection.Value_Views.Cardinality;

   overriding
   procedure Observe_Components
     (Item  : Variant_Probe_View;
      Using : in out Flyology.Reflection.Value_Views.Component_Consumer'Class);

   overriding
   function Selected_Alternative_Count
     (Item : Variant_Probe_View)
      return Flyology.Reflection.Value_Views.Cardinality;

   overriding
   procedure Observe_Selected_Alternatives
     (Item  : Variant_Probe_View;
      Using : in out Flyology.Reflection.Value_Views.Variant_Consumer'Class);

   overriding
   function Type_Of
     (Item : Variant_Probe_View)
      return Flyology.Reflection.Value_Views.Type_Reference
   is
      pragma Unreferenced (Item);
   begin
      return Flyology.Reflection.Predefined_Types.Integer_Type;
   end Type_Of;

   overriding
   procedure Dispatch
     (Item : Variant_Probe_View;
      To   : in out Flyology.Reflection.Value_Views.Value_Consumer'Class) is
   begin
      To.Consume (Item);
   end Dispatch;

   overriding
   function Active_Component_Count
     (Item : Variant_Probe_View)
      return Flyology.Reflection.Value_Views.Cardinality
   is (Flyology.Reflection.Value_Views.Exact_Count
         (if Item.Kind = Failing_Child then 1 else 0));

   overriding
   procedure Observe_Components
     (Item  : Variant_Probe_View;
      Using : in out Flyology.Reflection.Value_Views.Component_Consumer'Class)
   is
      Declaration :
        constant Flyology.Reflection.Value_Views.Declaration_Reference :=
          Views.Variant_Record_Component_1_Declaration;
   begin
      if Item.Kind = Failing_Child then
         declare
            Child : constant
              Flyology.Reflection.Predefined_Types.Character_View :=
                Flyology.Reflection.Predefined_Types.To_View ('x');
         begin
            Using.Visit_Component
              (Declaration,
               "bad",
               Flyology.Reflection.Value_Views.Variant_Component,
               Child);
         end;
      end if;
   end Observe_Components;

   overriding
   function Selected_Alternative_Count
     (Item : Variant_Probe_View)
      return Flyology.Reflection.Value_Views.Cardinality is
   begin
      case Item.Kind is
         when Announced_Two                =>
            return Flyology.Reflection.Value_Views.Exact_Count (2);

         when Unrepresentable_Alternatives =>
            return
              (Status =>
                 Flyology.Reflection.Value_Views.Count_Not_Representable);

         when others                       =>
            return Flyology.Reflection.Value_Views.Exact_Count (1);
      end case;
   end Selected_Alternative_Count;

   overriding
   procedure Observe_Selected_Alternatives
     (Item  : Variant_Probe_View;
      Using : in out Flyology.Reflection.Value_Views.Variant_Consumer'Class)
   is
      Part        :
        constant Flyology.Reflection.Value_Views.Declaration_Reference :=
          Views.Variant_Record_Variant_Part_Declaration;
      Alternative :
        constant Flyology.Reflection.Value_Views.Declaration_Reference :=
          Views.Variant_Record_Alternative_1_Declaration;
   begin
      case Item.Kind is
         when One_Alternative | Failing_Child              =>
            declare
               Name : constant String (10 .. 15) := "choice";
            begin
               Using.Visit_Selected_Alternative (Part, Alternative, Name);
            end;

         when Maximum_Alternative                          =>
            declare
               Name : constant String (10 .. 137) := [others => 'a'];
            begin
               Using.Visit_Selected_Alternative (Part, Alternative, Name);
            end;

         when Zero_Alternatives                            =>
            null;

         when Two_Alternatives                             =>
            Using.Visit_Selected_Alternative (Part, Alternative, "one");
            Using.Visit_Selected_Alternative (Part, Alternative, "two");

         when Overlong_Alternative                         =>
            declare
               Name : constant String (1 .. 129) := [others => 'a'];
            begin
               Using.Visit_Selected_Alternative (Part, Alternative, Name);
            end;

         when Invalid_UTF_8_Alternative                    =>
            declare
               Name : constant String := Character'Val (16#C0#) & "x";
            begin
               Using.Visit_Selected_Alternative (Part, Alternative, Name);
            end;

         when Announced_Two | Unrepresentable_Alternatives =>
            raise Program_Error with "alternative observer must not run";
      end case;
   end Observe_Selected_Alternatives;

   procedure Observe_Variant_Probe
     (Item  : Variant_Probe_Kind;
      Using : in out Flyology.Reflection.Value_Views.Value_Consumer'Class)
   is
      View : Variant_Probe_View (Item);
   begin
      Flyology.Reflection.Value_Views.Route (View, Using);
   end Observe_Variant_Probe;

   package Variant_Probes is new
     Flyology_Serde_Reflection.Serialization_Adapters
       (Source_Type => Variant_Probe_Kind,
        Limits      => Limits,
        Observe     => Observe_Variant_Probe);

   package Zero_Text_Variant_Probes is new
     Flyology_Serde_Reflection.Serialization_Adapters
       (Source_Type => Variant_Probe_Kind,
        Limits      => Zero_Text_Limits,
        Observe     => Observe_Variant_Probe);

   type Record_Probe_Kind is
     (Zero_Components, Two_Components, Fail_In_Second_Pass_Child);

   Record_Probe_Observe_Calls : Natural := 0;

   type Raising_Boolean_View is
     new Flyology.Reflection.Value_Views.Value_View
     and Flyology.Reflection.Value_Views.Boolean_View
   with null record;

   overriding
   function Type_Of
     (Item : Raising_Boolean_View)
      return Flyology.Reflection.Value_Views.Type_Reference;

   overriding
   procedure Dispatch
     (Item : Raising_Boolean_View;
      To   : in out Flyology.Reflection.Value_Views.Value_Consumer'Class);

   overriding
   function Boolean_Value (Item : Raising_Boolean_View) return Boolean;

   overriding
   function Type_Of
     (Item : Raising_Boolean_View)
      return Flyology.Reflection.Value_Views.Type_Reference
   is
      pragma Unreferenced (Item);
   begin
      return Flyology.Reflection.Predefined_Types.Boolean_Type;
   end Type_Of;

   overriding
   procedure Dispatch
     (Item : Raising_Boolean_View;
      To   : in out Flyology.Reflection.Value_Views.Value_Consumer'Class) is
   begin
      To.Consume (Item);
   end Dispatch;

   overriding
   function Boolean_Value (Item : Raising_Boolean_View) return Boolean is
      pragma Unreferenced (Item);
   begin
      if Record_Probe_Observe_Calls = 2 then
         raise Program_Error with "injected second-pass child failure";
      end if;
      return True;
   end Boolean_Value;

   type Record_Probe_View (Kind : Record_Probe_Kind) is
     new Flyology.Reflection.Value_Views.Value_View
     and Flyology.Reflection.Value_Views.Record_View
   with null record;

   overriding
   function Type_Of
     (Item : Record_Probe_View)
      return Flyology.Reflection.Value_Views.Type_Reference;

   overriding
   procedure Dispatch
     (Item : Record_Probe_View;
      To   : in out Flyology.Reflection.Value_Views.Value_Consumer'Class);

   overriding
   function Active_Component_Count
     (Item : Record_Probe_View)
      return Flyology.Reflection.Value_Views.Cardinality;

   overriding
   procedure Observe_Components
     (Item  : Record_Probe_View;
      Using : in out Flyology.Reflection.Value_Views.Component_Consumer'Class);

   overriding
   function Type_Of
     (Item : Record_Probe_View)
      return Flyology.Reflection.Value_Views.Type_Reference
   is
      pragma Unreferenced (Item);
   begin
      return Views.Snapshot_Type;
   end Type_Of;

   overriding
   procedure Dispatch
     (Item : Record_Probe_View;
      To   : in out Flyology.Reflection.Value_Views.Value_Consumer'Class) is
   begin
      To.Consume (Item);
   end Dispatch;

   overriding
   function Active_Component_Count
     (Item : Record_Probe_View)
      return Flyology.Reflection.Value_Views.Cardinality
   is
      pragma Unreferenced (Item);
   begin
      return Flyology.Reflection.Value_Views.Exact_Count (1);
   end Active_Component_Count;

   overriding
   procedure Observe_Components
     (Item  : Record_Probe_View;
      Using : in out Flyology.Reflection.Value_Views.Component_Consumer'Class)
   is
      Declaration :
        constant Flyology.Reflection.Value_Views.Declaration_Reference :=
          Views.Snapshot_Component_1_Declaration;
      Child       : Raising_Boolean_View;
   begin
      case Item.Kind is
         when Zero_Components           =>
            null;

         when Two_Components            =>
            Using.Visit_Component
              (Declaration,
               "first",
               Flyology.Reflection.Value_Views.Regular_Component,
               Child);
            Using.Visit_Component
              (Declaration,
               "second",
               Flyology.Reflection.Value_Views.Regular_Component,
               Child);

         when Fail_In_Second_Pass_Child =>
            Using.Visit_Component
              (Declaration,
               "value",
               Flyology.Reflection.Value_Views.Regular_Component,
               Child);
      end case;
   end Observe_Components;

   procedure Observe_Record_Probe
     (Item  : Record_Probe_Kind;
      Using : in out Flyology.Reflection.Value_Views.Value_Consumer'Class)
   is
      View : Record_Probe_View (Item);
   begin
      Record_Probe_Observe_Calls := Record_Probe_Observe_Calls + 1;
      Flyology.Reflection.Value_Views.Route (View, Using);
   end Observe_Record_Probe;

   package Record_Probes is new
     Flyology_Serde_Reflection.Serialization_Adapters
       (Source_Type => Record_Probe_Kind,
        Limits      => Limits,
        Observe     => Observe_Record_Probe);

   procedure Assert_JSON (Writer : JSON.Allocating_Writer; Expected : String)
   is
   begin
      pragma Assert (Writer.Is_Complete);
      pragma Assert (Writer.Output = Expected);
   end Assert_JSON;

begin
   pragma Assert (Mark_Assertion_Execution);
   if not Assertion_Probe_Ran then
      raise Program_Error with "integration tests require assertion checking";
   end if;

   declare
      Writer : JSON.Allocating_Writer;
      Error  : Errors.Error_Info;
   begin
      Booleans.Serialize (True, Writer, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      Assert_JSON (Writer, "true");
   end;

   declare
      Writer : JSON.Allocating_Writer;
      Error  : Errors.Error_Info;
   begin
      Shades.Serialize (Subjects.Light, Writer, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      Assert_JSON (Writer, """Light""");
   end;

   declare
      Writer : CBOR.Allocating_Writer;
      Error  : Errors.Error_Info;
   begin
      Shades.Serialize (Subjects.Light, Writer, Error);
      pragma Assert (Error.Code = Errors.No_Error and then Writer.Is_Complete);
      pragma
        Assert
          (Writer.Output
             = Ada.Streams.Stream_Element_Array'
                 [16#65#,
                  Character'Pos ('L'),
                  Character'Pos ('i'),
                  Character'Pos ('g'),
                  Character'Pos ('h'),
                  Character'Pos ('t')]);
   end;

   declare
      Writer : JSON.Allocating_Writer;
      Error  : Errors.Error_Info;
   begin
      Offsets.Serialize (-42, Writer, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      Assert_JSON (Writer, "-42");
   end;

   declare
      Writer : CBOR.Allocating_Writer;
      Error  : Errors.Error_Info;
   begin
      Offsets.Serialize (-42, Writer, Error);
      pragma Assert (Error.Code = Errors.No_Error and then Writer.Is_Complete);
      pragma
        Assert
          (Writer.Output = Ada.Streams.Stream_Element_Array'[16#38#, 16#29#]);
   end;

   declare
      Writer : JSON.Allocating_Writer;
      Error  : Errors.Error_Info;
   begin
      Words.Serialize (Subjects.Word'Last, Writer, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      Assert_JSON (Writer, "1099511627775");
   end;

   for Kind in Signed_Probe_Kind range Canonical_Zero .. Negative_Minimum loop
      declare
         Writer : JSON.Allocating_Writer;
         Error  : Errors.Error_Info;
      begin
         Signed_Probe_Observe_Calls := 0;
         Signed_Probes.Serialize (Kind, Writer, Error);
         pragma Assert (Error.Code = Errors.No_Error);
         pragma Assert (Signed_Probe_Observe_Calls = 2);
         Assert_JSON
           (Writer,
            (if Kind = Canonical_Zero
             then "0"
             elsif Kind = Positive_Maximum
             then "9223372036854775807"
             else "-9223372036854775808"));
      end;
   end loop;

   declare
      Writer : JSON.Allocating_Writer;
      Error  : Errors.Error_Info;
   begin
      Modular_Probes.Serialize (Modular_Maximum, Writer, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      Assert_JSON (Writer, "18446744073709551615");
   end;

   for Kind in Modular_Probe_Kind range Modular_Overflow .. Modular_Negative
   loop
      declare
         Writer : CBOR.Allocating_Writer;
         Error  : Errors.Error_Info;
      begin
         Modular_Probes.Serialize (Kind, Writer, Error);
         pragma
           Assert
             (Error.Code
                = (if Kind = Modular_Overflow
                   then Errors.Unsupported_Value
                   else Errors.Application_Error));
         pragma
           Assert
             (not Writer.Is_Complete
                and then Writer.State = Serialization.Poisoned);
      end;
   end loop;

   declare
      Writer : JSON.Allocating_Writer;
      Error  : Errors.Error_Info;
      Item   : constant Subjects.Shade_Array :=
        [1 => Subjects.Light, 2 => Subjects.Dark];
   begin
      Shade_Arrays.Serialize (Item, Writer, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      Assert_JSON (Writer, "[""Light"",""Dark""]");
   end;

   declare
      Writer : CBOR.Allocating_Writer;
      Error  : Errors.Error_Info;
      Item   : constant Subjects.Shade_Array :=
        [1 => Subjects.Light, 2 => Subjects.Dark];
   begin
      Shade_Arrays.Serialize (Item, Writer, Error);
      pragma Assert (Error.Code = Errors.No_Error and then Writer.Is_Complete);
      pragma
        Assert
          (Writer.Output
             = Ada.Streams.Stream_Element_Array'
                 [16#82#,
                  16#65#,
                  Character'Pos ('L'),
                  Character'Pos ('i'),
                  Character'Pos ('g'),
                  Character'Pos ('h'),
                  Character'Pos ('t'),
                  16#64#,
                  Character'Pos ('D'),
                  Character'Pos ('a'),
                  Character'Pos ('r'),
                  Character'Pos ('k')]);
   end;

   for Kind in Array_Probe_Kind loop
      declare
         Writer : JSON.Allocating_Writer;
         Error  : Errors.Error_Info;
      begin
         Array_Probes.Serialize (Kind, Writer, Error);
         pragma
           Assert
             (Error.Code
                = (if Kind in
                       Unrepresentable_Element_Count
                         | Unrepresentable_Dimension_Length
                         | Rank_Two
                         | Wrong_Bound_Type
                         | Overflowing_Bound_Canonical_Text
                   then Errors.Unsupported_Value
                   else Errors.Application_Error));
         pragma
           Assert
             (not Writer.Is_Complete
                and then Writer.State = Serialization.Poisoned);
      end;
   end loop;

   declare
      Writer : JSON.Allocating_Writer;
      Error  : Errors.Error_Info;
      Item   : constant Subjects.Snapshot :=
        (Tone => Subjects.Light, Palette => [Subjects.Light, Subjects.Medium]);
   begin
      Snapshots.Serialize (Item, Writer, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      Assert_JSON
        (Writer, "{""Tone"":""Light"",""Palette"":[""Light"",""Medium""]}");
   end;

   declare
      Writer : CBOR.Allocating_Writer;
      Error  : Errors.Error_Info;
      Item   : constant Subjects.Snapshot :=
        (Tone => Subjects.Light, Palette => [Subjects.Light, Subjects.Medium]);
   begin
      Snapshots.Serialize (Item, Writer, Error);
      pragma Assert (Error.Code = Errors.No_Error and then Writer.Is_Complete);
      pragma
        Assert
          (Writer.Output
             = Ada.Streams.Stream_Element_Array'
                 [16#A2#,
                  16#64#,
                  16#54#,
                  16#6F#,
                  16#6E#,
                  16#65#,
                  16#65#,
                  16#4C#,
                  16#69#,
                  16#67#,
                  16#68#,
                  16#74#,
                  16#67#,
                  16#50#,
                  16#61#,
                  16#6C#,
                  16#65#,
                  16#74#,
                  16#74#,
                  16#65#,
                  16#82#,
                  16#65#,
                  16#4C#,
                  16#69#,
                  16#67#,
                  16#68#,
                  16#74#,
                  16#66#,
                  16#4D#,
                  16#65#,
                  16#64#,
                  16#69#,
                  16#75#,
                  16#6D#]);
   end;

   declare
      Item : constant Subjects.Snapshot :=
        (Tone => Subjects.Light, Palette => [Subjects.Light, Subjects.Medium]);
      Reflected_JSON  : JSON.Allocating_Writer;
      Static_JSON     : JSON.Allocating_Writer;
      Reflected_CBOR  : CBOR.Allocating_Writer;
      Static_CBOR     : CBOR.Allocating_Writer;
      Reflected_Error : Errors.Error_Info;
      Static_Error    : Errors.Error_Info;
   begin
      Snapshots.Serialize (Item, Reflected_JSON, Reflected_Error);
      Static_Snapshots.Serialize (Item, Static_JSON, Static_Error);
      pragma
        Assert
          (Reflected_Error.Code = Errors.No_Error
             and then Static_Error.Code = Errors.No_Error
             and then Reflected_JSON.Output = Static_JSON.Output);

      Errors.Reset (Reflected_Error);
      Errors.Reset (Static_Error);
      Snapshots.Serialize (Item, Reflected_CBOR, Reflected_Error);
      Static_Snapshots.Serialize (Item, Static_CBOR, Static_Error);
      pragma
        Assert
          (Reflected_Error.Code = Errors.No_Error
             and then Static_Error.Code = Errors.No_Error
             and then Reflected_CBOR.Output = Static_CBOR.Output);
   end;

   declare
      Writer : JSON.Allocating_Writer;
      Error  : Errors.Error_Info;
      Item   : constant Subjects.Discriminated_Snapshot :=
        (Tone => Subjects.Medium, Palette => [Subjects.Light, Subjects.Dark]);
   begin
      Discriminated_Snapshots.Serialize (Item, Writer, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      Assert_JSON
        (Writer, "{""Tone"":""Medium"",""Palette"":[""Light"",""Dark""]}");
   end;

   declare
      Writer : JSON.Allocating_Writer;
      Error  : Errors.Error_Info;
      Item   : constant Subjects.Variant_Record :=
        (Tone => Subjects.Dark, Dark_Value => Subjects.Medium);
   begin
      Variants.Serialize (Item, Writer, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      Assert_JSON
        (Writer, "[""others"",{""Tone"":""Dark"",""Dark_Value"":""Medium""}]");
   end;

   declare
      Writer : CBOR.Allocating_Writer;
      Error  : Errors.Error_Info;
      Item   : constant Subjects.Variant_Record :=
        (Tone => Subjects.Dark, Dark_Value => Subjects.Medium);
   begin
      Variants.Serialize (Item, Writer, Error);
      pragma Assert (Error.Code = Errors.No_Error and then Writer.Is_Complete);
      pragma
        Assert
          (Writer.Output
             = Ada.Streams.Stream_Element_Array'
                 [16#82#,
                  16#66#,
                  16#6F#,
                  16#74#,
                  16#68#,
                  16#65#,
                  16#72#,
                  16#73#,
                  16#A2#,
                  16#64#,
                  16#54#,
                  16#6F#,
                  16#6E#,
                  16#65#,
                  16#64#,
                  16#44#,
                  16#61#,
                  16#72#,
                  16#6B#,
                  16#6A#,
                  16#44#,
                  16#61#,
                  16#72#,
                  16#6B#,
                  16#5F#,
                  16#56#,
                  16#61#,
                  16#6C#,
                  16#75#,
                  16#65#,
                  16#66#,
                  16#4D#,
                  16#65#,
                  16#64#,
                  16#69#,
                  16#75#,
                  16#6D#]);
   end;

   declare
      Item : constant Subjects.Variant_Record :=
        (Tone => Subjects.Dark, Dark_Value => Subjects.Medium);
      Reflected_JSON  : JSON.Allocating_Writer;
      Static_JSON     : JSON.Allocating_Writer;
      Reflected_CBOR  : CBOR.Allocating_Writer;
      Static_CBOR     : CBOR.Allocating_Writer;
      Reflected_Error : Errors.Error_Info;
      Static_Error    : Errors.Error_Info;
   begin
      Variants.Serialize (Item, Reflected_JSON, Reflected_Error);
      Static_Variants.Serialize (Item, Static_JSON, Static_Error);
      pragma
        Assert
          (Reflected_Error.Code = Errors.No_Error
             and then Static_Error.Code = Errors.No_Error
             and then Reflected_JSON.Output = Static_JSON.Output);

      Errors.Reset (Reflected_Error);
      Errors.Reset (Static_Error);
      Variants.Serialize (Item, Reflected_CBOR, Reflected_Error);
      Static_Variants.Serialize (Item, Static_CBOR, Static_Error);
      pragma
        Assert
          (Reflected_Error.Code = Errors.No_Error
             and then Static_Error.Code = Errors.No_Error
             and then Reflected_CBOR.Output = Static_CBOR.Output);
   end;

   --  Non-one-based and multidimensional arrays are structurally observable
   --  but not losslessly representable by this first Serde mapping.
   declare
      Writer : JSON.Allocating_Writer;
      Error  : Errors.Error_Info;
      Item   : constant Subjects.Shade_Array :=
        [3 => Subjects.Light, 4 => Subjects.Dark];
   begin
      Shade_Arrays.Serialize (Item, Writer, Error);
      pragma Assert (Error.Code = Errors.Unsupported_Value);
      pragma
        Assert
          (not Writer.Is_Complete
             and then Writer.State = Serialization.Poisoned);
   end;

   declare
      Writer : JSON.Allocating_Writer;
      Error  : Errors.Error_Info;
      Item   : Subjects.Shade_Array (1 .. 0);
   begin
      Shade_Arrays.Serialize (Item, Writer, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      Assert_JSON (Writer, "[]");
   end;

   declare
      Writer : JSON.Allocating_Writer;
      Error  : Errors.Error_Info;
      Item   : constant Subjects.Shade_Array :=
        [-1 => Subjects.Light, 0 => Subjects.Dark];
   begin
      Shade_Arrays.Serialize (Item, Writer, Error);
      pragma Assert (Error.Code = Errors.Unsupported_Value);
      pragma Assert (Writer.State = Serialization.Poisoned);
      JSON.Reset (Writer);
      Shades.Serialize (Subjects.Light, Writer, Error);
      pragma Assert (Error.Code = Errors.Unsupported_Value);
      Errors.Reset (Error);
      Shades.Serialize (Subjects.Light, Writer, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      Assert_JSON (Writer, """Light""");
   end;

   declare
      Writer : CBOR.Allocating_Writer;
      Error  : Errors.Error_Info;
      Item   : Subjects.Shade_Array (0 .. -1);
   begin
      Shade_Arrays.Serialize (Item, Writer, Error);
      pragma Assert (Error.Code = Errors.Unsupported_Value);
      pragma Assert (Writer.State = Serialization.Poisoned);
   end;

   declare
      Writer : CBOR.Allocating_Writer;
      Error  : Errors.Error_Info;
      Item   : constant Subjects.Shade_Matrix (1 .. 1, 1 .. 1) :=
        [1 => [1 => Subjects.Light]];
   begin
      Shade_Matrices.Serialize (Item, Writer, Error);
      pragma Assert (Error.Code = Errors.Unsupported_Value);
      pragma
        Assert
          (not Writer.Is_Complete
             and then Writer.State = Serialization.Poisoned);
   end;

   declare
      Item   : constant Subjects.Shade_Array :=
        [1 => Subjects.Light, 2 => Subjects.Dark];
      Writer : JSON.Allocating_Writer;
      Error  : Errors.Error_Info;
   begin
      Item_Limited_Arrays.Serialize (Item, Writer, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
      pragma Assert (Writer.State = Serialization.Poisoned);
   end;

   declare
      Item   : constant Subjects.Snapshot :=
        (Tone => Subjects.Light, Palette => [Subjects.Light, Subjects.Dark]);
      Writer : JSON.Allocating_Writer;
      Error  : Errors.Error_Info;
   begin
      Depth_Limited_Snapshots.Serialize (Item, Writer, Error);
      pragma Assert (Error.Code = Errors.Depth_Exceeded);
      pragma Assert (Writer.State = Serialization.Poisoned);
   end;

   declare
      Item   : constant Subjects.Snapshot :=
        (Tone => Subjects.Light, Palette => [Subjects.Light, Subjects.Dark]);
      Writer : CBOR.Allocating_Writer;
      Error  : Errors.Error_Info;
   begin
      Event_Limited_Snapshots.Serialize (Item, Writer, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
      pragma Assert (Writer.State = Serialization.Poisoned);
   end;

   declare
      Writer : JSON.Allocating_Writer;
      Error  : Errors.Error_Info;
   begin
      Text_Limited_Shades.Serialize (Subjects.Light, Writer, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
      pragma Assert (Writer.State = Serialization.Poisoned);
   end;

   declare
      Writer : JSON.Allocating_Writer;
      Error  : Errors.Error_Info;
   begin
      Characters.Serialize ('A', Writer, Error);
      pragma Assert (Error.Code = Errors.Unsupported_Value);
      pragma
        Assert
          (not Writer.Is_Complete
             and then Writer.State = Serialization.Poisoned);
   end;

   declare
      Writer : JSON.Allocating_Writer;
      Error  : Errors.Error_Info;
      Item   : constant Subjects.Limited_Item := Subjects.Make_Limited (7);
   begin
      Limited_Items.Serialize (Item, Writer, Error);
      pragma Assert (Error.Code = Errors.Unsupported_Value);
      pragma
        Assert
          (not Writer.Is_Complete
             and then Writer.State = Serialization.Poisoned);
      pragma Assert (Subjects.Marker_Of (Item) = 7);
   end;

   declare
      Writer : JSON.Allocating_Writer;
      Error  : Errors.Error_Info;
   begin
      Errors.Fail (Error, Errors.Application_Error);
      Shades.Serialize (Subjects.Light, Writer, Error);
      pragma Assert (Error.Code = Errors.Application_Error);
      pragma Assert (Writer.State = Serialization.Ready);
   end;

   declare
      Writer : JSON.Allocating_Writer;
      Error  : Errors.Error_Info;
   begin
      Writer.Abort_Document;
      Shades.Serialize (Subjects.Light, Writer, Error);
      pragma Assert (Error.Code = Errors.Invalid_State);
      pragma Assert (Writer.State = Serialization.Poisoned);
   end;

   declare
      Writer : CBOR.Allocating_Writer;
      Error  : Errors.Error_Info;
      Item   : constant Subjects.Standard_Scalar_Record :=
        (Enabled => True, Symbol => 'A');
   begin
      Standard_Scalar_Records.Serialize (Item, Writer, Error);
      pragma Assert (Error.Code = Errors.Unsupported_Value);
      pragma Assert (Error.Path_Length = 1);
      pragma
        Assert
          (Error.Path (1).Kind = Errors.Field_Element
             and then Error.Path (1).Name_Length = 6
             and then Error.Path (1).Name (1 .. 6) = "Symbol");
      pragma Assert (Writer.State = Serialization.Poisoned);
   end;

   for Kind in Signed_Probe_Kind range Negative_Zero_Text .. Two_Root_Callbacks
   loop
      declare
         Writer : JSON.Allocating_Writer;
         Error  : Errors.Error_Info;
      begin
         Signed_Probe_Observe_Calls := 0;
         Signed_Probes.Serialize (Kind, Writer, Error);
         pragma
           Assert
             (Error.Code
                = (if Kind in Positive_Overflow | Negative_Overflow
                   then Errors.Unsupported_Value
                   else Errors.Application_Error));
         pragma
           Assert
             (not Writer.Is_Complete
                and then Writer.State = Serialization.Poisoned);
         pragma Assert (Signed_Probe_Observe_Calls = 1);
      end;
   end loop;

   declare
      Writer : JSON.Allocating_Writer;
      Error  : Errors.Error_Info;
      Raised : Boolean := False;
   begin
      Signed_Probe_Observe_Calls := 0;
      begin
         Signed_Probes.Serialize (Raise_After_Root, Writer, Error);
      exception
         when Program_Error =>
            Raised := True;
      end;
      pragma Assert (Raised);
      pragma
        Assert
          (not Writer.Is_Complete
             and then Writer.State = Serialization.Poisoned
             and then Error.Path_Length = 0);
      pragma Assert (Signed_Probe_Observe_Calls = 1);
   end;

   declare
      Writer : JSON.Allocating_Writer;
      Error  : Errors.Error_Info;
   begin
      Bad_Supplements.Serialize (True, Writer, Error);
      pragma Assert (Error.Code = Errors.Application_Error);
      pragma
        Assert
          (not Writer.Is_Complete
             and then Writer.State = Serialization.Poisoned);
   end;

   for Kind in Reflection_Failure_Kind loop
      declare
         Writer : CBOR.Allocating_Writer;
         Error  : Errors.Error_Info;
      begin
         Reflection_Failures.Serialize (Kind, Writer, Error);
         pragma Assert (Error.Code = Errors.Application_Error);
         pragma
           Assert
             (not Writer.Is_Complete
                and then Writer.State = Serialization.Poisoned);
      end;
   end loop;

   declare
      Writer : JSON.Allocating_Writer;
      Error  : Errors.Error_Info;
   begin
      Variant_Probes.Serialize (One_Alternative, Writer, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      Assert_JSON (Writer, "[""choice"",{}]");
   end;

   declare
      Writer : JSON.Allocating_Writer;
      Error  : Errors.Error_Info;
      Name   : constant String (20 .. 147) := [others => 'a'];
   begin
      Variant_Probes.Serialize (Maximum_Alternative, Writer, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      Assert_JSON (Writer, "[""" & Name & """,{}]");
   end;

   declare
      Writer : JSON.Allocating_Writer;
      Error  : Errors.Error_Info;
   begin
      Zero_Text_Variant_Probes.Serialize (One_Alternative, Writer, Error);
      pragma
        Assert
          (Error.Code = Errors.Capacity_Exceeded
             and then Error.Path_Length = 0
             and then Writer.State = Serialization.Poisoned);
      JSON.Reset (Writer);
      Errors.Reset (Error);
      Booleans.Serialize (True, Writer, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      Assert_JSON (Writer, "true");
   end;

   declare
      Writer : JSON.Allocating_Writer;
      Error  : Errors.Error_Info;
   begin
      Variant_Probes.Serialize (Failing_Child, Writer, Error);
      pragma
        Assert
          (Error.Code = Errors.Unsupported_Value
             and then Error.Path_Length = 2
             and then Error.Path (1).Kind = Errors.Alternative_Element
             and then Error.Path (1).Name_Length = 6
             and then Error.Path (1).Name (1 .. 6) = "choice"
             and then Error.Path (2).Kind = Errors.Field_Element
             and then Error.Path (2).Name_Length = 3
             and then Error.Path (2).Name (1 .. 3) = "bad"
             and then Writer.State = Serialization.Poisoned);
      JSON.Reset (Writer);
      Errors.Reset (Error);
      Booleans.Serialize (True, Writer, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      Assert_JSON (Writer, "true");
   end;

   for Kind in
     Variant_Probe_Kind range Zero_Alternatives .. Invalid_UTF_8_Alternative
   loop
      declare
         Writer : CBOR.Allocating_Writer;
         Error  : Errors.Error_Info;
      begin
         Variant_Probes.Serialize (Kind, Writer, Error);
         pragma
           Assert
             (Error.Code
                = (if Kind = Unrepresentable_Alternatives
                   then Errors.Unsupported_Value
                   elsif Kind = Overlong_Alternative
                   then Errors.Capacity_Exceeded
                   elsif Kind = Invalid_UTF_8_Alternative
                   then Errors.Invalid_Text
                   else Errors.Application_Error));
         pragma
           Assert
             (not Writer.Is_Complete
                and then Writer.State = Serialization.Poisoned);
      end;
   end loop;

   for Kind in Record_Probe_Kind range Zero_Components .. Two_Components loop
      declare
         Writer : JSON.Allocating_Writer;
         Error  : Errors.Error_Info;
      begin
         Record_Probe_Observe_Calls := 0;
         Record_Probes.Serialize (Kind, Writer, Error);
         pragma Assert (Error.Code = Errors.Application_Error);
         pragma Assert (Record_Probe_Observe_Calls = 1);
         pragma
           Assert
             (not Writer.Is_Complete
                and then Writer.State = Serialization.Poisoned);
      end;
   end loop;

   declare
      Writer : JSON.Allocating_Writer;
      Error  : Errors.Error_Info;
      Raised : Boolean := False;
   begin
      Record_Probe_Observe_Calls := 0;
      begin
         Record_Probes.Serialize (Fail_In_Second_Pass_Child, Writer, Error);
      exception
         when Program_Error =>
            Raised := True;
      end;
      pragma Assert (Raised and then Record_Probe_Observe_Calls = 2);
      pragma
        Assert
          (not Writer.Is_Complete
             and then Writer.State = Serialization.Poisoned
             and then Error.Path_Length = 0);
   end;

   pragma Assert (Interfaces.Integer_64'First = -9_223_372_036_854_775_808);
end Reflection_Serialization_Tests;
