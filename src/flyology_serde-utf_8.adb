with Flyology_Serde.UTF_8_Validation;

package body Flyology_Serde.UTF_8 is
   function Is_Valid (Value : String) return Boolean is
      Valid          : Boolean;
      Invalid_Offset : Natural;
   begin
      Flyology_Serde.UTF_8_Validation.Locate
        (Value, Valid, Invalid_Offset);
      return Valid;
   end Is_Valid;
end Flyology_Serde.UTF_8;
