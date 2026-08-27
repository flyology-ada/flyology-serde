with Ada.Streams;
with Flyology_Serde.Adapters.Fixed_Arrays;
with Flyology_Serde.Adapters.Signed_Integers;
with Flyology_Serde.Deserialization;
with Flyology_Serde.Deserialization_Adapters;
with Flyology_Serde.Deserializers.CBOR;
with Flyology_Serde.Deserializers.JSON;
with Flyology_Serde.Errors;
with Flyology_Serde.Fixed_Array_Testing;
with Flyology_Serde.Policies;
with Flyology_Serde.Serialization;
with Flyology_Serde.Serialization_Adapters;
with Flyology_Serde.Serializers.CBOR;
with Flyology_Serde.Serializers.Counting;
with Flyology_Serde.Serializers.JSON;

procedure Fixed_Array_Adapter_Tests is
   package Errors renames Flyology_Serde.Errors;
   package Policies renames Flyology_Serde.Policies;
   package CBOR_Readers renames Flyology_Serde.Deserializers.CBOR;
   package CBOR_Writers renames Flyology_Serde.Serializers.CBOR;
   package JSON_Readers renames Flyology_Serde.Deserializers.JSON;
   package JSON_Writers renames Flyology_Serde.Serializers.JSON;
   package Counting renames Flyology_Serde.Serializers.Counting;
   package Test_Hooks renames Flyology_Serde.Fixed_Array_Testing;

   use type Ada.Streams.Stream_Element_Array;
   use type Errors.Error_Code;
   use type Errors.Path_Element_Kind;
   use type Flyology_Serde.Serialization.Serializer_State;

   type Position is (First, Second, Third);
   for Position use (First => 7, Second => 19, Third => 41);

   type Palette is array (Position) of Integer;

   package Integers is new Flyology_Serde.Adapters.Signed_Integers (Integer);

   procedure Deserialize_Integer
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out Integer;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info)
   is
      pragma Unreferenced (Policy);
   begin
      Integers.Deserialize_Candidate (From, Target, Error);
   end Deserialize_Integer;

   package Palettes is new
     Flyology_Serde.Adapters.Fixed_Arrays
       (Index_Type          => Position,
        Element_Type        => Integer,
        Array_Type          => Palette,
        Serialize_Element   => Integers.Serialize_Value,
        Deserialize_Element => Deserialize_Integer);

   subtype Bytes is Ada.Streams.Stream_Element_Array;

   Expected : constant Palette := [1, 2, 3];
   Prior    : constant Palette := [8, 9, 10];

   Prior_Read_Position : Natural := 0;

   procedure Deserialize_Integer_Reading_Prior
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out Integer;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info)
   is
      Index : constant Position := Position'Val (Prior_Read_Position);
   begin
      pragma Assert (Target = Prior (Index));
      Deserialize_Integer (From, Target, Policy, Error);
      if Error.Code = Errors.No_Error then
         Prior_Read_Position := Prior_Read_Position + 1;
      end if;
   end Deserialize_Integer_Reading_Prior;

   package Prior_Reading_Palettes is new
     Flyology_Serde.Adapters.Fixed_Arrays
       (Index_Type          => Position,
        Element_Type        => Integer,
        Array_Type          => Palette,
        Serialize_Element   => Integers.Serialize_Value,
        Deserialize_Element => Deserialize_Integer_Reading_Prior);

   Raise_During_Deserialization : Boolean := False;

   procedure Deserialize_Integer_With_Failure
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out Integer;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info) is
   begin
      if Raise_During_Deserialization and then Target = Prior (Second) then
         raise Storage_Error with "requested fixed-array element failure";
      end if;
      Deserialize_Integer (From, Target, Policy, Error);
   end Deserialize_Integer_With_Failure;

   package Exploding_Deserialize_Palettes is new
     Flyology_Serde.Adapters.Fixed_Arrays
       (Index_Type          => Position,
        Element_Type        => Integer,
        Array_Type          => Palette,
        Serialize_Element   => Integers.Serialize_Value,
        Deserialize_Element => Deserialize_Integer_With_Failure);

   Raise_During_Serialization : Boolean := False;

   procedure Serialize_Integer_With_Failure
     (Item  : Integer;
      Into  : in out Flyology_Serde.Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
   begin
      if Raise_During_Serialization and then Item = Expected (Second) then
         raise Program_Error with "requested fixed-array element failure";
      end if;
      Integers.Serialize_Value (Item, Into, Error);
   end Serialize_Integer_With_Failure;

   package Exploding_Palettes is new
     Flyology_Serde.Adapters.Fixed_Arrays
       (Index_Type          => Position,
        Element_Type        => Integer,
        Array_Type          => Palette,
        Serialize_Element   => Serialize_Integer_With_Failure,
        Deserialize_Element => Deserialize_Integer);

   Serialization_Limits :
     constant Flyology_Serde.Serialization.Serialization_Limits :=
       (Maximum_Nesting_Depth   => 4,
        Maximum_Container_Items => 3,
        Maximum_Text_Length     => 32,
        Maximum_Byte_Length     => 32,
        Maximum_Logical_Events  => 5);

   package Root_Serialization is new
     Flyology_Serde.Serialization_Adapters
       (Source_Type     => Palette,
        Limits          => Serialization_Limits,
        Serialize_Value => Exploding_Palettes.Serialize_Value);

   function Default_Policy return Policies.Decode_Policy
   is (others => <>);

   Root_Policy : constant Policies.Decode_Policy := Default_Policy;

   type Palette_Builder is limited record
      Published : Palette := Prior;
      Candidate : Palette := Prior;
      Ready     : Boolean := False;
      Commits   : Natural := 0;
      Rollbacks : Natural := 0;
   end record;

   procedure Begin_Palette
     (Target : in out Palette_Builder; Error : in out Errors.Error_Info)
   is
      pragma Unreferenced (Error);
   begin
      Target.Candidate := Target.Published;
      Target.Ready := True;
   end Begin_Palette;

   procedure Deserialize_Palette
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out Palette_Builder;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info) is
   begin
      if Raise_During_Deserialization then
         Exploding_Deserialize_Palettes.Deserialize_Candidate
           (From, Target.Candidate, Policy, Error);
      else
         Palettes.Deserialize_Candidate
           (From, Target.Candidate, Policy, Error);
      end if;
   end Deserialize_Palette;

   procedure Commit_Palette
     (Target : in out Palette_Builder; Error : in out Errors.Error_Info)
   is
      pragma Unreferenced (Error);
   begin
      pragma Assert (Target.Ready);
      Target.Published := Target.Candidate;
      Target.Ready := False;
      Target.Commits := Target.Commits + 1;
   end Commit_Palette;

   procedure Rollback_Palette (Target : in out Palette_Builder) is
   begin
      Target.Candidate := Target.Published;
      Target.Ready := False;
      Target.Rollbacks := Target.Rollbacks + 1;
   end Rollback_Palette;

   package Root_Deserialization is new
     Flyology_Serde.Deserialization_Adapters
       (Builder_Type       => Palette_Builder,
        Policy             => Root_Policy,
        Begin_Candidate    => Begin_Palette,
        Deserialize_Value  => Deserialize_Palette,
        Commit_Candidate   => Commit_Palette,
        Rollback_Candidate => Rollback_Palette);

   type End_Failing_Reader (Source : not null access constant String) is
      limited new JSON_Readers.Reader (Source)
   with record
      End_Attempts : Natural := 0;
   end record;

   overriding
   procedure End_Sequence
     (Self : in out End_Failing_Reader; Error : in out Errors.Error_Info) is
   begin
      Self.End_Attempts := Self.End_Attempts + 1;
      Errors.Fail (Error, Errors.Application_Error);
   end End_Sequence;

   procedure Assert_JSON_Success is
      Source : aliased constant String := "[1,2,3]";
      Reader : JSON_Readers.Reader (Source'Access);
      Target : Palette := Prior;
      Error  : Errors.Error_Info;
   begin
      JSON_Readers.Initialize (Reader, Default_Policy);
      Palettes.Deserialize_Candidate (Reader, Target, Default_Policy, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Error.Path_Length = 0);
      Reader.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Target = Expected);
   end Assert_JSON_Success;

   procedure Assert_CBOR_Success is
      Source : aliased constant Bytes := [16#83#, 1, 2, 3];
      Reader : CBOR_Readers.Reader (Source'Access);
      Target : Palette := Prior;
      Error  : Errors.Error_Info;
   begin
      CBOR_Readers.Initialize (Reader, Default_Policy);
      Palettes.Deserialize_Candidate (Reader, Target, Default_Policy, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      Reader.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Target = Expected);
   end Assert_CBOR_Success;

   procedure Assert_JSON_Failure
     (Source_Text    : String;
      Expected_Code  : Errors.Error_Code;
      Expected_Path  : Natural;
      Expected_Index : Natural := 0)
   is
      Source : aliased constant String := Source_Text;
      Reader : JSON_Readers.Reader (Source'Access);
      Target : Palette := Prior;
      Error  : Errors.Error_Info;
   begin
      JSON_Readers.Initialize (Reader, Default_Policy);
      Palettes.Deserialize_Candidate (Reader, Target, Default_Policy, Error);
      pragma Assert (Error.Code = Expected_Code);
      pragma Assert (Error.Path_Length = Expected_Path);
      if Expected_Path > 0 then
         pragma
           Assert (Error.Path (Expected_Path).Kind = Errors.Index_Element);
         pragma Assert (Error.Path (Expected_Path).Index = Expected_Index);
      end if;
      pragma Assert (Target = Prior);
      Reader.Abort_Document (Error);
   end Assert_JSON_Failure;

   procedure Assert_CBOR_Length_Failure (Source_Bytes : Bytes) is
      Source : aliased constant Bytes := Source_Bytes;
      Reader : CBOR_Readers.Reader (Source'Access);
      Target : Palette := Prior;
      Error  : Errors.Error_Info;
   begin
      CBOR_Readers.Initialize (Reader, Default_Policy);
      Palettes.Deserialize_Candidate (Reader, Target, Default_Policy, Error);
      pragma Assert (Error.Code = Errors.Out_Of_Range);
      pragma Assert (Error.Path_Length = 0);
      pragma Assert (Target = Prior);
      Reader.Abort_Document (Error);
   end Assert_CBOR_Length_Failure;

begin
   Assert_JSON_Success;
   Assert_CBOR_Success;
   Assert_JSON_Failure ("[1,2]", Errors.Out_Of_Range, 1, 2);
   Assert_JSON_Failure ("[1,2,3,4]", Errors.Out_Of_Range, 1, 3);
   Assert_JSON_Failure ("[1,false,3]", Errors.Unexpected_Kind, 1, 1);
   Assert_JSON_Failure ("[1,2,3", Errors.Syntax_Error, 0);
   Assert_CBOR_Length_Failure ([16#82#, 1, 2]);
   Assert_CBOR_Length_Failure ([16#84#, 1, 2, 3, 4]);

   declare
      Source : aliased constant String := "[1,2,3]";
      Reader : JSON_Readers.Reader (Source'Access);
      Target : Palette := Prior;
      Error  : Errors.Error_Info;
   begin
      Prior_Read_Position := 0;
      JSON_Readers.Initialize (Reader, Default_Policy);
      Prior_Reading_Palettes.Deserialize_Candidate
        (Reader, Target, Default_Policy, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Prior_Read_Position = Target'Length);
      pragma Assert (Target = Expected);
      Reader.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error);
   end;

   declare
      Source : aliased constant String := "[1,2,3]";
      Reader : End_Failing_Reader (Source'Access);
      Target : Palette := Prior;
      Error  : Errors.Error_Info;
   begin
      Reader.Initialize (Default_Policy);
      Palettes.Deserialize_Candidate (Reader, Target, Default_Policy, Error);
      pragma Assert (Error.Code = Errors.Application_Error);
      pragma Assert (Error.Path_Length = 0);
      pragma Assert (Reader.End_Attempts = 1);
      pragma Assert (Target = Prior);
      Reader.Abort_Document (Error);
   end;

   declare
      Writer : JSON_Writers.Bounded_Writer (32);
      Error  : Errors.Error_Info;
      Text   : String (1 .. 32);
      Length : Natural := 0;
   begin
      Palettes.Serialize_Value (Expected, Writer, Error);
      Writer.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error);
      Writer.Copy_Output (Text, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Text (1 .. Length) = "[1,2,3]");
   end;

   declare
      Writer : CBOR_Writers.Bounded_Writer (16);
      Error  : Errors.Error_Info;
      Buffer : Bytes (1 .. 16);
      Length : Natural := 0;
   begin
      Palettes.Serialize_Value (Expected, Writer, Error);
      Writer.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error);
      Writer.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma
        Assert
          (Buffer (1 .. Ada.Streams.Stream_Element_Offset (Length))
             = [16#83#, 1, 2, 3]);
   end;

   declare
      Source : aliased constant String := "[1,2,3]";
      Reader : JSON_Readers.Reader (Source'Access);
      Target : Palette := Prior;
      Error  : Errors.Error_Info;
      Policy : Policies.Decode_Policy := Default_Policy;
   begin
      Policy.Limits.Maximum_Container_Items := Target'Length;
      JSON_Readers.Initialize (Reader, Policy);
      Palettes.Deserialize_Candidate (Reader, Target, Policy, Error);
      Reader.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Target = Expected);
   end;

   declare
      Source : aliased constant String := "[1,2,3]";
      Reader : JSON_Readers.Reader (Source'Access);
      Target : Palette := Prior;
      Error  : Errors.Error_Info;
      Policy : Policies.Decode_Policy := Default_Policy;
   begin
      Policy.Limits.Maximum_Logical_Values := 3;
      JSON_Readers.Initialize (Reader, Policy);
      Palettes.Deserialize_Candidate (Reader, Target, Policy, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
      pragma Assert (Error.Path_Length = 1);
      pragma Assert (Error.Path (1).Kind = Errors.Index_Element);
      pragma Assert (Error.Path (1).Index = 2);
      pragma Assert (Target = Prior);
      Reader.Abort_Document (Error);
   end;

   declare
      Counter : Counting.Counter;
      Error   : Errors.Error_Info;
   begin
      Counting.Reset
        (Counter, Counting.Data_Model.All_Capabilities, Serialization_Limits);
      Palettes.Serialize_Value (Expected, Counter, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Counter.Event_Count = 5);
      pragma Assert (Counter.Container_Depth = 0);
      Counter.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error);
   end;

   declare
      Counter : Counting.Counter;
      Error   : Errors.Error_Info;
      Limits  : Flyology_Serde.Serialization.Serialization_Limits :=
        Serialization_Limits;
   begin
      Limits.Maximum_Logical_Events := 4;
      Counting.Reset (Counter, Counting.Data_Model.All_Capabilities, Limits);
      Palettes.Serialize_Value (Expected, Counter, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
      pragma Assert (Error.Path_Length = 0);
      pragma Assert (Counter.Event_Count = 4);
      pragma Assert (Counter.Container_Depth = 0);
      pragma Assert (Counter.State = Flyology_Serde.Serialization.Poisoned);
      Counter.Abort_Document;
   end;

   declare
      Source : aliased constant String := "[1,2,3]";
      Reader : JSON_Readers.Reader (Source'Access);
      Target : Palette_Builder;
      Error  : Errors.Error_Info;
      Raised : Boolean := False;
   begin
      JSON_Readers.Initialize (Reader, Root_Policy);
      Raise_During_Deserialization := True;
      begin
         Root_Deserialization.Deserialize (Reader, Target, Error);
      exception
         when Storage_Error =>
            Raised := True;
      end;
      Raise_During_Deserialization := False;
      pragma Assert (Raised);
      pragma Assert (Target.Published = Prior);
      pragma Assert (Target.Candidate = Prior);
      pragma Assert (not Target.Ready);
      pragma Assert (Target.Commits = 0);
      pragma Assert (Target.Rollbacks = 1);

      Errors.Reset (Error);
      JSON_Readers.Reset (Reader, Root_Policy);
      Root_Deserialization.Deserialize (Reader, Target, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Target.Published = Expected);
      pragma Assert (Target.Commits = 1);
      pragma Assert (Target.Rollbacks = 1);
   end;

   declare
      Writer : JSON_Writers.Bounded_Writer (32);
      Error  : Errors.Error_Info;
      Raised : Boolean := False;
      Text   : String (1 .. 32);
      Length : Natural := 0;
   begin
      Raise_During_Serialization := True;
      begin
         Root_Serialization.Serialize (Expected, Writer, Error);
      exception
         when Program_Error =>
            Raised := True;
      end;
      Raise_During_Serialization := False;
      pragma Assert (Raised);
      pragma Assert (Writer.State = Flyology_Serde.Serialization.Poisoned);
      pragma Assert (Writer.Written_Length = 0);

      Errors.Reset (Error);
      Writer.Reset;
      Root_Serialization.Serialize (Expected, Writer, Error);
      Writer.Copy_Output (Text, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Text (1 .. Length) = "[1,2,3]");
   end;

   declare
      Source : aliased constant String := "[1,2,3]";
      Reader : JSON_Readers.Reader (Source'Access);
      Target : Palette := Prior;
      Error  : Errors.Error_Info;
      Before : constant Natural := Test_Hooks.Candidate_Attempts;
      Policy : Policies.Decode_Policy := Default_Policy;
   begin
      Policy.Limits.Maximum_Container_Items := 2;
      JSON_Readers.Initialize (Reader, Policy);
      Palettes.Deserialize_Candidate (Reader, Target, Policy, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
      pragma Assert (JSON_Readers.Input_Offset (Reader) = 0);
      pragma Assert (Test_Hooks.Candidate_Attempts = Before);
      pragma Assert (Target = Prior);
      Reader.Abort_Document (Error);
   end;

   declare
      Source : aliased constant String := "[1,2,3]";
      Reader : JSON_Readers.Reader (Source'Access);
      Target : Palette := Prior;
      Error  : Errors.Error_Info;
   begin
      JSON_Readers.Initialize (Reader, Default_Policy);
      Errors.Fail (Error, Errors.Application_Error);
      Palettes.Deserialize_Candidate (Reader, Target, Default_Policy, Error);
      pragma Assert (Error.Code = Errors.Application_Error);
      pragma Assert (JSON_Readers.Input_Offset (Reader) = 0);
      pragma Assert (Target = Prior);
   end;

   declare
      Writer : JSON_Writers.Bounded_Writer (32);
      Error  : Errors.Error_Info;
   begin
      Errors.Fail (Error, Errors.Application_Error);
      Palettes.Serialize_Value (Expected, Writer, Error);
      pragma Assert (Error.Code = Errors.Application_Error);
      pragma Assert (Writer.Written_Length = 0);
   end;

   declare
      Source : aliased constant String := "[1,2,3]";
      Reader : JSON_Readers.Reader (Source'Access);
      Target : Palette := Prior;
      Error  : Errors.Error_Info;
      Before : constant Natural := Test_Hooks.Candidate_Attempts;
   begin
      JSON_Readers.Initialize (Reader, Default_Policy);
      Test_Hooks.Arm_Candidate_Failure;
      begin
         Palettes.Deserialize_Candidate
           (Reader, Target, Default_Policy, Error);
         raise Program_Error
           with "fixed-array candidate failure was not injected";
      exception
         when Storage_Error =>
            null;
      end;
      pragma Assert (Test_Hooks.Candidate_Attempts = Before + 1);
      Errors.Reset (Error);
      Reader.Abort_Document (Error);
      Test_Hooks.Disarm;
   end;
end Fixed_Array_Adapter_Tests;
