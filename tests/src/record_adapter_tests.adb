with Ada.Streams;
with Flyology_Serde.Adapters.Records;
with Flyology_Serde.Adapters.Signed_Integers;
with Flyology_Serde.Deserialization;
with Flyology_Serde.Deserialization_Adapters;
with Flyology_Serde.Deserializers.CBOR;
with Flyology_Serde.Deserializers.JSON;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;
with Flyology_Serde.Serialization;
with Flyology_Serde.Serializers.CBOR;
with Flyology_Serde.Serializers.Counting;
with Flyology_Serde.Serializers.JSON;

procedure Record_Adapter_Tests is
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

   type Person is record
      Identifier : Integer := 0;
      Enabled    : Boolean := False;
   end record;

   type Person_Builder is limited record
      Published       : Person := (others => <>);
      Candidate       : Person := (others => <>);
      Has_Identifier  : Boolean := False;
      Has_Enabled     : Boolean := False;
      Active          : Boolean := False;
      Candidate_Owned : Boolean := False;
      Acquisitions    : Natural := 0;
      Releases        : Natural := 0;
      Replacements    : Natural := 0;
      Defaults        : Natural := 0;
      Finishes        : Natural := 0;
      Commits         : Natural := 0;
      Rollbacks       : Natural := 0;
   end record;

   type Field is (Identifier_Field, Enabled_Field);

   type Metadata_Mode is
     (Normal_Metadata,
      Too_Many_Aliases,
      Overlong_Primary,
      Invalid_UTF_8_Primary,
      Duplicate_Primary,
      Alias_On_Other_Field,
      Matcher_No_Match);

   Active_Metadata : Metadata_Mode := Normal_Metadata;

   package Integers is new
     Flyology_Serde.Adapters.Signed_Integers (Integer);

   function Primary_Name (Item : Field) return String is
     (case Active_Metadata is
         when Overlong_Primary =>
           (if Item = Identifier_Field then "identifier-too-long" else "enabled"),
         when Invalid_UTF_8_Primary =>
           (if Item = Identifier_Field
            then String'[1 => Character'Val (16#C0#)]
            else "enabled"),
         when Duplicate_Primary => "same",
         when others            =>
           (case Item is
               when Identifier_Field => "identifier",
               when Enabled_Field    => "enabled"));

   function Alias_Count (Item : Field) return Natural is
     (if Active_Metadata = Too_Many_Aliases
        and then Item = Identifier_Field
      then 2
      elsif Active_Metadata = Duplicate_Primary
      then 0
      elsif Item = Identifier_Field
      then 1
      else 0);

   function Alias_Name
     (Item : Field; Position : Positive) return String is
     (if Item = Identifier_Field and then Position = 1
      then (if Active_Metadata = Alias_On_Other_Field then "enabled" else "id")
      else "");

   function Matches_Field (Item : Field; Name : String) return Boolean is
     (if Active_Metadata = Matcher_No_Match
      then False
      elsif Active_Metadata = Duplicate_Primary
      then Name = "same"
      else
        (case Item is
            when Identifier_Field =>
              Name = "identifier" or else Name = "id" or else Name = "x",
            when Enabled_Field    => Name = "enabled" or else Name = "x"));

   procedure Serialize_Field
     (Item  : Person;
      Which : Field;
      Into  : in out Flyology_Serde.Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
   begin
      case Which is
         when Identifier_Field =>
            Integers.Serialize_Value (Item.Identifier, Into, Error);
         when Enabled_Field    =>
            Into.Put_Boolean (Item.Enabled, Error);
      end case;
   end Serialize_Field;

   procedure Deserialize_Field
     (From      : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target    : in out Person_Builder;
      Which     : Field;
      Replacing : Boolean;
      Policy    : Policies.Decode_Policy;
      Error     : in out Errors.Error_Info)
   is
      pragma Unreferenced (Policy);
   begin
      case Which is
         when Identifier_Field =>
            pragma Assert (Replacing = Target.Has_Identifier);
            declare
               Value : Integer := 0;
            begin
               Integers.Deserialize_Candidate (From, Value, Error);
               if Error.Code = Errors.No_Error then
                  if Replacing then
                     pragma Assert (Target.Candidate_Owned);
                     Target.Releases := Target.Releases + 1;
                     Target.Candidate_Owned := False;
                  end if;
                  Target.Candidate.Identifier := Value;
                  Target.Has_Identifier := True;
                  Target.Acquisitions := Target.Acquisitions + 1;
                  Target.Candidate_Owned := True;
               end if;
            end;
         when Enabled_Field    =>
            pragma Assert (Replacing = Target.Has_Enabled);
            declare
               Value : Boolean;
            begin
               From.Read_Boolean (Value, Error);
               if Error.Code = Errors.No_Error then
                  Target.Candidate.Enabled := Value;
                  Target.Has_Enabled := True;
               end if;
            end;
      end case;
      if Error.Code = Errors.No_Error and then Replacing then
         Target.Replacements := Target.Replacements + 1;
      end if;
   end Deserialize_Field;

   procedure Apply_Missing
     (Target  : in out Person_Builder;
      Which   : Field;
      Policy  : Policies.Decode_Policy;
      Applied : out Boolean;
      Error   : in out Errors.Error_Info)
   is
      pragma Unreferenced (Policy, Error);
   begin
      case Which is
         when Identifier_Field =>
            Applied := False;
         when Enabled_Field    =>
            Target.Candidate.Enabled := False;
            Target.Has_Enabled := True;
            Target.Defaults := Target.Defaults + 1;
            Applied := True;
      end case;
   end Apply_Missing;

   procedure Finish_Person
     (Target : in out Person_Builder; Error : in out Errors.Error_Info) is
   begin
      pragma Assert (Target.Has_Identifier and then Target.Has_Enabled);
      if Target.Candidate.Identifier < 0 then
         Errors.Fail (Error, Errors.Invalid_Value);
      else
         Target.Finishes := Target.Finishes + 1;
      end if;
   end Finish_Person;

   package People is new
     Flyology_Serde.Adapters.Records
       (Source_Type              => Person,
        Builder_Type             => Person_Builder,
        Field_Ordinal            => Field,
        Type_Name                => "Person",
        Maximum_Type_Name_Length => 16,
        Maximum_Fields           => 2,
        Maximum_Field_Name_Length => 16,
        Maximum_Aliases_Per_Field => 1,
        Primary_Name             => Primary_Name,
        Alias_Count              => Alias_Count,
        Alias_Name               => Alias_Name,
        Matches_Field            => Matches_Field,
        Serialize_Field          => Serialize_Field,
        Deserialize_Field        => Deserialize_Field,
        Apply_Missing            => Apply_Missing,
        Finish_Candidate         => Finish_Person);

   procedure Begin_Person
     (Target : in out Person_Builder; Error : in out Errors.Error_Info) is
      pragma Unreferenced (Error);
   begin
      Target.Candidate := (others => <>);
      Target.Has_Identifier := False;
      Target.Has_Enabled := False;
      Target.Active := True;
      Target.Candidate_Owned := False;
      Target.Acquisitions := 0;
      Target.Releases := 0;
      Target.Replacements := 0;
      Target.Defaults := 0;
      Target.Finishes := 0;
   end Begin_Person;

   procedure Commit_Person
     (Target : in out Person_Builder; Error : in out Errors.Error_Info) is
      pragma Unreferenced (Error);
   begin
      pragma Assert (Target.Active and then Target.Finishes = 1);
      pragma Assert (Target.Candidate_Owned);
      Target.Published := Target.Candidate;
      Target.Candidate_Owned := False;
      Target.Active := False;
      Target.Commits := Target.Commits + 1;
   end Commit_Person;

   procedure Rollback_Person (Target : in out Person_Builder) is
   begin
      if Target.Candidate_Owned then
         Target.Releases := Target.Releases + 1;
         Target.Candidate_Owned := False;
      end if;
      Target.Candidate := (others => <>);
      Target.Has_Identifier := False;
      Target.Has_Enabled := False;
      Target.Active := False;
      Target.Rollbacks := Target.Rollbacks + 1;
   end Rollback_Person;

   Default_Policy : constant Policies.Decode_Policy := (others => <>);
   Ignore_Unknown_Policy : constant Policies.Decode_Policy :=
     (Limits  => (others => <>),
      Records =>
        (Unknown_Fields   => Policies.Ignore_Unknown,
         Duplicate_Fields => Policies.Reject_Duplicate));
   Keep_First_Policy : constant Policies.Decode_Policy :=
     (Limits  => (others => <>),
      Records =>
        (Unknown_Fields   => Policies.Reject_Unknown,
         Duplicate_Fields => Policies.Keep_First));
   Keep_Last_Policy : constant Policies.Decode_Policy :=
     (Limits  => (others => <>),
      Records =>
        (Unknown_Fields   => Policies.Reject_Unknown,
         Duplicate_Fields => Policies.Keep_Last));

   package Root_Default is new
     Flyology_Serde.Deserialization_Adapters
       (Builder_Type       => Person_Builder,
        Policy             => Default_Policy,
        Begin_Candidate    => Begin_Person,
        Deserialize_Value  => People.Deserialize_Candidate,
        Commit_Candidate   => Commit_Person,
        Rollback_Candidate => Rollback_Person);

   package Root_Ignore_Unknown is new
     Flyology_Serde.Deserialization_Adapters
       (Builder_Type       => Person_Builder,
        Policy             => Ignore_Unknown_Policy,
        Begin_Candidate    => Begin_Person,
        Deserialize_Value  => People.Deserialize_Candidate,
        Commit_Candidate   => Commit_Person,
        Rollback_Candidate => Rollback_Person);

   package Root_Keep_First is new
     Flyology_Serde.Deserialization_Adapters
       (Builder_Type       => Person_Builder,
        Policy             => Keep_First_Policy,
        Begin_Candidate    => Begin_Person,
        Deserialize_Value  => People.Deserialize_Candidate,
        Commit_Candidate   => Commit_Person,
        Rollback_Candidate => Rollback_Person);

   package Root_Keep_Last is new
     Flyology_Serde.Deserialization_Adapters
       (Builder_Type       => Person_Builder,
        Policy             => Keep_Last_Policy,
        Begin_Candidate    => Begin_Person,
        Deserialize_Value  => People.Deserialize_Candidate,
        Commit_Candidate   => Commit_Person,
        Rollback_Candidate => Rollback_Person);

   package Too_Small_People is new
     Flyology_Serde.Adapters.Records
       (Source_Type              => Person,
        Builder_Type             => Person_Builder,
        Field_Ordinal            => Field,
        Type_Name                => "Person",
        Maximum_Type_Name_Length => 16,
        Maximum_Fields           => 1,
        Maximum_Field_Name_Length => 16,
        Maximum_Aliases_Per_Field => 1,
        Primary_Name             => Primary_Name,
        Alias_Count              => Alias_Count,
        Alias_Name               => Alias_Name,
        Matches_Field            => Matches_Field,
        Serialize_Field          => Serialize_Field,
        Deserialize_Field        => Deserialize_Field,
        Apply_Missing            => Apply_Missing,
        Finish_Candidate         => Finish_Person);

   procedure Assert_Field_Path
     (Error : Errors.Error_Info; Name : String) is
   begin
      pragma Assert (Error.Path_Length = 1);
      pragma Assert (Error.Path (1).Kind = Errors.Field_Element);
      pragma Assert (Error.Path (1).Name_Length = Name'Length);
      pragma Assert
        (Error.Path (1).Name (1 .. Name'Length) = Name);
   end Assert_Field_Path;

   procedure Decode_JSON
     (Input  : String;
      Root   : not null access procedure
        (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
         Target : in out Person_Builder;
         Error  : in out Errors.Error_Info);
      Policy : Policies.Decode_Policy;
      Target : in out Person_Builder;
      Error  : in out Errors.Error_Info)
   is
      Source : aliased constant String := Input;
      From   : JSON_Readers.Reader (Source'Access);
   begin
      From.Initialize (Policy);
      Root (From, Target, Error);
   end Decode_JSON;
begin
   --  Serialization is declaration-ordered and emits every field.
   declare
      Into   : JSON_Writers.Bounded_Writer (64);
      Buffer : String (1 .. 64);
      Length : Natural;
      Error  : Errors.Error_Info;
   begin
      People.Serialize_Value
        ((Identifier => 7, Enabled => True), Into, Error);
      Into.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert
        (Buffer (1 .. Length) = "{""identifier"":7,""enabled"":true}");
   end;

   declare
      Into  : Counting.Counter;
      Error : Errors.Error_Info;
   begin
      People.Serialize_Value
        ((Identifier => 7, Enabled => True), Into, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Into.Event_Count = 6);
   end;

   declare
      Expected : constant Bytes :=
        [16#A2#,
         16#6A#, Character'Pos ('i'), Character'Pos ('d'),
         Character'Pos ('e'), Character'Pos ('n'), Character'Pos ('t'),
         Character'Pos ('i'), Character'Pos ('f'), Character'Pos ('i'),
         Character'Pos ('e'), Character'Pos ('r'), 7,
         16#67#, Character'Pos ('e'), Character'Pos ('n'),
         Character'Pos ('a'), Character'Pos ('b'), Character'Pos ('l'),
         Character'Pos ('e'), Character'Pos ('d'), 16#F5#];
      Into     : CBOR_Writers.Bounded_Writer (32);
      Buffer   : Bytes (1 .. 32);
      Length   : Natural;
      Error    : Errors.Error_Info;
   begin
      People.Serialize_Value
        ((Identifier => 7, Enabled => True), Into, Error);
      Into.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert
        (Buffer (1 .. Ada.Streams.Stream_Element_Offset (Length))
         = Expected);
   end;

   --  Source order is independent, aliases resolve, and missing defaults run
   --  in canonical ordinal order after End_Record.
   declare
      Target : Person_Builder :=
        (Published => (Identifier => 99, Enabled => True), others => <>);
      Error  : Errors.Error_Info;
   begin
      Decode_JSON
        ("{""enabled"":true,""id"":7}",
         Root_Default.Deserialize'Access,
         Default_Policy,
         Target,
         Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Target.Published = (Identifier => 7, Enabled => True));
      pragma Assert (Target.Defaults = 0 and then Target.Finishes = 1);
      pragma Assert (Error.Path_Length = 0);

      Errors.Reset (Error);
      Decode_JSON
        ("{""identifier"":8}",
         Root_Default.Deserialize'Access,
         Default_Policy,
         Target,
         Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Target.Published = (Identifier => 8, Enabled => False));
      pragma Assert (Target.Defaults = 1 and then Target.Finishes = 1);
   end;

   --  Missing, unknown, and runtime-ambiguous names retain the required path.
   declare
      Target : Person_Builder :=
        (Published => (Identifier => 99, Enabled => True), others => <>);
      Error  : Errors.Error_Info;
   begin
      Decode_JSON
        ("{""enabled"":true}",
         Root_Default.Deserialize'Access,
         Default_Policy,
         Target,
         Error);
      pragma Assert (Error.Code = Errors.Missing_Field);
      Assert_Field_Path (Error, "identifier");
      pragma Assert (Target.Published.Identifier = 99 and then Target.Rollbacks = 1);

      Errors.Reset (Error);
      Decode_JSON
        ("{""identifier"":7,""extra"":0}",
         Root_Default.Deserialize'Access,
         Default_Policy,
         Target,
         Error);
      pragma Assert (Error.Code = Errors.Unknown_Field);
      Assert_Field_Path (Error, "extra");

      Errors.Reset (Error);
      Decode_JSON
        ("{""x"":7}",
         Root_Default.Deserialize'Access,
         Default_Policy,
         Target,
         Error);
      pragma Assert (Error.Code = Errors.Application_Error);
      Assert_Field_Path (Error, "x");
      pragma Assert (Target.Published.Identifier = 99);
   end;

   --  Unknown skip and all duplicate policies consume exactly one value.
   declare
      Target : Person_Builder := (others => <>);
      Error  : Errors.Error_Info;
   begin
      Decode_JSON
        ("{""extra"":{""nested"":[1]},""identifier"":7}",
         Root_Ignore_Unknown.Deserialize'Access,
         Ignore_Unknown_Policy,
         Target,
         Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Target.Published = (Identifier => 7, Enabled => False));

      Errors.Reset (Error);
      Decode_JSON
        ("{""identifier"":1,""id"":2}",
         Root_Keep_First.Deserialize'Access,
         Keep_First_Policy,
         Target,
         Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Target.Published.Identifier = 1);
      pragma Assert (Target.Replacements = 0);

      Errors.Reset (Error);
      Decode_JSON
        ("{""identifier"":1,""id"":2}",
         Root_Keep_Last.Deserialize'Access,
         Keep_Last_Policy,
         Target,
         Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Target.Published.Identifier = 2);
      pragma Assert (Target.Replacements = 1);
      pragma Assert (Target.Acquisitions = 2 and then Target.Releases = 1);
      pragma Assert (not Target.Candidate_Owned);

      Errors.Reset (Error);
      Decode_JSON
        ("{""identifier"":1,""id"":2}",
         Root_Default.Deserialize'Access,
         Default_Policy,
         Target,
         Error);
      pragma Assert (Error.Code = Errors.Duplicate_Field);
      Assert_Field_Path (Error, "id");
   end;

   --  Failed replacement and final cross-field validation never publish.
   declare
      Target : Person_Builder :=
        (Published => (Identifier => 99, Enabled => True), others => <>);
      Error  : Errors.Error_Info;
   begin
      Decode_JSON
        ("{""identifier"":1,""id"":false}",
         Root_Keep_Last.Deserialize'Access,
         Keep_Last_Policy,
         Target,
         Error);
      pragma Assert (Error.Code = Errors.Unexpected_Kind);
      Assert_Field_Path (Error, "id");
      pragma Assert (Target.Published.Identifier = 99 and then Target.Rollbacks = 1);
      pragma Assert (Target.Acquisitions = 1 and then Target.Releases = 1);
      pragma Assert (not Target.Candidate_Owned);

      Errors.Reset (Error);
      Decode_JSON
        ("{""identifier"":-1}",
         Root_Default.Deserialize'Access,
         Default_Policy,
         Target,
         Error);
      pragma Assert (Error.Code = Errors.Invalid_Value);
      pragma Assert (Target.Published.Identifier = 99 and then Target.Rollbacks = 2);
      pragma Assert (Target.Acquisitions = 1 and then Target.Releases = 1);
      pragma Assert (not Target.Candidate_Owned);
   end;

   --  The same combinator traverses CBOR record maps without backend coupling.
   declare
      Input  : aliased constant Bytes :=
        [16#A2#,
         16#6A#, Character'Pos ('i'), Character'Pos ('d'),
         Character'Pos ('e'), Character'Pos ('n'), Character'Pos ('t'),
         Character'Pos ('i'), Character'Pos ('f'), Character'Pos ('i'),
         Character'Pos ('e'), Character'Pos ('r'), 7,
         16#67#, Character'Pos ('e'), Character'Pos ('n'),
         Character'Pos ('a'), Character'Pos ('b'), Character'Pos ('l'),
         Character'Pos ('e'), Character'Pos ('d'), 16#F5#];
      From   : CBOR_Readers.Reader (Input'Access);
      Target : Person_Builder;
      Error  : Errors.Error_Info;
   begin
      From.Initialize (Default_Policy);
      Root_Default.Deserialize (From, Target, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Target.Published = (Identifier => 7, Enabled => True));
   end;

   --  Invalid generated bounds and every representative metadata class fail
   --  before output events.
   declare
      Into  : Counting.Counter;
      Error : Errors.Error_Info;
   begin
      Too_Small_People.Serialize_Value
        ((Identifier => 7, Enabled => True), Into, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
      pragma Assert (Into.Event_Count = 0);

      for Mode in Metadata_Mode range
        Too_Many_Aliases .. Matcher_No_Match
      loop
         Errors.Reset (Error);
         Active_Metadata := Mode;
         People.Serialize_Value
           ((Identifier => 7, Enabled => True), Into, Error);
         case Mode is
            when Too_Many_Aliases | Overlong_Primary =>
               pragma Assert (Error.Code = Errors.Capacity_Exceeded);
            when Invalid_UTF_8_Primary               =>
               pragma Assert (Error.Code = Errors.Invalid_Text);
            when Duplicate_Primary
               | Alias_On_Other_Field
               | Matcher_No_Match                    =>
               pragma Assert (Error.Code = Errors.Application_Error);
         end case;
         pragma Assert (Into.Event_Count = 0);
      end loop;
   end;

   --  Decode-side metadata rejection consumes no backend byte and still
   --  rolls back the unpublished candidate through the root transaction.
   declare
      Input  : aliased constant String :=
        "{""identifier"":7,""enabled"":true}";
      From   : JSON_Readers.Reader (Input'Access);
      Target : Person_Builder :=
        (Published => (Identifier => 99, Enabled => True), others => <>);
      Error  : Errors.Error_Info;
   begin
      Active_Metadata := Alias_On_Other_Field;
      From.Initialize (Default_Policy);
      Root_Default.Deserialize (From, Target, Error);
      Active_Metadata := Normal_Metadata;
      pragma Assert (Error.Code = Errors.Application_Error);
      pragma Assert (Error.Input_Offset = 0);
      pragma Assert (Error.Offset_Unit = Errors.Byte_Offset);
      pragma Assert (From.Input_Offset = 0);
      pragma Assert (Target.Published = (Identifier => 99, Enabled => True));
      pragma Assert (Target.Rollbacks = 1 and then not Target.Active);
   end;
end Record_Adapter_Tests;
