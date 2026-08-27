with Ada.Streams;
with Flyology_JSON.Errors;
with Flyology_JSON.Profiles;
with Flyology_Serde.Adapters.Unsigned_Integers;
with Flyology_Serde.Deserialization;
with Flyology_Serde.Deserialization_Adapters;
with Flyology_Serde.Deserializers.JSON.Event_Readers;
with Flyology_Serde.JSON_Event_Driver_Test_Hooks;
with Flyology_Serde.JSON_Preflights;
with Interfaces;

package body Flyology_Serde.Deserializers.JSON.Testing is
   package Parsing renames JSON_Event_Drivers.Parsing;
   package JSON_Errors renames Flyology_JSON.Errors;
   package Event_Readers renames
     Flyology_Serde.Deserializers.JSON.Event_Readers;
   package Preflights renames Flyology_Serde.JSON_Preflights;
   package Test_Hooks renames Flyology_Serde.JSON_Event_Driver_Test_Hooks;

   use type Ada.Streams.Stream_Element_Count;
   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Array;
   use type Data_Model.Float_64_Category;
   use type Data_Model.Length_Information;
   use type Data_Model.Value_Kind;
   use type Errors.Error_Code;
   use type Errors.Input_Offset_Unit;
   use type Interfaces.IEEE_Float_64;
   use type Interfaces.Integer_64;
   use type Interfaces.Unsigned_64;
   use type JSON_Event_Drivers.Driver_Outcome;
   use type JSON_Errors.Error_Code;
   use type JSON_Event_Drivers.Event_Kind;
   use type Parsing.Parser_State;
   use type Parsing.Step_Outcome;
   use type Preflights.Number_Summary;
   use type Preflights.String_Summary;

   function Syntax_Input_Offset (Self : Reader) return Natural
   is (JSON_Event_Drivers.Input_Offset (Self.Syntax));

   function Budget_Input_Consumed (Self : Reader) return Natural
   is (Budgets.Input_Consumed (Self.Budget));

   function Budget_Values_Consumed (Self : Reader) return Natural
   is (Budgets.Values_Consumed (Self.Budget));

   function Logical_Depth (Self : Reader) return Natural
   is (Self.Depth);

   function Budget_Depth (Self : Reader) return Natural
   is (Budgets.Depth (Self.Budget));

   procedure Assert_JSON_Event_Contract is
      type Event_Set is array (Parsing.Event_Kind) of Boolean;
      Seen : Event_Set := [others => False];

      function Profile return Flyology_JSON.Profiles.Parser_Profile
      is (Syntax        =>
            (Family => Flyology_JSON.Profiles.RFC_8259, Version => 1),
          Unicode       =>
            (Family => Flyology_JSON.Profiles.Unicode_Scalars, Version => 1),
          Compatibility =>
            (Family => Flyology_JSON.Profiles.No_Extensions, Version => 1),
          BOM           => Flyology_JSON.Profiles.Reject_BOM,
          Duplicates    => Flyology_JSON.Profiles.Preserve_Unchecked,
          Top_Level     => Flyology_JSON.Profiles.Accept_Any_Value);

      procedure Run (Input : String; Expect_Success : Boolean) is
         Parser     :
           Parsing.Parser
             (Maximum_Depth => 8,
              Name_Octet_Capacity => 0,
              Name_Capacity => 0);
         Diagnostic : JSON_Errors.Diagnostic;
         Result     : Parsing.Step_Result;
         Window     : Ada.Streams.Stream_Element_Array (17 .. 17);
         Empty      : Ada.Streams.Stream_Element_Array (17 .. 16);
         Offset     : Natural := 0;
         Zero_Run   : JSON_Event_Drivers.Zero_Progress_Count := 0;
         Maximum    : JSON_Event_Drivers.Zero_Progress_Count := 0;
         Exceeded   : Boolean;
      begin
         Parsing.Initialize (Parser, Profile, Diagnostic);
         pragma Assert (Diagnostic.Code = JSON_Errors.No_Error);

         loop
            if Offset < Input'Length then
               Window (Window'First) :=
                 Ada.Streams.Stream_Element
                   (Character'Pos (Input (Input'First + Offset)));
               Parsing.Step
                 (Parser, Window, End_Of_Input => False, Result => Result);
            else
               Parsing.Step
                 (Parser, Empty, End_Of_Input => True, Result => Result);
            end if;

            pragma Assert (Result.Consumed in 0 .. 1);
            JSON_Event_Drivers.Account_Progress
              (Consumed    => Result.Consumed = 1,
               Event_Ready => Result.Outcome = Parsing.Event_Ready,
               Count       => Zero_Run,
               Exceeded    => Exceeded);
            pragma Assert (not Exceeded);
            if Zero_Run > Maximum then
               Maximum := Zero_Run;
            end if;

            if Result.Consumed = 1 then
               Offset := Offset + 1;
            end if;

            case Result.Outcome is
               when Parsing.Event_Ready       =>
                  Seen (Parsing.Kind (Result.Item)) := True;

               when Parsing.Need_Input        =>
                  pragma Assert (Result.Consumed = 1);

               when Parsing.Document_Complete =>
                  pragma Assert (Expect_Success);
                  exit;

               when Parsing.Step_Failed       =>
                  pragma Assert (not Expect_Success);
                  exit;

               when Parsing.Call_Rejected     =>
                  pragma Assert (False);
            end case;
         end loop;

         pragma Assert (Maximum <= JSON_Event_Drivers.Zero_Progress_Limit);
         if Expect_Success then
            pragma Assert (Parsing.State (Parser) = Parsing.Completed);
         else
            pragma Assert (Parsing.State (Parser) = Parsing.Failed);
         end if;
      end Run;

      Count    : JSON_Event_Drivers.Zero_Progress_Count := 0;
      Exceeded : Boolean;
   begin
      Run ("null", True);
      Run ("true", True);
      Run ("0", True);
      Run ("""""", True);
      Run ("""x""", True);
      Run ("[]", True);
      Run ("[null]", True);
      Run ("{}", True);
      Run ("{""x"":null}", True);
      Run ("truX", False);
      Run ("[}", False);
      Run ('"' & Character'Val (1) & '"', False);
      pragma Assert (for all Present of Seen => Present);

      for Index in 1 .. JSON_Event_Drivers.Zero_Progress_Limit loop
         JSON_Event_Drivers.Account_Progress
           (Consumed    => False,
            Event_Ready => True,
            Count       => Count,
            Exceeded    => Exceeded);
         pragma Assert (not Exceeded and then Count = Index);
      end loop;
      JSON_Event_Drivers.Account_Progress
        (Consumed    => False,
         Event_Ready => True,
         Count       => Count,
         Exceeded    => Exceeded);
      pragma
        Assert
          (Exceeded and then Count = JSON_Event_Drivers.Zero_Progress_Limit);
      JSON_Event_Drivers.Account_Progress
        (Consumed    => True,
         Event_Ready => False,
         Count       => Count,
         Exceeded    => Exceeded);
      pragma Assert (not Exceeded and then Count = 0);
   end Assert_JSON_Event_Contract;

   procedure Assert_JSON_Event_Summaries is
      Quote    : constant Character := '"';
      Input    : aliased constant String :=
        "{"
        & Quote
        & "a"
        & Quote
        & ":["
        & Quote
        & "\u20AC"
        & Quote
        & ",-1,true,null],"
        & Quote
        & "f"
        & Quote
        & ":false}";
      Driver   : JSON_Event_Drivers.Driver (Input'Access);
      Budget   : Budgets.Decode_Budget;
      Policy   : constant Policies.Decode_Policy := (others => <>);
      Error    : Errors.Error_Info;
      Events   :
        JSON_Event_Drivers.Event_Summary_Array
          (17 .. 16 + JSON_Event_Drivers.Maximum_Event_Summaries);
      Count    : Natural;
      Consumed : Boolean;

      type Event_Set is array (JSON_Event_Drivers.Event_Kind) of Boolean;
      type Transcript_Array is
        array (Positive range <>) of JSON_Event_Drivers.Event_Kind;
      Expected_Transcript : constant Transcript_Array :=
        [JSON_Event_Drivers.Document_Begin,
         JSON_Event_Drivers.Object_Begin,
         JSON_Event_Drivers.Name_Begin,
         JSON_Event_Drivers.Name_Fragment,
         JSON_Event_Drivers.Name_End,
         JSON_Event_Drivers.Array_Begin,
         JSON_Event_Drivers.String_Begin,
         JSON_Event_Drivers.String_Fragment,
         JSON_Event_Drivers.String_Fragment,
         JSON_Event_Drivers.String_Fragment,
         JSON_Event_Drivers.String_Fragment,
         JSON_Event_Drivers.String_Fragment,
         JSON_Event_Drivers.String_Fragment,
         JSON_Event_Drivers.String_End,
         JSON_Event_Drivers.Number_Begin,
         JSON_Event_Drivers.Number_Fragment,
         JSON_Event_Drivers.Number_Fragment,
         JSON_Event_Drivers.Number_End,
         JSON_Event_Drivers.Boolean_Value,
         JSON_Event_Drivers.Null_Value,
         JSON_Event_Drivers.Array_End,
         JSON_Event_Drivers.Name_Begin,
         JSON_Event_Drivers.Name_Fragment,
         JSON_Event_Drivers.Name_End,
         JSON_Event_Drivers.Boolean_Value,
         JSON_Event_Drivers.Object_End,
         JSON_Event_Drivers.Document_End];
      Seen                : Event_Set := [others => False];
      Transcript          : Transcript_Array (1 .. 32) :=
        [others => JSON_Event_Drivers.Document_Begin];
      Transcript_Length   : Natural := 0;
      Number_Text         : String (1 .. 2) := [others => ' '];
      Number_Length       : Natural := 0;
      Decoded             : Ada.Streams.Stream_Element_Array (1 .. 4) :=
        [others => 0];
      Decoded_Length      : Natural := 0;
      Saw_True            : Boolean := False;
      Saw_False           : Boolean := False;
      Saw_Raw_Decoded     : Boolean := False;
      Saw_Inline_Decoded  : Boolean := False;
      Saw_Empty_Batch     : Boolean := False;

      procedure Observe
        (Items : JSON_Event_Drivers.Event_Summary_Array; Last : Natural) is
      begin
         if Last > 0 then
            for Offset in 0 .. Last - 1 loop
               declare
                  Item : constant JSON_Event_Drivers.Event_Summary :=
                    Items (Items'First + Offset);
               begin
                  Seen (Item.Kind) := True;
                  Transcript_Length := Transcript_Length + 1;
                  Transcript (Transcript_Length) := Item.Kind;
                  if Item.Has_Raw_Byte then
                     pragma Assert (Item.Source_Length = 1);
                     pragma Assert (Item.Source_Offset < Input'Length);
                     pragma
                       Assert
                         (Item.Raw_Byte
                            = Ada.Streams.Stream_Element
                                (Character'Pos
                                   (Input
                                      (Input'First + Item.Source_Offset))));
                  end if;

                  if Item.Kind
                     in JSON_Event_Drivers.Document_Begin
                      | JSON_Event_Drivers.Document_End
                      | JSON_Event_Drivers.Number_Begin
                      | JSON_Event_Drivers.Number_End
                  then
                     pragma Assert (Item.Source_Length = 0);
                     pragma Assert (not Item.Has_Raw_Byte);
                  end if;

                  if Item.Kind = JSON_Event_Drivers.String_Fragment then
                     Saw_Inline_Decoded :=
                       Saw_Inline_Decoded or else Item.Decoded_Length = 3;
                     for Index in 1 .. Item.Decoded_Length loop
                        Decoded_Length := Decoded_Length + 1;
                        Decoded
                          (Decoded'First
                           + Ada.Streams.Stream_Element_Offset
                               (Decoded_Length - 1)) :=
                          Item.Decoded
                            (Item.Decoded'First
                             + Ada.Streams.Stream_Element_Offset (Index - 1));
                     end loop;
                  elsif Item.Kind = JSON_Event_Drivers.Name_Fragment then
                     pragma
                       Assert
                         (Item.Has_Raw_Byte
                            and then Item.Decoded_Length = 1
                            and then Item.Decoded (Item.Decoded'First)
                                     = Item.Raw_Byte);
                     Saw_Raw_Decoded := True;
                  elsif Item.Kind = JSON_Event_Drivers.Number_Fragment then
                     pragma Assert (Item.Has_Raw_Byte);
                     Number_Length := Number_Length + 1;
                     Number_Text (Number_Length) :=
                       Character'Val (Item.Raw_Byte);
                  elsif Item.Kind = JSON_Event_Drivers.Boolean_Value then
                     if Item.Boolean_Payload then
                        Saw_True := True;
                        pragma Assert (Item.Source_Length = 4);
                     else
                        Saw_False := True;
                        pragma Assert (Item.Source_Length = 5);
                     end if;
                     pragma Assert (not Item.Has_Raw_Byte);
                  end if;
               end;
            end loop;
         end if;
      end Observe;
   begin
      JSON_Event_Drivers.Initialize (Driver, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      Budgets.Initialize (Budget, Policy.Limits);

      while JSON_Event_Drivers.Input_Offset (Driver) < Input'Length loop
         JSON_Event_Drivers.Consume_One
           (Driver, Budget, Consumed, Events, Count, Error);
         pragma Assert (Error.Code = Errors.No_Error and then Consumed);
         pragma Assert (Count <= Events'Length);
         if Count = 0 then
            Saw_Empty_Batch := True;
            pragma
              Assert
                (Events (Events'First).Kind = JSON_Event_Drivers.Document_Begin
                   and then Events (Events'First).Source_Offset = 0
                   and then Events (Events'First).Source_Length = 0
                   and then not Events (Events'First).Has_Raw_Byte
                   and then Events (Events'First).Decoded_Length = 0);
         end if;
         Observe (Events, Count);
      end loop;

      JSON_Event_Drivers.Finish (Driver, Events, Count, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      Observe (Events, Count);

      pragma Assert (for all Present of Seen => Present);
      pragma
        Assert
          (Transcript_Length = Expected_Transcript'Length,
           "summary transcript length"
             & Transcript_Length'Image
             & " expected"
             & Expected_Transcript'Length'Image);
      pragma
        Assert (Transcript (1 .. Transcript_Length) = Expected_Transcript);
      pragma Assert (Saw_True and then Saw_False);
      pragma Assert (Saw_Raw_Decoded and then Saw_Inline_Decoded);
      pragma Assert (Saw_Empty_Batch);
      pragma Assert (Number_Length = 2 and then Number_Text = "-1");
      pragma Assert (Decoded_Length = 3);
      pragma Assert (Decoded (1 .. 3) = [16#E2#, 16#82#, 16#AC#]);
      pragma
        Assert
          (JSON_Event_Drivers.Input_Offset (Driver)
             = Budgets.Input_Consumed (Budget));

      declare
         Short_Input  : aliased constant String := "null";
         Short_Driver : JSON_Event_Drivers.Driver (Short_Input'Access);
         Short_Budget : Budgets.Decode_Budget;
         Short_Events :
           JSON_Event_Drivers.Event_Summary_Array
             (1 .. JSON_Event_Drivers.Maximum_Event_Summaries - 1);
      begin
         Errors.Reset (Error);
         JSON_Event_Drivers.Initialize (Short_Driver, Error);
         Budgets.Initialize (Short_Budget, Policy.Limits);
         JSON_Event_Drivers.Consume_One
           (Short_Driver, Short_Budget, Consumed, Short_Events, Count, Error);
         pragma Assert (Error.Code = Errors.Invalid_State);
         pragma Assert (not Consumed and then Count = 0);
         pragma Assert (Budgets.Input_Consumed (Short_Budget) = 0);
      end;

      declare
         Null_Input  : aliased constant String := "null";
         Null_Driver : JSON_Event_Drivers.Driver (Null_Input'Access);
         Null_Budget : Budgets.Decode_Budget;
         Null_Events : JSON_Event_Drivers.Event_Summary_Array (1 .. 0);
      begin
         Errors.Reset (Error);
         JSON_Event_Drivers.Initialize (Null_Driver, Error);
         Budgets.Initialize (Null_Budget, Policy.Limits);
         JSON_Event_Drivers.Consume_One
           (Null_Driver, Null_Budget, Consumed, Null_Events, Count, Error);
         pragma Assert (Error.Code = Errors.Invalid_State);
         pragma Assert (not Consumed and then Count = 0);
         pragma Assert (Budgets.Input_Consumed (Null_Budget) = 0);
      end;

      declare
         Bad_Input  : aliased constant String := "truX";
         Bad_Driver : JSON_Event_Drivers.Driver (Bad_Input'Access);
         Bad_Budget : Budgets.Decode_Budget;
      begin
         Errors.Reset (Error);
         JSON_Event_Drivers.Initialize (Bad_Driver, Error);
         Budgets.Initialize (Bad_Budget, Policy.Limits);
         loop
            JSON_Event_Drivers.Consume_One
              (Bad_Driver, Bad_Budget, Consumed, Events, Count, Error);
            exit when Error.Code /= Errors.No_Error;
         end loop;
         pragma Assert (Error.Code = Errors.Syntax_Error and then Count = 0);
      end;

      declare
         Open_Input  : aliased constant String := [1 => Quote];
         Open_Driver : JSON_Event_Drivers.Driver (Open_Input'Access);
         Open_Budget : Budgets.Decode_Budget;
      begin
         Errors.Reset (Error);
         JSON_Event_Drivers.Initialize (Open_Driver, Error);
         Budgets.Initialize (Open_Budget, Policy.Limits);
         JSON_Event_Drivers.Consume_One
           (Open_Driver, Open_Budget, Consumed, Events, Count, Error);
         pragma Assert (Error.Code = Errors.No_Error and then Consumed);
         JSON_Event_Drivers.Finish (Open_Driver, Events, Count, Error);
         pragma Assert (Error.Code = Errors.Syntax_Error and then Count = 0);
      end;
   end Assert_JSON_Event_Summaries;

   procedure Assert_JSON_Single_Step_Driver is
      Policy : Policies.Decode_Policy := (others => <>);

      procedure Advance_Number_Byte
        (Driver : in out JSON_Event_Drivers.Driver;
         Budget : in out Budgets.Decode_Budget;
         Error  : in out Errors.Error_Info)
      is
         Outcome  : JSON_Event_Drivers.Driver_Outcome;
         Summary  : JSON_Event_Drivers.Event_Summary;
         Consumed : Boolean;
      begin
         JSON_Event_Drivers.Step_Source
           (Driver, Budget, Outcome, Consumed, Summary, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Outcome = JSON_Event_Drivers.Event_Available
                and then not Consumed
                and then Summary.Kind = JSON_Event_Drivers.Document_Begin);
         JSON_Event_Drivers.Step_Source
           (Driver, Budget, Outcome, Consumed, Summary, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Outcome = JSON_Event_Drivers.Event_Available
                and then not Consumed
                and then Summary.Kind = JSON_Event_Drivers.Number_Begin);
         JSON_Event_Drivers.Step_Source
           (Driver, Budget, Outcome, Consumed, Summary, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Outcome = JSON_Event_Drivers.Event_Available
                and then Consumed
                and then Summary.Kind = JSON_Event_Drivers.Number_Fragment
                and then Summary.Has_Raw_Byte
                and then Summary.Raw_Byte = Character'Pos ('1'));
      end Advance_Number_Byte;
   begin
      --  The event-reader path primes Document_Begin without reading or
      --  charging source, and a prelatched claim leaves it pending.
      declare
         Input    : aliased constant String :=
           [' ', ASCII.HT, ASCII.CR, ASCII.LF, 'n', 'u', 'l', 'l'];
         Driver   : JSON_Event_Drivers.Driver (Input'Access);
         Budget   : Budgets.Decode_Budget;
         Error    : Errors.Error_Info;
         Outcome  : JSON_Event_Drivers.Driver_Outcome;
         Summary  : JSON_Event_Drivers.Event_Summary;
         Consumed : Boolean;
      begin
         JSON_Event_Drivers.Initialize (Driver, Error);
         Budgets.Initialize (Budget, Policy.Limits);
         JSON_Event_Drivers.Prime_Document_Begin (Driver, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then JSON_Event_Drivers.Input_Offset (Driver) = 0
                and then Budgets.Input_Consumed (Budget) = 0);

         for Expected in 1 .. 4 loop
            JSON_Event_Drivers.Consume_Leading_Whitespace
              (Driver, Budget, Error);
            pragma
              Assert
                (Error.Code = Errors.No_Error
                   and then JSON_Event_Drivers.Input_Offset (Driver) = Expected
                   and then Budgets.Input_Consumed (Budget) = Expected);
         end loop;

         Errors.Fail (Error, Errors.Invalid_State, 0, Errors.Byte_Offset);
         JSON_Event_Drivers.Claim_Document_Begin (Driver, Summary, Error);
         pragma
           Assert
             (Error.Code = Errors.Invalid_State
                and then Summary.Kind = JSON_Event_Drivers.Document_Begin
                and then Summary.Source_Length = 0);
         Errors.Reset (Error);
         JSON_Event_Drivers.Claim_Document_Begin (Driver, Summary, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Summary.Kind = JSON_Event_Drivers.Document_Begin
                and then Summary.Source_Offset = 0
                and then Summary.Source_Length = 0);
         while JSON_Event_Drivers.Input_Offset (Driver) < Input'Length loop
            JSON_Event_Drivers.Step_Source
              (Driver, Budget, Outcome, Consumed, Summary, Error);
            pragma Assert (Error.Code = Errors.No_Error);
         end loop;
         loop
            JSON_Event_Drivers.Step_Final (Driver, Outcome, Summary, Error);
            exit when
              Error.Code /= Errors.No_Error
              or else Outcome = JSON_Event_Drivers.Document_Accepted;
         end loop;
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then JSON_Event_Drivers.Input_Offset (Driver)
                         = Input'Length
                and then Budgets.Input_Consumed (Budget) = Input'Length);
      end;

      --  Non-whitespace is rejected without admission while the provisional
      --  boundary remains the only parser event observed.
      declare
         Input  : aliased constant String := "n";
         Driver : JSON_Event_Drivers.Driver (Input'Access);
         Budget : Budgets.Decode_Budget;
         Error  : Errors.Error_Info;
      begin
         JSON_Event_Drivers.Initialize (Driver, Error);
         Budgets.Initialize (Budget, Policy.Limits);
         JSON_Event_Drivers.Prime_Document_Begin (Driver, Error);
         JSON_Event_Drivers.Consume_Leading_Whitespace (Driver, Budget, Error);
         pragma
           Assert
             (Error.Code = Errors.Invalid_State
                and then JSON_Event_Drivers.Input_Offset (Driver) = 0
                and then Budgets.Input_Consumed (Budget) = 0);
      end;

      --  Capacity denial precedes source classification and copying. The
      --  armed copy hook survives until a later operation has capacity.
      declare
         Input  : aliased constant String := " ";
         Driver : JSON_Event_Drivers.Driver (Input'Access);
         Budget : Budgets.Decode_Budget;
         Error  : Errors.Error_Info;
         Raised : Boolean := False;
      begin
         Policy.Limits.Maximum_Input_Units := 0;
         JSON_Event_Drivers.Initialize (Driver, Error);
         Budgets.Initialize (Budget, Policy.Limits);
         JSON_Event_Drivers.Prime_Document_Begin (Driver, Error);
         Test_Hooks.Arm (Test_Hooks.Before_Source_Copy);
         JSON_Event_Drivers.Consume_Leading_Whitespace (Driver, Budget, Error);
         pragma
           Assert
             (Error.Code = Errors.Capacity_Exceeded
                and then JSON_Event_Drivers.Input_Offset (Driver) = 0
                and then Budgets.Input_Consumed (Budget) = 0);

         Policy := (others => <>);
         Errors.Reset (Error);
         JSON_Event_Drivers.Reset (Driver, Error);
         Budgets.Initialize (Budget, Policy.Limits);
         JSON_Event_Drivers.Prime_Document_Begin (Driver, Error);
         begin
            JSON_Event_Drivers.Consume_Leading_Whitespace
              (Driver, Budget, Error);
         exception
            when Constraint_Error =>
               Raised := True;
         end;
         pragma Assert (Raised and then Budgets.Input_Consumed (Budget) = 1);
      end;

      --  A prelatched call is a no-op; relative source indexing still works
      --  when the sole whitespace byte ends at Positive'Last.
      declare
         Input  : aliased constant String := [Positive'Last => ASCII.LF];
         Driver : JSON_Event_Drivers.Driver (Input'Access);
         Budget : Budgets.Decode_Budget;
         Error  : Errors.Error_Info;
      begin
         JSON_Event_Drivers.Initialize (Driver, Error);
         Budgets.Initialize (Budget, Policy.Limits);
         JSON_Event_Drivers.Prime_Document_Begin (Driver, Error);
         Errors.Fail (Error, Errors.Invalid_State, 0, Errors.Byte_Offset);
         JSON_Event_Drivers.Consume_Leading_Whitespace (Driver, Budget, Error);
         pragma
           Assert
             (Error.Code = Errors.Invalid_State
                and then JSON_Event_Drivers.Input_Offset (Driver) = 0
                and then Budgets.Input_Consumed (Budget) = 0);
         Errors.Reset (Error);
         JSON_Event_Drivers.Consume_Leading_Whitespace (Driver, Budget, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then JSON_Event_Drivers.Input_Offset (Driver) = 1
                and then Budgets.Input_Consumed (Budget) = 1);
      end;

      --  Legacy batch entry points cannot bypass an unclaimed provisional
      --  boundary; only leading-whitespace consumption and Claim may proceed.
      declare
         Input    : aliased constant String := "n";
         Driver   : JSON_Event_Drivers.Driver (Input'Access);
         Budget   : Budgets.Decode_Budget;
         Error    : Errors.Error_Info;
         Consumed : Boolean;
      begin
         JSON_Event_Drivers.Initialize (Driver, Error);
         Budgets.Initialize (Budget, Policy.Limits);
         JSON_Event_Drivers.Prime_Document_Begin (Driver, Error);
         JSON_Event_Drivers.Consume_One (Driver, Budget, Consumed, Error);
         pragma
           Assert
             (Error.Code = Errors.Invalid_State
                and then not Consumed
                and then JSON_Event_Drivers.Input_Offset (Driver) = 0
                and then Budgets.Input_Consumed (Budget) = 0);
      end;

      declare
         Input  : aliased constant String := "n";
         Driver : JSON_Event_Drivers.Driver (Input'Access);
         Error  : Errors.Error_Info;
      begin
         JSON_Event_Drivers.Initialize (Driver, Error);
         JSON_Event_Drivers.Prime_Document_Begin (Driver, Error);
         JSON_Event_Drivers.Finish (Driver, Error);
         pragma
           Assert
             (Error.Code = Errors.Invalid_State
                and then JSON_Event_Drivers.Input_Offset (Driver) = 0);
      end;

      --  A legal terminator is observed without admission or consumption,
      --  then the exact retained byte is admitted and replayed once.
      declare
         Input    : aliased constant String := [17 => '1', 18 => ' '];
         Driver   : JSON_Event_Drivers.Driver (Input'Access);
         Budget   : Budgets.Decode_Budget;
         Error    : Errors.Error_Info;
         Outcome  : JSON_Event_Drivers.Driver_Outcome;
         Summary  : JSON_Event_Drivers.Event_Summary;
         Consumed : Boolean;
      begin
         JSON_Event_Drivers.Initialize (Driver, Error);
         Budgets.Initialize (Budget, Policy.Limits);
         Advance_Number_Byte (Driver, Budget, Error);
         pragma
           Assert
             (JSON_Event_Drivers.Input_Offset (Driver) = 1
                and then Budgets.Input_Consumed (Budget) = 1);

         JSON_Event_Drivers.Observe_Number_End (Driver, Summary, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Summary.Kind = JSON_Event_Drivers.Number_End
                and then Summary.Source_Offset = 1
                and then Summary.Source_Length = 0
                and then JSON_Event_Drivers.Input_Offset (Driver) = 1
                and then Budgets.Input_Consumed (Budget) = 1);

         JSON_Event_Drivers.Step_Source
           (Driver, Budget, Outcome, Consumed, Summary, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Outcome = JSON_Event_Drivers.Event_Available
                and then not Consumed
                and then Summary.Kind = JSON_Event_Drivers.Document_End
                and then JSON_Event_Drivers.Input_Offset (Driver) = 1
                and then Budgets.Input_Consumed (Budget) = 2);
         JSON_Event_Drivers.Step_Source
           (Driver, Budget, Outcome, Consumed, Summary, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Outcome = JSON_Event_Drivers.Need_Source
                and then Consumed
                and then JSON_Event_Drivers.Input_Offset (Driver) = 2
                and then Budgets.Input_Consumed (Budget) = 2);
         JSON_Event_Drivers.Finish (Driver, Error);
         pragma Assert (Error.Code = Errors.No_Error);
      end;

      --  The generalized scalar-terminal observer covers every installed
      --  scalar terminal and preserves Boolean payload identity.
      declare
         procedure Check_Terminal
           (Token            : String;
            Expected         : JSON_Event_Drivers.Token_Terminal;
            Expected_Kind    : JSON_Event_Drivers.Event_Kind;
            Expected_Boolean : Boolean := False)
         is
            Input    : aliased constant String := Token & " ";
            Driver   : JSON_Event_Drivers.Driver (Input'Access);
            Budget   : Budgets.Decode_Budget;
            Error    : Errors.Error_Info;
            Summary  : JSON_Event_Drivers.Event_Summary;
            Consumed : Boolean;
         begin
            JSON_Event_Drivers.Initialize (Driver, Error);
            Budgets.Initialize (Budget, Policy.Limits);
            for Index in Token'Range loop
               pragma Unreferenced (Index);
               JSON_Event_Drivers.Consume_One
                 (Driver, Budget, Consumed, Error);
               pragma Assert (Error.Code = Errors.No_Error and then Consumed);
            end loop;
            JSON_Event_Drivers.Observe_Token_End
              (Driver, Expected, Summary, Error);
            pragma
              Assert
                (Error.Code = Errors.No_Error
                   and then Summary.Kind = Expected_Kind
                   and then (Expected_Kind /= JSON_Event_Drivers.Boolean_Value
                             or else Summary.Boolean_Payload
                                     = Expected_Boolean)
                   and then JSON_Event_Drivers.Input_Offset (Driver)
                            = Token'Length
                   and then Budgets.Input_Consumed (Budget) = Token'Length,
                 Token
                   & Error.Code'Image
                   & Summary.Kind'Image
                   & JSON_Event_Drivers.Input_Offset (Driver)'Image
                   & Budgets.Input_Consumed (Budget)'Image);
         end Check_Terminal;
      begin
         Check_Terminal
           ("null",
            JSON_Event_Drivers.Null_Terminal,
            JSON_Event_Drivers.Null_Value);
         Check_Terminal
           ("true",
            JSON_Event_Drivers.Boolean_Terminal,
            JSON_Event_Drivers.Boolean_Value,
            Expected_Boolean => True);
         Check_Terminal
           ("false",
            JSON_Event_Drivers.Boolean_Terminal,
            JSON_Event_Drivers.Boolean_Value,
            Expected_Boolean => False);
         Check_Terminal
           ("1",
            JSON_Event_Drivers.Number_Terminal,
            JSON_Event_Drivers.Number_End);
      end;

      --  A wrong selector and a duplicate observation publish the default
      --  summary and fail closed without charging the delimiter.
      declare
         Input    : aliased constant String := "null ";
         Driver   : JSON_Event_Drivers.Driver (Input'Access);
         Budget   : Budgets.Decode_Budget;
         Error    : Errors.Error_Info;
         Summary  : JSON_Event_Drivers.Event_Summary;
         Consumed : Boolean;
      begin
         JSON_Event_Drivers.Initialize (Driver, Error);
         Budgets.Initialize (Budget, Policy.Limits);
         for Index in 1 .. 4 loop
            pragma Unreferenced (Index);
            JSON_Event_Drivers.Consume_One (Driver, Budget, Consumed, Error);
         end loop;
         JSON_Event_Drivers.Observe_Token_End
           (Driver, JSON_Event_Drivers.Boolean_Terminal, Summary, Error);
         pragma
           Assert
             (Error.Code = Errors.Invalid_State
                and then Summary.Kind = JSON_Event_Drivers.Document_Begin
                and then JSON_Event_Drivers.Input_Offset (Driver) = 4
                and then Budgets.Input_Consumed (Budget) = 4);
      end;

      declare
         Input    : aliased constant String := "null ";
         Driver   : JSON_Event_Drivers.Driver (Input'Access);
         Budget   : Budgets.Decode_Budget;
         Error    : Errors.Error_Info;
         Summary  : JSON_Event_Drivers.Event_Summary;
         Consumed : Boolean;
      begin
         JSON_Event_Drivers.Initialize (Driver, Error);
         Budgets.Initialize (Budget, Policy.Limits);
         for Index in 1 .. 4 loop
            pragma Unreferenced (Index);
            JSON_Event_Drivers.Consume_One (Driver, Budget, Consumed, Error);
         end loop;
         JSON_Event_Drivers.Observe_Token_End
           (Driver, JSON_Event_Drivers.Null_Terminal, Summary, Error);
         pragma Assert (Error.Code = Errors.No_Error);
         JSON_Event_Drivers.Observe_Token_End
           (Driver, JSON_Event_Drivers.Null_Terminal, Summary, Error);
         pragma
           Assert
             (Error.Code = Errors.Invalid_State
                and then Summary.Kind = JSON_Event_Drivers.Document_Begin
                and then JSON_Event_Drivers.Input_Offset (Driver) = 4
                and then Budgets.Input_Consumed (Budget) = 4);
      end;

      --  Number-end observation admits exactly the strict JSON delimiter set
      --  and no alphabetic, control, or other structural follower.
      declare
         Legal_Delimiters  : constant String :=
           [' ', ASCII.HT, ASCII.CR, ASCII.LF, ',', ']', '}'];
         Invalid_Followers : constant String :=
           ['x', ASCII.NUL, '[', '{', ':', '"'];
      begin
         for Delimiter of Legal_Delimiters loop
            declare
               Input    : aliased constant String := "1" & Delimiter;
               Driver   : JSON_Event_Drivers.Driver (Input'Access);
               Budget   : Budgets.Decode_Budget;
               Error    : Errors.Error_Info;
               Outcome  : JSON_Event_Drivers.Driver_Outcome;
               Summary  : JSON_Event_Drivers.Event_Summary;
               Consumed : Boolean;
            begin
               JSON_Event_Drivers.Initialize (Driver, Error);
               Budgets.Initialize (Budget, Policy.Limits);
               Advance_Number_Byte (Driver, Budget, Error);
               JSON_Event_Drivers.Observe_Number_End (Driver, Summary, Error);
               pragma
                 Assert
                   (Error.Code = Errors.No_Error
                      and then Summary.Kind = JSON_Event_Drivers.Number_End
                      and then JSON_Event_Drivers.Input_Offset (Driver) = 1
                      and then Budgets.Input_Consumed (Budget) = 1);
               loop
                  JSON_Event_Drivers.Step_Source
                    (Driver, Budget, Outcome, Consumed, Summary, Error);
                  exit when Consumed or else Error.Code /= Errors.No_Error;
               end loop;
               if Delimiter in ' ' | ASCII.HT | ASCII.CR | ASCII.LF then
                  pragma
                    Assert (Error.Code = Errors.No_Error and then Consumed);
               else
                  pragma
                    Assert
                      (Error.Code = Errors.Syntax_Error and then Consumed);
               end if;
               pragma
                 Assert
                   (JSON_Event_Drivers.Input_Offset (Driver) = 2
                      and then Budgets.Input_Consumed (Budget) = 2);
               JSON_Event_Drivers.Abort_Document (Driver, Error);
            end;
         end loop;

         for Follower of Invalid_Followers loop
            declare
               Input   : aliased constant String := "1" & Follower;
               Driver  : JSON_Event_Drivers.Driver (Input'Access);
               Budget  : Budgets.Decode_Budget;
               Error   : Errors.Error_Info;
               Summary : JSON_Event_Drivers.Event_Summary;
            begin
               JSON_Event_Drivers.Initialize (Driver, Error);
               Budgets.Initialize (Budget, Policy.Limits);
               Advance_Number_Byte (Driver, Budget, Error);
               JSON_Event_Drivers.Observe_Number_End (Driver, Summary, Error);
               pragma
                 Assert
                   (Error.Code = Errors.Invalid_State
                      and then JSON_Event_Drivers.Input_Offset (Driver) = 1
                      and then Budgets.Input_Consumed (Budget) = 1);
            end;

            declare
               Input    : aliased constant String := "1" & Follower;
               Driver   : JSON_Event_Drivers.Driver (Input'Access);
               Budget   : Budgets.Decode_Budget;
               Error    : Errors.Error_Info;
               Outcome  : JSON_Event_Drivers.Driver_Outcome;
               Summary  : JSON_Event_Drivers.Event_Summary;
               Consumed : Boolean;
            begin
               JSON_Event_Drivers.Initialize (Driver, Error);
               Budgets.Initialize (Budget, Policy.Limits);
               Advance_Number_Byte (Driver, Budget, Error);
               loop
                  JSON_Event_Drivers.Step_Source
                    (Driver, Budget, Outcome, Consumed, Summary, Error);
                  exit when Consumed or else Error.Code /= Errors.No_Error;
               end loop;
               pragma
                 Assert
                   (Error.Code = Errors.Syntax_Error
                      and then Consumed
                      and then JSON_Event_Drivers.Input_Offset (Driver) = 2
                      and then Budgets.Input_Consumed (Budget) = 2);
            end;
         end loop;
      end;

      --  A prelatched observation leaves the delimiter unoffered. Abort then
      --  clears a retained uncharged delimiter, and Reset permits full reuse.
      declare
         Input    : aliased constant String := "1 ";
         Driver   : JSON_Event_Drivers.Driver (Input'Access);
         Budget   : Budgets.Decode_Budget;
         Error    : Errors.Error_Info;
         Summary  : JSON_Event_Drivers.Event_Summary;
         Consumed : Boolean;
      begin
         JSON_Event_Drivers.Initialize (Driver, Error);
         Budgets.Initialize (Budget, Policy.Limits);
         Advance_Number_Byte (Driver, Budget, Error);
         Errors.Fail (Error, Errors.Invalid_State, 0, Errors.Byte_Offset);
         JSON_Event_Drivers.Observe_Number_End (Driver, Summary, Error);
         pragma
           Assert
             (Error.Code = Errors.Invalid_State
                and then Summary.Kind = JSON_Event_Drivers.Document_Begin
                and then JSON_Event_Drivers.Input_Offset (Driver) = 1
                and then Budgets.Input_Consumed (Budget) = 1);
         Errors.Reset (Error);
         JSON_Event_Drivers.Observe_Number_End (Driver, Summary, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Summary.Kind = JSON_Event_Drivers.Number_End);
         JSON_Event_Drivers.Abort_Document (Driver, Error);
         Errors.Reset (Error);
         JSON_Event_Drivers.Reset (Driver, Error);
         Budgets.Initialize (Budget, Policy.Limits);
         while JSON_Event_Drivers.Input_Offset (Driver) < Input'Length loop
            JSON_Event_Drivers.Consume_One (Driver, Budget, Consumed, Error);
            pragma Assert (Error.Code = Errors.No_Error and then Consumed);
         end loop;
         JSON_Event_Drivers.Finish (Driver, Error);
         pragma Assert (Error.Code = Errors.No_Error);
      end;

      --  Denial before replay consumes neither the retained terminator nor a
      --  second budget unit and poisons the operation until reset.
      declare
         Input    : aliased constant String := "1 ";
         Driver   : JSON_Event_Drivers.Driver (Input'Access);
         Budget   : Budgets.Decode_Budget;
         Error    : Errors.Error_Info;
         Outcome  : JSON_Event_Drivers.Driver_Outcome;
         Summary  : JSON_Event_Drivers.Event_Summary;
         Consumed : Boolean;
      begin
         Policy.Limits.Maximum_Input_Units := 1;
         JSON_Event_Drivers.Initialize (Driver, Error);
         Budgets.Initialize (Budget, Policy.Limits);
         Advance_Number_Byte (Driver, Budget, Error);
         JSON_Event_Drivers.Observe_Number_End (Driver, Summary, Error);
         JSON_Event_Drivers.Step_Source
           (Driver, Budget, Outcome, Consumed, Summary, Error);
         pragma
           Assert
             (Error.Code = Errors.Capacity_Exceeded
                and then not Consumed
                and then JSON_Event_Drivers.Input_Offset (Driver) = 1
                and then Budgets.Input_Consumed (Budget) = 1);
         Errors.Reset (Error);
         JSON_Event_Drivers.Step_Source
           (Driver, Budget, Outcome, Consumed, Summary, Error);
         pragma
           Assert
             (Error.Code = Errors.Invalid_State
                and then not Consumed
                and then JSON_Event_Drivers.Input_Offset (Driver) = 1
                and then Budgets.Input_Consumed (Budget) = 1);

         Policy := (others => <>);
         Errors.Reset (Error);
         JSON_Event_Drivers.Reset (Driver, Error);
         Budgets.Initialize (Budget, Policy.Limits);
         while JSON_Event_Drivers.Input_Offset (Driver) < Input'Length loop
            JSON_Event_Drivers.Consume_One (Driver, Budget, Consumed, Error);
            pragma Assert (Error.Code = Errors.No_Error and then Consumed);
         end loop;
         JSON_Event_Drivers.Finish (Driver, Error);
         pragma Assert (Error.Code = Errors.No_Error);
      end;

      --  A first-byte denial occurs before the source-copy hook. The armed
      --  hook remains pending and fires only after a later successful charge.
      declare
         Input    : aliased constant String := "n";
         Driver   : JSON_Event_Drivers.Driver (Input'Access);
         Budget   : Budgets.Decode_Budget;
         Error    : Errors.Error_Info;
         Outcome  : JSON_Event_Drivers.Driver_Outcome;
         Summary  : JSON_Event_Drivers.Event_Summary;
         Consumed : Boolean;
         Raised   : Boolean := False;
      begin
         Policy.Limits.Maximum_Input_Units := 0;
         JSON_Event_Drivers.Initialize (Driver, Error);
         Budgets.Initialize (Budget, Policy.Limits);
         Test_Hooks.Arm (Test_Hooks.Before_Source_Copy);
         JSON_Event_Drivers.Step_Source
           (Driver, Budget, Outcome, Consumed, Summary, Error);
         pragma
           Assert
             (Error.Code = Errors.Capacity_Exceeded
                and then not Consumed
                and then JSON_Event_Drivers.Input_Offset (Driver) = 0
                and then Budgets.Input_Consumed (Budget) = 0);

         Errors.Reset (Error);
         Policy := (others => <>);
         JSON_Event_Drivers.Reset (Driver, Error);
         Budgets.Initialize (Budget, Policy.Limits);
         begin
            JSON_Event_Drivers.Step_Source
              (Driver, Budget, Outcome, Consumed, Summary, Error);
         exception
            when Constraint_Error =>
               Raised := True;
         end;
         pragma Assert (Raised and then Budgets.Input_Consumed (Budget) = 1);
      end;

      --  Physical EOF exposes Number_End, Document_End, and final acceptance
      --  as three separate caller-driven final steps.
      declare
         Input   : aliased constant String := "1";
         Driver  : JSON_Event_Drivers.Driver (Input'Access);
         Budget  : Budgets.Decode_Budget;
         Error   : Errors.Error_Info;
         Outcome : JSON_Event_Drivers.Driver_Outcome;
         Summary : JSON_Event_Drivers.Event_Summary;
      begin
         JSON_Event_Drivers.Initialize (Driver, Error);
         Budgets.Initialize (Budget, Policy.Limits);
         Advance_Number_Byte (Driver, Budget, Error);

         JSON_Event_Drivers.Step_Final (Driver, Outcome, Summary, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Outcome = JSON_Event_Drivers.Event_Available
                and then Summary.Kind = JSON_Event_Drivers.Number_End);
         JSON_Event_Drivers.Step_Final (Driver, Outcome, Summary, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Outcome = JSON_Event_Drivers.Event_Available
                and then Summary.Kind = JSON_Event_Drivers.Document_End);
         JSON_Event_Drivers.Step_Final (Driver, Outcome, Summary, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Outcome = JSON_Event_Drivers.Document_Accepted
                and then JSON_Event_Drivers.Input_Offset (Driver) = 1
                and then Budgets.Input_Consumed (Budget) = 1);

         Errors.Reset (Error);
         JSON_Event_Drivers.Step_Final (Driver, Outcome, Summary, Error);
         pragma Assert (Error.Code = Errors.Invalid_State);
      end;

      --  Relative indexing remains valid at the top of Positive, both at EOF
      --  and while retaining and replaying a two-byte delimiter window.
      declare
         Input   : aliased constant String := [Positive'Last => '1'];
         Driver  : JSON_Event_Drivers.Driver (Input'Access);
         Budget  : Budgets.Decode_Budget;
         Error   : Errors.Error_Info;
         Outcome : JSON_Event_Drivers.Driver_Outcome;
         Summary : JSON_Event_Drivers.Event_Summary;
      begin
         JSON_Event_Drivers.Initialize (Driver, Error);
         Budgets.Initialize (Budget, Policy.Limits);
         Advance_Number_Byte (Driver, Budget, Error);
         JSON_Event_Drivers.Step_Final (Driver, Outcome, Summary, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Summary.Kind = JSON_Event_Drivers.Number_End);
      end;

      declare
         Input    : aliased constant String :=
           [Positive'Last - 1 => '1', Positive'Last => ASCII.HT];
         Driver   : JSON_Event_Drivers.Driver (Input'Access);
         Budget   : Budgets.Decode_Budget;
         Error    : Errors.Error_Info;
         Outcome  : JSON_Event_Drivers.Driver_Outcome;
         Summary  : JSON_Event_Drivers.Event_Summary;
         Consumed : Boolean;
      begin
         JSON_Event_Drivers.Initialize (Driver, Error);
         Budgets.Initialize (Budget, Policy.Limits);
         Advance_Number_Byte (Driver, Budget, Error);
         JSON_Event_Drivers.Observe_Number_End (Driver, Summary, Error);
         pragma Assert (Error.Code = Errors.No_Error);
         loop
            JSON_Event_Drivers.Step_Source
              (Driver, Budget, Outcome, Consumed, Summary, Error);
            exit when Consumed or else Error.Code /= Errors.No_Error;
         end loop;
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Consumed
                and then JSON_Event_Drivers.Input_Offset (Driver) = 2
                and then Budgets.Input_Consumed (Budget) = 2);
      end;

      --  Final input is rejected before physical EOF and while an uncharged
      --  delimiter is retained.
      declare
         Input   : aliased constant String := "n";
         Driver  : JSON_Event_Drivers.Driver (Input'Access);
         Error   : Errors.Error_Info;
         Outcome : JSON_Event_Drivers.Driver_Outcome;
         Summary : JSON_Event_Drivers.Event_Summary;
      begin
         JSON_Event_Drivers.Initialize (Driver, Error);
         JSON_Event_Drivers.Step_Final (Driver, Outcome, Summary, Error);
         pragma Assert (Error.Code = Errors.Invalid_State);
      end;

      declare
         Input   : aliased constant String := "1 ";
         Driver  : JSON_Event_Drivers.Driver (Input'Access);
         Budget  : Budgets.Decode_Budget;
         Error   : Errors.Error_Info;
         Outcome : JSON_Event_Drivers.Driver_Outcome;
         Summary : JSON_Event_Drivers.Event_Summary;
      begin
         JSON_Event_Drivers.Initialize (Driver, Error);
         Budgets.Initialize (Budget, Policy.Limits);
         Advance_Number_Byte (Driver, Budget, Error);
         JSON_Event_Drivers.Observe_Number_End (Driver, Summary, Error);
         JSON_Event_Drivers.Step_Final (Driver, Outcome, Summary, Error);
         pragma Assert (Error.Code = Errors.Invalid_State);
      end;

      declare
         Input    : aliased constant String := "[";
         Driver   : JSON_Event_Drivers.Driver (Input'Access);
         Budget   : Budgets.Decode_Budget;
         Error    : Errors.Error_Info;
         Outcome  : JSON_Event_Drivers.Driver_Outcome;
         Summary  : JSON_Event_Drivers.Event_Summary;
         Consumed : Boolean;
      begin
         JSON_Event_Drivers.Initialize (Driver, Error);
         Budgets.Initialize (Budget, Policy.Limits);
         while JSON_Event_Drivers.Input_Offset (Driver) < Input'Length loop
            JSON_Event_Drivers.Step_Source
              (Driver, Budget, Outcome, Consumed, Summary, Error);
            pragma Assert (Error.Code = Errors.No_Error);
         end loop;
         JSON_Event_Drivers.Step_Final (Driver, Outcome, Summary, Error);
         pragma Assert (Error.Code = Errors.Syntax_Error);
      end;

      --  A prelatched error prevents every single-step primitive from
      --  inspecting, charging, or advancing its input.
      declare
         Input    : aliased constant String := "1";
         Driver   : JSON_Event_Drivers.Driver (Input'Access);
         Budget   : Budgets.Decode_Budget;
         Error    : Errors.Error_Info;
         Outcome  : JSON_Event_Drivers.Driver_Outcome;
         Summary  : JSON_Event_Drivers.Event_Summary;
         Consumed : Boolean;
      begin
         JSON_Event_Drivers.Initialize (Driver, Error);
         Budgets.Initialize (Budget, Policy.Limits);
         Errors.Fail (Error, Errors.Invalid_State, 0, Errors.Byte_Offset);
         JSON_Event_Drivers.Step_Source
           (Driver, Budget, Outcome, Consumed, Summary, Error);
         pragma
           Assert
             (Error.Code = Errors.Invalid_State
                and then Outcome = JSON_Event_Drivers.Need_Source
                and then not Consumed
                and then JSON_Event_Drivers.Input_Offset (Driver) = 0
                and then Budgets.Input_Consumed (Budget) = 0);

         Errors.Reset (Error);
         Advance_Number_Byte (Driver, Budget, Error);
         Errors.Fail (Error, Errors.Invalid_State, 0, Errors.Byte_Offset);
         JSON_Event_Drivers.Step_Final (Driver, Outcome, Summary, Error);
         pragma
           Assert
             (Error.Code = Errors.Invalid_State
                and then Outcome = JSON_Event_Drivers.Need_Source
                and then JSON_Event_Drivers.Input_Offset (Driver) = 1
                and then Budgets.Input_Consumed (Budget) = 1);
      end;

      --  A non-delimiter follower is admitted only by the later normal step
      --  and is then reported as the parser's syntax primary.
      declare
         Input    : aliased constant String := "1x";
         Driver   : JSON_Event_Drivers.Driver (Input'Access);
         Budget   : Budgets.Decode_Budget;
         Error    : Errors.Error_Info;
         Outcome  : JSON_Event_Drivers.Driver_Outcome;
         Summary  : JSON_Event_Drivers.Event_Summary;
         Consumed : Boolean;
      begin
         JSON_Event_Drivers.Initialize (Driver, Error);
         Budgets.Initialize (Budget, Policy.Limits);
         Advance_Number_Byte (Driver, Budget, Error);
         JSON_Event_Drivers.Step_Source
           (Driver, Budget, Outcome, Consumed, Summary, Error);
         pragma
           Assert
             (Error.Code = Errors.Syntax_Error
                and then Consumed
                and then JSON_Event_Drivers.Input_Offset (Driver) = 2
                and then Budgets.Input_Consumed (Budget) = 2);
      end;
   end Assert_JSON_Single_Step_Driver;

   procedure Assert_JSON_Driver_Lifecycle is
      Input    : aliased constant String := "truX";
      Driver   : JSON_Event_Drivers.Driver (Input'Access);
      Budget   : Budgets.Decode_Budget;
      Policy   : constant Policies.Decode_Policy := (others => <>);
      Error    : Errors.Error_Info;
      Consumed : Boolean;

      procedure Run_To_Failure is
      begin
         while Error.Code = Errors.No_Error loop
            JSON_Event_Drivers.Consume_One (Driver, Budget, Consumed, Error);
         end loop;
      end Run_To_Failure;

      procedure Reset_And_Complete
        (Item          : in out JSON_Event_Drivers.Driver;
         Item_Budget   : in out Budgets.Decode_Budget;
         Source_Length : Natural;
         Item_Error    : in out Errors.Error_Info)
      is
         Item_Consumed : Boolean;
      begin
         Errors.Reset (Item_Error);
         JSON_Event_Drivers.Reset (Item, Item_Error);
         Budgets.Initialize (Item_Budget, Policy.Limits);
         while JSON_Event_Drivers.Input_Offset (Item) < Source_Length loop
            JSON_Event_Drivers.Consume_One
              (Item, Item_Budget, Item_Consumed, Item_Error);
            pragma
              Assert
                (Item_Error.Code = Errors.No_Error and then Item_Consumed);
         end loop;
         JSON_Event_Drivers.Finish (Item, Item_Error);
         pragma Assert (Item_Error.Code = Errors.No_Error);
      end Reset_And_Complete;
   begin
      JSON_Event_Drivers.Initialize (Driver, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      Budgets.Initialize (Budget, Policy.Limits);
      Run_To_Failure;
      pragma Assert (Error.Code = Errors.Syntax_Error);
      pragma
        Assert
          (JSON_Event_Drivers.Input_Offset (Driver)
             = Budgets.Input_Consumed (Budget));

      --  A reported parser primary is not copied a second time by cleanup.
      Errors.Reset (Error);
      JSON_Event_Drivers.Abort_Document (Driver, Error);
      pragma Assert (Error.Code = Errors.No_Error);

      JSON_Event_Drivers.Reset (Driver, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      Budgets.Initialize (Budget, Policy.Limits);
      Run_To_Failure;
      pragma Assert (Error.Code = Errors.Syntax_Error);

      Errors.Reset (Error);
      JSON_Event_Drivers.Reset (Driver, Error);
      Budgets.Initialize (Budget, Policy.Limits);
      Errors.Fail (Error, Errors.Invalid_State, 0, Errors.Byte_Offset);
      declare
         Events :
           JSON_Event_Drivers.Event_Summary_Array
             (9 .. 8 + JSON_Event_Drivers.Maximum_Event_Summaries);
         Count  : Natural;
      begin
         JSON_Event_Drivers.Consume_One
           (Driver, Budget, Consumed, Events, Count, Error);
         pragma Assert (not Consumed and then Count = 0);
         JSON_Event_Drivers.Finish (Driver, Events, Count, Error);
         pragma Assert (Count = 0);
      end;
      pragma Assert (JSON_Event_Drivers.Input_Offset (Driver) = 0);
      pragma Assert (Budgets.Input_Consumed (Budget) = 0);
      JSON_Event_Drivers.Abort_Document (Driver, Error);
      pragma Assert (Error.Code = Errors.Invalid_State);

      --  Unexpected exceptions at every guarded call boundary are cleaned
      --  before they escape. Reset then starts a fresh parser operation.
      declare
         procedure Exercise
           (Point          : Test_Hooks.Failure_Point;
            Finish_Phase   : Boolean;
            Keep_Summaries : Boolean)
         is
            Valid_Input  : aliased constant String := "null";
            Valid_Driver : JSON_Event_Drivers.Driver (Valid_Input'Access);
            Valid_Budget : Budgets.Decode_Budget;
            Events       :
              JSON_Event_Drivers.Event_Summary_Array
                (23 .. 22 + JSON_Event_Drivers.Maximum_Event_Summaries);
            Count        : Natural;
            Raised       : Boolean := False;
         begin
            Errors.Reset (Error);
            JSON_Event_Drivers.Initialize (Valid_Driver, Error);
            Budgets.Initialize (Valid_Budget, Policy.Limits);
            if Finish_Phase then
               for Index in Valid_Input'Range loop
                  pragma Unreferenced (Index);
                  if Keep_Summaries then
                     JSON_Event_Drivers.Consume_One
                       (Valid_Driver,
                        Valid_Budget,
                        Consumed,
                        Events,
                        Count,
                        Error);
                  else
                     JSON_Event_Drivers.Consume_One
                       (Valid_Driver, Valid_Budget, Consumed, Error);
                  end if;
                  pragma
                    Assert (Consumed and then Error.Code = Errors.No_Error);
               end loop;
            end if;

            Test_Hooks.Arm (Point);
            begin
               if Finish_Phase then
                  if Keep_Summaries then
                     JSON_Event_Drivers.Finish
                       (Valid_Driver, Events, Count, Error);
                  else
                     JSON_Event_Drivers.Finish (Valid_Driver, Error);
                  end if;
               else
                  if Keep_Summaries then
                     JSON_Event_Drivers.Consume_One
                       (Valid_Driver,
                        Valid_Budget,
                        Consumed,
                        Events,
                        Count,
                        Error);
                  else
                     JSON_Event_Drivers.Consume_One
                       (Valid_Driver, Valid_Budget, Consumed, Error);
                  end if;
               end if;
            exception
               when Constraint_Error =>
                  Raised := True;
            end;
            pragma Assert (Raised);

            Errors.Reset (Error);
            JSON_Event_Drivers.Reset (Valid_Driver, Error);
            Budgets.Initialize (Valid_Budget, Policy.Limits);
            for Index in Valid_Input'Range loop
               pragma Unreferenced (Index);
               if Keep_Summaries then
                  JSON_Event_Drivers.Consume_One
                    (Valid_Driver,
                     Valid_Budget,
                     Consumed,
                     Events,
                     Count,
                     Error);
               else
                  JSON_Event_Drivers.Consume_One
                    (Valid_Driver, Valid_Budget, Consumed, Error);
               end if;
               pragma Assert (Consumed and then Error.Code = Errors.No_Error);
            end loop;
            if Keep_Summaries then
               JSON_Event_Drivers.Finish (Valid_Driver, Events, Count, Error);
            else
               JSON_Event_Drivers.Finish (Valid_Driver, Error);
            end if;
            pragma Assert (Error.Code = Errors.No_Error);
         end Exercise;
      begin
         for Keep_Summaries in Boolean loop
            Exercise (Test_Hooks.Before_Step, False, Keep_Summaries);
            Exercise (Test_Hooks.After_Step, False, Keep_Summaries);
            Exercise (Test_Hooks.Before_Finish_Step, True, Keep_Summaries);
            Exercise (Test_Hooks.After_Finish_Step, True, Keep_Summaries);
         end loop;
      end;

      --  Every new one-step and provisional-boundary call cleans up an
      --  injected exception before Reset starts a complete new document.
      for Point in Test_Hooks.Before_Source_Copy .. Test_Hooks.After_Step loop
         declare
            Valid_Input  : aliased constant String := "null";
            Valid_Driver : JSON_Event_Drivers.Driver (Valid_Input'Access);
            Valid_Budget : Budgets.Decode_Budget;
            Outcome      : JSON_Event_Drivers.Driver_Outcome;
            Summary      : JSON_Event_Drivers.Event_Summary;
            Raised       : Boolean := False;
         begin
            Errors.Reset (Error);
            JSON_Event_Drivers.Initialize (Valid_Driver, Error);
            Budgets.Initialize (Valid_Budget, Policy.Limits);
            Test_Hooks.Arm (Point);
            begin
               JSON_Event_Drivers.Step_Source
                 (Valid_Driver,
                  Valid_Budget,
                  Outcome,
                  Consumed,
                  Summary,
                  Error);
            exception
               when Constraint_Error =>
                  Raised := True;
            end;
            pragma Assert (Raised);
            Reset_And_Complete
              (Valid_Driver, Valid_Budget, Valid_Input'Length, Error);
         end;
      end loop;

      for Point in Test_Hooks.Before_Step .. Test_Hooks.After_Step loop
         declare
            Valid_Input  : aliased constant String := "null";
            Valid_Driver : JSON_Event_Drivers.Driver (Valid_Input'Access);
            Valid_Budget : Budgets.Decode_Budget;
            Raised       : Boolean := False;
         begin
            Errors.Reset (Error);
            JSON_Event_Drivers.Initialize (Valid_Driver, Error);
            Budgets.Initialize (Valid_Budget, Policy.Limits);
            Test_Hooks.Arm (Point);
            begin
               JSON_Event_Drivers.Prime_Document_Begin (Valid_Driver, Error);
            exception
               when Constraint_Error =>
                  Raised := True;
            end;
            pragma Assert (Raised);
            Reset_And_Complete
              (Valid_Driver, Valid_Budget, Valid_Input'Length, Error);
         end;
      end loop;

      for Point in Test_Hooks.Before_Source_Copy .. Test_Hooks.After_Step loop
         declare
            Valid_Input  : aliased constant String := " null";
            Valid_Driver : JSON_Event_Drivers.Driver (Valid_Input'Access);
            Valid_Budget : Budgets.Decode_Budget;
            Raised       : Boolean := False;
         begin
            Errors.Reset (Error);
            JSON_Event_Drivers.Initialize (Valid_Driver, Error);
            Budgets.Initialize (Valid_Budget, Policy.Limits);
            JSON_Event_Drivers.Prime_Document_Begin (Valid_Driver, Error);
            Test_Hooks.Arm (Point);
            begin
               JSON_Event_Drivers.Consume_Leading_Whitespace
                 (Valid_Driver, Valid_Budget, Error);
            exception
               when Constraint_Error =>
                  Raised := True;
            end;
            pragma Assert (Raised);
            Reset_And_Complete
              (Valid_Driver, Valid_Budget, Valid_Input'Length, Error);
         end;
      end loop;

      for Point in
        Test_Hooks.Before_Finish_Step .. Test_Hooks.After_Finish_Step
      loop
         declare
            Valid_Input  : aliased constant String := "null";
            Valid_Driver : JSON_Event_Drivers.Driver (Valid_Input'Access);
            Valid_Budget : Budgets.Decode_Budget;
            Outcome      : JSON_Event_Drivers.Driver_Outcome;
            Summary      : JSON_Event_Drivers.Event_Summary;
            Raised       : Boolean := False;
         begin
            Errors.Reset (Error);
            JSON_Event_Drivers.Initialize (Valid_Driver, Error);
            Budgets.Initialize (Valid_Budget, Policy.Limits);
            while JSON_Event_Drivers.Input_Offset (Valid_Driver)
              < Valid_Input'Length
            loop
               JSON_Event_Drivers.Consume_One
                 (Valid_Driver, Valid_Budget, Consumed, Error);
            end loop;
            Test_Hooks.Arm (Point);
            begin
               JSON_Event_Drivers.Step_Final
                 (Valid_Driver, Outcome, Summary, Error);
            exception
               when Constraint_Error =>
                  Raised := True;
            end;
            pragma Assert (Raised);
            Reset_And_Complete
              (Valid_Driver, Valid_Budget, Valid_Input'Length, Error);
         end;
      end loop;

      for Point in Test_Hooks.Before_Step .. Test_Hooks.After_Step loop
         declare
            Valid_Input  : aliased constant String := "1 ";
            Valid_Driver : JSON_Event_Drivers.Driver (Valid_Input'Access);
            Valid_Budget : Budgets.Decode_Budget;
            Summary      : JSON_Event_Drivers.Event_Summary;
            Raised       : Boolean := False;
         begin
            Errors.Reset (Error);
            JSON_Event_Drivers.Initialize (Valid_Driver, Error);
            Budgets.Initialize (Valid_Budget, Policy.Limits);
            JSON_Event_Drivers.Consume_One
              (Valid_Driver, Valid_Budget, Consumed, Error);
            pragma
              Assert
                (Error.Code = Errors.No_Error
                   and then Consumed
                   and then JSON_Event_Drivers.Input_Offset (Valid_Driver)
                            = 1);
            Test_Hooks.Arm (Point);
            begin
               JSON_Event_Drivers.Observe_Number_End
                 (Valid_Driver, Summary, Error);
            exception
               when Constraint_Error =>
                  Raised := True;
            end;
            pragma Assert (Raised);
            Reset_And_Complete
              (Valid_Driver, Valid_Budget, Valid_Input'Length, Error);
         end;
      end loop;

      for Point in Test_Hooks.Before_Step .. Test_Hooks.After_Step loop
         declare
            Valid_Input  : aliased constant String := "1 ";
            Valid_Driver : JSON_Event_Drivers.Driver (Valid_Input'Access);
            Valid_Budget : Budgets.Decode_Budget;
            Outcome      : JSON_Event_Drivers.Driver_Outcome;
            Summary      : JSON_Event_Drivers.Event_Summary;
            Raised       : Boolean := False;
         begin
            Errors.Reset (Error);
            JSON_Event_Drivers.Initialize (Valid_Driver, Error);
            Budgets.Initialize (Valid_Budget, Policy.Limits);
            JSON_Event_Drivers.Consume_One
              (Valid_Driver, Valid_Budget, Consumed, Error);
            JSON_Event_Drivers.Observe_Number_End
              (Valid_Driver, Summary, Error);
            pragma Assert (Error.Code = Errors.No_Error);
            Test_Hooks.Arm (Point);
            begin
               JSON_Event_Drivers.Step_Source
                 (Valid_Driver,
                  Valid_Budget,
                  Outcome,
                  Consumed,
                  Summary,
                  Error);
            exception
               when Constraint_Error =>
                  Raised := True;
            end;
            pragma
              Assert
                (Raised and then Budgets.Input_Consumed (Valid_Budget) = 2);
            Reset_And_Complete
              (Valid_Driver, Valid_Budget, Valid_Input'Length, Error);
         end;
      end loop;
   end Assert_JSON_Driver_Lifecycle;

   procedure Assert_JSON_Preflights is
      Error          : Errors.Error_Info;
      String_Result  : Preflights.String_Summary;
      Number_Result  : Preflights.Number_Summary;
      type Short_Number_Array is array (Positive range <>) of String (1 .. 2);
      Bad_Numbers    : constant Short_Number_Array := ["01", "1e"];
      Simple_Escapes : constant String :=
        ['"', '\', '/', 'b', 'f', 'n', 'r', 't'];

      procedure Check_String
        (Input : String; Expected_Raw : Natural; Expected_Decoded : Natural) is
      begin
         Errors.Reset (Error);
         Preflights.Scan_String (Input, 0, Input'Length, String_Result, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then String_Result.Raw_Length = Expected_Raw
                and then String_Result.Decoded_Length = Expected_Decoded);
      end Check_String;

      procedure Check_Number
        (Input             : String;
         Expected_Raw      : Natural;
         Expected_Integer  : Boolean;
         Expected_Negative : Boolean) is
      begin
         Errors.Reset (Error);
         Preflights.Scan_Number (Input, 0, Input'Length, Number_Result, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Number_Result.Raw_Length = Expected_Raw
                and then Number_Result.Is_Integer = Expected_Integer
                and then Number_Result.Negative = Expected_Negative);
      end Check_Number;

      procedure Reject_String
        (Input           : String;
         Limit           : Natural;
         Expected_Code   : Errors.Error_Code;
         Expected_Offset : Natural) is
      begin
         Errors.Reset (Error);
         Preflights.Scan_String (Input, 0, Limit, String_Result, Error);
         pragma
           Assert
             (Error.Code = Expected_Code
                and then Error.Input_Offset = Expected_Offset
                and then String_Result = (others => <>),
              "string reject:"
                & Error.Code'Image
                & Error.Input_Offset'Image
                & Expected_Code'Image
                & Expected_Offset'Image
                & Input'Length'Image
                & Limit'Image);
      end Reject_String;

      procedure Reject_Number
        (Input           : String;
         Limit           : Natural;
         Expected_Code   : Errors.Error_Code;
         Expected_Offset : Natural) is
      begin
         Errors.Reset (Error);
         Preflights.Scan_Number (Input, 0, Limit, Number_Result, Error);
         pragma
           Assert
             (Error.Code = Expected_Code
                and then Error.Input_Offset = Expected_Offset
                and then Number_Result = (others => <>));
      end Reject_Number;
   begin
      Check_String ("""abc""", 5, 3);
      Check_String ("""\u20AC""", 8, 3);
      Check_String ("""\uD834\uDD1E""", 14, 4);
      Check_String
        ([1 => '"',
          2 => Character'Val (16#E2#),
          3 => Character'Val (16#82#),
          4 => Character'Val (16#AC#),
          5 => '"'],
         5,
         3);
      Check_String
        ([1 => '"',
          2 => Character'Val (16#F0#),
          3 => Character'Val (16#9F#),
          4 => Character'Val (16#98#),
          5 => Character'Val (16#80#),
          6 => '"'],
         6,
         4);
      for Escape of Simple_Escapes loop
         Check_String ([1 => '"', 2 => '\', 3 => Escape, 4 => '"'], 4, 1);
      end loop;

      Reject_String ([1 => '"', 2 => '\'], 2, Errors.Syntax_Error, 2);
      Reject_String
        ([1 => '"', 2 => '\', 3 => 'u', 4 => '1'], 4, Errors.Syntax_Error, 3);
      Reject_String
        ([1 => '"', 2 => '\', 3 => 'u'], 3, Errors.Syntax_Error, 3);
      Reject_String
        ([1 => '"', 2 => '\', 3 => 'u', 4 => '1', 5 => '2'],
         5,
         Errors.Syntax_Error,
         3);
      Reject_String
        ([1 => '"', 2 => '\', 3 => 'u', 4 => '1', 5 => '2', 6 => '3'],
         6,
         Errors.Syntax_Error,
         3);
      Reject_String ("""\uG234""", 8, Errors.Syntax_Error, 3);
      Reject_String ("""\u1G34""", 8, Errors.Syntax_Error, 4);
      Reject_String ("""\u12G4""", 8, Errors.Syntax_Error, 5);
      Reject_String ("""\u123G""", 8, Errors.Syntax_Error, 6);
      Reject_String ("""\q""", 4, Errors.Syntax_Error, 2);
      Reject_String
        ([1 => '"', 2 => ASCII.NUL, 3 => '"'], 3, Errors.Syntax_Error, 1);
      Reject_String ("""\uDC00""", 8, Errors.Invalid_Text, 3);
      Reject_String ("""\uD800x""", 9, Errors.Invalid_Text, 7);
      Reject_String
        ([1 => '"',
          2 => '\',
          3 => 'u',
          4 => 'D',
          5 => '8',
          6 => '0',
          7 => '0'],
         7,
         Errors.Invalid_Text,
         7);
      Reject_String
        ([1 => '"',
          2 => '\',
          3 => 'u',
          4 => 'D',
          5 => '8',
          6 => '0',
          7 => '0',
          8 => '\'],
         8,
         Errors.Invalid_Text,
         7);
      for Low_Digits in 0 .. 3 loop
         declare
            Complete : constant String := """\uD800\uDC00""";
            Last     : constant Positive := 9 + Low_Digits;
         begin
            Reject_String
              (Complete (Complete'First .. Last),
               Last,
               Errors.Syntax_Error,
               9);
         end;
      end loop;
      Reject_String ("""\uD800\u0041""", 14, Errors.Invalid_Text, 9);

      declare
         Pair : constant String := """\uD834\uDD1E""";
      begin
         for Limit in 0 .. Pair'Length - 1 loop
            Reject_String (Pair, Limit, Errors.Capacity_Exceeded, Limit);
         end loop;
      end;

      declare
         Input : constant String := """a""";
      begin
         for Limit in 0 .. Input'Length - 1 loop
            Errors.Reset (Error);
            Preflights.Scan_String (Input, 0, Limit, String_Result, Error);
            pragma
              Assert
                (Error.Code = Errors.Capacity_Exceeded
                   and then Error.Input_Offset = Limit
                   and then String_Result = (others => <>));
         end loop;
      end;

      declare
         Input : constant String :=
           [1 => '"', 2 => Character'Val (16#C3#), 3 => '"'];
      begin
         Errors.Reset (Error);
         Preflights.Scan_String (Input, 0, Input'Length, String_Result, Error);
         pragma
           Assert
             (Error.Code = Errors.Invalid_Text
                and then Error.Input_Offset = 1
                and then String_Result.Raw_Length = 0);
      end;

      Reject_String
        ([1 => '"',
          2 => Character'Val (16#C0#),
          3 => Character'Val (16#AF#),
          4 => '"'],
         4,
         Errors.Invalid_Text,
         1);
      Reject_String
        ([1 => '"',
          2 => Character'Val (16#E2#),
          3 => '(',
          4 => Character'Val (16#A1#),
          5 => '"'],
         5,
         Errors.Invalid_Text,
         2);
      Reject_String
        ([1 => '"',
          2 => Character'Val (16#ED#),
          3 => Character'Val (16#A0#),
          4 => Character'Val (16#80#),
          5 => '"'],
         5,
         Errors.Invalid_Text,
         2);
      Reject_String
        ([1 => '"',
          2 => Character'Val (16#E2#),
          3 => Character'Val (16#82#),
          4 => '"'],
         4,
         Errors.Invalid_Text,
         1);
      Reject_String
        ([1 => '"',
          2 => Character'Val (16#F1#),
          3 => Character'Val (16#80#),
          4 => Character'Val (16#80#),
          5 => '"'],
         5,
         Errors.Invalid_Text,
         1);
      Reject_String
        ([1 => '"',
          2 => Character'Val (16#F4#),
          3 => Character'Val (16#90#),
          4 => Character'Val (16#80#),
          5 => Character'Val (16#80#),
          6 => '"'],
         6,
         Errors.Invalid_Text,
         2);

      declare
         Input : constant String :=
           [Positive'Last - 1 => '"', Positive'Last => '"'];
      begin
         Errors.Reset (Error);
         Preflights.Scan_String (Input, 0, Input'Length, String_Result, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then String_Result.Raw_Length = 2
                and then String_Result.Decoded_Length = 0);
      end;

      Check_Number ("0", 1, True, False);
      Check_Number ("-1", 2, True, True);
      Check_Number ("1.5", 3, False, False);
      Check_Number ("1e+2", 4, False, False);
      Check_Number ("12x", 2, True, False);
      Check_Number ("-0", 2, True, True);
      Reject_Number ("", 0, Errors.Syntax_Error, 0);
      Reject_Number ("-", 1, Errors.Syntax_Error, 1);
      Reject_Number ("1.", 2, Errors.Syntax_Error, 2);
      Reject_Number ("1E", 2, Errors.Syntax_Error, 2);
      Reject_Number ("1e+", 3, Errors.Syntax_Error, 3);
      Reject_Number ("1e-", 3, Errors.Syntax_Error, 3);
      Reject_Number ("x", 1, Errors.Syntax_Error, 0);

      declare
         Input : constant String := "1.2e+3 ";
      begin
         for Limit in 0 .. Input'Length - 1 loop
            Reject_Number (Input, Limit, Errors.Capacity_Exceeded, Limit);
         end loop;
      end;

      declare
         Input : constant String := "12 ";
      begin
         Errors.Reset (Error);
         Preflights.Scan_Number (Input, 0, 2, Number_Result, Error);
         pragma
           Assert
             (Error.Code = Errors.Capacity_Exceeded
                and then Error.Input_Offset = 2
                and then Number_Result.Raw_Length = 0);
      end;

      for Input of Bad_Numbers loop
         Errors.Reset (Error);
         Preflights.Scan_Number (Input, 0, Input'Length, Number_Result, Error);
         pragma Assert (Error.Code = Errors.Syntax_Error);
      end loop;

      declare
         Input : constant String := [Positive'Last => '7'];
      begin
         Errors.Reset (Error);
         Preflights.Scan_Number (Input, 0, Input'Length, Number_Result, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Number_Result.Raw_Length = 1);
      end;

      Errors.Reset (Error);
      Preflights.Match_Literal ("true", 0, 4, "true", Error);
      pragma Assert (Error.Code = Errors.No_Error);

      Errors.Reset (Error);
      Preflights.Match_Literal ("truX", 0, 4, "true", Error);
      pragma
        Assert
          (Error.Code = Errors.Syntax_Error and then Error.Input_Offset = 3);

      Errors.Reset (Error);
      Preflights.Match_Literal ("Xrue", 0, 3, "true", Error);
      pragma
        Assert
          (Error.Code = Errors.Syntax_Error and then Error.Input_Offset = 0);

      Errors.Reset (Error);
      Preflights.Match_Literal ("tXue", 0, 3, "true", Error);
      pragma
        Assert
          (Error.Code = Errors.Syntax_Error and then Error.Input_Offset = 1);

      Errors.Reset (Error);
      Preflights.Match_Literal ("tru", 0, 3, "true", Error);
      pragma
        Assert
          (Error.Code = Errors.Syntax_Error and then Error.Input_Offset = 0);

      Errors.Reset (Error);
      Preflights.Match_Literal ("tX", 0, 2, "true", Error);
      pragma
        Assert
          (Error.Code = Errors.Syntax_Error and then Error.Input_Offset = 0);

      Errors.Reset (Error);
      Preflights.Match_Literal ("tr", 0, 1, "true", Error);
      pragma
        Assert
          (Error.Code = Errors.Syntax_Error and then Error.Input_Offset = 0);

      Errors.Reset (Error);
      Preflights.Match_Literal ("true", 0, 3, "true", Error);
      pragma
        Assert
          (Error.Code = Errors.Capacity_Exceeded
             and then Error.Input_Offset = 3);

      Errors.Reset (Error);
      Preflights.Match_Literal ("truX", 0, 3, "true", Error);
      pragma
        Assert
          (Error.Code = Errors.Capacity_Exceeded
             and then Error.Input_Offset = 3);

      declare
         Input : constant String :=
           [Positive'Last - 3 => 'n',
            Positive'Last - 2 => 'u',
            Positive'Last - 1 => 'l',
            Positive'Last     => 'l'];
      begin
         Errors.Reset (Error);
         Preflights.Match_Literal (Input, 0, 4, "null", Error);
         pragma Assert (Error.Code = Errors.No_Error);
      end;

      declare
         Source  : constant String := "xx""a""";
         Literal : constant String :=
           [17 => 't', 18 => 'r', 19 => 'u', 20 => 'e'];
      begin
         Errors.Reset (Error);
         Preflights.Scan_String (Source, 2, 3, String_Result, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then String_Result.Raw_Length = 3
                and then String_Result.Decoded_Length = 1);

         Errors.Reset (Error);
         Preflights.Scan_Number ("xx12 ", 2, 3, Number_Result, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Number_Result.Raw_Length = 2);

         Errors.Reset (Error);
         Preflights.Scan_Number ("xx12 ", 2, 2, Number_Result, Error);
         pragma
           Assert
             (Error.Code = Errors.Capacity_Exceeded
                and then Error.Input_Offset = 4
                and then Number_Result = (others => <>));

         Errors.Reset (Error);
         Preflights.Match_Literal ("xxtrue", 2, 4, Literal, Error);
         pragma Assert (Error.Code = Errors.No_Error);

         Errors.Reset (Error);
         Preflights.Match_Literal ("xxtrue", 2, 3, Literal, Error);
         pragma
           Assert
             (Error.Code = Errors.Capacity_Exceeded
                and then Error.Input_Offset = 5);
      end;

      declare
         Empty : constant String (1 .. 0) := [];
      begin
         Reject_String (Empty, 0, Errors.Syntax_Error, 0);
         Reject_Number (Empty, 0, Errors.Syntax_Error, 0);
         Errors.Reset (Error);
         Preflights.Match_Literal (Empty, 0, 0, "null", Error);
         pragma
           Assert
             (Error.Code = Errors.Syntax_Error
                and then Error.Input_Offset = 0);

         Errors.Reset (Error);
         Preflights.Scan_String ("x", 2, 0, String_Result, Error);
         pragma Assert (Error.Code = Errors.Invalid_State);
         Errors.Reset (Error);
         Preflights.Scan_Number ("x", 2, 0, Number_Result, Error);
         pragma Assert (Error.Code = Errors.Invalid_State);
         Errors.Reset (Error);
         Preflights.Match_Literal ("x", 2, 0, "null", Error);
         pragma Assert (Error.Code = Errors.Invalid_State);
         Errors.Reset (Error);
         Preflights.Match_Literal ("x", 0, 1, Empty, Error);
         pragma Assert (Error.Code = Errors.Invalid_State);
      end;

      Errors.Reset (Error);
      Errors.Fail (Error, Errors.Application_Error, 9, Errors.Byte_Offset);
      String_Result := (Raw_Length => 99, Decoded_Length => 99);
      Preflights.Scan_String ("""x""", 0, 3, String_Result, Error);
      pragma
        Assert
          (Error.Code = Errors.Application_Error
             and then String_Result = (others => <>));
      Number_Result :=
        (Raw_Length => 99, Is_Integer => False, Negative => True);
      Preflights.Scan_Number ("1", 0, 1, Number_Result, Error);
      pragma Assert (Number_Result = (others => <>));
      Preflights.Match_Literal ("null", 0, 4, "null", Error);
      pragma
        Assert
          (Error.Code = Errors.Application_Error
             and then Error.Input_Offset = 9);
   end Assert_JSON_Preflights;

   procedure Assert_JSON_Event_Scalar_Reader is
      Policy : constant Policies.Decode_Policy := (others => <>);

      procedure Assert_Same
        (Oracle         : Reader;
         Parallel       : Event_Readers.Reader;
         Oracle_Error   : Errors.Error_Info;
         Parallel_Error : Errors.Error_Info) is
      begin
         pragma Assert (Parallel_Error.Code = Oracle_Error.Code);
         pragma
           Assert
             (Parallel_Error.Input_Offset = Oracle_Error.Input_Offset
                and then Parallel_Error.Offset_Unit = Oracle_Error.Offset_Unit
                and then Parallel_Error.Path_Length
                         = Oracle_Error.Path_Length);
         pragma
           Assert
             (Event_Readers.Input_Offset (Parallel) = Input_Offset (Oracle));
         pragma
           Assert
             (Event_Readers.Input_Consumed (Parallel)
                = Budgets.Input_Consumed (Oracle.Budget));
         pragma
           Assert
             (Event_Readers.Values_Consumed (Parallel)
                = Budgets.Values_Consumed (Oracle.Budget));
         pragma
           Assert
             (Event_Readers.Container_Depth (Parallel) = Oracle.Depth
                and then Event_Readers.Budget_Depth (Parallel)
                         = Budgets.Depth (Oracle.Budget),
              Event_Readers.Container_Depth (Parallel)'Image
                & Oracle.Depth'Image
                & Event_Readers.Budget_Depth (Parallel)'Image
                & Budgets.Depth (Oracle.Budget)'Image);
         pragma
           Assert
             (Event_Readers.Is_Complete (Parallel) = Is_Complete (Oracle));
      end Assert_Same;

      procedure Check_Null
        (Source         : String;
         Maximum_Input  : Natural := Natural'Last;
         Maximum_Values : Natural := Natural'Last)
      is
         Input          : aliased constant String := Source;
         Oracle         : Reader (Input'Access);
         Parallel       : Event_Readers.Reader (Input'Access);
         Oracle_Error   : Errors.Error_Info;
         Parallel_Error : Errors.Error_Info;
         Local_Policy   : Policies.Decode_Policy := Policy;
      begin
         Local_Policy.Limits.Maximum_Input_Units := Maximum_Input;
         Local_Policy.Limits.Maximum_Logical_Values := Maximum_Values;
         Initialize (Oracle, Local_Policy);
         Event_Readers.Initialize (Parallel, Local_Policy, Parallel_Error);
         pragma Assert (Parallel_Error.Code = Errors.No_Error);

         Read_Null (Oracle, Oracle_Error);
         Event_Readers.Read_Null (Parallel, Parallel_Error);
         Assert_Same (Oracle, Parallel, Oracle_Error, Parallel_Error);
         if Oracle_Error.Code = Errors.No_Error then
            Finish_Document (Oracle, Oracle_Error);
            Event_Readers.Finish_Document (Parallel, Parallel_Error);
            Assert_Same (Oracle, Parallel, Oracle_Error, Parallel_Error);
         end if;
      end Check_Null;

      procedure Check_Boolean
        (Source : String; Maximum_Input : Natural := Natural'Last)
      is
         Input          : aliased constant String := Source;
         Oracle         : Reader (Input'Access);
         Parallel       : Event_Readers.Reader (Input'Access);
         Oracle_Error   : Errors.Error_Info;
         Parallel_Error : Errors.Error_Info;
         Oracle_Value   : Boolean;
         Parallel_Value : Boolean;
         Local_Policy   : Policies.Decode_Policy := Policy;
      begin
         Local_Policy.Limits.Maximum_Input_Units := Maximum_Input;
         Initialize (Oracle, Local_Policy);
         Event_Readers.Initialize (Parallel, Local_Policy, Parallel_Error);
         pragma Assert (Parallel_Error.Code = Errors.No_Error);

         Read_Boolean (Oracle, Oracle_Value, Oracle_Error);
         Event_Readers.Read_Boolean (Parallel, Parallel_Value, Parallel_Error);
         pragma Assert (Parallel_Value = Oracle_Value);
         Assert_Same (Oracle, Parallel, Oracle_Error, Parallel_Error);
         if Oracle_Error.Code = Errors.No_Error then
            Finish_Document (Oracle, Oracle_Error);
            Event_Readers.Finish_Document (Parallel, Parallel_Error);
            Assert_Same (Oracle, Parallel, Oracle_Error, Parallel_Error);
         end if;
      end Check_Boolean;

      procedure Check_Text
        (Source : String; Maximum_Input : Natural := Natural'Last)
      is
         Input           : aliased constant String := Source;
         Oracle          : Reader (Input'Access);
         Parallel        : Event_Readers.Reader (Input'Access);
         Oracle_Error    : Errors.Error_Info;
         Parallel_Error  : Errors.Error_Info;
         Oracle_Value    : String (3 .. 34);
         Parallel_Value  : String (7 .. 38);
         Oracle_Length   : Natural;
         Parallel_Length : Natural;
         Local_Policy    : Policies.Decode_Policy := Policy;
      begin
         Local_Policy.Limits.Maximum_Input_Units := Maximum_Input;
         Initialize (Oracle, Local_Policy);
         Event_Readers.Initialize (Parallel, Local_Policy, Parallel_Error);
         pragma Assert (Parallel_Error.Code = Errors.No_Error);

         Read_Text (Oracle, Oracle_Value, Oracle_Length, Oracle_Error);
         Event_Readers.Read_Text
           (Parallel, Parallel_Value, Parallel_Length, Parallel_Error);
         pragma Assert (Parallel_Length = Oracle_Length);
         pragma
           Assert
             (Parallel_Value
                (Parallel_Value'First
                 .. Parallel_Value'First + Parallel_Length - 1)
                = Oracle_Value
                    (Oracle_Value'First
                     .. Oracle_Value'First + Oracle_Length - 1));
         pragma
           Assert
             ((for all Index in Parallel_Value'Range =>
                 (if Index >= Parallel_Value'First + Parallel_Length
                  then Parallel_Value (Index) = ' ')));
         Assert_Same (Oracle, Parallel, Oracle_Error, Parallel_Error);
         if Oracle_Error.Code = Errors.No_Error then
            Finish_Document (Oracle, Oracle_Error);
            Event_Readers.Finish_Document (Parallel, Parallel_Error);
            Assert_Same (Oracle, Parallel, Oracle_Error, Parallel_Error);
         end if;
      end Check_Text;

      procedure Check_Signed (Source : String) is
         Input          : aliased constant String := Source;
         Oracle         : Reader (Input'Access);
         Parallel       : Event_Readers.Reader (Input'Access);
         Oracle_Error   : Errors.Error_Info;
         Parallel_Error : Errors.Error_Info;
         Oracle_Value   : Interfaces.Integer_64;
         Parallel_Value : Interfaces.Integer_64;
      begin
         Initialize (Oracle, Policy);
         Event_Readers.Initialize (Parallel, Policy, Parallel_Error);
         Read_Signed (Oracle, Oracle_Value, Oracle_Error);
         Event_Readers.Read_Signed (Parallel, Parallel_Value, Parallel_Error);
         pragma Assert (Parallel_Value = Oracle_Value);
         Assert_Same (Oracle, Parallel, Oracle_Error, Parallel_Error);
         if Oracle_Error.Code = Errors.No_Error then
            Finish_Document (Oracle, Oracle_Error);
            Event_Readers.Finish_Document (Parallel, Parallel_Error);
            Assert_Same (Oracle, Parallel, Oracle_Error, Parallel_Error);
         end if;
      end Check_Signed;

      procedure Check_Unsigned
        (Source : String; Maximum_Input : Natural := Natural'Last)
      is
         Input          : aliased constant String := Source;
         Oracle         : Reader (Input'Access);
         Parallel       : Event_Readers.Reader (Input'Access);
         Oracle_Error   : Errors.Error_Info;
         Parallel_Error : Errors.Error_Info;
         Oracle_Value   : Interfaces.Unsigned_64;
         Parallel_Value : Interfaces.Unsigned_64;
         Local_Policy   : Policies.Decode_Policy := Policy;
      begin
         Local_Policy.Limits.Maximum_Input_Units := Maximum_Input;
         Initialize (Oracle, Local_Policy);
         Event_Readers.Initialize (Parallel, Local_Policy, Parallel_Error);
         Read_Unsigned (Oracle, Oracle_Value, Oracle_Error);
         Event_Readers.Read_Unsigned
           (Parallel, Parallel_Value, Parallel_Error);
         pragma Assert (Parallel_Value = Oracle_Value);
         Assert_Same (Oracle, Parallel, Oracle_Error, Parallel_Error);
         if Oracle_Error.Code = Errors.No_Error then
            Finish_Document (Oracle, Oracle_Error);
            Event_Readers.Finish_Document (Parallel, Parallel_Error);
            Assert_Same (Oracle, Parallel, Oracle_Error, Parallel_Error);
         end if;
      end Check_Unsigned;

      procedure Check_Float (Source : String) is
         Input          : aliased constant String := Source;
         Oracle         : Reader (Input'Access);
         Parallel       : Event_Readers.Reader (Input'Access);
         Oracle_Error   : Errors.Error_Info;
         Parallel_Error : Errors.Error_Info;
         Oracle_Value   : Data_Model.Float_64_Value;
         Parallel_Value : Data_Model.Float_64_Value;
      begin
         Initialize (Oracle, Policy);
         Event_Readers.Initialize (Parallel, Policy, Parallel_Error);
         Read_Float_64 (Oracle, Oracle_Value, Oracle_Error);
         Event_Readers.Read_Float_64
           (Parallel, Parallel_Value, Parallel_Error);
         pragma
           Assert
             (Data_Model.Category (Parallel_Value)
                = Data_Model.Category (Oracle_Value));
         if Data_Model.Category (Oracle_Value) = Data_Model.Finite_Float then
            pragma
              Assert
                (Data_Model.Finite_Value (Parallel_Value)
                   = Data_Model.Finite_Value (Oracle_Value)
                   and then Data_Model.Is_Negative_Zero (Parallel_Value)
                            = Data_Model.Is_Negative_Zero (Oracle_Value));
         end if;
         Assert_Same (Oracle, Parallel, Oracle_Error, Parallel_Error);
         if Oracle_Error.Code = Errors.No_Error then
            Finish_Document (Oracle, Oracle_Error);
            Event_Readers.Finish_Document (Parallel, Parallel_Error);
            Assert_Same (Oracle, Parallel, Oracle_Error, Parallel_Error);
         end if;
      end Check_Float;

      procedure Check_Peek (Source : String) is
         Input          : aliased constant String := Source;
         Oracle         : Reader (Input'Access);
         Parallel       : Event_Readers.Reader (Input'Access);
         Oracle_Error   : Errors.Error_Info;
         Parallel_Error : Errors.Error_Info;
         Oracle_Kind    : Data_Model.Value_Kind;
         Parallel_Kind  : Data_Model.Value_Kind;
      begin
         Initialize (Oracle, Policy);
         Event_Readers.Initialize (Parallel, Policy, Parallel_Error);
         Oracle_Kind := Peek_Kind (Oracle, Oracle_Error);
         Parallel_Kind := Event_Readers.Peek_Kind (Parallel, Parallel_Error);
         pragma Assert (Parallel_Kind = Oracle_Kind);
         Assert_Same (Oracle, Parallel, Oracle_Error, Parallel_Error);
         if Oracle_Error.Code = Errors.No_Error then
            Oracle_Kind := Peek_Kind (Oracle, Oracle_Error);
            Parallel_Kind :=
              Event_Readers.Peek_Kind (Parallel, Parallel_Error);
            pragma Assert (Parallel_Kind = Oracle_Kind);
            Assert_Same (Oracle, Parallel, Oracle_Error, Parallel_Error);
         end if;
      end Check_Peek;

      procedure Check_Text_Capacity
        (Source       : String;
         Capacity     : Natural;
         Maximum_Text : Natural := Natural'Last)
      is
         Input           : aliased constant String := Source;
         Oracle          : Reader (Input'Access);
         Parallel        : Event_Readers.Reader (Input'Access);
         Oracle_Error    : Errors.Error_Info;
         Parallel_Error  : Errors.Error_Info;
         Oracle_Value    : String (5 .. 4 + Capacity);
         Parallel_Value  : String (9 .. 8 + Capacity);
         Oracle_Length   : Natural;
         Parallel_Length : Natural;
         Local_Policy    : Policies.Decode_Policy := Policy;
      begin
         Local_Policy.Limits.Maximum_Text_Length := Maximum_Text;
         Initialize (Oracle, Local_Policy);
         Event_Readers.Initialize (Parallel, Local_Policy, Parallel_Error);
         Read_Text (Oracle, Oracle_Value, Oracle_Length, Oracle_Error);
         Event_Readers.Read_Text
           (Parallel, Parallel_Value, Parallel_Length, Parallel_Error);
         pragma
           Assert
             (Parallel_Length = Oracle_Length
                and then (for all Value of Parallel_Value => Value = ' '));
         Assert_Same (Oracle, Parallel, Oracle_Error, Parallel_Error);
      end Check_Text_Capacity;

      type Supported_Operation is
        (Peek_Operation,
         Read_Null_Operation,
         Read_Boolean_Operation,
         Read_Signed_Operation,
         Read_Unsigned_Operation,
         Read_Float_Operation,
         Read_Text_Operation,
         Begin_Sequence_Operation,
         Next_Element_Operation,
         End_Sequence_Operation);

      procedure Check_Prelatched (Operation : Supported_Operation) is
         Input          : aliased constant String := "null";
         Item           : Event_Readers.Reader (Input'Access);
         Error          : Errors.Error_Info;
         Kind           : Data_Model.Value_Kind := Data_Model.Text_Value;
         Boolean_Value  : Boolean := True;
         Signed_Value   : Interfaces.Integer_64 := 99;
         Unsigned_Value : Interfaces.Unsigned_64 := 99;
         Float_Value    : Data_Model.Float_64_Value :=
           Data_Model.Make_Finite (99.0);
         Text           : String (5 .. 8) := [others => 'x'];
         Length         : Natural := 99;
         Info           : Data_Model.Length_Information :=
           (Known => True, Length => 99);
         Available      : Boolean := True;
      begin
         Event_Readers.Initialize (Item, Policy, Error);
         Errors.Fail (Error, Errors.Application_Error, 17, Errors.Byte_Offset);
         case Operation is
            when Peek_Operation           =>
               Kind := Event_Readers.Peek_Kind (Item, Error);
               pragma Assert (Kind = Data_Model.Null_Value);

            when Read_Null_Operation      =>
               Event_Readers.Read_Null (Item, Error);

            when Read_Boolean_Operation   =>
               Event_Readers.Read_Boolean (Item, Boolean_Value, Error);
               pragma Assert (not Boolean_Value);

            when Read_Signed_Operation    =>
               Event_Readers.Read_Signed (Item, Signed_Value, Error);
               pragma Assert (Signed_Value = 0);

            when Read_Unsigned_Operation  =>
               Event_Readers.Read_Unsigned (Item, Unsigned_Value, Error);
               pragma Assert (Unsigned_Value = 0);

            when Read_Float_Operation     =>
               Event_Readers.Read_Float_64 (Item, Float_Value, Error);
               pragma
                 Assert
                   (Data_Model.Finite_Value (Float_Value) = 0.0
                      and then not Data_Model.Is_Negative_Zero (Float_Value));

            when Read_Text_Operation      =>
               Event_Readers.Read_Text (Item, Text, Length, Error);
               pragma
                 Assert
                   (Length = 0
                      and then (for all Value of Text => Value = ' '));

            when Begin_Sequence_Operation =>
               Event_Readers.Begin_Sequence (Item, Info, Error);
               pragma Assert (not Info.Known and then Info.Length = 0);

            when Next_Element_Operation   =>
               Event_Readers.Next_Element (Item, Available, Error);
               pragma Assert (not Available);

            when End_Sequence_Operation   =>
               Event_Readers.End_Sequence (Item, Error);
         end case;
         pragma
           Assert
             (Error.Code = Errors.Application_Error
                and then Error.Input_Offset = 17
                and then Event_Readers.Input_Offset (Item) = 0
                and then Event_Readers.Input_Consumed (Item) = 0
                and then Event_Readers.Values_Consumed (Item) = 0);
         Errors.Reset (Error);
         Event_Readers.Read_Null (Item, Error);
         Event_Readers.Finish_Document (Item, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Event_Readers.Is_Complete (Item),
              Operation'Image
                & Error.Code'Image
                & Error.Input_Offset'Image
                & Event_Readers.Input_Offset (Item)'Image);
      end Check_Prelatched;

      type Unsupported_Operation is
        (Read_Bytes_Operation,
         Skip_Value_Operation,
         Begin_Optional_Operation,
         End_Optional_Operation,
         Begin_Map_Operation,
         Next_Map_Entry_Operation,
         End_Map_Operation,
         Begin_Record_Operation,
         Next_Field_Operation,
         End_Record_Operation,
         Read_Enumeration_Operation,
         Begin_Variant_Operation,
         End_Variant_Operation);

      procedure Check_Unsupported (Operation : Unsupported_Operation) is
         Input     : aliased constant String := "null";
         Item      : Event_Readers.Reader (Input'Access);
         Error     : Errors.Error_Info;
         Bytes     : Ada.Streams.Stream_Element_Array (5 .. 6) :=
           [others => 9];
         Text      : String (7 .. 14) := [others => 'x'];
         Length    : Natural := 99;
         Name_Len  : Natural := 99;
         Available : Boolean := True;
         Present   : Boolean := True;
         Info      : Data_Model.Length_Information :=
           (Known => True, Length => 99);
         procedure Invoke is
         begin
            case Operation is
               when Read_Bytes_Operation       =>
                  Event_Readers.Read_Bytes (Item, Bytes, Length, Error);
                  pragma
                    Assert
                      (Length = 0
                         and then (for all Value of Bytes => Value = 0));

               when Skip_Value_Operation       =>
                  Event_Readers.Skip_Value (Item, Error);

               when Begin_Optional_Operation   =>
                  Event_Readers.Begin_Optional (Item, Present, Error);
                  pragma Assert (not Present);

               when End_Optional_Operation     =>
                  Event_Readers.End_Optional (Item, Error);

               when Begin_Map_Operation        =>
                  Event_Readers.Begin_Map (Item, Info, Error);
                  pragma Assert (not Info.Known and then Info.Length = 0);

               when Next_Map_Entry_Operation   =>
                  Event_Readers.Next_Map_Entry (Item, Available, Error);
                  pragma Assert (not Available);

               when End_Map_Operation          =>
                  Event_Readers.End_Map (Item, Error);

               when Begin_Record_Operation     =>
                  Event_Readers.Begin_Record (Item, "T", Info, Error);
                  pragma Assert (not Info.Known and then Info.Length = 0);

               when Next_Field_Operation       =>
                  Event_Readers.Next_Field
                    (Item, Text, Name_Len, Available, Error);
                  pragma
                    Assert
                      (Name_Len = 0
                         and then not Available
                         and then (for all Value of Text => Value = ' '));

               when End_Record_Operation       =>
                  Event_Readers.End_Record (Item, Error);

               when Read_Enumeration_Operation =>
                  Event_Readers.Read_Enumeration
                    (Item, "T", Text, Name_Len, Error);
                  pragma
                    Assert
                      (Name_Len = 0
                         and then (for all Value of Text => Value = ' '));

               when Begin_Variant_Operation    =>
                  Event_Readers.Begin_Variant
                    (Item, "T", Text, Name_Len, Info, Error);
                  pragma
                    Assert
                      (Name_Len = 0
                         and then not Info.Known
                         and then Info.Length = 0
                         and then (for all Value of Text => Value = ' '));

               when End_Variant_Operation      =>
                  Event_Readers.End_Variant (Item, Error);
            end case;
         end Invoke;
      begin
         Event_Readers.Initialize (Item, Policy, Error);
         Errors.Fail (Error, Errors.Application_Error, 17, Errors.Byte_Offset);
         Invoke;
         pragma
           Assert
             (Error.Code = Errors.Application_Error
                and then Error.Input_Offset = 17
                and then Event_Readers.Input_Offset (Item) = 0
                and then Event_Readers.Input_Consumed (Item) = 0
                and then Event_Readers.Values_Consumed (Item) = 0);
         Errors.Reset (Error);
         Event_Readers.Read_Null (Item, Error);
         Event_Readers.Finish_Document (Item, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Event_Readers.Is_Complete (Item));
         Event_Readers.Reset (Item, Policy, Error);
         Invoke;

         pragma
           Assert
             (Error.Code = Errors.Invalid_State
                and then Error.Input_Offset = 0
                and then Event_Readers.Input_Offset (Item) = 0
                and then Event_Readers.Input_Consumed (Item) = 0
                and then Event_Readers.Values_Consumed (Item) = 0);
         Errors.Reset (Error);
         Event_Readers.Read_Null (Item, Error);
         pragma Assert (Error.Code = Errors.Invalid_State);
         Errors.Reset (Error);
         Event_Readers.Reset (Item, Policy, Error);
         Event_Readers.Read_Null (Item, Error);
         Event_Readers.Finish_Document (Item, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Event_Readers.Is_Complete (Item));
      end Check_Unsupported;

      package U64_Adapter is new
        Flyology_Serde.Adapters.Unsigned_Integers (Interfaces.Unsigned_64);

      type U64_Builder is limited record
         Published : Interfaces.Unsigned_64 := 41;
         Candidate : Interfaces.Unsigned_64 := 0;
         Commits   : Natural := 0;
         Rollbacks : Natural := 0;
      end record;

      procedure Begin_U64
        (Target : in out U64_Builder; Error : in out Errors.Error_Info)
      is
         pragma Unreferenced (Error);
      begin
         Target.Candidate := 0;
      end Begin_U64;

      procedure Read_U64
        (From   : in out Deserialization.Deserializer'Class;
         Target : in out U64_Builder;
         Policy : Policies.Decode_Policy;
         Error  : in out Errors.Error_Info)
      is
         pragma Unreferenced (Policy);
      begin
         U64_Adapter.Deserialize_Candidate (From, Target.Candidate, Error);
      end Read_U64;

      procedure Commit_U64
        (Target : in out U64_Builder; Error : in out Errors.Error_Info)
      is
         pragma Unreferenced (Error);
      begin
         Target.Published := Target.Candidate;
         Target.Commits := Target.Commits + 1;
      end Commit_U64;

      procedure Rollback_U64 (Target : in out U64_Builder) is
      begin
         Target.Candidate := 0;
         Target.Rollbacks := Target.Rollbacks + 1;
      end Rollback_U64;

      procedure Check_Sequence_Parity is
         Input                : aliased constant String :=
           "[null, true, [-1, ""x""]]";
         Oracle               : Reader (Input'Access);
         Parallel             : Event_Readers.Reader (Input'Access);
         Oracle_Error         : Errors.Error_Info;
         Parallel_Error       : Errors.Error_Info;
         Oracle_Length        : Data_Model.Length_Information;
         Parallel_Length      : Data_Model.Length_Information;
         Oracle_Available     : Boolean;
         Parallel_Available   : Boolean;
         Oracle_Boolean       : Boolean;
         Parallel_Boolean     : Boolean;
         Oracle_Signed        : Interfaces.Integer_64;
         Parallel_Signed      : Interfaces.Integer_64;
         Oracle_Text          : String (5 .. 5);
         Parallel_Text        : String (5 .. 5);
         Oracle_Text_Length   : Natural;
         Parallel_Text_Length : Natural;

         procedure Compare is
         begin
            Assert_Same (Oracle, Parallel, Oracle_Error, Parallel_Error);
         end Compare;
      begin
         Initialize (Oracle, Policy);
         Event_Readers.Initialize (Parallel, Policy, Parallel_Error);
         Compare;

         Begin_Sequence (Oracle, Oracle_Length, Oracle_Error);
         Event_Readers.Begin_Sequence
           (Parallel, Parallel_Length, Parallel_Error);
         pragma Assert (Oracle_Length = Parallel_Length);
         Compare;

         Next_Element (Oracle, Oracle_Available, Oracle_Error);
         Event_Readers.Next_Element
           (Parallel, Parallel_Available, Parallel_Error);
         pragma Assert (Oracle_Available = Parallel_Available);
         Compare;
         Read_Null (Oracle, Oracle_Error);
         Event_Readers.Read_Null (Parallel, Parallel_Error);
         Compare;

         Next_Element (Oracle, Oracle_Available, Oracle_Error);
         Event_Readers.Next_Element
           (Parallel, Parallel_Available, Parallel_Error);
         pragma Assert (Oracle_Available = Parallel_Available);
         Compare;
         Read_Boolean (Oracle, Oracle_Boolean, Oracle_Error);
         Event_Readers.Read_Boolean
           (Parallel, Parallel_Boolean, Parallel_Error);
         pragma Assert (Oracle_Boolean = Parallel_Boolean);
         Compare;

         Next_Element (Oracle, Oracle_Available, Oracle_Error);
         Event_Readers.Next_Element
           (Parallel, Parallel_Available, Parallel_Error);
         pragma Assert (Oracle_Available = Parallel_Available);
         Compare;
         Begin_Sequence (Oracle, Oracle_Length, Oracle_Error);
         Event_Readers.Begin_Sequence
           (Parallel, Parallel_Length, Parallel_Error);
         pragma Assert (Oracle_Length = Parallel_Length);
         Compare;

         Next_Element (Oracle, Oracle_Available, Oracle_Error);
         Event_Readers.Next_Element
           (Parallel, Parallel_Available, Parallel_Error);
         pragma Assert (Oracle_Available = Parallel_Available);
         Compare;
         Read_Signed (Oracle, Oracle_Signed, Oracle_Error);
         Event_Readers.Read_Signed (Parallel, Parallel_Signed, Parallel_Error);
         pragma Assert (Oracle_Signed = Parallel_Signed);
         Compare;

         Next_Element (Oracle, Oracle_Available, Oracle_Error);
         Event_Readers.Next_Element
           (Parallel, Parallel_Available, Parallel_Error);
         pragma Assert (Oracle_Available = Parallel_Available);
         Compare;
         Read_Text (Oracle, Oracle_Text, Oracle_Text_Length, Oracle_Error);
         Event_Readers.Read_Text
           (Parallel, Parallel_Text, Parallel_Text_Length, Parallel_Error);
         pragma
           Assert
             (Oracle_Text_Length = Parallel_Text_Length
                and then Oracle_Text = Parallel_Text);
         Compare;

         Next_Element (Oracle, Oracle_Available, Oracle_Error);
         Event_Readers.Next_Element
           (Parallel, Parallel_Available, Parallel_Error);
         pragma Assert (Oracle_Available = Parallel_Available);
         Compare;
         End_Sequence (Oracle, Oracle_Error);
         Event_Readers.End_Sequence (Parallel, Parallel_Error);
         Compare;

         Next_Element (Oracle, Oracle_Available, Oracle_Error);
         Event_Readers.Next_Element
           (Parallel, Parallel_Available, Parallel_Error);
         pragma Assert (Oracle_Available = Parallel_Available);
         Compare;
         End_Sequence (Oracle, Oracle_Error);
         Event_Readers.End_Sequence (Parallel, Parallel_Error);
         Compare;

         Finish_Document (Oracle, Oracle_Error);
         Event_Readers.Finish_Document (Parallel, Parallel_Error);
         Compare;
      end Check_Sequence_Parity;

      procedure Check_Sequence_Denial_Parity
        (Source            : String;
         Expected_Offset   : Natural;
         Expected_Consumed : Natural)
      is
         Input              : aliased constant String := Source;
         Oracle             : Reader (Input'Access);
         Parallel           : Event_Readers.Reader (Input'Access);
         Oracle_Error       : Errors.Error_Info;
         Parallel_Error     : Errors.Error_Info;
         Oracle_Length      : Data_Model.Length_Information;
         Parallel_Length    : Data_Model.Length_Information;
         Oracle_Available   : Boolean;
         Parallel_Available : Boolean;
      begin
         Initialize (Oracle, Policy);
         Event_Readers.Initialize (Parallel, Policy, Parallel_Error);
         Assert_Same (Oracle, Parallel, Oracle_Error, Parallel_Error);

         Begin_Sequence (Oracle, Oracle_Length, Oracle_Error);
         Event_Readers.Begin_Sequence
           (Parallel, Parallel_Length, Parallel_Error);
         pragma Assert (Oracle_Length = Parallel_Length);
         Assert_Same (Oracle, Parallel, Oracle_Error, Parallel_Error);

         Next_Element (Oracle, Oracle_Available, Oracle_Error);
         Event_Readers.Next_Element
           (Parallel, Parallel_Available, Parallel_Error);
         pragma Assert (Oracle_Available = Parallel_Available);
         Assert_Same (Oracle, Parallel, Oracle_Error, Parallel_Error);

         Read_Null (Oracle, Oracle_Error);
         Event_Readers.Read_Null (Parallel, Parallel_Error);
         Assert_Same (Oracle, Parallel, Oracle_Error, Parallel_Error);

         Oracle_Available := True;
         Parallel_Available := True;
         Next_Element (Oracle, Oracle_Available, Oracle_Error);
         Event_Readers.Next_Element
           (Parallel, Parallel_Available, Parallel_Error);
         pragma
           Assert
             (not Oracle_Available
                and then not Parallel_Available
                and then Parallel_Error.Code = Errors.Syntax_Error
                and then Parallel_Error.Input_Offset = Expected_Offset
                and then Event_Readers.Input_Consumed (Parallel)
                         = Expected_Consumed);
         Assert_Same (Oracle, Parallel, Oracle_Error, Parallel_Error);
      end Check_Sequence_Denial_Parity;

      procedure Check_Sequence_Limit_Parity
        (Source            : String;
         Maximum_Input     : Natural;
         Maximum_Values    : Natural;
         Expected_Offset   : Natural;
         Expected_Consumed : Natural)
      is
         Input              : aliased constant String := Source;
         Oracle             : Reader (Input'Access);
         Parallel           : Event_Readers.Reader (Input'Access);
         Oracle_Error       : Errors.Error_Info;
         Parallel_Error     : Errors.Error_Info;
         Oracle_Length      : Data_Model.Length_Information;
         Parallel_Length    : Data_Model.Length_Information;
         Oracle_Available   : Boolean;
         Parallel_Available : Boolean;
         Oracle_Boolean     : Boolean;
         Parallel_Boolean   : Boolean;
         Local_Policy       : Policies.Decode_Policy := Policy;

         procedure Compare is
         begin
            Assert_Same (Oracle, Parallel, Oracle_Error, Parallel_Error);
         end Compare;
      begin
         Local_Policy.Limits.Maximum_Input_Units := Maximum_Input;
         Local_Policy.Limits.Maximum_Logical_Values := Maximum_Values;
         Initialize (Oracle, Local_Policy);
         Event_Readers.Initialize (Parallel, Local_Policy, Parallel_Error);
         Compare;

         Begin_Sequence (Oracle, Oracle_Length, Oracle_Error);
         Event_Readers.Begin_Sequence
           (Parallel, Parallel_Length, Parallel_Error);
         pragma Assert (Oracle_Length = Parallel_Length);
         Compare;

         if Oracle_Error.Code = Errors.No_Error then
            Next_Element (Oracle, Oracle_Available, Oracle_Error);
            Event_Readers.Next_Element
              (Parallel, Parallel_Available, Parallel_Error);
            pragma Assert (Oracle_Available = Parallel_Available);
            Compare;
         end if;

         if Oracle_Error.Code = Errors.No_Error and then Oracle_Available then
            Read_Null (Oracle, Oracle_Error);
            Event_Readers.Read_Null (Parallel, Parallel_Error);
            Compare;
         end if;

         if Oracle_Error.Code = Errors.No_Error then
            Next_Element (Oracle, Oracle_Available, Oracle_Error);
            Event_Readers.Next_Element
              (Parallel, Parallel_Available, Parallel_Error);
            pragma Assert (Oracle_Available = Parallel_Available);
            Compare;
         end if;

         if Oracle_Error.Code = Errors.No_Error and then Oracle_Available then
            Read_Boolean (Oracle, Oracle_Boolean, Oracle_Error);
            Event_Readers.Read_Boolean
              (Parallel, Parallel_Boolean, Parallel_Error);
            pragma Assert (Oracle_Boolean = Parallel_Boolean);
            Compare;
         end if;

         pragma
           Assert
             (Parallel_Error.Code = Errors.Capacity_Exceeded
                and then Parallel_Error.Input_Offset = Expected_Offset
                and then Event_Readers.Input_Consumed (Parallel)
                         = Expected_Consumed,
              Source
                & Parallel_Error.Code'Image
                & Parallel_Error.Input_Offset'Image
                & Event_Readers.Input_Consumed (Parallel)'Image);
      end Check_Sequence_Limit_Parity;

      package U64_Root is new
        Flyology_Serde.Deserialization_Adapters
          (Builder_Type       => U64_Builder,
           Policy             => Policy,
           Begin_Candidate    => Begin_U64,
           Deserialize_Value  => Read_U64,
           Commit_Candidate   => Commit_U64,
           Rollback_Candidate => Rollback_U64);
   begin
      Test_Hooks.Disarm;

      declare
         Input : aliased constant String := "null";
         Item  : Event_Readers.Reader (Input'Access);
         Error : Errors.Error_Info;
      begin
         Event_Readers.Initialize (Item, Policy, Error);
         Event_Readers.Read_Null (Item, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Event_Readers.Input_Offset (Item) = Input'Length
                and then Event_Readers.Input_Consumed (Item) = Input'Length
                and then Event_Readers.Values_Consumed (Item) = 1,
              Error.Code'Image
                & Error.Input_Offset'Image
                & Event_Readers.Input_Offset (Item)'Image
                & Event_Readers.Input_Consumed (Item)'Image
                & Event_Readers.Values_Consumed (Item)'Image);
         Event_Readers.Finish_Document (Item, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Event_Readers.Is_Complete (Item));
      end;

      declare
         Input : aliased constant String := "true";
         Item  : Event_Readers.Reader (Input'Access);
         Error : Errors.Error_Info;
         Value : Boolean;
      begin
         Event_Readers.Initialize (Item, Policy, Error);
         Event_Readers.Read_Boolean (Item, Value, Error);
         pragma Assert (Error.Code = Errors.No_Error and then Value);
         Event_Readers.Finish_Document (Item, Error);
         pragma Assert (Event_Readers.Is_Complete (Item));
      end;

      declare
         Input : aliased constant String := "-9223372036854775808";
         Item  : Event_Readers.Reader (Input'Access);
         Error : Errors.Error_Info;
         Value : Interfaces.Integer_64;
      begin
         Event_Readers.Initialize (Item, Policy, Error);
         Event_Readers.Read_Signed (Item, Value, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Value = Interfaces.Integer_64'First);
         Event_Readers.Finish_Document (Item, Error);
         pragma Assert (Event_Readers.Is_Complete (Item));
      end;

      declare
         Input : aliased constant String := "18446744073709551615";
         Item  : Event_Readers.Reader (Input'Access);
         Error : Errors.Error_Info;
         Value : Interfaces.Unsigned_64;
      begin
         Event_Readers.Initialize (Item, Policy, Error);
         Event_Readers.Read_Unsigned (Item, Value, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Value = Interfaces.Unsigned_64'Last);
         Event_Readers.Finish_Document (Item, Error);
         pragma Assert (Event_Readers.Is_Complete (Item));
      end;

      declare
         Input  : aliased constant String := """line\n\uD83D\uDE00""";
         Item   : Event_Readers.Reader (Input'Access);
         Error  : Errors.Error_Info;
         Value  : String (1 .. 16);
         Length : Natural;
      begin
         Event_Readers.Initialize (Item, Policy, Error);
         Event_Readers.Read_Text (Item, Value, Length, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Length = 9
                and then Value (1 .. 5) = "line" & ASCII.LF,
              Error.Code'Image
                & Length'Image
                & Event_Readers.Input_Offset (Item)'Image
                & Event_Readers.Input_Consumed (Item)'Image);
         Event_Readers.Finish_Document (Item, Error);
         pragma Assert (Event_Readers.Is_Complete (Item));
      end;

      declare
         Input : aliased constant String := "1x";
         Item  : Event_Readers.Reader (Input'Access);
         Error : Errors.Error_Info;
         Value : Interfaces.Unsigned_64;
      begin
         Event_Readers.Initialize (Item, Policy, Error);
         Event_Readers.Read_Unsigned (Item, Value, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Value = 1
                and then Event_Readers.Input_Offset (Item) = 1
                and then Event_Readers.Input_Consumed (Item) = 1);
         Event_Readers.Finish_Document (Item, Error);
         pragma
           Assert
             (Error.Code = Errors.Syntax_Error
                and then Error.Input_Offset = 1
                and then Event_Readers.Input_Offset (Item) = 1
                and then Event_Readers.Input_Consumed (Item) = 1);
      end;

      --  A real root adapter cannot publish a provisional scalar when
      --  Finish_Document later rejects its deferred follower.
      declare
         Input  : aliased constant String := "1x";
         Item   : Event_Readers.Reader (Input'Access);
         Target : U64_Builder;
         Error  : Errors.Error_Info;
      begin
         Event_Readers.Initialize (Item, Policy, Error);
         U64_Root.Deserialize (Item, Target, Error);
         pragma
           Assert
             (Error.Code = Errors.Syntax_Error
                and then Target.Published = 41
                and then Target.Commits = 0
                and then Target.Rollbacks = 1);
      end;

      declare
         Input  : aliased constant String := "42";
         Item   : Event_Readers.Reader (Input'Access);
         Target : U64_Builder;
         Error  : Errors.Error_Info;
      begin
         Event_Readers.Initialize (Item, Policy, Error);
         U64_Root.Deserialize (Item, Target, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Target.Published = 42
                and then Target.Commits = 1
                and then Target.Rollbacks = 0);
      end;

      Check_Null ("null");
      Check_Null ("null ");
      Check_Null ("null" & ASCII.HT);
      Check_Null ("null" & ASCII.CR);
      Check_Null ("null" & ASCII.LF);
      Check_Null ("null,");
      Check_Null ("null]");
      Check_Null ("null}");
      Check_Null ("nullx");
      Check_Null ("null!");
      Check_Null ("null ", 4);
      Check_Null ("nullx", 4);
      for Limit in Natural range 0 .. 3 loop
         Check_Null ("null", Limit);
      end loop;
      Check_Null (" null", 4);
      Check_Null ("null  ", 5);
      Check_Null ("null", Maximum_Values => 0);

      Check_Boolean ("true");
      Check_Boolean ("false");
      Check_Boolean ("true ");
      Check_Boolean ("false ");
      Check_Boolean ("true,");
      Check_Boolean ("false]");
      Check_Boolean ("truex");
      Check_Boolean ("false!");
      Check_Boolean ("true ", 4);
      Check_Boolean ("false ", 5);
      Check_Boolean ("truex", 4);
      Check_Boolean ("falsex", 5);
      Check_Boolean ("true", 3);
      Check_Boolean ("false", 4);

      declare
         Delimiters : constant String :=
           [' ', ASCII.HT, ASCII.CR, ASCII.LF, ',', ']', '}'];
      begin
         for Delimiter of Delimiters loop
            Check_Boolean ("true" & Delimiter);
            Check_Boolean ("false" & Delimiter);
            Check_Text ("""x""" & Delimiter);
            Check_Signed ("-1" & Delimiter);
            Check_Unsigned ("1" & Delimiter);
            Check_Float ("1.5" & Delimiter);
         end loop;
      end;

      --  The reader validates the parser's Boolean payload rather than
      --  trusting only the event kind, at EOF and at a retained delimiter.
      declare
         Input : aliased constant String := "true";
         Item  : Event_Readers.Reader (Input'Access);
         Error : Errors.Error_Info;
         Value : Boolean := True;
      begin
         Event_Readers.Initialize (Item, Policy, Error);
         Test_Hooks.Arm_Boolean_Override (False);
         Event_Readers.Read_Boolean (Item, Value, Error);
         pragma
           Assert
             (Error.Code = Errors.Invalid_State
                and then not Value
                and then not Event_Readers.Is_Complete (Item));
         Errors.Reset (Error);
         Event_Readers.Reset (Item, Policy, Error);
         Event_Readers.Read_Boolean (Item, Value, Error);
         Event_Readers.Finish_Document (Item, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Value
                and then Event_Readers.Is_Complete (Item));
      end;

      declare
         Input : aliased constant String := "false ";
         Item  : Event_Readers.Reader (Input'Access);
         Error : Errors.Error_Info;
         Value : Boolean := True;
      begin
         Event_Readers.Initialize (Item, Policy, Error);
         Test_Hooks.Arm_Boolean_Override (True);
         Event_Readers.Read_Boolean (Item, Value, Error);
         pragma
           Assert
             (Error.Code = Errors.Invalid_State
                and then not Value
                and then Event_Readers.Input_Consumed (Item) = 5);
      end;

      --  Numeric conversion cannot bypass a missing/reordered event fragment.
      declare
         Input : aliased constant String := "12";
         Item  : Event_Readers.Reader (Input'Access);
         Error : Errors.Error_Info;
         Value : Interfaces.Unsigned_64 := 99;
      begin
         Event_Readers.Initialize (Item, Policy, Error);
         Test_Hooks.Arm_Source_Offset_Override
           (Summaries_To_Skip => 1, Value => 1);
         Event_Readers.Read_Unsigned (Item, Value, Error);
         pragma
           Assert
             (Error.Code = Errors.Invalid_State
                and then Value = 0
                and then not Event_Readers.Is_Complete (Item));
      end;

      --  String fragment source ranges must cover the raw token in order,
      --  without a gap or overlap, independently of decoded-length parity.
      declare
         procedure Check_Fragment_Offset_Mismatch
           (Summaries_To_Skip : Natural; Source_Offset : Natural)
         is
            Input  : aliased constant String := """ab""";
            Item   : Event_Readers.Reader (Input'Access);
            Error  : Errors.Error_Info;
            Value  : String (4 .. 7) := [others => 'x'];
            Length : Natural := 99;
         begin
            Event_Readers.Initialize (Item, Policy, Error);
            Test_Hooks.Arm_Source_Offset_Override
              (Summaries_To_Skip, Source_Offset);
            Event_Readers.Read_Text (Item, Value, Length, Error);
            pragma
              Assert
                (Error.Code = Errors.Invalid_State
                   and then Length = 0
                   and then (for all Item of Value => Item = ' '));
         end Check_Fragment_Offset_Mismatch;
      begin
         Check_Fragment_Offset_Mismatch
           (Summaries_To_Skip => 1, Source_Offset => 2);
         Check_Fragment_Offset_Mismatch
           (Summaries_To_Skip => 2, Source_Offset => 1);
      end;

      --  A mismatch after decoded text was copied clears the complete
      --  arbitrary-bound destination and publishes length zero.
      declare
         Input  : aliased constant String := """x""";
         Item   : Event_Readers.Reader (Input'Access);
         Error  : Errors.Error_Info;
         Value  : String (9 .. 12) := [others => 'x'];
         Length : Natural := 99;
      begin
         Event_Readers.Initialize (Item, Policy, Error);
         Test_Hooks.Arm_Source_Offset_Override
           (Summaries_To_Skip => 2, Value => 0);
         Event_Readers.Read_Text (Item, Value, Length, Error);
         pragma
           Assert
             (Error.Code = Errors.Invalid_State
                and then Length = 0
                and then (for all Item of Value => Item = ' '));
      end;

      Check_Text ("""""");
      Check_Text ("""x""");
      Check_Text ("""x"" ");
      Check_Text ("""x"",");
      Check_Text ("""x""x");
      Check_Text ("""x"" ", 3);
      Check_Text ("""x""x", 3);
      Check_Text ("""x""", 2);
      Check_Text ("""line\n\uD83D\uDE00""");
      Check_Text ("""\""""");
      Check_Text ("""\\""");
      Check_Text ("""\/""");
      Check_Text ("""\b""");
      Check_Text ("""\f""");
      Check_Text ("""\n""");
      Check_Text ("""\r""");
      Check_Text ("""\t""");
      Check_Text ("""\u0000""");
      Check_Text ("""\u20AC""");
      Check_Text ("""\uD800""");
      Check_Text ("""\u12""");
      Check_Text ('"' & Character'Val (16#C2#) & '"');
      Check_Text_Capacity ("""x""", 0);
      Check_Text_Capacity ("""x""", 1, Maximum_Text => 0);

      Check_Signed ("-9223372036854775808");
      Check_Signed ("9223372036854775807");
      Check_Signed ("-9223372036854775809");
      Check_Signed ("9223372036854775808");
      Check_Signed ("-0");
      Check_Signed ("1.0");

      Check_Unsigned ("0");
      Check_Unsigned ("18446744073709551615");
      Check_Unsigned ("18446744073709551616");
      Check_Unsigned ("-0");
      Check_Unsigned ("1 ");
      Check_Unsigned ("1" & ASCII.HT);
      Check_Unsigned ("1" & ASCII.CR);
      Check_Unsigned ("1" & ASCII.LF);
      Check_Unsigned ("1,");
      Check_Unsigned ("1]");
      Check_Unsigned ("1}");
      Check_Unsigned ("1x");
      Check_Unsigned ("1 ", 1);

      Check_Float ("0.0");
      Check_Float ("-0.0");
      Check_Float ("1.5");
      Check_Float ("2.2250738585072014e-308");
      Check_Float ("4.9406564584124654e-324");
      Check_Float ("1e309");
      Check_Float ("1.0x");

      Check_Null ("null" & Character'Val (16#C2#));
      Check_Boolean ("true" & Character'Val (16#C2#));
      Check_Text ("""x""" & Character'Val (16#C2#));
      Check_Signed ("-1" & Character'Val (16#C2#));
      Check_Float ("1.5" & Character'Val (16#C2#));

      Check_Peek ("null");
      Check_Peek ("truX");
      Check_Peek ("false");
      Check_Peek ("-1");
      Check_Peek ("1");
      Check_Peek ("1.0");
      Check_Peek ("""unterminated");
      Check_Peek ("[");
      Check_Peek ("{");
      Check_Peek (" ");
      Check_Peek ("-");
      Check_Peek ("x");
      Check_Sequence_Parity;
      Check_Sequence_Denial_Parity ("[nullx]", 5, 5);
      Check_Sequence_Denial_Parity ("[null,,true]", 6, 6);
      Check_Sequence_Limit_Parity ("[null,true]", 0, Natural'Last, 0, 0);
      Check_Sequence_Limit_Parity ("[null,true]", Natural'Last, 0, 0, 0);
      Check_Sequence_Limit_Parity ("[null ,true]", 5, Natural'Last, 5, 5);
      Check_Sequence_Limit_Parity ("[null ,true]", 6, Natural'Last, 6, 6);
      Check_Sequence_Limit_Parity ("[null, true]", 6, Natural'Last, 6, 6);
      Check_Sequence_Limit_Parity ("[null,true]", Natural'Last, 2, 6, 6);

      --  Public map and record whitespace denial must stop before consulting
      --  the frame that common failure cleanup has just unpublished.
      declare
         Input          : aliased constant String := "[ ]";
         Item           : Reader (Input'Access);
         Error          : Errors.Error_Info;
         Bounded_Policy : Policies.Decode_Policy := Policy;
         Length         : Data_Model.Length_Information;
         Available      : Boolean := True;
      begin
         Bounded_Policy.Limits.Maximum_Input_Units := 1;
         Initialize (Item, Bounded_Policy);
         Begin_Map (Item, Length, Error);
         Next_Map_Entry (Item, Available, Error);
         pragma
           Assert
             (Error.Code = Errors.Capacity_Exceeded
                and then Error.Input_Offset = 1
                and then not Available
                and then Item.Depth = 0
                and then Budgets.Depth (Item.Budget) = 0);
      end;

      declare
         Input          : aliased constant String := "{ }";
         Item           : Reader (Input'Access);
         Error          : Errors.Error_Info;
         Bounded_Policy : Policies.Decode_Policy := Policy;
         Info           : Data_Model.Length_Information;
         Name           : String (5 .. 8) := [others => 'x'];
         Length         : Natural := 99;
         Available      : Boolean := True;
      begin
         Bounded_Policy.Limits.Maximum_Input_Units := 1;
         Initialize (Item, Bounded_Policy);
         Begin_Record (Item, "T", Info, Error);
         Next_Field (Item, Name, Length, Available, Error);
         pragma
           Assert
             (Error.Code = Errors.Capacity_Exceeded
                and then Error.Input_Offset = 1
                and then not Available
                and then Length = 0
                and then (for all Value of Name => Value = ' ')
                and then Item.Depth = 0
                and then Budgets.Depth (Item.Budget) = 0);
      end;

      --  The first structural slice covers empty, mixed, and nested
      --  sequences while preserving the existing logical traversal.
      declare
         Input         : aliased constant String :=
           "[null, true, [-1, ""x""]]";
         Item          : Event_Readers.Reader (Input'Access);
         Error         : Errors.Error_Info;
         Length        : Data_Model.Length_Information;
         Available     : Boolean;
         Boolean_Value : Boolean;
         Signed_Value  : Interfaces.Integer_64;
         Text          : String (5 .. 5);
         Text_Length   : Natural;
      begin
         Event_Readers.Initialize (Item, Policy, Error);
         Event_Readers.Begin_Sequence (Item, Length, Error);
         pragma Assert (not Length.Known);
         Event_Readers.Next_Element (Item, Available, Error);
         pragma Assert (Available);
         Event_Readers.Read_Null (Item, Error);
         Event_Readers.Next_Element (Item, Available, Error);
         pragma Assert (Available);
         Event_Readers.Read_Boolean (Item, Boolean_Value, Error);
         pragma Assert (Boolean_Value);
         Event_Readers.Next_Element (Item, Available, Error);
         pragma Assert (Available);
         Event_Readers.Begin_Sequence (Item, Length, Error);
         Event_Readers.Next_Element (Item, Available, Error);
         pragma Assert (Available);
         Event_Readers.Read_Signed (Item, Signed_Value, Error);
         pragma Assert (Signed_Value = -1);
         Event_Readers.Next_Element (Item, Available, Error);
         pragma Assert (Available);
         Event_Readers.Read_Text (Item, Text, Text_Length, Error);
         pragma Assert (Text_Length = 1 and then Text (Text'First) = 'x');
         Event_Readers.Next_Element (Item, Available, Error);
         pragma Assert (not Available);
         Event_Readers.End_Sequence (Item, Error);
         Event_Readers.Next_Element (Item, Available, Error);
         pragma Assert (not Available);
         Event_Readers.End_Sequence (Item, Error);
         Event_Readers.Finish_Document (Item, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Event_Readers.Is_Complete (Item)
                and then Event_Readers.Input_Offset (Item) = Input'Length
                and then Event_Readers.Input_Consumed (Item) = Input'Length
                and then Event_Readers.Values_Consumed (Item) = 6);
      end;

      declare
         Input     : aliased constant String := "[]";
         Item      : Event_Readers.Reader (Input'Access);
         Error     : Errors.Error_Info;
         Length    : Data_Model.Length_Information;
         Available : Boolean := True;
      begin
         Event_Readers.Initialize (Item, Policy, Error);
         Event_Readers.Begin_Sequence (Item, Length, Error);
         Event_Readers.Next_Element (Item, Available, Error);
         pragma Assert (not Available);
         Event_Readers.End_Sequence (Item, Error);
         Event_Readers.Finish_Document (Item, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Event_Readers.Is_Complete (Item)
                and then Event_Readers.Values_Consumed (Item) = 1);
      end;

      declare
         Input     : aliased constant String :=
           "[null " & ASCII.LF & ", true " & ASCII.HT & "]";
         Item      : Event_Readers.Reader (Input'Access);
         Error     : Errors.Error_Info;
         Length    : Data_Model.Length_Information;
         Available : Boolean;
         Value     : Boolean;
      begin
         Event_Readers.Initialize (Item, Policy, Error);
         Event_Readers.Begin_Sequence (Item, Length, Error);
         Event_Readers.Next_Element (Item, Available, Error);
         Event_Readers.Read_Null (Item, Error);
         Event_Readers.Next_Element (Item, Available, Error);
         pragma Assert (Available);
         Event_Readers.Read_Boolean (Item, Value, Error);
         Event_Readers.Next_Element (Item, Available, Error);
         pragma Assert (not Available);
         Event_Readers.End_Sequence (Item, Error);
         Event_Readers.Finish_Document (Item, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Value
                and then Event_Readers.Is_Complete (Item));
      end;

      --  A denied subsequent item is never published and normal poison
      --  unwinds both the logical frame and the shared budget scope.
      declare
         Input          : aliased constant String := "[null,true]";
         Item           : Event_Readers.Reader (Input'Access);
         Error          : Errors.Error_Info;
         Bounded_Policy : Policies.Decode_Policy := Policy;
         Length         : Data_Model.Length_Information;
         Available      : Boolean;
      begin
         Bounded_Policy.Limits.Maximum_Container_Items := 1;
         Event_Readers.Initialize (Item, Bounded_Policy, Error);
         Event_Readers.Begin_Sequence (Item, Length, Error);
         Event_Readers.Next_Element (Item, Available, Error);
         Event_Readers.Read_Null (Item, Error);
         Event_Readers.Next_Element (Item, Available, Error);
         pragma
           Assert
             (Error.Code = Errors.Capacity_Exceeded
                and then Error.Input_Offset = 6
                and then Error.Offset_Unit = Errors.Byte_Offset
                and then not Available
                and then Event_Readers.Input_Offset (Item) = 6
                and then Event_Readers.Input_Consumed (Item) = 6
                and then Event_Readers.Values_Consumed (Item) = 2
                and then Event_Readers.Container_Depth (Item) = 0
                and then Event_Readers.Budget_Depth (Item) = 0);
         Errors.Reset (Error);
         Event_Readers.Reset (Item, Bounded_Policy, Error);
         Event_Readers.Begin_Sequence (Item, Length, Error);
         pragma Assert (Error.Code = Errors.No_Error);
         Event_Readers.Abort_Document (Item, Error);
      end;

      --  Invalid source after an observed scalar terminal remains uncharged.
      declare
         Input     : aliased constant String := "[null x]";
         Item      : Event_Readers.Reader (Input'Access);
         Error     : Errors.Error_Info;
         Length    : Data_Model.Length_Information;
         Available : Boolean;
      begin
         Event_Readers.Initialize (Item, Policy, Error);
         Event_Readers.Begin_Sequence (Item, Length, Error);
         Event_Readers.Next_Element (Item, Available, Error);
         Event_Readers.Read_Null (Item, Error);
         Event_Readers.Next_Element (Item, Available, Error);
         pragma
           Assert
             (Error.Code = Errors.Syntax_Error
                and then Error.Input_Offset = 6
                and then Event_Readers.Input_Offset (Item) = 6
                and then Event_Readers.Input_Consumed (Item) = 6
                and then Event_Readers.Container_Depth (Item) = 0
                and then Event_Readers.Budget_Depth (Item) = 0);
      end;

      declare
         Input          : aliased constant String := "[null]";
         Item           : Event_Readers.Reader (Input'Access);
         Error          : Errors.Error_Info;
         Bounded_Policy : Policies.Decode_Policy := Policy;
         Length         : Data_Model.Length_Information;
         Available      : Boolean := True;
      begin
         Bounded_Policy.Limits.Maximum_Container_Items := 0;
         Event_Readers.Initialize (Item, Bounded_Policy, Error);
         Event_Readers.Begin_Sequence (Item, Length, Error);
         Event_Readers.Next_Element (Item, Available, Error);
         pragma
           Assert
             (Error.Code = Errors.Capacity_Exceeded
                and then Error.Input_Offset = 1
                and then not Available
                and then Event_Readers.Input_Consumed (Item) = 1
                and then Event_Readers.Values_Consumed (Item) = 1
                and then Event_Readers.Container_Depth (Item) = 0
                and then Event_Readers.Budget_Depth (Item) = 0);
      end;

      declare
         Input          : aliased constant String := "[[]]";
         Item           : Event_Readers.Reader (Input'Access);
         Error          : Errors.Error_Info;
         Bounded_Policy : Policies.Decode_Policy := Policy;
         Length         : Data_Model.Length_Information;
         Available      : Boolean;
      begin
         Bounded_Policy.Limits.Maximum_Nesting_Depth := 1;
         Event_Readers.Initialize (Item, Bounded_Policy, Error);
         Event_Readers.Begin_Sequence (Item, Length, Error);
         Event_Readers.Next_Element (Item, Available, Error);
         Event_Readers.Begin_Sequence (Item, Length, Error);
         pragma
           Assert
             (Error.Code = Errors.Depth_Exceeded
                and then Error.Input_Offset = 2
                and then Event_Readers.Input_Consumed (Item) = 2
                and then Event_Readers.Values_Consumed (Item) = 2
                and then Event_Readers.Container_Depth (Item) = 0
                and then Event_Readers.Budget_Depth (Item) = 0);
      end;

      --  A retained closer belongs to Next first and End second; Next does
      --  not admit or replay it.
      declare
         Input     : aliased constant String := "[null]";
         Item      : Event_Readers.Reader (Input'Access);
         Error     : Errors.Error_Info;
         Length    : Data_Model.Length_Information;
         Available : Boolean;
      begin
         Event_Readers.Initialize (Item, Policy, Error);
         Event_Readers.Begin_Sequence (Item, Length, Error);
         Event_Readers.Next_Element (Item, Available, Error);
         Event_Readers.Read_Null (Item, Error);
         pragma Assert (Event_Readers.Input_Consumed (Item) = 5);
         Event_Readers.Next_Element (Item, Available, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then not Available
                and then Event_Readers.Input_Offset (Item) = 5
                and then Event_Readers.Input_Consumed (Item) = 5);
         Event_Readers.End_Sequence (Item, Error);
         Event_Readers.Finish_Document (Item, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Event_Readers.Is_Complete (Item)
                and then Event_Readers.Input_Consumed (Item) = 6);
      end;

      --  At exact input exhaustion, the closer can be classified and rebound
      --  by Next but End owns the denied replay.
      declare
         Input          : aliased constant String := "[null]";
         Item           : Event_Readers.Reader (Input'Access);
         Error          : Errors.Error_Info;
         Bounded_Policy : Policies.Decode_Policy := Policy;
         Length         : Data_Model.Length_Information;
         Available      : Boolean := True;
      begin
         Bounded_Policy.Limits.Maximum_Input_Units := 5;
         Event_Readers.Initialize (Item, Bounded_Policy, Error);
         Event_Readers.Begin_Sequence (Item, Length, Error);
         Event_Readers.Next_Element (Item, Available, Error);
         Event_Readers.Read_Null (Item, Error);
         Event_Readers.Next_Element (Item, Available, Error);
         pragma Assert (Error.Code = Errors.No_Error and then not Available);
         Event_Readers.End_Sequence (Item, Error);
         pragma
           Assert
             (Error.Code = Errors.Capacity_Exceeded
                and then Error.Input_Offset = 5
                and then Event_Readers.Input_Consumed (Item) = 5
                and then Event_Readers.Container_Depth (Item) = 0
                and then Event_Readers.Budget_Depth (Item) = 0);
      end;

      declare
         Input     : aliased constant String := "[null}";
         Item      : Event_Readers.Reader (Input'Access);
         Error     : Errors.Error_Info;
         Length    : Data_Model.Length_Information;
         Available : Boolean;
      begin
         Event_Readers.Initialize (Item, Policy, Error);
         Event_Readers.Begin_Sequence (Item, Length, Error);
         Event_Readers.Next_Element (Item, Available, Error);
         Event_Readers.Read_Null (Item, Error);
         Event_Readers.Next_Element (Item, Available, Error);
         pragma
           Assert
             (Error.Code = Errors.Syntax_Error
                and then Error.Input_Offset = 5
                and then Event_Readers.Input_Consumed (Item) = 5
                and then Event_Readers.Container_Depth (Item) = 0);
      end;

      declare
         Input  : aliased constant String := "[]";
         Item   : Event_Readers.Reader (Input'Access);
         Error  : Errors.Error_Info;
         Length : Data_Model.Length_Information;
      begin
         Event_Readers.Initialize (Item, Policy, Error);
         Event_Readers.Begin_Sequence (Item, Length, Error);
         Event_Readers.End_Sequence (Item, Error);
         pragma
           Assert
             (Error.Code = Errors.Invalid_State
                and then Error.Input_Offset = 1
                and then Event_Readers.Input_Consumed (Item) = 1
                and then Event_Readers.Container_Depth (Item) = 0);
      end;

      declare
         Input     : aliased constant String :=
           [17 => '[', 18 => 'n', 19 => 'u', 20 => 'l', 21 => 'l', 22 => ']'];
         Item      : Event_Readers.Reader (Input'Access);
         Error     : Errors.Error_Info;
         Length    : Data_Model.Length_Information;
         Available : Boolean;
      begin
         Event_Readers.Initialize (Item, Policy, Error);
         Event_Readers.Begin_Sequence (Item, Length, Error);
         Event_Readers.Next_Element (Item, Available, Error);
         Event_Readers.Read_Null (Item, Error);
         Event_Readers.Next_Element (Item, Available, Error);
         Event_Readers.End_Sequence (Item, Error);
         Event_Readers.Finish_Document (Item, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Event_Readers.Is_Complete (Item)
                and then Event_Readers.Input_Consumed (Item) = 6);
      end;

      --  Closing a root sequence publishes the root value, but trailing JSON
      --  whitespace remains syntax work owned by Finish_Document.
      declare
         Input     : aliased constant String := "[] ";
         Item      : Event_Readers.Reader (Input'Access);
         Error     : Errors.Error_Info;
         Length    : Data_Model.Length_Information;
         Available : Boolean;
      begin
         Event_Readers.Initialize (Item, Policy, Error);
         Event_Readers.Begin_Sequence (Item, Length, Error);
         Event_Readers.Next_Element (Item, Available, Error);
         pragma Assert (not Available);
         Event_Readers.End_Sequence (Item, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Event_Readers.Input_Offset (Item) = 2
                and then not Event_Readers.Is_Complete (Item));
         Event_Readers.Finish_Document (Item, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Event_Readers.Input_Offset (Item) = 3
                and then Event_Readers.Is_Complete (Item));
      end;

      --  Every catchable driver exception poisons the parser and traversal
      --  before propagating, then Reset is the sole recovery path.
      declare
         Input  : aliased constant String := "[null]";
         Item   : Event_Readers.Reader (Input'Access);
         Error  : Errors.Error_Info;
         Length : Data_Model.Length_Information;
      begin
         Event_Readers.Initialize (Item, Policy, Error);
         Test_Hooks.Arm (Test_Hooks.Before_Source_Copy);
         begin
            Event_Readers.Begin_Sequence (Item, Length, Error);
            pragma Assert (False);
         exception
            when Constraint_Error =>
               null;
         end;
         pragma
           Assert
             (Event_Readers.Container_Depth (Item) = 0
                and then Event_Readers.Budget_Depth (Item) = 0);
         Event_Readers.Read_Null (Item, Error);
         pragma Assert (Error.Code = Errors.Invalid_State);
         Errors.Reset (Error);
         Event_Readers.Reset (Item, Policy, Error);
         Event_Readers.Begin_Sequence (Item, Length, Error);
         pragma Assert (Error.Code = Errors.No_Error);
         Event_Readers.Abort_Document (Item, Error);
      end;

      for Point in Test_Hooks.Before_Step .. Test_Hooks.After_Step loop
         declare
            Input  : aliased constant String := "[null]";
            Item   : Event_Readers.Reader (Input'Access);
            Error  : Errors.Error_Info;
            Length : Data_Model.Length_Information :=
              (Known => True, Length => 99);
         begin
            Event_Readers.Initialize (Item, Policy, Error);
            Test_Hooks.Arm (Point);
            begin
               Event_Readers.Begin_Sequence (Item, Length, Error);
               pragma Assert (False);
            exception
               when Constraint_Error =>
                  null;
            end;
            pragma Assert (Event_Readers.Container_Depth (Item) = 0);
            pragma Assert (Event_Readers.Budget_Depth (Item) = 0);
            Event_Readers.Read_Null (Item, Error);
            pragma Assert (Error.Code = Errors.Invalid_State);
            Errors.Reset (Error);
            Event_Readers.Reset (Item, Policy, Error);
            Event_Readers.Begin_Sequence (Item, Length, Error);
            pragma Assert (Error.Code = Errors.No_Error);
            Event_Readers.Abort_Document (Item, Error);
         end;

         declare
            Input     : aliased constant String := "[null ,true]";
            Item      : Event_Readers.Reader (Input'Access);
            Error     : Errors.Error_Info;
            Length    : Data_Model.Length_Information;
            Available : Boolean := True;
         begin
            Event_Readers.Initialize (Item, Policy, Error);
            Event_Readers.Begin_Sequence (Item, Length, Error);
            Event_Readers.Next_Element (Item, Available, Error);
            Event_Readers.Read_Null (Item, Error);
            Test_Hooks.Arm (Point);
            Available := True;
            begin
               Event_Readers.Next_Element (Item, Available, Error);
               pragma Assert (False);
            exception
               when Constraint_Error =>
                  null;
            end;
            pragma Assert (Event_Readers.Container_Depth (Item) = 0);
            pragma Assert (Event_Readers.Budget_Depth (Item) = 0);
            Event_Readers.Read_Null (Item, Error);
            pragma Assert (Error.Code = Errors.Invalid_State);
            Errors.Reset (Error);
            Event_Readers.Reset (Item, Policy, Error);
            Event_Readers.Begin_Sequence (Item, Length, Error);
            pragma Assert (Error.Code = Errors.No_Error);
            Event_Readers.Abort_Document (Item, Error);
         end;

         declare
            Input     : aliased constant String := "[null,true]";
            Item      : Event_Readers.Reader (Input'Access);
            Error     : Errors.Error_Info;
            Length    : Data_Model.Length_Information;
            Available : Boolean := True;
         begin
            Event_Readers.Initialize (Item, Policy, Error);
            Event_Readers.Begin_Sequence (Item, Length, Error);
            Event_Readers.Next_Element (Item, Available, Error);
            Event_Readers.Read_Null (Item, Error);
            Test_Hooks.Arm (Point);
            Available := True;
            begin
               Event_Readers.Next_Element (Item, Available, Error);
               pragma Assert (False);
            exception
               when Constraint_Error =>
                  null;
            end;
            pragma Assert (Event_Readers.Container_Depth (Item) = 0);
            pragma Assert (Event_Readers.Budget_Depth (Item) = 0);
            Errors.Reset (Error);
            Event_Readers.Reset (Item, Policy, Error);
            Event_Readers.Begin_Sequence (Item, Length, Error);
            pragma Assert (Error.Code = Errors.No_Error);
            Event_Readers.Abort_Document (Item, Error);
         end;

         declare
            Input     : aliased constant String := "[]";
            Item      : Event_Readers.Reader (Input'Access);
            Error     : Errors.Error_Info;
            Length    : Data_Model.Length_Information;
            Available : Boolean;
         begin
            Event_Readers.Initialize (Item, Policy, Error);
            Event_Readers.Begin_Sequence (Item, Length, Error);
            Event_Readers.Next_Element (Item, Available, Error);
            Test_Hooks.Arm (Point);
            begin
               Event_Readers.End_Sequence (Item, Error);
               pragma Assert (False);
            exception
               when Constraint_Error =>
                  null;
            end;
            pragma
              Assert
                (Event_Readers.Container_Depth (Item) = 0
                   and then Event_Readers.Budget_Depth (Item) = 0);
            Event_Readers.Read_Null (Item, Error);
            pragma Assert (Error.Code = Errors.Invalid_State);
            Errors.Reset (Error);
            Event_Readers.Reset (Item, Policy, Error);
            Event_Readers.Begin_Sequence (Item, Length, Error);
            pragma Assert (Error.Code = Errors.No_Error);
            Event_Readers.Abort_Document (Item, Error);
         end;
      end loop;

      --  Zero-source boundaries and structural summaries reject every
      --  impossible payload before any checked state is published.
      declare
         Input  : aliased constant String := "[]";
         Item   : Event_Readers.Reader (Input'Access);
         Error  : Errors.Error_Info;
         Length : Data_Model.Length_Information;
      begin
         Test_Hooks.Arm_Payload_Contamination (0);
         Event_Readers.Initialize (Item, Policy, Error);
         Event_Readers.Begin_Sequence (Item, Length, Error);
         pragma
           Assert
             (Error.Code = Errors.Invalid_State
                and then Event_Readers.Container_Depth (Item) = 0
                and then Event_Readers.Budget_Depth (Item) = 0);
      end;

      declare
         Input  : aliased constant String := "[]";
         Item   : Event_Readers.Reader (Input'Access);
         Error  : Errors.Error_Info;
         Length : Data_Model.Length_Information;
      begin
         Event_Readers.Initialize (Item, Policy, Error);
         Test_Hooks.Arm_Payload_Contamination (0);
         Event_Readers.Begin_Sequence (Item, Length, Error);
         pragma
           Assert
             (Error.Code = Errors.Invalid_State
                and then Event_Readers.Container_Depth (Item) = 0
                and then Event_Readers.Budget_Depth (Item) = 0);
      end;

      declare
         Input     : aliased constant String := "[]";
         Item      : Event_Readers.Reader (Input'Access);
         Error     : Errors.Error_Info;
         Length    : Data_Model.Length_Information;
         Available : Boolean;
      begin
         Event_Readers.Initialize (Item, Policy, Error);
         Event_Readers.Begin_Sequence (Item, Length, Error);
         Event_Readers.Next_Element (Item, Available, Error);
         Test_Hooks.Arm_Payload_Contamination (1);
         Event_Readers.End_Sequence (Item, Error);
         if Error.Code = Errors.No_Error then
            Event_Readers.Finish_Document (Item, Error);
         end if;
         pragma
           Assert
             (Error.Code = Errors.Invalid_State
                and then not Event_Readers.Is_Complete (Item)
                and then Event_Readers.Container_Depth (Item) = 0
                and then Event_Readers.Budget_Depth (Item) = 0);
         Errors.Reset (Error);
         Event_Readers.Reset (Item, Policy, Error);
         Event_Readers.Begin_Sequence (Item, Length, Error);
         Event_Readers.Next_Element (Item, Available, Error);
         Event_Readers.End_Sequence (Item, Error);
         Event_Readers.Finish_Document (Item, Error);
         pragma Assert (Error.Code = Errors.No_Error);
      end;

      --  Array_End itself is a zero-payload structural event. Contamination
      --  is rejected while the logical frame remains unpublished.
      declare
         Input     : aliased constant String := "[]";
         Item      : Event_Readers.Reader (Input'Access);
         Error     : Errors.Error_Info;
         Length    : Data_Model.Length_Information;
         Available : Boolean := True;
      begin
         Event_Readers.Initialize (Item, Policy, Error);
         Event_Readers.Begin_Sequence (Item, Length, Error);
         Event_Readers.Next_Element (Item, Available, Error);
         pragma Assert (Error.Code = Errors.No_Error and then not Available);
         Test_Hooks.Arm_Payload_Contamination (0);
         Event_Readers.End_Sequence (Item, Error);
         pragma
           Assert
             (Error.Code = Errors.Invalid_State
                and then Event_Readers.Container_Depth (Item) = 0
                and then Event_Readers.Budget_Depth (Item) = 0);
      end;

      --  Structural event source ranges and kinds are validated rather than
      --  trusted as authority from the syntax engine.
      declare
         Input  : aliased constant String := "[]";
         Item   : Event_Readers.Reader (Input'Access);
         Error  : Errors.Error_Info;
         Length : Data_Model.Length_Information;
      begin
         Event_Readers.Initialize (Item, Policy, Error);
         Test_Hooks.Arm_Source_Offset_Override (0, 99);
         Event_Readers.Begin_Sequence (Item, Length, Error);
         pragma
           Assert
             (Error.Code = Errors.Invalid_State
                and then Event_Readers.Container_Depth (Item) = 0
                and then Event_Readers.Budget_Depth (Item) = 0);
      end;

      declare
         Input  : aliased constant String := "[]";
         Item   : Event_Readers.Reader (Input'Access);
         Error  : Errors.Error_Info;
         Length : Data_Model.Length_Information;
      begin
         Event_Readers.Initialize (Item, Policy, Error);
         Test_Hooks.Arm_Kind_Override
           (JSON_Event_Drivers.Event_Kind'Pos
              (JSON_Event_Drivers.Document_End));
         Event_Readers.Begin_Sequence (Item, Length, Error);
         pragma
           Assert
             (Error.Code = Errors.Invalid_State
                and then Event_Readers.Container_Depth (Item) = 0
                and then Event_Readers.Budget_Depth (Item) = 0);
      end;

      --  An explicit abort while a sequence is active preserves the caller's
      --  primary error, unwinds both depth domains, and permits Reset only.
      declare
         Input     : aliased constant String := "[]";
         Item      : Event_Readers.Reader (Input'Access);
         Error     : Errors.Error_Info;
         Length    : Data_Model.Length_Information;
         Available : Boolean;
      begin
         Event_Readers.Initialize (Item, Policy, Error);
         Event_Readers.Begin_Sequence (Item, Length, Error);
         Errors.Fail (Error, Errors.Application_Error, 17, Errors.Byte_Offset);
         Event_Readers.Abort_Document (Item, Error);
         pragma
           Assert
             (Error.Code = Errors.Application_Error
                and then Error.Input_Offset = 17
                and then Event_Readers.Container_Depth (Item) = 0
                and then Event_Readers.Budget_Depth (Item) = 0);
         Errors.Reset (Error);
         Event_Readers.Reset (Item, Policy, Error);
         Event_Readers.Begin_Sequence (Item, Length, Error);
         Event_Readers.Next_Element (Item, Available, Error);
         Event_Readers.End_Sequence (Item, Error);
         Event_Readers.Finish_Document (Item, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Event_Readers.Is_Complete (Item));
      end;

      --  A trailing-byte failure follows exactly one driver abort. This
      --  catches duplicate cleanup when Finish and the common poison path
      --  both observe the same primary error.
      declare
         Input     : aliased constant String := "[]x";
         Item      : Event_Readers.Reader (Input'Access);
         Error     : Errors.Error_Info;
         Length    : Data_Model.Length_Information;
         Available : Boolean;
      begin
         Test_Hooks.Reset_Abort_Count;
         Event_Readers.Initialize (Item, Policy, Error);
         Event_Readers.Begin_Sequence (Item, Length, Error);
         Event_Readers.Next_Element (Item, Available, Error);
         Event_Readers.End_Sequence (Item, Error);
         Event_Readers.Finish_Document (Item, Error);
         pragma
           Assert
             (Error.Code = Errors.Syntax_Error
                and then Test_Hooks.Abort_Count = 1);
      end;

      declare
         Input  : aliased constant String := "x";
         Item   : Event_Readers.Reader (Input'Access);
         Error  : Errors.Error_Info;
         Length : Data_Model.Length_Information;
      begin
         Test_Hooks.Reset_Abort_Count;
         Event_Readers.Initialize (Item, Policy, Error);
         Event_Readers.Begin_Sequence (Item, Length, Error);
         pragma
           Assert
             (Error.Code = Errors.Unexpected_Kind
                and then Test_Hooks.Abort_Count = 1
                and then Event_Readers.Container_Depth (Item) = 0
                and then Event_Readers.Budget_Depth (Item) = 0,
              Error.Code'Image
                & Test_Hooks.Abort_Count'Image
                & Event_Readers.Container_Depth (Item)'Image
                & Event_Readers.Budget_Depth (Item)'Image);
      end;

      declare
         Input : aliased constant String := "nulX";
         Item  : Event_Readers.Reader (Input'Access);
         Error : Errors.Error_Info;
      begin
         Test_Hooks.Reset_Abort_Count;
         Event_Readers.Initialize (Item, Policy, Error);
         Event_Readers.Read_Null (Item, Error);
         pragma
           Assert
             (Error.Code = Errors.Syntax_Error
                and then Test_Hooks.Abort_Count = 1
                and then Event_Readers.Container_Depth (Item) = 0
                and then Event_Readers.Budget_Depth (Item) = 0);
      end;

      for Operation in Unsupported_Operation loop
         Check_Unsupported (Operation);
      end loop;

      for Operation in Supported_Operation loop
         Check_Prelatched (Operation);
      end loop;

      --  A prelatched initialization is a strict no-op. A clean second
      --  initialization poisons the old operation until Reset.
      declare
         Input : aliased constant String := "null";
         Item  : Event_Readers.Reader (Input'Access);
         Error : Errors.Error_Info;
      begin
         Errors.Fail (Error, Errors.Application_Error, 17);
         Event_Readers.Initialize (Item, Policy, Error);
         Errors.Reset (Error);
         Event_Readers.Initialize (Item, Policy, Error);
         pragma Assert (Error.Code = Errors.No_Error);
         Event_Readers.Initialize (Item, Policy, Error);
         pragma Assert (Error.Code = Errors.Invalid_State);
         Errors.Reset (Error);
         Event_Readers.Reset (Item, Policy, Error);
         Event_Readers.Read_Null (Item, Error);
         Event_Readers.Finish_Document (Item, Error);
         pragma Assert (Event_Readers.Is_Complete (Item));
         Event_Readers.Finish_Document (Item, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Event_Readers.Is_Complete (Item));
      end;

      --  Finish before a root fails closed; Abort is idempotent and Reset
      --  starts a fresh budget/parser operation.
      declare
         Input : aliased constant String := "null";
         Item  : Event_Readers.Reader (Input'Access);
         Error : Errors.Error_Info;
      begin
         Event_Readers.Initialize (Item, Policy, Error);
         Event_Readers.Finish_Document (Item, Error);
         pragma Assert (Error.Code = Errors.Invalid_State);
         Event_Readers.Abort_Document (Item, Error);
         Event_Readers.Abort_Document (Item, Error);
         pragma Assert (Error.Code = Errors.Invalid_State);
         Errors.Reset (Error);
         Event_Readers.Reset (Item, Policy, Error);
         Errors.Fail (Error, Errors.Application_Error, 23);
         Event_Readers.Reset (Item, Policy, Error);
         pragma Assert (Error.Code = Errors.Application_Error);
         Errors.Reset (Error);
         Event_Readers.Read_Null (Item, Error);
         Event_Readers.Finish_Document (Item, Error);
         pragma Assert (Event_Readers.Is_Complete (Item));
      end;

      --  A prelatched Finish is a strict no-op, while Finish after a reader
      --  failure reports protocol misuse without trying to revive the parser.
      declare
         Input        : aliased constant String := "null";
         Item         : Event_Readers.Reader (Input'Access);
         Error        : Errors.Error_Info;
         Before_Input : Natural;
      begin
         Event_Readers.Initialize (Item, Policy, Error);
         Event_Readers.Read_Null (Item, Error);
         Before_Input := Event_Readers.Input_Consumed (Item);
         Errors.Fail (Error, Errors.Application_Error, 29, Errors.Byte_Offset);
         Event_Readers.Finish_Document (Item, Error);
         pragma
           Assert
             (Error.Code = Errors.Application_Error
                and then Error.Input_Offset = 29
                and then Event_Readers.Input_Consumed (Item) = Before_Input
                and then not Event_Readers.Is_Complete (Item));
         Errors.Reset (Error);
         Event_Readers.Finish_Document (Item, Error);
         pragma Assert (Event_Readers.Is_Complete (Item));
         Event_Readers.Abort_Document (Item, Error);
         Errors.Reset (Error);
         Event_Readers.Finish_Document (Item, Error);
         pragma Assert (Error.Code = Errors.Invalid_State);
      end;

      --  Every guarded parser boundary leaves the event reader failed and
      --  Reset can construct a complete fresh operation after propagation.
      for Point in Test_Hooks.Before_Step .. Test_Hooks.After_Step loop
         declare
            Input  : aliased constant String := "null";
            Item   : Event_Readers.Reader (Input'Access);
            Error  : Errors.Error_Info;
            Raised : Boolean := False;
         begin
            Test_Hooks.Arm (Point);
            begin
               Event_Readers.Initialize (Item, Policy, Error);
            exception
               when Constraint_Error =>
                  Raised := True;
            end;
            pragma
              Assert (Raised and then not Event_Readers.Is_Complete (Item));
            Event_Readers.Initialize (Item, Policy, Error);
            pragma Assert (Error.Code = Errors.Invalid_State);
            Errors.Reset (Error);
            Event_Readers.Reset (Item, Policy, Error);
            Event_Readers.Read_Null (Item, Error);
            Event_Readers.Finish_Document (Item, Error);
            pragma
              Assert
                (Error.Code = Errors.No_Error
                   and then Event_Readers.Is_Complete (Item));
         end;
      end loop;

      for Point in Test_Hooks.Failure_Point loop
         declare
            Input  : aliased constant String := "null";
            Item   : Event_Readers.Reader (Input'Access);
            Error  : Errors.Error_Info;
            Raised : Boolean := False;
         begin
            Event_Readers.Initialize (Item, Policy, Error);
            Test_Hooks.Arm (Point);
            begin
               Event_Readers.Read_Null (Item, Error);
            exception
               when Constraint_Error =>
                  Raised := True;
            end;
            pragma
              Assert
                (Raised and then not Event_Readers.Is_Complete (Item),
                 Point'Image);
            Errors.Reset (Error);
            Event_Readers.Read_Null (Item, Error);
            pragma Assert (Error.Code = Errors.Invalid_State);
            Errors.Reset (Error);
            Event_Readers.Reset (Item, Policy, Error);
            Event_Readers.Read_Null (Item, Error);
            Event_Readers.Finish_Document (Item, Error);
            pragma
              Assert
                (Error.Code = Errors.No_Error
                   and then Event_Readers.Is_Complete (Item));
         end;
      end loop;

      --  Finish owns both retained-window Step and final-input Step calls.
      --  Abnormal transfer from either boundary poisons the reader, and Reset
      --  rebuilds a complete operation.
      for Point in Test_Hooks.Before_Step .. Test_Hooks.After_Finish_Step loop
         declare
            Input  : aliased constant String := "null ";
            Item   : Event_Readers.Reader (Input'Access);
            Error  : Errors.Error_Info;
            Raised : Boolean := False;
         begin
            Event_Readers.Initialize (Item, Policy, Error);
            Event_Readers.Read_Null (Item, Error);
            pragma Assert (Error.Code = Errors.No_Error);
            Test_Hooks.Arm (Point);
            begin
               Event_Readers.Finish_Document (Item, Error);
            exception
               when Constraint_Error =>
                  Raised := True;
            end;
            pragma
              Assert
                (Raised and then not Event_Readers.Is_Complete (Item),
                 Point'Image);
            Errors.Reset (Error);
            Event_Readers.Finish_Document (Item, Error);
            pragma Assert (Error.Code = Errors.Invalid_State);
            Errors.Reset (Error);
            Event_Readers.Reset (Item, Policy, Error);
            Event_Readers.Read_Null (Item, Error);
            Event_Readers.Finish_Document (Item, Error);
            pragma
              Assert
                (Error.Code = Errors.No_Error
                   and then Event_Readers.Is_Complete (Item));
         end;
      end loop;

      --  Abort and direct Reset discard every scalar terminal state without
      --  replaying or refunding its retained/deferred source.
      declare
         type Terminal_State_Case is
           (EOF_Complete, Retained_Delimiter, Deferred_Follower, Unclassified);

         procedure Exercise
           (State_Case   : Terminal_State_Case;
            Abort_First  : Boolean;
            With_Primary : Boolean)
         is
            Input_Text   : constant String :=
              (case State_Case is
                 when EOF_Complete       => "null",
                 when Retained_Delimiter => "null ",
                 when Deferred_Follower  => "nullx",
                 when Unclassified       => "null ");
            Input        : aliased constant String := Input_Text;
            Item         : Event_Readers.Reader (Input'Access);
            Error        : Errors.Error_Info;
            Local_Policy : Policies.Decode_Policy := Policy;
            Before_Input : Natural;
         begin
            if State_Case = Unclassified then
               Local_Policy.Limits.Maximum_Input_Units := 4;
            end if;
            Event_Readers.Initialize (Item, Local_Policy, Error);
            Event_Readers.Read_Null (Item, Error);
            pragma Assert (Error.Code = Errors.No_Error);
            Before_Input := Event_Readers.Input_Consumed (Item);
            if Abort_First then
               if With_Primary then
                  Errors.Fail
                    (Error, Errors.Application_Error, 41, Errors.Byte_Offset);
               end if;
               Event_Readers.Abort_Document (Item, Error);
               pragma
                 Assert
                   ((if With_Primary
                     then
                       Error.Code = Errors.Application_Error
                       and then Error.Input_Offset = 41
                     else Error.Code = Errors.No_Error)
                      and then Event_Readers.Input_Consumed (Item)
                               = Before_Input);
               Errors.Reset (Error);
            end if;
            Event_Readers.Reset (Item, Policy, Error);
            pragma
              Assert
                (Error.Code = Errors.No_Error
                   and then Event_Readers.Input_Consumed (Item) = 0
                   and then Event_Readers.Values_Consumed (Item) = 0);
            Event_Readers.Read_Null (Item, Error);
            pragma Assert (Error.Code = Errors.No_Error);
            if State_Case /= Deferred_Follower then
               Event_Readers.Finish_Document (Item, Error);
               pragma
                 Assert
                   (Error.Code = Errors.No_Error
                      and then Event_Readers.Is_Complete (Item));
            else
               Event_Readers.Abort_Document (Item, Error);
            end if;
         end Exercise;
      begin
         for State_Case in Terminal_State_Case loop
            Exercise (State_Case, Abort_First => False, With_Primary => False);
            Exercise (State_Case, Abort_First => True, With_Primary => False);
            Exercise (State_Case, Abort_First => True, With_Primary => True);
         end loop;
      end;

      --  The source lower bound is irrelevant; all public offsets are
      --  zero-based relative counts.
      declare
         Input : aliased constant String :=
           [Positive'Last - 3 => 'n',
            Positive'Last - 2 => 'u',
            Positive'Last - 1 => 'l',
            Positive'Last     => 'l'];
         Item  : Event_Readers.Reader (Input'Access);
         Error : Errors.Error_Info;
      begin
         Event_Readers.Initialize (Item, Policy, Error);
         Event_Readers.Read_Null (Item, Error);
         Event_Readers.Finish_Document (Item, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Event_Readers.Input_Offset (Item) = 4
                and then Event_Readers.Input_Consumed (Item) = 4);
      end;

      --  Text decoding also uses relative counts when the source and output
      --  end at Positive'Last.
      declare
         Input  : aliased constant String :=
           [Positive'Last - 2 => '"',
            Positive'Last - 1 => 'x',
            Positive'Last     => '"'];
         Item   : Event_Readers.Reader (Input'Access);
         Error  : Errors.Error_Info;
         Value  : String (Positive'Last .. Positive'Last) := [others => '?'];
         Length : Natural := 0;
      begin
         Event_Readers.Initialize (Item, Policy, Error);
         Event_Readers.Read_Text (Item, Value, Length, Error);
         Event_Readers.Finish_Document (Item, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Length = 1
                and then Value (Positive'Last) = 'x'
                and then Event_Readers.Input_Offset (Item) = 3
                and then Event_Readers.Input_Consumed (Item) = 3);
      end;

      --  Mutation hooks are explicit test-operation resources. A hook that a
      --  prelatched no-op cannot consume is discarded before later parsing.
      declare
         Input : aliased constant String := "null";
         Item  : Event_Readers.Reader (Input'Access);
         Error : Errors.Error_Info;
      begin
         Event_Readers.Initialize (Item, Policy, Error);
         Test_Hooks.Arm_Source_Offset_Override (0, 99);
         Errors.Fail (Error, Errors.Application_Error, 7, Errors.Byte_Offset);
         Event_Readers.Read_Null (Item, Error);
         Test_Hooks.Disarm;
         Errors.Reset (Error);
         Event_Readers.Read_Null (Item, Error);
         Event_Readers.Finish_Document (Item, Error);
         pragma
           Assert
             (Error.Code = Errors.No_Error
                and then Event_Readers.Is_Complete (Item));
      end;

      Test_Hooks.Disarm;
   end Assert_JSON_Event_Scalar_Reader;

end Flyology_Serde.Deserializers.JSON.Testing;
