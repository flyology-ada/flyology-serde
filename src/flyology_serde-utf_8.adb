package body Flyology_Serde.UTF_8 is
   function Is_Continuation (Item : Character) return Boolean
   is (Character'Pos (Item) in 16#80# .. 16#BF#);

   function Is_Valid (Value : String) return Boolean is
      Position  : Integer := Value'First;
      Last      : constant Integer := Value'Last;
      First     : Natural;
      Second    : Natural;
      Remaining : Natural;
   begin
      while Position <= Last loop
         First := Character'Pos (Value (Position));
         Remaining := Natural (Last - Position);
         if First <= 16#7F# then
            Position := Position + 1;
         elsif First in 16#C2# .. 16#DF# then
            if Remaining < 1 or else not Is_Continuation (Value (Position + 1))
            then
               return False;
            end if;
            Position := Position + 2;
         elsif First in 16#E0# .. 16#EF# then
            if Remaining < 2 or else not Is_Continuation (Value (Position + 2))
            then
               return False;
            end if;
            Second := Character'Pos (Value (Position + 1));
            if (First = 16#E0# and then Second not in 16#A0# .. 16#BF#)
              or else (First = 16#ED# and then Second not in 16#80# .. 16#9F#)
              or else (First not in 16#E0# | 16#ED#
                       and then Second not in 16#80# .. 16#BF#)
            then
               return False;
            end if;
            Position := Position + 3;
         elsif First in 16#F0# .. 16#F4# then
            if Remaining < 3
              or else not Is_Continuation (Value (Position + 2))
              or else not Is_Continuation (Value (Position + 3))
            then
               return False;
            end if;
            Second := Character'Pos (Value (Position + 1));
            if (First = 16#F0# and then Second not in 16#90# .. 16#BF#)
              or else (First = 16#F4# and then Second not in 16#80# .. 16#8F#)
              or else (First in 16#F1# .. 16#F3#
                       and then Second not in 16#80# .. 16#BF#)
            then
               return False;
            end if;
            Position := Position + 4;
         else
            return False;
         end if;
      end loop;
      return True;
   end Is_Valid;
end Flyology_Serde.UTF_8;
