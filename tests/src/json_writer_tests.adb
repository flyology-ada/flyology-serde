with Ada.Streams;
with Flyology_Serde.Errors;
with Flyology_Serde.Serializers.JSON;
with Interfaces;

procedure JSON_Writer_Tests is
   package Errors renames Flyology_Serde.Errors;
   package JSON renames Flyology_Serde.Serializers.JSON;
   use type Errors.Error_Code;
   use type Interfaces.IEEE_Float_64;

   Writer  : JSON.Bounded_Writer (512);
   Small   : JSON.Bounded_Writer (4);
   Dynamic : JSON.Allocating_Writer;
   Error   : Errors.Error_Info;
   Bytes   : constant Ada.Streams.Stream_Element_Array := [0, 255];

   procedure Assert_Output (Self : JSON.Bounded_Writer; Expected : String) is
      Buffer     : String (1 .. Expected'Length);
      Length     : Natural;
      Copy_Error : Errors.Error_Info;
   begin
      Self.Copy_Output (Buffer, Length, Copy_Error);
      pragma Assert (Copy_Error.Code = Errors.No_Error);
      pragma Assert (Length = Expected'Length);
      pragma Assert (Buffer = Expected);
   end Assert_Output;
begin
   Writer.Begin_Record ("Tests.Sample", 2, Error);
   Writer.Put_Field ("identifier", Error);
   Writer.Put_Unsigned (42, Error);
   Writer.Put_Field ("enabled", Error);
   Writer.Put_Boolean (True, Error);
   Writer.End_Record (Error);
   pragma Assert (Error.Code = Errors.No_Error);
   pragma Assert (Writer.Is_Complete);
   Assert_Output (Writer, "{""identifier"":42,""enabled"":true}");

   Writer.Reset;
   Writer.Begin_Optional (True, Error);
   Writer.Begin_Optional (False, Error);
   Writer.End_Optional (Error);
   Writer.End_Optional (Error);
   pragma Assert (Error.Code = Errors.No_Error);
   Assert_Output (Writer, "[1,[0]]");

   Writer.Reset;
   Writer.Put_Bytes (Bytes, Error);
   pragma Assert (Error.Code = Errors.No_Error);
   Assert_Output (Writer, "{""$bytes"":""00FF""}");

   Writer.Reset;
   Writer.Begin_Map ((Known => True, Length => 2), Error);
   Writer.Put_Signed (1, Error);
   Writer.Put_Text ("one", Error);
   Writer.Put_Signed (2, Error);
   Writer.Put_Text ("two", Error);
   Writer.End_Map (Error);
   pragma Assert (Error.Code = Errors.No_Error);
   Assert_Output (Writer, "[[1,""one""],[2,""two""]]");

   Writer.Reset;
   Writer.Begin_Variant ("Tests.Shape", "Circle", 1, Error);
   Writer.Put_Field ("radius", Error);
   Writer.Put_Signed (3, Error);
   Writer.End_Variant (Error);
   pragma Assert (Error.Code = Errors.No_Error);
   Assert_Output (Writer, "[""Circle"",{""radius"":3}]");

   Writer.Reset;
   Writer.Put_Text ("line" & Character'Val (10) & """quote", Error);
   pragma Assert (Error.Code = Errors.No_Error);
   Assert_Output (Writer, """line\n\""quote""");

   Writer.Reset;
   Writer.Put_Float_64 (-0.0, Error);
   pragma Assert (Error.Code = Errors.No_Error);
   declare
      Buffer     : String (1 .. 64);
      Length     : Natural;
      Copy_Error : Errors.Error_Info;
   begin
      Writer.Copy_Output (Buffer, Length, Copy_Error);
      pragma Assert (Copy_Error.Code = Errors.No_Error);
      pragma Assert (Length > 0 and then Buffer (1) = '-');
   end;

   Small.Put_Null (Error);
   pragma Assert (Error.Code = Errors.No_Error);
   Assert_Output (Small, "null");
   Small.Reset;
   Small.Put_Text ("abc", Error);
   pragma Assert (Error.Code = Errors.Capacity_Exceeded);
   pragma Assert (not Small.Is_Complete);

   Errors.Reset (Error);
   Small.Reset;
   Small.Put_Null (Error);
   pragma Assert (Small.Is_Complete);

   Dynamic.Begin_Sequence ((Known => False, Length => 0), Error);
   Dynamic.Put_Boolean (False, Error);
   Dynamic.Put_Enumeration ("Tests.Color", "Red", Error);
   Dynamic.End_Sequence (Error);
   pragma Assert (Error.Code = Errors.No_Error);
   pragma Assert (Dynamic.Is_Complete);
   pragma Assert (Dynamic.Output = "[false,""Red""]");
end JSON_Writer_Tests;
