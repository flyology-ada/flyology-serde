with Ada.Streams;
with Flyology_JSON.Parsing;
with Flyology_JSON.Profiles;
with Flyology_Serde.Budgets;
with Flyology_Serde.Errors;
with Flyology_Serde.Policies;

--  Private one-byte admission boundary between the Serde JSON reader and the
--  trusted Flyology JSON event parser.

private package Flyology_Serde.JSON_Event_Drivers is
   package Budgets renames Flyology_Serde.Budgets;
   package Errors renames Flyology_Serde.Errors;

   package Parsing is new
     Flyology_JSON.Parsing
       (Duplicate_Mode => Flyology_JSON.Profiles.Preserve_Unchecked);

   Zero_Progress_Limit : constant Natural :=
     Parsing.Event_Kind'Pos (Parsing.Event_Kind'Last) + 1;

   subtype Zero_Progress_Count is Natural range 0 .. Zero_Progress_Limit;

   --  Closed progress accounting shared by the live driver and the direct
   --  conformance test. Exceeded is true before Count could wrap.
   procedure Account_Progress
     (Consumed    : Boolean;
      Event_Ready : Boolean;
      Count       : in out Zero_Progress_Count;
      Exceeded    : out Boolean);

   type Driver (Source : not null access constant String) is limited private;

   procedure Initialize
     (Self : in out Driver; Error : in out Errors.Error_Info);

   procedure Reset (Self : in out Driver; Error : in out Errors.Error_Info);

   --  Consume exactly one source byte or fail. The byte is charged through
   --  Budget before Flyology JSON can inspect it. Zero-consumption events
   --  reuse the same charged one-byte window.
   procedure Consume_One
     (Self     : in out Driver;
      Budget   : in out Budgets.Decode_Budget;
      Consumed : out Boolean;
      Error    : in out Errors.Error_Info);

   --  Admit final input and require Flyology JSON's complete-document gate.
   procedure Finish (Self : in out Driver; Error : in out Errors.Error_Info);

   --  Preserve an unreported parser terminal diagnostic in Error before
   --  ending the parser operation. An already latched Serde error remains
   --  primary.
   procedure Abort_Document
     (Self : in out Driver; Error : in out Errors.Error_Info);

   --  Exception-cleanup form. It discards diagnostics and never raises.
   procedure Abort_Document (Self : in out Driver);

   function Input_Offset (Self : Driver) return Natural;

private
   --  A logical Serde container can add two physical JSON containers (map
   --  entry and variant envelopes), and a scalar byte envelope can add one.
   Physical_Maximum_Depth : constant Natural :=
     2 * Policies.Maximum_Supported_Nesting + 1;

   subtype One_Byte_Input is
     Ada.Streams.Stream_Element_Array
       (Ada.Streams.Stream_Element_Offset range 1 .. 1);

   type Driver (Source : not null access constant String) is limited record
      Parser              :
        Parsing.Parser
          (Maximum_Depth => Physical_Maximum_Depth,
           Name_Octet_Capacity => 0,
           Name_Capacity => 0);
      Window              : One_Byte_Input := [others => 0];
      Window_Valid        : Boolean := False;
      Offset              : Natural := 0;
      Zero_Run            : Zero_Progress_Count := 0;
      Initialized         : Boolean := False;
      Failed              : Boolean := False;
      Diagnostic_Reported : Boolean := False;
      Document_Accepted   : Boolean := False;
   end record;
end Flyology_Serde.JSON_Event_Drivers;
