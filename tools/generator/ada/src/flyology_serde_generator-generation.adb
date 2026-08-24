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
         declare
            Path_Length : Natural := 0;
         begin
            Flyology_Serde_Generator.Requests.Read_Overlay_Path_Length
              (Request, Budget, Path_Length, Diagnostic);
            if Code (Diagnostic) = No_Error then
               declare
                  Path    : String (1 .. Path_Length);
                  Written : Natural := 0;
                  Copied  : Boolean := False;
               begin
                  Flyology_Serde_Generator.Requests.Copy_Overlay_Path
                    (Request, Budget, Path, Written, Copied, Diagnostic);
                  if Code (Diagnostic) = No_Error and then Copied and then Written = Path_Length then
                     Flyology_Serde_Generator.Overlays.Load_Checked
                       (Path, Budget, Overlay, Diagnostic);
                  elsif Code (Diagnostic) = No_Error then
                     Flyology_Serde_Generator.Requests.Poison (Budget);
                     Set (Diagnostic, Internal_Error);
                  end if;
               end;
            end if;
         end;
         if Code (Diagnostic) = No_Error then
            declare
               Fixture_Only : Boolean := False;
            begin
               Flyology_Serde_Generator.Overlays.Read_Fixture_Only
                 (Overlay, Budget, Fixture_Only, Diagnostic);
               if Code (Diagnostic) = No_Error and then not Fixture_Only then
                  Set (Diagnostic, Unsupported_Overlay);
               elsif Code (Diagnostic) = No_Error then
                  Set (Diagnostic, Type_IR_API_Unavailable);
               end if;
            end;
         end if;
      end if;
   exception
      when Storage_Error =>
         Flyology_Serde_Generator.Requests.Poison (Budget);
         if Code (Diagnostic) = No_Error then
            Set (Diagnostic, Resource_Exhausted);
         end if;
      when others =>
         Flyology_Serde_Generator.Requests.Poison (Budget);
         if Code (Diagnostic) = No_Error then
            Set (Diagnostic, Internal_Error);
         end if;
   end Generate;
end Flyology_Serde_Generator.Generation;
