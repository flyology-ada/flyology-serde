with Flyology_Serde.Deserialization;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;
with Flyology_Serde.Serialization;

generic
   type Source_Type (<>) is limited private;
   type Builder_Type (<>) is limited private;
   Maximum_Entries          : Natural;
   --  True is a promise that every serialized and deserialized key has exactly
   --  logical Text_Value or Enumeration_Value kind. It does not mean that an
   --  arbitrary logical key is later rendered as text. False requires the
   --  backend's Arbitrary_Map_Keys capability.
   Keys_Use_Restricted_Kinds : Boolean;
   with function Entry_Count (Item : Source_Type) return Natural;
   with
     procedure Serialize_Entry
       (Item     : Source_Type;
        Position : Natural;
        Into     : in out Serialization.Serializer'Class;
        Error    : in out Errors.Error_Info);
   with
     procedure Begin_Candidate
       (Target : in out Builder_Type;
        Length : Serialization.Data_Model.Length_Information;
        Policy : Policies.Decode_Policy;
        Error  : in out Errors.Error_Info);
   with
     procedure Deserialize_Entry
       (From     : in out Deserialization.Deserializer'Class;
        Target   : in out Builder_Type;
        Position : Natural;
        Policy   : Policies.Decode_Policy;
        Error    : in out Errors.Error_Info);
   with
     procedure Finish_Candidate
       (Target : in out Builder_Type; Error : in out Errors.Error_Info);
package Flyology_Serde.Adapters.Maps is
   --  Deserialize_Entry owns duplicate-key detection and replacement for its
   --  unpublished candidate. When it rejects a decoded logical key as equal
   --  to an earlier key, it reports Duplicate_Key. Accepted or replacement
   --  duplicates do not report that status. The generic adds no implicit
   --  equality or duplicate policy.
   procedure Serialize_Value
     (Item  : Source_Type;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info);

   procedure Deserialize_Candidate
     (From   : in out Deserialization.Deserializer'Class;
      Target : in out Builder_Type;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info);
end Flyology_Serde.Adapters.Maps;
