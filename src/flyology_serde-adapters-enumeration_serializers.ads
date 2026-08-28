with Flyology_Serde.Errors;
with Flyology_Serde.Serialization;

generic
   type Value_Type is (<>);
   Type_Name                   : String;
   Maximum_Type_Name_Length    : Positive;
   Maximum_Literals            : Positive;
   Maximum_Literal_Name_Length : Positive;
   with function Primary_Name (Value : Value_Type) return String;
package Flyology_Serde.Adapters.Enumeration_Serializers is
   --  Metadata must remain stable and nonallocating for one operation. Every
   --  primary name must be valid UTF-8 and unique. The adapter validates and
   --  reobserves all names before its first output event.
   procedure Serialize_Value
     (Item  : Value_Type;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info);
end Flyology_Serde.Adapters.Enumeration_Serializers;
