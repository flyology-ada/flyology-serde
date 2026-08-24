package Flyology_Serde_Generator.Diagnostics is
   type Error_Code is
     (No_Error,
      Invalid_Arguments,
      Input_IO_Error,
      Invalid_Overlay_JSON,
      Noncanonical_Overlay,
      Unsupported_Overlay,
      Unsupported_Lowered_Model,
      Resource_Exhausted,
      Type_IR_API_Unavailable,
      Internal_Error);

   type Diagnostic is private;

   function Code (Value : Diagnostic) return Error_Code;
   function Stable_Name (Value : Diagnostic) return String;

   function Message
     (Value         : Diagnostic;
      Maximum_Bytes : Natural) return String;

   procedure Clear (Value : out Diagnostic);

   procedure Set
     (Value : out Diagnostic;
      Code  : Error_Code);

private
   type Diagnostic is record
      Error : Error_Code := No_Error;
   end record;
end Flyology_Serde_Generator.Diagnostics;
