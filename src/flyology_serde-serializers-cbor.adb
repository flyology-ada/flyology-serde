with Ada.Unchecked_Conversion;
with Flyology_Serde.UTF_8;

package body Flyology_Serde.Serializers.CBOR is
   use type Ada.Streams.Stream_Element_Offset;
   use type Data_Model.Float_64_Category;
   use type Errors.Error_Code;
   use type Interfaces.Integer_64;
   use type Interfaces.Unsigned_64;

   subtype Byte is Ada.Streams.Stream_Element;
   subtype Byte_Offset is Ada.Streams.Stream_Element_Offset;
   subtype Byte_Array is Ada.Streams.Stream_Element_Array;
   subtype Major_Type is Natural range 0 .. 7;

   function Float_Bits is new Ada.Unchecked_Conversion
     (Interfaces.IEEE_Float_64, Interfaces.Unsigned_64);

   procedure Append
     (Self  : in out Writer_Base'Class;
      Value : Byte_Array;
      Error : in out Errors.Error_Info) is
   begin
      Emit (Self, Value, Error);
   end Append;

   procedure Fail
     (Self  : in out Writer_Base;
      Code  : Errors.Error_Code;
      Error : in out Errors.Error_Info) is
   begin
      Self.Failed := True;
      Self.Finalized := False;
      Errors.Fail (Error, Code);
   end Fail;

   procedure Guard_Event
     (Self    : in out Writer_Base;
      Allowed : out Boolean;
      Error   : in out Errors.Error_Info) is
   begin
      Allowed := False;
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.Failed or else Self.Finalized then
         Errors.Fail (Error, Errors.Invalid_State);
      else
         Allowed := True;
      end if;
   end Guard_Event;

   procedure Emit
     (Self  : in out Writer_Base;
      Value : Byte_Array;
      Error : in out Errors.Error_Info)
   is
      pragma Unreferenced (Value);
   begin
      Fail (Self, Errors.Invalid_State, Error);
   end Emit;

   procedure Emit_Byte
     (Self  : in out Writer_Base'Class;
      Value : Byte;
      Error : in out Errors.Error_Info) is
   begin
      Append (Self, Byte_Array'[1 => Value], Error);
   end Emit_Byte;

   procedure Emit_Head
     (Self     : in out Writer_Base'Class;
      Major    : Major_Type;
      Argument : Interfaces.Unsigned_64;
      Error    : in out Errors.Error_Info)
   is
      Buffer : Byte_Array (1 .. 9) := [others => 0];
      Last   : Byte_Offset;

      function Octet (Shift : Natural) return Byte
      is (Byte
            (Interfaces.Shift_Right (Argument, Shift)
             and Interfaces.Unsigned_64'(16#FF#)));
   begin
      if Argument < 24 then
         Last := 1;
         Buffer (1) := Byte (Major * 32 + Natural (Argument));
      elsif Argument <= 16#FF# then
         Last := 2;
         Buffer (1) := Byte (Major * 32 + 24);
         Buffer (2) := Octet (0);
      elsif Argument <= 16#FFFF# then
         Last := 3;
         Buffer (1) := Byte (Major * 32 + 25);
         Buffer (2) := Octet (8);
         Buffer (3) := Octet (0);
      elsif Argument <= 16#FFFF_FFFF# then
         Last := 5;
         Buffer (1) := Byte (Major * 32 + 26);
         for Index in Byte_Offset range 2 .. 5 loop
            Buffer (Index) := Octet (Natural (5 - Index) * 8);
         end loop;
      else
         Last := 9;
         Buffer (1) := Byte (Major * 32 + 27);
         for Index in Byte_Offset range 2 .. 9 loop
            Buffer (Index) := Octet (Natural (9 - Index) * 8);
         end loop;
      end if;
      Append (Self, Buffer (1 .. Last), Error);
   end Emit_Head;

   procedure Increment
     (Value : in out Natural;
      Self  : in out Writer_Base;
      Error : in out Errors.Error_Info) is
   begin
      if Value = Natural'Last then
         Fail (Self, Errors.Capacity_Exceeded, Error);
      else
         Value := Value + 1;
      end if;
   end Increment;

   procedure Before_Value
     (Self : in out Writer_Base; Error : in out Errors.Error_Info)
   is
      Allowed : Boolean;
   begin
      Guard_Event (Self, Allowed, Error);
      if not Allowed then
         return;
      elsif Self.Depth = 0 then
         if Self.Root_Written then
            Fail (Self, Errors.Invalid_State, Error);
         else
            Self.Root_Written := True;
         end if;
         return;
      end if;

      case Self.Stack (Self.Depth).Kind is
         when Optional_Container | Sequence_Container =>
            if Self.Stack (Self.Depth).Expected_Known
              and then Self.Stack (Self.Depth).Observed_Items
                       = Self.Stack (Self.Depth).Expected_Items
            then
               Fail (Self, Errors.Invalid_State, Error);
            end if;

         when Map_Container                         =>
            if not Self.Stack (Self.Depth).Waiting_For_Value then
               if Self.Stack (Self.Depth).Expected_Known
                 and then Self.Stack (Self.Depth).Observed_Items
                          = Self.Stack (Self.Depth).Expected_Items
               then
                  Fail (Self, Errors.Invalid_State, Error);
                  return;
               end if;
               Self.Stack (Self.Depth).Map_Child_Is_Value := False;
            else
               Self.Stack (Self.Depth).Map_Child_Is_Value := True;
            end if;

         when Record_Container | Variant_Container =>
            if not Self.Stack (Self.Depth).Waiting_For_Value then
               Fail (Self, Errors.Invalid_State, Error);
            end if;
      end case;
   end Before_Value;

   procedure After_Value
     (Self : in out Writer_Base; Error : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error
        or else Self.Failed
        or else Self.Depth = 0
      then
         return;
      end if;

      case Self.Stack (Self.Depth).Kind is
         when Optional_Container | Sequence_Container =>
            Increment (Self.Stack (Self.Depth).Observed_Items, Self, Error);

         when Map_Container                           =>
            if Self.Stack (Self.Depth).Map_Child_Is_Value then
               Self.Stack (Self.Depth).Waiting_For_Value := False;
               Increment
                 (Self.Stack (Self.Depth).Observed_Items, Self, Error);
            else
               Self.Stack (Self.Depth).Waiting_For_Value := True;
            end if;

         when Record_Container | Variant_Container    =>
            Self.Stack (Self.Depth).Waiting_For_Value := False;
            Increment (Self.Stack (Self.Depth).Observed_Items, Self, Error);
      end case;
   end After_Value;

   procedure Push
     (Self     : in out Writer_Base;
      Kind     : Container_Kind;
      Expected : Data_Model.Length_Information;
      Error    : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.Depth = Policies.Maximum_Supported_Nesting then
         Fail (Self, Errors.Depth_Exceeded, Error);
      else
         Self.Depth := Self.Depth + 1;
         Self.Stack (Self.Depth) :=
           (Kind           => Kind,
            Expected_Known => Expected.Known,
            Expected_Items => Expected.Length,
            others         => <>);
      end if;
   end Push;

   procedure Pop
     (Self  : in out Writer_Base;
      Kind  : Container_Kind;
      Error : in out Errors.Error_Info)
   is
      Allowed : Boolean;
   begin
      Guard_Event (Self, Allowed, Error);
      if not Allowed then
         return;
      elsif Self.Depth = 0
        or else Self.Stack (Self.Depth).Kind /= Kind
        or else Self.Stack (Self.Depth).Waiting_For_Value
        or else (Self.Stack (Self.Depth).Expected_Known
                 and then Self.Stack (Self.Depth).Observed_Items
                          /= Self.Stack (Self.Depth).Expected_Items)
      then
         Fail (Self, Errors.Invalid_State, Error);
         return;
      end if;

      if not Self.Stack (Self.Depth).Expected_Known then
         Emit_Byte (Writer_Base'Class (Self), 16#FF#, Error);
      end if;
      if Error.Code = Errors.No_Error then
         Self.Stack (Self.Depth) := (others => <>);
         Self.Depth := Self.Depth - 1;
         After_Value (Self, Error);
      end if;
   end Pop;

   procedure Emit_Text
     (Self  : in out Writer_Base'Class;
      Value : String;
      Error : in out Errors.Error_Info)
   is
      Buffer : Byte_Array (1 .. 256);
      Used   : Natural := 0;
   begin
      if not UTF_8.Is_Valid (Value) then
         Fail (Writer_Base (Self), Errors.Invalid_Text, Error);
         return;
      end if;

      Emit_Head (Self, 3, Interfaces.Unsigned_64 (Value'Length), Error);
      for Item of Value loop
         exit when Error.Code /= Errors.No_Error;
         Used := Used + 1;
         Buffer (Byte_Offset (Used)) := Byte (Character'Pos (Item));
         if Used = Buffer'Length then
            Append (Self, Buffer, Error);
            Used := 0;
         end if;
      end loop;
      if Error.Code = Errors.No_Error and then Used > 0 then
         Append (Self, Buffer (1 .. Byte_Offset (Used)), Error);
      end if;
   end Emit_Text;

   procedure Reset_Common (Self : in out Writer_Base) is
   begin
      Self.Stack := [others => <>];
      Self.Depth := 0;
      Self.Root_Written := False;
      Self.Failed := False;
      Self.Finalized := False;
   end Reset_Common;

   function Complete (Self : Writer_Base) return Boolean
   is (Self.Finalized and then not Self.Failed);

   overriding
   function State (Self : Writer_Base) return Serialization.Serializer_State
   is
     (if Self.Failed then Serialization.Poisoned
      elsif Self.Finalized then Serialization.Finished
      elsif Self.Root_Written then Serialization.Active
      else Serialization.Ready);

   overriding
   procedure Finish_Document
     (Self : in out Writer_Base; Error : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.Failed or else Self.Finalized then
         Errors.Fail (Error, Errors.Invalid_State);
      elsif not Self.Root_Written or else Self.Depth /= 0
      then
         Fail (Self, Errors.Invalid_State, Error);
      else
         Self.Finalized := True;
      end if;
   end Finish_Document;

   overriding
   procedure Abort_Document (Self : in out Writer_Base) is
   begin
      Self.Stack := [others => <>];
      Self.Depth := 0;
      Self.Finalized := False;
      Self.Failed := True;
   exception
      when others =>
         null;
   end Abort_Document;

   overriding
   function Capabilities
     (Self : Writer_Base) return Data_Model.Format_Capabilities
   is
      pragma Unreferenced (Self);
   begin
      return Data_Model.All_Capabilities;
   end Capabilities;

   overriding
   procedure Put_Null
     (Self : in out Writer_Base; Error : in out Errors.Error_Info) is
   begin
      Before_Value (Self, Error);
      Emit_Byte (Writer_Base'Class (Self), 16#F6#, Error);
      After_Value (Self, Error);
   end Put_Null;

   overriding
   procedure Put_Boolean
     (Self  : in out Writer_Base;
      Value : Boolean;
      Error : in out Errors.Error_Info) is
   begin
      Before_Value (Self, Error);
      Emit_Byte
        (Writer_Base'Class (Self),
         (if Value then 16#F5# else 16#F4#),
         Error);
      After_Value (Self, Error);
   end Put_Boolean;

   overriding
   procedure Put_Signed
     (Self  : in out Writer_Base;
      Value : Interfaces.Integer_64;
      Error : in out Errors.Error_Info) is
   begin
      Before_Value (Self, Error);
      if Value >= 0 then
         Emit_Head
           (Writer_Base'Class (Self),
            0,
            Interfaces.Unsigned_64 (Value),
            Error);
      else
         Emit_Head
           (Writer_Base'Class (Self),
            1,
            Interfaces.Unsigned_64 (-(Value + 1)),
            Error);
      end if;
      After_Value (Self, Error);
   end Put_Signed;

   overriding
   procedure Put_Unsigned
     (Self  : in out Writer_Base;
      Value : Interfaces.Unsigned_64;
      Error : in out Errors.Error_Info) is
   begin
      Before_Value (Self, Error);
      Emit_Head (Writer_Base'Class (Self), 0, Value, Error);
      After_Value (Self, Error);
   end Put_Unsigned;

   overriding
   procedure Put_Float_64
     (Self  : in out Writer_Base;
      Value : Data_Model.Float_64_Value;
      Error : in out Errors.Error_Info)
   is
      Bits   : Interfaces.Unsigned_64;
      Buffer : Byte_Array (1 .. 9);
   begin
      case Data_Model.Category (Value) is
         when Data_Model.Finite_Float      =>
            Bits := Float_Bits (Data_Model.Finite_Value (Value));
         when Data_Model.Positive_Infinity =>
            Bits := 16#7FF0_0000_0000_0000#;
         when Data_Model.Negative_Infinity =>
            Bits := 16#FFF0_0000_0000_0000#;
         when Data_Model.Not_A_Number      =>
            Bits := 16#7FF8_0000_0000_0000#;
      end case;
      Before_Value (Self, Error);
      Buffer (1) := 16#FB#;
      for Index in Byte_Offset range 2 .. 9 loop
         Buffer (Index) :=
           Byte
             (Interfaces.Shift_Right (Bits, Natural (9 - Index) * 8)
              and Interfaces.Unsigned_64'(16#FF#));
      end loop;
      Append (Writer_Base'Class (Self), Buffer, Error);
      After_Value (Self, Error);
   end Put_Float_64;

   overriding
   procedure Put_Text
     (Self  : in out Writer_Base;
     Value : String;
      Error : in out Errors.Error_Info) is
      Allowed : Boolean;
   begin
      Guard_Event (Self, Allowed, Error);
      if not Allowed then
         return;
      end if;
      if not UTF_8.Is_Valid (Value) then
         Fail (Self, Errors.Invalid_Text, Error);
         return;
      end if;
      Before_Value (Self, Error);
      Emit_Text (Writer_Base'Class (Self), Value, Error);
      After_Value (Self, Error);
   end Put_Text;

   overriding
   procedure Put_Bytes
     (Self  : in out Writer_Base;
      Value : Byte_Array;
      Error : in out Errors.Error_Info) is
   begin
      Before_Value (Self, Error);
      Emit_Head
        (Writer_Base'Class (Self),
         2,
         Interfaces.Unsigned_64 (Value'Length),
         Error);
      Append (Writer_Base'Class (Self), Value, Error);
      After_Value (Self, Error);
   end Put_Bytes;

   overriding
   procedure Begin_Optional
     (Self    : in out Writer_Base;
      Present : Boolean;
      Error   : in out Errors.Error_Info) is
   begin
      Before_Value (Self, Error);
      Emit_Head
        (Writer_Base'Class (Self),
         4,
         Interfaces.Unsigned_64 (1 + Boolean'Pos (Present)),
         Error);
      Emit_Head
        (Writer_Base'Class (Self),
         0,
         Interfaces.Unsigned_64 (Boolean'Pos (Present)),
         Error);
      Push
        (Self,
         Optional_Container,
         Data_Model.Known_Length (Boolean'Pos (Present)),
         Error);
   end Begin_Optional;

   overriding
   procedure End_Optional
     (Self : in out Writer_Base; Error : in out Errors.Error_Info) is
   begin
      Pop (Self, Optional_Container, Error);
   end End_Optional;

   overriding
   procedure Begin_Sequence
     (Self   : in out Writer_Base;
      Length : Data_Model.Length_Information;
      Error  : in out Errors.Error_Info) is
   begin
      Before_Value (Self, Error);
      if Length.Known then
         Emit_Head
           (Writer_Base'Class (Self),
            4,
            Interfaces.Unsigned_64 (Length.Length),
            Error);
      else
         Emit_Byte (Writer_Base'Class (Self), 16#9F#, Error);
      end if;
      Push (Self, Sequence_Container, Length, Error);
   end Begin_Sequence;

   overriding
   procedure End_Sequence
     (Self : in out Writer_Base; Error : in out Errors.Error_Info) is
   begin
      Pop (Self, Sequence_Container, Error);
   end End_Sequence;

   overriding
   procedure Begin_Map
     (Self   : in out Writer_Base;
      Length : Data_Model.Length_Information;
      Error  : in out Errors.Error_Info) is
   begin
      Before_Value (Self, Error);
      if Length.Known then
         Emit_Head
           (Writer_Base'Class (Self),
            5,
            Interfaces.Unsigned_64 (Length.Length),
            Error);
      else
         Emit_Byte (Writer_Base'Class (Self), 16#BF#, Error);
      end if;
      Push (Self, Map_Container, Length, Error);
   end Begin_Map;

   overriding
   procedure End_Map
     (Self : in out Writer_Base; Error : in out Errors.Error_Info) is
   begin
      Pop (Self, Map_Container, Error);
   end End_Map;

   overriding
   procedure Begin_Record
     (Self        : in out Writer_Base;
      Type_Name   : String;
      Field_Count : Natural;
      Error       : in out Errors.Error_Info)
   is
      pragma Unreferenced (Type_Name);
   begin
      Before_Value (Self, Error);
      Emit_Head
        (Writer_Base'Class (Self),
         5,
         Interfaces.Unsigned_64 (Field_Count),
         Error);
      Push
        (Self, Record_Container, Data_Model.Known_Length (Field_Count), Error);
   end Begin_Record;

   overriding
   procedure Put_Field
     (Self  : in out Writer_Base;
      Name  : String;
      Error : in out Errors.Error_Info)
   is
      Allowed : Boolean;
   begin
      Guard_Event (Self, Allowed, Error);
      if not Allowed then
         return;
      elsif not UTF_8.Is_Valid (Name) then
         Fail (Self, Errors.Invalid_Text, Error);
      elsif Self.Depth = 0
        or else Self.Stack (Self.Depth).Kind
                not in Record_Container | Variant_Container
        or else Self.Stack (Self.Depth).Waiting_For_Value
        or else (Self.Stack (Self.Depth).Expected_Known
                 and then Self.Stack (Self.Depth).Observed_Items
                          = Self.Stack (Self.Depth).Expected_Items)
      then
         Fail (Self, Errors.Invalid_State, Error);
      else
         Emit_Text (Writer_Base'Class (Self), Name, Error);
         if Error.Code = Errors.No_Error then
            Self.Stack (Self.Depth).Waiting_For_Value := True;
         end if;
      end if;
   end Put_Field;

   overriding
   procedure End_Record
     (Self : in out Writer_Base; Error : in out Errors.Error_Info) is
   begin
      Pop (Self, Record_Container, Error);
   end End_Record;

   overriding
   procedure Put_Enumeration
     (Self         : in out Writer_Base;
      Type_Name    : String;
      Literal_Name : String;
      Error        : in out Errors.Error_Info)
   is
      pragma Unreferenced (Type_Name);
   begin
      Put_Text (Self, Literal_Name, Error);
   end Put_Enumeration;

   overriding
   procedure Begin_Variant
     (Self             : in out Writer_Base;
      Type_Name        : String;
      Alternative_Name : String;
      Field_Count      : Natural;
      Error            : in out Errors.Error_Info)
   is
      pragma Unreferenced (Type_Name);
      Allowed : Boolean;
   begin
      Guard_Event (Self, Allowed, Error);
      if not Allowed then
         return;
      end if;
      if not UTF_8.Is_Valid (Alternative_Name) then
         Fail (Self, Errors.Invalid_Text, Error);
         return;
      end if;
      Before_Value (Self, Error);
      Emit_Head (Writer_Base'Class (Self), 4, 2, Error);
      Emit_Text (Writer_Base'Class (Self), Alternative_Name, Error);
      Emit_Head
        (Writer_Base'Class (Self),
         5,
         Interfaces.Unsigned_64 (Field_Count),
         Error);
      Push
        (Self,
         Variant_Container,
         Data_Model.Known_Length (Field_Count),
         Error);
   end Begin_Variant;

   overriding
   procedure End_Variant
     (Self : in out Writer_Base; Error : in out Errors.Error_Info) is
   begin
      Pop (Self, Variant_Container, Error);
   end End_Variant;

   overriding
   procedure Emit
     (Self  : in out Bounded_Writer;
      Value : Byte_Array;
      Error : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error or else Self.Failed then
         return;
      elsif Self.Length > Self.Capacity
        or else Value'Length > Self.Capacity - Self.Length
      then
         Fail (Writer_Base (Self), Errors.Capacity_Exceeded, Error);
      elsif Value'Length > 0 then
         for Item of Value loop
            Self.Length := Self.Length + 1;
            Self.Buffer (Self.Length) := Item;
         end loop;
      end if;
   end Emit;

   procedure Reset (Self : in out Bounded_Writer) is
   begin
      Reset_Common (Writer_Base (Self));
      Self.Buffer := [others => 0];
      Self.Length := 0;
   end Reset;

   function Written_Length (Self : Bounded_Writer) return Natural
   is (Self.Length);

   procedure Copy_Output
     (Self   : Bounded_Writer;
      Target : out Byte_Array;
      Length : out Natural;
      Error  : in out Errors.Error_Info) is
   begin
      Target := [others => 0];
      Length := 0;
      if Error.Code /= Errors.No_Error then
         return;
      elsif not Complete (Writer_Base (Self)) then
         Errors.Fail (Error, Errors.Invalid_State);
      elsif Target'Length < Self.Length then
         Errors.Fail (Error, Errors.Capacity_Exceeded);
      elsif Self.Length > 0 then
         for Index in Positive range 1 .. Self.Length loop
            Target (Target'First + Byte_Offset (Index - 1)) :=
              Self.Buffer (Index);
         end loop;
         Length := Self.Length;
      end if;
   end Copy_Output;

   function Is_Complete (Self : Bounded_Writer) return Boolean
   is (Complete (Writer_Base (Self)));

   overriding
   procedure Emit
     (Self  : in out Allocating_Writer;
      Value : Byte_Array;
      Error : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error or else Self.Failed then
         return;
      end if;
      for Item of Value loop
         Self.Buffer.Append (Item);
      end loop;
   exception
      when Storage_Error =>
         Self.Failed := True;
         raise;
      when Constraint_Error =>
         Fail (Writer_Base (Self), Errors.Capacity_Exceeded, Error);
   end Emit;

   procedure Reset (Self : in out Allocating_Writer) is
   begin
      Reset_Common (Writer_Base (Self));
      Self.Buffer.Clear;
   end Reset;

   function Output (Self : Allocating_Writer) return Byte_Array is
   begin
      if not Complete (Writer_Base (Self)) then
         return [1 .. 0 => 0];
      end if;

      return Result : Byte_Array (1 .. Byte_Offset (Self.Buffer.Length)) do
         declare
            Cursor : Byte_Offset := Result'First;
         begin
            for Item of Self.Buffer loop
               Result (Cursor) := Item;
               Cursor := Cursor + 1;
            end loop;
         end;
      end return;
   end Output;

   function Is_Complete (Self : Allocating_Writer) return Boolean
   is (Complete (Writer_Base (Self)));
end Flyology_Serde.Serializers.CBOR;
