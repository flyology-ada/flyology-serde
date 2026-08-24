with Ada.Streams;
with Ada.Exceptions;
with Flyology_Serde.Adapters.Nullary_Variants;
with Flyology_Serde.Adapters.Signed_Integers;
with Flyology_Serde.Adapters.Variants;
with Flyology_Serde.Deserialization;
with Flyology_Serde.Deserialization_Adapters;
with Flyology_Serde.Deserializers.CBOR;
with Flyology_Serde.Deserializers.JSON;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;
with Flyology_Serde.Serialization;
with Flyology_Serde.Serializers.CBOR;
with Flyology_Serde.Serializers.Counting;
with Flyology_Serde.Serializers.JSON;

procedure Variant_Adapter_Tests is
   package CBOR_Readers renames Flyology_Serde.Deserializers.CBOR;
   package CBOR_Writers renames Flyology_Serde.Serializers.CBOR;
   package Counting renames Flyology_Serde.Serializers.Counting;
   package Errors renames Flyology_Serde.Errors;
   package JSON_Readers renames Flyology_Serde.Deserializers.JSON;
   package JSON_Writers renames Flyology_Serde.Serializers.JSON;
   package Policies renames Flyology_Serde.Policies;
   use type Ada.Streams.Stream_Element_Array;
   use type Errors.Error_Code;
   use type Errors.Path_Element_Kind;

   subtype Bytes is Ada.Streams.Stream_Element_Array;
   package Integers is new Flyology_Serde.Adapters.Signed_Integers (Integer);

   type Alternative is (Empty_Alternative, Point_Alternative, Label_Alternative);
   type Field is (Common_Field, Point_Value_Field, Label_Value_Field);

   type Shape is record
      Kind   : Alternative := Empty_Alternative;
      Common : Integer := 0;
      Value  : Integer := 0;
   end record;

   type Metadata_Mode is
     (Normal_Metadata, Unused_Field, Too_Many_Members, Field_Collision);
   Active_Metadata : Metadata_Mode := Normal_Metadata;

   function Alternative_Name (Item : Alternative) return String is
     (case Item is
         when Empty_Alternative => "empty",
         when Point_Alternative => "point",
         when Label_Alternative => "label");

   function Alternative_Alias_Count (Item : Alternative) return Natural is
     (if Item = Point_Alternative then 1 else 0);

   function Alternative_Alias_Name
     (Item : Alternative; Position : Positive) return String is
     (if Item = Point_Alternative and then Position = 1 then "p" else "");

   function Is_Long_Point_Name (Name : String) return Boolean is
   begin
      if Name'Length /= 70 then
         return False;
      end if;
      for Character of Name loop
         if Character /= 'q' then
            return False;
         end if;
      end loop;
      return True;
   end Is_Long_Point_Name;

   function Matches_Alternative
     (Item : Alternative; Name : String) return Boolean is
     (case Item is
         when Empty_Alternative => Name = "empty",
         when Point_Alternative =>
           Name = "point" or else Name = "p" or else Name = "x"
           or else Is_Long_Point_Name (Name),
         when Label_Alternative => Name = "label" or else Name = "x");

   function Field_Belongs_To
     (Selected : Alternative; Item : Field) return Boolean is
     (case Active_Metadata is
         when Unused_Field =>
           (case Selected is
               when Empty_Alternative => False,
               when Point_Alternative =>
                 Item = Common_Field or else Item = Point_Value_Field,
               when Label_Alternative => Item = Common_Field),
         when Too_Many_Members =>
           (if Selected = Point_Alternative
            then True
            else
              (case Selected is
                  when Empty_Alternative => False,
                  when Point_Alternative => False,
                  when Label_Alternative =>
                    Item = Common_Field or else Item = Label_Value_Field)),
         when Field_Collision =>
           (case Selected is
               when Empty_Alternative => False,
               when Point_Alternative =>
                 Item = Point_Value_Field or else Item = Label_Value_Field,
               when Label_Alternative => Item = Common_Field),
         when Normal_Metadata =>
           (case Selected is
               when Empty_Alternative => False,
               when Point_Alternative =>
                 Item = Common_Field or else Item = Point_Value_Field,
               when Label_Alternative =>
                 Item = Common_Field or else Item = Label_Value_Field));

   function Field_Name (Item : Field) return String is
     (case Item is
         when Common_Field      => "common",
         when Point_Value_Field => "value",
         when Label_Value_Field =>
           (if Active_Metadata = Too_Many_Members
            then "label-value"
            else "value"));

   function Field_Alias_Count (Item : Field) return Natural is
     (if Item = Common_Field then 1 else 0);

   function Field_Alias_Name
     (Item : Field; Position : Positive) return String is
     (if Item = Common_Field and then Position = 1 then "c" else "");

   function Matches_Field (Item : Field; Name : String) return Boolean is
     (case Item is
         when Common_Field      =>
           Name = "common" or else Name = "c" or else Name = "z",
         when Point_Value_Field => Name = "value" or else Name = "z",
         when Label_Value_Field =>
           (if Active_Metadata = Too_Many_Members
            then Name = "label-value"
            else Name = "value"));

   function Select_Alternative (Item : Shape) return Alternative is (Item.Kind);

   procedure Serialize_Field
     (Item        : Shape;
      Selected    : Alternative;
      Which       : Field;
      Into        : in out Flyology_Serde.Serialization.Serializer'Class;
      Error       : in out Errors.Error_Info)
   is
      pragma Unreferenced (Selected);
   begin
      case Which is
         when Common_Field =>
            Integers.Serialize_Value (Item.Common, Into, Error);
         when Point_Value_Field | Label_Value_Field =>
            Integers.Serialize_Value (Item.Value, Into, Error);
      end case;
   end Serialize_Field;

   type Shape_Builder is limited record
      Published       : Shape := (others => <>);
      Candidate       : Shape := (others => <>);
      Selected        : Alternative := Empty_Alternative;
      Has_Common      : Boolean := False;
      Has_Value       : Boolean := False;
      Candidate_Owned : Boolean := False;
      Begin_Owned     : Boolean := False;
      Begin_Acquires  : Natural := 0;
      Begin_Releases  : Natural := 0;
      Acquisitions    : Natural := 0;
      Releases        : Natural := 0;
      Begin_Calls     : Natural := 0;
      Replacements    : Natural := 0;
      Missing_Order   : String (1 .. 2) := [others => ' '];
      Missing_Count   : Natural range 0 .. 2 := 0;
      Finishes        : Natural := 0;
      Active          : Boolean := False;
      Commits         : Natural := 0;
      Rollbacks       : Natural := 0;
   end record;

   Report_Begin : Boolean := False;
   Raise_Begin : Boolean := False;
   Report_Final_Mismatch : Boolean := False;

   procedure Begin_Alternative
     (Target      : in out Shape_Builder;
      Selected    : Alternative;
      Policy      : Policies.Decode_Policy;
      Error       : in out Errors.Error_Info)
   is
      pragma Unreferenced (Policy);
   begin
      Target.Begin_Calls := Target.Begin_Calls + 1;
      Target.Selected := Selected;
      Target.Candidate.Kind := Selected;
      Target.Begin_Owned := True;
      Target.Begin_Acquires := Target.Begin_Acquires + 1;
      if Report_Begin then
         Errors.Fail (Error, Errors.Application_Error);
      elsif Raise_Begin then
         raise Program_Error with "injected variant begin failure";
      end if;
   end Begin_Alternative;

   procedure Deserialize_Field
     (From        : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target      : in out Shape_Builder;
      Selected    : Alternative;
      Which       : Field;
      Replacing   : Boolean;
      Policy      : Policies.Decode_Policy;
      Error       : in out Errors.Error_Info)
   is
      pragma Unreferenced (Policy);
      Value : Integer := 0;
   begin
      pragma Assert (Selected = Target.Selected);
      Integers.Deserialize_Candidate (From, Value, Error);
      if Error.Code /= Errors.No_Error then
         return;
      end if;
      case Which is
         when Common_Field =>
            pragma Assert (Replacing = Target.Has_Common);
            Target.Candidate.Common := Value;
            Target.Has_Common := True;
         when Point_Value_Field | Label_Value_Field =>
            pragma Assert (Replacing = Target.Has_Value);
            if Replacing then
               pragma Assert (Target.Candidate_Owned);
               Target.Releases := Target.Releases + 1;
               Target.Candidate_Owned := False;
            end if;
            Target.Candidate.Value := Value;
            Target.Has_Value := True;
            Target.Acquisitions := Target.Acquisitions + 1;
            Target.Candidate_Owned := True;
      end case;
      if Replacing then
         Target.Replacements := Target.Replacements + 1;
      end if;
   end Deserialize_Field;

   procedure Apply_Missing
     (Target      : in out Shape_Builder;
      Selected    : Alternative;
      Which       : Field;
      Policy      : Policies.Decode_Policy;
      Applied     : out Boolean;
      Error       : in out Errors.Error_Info)
   is
      pragma Unreferenced (Selected, Policy, Error);
   begin
      Target.Missing_Count := Target.Missing_Count + 1;
      Target.Missing_Order (Target.Missing_Count) :=
        (if Which = Common_Field then 'C' else 'V');
      if Which = Common_Field then
         Target.Candidate.Common := 0;
         Target.Has_Common := True;
         Applied := True;
      else
         Applied := False;
      end if;
   end Apply_Missing;

   procedure Finish_Shape
     (Target      : in out Shape_Builder;
      Selected    : Alternative;
      Error       : in out Errors.Error_Info) is
   begin
      if Report_Final_Mismatch or else Target.Candidate.Kind /= Selected then
         Errors.Fail (Error, Errors.Invalid_Value);
      elsif Selected /= Empty_Alternative
        and then (not Target.Has_Common or else not Target.Has_Value)
      then
         Errors.Fail (Error, Errors.Invalid_Value);
      else
         Target.Finishes := Target.Finishes + 1;
      end if;
   end Finish_Shape;

   package Shapes is new
     Flyology_Serde.Adapters.Variants
       (Source_Type                       => Shape,
        Builder_Type                      => Shape_Builder,
        Alternative_Ordinal               => Alternative,
        Field_Ordinal                     => Field,
        Type_Name                         => "Shape",
        Maximum_Type_Name_Length          => 16,
        Maximum_Alternatives              => 3,
        Maximum_Alternative_Name_Length   => 80,
        Maximum_Aliases_Per_Alternative   => 1,
        Maximum_Total_Fields              => 3,
        Maximum_Fields_Per_Alternative    => 2,
        Maximum_Field_Name_Length         => 16,
        Maximum_Aliases_Per_Field         => 1,
        Alternative_Name                  => Alternative_Name,
        Alternative_Alias_Count           => Alternative_Alias_Count,
        Alternative_Alias_Name            => Alternative_Alias_Name,
        Matches_Alternative               => Matches_Alternative,
        Field_Belongs_To                  => Field_Belongs_To,
        Field_Name                        => Field_Name,
        Field_Alias_Count                 => Field_Alias_Count,
        Field_Alias_Name                  => Field_Alias_Name,
        Matches_Field                     => Matches_Field,
        Select_Alternative                => Select_Alternative,
        Serialize_Field                   => Serialize_Field,
        Begin_Alternative                 => Begin_Alternative,
        Deserialize_Field                 => Deserialize_Field,
        Apply_Missing                     => Apply_Missing,
        Finish_Candidate                  => Finish_Shape);

   package Too_Few_Alternative_Shapes is new
     Flyology_Serde.Adapters.Variants
       (Source_Type                       => Shape,
        Builder_Type                      => Shape_Builder,
        Alternative_Ordinal               => Alternative,
        Field_Ordinal                     => Field,
        Type_Name                         => "Shape",
        Maximum_Type_Name_Length          => 16,
        Maximum_Alternatives              => 2,
        Maximum_Alternative_Name_Length   => 80,
        Maximum_Aliases_Per_Alternative   => 1,
        Maximum_Total_Fields              => 3,
        Maximum_Fields_Per_Alternative    => 2,
        Maximum_Field_Name_Length         => 16,
        Maximum_Aliases_Per_Field         => 1,
        Alternative_Name                  => Alternative_Name,
        Alternative_Alias_Count           => Alternative_Alias_Count,
        Alternative_Alias_Name            => Alternative_Alias_Name,
        Matches_Alternative               => Matches_Alternative,
        Field_Belongs_To                  => Field_Belongs_To,
        Field_Name                        => Field_Name,
        Field_Alias_Count                 => Field_Alias_Count,
        Field_Alias_Name                  => Field_Alias_Name,
        Matches_Field                     => Matches_Field,
        Select_Alternative                => Select_Alternative,
        Serialize_Field                   => Serialize_Field,
        Begin_Alternative                 => Begin_Alternative,
        Deserialize_Field                 => Deserialize_Field,
        Apply_Missing                     => Apply_Missing,
        Finish_Candidate                  => Finish_Shape);

   package Too_Few_Field_Shapes is new
     Flyology_Serde.Adapters.Variants
       (Source_Type                       => Shape,
        Builder_Type                      => Shape_Builder,
        Alternative_Ordinal               => Alternative,
        Field_Ordinal                     => Field,
        Type_Name                         => "Shape",
        Maximum_Type_Name_Length          => 16,
        Maximum_Alternatives              => 3,
        Maximum_Alternative_Name_Length   => 80,
        Maximum_Aliases_Per_Alternative   => 1,
        Maximum_Total_Fields              => 2,
        Maximum_Fields_Per_Alternative    => 2,
        Maximum_Field_Name_Length         => 16,
        Maximum_Aliases_Per_Field         => 1,
        Alternative_Name                  => Alternative_Name,
        Alternative_Alias_Count           => Alternative_Alias_Count,
        Alternative_Alias_Name            => Alternative_Alias_Name,
        Matches_Alternative               => Matches_Alternative,
        Field_Belongs_To                  => Field_Belongs_To,
        Field_Name                        => Field_Name,
        Field_Alias_Count                 => Field_Alias_Count,
        Field_Alias_Name                  => Field_Alias_Name,
        Matches_Field                     => Matches_Field,
        Select_Alternative                => Select_Alternative,
        Serialize_Field                   => Serialize_Field,
        Begin_Alternative                 => Begin_Alternative,
        Deserialize_Field                 => Deserialize_Field,
        Apply_Missing                     => Apply_Missing,
        Finish_Candidate                  => Finish_Shape);

   procedure Begin_Shape
     (Target : in out Shape_Builder; Error : in out Errors.Error_Info) is
      pragma Unreferenced (Error);
   begin
      Target.Candidate := (others => <>);
      Target.Selected := Empty_Alternative;
      Target.Has_Common := False;
      Target.Has_Value := False;
      Target.Candidate_Owned := False;
      Target.Begin_Owned := False;
      Target.Begin_Acquires := 0;
      Target.Begin_Releases := 0;
      Target.Acquisitions := 0;
      Target.Releases := 0;
      Target.Begin_Calls := 0;
      Target.Replacements := 0;
      Target.Missing_Order := [others => ' '];
      Target.Missing_Count := 0;
      Target.Finishes := 0;
      Target.Active := True;
   end Begin_Shape;

   procedure Commit_Shape
     (Target : in out Shape_Builder; Error : in out Errors.Error_Info) is
      pragma Unreferenced (Error);
   begin
      Target.Published := Target.Candidate;
      Target.Candidate_Owned := False;
      Target.Begin_Owned := False;
      Target.Active := False;
      Target.Commits := Target.Commits + 1;
   end Commit_Shape;

   procedure Rollback_Shape (Target : in out Shape_Builder) is
   begin
      if Target.Candidate_Owned then
         Target.Releases := Target.Releases + 1;
         Target.Candidate_Owned := False;
      end if;
      if Target.Begin_Owned then
         Target.Begin_Releases := Target.Begin_Releases + 1;
         Target.Begin_Owned := False;
      end if;
      Target.Active := False;
      Target.Rollbacks := Target.Rollbacks + 1;
   end Rollback_Shape;

   Default_Policy : constant Policies.Decode_Policy := (others => <>);
   Ignore_Policy : constant Policies.Decode_Policy :=
     (Limits  => (others => <>),
      Records =>
        (Unknown_Fields   => Policies.Ignore_Unknown,
         Duplicate_Fields => Policies.Reject_Duplicate),
      Maps    => (others => <>));
   Keep_First_Policy : constant Policies.Decode_Policy :=
     (Limits  => (others => <>),
      Records =>
        (Unknown_Fields   => Policies.Reject_Unknown,
         Duplicate_Fields => Policies.Keep_First),
      Maps    => (others => <>));
   Keep_Last_Policy : constant Policies.Decode_Policy :=
     (Limits  => (others => <>),
      Records =>
        (Unknown_Fields   => Policies.Reject_Unknown,
         Duplicate_Fields => Policies.Keep_Last),
      Maps    => (others => <>));

   package Root_Default is new
     Flyology_Serde.Deserialization_Adapters
       (Builder_Type       => Shape_Builder,
        Policy             => Default_Policy,
        Begin_Candidate    => Begin_Shape,
        Deserialize_Value  => Shapes.Deserialize_Candidate,
        Commit_Candidate   => Commit_Shape,
        Rollback_Candidate => Rollback_Shape);
   package Root_Ignore is new
     Flyology_Serde.Deserialization_Adapters
       (Builder_Type       => Shape_Builder,
        Policy             => Ignore_Policy,
        Begin_Candidate    => Begin_Shape,
        Deserialize_Value  => Shapes.Deserialize_Candidate,
        Commit_Candidate   => Commit_Shape,
        Rollback_Candidate => Rollback_Shape);
   package Root_Keep_First is new
     Flyology_Serde.Deserialization_Adapters
       (Builder_Type       => Shape_Builder,
        Policy             => Keep_First_Policy,
        Begin_Candidate    => Begin_Shape,
        Deserialize_Value  => Shapes.Deserialize_Candidate,
        Commit_Candidate   => Commit_Shape,
        Rollback_Candidate => Rollback_Shape);
   package Root_Keep_Last is new
     Flyology_Serde.Deserialization_Adapters
       (Builder_Type       => Shape_Builder,
        Policy             => Keep_Last_Policy,
        Begin_Candidate    => Begin_Shape,
        Deserialize_Value  => Shapes.Deserialize_Candidate,
        Commit_Candidate   => Commit_Shape,
        Rollback_Candidate => Rollback_Shape);

   procedure Decode_JSON
     (Input  : String;
      Root   : not null access procedure
        (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
         Target : in out Shape_Builder;
         Error  : in out Errors.Error_Info);
      Policy : Policies.Decode_Policy;
      Target : in out Shape_Builder;
      Error  : in out Errors.Error_Info)
   is
      Source : aliased constant String := Input;
      From   : JSON_Readers.Reader (Source'Access);
   begin
      From.Initialize (Policy);
      Root (From, Target, Error);
   end Decode_JSON;

   type Signal is (Started, Stopped);
   function Signal_Name (Item : Signal) return String is
     (if Item = Started then "started" else "stopped");
   function Signal_Alias_Count (Item : Signal) return Natural is
      pragma Unreferenced (Item);
   begin
      return 0;
   end Signal_Alias_Count;
   function Signal_Alias_Name
     (Item : Signal; Position : Positive) return String is
      pragma Unreferenced (Item, Position);
   begin
      return "";
   end Signal_Alias_Name;
   function Matches_Signal (Item : Signal; Name : String) return Boolean is
     (Name = Signal_Name (Item));
   function Select_Signal (Item : Signal) return Signal is (Item);

   type Signal_Builder is limited record
      Published   : Signal := Stopped;
      Candidate   : Signal := Stopped;
      Begin_Calls : Natural := 0;
      Finishes    : Natural := 0;
      Rollbacks   : Natural := 0;
   end record;
   procedure Begin_Signal
     (Target      : in out Signal_Builder;
      Selected    : Signal;
      Policy      : Policies.Decode_Policy;
      Error       : in out Errors.Error_Info) is
      pragma Unreferenced (Policy, Error);
   begin
      Target.Candidate := Selected;
      Target.Begin_Calls := Target.Begin_Calls + 1;
   end Begin_Signal;
   procedure Finish_Signal
     (Target   : in out Signal_Builder;
      Selected : Signal;
      Error    : in out Errors.Error_Info) is
      pragma Unreferenced (Selected, Error);
   begin
      Target.Finishes := Target.Finishes + 1;
   end Finish_Signal;
   package Signals is new
     Flyology_Serde.Adapters.Nullary_Variants
       (Source_Type                        => Signal,
        Builder_Type                       => Signal_Builder,
        Alternative_Ordinal                => Signal,
        Type_Name                          => "Signal",
        Maximum_Type_Name_Length           => 16,
        Maximum_Alternatives               => 2,
        Maximum_Alternative_Name_Length    => 16,
        Maximum_Aliases_Per_Alternative    => 0,
        Maximum_Incoming_Field_Name_Length => 16,
        Alternative_Name                   => Signal_Name,
        Alternative_Alias_Count            => Signal_Alias_Count,
        Alternative_Alias_Name             => Signal_Alias_Name,
        Matches_Alternative                => Matches_Signal,
        Select_Alternative                 => Select_Signal,
        Begin_Alternative                  => Begin_Signal,
        Finish_Candidate                   => Finish_Signal);

   procedure Begin_Signal_Root
     (Target : in out Signal_Builder; Error : in out Errors.Error_Info) is
      pragma Unreferenced (Error);
   begin
      Target.Candidate := Target.Published;
      Target.Begin_Calls := 0;
      Target.Finishes := 0;
   end Begin_Signal_Root;

   procedure Read_Signal
     (From   : in out Flyology_Serde.Deserialization.Deserializer'Class;
      Target : in out Signal_Builder;
      Policy : Policies.Decode_Policy;
      Error  : in out Errors.Error_Info) is
   begin
      Signals.Deserialize_Candidate (From, Target, Policy, Error);
   end Read_Signal;

   procedure Commit_Signal
     (Target : in out Signal_Builder; Error : in out Errors.Error_Info) is
      pragma Unreferenced (Error);
   begin
      Target.Published := Target.Candidate;
   end Commit_Signal;

   procedure Rollback_Signal (Target : in out Signal_Builder) is
   begin
      Target.Candidate := Target.Published;
      Target.Rollbacks := Target.Rollbacks + 1;
   end Rollback_Signal;

   package Root_Signal_Default is new
     Flyology_Serde.Deserialization_Adapters
       (Builder_Type       => Signal_Builder,
        Policy             => Default_Policy,
        Begin_Candidate    => Begin_Signal_Root,
        Deserialize_Value  => Read_Signal,
        Commit_Candidate   => Commit_Signal,
        Rollback_Candidate => Rollback_Signal);

   package Root_Signal_Ignore is new
     Flyology_Serde.Deserialization_Adapters
       (Builder_Type       => Signal_Builder,
        Policy             => Ignore_Policy,
        Begin_Candidate    => Begin_Signal_Root,
        Deserialize_Value  => Read_Signal,
        Commit_Candidate   => Commit_Signal,
        Rollback_Candidate => Rollback_Signal);
begin
   --  Canonical finite and zero-field alternatives retain variant envelopes.
   declare
      Into   : JSON_Writers.Bounded_Writer (64);
      Buffer : String (1 .. 64);
      Length : Natural;
      Error  : Errors.Error_Info;
   begin
      Shapes.Serialize_Value
        ((Kind => Point_Alternative, Common => 1, Value => 2), Into, Error);
      Into.Finish_Document (Error);
      Into.Copy_Output (Buffer, Length, Error);
      pragma Assert
        (Buffer (1 .. Length) =
           "[""point"",{""common"":1,""value"":2}]");
      Into.Reset;
      Errors.Reset (Error);
      Shapes.Serialize_Value
        ((Kind => Empty_Alternative, others => <>), Into, Error);
      Into.Finish_Document (Error);
      Into.Copy_Output (Buffer, Length, Error);
      pragma Assert (Buffer (1 .. Length) = "[""empty"",{}]");
   end;

   --  Alias resolution, common fields, and disjoint same-spelled fields.
   declare
      Target : Shape_Builder;
      Error  : Errors.Error_Info;
   begin
      Decode_JSON
        ("[""p"",{""value"":2,""c"":1}]",
         Root_Default.Deserialize'Access,
         Default_Policy,
         Target,
         Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert
        (Target.Published =
           (Kind => Point_Alternative, Common => 1, Value => 2));
      pragma Assert (Target.Begin_Calls = 1 and then Target.Finishes = 1);
   end;

   declare
      Input  : aliased constant Bytes :=
        [16#82#, 16#65#, Character'Pos ('l'), Character'Pos ('a'),
         Character'Pos ('b'), Character'Pos ('e'), Character'Pos ('l'),
         16#A2#, 16#66#, Character'Pos ('c'), Character'Pos ('o'),
         Character'Pos ('m'), Character'Pos ('m'), Character'Pos ('o'),
         Character'Pos ('n'), 1, 16#65#, Character'Pos ('v'),
         Character'Pos ('a'), Character'Pos ('l'), Character'Pos ('u'),
         Character'Pos ('e'), 3];
      From   : CBOR_Readers.Reader (Input'Access);
      Target : Shape_Builder;
      Error  : Errors.Error_Info;
   begin
      From.Initialize (Default_Policy);
      Root_Default.Deserialize (From, Target, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert
        (Target.Published =
           (Kind => Label_Alternative, Common => 1, Value => 3));
   end;

   --  Constructor failures precede builder mutation and retain typed paths.
   declare
      Target : Shape_Builder :=
        (Published => (Kind => Point_Alternative, others => <>), others => <>);
      Error  : Errors.Error_Info;
   begin
      Decode_JSON
        ("[""unknown"",{}]",
         Root_Default.Deserialize'Access,
         Default_Policy,
         Target,
         Error);
      pragma Assert (Error.Code = Errors.Invalid_Value);
      pragma Assert (Target.Begin_Calls = 0 and then Target.Rollbacks = 1);
      pragma Assert (Error.Path (1).Kind = Errors.Alternative_Element);

      Errors.Reset (Error);
      Decode_JSON
        ("[""x"",{}]",
         Root_Default.Deserialize'Access,
         Default_Policy,
         Target,
         Error);
      pragma Assert (Error.Code = Errors.Application_Error);
      pragma Assert (Target.Begin_Calls = 0);

      Errors.Reset (Error);
      Report_Begin := True;
      Decode_JSON
        ("[""point"",{""common"":1,""value"":2}]",
         Root_Default.Deserialize'Access,
         Default_Policy,
         Target,
         Error);
      Report_Begin := False;
      pragma Assert (Error.Code = Errors.Application_Error);
      pragma Assert (Target.Begin_Calls = 1);
      pragma Assert (Target.Rollbacks = 3);
      pragma Assert (Target.Begin_Acquires = 1 and then Target.Begin_Releases = 1);
      pragma Assert (not Target.Begin_Owned);

      Errors.Reset (Error);
      Raise_Begin := True;
      declare
         Raised : Boolean := False;
      begin
         begin
            Decode_JSON
              ("[""point"",{""common"":1,""value"":2}]",
               Root_Default.Deserialize'Access,
               Default_Policy,
               Target,
               Error);
         exception
            when Occurrence : Program_Error =>
               Raised :=
                 Ada.Exceptions.Exception_Message (Occurrence)
                 = "injected variant begin failure";
         end;
         Raise_Begin := False;
         pragma Assert (Raised);
         pragma Assert
           (Target.Begin_Acquires = 1 and then Target.Begin_Releases = 1);
         pragma Assert (not Target.Begin_Owned);
      end;
   end;

   --  Zero-known-field payloads still reject or skip every supplied child.
   declare
      Target : Shape_Builder;
      Error  : Errors.Error_Info;
   begin
      Decode_JSON
        ("[""empty"",{""extra"":{""nested"":[1]}}]",
         Root_Default.Deserialize'Access,
         Default_Policy,
         Target,
         Error);
      pragma Assert (Error.Code = Errors.Unknown_Field);
      pragma Assert (Error.Path (1).Kind = Errors.Alternative_Element);
      pragma Assert (Error.Path (2).Kind = Errors.Field_Element);

      Errors.Reset (Error);
      Decode_JSON
        ("[""empty"",{""extra"":{""nested"":[1]}}]",
         Root_Ignore.Deserialize'Access,
         Ignore_Policy,
         Target,
         Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Target.Published.Kind = Empty_Alternative);
      pragma Assert (Target.Missing_Count = 0);
   end;

   --  Missing runs only for selected membership, under the incoming alias.
   declare
      Target : Shape_Builder;
      Error  : Errors.Error_Info;
   begin
      Decode_JSON
        ("[""p"",{}]",
         Root_Default.Deserialize'Access,
         Default_Policy,
         Target,
         Error);
      pragma Assert (Error.Code = Errors.Missing_Field);
      pragma Assert (Target.Missing_Order = "CV");
      pragma Assert (Error.Path (1).Kind = Errors.Alternative_Element);
      pragma Assert (Error.Path (1).Name (1 .. 1) = "p");
      pragma Assert (Error.Path (2).Name (1 .. 5) = "value");
   end;

   --  Keep-last owns replacement; parse and final failures roll back once.
   declare
      Target : Shape_Builder :=
        (Published => (Kind => Empty_Alternative, others => <>), others => <>);
      Error  : Errors.Error_Info;
   begin
      Decode_JSON
        ("[""point"",{""common"":1,""value"":2,""value"":3}]",
         Root_Keep_First.Deserialize'Access,
         Keep_First_Policy,
         Target,
         Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Target.Published.Value = 2);
      pragma Assert (Target.Acquisitions = 1 and then Target.Releases = 0);

      Errors.Reset (Error);
      Decode_JSON
        ("[""point"",{""common"":1,""value"":2,""value"":3}]",
         Root_Keep_Last.Deserialize'Access,
         Keep_Last_Policy,
         Target,
         Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Target.Published.Value = 3);
      pragma Assert (Target.Acquisitions = 2 and then Target.Releases = 1);

      Errors.Reset (Error);
      Decode_JSON
        ("[""point"",{""common"":1,""value"":2,""value"":false}]",
         Root_Keep_Last.Deserialize'Access,
         Keep_Last_Policy,
         Target,
         Error);
      pragma Assert (Error.Code = Errors.Unexpected_Kind);
      pragma Assert (Target.Acquisitions = 1 and then Target.Releases = 1);
      pragma Assert (not Target.Candidate_Owned);

      Errors.Reset (Error);
      Report_Final_Mismatch := True;
      Decode_JSON
        ("[""point"",{""common"":1,""value"":2}]",
         Root_Default.Deserialize'Access,
         Default_Policy,
         Target,
         Error);
      Report_Final_Mismatch := False;
      pragma Assert (Error.Code = Errors.Invalid_Value);
      pragma Assert (Target.Acquisitions = 1 and then Target.Releases = 1);
   end;

   --  Long accepted constructor spellings use a truncated typed path.
   declare
      Long_Name : constant String (1 .. 70) := [others => 'q'];
      Target    : Shape_Builder;
      Error     : Errors.Error_Info;
   begin
      Decode_JSON
        ("[""" & Long_Name & """,{}]",
         Root_Default.Deserialize'Access,
         Default_Policy,
         Target,
         Error);
      pragma Assert (Error.Code = Errors.Missing_Field);
      pragma Assert (Error.Path (1).Kind = Errors.Alternative_Element);
      pragma Assert (Error.Path (1).Name_Truncated);
      pragma Assert (Error.Path (1).Name_Length = Errors.Maximum_Name_Length);
   end;

   --  Global and per-alternative metadata failures precede events.
   declare
      Into  : Counting.Counter;
      Error : Errors.Error_Info;
   begin
      Active_Metadata := Unused_Field;
      Shapes.Serialize_Value ((others => <>), Into, Error);
      pragma Assert (Error.Code = Errors.Application_Error);
      pragma Assert (Into.Event_Count = 0);

      Errors.Reset (Error);
      Active_Metadata := Too_Many_Members;
      Shapes.Serialize_Value ((others => <>), Into, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
      pragma Assert (Into.Event_Count = 0);
      Active_Metadata := Normal_Metadata;
   end;

   --  All-nullary sums preserve variant rather than enumeration envelopes.
   declare
      Into   : JSON_Writers.Bounded_Writer (32);
      Buffer : String (1 .. 32);
      Length : Natural;
      Error  : Errors.Error_Info;
   begin
      Signals.Serialize_Value (Started, Into, Error);
      Into.Finish_Document (Error);
      Into.Copy_Output (Buffer, Length, Error);
      pragma Assert (Buffer (1 .. Length) = "[""started"",{}]");
   end;

   declare
      Into   : CBOR_Writers.Bounded_Writer (32);
      Buffer : Bytes (1 .. 32);
      Length : Natural;
      Error  : Errors.Error_Info;
   begin
      Signals.Serialize_Value (Started, Into, Error);
      Into.Finish_Document (Error);
      Into.Copy_Output (Buffer, Length, Error);
      pragma Assert
        (Buffer (1 .. Ada.Streams.Stream_Element_Offset (Length))
         = Bytes'
             [16#82#, 16#67#, Character'Pos ('s'), Character'Pos ('t'),
              Character'Pos ('a'), Character'Pos ('r'), Character'Pos ('t'),
              Character'Pos ('e'), Character'Pos ('d'), 16#A0#]);
   end;

   declare
      Input  : aliased constant String := "[""started"",{}]";
      From   : JSON_Readers.Reader (Input'Access);
      Target : Signal_Builder;
      Error  : Errors.Error_Info;
   begin
      From.Initialize (Default_Policy);
      Root_Signal_Default.Deserialize (From, Target, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Target.Published = Started);
      pragma Assert (Target.Begin_Calls = 1 and then Target.Finishes = 1);
   end;

   declare
      Input  : aliased constant String :=
        "[""started"",{""extra"":{""nested"":[1]}}]";
      From   : JSON_Readers.Reader (Input'Access);
      Target : Signal_Builder;
      Error  : Errors.Error_Info;
   begin
      From.Initialize (Default_Policy);
      Root_Signal_Default.Deserialize (From, Target, Error);
      pragma Assert (Error.Code = Errors.Unknown_Field);
      pragma Assert (Error.Path (1).Kind = Errors.Alternative_Element);
      pragma Assert (Error.Path (1).Name (1 .. 7) = "started");
      pragma Assert (Error.Path (2).Kind = Errors.Field_Element);
      pragma Assert (Error.Path (2).Name (1 .. 5) = "extra");

      Errors.Reset (Error);
      From.Reset (Ignore_Policy);
      Root_Signal_Ignore.Deserialize (From, Target, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Target.Published = Started);
   end;

   --  CBOR zero-known-field payloads follow the same reject/skip policy for
   --  both finite and all-nullary variants.
   declare
      Input  : aliased constant Bytes :=
        [16#82#, 16#65#, Character'Pos ('e'), Character'Pos ('m'),
         Character'Pos ('p'), Character'Pos ('t'), Character'Pos ('y'),
         16#A1#, 16#65#, Character'Pos ('e'), Character'Pos ('x'),
         Character'Pos ('t'), Character'Pos ('r'), Character'Pos ('a'),
         16#81#, 1];
      From   : CBOR_Readers.Reader (Input'Access);
      Target : Shape_Builder;
      Error  : Errors.Error_Info;
   begin
      From.Initialize (Default_Policy);
      Root_Default.Deserialize (From, Target, Error);
      pragma Assert (Error.Code = Errors.Unknown_Field);
      pragma Assert (Error.Path (1).Name (1 .. 5) = "empty");
      pragma Assert (Error.Path (2).Name (1 .. 5) = "extra");

      Errors.Reset (Error);
      From.Reset (Ignore_Policy);
      Root_Ignore.Deserialize (From, Target, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Target.Published.Kind = Empty_Alternative);
   end;

   declare
      Input  : aliased constant Bytes :=
        [16#82#, 16#67#, Character'Pos ('s'), Character'Pos ('t'),
         Character'Pos ('a'), Character'Pos ('r'), Character'Pos ('t'),
         Character'Pos ('e'), Character'Pos ('d'), 16#A1#, 16#65#,
         Character'Pos ('e'), Character'Pos ('x'), Character'Pos ('t'),
         Character'Pos ('r'), Character'Pos ('a'), 16#81#, 1];
      From   : CBOR_Readers.Reader (Input'Access);
      Target : Signal_Builder;
      Error  : Errors.Error_Info;
   begin
      From.Initialize (Default_Policy);
      Root_Signal_Default.Deserialize (From, Target, Error);
      pragma Assert (Error.Code = Errors.Unknown_Field);

      Errors.Reset (Error);
      From.Reset (Ignore_Policy);
      Root_Signal_Ignore.Deserialize (From, Target, Error);
      pragma Assert (Error.Code = Errors.No_Error);
      pragma Assert (Target.Published = Started);
   end;

   --  Duplicate rejection and runtime field ambiguity preserve selected paths.
   declare
      Target : Shape_Builder;
      Error  : Errors.Error_Info;
   begin
      Decode_JSON
        ("[""point"",{""common"":1,""value"":2,""value"":3}]",
         Root_Default.Deserialize'Access,
         Default_Policy,
         Target,
         Error);
      pragma Assert (Error.Code = Errors.Duplicate_Field);
      pragma Assert (Error.Path (1).Name (1 .. 5) = "point");
      pragma Assert (Error.Path (2).Name (1 .. 5) = "value");

      Errors.Reset (Error);
      Decode_JSON
        ("[""point"",{""z"":1}]",
         Root_Default.Deserialize'Access,
         Default_Policy,
         Target,
         Error);
      pragma Assert (Error.Code = Errors.Application_Error);
      pragma Assert (Error.Path (2).Name (1 .. 1) = "z");
   end;

   --  Malformed backend envelopes win before constructor/builder semantics.
   declare
      Target : Shape_Builder;
      Error  : Errors.Error_Info;
   begin
      Decode_JSON
        ("[""point"",[]]",
         Root_Default.Deserialize'Access,
         Default_Policy,
         Target,
         Error);
      pragma Assert (Error.Code = Errors.Syntax_Error);
      pragma Assert (Target.Begin_Calls = 0);
   end;

   declare
      Input  : aliased constant Bytes :=
        [16#82#, 16#65#, Character'Pos ('p'), Character'Pos ('o'),
         Character'Pos ('i'), Character'Pos ('n'), Character'Pos ('t'),
         16#80#];
      From   : CBOR_Readers.Reader (Input'Access);
      Target : Shape_Builder;
      Error  : Errors.Error_Info;
   begin
      From.Initialize (Default_Policy);
      Root_Default.Deserialize (From, Target, Error);
      pragma Assert (Error.Code = Errors.Invalid_Value);
      pragma Assert (Target.Begin_Calls = 0);
   end;

   --  Independent table bounds, within-alternative collision, and decode-side
   --  metadata rejection all fail before a format event or input byte.
   declare
      Into  : Counting.Counter;
      Error : Errors.Error_Info;
   begin
      Too_Few_Alternative_Shapes.Serialize_Value ((others => <>), Into, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
      pragma Assert (Into.Event_Count = 0);

      Errors.Reset (Error);
      Too_Few_Field_Shapes.Serialize_Value ((others => <>), Into, Error);
      pragma Assert (Error.Code = Errors.Capacity_Exceeded);
      pragma Assert (Into.Event_Count = 0);

      Errors.Reset (Error);
      Active_Metadata := Field_Collision;
      Shapes.Serialize_Value ((others => <>), Into, Error);
      pragma Assert (Error.Code = Errors.Application_Error);
      pragma Assert (Into.Event_Count = 0);
   end;

   declare
      Input  : aliased constant String := "[""empty"",{}]";
      From   : JSON_Readers.Reader (Input'Access);
      Target : Shape_Builder :=
        (Published => (Kind => Point_Alternative, others => <>), others => <>);
      Error  : Errors.Error_Info;
   begin
      Active_Metadata := Unused_Field;
      From.Initialize (Default_Policy);
      Root_Default.Deserialize (From, Target, Error);
      Active_Metadata := Normal_Metadata;
      pragma Assert (Error.Code = Errors.Application_Error);
      pragma Assert (From.Input_Offset = 0);
      pragma Assert (Error.Input_Offset = 0);
      pragma Assert (Target.Published.Kind = Point_Alternative);
      pragma Assert (Target.Rollbacks = 1 and then Target.Begin_Calls = 0);
   end;
end Variant_Adapter_Tests;
