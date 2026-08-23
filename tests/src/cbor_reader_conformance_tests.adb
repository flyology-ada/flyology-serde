with Ada.Streams;
with Ada.Unchecked_Conversion;
with Flyology_Serde.Data_Model;
with Flyology_Serde.Deserializers.CBOR;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;
with Interfaces;

procedure CBOR_Reader_Conformance_Tests is
   package CBOR renames Flyology_Serde.Deserializers.CBOR;
   package Data_Model renames Flyology_Serde.Data_Model;
   package Errors renames Flyology_Serde.Errors;
   package Policies renames Flyology_Serde.Policies;
   use type Ada.Streams.Stream_Element_Array;
   use type Data_Model.Float_64_Category;
   use type Errors.Error_Code;
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
   end Finish;
begin
   --  Duplicate generic-map keys remain distinct and retain source order.
   declare
      Input     : aliased constant Bytes := [16#A2#, 1, 10, 1, 11];
      Item      : CBOR.Reader (Input'Access);
      Error     : Errors.Error_Info;
      Length    : Data_Model.Length_Information;
      Available : Boolean;
      Key       : Interfaces.Unsigned_64;
      Value     : Interfaces.Unsigned_64;
   begin
      Item.Initialize;
      Item.Begin_Map (Length, Error);
      for Expected in Interfaces.Unsigned_64 range 10 .. 11 loop
         Item.Next_Map_Entry (Available, Error);
         pragma Assert (Available);
         Item.Read_Unsigned (Key, Error);
         Item.Read_Unsigned (Value, Error);
         pragma Assert (Key = 1 and then Value = Expected);
      end loop;
      Item.Next_Map_Entry (Available, Error);
      pragma Assert (not Available);
      Item.End_Map (Error);
      Finish (Item, Error);
   end;

   --  Definite none, indefinite none, and nested optionals are lossless.
   declare
      Input   : aliased constant Bytes := [16#81#, 0];
      Item    : CBOR.Reader (Input'Access);
      Error   : Errors.Error_Info;
      Present : Boolean;
   begin
      Item.Initialize;
      Item.Begin_Optional (Present, Error);
      pragma Assert (not Present);
      Item.End_Optional (Error);
      Finish (Item, Error);
   end;

   declare
      Input   : aliased constant Bytes := [16#9F#, 0, 16#FF#];
      Item    : CBOR.Reader (Input'Access);
      Error   : Errors.Error_Info;
      Present : Boolean;
   begin
      Item.Initialize;
      Item.Begin_Optional (Present, Error);
      pragma Assert (not Present);
      Item.End_Optional (Error);
      Finish (Item, Error);
   end;

   declare
      Input         : aliased constant Bytes := [16#82#, 1, 16#82#, 1, 16#F6#];
      Item          : CBOR.Reader (Input'Access);
      Error         : Errors.Error_Info;
      Outer_Present : Boolean;
      Inner_Present : Boolean;
   begin
      Item.Initialize;
      Item.Begin_Optional (Outer_Present, Error);
      Item.Begin_Optional (Inner_Present, Error);
      pragma Assert (Outer_Present and then Inner_Present);
      Item.Read_Null (Error);
      Item.End_Optional (Error);
      Item.End_Optional (Error);
      Finish (Item, Error);
   end;

   declare
      Input         : aliased constant Bytes :=
        [16#9F#, 1, 16#9F#, 0, 16#FF#, 16#FF#];
      Item          : CBOR.Reader (Input'Access);
      Error         : Errors.Error_Info;
      Outer_Present : Boolean;
      Inner_Present : Boolean;
   begin
      Item.Initialize;
      Item.Begin_Optional (Outer_Present, Error);
      Item.Begin_Optional (Inner_Present, Error);
      pragma Assert (Outer_Present and then not Inner_Present);
      Item.End_Optional (Error);
      Item.End_Optional (Error);
      Finish (Item, Error);
   end;

   --  Indefinite variant envelope and payload map retain exact typed structure.
   declare
      Input     : aliased constant Bytes :=
        [16#9F#, 16#61#, 16#41#, 16#BF#, 16#61#, 16#78#, 1, 16#FF#, 16#FF#];
      Item      : CBOR.Reader (Input'Access);
      Error     : Errors.Error_Info;
      Length    : Data_Model.Length_Information;
      Available : Boolean;
      Alt       : String (1 .. 1);
      Alt_Len   : Natural;
      Name      : String (1 .. 1);
      Name_Len  : Natural;
      Value     : Interfaces.Unsigned_64;
   begin
      Item.Initialize;
      Item.Begin_Variant ("Tests.Variant", Alt, Alt_Len, Length, Error);
      pragma Assert (Alt (1 .. Alt_Len) = "A" and then not Length.Known);
      Item.Next_Field (Name, Name_Len, Available, Error);
      pragma Assert (Available and then Name (1 .. Name_Len) = "x");
      Item.Read_Unsigned (Value, Error);
      Item.Next_Field (Name, Name_Len, Available, Error);
      pragma Assert (not Available);
      Item.End_Variant (Error);
      Finish (Item, Error);
   end;

   declare
      Input   : aliased constant Bytes := [16#C0#, 16#82#, 16#61#, 16#41#, 16#A0#];
      Item    : CBOR.Reader (Input'Access);
      Error   : Errors.Error_Info;
      Length  : Data_Model.Length_Information;
      Alt     : String (1 .. 1);
      Alt_Len : Natural;
   begin
      Item.Initialize;
      Item.Begin_Variant ("Tests.Variant", Alt, Alt_Len, Length, Error);
      pragma Assert (Error.Code = Errors.Unsupported_Value);
   end;

   declare
      Input   : aliased constant Bytes := [16#F6#];
      Item    : CBOR.Reader (Input'Access);
      Error   : Errors.Error_Info;
      Length  : Data_Model.Length_Information;
      Alt     : String (1 .. 1);
      Alt_Len : Natural;
   begin
      Item.Initialize;
      Item.Begin_Variant ("Tests.Variant", Alt, Alt_Len, Length, Error);
      pragma Assert (Error.Code = Errors.Unexpected_Kind);
   end;

   declare
      Input   : aliased constant Bytes :=
        [16#82#, 16#C0#, 16#61#, 16#41#, 16#A0#];
      Item    : CBOR.Reader (Input'Access);
      Error   : Errors.Error_Info;
      Length  : Data_Model.Length_Information;
      Alt     : String (1 .. 1);
      Alt_Len : Natural;
   begin
      Item.Initialize;
      Item.Begin_Variant ("Tests.Variant", Alt, Alt_Len, Length, Error);
      pragma Assert (Error.Code = Errors.Unsupported_Value);
   end;

   declare
      Input   : aliased constant Bytes :=
        [16#82#, 16#61#, 16#41#, 16#C0#, 16#A0#];
      Item    : CBOR.Reader (Input'Access);
      Error   : Errors.Error_Info;
      Length  : Data_Model.Length_Information;
      Alt     : String (1 .. 1);
      Alt_Len : Natural;
   begin
      Item.Initialize;
      Item.Begin_Variant ("Tests.Variant", Alt, Alt_Len, Length, Error);
      pragma Assert (Error.Code = Errors.Unsupported_Value);
   end;

   declare
      Input   : aliased constant Bytes := [16#82#, 0, 16#A0#];
      Item    : CBOR.Reader (Input'Access);
      Error   : Errors.Error_Info;
      Length  : Data_Model.Length_Information;
      Alt     : String (1 .. 1);
      Alt_Len : Natural;
   begin
      Item.Initialize;
      Item.Begin_Variant ("Tests.Variant", Alt, Alt_Len, Length, Error);
      pragma Assert (Error.Code = Errors.Invalid_Value);
   end;

   declare
      Input   : aliased constant Bytes := [16#81#, 16#61#, 16#41#];
      Item    : CBOR.Reader (Input'Access);
      Error   : Errors.Error_Info;
      Length  : Data_Model.Length_Information;
      Alt     : String (1 .. 1);
      Alt_Len : Natural;
   begin
      Item.Initialize;
      Item.Begin_Variant ("Tests.Variant", Alt, Alt_Len, Length, Error);
      pragma Assert (Error.Code = Errors.Invalid_Value);
   end;

   declare
      Input   : aliased constant Bytes := [16#82#, 16#61#, 16#41#, 16#80#];
      Item    : CBOR.Reader (Input'Access);
      Error   : Errors.Error_Info;
      Length  : Data_Model.Length_Information;
      Alt     : String (1 .. 1);
      Alt_Len : Natural;
   begin
      Item.Initialize;
      Item.Begin_Variant ("Tests.Variant", Alt, Alt_Len, Length, Error);
      pragma Assert (Error.Code = Errors.Invalid_Value);
   end;

   declare
      Input     : aliased constant Bytes :=
        [16#9F#, 16#61#, 16#41#, 16#A0#, 16#F6#, 16#FF#];
      Item      : CBOR.Reader (Input'Access);
      Error     : Errors.Error_Info;
      Length    : Data_Model.Length_Information;
      Available : Boolean;
      Alt       : String (1 .. 1);
      Alt_Len   : Natural;
      Name      : String (1 .. 1);
      Name_Len  : Natural;
   begin
      Item.Initialize;
      Item.Begin_Variant ("Tests.Variant", Alt, Alt_Len, Length, Error);
      Item.Next_Field (Name, Name_Len, Available, Error);
      pragma Assert (not Available);
      Item.End_Variant (Error);
      pragma Assert (Error.Code = Errors.Invalid_Value);
   end;

   --  Nonpreferred length widths remain accepted.
   declare
      Input  : aliased constant Bytes := [16#78#, 1, 16#61#];
      Item   : CBOR.Reader (Input'Access);
      Error  : Errors.Error_Info;
      Value  : String (1 .. 1);
      Length : Natural;
   begin
      Item.Initialize;
      Item.Read_Text (Value, Length, Error);
      pragma Assert (Value = "a" and then Length = 1);
      Finish (Item, Error);
   end;

   declare
      Input     : aliased constant Bytes := [16#98#, 1, 16#F6#];
      Item      : CBOR.Reader (Input'Access);
      Error     : Errors.Error_Info;
      Length    : Data_Model.Length_Information;
      Available : Boolean;
   begin
      Item.Initialize;
      Item.Begin_Sequence (Length, Error);
      Item.Next_Element (Available, Error);
      Item.Read_Null (Error);
      Item.Next_Element (Available, Error);
      Item.End_Sequence (Error);
      Finish (Item, Error);
   end;

   --  Structural U64 lengths are rejected before narrowing.
   declare
      Input  : aliased constant Bytes :=
        [16#5B#, 16#FF#, 16#FF#, 16#FF#, 16#FF#,
         16#FF#, 16#FF#, 16#FF#, 16#FF#];
      Item   : CBOR.Reader (Input'Access);
      Error  : Errors.Error_Info;
      Value  : Bytes (1 .. 1);
      Length : Natural;
   begin
      Item.Initialize;
      Item.Read_Bytes (Value, Length, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
   end;

   declare
      Input  : aliased constant Bytes :=
        [16#9B#, 16#FF#, 16#FF#, 16#FF#, 16#FF#,
         16#FF#, 16#FF#, 16#FF#, 16#FF#];
      Item   : CBOR.Reader (Input'Access);
      Error  : Errors.Error_Info;
      Length : Data_Model.Length_Information;
   begin
      Item.Initialize;
      Item.Begin_Sequence (Length, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
   end;

   --  Empty chunks are legal; mixed and recursively indefinite chunks are not.
   declare
      Input  : aliased constant Bytes :=
        [16#7F#, 16#60#, 16#61#, 16#61#, 16#60#, 16#FF#];
      Item   : CBOR.Reader (Input'Access);
      Error  : Errors.Error_Info;
      Value  : String (1 .. 1);
      Length : Natural;
   begin
      Item.Initialize;
      Item.Read_Text (Value, Length, Error);
      pragma Assert (Value = "a" and then Length = 1);
      Finish (Item, Error);
   end;

   declare
      Input  : aliased constant Bytes := [16#5F#, 16#40#, 16#41#, 1, 16#FF#];
      Item   : CBOR.Reader (Input'Access);
      Error  : Errors.Error_Info;
      Value  : Bytes (1 .. 1);
      Length : Natural;
   begin
      Item.Initialize;
      Item.Read_Bytes (Value, Length, Error);
      pragma Assert (Value = Bytes'[1] and then Length = 1);
      Finish (Item, Error);
   end;

   declare
      Input  : aliased constant Bytes := [16#7F#, 16#41#, 16#61#, 16#FF#];
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
      Input  : aliased constant Bytes := [16#7F#, 16#7F#, 16#FF#, 16#FF#];
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
      Input  : aliased constant Bytes := [16#7F#, 16#60#, 16#60#, 16#FF#];
      Item   : CBOR.Reader (Input'Access);
      Error  : Errors.Error_Info;
      Policy : Policies.Decode_Policy := (others => <>);
      Value  : String (1 .. 1);
      Length : Natural;
   begin
      Policy.Limits.Maximum_Container_Items := 1;
      Item.Initialize (Policy);
      Item.Read_Text (Value, Length, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
   end;

   declare
      Input  : aliased constant Bytes := [16#62#, 16#61#, 16#62#];
      Item   : CBOR.Reader (Input'Access);
      Error  : Errors.Error_Info;
      Value  : String (1 .. 1);
      Length : Natural;
   begin
      Item.Initialize;
      Item.Read_Text (Value, Length, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
   end;

   declare
      Input  : aliased constant Bytes := [16#42#, 0, 1];
      Item   : CBOR.Reader (Input'Access);
      Error  : Errors.Error_Info;
      Value  : Bytes (1 .. 1);
      Length : Natural;
   begin
      Item.Initialize;
      Item.Read_Bytes (Value, Length, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
   end;

   --  Reserved additional information and truncation fail as syntax.
   declare
      Input : aliased constant Bytes := [16#1C#];
      Item  : CBOR.Reader (Input'Access);
      Error : Errors.Error_Info;
      Value : Interfaces.Unsigned_64;
   begin
      Item.Initialize;
      Item.Read_Unsigned (Value, Error);
      pragma Assert (Error.Code = Errors.Syntax_Error);
   end;

   declare
      Input : aliased constant Bytes := [16#1D#];
      Item  : CBOR.Reader (Input'Access);
      Error : Errors.Error_Info;
   begin
      Item.Initialize;
      Item.Skip_Value (Error);
      pragma Assert (Error.Code = Errors.Syntax_Error);
   end;

   declare
      Input : aliased constant Bytes := [16#1E#];
      Item  : CBOR.Reader (Input'Access);
      Error : Errors.Error_Info;
   begin
      Item.Initialize;
      Item.Skip_Value (Error);
      pragma Assert (Error.Code = Errors.Syntax_Error);
   end;

   declare
      Input : aliased constant Bytes := [16#1A#, 0];
      Item  : CBOR.Reader (Input'Access);
      Error : Errors.Error_Info;
      Value : Interfaces.Unsigned_64;
   begin
      Item.Initialize;
      Item.Read_Unsigned (Value, Error);
      pragma Assert (Error.Code = Errors.Syntax_Error);
   end;

   declare
      Input  : aliased constant Bytes := [16#62#, 16#61#];
      Item   : CBOR.Reader (Input'Access);
      Error  : Errors.Error_Info;
      Value  : String (1 .. 2);
      Length : Natural;
   begin
      Item.Initialize;
      Item.Read_Text (Value, Length, Error);
      pragma Assert (Error.Code = Errors.Syntax_Error);
   end;

   declare
      Input  : aliased constant Bytes := [16#7F#, 16#78#];
      Item   : CBOR.Reader (Input'Access);
      Error  : Errors.Error_Info;
      Value  : String (1 .. 1);
      Length : Natural;
   begin
      Item.Initialize;
      Item.Read_Text (Value, Length, Error);
      pragma Assert (Error.Code = Errors.Syntax_Error);
   end;

   --  Shorter float widths preserve both zeros; all widths classify nonfinite values.
   declare
      Input : aliased constant Bytes := [16#F9#, 0, 0];
      Item  : CBOR.Reader (Input'Access);
      Error : Errors.Error_Info;
      Value : Data_Model.Float_64_Value;
   begin
      Item.Initialize;
      Item.Read_Float_64 (Value, Error);
      pragma Assert (Float_Bits (Data_Model.Finite_Value (Value)) = 0);
      Finish (Item, Error);
   end;

   declare
      Input : aliased constant Bytes := [16#F9#, 16#80#, 0];
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

   declare
      Input : aliased constant Bytes := [16#FA#, 16#80#, 0, 0, 0];
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

   for Width_Index in 1 .. 2 loop
      for Expected in Data_Model.Positive_Infinity .. Data_Model.Not_A_Number loop
         declare
            Width : constant Natural := (if Width_Index = 1 then 32 else 64);
            Input : aliased constant Bytes :=
              (case Width is
                  when 32 =>
                    (case Expected is
                        when Data_Model.Positive_Infinity => [16#FA#, 16#7F#, 16#80#, 0, 0],
                        when Data_Model.Negative_Infinity => [16#FA#, 16#FF#, 16#80#, 0, 0],
                        when Data_Model.Not_A_Number => [16#FA#, 16#7F#, 16#C0#, 0, 1]),
                  when 64 =>
                    (case Expected is
                        when Data_Model.Positive_Infinity =>
                          [16#FB#, 16#7F#, 16#F0#, 0, 0, 0, 0, 0, 0],
                        when Data_Model.Negative_Infinity =>
                          [16#FB#, 16#FF#, 16#F0#, 0, 0, 0, 0, 0, 0],
                        when Data_Model.Not_A_Number =>
                          [16#FB#, 16#7F#, 16#F8#, 0, 0, 0, 0, 0, 1]),
                  when others => raise Program_Error);
            Item  : CBOR.Reader (Input'Access);
            Error : Errors.Error_Info;
            Value : Data_Model.Float_64_Value;
         begin
            Item.Initialize;
            Item.Read_Float_64 (Value, Error);
            pragma Assert (Data_Model.Category (Value) = Expected);
            Finish (Item, Error);
         end;
      end loop;
   end loop;

   --  Signed reads accept both endpoints and reject either adjacent U64 argument.
   declare
      Input : aliased constant Bytes :=
        [16#1B#, 16#7F#, 16#FF#, 16#FF#, 16#FF#,
         16#FF#, 16#FF#, 16#FF#, 16#FF#];
      Item  : CBOR.Reader (Input'Access);
      Error : Errors.Error_Info;
      Value : Interfaces.Integer_64;
   begin
      Item.Initialize;
      Item.Read_Signed (Value, Error);
      pragma Assert (Value = Interfaces.Integer_64'Last);
      Finish (Item, Error);
   end;

   declare
      Input : aliased constant Bytes :=
        [16#1B#, 16#80#, 0, 0, 0, 0, 0, 0, 0];
      Item  : CBOR.Reader (Input'Access);
      Error : Errors.Error_Info;
      Value : Interfaces.Integer_64;
   begin
      Item.Initialize;
      Item.Read_Signed (Value, Error);
      pragma Assert (Error.Code = Errors.Out_Of_Range);
   end;

   declare
      Input : aliased constant Bytes :=
        [16#3B#, 16#80#, 0, 0, 0, 0, 0, 0, 0];
      Item  : CBOR.Reader (Input'Access);
      Error : Errors.Error_Info;
      Value : Interfaces.Integer_64;
   begin
      Item.Initialize;
      Item.Read_Signed (Value, Error);
      pragma Assert (Error.Code = Errors.Out_Of_Range);
   end;

   --  Tags at every optional structural position take precedence.
   declare
      Input   : aliased constant Bytes := [16#C0#, 16#81#, 0];
      Item    : CBOR.Reader (Input'Access);
      Error   : Errors.Error_Info;
      Present : Boolean;
   begin
      Item.Initialize;
      Item.Begin_Optional (Present, Error);
      pragma Assert (Error.Code = Errors.Unsupported_Value);
   end;

   declare
      Input   : aliased constant Bytes := [16#81#, 16#C0#, 0];
      Item    : CBOR.Reader (Input'Access);
      Error   : Errors.Error_Info;
      Present : Boolean;
   begin
      Item.Initialize;
      Item.Begin_Optional (Present, Error);
      pragma Assert (Error.Code = Errors.Unsupported_Value);
   end;

   declare
      Input   : aliased constant Bytes := [16#82#, 1, 16#C0#, 16#F6#];
      Item    : CBOR.Reader (Input'Access);
      Error   : Errors.Error_Info;
      Present : Boolean;
   begin
      Item.Initialize;
      Item.Begin_Optional (Present, Error);
      pragma Assert (not Present);
      pragma Assert (Error.Code = Errors.Unsupported_Value);
   end;

   --  Raw skip and ordinary traversal enforce independent item and depth limits.
   declare
      Input  : aliased constant Bytes := [16#82#, 16#F6#, 16#F6#];
      Item   : CBOR.Reader (Input'Access);
      Error  : Errors.Error_Info;
      Policy : Policies.Decode_Policy := (others => <>);
   begin
      Policy.Limits.Maximum_Container_Items := 1;
      Item.Initialize (Policy);
      Item.Skip_Value (Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
   end;

   declare
      Input  : aliased constant Bytes := [16#7F#, 16#60#, 16#60#, 16#FF#];
      Item   : CBOR.Reader (Input'Access);
      Error  : Errors.Error_Info;
      Policy : Policies.Decode_Policy := (others => <>);
   begin
      Policy.Limits.Maximum_Container_Items := 1;
      Item.Initialize (Policy);
      Item.Skip_Value (Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
   end;

   declare
      Input     : aliased constant Bytes := [16#81#, 16#81#, 16#F6#];
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
      Item.Begin_Sequence (Length, Error);
      pragma Assert (Error.Code = Errors.Depth_Exceeded);
   end;

   --  A nested failure poisons the reader, unwinds its budget, and Reset makes it reusable.
   declare
      Input     : aliased constant Bytes := [16#81#, 16#F6#];
      Item      : CBOR.Reader (Input'Access);
      Error     : Errors.Error_Info;
      Policy    : Policies.Decode_Policy := (others => <>);
      Length    : Data_Model.Length_Information;
      Available : Boolean;
   begin
      Policy.Limits.Maximum_Logical_Values := 1;
      Item.Initialize (Policy);
      Item.Begin_Sequence (Length, Error);
      Item.Next_Element (Available, Error);
      Item.Read_Null (Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
      Errors.Reset (Error);
      Item.Read_Null (Error);
      pragma Assert (Error.Code = Errors.Invalid_State);
      Errors.Reset (Error);
      Item.Reset;
      Item.Begin_Sequence (Length, Error);
      Item.Next_Element (Available, Error);
      Item.Read_Null (Error);
      Item.Next_Element (Available, Error);
      Item.End_Sequence (Error);
      Finish (Item, Error);
   end;

   --  Offsets are zero based even when the source array is not.
   declare
      Input : aliased constant Bytes := [5 => 16#F6#];
      Item  : CBOR.Reader (Input'Access);
      Error : Errors.Error_Info;
   begin
      Item.Initialize;
      Item.Read_Null (Error);
      pragma Assert (Item.Input_Offset = 1);
      Finish (Item, Error);
   end;

   declare
      Input : aliased constant Bytes := [5 => 16#FF#];
      Item  : CBOR.Reader (Input'Access);
      Error : Errors.Error_Info;
   begin
      Item.Initialize;
      Item.Read_Null (Error);
      pragma Assert (Error.Code = Errors.Syntax_Error);
      pragma Assert (Error.Input_Offset = 0);
   end;
end CBOR_Reader_Conformance_Tests;
