package body Flyology_Serde.Deserialization_Adapters is
   use type Errors.Error_Code;

   procedure Deserialize
     (From   : in out Deserialization.Deserializer'Class;
      Target : in out Builder;
      Error  : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error then
         return;
      end if;

      Begin_Candidate (Target, Error);
      if Error.Code = Errors.No_Error then
         Deserialize_Value (From, Target, Policy, Error);
      end if;
      if Error.Code = Errors.No_Error then
         From.Finish_Document (Error);
      end if;
      if Error.Code = Errors.No_Error then
         Commit_Candidate (Target, Error);
      end if;
      if Error.Code /= Errors.No_Error then
         From.Abort_Document (Error);
         Rollback_Candidate (Target);
      end if;
   exception
      when others =>
         From.Abort_Document (Error);
         Rollback_Candidate (Target);
         Errors.Clear_Path (Error);
         raise;
   end Deserialize;
end Flyology_Serde.Deserialization_Adapters;
