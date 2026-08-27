private package Flyology_Serde.Fixed_Array_Test_Hooks is
   Enabled : constant Boolean := False;

   procedure Before_Candidate
   with
     Import,
     Convention    => Ada,
     External_Name => "flyology_serde_disabled_fixed_array_candidate";
end Flyology_Serde.Fixed_Array_Test_Hooks;
