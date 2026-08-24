with Ada.Containers.Ordered_Maps;
with Flyology_Serde.Deserialization;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;
with Flyology_Serde.Serialization;

generic
   type Key_Type is private;
   type Element_Type is private;
   with function "<" (Left, Right : Key_Type) return Boolean is <>;
   with function "=" (Left, Right : Element_Type) return Boolean is <>;
   Keys_Use_Restricted_Kinds : Boolean;
   with
     procedure Serialize_Key
       (Item  : Key_Type;
        Into  : in out Serialization.Serializer'Class;
        Error : in out Errors.Error_Info);
   with
     procedure Serialize_Element
       (Item  : Element_Type;
        Into  : in out Serialization.Serializer'Class;
        Error : in out Errors.Error_Info);
   with
     procedure Deserialize_Key
       (From   : in out Deserialization.Deserializer'Class;
        Target : in out Key_Type;
        Policy : Policies.Decode_Policy;
        Error  : in out Errors.Error_Info);
   with
     procedure Deserialize_Element
       (From   : in out Deserialization.Deserializer'Class;
        Target : in out Element_Type;
        Policy : Policies.Decode_Policy;
        Error  : in out Errors.Error_Info);
package Flyology_Serde.Adapters.Allocating_Maps is
   package Maps is new Ada.Containers.Ordered_Maps
     (Key_Type     => Key_Type,
      Element_Type => Element_Type,
      "<"          => "<",
      "="          => "=");

   subtype Value is Maps.Map;

   --  Serialization order is the stable comparator order. JSON renders the
   --  logical map as an array of key/value pairs; it is not lowered to a JSON
   --  object. The comparator must be stable, side-effect-free, nonraising, and
   --  a strict weak ordering. Comparator equivalence defines duplicate keys.
   procedure Serialize_Value
     (Item  : Value;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info);

   --  Target is an exclusively owned unpublished candidate with no live
   --  cursor, reference, or iterator. Keys and elements must be definite,
   --  nonlimited, and safe under standard-container copying. Controlled
   --  Initialize, Adjust, and Finalize operations must be nonraising and keep
   --  ownership correct for insertion, replacement, spare locals, and final
   --  cleanup. Limited, move-only, or identity-owning types use the general
   --  Maps builder seam instead.
   --
   --  Duplicate policy is Policy.Maps.Duplicate_Keys. Keep_First retains the
   --  first key/value and skips each later value. Keep_Last retains the first
   --  comparator-equivalent key object and replaces only its value. Target
   --  changes only after exact traversal and End_Map succeed; publication
   --  still belongs to the root transaction.
   procedure Deserialize_Candidate
     (From   : in out Deserialization.Deserializer'Class;
      Target : in out Value;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info);
end Flyology_Serde.Adapters.Allocating_Maps;
