with Ada.Containers;
with Ada.Exceptions;
with Ada.Finalization;
with Ada.Streams;
with Ada.Strings.Unbounded;
with Flyology_Serde.Adapters.Allocating_Maps;
with Flyology_Serde.Adapters.Allocating_Text;
with Flyology_Serde.Adapters.Signed_Integers;
with Flyology_Serde.Deserialization;
with Flyology_Serde.Deserialization_Adapters;
with Flyology_Serde.Data_Model;
with Flyology_Serde.Deserializers.CBOR;
with Flyology_Serde.Deserializers.JSON;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;
with Flyology_Serde.Serialization;
with Flyology_Serde.Serialization_Adapters;
with Flyology_Serde.Serializers.CBOR;
with Flyology_Serde.Serializers.Counting;
with Flyology_Serde.Serializers.JSON;

procedure Allocating_Map_Tests is
   package Errors renames Flyology_Serde.Errors;
   package Data_Model renames Flyology_Serde.Data_Model;
   package Policies renames Flyology_Serde.Policies;
   package CBOR_Readers renames Flyology_Serde.Deserializers.CBOR;
   package JSON_Readers renames Flyology_Serde.Deserializers.JSON;
   package CBOR_Writers renames Flyology_Serde.Serializers.CBOR;
   package JSON_Writers renames Flyology_Serde.Serializers.JSON;
   package Counting renames Flyology_Serde.Serializers.Counting;
   package Text renames Flyology_Serde.Adapters.Allocating_Text;
   package Unbounded renames Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;
   use type Ada.Streams.Stream_Element_Array;
   use type Errors.Error_Code;
   use type Errors.Path_Element_Kind;
   use type Text.Value;

   subtype Bytes is Ada.Streams.Stream_Element_Array;

   type Restricted_JSON_Reader
     (Source : not null access constant String) is
     limited new JSON_Readers.Reader (Source) with null record;

   overriding
   function Capabilities
     (Self : Restricted_JSON_Reader) return Data_Model.Format_Capabilities;

   overriding
   function Capabilities
     (Self : Restricted_JSON_Reader) return Data_Model.Format_Capabilities is
      pragma Unreferenced (Self);
   begin
      return
        (Unknown_Container_Lengths => True,
         Byte_Values               => True,
         Nonfinite_Float_64        => True,
         Signed_Float_Zero         => True,
         Arbitrary_Map_Keys        => False,
         Lossless_Optionals        => True);
   end Capabilities;

   package Integers is new
     Flyology_Serde.Adapters.Signed_Integers (Integer);

   function Text_Less (Left, Right : Text.Value) return Boolean
   is (Left < Right);

   Key_Calls                 : Natural := 0;
   Element_Calls             : Natural := 0;
   Serialized_Key_Calls      : Natural := 0;
   Serialized_Element_Calls  : Natural := 0;
   Key_Failure_Mode          : Natural := 0;
   Element_Failure_Mode      : Natural := 0;

   procedure Serialize_Key
     (Item  : Text.Value;
      Into  : in out Flyology_Serde.Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
   begin
      Serialized_Key_Calls := Serialized_Key_Calls + 1;
      Text.Serialize_Value (Item, Into, Error);
   end Serialize_Key;

   procedure Serialize_Element
     (Item  : Integer;
      Into  : in out Flyology_Serde.Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
   begin
      Serialized_Element_Calls := Serialized_Element_Calls + 1;
      Integers.Serialize_Value (Item, Into, Error);
   end Serialize_Element;

   procedure Deserialize_Key
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out Text.Value;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info) is
   begin
      Key_Calls := Key_Calls + 1;
      Text.Deserialize_Candidate (From, Target, Policy, Error);
      if Error.Code = Errors.No_Error
        and then Unbounded.To_String (Target) = "b"
      then
         if Key_Failure_Mode = 1 then
            Errors.Fail (Error, Errors.Application_Error);
         elsif Key_Failure_Mode = 2 then
            raise Program_Error with "injected map key failure";
         end if;
      end if;
   end Deserialize_Key;

   procedure Deserialize_Element
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out Integer;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info) is
      pragma Unreferenced (Policy);
   begin
      Element_Calls := Element_Calls + 1;
      Integers.Deserialize_Candidate (From, Target, Error);
      if Error.Code = Errors.No_Error and then Target = 2 then
         if Element_Failure_Mode = 1 then
            Errors.Fail (Error, Errors.Application_Error);
         elsif Element_Failure_Mode = 2 then
            raise Program_Error with "injected map element failure";
         end if;
      end if;
   end Deserialize_Element;

   package Integer_Maps is new
     Flyology_Serde.Adapters.Allocating_Maps
       (Key_Type                  => Text.Value,
        Element_Type              => Integer,
        "<"                       => Text_Less,
        Keys_Use_Restricted_Kinds => True,
        Serialize_Key             => Serialize_Key,
        Serialize_Element         => Serialize_Element,
        Deserialize_Key           => Deserialize_Key,
        Deserialize_Element       => Deserialize_Element);

   package Conservative_Maps is new
     Flyology_Serde.Adapters.Allocating_Maps
       (Key_Type                  => Text.Value,
        Element_Type              => Integer,
        "<"                       => Text_Less,
        Keys_Use_Restricted_Kinds => False,
        Serialize_Key             => Serialize_Key,
        Serialize_Element         => Serialize_Element,
        Deserialize_Key           => Deserialize_Key,
        Deserialize_Element       => Deserialize_Element);

   function Key (Value : String) return Text.Value
   is (Unbounded.To_Unbounded_String (Value));

   Test_Limits : constant Policies.Decode_Limits :=
     (Maximum_Nesting_Depth   => 8,
      Maximum_Container_Items => 8,
      Maximum_Text_Length     => 16,
      Maximum_Byte_Length     => 16,
      Maximum_Input_Units     => 128,
      Maximum_Logical_Values  => 32);
   Reject_Policy : constant Policies.Decode_Policy :=
     (Limits  => Test_Limits,
      Records => (others => <>),
      Maps    => (Duplicate_Keys => Policies.Reject_Duplicate));
   Keep_First_Policy : constant Policies.Decode_Policy :=
     (Limits  => Test_Limits,
      Records => (others => <>),
      Maps    => (Duplicate_Keys => Policies.Keep_First));
   Keep_Last_Policy : constant Policies.Decode_Policy :=
     (Limits  => Test_Limits,
      Records => (others => <>),
      Maps    => (Duplicate_Keys => Policies.Keep_Last));

   Serialization_Limits : constant
     Flyology_Serde.Serialization.Serialization_Limits :=
       (Maximum_Nesting_Depth   => 8,
        Maximum_Container_Items => 8,
        Maximum_Text_Length     => 16,
        Maximum_Byte_Length     => 16,
        Maximum_Logical_Events  => 32);

   package Map_Serialization is new
     Flyology_Serde.Serialization_Adapters
       (Source_Type     => Integer_Maps.Value,
        Limits          => Serialization_Limits,
        Serialize_Value => Integer_Maps.Serialize_Value);

   type Map_Builder is limited record
      Published : Integer_Maps.Value;
      Candidate : Integer_Maps.Value;
      Commits   : Natural := 0;
      Rollbacks : Natural := 0;
   end record;

   procedure Begin_Map
     (Target : in out Map_Builder; Error : in out Errors.Error_Info) is
      pragma Unreferenced (Error);
   begin
      Target.Candidate.Clear;
   end Begin_Map;

   procedure Read_Map
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out Map_Builder;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info) is
   begin
      Integer_Maps.Deserialize_Candidate
        (From, Target.Candidate, Policy, Error);
   end Read_Map;

   procedure Commit_Map
     (Target : in out Map_Builder; Error : in out Errors.Error_Info) is
      pragma Unreferenced (Error);
   begin
      Integer_Maps.Maps.Move (Target.Published, Target.Candidate);
      Target.Commits := Target.Commits + 1;
   end Commit_Map;

   procedure Rollback_Map (Target : in out Map_Builder) is
   begin
      Target.Candidate.Clear;
      Target.Rollbacks := Target.Rollbacks + 1;
   end Rollback_Map;

   package Reject_Root is new
     Flyology_Serde.Deserialization_Adapters
       (Builder_Type       => Map_Builder,
        Policy             => Reject_Policy,
        Begin_Candidate    => Begin_Map,
        Deserialize_Value  => Read_Map,
        Commit_Candidate   => Commit_Map,
        Rollback_Candidate => Rollback_Map);

   package Keep_First_Root is new
     Flyology_Serde.Deserialization_Adapters
       (Builder_Type       => Map_Builder,
        Policy             => Keep_First_Policy,
        Begin_Candidate    => Begin_Map,
        Deserialize_Value  => Read_Map,
        Commit_Candidate   => Commit_Map,
        Rollback_Candidate => Rollback_Map);

   package Keep_Last_Root is new
     Flyology_Serde.Deserialization_Adapters
       (Builder_Type       => Map_Builder,
        Policy             => Keep_Last_Policy,
        Begin_Candidate    => Begin_Map,
        Deserialize_Value  => Read_Map,
        Commit_Candidate   => Commit_Map,
        Rollback_Candidate => Rollback_Map);

   procedure Seed (Target : in out Integer_Maps.Value) is
   begin
      Target.Insert (Key ("z"), 9);
   end Seed;

   procedure Assert_Duplicate_Result
     (Target : Integer_Maps.Value; Value : Integer) is
   begin
      pragma Assert (Target.Length = 1);
      pragma Assert (Target.Contains (Key ("a")));
      pragma Assert (Target.Element (Key ("a")) = Value);
      pragma Assert
        (Unbounded.To_String (Integer_Maps.Maps.Key (Target.First)) = "a",
         "stored key=" &
           Unbounded.To_String (Integer_Maps.Maps.Key (Target.First)));
   end Assert_Duplicate_Result;

   procedure Decode_JSON
     (Input  : aliased String;
      Policy : Policies.Decode_Policy;
      Target : in out Integer_Maps.Value;
      Error  : in out Errors.Error_Info) is
      Reader : JSON_Readers.Reader (Input'Unchecked_Access);
   begin
      Reader.Initialize (Policy);
      Integer_Maps.Deserialize_Candidate (Reader, Target, Policy, Error);
      if Error.Code = Errors.No_Error then
         Reader.Finish_Document (Error);
      end if;
   end Decode_JSON;

   procedure Decode_CBOR
     (Input  : aliased Bytes;
      Policy : Policies.Decode_Policy;
      Target : in out Integer_Maps.Value;
      Error  : in out Errors.Error_Info) is
      Reader : CBOR_Readers.Reader (Input'Unchecked_Access);
   begin
      Reader.Initialize (Policy);
      Integer_Maps.Deserialize_Candidate (Reader, Target, Policy, Error);
      if Error.Code = Errors.No_Error then
         Reader.Finish_Document (Error);
      end if;
   end Decode_CBOR;

   Live_Keys     : Integer := 0;
   Live_Elements : Integer := 0;

   type Controlled_Key is new Ada.Finalization.Controlled with record
      Raw : Integer := 0;
   end record;

   overriding procedure Initialize (Self : in out Controlled_Key);
   overriding procedure Adjust (Self : in out Controlled_Key);
   overriding procedure Finalize (Self : in out Controlled_Key);

   overriding procedure Initialize (Self : in out Controlled_Key) is
      pragma Unreferenced (Self);
   begin
      Live_Keys := Live_Keys + 1;
   end Initialize;

   overriding procedure Adjust (Self : in out Controlled_Key) is
      pragma Unreferenced (Self);
   begin
      Live_Keys := Live_Keys + 1;
   end Adjust;

   overriding procedure Finalize (Self : in out Controlled_Key) is
      pragma Unreferenced (Self);
   begin
      Live_Keys := Live_Keys - 1;
   end Finalize;

   type Controlled_Element is new Ada.Finalization.Controlled with record
      Value : Integer := 0;
   end record;

   overriding procedure Initialize (Self : in out Controlled_Element);
   overriding procedure Adjust (Self : in out Controlled_Element);
   overriding procedure Finalize (Self : in out Controlled_Element);

   overriding procedure Initialize (Self : in out Controlled_Element) is
      pragma Unreferenced (Self);
   begin
      Live_Elements := Live_Elements + 1;
   end Initialize;

   overriding procedure Adjust (Self : in out Controlled_Element) is
      pragma Unreferenced (Self);
   begin
      Live_Elements := Live_Elements + 1;
   end Adjust;

   overriding procedure Finalize (Self : in out Controlled_Element) is
      pragma Unreferenced (Self);
   begin
      Live_Elements := Live_Elements - 1;
   end Finalize;

   function Controlled_Less
     (Left, Right : Controlled_Key) return Boolean
   is (Left.Raw mod 2 < Right.Raw mod 2);

   function Same_Controlled
     (Left, Right : Controlled_Element) return Boolean
   is (Left.Value = Right.Value);

   procedure Serialize_Controlled_Key
     (Item  : Controlled_Key;
      Into  : in out Flyology_Serde.Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
   begin
      Integers.Serialize_Value (Item.Raw, Into, Error);
   end Serialize_Controlled_Key;

   procedure Deserialize_Controlled_Key
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out Controlled_Key;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info) is
      pragma Unreferenced (Policy);
   begin
      Integers.Deserialize_Candidate (From, Target.Raw, Error);
   end Deserialize_Controlled_Key;

   Controlled_Failure_Mode : Natural := 0;

   procedure Serialize_Controlled_Element
     (Item  : Controlled_Element;
      Into  : in out Flyology_Serde.Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
   begin
      Integers.Serialize_Value (Item.Value, Into, Error);
   end Serialize_Controlled_Element;

   procedure Deserialize_Controlled_Element
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out Controlled_Element;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info) is
      pragma Unreferenced (Policy);
   begin
      Integers.Deserialize_Candidate (From, Target.Value, Error);
      if Error.Code = Errors.No_Error and then Target.Value = 20 then
         if Controlled_Failure_Mode = 1 then
            Errors.Fail (Error, Errors.Application_Error);
         elsif Controlled_Failure_Mode = 2 then
            raise Program_Error with "injected controlled map failure";
         end if;
      end if;
   end Deserialize_Controlled_Element;

   package Controlled_Maps is new
     Flyology_Serde.Adapters.Allocating_Maps
       (Key_Type                  => Controlled_Key,
        Element_Type              => Controlled_Element,
        "<"                       => Controlled_Less,
        "="                       => Same_Controlled,
        Keys_Use_Restricted_Kinds => False,
        Serialize_Key             => Serialize_Controlled_Key,
        Serialize_Element         => Serialize_Controlled_Element,
        Deserialize_Key           => Deserialize_Controlled_Key,
        Deserialize_Element       => Deserialize_Controlled_Element);

begin
   --  Root serialization traverses the same comparator order twice.
   declare
      Item   : Integer_Maps.Value;
      Output : JSON_Writers.Bounded_Writer (32);
      Buffer : String (1 .. 32);
      Length : Natural;
      Error  : Errors.Error_Info;
   begin
      Item.Insert (Key ("b"), 2);
      Item.Insert (Key ("a"), 1);
      Serialized_Key_Calls := 0;
      Serialized_Element_Calls := 0;
      Map_Serialization.Serialize (Item, Output, Error);
      Output.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Buffer (1 .. Length) = "[[""a"",1],[""b"",2]]");
      pragma Assert (Serialized_Key_Calls = 4);
      pragma Assert (Serialized_Element_Calls = 4);
   end;

   declare
      Item   : Integer_Maps.Value;
      Output : CBOR_Writers.Bounded_Writer (32);
      Buffer : Bytes (1 .. 32);
      Length : Natural;
      Error  : Errors.Error_Info;
   begin
      Item.Insert (Key ("b"), 2);
      Item.Insert (Key ("a"), 1);
      Map_Serialization.Serialize (Item, Output, Error);
      Output.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert
        (Buffer (1 .. Ada.Streams.Stream_Element_Offset (Length)) =
           Bytes'[16#A2#, 16#61#, Character'Pos ('a'), 1,
                  16#61#, Character'Pos ('b'), 2]);
   end;

   declare
      Empty_JSON : JSON_Writers.Bounded_Writer (4);
      Empty_CBOR : CBOR_Writers.Bounded_Writer (4);
      Item       : Integer_Maps.Value;
      Text_Out   : String (1 .. 4);
      Byte_Out   : Bytes (1 .. 4);
      Length     : Natural;
      Error      : Errors.Error_Info;
   begin
      Map_Serialization.Serialize (Item, Empty_JSON, Error);
      Empty_JSON.Copy_Output (Text_Out, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Text_Out (1 .. Length) = "[]");
      Errors.Reset (Error);
      Map_Serialization.Serialize (Item, Empty_CBOR, Error);
      Empty_CBOR.Copy_Output (Byte_Out, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Byte_Out (1 .. 1) = Bytes'[16#A0#]);
   end;

   declare
      Item   : Integer_Maps.Value;
      Output : JSON_Writers.Bounded_Writer (8);
      Error  : Errors.Error_Info;
   begin
      Item.Insert (Key ("a"), 1);
      Errors.Fail (Error, Errors.Application_Error);
      Integer_Maps.Serialize_Value (Item, Output, Error);
      pragma Assert (Output.Written_Length = 0);
   end;

   --  A prelatched candidate call consumes no input and changes no target.
   declare
      Input  : aliased constant String := "[[""a"",1]]";
      From   : JSON_Readers.Reader (Input'Access);
      Target : Integer_Maps.Value;
      Error  : Errors.Error_Info;
   begin
      Seed (Target);
      Key_Calls := 0;
      Element_Calls := 0;
      From.Initialize (Reject_Policy);
      Errors.Fail (Error, Errors.Application_Error);
      Integer_Maps.Deserialize_Candidate
        (From, Target, Reject_Policy, Error);
      pragma Assert (From.Input_Offset = 0);
      pragma Assert (Key_Calls = 0 and then Element_Calls = 0);
      pragma Assert (Target.Length = 1 and then Target.Element (Key ("z")) = 9);

      Errors.Reset (Error);
      Integer_Maps.Deserialize_Candidate
        (From, Target, Reject_Policy, Error);
      From.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Target.Length = 1 and then Target.Element (Key ("a")) = 1);
   end;

   --  JSON unknown length and CBOR definite and indefinite maps share one adapter.
   declare
      Target : Integer_Maps.Value;
      Error  : Errors.Error_Info;
      Input  : aliased constant String := "[[""a"",1],[""b"",2]]";
   begin
      Seed (Target);
      Decode_JSON (Input, Reject_Policy, Target, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Target.Length = 2);
      pragma Assert (not Target.Contains (Key ("z")));
      pragma Assert (Target.Element (Key ("a")) = 1);
      pragma Assert (Target.Element (Key ("b")) = 2);
   end;

   declare
      Target : Integer_Maps.Value;
      Error  : Errors.Error_Info;
      Input  : aliased constant Bytes :=
        [16#A2#, 16#61#, Character'Pos ('a'), 1,
         16#61#, Character'Pos ('b'), 2];
   begin
      Decode_CBOR (Input, Reject_Policy, Target, Error);
      pragma Assert (Error.Code = Errors.No_Error and then Target.Length = 2);
   end;

   declare
      Target : Integer_Maps.Value;
      Error  : Errors.Error_Info;
      Input  : aliased constant Bytes :=
        [16#BF#, 16#61#, Character'Pos ('a'), 1,
         16#61#, Character'Pos ('b'), 2, 16#FF#];
   begin
      Decode_CBOR (Input, Reject_Policy, Target, Error);
      pragma Assert (Error.Code = Errors.No_Error and then Target.Length = 2);
   end;

   --  Identical text keys exercise every duplicate policy in both formats.
   declare
      Input  : aliased constant String := "[[""a"",1],[""a"",2]]";
      Target : Integer_Maps.Value;
      Error  : Errors.Error_Info;
   begin
      Seed (Target);
      Decode_JSON (Input, Reject_Policy, Target, Error);
      pragma Assert (Error.Code = Errors.Duplicate_Key);
      pragma Assert (Target.Length = 1 and then Target.Element (Key ("z")) = 9);
   end;

   declare
      Input  : aliased constant String := "[[""a"",1],[""a"",2]]";
      Target : Integer_Maps.Value;
      Error  : Errors.Error_Info;
   begin
      Element_Calls := 0;
      Decode_JSON (Input, Keep_First_Policy, Target, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Element_Calls = 1);
      Assert_Duplicate_Result (Target, 1);
   end;

   declare
      Input  : aliased constant String := "[[""a"",1],[""a"",2]]";
      Target : Integer_Maps.Value;
      Error  : Errors.Error_Info;
   begin
      Decode_JSON (Input, Keep_Last_Policy, Target, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      Assert_Duplicate_Result (Target, 2);
   end;

   declare
      Input  : aliased constant Bytes :=
        [16#A2#, 16#61#, Character'Pos ('a'), 1,
         16#61#, Character'Pos ('a'), 2];
      Target : Integer_Maps.Value;
      Error  : Errors.Error_Info;
   begin
      Decode_CBOR (Input, Reject_Policy, Target, Error);
      pragma Assert (Error.Code = Errors.Duplicate_Key);
   end;

   declare
      Input  : aliased constant Bytes :=
        [16#A2#, 16#61#, Character'Pos ('a'), 1,
         16#61#, Character'Pos ('a'), 2];
      Target : Integer_Maps.Value;
      Error  : Errors.Error_Info;
   begin
      Element_Calls := 0;
      Decode_CBOR (Input, Keep_First_Policy, Target, Error);
      pragma Assert (Error.Code = Errors.No_Error and then Element_Calls = 1);
      Assert_Duplicate_Result (Target, 1);
   end;

   declare
      Input  : aliased constant Bytes :=
        [16#A2#, 16#61#, Character'Pos ('a'), 1,
         16#61#, Character'Pos ('a'), 2];
      Target : Integer_Maps.Value;
      Error  : Errors.Error_Info;
   begin
      Decode_CBOR (Input, Keep_Last_Policy, Target, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      Assert_Duplicate_Result (Target, 2);
   end;

   --  Known and unknown-length capacity limits fail before the next key callback.
   declare
      Policy : Policies.Decode_Policy := Reject_Policy;
      Input  : aliased constant Bytes :=
        [16#A2#, 16#61#, Character'Pos ('a'), 1,
         16#61#, Character'Pos ('b'), 2];
      From   : CBOR_Readers.Reader (Input'Access);
      Target : Integer_Maps.Value;
      Error  : Errors.Error_Info;
   begin
      Policy.Limits.Maximum_Container_Items := 1;
      Seed (Target);
      Key_Calls := 0;
      From.Initialize (Policy);
      Integer_Maps.Deserialize_Candidate (From, Target, Policy, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
      pragma Assert (Key_Calls = 0);
      pragma Assert (Target.Length = 1 and then Target.Element (Key ("z")) = 9);
      From.Abort_Document (Error);
   end;

   declare
      Policy : Policies.Decode_Policy := Reject_Policy;
      Input  : aliased Bytes :=
        [16#BF#, 16#61#, Character'Pos ('a'), 1,
         16#61#, Character'Pos ('b'), 2, 16#FF#];
      From   : CBOR_Readers.Reader (Input'Access);
      Target : Integer_Maps.Value;
      Error  : Errors.Error_Info;
   begin
      Policy.Limits.Maximum_Container_Items := 1;
      Key_Calls := 0;
      From.Initialize (Policy);
      Integer_Maps.Deserialize_Candidate (From, Target, Policy, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
      pragma Assert (Key_Calls = 1);
      From.Abort_Document (Error);
   end;

   declare
      Policy : Policies.Decode_Policy := Reject_Policy;
      Input  : aliased constant String := "[[""a"",1],[""b"",2]]";
      From   : JSON_Readers.Reader (Input'Access);
      Target : Integer_Maps.Value;
      Error  : Errors.Error_Info;
   begin
      Policy.Limits.Maximum_Container_Items := 1;
      Key_Calls := 0;
      From.Initialize (Policy);
      Integer_Maps.Deserialize_Candidate (From, Target, Policy, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
      pragma Assert (Key_Calls = 1);
      From.Abort_Document (Error);
   end;

   --  Root failures preserve the published map and roll back the candidate.
   declare
      Input  : aliased constant String := "[[""a"",1],[""a"",2]]";
      From   : JSON_Readers.Reader (Input'Access);
      Target : Map_Builder;
      Error  : Errors.Error_Info;
   begin
      Seed (Target.Published);
      From.Initialize (Reject_Policy);
      Reject_Root.Deserialize (From, Target, Error);
      pragma Assert (Error.Code = Errors.Duplicate_Key);
      pragma Assert (Error.Path_Length = 1);
      pragma Assert (Error.Path (1).Kind = Errors.Index_Element);
      pragma Assert (Error.Path (1).Index = 1);
      pragma Assert (Target.Published.Element (Key ("z")) = 9);
      pragma Assert (Target.Commits = 0 and then Target.Rollbacks = 1);
      pragma Assert (not From.Is_Complete);
   end;

   declare
      Input  : aliased constant String := "[[""a"",1],[""a"",2]]";
      From   : JSON_Readers.Reader (Input'Access);
      Target : Map_Builder;
      Error  : Errors.Error_Info;
   begin
      From.Initialize (Keep_First_Policy);
      Keep_First_Root.Deserialize (From, Target, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Target.Commits = 1 and then Target.Rollbacks = 0);
      Assert_Duplicate_Result (Target.Published, 1);
      pragma Assert (From.Is_Complete);
   end;

   declare
      Input  : aliased constant Bytes :=
        [16#A2#, 16#61#, Character'Pos ('a'), 1,
         16#61#, Character'Pos ('a'), 2];
      From   : CBOR_Readers.Reader (Input'Access);
      Target : Map_Builder;
      Error  : Errors.Error_Info;
   begin
      From.Initialize (Keep_Last_Policy);
      Keep_Last_Root.Deserialize (From, Target, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Target.Commits = 1 and then Target.Rollbacks = 0);
      Assert_Duplicate_Result (Target.Published, 2);
      pragma Assert (From.Is_Complete);
   end;

   declare
      Input  : aliased constant String := "[[""a"",1],[""b"",2]]";
      From   : JSON_Readers.Reader (Input'Access);
      Target : Map_Builder;
      Error  : Errors.Error_Info;
   begin
      Seed (Target.Published);
      Key_Failure_Mode := 1;
      From.Initialize (Reject_Policy);
      Reject_Root.Deserialize (From, Target, Error);
      Key_Failure_Mode := 0;
      pragma Assert (Error.Code = Errors.Application_Error);
      pragma Assert (Error.Path_Length = 1);
      pragma Assert (Error.Path (1).Index = 1);
      pragma Assert (Target.Published.Element (Key ("z")) = 9);
      pragma Assert (Target.Commits = 0 and then Target.Rollbacks = 1);
   end;

   declare
      Input  : aliased constant Bytes :=
        [16#A2#, 16#61#, Character'Pos ('a'), 1,
         16#61#, Character'Pos ('b'), 2];
      From   : CBOR_Readers.Reader (Input'Access);
      Target : Map_Builder;
      Error  : Errors.Error_Info;
      Raised : Boolean := False;
   begin
      Seed (Target.Published);
      Key_Failure_Mode := 2;
      From.Initialize (Reject_Policy);
      begin
         Reject_Root.Deserialize (From, Target, Error);
      exception
         when Occurrence : Program_Error =>
            Raised := Ada.Exceptions.Exception_Message (Occurrence) =
              "injected map key failure";
      end;
      Key_Failure_Mode := 0;
      pragma Assert (Raised and then Error.Code = Errors.No_Error);
      pragma Assert (Target.Published.Element (Key ("z")) = 9);
      pragma Assert (Target.Commits = 0 and then Target.Rollbacks = 1);
   end;

   declare
      Input  : aliased constant String := "[[""a"",1],[""b"",2]]";
      From   : JSON_Readers.Reader (Input'Access);
      Target : Map_Builder;
      Error  : Errors.Error_Info;
   begin
      Seed (Target.Published);
      Element_Failure_Mode := 1;
      From.Initialize (Reject_Policy);
      Reject_Root.Deserialize (From, Target, Error);
      Element_Failure_Mode := 0;
      pragma Assert (Error.Code = Errors.Application_Error);
      pragma Assert (Error.Path_Length = 1);
      pragma Assert (Error.Path (1).Index = 1);
      pragma Assert (Target.Published.Element (Key ("z")) = 9);
      pragma Assert (Target.Commits = 0 and then Target.Rollbacks = 1);
   end;

   declare
      Input  : aliased constant Bytes :=
        [16#A2#, 16#61#, Character'Pos ('a'), 1,
         16#61#, Character'Pos ('b'), 2];
      From   : CBOR_Readers.Reader (Input'Access);
      Target : Map_Builder;
      Error  : Errors.Error_Info;
      Raised : Boolean := False;
   begin
      Seed (Target.Published);
      Element_Failure_Mode := 2;
      From.Initialize (Reject_Policy);
      begin
         Reject_Root.Deserialize (From, Target, Error);
      exception
         when Occurrence : Program_Error =>
            Raised := Ada.Exceptions.Exception_Message (Occurrence) =
              "injected map element failure";
      end;
      Element_Failure_Mode := 0;
      pragma Assert (Raised and then Error.Code = Errors.No_Error);
      pragma Assert (Target.Published.Element (Key ("z")) = 9);
      pragma Assert (Target.Commits = 0 and then Target.Rollbacks = 1);
      pragma Assert (not From.Is_Complete);
   end;

   declare
      Input  : aliased constant String := "[[""a"",1],[""b""]]";
      From   : JSON_Readers.Reader (Input'Access);
      Target : Map_Builder;
      Error  : Errors.Error_Info;
   begin
      Seed (Target.Published);
      From.Initialize (Reject_Policy);
      Reject_Root.Deserialize (From, Target, Error);
      pragma Assert (Error.Code /= Errors.No_Error);
      pragma Assert (Target.Published.Element (Key ("z")) = 9);
      pragma Assert (Target.Commits = 0 and then Target.Rollbacks = 1);
   end;

   --  Conservative key metadata rejects JSON before input or callbacks.
   declare
      Input  : aliased constant String := "[[""a"",1]]";
      From   : Restricted_JSON_Reader (Input'Access);
      Target : Conservative_Maps.Value;
      Error  : Errors.Error_Info;
   begin
      Key_Calls := 0;
      From.Initialize (Reject_Policy);
      Conservative_Maps.Deserialize_Candidate
        (From, Target, Reject_Policy, Error);
      pragma Assert (Error.Code = Errors.Unsupported_Value);
      pragma Assert (From.Input_Offset = 0 and then Key_Calls = 0);
   end;

   declare
      Item    : Conservative_Maps.Value;
      Counter : Counting.Counter;
      Profile : Data_Model.Format_Capabilities := Data_Model.All_Capabilities;
      Error   : Errors.Error_Info;
   begin
      Item.Insert (Key ("a"), 1);
      Profile.Arbitrary_Map_Keys := False;
      Counter.Reset (Profile, Serialization_Limits);
      Serialized_Key_Calls := 0;
      Conservative_Maps.Serialize_Value (Item, Counter, Error);
      pragma Assert (Error.Code = Errors.Unsupported_Value);
      pragma Assert (Serialized_Key_Calls = 0);
   end;

   declare
      Input  : aliased constant Bytes :=
        [16#A1#, 16#61#, Character'Pos ('a'), 1];
      From   : CBOR_Readers.Reader (Input'Access);
      Target : Conservative_Maps.Value;
      Error  : Errors.Error_Info;
   begin
      From.Initialize (Reject_Policy);
      Conservative_Maps.Deserialize_Candidate
        (From, Target, Reject_Policy, Error);
      From.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error and then Target.Length = 1);
   end;

   --  Distinct comparator-equivalent controlled keys retain the first key;
   --  controlled keys and values clean up after replacement and exceptions.
   declare
      Baseline_Keys     : constant Integer := Live_Keys;
      Baseline_Elements : constant Integer := Live_Elements;
   begin
      declare
         Input  : aliased constant Bytes := [16#A2#, 1, 10, 16#20#, 20];
         From   : CBOR_Readers.Reader (Input'Access);
         Target : Controlled_Maps.Value;
         Error  : Errors.Error_Info;
      begin
         From.Initialize (Keep_Last_Policy);
         Controlled_Maps.Deserialize_Candidate
           (From, Target, Keep_Last_Policy, Error);
         From.Finish_Document (Error);
         pragma Assert (Error.Code = Errors.No_Error);
         pragma Assert (Target.Length = 1);
         pragma Assert (Controlled_Maps.Maps.Key (Target.First).Raw = 1);
         pragma Assert (Controlled_Maps.Maps.Element (Target.First).Value = 20);
      end;
      pragma Assert (Live_Keys = Baseline_Keys);
      pragma Assert (Live_Elements = Baseline_Elements);

      declare
         Initial_Input : aliased constant Bytes := [16#A1#, 1, 10];
         Failure_Input : aliased constant Bytes :=
           [16#A2#, 1, 10, 2, 20];
         Initial_From  : CBOR_Readers.Reader (Initial_Input'Access);
         Failure_From  : CBOR_Readers.Reader (Failure_Input'Access);
         Target        : Controlled_Maps.Value;
         Error         : Errors.Error_Info;
      begin
         Initial_From.Initialize (Reject_Policy);
         Controlled_Maps.Deserialize_Candidate
           (Initial_From, Target, Reject_Policy, Error);
         Initial_From.Finish_Document (Error);
         pragma Assert (Error.Code = Errors.No_Error);
         pragma Assert (Target.Length = 1);

         Controlled_Failure_Mode := 1;
         Failure_From.Initialize (Reject_Policy);
         Controlled_Maps.Deserialize_Candidate
           (Failure_From, Target, Reject_Policy, Error);
         Controlled_Failure_Mode := 0;
         pragma Assert (Error.Code = Errors.Application_Error);
         pragma Assert (Target.Length = 1);
         pragma Assert (Controlled_Maps.Maps.Key (Target.First).Raw = 1);
         pragma Assert (Controlled_Maps.Maps.Element (Target.First).Value = 10);
         Failure_From.Abort_Document (Error);
      end;
      pragma Assert (Live_Keys = Baseline_Keys);
      pragma Assert (Live_Elements = Baseline_Elements);

      declare
         Input  : aliased constant Bytes := [16#A2#, 1, 10, 2, 20];
         From   : CBOR_Readers.Reader (Input'Access);
         Target : Controlled_Maps.Value;
         Error  : Errors.Error_Info;
         Raised : Boolean := False;
      begin
         Controlled_Failure_Mode := 2;
         From.Initialize (Reject_Policy);
         begin
            Controlled_Maps.Deserialize_Candidate
              (From, Target, Reject_Policy, Error);
         exception
            when Occurrence : Program_Error =>
               Raised := Ada.Exceptions.Exception_Message (Occurrence) =
                 "injected controlled map failure";
         end;
         Controlled_Failure_Mode := 0;
         pragma Assert (Raised);
         pragma Assert (Target.Is_Empty);
      end;
      pragma Assert (Live_Keys = Baseline_Keys);
      pragma Assert (Live_Elements = Baseline_Elements);
   end;
end Allocating_Map_Tests;
