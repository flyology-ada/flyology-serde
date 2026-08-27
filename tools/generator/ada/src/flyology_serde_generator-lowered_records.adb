with Ada.Unchecked_Deallocation;

package body Flyology_Serde_Generator.Lowered_Records is
   procedure Free is new
     Ada.Unchecked_Deallocation
       (Object => Graph_Data,
        Name   => Graph_Data_Access);

   function Text (Value : Bounded_Text) return String
   is (if Value.Length = 0 then "" else Value.Data (1 .. Value.Length));

   procedure Set_Text (Target : out Bounded_Text; Value : String) is
   begin
      Target := (Length => 0, Data => [others => ASCII.NUL]);
      if Value'Length > Text_Capacity then
         raise Constraint_Error
           with "lowered-record text exceeds its intrinsic capacity";
      end if;
      Target.Length := Value'Length;
      if Value'Length > 0 then
         Target.Data (1 .. Value'Length) := Value;
      end if;
   end Set_Text;

   function Is_Valid (Value : Model) return Boolean
   is (if Value.Graph = null then Value.Valid else Value.Graph.Valid);

   function Output_Unit (Value : Model) return String
   is (if Value.Graph = null
       then Text (Value.Unit_Name)
       else Text (Value.Graph.Unit_Name));

   function With_Unit_Count (Value : Model) return Natural
   is (if Value.Graph = null
       then Value.With_Count
       else Value.Graph.With_Count);

   function With_Unit (Value : Model; Index : Positive) return String
   is (if Value.Graph = null
       then Text (Value.With_Units (Index))
       else Text (Value.Graph.With_Units (Index)));

   function Record_Ada_Type (Value : Model) return String
   is (if Value.Graph = null
       then Text (Value.Ada_Type)
       else Text (Value.Graph.Types (Value.Graph.Root).Ada_Type));

   function Logical_Type_Name (Value : Model) return String
   is (if Value.Graph = null
       then Text (Value.Logical_Name)
       else Text (Value.Graph.Types (Value.Graph.Root).Logical_Name));

   function Field_Count (Value : Model) return Natural
   is (if Value.Graph = null
       then Value.Fields_Count
       else Value.Graph.Fields_Count);

   function Field_Ada_Component (Value : Model; Index : Positive) return String
   is (if Value.Graph = null
       then Text (Value.Fields (Index).Ada_Component)
       else Text (Value.Graph.Fields (Index).Ada_Component));

   function Field_Ada_Type (Value : Model; Index : Positive) return String
   is (if Value.Graph = null
       then Text (Value.Fields (Index).Ada_Type)
       else
         Text
           (Value.Graph.Types (Value.Graph.Fields (Index).Type_Node)
              .Ada_Type));

   function Field_Presentation_Name
     (Value : Model; Index : Positive) return String
   is (if Value.Graph = null
       then Text (Value.Fields (Index).Presentation_Name)
       else Text (Value.Graph.Fields (Index).Presentation_Name));

   function Field_Scalar_Kind
     (Value : Model; Index : Positive) return Scalar_Kind
   is (if Value.Graph = null
       then Value.Fields (Index).Kind
       else
         (case Value.Graph.Types (Value.Graph.Fields (Index).Type_Node).Kind is
            when Boolean_Node     => Boolean_Scalar,
            when Signed_64_Node   => Signed_64_Scalar,
            when Unsigned_64_Node => Unsigned_64_Scalar,
            when others           => raise Constraint_Error));

   function Runtime_Limits (Value : Model) return Runtime_Limit_Set
   is (if Value.Graph = null
       then Value.Serialization_Limits
       else Value.Graph.Serialization_Limits);

   function Has_Type_Graph (Value : Model) return Boolean
   is (Value.Graph /= null);

   function Type_Node_Count (Value : Model) return Natural
   is (Value.Graph.Types_Count);

   function Node_Kind (Value : Model; Index : Positive) return Type_Node_Kind
   is (Value.Graph.Types (Index).Kind);

   function Node_Ada_Type (Value : Model; Index : Positive) return String
   is (Text (Value.Graph.Types (Index).Ada_Type));

   function Node_Logical_Name (Value : Model; Index : Positive) return String
   is (Text (Value.Graph.Types (Index).Logical_Name));

   function Node_Defining_With (Value : Model; Index : Positive) return Natural
   is (Value.Graph.Types (Index).Defining_With);

   function Literal_Index
     (Value : Model; Node : Positive; Position : Positive) return Positive
   is (Value.Graph.Types (Node).Literal_First + Position - 1);

   function Enumeration_Literal_Count
     (Value : Model; Node : Positive) return Natural
   is (Value.Graph.Types (Node).Literal_Count);

   function Enumeration_Literal_Ada_Name
     (Value : Model; Node : Positive; Position : Positive) return String
   is (Text
         (Value.Graph.Literals (Literal_Index (Value, Node, Position))
            .Ada_Name));

   function Enumeration_Literal_Primary_Name
     (Value : Model; Node : Positive; Position : Positive) return String
   is (Text
         (Value.Graph.Literals (Literal_Index (Value, Node, Position))
            .Primary_Name));

   function Enumeration_Literal_Alias_Count
     (Value : Model; Node : Positive; Position : Positive) return Natural
   is (Value.Graph.Literals (Literal_Index (Value, Node, Position))
         .Alias_Count);

   function Enumeration_Literal_Alias_Name
     (Value : Model; Node : Positive; Position : Positive; Alias : Positive)
      return String
   is
      Literal : constant Graph_Literal_Data :=
        Value.Graph.Literals (Literal_Index (Value, Node, Position));
   begin
      return Text (Value.Graph.Aliases (Literal.Alias_First + Alias - 1));
   end Enumeration_Literal_Alias_Name;

   function Array_Index_Node (Value : Model; Node : Positive) return Positive
   is (Value.Graph.Types (Node).Index_Node);

   function Array_Element_Node (Value : Model; Node : Positive) return Positive
   is (Value.Graph.Types (Node).Element_Node);

   function Field_Type_Node (Value : Model; Index : Positive) return Positive
   is (Value.Graph.Fields (Index).Type_Node);

   function Root_Node (Value : Model) return Positive
   is (Value.Graph.Root);

   function Graph_Work_Units (Value : Model) return Positive
   is (Value.Graph.Work_Units);

   function Graph_Structure_Is_Valid (Value : Graph_Data) return Boolean is
      Next_Field   : Natural := 1;
      Next_Literal : Natural := 1;
      Next_Alias   : Natural := 1;
      Records      : Natural := 0;
   begin
      if Value.Valid
        or else Value.Types_Count = 0
        or else Value.Fields_Count = 0
        or else Value.With_Count = 0
        or else Value.Root not in Value.Types'Range
        or else Value.Work_Units = 0
      then
         return False;
      end if;

      for Node in Value.Types'Range loop
         declare
            Item : Graph_Type_Data renames Value.Types (Node);
         begin
            if Item.Defining_With > Value.With_Count then
               return False;
            end if;
            case Item.Kind is
               when Enumeration_Node                                 =>
                  if Item.Literal_Count = 0
                    or else Item.Literal_First /= Next_Literal
                    or else Item.Literal_Count
                            > Value.Literals_Count - Next_Literal + 1
                    or else Item.Index_Node /= 0
                    or else Item.Element_Node /= 0
                    or else Item.Field_First /= 0
                    or else Item.Field_Count /= 0
                  then
                     return False;
                  end if;
                  Next_Literal := Next_Literal + Item.Literal_Count;

               when Fixed_Array_Node                                 =>
                  if Item.Literal_First /= 0
                    or else Item.Literal_Count /= 0
                    or else Item.Index_Node not in Value.Types'Range
                    or else Item.Element_Node not in Value.Types'Range
                    or else Item.Field_First /= 0
                    or else Item.Field_Count /= 0
                  then
                     return False;
                  end if;

               when Record_Node                                      =>
                  Records := Records + 1;
                  if Item.Literal_First /= 0
                    or else Item.Literal_Count /= 0
                    or else Item.Index_Node /= 0
                    or else Item.Element_Node /= 0
                    or else Item.Field_Count = 0
                    or else Item.Field_First /= Next_Field
                    or else Item.Field_Count
                            > Value.Fields_Count - Next_Field + 1
                  then
                     return False;
                  end if;
                  Next_Field := Next_Field + Item.Field_Count;

               when Boolean_Node | Signed_64_Node | Unsigned_64_Node =>
                  if Item.Literal_First /= 0
                    or else Item.Literal_Count /= 0
                    or else Item.Index_Node /= 0
                    or else Item.Element_Node /= 0
                    or else Item.Field_First /= 0
                    or else Item.Field_Count /= 0
                  then
                     return False;
                  end if;
            end case;
         end;
      end loop;

      if Records /= 1
        or else Value.Types (Value.Root).Kind /= Record_Node
        or else Next_Field /= Value.Fields_Count + 1
        or else Next_Literal /= Value.Literals_Count + 1
      then
         return False;
      end if;

      for Literal in Value.Literals'Range loop
         if Value.Literals (Literal).Alias_Count = 0 then
            if Value.Literals (Literal).Alias_First /= 0 then
               return False;
            end if;
         elsif Value.Literals (Literal).Alias_First /= Next_Alias
           or else Value.Literals (Literal).Alias_Count
                   > Value.Aliases_Count - Next_Alias + 1
         then
            return False;
         else
            Next_Alias := Next_Alias + Value.Literals (Literal).Alias_Count;
         end if;
      end loop;

      if Next_Alias /= Value.Aliases_Count + 1 then
         return False;
      end if;
      for Field of Value.Fields loop
         if Field.Type_Node not in Value.Types'Range then
            return False;
         end if;
      end loop;
      return True;
   exception
      when Constraint_Error =>
         return False;
   end Graph_Structure_Is_Valid;

   overriding
   procedure Finalize (Value : in out Model) is
   begin
      if Value.Graph /= null then
         Free (Value.Graph);
      end if;
      Value.Valid := False;
   exception
      when others =>
         Value.Graph := null;
         Value.Valid := False;
   end Finalize;
end Flyology_Serde_Generator.Lowered_Records;
