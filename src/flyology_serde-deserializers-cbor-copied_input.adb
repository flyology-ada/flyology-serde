with Ada.Unchecked_Deallocation;

package body Flyology_Serde.Deserializers.CBOR.Copied_Input is
   use type Errors.Error_Code;

   subtype Byte_Array is Ada.Streams.Stream_Element_Array;
   type Source_Access is access Byte_Array;

   procedure Free is new Ada.Unchecked_Deallocation (Byte_Array, Source_Access);

   procedure Deserialize
     (Input  : Byte_Array;
      Target : in out Adapter.Builder;
      Error  : in out Errors.Error_Info) is
      Source : Source_Access := null;
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif Input'Length > Adapter.Configured_Policy.Limits.Maximum_Input_Units then
         Errors.Fail
           (Error,
            Errors.Capacity_Exceeded,
            Adapter.Configured_Policy.Limits.Maximum_Input_Units,
            Errors.Byte_Offset);
         return;
      end if;

      Source := new Byte_Array'(Input);
      declare
         From : Reader (Source.all'Access);
      begin
         From.Initialize (Adapter.Configured_Policy);
         Adapter.Deserialize (From, Target, Error);
      end;
      Free (Source);
   exception
      when others =>
         Free (Source);
         raise;
   end Deserialize;
end Flyology_Serde.Deserializers.CBOR.Copied_Input;
