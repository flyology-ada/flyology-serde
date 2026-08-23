package body Flyology_Serde.Serializers.Counting is
   use type Errors.Error_Code;

   procedure Note_Event
     (Self : in out Counter; Error : in out Errors.Error_Info) is
   begin
      if Error.Code = Errors.No_Error then
         if Self.Events = Natural'Last then
            Errors.Fail (Error, Errors.Capacity_Exceeded);
         else
            Self.Events := Self.Events + 1;
         end if;
      end if;
   end Note_Event;

   procedure Note_Value
     (Self : in out Counter; Error : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.Depth > 0 then
         case Self.Stack (Self.Depth).Kind is
            when Sequence_Container                   =>
               if Self.Stack (Self.Depth).Expected_Known
                 and then Self.Stack (Self.Depth).Observed_Items
                          = Self.Stack (Self.Depth).Expected_Items
               then
                  Errors.Fail (Error, Errors.Invalid_State);
                  return;
               elsif Self.Stack (Self.Depth).Observed_Items = Natural'Last then
                  Errors.Fail (Error, Errors.Capacity_Exceeded);
                  return;
               end if;
               Self.Stack (Self.Depth).Observed_Items :=
                 Self.Stack (Self.Depth).Observed_Items + 1;

            when Map_Container                        =>
               if not Self.Stack (Self.Depth).Waiting_For_Value
                 and then Self.Stack (Self.Depth).Expected_Known
                 and then Self.Stack (Self.Depth).Observed_Items
                          = Self.Stack (Self.Depth).Expected_Items
               then
                  Errors.Fail (Error, Errors.Invalid_State);
                  return;
               end if;
               if Self.Stack (Self.Depth).Waiting_For_Value then
                  if Self.Stack (Self.Depth).Observed_Items = Natural'Last then
                     Errors.Fail (Error, Errors.Capacity_Exceeded);
                     return;
                  end if;
                  Self.Stack (Self.Depth).Observed_Items :=
                    Self.Stack (Self.Depth).Observed_Items + 1;
               end if;
               Self.Stack (Self.Depth).Waiting_For_Value :=
                 not Self.Stack (Self.Depth).Waiting_For_Value;

            when Record_Container | Variant_Container =>
               if not Self.Stack (Self.Depth).Waiting_For_Value then
                  Errors.Fail (Error, Errors.Invalid_State);
                  return;
               elsif Self.Stack (Self.Depth).Observed_Items = Natural'Last then
                  Errors.Fail (Error, Errors.Capacity_Exceeded);
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
      elsif Self.Depth = Errors.Maximum_Path_Depth then
         Errors.Fail (Error, Errors.Depth_Exceeded);
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
      Error : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.Depth = 0 then
         Errors.Fail (Error, Errors.Invalid_State);
      elsif Self.Stack (Self.Depth).Kind /= Kind then
         Errors.Fail (Error, Errors.Invalid_State);
      elsif Self.Stack (Self.Depth).Waiting_For_Value then
         Errors.Fail (Error, Errors.Invalid_State);
      elsif Self.Stack (Self.Depth).Expected_Known
        and then Self.Stack (Self.Depth).Observed_Items
                 /= Self.Stack (Self.Depth).Expected_Items
      then
         Errors.Fail (Error, Errors.Invalid_State);
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
      Value : Interfaces.IEEE_Float_64;
      Error : in out Errors.Error_Info)
   is
      pragma Unreferenced (Value);
   begin
      Note_Value (Self, Error);
   end Put_Float_64;

   overriding
   procedure Put_Text
     (Self : in out Counter; Value : String; Error : in out Errors.Error_Info)
   is
      pragma Unreferenced (Value);
   begin
      Note_Value (Self, Error);
   end Put_Text;

   overriding
   procedure Put_Bytes
     (Self  : in out Counter;
      Value : Ada.Streams.Stream_Element_Array;
      Error : in out Errors.Error_Info)
   is
      pragma Unreferenced (Value);
   begin
      Note_Value (Self, Error);
   end Put_Bytes;

   overriding
   procedure Begin_Sequence
     (Self   : in out Counter;
      Length : Data_Model.Length_Information;
      Error  : in out Errors.Error_Info) is
   begin
      Open_Container (Self, Sequence_Container, Length, Error);
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
   begin
      Open_Container (Self, Map_Container, Length, Error);
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
      pragma Unreferenced (Type_Name);
   begin
      Open_Container
        (Self,
         Record_Container,
         (Known => True, Length => Field_Count),
         Error);
   end Begin_Record;

   overriding
   procedure Put_Field
     (Self : in out Counter; Name : String; Error : in out Errors.Error_Info)
   is
      pragma Unreferenced (Name);
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif Self.Depth = 0
        or else Self.Stack (Self.Depth).Kind
                not in Record_Container | Variant_Container
        or else Self.Stack (Self.Depth).Waiting_For_Value
        or else (Self.Stack (Self.Depth).Expected_Known
                 and then Self.Stack (Self.Depth).Observed_Items
                          = Self.Stack (Self.Depth).Expected_Items)
      then
         Errors.Fail (Error, Errors.Invalid_State);
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
      pragma Unreferenced (Type_Name, Literal_Name);
   begin
      Note_Value (Self, Error);
   end Put_Enumeration;

   overriding
   procedure Begin_Variant
     (Self             : in out Counter;
      Type_Name        : String;
      Alternative_Name : String;
      Field_Count      : Natural;
      Error            : in out Errors.Error_Info)
   is
      pragma Unreferenced (Type_Name, Alternative_Name);
   begin
      Open_Container
        (Self,
         Variant_Container,
         (Known => True, Length => Field_Count),
         Error);
   end Begin_Variant;

   overriding
   procedure End_Variant
     (Self : in out Counter; Error : in out Errors.Error_Info) is
   begin
      Close_Container (Self, Variant_Container, Error);
   end End_Variant;
end Flyology_Serde.Serializers.Counting;
