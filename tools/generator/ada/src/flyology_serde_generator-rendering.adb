with Ada.Characters.Handling;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Unchecked_Deallocation;

package body Flyology_Serde_Generator.Rendering is
   use Ada.Strings.Unbounded;
   use Flyology_Serde_Generator.Diagnostics;
   use Flyology_Serde_Generator.Lowered_Records;
   use Flyology_Serde_Generator.Requests;

   type Artifact_Data is record
      Specification_Name    : Unbounded_String;
      Specification_Payload : aliased Unbounded_String;
      Body_Name             : Unbounded_String;
      Body_Payload          : aliased Unbounded_String;
   end record;

   procedure Free is new Ada.Unchecked_Deallocation
     (Object => Artifact_Data,
      Name   => Artifact_Data_Access);

   procedure Discard (Value : in out Artifact_Data_Access) is
      Detached : Artifact_Data_Access := Value;
   begin
      Value := null;
      Free (Detached);
   exception
      when others =>
         null;
   end Discard;

   Unsupported_Model : exception;
   Invalid_Render     : exception;
   Exhausted          : exception;

   type Output_Sink
     (Budget : not null access Operation_Budget;
      Target : not null access Unbounded_String)
   is limited record
      Bytes      : Natural := 0;
      Column     : Natural := 0;
      Last_Was_LF : Boolean := False;
   end record;

   procedure Put (Into : in out Output_Sink; Text : String) is
      Accepted : Boolean;
   begin
      if Text'Length > Natural'Last - Into.Bytes then
         raise Invalid_Render;
      end if;
      Charge_Rendered_Chunk (Into.Budget.all, Into.Bytes, Text'Length, Accepted);
      if not Accepted then
         raise Exhausted;
      end if;
      for Item of Text loop
         if Character'Pos (Item) > 127 or else Item = ASCII.CR or else Item = ASCII.NUL then
            raise Invalid_Render;
         elsif Item = ASCII.LF then
            Into.Column := 0;
            Into.Last_Was_LF := True;
         else
            if Into.Column = 110 then
               raise Invalid_Render;
            end if;
            Into.Column := Into.Column + 1;
            Into.Last_Was_LF := False;
         end if;
      end loop;
      Into.Bytes := Into.Bytes + Text'Length;
      Append (Into.Target.all, Text);
   end Put;

   procedure Put_Line (Into : in out Output_Sink; Text : String := "") is
   begin
      Put (Into, Text);
      Put (Into, String'(1 => ASCII.LF));
   end Put_Line;

   function Image (Value : Natural) return String is
      Result : constant String := Natural'Image (Value);
   begin
      return Result (Result'First + 1 .. Result'Last);
   end Image;

   function Ada_Literal (Value : String) return String is
      Result : Unbounded_String := To_Unbounded_String (String'(1 => '"'));
   begin
      for Item of Value loop
         if Item = '"' then
            Append (Result, """");
         end if;
         Append (Result, Item);
      end loop;
      Append (Result, '"');
      return To_String (Result);
   end Ada_Literal;

   function Is_ASCII_Letter (Value : Character) return Boolean is
     (Value in 'A' .. 'Z' or else Value in 'a' .. 'z');

   function Is_ASCII_Digit (Value : Character) return Boolean is
     (Value in '0' .. '9');

   function Is_Reserved (Value : String) return Boolean is
      Lower : constant String := Ada.Characters.Handling.To_Lower (Value);
      Words : constant String :=
        "|abort|abs|abstract|accept|access|aliased|all|and|array|at|begin|body|case|constant|" &
        "declare|delay|delta|digits|do|else|elsif|end|entry|exception|exit|for|function|" &
        "generic|goto|if|in|interface|is|limited|loop|mod|new|not|null|of|or|others|out|" &
        "overriding|package|parallel|pragma|private|procedure|protected|raise|range|record|" &
        "rem|renames|requeue|return|reverse|select|separate|some|subtype|synchronized|tagged|" &
        "task|terminate|then|type|until|use|when|while|with|xor|";
   begin
      return Ada.Strings.Fixed.Index (Words, "|" & Lower & "|") /= 0;
   end Is_Reserved;

   function Is_Identifier (Value : String) return Boolean is
   begin
      if Value'Length = 0
        or else not Is_ASCII_Letter (Value (Value'First))
        or else not (Is_ASCII_Letter (Value (Value'Last)) or else Is_ASCII_Digit (Value (Value'Last)))
        or else Is_Reserved (Value)
      then
         return False;
      end if;
      for Index in Value'Range loop
         if not Is_ASCII_Letter (Value (Index))
           and then not Is_ASCII_Digit (Value (Index))
           and then Value (Index) /= '_'
         then
            return False;
         elsif Value (Index) = '_'
           and then Index < Value'Last
           and then Value (Index + 1) = '_'
         then
            return False;
         end if;
      end loop;
      return True;
   end Is_Identifier;

   function Is_Selected_Name (Value : String) return Boolean is
      Start : Positive := Value'First;
   begin
      if Value'Length = 0 or else Value'Length > 64 then
         return False;
      end if;
      for Index in Value'Range loop
         if Value (Index) = '.' then
            if Index = Start or else not Is_Identifier (Value (Start .. Index - 1)) then
               return False;
            end if;
            if Index = Value'Last then
               return False;
            end if;
            Start := Index + 1;
         end if;
      end loop;
      return Is_Identifier (Value (Start .. Value'Last));
   end Is_Selected_Name;

   function Is_Logical_Name (Value : String) return Boolean is
   begin
      if Value'Length = 0 or else Value'Length > 64 then
         return False;
      end if;
      return (for all Item of Value => Character'Pos (Item) in 33 .. 126);
   end Is_Logical_Name;

   function Equal_Ignoring_Case (Left, Right : String) return Boolean is
     (Ada.Characters.Handling.To_Lower (Left) = Ada.Characters.Handling.To_Lower (Right));

   function Adapter_Name (Index : Positive) return String;

   procedure Validate (Value : Model) is
      Limits : constant Runtime_Limit_Set := Runtime_Limits (Value);

      procedure Require_Line (Text : String) is
      begin
         if Text'Length > 110 then
            raise Unsupported_Model;
         end if;
      end Require_Line;
   begin
      if not Is_Valid (Value)
        or else not Is_Selected_Name (Output_Unit (Value))
        or else With_Unit_Count (Value) = 0
        or else Field_Count (Value) not in 1 .. 3
        or else not Is_Selected_Name (Record_Ada_Type (Value))
        or else not Is_Logical_Name (Logical_Type_Name (Value))
        or else Limits.Maximum_Nesting_Depth not in 1 .. 256
        or else Limits.Maximum_Container_Items = 0
        or else Limits.Maximum_Text_Length = 0
        or else Limits.Maximum_Byte_Length = 0
        or else Limits.Maximum_Logical_Events = 0
      then
         raise Unsupported_Model;
      end if;
      for Index in 1 .. With_Unit_Count (Value) loop
         if not Is_Selected_Name (With_Unit (Value, Index)) then
            raise Unsupported_Model;
         end if;
         for Prior in 1 .. Index - 1 loop
            if Equal_Ignoring_Case (With_Unit (Value, Prior), With_Unit (Value, Index)) then
               raise Unsupported_Model;
            end if;
         end loop;
         Require_Line ("with " & With_Unit (Value, Index) & ";");
      end loop;
      Require_Line ("package " & Output_Unit (Value) & " is");
      Require_Line ("package body " & Output_Unit (Value) & " is");
      Require_Line ("end " & Output_Unit (Value) & ";");
      Require_Line ("   function Value (Target : Builder) return " & Record_Ada_Type (Value));
      Require_Line ("      Published : " & Record_Ada_Type (Value) & ";");
      Require_Line ("      Candidate : " & Record_Ada_Type (Value) & ";");
      Require_Line ("     (Item  : " & Record_Ada_Type (Value) & ";");
      Require_Line ("      Value  : " & Record_Ada_Type (Value) & ";");
      Require_Line
        ("      Into.Begin_Record (" & Ada_Literal (Logical_Type_Name (Value)) & ", " &
           Image (Field_Count (Value)) & ", Error);");
      Require_Line
        ("      From.Begin_Record (" & Ada_Literal (Logical_Type_Name (Value)) & ", Length, Error);");
      for Index in 1 .. Field_Count (Value) loop
         if not Is_Identifier (Field_Ada_Component (Value, Index))
           or else not Is_Selected_Name (Field_Ada_Type (Value, Index))
           or else not Is_Logical_Name (Field_Presentation_Name (Value, Index))
         then
            raise Unsupported_Model;
         end if;
         for Prior in 1 .. Index - 1 loop
            if Equal_Ignoring_Case
                 (Field_Ada_Component (Value, Prior), Field_Ada_Component (Value, Index))
              or else Field_Presentation_Name (Value, Prior) = Field_Presentation_Name (Value, Index)
            then
               raise Unsupported_Model;
            end if;
         end loop;
         Require_Line
           ("      Into.Put_Field (" & Ada_Literal (Field_Presentation_Name (Value, Index)) &
              ", Error);");
         Require_Line
           ("         " & (if Index = 1 then "if" else "elsif") &
              " Name (1 .. Name_Last) = " & Ada_Literal (Field_Presentation_Name (Value, Index)) &
              " then");
         Require_Line
           ("         Flyology_Serde.Errors.Push_Field (Error, " &
              Ada_Literal (Field_Presentation_Name (Value, Index)) & ");");
         if Field_Scalar_Kind (Value, Index) = Boolean_Scalar then
            Require_Line
              ("      Into.Put_Boolean (Item." & Field_Ada_Component (Value, Index) & ", Error);");
            Require_Line
              ("                  From.Read_Boolean (Target.Candidate." &
                 Field_Ada_Component (Value, Index) & ", Error);");
         else
            Require_Line
              ("   package " & Adapter_Name (Index) & " is new Flyology_Serde.Adapters." &
                 (if Field_Scalar_Kind (Value, Index) = Signed_64_Scalar
                  then "Signed_Integers"
                  else "Unsigned_Integers"));
            Require_Line ("     (" & Field_Ada_Type (Value, Index) & ");");
            Require_Line
              ("      " & Adapter_Name (Index) & ".Serialize_Value (Item." &
                 Field_Ada_Component (Value, Index) & ", Into, Error);");
            Require_Line
              ("                  " & Adapter_Name (Index) & ".Deserialize_Candidate " &
                 "(From, Target.Candidate." & Field_Ada_Component (Value, Index) & ", Error);");
         end if;
      end loop;
   end Validate;

   function Adapter_Name (Index : Positive) return String is
     ("Field_" & Image (Index) & "_Adapter");

   procedure Emit_Spec (Value : Model; Into : in out Output_Sink) is
      Unit_Name : constant String := Output_Unit (Value);
      Ada_Type  : constant String := Record_Ada_Type (Value);
   begin
      for Index in 1 .. With_Unit_Count (Value) loop
         Put_Line (Into, "with " & With_Unit (Value, Index) & ";");
      end loop;
      Put_Line (Into, "with Flyology_Serde.Deserialization;");
      Put_Line (Into, "with Flyology_Serde.Errors;");
      Put_Line (Into, "with Flyology_Serde.Serialization;");
      Put_Line (Into);
      Put_Line (Into, "package " & Unit_Name & " is");
      Put_Line (Into, "   type Builder is limited private;");
      Put_Line (Into);
      Put_Line (Into, "   procedure Initialize");
      Put_Line (Into, "     (Target : in out Builder;");
      Put_Line (Into, "      Value  : " & Ada_Type & ";");
      Put_Line (Into, "      Error  : in out Flyology_Serde.Errors.Error_Info);");
      Put_Line (Into, "   function Has_Value (Target : Builder) return Boolean;");
      Put_Line (Into, "   function Value (Target : Builder) return " & Ada_Type);
      Put_Line (Into, "   with Pre => Has_Value (Target);");
      Put_Line (Into);
      Put_Line (Into, "   procedure Serialize");
      Put_Line (Into, "     (Item  : " & Ada_Type & ";");
      Put_Line (Into, "      Into  : in out Flyology_Serde.Serialization.Serializer'Class;");
      Put_Line (Into, "      Error : in out Flyology_Serde.Errors.Error_Info);");
      Put_Line (Into);
      Put_Line (Into, "   procedure Deserialize");
      Put_Line (Into, "     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;");
      Put_Line (Into, "      Target : in out Builder;");
      Put_Line (Into, "      Error  : in out Flyology_Serde.Errors.Error_Info);");
      Put_Line (Into);
      Put_Line (Into, "private");
      Put_Line (Into, "   type Builder is limited record");
      Put_Line (Into, "      Published : " & Ada_Type & ";");
      Put_Line (Into, "      Candidate : " & Ada_Type & ";");
      Put_Line (Into, "      Initialized : Boolean := False;");
      Put_Line (Into, "      Active      : Boolean := False;");
      Put_Line (Into, "      Root_Started : Boolean := False;");
      Put_Line (Into, "   end record;");
      Put_Line (Into, "end " & Unit_Name & ";");
   end Emit_Spec;

   procedure Emit_Body (Value : Model; Into : in out Output_Sink) is
      Unit_Name : constant String := Output_Unit (Value);
      Ada_Type  : constant String := Record_Ada_Type (Value);
      Limits    : constant Runtime_Limit_Set := Runtime_Limits (Value);
   begin
      Put_Line (Into, "with Flyology_Serde.Adapters.Signed_Integers;");
      Put_Line (Into, "with Flyology_Serde.Adapters.Unsigned_Integers;");
      Put_Line (Into, "with Flyology_Serde.Data_Model;");
      Put_Line (Into, "with Flyology_Serde.Deserialization_Adapters;");
      Put_Line (Into, "with Flyology_Serde.Policies;");
      Put_Line (Into, "with Flyology_Serde.Serialization_Adapters;");
      Put_Line (Into);
      Put_Line (Into, "package body " & Unit_Name & " is");
      Put_Line (Into, "   use type Flyology_Serde.Errors.Error_Code;");
      Put_Line (Into);
      for Index in 1 .. Field_Count (Value) loop
         if Field_Scalar_Kind (Value, Index) /= Boolean_Scalar then
            Put_Line
              (Into,
               "   package " & Adapter_Name (Index) & " is new Flyology_Serde.Adapters." &
                 (if Field_Scalar_Kind (Value, Index) = Signed_64_Scalar
                  then "Signed_Integers"
                  else "Unsigned_Integers"));
            Put_Line (Into, "     (" & Field_Ada_Type (Value, Index) & ");");
         end if;
      end loop;
      Put_Line (Into);
      Put_Line
        (Into,
         "   Default_Policy : constant Flyology_Serde.Policies.Decode_Policy := (others => <>);");
      Put_Line (Into);
      Put_Line
        (Into, "   Serialization_Limits : constant Flyology_Serde.Serialization.Serialization_Limits :=");
      Put_Line (Into, "     (Maximum_Nesting_Depth   => " & Image (Limits.Maximum_Nesting_Depth) & ",");
      Put_Line
        (Into, "      Maximum_Container_Items => " & Image (Limits.Maximum_Container_Items) & ",");
      Put_Line (Into, "      Maximum_Text_Length     => " & Image (Limits.Maximum_Text_Length) & ",");
      Put_Line (Into, "      Maximum_Byte_Length     => " & Image (Limits.Maximum_Byte_Length) & ",");
      Put_Line (Into, "      Maximum_Logical_Events  => " & Image (Limits.Maximum_Logical_Events) & ");");
      Put_Line (Into);
      Put_Line (Into, "   procedure Serialize_Value");
      Put_Line (Into, "     (Item  : " & Ada_Type & ";");
      Put_Line (Into, "      Into  : in out Flyology_Serde.Serialization.Serializer'Class;");
      Put_Line (Into, "      Error : in out Flyology_Serde.Errors.Error_Info) is");
      Put_Line (Into, "   begin");
      Put_Line
        (Into,
         "      Into.Begin_Record (" & Ada_Literal (Logical_Type_Name (Value)) & ", " &
           Image (Field_Count (Value)) & ", Error);");
      for Index in 1 .. Field_Count (Value) loop
         Put_Line
           (Into,
            "      Into.Put_Field (" & Ada_Literal (Field_Presentation_Name (Value, Index)) & ", Error);");
         if Field_Scalar_Kind (Value, Index) = Boolean_Scalar then
            Put_Line
              (Into,
               "      Into.Put_Boolean (Item." & Field_Ada_Component (Value, Index) & ", Error);");
         else
            Put_Line
              (Into,
               "      " & Adapter_Name (Index) & ".Serialize_Value (Item." &
                 Field_Ada_Component (Value, Index) & ", Into, Error);");
         end if;
      end loop;
      Put_Line (Into, "      Into.End_Record (Error);");
      Put_Line (Into, "   end Serialize_Value;");
      Put_Line (Into);
      Put_Line (Into, "   procedure Begin_Candidate");
      Put_Line
        (Into, "     (Target : in out Builder; Error : in out Flyology_Serde.Errors.Error_Info) is");
      Put_Line (Into, "   begin");
      Put_Line (Into, "      if Target.Active then");
      Put_Line
        (Into, "         Flyology_Serde.Errors.Fail (Error, Flyology_Serde.Errors.Invalid_State);");
      Put_Line (Into, "      else");
      Put_Line (Into, "         Target.Active := True;");
      Put_Line (Into, "         Target.Root_Started := True;");
      Put_Line (Into, "      end if;");
      Put_Line (Into, "   end Begin_Candidate;");
      Put_Line (Into);
      Put_Line (Into, "   procedure Deserialize_Value");
      Put_Line (Into, "     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;");
      Put_Line (Into, "      Target : in out Builder;");
      Put_Line (Into, "      Policy : Flyology_Serde.Policies.Decode_Policy;");
      Put_Line (Into, "      Error  : in out Flyology_Serde.Errors.Error_Info)");
      Put_Line (Into, "   is");
      Put_Line (Into, "      pragma Unreferenced (Policy);");
      Put_Line (Into, "      Length    : Flyology_Serde.Data_Model.Length_Information;");
      Put_Line (Into, "      Available : Boolean := False;");
      Put_Line (Into, "      Name      : String (1 .. 64);");
      Put_Line (Into, "      Name_Last : Natural := 0;");
      Put_Line
        (Into,
         "      Seen      : array (Positive range 1 .. " & Image (Field_Count (Value)) &
           ") of Boolean := [others => False];");
      Put_Line (Into, "   begin");
      Put_Line
        (Into, "      From.Begin_Record (" & Ada_Literal (Logical_Type_Name (Value)) & ", Length, Error);");
      Put_Line (Into, "      while Error.Code = Flyology_Serde.Errors.No_Error loop");
      Put_Line (Into, "         From.Next_Field (Name, Name_Last, Available, Error);");
      Put_Line
        (Into, "         exit when Error.Code /= Flyology_Serde.Errors.No_Error or else not Available;");
      Put_Line (Into, "         Flyology_Serde.Errors.Push_Field (Error, Name (1 .. Name_Last));");
      for Index in 1 .. Field_Count (Value) loop
         Put_Line
           (Into,
            "         " & (if Index = 1 then "if" else "elsif") & " Name (1 .. Name_Last) = " &
              Ada_Literal (Field_Presentation_Name (Value, Index)) & " then");
         Put_Line (Into, "               if Seen (" & Image (Index) & ") then");
         Put_Line
           (Into,
            "                  Flyology_Serde.Errors.Fail (Error, Flyology_Serde.Errors.Duplicate_Field);");
         Put_Line (Into, "               else");
         Put_Line (Into, "                  Seen (" & Image (Index) & ") := True;");
         if Field_Scalar_Kind (Value, Index) = Boolean_Scalar then
            Put_Line
              (Into,
               "                  From.Read_Boolean (Target.Candidate." &
                 Field_Ada_Component (Value, Index) & ", Error);");
         else
            Put_Line
              (Into,
               "                  " & Adapter_Name (Index) & ".Deserialize_Candidate " &
                 "(From, Target.Candidate." & Field_Ada_Component (Value, Index) & ", Error);");
         end if;
         Put_Line (Into, "               end if;");
      end loop;
      Put_Line (Into, "         else");
      Put_Line
        (Into, "            Flyology_Serde.Errors.Fail (Error, Flyology_Serde.Errors.Unknown_Field);");
      Put_Line (Into, "         end if;");
      Put_Line (Into, "         exit when Error.Code /= Flyology_Serde.Errors.No_Error;");
      Put_Line (Into, "         Flyology_Serde.Errors.Pop (Error);");
      Put_Line (Into, "      end loop;");
      Put_Line (Into, "      if Error.Code = Flyology_Serde.Errors.No_Error then");
      Put_Line (Into, "         From.End_Record (Error);");
      Put_Line (Into, "      end if;");
      for Index in 1 .. Field_Count (Value) loop
         Put_Line
           (Into,
            "      if Error.Code = Flyology_Serde.Errors.No_Error and then not Seen (" &
              Image (Index) & ") then");
         Put_Line
           (Into,
            "         Flyology_Serde.Errors.Push_Field (Error, " &
              Ada_Literal (Field_Presentation_Name (Value, Index)) & ");");
         Put_Line
           (Into,
            "         Flyology_Serde.Errors.Fail (Error, Flyology_Serde.Errors.Missing_Field);");
         Put_Line (Into, "      end if;");
      end loop;
      Put_Line (Into, "   end Deserialize_Value;");
      Put_Line (Into);
      Put_Line (Into, "   procedure Commit_Candidate");
      Put_Line
        (Into, "     (Target : in out Builder; Error : in out Flyology_Serde.Errors.Error_Info) is");
      Put_Line (Into, "   begin");
      Put_Line (Into, "      if not Target.Active or else not Target.Root_Started then");
      Put_Line
        (Into, "         Flyology_Serde.Errors.Fail (Error, Flyology_Serde.Errors.Invalid_State);");
      Put_Line (Into, "      else");
      Put_Line (Into, "         Target.Published := Target.Candidate;");
      Put_Line (Into, "         Target.Initialized := True;");
      Put_Line (Into, "         Target.Active := False;");
      Put_Line (Into, "         Target.Root_Started := False;");
      Put_Line (Into, "      end if;");
      Put_Line (Into, "   end Commit_Candidate;");
      Put_Line (Into);
      Put_Line (Into, "   procedure Rollback_Candidate (Target : in out Builder) is");
      Put_Line (Into, "   begin");
      Put_Line (Into, "      if Target.Root_Started then");
      Put_Line (Into, "         Target.Active := False;");
      Put_Line (Into, "         Target.Root_Started := False;");
      Put_Line (Into, "      end if;");
      Put_Line (Into, "   exception");
      Put_Line (Into, "      when others =>");
      Put_Line (Into, "         null;");
      Put_Line (Into, "   end Rollback_Candidate;");
      Put_Line (Into);
      Put_Line (Into, "   package Serialization_Root is new Flyology_Serde.Serialization_Adapters");
      Put_Line (Into, "     (Source_Type      => " & Ada_Type & ",");
      Put_Line (Into, "      Limits           => Serialization_Limits,");
      Put_Line (Into, "      Serialize_Value => Serialize_Value);");
      Put_Line (Into);
      Put_Line
        (Into, "   package Deserialization_Root is new Flyology_Serde.Deserialization_Adapters");
      Put_Line (Into, "     (Builder_Type       => Builder,");
      Put_Line (Into, "      Policy             => Default_Policy,");
      Put_Line (Into, "      Begin_Candidate    => Begin_Candidate,");
      Put_Line (Into, "      Deserialize_Value  => Deserialize_Value,");
      Put_Line (Into, "      Commit_Candidate   => Commit_Candidate,");
      Put_Line (Into, "      Rollback_Candidate => Rollback_Candidate);");
      Put_Line (Into);
      Put_Line (Into, "   procedure Initialize");
      Put_Line (Into, "     (Target : in out Builder;");
      Put_Line (Into, "      Value  : " & Ada_Type & ";");
      Put_Line (Into, "      Error  : in out Flyology_Serde.Errors.Error_Info) is");
      Put_Line (Into, "   begin");
      Put_Line (Into, "      if Error.Code /= Flyology_Serde.Errors.No_Error then");
      Put_Line (Into, "         return;");
      Put_Line (Into, "      elsif Target.Active then");
      Put_Line
        (Into, "         Flyology_Serde.Errors.Fail (Error, Flyology_Serde.Errors.Invalid_State);");
      Put_Line (Into, "      else");
      Put_Line (Into, "         Target.Published := Value;");
      Put_Line (Into, "         Target.Candidate := Value;");
      Put_Line (Into, "         Target.Initialized := True;");
      Put_Line (Into, "         Target.Root_Started := False;");
      Put_Line (Into, "      end if;");
      Put_Line (Into, "   end Initialize;");
      Put_Line (Into);
      Put_Line (Into, "   function Has_Value (Target : Builder) return Boolean");
      Put_Line (Into, "   is (Target.Initialized and then not Target.Active);");
      Put_Line (Into);
      Put_Line (Into, "   function Value (Target : Builder) return " & Ada_Type);
      Put_Line (Into, "   is (Target.Published);");
      Put_Line (Into);
      Put_Line (Into, "   procedure Serialize");
      Put_Line (Into, "     (Item  : " & Ada_Type & ";");
      Put_Line (Into, "      Into  : in out Flyology_Serde.Serialization.Serializer'Class;");
      Put_Line (Into, "      Error : in out Flyology_Serde.Errors.Error_Info) is");
      Put_Line (Into, "   begin");
      Put_Line (Into, "      Serialization_Root.Serialize (Item, Into, Error);");
      Put_Line (Into, "   end Serialize;");
      Put_Line (Into);
      Put_Line (Into, "   procedure Deserialize");
      Put_Line (Into, "     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;");
      Put_Line (Into, "      Target : in out Builder;");
      Put_Line (Into, "      Error  : in out Flyology_Serde.Errors.Error_Info) is");
      Put_Line (Into, "   begin");
      Put_Line (Into, "      Deserialization_Root.Deserialize (From, Target, Error);");
      Put_Line (Into, "   end Deserialize;");
      Put_Line (Into, "end " & Unit_Name & ";");
   end Emit_Body;

   function File_Stem (Unit_Name : String) return String is
      Result : String (Unit_Name'Range);
   begin
      for Index in Unit_Name'Range loop
         Result (Index) :=
           (if Unit_Name (Index) = '.' then '-' else Ada.Characters.Handling.To_Lower (Unit_Name (Index)));
      end loop;
      return Result;
   end File_Stem;

   procedure Render_Payload
     (Value      : Model;
      Budget     : aliased in out Operation_Budget;
      Into       : in out Rendered_Artifacts;
      Diagnostic : out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
      Candidate    : Artifact_Data_Access := null;
      Accepted     : Boolean;
      Previous     : Artifact_Data_Access;
      Model_Work   : constant Natural := With_Unit_Count (Value) + Field_Count (Value);
   begin
      Clear (Diagnostic);
      if Is_Poisoned (Budget) then
         Set (Diagnostic, Resource_Exhausted);
         return;
      end if;
      Validate (Value);
      Charge_Work (Budget, Model_Work, Accepted);
      if not Accepted then
         raise Exhausted;
      end if;
      Start_Rendered_Artifact (Budget, Accepted);
      if not Accepted then
         raise Exhausted;
      end if;
      Start_Rendered_Artifact (Budget, Accepted);
      if not Accepted then
         raise Exhausted;
      end if;
      Candidate :=
        new Artifact_Data'
          (Specification_Name    => To_Unbounded_String (File_Stem (Output_Unit (Value)) & ".ads"),
           Specification_Payload => Null_Unbounded_String,
           Body_Name             => To_Unbounded_String (File_Stem (Output_Unit (Value)) & ".adb"),
           Body_Payload          => Null_Unbounded_String);
      declare
         Spec_Output : Output_Sink (Budget'Access, Candidate.Specification_Payload'Access);
         Body_Output : Output_Sink (Budget'Access, Candidate.Body_Payload'Access);
      begin
         Emit_Spec (Value, Spec_Output);
         Emit_Body (Value, Body_Output);
         if not Spec_Output.Last_Was_LF
           or else not Body_Output.Last_Was_LF
           or else Length (Candidate.Specification_Payload) /= Spec_Output.Bytes
           or else Length (Candidate.Body_Payload) /= Body_Output.Bytes
         then
            raise Invalid_Render;
         end if;
      end;
      Previous := Into.Data;
      Into.Data := Candidate;
      Candidate := null;
      Discard (Previous);
   exception
      when Unsupported_Model =>
         Discard (Candidate);
         Set (Diagnostic, Unsupported_Lowered_Model);
      when Invalid_Render =>
         Discard (Candidate);
         Poison (Budget);
         Set (Diagnostic, Internal_Error);
      when Exhausted =>
         Discard (Candidate);
         Set (Diagnostic, Resource_Exhausted);
      when Storage_Error =>
         Discard (Candidate);
         Poison (Budget);
         if Code (Diagnostic) = No_Error then
            Set (Diagnostic, Internal_Error);
         end if;
      when others =>
         Discard (Candidate);
         Poison (Budget);
         if Code (Diagnostic) = No_Error then
            Set (Diagnostic, Internal_Error);
         end if;
   end Render_Payload;

   function Is_Valid (Value : Rendered_Artifacts) return Boolean is (Value.Data /= null);

   function Artifact_Count (Value : Rendered_Artifacts) return Natural is
     (if Value.Data = null then 0 else 2);

   function File_Name (Value : Rendered_Artifacts; Kind : Artifact_Kind) return String is
     (case Kind is
        when Specification => To_String (Value.Data.Specification_Name),
        when Package_Body  => To_String (Value.Data.Body_Name));

   function Payload_Length (Value : Rendered_Artifacts; Kind : Artifact_Kind) return Natural is
     (case Kind is
        when Specification => Length (Value.Data.Specification_Payload),
        when Package_Body  => Length (Value.Data.Body_Payload));

   procedure Copy_Payload
     (Value   : Rendered_Artifacts;
      Kind    : Artifact_Kind;
      Into    : in out String;
      Written : in out Natural;
      Copied  : out Boolean)
   is
      Source_Length : constant Natural := Payload_Length (Value, Kind);
   begin
      Copied := Into'Length >= Source_Length;
      if not Copied then
         return;
      end if;
      for Index in 1 .. Source_Length loop
         Into (Into'First + Index - 1) :=
           (case Kind is
              when Specification => Element (Value.Data.Specification_Payload, Index),
              when Package_Body  => Element (Value.Data.Body_Payload, Index));
      end loop;
      Written := Source_Length;
   end Copy_Payload;

   overriding procedure Finalize (Value : in out Rendered_Artifacts) is
   begin
      Discard (Value.Data);
   exception
      when others =>
         null;
   end Finalize;
end Flyology_Serde_Generator.Rendering;
