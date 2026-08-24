package body Flyology_Serde.Adapters.Bytes is
   use type Ada.Streams.Stream_Element_Offset;
   use type Errors.Error_Code;

   procedure Serialize_Value
     (Item  : Ada.Streams.Stream_Element_Array;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif not Into.Capabilities.Byte_Values then
         Errors.Fail (Error, Errors.Unsupported_Value);
      else
         Into.Put_Bytes (Item, Error);
      end if;
   end Serialize_Value;

   procedure Deserialize_Candidate
     (From   : in out Deserialization.Deserializer'Class;
      Target : in out Ada.Streams.Stream_Element_Array;
      Length : out Natural;
      Error  : in out Errors.Error_Info)
   is
   begin
      Length := 0;
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      declare
         Candidate : Ada.Streams.Stream_Element_Array (Target'Range);
      begin
         From.Read_Bytes (Candidate, Length, Error);
         if Error.Code = Errors.No_Error and then Length > Target'Length then
            Errors.Fail (Error, Errors.Invalid_State);
         elsif Error.Code = Errors.No_Error and then Length > 0 then
            Target
              (Target'First
               .. Target'First
                  + Ada.Streams.Stream_Element_Offset (Length - 1)) :=
              Candidate
                (Candidate'First
                 .. Candidate'First
                    + Ada.Streams.Stream_Element_Offset (Length - 1));
         end if;
      end;
   end Deserialize_Candidate;

   procedure Deserialize_Exact
     (From   : in out Deserialization.Deserializer'Class;
      Target : in out Ada.Streams.Stream_Element_Array;
      Error  : in out Errors.Error_Info)
   is
      Length : Natural := 0;
   begin
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      declare
         Candidate : Ada.Streams.Stream_Element_Array (Target'Range);
      begin
         From.Read_Bytes (Candidate, Length, Error);
         if Error.Code /= Errors.No_Error then
            return;
         elsif Length /= Target'Length then
            Errors.Fail (Error, Errors.Out_Of_Range);
         else
            Target := Candidate;
         end if;
      end;
   end Deserialize_Exact;
end Flyology_Serde.Adapters.Bytes;
