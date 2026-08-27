with Flyology_JSON.Numbers.Signed_Integers;
with Flyology_JSON.Numbers.Unsigned_Integers;
with Flyology_Serde.JSON_Preflights;
with Flyology_Serde.UTF_8_Validation;

package body Flyology_Serde.Deserializers.JSON.Event_Readers is
   package Drivers renames Flyology_Serde.JSON_Event_Drivers;
   package Preflights renames Flyology_Serde.JSON_Preflights;

   package Signed_64 is new
     Flyology_JSON.Numbers.Signed_Integers (Interfaces.Integer_64);
   package Unsigned_64 is new
     Flyology_JSON.Numbers.Unsigned_Integers (Interfaces.Unsigned_64);

   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Streams.Stream_Element;
   use type Drivers.Decoded_Form;
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
       and then Item.Decoded_Form = Drivers.No_Decoded
       and then Item.Decoded_Offset = 0
       and then Item.Decoded_Source_Length = 0
       and then Item.Decoded_Length = 0
       and then (for all Value of Item.Decoded => Value = 0)
       and then not Item.Boolean_Payload);

   function Has_Raw_Only_Payload (Item : Drivers.Event_Summary) return Boolean
   is (Item.Has_Raw_Byte
       and then Item.Decoded_Form = Drivers.No_Decoded
       and then Item.Decoded_Offset = 0
       and then Item.Decoded_Source_Length = 0
       and then Item.Decoded_Length = 0
       and then (for all Value of Item.Decoded => Value = 0)
       and then not Item.Boolean_Payload);

   function Valid_Quote
     (Item : Drivers.Event_Summary; Kind : Drivers.Event_Kind) return Boolean
   is (Item.Kind = Kind
       and then Item.Source_Length = 1
       and then Item.Has_Raw_Byte
       and then Item.Raw_Byte
                = Ada.Streams.Stream_Element (Character'Pos ('"'))
       and then Item.Decoded_Form = Drivers.No_Decoded
       and then Item.Decoded_Offset = 0
       and then Item.Decoded_Source_Length = 0
       and then Item.Decoded_Length = 0
       and then (for all Value of Item.Decoded => Value = 0)
       and then not Item.Boolean_Payload);

   function Hex_Value (Item : Character) return Natural is
   begin
      case Item is
         when '0' .. '9' =>
            return Character'Pos (Item) - Character'Pos ('0');

         when 'A' .. 'F' =>
            return Character'Pos (Item) - Character'Pos ('A') + 10;

         when 'a' .. 'f' =>
            return Character'Pos (Item) - Character'Pos ('a') + 10;

         when others     =>
            return 16;
      end case;
   end Hex_Value;

   function Inline_Matches_Source
     (Self        : Reader;
      Token_First : Natural;
      Token_Last  : Natural;
      Item        : Drivers.Event_Summary) return Boolean
   is
      Expected        : Drivers.Scalar_Storage := [others => 0];
      Expected_Length : Natural := 0;
      Code            : Natural := 0;
      Low             : Natural := 0;
      Source_First    : Natural;
      Source_Last     : Natural;

      function Source_Byte (Offset : Natural) return Character
      is (Self.Source (Self.Source'First + Source_First + Offset));

      function Read_Hex (Offset : Natural; Value : out Natural) return Boolean
      is
         Digit : Natural;
      begin
         Value := 0;
         for Index in Offset .. Offset + 3 loop
            Digit := Hex_Value (Source_Byte (Index));
            if Digit = 16 then
               return False;
            end if;
            Value := Value * 16 + Digit;
         end loop;
         return True;
      end Read_Hex;

      procedure Put (Value : Natural) is
      begin
         Expected_Length := Expected_Length + 1;
         Expected
           (Expected'First
            + Ada.Streams.Stream_Element_Offset (Expected_Length - 1)) :=
           Ada.Streams.Stream_Element (Value);
      end Put;

      procedure Encode (Point : Natural) is
      begin
         if Point <= 16#7F# then
            Put (Point);
         elsif Point <= 16#7FF# then
            Put (16#C0# + Point / 64);
            Put (16#80# + Point mod 64);
         elsif Point <= 16#FFFF# then
            Put (16#E0# + Point / 4_096);
            Put (16#80# + Point / 64 mod 64);
            Put (16#80# + Point mod 64);
         else
            Put (16#F0# + Point / 262_144);
            Put (16#80# + Point / 4_096 mod 64);
            Put (16#80# + Point / 64 mod 64);
            Put (16#80# + Point mod 64);
         end if;
      end Encode;
   begin
      if Item.Decoded_Source_Length = 0
        or else Item.Decoded_Offset <= Token_First
        or else Item.Decoded_Offset >= Token_Last - 1
        or else Item.Decoded_Source_Length
                > Token_Last - 1 - Item.Decoded_Offset
        or else Item.Source_Offset > Natural'Last - Item.Source_Length
        or else Item.Decoded_Offset > Natural'Last - Item.Decoded_Source_Length
        or else Item.Decoded_Offset + Item.Decoded_Source_Length
                /= Item.Source_Offset + Item.Source_Length
      then
         return False;
      end if;
      Source_First := Item.Decoded_Offset;
      Source_Last := Source_First + Item.Decoded_Source_Length - 1;

      if Source_Byte (0) /= '\' then
         if (case Character'Pos (Source_Byte (0)) is
               when 16#C2# .. 16#DF# => Item.Decoded_Source_Length /= 2,
               when 16#E0# .. 16#EF# => Item.Decoded_Source_Length /= 3,
               when 16#F0# .. 16#F4# => Item.Decoded_Source_Length /= 4,
               when others           => True)
         then
            return False;
         end if;
         declare
            Valid   : Boolean;
            Invalid : Natural;
         begin
            Flyology_Serde.UTF_8_Validation.Locate
              (Self.Source
                 (Self.Source'First
                  + Source_First
                  .. Self.Source'First + Source_Last),
               Valid,
               Invalid);
            if not Valid then
               return False;
            end if;
         end;
         Expected_Length := Item.Decoded_Source_Length;
         for Offset in 0 .. Expected_Length - 1 loop
            Expected
              (Expected'First + Ada.Streams.Stream_Element_Offset (Offset)) :=
              Ada.Streams.Stream_Element
                (Character'Pos (Source_Byte (Offset)));
         end loop;
      elsif Item.Decoded_Source_Length = 2 then
         case Source_Byte (1) is
            when '"' | '\' | '/' =>
               Code := Character'Pos (Source_Byte (1));

            when 'b'             =>
               Code := 8;

            when 'f'             =>
               Code := 12;

            when 'n'             =>
               Code := 10;

            when 'r'             =>
               Code := 13;

            when 't'             =>
               Code := 9;

            when others          =>
               return False;
         end case;
         Encode (Code);
      elsif Item.Decoded_Source_Length = 6
        and then Source_Byte (1) = 'u'
        and then Read_Hex (2, Code)
        and then Code not in 16#D800# .. 16#DFFF#
      then
         Encode (Code);
      elsif Item.Decoded_Source_Length = 12
        and then Source_Byte (1) = 'u'
        and then Source_Byte (6) = '\'
        and then Source_Byte (7) = 'u'
        and then Read_Hex (2, Code)
        and then Read_Hex (8, Low)
        and then Code in 16#D800# .. 16#DBFF#
        and then Low in 16#DC00# .. 16#DFFF#
      then
         Encode (16#1_0000# + (Code - 16#D800#) * 1_024 + Low - 16#DC00#);
      else
         return False;
      end if;

      return
        Expected_Length = Item.Decoded_Length
        and then (for all Offset in 0 .. Expected_Length - 1 =>
                    Expected
                      (Expected'First
                       + Ada.Streams.Stream_Element_Offset (Offset))
                    = Item.Decoded
                        (Item.Decoded'First
                         + Ada.Streams.Stream_Element_Offset (Offset)));
   end Inline_Matches_Source;

   function Valid_Text_Fragment
     (Self        : Reader;
      Token_First : Natural;
      Token_Last  : Natural;
      Item        : Drivers.Event_Summary;
      Kind        : Drivers.Event_Kind) return Boolean
   is
      Source_Last : Natural;
   begin
      if Item.Kind /= Kind
        or else Item.Boolean_Payload
        or else Item.Source_Length = 0
        or else Item.Source_Offset >= Self.Source'Length
        or else Item.Source_Length > Self.Source'Length - Item.Source_Offset
        or else not Item.Has_Raw_Byte
      then
         return False;
      end if;

      Source_Last := Item.Source_Offset + Item.Source_Length - 1;
      if Item.Raw_Byte
        /= Ada.Streams.Stream_Element
             (Character'Pos (Self.Source (Self.Source'First + Source_Last)))
      then
         return False;
      end if;

      case Item.Decoded_Form is
         when Drivers.No_Decoded     =>
            if Item.Decoded_Offset /= 0
              or else Item.Decoded_Source_Length /= 0
              or else Item.Decoded_Length /= 0
              or else Item.Source_Length /= 1
            then
               return False;
            end if;

         when Drivers.Raw_Decoded    =>
            if Item.Source_Length /= 1
              or else Item.Decoded_Offset /= Item.Source_Offset
              or else Item.Decoded_Source_Length /= Item.Source_Length
              or else Item.Decoded_Length /= 1
              or else Item.Decoded (Item.Decoded'First) /= Item.Raw_Byte
            then
               return False;
            end if;

         when Drivers.Inline_Decoded =>
            if not Inline_Matches_Source (Self, Token_First, Token_Last, Item)
            then
               return False;
            end if;
      end case;

      for Index in Item.Decoded'Range loop
         if Index
           >= Item.Decoded'First
              + Ada.Streams.Stream_Element_Offset (Item.Decoded_Length)
           and then Item.Decoded (Index) /= 0
         then
            return False;
         end if;
      end loop;
      return True;
   end Valid_Text_Fragment;

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
         if Terminal = No_Pending_Terminal then
            Self.Owner := No_Terminal_Owner;
         else
            case Self.Stack (Self.Depth).Kind is
               when Sequence_Container =>
                  Self.Owner := Sequence_Child_Terminal;

               when Record_Container   =>
                  Self.Owner := Record_Child_Terminal;

               when Variant_Container  =>
                  Self.Owner := Variant_Child_Terminal;

               when Optional_Container =>
                  Self.Owner := Optional_Child_Terminal;

               when others             =>
                  raise Program_Error;
            end case;
         end if;
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
      elsif Self.Stack (Self.Depth).Kind = Map_Container then
         if Self.Stack (Self.Depth).Map_Phase
            not in Map_Key_Ready | Map_Value_Ready
         then
            Reject (Self, Errors.Invalid_State, Error);
         end if;
      elsif Self.Stack (Self.Depth).Kind
            not in Optional_Container
                 | Sequence_Container
                 | Record_Container
                 | Variant_Container
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
         elsif Self.Stack (Self.Depth).Kind = Map_Container then
            case Self.Stack (Self.Depth).Map_Phase is
               when Map_Key_Ready   =>
                  Self.Stack (Self.Depth).Map_Phase := Map_Key_In_Progress;

               when Map_Value_Ready =>
                  Self.Stack (Self.Depth).Map_Phase := Map_Value_In_Progress;

               when others          =>
                  raise Program_Error;
            end case;
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
          and then Item.Decoded_Form = Drivers.No_Decoded
          and then Item.Decoded_Offset = 0
          and then Item.Decoded_Source_Length = 0
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
           (Kind             => Sequence_Container,
            Child            => No_Child,
            Map_Phase        => Map_Needs_Entry,
            First_Item       => True,
            Exhausted        => False,
            Optional_Present => False);
      end if;
   end Push_Sequence;

   procedure Push_Map (Self : in out Reader; Error : in out Errors.Error_Info)
   is
   begin
      Budgets.Enter_Container (Self.Budget, Unknown_Length, Error);
      if Error.Code /= Errors.No_Error then
         Latch (Self, Error);
      elsif Self.Depth = Policies.Maximum_Supported_Nesting then
         Reject (Self, Errors.Depth_Exceeded, Error);
      else
         Self.Depth := Self.Depth + 1;
         Self.Stack (Self.Depth) :=
           (Kind             => Map_Container,
            Child            => No_Child,
            Map_Phase        => Map_Needs_Entry,
            First_Item       => True,
            Exhausted        => False,
            Optional_Present => False);
      end if;
   end Push_Map;

   procedure Push_Record
     (Self  : in out Reader;
      Kind  : Container_Kind;
      Error : in out Errors.Error_Info) is
   begin
      if Kind not in Record_Container | Variant_Container then
         raise Program_Error;
      end if;
      Budgets.Enter_Container (Self.Budget, Unknown_Length, Error);
      if Error.Code /= Errors.No_Error then
         Latch (Self, Error);
      elsif Self.Depth = Policies.Maximum_Supported_Nesting then
         Reject (Self, Errors.Depth_Exceeded, Error);
      else
         Self.Depth := Self.Depth + 1;
         Self.Stack (Self.Depth) :=
           (Kind             => Kind,
            Child            => No_Child,
            Map_Phase        => Map_Needs_Entry,
            First_Item       => True,
            Exhausted        => False,
            Optional_Present => False);
      end if;
   end Push_Record;

   procedure Resolve_Local_Separator
     (Self     : in out Reader;
      Terminal : Terminal_State;
      Expected : Character;
      Error    : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif Terminal = Deferred_Invalid_Follower or else not Has_Input (Self)
      then
         Reject (Self, Errors.Syntax_Error, Error);
         return;
      elsif Is_Whitespace (Current (Self)) then
         Consume_Separator (Self, Current (Self), Error);
         Commit_Value_Whitespace (Self, Error);
         if Error.Code /= Errors.No_Error then
            return;
         end if;
      end if;
      Consume_Separator (Self, Expected, Error);
   end Resolve_Local_Separator;

   procedure Push_Optional
     (Self         : in out Reader;
      Present      : Boolean;
      Tag_Terminal : Terminal_State;
      Error        : in out Errors.Error_Info) is
   begin
      Budgets.Enter_Container (Self.Budget, Unknown_Length, Error);
      if Error.Code /= Errors.No_Error then
         Latch (Self, Error);
      elsif Self.Depth = Policies.Maximum_Supported_Nesting then
         Reject (Self, Errors.Depth_Exceeded, Error);
      elsif Present then
         Budgets.Consume_Container_Item (Self.Budget, Error);
         if Error.Code /= Errors.No_Error then
            Latch (Self, Error);
            return;
         end if;
      end if;

      if Error.Code = Errors.No_Error then
         Self.Depth := Self.Depth + 1;
         Self.Stack (Self.Depth) :=
           (Kind             => Optional_Container,
            Child            => (if Present then Child_Ready else No_Child),
            Map_Phase        => Map_Needs_Entry,
            First_Item       => False,
            Exhausted        => True,
            Optional_Present => Present);
         Self.Terminal := Tag_Terminal;
         Self.Owner :=
           (if Tag_Terminal = No_Pending_Terminal
            then No_Terminal_Owner
            else Optional_Tag_Terminal);
         Self.Owner_Depth := Self.Depth;
      end if;
   end Push_Optional;

   procedure Resolve_Map_Child
     (Self : in out Reader; Error : in out Errors.Error_Info)
   is
      Phase            : constant Map_State :=
        Self.Stack (Self.Depth).Map_Phase;
      Expected_Owner   : constant Terminal_Owner :=
        (if Phase = Map_Key_In_Progress
         then Map_Key_Terminal
         else Map_Value_Terminal);
      Saw_Document_End : Boolean;
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.Operation /= Active
        or else Self.Depth = 0
        or else Self.Stack (Self.Depth).Kind /= Map_Container
        or else Phase not in Map_Key_In_Progress | Map_Value_In_Progress
        or else (Self.Terminal /= No_Pending_Terminal
                 and then (Self.Owner /= Expected_Owner
                           or else Self.Owner_Depth /= Self.Depth))
      then
         Reject (Self, Errors.Invalid_State, Error);
         return;
      end if;

      if Self.Terminal /= No_Pending_Terminal then
         if Self.Terminal = Deferred_Invalid_Follower
           or else not Has_Input (Self)
         then
            Reject (Self, Errors.Syntax_Error, Error);
            return;
         elsif Is_Whitespace (Current (Self)) then
            Consume_Separator (Self, Current (Self), Error);
            if Error.Code /= Errors.No_Error then
               return;
            end if;
            Clear_Terminal (Self);
         end if;
      end if;

      Commit_Value_Whitespace (Self, Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;

      if Phase = Map_Key_In_Progress then
         Consume_Separator (Self, ',', Error);
         if Error.Code /= Errors.No_Error then
            return;
         end if;
         Clear_Terminal (Self);
         Commit_Value_Whitespace (Self, Error);
         if Error.Code /= Errors.No_Error then
            return;
         elsif not Has_Input (Self)
           or else not Is_Value_Leading (Current (Self))
         then
            Reject (Self, Errors.Syntax_Error, Error);
         else
            Self.Stack (Self.Depth).Map_Phase := Map_Value_Ready;
         end if;
      else
         Consume_Structure
           (Self,
            ']',
            Drivers.Array_End,
            Allow_Document_End => False,
            Saw_Document_End   => Saw_Document_End,
            Error              => Error);
         if Error.Code /= Errors.No_Error then
            return;
         elsif Saw_Document_End then
            Reject_Transcript (Self, Error);
         else
            Clear_Terminal (Self);
            Self.Stack (Self.Depth).Map_Phase := Map_Needs_Entry;
         end if;
      end if;
   end Resolve_Map_Child;

   procedure Finish_Value
     (Self             : in out Reader;
      Terminal         : Terminal_State;
      Error            : in out Errors.Error_Info;
      Saw_Document_End : Boolean := False) is
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.Depth > 0
        and then Self.Stack (Self.Depth).Kind = Map_Container
      then
         if Saw_Document_End
           or else Self.Stack (Self.Depth).Map_Phase
                   not in Map_Key_In_Progress | Map_Value_In_Progress
         then
            Reject_Transcript (Self, Error);
            return;
         end if;
         Self.Terminal := Terminal;
         Self.Owner :=
           (if Terminal = No_Pending_Terminal
            then No_Terminal_Owner
            elsif Self.Stack (Self.Depth).Map_Phase = Map_Key_In_Progress
            then Map_Key_Terminal
            else Map_Value_Terminal);
         Self.Owner_Depth := Self.Depth;
         Resolve_Map_Child (Self, Error);
      else
         Mark_Value_Complete
           (Self, Terminal, Saw_Document_End => Saw_Document_End);
      end if;
   end Finish_Value;

   procedure Collect_Literal
     (Self            : in out Reader;
      Raw_Length      : Positive;
      Expected        : Drivers.Event_Kind;
      Boolean_Payload : Boolean;
      Terminal        : out Terminal_State;
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
         Selector : Drivers.Token_Terminal;
      begin
         if Expected = Drivers.Null_Value then
            Selector := Drivers.Null_Terminal;
         elsif Expected = Drivers.Boolean_Value then
            Selector := Drivers.Boolean_Terminal;
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
                  Terminal := No_Pending_Terminal;
               end if;
            end if;
         elsif Budgets.Input_Remaining (Self.Budget) = 0 then
            Terminal := Unclassified_Exhausted;
         elsif Is_Number_Delimiter (Current (Self)) then
            Drivers.Observe_Token_End (Self.Syntax, Selector, Summary, Error);
            if Error.Code /= Errors.No_Error then
               Latch (Self, Error);
            else
               Accept_Terminal (Summary);
               if Error.Code = Errors.No_Error then
                  Terminal := Retained_Delimiter;
               end if;
            end if;
         else
            Terminal := Deferred_Invalid_Follower;
         end if;
      end Complete_Literal_End;
   begin
      Terminal := No_Pending_Terminal;
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
         Terminal := No_Pending_Terminal;
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
              or else not Has_Empty_Payload (Summary)
            then
               Reject_Transcript (Self, Error);
            else
               Begun := True;
            end if;

         when Drivers.Number_Fragment =>
            if not Begun
              or else Ended
              or else not Has_Raw_Only_Payload (Summary)
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
              or else not Has_Empty_Payload (Summary)
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
     (Self            : in out Reader;
      Token_First     : Natural;
      Raw_Length      : Positive;
      Terminal        : out Terminal_State;
      Error           : in out Errors.Error_Info;
      Finalize_At_EOF : Boolean := True)
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
      Terminal := No_Pending_Terminal;
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

      if not Has_Input (Self) and then not Finalize_At_EOF then
         Terminal := Deferred_Invalid_Follower;
      elsif not Has_Input (Self) then
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
            Terminal := No_Pending_Terminal;
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
            Terminal := Retained_Delimiter;
         end if;
      else
         Terminal := Deferred_Invalid_Follower;
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
      Terminal : Terminal_State;
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
         Terminal        => Terminal,
         Error           => Error);
      Finish_Value (Self, Terminal, Error);
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
      Terminal : Terminal_State;
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
         Terminal        => Terminal,
         Error           => Error);
      Finish_Value (Self, Terminal, Error);
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
      Parsed    : Interfaces.Integer_64 := 0;
      Terminal  : Terminal_State;
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
      Collect_Number
        (Self, Start, Summary.Raw_Length, Terminal, Error => Error);
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
            Parsed := Result.Value;

         when Signed_64.Invalid_Syntax                      =>
            Reject (Self, Errors.Unexpected_Kind, Error, Start);

         when Signed_64.Below_Range | Signed_64.Above_Range =>
            Reject (Self, Errors.Out_Of_Range, Error, Start);
      end case;
      Finish_Value (Self, Terminal, Error);
      if Error.Code = Errors.No_Error then
         Value := Parsed;
      end if;
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
      Parsed    : Interfaces.Unsigned_64 := 0;
      Terminal  : Terminal_State;
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
      Collect_Number
        (Self, Start, Summary.Raw_Length, Terminal, Error => Error);
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
            Parsed := Result.Value;

         when Unsigned_64.Invalid_Syntax                           =>
            Reject (Self, Errors.Unexpected_Kind, Error, Start);

         when Unsigned_64.Negative_Value | Unsigned_64.Above_Range =>
            Reject (Self, Errors.Out_Of_Range, Error, Start);
      end case;
      Finish_Value (Self, Terminal, Error);
      if Error.Code = Errors.No_Error then
         Value := Parsed;
      end if;
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
      Result    : Data_Model.Float_64_Value := Data_Model.Make_Finite (0.0);
      Terminal  : Terminal_State;
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
      Collect_Number
        (Self, Start, Summary.Raw_Length, Terminal, Error => Error);
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
            Result := Data_Model.Make_Finite (Parsed);
         end if;
      exception
         when Constraint_Error =>
            Reject (Self, Errors.Out_Of_Range, Error, Start);
      end;
      Finish_Value (Self, Terminal, Error);
      if Error.Code = Errors.No_Error then
         Value := Result;
      end if;
   exception
      when others =>
         Poison_After_Exception (Self);
         Value := Data_Model.Make_Finite (0.0);
         raise;
   end Read_Float_64;

   procedure Collect_String
     (Self     : in out Reader;
      Value    : out String;
      Length   : out Natural;
      Terminal : out Terminal_State;
      Error    : in out Errors.Error_Info)
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
           or else not Valid_Quote (Item, Drivers.String_End)
           or else Item.Source_Offset /= Next_Source
           or else Item.Source_Offset /= Token_Last - 1
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
                  Terminal := No_Pending_Terminal;
               end if;
            end if;
         elsif Budgets.Input_Remaining (Self.Budget) = 0 then
            Terminal := Unclassified_Exhausted;
         elsif Is_Number_Delimiter (Current (Self)) then
            Drivers.Observe_Token_End
              (Self.Syntax, Drivers.String_Terminal, Item, Error);
            if Error.Code /= Errors.No_Error then
               Latch (Self, Error);
            else
               Accept_String_End (Item);
               if Error.Code = Errors.No_Error then
                  Terminal := Retained_Delimiter;
               end if;
            end if;
         else
            Terminal := Deferred_Invalid_Follower;
         end if;
      end Complete_String_End;
   begin
      Value := [others => ' '];
      Length := 0;
      Terminal := No_Pending_Terminal;
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

      for Byte_Index in 1 .. Summary.Raw_Length loop
         exit when Error.Code /= Errors.No_Error;
         Consume_Owned_Byte (Self, Events, Count, Error);
         if Error.Code = Errors.No_Error and then Count > 0 then
            for Index in Events'First .. Events'First + Count - 1 loop
               case Events (Index).Kind is
                  when Drivers.String_Begin    =>
                     if Phase /= 0
                       or else not Valid_Quote
                                     (Events (Index), Drivers.String_Begin)
                       or else Events (Index).Source_Offset /= Token_First
                     then
                        Reject_Transcript (Self, Error);
                     else
                        Phase := 1;
                        Next_Source := Token_First + 1;
                     end if;

                  when Drivers.String_Fragment =>
                     if Phase /= 1
                       or else not Valid_Text_Fragment
                                     (Self,
                                      Token_First,
                                      Token_Last,
                                      Events (Index),
                                      Drivers.String_Fragment)
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
         Terminal := No_Pending_Terminal;
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
   end Collect_String;

   overriding
   procedure Read_Text
     (Self   : in out Reader;
      Value  : out String;
      Length : out Natural;
      Error  : in out Errors.Error_Info)
   is
      Terminal : Terminal_State;
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
      Claim_Boundary (Self, Error);
      Collect_String (Self, Value, Length, Terminal, Error);
      Finish_Value (Self, Terminal, Error);
      if Error.Code /= Errors.No_Error then
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
      Error   : in out Errors.Error_Info)
   is
      Candidate        : Boolean := False;
      Start            : Natural := 0;
      Terminal         : Terminal_State := No_Pending_Terminal;
      Saw_Document_End : Boolean;
   begin
      Present := False;
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
         return;
      end if;
      Commit_Value_Whitespace (Self, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif not Has_Input (Self) or else Current (Self) not in '0' | '1' then
         Reject (Self, Errors.Syntax_Error, Error);
         return;
      end if;

      Start := Self.Cursor;
      Candidate := Current (Self) = '1';
      Collect_Number
        (Self, Start, 1, Terminal, Error, Finalize_At_EOF => False);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Candidate then
         Resolve_Local_Separator (Self, Terminal, ',', Error);
         Commit_Value_Whitespace (Self, Error);
         if Error.Code /= Errors.No_Error then
            return;
         elsif not Has_Input (Self)
           or else not Is_Value_Leading (Current (Self))
         then
            Reject (Self, Errors.Syntax_Error, Error);
            return;
         end if;
         Push_Optional
           (Self,
            Present      => True,
            Tag_Terminal => No_Pending_Terminal,
            Error        => Error);
      else
         Push_Optional (Self, False, Terminal, Error);
      end if;
      if Error.Code = Errors.No_Error then
         Present := Candidate;
      end if;
   exception
      when others =>
         Poison_After_Exception (Self);
         Present := False;
         raise;
   end Begin_Optional;

   overriding
   procedure End_Optional
     (Self : in out Reader; Error : in out Errors.Error_Info)
   is
      Closing_Root     : Boolean;
      Saw_Document_End : Boolean;
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.Operation /= Active
        or else Self.Depth = 0
        or else Self.Stack (Self.Depth).Kind /= Optional_Container
        or else Self.Stack (Self.Depth).Child /= No_Child
        or else not Self.Stack (Self.Depth).Exhausted
        or else (if not Self.Stack (Self.Depth).Optional_Present
                 then
                   Self.Terminal = No_Pending_Terminal
                   or else Self.Owner /= Optional_Tag_Terminal
                   or else Self.Owner_Depth /= Self.Depth
                 elsif Self.Terminal = No_Pending_Terminal
                 then Self.Owner /= No_Terminal_Owner
                 else
                   Self.Owner /= Optional_Child_Terminal
                   or else Self.Owner_Depth /= Self.Depth)
      then
         Reject (Self, Errors.Invalid_State, Error);
         return;
      end if;

      if Self.Terminal /= No_Pending_Terminal then
         if Self.Terminal = Deferred_Invalid_Follower
           or else not Has_Input (Self)
         then
            Reject (Self, Errors.Syntax_Error, Error);
            return;
         elsif Is_Whitespace (Current (Self)) then
            Consume_Separator (Self, Current (Self), Error);
            if Error.Code /= Errors.No_Error then
               return;
            end if;
            Clear_Terminal (Self);
            Commit_Value_Whitespace (Self, Error);
         elsif Current (Self) /= ']' then
            Reject (Self, Errors.Syntax_Error, Error);
         end if;
      else
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
         Finish_Value
           (Self,
            No_Pending_Terminal,
            Error,
            Saw_Document_End => Saw_Document_End);
      end if;
   exception
      when others =>
         Poison_After_Exception (Self);
         raise;
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
         Finish_Value
           (Self,
            No_Pending_Terminal,
            Error,
            Saw_Document_End => Saw_Document_End);
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
         Push_Map (Self, Error);
      end if;
   exception
      when others =>
         Poison_After_Exception (Self);
         Length := Unknown_Length;
         raise;
   end Begin_Map;

   overriding
   procedure Next_Map_Entry
     (Self      : in out Reader;
      Available : out Boolean;
      Error     : in out Errors.Error_Info)
   is
      Saw_Document_End : Boolean;
   begin
      Available := False;
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.Operation /= Active
        or else Self.Depth = 0
        or else Self.Stack (Self.Depth).Kind /= Map_Container
        or else Self.Stack (Self.Depth).Map_Phase /= Map_Needs_Entry
        or else Self.Stack (Self.Depth).Child /= No_Child
        or else Self.Stack (Self.Depth).Exhausted
        or else Self.Terminal /= No_Pending_Terminal
      then
         Reject (Self, Errors.Invalid_State, Error);
         return;
      end if;

      Commit_Value_Whitespace (Self, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif not Has_Input (Self) then
         Reject (Self, Errors.Syntax_Error, Error);
         return;
      elsif Current (Self) = ']' then
         Self.Stack (Self.Depth).Exhausted := True;
         return;
      end if;

      if not Self.Stack (Self.Depth).First_Item then
         Consume_Separator (Self, ',', Error);
         Commit_Value_Whitespace (Self, Error);
         if Error.Code /= Errors.No_Error then
            return;
         end if;
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
         return;
      end if;
      Commit_Value_Whitespace (Self, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif not Has_Input (Self) or else not Is_Value_Leading (Current (Self))
      then
         Reject (Self, Errors.Syntax_Error, Error);
         return;
      end if;

      Budgets.Consume_Container_Item (Self.Budget, Error);
      if Error.Code /= Errors.No_Error then
         Latch (Self, Error);
      else
         Self.Stack (Self.Depth).First_Item := False;
         Self.Stack (Self.Depth).Map_Phase := Map_Key_Ready;
         Available := True;
      end if;
   exception
      when others =>
         Poison_After_Exception (Self);
         Available := False;
         raise;
   end Next_Map_Entry;

   overriding
   procedure End_Map (Self : in out Reader; Error : in out Errors.Error_Info)
   is
      Closing_Root     : Boolean;
      Saw_Document_End : Boolean;
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.Operation /= Active
        or else Self.Depth = 0
        or else Self.Stack (Self.Depth).Kind /= Map_Container
        or else Self.Stack (Self.Depth).Map_Phase /= Map_Needs_Entry
        or else Self.Stack (Self.Depth).Child /= No_Child
        or else not Self.Stack (Self.Depth).Exhausted
        or else Self.Terminal /= No_Pending_Terminal
      then
         Reject (Self, Errors.Invalid_State, Error);
         return;
      end if;

      Commit_Value_Whitespace (Self, Error);
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

      Self.Stack (Self.Depth) := (others => <>);
      Self.Depth := Self.Depth - 1;
      Budgets.Leave_Container (Self.Budget, Error);
      if Error.Code /= Errors.No_Error then
         Latch (Self, Error);
      else
         Finish_Value
           (Self,
            No_Pending_Terminal,
            Error,
            Saw_Document_End => Saw_Document_End);
      end if;
   exception
      when others =>
         Poison_After_Exception (Self);
         raise;
   end End_Map;

   procedure Collect_Record_Name
     (Self      : in out Reader;
      Candidate : out String;
      Length    : out Natural;
      Error     : in out Errors.Error_Info)
   is
      Summary     : Preflights.String_Summary;
      Events      :
        Drivers.Event_Summary_Array (1 .. Drivers.Maximum_Event_Summaries);
      Count       : Natural;
      Phase       : Natural range 0 .. 2 := 0;
      Copied      : Natural := 0;
      Token_First : constant Natural := Self.Cursor;
      Token_Last  : Natural := 0;
      Next_Source : Natural := 0;

      procedure Accept_Name_End (Item : Drivers.Event_Summary) is
      begin
         if Phase /= 1
           or else not Valid_Quote (Item, Drivers.Name_End)
           or else Item.Source_Offset /= Next_Source
           or else Item.Source_Offset /= Token_Last - 1
         then
            Reject_Transcript (Self, Error);
         else
            Phase := 2;
         end if;
      end Accept_Name_End;

   begin
      Candidate := [others => ' '];
      Length := 0;
      if Error.Code /= Errors.No_Error then
         return;
      elsif not Has_Input (Self) or else Current (Self) /= '"' then
         Reject (Self, Errors.Syntax_Error, Error);
         return;
      end if;

      Preflights.Scan_String
        (Self.Source.all,
         Self.Cursor,
         Budgets.Input_Remaining (Self.Budget),
         Summary,
         Error);
      if Error.Code /= Errors.No_Error then
         Latch (Self, Error);
         return;
      elsif Summary.Raw_Length > Self.Source'Length - Token_First then
         Reject_Transcript (Self, Error);
         return;
      end if;
      Token_Last := Token_First + Summary.Raw_Length;
      Budgets.Check_Text_Length (Self.Budget, Summary.Decoded_Length, Error);
      if Error.Code = Errors.No_Error
        and then Summary.Decoded_Length > Candidate'Length
      then
         Errors.Fail (Error, Errors.Capacity_Exceeded);
      end if;
      if Error.Code /= Errors.No_Error then
         Latch (Self, Error);
         return;
      end if;

      for Byte_Index in 1 .. Summary.Raw_Length loop
         exit when Error.Code /= Errors.No_Error;
         Consume_Owned_Byte (Self, Events, Count, Error);
         if Error.Code = Errors.No_Error and then Count > 0 then
            for Index in Events'First .. Events'First + Count - 1 loop
               case Events (Index).Kind is
                  when Drivers.Name_Begin    =>
                     if Phase /= 0
                       or else not Valid_Quote
                                     (Events (Index), Drivers.Name_Begin)
                       or else Events (Index).Source_Offset /= Token_First
                     then
                        Reject_Transcript (Self, Error);
                     else
                        Phase := 1;
                        Next_Source := Token_First + 1;
                     end if;

                  when Drivers.Name_Fragment =>
                     if Phase /= 1
                       or else not Valid_Text_Fragment
                                     (Self,
                                      Token_First,
                                      Token_Last,
                                      Events (Index),
                                      Drivers.Name_Fragment)
                       or else Events (Index).Source_Offset /= Next_Source
                       or else Events (Index).Source_Offset <= Token_First
                       or else Events (Index).Source_Offset >= Token_Last - 1
                       or else Events (Index).Source_Length
                               > Token_Last - 1 - Events (Index).Source_Offset
                       or else Copied > Candidate'Length
                       or else Events (Index).Decoded_Length
                               > Candidate'Length - Copied
                     then
                        Reject_Transcript (Self, Error);
                     else
                        if Events (Index).Decoded_Length > 0 then
                           for Fragment_Index in
                             0 .. Events (Index).Decoded_Length - 1
                           loop
                              Candidate
                                (Candidate'First + Copied + Fragment_Index) :=
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

                  when Drivers.Name_End      =>
                     Accept_Name_End (Events (Index));

                  when others                =>
                     Reject_Transcript (Self, Error);
               end case;
               exit when Error.Code /= Errors.No_Error;
            end loop;
         end if;
      end loop;

      if Error.Code = Errors.No_Error and then Copied /= Summary.Decoded_Length
      then
         Reject_Transcript (Self, Error);
      elsif Error.Code = Errors.No_Error and then Phase /= 2 then
         Reject_Transcript (Self, Error);
      end if;
      if Error.Code /= Errors.No_Error then
         Candidate := [others => ' '];
         return;
      end if;

      Commit_Value_Whitespace (Self, Error);
      Consume_Separator (Self, ':', Error);
      Commit_Value_Whitespace (Self, Error);
      if Error.Code /= Errors.No_Error then
         Candidate := [others => ' '];
      elsif not Has_Input (Self) or else not Is_Value_Leading (Current (Self))
      then
         Reject (Self, Errors.Syntax_Error, Error);
         Candidate := [others => ' '];
      else
         Length := Copied;
      end if;
   end Collect_Record_Name;

   procedure Admit_Record_Field
     (Self      : in out Reader;
      Name      : out String;
      Length    : out Natural;
      Available : out Boolean;
      Error     : in out Errors.Error_Info) is
   begin
      Name := [others => ' '];
      Length := 0;
      Available := False;
      Collect_Record_Name (Self, Name, Length, Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Budgets.Consume_Container_Item (Self.Budget, Error);
      if Error.Code /= Errors.No_Error then
         Latch (Self, Error);
         Name := [others => ' '];
         Length := 0;
         return;
      end if;
      Self.Stack (Self.Depth).First_Item := False;
      Self.Stack (Self.Depth).Child := Child_Ready;
      Available := True;
   end Admit_Record_Field;

   overriding
   procedure Begin_Record
     (Self      : in out Reader;
      Type_Name : String;
      Length    : out Data_Model.Length_Information;
      Error     : in out Errors.Error_Info)
   is
      pragma Unreferenced (Type_Name);
      Saw_Document_End : Boolean;
   begin
      Length := Unknown_Length;
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Require_Leading (Self, "{", Error);
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
         '{',
         Drivers.Object_Begin,
         Allow_Document_End => False,
         Saw_Document_End   => Saw_Document_End,
         Error              => Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Saw_Document_End then
         Reject_Transcript (Self, Error);
      else
         Push_Record (Self, Record_Container, Error);
      end if;
   exception
      when others =>
         Poison_After_Exception (Self);
         Length := Unknown_Length;
         raise;
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
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.Operation /= Active
        or else Self.Depth = 0
        or else Self.Stack (Self.Depth).Kind
                not in Record_Container | Variant_Container
        or else Self.Stack (Self.Depth).Child /= No_Child
        or else Self.Stack (Self.Depth).Exhausted
      then
         Reject (Self, Errors.Invalid_State, Error);
         return;
      end if;

      loop
         if Self.Terminal /= No_Pending_Terminal then
            if Self.Owner
              /= (if Self.Stack (Self.Depth).Kind = Record_Container
                  then Record_Child_Terminal
                  else Variant_Child_Terminal)
              or else Self.Owner_Depth /= Self.Depth
            then
               Reject (Self, Errors.Invalid_State, Error);
               return;
            elsif Self.Terminal = Deferred_Invalid_Follower
              or else not Has_Input (Self)
            then
               Reject (Self, Errors.Syntax_Error, Error);
               return;
            elsif Current (Self) = '}' then
               Self.Stack (Self.Depth).Exhausted := True;
               Self.Owner :=
                 (if Self.Stack (Self.Depth).Kind = Record_Container
                  then Record_End_Terminal
                  else Variant_End_Terminal);
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
               Admit_Record_Field (Self, Name, Length, Available, Error);
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
            elsif Current (Self) = '}' then
               Self.Stack (Self.Depth).Exhausted := True;
               return;
            elsif not Self.Stack (Self.Depth).First_Item then
               Consume_Separator (Self, ',', Error);
               Commit_Value_Whitespace (Self, Error);
            end if;
            Admit_Record_Field (Self, Name, Length, Available, Error);
            return;
         end if;
      end loop;
   exception
      when others =>
         Poison_After_Exception (Self);
         Name := [others => ' '];
         Length := 0;
         Available := False;
         raise;
   end Next_Field;

   overriding
   procedure End_Record
     (Self : in out Reader; Error : in out Errors.Error_Info)
   is
      Closing_Root     : Boolean;
      Saw_Document_End : Boolean;
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.Operation /= Active
        or else Self.Depth = 0
        or else Self.Stack (Self.Depth).Kind /= Record_Container
        or else Self.Stack (Self.Depth).Child /= No_Child
        or else not Self.Stack (Self.Depth).Exhausted
        or else (Self.Terminal /= No_Pending_Terminal
                 and then (Self.Owner /= Record_End_Terminal
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
         '}',
         Drivers.Object_End,
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
         Finish_Value
           (Self,
            No_Pending_Terminal,
            Error,
            Saw_Document_End => Saw_Document_End);
      end if;
   exception
      when others =>
         Poison_After_Exception (Self);
         raise;
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
      Read_Text (Self, Literal_Name, Length, Error);
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
      Terminal         : Terminal_State;
      Saw_Document_End : Boolean;
   begin
      Alternative_Name := [others => ' '];
      Name_Length := 0;
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
         return;
      end if;
      Commit_Value_Whitespace (Self, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif not Has_Input (Self) or else Current (Self) /= '"' then
         Reject (Self, Errors.Syntax_Error, Error);
         return;
      end if;
      Collect_String (Self, Alternative_Name, Name_Length, Terminal, Error);
      Resolve_Local_Separator (Self, Terminal, ',', Error);
      Commit_Value_Whitespace (Self, Error);
      if Error.Code /= Errors.No_Error then
         Alternative_Name := [others => ' '];
         Name_Length := 0;
         return;
      elsif not Has_Input (Self) or else Current (Self) /= '{' then
         Reject (Self, Errors.Syntax_Error, Error);
         Alternative_Name := [others => ' '];
         Name_Length := 0;
         return;
      end if;
      Consume_Structure
        (Self,
         '{',
         Drivers.Object_Begin,
         Allow_Document_End => False,
         Saw_Document_End   => Saw_Document_End,
         Error              => Error);
      if Error.Code /= Errors.No_Error then
         Alternative_Name := [others => ' '];
         Name_Length := 0;
         return;
      elsif Saw_Document_End then
         Reject_Transcript (Self, Error);
      else
         Push_Record (Self, Variant_Container, Error);
      end if;
      if Error.Code /= Errors.No_Error then
         Alternative_Name := [others => ' '];
         Name_Length := 0;
      end if;
   exception
      when others =>
         Poison_After_Exception (Self);
         Alternative_Name := [others => ' '];
         Name_Length := 0;
         Length := Unknown_Length;
         raise;
   end Begin_Variant;

   overriding
   procedure End_Variant
     (Self : in out Reader; Error : in out Errors.Error_Info)
   is
      Closing_Root     : Boolean;
      Saw_Document_End : Boolean;
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.Operation /= Active
        or else Self.Depth = 0
        or else Self.Stack (Self.Depth).Kind /= Variant_Container
        or else Self.Stack (Self.Depth).Child /= No_Child
        or else not Self.Stack (Self.Depth).Exhausted
        or else (Self.Terminal /= No_Pending_Terminal
                 and then (Self.Owner /= Variant_End_Terminal
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
      Consume_Structure
        (Self,
         '}',
         Drivers.Object_End,
         Allow_Document_End => False,
         Saw_Document_End   => Saw_Document_End,
         Error              => Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Saw_Document_End then
         Reject_Transcript (Self, Error);
         return;
      end if;

      Clear_Terminal (Self);
      Commit_Value_Whitespace (Self, Error);
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

      Self.Stack (Self.Depth) := (others => <>);
      Self.Depth := Self.Depth - 1;
      Budgets.Leave_Container (Self.Budget, Error);
      if Error.Code /= Errors.No_Error then
         Latch (Self, Error);
      else
         Finish_Value
           (Self,
            No_Pending_Terminal,
            Error,
            Saw_Document_End => Saw_Document_End);
      end if;
   exception
      when others =>
         Poison_After_Exception (Self);
         raise;
   end End_Variant;
end Flyology_Serde.Deserializers.JSON.Event_Readers;
