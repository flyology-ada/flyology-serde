with Ada.Characters.Handling;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Unchecked_Deallocation;
with Flyology_Serde_Generator.Graph_Work;

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

   procedure Free is new
     Ada.Unchecked_Deallocation
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
   Invalid_Render    : exception;
   Exhausted         : exception;

   type Output_Sink
     (Measure_Only : Boolean;
      Budget       : access Operation_Budget;
      Target       : access Unbounded_String)
   is limited record
      Bytes       : Natural := 0;
      Column      : Natural := 0;
      Last_Was_LF : Boolean := False;
   end record;

   procedure Put (Into : in out Output_Sink; Text : String) is
      Accepted     : Boolean;
      Next_Column  : Natural := Into.Column;
      Next_Last_LF : Boolean := Into.Last_Was_LF;
   begin
      if Text'Length > Natural'Last - Into.Bytes then
         raise Unsupported_Model;
      end if;
      for Item of Text loop
         if Character'Pos (Item) > 127
           or else Item = ASCII.CR
           or else Item = ASCII.NUL
         then
            raise Unsupported_Model;
         elsif Item = ASCII.LF then
            Next_Column := 0;
            Next_Last_LF := True;
         else
            if Next_Column = 110 then
               raise Unsupported_Model;
            end if;
            Next_Column := Next_Column + 1;
            Next_Last_LF := False;
         end if;
      end loop;
      if not Into.Measure_Only then
         if Into.Budget = null or else Into.Target = null then
            raise Invalid_Render;
         end if;
         Charge_Rendered_Chunk
           (Into.Budget.all, Into.Bytes, Text'Length, Accepted);
         if not Accepted then
            raise Exhausted;
         end if;
      end if;
      Into.Bytes := Into.Bytes + Text'Length;
      Into.Column := Next_Column;
      Into.Last_Was_LF := Next_Last_LF;
      if not Into.Measure_Only then
         Append (Into.Target.all, Text);
      end if;
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

   function Is_ASCII_Letter (Value : Character) return Boolean
   is (Value in 'A' .. 'Z' or else Value in 'a' .. 'z');

   function Is_ASCII_Digit (Value : Character) return Boolean
   is (Value in '0' .. '9');

   function Is_Reserved (Value : String) return Boolean is
      Lower : constant String := Ada.Characters.Handling.To_Lower (Value);
      Words : constant String :=
        "|abort|abs|abstract|accept|access|aliased|all|and|array|at|begin|body|case|constant|"
        & "declare|delay|delta|digits|do|else|elsif|end|entry|exception|exit|for|function|"
        & "generic|goto|if|in|interface|is|limited|loop|mod|new|not|null|of|or|others|out|"
        & "overriding|package|parallel|pragma|private|procedure|protected|raise|range|record|"
        & "rem|renames|requeue|return|reverse|select|separate|some|subtype|synchronized|tagged|"
        & "task|terminate|then|type|until|use|when|while|with|xor|";
   begin
      return Ada.Strings.Fixed.Index (Words, "|" & Lower & "|") /= 0;
   end Is_Reserved;

   function Is_Identifier (Value : String) return Boolean is
   begin
      if Value'Length = 0
        or else not Is_ASCII_Letter (Value (Value'First))
        or else not (Is_ASCII_Letter (Value (Value'Last))
                     or else Is_ASCII_Digit (Value (Value'Last)))
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
            if Index = Start
              or else not Is_Identifier (Value (Start .. Index - 1))
            then
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

   function Equal_Ignoring_Case (Left, Right : String) return Boolean
   is (Ada.Characters.Handling.To_Lower (Left)
       = Ada.Characters.Handling.To_Lower (Right));

   function Same_Or_Ancestor (Left, Right : String) return Boolean is
      Lower_Left  : constant String := Ada.Characters.Handling.To_Lower (Left);
      Lower_Right : constant String :=
        Ada.Characters.Handling.To_Lower (Right);
   begin
      return
        Lower_Left = Lower_Right
        or else (Lower_Left'Length < Lower_Right'Length
                 and then Lower_Right
                            (Lower_Right'First
                             .. Lower_Right'First + Lower_Left'Length - 1)
                          = Lower_Left
                 and then Lower_Right (Lower_Right'First + Lower_Left'Length)
                          = '.');
   end Same_Or_Ancestor;

   function Adapter_Name (Index : Positive) return String;

   function Graph_Adapter_Name (Node : Positive) return String
   is ("Type_" & Image (Node) & "_Adapter");

   function Has_Node_Kind (Value : Model; Kind : Type_Node_Kind) return Boolean
   is (for some Node in 1 .. Type_Node_Count (Value) =>
         Node_Kind (Value, Node) = Kind);

   function Defining_Scope (Ada_Type : String) return String is
      Separator : Natural := 0;
   begin
      for Index in reverse Ada_Type'Range loop
         if Ada_Type (Index) = '.' then
            Separator := Index;
            exit;
         end if;
      end loop;
      if Separator = 0 or else Separator = Ada_Type'First then
         raise Unsupported_Model;
      end if;
      return Ada_Type (Ada_Type'First .. Separator - 1);
   end Defining_Scope;

   function Enumeration_Literal
     (Value : Model; Node : Positive; Position : Positive) return String
   is (Defining_Scope (Node_Ada_Type (Value, Node))
       & "."
       & Enumeration_Literal_Ada_Name (Value, Node, Position));

   function Is_Value_Reachable_Enumeration
     (Value : Model; Node : Positive) return Boolean is
   begin
      for Field in 1 .. Field_Count (Value) loop
         declare
            Field_Node : constant Positive := Field_Type_Node (Value, Field);
         begin
            if Field_Node = Node then
               return True;
            elsif Node_Kind (Value, Field_Node) = Fixed_Array_Node
              and then Array_Element_Node (Value, Field_Node) = Node
            then
               return True;
            end if;
         end;
      end loop;
      return False;
   end Is_Value_Reachable_Enumeration;

   function Is_Reachable (Value : Model; Node : Positive) return Boolean is
   begin
      if Node = Root_Node (Value) then
         return True;
      end if;
      for Field in 1 .. Field_Count (Value) loop
         declare
            Field_Node : constant Positive := Field_Type_Node (Value, Field);
         begin
            if Field_Node = Node
              or else (Node_Kind (Value, Field_Node) = Fixed_Array_Node
                       and then (Array_Index_Node (Value, Field_Node) = Node
                                 or else Array_Element_Node (Value, Field_Node)
                                         = Node))
            then
               return True;
            end if;
         end;
      end loop;
      return False;
   end Is_Reachable;

   function Presentation_Name_Is_Unique
     (Value    : Model;
      Node     : Positive;
      Position : Positive;
      Alias    : Natural;
      Name     : String) return Boolean is
   begin
      for Other_Position in 1 .. Enumeration_Literal_Count (Value, Node) loop
         if Other_Position /= Position or else Alias /= 0 then
            if Enumeration_Literal_Primary_Name (Value, Node, Other_Position)
              = Name
            then
               return False;
            end if;
         end if;
         for Other_Alias in
           1 .. Enumeration_Literal_Alias_Count (Value, Node, Other_Position)
         loop
            if (Other_Position /= Position or else Other_Alias /= Alias)
              and then Enumeration_Literal_Alias_Name
                         (Value, Node, Other_Position, Other_Alias)
                       = Name
            then
               return False;
            end if;
         end loop;
      end loop;
      return True;
   end Presentation_Name_Is_Unique;

   procedure Graph_Size
     (Value      : Model;
      Members    : out Natural;
      Text_Bytes : out Natural;
      Work       : out Natural)
   is
      M     : Natural := 0;
      S     : Natural := Output_Unit (Value)'Length;
      Valid : Boolean := False;

      procedure Add_Text (Text : String) is
      begin
         if Text'Length > Natural'Last - S then
            raise Unsupported_Model;
         end if;
         S := S + Text'Length;
      end Add_Text;

      procedure Add_Member is
      begin
         if M = Natural'Last then
            raise Unsupported_Model;
         end if;
         M := M + 1;
      end Add_Member;
   begin
      for Index in 1 .. With_Unit_Count (Value) loop
         Add_Member;
         Add_Text (With_Unit (Value, Index));
      end loop;
      for Node in 1 .. Type_Node_Count (Value) loop
         Add_Member;
         Add_Text (Node_Ada_Type (Value, Node));
         Add_Text (Node_Logical_Name (Value, Node));
         if Node_Kind (Value, Node) = Enumeration_Node then
            for Position in 1 .. Enumeration_Literal_Count (Value, Node) loop
               Add_Member;
               Add_Text (Enumeration_Literal_Ada_Name (Value, Node, Position));
               Add_Text
                 (Enumeration_Literal_Primary_Name (Value, Node, Position));
               for Alias in
                 1 .. Enumeration_Literal_Alias_Count (Value, Node, Position)
               loop
                  Add_Member;
                  Add_Text
                    (Enumeration_Literal_Alias_Name
                       (Value, Node, Position, Alias));
               end loop;
            end loop;
         end if;
      end loop;
      for Field in 1 .. Field_Count (Value) loop
         Add_Member;
         Add_Text (Field_Ada_Component (Value, Field));
         Add_Text (Field_Presentation_Name (Value, Field));
      end loop;

      Flyology_Serde_Generator.Graph_Work.Compute (M, S, Work, Valid);
      if not Valid then
         raise Unsupported_Model;
      end if;
      Members := M;
      Text_Bytes := S;
   end Graph_Size;

   procedure Validate_Graph
     (Value : Model; Require_Published : Boolean := True)
   is
      Limits       : constant Runtime_Limit_Set := Runtime_Limits (Value);
      Record_Count : Natural := 0;
      With_Used    :
        array (Positive range 1 .. With_Unit_Count (Value)) of Boolean :=
          [others => False];
   begin
      if (Require_Published and then not Is_Valid (Value))
        or else not Has_Type_Graph (Value)
        or else Type_Node_Count (Value) = 0
        or else Root_Node (Value) /= Type_Node_Count (Value)
        or else Node_Kind (Value, Root_Node (Value)) /= Record_Node
        or else Field_Count (Value) = 0
        or else not Is_Selected_Name (Output_Unit (Value))
        or else Same_Or_Ancestor (Output_Unit (Value), "Flyology_Serde")
        or else Same_Or_Ancestor ("Flyology_Serde", Output_Unit (Value))
        or else With_Unit_Count (Value) = 0
        or else Limits.Maximum_Nesting_Depth not in 1 .. 256
        or else Limits.Maximum_Container_Items = 0
        or else Limits.Maximum_Text_Length not in 1 .. 128
        or else Limits.Maximum_Byte_Length = 0
        or else Limits.Maximum_Logical_Events = 0
      then
         raise Unsupported_Model;
      end if;

      for Index in 1 .. With_Unit_Count (Value) loop
         if not Is_Selected_Name (With_Unit (Value, Index))
           or else Same_Or_Ancestor
                     (With_Unit (Value, Index), "Flyology_Serde")
           or else Same_Or_Ancestor
                     ("Flyology_Serde", With_Unit (Value, Index))
           or else Same_Or_Ancestor
                     (With_Unit (Value, Index), Output_Unit (Value))
           or else Same_Or_Ancestor
                     (Output_Unit (Value), With_Unit (Value, Index))
         then
            raise Unsupported_Model;
         end if;
         for Prior in 1 .. Index - 1 loop
            if Equal_Ignoring_Case
                 (With_Unit (Value, Prior), With_Unit (Value, Index))
            then
               raise Unsupported_Model;
            end if;
         end loop;
      end loop;

      for Node in 1 .. Type_Node_Count (Value) loop
         if not Is_Selected_Name (Node_Ada_Type (Value, Node))
           or else not Is_Reachable (Value, Node)
           or else (Node_Kind (Value, Node) = Boolean_Node
                    and then Node_Defining_With (Value, Node) /= 0)
           or else (Node_Kind (Value, Node) /= Boolean_Node
                    and then Node_Defining_With (Value, Node) = 0)
           or else Node_Defining_With (Value, Node) > With_Unit_Count (Value)
         then
            raise Unsupported_Model;
         end if;
         if Node_Kind (Value, Node) /= Boolean_Node then
            declare
               Binding : constant Positive := Node_Defining_With (Value, Node);
               Unit    : constant String := With_Unit (Value, Binding);
               Name    : constant String := Node_Ada_Type (Value, Node);
            begin
               if Equal_Ignoring_Case (Unit, Name)
                 or else not Same_Or_Ancestor (Unit, Name)
               then
                  raise Unsupported_Model;
               end if;
               With_Used (Binding) := True;
            end;
         end if;
         for Prior in 1 .. Node - 1 loop
            if Equal_Ignoring_Case
                 (Node_Ada_Type (Value, Prior), Node_Ada_Type (Value, Node))
            then
               raise Unsupported_Model;
            end if;
         end loop;
         case Node_Kind (Value, Node) is
            when Boolean_Node                      =>
               if not Equal_Ignoring_Case
                        (Node_Ada_Type (Value, Node), "Standard.Boolean")
                 or else Node_Logical_Name (Value, Node)'Length /= 0
               then
                  raise Unsupported_Model;
               end if;

            when Signed_64_Node | Unsigned_64_Node =>
               if Node_Logical_Name (Value, Node)'Length /= 0 then
                  raise Unsupported_Model;
               end if;

            when Enumeration_Node                  =>
               if Enumeration_Literal_Count (Value, Node) = 0 then
                  raise Unsupported_Model;
               end if;
               for Position in 1 .. Enumeration_Literal_Count (Value, Node)
               loop
                  if not Is_Identifier
                           (Enumeration_Literal_Ada_Name
                              (Value, Node, Position))
                  then
                     raise Unsupported_Model;
                  end if;
                  for Prior in 1 .. Position - 1 loop
                     if Equal_Ignoring_Case
                          (Enumeration_Literal_Ada_Name (Value, Node, Prior),
                           Enumeration_Literal_Ada_Name
                             (Value, Node, Position))
                     then
                        raise Unsupported_Model;
                     end if;
                  end loop;
                  if Is_Value_Reachable_Enumeration (Value, Node) then
                     if not Is_Logical_Name (Node_Logical_Name (Value, Node))
                       or else Node_Logical_Name (Value, Node)'Length
                               > Limits.Maximum_Text_Length
                       or else not Is_Logical_Name
                                     (Enumeration_Literal_Primary_Name
                                        (Value, Node, Position))
                       or else Enumeration_Literal_Primary_Name
                                 (Value, Node, Position)'Length
                               > Limits.Maximum_Text_Length
                       or else not Presentation_Name_Is_Unique
                                     (Value,
                                      Node,
                                      Position,
                                      0,
                                      Enumeration_Literal_Primary_Name
                                        (Value, Node, Position))
                     then
                        raise Unsupported_Model;
                     end if;
                     for Alias in
                       1
                       .. Enumeration_Literal_Alias_Count
                            (Value, Node, Position)
                     loop
                        if not Is_Logical_Name
                                 (Enumeration_Literal_Alias_Name
                                    (Value, Node, Position, Alias))
                          or else Enumeration_Literal_Alias_Name
                                    (Value, Node, Position, Alias)'Length
                                  > Limits.Maximum_Text_Length
                          or else not Presentation_Name_Is_Unique
                                        (Value,
                                         Node,
                                         Position,
                                         Alias,
                                         Enumeration_Literal_Alias_Name
                                           (Value, Node, Position, Alias))
                        then
                           raise Unsupported_Model;
                        end if;
                     end loop;
                  elsif Node_Logical_Name (Value, Node)'Length /= 0
                    or else Enumeration_Literal_Primary_Name
                              (Value, Node, Position)'Length
                            /= 0
                    or else Enumeration_Literal_Alias_Count
                              (Value, Node, Position)
                            /= 0
                  then
                     raise Unsupported_Model;
                  end if;
               end loop;

            when Fixed_Array_Node                  =>
               if Node_Logical_Name (Value, Node)'Length /= 0
                 or else Array_Index_Node (Value, Node) >= Node
                 or else Array_Element_Node (Value, Node) >= Node
                 or else Node_Kind (Value, Array_Index_Node (Value, Node))
                         /= Enumeration_Node
                 or else Node_Kind (Value, Array_Element_Node (Value, Node))
                         not in Boolean_Node
                              | Signed_64_Node
                              | Unsigned_64_Node
                              | Enumeration_Node
               then
                  raise Unsupported_Model;
               end if;

            when Record_Node                       =>
               Record_Count := Record_Count + 1;
               if Node /= Root_Node (Value)
                 or else not Is_Logical_Name (Node_Logical_Name (Value, Node))
                 or else Node_Logical_Name (Value, Node)'Length
                         > Limits.Maximum_Text_Length
               then
                  raise Unsupported_Model;
               end if;
         end case;
      end loop;

      if (for some Used of With_Used => not Used) then
         raise Unsupported_Model;
      end if;
      if Record_Count /= 1 then
         raise Unsupported_Model;
      end if;

      for Field in 1 .. Field_Count (Value) loop
         if Field_Type_Node (Value, Field) >= Root_Node (Value)
           or else not Is_Identifier (Field_Ada_Component (Value, Field))
           or else not Is_Logical_Name (Field_Presentation_Name (Value, Field))
           or else Field_Presentation_Name (Value, Field)'Length
                   > Limits.Maximum_Text_Length
         then
            raise Unsupported_Model;
         end if;
         for Prior in 1 .. Field - 1 loop
            if Equal_Ignoring_Case
                 (Field_Ada_Component (Value, Prior),
                  Field_Ada_Component (Value, Field))
              or else Field_Presentation_Name (Value, Prior)
                      = Field_Presentation_Name (Value, Field)
            then
               raise Unsupported_Model;
            end if;
         end loop;
      end loop;
   end Validate_Graph;

   procedure Validate (Value : Model; Require_Published : Boolean := True) is
      Limits : constant Runtime_Limit_Set := Runtime_Limits (Value);

      procedure Require_Line (Text : String) is
      begin
         if Text'Length > 110 then
            raise Unsupported_Model;
         end if;
      end Require_Line;
   begin
      if Has_Type_Graph (Value) then
         Validate_Graph (Value, Require_Published);
         return;
      end if;
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
            if Equal_Ignoring_Case
                 (With_Unit (Value, Prior), With_Unit (Value, Index))
            then
               raise Unsupported_Model;
            end if;
         end loop;
         Require_Line ("with " & With_Unit (Value, Index) & ";");
      end loop;
      Require_Line ("package " & Output_Unit (Value) & " is");
      Require_Line ("package body " & Output_Unit (Value) & " is");
      Require_Line ("end " & Output_Unit (Value) & ";");
      Require_Line
        ("   function Value (Target : Builder) return "
         & Record_Ada_Type (Value));
      Require_Line ("      Published : " & Record_Ada_Type (Value) & ";");
      Require_Line ("      Candidate : " & Record_Ada_Type (Value) & ";");
      Require_Line ("     (Item  : " & Record_Ada_Type (Value) & ";");
      Require_Line ("      Value  : " & Record_Ada_Type (Value) & ";");
      Require_Line
        ("      Into.Begin_Record ("
         & Ada_Literal (Logical_Type_Name (Value))
         & ", "
         & Image (Field_Count (Value))
         & ", Error);");
      Require_Line
        ("      From.Begin_Record ("
         & Ada_Literal (Logical_Type_Name (Value))
         & ", Length, Error);");
      for Index in 1 .. Field_Count (Value) loop
         if not Is_Identifier (Field_Ada_Component (Value, Index))
           or else not Is_Selected_Name (Field_Ada_Type (Value, Index))
           or else not Is_Logical_Name (Field_Presentation_Name (Value, Index))
         then
            raise Unsupported_Model;
         end if;
         for Prior in 1 .. Index - 1 loop
            if Equal_Ignoring_Case
                 (Field_Ada_Component (Value, Prior),
                  Field_Ada_Component (Value, Index))
              or else Field_Presentation_Name (Value, Prior)
                      = Field_Presentation_Name (Value, Index)
            then
               raise Unsupported_Model;
            end if;
         end loop;
         Require_Line
           ("      Into.Put_Field ("
            & Ada_Literal (Field_Presentation_Name (Value, Index))
            & ", Error);");
         Require_Line
           ("         "
            & (if Index = 1 then "if" else "elsif")
            & " Name (1 .. Name_Last) = "
            & Ada_Literal (Field_Presentation_Name (Value, Index))
            & " then");
         Require_Line
           ("         Flyology_Serde.Errors.Push_Field (Error, "
            & Ada_Literal (Field_Presentation_Name (Value, Index))
            & ");");
         if Field_Scalar_Kind (Value, Index) = Boolean_Scalar then
            Require_Line
              ("      Into.Put_Boolean (Item."
               & Field_Ada_Component (Value, Index)
               & ", Error);");
            Require_Line
              ("                  From.Read_Boolean (Target.Candidate."
               & Field_Ada_Component (Value, Index)
               & ", Error);");
         else
            Require_Line
              ("   package "
               & Adapter_Name (Index)
               & " is new Flyology_Serde.Adapters."
               & (if Field_Scalar_Kind (Value, Index) = Signed_64_Scalar
                  then "Signed_Integers"
                  else "Unsigned_Integers"));
            Require_Line ("     (" & Field_Ada_Type (Value, Index) & ");");
            Require_Line
              ("      "
               & Adapter_Name (Index)
               & ".Serialize_Value (Item."
               & Field_Ada_Component (Value, Index)
               & ", Into, Error);");
            Require_Line
              ("                  "
               & Adapter_Name (Index)
               & ".Deserialize_Candidate "
               & "(From, Target.Candidate."
               & Field_Ada_Component (Value, Index)
               & ", Error);");
         end if;
      end loop;
   end Validate;

   function Adapter_Name (Index : Positive) return String
   is ("Field_" & Image (Index) & "_Adapter");

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
      Put_Line
        (Into, "      Error  : in out Flyology_Serde.Errors.Error_Info);");
      Put_Line
        (Into, "   function Has_Value (Target : Builder) return Boolean;");
      Put_Line
        (Into, "   function Value (Target : Builder) return " & Ada_Type);
      Put_Line (Into, "   with Pre => Has_Value (Target);");
      Put_Line (Into);
      Put_Line (Into, "   procedure Serialize");
      Put_Line (Into, "     (Item  : " & Ada_Type & ";");
      Put_Line
        (Into,
         "      Into  : in out Flyology_Serde.Serialization.Serializer'Class;");
      Put_Line
        (Into, "      Error : in out Flyology_Serde.Errors.Error_Info);");
      Put_Line (Into);
      Put_Line (Into, "   procedure Deserialize");
      Put_Line
        (Into,
         "     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;");
      Put_Line (Into, "      Target : in out Builder;");
      Put_Line
        (Into, "      Error  : in out Flyology_Serde.Errors.Error_Info);");
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

   function Maximum_Aliases (Value : Model; Node : Positive) return Natural is
      Result : Natural := 0;
   begin
      for Position in 1 .. Enumeration_Literal_Count (Value, Node) loop
         Result :=
           Natural'Max
             (Result, Enumeration_Literal_Alias_Count (Value, Node, Position));
      end loop;
      return Result;
   end Maximum_Aliases;

   procedure Emit_Enumeration_Adapter
     (Value : Model; Node : Positive; Into : in out Output_Sink)
   is
      Prefix   : constant String := "Type_" & Image (Node);
      Ada_Type : constant String := Node_Ada_Type (Value, Node);
   begin
      Put_Line
        (Into,
         "   function "
         & Prefix
         & "_Primary_Name (Value : "
         & Ada_Type
         & ") return String is");
      Put_Line (Into, "     (case Value is");
      for Position in 1 .. Enumeration_Literal_Count (Value, Node) loop
         Put_Line
           (Into,
            "         when "
            & Enumeration_Literal (Value, Node, Position)
            & " => "
            & Ada_Literal
                (Enumeration_Literal_Primary_Name (Value, Node, Position))
            & (if Position = Enumeration_Literal_Count (Value, Node)
               then ");"
               else ","));
      end loop;
      Put_Line (Into);

      Put_Line
        (Into,
         "   function "
         & Prefix
         & "_Alias_Count (Value : "
         & Ada_Type
         & ") return Natural is");
      Put_Line (Into, "     (case Value is");
      for Position in 1 .. Enumeration_Literal_Count (Value, Node) loop
         Put_Line
           (Into,
            "         when "
            & Enumeration_Literal (Value, Node, Position)
            & " => "
            & Image (Enumeration_Literal_Alias_Count (Value, Node, Position))
            & (if Position = Enumeration_Literal_Count (Value, Node)
               then ");"
               else ","));
      end loop;
      Put_Line (Into);

      Put_Line (Into, "   function " & Prefix & "_Alias_Name");
      Put_Line
        (Into,
         "     (Value : "
         & Ada_Type
         & "; Position : Positive) return String is");
      Put_Line (Into, "     (case Value is");
      for Literal in 1 .. Enumeration_Literal_Count (Value, Node) loop
         declare
            Alias_Count : constant Natural :=
              Enumeration_Literal_Alias_Count (Value, Node, Literal);
         begin
            Put_Line
              (Into,
               "         when "
               & Enumeration_Literal (Value, Node, Literal)
               & " =>");
            if Alias_Count = 0 then
               Put_Line
                 (Into,
                  "           "
                  & Ada_Literal ("")
                  & (if Literal = Enumeration_Literal_Count (Value, Node)
                     then ");"
                     else ","));
            else
               Put_Line (Into, "           (case Position is");
               for Alias in 1 .. Alias_Count loop
                  Put_Line
                    (Into,
                     "               when "
                     & Image (Alias)
                     & " => "
                     & Ada_Literal
                         (Enumeration_Literal_Alias_Name
                            (Value, Node, Literal, Alias))
                     & ",");
               end loop;
               Put_Line
                 (Into,
                  "               when others => "
                  & Ada_Literal ("")
                  & ")"
                  & (if Literal = Enumeration_Literal_Count (Value, Node)
                     then ");"
                     else ","));
            end if;
         end;
      end loop;
      Put_Line (Into);

      Put_Line (Into, "   function " & Prefix & "_Matches");
      Put_Line
        (Into,
         "     (Value : " & Ada_Type & "; Name : String) return Boolean is");
      Put_Line (Into, "     (case Value is");
      for Literal in 1 .. Enumeration_Literal_Count (Value, Node) loop
         Put
           (Into,
            "         when "
            & Enumeration_Literal (Value, Node, Literal)
            & " => Name = "
            & Ada_Literal
                (Enumeration_Literal_Primary_Name (Value, Node, Literal)));
         for Alias in
           1 .. Enumeration_Literal_Alias_Count (Value, Node, Literal)
         loop
            Put
              (Into,
               " or else Name = "
               & Ada_Literal
                   (Enumeration_Literal_Alias_Name
                      (Value, Node, Literal, Alias)));
         end loop;
         Put_Line
           (Into,
            (if Literal = Enumeration_Literal_Count (Value, Node)
             then ");"
             else ","));
      end loop;
      Put_Line (Into);

      Put_Line
        (Into,
         "   package "
         & Graph_Adapter_Name (Node)
         & " is new Flyology_Serde.Adapters.Enumerations");
      Put_Line
        (Into, "     (Value_Type                  => " & Ada_Type & ",");
      Put_Line
        (Into,
         "      Type_Name                   => "
         & Ada_Literal (Node_Logical_Name (Value, Node))
         & ",");
      Put_Line
        (Into,
         "      Maximum_Type_Name_Length    => "
         & Image (Runtime_Limits (Value).Maximum_Text_Length)
         & ",");
      Put_Line
        (Into,
         "      Maximum_Literals            => "
         & Image (Enumeration_Literal_Count (Value, Node))
         & ",");
      Put_Line
        (Into,
         "      Maximum_Literal_Name_Length => "
         & Image (Runtime_Limits (Value).Maximum_Text_Length)
         & ",");
      Put_Line
        (Into,
         "      Maximum_Aliases_Per_Literal => "
         & Image (Maximum_Aliases (Value, Node))
         & ",");
      Put_Line
        (Into,
         "      Primary_Name                => " & Prefix & "_Primary_Name,");
      Put_Line
        (Into,
         "      Alias_Count                 => " & Prefix & "_Alias_Count,");
      Put_Line
        (Into,
         "      Alias_Name                  => " & Prefix & "_Alias_Name,");
      Put_Line
        (Into,
         "      Matches_Literal             => " & Prefix & "_Matches);");
      Put_Line (Into);
   end Emit_Enumeration_Adapter;

   procedure Emit_Array_Adapter
     (Value : Model; Node : Positive; Into : in out Output_Sink)
   is
      Prefix       : constant String := "Type_" & Image (Node);
      Element_Node : constant Positive := Array_Element_Node (Value, Node);
      Element_Type : constant String := Node_Ada_Type (Value, Element_Node);
   begin
      Put_Line (Into, "   procedure " & Prefix & "_Serialize_Element");
      Put_Line (Into, "     (Item  : " & Element_Type & ";");
      Put_Line
        (Into,
         "      Into  : in out Flyology_Serde.Serialization.Serializer'Class;");
      Put_Line
        (Into, "      Error : in out Flyology_Serde.Errors.Error_Info) is");
      Put_Line (Into, "   begin");
      case Node_Kind (Value, Element_Node) is
         when Boolean_Node                                         =>
            Put_Line (Into, "      Into.Put_Boolean (Item, Error);");

         when Signed_64_Node | Unsigned_64_Node | Enumeration_Node =>
            Put_Line
              (Into,
               "      "
               & Graph_Adapter_Name (Element_Node)
               & ".Serialize_Value (Item, Into, Error);");

         when others                                               =>
            raise Unsupported_Model;
      end case;
      Put_Line (Into, "   end " & Prefix & "_Serialize_Element;");
      Put_Line (Into);

      Put_Line (Into, "   procedure " & Prefix & "_Deserialize_Element");
      Put_Line
        (Into,
         "     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;");
      Put_Line (Into, "      Target : in out " & Element_Type & ";");
      Put_Line (Into, "      Policy : Flyology_Serde.Policies.Decode_Policy;");
      Put_Line
        (Into, "      Error  : in out Flyology_Serde.Errors.Error_Info) is");
      if Node_Kind (Value, Element_Node) /= Fixed_Array_Node then
         Put_Line (Into, "      pragma Unreferenced (Policy);");
      end if;
      Put_Line (Into, "   begin");
      case Node_Kind (Value, Element_Node) is
         when Boolean_Node                                         =>
            Put_Line (Into, "      From.Read_Boolean (Target, Error);");

         when Signed_64_Node | Unsigned_64_Node | Enumeration_Node =>
            Put_Line
              (Into,
               "      "
               & Graph_Adapter_Name (Element_Node)
               & ".Deserialize_Candidate (From, Target, Error);");

         when others                                               =>
            raise Unsupported_Model;
      end case;
      Put_Line (Into, "   end " & Prefix & "_Deserialize_Element;");
      Put_Line (Into);

      Put_Line
        (Into,
         "   package "
         & Graph_Adapter_Name (Node)
         & " is new Flyology_Serde.Adapters.Fixed_Arrays");
      Put_Line
        (Into,
         "     (Index_Type          => "
         & Node_Ada_Type (Value, Array_Index_Node (Value, Node))
         & ",");
      Put_Line (Into, "      Element_Type        => " & Element_Type & ",");
      Put_Line
        (Into,
         "      Array_Type          => " & Node_Ada_Type (Value, Node) & ",");
      Put_Line
        (Into,
         "      Serialize_Element   => " & Prefix & "_Serialize_Element,");
      Put_Line
        (Into,
         "      Deserialize_Element => " & Prefix & "_Deserialize_Element);");
      Put_Line (Into);
   end Emit_Array_Adapter;

   procedure Emit_Graph_Body (Value : Model; Into : in out Output_Sink) is
      Unit_Name : constant String := Output_Unit (Value);
      Ada_Type  : constant String := Record_Ada_Type (Value);
      Limits    : constant Runtime_Limit_Set := Runtime_Limits (Value);

      procedure Serialize_Field (Field : Positive) is
         Node       : constant Positive := Field_Type_Node (Value, Field);
         Expression : constant String :=
           "Item." & Field_Ada_Component (Value, Field);
      begin
         case Node_Kind (Value, Node) is
            when Boolean_Node =>
               Put_Line
                 (Into, "      Into.Put_Boolean (" & Expression & ", Error);");

            when others       =>
               Put_Line
                 (Into,
                  "      "
                  & Graph_Adapter_Name (Node)
                  & ".Serialize_Value ("
                  & Expression
                  & ", Into, Error);");
         end case;
      end Serialize_Field;

      procedure Deserialize_Field (Field : Positive) is
         Node       : constant Positive := Field_Type_Node (Value, Field);
         Expression : constant String :=
           "Target.Candidate." & Field_Ada_Component (Value, Field);
      begin
         case Node_Kind (Value, Node) is
            when Boolean_Node     =>
               Put_Line
                 (Into,
                  "                  From.Read_Boolean ("
                  & Expression
                  & ", Error);");

            when Fixed_Array_Node =>
               Put_Line
                 (Into,
                  "                  "
                  & Graph_Adapter_Name (Node)
                  & ".Deserialize_Candidate");
               Put_Line
                 (Into,
                  "                    (From, "
                  & Expression
                  & ", Policy, Error);");

            when others           =>
               Put_Line
                 (Into,
                  "                  "
                  & Graph_Adapter_Name (Node)
                  & ".Deserialize_Candidate (From, "
                  & Expression
                  & ", Error);");
         end case;
      end Deserialize_Field;
   begin
      Put_Line (Into, "with Flyology_Serde.Adapters.Enumerations;");
      Put_Line (Into, "with Flyology_Serde.Adapters.Fixed_Arrays;");
      if Has_Node_Kind (Value, Signed_64_Node) then
         Put_Line (Into, "with Flyology_Serde.Adapters.Signed_Integers;");
      end if;
      if Has_Node_Kind (Value, Unsigned_64_Node) then
         Put_Line (Into, "with Flyology_Serde.Adapters.Unsigned_Integers;");
      end if;
      Put_Line (Into, "with Flyology_Serde.Data_Model;");
      Put_Line (Into, "with Flyology_Serde.Deserialization_Adapters;");
      Put_Line (Into, "with Flyology_Serde.Policies;");
      Put_Line (Into, "with Flyology_Serde.Serialization_Adapters;");
      Put_Line (Into);
      Put_Line (Into, "package body " & Unit_Name & " is");
      Put_Line (Into, "   use type Flyology_Serde.Errors.Error_Code;");
      Put_Line (Into);

      for Node in 1 .. Type_Node_Count (Value) loop
         case Node_Kind (Value, Node) is
            when Signed_64_Node   =>
               Put_Line
                 (Into,
                  "   package "
                  & Graph_Adapter_Name (Node)
                  & " is new Flyology_Serde.Adapters.Signed_Integers");
               Put_Line (Into, "     (" & Node_Ada_Type (Value, Node) & ");");
               Put_Line (Into);

            when Unsigned_64_Node =>
               Put_Line
                 (Into,
                  "   package "
                  & Graph_Adapter_Name (Node)
                  & " is new Flyology_Serde.Adapters.Unsigned_Integers");
               Put_Line (Into, "     (" & Node_Ada_Type (Value, Node) & ");");
               Put_Line (Into);

            when Enumeration_Node =>
               if Is_Value_Reachable_Enumeration (Value, Node) then
                  Emit_Enumeration_Adapter (Value, Node, Into);
               end if;

            when Fixed_Array_Node =>
               Emit_Array_Adapter (Value, Node, Into);

            when others           =>
               null;
         end case;
      end loop;

      Put_Line
        (Into,
         "   Default_Policy : constant Flyology_Serde.Policies.Decode_Policy := (others => <>);");
      Put_Line (Into);
      Put_Line
        (Into,
         "   Serialization_Limits : constant Flyology_Serde.Serialization.Serialization_Limits :=");
      Put_Line
        (Into,
         "     (Maximum_Nesting_Depth   => "
         & Image (Limits.Maximum_Nesting_Depth)
         & ",");
      Put_Line
        (Into,
         "      Maximum_Container_Items => "
         & Image (Limits.Maximum_Container_Items)
         & ",");
      Put_Line
        (Into,
         "      Maximum_Text_Length     => "
         & Image (Limits.Maximum_Text_Length)
         & ",");
      Put_Line
        (Into,
         "      Maximum_Byte_Length     => "
         & Image (Limits.Maximum_Byte_Length)
         & ",");
      Put_Line
        (Into,
         "      Maximum_Logical_Events  => "
         & Image (Limits.Maximum_Logical_Events)
         & ");");
      Put_Line (Into);

      Put_Line (Into, "   procedure Serialize_Value");
      Put_Line (Into, "     (Item  : " & Ada_Type & ";");
      Put_Line
        (Into,
         "      Into  : in out Flyology_Serde.Serialization.Serializer'Class;");
      Put_Line
        (Into, "      Error : in out Flyology_Serde.Errors.Error_Info) is");
      Put_Line (Into, "   begin");
      Put_Line
        (Into,
         "      Into.Begin_Record ("
         & Ada_Literal (Logical_Type_Name (Value))
         & ", "
         & Image (Field_Count (Value))
         & ", Error);");
      for Field in 1 .. Field_Count (Value) loop
         Put_Line
           (Into,
            "      Into.Put_Field ("
            & Ada_Literal (Field_Presentation_Name (Value, Field))
            & ", Error);");
         Serialize_Field (Field);
      end loop;
      Put_Line (Into, "      Into.End_Record (Error);");
      Put_Line (Into, "   end Serialize_Value;");
      Put_Line (Into);

      Put_Line (Into, "   procedure Begin_Candidate");
      Put_Line
        (Into,
         "     (Target : in out Builder; Error : in out Flyology_Serde.Errors.Error_Info) is");
      Put_Line (Into, "   begin");
      Put_Line (Into, "      if Target.Active then");
      Put_Line
        (Into,
         "         Flyology_Serde.Errors.Fail (Error, Flyology_Serde.Errors.Invalid_State);");
      Put_Line (Into, "      elsif not Target.Initialized then");
      Put_Line
        (Into,
         "         Flyology_Serde.Errors.Fail (Error, Flyology_Serde.Errors.Invalid_State);");
      Put_Line (Into, "      else");
      Put_Line (Into, "         Target.Candidate := Target.Published;");
      Put_Line (Into, "         Target.Active := True;");
      Put_Line (Into, "         Target.Root_Started := True;");
      Put_Line (Into, "      end if;");
      Put_Line (Into, "   end Begin_Candidate;");
      Put_Line (Into);

      Put_Line (Into, "   procedure Deserialize_Value");
      Put_Line
        (Into,
         "     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;");
      Put_Line (Into, "      Target : in out Builder;");
      Put_Line (Into, "      Policy : Flyology_Serde.Policies.Decode_Policy;");
      Put_Line
        (Into, "      Error  : in out Flyology_Serde.Errors.Error_Info)");
      Put_Line (Into, "   is");
      Put_Line
        (Into,
         "      Length    : Flyology_Serde.Data_Model.Length_Information;");
      Put_Line (Into, "      Available : Boolean := False;");
      Put_Line
        (Into,
         "      Name      : String (1 .. "
         & Image (Limits.Maximum_Text_Length)
         & ");");
      Put_Line (Into, "      Name_Last : Natural := 0;");
      Put_Line
        (Into,
         "      Seen      : array (Positive range 1 .. "
         & Image (Field_Count (Value))
         & ") of Boolean := [others => False];");
      Put_Line (Into, "   begin");
      Put_Line
        (Into,
         "      From.Begin_Record ("
         & Ada_Literal (Logical_Type_Name (Value))
         & ", Length, Error);");
      Put_Line
        (Into, "      while Error.Code = Flyology_Serde.Errors.No_Error loop");
      Put_Line
        (Into,
         "         From.Next_Field (Name, Name_Last, Available, Error);");
      Put_Line
        (Into,
         "         exit when Error.Code /= Flyology_Serde.Errors.No_Error or else not Available;");
      Put_Line
        (Into,
         "         Flyology_Serde.Errors.Push_Field (Error, Name (1 .. Name_Last));");
      for Field in 1 .. Field_Count (Value) loop
         Put_Line
           (Into,
            "         "
            & (if Field = 1 then "if" else "elsif")
            & " Name (1 .. Name_Last) = "
            & Ada_Literal (Field_Presentation_Name (Value, Field))
            & " then");
         Put_Line (Into, "            if Seen (" & Image (Field) & ") then");
         Put_Line
           (Into,
            "               Flyology_Serde.Errors.Fail "
            & "(Error, Flyology_Serde.Errors.Duplicate_Field);");
         Put_Line (Into, "            else");
         Put_Line
           (Into, "               Seen (" & Image (Field) & ") := True;");
         Deserialize_Field (Field);
         Put_Line (Into, "            end if;");
      end loop;
      Put_Line (Into, "         else");
      Put_Line
        (Into,
         "            Flyology_Serde.Errors.Fail (Error, Flyology_Serde.Errors.Unknown_Field);");
      Put_Line (Into, "         end if;");
      Put_Line
        (Into,
         "         exit when Error.Code /= Flyology_Serde.Errors.No_Error;");
      Put_Line (Into, "         Flyology_Serde.Errors.Pop (Error);");
      Put_Line (Into, "      end loop;");
      Put_Line
        (Into, "      if Error.Code = Flyology_Serde.Errors.No_Error then");
      Put_Line (Into, "         From.End_Record (Error);");
      Put_Line (Into, "      end if;");
      for Field in 1 .. Field_Count (Value) loop
         Put_Line
           (Into,
            "      if Error.Code = Flyology_Serde.Errors.No_Error and then not Seen ("
            & Image (Field)
            & ") then");
         Put_Line
           (Into,
            "         Flyology_Serde.Errors.Push_Field (Error, "
            & Ada_Literal (Field_Presentation_Name (Value, Field))
            & ");");
         Put_Line
           (Into,
            "         Flyology_Serde.Errors.Fail (Error, Flyology_Serde.Errors.Missing_Field);");
         Put_Line (Into, "      end if;");
      end loop;
      Put_Line (Into, "   end Deserialize_Value;");
      Put_Line (Into);

      Put_Line (Into, "   procedure Commit_Candidate");
      Put_Line
        (Into,
         "     (Target : in out Builder; Error : in out Flyology_Serde.Errors.Error_Info) is");
      Put_Line (Into, "   begin");
      Put_Line
        (Into,
         "      if not Target.Active or else not Target.Root_Started then");
      Put_Line
        (Into,
         "         Flyology_Serde.Errors.Fail (Error, Flyology_Serde.Errors.Invalid_State);");
      Put_Line (Into, "      else");
      Put_Line (Into, "         Target.Published := Target.Candidate;");
      Put_Line (Into, "         Target.Initialized := True;");
      Put_Line (Into, "         Target.Active := False;");
      Put_Line (Into, "         Target.Root_Started := False;");
      Put_Line (Into, "      end if;");
      Put_Line (Into, "   end Commit_Candidate;");
      Put_Line (Into);
      Put_Line
        (Into, "   procedure Rollback_Candidate (Target : in out Builder) is");
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

      Put_Line
        (Into,
         "   package Serialization_Root is new Flyology_Serde.Serialization_Adapters");
      Put_Line (Into, "     (Source_Type     => " & Ada_Type & ",");
      Put_Line (Into, "      Limits          => Serialization_Limits,");
      Put_Line (Into, "      Serialize_Value => Serialize_Value);");
      Put_Line (Into);
      Put_Line
        (Into,
         "   package Deserialization_Root is new Flyology_Serde.Deserialization_Adapters");
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
      Put_Line
        (Into, "      Error  : in out Flyology_Serde.Errors.Error_Info) is");
      Put_Line (Into, "   begin");
      Put_Line
        (Into, "      if Error.Code /= Flyology_Serde.Errors.No_Error then");
      Put_Line (Into, "         return;");
      Put_Line (Into, "      elsif Target.Active then");
      Put_Line
        (Into,
         "         Flyology_Serde.Errors.Fail (Error, Flyology_Serde.Errors.Invalid_State);");
      Put_Line (Into, "      else");
      Put_Line (Into, "         Target.Published := Value;");
      Put_Line (Into, "         Target.Candidate := Value;");
      Put_Line (Into, "         Target.Initialized := True;");
      Put_Line (Into, "         Target.Root_Started := False;");
      Put_Line (Into, "      end if;");
      Put_Line (Into, "   end Initialize;");
      Put_Line (Into);
      Put_Line
        (Into, "   function Has_Value (Target : Builder) return Boolean");
      Put_Line
        (Into, "   is (Target.Initialized and then not Target.Active);");
      Put_Line (Into);
      Put_Line
        (Into, "   function Value (Target : Builder) return " & Ada_Type);
      Put_Line (Into, "   is (Target.Published);");
      Put_Line (Into);
      Put_Line (Into, "   procedure Serialize");
      Put_Line (Into, "     (Item  : " & Ada_Type & ";");
      Put_Line
        (Into,
         "      Into  : in out Flyology_Serde.Serialization.Serializer'Class;");
      Put_Line
        (Into, "      Error : in out Flyology_Serde.Errors.Error_Info) is");
      Put_Line (Into, "   begin");
      Put_Line
        (Into, "      Serialization_Root.Serialize (Item, Into, Error);");
      Put_Line (Into, "   end Serialize;");
      Put_Line (Into);
      Put_Line (Into, "   procedure Deserialize");
      Put_Line
        (Into,
         "     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;");
      Put_Line (Into, "      Target : in out Builder;");
      Put_Line
        (Into, "      Error  : in out Flyology_Serde.Errors.Error_Info) is");
      Put_Line (Into, "   begin");
      Put_Line
        (Into,
         "      Deserialization_Root.Deserialize (From, Target, Error);");
      Put_Line (Into, "   end Deserialize;");
      Put_Line (Into, "end " & Unit_Name & ";");
   end Emit_Graph_Body;

   procedure Emit_Body (Value : Model; Into : in out Output_Sink) is
      Unit_Name : constant String := Output_Unit (Value);
      Ada_Type  : constant String := Record_Ada_Type (Value);
      Limits    : constant Runtime_Limit_Set := Runtime_Limits (Value);
   begin
      if Has_Type_Graph (Value) then
         Emit_Graph_Body (Value, Into);
         return;
      end if;
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
               "   package "
               & Adapter_Name (Index)
               & " is new Flyology_Serde.Adapters."
               & (if Field_Scalar_Kind (Value, Index) = Signed_64_Scalar
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
        (Into,
         "   Serialization_Limits : constant Flyology_Serde.Serialization.Serialization_Limits :=");
      Put_Line
        (Into,
         "     (Maximum_Nesting_Depth   => "
         & Image (Limits.Maximum_Nesting_Depth)
         & ",");
      Put_Line
        (Into,
         "      Maximum_Container_Items => "
         & Image (Limits.Maximum_Container_Items)
         & ",");
      Put_Line
        (Into,
         "      Maximum_Text_Length     => "
         & Image (Limits.Maximum_Text_Length)
         & ",");
      Put_Line
        (Into,
         "      Maximum_Byte_Length     => "
         & Image (Limits.Maximum_Byte_Length)
         & ",");
      Put_Line
        (Into,
         "      Maximum_Logical_Events  => "
         & Image (Limits.Maximum_Logical_Events)
         & ");");
      Put_Line (Into);
      Put_Line (Into, "   procedure Serialize_Value");
      Put_Line (Into, "     (Item  : " & Ada_Type & ";");
      Put_Line
        (Into,
         "      Into  : in out Flyology_Serde.Serialization.Serializer'Class;");
      Put_Line
        (Into, "      Error : in out Flyology_Serde.Errors.Error_Info) is");
      Put_Line (Into, "   begin");
      Put_Line
        (Into,
         "      Into.Begin_Record ("
         & Ada_Literal (Logical_Type_Name (Value))
         & ", "
         & Image (Field_Count (Value))
         & ", Error);");
      for Index in 1 .. Field_Count (Value) loop
         Put_Line
           (Into,
            "      Into.Put_Field ("
            & Ada_Literal (Field_Presentation_Name (Value, Index))
            & ", Error);");
         if Field_Scalar_Kind (Value, Index) = Boolean_Scalar then
            Put_Line
              (Into,
               "      Into.Put_Boolean (Item."
               & Field_Ada_Component (Value, Index)
               & ", Error);");
         else
            Put_Line
              (Into,
               "      "
               & Adapter_Name (Index)
               & ".Serialize_Value (Item."
               & Field_Ada_Component (Value, Index)
               & ", Into, Error);");
         end if;
      end loop;
      Put_Line (Into, "      Into.End_Record (Error);");
      Put_Line (Into, "   end Serialize_Value;");
      Put_Line (Into);
      Put_Line (Into, "   procedure Begin_Candidate");
      Put_Line
        (Into,
         "     (Target : in out Builder; Error : in out Flyology_Serde.Errors.Error_Info) is");
      Put_Line (Into, "   begin");
      Put_Line (Into, "      if Target.Active then");
      Put_Line
        (Into,
         "         Flyology_Serde.Errors.Fail (Error, Flyology_Serde.Errors.Invalid_State);");
      Put_Line (Into, "      elsif not Target.Initialized then");
      Put_Line
        (Into,
         "         Flyology_Serde.Errors.Fail (Error, Flyology_Serde.Errors.Invalid_State);");
      Put_Line (Into, "      else");
      Put_Line (Into, "         Target.Candidate := Target.Published;");
      Put_Line (Into, "         Target.Active := True;");
      Put_Line (Into, "         Target.Root_Started := True;");
      Put_Line (Into, "      end if;");
      Put_Line (Into, "   end Begin_Candidate;");
      Put_Line (Into);
      Put_Line (Into, "   procedure Deserialize_Value");
      Put_Line
        (Into,
         "     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;");
      Put_Line (Into, "      Target : in out Builder;");
      Put_Line (Into, "      Policy : Flyology_Serde.Policies.Decode_Policy;");
      Put_Line
        (Into, "      Error  : in out Flyology_Serde.Errors.Error_Info)");
      Put_Line (Into, "   is");
      Put_Line (Into, "      pragma Unreferenced (Policy);");
      Put_Line
        (Into,
         "      Length    : Flyology_Serde.Data_Model.Length_Information;");
      Put_Line (Into, "      Available : Boolean := False;");
      Put_Line (Into, "      Name      : String (1 .. 64);");
      Put_Line (Into, "      Name_Last : Natural := 0;");
      Put_Line
        (Into,
         "      Seen      : array (Positive range 1 .. "
         & Image (Field_Count (Value))
         & ") of Boolean := [others => False];");
      Put_Line (Into, "   begin");
      Put_Line
        (Into,
         "      From.Begin_Record ("
         & Ada_Literal (Logical_Type_Name (Value))
         & ", Length, Error);");
      Put_Line
        (Into, "      while Error.Code = Flyology_Serde.Errors.No_Error loop");
      Put_Line
        (Into,
         "         From.Next_Field (Name, Name_Last, Available, Error);");
      Put_Line
        (Into,
         "         exit when Error.Code /= Flyology_Serde.Errors.No_Error or else not Available;");
      Put_Line
        (Into,
         "         Flyology_Serde.Errors.Push_Field (Error, Name (1 .. Name_Last));");
      for Index in 1 .. Field_Count (Value) loop
         Put_Line
           (Into,
            "         "
            & (if Index = 1 then "if" else "elsif")
            & " Name (1 .. Name_Last) = "
            & Ada_Literal (Field_Presentation_Name (Value, Index))
            & " then");
         Put_Line
           (Into, "               if Seen (" & Image (Index) & ") then");
         Put_Line
           (Into,
            "                  Flyology_Serde.Errors.Fail (Error, Flyology_Serde.Errors.Duplicate_Field);");
         Put_Line (Into, "               else");
         Put_Line
           (Into, "                  Seen (" & Image (Index) & ") := True;");
         if Field_Scalar_Kind (Value, Index) = Boolean_Scalar then
            Put_Line
              (Into,
               "                  From.Read_Boolean (Target.Candidate."
               & Field_Ada_Component (Value, Index)
               & ", Error);");
         else
            Put_Line
              (Into,
               "                  "
               & Adapter_Name (Index)
               & ".Deserialize_Candidate "
               & "(From, Target.Candidate."
               & Field_Ada_Component (Value, Index)
               & ", Error);");
         end if;
         Put_Line (Into, "               end if;");
      end loop;
      Put_Line (Into, "         else");
      Put_Line
        (Into,
         "            Flyology_Serde.Errors.Fail (Error, Flyology_Serde.Errors.Unknown_Field);");
      Put_Line (Into, "         end if;");
      Put_Line
        (Into,
         "         exit when Error.Code /= Flyology_Serde.Errors.No_Error;");
      Put_Line (Into, "         Flyology_Serde.Errors.Pop (Error);");
      Put_Line (Into, "      end loop;");
      Put_Line
        (Into, "      if Error.Code = Flyology_Serde.Errors.No_Error then");
      Put_Line (Into, "         From.End_Record (Error);");
      Put_Line (Into, "      end if;");
      for Index in 1 .. Field_Count (Value) loop
         Put_Line
           (Into,
            "      if Error.Code = Flyology_Serde.Errors.No_Error and then not Seen ("
            & Image (Index)
            & ") then");
         Put_Line
           (Into,
            "         Flyology_Serde.Errors.Push_Field (Error, "
            & Ada_Literal (Field_Presentation_Name (Value, Index))
            & ");");
         Put_Line
           (Into,
            "         Flyology_Serde.Errors.Fail (Error, Flyology_Serde.Errors.Missing_Field);");
         Put_Line (Into, "      end if;");
      end loop;
      Put_Line (Into, "   end Deserialize_Value;");
      Put_Line (Into);
      Put_Line (Into, "   procedure Commit_Candidate");
      Put_Line
        (Into,
         "     (Target : in out Builder; Error : in out Flyology_Serde.Errors.Error_Info) is");
      Put_Line (Into, "   begin");
      Put_Line
        (Into,
         "      if not Target.Active or else not Target.Root_Started then");
      Put_Line
        (Into,
         "         Flyology_Serde.Errors.Fail (Error, Flyology_Serde.Errors.Invalid_State);");
      Put_Line (Into, "      else");
      Put_Line (Into, "         Target.Published := Target.Candidate;");
      Put_Line (Into, "         Target.Initialized := True;");
      Put_Line (Into, "         Target.Active := False;");
      Put_Line (Into, "         Target.Root_Started := False;");
      Put_Line (Into, "      end if;");
      Put_Line (Into, "   end Commit_Candidate;");
      Put_Line (Into);
      Put_Line
        (Into, "   procedure Rollback_Candidate (Target : in out Builder) is");
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
      Put_Line
        (Into,
         "   package Serialization_Root is new Flyology_Serde.Serialization_Adapters");
      Put_Line (Into, "     (Source_Type      => " & Ada_Type & ",");
      Put_Line (Into, "      Limits           => Serialization_Limits,");
      Put_Line (Into, "      Serialize_Value => Serialize_Value);");
      Put_Line (Into);
      Put_Line
        (Into,
         "   package Deserialization_Root is new Flyology_Serde.Deserialization_Adapters");
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
      Put_Line
        (Into, "      Error  : in out Flyology_Serde.Errors.Error_Info) is");
      Put_Line (Into, "   begin");
      Put_Line
        (Into, "      if Error.Code /= Flyology_Serde.Errors.No_Error then");
      Put_Line (Into, "         return;");
      Put_Line (Into, "      elsif Target.Active then");
      Put_Line
        (Into,
         "         Flyology_Serde.Errors.Fail (Error, Flyology_Serde.Errors.Invalid_State);");
      Put_Line (Into, "      else");
      Put_Line (Into, "         Target.Published := Value;");
      Put_Line (Into, "         Target.Candidate := Value;");
      Put_Line (Into, "         Target.Initialized := True;");
      Put_Line (Into, "         Target.Root_Started := False;");
      Put_Line (Into, "      end if;");
      Put_Line (Into, "   end Initialize;");
      Put_Line (Into);
      Put_Line
        (Into, "   function Has_Value (Target : Builder) return Boolean");
      Put_Line
        (Into, "   is (Target.Initialized and then not Target.Active);");
      Put_Line (Into);
      Put_Line
        (Into, "   function Value (Target : Builder) return " & Ada_Type);
      Put_Line (Into, "   is (Target.Published);");
      Put_Line (Into);
      Put_Line (Into, "   procedure Serialize");
      Put_Line (Into, "     (Item  : " & Ada_Type & ";");
      Put_Line
        (Into,
         "      Into  : in out Flyology_Serde.Serialization.Serializer'Class;");
      Put_Line
        (Into, "      Error : in out Flyology_Serde.Errors.Error_Info) is");
      Put_Line (Into, "   begin");
      Put_Line
        (Into, "      Serialization_Root.Serialize (Item, Into, Error);");
      Put_Line (Into, "   end Serialize;");
      Put_Line (Into);
      Put_Line (Into, "   procedure Deserialize");
      Put_Line
        (Into,
         "     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;");
      Put_Line (Into, "      Target : in out Builder;");
      Put_Line
        (Into, "      Error  : in out Flyology_Serde.Errors.Error_Info) is");
      Put_Line (Into, "   begin");
      Put_Line
        (Into,
         "      Deserialization_Root.Deserialize (From, Target, Error);");
      Put_Line (Into, "   end Deserialize;");
      Put_Line (Into, "end " & Unit_Name & ";");
   end Emit_Body;

   procedure Preflight_Graph
     (Value : Model; Require_Published : Boolean := True)
   is
      Spec_Measure : Output_Sink (True, null, null);
      Body_Measure : Output_Sink (True, null, null);
   begin
      Validate (Value, Require_Published);
      Emit_Spec (Value, Spec_Measure);
      Emit_Body (Value, Body_Measure);
      if not Spec_Measure.Last_Was_LF or else not Body_Measure.Last_Was_LF then
         raise Invalid_Render;
      end if;
   end Preflight_Graph;

   function Preflight_Unpublished (Value : Model) return Boolean is
      Members         : Natural := 0;
      Text_Bytes      : Natural := 0;
      Recomputed_Work : Natural := 0;
   begin
      if Has_Type_Graph (Value) and then not Is_Valid (Value) then
         Graph_Size (Value, Members, Text_Bytes, Recomputed_Work);
         if Recomputed_Work /= Graph_Work_Units (Value) then
            raise Unsupported_Model;
         end if;
         Preflight_Graph (Value, Require_Published => False);
      else
         raise Unsupported_Model;
      end if;
      return True;
   exception
      when Unsupported_Model =>
         return False;
   end Preflight_Unpublished;

   function File_Stem (Unit_Name : String) return String is
      Result : String (Unit_Name'Range);
   begin
      for Index in Unit_Name'Range loop
         Result (Index) :=
           (if Unit_Name (Index) = '.'
            then '-'
            else Ada.Characters.Handling.To_Lower (Unit_Name (Index)));
      end loop;
      return Result;
   end File_Stem;

   procedure Render_Payload
     (Value      : Model;
      Budget     : aliased in out Operation_Budget;
      Into       : in out Rendered_Artifacts;
      Diagnostic : out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
      Candidate  : Artifact_Data_Access := null;
      Accepted   : Boolean;
      Previous   : Artifact_Data_Access;
      Model_Work : Natural := 0;
   begin
      Clear (Diagnostic);
      if Is_Poisoned (Budget) then
         Set (Diagnostic, Resource_Exhausted);
         return;
      end if;
      if Has_Type_Graph (Value) then
         Model_Work := Graph_Work_Units (Value);
      else
         Validate (Value);
         Model_Work := With_Unit_Count (Value) + Field_Count (Value);
      end if;
      Charge_Work (Budget, Model_Work, Accepted);
      if not Accepted then
         raise Exhausted;
      end if;
      if Has_Type_Graph (Value) then
         declare
            Members         : Natural := 0;
            Text_Bytes      : Natural := 0;
            Recomputed_Work : Natural := 0;
         begin
            Graph_Size (Value, Members, Text_Bytes, Recomputed_Work);
            if Recomputed_Work /= Model_Work then
               raise Unsupported_Model;
            end if;
            Preflight_Graph (Value);
         end;
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
          (Specification_Name    =>
             To_Unbounded_String (File_Stem (Output_Unit (Value)) & ".ads"),
           Specification_Payload => Null_Unbounded_String,
           Body_Name             =>
             To_Unbounded_String (File_Stem (Output_Unit (Value)) & ".adb"),
           Body_Payload          => Null_Unbounded_String);
      declare
         Spec_Output :
           Output_Sink
             (False, Budget'Access, Candidate.Specification_Payload'Access);
         Body_Output :
           Output_Sink (False, Budget'Access, Candidate.Body_Payload'Access);
      begin
         Emit_Spec (Value, Spec_Output);
         Emit_Body (Value, Body_Output);
         if not Spec_Output.Last_Was_LF
           or else not Body_Output.Last_Was_LF
           or else Length (Candidate.Specification_Payload)
                   /= Spec_Output.Bytes
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

   function Is_Valid (Value : Rendered_Artifacts) return Boolean
   is (Value.Data /= null);

   function Artifact_Count (Value : Rendered_Artifacts) return Natural
   is (if Value.Data = null then 0 else 2);

   function File_Name
     (Value : Rendered_Artifacts; Kind : Artifact_Kind) return String
   is (case Kind is
         when Specification => To_String (Value.Data.Specification_Name),
         when Package_Body  => To_String (Value.Data.Body_Name));

   function Payload_Length
     (Value : Rendered_Artifacts; Kind : Artifact_Kind) return Natural
   is (case Kind is
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
      Cursor        : Positive := Into'First;
   begin
      Copied := Into'Length >= Source_Length;
      if not Copied then
         return;
      end if;
      for Index in 1 .. Source_Length loop
         Into (Cursor) :=
           (case Kind is
              when Specification =>
                Element (Value.Data.Specification_Payload, Index),
              when Package_Body  => Element (Value.Data.Body_Payload, Index));
         if Index < Source_Length then
            Cursor := Positive'Succ (Cursor);
         end if;
      end loop;
      Written := Source_Length;
   end Copy_Payload;

   overriding
   procedure Finalize (Value : in out Rendered_Artifacts) is
   begin
      Discard (Value.Data);
   exception
      when others =>
         null;
   end Finalize;
end Flyology_Serde_Generator.Rendering;
