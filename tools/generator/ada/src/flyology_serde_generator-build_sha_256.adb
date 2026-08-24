package body Flyology_Serde_Generator.Build_SHA_256 is
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;

   Round_Constants : constant array (Natural range 0 .. 63) of Interfaces.Unsigned_32 :=
     [16#428A_2F98#, 16#7137_4491#, 16#B5C0_FBCF#, 16#E9B5_DBA5#,
      16#3956_C25B#, 16#59F1_11F1#, 16#923F_82A4#, 16#AB1C_5ED5#,
      16#D807_AA98#, 16#1283_5B01#, 16#2431_85BE#, 16#550C_7DC3#,
      16#72BE_5D74#, 16#80DE_B1FE#, 16#9BDC_06A7#, 16#C19B_F174#,
      16#E49B_69C1#, 16#EFBE_4786#, 16#0FC1_9DC6#, 16#240C_A1CC#,
      16#2DE9_2C6F#, 16#4A74_84AA#, 16#5CB0_A9DC#, 16#76F9_88DA#,
      16#983E_5152#, 16#A831_C66D#, 16#B003_27C8#, 16#BF59_7FC7#,
      16#C6E0_0BF3#, 16#D5A7_9147#, 16#06CA_6351#, 16#1429_2967#,
      16#27B7_0A85#, 16#2E1B_2138#, 16#4D2C_6DFC#, 16#5338_0D13#,
      16#650A_7354#, 16#766A_0ABB#, 16#81C2_C92E#, 16#9272_2C85#,
      16#A2BF_E8A1#, 16#A81A_664B#, 16#C24B_8B70#, 16#C76C_51A3#,
      16#D192_E819#, 16#D699_0624#, 16#F40E_3585#, 16#106A_A070#,
      16#19A4_C116#, 16#1E37_6C08#, 16#2748_774C#, 16#34B0_BCB5#,
      16#391C_0CB3#, 16#4ED8_AA4A#, 16#5B9C_CA4F#, 16#682E_6FF3#,
      16#748F_82EE#, 16#78A5_636F#, 16#84C8_7814#, 16#8CC7_0208#,
      16#90BE_FFFA#, 16#A450_6CEB#, 16#BEF9_A3F7#, 16#C671_78F2#];

   function Choice
     (X, Y, Z : Interfaces.Unsigned_32) return Interfaces.Unsigned_32
   is ((X and Y) xor ((not X) and Z));

   function Majority
     (X, Y, Z : Interfaces.Unsigned_32) return Interfaces.Unsigned_32
   is ((X and Y) xor (X and Z) xor (Y and Z));

   function Big_Sigma_0 (Value : Interfaces.Unsigned_32) return Interfaces.Unsigned_32 is
     (Interfaces.Rotate_Right (Value, 2)
      xor Interfaces.Rotate_Right (Value, 13)
      xor Interfaces.Rotate_Right (Value, 22));

   function Big_Sigma_1 (Value : Interfaces.Unsigned_32) return Interfaces.Unsigned_32 is
     (Interfaces.Rotate_Right (Value, 6)
      xor Interfaces.Rotate_Right (Value, 11)
      xor Interfaces.Rotate_Right (Value, 25));

   function Small_Sigma_0 (Value : Interfaces.Unsigned_32) return Interfaces.Unsigned_32 is
     (Interfaces.Rotate_Right (Value, 7)
      xor Interfaces.Rotate_Right (Value, 18)
      xor Interfaces.Shift_Right (Value, 3));

   function Small_Sigma_1 (Value : Interfaces.Unsigned_32) return Interfaces.Unsigned_32 is
     (Interfaces.Rotate_Right (Value, 17)
      xor Interfaces.Rotate_Right (Value, 19)
      xor Interfaces.Shift_Right (Value, 10));

   procedure Transform (Value : in out Context) is
      Schedule : array (Natural range 0 .. 63) of Interfaces.Unsigned_32 := [others => 0];
      A        : Interfaces.Unsigned_32 := Value.State (0);
      B        : Interfaces.Unsigned_32 := Value.State (1);
      C        : Interfaces.Unsigned_32 := Value.State (2);
      D        : Interfaces.Unsigned_32 := Value.State (3);
      E        : Interfaces.Unsigned_32 := Value.State (4);
      F        : Interfaces.Unsigned_32 := Value.State (5);
      G        : Interfaces.Unsigned_32 := Value.State (6);
      H        : Interfaces.Unsigned_32 := Value.State (7);
      First    : Interfaces.Unsigned_32;
      Second   : Interfaces.Unsigned_32;
   begin
      for Index in 0 .. 15 loop
         declare
            Offset : constant Natural := Index * 4;
         begin
            Schedule (Index) :=
              Interfaces.Shift_Left (Interfaces.Unsigned_32 (Value.Block (Offset)), 24)
              or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Value.Block (Offset + 1)), 16)
              or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Value.Block (Offset + 2)), 8)
              or Interfaces.Unsigned_32 (Value.Block (Offset + 3));
         end;
      end loop;

      for Index in 16 .. 63 loop
         Schedule (Index) :=
           Small_Sigma_1 (Schedule (Index - 2)) + Schedule (Index - 7)
           + Small_Sigma_0 (Schedule (Index - 15)) + Schedule (Index - 16);
      end loop;

      for Index in Schedule'Range loop
         First := H + Big_Sigma_1 (E) + Choice (E, F, G) + Round_Constants (Index) + Schedule (Index);
         Second := Big_Sigma_0 (A) + Majority (A, B, C);
         H := G;
         G := F;
         F := E;
         E := D + First;
         D := C;
         C := B;
         B := A;
         A := First + Second;
      end loop;

      Value.State (0) := Value.State (0) + A;
      Value.State (1) := Value.State (1) + B;
      Value.State (2) := Value.State (2) + C;
      Value.State (3) := Value.State (3) + D;
      Value.State (4) := Value.State (4) + E;
      Value.State (5) := Value.State (5) + F;
      Value.State (6) := Value.State (6) + G;
      Value.State (7) := Value.State (7) + H;
      Value.Block := [others => 0];
      Value.Block_Length := 0;
   end Transform;

   procedure Initialize (Value : out Context) is
   begin
      Value.State :=
        [16#6A09_E667#, 16#BB67_AE85#, 16#3C6E_F372#, 16#A54F_F53A#,
         16#510E_527F#, 16#9B05_688C#, 16#1F83_D9AB#, 16#5BE0_CD19#];
      Value.Block := [others => 0];
      Value.Block_Length := 0;
      Value.Byte_Length := 0;
      Value.Initialized := True;
      Value.Failed := False;
      Value.Finalized := False;
   end Initialize;

   procedure Append_Byte
     (Value : in out Context;
      Item  : Interfaces.Unsigned_8)
   is
   begin
      Value.Block (Value.Block_Length) := Item;
      Value.Block_Length := Value.Block_Length + 1;
      if Value.Block_Length = Value.Block'Length then
         Transform (Value);
      end if;
   end Append_Byte;

   function Can_Accept
     (Value : Context;
      Count : Natural) return Boolean
   is
      Maximum_Bytes : constant Interfaces.Unsigned_64 := Interfaces.Unsigned_64'Last / 8;
   begin
      return
        Value.Initialized
        and then not Value.Failed
        and then not Value.Finalized
        and then Value.Byte_Length <= Maximum_Bytes
        and then Interfaces.Unsigned_64 (Count) <= Maximum_Bytes - Value.Byte_Length;
   end Can_Accept;

   procedure Update
     (Value : in out Context;
      Data  : String)
   is
   begin
      if not Can_Accept (Value, Data'Length) then
         Value.Failed := True;
         return;
      end if;
      Value.Byte_Length := Value.Byte_Length + Interfaces.Unsigned_64 (Data'Length);
      for Item of Data loop
         Append_Byte (Value, Interfaces.Unsigned_8 (Character'Pos (Item)));
      end loop;
   exception
      when others =>
         Value.Failed := True;
   end Update;

   procedure Update
     (Value : in out Context;
      Data  : Ada.Streams.Stream_Element_Array)
   is
   begin
      if not Can_Accept (Value, Data'Length) then
         Value.Failed := True;
         return;
      end if;
      Value.Byte_Length := Value.Byte_Length + Interfaces.Unsigned_64 (Data'Length);
      for Item of Data loop
         Append_Byte (Value, Interfaces.Unsigned_8 (Item));
      end loop;
   exception
      when others =>
         Value.Failed := True;
   end Update;

   procedure Finish
     (Value   : in out Context;
      Into    : in out Digest;
      Success : out Boolean)
   is
      Candidate  : Digest := [others => 0];
      Bit_Length : Interfaces.Unsigned_64;
   begin
      Success := False;
      if not Value.Initialized then
         Value.Failed := True;
         return;
      elsif Value.Failed or else Value.Finalized then
         return;
      end if;

      Bit_Length := Value.Byte_Length * 8;
      Value.Block (Value.Block_Length) := 16#80#;
      Value.Block_Length := Value.Block_Length + 1;
      if Value.Block_Length > 56 then
         while Value.Block_Length < 64 loop
            Value.Block (Value.Block_Length) := 0;
            Value.Block_Length := Value.Block_Length + 1;
         end loop;
         Transform (Value);
      end if;
      while Value.Block_Length < 56 loop
         Value.Block (Value.Block_Length) := 0;
         Value.Block_Length := Value.Block_Length + 1;
      end loop;
      for Offset in 0 .. 7 loop
         Value.Block (63 - Offset) :=
           Interfaces.Unsigned_8
             (Interfaces.Shift_Right (Bit_Length, Offset * 8) and Interfaces.Unsigned_64 (16#FF#));
      end loop;
      Value.Block_Length := 64;
      Transform (Value);

      for Word_Index in Value.State'Range loop
         for Byte_Index in 0 .. 3 loop
            Candidate (Word_Index * 4 + Byte_Index) :=
              Interfaces.Unsigned_8
                (Interfaces.Shift_Right (Value.State (Word_Index), (3 - Byte_Index) * 8)
                 and Interfaces.Unsigned_32 (16#FF#));
         end loop;
      end loop;
      Value.Finalized := True;
      Into := Candidate;
      Success := True;
   exception
      when others =>
         Value.Failed := True;
         Success := False;
   end Finish;

   function To_Hex (Value : Digest) return Hex_Digest is
      Hex_Digits : constant String := "0123456789abcdef";
      Result     : Hex_Digest;
      Position   : Positive := Result'First;
   begin
      for Item of Value loop
         Result (Position) := Hex_Digits (Natural (Item) / 16 + 1);
         Result (Position + 1) := Hex_Digits (Natural (Item) mod 16 + 1);
         Position := Position + 2;
      end loop;
      return Result;
   end To_Hex;

   function Is_Failed (Value : Context) return Boolean is
     (Value.Failed);
end Flyology_Serde_Generator.Build_SHA_256;
