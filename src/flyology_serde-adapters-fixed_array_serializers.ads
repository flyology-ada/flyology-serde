with Flyology_Serde.Errors;
with Flyology_Serde.Serialization;

generic
   type Index_Type is (<>);
   type Element_Type is private;
   type Array_Type is array (Index_Type) of Element_Type;
   with procedure Serialize_Element
     (Item  : Element_Type;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info);
package Flyology_Serde.Adapters.Fixed_Array_Serializers is
   --  Serialize_Element emits exactly one value and leaves its successful
   --  path nesting balanced. The array emits every component in Ada component
   --  order; omission requires a different explicit adapter.
   procedure Serialize_Value
     (Item  : Array_Type;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info);
end Flyology_Serde.Adapters.Fixed_Array_Serializers;
