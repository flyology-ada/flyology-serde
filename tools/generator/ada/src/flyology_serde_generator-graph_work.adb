package body Flyology_Serde_Generator.Graph_Work is
   procedure Compute
     (Members       : Natural;
      Text_Bytes    : Natural;
      Work          : out Natural;
      Representable : out Boolean)
   is
      Multiplier : Natural;
      Factor     : Natural;
   begin
      Work := 0;
      Representable := False;
      if Members = Natural'Last or else Text_Bytes > Natural'Last - Members - 1
      then
         return;
      end if;

      Multiplier := Members + 1;
      Factor := Text_Bytes + Members + 1;
      if Multiplier > (Natural'Last - 1) / Factor then
         return;
      end if;

      Work := 1 + Multiplier * Factor;
      Representable := True;
   end Compute;
end Flyology_Serde_Generator.Graph_Work;
