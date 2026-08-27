package body Flyology_Serde.JSON_Event_Driver_Test_Hooks is
   Armed                  : Boolean := False;
   Armed_Point            : Failure_Point := Before_Step;
   Boolean_Override_Armed : Boolean := False;
   Boolean_Override_Value : Boolean := False;
   Source_Override_Armed  : Boolean := False;
   Source_Override_Skip   : Natural := 0;
   Source_Override_Value  : Natural := 0;
   Kind_Override_Armed    : Boolean := False;
   Kind_Override_Value    : Natural := 0;
   Payload_Override_Armed : Boolean := False;
   Payload_Override_Skip  : Natural := 0;
   Aborts                 : Natural := 0;

   procedure Disarm is
   begin
      Armed := False;
      Armed_Point := Before_Step;
      Boolean_Override_Armed := False;
      Boolean_Override_Value := False;
      Source_Override_Armed := False;
      Source_Override_Skip := 0;
      Source_Override_Value := 0;
      Kind_Override_Armed := False;
      Kind_Override_Value := 0;
      Payload_Override_Armed := False;
      Payload_Override_Skip := 0;
   end Disarm;

   procedure Arm (Point : Failure_Point) is
   begin
      Disarm;
      Armed_Point := Point;
      Armed := True;
   end Arm;

   procedure Raise_If_Armed (Point : Failure_Point) is
   begin
      if Armed and then Point = Armed_Point then
         Armed := False;
         raise Constraint_Error with "injected JSON driver failure";
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
      Kind_Override_Value := Value;
      Kind_Override_Armed := True;
   end Arm_Kind_Override;

   procedure Apply_Kind_Override (Value : in out Natural) is
   begin
      if Kind_Override_Armed then
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
