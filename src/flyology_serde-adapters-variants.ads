with Flyology_Serde.Deserialization;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;
with Flyology_Serde.Serialization;

generic
   type Source_Type (<>) is limited private;
   type Builder_Type (<>) is limited private;
   type Alternative_Ordinal is (<>);
   type Field_Ordinal is (<>);
   Type_Name                         : String;
   Maximum_Type_Name_Length          : Positive;
   Maximum_Alternatives              : Positive;
   Maximum_Alternative_Name_Length   : Positive;
   Maximum_Aliases_Per_Alternative   : Natural;
   Maximum_Total_Fields              : Positive;
   Maximum_Fields_Per_Alternative    : Natural;
   Maximum_Field_Name_Length         : Positive;
   Maximum_Aliases_Per_Field         : Natural;
   with function Alternative_Name (Item : Alternative_Ordinal) return String;
   with function Alternative_Alias_Count (Item : Alternative_Ordinal) return Natural;
   with
     function Alternative_Alias_Name
       (Item : Alternative_Ordinal; Position : Positive) return String;
   with
     function Matches_Alternative
       (Item : Alternative_Ordinal; Name : String) return Boolean;
   with
     function Field_Belongs_To
       (Alternative : Alternative_Ordinal; Field : Field_Ordinal) return Boolean;
   with function Field_Name (Item : Field_Ordinal) return String;
   with function Field_Alias_Count (Item : Field_Ordinal) return Natural;
   with
     function Field_Alias_Name
       (Item : Field_Ordinal; Position : Positive) return String;
   with
     function Matches_Field
       (Item : Field_Ordinal; Name : String) return Boolean;
   with function Select_Alternative (Item : Source_Type) return Alternative_Ordinal;
   with
     procedure Serialize_Field
       (Item        : Source_Type;
        Alternative : Alternative_Ordinal;
        Field       : Field_Ordinal;
        Into        : in out Serialization.Serializer'Class;
        Error       : in out Errors.Error_Info);
   with
     procedure Begin_Alternative
       (Target      : in out Builder_Type;
        Alternative : Alternative_Ordinal;
        Policy      : Policies.Decode_Policy;
        Error       : in out Errors.Error_Info);
   with
     procedure Deserialize_Field
       (From        : in out Deserialization.Deserializer'Class;
        Target      : in out Builder_Type;
        Alternative : Alternative_Ordinal;
        Field       : Field_Ordinal;
        Replacing   : Boolean;
        Policy      : Policies.Decode_Policy;
        Error       : in out Errors.Error_Info);
   with
     procedure Apply_Missing
       (Target      : in out Builder_Type;
        Alternative : Alternative_Ordinal;
        Field       : Field_Ordinal;
        Policy      : Policies.Decode_Policy;
        Applied     : out Boolean;
        Error       : in out Errors.Error_Info);
   with
     procedure Finish_Candidate
       (Target      : in out Builder_Type;
        Alternative : Alternative_Ordinal;
        Error       : in out Errors.Error_Info);
package Flyology_Serde.Adapters.Variants is
   --  Every metadata, membership, name, selection, and matcher function must
   --  be stable and nonallocating for one operation. The adapter reuses the
   --  checked results during traversal.
   --
   --  Global field identity follows Ada declaration identity. Common fields
   --  share one ordinal across alternatives; distinct branch declarations do
   --  not share an ordinal merely because their presentation names match.
   procedure Serialize_Value
     (Item  : Source_Type;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info);

   --  Begin_Alternative stages only unpublished state and must leave outer
   --  rollback valid after any status or exception. Replacing has the strong
   --  record-adapter ownership contract. Structural overlays cannot invent or
   --  override discriminant/default facts or grant visibility.
   procedure Deserialize_Candidate
     (From   : in out Deserialization.Deserializer'Class;
      Target : in out Builder_Type;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info);
end Flyology_Serde.Adapters.Variants;
