with Interfaces;

procedure Flyology_Serde_Generator.Build_Budgets.Session_Exhaustion_Test is
   use type Interfaces.Unsigned_64;

   Value          : aliased Budget;
   Carry_Value    : aliased Budget;
   Terminal_Value : aliased Budget;
   Denied_Value   : aliased Budget;
   Again_Value    : aliased Budget;
   Carry_Sequence : Owner_Sequence_State :=
     (Last_Issued => (High => 7, Low => Interfaces.Unsigned_64'Last),
      Exhausted   => False);
   Terminal_Sequence : Owner_Sequence_State :=
     (Last_Issued =>
        (High => Interfaces.Unsigned_64'Last,
         Low  => Interfaces.Unsigned_64'Last - 1),
      Exhausted => False);
   Inconsistent_Sequence : Owner_Sequence_State :=
     (Last_Issued =>
        (High => Interfaces.Unsigned_64'Last,
         Low  => Interfaces.Unsigned_64'Last),
      Exhausted => False);
   Candidate   : Owner_Token := Invalid_Owner;
   Minted      : Boolean := False;
   Initialized : Boolean := False;
   Granted     : Boolean := False;
   Last_Tag    : Session_Tag;
   Saved_Ceiling_Input : Interfaces.Unsigned_64;
   Saved_Ceiling_Work  : Interfaces.Unsigned_64;
   Saved_Used_Input    : Interfaces.Unsigned_64;
   Saved_Used_Work     : Interfaces.Unsigned_64;
   Saved_Generation    : Interfaces.Unsigned_64;

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;
begin
   Initialize
     ((Maximum_Input_Bytes => 100, Maximum_Work_Units => 200), Value, Initialized);
   Require (Initialized, "initial session creation failed");
   Reserve (Value, Input_Bytes, 17, Granted);
   Require (Granted, "representative input charge failed");
   Reserve (Value, Work_Units, 29, Granted);
   Require (Granted, "representative work charge failed");

   Value.Generation := Interfaces.Unsigned_64'Last;
   Last_Tag := Current_Session (Value);
   Require (Matches (Value, Last_Tag), "last-generation tag did not match before reset");
   Saved_Ceiling_Input := Value.Ceiling_Input;
   Saved_Ceiling_Work := Value.Ceiling_Work;
   Saved_Used_Input := Value.Used_Input;
   Saved_Used_Work := Value.Used_Work;
   Saved_Generation := Value.Generation;

   Initialize
     ((Maximum_Input_Bytes => 7, Maximum_Work_Units => 11), Value, Initialized);
   Require (not Initialized, "generation exhaustion unexpectedly initialized");
   Require (Value.State = Failed, "generation exhaustion did not fail the budget");
   Require (not Value.Session_Valid, "generation exhaustion retained session validity");
   Require
     (not Matches (Value, Current_Session (Value)),
      "generation exhaustion minted a current session");
   Require (not Matches (Value, Last_Tag), "generation exhaustion retained the last tag");
   Require (Value.Ceiling_Input = Saved_Ceiling_Input, "input ceiling changed on exhaustion");
   Require (Value.Ceiling_Work = Saved_Ceiling_Work, "work ceiling changed on exhaustion");
   Require (Value.Used_Input = Saved_Used_Input, "input usage changed on exhaustion");
   Require (Value.Used_Work = Saved_Used_Work, "work usage changed on exhaustion");
   Require (Value.Generation = Saved_Generation, "generation changed on exhaustion");

   Advance_Owner_Sequence (Carry_Sequence, Candidate, Minted);
   Require (Minted, "owner-token carry failed");
   Require (Candidate.High = 8, "owner-token carry did not advance the high word");
   Require (Candidate.Low = 0, "owner-token carry did not clear the low word");
   Apply_Initialization
     ((Maximum_Input_Bytes => 1, Maximum_Work_Units => 1),
      Candidate,
      Minted,
      Carry_Value,
      Initialized);
   Require (Initialized, "carried owner token did not initialize a budget");

   Advance_Owner_Sequence (Terminal_Sequence, Candidate, Minted);
   Require (Minted, "terminal owner token was not issued");
   Require (Terminal_Sequence.Exhausted, "terminal issuance did not exhaust the sequence");
   Apply_Initialization
     ((Maximum_Input_Bytes => 13, Maximum_Work_Units => 17),
      Candidate,
      Minted,
      Terminal_Value,
      Initialized);
   Require (Initialized, "terminal owner token was not issued");
   Require
     (Terminal_Value.Owner =
        (High => Interfaces.Unsigned_64'Last, Low => Interfaces.Unsigned_64'Last),
      "terminal owner token had the wrong value");
   Apply_Initialization
     ((Maximum_Input_Bytes => 19, Maximum_Work_Units => 23),
      Invalid_Owner,
      False,
      Terminal_Value,
      Initialized);
   Require (Initialized, "owned budget could not reinitialize after source exhaustion");
   Require (Terminal_Value.Generation = 2, "owned budget generation did not advance");

   Denied_Value.Ceiling_Input := 31;
   Denied_Value.Ceiling_Work := 37;
   Denied_Value.Used_Input := 3;
   Denied_Value.Used_Work := 5;
   Denied_Value.Generation := 7;
   Advance_Owner_Sequence (Terminal_Sequence, Candidate, Minted);
   Require (not Minted, "exhausted owner sequence issued another token");
   Require (Candidate = Invalid_Owner, "exhausted owner sequence returned a token");
   Apply_Initialization
     ((Maximum_Input_Bytes => 41, Maximum_Work_Units => 43),
      Candidate,
      Minted,
      Denied_Value,
      Initialized);
   Require (not Initialized, "exhausted owner source initialized a new budget");
   Require (Denied_Value.State = Failed, "owner exhaustion did not fail the budget");
   Require (not Denied_Value.Session_Valid, "owner exhaustion retained session validity");
   Require (Denied_Value.Owner = Invalid_Owner, "owner exhaustion published a token");
   Require (Denied_Value.Ceiling_Input = 31, "owner exhaustion changed input ceiling");
   Require (Denied_Value.Ceiling_Work = 37, "owner exhaustion changed work ceiling");
   Require (Denied_Value.Used_Input = 3, "owner exhaustion changed input usage");
   Require (Denied_Value.Used_Work = 5, "owner exhaustion changed work usage");
   Require (Denied_Value.Generation = 7, "owner exhaustion changed generation");

   Advance_Owner_Sequence (Terminal_Sequence, Candidate, Minted);
   Require (not Minted, "owner sequence exhaustion was not sticky");
   Apply_Initialization
     ((Maximum_Input_Bytes => 47, Maximum_Work_Units => 53),
      Candidate,
      Minted,
      Again_Value,
      Initialized);
   Require (not Initialized, "owner source exhaustion was not sticky");
   Require (Again_Value.Owner = Invalid_Owner, "sticky owner exhaustion published a token");

   Advance_Owner_Sequence (Inconsistent_Sequence, Candidate, Minted);
   Require (not Minted, "inconsistent terminal sequence wrapped");
   Require (Candidate = Invalid_Owner, "inconsistent terminal sequence returned a token");
   Require (Inconsistent_Sequence.Exhausted, "inconsistent terminal sequence did not fail closed");
   Advance_Owner_Sequence (Inconsistent_Sequence, Candidate, Minted);
   Require (not Minted, "inconsistent terminal sequence failure was not sticky");
end Flyology_Serde_Generator.Build_Budgets.Session_Exhaustion_Test;
