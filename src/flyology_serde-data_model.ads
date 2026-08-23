--  Logical value kinds exchanged between Ada adapters and format backends.

package Flyology_Serde.Data_Model
  with Pure
is
   type Value_Kind is
     (Null_Value,
      Boolean_Value,
      Signed_Integer_Value,
      Unsigned_Integer_Value,
      Float_Value,
      Text_Value,
      Bytes_Value,
      Sequence_Value,
      Map_Value,
      Record_Value,
      Enumeration_Value,
      Variant_Value);

   type Length_Information is record
      Known  : Boolean := False;
      Length : Natural := 0;
   end record;
end Flyology_Serde.Data_Model;
