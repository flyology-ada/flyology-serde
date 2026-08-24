with Ada.Command_Line;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Interfaces;

with Flyology_Serde_Generator.Build_Attestation_Test_Hooks;

procedure Flyology_Serde_Generator.Build_Attestations.Source_Lists.Test is
   package Hooks renames Flyology_Serde_Generator.Build_Attestation_Test_Hooks;
   use type Budgets.Budget_State;
   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.Unsigned_64;

   P1 : constant String := "alire.toml";
   P2 : constant String := "dependency-identities-v2.json";
   P3 : constant String := "flyology_serde_generator.gpr";
   P4 : constant String := "provenance-files-v2.txt";
   Long_Leading : constant String := "0000000000000000000000000000000000000000";
   LF : constant Character := Character'Val (10);
   Minimal : constant String := P1 & LF & P2 & LF & P3 & LF & P4 & LF;

   function Comparison_Cost (Left, Right : String) return Interfaces.Unsigned_64 is
     (Interfaces.Unsigned_64 (Natural'Min (Left'Length, Right'Length)) + 2);

   Parse_Work : constant Interfaces.Unsigned_64 :=
     Interfaces.Unsigned_64 (Minimal'Length) +
     Comparison_Cost (P1, P1) +
     Comparison_Cost (P1, P2) +
     Comparison_Cost (P1, P3) +
     Comparison_Cost (P1, P4) +
     Comparison_Cost (P1, P2) +
     Comparison_Cost (P2, P2) +
     Comparison_Cost (P2, P3) +
     Comparison_Cost (P2, P4) +
     Comparison_Cost (P2, P3) +
     Comparison_Cost (P3, P3) +
     Comparison_Cost (P3, P4) +
     Comparison_Cost (P3, P4) +
     Comparison_Cost (P4, P4);

   Visit_Work : constant Interfaces.Unsigned_64 :=
     Interfaces.Unsigned_64 (P1'Length + P2'Length + P3'Length + P4'Length + 4);
   One_Entry_Work : constant Interfaces.Unsigned_64 :=
     Interfaces.Unsigned_64 (P1'Length + 1) +
     Comparison_Cost (P1, P1) +
     Comparison_Cost (P1, P2) +
     Comparison_Cost (P1, P3) +
     Comparison_Cost (P1, P4);

   type Charge_Trace is array (Positive range 1 .. 128) of Interfaces.Unsigned_64;

   procedure Build_Parse_Trace
     (Trace : out Charge_Trace;
      Last  : out Natural)
   is
      procedure Add (Amount : Interfaces.Unsigned_64) is
      begin
         Last := Last + 1;
         Trace (Last) := Amount;
      end Add;

      procedure Add_Bytes (Count : Positive) is
      begin
         for Byte in 1 .. Count loop
            pragma Unreferenced (Byte);
            Add (1);
         end loop;
      end Add_Bytes;

      procedure Add_Comparison (Left, Right : String) is
      begin
         Add (1);
         Add (Interfaces.Unsigned_64 (Natural'Min (Left'Length, Right'Length)) + 1);
      end Add_Comparison;
   begin
      Trace := [others => 1];
      Last := 0;
      Add_Bytes (P1'Length + 1);
      Add_Comparison (P1, P1);
      Add_Comparison (P1, P2);
      Add_Comparison (P1, P3);
      Add_Comparison (P1, P4);
      Add_Bytes (P2'Length + 1);
      Add_Comparison (P1, P2);
      Add_Comparison (P2, P2);
      Add_Comparison (P2, P3);
      Add_Comparison (P2, P4);
      Add_Bytes (P3'Length + 1);
      Add_Comparison (P2, P3);
      Add_Comparison (P3, P3);
      Add_Comparison (P3, P4);
      Add_Bytes (P4'Length + 1);
      Add_Comparison (P3, P4);
      Add_Comparison (P4, P4);
   end Build_Parse_Trace;

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   function Read_File (Path : String) return String is
      package IO renames Ada.Streams.Stream_IO;
      File   : IO.File_Type;
   begin
      IO.Open (File, IO.In_File, Path);
      declare
         Length : constant IO.Count := IO.Size (File);
         Data   : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Length));
         Last   : Ada.Streams.Stream_Element_Offset;
         Result : String (1 .. Natural (Length));
      begin
         IO.Read (File, Data, Last);
         Require (Last = Data'Last, "tracked source list short read");
         IO.Close (File);
         for Index in Result'Range loop
            Result (Index) := Character'Val (Data (Ada.Streams.Stream_Element_Offset (Index)));
         end loop;
         return Result;
      end;
   end Read_File;

   procedure Initialize_Budget
     (Value : in out Budgets.Budget;
      Work  : Budgets.Limit_Value)
   is
      Initialized : Boolean;
   begin
      Budgets.Initialize
        ((Maximum_Input_Bytes => Interfaces.Unsigned_64'Last, Maximum_Work_Units => Work),
         Value,
         Initialized);
      Require (Initialized, "source-list budget initialization failed");
   end Initialize_Budget;

   procedure Require_Work (Value : Budgets.Budget; Expected : Interfaces.Unsigned_64) is
      Usage : constant Budgets.Usage := Budgets.Current_Usage (Value);
   begin
      Require (Usage.Input_Bytes = 0, "source-list parser charged input bytes");
      Require
        (Usage.Work_Units = Expected,
         "unexpected source-list work trace:" & Usage.Work_Units'Image & " expected" & Expected'Image);
   end Require_Work;

   procedure Check_Parse
     (Bytes    : String;
      Expected : Parse_Status;
      Message  : String)
   is
      Budget  : aliased Budgets.Budget;
      Value   : Parsed_List (Budget'Access);
      Session : Budgets.Session_Tag;
      Status  : Parse_Status := Parse_Succeeded;
   begin
      Initialize_Budget (Budget, Interfaces.Unsigned_64'Last);
      Session := Budgets.Current_Session (Budget);
      Parse
        (Bytes, Session, Interfaces.Unsigned_64'Last, Interfaces.Unsigned_64'Last,
         Interfaces.Unsigned_64'Last, Value, Status);
      Require (Status = Expected, Message);
   end Check_Parse;

   procedure Check_Limited_Parse
     (Bytes            : String;
      Manifest_Limit   : Limit_Value;
      Path_Limit       : Limit_Value;
      File_Limit       : Limit_Value;
      Expected_Status  : Parse_Status;
      Expected_Work    : Interfaces.Unsigned_64;
      Message          : String)
   is
      Budget  : aliased Budgets.Budget;
      Value   : Parsed_List (Budget'Access);
      Session : Budgets.Session_Tag;
      Status  : Parse_Status := Parse_Succeeded;
   begin
      Initialize_Budget (Budget, Interfaces.Unsigned_64'Last);
      Session := Budgets.Current_Session (Budget);
      Parse (Bytes, Session, Manifest_Limit, Path_Limit, File_Limit, Value, Status);
      Require (Status = Expected_Status, Message);
      Require_Work (Budget, Expected_Work);
   end Check_Limited_Parse;

   procedure Check_Budget_Parse
     (Maximum_Work   : Budgets.Limit_Value;
      Expected_Status : Parse_Status;
      Expected_Work   : Interfaces.Unsigned_64;
      Message         : String)
   is
      Budget  : aliased Budgets.Budget;
      Value   : Parsed_List (Budget'Access);
      Session : Budgets.Session_Tag;
      Status  : Parse_Status := Parse_Succeeded;
   begin
      Initialize_Budget (Budget, Maximum_Work);
      Session := Budgets.Current_Session (Budget);
      Parse (Minimal, Session, Minimal'Length, P2'Length, 4, Value, Status);
      Require (Status = Expected_Status, Message);
      Require_Work (Budget, Expected_Work);
   end Check_Budget_Parse;

   procedure Check_All_Parse_Denials is
      Trace      : Charge_Trace;
      Last       : Natural;
      Cumulative : Interfaces.Unsigned_64 := 0;
   begin
      Build_Parse_Trace (Trace, Last);
      for Index in 1 .. Last loop
         Cumulative := Cumulative + Trace (Index);
      end loop;
      Require (Cumulative = Parse_Work, "independent parser charge trace changed");

      Cumulative := Trace (1);
      for Denied in 2 .. Last loop
         declare
            Budget  : aliased Budgets.Budget;
            Value   : Parsed_List (Budget'Access);
            Session : Budgets.Session_Tag;
            Status  : Parse_Status := Parse_Succeeded;
         begin
            Initialize_Budget (Budget, Budgets.Limit_Value (Cumulative));
            Session := Budgets.Current_Session (Budget);
            Parse (Minimal, Session, Minimal'Length, P2'Length, 4, Value, Status);
            Require
              (Status = Parse_Budget_Exhausted,
               "parser reserve denial" & Natural'Image (Denied) & " was not exhausted");
            Require_Work (Budget, Cumulative);
         end;
         Cumulative := Cumulative + Trace (Denied);
      end loop;
   end Check_All_Parse_Denials;

   procedure Check_Required_Comparison_Order is
      Bytes  : constant String := Long_Leading & LF & Minimal;
      Prefix : Interfaces.Unsigned_64 := Interfaces.Unsigned_64 (Long_Leading'Length + 1);

      procedure Check_Boundary
        (Maximum_Work : Budgets.Limit_Value;
         Expected     : Interfaces.Unsigned_64;
         Label        : String)
      is
         Budget  : aliased Budgets.Budget;
         Value   : Parsed_List (Budget'Access);
         Session : Budgets.Session_Tag;
         Status  : Parse_Status := Parse_Succeeded;
      begin
         Initialize_Budget (Budget, Maximum_Work);
         Session := Budgets.Current_Session (Budget);
         Parse (Bytes, Session, Bytes'Length, Long_Leading'Length, 5, Value, Status);
         Require (Status = Parse_Budget_Exhausted, Label & " did not exhaust");
         Require_Work (Budget, Expected);
      end Check_Boundary;

      procedure Check_Comparison (Name : String; Label : String) is
         Amount : constant Interfaces.Unsigned_64 :=
           Interfaces.Unsigned_64 (Natural'Min (Long_Leading'Length, Name'Length)) + 1;
      begin
         Prefix := Prefix + 1;
         Check_Boundary
           (Budgets.Limit_Value (Prefix + Amount - 1), Prefix,
            Label & " one-less amount boundary");
         Prefix := Prefix + Amount;
         Check_Boundary
           (Budgets.Limit_Value (Prefix), Prefix, Label & " exact amount boundary");
      end Check_Comparison;
   begin
      Check_Comparison (P1, "alire comparison");
      Check_Comparison (P2, "dependency comparison");
      Check_Comparison (P3, "project comparison");
      Check_Comparison (P4, "self comparison");
   end Check_Required_Comparison_Order;

   procedure Check_All_Visit_Denials is
      Trace : constant array (Positive range 1 .. 8) of Interfaces.Unsigned_64 :=
        [1, P1'Length, 1, P2'Length, 1, P3'Length, 1, P4'Length];
      Cumulative : Interfaces.Unsigned_64 := 0;
   begin
      for Denied in Trace'Range loop
         declare
            Budget   : aliased Budgets.Budget;
            Value    : Parsed_List (Budget'Access);
            Session  : Budgets.Session_Tag;
            P_State  : Parse_Status := Parse_Succeeded;
            V_State  : Visit_Status := Visit_Succeeded;
            Calls    : Natural := 0;

            procedure Observe
              (Session : Budgets.Session_Tag;
               Path    : String;
               Action  : out Visit_Action)
            is
               pragma Unreferenced (Session, Path);
            begin
               Calls := Calls + 1;
               Action := Continue;
            end Observe;
         begin
            Initialize_Budget
              (Budget, Budgets.Limit_Value (Parse_Work + Cumulative));
            Session := Budgets.Current_Session (Budget);
            Parse (Minimal, Session, Minimal'Length, P2'Length, 4, Value, P_State);
            Require (P_State = Parse_Succeeded, "visit denial setup parse failed");
            Visit (Value, Session, Observe'Access, V_State);
            Require
              (V_State = Visit_Budget_Exhausted,
               "visit reserve denial" & Natural'Image (Denied) & " was not exhausted");
            Require
              (Calls = (Denied - 1) / 2,
               "visit reserve denial invoked the wrong callback count");
            Require_Work (Budget, Parse_Work + Cumulative);
         end;
         Cumulative := Cumulative + Trace (Denied);
      end loop;
      Require (Cumulative = Visit_Work, "independent visit charge trace changed");
   end Check_All_Visit_Denials;

   procedure Check_Source_Failure
     (Point             : Hooks.Source_Failure_Point;
      Expected_Status   : Parse_Status;
      Expected_Paths    : Natural;
      Expected_Nodes    : Natural;
      Expected_Payloads : Natural;
      Message           : String)
   is
      PA0, PR0, NA0, NR0, OA0, OR0 : Natural;
      PA1, PR1, NA1, NR1, OA1, OR1 : Natural;
   begin
      Hooks.Source_Allocation_Counts (PA0, PR0, NA0, NR0, OA0, OR0);
      declare
         Budget  : aliased Budgets.Budget;
         Value   : Parsed_List (Budget'Access);
         Session : Budgets.Session_Tag;
         Status  : Parse_Status := Parse_Succeeded;
      begin
         Initialize_Budget (Budget, Interfaces.Unsigned_64'Last);
         Session := Budgets.Current_Session (Budget);
         Hooks.Arm_Source_Failure (Point);
         Parse (Minimal, Session, Minimal'Length, P2'Length, 4, Value, Status);
         Require (Status = Expected_Status, Message);
         Require (Budgets.Current_State (Budget) = Budgets.Failed, Message & " did not poison budget");
      end;
      Hooks.Source_Allocation_Counts (PA1, PR1, NA1, NR1, OA1, OR1);
      Require
        (PA1 = PA0 + Expected_Paths
         and then PR1 = PR0 + Expected_Paths
         and then NA1 = NA0 + Expected_Nodes
         and then NR1 = NR0 + Expected_Nodes
         and then OA1 = OA0 + Expected_Payloads
         and then OR1 = OR0 + Expected_Payloads,
         Message & " leaked or double-freed ownership");
   end Check_Source_Failure;

begin
   declare
      Budget   : aliased Budgets.Budget;
      Value    : Parsed_List (Budget'Access);
      Session  : Budgets.Session_Tag;
      Status   : Parse_Status := Parse_Succeeded;
      V_Status : Visit_Status := Visit_Succeeded;
      Position : Natural := 0;

      procedure Observe
        (Session : Budgets.Session_Tag;
         Path    : String;
         Action  : out Visit_Action)
      is
         pragma Unreferenced (Session);
      begin
         Position := Position + 1;
         case Position is
            when 1 => Require (Path = P1, "first source-list path changed");
            when 2 => Require (Path = P2, "second source-list path changed");
            when 3 => Require (Path = P3, "third source-list path changed");
            when 4 => Require (Path = P4, "fourth source-list path changed");
            when others => raise Program_Error with "extra source-list path";
         end case;
         Action := Continue;
      end Observe;
   begin
      Initialize_Budget (Budget, Interfaces.Unsigned_64'Last);
      Session := Budgets.Current_Session (Budget);
      Parse
        (Minimal, Session, Minimal'Length, P2'Length, 4, Value, Status);
      Require (Status = Parse_Succeeded, "minimal source list was rejected: " & Status'Image);
      Require_Work (Budget, Parse_Work);
      Visit (Value, Session, Observe'Access, V_Status);
      Require (V_Status = Visit_Succeeded, "valid source-list visit failed");
      Require (Position = 4, "source-list visit ended early");
      Require_Work (Budget, Parse_Work + Visit_Work);

      Status := Parse_Succeeded;
      Parse (Minimal, Session, Minimal'Length, P2'Length, 4, Value, Status);
      Require (Status = Parse_Owner_Not_Empty, "nonempty list was replaced");
      Require_Work (Budget, Parse_Work + Visit_Work);

      Position := 0;
      V_Status := Visit_Succeeded;
      Visit (Value, Session, Observe'Access, V_Status);
      Require (V_Status = Visit_Succeeded, "rejected replacement damaged prior list");
      Require (Position = 4, "rejected replacement changed prior list content");
      Require_Work (Budget, Parse_Work + 2 * Visit_Work);
   end;

   Check_Parse ("", Parse_Malformed, "empty source list was accepted");
   Check_Parse (Minimal (Minimal'First .. Minimal'Last - 1), Parse_Malformed,
                "missing final LF was accepted");
   Check_Parse (Minimal & LF, Parse_Malformed, "blank final entry was accepted");
   Check_Parse (P1 & LF & P1 & LF & P2 & LF & P3 & LF & P4 & LF, Parse_Malformed,
                "duplicate path was accepted");
   Check_Parse (P2 & LF & P1 & LF & P3 & LF & P4 & LF, Parse_Malformed,
                "decreasing path was accepted");
   Check_Parse ("./" & P1 & LF & P2 & LF & P3 & LF & P4 & LF, Parse_Malformed,
                "dot component was accepted");
   Check_Parse (P1 & LF & P2 & LF & P3 & LF, Parse_Malformed,
                "missing required path was accepted");
   Check_Limited_Parse
     (P1 & LF, P1'Length + 1, P1'Length, 4, Parse_Malformed, One_Entry_Work,
      "one-entry source list was not rejected for missing membership");
   Check_Parse (P1 & Character'Val (13) & LF & P2 & LF & P3 & LF & P4 & LF,
                Parse_Malformed, "CR was accepted");
   Check_Parse (P1 & Character'Val (0) & LF & P2 & LF & P3 & LF & P4 & LF,
                Parse_Malformed, "NUL was accepted");
   Check_Parse (P1 & Character'Val (16#80#) & LF & P2 & LF & P3 & LF & P4 & LF,
                Parse_Malformed, "high byte was accepted");
   Check_Parse ("/" & P1 & LF & P2 & LF & P3 & LF & P4 & LF,
                Parse_Malformed, "leading separator was accepted");
   Check_Parse (P1 & "/" & LF & P2 & LF & P3 & LF & P4 & LF,
                Parse_Malformed, "trailing separator was accepted");
   Check_Parse ("a//b" & LF & P1 & LF & P2 & LF & P3 & LF & P4 & LF,
                Parse_Malformed, "repeated separator was accepted");
   Check_Parse ("a/../b" & LF & P1 & LF & P2 & LF & P3 & LF & P4 & LF,
                Parse_Malformed, "dot-dot component was accepted");
   Check_Parse ("@" & LF & P1 & LF & P2 & LF & P3 & LF & P4 & LF,
                Parse_Malformed, "nonportable byte was accepted");
   Check_Parse ("A-0_." & LF & Minimal, Parse_Succeeded,
                "portable character boundary was rejected");
   Check_Parse (P2 & LF & P3 & LF & P4 & LF, Parse_Malformed,
                "missing alire path was accepted");
   Check_Parse (P1 & LF & P3 & LF & P4 & LF, Parse_Malformed,
                "missing dependency path was accepted");
   Check_Parse (P1 & LF & P2 & LF & P4 & LF, Parse_Malformed,
                "missing project path was accepted");
   Check_Parse (P1 & LF & P2 & LF & P3 & LF, Parse_Malformed,
                "missing self path was accepted");

   Check_Limited_Parse
     (Minimal, Minimal'Length, P2'Length, 4, Parse_Succeeded, Parse_Work,
      "exact parser limits failed");
   Check_Limited_Parse
     (Minimal, Minimal'Length - 1, P2'Length, 4, Parse_Limit_Exceeded, 0,
      "manifest max-plus-one was accepted");
   Check_Limited_Parse
     (Minimal, Minimal'Length, P2'Length - 1, 4, Parse_Limit_Exceeded, 88,
      "path max-plus-one was accepted");
   Check_Limited_Parse
     (Minimal, Minimal'Length, P2'Length, 3, Parse_Limit_Exceeded,
      Parse_Work - Comparison_Cost (P3, P4) - Comparison_Cost (P4, P4),
      "file-count max-plus-one was accepted");
   Check_Limited_Parse
     (P1 & "@" & LF, P1'Length + 2, P1'Length, 4, Parse_Limit_Exceeded,
      Interfaces.Unsigned_64 (P1'Length + 1), "path limit did not precede invalid byte");
   Check_Limited_Parse
     (P1 & LF & "A" & LF, P1'Length + 4, P1'Length, 1, Parse_Limit_Exceeded,
      61, "count limit did not precede ordering");

   Check_Budget_Parse (1, Parse_Budget_Exhausted, 1, "parse byte denial failed");
   Check_Budget_Parse
     (Budgets.Limit_Value (P1'Length + 1), Parse_Budget_Exhausted,
      Interfaces.Unsigned_64 (P1'Length + 1), "required comparison probe denial failed");
   Check_Budget_Parse
     (Budgets.Limit_Value (P1'Length + 2), Parse_Budget_Exhausted,
      Interfaces.Unsigned_64 (P1'Length + 2), "required comparison byte denial failed");
   Check_Budget_Parse (89, Parse_Budget_Exhausted, 89, "ordering comparison probe denial failed");
   Check_Budget_Parse (90, Parse_Budget_Exhausted, 90, "ordering comparison byte denial failed");
   Check_All_Parse_Denials;
   Check_Required_Comparison_Order;
   Check_All_Visit_Denials;

   declare
      Budget  : aliased Budgets.Budget;
      Value   : Parsed_List (Budget'Access);
      Session : Budgets.Session_Tag;
      Status  : Parse_Status := Parse_Succeeded;
   begin
      Initialize_Budget (Budget, Budgets.Limit_Value (Parse_Work - 1));
      Session := Budgets.Current_Session (Budget);
      Parse (Minimal, Session, Minimal'Length, P2'Length, 4, Value, Status);
      Require (Status = Parse_Budget_Exhausted, "one-less parser work did not exhaust");
      Require (Budgets.Current_State (Budget) = Budgets.Exhausted, "parser denial did not latch");
      Require_Work (Budget, Parse_Work - Comparison_Cost (P4, P4) + 1);
   end;

   declare
      Budget   : aliased Budgets.Budget;
      Value    : Parsed_List (Budget'Access);
      Session  : Budgets.Session_Tag;
      Status   : Parse_Status := Parse_Succeeded;
      V_Status : Visit_Status := Visit_Succeeded;
      Calls    : Natural := 0;

      procedure Stop_After_First
        (Session : Budgets.Session_Tag;
         Path    : String;
         Action  : out Visit_Action)
      is
         pragma Unreferenced (Session, Path);
      begin
         Calls := Calls + 1;
         Action := Stop;
      end Stop_After_First;
   begin
      Initialize_Budget (Budget, Interfaces.Unsigned_64'Last);
      Session := Budgets.Current_Session (Budget);
      Parse (Minimal, Session, Minimal'Length, P2'Length, 4, Value, Status);
      Visit (Value, Session, Stop_After_First'Access, V_Status);
      Require (V_Status = Visit_Stopped and then Calls = 1, "ordinary visit stop failed");
      Require_Work (Budget, Parse_Work + 1 + Interfaces.Unsigned_64 (P1'Length));
   end;

   declare
      Budget   : aliased Budgets.Budget;
      Other    : aliased Budgets.Budget;
      Value    : Parsed_List (Budget'Access);
      Session  : Budgets.Session_Tag;
      Foreign  : Budgets.Session_Tag;
      P_State  : Parse_Status := Parse_Malformed;
      V_State  : Visit_Status := Visit_No_List;

      procedure Ignore
        (Session : Budgets.Session_Tag;
         Path    : String;
         Action  : out Visit_Action)
      is
         pragma Unreferenced (Session, Path);
      begin
         Action := Continue;
      end Ignore;
   begin
      Initialize_Budget (Budget, Interfaces.Unsigned_64'Last);
      Initialize_Budget (Other, Interfaces.Unsigned_64'Last);
      Session := Budgets.Current_Session (Budget);
      Foreign := Budgets.Current_Session (Other);
      Parse (Minimal, Session, Minimal'Length, P2'Length, 4, Value, P_State);
      Visit (Value, Session, Ignore'Access, V_State);
      Require (P_State = Parse_Malformed, "prelatched parse status changed");
      Require (V_State = Visit_No_List, "prelatched visit status changed");
      Require_Work (Budget, 0);

      P_State := Parse_Succeeded;
      Parse (Minimal, Foreign, Minimal'Length, P2'Length, 4, Value, P_State);
      Require (P_State = Parse_Session_Foreign, "foreign parse session was accepted");
      V_State := Visit_Succeeded;
      Visit (Value, Foreign, Ignore'Access, V_State);
      Require (V_State = Visit_Session_Foreign, "foreign visit session was accepted");
      Require_Work (Budget, 0);

      V_State := Visit_Succeeded;
      Visit (Value, Session, Ignore'Access, V_State);
      Require (V_State = Visit_No_List, "empty list visit was misclassified");
      Require_Work (Budget, 0);
   end;

   declare
      Budget      : aliased Budgets.Budget;
      Value       : Parsed_List (Budget'Access);
      Old_Session : Budgets.Session_Tag;
      New_Session : Budgets.Session_Tag;
      P_State     : Parse_Status := Parse_Succeeded;
      V_State     : Visit_Status := Visit_Succeeded;
      Initialized : Boolean;

      procedure Ignore
        (Session : Budgets.Session_Tag;
         Path    : String;
         Action  : out Visit_Action)
      is
         pragma Unreferenced (Session, Path);
      begin
         Action := Continue;
      end Ignore;
   begin
      Initialize_Budget (Budget, Interfaces.Unsigned_64'Last);
      Old_Session := Budgets.Current_Session (Budget);
      Parse (Minimal, Old_Session, Minimal'Length, P2'Length, 4, Value, P_State);
      Budgets.Initialize
        ((Maximum_Input_Bytes => Interfaces.Unsigned_64'Last,
          Maximum_Work_Units  => Interfaces.Unsigned_64'Last),
         Budget,
         Initialized);
      Require (Initialized, "source-list stale-session reinitialize failed");
      New_Session := Budgets.Current_Session (Budget);
      P_State := Parse_Succeeded;
      Parse (Minimal, New_Session, Minimal'Length, P2'Length, 4, Value, P_State);
      Require (P_State = Parse_Session_Foreign, "stale list was replaced");
      Visit (Value, New_Session, Ignore'Access, V_State);
      Require (V_State = Visit_Session_Foreign, "stale list was visited");
      Require_Work (Budget, 0);
   end;

   declare
      Budget  : aliased Budgets.Budget;
      Value   : Parsed_List (Budget'Access);
      Session : Budgets.Session_Tag;
      P_State : Parse_Status := Parse_Succeeded;
      V_State : Visit_Status := Visit_Succeeded;
      Granted : Boolean;

      procedure Ignore
        (Session : Budgets.Session_Tag;
         Path    : String;
         Action  : out Visit_Action)
      is
         pragma Unreferenced (Session, Path);
      begin
         Action := Continue;
      end Ignore;
   begin
      Initialize_Budget (Budget, 1);
      Session := Budgets.Current_Session (Budget);
      Budgets.Reserve (Budget, Budgets.Work_Units, 1, Granted);
      Require (Granted, "first-denial setup charge was rejected");
      Parse (Minimal, Session, Minimal'Length, P2'Length, 4, Value, P_State);
      Require (P_State = Parse_Budget_Exhausted, "first parser reservation denial failed");
      V_State := Visit_Succeeded;
      Visit (Value, Session, Ignore'Access, V_State);
      Require (V_State = Visit_Budget_Exhausted, "preexhausted visit was misclassified");
      Require_Work (Budget, 1);
   end;

   declare
      Budget  : aliased Budgets.Budget;
      Value   : Parsed_List (Budget'Access);
      Session : Budgets.Session_Tag;
      P_State : Parse_Status := Parse_Succeeded;
      V_State : Visit_Status := Visit_Succeeded;

      procedure Ignore
        (Session : Budgets.Session_Tag;
         Path    : String;
         Action  : out Visit_Action)
      is
         pragma Unreferenced (Session, Path);
      begin
         Action := Continue;
      end Ignore;
   begin
      Initialize_Budget (Budget, Interfaces.Unsigned_64'Last);
      Session := Budgets.Current_Session (Budget);
      Budgets.Poison (Budget);
      Parse (Minimal, Session, Minimal'Length, P2'Length, 4, Value, P_State);
      Require (P_State = Parse_Budget_Failed, "failed-budget parse was misclassified");
      Visit (Value, Session, Ignore'Access, V_State);
      Require (V_State = Visit_Budget_Failed, "failed-budget visit was misclassified");
      Require_Work (Budget, 0);
   end;

   declare
      procedure Check_Visit_Denial
        (Maximum_Work : Budgets.Limit_Value;
         Expected     : Interfaces.Unsigned_64;
         Message      : String)
      is
         Budget   : aliased Budgets.Budget;
         Value    : Parsed_List (Budget'Access);
         Session  : Budgets.Session_Tag;
         P_State  : Parse_Status := Parse_Succeeded;
         V_State  : Visit_Status := Visit_Succeeded;
         Calls    : Natural := 0;

         procedure Observe
           (Session : Budgets.Session_Tag;
            Path    : String;
            Action  : out Visit_Action)
         is
            pragma Unreferenced (Session, Path);
         begin
            Calls := Calls + 1;
            Action := Continue;
         end Observe;
      begin
         Initialize_Budget (Budget, Maximum_Work);
         Session := Budgets.Current_Session (Budget);
         Parse (Minimal, Session, Minimal'Length, P2'Length, 4, Value, P_State);
         Visit (Value, Session, Observe'Access, V_State);
         Require (V_State = Visit_Budget_Exhausted, Message);
         Require (Calls = 0, Message & " invoked callback");
         Require_Work (Budget, Expected);
      end Check_Visit_Denial;
   begin
      Check_Visit_Denial
        (Budgets.Limit_Value (Parse_Work), Parse_Work, "visit probe denial failed");
      Check_Visit_Denial
        (Budgets.Limit_Value (Parse_Work + 1), Parse_Work + 1,
         "visit path-byte denial failed");
   end;

   declare
      Budget   : aliased Budgets.Budget;
      Value    : Parsed_List (Budget'Access);
      Session  : Budgets.Session_Tag;
      P_State  : Parse_Status := Parse_Succeeded;
      V_State  : Visit_Status := Visit_Succeeded;
      Nested   : Visit_Status := Visit_Succeeded;

      procedure Ignore
        (Session : Budgets.Session_Tag;
         Path    : String;
         Action  : out Visit_Action)
      is
         pragma Unreferenced (Session, Path);
      begin
         Action := Continue;
      end Ignore;

      procedure Reenter
        (Session : Budgets.Session_Tag;
         Path    : String;
         Action  : out Visit_Action)
      is
         pragma Unreferenced (Path);
      begin
         Visit (Value, Session, Ignore'Access, Nested);
         Action := Stop;
      end Reenter;
   begin
      Initialize_Budget (Budget, Interfaces.Unsigned_64'Last);
      Session := Budgets.Current_Session (Budget);
      Parse (Minimal, Session, Minimal'Length, P2'Length, 4, Value, P_State);
      Visit (Value, Session, Reenter'Access, V_State);
      Require (Nested = Visit_Reentrant, "recursive visit was accepted");
      Require (V_State = Visit_Stopped, "recursive visit damaged outer traversal");
   end;

   declare
      Budget   : aliased Budgets.Budget;
      Value    : Parsed_List (Budget'Access);
      Session  : Budgets.Session_Tag;
      P_State  : Parse_Status := Parse_Succeeded;
      V_State  : Visit_Status := Visit_Succeeded;
      Reset_OK : Boolean;

      procedure Reset_Then_Fail
        (Session : Budgets.Session_Tag;
         Path    : String;
         Action  : out Visit_Action)
      is
         pragma Unreferenced (Session, Path, Action);
      begin
         Budgets.Initialize
           ((Maximum_Input_Bytes => Interfaces.Unsigned_64'Last,
             Maximum_Work_Units  => Interfaces.Unsigned_64'Last),
            Budget,
            Reset_OK);
         Require (Reset_OK, "visit-release reset failed");
         Hooks.Arm_Source_Failure (Hooks.Source_Visit_Release);
         raise Program_Error with "injected source-list callback failure";
      end Reset_Then_Fail;
   begin
      Initialize_Budget (Budget, Interfaces.Unsigned_64'Last);
      Session := Budgets.Current_Session (Budget);
      Parse (Minimal, Session, Minimal'Length, P2'Length, 4, Value, P_State);
      Visit (Value, Session, Reset_Then_Fail'Access, V_State);
      Require
        (V_State = Visit_Session_Foreign,
         "visit-release damage replaced the callback session primary");
      Require
        (Budgets.Current_State (Budget) = Budgets.Failed,
         "visit-release damage did not poison the fresh active budget");
   end;

   declare
      Budget      : aliased Budgets.Budget;
      Value       : Parsed_List (Budget'Access);
      Session     : Budgets.Session_Tag;
      P_State     : Parse_Status := Parse_Succeeded;
      V_State     : Visit_Status := Visit_Succeeded;
      Initialized : Boolean;

      procedure Reset
        (Session : Budgets.Session_Tag;
         Path    : String;
         Action  : out Visit_Action)
      is
         pragma Unreferenced (Session, Path);
      begin
         Budgets.Initialize
           ((Maximum_Input_Bytes => Interfaces.Unsigned_64'Last,
             Maximum_Work_Units  => Interfaces.Unsigned_64'Last),
            Budget,
            Initialized);
         Require (Initialized, "callback budget reset failed");
         Action := Continue;
      end Reset;
   begin
      Initialize_Budget (Budget, Interfaces.Unsigned_64'Last);
      Session := Budgets.Current_Session (Budget);
      Parse (Minimal, Session, Minimal'Length, P2'Length, 4, Value, P_State);
      Visit (Value, Session, Reset'Access, V_State);
      Require (V_State = Visit_Session_Foreign, "callback session reset was misclassified");
      Require_Work (Budget, 0);
   end;

   declare
      Budget   : aliased Budgets.Budget;
      Value    : Parsed_List (Budget'Access);
      Session  : Budgets.Session_Tag;
      P_State  : Parse_Status := Parse_Succeeded;
      V_State  : Visit_Status := Visit_Succeeded;
      Granted  : Boolean;

      procedure Exhaust
        (Session : Budgets.Session_Tag;
         Path    : String;
         Action  : out Visit_Action)
      is
         pragma Unreferenced (Session, Path);
      begin
         Budgets.Reserve (Budget, Budgets.Work_Units, 1, Granted);
         Action := Continue;
      end Exhaust;
   begin
      Initialize_Budget
        (Budget, Budgets.Limit_Value (Parse_Work + 1 + Interfaces.Unsigned_64 (P1'Length)));
      Session := Budgets.Current_Session (Budget);
      Parse (Minimal, Session, Minimal'Length, P2'Length, 4, Value, P_State);
      Visit (Value, Session, Exhaust'Access, V_State);
      Require (not Granted, "callback exhaustion setup unexpectedly granted");
      Require (V_State = Visit_Budget_Exhausted, "callback exhaustion was misclassified");
   end;

   declare
      Budget   : aliased Budgets.Budget;
      Value    : Parsed_List (Budget'Access);
      Session  : Budgets.Session_Tag;
      P_State  : Parse_Status := Parse_Succeeded;
      V_State  : Visit_Status := Visit_Succeeded;

      procedure Poison
        (Session : Budgets.Session_Tag;
         Path    : String;
         Action  : out Visit_Action)
      is
         pragma Unreferenced (Session, Path);
      begin
         Budgets.Poison (Budget);
         Action := Continue;
      end Poison;
   begin
      Initialize_Budget (Budget, Interfaces.Unsigned_64'Last);
      Session := Budgets.Current_Session (Budget);
      Parse (Minimal, Session, Minimal'Length, P2'Length, 4, Value, P_State);
      Visit (Value, Session, Poison'Access, V_State);
      Require (V_State = Visit_Budget_Failed, "callback poison was misclassified");
   end;

   Check_Source_Failure
     (Hooks.Source_Path_Storage, Parse_Allocation_Failed, 0, 0, 0,
      "path Storage_Error was misclassified");
   Check_Source_Failure
     (Hooks.Source_Node_Storage, Parse_Allocation_Failed, 1, 0, 0,
      "node Storage_Error was misclassified");
   Check_Source_Failure
     (Hooks.Source_Payload_Storage, Parse_Allocation_Failed, 4, 4, 0,
      "payload Storage_Error was misclassified");
   Check_Source_Failure
     (Hooks.Source_Internal, Parse_Internal_Failure, 4, 4, 0,
      "source-list internal failure was misclassified");

   declare
      procedure Check_Candidate_Release
        (Point   : Hooks.Source_Failure_Point;
         Message : String)
      is
         PA0, PR0, NA0, NR0, OA0, OR0 : Natural;
         PA1, PR1, NA1, NR1, OA1, OR1 : Natural;
      begin
         Hooks.Source_Allocation_Counts (PA0, PR0, NA0, NR0, OA0, OR0);
         declare
            Budget  : aliased Budgets.Budget;
            Value   : Parsed_List (Budget'Access);
            Session : Budgets.Session_Tag;
            Status  : Parse_Status := Parse_Succeeded;
         begin
            Initialize_Budget (Budget, Interfaces.Unsigned_64'Last);
            Session := Budgets.Current_Session (Budget);
            Hooks.Arm_Source_Failure (Point);
            Parse
              (P1 & LF & "@" & LF, Session, Minimal'Length, P2'Length, 4, Value, Status);
            Require (Status = Parse_Malformed, Message & " replaced primary status");
            Require
              (Budgets.Current_State (Budget) = Budgets.Failed,
               Message & " did not poison budget");
         end;
         Hooks.Source_Allocation_Counts (PA1, PR1, NA1, NR1, OA1, OR1);
         Require
           (PA1 = PA0 + 1
            and then PR1 = PR0 + 1
            and then NA1 = NA0 + 1
            and then NR1 = NR0 + 1
            and then OA1 = OA0
            and then OR1 = OR0,
            Message & " did not release the exact candidate ownership");
      end Check_Candidate_Release;
   begin
      Check_Candidate_Release (Hooks.Source_Path_Release, "candidate path release failure");
      Check_Candidate_Release (Hooks.Source_Node_Release, "candidate node release failure");
   end;

   declare
      Budget  : aliased Budgets.Budget;
      Session : Budgets.Session_Tag;
      PA0, PR0, NA0, NR0, OA0, OR0 : Natural;
      PA1, PR1, NA1, NR1, OA1, OR1 : Natural;
   begin
      Initialize_Budget (Budget, Interfaces.Unsigned_64'Last);
      Session := Budgets.Current_Session (Budget);
      Hooks.Source_Allocation_Counts (PA0, PR0, NA0, NR0, OA0, OR0);
      declare
         Value  : Parsed_List (Budget'Access);
         Status : Parse_Status := Parse_Succeeded;
      begin
         Parse (Minimal, Session, Minimal'Length, P2'Length, 4, Value, Status);
         Require (Status = Parse_Succeeded, "payload release-failure setup failed");
         Hooks.Arm_Source_Failure (Hooks.Source_Payload_Release);
      end;
      Hooks.Source_Allocation_Counts (PA1, PR1, NA1, NR1, OA1, OR1);
      Require
        (Budgets.Current_State (Budget) = Budgets.Failed,
         "payload finalization failure did not poison budget");
      Require
        (PA1 = PA0 + 4
         and then PR1 = PR0 + 4
         and then NA1 = NA0 + 4
         and then NR1 = NR0 + 4
         and then OA1 = OA0 + 1
         and then OR1 = OR0 + 1,
         "payload finalization failure did not release exact ownership");
   end;

   declare
      Shifted  : constant String (10 .. 10 + Minimal'Length - 1) := Minimal;
      Budget   : aliased Budgets.Budget;
      Value    : Parsed_List (Budget'Access);
      Session  : Budgets.Session_Tag;
      Status   : Parse_Status := Parse_Succeeded;
   begin
      Initialize_Budget (Budget, Interfaces.Unsigned_64'Last);
      Session := Budgets.Current_Session (Budget);
      Parse (Shifted, Session, Shifted'Length, P2'Length, 4, Value, Status);
      Require (Status = Parse_Succeeded, "arbitrary-bound source list was rejected");
      Require_Work (Budget, Parse_Work);
   end;

   declare
      Shifted  : constant String
        (Positive'Last - Minimal'Length + 1 .. Positive'Last) := Minimal;
      Budget   : aliased Budgets.Budget;
      Value    : Parsed_List (Budget'Access);
      Session  : Budgets.Session_Tag;
      Status   : Parse_Status := Parse_Succeeded;
   begin
      Initialize_Budget (Budget, Interfaces.Unsigned_64'Last);
      Session := Budgets.Current_Session (Budget);
      Parse (Shifted, Session, Shifted'Length, P2'Length, 4, Value, Status);
      Require (Status = Parse_Succeeded, "Positive'Last-ended source list was rejected");
      Require_Work (Budget, Parse_Work);
   end;

   if Ada.Command_Line.Argument_Count = 1 then
      declare
         Tracked : constant String := Read_File (Ada.Command_Line.Argument (1));
      begin
         Check_Parse (Tracked, Parse_Succeeded, "tracked provenance list was rejected");
      end;
   else
      Require (Ada.Command_Line.Argument_Count = 0, "unexpected source-list test arguments");
   end if;
end Flyology_Serde_Generator.Build_Attestations.Source_Lists.Test;
