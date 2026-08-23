with Ada.Unchecked_Deallocation;

package body Flyology_Serde.Deserializers.JSON.Copied_Input is
   use type Errors.Error_Code;

   type Source_Access is access String;

   procedure Free is new Ada.Unchecked_Deallocation (String, Source_Access);

   procedure Deserialize
     (Input  : String;
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

      Source := new String'(Input);
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
end Flyology_Serde.Deserializers.JSON.Copied_Input;
