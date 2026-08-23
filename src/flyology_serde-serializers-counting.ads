with Ada.Streams;
with Flyology_Serde.Data_Model;
with Flyology_Serde.Errors;
with Flyology_Serde.Serialization;
with Interfaces;

--  Format-neutral serializer used to validate traversals without producing output.

package Flyology_Serde.Serializers.Counting is
   package Data_Model renames Flyology_Serde.Data_Model;

   type Counter is limited new Serialization.Serializer with private;

   overriding
   function Capabilities
     (Self : Counter) return Data_Model.Format_Capabilities;

   function Event_Count (Self : Counter) return Natural;

   function Container_Depth (Self : Counter) return Natural;

   overriding
   procedure Put_Null
     (Self : in out Counter; Error : in out Errors.Error_Info);

   overriding
   procedure Put_Boolean
     (Self  : in out Counter;
      Value : Boolean;
      Error : in out Errors.Error_Info);

   overriding
   procedure Put_Signed
     (Self  : in out Counter;
      Value : Interfaces.Integer_64;
      Error : in out Errors.Error_Info);

   overriding
   procedure Put_Unsigned
     (Self  : in out Counter;
      Value : Interfaces.Unsigned_64;
      Error : in out Errors.Error_Info);

   overriding
   procedure Put_Float_64
     (Self  : in out Counter;
      Value : Interfaces.IEEE_Float_64;
      Error : in out Errors.Error_Info);

   overriding
   procedure Put_Text
     (Self : in out Counter; Value : String; Error : in out Errors.Error_Info);

   overriding
   procedure Put_Bytes
     (Self  : in out Counter;
      Value : Ada.Streams.Stream_Element_Array;
      Error : in out Errors.Error_Info);

   overriding
   procedure Begin_Optional
     (Self    : in out Counter;
      Present : Boolean;
      Error   : in out Errors.Error_Info);

   overriding
   procedure End_Optional
     (Self : in out Counter; Error : in out Errors.Error_Info);

   overriding
   procedure Begin_Sequence
     (Self   : in out Counter;
      Length : Data_Model.Length_Information;
      Error  : in out Errors.Error_Info);

   overriding
   procedure End_Sequence
     (Self : in out Counter; Error : in out Errors.Error_Info);

   overriding
   procedure Begin_Map
     (Self   : in out Counter;
      Length : Data_Model.Length_Information;
      Error  : in out Errors.Error_Info);

   overriding
   procedure End_Map (Self : in out Counter; Error : in out Errors.Error_Info);

   overriding
   procedure Begin_Record
     (Self        : in out Counter;
      Type_Name   : String;
      Field_Count : Natural;
      Error       : in out Errors.Error_Info);

   overriding
   procedure Put_Field
     (Self : in out Counter; Name : String; Error : in out Errors.Error_Info);

   overriding
   procedure End_Record
     (Self : in out Counter; Error : in out Errors.Error_Info);

   overriding
   procedure Put_Enumeration
     (Self         : in out Counter;
      Type_Name    : String;
      Literal_Name : String;
      Error        : in out Errors.Error_Info);

   overriding
   procedure Begin_Variant
     (Self             : in out Counter;
      Type_Name        : String;
      Alternative_Name : String;
      Field_Count      : Natural;
      Error            : in out Errors.Error_Info);

   overriding
   procedure End_Variant
     (Self : in out Counter; Error : in out Errors.Error_Info);

private
   type Container_Kind is
     (Optional_Container,
      Sequence_Container,
      Map_Container,
      Record_Container,
      Variant_Container);

   type Container_Frame is record
      Kind              : Container_Kind := Sequence_Container;
      Expected_Known    : Boolean := False;
      Expected_Items    : Natural := 0;
      Observed_Items    : Natural := 0;
      Waiting_For_Value : Boolean := False;
   end record;

   type Container_Stack is
     array (Positive range 1 .. Errors.Maximum_Path_Depth) of Container_Frame;

   type Counter is limited new Serialization.Serializer with record
      Events : Natural := 0;
      Depth  : Natural := 0;
      Stack  : Container_Stack := [others => <>];
   end record;
end Flyology_Serde.Serializers.Counting;
