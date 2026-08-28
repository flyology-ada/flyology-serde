with Flyology_Serde.UTF_8;

package body Flyology_Serde.Adapters.Record_Serializers is
   use type Errors.Error_Code;

   subtype Field_Index is Positive range 1 .. Maximum_Fields;

   type Field_Table is array (Field_Index) of Field_Ordinal;

   type Bounded_Name is record
      Length : Natural range 0 .. Maximum_Field_Name_Length := 0;
      Data   : String (1 .. Maximum_Field_Name_Length) := [others => ' '];
   end record;

   type Name_Table is array (Field_Index) of Bounded_Name;

   procedure Store
     (Into : out Bounded_Name;
      From : String) is
   begin
      Into := (others => <>);
      Into.Length := From'Length;
      for Offset in 0 .. From'Length - 1 loop
         Into.Data (Into.Data'First + Offset) := From (From'First + Offset);
      end loop;
   end Store;

   function Equals (Left : Bounded_Name; Right : String) return Boolean is
   begin
      if Left.Length /= Right'Length then
         return False;
      elsif Right'Length = 0 then
         return True;
      end if;
      for Offset in 0 .. Right'Length - 1 loop
         if Left.Data (Left.Data'First + Offset) /= Right (Right'First + Offset) then
            return False;
         end if;
      end loop;
      return True;
   end Equals;

   function Equals (Left, Right : Bounded_Name) return Boolean is
   begin
      if Left.Length /= Right.Length then
         return False;
      elsif Left.Length = 0 then
         return True;
      end if;
      for Offset in 0 .. Left.Length - 1 loop
         if Left.Data (Left.Data'First + Offset) /= Right.Data (Right.Data'First + Offset) then
            return False;
         end if;
      end loop;
      return True;
   end Equals;

   function Text (Value : Bounded_Name) return String is
     (Value.Data (Value.Data'First .. Value.Data'First + Value.Length - 1));

   procedure Prepare_Metadata
     (Fields : out Field_Table;
      Names  : out Name_Table;
      Count  : out Natural;
      Error  : in out Errors.Error_Info) is
   begin
      Count := 0;
      if Error.Code /= Errors.No_Error then
         return;
      elsif Type_Name'Length = 0 or else Type_Name'Length > Maximum_Type_Name_Length then
         Errors.Fail (Error, Errors.Capacity_Exceeded);
         return;
      elsif not Flyology_Serde.UTF_8.Is_Valid (Type_Name) then
         Errors.Fail (Error, Errors.Invalid_Text);
         return;
      end if;

      Fields := [others => Field_Ordinal'First];
      Names := [others => (others => <>)];

      for Field in Field_Ordinal loop
         if Count = Maximum_Fields then
            Errors.Fail (Error, Errors.Capacity_Exceeded);
            return;
         end if;
         Count := Count + 1;
         Fields (Count) := Field;
         declare
            Name : constant String := Primary_Name (Field);
         begin
            if Name'Length = 0 or else Name'Length > Maximum_Field_Name_Length then
               Errors.Fail (Error, Errors.Capacity_Exceeded);
               return;
            elsif not Flyology_Serde.UTF_8.Is_Valid (Name) then
               Errors.Fail (Error, Errors.Invalid_Text);
               return;
            end if;
            Store (Names (Count), Name);
         end;
      end loop;

      for Index in Field_Index'First .. Count loop
         if Index < Count then
            for Other in Field_Index'Succ (Index) .. Count loop
               if Equals (Names (Index), Names (Other)) then
                  Errors.Fail (Error, Errors.Application_Error);
                  return;
               end if;
            end loop;
         end if;
      end loop;

      for Index in Field_Index'First .. Count loop
         if not Equals (Names (Index), Primary_Name (Fields (Index))) then
            Errors.Fail (Error, Errors.Application_Error);
            return;
         end if;
      end loop;
   end Prepare_Metadata;

   procedure Serialize_Value
     (Item  : Source_Type;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info)
   is
   begin
      if Error.Code /= Errors.No_Error then
         return;
      end if;

      declare
         Fields : Field_Table;
         Names  : Name_Table;
         Count  : Natural;
      begin
         Prepare_Metadata (Fields, Names, Count, Error);
         if Error.Code /= Errors.No_Error then
            return;
         end if;

         Into.Begin_Record (Type_Name, Count, Error);
         for Index in Field_Index'First .. Count loop
            exit when Error.Code /= Errors.No_Error;
            declare
               Name : constant String := Text (Names (Index));
            begin
               Errors.Push_Field (Error, Name);
               if Error.Code = Errors.No_Error then
                  Into.Put_Field (Name, Error);
               end if;
               if Error.Code = Errors.No_Error then
                  Serialize_Field (Item, Fields (Index), Into, Error);
               end if;
               if Error.Code = Errors.No_Error then
                  Errors.Pop (Error);
               end if;
            end;
         end loop;
         if Error.Code = Errors.No_Error then
            Into.End_Record (Error);
         end if;
      end;
   end Serialize_Value;
end Flyology_Serde.Adapters.Record_Serializers;
