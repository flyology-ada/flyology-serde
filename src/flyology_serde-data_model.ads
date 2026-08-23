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
      Optional_Value,
      Sequence_Value,
      Map_Value,
      Record_Value,
      Enumeration_Value,
      Variant_Value);

   type Length_Information is record
      Known  : Boolean := False;
      Length : Natural := 0;
   end record;

   Unknown_Length : constant Length_Information :=
     (Known => False, Length => 0);

   function Known_Length (Length : Natural) return Length_Information
   is ((Known => True, Length => Length));

   type Format_Capabilities is record
      Unknown_Container_Lengths : Boolean := False;
      Byte_Values               : Boolean := False;
      Nonfinite_Float_64        : Boolean := False;
      Signed_Float_Zero         : Boolean := False;
      Arbitrary_Map_Keys        : Boolean := False;
      Nested_Optionals          : Boolean := False;
   end record;

   All_Capabilities : constant Format_Capabilities := (others => True);
end Flyology_Serde.Data_Model;
