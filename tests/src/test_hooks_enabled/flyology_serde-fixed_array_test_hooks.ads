private package Flyology_Serde.Fixed_Array_Test_Hooks is
   Enabled : constant Boolean := True;

   procedure Arm_Candidate_Failure;
   procedure Disarm;
   procedure Before_Candidate;
   function Candidate_Attempts return Natural;
end Flyology_Serde.Fixed_Array_Test_Hooks;
