package body Flyology_Serde_Generator.Diagnostics is
   function Code (Value : Diagnostic) return Error_Code is
     (Value.Error);

   function Stable_Name (Value : Diagnostic) return String is
   begin
      case Value.Error is
         when No_Error =>
            return "ok";
         when Invalid_Arguments =>
            return "generator/invalid-arguments";
         when Input_IO_Error =>
            return "generator/input-io-error";
         when Invalid_Overlay_JSON =>
            return "generator/invalid-overlay-json";
         when Noncanonical_Overlay =>
            return "generator/noncanonical-overlay";
         when Unsupported_Overlay =>
            return "generator/unsupported-overlay";
         when Resource_Exhausted =>
            return "generator/resource-exhausted";
         when Type_IR_API_Unavailable =>
            return "generator/type-ir-ada-api-unavailable";
         when Internal_Error =>
            return "generator/internal-error";
      end case;
   end Stable_Name;

   function Message
     (Value         : Diagnostic;
      Maximum_Bytes : Natural) return String
   is
      Full : constant String :=
        (case Value.Error is
           when No_Error                => "",
           when Invalid_Arguments       => "invalid command line or generation request",
           when Input_IO_Error          => "cannot read a generator input",
           when Invalid_Overlay_JSON    => "overlay is not valid JSON",
           when Noncanonical_Overlay    => "overlay JSON is not in canonical form",
           when Unsupported_Overlay     => "overlay does not satisfy the closed serde v1 contract",
           when Resource_Exhausted      => "configured resource limit exceeded",
           when Type_IR_API_Unavailable =>
             "the reviewed Flyology Type IR Ada checked-document API is not published",
           when Internal_Error          => "generation failed with an unexpected internal exception");
      Last : constant Natural := Natural'Min (Full'Length, Maximum_Bytes);
   begin
      return (if Last = 0 then "" else Full (Full'First .. Full'First + Last - 1));
   end Message;

   procedure Clear (Value : out Diagnostic) is
   begin
      Value := (Error => No_Error);
   end Clear;

   procedure Set
     (Value : out Diagnostic;
      Code  : Error_Code)
   is
   begin
      Value := (Error => Code);
   end Set;
end Flyology_Serde_Generator.Diagnostics;
