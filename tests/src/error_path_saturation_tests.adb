with Ada.Streams;
with Flyology_Serde.Adapters.Arrays;
with Flyology_Serde.Data_Model;
with Flyology_Serde.Deserialization;
with Flyology_Serde.Deserialization_Adapters;
with Flyology_Serde.Deserializers.CBOR;
with Flyology_Serde.Deserializers.CBOR.Testing;
with Flyology_Serde.Deserializers.JSON;
with Flyology_Serde.Deserializers.JSON.Testing;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;
with Flyology_Serde.Serialization;
with Flyology_Serde.Serialization_Adapters;
with Flyology_Serde.Serializers.CBOR;
with Flyology_Serde.Serializers.JSON;

procedure Error_Path_Saturation_Tests is
   package Data_Model renames Flyology_Serde.Data_Model;
   package Deserialization renames Flyology_Serde.Deserialization;
   package Errors renames Flyology_Serde.Errors;
   package Policies renames Flyology_Serde.Policies;
   package Serialization renames Flyology_Serde.Serialization;
   package CBOR_Reader renames Flyology_Serde.Deserializers.CBOR;
   package CBOR_Testing renames Flyology_Serde.Deserializers.CBOR.Testing;
   package CBOR_Writer renames Flyology_Serde.Serializers.CBOR;
   package JSON_Reader renames Flyology_Serde.Deserializers.JSON;
   package JSON_Testing renames Flyology_Serde.Deserializers.JSON.Testing;
   package JSON_Writer renames Flyology_Serde.Serializers.JSON;

   use type Ada.Streams.Stream_Element_Array;
   use type Ada.Streams.Stream_Element_Offset;
   use type Errors.Error_Code;
   use type Errors.Input_Offset_Unit;
   use type Errors.Path_Array;
   use type Errors.Path_Element_Kind;
   use type Serialization.Serializer_State;

   subtype Byte_Array is Ada.Streams.Stream_Element_Array;
   subtype Byte_Offset is Ada.Streams.Stream_Element_Offset;

   Deep_Policy : constant Policies.Decode_Policy :=
     (Limits  =>
        (Maximum_Nesting_Depth   => 256,
         Maximum_Container_Items => 1,
         Maximum_Text_Length     => 1,
         Maximum_Byte_Length     => 1,
         Maximum_Input_Units     => 1_024,
         Maximum_Logical_Values  => 300),
      Records => (others => <>),
      Maps    => (others => <>));

   Deep_Serialization_Limits : constant Serialization.Serialization_Limits :=
     (Maximum_Nesting_Depth   => 256,
      Maximum_Container_Items => 1,
      Maximum_Text_Length     => 1,
      Maximum_Byte_Length     => 1,
      Maximum_Logical_Events  => 600);

   Success_Depths : constant array (Positive range 1 .. 3) of Positive :=
     [32, 33, 256];
   Failure_Depths : constant array (Positive range 1 .. 2) of Positive :=
     [33, 256];

   type Leaf_Action is (Emit_Null, Report_Failure, Raise_Exception);

   type Tree_Request is record
      Depth  : Natural := 0;
      Action : Leaf_Action := Emit_Null;
   end record;

   type Request_Array is array (Positive range <>) of Tree_Request;

   type Decode_Leaf_Action is (Read_Null_Leaf, Read_Boolean_Leaf, Raise_Leaf);

   type Nested_Builder is limited record
      Expected_Depth  : Natural := 0;
      Leaf_Action     : Decode_Leaf_Action := Read_Null_Leaf;
      Open_Depth      : Natural := 0;
      Candidate_Depth : Natural := 0;
      Published_Depth : Natural := 777;
      Candidate_Ready : Boolean := False;
      Commit_Count    : Natural := 0;
      Rollback_Count  : Natural := 0;
   end record;

   procedure Serialize_Level
     (Item  : Tree_Request;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info);

   procedure Serialize_Child
     (Item  : Tree_Request;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info);

   procedure Begin_Array
     (Target : in out Nested_Builder;
      Length : Data_Model.Length_Information;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info);

   procedure Append_Child
     (From     : in out Deserialization.Deserializer'Class;
      Target   : in out Nested_Builder;
      Position : Natural;
      Policy   : Policies.Decode_Policy;
      Error    : in out Errors.Error_Info);

   procedure Finish_Array
     (Target : in out Nested_Builder; Error : in out Errors.Error_Info);

   package Nested_Arrays is new
     Flyology_Serde.Adapters.Arrays
       (Index_Type        => Positive,
        Element_Type      => Tree_Request,
        Array_Type        => Request_Array,
        Builder_Type      => Nested_Builder,
        Maximum_Elements  => 1,
        Serialize_Element => Serialize_Child,
        Begin_Candidate   => Begin_Array,
        Append_Element    => Append_Child,
        Finish_Candidate  => Finish_Array);

   procedure Serialize_Level
     (Item  : Tree_Request;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
   begin
      if Item.Depth > 0 then
         Nested_Arrays.Serialize_Value
           ([1 => (Depth => Item.Depth - 1, Action => Item.Action)],
            Into,
            Error);
      else
         case Item.Action is
            when Emit_Null       =>
               Into.Put_Null (Error);

            when Report_Failure  =>
               Errors.Fail (Error, Errors.Application_Error);

            when Raise_Exception =>
               raise Program_Error;
         end case;
      end if;
   end Serialize_Level;

   procedure Serialize_Child
     (Item  : Tree_Request;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
   begin
      Serialize_Level (Item, Into, Error);
   end Serialize_Child;

   procedure Begin_Array
     (Target : in out Nested_Builder;
      Length : Data_Model.Length_Information;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info)
   is
      pragma Unreferenced (Length, Policy);
   begin
      if Error.Code = Errors.No_Error then
         Target.Open_Depth := Target.Open_Depth + 1;
      end if;
   end Begin_Array;

   procedure Append_Child
     (From     : in out Deserialization.Deserializer'Class;
      Target   : in out Nested_Builder;
      Position : Natural;
      Policy   : Policies.Decode_Policy;
      Error    : in out Errors.Error_Info)
   is
      Value : Boolean;
   begin
      pragma Assert (Position = 0);
      if Target.Open_Depth < Target.Expected_Depth then
         Nested_Arrays.Deserialize_Candidate (From, Target, Policy, Error);
      else
         case Target.Leaf_Action is
            when Read_Null_Leaf    =>
               From.Read_Null (Error);

            when Read_Boolean_Leaf =>
               From.Read_Boolean (Value, Error);
               if Error.Code = Errors.No_Error and then not Value then
                  Errors.Fail (Error, Errors.Invalid_Value);
               end if;

            when Raise_Leaf        =>
               raise Program_Error;
         end case;
      end if;
   end Append_Child;

   procedure Finish_Array
     (Target : in out Nested_Builder; Error : in out Errors.Error_Info) is
   begin
      if Error.Code = Errors.No_Error then
         pragma Assert (Target.Open_Depth > 0);
         Target.Open_Depth := Target.Open_Depth - 1;
         Target.Candidate_Depth := Target.Candidate_Depth + 1;
      end if;
   end Finish_Array;

   package Root_Serialization is new
     Flyology_Serde.Serialization_Adapters
       (Source_Type     => Tree_Request,
        Limits          => Deep_Serialization_Limits,
        Serialize_Value => Serialize_Level);

   procedure Begin_Root
     (Target : in out Nested_Builder; Error : in out Errors.Error_Info) is
   begin
      if Error.Code = Errors.No_Error then
         Target.Open_Depth := 0;
         Target.Candidate_Depth := 0;
         Target.Candidate_Ready := True;
      end if;
   end Begin_Root;

   procedure Deserialize_Root_Value
     (From   : in out Deserialization.Deserializer'Class;
      Target : in out Nested_Builder;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info) is
   begin
      if Target.Expected_Depth = 0 then
         if Target.Leaf_Action = Raise_Leaf then
            raise Program_Error;
         elsif Target.Leaf_Action = Read_Boolean_Leaf then
            declare
               Value : Boolean;
            begin
               From.Read_Boolean (Value, Error);
            end;
         else
            From.Read_Null (Error);
         end if;
      else
         Nested_Arrays.Deserialize_Candidate (From, Target, Policy, Error);
      end if;
   end Deserialize_Root_Value;

   procedure Commit_Root
     (Target : in out Nested_Builder; Error : in out Errors.Error_Info) is
   begin
      if not Target.Candidate_Ready
        or else Target.Open_Depth /= 0
        or else Target.Candidate_Depth /= Target.Expected_Depth
      then
         Errors.Fail (Error, Errors.Invalid_State);
      else
         Target.Published_Depth := Target.Candidate_Depth;
         Target.Candidate_Ready := False;
         Target.Commit_Count := Target.Commit_Count + 1;
      end if;
   end Commit_Root;

   procedure Rollback_Root (Target : in out Nested_Builder) is
   begin
      Target.Open_Depth := 0;
      Target.Candidate_Depth := 0;
      Target.Candidate_Ready := False;
      Target.Rollback_Count := Target.Rollback_Count + 1;
   end Rollback_Root;

   package Root_Deserialization is new
     Flyology_Serde.Deserialization_Adapters
       (Builder_Type       => Nested_Builder,
        Policy             => Deep_Policy,
        Begin_Candidate    => Begin_Root,
        Deserialize_Value  => Deserialize_Root_Value,
        Commit_Candidate   => Commit_Root,
        Rollback_Candidate => Rollback_Root);

   function JSON_Input
     (Depth : Natural; Boolean_Leaf : Boolean := False) return String
   is
      Leaf   : constant String := (if Boolean_Leaf then "true" else "null");
      Result : String (1 .. 2 * Depth + Leaf'Length);
   begin
      for Index in 1 .. Depth loop
         Result (Index) := '[';
         Result (Depth + Leaf'Length + Index) := ']';
      end loop;
      Result (Depth + 1 .. Depth + Leaf'Length) := Leaf;
      return Result;
   end JSON_Input;

   function CBOR_Input
     (Depth : Natural; Boolean_Leaf : Boolean := False) return Byte_Array
   is
      First  : constant Byte_Offset := 17;
      Result : Byte_Array (First .. First + Byte_Offset (Depth));
   begin
      for Index in 1 .. Depth loop
         Result (First + Byte_Offset (Index - 1)) := 16#81#;
      end loop;
      Result (First + Byte_Offset (Depth)) :=
        (if Boolean_Leaf then 16#F5# else 16#F6#);
      return Result;
   end CBOR_Input;

   procedure Assert_Index_Prefix (Error : Errors.Error_Info; Depth : Natural)
   is
   begin
      pragma
        Assert
          (Error.Path_Length = Natural'Min (Depth, Errors.Maximum_Path_Depth));
      for Index in 1 .. Error.Path_Length loop
         pragma Assert (Error.Path (Index).Kind = Errors.Index_Element);
         pragma Assert (Error.Path (Index).Index = 0);
      end loop;
      pragma Assert (Error.Omitted_Path_Elements = Depth - Error.Path_Length);
   end Assert_Index_Prefix;

   procedure Check_JSON_Success (Depth : Natural) is
      Expected : constant String := JSON_Input (Depth);
      Writer   : JSON_Writer.Bounded_Writer (1_024);
      Error    : Errors.Error_Info;
      Output   : String (23 .. 22 + Expected'Length);
      Length   : Natural;
   begin
      Root_Serialization.Serialize ((Depth, Emit_Null), Writer, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma
        Assert
          (Error.Path_Length = 0 and then Error.Omitted_Path_Elements = 0);
      pragma Assert (Writer.Is_Complete);
      Writer.Copy_Output (Output, Length, Error);
      pragma
        Assert
          (Error.Code = Errors.No_Error and then Length = Expected'Length);
      pragma Assert (Output = Expected);

      declare
         Input   : aliased constant String := Expected;
         Reader  : JSON_Reader.Reader (Input'Access);
         Builder : Nested_Builder;
      begin
         Builder.Expected_Depth := Depth;
         Reader.Initialize (Deep_Policy);
         Root_Deserialization.Deserialize (Reader, Builder, Error);
         pragma Assert (Error.Code = Errors.No_Error);
         pragma
           Assert
             (Error.Path_Length = 0 and then Error.Omitted_Path_Elements = 0);
         pragma Assert (Builder.Published_Depth = Depth);
         pragma
           Assert
             (Builder.Commit_Count = 1 and then Builder.Rollback_Count = 0);
         pragma
           Assert (JSON_Testing.Budget_Input_Consumed (Reader) = Input'Length);
         pragma
           Assert (JSON_Testing.Budget_Values_Consumed (Reader) = Depth + 1);
         pragma Assert (JSON_Testing.Logical_Depth (Reader) = 0);
         pragma Assert (JSON_Testing.Budget_Depth (Reader) = 0);
      end;
   end Check_JSON_Success;

   procedure Check_CBOR_Success (Depth : Natural) is
      Expected : constant Byte_Array := CBOR_Input (Depth);
      Writer   : CBOR_Writer.Bounded_Writer (1_024);
      Error    : Errors.Error_Info;
      Output   :
        Byte_Array
          (Byte_Offset (23)
           .. Byte_Offset (22) + Byte_Offset (Expected'Length));
      Length   : Natural;
   begin
      Root_Serialization.Serialize ((Depth, Emit_Null), Writer, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma
        Assert
          (Error.Path_Length = 0 and then Error.Omitted_Path_Elements = 0);
      pragma Assert (Writer.Is_Complete);
      Writer.Copy_Output (Output, Length, Error);
      pragma
        Assert
          (Error.Code = Errors.No_Error and then Length = Expected'Length);
      pragma Assert (Output = Expected);

      declare
         Input   : aliased constant Byte_Array := Expected;
         Reader  : CBOR_Reader.Reader (Input'Access);
         Builder : Nested_Builder;
      begin
         Builder.Expected_Depth := Depth;
         Reader.Initialize (Deep_Policy);
         Root_Deserialization.Deserialize (Reader, Builder, Error);
         pragma Assert (Error.Code = Errors.No_Error);
         pragma
           Assert
             (Error.Path_Length = 0 and then Error.Omitted_Path_Elements = 0);
         pragma Assert (Builder.Published_Depth = Depth);
         pragma
           Assert
             (Builder.Commit_Count = 1 and then Builder.Rollback_Count = 0);
         pragma
           Assert (CBOR_Testing.Budget_Input_Consumed (Reader) = Input'Length);
         pragma
           Assert (CBOR_Testing.Budget_Values_Consumed (Reader) = Depth + 1);
         pragma Assert (CBOR_Testing.Logical_Depth (Reader) = 0);
         pragma Assert (CBOR_Testing.Budget_Depth (Reader) = 0);
      end;
   end Check_CBOR_Success;

   procedure Check_JSON_Wrong_Kind (Depth : Natural) is
      Input   : aliased constant String :=
        JSON_Input (Depth, Boolean_Leaf => True);
      Reader  : JSON_Reader.Reader (Input'Access);
      Builder : Nested_Builder;
      Error   : Errors.Error_Info;
   begin
      Builder.Expected_Depth := Depth;
      Reader.Initialize (Deep_Policy);
      Root_Deserialization.Deserialize (Reader, Builder, Error);
      pragma Assert (Error.Code = Errors.Unexpected_Kind);
      pragma
        Assert
          (Error.Input_Offset = Depth
             and then Error.Offset_Unit = Errors.Byte_Offset);
      Assert_Index_Prefix (Error, Depth);
      pragma Assert (Builder.Published_Depth = 777);
      pragma
        Assert (Builder.Commit_Count = 0 and then Builder.Rollback_Count = 1);
      pragma Assert (Builder.Open_Depth = 0);
      pragma Assert (JSON_Testing.Budget_Input_Consumed (Reader) = Depth);
      pragma Assert (JSON_Testing.Budget_Values_Consumed (Reader) = Depth);
      pragma Assert (JSON_Testing.Logical_Depth (Reader) = 0);
      pragma Assert (JSON_Testing.Budget_Depth (Reader) = 0);

      Errors.Reset (Error);
      Reader.Read_Null (Error);
      pragma Assert (Error.Code = Errors.Invalid_State);
      Builder.Leaf_Action := Read_Boolean_Leaf;
      Reader.Reset (Deep_Policy);
      Errors.Reset (Error);
      Root_Deserialization.Deserialize (Reader, Builder, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma
        Assert
          (Builder.Published_Depth = Depth and then Builder.Commit_Count = 1);
   end Check_JSON_Wrong_Kind;

   procedure Check_CBOR_Wrong_Kind (Depth : Natural) is
      Input   : aliased constant Byte_Array :=
        CBOR_Input (Depth, Boolean_Leaf => True);
      Reader  : CBOR_Reader.Reader (Input'Access);
      Builder : Nested_Builder;
      Error   : Errors.Error_Info;
   begin
      Builder.Expected_Depth := Depth;
      Reader.Initialize (Deep_Policy);
      Root_Deserialization.Deserialize (Reader, Builder, Error);
      pragma Assert (Error.Code = Errors.Unexpected_Kind);
      pragma
        Assert
          (Error.Input_Offset = Depth
             and then Error.Offset_Unit = Errors.Byte_Offset);
      Assert_Index_Prefix (Error, Depth);
      pragma Assert (Builder.Published_Depth = 777);
      pragma
        Assert (Builder.Commit_Count = 0 and then Builder.Rollback_Count = 1);
      pragma Assert (Builder.Open_Depth = 0);
      pragma Assert (CBOR_Testing.Budget_Input_Consumed (Reader) = Depth);
      pragma Assert (CBOR_Testing.Budget_Values_Consumed (Reader) = Depth);
      pragma Assert (CBOR_Testing.Logical_Depth (Reader) = 0);
      pragma Assert (CBOR_Testing.Budget_Depth (Reader) = 0);

      Errors.Reset (Error);
      Reader.Read_Null (Error);
      pragma Assert (Error.Code = Errors.Invalid_State);
      Builder.Leaf_Action := Read_Boolean_Leaf;
      Reader.Reset (Deep_Policy);
      Errors.Reset (Error);
      Root_Deserialization.Deserialize (Reader, Builder, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma
        Assert
          (Builder.Published_Depth = Depth and then Builder.Commit_Count = 1);
   end Check_CBOR_Wrong_Kind;

   procedure Check_JSON_Preflight_Failure is
      Writer : JSON_Writer.Bounded_Writer (1_024);
      Error  : Errors.Error_Info;
   begin
      Root_Serialization.Serialize ((256, Report_Failure), Writer, Error);
      pragma Assert (Error.Code = Errors.Application_Error);
      Assert_Index_Prefix (Error, 256);
      pragma
        Assert (not Writer.Is_Complete and then Writer.Written_Length = 0);
      pragma Assert (Writer.State = Serialization.Poisoned);

      Errors.Reset (Error);
      Writer.Reset;
      Root_Serialization.Serialize ((256, Emit_Null), Writer, Error);
      pragma Assert (Error.Code = Errors.No_Error and then Writer.Is_Complete);
   end Check_JSON_Preflight_Failure;

   procedure Check_CBOR_Preflight_Failure is
      Writer : CBOR_Writer.Bounded_Writer (1_024);
      Error  : Errors.Error_Info;
   begin
      Root_Serialization.Serialize ((256, Report_Failure), Writer, Error);
      pragma Assert (Error.Code = Errors.Application_Error);
      Assert_Index_Prefix (Error, 256);
      pragma
        Assert (not Writer.Is_Complete and then Writer.Written_Length = 0);
      pragma Assert (Writer.State = Serialization.Poisoned);

      Errors.Reset (Error);
      Writer.Reset;
      Root_Serialization.Serialize ((256, Emit_Null), Writer, Error);
      pragma Assert (Error.Code = Errors.No_Error and then Writer.Is_Complete);
   end Check_CBOR_Preflight_Failure;

   procedure Check_Exception_Cleanup is
      JSON_Output : JSON_Writer.Bounded_Writer (1_024);
      CBOR_Output : CBOR_Writer.Bounded_Writer (1_024);
      Error       : Errors.Error_Info;
      Raised      : Boolean := False;
   begin
      begin
         Root_Serialization.Serialize
           ((33, Raise_Exception), JSON_Output, Error);
      exception
         when Program_Error =>
            Raised := True;
      end;
      pragma Assert (Raised);
      pragma Assert (JSON_Output.State = Serialization.Poisoned);
      pragma
        Assert
          (not JSON_Output.Is_Complete
             and then JSON_Output.Written_Length = 0);
      Errors.Clear_Path (Error);
      pragma
        Assert
          (Error.Path_Length = 0 and then Error.Omitted_Path_Elements = 0);
      JSON_Output.Reset;
      Errors.Reset (Error);
      Root_Serialization.Serialize ((33, Emit_Null), JSON_Output, Error);
      pragma
        Assert (Error.Code = Errors.No_Error and then JSON_Output.Is_Complete);

      Raised := False;
      begin
         Root_Serialization.Serialize
           ((33, Raise_Exception), CBOR_Output, Error);
      exception
         when Program_Error =>
            Raised := True;
      end;
      pragma Assert (Raised);
      pragma Assert (CBOR_Output.State = Serialization.Poisoned);
      pragma
        Assert
          (not CBOR_Output.Is_Complete
             and then CBOR_Output.Written_Length = 0);
      Errors.Clear_Path (Error);
      CBOR_Output.Reset;
      Errors.Reset (Error);
      Root_Serialization.Serialize ((33, Emit_Null), CBOR_Output, Error);
      pragma
        Assert (Error.Code = Errors.No_Error and then CBOR_Output.Is_Complete);

      declare
         Input   : aliased constant String := JSON_Input (33);
         Reader  : JSON_Reader.Reader (Input'Access);
         Builder : Nested_Builder;
      begin
         Builder.Expected_Depth := 33;
         Builder.Leaf_Action := Raise_Leaf;
         Reader.Initialize (Deep_Policy);
         Raised := False;
         begin
            Root_Deserialization.Deserialize (Reader, Builder, Error);
         exception
            when Program_Error =>
               Raised := True;
         end;
         pragma Assert (Raised);
         pragma Assert (Builder.Published_Depth = 777);
         pragma
           Assert (Builder.Rollback_Count = 1 and then Builder.Open_Depth = 0);
         pragma Assert (JSON_Testing.Logical_Depth (Reader) = 0);
         pragma Assert (JSON_Testing.Budget_Depth (Reader) = 0);
         Errors.Clear_Path (Error);
         pragma
           Assert
             (Error.Path_Length = 0 and then Error.Omitted_Path_Elements = 0);

         Errors.Reset (Error);
         Reader.Read_Null (Error);
         pragma Assert (Error.Code = Errors.Invalid_State);

         Builder.Leaf_Action := Read_Null_Leaf;
         Reader.Reset (Deep_Policy);
         Errors.Reset (Error);
         Root_Deserialization.Deserialize (Reader, Builder, Error);
         pragma Assert (Error.Code = Errors.No_Error);
         pragma Assert (Builder.Published_Depth = 33);
      end;

      declare
         Input   : aliased constant Byte_Array := CBOR_Input (33);
         Reader  : CBOR_Reader.Reader (Input'Access);
         Builder : Nested_Builder;
      begin
         Builder.Expected_Depth := 33;
         Builder.Leaf_Action := Raise_Leaf;
         Reader.Initialize (Deep_Policy);
         Raised := False;
         begin
            Root_Deserialization.Deserialize (Reader, Builder, Error);
         exception
            when Program_Error =>
               Raised := True;
         end;
         pragma Assert (Raised);
         pragma Assert (Builder.Published_Depth = 777);
         pragma
           Assert (Builder.Rollback_Count = 1 and then Builder.Open_Depth = 0);
         pragma Assert (CBOR_Testing.Logical_Depth (Reader) = 0);
         pragma Assert (CBOR_Testing.Budget_Depth (Reader) = 0);
         Errors.Clear_Path (Error);

         Errors.Reset (Error);
         Reader.Read_Null (Error);
         pragma Assert (Error.Code = Errors.Invalid_State);

         Builder.Leaf_Action := Read_Null_Leaf;
         Reader.Reset (Deep_Policy);
         Errors.Reset (Error);
         Root_Deserialization.Deserialize (Reader, Builder, Error);
         pragma Assert (Error.Code = Errors.No_Error);
         pragma Assert (Builder.Published_Depth = 33);
      end;
   end Check_Exception_Cleanup;

   procedure Check_Direct_Paths is
      Error     : Errors.Error_Info;
      Long_Name : constant String (17 .. 88) := [others => 'x'];
      Alt_Name  : constant String (41 .. 48) := "selected";
      Last_Name : constant String (Positive'Last - 1 .. Positive'Last) := "xy";

      procedure Assert_Path_Cleared (Item : Errors.Error_Info) is
      begin
         pragma
           Assert
             (Item.Path_Length = 0 and then Item.Omitted_Path_Elements = 0);
         for Index in Item.Path'Range loop
            pragma Assert (Item.Path (Index).Kind = Errors.Field_Element);
            pragma Assert (Item.Path (Index).Index = 0);
            pragma Assert (Item.Path (Index).Name_Length = 0);
            pragma Assert (not Item.Path (Index).Name_Truncated);
            pragma
              Assert
                (Item.Path (Index).Name
                   = String'(1 .. Errors.Maximum_Name_Length => ' '));
         end loop;
      end Assert_Path_Cleared;
   begin
      pragma Assert (Error.Code = Errors.No_Error);
      pragma
        Assert
          (Error.Path_Length = 0 and then Error.Omitted_Path_Elements = 0);
      for Index in Error.Path'Range loop
         pragma Assert (Error.Path (Index).Name_Length = 0);
         pragma Assert (not Error.Path (Index).Name_Truncated);
      end loop;

      Errors.Push_Field (Error, Last_Name);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Error.Path (1).Name (1 .. 2) = "xy");
      Errors.Pop (Error);
      Errors.Push_Alternative (Error, Last_Name);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Error.Path (1).Name (1 .. 2) = "xy");
      Errors.Pop (Error);

      Errors.Push_Field (Error, Long_Name);
      Errors.Push_Alternative (Error, Alt_Name);
      for Index in 3 .. Errors.Maximum_Path_Depth loop
         Errors.Push_Index (Error, Index - 1);
      end loop;
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Error.Path_Length = Errors.Maximum_Path_Depth);
      pragma Assert (Error.Path (1).Kind = Errors.Field_Element);
      pragma Assert (Error.Path (1).Name_Truncated);
      pragma Assert (Error.Path (2).Kind = Errors.Alternative_Element);
      pragma Assert (Error.Path (2).Name (1 .. 8) = "selected");

      Errors.Push_Index (Error, 90);
      Errors.Push_Field (Error, Long_Name);
      Errors.Push_Alternative (Error, Alt_Name);
      pragma
        Assert
          (Error.Code = Errors.No_Error
             and then Error.Omitted_Path_Elements = 3);
      for Index in 1 .. 3 loop
         Errors.Pop (Error);
      end loop;
      pragma Assert (Error.Omitted_Path_Elements = 0);
      for Index in 1 .. Errors.Maximum_Path_Depth loop
         Errors.Pop (Error);
      end loop;
      pragma Assert (Error.Path_Length = 0);

      for Kind in Errors.Path_Element_Kind loop
         Errors.Reset (Error);
         for Index in 1 .. Errors.Maximum_Path_Depth loop
            Errors.Push_Index (Error, Index);
         end loop;
         declare
            Before        : constant Errors.Path_Array := Error.Path;
            Before_Length : constant Natural := Error.Path_Length;
         begin
            case Kind is
               when Errors.Field_Element       =>
                  Errors.Push_Field (Error, "field");

               when Errors.Index_Element       =>
                  Errors.Push_Index (Error, 0);

               when Errors.Alternative_Element =>
                  Errors.Push_Alternative (Error, "alternative");
            end case;
            pragma Assert (Error.Code = Errors.No_Error);
            pragma Assert (Error.Path_Length = Before_Length);
            pragma Assert (Error.Omitted_Path_Elements = 1);
            pragma Assert (Error.Path = Before);
         end;
      end loop;

      Errors.Reset (Error);
      for Index in 1 .. Errors.Maximum_Path_Depth loop
         Errors.Push_Index (Error, Index);
      end loop;
      Error.Omitted_Path_Elements := Natural'Last;
      declare
         Before : constant Errors.Path_Array := Error.Path;
      begin
         Errors.Push_Field (Error, "overflow");
         pragma Assert (Error.Code = Errors.Depth_Exceeded);
         pragma Assert (Error.Path_Length = Errors.Maximum_Path_Depth);
         pragma Assert (Error.Omitted_Path_Elements = Natural'Last);
         pragma Assert (Error.Path = Before);
         Errors.Push_Index (Error, 0);
         Errors.Pop (Error);
         pragma Assert (Error.Code = Errors.Depth_Exceeded);
         pragma Assert (Error.Path_Length = Errors.Maximum_Path_Depth);
         pragma Assert (Error.Omitted_Path_Elements = Natural'Last);
         pragma Assert (Error.Path = Before);
      end;

      Errors.Reset (Error);
      for Index in 1 .. Errors.Maximum_Path_Depth loop
         Errors.Push_Index (Error, Index);
      end loop;
      Error.Omitted_Path_Elements := Natural'Last;
      Errors.Fail (Error, Errors.Syntax_Error, 17, Errors.Byte_Offset);
      declare
         Before : constant Errors.Path_Array := Error.Path;
      begin
         Errors.Push_Field (Error, "field");
         Errors.Push_Index (Error, 0);
         Errors.Push_Alternative (Error, "alternative");
         Errors.Pop (Error);
         pragma Assert (Error.Code = Errors.Syntax_Error);
         pragma Assert (Error.Input_Offset = 17);
         pragma Assert (Error.Path_Length = Errors.Maximum_Path_Depth);
         pragma Assert (Error.Omitted_Path_Elements = Natural'Last);
         pragma Assert (Error.Path = Before);
      end;

      Errors.Reset (Error);
      Error.Omitted_Path_Elements := 1;
      Error.Path (1) :=
        (Kind => Errors.Alternative_Element, Index => 23, others => <>);
      Errors.Fail (Error, Errors.Syntax_Error, 19, Errors.Byte_Offset);
      declare
         Before : constant Errors.Path_Array := Error.Path;
      begin
         Errors.Push_Field (Error, "field");
         Errors.Push_Index (Error, 0);
         Errors.Push_Alternative (Error, "alternative");
         Errors.Pop (Error);
         pragma Assert (Error.Code = Errors.Syntax_Error);
         pragma Assert (Error.Input_Offset = 19);
         pragma Assert (Error.Path_Length = 0);
         pragma Assert (Error.Omitted_Path_Elements = 1);
         pragma Assert (Error.Path = Before);
      end;

      Errors.Reset (Error);
      Error.Omitted_Path_Elements := 1;
      Error.Path (1) :=
        (Kind => Errors.Alternative_Element, Index => 17, others => <>);
      declare
         Before : constant Errors.Path_Array := Error.Path;
      begin
         Errors.Push_Field (Error, "malformed");
         pragma Assert (Error.Code = Errors.Invalid_State);
         pragma
           Assert
             (Error.Path_Length = 0 and then Error.Omitted_Path_Elements = 1);
         pragma Assert (Error.Path = Before);
      end;

      Errors.Reset (Error);
      Error.Omitted_Path_Elements := 1;
      Error.Path (1) :=
        (Kind => Errors.Alternative_Element, Index => 17, others => <>);
      declare
         Before : constant Errors.Path_Array := Error.Path;
      begin
         Errors.Pop (Error);
         pragma Assert (Error.Code = Errors.Invalid_State);
         pragma
           Assert
             (Error.Path_Length = 0 and then Error.Omitted_Path_Elements = 1);
         pragma Assert (Error.Path = Before);
      end;

      --  Clear a valid clean saturated path, including every nondefault slot.
      Errors.Reset (Error);
      Error.Path_Length := Errors.Maximum_Path_Depth;
      Error.Omitted_Path_Elements := 2;
      Error.Path :=
        [others =>
           (Kind           => Errors.Alternative_Element,
            Index          => 99,
            Name_Length    => 5,
            Name_Truncated => True,
            Name           => [others => 'q'])];
      Errors.Clear_Path (Error);
      pragma Assert (Error.Code = Errors.No_Error);
      Assert_Path_Cleared (Error);

      --  Clear caller-forged malformed clean state without interpreting it.
      Error.Omitted_Path_Elements := 1;
      Error.Path :=
        [others =>
           (Kind           => Errors.Index_Element,
            Index          => 7,
            Name_Length    => 3,
            Name_Truncated => True,
            Name           => [others => 'm'])];
      Errors.Clear_Path (Error);
      pragma Assert (Error.Code = Errors.No_Error);
      Assert_Path_Cleared (Error);

      --  Preserve a primary status and position while clearing every slot.
      Error.Path_Length := Errors.Maximum_Path_Depth;
      Error.Omitted_Path_Elements := 1;
      Error.Path :=
        [others =>
           (Kind           => Errors.Alternative_Element,
            Index          => 99,
            Name_Length    => 5,
            Name_Truncated => True,
            Name           => [others => 'q'])];
      Errors.Fail (Error, Errors.Syntax_Error, 91, Errors.Byte_Offset);
      Errors.Clear_Path (Error);
      pragma Assert (Error.Code = Errors.Syntax_Error);
      pragma
        Assert
          (Error.Input_Offset = 91
             and then Error.Offset_Unit = Errors.Byte_Offset);
      Assert_Path_Cleared (Error);
      Errors.Clear_Path (Error);
      pragma
        Assert
          (Error.Code = Errors.Syntax_Error and then Error.Input_Offset = 91);
      Assert_Path_Cleared (Error);
      Errors.Reset (Error);
      pragma Assert (Error.Code = Errors.No_Error);
   end Check_Direct_Paths;
begin
   Check_Direct_Paths;

   for Depth of Success_Depths loop
      Check_JSON_Success (Depth);
      Check_CBOR_Success (Depth);
   end loop;

   for Depth of Failure_Depths loop
      Check_JSON_Wrong_Kind (Depth);
      Check_CBOR_Wrong_Kind (Depth);
   end loop;

   Check_JSON_Preflight_Failure;
   Check_CBOR_Preflight_Failure;
   Check_Exception_Cleanup;
end Error_Path_Saturation_Tests;
