with Ada.Containers;
with Ada.Finalization;
with Ada.Streams;
with Flyology_Serde.Adapters.Allocating_Sequences;
with Flyology_Serde.Adapters.Signed_Integers;
with Flyology_Serde.Deserialization;
with Flyology_Serde.Deserialization_Adapters;
with Flyology_Serde.Deserializers.CBOR;
with Flyology_Serde.Deserializers.JSON;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;
with Flyology_Serde.Serialization;
with Flyology_Serde.Serializers.CBOR;
with Flyology_Serde.Serializers.JSON;

procedure Allocating_Sequence_Tests is
   package Errors renames Flyology_Serde.Errors;
   package Policies renames Flyology_Serde.Policies;
   package CBOR_Readers renames Flyology_Serde.Deserializers.CBOR;
   package JSON_Readers renames Flyology_Serde.Deserializers.JSON;
   package CBOR_Writers renames Flyology_Serde.Serializers.CBOR;
   package JSON_Writers renames Flyology_Serde.Serializers.JSON;
   use type Ada.Containers.Count_Type;
   use type Ada.Streams.Stream_Element_Array;
   use type Errors.Error_Code;
   use type Errors.Path_Element_Kind;

   subtype Bytes is Ada.Streams.Stream_Element_Array;

   package Integers is new
     Flyology_Serde.Adapters.Signed_Integers (Integer);

   Fail_Serialize_On_Two : Boolean := False;
   Raise_On_Two          : Boolean := False;
   Deserialize_Calls     : Natural := 0;

   procedure Serialize_Integer
     (Item  : Integer;
      Into  : in out Flyology_Serde.Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
   begin
      Integers.Serialize_Value (Item, Into, Error);
      if Error.Code = Errors.No_Error
        and then Fail_Serialize_On_Two
        and then Item = 2
      then
         Errors.Fail (Error, Errors.Application_Error);
      end if;
   end Serialize_Integer;

   procedure Deserialize_Integer
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out Integer;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info) is
      pragma Unreferenced (Policy);
   begin
      Deserialize_Calls := Deserialize_Calls + 1;
      Integers.Deserialize_Candidate (From, Target, Error);
      if Error.Code = Errors.No_Error and then Raise_On_Two and then Target = 2 then
         raise Program_Error with "injected sequence element failure";
      end if;
   end Deserialize_Integer;

   package Integer_Sequences is new
     Flyology_Serde.Adapters.Allocating_Sequences
       (Element_Type        => Integer,
        Serialize_Element   => Serialize_Integer,
        Deserialize_Element => Deserialize_Integer);

   type Integer_Builder is limited record
      Published : Integer_Sequences.Value;
      Candidate : Integer_Sequences.Value;
      Commits   : Natural := 0;
      Rollbacks : Natural := 0;
   end record;

   procedure Begin_Integer_Sequence
     (Target : in out Integer_Builder; Error : in out Errors.Error_Info) is
      pragma Unreferenced (Error);
   begin
      Target.Candidate.Clear;
   end Begin_Integer_Sequence;

   procedure Read_Integer_Sequence
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out Integer_Builder;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info) is
   begin
      Integer_Sequences.Deserialize_Candidate
        (From, Target.Candidate, Policy, Error);
   end Read_Integer_Sequence;

   procedure Commit_Integer_Sequence
     (Target : in out Integer_Builder; Error : in out Errors.Error_Info) is
      pragma Unreferenced (Error);
   begin
      Integer_Sequences.Vectors.Move (Target.Published, Target.Candidate);
      Target.Commits := Target.Commits + 1;
   end Commit_Integer_Sequence;

   procedure Rollback_Integer_Sequence (Target : in out Integer_Builder) is
   begin
      Target.Candidate.Clear;
      Target.Rollbacks := Target.Rollbacks + 1;
   end Rollback_Integer_Sequence;

   Default_Policy : constant Policies.Decode_Policy := (others => <>);

   package Integer_Root is new
     Flyology_Serde.Deserialization_Adapters
       (Builder_Type       => Integer_Builder,
        Policy             => Default_Policy,
        Begin_Candidate    => Begin_Integer_Sequence,
        Deserialize_Value  => Read_Integer_Sequence,
        Commit_Candidate   => Commit_Integer_Sequence,
        Rollback_Candidate => Rollback_Integer_Sequence);

   Live_Controlled : Integer := 0;

   type Controlled_Element is new Ada.Finalization.Controlled with record
      Value : Integer := 0;
   end record;

   overriding procedure Initialize (Self : in out Controlled_Element);
   overriding procedure Adjust (Self : in out Controlled_Element);
   overriding procedure Finalize (Self : in out Controlled_Element);

   overriding procedure Initialize (Self : in out Controlled_Element) is
      pragma Unreferenced (Self);
   begin
      Live_Controlled := Live_Controlled + 1;
   end Initialize;

   overriding procedure Adjust (Self : in out Controlled_Element) is
      pragma Unreferenced (Self);
   begin
      Live_Controlled := Live_Controlled + 1;
   end Adjust;

   overriding procedure Finalize (Self : in out Controlled_Element) is
      pragma Unreferenced (Self);
   begin
      Live_Controlled := Live_Controlled - 1;
   end Finalize;

   function Same_Controlled
     (Left, Right : Controlled_Element) return Boolean
   is (Left.Value = Right.Value);

   Controlled_Mode : Natural := 0;

   procedure Serialize_Controlled
     (Item  : Controlled_Element;
      Into  : in out Flyology_Serde.Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
   begin
      Integers.Serialize_Value (Item.Value, Into, Error);
   end Serialize_Controlled;

   procedure Deserialize_Controlled
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out Controlled_Element;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info) is
      pragma Unreferenced (Policy);
   begin
      Integers.Deserialize_Candidate (From, Target.Value, Error);
      if Error.Code = Errors.No_Error and then Target.Value = 2 then
         if Controlled_Mode = 1 then
            Errors.Fail (Error, Errors.Application_Error);
         elsif Controlled_Mode = 2 then
            raise Program_Error with "injected controlled element failure";
         end if;
      end if;
   end Deserialize_Controlled;

   package Controlled_Sequences is new
     Flyology_Serde.Adapters.Allocating_Sequences
       (Element_Type        => Controlled_Element,
        "="                 => Same_Controlled,
        Serialize_Element   => Serialize_Controlled,
        Deserialize_Element => Deserialize_Controlled);

