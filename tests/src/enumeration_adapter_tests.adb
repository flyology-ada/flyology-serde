with Ada.Streams;
with Flyology_Serde.Adapters.Enumerations;
with Flyology_Serde.Deserialization;
with Flyology_Serde.Deserialization_Adapters;
with Flyology_Serde.Deserializers.CBOR;
with Flyology_Serde.Deserializers.JSON;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;
with Flyology_Serde.Serializers.CBOR;
with Flyology_Serde.Serializers.Counting;
with Flyology_Serde.Serializers.JSON;

procedure Enumeration_Adapter_Tests is
   package CBOR_Readers renames Flyology_Serde.Deserializers.CBOR;
   package CBOR_Writers renames Flyology_Serde.Serializers.CBOR;
   package Counting renames Flyology_Serde.Serializers.Counting;
   package Errors renames Flyology_Serde.Errors;
   package JSON_Readers renames Flyology_Serde.Deserializers.JSON;
   package JSON_Writers renames Flyology_Serde.Serializers.JSON;
   package Policies renames Flyology_Serde.Policies;
   use type Ada.Streams.Stream_Element_Array;
   use type Errors.Error_Code;
   use type Errors.Input_Offset_Unit;
   use type Errors.Path_Element_Kind;

   subtype Bytes is Ada.Streams.Stream_Element_Array;

   type Color is (Red, Green, Blue);
   for Color use (Red => 10, Green => 42, Blue => 99);

   type Metadata_Mode is
     (Normal_Metadata,
      Too_Many_Aliases,
      Overlong_Primary,
      Invalid_UTF_8_Primary,
      Duplicate_Primary,
      Alias_On_Other_Literal,
      Overlong_Alias,
      Invalid_UTF_8_Alias,
      Matcher_No_Match);

   Active_Metadata : Metadata_Mode := Normal_Metadata;

   function Primary_Name (Value : Color) return String is
     (case Active_Metadata is
         when Overlong_Primary =>
           (if Value = Red then "red-name-too-long" else Color'Image (Value)),
         when Invalid_UTF_8_Primary =>
           (if Value = Red
            then String'[1 => Character'Val (16#C0#)]
            else (if Value = Green then "green" else "blue")),
         when Duplicate_Primary => "same",
         when others            =>
           (case Value is
               when Red   => "red",
               when Green => "green",
               when Blue  => "blue"));

   function Alias_Count (Value : Color) return Natural is
     (if Active_Metadata = Too_Many_Aliases and then Value = Red
      then 2
      elsif Active_Metadata = Duplicate_Primary
      then 0
      elsif Value = Red
      then 1
      else 0);

   function Alias_Name
     (Value : Color; Position : Positive) return String is
     (if Value = Red and then Position = 1
      then
        (case Active_Metadata is
            when Alias_On_Other_Literal => "green",
            when Overlong_Alias         => "alias-name-too-long",
            when Invalid_UTF_8_Alias    => String'[1 => Character'Val (16#C0#)],
            when others                 => "r")
      else "");

   function Matches_Literal (Value : Color; Name : String) return Boolean is
     (if Active_Metadata = Matcher_No_Match
      then False
      elsif Active_Metadata = Duplicate_Primary
      then Name = "same"
      else
        (case Value is
            when Red   => Name = "red" or else Name = "r" or else Name = "x",
            when Green => Name = "green" or else Name = "x",
            when Blue  => Name = "blue"));

   package Colors is new
     Flyology_Serde.Adapters.Enumerations
       (Value_Type                  => Color,
        Type_Name                   => "Color",
        Maximum_Type_Name_Length    => 16,
        Maximum_Literals            => 3,
        Maximum_Literal_Name_Length => 16,
        Maximum_Aliases_Per_Literal => 1,
        Primary_Name                => Primary_Name,
        Alias_Count                 => Alias_Count,
        Alias_Name                  => Alias_Name,
        Matches_Literal             => Matches_Literal);

   package Too_Small_Colors is new
     Flyology_Serde.Adapters.Enumerations
       (Value_Type                  => Color,
        Type_Name                   => "Color",
        Maximum_Type_Name_Length    => 16,
        Maximum_Literals            => 2,
        Maximum_Literal_Name_Length => 16,
        Maximum_Aliases_Per_Literal => 1,
        Primary_Name                => Primary_Name,
        Alias_Count                 => Alias_Count,
        Alias_Name                  => Alias_Name,
        Matches_Literal             => Matches_Literal);

   package Overlong_Type_Colors is new
     Flyology_Serde.Adapters.Enumerations
       (Value_Type                  => Color,
        Type_Name                   => "Color-name-too-long",
        Maximum_Type_Name_Length    => 16,
        Maximum_Literals            => 3,
        Maximum_Literal_Name_Length => 16,
        Maximum_Aliases_Per_Literal => 1,
        Primary_Name                => Primary_Name,
        Alias_Count                 => Alias_Count,
        Alias_Name                  => Alias_Name,
        Matches_Literal             => Matches_Literal);

   package Invalid_Type_Colors is new
     Flyology_Serde.Adapters.Enumerations
       (Value_Type                  => Color,
        Type_Name                   => String'[1 => Character'Val (16#C0#)],
        Maximum_Type_Name_Length    => 16,
        Maximum_Literals            => 3,
        Maximum_Literal_Name_Length => 16,
        Maximum_Aliases_Per_Literal => 1,
        Primary_Name                => Primary_Name,
        Alias_Count                 => Alias_Count,
        Alias_Name                  => Alias_Name,
        Matches_Literal             => Matches_Literal);

   type Color_Builder is limited record
      Published : Color := Blue;
      Candidate : Color := Blue;
      Active    : Boolean := False;
      Commits   : Natural := 0;
      Rollbacks : Natural := 0;
   end record;

   procedure Begin_Color
     (Target : in out Color_Builder; Error : in out Errors.Error_Info) is
      pragma Unreferenced (Error);
   begin
      Target.Candidate := Target.Published;
      Target.Active := True;
   end Begin_Color;

   procedure Read_Color
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out Color_Builder;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info) is
      pragma Unreferenced (Policy);
   begin
      Colors.Deserialize_Candidate (From, Target.Candidate, Error);
   end Read_Color;

   procedure Commit_Color
     (Target : in out Color_Builder; Error : in out Errors.Error_Info) is
      pragma Unreferenced (Error);
   begin
      Target.Published := Target.Candidate;
      Target.Active := False;
      Target.Commits := Target.Commits + 1;
   end Commit_Color;

   procedure Rollback_Color (Target : in out Color_Builder) is
   begin
      Target.Candidate := Target.Published;
      Target.Active := False;
      Target.Rollbacks := Target.Rollbacks + 1;
   end Rollback_Color;

   Default_Policy : constant Policies.Decode_Policy := (others => <>);

   package Root_Color is new
     Flyology_Serde.Deserialization_Adapters
       (Builder_Type       => Color_Builder,
        Policy             => Default_Policy,
        Begin_Candidate    => Begin_Color,
        Deserialize_Value  => Read_Color,
        Commit_Candidate   => Commit_Color,
        Rollback_Candidate => Rollback_Color);
begin
   --  Logical names are independent of non-default, noncontiguous reps.
   pragma Assert (Color'Enum_Rep (Red) = 10);
   pragma Assert (Color'Enum_Rep (Green) = 42);
   pragma Assert (Color'Enum_Rep (Blue) = 99);

   declare
      Into   : JSON_Writers.Bounded_Writer (16);
      Buffer : String (1 .. 16);
      Length : Natural;
      Error  : Errors.Error_Info;
   begin
      Colors.Serialize_Value (Red, Into, Error);
      Into.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Buffer (1 .. Length) = """red""");
   end;

   declare
      Into   : CBOR_Writers.Bounded_Writer (16);
      Buffer : Bytes (1 .. 16);
      Length : Natural;
      Error  : Errors.Error_Info;
   begin
      Colors.Serialize_Value (Red, Into, Error);
      Into.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert
        (Buffer (1 .. Ada.Streams.Stream_Element_Offset (Length))
         = Bytes'[16#63#, Character'Pos ('r'), Character'Pos ('e'), Character'Pos ('d')]);
   end;

   declare
      Input  : aliased constant String := """r""";
      From   : JSON_Readers.Reader (Input'Access);
      Target : Color_Builder;
      Error  : Errors.Error_Info;
   begin
      From.Initialize (Default_Policy);
      Root_Color.Deserialize (From, Target, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Target.Published = Red and then Target.Commits = 1);
   end;

   declare
      Input  : aliased constant String := """green""";
      From   : JSON_Readers.Reader (Input'Access);
      Target : Color_Builder;
      Error  : Errors.Error_Info;
   begin
      From.Initialize (Default_Policy);
      Root_Color.Deserialize (From, Target, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Target.Published = Green);
   end;

   declare
      Input  : aliased constant Bytes :=
        [16#64#, Character'Pos ('b'), Character'Pos ('l'),
         Character'Pos ('u'), Character'Pos ('e')];
      From   : CBOR_Readers.Reader (Input'Access);
      Target : Color_Builder;
      Error  : Errors.Error_Info;
   begin
      From.Initialize (Default_Policy);
      Root_Color.Deserialize (From, Target, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Target.Published = Blue);
   end;

   --  Direct candidate failures do not assign and cannot claim an offset
   --  until the mandatory root transaction aborts the backend.
   declare
      Input  : aliased constant String := """purple""";
      From   : JSON_Readers.Reader (Input'Access);
      Target : Color := Green;
      Error  : Errors.Error_Info;
   begin
      From.Initialize (Default_Policy);
      Colors.Deserialize_Candidate (From, Target, Error);
      pragma Assert (Error.Code = Errors.Invalid_Value);
      pragma Assert (Error.Offset_Unit = Errors.Unknown_Offset);
      pragma Assert (Target = Green);
   end;

   declare
      Input  : aliased constant String := """x""";
      From   : JSON_Readers.Reader (Input'Access);
      Target : Color := Green;
      Error  : Errors.Error_Info;
   begin
      From.Initialize (Default_Policy);
      Colors.Deserialize_Candidate (From, Target, Error);
      pragma Assert (Error.Code = Errors.Application_Error);
      pragma Assert (Error.Offset_Unit = Errors.Unknown_Offset);
      pragma Assert (Target = Green);
   end;

   declare
      Input  : aliased constant String := """literal-name-is-too-long""";
      From   : JSON_Readers.Reader (Input'Access);
      Target : Color := Green;
      Error  : Errors.Error_Info;
   begin
      From.Initialize (Default_Policy);
      Colors.Deserialize_Candidate (From, Target, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
      pragma Assert (Target = Green);
   end;

   --  No-match and ambiguity retain the enclosing path; root abort attaches
   --  the JSON next-unread byte offset after the string token.
   declare
      Input  : aliased constant String := """purple""";
      From   : JSON_Readers.Reader (Input'Access);
      Target : Color_Builder := (Published => Green, others => <>);
      Error  : Errors.Error_Info;
   begin
      Errors.Push_Field (Error, "color");
      From.Initialize (Default_Policy);
      Root_Color.Deserialize (From, Target, Error);
      pragma Assert (Error.Code = Errors.Invalid_Value);
      pragma Assert (Error.Input_Offset = Input'Length);
      pragma Assert (Error.Offset_Unit = Errors.Byte_Offset);
      pragma Assert (Error.Path_Length = 1);
      pragma Assert (Error.Path (1).Kind = Errors.Field_Element);
      pragma Assert (Error.Path (1).Name (1 .. 5) = "color");
      pragma Assert (Target.Published = Green and then Target.Rollbacks = 1);
   end;

   declare
      Input  : aliased constant String := """x""";
      From   : JSON_Readers.Reader (Input'Access);
      Target : Color_Builder := (Published => Green, others => <>);
      Error  : Errors.Error_Info;
   begin
      From.Initialize (Default_Policy);
      Root_Color.Deserialize (From, Target, Error);
      pragma Assert (Error.Code = Errors.Application_Error);
      pragma Assert (Error.Input_Offset = Input'Length);
      pragma Assert (Target.Published = Green and then Target.Rollbacks = 1);
   end;

   --  Backend kind errors precede semantic literal lookup.
   declare
      Input  : aliased constant String := "7";
      From   : JSON_Readers.Reader (Input'Access);
      Target : Color_Builder;
      Error  : Errors.Error_Info;
   begin
      From.Initialize (Default_Policy);
      Root_Color.Deserialize (From, Target, Error);
      pragma Assert (Error.Code = Errors.Unexpected_Kind);
   end;

   --  Every representative metadata failure precedes an output event.
   declare
      Into  : Counting.Counter;
      Error : Errors.Error_Info;
   begin
      Too_Small_Colors.Serialize_Value (Red, Into, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
      pragma Assert (Into.Event_Count = 0);

      Errors.Reset (Error);
      Overlong_Type_Colors.Serialize_Value (Red, Into, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
      pragma Assert (Into.Event_Count = 0);

      Errors.Reset (Error);
      Invalid_Type_Colors.Serialize_Value (Red, Into, Error);
      pragma Assert (Error.Code = Errors.Invalid_Text);
      pragma Assert (Into.Event_Count = 0);

      for Mode in Metadata_Mode range
        Too_Many_Aliases .. Matcher_No_Match
      loop
         Errors.Reset (Error);
         Active_Metadata := Mode;
         Colors.Serialize_Value (Red, Into, Error);
         case Mode is
            when Too_Many_Aliases | Overlong_Primary | Overlong_Alias =>
               pragma Assert (Error.Code = Errors.Capacity_Exceeded);
            when Invalid_UTF_8_Primary | Invalid_UTF_8_Alias =>
               pragma Assert (Error.Code = Errors.Invalid_Text);
            when Duplicate_Primary
               | Alias_On_Other_Literal
               | Matcher_No_Match                    =>
               pragma Assert (Error.Code = Errors.Application_Error);
         end case;
         pragma Assert (Into.Event_Count = 0);
      end loop;
   end;

   --  Decode-side metadata rejection consumes no input and rolls back.
   declare
      Input  : aliased constant String := """red""";
      From   : JSON_Readers.Reader (Input'Access);
      Target : Color_Builder := (Published => Green, others => <>);
      Error  : Errors.Error_Info;
   begin
      Active_Metadata := Alias_On_Other_Literal;
      From.Initialize (Default_Policy);
      Root_Color.Deserialize (From, Target, Error);
      Active_Metadata := Normal_Metadata;
      pragma Assert (Error.Code = Errors.Application_Error);
      pragma Assert (Error.Input_Offset = 0);
      pragma Assert (Error.Offset_Unit = Errors.Byte_Offset);
      pragma Assert (From.Input_Offset = 0);
      pragma Assert (Target.Published = Green and then Target.Rollbacks = 1);
   end;
end Enumeration_Adapter_Tests;
