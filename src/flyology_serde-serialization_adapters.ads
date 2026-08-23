with Flyology_Serde.Errors;
with Flyology_Serde.Serialization;

--  Statically binds one Ada source type to its serialization traversal.

generic
   type Source_Type (<>) is limited private;
   with
     procedure Serialize_Value
       (Item  : Source_Type;
        Into  : in out Serialization.Serializer'Class;
        Error : in out Errors.Error_Info);
package Flyology_Serde.Serialization_Adapters is
   subtype Source is Source_Type;

   --  An already-latched status makes the root call a strict no-op: the
   --  application hook is not invoked and no backend event is attempted.
   procedure Serialize
     (Item  : Source;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info);
end Flyology_Serde.Serialization_Adapters;
