with Flyology_Serde.Fixed_Array_Test_Hooks;

package body Flyology_Serde.Fixed_Array_Testing is
   package Hooks renames Flyology_Serde.Fixed_Array_Test_Hooks;

   procedure Arm_Candidate_Failure is
   begin
      Hooks.Arm_Candidate_Failure;
   end Arm_Candidate_Failure;

   procedure Disarm is
   begin
      Hooks.Disarm;
   end Disarm;

   function Candidate_Attempts return Natural
   is (Hooks.Candidate_Attempts);
end Flyology_Serde.Fixed_Array_Testing;
