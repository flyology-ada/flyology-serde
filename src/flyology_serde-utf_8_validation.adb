package body Flyology_Serde.UTF_8_Validation is
   procedure Locate
     (Value          : String;
      Valid          : out Boolean;
      Invalid_Offset : out Natural)
   is
      Offset    : Natural := 0;
      First     : Natural;
      Second    : Natural;
      Remaining : Natural;

      function Byte (Ahead : Natural := 0) return Natural is
        (Character'Pos (Value (Value'First + Offset + Ahead)));

      function Continuation (Ahead : Natural) return Boolean is
        (Byte (Ahead) in 16#80# .. 16#BF#);

      procedure Reject (At_Offset : Natural) is
      begin
         Valid := False;
         Invalid_Offset := At_Offset;
      end Reject;
   begin
      while Offset < Value'Length loop
         First := Byte;
         Remaining := Value'Length - Offset;
         if First <= 16#7F# then
            Offset := Offset + 1;
         elsif First in 16#C2# .. 16#DF# then
            if Remaining < 2 then
               Reject (Offset);
               return;
            elsif not Continuation (1) then
               Reject (Offset + 1);
               return;
            end if;
            Offset := Offset + 2;
         elsif First in 16#E0# .. 16#EF# then
            if Remaining < 2 then
               Reject (Offset);
               return;
            end if;
            Second := Byte (1);
            if (First = 16#E0# and then Second not in 16#A0# .. 16#BF#)
              or else (First = 16#ED# and then Second not in 16#80# .. 16#9F#)
              or else (First not in 16#E0# | 16#ED#
                       and then Second not in 16#80# .. 16#BF#)
            then
               Reject (Offset + 1);
               return;
            elsif Remaining < 3 then
               Reject (Offset);
               return;
            elsif not Continuation (2) then
               Reject (Offset + 2);
               return;
            end if;
            Offset := Offset + 3;
         elsif First in 16#F0# .. 16#F4# then
            if Remaining < 2 then
               Reject (Offset);
               return;
            end if;
            Second := Byte (1);
            if (First = 16#F0# and then Second not in 16#90# .. 16#BF#)
              or else (First = 16#F4# and then Second not in 16#80# .. 16#8F#)
              or else (First in 16#F1# .. 16#F3#
                       and then Second not in 16#80# .. 16#BF#)
            then
               Reject (Offset + 1);
               return;
            elsif Remaining < 3 then
               Reject (Offset);
               return;
            elsif not Continuation (2) then
               Reject (Offset + 2);
               return;
            elsif Remaining < 4 then
               Reject (Offset);
               return;
            elsif not Continuation (3) then
               Reject (Offset + 3);
               return;
            end if;
            Offset := Offset + 4;
         else
            Reject (Offset);
            return;
         end if;
      end loop;
      Valid := True;
      Invalid_Offset := Value'Length;
   end Locate;
end Flyology_Serde.UTF_8_Validation;
