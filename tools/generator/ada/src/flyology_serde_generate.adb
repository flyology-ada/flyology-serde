with Ada.Command_Line;
with Ada.Text_IO;
with Flyology_Serde_Generator.CLI;
with Flyology_Serde_Generator.Diagnostics;
with Flyology_Serde_Generator.Generation;
with Flyology_Serde_Generator.Requests;

procedure Flyology_Serde_Generate is
   use type Flyology_Serde_Generator.Diagnostics.Error_Code;

   Result     : Flyology_Serde_Generator.CLI.Parse_Result;
   Request    : Flyology_Serde_Generator.Requests.Generation_Request;
   Diagnostic : Flyology_Serde_Generator.Diagnostics.Diagnostic;

   function Diagnostic_Bytes return Natural is
      use type Flyology_Serde_Generator.Requests.Limit_Value;

      Limit : Flyology_Serde_Generator.Requests.Limit_Value;
   begin
      if not Flyology_Serde_Generator.Requests.Has_Limits (Request) then
         return Natural'Last;
      end if;

      Limit :=
        Flyology_Serde_Generator.Requests.Operation_Limits (Request).Maximum_Diagnostic_Bytes;
      return
        (if Limit > Flyology_Serde_Generator.Requests.Limit_Value (Natural'Last)
         then Natural'Last
         else Natural (Limit));
   end Diagnostic_Bytes;

   procedure Report_Failure is
   begin
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      begin
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            Flyology_Serde_Generator.Diagnostics.Stable_Name (Diagnostic) & ": " &
            Flyology_Serde_Generator.Diagnostics.Message (Diagnostic, Diagnostic_Bytes));
      exception
         when others =>
            null;
      end;
   end Report_Failure;
begin
   Flyology_Serde_Generator.CLI.Parse (Result, Request, Diagnostic);

   case Result is
      when Flyology_Serde_Generator.CLI.Help_Requested =>
         Flyology_Serde_Generator.CLI.Print_Usage;
      when Flyology_Serde_Generator.CLI.Version_Requested =>
         Flyology_Serde_Generator.CLI.Print_Version;
      when Flyology_Serde_Generator.CLI.Failed =>
         Report_Failure;
      when Flyology_Serde_Generator.CLI.Parsed =>
         Flyology_Serde_Generator.Generation.Generate (Request, Diagnostic);
         if Flyology_Serde_Generator.Diagnostics.Code (Diagnostic) /=
           Flyology_Serde_Generator.Diagnostics.No_Error
         then
            Report_Failure;
         end if;
   end case;
exception
   when others =>
      if Flyology_Serde_Generator.Diagnostics.Code (Diagnostic) =
        Flyology_Serde_Generator.Diagnostics.No_Error
      then
         Flyology_Serde_Generator.Diagnostics.Set
           (Diagnostic,
            Flyology_Serde_Generator.Diagnostics.Internal_Error);
      end if;
      Report_Failure;
end Flyology_Serde_Generate;
