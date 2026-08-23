with Flyology_Serde.Deserialization;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;
with Flyology_Serde.Serialization;

generic
   type Index_Type is (<>);
   type Element_Type is limited private;
   type Array_Type is array (Index_Type range <>) of Element_Type;
   type Builder_Type (<>) is limited private;
   with
     procedure Serialize_Element
       (Item  : Element_Type;
        Into  : in out Serialization.Serializer'Class;
        Error : in out Errors.Error_Info);
   with
     procedure Begin_Candidate
       (Target : in out Builder_Type;
        Length : Natural;
        Policy : Policies.Decode_Policy;
        Error  : in out Errors.Error_Info);
   with
     procedure Append_Element
       (From     : in out Deserialization.Deserializer'Class;
        Target   : in out Builder_Type;
        Position : Natural;
        Policy   : Policies.Decode_Policy;
        Error    : in out Errors.Error_Info);
   with
     procedure Finish_Candidate
       (Target : in out Builder_Type; Error : in out Errors.Error_Info);
package Flyology_Serde.Adapters.Arrays is
   procedure Serialize_Value
     (Item  : Array_Type;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info);

   procedure Deserialize_Candidate
     (From   : in out Deserialization.Deserializer'Class;
      Target : in out Builder_Type;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info);
end Flyology_Serde.Adapters.Arrays;
