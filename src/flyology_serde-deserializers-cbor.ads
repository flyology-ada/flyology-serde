with Ada.Streams;
with Flyology_Serde.Budgets;
with Flyology_Serde.Data_Model;
with Flyology_Serde.Deserialization;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;
with Interfaces;

--  Bounded pull reader for RFC 8949 CBOR and the serde logical mapping.

package Flyology_Serde.Deserializers.CBOR is
   package Budgets renames Flyology_Serde.Budgets;
   package Data_Model renames Flyology_Serde.Data_Model;
   package Errors renames Flyology_Serde.Errors;
   package Policies renames Flyology_Serde.Policies;

   --  Source is borrowed for the Reader's lifetime and must not be mutated
   --  through another alias or task. Decoded values are copied to caller
   --  buffers; no source slice escapes an operation.
   type Reader
     (Source : not null access constant Ada.Streams.Stream_Element_Array) is
     limited new Deserialization.Deserializer with private;

   procedure Initialize
     (Self   : in out Reader;
      Policy : Policies.Decode_Policy := (others => <>));

   procedure Reset
     (Self   : in out Reader;
      Policy : Policies.Decode_Policy := (others => <>));

   procedure Finish_Document
     (Self : in out Reader; Error : in out Errors.Error_Info);

   function Is_Complete (Self : Reader) return Boolean;
   function Input_Offset (Self : Reader) return Natural;

   overriding
   function Capabilities
     (Self : Reader) return Data_Model.Format_Capabilities;

   overriding
   function Peek_Kind
     (Self : in out Reader; Error : in out Errors.Error_Info)
      return Data_Model.Value_Kind;

   overriding
   procedure Read_Null
     (Self : in out Reader; Error : in out Errors.Error_Info);

   overriding
   procedure Read_Boolean
     (Self  : in out Reader;
      Value : out Boolean;
      Error : in out Errors.Error_Info);

   overriding
   procedure Read_Signed
     (Self  : in out Reader;
      Value : out Interfaces.Integer_64;
      Error : in out Errors.Error_Info);

   overriding
   procedure Read_Unsigned
     (Self  : in out Reader;
      Value : out Interfaces.Unsigned_64;
      Error : in out Errors.Error_Info);

   overriding
   procedure Read_Float_64
     (Self  : in out Reader;
      Value : out Data_Model.Float_64_Value;
      Error : in out Errors.Error_Info);

   overriding
   procedure Read_Text
     (Self   : in out Reader;
      Value  : out String;
      Length : out Natural;
      Error  : in out Errors.Error_Info);

   overriding
   procedure Read_Bytes
     (Self   : in out Reader;
      Value  : out Ada.Streams.Stream_Element_Array;
      Length : out Natural;
      Error  : in out Errors.Error_Info);

   overriding
   procedure Skip_Value
     (Self : in out Reader; Error : in out Errors.Error_Info);

   overriding
   procedure Begin_Optional
     (Self    : in out Reader;
      Present : out Boolean;
      Error   : in out Errors.Error_Info);

   overriding
   procedure End_Optional
     (Self : in out Reader; Error : in out Errors.Error_Info);

   overriding
   procedure Begin_Sequence
     (Self   : in out Reader;
      Length : out Data_Model.Length_Information;
      Error  : in out Errors.Error_Info);

   overriding
   procedure Next_Element
     (Self      : in out Reader;
      Available : out Boolean;
      Error     : in out Errors.Error_Info);

   overriding
   procedure End_Sequence
     (Self : in out Reader; Error : in out Errors.Error_Info);

   overriding
   procedure Begin_Map
     (Self   : in out Reader;
      Length : out Data_Model.Length_Information;
      Error  : in out Errors.Error_Info);

   overriding
   procedure Next_Map_Entry
     (Self      : in out Reader;
      Available : out Boolean;
      Error     : in out Errors.Error_Info);

   overriding
   procedure End_Map
     (Self : in out Reader; Error : in out Errors.Error_Info);

   overriding
   procedure Begin_Record
     (Self      : in out Reader;
      Type_Name : String;
      Length    : out Data_Model.Length_Information;
      Error     : in out Errors.Error_Info);

   overriding
   procedure Next_Field
     (Self      : in out Reader;
      Name      : out String;
      Length    : out Natural;
      Available : out Boolean;
      Error     : in out Errors.Error_Info);

   overriding
   procedure End_Record
     (Self : in out Reader; Error : in out Errors.Error_Info);

   overriding
   procedure Read_Enumeration
     (Self         : in out Reader;
      Type_Name    : String;
      Literal_Name : out String;
      Length       : out Natural;
      Error        : in out Errors.Error_Info);

   overriding
   procedure Begin_Variant
     (Self             : in out Reader;
      Type_Name        : String;
      Alternative_Name : out String;
      Name_Length      : out Natural;
      Length           : out Data_Model.Length_Information;
      Error            : in out Errors.Error_Info);

   overriding
   procedure End_Variant
     (Self : in out Reader; Error : in out Errors.Error_Info);

private
   type Container_Kind is
     (Optional_Container,
      Sequence_Container,
      Map_Container,
      Record_Container,
      Variant_Container);

   type Child_State is (No_Child, Child_Ready, Child_In_Progress);
   type Map_State is
     (Map_Needs_Entry,
      Map_Key_Ready,
      Map_Key_In_Progress,
      Map_Value_Ready,
      Map_Value_In_Progress);

   type Container_Frame is record
      Kind                : Container_Kind := Sequence_Container;
      Child               : Child_State := No_Child;
      Map_Phase           : Map_State := Map_Needs_Entry;
      Declared            : Data_Model.Length_Information;
      Observed            : Natural := 0;
      Exhausted           : Boolean := False;
      Indefinite          : Boolean := False;
      Envelope_Indefinite : Boolean := False;
   end record;

   type Container_Stack is
     array (Positive range 1 .. Policies.Maximum_Supported_Nesting)
     of Container_Frame;

   type Root_State is (Root_Ready, Root_In_Progress, Root_Complete);

   type Reader
     (Source : not null access constant Ada.Streams.Stream_Element_Array) is
     limited new Deserialization.Deserializer with record
      Policy            : Policies.Decode_Policy;
      Budget            : Budgets.Decode_Budget;
      Stack             : Container_Stack := [others => <>];
      Depth             : Natural := 0;
      Cursor            : Natural := 0;
      Root              : Root_State := Root_Ready;
      Initialized       : Boolean := False;
      Failed            : Boolean := False;
      Document_Complete : Boolean := False;
   end record;
end Flyology_Serde.Deserializers.CBOR;
