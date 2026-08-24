with Ada.Streams;
with Flyology_Serde.Adapters.Booleans;
with Flyology_Serde.Adapters.Bytes;
with Flyology_Serde.Adapters.Constrained_Arrays;
with Flyology_Serde.Adapters.Arrays;
with Flyology_Serde.Adapters.Float_64_Values;
with Flyology_Serde.Adapters.Maps;
with Flyology_Serde.Adapters.Nulls;
with Flyology_Serde.Adapters.Signed_Integers;
with Flyology_Serde.Adapters.Text;
with Flyology_Serde.Data_Model;
with Flyology_Serde.Deserialization;
with Flyology_Serde.Deserializers.CBOR;
with Flyology_Serde.Deserializers.JSON;
with Flyology_Serde.Deserialization_Adapters;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;
with Flyology_Serde.Serialization_Adapters;
with Flyology_Serde.Serialization;
with Flyology_Serde.Serializers.CBOR;
with Flyology_Serde.Serializers.Counting;
with Flyology_Serde.Serializers.JSON;
with Interfaces;

procedure Adapter_Conformance_Tests is
   package Booleans renames Flyology_Serde.Adapters.Booleans;
   package Bytes_Adapter renames Flyology_Serde.Adapters.Bytes;
   package Float_Values renames Flyology_Serde.Adapters.Float_64_Values;
   package Data_Model renames Flyology_Serde.Data_Model;
   package Errors renames Flyology_Serde.Errors;
   package Policies renames Flyology_Serde.Policies;
   package CBOR_Readers renames Flyology_Serde.Deserializers.CBOR;
   package CBOR_Writers renames Flyology_Serde.Serializers.CBOR;
   package Counting renames Flyology_Serde.Serializers.Counting;
   package JSON_Readers renames Flyology_Serde.Deserializers.JSON;
   package JSON_Writers renames Flyology_Serde.Serializers.JSON;

   use type Ada.Streams.Stream_Element_Array;
   use type Data_Model.Float_64_Category;
   use type Errors.Error_Code;
   use type Errors.Path_Element_Kind;
   use type Flyology_Serde.Serialization.Serializer_State;
   use type Interfaces.IEEE_Float_64;

   Serialization_Limits : constant
     Flyology_Serde.Serialization.Serialization_Limits :=
       (Maximum_Nesting_Depth   => 16,
        Maximum_Container_Items => 32,
        Maximum_Text_Length     => 128,
        Maximum_Byte_Length     => 128,
        Maximum_Logical_Events  => 256);

   subtype Byte_Array is Ada.Streams.Stream_Element_Array;

   type Null_Record is null record;
   type Null_Builder is record
      Constructed : Boolean := False;
   end record;
   Fail_Null_Construct : Boolean := False;

   procedure Construct_Null
     (Target : in out Null_Builder; Error : in out Errors.Error_Info)
   is
   begin
      if Fail_Null_Construct then
         Errors.Fail (Error, Errors.Application_Error);
      else
         Target.Constructed := True;
      end if;
   end Construct_Null;

   package Null_Records is new Flyology_Serde.Adapters.Nulls
     (Source_Type   => Null_Record,
      Builder_Type  => Null_Builder,
      Construct_Null => Construct_Null);

   package Null_Root is new Flyology_Serde.Serialization_Adapters
     (Source_Type      => Null_Record,
      Limits           => Serialization_Limits,
      Serialize_Value => Null_Records.Serialize_Value);

   type Array_Index is range 5 .. 7;
   type Integer_Array is array (Array_Index range <>) of Integer;
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

   package Arrays is new Flyology_Serde.Adapters.Constrained_Arrays
     (Index_Type          => Array_Index,
      Element_Type        => Integer,
      Array_Type          => Integer_Array,
      Serialize_Element   => Integers.Serialize_Value,
      Deserialize_Element => Deserialize_Integer);

   type Sequence_Items is array (Natural range 0 .. 2) of Integer;
   type Sequence_Builder is record
      Items          : Sequence_Items := [others => 0];
      Count          : Natural := 0;
      Declared_Known : Boolean := False;
   end record;

   procedure Begin_Sequence
     (Target : in out Sequence_Builder;
      Length : Data_Model.Length_Information;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info)
   is
      pragma Unreferenced (Policy, Error);
   begin
      Target.Count := 0;
      Target.Declared_Known := Length.Known;
   end Begin_Sequence;

   procedure Append_Sequence_Element
     (From     : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target   : in out Sequence_Builder;
      Position : Natural;
      Policy   : Policies.Decode_Policy;
      Error    : in out Errors.Error_Info)
   is
      pragma Unreferenced (Policy);
   begin
      Integers.Deserialize_Candidate (From, Target.Items (Position), Error);
      if Error.Code = Errors.No_Error then
         Target.Count := Position + 1;
      end if;
   end Append_Sequence_Element;

   procedure Finish_Sequence
     (Target : in out Sequence_Builder; Error : in out Errors.Error_Info)
   is
      pragma Unreferenced (Target, Error);
   begin
      null;
   end Finish_Sequence;

   package Growing_Arrays is new Flyology_Serde.Adapters.Arrays
     (Index_Type        => Array_Index,
      Element_Type      => Integer,
      Array_Type        => Integer_Array,
      Builder_Type      => Sequence_Builder,
      Maximum_Elements  => 3,
      Serialize_Element => Integers.Serialize_Value,
      Begin_Candidate   => Begin_Sequence,
      Append_Element    => Append_Sequence_Element,
      Finish_Candidate  => Finish_Sequence);

   package Array_Root is new Flyology_Serde.Serialization_Adapters
     (Source_Type      => Integer_Array,
      Limits           => Serialization_Limits,
      Serialize_Value => Arrays.Serialize_Value);

   subtype Fixed_Integer_Array is Integer_Array (5 .. 7);
   type Array_Builder is limited record
      Published : Fixed_Integer_Array := [others => 0];
      Candidate : Fixed_Integer_Array := [others => 0];
      Rollbacks : Natural := 0;
   end record;

   procedure Begin_Array
     (Target : in out Array_Builder; Error : in out Errors.Error_Info)
   is
      pragma Unreferenced (Error);
   begin
      Target.Candidate := [others => 0];
   end Begin_Array;

   procedure Read_Array
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out Array_Builder;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info) is
   begin
      Arrays.Deserialize_Candidate (From, Target.Candidate, Policy, Error);
   end Read_Array;

   procedure Commit_Array
     (Target : in out Array_Builder; Error : in out Errors.Error_Info)
   is
      pragma Unreferenced (Error);
   begin
      Target.Published := Target.Candidate;
   end Commit_Array;

   procedure Rollback_Array (Target : in out Array_Builder) is
   begin
      Target.Rollbacks := Target.Rollbacks + 1;
   end Rollback_Array;

   type Pair is record
      Key   : Character := ' ';
      Value : Integer := 0;
   end record;
   type Pair_Array is array (Positive range <>) of Pair;

   type Map_Builder is record
      Items : Pair_Array (1 .. 3);
      Count : Natural := 0;
   end record;

   function Entry_Count (Item : Pair_Array) return Natural
   is (Item'Length);

   procedure Serialize_Entry
     (Item     : Pair_Array;
      Position : Natural;
      Into     : in out Flyology_Serde.Serialization.Serializer'Class;
      Error    : in out Errors.Error_Info)
   is
      Index : constant Positive := Item'First + Position;
   begin
      Into.Put_Text (String'[1 => Item (Index).Key], Error);
      Integers.Serialize_Value (Item (Index).Value, Into, Error);
   end Serialize_Entry;

   procedure Begin_Map
     (Target : in out Map_Builder;
      Length : Data_Model.Length_Information;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info)
   is
      pragma Unreferenced (Policy);
   begin
      Target.Count := 0;
      if Length.Known and then Length.Length > Target.Items'Length then
         Errors.Fail (Error, Errors.Capacity_Exceeded);
      end if;
   end Begin_Map;

   procedure Deserialize_Entry
     (From     : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target   : in out Map_Builder;
      Position : Natural;
      Policy   : Policies.Decode_Policy;
      Error    : in out Errors.Error_Info)
   is
      pragma Unreferenced (Policy);
      Text   : String (1 .. 1);
      Length : Natural := 0;
      Value  : Integer := 0;
   begin
      if Position >= Target.Items'Length then
         Errors.Fail (Error, Errors.Capacity_Exceeded);
         return;
      end if;
      From.Read_Text (Text, Length, Error);
      if Error.Code = Errors.No_Error and then Length /= 1 then
         Errors.Fail (Error, Errors.Invalid_Value);
      end if;
      if Error.Code = Errors.No_Error and then Target.Count > 0 then
         for Index in 1 .. Target.Count loop
            if Target.Items (Index).Key = Text (1) then
               Errors.Fail (Error, Errors.Duplicate_Key);
               exit;
            end if;
         end loop;
      end if;
      Integers.Deserialize_Candidate (From, Value, Error);
      if Error.Code = Errors.No_Error then
         Target.Items (Position + 1) := (Text (1), Value);
         Target.Count := Position + 1;
      end if;
   end Deserialize_Entry;

   procedure Finish_Map
     (Target : in out Map_Builder; Error : in out Errors.Error_Info)
   is
      pragma Unreferenced (Target, Error);
   begin
      null;
   end Finish_Map;

   package Maps is new Flyology_Serde.Adapters.Maps
     (Source_Type       => Pair_Array,
      Builder_Type      => Map_Builder,
      Maximum_Entries   => 3,
      Keys_Use_Restricted_Kinds => True,
      Entry_Count       => Entry_Count,
      Serialize_Entry   => Serialize_Entry,
      Begin_Candidate   => Begin_Map,
      Deserialize_Entry => Deserialize_Entry,
      Finish_Candidate  => Finish_Map);

   package Conservatively_Nontext_Maps is new Flyology_Serde.Adapters.Maps
     (Source_Type       => Pair_Array,
      Builder_Type      => Map_Builder,
      Maximum_Entries   => 3,
      Keys_Use_Restricted_Kinds => False,
      Entry_Count       => Entry_Count,
      Serialize_Entry   => Serialize_Entry,
      Begin_Candidate   => Begin_Map,
      Deserialize_Entry => Deserialize_Entry,
      Finish_Candidate  => Finish_Map);

   package Map_Root is new Flyology_Serde.Serialization_Adapters
     (Source_Type      => Pair_Array,
      Limits           => Serialization_Limits,
      Serialize_Value => Maps.Serialize_Value);

   package Nontext_Map_Root is new Flyology_Serde.Serialization_Adapters
     (Source_Type      => Pair_Array,
      Limits           => Serialization_Limits,
      Serialize_Value => Conservatively_Nontext_Maps.Serialize_Value);

   type Map_Root_Builder is limited record
      Published : Map_Builder;
      Candidate : Map_Builder;
      Rollbacks : Natural := 0;
   end record;

   procedure Begin_Map_Root
     (Target : in out Map_Root_Builder; Error : in out Errors.Error_Info)
   is
      pragma Unreferenced (Error);
   begin
      Target.Candidate.Count := 0;
   end Begin_Map_Root;

   procedure Read_Map_Root
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out Map_Root_Builder;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info) is
   begin
      Maps.Deserialize_Candidate (From, Target.Candidate, Policy, Error);
   end Read_Map_Root;

   procedure Commit_Map_Root
     (Target : in out Map_Root_Builder; Error : in out Errors.Error_Info)
   is
      pragma Unreferenced (Error);
   begin
      Target.Published := Target.Candidate;
   end Commit_Map_Root;

   procedure Rollback_Map_Root (Target : in out Map_Root_Builder) is
   begin
      Target.Rollbacks := Target.Rollbacks + 1;
   end Rollback_Map_Root;

   type Float_Array is array (Positive range <>) of Data_Model.Float_64_Value;

   procedure Serialize_Floats
     (Item  : Float_Array;
      Into  : in out Flyology_Serde.Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
   begin
      Into.Begin_Sequence (Data_Model.Known_Length (Item'Length), Error);
      for Value of Item loop
         Float_Values.Serialize_Value (Value, Into, Error);
         exit when Error.Code /= Errors.No_Error;
      end loop;
      if Error.Code = Errors.No_Error then
         Into.End_Sequence (Error);
      end if;
   end Serialize_Floats;

   package Float_Root is new Flyology_Serde.Serialization_Adapters
     (Source_Type      => Float_Array,
      Limits           => Serialization_Limits,
      Serialize_Value => Serialize_Floats);

   package Float_Value_Root is new Flyology_Serde.Serialization_Adapters
     (Source_Type      => Data_Model.Float_64_Value,
      Limits           => Serialization_Limits,
      Serialize_Value => Float_Values.Serialize_Value);

   Tiny_Limits : constant Flyology_Serde.Serialization.Serialization_Limits :=
     (Maximum_Nesting_Depth   => 1,
      Maximum_Container_Items => 1,
      Maximum_Text_Length     => 2,
      Maximum_Byte_Length     => 2,
      Maximum_Logical_Events  => 2);

   package Tiny_Float_Root is new Flyology_Serde.Serialization_Adapters
     (Source_Type      => Float_Array,
      Limits           => Tiny_Limits,
      Serialize_Value => Serialize_Floats);

   package Tiny_Text_Root is new Flyology_Serde.Serialization_Adapters
     (Source_Type      => String,
      Limits           => Tiny_Limits,
      Serialize_Value => Flyology_Serde.Adapters.Text.Serialize_Value);

   Default_Policy : constant Policies.Decode_Policy := (others => <>);

   package Array_Decode_Root is new Flyology_Serde.Deserialization_Adapters
     (Builder_Type       => Array_Builder,
      Policy             => Default_Policy,
      Begin_Candidate    => Begin_Array,
      Deserialize_Value  => Read_Array,
      Commit_Candidate   => Commit_Array,
      Rollback_Candidate => Rollback_Array);

   package Map_Decode_Root is new Flyology_Serde.Deserialization_Adapters
     (Builder_Type       => Map_Root_Builder,
      Policy             => Default_Policy,
      Begin_Candidate    => Begin_Map_Root,
      Deserialize_Value  => Read_Map_Root,
      Commit_Candidate   => Commit_Map_Root,
      Rollback_Candidate => Rollback_Map_Root);

   Injected_Failure : exception;
   type Injection_Mode is
     (No_Injection,
      Sink_Status,
      Sink_Exception,
      Finish_Status,
      Finish_Exception);

   type Injected_Counter is limited new Counting.Counter with record
      Mode : Injection_Mode := No_Injection;
   end record;

   overriding
   procedure Put_Null
     (Self : in out Injected_Counter; Error : in out Errors.Error_Info);

   overriding
   procedure Finish_Document
     (Self : in out Injected_Counter; Error : in out Errors.Error_Info);

   overriding
   procedure Put_Null
     (Self : in out Injected_Counter; Error : in out Errors.Error_Info) is
   begin
      case Self.Mode is
         when Sink_Status =>
            Errors.Fail (Error, Errors.Application_Error);
         when Sink_Exception =>
            raise Injected_Failure;
         when others =>
            Counting.Put_Null (Counting.Counter (Self), Error);
      end case;
   end Put_Null;

   overriding
   procedure Finish_Document
     (Self : in out Injected_Counter; Error : in out Errors.Error_Info) is
   begin
      case Self.Mode is
         when Finish_Status =>
            Errors.Fail (Error, Errors.Application_Error);
         when Finish_Exception =>
            raise Injected_Failure;
         when others =>
            Counting.Finish_Document (Counting.Counter (Self), Error);
      end case;
   end Finish_Document;

   procedure Reset_Injected
     (Self : in out Injected_Counter; Mode : Injection_Mode) is
   begin
      Counting.Reset
        (Counting.Counter (Self), Data_Model.All_Capabilities, Serialization_Limits);
      Self.Mode := Mode;
   end Reset_Injected;

   Traversal_Calls : Natural := 0;

   procedure Raising_Traversal
     (Item  : Null_Record;
      Into  : in out Flyology_Serde.Serialization.Serializer'Class;
      Error : in out Errors.Error_Info)
   is
      pragma Unreferenced (Item, Into, Error);
   begin
      Traversal_Calls := Traversal_Calls + 1;
      raise Injected_Failure;
   end Raising_Traversal;

   package Raising_Root is new Flyology_Serde.Serialization_Adapters
     (Source_Type      => Null_Record,
      Limits           => Serialization_Limits,
      Serialize_Value => Raising_Traversal);

   Status_Traversal_Calls : Natural := 0;

   procedure Status_Traversal
     (Item  : Null_Record;
      Into  : in out Flyology_Serde.Serialization.Serializer'Class;
      Error : in out Errors.Error_Info)
   is
      pragma Unreferenced (Item, Into);
   begin
      Status_Traversal_Calls := Status_Traversal_Calls + 1;
      Errors.Fail (Error, Errors.Application_Error);
   end Status_Traversal;

   package Status_Root is new Flyology_Serde.Serialization_Adapters
     (Source_Type      => Null_Record,
      Limits           => Serialization_Limits,
      Serialize_Value => Status_Traversal);
begin
   declare
      Writer : JSON_Writers.Bounded_Writer (8);
      Buffer : String (1 .. 8);
      Length : Natural := 0;
      Error  : Errors.Error_Info;
   begin
      Null_Root.Serialize ((null record), Writer, Error);
      Writer.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Buffer (1 .. Length) = "null");
      Errors.Reset (Error);
      Null_Root.Serialize ((null record), Writer, Error);
      pragma Assert (Error.Code = Errors.Invalid_State);
      pragma Assert (Writer.State = Flyology_Serde.Serialization.Finished);
      Errors.Reset (Error);
      Writer.Copy_Output (Buffer, Length, Error);
      pragma Assert (Buffer (1 .. Length) = "null");
   end;

   declare
      Writer : JSON_Writers.Bounded_Writer (16);
      Error  : Errors.Error_Info;
   begin
      Writer.Begin_Sequence (Data_Model.Unknown_Length, Error);
      Null_Root.Serialize ((null record), Writer, Error);
      pragma Assert (Error.Code = Errors.Invalid_State);
      pragma Assert (Writer.State = Flyology_Serde.Serialization.Poisoned);
      Errors.Reset (Error);
      Null_Root.Serialize ((null record), Writer, Error);
      pragma Assert (Error.Code = Errors.Invalid_State);
      pragma Assert (Writer.State = Flyology_Serde.Serialization.Poisoned);
   end;

   declare
      Input   : aliased constant String := "false";
      Reader  : JSON_Readers.Reader (Input'Access);
      Target  : Boolean := True;
      Error   : Errors.Error_Info;
   begin
      Reader.Initialize (Default_Policy);
      Booleans.Deserialize_Candidate (Reader, Target, Error);
      Reader.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error and then not Target);
   end;

   declare
      Input  : aliased constant String := "1";
      Reader : JSON_Readers.Reader (Input'Access);
      Target : Boolean := True;
      Error  : Errors.Error_Info;
   begin
      Reader.Initialize (Default_Policy);
      Booleans.Deserialize_Candidate (Reader, Target, Error);
      pragma Assert (Error.Code = Errors.Unexpected_Kind and then Target);
   end;

   declare
      Input  : aliased constant String := "null";
      Reader : JSON_Readers.Reader (Input'Access);
      Target : Null_Builder;
      Error  : Errors.Error_Info;
   begin
      Reader.Initialize (Default_Policy);
      Null_Records.Deserialize_Candidate (Reader, Target, Error);
      Reader.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error and then Target.Constructed);
      Fail_Null_Construct := True;
      Reader.Reset (Default_Policy);
      Target.Constructed := False;
      Errors.Reset (Error);
      Null_Records.Deserialize_Candidate (Reader, Target, Error);
      pragma Assert
        (Error.Code = Errors.Application_Error and then not Target.Constructed);
      Fail_Null_Construct := False;
   end;

   declare
      Input  : aliased constant Byte_Array := [16#43#, 1, 2, 3];
      Reader : CBOR_Readers.Reader (Input'Access);
      Target : Byte_Array (4 .. 6) := [others => 9];
      Error  : Errors.Error_Info;
   begin
      Reader.Initialize (Default_Policy);
      Bytes_Adapter.Deserialize_Exact (Reader, Target, Error);
      Reader.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Target = Byte_Array'[1, 2, 3]);
   end;

   declare
      Input  : aliased constant Byte_Array := [16#42#, 1, 2];
      Reader : CBOR_Readers.Reader (Input'Access);
      Target : Byte_Array (1 .. 3) := [others => 9];
      Error  : Errors.Error_Info;
   begin
      Reader.Initialize (Default_Policy);
      Bytes_Adapter.Deserialize_Exact (Reader, Target, Error);
      pragma Assert (Error.Code = Errors.Out_Of_Range);
      pragma Assert (Target = Byte_Array'[9, 9, 9]);
   end;

   declare
      Input  : aliased constant Byte_Array := [16#FB#, 16#80#, 0, 0, 0, 0, 0, 0, 0];
      Reader : CBOR_Readers.Reader (Input'Access);
      Target : Data_Model.Float_64_Value;
      Error  : Errors.Error_Info;
   begin
      Reader.Initialize (Default_Policy);
      Float_Values.Deserialize_Candidate (Reader, Target, Error);
      Reader.Finish_Document (Error);
      pragma Assert
        (Error.Code = Errors.No_Error and then Data_Model.Is_Negative_Zero (Target));
   end;

   declare
      Input  : aliased constant String := "[1,2,3]";
      Reader : JSON_Readers.Reader (Input'Access);
      Target : Array_Builder;
      Error  : Errors.Error_Info;
   begin
      Target.Published := [others => 9];
      Reader.Initialize (Default_Policy);
      Array_Decode_Root.Deserialize (Reader, Target, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert
        (Target.Published = Integer_Array'(5 => 1, 6 => 2, 7 => 3));
      pragma Assert (Target.Rollbacks = 0);
   end;

   declare
      Input  : aliased constant String := "[4,5]";
      Reader : JSON_Readers.Reader (Input'Access);
      Target : Sequence_Builder;
      Error  : Errors.Error_Info;
   begin
      Reader.Initialize (Default_Policy);
      Growing_Arrays.Deserialize_Candidate
        (Reader, Target, Default_Policy, Error);
      Reader.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert
        (not Target.Declared_Known
         and then Target.Count = 2
         and then Target.Items (0) = 4
         and then Target.Items (1) = 5);
   end;

   declare
      Input  : aliased constant Byte_Array := [16#82#, 4, 5];
      Reader : CBOR_Readers.Reader (Input'Access);
      Target : Sequence_Builder;
      Error  : Errors.Error_Info;
   begin
      Reader.Initialize (Default_Policy);
      Growing_Arrays.Deserialize_Candidate
        (Reader, Target, Default_Policy, Error);
      Reader.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Target.Declared_Known and then Target.Count = 2);
   end;

   declare
      Input  : aliased constant Byte_Array := [16#9F#, 4, 5, 16#FF#];
      Reader : CBOR_Readers.Reader (Input'Access);
      Target : Sequence_Builder;
      Error  : Errors.Error_Info;
   begin
      Reader.Initialize (Default_Policy);
      Growing_Arrays.Deserialize_Candidate
        (Reader, Target, Default_Policy, Error);
      Reader.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (not Target.Declared_Known and then Target.Count = 2);
   end;

   declare
      Input  : aliased constant String := "[1,2,3] false";
      Reader : JSON_Readers.Reader (Input'Access);
      Target : Array_Builder;
      Error  : Errors.Error_Info;
   begin
      Target.Published := [others => 9];
      Reader.Initialize (Default_Policy);
      Array_Decode_Root.Deserialize (Reader, Target, Error);
      pragma Assert (Error.Code = Errors.Syntax_Error);
      pragma Assert (Target.Published = Fixed_Integer_Array'[others => 9]);
      pragma Assert (Target.Rollbacks = 1);
   end;

   for Long_Input in Boolean loop
      declare
         Short_Source : aliased constant String := "[1,2]";
         Long_Source  : aliased constant String := "[1,2,3,4]";
         Reader : JSON_Readers.Reader
           ((if Long_Input then Long_Source'Access else Short_Source'Access));
         Target : Array_Builder;
         Error  : Errors.Error_Info;
      begin
         Target.Published := [others => 9];
         Reader.Initialize (Default_Policy);
         Array_Decode_Root.Deserialize (Reader, Target, Error);
         pragma Assert (Error.Code = Errors.Out_Of_Range);
         pragma Assert (Target.Published = Fixed_Integer_Array'[others => 9]);
         pragma Assert (Target.Rollbacks = 1);
      end;
   end loop;

   declare
      Writer : CBOR_Writers.Bounded_Writer (32);
      Buffer : Byte_Array (1 .. 32);
      Length : Natural := 0;
      Error  : Errors.Error_Info;
      Value  : constant Integer_Array (5 .. 7) := [5 => 1, 6 => 2, 7 => 3];
   begin
      Array_Root.Serialize (Value, Writer, Error);
      Writer.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert
        (Buffer (1 .. Ada.Streams.Stream_Element_Offset (Length))
         = Byte_Array'[16#83#, 1, 2, 3]);
   end;

   declare
      Writer : JSON_Writers.Bounded_Writer (32);
      Buffer : String (1 .. 32);
      Length : Natural := 0;
      Error  : Errors.Error_Info;
      Value  : constant Pair_Array := [('a', 1), ('b', 2)];
   begin
      Map_Root.Serialize (Value, Writer, Error);
      Writer.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Buffer (1 .. Length) = "[[""a"",1],[""b"",2]]");
   end;

   declare
      Profile : constant Data_Model.Format_Capabilities :=
        (Unknown_Container_Lengths => True,
         Byte_Values               => True,
         Nonfinite_Float_64        => True,
         Signed_Float_Zero         => True,
         Arbitrary_Map_Keys        => False,
         Lossless_Optionals        => True);
      Writer : Counting.Counter;
      Error  : Errors.Error_Info;
      Value  : constant Pair_Array := [('a', 1)];
   begin
      Counting.Reset (Writer, Profile, Serialization_Limits);
      Map_Root.Serialize (Value, Writer, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      Counting.Reset (Writer, Profile, Serialization_Limits);
      Nontext_Map_Root.Serialize (Value, Writer, Error);
      pragma Assert (Error.Code = Errors.Unsupported_Value);
      pragma Assert (Writer.Event_Count = 0);
   end;

   declare
      Input  : aliased constant Byte_Array :=
        [16#A2#, 16#61#, Character'Pos ('a'), 1,
         16#61#, Character'Pos ('b'), 2];
      Reader : CBOR_Readers.Reader (Input'Access);
      Target : Map_Root_Builder;
      Error  : Errors.Error_Info;
   begin
      Reader.Initialize (Default_Policy);
      Map_Decode_Root.Deserialize (Reader, Target, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert
        (Target.Published.Count = 2
         and then Target.Published.Items (1) = ('a', 1)
         and then Target.Published.Items (2) = ('b', 2));
   end;

   declare
      Input  : aliased constant Byte_Array :=
        [16#A4#, 16#61#, Character'Pos ('a'), 1,
         16#61#, Character'Pos ('b'), 2,
         16#61#, Character'Pos ('c'), 3,
         16#61#, Character'Pos ('d'), 4];
      Reader : CBOR_Readers.Reader (Input'Access);
      Target : Map_Root_Builder;
      Error  : Errors.Error_Info;
   begin
      Target.Published.Count := 1;
      Target.Published.Items (1) := ('z', 9);
      Reader.Initialize (Default_Policy);
      Map_Decode_Root.Deserialize (Reader, Target, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
      pragma Assert
        (Target.Published.Count = 1
         and then Target.Published.Items (1) = ('z', 9)
         and then Target.Rollbacks = 1);
   end;

   declare
      Input  : aliased constant String := "[[""a"",1],[""a"",2]]";
      Reader : JSON_Readers.Reader (Input'Access);
      Target : Map_Root_Builder;
      Error  : Errors.Error_Info;
   begin
      Target.Published.Count := 1;
      Target.Published.Items (1) := ('z', 9);
      Reader.Initialize (Default_Policy);
      Map_Decode_Root.Deserialize (Reader, Target, Error);
      pragma Assert (Error.Code = Errors.Duplicate_Key);
      pragma Assert (Error.Path_Length = 1);
      pragma Assert (Error.Path (1).Kind = Errors.Index_Element);
      pragma Assert (Error.Path (1).Index = 1);
      pragma Assert
        (Target.Published.Count = 1
         and then Target.Published.Items (1) = ('z', 9)
         and then Target.Rollbacks = 1);
   end;

   declare
      Input  : aliased constant Byte_Array :=
        [16#BF#, 16#61#, Character'Pos ('a'), 1,
         16#61#, Character'Pos ('b'), 2,
         16#61#, Character'Pos ('c'), 3,
         16#61#, Character'Pos ('d'), 4, 16#FF#];
      Reader : CBOR_Readers.Reader (Input'Access);
      Target : Map_Root_Builder;
      Error  : Errors.Error_Info;
   begin
      Target.Published.Count := 1;
      Target.Published.Items (1) := ('z', 9);
      Reader.Initialize (Default_Policy);
      Map_Decode_Root.Deserialize (Reader, Target, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
      pragma Assert
        (Target.Published.Count = 1
         and then Target.Published.Items (1) = ('z', 9)
         and then Target.Rollbacks = 1);
   end;

   declare
      Input  : aliased constant Byte_Array :=
        [16#A2#, 16#61#, Character'Pos ('a'), 1,
         16#61#, Character'Pos ('a'), 2];
      Reader : CBOR_Readers.Reader (Input'Access);
      Target : Map_Root_Builder;
      Error  : Errors.Error_Info;
   begin
      Target.Published.Count := 1;
      Target.Published.Items (1) := ('z', 9);
      Reader.Initialize (Default_Policy);
      Map_Decode_Root.Deserialize (Reader, Target, Error);
      pragma Assert (Error.Code = Errors.Duplicate_Key);
      pragma Assert (Error.Path_Length = 1);
      pragma Assert (Error.Path (1).Kind = Errors.Index_Element);
      pragma Assert (Error.Path (1).Index = 1);
      pragma Assert
        (Target.Published.Count = 1
         and then Target.Published.Items (1) = ('z', 9)
         and then Target.Rollbacks = 1);
   end;

   declare
      Input  : aliased constant Byte_Array :=
        [16#A1#, 16#61#, Character'Pos ('a'), 16#F4#];
      Reader : CBOR_Readers.Reader (Input'Access);
      Target : Map_Root_Builder;
      Error  : Errors.Error_Info;
   begin
      Target.Published.Count := 1;
      Target.Published.Items (1) := ('z', 9);
      Reader.Initialize (Default_Policy);
      Map_Decode_Root.Deserialize (Reader, Target, Error);
      pragma Assert (Error.Code = Errors.Unexpected_Kind);
      pragma Assert
        (Target.Published.Count = 1
         and then Target.Published.Items (1) = ('z', 9)
         and then Target.Rollbacks = 1);
   end;

   declare
      Writer : CBOR_Writers.Bounded_Writer (16);
      Error  : Errors.Error_Info;
      Value  : constant Data_Model.Float_64_Value :=
        Data_Model.Positive_Infinity_Value;
   begin
      Float_Value_Root.Serialize (Value, Writer, Error);
      pragma Assert
        (Error.Code = Errors.No_Error
         and then Data_Model.Category (Value) = Data_Model.Positive_Infinity);
   end;

   --  Deterministic semantic rejection happens in the non-emitting pass.
   declare
      Writer : JSON_Writers.Bounded_Writer (64);
      Error  : Errors.Error_Info;
      Value  : constant Float_Array :=
        [Data_Model.Make_Finite (1.0), Data_Model.Positive_Infinity_Value];
   begin
      Float_Root.Serialize (Value, Writer, Error);
      pragma Assert (Error.Code = Errors.Unsupported_Value);
      pragma Assert (Writer.Written_Length = 0);
      pragma Assert (Writer.State = Flyology_Serde.Serialization.Poisoned);
      pragma Assert (not Writer.Is_Complete);
      Writer.Abort_Document;
      pragma Assert (Writer.State = Flyology_Serde.Serialization.Poisoned);
   end;

   --  An already-latched root call remains a strict no-op.
   declare
      Writer : JSON_Writers.Bounded_Writer (16);
      Error  : Errors.Error_Info;
   begin
      Errors.Fail (Error, Errors.Application_Error);
      Null_Root.Serialize ((null record), Writer, Error);
      pragma Assert (Writer.State = Flyology_Serde.Serialization.Ready);
      pragma Assert (Writer.Written_Length = 0);
   end;

   --  A prelatched root never invokes application traversal. A preflight
   --  exception remains primary, poisons the destination, and Reset restores
   --  reuse without exposing output.
   declare
      Writer : JSON_Writers.Bounded_Writer (16);
      Buffer : String (1 .. 16);
      Length : Natural := 0;
      Error  : Errors.Error_Info;
   begin
      Traversal_Calls := 0;
      Errors.Fail (Error, Errors.Application_Error);
      Raising_Root.Serialize ((null record), Writer, Error);
      pragma Assert (Traversal_Calls = 0);
      pragma Assert (Writer.State = Flyology_Serde.Serialization.Ready);

      Errors.Reset (Error);
      begin
         Raising_Root.Serialize ((null record), Writer, Error);
         pragma Assert (False);
      exception
         when Injected_Failure =>
            null;
      end;
      pragma Assert (Traversal_Calls = 1);
      pragma Assert (Writer.State = Flyology_Serde.Serialization.Poisoned);
      pragma Assert (not Writer.Is_Complete and then Writer.Written_Length = 0);

      Writer.Reset;
      Null_Root.Serialize ((null record), Writer, Error);
      Writer.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Buffer (1 .. Length) = "null");
   end;

   declare
      Writer : JSON_Writers.Bounded_Writer (16);
      Buffer : String (1 .. 16);
      Length : Natural := 0;
      Error  : Errors.Error_Info;
   begin
      Status_Traversal_Calls := 0;
      Status_Root.Serialize ((null record), Writer, Error);
      pragma Assert (Error.Code = Errors.Application_Error);
      pragma Assert (Status_Traversal_Calls = 1);
      pragma Assert (Writer.State = Flyology_Serde.Serialization.Poisoned);
      pragma Assert (not Writer.Is_Complete and then Writer.Written_Length = 0);

      Errors.Reset (Error);
      Writer.Reset;
      Null_Root.Serialize ((null record), Writer, Error);
      Writer.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Buffer (1 .. Length) = "null");
   end;

   --  Actual-sink and Finish failures preserve their original outcome and the
   --  root always aborts the serializer. Each poisoned fake remains reusable
   --  only after its explicit reset.
   for Mode in Sink_Status .. Finish_Exception loop
      declare
         Writer : Injected_Counter;
         Error  : Errors.Error_Info;
         Raised : Boolean := False;
      begin
         Reset_Injected (Writer, Mode);
         begin
            Null_Root.Serialize ((null record), Writer, Error);
         exception
            when Injected_Failure =>
               Raised := True;
         end;
         if Mode in Sink_Exception | Finish_Exception then
            pragma Assert (Raised and then Error.Code = Errors.No_Error);
         else
            pragma Assert
              (not Raised and then Error.Code = Errors.Application_Error);
         end if;
         pragma Assert (Writer.State = Flyology_Serde.Serialization.Poisoned);

         Errors.Reset (Error);
         Reset_Injected (Writer, No_Injection);
         Null_Root.Serialize ((null record), Writer, Error);
         pragma Assert (Error.Code = Errors.No_Error);
         pragma Assert (Writer.State = Flyology_Serde.Serialization.Finished);
      end;
   end loop;

   --  Operational capacity failure may occur after buffered bytes exist, but
   --  the unfinished prefix is never publishable.
   declare
      Writer : JSON_Writers.Bounded_Writer (2);
      Buffer : String (1 .. 2);
      Length : Natural := Natural'Last;
      Error  : Errors.Error_Info;
      Copy_Error : Errors.Error_Info;
      Value  : constant Float_Array := [1 => Data_Model.Make_Finite (1.0)];
   begin
      Float_Root.Serialize (Value, Writer, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
      pragma Assert (Writer.Written_Length > 0);
      Writer.Copy_Output (Buffer, Length, Copy_Error);
      pragma Assert (Copy_Error.Code = Errors.Invalid_State);
      pragma Assert (Length = 0);
   end;

   declare
      Writer : JSON_Writers.Bounded_Writer (64);
      Error  : Errors.Error_Info;
      Values : constant Float_Array :=
        [Data_Model.Make_Finite (1.0), Data_Model.Make_Finite (2.0)];
   begin
      Tiny_Float_Root.Serialize (Values, Writer, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
      pragma Assert (Writer.Written_Length = 0);
   end;

   declare
      Writer : JSON_Writers.Bounded_Writer (64);
      Error  : Errors.Error_Info;
   begin
      Tiny_Text_Root.Serialize ("abc", Writer, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
      pragma Assert (Writer.Written_Length = 0);
   end;

   --  Serialization limits are independent exact bounds. Each check first
   --  accepts its maximum, then rejects maximum plus one without real output.
   declare
      Limits : constant Flyology_Serde.Serialization.Serialization_Limits :=
        (Maximum_Nesting_Depth   => 1,
         Maximum_Container_Items => 1,
         Maximum_Text_Length     => 2,
         Maximum_Byte_Length     => 2,
         Maximum_Logical_Events  => 8);
      Writer : Counting.Counter;
      Error  : Errors.Error_Info;
   begin
      Counting.Reset (Writer, Data_Model.All_Capabilities, Limits);
      Writer.Begin_Sequence (Data_Model.Known_Length (1), Error);
      Writer.Put_Null (Error);
      Writer.End_Sequence (Error);
      Writer.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error);

      Counting.Reset (Writer, Data_Model.All_Capabilities, Limits);
      Writer.Begin_Sequence (Data_Model.Unknown_Length, Error);
      Writer.Begin_Optional (False, Error);
      pragma Assert (Error.Code = Errors.Depth_Exceeded);

      Errors.Reset (Error);
      Counting.Reset (Writer, Data_Model.All_Capabilities, Limits);
      Writer.Begin_Sequence (Data_Model.Known_Length (2), Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);

      Errors.Reset (Error);
      Counting.Reset (Writer, Data_Model.All_Capabilities, Limits);
      Writer.Begin_Sequence (Data_Model.Unknown_Length, Error);
      Writer.Put_Null (Error);
      Writer.Put_Null (Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);

      Errors.Reset (Error);
      Counting.Reset (Writer, Data_Model.All_Capabilities, Limits);
      Writer.Begin_Record ("ab", 1, Error);
      Writer.Put_Field ("cd", Error);
      Writer.Put_Null (Error);
      Writer.End_Record (Error);
      Writer.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error);

      Counting.Reset (Writer, Data_Model.All_Capabilities, Limits);
      Writer.Begin_Record ("ab", 2, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);

      Errors.Reset (Error);
      Counting.Reset (Writer, Data_Model.All_Capabilities, Limits);
      Writer.Begin_Variant ("ab", "cd", 2, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);

      Errors.Reset (Error);
      Counting.Reset (Writer, Data_Model.All_Capabilities, Limits);
      Writer.Begin_Record ("abc", 0, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);

      Errors.Reset (Error);
      Counting.Reset (Writer, Data_Model.All_Capabilities, Limits);
      Writer.Begin_Map (Data_Model.Unknown_Length, Error);
      Writer.Put_Text ("a", Error);
      Writer.Put_Null (Error);
      Writer.End_Map (Error);
      Writer.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error);

      Counting.Reset (Writer, Data_Model.All_Capabilities, Limits);
      Writer.Begin_Map (Data_Model.Unknown_Length, Error);
      Writer.Put_Text ("a", Error);
      Writer.Put_Null (Error);
      Writer.Put_Text ("b", Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);

      Errors.Reset (Error);
      Counting.Reset (Writer, Data_Model.All_Capabilities, Limits);
      Writer.Put_Text ("ab", Error);
      Writer.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error);

      Counting.Reset (Writer, Data_Model.All_Capabilities, Limits);
      Writer.Put_Text ("abc", Error);
      pragma Assert
        (Error.Code = Errors.Capacity_Exceeded and then Writer.Event_Count = 0);

      Errors.Reset (Error);
      Counting.Reset (Writer, Data_Model.All_Capabilities, Limits);
      Writer.Put_Bytes (Byte_Array'[1, 2], Error);
      Writer.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error);

      Counting.Reset (Writer, Data_Model.All_Capabilities, Limits);
      Writer.Put_Bytes (Byte_Array'[1, 2, 3], Error);
      pragma Assert
        (Error.Code = Errors.Capacity_Exceeded and then Writer.Event_Count = 0);
   end;

   declare
      One_Event : constant Flyology_Serde.Serialization.Serialization_Limits :=
        (Maximum_Nesting_Depth   => 1,
         Maximum_Container_Items => 1,
         Maximum_Text_Length     => 2,
         Maximum_Byte_Length     => 2,
         Maximum_Logical_Events  => 1);
      Zero_Events : constant Flyology_Serde.Serialization.Serialization_Limits :=
        (One_Event with delta Maximum_Logical_Events => 0);
      Writer : Counting.Counter;
      Error  : Errors.Error_Info;
   begin
      Counting.Reset (Writer, Data_Model.All_Capabilities, One_Event);
      Writer.Put_Null (Error);
      Writer.Finish_Document (Error);
      pragma Assert
        (Error.Code = Errors.No_Error and then Writer.Event_Count = 1);

      Counting.Reset (Writer, Data_Model.All_Capabilities, Zero_Events);
      Writer.Put_Null (Error);
      pragma Assert
        (Error.Code = Errors.Capacity_Exceeded and then Writer.Event_Count = 0);
   end;

   declare
      No_Signed_Zero : constant Data_Model.Format_Capabilities :=
        (Unknown_Container_Lengths => True,
         Byte_Values               => True,
         Nonfinite_Float_64        => True,
         Signed_Float_Zero         => False,
         Arbitrary_Map_Keys        => True,
         Lossless_Optionals        => True);
      Writer : Counting.Counter;
      Error  : Errors.Error_Info;
   begin
      Counting.Reset (Writer, No_Signed_Zero, Serialization_Limits);
      Writer.Put_Float_64 (Data_Model.Make_Finite (-0.0), Error);
      pragma Assert
        (Error.Code = Errors.Unsupported_Value and then Writer.Event_Count = 0);

      Errors.Reset (Error);
      Counting.Reset (Writer, No_Signed_Zero, Serialization_Limits);
      Writer.Put_Float_64 (Data_Model.Make_Finite (0.0), Error);
      Writer.Finish_Document (Error);
      pragma Assert
        (Error.Code = Errors.No_Error and then Writer.Event_Count = 1);
   end;

   declare
      Restricted : constant Data_Model.Format_Capabilities :=
        (Unknown_Container_Lengths => True,
         Byte_Values               => True,
         Nonfinite_Float_64        => True,
         Signed_Float_Zero         => True,
         Arbitrary_Map_Keys        => False,
         Lossless_Optionals        => True);
      Writer : Counting.Counter;
      Error  : Errors.Error_Info;
   begin
      Counting.Reset (Writer, Restricted, Serialization_Limits);
      Writer.Begin_Map (Data_Model.Known_Length (1), Error);
      Writer.Put_Enumeration ("Fixtures.Key", "first", Error);
      Writer.Put_Signed (1, Error);
      Writer.End_Map (Error);
      Writer.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error);

      Counting.Reset (Writer, Restricted, Serialization_Limits);
      Errors.Fail (Error, Errors.Application_Error);
      Writer.Put_Text (String'[1 => Character'Val (16#C0#)], Error);
      pragma Assert (Error.Code = Errors.Application_Error);
      pragma Assert (Writer.State = Flyology_Serde.Serialization.Ready);

      Errors.Reset (Error);
      Writer.Put_Null (Error);
      Writer.Finish_Document (Error);
      pragma Assert (Writer.State = Flyology_Serde.Serialization.Finished);
      Errors.Reset (Error);
      Writer.Put_Text (String'[1 => Character'Val (16#C0#)], Error);
      pragma Assert (Error.Code = Errors.Invalid_State);
      pragma Assert (Writer.State = Flyology_Serde.Serialization.Finished);

      Errors.Reset (Error);
      Writer.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.Invalid_State);
      pragma Assert (Writer.State = Flyology_Serde.Serialization.Finished);

      Writer.Abort_Document;
      Errors.Reset (Error);
      Writer.Put_Boolean (True, Error);
      pragma Assert (Error.Code = Errors.Invalid_State);
      pragma Assert (Writer.State = Flyology_Serde.Serialization.Poisoned);

      Errors.Reset (Error);
      Counting.Reset (Writer, Restricted, Serialization_Limits);
      Writer.Put_Boolean (True, Error);
      Writer.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Writer.State = Flyology_Serde.Serialization.Finished);
   end;
end Adapter_Conformance_Tests;
