with Ada.Streams;

package Flyology_Serde_Generator.Hashing is
   subtype SHA_256_Hex is String (1 .. 64);

   function SHA_256 (Input : String) return SHA_256_Hex;
   function SHA_256 (Input : Ada.Streams.Stream_Element_Array) return SHA_256_Hex;
end Flyology_Serde_Generator.Hashing;
