with Ada.Streams;
with Flyology_Serde.Data_Model;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;
with Flyology_Serde.Serializers.CBOR;
with Interfaces;

procedure CBOR_Writer_Tests is
   package CBOR renames Flyology_Serde.Serializers.CBOR;
   package Data_Model renames Flyology_Serde.Data_Model;
   package Errors renames Flyology_Serde.Errors;
   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Array;
   use type Data_Model.Format_Capabilities;
   use type Errors.Error_Code;
   use type Interfaces.IEEE_Float_64;
   use type Interfaces.Integer_64;

   subtype Byte_Array is Ada.Streams.Stream_Element_Array;
   subtype Byte_Offset is Ada.Streams.Stream_Element_Offset;

   Writer  : CBOR.Bounded_Writer (512);
   Small   : CBOR.Bounded_Writer (1);
   Dynamic : CBOR.Allocating_Writer;
   Error   : Errors.Error_Info;

   procedure Assert_Output
     (Self : CBOR.Bounded_Writer; Expected : Byte_Array)
   is
      Buffer     : Byte_Array (1 .. Byte_Offset (Expected'Length));
      Length     : Natural;
      Copy_Error : Errors.Error_Info;
   begin
      Self.Copy_Output (Buffer, Length, Copy_Error);
      pragma Assert (Copy_Error.Code = Errors.No_Error);
      pragma Assert (Length = Expected'Length);
      pragma Assert (Buffer = Expected);
   end Assert_Output;

   procedure Reset_Writer is
   begin
      Errors.Reset (Error);
      Writer.Reset;
   end Reset_Writer;
begin
   pragma Assert (Writer.Capabilities = Data_Model.All_Capabilities);

   Writer.Put_Null (Error);
   pragma Assert (Error.Code = Errors.No_Error);
   pragma Assert (Writer.Is_Complete);
   Assert_Output (Writer, [1 => 16#F6#]);

   Reset_Writer;
   Writer.Put_Boolean (True, Error);
   Assert_Output (Writer, [1 => 16#F5#]);

   Reset_Writer;
   Writer.Put_Unsigned (23, Error);
   Assert_Output (Writer, [1 => 16#17#]);

   Reset_Writer;
   Writer.Put_Unsigned (24, Error);
   Assert_Output (Writer, [16#18#, 16#18#]);

   Reset_Writer;
   Writer.Put_Unsigned (255, Error);
   Assert_Output (Writer, [16#18#, 16#FF#]);

   Reset_Writer;
   Writer.Put_Unsigned (256, Error);
   Assert_Output (Writer, [16#19#, 16#01#, 16#00#]);

   Reset_Writer;
   Writer.Put_Unsigned (65_535, Error);
   Assert_Output (Writer, [16#19#, 16#FF#, 16#FF#]);

   Reset_Writer;
   Writer.Put_Unsigned (65_536, Error);
   Assert_Output (Writer, [16#1A#, 16#00#, 16#01#, 16#00#, 16#00#]);

   Reset_Writer;
   Writer.Put_Unsigned (16#1_0000_0000#, Error);
   Assert_Output
     (Writer,
      [16#1B#,
       16#00#,
       16#00#,
       16#00#,
       16#01#,
       16#00#,
       16#00#,
       16#00#,
       16#00#]);

   Reset_Writer;
   Writer.Put_Unsigned (Interfaces.Unsigned_64'Last, Error);
   Assert_Output
     (Writer,
      [16#1B#,
       16#FF#,
       16#FF#,
       16#FF#,
       16#FF#,
       16#FF#,
       16#FF#,
       16#FF#,
       16#FF#]);

   Reset_Writer;
   Writer.Put_Signed (0, Error);
   Assert_Output (Writer, [1 => 16#00#]);

   Reset_Writer;
   Writer.Put_Signed (-1, Error);
   Assert_Output (Writer, [1 => 16#20#]);

   Reset_Writer;
   Writer.Put_Signed (-24, Error);
   Assert_Output (Writer, [1 => 16#37#]);

   Reset_Writer;
   Writer.Put_Signed (-25, Error);
   Assert_Output (Writer, [16#38#, 16#18#]);

   Reset_Writer;
   Writer.Put_Signed (Interfaces.Integer_64'First, Error);
   Assert_Output
     (Writer,
      [16#3B#,
       16#7F#,
       16#FF#,
       16#FF#,
       16#FF#,
       16#FF#,
       16#FF#,
       16#FF#,
       16#FF#]);

   Reset_Writer;
   Writer.Put_Float_64 (Data_Model.Make_Finite (1.5), Error);
   Assert_Output
     (Writer,
      [16#FB#,
       16#3F#,
       16#F8#,
       16#00#,
       16#00#,
       16#00#,
       16#00#,
       16#00#,
       16#00#]);

   Reset_Writer;
   Writer.Put_Float_64 (Data_Model.Make_Finite (-0.0), Error);
   Assert_Output
     (Writer,
      [16#FB#,
       16#80#,
       16#00#,
       16#00#,
       16#00#,
       16#00#,
       16#00#,
       16#00#,
       16#00#]);

   Reset_Writer;
   Writer.Put_Float_64 (Data_Model.Positive_Infinity_Value, Error);
   Assert_Output
     (Writer,
      [16#FB#,
       16#7F#,
       16#F0#,
       16#00#,
       16#00#,
       16#00#,
       16#00#,
       16#00#,
       16#00#]);

   Reset_Writer;
   Writer.Put_Float_64 (Data_Model.Negative_Infinity_Value, Error);
   Assert_Output
     (Writer,
      [16#FB#,
       16#FF#,
       16#F0#,
       16#00#,
       16#00#,
       16#00#,
       16#00#,
       16#00#,
       16#00#]);

   Reset_Writer;
   Writer.Put_Float_64 (Data_Model.Not_A_Number_Value, Error);
   Assert_Output
     (Writer,
      [16#FB#,
       16#7F#,
       16#F8#,
       16#00#,
       16#00#,
       16#00#,
       16#00#,
       16#00#,
       16#00#]);

   Reset_Writer;
   Writer.Put_Text ("Ada", Error);
   Assert_Output (Writer, [16#63#, 16#41#, 16#64#, 16#61#]);

   Reset_Writer;
   Writer.Put_Text
     (Character'Val (16#C3#) & Character'Val (16#A9#), Error);
   Assert_Output (Writer, [16#62#, 16#C3#, 16#A9#]);

   Reset_Writer;
   declare
      Text       : constant String (1 .. 257) := [others => 'x'];
      Buffer     : Byte_Array (1 .. 260);
      Length     : Natural;
      Copy_Error : Errors.Error_Info;
   begin
      Writer.Put_Text (Text, Error);
      Writer.Copy_Output (Buffer, Length, Copy_Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Copy_Error.Code = Errors.No_Error);
      pragma Assert (Length = 260);
      pragma Assert
        (Buffer (1 .. 3) = Byte_Array'[16#79#, 16#01#, 16#01#]);
      for Index in Byte_Offset range 4 .. Byte_Offset (Length) loop
         pragma Assert (Buffer (Index) = 16#78#);
      end loop;
   end;

   Reset_Writer;
   Writer.Put_Bytes ([0, 255], Error);
   Assert_Output (Writer, [16#42#, 16#00#, 16#FF#]);

   Reset_Writer;
   Writer.Begin_Optional (True, Error);
   Writer.Begin_Optional (False, Error);
   Writer.End_Optional (Error);
   Writer.End_Optional (Error);
   Assert_Output (Writer, [16#82#, 16#01#, 16#81#, 16#00#]);

   Reset_Writer;
   Writer.Begin_Optional (False, Error);
   Writer.End_Optional (Error);
   Assert_Output (Writer, [16#81#, 16#00#]);

   Reset_Writer;
   Writer.Begin_Optional (True, Error);
   Writer.Put_Null (Error);
   Writer.End_Optional (Error);
   Assert_Output (Writer, [16#82#, 16#01#, 16#F6#]);

   Reset_Writer;
   Writer.Begin_Sequence (Data_Model.Known_Length (2), Error);
   Writer.Put_Boolean (False, Error);
   Writer.Put_Enumeration ("Tests.Color", "Red", Error);
   Writer.End_Sequence (Error);
   Assert_Output
     (Writer,
      [16#82#, 16#F4#, 16#63#, 16#52#, 16#65#, 16#64#]);

   Reset_Writer;
   Writer.Begin_Sequence (Data_Model.Unknown_Length, Error);
   Writer.Put_Null (Error);
   Writer.End_Sequence (Error);
   Assert_Output (Writer, [16#9F#, 16#F6#, 16#FF#]);

   Reset_Writer;
   Writer.Begin_Map (Data_Model.Unknown_Length, Error);
   Writer.Put_Text ("key", Error);
   Writer.Put_Bytes ([1 => 16#AA#], Error);
   Writer.End_Map (Error);
   Assert_Output
     (Writer,
      [16#BF#,
       16#63#,
       16#6B#,
       16#65#,
       16#79#,
       16#41#,
       16#AA#,
       16#FF#]);

   Reset_Writer;
   Writer.Begin_Map (Data_Model.Known_Length (2), Error);
   Writer.Put_Unsigned (1, Error);
   Writer.Put_Text ("one", Error);
   Writer.Put_Unsigned (2, Error);
   Writer.Put_Text ("two", Error);
   Writer.End_Map (Error);
   Assert_Output
     (Writer,
      [16#A2#,
       16#01#,
       16#63#,
       16#6F#,
       16#6E#,
       16#65#,
       16#02#,
       16#63#,
       16#74#,
       16#77#,
       16#6F#]);

   Reset_Writer;
   Writer.Begin_Record ("Tests.Sample", 1, Error);
   Writer.Put_Field ("id", Error);
   Writer.Put_Unsigned (42, Error);
   Writer.End_Record (Error);
   Assert_Output
     (Writer, [16#A1#, 16#62#, 16#69#, 16#64#, 16#18#, 16#2A#]);

   Reset_Writer;
   Writer.Begin_Variant ("Tests.Shape", "Circle", 1, Error);
   Writer.Put_Field ("r", Error);
   Writer.Put_Signed (3, Error);
   Writer.End_Variant (Error);
   Assert_Output
     (Writer,
      [16#82#,
       16#66#,
       16#43#,
       16#69#,
       16#72#,
       16#63#,
       16#6C#,
       16#65#,
       16#A1#,
       16#61#,
       16#72#,
       16#03#]);

   Reset_Writer;
   Writer.Begin_Sequence (Data_Model.Known_Length (1), Error);
   Writer.End_Sequence (Error);
   pragma Assert (Error.Code = Errors.Invalid_State);
   pragma Assert (not Writer.Is_Complete);

   Reset_Writer;
   Writer.Put_Null (Error);
   Writer.Put_Null (Error);
   pragma Assert (Error.Code = Errors.Invalid_State);
   pragma Assert (not Writer.Is_Complete);

   Reset_Writer;
   Writer.Begin_Map (Data_Model.Unknown_Length, Error);
   Writer.Put_Unsigned (1, Error);
   Writer.End_Map (Error);
   pragma Assert (Error.Code = Errors.Invalid_State);
   pragma Assert (not Writer.Is_Complete);

   Reset_Writer;
   Writer.Put_Text (String'[1 => Character'Val (16#C3#)], Error);
   pragma Assert (Error.Code = Errors.Invalid_Text);
   pragma Assert (not Writer.Is_Complete);

   Reset_Writer;
   for Index in 1 .. Flyology_Serde.Policies.Maximum_Supported_Nesting loop
      Writer.Begin_Sequence (Data_Model.Unknown_Length, Error);
   end loop;
   Writer.Begin_Sequence (Data_Model.Unknown_Length, Error);
   pragma Assert (Error.Code = Errors.Depth_Exceeded);
   pragma Assert (not Writer.Is_Complete);

   Errors.Reset (Error);
   Small.Put_Unsigned (24, Error);
   pragma Assert (Error.Code = Errors.Capacity_Exceeded);
   pragma Assert (not Small.Is_Complete);
   declare
      Buffer : Byte_Array (1 .. 1);
      Length : Natural;
   begin
      Errors.Reset (Error);
      Small.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.Invalid_State);
      pragma Assert (Length = 0);
   end;

   Errors.Reset (Error);
   Small.Reset;
   Small.Put_Text ("a", Error);
   pragma Assert (Error.Code = Errors.Capacity_Exceeded);
   pragma Assert (Small.Written_Length = 1);
   pragma Assert (not Small.Is_Complete);
   declare
      Buffer : Byte_Array (1 .. 1);
      Length : Natural;
   begin
      Errors.Reset (Error);
      Small.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.Invalid_State);
      pragma Assert (Length = 0);
   end;

   Errors.Reset (Error);
   Small.Reset;
   Small.Put_Null (Error);
   pragma Assert (Error.Code = Errors.No_Error);
   pragma Assert (Small.Is_Complete);
   Assert_Output (Small, [1 => 16#F6#]);

   Errors.Reset (Error);
   Dynamic.Begin_Sequence (Data_Model.Known_Length (1), Error);
   Dynamic.End_Sequence (Error);
   pragma Assert (Error.Code = Errors.Invalid_State);
   pragma Assert (not Dynamic.Is_Complete);
   declare
      Partial : constant Byte_Array := Dynamic.Output;
   begin
      pragma Assert (Partial'Length = 0);
   end;

   Errors.Reset (Error);
   Dynamic.Reset;
   Dynamic.Begin_Sequence (Data_Model.Unknown_Length, Error);
   Dynamic.Put_Boolean (False, Error);
   Dynamic.Put_Null (Error);
   Dynamic.End_Sequence (Error);
   pragma Assert (Error.Code = Errors.No_Error);
   pragma Assert (Dynamic.Is_Complete);
   pragma Assert (Dynamic.Output = Byte_Array'[16#9F#, 16#F4#, 16#F6#, 16#FF#]);
end CBOR_Writer_Tests;
