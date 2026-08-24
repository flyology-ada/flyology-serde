with Interfaces;

package body Flyology_Serde_Generator.Build_SHA_256.Test_Fixtures is
   use type Interfaces.Unsigned_64;

   procedure Leave_Byte_Capacity
     (Value     : in out Context;
      Remaining : Natural)
   is
      Maximum_Bytes : constant Interfaces.Unsigned_64 := Interfaces.Unsigned_64'Last / 8;
   begin
      Value.Byte_Length := Maximum_Bytes - Interfaces.Unsigned_64 (Remaining);
      Value.Block := [others => 0];
      Value.Block_Length := 0;
      Value.Initialized := True;
      Value.Failed := False;
      Value.Finalized := False;
   end Leave_Byte_Capacity;
end Flyology_Serde_Generator.Build_SHA_256.Test_Fixtures;
