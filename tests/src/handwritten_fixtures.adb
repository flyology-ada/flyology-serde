with Flyology_Serde.Adapters.Signed_Integers;
with Flyology_Serde.Data_Model;
with Flyology_Serde.Deserialization_Adapters;
with Flyology_Serde.Policies;
with Flyology_Serde.Serialization_Adapters;

package body Handwritten_Fixtures is
   package Errors renames Flyology_Serde.Errors;
   package Policies renames Flyology_Serde.Policies;
   package Serialization renames Flyology_Serde.Serialization;
   package Integers is new Flyology_Serde.Adapters.Signed_Integers (Integer);
   use type Errors.Error_Code;

   Policy : constant Policies.Decode_Policy := (others => <>);
   Limits : constant Serialization.Serialization_Limits :=
     (Maximum_Nesting_Depth   => 8,
      Maximum_Container_Items => 16,
      Maximum_Text_Length     => 64,
      Maximum_Byte_Length     => 64,
      Maximum_Logical_Events  => 32);

   Acquisition_Count : Natural := 0;
   Release_Count : Natural := 0;

   function Make_Private (Value : Integer) return Private_Value is
     (Data => Value);

   function Observe (Item : Private_Value) return Integer is
     (Item.Data);

   procedure Serialize_Private_Value
     (Item  : Private_Value;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
   begin
      Integers.Serialize_Value (Item.Data, Into, Error);
   end Serialize_Private_Value;

   package Private_Serialization is new Flyology_Serde.Serialization_Adapters
     (Source_Type      => Private_Value,
      Limits           => Limits,
      Serialize_Value => Serialize_Private_Value);

   procedure Serialize
     (Item  : Private_Value;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
   begin
      Private_Serialization.Serialize (Item, Into, Error);
   end Serialize;

   procedure Initialize (Target : in out Limited_Value; Value : Integer) is
   begin
      Target.Data := Value;
   end Initialize;

   function Observe (Item : Limited_Value) return Integer is
     (Item.Data);

   procedure Serialize_Limited_Value
     (Item  : Limited_Value;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
   begin
      Integers.Serialize_Value (Item.Data, Into, Error);
   end Serialize_Limited_Value;

   package Limited_Serialization is new Flyology_Serde.Serialization_Adapters
     (Source_Type      => Limited_Value,
      Limits           => Limits,
      Serialize_Value => Serialize_Limited_Value);

   procedure Serialize
     (Item  : Limited_Value;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
   begin
      Limited_Serialization.Serialize (Item, Into, Error);
   end Serialize;

   overriding procedure Finalize (Item : in out Resource) is
   begin
      if Item.Owned then
         Release_Count := Release_Count + 1;
         Item.Owned := False;
      end if;
   end Finalize;

   procedure Begin_Controlled
     (Target : in out Controlled_Builder; Error : in out Errors.Error_Info)
   is
      pragma Unreferenced (Error);
   begin
      pragma Assert (not Target.Candidate.Owned);
      Target.Candidate.Owned := True;
      Acquisition_Count := Acquisition_Count + 1;
   end Begin_Controlled;

   procedure Read_Controlled
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out Controlled_Builder;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info)
   is
      pragma Unreferenced (Policy);
   begin
      Integers.Deserialize_Candidate (From, Target.Candidate.Data, Error);
   end Read_Controlled;

   procedure Commit_Controlled
     (Target : in out Controlled_Builder; Error : in out Errors.Error_Info)
   is
      pragma Unreferenced (Error);
   begin
      Target.Published := Target.Candidate.Data;
      if Target.Candidate.Owned then
         Release_Count := Release_Count + 1;
         Target.Candidate.Owned := False;
      end if;
   end Commit_Controlled;

   procedure Rollback_Controlled (Target : in out Controlled_Builder) is
   begin
      if Target.Candidate.Owned then
         Release_Count := Release_Count + 1;
         Target.Candidate.Owned := False;
      end if;
   exception
      when others =>
         null;
   end Rollback_Controlled;

   package Controlled_Deserialization is new Flyology_Serde.Deserialization_Adapters
     (Builder_Type       => Controlled_Builder,
      Policy             => Policy,
      Begin_Candidate    => Begin_Controlled,
      Deserialize_Value  => Read_Controlled,
      Commit_Candidate   => Commit_Controlled,
      Rollback_Candidate => Rollback_Controlled);

   procedure Initialize (Target : in out Controlled_Builder; Value : Integer) is
   begin
      Target.Published := Value;
   end Initialize;

   function Value (Target : Controlled_Builder) return Integer is
     (Target.Published);

   procedure Deserialize
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out Controlled_Builder;
      Error  : in out Errors.Error_Info) is
   begin
      Controlled_Deserialization.Deserialize (From, Target, Error);
   end Deserialize;

   procedure Reset_Controlled_Counters is
   begin
      Acquisition_Count := 0;
      Release_Count := 0;
   end Reset_Controlled_Counters;

   function Acquisitions return Natural is (Acquisition_Count);
   function Releases return Natural is (Release_Count);

   procedure Begin_Variant_Candidate
     (Target : in out Variant_Builder; Error : in out Errors.Error_Info)
   is
      pragma Unreferenced (Error);
   begin
      Target.Has_Field := False;
   end Begin_Variant_Candidate;

   procedure Read_Variant
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out Variant_Builder;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info)
   is
      pragma Unreferenced (Policy);
      Alternative : String (1 .. 16);
      Alternative_Last : Natural := 0;
      Length : Flyology_Serde.Data_Model.Length_Information;
      Name : String (1 .. 16);
      Name_Last : Natural := 0;
      Available : Boolean := False;
   begin
      From.Begin_Variant
        ("Fixtures.Discriminated", Alternative, Alternative_Last, Length, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Alternative (1 .. Alternative_Last) = "number" then
         Target.Candidate_Kind := Number_Kind;
      elsif Alternative (1 .. Alternative_Last) = "flag" then
         Target.Candidate_Kind := Flag_Kind;
      else
         Errors.Fail (Error, Errors.Invalid_Value);
         return;
      end if;

      From.Next_Field (Name, Name_Last, Available, Error);
      if Error.Code /= Errors.No_Error then
         return;
      elsif not Available then
         Errors.Fail (Error, Errors.Missing_Field);
         return;
      elsif Target.Candidate_Kind = Number_Kind
        and then Name (1 .. Name_Last) = "number"
      then
         Integers.Deserialize_Candidate (From, Target.Candidate_Number, Error);
      elsif Target.Candidate_Kind = Flag_Kind
        and then Name (1 .. Name_Last) = "flag"
      then
         From.Read_Boolean (Target.Candidate_Flag, Error);
      else
         Errors.Fail (Error, Errors.Unknown_Field);
      end if;
      Target.Has_Field := Error.Code = Errors.No_Error;
      if Error.Code = Errors.No_Error then
         From.Next_Field (Name, Name_Last, Available, Error);
      end if;
      if Error.Code = Errors.No_Error and then Available then
         Errors.Fail (Error, Errors.Duplicate_Field);
      elsif Error.Code = Errors.No_Error then
         From.End_Variant (Error);
      end if;
   end Read_Variant;

   procedure Commit_Variant
     (Target : in out Variant_Builder; Error : in out Errors.Error_Info)
   is
      pragma Unreferenced (Error);
   begin
      pragma Assert (Target.Has_Field);
      case Target.Candidate_Kind is
         when Number_Kind =>
            Target.Published :=
              (Kind => Number_Kind, Number => Target.Candidate_Number);
         when Flag_Kind =>
            Target.Published :=
              (Kind => Flag_Kind, Flag => Target.Candidate_Flag);
      end case;
   end Commit_Variant;

   procedure Rollback_Variant (Target : in out Variant_Builder) is
   begin
      Target.Has_Field := False;
   end Rollback_Variant;

   package Variant_Deserialization is new Flyology_Serde.Deserialization_Adapters
     (Builder_Type       => Variant_Builder,
      Policy             => Policy,
      Begin_Candidate    => Begin_Variant_Candidate,
      Deserialize_Value  => Read_Variant,
      Commit_Candidate   => Commit_Variant,
      Rollback_Candidate => Rollback_Variant);

   procedure Initialize
     (Target : in out Variant_Builder; Item : Discriminated_Value) is
   begin
      Target.Published := Item;
      Target.Has_Field := False;
   end Initialize;

   function Value (Target : Variant_Builder) return Discriminated_Value is
     (Target.Published);

   procedure Deserialize
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out Variant_Builder;
      Error  : in out Errors.Error_Info) is
   begin
      Variant_Deserialization.Deserialize (From, Target, Error);
   end Deserialize;

   package body Boxes is
      function Make (Value : Scalar) return Box is
        (Element => Value);

      function Get (Item : Box) return Scalar is
        (Item.Element);
   end Boxes;
end Handwritten_Fixtures;
