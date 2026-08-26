with Ada.Streams;
with Ada.Unchecked_Conversion;
with Flyology_Serde.Data_Model;
with Flyology_Serde.Deserializers.JSON;
with Flyology_Serde.Deserializers.JSON.Testing;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;
with Interfaces;

procedure JSON_Reader_Tests is
   package Data_Model renames Flyology_Serde.Data_Model;
   package Errors renames Flyology_Serde.Errors;
   package JSON renames Flyology_Serde.Deserializers.JSON;
   package JSON_Testing renames Flyology_Serde.Deserializers.JSON.Testing;
   package Policies renames Flyology_Serde.Policies;
   use type Ada.Streams.Stream_Element;
   use type Errors.Error_Code;
   use type Errors.Input_Offset_Unit;
   use type Interfaces.IEEE_Float_64;
   use type Interfaces.Integer_64;
   use type Interfaces.Unsigned_64;
   use type Data_Model.Value_Kind;

   function Bits is new
     Ada.Unchecked_Conversion
       (Interfaces.IEEE_Float_64,
        Interfaces.Unsigned_64);

   procedure Finish
     (Item : in out JSON.Reader; Error : in out Errors.Error_Info) is
   begin
      Item.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Item.Is_Complete);
   end Finish;
begin
   JSON_Testing.Assert_JSON_Event_Contract;
   JSON_Testing.Assert_JSON_Event_Summaries;
   JSON_Testing.Assert_JSON_Driver_Lifecycle;

   --  Flyology JSON sees each source byte only after the one shared Serde
   --  budget admits it. Zero-consumption events reuse the charged window.
   declare
      Input : aliased constant String := "null";
      Item  : JSON.Reader (Input'Access);
      Error : Errors.Error_Info;
   begin
      Item.Initialize;
      pragma Assert (JSON_Testing.Syntax_Input_Offset (Item) = 0);
      pragma Assert (JSON_Testing.Budget_Input_Consumed (Item) = 0);
      Item.Read_Null (Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Item.Input_Offset = Input'Length);
      pragma Assert (JSON_Testing.Syntax_Input_Offset (Item) = Input'Length);
      pragma Assert (JSON_Testing.Budget_Input_Consumed (Item) = Input'Length);
      Finish (Item, Error);
      pragma Assert (JSON_Testing.Budget_Input_Consumed (Item) = Input'Length);
   end;

   --  The borrowed source can use any legal positive lower bound; parser
   --  coordinates and Serde offsets remain zero based.
   declare
      Input : aliased constant String :=
        [17 => 'n', 18 => 'u', 19 => 'l', 20 => 'l'];
      Item  : JSON.Reader (Input'Access);
      Error : Errors.Error_Info;
   begin
      Item.Initialize;
      Item.Read_Null (Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Item.Input_Offset = Input'Length);
      pragma Assert (JSON_Testing.Syntax_Input_Offset (Item) = Input'Length);
      Finish (Item, Error);
   end;

   declare
      Input       : aliased constant String :=
        "{""identifier"":42,""enabled"":true}";
      Item        : JSON.Reader (Input'Access);
      Error       : Errors.Error_Info;
      Length      : Flyology_Serde.Data_Model.Length_Information;
      Name        : String (1 .. 16);
      Name_Length : Natural;
      Has_Field   : Boolean;
      Identifier  : Interfaces.Unsigned_64;
      Enabled     : Boolean;
   begin
      Item.Initialize;
      Item.Begin_Record ("Tests.Sample", Length, Error);
      pragma Assert (not Length.Known);
      Item.Next_Field (Name, Name_Length, Has_Field, Error);
      pragma
        Assert (Has_Field and then Name (1 .. Name_Length) = "identifier");
      Item.Read_Unsigned (Identifier, Error);
      Item.Next_Field (Name, Name_Length, Has_Field, Error);
      pragma Assert (Has_Field and then Name (1 .. Name_Length) = "enabled");
      Item.Read_Boolean (Enabled, Error);
      Item.Next_Field (Name, Name_Length, Has_Field, Error);
      pragma Assert (not Has_Field);
      Item.End_Record (Error);
      pragma Assert (Identifier = 42 and then Enabled);
      Finish (Item, Error);
   end;

   declare
      Input   : aliased constant String := " [1, [0] ] ";
      Item    : JSON.Reader (Input'Access);
      Error   : Errors.Error_Info;
      Present : Boolean;
   begin
      Item.Initialize;
      Item.Begin_Optional (Present, Error);
      pragma Assert (Present);
      Item.Begin_Optional (Present, Error);
      pragma Assert (not Present);
      Item.End_Optional (Error);
      Item.End_Optional (Error);
      Finish (Item, Error);
   end;

   declare
      Input  : aliased constant String := " { ""$bytes"" : ""00FF"" } ";
      Item   : JSON.Reader (Input'Access);
      Error  : Errors.Error_Info;
      Value  : Ada.Streams.Stream_Element_Array (1 .. 2);
      Length : Natural;
   begin
      Item.Initialize;
      Item.Read_Bytes (Value, Length, Error);
      pragma
        Assert (Length = 2 and then Value (1) = 0 and then Value (2) = 255);
      Finish (Item, Error);
   end;

   declare
      Input     : aliased constant String := "[[1,""one""],[2,""two""]]";
      Item      : JSON.Reader (Input'Access);
      Error     : Errors.Error_Info;
      Length    : Flyology_Serde.Data_Model.Length_Information;
      Has_Entry : Boolean;
      Key       : Interfaces.Integer_64;
      Value     : String (1 .. 3);
      Count     : Natural;
   begin
      Item.Initialize;
      Item.Begin_Map (Length, Error);
      for Expected in Interfaces.Integer_64 range 1 .. 2 loop
         Item.Next_Map_Entry (Has_Entry, Error);
         pragma Assert (Has_Entry);
         Item.Read_Signed (Key, Error);
         Item.Read_Text (Value, Count, Error);
         pragma Assert (Key = Expected and then Count = 3);
      end loop;
      Item.Next_Map_Entry (Has_Entry, Error);
      pragma Assert (not Has_Entry);
      Item.End_Map (Error);
      Finish (Item, Error);
   end;

   declare
      Input       : aliased constant String :=
        "[ ""Circle"" , {""radius"":3} ]";
      Item        : JSON.Reader (Input'Access);
      Error       : Errors.Error_Info;
      Alternative : String (1 .. 16);
      Alt_Length  : Natural;
      Length      : Flyology_Serde.Data_Model.Length_Information;
      Name        : String (1 .. 16);
      Name_Length : Natural;
      Has_Field   : Boolean;
      Radius      : Interfaces.Integer_64;
   begin
      Item.Initialize;
      Item.Begin_Variant
        ("Tests.Shape", Alternative, Alt_Length, Length, Error);
      pragma Assert (Alternative (1 .. Alt_Length) = "Circle");
      Item.Next_Field (Name, Name_Length, Has_Field, Error);
      pragma Assert (Has_Field and then Name (1 .. Name_Length) = "radius");
      Item.Read_Signed (Radius, Error);
      Item.Next_Field (Name, Name_Length, Has_Field, Error);
      pragma Assert (not Has_Field);
      Item.End_Variant (Error);
      pragma Assert (Radius = 3);
      Finish (Item, Error);
   end;

   declare
      Input  : aliased constant String := """line\n\""quote \uD83D\uDE00""";
      Item   : JSON.Reader (Input'Access);
      Error  : Errors.Error_Info;
      Value  : String (1 .. 32);
      Length : Natural;
   begin
      Item.Initialize;
      Item.Read_Text (Value, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Length = 16);
      pragma
        Assert (Value (1 .. 12) = "line" & Character'Val (10) & """quote ");
      pragma
        Assert
          (Value (13 .. 16)
             = Character'Val (16#F0#)
               & Character'Val (16#9F#)
               & Character'Val (16#98#)
               & Character'Val (16#80#));
      Finish (Item, Error);
   end;

   declare
      Input : aliased constant String := "-0.0";
      Item  : JSON.Reader (Input'Access);
      Error : Errors.Error_Info;
      Value : Flyology_Serde.Data_Model.Float_64_Value;
   begin
      Item.Initialize;
      Item.Read_Float_64 (Value, Error);
      pragma
        Assert
          (Flyology_Serde.Data_Model.Finite_Value (Value) = 0.0
             and then Bits (Flyology_Serde.Data_Model.Finite_Value (Value))
                      = 16#8000_0000_0000_0000#);
      Finish (Item, Error);
   end;

   declare
      Input       : aliased constant String :=
        "{""known"":1,""ignored"":{""nested"":[true,false]}}";
      Item        : JSON.Reader (Input'Access);
      Error       : Errors.Error_Info;
      Length      : Flyology_Serde.Data_Model.Length_Information;
      Name        : String (1 .. 16);
      Name_Length : Natural;
      Has_Field   : Boolean;
      Known       : Interfaces.Integer_64;
   begin
      Item.Initialize;
      Item.Begin_Record ("Tests.With_Unknown", Length, Error);
      Item.Next_Field (Name, Name_Length, Has_Field, Error);
      Item.Read_Signed (Known, Error);
      Item.Next_Field (Name, Name_Length, Has_Field, Error);
      pragma Assert (Name (1 .. Name_Length) = "ignored");
      Item.Skip_Value (Error);
      Item.Next_Field (Name, Name_Length, Has_Field, Error);
      pragma Assert (not Has_Field and then Known = 1);
      Item.End_Record (Error);
      Finish (Item, Error);
   end;

   --  A skipped raw subtree shares the active logical nesting allowance.
   declare
      Input       : aliased constant String := "{""ignored"":[]}";
      Item        : JSON.Reader (Input'Access);
      Error       : Errors.Error_Info;
      Policy      : Policies.Decode_Policy := (others => <>);
      Length      : Data_Model.Length_Information;
      Name        : String (1 .. 16);
      Name_Length : Natural;
      Has_Field   : Boolean;
   begin
      Policy.Limits.Maximum_Nesting_Depth := 1;
      Item.Initialize (Policy);
      Item.Begin_Record ("Tests.Skip_Depth", Length, Error);
      Item.Next_Field (Name, Name_Length, Has_Field, Error);
      pragma Assert (Has_Field and then Name (1 .. Name_Length) = "ignored");
      Item.Skip_Value (Error);
      pragma Assert (Error.Code = Errors.Depth_Exceeded);
      Item.Abort_Document (Error);

      Errors.Reset (Error);
      Item.Reset (Policy);
      Item.Read_Null (Error);
      pragma Assert (Error.Code = Errors.Unexpected_Kind);
   end;

   declare
      Input   : aliased constant String := "[1,[1,[0]]]";
      Item    : JSON.Reader (Input'Access);
      Error   : Errors.Error_Info;
      Policy  : Policies.Decode_Policy := (others => <>);
      Present : Boolean;
   begin
      Policy.Limits.Maximum_Nesting_Depth := 2;
      Item.Initialize (Policy);
      Item.Begin_Optional (Present, Error);
      Item.Begin_Optional (Present, Error);
      Item.Begin_Optional (Present, Error);
      pragma Assert (Error.Code = Errors.Depth_Exceeded);
      pragma Assert (Error.Offset_Unit = Errors.Byte_Offset);
      Errors.Reset (Error);
      Item.End_Optional (Error);
      pragma Assert (Error.Code = Errors.Invalid_State);

      Errors.Reset (Error);
      Item.Reset;
      Item.Begin_Optional (Present, Error);
      pragma Assert (Error.Code = Errors.No_Error);
   end;

   declare
      Input       : aliased constant String := "[1,2]";
      Item        : JSON.Reader (Input'Access);
      Error       : Errors.Error_Info;
      Policy      : Policies.Decode_Policy := (others => <>);
      Length      : Flyology_Serde.Data_Model.Length_Information;
      Has_Element : Boolean;
      Value       : Interfaces.Integer_64;
   begin
      Policy.Limits.Maximum_Container_Items := 1;
      Item.Initialize (Policy);
      Item.Begin_Sequence (Length, Error);
      Item.Next_Element (Has_Element, Error);
      Item.Read_Signed (Value, Error);
      Item.Next_Element (Has_Element, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
   end;

   declare
      Input : aliased constant String := "01";
      Item  : JSON.Reader (Input'Access);
      Error : Errors.Error_Info;
      Value : Interfaces.Unsigned_64;
   begin
      Item.Initialize;
      Item.Read_Unsigned (Value, Error);
      pragma Assert (Error.Code = Errors.Syntax_Error);
      pragma Assert (Error.Input_Offset = 1);
   end;

   declare
      Input  : aliased constant String := """\uD800""";
      Item   : JSON.Reader (Input'Access);
      Error  : Errors.Error_Info;
      Value  : String (1 .. 8);
      Length : Natural;
   begin
      Item.Initialize;
      Item.Read_Text (Value, Length, Error);
      pragma Assert (Error.Code = Errors.Invalid_Text);
   end;

   declare
      Input  : aliased constant String := """abcd""";
      Item   : JSON.Reader (Input'Access);
      Error  : Errors.Error_Info;
      Value  : String (1 .. 3);
      Length : Natural;
   begin
      Item.Initialize;
      Item.Read_Text (Value, Length, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
      pragma Assert (Item.Input_Offset = 0);
      pragma
        Assert (Length = 0 and then (for all Item of Value => Item = ' '));
   end;

   declare
      Input : aliased constant String := "null false";
      Item  : JSON.Reader (Input'Access);
      Error : Errors.Error_Info;
   begin
      Item.Initialize;
      Item.Read_Null (Error);
      Item.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.Syntax_Error);
      pragma Assert (Error.Input_Offset = 5);
   end;

   declare
      Input  : aliased constant String := "null";
      Item   : JSON.Reader (Input'Access);
      Error  : Errors.Error_Info;
      Policy : Policies.Decode_Policy := (others => <>);
   begin
      Policy.Limits.Maximum_Input_Units := 3;
      Item.Initialize (Policy);
      Item.Read_Null (Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
      pragma Assert (Error.Input_Offset = 3);
      pragma Assert (Item.Input_Offset = 3);
   end;

   declare
      Input       : aliased constant String :=
        "[-9223372036854775808,18446744073709551615]";
      Item        : JSON.Reader (Input'Access);
      Error       : Errors.Error_Info;
      Length      : Flyology_Serde.Data_Model.Length_Information;
      Has_Element : Boolean;
      Signed      : Interfaces.Integer_64;
      Unsigned    : Interfaces.Unsigned_64;
   begin
      Item.Initialize;
      Item.Begin_Sequence (Length, Error);
      Item.Next_Element (Has_Element, Error);
      Item.Read_Signed (Signed, Error);
      Item.Next_Element (Has_Element, Error);
      Item.Read_Unsigned (Unsigned, Error);
      Item.Next_Element (Has_Element, Error);
      Item.End_Sequence (Error);
      pragma Assert (Signed = Interfaces.Integer_64'First);
      pragma Assert (Unsigned = Interfaces.Unsigned_64'Last);
      Finish (Item, Error);
   end;

   declare
      Input       : aliased constant String := "[null,null]";
      Item        : JSON.Reader (Input'Access);
      Error       : Errors.Error_Info;
      Policy      : Policies.Decode_Policy := (others => <>);
      Length      : Flyology_Serde.Data_Model.Length_Information;
      Has_Element : Boolean;
   begin
      Policy.Limits.Maximum_Logical_Values := 2;
      Item.Initialize (Policy);
      Item.Begin_Sequence (Length, Error);
      Item.Next_Element (Has_Element, Error);
      Item.Read_Null (Error);
      Item.Next_Element (Has_Element, Error);
      Item.Read_Null (Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
   end;

   declare
      Input  : aliased constant String := """four""";
      Item   : JSON.Reader (Input'Access);
      Error  : Errors.Error_Info;
      Policy : Policies.Decode_Policy := (others => <>);
      Value  : String (1 .. 8);
      Length : Natural;
   begin
      Policy.Limits.Maximum_Text_Length := 3;
      Item.Initialize (Policy);
      Item.Read_Text (Value, Length, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
      pragma Assert (Item.Input_Offset = 0);
   end;

   declare
      Input  : aliased constant String := """\u0000""";
      Item   : JSON.Reader (Input'Access);
      Error  : Errors.Error_Info;
      Policy : Policies.Decode_Policy := (others => <>);
      Value  : String (1 .. 1);
      Length : Natural;
   begin
      Policy.Limits.Maximum_Input_Units := 2;
      Item.Initialize (Policy);
      Item.Read_Text (Value, Length, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
      pragma Assert (Error.Input_Offset = 2);

      Errors.Reset (Error);
      Item.Reset;
      Item.Read_Text (Value, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Length = 1 and then Value (1) = Character'Val (0));
      Finish (Item, Error);
   end;

   declare
      Input  : aliased constant String := "{""$bytes"":""""}";
      Item   : JSON.Reader (Input'Access);
      Error  : Errors.Error_Info;
      Policy : Policies.Decode_Policy := (others => <>);
      Value  : Ada.Streams.Stream_Element_Array (1 .. 1);
      Length : Natural;
   begin
      Policy.Limits.Maximum_Text_Length := 0;
      Item.Initialize (Policy);
      Item.Read_Bytes (Value, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error and then Length = 0);
      Finish (Item, Error);
   end;

   declare
      Input  : aliased constant String := "{""many"":[1,2,3]}";
      Item   : JSON.Reader (Input'Access);
      Error  : Errors.Error_Info;
      Policy : Policies.Decode_Policy := (others => <>);
   begin
      Policy.Limits.Maximum_Logical_Values := 1;
      Item.Initialize (Policy);
      Item.Skip_Value (Error);
      Finish (Item, Error);
   end;

   declare
      Input : aliased constant String := "1.5";
      Item  : JSON.Reader (Input'Access);
      Error : Errors.Error_Info;
   begin
      Item.Initialize;
      pragma Assert (Item.Peek_Kind (Error) = Data_Model.Float_Value);
   end;

   declare
      Input : aliased constant String := "-1";
      Item  : JSON.Reader (Input'Access);
      Error : Errors.Error_Info;
   begin
      Item.Initialize;
      pragma Assert (Item.Peek_Kind (Error) = Data_Model.Signed_Integer_Value);
   end;

   declare
      Input : aliased constant String := "1";
      Item  : JSON.Reader (Input'Access);
      Error : Errors.Error_Info;
   begin
      Item.Initialize;
      pragma
        Assert (Item.Peek_Kind (Error) = Data_Model.Unsigned_Integer_Value);
   end;

   declare
      Input : aliased constant String := "null";
      Item  : JSON.Reader (Input'Access);
      Error : Errors.Error_Info;
      Value : Boolean;
   begin
      Item.Initialize;
      Item.Read_Boolean (Value, Error);
      pragma Assert (Error.Code = Errors.Unexpected_Kind);
      pragma Assert (Error.Input_Offset = 0);
   end;

   declare
      Input       : aliased constant String := "[1,]";
      Item        : JSON.Reader (Input'Access);
      Error       : Errors.Error_Info;
      Length      : Data_Model.Length_Information;
      Has_Element : Boolean;
      Value       : Interfaces.Integer_64;
   begin
      Item.Initialize;
      Item.Begin_Sequence (Length, Error);
      Item.Next_Element (Has_Element, Error);
      Item.Read_Signed (Value, Error);
      Item.Next_Element (Has_Element, Error);
      pragma Assert (Error.Code = Errors.Syntax_Error);
      pragma Assert (not Has_Element and then Error.Input_Offset = 3);
   end;

   declare
      Input       : aliased constant String := "[";
      Item        : JSON.Reader (Input'Access);
      Error       : Errors.Error_Info;
      Length      : Data_Model.Length_Information;
      Has_Element : Boolean;
   begin
      Item.Initialize;
      Item.Begin_Sequence (Length, Error);
      Item.Next_Element (Has_Element, Error);
      pragma Assert (Error.Code = Errors.Syntax_Error);
      pragma Assert (not Has_Element and then Error.Input_Offset = 1);
   end;

   declare
      Input  : aliased constant String :=
        '"' & "ok" & Character'Val (16#C2#) & 'x' & '"';
      Item   : JSON.Reader (Input'Access);
      Error  : Errors.Error_Info;
      Value  : String (1 .. 8);
      Length : Natural;
   begin
      Item.Initialize;
      Item.Read_Text (Value, Length, Error);
      pragma Assert (Error.Code = Errors.Invalid_Text);
      pragma Assert (Error.Input_Offset = 4);
      pragma
        Assert (Length = 0 and then (for all Item of Value => Item = ' '));
   end;

   declare
      Input       : aliased constant String := "{""name"" 1}";
      Item        : JSON.Reader (Input'Access);
      Error       : Errors.Error_Info;
      Length      : Data_Model.Length_Information;
      Name        : String (1 .. 8) := [others => 'x'];
      Name_Length : Natural := Natural'Last;
      Has_Field   : Boolean := True;
   begin
      Item.Initialize;
      Item.Begin_Record ("Tests.Malformed", Length, Error);
      Item.Next_Field (Name, Name_Length, Has_Field, Error);
      pragma Assert (Error.Code = Errors.Syntax_Error);
      pragma Assert (not Has_Field and then Name_Length = 0);
      pragma Assert (for all Character of Name => Character = ' ');
   end;

   declare
      Input       : aliased constant String := "[""Circle"" {}]";
      Item        : JSON.Reader (Input'Access);
      Error       : Errors.Error_Info;
      Alternative : String (1 .. 8) := [others => 'x'];
      Name_Length : Natural := Natural'Last;
      Length      : Data_Model.Length_Information;
   begin
      Item.Initialize;
      Item.Begin_Variant
        ("Tests.Malformed", Alternative, Name_Length, Length, Error);
      pragma Assert (Error.Code = Errors.Syntax_Error);
      pragma Assert (Name_Length = 0);
      pragma Assert (for all Character of Alternative => Character = ' ');
   end;

   declare
      Input       : aliased constant String := "[,]";
      Item        : JSON.Reader (Input'Access);
      Error       : Errors.Error_Info;
      Length      : Data_Model.Length_Information;
      Has_Element : Boolean;
   begin
      Item.Initialize;
      Item.Begin_Sequence (Length, Error);
      Item.Next_Element (Has_Element, Error);
      pragma Assert (Error.Code = Errors.Syntax_Error);
      pragma Assert (not Has_Element and then Error.Input_Offset = 1);
   end;

   declare
      Input       : aliased constant String := "[1,,2]";
      Item        : JSON.Reader (Input'Access);
      Error       : Errors.Error_Info;
      Length      : Data_Model.Length_Information;
      Has_Element : Boolean;
      Value       : Interfaces.Integer_64;
   begin
      Item.Initialize;
      Item.Begin_Sequence (Length, Error);
      Item.Next_Element (Has_Element, Error);
      Item.Read_Signed (Value, Error);
      Item.Next_Element (Has_Element, Error);
      pragma Assert (Error.Code = Errors.Syntax_Error);
      pragma Assert (not Has_Element and then Error.Input_Offset = 3);
   end;
end JSON_Reader_Tests;
