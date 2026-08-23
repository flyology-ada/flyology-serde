with Ada.Streams;
with Ada.Unchecked_Conversion;
with Flyology_Serde.Data_Model;
with Flyology_Serde.Deserializers.CBOR;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;
with Interfaces;

procedure CBOR_Reader_Tests is
   package CBOR renames Flyology_Serde.Deserializers.CBOR;
   package Data_Model renames Flyology_Serde.Data_Model;
   package Errors renames Flyology_Serde.Errors;
   package Policies renames Flyology_Serde.Policies;
   use type Ada.Streams.Stream_Element_Array;
   use type Data_Model.Float_64_Category;
   use type Data_Model.Format_Capabilities;
   use type Data_Model.Length_Information;
   use type Data_Model.Value_Kind;
   use type Errors.Error_Code;
   use type Errors.Input_Offset_Unit;
   use type Interfaces.IEEE_Float_64;
   use type Interfaces.Integer_64;
   use type Interfaces.Unsigned_64;

   subtype Bytes is Ada.Streams.Stream_Element_Array;

   function Float_Bits is new Ada.Unchecked_Conversion
     (Interfaces.IEEE_Float_64, Interfaces.Unsigned_64);

   procedure Finish
     (Item : in out CBOR.Reader; Error : in out Errors.Error_Info) is
   begin
      Item.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Item.Is_Complete);
      pragma Assert (Item.Input_Offset = Item.Source'Length);
   end Finish;
begin
   declare
      Input : aliased constant Bytes :=
        [16#1B#,
         16#FF#,
         16#FF#,
         16#FF#,
         16#FF#,
         16#FF#,
         16#FF#,
         16#FF#,
         16#FF#];
      Item  : CBOR.Reader (Input'Access);
      Error : Errors.Error_Info;
      Value : Interfaces.Unsigned_64;
   begin
      Item.Initialize;
      pragma Assert (Item.Capabilities = Data_Model.All_Capabilities);
      pragma Assert (Item.Peek_Kind (Error) = Data_Model.Unsigned_Integer_Value);
      Item.Read_Unsigned (Value, Error);
      pragma Assert (Value = Interfaces.Unsigned_64'Last);
      Finish (Item, Error);
   end;

   declare
      Input : aliased constant Bytes :=
        [16#3B#,
         16#7F#,
         16#FF#,
         16#FF#,
         16#FF#,
         16#FF#,
         16#FF#,
         16#FF#,
         16#FF#];
      Item  : CBOR.Reader (Input'Access);
      Error : Errors.Error_Info;
      Value : Interfaces.Integer_64;
   begin
      Item.Initialize;
      Item.Read_Signed (Value, Error);
      pragma Assert (Value = Interfaces.Integer_64'First);
      Finish (Item, Error);
   end;

   declare
      Input : aliased constant Bytes := [16#18#, 16#01#];
      Item  : CBOR.Reader (Input'Access);
      Error : Errors.Error_Info;
      Value : Interfaces.Integer_64;
   begin
      Item.Initialize;
      Item.Read_Signed (Value, Error);
      pragma Assert (Value = 1);
      Finish (Item, Error);
   end;

   declare
      Input : aliased constant Bytes := [16#F9#, 16#3E#, 16#00#];
      Item  : CBOR.Reader (Input'Access);
      Error : Errors.Error_Info;
      Value : Data_Model.Float_64_Value;
   begin
      Item.Initialize;
      Item.Read_Float_64 (Value, Error);
      pragma Assert (Data_Model.Category (Value) = Data_Model.Finite_Float);
      pragma Assert (Data_Model.Finite_Value (Value) = 1.5);
      Finish (Item, Error);
   end;

   declare
      Input : aliased constant Bytes :=
        [16#FA#, 16#3F#, 16#C0#, 16#00#, 16#00#];
      Item  : CBOR.Reader (Input'Access);
      Error : Errors.Error_Info;
      Value : Data_Model.Float_64_Value;
   begin
      Item.Initialize;
      Item.Read_Float_64 (Value, Error);
      pragma Assert (Data_Model.Finite_Value (Value) = 1.5);
      Finish (Item, Error);
   end;

   declare
      Input : aliased constant Bytes := [16#F9#, 16#00#, 16#01#];
      Item  : CBOR.Reader (Input'Access);
      Error : Errors.Error_Info;
      Value : Data_Model.Float_64_Value;
   begin
      Item.Initialize;
      Item.Read_Float_64 (Value, Error);
      pragma Assert
        (Float_Bits (Data_Model.Finite_Value (Value))
         = 16#3E70_0000_0000_0000#);
      Finish (Item, Error);
   end;

   declare
      Input : aliased constant Bytes := [16#FA#, 0, 0, 0, 1];
      Item  : CBOR.Reader (Input'Access);
      Error : Errors.Error_Info;
      Value : Data_Model.Float_64_Value;
   begin
      Item.Initialize;
      Item.Read_Float_64 (Value, Error);
      pragma Assert
        (Float_Bits (Data_Model.Finite_Value (Value))
         = 16#36A0_0000_0000_0000#);
      Finish (Item, Error);
   end;

   declare
      Input : aliased constant Bytes :=
        [16#FB#, 16#80#, 0, 0, 0, 0, 0, 0, 0];
      Item  : CBOR.Reader (Input'Access);
      Error : Errors.Error_Info;
      Value : Data_Model.Float_64_Value;
   begin
      Item.Initialize;
      Item.Read_Float_64 (Value, Error);
      pragma Assert
        (Float_Bits (Data_Model.Finite_Value (Value)) = 16#8000_0000_0000_0000#);
      Finish (Item, Error);
   end;

   for Kind in Data_Model.Positive_Infinity .. Data_Model.Not_A_Number loop
      declare
         Input : aliased constant Bytes :=
           (case Kind is
               when Data_Model.Positive_Infinity =>
                 [16#F9#, 16#7C#, 16#00#],
               when Data_Model.Negative_Infinity =>
                 [16#F9#, 16#FC#, 16#00#],
               when Data_Model.Not_A_Number =>
                 [16#F9#, 16#7E#, 16#01#]);
         Item  : CBOR.Reader (Input'Access);
         Error : Errors.Error_Info;
         Value : Data_Model.Float_64_Value;
      begin
         Item.Initialize;
         Item.Read_Float_64 (Value, Error);
         pragma Assert (Data_Model.Category (Value) = Kind);
         Finish (Item, Error);
      end;
   end loop;

   declare
      Input : aliased constant Bytes := [16#62#, 16#C3#, 16#A9#];
      Item  : CBOR.Reader (Input'Access);
      Error : Errors.Error_Info;
      Value : String (1 .. 4);
      Length : Natural;
   begin
      Item.Initialize;
      Item.Read_Text (Value, Length, Error);
      pragma Assert (Length = 2);
      pragma Assert
        (Value (1 .. Length)
         = Character'Val (16#C3#) & Character'Val (16#A9#));
      Finish (Item, Error);
   end;

   declare
      Input : aliased constant Bytes :=
        [16#7F#, 16#62#, 16#C3#, 16#A9#, 16#61#, 16#78#, 16#FF#];
      Item  : CBOR.Reader (Input'Access);
      Error : Errors.Error_Info;
      Value : String (1 .. 4);
      Length : Natural;
   begin
      Item.Initialize;
      Item.Read_Text (Value, Length, Error);
      pragma Assert (Length = 3);
      Finish (Item, Error);
   end;

   declare
      Input : aliased constant Bytes :=
        [16#5F#, 16#42#, 0, 1, 16#41#, 2, 16#FF#];
      Item  : CBOR.Reader (Input'Access);
      Error : Errors.Error_Info;
      Value : Bytes (1 .. 4);
      Length : Natural;
   begin
      Item.Initialize;
      Item.Read_Bytes (Value, Length, Error);
      pragma Assert (Length = 3);
      pragma Assert (Value (1 .. 3) = Bytes'[0, 1, 2]);
      Finish (Item, Error);
   end;

   declare
      Input    : aliased constant Bytes := [16#82#, 16#F4#, 16#F6#];
      Item     : CBOR.Reader (Input'Access);
      Error    : Errors.Error_Info;
      Length   : Data_Model.Length_Information;
      Available : Boolean;
      Flag     : Boolean;
   begin
      Item.Initialize;
      Item.Begin_Sequence (Length, Error);
      pragma Assert (Length = Data_Model.Known_Length (2));
      Item.Next_Element (Available, Error);
      pragma Assert (Available);
      Item.Read_Boolean (Flag, Error);
      pragma Assert (not Flag);
      Item.Next_Element (Available, Error);
      pragma Assert (Available);
      Item.Read_Null (Error);
      Item.Next_Element (Available, Error);
      pragma Assert (not Available);
      Item.End_Sequence (Error);
      Finish (Item, Error);
   end;

   declare
      Input     : aliased constant Bytes := [16#9F#, 1, 2, 16#FF#];
      Item      : CBOR.Reader (Input'Access);
      Error     : Errors.Error_Info;
      Length    : Data_Model.Length_Information;
      Available : Boolean;
      Value     : Interfaces.Unsigned_64;
   begin
      Item.Initialize;
      Item.Begin_Sequence (Length, Error);
      pragma Assert (not Length.Known);
      for Expected in Interfaces.Unsigned_64 range 1 .. 2 loop
         Item.Next_Element (Available, Error);
         pragma Assert (Available);
         Item.Read_Unsigned (Value, Error);
         pragma Assert (Value = Expected);
      end loop;
      Item.Next_Element (Available, Error);
      pragma Assert (not Available);
      Item.End_Sequence (Error);
      Finish (Item, Error);
   end;

   declare
      Input     : aliased constant Bytes := [16#A1#, 1, 16#61#, 16#61#];
      Item      : CBOR.Reader (Input'Access);
      Error     : Errors.Error_Info;
      Length    : Data_Model.Length_Information;
      Available : Boolean;
      Key       : Interfaces.Unsigned_64;
      Text      : String (1 .. 1);
      Text_Len  : Natural;
   begin
      Item.Initialize;
      Item.Begin_Map (Length, Error);
      Item.Next_Map_Entry (Available, Error);
      pragma Assert (Available);
      Item.Read_Unsigned (Key, Error);
      Item.Read_Text (Text, Text_Len, Error);
      Item.Next_Map_Entry (Available, Error);
      pragma Assert (not Available);
      Item.End_Map (Error);
      Finish (Item, Error);
   end;

   declare
      Input     : aliased constant Bytes :=
        [16#A1#, 16#62#, 16#69#, 16#64#, 16#18#, 16#2A#];
      Item      : CBOR.Reader (Input'Access);
      Error     : Errors.Error_Info;
      Length    : Data_Model.Length_Information;
      Available : Boolean;
      Name      : String (1 .. 8);
      Name_Len  : Natural;
      Value     : Interfaces.Unsigned_64;
   begin
      Item.Initialize;
      Item.Begin_Record ("Tests.Sample", Length, Error);
      Item.Next_Field (Name, Name_Len, Available, Error);
      pragma Assert (Available and then Name (1 .. Name_Len) = "id");
      Item.Read_Unsigned (Value, Error);
      pragma Assert (Value = 42);
      Item.Next_Field (Name, Name_Len, Available, Error);
      pragma Assert (not Available);
      Item.End_Record (Error);
      Finish (Item, Error);
   end;

   declare
      Input     : aliased constant Bytes :=
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
         3];
      Item      : CBOR.Reader (Input'Access);
      Error     : Errors.Error_Info;
      Length    : Data_Model.Length_Information;
      Available : Boolean;
      Alt       : String (1 .. 8);
      Alt_Len   : Natural;
      Name      : String (1 .. 4);
      Name_Len  : Natural;
      Value     : Interfaces.Integer_64;
   begin
      Item.Initialize;
      Item.Begin_Variant ("Tests.Shape", Alt, Alt_Len, Length, Error);
      pragma Assert (Alt (1 .. Alt_Len) = "Circle");
      Item.Next_Field (Name, Name_Len, Available, Error);
      pragma Assert (Available and then Name (1 .. Name_Len) = "r");
      Item.Read_Signed (Value, Error);
      Item.Next_Field (Name, Name_Len, Available, Error);
      pragma Assert (not Available);
      Item.End_Variant (Error);
      Finish (Item, Error);
   end;

   declare
      Input   : aliased constant Bytes := [16#82#, 1, 16#F6#];
      Item    : CBOR.Reader (Input'Access);
      Error   : Errors.Error_Info;
      Present : Boolean;
   begin
      Item.Initialize;
      Item.Begin_Optional (Present, Error);
      pragma Assert (Present);
      Item.Read_Null (Error);
      Item.End_Optional (Error);
      Finish (Item, Error);
   end;

   declare
      Input : aliased constant Bytes :=
        [16#D9#, 16#D9#, 16#F7#, 16#F6#];
      Item  : CBOR.Reader (Input'Access);
      Error : Errors.Error_Info;
   begin
      Item.Initialize;
      Item.Read_Null (Error);
      pragma Assert (Error.Code = Errors.Unsupported_Value);
      pragma Assert (Error.Input_Offset = 0);
      pragma Assert (Error.Offset_Unit = Errors.Byte_Offset);
      Errors.Reset (Error);
      Item.Reset;
      Item.Skip_Value (Error);
      Finish (Item, Error);
   end;

   declare
      Input : aliased constant Bytes := [16#7F#, 16#61#, 16#C3#, 16#61#, 16#A9#, 16#FF#];
      Item  : CBOR.Reader (Input'Access);
      Error : Errors.Error_Info;
      Value : String (1 .. 4);
      Length : Natural;
   begin
      Item.Initialize;
      Item.Read_Text (Value, Length, Error);
      pragma Assert (Error.Code = Errors.Invalid_Text);
      pragma Assert (not Item.Is_Complete);
   end;

   declare
      Input  : aliased constant Bytes := [16#F8#, 16#1F#];
      Item   : CBOR.Reader (Input'Access);
      Error  : Errors.Error_Info;
   begin
      Item.Initialize;
      Item.Skip_Value (Error);
      pragma Assert (Error.Code = Errors.Syntax_Error);
   end;

   declare
      Input : aliased constant Bytes := [16#FF#];
      Item  : CBOR.Reader (Input'Access);
      Error : Errors.Error_Info;
      Value : Interfaces.Integer_64;
   begin
      Item.Initialize;
      Item.Read_Signed (Value, Error);
      pragma Assert (Error.Code = Errors.Syntax_Error);
   end;

   declare
      Input  : aliased constant Bytes := [16#FF#];
      Item   : CBOR.Reader (Input'Access);
      Error  : Errors.Error_Info;
      Value  : String (1 .. 1);
      Length : Natural;
   begin
      Item.Initialize;
      Item.Read_Text (Value, Length, Error);
      pragma Assert (Error.Code = Errors.Syntax_Error);
   end;

   declare
      Input : aliased constant Bytes := [16#E0#];
      Item  : CBOR.Reader (Input'Access);
      Error : Errors.Error_Info;
   begin
      Item.Initialize;
      pragma Assert (Item.Peek_Kind (Error) = Data_Model.Null_Value);
      pragma Assert (Error.Code = Errors.Unsupported_Value);
      Errors.Reset (Error);
      Item.Reset;
      Item.Read_Null (Error);
      pragma Assert (Error.Code = Errors.Unsupported_Value);
   end;

   declare
      Input     : aliased constant Bytes := [16#BF#, 1, 16#FF#];
      Item      : CBOR.Reader (Input'Access);
      Error     : Errors.Error_Info;
      Length    : Data_Model.Length_Information;
      Available : Boolean;
      Key       : Interfaces.Unsigned_64;
   begin
      Item.Initialize;
      Item.Begin_Map (Length, Error);
      Item.Next_Map_Entry (Available, Error);
      Item.Read_Unsigned (Key, Error);
      Item.Read_Null (Error);
      pragma Assert (Error.Code = Errors.Syntax_Error);
   end;

   declare
      Input     : aliased constant Bytes := [16#81#];
      Item      : CBOR.Reader (Input'Access);
      Error     : Errors.Error_Info;
      Length    : Data_Model.Length_Information;
      Available : Boolean;
   begin
      Item.Initialize;
      Item.Begin_Sequence (Length, Error);
      Item.Next_Element (Available, Error);
      pragma Assert (not Available);
      pragma Assert (Error.Code = Errors.Syntax_Error);
   end;

   declare
      Input     : aliased constant Bytes := [16#81#, 16#FF#];
      Item      : CBOR.Reader (Input'Access);
      Error     : Errors.Error_Info;
      Length    : Data_Model.Length_Information;
      Available : Boolean;
   begin
      Item.Initialize;
      Item.Begin_Sequence (Length, Error);
      Item.Next_Element (Available, Error);
      pragma Assert (not Available);
      pragma Assert (Error.Code = Errors.Syntax_Error);
   end;

   declare
      Input     : aliased constant Bytes := [16#A1#];
      Item      : CBOR.Reader (Input'Access);
      Error     : Errors.Error_Info;
      Length    : Data_Model.Length_Information;
      Available : Boolean;
   begin
      Item.Initialize;
      Item.Begin_Map (Length, Error);
      Item.Next_Map_Entry (Available, Error);
      pragma Assert (not Available);
      pragma Assert (Error.Code = Errors.Syntax_Error);
   end;

   declare
      Input     : aliased constant Bytes := [16#A1#, 0];
      Item      : CBOR.Reader (Input'Access);
      Error     : Errors.Error_Info;
      Length    : Data_Model.Length_Information;
      Available : Boolean;
      Key       : Interfaces.Unsigned_64;
   begin
      Item.Initialize;
      Item.Begin_Map (Length, Error);
      Item.Next_Map_Entry (Available, Error);
      pragma Assert (Available);
      Item.Read_Unsigned (Key, Error);
      pragma Assert (Error.Code = Errors.Syntax_Error);
   end;

   declare
      Input     : aliased constant Bytes := [16#A1#, 16#61#, 16#6B#];
      Item      : CBOR.Reader (Input'Access);
      Error     : Errors.Error_Info;
      Length    : Data_Model.Length_Information;
      Available : Boolean;
      Name      : String (1 .. 1);
      Name_Len  : Natural;
   begin
      Item.Initialize;
      Item.Begin_Record ("Tests.Record", Length, Error);
      Item.Next_Field (Name, Name_Len, Available, Error);
      pragma Assert (not Available);
      pragma Assert (Error.Code = Errors.Syntax_Error);
   end;

   declare
      Input     : aliased constant Bytes := [16#A1#, 16#FF#];
      Item      : CBOR.Reader (Input'Access);
      Error     : Errors.Error_Info;
      Length    : Data_Model.Length_Information;
      Available : Boolean;
      Name      : String (1 .. 1);
      Name_Len  : Natural;
   begin
      Item.Initialize;
      Item.Begin_Record ("Tests.Record", Length, Error);
      Item.Next_Field (Name, Name_Len, Available, Error);
      pragma Assert (not Available);
      pragma Assert (Error.Code = Errors.Syntax_Error);
   end;

   declare
      Input  : aliased constant Bytes := [16#C0#, 16#C0#, 16#F6#];
      Item   : CBOR.Reader (Input'Access);
      Error  : Errors.Error_Info;
      Policy : Policies.Decode_Policy := (others => <>);
   begin
      Policy.Limits.Maximum_Nesting_Depth := 1;
      Item.Initialize (Policy);
      Item.Skip_Value (Error);
      pragma Assert (Error.Code = Errors.Depth_Exceeded);
   end;

   declare
      Input  : aliased constant Bytes := [16#F6#];
      Item   : CBOR.Reader (Input'Access);
      Error  : Errors.Error_Info;
      Policy : Policies.Decode_Policy := (others => <>);
   begin
      Policy.Limits.Maximum_Input_Units := 0;
      Item.Initialize (Policy);
      Item.Read_Null (Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
   end;

   declare
      Input  : aliased constant Bytes := [16#F6#];
      Item   : CBOR.Reader (Input'Access);
      Error  : Errors.Error_Info;
      Policy : Policies.Decode_Policy := (others => <>);
   begin
      Policy.Limits.Maximum_Logical_Values := 0;
      Item.Initialize (Policy);
      Item.Read_Null (Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
   end;

   declare
      Input  : aliased constant Bytes := [16#62#, 16#61#, 16#62#];
      Item   : CBOR.Reader (Input'Access);
      Error  : Errors.Error_Info;
      Policy : Policies.Decode_Policy := (others => <>);
      Value  : String (1 .. 2);
      Length : Natural;
   begin
      Policy.Limits.Maximum_Text_Length := 1;
      Item.Initialize (Policy);
      Item.Read_Text (Value, Length, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
   end;

   declare
      Input  : aliased constant Bytes := [16#42#, 16#00#, 16#01#];
      Item   : CBOR.Reader (Input'Access);
      Error  : Errors.Error_Info;
      Policy : Policies.Decode_Policy := (others => <>);
      Value  : Bytes (1 .. 2);
      Length : Natural;
   begin
      Policy.Limits.Maximum_Byte_Length := 1;
      Item.Initialize (Policy);
      Item.Read_Bytes (Value, Length, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
   end;

   declare
      Input  : aliased constant Bytes := [16#82#, 0, 1];
      Item   : CBOR.Reader (Input'Access);
      Error  : Errors.Error_Info;
      Policy : Policies.Decode_Policy := (others => <>);
      Length : Data_Model.Length_Information;
   begin
      Policy.Limits.Maximum_Container_Items := 1;
      Item.Initialize (Policy);
      Item.Begin_Sequence (Length, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
   end;

   declare
      Input     : aliased constant Bytes := [16#81#, 16#C0#, 16#F6#];
      Item      : CBOR.Reader (Input'Access);
      Error     : Errors.Error_Info;
      Policy    : Policies.Decode_Policy := (others => <>);
      Length    : Data_Model.Length_Information;
      Available : Boolean;
   begin
      Policy.Limits.Maximum_Nesting_Depth := 1;
      Item.Initialize (Policy);
      Item.Begin_Sequence (Length, Error);
      Item.Next_Element (Available, Error);
      Item.Skip_Value (Error);
      pragma Assert (Error.Code = Errors.Depth_Exceeded);
   end;

   declare
      Input   : aliased constant Bytes := [16#81#, 1];
      Item    : CBOR.Reader (Input'Access);
      Error   : Errors.Error_Info;
      Present : Boolean;
   begin
      Item.Initialize;
      Item.Begin_Optional (Present, Error);
      pragma Assert (Error.Code = Errors.Invalid_Value);
   end;

   declare
      Input   : aliased constant Bytes := [16#82#, 1];
      Item    : CBOR.Reader (Input'Access);
      Error   : Errors.Error_Info;
      Present : Boolean;
   begin
      Item.Initialize;
      Item.Begin_Optional (Present, Error);
      pragma Assert (not Present);
      pragma Assert (Error.Code = Errors.Syntax_Error);
   end;

   declare
      Input   : aliased constant Bytes := [16#9F#, 1];
      Item    : CBOR.Reader (Input'Access);
      Error   : Errors.Error_Info;
      Present : Boolean;
   begin
      Item.Initialize;
      Item.Begin_Optional (Present, Error);
      pragma Assert (not Present);
      pragma Assert (Error.Code = Errors.Syntax_Error);
   end;

   declare
      Input   : aliased constant Bytes := [16#81#, 16#FF#];
      Item    : CBOR.Reader (Input'Access);
      Error   : Errors.Error_Info;
      Present : Boolean;
   begin
      Item.Initialize;
      Item.Begin_Optional (Present, Error);
      pragma Assert (Error.Code = Errors.Syntax_Error);
   end;

   declare
      Input   : aliased constant Bytes := [16#9F#, 16#FF#];
      Item    : CBOR.Reader (Input'Access);
      Error   : Errors.Error_Info;
      Present : Boolean;
   begin
      Item.Initialize;
      Item.Begin_Optional (Present, Error);
      pragma Assert (Error.Code = Errors.Invalid_Value);
   end;

   declare
      Input   : aliased constant Bytes := [16#9F#, 1, 16#FF#];
      Item    : CBOR.Reader (Input'Access);
      Error   : Errors.Error_Info;
      Present : Boolean;
   begin
      Item.Initialize;
      Item.Begin_Optional (Present, Error);
      pragma Assert (not Present);
      pragma Assert (Error.Code = Errors.Invalid_Value);
   end;

   declare
      Input  : aliased constant Bytes := [16#F6#, 16#F6#];
      Item   : CBOR.Reader (Input'Access);
      Error  : Errors.Error_Info;
   begin
      Item.Initialize;
      Item.Read_Null (Error);
      Item.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.Syntax_Error);
      Errors.Reset (Error);
      Item.Reset;
      Item.Read_Null (Error);
      pragma Assert (Error.Code = Errors.No_Error);
   end;
end CBOR_Reader_Tests;
