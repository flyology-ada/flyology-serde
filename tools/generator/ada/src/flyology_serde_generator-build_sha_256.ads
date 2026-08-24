with Ada.Streams;
with Interfaces;

package Flyology_Serde_Generator.Build_SHA_256 is
   subtype Hex_Digest is String (1 .. 64);
   type Digest is array (Natural range 0 .. 31) of Interfaces.Unsigned_8;

   type Context is limited private;

   --  A default-initialized Context is invalid. Initialize is the only reset
   --  operation and must precede Update or Finish.
   procedure Initialize (Value : out Context);

   --  Update accepts arbitrary bounds, including a null array. The cumulative
   --  whole-byte length is limited to Unsigned_64'Last / 8 so the SHA-256 bit
   --  length is exact. Invalid state or length overflow latches failure.
   procedure Update
     (Value : in out Context;
      Data  : String);

   procedure Update
     (Value : in out Context;
      Data  : Ada.Streams.Stream_Element_Array);

   --  Finish is one-shot. Success publishes the complete digest into Into.
   --  Every rejection preserves Into. A second Finish rejects; an Update
   --  after successful Finish latches failure.
   procedure Finish
     (Value   : in out Context;
      Into    : in out Digest;
      Success : out Boolean);

   function To_Hex (Value : Digest) return Hex_Digest;
   function Is_Failed (Value : Context) return Boolean;

private
   type Word_Array is array (Natural range 0 .. 7) of Interfaces.Unsigned_32;
   type Block_Array is array (Natural range 0 .. 63) of Interfaces.Unsigned_8;

   type Context is limited record
      State        : Word_Array := [others => 0];
      Block        : Block_Array := [others => 0];
      Block_Length : Natural range 0 .. 64 := 0;
      Byte_Length  : Interfaces.Unsigned_64 := 0;
      Initialized  : Boolean := False;
      Failed       : Boolean := False;
      Finalized    : Boolean := False;
   end record;
end Flyology_Serde_Generator.Build_SHA_256;
