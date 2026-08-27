with Ada.Streams;
with Production_Shapes;
with Production_Shapes_Serde;
with Flyology_Serde.Deserializers.CBOR;
with Flyology_Serde.Deserializers.JSON;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;
with Flyology_Serde.Serializers.CBOR;
with Flyology_Serde.Serializers.JSON;

procedure Production_Shape_Generated_Tests is
   package CBOR_Readers renames Flyology_Serde.Deserializers.CBOR;
   package CBOR_Writers renames Flyology_Serde.Serializers.CBOR;
   package Errors renames Flyology_Serde.Errors;
   package JSON_Readers renames Flyology_Serde.Deserializers.JSON;
   package JSON_Writers renames Flyology_Serde.Serializers.JSON;
   package Policies renames Flyology_Serde.Policies;
   package Serde renames Production_Shapes_Serde;
   package Shapes renames Production_Shapes;

   use type Errors.Error_Code;
   use type Shapes.Packet;

   Expected       : constant Shapes.Packet :=
     (Shade   => Shapes.Green,
      Samples =>
        [Shapes.First  => Shapes.Red,
         Shapes.Middle => Shapes.Green,
         Shapes.Last   => Shapes.Blue]);
   Prior          : constant Shapes.Packet :=
     (Shade => Shapes.Blue, Samples => [others => Shapes.Blue]);
   Default_Policy : constant Policies.Decode_Policy := (others => <>);

   procedure Assert_JSON_Roundtrip is
      Writer : JSON_Writers.Bounded_Writer (128);
      Buffer : String (1 .. 128);
      Length : Natural := 0;
      Error  : Errors.Error_Info;
   begin
      Serde.Serialize (Expected, Writer, Error);
      Writer.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma
        Assert
          (Buffer (1 .. Length)
             = "{""shade"":""green"",""samples"":[""red"",""green"",""blue""]}");

      declare
         Source : aliased constant String := Buffer (1 .. Length);
         Reader : JSON_Readers.Reader (Source'Access);
         Target : Serde.Builder;
      begin
         Errors.Reset (Error);
         Serde.Initialize (Target, Prior, Error);
         Reader.Initialize (Default_Policy);
         Serde.Deserialize (Reader, Target, Error);
         pragma Assert (Error.Code = Errors.No_Error);
         pragma Assert (Serde.Value (Target) = Expected);
      end;
   end Assert_JSON_Roundtrip;

   procedure Assert_JSON_Aliases is
      Source : aliased constant String :=
        "{""shade"":""g"",""samples"":[""r"",""g"",""b""]}";
      Reader : JSON_Readers.Reader (Source'Access);
      Target : Serde.Builder;
      Error  : Errors.Error_Info;
   begin
      Serde.Initialize (Target, Prior, Error);
      Reader.Initialize (Default_Policy);
      Serde.Deserialize (Reader, Target, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Serde.Value (Target) = Expected);
   end Assert_JSON_Aliases;

   procedure Assert_JSON_Rollback is
      Source : aliased constant String :=
        "{""shade"":""green"",""samples"":[""red"",""green""]}";
      Reader : JSON_Readers.Reader (Source'Access);
      Target : Serde.Builder;
      Error  : Errors.Error_Info;
   begin
      Serde.Initialize (Target, Prior, Error);
      Reader.Initialize (Default_Policy);
      Serde.Deserialize (Reader, Target, Error);
      pragma Assert (Error.Code = Errors.Out_Of_Range);
      pragma Assert (Serde.Value (Target) = Prior);
   end Assert_JSON_Rollback;

   procedure Assert_JSON_Failure
     (Text : String; Expected_Code : Errors.Error_Code)
   is
      Source : aliased constant String := Text;
      Reader : JSON_Readers.Reader (Source'Access);
      Target : Serde.Builder;
      Error  : Errors.Error_Info;
   begin
      Serde.Initialize (Target, Prior, Error);
      Reader.Initialize (Default_Policy);
      Serde.Deserialize (Reader, Target, Error);
      pragma Assert (Error.Code = Expected_Code);
      pragma Assert (Serde.Value (Target) = Prior);
   end Assert_JSON_Failure;

   procedure Assert_Fresh_And_Retry is
      Valid_Text    : aliased constant String :=
        "{""shade"":""green"",""samples"":[""red"",""green"",""blue""]}";
      Invalid_Text  : aliased constant String :=
        "{""shade"":""green"",""samples"":[""red"",""green""]}";
      Fresh_Reader  : JSON_Readers.Reader (Valid_Text'Access);
      Failed_Reader : JSON_Readers.Reader (Invalid_Text'Access);
      Retry_Reader  : JSON_Readers.Reader (Valid_Text'Access);
      Fresh_Target  : Serde.Builder;
      Retry_Target  : Serde.Builder;
      Error         : Errors.Error_Info;
   begin
      Fresh_Reader.Initialize (Default_Policy);
      Serde.Deserialize (Fresh_Reader, Fresh_Target, Error);
      pragma Assert (Error.Code = Errors.Invalid_State);
      pragma Assert (not Serde.Has_Value (Fresh_Target));

      Errors.Reset (Error);
      Serde.Initialize (Retry_Target, Prior, Error);
      Failed_Reader.Initialize (Default_Policy);
      Serde.Deserialize (Failed_Reader, Retry_Target, Error);
      pragma Assert (Error.Code = Errors.Out_Of_Range);
      pragma Assert (Serde.Value (Retry_Target) = Prior);

      Errors.Reset (Error);
      Retry_Reader.Initialize (Default_Policy);
      Serde.Deserialize (Retry_Reader, Retry_Target, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Serde.Value (Retry_Target) = Expected);
   end Assert_Fresh_And_Retry;

   procedure Assert_CBOR_Roundtrip is
      subtype Bytes is Ada.Streams.Stream_Element_Array;
      Writer : CBOR_Writers.Bounded_Writer (128);
      Buffer : Bytes (1 .. 128);
      Length : Natural := 0;
      Error  : Errors.Error_Info;
   begin
      Serde.Serialize (Expected, Writer, Error);
      Writer.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      declare
         Source : aliased constant Bytes :=
           Buffer (1 .. Ada.Streams.Stream_Element_Offset (Length));
         Reader : CBOR_Readers.Reader (Source'Access);
         Target : Serde.Builder;
      begin
         Errors.Reset (Error);
         Serde.Initialize (Target, Prior, Error);
         Reader.Initialize (Default_Policy);
         Serde.Deserialize (Reader, Target, Error);
         pragma Assert (Error.Code = Errors.No_Error);
         pragma Assert (Serde.Value (Target) = Expected);
      end;
      declare
         Source : aliased constant Bytes :=
           Buffer (1 .. Ada.Streams.Stream_Element_Offset (Length - 1));
         Reader : CBOR_Readers.Reader (Source'Access);
         Target : Serde.Builder;
      begin
         Errors.Reset (Error);
         Serde.Initialize (Target, Prior, Error);
         Reader.Initialize (Default_Policy);
         Serde.Deserialize (Reader, Target, Error);
         pragma Assert (Error.Code = Errors.Syntax_Error);
         pragma Assert (Serde.Value (Target) = Prior);
      end;
   end Assert_CBOR_Roundtrip;
begin
   Assert_JSON_Roundtrip;
   Assert_JSON_Aliases;
   Assert_JSON_Rollback;
   Assert_JSON_Failure
     ("{""shade"":""purple"",""samples"":[""red"",""green"",""blue""]}",
      Errors.Invalid_Value);
   Assert_JSON_Failure
     ("{""shade"":""green"",""samples"":[""red"",""green"",""blue"",""red""]}",
      Errors.Out_Of_Range);
   Assert_JSON_Failure
     ("{""shade"":""green"",""shade"":""blue"",""samples"":[""red"",""green"",""blue""]}",
      Errors.Duplicate_Field);
   Assert_JSON_Failure
     ("{""shade"":""green"",""samples"":[""red"",""green"",""blue""],""other"":0}",
      Errors.Unknown_Field);
   Assert_JSON_Failure
     ("{""shade"":""green"",""samples"":[""red"",""green"",""blue""],""unknown8"":0}",
      Errors.Unknown_Field);
   Assert_JSON_Failure
     ("{""samples"":[""red"",""green"",""blue""]}", Errors.Missing_Field);
   declare
      Name_64 : constant String (1 .. 64) := [others => 'x'];
      Name_65 : constant String (1 .. 65) := [others => 'x'];
   begin
      Assert_JSON_Failure
        ("{""shade"":"""
         & Name_64
         & """,""samples"":[""red"",""green"",""blue""]}",
         Errors.Invalid_Value);
      Assert_JSON_Failure
        ("{""shade"":"""
         & Name_65
         & """,""samples"":[""red"",""green"",""blue""]}",
         Errors.Capacity_Exceeded);
      Assert_JSON_Failure
        ("{""shade"":""green"",""samples"":[""red"",""green"",""blue""],"""
         & Name_64
         & """:0}",
         Errors.Unknown_Field);
      Assert_JSON_Failure
        ("{""shade"":""green"",""samples"":[""red"",""green"",""blue""],"""
         & Name_65
         & """:0}",
         Errors.Capacity_Exceeded);
   end;
   Assert_Fresh_And_Retry;
   Assert_CBOR_Roundtrip;
end Production_Shape_Generated_Tests;
