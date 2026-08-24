with Ada.Exceptions;
with Ada.Streams;
with Flyology_Serde.Adapters.Nulls;
with Flyology_Serde.Adapters.Optionals;
with Flyology_Serde.Adapters.Signed_Integers;
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

procedure Optional_Parity_Tests is
   package Errors renames Flyology_Serde.Errors;
   package Policies renames Flyology_Serde.Policies;
   package CBOR_Readers renames Flyology_Serde.Deserializers.CBOR;
   package JSON_Readers renames Flyology_Serde.Deserializers.JSON;
   package CBOR_Writers renames Flyology_Serde.Serializers.CBOR;
   package JSON_Writers renames Flyology_Serde.Serializers.JSON;
   use type Ada.Streams.Stream_Element_Array;
   use type Errors.Error_Code;

   subtype Bytes is Ada.Streams.Stream_Element_Array;

   Serialization_Limits : constant
     Flyology_Serde.Serialization.Serialization_Limits :=
       (Maximum_Nesting_Depth   => 8,
        Maximum_Container_Items => 8,
        Maximum_Text_Length     => 64,
        Maximum_Byte_Length     => 64,
        Maximum_Logical_Events  => 32);
   Default_Policy : constant Policies.Decode_Policy := (others => <>);

   package Integers is new
     Flyology_Serde.Adapters.Signed_Integers (Integer);

   type Maybe_Integer is record
      Present : Boolean := False;
      Value   : Integer := 0;
   end record;

   Present_Failure_Mode : Natural := 0;
   Fail_Set_Absent      : Boolean := False;

   function Has_Integer (Item : Maybe_Integer) return Boolean
   is (Item.Present);

   procedure Serialize_Integer
     (Item  : Maybe_Integer;
      Into  : in out Flyology_Serde.Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
   begin
      Integers.Serialize_Value (Item.Value, Into, Error);
   end Serialize_Integer;

   procedure Set_Integer_Absent
     (Target : in out Maybe_Integer; Error : in out Errors.Error_Info) is
   begin
      Target := (Present => False, Value => 0);
      if Fail_Set_Absent then
         Errors.Fail (Error, Errors.Application_Error);
      end if;
   end Set_Integer_Absent;

   procedure Deserialize_Integer
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out Maybe_Integer;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info) is
      pragma Unreferenced (Policy);
   begin
      Integers.Deserialize_Candidate (From, Target.Value, Error);
      if Error.Code = Errors.No_Error then
         Target.Present := True;
         if Present_Failure_Mode = 1 then
            Errors.Fail (Error, Errors.Application_Error);
         elsif Present_Failure_Mode = 2 then
            raise Program_Error with "injected optional child failure";
         end if;
      end if;
   end Deserialize_Integer;

   package Integer_Optionals is new
     Flyology_Serde.Adapters.Optionals
       (Source_Type         => Maybe_Integer,
        Builder_Type        => Maybe_Integer,
        Is_Present          => Has_Integer,
        Serialize_Present   => Serialize_Integer,
        Set_Absent          => Set_Integer_Absent,
        Deserialize_Present => Deserialize_Integer);

   type Maybe_Maybe is record
      Present : Boolean := False;
      Value   : Maybe_Integer;
   end record;

   function Has_Maybe (Item : Maybe_Maybe) return Boolean
   is (Item.Present);

   procedure Serialize_Maybe
     (Item  : Maybe_Maybe;
      Into  : in out Flyology_Serde.Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
   begin
      Integer_Optionals.Serialize_Value (Item.Value, Into, Error);
   end Serialize_Maybe;

   procedure Set_Maybe_Absent
     (Target : in out Maybe_Maybe; Error : in out Errors.Error_Info) is
      pragma Unreferenced (Error);
   begin
      Target := (Present => False, Value => <>);
   end Set_Maybe_Absent;

   procedure Deserialize_Maybe
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out Maybe_Maybe;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info) is
   begin
      Integer_Optionals.Deserialize_Candidate
        (From, Target.Value, Policy, Error);
      if Error.Code = Errors.No_Error then
         Target.Present := True;
      end if;
   end Deserialize_Maybe;

   package Nested_Optionals is new
     Flyology_Serde.Adapters.Optionals
       (Source_Type         => Maybe_Maybe,
        Builder_Type        => Maybe_Maybe,
        Is_Present          => Has_Maybe,
        Serialize_Present   => Serialize_Maybe,
        Set_Absent          => Set_Maybe_Absent,
        Deserialize_Present => Deserialize_Maybe);

   type Maybe_Null is record
      Present          : Boolean := False;
      Constructed      : Boolean := False;
      Construct_Count  : Natural := 0;
   end record;

   procedure Construct_Null
     (Target : in out Maybe_Null; Error : in out Errors.Error_Info) is
      pragma Unreferenced (Error);
   begin
      Target.Present := True;
      Target.Constructed := True;
      Target.Construct_Count := Target.Construct_Count + 1;
   end Construct_Null;

   package Null_Values is new
     Flyology_Serde.Adapters.Nulls
       (Source_Type    => Maybe_Null,
        Builder_Type   => Maybe_Null,
        Construct_Null => Construct_Null);

   function Has_Null (Item : Maybe_Null) return Boolean
   is (Item.Present);

   procedure Serialize_Null
     (Item  : Maybe_Null;
      Into  : in out Flyology_Serde.Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
   begin
      Null_Values.Serialize_Value (Item, Into, Error);
   end Serialize_Null;

   procedure Set_Null_Absent
     (Target : in out Maybe_Null; Error : in out Errors.Error_Info) is
      pragma Unreferenced (Error);
   begin
      Target := (others => <>);
   end Set_Null_Absent;

   procedure Deserialize_Null
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out Maybe_Null;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info) is
      pragma Unreferenced (Policy);
   begin
      Null_Values.Deserialize_Candidate (From, Target, Error);
   end Deserialize_Null;

   package Null_Optionals is new
     Flyology_Serde.Adapters.Optionals
       (Source_Type         => Maybe_Null,
        Builder_Type        => Maybe_Null,
        Is_Present          => Has_Null,
        Serialize_Present   => Serialize_Null,
        Set_Absent          => Set_Null_Absent,
        Deserialize_Present => Deserialize_Null);

   generic
      type Value_Type is private;
      Default_Value : Value_Type;
      with
        procedure Serialize_Value
          (Item  : Value_Type;
           Into  : in out Flyology_Serde.Serialization.Serializer'Class;
           Error : in out Errors.Error_Info);
      with
        procedure Deserialize_Value
          (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
           Target : in out Value_Type;
           Policy : Policies.Decode_Policy;
           Error  : in out Errors.Error_Info);
   package Root_Support is
      type Builder is limited private;

      procedure Initialize (Target : in out Builder; Value : Value_Type);
      function Published_Value (Target : Builder) return Value_Type;
      function Commit_Count (Target : Builder) return Natural;
      function Rollback_Count (Target : Builder) return Natural;

      procedure Serialize
        (Item  : Value_Type;
         Into  : in out Flyology_Serde.Serialization.Serializer'Class;
         Error : in out Errors.Error_Info);
      procedure Deserialize
        (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
         Target : in out Builder;
         Error  : in out Errors.Error_Info);

   private
      type Builder is limited record
         Published : Value_Type := Default_Value;
         Candidate : Value_Type := Default_Value;
         Commits   : Natural := 0;
         Rollbacks : Natural := 0;
      end record;
   end Root_Support;

   package body Root_Support is
      procedure Begin_Candidate
        (Target : in out Builder; Error : in out Errors.Error_Info) is
         pragma Unreferenced (Error);
      begin
         Target.Candidate := Default_Value;
      end Begin_Candidate;

      procedure Read_Candidate
        (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
         Target : in out Builder;
         Policy : Policies.Decode_Policy;
         Error  : in out Errors.Error_Info) is
      begin
         Deserialize_Value (From, Target.Candidate, Policy, Error);
      end Read_Candidate;

      procedure Commit_Candidate
        (Target : in out Builder; Error : in out Errors.Error_Info) is
         pragma Unreferenced (Error);
      begin
         Target.Published := Target.Candidate;
         Target.Commits := Target.Commits + 1;
      end Commit_Candidate;

      procedure Rollback_Candidate (Target : in out Builder) is
      begin
         Target.Candidate := Default_Value;
         Target.Rollbacks := Target.Rollbacks + 1;
      end Rollback_Candidate;

      package Serialization_Root is new
        Flyology_Serde.Serialization_Adapters
          (Source_Type     => Value_Type,
           Limits          => Serialization_Limits,
           Serialize_Value => Serialize_Value);

      package Deserialization_Root is new
        Flyology_Serde.Deserialization_Adapters
          (Builder_Type       => Builder,
           Policy             => Default_Policy,
           Begin_Candidate    => Begin_Candidate,
           Deserialize_Value  => Read_Candidate,
           Commit_Candidate   => Commit_Candidate,
           Rollback_Candidate => Rollback_Candidate);

      procedure Initialize (Target : in out Builder; Value : Value_Type) is
      begin
         Target.Published := Value;
         Target.Candidate := Value;
      end Initialize;

      function Published_Value (Target : Builder) return Value_Type
      is (Target.Published);

      function Commit_Count (Target : Builder) return Natural
      is (Target.Commits);

      function Rollback_Count (Target : Builder) return Natural
      is (Target.Rollbacks);

      procedure Serialize
        (Item  : Value_Type;
         Into  : in out Flyology_Serde.Serialization.Serializer'Class;
         Error : in out Errors.Error_Info) is
      begin
         Serialization_Root.Serialize (Item, Into, Error);
      end Serialize;

      procedure Deserialize
        (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
         Target : in out Builder;
         Error  : in out Errors.Error_Info) is
      begin
         Deserialization_Root.Deserialize (From, Target, Error);
      end Deserialize;
   end Root_Support;

   package Integer_Root is new Root_Support
     (Value_Type        => Maybe_Integer,
      Default_Value     => (others => <>),
      Serialize_Value   => Integer_Optionals.Serialize_Value,
      Deserialize_Value => Integer_Optionals.Deserialize_Candidate);

   package Nested_Root is new Root_Support
     (Value_Type        => Maybe_Maybe,
      Default_Value     => (others => <>),
      Serialize_Value   => Nested_Optionals.Serialize_Value,
      Deserialize_Value => Nested_Optionals.Deserialize_Candidate);

   package Null_Root is new Root_Support
     (Value_Type        => Maybe_Null,
      Default_Value     => (others => <>),
      Serialize_Value   => Null_Optionals.Serialize_Value,
      Deserialize_Value => Null_Optionals.Deserialize_Candidate);

   procedure Check_JSON_Integer
     (Item : Maybe_Integer; Expected : String) is
      Output : JSON_Writers.Bounded_Writer (32);
      Buffer : String (1 .. 32);
      Length : Natural;
      Error  : Errors.Error_Info;
   begin
      Integer_Root.Serialize (Item, Output, Error);
      Output.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Buffer (1 .. Length) = Expected);
      declare
         Input  : aliased constant String := Buffer (1 .. Length);
         Reader : JSON_Readers.Reader (Input'Access);
         Target : Integer_Root.Builder;
      begin
         Reader.Initialize (Default_Policy);
         Integer_Root.Deserialize (Reader, Target, Error);
         pragma Assert (Error.Code = Errors.No_Error);
         pragma Assert (Integer_Root.Published_Value (Target) = Item);
         pragma Assert (Integer_Root.Commit_Count (Target) = 1);
         pragma Assert (Integer_Root.Rollback_Count (Target) = 0);
      end;
   end Check_JSON_Integer;

   procedure Check_CBOR_Integer
     (Item : Maybe_Integer; Expected : Bytes) is
      Output : CBOR_Writers.Bounded_Writer (32);
      Buffer : Bytes (1 .. 32);
      Length : Natural;
      Error  : Errors.Error_Info;
   begin
      Integer_Root.Serialize (Item, Output, Error);
      Output.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert
        (Buffer (1 .. Ada.Streams.Stream_Element_Offset (Length)) = Expected);
      declare
         Input  : aliased constant Bytes :=
           Buffer (1 .. Ada.Streams.Stream_Element_Offset (Length));
         Reader : CBOR_Readers.Reader (Input'Access);
         Target : Integer_Root.Builder;
      begin
         Reader.Initialize (Default_Policy);
         Integer_Root.Deserialize (Reader, Target, Error);
         pragma Assert (Error.Code = Errors.No_Error);
         pragma Assert (Integer_Root.Published_Value (Target) = Item);
         pragma Assert (Integer_Root.Commit_Count (Target) = 1);
         pragma Assert (Integer_Root.Rollback_Count (Target) = 0);
      end;
   end Check_CBOR_Integer;

   procedure Check_JSON_Nested
     (Item : Maybe_Maybe; Expected : String) is
      Output : JSON_Writers.Bounded_Writer (32);
      Buffer : String (1 .. 32);
      Length : Natural;
      Error  : Errors.Error_Info;
   begin
      Nested_Root.Serialize (Item, Output, Error);
      Output.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Buffer (1 .. Length) = Expected);
      declare
         Input  : aliased constant String := Buffer (1 .. Length);
         Reader : JSON_Readers.Reader (Input'Access);
         Target : Nested_Root.Builder;
      begin
         Reader.Initialize (Default_Policy);
         Nested_Root.Deserialize (Reader, Target, Error);
         pragma Assert (Error.Code = Errors.No_Error);
         pragma Assert (Nested_Root.Published_Value (Target) = Item);
         pragma Assert (Nested_Root.Commit_Count (Target) = 1);
         pragma Assert (Nested_Root.Rollback_Count (Target) = 0);
      end;
   end Check_JSON_Nested;

   procedure Check_CBOR_Nested
     (Item : Maybe_Maybe; Expected : Bytes) is
      Output : CBOR_Writers.Bounded_Writer (32);
      Buffer : Bytes (1 .. 32);
      Length : Natural;
      Error  : Errors.Error_Info;
   begin
      Nested_Root.Serialize (Item, Output, Error);
      Output.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert
        (Buffer (1 .. Ada.Streams.Stream_Element_Offset (Length)) = Expected);
      declare
         Input  : aliased constant Bytes :=
           Buffer (1 .. Ada.Streams.Stream_Element_Offset (Length));
         Reader : CBOR_Readers.Reader (Input'Access);
         Target : Nested_Root.Builder;
      begin
         Reader.Initialize (Default_Policy);
         Nested_Root.Deserialize (Reader, Target, Error);
         pragma Assert (Error.Code = Errors.No_Error);
         pragma Assert (Nested_Root.Published_Value (Target) = Item);
         pragma Assert (Nested_Root.Commit_Count (Target) = 1);
         pragma Assert (Nested_Root.Rollback_Count (Target) = 0);
      end;
   end Check_CBOR_Nested;

   procedure Check_JSON_Null
     (Present : Boolean; Expected : String) is
      Item   : constant Maybe_Null := (Present => Present, others => <>);
      Output : JSON_Writers.Bounded_Writer (32);
      Buffer : String (1 .. 32);
      Length : Natural;
      Error  : Errors.Error_Info;
   begin
      Null_Root.Serialize (Item, Output, Error);
      Output.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Buffer (1 .. Length) = Expected);
      declare
         Input  : aliased constant String := Buffer (1 .. Length);
         Reader : JSON_Readers.Reader (Input'Access);
         Target : Null_Root.Builder;
         Result : Maybe_Null;
      begin
         Reader.Initialize (Default_Policy);
         Null_Root.Deserialize (Reader, Target, Error);
         Result := Null_Root.Published_Value (Target);
         pragma Assert (Error.Code = Errors.No_Error);
         pragma Assert (Result.Present = Present);
         pragma Assert (Result.Constructed = Present);
         pragma Assert (Result.Construct_Count = (if Present then 1 else 0));
         pragma Assert (Null_Root.Commit_Count (Target) = 1);
         pragma Assert (Null_Root.Rollback_Count (Target) = 0);
      end;
   end Check_JSON_Null;

   procedure Check_CBOR_Null
     (Present : Boolean; Expected : Bytes) is
      Item   : constant Maybe_Null := (Present => Present, others => <>);
      Output : CBOR_Writers.Bounded_Writer (32);
      Buffer : Bytes (1 .. 32);
      Length : Natural;
      Error  : Errors.Error_Info;
   begin
      Null_Root.Serialize (Item, Output, Error);
      Output.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert
        (Buffer (1 .. Ada.Streams.Stream_Element_Offset (Length)) = Expected);
      declare
         Input  : aliased constant Bytes :=
           Buffer (1 .. Ada.Streams.Stream_Element_Offset (Length));
         Reader : CBOR_Readers.Reader (Input'Access);
         Target : Null_Root.Builder;
         Result : Maybe_Null;
      begin
         Reader.Initialize (Default_Policy);
         Null_Root.Deserialize (Reader, Target, Error);
         Result := Null_Root.Published_Value (Target);
         pragma Assert (Error.Code = Errors.No_Error);
         pragma Assert (Result.Present = Present);
         pragma Assert (Result.Constructed = Present);
         pragma Assert (Result.Construct_Count = (if Present then 1 else 0));
         pragma Assert (Null_Root.Commit_Count (Target) = 1);
         pragma Assert (Null_Root.Rollback_Count (Target) = 0);
      end;
   end Check_CBOR_Null;

begin
   Check_JSON_Integer ((Present => False, Value => 0), "[0]");
   Check_JSON_Integer ((Present => True, Value => 7), "[1,7]");
   Check_CBOR_Integer ((Present => False, Value => 0), Bytes'[16#81#, 0]);
   Check_CBOR_Integer ((Present => True, Value => 7), Bytes'[16#82#, 1, 7]);

   Check_JSON_Nested ((Present => False, Value => <>), "[0]");
   Check_JSON_Nested
     ((Present => True, Value => (Present => False, Value => 0)), "[1,[0]]");
   Check_CBOR_Nested
     ((Present => False, Value => <>), Bytes'[16#81#, 0]);
   Check_CBOR_Nested
     ((Present => True, Value => (Present => False, Value => 0)),
      Bytes'[16#82#, 1, 16#81#, 0]);

   Check_JSON_Null (False, "[0]");
   Check_JSON_Null (True, "[1,null]");
   Check_CBOR_Null (False, Bytes'[16#81#, 0]);
   Check_CBOR_Null (True, Bytes'[16#82#, 1, 16#F6#]);

   --  A status after consuming the child triggers abort and rollback, then reset reuses the reader.
   declare
      Input  : aliased constant String := "[1,7]";
      Reader : JSON_Readers.Reader (Input'Access);
      Target : Integer_Root.Builder;
      Error  : Errors.Error_Info;
   begin
      Integer_Root.Initialize (Target, (Present => True, Value => 9));
      Present_Failure_Mode := 1;
      Reader.Initialize (Default_Policy);
      Integer_Root.Deserialize (Reader, Target, Error);
      Present_Failure_Mode := 0;
      pragma Assert (Error.Code = Errors.Application_Error);
      pragma Assert (Integer_Root.Commit_Count (Target) = 0);
      pragma Assert (Integer_Root.Rollback_Count (Target) = 1);
      pragma Assert
        (Integer_Root.Published_Value (Target) = (Present => True, Value => 9));
      pragma Assert (not Reader.Is_Complete);
      Reader.Reset (Default_Policy);
      Errors.Reset (Error);
      Integer_Root.Deserialize (Reader, Target, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert
        (Integer_Root.Published_Value (Target) = (Present => True, Value => 7));
   end;

   --  An exception after consuming the child remains primary and also rolls back.
   declare
      Input  : aliased constant Bytes := [16#82#, 1, 7];
      Reader : CBOR_Readers.Reader (Input'Access);
      Target : Integer_Root.Builder;
      Error  : Errors.Error_Info;
      Raised : Boolean := False;
   begin
      Integer_Root.Initialize (Target, (Present => True, Value => 9));
      Present_Failure_Mode := 2;
      Reader.Initialize (Default_Policy);
      begin
         Integer_Root.Deserialize (Reader, Target, Error);
      exception
         when Occurrence : Program_Error =>
            Raised :=
              Ada.Exceptions.Exception_Message (Occurrence) =
                "injected optional child failure";
      end;
      Present_Failure_Mode := 0;
      pragma Assert (Raised and then Error.Code = Errors.No_Error);
      pragma Assert (Integer_Root.Commit_Count (Target) = 0);
      pragma Assert (Integer_Root.Rollback_Count (Target) = 1);
      pragma Assert
        (Integer_Root.Published_Value (Target) = (Present => True, Value => 9));
      pragma Assert (not Reader.Is_Complete);

      Integer_Root.Deserialize (Reader, Target, Error);
      pragma Assert (Error.Code = Errors.Invalid_State);
      pragma Assert (Integer_Root.Commit_Count (Target) = 0);
      pragma Assert (Integer_Root.Rollback_Count (Target) = 2);
      pragma Assert
        (Integer_Root.Published_Value (Target) = (Present => True, Value => 9));

      Reader.Reset (Default_Policy);
      Errors.Reset (Error);
      Integer_Root.Deserialize (Reader, Target, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Integer_Root.Commit_Count (Target) = 1);
      pragma Assert (Integer_Root.Rollback_Count (Target) = 2);
      pragma Assert
        (Integer_Root.Published_Value (Target) = (Present => True, Value => 7));
   end;

   --  Set_Absent status failure mutates only the unpublished candidate.
   declare
      Input  : aliased constant String := "[0]";
      Reader : JSON_Readers.Reader (Input'Access);
      Target : Integer_Root.Builder;
      Error  : Errors.Error_Info;
   begin
      Integer_Root.Initialize (Target, (Present => True, Value => 9));
      Fail_Set_Absent := True;
      Reader.Initialize (Default_Policy);
      Integer_Root.Deserialize (Reader, Target, Error);
      Fail_Set_Absent := False;
      pragma Assert (Error.Code = Errors.Application_Error);
      pragma Assert (Integer_Root.Commit_Count (Target) = 0);
      pragma Assert (Integer_Root.Rollback_Count (Target) = 1);
      pragma Assert
        (Integer_Root.Published_Value (Target) = (Present => True, Value => 9));
   end;

   --  Direct prelatched optional traversal touches neither candidate nor reader.
   declare
      Input     : aliased constant String := "[1,7]";
      Reader    : JSON_Readers.Reader (Input'Access);
      Candidate : Maybe_Integer := (Present => True, Value => 9);
      Error     : Errors.Error_Info;
   begin
      Reader.Initialize (Default_Policy);
      Errors.Fail (Error, Errors.Application_Error);
      Integer_Optionals.Deserialize_Candidate
        (Reader, Candidate, Default_Policy, Error);
      pragma Assert (Candidate = (Present => True, Value => 9));
      pragma Assert (Reader.Input_Offset = 0);
      Errors.Reset (Error);
      Integer_Optionals.Deserialize_Candidate
        (Reader, Candidate, Default_Policy, Error);
      Reader.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Candidate = (Present => True, Value => 7));
   end;
end Optional_Parity_Tests;
