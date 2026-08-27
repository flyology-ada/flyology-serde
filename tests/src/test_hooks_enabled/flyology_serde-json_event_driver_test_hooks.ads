with Ada.Streams;

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
   procedure Arm_Kind_Override (Value : Natural);
   procedure Apply_Kind_Override (Value : in out Natural);
   procedure Arm_Payload_Contamination (Summaries_To_Skip : Natural);
   procedure Apply_Payload_Contamination
     (Has_Raw_Byte    : in out Boolean;
      Raw_Byte        : in out Ada.Streams.Stream_Element;
      Decoded_Length  : in out Natural;
      Decoded         : in out Ada.Streams.Stream_Element_Array;
      Boolean_Payload : in out Boolean);
   procedure Reset_Abort_Count;
   procedure Note_Abort;
   function Abort_Count return Natural;
end Flyology_Serde.JSON_Event_Driver_Test_Hooks;
