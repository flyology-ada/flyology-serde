package body Flyology_Serde_Generator.Build_Budgets is
   use type Interfaces.Unsigned_64;

   procedure Advance_Owner_Sequence
     (Sequence : in out Owner_Sequence_State;
      Into     : out Owner_Token;
      Minted   : out Boolean)
   is
   begin
      Into := Invalid_Owner;
      Minted := False;
      if Sequence.Exhausted then
         return;
      end if;
      if Sequence.Last_Issued.High = Interfaces.Unsigned_64'Last
        and then Sequence.Last_Issued.Low = Interfaces.Unsigned_64'Last
      then
         Sequence.Exhausted := True;
         return;
      end if;

      if Sequence.Last_Issued.Low = Interfaces.Unsigned_64'Last then
         Sequence.Last_Issued.High := Sequence.Last_Issued.High + 1;
         Sequence.Last_Issued.Low := 0;
      else
         Sequence.Last_Issued.Low := Sequence.Last_Issued.Low + 1;
      end if;
      Into := Sequence.Last_Issued;
      Minted := True;
      if Sequence.Last_Issued.High = Interfaces.Unsigned_64'Last
        and then Sequence.Last_Issued.Low = Interfaces.Unsigned_64'Last
      then
         Sequence.Exhausted := True;
      end if;
   exception
      when others =>
         Into := Invalid_Owner;
         Minted := False;
         Sequence.Exhausted := True;
   end Advance_Owner_Sequence;

   protected Owner_Tokens is
      procedure Mint (Into : out Owner_Token; Minted : out Boolean);
   private
      Sequence : Owner_Sequence_State;
   end Owner_Tokens;

   protected body Owner_Tokens is
      procedure Mint (Into : out Owner_Token; Minted : out Boolean) is
      begin
         Advance_Owner_Sequence (Sequence, Into, Minted);
      exception
         when others =>
            Into := Invalid_Owner;
            Minted := False;
            Sequence.Exhausted := True;
      end Mint;
   end Owner_Tokens;

   procedure Apply_Initialization
     (With_Limits     : Limits;
      Candidate       : Owner_Token;
      Owner_Available : Boolean;
      Into            : in out Budget;
      Initialized     : out Boolean)
   is
   begin
      Initialized := False;
      if Into.Generation = Interfaces.Unsigned_64'Last then
         Into.State := Failed;
         Into.Session_Valid := False;
         return;
      end if;

      if Into.Owner = Invalid_Owner then
         if not Owner_Available or else Candidate = Invalid_Owner then
            Into.State := Failed;
            Into.Session_Valid := False;
            return;
         end if;
         Into.Owner := Candidate;
      end if;

      Into.Generation := Into.Generation + 1;
      Into.Ceiling_Input := With_Limits.Maximum_Input_Bytes;
      Into.Ceiling_Work := With_Limits.Maximum_Work_Units;
      Into.Used_Input := 0;
      Into.Used_Work := 0;
      Into.State := Active;
      Into.Session_Valid := True;
      Initialized := True;
   exception
      when others =>
         Into.State := Failed;
         Into.Session_Valid := False;
         Initialized := False;
   end Apply_Initialization;

   procedure Initialize
     (With_Limits : Limits;
      Into        : in out Budget;
      Initialized : out Boolean)
   is
      Candidate : Owner_Token := Invalid_Owner;
      Minted    : Boolean := False;
   begin
      if Into.Owner = Invalid_Owner and then Into.Generation /= Interfaces.Unsigned_64'Last then
         Owner_Tokens.Mint (Candidate, Minted);
      end if;
      Apply_Initialization (With_Limits, Candidate, Minted, Into, Initialized);
   exception
      when others =>
         Into.State := Failed;
         Into.Session_Valid := False;
         Initialized := False;
   end Initialize;

   function Current_Session (Value : aliased Budget) return Session_Tag is
   begin
      if Value.Session_Valid and then Value.State = Active then
         return (Owner => Value.Owner, Generation => Value.Generation);
      end if;
      return (Owner => Invalid_Owner, Generation => 0);
   exception
      when others =>
         return (Owner => Invalid_Owner, Generation => 0);
   end Current_Session;

   function Matches (Value : aliased Budget; Expected : Session_Tag) return Boolean is
     (Value.Session_Valid
      and then Expected.Owner /= Invalid_Owner
      and then Expected.Owner = Value.Owner
      and then Expected.Generation = Value.Generation);

   procedure Reserve
     (Value   : in out Budget;
      Kind    : Category;
      Amount  : Charge_Amount;
      Granted : out Boolean)
   is
   begin
      Granted := False;
      if Value.State /= Active then
         return;
      end if;

      case Kind is
         when Input_Bytes =>
            if Value.Used_Input <= Value.Ceiling_Input
              and then Amount <= Value.Ceiling_Input - Value.Used_Input
            then
               Value.Used_Input := Value.Used_Input + Amount;
               Granted := True;
            else
               Value.State := Exhausted;
            end if;
         when Work_Units =>
            if Value.Used_Work <= Value.Ceiling_Work
              and then Amount <= Value.Ceiling_Work - Value.Used_Work
            then
               Value.Used_Work := Value.Used_Work + Amount;
               Granted := True;
            else
               Value.State := Exhausted;
            end if;
      end case;
   exception
      when others =>
         Value.State := Failed;
         Granted := False;
   end Reserve;

   procedure Poison (Value : in out Budget) is
   begin
      if Value.State = Active then
         Value.State := Failed;
      end if;
   exception
      when others =>
         null;
   end Poison;

   function Current_State (Value : Budget) return Budget_State is
     (Value.State);

   function Current_Usage (Value : Budget) return Usage is
     (Input_Bytes => Value.Used_Input,
      Work_Units  => Value.Used_Work);
end Flyology_Serde_Generator.Build_Budgets;
