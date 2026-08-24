with Flyology_Serde.UTF_8;

package body Flyology_Serde.Serializers.Counting is
   use type Data_Model.Float_64_Category;
   use type Errors.Error_Code;

   overriding
   function Capabilities (Self : Counter) return Data_Model.Format_Capabilities
   is (Self.Profile);

   overriding
   function State (Self : Counter) return Serialization.Serializer_State
   is
     (if Self.Failed then Serialization.Poisoned
      elsif Self.Finalized then Serialization.Finished
      elsif Self.Root_Written then Serialization.Active
      else Serialization.Ready);

   procedure Reset
     (Self         : in out Counter;
      Capabilities : Data_Model.Format_Capabilities;
      Limits       : Serialization.Serialization_Limits) is
   begin
      Self.Profile := Capabilities;
      Self.Limits := Limits;
      Self.Events := 0;
      Self.Depth := 0;
      Self.Stack := [others => <>];
      Self.Root_Written := False;
      Self.Failed := False;
      Self.Finalized := False;
   end Reset;

   overriding
   procedure Finish_Document
     (Self : in out Counter; Error : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.Failed or else Self.Finalized then
         Errors.Fail (Error, Errors.Invalid_State);
      elsif not Self.Root_Written or else Self.Depth /= 0
      then
         Self.Failed := True;
         Self.Finalized := False;
         Errors.Fail (Error, Errors.Invalid_State);
      else
         Self.Finalized := True;
      end if;
   end Finish_Document;

   overriding
   procedure Abort_Document (Self : in out Counter) is
   begin
      Self.Depth := 0;
      Self.Stack := [others => <>];
      Self.Finalized := False;
      Self.Failed := True;
   exception
      when others =>
         null;
   end Abort_Document;

   procedure Reject
     (Self  : in out Counter;
      Code  : Errors.Error_Code;
      Error : in out Errors.Error_Info) is
   begin
      if Error.Code = Errors.No_Error then
         Self.Failed := True;
         Self.Finalized := False;
         Errors.Fail (Error, Code);
      end if;
   end Reject;

   procedure Guard_Event
     (Self    : in out Counter;
      Allowed : out Boolean;
      Error   : in out Errors.Error_Info) is
   begin
      Allowed := False;
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.Failed or else Self.Finalized then
         Errors.Fail (Error, Errors.Invalid_State);
      else
         Allowed := True;
      end if;
   end Guard_Event;

   procedure Note_Event
     (Self : in out Counter; Error : in out Errors.Error_Info) is
   begin
      if Error.Code = Errors.No_Error then
         if Self.Events = Natural'Last
           or else Self.Events >= Self.Limits.Maximum_Logical_Events
         then
            Reject (Self, Errors.Capacity_Exceeded, Error);
         else
            Self.Events := Self.Events + 1;
         end if;
      end if;
   end Note_Event;

   procedure Note_Value
     (Self    : in out Counter;
      Error   : in out Errors.Error_Info;
      Is_Text : Boolean := False) is
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.Failed or else Self.Finalized then
         Errors.Fail (Error, Errors.Invalid_State);
         return;
      elsif Self.Depth = 0 then
         if Self.Root_Written then
            Reject (Self, Errors.Invalid_State, Error);
            return;
         end if;
         Self.Root_Written := True;
      elsif Self.Depth > 0 then
         if Self.Stack (Self.Depth).Kind = Map_Container
           and then not Self.Stack (Self.Depth).Waiting_For_Value
           and then not Self.Profile.Arbitrary_Map_Keys
           and then not Is_Text
         then
            Reject (Self, Errors.Unsupported_Value, Error);
            return;
         end if;
         case Self.Stack (Self.Depth).Kind is
            when Optional_Container | Sequence_Container =>
               if Self.Stack (Self.Depth).Expected_Known
                 and then Self.Stack (Self.Depth).Observed_Items
                          = Self.Stack (Self.Depth).Expected_Items
               then
                  Reject (Self, Errors.Invalid_State, Error);
                  return;
               elsif Self.Stack (Self.Depth).Observed_Items = Natural'Last
                 or else Self.Stack (Self.Depth).Observed_Items
                           >= Self.Limits.Maximum_Container_Items
               then
                  Reject (Self, Errors.Capacity_Exceeded, Error);
                  return;
               end if;
               Self.Stack (Self.Depth).Observed_Items :=
                 Self.Stack (Self.Depth).Observed_Items + 1;

            when Map_Container                           =>
               if not Self.Stack (Self.Depth).Waiting_For_Value
                 and then Self.Stack (Self.Depth).Observed_Items
                           >= Self.Limits.Maximum_Container_Items
               then
                  Reject (Self, Errors.Capacity_Exceeded, Error);
                  return;
               end if;
               if not Self.Stack (Self.Depth).Waiting_For_Value
                 and then Self.Stack (Self.Depth).Expected_Known
                 and then Self.Stack (Self.Depth).Observed_Items
                          = Self.Stack (Self.Depth).Expected_Items
               then
                  Reject (Self, Errors.Invalid_State, Error);
                  return;
               end if;
               if Self.Stack (Self.Depth).Waiting_For_Value then
                  if Self.Stack (Self.Depth).Observed_Items = Natural'Last then
                     Reject (Self, Errors.Capacity_Exceeded, Error);
                     return;
                  end if;
                  Self.Stack (Self.Depth).Observed_Items :=
                    Self.Stack (Self.Depth).Observed_Items + 1;
               end if;
               Self.Stack (Self.Depth).Waiting_For_Value :=
                 not Self.Stack (Self.Depth).Waiting_For_Value;

            when Record_Container | Variant_Container    =>
               if not Self.Stack (Self.Depth).Waiting_For_Value then
                  Reject (Self, Errors.Invalid_State, Error);
                  return;
               elsif Self.Stack (Self.Depth).Observed_Items = Natural'Last then
                  Reject (Self, Errors.Capacity_Exceeded, Error);
                  return;
               end if;
               Self.Stack (Self.Depth).Waiting_For_Value := False;
               Self.Stack (Self.Depth).Observed_Items :=
                 Self.Stack (Self.Depth).Observed_Items + 1;
         end case;
      end if;

      Note_Event (Self, Error);
   end Note_Value;

   procedure Open_Container
     (Self   : in out Counter;
      Kind   : Container_Kind;
      Length : Data_Model.Length_Information;
      Error  : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.Depth = Policies.Maximum_Supported_Nesting
        or else Self.Depth >= Self.Limits.Maximum_Nesting_Depth
      then
         Reject (Self, Errors.Depth_Exceeded, Error);
         return;
      elsif Length.Known
        and then Length.Length > Self.Limits.Maximum_Container_Items
      then
         Reject (Self, Errors.Capacity_Exceeded, Error);
         return;
      end if;

      Note_Value (Self, Error);
      if Error.Code = Errors.No_Error then
         Self.Depth := Self.Depth + 1;
         Self.Stack (Self.Depth) :=
           (Kind           => Kind,
            Expected_Known => Length.Known,
            Expected_Items => Length.Length,
            others         => <>);
      end if;
   end Open_Container;

   procedure Close_Container
     (Self  : in out Counter;
      Kind  : Container_Kind;
      Error : in out Errors.Error_Info)
   is
      Allowed : Boolean;
   begin
      Guard_Event (Self, Allowed, Error);
      if not Allowed then
         return;
      elsif Self.Depth = 0 then
         Reject (Self, Errors.Invalid_State, Error);
      elsif Self.Stack (Self.Depth).Kind /= Kind then
         Reject (Self, Errors.Invalid_State, Error);
      elsif Self.Stack (Self.Depth).Waiting_For_Value then
         Reject (Self, Errors.Invalid_State, Error);
      elsif Self.Stack (Self.Depth).Expected_Known
        and then Self.Stack (Self.Depth).Observed_Items
                 /= Self.Stack (Self.Depth).Expected_Items
      then
         Reject (Self, Errors.Invalid_State, Error);
      else
         Self.Stack (Self.Depth) := (others => <>);
         Self.Depth := Self.Depth - 1;
         Note_Event (Self, Error);
      end if;
   end Close_Container;

   function Event_Count (Self : Counter) return Natural
   is (Self.Events);

   function Container_Depth (Self : Counter) return Natural
   is (Self.Depth);

   overriding
   procedure Put_Null (Self : in out Counter; Error : in out Errors.Error_Info)
   is
   begin
      Note_Value (Self, Error);
   end Put_Null;

   overriding
   procedure Put_Boolean
     (Self : in out Counter; Value : Boolean; Error : in out Errors.Error_Info)
   is
      pragma Unreferenced (Value);
   begin
      Note_Value (Self, Error);
   end Put_Boolean;

   overriding
   procedure Put_Signed
     (Self  : in out Counter;
      Value : Interfaces.Integer_64;
      Error : in out Errors.Error_Info)
   is
      pragma Unreferenced (Value);
   begin
      Note_Value (Self, Error);
   end Put_Signed;

   overriding
   procedure Put_Unsigned
     (Self  : in out Counter;
      Value : Interfaces.Unsigned_64;
      Error : in out Errors.Error_Info)
   is
      pragma Unreferenced (Value);
   begin
      Note_Value (Self, Error);
   end Put_Unsigned;

   overriding
   procedure Put_Float_64
     (Self  : in out Counter;
      Value : Data_Model.Float_64_Value;
      Error : in out Errors.Error_Info)
   is
      Allowed : Boolean;
   begin
      Guard_Event (Self, Allowed, Error);
      if not Allowed then
         return;
      elsif Data_Model.Category (Value) /= Data_Model.Finite_Float
        and then not Self.Profile.Nonfinite_Float_64
      then
         Reject (Self, Errors.Unsupported_Value, Error);
      elsif Data_Model.Is_Negative_Zero (Value)
        and then not Self.Profile.Signed_Float_Zero
      then
         Reject (Self, Errors.Unsupported_Value, Error);
      else
         Note_Value (Self, Error);
      end if;
   end Put_Float_64;

   overriding
   procedure Put_Text
     (Self : in out Counter; Value : String; Error : in out Errors.Error_Info)
   is
      Allowed : Boolean;
   begin
      Guard_Event (Self, Allowed, Error);
      if not Allowed then
         return;
      elsif not Flyology_Serde.UTF_8.Is_Valid (Value) then
         Reject (Self, Errors.Invalid_Text, Error);
      elsif Value'Length > Self.Limits.Maximum_Text_Length then
         Reject (Self, Errors.Capacity_Exceeded, Error);
      else
         Note_Value (Self, Error, Is_Text => True);
      end if;
   end Put_Text;

   overriding
   procedure Put_Bytes
     (Self  : in out Counter;
      Value : Ada.Streams.Stream_Element_Array;
      Error : in out Errors.Error_Info)
   is
      Allowed : Boolean;
   begin
      Guard_Event (Self, Allowed, Error);
      if not Allowed then
         return;
      elsif not Self.Profile.Byte_Values then
         Reject (Self, Errors.Unsupported_Value, Error);
      elsif Value'Length > Self.Limits.Maximum_Byte_Length then
         Reject (Self, Errors.Capacity_Exceeded, Error);
      else
         Note_Value (Self, Error);
      end if;
   end Put_Bytes;

   overriding
   procedure Begin_Optional
     (Self    : in out Counter;
      Present : Boolean;
      Error   : in out Errors.Error_Info) is
      Allowed : Boolean;
   begin
      Guard_Event (Self, Allowed, Error);
      if not Allowed then
         return;
      elsif not Self.Profile.Lossless_Optionals then
         Reject (Self, Errors.Unsupported_Value, Error);
      else
         Open_Container
           (Self,
            Optional_Container,
            Data_Model.Known_Length (Boolean'Pos (Present)),
            Error);
      end if;
   end Begin_Optional;

   overriding
   procedure End_Optional
     (Self : in out Counter; Error : in out Errors.Error_Info) is
   begin
      Close_Container (Self, Optional_Container, Error);
   end End_Optional;

   overriding
   procedure Begin_Sequence
     (Self   : in out Counter;
      Length : Data_Model.Length_Information;
      Error  : in out Errors.Error_Info) is
      Allowed : Boolean;
   begin
      Guard_Event (Self, Allowed, Error);
      if not Allowed then
         return;
      elsif not Length.Known and then not Self.Profile.Unknown_Container_Lengths then
         Reject (Self, Errors.Unsupported_Value, Error);
      else
         Open_Container (Self, Sequence_Container, Length, Error);
      end if;
   end Begin_Sequence;

   overriding
   procedure End_Sequence
     (Self : in out Counter; Error : in out Errors.Error_Info) is
   begin
      Close_Container (Self, Sequence_Container, Error);
   end End_Sequence;

   overriding
   procedure Begin_Map
     (Self   : in out Counter;
      Length : Data_Model.Length_Information;
      Error  : in out Errors.Error_Info) is
      Allowed : Boolean;
   begin
      Guard_Event (Self, Allowed, Error);
      if not Allowed then
         return;
      elsif not Length.Known and then not Self.Profile.Unknown_Container_Lengths then
         Reject (Self, Errors.Unsupported_Value, Error);
      else
         Open_Container (Self, Map_Container, Length, Error);
      end if;
   end Begin_Map;

   overriding
   procedure End_Map (Self : in out Counter; Error : in out Errors.Error_Info)
   is
   begin
      Close_Container (Self, Map_Container, Error);
   end End_Map;

   overriding
   procedure Begin_Record
     (Self        : in out Counter;
      Type_Name   : String;
      Field_Count : Natural;
      Error       : in out Errors.Error_Info)
   is
      Allowed : Boolean;
   begin
      Guard_Event (Self, Allowed, Error);
      if not Allowed then
         return;
      elsif not Flyology_Serde.UTF_8.Is_Valid (Type_Name) then
         Reject (Self, Errors.Invalid_Text, Error);
      elsif Type_Name'Length > Self.Limits.Maximum_Text_Length then
         Reject (Self, Errors.Capacity_Exceeded, Error);
      else
         Open_Container
           (Self,
            Record_Container,
            (Known => True, Length => Field_Count),
            Error);
      end if;
   end Begin_Record;

   overriding
   procedure Put_Field
     (Self : in out Counter; Name : String; Error : in out Errors.Error_Info)
   is
      Allowed : Boolean;
   begin
      Guard_Event (Self, Allowed, Error);
      if not Allowed then
         return;
      elsif not Flyology_Serde.UTF_8.Is_Valid (Name) then
         Reject (Self, Errors.Invalid_Text, Error);
      elsif Name'Length > Self.Limits.Maximum_Text_Length then
         Reject (Self, Errors.Capacity_Exceeded, Error);
      elsif Self.Depth = 0
        or else Self.Stack (Self.Depth).Kind
                not in Record_Container | Variant_Container
        or else Self.Stack (Self.Depth).Waiting_For_Value
        or else (Self.Stack (Self.Depth).Expected_Known
                 and then Self.Stack (Self.Depth).Observed_Items
                          = Self.Stack (Self.Depth).Expected_Items)
      then
         Reject (Self, Errors.Invalid_State, Error);
         return;
      end if;

      Self.Stack (Self.Depth).Waiting_For_Value := True;
      Note_Event (Self, Error);
   end Put_Field;

   overriding
   procedure End_Record
     (Self : in out Counter; Error : in out Errors.Error_Info) is
   begin
      Close_Container (Self, Record_Container, Error);
   end End_Record;

   overriding
   procedure Put_Enumeration
     (Self         : in out Counter;
      Type_Name    : String;
      Literal_Name : String;
      Error        : in out Errors.Error_Info)
   is
      Allowed : Boolean;
   begin
      Guard_Event (Self, Allowed, Error);
      if not Allowed then
         return;
      elsif not Flyology_Serde.UTF_8.Is_Valid (Type_Name)
        or else not Flyology_Serde.UTF_8.Is_Valid (Literal_Name)
      then
         Reject (Self, Errors.Invalid_Text, Error);
      elsif Type_Name'Length > Self.Limits.Maximum_Text_Length
        or else Literal_Name'Length > Self.Limits.Maximum_Text_Length
      then
         Reject (Self, Errors.Capacity_Exceeded, Error);
      else
         Note_Value (Self, Error, Is_Text => True);
      end if;
   end Put_Enumeration;

   overriding
   procedure Begin_Variant
     (Self             : in out Counter;
      Type_Name        : String;
      Alternative_Name : String;
      Field_Count      : Natural;
      Error            : in out Errors.Error_Info)
   is
      Allowed : Boolean;
   begin
      Guard_Event (Self, Allowed, Error);
      if not Allowed then
         return;
      elsif not Flyology_Serde.UTF_8.Is_Valid (Type_Name)
        or else not Flyology_Serde.UTF_8.Is_Valid (Alternative_Name)
      then
         Reject (Self, Errors.Invalid_Text, Error);
      elsif Type_Name'Length > Self.Limits.Maximum_Text_Length
        or else Alternative_Name'Length > Self.Limits.Maximum_Text_Length
      then
         Reject (Self, Errors.Capacity_Exceeded, Error);
      else
         Open_Container
           (Self,
            Variant_Container,
            (Known => True, Length => Field_Count),
            Error);
      end if;
   end Begin_Variant;

   overriding
   procedure End_Variant
     (Self : in out Counter; Error : in out Errors.Error_Info) is
   begin
      Close_Container (Self, Variant_Container, Error);
   end End_Variant;
end Flyology_Serde.Serializers.Counting;
