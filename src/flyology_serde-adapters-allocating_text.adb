with Ada.Unchecked_Deallocation;
with Flyology_Serde.Adapters.Text;

package body Flyology_Serde.Adapters.Allocating_Text is
   use type Errors.Error_Code;

   type Scratch_Access is access String;

   procedure Free is new Ada.Unchecked_Deallocation (String, Scratch_Access);

   procedure Serialize_Value
     (Item  : Value;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      Text.Serialize_Value
        (Ada.Strings.Unbounded.To_String (Item), Into, Error);
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
      Target := Ada.Strings.Unbounded.Null_Unbounded_String;

      Scratch := new String (1 .. Policy.Limits.Maximum_Text_Length);
      From.Read_Text (Scratch.all, Length, Error);
      if Error.Code = Errors.No_Error then
         Target := Ada.Strings.Unbounded.To_Unbounded_String
           (Scratch (1 .. Length));
      end if;
      Free (Scratch);
   exception
      when others =>
         Free (Scratch);
         raise;
   end Deserialize_Candidate;
end Flyology_Serde.Adapters.Allocating_Text;
