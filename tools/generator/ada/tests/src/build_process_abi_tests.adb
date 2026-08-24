with Ada.Command_Line;
with Flyology_Serde_Generator.Build_Process_ABI_Test_Facade;

procedure Build_Process_ABI_Tests is
begin
   if Ada.Command_Line.Argument_Count /= 1 then
      raise Program_Error with "expected the signal-child executable path";
   end if;
   Flyology_Serde_Generator.Build_Process_ABI_Test_Facade.Run
     (Ada.Command_Line.Argument (1));
end Build_Process_ABI_Tests;
