with Flyology_JSON.Numbers.Signed_Integers;
with Flyology_JSON.Numbers.Unsigned_Integers;
with Flyology_Serde.JSON_Preflights;

package body Flyology_Serde.Deserializers.JSON.Event_Readers is
   package Drivers renames Flyology_Serde.JSON_Event_Drivers;
   package Preflights renames Flyology_Serde.JSON_Preflights;

   package Signed_64 is new
     Flyology_JSON.Numbers.Signed_Integers (Interfaces.Integer_64);
   package Unsigned_64 is new
     Flyology_JSON.Numbers.Unsigned_Integers (Interfaces.Unsigned_64);

   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Streams.Stream_Element;
   use type Drivers.Driver_Outcome;
   use type Drivers.Event_Kind;
   use type Errors.Error_Code;
   use type Errors.Input_Offset_Unit;
   use type Interfaces.IEEE_Float_64;
   use type Signed_64.Parse_Status;
   use type Unsigned_64.Parse_Status;

   Unknown_Length : constant Data_Model.Length_Information :=
     (Known => False, Length => 0);

   function Has_Input (Self : Reader; Ahead : Natural := 0) return Boolean is
   begin
      return
        Ahead <= Self.Source'Length
        and then Self.Cursor <= Self.Source'Length - Ahead
        and then Self.Cursor + Ahead < Self.Source'Length;
   end Has_Input;

   function Current (Self : Reader; Ahead : Natural := 0) return Character is
   begin
      return Self.Source (Self.Source'First + Self.Cursor + Ahead);
   end Current;

   function Is_Whitespace (Item : Character) return Boolean
   is (Item in ' ' | ASCII.HT | ASCII.CR | ASCII.LF);

   function Is_Number_Delimiter (Item : Character) return Boolean
   is (Is_Whitespace (Item) or else Item in ',' | ']' | '}');

   procedure Mark_Root_Complete (Self : in out Reader; State : Lifecycle_State)
   is
   begin
      Self.Root_End_Offset := Self.Cursor;
      Self.State := State;
   end Mark_Root_Complete;

   procedure Latch (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error then
         if Error.Offset_Unit = Errors.Unknown_Offset then
            Error.Input_Offset := Self.Cursor;
            Error.Offset_Unit := Errors.Byte_Offset;
         end if;
         Self.State := Failed;
         Self.Root_End_Offset := 0;
         Self.Document_End_Seen := False;
      end if;
   end Latch;

   procedure Reject
     (Self   : in out Reader;
      Code   : Errors.Error_Code;
      Error  : in out Errors.Error_Info;
      Offset : Natural) is
   begin
      Errors.Fail (Error, Code, Offset, Errors.Byte_Offset);
      Latch (Self, Error);
   end Reject;

   procedure Reject
     (Self  : in out Reader;
      Code  : Errors.Error_Code;
      Error : in out Errors.Error_Info) is
   begin
      Reject (Self, Code, Error, Self.Cursor);
   end Reject;

   procedure Reject_Transcript
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      Reject (Self, Errors.Invalid_State, Error);
      Drivers.Abort_Document (Self.Syntax);
   end Reject_Transcript;

   procedure Reject_Unsupported
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      if Error.Code = Errors.No_Error then
         Reject (Self, Errors.Invalid_State, Error);
      end if;
   end Reject_Unsupported;

   procedure Apply_New_Operation
     (Self   : in out Reader;
      Policy : Policies.Decode_Policy;
      Reset  : Boolean;
      Error  : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error then
         return;
      end if;

      Self.State := Uninitialized;
      Self.Cursor := 0;
      Self.Root_End_Offset := 0;
      Self.Document_End_Seen := False;
      if Reset then
         Drivers.Reset (Self.Syntax, Error);
      else
         Drivers.Initialize (Self.Syntax, Error);
      end if;
      if Error.Code /= Errors.No_Error then
         Latch (Self, Error);
         return;
      end if;

      Budgets.Initialize (Self.Budget, Policy.Limits);
      Drivers.Prime_Document_Begin (Self.Syntax, Error);
      if Error.Code /= Errors.No_Error then
         Latch (Self, Error);
         return;
      end if;

      Self.Policy := Policy;
      Self.State := Ready;
   exception
      when others =>
         Drivers.Abort_Document (Self.Syntax);
         Self.State := Failed;
         Self.Document_End_Seen := False;
         raise;
   end Apply_New_Operation;

   procedure Initialize
     (Self   : in out Reader;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.State /= Uninitialized then
         Reject (Self, Errors.Invalid_State, Error);
         return;
      end if;
      Apply_New_Operation (Self, Policy, Reset => False, Error => Error);
   end Initialize;

   procedure Reset
     (Self   : in out Reader;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Drivers.Abort_Document (Self.Syntax);
      Apply_New_Operation (Self, Policy, Reset => True, Error => Error);
   end Reset;

   procedure Commit_Leading_Whitespace
     (Self : in out Reader; Error : in out Errors.Error_Info)
   is
      Before : Natural;
   begin
      while Error.Code = Errors.No_Error
        and then Self.State = Ready
        and then Has_Input (Self)
        and then Is_Whitespace (Current (Self))
      loop
         Before := Self.Cursor;
         Drivers.Consume_Leading_Whitespace (Self.Syntax, Self.Budget, Error);
         if Error.Code = Errors.No_Error then
            Self.Cursor := Drivers.Input_Offset (Self.Syntax);
            if Before = Natural'Last or else Self.Cursor /= Before + 1 then
               Reject_Transcript (Self, Error);
            end if;
         else
            Latch (Self, Error);
         end if;
      end loop;
   exception
      when others =>
         Drivers.Abort_Document (Self.Syntax);
         Self.State := Failed;
         Self.Document_End_Seen := False;
         raise;
   end Commit_Leading_Whitespace;

   procedure Require_Leading
     (Self : in out Reader; Allowed : String; Error : in out Errors.Error_Info)
   is
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.State /= Ready then
         Reject (Self, Errors.Invalid_State, Error);
         return;
      end if;

      Commit_Leading_Whitespace (Self, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif not Has_Input (Self) then
         Reject (Self, Errors.Syntax_Error, Error);
      elsif (for all Item of Allowed => Current (Self) /= Item) then
         Reject (Self, Errors.Unexpected_Kind, Error);
      end if;
   end Require_Leading;

   procedure Prepare_Root
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Budgets.Consume_Value (Self.Budget, Error);
      if Error.Code /= Errors.No_Error then
         Latch (Self, Error);
      else
         Self.State := Root_In_Progress;
      end if;
   end Prepare_Root;

   procedure Claim_Boundary
     (Self : in out Reader; Error : in out Errors.Error_Info)
   is
      Summary : Drivers.Event_Summary;
   begin
      Drivers.Claim_Document_Begin (Self.Syntax, Summary, Error);
      if Error.Code /= Errors.No_Error then
         Latch (Self, Error);
      elsif Summary.Kind /= Drivers.Document_Begin
        or else Summary.Source_Offset /= 0
        or else Summary.Source_Length /= 0
      then
         Reject_Transcript (Self, Error);
      end if;
   end Claim_Boundary;

   procedure Consume_Owned_Byte
     (Self      : in out Reader;
      Summaries : out Drivers.Event_Summary_Array;
      Count     : out Natural;
      Error     : in out Errors.Error_Info)
   is
      Consumed : Boolean;
      Before   : constant Natural := Self.Cursor;
   begin
      Drivers.Consume_One
        (Self.Syntax, Self.Budget, Consumed, Summaries, Count, Error);
      if Error.Code /= Errors.No_Error then
         Count := 0;
         Latch (Self, Error);
      elsif not Consumed
        or else Before = Natural'Last
        or else Drivers.Input_Offset (Self.Syntax) /= Before + 1
      then
         Count := 0;
         Reject_Transcript (Self, Error);
      else
         Self.Cursor := Before + 1;
      end if;
   exception
      when others =>
         Drivers.Abort_Document (Self.Syntax);
         Self.State := Failed;
         Count := 0;
         raise;
   end Consume_Owned_Byte;

   procedure Collect_Literal
     (Self            : in out Reader;
      Raw_Length      : Positive;
      Expected        : Drivers.Event_Kind;
      Boolean_Payload : Boolean;
      Error           : in out Errors.Error_Info)
   is
      Summaries   :
        Drivers.Event_Summary_Array (1 .. Drivers.Maximum_Event_Summaries);
      Count       : Natural;
      Seen        : Boolean := False;
      Token_First : constant Natural := Self.Cursor;

      procedure Accept_Terminal (Summary : Drivers.Event_Summary) is
      begin
         if Seen
           or else Summary.Kind /= Expected
           or else Summary.Source_Offset /= Token_First
           or else Summary.Source_Length /= Raw_Length
         then
            Reject_Transcript (Self, Error);
         elsif Expected = Drivers.Boolean_Value
           and then Summary.Boolean_Payload /= Boolean_Payload
         then
            Reject_Transcript (Self, Error);
         else
            Seen := True;
         end if;
      end Accept_Terminal;

      procedure Complete_Literal_End is
         Summary  : Drivers.Event_Summary;
         Outcome  : Drivers.Driver_Outcome;
         Terminal : Drivers.Token_Terminal;
      begin
         if Expected = Drivers.Null_Value then
            Terminal := Drivers.Null_Terminal;
         elsif Expected = Drivers.Boolean_Value then
            Terminal := Drivers.Boolean_Terminal;
         else
            Reject_Transcript (Self, Error);
            return;
         end if;

         if not Has_Input (Self) then
            Drivers.Step_Final (Self.Syntax, Outcome, Summary, Error);
            if Error.Code /= Errors.No_Error then
               Latch (Self, Error);
            elsif Outcome /= Drivers.Event_Available then
               Reject_Transcript (Self, Error);
            else
               Accept_Terminal (Summary);
               if Error.Code = Errors.No_Error then
                  Mark_Root_Complete (Self, Root_Complete);
               end if;
            end if;
         elsif Budgets.Input_Remaining (Self.Budget) = 0 then
            Mark_Root_Complete (Self, Root_Complete_Unclassified);
         elsif Is_Number_Delimiter (Current (Self)) then
            Drivers.Observe_Token_End (Self.Syntax, Terminal, Summary, Error);
            if Error.Code /= Errors.No_Error then
               Latch (Self, Error);
            else
               Accept_Terminal (Summary);
               if Error.Code = Errors.No_Error then
                  Mark_Root_Complete (Self, Root_Complete_Retained);
               end if;
            end if;
         else
            Mark_Root_Complete (Self, Root_Complete_Deferred);
         end if;
      end Complete_Literal_End;
   begin
      Claim_Boundary (Self, Error);
      for Byte_Index in 1 .. Raw_Length loop
         exit when Error.Code /= Errors.No_Error;
         Consume_Owned_Byte (Self, Summaries, Count, Error);
         if Error.Code = Errors.No_Error and then Count > 0 then
            for Index in Summaries'First .. Summaries'First + Count - 1 loop
               Accept_Terminal (Summaries (Index));
               exit when Error.Code /= Errors.No_Error;
            end loop;
         end if;
      end loop;
      if Error.Code = Errors.No_Error and then Seen then
         Mark_Root_Complete (Self, Root_Complete);
      elsif Error.Code = Errors.No_Error then
         Complete_Literal_End;
      end if;
   end Collect_Literal;

   procedure Process_Number_Event
     (Self        : in out Reader;
      Summary     : Drivers.Event_Summary;
      Begun       : in out Boolean;
      Next_Byte   : in out Natural;
      Ended       : in out Boolean;
      Token_First : Natural;
      Token_Last  : Natural;
      Error       : in out Errors.Error_Info) is
   begin
      case Summary.Kind is
         when Drivers.Number_Begin    =>
            if Begun
              or else Next_Byte /= Token_First
              or else Ended
              or else Summary.Source_Offset /= Token_First
              or else Summary.Source_Length /= 0
            then
               Reject_Transcript (Self, Error);
            else
               Begun := True;
            end if;

         when Drivers.Number_Fragment =>
            if not Begun
              or else Ended
              or else not Summary.Has_Raw_Byte
              or else Summary.Source_Length /= 1
              or else Summary.Source_Offset /= Next_Byte
              or else Next_Byte >= Token_Last
            then
               Reject_Transcript (Self, Error);
            elsif Character'Pos
                    (Self.Source (Self.Source'First + Summary.Source_Offset))
              /= Integer (Summary.Raw_Byte)
            then
               Reject_Transcript (Self, Error);
            else
               Next_Byte := Next_Byte + 1;
            end if;

         when Drivers.Number_End      =>
            if not Begun
              or else Next_Byte /= Token_Last
              or else Ended
              or else Summary.Source_Offset /= Token_Last
              or else Summary.Source_Length /= 0
            then
               Reject_Transcript (Self, Error);
            else
               Ended := True;
            end if;

         when others                  =>
            Reject_Transcript (Self, Error);
      end case;
   end Process_Number_Event;

   procedure Collect_Number
     (Self        : in out Reader;
      Token_First : Natural;
      Raw_Length  : Positive;
      Error       : in out Errors.Error_Info)
   is
      Summaries  :
        Drivers.Event_Summary_Array (1 .. Drivers.Maximum_Event_Summaries);
      Summary    : Drivers.Event_Summary;
      Count      : Natural;
      Begun      : Boolean := False;
      Next_Byte  : Natural := Token_First;
      Ended      : Boolean := False;
      Outcome    : Drivers.Driver_Outcome;
      Token_Last : constant Natural := Token_First + Raw_Length;
   begin
      Claim_Boundary (Self, Error);
      for Byte_Index in 1 .. Raw_Length loop
         exit when Error.Code /= Errors.No_Error;
         Consume_Owned_Byte (Self, Summaries, Count, Error);
         if Error.Code = Errors.No_Error and then Count > 0 then
            for Index in Summaries'First .. Summaries'First + Count - 1 loop
               Process_Number_Event
                 (Self,
                  Summaries (Index),
                  Begun,
                  Next_Byte,
                  Ended,
                  Token_First,
                  Token_Last,
                  Error);
               exit when Error.Code /= Errors.No_Error;
            end loop;
         end if;
      end loop;
      if Error.Code /= Errors.No_Error then
         return;
      elsif not Begun or else Next_Byte = Token_First or else Ended then
         Reject_Transcript (Self, Error);
         return;
      end if;

      if not Has_Input (Self) then
         Drivers.Step_Final (Self.Syntax, Outcome, Summary, Error);
         if Error.Code /= Errors.No_Error then
            Latch (Self, Error);
            return;
         elsif Outcome /= Drivers.Event_Available then
            Reject_Transcript (Self, Error);
            return;
         end if;
         Process_Number_Event
           (Self,
            Summary,
            Begun,
            Next_Byte,
            Ended,
            Token_First,
            Token_Last,
            Error);
         if Error.Code = Errors.No_Error and then Ended then
            Mark_Root_Complete (Self, Root_Complete);
         end if;
      elsif Is_Number_Delimiter (Current (Self)) then
         Drivers.Observe_Number_End (Self.Syntax, Summary, Error);
         if Error.Code /= Errors.No_Error then
            Latch (Self, Error);
            return;
         end if;
         Process_Number_Event
           (Self,
            Summary,
            Begun,
            Next_Byte,
            Ended,
            Token_First,
            Token_Last,
            Error);
         if Error.Code = Errors.No_Error and then Ended then
            Mark_Root_Complete (Self, Root_Complete_Retained);
         end if;
      else
         Mark_Root_Complete (Self, Root_Complete_Deferred);
      end if;
   end Collect_Number;

   procedure Preflight_Number
     (Self    : in out Reader;
      Maximum : Positive;
      Summary : out Preflights.Number_Summary;
      Start   : out Natural;
      Error   : in out Errors.Error_Info) is
   begin
      Summary := (others => <>);
      Start := Self.Cursor;
      Preflights.Scan_Number
        (Self.Source.all,
         Self.Cursor,
         Budgets.Input_Remaining (Self.Budget),
         Summary,
         Error);
      if Error.Code /= Errors.No_Error then
         Latch (Self, Error);
      elsif Summary.Raw_Length > Maximum then
         Reject (Self, Errors.Out_Of_Range, Error, Start);
      end if;
   end Preflight_Number;

   function Is_Complete (Self : Reader) return Boolean
   is (Self.State = Complete);

   function Input_Offset (Self : Reader) return Natural
   is (Self.Cursor);

   function Input_Consumed (Self : Reader) return Natural
   is (Budgets.Input_Consumed (Self.Budget));

   function Values_Consumed (Self : Reader) return Natural
   is (Budgets.Values_Consumed (Self.Budget));

   overriding
   function Capabilities (Self : Reader) return Data_Model.Format_Capabilities
   is
      pragma Unreferenced (Self);
   begin
      return
        (Unknown_Container_Lengths => True,
         Byte_Values               => True,
         Nonfinite_Float_64        => False,
         Signed_Float_Zero         => True,
         Arbitrary_Map_Keys        => True,
         Lossless_Optionals        => True);
   end Capabilities;

   overriding
   function Peek_Kind
     (Self : in out Reader; Error : in out Errors.Error_Info)
      return Data_Model.Value_Kind
   is
      Summary : Preflights.Number_Summary;
   begin
      if Error.Code /= Errors.No_Error then
         return Data_Model.Null_Value;
      elsif Self.State /= Ready then
         Reject (Self, Errors.Invalid_State, Error);
         return Data_Model.Null_Value;
      end if;
      Commit_Leading_Whitespace (Self, Error);
      if Error.Code /= Errors.No_Error then
         return Data_Model.Null_Value;
      elsif not Has_Input (Self) then
         Reject (Self, Errors.Syntax_Error, Error);
         return Data_Model.Null_Value;
      end if;

      case Current (Self) is
         when 'n'              =>
            return Data_Model.Null_Value;

         when 't' | 'f'        =>
            return Data_Model.Boolean_Value;

         when '-' | '0' .. '9' =>
            Preflights.Scan_Number
              (Self.Source.all,
               Self.Cursor,
               Budgets.Input_Remaining (Self.Budget),
               Summary,
               Error);
            if Error.Code /= Errors.No_Error then
               Latch (Self, Error);
               return Data_Model.Null_Value;
            elsif not Summary.Is_Integer then
               return Data_Model.Float_Value;
            elsif Summary.Negative then
               return Data_Model.Signed_Integer_Value;
            else
               return Data_Model.Unsigned_Integer_Value;
            end if;

         when '"'              =>
            return Data_Model.Text_Value;

         when '['              =>
            return Data_Model.Sequence_Value;

         when '{'              =>
            return Data_Model.Record_Value;

         when others           =>
            Reject (Self, Errors.Syntax_Error, Error);
            return Data_Model.Null_Value;
      end case;
   exception
      when others =>
         Drivers.Abort_Document (Self.Syntax);
         Self.State := Failed;
         Self.Document_End_Seen := False;
         raise;
   end Peek_Kind;

   procedure Process_Document_Event
     (Self    : in out Reader;
      Summary : Drivers.Event_Summary;
      Error   : in out Errors.Error_Info) is
   begin
      if Summary.Kind /= Drivers.Document_End
        or else Summary.Source_Offset /= Self.Root_End_Offset
        or else Summary.Source_Length /= 0
        or else Self.Document_End_Seen
      then
         Reject_Transcript (Self, Error);
      else
         Self.Document_End_Seen := True;
      end if;
   end Process_Document_Event;

   overriding
   procedure Finish_Document
     (Self : in out Reader; Error : in out Errors.Error_Info)
   is
      Outcome  : Drivers.Driver_Outcome;
      Summary  : Drivers.Event_Summary;
      Consumed : Boolean;
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.State = Complete then
         return;
      elsif Self.State
            not in Root_Complete
                 | Root_Complete_Retained
                 | Root_Complete_Deferred
                 | Root_Complete_Unclassified
      then
         Reject (Self, Errors.Invalid_State, Error);
         return;
      end if;

      while Has_Input (Self) loop
         if not Is_Whitespace (Current (Self)) then
            Errors.Fail
              (Error, Errors.Syntax_Error, Self.Cursor, Errors.Byte_Offset);
            Drivers.Abort_Document (Self.Syntax);
            Latch (Self, Error);
            return;
         end if;

         Consumed := False;
         while Error.Code = Errors.No_Error and then not Consumed loop
            Drivers.Step_Source
              (Self.Syntax, Self.Budget, Outcome, Consumed, Summary, Error);
            if Error.Code /= Errors.No_Error then
               Latch (Self, Error);
            elsif Outcome = Drivers.Event_Available then
               Process_Document_Event (Self, Summary, Error);
            elsif Outcome /= Drivers.Need_Source or else not Consumed then
               Reject_Transcript (Self, Error);
            end if;
         end loop;
         if Error.Code = Errors.No_Error then
            if Self.Cursor = Natural'Last then
               Reject (Self, Errors.Capacity_Exceeded, Error);
            else
               Self.Cursor := Self.Cursor + 1;
            end if;
         end if;
         exit when Error.Code /= Errors.No_Error;
      end loop;

      while Error.Code = Errors.No_Error loop
         Drivers.Step_Final (Self.Syntax, Outcome, Summary, Error);
         if Error.Code /= Errors.No_Error then
            Latch (Self, Error);
         elsif Outcome = Drivers.Event_Available then
            Process_Document_Event (Self, Summary, Error);
         elsif Outcome = Drivers.Document_Accepted then
            exit;
         else
            Reject_Transcript (Self, Error);
         end if;
      end loop;

      if Error.Code = Errors.No_Error
        and then (not Self.Document_End_Seen
                  or else Self.Cursor /= Self.Source'Length
                  or else Drivers.Input_Offset (Self.Syntax) /= Self.Cursor)
      then
         Reject_Transcript (Self, Error);
      elsif Error.Code = Errors.No_Error then
         Self.State := Complete;
      end if;
   exception
      when others =>
         Drivers.Abort_Document (Self.Syntax);
         Self.State := Failed;
         Self.Document_End_Seen := False;
         raise;
   end Finish_Document;

   overriding
   procedure Abort_Document
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      Drivers.Abort_Document (Self.Syntax, Error);
      Latch (Self, Error);
      Self.State := Failed;
      Self.Document_End_Seen := False;
   exception
      when others =>
         Self.State := Failed;
         Self.Document_End_Seen := False;
   end Abort_Document;

   overriding
   procedure Read_Null (Self : in out Reader; Error : in out Errors.Error_Info)
   is
   begin
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Require_Leading (Self, "n", Error);
      Prepare_Root (Self, Error);
      Preflights.Match_Literal
        (Self.Source.all,
         Self.Cursor,
         Budgets.Input_Remaining (Self.Budget),
         "null",
         Error);
      if Error.Code /= Errors.No_Error then
         Latch (Self, Error);
         return;
      end if;
      Collect_Literal
        (Self,
         4,
         Drivers.Null_Value,
         Boolean_Payload => False,
         Error           => Error);
   exception
      when others =>
         Drivers.Abort_Document (Self.Syntax);
         Self.State := Failed;
         Self.Document_End_Seen := False;
         raise;
   end Read_Null;

   overriding
   procedure Read_Boolean
     (Self  : in out Reader;
      Value : out Boolean;
      Error : in out Errors.Error_Info)
   is
      Expected : Boolean := False;
      Literal  : String (1 .. 5) := "false";
      Length   : Positive := 5;
   begin
      Value := False;
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Require_Leading (Self, "tf", Error);
      Prepare_Root (Self, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Current (Self) = 't' then
         Expected := True;
         Literal (1 .. 4) := "true";
         Length := 4;
      end if;
      Preflights.Match_Literal
        (Self.Source.all,
         Self.Cursor,
         Budgets.Input_Remaining (Self.Budget),
         Literal (1 .. Length),
         Error);
      if Error.Code /= Errors.No_Error then
         Latch (Self, Error);
         return;
      end if;
      Collect_Literal
        (Self,
         Length,
         Drivers.Boolean_Value,
         Boolean_Payload => Expected,
         Error           => Error);
      if Error.Code = Errors.No_Error then
         Value := Expected;
      end if;
   exception
      when others =>
         Drivers.Abort_Document (Self.Syntax);
         Self.State := Failed;
         Self.Document_End_Seen := False;
         Value := False;
         raise;
   end Read_Boolean;

   overriding
   procedure Read_Signed
     (Self  : in out Reader;
      Value : out Interfaces.Integer_64;
      Error : in out Errors.Error_Info)
   is
      Candidate : Ada.Streams.Stream_Element_Array (1 .. 32) := [others => 0];
      Summary   : Preflights.Number_Summary;
      Start     : Natural;
      Result    : Signed_64.Parse_Result;
   begin
      Value := 0;
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Require_Leading (Self, "-0123456789", Error);
      Prepare_Root (Self, Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Preflight_Number (Self, 32, Summary, Start, Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Collect_Number (Self, Start, Summary.Raw_Length, Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      for Offset in 0 .. Summary.Raw_Length - 1 loop
         Candidate
           (Candidate'First + Ada.Streams.Stream_Element_Offset (Offset)) :=
           Ada.Streams.Stream_Element
             (Character'Pos
                (Self.Source (Self.Source'First + Start + Offset)));
      end loop;
      Signed_64.Parse
        (Candidate
           (Candidate'First
            .. Candidate'First
               + Ada.Streams.Stream_Element_Offset (Summary.Raw_Length - 1)),
         Result);
      case Result.Status is
         when Signed_64.Converted                           =>
            Value := Result.Value;

         when Signed_64.Invalid_Syntax                      =>
            Reject (Self, Errors.Unexpected_Kind, Error, Start);

         when Signed_64.Below_Range | Signed_64.Above_Range =>
            Reject (Self, Errors.Out_Of_Range, Error, Start);
      end case;
   exception
      when others =>
         Drivers.Abort_Document (Self.Syntax);
         Self.State := Failed;
         Self.Document_End_Seen := False;
         Value := 0;
         raise;
   end Read_Signed;

   overriding
   procedure Read_Unsigned
     (Self  : in out Reader;
      Value : out Interfaces.Unsigned_64;
      Error : in out Errors.Error_Info)
   is
      Candidate : Ada.Streams.Stream_Element_Array (1 .. 32) := [others => 0];
      Summary   : Preflights.Number_Summary;
      Start     : Natural;
      Result    : Unsigned_64.Parse_Result;
   begin
      Value := 0;
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Require_Leading (Self, "-0123456789", Error);
      Prepare_Root (Self, Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Preflight_Number (Self, 32, Summary, Start, Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Collect_Number (Self, Start, Summary.Raw_Length, Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      for Offset in 0 .. Summary.Raw_Length - 1 loop
         Candidate
           (Candidate'First + Ada.Streams.Stream_Element_Offset (Offset)) :=
           Ada.Streams.Stream_Element
             (Character'Pos
                (Self.Source (Self.Source'First + Start + Offset)));
      end loop;
      Unsigned_64.Parse
        (Candidate
           (Candidate'First
            .. Candidate'First
               + Ada.Streams.Stream_Element_Offset (Summary.Raw_Length - 1)),
         Result);
      case Result.Status is
         when Unsigned_64.Converted                                =>
            Value := Result.Value;

         when Unsigned_64.Invalid_Syntax                           =>
            Reject (Self, Errors.Unexpected_Kind, Error, Start);

         when Unsigned_64.Negative_Value | Unsigned_64.Above_Range =>
            Reject (Self, Errors.Out_Of_Range, Error, Start);
      end case;
   exception
      when others =>
         Drivers.Abort_Document (Self.Syntax);
         Self.State := Failed;
         Self.Document_End_Seen := False;
         Value := 0;
         raise;
   end Read_Unsigned;

   overriding
   procedure Read_Float_64
     (Self  : in out Reader;
      Value : out Data_Model.Float_64_Value;
      Error : in out Errors.Error_Info)
   is
      Candidate : String (1 .. 768) := [others => ' '];
      Summary   : Preflights.Number_Summary;
      Start     : Natural;
      Parsed    : Interfaces.IEEE_Float_64;
   begin
      Value := Data_Model.Make_Finite (0.0);
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Require_Leading (Self, "-0123456789", Error);
      Prepare_Root (Self, Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Preflight_Number (Self, 768, Summary, Start, Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Collect_Number (Self, Start, Summary.Raw_Length, Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Candidate (1 .. Summary.Raw_Length) :=
        Self.Source
          (Self.Source'First
           + Start
           .. Self.Source'First + Start + Summary.Raw_Length - 1);
      begin
         Parsed :=
           Interfaces.IEEE_Float_64'Value
             (Candidate (1 .. Summary.Raw_Length));
         if Parsed /= Parsed
           or else Parsed < Interfaces.IEEE_Float_64'First
           or else Parsed > Interfaces.IEEE_Float_64'Last
         then
            Reject (Self, Errors.Out_Of_Range, Error, Start);
         else
            Value := Data_Model.Make_Finite (Parsed);
         end if;
      exception
         when Constraint_Error =>
            Reject (Self, Errors.Out_Of_Range, Error, Start);
      end;
   exception
      when others =>
         Drivers.Abort_Document (Self.Syntax);
         Self.State := Failed;
         Self.Document_End_Seen := False;
         Value := Data_Model.Make_Finite (0.0);
         raise;
   end Read_Float_64;

   overriding
   procedure Read_Text
     (Self   : in out Reader;
      Value  : out String;
      Length : out Natural;
      Error  : in out Errors.Error_Info)
   is
      Summary     : Preflights.String_Summary;
      Events      :
        Drivers.Event_Summary_Array (1 .. Drivers.Maximum_Event_Summaries);
      Count       : Natural;
      Phase       : Natural range 0 .. 2 := 0;
      Copied      : Natural := 0;
      Token_First : Natural := 0;
      Token_Last  : Natural := 0;
      Next_Source : Natural := 0;

      procedure Accept_String_End (Item : Drivers.Event_Summary) is
      begin
         if Phase /= 1
           or else Item.Kind /= Drivers.String_End
           or else Item.Source_Offset /= Next_Source
           or else Item.Source_Offset /= Token_Last - 1
           or else Item.Source_Length /= 1
         then
            Reject_Transcript (Self, Error);
         else
            Phase := 2;
         end if;
      end Accept_String_End;

      procedure Complete_String_End is
         Item    : Drivers.Event_Summary;
         Outcome : Drivers.Driver_Outcome;
      begin
         if not Has_Input (Self) then
            Drivers.Step_Final (Self.Syntax, Outcome, Item, Error);
            if Error.Code /= Errors.No_Error then
               Latch (Self, Error);
            elsif Outcome /= Drivers.Event_Available then
               Reject_Transcript (Self, Error);
            else
               Accept_String_End (Item);
               if Error.Code = Errors.No_Error then
                  Mark_Root_Complete (Self, Root_Complete);
               end if;
            end if;
         elsif Budgets.Input_Remaining (Self.Budget) = 0 then
            Mark_Root_Complete (Self, Root_Complete_Unclassified);
         elsif Is_Number_Delimiter (Current (Self)) then
            Drivers.Observe_Token_End
              (Self.Syntax, Drivers.String_Terminal, Item, Error);
            if Error.Code /= Errors.No_Error then
               Latch (Self, Error);
            else
               Accept_String_End (Item);
               if Error.Code = Errors.No_Error then
                  Mark_Root_Complete (Self, Root_Complete_Retained);
               end if;
            end if;
         else
            Mark_Root_Complete (Self, Root_Complete_Deferred);
         end if;
      end Complete_String_End;
   begin
      Value := [others => ' '];
      Length := 0;
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Require_Leading (Self, """", Error);
      Prepare_Root (Self, Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Token_First := Self.Cursor;
      Preflights.Scan_String
        (Self.Source.all,
         Self.Cursor,
         Budgets.Input_Remaining (Self.Budget),
         Summary,
         Error);
      if Error.Code /= Errors.No_Error then
         Latch (Self, Error);
         return;
      end if;
      if Summary.Raw_Length > Self.Source'Length - Token_First then
         Reject_Transcript (Self, Error);
         return;
      end if;
      Token_Last := Token_First + Summary.Raw_Length;
      Budgets.Check_Text_Length (Self.Budget, Summary.Decoded_Length, Error);
      if Error.Code = Errors.No_Error
        and then Summary.Decoded_Length > Value'Length
      then
         Errors.Fail (Error, Errors.Capacity_Exceeded);
      end if;
      if Error.Code /= Errors.No_Error then
         Latch (Self, Error);
         return;
      end if;

      Claim_Boundary (Self, Error);
      for Byte_Index in 1 .. Summary.Raw_Length loop
         exit when Error.Code /= Errors.No_Error;
         Consume_Owned_Byte (Self, Events, Count, Error);
         if Error.Code = Errors.No_Error and then Count > 0 then
            for Index in Events'First .. Events'First + Count - 1 loop
               case Events (Index).Kind is
                  when Drivers.String_Begin    =>
                     if Phase /= 0
                       or else Events (Index).Source_Offset /= Token_First
                       or else Events (Index).Source_Length /= 1
                       or else not Events (Index).Has_Raw_Byte
                       or else Events (Index).Raw_Byte
                               /= Ada.Streams.Stream_Element
                                    (Character'Pos ('"'))
                     then
                        Reject_Transcript (Self, Error);
                     else
                        Phase := 1;
                        Next_Source := Token_First + 1;
                     end if;

                  when Drivers.String_Fragment =>
                     if Phase /= 1
                       or else (Events (Index).Decoded_Length = 0
                                and then not Events (Index).Has_Raw_Byte)
                       or else Events (Index).Source_Length = 0
                       or else Events (Index).Source_Offset /= Next_Source
                       or else Events (Index).Source_Offset <= Token_First
                       or else Events (Index).Source_Offset >= Token_Last - 1
                       or else Events (Index).Source_Length
                               > Token_Last - 1 - Events (Index).Source_Offset
                       or else Copied > Value'Length
                       or else Events (Index).Decoded_Length
                               > Value'Length - Copied
                     then
                        Reject_Transcript (Self, Error);
                     else
                        if Events (Index).Decoded_Length > 0 then
                           for Fragment_Index in
                             0 .. Events (Index).Decoded_Length - 1
                           loop
                              Value (Value'First + Copied + Fragment_Index) :=
                                Character'Val
                                  (Events (Index).Decoded
                                     (Events (Index).Decoded'First
                                      + Ada.Streams.Stream_Element_Offset
                                          (Fragment_Index)));
                           end loop;
                        end if;
                        Copied := Copied + Events (Index).Decoded_Length;
                        Next_Source :=
                          Events (Index).Source_Offset
                          + Events (Index).Source_Length;
                     end if;

                  when Drivers.String_End      =>
                     Accept_String_End (Events (Index));

                  when others                  =>
                     Reject_Transcript (Self, Error);
               end case;
               exit when Error.Code /= Errors.No_Error;
            end loop;
         end if;
      end loop;
      if Error.Code = Errors.No_Error and then Copied /= Summary.Decoded_Length
      then
         Reject_Transcript (Self, Error);
      elsif Error.Code = Errors.No_Error and then Phase = 2 then
         Mark_Root_Complete (Self, Root_Complete);
      elsif Error.Code = Errors.No_Error and then Phase = 1 then
         Complete_String_End;
      elsif Error.Code = Errors.No_Error then
         Reject_Transcript (Self, Error);
      end if;

      if Error.Code = Errors.No_Error then
         Length := Copied;
      else
         Value := [others => ' '];
         Length := 0;
      end if;
   exception
      when others =>
         Drivers.Abort_Document (Self.Syntax);
         Self.State := Failed;
         Self.Document_End_Seen := False;
         Value := [others => ' '];
         Length := 0;
         raise;
   end Read_Text;

   overriding
   procedure Read_Bytes
     (Self   : in out Reader;
      Value  : out Ada.Streams.Stream_Element_Array;
      Length : out Natural;
      Error  : in out Errors.Error_Info) is
   begin
      Value := [others => 0];
      Length := 0;
      Reject_Unsupported (Self, Error);
   end Read_Bytes;

   overriding
   procedure Skip_Value
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      Reject_Unsupported (Self, Error);
   end Skip_Value;

   overriding
   procedure Begin_Optional
     (Self    : in out Reader;
      Present : out Boolean;
      Error   : in out Errors.Error_Info) is
   begin
      Present := False;
      Reject_Unsupported (Self, Error);
   end Begin_Optional;

   overriding
   procedure End_Optional
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      Reject_Unsupported (Self, Error);
   end End_Optional;

   overriding
   procedure Begin_Sequence
     (Self   : in out Reader;
      Length : out Data_Model.Length_Information;
      Error  : in out Errors.Error_Info) is
   begin
      Length := Unknown_Length;
      Reject_Unsupported (Self, Error);
   end Begin_Sequence;

   overriding
   procedure Next_Element
     (Self      : in out Reader;
      Available : out Boolean;
      Error     : in out Errors.Error_Info) is
   begin
      Available := False;
      Reject_Unsupported (Self, Error);
   end Next_Element;

   overriding
   procedure End_Sequence
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      Reject_Unsupported (Self, Error);
   end End_Sequence;

   overriding
   procedure Begin_Map
     (Self   : in out Reader;
      Length : out Data_Model.Length_Information;
      Error  : in out Errors.Error_Info) is
   begin
      Length := Unknown_Length;
      Reject_Unsupported (Self, Error);
   end Begin_Map;

   overriding
   procedure Next_Map_Entry
     (Self      : in out Reader;
      Available : out Boolean;
      Error     : in out Errors.Error_Info) is
   begin
      Available := False;
      Reject_Unsupported (Self, Error);
   end Next_Map_Entry;

   overriding
   procedure End_Map (Self : in out Reader; Error : in out Errors.Error_Info)
   is
   begin
      Reject_Unsupported (Self, Error);
   end End_Map;

   overriding
   procedure Begin_Record
     (Self      : in out Reader;
      Type_Name : String;
      Length    : out Data_Model.Length_Information;
      Error     : in out Errors.Error_Info)
   is
      pragma Unreferenced (Type_Name);
   begin
      Length := Unknown_Length;
      Reject_Unsupported (Self, Error);
   end Begin_Record;

   overriding
   procedure Next_Field
     (Self      : in out Reader;
      Name      : out String;
      Length    : out Natural;
      Available : out Boolean;
      Error     : in out Errors.Error_Info) is
   begin
      Name := [others => ' '];
      Length := 0;
      Available := False;
      Reject_Unsupported (Self, Error);
   end Next_Field;

   overriding
   procedure End_Record
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      Reject_Unsupported (Self, Error);
   end End_Record;

   overriding
   procedure Read_Enumeration
     (Self         : in out Reader;
      Type_Name    : String;
      Literal_Name : out String;
      Length       : out Natural;
      Error        : in out Errors.Error_Info)
   is
      pragma Unreferenced (Type_Name);
   begin
      Literal_Name := [others => ' '];
      Length := 0;
      Reject_Unsupported (Self, Error);
   end Read_Enumeration;

   overriding
   procedure Begin_Variant
     (Self             : in out Reader;
      Type_Name        : String;
      Alternative_Name : out String;
      Name_Length      : out Natural;
      Length           : out Data_Model.Length_Information;
      Error            : in out Errors.Error_Info)
   is
      pragma Unreferenced (Type_Name);
   begin
      Alternative_Name := [others => ' '];
      Name_Length := 0;
      Length := Unknown_Length;
      Reject_Unsupported (Self, Error);
   end Begin_Variant;

   overriding
   procedure End_Variant
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      Reject_Unsupported (Self, Error);
   end End_Variant;
end Flyology_Serde.Deserializers.JSON.Event_Readers;
