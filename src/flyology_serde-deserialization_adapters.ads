with Flyology_Serde.Deserialization;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;

--  Statically binds one complete format document to a private transactional
--  candidate. Nested combinators call Deserialize_Value directly and must not
--  call this root transaction.

generic
   type Builder_Type (<>) is limited private;
   Policy : Policies.Decode_Policy := (others => <>);
   with
     procedure Begin_Candidate
       (Target : in out Builder_Type; Error : in out Errors.Error_Info);
   with
     procedure Deserialize_Value
       (From   : in out Deserialization.Deserializer'Class;
        Target : in out Builder_Type;
        Policy : Policies.Decode_Policy;
        Error  : in out Errors.Error_Info);
   with
     procedure Commit_Candidate
       (Target : in out Builder_Type; Error : in out Errors.Error_Info);
   --  Must be nonraising and valid after any attempted Begin_Candidate.
   with procedure Rollback_Candidate (Target : in out Builder_Type);
package Flyology_Serde.Deserialization_Adapters is
   subtype Builder is Builder_Type;

   Configured_Policy : constant Policies.Decode_Policy := Policy;

   procedure Deserialize
     (From   : in out Deserialization.Deserializer'Class;
      Target : in out Builder;
      Error  : in out Errors.Error_Info);
end Flyology_Serde.Deserialization_Adapters;
