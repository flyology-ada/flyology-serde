with Flyology_Serde.Deserialization;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;
with Flyology_Serde.Serialization;

generic
   type Source_Type (<>) is limited private;
   type Builder_Type (<>) is limited private;
   type Field_Ordinal is (<>);
   Type_Name                     : String;
   Maximum_Type_Name_Length      : Positive;
   Maximum_Fields                : Positive;
   Maximum_Field_Name_Length     : Positive;
   Maximum_Aliases_Per_Field     : Natural;
   with function Primary_Name (Field : Field_Ordinal) return String;
   with function Alias_Count (Field : Field_Ordinal) return Natural;
   with
     function Alias_Name
       (Field : Field_Ordinal; Position : Positive) return String;
   with
     function Matches_Field
       (Field : Field_Ordinal; Name : String) return Boolean;
   with
     procedure Serialize_Field
       (Item  : Source_Type;
        Field : Field_Ordinal;
        Into  : in out Serialization.Serializer'Class;
        Error : in out Errors.Error_Info);
   with
     procedure Deserialize_Field
       (From      : in out Deserialization.Deserializer'Class;
        Target    : in out Builder_Type;
        Field     : Field_Ordinal;
        Replacing : Boolean;
        Policy    : Policies.Decode_Policy;
        Error     : in out Errors.Error_Info);
   with
     procedure Apply_Missing
       (Target  : in out Builder_Type;
        Field   : Field_Ordinal;
        Policy  : Policies.Decode_Policy;
        Applied : out Boolean;
        Error   : in out Errors.Error_Info);
   with
     procedure Finish_Candidate
       (Target : in out Builder_Type; Error : in out Errors.Error_Info);
package Flyology_Serde.Adapters.Records is
   --  Metadata functions must be stable and nonallocating for an operation.
   --  Every primary and declared alias must be valid UTF-8, unique, and match
   --  only its own ordinal. The adapter validates this before its first event.

   --  Serialize_Field emits exactly one value. Every ordinal is emitted in
   --  declaration order; omission requires a different explicit adapter.
   procedure Serialize_Value
     (Item  : Source_Type;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info);

   --  Deserialize_Field consumes exactly one value. When Replacing is true,
   --  it must replace the candidate field without publishing it and leave the
   --  whole candidate safe for rollback after any failure.
   --
   --  Apply_Missing runs in ordinal order after End_Record. Applied = False
   --  must not mutate the field. An overlay may choose serialization/default
   --  policy, but cannot alter a Known structural fact, override a mandatory
   --  Unknown or Unsupported fact, or grant representation visibility.
   procedure Deserialize_Candidate
     (From   : in out Deserialization.Deserializer'Class;
      Target : in out Builder_Type;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info);
end Flyology_Serde.Adapters.Records;
