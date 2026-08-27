with Ada.Streams;
with Flyology_Serde.Adapters.Fixed_Arrays;
with Flyology_Serde.Adapters.Signed_Integers;
with Flyology_Serde.Deserialization;
with Flyology_Serde.Deserializers.CBOR;
with Flyology_Serde.Deserializers.JSON;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;
with Flyology_Serde.Serializers.CBOR;
with Flyology_Serde.Serializers.JSON;

procedure Public_Fixed_Array_Client is
   package Errors renames Flyology_Serde.Errors;
   package Policies renames Flyology_Serde.Policies;

   use type Ada.Streams.Stream_Element_Array;
   use type Errors.Error_Code;

   type Position is (Left, Right);
   for Position use (Left => 11, Right => 37);
   type Pair is array (Position) of Integer;

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

   package Pairs is new
     Flyology_Serde.Adapters.Fixed_Arrays
       (Index_Type          => Position,
        Element_Type        => Integer,
        Array_Type          => Pair,
        Serialize_Element   => Integers.Serialize_Value,
        Deserialize_Element => Deserialize_Integer);

   Policy   : constant Policies.Decode_Policy := (others => <>);
   Expected : constant Pair := [17, -9];
begin
   declare
      Writer : Flyology_Serde.Serializers.JSON.Bounded_Writer (32);
      Error  : Errors.Error_Info;
      Text   : String (1 .. 32);
      Length : Natural := 0;
      Source : aliased constant String := "[17,-9]";
      Reader : Flyology_Serde.Deserializers.JSON.Reader (Source'Access);
      Target : Pair := [0, 0];
   begin
      Pairs.Serialize_Value (Expected, Writer, Error);
      Writer.Finish_Document (Error);
      Writer.Copy_Output (Text, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Text (1 .. Length) = Source);

      Flyology_Serde.Deserializers.JSON.Initialize (Reader, Policy);
      Pairs.Deserialize_Candidate (Reader, Target, Policy, Error);
      Reader.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Target = Expected);
   end;

   declare
      subtype Bytes is Ada.Streams.Stream_Element_Array;
      Writer : Flyology_Serde.Serializers.CBOR.Bounded_Writer (16);
      Error  : Errors.Error_Info;
      Buffer : Bytes (1 .. 16);
      Length : Natural := 0;
      Source : aliased constant Bytes := [16#82#, 17, 16#28#];
      Reader : Flyology_Serde.Deserializers.CBOR.Reader (Source'Access);
      Target : Pair := [0, 0];
   begin
      Pairs.Serialize_Value (Expected, Writer, Error);
      Writer.Finish_Document (Error);
      Writer.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma
        Assert
          (Buffer (1 .. Ada.Streams.Stream_Element_Offset (Length)) = Source);

      Flyology_Serde.Deserializers.CBOR.Initialize (Reader, Policy);
      Pairs.Deserialize_Candidate (Reader, Target, Policy, Error);
      Reader.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Target = Expected);
   end;
end Public_Fixed_Array_Client;
