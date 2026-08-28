with Flyology_Serde.Errors;
with Flyology_Serde.Serialization;

generic
   type Source_Type (<>) is limited private;
   type Field_Ordinal is (<>);
   Type_Name                 : String;
   Maximum_Type_Name_Length  : Positive;
   Maximum_Fields            : Positive;
   Maximum_Field_Name_Length : Positive;
   with function Primary_Name (Field : Field_Ordinal) return String;
   with procedure Serialize_Field
     (Item  : Source_Type;
      Field : Field_Ordinal;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info);
package Flyology_Serde.Adapters.Record_Serializers is
   --  Metadata must remain stable and nonallocating for one operation. Every
   --  primary name must be valid UTF-8 and unique. The adapter validates and
   --  reobserves all names before its first output event.
   --
   --  Serialize_Field emits exactly one value and leaves its successful path
   --  nesting balanced. Every ordinal is emitted in declaration order;
   --  omission requires a different explicit adapter.
   procedure Serialize_Value
     (Item  : Source_Type;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info);
end Flyology_Serde.Adapters.Record_Serializers;
