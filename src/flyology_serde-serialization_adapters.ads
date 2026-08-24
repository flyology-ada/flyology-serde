with Flyology_Serde.Errors;
with Flyology_Serde.Serialization;

--  Statically binds one Ada source type to its serialization traversal.

generic
   type Source_Type (<>) is limited private;
   Limits : Serialization.Serialization_Limits;
   with
     procedure Serialize_Value
       (Item  : Source_Type;
        Into  : in out Serialization.Serializer'Class;
        Error : in out Errors.Error_Info);
package Flyology_Serde.Serialization_Adapters is
   subtype Source is Source_Type;

   --  An already-latched status makes the root call a strict no-op. Otherwise
   --  the traversal runs first through a non-emitting validator configured
   --  from Into.Capabilities, then through Into, and finally finishes the
   --  document. A failure or exception aborts the owned serializer operation.
   --
   --  Serialize_Value and every callback it invokes must be repeatable and
   --  externally side-effect-free except for changes to Into and Error. Item,
   --  observers, iterators, and callback results must remain stable across
   --  both traversals. A caller that cannot satisfy this contract must first
   --  construct and serialize a stable snapshot.
   procedure Serialize
     (Item  : Source;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info);
end Flyology_Serde.Serialization_Adapters;
