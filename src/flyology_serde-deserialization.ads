with Ada.Streams;
with Flyology_Serde.Data_Model;
with Flyology_Serde.Errors;
with Interfaces;

--  Bounded pull source implemented by JSON, CBOR, and other format backends.

package Flyology_Serde.Deserialization is
   package Data_Model renames Flyology_Serde.Data_Model;
   package Errors renames Flyology_Serde.Errors;

   type Deserializer is limited interface;

   function Peek_Kind
     (Self : in out Deserializer; Error : in out Errors.Error_Info)
      return Data_Model.Value_Kind
   is abstract;

   procedure Read_Null
     (Self : in out Deserializer; Error : in out Errors.Error_Info)
   is abstract;

   procedure Read_Boolean
     (Self  : in out Deserializer;
      Value : out Boolean;
      Error : in out Errors.Error_Info)
   is abstract;

   procedure Read_Signed
     (Self  : in out Deserializer;
      Value : out Interfaces.Integer_64;
      Error : in out Errors.Error_Info)
   is abstract;

   procedure Read_Unsigned
     (Self  : in out Deserializer;
      Value : out Interfaces.Unsigned_64;
      Error : in out Errors.Error_Info)
   is abstract;

   procedure Read_Float_64
     (Self  : in out Deserializer;
      Value : out Interfaces.IEEE_Float_64;
      Error : in out Errors.Error_Info)
   is abstract;

   --  Copies validated UTF-8; Length is the number of bytes copied.
   procedure Read_Text
     (Self   : in out Deserializer;
      Value  : out String;
      Length : out Natural;
      Error  : in out Errors.Error_Info)
   is abstract;

   --  Copies bytes; Length is the number of stream elements copied.
   procedure Read_Bytes
     (Self   : in out Deserializer;
      Value  : out Ada.Streams.Stream_Element_Array;
      Length : out Natural;
      Error  : in out Errors.Error_Info)
   is abstract;

   procedure Skip_Value
     (Self : in out Deserializer; Error : in out Errors.Error_Info)
   is abstract;

   procedure Begin_Sequence
     (Self   : in out Deserializer;
      Length : out Data_Model.Length_Information;
      Error  : in out Errors.Error_Info)
   is abstract;

   procedure Next_Element
     (Self      : in out Deserializer;
      Available : out Boolean;
      Error     : in out Errors.Error_Info)
   is abstract;

   procedure End_Sequence
     (Self : in out Deserializer; Error : in out Errors.Error_Info)
   is abstract;

   procedure Begin_Map
     (Self   : in out Deserializer;
      Length : out Data_Model.Length_Information;
      Error  : in out Errors.Error_Info)
   is abstract;

   procedure Next_Map_Entry
     (Self      : in out Deserializer;
      Available : out Boolean;
      Error     : in out Errors.Error_Info)
   is abstract;

   procedure End_Map
     (Self : in out Deserializer; Error : in out Errors.Error_Info)
   is abstract;

   procedure Begin_Record
     (Self      : in out Deserializer;
      Type_Name : String;
      Length    : out Data_Model.Length_Information;
      Error     : in out Errors.Error_Info)
   is abstract;

   procedure Next_Field
     (Self      : in out Deserializer;
      Name      : out String;
      Length    : out Natural;
      Available : out Boolean;
      Error     : in out Errors.Error_Info)
   is abstract;

   procedure End_Record
     (Self : in out Deserializer; Error : in out Errors.Error_Info)
   is abstract;

   procedure Read_Enumeration
     (Self         : in out Deserializer;
      Type_Name    : String;
      Literal_Name : out String;
      Length       : out Natural;
      Error        : in out Errors.Error_Info)
   is abstract;

   procedure Begin_Variant
     (Self             : in out Deserializer;
      Type_Name        : String;
      Alternative_Name : out String;
      Name_Length      : out Natural;
      Length           : out Data_Model.Length_Information;
      Error            : in out Errors.Error_Info)
   is abstract;

   procedure End_Variant
     (Self : in out Deserializer; Error : in out Errors.Error_Info)
   is abstract;
end Flyology_Serde.Deserialization;
