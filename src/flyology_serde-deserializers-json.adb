package body Flyology_Serde.Deserializers.JSON is

   procedure Initialize
     (Self : in out Reader; Policy : Policies.Decode_Policy := (others => <>))
   is
      Local_Error : Errors.Error_Info;
   begin
      Errors.Reset (Local_Error);
      JSON_Event_Readers.Reinitialize
        (Self.Implementation,
         Policy,
         Allow_Failed => False,
         Error        => Local_Error);
   end Initialize;

   procedure Reset
     (Self : in out Reader; Policy : Policies.Decode_Policy := (others => <>))
   is
      Local_Error : Errors.Error_Info;
   begin
      Errors.Reset (Local_Error);
      JSON_Event_Readers.Reinitialize
        (Self.Implementation,
         Policy,
         Allow_Failed => True,
         Error        => Local_Error);
   end Reset;

   overriding
   procedure Finish_Document
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      JSON_Event_Readers.Finish_Document (Self.Implementation, Error);
   end Finish_Document;

   overriding
   procedure Abort_Document
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      JSON_Event_Readers.Abort_Document (Self.Implementation, Error);
   end Abort_Document;

   function Is_Complete (Self : Reader) return Boolean
   is (JSON_Event_Readers.Is_Complete (Self.Implementation));

   function Input_Offset (Self : Reader) return Natural
   is (JSON_Event_Readers.Input_Offset (Self.Implementation));

   overriding
   function Capabilities (Self : Reader) return Data_Model.Format_Capabilities
   is (JSON_Event_Readers.Capabilities (Self.Implementation));

   overriding
   function Peek_Kind
     (Self : in out Reader; Error : in out Errors.Error_Info)
      return Data_Model.Value_Kind
   is (JSON_Event_Readers.Peek_Kind (Self.Implementation, Error));

   overriding
   procedure Read_Null (Self : in out Reader; Error : in out Errors.Error_Info)
   is
   begin
      JSON_Event_Readers.Read_Null (Self.Implementation, Error);
   end Read_Null;

   overriding
   procedure Read_Boolean
     (Self  : in out Reader;
      Value : out Boolean;
      Error : in out Errors.Error_Info) is
   begin
      JSON_Event_Readers.Read_Boolean (Self.Implementation, Value, Error);
   end Read_Boolean;

   overriding
   procedure Read_Signed
     (Self  : in out Reader;
      Value : out Interfaces.Integer_64;
      Error : in out Errors.Error_Info) is
   begin
      JSON_Event_Readers.Read_Signed (Self.Implementation, Value, Error);
   end Read_Signed;

   overriding
   procedure Read_Unsigned
     (Self  : in out Reader;
      Value : out Interfaces.Unsigned_64;
      Error : in out Errors.Error_Info) is
   begin
      JSON_Event_Readers.Read_Unsigned (Self.Implementation, Value, Error);
   end Read_Unsigned;

   overriding
   procedure Read_Float_64
     (Self  : in out Reader;
      Value : out Data_Model.Float_64_Value;
      Error : in out Errors.Error_Info) is
   begin
      JSON_Event_Readers.Read_Float_64 (Self.Implementation, Value, Error);
   end Read_Float_64;

   overriding
   procedure Read_Text
     (Self   : in out Reader;
      Value  : out String;
      Length : out Natural;
      Error  : in out Errors.Error_Info) is
   begin
      JSON_Event_Readers.Read_Text (Self.Implementation, Value, Length, Error);
   end Read_Text;

   overriding
   procedure Read_Bytes
     (Self   : in out Reader;
      Value  : out Ada.Streams.Stream_Element_Array;
      Length : out Natural;
      Error  : in out Errors.Error_Info) is
   begin
      JSON_Event_Readers.Read_Bytes
        (Self.Implementation, Value, Length, Error);
   end Read_Bytes;

   overriding
   procedure Skip_Value
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      JSON_Event_Readers.Skip_Value (Self.Implementation, Error);
   end Skip_Value;

   overriding
   procedure Begin_Optional
     (Self    : in out Reader;
      Present : out Boolean;
      Error   : in out Errors.Error_Info) is
   begin
      JSON_Event_Readers.Begin_Optional (Self.Implementation, Present, Error);
   end Begin_Optional;

   overriding
   procedure End_Optional
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      JSON_Event_Readers.End_Optional (Self.Implementation, Error);
   end End_Optional;

   overriding
   procedure Begin_Sequence
     (Self   : in out Reader;
      Length : out Data_Model.Length_Information;
      Error  : in out Errors.Error_Info) is
   begin
      JSON_Event_Readers.Begin_Sequence (Self.Implementation, Length, Error);
   end Begin_Sequence;

   overriding
   procedure Next_Element
     (Self      : in out Reader;
      Available : out Boolean;
      Error     : in out Errors.Error_Info) is
   begin
      JSON_Event_Readers.Next_Element (Self.Implementation, Available, Error);
   end Next_Element;

   overriding
   procedure End_Sequence
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      JSON_Event_Readers.End_Sequence (Self.Implementation, Error);
   end End_Sequence;

   overriding
   procedure Begin_Map
     (Self   : in out Reader;
      Length : out Data_Model.Length_Information;
      Error  : in out Errors.Error_Info) is
   begin
      JSON_Event_Readers.Begin_Map (Self.Implementation, Length, Error);
   end Begin_Map;

   overriding
   procedure Next_Map_Entry
     (Self      : in out Reader;
      Available : out Boolean;
      Error     : in out Errors.Error_Info) is
   begin
      JSON_Event_Readers.Next_Map_Entry
        (Self.Implementation, Available, Error);
   end Next_Map_Entry;

   overriding
   procedure End_Map (Self : in out Reader; Error : in out Errors.Error_Info)
   is
   begin
      JSON_Event_Readers.End_Map (Self.Implementation, Error);
   end End_Map;

   overriding
   procedure Begin_Record
     (Self      : in out Reader;
      Type_Name : String;
      Length    : out Data_Model.Length_Information;
      Error     : in out Errors.Error_Info) is
   begin
      JSON_Event_Readers.Begin_Record
        (Self.Implementation, Type_Name, Length, Error);
   end Begin_Record;

   overriding
   procedure Next_Field
     (Self      : in out Reader;
      Name      : out String;
      Length    : out Natural;
      Available : out Boolean;
      Error     : in out Errors.Error_Info) is
   begin
      JSON_Event_Readers.Next_Field
        (Self.Implementation, Name, Length, Available, Error);
   end Next_Field;

   overriding
   procedure End_Record
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      JSON_Event_Readers.End_Record (Self.Implementation, Error);
   end End_Record;

   overriding
   procedure Read_Enumeration
     (Self         : in out Reader;
      Type_Name    : String;
      Literal_Name : out String;
      Length       : out Natural;
      Error        : in out Errors.Error_Info) is
   begin
      JSON_Event_Readers.Read_Enumeration
        (Self.Implementation, Type_Name, Literal_Name, Length, Error);
   end Read_Enumeration;

   overriding
   procedure Begin_Variant
     (Self             : in out Reader;
      Type_Name        : String;
      Alternative_Name : out String;
      Name_Length      : out Natural;
      Length           : out Data_Model.Length_Information;
      Error            : in out Errors.Error_Info) is
   begin
      JSON_Event_Readers.Begin_Variant
        (Self.Implementation,
         Type_Name,
         Alternative_Name,
         Name_Length,
         Length,
         Error);
   end Begin_Variant;

   overriding
   procedure End_Variant
     (Self : in out Reader; Error : in out Errors.Error_Info) is
   begin
      JSON_Event_Readers.End_Variant (Self.Implementation, Error);
   end End_Variant;

end Flyology_Serde.Deserializers.JSON;
