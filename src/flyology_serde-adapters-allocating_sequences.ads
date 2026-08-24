with Ada.Containers.Vectors;
with Flyology_Serde.Deserialization;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;
with Flyology_Serde.Serialization;

generic
   type Element_Type is private;
   with function "=" (Left, Right : Element_Type) return Boolean is <>;
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
package Flyology_Serde.Adapters.Allocating_Sequences is
   package Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Element_Type,
      "="          => "=");

   subtype Value is Vectors.Vector;

   procedure Serialize_Value
     (Item  : Value;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info);

   --  Target is an exclusively owned unpublished candidate with no live
   --  cursor, reference, or iterator. Elements must be definite, nonlimited,
   --  and safe under standard-container copying. Reserve or growth may
   --  initialize and finalize spare capacity and copy existing elements;
   --  Append copies the fresh local element, which then finalizes. Controlled
   --  Initialize, Adjust, and Finalize operations must be nonraising and keep
   --  ownership correct for every such copy and spare value. Limited,
   --  move-only, or identity-owning values use the general builder seam
   --  instead. Target changes only after complete traversal and End_Sequence
   --  succeed; publication still belongs to the root transaction.
   procedure Deserialize_Candidate
     (From   : in out Deserialization.Deserializer'Class;
      Target : in out Value;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info);
end Flyology_Serde.Adapters.Allocating_Sequences;
