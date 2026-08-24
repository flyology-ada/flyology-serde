with Flyology_Serde_Generator.Diagnostics;
with Flyology_Serde_Generator.Requests;

package Flyology_Serde_Generator.CLI is
   type Parse_Result is (Parsed, Help_Requested, Version_Requested, Failed);

   procedure Parse
     (Result     : out Parse_Result;
      Request    : out Flyology_Serde_Generator.Requests.Generation_Request;
      Diagnostic : out Flyology_Serde_Generator.Diagnostics.Diagnostic);

   procedure Print_Usage;
   procedure Print_Version;
end Flyology_Serde_Generator.CLI;
