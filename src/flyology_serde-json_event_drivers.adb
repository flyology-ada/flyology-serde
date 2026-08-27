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
   use type Parsing.Decoded_Fragment_Kind;
   use type Parsing.Event_Kind;
   use type Parsing.Parser_State;
   use type Parsing.Slice_Status;
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
      Self.Window_Charged := False;
      Self.Boundary_Pending := False;
      Self.Pending_Boundary := (others => <>);
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
      Self.Window_Charged := False;
      Self.Boundary_Pending := False;
      Self.Pending_Boundary := (others => <>);
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
         Self.Window_Charged := False;
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

   function Summary_Kind (Kind : Parsing.Event_Kind) return Event_Kind is
   begin
      case Kind is
         when Parsing.Document_Begin  =>
            return Document_Begin;

         when Parsing.Document_End    =>
            return Document_End;

         when Parsing.Object_Begin    =>
            return Object_Begin;

         when Parsing.Object_End      =>
            return Object_End;

         when Parsing.Array_Begin     =>
            return Array_Begin;

         when Parsing.Array_End       =>
            return Array_End;

         when Parsing.Name_Begin      =>
            return Name_Begin;

         when Parsing.Name_Fragment   =>
            return Name_Fragment;

         when Parsing.Name_End        =>
            return Name_End;

         when Parsing.String_Begin    =>
            return String_Begin;

         when Parsing.String_Fragment =>
            return String_Fragment;

         when Parsing.String_End      =>
            return String_End;

         when Parsing.Number_Begin    =>
            return Number_Begin;

         when Parsing.Number_Fragment =>
            return Number_Fragment;

         when Parsing.Number_End      =>
            return Number_End;

         when Parsing.Null_Value      =>
            return Null_Value;

         when Parsing.Boolean_Value   =>
            return Boolean_Value;
      end case;
   end Summary_Kind;

   procedure Copy_Summary
     (Self    : in out Driver;
      Result  : Parsing.Step_Result;
      Summary : out Event_Summary;
      Error   : in out Errors.Error_Info)
   is
      Item       : constant Parsing.Event := Result.Item;
      Source     : constant Parsing.Source_Range := Parsing.Source (Item);
      Raw        : Parsing.Chunk_Range;
      Raw_Status : Parsing.Slice_Status;
   begin
      Summary := (others => <>);
      if Source.First > Parsing.Byte_Offset (Natural'Last)
        or else Source.Octet_Length > Parsing.Byte_Offset (Natural'Last)
      then
         Fail (Self, Errors.Capacity_Exceeded, Error, Self.Offset);
         return;
      end if;

      Summary.Kind := Summary_Kind (Parsing.Kind (Item));
      if Test_Hooks.Enabled then
         declare
            Kind_Position : Natural := Event_Kind'Pos (Summary.Kind);
         begin
            Test_Hooks.Apply_Kind_Override (Kind_Position);
            if Kind_Position > Event_Kind'Pos (Event_Kind'Last) then
               Fail (Self, Errors.Invalid_State, Error, Self.Offset);
               return;
            end if;
            Summary.Kind := Event_Kind'Val (Kind_Position);
         end;
      end if;
      Summary.Source_Offset := Natural (Source.First);
      Summary.Source_Length := Natural (Source.Octet_Length);
      if Test_Hooks.Enabled then
         Test_Hooks.Apply_Source_Offset_Override (Summary.Source_Offset);
      end if;

      if Parsing.Has_Raw_Slice (Item) then
         Parsing.Resolve_Raw_Range
           (Item, Result.Input_Origin, Self.Window'Length, Raw, Raw_Status);
         if Raw_Status /= Parsing.Slice_Resolved
           or else Raw.First_Count /= 0
           or else Raw.Octet_Length /= 1
           or else not Self.Window_Valid
         then
            Fail (Self, Errors.Invalid_State, Error, Self.Offset);
            return;
         end if;
         Summary.Has_Raw_Byte := True;
         Summary.Raw_Byte := Self.Window (Self.Window'First);
      end if;

      case Parsing.Decoded_Kind (Item) is
         when Parsing.No_Decoded_Fragment   =>
            null;

         when Parsing.Decoded_Is_Raw_Range  =>
            if not Summary.Has_Raw_Byte then
               Fail (Self, Errors.Invalid_State, Error, Self.Offset);
               return;
            end if;
            Summary.Decoded_Length := 1;
            Summary.Decoded (Summary.Decoded'First) := Summary.Raw_Byte;

         when Parsing.Decoded_Inline_Scalar =>
            declare
               Scalar : constant Parsing.Inline_Scalar :=
                 Parsing.Decoded_Scalar (Item);
            begin
               Summary.Decoded_Length := Scalar.Length;
               for Index in 1 .. Scalar.Length loop
                  Summary.Decoded
                    (Summary.Decoded'First
                     + Ada.Streams.Stream_Element_Offset (Index - 1)) :=
                    Scalar.Octets
                      (Scalar.Octets'First
                       + Ada.Streams.Stream_Element_Offset (Index - 1));
               end loop;
            end;
      end case;

      if Parsing.Kind (Item) = Parsing.Boolean_Value then
         Summary.Boolean_Payload := Parsing.Boolean_Data (Item);
         if Test_Hooks.Enabled then
            Test_Hooks.Apply_Boolean_Override (Summary.Boolean_Payload);
         end if;
      end if;
      if Test_Hooks.Enabled then
         Test_Hooks.Apply_Payload_Contamination
           (Summary.Has_Raw_Byte,
            Summary.Raw_Byte,
            Summary.Decoded_Length,
            Summary.Decoded,
            Summary.Boolean_Payload);
      end if;
   end Copy_Summary;

   function Is_JSON_Whitespace (Item : Character) return Boolean
   is (Item in ' ' | ASCII.HT | ASCII.CR | ASCII.LF);

   procedure Prime_Document_Begin
     (Self : in out Driver; Error : in out Errors.Error_Info)
   is
      Empty    : Ada.Streams.Stream_Element_Array (1 .. 0);
      Result   : Parsing.Step_Result;
      Summary  : Event_Summary;
      Consumed : Boolean;
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif not Self.Initialized
        or else Self.Failed
        or else Self.Document_Accepted
        or else Self.Window_Valid
        or else Self.Boundary_Pending
        or else Self.Offset /= 0
        or else Self.Zero_Run /= 0
      then
         Fail (Self, Errors.Invalid_State, Error, Self.Offset);
         return;
      end if;

      if Test_Hooks.Enabled then
         Test_Hooks.Raise_If_Armed (Test_Hooks.Before_Step);
      end if;
      Parsing.Step
        (Self.Parser, Empty, End_Of_Input => False, Result => Result);
      if Test_Hooks.Enabled then
         Test_Hooks.Raise_If_Armed (Test_Hooks.After_Step);
      end if;
      if Result.Outcome /= Parsing.Event_Ready
        or else Result.Consumed /= 0
        or else Parsing.Kind (Result.Item) /= Parsing.Document_Begin
      then
         Fail (Self, Errors.Invalid_State, Error, Self.Offset);
         return;
      end if;

      Copy_Summary (Self, Result, Summary, Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Register_Result (Self, Result, Consumed, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Consumed then
         Fail (Self, Errors.Invalid_State, Error, Self.Offset);
         return;
      end if;

      Self.Pending_Boundary := Summary;
      Self.Boundary_Pending := True;
   exception
      when others =>
         Abort_Document (Self);
         raise;
   end Prime_Document_Begin;

   procedure Claim_Document_Begin
     (Self    : in out Driver;
      Summary : out Event_Summary;
      Error   : in out Errors.Error_Info) is
   begin
      Summary := (others => <>);
      if Error.Code /= Errors.No_Error then
         return;
      elsif not Self.Initialized
        or else Self.Failed
        or else Self.Document_Accepted
        or else not Self.Boundary_Pending
      then
         Fail (Self, Errors.Invalid_State, Error, Self.Offset);
         return;
      end if;

      Summary := Self.Pending_Boundary;
      Self.Boundary_Pending := False;
      Self.Pending_Boundary := (others => <>);
   end Claim_Document_Begin;

   procedure Consume_Leading_Whitespace
     (Self   : in out Driver;
      Budget : in out Budgets.Decode_Budget;
      Error  : in out Errors.Error_Info)
   is
      Result   : Parsing.Step_Result;
      Consumed : Boolean;
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif not Self.Initialized
        or else Self.Failed
        or else Self.Document_Accepted
        or else not Self.Boundary_Pending
        or else Self.Window_Valid
        or else Self.Offset >= Self.Source'Length
      then
         Fail (Self, Errors.Invalid_State, Error, Self.Offset);
         return;
      end if;

      if Budgets.Input_Remaining (Budget) = 0 then
         Budgets.Consume_Input (Budget, 1, Error);
         if Error.Code = Errors.No_Error then
            Fail (Self, Errors.Invalid_State, Error, Self.Offset);
         else
            Self.Failed := True;
         end if;
         return;
      elsif not Is_JSON_Whitespace
                  (Self.Source (Self.Source'First + Self.Offset))
      then
         Fail (Self, Errors.Invalid_State, Error, Self.Offset);
         return;
      end if;

      Budgets.Consume_Input (Budget, 1, Error);
      if Error.Code /= Errors.No_Error then
         Self.Failed := True;
         return;
      end if;
      if Test_Hooks.Enabled then
         Test_Hooks.Raise_If_Armed (Test_Hooks.Before_Source_Copy);
      end if;
      Self.Window (Self.Window'First) :=
        Ada.Streams.Stream_Element
          (Character'Pos (Self.Source (Self.Source'First + Self.Offset)));
      Self.Window_Valid := True;
      Self.Window_Charged := True;

      if Test_Hooks.Enabled then
         Test_Hooks.Raise_If_Armed (Test_Hooks.Before_Step);
      end if;
      Parsing.Step
        (Self.Parser, Self.Window, End_Of_Input => False, Result => Result);
      if Test_Hooks.Enabled then
         Test_Hooks.Raise_If_Armed (Test_Hooks.After_Step);
      end if;
      Register_Result (Self, Result, Consumed, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Result.Outcome /= Parsing.Need_Input or else not Consumed then
         Fail (Self, Errors.Invalid_State, Error, Self.Offset);
      end if;
   exception
      when others =>
         Abort_Document (Self);
         raise;
   end Consume_Leading_Whitespace;

   procedure Step_Source
     (Self     : in out Driver;
      Budget   : in out Budgets.Decode_Budget;
      Outcome  : out Driver_Outcome;
      Consumed : out Boolean;
      Summary  : out Event_Summary;
      Error    : in out Errors.Error_Info)
   is
      Result : Parsing.Step_Result;
   begin
      Outcome := Need_Source;
      Consumed := False;
      Summary := (others => <>);
      if Error.Code /= Errors.No_Error then
         return;
      elsif not Self.Initialized
        or else Self.Failed
        or else Self.Document_Accepted
        or else Self.Boundary_Pending
      then
         Fail (Self, Errors.Invalid_State, Error, Self.Offset);
         return;
      end if;

      if not Self.Window_Valid then
         if Self.Offset >= Self.Source'Length then
            Fail (Self, Errors.Syntax_Error, Error, Self.Offset);
            return;
         end if;
         Budgets.Consume_Input (Budget, 1, Error);
         if Error.Code /= Errors.No_Error then
            Self.Failed := True;
            return;
         end if;
         if Test_Hooks.Enabled then
            Test_Hooks.Raise_If_Armed (Test_Hooks.Before_Source_Copy);
         end if;
         Self.Window (Self.Window'First) :=
           Ada.Streams.Stream_Element
             (Character'Pos (Self.Source (Self.Source'First + Self.Offset)));
         Self.Window_Valid := True;
         Self.Window_Charged := True;
      elsif not Self.Window_Charged then
         Budgets.Consume_Input (Budget, 1, Error);
         if Error.Code /= Errors.No_Error then
            Self.Window_Valid := False;
            Self.Failed := True;
            return;
         end if;
         Self.Window_Charged := True;
      end if;

      if Test_Hooks.Enabled then
         Test_Hooks.Raise_If_Armed (Test_Hooks.Before_Step);
      end if;
      Parsing.Step
        (Self.Parser, Self.Window, End_Of_Input => False, Result => Result);
      if Test_Hooks.Enabled then
         Test_Hooks.Raise_If_Armed (Test_Hooks.After_Step);
      end if;
      if Result.Outcome = Parsing.Event_Ready then
         Copy_Summary (Self, Result, Summary, Error);
      end if;
      if Error.Code /= Errors.No_Error then
         return;
      end if;

      Register_Result (Self, Result, Consumed, Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;

      case Result.Outcome is
         when Parsing.Event_Ready       =>
            Outcome := Event_Available;

         when Parsing.Need_Input        =>
            if not Consumed then
               Fail (Self, Errors.Invalid_State, Error, Self.Offset);
            end if;

         when Parsing.Document_Complete =>
            Fail (Self, Errors.Invalid_State, Error, Self.Offset);

         when Parsing.Step_Failed       =>
            Fail (Self, Result.Diagnostic, Error);

         when Parsing.Call_Rejected     =>
            Fail
              (Self,
               Errors.Invalid_State,
               Error,
               Serde_Offset (Self, Result.Diagnostic));
      end case;
   exception
      when others =>
         Abort_Document (Self);
         raise;
   end Step_Source;

   procedure Step_Final
     (Self    : in out Driver;
      Outcome : out Driver_Outcome;
      Summary : out Event_Summary;
      Error   : in out Errors.Error_Info)
   is
      Empty    : Ada.Streams.Stream_Element_Array (1 .. 0);
      Result   : Parsing.Step_Result;
      Consumed : Boolean;
   begin
      Outcome := Need_Source;
      Summary := (others => <>);
      if Error.Code /= Errors.No_Error then
         return;
      elsif not Self.Initialized
        or else Self.Failed
        or else Self.Document_Accepted
        or else Self.Boundary_Pending
        or else Self.Window_Valid
        or else Self.Offset /= Self.Source'Length
      then
         Fail (Self, Errors.Invalid_State, Error, Self.Offset);
         return;
      end if;

      if Test_Hooks.Enabled then
         Test_Hooks.Raise_If_Armed (Test_Hooks.Before_Finish_Step);
      end if;
      Parsing.Step
        (Self.Parser, Empty, End_Of_Input => True, Result => Result);
      if Test_Hooks.Enabled then
         Test_Hooks.Raise_If_Armed (Test_Hooks.After_Finish_Step);
      end if;
      if Result.Outcome = Parsing.Event_Ready then
         Copy_Summary (Self, Result, Summary, Error);
      end if;
      if Error.Code /= Errors.No_Error then
         return;
      end if;

      Register_Result (Self, Result, Consumed, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Consumed then
         Fail (Self, Errors.Invalid_State, Error, Self.Offset);
         return;
      end if;

      case Result.Outcome is
         when Parsing.Event_Ready                        =>
            Outcome := Event_Available;

         when Parsing.Document_Complete                  =>
            Self.Document_Accepted := True;
            Outcome := Document_Accepted;

         when Parsing.Step_Failed                        =>
            Fail (Self, Result.Diagnostic, Error);

         when Parsing.Need_Input | Parsing.Call_Rejected =>
            Fail (Self, Errors.Invalid_State, Error, Self.Offset);
      end case;
   exception
      when others =>
         Abort_Document (Self);
         raise;
   end Step_Final;

   function Is_Token_Delimiter (Item : Character) return Boolean
   is (Item in ' ' | ASCII.HT | ASCII.CR | ASCII.LF | ',' | ']' | '}');

   function Terminal_Kind (Expected : Token_Terminal) return Parsing.Event_Kind
   is
   begin
      case Expected is
         when Null_Terminal    =>
            return Parsing.Null_Value;

         when Boolean_Terminal =>
            return Parsing.Boolean_Value;

         when String_Terminal  =>
            return Parsing.String_End;

         when Number_Terminal  =>
            return Parsing.Number_End;
      end case;
   end Terminal_Kind;

   procedure Observe_Token_End
     (Self     : in out Driver;
      Expected : Token_Terminal;
      Summary  : out Event_Summary;
      Error    : in out Errors.Error_Info)
   is
      Result    : Parsing.Step_Result;
      Consumed  : Boolean;
      Candidate : Event_Summary;
   begin
      Summary := (others => <>);
      if Error.Code /= Errors.No_Error then
         return;
      elsif not Self.Initialized
        or else Self.Failed
        or else Self.Document_Accepted
        or else Self.Boundary_Pending
        or else Self.Window_Valid
      then
         Fail (Self, Errors.Invalid_State, Error, Self.Offset);
         return;
      elsif Self.Offset >= Self.Source'Length then
         Fail (Self, Errors.Invalid_State, Error, Self.Offset);
         return;
      elsif not Is_Token_Delimiter
                  (Self.Source (Self.Source'First + Self.Offset))
      then
         Fail (Self, Errors.Invalid_State, Error, Self.Offset);
         return;
      end if;

      Self.Window (Self.Window'First) :=
        Ada.Streams.Stream_Element
          (Character'Pos (Self.Source (Self.Source'First + Self.Offset)));
      Self.Window_Valid := True;
      Self.Window_Charged := False;

      if Test_Hooks.Enabled then
         Test_Hooks.Raise_If_Armed (Test_Hooks.Before_Step);
      end if;
      Parsing.Step
        (Self.Parser, Self.Window, End_Of_Input => False, Result => Result);
      if Test_Hooks.Enabled then
         Test_Hooks.Raise_If_Armed (Test_Hooks.After_Step);
      end if;

      if Result.Consumed /= 0
        or else Result.Outcome /= Parsing.Event_Ready
        or else Parsing.Kind (Result.Item) /= Terminal_Kind (Expected)
      then
         Parsing.Abort_Document (Self.Parser);
         Fail (Self, Errors.Invalid_State, Error, Self.Offset);
         return;
      end if;

      Copy_Summary (Self, Result, Candidate, Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Register_Result (Self, Result, Consumed, Error);
      if Error.Code = Errors.No_Error and then Consumed then
         Fail (Self, Errors.Invalid_State, Error, Self.Offset);
      elsif Error.Code = Errors.No_Error then
         Summary := Candidate;
      end if;
   exception
      when others =>
         Abort_Document (Self);
         raise;
   end Observe_Token_End;

   procedure Observe_Number_End
     (Self    : in out Driver;
      Summary : out Event_Summary;
      Error   : in out Errors.Error_Info) is
   begin
      Observe_Token_End (Self, Number_Terminal, Summary, Error);
   end Observe_Number_End;

   procedure Consume_One
     (Self     : in out Driver;
      Budget   : in out Budgets.Decode_Budget;
      Consumed : out Boolean;
      Error    : in out Errors.Error_Info)
   is
      Discard : Event_Summary_Array (1 .. Maximum_Event_Summaries);
      Count   : Natural;
   begin
      Consume_One (Self, Budget, Consumed, Discard, Count, Error);
   end Consume_One;

   procedure Consume_One
     (Self      : in out Driver;
      Budget    : in out Budgets.Decode_Budget;
      Consumed  : out Boolean;
      Summaries : out Event_Summary_Array;
      Count     : out Natural;
      Error     : in out Errors.Error_Info)
   is
      Result : Parsing.Step_Result;
   begin
      Consumed := False;
      Count := 0;
      Summaries := [others => <>];
      if Error.Code /= Errors.No_Error then
         return;
      elsif Summaries'Length < Maximum_Event_Summaries then
         Fail (Self, Errors.Invalid_State, Error, Self.Offset);
         return;
      elsif not Self.Initialized
        or else Self.Failed
        or else Self.Document_Accepted
        or else Self.Boundary_Pending
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

         if Test_Hooks.Enabled then
            Test_Hooks.Raise_If_Armed (Test_Hooks.Before_Source_Copy);
         end if;
         Self.Window (Self.Window'First) :=
           Ada.Streams.Stream_Element
             (Character'Pos (Self.Source (Self.Source'First + Self.Offset)));
         Self.Window_Valid := True;
         Self.Window_Charged := True;
      elsif not Self.Window_Charged then
         Budgets.Consume_Input (Budget, 1, Error);
         if Error.Code /= Errors.No_Error then
            Self.Window_Valid := False;
            Self.Failed := True;
            return;
         end if;
         Self.Window_Charged := True;
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
         if Result.Outcome = Parsing.Event_Ready then
            if Count = Summaries'Length then
               Fail (Self, Errors.Invalid_State, Error, Self.Offset);
            else
               Copy_Summary
                 (Self, Result, Summaries (Summaries'First + Count), Error);
               if Error.Code = Errors.No_Error then
                  Count := Count + 1;
               end if;
            end if;
         end if;
         exit when Error.Code /= Errors.No_Error;
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
      if Error.Code /= Errors.No_Error then
         Count := 0;
      end if;
   exception
      when others =>
         Abort_Document (Self);
         raise;
   end Consume_One;

   procedure Finish (Self : in out Driver; Error : in out Errors.Error_Info) is
      Discard : Event_Summary_Array (1 .. Maximum_Event_Summaries);
      Count   : Natural;
   begin
      Finish (Self, Discard, Count, Error);
   end Finish;

   procedure Finish
     (Self      : in out Driver;
      Summaries : out Event_Summary_Array;
      Count     : out Natural;
      Error     : in out Errors.Error_Info)
   is
      Empty            : Ada.Streams.Stream_Element_Array (1 .. 0);
      Result           : Parsing.Step_Result;
      Ignored_Consumed : Boolean;
   begin
      Count := 0;
      Summaries := [others => <>];
      if Error.Code /= Errors.No_Error then
         return;
      elsif Summaries'Length < Maximum_Event_Summaries then
         Fail (Self, Errors.Invalid_State, Error, Self.Offset);
         return;
      elsif not Self.Initialized or else Self.Failed or else Self.Window_Valid
      then
         Fail (Self, Errors.Invalid_State, Error, Self.Offset);
         return;
      elsif Self.Boundary_Pending then
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
         if Result.Outcome = Parsing.Event_Ready then
            if Count = Summaries'Length then
               Fail (Self, Errors.Invalid_State, Error, Self.Offset);
            else
               Copy_Summary
                 (Self, Result, Summaries (Summaries'First + Count), Error);
               if Error.Code = Errors.No_Error then
                  Count := Count + 1;
               end if;
            end if;
         end if;
         exit when Error.Code /= Errors.No_Error;
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
      if Error.Code /= Errors.No_Error then
         Count := 0;
      end if;
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
      if Test_Hooks.Enabled then
         Test_Hooks.Note_Abort;
      end if;
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
      Self.Window_Charged := False;
      Self.Boundary_Pending := False;
      Self.Pending_Boundary := (others => <>);
      Self.Failed := True;
      Self.Document_Accepted := False;
   exception
      when others =>
         Self.Window_Valid := False;
         Self.Window_Charged := False;
         Self.Boundary_Pending := False;
         Self.Pending_Boundary := (others => <>);
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
         Self.Window_Charged := False;
         Self.Boundary_Pending := False;
         Self.Pending_Boundary := (others => <>);
         Self.Failed := True;
         Self.Document_Accepted := False;
   end Abort_Document;

   function Input_Offset (Self : Driver) return Natural
   is (Self.Offset);

end Flyology_Serde.JSON_Event_Drivers;
