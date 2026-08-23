with Ada.Unchecked_Conversion;

package body Flyology_Serde.Deserializers.CBOR is
   use type Ada.Streams.Stream_Element_Offset;
   use type Errors.Error_Code;
   use type Errors.Input_Offset_Unit;
   use type Interfaces.Integer_64;
   use type Interfaces.Unsigned_64;

   subtype Byte is Ada.Streams.Stream_Element;
   subtype Byte_Offset is Ada.Streams.Stream_Element_Offset;
   subtype Byte_Array is Ada.Streams.Stream_Element_Array;
   subtype Major_Type is Natural range 0 .. 7;

   type Head_Info is record
      Major         : Major_Type := 0;
      Additional    : Natural range 0 .. 31 := 0;
      Argument      : Interfaces.Unsigned_64 := 0;
      Header_Length : Natural range 1 .. 9 := 1;
      Indefinite    : Boolean := False;
      Break_Code    : Boolean := False;
   end record;

   function Float_From_Bits is new Ada.Unchecked_Conversion
     (Interfaces.Unsigned_64, Interfaces.IEEE_Float_64);

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
     (Self : in out Reader; Code : Errors.Error_Code; Error : in out Errors.Error_Info) is
   begin
      Fail (Self, Code, Error, Self.Cursor);
   end Fail;

   function Source_Length (Self : Reader) return Interfaces.Unsigned_64
   is (Interfaces.Unsigned_64 (Self.Source'Length));

   function Byte_At (Self : Reader; Offset : Natural) return Byte
   is (Self.Source (Self.Source'First + Byte_Offset (Offset)));

   procedure Check_Span
     (Self   : in out Reader;
      Offset : Natural;
      Count  : Interfaces.Unsigned_64;
      Error  : in out Errors.Error_Info) is
      Start    : constant Interfaces.Unsigned_64 := Interfaces.Unsigned_64 (Offset);
      Distance : Interfaces.Unsigned_64;
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif Start > Source_Length (Self)
        or else Count > Source_Length (Self) - Start
      then
         Fail (Self, Errors.Syntax_Error, Error, Offset);
         return;
      elsif Offset < Self.Cursor then
         Fail (Self, Errors.Invalid_State, Error, Offset);
         return;
      end if;

      Distance := Interfaces.Unsigned_64 (Offset - Self.Cursor);
      if Distance > Interfaces.Unsigned_64 (Budgets.Input_Remaining (Self.Budget))
        or else Count
                > Interfaces.Unsigned_64 (Budgets.Input_Remaining (Self.Budget))
                  - Distance
      then
         Fail (Self, Errors.Capacity_Exceeded, Error, Offset);
      end if;
   end Check_Span;

   procedure Inspect_Head
     (Self   : in out Reader;
      Offset : Natural;
      Item   : out Head_Info;
      Error  : in out Errors.Error_Info)
   is
      Initial : Natural;
      Extra   : Natural := 0;
   begin
      Item := (others => <>);
      Check_Span (Self, Offset, 1, Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;

      Initial := Natural (Byte_At (Self, Offset));
      Item.Major := Initial / 32;
      Item.Additional := Initial mod 32;
      if Item.Additional < 24 then
         Item.Argument := Interfaces.Unsigned_64 (Item.Additional);
      elsif Item.Additional in 24 .. 27 then
         Extra := 2 ** (Item.Additional - 24);
         Item.Header_Length := 1 + Extra;
         Check_Span
           (Self, Offset, Interfaces.Unsigned_64 (Item.Header_Length), Error);
         if Error.Code /= Errors.No_Error then
            return;
         end if;
         Item.Argument := 0;
         for Index in 1 .. Extra loop
            Item.Argument :=
              Interfaces.Shift_Left (Item.Argument, 8)
              or Interfaces.Unsigned_64 (Byte_At (Self, Offset + Index));
         end loop;
         if Item.Major = 7
           and then Item.Additional = 24
           and then Item.Argument < 32
         then
            Fail (Self, Errors.Syntax_Error, Error, Offset);
         end if;
      elsif Item.Additional in 28 .. 30 then
         Fail (Self, Errors.Syntax_Error, Error, Offset);
      elsif Item.Major in 2 .. 5 then
         Item.Indefinite := True;
      elsif Item.Major = 7 then
         Item.Break_Code := True;
      else
         Fail (Self, Errors.Syntax_Error, Error, Offset);
      end if;
   end Inspect_Head;

   procedure Inspect_Surface_Head
     (Self   : in out Reader;
      Offset : Natural;
      Item   : out Head_Info;
      Error  : in out Errors.Error_Info) is
   begin
      Inspect_Head (Self, Offset, Item, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Item.Break_Code then
         Fail (Self, Errors.Syntax_Error, Error, Offset);
      elsif Item.Major = 6 then
         Fail (Self, Errors.Unsupported_Value, Error, Offset);
      elsif Item.Major = 7
        and then Item.Additional not in 20 | 21 | 22 | 25 .. 27
      then
         Fail (Self, Errors.Unsupported_Value, Error, Offset);
      end if;
   end Inspect_Surface_Head;

   procedure Advance
     (Self : in out Reader; Count : Natural; Error : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error or else Self.Failed then
         return;
      end if;
      Check_Span (Self, Self.Cursor, Interfaces.Unsigned_64 (Count), Error);
      if Error.Code = Errors.No_Error then
         Budgets.Consume_Input (Self.Budget, Count, Error);
         if Error.Code = Errors.No_Error then
            Self.Cursor := Self.Cursor + Count;
         end if;
         Latch (Self, Error);
      end if;
   end Advance;

   procedure Read_Head
     (Self : in out Reader; Item : out Head_Info; Error : in out Errors.Error_Info) is
   begin
      Inspect_Head (Self, Self.Cursor, Item, Error);
      if Error.Code = Errors.No_Error then
         Advance (Self, Item.Header_Length, Error);
      end if;
   end Read_Head;

   procedure Require_Ready
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif not Self.Initialized or else Self.Failed then
         Fail (Self, Errors.Invalid_State, Error);
      end if;
   end Require_Ready;

   function At_Break (Self : in out Reader; Error : in out Errors.Error_Info) return Boolean;

   procedure Require_Child_Start
     (Self : in out Reader; Error : in out Errors.Error_Info);

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
      if Error.Code = Errors.No_Error
        and then Self.Depth > 0
        and then Self.Stack (Self.Depth).Kind = Optional_Container
        and then Self.Stack (Self.Depth).Envelope_Indefinite
        and then Self.Stack (Self.Depth).Child = Child_Ready
        and then At_Break (Self, Error)
      then
         Fail (Self, Errors.Invalid_Value, Error);
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
               when Map_Key_In_Progress   =>
                  Require_Child_Start (Self, Error);
                  if Error.Code = Errors.No_Error then
                     Self.Stack (Self.Depth).Map_Phase := Map_Value_Ready;
                  end if;
               when Map_Value_In_Progress =>
                  Self.Stack (Self.Depth).Map_Phase := Map_Needs_Entry;
               when others                =>
                  Fail (Self, Errors.Invalid_State, Error);
            end case;
      end case;
   end Finish_Value;

   procedure Require_Major
     (Self     : in out Reader;
      Expected : Major_Type;
      Mismatch : Errors.Error_Code;
      Item     : out Head_Info;
      Error    : in out Errors.Error_Info) is
   begin
      Check_Value_Ready (Self, Error);
      Inspect_Surface_Head (Self, Self.Cursor, Item, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Item.Major /= Expected then
         Fail (Self, Mismatch, Error);
      end if;
   end Require_Major;

   procedure To_Length
     (Self  : in out Reader;
      Raw   : Interfaces.Unsigned_64;
      Value : out Natural;
      Error : in out Errors.Error_Info) is
   begin
      Value := 0;
      if Raw > Interfaces.Unsigned_64 (Natural'Last) then
         Fail (Self, Errors.Capacity_Exceeded, Error);
      else
         Value := Natural (Raw);
      end if;
   end To_Length;

   procedure Push
     (Self  : in out Reader;
      Frame : Container_Frame;
      Error : in out Errors.Error_Info) is
   begin
      Budgets.Enter_Container (Self.Budget, Frame.Declared, Error);
      if Error.Code /= Errors.No_Error then
         Latch (Self, Error);
      elsif Self.Depth = Policies.Maximum_Supported_Nesting then
         Fail (Self, Errors.Depth_Exceeded, Error);
      else
         Self.Depth := Self.Depth + 1;
         Self.Stack (Self.Depth) := Frame;
      end if;
   end Push;

   procedure Finish_Container
     (Self : in out Reader; Kind : Container_Kind; Error : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error or else Self.Failed then
         return;
      elsif Self.Depth = 0 or else Self.Stack (Self.Depth).Kind /= Kind then
         Fail (Self, Errors.Invalid_State, Error);
         return;
      end if;
      Budgets.Leave_Container (Self.Budget, Error);
      Self.Stack (Self.Depth) := (others => <>);
      Self.Depth := Self.Depth - 1;
      Finish_Value (Self, Error);
   end Finish_Container;

   function At_Break (Self : in out Reader; Error : in out Errors.Error_Info) return Boolean is
      Item : Head_Info;
   begin
      Inspect_Head (Self, Self.Cursor, Item, Error);
      return Error.Code = Errors.No_Error and then Item.Break_Code;
   end At_Break;

   procedure Require_Child_Start
     (Self : in out Reader; Error : in out Errors.Error_Info) is
      Item : Head_Info;
   begin
      Inspect_Head (Self, Self.Cursor, Item, Error);
      if Error.Code = Errors.No_Error and then Item.Break_Code then
         Fail (Self, Errors.Syntax_Error, Error);
      end if;
   end Require_Child_Start;

   procedure Consume_Break
     (Self : in out Reader; Code : Errors.Error_Code; Error : in out Errors.Error_Info) is
      Item : Head_Info;
   begin
      Inspect_Head (Self, Self.Cursor, Item, Error);
      if Error.Code = Errors.No_Error and then not Item.Break_Code then
         Fail (Self, Code, Error);
      elsif Error.Code = Errors.No_Error then
         Advance (Self, 1, Error);
      end if;
   end Consume_Break;

   procedure Validate_UTF_8
     (Self   : in out Reader;
      Offset : Natural;
      Length : Natural;
      Error  : in out Errors.Error_Info)
   is
      Position  : Natural := 0;
      First     : Natural;
      Second    : Natural;
      Remaining : Natural;

      function Octet (Ahead : Natural := 0) return Natural
      is (Natural (Byte_At (Self, Offset + Position + Ahead)));

      procedure Reject (At_Position : Natural) is
      begin
         Fail (Self, Errors.Invalid_Text, Error, Offset + At_Position);
      end Reject;
   begin
      while Position < Length loop
         First := Octet;
         Remaining := Length - Position;
         if First <= 16#7F# then
            Position := Position + 1;
         elsif First in 16#C2# .. 16#DF# then
            if Remaining < 2 then
               Reject (Position);
               return;
            elsif Octet (1) not in 16#80# .. 16#BF# then
               Reject (Position + 1);
               return;
            end if;
            Position := Position + 2;
         elsif First in 16#E0# .. 16#EF# then
            if Remaining < 2 then
               Reject (Position);
               return;
            end if;
            Second := Octet (1);
            if (First = 16#E0# and then Second not in 16#A0# .. 16#BF#)
              or else (First = 16#ED# and then Second not in 16#80# .. 16#9F#)
              or else (First not in 16#E0# | 16#ED#
                       and then Second not in 16#80# .. 16#BF#)
            then
               Reject (Position + 1);
               return;
            elsif Remaining < 3 then
               Reject (Position);
               return;
            elsif Octet (2) not in 16#80# .. 16#BF# then
               Reject (Position + 2);
               return;
            end if;
            Position := Position + 3;
         elsif First in 16#F0# .. 16#F4# then
            if Remaining < 2 then
               Reject (Position);
               return;
            end if;
            Second := Octet (1);
            if (First = 16#F0# and then Second not in 16#90# .. 16#BF#)
              or else (First = 16#F4# and then Second not in 16#80# .. 16#8F#)
              or else (First in 16#F1# .. 16#F3#
                       and then Second not in 16#80# .. 16#BF#)
            then
               Reject (Position + 1);
               return;
            elsif Remaining < 3 then
               Reject (Position);
               return;
            elsif Octet (2) not in 16#80# .. 16#BF# then
               Reject (Position + 2);
               return;
            elsif Remaining < 4 then
               Reject (Position);
               return;
            elsif Octet (3) not in 16#80# .. 16#BF# then
               Reject (Position + 3);
               return;
            end if;
            Position := Position + 4;
         else
            Reject (Position);
            return;
         end if;
      end loop;
   end Validate_UTF_8;

   procedure Scan_String
     (Self           : in out Reader;
      Expected_Major : Major_Type;
      Total          : out Natural;
      End_Offset     : out Natural;
      Error          : in out Errors.Error_Info)
   is
      Item        : Head_Info;
      Offset      : Natural := Self.Cursor;
      Chunk_Count : Natural := 0;
      Chunk       : Natural;

      procedure Add_Chunk is
      begin
         To_Length (Self, Item.Argument, Chunk, Error);
         if Error.Code /= Errors.No_Error then
            return;
         elsif Total > Natural'Last - Chunk then
            Fail (Self, Errors.Capacity_Exceeded, Error, Offset);
            return;
         end if;
         Check_Span
           (Self,
            Offset + Item.Header_Length,
            Interfaces.Unsigned_64 (Chunk),
            Error);
         if Error.Code = Errors.No_Error and then Expected_Major = 3 then
            Validate_UTF_8 (Self, Offset + Item.Header_Length, Chunk, Error);
         end if;
         if Error.Code = Errors.No_Error then
            Total := Total + Chunk;
            if Expected_Major = 3 then
               Budgets.Check_Text_Length (Self.Budget, Total, Error);
            else
               Budgets.Check_Byte_Length (Self.Budget, Total, Error);
            end if;
            Latch (Self, Error);
         end if;
         if Error.Code = Errors.No_Error then
            Offset := Offset + Item.Header_Length + Chunk;
         end if;
      end Add_Chunk;
   begin
      Total := 0;
      End_Offset := Self.Cursor;
      Inspect_Surface_Head (Self, Offset, Item, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Item.Major /= Expected_Major then
         Fail (Self, Errors.Unexpected_Kind, Error, Offset);
         return;
      end if;

      if not Item.Indefinite then
         Add_Chunk;
      else
         Offset := Offset + Item.Header_Length;
         loop
            Inspect_Head (Self, Offset, Item, Error);
            exit when Error.Code /= Errors.No_Error;
            if Item.Break_Code then
               Offset := Offset + 1;
               exit;
            elsif Item.Major /= Expected_Major or else Item.Indefinite then
               Fail (Self, Errors.Syntax_Error, Error, Offset);
               exit;
            elsif Chunk_Count = Self.Policy.Limits.Maximum_Container_Items then
               Fail (Self, Errors.Capacity_Exceeded, Error, Offset);
               exit;
            end if;
            Chunk_Count := Chunk_Count + 1;
            Add_Chunk;
         end loop;
      end if;
      if Error.Code = Errors.No_Error then
         End_Offset := Offset;
      end if;
   end Scan_String;

   procedure Consume_String
     (Self           : in out Reader;
      Expected_Major : Major_Type;
      Text_Target    : in out String;
      Byte_Target    : in out Byte_Array;
      Is_Text        : Boolean;
      Error          : in out Errors.Error_Info)
   is
      Item   : Head_Info;
      Length : Natural;
      Cursor : Natural := 0;

      procedure Copy_Payload is
      begin
         To_Length (Self, Item.Argument, Length, Error);
         if Error.Code /= Errors.No_Error then
            return;
         end if;
         if Length > 0 then
            for Index in 0 .. Length - 1 loop
               if Is_Text then
                  Text_Target (Text_Target'First + Cursor + Index) :=
                    Character'Val (Byte_At (Self, Self.Cursor + Index));
               else
                  Byte_Target
                    (Byte_Target'First + Byte_Offset (Cursor + Index)) :=
                    Byte_At (Self, Self.Cursor + Index);
               end if;
            end loop;
         end if;
         Advance (Self, Length, Error);
         Cursor := Cursor + Length;
      end Copy_Payload;
   begin
      Read_Head (Self, Item, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif not Item.Indefinite then
         Copy_Payload;
      else
         loop
            Read_Head (Self, Item, Error);
            exit when Error.Code /= Errors.No_Error or else Item.Break_Code;
            if Item.Major /= Expected_Major or else Item.Indefinite then
               Fail (Self, Errors.Syntax_Error, Error);
               exit;
            end if;
            Copy_Payload;
         end loop;
      end if;
   end Consume_String;

   procedure Read_String_Value
     (Self        : in out Reader;
      Text_Target : in out String;
      Byte_Target : in out Byte_Array;
      Is_Text     : Boolean;
      Length      : out Natural;
      Error       : in out Errors.Error_Info) is
      End_Offset : Natural;
      Major      : constant Major_Type := (if Is_Text then 3 else 2);
   begin
      Length := 0;
      Check_Value_Ready (Self, Error);
      Scan_String (Self, Major, Length, End_Offset, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif (Is_Text and then Length > Text_Target'Length)
        or else (not Is_Text and then Length > Byte_Target'Length)
      then
         Fail (Self, Errors.Capacity_Exceeded, Error);
         return;
      end if;
      if Is_Text then
         Budgets.Check_Text_Length (Self.Budget, Length, Error);
      else
         Budgets.Check_Byte_Length (Self.Budget, Length, Error);
      end if;
      Latch (Self, Error);
      Prepare_Value (Self, Error);
      if Error.Code = Errors.No_Error then
         Consume_String
           (Self, Major, Text_Target, Byte_Target, Is_Text, Error);
         Finish_Value (Self, Error);
      end if;
   end Read_String_Value;

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

   overriding
   procedure Abort_Document
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      Latch (Self, Error);
      while Budgets.Depth (Self.Budget) > 0 loop
         Budgets.Leave_Container (Self.Budget, Error);
      end loop;
      Self.Stack := [others => <>];
      Self.Depth := 0;
      Self.Failed := True;
      Self.Document_Complete := False;
   end Abort_Document;

   overriding
   procedure Finish_Document
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      Require_Ready (Self, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.Root /= Root_Complete or else Self.Depth /= 0 then
         Fail (Self, Errors.Invalid_State, Error);
      elsif Interfaces.Unsigned_64 (Self.Cursor) /= Source_Length (Self) then
         Fail (Self, Errors.Syntax_Error, Error);
      else
         Self.Document_Complete := True;
      end if;
   end Finish_Document;

   function Is_Complete (Self : Reader) return Boolean
   is (Self.Document_Complete and then not Self.Failed);

   function Input_Offset (Self : Reader) return Natural is (Self.Cursor);

   overriding
   function Capabilities
     (Self : Reader) return Data_Model.Format_Capabilities is
      pragma Unreferenced (Self);
   begin
      return Data_Model.All_Capabilities;
   end Capabilities;

   overriding
   function Peek_Kind
     (Self : in out Reader; Error : in out Errors.Error_Info)
      return Data_Model.Value_Kind is
      Item : Head_Info;
   begin
      Check_Value_Ready (Self, Error);
      Inspect_Surface_Head (Self, Self.Cursor, Item, Error);
      if Error.Code /= Errors.No_Error then
         return Data_Model.Null_Value;
      end if;
      case Item.Major is
         when 0 => return Data_Model.Unsigned_Integer_Value;
         when 1 => return Data_Model.Signed_Integer_Value;
         when 2 => return Data_Model.Bytes_Value;
         when 3 => return Data_Model.Text_Value;
         when 4 => return Data_Model.Sequence_Value;
         when 5 => return Data_Model.Map_Value;
         when 6 => null;
         when 7 =>
            case Item.Additional is
               when 20 | 21    => return Data_Model.Boolean_Value;
               when 22         => return Data_Model.Null_Value;
               when 25 .. 27   => return Data_Model.Float_Value;
               when others     => null;
            end case;
      end case;
      return Data_Model.Null_Value;
   end Peek_Kind;

   overriding
   procedure Read_Null
     (Self : in out Reader; Error : in out Errors.Error_Info) is
      Item : Head_Info;
   begin
      Require_Major (Self, 7, Errors.Unexpected_Kind, Item, Error);
      if Error.Code = Errors.No_Error and then Item.Additional /= 22 then
         Fail (Self, Errors.Unexpected_Kind, Error);
      end if;
      Prepare_Value (Self, Error);
      Read_Head (Self, Item, Error);
      Finish_Value (Self, Error);
   end Read_Null;

   overriding
   procedure Read_Boolean
     (Self  : in out Reader;
      Value : out Boolean;
      Error : in out Errors.Error_Info) is
      Item : Head_Info;
   begin
      Value := False;
      Require_Major (Self, 7, Errors.Unexpected_Kind, Item, Error);
      if Error.Code = Errors.No_Error and then Item.Additional not in 20 | 21 then
         Fail (Self, Errors.Unexpected_Kind, Error);
      elsif Error.Code = Errors.No_Error then
         Value := Item.Additional = 21;
      end if;
      Prepare_Value (Self, Error);
      Read_Head (Self, Item, Error);
      Finish_Value (Self, Error);
   end Read_Boolean;

   overriding
   procedure Read_Unsigned
     (Self  : in out Reader;
      Value : out Interfaces.Unsigned_64;
      Error : in out Errors.Error_Info) is
      Item : Head_Info;
   begin
      Value := 0;
      Require_Major (Self, 0, Errors.Unexpected_Kind, Item, Error);
      if Error.Code = Errors.No_Error then
         Value := Item.Argument;
      end if;
      Prepare_Value (Self, Error);
      Read_Head (Self, Item, Error);
      Finish_Value (Self, Error);
   end Read_Unsigned;

   overriding
   procedure Read_Signed
     (Self  : in out Reader;
      Value : out Interfaces.Integer_64;
      Error : in out Errors.Error_Info) is
      Item : Head_Info;
   begin
      Value := 0;
      Check_Value_Ready (Self, Error);
      Inspect_Surface_Head (Self, Self.Cursor, Item, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Item.Major not in 0 | 1 then
         Fail (Self, Errors.Unexpected_Kind, Error);
      elsif Item.Argument > Interfaces.Unsigned_64 (Interfaces.Integer_64'Last) then
         Fail (Self, Errors.Out_Of_Range, Error);
      elsif Item.Major = 0 then
         Value := Interfaces.Integer_64 (Item.Argument);
      else
         Value := -1 - Interfaces.Integer_64 (Item.Argument);
      end if;
      Prepare_Value (Self, Error);
      Read_Head (Self, Item, Error);
      Finish_Value (Self, Error);
   end Read_Signed;

   function Highest_Bit
     (Value : Interfaces.Unsigned_64; Maximum : Natural) return Natural is
   begin
      for Position in reverse 0 .. Maximum loop
         if (Value and Interfaces.Shift_Left (Interfaces.Unsigned_64'(1), Position)) /= 0 then
            return Position;
         end if;
      end loop;
      return 0;
   end Highest_Bit;

   function Promote_Finite
     (Bits : Interfaces.Unsigned_64; Width : Natural) return Interfaces.Unsigned_64 is
      Sign          : Interfaces.Unsigned_64;
      Exponent      : Interfaces.Unsigned_64;
      Fraction      : Interfaces.Unsigned_64;
      Fraction_Bits : Natural;
      Bias          : Integer;
      Position      : Natural;
      Double_Exp    : Integer;
   begin
      if Width = 16 then
         Sign := Interfaces.Shift_Left (Bits and 16#8000#, 48);
         Exponent := Interfaces.Shift_Right (Bits and 16#7C00#, 10);
         Fraction := Bits and 16#03FF#;
         Fraction_Bits := 10;
         Bias := 15;
      elsif Width = 32 then
         Sign := Interfaces.Shift_Left (Bits and 16#8000_0000#, 32);
         Exponent := Interfaces.Shift_Right (Bits and 16#7F80_0000#, 23);
         Fraction := Bits and 16#007F_FFFF#;
         Fraction_Bits := 23;
         Bias := 127;
      else
         return Bits;
      end if;

      if Exponent = 0 and then Fraction = 0 then
         return Sign;
      elsif Exponent = 0 then
         Position := Highest_Bit (Fraction, Fraction_Bits - 1);
         Double_Exp := Position - (Bias + Fraction_Bits - 1) + 1023;
         return Sign
           or Interfaces.Shift_Left (Interfaces.Unsigned_64 (Double_Exp), 52)
           or Interfaces.Shift_Left
                (Fraction - Interfaces.Shift_Left (Interfaces.Unsigned_64'(1), Position),
                 52 - Position);
      else
         Double_Exp := Integer (Exponent) - Bias + 1023;
         return Sign
           or Interfaces.Shift_Left (Interfaces.Unsigned_64 (Double_Exp), 52)
           or Interfaces.Shift_Left (Fraction, 52 - Fraction_Bits);
      end if;
   end Promote_Finite;

   overriding
   procedure Read_Float_64
     (Self  : in out Reader;
      Value : out Data_Model.Float_64_Value;
      Error : in out Errors.Error_Info) is
      Item      : Head_Info;
      Width     : Natural;
      Exp_Shift : Natural;
      Exp_Mask  : Interfaces.Unsigned_64;
      Frac_Mask : Interfaces.Unsigned_64;
      Exponent  : Interfaces.Unsigned_64;
      Fraction  : Interfaces.Unsigned_64;
      Sign      : Boolean;
      Bits      : Interfaces.Unsigned_64;
   begin
      Value := Data_Model.Make_Finite (0.0);
      Require_Major (Self, 7, Errors.Unexpected_Kind, Item, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Item.Additional = 25 then
         Width := 16;
         Exp_Shift := 10;
         Exp_Mask := 16#1F#;
         Frac_Mask := 16#03FF#;
      elsif Item.Additional = 26 then
         Width := 32;
         Exp_Shift := 23;
         Exp_Mask := 16#FF#;
         Frac_Mask := 16#007F_FFFF#;
      elsif Item.Additional = 27 then
         Width := 64;
         Exp_Shift := 52;
         Exp_Mask := 16#7FF#;
         Frac_Mask := 16#000F_FFFF_FFFF_FFFF#;
      else
         Fail (Self, Errors.Unexpected_Kind, Error);
         return;
      end if;

      Bits := Item.Argument;
      Exponent := Interfaces.Shift_Right (Bits, Exp_Shift) and Exp_Mask;
      Fraction := Bits and Frac_Mask;
      Sign := (Bits and Interfaces.Shift_Left (Interfaces.Unsigned_64'(1), Width - 1)) /= 0;
      Prepare_Value (Self, Error);
      Read_Head (Self, Item, Error);
      if Error.Code = Errors.No_Error then
         if Exponent = Exp_Mask then
            if Fraction /= 0 then
               Value := Data_Model.Not_A_Number_Value;
            elsif Sign then
               Value := Data_Model.Negative_Infinity_Value;
            else
               Value := Data_Model.Positive_Infinity_Value;
            end if;
         else
            Value := Data_Model.Make_Finite
              (Float_From_Bits (Promote_Finite (Bits, Width)));
         end if;
      end if;
      Finish_Value (Self, Error);
   end Read_Float_64;

   overriding
   procedure Read_Text
     (Self   : in out Reader;
      Value  : out String;
      Length : out Natural;
      Error  : in out Errors.Error_Info)
   is
      Dummy : Byte_Array (1 .. 0);
   begin
      Value := [others => ' '];
      Read_String_Value (Self, Value, Dummy, True, Length, Error);
   end Read_Text;

   overriding
   procedure Read_Bytes
     (Self   : in out Reader;
      Value  : out Byte_Array;
      Length : out Natural;
      Error  : in out Errors.Error_Info)
   is
      Dummy : String (1 .. 0);
   begin
      Value := [others => 0];
      Read_String_Value (Self, Dummy, Value, False, Length, Error);
   end Read_Bytes;

   procedure Skip_Raw
     (Self      : in out Reader;
      Raw_Depth : Natural;
      Error     : in out Errors.Error_Info);

   procedure Check_Raw_Depth
     (Self : in out Reader; Raw_Depth : Natural; Error : in out Errors.Error_Info) is
   begin
      if Budgets.Depth (Self.Budget) > Natural (Self.Policy.Limits.Maximum_Nesting_Depth)
        or else Raw_Depth
                > Natural (Self.Policy.Limits.Maximum_Nesting_Depth)
                  - Budgets.Depth (Self.Budget)
      then
         Fail (Self, Errors.Depth_Exceeded, Error);
      end if;
   end Check_Raw_Depth;

   procedure Skip_Raw_String
     (Self : in out Reader; Item : Head_Info; Raw_Depth : Natural;
      Error : in out Errors.Error_Info) is
      Current_Item : Head_Info := Item;
      Length       : Natural;
      Total        : Natural := 0;
      Chunks       : Natural := 0;
      Is_Text      : constant Boolean := Item.Major = 3;

      procedure Consume_Payload is
      begin
         To_Length (Self, Current_Item.Argument, Length, Error);
         if Error.Code /= Errors.No_Error or else Total > Natural'Last - Length then
            if Error.Code = Errors.No_Error then
               Fail (Self, Errors.Capacity_Exceeded, Error);
            end if;
            return;
         end if;
         Check_Span (Self, Self.Cursor, Interfaces.Unsigned_64 (Length), Error);
         if Is_Text and then Error.Code = Errors.No_Error then
            Validate_UTF_8 (Self, Self.Cursor, Length, Error);
         end if;
         if Error.Code = Errors.No_Error then
            Total := Total + Length;
            if Is_Text then
               Budgets.Check_Text_Length (Self.Budget, Total, Error);
            else
               Budgets.Check_Byte_Length (Self.Budget, Total, Error);
            end if;
            Latch (Self, Error);
            Advance (Self, Length, Error);
         end if;
      end Consume_Payload;
   begin
      if not Item.Indefinite then
         Consume_Payload;
         return;
      end if;
      Check_Raw_Depth (Self, Raw_Depth + 1, Error);
      while Error.Code = Errors.No_Error loop
         Read_Head (Self, Current_Item, Error);
         exit when Error.Code /= Errors.No_Error or else Current_Item.Break_Code;
         if Current_Item.Major /= Item.Major or else Current_Item.Indefinite then
            Fail (Self, Errors.Syntax_Error, Error);
         elsif Chunks = Self.Policy.Limits.Maximum_Container_Items then
            Fail (Self, Errors.Capacity_Exceeded, Error);
         else
            Chunks := Chunks + 1;
            Consume_Payload;
         end if;
      end loop;
   end Skip_Raw_String;

   procedure Skip_Raw
     (Self      : in out Reader;
      Raw_Depth : Natural;
      Error     : in out Errors.Error_Info) is
      Item  : Head_Info;
      Count : Natural;
   begin
      Read_Head (Self, Item, Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      case Item.Major is
         when 0 | 1 => null;
         when 2 | 3 => Skip_Raw_String (Self, Item, Raw_Depth, Error);
         when 4 | 5 =>
            Check_Raw_Depth (Self, Raw_Depth + 1, Error);
            if Error.Code /= Errors.No_Error then
               return;
            end if;
            if Item.Indefinite then
               Count := 0;
               loop
                  exit when Error.Code /= Errors.No_Error;
                  if At_Break (Self, Error) then
                     Advance (Self, 1, Error);
                     exit;
                  elsif Count = Self.Policy.Limits.Maximum_Container_Items then
                     Fail (Self, Errors.Capacity_Exceeded, Error);
                     exit;
                  end if;
                  Count := Count + 1;
                  Skip_Raw (Self, Raw_Depth + 1, Error);
                  if Item.Major = 5 and then Error.Code = Errors.No_Error then
                     if At_Break (Self, Error) then
                        Fail (Self, Errors.Syntax_Error, Error);
                     else
                        Skip_Raw (Self, Raw_Depth + 1, Error);
                     end if;
                  end if;
               end loop;
            else
               To_Length (Self, Item.Argument, Count, Error);
               if Error.Code = Errors.No_Error
                 and then Count > Self.Policy.Limits.Maximum_Container_Items
               then
                  Fail (Self, Errors.Capacity_Exceeded, Error);
               end if;
               for Index in 1 .. Count loop
                  exit when Error.Code /= Errors.No_Error;
                  Skip_Raw (Self, Raw_Depth + 1, Error);
                  if Item.Major = 5 then
                     Skip_Raw (Self, Raw_Depth + 1, Error);
                  end if;
               end loop;
            end if;
         when 6 =>
            Check_Raw_Depth (Self, Raw_Depth + 1, Error);
            Skip_Raw (Self, Raw_Depth + 1, Error);
         when 7 =>
            if Item.Break_Code then
               Fail (Self, Errors.Syntax_Error, Error);
            end if;
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

   procedure Begin_Container
     (Self       : in out Reader;
      Kind       : Container_Kind;
      Major      : Major_Type;
      Length     : out Data_Model.Length_Information;
      Indefinite : out Boolean;
      Error      : in out Errors.Error_Info) is
      Item : Head_Info;
      Size : Natural;
   begin
      Length := Data_Model.Unknown_Length;
      Indefinite := False;
      Require_Major (Self, Major, Errors.Unexpected_Kind, Item, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Item.Indefinite then
         Indefinite := True;
      else
         To_Length (Self, Item.Argument, Size, Error);
         Length := Data_Model.Known_Length (Size);
      end if;
      Prepare_Value (Self, Error);
      Read_Head (Self, Item, Error);
      if Error.Code = Errors.No_Error then
         Push
           (Self,
            (Kind       => Kind,
             Declared   => Length,
             Indefinite => Indefinite,
             others     => <>),
            Error);
      end if;
   end Begin_Container;

   procedure Next_Item
     (Self      : in out Reader;
      Kind      : Container_Kind;
      Available : out Boolean;
      Error     : in out Errors.Error_Info) is
   begin
      Available := False;
      Require_Ready (Self, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.Depth = 0 or else Self.Stack (Self.Depth).Kind /= Kind
        or else Self.Stack (Self.Depth).Child /= No_Child
        or else Self.Stack (Self.Depth).Exhausted
      then
         Fail (Self, Errors.Invalid_State, Error);
         return;
      elsif Self.Stack (Self.Depth).Declared.Known
        and then Self.Stack (Self.Depth).Observed
                 = Self.Stack (Self.Depth).Declared.Length
      then
         Self.Stack (Self.Depth).Exhausted := True;
         return;
      elsif Self.Stack (Self.Depth).Indefinite and then At_Break (Self, Error) then
         Self.Stack (Self.Depth).Exhausted := True;
         return;
      end if;
      Require_Child_Start (Self, Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Budgets.Consume_Container_Item (Self.Budget, Error);
      Latch (Self, Error);
      if Error.Code = Errors.No_Error then
         Self.Stack (Self.Depth).Observed := Self.Stack (Self.Depth).Observed + 1;
         Self.Stack (Self.Depth).Child := Child_Ready;
         Available := True;
      end if;
   end Next_Item;

   procedure End_Item_Container
     (Self : in out Reader; Kind : Container_Kind; Error : in out Errors.Error_Info) is
   begin
      Require_Ready (Self, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.Depth = 0 or else Self.Stack (Self.Depth).Kind /= Kind
        or else Self.Stack (Self.Depth).Child /= No_Child
        or else not Self.Stack (Self.Depth).Exhausted
      then
         Fail (Self, Errors.Invalid_State, Error);
         return;
      end if;
      if Self.Stack (Self.Depth).Indefinite then
         Consume_Break (Self, Errors.Syntax_Error, Error);
      end if;
      Finish_Container (Self, Kind, Error);
   end End_Item_Container;

   overriding
   procedure Begin_Optional
     (Self    : in out Reader;
      Present : out Boolean;
      Error   : in out Errors.Error_Info) is
      Envelope : Head_Info;
      Marker   : Head_Info;
      Child    : Head_Info;
      Expected : Interfaces.Unsigned_64;
      Is_Present : Boolean;
   begin
      Present := False;
      Require_Major (Self, 4, Errors.Unexpected_Kind, Envelope, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif not Envelope.Indefinite and then Envelope.Argument not in 1 | 2 then
         Fail (Self, Errors.Invalid_Value, Error);
         return;
      end if;
      Prepare_Value (Self, Error);
      Read_Head (Self, Envelope, Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Inspect_Head (Self, Self.Cursor, Marker, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Marker.Major = 6 then
         Fail (Self, Errors.Unsupported_Value, Error);
      elsif Marker.Break_Code then
         Fail
           (Self,
            (if Envelope.Indefinite
             then Errors.Invalid_Value
             else Errors.Syntax_Error),
            Error);
      elsif Marker.Major /= 0 or else Marker.Argument not in 0 | 1 then
         Fail (Self, Errors.Invalid_Value, Error);
      end if;
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Read_Head (Self, Marker, Error);
      Is_Present := Marker.Argument = 1;
      Expected := 1 + Marker.Argument;
      if not Envelope.Indefinite and then Envelope.Argument /= Expected then
         Fail (Self, Errors.Invalid_Value, Error);
         return;
      end if;
      if Is_Present then
         Inspect_Head (Self, Self.Cursor, Child, Error);
         if Error.Code = Errors.No_Error and then Child.Major = 6 then
            Fail (Self, Errors.Unsupported_Value, Error);
         elsif Error.Code = Errors.No_Error and then Child.Break_Code then
            Fail
              (Self,
               (if Envelope.Indefinite
                then Errors.Invalid_Value
                else Errors.Syntax_Error),
               Error);
         end if;
         if Error.Code /= Errors.No_Error then
            return;
         end if;
      end if;
      Push
        (Self,
         (Kind                => Optional_Container,
          Child               => (if Is_Present then Child_Ready else No_Child),
          Declared            => Data_Model.Known_Length (Boolean'Pos (Is_Present)),
          Exhausted           => True,
          Indefinite          => Envelope.Indefinite,
          Envelope_Indefinite => Envelope.Indefinite,
         others              => <>),
         Error);
      if Error.Code = Errors.No_Error and then Is_Present then
         Budgets.Consume_Container_Item (Self.Budget, Error);
         Latch (Self, Error);
      end if;
      if Error.Code = Errors.No_Error then
         Present := Is_Present;
      end if;
   end Begin_Optional;

   overriding
   procedure End_Optional
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      Require_Ready (Self, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.Depth = 0
        or else Self.Stack (Self.Depth).Kind /= Optional_Container
        or else Self.Stack (Self.Depth).Child /= No_Child
      then
         Fail (Self, Errors.Invalid_State, Error);
         return;
      end if;
      if Self.Stack (Self.Depth).Envelope_Indefinite then
         Consume_Break (Self, Errors.Invalid_Value, Error);
      end if;
      Finish_Container (Self, Optional_Container, Error);
   end End_Optional;

   overriding
   procedure Begin_Sequence
     (Self   : in out Reader;
      Length : out Data_Model.Length_Information;
      Error  : in out Errors.Error_Info) is
      Indefinite : Boolean;
   begin
      Begin_Container
        (Self, Sequence_Container, 4, Length, Indefinite, Error);
   end Begin_Sequence;

   overriding
   procedure Next_Element
     (Self      : in out Reader;
      Available : out Boolean;
      Error     : in out Errors.Error_Info) is
   begin
      Next_Item (Self, Sequence_Container, Available, Error);
   end Next_Element;

   overriding
   procedure End_Sequence
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      End_Item_Container (Self, Sequence_Container, Error);
   end End_Sequence;

   overriding
   procedure Begin_Map
     (Self   : in out Reader;
      Length : out Data_Model.Length_Information;
      Error  : in out Errors.Error_Info) is
      Indefinite : Boolean;
   begin
      Begin_Container (Self, Map_Container, 5, Length, Indefinite, Error);
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
      elsif Self.Stack (Self.Depth).Declared.Known
        and then Self.Stack (Self.Depth).Observed
                 = Self.Stack (Self.Depth).Declared.Length
      then
         Self.Stack (Self.Depth).Exhausted := True;
         return;
      elsif Self.Stack (Self.Depth).Indefinite and then At_Break (Self, Error) then
         Self.Stack (Self.Depth).Exhausted := True;
         return;
      end if;
      Require_Child_Start (Self, Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Budgets.Consume_Container_Item (Self.Budget, Error);
      Latch (Self, Error);
      if Error.Code = Errors.No_Error then
         Self.Stack (Self.Depth).Observed := Self.Stack (Self.Depth).Observed + 1;
         Self.Stack (Self.Depth).Map_Phase := Map_Key_Ready;
         Available := True;
      end if;
   end Next_Map_Entry;

   overriding
   procedure End_Map
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      Require_Ready (Self, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.Depth = 0
        or else Self.Stack (Self.Depth).Kind /= Map_Container
        or else Self.Stack (Self.Depth).Map_Phase /= Map_Needs_Entry
        or else not Self.Stack (Self.Depth).Exhausted
      then
         Fail (Self, Errors.Invalid_State, Error);
         return;
      end if;
      if Self.Stack (Self.Depth).Indefinite then
         Consume_Break (Self, Errors.Syntax_Error, Error);
      end if;
      Finish_Container (Self, Map_Container, Error);
   end End_Map;

   procedure Read_Structural_Text
     (Self   : in out Reader;
      Value  : out String;
      Length : out Natural;
      Error  : in out Errors.Error_Info) is
      End_Offset : Natural;
      Dummy      : Byte_Array (1 .. 0);
   begin
      Value := [others => ' '];
      Scan_String (Self, 3, Length, End_Offset, Error);
      if Error.Code = Errors.No_Error and then Length > Value'Length then
         Fail (Self, Errors.Capacity_Exceeded, Error);
      end if;
      Budgets.Check_Text_Length (Self.Budget, Length, Error);
      Latch (Self, Error);
      if Error.Code = Errors.No_Error then
         Consume_String (Self, 3, Value, Dummy, True, Error);
      end if;
   end Read_Structural_Text;

   overriding
   procedure Begin_Record
     (Self      : in out Reader;
      Type_Name : String;
      Length    : out Data_Model.Length_Information;
      Error     : in out Errors.Error_Info) is
      pragma Unreferenced (Type_Name);
      Indefinite : Boolean;
   begin
      Begin_Container (Self, Record_Container, 5, Length, Indefinite, Error);
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
      elsif Self.Depth = 0 or else Self.Stack (Self.Depth).Kind /= Kind
        or else Self.Stack (Self.Depth).Child /= No_Child
        or else Self.Stack (Self.Depth).Exhausted
      then
         Fail (Self, Errors.Invalid_State, Error);
         return;
      elsif Self.Stack (Self.Depth).Declared.Known
        and then Self.Stack (Self.Depth).Observed
                 = Self.Stack (Self.Depth).Declared.Length
      then
         Self.Stack (Self.Depth).Exhausted := True;
         return;
      elsif Self.Stack (Self.Depth).Indefinite and then At_Break (Self, Error) then
         Self.Stack (Self.Depth).Exhausted := True;
         return;
      end if;
      if At_Break (Self, Error) then
         Fail (Self, Errors.Syntax_Error, Error);
         return;
      end if;
      Read_Structural_Text (Self, Name, Length, Error);
      if Error.Code = Errors.No_Error then
         Require_Child_Start (Self, Error);
      end if;
      if Error.Code = Errors.No_Error then
         Budgets.Consume_Container_Item (Self.Budget, Error);
         Latch (Self, Error);
      end if;
      if Error.Code = Errors.No_Error then
         Self.Stack (Self.Depth).Observed := Self.Stack (Self.Depth).Observed + 1;
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
      if Self.Depth > 0 and then Self.Stack (Self.Depth).Kind = Variant_Container then
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
      End_Item_Container (Self, Record_Container, Error);
   end End_Record;

   overriding
   procedure Read_Enumeration
     (Self         : in out Reader;
      Type_Name    : String;
      Literal_Name : out String;
      Length       : out Natural;
      Error        : in out Errors.Error_Info) is
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
      Error            : in out Errors.Error_Info) is
      pragma Unreferenced (Type_Name);
      Envelope : Head_Info;
      Payload  : Head_Info;
      Size     : Natural;
   begin
      Alternative_Name := [others => ' '];
      Name_Length := 0;
      Length := Data_Model.Unknown_Length;
      Require_Major (Self, 4, Errors.Unexpected_Kind, Envelope, Error);
      if Error.Code = Errors.No_Error
        and then not Envelope.Indefinite
        and then Envelope.Argument /= 2
      then
         Fail (Self, Errors.Invalid_Value, Error);
      end if;
      Prepare_Value (Self, Error);
      Read_Head (Self, Envelope, Error);
      if Error.Code = Errors.No_Error then
         Inspect_Head (Self, Self.Cursor, Payload, Error);
         if Error.Code = Errors.No_Error and then Payload.Major = 6 then
            Fail (Self, Errors.Unsupported_Value, Error);
         elsif Error.Code = Errors.No_Error and then Payload.Break_Code then
            Fail
              (Self,
               (if Envelope.Indefinite
                then Errors.Invalid_Value
                else Errors.Syntax_Error),
               Error);
         elsif Error.Code = Errors.No_Error and then Payload.Major /= 3 then
            Fail (Self, Errors.Invalid_Value, Error);
         end if;
         if Error.Code = Errors.No_Error then
            Read_Structural_Text
              (Self, Alternative_Name, Name_Length, Error);
         end if;
      end if;
      if Error.Code = Errors.No_Error then
         Inspect_Head (Self, Self.Cursor, Payload, Error);
         if Error.Code = Errors.No_Error and then Payload.Major = 6 then
            Fail (Self, Errors.Unsupported_Value, Error);
         elsif Error.Code = Errors.No_Error and then Payload.Break_Code then
            Fail
              (Self,
               (if Envelope.Indefinite
                then Errors.Invalid_Value
                else Errors.Syntax_Error),
               Error);
         elsif Error.Code = Errors.No_Error and then Payload.Major /= 5 then
            Fail (Self, Errors.Invalid_Value, Error);
         end if;
      end if;
      if Error.Code = Errors.No_Error then
         if not Payload.Indefinite then
            To_Length (Self, Payload.Argument, Size, Error);
            Length := Data_Model.Known_Length (Size);
         end if;
         Read_Head (Self, Payload, Error);
      end if;
      if Error.Code = Errors.No_Error then
         Push
           (Self,
            (Kind                => Variant_Container,
             Declared            => Length,
             Indefinite          => Payload.Indefinite,
             Envelope_Indefinite => Envelope.Indefinite,
             others              => <>),
            Error);
      end if;
   end Begin_Variant;

   overriding
   procedure End_Variant
     (Self : in out Reader; Error : in out Errors.Error_Info) is
      Envelope_Indefinite : Boolean;
   begin
      Require_Ready (Self, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.Depth = 0
        or else Self.Stack (Self.Depth).Kind /= Variant_Container
        or else Self.Stack (Self.Depth).Child /= No_Child
        or else not Self.Stack (Self.Depth).Exhausted
      then
         Fail (Self, Errors.Invalid_State, Error);
         return;
      end if;
      Envelope_Indefinite := Self.Stack (Self.Depth).Envelope_Indefinite;
      if Self.Stack (Self.Depth).Indefinite then
         Consume_Break (Self, Errors.Syntax_Error, Error);
      end if;
      if Error.Code = Errors.No_Error and then Envelope_Indefinite then
         Consume_Break (Self, Errors.Invalid_Value, Error);
      end if;
      Finish_Container (Self, Variant_Container, Error);
   end End_Variant;
end Flyology_Serde.Deserializers.CBOR;
