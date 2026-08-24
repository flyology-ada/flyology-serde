with Ada.Streams;
with Ada.Unchecked_Conversion;
with Flyology_Serde.Data_Model;
with Flyology_Serde.Errors;
with Flyology_Serde.Serialization;
with Flyology_Serde.Serializers.JSON;
with Interfaces;

procedure JSON_Writer_Tests is
   package Errors renames Flyology_Serde.Errors;
   package JSON renames Flyology_Serde.Serializers.JSON;
   package Data_Model renames Flyology_Serde.Data_Model;
   use type Errors.Error_Code;
   use type Flyology_Serde.Serialization.Serializer_State;
   use type Interfaces.IEEE_Float_64;
   use type Interfaces.Unsigned_64;

   function Bits is new Ada.Unchecked_Conversion
     (Interfaces.IEEE_Float_64, Interfaces.Unsigned_64);

   Writer  : JSON.Bounded_Writer (512);
   Small   : JSON.Bounded_Writer (4);
   Dynamic : JSON.Allocating_Writer;
   Error   : Errors.Error_Info;
   Bytes   : constant Ada.Streams.Stream_Element_Array := [0, 255];

   procedure Assert_Output
     (Self : in out JSON.Bounded_Writer; Expected : String) is
      Buffer     : String (1 .. Expected'Length);
      Length     : Natural;
      Copy_Error : Errors.Error_Info;
   begin
      Self.Finish_Document (Copy_Error);
      pragma Assert (Copy_Error.Code = Errors.No_Error);
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
   Assert_Output (Writer, "{""identifier"":42,""enabled"":true}");
   pragma Assert (Writer.Is_Complete);

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
   Writer.Put_Float_64 (Data_Model.Make_Finite (-0.0), Error);
   pragma Assert (Error.Code = Errors.No_Error);
   declare
      Buffer     : String (1 .. 64);
      Length     : Natural;
      Copy_Error : Errors.Error_Info;
   begin
      Writer.Finish_Document (Copy_Error);
      Writer.Copy_Output (Buffer, Length, Copy_Error);
      pragma Assert (Copy_Error.Code = Errors.No_Error);
      pragma Assert (Length > 0 and then Buffer (1) = '-');
   end;

   Writer.Reset;
   declare
      Original   : constant Interfaces.IEEE_Float_64 :=
        Interfaces.IEEE_Float_64'Adjacent (1.0, 2.0);
      Buffer     : String (1 .. 64);
      Length     : Natural;
      Copy_Error : Errors.Error_Info;
      Reparsed   : Interfaces.IEEE_Float_64;
   begin
      Writer.Put_Float_64 (Data_Model.Make_Finite (Original), Error);
      Writer.Finish_Document (Copy_Error);
      Writer.Copy_Output (Buffer, Length, Copy_Error);
      pragma Assert (Copy_Error.Code = Errors.No_Error);
      Reparsed := Interfaces.IEEE_Float_64'Value (Buffer (1 .. Length));
      pragma Assert (Bits (Reparsed) = Bits (Original));
   end;

   Writer.Reset;
   Writer.Put_Float_64 (Data_Model.Positive_Infinity_Value, Error);
   pragma Assert (Error.Code = Errors.Unsupported_Value);
   pragma Assert (Writer.Written_Length = 0);
   pragma Assert (not Writer.Is_Complete);

   Errors.Reset (Error);
   Writer.Reset;

   Small.Put_Null (Error);
   pragma Assert (Error.Code = Errors.No_Error);
   Assert_Output (Small, "null");
   Small.Reset;
   Small.Put_Text ("abc", Error);
   pragma Assert (Error.Code = Errors.Capacity_Exceeded);
   pragma Assert (not Small.Is_Complete);

   declare
      Buffer       : String (1 .. 4);
      Length       : Natural := Natural'Last;
      Output_Error : Errors.Error_Info;
   begin
      Small.Copy_Output (Buffer, Length, Output_Error);
      pragma Assert (Output_Error.Code = Errors.Invalid_State);
      pragma Assert (Length = 0 and then Buffer = "    ");
   end;

   Errors.Reset (Error);
   Small.Reset;
   Small.Put_Null (Error);
   Small.Finish_Document (Error);
   pragma Assert (Small.Is_Complete);

   Dynamic.Begin_Sequence ((Known => False, Length => 0), Error);
   Dynamic.Put_Boolean (False, Error);
   Dynamic.Put_Enumeration ("Tests.Color", "Red", Error);
   pragma Assert (Dynamic.Output = "");
   Dynamic.End_Record (Error);
   pragma Assert (Error.Code = Errors.Invalid_State);
   pragma Assert (Dynamic.Output = "");

   Errors.Reset (Error);
   Dynamic.Reset;
   Dynamic.Begin_Sequence ((Known => False, Length => 0), Error);
   Dynamic.Put_Boolean (False, Error);
   Dynamic.Put_Enumeration ("Tests.Color", "Red", Error);
   Dynamic.End_Sequence (Error);
   Dynamic.Finish_Document (Error);
   pragma Assert (Error.Code = Errors.No_Error);
   pragma Assert (Dynamic.Is_Complete);
   pragma Assert (Dynamic.Output = "[false,""Red""]");

   Writer.Reset;
   Errors.Fail (Error, Errors.Application_Error);
   Writer.Put_Text (String'[1 => Character'Val (16#C0#)], Error);
   pragma Assert (Error.Code = Errors.Application_Error);
   pragma Assert (Writer.State = Flyology_Serde.Serialization.Ready);

   Errors.Reset (Error);
   Writer.Put_Null (Error);
   declare
      Buffer : String (1 .. 4);
      Length : Natural := Natural'Last;
      Copy_Error : Errors.Error_Info;
   begin
      Writer.Copy_Output (Buffer, Length, Copy_Error);
      pragma Assert (Copy_Error.Code = Errors.Invalid_State and then Length = 0);
   end;
   Writer.Finish_Document (Error);
   pragma Assert (Writer.State = Flyology_Serde.Serialization.Finished);
   Errors.Reset (Error);
   Writer.Begin_Variant
     ("Tests.Shape", String'[1 => Character'Val (16#C0#)], 0, Error);
   pragma Assert (Error.Code = Errors.Invalid_State);
   pragma Assert (Writer.State = Flyology_Serde.Serialization.Finished);
   Errors.Reset (Error);
   Writer.Finish_Document (Error);
   pragma Assert (Error.Code = Errors.Invalid_State);
   pragma Assert (Writer.State = Flyology_Serde.Serialization.Finished);
   declare
      Buffer : String (1 .. 4);
      Length : Natural := 0;
      Copy_Error : Errors.Error_Info;
   begin
      Writer.Copy_Output (Buffer, Length, Copy_Error);
      pragma Assert (Copy_Error.Code = Errors.No_Error);
      pragma Assert (Buffer = "null" and then Length = 4);
   end;

   Writer.Abort_Document;
   Errors.Reset (Error);
   Writer.Put_Boolean (True, Error);
   pragma Assert (Error.Code = Errors.Invalid_State);
   pragma Assert (Writer.State = Flyology_Serde.Serialization.Poisoned);

   Errors.Reset (Error);
   Writer.Reset;
   Writer.Put_Boolean (True, Error);
   Writer.Finish_Document (Error);
   pragma Assert (Error.Code = Errors.No_Error);
   pragma Assert (Writer.State = Flyology_Serde.Serialization.Finished);
   declare
      Buffer : String (1 .. 4);
      Length : Natural := 0;
   begin
      Writer.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Buffer = "true" and then Length = 4);
   end;
end JSON_Writer_Tests;
