private package Flyology_Serde.JSON_Event_Driver_Test_Hooks is
   Enabled : constant Boolean := False;

   type Failure_Point is
     (Before_Source_Copy,
      Before_Step,
      After_Step,
      Before_Finish_Step,
      After_Finish_Step);

   procedure Disarm
   with
     Import,
     Convention    => Ada,
     External_Name => "flyology_serde_disabled_json_driver_disarm";

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

   procedure Arm_Boolean_Override (Value : Boolean)
   with
     Import,
     Convention    => Ada,
     External_Name => "flyology_serde_disabled_json_driver_boolean_arm";

   procedure Apply_Boolean_Override (Value : in out Boolean)
   with
     Import,
     Convention    => Ada,
     External_Name => "flyology_serde_disabled_json_driver_boolean_apply";

   procedure Arm_Source_Offset_Override
     (Summaries_To_Skip : Natural; Value : Natural)
   with
     Import,
     Convention    => Ada,
     External_Name => "flyology_serde_disabled_json_driver_source_arm";

   procedure Apply_Source_Offset_Override (Value : in out Natural)
   with
     Import,
     Convention    => Ada,
     External_Name => "flyology_serde_disabled_json_driver_source_apply";
end Flyology_Serde.JSON_Event_Driver_Test_Hooks;
