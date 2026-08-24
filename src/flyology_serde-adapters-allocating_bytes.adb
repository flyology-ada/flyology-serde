with Ada.Containers;
with Ada.Unchecked_Deallocation;

package body Flyology_Serde.Adapters.Allocating_Bytes is
   use type Ada.Streams.Stream_Element_Offset;
   use type Errors.Error_Code;

   subtype Byte_Array is Ada.Streams.Stream_Element_Array;
   type Scratch_Access is access Byte_Array;

   procedure Free is new Ada.Unchecked_Deallocation (Byte_Array, Scratch_Access);

   procedure Serialize_Value
     (Item  : Value;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
      Scratch : Scratch_Access := null;
      Last    : Ada.Streams.Stream_Element_Offset := 0;
      Cursor  : Ada.Streams.Stream_Element_Offset := 0;
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif not Into.Capabilities.Byte_Values then
         Errors.Fail (Error, Errors.Unsupported_Value);
         return;
      elsif Ada.Containers.Count_Type'Pos (Item.Length)
        > Ada.Streams.Stream_Element_Offset'Pos
            (Ada.Streams.Stream_Element_Offset'Last)
          - Ada.Streams.Stream_Element_Offset'Pos (0)
      then
         Errors.Fail (Error, Errors.Capacity_Exceeded);
         return;
      end if;
      Last := Ada.Streams.Stream_Element_Offset (Item.Length);
      Scratch := new Byte_Array (1 .. Last);
      for Element of Item loop
         Cursor := Cursor + 1;
         Scratch (Cursor) := Element;
      end loop;
      Into.Put_Bytes (Scratch.all, Error);
      Free (Scratch);
   exception
      when others =>
         Free (Scratch);
         raise;
   end Serialize_Value;

   procedure Deserialize_Candidate
     (From   : in out Deserialization.Deserializer'Class;
      Target : in out Value;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info) is
      Scratch : Scratch_Access := null;
      Length  : Natural := 0;
   begin
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Target := Byte_Vectors.Empty_Vector;
      Scratch := new Byte_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Policy.Limits.Maximum_Byte_Length));
      From.Read_Bytes (Scratch.all, Length, Error);
      if Error.Code = Errors.No_Error then
         begin
            Target.Reserve_Capacity (Ada.Containers.Count_Type (Length));
            for Index in 1 .. Length loop
               Target.Append (Scratch (Ada.Streams.Stream_Element_Offset (Index)));
            end loop;
         exception
            when Ada.Containers.Capacity_Error =>
               Target.Clear;
               Errors.Fail (Error, Errors.Capacity_Exceeded);
         end;
      end if;
      Free (Scratch);
   exception
      when others =>
         Free (Scratch);
         raise;
   end Deserialize_Candidate;
end Flyology_Serde.Adapters.Allocating_Bytes;
