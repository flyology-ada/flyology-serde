package body Flyology_Serde.JSON_Event_Driver_Test_Hooks is
   Armed                   : Boolean := False;
   Armed_Point             : Failure_Point := Before_Step;
   Armed_Skip              : Natural := 0;
   Boolean_Override_Armed  : Boolean := False;
   Boolean_Override_Value  : Boolean := False;
   Source_Override_Armed   : Boolean := False;
   Source_Override_Skip    : Natural := 0;
   Source_Override_Value   : Natural := 0;
   Kind_Override_Armed     : Boolean := False;
   Kind_Override_Skip      : Natural := 0;
   Kind_Override_Value     : Natural := 0;
   Payload_Override_Armed  : Boolean := False;
   Payload_Override_Skip   : Natural := 0;
   Fragment_Override_Armed : Boolean := False;
   Fragment_Override_Skip  : Natural := 0;
   Fragment_Raw_Value      : Ada.Streams.Stream_Element := 0;
   Fragment_Decoded_Value  : Ada.Streams.Stream_Element := 0;
   Form_Override_Armed     : Boolean := False;
   Form_Override_Skip      : Natural := 0;
   Form_Override_Value     : Natural := 0;
   Classifications         : Natural := 0;
   Frame_Operations        : Natural := 0;
   Step_Attempts           : Natural := 0;
   Decoded_Copies          : Natural := 0;
   Skip_Trace_Start        : Natural := 0;
   Inspected_Source_Units  : Natural := 0;
   Aborts                  : Natural := 0;

   procedure Add (Counter : in out Natural; Units : Natural := 1) is
   begin
      if Units > Natural'Last - Counter then
         Counter := Natural'Last;
      else
         Counter := Counter + Units;
      end if;
   end Add;

   procedure Disarm is
   begin
      Armed := False;
      Armed_Point := Before_Step;
      Armed_Skip := 0;
      Boolean_Override_Armed := False;
      Boolean_Override_Value := False;
      Source_Override_Armed := False;
      Source_Override_Skip := 0;
      Source_Override_Value := 0;
      Kind_Override_Armed := False;
      Kind_Override_Skip := 0;
      Kind_Override_Value := 0;
      Payload_Override_Armed := False;
      Payload_Override_Skip := 0;
      Fragment_Override_Armed := False;
      Fragment_Override_Skip := 0;
      Fragment_Raw_Value := 0;
      Fragment_Decoded_Value := 0;
      Form_Override_Armed := False;
      Form_Override_Skip := 0;
      Form_Override_Value := 0;
   end Disarm;

   procedure Arm (Point : Failure_Point) is
   begin
      Disarm;
      Armed_Point := Point;
      Armed := True;
   end Arm;

   procedure Arm_After
     (Point : Failure_Point; Matching_Calls_To_Skip : Natural) is
   begin
      Disarm;
      Armed_Point := Point;
      Armed_Skip := Matching_Calls_To_Skip;
      Armed := True;
   end Arm_After;

   procedure Raise_If_Armed (Point : Failure_Point) is
   begin
      if Point in Before_Step | Before_Finish_Step then
         Add (Step_Attempts);
      end if;
      if Armed and then Point = Armed_Point then
         if Armed_Skip > 0 then
            Armed_Skip := Armed_Skip - 1;
         else
            Armed := False;
            raise Constraint_Error with "injected JSON driver failure";
         end if;
      end if;
   end Raise_If_Armed;

   procedure Arm_Boolean_Override (Value : Boolean) is
   begin
      Disarm;
      Boolean_Override_Value := Value;
      Boolean_Override_Armed := True;
   end Arm_Boolean_Override;

   procedure Apply_Boolean_Override (Value : in out Boolean) is
   begin
      if Boolean_Override_Armed then
         Value := Boolean_Override_Value;
         Boolean_Override_Armed := False;
      end if;
   end Apply_Boolean_Override;

   procedure Arm_Source_Offset_Override
     (Summaries_To_Skip : Natural; Value : Natural) is
   begin
      Disarm;
      Source_Override_Skip := Summaries_To_Skip;
      Source_Override_Value := Value;
      Source_Override_Armed := True;
   end Arm_Source_Offset_Override;

   procedure Apply_Source_Offset_Override (Value : in out Natural) is
   begin
      if Source_Override_Armed and then Source_Override_Skip > 0 then
         Source_Override_Skip := Source_Override_Skip - 1;
      elsif Source_Override_Armed then
         Value := Source_Override_Value;
         Source_Override_Armed := False;
      end if;
   end Apply_Source_Offset_Override;

   procedure Arm_Kind_Override (Value : Natural) is
   begin
      Disarm;
      Kind_Override_Skip := 0;
      Kind_Override_Value := Value;
      Kind_Override_Armed := True;
   end Arm_Kind_Override;

   procedure Arm_Kind_Override_After
     (Summaries_To_Skip : Natural; Value : Natural) is
   begin
      Disarm;
      Kind_Override_Skip := Summaries_To_Skip;
      Kind_Override_Value := Value;
      Kind_Override_Armed := True;
   end Arm_Kind_Override_After;

   procedure Apply_Kind_Override (Value : in out Natural) is
   begin
      if Kind_Override_Armed and then Kind_Override_Skip > 0 then
         Kind_Override_Skip := Kind_Override_Skip - 1;
      elsif Kind_Override_Armed then
         Value := Kind_Override_Value;
         Kind_Override_Armed := False;
      end if;
   end Apply_Kind_Override;

   procedure Arm_Payload_Contamination (Summaries_To_Skip : Natural) is
   begin
      Disarm;
      Payload_Override_Skip := Summaries_To_Skip;
      Payload_Override_Armed := True;
   end Arm_Payload_Contamination;

   procedure Apply_Payload_Contamination
     (Has_Raw_Byte    : in out Boolean;
      Raw_Byte        : in out Ada.Streams.Stream_Element;
      Decoded_Length  : in out Natural;
      Decoded         : in out Ada.Streams.Stream_Element_Array;
      Boolean_Payload : in out Boolean) is
   begin
      if Payload_Override_Armed and then Payload_Override_Skip > 0 then
         Payload_Override_Skip := Payload_Override_Skip - 1;
      elsif Payload_Override_Armed then
         Has_Raw_Byte := True;
         Raw_Byte := 1;
         Decoded_Length := 1;
         Decoded (Decoded'First) := 1;
         Boolean_Payload := True;
         Payload_Override_Armed := False;
      end if;
   end Apply_Payload_Contamination;

   procedure Arm_Fragment_Byte_Override
     (Summaries_To_Skip : Natural;
      Raw_Byte          : Ada.Streams.Stream_Element;
      Decoded_Byte      : Ada.Streams.Stream_Element) is
   begin
      Disarm;
      Fragment_Override_Skip := Summaries_To_Skip;
      Fragment_Raw_Value := Raw_Byte;
      Fragment_Decoded_Value := Decoded_Byte;
      Fragment_Override_Armed := True;
   end Arm_Fragment_Byte_Override;

   procedure Apply_Fragment_Byte_Override
     (Raw_Byte : in out Ada.Streams.Stream_Element;
      Decoded  : in out Ada.Streams.Stream_Element_Array) is
   begin
      if Fragment_Override_Armed and then Fragment_Override_Skip > 0 then
         Fragment_Override_Skip := Fragment_Override_Skip - 1;
      elsif Fragment_Override_Armed then
         Raw_Byte := Fragment_Raw_Value;
         Decoded (Decoded'First) := Fragment_Decoded_Value;
         Fragment_Override_Armed := False;
      end if;
   end Apply_Fragment_Byte_Override;

   procedure Arm_Decoded_Form_Override
     (Summaries_To_Skip : Natural; Value : Natural) is
   begin
      Disarm;
      Form_Override_Skip := Summaries_To_Skip;
      Form_Override_Value := Value;
      Form_Override_Armed := True;
   end Arm_Decoded_Form_Override;

   procedure Apply_Decoded_Form_Override (Value : in out Natural) is
   begin
      if Form_Override_Armed and then Form_Override_Skip > 0 then
         Form_Override_Skip := Form_Override_Skip - 1;
      elsif Form_Override_Armed then
         Value := Form_Override_Value;
         Form_Override_Armed := False;
      end if;
   end Apply_Decoded_Form_Override;

   procedure Reset_Work_Counts is
   begin
      Classifications := 0;
      Frame_Operations := 0;
      Step_Attempts := 0;
      Decoded_Copies := 0;
      Skip_Trace_Start := 0;
      Inspected_Source_Units := 0;
   end Reset_Work_Counts;

   procedure Begin_Skip_Trace (Start_Offset : Natural) is
   begin
      Skip_Trace_Start := Start_Offset;
      Inspected_Source_Units := 0;
   end Begin_Skip_Trace;

   procedure Note_Skip_Inspection (End_Exclusive : Natural) is
      Span : Natural;
   begin
      if End_Exclusive < Skip_Trace_Start then
         Inspected_Source_Units := Natural'Last;
      else
         Span := End_Exclusive - Skip_Trace_Start;
         if Span > Inspected_Source_Units then
            Inspected_Source_Units := Span;
         end if;
      end if;
   end Note_Skip_Inspection;

   procedure Note_Skip_Classification (Units : Natural := 1) is
   begin
      Add (Classifications, Units);
   end Note_Skip_Classification;

   procedure Note_Skip_Frame_Operation is
   begin
      Add (Frame_Operations);
   end Note_Skip_Frame_Operation;

   procedure Note_Decoded_Copy (Units : Natural) is
   begin
      Add (Decoded_Copies, Units);
   end Note_Decoded_Copy;

   function Skip_Classifications return Natural
   is (Classifications);

   function Skip_Frame_Operations return Natural
   is (Frame_Operations);

   function Parser_Step_Attempts return Natural
   is (Step_Attempts);

   function Decoded_Octets_Copied return Natural
   is (Decoded_Copies);

   function Skip_Inspected_Source_Units return Natural
   is (Inspected_Source_Units);

   procedure Reset_Abort_Count is
   begin
      Aborts := 0;
   end Reset_Abort_Count;

   procedure Note_Abort is
   begin
      Aborts := Aborts + 1;
   end Note_Abort;

   function Abort_Count return Natural
   is (Aborts);
end Flyology_Serde.JSON_Event_Driver_Test_Hooks;
