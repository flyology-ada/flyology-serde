package Production_Shapes is
   type Position is (First, Middle, Last);
   type Color is (Red, Green, Blue);
   for Color use (Red => 10, Green => 42, Blue => 99);

   type Palette is array (Position) of Color;

   type Packet is record
      Shade   : Color;
      Samples : Palette;
   end record;
end Production_Shapes;
