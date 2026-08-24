with Ada.Finalization;
with Flyology_Serde.Deserialization;
with Flyology_Serde.Errors;
with Flyology_Serde.Serialization;

package Handwritten_Fixtures is
   type Private_Value is private;
   function Make_Private (Value : Integer) return Private_Value;
   function Observe (Item : Private_Value) return Integer;
   procedure Serialize
     (Item  : Private_Value;
      Into  : in out Flyology_Serde.Serialization.Serializer'Class;
      Error : in out Flyology_Serde.Errors.Error_Info);

   type Limited_Value is limited private;
   procedure Initialize (Target : in out Limited_Value; Value : Integer);
   function Observe (Item : Limited_Value) return Integer;
   procedure Serialize
     (Item  : Limited_Value;
      Into  : in out Flyology_Serde.Serialization.Serializer'Class;
      Error : in out Flyology_Serde.Errors.Error_Info);

   type Resource is new Ada.Finalization.Controlled with record
      Data  : Integer := 0;
      Owned : Boolean := False;
   end record;
   overriding procedure Finalize (Item : in out Resource);

   type Controlled_Builder is limited private;
   procedure Initialize (Target : in out Controlled_Builder; Value : Integer);
   function Value (Target : Controlled_Builder) return Integer;
   procedure Deserialize
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out Controlled_Builder;
      Error  : in out Flyology_Serde.Errors.Error_Info);
   procedure Reset_Controlled_Counters;
   function Acquisitions return Natural;
   function Releases return Natural;

   type Variant_Kind is (Number_Kind, Flag_Kind);
   type Discriminated_Value (Kind : Variant_Kind := Number_Kind) is record
      case Kind is
         when Number_Kind =>
            Number : Integer := 0;
         when Flag_Kind =>
            Flag : Boolean := False;
      end case;
   end record;

   type Variant_Builder is limited private;
   procedure Initialize
     (Target : in out Variant_Builder; Item : Discriminated_Value);
   function Value (Target : Variant_Builder) return Discriminated_Value;
   procedure Deserialize
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out Variant_Builder;
      Error  : in out Flyology_Serde.Errors.Error_Info);

   generic
      type Scalar is range <>;
   package Boxes is
      type Box is private;
      function Make (Value : Scalar) return Box;
      function Get (Item : Box) return Scalar;
   private
      type Box is record
         Element : Scalar;
      end record;
   end Boxes;

private
   type Private_Value is record
      Data : Integer := 0;
   end record;

   type Limited_Value is limited record
      Data : Integer := 0;
   end record;

   type Controlled_Builder is limited record
      Published : Integer := 0;
      Candidate : Resource;
   end record;

   type Variant_Builder is limited record
      Published        : Discriminated_Value;
      Candidate_Kind   : Variant_Kind := Number_Kind;
      Candidate_Number : Integer := 0;
      Candidate_Flag   : Boolean := False;
      Has_Field        : Boolean := False;
   end record;
end Handwritten_Fixtures;
