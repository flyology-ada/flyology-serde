package body Flyology_Serde.JSON_Event_Driver_Test_Hooks is
   Armed                  : Boolean := False;
   Armed_Point            : Failure_Point := Before_Step;
   Boolean_Override_Armed : Boolean := False;
   Boolean_Override_Value : Boolean := False;
   Source_Override_Armed  : Boolean := False;
   Source_Override_Skip   : Natural := 0;
   Source_Override_Value  : Natural := 0;

   procedure Disarm is
   begin
      Armed := False;
      Armed_Point := Before_Step;
      Boolean_Override_Armed := False;
      Boolean_Override_Value := False;
      Source_Override_Armed := False;
      Source_Override_Skip := 0;
      Source_Override_Value := 0;
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
end Flyology_Serde.JSON_Event_Driver_Test_Hooks;
