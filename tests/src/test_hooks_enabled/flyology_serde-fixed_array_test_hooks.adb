package body Flyology_Serde.Fixed_Array_Test_Hooks is
   Armed    : Boolean := False;
   Attempts : Natural := 0;

   procedure Arm_Candidate_Failure is
   begin
      Armed := True;
   end Arm_Candidate_Failure;

   procedure Disarm is
   begin
      Armed := False;
   end Disarm;

   procedure Before_Candidate is
   begin
      Attempts := Attempts + 1;
      if Armed then
         Armed := False;
         raise Storage_Error with "injected fixed-array candidate failure";
      end if;
   end Before_Candidate;

   function Candidate_Attempts return Natural
   is (Attempts);
end Flyology_Serde.Fixed_Array_Test_Hooks;
