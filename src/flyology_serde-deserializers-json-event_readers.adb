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

   function Has_Empty_Payload (Item : Drivers.Event_Summary) return Boolean
   is (not Item.Has_Raw_Byte
       and then Item.Raw_Byte = 0
       and then Item.Decoded_Length = 0
       and then (for all Value of Item.Decoded => Value = 0)
       and then not Item.Boolean_Payload);

   procedure Mark_Value_Complete
     (Self             : in out Reader;
      Terminal         : Terminal_State;
      Saw_Document_End : Boolean := False) is
   begin
      if Self.Depth = 0 then
         if Self.Root /= Root_In_Progress then
            raise Program_Error;
         end if;
         Self.Root := Root_Complete;
         Self.Root_End_Offset := Self.Cursor;
         Self.Document_End_Seen := Saw_Document_End;
         Self.Owner :=
           (if Terminal = No_Pending_Terminal
            then No_Terminal_Owner
            else Root_Terminal);
         Self.Owner_Depth := 0;
      else
         if Self.Stack (Self.Depth).Child /= Child_In_Progress then
            raise Program_Error;
         end if;
         Self.Stack (Self.Depth).Child := No_Child;
         Self.Owner :=
           (if Terminal = No_Pending_Terminal
            then No_Terminal_Owner
            else Sequence_Child_Terminal);
         Self.Owner_Depth := Self.Depth;
      end if;
      Self.Terminal := Terminal;
   end Mark_Value_Complete;

   procedure Publish_Failed
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      while Budgets.Depth (Self.Budget) > 0 loop
         Budgets.Leave_Container (Self.Budget, Error);
      end loop;
      Self.Stack := [others => <>];
      Self.Depth := 0;
      Self.Root := Root_Ready;
      Self.Terminal := No_Pending_Terminal;
      Self.Owner := No_Terminal_Owner;
      Self.Owner_Depth := 0;
      Self.Root_End_Offset := 0;
      Self.Document_Begin_Seen := False;
      Self.Document_End_Seen := False;
      Self.Operation := Failed;
   end Publish_Failed;

   procedure Latch (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error and then Self.Operation /= Failed then
         if Error.Offset_Unit = Errors.Unknown_Offset then
            Error.Input_Offset := Self.Cursor;
            Error.Offset_Unit := Errors.Byte_Offset;
         end if;
         begin
            Drivers.Abort_Document (Self.Syntax, Error);
         exception
            when others =>
               null;
         end;
         Publish_Failed (Self, Error);
      end if;
   end Latch;

   procedure Poison_After_Exception (Self : in out Reader) is
      Cleanup_Error : Errors.Error_Info;
   begin
      Drivers.Abort_Document (Self.Syntax);
      while Budgets.Depth (Self.Budget) > 0 loop
         Budgets.Leave_Container (Self.Budget, Cleanup_Error);
      end loop;
      Self.Stack := [others => <>];
      Self.Depth := 0;
      Self.Operation := Failed;
      Self.Root := Root_Ready;
      Self.Terminal := No_Pending_Terminal;
      Self.Owner := No_Terminal_Owner;
      Self.Owner_Depth := 0;
      Self.Root_End_Offset := 0;
      Self.Document_Begin_Seen := False;
      Self.Document_End_Seen := False;
   exception
      when others =>
         Self.Stack := [others => <>];
         Self.Depth := 0;
         Self.Operation := Failed;
         Self.Root := Root_Ready;
         Self.Terminal := No_Pending_Terminal;
         Self.Owner := No_Terminal_Owner;
         Self.Owner_Depth := 0;
         Self.Root_End_Offset := 0;
         Self.Document_Begin_Seen := False;
         Self.Document_End_Seen := False;
   end Poison_After_Exception;

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

      Self.Operation := Uninitialized;
      Self.Root := Root_Ready;
      Self.Stack := [others => <>];
      Self.Depth := 0;
      Self.Terminal := No_Pending_Terminal;
      Self.Owner := No_Terminal_Owner;
      Self.Owner_Depth := 0;
      Self.Cursor := 0;
      Self.Root_End_Offset := 0;
      Self.Document_Begin_Seen := False;
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
      Self.Operation := Ready;
   exception
      when others =>
         Poison_After_Exception (Self);
         raise;
   end Apply_New_Operation;

   procedure Initialize
     (Self   : in out Reader;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.Operation /= Uninitialized then
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
        and then Self.Operation = Ready
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
         Poison_After_Exception (Self);
         raise;
   end Commit_Leading_Whitespace;

   procedure Commit_Value_Whitespace
     (Self : in out Reader; Error : in out Errors.Error_Info);

   procedure Check_Value_Ready
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.Operation not in Ready | Active
        or else Self.Terminal /= No_Pending_Terminal
      then
         Reject (Self, Errors.Invalid_State, Error);
      elsif Self.Depth = 0 then
         if Self.Root /= Root_Ready then
            Reject (Self, Errors.Invalid_State, Error);
         end if;
      elsif Self.Stack (Self.Depth).Kind /= Sequence_Container
        or else Self.Stack (Self.Depth).Child /= Child_Ready
      then
         Reject (Self, Errors.Invalid_State, Error);
      end if;
   end Check_Value_Ready;

   procedure Require_Leading
     (Self : in out Reader; Allowed : String; Error : in out Errors.Error_Info)
   is
   begin
      if Error.Code /= Errors.No_Error then
         return;
      end if;

      Check_Value_Ready (Self, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.Operation = Ready then
         Commit_Leading_Whitespace (Self, Error);
      else
         Commit_Value_Whitespace (Self, Error);
      end if;
      if Error.Code /= Errors.No_Error then
         return;
      elsif not Has_Input (Self) then
         Reject (Self, Errors.Syntax_Error, Error);
      elsif (for all Item of Allowed => Current (Self) /= Item) then
         Reject (Self, Errors.Unexpected_Kind, Error);
      end if;
   end Require_Leading;

   procedure Prepare_Value
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Budgets.Consume_Value (Self.Budget, Error);
      if Error.Code /= Errors.No_Error then
         Latch (Self, Error);
      else
         Self.Operation := Active;
         if Self.Depth = 0 then
            Self.Root := Root_In_Progress;
         else
            Self.Stack (Self.Depth).Child := Child_In_Progress;
         end if;
      end if;
   end Prepare_Value;

   procedure Claim_Boundary
     (Self : in out Reader; Error : in out Errors.Error_Info)
   is
      Summary : Drivers.Event_Summary;
   begin
      if Self.Depth /= 0 or else Self.Document_Begin_Seen then
         return;
      end if;
      Drivers.Claim_Document_Begin (Self.Syntax, Summary, Error);
      if Error.Code /= Errors.No_Error then
         Latch (Self, Error);
      elsif Summary.Kind /= Drivers.Document_Begin
        or else Summary.Source_Offset /= 0
        or else Summary.Source_Length /= 0
        or else not Has_Empty_Payload (Summary)
      then
         Reject_Transcript (Self, Error);
      else
         Self.Document_Begin_Seen := True;
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
         Poison_After_Exception (Self);
         Count := 0;
         raise;
   end Consume_Owned_Byte;

   procedure Commit_Value_Whitespace
     (Self : in out Reader; Error : in out Errors.Error_Info)
   is
      Summaries :
        Drivers.Event_Summary_Array (1 .. Drivers.Maximum_Event_Summaries);
      Count     : Natural;
   begin
      while Error.Code = Errors.No_Error
        and then Has_Input (Self)
        and then Is_Whitespace (Current (Self))
      loop
         Consume_Owned_Byte (Self, Summaries, Count, Error);
         if Error.Code = Errors.No_Error and then Count /= 0 then
            Reject_Transcript (Self, Error);
         end if;
      end loop;
   end Commit_Value_Whitespace;

   procedure Clear_Terminal (Self : in out Reader) is
   begin
      Self.Terminal := No_Pending_Terminal;
      Self.Owner := No_Terminal_Owner;
      Self.Owner_Depth := 0;
   end Clear_Terminal;

   procedure Consume_Separator
     (Self     : in out Reader;
      Expected : Character;
      Error    : in out Errors.Error_Info)
   is
      Summaries :
        Drivers.Event_Summary_Array (1 .. Drivers.Maximum_Event_Summaries);
      Count     : Natural;
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif not Has_Input (Self) or else Current (Self) /= Expected then
         Reject (Self, Errors.Syntax_Error, Error);
         return;
      end if;
      Consume_Owned_Byte (Self, Summaries, Count, Error);
      if Error.Code = Errors.No_Error and then Count /= 0 then
         Reject_Transcript (Self, Error);
      end if;
   end Consume_Separator;

   procedure Consume_Structure
     (Self               : in out Reader;
      Expected_Byte      : Character;
      Expected_Event     : Drivers.Event_Kind;
      Allow_Document_End : Boolean;
      Saw_Document_End   : out Boolean;
      Error              : in out Errors.Error_Info)
   is
      Summaries :
        Drivers.Event_Summary_Array (1 .. Drivers.Maximum_Event_Summaries);
      Count     : Natural;
      Before    : constant Natural := Self.Cursor;

      function Valid_Structure (Item : Drivers.Event_Summary) return Boolean
      is (Item.Kind = Expected_Event
          and then Item.Source_Offset = Before
          and then Item.Source_Length = 1
          and then Item.Has_Raw_Byte
          and then Item.Raw_Byte
                   = Ada.Streams.Stream_Element (Character'Pos (Expected_Byte))
          and then Item.Decoded_Length = 0
          and then (for all Value of Item.Decoded => Value = 0)
          and then not Item.Boolean_Payload);
   begin
      Saw_Document_End := False;
      if Error.Code /= Errors.No_Error then
         return;
      elsif not Has_Input (Self) or else Current (Self) /= Expected_Byte then
         Reject (Self, Errors.Syntax_Error, Error);
         return;
      end if;
      Consume_Owned_Byte (Self, Summaries, Count, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Count = 0 or else not Valid_Structure (Summaries (Summaries'First))
      then
         Reject_Transcript (Self, Error);
         return;
      end if;

      if Count = 1 then
         null;
      elsif Allow_Document_End
        and then Count = 2
        and then Summaries (Summaries'First + 1).Kind = Drivers.Document_End
        and then Summaries (Summaries'First + 1).Source_Offset = Before + 1
        and then Summaries (Summaries'First + 1).Source_Length = 0
        and then Has_Empty_Payload (Summaries (Summaries'First + 1))
        and then not Self.Document_End_Seen
      then
         Saw_Document_End := True;
      else
         Reject_Transcript (Self, Error);
      end if;
   end Consume_Structure;

   function Is_Value_Leading (Item : Character) return Boolean
   is (Item in 'n' | 't' | 'f' | '-' | '0' .. '9' | '"' | '[' | '{');

   procedure Push_Sequence
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      Budgets.Enter_Container (Self.Budget, Unknown_Length, Error);
      if Error.Code /= Errors.No_Error then
         Latch (Self, Error);
      elsif Self.Depth = Policies.Maximum_Supported_Nesting then
         Reject (Self, Errors.Depth_Exceeded, Error);
      else
         Self.Depth := Self.Depth + 1;
         Self.Stack (Self.Depth) :=
           (Kind       => Sequence_Container,
            Child      => No_Child,
            Map_Phase  => Map_Needs_Entry,
            First_Item => True,
            Exhausted  => False);
      end if;
   end Push_Sequence;

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
                  Mark_Value_Complete (Self, No_Pending_Terminal);
               end if;
            end if;
         elsif Budgets.Input_Remaining (Self.Budget) = 0 then
            Mark_Value_Complete (Self, Unclassified_Exhausted);
         elsif Is_Number_Delimiter (Current (Self)) then
            Drivers.Observe_Token_End (Self.Syntax, Terminal, Summary, Error);
            if Error.Code /= Errors.No_Error then
               Latch (Self, Error);
            else
               Accept_Terminal (Summary);
               if Error.Code = Errors.No_Error then
                  Mark_Value_Complete (Self, Retained_Delimiter);
               end if;
            end if;
         else
            Mark_Value_Complete (Self, Deferred_Invalid_Follower);
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
         Mark_Value_Complete (Self, No_Pending_Terminal);
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
            Mark_Value_Complete (Self, No_Pending_Terminal);
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
            Mark_Value_Complete (Self, Retained_Delimiter);
         end if;
      else
         Mark_Value_Complete (Self, Deferred_Invalid_Follower);
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
   is (Self.Operation = Complete);

   function Input_Offset (Self : Reader) return Natural
   is (Self.Cursor);

   function Input_Consumed (Self : Reader) return Natural
   is (Budgets.Input_Consumed (Self.Budget));

   function Values_Consumed (Self : Reader) return Natural
   is (Budgets.Values_Consumed (Self.Budget));

   function Container_Depth (Self : Reader) return Natural
   is (Self.Depth);

   function Budget_Depth (Self : Reader) return Natural
   is (Budgets.Depth (Self.Budget));

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
      end if;
      Check_Value_Ready (Self, Error);
      if Error.Code = Errors.No_Error and then Self.Operation = Ready then
         Commit_Leading_Whitespace (Self, Error);
      elsif Error.Code = Errors.No_Error then
         Commit_Value_Whitespace (Self, Error);
      end if;
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
         Poison_After_Exception (Self);
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
        or else not Has_Empty_Payload (Summary)
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
      elsif Self.Operation = Complete then
         return;
      elsif Self.Operation /= Active
        or else Self.Root /= Root_Complete
        or else Self.Depth /= 0
        or else Self.Owner not in No_Terminal_Owner | Root_Terminal
      then
         Reject (Self, Errors.Invalid_State, Error);
         return;
      end if;

      while Has_Input (Self) loop
         if not Is_Whitespace (Current (Self)) then
            Errors.Fail
              (Error, Errors.Syntax_Error, Self.Cursor, Errors.Byte_Offset);
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
         Clear_Terminal (Self);
         Self.Operation := Complete;
      end if;
   exception
      when others =>
         Poison_After_Exception (Self);
         raise;
   end Finish_Document;

   overriding
   procedure Abort_Document
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      Drivers.Abort_Document (Self.Syntax, Error);
      if Error.Code /= Errors.No_Error
        and then Error.Offset_Unit = Errors.Unknown_Offset
      then
         Error.Input_Offset := Self.Cursor;
         Error.Offset_Unit := Errors.Byte_Offset;
      end if;
      Publish_Failed (Self, Error);
   exception
      when others =>
         Poison_After_Exception (Self);
   end Abort_Document;

   overriding
   procedure Read_Null (Self : in out Reader; Error : in out Errors.Error_Info)
   is
   begin
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Require_Leading (Self, "n", Error);
      Prepare_Value (Self, Error);
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
         Poison_After_Exception (Self);
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
      Prepare_Value (Self, Error);
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
         Poison_After_Exception (Self);
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
      Prepare_Value (Self, Error);
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
         Poison_After_Exception (Self);
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
      Prepare_Value (Self, Error);
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
         Poison_After_Exception (Self);
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
      Prepare_Value (Self, Error);
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
         Poison_After_Exception (Self);
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
                  Mark_Value_Complete (Self, No_Pending_Terminal);
               end if;
            end if;
         elsif Budgets.Input_Remaining (Self.Budget) = 0 then
            Mark_Value_Complete (Self, Unclassified_Exhausted);
         elsif Is_Number_Delimiter (Current (Self)) then
            Drivers.Observe_Token_End
              (Self.Syntax, Drivers.String_Terminal, Item, Error);
            if Error.Code /= Errors.No_Error then
               Latch (Self, Error);
            else
               Accept_String_End (Item);
               if Error.Code = Errors.No_Error then
                  Mark_Value_Complete (Self, Retained_Delimiter);
               end if;
            end if;
         else
            Mark_Value_Complete (Self, Deferred_Invalid_Follower);
         end if;
      end Complete_String_End;
   begin
      Value := [others => ' '];
      Length := 0;
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Require_Leading (Self, """", Error);
      Prepare_Value (Self, Error);
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
         Mark_Value_Complete (Self, No_Pending_Terminal);
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
         Poison_After_Exception (Self);
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

   procedure Admit_Sequence_Child
     (Self      : in out Reader;
      Available : out Boolean;
      Error     : in out Errors.Error_Info) is
   begin
      Available := False;
      if Error.Code /= Errors.No_Error then
         return;
      elsif not Has_Input (Self) then
         Reject (Self, Errors.Syntax_Error, Error);
      elsif not Is_Value_Leading (Current (Self)) then
         Reject (Self, Errors.Syntax_Error, Error);
      else
         Budgets.Consume_Container_Item (Self.Budget, Error);
         if Error.Code /= Errors.No_Error then
            Latch (Self, Error);
         else
            Self.Stack (Self.Depth).First_Item := False;
            Self.Stack (Self.Depth).Child := Child_Ready;
            Available := True;
         end if;
      end if;
   end Admit_Sequence_Child;

   overriding
   procedure Begin_Sequence
     (Self   : in out Reader;
      Length : out Data_Model.Length_Information;
      Error  : in out Errors.Error_Info)
   is
      Saw_Document_End : Boolean;
   begin
      Length := Unknown_Length;
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Require_Leading (Self, "[", Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Prepare_Value (Self, Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Claim_Boundary (Self, Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Consume_Structure
        (Self,
         '[',
         Drivers.Array_Begin,
         Allow_Document_End => False,
         Saw_Document_End   => Saw_Document_End,
         Error              => Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Saw_Document_End then
         Reject_Transcript (Self, Error);
      else
         Push_Sequence (Self, Error);
      end if;
   exception
      when others =>
         Poison_After_Exception (Self);
         Length := Unknown_Length;
         raise;
   end Begin_Sequence;

   overriding
   procedure Next_Element
     (Self      : in out Reader;
      Available : out Boolean;
      Error     : in out Errors.Error_Info) is
   begin
      Available := False;
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.Operation /= Active
        or else Self.Depth = 0
        or else Self.Stack (Self.Depth).Kind /= Sequence_Container
        or else Self.Stack (Self.Depth).Child /= No_Child
        or else Self.Stack (Self.Depth).Exhausted
      then
         Reject (Self, Errors.Invalid_State, Error);
         return;
      end if;

      loop
         if Self.Terminal /= No_Pending_Terminal then
            if Self.Owner /= Sequence_Child_Terminal
              or else Self.Owner_Depth /= Self.Depth
            then
               Reject (Self, Errors.Invalid_State, Error);
               return;
            elsif Self.Terminal = Deferred_Invalid_Follower
              or else not Has_Input (Self)
            then
               Reject (Self, Errors.Syntax_Error, Error);
               return;
            elsif Current (Self) = ']' then
               Self.Stack (Self.Depth).Exhausted := True;
               Self.Owner := Sequence_End_Terminal;
               return;
            elsif Is_Whitespace (Current (Self)) then
               Consume_Separator (Self, Current (Self), Error);
               if Error.Code /= Errors.No_Error then
                  return;
               end if;
               Clear_Terminal (Self);
            elsif Current (Self) = ',' then
               Consume_Separator (Self, ',', Error);
               if Error.Code /= Errors.No_Error then
                  return;
               end if;
               Clear_Terminal (Self);
               Commit_Value_Whitespace (Self, Error);
               Admit_Sequence_Child (Self, Available, Error);
               return;
            else
               Reject (Self, Errors.Syntax_Error, Error);
               return;
            end if;
         else
            Commit_Value_Whitespace (Self, Error);
            if Error.Code /= Errors.No_Error then
               return;
            elsif not Has_Input (Self) then
               Reject (Self, Errors.Syntax_Error, Error);
               return;
            elsif Current (Self) = ']' then
               Self.Stack (Self.Depth).Exhausted := True;
               return;
            elsif not Self.Stack (Self.Depth).First_Item then
               Consume_Separator (Self, ',', Error);
               Commit_Value_Whitespace (Self, Error);
            end if;
            Admit_Sequence_Child (Self, Available, Error);
            return;
         end if;
      end loop;
   exception
      when others =>
         Poison_After_Exception (Self);
         Available := False;
         raise;
   end Next_Element;

   overriding
   procedure End_Sequence
     (Self : in out Reader; Error : in out Errors.Error_Info)
   is
      Closing_Root     : Boolean;
      Saw_Document_End : Boolean;
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.Operation /= Active
        or else Self.Depth = 0
        or else Self.Stack (Self.Depth).Kind /= Sequence_Container
        or else Self.Stack (Self.Depth).Child /= No_Child
        or else not Self.Stack (Self.Depth).Exhausted
        or else (Self.Terminal /= No_Pending_Terminal
                 and then (Self.Owner /= Sequence_End_Terminal
                           or else Self.Owner_Depth /= Self.Depth))
      then
         Reject (Self, Errors.Invalid_State, Error);
         return;
      end if;

      if Self.Terminal = No_Pending_Terminal then
         Commit_Value_Whitespace (Self, Error);
      end if;
      if Error.Code /= Errors.No_Error then
         return;
      end if;

      Closing_Root := Self.Depth = 1 and then Self.Root = Root_In_Progress;
      Consume_Structure
        (Self,
         ']',
         Drivers.Array_End,
         Allow_Document_End => Closing_Root,
         Saw_Document_End   => Saw_Document_End,
         Error              => Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;

      Clear_Terminal (Self);
      Self.Stack (Self.Depth) := (others => <>);
      Self.Depth := Self.Depth - 1;
      Budgets.Leave_Container (Self.Budget, Error);
      if Error.Code /= Errors.No_Error then
         Latch (Self, Error);
      else
         Mark_Value_Complete
           (Self, No_Pending_Terminal, Saw_Document_End => Saw_Document_End);
      end if;
   exception
      when others =>
         Poison_After_Exception (Self);
         raise;
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
