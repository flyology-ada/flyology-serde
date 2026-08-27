with Flyology_Serde.Adapters.Fixed_Arrays;
with Flyology_Serde.Deserialization;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;
with Flyology_Serde.Serialization;

procedure Limited_Fixed_Array_Client is
   type Index_Type is (Only);
   type Limited_Element is limited record
      Value : Integer := 0;
   end record;
   type Limited_Array is array (Index_Type) of Limited_Element;

   procedure Serialize_Element
     (Item  : Limited_Element;
      Into  : in out Flyology_Serde.Serialization.Serializer'Class;
      Error : in out Flyology_Serde.Errors.Error_Info)
   is null;

   procedure Deserialize_Element
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out Limited_Element;
      Policy : Flyology_Serde.Policies.Decode_Policy;
      Error  : in out Flyology_Serde.Errors.Error_Info)
   is null;

   package Rejected is new
     Flyology_Serde.Adapters.Fixed_Arrays
       (Index_Type          => Index_Type,
        Element_Type        => Limited_Element,
        Array_Type          => Limited_Array,
        Serialize_Element   => Serialize_Element,
        Deserialize_Element => Deserialize_Element);
begin
   null;
end Limited_Fixed_Array_Client;