begin
   --  Serialization emits the same logical sequence through both formats.
   declare
      Item   : Integer_Sequences.Value;
      Output : JSON_Writers.Bounded_Writer (16);
      Buffer : String (1 .. 16);
      Length : Natural;
      Error  : Errors.Error_Info;
   begin
      Item.Append (1);
      Item.Append (2);
      Integer_Sequences.Serialize_Value (Item, Output, Error);
      Output.Finish_Document (Error);
      Output.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Buffer (1 .. Length) = "[1,2]");
   end;

   declare
      Item   : Integer_Sequences.Value;
      Output : JSON_Writers.Bounded_Writer (16);
      Error  : Errors.Error_Info;
   begin
      Item.Append (1);
      Errors.Fail (Error, Errors.Application_Error);
      Integer_Sequences.Serialize_Value (Item, Output, Error);
      pragma Assert (Output.Written_Length = 0);
   end;

   declare
      Item   : Integer_Sequences.Value;
      Output : JSON_Writers.Bounded_Writer (16);
      Error  : Errors.Error_Info;
   begin
      Item.Append (1);
      Item.Append (2);
      Fail_Serialize_On_Two := True;
      Integer_Sequences.Serialize_Value (Item, Output, Error);
      Fail_Serialize_On_Two := False;
      pragma Assert (Error.Code = Errors.Application_Error);
      pragma Assert (Error.Path_Length = 1);
      pragma Assert (Error.Path (1).Kind = Errors.Index_Element);
      pragma Assert (Error.Path (1).Index = 1);
      pragma Assert (not Output.Is_Complete);
      Output.Abort_Document;
   end;

   declare
      Item   : Integer_Sequences.Value;
      Output : CBOR_Writers.Bounded_Writer (16);
      Buffer : Bytes (1 .. 16);
      Length : Natural;
      Error  : Errors.Error_Info;
   begin
      Item.Append (1);
      Item.Append (2);
      Integer_Sequences.Serialize_Value (Item, Output, Error);
      Output.Finish_Document (Error);
      Output.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert
        (Buffer (1 .. Ada.Streams.Stream_Element_Offset (Length))
         = Bytes'[16#82#, 1, 2]);
   end;

   --  JSON unknown length and CBOR indefinite and definite lengths share one
   --  adapter.
   declare
      Input  : aliased constant String := "[1,2]";
      From   : JSON_Readers.Reader (Input'Access);
      Target : Integer_Sequences.Value;
      Error  : Errors.Error_Info;
   begin
      From.Initialize (Default_Policy);
      Integer_Sequences.Deserialize_Candidate
        (From, Target, Default_Policy, Error);
      From.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert
        (Target.Length = 2 and then Target (0) = 1 and then Target (1) = 2);
   end;

   declare
      Input  : aliased constant Bytes := [16#9F#, 1, 2, 16#FF#];
      From   : CBOR_Readers.Reader (Input'Access);
      Target : Integer_Sequences.Value;
      Error  : Errors.Error_Info;
   begin
      From.Initialize (Default_Policy);
      Integer_Sequences.Deserialize_Candidate
        (From, Target, Default_Policy, Error);
      From.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert
        (Target.Length = 2 and then Target (0) = 1 and then Target (1) = 2);
   end;

   declare
      Input  : aliased constant Bytes := [16#82#, 1, 2];
      From   : CBOR_Readers.Reader (Input'Access);
      Target : Integer_Sequences.Value;
      Error  : Errors.Error_Info;
   begin
      From.Initialize (Default_Policy);
      Integer_Sequences.Deserialize_Candidate
        (From, Target, Default_Policy, Error);
      From.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert
        (Target.Length = 2 and then Target (0) = 1 and then Target (1) = 2);
   end;

   --  Zero, exact, and one-over construction limits are deterministic.
   declare
      Policy : Policies.Decode_Policy := (others => <>);
      Input  : aliased constant Bytes := [16#82#, 1, 2];
      From   : CBOR_Readers.Reader (Input'Access);
      Target : Integer_Sequences.Value;
      Error  : Errors.Error_Info;
   begin
      Policy.Limits.Maximum_Container_Items := 1;
      Target.Append (99);
      Deserialize_Calls := 0;
      From.Initialize (Default_Policy);
      Integer_Sequences.Deserialize_Candidate (From, Target, Policy, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
      pragma Assert (Deserialize_Calls = 0);
      pragma Assert (Target.Length = 1 and then Target (0) = 99);
      From.Abort_Document (Error);
   end;

   declare
      Policy : Policies.Decode_Policy := (others => <>);
      Input  : aliased constant String := "[]";
      From   : JSON_Readers.Reader (Input'Access);
      Target : Integer_Sequences.Value;
      Error  : Errors.Error_Info;
   begin
      Policy.Limits.Maximum_Container_Items := 0;
      From.Initialize (Policy);
      Integer_Sequences.Deserialize_Candidate (From, Target, Policy, Error);
      From.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error and then Target.Is_Empty);
   end;

   declare
      Policy : Policies.Decode_Policy := (others => <>);
      Input  : aliased constant Bytes := [16#9F#, 1, 2, 16#FF#];
      From   : CBOR_Readers.Reader (Input'Access);
      Target : Integer_Sequences.Value;
      Error  : Errors.Error_Info;
   begin
      Policy.Limits.Maximum_Container_Items := 2;
      Target.Append (99);
      From.Initialize (Policy);
      Integer_Sequences.Deserialize_Candidate (From, Target, Policy, Error);
      From.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert
        (Target.Length = 2 and then Target (0) = 1 and then Target (1) = 2);
   end;

   declare
      Policy : Policies.Decode_Policy := (others => <>);
      Input  : aliased constant Bytes := [16#9F#, 1, 2, 16#FF#];
      From   : CBOR_Readers.Reader (Input'Access);
      Target : Integer_Sequences.Value;
      Error  : Errors.Error_Info;
   begin
      Policy.Limits.Maximum_Container_Items := 1;
      Target.Append (99);
      --  A permissive backend budget isolates the adapter's stricter
      --  construction-capacity guard. Root operations use one shared policy.
      From.Initialize (Default_Policy);
      Deserialize_Calls := 0;
      Integer_Sequences.Deserialize_Candidate (From, Target, Policy, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
      pragma Assert (Error.Path_Length = 1);
      pragma Assert (Error.Path (1).Kind = Errors.Index_Element);
      pragma Assert (Error.Path (1).Index = 1);
      pragma Assert (Deserialize_Calls = 1);
      pragma Assert (Target.Length = 1 and then Target (0) = 99);
      From.Abort_Document (Error);
   end;

   --  Element status and terminal syntax failure preserve the target and path.
   declare
      Input  : aliased constant String := "[1,""x""]";
      From   : JSON_Readers.Reader (Input'Access);
      Target : Integer_Sequences.Value;
      Error  : Errors.Error_Info;
   begin
      Target.Append (99);
      From.Initialize (Default_Policy);
      Integer_Sequences.Deserialize_Candidate
        (From, Target, Default_Policy, Error);
      pragma Assert (Error.Code = Errors.Unexpected_Kind);
      pragma Assert (Error.Path (1).Kind = Errors.Index_Element);
      pragma Assert (Error.Path (1).Index = 1);
      pragma Assert (Target.Length = 1 and then Target (0) = 99);
      From.Abort_Document (Error);
   end;

   declare
      Input  : aliased constant String := "[1,2";
      From   : JSON_Readers.Reader (Input'Access);
      Target : Integer_Sequences.Value;
      Error  : Errors.Error_Info;
   begin
      Target.Append (99);
      From.Initialize (Default_Policy);
      Integer_Sequences.Deserialize_Candidate
        (From, Target, Default_Policy, Error);
      pragma Assert (Error.Code = Errors.Syntax_Error);
      pragma Assert (Target.Length = 1 and then Target (0) = 99);
      From.Abort_Document (Error);
   end;

   --  A prelatched status touches neither target nor input.
   declare
      Input  : aliased constant String := "[1]";
      From   : JSON_Readers.Reader (Input'Access);
      Target : Integer_Sequences.Value;
      Error  : Errors.Error_Info;
   begin
      Target.Append (99);
      From.Initialize (Default_Policy);
      Errors.Fail (Error, Errors.Application_Error);
      Integer_Sequences.Deserialize_Candidate
        (From, Target, Default_Policy, Error);
      pragma Assert (Target.Length = 1 and then Target (0) = 99);
      Errors.Reset (Error);
      Integer_Sequences.Deserialize_Candidate
        (From, Target, Default_Policy, Error);
      From.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Target.Length = 1 and then Target (0) = 1);
   end;

   --  Root exception handling aborts the reader and rolls back the candidate.
   declare
      Input   : aliased constant String := "[1,2]";
      From    : JSON_Readers.Reader (Input'Access);
      Builder : Integer_Builder;
      Error   : Errors.Error_Info;
      Raised  : Boolean := False;
   begin
      Builder.Published.Append (99);
      From.Initialize (Default_Policy);
      Raise_On_Two := True;
      begin
         Integer_Root.Deserialize (From, Builder, Error);
      exception
         when Program_Error =>
            Raised := True;
      end;
      Raise_On_Two := False;
      pragma Assert (Raised);
      pragma Assert (Builder.Commits = 0 and then Builder.Rollbacks = 1);
      pragma Assert
        (Builder.Published.Length = 1 and then Builder.Published (0) = 99);
   end;

   --  Controlled copies balance on success, status failure, and exception.
   pragma Assert (Live_Controlled = 0);
   Controlled_Mode := 0;
   declare
      Input  : aliased constant String := "[1,2]";
      From   : JSON_Readers.Reader (Input'Access);
      Target : Controlled_Sequences.Value;
      Error  : Errors.Error_Info;
   begin
      From.Initialize (Default_Policy);
      Controlled_Sequences.Deserialize_Candidate
        (From, Target, Default_Policy, Error);
      From.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Target.Length = 2 and then Live_Controlled >= 2);
   end;
   pragma Assert (Live_Controlled = 0);

   Controlled_Mode := 1;
   declare
      Input  : aliased constant String := "[1,2]";
      From   : JSON_Readers.Reader (Input'Access);
      Target : Controlled_Sequences.Value;
      Seed   : Controlled_Element;
      Error  : Errors.Error_Info;
      Baseline : Integer;
   begin
      Seed.Value := 9;
      Target.Append (Seed);
      Baseline := Live_Controlled;
      From.Initialize (Default_Policy);
      Controlled_Sequences.Deserialize_Candidate
        (From, Target, Default_Policy, Error);
      pragma Assert (Error.Code = Errors.Application_Error);
      pragma Assert (Target.Length = 1 and then Target (0).Value = 9);
      pragma Assert (Live_Controlled = Baseline);
      From.Abort_Document (Error);
   end;
   pragma Assert (Live_Controlled = 0);

   Controlled_Mode := 2;
   declare
      Input  : aliased constant String := "[1,2]";
      From   : JSON_Readers.Reader (Input'Access);
      Target : Controlled_Sequences.Value;
      Seed   : Controlled_Element;
      Error  : Errors.Error_Info;
      Raised : Boolean := False;
      Baseline : Integer;
   begin
      Seed.Value := 9;
      Target.Append (Seed);
      Baseline := Live_Controlled;
      From.Initialize (Default_Policy);
      begin
         Controlled_Sequences.Deserialize_Candidate
           (From, Target, Default_Policy, Error);
      exception
         when Program_Error =>
            Raised := True;
            From.Abort_Document (Error);
      end;
      pragma Assert (Raised);
      pragma Assert (Target.Length = 1 and then Target (0).Value = 9);
      pragma Assert (Live_Controlled = Baseline);
   end;
   pragma Assert (Live_Controlled = 0);
end Allocating_Sequence_Tests;
