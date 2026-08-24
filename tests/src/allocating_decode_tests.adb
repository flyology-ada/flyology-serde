with Ada.Containers;
with Ada.Exceptions;
with Ada.Streams;
with Ada.Strings.Unbounded;
with Flyology_Serde.Adapters.Allocating_Bytes;
with Flyology_Serde.Adapters.Allocating_Text;
with Flyology_Serde.Adapters.Optionals;
with Flyology_Serde.Adapters.Signed_Integers;
with Flyology_Serde.Data_Model;
with Flyology_Serde.Deserialization;
with Flyology_Serde.Deserialization_Adapters;
with Flyology_Serde.Deserializers.CBOR;
with Flyology_Serde.Deserializers.CBOR.Copied_Input;
with Flyology_Serde.Deserializers.JSON;
with Flyology_Serde.Deserializers.JSON.Copied_Input;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;
with Flyology_Serde.Serialization;
with Flyology_Serde.Serializers.CBOR;
with Flyology_Serde.Serializers.Counting;
with Flyology_Serde.Serializers.JSON;
with Interfaces;

procedure Allocating_Decode_Tests is
   package Allocating_Bytes renames Flyology_Serde.Adapters.Allocating_Bytes;
   package Allocating_Text renames Flyology_Serde.Adapters.Allocating_Text;
   package CBOR renames Flyology_Serde.Deserializers.CBOR;
   package Data_Model renames Flyology_Serde.Data_Model;
   package Errors renames Flyology_Serde.Errors;
   package JSON renames Flyology_Serde.Deserializers.JSON;
   package Policies renames Flyology_Serde.Policies;
   package Counting renames Flyology_Serde.Serializers.Counting;
   package CBOR_Writers renames Flyology_Serde.Serializers.CBOR;
   package JSON_Writers renames Flyology_Serde.Serializers.JSON;
   use type Ada.Containers.Count_Type;
   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Array;
   use type Ada.Streams.Stream_Element_Offset;
   use type Data_Model.Value_Kind;
   use type Errors.Error_Code;
   use type Errors.Input_Offset_Unit;
   use type Errors.Path_Element_Kind;
   use type Interfaces.Integer_64;

   subtype Bytes is Ada.Streams.Stream_Element_Array;

   package Integers is new
     Flyology_Serde.Adapters.Signed_Integers (Integer);

   type Integer_Builder is limited record
      Published : Integer := 0;
      Candidate : Integer := 0;
      Active    : Boolean := False;
      Commits   : Natural := 0;
      Rollbacks : Natural := 0;
   end record;

   Finish_Observed          : Boolean := False;
   Require_Finish           : Boolean := False;
   Raise_During_Read        : Boolean := False;
   Report_In_Open_Sequence  : Boolean := False;
   Raise_In_Open_Sequence   : Boolean := False;
   Report_During_Commit     : Boolean := False;
   Raise_During_Commit      : Boolean := False;

   procedure Begin_Integer
     (Target : in out Integer_Builder; Error : in out Errors.Error_Info) is
      pragma Unreferenced (Error);
   begin
      Target.Candidate := 0;
      Target.Active := True;
   end Begin_Integer;

   procedure Read_Integer
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out Integer_Builder;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info) is
      pragma Unreferenced (Policy);
      Length    : Data_Model.Length_Information;
      Available : Boolean;
   begin
      if Raise_During_Read then
         raise Program_Error with "injected candidate failure";
      end if;

      if Report_In_Open_Sequence or else Raise_In_Open_Sequence then
         From.Begin_Sequence (Length, Error);
         if Error.Code = Errors.No_Error then
            From.Next_Element (Available, Error);
         end if;
         if Error.Code /= Errors.No_Error then
            return;
         end if;
         pragma Assert (Available);

         if Report_In_Open_Sequence then
            Errors.Push_Field (Error, "payload");
            Errors.Fail (Error, Errors.Application_Error);
            return;
         end if;
         raise Program_Error with "injected open-container failure";
      end if;

      Integers.Deserialize_Candidate (From, Target.Candidate, Error);
   end Read_Integer;

   procedure Commit_Integer
     (Target : in out Integer_Builder; Error : in out Errors.Error_Info) is
   begin
      pragma Assert (not Require_Finish or else Finish_Observed);
      if Report_During_Commit then
         Errors.Fail (Error, Errors.Application_Error);
         return;
      elsif Raise_During_Commit then
         raise Program_Error with "injected commit failure";
      end if;
      Target.Published := Target.Candidate;
      Target.Active := False;
      Target.Commits := Target.Commits + 1;
   end Commit_Integer;

   procedure Rollback_Integer (Target : in out Integer_Builder) is
   begin
      Target.Candidate := 0;
      Target.Active := False;
      Target.Rollbacks := Target.Rollbacks + 1;
   end Rollback_Integer;

   Default_Policy : constant Policies.Decode_Policy := (others => <>);
   One_Byte_Policy : constant Policies.Decode_Policy :=
     (Limits  => (Maximum_Input_Units => 1, others => <>),
      Records => (others => <>));
   Two_Byte_Policy : constant Policies.Decode_Policy :=
     (Limits  => (Maximum_Input_Units => 2, others => <>),
      Records => (others => <>));

   package Root_Default is new
     Flyology_Serde.Deserialization_Adapters
       (Builder_Type       => Integer_Builder,
        Policy             => Default_Policy,
        Begin_Candidate    => Begin_Integer,
        Deserialize_Value  => Read_Integer,
        Commit_Candidate   => Commit_Integer,
        Rollback_Candidate => Rollback_Integer);

   package Root_One_Byte is new
     Flyology_Serde.Deserialization_Adapters
       (Builder_Type       => Integer_Builder,
        Policy             => One_Byte_Policy,
        Begin_Candidate    => Begin_Integer,
        Deserialize_Value  => Read_Integer,
        Commit_Candidate   => Commit_Integer,
        Rollback_Candidate => Rollback_Integer);

   package Root_Two_Bytes is new
     Flyology_Serde.Deserialization_Adapters
       (Builder_Type       => Integer_Builder,
        Policy             => Two_Byte_Policy,
        Begin_Candidate    => Begin_Integer,
        Deserialize_Value  => Read_Integer,
        Commit_Candidate   => Commit_Integer,
        Rollback_Candidate => Rollback_Integer);

   package JSON_Copy_One is new JSON.Copied_Input (Root_One_Byte);
   package JSON_Copy_Two is new JSON.Copied_Input (Root_Two_Bytes);
   package CBOR_Copy_Default is new CBOR.Copied_Input (Root_Default);
   package CBOR_Copy_One is new CBOR.Copied_Input (Root_One_Byte);

   type Finish_Action is (Finish_Succeeds, Finish_Reports, Finish_Raises);

   type Observed_JSON_Reader
     (Source : not null access constant String) is limited
     new JSON.Reader (Source) with record
      Action       : Finish_Action := Finish_Succeeds;
      Finish_Calls : Natural := 0;
   end record;

   overriding
   procedure Finish_Document
     (Self : in out Observed_JSON_Reader;
      Error : in out Errors.Error_Info) is
   begin
      Self.Finish_Calls := Self.Finish_Calls + 1;
      Finish_Observed := True;
      case Self.Action is
         when Finish_Succeeds =>
            JSON.Finish_Document (JSON.Reader (Self), Error);
         when Finish_Reports =>
            Errors.Fail
              (Error,
               Errors.Syntax_Error,
               Self.Input_Offset,
               Errors.Byte_Offset);
         when Finish_Raises =>
            raise Constraint_Error with "injected finish failure";
      end case;
   end Finish_Document;

   type Maybe_Integer is record
      Present : Boolean := False;
      Value   : Integer := 0;
   end record;

   function Is_Present (Item : Maybe_Integer) return Boolean is (Item.Present);

   procedure Serialize_Present
     (Item  : Maybe_Integer;
      Into  : in out Flyology_Serde.Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
   begin
      Integers.Serialize_Value (Item.Value, Into, Error);
   end Serialize_Present;

   procedure Set_Absent
     (Target : in out Maybe_Integer; Error : in out Errors.Error_Info) is
      pragma Unreferenced (Error);
   begin
      Target := (Present => False, Value => 0);
   end Set_Absent;

   procedure Read_Present
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out Maybe_Integer;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info) is
      pragma Unreferenced (Policy);
   begin
      Integers.Deserialize_Candidate (From, Target.Value, Error);
      if Error.Code = Errors.No_Error then
         Target.Present := True;
      end if;
   end Read_Present;

   package Maybe_Integers is new
     Flyology_Serde.Adapters.Optionals
       (Source_Type         => Maybe_Integer,
        Builder_Type        => Maybe_Integer,
        Is_Present          => Is_Present,
        Serialize_Present   => Serialize_Present,
        Set_Absent          => Set_Absent,
        Deserialize_Present => Read_Present);
