with Flyology_Serde.Deserialization;
with Flyology_Serde.Errors;
with Flyology_Serde.Serialization;

generic
   type Value_Type is (<>);
   Type_Name                       : String;
   Maximum_Type_Name_Length        : Positive;
   Maximum_Literals                : Positive;
   Maximum_Literal_Name_Length     : Positive;
   Maximum_Aliases_Per_Literal     : Natural;
   with function Primary_Name (Value : Value_Type) return String;
   with function Alias_Count (Value : Value_Type) return Natural;
   with
     function Alias_Name
       (Value : Value_Type; Position : Positive) return String;
   with
     function Matches_Literal
       (Value : Value_Type; Name : String) return Boolean;
package Flyology_Serde.Adapters.Enumerations is
   --  Metadata functions must remain stable and nonallocating for one
   --  operation. Every declared name must be valid UTF-8, unique, and match
   --  only its own literal. Handwritten matchers may accept extra names;
   --  runtime ambiguity is rejected.
   procedure Serialize_Value
     (Item  : Value_Type;
      Into  : in out Serialization.Serializer'Class;
      Error : in out Errors.Error_Info);

   --  Target changes only after one literal resolves successfully. Literal
   --  content is not added to the structural error path. The enclosing root
   --  abort attaches the backend's current next-unread offset when needed.
   procedure Deserialize_Candidate
     (From   : in out Deserialization.Deserializer'Class;
      Target : in out Value_Type;
      Error  : in out Errors.Error_Info);
end Flyology_Serde.Adapters.Enumerations;
