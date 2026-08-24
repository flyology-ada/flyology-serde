with Ada.Streams;
with Ada.Unchecked_Conversion;
with Flyology_Serde.Adapters.Float_64_Values;
with Flyology_Serde.Adapters.Unsigned_Integers;
with Flyology_Serde.Data_Model;
with Flyology_Serde.Deserialization;
with Flyology_Serde.Deserialization_Adapters;
with Flyology_Serde.Deserializers.CBOR;
with Flyology_Serde.Deserializers.JSON;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;
with Flyology_Serde.Serialization;
with Flyology_Serde.Serialization_Adapters;
with Flyology_Serde.Serializers.CBOR;
with Flyology_Serde.Serializers.JSON;
with Interfaces;

procedure Scalar_Parity_Tests is
   package Data_Model renames Flyology_Serde.Data_Model;
   package Errors renames Flyology_Serde.Errors;
   package Policies renames Flyology_Serde.Policies;
   package CBOR_Readers renames Flyology_Serde.Deserializers.CBOR;
   package JSON_Readers renames Flyology_Serde.Deserializers.JSON;
   package CBOR_Writers renames Flyology_Serde.Serializers.CBOR;
   package JSON_Writers renames Flyology_Serde.Serializers.JSON;
   use type Ada.Streams.Stream_Element_Array;
   use type Errors.Error_Code;
   use type Flyology_Serde.Serialization.Serializer_State;
   use type Interfaces.Unsigned_64;

   subtype Bytes is Ada.Streams.Stream_Element_Array;

   type Byte_Mod is mod 2 ** 8;

   package Bytes_Unsigned is new
     Flyology_Serde.Adapters.Unsigned_Integers (Byte_Mod);
   package U64_Unsigned is new
     Flyology_Serde.Adapters.Unsigned_Integers (Interfaces.Unsigned_64);

   Serialization_Limits : constant
     Flyology_Serde.Serialization.Serialization_Limits :=
       (Maximum_Nesting_Depth   => 4,
        Maximum_Container_Items => 4,
        Maximum_Text_Length     => 128,
        Maximum_Byte_Length     => 128,
        Maximum_Logical_Events  => 16);

   package Byte_Serialization is new
     Flyology_Serde.Serialization_Adapters
       (Source_Type     => Byte_Mod,
        Limits          => Serialization_Limits,
        Serialize_Value => Bytes_Unsigned.Serialize_Value);

   package U64_Serialization is new
     Flyology_Serde.Serialization_Adapters
       (Source_Type     => Interfaces.Unsigned_64,
        Limits          => Serialization_Limits,
        Serialize_Value => U64_Unsigned.Serialize_Value);

   type U64_Builder is limited record
      Published : Interfaces.Unsigned_64 := 0;
      Candidate : Interfaces.Unsigned_64 := 0;
      Commits   : Natural := 0;
      Rollbacks : Natural := 0;
   end record;

   procedure Begin_U64
     (Target : in out U64_Builder; Error : in out Errors.Error_Info) is
      pragma Unreferenced (Error);
   begin
      Target.Candidate := 0;
   end Begin_U64;

   procedure Read_U64
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out U64_Builder;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info) is
      pragma Unreferenced (Policy);
   begin
      U64_Unsigned.Deserialize_Candidate (From, Target.Candidate, Error);
   end Read_U64;

   procedure Commit_U64
     (Target : in out U64_Builder; Error : in out Errors.Error_Info) is
      pragma Unreferenced (Error);
   begin
      Target.Published := Target.Candidate;
      Target.Commits := Target.Commits + 1;
   end Commit_U64;

   procedure Rollback_U64 (Target : in out U64_Builder) is
   begin
      Target.Candidate := 0;
      Target.Rollbacks := Target.Rollbacks + 1;
   end Rollback_U64;

   Default_Policy : constant Policies.Decode_Policy := (others => <>);

   package U64_Deserialization is new
     Flyology_Serde.Deserialization_Adapters
       (Builder_Type       => U64_Builder,
        Policy             => Default_Policy,
        Begin_Candidate    => Begin_U64,
        Deserialize_Value  => Read_U64,
        Commit_Candidate   => Commit_U64,
        Rollback_Candidate => Rollback_U64);

   package Float_Serialization is new
     Flyology_Serde.Serialization_Adapters
       (Source_Type     => Data_Model.Float_64_Value,
        Limits          => Serialization_Limits,
        Serialize_Value => Flyology_Serde.Adapters.Float_64_Values.Serialize_Value);

   type Float_Builder is limited record
      Published : Data_Model.Float_64_Value;
      Candidate : Data_Model.Float_64_Value;
      Commits   : Natural := 0;
      Rollbacks : Natural := 0;
   end record;

   procedure Begin_Float
     (Target : in out Float_Builder; Error : in out Errors.Error_Info) is
      pragma Unreferenced (Error);
   begin
      Target.Candidate := Data_Model.Make_Finite (0.0);
   end Begin_Float;

   procedure Read_Float
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out Float_Builder;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info) is
      pragma Unreferenced (Policy);
   begin
      Flyology_Serde.Adapters.Float_64_Values.Deserialize_Candidate
        (From, Target.Candidate, Error);
   end Read_Float;

   procedure Commit_Float
     (Target : in out Float_Builder; Error : in out Errors.Error_Info) is
      pragma Unreferenced (Error);
   begin
      Target.Published := Target.Candidate;
      Target.Commits := Target.Commits + 1;
   end Commit_Float;

   procedure Rollback_Float (Target : in out Float_Builder) is
   begin
      Target.Candidate := Data_Model.Make_Finite (0.0);
      Target.Rollbacks := Target.Rollbacks + 1;
   end Rollback_Float;

   package Float_Deserialization is new
     Flyology_Serde.Deserialization_Adapters
       (Builder_Type       => Float_Builder,
        Policy             => Default_Policy,
        Begin_Candidate    => Begin_Float,
        Deserialize_Value  => Read_Float,
        Commit_Candidate   => Commit_Float,
        Rollback_Candidate => Rollback_Float);

   function To_Float is new Ada.Unchecked_Conversion
     (Interfaces.Unsigned_64, Interfaces.IEEE_Float_64);
   function To_Bits is new Ada.Unchecked_Conversion
     (Interfaces.IEEE_Float_64, Interfaces.Unsigned_64);

   type Bit_Array is array (Positive range <>) of Interfaces.Unsigned_64;
   Float_Fixtures : constant Bit_Array :=
     [16#0000_0000_0000_0000#,
      16#8000_0000_0000_0000#,
      16#0000_0000_0000_0001#,
      16#8000_0000_0000_0001#,
      16#0010_0000_0000_0000#,
      16#7FEF_FFFF_FFFF_FFFF#,
      16#FFEF_FFFF_FFFF_FFFF#,
      16#3FEF_FFFF_FFFF_FFFF#,
      16#3FF0_0000_0000_0001#];

   procedure Check_JSON_Unsigned (Value : Interfaces.Unsigned_64) is
      Output : JSON_Writers.Bounded_Writer (32);
      Buffer : String (1 .. 32);
      Length : Natural;
      Error  : Errors.Error_Info;
   begin
      U64_Serialization.Serialize (Value, Output, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      Output.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      declare
         Input  : aliased constant String := Buffer (1 .. Length);
         Reader : JSON_Readers.Reader (Input'Access);
         Target : U64_Builder;
      begin
         Reader.Initialize (Default_Policy);
         U64_Deserialization.Deserialize (Reader, Target, Error);
         pragma Assert (Error.Code = Errors.No_Error);
         pragma Assert (Target.Published = Value and then Target.Commits = 1);
      end;
   end Check_JSON_Unsigned;

   procedure Check_CBOR_Unsigned (Value : Interfaces.Unsigned_64) is
      Output : CBOR_Writers.Bounded_Writer (16);
      Buffer : Bytes (1 .. 16);
      Length : Natural;
      Error  : Errors.Error_Info;
   begin
      U64_Serialization.Serialize (Value, Output, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      Output.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      declare
         Input  : aliased constant Bytes :=
           Buffer (1 .. Ada.Streams.Stream_Element_Offset (Length));
         Reader : CBOR_Readers.Reader (Input'Access);
         Target : U64_Builder;
      begin
         Reader.Initialize (Default_Policy);
         U64_Deserialization.Deserialize (Reader, Target, Error);
         pragma Assert (Error.Code = Errors.No_Error);
         pragma Assert (Target.Published = Value and then Target.Commits = 1);
      end;
   end Check_CBOR_Unsigned;

   procedure Check_JSON_Float (Bits : Interfaces.Unsigned_64) is
      Original : constant Data_Model.Float_64_Value :=
        Data_Model.Make_Finite (To_Float (Bits));
      Output : JSON_Writers.Bounded_Writer (64);
      Buffer : String (1 .. 64);
      Length : Natural;
      Error  : Errors.Error_Info;
   begin
      Float_Serialization.Serialize (Original, Output, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      Output.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      declare
         Input  : aliased constant String := Buffer (1 .. Length);
         Reader : JSON_Readers.Reader (Input'Access);
         Target : Float_Builder;
      begin
         Reader.Initialize (Default_Policy);
         Float_Deserialization.Deserialize (Reader, Target, Error);
         pragma Assert (Error.Code = Errors.No_Error);
         pragma Assert (Target.Commits = 1);
         pragma Assert
           (To_Bits (Data_Model.Finite_Value (Target.Published)) = Bits);
      end;
   end Check_JSON_Float;

begin
   pragma Assert (Interfaces.Unsigned_64'Size = 64);
   pragma Assert (Interfaces.IEEE_Float_64'Size = 64);
   pragma Assert (Interfaces.IEEE_Float_64'Machine_Mantissa = 53);
   pragma Assert (Interfaces.IEEE_Float_64'Machine_Emin = -1_021);
   pragma Assert (Interfaces.IEEE_Float_64'Machine_Emax = 1_024);

   Check_JSON_Unsigned (0);
   Check_JSON_Unsigned (Interfaces.Unsigned_64'Last);
   Check_CBOR_Unsigned (0);
   Check_CBOR_Unsigned (Interfaces.Unsigned_64'Last);

   declare
      Output : JSON_Writers.Bounded_Writer (16);
      Buffer : String (1 .. 16);
      Length : Natural;
      Error  : Errors.Error_Info;
   begin
      Byte_Serialization.Serialize (0, Output, Error);
      Output.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Buffer (1 .. Length) = "0");
   end;

   declare
      Output : CBOR_Writers.Bounded_Writer (16);
      Buffer : Bytes (1 .. 16);
      Length : Natural;
      Error  : Errors.Error_Info;
   begin
      Byte_Serialization.Serialize (0, Output, Error);
      Output.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert
        (Buffer (1 .. Ada.Streams.Stream_Element_Offset (Length))
         = Bytes'[0]);
   end;

   declare
      Output : JSON_Writers.Bounded_Writer (16);
      Buffer : String (1 .. 16);
      Length : Natural;
      Error  : Errors.Error_Info;
   begin
      Byte_Serialization.Serialize (255, Output, Error);
      Output.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Buffer (1 .. Length) = "255");
   end;

   declare
      Output : CBOR_Writers.Bounded_Writer (16);
      Buffer : Bytes (1 .. 16);
      Length : Natural;
      Error  : Errors.Error_Info;
   begin
      Byte_Serialization.Serialize (255, Output, Error);
      Output.Copy_Output (Buffer, Length, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert
        (Buffer (1 .. Ada.Streams.Stream_Element_Offset (Length))
         = Bytes'[16#18#, 16#FF#]);
   end;

   --  Narrow modular endpoints decode through both backends.
   declare
      Input  : aliased constant String := "0";
      Reader : JSON_Readers.Reader (Input'Access);
      Target : Byte_Mod := 255;
      Error  : Errors.Error_Info;
   begin
      Reader.Initialize (Default_Policy);
      Bytes_Unsigned.Deserialize_Candidate (Reader, Target, Error);
      Reader.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error and then Target = 0);
   end;

   declare
      Input  : aliased constant Bytes := [0];
      Reader : CBOR_Readers.Reader (Input'Access);
      Target : Byte_Mod := 255;
      Error  : Errors.Error_Info;
   begin
      Reader.Initialize (Default_Policy);
      Bytes_Unsigned.Deserialize_Candidate (Reader, Target, Error);
      Reader.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error and then Target = 0);
   end;

   declare
      Input  : aliased constant String := "255";
      Reader : JSON_Readers.Reader (Input'Access);
      Target : Byte_Mod := 0;
      Error  : Errors.Error_Info;
   begin
      Reader.Initialize (Default_Policy);
      Bytes_Unsigned.Deserialize_Candidate (Reader, Target, Error);
      Reader.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error and then Target = 255);
   end;

   declare
      Input  : aliased constant Bytes := [16#18#, 16#FF#];
      Reader : CBOR_Readers.Reader (Input'Access);
      Target : Byte_Mod := 0;
      Error  : Errors.Error_Info;
   begin
      Reader.Initialize (Default_Policy);
      Bytes_Unsigned.Deserialize_Candidate (Reader, Target, Error);
      Reader.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error and then Target = 255);
   end;

   --  A narrow overflow is a status and leaves the leaf candidate unchanged.
   declare
      Input  : aliased constant String := "256";
      Reader : JSON_Readers.Reader (Input'Access);
      Target : Byte_Mod := 7;
      Error  : Errors.Error_Info;
   begin
      Reader.Initialize (Default_Policy);
      Bytes_Unsigned.Deserialize_Candidate (Reader, Target, Error);
      pragma Assert (Error.Code = Errors.Out_Of_Range and then Target = 7);
      Reader.Abort_Document (Error);
   end;

   declare
      Input  : aliased constant Bytes := [16#19#, 1, 0];
      Reader : CBOR_Readers.Reader (Input'Access);
      Target : Byte_Mod := 7;
      Error  : Errors.Error_Info;
   begin
      Reader.Initialize (Default_Policy);
      Bytes_Unsigned.Deserialize_Candidate (Reader, Target, Error);
      pragma Assert (Error.Code = Errors.Out_Of_Range and then Target = 7);
      Reader.Abort_Document (Error);
   end;

   --  A prelatched status touches neither writer nor reader.
   declare
      Output : JSON_Writers.Bounded_Writer (32);
      Error  : Errors.Error_Info;
   begin
      Errors.Fail (Error, Errors.Application_Error);
      Bytes_Unsigned.Serialize_Value (255, Output, Error);
      pragma Assert (Output.State = Flyology_Serde.Serialization.Ready);
      pragma Assert (Output.Written_Length = 0);
   end;

   declare
      Input  : aliased constant String := "255";
      Reader : JSON_Readers.Reader (Input'Access);
      Target : Byte_Mod := 7;
      Error  : Errors.Error_Info;
   begin
      Reader.Initialize (Default_Policy);
      Errors.Fail (Error, Errors.Application_Error);
      Bytes_Unsigned.Deserialize_Candidate (Reader, Target, Error);
      pragma Assert (Target = 7);
      Errors.Reset (Error);
      Bytes_Unsigned.Deserialize_Candidate (Reader, Target, Error);
      Reader.Finish_Document (Error);
      pragma Assert (Error.Code = Errors.No_Error and then Target = 255);
   end;

   for Bits of Float_Fixtures loop
      Check_JSON_Float (Bits);
   end loop;

   --  Root trailing-input failure keeps the previous published float.
   declare
      Original_Bits : constant Interfaces.Unsigned_64 :=
        16#7FEF_FFFF_FFFF_FFFF#;
      Input  : aliased constant String := "1.0 0";
      Reader : JSON_Readers.Reader (Input'Access);
      Target : Float_Builder;
      Error  : Errors.Error_Info;
   begin
      Target.Published := Data_Model.Make_Finite (To_Float (Original_Bits));
      Reader.Initialize (Default_Policy);
      Float_Deserialization.Deserialize (Reader, Target, Error);
      pragma Assert (Error.Code = Errors.Syntax_Error);
      pragma Assert (Target.Commits = 0 and then Target.Rollbacks = 1);
      pragma Assert
        (To_Bits (Data_Model.Finite_Value (Target.Published)) = Original_Bits);
   end;
end Scalar_Parity_Tests;
