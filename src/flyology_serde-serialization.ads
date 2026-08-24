with Ada.Streams;
with Flyology_Serde.Data_Model;
with Flyology_Serde.Errors;
with Interfaces;

--  Event sink implemented by JSON, CBOR, and other format backends.

package Flyology_Serde.Serialization is
   package Data_Model renames Flyology_Serde.Data_Model;
   package Errors renames Flyology_Serde.Errors;

   type Serializer is limited interface;

   type Serializer_State is (Ready, Active, Finished, Poisoned);

   --  Every implementation starts, or is explicitly reset, in Ready. The
   --  first accepted root event changes the operation to Active. A successful
   --  balanced Finish_Document changes it to Finished and makes the published
   --  document immutable. In Finished, another event or Finish_Document
   --  reports Invalid_State without changing state or output. Poisoned rejects
   --  events and Finish_Document with Invalid_State. When Error is already
   --  latched, every event and Finish_Document is a strict no-op.
   --
   --  Abort_Document is the nonraising, idempotent transition from any state
   --  to Poisoned and revokes publication. A concrete Reset is the only route
   --  from Finished or Poisoned to Ready. Capabilities remain stable for one
   --  operation. Together with the root Serialization_Limits, they completely
   --  determine semantic acceptance of an identical traversal; after a
   --  successful Counting preflight, only backend storage or sink failures
   --  may newly fail in the real pass.

   type Serialization_Limits is record
      Maximum_Nesting_Depth   : Natural;
      Maximum_Container_Items : Natural;
      Maximum_Text_Length     : Natural;
      Maximum_Byte_Length     : Natural;
      Maximum_Logical_Events  : Natural;
   end record;

   function Capabilities
     (Self : Serializer) return Data_Model.Format_Capabilities
   is abstract;

   function State (Self : Serializer) return Serializer_State is abstract;

   --  Finish publishes one balanced root value. Buffered output remains
   --  unavailable until this succeeds.
   procedure Finish_Document
     (Self : in out Serializer; Error : in out Errors.Error_Info)
   is abstract;

   --  Abort is nonraising and idempotent. It releases local traversal state
   --  and poisons the serializer until its concrete Reset operation is used.
   --  A streaming backend cannot retract bytes already accepted by its sink.
   procedure Abort_Document (Self : in out Serializer) is abstract;

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
      Value : Data_Model.Float_64_Value;
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
