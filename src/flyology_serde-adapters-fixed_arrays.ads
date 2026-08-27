with Flyology_Serde.Deserialization;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;
with Flyology_Serde.Serialization;

generic
   type Index_Type is (<>);
   type Element_Type is private;
   type Array_Type is array (Index_Type) of Element_Type;
   with
     procedure Serialize_Element
       (Item  : Element_Type;
        Into  : in out Serialization.Serializer'Class;
        Error : in out Errors.Error_Info);
   with
     procedure Deserialize_Element
       (From   : in out Deserialization.Deserializer'Class;
        Target : in out Element_Type;
        Policy : Policies.Decode_Policy;
        Error  : in out Errors.Error_Info);
package Flyology_Serde.Adapters.Fixed_Arrays is
   procedure Serialize_Value
     (Item  : Array_Type;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info);

   --  Target is an unpublished candidate and changes only after exact
   --  cardinality and End_Sequence succeed. The local candidate is initialized
   --  from Target before Deserialize_Element is called, so an in-out element
   --  adapter may inspect the prior valid value. Element_Type must be a
   --  definite nonlimited type whose copy and final assignment are valid for
   --  this transaction. Controlled, resource-owning, or invariant-bearing
   --  elements that need explicit construction or cleanup require a staged
   --  builder adapter instead of this assignment seam.
   procedure Deserialize_Candidate
     (From   : in out Deserialization.Deserializer'Class;
      Target : in out Array_Type;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info);
end Flyology_Serde.Adapters.Fixed_Arrays;
