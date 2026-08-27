private package Flyology_Serde.JSON_Event_Driver_Test_Hooks is
   Enabled : constant Boolean := True;

   type Failure_Point is
     (Before_Source_Copy,
      Before_Step,
      After_Step,
      Before_Finish_Step,
      After_Finish_Step);

   procedure Disarm;
   procedure Arm (Point : Failure_Point);
   procedure Raise_If_Armed (Point : Failure_Point);
   procedure Arm_Boolean_Override (Value : Boolean);
   procedure Apply_Boolean_Override (Value : in out Boolean);
   procedure Arm_Source_Offset_Override
     (Summaries_To_Skip : Natural; Value : Natural);
   procedure Apply_Source_Offset_Override (Value : in out Natural);
end Flyology_Serde.JSON_Event_Driver_Test_Hooks;
