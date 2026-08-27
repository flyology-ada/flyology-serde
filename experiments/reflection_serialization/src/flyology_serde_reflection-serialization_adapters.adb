with Ada.Strings.Unbounded;
with Flyology.Reflection.Predefined_Types;
with Flyology_Serde.Data_Model;
with Flyology_Serde.Serialization_Adapters;
with Flyology_Serde.UTF_8;
with Interfaces;

package body Flyology_Serde_Reflection.Serialization_Adapters is
   use Ada.Strings.Unbounded;
   use Flyology.Reflection.Value_Views;
   use type Flyology_Serde.Errors.Error_Code;
   use type Interfaces.Integer_64;

   procedure Serialize_Reflected
     (Item  : Source_Type;
      Into  : in out Flyology_Serde.Serialization.Serializer'Class;
      Error : in out Flyology_Serde.Errors.Error_Info);

   package Root_Adapter is new
     Flyology_Serde.Serialization_Adapters
       (Source_Type     => Source_Type,
        Limits          => Limits,
        Serialize_Value => Serialize_Reflected);

   procedure Serialize_Reflected
     (Item  : Source_Type;
      Into  : in out Flyology_Serde.Serialization.Serializer'Class;
      Error : in out Flyology_Serde.Errors.Error_Info)
   is
      Traversal_Stopped : exception;

      procedure Stop (Code : Flyology_Serde.Errors.Error_Code)
      with No_Return;

      procedure Check_Error;

      procedure Emit_View (View : Value_View'Class);

      procedure Stop (Code : Flyology_Serde.Errors.Error_Code) is
      begin
         Flyology_Serde.Errors.Fail (Error, Code);
         raise Traversal_Stopped;
      end Stop;

      procedure Check_Error is
      begin
         if Error.Code /= Flyology_Serde.Errors.No_Error then
            raise Traversal_Stopped;
         end if;
      end Check_Error;

      function Exact_Natural (Value : Cardinality) return Natural is
      begin
         if Value.Status /= Exact_Cardinality
           or else Value.Value > Count_Value (Natural'Last)
         then
            Stop (Flyology_Serde.Errors.Unsupported_Value);
         end if;
         return Natural (Value.Value);
      end Exact_Natural;

      function Is_Digit (Value : Character) return Boolean
      is (Value in '0' .. '9');

      function Valid_Unsigned_Grammar (Value : String) return Boolean is
      begin
         if Value'Length = 1 then
            return Value (Value'First) in '0' .. '9';
         elsif Value'Length = 0 or else Value (Value'First) not in '1' .. '9'
         then
            return False;
         end if;
         for Position in Value'First + 1 .. Value'Last loop
            if not Is_Digit (Value (Position)) then
               return False;
            end if;
         end loop;
         return True;
      end Valid_Unsigned_Grammar;

      function Within_Unsigned_Maximum (Value, Maximum : String) return Boolean
      is (Value'Length < Maximum'Length
          or else (Value'Length = Maximum'Length and then Value <= Maximum));

      procedure Put_Signed_Decimal (Value : String) is
         Positive_Maximum : constant String := "9223372036854775807";
         Negative_Maximum : constant String := "9223372036854775808";
         Negative         : constant Boolean :=
           Value'Length > 0 and then Value (Value'First) = '-';
      begin
         if Negative then
            if Value'Length <= 1
              or else not Valid_Unsigned_Grammar
                            (Value (Value'First + 1 .. Value'Last))
              or else Value (Value'First + 1) = '0'
            then
               Stop (Flyology_Serde.Errors.Application_Error);
            elsif not Within_Unsigned_Maximum
                        (Value (Value'First + 1 .. Value'Last),
                         Negative_Maximum)
            then
               Stop (Flyology_Serde.Errors.Unsupported_Value);
            end if;
         elsif not Valid_Unsigned_Grammar (Value) then
            Stop (Flyology_Serde.Errors.Application_Error);
         elsif not Within_Unsigned_Maximum (Value, Positive_Maximum) then
            Stop (Flyology_Serde.Errors.Unsupported_Value);
         end if;

         begin
            Into.Put_Signed (Interfaces.Integer_64'Value (Value), Error);
         exception
            when Constraint_Error =>
               Stop (Flyology_Serde.Errors.Application_Error);
         end;
         Check_Error;
      end Put_Signed_Decimal;

      procedure Put_Modular_Decimal (Value : String) is
         Maximum : constant String := "18446744073709551615";
      begin
         if not Valid_Unsigned_Grammar (Value) then
            Stop (Flyology_Serde.Errors.Application_Error);
         elsif not Within_Unsigned_Maximum (Value, Maximum) then
            Stop (Flyology_Serde.Errors.Unsupported_Value);
         end if;

         begin
            Into.Put_Unsigned (Interfaces.Unsigned_64'Value (Value), Error);
         exception
            when Constraint_Error =>
               Stop (Flyology_Serde.Errors.Application_Error);
         end;
         Check_Error;
      end Put_Modular_Decimal;

      procedure Emit_Array (View : Array_View'Class) is
         Count           : constant Natural :=
           Exact_Natural (Element_Count (View));
         Dimension_Count : Natural;

         type Bound_Reader is new Value_Consumer with record
            Calls : Natural := 0;
            Value : Interfaces.Integer_64 := 0;
         end record;

         overriding
         procedure Consume
           (Self : in out Bound_Reader; Bound : Value_View'Class);

         type Element_Reader is new Element_Consumer with record
            Calls : Natural := 0;
         end record;

         overriding
         procedure Visit_Element
           (Self : in out Element_Reader; Element : Value_View'Class);

         overriding
         procedure Consume
           (Self : in out Bound_Reader; Bound : Value_View'Class)
         is
            Text     : Unbounded_String;
            Negative : Boolean;
         begin
            if Self.Calls /= 0 then
               Stop (Flyology_Serde.Errors.Application_Error);
            end if;
            Validate_Terminal_Facet (Bound);
            if Bound in Variant_View'Class
              and then Bound not in Record_View'Class
            then
               Stop (Flyology_Serde.Errors.Application_Error);
            elsif not Same_Type
                        (Type_Of (Bound),
                         Flyology.Reflection.Predefined_Types.Integer_Type)
              or else Bound not in Signed_Integer_View'Class
            then
               Stop (Flyology_Serde.Errors.Unsupported_Value);
            end if;
            Self.Calls := Self.Calls + 1;
            Text :=
              To_Unbounded_String
                (Canonical_Decimal (Signed_Integer_View'Class (Bound)));
            Negative := Length (Text) > 0 and then Element (Text, 1) = '-';
            if Negative then
               if Length (Text) <= 1
                 or else not Valid_Unsigned_Grammar
                               (Slice (Text, 2, Length (Text)))
                 or else Element (Text, 2) = '0'
               then
                  Stop (Flyology_Serde.Errors.Application_Error);
               elsif not Within_Unsigned_Maximum
                           (Slice (Text, 2, Length (Text)),
                            "9223372036854775808")
               then
                  Stop (Flyology_Serde.Errors.Unsupported_Value);
               end if;
            elsif not Valid_Unsigned_Grammar (To_String (Text)) then
               Stop (Flyology_Serde.Errors.Application_Error);
            elsif not Within_Unsigned_Maximum
                        (To_String (Text), "9223372036854775807")
            then
               Stop (Flyology_Serde.Errors.Unsupported_Value);
            end if;
            begin
               Self.Value := Interfaces.Integer_64'Value (To_String (Text));
            exception
               when Constraint_Error =>
                  Stop (Flyology_Serde.Errors.Application_Error);
            end;
         end Consume;

         overriding
         procedure Visit_Element
           (Self : in out Element_Reader; Element : Value_View'Class) is
         begin
            if Self.Calls >= Count then
               Stop (Flyology_Serde.Errors.Application_Error);
            end if;
            Flyology_Serde.Errors.Push_Index (Error, Self.Calls);
            Check_Error;
            Emit_View (Element);
            Flyology_Serde.Errors.Pop (Error);
            Self.Calls := Self.Calls + 1;
         end Visit_Element;

         First, Last   : Bound_Reader;
         Elements      : Element_Reader;
         Expected_Last : Interfaces.Integer_64;
      begin
         Dimension_Count := Rank (View);
         if Dimension_Count /= 1 then
            Stop (Flyology_Serde.Errors.Unsupported_Value);
         end if;
         if Exact_Natural (Dimension_Length (View, 1)) /= Count then
            Stop (Flyology_Serde.Errors.Application_Error);
         end if;

         Observe_First_Index (View, 1, First);
         Observe_Last_Index (View, 1, Last);
         begin
            Expected_Last := Interfaces.Integer_64 (Count);
         exception
            when Constraint_Error =>
               Stop (Flyology_Serde.Errors.Unsupported_Value);
         end;
         if First.Calls /= 1 or else Last.Calls /= 1 then
            Stop (Flyology_Serde.Errors.Application_Error);
         elsif First.Value /= 1
           or else (if Count = 0
                    then Last.Value /= 0
                    else Last.Value /= Expected_Last)
         then
            Stop (Flyology_Serde.Errors.Unsupported_Value);
         end if;

         Into.Begin_Sequence
           (Flyology_Serde.Data_Model.Known_Length (Count), Error);
         Check_Error;
         Observe_Elements (View, Elements);
         if Elements.Calls /= Count then
            Stop (Flyology_Serde.Errors.Application_Error);
         end if;
         Into.End_Sequence (Error);
         Check_Error;
      end Emit_Array;

      procedure Emit_Record (View : Record_View'Class; Root : Value_View'Class)
      is
         Count      : constant Natural :=
           Exact_Natural (Active_Component_Count (View));
         Is_Variant : constant Boolean := Root in Variant_View'Class;

         type Alternative_Reader is new Variant_Consumer with record
            Calls : Natural := 0;
            Length : Natural range 0 .. Limits.Maximum_Text_Length := 0;
            Name   : String (1 .. Limits.Maximum_Text_Length) :=
              [others => ' '];
         end record;

         overriding
         procedure Visit_Selected_Alternative
           (Self         : in out Alternative_Reader;
            Variant_Part : Declaration_Reference;
            Alternative  : Declaration_Reference;
            Choice_Name  : String);

         type Component_Reader is new Component_Consumer with record
            Calls : Natural := 0;
         end record;

         overriding
         procedure Visit_Component
           (Self        : in out Component_Reader;
            Declaration : Declaration_Reference;
            Name        : String;
            Role        : Component_Role;
            Child       : Value_View'Class);

         overriding
         procedure Visit_Selected_Alternative
           (Self         : in out Alternative_Reader;
            Variant_Part : Declaration_Reference;
            Alternative  : Declaration_Reference;
            Choice_Name  : String)
         is
            pragma Unreferenced (Variant_Part, Alternative);
         begin
            if Self.Calls /= 0 then
               Stop (Flyology_Serde.Errors.Application_Error);
            elsif Choice_Name'Length = 0 then
               Stop (Flyology_Serde.Errors.Application_Error);
            elsif Choice_Name'Length > Limits.Maximum_Text_Length then
               Stop (Flyology_Serde.Errors.Capacity_Exceeded);
            elsif not Flyology_Serde.UTF_8.Is_Valid (Choice_Name) then
               Stop (Flyology_Serde.Errors.Invalid_Text);
            end if;
            Self.Name (1 .. Choice_Name'Length) := Choice_Name;
            Self.Length := Choice_Name'Length;
            Self.Calls := Self.Calls + 1;
         end Visit_Selected_Alternative;

         overriding
         procedure Visit_Component
           (Self        : in out Component_Reader;
            Declaration : Declaration_Reference;
            Name        : String;
            Role        : Component_Role;
            Child       : Value_View'Class)
         is
            pragma Unreferenced (Declaration, Role);
         begin
            if Self.Calls >= Count then
               Stop (Flyology_Serde.Errors.Application_Error);
            end if;
            Flyology_Serde.Errors.Push_Field (Error, Name);
            Check_Error;
            Into.Put_Field (Name, Error);
            Check_Error;
            Emit_View (Child);
            Flyology_Serde.Errors.Pop (Error);
            Self.Calls := Self.Calls + 1;
         end Visit_Component;

         Alternative : Alternative_Reader;
         Components  : Component_Reader;
         Type_Name   : constant String := Qualified_Name (Type_Of (Root));
      begin
         if Is_Variant then
            declare
               Variant : Variant_View'Class renames Variant_View'Class (Root);
            begin
               if Exact_Natural (Selected_Alternative_Count (Variant)) /= 1
               then
                  Stop (Flyology_Serde.Errors.Application_Error);
               end if;
               Observe_Selected_Alternatives (Variant, Alternative);
            end;
            if Alternative.Calls /= 1 then
               Stop (Flyology_Serde.Errors.Application_Error);
            end if;
            Flyology_Serde.Errors.Push_Alternative
              (Error, Alternative.Name (1 .. Alternative.Length));
            Check_Error;
            Into.Begin_Variant
              (Type_Name,
               Alternative.Name (1 .. Alternative.Length),
               Count,
               Error);
         else
            Into.Begin_Record (Type_Name, Count, Error);
         end if;
         Check_Error;

         Observe_Components (View, Components);
         if Components.Calls /= Count then
            Stop (Flyology_Serde.Errors.Application_Error);
         elsif Is_Variant then
            Into.End_Variant (Error);
         else
            Into.End_Record (Error);
         end if;
         Check_Error;
         if Is_Variant then
            Flyology_Serde.Errors.Pop (Error);
         end if;
      end Emit_Record;

      procedure Emit_View (View : Value_View'Class) is
      begin
         Validate_Terminal_Facet (View);
         if View in Variant_View'Class and then View not in Record_View'Class
         then
            Stop (Flyology_Serde.Errors.Application_Error);
         elsif View in Unsupported_View'Class then
            Stop (Flyology_Serde.Errors.Unsupported_Value);
         elsif View in Boolean_View'Class then
            Into.Put_Boolean
              (Boolean_Value (Boolean_View'Class (View)), Error);
            Check_Error;
         elsif View in Signed_Integer_View'Class then
            Put_Signed_Decimal
              (Canonical_Decimal (Signed_Integer_View'Class (View)));
         elsif View in Modular_Integer_View'Class then
            Put_Modular_Decimal
              (Canonical_Decimal (Modular_Integer_View'Class (View)));
         elsif View in Enumeration_View'Class then
            Into.Put_Enumeration
              (Qualified_Name (Type_Of (View)),
               Literal_Name (Enumeration_View'Class (View)),
               Error);
            Check_Error;
         elsif View in Array_View'Class then
            Emit_Array (Array_View'Class (View));
         elsif View in Record_View'Class then
            Emit_Record (Record_View'Class (View), View);
         elsif View in Variant_View'Class then
            Stop (Flyology_Serde.Errors.Application_Error);
         else
            Stop (Flyology_Serde.Errors.Unsupported_Value);
         end if;
      end Emit_View;

      type Root_Consumer is new Value_Consumer with record
         Calls : Natural := 0;
      end record;

      overriding
      procedure Consume (Self : in out Root_Consumer; View : Value_View'Class);

      overriding
      procedure Consume (Self : in out Root_Consumer; View : Value_View'Class)
      is
      begin
         if Self.Calls /= 0 then
            Stop (Flyology_Serde.Errors.Application_Error);
         end if;
         Self.Calls := Self.Calls + 1;
         Emit_View (View);
      end Consume;

      Root : Root_Consumer;
   begin
      Observe (Item, Root);
      if Root.Calls /= 1 then
         Stop (Flyology_Serde.Errors.Application_Error);
      end if;
   exception
      when Traversal_Stopped =>
         null;
      when Malformed_View | Traversal_Not_Available =>
         Flyology_Serde.Errors.Fail
           (Error, Flyology_Serde.Errors.Application_Error);
   end Serialize_Reflected;

   procedure Serialize
     (Item  : Source_Type;
      Into  : in out Flyology_Serde.Serialization.Serializer'Class;
      Error : in out Flyology_Serde.Errors.Error_Info) is
   begin
      Root_Adapter.Serialize (Item, Into, Error);
   end Serialize;
end Flyology_Serde_Reflection.Serialization_Adapters;
