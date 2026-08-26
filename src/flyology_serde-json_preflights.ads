with Flyology_Serde.Errors;

--  Bounded, nonmutating raw observations shared by JSON reader engines.
--  Cursor and every reported offset are zero-based source-byte counts.

private package Flyology_Serde.JSON_Preflights is
   package Errors renames Flyology_Serde.Errors;

   type String_Summary is record
      Raw_Length     : Natural := 0;
      Decoded_Length : Natural := 0;
   end record;

   type Number_Summary is record
      Raw_Length : Natural := 0;
      Is_Integer : Boolean := True;
      Negative   : Boolean := False;
   end record;

   --  Scan one complete JSON string beginning at Cursor. Input_Remaining is
   --  the maximum source-byte count that may be inspected. No source byte at
   --  or beyond that boundary is read.
   procedure Scan_String
     (Source          : String;
      Cursor          : Natural;
      Input_Remaining : Natural;
      Summary         : out String_Summary;
      Error           : in out Errors.Error_Info);

   --  Scan one complete JSON number prefix beginning at Cursor. A legal or
   --  illegal following byte is not part of the returned raw length.
   procedure Scan_Number
     (Source          : String;
      Cursor          : Natural;
      Input_Remaining : Natural;
      Summary         : out Number_Summary;
      Error           : in out Errors.Error_Info);

   --  Compare one complete fixed JSON literal without admitting source.
   --  Truncation and mismatch are Syntax_Error; an otherwise available byte
   --  outside Input_Remaining is Capacity_Exceeded.
   procedure Match_Literal
     (Source          : String;
      Cursor          : Natural;
      Input_Remaining : Natural;
      Literal         : String;
      Error           : in out Errors.Error_Info);
end Flyology_Serde.JSON_Preflights;
