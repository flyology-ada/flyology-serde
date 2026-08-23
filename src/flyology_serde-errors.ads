--  Bounded, nonraising error details shared by adapters and format backends.

package Flyology_Serde.Errors
  with Preelaborate
is
   Maximum_Path_Depth  : constant Positive := 32;
   Maximum_Name_Length : constant Positive := 64;

   type Error_Code is
     (No_Error,
      Syntax_Error,
      Unexpected_Kind,
      Invalid_Value,
      Out_Of_Range,
      Invalid_Text,
      Missing_Field,
      Duplicate_Field,
      Unknown_Field,
      Capacity_Exceeded,
      Depth_Exceeded,
      Unsupported_Value,
      Invalid_State,
      Application_Error);

   type Path_Element_Kind is
     (Field_Element, Index_Element, Alternative_Element);

   type Path_Element is record
      Kind           : Path_Element_Kind := Field_Element;
      Index          : Natural := 0;
      Name_Length    : Natural range 0 .. Maximum_Name_Length := 0;
      Name_Truncated : Boolean := False;
      Name           : String (1 .. Maximum_Name_Length) := [others => ' '];
   end record;

   type Path_Array is
     array (Positive range 1 .. Maximum_Path_Depth) of Path_Element;

   type Input_Offset_Unit is
     (Unknown_Offset, Byte_Offset, Code_Unit_Offset, Code_Point_Offset);

   type Error_Info is record
      Code         : Error_Code := No_Error;
      Input_Offset : Natural := 0;
      Offset_Unit  : Input_Offset_Unit := Unknown_Offset;
      Path_Length  : Natural range 0 .. Maximum_Path_Depth := 0;
      Path         : Path_Array;
   end record;

   procedure Reset (Item : out Error_Info);

   procedure Fail
     (Item         : in out Error_Info;
      Code         : Error_Code;
      Input_Offset : Natural := 0;
      Offset_Unit  : Input_Offset_Unit := Unknown_Offset);

   procedure Push_Field (Item : in out Error_Info; Name : String);

   procedure Push_Alternative (Item : in out Error_Info; Name : String);

   procedure Push_Index (Item : in out Error_Info; Index : Natural);

   procedure Pop (Item : in out Error_Info);
end Flyology_Serde.Errors;
