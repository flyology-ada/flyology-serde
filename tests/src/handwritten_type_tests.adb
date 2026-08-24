with Flyology_Serde.Adapters.Signed_Integers;
with Flyology_Serde.Deserializers.JSON;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;
with Flyology_Serde.Serialization;
with Flyology_Serde.Serialization_Adapters;
with Flyology_Serde.Serializers.JSON;
with Handwritten_Fixtures;

procedure Handwritten_Type_Tests is
   package Errors renames Flyology_Serde.Errors;
   package JSON_Readers renames Flyology_Serde.Deserializers.JSON;
   package JSON_Writers renames Flyology_Serde.Serializers.JSON;
   package Serialization renames Flyology_Serde.Serialization;
   use type Errors.Error_Code;
   use type Handwritten_Fixtures.Variant_Kind;

   Policy : constant Flyology_Serde.Policies.Decode_Policy := (others => <>);
   Limits : constant Serialization.Serialization_Limits :=
     (Maximum_Nesting_Depth   => 8,
      Maximum_Container_Items => 16,
      Maximum_Text_Length     => 64,
      Maximum_Byte_Length     => 64,
      Maximum_Logical_Events  => 32);

   package Integer_Boxes is new Handwritten_Fixtures.Boxes (Integer);
   package Integers is new Flyology_Serde.Adapters.Signed_Integers (Integer);

   procedure Serialize_Box
     (Item  : Integer_Boxes.Box;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
   begin
      Integers.Serialize_Value (Integer_Boxes.Get (Item), Into, Error);
   end Serialize_Box;

   package Box_Serialization is new Flyology_Serde.Serialization_Adapters
     (Source_Type      => Integer_Boxes.Box,
      Limits           => Limits,
      Serialize_Value => Serialize_Box);
begin
   declare
      Writer : JSON_Writers.Bounded_Writer (16);
      Buffer : String (1 .. 16);
      Length : Natural := 0;
      Error  : Errors.Error_Info;
   begin
      Handwritten_Fixtures.Serialize
        (Handwritten_Fixtures.Make_Private (42), Writer, Error);
      Writer.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Buffer (1 .. Length) = "42");
   end;

   declare
      Item   : Handwritten_Fixtures.Limited_Value;
      Writer : JSON_Writers.Bounded_Writer (16);
      Buffer : String (1 .. 16);
      Length : Natural := 0;
      Error  : Errors.Error_Info;
   begin
      Handwritten_Fixtures.Initialize (Item, 9);
      Handwritten_Fixtures.Serialize (Item, Writer, Error);
      Writer.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Buffer (1 .. Length) = "9");
   end;

   declare
      Input  : aliased constant String := "13 false";
      Reader : JSON_Readers.Reader (Input'Access);
      Target : Handwritten_Fixtures.Controlled_Builder;
      Error  : Errors.Error_Info;
   begin
      Handwritten_Fixtures.Reset_Controlled_Counters;
      Handwritten_Fixtures.Initialize (Target, 4);
      Reader.Initialize (Policy);
      Handwritten_Fixtures.Deserialize (Reader, Target, Error);
      pragma Assert (Error.Code = Errors.Syntax_Error);
      pragma Assert (Handwritten_Fixtures.Value (Target) = 4);
      pragma Assert
        (Handwritten_Fixtures.Acquisitions = 1
         and then Handwritten_Fixtures.Releases = 1);
      declare
         Success_Input : aliased constant String := "14";
         Success_Reader : JSON_Readers.Reader (Success_Input'Access);
         Success_Error : Errors.Error_Info;
      begin
         Success_Reader.Initialize (Policy);
         Handwritten_Fixtures.Deserialize
           (Success_Reader, Target, Success_Error);
         pragma Assert (Success_Error.Code = Errors.No_Error);
         pragma Assert (Handwritten_Fixtures.Value (Target) = 14);
         pragma Assert
           (Handwritten_Fixtures.Acquisitions = 2
            and then Handwritten_Fixtures.Releases = 2);
      end;
   end;

   declare
      Input  : aliased constant String := "[""flag"",{""flag"":true}]";
      Reader : JSON_Readers.Reader (Input'Access);
      Target : Handwritten_Fixtures.Variant_Builder;
      Result : Handwritten_Fixtures.Discriminated_Value;
      Error  : Errors.Error_Info;
   begin
      Handwritten_Fixtures.Initialize
        (Target, (Kind => Handwritten_Fixtures.Number_Kind, Number => 5));
      Reader.Initialize (Policy);
      Handwritten_Fixtures.Deserialize (Reader, Target, Error);
      Result := Handwritten_Fixtures.Value (Target);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert
        (Result.Kind = Handwritten_Fixtures.Flag_Kind and then Result.Flag);
   end;

   declare
      Input  : aliased constant String := "[""number"",{""flag"":true}]";
      Reader : JSON_Readers.Reader (Input'Access);
      Target : Handwritten_Fixtures.Variant_Builder;
      Result : Handwritten_Fixtures.Discriminated_Value;
      Error  : Errors.Error_Info;
   begin
      Handwritten_Fixtures.Initialize
        (Target, (Kind => Handwritten_Fixtures.Number_Kind, Number => 5));
      Reader.Initialize (Policy);
      Handwritten_Fixtures.Deserialize (Reader, Target, Error);
      Result := Handwritten_Fixtures.Value (Target);
      pragma Assert (Error.Code = Errors.Unknown_Field);
      pragma Assert
        (Result.Kind = Handwritten_Fixtures.Number_Kind
         and then Result.Number = 5);
   end;

   declare
      Writer : JSON_Writers.Bounded_Writer (16);
      Buffer : String (1 .. 16);
      Length : Natural := 0;
      Error  : Errors.Error_Info;
   begin
      Box_Serialization.Serialize (Integer_Boxes.Make (-17), Writer, Error);
      Writer.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Buffer (1 .. Length) = "-17");
   end;
end Handwritten_Type_Tests;
