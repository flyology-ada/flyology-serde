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

   type Event_Kind is
     (Document_Begin,
      Document_End,
      Object_Begin,
      Object_End,
      Array_Begin,
      Array_End,
      Name_Begin,
      Name_Fragment,
      Name_End,
      String_Begin,
      String_Fragment,
      String_End,
      Number_Begin,
      Number_Fragment,
      Number_End,
      Null_Value,
      Boolean_Value);

   subtype Scalar_Length is Natural range 0 .. 4;
   subtype Scalar_Storage is
     Ada.Streams.Stream_Element_Array
       (Ada.Streams.Stream_Element_Offset range 1 .. 4);

   type Decoded_Form is (No_Decoded, Raw_Decoded, Inline_Decoded);

   type Event_Summary is record
      Kind                  : Event_Kind := Document_Begin;
      Source_Offset         : Natural := 0;
      Source_Length         : Natural := 0;
      Has_Raw_Byte          : Boolean := False;
      Raw_Byte              : Ada.Streams.Stream_Element := 0;
      Decoded_Form          : JSON_Event_Drivers.Decoded_Form := No_Decoded;
      Decoded_Offset        : Natural := 0;
      Decoded_Source_Length : Natural := 0;
      Decoded_Length        : Scalar_Length := 0;
      Decoded               : Scalar_Storage := [others => 0];
      Boolean_Payload       : Boolean := False;
   end record;

   Maximum_Event_Summaries : constant Natural := Zero_Progress_Limit + 1;
   type Event_Summary_Array is array (Natural range <>) of Event_Summary;

   type Driver_Outcome is (Event_Available, Need_Source, Document_Accepted);

   type Token_Terminal is
     (Null_Terminal, Boolean_Terminal, String_Terminal, Number_Terminal);

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

   --  Obtain and retain the sole zero-source Document_Begin boundary without
   --  touching a decode budget or source frontier. The event reader calls
   --  this once immediately after Initialize; legacy syntax-gate callers do
   --  not call it.
   procedure Prime_Document_Begin
     (Self : in out Driver; Error : in out Errors.Error_Info);

   --  Publish the retained boundary only after the caller's value preflight
   --  succeeds. A prelatched error leaves it pending.
   procedure Claim_Document_Begin
     (Self    : in out Driver;
      Summary : out Event_Summary;
      Error   : in out Errors.Error_Info);

   --  Consume one strict JSON whitespace byte while Document_Begin remains
   --  pending. This is the only parser-advancing operation allowed before
   --  Claim_Document_Begin and can produce no event.
   procedure Consume_Leading_Whitespace
     (Self   : in out Driver;
      Budget : in out Budgets.Decode_Budget;
      Error  : in out Errors.Error_Info);

   --  Consume exactly one source byte or fail. The byte is charged through
   --  Budget before Flyology JSON can inspect it. Zero-consumption events
   --  reuse the same charged one-byte window.
   procedure Consume_One
     (Self     : in out Driver;
      Budget   : in out Budgets.Decode_Budget;
      Consumed : out Boolean;
      Error    : in out Errors.Error_Info);

   --  Event-preserving form used by the parallel pull reader. Every event is
   --  copied before the next parser Step, so no Flyology JSON borrow escapes.
   --  Summaries must have at least Maximum_Event_Summaries components. Count
   --  is zero on failure and otherwise identifies the prefix from First.
   procedure Consume_One
     (Self      : in out Driver;
      Budget    : in out Budgets.Decode_Budget;
      Consumed  : out Boolean;
      Summaries : out Event_Summary_Array;
      Count     : out Natural;
      Error     : in out Errors.Error_Info);

   --  Perform exactly one nonfinal parser Step. A new source byte is charged
   --  before inspection; an uncharged retained number terminator is charged
   --  immediately before replay. Summary is eligible only for
   --  Event_Available. Consumed reports parser consumption of the source byte.
   procedure Step_Source
     (Self     : in out Driver;
      Budget   : in out Budgets.Decode_Budget;
      Outcome  : out Driver_Outcome;
      Consumed : out Boolean;
      Summary  : out Event_Summary;
      Error    : in out Errors.Error_Info);

   --  Perform exactly one final-input parser Step without source bytes. This
   --  is the physical-EOF counterpart of Step_Source: it can expose
   --  Number_End or Document_End before a later call observes
   --  Document_Accepted. A retained source window is invalid here.
   procedure Step_Final
     (Self    : in out Driver;
      Outcome : out Driver_Outcome;
      Summary : out Event_Summary;
      Error   : in out Errors.Error_Info);

   --  Offer the exact current source byte without charging it and require a
   --  zero-consumption Number_End. The byte remains retained and uncharged;
   --  Step_Source later charges and replays that identical window.
   procedure Observe_Number_End
     (Self    : in out Driver;
      Summary : out Event_Summary;
      Error   : in out Errors.Error_Info);

   --  Offer the exact current strict value delimiter without charging it and
   --  require the selected literal or string terminal event with zero
   --  consumption. The delimiter is JSON whitespace, comma, or a container
   --  closer. The unchanged byte remains retained and uncharged for
   --  Step_Source replay. Flyology JSON emits Name_End while consuming the
   --  closing quote, so names do not use this operation.
   procedure Observe_Token_End
     (Self     : in out Driver;
      Expected : Token_Terminal;
      Summary  : out Event_Summary;
      Error    : in out Errors.Error_Info);

   --  Admit final input and require Flyology JSON's complete-document gate.
   procedure Finish (Self : in out Driver; Error : in out Errors.Error_Info);

   --  Event-preserving final-input form. It copies every zero-source terminal
   --  event before requiring Document_Complete.
   procedure Finish
     (Self      : in out Driver;
      Summaries : out Event_Summary_Array;
      Count     : out Natural;
      Error     : in out Errors.Error_Info);

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
      Window_Charged      : Boolean := False;
      Boundary_Pending    : Boolean := False;
      Pending_Boundary    : Event_Summary := (others => <>);
      Offset              : Natural := 0;
      Zero_Run            : Zero_Progress_Count := 0;
      Initialized         : Boolean := False;
      Failed              : Boolean := False;
      Aborted             : Boolean := False;
      Diagnostic_Reported : Boolean := False;
      Document_Accepted   : Boolean := False;
   end record;
end Flyology_Serde.JSON_Event_Drivers;
