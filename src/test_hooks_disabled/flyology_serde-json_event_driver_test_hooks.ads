with Ada.Streams;

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

   procedure Arm_After
     (Point : Failure_Point; Matching_Calls_To_Skip : Natural)
   with
     Import,
     Convention    => Ada,
     External_Name => "flyology_serde_disabled_json_driver_arm_after";

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

   procedure Arm_Kind_Override (Value : Natural)
   with
     Import,
     Convention    => Ada,
     External_Name => "flyology_serde_disabled_json_driver_kind_arm";

   procedure Apply_Kind_Override (Value : in out Natural)
   with
     Import,
     Convention    => Ada,
     External_Name => "flyology_serde_disabled_json_driver_kind_apply";

   procedure Arm_Payload_Contamination (Summaries_To_Skip : Natural)
   with
     Import,
     Convention    => Ada,
     External_Name => "flyology_serde_disabled_json_driver_payload_arm";

   procedure Apply_Payload_Contamination
     (Has_Raw_Byte    : in out Boolean;
      Raw_Byte        : in out Ada.Streams.Stream_Element;
      Decoded_Length  : in out Natural;
      Decoded         : in out Ada.Streams.Stream_Element_Array;
      Boolean_Payload : in out Boolean)
   with
     Import,
     Convention    => Ada,
     External_Name => "flyology_serde_disabled_json_driver_payload_apply";

   procedure Arm_Fragment_Byte_Override
     (Summaries_To_Skip : Natural;
      Raw_Byte          : Ada.Streams.Stream_Element;
      Decoded_Byte      : Ada.Streams.Stream_Element)
   with
     Import,
     Convention    => Ada,
     External_Name => "flyology_serde_disabled_json_driver_fragment_arm";

   procedure Apply_Fragment_Byte_Override
     (Raw_Byte : in out Ada.Streams.Stream_Element;
      Decoded  : in out Ada.Streams.Stream_Element_Array)
   with
     Import,
     Convention    => Ada,
     External_Name => "flyology_serde_disabled_json_driver_fragment_apply";

   procedure Arm_Decoded_Form_Override
     (Summaries_To_Skip : Natural; Value : Natural)
   with
     Import,
     Convention    => Ada,
     External_Name => "flyology_serde_disabled_json_driver_form_arm";

   procedure Apply_Decoded_Form_Override (Value : in out Natural)
   with
     Import,
     Convention    => Ada,
     External_Name => "flyology_serde_disabled_json_driver_form_apply";

   procedure Reset_Abort_Count
   with
     Import,
     Convention    => Ada,
     External_Name => "flyology_serde_disabled_json_driver_abort_reset";

   procedure Note_Abort
   with
     Import,
     Convention    => Ada,
     External_Name => "flyology_serde_disabled_json_driver_abort_note";

   function Abort_Count return Natural
   with
     Import,
     Convention    => Ada,
     External_Name => "flyology_serde_disabled_json_driver_abort_count";
end Flyology_Serde.JSON_Event_Driver_Test_Hooks;
