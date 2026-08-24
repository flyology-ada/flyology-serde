with Ada.Streams;
with Flyology_Serde_Generator.Build_SHA_256;
with Flyology_Serde_Generator.Build_SHA_256.Test_Fixtures;

procedure Build_SHA_256_Tests is
   package SHA renames Flyology_Serde_Generator.Build_SHA_256;
   use type Ada.Streams.Stream_Element_Offset;
   use type SHA.Digest;

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   procedure Check
     (Input    : String;
      Expected : SHA.Hex_Digest)
   is
      State   : SHA.Context;
      Result  : SHA.Digest := [others => 0];
      Success : Boolean := False;
   begin
      SHA.Initialize (State);
      SHA.Update (State, Input);
      SHA.Finish (State, Result, Success);
      Require (Success, "SHA-256 finish rejected a valid input");
      Require (SHA.To_Hex (Result) = Expected, "SHA-256 vector mismatch");
   end Check;

   procedure Check_Stream
     (Input    : Ada.Streams.Stream_Element_Array;
      Expected : SHA.Hex_Digest)
   is
      State   : SHA.Context;
      Result  : SHA.Digest := [others => 0];
      Success : Boolean := False;
   begin
      SHA.Initialize (State);
      SHA.Update (State, Input);
      SHA.Finish (State, Result, Success);
      Require (Success, "SHA-256 stream finish rejected a valid input");
      Require (SHA.To_Hex (Result) = Expected, "SHA-256 stream vector mismatch");
   end Check_Stream;

   State     : SHA.Context;
   Result    : SHA.Digest := [others => 0];
   Preserved : SHA.Digest;
   Success   : Boolean := False;
   Fragment  : constant String (7 .. 9) := "abc";
   Stream    : constant Ada.Streams.Stream_Element_Array (-2 .. 0) := [16#61#, 16#62#, 16#63#];
   Binary    : constant Ada.Streams.Stream_Element_Array (4 .. 10) :=
     [16#00#, 16#01#, 16#02#, 16#00#, 16#FF#, 16#80#, 16#41#];
   Null_Stream : constant Ada.Streams.Stream_Element_Array (10 .. 9) := [others => 0];
   Sixty_Five : constant String (1 .. 65) := [others => 'a'];
   Thousand   : constant String (1 .. 1_000) := [others => 'a'];
   Uninitialized        : SHA.Context;
   Uninitialized_Update : SHA.Context;
begin
   Result := [others => 16#A5#];
   Preserved := Result;
   SHA.Finish (Uninitialized, Result, Success);
   Require (not Success, "uninitialized SHA-256 finish unexpectedly succeeded");
   Require (SHA.Is_Failed (Uninitialized), "uninitialized SHA-256 finish was not latched");
   Require (Result = Preserved, "uninitialized SHA-256 finish changed the digest");

   SHA.Update (Uninitialized_Update, "abc");
   Require (SHA.Is_Failed (Uninitialized_Update), "uninitialized SHA-256 update was not latched");
   SHA.Finish (Uninitialized_Update, Result, Success);
   Require (not Success, "uninitialized SHA-256 update permitted finish");
   Require (Result = Preserved, "uninitialized SHA-256 update changed the digest");

   Check ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
   Check ("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
   Check
     ("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
      "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");
   Check
     (String'[1 .. 55 => 'a'],
      "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318");
   Check
     (String'[1 .. 56 => 'a'],
      "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a");
   Check
     (String'[1 .. 63 => 'a'],
      "7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34");
   Check
     (String'[1 .. 64 => 'a'],
      "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb");
   Check
     (Sixty_Five,
      "635361c48bb9eab14198e76ea8ab7f1a41685d6ad62aa9146d301d4f17eb0ae0");
   Check_Stream
     (Binary,
      "04eb7e487be0f404dffe04faebfb3df0df79d644f4f8692eeb0f80bda0a7e1c3");
   Check_Stream
     (Null_Stream,
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");

   SHA.Initialize (State);
   SHA.Update (State, Fragment (7 .. 7));
   SHA.Update (State, Fragment (8 .. 8));
   SHA.Update (State, Fragment (9 .. 9));
   SHA.Finish (State, Result, Success);
   Require (Success, "fragmented SHA-256 finish failed");
   Require
     (SHA.To_Hex (Result) = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
      "fragmented SHA-256 mismatch");

   for Split in 0 .. Sixty_Five'Length loop
      SHA.Initialize (State);
      if Split > 0 then
         SHA.Update (State, Sixty_Five (Sixty_Five'First .. Sixty_Five'First + Split - 1));
      end if;
      if Split < Sixty_Five'Length then
         SHA.Update (State, Sixty_Five (Sixty_Five'First + Split .. Sixty_Five'Last));
      end if;
      SHA.Finish (State, Result, Success);
      Require (Success, "split SHA-256 finish failed");
      Require
        (SHA.To_Hex (Result) = "635361c48bb9eab14198e76ea8ab7f1a41685d6ad62aa9146d301d4f17eb0ae0",
         "split SHA-256 mismatch");
   end loop;

   SHA.Initialize (State);
   for Iteration in 1 .. 1_000 loop
      SHA.Update (State, Thousand);
   end loop;
   SHA.Finish (State, Result, Success);
   Require (Success, "million-byte SHA-256 finish failed");
   Require
     (SHA.To_Hex (Result) = "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0",
      "million-byte SHA-256 mismatch");

   Preserved := Result;
   SHA.Finish (State, Result, Success);
   Require (not Success, "second SHA-256 finish unexpectedly succeeded");
   Require (Result = Preserved, "rejected SHA-256 finish changed the digest");
   SHA.Update (State, "late");
   Require (SHA.Is_Failed (State), "SHA-256 update after finish was not latched");

   SHA.Initialize (State);
   SHA.Update (State, Stream);
   SHA.Finish (State, Result, Success);
   Require (Success, "stream SHA-256 finish failed");
   Require
     (SHA.To_Hex (Result) = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
      "stream SHA-256 mismatch");

   SHA.Initialize (State);
   Flyology_Serde_Generator.Build_SHA_256.Test_Fixtures.Leave_Byte_Capacity (State, 1);
   Preserved := Result;
   SHA.Update (State, "ab");
   Require (SHA.Is_Failed (State), "SHA-256 total-length overflow was not latched");
   SHA.Finish (State, Result, Success);
   Require (not Success, "overflowed SHA-256 context unexpectedly finished");
   Require (Result = Preserved, "overflowed SHA-256 finish changed the digest");

   SHA.Initialize (State);
   Flyology_Serde_Generator.Build_SHA_256.Test_Fixtures.Leave_Byte_Capacity (State, 1);
   SHA.Update (State, "a");
   Require (not SHA.Is_Failed (State), "exact SHA-256 total-length boundary was rejected");
   SHA.Update (State, "b");
   Require (SHA.Is_Failed (State), "byte beyond SHA-256 total-length boundary was accepted");
end Build_SHA_256_Tests;
