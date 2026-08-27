with Ada.Streams;
with Flyology_Serde.Budgets;
with Flyology_Serde.Data_Model;
with Flyology_Serde.Deserialization;
with Flyology_Serde.Errors;
with Flyology_Serde.JSON_Event_Drivers;
with Flyology_Serde.Policies;
with Interfaces;

--  Private Flyology JSON event-to-Serde reader. The public handwritten Reader
--  remains authoritative until the complete event-backed data model passes
--  the reviewed differential cutover gate.

private package Flyology_Serde.Deserializers.JSON.Event_Readers is
   package Budgets renames Flyology_Serde.Budgets;
   package Data_Model renames Flyology_Serde.Data_Model;
   package Errors renames Flyology_Serde.Errors;
   package Policies renames Flyology_Serde.Policies;

   type Reader (Source : not null access constant String) is limited
     new Deserialization.Deserializer with private;

   procedure Initialize
     (Self   : in out Reader;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info);

   procedure Reset
     (Self   : in out Reader;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info);

   function Is_Complete (Self : Reader) return Boolean;
   function Input_Offset (Self : Reader) return Natural;
   function Input_Consumed (Self : Reader) return Natural;
   function Values_Consumed (Self : Reader) return Natural;
   function Container_Depth (Self : Reader) return Natural;
   function Budget_Depth (Self : Reader) return Natural;

   overriding
   function Capabilities (Self : Reader) return Data_Model.Format_Capabilities;

   overriding
   function Peek_Kind
     (Self : in out Reader; Error : in out Errors.Error_Info)
      return Data_Model.Value_Kind;

   overriding
   procedure Finish_Document
     (Self : in out Reader; Error : in out Errors.Error_Info);

   overriding
   procedure Abort_Document
     (Self : in out Reader; Error : in out Errors.Error_Info);

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
   procedure End_Map (Self : in out Reader; Error : in out Errors.Error_Info);

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
   type Operation_State is (Uninitialized, Ready, Active, Complete, Failed);
   type Root_State is (Root_Ready, Root_In_Progress, Root_Complete);

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
      Kind       : Container_Kind := Sequence_Container;
      Child      : Child_State := No_Child;
      Map_Phase  : Map_State := Map_Needs_Entry;
      First_Item : Boolean := True;
      Exhausted  : Boolean := False;
   end record;
   type Container_Stack is
     array (Positive range 1 .. Policies.Maximum_Supported_Nesting)
     of Container_Frame;

   type Terminal_State is
     (No_Pending_Terminal,
      Retained_Delimiter,
      Deferred_Invalid_Follower,
      Unclassified_Exhausted);
   type Terminal_Owner is
     (No_Terminal_Owner,
      Root_Terminal,
      Sequence_Child_Terminal,
      Sequence_End_Terminal);

   type Reader (Source : not null access constant String) is limited
     new Deserialization.Deserializer
   with record
      Policy              : Policies.Decode_Policy;
      Budget              : Budgets.Decode_Budget;
      Syntax              : JSON_Event_Drivers.Driver (Source);
      Stack               : Container_Stack := [others => <>];
      Depth               : Natural := 0;
      Cursor              : Natural := 0;
      Root_End_Offset     : Natural := 0;
      Operation           : Operation_State := Uninitialized;
      Root                : Root_State := Root_Ready;
      Terminal            : Terminal_State := No_Pending_Terminal;
      Owner               : Terminal_Owner := No_Terminal_Owner;
      Owner_Depth         : Natural := 0;
      Document_Begin_Seen : Boolean := False;
      Document_End_Seen   : Boolean := False;
   end record;
end Flyology_Serde.Deserializers.JSON.Event_Readers;
