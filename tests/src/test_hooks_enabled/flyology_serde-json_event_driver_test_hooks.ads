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
   procedure Arm_After
     (Point : Failure_Point; Matching_Calls_To_Skip : Natural);
   procedure Raise_If_Armed (Point : Failure_Point);
   procedure Arm_Boolean_Override (Value : Boolean);
   procedure Apply_Boolean_Override (Value : in out Boolean);
   procedure Arm_Source_Offset_Override
     (Summaries_To_Skip : Natural; Value : Natural);
   procedure Apply_Source_Offset_Override (Value : in out Natural);
   procedure Arm_Kind_Override (Value : Natural);
   procedure Arm_Kind_Override_After
     (Summaries_To_Skip : Natural; Value : Natural);
   procedure Apply_Kind_Override (Value : in out Natural);
   procedure Arm_Payload_Contamination (Summaries_To_Skip : Natural);
   procedure Apply_Payload_Contamination
     (Has_Raw_Byte    : in out Boolean;
      Raw_Byte        : in out Ada.Streams.Stream_Element;
      Decoded_Length  : in out Natural;
      Decoded         : in out Ada.Streams.Stream_Element_Array;
      Boolean_Payload : in out Boolean);
   procedure Arm_Fragment_Byte_Override
     (Summaries_To_Skip : Natural;
      Raw_Byte          : Ada.Streams.Stream_Element;
      Decoded_Byte      : Ada.Streams.Stream_Element);
   procedure Apply_Fragment_Byte_Override
     (Raw_Byte : in out Ada.Streams.Stream_Element;
      Decoded  : in out Ada.Streams.Stream_Element_Array);
   procedure Arm_Decoded_Form_Override
     (Summaries_To_Skip : Natural; Value : Natural);
   procedure Apply_Decoded_Form_Override (Value : in out Natural);
   procedure Reset_Work_Counts;
   procedure Begin_Skip_Trace (Start_Offset : Natural);
   procedure Note_Skip_Inspection (End_Exclusive : Natural);
   procedure Note_Skip_Classification (Units : Natural := 1);
   procedure Note_Skip_Frame_Operation;
   procedure Note_Decoded_Copy (Units : Natural);
   function Skip_Classifications return Natural;
   function Skip_Frame_Operations return Natural;
   function Parser_Step_Attempts return Natural;
   function Decoded_Octets_Copied return Natural;
   function Skip_Inspected_Source_Units return Natural;
   procedure Reset_Abort_Count;
   procedure Note_Abort;
   function Abort_Count return Natural;
end Flyology_Serde.JSON_Event_Driver_Test_Hooks;
