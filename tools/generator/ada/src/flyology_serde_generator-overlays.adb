with Ada.Characters.Handling;
with Ada.Containers.Indefinite_Vectors;
with Ada.Containers.Vectors;
with Ada.Streams;
with Ada.Strings.Unbounded;
with Ada.Unchecked_Deallocation;
with Interfaces.C;
with JSON.Parsers;
with JSON.Types;
with Flyology_Serde_Generator.Hashing;
with System;

package body Flyology_Serde_Generator.Overlays is
   use Ada.Strings.Unbounded;
   use Flyology_Serde_Generator.Diagnostics;
   use Flyology_Serde_Generator.Requests;
   use type Interfaces.C.int;
   use type Interfaces.C.ptrdiff_t;

   Type_IR_Commit_V1 : constant String := "78e6726a80d02b22f573fed3f65538cafd89fc0d";
   Intrinsic_Maximum_JSON_Nesting : constant Positive := 8;
   Intrinsic_Maximum_Number_Bytes : constant Positive := 32;

   package JSON_Values is new JSON.Types
     (Integer_Type         => Long_Long_Integer,
      Float_Type           => Long_Long_Float,
      Maximum_Number_Length => Intrinsic_Maximum_Number_Bytes);

   package JSON_Readers is new JSON.Parsers
     (Types                 => JSON_Values,
      Default_Maximum_Depth => Intrinsic_Maximum_JSON_Nesting + 1,
      Check_Duplicate_Keys  => False);

   use type JSON_Values.Value_Kind;

   type Field_Data is record
      Ada_Component    : Unbounded_String;
      Ada_Type         : Unbounded_String;
      Component_ID     : Unbounded_String;
      Presentation_Name : Unbounded_String;
   end record;

   package Field_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Field_Data);

   package String_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Unbounded_String);

   type Overlay_Data is record
      Fixture_Only                : Boolean := False;
      Output_Unit                 : Unbounded_String;
      Type_IR_Commit              : Unbounded_String;
      Type_IR_Semantic_Fingerprint : Unbounded_String;
      Type_IR_Source_SHA256       : Unbounded_String;
      Source_SHA256               : Unbounded_String;
      Limits                      : Serialization_Limits := (others => 0);
      With_Units                  : String_Vectors.Vector;
      Record_Ada_Type             : Unbounded_String;
      Record_Declaration_ID       : Unbounded_String;
      Record_Logical_Type_Name    : Unbounded_String;
      Fields                      : Field_Vectors.Vector;
   end record;

   procedure Free is new Ada.Unchecked_Deallocation
     (Object => Overlay_Data,
      Name   => Overlay_Data_Access);

   procedure Discard (Value : in out Overlay_Data_Access) is
      Detached : Overlay_Data_Access := Value;
   begin
      Value := null;
      Free (Detached);
   exception
      when others =>
         null;
   end Discard;

   Invalid_JSON         : exception;
   Noncanonical_JSON    : exception;
   Unsupported_Document : exception;
   Exhausted            : exception;
   Input_Error          : exception;

   type Count_Value is range 0 .. Long_Long_Integer'Last;

   package Key_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => String);

   function Is_ASCII_Letter (Value : Character) return Boolean is
     (Value in 'A' .. 'Z' or else Value in 'a' .. 'z');

   function Is_ASCII_Digit (Value : Character) return Boolean is
     (Value in '0' .. '9');

   procedure Preflight
     (Source : String;
      Budget : in out Operation_Budget)
   is
      Limits : constant Generation_Limits := Budget_Limits (Budget);
      Offset : Natural := 0;
      Depth  : Natural := 0;

      procedure Must_Charge_Work (Units : Natural) is
         Accepted : Boolean;
      begin
         Charge_Work (Budget, Units, Accepted);
         if not Accepted then
            raise Exhausted;
         end if;
      end Must_Charge_Work;

      procedure Charge_Node is
         Accepted : Boolean;
      begin
         Charge_Overlay_Node (Budget, Accepted);
         if not Accepted then
            raise Exhausted;
         end if;
         Must_Charge_Work (1);
      end Charge_Node;

      function Has_More return Boolean is (Offset < Source'Length);

      function Current return Character is
        (Source (Source'First + Integer (Offset)));

      procedure Advance is
      begin
         if not Has_More then
            raise Invalid_JSON;
         end if;
         Offset := Offset + 1;
      end Advance;

      procedure Skip_Whitespace is
      begin
         while Has_More and then Current in ' ' | ASCII.HT | ASCII.LF | ASCII.CR loop
            Advance;
         end loop;
      end Skip_Whitespace;

      procedure Expect (Text : String) is
      begin
         for Item of Text loop
            if not Has_More or else Current /= Item then
               raise Invalid_JSON;
            end if;
            Advance;
         end loop;
      end Expect;

      procedure Parse_String (Value : out Unbounded_String) is
         Decoded : Count_Value := 0;
      begin
         Value := Null_Unbounded_String;
         Expect ("""");
         while Has_More and then Current /= '"' loop
            declare
               Item : Character := Current;
            begin
               if Character'Pos (Item) < 32 or else Character'Pos (Item) > 127 then
                  raise Invalid_JSON;
               elsif Item = '\' then
                  Advance;
                  if not Has_More or else Current not in '"' | '\' | '/' | 'b' | 'f' | 'n' | 'r' | 't' then
                     raise Invalid_JSON;
                  end if;
                  Item :=
                    (case Current is
                       when 'b'    => Character'Val (8),
                       when 'f'    => Character'Val (12),
                       when 'n'    => ASCII.LF,
                       when 'r'    => ASCII.CR,
                       when 't'    => ASCII.HT,
                       when others => Current);
               end if;
               if Decoded >= Count_Value (Limits.Maximum_Decoded_String_Bytes) then
                  raise Exhausted;
               end if;
               Decoded := Decoded + 1;
               Append (Value, Item);
               Advance;
            end;
         end loop;
         Expect ("""");
      end Parse_String;

      procedure Parse_Value;

      procedure Enter_Container is
      begin
         if Depth = Intrinsic_Maximum_JSON_Nesting
           or else Limit_Value (Depth + 1) > Limits.Maximum_JSON_Nesting
         then
            raise Exhausted;
         end if;
         Depth := Depth + 1;
      end Enter_Container;

      procedure Parse_Object is
         Keys    : Key_Vectors.Vector;
         Members : Count_Value := 0;
      begin
         Expect ("{");
         Enter_Container;
         Skip_Whitespace;
         if Has_More and then Current = '}' then
            Advance;
            Depth := Depth - 1;
            return;
         end if;
         loop
            if Members >= Count_Value (Limits.Maximum_Object_Members) then
               raise Exhausted;
            end if;
            declare
               Key : Unbounded_String;
            begin
               Parse_String (Key);
               for Prior of Keys loop
                  Must_Charge_Work (Natural'Min (Prior'Length, Length (Key)) + 1);
                  if Prior = To_String (Key) then
                     raise Invalid_JSON;
                  end if;
               end loop;
               Keys.Append (To_String (Key));
            end;
            Skip_Whitespace;
            Expect (":");
            Skip_Whitespace;
            Parse_Value;
            Members := Members + 1;
            Skip_Whitespace;
            if Has_More and then Current = '}' then
               Advance;
               exit;
            end if;
            Expect (",");
            Skip_Whitespace;
         end loop;
         Depth := Depth - 1;
      end Parse_Object;

      procedure Parse_Array is
         Elements : Count_Value := 0;
      begin
         Expect ("[");
         Enter_Container;
         Skip_Whitespace;
         if Has_More and then Current = ']' then
            Advance;
            Depth := Depth - 1;
            return;
         end if;
         loop
            if Elements >= Count_Value (Limits.Maximum_Array_Elements) then
               raise Exhausted;
            end if;
            Parse_Value;
            Elements := Elements + 1;
            Skip_Whitespace;
            if Has_More and then Current = ']' then
               Advance;
               exit;
            end if;
            Expect (",");
            Skip_Whitespace;
         end loop;
         Depth := Depth - 1;
      end Parse_Array;

      procedure Parse_Number is
         Start : constant Natural := Offset;
      begin
         if Current = '-' then
            Advance;
         end if;
         if not Has_More then
            raise Invalid_JSON;
         elsif Current = '0' then
            Advance;
            if Has_More and then Current in '0' .. '9' then
               raise Invalid_JSON;
            end if;
         elsif Current in '1' .. '9' then
            while Has_More and then Current in '0' .. '9' loop
               Advance;
            end loop;
         else
            raise Invalid_JSON;
         end if;
         if Has_More and then Current = '.' then
            Advance;
            if not Has_More or else Current not in '0' .. '9' then
               raise Invalid_JSON;
            end if;
            while Has_More and then Current in '0' .. '9' loop
               Advance;
            end loop;
         end if;
         if Has_More and then Current in 'e' | 'E' then
            Advance;
            if Has_More and then Current in '+' | '-' then
               Advance;
            end if;
            if not Has_More or else Current not in '0' .. '9' then
               raise Invalid_JSON;
            end if;
            while Has_More and then Current in '0' .. '9' loop
               Advance;
            end loop;
         end if;
         if Limit_Value (Offset - Start) > Limits.Maximum_Number_Token_Bytes then
            raise Exhausted;
         end if;
      end Parse_Number;

      procedure Parse_Value is
         Ignored : Unbounded_String;
      begin
         if not Has_More then
            raise Invalid_JSON;
         end if;
         case Current is
            when '{' =>
               Parse_Object;
            when '[' =>
               Parse_Array;
            when '"' =>
               Parse_String (Ignored);
            when '-' | '0' .. '9' =>
               Parse_Number;
            when 't' =>
               Expect ("true");
            when 'f' =>
               Expect ("false");
            when 'n' =>
               Expect ("null");
            when others =>
               raise Invalid_JSON;
         end case;
         Charge_Node;
      end Parse_Value;
   begin
      if Limit_Value (Source'Length) > Limits.Maximum_Input_Bytes_Per_File
      then
         raise Exhausted;
      end if;
      Must_Charge_Work (Source'Length);
      Skip_Whitespace;
      Parse_Value;
      Skip_Whitespace;
      if Has_More or else Depth /= 0 then
         raise Invalid_JSON;
      end if;
   end Preflight;

   function Open_No_Follow (Path : System.Address) return Interfaces.C.int
     with Import,
          Convention    => C,
          External_Name => "flyology_serde_open_nofollow";

   function Is_Regular (File : Interfaces.C.int) return Interfaces.C.int
     with Import,
          Convention    => C,
          External_Name => "flyology_serde_is_regular";

   function POSIX_Read
     (File   : Interfaces.C.int;
      Buffer : System.Address;
      Count  : Interfaces.C.size_t) return Interfaces.C.ptrdiff_t
     with Import,
          Convention    => C,
          External_Name => "read";

   function POSIX_Close (File : Interfaces.C.int) return Interfaces.C.int
     with Import,
          Convention    => C,
          External_Name => "close";

   procedure Close_Discard (File : in out Interfaces.C.int) is
      Detached : constant Interfaces.C.int := File;
      Ignored  : Interfaces.C.int;
   begin
      File := -1;
      if Detached >= 0 then
         Ignored := POSIX_Close (Detached);
      end if;
   exception
      when others =>
         null;
   end Close_Discard;

   function Read_Source
     (Path   : String;
      Budget : in out Operation_Budget) return String
   is
      Limits : constant Generation_Limits := Budget_Limits (Budget);
      File   : Interfaces.C.int := -1;
      Result : Unbounded_String;
      Buffer : aliased Ada.Streams.Stream_Element_Array (1 .. 4_096);
   begin
      if Path'Length = 0 or else (for some Item of Path => Item = ASCII.NUL) then
         raise Input_Error;
      elsif Limit_Value (Path'Length) > Limits.Maximum_Path_Bytes then
         raise Exhausted;
      end if;

      declare
         C_Path : aliased Interfaces.C.char_array := Interfaces.C.To_C (Path);
      begin
         File := Open_No_Follow (C_Path'Address);
      end;
      if File < 0 then
         raise Input_Error;
      elsif Is_Regular (File) /= 1 then
         Close_Discard (File);
         raise Input_Error;
      end if;

      loop
         declare
            Read_Count : constant Interfaces.C.ptrdiff_t :=
              POSIX_Read (File, Buffer'Address, Interfaces.C.size_t (Buffer'Length));
         begin
            if Read_Count < 0 then
               raise Input_Error;
            elsif Read_Count = 0 then
               exit;
            end if;
            declare
               Added    : constant Natural := Natural (Read_Count);
               Accepted : Boolean;
            begin
               if Length (Result) > Natural'Last - Added
                 or else Limit_Value (Length (Result) + Added) > Limits.Maximum_Input_Bytes_Per_File
               then
                  raise Exhausted;
               end if;
               Charge_Input (Budget, Added, Accepted);
               if not Accepted then
                  raise Exhausted;
               end if;
               for Index in 1 .. Added loop
                  Append (Result, Character'Val (Buffer (Ada.Streams.Stream_Element_Offset (Index))));
               end loop;
            end;
         end;
      end loop;

      if POSIX_Close (File) /= 0 then
         File := -1;
         raise Input_Error;
      end if;
      File := -1;
      return To_String (Result);
   exception
      when Exhausted | Storage_Error =>
         Close_Discard (File);
         raise;
      when others =>
         Close_Discard (File);
         raise Input_Error;
   end Read_Source;

   procedure Require_Object (Value : JSON_Values.JSON_Value; Member_Count : Natural) is
   begin
      if Value.Kind /= JSON_Values.Object_Kind or else JSON_Values.Length (Value) /= Member_Count then
         raise Unsupported_Document;
      end if;
   end Require_Object;

   procedure Require_Array (Value : JSON_Values.JSON_Value; Minimum, Maximum : Natural) is
      Length : Natural;
   begin
      if Value.Kind /= JSON_Values.Array_Kind then
         raise Unsupported_Document;
      end if;
      Length := JSON_Values.Length (Value);
      if Length < Minimum or else Length > Maximum then
         raise Unsupported_Document;
      end if;
   end Require_Array;

   procedure Require_Keys
     (Value : JSON_Values.JSON_Value;
      One   : String;
      Two   : String := "";
      Three : String := "";
      Four  : String := "";
      Five  : String := "";
      Six   : String := "";
      Seven : String := "";
      Eight : String := "";
      Nine  : String := "")
   is
      procedure Require (Key : String) is
      begin
         if Key'Length > 0 and then not JSON_Values.Contains (Value, Key) then
            raise Unsupported_Document;
         end if;
      end Require;
   begin
      Require (One);
      Require (Two);
      Require (Three);
      Require (Four);
      Require (Five);
      Require (Six);
      Require (Seven);
      Require (Eight);
      Require (Nine);
   end Require_Keys;

   function Read_String (Object : JSON_Values.JSON_Value; Key : String) return String is
      Value : constant JSON_Values.JSON_Value := JSON_Values.Get (Object, Key);
   begin
      if Value.Kind /= JSON_Values.String_Kind then
         raise Unsupported_Document;
      end if;
      return JSON_Values.Value (Value);
   end Read_String;

   function Read_Integer (Object : JSON_Values.JSON_Value; Key : String) return Long_Long_Integer is
      Value : constant JSON_Values.JSON_Value := JSON_Values.Get (Object, Key);
   begin
      if Value.Kind /= JSON_Values.Integer_Kind then
         raise Unsupported_Document;
      end if;
      return JSON_Values.Value (Value);
   end Read_Integer;

   function Read_Boolean (Object : JSON_Values.JSON_Value; Key : String) return Boolean is
      Value : constant JSON_Values.JSON_Value := JSON_Values.Get (Object, Key);
   begin
      if Value.Kind /= JSON_Values.Boolean_Kind then
         raise Unsupported_Document;
      end if;
      return JSON_Values.Value (Value);
   end Read_Boolean;

   procedure Require_Printable_ASCII (Value : String; Allow_Empty : Boolean := False) is
   begin
      if (not Allow_Empty and then Value'Length = 0)
        or else (for some Item of Value => Character'Pos (Item) < 32 or else Character'Pos (Item) > 126)
      then
         raise Unsupported_Document;
      end if;
   end Require_Printable_ASCII;

   procedure Require_Selected_Name (Value : String) is
      Segment_Start : Positive := Value'First;
   begin
      if Value'Length = 0 or else Value'Length > 48 then
         raise Unsupported_Document;
      end if;
      for Index in Value'Range loop
         if Index = Segment_Start then
            if not Is_ASCII_Letter (Value (Index)) then
               raise Unsupported_Document;
            end if;
         elsif Value (Index) = '.' then
            if Value (Index - 1) = '_' or else Index = Value'Last then
               raise Unsupported_Document;
            end if;
            Segment_Start := Index + 1;
         elsif not Is_ASCII_Letter (Value (Index))
           and then not Is_ASCII_Digit (Value (Index))
           and then Value (Index) /= '_'
         then
            raise Unsupported_Document;
         elsif Value (Index) = '_'
           and then (Value (Index - 1) = '_' or else Index = Value'Last)
         then
            raise Unsupported_Document;
         end if;
      end loop;

      declare
         Start : Positive := Value'First;
      begin
         for Index in Value'Range loop
            if Value (Index) = '.' or else Index = Value'Last then
               declare
                  Last : constant Positive := (if Value (Index) = '.' then Index - 1 else Index);
                  Word : constant String := Ada.Characters.Handling.To_Lower (Value (Start .. Last));
               begin
                  if Word in "abort" | "abs" | "abstract" | "accept" | "access" | "aliased" |
                    "all" | "and" | "array" | "at" | "begin" | "body" | "case" | "constant" |
                    "declare" | "delay" | "delta" | "digits" | "do" | "else" | "elsif" | "end" |
                    "entry" | "exception" | "exit" | "for" | "function" | "generic" | "goto" |
                    "if" | "in" | "interface" | "is" | "limited" | "loop" | "mod" | "new" |
                    "not" | "null" | "of" | "or" | "others" | "out" | "overriding" | "package" |
                    "parallel" | "pragma" | "private" | "procedure" | "protected" | "raise" |
                    "range" | "record" | "rem" | "renames" | "requeue" | "return" | "reverse" |
                    "select" | "separate" | "some" | "subtype" | "synchronized" | "tagged" |
                    "task" | "terminate" | "then" | "type" | "until" | "use" | "when" | "while" |
                    "with" | "xor"
                  then
                     raise Unsupported_Document;
                  end if;
               end;
               Start := Index + 1;
            end if;
         end loop;
      end;
   end Require_Selected_Name;

   procedure Require_Logical_Name (Value : String) is
      Escaped_Length : Natural := 2;
   begin
      Require_Printable_ASCII (Value);
      if Value'Length > 64 then
         raise Unsupported_Document;
      end if;
      for Item of Value loop
         Escaped_Length := Escaped_Length + (if Item = '"' then 2 else 1);
      end loop;
      if Escaped_Length > 58 then
         raise Unsupported_Document;
      end if;
   end Require_Logical_Name;

   procedure Require_SHA256 (Value : String) is
   begin
      if Value'Length /= 64
        or else (for some Item of Value => Item not in '0' .. '9' | 'a' .. 'f')
      then
         raise Unsupported_Document;
      end if;
   end Require_SHA256;

   function Read_Runtime_Limit
     (Object  : JSON_Values.JSON_Value;
      Key     : String;
      Maximum : Natural := 2_147_483_647) return Natural
   is
      Value : constant Long_Long_Integer := Read_Integer (Object, Key);
   begin
      if Value < 0 or else Value > Long_Long_Integer (Maximum) then
         raise Unsupported_Document;
      end if;
      return Natural (Value);
   end Read_Runtime_Limit;

   function Bounded_Natural (Value : Limit_Value) return Natural is
     (if Value > Limit_Value (Natural'Last)
      then Natural'Last
      else Natural (Value));

   function Effective_JSON_Depth (Value : Limit_Value) return Positive is
     (if Value >= Limit_Value (Intrinsic_Maximum_JSON_Nesting)
      then Intrinsic_Maximum_JSON_Nesting
      else Positive (Value));

   procedure Must_Charge_Work
     (Budget : in out Operation_Budget;
      Units  : Natural)
   is
      Accepted : Boolean;
   begin
      Charge_Work (Budget, Units, Accepted);
      if not Accepted then
         raise Exhausted;
      end if;
   end Must_Charge_Work;

   function Parse_Document
     (Source : String;
      Limits : Generation_Limits;
      Budget : in out Operation_Budget) return Overlay_Data_Access
   is
      Parser : JSON_Readers.Parser :=
        JSON_Readers.Create
          (Source,
           Maximum_Depth =>
             Effective_JSON_Depth (Limits.Maximum_JSON_Nesting) + 1);
      Root      : constant JSON_Values.JSON_Value := JSON_Readers.Parse (Parser);
      Candidate : Overlay_Data_Access := new Overlay_Data;
   begin
      Require_Object (Root, 9);
      Require_Keys
        (Root,
         "fixture_only",
         "output_unit",
         "overlay_version",
         "records",
         "serialization_limits",
         "type_ir_commit",
         "type_ir_semantic_fingerprint",
         "type_ir_source_sha256",
         "with_units");

      if Read_Integer (Root, "overlay_version") /= 1 then
         raise Unsupported_Document;
      end if;
      Candidate.Fixture_Only := Read_Boolean (Root, "fixture_only");

      declare
         Output_Unit : constant String := Read_String (Root, "output_unit");
         Commit      : constant String := Read_String (Root, "type_ir_commit");
         Semantic    : constant String := Read_String (Root, "type_ir_semantic_fingerprint");
         Source_Hash : constant String := Read_String (Root, "type_ir_source_sha256");
      begin
         Require_Selected_Name (Output_Unit);
         if Commit /= Type_IR_Commit_V1 then
            raise Unsupported_Document;
         end if;
         Require_SHA256 (Semantic);
         Require_SHA256 (Source_Hash);
         Candidate.Output_Unit := To_Unbounded_String (Output_Unit);
         Candidate.Type_IR_Commit := To_Unbounded_String (Commit);
         Candidate.Type_IR_Semantic_Fingerprint := To_Unbounded_String (Semantic);
         Candidate.Type_IR_Source_SHA256 := To_Unbounded_String (Source_Hash);
      end;

      declare
         JSON_Limits : constant JSON_Values.JSON_Value :=
           JSON_Values.Get (Root, "serialization_limits");
      begin
         Require_Object (JSON_Limits, 5);
         Require_Keys
           (JSON_Limits,
            "maximum_byte_length",
            "maximum_container_items",
            "maximum_logical_events",
            "maximum_nesting_depth",
            "maximum_text_length");
         Candidate.Limits :=
           (Maximum_Byte_Length     => Read_Runtime_Limit (JSON_Limits, "maximum_byte_length"),
            Maximum_Container_Items => Read_Runtime_Limit (JSON_Limits, "maximum_container_items"),
            Maximum_Logical_Events  => Read_Runtime_Limit (JSON_Limits, "maximum_logical_events"),
            Maximum_Nesting_Depth   => Read_Runtime_Limit (JSON_Limits, "maximum_nesting_depth", 256),
            Maximum_Text_Length     => Read_Runtime_Limit (JSON_Limits, "maximum_text_length"));
      end;

      declare
         Units : constant JSON_Values.JSON_Value := JSON_Values.Get (Root, "with_units");
      begin
         Require_Array (Units, 1, Bounded_Natural (Limits.Maximum_Array_Elements));
         for Index in 1 .. JSON_Values.Length (Units) loop
            declare
               Item : constant JSON_Values.JSON_Value := JSON_Values.Get (Units, Index);
            begin
               if Item.Kind /= JSON_Values.String_Kind then
                  raise Unsupported_Document;
               end if;
               declare
                  Unit_Name : constant String := JSON_Values.Value (Item);
                  Folded    : constant String := Ada.Characters.Handling.To_Lower (Unit_Name);
               begin
                  Require_Selected_Name (Unit_Name);
                  for Existing of Candidate.With_Units loop
                     Must_Charge_Work
                       (Budget, Natural'Min (Length (Existing), Unit_Name'Length) + 1);
                     if Ada.Characters.Handling.To_Lower (To_String (Existing)) = Folded then
                        raise Unsupported_Document;
                     end if;
                  end loop;
                  Candidate.With_Units.Append (To_Unbounded_String (Unit_Name));
               end;
            end;
         end loop;
      end;

      declare
         Records : constant JSON_Values.JSON_Value := JSON_Values.Get (Root, "records");
      begin
         Require_Array (Records, 1, 1);
         declare
            Item : constant JSON_Values.JSON_Value := JSON_Values.Get (Records, 1);
         begin
            Require_Object (Item, 4);
            Require_Keys (Item, "ada_type", "declaration_id", "fields", "logical_type_name");
            declare
               Ada_Type     : constant String := Read_String (Item, "ada_type");
               Declaration  : constant String := Read_String (Item, "declaration_id");
               Logical_Name : constant String := Read_String (Item, "logical_type_name");
               Fields       : constant JSON_Values.JSON_Value := JSON_Values.Get (Item, "fields");
            begin
               Require_Selected_Name (Ada_Type);
               Require_Printable_ASCII (Declaration);
               Require_Logical_Name (Logical_Name);
               Require_Array (Fields, 1, Bounded_Natural (Limits.Maximum_Array_Elements));
               Candidate.Record_Ada_Type := To_Unbounded_String (Ada_Type);
               Candidate.Record_Declaration_ID := To_Unbounded_String (Declaration);
               Candidate.Record_Logical_Type_Name := To_Unbounded_String (Logical_Name);

               for Index in 1 .. JSON_Values.Length (Fields) loop
                  declare
                     Field : constant JSON_Values.JSON_Value := JSON_Values.Get (Fields, Index);
                  begin
                     Require_Object (Field, 4);
                     Require_Keys
                       (Field, "ada_component", "ada_type", "component_id", "presentation_name");
                     declare
                        Ada_Component : constant String := Read_String (Field, "ada_component");
                        Field_Type    : constant String := Read_String (Field, "ada_type");
                        Component_ID  : constant String := Read_String (Field, "component_id");
                        Presentation  : constant String := Read_String (Field, "presentation_name");
                     begin
                        Require_Selected_Name (Ada_Component);
                        Require_Selected_Name (Field_Type);
                        Require_Printable_ASCII (Component_ID);
                        Require_Logical_Name (Presentation);
                        for Existing of Candidate.Fields loop
                           Must_Charge_Work
                             (Budget,
                              Natural'Min (Length (Existing.Component_ID), Component_ID'Length) + 1);
                           Must_Charge_Work
                             (Budget,
                              Natural'Min
                                (Length (Existing.Presentation_Name), Presentation'Length) + 1);
                           if To_String (Existing.Component_ID) = Component_ID
                             or else To_String (Existing.Presentation_Name) = Presentation
                           then
                              raise Unsupported_Document;
                           end if;
                        end loop;
                        Candidate.Fields.Append
                          (New_Item =>
                             Field_Data'
                               (Ada_Component     => To_Unbounded_String (Ada_Component),
                                Ada_Type          => To_Unbounded_String (Field_Type),
                                Component_ID      => To_Unbounded_String (Component_ID),
                                Presentation_Name => To_Unbounded_String (Presentation)));
                     end;
                  end;
               end loop;
            end;
         end;
      end;
      return Candidate;
   exception
      when others =>
         Discard (Candidate);
         raise;
   end Parse_Document;

   procedure Append_Checked
     (Into    : in out Unbounded_String;
      Item    : String;
      Maximum : Natural;
      Budget  : in out Operation_Budget)
   is
   begin
      if Length (Into) > Maximum or else Item'Length > Maximum - Length (Into) then
         raise Noncanonical_JSON;
      end if;
      Must_Charge_Work (Budget, Item'Length);
      Append (Into, Item);
   end Append_Checked;

   procedure Append_JSON_String
     (Into    : in out Unbounded_String;
      Item    : String;
      Maximum : Natural;
      Budget  : in out Operation_Budget)
   is
   begin
      Append_Checked (Into, """", Maximum, Budget);
      for Character_Value of Item loop
         if Character_Value in '"' | '\' then
            Append_Checked (Into, "\" & Character_Value, Maximum, Budget);
         else
            Append_Checked (Into, String'(1 => Character_Value), Maximum, Budget);
         end if;
      end loop;
      Append_Checked (Into, """", Maximum, Budget);
   end Append_JSON_String;

   function Natural_Image (Value : Natural) return String is
      Image : constant String := Natural'Image (Value);
   begin
      return Image (Image'First + 1 .. Image'Last);
   end Natural_Image;

   function Canonical
     (Value   : Overlay_Data;
      Maximum : Natural;
      Budget  : in out Operation_Budget) return String
   is
      Result : Unbounded_String;

      procedure Put (Text : String) is
      begin
         Append_Checked (Result, Text, Maximum, Budget);
      end Put;

      procedure Put_String (Text : String) is
      begin
         Append_JSON_String (Result, Text, Maximum, Budget);
      end Put_String;
   begin
      Put ("{""fixture_only"":");
      Put ((if Value.Fixture_Only then "true" else "false"));
      Put (",");
      Put_String ("output_unit");
      Put (":");
      Put_String (To_String (Value.Output_Unit));
      Put (",");
      Put_String ("overlay_version");
      Put (":1,");
      Put_String ("records");
      Put (":[{");
      Put_String ("ada_type");
      Put (":");
      Put_String (To_String (Value.Record_Ada_Type));
      Put (",");
      Put_String ("declaration_id");
      Put (":");
      Put_String (To_String (Value.Record_Declaration_ID));
      Put (",");
      Put_String ("fields");
      Put (":[");
      for Index in 1 .. Natural (Value.Fields.Length) loop
         if Index > 1 then
            Put (",");
         end if;
         declare
            Field : constant Field_Data := Value.Fields.Element (Index);
         begin
            Put ("{");
            Put_String ("ada_component");
            Put (":");
            Put_String (To_String (Field.Ada_Component));
            Put (",");
            Put_String ("ada_type");
            Put (":");
            Put_String (To_String (Field.Ada_Type));
            Put (",");
            Put_String ("component_id");
            Put (":");
            Put_String (To_String (Field.Component_ID));
            Put (",");
            Put_String ("presentation_name");
            Put (":");
            Put_String (To_String (Field.Presentation_Name));
            Put ("}");
         end;
      end loop;
      Put ("],");
      Put_String ("logical_type_name");
      Put (":");
      Put_String (To_String (Value.Record_Logical_Type_Name));
      Put ("}],");
      Put_String ("serialization_limits");
      Put (":{");
      Put_String ("maximum_byte_length");
      Put (":" & Natural_Image (Value.Limits.Maximum_Byte_Length) & ",");
      Put_String ("maximum_container_items");
      Put (":" & Natural_Image (Value.Limits.Maximum_Container_Items) & ",");
      Put_String ("maximum_logical_events");
      Put (":" & Natural_Image (Value.Limits.Maximum_Logical_Events) & ",");
      Put_String ("maximum_nesting_depth");
      Put (":" & Natural_Image (Value.Limits.Maximum_Nesting_Depth) & ",");
      Put_String ("maximum_text_length");
      Put (":" & Natural_Image (Value.Limits.Maximum_Text_Length) & "},");
      Put_String ("type_ir_commit");
      Put (":");
      Put_String (To_String (Value.Type_IR_Commit));
      Put (",");
      Put_String ("type_ir_semantic_fingerprint");
      Put (":");
      Put_String (To_String (Value.Type_IR_Semantic_Fingerprint));
      Put (",");
      Put_String ("type_ir_source_sha256");
      Put (":");
      Put_String (To_String (Value.Type_IR_Source_SHA256));
      Put (",");
      Put_String ("with_units");
      Put (":[");
      for Index in 1 .. Natural (Value.With_Units.Length) loop
         if Index > 1 then
            Put (",");
         end if;
         Put_String (To_String (Value.With_Units.Element (Index)));
      end loop;
      Put ("]}" & ASCII.LF);
      return To_String (Result);
   end Canonical;

   procedure Decode_Source
     (Source             : String;
      Charge_Input_Bytes : Boolean;
      Budget             : in out Operation_Budget;
      Into               : in out Overlay_Document;
      Diagnostic         : out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
      Limits    : constant Generation_Limits := Budget_Limits (Budget);
      Candidate : Overlay_Data_Access := null;
      Previous  : Overlay_Data_Access := null;
      Accepted  : Boolean;
   begin
      Clear (Diagnostic);
      if Charge_Input_Bytes then
         if Limit_Value (Source'Length) > Limits.Maximum_Input_Bytes_Per_File then
            raise Exhausted;
         end if;
         Charge_Input (Budget, Source'Length, Accepted);
         if not Accepted then
            raise Exhausted;
         end if;
      end if;
      Preflight (Source, Budget);
      Must_Charge_Work (Budget, Source'Length);
      Candidate := Parse_Document (Source, Limits, Budget);
      declare
         Encoded : constant String := Canonical (Candidate.all, Source'Length, Budget);
      begin
         Must_Charge_Work (Budget, Natural'Min (Source'Length, Encoded'Length) + 1);
         if Source /= Encoded then
            raise Noncanonical_JSON;
         end if;
      end;
      Must_Charge_Work (Budget, Source'Length);
      Candidate.Source_SHA256 :=
        To_Unbounded_String (Flyology_Serde_Generator.Hashing.SHA_256 (Source));
      Previous := Into.Data;
      Into.Data := Candidate;
      Candidate := null;
      Discard (Previous);
   exception
      when Exhausted | Storage_Error =>
         Discard (Candidate);
         Poison (Budget);
         Set (Diagnostic, Resource_Exhausted);
      when Noncanonical_JSON =>
         Discard (Candidate);
         Set (Diagnostic, Noncanonical_Overlay);
      when Unsupported_Document =>
         Discard (Candidate);
         Set (Diagnostic, Unsupported_Overlay);
      when Invalid_JSON | JSON_Readers.Parse_Error =>
         Discard (Candidate);
         Set (Diagnostic, Invalid_Overlay_JSON);
      when others =>
         Discard (Candidate);
         Set (Diagnostic, Internal_Error);
   end Decode_Source;

   procedure Load_Checked
     (Path       : String;
      Budget     : in out Operation_Budget;
      Into       : in out Overlay_Document;
      Diagnostic : out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
   begin
      Clear (Diagnostic);
      declare
         Source : constant String := Read_Source (Path, Budget);
      begin
         Decode_Source (Source, False, Budget, Into, Diagnostic);
      end;
   exception
      when Exhausted | Storage_Error =>
         Poison (Budget);
         Set (Diagnostic, Resource_Exhausted);
      when Input_Error =>
         Set (Diagnostic, Input_IO_Error);
      when others =>
         Set (Diagnostic, Internal_Error);
   end Load_Checked;

   procedure Decode_Checked
     (Source     : String;
      Budget     : in out Operation_Budget;
      Into       : in out Overlay_Document;
      Diagnostic : out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
   begin
      Decode_Source (Source, True, Budget, Into, Diagnostic);
   end Decode_Checked;

   function Is_Valid (Value : Overlay_Document) return Boolean is
     (Value.Data /= null);

   function Ready_For_Query
     (Budget     : in out Operation_Budget;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic) return Boolean
   is
   begin
      if Code (Diagnostic) /= No_Error then
         return False;
      elsif Is_Poisoned (Budget) then
         Set (Diagnostic, Resource_Exhausted);
         return False;
      end if;
      return True;
   end Ready_For_Query;

   function Reserve_Query_Work
     (Budget     : in out Operation_Budget;
      Units      : Natural;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic) return Boolean
   is
      Accepted : Boolean;
   begin
      if not Ready_For_Query (Budget, Diagnostic) then
         return False;
      end if;
      Charge_Work (Budget, Units, Accepted);
      if not Accepted then
         Set (Diagnostic, Resource_Exhausted);
      end if;
      return Accepted;
   end Reserve_Query_Work;

   procedure Read_Text_Length
     (Source     : Unbounded_String;
      Budget     : in out Operation_Budget;
      Length     : in out Natural;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
   begin
      if Reserve_Query_Work (Budget, 1, Diagnostic) then
         Length := Ada.Strings.Unbounded.Length (Source);
      end if;
   end Read_Text_Length;

   procedure Copy_Text
     (Source     : Unbounded_String;
      Budget     : in out Operation_Budget;
      Into       : in out String;
      Written    : in out Natural;
      Copied     : in out Boolean;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
      Count : Natural;
   begin
      if not Reserve_Query_Work (Budget, 1, Diagnostic) then
         return;
      end if;
      Count := Ada.Strings.Unbounded.Length (Source);
      if Into'Length < Count then
         Copied := False;
         return;
      elsif not Reserve_Query_Work (Budget, Count, Diagnostic) then
         return;
      end if;
      for Position in 1 .. Count loop
         Into (Into'First - 1 + Position) := Element (Source, Position);
      end loop;
      Written := Count;
      Copied := True;
   end Copy_Text;

   procedure Read_Fixture_Only
     (Value      : Overlay_Document;
      Budget     : in out Operation_Budget;
      Result     : in out Boolean;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
   begin
      if Reserve_Query_Work (Budget, 1, Diagnostic) then
         Result := Value.Data.Fixture_Only;
      end if;
   end Read_Fixture_Only;

   procedure Read_Runtime_Limits
     (Value      : Overlay_Document;
      Budget     : in out Operation_Budget;
      Result     : in out Serialization_Limits;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
   begin
      if Reserve_Query_Work (Budget, 1, Diagnostic) then
         Result := Value.Data.Limits;
      end if;
   end Read_Runtime_Limits;

   procedure Read_With_Unit_Count
     (Value      : Overlay_Document;
      Budget     : in out Operation_Budget;
      Result     : in out Natural;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
   begin
      if Reserve_Query_Work (Budget, 1, Diagnostic) then
         Result := Natural (Value.Data.With_Units.Length);
      end if;
   end Read_With_Unit_Count;

   procedure Read_Field_Count
     (Value      : Overlay_Document;
      Budget     : in out Operation_Budget;
      Result     : in out Natural;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
   begin
      if Reserve_Query_Work (Budget, 1, Diagnostic) then
         Result := Natural (Value.Data.Fields.Length);
      end if;
   end Read_Field_Count;

   procedure Read_Output_Unit_Length
     (Value      : Overlay_Document;
      Budget     : in out Operation_Budget;
      Length     : in out Natural;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
   begin
      Read_Text_Length (Value.Data.Output_Unit, Budget, Length, Diagnostic);
   end Read_Output_Unit_Length;

   procedure Copy_Output_Unit
     (Value      : Overlay_Document;
      Budget     : in out Operation_Budget;
      Into       : in out String;
      Written    : in out Natural;
      Copied     : in out Boolean;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
   begin
      Copy_Text (Value.Data.Output_Unit, Budget, Into, Written, Copied, Diagnostic);
   end Copy_Output_Unit;

   procedure Read_Type_IR_Commit_Length
     (Value      : Overlay_Document;
      Budget     : in out Operation_Budget;
      Length     : in out Natural;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
   begin
      Read_Text_Length (Value.Data.Type_IR_Commit, Budget, Length, Diagnostic);
   end Read_Type_IR_Commit_Length;

   procedure Copy_Type_IR_Commit
     (Value      : Overlay_Document;
      Budget     : in out Operation_Budget;
      Into       : in out String;
      Written    : in out Natural;
      Copied     : in out Boolean;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
   begin
      Copy_Text (Value.Data.Type_IR_Commit, Budget, Into, Written, Copied, Diagnostic);
   end Copy_Type_IR_Commit;

   procedure Read_Type_IR_Semantic_Fingerprint_Length
     (Value      : Overlay_Document;
      Budget     : in out Operation_Budget;
      Length     : in out Natural;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
   begin
      Read_Text_Length (Value.Data.Type_IR_Semantic_Fingerprint, Budget, Length, Diagnostic);
   end Read_Type_IR_Semantic_Fingerprint_Length;

   procedure Copy_Type_IR_Semantic_Fingerprint
     (Value      : Overlay_Document;
      Budget     : in out Operation_Budget;
      Into       : in out String;
      Written    : in out Natural;
      Copied     : in out Boolean;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
   begin
      Copy_Text (Value.Data.Type_IR_Semantic_Fingerprint, Budget, Into, Written, Copied, Diagnostic);
   end Copy_Type_IR_Semantic_Fingerprint;

   procedure Read_Type_IR_Source_SHA256_Length
     (Value      : Overlay_Document;
      Budget     : in out Operation_Budget;
      Length     : in out Natural;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
   begin
      Read_Text_Length (Value.Data.Type_IR_Source_SHA256, Budget, Length, Diagnostic);
   end Read_Type_IR_Source_SHA256_Length;

   procedure Copy_Type_IR_Source_SHA256
     (Value      : Overlay_Document;
      Budget     : in out Operation_Budget;
      Into       : in out String;
      Written    : in out Natural;
      Copied     : in out Boolean;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
   begin
      Copy_Text (Value.Data.Type_IR_Source_SHA256, Budget, Into, Written, Copied, Diagnostic);
   end Copy_Type_IR_Source_SHA256;

   procedure Read_Source_SHA256_Length
     (Value      : Overlay_Document;
      Budget     : in out Operation_Budget;
      Length     : in out Natural;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
   begin
      Read_Text_Length (Value.Data.Source_SHA256, Budget, Length, Diagnostic);
   end Read_Source_SHA256_Length;

   procedure Copy_Source_SHA256
     (Value      : Overlay_Document;
      Budget     : in out Operation_Budget;
      Into       : in out String;
      Written    : in out Natural;
      Copied     : in out Boolean;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
   begin
      Copy_Text (Value.Data.Source_SHA256, Budget, Into, Written, Copied, Diagnostic);
   end Copy_Source_SHA256;

   procedure Read_With_Unit_Length
     (Value      : Overlay_Document;
      Index      : Positive;
      Budget     : in out Operation_Budget;
      Length     : in out Natural;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
   begin
      if not Ready_For_Query (Budget, Diagnostic) then
         return;
      elsif Index > Natural (Value.Data.With_Units.Length) then
         Set (Diagnostic, Internal_Error);
         return;
      end if;
      declare
         Reference : constant String_Vectors.Constant_Reference_Type :=
           Value.Data.With_Units.Constant_Reference (Index);
      begin
         Read_Text_Length (Reference.Element.all, Budget, Length, Diagnostic);
      end;
   end Read_With_Unit_Length;

   procedure Copy_With_Unit
     (Value      : Overlay_Document;
      Index      : Positive;
      Budget     : in out Operation_Budget;
      Into       : in out String;
      Written    : in out Natural;
      Copied     : in out Boolean;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
   begin
      if not Ready_For_Query (Budget, Diagnostic) then
         return;
      elsif Index > Natural (Value.Data.With_Units.Length) then
         Set (Diagnostic, Internal_Error);
         return;
      end if;
      declare
         Reference : constant String_Vectors.Constant_Reference_Type :=
           Value.Data.With_Units.Constant_Reference (Index);
      begin
         Copy_Text (Reference.Element.all, Budget, Into, Written, Copied, Diagnostic);
      end;
   end Copy_With_Unit;

   procedure Read_Record_Ada_Type_Length
     (Value      : Overlay_Document;
      Budget     : in out Operation_Budget;
      Length     : in out Natural;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
   begin
      Read_Text_Length (Value.Data.Record_Ada_Type, Budget, Length, Diagnostic);
   end Read_Record_Ada_Type_Length;

   procedure Copy_Record_Ada_Type
     (Value      : Overlay_Document;
      Budget     : in out Operation_Budget;
      Into       : in out String;
      Written    : in out Natural;
      Copied     : in out Boolean;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
   begin
      Copy_Text (Value.Data.Record_Ada_Type, Budget, Into, Written, Copied, Diagnostic);
   end Copy_Record_Ada_Type;

   procedure Read_Record_Declaration_ID_Length
     (Value      : Overlay_Document;
      Budget     : in out Operation_Budget;
      Length     : in out Natural;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
   begin
      Read_Text_Length (Value.Data.Record_Declaration_ID, Budget, Length, Diagnostic);
   end Read_Record_Declaration_ID_Length;

   procedure Copy_Record_Declaration_ID
     (Value      : Overlay_Document;
      Budget     : in out Operation_Budget;
      Into       : in out String;
      Written    : in out Natural;
      Copied     : in out Boolean;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
   begin
      Copy_Text (Value.Data.Record_Declaration_ID, Budget, Into, Written, Copied, Diagnostic);
   end Copy_Record_Declaration_ID;

   procedure Read_Record_Logical_Type_Name_Length
     (Value      : Overlay_Document;
      Budget     : in out Operation_Budget;
      Length     : in out Natural;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
   begin
      Read_Text_Length (Value.Data.Record_Logical_Type_Name, Budget, Length, Diagnostic);
   end Read_Record_Logical_Type_Name_Length;

   procedure Copy_Record_Logical_Type_Name
     (Value      : Overlay_Document;
      Budget     : in out Operation_Budget;
      Into       : in out String;
      Written    : in out Natural;
      Copied     : in out Boolean;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
   begin
      Copy_Text (Value.Data.Record_Logical_Type_Name, Budget, Into, Written, Copied, Diagnostic);
   end Copy_Record_Logical_Type_Name;

   function Valid_Field_Index
     (Value      : Overlay_Document;
      Index      : Positive;
      Budget     : in out Operation_Budget;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic) return Boolean
   is
   begin
      if not Ready_For_Query (Budget, Diagnostic) then
         return False;
      elsif Index > Natural (Value.Data.Fields.Length) then
         Set (Diagnostic, Internal_Error);
         return False;
      end if;
      return True;
   end Valid_Field_Index;

   procedure Read_Field_Ada_Component_Length
     (Value      : Overlay_Document;
      Index      : Positive;
      Budget     : in out Operation_Budget;
      Length     : in out Natural;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
   begin
      if Valid_Field_Index (Value, Index, Budget, Diagnostic) then
         declare
            Reference : constant Field_Vectors.Constant_Reference_Type :=
              Value.Data.Fields.Constant_Reference (Index);
         begin
            Read_Text_Length (Reference.Element.Ada_Component, Budget, Length, Diagnostic);
         end;
      end if;
   end Read_Field_Ada_Component_Length;

   procedure Copy_Field_Ada_Component
     (Value      : Overlay_Document;
      Index      : Positive;
      Budget     : in out Operation_Budget;
      Into       : in out String;
      Written    : in out Natural;
      Copied     : in out Boolean;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
   begin
      if Valid_Field_Index (Value, Index, Budget, Diagnostic) then
         declare
            Reference : constant Field_Vectors.Constant_Reference_Type :=
              Value.Data.Fields.Constant_Reference (Index);
         begin
            Copy_Text (Reference.Element.Ada_Component, Budget, Into, Written, Copied, Diagnostic);
         end;
      end if;
   end Copy_Field_Ada_Component;

   procedure Read_Field_Ada_Type_Length
     (Value      : Overlay_Document;
      Index      : Positive;
      Budget     : in out Operation_Budget;
      Length     : in out Natural;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
   begin
      if Valid_Field_Index (Value, Index, Budget, Diagnostic) then
         declare
            Reference : constant Field_Vectors.Constant_Reference_Type :=
              Value.Data.Fields.Constant_Reference (Index);
         begin
            Read_Text_Length (Reference.Element.Ada_Type, Budget, Length, Diagnostic);
         end;
      end if;
   end Read_Field_Ada_Type_Length;

   procedure Copy_Field_Ada_Type
     (Value      : Overlay_Document;
      Index      : Positive;
      Budget     : in out Operation_Budget;
      Into       : in out String;
      Written    : in out Natural;
      Copied     : in out Boolean;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
   begin
      if Valid_Field_Index (Value, Index, Budget, Diagnostic) then
         declare
            Reference : constant Field_Vectors.Constant_Reference_Type :=
              Value.Data.Fields.Constant_Reference (Index);
         begin
            Copy_Text (Reference.Element.Ada_Type, Budget, Into, Written, Copied, Diagnostic);
         end;
      end if;
   end Copy_Field_Ada_Type;

   procedure Read_Field_Component_ID_Length
     (Value      : Overlay_Document;
      Index      : Positive;
      Budget     : in out Operation_Budget;
      Length     : in out Natural;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
   begin
      if Valid_Field_Index (Value, Index, Budget, Diagnostic) then
         declare
            Reference : constant Field_Vectors.Constant_Reference_Type :=
              Value.Data.Fields.Constant_Reference (Index);
         begin
            Read_Text_Length (Reference.Element.Component_ID, Budget, Length, Diagnostic);
         end;
      end if;
   end Read_Field_Component_ID_Length;

   procedure Copy_Field_Component_ID
     (Value      : Overlay_Document;
      Index      : Positive;
      Budget     : in out Operation_Budget;
      Into       : in out String;
      Written    : in out Natural;
      Copied     : in out Boolean;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
   begin
      if Valid_Field_Index (Value, Index, Budget, Diagnostic) then
         declare
            Reference : constant Field_Vectors.Constant_Reference_Type :=
              Value.Data.Fields.Constant_Reference (Index);
         begin
            Copy_Text (Reference.Element.Component_ID, Budget, Into, Written, Copied, Diagnostic);
         end;
      end if;
   end Copy_Field_Component_ID;

   procedure Read_Field_Presentation_Name_Length
     (Value      : Overlay_Document;
      Index      : Positive;
      Budget     : in out Operation_Budget;
      Length     : in out Natural;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
   begin
      if Valid_Field_Index (Value, Index, Budget, Diagnostic) then
         declare
            Reference : constant Field_Vectors.Constant_Reference_Type :=
              Value.Data.Fields.Constant_Reference (Index);
         begin
            Read_Text_Length (Reference.Element.Presentation_Name, Budget, Length, Diagnostic);
         end;
      end if;
   end Read_Field_Presentation_Name_Length;

   procedure Copy_Field_Presentation_Name
     (Value      : Overlay_Document;
      Index      : Positive;
      Budget     : in out Operation_Budget;
      Into       : in out String;
      Written    : in out Natural;
      Copied     : in out Boolean;
      Diagnostic : in out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
   begin
      if Valid_Field_Index (Value, Index, Budget, Diagnostic) then
         declare
            Reference : constant Field_Vectors.Constant_Reference_Type :=
              Value.Data.Fields.Constant_Reference (Index);
         begin
            Copy_Text (Reference.Element.Presentation_Name, Budget, Into, Written, Copied, Diagnostic);
         end;
      end if;
   end Copy_Field_Presentation_Name;

   overriding procedure Finalize (Value : in out Overlay_Document) is
   begin
      Discard (Value.Data);
   end Finalize;
end Flyology_Serde_Generator.Overlays;
