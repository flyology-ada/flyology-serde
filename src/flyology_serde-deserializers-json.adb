with Flyology_Serde.UTF_8_Validation;

package body Flyology_Serde.Deserializers.JSON is
   use type Ada.Streams.Stream_Element_Offset;
   use type Errors.Error_Code;
   use type Errors.Input_Offset_Unit;
   use type Interfaces.IEEE_Float_64;

   Unknown_Length : constant Data_Model.Length_Information :=
     (Known => False, Length => 0);

   procedure Latch (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error then
         if Error.Offset_Unit = Errors.Unknown_Offset then
            Error.Input_Offset := Self.Cursor;
            Error.Offset_Unit := Errors.Byte_Offset;
         end if;
         while Budgets.Depth (Self.Budget) > 0 loop
            Budgets.Leave_Container (Self.Budget, Error);
         end loop;
         Self.Failed := True;
      end if;
   end Latch;

   procedure Fail
     (Self   : in out Reader;
      Code   : Errors.Error_Code;
      Error  : in out Errors.Error_Info;
      Offset : Natural) is
   begin
      Errors.Fail (Error, Code, Offset, Errors.Byte_Offset);
      Latch (Self, Error);
   end Fail;

   procedure Fail
     (Self  : in out Reader;
      Code  : Errors.Error_Code;
      Error : in out Errors.Error_Info) is
   begin
      Fail (Self, Code, Error, Self.Cursor);
   end Fail;

   function Has_Input (Self : Reader; Ahead : Natural := 0) return Boolean is
   begin
      return Ahead <= Self.Source'Length
        and then Self.Cursor <= Self.Source'Length - Ahead
        and then Self.Cursor + Ahead < Self.Source'Length;
   end Has_Input;

   function Current (Self : Reader; Ahead : Natural := 0) return Character is
   begin
      return Self.Source (Self.Source'First + Self.Cursor + Ahead);
   end Current;

   function Is_Value_Leading (Item : Character) return Boolean is
     (Item in 'n' | 't' | 'f' | '"' | '{' | '[' | '-' | '0' .. '9');

   procedure Advance
     (Self : in out Reader; Count : Natural; Error : in out Errors.Error_Info)
   is
      Remaining : Natural := Count;
   begin
      if Error.Code /= Errors.No_Error or else Self.Failed then
         return;
      elsif Count > Self.Source'Length - Self.Cursor then
         Fail (Self, Errors.Syntax_Error, Error);
         return;
      end if;

      while Remaining > 0 loop
         Budgets.Consume_Input (Self.Budget, 1, Error);
         exit when Error.Code /= Errors.No_Error;
         Self.Cursor := Self.Cursor + 1;
         Remaining := Remaining - 1;
      end loop;
      Latch (Self, Error);
   end Advance;

   procedure Skip_Whitespace
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      while Error.Code = Errors.No_Error
        and then not Self.Failed
        and then Has_Input (Self)
        and then Current (Self) in ' ' | Character'Val (9) | Character'Val (10)
                                      | Character'Val (13)
      loop
         Advance (Self, 1, Error);
      end loop;
   end Skip_Whitespace;

   procedure Expect
     (Self  : in out Reader;
      Value : Character;
      Error : in out Errors.Error_Info) is
   begin
      Skip_Whitespace (Self, Error);
      if Error.Code /= Errors.No_Error or else Self.Failed then
         return;
      elsif not Has_Input (Self) or else Current (Self) /= Value then
         Fail (Self, Errors.Syntax_Error, Error);
      else
         Advance (Self, 1, Error);
      end if;
   end Expect;

   procedure Expect_Literal
     (Self  : in out Reader;
      Value : String;
      Error : in out Errors.Error_Info) is
   begin
      Skip_Whitespace (Self, Error);
      if Error.Code /= Errors.No_Error or else Self.Failed then
         return;
      elsif Value'Length > Self.Source'Length - Self.Cursor then
         Fail (Self, Errors.Syntax_Error, Error);
      else
         for Index in Value'Range loop
            if Current (Self, Index - Value'First) /= Value (Index) then
               Fail
                 (Self,
                  Errors.Syntax_Error,
                  Error,
                  Self.Cursor + Index - Value'First);
               return;
            end if;
         end loop;
         Advance (Self, Value'Length, Error);
      end if;
   end Expect_Literal;

   procedure Require_Ready
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif not Self.Initialized or else Self.Failed then
         Fail (Self, Errors.Invalid_State, Error);
      end if;
   end Require_Ready;

   procedure Check_Value_Ready
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      Require_Ready (Self, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.Depth = 0 then
         if Self.Root /= Root_Ready then
            Fail (Self, Errors.Invalid_State, Error);
         end if;
      else
         case Self.Stack (Self.Depth).Kind is
            when Optional_Container | Sequence_Container | Record_Container
               | Variant_Container =>
               if Self.Stack (Self.Depth).Child /= Child_Ready then
                  Fail (Self, Errors.Invalid_State, Error);
               end if;
            when Map_Container =>
               if Self.Stack (Self.Depth).Map_Phase
                    not in Map_Key_Ready | Map_Value_Ready
               then
                  Fail (Self, Errors.Invalid_State, Error);
               end if;
         end case;
      end if;
   end Check_Value_Ready;

   procedure Prepare_Value
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      Check_Value_Ready (Self, Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;

      Budgets.Consume_Value (Self.Budget, Error);
      if Error.Code /= Errors.No_Error then
         Latch (Self, Error);
         return;
      end if;

      if Self.Depth = 0 then
         Self.Root := Root_In_Progress;
      else
         case Self.Stack (Self.Depth).Kind is
            when Optional_Container | Sequence_Container | Record_Container
               | Variant_Container =>
               Self.Stack (Self.Depth).Child := Child_In_Progress;
            when Map_Container =>
               if Self.Stack (Self.Depth).Map_Phase = Map_Key_Ready then
                  Self.Stack (Self.Depth).Map_Phase := Map_Key_In_Progress;
               else
                  Self.Stack (Self.Depth).Map_Phase := Map_Value_In_Progress;
               end if;
         end case;
      end if;
   end Prepare_Value;

   procedure Require_Leading
     (Self    : in out Reader;
      Allowed : String;
      Error   : in out Errors.Error_Info) is
   begin
      Check_Value_Ready (Self, Error);
      Skip_Whitespace (Self, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif not Has_Input (Self) then
         Fail (Self, Errors.Syntax_Error, Error);
      elsif (for all Item of Allowed => Current (Self) /= Item) then
         Fail (Self, Errors.Unexpected_Kind, Error);
      end if;
   end Require_Leading;

   procedure Require_Child_Start
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      Skip_Whitespace (Self, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif not Has_Input (Self)
        or else not Is_Value_Leading (Current (Self))
      then
         Fail (Self, Errors.Syntax_Error, Error);
      end if;
   end Require_Child_Start;

   procedure Finish_Value
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error or else Self.Failed then
         return;
      elsif Self.Depth = 0 then
         if Self.Root /= Root_In_Progress then
            Fail (Self, Errors.Invalid_State, Error);
         else
            Self.Root := Root_Complete;
         end if;
         return;
      end if;

      case Self.Stack (Self.Depth).Kind is
         when Optional_Container | Sequence_Container | Record_Container
            | Variant_Container =>
            if Self.Stack (Self.Depth).Child /= Child_In_Progress then
               Fail (Self, Errors.Invalid_State, Error);
            else
               Self.Stack (Self.Depth).Child := No_Child;
            end if;
         when Map_Container =>
            case Self.Stack (Self.Depth).Map_Phase is
               when Map_Key_In_Progress =>
                  Expect (Self, ',', Error);
                  if Error.Code = Errors.No_Error then
                     Require_Child_Start (Self, Error);
                     if Error.Code = Errors.No_Error then
                        Self.Stack (Self.Depth).Map_Phase := Map_Value_Ready;
                     end if;
                  end if;
               when Map_Value_In_Progress =>
                  Expect (Self, ']', Error);
                  if Error.Code = Errors.No_Error then
                     Self.Stack (Self.Depth).Map_Phase := Map_Needs_Entry;
                  end if;
               when others =>
                  Fail (Self, Errors.Invalid_State, Error);
            end case;
      end case;
   end Finish_Value;

   procedure Push
     (Self  : in out Reader;
      Kind  : Container_Kind;
      Frame : Container_Frame;
      Error : in out Errors.Error_Info) is
   begin
      Budgets.Enter_Container (Self.Budget, Unknown_Length, Error);
      if Error.Code /= Errors.No_Error then
         Latch (Self, Error);
      elsif Self.Depth = Policies.Maximum_Supported_Nesting then
         Fail (Self, Errors.Depth_Exceeded, Error);
      else
         Self.Depth := Self.Depth + 1;
         Self.Stack (Self.Depth) := Frame;
         Self.Stack (Self.Depth).Kind := Kind;
      end if;
   end Push;

   procedure Pop
     (Self  : in out Reader;
      Kind  : Container_Kind;
      Close : String;
      Error : in out Errors.Error_Info) is
   begin
      Require_Ready (Self, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.Depth = 0
        or else Self.Stack (Self.Depth).Kind /= Kind
        or else Self.Stack (Self.Depth).Child /= No_Child
        or else (Kind = Map_Container
                 and then Self.Stack (Self.Depth).Map_Phase /= Map_Needs_Entry)
        or else not Self.Stack (Self.Depth).Exhausted
      then
         Fail (Self, Errors.Invalid_State, Error);
         return;
      end if;

      for Item of Close loop
         Expect (Self, Item, Error);
         exit when Error.Code /= Errors.No_Error;
      end loop;
      if Error.Code = Errors.No_Error then
         Self.Stack (Self.Depth) := (others => <>);
         Self.Depth := Self.Depth - 1;
         Budgets.Leave_Container (Self.Budget, Error);
         Finish_Value (Self, Error);
      end if;
   end Pop;

   function Hex_Value (Item : Character) return Natural is
   begin
      case Item is
         when '0' .. '9' =>
            return Character'Pos (Item) - Character'Pos ('0');
         when 'A' .. 'F' =>
            return Character'Pos (Item) - Character'Pos ('A') + 10;
         when 'a' .. 'f' =>
            return Character'Pos (Item) - Character'Pos ('a') + 10;
         when others =>
            return 16;
      end case;
   end Hex_Value;

   procedure Scan_String
     (Self           : in out Reader;
      Raw_Length     : out Natural;
      Decoded_Length : out Natural;
      Error          : in out Errors.Error_Info)
   is
      Position      : Natural := Self.Cursor;
      Segment_Start : Natural;
      Code          : Natural;
      Low           : Natural;
      Input_Remaining : constant Natural :=
        Budgets.Input_Remaining (Self.Budget);

      function Has (Count : Natural := 1) return Boolean is
         Inspected : constant Natural := Position - Self.Cursor;
      begin
         if Position < Self.Source'Length
           and then (Inspected >= Input_Remaining
                     or else Count > Input_Remaining - Inspected)
         then
            Fail
              (Self,
               Errors.Capacity_Exceeded,
               Error,
               Self.Cursor + Input_Remaining);
            return False;
         end if;
         return Position <= Self.Source'Length
           and then Count <= Self.Source'Length - Position;
      end Has;

      function Item (Ahead : Natural := 0) return Character is
      begin
         return Self.Source (Self.Source'First + Position + Ahead);
      end Item;

      procedure Scan_Hex (Value : out Natural) is
         Digit : Natural;
      begin
         Value := 0;
         if not Has (4) then
            Fail (Self, Errors.Syntax_Error, Error, Position);
            return;
         end if;
         for Offset in 0 .. 3 loop
            Digit := Hex_Value (Item (Offset));
            if Digit = 16 then
               Fail
                 (Self, Errors.Syntax_Error, Error, Position + Offset);
               return;
            end if;
            Value := Value * 16 + Digit;
         end loop;
         Position := Position + 4;
      end Scan_Hex;

      procedure Add_Decoded (Count : Natural) is
      begin
         if Decoded_Length > Natural'Last - Count then
            Fail (Self, Errors.Capacity_Exceeded, Error, Position);
         else
            Decoded_Length := Decoded_Length + Count;
         end if;
      end Add_Decoded;

      procedure Validate_Segment (Last : Natural) is
         Valid   : Boolean;
         Invalid : Natural;
      begin
         if Last > Segment_Start then
            Flyology_Serde.UTF_8_Validation.Locate
              (Self.Source
                 (Self.Source'First + Segment_Start
                  .. Self.Source'First + Last - 1),
               Valid,
               Invalid);
         else
            Valid := True;
            Invalid := 0;
         end if;
         if not Valid then
            Fail
              (Self,
               Errors.Invalid_Text,
               Error,
               Segment_Start + Invalid);
         end if;
      end Validate_Segment;
   begin
      Raw_Length := 0;
      Decoded_Length := 0;
      if not Has or else Item /= '"' then
         Fail (Self, Errors.Syntax_Error, Error, Position);
         return;
      end if;
      Position := Position + 1;
      Segment_Start := Position;

      while Error.Code = Errors.No_Error loop
         if not Has then
            Fail (Self, Errors.Syntax_Error, Error, Position);
            exit;
         end if;
         case Item is
            when '"' =>
               Validate_Segment (Position);
               exit when Error.Code /= Errors.No_Error;
               Position := Position + 1;
               Raw_Length := Position - Self.Cursor;
               return;
            when Character'Val (0) .. Character'Val (31) =>
               Fail (Self, Errors.Syntax_Error, Error, Position);
            when '\' =>
               Validate_Segment (Position);
               exit when Error.Code /= Errors.No_Error;
               Position := Position + 1;
               if not Has then
                  Fail (Self, Errors.Syntax_Error, Error, Position);
                  exit;
               end if;
               case Item is
                  when '"' | '\' | '/' | 'b' | 'f' | 'n' | 'r' | 't' =>
                     Add_Decoded (1);
                     Position := Position + 1;
                  when 'u' =>
                     Position := Position + 1;
                     Scan_Hex (Code);
                     exit when Error.Code /= Errors.No_Error;
                     if Code in 16#D800# .. 16#DBFF# then
                        if not Has (2) or else Item /= '\' or else Item (1) /= 'u' then
                           Fail (Self, Errors.Invalid_Text, Error, Position);
                           exit;
                        end if;
                        Position := Position + 2;
                        Scan_Hex (Low);
                        exit when Error.Code /= Errors.No_Error;
                        if Low not in 16#DC00# .. 16#DFFF# then
                           Fail (Self, Errors.Invalid_Text, Error, Position - 4);
                           exit;
                        end if;
                        Add_Decoded (4);
                     elsif Code in 16#DC00# .. 16#DFFF# then
                        Fail (Self, Errors.Invalid_Text, Error, Position - 4);
                     elsif Code <= 16#7F# then
                        Add_Decoded (1);
                     elsif Code <= 16#7FF# then
                        Add_Decoded (2);
                     else
                        Add_Decoded (3);
                     end if;
                  when others =>
                     Fail (Self, Errors.Syntax_Error, Error, Position);
               end case;
               Segment_Start := Position;
            when others =>
               Add_Decoded (1);
               Position := Position + 1;
         end case;
      end loop;
   end Scan_String;

   procedure Decode_String
     (Self   : in out Reader;
      Value  : out String;
      Length : out Natural;
      Check_Length : Boolean;
      Error  : in out Errors.Error_Info)
   is
      Raw_Length     : Natural;
      Decoded_Length : Natural;
      Code           : Natural;
      Low            : Natural;
      Output         : Natural := 0;

      procedure Put (Item : Character) is
      begin
         if Error.Code /= Errors.No_Error then
            return;
         elsif Output = Value'Length then
            Fail (Self, Errors.Capacity_Exceeded, Error);
         else
            Output := Output + 1;
            Value (Value'First + Output - 1) := Item;
         end if;
      end Put;

      procedure Read_Hex (Result : out Natural) is
      begin
         Result := 0;
         for Offset in 1 .. 4 loop
            exit when Error.Code /= Errors.No_Error;
            Result := Result * 16 + Hex_Value (Current (Self));
            Advance (Self, 1, Error);
         end loop;
      end Read_Hex;

      procedure Put_Code_Point (Point : Natural) is
      begin
         if Point <= 16#7F# then
            Put (Character'Val (Point));
         elsif Point <= 16#7FF# then
            Put (Character'Val (16#C0# + Point / 64));
            if Error.Code /= Errors.No_Error then
               return;
            end if;
            Put (Character'Val (16#80# + Point mod 64));
         elsif Point <= 16#FFFF# then
            Put (Character'Val (16#E0# + Point / 4_096));
            if Error.Code /= Errors.No_Error then
               return;
            end if;
            Put (Character'Val (16#80# + Point / 64 mod 64));
            if Error.Code /= Errors.No_Error then
               return;
            end if;
            Put (Character'Val (16#80# + Point mod 64));
         else
            Put (Character'Val (16#F0# + Point / 262_144));
            if Error.Code /= Errors.No_Error then
               return;
            end if;
            Put (Character'Val (16#80# + Point / 4_096 mod 64));
            if Error.Code /= Errors.No_Error then
               return;
            end if;
            Put (Character'Val (16#80# + Point / 64 mod 64));
            if Error.Code /= Errors.No_Error then
               return;
            end if;
            Put (Character'Val (16#80# + Point mod 64));
         end if;
      end Put_Code_Point;
   begin
      Value := [others => ' '];
      Length := 0;
      Skip_Whitespace (Self, Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Scan_String (Self, Raw_Length, Decoded_Length, Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      if Check_Length then
         Budgets.Check_Text_Length (Self.Budget, Decoded_Length, Error);
      end if;
      if Error.Code = Errors.No_Error and then Decoded_Length > Value'Length then
         Errors.Fail (Error, Errors.Capacity_Exceeded);
      end if;
      Latch (Self, Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;

      Advance (Self, 1, Error);
      while Error.Code = Errors.No_Error and then Current (Self) /= '"' loop
         if Current (Self) /= '\' then
            Put (Current (Self));
            Advance (Self, 1, Error);
         else
            Advance (Self, 1, Error);
            exit when Error.Code /= Errors.No_Error;
            case Current (Self) is
               when '"' | '\' | '/' =>
                  Put (Current (Self));
                  Advance (Self, 1, Error);
               when 'b' => Put (Character'Val (8)); Advance (Self, 1, Error);
               when 'f' => Put (Character'Val (12)); Advance (Self, 1, Error);
               when 'n' => Put (Character'Val (10)); Advance (Self, 1, Error);
               when 'r' => Put (Character'Val (13)); Advance (Self, 1, Error);
               when 't' => Put (Character'Val (9)); Advance (Self, 1, Error);
               when 'u' =>
                  Advance (Self, 1, Error);
                  exit when Error.Code /= Errors.No_Error;
                  Read_Hex (Code);
                  exit when Error.Code /= Errors.No_Error;
                  if Code in 16#D800# .. 16#DBFF# then
                     Advance (Self, 2, Error);
                     exit when Error.Code /= Errors.No_Error;
                     Read_Hex (Low);
                     exit when Error.Code /= Errors.No_Error;
                     Code := 16#1_0000# + (Code - 16#D800#) * 1_024
                       + Low - 16#DC00#;
                  end if;
                  Put_Code_Point (Code);
               when others =>
                  Fail (Self, Errors.Syntax_Error, Error);
            end case;
         end if;
      end loop;
      if Error.Code = Errors.No_Error then
         Advance (Self, 1, Error);
         Length := Output;
      end if;
   end Decode_String;

   procedure Scan_Number
     (Self       : in out Reader;
      Raw_Length : out Natural;
      Is_Integer : out Boolean;
      Negative   : out Boolean;
      Error      : in out Errors.Error_Info)
   is
      Position : Natural := Self.Cursor;
      Start    : constant Natural := Self.Cursor;
      Input_Remaining : constant Natural :=
        Budgets.Input_Remaining (Self.Budget);

      function Has return Boolean is
      begin
         if Position < Self.Source'Length
           and then Position - Start >= Input_Remaining
         then
            Fail
              (Self,
               Errors.Capacity_Exceeded,
               Error,
               Start + Input_Remaining);
            return False;
         end if;
         return Position < Self.Source'Length;
      end Has;
      function Item return Character is
        (Self.Source (Self.Source'First + Position));

      procedure Scan_Digits is
      begin
         if not Has or else Item not in '0' .. '9' then
            Fail (Self, Errors.Syntax_Error, Error, Position);
            return;
         end if;
         while Has and then Item in '0' .. '9' loop
            Position := Position + 1;
         end loop;
      end Scan_Digits;
   begin
      Raw_Length := 0;
      Is_Integer := True;
      Negative := False;
      if Has and then Item = '-' then
         Negative := True;
         Position := Position + 1;
      end if;
      if not Has then
         Fail (Self, Errors.Syntax_Error, Error, Position);
         return;
      elsif Item = '0' then
         Position := Position + 1;
         if Has and then Item in '0' .. '9' then
            Fail (Self, Errors.Syntax_Error, Error, Position);
            return;
         end if;
      elsif Item in '1' .. '9' then
         Scan_Digits;
      else
         Fail (Self, Errors.Syntax_Error, Error, Position);
         return;
      end if;
      if Has and then Item = '.' then
         Is_Integer := False;
         Position := Position + 1;
         Scan_Digits;
      end if;
      if Error.Code = Errors.No_Error and then Has and then Item in 'e' | 'E' then
         Is_Integer := False;
         Position := Position + 1;
         if Has and then Item in '+' | '-' then
            Position := Position + 1;
         end if;
         Scan_Digits;
      end if;
      if Error.Code = Errors.No_Error then
         Raw_Length := Position - Start;
      end if;
   end Scan_Number;

   procedure Read_Number_Text
     (Self       : in out Reader;
      Buffer     : out String;
      Length     : out Natural;
      Is_Integer : out Boolean;
      Negative   : out Boolean;
      Error      : in out Errors.Error_Info) is
   begin
      Buffer := [others => ' '];
      Skip_Whitespace (Self, Error);
      Scan_Number (Self, Length, Is_Integer, Negative, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Length > Buffer'Length then
         Fail (Self, Errors.Out_Of_Range, Error);
      else
         Buffer (Buffer'First .. Buffer'First + Length - 1) :=
           Self.Source
             (Self.Source'First + Self.Cursor
              .. Self.Source'First + Self.Cursor + Length - 1);
         Advance (Self, Length, Error);
      end if;
   end Read_Number_Text;

   procedure Initialize
     (Self   : in out Reader;
      Policy : Policies.Decode_Policy := (others => <>)) is
   begin
      Self.Policy := Policy;
      Budgets.Initialize (Self.Budget, Policy.Limits);
      Self.Stack := [others => <>];
      Self.Depth := 0;
      Self.Cursor := 0;
      Self.Root := Root_Ready;
      Self.Initialized := True;
      Self.Failed := False;
      Self.Document_Complete := False;
   end Initialize;

   procedure Reset
     (Self   : in out Reader;
      Policy : Policies.Decode_Policy := (others => <>)) is
   begin
      Initialize (Self, Policy);
   end Reset;

   procedure Finish_Document
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      Require_Ready (Self, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.Root /= Root_Complete or else Self.Depth /= 0 then
         Fail (Self, Errors.Invalid_State, Error);
         return;
      end if;
      Skip_Whitespace (Self, Error);
      if Error.Code = Errors.No_Error and then Has_Input (Self) then
         Fail (Self, Errors.Syntax_Error, Error);
      elsif Error.Code = Errors.No_Error then
         Self.Document_Complete := True;
      end if;
   end Finish_Document;

   function Is_Complete (Self : Reader) return Boolean is
     (Self.Document_Complete and then not Self.Failed);

   function Input_Offset (Self : Reader) return Natural is (Self.Cursor);

   overriding
   function Capabilities
     (Self : Reader) return Data_Model.Format_Capabilities is
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
      return Data_Model.Value_Kind is
      Raw_Length : Natural;
      Is_Integer : Boolean;
      Negative   : Boolean;
   begin
      Check_Value_Ready (Self, Error);
      Skip_Whitespace (Self, Error);
      if Error.Code /= Errors.No_Error or else not Has_Input (Self) then
         if Error.Code = Errors.No_Error then
            Fail (Self, Errors.Syntax_Error, Error);
         end if;
         return Data_Model.Null_Value;
      end if;
      case Current (Self) is
         when 'n'       => return Data_Model.Null_Value;
         when 't' | 'f' => return Data_Model.Boolean_Value;
         when '-' | '0' .. '9' =>
            Scan_Number
              (Self, Raw_Length, Is_Integer, Negative, Error);
            if Error.Code /= Errors.No_Error then
               return Data_Model.Null_Value;
            elsif not Is_Integer then
               return Data_Model.Float_Value;
            elsif Negative then
               return Data_Model.Signed_Integer_Value;
            else
               return Data_Model.Unsigned_Integer_Value;
            end if;
         when '"'       => return Data_Model.Text_Value;
         when '['       => return Data_Model.Sequence_Value;
         when '{'       => return Data_Model.Record_Value;
         when others    =>
            Fail (Self, Errors.Syntax_Error, Error);
            return Data_Model.Null_Value;
      end case;
   end Peek_Kind;

   overriding
   procedure Read_Null
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      Require_Leading (Self, "n", Error);
      Prepare_Value (Self, Error);
      Expect_Literal (Self, "null", Error);
      Finish_Value (Self, Error);
   end Read_Null;

   overriding
   procedure Read_Boolean
     (Self  : in out Reader;
      Value : out Boolean;
      Error : in out Errors.Error_Info) is
   begin
      Value := False;
      Require_Leading (Self, "tf", Error);
      Prepare_Value (Self, Error);
      Skip_Whitespace (Self, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Has_Input (Self) and then Current (Self) = 't' then
         Expect_Literal (Self, "true", Error);
         Value := True;
      else
         Expect_Literal (Self, "false", Error);
      end if;
      Finish_Value (Self, Error);
   end Read_Boolean;

   overriding
   procedure Read_Signed
     (Self  : in out Reader;
      Value : out Interfaces.Integer_64;
      Error : in out Errors.Error_Info)
   is
      Buffer     : String (1 .. 32);
      Length     : Natural;
      Is_Integer : Boolean;
      Negative   : Boolean;
   begin
      Value := 0;
      Require_Leading (Self, "-0123456789", Error);
      Prepare_Value (Self, Error);
      Read_Number_Text (Self, Buffer, Length, Is_Integer, Negative, Error);
      if Error.Code = Errors.No_Error and then not Is_Integer then
         Fail (Self, Errors.Unexpected_Kind, Error, Self.Cursor - Length);
      elsif Error.Code = Errors.No_Error then
         begin
            Value := Interfaces.Integer_64'Value (Buffer (1 .. Length));
         exception
            when Constraint_Error =>
               Fail (Self, Errors.Out_Of_Range, Error, Self.Cursor - Length);
         end;
      end if;
      Finish_Value (Self, Error);
   end Read_Signed;

   overriding
   procedure Read_Unsigned
     (Self  : in out Reader;
      Value : out Interfaces.Unsigned_64;
      Error : in out Errors.Error_Info)
   is
      Buffer     : String (1 .. 32);
      Length     : Natural;
      Is_Integer : Boolean;
      Negative   : Boolean;
   begin
      Value := 0;
      Require_Leading (Self, "-0123456789", Error);
      Prepare_Value (Self, Error);
      Read_Number_Text (Self, Buffer, Length, Is_Integer, Negative, Error);
      if Error.Code = Errors.No_Error and then not Is_Integer then
         Fail (Self, Errors.Unexpected_Kind, Error, Self.Cursor - Length);
      elsif Error.Code = Errors.No_Error and then Negative then
         Fail (Self, Errors.Out_Of_Range, Error, Self.Cursor - Length);
      elsif Error.Code = Errors.No_Error then
         begin
            Value := Interfaces.Unsigned_64'Value (Buffer (1 .. Length));
         exception
            when Constraint_Error =>
               Fail (Self, Errors.Out_Of_Range, Error, Self.Cursor - Length);
         end;
      end if;
      Finish_Value (Self, Error);
   end Read_Unsigned;

   overriding
   procedure Read_Float_64
     (Self  : in out Reader;
      Value : out Interfaces.IEEE_Float_64;
      Error : in out Errors.Error_Info)
   is
      Buffer     : String (1 .. 768);
      Length     : Natural;
      Is_Integer : Boolean;
      Negative   : Boolean;
   begin
      Value := 0.0;
      Require_Leading (Self, "-0123456789", Error);
      Prepare_Value (Self, Error);
      Read_Number_Text (Self, Buffer, Length, Is_Integer, Negative, Error);
      if Error.Code = Errors.No_Error then
         begin
            Value := Interfaces.IEEE_Float_64'Value (Buffer (1 .. Length));
            if Value /= Value
              or else Value < Interfaces.IEEE_Float_64'First
              or else Value > Interfaces.IEEE_Float_64'Last
            then
               Fail (Self, Errors.Out_Of_Range, Error, Self.Cursor - Length);
            end if;
         exception
            when Constraint_Error =>
               Fail (Self, Errors.Out_Of_Range, Error, Self.Cursor - Length);
         end;
      end if;
      Finish_Value (Self, Error);
   end Read_Float_64;

   overriding
   procedure Read_Text
     (Self   : in out Reader;
      Value  : out String;
      Length : out Natural;
      Error  : in out Errors.Error_Info) is
   begin
      Require_Leading (Self, """", Error);
      Prepare_Value (Self, Error);
      Decode_String (Self, Value, Length, True, Error);
      Finish_Value (Self, Error);
   end Read_Text;

   overriding
   procedure Read_Bytes
     (Self   : in out Reader;
      Value  : out Ada.Streams.Stream_Element_Array;
      Length : out Natural;
      Error  : in out Errors.Error_Info)
   is
      Position : Natural;
      Count    : Natural := 0;
      Tag      : String (1 .. 6);
      Tag_Length : Natural;
      Input_Remaining : Natural;
   begin
      Value := [others => 0];
      Length := 0;
      Require_Leading (Self, "{", Error);
      Prepare_Value (Self, Error);
      Expect (Self, '{', Error);
      Decode_String (Self, Tag, Tag_Length, False, Error);
      if Error.Code = Errors.No_Error
        and then (Tag_Length /= 6 or else Tag /= "$bytes")
      then
         Fail (Self, Errors.Unexpected_Kind, Error);
      end if;
      Expect (Self, ':', Error);
      Expect (Self, '"', Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Position := Self.Cursor;
      Input_Remaining := Budgets.Input_Remaining (Self.Budget);
      while Position < Self.Source'Length loop
         if Position - Self.Cursor >= Input_Remaining then
            Fail
              (Self,
               Errors.Capacity_Exceeded,
               Error,
               Self.Cursor + Input_Remaining);
            return;
         elsif Self.Source (Self.Source'First + Position) = '"' then
            exit;
         end if;
         if Hex_Value (Self.Source (Self.Source'First + Position)) = 16 then
            Fail (Self, Errors.Syntax_Error, Error, Position);
            return;
         end if;
         Count := Count + 1;
         Position := Position + 1;
      end loop;
      if Position = Self.Source'Length or else Count mod 2 /= 0 then
         Fail (Self, Errors.Syntax_Error, Error, Position);
         return;
      end if;
      Count := Count / 2;
      Budgets.Check_Byte_Length (Self.Budget, Count, Error);
      if Error.Code = Errors.No_Error and then Count > Value'Length then
         Errors.Fail (Error, Errors.Capacity_Exceeded);
      end if;
      Latch (Self, Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      for Index in 1 .. Count loop
         Value (Value'First + Ada.Streams.Stream_Element_Offset (Index - 1)) :=
           Ada.Streams.Stream_Element
             (Hex_Value (Current (Self)) * 16
              + Hex_Value (Current (Self, 1)));
         Advance (Self, 2, Error);
      end loop;
      Expect (Self, '"', Error);
      Expect (Self, '}', Error);
      if Error.Code = Errors.No_Error then
         Length := Count;
      end if;
      Finish_Value (Self, Error);
   end Read_Bytes;

   procedure Skip_Raw
     (Self         : in out Reader;
      Syntax_Depth : Natural;
      Error        : in out Errors.Error_Info);

   procedure Skip_Raw_String
     (Self : in out Reader; Error : in out Errors.Error_Info)
   is
      Raw_Length     : Natural;
      Decoded_Length : Natural;
   begin
      Scan_String (Self, Raw_Length, Decoded_Length, Error);
      Budgets.Check_Text_Length (Self.Budget, Decoded_Length, Error);
      Latch (Self, Error);
      Advance (Self, Raw_Length, Error);
   end Skip_Raw_String;

   procedure Skip_Raw
     (Self         : in out Reader;
      Syntax_Depth : Natural;
      Error        : in out Errors.Error_Info)
   is
      Raw_Length : Natural;
      Integerish : Boolean;
      Negative   : Boolean;
      First      : Boolean;
      Items      : Natural;
   begin
      Skip_Whitespace (Self, Error);
      if Error.Code /= Errors.No_Error or else not Has_Input (Self) then
         if Error.Code = Errors.No_Error then
            Fail (Self, Errors.Syntax_Error, Error);
         end if;
         return;
      end if;
      case Current (Self) is
         when 'n' => Expect_Literal (Self, "null", Error);
         when 't' => Expect_Literal (Self, "true", Error);
         when 'f' => Expect_Literal (Self, "false", Error);
         when '"' => Skip_Raw_String (Self, Error);
         when '-' | '0' .. '9' =>
            Scan_Number (Self, Raw_Length, Integerish, Negative, Error);
            Advance (Self, Raw_Length, Error);
         when '[' | '{' =>
            if Syntax_Depth = Natural (Self.Policy.Limits.Maximum_Nesting_Depth) then
               Fail (Self, Errors.Depth_Exceeded, Error);
               return;
            end if;
            declare
               Open  : constant Character := Current (Self);
               Close : constant Character := (if Open = '[' then ']' else '}');
            begin
               Advance (Self, 1, Error);
               First := True;
               Items := 0;
               loop
                  Skip_Whitespace (Self, Error);
                  exit when Error.Code /= Errors.No_Error;
                  if Has_Input (Self) and then Current (Self) = Close then
                     Advance (Self, 1, Error);
                     exit;
                  end if;
                  if not First then
                     Expect (Self, ',', Error);
                  end if;
                  if Items = Self.Policy.Limits.Maximum_Container_Items then
                     Fail (Self, Errors.Capacity_Exceeded, Error);
                     exit;
                  end if;
                  Items := Items + 1;
                  if Open = '{' then
                     Skip_Raw_String (Self, Error);
                     Expect (Self, ':', Error);
                  end if;
                  Skip_Raw (Self, Syntax_Depth + 1, Error);
                  First := False;
               end loop;
            end;
         when others =>
            Fail (Self, Errors.Syntax_Error, Error);
      end case;
   end Skip_Raw;

   overriding
   procedure Skip_Value
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      Prepare_Value (Self, Error);
      Skip_Raw (Self, 0, Error);
      Finish_Value (Self, Error);
   end Skip_Value;

   overriding
   procedure Begin_Optional
     (Self    : in out Reader;
      Present : out Boolean;
      Error   : in out Errors.Error_Info) is
   begin
      Present := False;
      Require_Leading (Self, "[", Error);
      Prepare_Value (Self, Error);
      Expect (Self, '[', Error);
      Skip_Whitespace (Self, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif not Has_Input (Self) or else Current (Self) not in '0' | '1' then
         Fail (Self, Errors.Syntax_Error, Error);
         return;
      end if;
      Present := Current (Self) = '1';
      Advance (Self, 1, Error);
      if Present then
         Expect (Self, ',', Error);
         Require_Child_Start (Self, Error);
      end if;
      Push
        (Self,
         Optional_Container,
         (Kind       => Optional_Container,
          Child      => (if Present then Child_Ready else No_Child),
          Map_Phase  => <>,
          First_Item => False,
          Exhausted  => True),
         Error);
      if Error.Code = Errors.No_Error and then Present then
         Budgets.Consume_Container_Item (Self.Budget, Error);
         Latch (Self, Error);
      end if;
   end Begin_Optional;

   overriding
   procedure End_Optional
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      Pop (Self, Optional_Container, "]", Error);
   end End_Optional;

   overriding
   procedure Begin_Sequence
     (Self   : in out Reader;
      Length : out Data_Model.Length_Information;
      Error  : in out Errors.Error_Info) is
   begin
      Length := Unknown_Length;
      Require_Leading (Self, "[", Error);
      Prepare_Value (Self, Error);
      Expect (Self, '[', Error);
      Push (Self, Sequence_Container, (others => <>), Error);
   end Begin_Sequence;

   overriding
   procedure Next_Element
     (Self      : in out Reader;
      Available : out Boolean;
      Error     : in out Errors.Error_Info) is
   begin
      Available := False;
      Require_Ready (Self, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.Depth = 0
        or else Self.Stack (Self.Depth).Kind /= Sequence_Container
        or else Self.Stack (Self.Depth).Child /= No_Child
        or else Self.Stack (Self.Depth).Exhausted
      then
         Fail (Self, Errors.Invalid_State, Error);
         return;
      end if;
      Skip_Whitespace (Self, Error);
      if not Has_Input (Self) then
         Fail (Self, Errors.Syntax_Error, Error);
         return;
      elsif Current (Self) = ']' then
         Self.Stack (Self.Depth).Exhausted := True;
         return;
      end if;
      if not Self.Stack (Self.Depth).First_Item then
         Expect (Self, ',', Error);
      end if;
      Require_Child_Start (Self, Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Budgets.Consume_Container_Item (Self.Budget, Error);
      Latch (Self, Error);
      if Error.Code = Errors.No_Error then
         Self.Stack (Self.Depth).First_Item := False;
         Self.Stack (Self.Depth).Child := Child_Ready;
         Available := True;
      end if;
   end Next_Element;

   overriding
   procedure End_Sequence
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      Pop (Self, Sequence_Container, "]", Error);
   end End_Sequence;

   overriding
   procedure Begin_Map
     (Self   : in out Reader;
      Length : out Data_Model.Length_Information;
      Error  : in out Errors.Error_Info) is
   begin
      Length := Unknown_Length;
      Require_Leading (Self, "[", Error);
      Prepare_Value (Self, Error);
      Expect (Self, '[', Error);
      Push
        (Self,
         Map_Container,
         (Kind => Map_Container, others => <>),
         Error);
   end Begin_Map;

   overriding
   procedure Next_Map_Entry
     (Self      : in out Reader;
      Available : out Boolean;
      Error     : in out Errors.Error_Info) is
   begin
      Available := False;
      Require_Ready (Self, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.Depth = 0
        or else Self.Stack (Self.Depth).Kind /= Map_Container
        or else Self.Stack (Self.Depth).Map_Phase /= Map_Needs_Entry
        or else Self.Stack (Self.Depth).Exhausted
      then
         Fail (Self, Errors.Invalid_State, Error);
         return;
      end if;
      Skip_Whitespace (Self, Error);
      if Has_Input (Self) and then Current (Self) = ']' then
         Self.Stack (Self.Depth).Exhausted := True;
         return;
      end if;
      if not Self.Stack (Self.Depth).First_Item then
         Expect (Self, ',', Error);
      end if;
      Expect (Self, '[', Error);
      Require_Child_Start (Self, Error);
      Budgets.Consume_Container_Item (Self.Budget, Error);
      Latch (Self, Error);
      if Error.Code = Errors.No_Error then
         Self.Stack (Self.Depth).First_Item := False;
         Self.Stack (Self.Depth).Map_Phase := Map_Key_Ready;
         Available := True;
      end if;
   end Next_Map_Entry;

   overriding
   procedure End_Map
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      Pop (Self, Map_Container, "]", Error);
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
      Require_Leading (Self, "{", Error);
      Prepare_Value (Self, Error);
      Expect (Self, '{', Error);
      Push (Self, Record_Container, (others => <>), Error);
   end Begin_Record;

   procedure Next_Record_Field
     (Self      : in out Reader;
      Kind      : Container_Kind;
      Name      : out String;
      Length    : out Natural;
      Available : out Boolean;
      Error     : in out Errors.Error_Info) is
   begin
      Name := [others => ' '];
      Length := 0;
      Available := False;
      Require_Ready (Self, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.Depth = 0
        or else Self.Stack (Self.Depth).Kind /= Kind
        or else Self.Stack (Self.Depth).Child /= No_Child
        or else Self.Stack (Self.Depth).Exhausted
      then
         Fail (Self, Errors.Invalid_State, Error);
         return;
      end if;
      Skip_Whitespace (Self, Error);
      if Has_Input (Self) and then Current (Self) = '}' then
         Self.Stack (Self.Depth).Exhausted := True;
         return;
      end if;
      if not Self.Stack (Self.Depth).First_Item then
         Expect (Self, ',', Error);
      end if;
      Decode_String (Self, Name, Length, True, Error);
      Expect (Self, ':', Error);
      Require_Child_Start (Self, Error);
      Budgets.Consume_Container_Item (Self.Budget, Error);
      Latch (Self, Error);
      if Error.Code = Errors.No_Error then
         Self.Stack (Self.Depth).First_Item := False;
         Self.Stack (Self.Depth).Child := Child_Ready;
         Available := True;
      end if;
   end Next_Record_Field;

   overriding
   procedure Next_Field
     (Self      : in out Reader;
      Name      : out String;
      Length    : out Natural;
      Available : out Boolean;
      Error     : in out Errors.Error_Info) is
   begin
      if Self.Depth > 0
        and then Self.Stack (Self.Depth).Kind = Variant_Container
      then
         Next_Record_Field
           (Self, Variant_Container, Name, Length, Available, Error);
      else
         Next_Record_Field
           (Self, Record_Container, Name, Length, Available, Error);
      end if;
   end Next_Field;

   overriding
   procedure End_Record
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      Pop (Self, Record_Container, "}", Error);
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
   begin
      Alternative_Name := [others => ' '];
      Name_Length := 0;
      Length := Unknown_Length;
      Require_Leading (Self, "[", Error);
      Prepare_Value (Self, Error);
      Expect (Self, '[', Error);
      Decode_String (Self, Alternative_Name, Name_Length, True, Error);
      Expect (Self, ',', Error);
      Expect (Self, '{', Error);
      Push (Self, Variant_Container, (others => <>), Error);
   end Begin_Variant;

   overriding
   procedure End_Variant
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      Pop (Self, Variant_Container, "}]", Error);
   end End_Variant;
end Flyology_Serde.Deserializers.JSON;
