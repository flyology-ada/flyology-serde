--  Allocation-free validation for UTF-8 carried by logical text events.

package Flyology_Serde.UTF_8
  with Pure
is
   function Is_Valid (Value : String) return Boolean;
end Flyology_Serde.UTF_8;
