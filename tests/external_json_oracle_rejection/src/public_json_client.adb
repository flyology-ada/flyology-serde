with Ada.Streams;
with Flyology_Serde.Adapters.Booleans;
with Flyology_Serde.Adapters.Records;
with Flyology_Serde.Adapters.Unsigned_Integers;
with Flyology_Serde.Deserialization;
with Flyology_Serde.Deserialization_Adapters;
with Flyology_Serde.Deserializers.CBOR;
with Flyology_Serde.Deserializers.JSON;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;
with Flyology_Serde.Serialization;
with Flyology_Serde.Serialization_Adapters;
with Flyology_Serde.Serializers.CBOR;
with Flyology_Serde.Serializers.JSON;
with Interfaces;

procedure Public_JSON_Client is
   package CBOR_Readers renames Flyology_Serde.Deserializers.CBOR;
   package CBOR_Writers renames Flyology_Serde.Serializers.CBOR;
   package Errors renames Flyology_Serde.Errors;
   package JSON_Readers renames Flyology_Serde.Deserializers.JSON;
   package JSON_Writers renames Flyology_Serde.Serializers.JSON;
   package Policies renames Flyology_Serde.Policies;
   package Serialization renames Flyology_Serde.Serialization;

   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Array;
   use type Ada.Streams.Stream_Element_Offset;
   use type Errors.Error_Code;
   use type Errors.Path_Element_Kind;
   use type Interfaces.Unsigned_64;

   subtype Byte_Array is Ada.Streams.Stream_Element_Array;
   subtype Byte_Offset is Ada.Streams.Stream_Element_Offset;

   Check_Number : Natural := 0;

   procedure Require (Condition : Boolean) is
   begin
      Check_Number := Check_Number + 1;
      if not Condition then
         raise Program_Error with "check" & Natural'Image (Check_Number);
      end if;
   end Require;

   type Sample is record
      Identifier : Interfaces.Unsigned_64 := 0;
      Enabled    : Boolean := False;
   end record;

   type Sample_Builder is limited record
      Published       : Sample := (Identifier => 0, Enabled => False);
      Candidate       : Sample := (Identifier => 0, Enabled => False);
      Has_Identifier  : Boolean := False;
      Has_Enabled     : Boolean := False;
      Candidate_Ready : Boolean := False;
      Commits         : Natural := 0;
      Rollbacks       : Natural := 0;
   end record;

   type Field is (Identifier_Field, Enabled_Field);

   package Unsigned_64_Values is new
     Flyology_Serde.Adapters.Unsigned_Integers (Interfaces.Unsigned_64);

   function Primary_Name (Item : Field) return String
   is (case Item is
         when Identifier_Field => "identifier",
         when Enabled_Field    => "enabled");

   function Alias_Count (Item : Field) return Natural is
      pragma Unreferenced (Item);
   begin
      return 0;
   end Alias_Count;

   function Alias_Name (Item : Field; Position : Positive) return String is
      pragma Unreferenced (Item, Position);
   begin
      return "";
   end Alias_Name;

   function Matches_Field (Item : Field; Name : String) return Boolean
   is (Name = Primary_Name (Item));

   procedure Serialize_Field
     (Item  : Sample;
      Which : Field;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
   begin
      case Which is
         when Identifier_Field =>
            Unsigned_64_Values.Serialize_Value (Item.Identifier, Into, Error);

         when Enabled_Field    =>
            Flyology_Serde.Adapters.Booleans.Serialize_Value
              (Item.Enabled, Into, Error);
      end case;
   end Serialize_Field;

   procedure Deserialize_Field
     (From      : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target    : in out Sample_Builder;
      Which     : Field;
      Replacing : Boolean;
      Policy    : Policies.Decode_Policy;
      Error     : in out Errors.Error_Info)
   is
      pragma Unreferenced (Policy);
   begin
      if Replacing then
         Errors.Fail (Error, Errors.Invalid_State);
         return;
      end if;

      case Which is
         when Identifier_Field =>
            Unsigned_64_Values.Deserialize_Candidate
              (From, Target.Candidate.Identifier, Error);
            if Error.Code = Errors.No_Error then
               Target.Has_Identifier := True;
            end if;

         when Enabled_Field    =>
            Flyology_Serde.Adapters.Booleans.Deserialize_Candidate
              (From, Target.Candidate.Enabled, Error);
            if Error.Code = Errors.No_Error then
               Target.Has_Enabled := True;
            end if;
      end case;
   end Deserialize_Field;

   procedure Apply_Missing
     (Target  : in out Sample_Builder;
      Which   : Field;
      Policy  : Policies.Decode_Policy;
      Applied : out Boolean;
      Error   : in out Errors.Error_Info)
   is
      pragma Unreferenced (Target, Which, Policy, Error);
   begin
      Applied := False;
   end Apply_Missing;

   procedure Finish_Candidate
     (Target : in out Sample_Builder; Error : in out Errors.Error_Info)
   is
      pragma Unreferenced (Target, Error);
   begin
      null;
   end Finish_Candidate;

   package Samples is new
     Flyology_Serde.Adapters.Records
       (Source_Type               => Sample,
        Builder_Type              => Sample_Builder,
        Field_Ordinal             => Field,
        Type_Name                 => "Public.Sample",
        Maximum_Type_Name_Length  => 32,
        Maximum_Fields            => 2,
        Maximum_Field_Name_Length => 16,
        Maximum_Aliases_Per_Field => 0,
        Primary_Name              => Primary_Name,
        Alias_Count               => Alias_Count,
        Alias_Name                => Alias_Name,
        Matches_Field             => Matches_Field,
        Serialize_Field           => Serialize_Field,
        Deserialize_Field         => Deserialize_Field,
        Apply_Missing             => Apply_Missing,
        Finish_Candidate          => Finish_Candidate);

   Serialization_Limits : constant Serialization.Serialization_Limits :=
     (Maximum_Nesting_Depth   => 8,
      Maximum_Container_Items => 8,
      Maximum_Text_Length     => 64,
      Maximum_Byte_Length     => 64,
      Maximum_Logical_Events  => 16);

   Decode_Policy : constant Policies.Decode_Policy :=
     (Limits  =>
        (Maximum_Nesting_Depth   => 8,
         Maximum_Container_Items => 8,
         Maximum_Text_Length     => 64,
         Maximum_Byte_Length     => 64,
         Maximum_Input_Units     => 128,
         Maximum_Logical_Values  => 16),
      Records =>
        (Unknown_Fields   => Policies.Reject_Unknown,
         Duplicate_Fields => Policies.Reject_Duplicate),
      Maps    => (Duplicate_Keys => Policies.Reject_Duplicate));

   package Root_Serialization is new
     Flyology_Serde.Serialization_Adapters
       (Source_Type     => Sample,
        Limits          => Serialization_Limits,
        Serialize_Value => Samples.Serialize_Value);

   procedure Begin_Sample
     (Target : in out Sample_Builder; Error : in out Errors.Error_Info)
   is
      pragma Unreferenced (Error);
   begin
      Target.Candidate := (Identifier => 0, Enabled => False);
      Target.Has_Identifier := False;
      Target.Has_Enabled := False;
      Target.Candidate_Ready := True;
   end Begin_Sample;

   procedure Commit_Sample
     (Target : in out Sample_Builder; Error : in out Errors.Error_Info)
   is
      pragma Unreferenced (Error);
   begin
      Require
        (Target.Candidate_Ready
         and then Target.Has_Identifier
         and then Target.Has_Enabled);
      Target.Published := Target.Candidate;
      Target.Candidate := (Identifier => 0, Enabled => False);
      Target.Has_Identifier := False;
      Target.Has_Enabled := False;
      Target.Candidate_Ready := False;
      Target.Commits := Target.Commits + 1;
   end Commit_Sample;

   procedure Rollback_Sample (Target : in out Sample_Builder) is
   begin
      Target.Candidate := (Identifier => 0, Enabled => False);
      Target.Has_Identifier := False;
      Target.Has_Enabled := False;
      Target.Candidate_Ready := False;
      if Target.Rollbacks < Natural'Last then
         Target.Rollbacks := Target.Rollbacks + 1;
      end if;
   end Rollback_Sample;

   package Root_Deserialization is new
     Flyology_Serde.Deserialization_Adapters
       (Builder_Type       => Sample_Builder,
        Policy             => Decode_Policy,
        Begin_Candidate    => Begin_Sample,
        Deserialize_Value  => Samples.Deserialize_Candidate,
        Commit_Candidate   => Commit_Sample,
        Rollback_Candidate => Rollback_Sample);

   procedure Require_Clean (Error : Errors.Error_Info) is
   begin
      Require (Error.Code = Errors.No_Error);
      Require (Error.Path_Length = 0);
      Require (Error.Omitted_Path_Elements = 0);
   end Require_Clean;

   procedure Require_Clean_Candidate (Target : Sample_Builder) is
   begin
      Require (Target.Candidate = (Identifier => 0, Enabled => False));
      Require (not Target.Has_Identifier);
      Require (not Target.Has_Enabled);
      Require (not Target.Candidate_Ready);
   end Require_Clean_Candidate;

   procedure Require_Missing_Enabled
     (Error : Errors.Error_Info; Target : Sample_Builder) is
   begin
      Require (Error.Code = Errors.Missing_Field);
      Require (Error.Path_Length = 1);
      Require (Error.Omitted_Path_Elements = 0);
      Require (Error.Path (1).Kind = Errors.Field_Element);
      Require (Error.Path (1).Name_Length = 7);
      Require (Error.Path (1).Name (1 .. 7) = "enabled");
      Require_Clean_Candidate (Target);
   end Require_Missing_Enabled;

   Item : constant Sample := (Identifier => 42, Enabled => True);
begin
   declare
      Writer : JSON_Writers.Bounded_Writer (128);
      Error  : Errors.Error_Info;
   begin
      Root_Serialization.Serialize (Item, Writer, Error);
      Require_Clean (Error);
      Require (Writer.Is_Complete);
      Require (Writer.Written_Length > 0);

      declare
         Expected : constant String := "{""identifier"":42,""enabled"":true}";
         Length   : constant Positive := Writer.Written_Length;
         First    : constant Positive := Positive'Last - Length + 1;
         Output   : aliased String := [First .. Positive'Last => 'X'];
         Written  : Natural := 0;
      begin
         Writer.Copy_Output (Output, Written, Error);
         Require_Clean (Error);
         Require (Written = Length);
         Require (Output = Expected);

         declare
            Reader : JSON_Readers.Reader (Output'Access);
            Target : Sample_Builder;
         begin
            Reader.Initialize (Decode_Policy);
            Root_Deserialization.Deserialize (Reader, Target, Error);
            Require_Clean (Error);
            Require (Reader.Is_Complete);
            Require (Target.Published = Item);
            Require (Target.Commits = 1 and then Target.Rollbacks = 0);
            Require_Clean_Candidate (Target);
         end;

         declare
            Extra          : constant Positive := 7;
            Larger_First   : constant Positive :=
              Positive'Last - (Length + Extra) + 1;
            Prefix_Last    : constant Positive := Larger_First + (Length - 1);
            Larger         : String (Larger_First .. Positive'Last) :=
              [others => 'X'];
            Larger_Written : Natural := 0;
         begin
            Writer.Copy_Output (Larger, Larger_Written, Error);
            Require_Clean (Error);
            Require (Larger_Written = Length);
            Require (Larger (Larger_First .. Prefix_Last) = Expected);
            Require
              (for all Index in Prefix_Last + 1 .. Larger'Last =>
                 Larger (Index) = ' ');
         end;
      end;
   end;

   declare
      Writer : CBOR_Writers.Bounded_Writer (128);
      Error  : Errors.Error_Info;
   begin
      Root_Serialization.Serialize (Item, Writer, Error);
      Require_Clean (Error);
      Require (Writer.Is_Complete);
      Require (Writer.Written_Length > 0);

      declare
         Length  : constant Positive := Writer.Written_Length;
         First   : constant Byte_Offset :=
           Byte_Offset'Last - Byte_Offset (Length) + 1;
         Output  : aliased Byte_Array := [First .. Byte_Offset'Last => 255];
         Written : Natural := 0;
      begin
         Writer.Copy_Output (Output, Written, Error);
         Require_Clean (Error);
         Require (Written = Length);

         declare
            Reader : CBOR_Readers.Reader (Output'Access);
            Target : Sample_Builder;
         begin
            Reader.Initialize (Decode_Policy);
            Root_Deserialization.Deserialize (Reader, Target, Error);
            Require_Clean (Error);
            Require (Reader.Is_Complete);
            Require (Target.Published = Item);
            Require (Target.Commits = 1 and then Target.Rollbacks = 0);
            Require_Clean_Candidate (Target);
         end;

         declare
            Extra          : constant Positive := 7;
            Larger_First   : constant Byte_Offset :=
              Byte_Offset'Last - Byte_Offset (Length + Extra) + 1;
            Prefix_Last    : constant Byte_Offset :=
              Larger_First + Byte_Offset (Length - 1);
            Larger         : Byte_Array (Larger_First .. Byte_Offset'Last) :=
              [others => 255];
            Larger_Written : Natural := 0;
         begin
            Writer.Copy_Output (Larger, Larger_Written, Error);
            Require_Clean (Error);
            Require (Larger_Written = Length);
            Require (Larger (Larger_First .. Prefix_Last) = Output);
            Require
              (for all Index in Prefix_Last + 1 .. Larger'Last =>
                 Larger (Index) = 0);
         end;
      end;
   end;

   declare
      Input  : aliased constant String := "{""identifier"":9}";
      Reader : JSON_Readers.Reader (Input'Access);
      Target : Sample_Builder :=
        (Published       => (Identifier => 777, Enabled => False),
         Candidate       => (Identifier => 0, Enabled => False),
         Has_Identifier  => False,
         Has_Enabled     => False,
         Candidate_Ready => False,
         Commits         => 0,
         Rollbacks       => 0);
      Error  : Errors.Error_Info;
   begin
      Reader.Initialize (Decode_Policy);
      Root_Deserialization.Deserialize (Reader, Target, Error);
      Require_Missing_Enabled (Error, Target);
      Require (Target.Published = (Identifier => 777, Enabled => False));
      Require (Target.Commits = 0 and then Target.Rollbacks = 1);
      Require (not Reader.Is_Complete);

      Errors.Reset (Error);
      Reader.Read_Null (Error);
      Require (Error.Code = Errors.Invalid_State);
      Require_Clean_Candidate (Target);
      Require (Target.Published = (Identifier => 777, Enabled => False));
      Require (Target.Commits = 0 and then Target.Rollbacks = 1);

      Errors.Reset (Error);
      Reader.Reset (Decode_Policy);
      Root_Deserialization.Deserialize (Reader, Target, Error);
      Require_Missing_Enabled (Error, Target);
      Require (Target.Published = (Identifier => 777, Enabled => False));
      Require (Target.Commits = 0 and then Target.Rollbacks = 2);
      Require (not Reader.Is_Complete);
   end;
end Public_JSON_Client;
