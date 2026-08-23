with Flyology_Serde.Deserialization;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;
with Flyology_Serde.Serialization;

generic
   type Source_Type (<>) is limited private;
   type Builder_Type (<>) is limited private;
   type Alternative_Ordinal is (<>);
   Type_Name                         : String;
   Maximum_Type_Name_Length          : Positive;
   Maximum_Alternatives              : Positive;
   Maximum_Alternative_Name_Length   : Positive;
   Maximum_Aliases_Per_Alternative   : Natural;
   Maximum_Incoming_Field_Name_Length : Positive;
   with function Alternative_Name (Item : Alternative_Ordinal) return String;
   with function Alternative_Alias_Count (Item : Alternative_Ordinal) return Natural;
   with
     function Alternative_Alias_Name
       (Item : Alternative_Ordinal; Position : Positive) return String;
   with
     function Matches_Alternative
       (Item : Alternative_Ordinal; Name : String) return Boolean;
   with function Select_Alternative (Item : Source_Type) return Alternative_Ordinal;
   with
     procedure Begin_Alternative
       (Target      : in out Builder_Type;
        Alternative : Alternative_Ordinal;
        Policy      : Policies.Decode_Policy;
        Error       : in out Errors.Error_Info);
   with
     procedure Finish_Candidate
       (Target      : in out Builder_Type;
        Alternative : Alternative_Ordinal;
        Error       : in out Errors.Error_Info);
package Flyology_Serde.Adapters.Nullary_Variants is
   --  Every metadata, name, selection, and matcher function must be stable and
   --  nonallocating for one operation. The adapter reuses checked metadata.
   --
   --  Preserves the logical variant envelope with a zero-field payload. It is
   --  not an implicit enumeration mapping.
   procedure Serialize_Value
     (Item  : Source_Type;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info);

   --  Supplied payload fields are unknown and follow record unknown-field
   --  policy. Ignore consumes each complete value exactly once.
   --  Begin_Alternative stages only unpublished state and may acquire
   --  candidate resources; it and Finish_Candidate must leave outer rollback
   --  valid after any status or exception and must never mutate a constrained
   --  published value.
   procedure Deserialize_Candidate
     (From   : in out Deserialization.Deserializer'Class;
      Target : in out Builder_Type;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info);
end Flyology_Serde.Adapters.Nullary_Variants;
