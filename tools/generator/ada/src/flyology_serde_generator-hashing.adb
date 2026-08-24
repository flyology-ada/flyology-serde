with SHA2;

package body Flyology_Serde_Generator.Hashing is
   Hex_Digits : constant String := "0123456789abcdef";

   function To_Hex (Value : SHA2.SHA_256.Digest) return SHA_256_Hex is
      Result : SHA_256_Hex;
      Offset : Positive := Result'First;
   begin
      for Byte of Value loop
         Result (Offset) := Hex_Digits (Natural (Byte) / 16 + 1);
         Result (Offset + 1) := Hex_Digits (Natural (Byte) mod 16 + 1);
         Offset := Offset + 2;
      end loop;
      return Result;
   end To_Hex;

   function SHA_256 (Input : String) return SHA_256_Hex is
   begin
      return To_Hex (SHA2.SHA_256.Hash (Input));
   end SHA_256;

   function SHA_256 (Input : Ada.Streams.Stream_Element_Array) return SHA_256_Hex is
   begin
      return To_Hex (SHA2.SHA_256.Hash (Input));
   end SHA_256;
end Flyology_Serde_Generator.Hashing;
