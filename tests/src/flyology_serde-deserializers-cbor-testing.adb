package body Flyology_Serde.Deserializers.CBOR.Testing is
   function Budget_Input_Consumed (Self : Reader) return Natural
   is (Budgets.Input_Consumed (Self.Budget));

   function Budget_Values_Consumed (Self : Reader) return Natural
   is (Budgets.Values_Consumed (Self.Budget));

   function Logical_Depth (Self : Reader) return Natural
   is (Self.Depth);

   function Budget_Depth (Self : Reader) return Natural
   is (Budgets.Depth (Self.Budget));
end Flyology_Serde.Deserializers.CBOR.Testing;