begin
   --  Finish_Document is exactly inside the root candidate transaction.
   declare
      Input  : aliased constant String := "7";
      From   : Observed_JSON_Reader (Input'Access);
      Target : Integer_Builder := (Published => 3, others => <>);
      Error  : Errors.Error_Info;
   begin
      Finish_Observed := False;
      Require_Finish := True;
      From.Initialize (Root_Default.Configured_Policy);
      Root_Default.Deserialize (From, Target, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (From.Finish_Calls = 1);
      pragma Assert (Target.Published = 7 and then Target.Commits = 1);
      Require_Finish := False;
   end;

   declare
      Input  : aliased constant String := "7";
      From   : Observed_JSON_Reader (Input'Access);
      Target : Integer_Builder := (Published => 3, others => <>);
      Error  : Errors.Error_Info;
   begin
      From.Action := Finish_Reports;
      From.Initialize (Root_Default.Configured_Policy);
      Root_Default.Deserialize (From, Target, Error);
      pragma Assert (Error.Code = Errors.Syntax_Error);
      pragma Assert (From.Finish_Calls = 1);
      pragma Assert (Target.Published = 3 and then Target.Rollbacks = 1);
   end;

   declare
      Input  : aliased constant String := "7";
      From   : Observed_JSON_Reader (Input'Access);
      Target : Integer_Builder := (Published => 3, others => <>);
      Error  : Errors.Error_Info;
      Raised : Boolean := False;
   begin
      From.Action := Finish_Raises;
      From.Initialize (Root_Default.Configured_Policy);
      begin
         Root_Default.Deserialize (From, Target, Error);
      exception
         when Constraint_Error =>
            Raised := True;
      end;
      pragma Assert (Raised and then From.Finish_Calls = 1);
      pragma Assert (Target.Published = 3 and then Target.Rollbacks = 1);
   end;

   declare
      Input  : aliased constant String := "7 trailing";
      From   : JSON.Reader (Input'Access);
      Target : Integer_Builder := (Published => 3, others => <>);
      Error  : Errors.Error_Info;
   begin
      From.Initialize (Root_Default.Configured_Policy);
      Root_Default.Deserialize (From, Target, Error);
      pragma Assert (Error.Code = Errors.Syntax_Error);
      pragma Assert (Target.Published = 3 and then Target.Rollbacks = 1);
   end;

   --  Root failure unwinds open backend scopes, poisons reuse, and preserves
   --  the primary status until an explicit reader reset.
   declare
      Input     : aliased constant String := "[7]";
      From      : JSON.Reader (Input'Access);
      Target    : Integer_Builder := (Published => 3, others => <>);
      Error     : Errors.Error_Info;
      Length    : Data_Model.Length_Information;
      Available : Boolean;
      Value     : Interfaces.Integer_64;
   begin
      Report_In_Open_Sequence := True;
      From.Initialize (Root_Default.Configured_Policy);
      Root_Default.Deserialize (From, Target, Error);
      Report_In_Open_Sequence := False;
      pragma Assert (Error.Code = Errors.Application_Error);
      pragma Assert (Error.Input_Offset = 1);
      pragma Assert (Error.Offset_Unit = Errors.Byte_Offset);
      pragma Assert (Error.Path_Length = 1);
      pragma Assert (Error.Path (1).Kind = Errors.Field_Element);
      pragma Assert (Error.Path (1).Name_Length = 7);
      pragma Assert (Error.Path (1).Name (1 .. 7) = "payload");
      pragma Assert (Target.Published = 3 and then Target.Rollbacks = 1);

      From.Abort_Document (Error);
      pragma Assert (Error.Code = Errors.Application_Error);
      Errors.Reset (Error);
      pragma Assert (From.Peek_Kind (Error) = Data_Model.Null_Value);
      pragma Assert (Error.Code = Errors.Invalid_State);

      Errors.Reset (Error);
      From.Reset (Root_Default.Configured_Policy);
      From.Begin_Sequence (Length, Error);
      From.Next_Element (Available, Error);
      From.Read_Signed (Value, Error);
      pragma Assert (Available and then Value = 7);
      From.Next_Element (Available, Error);
      From.End_Sequence (Error);
      From.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error and then not Available);
   end;

   --  The same unwind and poison contract applies when an adapter raises.
   declare
      Input  : aliased constant Bytes := [16#81#, 7];
      From   : CBOR.Reader (Input'Access);
      Target : Integer_Builder := (Published => 3, others => <>);
      Error  : Errors.Error_Info;
      Raised : Boolean := False;
   begin
      Raise_In_Open_Sequence := True;
      From.Initialize (Root_Default.Configured_Policy);
      begin
         Root_Default.Deserialize (From, Target, Error);
      exception
         when Occurrence : Program_Error =>
            Raised :=
              Ada.Exceptions.Exception_Message (Occurrence)
              = "injected open-container failure";
      end;
      Raise_In_Open_Sequence := False;
      pragma Assert (Raised);
      pragma Assert (Target.Published = 3 and then Target.Rollbacks = 1);
      From.Abort_Document (Error);
      Errors.Reset (Error);
      pragma Assert (From.Peek_Kind (Error) = Data_Model.Null_Value);
      pragma Assert (Error.Code = Errors.Invalid_State);
   end;

   --  A commit status after successful document finishing still aborts the
   --  backend and rolls back without publishing the candidate.
   declare
      Input  : aliased constant String := "7";
      From   : JSON.Reader (Input'Access);
      Target : Integer_Builder := (Published => 3, others => <>);
      Error  : Errors.Error_Info;
   begin
      Report_During_Commit := True;
      From.Initialize (Root_Default.Configured_Policy);
      Root_Default.Deserialize (From, Target, Error);
      Report_During_Commit := False;
      pragma Assert (Error.Code = Errors.Application_Error);
      pragma Assert (Error.Input_Offset = 1);
      pragma Assert (Error.Offset_Unit = Errors.Byte_Offset);
      pragma Assert (not From.Is_Complete);
      pragma Assert (Target.Published = 3 and then Target.Rollbacks = 1);
      Errors.Reset (Error);
      pragma Assert (From.Peek_Kind (Error) = Data_Model.Null_Value);
      pragma Assert (Error.Code = Errors.Invalid_State);
   end;

   --  A commit exception likewise remains primary after abort and rollback.
   declare
      Input  : aliased constant Bytes := [7];
      From   : CBOR.Reader (Input'Access);
      Target : Integer_Builder := (Published => 3, others => <>);
      Error  : Errors.Error_Info;
      Raised : Boolean := False;
   begin
      Raise_During_Commit := True;
      From.Initialize (Root_Default.Configured_Policy);
      begin
         Root_Default.Deserialize (From, Target, Error);
      exception
         when Occurrence : Program_Error =>
            Raised :=
              Ada.Exceptions.Exception_Message (Occurrence)
              = "injected commit failure";
      end;
      Raise_During_Commit := False;
      pragma Assert (Raised and then Error.Code = Errors.No_Error);
      pragma Assert (not From.Is_Complete);
      pragma Assert (Target.Published = 3 and then Target.Rollbacks = 1);
      pragma Assert (From.Peek_Kind (Error) = Data_Model.Null_Value);
      pragma Assert (Error.Code = Errors.Invalid_State);
   end;

   declare
      Input  : aliased constant String := "7 ";
      From   : JSON.Reader (Input'Access);
      Target : Integer_Builder := (Published => 3, others => <>);
      Error  : Errors.Error_Info;
   begin
      From.Initialize (Root_Default.Configured_Policy);
      Root_Default.Deserialize (From, Target, Error);
      pragma Assert (Error.Code = Errors.No_Error and then Target.Published = 7);
   end;

   --  Nested candidate combinators never finish their containing document.
   declare
      Input     : aliased constant String := "[1,7]";
      From      : Observed_JSON_Reader (Input'Access);
      Candidate : Maybe_Integer;
      Error     : Errors.Error_Info;
   begin
      From.Initialize (Default_Policy);
      Maybe_Integers.Deserialize_Candidate
        (From, Candidate, Default_Policy, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Candidate = (Present => True, Value => 7));
      pragma Assert (From.Finish_Calls = 0);
      From.Finish_Document (Error);
   end;

   --  Copied-input facades preflight length before allocating or mutating.
   declare
      Target : Integer_Builder := (Published => 3, others => <>);
      Error  : Errors.Error_Info;
   begin
      JSON_Copy_One.Deserialize ("7", Target, Error);
      pragma Assert (Error.Code = Errors.No_Error and then Target.Published = 7);
      Errors.Reset (Error);
      Target.Published := 3;
      JSON_Copy_One.Deserialize ("7 ", Target, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
      pragma Assert (Error.Input_Offset = 1);
      pragma Assert (Error.Offset_Unit = Errors.Byte_Offset);
      pragma Assert (Target.Published = 3 and then not Target.Active);
   end;

   declare
      Target : Integer_Builder := (Published => 3, others => <>);
      Error  : Errors.Error_Info;
   begin
      JSON_Copy_Two.Deserialize ("7 ", Target, Error);
      pragma Assert (Error.Code = Errors.No_Error and then Target.Published = 7);
   end;

   declare
      Target : Integer_Builder := (Published => 3, others => <>);
      Error  : Errors.Error_Info;
      Raised : Boolean := False;
   begin
      Raise_During_Read := True;
      begin
         JSON_Copy_Two.Deserialize ("7", Target, Error);
      exception
         when Program_Error =>
            Raised := True;
      end;
      Raise_During_Read := False;
      pragma Assert (Raised);
      pragma Assert (Target.Published = 3 and then Target.Rollbacks = 1);
   end;

   declare
      Target : Integer_Builder := (Published => 3, others => <>);
      Error  : Errors.Error_Info;
   begin
      Errors.Fail (Error, Errors.Application_Error);
      JSON_Copy_Two.Deserialize ("7", Target, Error);
      pragma Assert (Target.Published = 3);
      pragma Assert (Target.Commits = 0 and then Target.Rollbacks = 0);
   end;

   declare
      Input  : constant Bytes := [5 => 1];
      Target : Integer_Builder := (Published => 3, others => <>);
      Error  : Errors.Error_Info;
   begin
      CBOR_Copy_One.Deserialize (Input, Target, Error);
      pragma Assert (Error.Code = Errors.No_Error and then Target.Published = 1);
   end;

   declare
      Input  : constant Bytes := [5 => 1, 6 => 0];
      Target : Integer_Builder := (Published => 3, others => <>);
      Error  : Errors.Error_Info;
   begin
      CBOR_Copy_One.Deserialize (Input, Target, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
      pragma Assert (Error.Input_Offset = 1);
      pragma Assert (Target.Published = 3 and then Target.Commits = 0);
   end;

   declare
      Input  : constant Bytes := [1, 0];
      Target : Integer_Builder := (Published => 3, others => <>);
      Error  : Errors.Error_Info;
   begin
      CBOR_Copy_Default.Deserialize (Input, Target, Error);
      pragma Assert (Error.Code = Errors.Syntax_Error);
      pragma Assert (Target.Published = 3 and then Target.Rollbacks = 1);
   end;

   --  Allocating serialization is exact and a no-op for a latched status.
   declare
      Output : JSON_Writers.Bounded_Writer (16);
      Target : constant Allocating_Text.Value :=
        Ada.Strings.Unbounded.To_Unbounded_String ("ab");
      Buffer : String (1 .. 16);
      Length : Natural;
      Error  : Errors.Error_Info;
   begin
      Allocating_Text.Serialize_Value (Target, Output, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      Output.Finish_Document (Error);
      Output.Copy_Output (Buffer, Length, Error);
      pragma Assert (Buffer (1 .. Length) = """ab""");
   end;

   declare
      Output : Counting.Counter;
      Target : constant Allocating_Text.Value :=
        Ada.Strings.Unbounded.To_Unbounded_String ("ab");
      Error  : Errors.Error_Info;
   begin
      Errors.Fail (Error, Errors.Application_Error);
      Allocating_Text.Serialize_Value (Target, Output, Error);
      pragma Assert (Output.Event_Count = 0);
   end;

   declare
      Output : Counting.Counter;
      Target : constant Allocating_Text.Value :=
        Ada.Strings.Unbounded.To_Unbounded_String
          (String'[1 => Character'Val (16#C0#)]);
      Error : Errors.Error_Info;
   begin
      Allocating_Text.Serialize_Value (Target, Output, Error);
      pragma Assert (Error.Code = Errors.Invalid_Text);
      pragma Assert (Output.Event_Count = 0);
   end;

   declare
      Output : CBOR_Writers.Bounded_Writer (16);
      Target : Allocating_Bytes.Value;
      Buffer : Bytes (1 .. 16);
      Length : Natural;
      Error  : Errors.Error_Info;
   begin
      Target.Append (0);
      Target.Append (1);
      Allocating_Bytes.Serialize_Value (Target, Output, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      Output.Finish_Document (Error);
      Output.Copy_Output (Buffer, Length, Error);
      pragma Assert
        (Buffer (1 .. Ada.Streams.Stream_Element_Offset (Length))
         = Bytes'[16#42#, 0, 1]);
   end;

   declare
      Output : Counting.Counter;
      Target : Allocating_Bytes.Value;
      Error  : Errors.Error_Info;
   begin
      Target.Append (0);
      Errors.Fail (Error, Errors.Application_Error);
      Allocating_Bytes.Serialize_Value (Target, Output, Error);
      pragma Assert (Output.Event_Count = 0);
   end;

   --  Allocating text candidates support zero, exact, and exceeded limits.
   declare
      Policy : Policies.Decode_Policy := (others => <>);
      Input  : aliased constant String := """""";
      From   : JSON.Reader (Input'Access);
      Target : Allocating_Text.Value;
      Error  : Errors.Error_Info;
   begin
      Policy.Limits.Maximum_Text_Length := 0;
      From.Initialize (Policy);
      Allocating_Text.Deserialize_Candidate (From, Target, Policy, Error);
      From.Finish_Document (Error);
      pragma Assert (Ada.Strings.Unbounded.Length (Target) = 0);
   end;

   declare
      Policy : Policies.Decode_Policy := (others => <>);
      Input  : aliased constant String := """ab""";
      From   : JSON.Reader (Input'Access);
      Target : Allocating_Text.Value;
      Error  : Errors.Error_Info;
   begin
      Policy.Limits.Maximum_Text_Length := 2;
      From.Initialize (Policy);
      Allocating_Text.Deserialize_Candidate (From, Target, Policy, Error);
      From.Finish_Document (Error);
      pragma Assert (Ada.Strings.Unbounded.To_String (Target) = "ab");
   end;

   declare
      Policy : Policies.Decode_Policy := (others => <>);
      Input  : aliased constant String := """abc""";
      From   : JSON.Reader (Input'Access);
      Target : Allocating_Text.Value;
      Error  : Errors.Error_Info;
   begin
      Policy.Limits.Maximum_Text_Length := 2;
      From.Initialize (Policy);
      Allocating_Text.Deserialize_Candidate (From, Target, Policy, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
      pragma Assert (Ada.Strings.Unbounded.Length (Target) = 0);
   end;

   --  Allocating byte candidates follow the same bounded scratch contract.
   declare
      Policy : Policies.Decode_Policy := (others => <>);
      Input  : aliased constant Bytes := [16#40#];
      From   : CBOR.Reader (Input'Access);
      Target : Allocating_Bytes.Value;
      Error  : Errors.Error_Info;
   begin
      Policy.Limits.Maximum_Byte_Length := 0;
      From.Initialize (Policy);
      Allocating_Bytes.Deserialize_Candidate (From, Target, Policy, Error);
      From.Finish_Document (Error);
      pragma Assert (Target.Length = 0);
   end;

   declare
      Policy : Policies.Decode_Policy := (others => <>);
      Input  : aliased constant Bytes := [16#42#, 0, 1];
      From   : CBOR.Reader (Input'Access);
      Target : Allocating_Bytes.Value;
      Error  : Errors.Error_Info;
   begin
      Policy.Limits.Maximum_Byte_Length := 2;
      From.Initialize (Policy);
      Allocating_Bytes.Deserialize_Candidate (From, Target, Policy, Error);
      From.Finish_Document (Error);
      pragma Assert (Target.Length = 2);
      pragma Assert (Target (0) = 0 and then Target (1) = 1);
   end;

   declare
      Policy : Policies.Decode_Policy := (others => <>);
      Input  : aliased constant Bytes := [16#43#, 0, 1, 2];
      From   : CBOR.Reader (Input'Access);
      Target : Allocating_Bytes.Value;
      Error  : Errors.Error_Info;
   begin
      Policy.Limits.Maximum_Byte_Length := 2;
      From.Initialize (Policy);
      Allocating_Bytes.Deserialize_Candidate (From, Target, Policy, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
      pragma Assert (Target.Length = 0);
   end;

   --  A prelatched status preserves an established allocating candidate.
   declare
      Policy : constant Policies.Decode_Policy := (others => <>);
      Input  : aliased constant String := """new""";
      From   : JSON.Reader (Input'Access);
      Target : Allocating_Text.Value :=
        Ada.Strings.Unbounded.To_Unbounded_String ("old");
      Error  : Errors.Error_Info;
   begin
      Errors.Fail (Error, Errors.Application_Error);
      Allocating_Text.Deserialize_Candidate (From, Target, Policy, Error);
      pragma Assert (Ada.Strings.Unbounded.To_String (Target) = "old");
   end;

   declare
      Policy : constant Policies.Decode_Policy := (others => <>);
      Input  : aliased constant Bytes := [16#41#, 1];
      From   : CBOR.Reader (Input'Access);
      Target : Allocating_Bytes.Value;
      Error  : Errors.Error_Info;
   begin
      Target.Append (99);
      Errors.Fail (Error, Errors.Application_Error);
      Allocating_Bytes.Deserialize_Candidate (From, Target, Policy, Error);
      pragma Assert (Target.Length = 1 and then Target (0) = 99);
   end;

   --  Targets whose Natural range exceeds the stream index range reject an
   --  unrepresentable configured maximum before reading or clearing Target.
   if Natural'Pos (Natural'Last)
     > Ada.Streams.Stream_Element_Offset'Pos
         (Ada.Streams.Stream_Element_Offset'Last)
       - Ada.Streams.Stream_Element_Offset'Pos (0)
   then
      declare
         Policy : Policies.Decode_Policy := (others => <>);
         Input  : aliased constant Bytes := [16#41#, 1];
         From   : CBOR.Reader (Input'Access);
         Target : Allocating_Bytes.Value;
         Error  : Errors.Error_Info;
      begin
         Policy.Limits.Maximum_Byte_Length := Natural'Last;
         From.Initialize (Policy);
         Target.Append (99);
         Allocating_Bytes.Deserialize_Candidate (From, Target, Policy, Error);
         pragma Assert (Error.Code = Errors.Capacity_Exceeded);
         pragma Assert (Target.Length = 1 and then Target (0) = 99);

         Errors.Reset (Error);
         Policy.Limits.Maximum_Byte_Length := 1;
         Allocating_Bytes.Deserialize_Candidate (From, Target, Policy, Error);
         From.Finish_Document (Error);
         pragma Assert (Error.Code = Errors.No_Error);
         pragma Assert (Target.Length = 1 and then Target (0) = 1);
      end;
   end if;
end Allocating_Decode_Tests;
