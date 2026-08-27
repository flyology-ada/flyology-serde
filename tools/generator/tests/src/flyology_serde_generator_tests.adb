with Ada.Streams;
with Flyology.Generated;
with Flyology_Serde.Deserializers.CBOR;
with Flyology_Serde.Deserializers.JSON;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;
with Flyology_Serde.Serializers.CBOR;
with Flyology_Serde.Serializers.JSON;
with Wire_Shape;

procedure Flyology_Serde_Generator_Tests is
   package CBOR_Readers renames Flyology_Serde.Deserializers.CBOR;
   package CBOR_Writers renames Flyology_Serde.Serializers.CBOR;
   package Errors renames Flyology_Serde.Errors;
   package JSON_Readers renames Flyology_Serde.Deserializers.JSON;
   package JSON_Writers renames Flyology_Serde.Serializers.JSON;
   package Policies renames Flyology_Serde.Policies;

   use type Ada.Streams.Stream_Element_Array;
   use type Errors.Error_Code;
   use type Wire_Shape.Public_Record;
   use type Wire_Shape.Signed_16;
   use type Wire_Shape.Unsigned_16;

   subtype Bytes is Ada.Streams.Stream_Element_Array;
   Policy        : constant Policies.Decode_Policy := (others => <>);
   Original      : constant Wire_Shape.Public_Record :=
     (Enabled => True, Signed => -12, Unsigned => 65_535);
   CBOR_Encoding : constant Bytes :=
     [16#A3#,
      16#67#,
      Character'Pos ('e'),
      Character'Pos ('n'),
      Character'Pos ('a'),
      Character'Pos ('b'),
      Character'Pos ('l'),
      Character'Pos ('e'),
      Character'Pos ('d'),
      16#F5#,
      16#66#,
      Character'Pos ('s'),
      Character'Pos ('i'),
      Character'Pos ('g'),
      Character'Pos ('n'),
      Character'Pos ('e'),
      Character'Pos ('d'),
      16#2B#,
      16#68#,
      Character'Pos ('u'),
      Character'Pos ('n'),
      Character'Pos ('s'),
      Character'Pos ('i'),
      Character'Pos ('g'),
      Character'Pos ('n'),
      Character'Pos ('e'),
      Character'Pos ('d'),
      16#19#,
      16#FF#,
      16#FF#];
begin
   declare
      Writer : JSON_Writers.Bounded_Writer (96);
      Buffer : String (1 .. 96);
      Length : Natural := 0;
      Error  : Errors.Error_Info;
   begin
      Flyology.Generated.Serialize (Original, Writer, Error);
      Writer.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma
        Assert
          (Buffer (1 .. Length)
             = "{""enabled"":true,""signed"":-12,""unsigned"":65535}");
   end;

   declare
      Writer : CBOR_Writers.Bounded_Writer (64);
      Buffer : Bytes (1 .. 64);
      Length : Natural := 0;
      Error  : Errors.Error_Info;
   begin
      Flyology.Generated.Serialize (Original, Writer, Error);
      Writer.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma
        Assert
          (Buffer (1 .. Ada.Streams.Stream_Element_Offset (Length))
             = CBOR_Encoding);
   end;

   declare
      Input  : aliased constant String :=
        "{""unsigned"":65535,""enabled"":true,""signed"":-12}";
      Reader : JSON_Readers.Reader (Input'Access);
      Target : Flyology.Generated.Builder;
      Error  : Errors.Error_Info;
      Result : Wire_Shape.Public_Record;
   begin
      pragma Assert (not Flyology.Generated.Has_Value (Target));
      Flyology.Generated.Initialize
        (Target, (Enabled => False, Signed => 7, Unsigned => 8), Error);
      pragma Assert (Flyology.Generated.Has_Value (Target));
      Reader.Initialize (Policy);
      Flyology.Generated.Deserialize (Reader, Target, Error);
      Result := Flyology.Generated.Value (Target);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma
        Assert
          (Result.Enabled
             and then Result.Signed = -12
             and then Result.Unsigned = 65_535);
   end;

   declare
      Input  : aliased constant Bytes := CBOR_Encoding;
      Reader : CBOR_Readers.Reader (Input'Access);
      Target : Flyology.Generated.Builder;
      Error  : Errors.Error_Info;
      Result : Wire_Shape.Public_Record;
   begin
      pragma Assert (not Flyology.Generated.Has_Value (Target));
      Flyology.Generated.Initialize
        (Target, (Enabled => False, Signed => 7, Unsigned => 8), Error);
      pragma Assert (Flyology.Generated.Has_Value (Target));
      Reader.Initialize (Policy);
      Flyology.Generated.Deserialize (Reader, Target, Error);
      Result := Flyology.Generated.Value (Target);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma
        Assert
          (Result.Enabled
             and then Result.Signed = -12
             and then Result.Unsigned = 65_535);
   end;

   --  Trailing input fails before the generated builder publishes Candidate.
   declare
      Input  : aliased constant String :=
        "{""enabled"":true,""signed"":-12,""unsigned"":65535} false";
      Reader : JSON_Readers.Reader (Input'Access);
      Target : Flyology.Generated.Builder;
      Error  : Errors.Error_Info;
      Result : Wire_Shape.Public_Record;
   begin
      pragma Assert (not Flyology.Generated.Has_Value (Target));
      Flyology.Generated.Initialize
        (Target, (Enabled => False, Signed => 7, Unsigned => 8), Error);
      pragma Assert (Flyology.Generated.Has_Value (Target));
      Reader.Initialize (Policy);
      Flyology.Generated.Deserialize (Reader, Target, Error);
      pragma Assert (Flyology.Generated.Has_Value (Target));
      Result := Flyology.Generated.Value (Target);
      pragma Assert (Error.Code = Errors.Syntax_Error);
      pragma
        Assert
          (not Result.Enabled
             and then Result.Signed = 7
             and then Result.Unsigned = 8);
   end;

   --  A fresh builder is not a published value, and a failed attempt cannot
   --  contaminate the candidate used by a later retry.
   declare
      Valid_Input   : aliased constant String :=
        "{""enabled"":true,""signed"":-12,""unsigned"":65535}";
      Invalid_Input : aliased constant String := "{""enabled"":true}";
      Fresh_Reader  : JSON_Readers.Reader (Valid_Input'Access);
      Failed_Reader : JSON_Readers.Reader (Invalid_Input'Access);
      Retry_Reader  : JSON_Readers.Reader (Valid_Input'Access);
      Fresh_Target  : Flyology.Generated.Builder;
      Retry_Target  : Flyology.Generated.Builder;
      Error         : Errors.Error_Info;
      Prior         : constant Wire_Shape.Public_Record :=
        (Enabled => False, Signed => 7, Unsigned => 8);
   begin
      Fresh_Reader.Initialize (Policy);
      Flyology.Generated.Deserialize (Fresh_Reader, Fresh_Target, Error);
      pragma Assert (Error.Code = Errors.Invalid_State);
      pragma Assert (not Flyology.Generated.Has_Value (Fresh_Target));

      Errors.Reset (Error);
      Flyology.Generated.Initialize (Retry_Target, Prior, Error);
      Failed_Reader.Initialize (Policy);
      Flyology.Generated.Deserialize (Failed_Reader, Retry_Target, Error);
      pragma Assert (Error.Code = Errors.Missing_Field);
      pragma Assert (Flyology.Generated.Value (Retry_Target) = Prior);

      Errors.Reset (Error);
      Retry_Reader.Initialize (Policy);
      Flyology.Generated.Deserialize (Retry_Reader, Retry_Target, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Flyology.Generated.Value (Retry_Target) = Original);
   end;
end Flyology_Serde_Generator_Tests;
