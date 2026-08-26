private package Flyology_Serde.JSON_Event_Driver_Test_Hooks is
   Enabled : constant Boolean := False;

   type Failure_Point is
     (Before_Step, After_Step, Before_Finish_Step, After_Finish_Step);

   procedure Arm (Point : Failure_Point)
   with
     Import,
     Convention    => Ada,
     External_Name => "flyology_serde_disabled_json_driver_arm";

   procedure Raise_If_Armed (Point : Failure_Point)
   with
     Import,
     Convention    => Ada,
     External_Name => "flyology_serde_disabled_json_driver_raise";
end Flyology_Serde.JSON_Event_Driver_Test_Hooks;
