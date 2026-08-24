with Flyology_Serde_Generator.Diagnostics;
with Flyology_Serde_Generator.Requests;

package Flyology_Serde_Generator.Generation is
   procedure Generate
     (Request    : Flyology_Serde_Generator.Requests.Generation_Request;
      Diagnostic : out Flyology_Serde_Generator.Diagnostics.Diagnostic);
end Flyology_Serde_Generator.Generation;
