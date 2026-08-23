with Ada.Strings;
with Ada.Strings.Fixed;
with Flyology_Serde.UTF_8;

package body Flyology_Serde.Serializers.JSON is
   use type Errors.Error_Code;
   use type Interfaces.IEEE_Float_64;

   Hex_Digits : constant String := "0123456789ABCDEF";

   procedure Append
     (Self  : in out Writer_Base'Class;
      Value : String;
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
      Errors.Fail (Error, Code);
   end Fail;

   procedure Emit
     (Self  : in out Writer_Base;
      Value : String;
      Error : in out Errors.Error_Info)
   is
      pragma Unreferenced (Value);
   begin
      Fail (Self, Errors.Invalid_State, Error);
   end Emit;

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
     (Self : in out Writer_Base; Error : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error or else Self.Failed then
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
         when Optional_Container                   =>
            if Self.Stack (Self.Depth).Expected_Known
              and then Self.Stack (Self.Depth).Observed_Items
                       = Self.Stack (Self.Depth).Expected_Items
            then
               Fail (Self, Errors.Invalid_State, Error);
            else
               Append (Writer_Base'Class (Self), ",", Error);
            end if;

         when Sequence_Container                   =>
            if Self.Stack (Self.Depth).Expected_Known
              and then Self.Stack (Self.Depth).Observed_Items
                       = Self.Stack (Self.Depth).Expected_Items
            then
               Fail (Self, Errors.Invalid_State, Error);
            elsif Self.Stack (Self.Depth).Observed_Items > 0 then
               Append (Writer_Base'Class (Self), ",", Error);
            end if;

         when Map_Container                        =>
            if not Self.Stack (Self.Depth).Waiting_For_Value then
               if Self.Stack (Self.Depth).Expected_Known
                 and then Self.Stack (Self.Depth).Observed_Items
                          = Self.Stack (Self.Depth).Expected_Items
               then
                  Fail (Self, Errors.Invalid_State, Error);
                  return;
               elsif Self.Stack (Self.Depth).Observed_Items > 0 then
                  Append (Writer_Base'Class (Self), ",", Error);
               end if;
               Append (Writer_Base'Class (Self), "[", Error);
               Self.Stack (Self.Depth).Map_Child_Is_Value := False;
            else
               Append (Writer_Base'Class (Self), ",", Error);
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
               Append (Writer_Base'Class (Self), "]", Error);
               if Error.Code = Errors.No_Error then
                  Self.Stack (Self.Depth).Waiting_For_Value := False;
                  Increment
                    (Self.Stack (Self.Depth).Observed_Items, Self, Error);
               end if;
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
      Close : String;
      Error : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error or else Self.Failed then
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

      Append (Writer_Base'Class (Self), Close, Error);
      if Error.Code = Errors.No_Error then
         Self.Stack (Self.Depth) := (others => <>);
         Self.Depth := Self.Depth - 1;
         After_Value (Self, Error);
      end if;
   end Pop;

   procedure Emit_Quoted
     (Self  : in out Writer_Base;
      Value : String;
      Error : in out Errors.Error_Info) is
   begin
      if not UTF_8.Is_Valid (Value) then
         Fail (Self, Errors.Invalid_Text, Error);
         return;
      end if;

      Append (Writer_Base'Class (Self), String'[1 => '"'], Error);
      for Item of Value loop
         exit when Error.Code /= Errors.No_Error;
         case Item is
            when '"' | '\'                                =>
               Append
                 (Writer_Base'Class (Self),
                  String'[1 => '\', 2 => Item],
                  Error);

            when Character'Val (8)                        =>
               Append (Writer_Base'Class (Self), "\b", Error);

            when Character'Val (9)                        =>
               Append (Writer_Base'Class (Self), "\t", Error);

            when Character'Val (10)                       =>
               Append (Writer_Base'Class (Self), "\n", Error);

            when Character'Val (12)                       =>
               Append (Writer_Base'Class (Self), "\f", Error);

            when Character'Val (13)                       =>
               Append (Writer_Base'Class (Self), "\r", Error);

            when Character'Val (0) .. Character'Val (7)
               | Character'Val (11)
               | Character'Val (14) .. Character'Val (31) =>
               Append
                 (Writer_Base'Class (Self),
                  "\u00"
                  & Hex_Digits (Character'Pos (Item) / 16 + 1)
                  & Hex_Digits (Character'Pos (Item) mod 16 + 1),
                  Error);

            when others                                   =>
               Append (Writer_Base'Class (Self), String'[1 => Item], Error);
         end case;
      end loop;
      if Error.Code = Errors.No_Error then
         Append (Writer_Base'Class (Self), String'[1 => '"'], Error);
      end if;
   end Emit_Quoted;

   procedure Reset_Common (Self : in out Writer_Base) is
   begin
      Self.Stack := [others => <>];
      Self.Depth := 0;
      Self.Root_Written := False;
      Self.Failed := False;
   end Reset_Common;

   function Complete (Self : Writer_Base) return Boolean
   is (Self.Root_Written and then Self.Depth = 0 and then not Self.Failed);

   overriding
   function Capabilities
     (Self : Writer_Base) return Data_Model.Format_Capabilities
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
   procedure Put_Null
     (Self : in out Writer_Base; Error : in out Errors.Error_Info) is
   begin
      Before_Value (Self, Error);
      Append (Writer_Base'Class (Self), "null", Error);
      After_Value (Self, Error);
   end Put_Null;

   overriding
   procedure Put_Boolean
     (Self  : in out Writer_Base;
      Value : Boolean;
      Error : in out Errors.Error_Info) is
   begin
      Before_Value (Self, Error);
      if Value then
         Append (Writer_Base'Class (Self), "true", Error);
      else
         Append (Writer_Base'Class (Self), "false", Error);
      end if;
      After_Value (Self, Error);
   end Put_Boolean;

   overriding
   procedure Put_Signed
     (Self  : in out Writer_Base;
      Value : Interfaces.Integer_64;
      Error : in out Errors.Error_Info) is
   begin
      Before_Value (Self, Error);
      Append
        (Writer_Base'Class (Self),
         Ada.Strings.Fixed.Trim
           (Interfaces.Integer_64'Image (Value), Ada.Strings.Both),
         Error);
      After_Value (Self, Error);
   end Put_Signed;

   overriding
   procedure Put_Unsigned
     (Self  : in out Writer_Base;
      Value : Interfaces.Unsigned_64;
      Error : in out Errors.Error_Info) is
   begin
      Before_Value (Self, Error);
      Append
        (Writer_Base'Class (Self),
         Ada.Strings.Fixed.Trim
           (Interfaces.Unsigned_64'Image (Value), Ada.Strings.Both),
         Error);
      After_Value (Self, Error);
   end Put_Unsigned;

   overriding
   procedure Put_Float_64
     (Self  : in out Writer_Base;
      Value : Interfaces.IEEE_Float_64;
      Error : in out Errors.Error_Info) is
   begin
      if Value /= Value
        or else Value < Interfaces.IEEE_Float_64'First
        or else Value > Interfaces.IEEE_Float_64'Last
      then
         Fail (Self, Errors.Unsupported_Value, Error);
         return;
      end if;

      Before_Value (Self, Error);
      Append
        (Writer_Base'Class (Self),
         Ada.Strings.Fixed.Trim
           (Interfaces.IEEE_Float_64'Image (Value), Ada.Strings.Both),
         Error);
      After_Value (Self, Error);
   end Put_Float_64;

   overriding
   procedure Put_Text
     (Self  : in out Writer_Base;
      Value : String;
      Error : in out Errors.Error_Info) is
   begin
      if not UTF_8.Is_Valid (Value) then
         Fail (Self, Errors.Invalid_Text, Error);
         return;
      end if;
      Before_Value (Self, Error);
      Emit_Quoted (Self, Value, Error);
      After_Value (Self, Error);
   end Put_Text;

   overriding
   procedure Put_Bytes
     (Self  : in out Writer_Base;
      Value : Ada.Streams.Stream_Element_Array;
      Error : in out Errors.Error_Info) is
   begin
      Before_Value (Self, Error);
      Append (Writer_Base'Class (Self), "{""$bytes"":""", Error);
      for Item of Value loop
         exit when Error.Code /= Errors.No_Error;
         Append
           (Writer_Base'Class (Self),
            String'
              [1 => Hex_Digits (Natural (Item) / 16 + 1),
               2 => Hex_Digits (Natural (Item) mod 16 + 1)],
            Error);
      end loop;
      if Error.Code = Errors.No_Error then
         Append (Writer_Base'Class (Self), String'[1 => '"', 2 => '}'], Error);
      end if;
      After_Value (Self, Error);
   end Put_Bytes;

   overriding
   procedure Begin_Optional
     (Self    : in out Writer_Base;
      Present : Boolean;
      Error   : in out Errors.Error_Info) is
   begin
      Before_Value (Self, Error);
      if Present then
         Append (Writer_Base'Class (Self), "[1", Error);
      else
         Append (Writer_Base'Class (Self), "[0", Error);
      end if;
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
      Pop (Self, Optional_Container, "]", Error);
   end End_Optional;

   overriding
   procedure Begin_Sequence
     (Self   : in out Writer_Base;
      Length : Data_Model.Length_Information;
      Error  : in out Errors.Error_Info) is
   begin
      Before_Value (Self, Error);
      Append (Writer_Base'Class (Self), "[", Error);
      Push (Self, Sequence_Container, Length, Error);
   end Begin_Sequence;

   overriding
   procedure End_Sequence
     (Self : in out Writer_Base; Error : in out Errors.Error_Info) is
   begin
      Pop (Self, Sequence_Container, "]", Error);
   end End_Sequence;

   overriding
   procedure Begin_Map
     (Self   : in out Writer_Base;
      Length : Data_Model.Length_Information;
      Error  : in out Errors.Error_Info) is
   begin
      Before_Value (Self, Error);
      Append (Writer_Base'Class (Self), "[", Error);
      Push (Self, Map_Container, Length, Error);
   end Begin_Map;

   overriding
   procedure End_Map
     (Self : in out Writer_Base; Error : in out Errors.Error_Info) is
   begin
      Pop (Self, Map_Container, "]", Error);
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
      Append (Writer_Base'Class (Self), "{", Error);
      Push
        (Self, Record_Container, Data_Model.Known_Length (Field_Count), Error);
   end Begin_Record;

   overriding
   procedure Put_Field
     (Self  : in out Writer_Base;
      Name  : String;
      Error : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error or else Self.Failed then
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
         if Self.Stack (Self.Depth).Observed_Items > 0 then
            Append (Writer_Base'Class (Self), ",", Error);
         end if;
         Emit_Quoted (Self, Name, Error);
         Append (Writer_Base'Class (Self), ":", Error);
         if Error.Code = Errors.No_Error then
            Self.Stack (Self.Depth).Waiting_For_Value := True;
         end if;
      end if;
   end Put_Field;

   overriding
   procedure End_Record
     (Self : in out Writer_Base; Error : in out Errors.Error_Info) is
   begin
      Pop (Self, Record_Container, "}", Error);
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
   begin
      if not UTF_8.Is_Valid (Alternative_Name) then
         Fail (Self, Errors.Invalid_Text, Error);
         return;
      end if;
      Before_Value (Self, Error);
      Append (Writer_Base'Class (Self), "[", Error);
      Emit_Quoted (Self, Alternative_Name, Error);
      Append (Writer_Base'Class (Self), ",{", Error);
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
      Pop (Self, Variant_Container, "}]", Error);
   end End_Variant;

   overriding
   procedure Emit
     (Self  : in out Bounded_Writer;
      Value : String;
      Error : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error or else Self.Failed then
         return;
      elsif Self.Length > Self.Capacity
        or else Value'Length > Self.Capacity - Self.Length
      then
         Fail (Writer_Base (Self), Errors.Capacity_Exceeded, Error);
      elsif Value'Length > 0 then
         Self.Buffer (Self.Length + 1 .. Self.Length + Value'Length) := Value;
         Self.Length := Self.Length + Value'Length;
      end if;
   end Emit;

   procedure Reset (Self : in out Bounded_Writer) is
   begin
      Reset_Common (Writer_Base (Self));
      Self.Buffer := [others => ' '];
      Self.Length := 0;
   end Reset;

   function Written_Length (Self : Bounded_Writer) return Natural
   is (Self.Length);

   procedure Copy_Output
     (Self   : Bounded_Writer;
      Target : out String;
      Length : out Natural;
      Error  : in out Errors.Error_Info) is
   begin
      Target := [others => ' '];
      Length := Self.Length;
      if Error.Code /= Errors.No_Error then
         return;
      elsif Target'Length < Self.Length then
         Errors.Fail (Error, Errors.Capacity_Exceeded);
      elsif Self.Length > 0 then
         Target (Target'First .. Target'First + Self.Length - 1) :=
           Self.Buffer (1 .. Self.Length);
      end if;
   end Copy_Output;

   function Is_Complete (Self : Bounded_Writer) return Boolean
   is (Complete (Writer_Base (Self)));

   overriding
   procedure Emit
     (Self  : in out Allocating_Writer;
      Value : String;
      Error : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error or else Self.Failed then
         return;
      end if;
      Ada.Strings.Unbounded.Append (Self.Buffer, Value);
   exception
      when Storage_Error =>
         Fail (Writer_Base (Self), Errors.Capacity_Exceeded, Error);
   end Emit;

   procedure Reset (Self : in out Allocating_Writer) is
   begin
      Reset_Common (Writer_Base (Self));
      Ada.Strings.Unbounded.Set_Unbounded_String (Self.Buffer, "");
   end Reset;

   function Output (Self : Allocating_Writer) return String
   is (Ada.Strings.Unbounded.To_String (Self.Buffer));

   function Is_Complete (Self : Allocating_Writer) return Boolean
   is (Complete (Writer_Base (Self)));
end Flyology_Serde.Serializers.JSON;
