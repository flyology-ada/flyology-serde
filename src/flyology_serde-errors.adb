package body Flyology_Serde.Errors is

   procedure Reset (Item : out Error_Info) is
   begin
      Item :=
        (Code                  => No_Error,
         Input_Offset          => 0,
         Offset_Unit           => Unknown_Offset,
         Path_Length           => 0,
         Omitted_Path_Elements => 0,
         Path                  => [others => <>]);
   end Reset;

   procedure Clear_Path (Item : in out Error_Info) is
   begin
      Item.Path_Length := 0;
      Item.Omitted_Path_Elements := 0;
      Item.Path := [others => <>];
   end Clear_Path;

   procedure Fail
     (Item         : in out Error_Info;
      Code         : Error_Code;
      Input_Offset : Natural := 0;
      Offset_Unit  : Input_Offset_Unit := Unknown_Offset) is
   begin
      if Item.Code = No_Error then
         Item.Code := Code;
         Item.Input_Offset := Input_Offset;
         Item.Offset_Unit := Offset_Unit;
      end if;
   end Fail;

   procedure Push_Name
     (Item : in out Error_Info; Name : String; Kind : Path_Element_Kind)
   is
      Retained : constant Natural :=
        Natural'Min (Name'Length, Maximum_Name_Length);
      Target   : Positive;
   begin
      if Item.Code /= No_Error then
         return;
      elsif Item.Omitted_Path_Elements > 0
        and then Item.Path_Length < Maximum_Path_Depth
      then
         Fail (Item, Invalid_State);
         return;
      elsif Item.Path_Length = Maximum_Path_Depth then
         if Item.Omitted_Path_Elements = Natural'Last then
            Fail (Item, Depth_Exceeded);
         else
            Item.Omitted_Path_Elements := Item.Omitted_Path_Elements + 1;
         end if;
         return;
      end if;

      Item.Path_Length := Item.Path_Length + 1;
      Target := Item.Path_Length;
      Item.Path (Target) := (others => <>);
      Item.Path (Target).Kind := Kind;
      Item.Path (Target).Name_Length := Retained;
      Item.Path (Target).Name_Truncated := Retained < Name'Length;
      if Retained > 0 then
         Item.Path (Target).Name (1 .. Retained) :=
           Name (Name'First .. Name'First + (Retained - 1));
      end if;
   end Push_Name;

   procedure Push_Field (Item : in out Error_Info; Name : String) is
   begin
      Push_Name (Item, Name, Field_Element);
   end Push_Field;

   procedure Push_Alternative (Item : in out Error_Info; Name : String) is
   begin
      Push_Name (Item, Name, Alternative_Element);
   end Push_Alternative;

   procedure Push_Index (Item : in out Error_Info; Index : Natural) is
      Target : Positive;
   begin
      if Item.Code /= No_Error then
         return;
      elsif Item.Omitted_Path_Elements > 0
        and then Item.Path_Length < Maximum_Path_Depth
      then
         Fail (Item, Invalid_State);
         return;
      elsif Item.Path_Length = Maximum_Path_Depth then
         if Item.Omitted_Path_Elements = Natural'Last then
            Fail (Item, Depth_Exceeded);
         else
            Item.Omitted_Path_Elements := Item.Omitted_Path_Elements + 1;
         end if;
         return;
      end if;

      Item.Path_Length := Item.Path_Length + 1;
      Target := Item.Path_Length;
      Item.Path (Target) :=
        (Kind => Index_Element, Index => Index, others => <>);
   end Push_Index;

   procedure Pop (Item : in out Error_Info) is
   begin
      if Item.Code /= No_Error then
         return;
      elsif Item.Omitted_Path_Elements > 0
        and then Item.Path_Length < Maximum_Path_Depth
      then
         Fail (Item, Invalid_State);
      elsif Item.Omitted_Path_Elements > 0 then
         Item.Omitted_Path_Elements := Item.Omitted_Path_Elements - 1;
      elsif Item.Path_Length > 0 then
         Item.Path (Item.Path_Length) := (others => <>);
         Item.Path_Length := Item.Path_Length - 1;
      end if;
   end Pop;
end Flyology_Serde.Errors;
