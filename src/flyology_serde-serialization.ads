with Ada.Streams;
with Flyology_Serde.Data_Model;
with Flyology_Serde.Errors;
with Interfaces;

--  Event sink implemented by JSON, CBOR, and other format backends.

package Flyology_Serde.Serialization is
   package Data_Model renames Flyology_Serde.Data_Model;
   package Errors renames Flyology_Serde.Errors;

   type Serializer is limited interface;

   function Capabilities
     (Self : Serializer) return Data_Model.Format_Capabilities
   is abstract;

   procedure Put_Null
     (Self : in out Serializer; Error : in out Errors.Error_Info)
   is abstract;

   procedure Put_Boolean
     (Self  : in out Serializer;
      Value : Boolean;
      Error : in out Errors.Error_Info)
   is abstract;

   procedure Put_Signed
     (Self  : in out Serializer;
      Value : Interfaces.Integer_64;
      Error : in out Errors.Error_Info)
   is abstract;

   procedure Put_Unsigned
     (Self  : in out Serializer;
      Value : Interfaces.Unsigned_64;
      Error : in out Errors.Error_Info)
   is abstract;

   procedure Put_Float_64
     (Self  : in out Serializer;
      Value : Interfaces.IEEE_Float_64;
      Error : in out Errors.Error_Info)
   is abstract;

   --  Value is validated UTF-8 and is borrowed only until this call returns.
   procedure Put_Text
     (Self  : in out Serializer;
      Value : String;
      Error : in out Errors.Error_Info)
   is abstract;

   --  Value is borrowed only until this call returns.
   procedure Put_Bytes
     (Self  : in out Serializer;
      Value : Ada.Streams.Stream_Element_Array;
      Error : in out Errors.Error_Info)
   is abstract;

   procedure Begin_Optional
     (Self    : in out Serializer;
      Present : Boolean;
      Error   : in out Errors.Error_Info)
   is abstract;

   procedure End_Optional
     (Self : in out Serializer; Error : in out Errors.Error_Info)
   is abstract;

   procedure Begin_Sequence
     (Self   : in out Serializer;
      Length : Data_Model.Length_Information;
      Error  : in out Errors.Error_Info)
   is abstract;

   procedure End_Sequence
     (Self : in out Serializer; Error : in out Errors.Error_Info)
   is abstract;

   procedure Begin_Map
     (Self   : in out Serializer;
      Length : Data_Model.Length_Information;
      Error  : in out Errors.Error_Info)
   is abstract;

   procedure End_Map
     (Self : in out Serializer; Error : in out Errors.Error_Info)
   is abstract;

   procedure Begin_Record
     (Self        : in out Serializer;
      Type_Name   : String;
      Field_Count : Natural;
      Error       : in out Errors.Error_Info)
   is abstract;

   procedure Put_Field
     (Self  : in out Serializer;
      Name  : String;
      Error : in out Errors.Error_Info)
   is abstract;

   procedure End_Record
     (Self : in out Serializer; Error : in out Errors.Error_Info)
   is abstract;

   procedure Put_Enumeration
     (Self         : in out Serializer;
      Type_Name    : String;
      Literal_Name : String;
      Error        : in out Errors.Error_Info)
   is abstract;

   procedure Begin_Variant
     (Self             : in out Serializer;
      Type_Name        : String;
      Alternative_Name : String;
      Field_Count      : Natural;
      Error            : in out Errors.Error_Info)
   is abstract;

   procedure End_Variant
     (Self : in out Serializer; Error : in out Errors.Error_Info)
   is abstract;
end Flyology_Serde.Serialization;
