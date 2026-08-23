with Ada.Containers.Vectors;
with Ada.Streams;
with Flyology_Serde.Data_Model;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;
with Flyology_Serde.Serialization;
with Interfaces;

--  RFC 8949 CBOR writers for the Flyology serde logical data model.

package Flyology_Serde.Serializers.CBOR is
   package Data_Model renames Flyology_Serde.Data_Model;
   package Errors renames Flyology_Serde.Errors;
   package Policies renames Flyology_Serde.Policies;

   type Writer_Base is abstract limited
     new Serialization.Serializer with private;

   overriding
   function Capabilities
     (Self : Writer_Base) return Data_Model.Format_Capabilities;

   overriding
   procedure Put_Null
     (Self : in out Writer_Base; Error : in out Errors.Error_Info);

   overriding
   procedure Put_Boolean
     (Self  : in out Writer_Base;
      Value : Boolean;
      Error : in out Errors.Error_Info);

   overriding
   procedure Put_Signed
     (Self  : in out Writer_Base;
      Value : Interfaces.Integer_64;
      Error : in out Errors.Error_Info);

   overriding
   procedure Put_Unsigned
     (Self  : in out Writer_Base;
      Value : Interfaces.Unsigned_64;
      Error : in out Errors.Error_Info);

   overriding
   procedure Put_Float_64
     (Self  : in out Writer_Base;
      Value : Data_Model.Float_64_Value;
      Error : in out Errors.Error_Info);

   overriding
   procedure Put_Text
     (Self  : in out Writer_Base;
      Value : String;
      Error : in out Errors.Error_Info);

   overriding
   procedure Put_Bytes
     (Self  : in out Writer_Base;
      Value : Ada.Streams.Stream_Element_Array;
      Error : in out Errors.Error_Info);

   overriding
   procedure Begin_Optional
     (Self    : in out Writer_Base;
      Present : Boolean;
      Error   : in out Errors.Error_Info);

   overriding
   procedure End_Optional
     (Self : in out Writer_Base; Error : in out Errors.Error_Info);

   overriding
   procedure Begin_Sequence
     (Self   : in out Writer_Base;
      Length : Data_Model.Length_Information;
      Error  : in out Errors.Error_Info);

   overriding
   procedure End_Sequence
     (Self : in out Writer_Base; Error : in out Errors.Error_Info);

   overriding
   procedure Begin_Map
     (Self   : in out Writer_Base;
      Length : Data_Model.Length_Information;
      Error  : in out Errors.Error_Info);

   overriding
   procedure End_Map
     (Self : in out Writer_Base; Error : in out Errors.Error_Info);

   overriding
   procedure Begin_Record
     (Self        : in out Writer_Base;
      Type_Name   : String;
      Field_Count : Natural;
      Error       : in out Errors.Error_Info);

   overriding
   procedure Put_Field
     (Self  : in out Writer_Base;
      Name  : String;
      Error : in out Errors.Error_Info);

   overriding
   procedure End_Record
     (Self : in out Writer_Base; Error : in out Errors.Error_Info);

   overriding
   procedure Put_Enumeration
     (Self         : in out Writer_Base;
      Type_Name    : String;
      Literal_Name : String;
      Error        : in out Errors.Error_Info);

   overriding
   procedure Begin_Variant
     (Self             : in out Writer_Base;
      Type_Name        : String;
      Alternative_Name : String;
      Field_Count      : Natural;
      Error            : in out Errors.Error_Info);

   overriding
   procedure End_Variant
     (Self : in out Writer_Base; Error : in out Errors.Error_Info);

   type Bounded_Writer (Capacity : Positive) is limited
     new Writer_Base with private;

   procedure Reset (Self : in out Bounded_Writer);
   function Written_Length (Self : Bounded_Writer) return Natural;
   procedure Copy_Output
     (Self   : Bounded_Writer;
      Target : out Ada.Streams.Stream_Element_Array;
      Length : out Natural;
      Error  : in out Errors.Error_Info);
   function Is_Complete (Self : Bounded_Writer) return Boolean;

   type Allocating_Writer is limited new Writer_Base with private;

   procedure Reset (Self : in out Allocating_Writer);
   function Output
     (Self : Allocating_Writer) return Ada.Streams.Stream_Element_Array;
   function Is_Complete (Self : Allocating_Writer) return Boolean;

private
   type Container_Kind is
     (Optional_Container,
      Sequence_Container,
      Map_Container,
      Record_Container,
      Variant_Container);

   type Container_Frame is record
      Kind               : Container_Kind := Sequence_Container;
      Expected_Known     : Boolean := False;
      Expected_Items     : Natural := 0;
      Observed_Items     : Natural := 0;
      Waiting_For_Value  : Boolean := False;
      Map_Child_Is_Value : Boolean := False;
   end record;

   type Container_Stack is
     array (Positive range 1 .. Policies.Maximum_Supported_Nesting)
     of Container_Frame;

   type Writer_Base is abstract limited new Serialization.Serializer
   with record
      Stack        : Container_Stack := [others => <>];
      Depth        : Natural := 0;
      Root_Written : Boolean := False;
      Failed       : Boolean := False;
   end record;

   procedure Emit
     (Self  : in out Writer_Base;
      Value : Ada.Streams.Stream_Element_Array;
      Error : in out Errors.Error_Info);

   type Bounded_Buffer is
     array (Positive range <>) of Ada.Streams.Stream_Element;

   type Bounded_Writer (Capacity : Positive) is limited new Writer_Base
   with record
      Buffer : Bounded_Buffer (1 .. Capacity) := [others => 0];
      Length : Natural := 0;
   end record;

   overriding
   procedure Emit
     (Self  : in out Bounded_Writer;
      Value : Ada.Streams.Stream_Element_Array;
      Error : in out Errors.Error_Info);

   package Byte_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Ada.Streams.Stream_Element,
      "="          => Ada.Streams."=");

   type Allocating_Writer is limited new Writer_Base with record
      Buffer : Byte_Vectors.Vector;
   end record;

   overriding
   procedure Emit
     (Self  : in out Allocating_Writer;
      Value : Ada.Streams.Stream_Element_Array;
      Error : in out Errors.Error_Info);
end Flyology_Serde.Serializers.CBOR;
