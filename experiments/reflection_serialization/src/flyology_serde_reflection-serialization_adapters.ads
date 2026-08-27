with Flyology.Reflection.Value_Views;
with Flyology_Serde.Errors;
with Flyology_Serde.Serialization;

--  Experimental generic bridge from one generated Reflection Observe root to
--  the format-neutral Serde serializer. This unit is not yet installed.

generic
   type Source_Type (<>) is limited private;
   Limits : Flyology_Serde.Serialization.Serialization_Limits;
   with
     procedure Observe
       (Item  : Source_Type;
        Using : in out Flyology.Reflection.Value_Views.Value_Consumer'Class);
package Flyology_Serde_Reflection.Serialization_Adapters is
   procedure Serialize
     (Item  : Source_Type;
      Into  : in out Flyology_Serde.Serialization.Serializer'Class;
      Error : in out Flyology_Serde.Errors.Error_Info);
end Flyology_Serde_Reflection.Serialization_Adapters;
