with Ada.Streams;
with Flyology_Serde.Adapters.Enumerations;
with Flyology_Serde.Adapters.Fixed_Arrays;
with Flyology_Serde.Adapters.Enumeration_Serializers;
with Flyology_Serde.Adapters.Fixed_Array_Serializers;
with Flyology_Serde.Adapters.Record_Serializers;
with Flyology_Serde.Adapters.Records;
with Flyology_Serde.Deserialization;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;
with Flyology_Serde.Serialization;
with Flyology_Serde.Serializers.CBOR;
with Flyology_Serde.Serializers.Counting;
with Flyology_Serde.Serializers.JSON;

procedure Serialization_Only_Adapter_Tests is
   package CBOR_Writers renames Flyology_Serde.Serializers.CBOR;
   package Counting renames Flyology_Serde.Serializers.Counting;
   package Errors renames Flyology_Serde.Errors;
   package JSON_Writers renames Flyology_Serde.Serializers.JSON;

   use type Ada.Streams.Stream_Element_Array;
   use type Errors.Error_Code;
   use type Errors.Path_Element_Kind;

   subtype Bytes is Ada.Streams.Stream_Element_Array;

   type Color is (Red, Green, Blue);
   for Color use (Red => 10, Green => 42, Blue => 99);

   type Color_Metadata_Mode is
     (Normal_Color_Metadata,
      Duplicate_Color_Name,
      Invalid_Color_Name,
      Overlong_Color_Name,
      Empty_Second_Color_Name,
      Raise_Color_Name,
      High_End_Color_Bounds,
      Shifted_Color_Bounds,
      Unstable_Color_Name);

   Active_Color_Metadata : Color_Metadata_Mode := Normal_Color_Metadata;
   Color_Name_Calls      : Natural := 0;
   Red_Name_Observations : Natural := 0;
   High_Red_Name : constant String
     (Positive'Last - 2 .. Positive'Last) := "red";
   High_Green_Name : constant String
     (Positive'Last - 4 .. Positive'Last) := "green";
   High_Blue_Name : constant String
     (Positive'Last - 3 .. Positive'Last) := "blue";
   High_Type_Name : constant String
     (Positive'Last - 4 .. Positive'Last) := "Color";

   function Color_Name (Value : Color) return String is
   begin
      Color_Name_Calls := Color_Name_Calls + 1;
      if Active_Color_Metadata = Raise_Color_Name and then Value = Red then
         raise Program_Error with "requested color metadata failure";
      end if;
      if Active_Color_Metadata = Unstable_Color_Name and then Value = Red then
         Red_Name_Observations := Red_Name_Observations + 1;
         return (if Red_Name_Observations = 1 then "red" else "rouge");
      elsif Active_Color_Metadata = Empty_Second_Color_Name and then Value = Red then
         Red_Name_Observations := Red_Name_Observations + 1;
         return (if Red_Name_Observations = 1 then "red" else "");
      elsif Active_Color_Metadata = High_End_Color_Bounds then
         return
           (case Value is
               when Red   => High_Red_Name,
               when Green => High_Green_Name,
               when Blue  => High_Blue_Name);
      elsif Active_Color_Metadata = Shifted_Color_Bounds then
         case Value is
            when Red =>
               return String'(7 => 'r', 8 => 'e', 9 => 'd');
            when Green =>
               return String'
                 (7 => 'g', 8 => 'r', 9 => 'e', 10 => 'e', 11 => 'n');
            when Blue =>
               return String'(7 => 'b', 8 => 'l', 9 => 'u', 10 => 'e');
         end case;
      end if;

      return
        (case Active_Color_Metadata is
            when Duplicate_Color_Name => "same",
            when Invalid_Color_Name   =>
              (if Value = Red
               then String'[1 => Character'Val (16#C0#)]
               else (if Value = Green then "green" else "blue")),
            when Overlong_Color_Name  =>
              (if Value = Red then "literal-name-too-long" else Color'Image (Value)),
            when others               =>
              (case Value is
                  when Red   => "red",
                  when Green => "green",
                  when Blue  => "blue"));
   end Color_Name;

   package Colors is new
     Flyology_Serde.Adapters.Enumeration_Serializers
       (Value_Type                  => Color,
        Type_Name                   => "Color",
        Maximum_Type_Name_Length    => 16,
        Maximum_Literals            => 3,
        Maximum_Literal_Name_Length => 16,
        Primary_Name                => Color_Name);

   package Too_Small_Colors is new
     Flyology_Serde.Adapters.Enumeration_Serializers
       (Value_Type                  => Color,
        Type_Name                   => "Color",
        Maximum_Type_Name_Length    => 16,
        Maximum_Literals            => 2,
        Maximum_Literal_Name_Length => 16,
        Primary_Name                => Color_Name);

   package Empty_Type_Colors is new
     Flyology_Serde.Adapters.Enumeration_Serializers
       (Value_Type                  => Color,
        Type_Name                   => "",
        Maximum_Type_Name_Length    => 16,
        Maximum_Literals            => 3,
        Maximum_Literal_Name_Length => 16,
        Primary_Name                => Color_Name);

   package Invalid_Type_Colors is new
     Flyology_Serde.Adapters.Enumeration_Serializers
       (Value_Type                  => Color,
        Type_Name                   => String'[1 => Character'Val (16#C0#)],
        Maximum_Type_Name_Length    => 16,
        Maximum_Literals            => 3,
        Maximum_Literal_Name_Length => 16,
        Primary_Name                => Color_Name);

   package Overlong_Type_Colors is new
     Flyology_Serde.Adapters.Enumeration_Serializers
       (Value_Type                  => Color,
        Type_Name                   => "type-name-too-long",
        Maximum_Type_Name_Length    => 16,
        Maximum_Literals            => 3,
        Maximum_Literal_Name_Length => 16,
        Primary_Name                => Color_Name);

   package Shifted_Type_Colors is new
     Flyology_Serde.Adapters.Enumeration_Serializers
       (Value_Type                  => Color,
        Type_Name                   =>
          String'(7 => 'C', 8 => 'o', 9 => 'l', 10 => 'o', 11 => 'r'),
        Maximum_Type_Name_Length    => 16,
        Maximum_Literals            => 3,
        Maximum_Literal_Name_Length => 16,
        Primary_Name                => Color_Name);

   package High_End_Type_Colors is new
     Flyology_Serde.Adapters.Enumeration_Serializers
       (Value_Type                  => Color,
        Type_Name                   => High_Type_Name,
        Maximum_Type_Name_Length    => 16,
        Maximum_Literals            => 3,
        Maximum_Literal_Name_Length => 16,
        Primary_Name                => Color_Name);

   type Position is (First, Second);
   for Position use (First => 7, Second => 19);

   type Palette is array (Position) of Color;

   type Empty_Position is range 1 .. 0;
   type Empty_Palette is array (Empty_Position) of Color;

   package Palettes is new
     Flyology_Serde.Adapters.Fixed_Array_Serializers
       (Index_Type        => Position,
        Element_Type      => Color,
        Array_Type        => Palette,
        Serialize_Element => Colors.Serialize_Value);

   package Empty_Palettes is new
     Flyology_Serde.Adapters.Fixed_Array_Serializers
       (Index_Type        => Empty_Position,
        Element_Type      => Color,
        Array_Type        => Empty_Palette,
        Serialize_Element => Colors.Serialize_Value);

   type Packet is record
      Shade   : Color;
      Samples : Palette;
   end record;

   type Packet_Field is (Shade_Field, Samples_Field);

   type Field_Metadata_Mode is
     (Normal_Field_Metadata,
      Duplicate_Field_Name,
      Invalid_Field_Name,
      Overlong_Field_Name,
      Empty_Second_Field_Name,
      Raise_Field_Name,
      Shifted_Field_Bounds,
      Unstable_Field_Name);

   Active_Field_Metadata   : Field_Metadata_Mode := Normal_Field_Metadata;
   Field_Name_Calls        : Natural := 0;
   Shade_Name_Observations : Natural := 0;

   function Field_Name (Field : Packet_Field) return String is
   begin
      Field_Name_Calls := Field_Name_Calls + 1;
      if Active_Field_Metadata = Raise_Field_Name and then Field = Shade_Field then
         raise Program_Error with "requested field metadata failure";
      end if;
      if Active_Field_Metadata = Unstable_Field_Name and then Field = Shade_Field then
         Shade_Name_Observations := Shade_Name_Observations + 1;
         return (if Shade_Name_Observations = 1 then "shade" else "tone");
      elsif Active_Field_Metadata = Empty_Second_Field_Name
        and then Field = Shade_Field
      then
         Shade_Name_Observations := Shade_Name_Observations + 1;
         return (if Shade_Name_Observations = 1 then "shade" else "");
      elsif Active_Field_Metadata = Shifted_Field_Bounds then
         case Field is
            when Shade_Field =>
               return String'
                 (7 => 's', 8 => 'h', 9 => 'a', 10 => 'd', 11 => 'e');
            when Samples_Field =>
               return String'
                 (7 => 's',
                  8 => 'a',
                  9 => 'm',
                  10 => 'p',
                  11 => 'l',
                  12 => 'e',
                  13 => 's');
         end case;
      end if;

      return
        (case Active_Field_Metadata is
            when Duplicate_Field_Name => "same",
            when Invalid_Field_Name   =>
              (if Field = Shade_Field
               then String'[1 => Character'Val (16#C0#)]
               else "samples"),
            when Overlong_Field_Name  =>
              (if Field = Shade_Field then "field-name-too-long" else "samples"),
            when others               =>
              (case Field is
                  when Shade_Field   => "shade",
                  when Samples_Field => "samples"));
   end Field_Name;

   procedure Serialize_Field
     (Item  : Packet;
      Field : Packet_Field;
      Into  : in out Flyology_Serde.Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
   begin
      case Field is
         when Shade_Field =>
            Colors.Serialize_Value (Item.Shade, Into, Error);
         when Samples_Field =>
            Palettes.Serialize_Value (Item.Samples, Into, Error);
      end case;
   end Serialize_Field;

   package Packets is new
     Flyology_Serde.Adapters.Record_Serializers
       (Source_Type               => Packet,
        Field_Ordinal             => Packet_Field,
        Type_Name                 => "Packet",
        Maximum_Type_Name_Length  => 16,
        Maximum_Fields            => 2,
        Maximum_Field_Name_Length => 16,
        Primary_Name              => Field_Name,
        Serialize_Field           => Serialize_Field);

   package Too_Small_Packets is new
     Flyology_Serde.Adapters.Record_Serializers
       (Source_Type               => Packet,
        Field_Ordinal             => Packet_Field,
        Type_Name                 => "Packet",
        Maximum_Type_Name_Length  => 16,
        Maximum_Fields            => 1,
        Maximum_Field_Name_Length => 16,
        Primary_Name              => Field_Name,
        Serialize_Field           => Serialize_Field);

   function No_Alias_Count (Value : Color) return Natural is
      pragma Unreferenced (Value);
   begin
      return 0;
   end No_Alias_Count;

   function No_Alias_Name
     (Value : Color; Position : Positive) return String
   is
      pragma Unreferenced (Value, Position);
   begin
      return "";
   end No_Alias_Name;

   function Matches_Color (Value : Color; Name : String) return Boolean is
     (Color_Name (Value) = Name);

   package Existing_Colors is new
     Flyology_Serde.Adapters.Enumerations
       (Value_Type                  => Color,
        Type_Name                   => "Color",
        Maximum_Type_Name_Length    => 16,
        Maximum_Literals            => 3,
        Maximum_Literal_Name_Length => 16,
        Maximum_Aliases_Per_Literal => 0,
        Primary_Name                => Color_Name,
        Alias_Count                 => No_Alias_Count,
        Alias_Name                  => No_Alias_Name,
        Matches_Literal             => Matches_Color);

   procedure Unused_Deserialize_Color
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out Color;
      Policy : Flyology_Serde.Policies.Decode_Policy;
      Error  : in out Errors.Error_Info)
   is
      pragma Unreferenced (From, Target, Policy);
   begin
      Errors.Fail (Error, Errors.Application_Error);
   end Unused_Deserialize_Color;

   package Existing_Palettes is new
     Flyology_Serde.Adapters.Fixed_Arrays
       (Index_Type          => Position,
        Element_Type        => Color,
        Array_Type          => Palette,
        Serialize_Element   => Existing_Colors.Serialize_Value,
        Deserialize_Element => Unused_Deserialize_Color);

   function No_Field_Alias_Count (Field : Packet_Field) return Natural is
      pragma Unreferenced (Field);
   begin
      return 0;
   end No_Field_Alias_Count;

   function No_Field_Alias_Name
     (Field : Packet_Field; Position : Positive) return String
   is
      pragma Unreferenced (Field, Position);
   begin
      return "";
   end No_Field_Alias_Name;

   function Matches_Packet_Field
     (Field : Packet_Field; Name : String) return Boolean is
     (Field_Name (Field) = Name);

   procedure Existing_Serialize_Field
     (Item  : Packet;
      Field : Packet_Field;
      Into  : in out Flyology_Serde.Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
   begin
      case Field is
         when Shade_Field =>
            Existing_Colors.Serialize_Value (Item.Shade, Into, Error);
         when Samples_Field =>
            Existing_Palettes.Serialize_Value (Item.Samples, Into, Error);
      end case;
   end Existing_Serialize_Field;

   type Unused_Packet_Builder is limited null record;

   procedure Unused_Deserialize_Field
     (From      : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target    : in out Unused_Packet_Builder;
      Field     : Packet_Field;
      Replacing : Boolean;
      Policy    : Flyology_Serde.Policies.Decode_Policy;
      Error     : in out Errors.Error_Info)
   is
      pragma Unreferenced (From, Target, Field, Replacing, Policy);
   begin
      Errors.Fail (Error, Errors.Application_Error);
   end Unused_Deserialize_Field;

   procedure Unused_Apply_Missing
     (Target  : in out Unused_Packet_Builder;
      Field   : Packet_Field;
      Policy  : Flyology_Serde.Policies.Decode_Policy;
      Applied : out Boolean;
      Error   : in out Errors.Error_Info)
   is
      pragma Unreferenced (Target, Field, Policy, Error);
   begin
      Applied := False;
   end Unused_Apply_Missing;

   procedure Unused_Finish
     (Target : in out Unused_Packet_Builder;
      Error  : in out Errors.Error_Info)
   is
      pragma Unreferenced (Target, Error);
   begin
      null;
   end Unused_Finish;

   package Existing_Packets is new
     Flyology_Serde.Adapters.Records
       (Source_Type               => Packet,
        Builder_Type              => Unused_Packet_Builder,
        Field_Ordinal             => Packet_Field,
        Type_Name                 => "Packet",
        Maximum_Type_Name_Length  => 16,
        Maximum_Fields            => 2,
        Maximum_Field_Name_Length => 16,
        Maximum_Aliases_Per_Field => 0,
        Primary_Name              => Field_Name,
        Alias_Count               => No_Field_Alias_Count,
        Alias_Name                => No_Field_Alias_Name,
        Matches_Field             => Matches_Packet_Field,
        Serialize_Field           => Existing_Serialize_Field,
        Deserialize_Field         => Unused_Deserialize_Field,
        Apply_Missing             => Unused_Apply_Missing,
        Finish_Candidate          => Unused_Finish);

   type Child_Failure_Mode is
     (No_Child_Failure, Fail_Child_With_Status, Raise_From_Child);

   Active_Child_Failure : Child_Failure_Mode := No_Child_Failure;

   procedure Serialize_Color_With_Failure
     (Item  : Color;
      Into  : in out Flyology_Serde.Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
   begin
      if Item = Blue then
         case Active_Child_Failure is
            when No_Child_Failure =>
               null;
            when Fail_Child_With_Status =>
               Errors.Fail (Error, Errors.Invalid_Value);
               return;
            when Raise_From_Child =>
               raise Program_Error with "requested child serialization failure";
         end case;
      end if;
      Colors.Serialize_Value (Item, Into, Error);
   end Serialize_Color_With_Failure;

   package Failing_Palettes is new
     Flyology_Serde.Adapters.Fixed_Array_Serializers
       (Index_Type        => Position,
        Element_Type      => Color,
        Array_Type        => Palette,
        Serialize_Element => Serialize_Color_With_Failure);

   procedure Serialize_Field_With_Failure
     (Item  : Packet;
      Field : Packet_Field;
      Into  : in out Flyology_Serde.Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
   begin
      case Field is
         when Shade_Field =>
            Colors.Serialize_Value (Item.Shade, Into, Error);
         when Samples_Field =>
            Failing_Palettes.Serialize_Value (Item.Samples, Into, Error);
      end case;
   end Serialize_Field_With_Failure;

   package Failing_Packets is new
     Flyology_Serde.Adapters.Record_Serializers
       (Source_Type               => Packet,
        Field_Ordinal             => Packet_Field,
        Type_Name                 => "Packet",
        Maximum_Type_Name_Length  => 16,
        Maximum_Fields            => 2,
        Maximum_Field_Name_Length => 16,
        Primary_Name              => Field_Name,
        Serialize_Field           => Serialize_Field_With_Failure);

   type Backend_Failure_Point is
     (No_Backend_Failure,
      Fail_Begin_Record,
      Fail_Put_Field,
      Fail_End_Record,
      Fail_Begin_Sequence,
      Fail_End_Sequence,
      Fail_Put_Enumeration);

   type Failing_Counter is new Counting.Counter with record
      Failure : Backend_Failure_Point := No_Backend_Failure;
   end record;

   overriding
   procedure Begin_Record
     (Self        : in out Failing_Counter;
      Type_Name   : String;
      Field_Count : Natural;
      Error       : in out Errors.Error_Info);

   overriding
   procedure Put_Field
     (Self  : in out Failing_Counter;
      Name  : String;
      Error : in out Errors.Error_Info);

   overriding
   procedure End_Record
     (Self  : in out Failing_Counter;
      Error : in out Errors.Error_Info);

   overriding
   procedure Begin_Sequence
     (Self   : in out Failing_Counter;
      Length : Flyology_Serde.Serialization.Data_Model.Length_Information;
      Error  : in out Errors.Error_Info);

   overriding
   procedure End_Sequence
     (Self  : in out Failing_Counter;
      Error : in out Errors.Error_Info);

   overriding
   procedure Put_Enumeration
     (Self         : in out Failing_Counter;
      Type_Name    : String;
      Literal_Name : String;
      Error        : in out Errors.Error_Info);

   overriding
   procedure Begin_Record
     (Self        : in out Failing_Counter;
      Type_Name   : String;
      Field_Count : Natural;
      Error       : in out Errors.Error_Info) is
   begin
      if Self.Failure = Fail_Begin_Record then
         Errors.Fail (Error, Errors.Application_Error);
      else
         Counting.Begin_Record
           (Counting.Counter (Self), Type_Name, Field_Count, Error);
      end if;
   end Begin_Record;

   overriding
   procedure Put_Field
     (Self  : in out Failing_Counter;
      Name  : String;
      Error : in out Errors.Error_Info) is
   begin
      if Self.Failure = Fail_Put_Field then
         Errors.Fail (Error, Errors.Application_Error);
      else
         Counting.Put_Field (Counting.Counter (Self), Name, Error);
      end if;
   end Put_Field;

   overriding
   procedure End_Record
     (Self  : in out Failing_Counter;
      Error : in out Errors.Error_Info) is
   begin
      if Self.Failure = Fail_End_Record then
         Errors.Fail (Error, Errors.Application_Error);
      else
         Counting.End_Record (Counting.Counter (Self), Error);
      end if;
   end End_Record;

   overriding
   procedure Begin_Sequence
     (Self   : in out Failing_Counter;
      Length : Flyology_Serde.Serialization.Data_Model.Length_Information;
      Error  : in out Errors.Error_Info) is
   begin
      if Self.Failure = Fail_Begin_Sequence then
         Errors.Fail (Error, Errors.Application_Error);
      else
         Counting.Begin_Sequence (Counting.Counter (Self), Length, Error);
      end if;
   end Begin_Sequence;

   overriding
   procedure End_Sequence
     (Self  : in out Failing_Counter;
      Error : in out Errors.Error_Info) is
   begin
      if Self.Failure = Fail_End_Sequence then
         Errors.Fail (Error, Errors.Application_Error);
      else
         Counting.End_Sequence (Counting.Counter (Self), Error);
      end if;
   end End_Sequence;

   overriding
   procedure Put_Enumeration
     (Self         : in out Failing_Counter;
      Type_Name    : String;
      Literal_Name : String;
      Error        : in out Errors.Error_Info) is
   begin
      if Self.Failure = Fail_Put_Enumeration then
         Errors.Fail (Error, Errors.Application_Error);
      else
         Counting.Put_Enumeration
           (Counting.Counter (Self), Type_Name, Literal_Name, Error);
      end if;
   end Put_Enumeration;

   Sample : constant Packet :=
     (Shade => Green, Samples => [First => Red, Second => Blue]);

   procedure Assert_Backend_Failure
     (Point           : Backend_Failure_Point;
      Expected_Events : Natural;
      Expected_Depth  : Natural;
      Expected_Field  : String)
   is
      Into  : Failing_Counter := (Counting.Counter with Failure => Point);
      Error : Errors.Error_Info;
   begin
      Packets.Serialize_Value (Sample, Into, Error);
      pragma Assert (Error.Code = Errors.Application_Error);
      pragma Assert
        (Counting.Event_Count (Counting.Counter (Into)) = Expected_Events);
      pragma Assert
        (Counting.Container_Depth (Counting.Counter (Into)) = Expected_Depth);
      if Expected_Field'Length = 0 then
         pragma Assert (Error.Path_Length = 0);
      else
         pragma Assert (Error.Path_Length = 1);
         pragma Assert (Error.Path (1).Kind = Errors.Field_Element);
         pragma Assert (Error.Path (1).Name_Length = Expected_Field'Length);
         pragma Assert
           (Error.Path (1).Name (1 .. Expected_Field'Length) = Expected_Field);
      end if;
   end Assert_Backend_Failure;

   procedure Assert_Color_Metadata_Rejected
     (Mode          : Color_Metadata_Mode;
      Expected_Code : Errors.Error_Code;
      Too_Small     : Boolean := False)
   is
      Into  : Counting.Counter;
      Error : Errors.Error_Info;
   begin
      Active_Color_Metadata := Mode;
      Color_Name_Calls := 0;
      Red_Name_Observations := 0;
      if Too_Small then
         Too_Small_Colors.Serialize_Value (Red, Into, Error);
      else
         Colors.Serialize_Value (Red, Into, Error);
      end if;
      pragma Assert (Error.Code = Expected_Code);
      pragma Assert (Counting.Event_Count (Into) = 0);
      Active_Color_Metadata := Normal_Color_Metadata;
   end Assert_Color_Metadata_Rejected;

   procedure Assert_Field_Metadata_Rejected
     (Mode          : Field_Metadata_Mode;
      Expected_Code : Errors.Error_Code;
      Too_Small     : Boolean := False) is
      Into  : Counting.Counter;
      Error : Errors.Error_Info;
   begin
      Active_Field_Metadata := Mode;
      Field_Name_Calls := 0;
      Shade_Name_Observations := 0;
      if Too_Small then
         Too_Small_Packets.Serialize_Value (Sample, Into, Error);
      else
         Packets.Serialize_Value (Sample, Into, Error);
      end if;
      pragma Assert (Error.Code = Expected_Code);
      pragma Assert (Counting.Event_Count (Into) = 0);
      Active_Field_Metadata := Normal_Field_Metadata;
   end Assert_Field_Metadata_Rejected;
begin
   pragma Assert (Color'Enum_Rep (Red) = 10);
   pragma Assert (Color'Enum_Rep (Green) = 42);
   pragma Assert (Color'Enum_Rep (Blue) = 99);

   declare
      Into  : Counting.Counter;
      Error : Errors.Error_Info;
   begin
      Color_Name_Calls := 0;
      Field_Name_Calls := 0;
      Packets.Serialize_Value (Sample, Into, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Counting.Event_Count (Into) = 9);
      pragma Assert (Color_Name_Calls = 18);
      pragma Assert (Field_Name_Calls = 4);
   end;

   declare
      Into   : JSON_Writers.Bounded_Writer (8);
      Buffer : String (1 .. 8);
      Length : Natural;
      Error  : Errors.Error_Info;
      Empty  : constant Empty_Palette := [others => Red];
   begin
      Empty_Palettes.Serialize_Value (Empty, Into, Error);
      Into.Finish_Document (Error);
      Into.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Buffer (1 .. Length) = "[]");
   end;

   declare
      Into   : JSON_Writers.Bounded_Writer (16);
      Buffer : String (1 .. 16);
      Length : Natural;
      Error  : Errors.Error_Info;
   begin
      Active_Color_Metadata := Shifted_Color_Bounds;
      Shifted_Type_Colors.Serialize_Value (Red, Into, Error);
      Into.Finish_Document (Error);
      Into.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Buffer (1 .. Length) = """red""");
   end;

   declare
      Into   : JSON_Writers.Bounded_Writer (16);
      Buffer : String (1 .. 16);
      Length : Natural;
      Error  : Errors.Error_Info;
   begin
      Active_Color_Metadata := High_End_Color_Bounds;
      High_End_Type_Colors.Serialize_Value (Red, Into, Error);
      Into.Finish_Document (Error);
      Into.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Buffer (1 .. Length) = """red""");
   end;

   declare
      Into   : JSON_Writers.Bounded_Writer (64);
      Buffer : String (1 .. 64);
      Length : Natural;
      Error  : Errors.Error_Info;
   begin
      Active_Color_Metadata := Shifted_Color_Bounds;
      Active_Field_Metadata := Shifted_Field_Bounds;
      Packets.Serialize_Value (Sample, Into, Error);
      Into.Finish_Document (Error);
      Into.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert
        (Buffer (1 .. Length)
         = "{""shade"":""green"",""samples"":[""red"",""blue""]}");
      Active_Color_Metadata := Normal_Color_Metadata;
      Active_Field_Metadata := Normal_Field_Metadata;
   end;

   declare
      Into   : JSON_Writers.Bounded_Writer (64);
      Buffer : String (1 .. 64);
      Length : Natural;
      Error  : Errors.Error_Info;
      Existing_Into   : JSON_Writers.Bounded_Writer (64);
      Existing_Buffer : String (1 .. 64);
      Existing_Length : Natural;
      Existing_Error  : Errors.Error_Info;
   begin
      Packets.Serialize_Value (Sample, Into, Error);
      Into.Finish_Document (Error);
      Into.Copy_Output (Buffer, Length, Error);
      Existing_Packets.Serialize_Value (Sample, Existing_Into, Existing_Error);
      Existing_Into.Finish_Document (Existing_Error);
      Existing_Into.Copy_Output
        (Existing_Buffer, Existing_Length, Existing_Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Existing_Error.Code = Errors.No_Error);
      pragma Assert
        (Buffer (1 .. Length)
         = "{""shade"":""green"",""samples"":[""red"",""blue""]}");
      pragma Assert (Existing_Length = Length);
      pragma Assert
        (Existing_Buffer (1 .. Existing_Length) = Buffer (1 .. Length));
   end;

   declare
      Into     : CBOR_Writers.Bounded_Writer (64);
      Buffer   : Bytes (1 .. 64);
      Length   : Natural;
      Error    : Errors.Error_Info;
      Existing_Into   : CBOR_Writers.Bounded_Writer (64);
      Existing_Buffer : Bytes (1 .. 64);
      Existing_Length : Natural;
      Existing_Error  : Errors.Error_Info;
      Expected : constant Bytes :=
        [16#A2#,
         16#65#, Character'Pos ('s'), Character'Pos ('h'),
         Character'Pos ('a'), Character'Pos ('d'), Character'Pos ('e'),
         16#65#, Character'Pos ('g'), Character'Pos ('r'),
         Character'Pos ('e'), Character'Pos ('e'), Character'Pos ('n'),
         16#67#, Character'Pos ('s'), Character'Pos ('a'),
         Character'Pos ('m'), Character'Pos ('p'), Character'Pos ('l'),
         Character'Pos ('e'), Character'Pos ('s'),
         16#82#,
         16#63#, Character'Pos ('r'), Character'Pos ('e'), Character'Pos ('d'),
         16#64#, Character'Pos ('b'), Character'Pos ('l'),
         Character'Pos ('u'), Character'Pos ('e')];
   begin
      Packets.Serialize_Value (Sample, Into, Error);
      Into.Finish_Document (Error);
      Into.Copy_Output (Buffer, Length, Error);
      Existing_Packets.Serialize_Value (Sample, Existing_Into, Existing_Error);
      Existing_Into.Finish_Document (Existing_Error);
      Existing_Into.Copy_Output
        (Existing_Buffer, Existing_Length, Existing_Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Existing_Error.Code = Errors.No_Error);
      pragma Assert (Length = Expected'Length);
      pragma Assert
        (Buffer (1 .. Ada.Streams.Stream_Element_Offset (Length)) = Expected);
      pragma Assert (Existing_Length = Length);
      pragma Assert
        (Existing_Buffer
           (1 .. Ada.Streams.Stream_Element_Offset (Existing_Length))
         = Buffer (1 .. Ada.Streams.Stream_Element_Offset (Length)));
   end;

   Assert_Color_Metadata_Rejected
     (Duplicate_Color_Name, Errors.Application_Error);
   Assert_Color_Metadata_Rejected
     (Invalid_Color_Name, Errors.Invalid_Text);
   Assert_Color_Metadata_Rejected
     (Overlong_Color_Name, Errors.Capacity_Exceeded);
   Assert_Color_Metadata_Rejected
     (Empty_Second_Color_Name, Errors.Application_Error);
   Assert_Color_Metadata_Rejected
     (Unstable_Color_Name, Errors.Application_Error);
   Assert_Color_Metadata_Rejected
     (Normal_Color_Metadata, Errors.Capacity_Exceeded, Too_Small => True);
   Assert_Field_Metadata_Rejected
     (Duplicate_Field_Name, Errors.Application_Error);
   Assert_Field_Metadata_Rejected
     (Invalid_Field_Name, Errors.Invalid_Text);
   Assert_Field_Metadata_Rejected
     (Overlong_Field_Name, Errors.Capacity_Exceeded);
   Assert_Field_Metadata_Rejected
     (Empty_Second_Field_Name, Errors.Application_Error);
   Assert_Field_Metadata_Rejected
     (Unstable_Field_Name, Errors.Application_Error);
   Assert_Field_Metadata_Rejected
     (Normal_Field_Metadata, Errors.Capacity_Exceeded, Too_Small => True);

   Assert_Backend_Failure
     (Fail_Begin_Record, 0, 0, "");
   Assert_Backend_Failure
     (Fail_Put_Field, 1, 1, "shade");
   Assert_Backend_Failure
     (Fail_End_Record, 8, 1, "");
   Assert_Backend_Failure
     (Fail_Begin_Sequence, 4, 1, "samples");
   Assert_Backend_Failure
     (Fail_End_Sequence, 7, 2, "samples");

   declare
      Into  : Failing_Counter :=
        (Counting.Counter with Failure => Fail_Put_Enumeration);
      Error : Errors.Error_Info;
   begin
      Colors.Serialize_Value (Red, Into, Error);
      pragma Assert (Error.Code = Errors.Application_Error);
      pragma Assert (Counting.Event_Count (Counting.Counter (Into)) = 0);
      pragma Assert (Counting.Container_Depth (Counting.Counter (Into)) = 0);
      pragma Assert (Error.Path_Length = 0);
   end;

   declare
      Into  : Counting.Counter;
      Error : Errors.Error_Info;
   begin
      Color_Name_Calls := 0;
      Empty_Type_Colors.Serialize_Value (Red, Into, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
      pragma Assert (Counting.Event_Count (Into) = 0);
      pragma Assert (Color_Name_Calls = 0);
   end;

   declare
      Into  : Counting.Counter;
      Error : Errors.Error_Info;
   begin
      Color_Name_Calls := 0;
      Invalid_Type_Colors.Serialize_Value (Red, Into, Error);
      pragma Assert (Error.Code = Errors.Invalid_Text);
      pragma Assert (Counting.Event_Count (Into) = 0);
      pragma Assert (Color_Name_Calls = 0);
   end;

   declare
      Into  : Counting.Counter;
      Error : Errors.Error_Info;
   begin
      Color_Name_Calls := 0;
      Overlong_Type_Colors.Serialize_Value (Red, Into, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
      pragma Assert (Counting.Event_Count (Into) = 0);
      pragma Assert (Color_Name_Calls = 0);
   end;

   declare
      Into   : Counting.Counter;
      Error  : Errors.Error_Info;
      Raised : Boolean := False;
   begin
      Active_Color_Metadata := Raise_Color_Name;
      begin
         Colors.Serialize_Value (Red, Into, Error);
      exception
         when Program_Error =>
            Raised := True;
      end;
      pragma Assert (Raised);
      pragma Assert (Counting.Event_Count (Into) = 0);
      Errors.Reset (Error);
      Active_Color_Metadata := Normal_Color_Metadata;
   end;

   declare
      Into   : Counting.Counter;
      Error  : Errors.Error_Info;
      Raised : Boolean := False;
   begin
      Active_Field_Metadata := Raise_Field_Name;
      begin
         Packets.Serialize_Value (Sample, Into, Error);
      exception
         when Program_Error =>
            Raised := True;
      end;
      pragma Assert (Raised);
      pragma Assert (Counting.Event_Count (Into) = 0);
      Errors.Reset (Error);
      Active_Field_Metadata := Normal_Field_Metadata;
   end;

   declare
      Into  : Counting.Counter;
      Error : Errors.Error_Info;
   begin
      Color_Name_Calls := 0;
      Field_Name_Calls := 0;
      Errors.Fail (Error, Errors.Invalid_Value);
      Packets.Serialize_Value (Sample, Into, Error);
      pragma Assert (Error.Code = Errors.Invalid_Value);
      pragma Assert (Counting.Event_Count (Into) = 0);
      pragma Assert (Color_Name_Calls = 0);
      pragma Assert (Field_Name_Calls = 0);
   end;

   declare
      Into  : Counting.Counter;
      Error : Errors.Error_Info;
   begin
      Color_Name_Calls := 0;
      Errors.Fail (Error, Errors.Invalid_Value);
      Colors.Serialize_Value (Red, Into, Error);
      pragma Assert (Error.Code = Errors.Invalid_Value);
      pragma Assert (Counting.Event_Count (Into) = 0);
      pragma Assert (Color_Name_Calls = 0);
   end;

   declare
      Into  : Counting.Counter;
      Error : Errors.Error_Info;
   begin
      Color_Name_Calls := 0;
      Errors.Fail (Error, Errors.Invalid_Value);
      Palettes.Serialize_Value (Sample.Samples, Into, Error);
      pragma Assert (Error.Code = Errors.Invalid_Value);
      pragma Assert (Counting.Event_Count (Into) = 0);
      pragma Assert (Color_Name_Calls = 0);
   end;

   declare
      Into  : Counting.Counter;
      Error : Errors.Error_Info;
   begin
      Active_Child_Failure := Fail_Child_With_Status;
      Failing_Packets.Serialize_Value (Sample, Into, Error);
      pragma Assert (Error.Code = Errors.Invalid_Value);
      pragma Assert (Counting.Event_Count (Into) = 6);
      pragma Assert (Counting.Container_Depth (Into) = 2);
      pragma Assert (Error.Path_Length = 2);
      pragma Assert (Error.Path (1).Kind = Errors.Field_Element);
      pragma Assert (Error.Path (1).Name_Length = 7);
      pragma Assert (Error.Path (1).Name (1 .. 7) = "samples");
      pragma Assert (Error.Path (2).Kind = Errors.Index_Element);
      pragma Assert (Error.Path (2).Index = 1);
   end;

   declare
      Into   : Counting.Counter;
      Error  : Errors.Error_Info;
      Raised : Boolean := False;
   begin
      Active_Child_Failure := Raise_From_Child;
      begin
         Failing_Packets.Serialize_Value (Sample, Into, Error);
      exception
         when Program_Error =>
            Raised := True;
      end;
      pragma Assert (Raised);
      pragma Assert (Counting.Event_Count (Into) = 6);
      pragma Assert (Counting.Container_Depth (Into) = 2);
      Errors.Reset (Error);
   end;
end Serialization_Only_Adapter_Tests;
