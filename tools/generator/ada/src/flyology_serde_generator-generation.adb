with Flyology_Serde_Generator.Overlays;

package body Flyology_Serde_Generator.Generation is
   procedure Generate
     (Request    : Flyology_Serde_Generator.Requests.Generation_Request;
      Diagnostic : out Flyology_Serde_Generator.Diagnostics.Diagnostic)
   is
      use Flyology_Serde_Generator.Diagnostics;
      Overlay : Flyology_Serde_Generator.Overlays.Overlay_Document;
      Budget  : Flyology_Serde_Generator.Requests.Operation_Budget;
   begin
      Clear (Diagnostic);
      if not Flyology_Serde_Generator.Requests.Is_Valid (Request)
        or else not Flyology_Serde_Generator.Requests.Is_Fixture_Request (Request)
      then
         Set (Diagnostic, Invalid_Arguments);
      else
         Flyology_Serde_Generator.Requests.Start_Budget
           (Flyology_Serde_Generator.Requests.Operation_Limits (Request), Budget);
         Flyology_Serde_Generator.Overlays.Load_Checked
           (Flyology_Serde_Generator.Requests.Overlay_Path (Request),
            Budget,
            Overlay,
            Diagnostic);
         if Code (Diagnostic) = No_Error then
            if not Flyology_Serde_Generator.Overlays.Is_Fixture_Only (Overlay) then
               Set (Diagnostic, Unsupported_Overlay);
            else
               Set (Diagnostic, Type_IR_API_Unavailable);
            end if;
         end if;
      end if;
   exception
      when others =>
         if Code (Diagnostic) = No_Error then
            Set (Diagnostic, Internal_Error);
         end if;
   end Generate;
end Flyology_Serde_Generator.Generation;
