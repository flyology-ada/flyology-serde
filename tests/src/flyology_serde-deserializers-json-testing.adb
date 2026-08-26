with Ada.Streams;
with Flyology_JSON.Errors;
with Flyology_JSON.Profiles;
with Flyology_Serde.JSON_Event_Driver_Test_Hooks;

package body Flyology_Serde.Deserializers.JSON.Testing is
   package Parsing renames JSON_Event_Drivers.Parsing;
   package JSON_Errors renames Flyology_JSON.Errors;
   package Test_Hooks renames Flyology_Serde.JSON_Event_Driver_Test_Hooks;

   use type Ada.Streams.Stream_Element_Count;
   use type Errors.Error_Code;
   use type JSON_Errors.Error_Code;
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
      JSON_Event_Drivers.Consume_One (Driver, Budget, Consumed, Error);
      pragma Assert (not Consumed);
      pragma Assert (JSON_Event_Drivers.Input_Offset (Driver) = 0);
      pragma Assert (Budgets.Input_Consumed (Budget) = 0);
      JSON_Event_Drivers.Abort_Document (Driver, Error);
      pragma Assert (Error.Code = Errors.Invalid_State);

      --  Unexpected exceptions at every guarded call boundary are cleaned
      --  before they escape. Reset then starts a fresh parser operation.
      declare
         procedure Exercise
           (Point : Test_Hooks.Failure_Point; Finish_Phase : Boolean)
         is
            Valid_Input  : aliased constant String := "null";
            Valid_Driver : JSON_Event_Drivers.Driver (Valid_Input'Access);
            Valid_Budget : Budgets.Decode_Budget;
            Raised       : Boolean := False;
         begin
            Errors.Reset (Error);
            JSON_Event_Drivers.Initialize (Valid_Driver, Error);
            Budgets.Initialize (Valid_Budget, Policy.Limits);
            if Finish_Phase then
               for Index in Valid_Input'Range loop
                  pragma Unreferenced (Index);
                  JSON_Event_Drivers.Consume_One
                    (Valid_Driver, Valid_Budget, Consumed, Error);
                  pragma
                    Assert (Consumed and then Error.Code = Errors.No_Error);
               end loop;
            end if;

            Test_Hooks.Arm (Point);
            begin
               if Finish_Phase then
                  JSON_Event_Drivers.Finish (Valid_Driver, Error);
               else
                  JSON_Event_Drivers.Consume_One
                    (Valid_Driver, Valid_Budget, Consumed, Error);
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
               JSON_Event_Drivers.Consume_One
                 (Valid_Driver, Valid_Budget, Consumed, Error);
               pragma Assert (Consumed and then Error.Code = Errors.No_Error);
            end loop;
            JSON_Event_Drivers.Finish (Valid_Driver, Error);
            pragma Assert (Error.Code = Errors.No_Error);
         end Exercise;
      begin
         Exercise (Test_Hooks.Before_Step, False);
         Exercise (Test_Hooks.After_Step, False);
         Exercise (Test_Hooks.Before_Finish_Step, True);
         Exercise (Test_Hooks.After_Finish_Step, True);
      end;
   end Assert_JSON_Driver_Lifecycle;

end Flyology_Serde.Deserializers.JSON.Testing;
