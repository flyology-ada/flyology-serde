package Flyology_Serde.Deserializers.JSON.Testing is
   function Syntax_Input_Offset (Self : Reader) return Natural;
   function Budget_Input_Consumed (Self : Reader) return Natural;

   procedure Assert_JSON_Event_Contract;
   procedure Assert_JSON_Event_Summaries;
   procedure Assert_JSON_Single_Step_Driver;
   procedure Assert_JSON_Driver_Lifecycle;
end Flyology_Serde.Deserializers.JSON.Testing;
