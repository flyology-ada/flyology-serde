--  Explicit resource and record-handling policy for bounded decoders.

package Flyology_Serde.Policies
  with Pure
is
   type Unknown_Field_Action is (Reject_Unknown, Ignore_Unknown);
   type Duplicate_Field_Action is (Reject_Duplicate, Keep_First, Keep_Last);

   type Decode_Limits is record
      Maximum_Nesting_Depth   : Natural := 32;
      Maximum_Container_Items : Natural := 1_024;
      Maximum_Text_Length     : Natural := 1_048_576;
      Maximum_Byte_Length     : Natural := 1_048_576;
      Maximum_Input_Units     : Natural := 16_777_216;
      Maximum_Logical_Values  : Natural := 1_048_576;
   end record;

   type Record_Policy is record
      Unknown_Fields   : Unknown_Field_Action := Reject_Unknown;
      Duplicate_Fields : Duplicate_Field_Action := Reject_Duplicate;
   end record;

   type Decode_Policy is record
      Limits  : Decode_Limits;
      Records : Record_Policy;
   end record;
end Flyology_Serde.Policies;
