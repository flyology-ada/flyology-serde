--  Internal locating validator shared by serde format backends.

private package Flyology_Serde.UTF_8_Validation
  with Pure
is
   procedure Locate
     (Value          : String;
      Valid          : out Boolean;
      Invalid_Offset : out Natural);
end Flyology_Serde.UTF_8_Validation;
