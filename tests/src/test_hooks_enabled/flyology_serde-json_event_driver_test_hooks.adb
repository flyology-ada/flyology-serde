package body Flyology_Serde.JSON_Event_Driver_Test_Hooks is
   Armed       : Boolean := False;
   Armed_Point : Failure_Point := Before_Step;

   procedure Arm (Point : Failure_Point) is
   begin
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
end Flyology_Serde.JSON_Event_Driver_Test_Hooks;
