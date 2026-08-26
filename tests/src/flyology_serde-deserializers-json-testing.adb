with Ada.Streams;
with Flyology_JSON.Errors;
with Flyology_JSON.Profiles;
with Flyology_Serde.JSON_Event_Driver_Test_Hooks;

package body Flyology_Serde.Deserializers.JSON.Testing is
   package Parsing renames JSON_Event_Drivers.Parsing;
   package JSON_Errors renames Flyology_JSON.Errors;
   package Test_Hooks renames Flyology_Serde.JSON_Event_Driver_Test_Hooks;

   use type Ada.Streams.Stream_Element_Count;
   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Array;
   use type Errors.Error_Code;
   use type JSON_Errors.Error_Code;
   use type JSON_Event_Drivers.Event_Kind;
   use type Parsing.Parser_State;
   use type Parsing.Step_Outcome;

   function Syntax_Input_Offset (Self : Reader) return Natural
   is (JSON_Event_Drivers.Input_Offset (Self.Syntax));

   function Budget_Input_Consumed (Self : Reader) return Natural
   is (Budgets.Input_Consumed (Self.Budget));

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
   end Assert_JSON_Driver_Lifecycle;

end Flyology_Serde.Deserializers.JSON.Testing;
