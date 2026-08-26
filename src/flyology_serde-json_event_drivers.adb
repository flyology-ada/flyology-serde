with Flyology_JSON.Errors;
with Flyology_Serde.JSON_Event_Driver_Test_Hooks;

package body Flyology_Serde.JSON_Event_Drivers is
   package JSON_Errors renames Flyology_JSON.Errors;
   package Test_Hooks renames Flyology_Serde.JSON_Event_Driver_Test_Hooks;

   use type Ada.Streams.Stream_Element_Count;
   use type JSON_Errors.Byte_Offset;
   use type JSON_Errors.Coordinate_Kind;
   use type JSON_Errors.Error_Code;
   use type Errors.Error_Code;
   use type Parsing.Parser_State;
   use type Parsing.Step_Outcome;

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

   function Serde_Code (Code : JSON_Errors.Error_Code) return Errors.Error_Code
   is
   begin
      case Code is
         when JSON_Errors.Invalid_Escape
            | JSON_Errors.Invalid_UTF8
            | JSON_Errors.Invalid_Surrogate
            | JSON_Errors.Raw_Control_Character =>
            return Errors.Invalid_Text;

         when JSON_Errors.Depth_Exhausted       =>
            return Errors.Depth_Exceeded;

         when JSON_Errors.Offset_Exhausted      =>
            return Errors.Capacity_Exceeded;

         when JSON_Errors.No_Error
            | JSON_Errors.Unsupported_Profile
            | JSON_Errors.Incompatible_Profile
            | JSON_Errors.Invalid_State
            | JSON_Errors.Final_Input_Retracted
            | JSON_Errors.Invalid_Writer_Grammar
            | JSON_Errors.Writer_Interrupted
            | JSON_Errors.Duplicate_Name
            | JSON_Errors.Name_Storage_Exhausted
            | JSON_Errors.Duplicate_Index_Exhausted
            | JSON_Errors.Destination_Exhausted
            | JSON_Errors.Destination_Failed
            | JSON_Errors.Commit_Failed
            | JSON_Errors.Abort_Failed          =>
            return Errors.Invalid_State;

         when others                            =>
            return Errors.Syntax_Error;
      end case;
   end Serde_Code;

   function Serde_Offset
     (Self : Driver; Diagnostic : JSON_Errors.Diagnostic) return Natural is
   begin
      if Diagnostic.Coordinate = JSON_Errors.Source_Byte
        and then Diagnostic.Offset <= JSON_Errors.Byte_Offset (Natural'Last)
      then
         return Natural (Diagnostic.Offset);
      end if;
      return Self.Offset;
   end Serde_Offset;

   procedure Account_Progress
     (Consumed    : Boolean;
      Event_Ready : Boolean;
      Count       : in out Zero_Progress_Count;
      Exceeded    : out Boolean) is
   begin
      Exceeded := False;
      if Consumed then
         Count := 0;
      elsif Event_Ready then
         if Count = Zero_Progress_Limit then
            Exceeded := True;
         else
            Count := Count + 1;
         end if;
      end if;
   end Account_Progress;

   procedure Fail
     (Self   : in out Driver;
      Code   : Errors.Error_Code;
      Error  : in out Errors.Error_Info;
      Offset : Natural) is
   begin
      Errors.Fail (Error, Code, Offset, Errors.Byte_Offset);
      Self.Failed := True;
      Self.Document_Accepted := False;
      Self.Window_Valid := False;
   end Fail;

   procedure Fail
     (Self       : in out Driver;
      Diagnostic : JSON_Errors.Diagnostic;
      Error      : in out Errors.Error_Info) is
   begin
      Fail
        (Self,
         Serde_Code (Diagnostic.Code),
         Error,
         Serde_Offset (Self, Diagnostic));
      Self.Diagnostic_Reported := True;
   end Fail;

   procedure Reset_Progress (Self : in out Driver) is
   begin
      Self.Window_Valid := False;
      Self.Offset := 0;
      Self.Zero_Run := 0;
      Self.Failed := False;
      Self.Diagnostic_Reported := False;
      Self.Document_Accepted := False;
   end Reset_Progress;

   procedure Apply_Profile
     (Self : in out Driver; Error : in out Errors.Error_Info)
   is
      Diagnostic : JSON_Errors.Diagnostic;
   begin
      if Error.Code /= Errors.No_Error then
         return;
      end if;

      if Parsing.State (Self.Parser) = Parsing.Uninitialized then
         Parsing.Initialize (Self.Parser, Profile, Diagnostic);
      else
         Parsing.Abort_Document (Self.Parser);
         Parsing.Reset (Self.Parser, Profile, Diagnostic);
      end if;

      if Diagnostic.Code /= JSON_Errors.No_Error then
         Fail (Self, Diagnostic, Error);
         return;
      end if;

      Reset_Progress (Self);
      Self.Initialized := True;
   exception
      when others =>
         Abort_Document (Self);
         raise;
   end Apply_Profile;

   procedure Initialize
     (Self : in out Driver; Error : in out Errors.Error_Info) is
   begin
      Apply_Profile (Self, Error);
   end Initialize;

   procedure Reset (Self : in out Driver; Error : in out Errors.Error_Info) is
   begin
      Apply_Profile (Self, Error);
   end Reset;

   procedure Register_Result
     (Self     : in out Driver;
      Result   : Parsing.Step_Result;
      Consumed : out Boolean;
      Error    : in out Errors.Error_Info)
   is
      Exceeded : Boolean;
   begin
      Consumed := False;
      if Result.Consumed > 1
        or else (Result.Consumed = 1 and then not Self.Window_Valid)
      then
         Fail (Self, Errors.Invalid_State, Error, Self.Offset);
         return;
      end if;

      if Result.Consumed = 1 then
         if Self.Offset = Natural'Last then
            Fail (Self, Errors.Capacity_Exceeded, Error, Self.Offset);
            return;
         end if;
         Self.Offset := Self.Offset + 1;
         Self.Window_Valid := False;
         Consumed := True;
      end if;

      Account_Progress
        (Consumed,
         Result.Outcome = Parsing.Event_Ready,
         Self.Zero_Run,
         Exceeded);
      if Exceeded then
         Parsing.Abort_Document (Self.Parser);
         Fail (Self, Errors.Invalid_State, Error, Self.Offset);
      end if;
   end Register_Result;

   procedure Consume_One
     (Self     : in out Driver;
      Budget   : in out Budgets.Decode_Budget;
      Consumed : out Boolean;
      Error    : in out Errors.Error_Info)
   is
      Result : Parsing.Step_Result;
   begin
      Consumed := False;
      if Error.Code /= Errors.No_Error then
         return;
      elsif not Self.Initialized
        or else Self.Failed
        or else Self.Document_Accepted
      then
         Fail (Self, Errors.Invalid_State, Error, Self.Offset);
         return;
      elsif not Self.Window_Valid then
         if Self.Offset >= Self.Source'Length then
            Fail (Self, Errors.Syntax_Error, Error, Self.Offset);
            return;
         end if;

         Budgets.Consume_Input (Budget, 1, Error);
         if Error.Code /= Errors.No_Error then
            Self.Failed := True;
            return;
         end if;

         Self.Window (Self.Window'First) :=
           Ada.Streams.Stream_Element
             (Character'Pos (Self.Source (Self.Source'First + Self.Offset)));
         Self.Window_Valid := True;
      end if;

      loop
         if Test_Hooks.Enabled then
            Test_Hooks.Raise_If_Armed (Test_Hooks.Before_Step);
         end if;
         Parsing.Step
           (Self.Parser, Self.Window, End_Of_Input => False, Result => Result);
         if Test_Hooks.Enabled then
            Test_Hooks.Raise_If_Armed (Test_Hooks.After_Step);
         end if;
         Register_Result (Self, Result, Consumed, Error);
         exit when Error.Code /= Errors.No_Error;

         case Result.Outcome is
            when Parsing.Event_Ready       =>
               exit when Consumed;

            when Parsing.Need_Input        =>
               if not Consumed then
                  Fail (Self, Errors.Invalid_State, Error, Self.Offset);
               end if;
               exit;

            when Parsing.Document_Complete =>
               Self.Document_Accepted := True;
               if not Consumed then
                  Fail (Self, Errors.Invalid_State, Error, Self.Offset);
               end if;
               exit;

            when Parsing.Step_Failed       =>
               Fail (Self, Result.Diagnostic, Error);
               exit;

            when Parsing.Call_Rejected     =>
               Fail
                 (Self,
                  Errors.Invalid_State,
                  Error,
                  Serde_Offset (Self, Result.Diagnostic));
               exit;
         end case;
      end loop;
   exception
      when others =>
         Abort_Document (Self);
         raise;
   end Consume_One;

   procedure Finish (Self : in out Driver; Error : in out Errors.Error_Info) is
      Empty            : Ada.Streams.Stream_Element_Array (1 .. 0);
      Result           : Parsing.Step_Result;
      Ignored_Consumed : Boolean;
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif not Self.Initialized or else Self.Failed or else Self.Window_Valid
      then
         Fail (Self, Errors.Invalid_State, Error, Self.Offset);
         return;
      elsif Self.Document_Accepted then
         return;
      end if;

      loop
         if Test_Hooks.Enabled then
            Test_Hooks.Raise_If_Armed (Test_Hooks.Before_Finish_Step);
         end if;
         Parsing.Step
           (Self.Parser, Empty, End_Of_Input => True, Result => Result);
         if Test_Hooks.Enabled then
            Test_Hooks.Raise_If_Armed (Test_Hooks.After_Finish_Step);
         end if;
         Register_Result (Self, Result, Ignored_Consumed, Error);
         exit when Error.Code /= Errors.No_Error;

         if Ignored_Consumed then
            Fail (Self, Errors.Invalid_State, Error, Self.Offset);
            exit;
         end if;

         case Result.Outcome is
            when Parsing.Event_Ready                        =>
               null;

            when Parsing.Document_Complete                  =>
               Self.Document_Accepted := True;
               exit;

            when Parsing.Step_Failed                        =>
               Fail (Self, Result.Diagnostic, Error);
               exit;

            when Parsing.Need_Input | Parsing.Call_Rejected =>
               Fail (Self, Errors.Invalid_State, Error, Self.Offset);
               exit;
         end case;
      end loop;
   exception
      when others =>
         Abort_Document (Self);
         raise;
   end Finish;

   procedure Abort_Document
     (Self : in out Driver; Error : in out Errors.Error_Info)
   is
      Diagnostic : JSON_Errors.Diagnostic;
   begin
      if Self.Initialized then
         if not Self.Diagnostic_Reported
           and then Parsing.State (Self.Parser)
                    in Parsing.Failure_Pending | Parsing.Failed
         then
            Diagnostic := Parsing.Terminal_Diagnostic (Self.Parser);
            if Diagnostic.Code /= JSON_Errors.No_Error then
               Fail (Self, Diagnostic, Error);
            end if;
         end if;
         Parsing.Abort_Document (Self.Parser);
      end if;
      Self.Window_Valid := False;
      Self.Failed := True;
      Self.Document_Accepted := False;
   exception
      when others =>
         Self.Window_Valid := False;
         Self.Failed := True;
         Self.Document_Accepted := False;
   end Abort_Document;

   procedure Abort_Document (Self : in out Driver) is
      Ignored : Errors.Error_Info;
   begin
      Errors.Reset (Ignored);
      Abort_Document (Self, Ignored);
   exception
      when others =>
         Self.Window_Valid := False;
         Self.Failed := True;
         Self.Document_Accepted := False;
   end Abort_Document;

   function Input_Offset (Self : Driver) return Natural
   is (Self.Offset);

end Flyology_Serde.JSON_Event_Drivers;
