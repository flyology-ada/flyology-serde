with Flyology_Serde.UTF_8;

package body Flyology_Serde.Adapters.Enumeration_Serializers is
   use type Errors.Error_Code;

   subtype Literal_Index is Positive range 1 .. Maximum_Literals;

   type Literal_Table is array (Literal_Index) of Value_Type;

   type Bounded_Name is record
      Length : Natural range 0 .. Maximum_Literal_Name_Length := 0;
      Data   : String (1 .. Maximum_Literal_Name_Length) := [others => ' '];
   end record;

   type Name_Table is array (Literal_Index) of Bounded_Name;

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
     (Literals : out Literal_Table;
      Names    : out Name_Table;
      Count    : out Natural;
      Error    : in out Errors.Error_Info) is
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

      Literals := [others => Value_Type'First];
      Names := [others => (others => <>)];

      for Value in Value_Type loop
         if Count = Maximum_Literals then
            Errors.Fail (Error, Errors.Capacity_Exceeded);
            return;
         end if;
         Count := Count + 1;
         Literals (Count) := Value;
         declare
            Name : constant String := Primary_Name (Value);
         begin
            if Name'Length = 0 or else Name'Length > Maximum_Literal_Name_Length then
               Errors.Fail (Error, Errors.Capacity_Exceeded);
               return;
            elsif not Flyology_Serde.UTF_8.Is_Valid (Name) then
               Errors.Fail (Error, Errors.Invalid_Text);
               return;
            end if;
            Store (Names (Count), Name);
         end;
      end loop;

      for Index in Literal_Index'First .. Count loop
         if Index < Count then
            for Other in Literal_Index'Succ (Index) .. Count loop
               if Equals (Names (Index), Names (Other)) then
                  Errors.Fail (Error, Errors.Application_Error);
                  return;
               end if;
            end loop;
         end if;
      end loop;

      for Index in Literal_Index'First .. Count loop
         if not Equals (Names (Index), Primary_Name (Literals (Index))) then
            Errors.Fail (Error, Errors.Application_Error);
            return;
         end if;
      end loop;
   end Prepare_Metadata;

   procedure Serialize_Value
     (Item  : Value_Type;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info)
   is
   begin
      if Error.Code /= Errors.No_Error then
         return;
      end if;

      declare
         Literals : Literal_Table;
         Names    : Name_Table;
         Count    : Natural;
      begin
         Prepare_Metadata (Literals, Names, Count, Error);
         if Error.Code /= Errors.No_Error then
            return;
         end if;

         for Index in Literal_Index'First .. Count loop
            if Literals (Index) = Item then
               Into.Put_Enumeration (Type_Name, Text (Names (Index)), Error);
               return;
            end if;
         end loop;
         Errors.Fail (Error, Errors.Application_Error);
      end;
   end Serialize_Value;
end Flyology_Serde.Adapters.Enumeration_Serializers;
