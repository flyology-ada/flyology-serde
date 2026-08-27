with Flyology_Serde.UTF_8_Validation;
with Flyology_Serde.JSON_Event_Driver_Test_Hooks;

package body Flyology_Serde.JSON_Preflights is
   package Test_Hooks renames Flyology_Serde.JSON_Event_Driver_Test_Hooks;

   use type Errors.Error_Code;

   procedure Note_Classification is
   begin
      if Test_Hooks.Enabled then
         Test_Hooks.Note_Skip_Classification;
      end if;
   end Note_Classification;

   procedure Note_Inspection (End_Exclusive : Natural) is
   begin
      if Test_Hooks.Enabled then
         Test_Hooks.Note_Skip_Inspection (End_Exclusive);
      end if;
   end Note_Inspection;

   procedure Reject
     (Error  : in out Errors.Error_Info;
      Code   : Errors.Error_Code;
      Offset : Natural) is
   begin
      Errors.Fail (Error, Code, Offset, Errors.Byte_Offset);
   end Reject;

   function Hex_Value (Item : Character) return Natural is
   begin
      case Item is
         when '0' .. '9' =>
            return Character'Pos (Item) - Character'Pos ('0');

         when 'A' .. 'F' =>
            return Character'Pos (Item) - Character'Pos ('A') + 10;

         when 'a' .. 'f' =>
            return Character'Pos (Item) - Character'Pos ('a') + 10;

         when others     =>
            return 16;
      end case;
   end Hex_Value;

   procedure Scan_String
     (Source          : String;
      Cursor          : Natural;
      Input_Remaining : Natural;
      Summary         : out String_Summary;
      Error           : in out Errors.Error_Info)
   is
      Position      : Natural := Cursor;
      Segment_Start : Natural;
      Code          : Natural;
      Low           : Natural;
      Candidate     : String_Summary := (others => <>);

      function Has (Count : Natural := 1) return Boolean is
         Inspected : constant Natural := Position - Cursor;
      begin
         Note_Classification;
         if Position <= Source'Length and then Count > Source'Length - Position
         then
            return False;
         elsif Position < Source'Length
           and then (Inspected >= Input_Remaining
                     or else Count > Input_Remaining - Inspected)
         then
            Reject (Error, Errors.Capacity_Exceeded, Cursor + Input_Remaining);
            return False;
         end if;
         if Position < Source'Length and then Count <= Source'Length - Position
         then
            Note_Inspection (Position + Count);
         end if;
         return
           Position <= Source'Length
           and then Count <= Source'Length - Position;
      end Has;

      function Item (Ahead : Natural := 0) return Character
      is (Source (Source'First + Position + Ahead));

      procedure Scan_Hex (Value : out Natural) is
         Digit : Natural;
      begin
         Value := 0;
         if not Has (4) then
            if Error.Code = Errors.No_Error then
               Reject (Error, Errors.Syntax_Error, Position);
            end if;
            return;
         end if;
         for Offset in 0 .. 3 loop
            Digit := Hex_Value (Item (Offset));
            if Digit = 16 then
               Reject (Error, Errors.Syntax_Error, Position + Offset);
               return;
            end if;
            Value := Value * 16 + Digit;
         end loop;
         Position := Position + 4;
      end Scan_Hex;

      procedure Add_Decoded (Count : Natural) is
      begin
         if Candidate.Decoded_Length > Natural'Last - Count then
            Reject (Error, Errors.Capacity_Exceeded, Position);
         else
            Candidate.Decoded_Length := Candidate.Decoded_Length + Count;
         end if;
      end Add_Decoded;

      procedure Validate_Segment (Last : Natural) is
         Valid   : Boolean;
         Invalid : Natural;
      begin
         if Last > Segment_Start then
            Flyology_Serde.UTF_8_Validation.Locate
              (Source
                 (Source'First + Segment_Start .. Source'First + Last - 1),
               Valid,
               Invalid);
         else
            Valid := True;
            Invalid := 0;
         end if;
         if not Valid then
            Reject (Error, Errors.Invalid_Text, Segment_Start + Invalid);
         end if;
      end Validate_Segment;
   begin
      Summary := (others => <>);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Cursor > Source'Length then
         Reject (Error, Errors.Invalid_State, Cursor);
         return;
      elsif not Has or else Item /= '"' then
         if Error.Code = Errors.No_Error then
            Reject (Error, Errors.Syntax_Error, Position);
         end if;
         return;
      end if;
      Position := Position + 1;
      Segment_Start := Position;

      while Error.Code = Errors.No_Error loop
         if not Has then
            if Error.Code = Errors.No_Error then
               Reject (Error, Errors.Syntax_Error, Position);
            end if;
            exit;
         end if;
         case Item is
            when '"'                                     =>
               Validate_Segment (Position);
               exit when Error.Code /= Errors.No_Error;
               Position := Position + 1;
               Candidate.Raw_Length := Position - Cursor;
               Summary := Candidate;
               return;

            when Character'Val (0) .. Character'Val (31) =>
               Reject (Error, Errors.Syntax_Error, Position);

            when '\'                                     =>
               Validate_Segment (Position);
               exit when Error.Code /= Errors.No_Error;
               Position := Position + 1;
               if not Has then
                  if Error.Code = Errors.No_Error then
                     Reject (Error, Errors.Syntax_Error, Position);
                  end if;
                  exit;
               end if;
               case Item is
                  when '"' | '\' | '/' | 'b' | 'f' | 'n' | 'r' | 't' =>
                     Add_Decoded (1);
                     Position := Position + 1;

                  when 'u'                                           =>
                     Position := Position + 1;
                     Scan_Hex (Code);
                     exit when Error.Code /= Errors.No_Error;
                     if Code in 16#D800# .. 16#DBFF# then
                        if not Has (2)
                          or else Item /= '\'
                          or else Item (1) /= 'u'
                        then
                           if Error.Code = Errors.No_Error then
                              Reject (Error, Errors.Invalid_Text, Position);
                           end if;
                           exit;
                        end if;
                        Position := Position + 2;
                        Scan_Hex (Low);
                        exit when Error.Code /= Errors.No_Error;
                        if Low not in 16#DC00# .. 16#DFFF# then
                           Reject (Error, Errors.Invalid_Text, Position - 4);
                           exit;
                        end if;
                        Add_Decoded (4);
                     elsif Code in 16#DC00# .. 16#DFFF# then
                        Reject (Error, Errors.Invalid_Text, Position - 4);
                     elsif Code <= 16#7F# then
                        Add_Decoded (1);
                     elsif Code <= 16#7FF# then
                        Add_Decoded (2);
                     else
                        Add_Decoded (3);
                     end if;

                  when others                                        =>
                     Reject (Error, Errors.Syntax_Error, Position);
               end case;
               Segment_Start := Position;

            when others                                  =>
               Add_Decoded (1);
               Position := Position + 1;
         end case;
      end loop;
   end Scan_String;

   procedure Scan_Number
     (Source          : String;
      Cursor          : Natural;
      Input_Remaining : Natural;
      Summary         : out Number_Summary;
      Error           : in out Errors.Error_Info)
   is
      Position  : Natural := Cursor;
      Candidate : Number_Summary := (others => <>);

      function Has return Boolean is
      begin
         Note_Classification;
         if Position < Source'Length
           and then Position - Cursor >= Input_Remaining
         then
            Reject (Error, Errors.Capacity_Exceeded, Cursor + Input_Remaining);
            return False;
         end if;
         if Position < Source'Length then
            Note_Inspection (Position + 1);
         end if;
         return Position < Source'Length;
      end Has;

      function Item return Character
      is (Source (Source'First + Position));

      procedure Scan_Digits is
      begin
         if not Has or else Item not in '0' .. '9' then
            if Error.Code = Errors.No_Error then
               Reject (Error, Errors.Syntax_Error, Position);
            end if;
            return;
         end if;
         while Has and then Item in '0' .. '9' loop
            Position := Position + 1;
         end loop;
      end Scan_Digits;
   begin
      Summary := (others => <>);
      if Error.Code /= Errors.No_Error then
         return;
      elsif Cursor > Source'Length then
         Reject (Error, Errors.Invalid_State, Cursor);
         return;
      end if;

      if Has and then Item = '-' then
         Candidate.Negative := True;
         Position := Position + 1;
      end if;
      if not Has then
         if Error.Code = Errors.No_Error then
            Reject (Error, Errors.Syntax_Error, Position);
         end if;
         return;
      elsif Item = '0' then
         Position := Position + 1;
         if Has and then Item in '0' .. '9' then
            Reject (Error, Errors.Syntax_Error, Position);
            return;
         end if;
      elsif Item in '1' .. '9' then
         Scan_Digits;
      else
         Reject (Error, Errors.Syntax_Error, Position);
         return;
      end if;
      if Has and then Item = '.' then
         Candidate.Is_Integer := False;
         Position := Position + 1;
         Scan_Digits;
      end if;
      if Error.Code = Errors.No_Error and then Has and then Item in 'e' | 'E'
      then
         Candidate.Is_Integer := False;
         Position := Position + 1;
         if Has and then Item in '+' | '-' then
            Position := Position + 1;
         end if;
         Scan_Digits;
      end if;
      if Error.Code = Errors.No_Error then
         Candidate.Raw_Length := Position - Cursor;
         Summary := Candidate;
      end if;
   end Scan_Number;

   procedure Match_Literal
     (Source          : String;
      Cursor          : Natural;
      Input_Remaining : Natural;
      Literal         : String;
      Error           : in out Errors.Error_Info) is
   begin
      if Error.Code /= Errors.No_Error then
         return;
      elsif Cursor > Source'Length or else Literal'Length = 0 then
         Reject (Error, Errors.Invalid_State, Cursor);
         return;
      elsif Literal'Length > Source'Length - Cursor then
         Note_Classification;
         Reject (Error, Errors.Syntax_Error, Cursor);
         return;
      end if;

      Note_Classification;
      for Offset in 0 .. Literal'Length - 1 loop
         Note_Classification;
         if Offset >= Input_Remaining then
            Reject (Error, Errors.Capacity_Exceeded, Cursor + Offset);
            return;
         end if;
         Note_Inspection (Cursor + Offset + 1);
         if Source (Source'First + Cursor + Offset)
           /= Literal (Literal'First + Offset)
         then
            Reject (Error, Errors.Syntax_Error, Cursor + Offset);
            return;
         end if;
      end loop;
   end Match_Literal;
end Flyology_Serde.JSON_Preflights;
