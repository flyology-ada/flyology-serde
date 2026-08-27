with Flyology.Reflection.Value_Views;
with Flyology_Serde.Serialization;
with Flyology_Serde_Reflection.Serialization_Adapters;
with Typed_Generated_Subjects;
with Typed_Generated_Subjects.Reflection.Values;

procedure Mismatched_Observe is
   package Serialization renames Flyology_Serde.Serialization;
   package Subjects renames Typed_Generated_Subjects;
   package Views renames Typed_Generated_Subjects.Reflection.Values;

   Limits : constant Serialization.Serialization_Limits :=
     (Maximum_Nesting_Depth   => 1,
      Maximum_Container_Items => 1,
      Maximum_Text_Length     => 1,
      Maximum_Byte_Length     => 1,
      Maximum_Logical_Events  => 1);

   procedure Observe_Shade
     (Item  : Subjects.Shade;
      Using : in out Flyology.Reflection.Value_Views.Value_Consumer'Class)
   renames Views.Observe;

   package Invalid is new
     Flyology_Serde_Reflection.Serialization_Adapters
       (Source_Type => Subjects.Offset,
        Limits      => Limits,
        Observe     => Observe_Shade);
begin
   null;
end Mismatched_Observe;
