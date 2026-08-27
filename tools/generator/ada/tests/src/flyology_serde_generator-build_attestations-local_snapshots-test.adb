with Ada.Command_Line;
with Ada.Streams.Stream_IO;
with Interfaces;

with Flyology_Serde_Generator.Build_SHA_256;
with Flyology_Serde_Generator.Build_Attestation_Test_Hooks;

procedure Flyology_Serde_Generator.Build_Attestations.Local_Snapshots.Test is
   package IO renames Ada.Streams.Stream_IO;
   package SHA_256 renames Flyology_Serde_Generator.Build_SHA_256;
   package Hooks renames Flyology_Serde_Generator.Build_Attestation_Test_Hooks;

   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Array;
   use type Ada.Streams.Stream_Element_Offset;
   use type Budgets.Budget_State;
   use type Interfaces.Unsigned_64;

   Test_Block_Bytes : constant Interfaces.Unsigned_64 := 4_096;
   Long_Path : constant String :=
     "long_abcdefghijklmnopqrstuvwxyz_abcdefghijklmnopqrstuvwxyz_" &
     "abcdefghijklmnopqrstuvwxyz_abcdefghijklmnop.bin";

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   function Read_File (Path : String) return Ada.Streams.Stream_Element_Array is
      File : IO.File_Type;
   begin
      IO.Open (File, IO.In_File, Path);
      declare
         Length : constant IO.Count := IO.Size (File);
         Data   : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Length));
         Last   : Ada.Streams.Stream_Element_Offset;
      begin
         IO.Read (File, Data, Last);
         Require
           ((Data'Length = 0 and then Last = Data'First - 1)
            or else Last = Data'Last,
            "snapshot fixture short read");
         IO.Close (File);
         return Data;
      end;
   end Read_File;

   procedure Initialize_Budget
     (Value : in out Budgets.Budget;
      Work  : Budgets.Limit_Value := Interfaces.Unsigned_64'Last;
      Input : Budgets.Limit_Value := Interfaces.Unsigned_64'Last)
   is
      Initialized : Boolean := False;
   begin
      Budgets.Initialize
        ((Maximum_Input_Bytes => Input,
          Maximum_Work_Units  => Work),
         Value,
         Initialized);
      Require (Initialized, "snapshot budget initialization failed");
   end Initialize_Budget;

   function Work (Value : Budgets.Budget) return Interfaces.Unsigned_64 is
     (Budgets.Current_Usage (Value).Work_Units);

   type Ownership_Counts is record
      Descriptors_Attached : Natural;
      Descriptors_Released : Natural;
      Blocks_Allocated     : Natural;
      Blocks_Released      : Natural;
      Paths_Allocated      : Natural;
      Paths_Released       : Natural;
      Payloads_Allocated   : Natural;
      Payloads_Released    : Natural;
   end record;

   procedure Read_Ownership_Counts (Into : out Ownership_Counts) is
   begin
      Hooks.Snapshot_Descriptor_Counts
        (Into.Descriptors_Attached, Into.Descriptors_Released);
      Hooks.Snapshot_Allocation_Counts
        (Into.Blocks_Allocated, Into.Blocks_Released,
         Into.Paths_Allocated, Into.Paths_Released,
         Into.Payloads_Allocated, Into.Payloads_Released);
   end Read_Ownership_Counts;

   procedure Require_Balanced_Delta
     (Before : Ownership_Counts;
      After  : Ownership_Counts;
      Message : String) is
   begin
      Require
        (After.Descriptors_Attached - Before.Descriptors_Attached =
           After.Descriptors_Released - Before.Descriptors_Released
         and then After.Blocks_Allocated - Before.Blocks_Allocated =
           After.Blocks_Released - Before.Blocks_Released
         and then After.Paths_Allocated - Before.Paths_Allocated =
           After.Paths_Released - Before.Paths_Released
         and then After.Payloads_Allocated - Before.Payloads_Allocated =
           After.Payloads_Released - Before.Payloads_Released,
         Message);
   end Require_Balanced_Delta;

   procedure Reset_Failures is
   begin
      Hooks.Reset_Snapshot_Failures;
      Require (Hooks.Snapshot_Failures_Clear, "snapshot failure reset did not clear every point");
   end Reset_Failures;

   procedure Require_Consumed
     (Point : Hooks.Snapshot_Failure_Point;
      Message : String) is
   begin
      Require
        (Hooks.Snapshot_Failure_Remaining (Point) = 0,
         Message & ":" & Natural'Image (Hooks.Snapshot_Failure_Remaining (Point)));
   end Require_Consumed;

   function Expected_Digest
     (Data : Ada.Streams.Stream_Element_Array) return SHA_256.Hex_Digest
   is
      Context : SHA_256.Context;
      Binary  : SHA_256.Digest := [others => 0];
      Ready   : Boolean := False;
   begin
      SHA_256.Initialize (Context);
      SHA_256.Update (Context, Data);
      SHA_256.Finish (Context, Binary, Ready);
      Require (Ready, "snapshot fixture digest failed");
      return SHA_256.To_Hex (Binary);
   end Expected_Digest;

   procedure Capture_Expected
     (Root_Value    : in out Root;
      Session       : Budgets.Session_Tag;
      Relative_Path : String;
      Snapshot      : in out File_Snapshot;
      Expected      : Ada.Streams.Stream_Element_Array;
      Budget        : in out Budgets.Budget)
   is
      Status       : Capture_Status := Capture_Succeeded;
      Length       : Interfaces.Unsigned_64 := Interfaces.Unsigned_64'Last;
      Query        : Query_Status := Query_Succeeded;
      Before_Query : Interfaces.Unsigned_64;
   begin
      Capture (Root_Value, Relative_Path, Session, Snapshot, Status);
      Require (Status = Capture_Succeeded, "valid snapshot capture failed:" & Status'Image);

      Before_Query := Work (Budget);
      Read_Byte_Length (Snapshot, Session, Length, Query);
      Require (Query = Query_Succeeded, "snapshot byte-length query failed");
      Require (Length = Interfaces.Unsigned_64 (Expected'Length), "snapshot byte length changed");
      Require (Work (Budget) = Before_Query + 1, "snapshot length query charge changed");
   end Capture_Expected;

   procedure Check_Large
     (Root_Path  : String;
      Root_Value : in out Root;
      Session    : Budgets.Session_Tag;
      Snapshot   : in out File_Snapshot;
      Budget     : in out Budgets.Budget)
   is
      Expected : constant Ada.Streams.Stream_Element_Array :=
        Read_File (Root_Path & "/large.bin");
      Output : Ada.Streams.Stream_Element_Array
        (101 .. 100 + Ada.Streams.Stream_Element_Offset (Expected'Length)) :=
          [others => 16#EE#];
      Written : Interfaces.Unsigned_64 := Interfaces.Unsigned_64'Last;
      Complete : Boolean := False;
      Query    : Query_Status := Query_Succeeded;
      Before   : Interfaces.Unsigned_64;
      Visits   : Interfaces.Unsigned_64;
      Path_Length : Interfaces.Unsigned_64 := 0;
      Path_Buffer : String (20 .. 40) := [others => '?'];
      Digest_Length : Interfaces.Unsigned_64 := 0;
      Digest_Buffer : String (50 .. 120) := [others => '?'];
      Digest_Written : Interfaces.Unsigned_64 := 0;
      Expected_Hash : constant SHA_256.Hex_Digest := Expected_Digest (Expected);
      Partial : Ada.Streams.Stream_Element_Array (200 .. 209) := [others => 16#DD#];
      Null_Output : Ada.Streams.Stream_Element_Array (1 .. 0) := [];
      Preserved_Written : Interfaces.Unsigned_64;
      Preserved_Complete : Boolean;
      type Offset_Array is array (Positive range <>) of Interfaces.Unsigned_64;
      Offsets : constant Offset_Array :=
        [0, Test_Block_Bytes - 1, Test_Block_Bytes,
         Test_Block_Bytes + 1, Interfaces.Unsigned_64 (Expected'Length) - 1];
   begin
      Require (Expected'Length > 4_096, "large snapshot fixture is too short");
      Capture_Expected
        (Root_Value, Session, "large.bin", Snapshot, Expected, Budget);

      Before := Work (Budget);
      Copy_Bytes (Snapshot, Session, 0, Output, Written, Complete, Query);
      Visits :=
        1 + (Interfaces.Unsigned_64 (Expected'Length) - 1) / Test_Block_Bytes;
      Require (Query = Query_Succeeded, "large snapshot copy failed:" & Query'Image);
      Require (Written = Interfaces.Unsigned_64 (Expected'Length), "large copy count changed");
      Require (Complete, "large snapshot copy was not complete");
      Require (Output = Expected, "large snapshot bytes changed");
      Require
        (Work (Budget) = Before + 1 + Visits + 2 * Written,
         "large snapshot copy charge changed");

      Written := 0;
      Complete := True;
      Query := Query_Succeeded;
      Before := Work (Budget);
      Copy_Bytes (Snapshot, Session, 4_093, Partial, Written, Complete, Query);
      Require (Query = Query_Succeeded and then Written = 10, "cross-block copy failed");
      Require (not Complete, "partial cross-block copy reported complete");
      Require
        (Partial = Expected (Expected'First + 4_093 .. Expected'First + 4_102),
         "cross-block bytes changed");
      Require (Work (Budget) = Before + 1 + 2 + 20, "cross-block copy charge changed");

      for Offset of Offsets loop
         declare
            Single : Ada.Streams.Stream_Element_Array
              (Ada.Streams.Stream_Element_Offset (Positive'Last)
               .. Ada.Streams.Stream_Element_Offset (Positive'Last)) := [16#CC#];
         begin
            Written := 0;
            Complete := False;
            Query := Query_Succeeded;
            Copy_Bytes (Snapshot, Session, Offset, Single, Written, Complete, Query);
            Require
              (Query = Query_Succeeded and then Written = 1
               and then Single (Single'First) =
                 Expected (Expected'First + Ada.Streams.Stream_Element_Offset (Offset)),
               "snapshot boundary byte changed:" & Offset'Image);
            Require
              (Complete = (Offset + 1 = Interfaces.Unsigned_64 (Expected'Length)),
               "snapshot boundary completion changed:" & Offset'Image);
         end;
      end loop;

      Written := 91;
      Complete := True;
      Query := Query_Succeeded;
      Before := Work (Budget);
      Copy_Bytes (Snapshot, Session, 0, Null_Output, Written, Complete, Query);
      Require (Query = Query_Output_Too_Small, "null byte output was accepted");
      Require (Written = 91 and then Complete, "null byte output changed scalar outputs");
      Require (Work (Budget) = Before + 1, "null byte output charged beyond its probe");

      Preserved_Written := Written;
      Preserved_Complete := Complete;
      Query := Query_Succeeded;
      Copy_Bytes
        (Snapshot, Session, Interfaces.Unsigned_64 (Expected'Length), Partial,
         Written, Complete, Query);
      Require (Query = Query_End_Of_Bytes, "end byte offset was accepted");
      Require
        (Written = Preserved_Written and then Complete = Preserved_Complete,
         "end byte offset changed outputs");

      Query := Query_Succeeded;
      Copy_Bytes
        (Snapshot, Session, Interfaces.Unsigned_64 (Expected'Length) + 1, Partial,
         Written, Complete, Query);
      Require (Query = Query_Invalid_Offset, "invalid byte offset was accepted");
      Require
        (Written = Preserved_Written and then Complete = Preserved_Complete,
         "invalid byte offset changed outputs");

      Query := Query_Succeeded;
      Read_Path_Length (Snapshot, Session, Path_Length, Query);
      Require (Query = Query_Succeeded and then Path_Length = 9, "snapshot path length changed");
      Query := Query_Succeeded;
      Copy_Path (Snapshot, Session, Path_Buffer, Written, Query);
      Require (Query = Query_Succeeded and then Written = 9, "snapshot path copy failed");
      Require (Path_Buffer (20 .. 28) = "large.bin", "snapshot path bytes changed");
      Require (Path_Buffer (29) = '?', "snapshot path copy exceeded its prefix");

      declare
         Short_Path : String (1 .. 8) := [others => '!'];
         Short_Written : Interfaces.Unsigned_64 := 88;
      begin
         Query := Query_Succeeded;
         Copy_Path (Snapshot, Session, Short_Path, Short_Written, Query);
         Require (Query = Query_Output_Too_Small, "short path buffer was accepted");
         Require
           (Short_Path = [1 .. 8 => '!'] and then Short_Written = 88,
            "short path failure changed outputs");
      end;

      Query := Query_Succeeded;
      Read_Digest_Length (Snapshot, Session, Digest_Length, Query);
      Require
        (Query = Query_Succeeded and then Digest_Length = SHA_256.Hex_Digest'Length,
         "snapshot digest length changed");
      Query := Query_Succeeded;
      Copy_Digest (Snapshot, Session, Digest_Buffer, Digest_Written, Query);
      Require
        (Query = Query_Succeeded and then Digest_Written = SHA_256.Hex_Digest'Length,
         "snapshot digest copy failed");
      Require
        (Digest_Buffer (50 .. 113) = Expected_Hash,
         "snapshot digest changed");
      Require (Digest_Buffer (114) = '?', "snapshot digest copy exceeded its prefix");

      declare
         Short_Digest : String (1 .. 63) := [others => '!'];
         Short_Written : Interfaces.Unsigned_64 := 99;
      begin
         Query := Query_Succeeded;
         Copy_Digest (Snapshot, Session, Short_Digest, Short_Written, Query);
         Require (Query = Query_Output_Too_Small, "short digest buffer was accepted");
         Require
           (Short_Digest = [1 .. 63 => '!'] and then Short_Written = 99,
            "short digest failure changed outputs");
      end;
   end Check_Large;

   procedure Check_Copy_Denial
     (Root_Path       : String;
      Maximum_Work    : Budgets.Limit_Value;
      Expected_Usage  : Interfaces.Unsigned_64;
      Expected_Status : Query_Status;
      Message         : String)
   is
      Budget    : aliased Budgets.Budget;
      Session   : Budgets.Session_Tag;
      Root_Value : Root (Budget'Access);
      Snapshot  : File_Snapshot (Budget'Access);
      Root_State : Root_Status := Root_Succeeded;
      Capture_State : Capture_Status := Capture_Succeeded;
      Output    : Ada.Streams.Stream_Element_Array (1 .. 10) := [others => 16#A5#];
      Written   : Interfaces.Unsigned_64 := 55;
      Complete  : Boolean := True;
      Query     : Query_Status := Query_Succeeded;
   begin
      Initialize_Budget (Budget, Maximum_Work);
      Session := Budgets.Current_Session (Budget);
      Open_Root
        (Root_Path, Session, 4_096, 32, 1_048_576, 2_097_152,
         Root_Value, Root_State);
      Require (Root_State = Root_Succeeded, Message & " root setup failed");
      Capture (Root_Value, "large.bin", Session, Snapshot, Capture_State);
      Require (Capture_State = Capture_Succeeded, Message & " capture setup failed");
      Copy_Bytes (Snapshot, Session, 4_093, Output, Written, Complete, Query);
      Require (Query = Expected_Status, Message & " status changed:" & Query'Image);
      Require
        (Output = [1 .. 10 => 16#A5#] and then Written = 55 and then Complete,
         Message & " changed caller outputs");
      Require (Work (Budget) = Expected_Usage, Message & " usage changed");
      Require (Budgets.Current_State (Budget) = Budgets.Exhausted, Message & " did not exhaust");
   end Check_Copy_Denial;

   procedure Check_Empty
     (Root_Value : in out Root;
      Session    : Budgets.Session_Tag;
      Snapshot   : in out File_Snapshot;
      Budget     : in out Budgets.Budget)
   is
      Expected : constant Ada.Streams.Stream_Element_Array (1 .. 0) := [];
      Output   : Ada.Streams.Stream_Element_Array
        (Ada.Streams.Stream_Element_Offset (Positive'Last)
         .. Ada.Streams.Stream_Element_Offset (Positive'Last)) := [16#AA#];
      Written  : Interfaces.Unsigned_64 := 77;
      Complete : Boolean := True;
      Query    : Query_Status := Query_Succeeded;
   begin
      Capture_Expected
        (Root_Value, Session, "empty.bin", Snapshot, Expected, Budget);
      Copy_Bytes (Snapshot, Session, 0, Output, Written, Complete, Query);
      Require (Query = Query_End_Of_Bytes, "empty snapshot did not report end");
      Require
        (Output (Output'First) = 16#AA# and then Written = 77 and then Complete,
         "empty snapshot query changed outputs");
   end Check_Empty;

   procedure Check_Rejections
     (Root_Value : in out Root;
      Session    : Budgets.Session_Tag;
      Budget     : aliased in out Budgets.Budget)
   is
      Snapshot : File_Snapshot (Budget'Access);
      Status   : Capture_Status;

      procedure Reject (Path : String; Expected : Capture_Status; Message : String) is
      begin
         Status := Capture_Succeeded;
         Capture (Root_Value, Path, Session, Snapshot, Status);
         Require (Status = Expected, Message & ":" & Status'Image);
      end Reject;
   begin
      Reject ("", Capture_Invalid_Path, "empty relative path accepted");
      Reject ("/large.bin", Capture_Invalid_Path, "absolute path accepted");
      Reject ("../large.bin", Capture_Invalid_Path, "parent path accepted");
      Reject ("nested//file.bin", Capture_Invalid_Path, "empty component accepted");
      Reject ("directory", Capture_Not_Regular, "directory accepted as regular file");
      Reject ("link.bin", Capture_Open_Failed, "final symlink was followed");
      Reject ("directory-link/file.bin", Capture_Open_Failed, "intermediate symlink was followed");
      Reject ("fifo", Capture_Not_Regular, "FIFO accepted as regular file");
   end Check_Rejections;

   procedure Check_Open_Faults (Root_Path : String) is
      procedure Check
        (Point      : Hooks.Snapshot_Failure_Point;
         Expected   : Root_Status;
         Occurrence : Positive := 1;
         Poisoned   : Boolean := False)
      is
         Before, After : Ownership_Counts;
      begin
         Reset_Failures;
         Read_Ownership_Counts (Before);
         declare
            Budget     : aliased Budgets.Budget;
            Session    : Budgets.Session_Tag;
            Root_Value : Root (Budget'Access);
            Status     : Root_Status := Root_Succeeded;
         begin
            Initialize_Budget (Budget);
            Session := Budgets.Current_Session (Budget);
            Hooks.Arm_Snapshot_Failure (Point, Occurrence);
            Open_Root
              (Root_Path, Session, 4_096, 32, 1_048_576, 2_097_152,
               Root_Value, Status);
            Require (Status = Expected, "root fault status changed:" & Status'Image);
            Require_Consumed (Point, "root fault occurrence was not consumed");
            Require
              ((Budgets.Current_State (Budget) = Budgets.Failed) = Poisoned,
               "root fault poison state changed:" & Point'Image);
            if not Poisoned and then Expected /= Root_Succeeded then
               Status := Root_Succeeded;
               Open_Root
                 (Root_Path, Session, 4_096, 32, 1_048_576, 2_097_152,
                  Root_Value, Status);
               Require
                 (Status = Root_Succeeded,
                  "normally failed root call published or damaged its owner:" & Status'Image);
            end if;
         end;
         Read_Ownership_Counts (After);
         Require_Balanced_Delta (Before, After, "root fault leaked snapshot ownership");
         Require (Hooks.Snapshot_Failures_Clear, "root fault left an armed occurrence");
      end Check;

      function Measure_Open (Inject : Boolean) return Interfaces.Unsigned_64 is
         Before, After : Ownership_Counts;
         Total_Work    : Interfaces.Unsigned_64 := 0;
      begin
         Reset_Failures;
         Read_Ownership_Counts (Before);
         declare
            Budget     : aliased Budgets.Budget;
            Session    : Budgets.Session_Tag;
            Root_Value : Root (Budget'Access);
            Status     : Root_Status := Root_Succeeded;
         begin
            Initialize_Budget (Budget);
            Session := Budgets.Current_Session (Budget);
            if Inject then
               Hooks.Arm_Snapshot_Failure (Hooks.Snapshot_Open_Interrupted);
            end if;
            Open_Root
              (Root_Path, Session, 4_096, 32, 1_048_576, 2_097_152,
               Root_Value, Status);
            Require (Status = Root_Succeeded, "root retry accounting setup failed");
            if Inject then
               Require_Consumed
                 (Hooks.Snapshot_Open_Interrupted, "root open interruption remained armed");
            end if;
            Total_Work := Work (Budget);
         end;
         Read_Ownership_Counts (After);
         Require_Balanced_Delta (Before, After, "root retry accounting leaked ownership");
         Require (Hooks.Snapshot_Failures_Clear, "root retry accounting left an armed occurrence");
         return Total_Work;
      end Measure_Open;
   begin
      Check (Hooks.Snapshot_Open_Interrupted, Root_Succeeded);
      Check (Hooks.Snapshot_Open_Failed, Root_Open_Failed);
      Check (Hooks.Snapshot_Identity_Failed, Root_Identity_Failed);
      Check (Hooks.Snapshot_Payload_Storage, Root_Allocation_Failed, Poisoned => True);
      declare
         Before, After : Ownership_Counts;
      begin
         Reset_Failures;
         Read_Ownership_Counts (Before);
         declare
            Budget     : aliased Budgets.Budget;
            Session    : Budgets.Session_Tag;
            Root_Value : Root (Budget'Access);
            Status     : Root_Status := Root_Succeeded;
         begin
            Initialize_Budget (Budget);
            Session := Budgets.Current_Session (Budget);
            Hooks.Arm_Snapshot_Failure (Hooks.Snapshot_Identity_Failed);
            Hooks.Arm_Snapshot_Failure (Hooks.Snapshot_Close_Failed);
            Open_Root
              (Root_Path, Session, 4_096, 32, 1_048_576, 2_097_152,
               Root_Value, Status);
            Require (Status = Root_Identity_Failed, "root cleanup replaced its primary status");
            Require (Budgets.Current_State (Budget) = Budgets.Failed,
                     "root close damage did not poison the matching session");
            Require_Consumed
              (Hooks.Snapshot_Identity_Failed, "root primary identity fault remained armed");
            Require_Consumed
              (Hooks.Snapshot_Close_Failed, "root secondary close fault remained armed");
         end;
         Read_Ownership_Counts (After);
         Require_Balanced_Delta (Before, After, "root cleanup-primary case leaked ownership");
         Require (Hooks.Snapshot_Failures_Clear, "root cleanup-primary left an armed occurrence");
      end;

      declare
         Baseline : constant Interfaces.Unsigned_64 := Measure_Open (False);
         Retried  : constant Interfaces.Unsigned_64 := Measure_Open (True);
         Before, After : Ownership_Counts;
      begin
         Require (Retried = Baseline + 1, "root open EINTR retry charge changed");
         Reset_Failures;
         Read_Ownership_Counts (Before);
         declare
            Budget     : aliased Budgets.Budget;
            Session    : Budgets.Session_Tag;
            Root_Value : Root (Budget'Access);
            Status     : Root_Status := Root_Succeeded;
         begin
            Initialize_Budget (Budget, Retried - 1);
            Session := Budgets.Current_Session (Budget);
            Hooks.Arm_Snapshot_Failure (Hooks.Snapshot_Open_Interrupted);
            Open_Root
              (Root_Path, Session, 4_096, 32, 1_048_576, 2_097_152,
               Root_Value, Status);
            Require (Status = Root_Budget_Exhausted, "one-less root retry budget was accepted");
            Require (Work (Budget) = Retried - 1, "root retry denial work debit changed");
            Require_Consumed
              (Hooks.Snapshot_Open_Interrupted, "root retry-denial occurrence remained armed");
         end;
         Read_Ownership_Counts (After);
         Require_Balanced_Delta (Before, After, "root retry denial leaked ownership");
         Require (Hooks.Snapshot_Failures_Clear, "root retry denial left an armed occurrence");
      end;
   end Check_Open_Faults;

   procedure Check_Capture_Faults (Root_Path : String) is
      Length : constant Interfaces.Unsigned_64 :=
        Interfaces.Unsigned_64 (Read_File (Root_Path & "/large.bin")'Length);
      Baseline_Read_Attempts : constant Interfaces.Unsigned_64 :=
        (Length + Test_Block_Bytes - 1) / Test_Block_Bytes + 1;

      function Short_Read_Attempts (Occurrence : Positive) return Interfaces.Unsigned_64 is
         Prior     : constant Interfaces.Unsigned_64 :=
           Interfaces.Unsigned_64 (Occurrence - 1) * Test_Block_Bytes;
         Remaining : Interfaces.Unsigned_64;
      begin
         Require (Length > Prior + 7, "short-read occurrence exceeds the fixture's positive reads");
         Remaining := Length - Prior - 7;
         return
           Interfaces.Unsigned_64 (Occurrence)
           + (Remaining + Test_Block_Bytes - 1) / Test_Block_Bytes
           + 1;
      end Short_Read_Attempts;

      procedure Check
        (Point      : Hooks.Snapshot_Failure_Point;
         Expected   : Capture_Status;
         Occurrence : Positive := 1;
         Poisoned   : Boolean := False)
      is
         Before, After : Ownership_Counts;
      begin
         Reset_Failures;
         Read_Ownership_Counts (Before);
         declare
            Budget     : aliased Budgets.Budget;
            Session    : Budgets.Session_Tag;
            Root_Value : Root (Budget'Access);
            Snapshot   : File_Snapshot (Budget'Access);
            Root_State : Root_Status := Root_Succeeded;
            Status     : Capture_Status := Capture_Succeeded;
         begin
            Initialize_Budget (Budget);
            Session := Budgets.Current_Session (Budget);
            Open_Root
              (Root_Path, Session, 4_096, 32, Length, Length,
               Root_Value, Root_State);
            Require (Root_State = Root_Succeeded, "capture-fault root setup failed");
            Hooks.Arm_Snapshot_Failure (Point, Occurrence);
            Capture (Root_Value, "large.bin", Session, Snapshot, Status);
            Require (Status = Expected, "capture fault status changed:" & Status'Image);
            Require_Consumed (Point, "capture fault occurrence was not consumed");
            Require
              ((Budgets.Current_State (Budget) = Budgets.Failed) = Poisoned,
               "capture fault poison state changed:" & Point'Image);
            if not Poisoned then
               Status := Capture_Succeeded;
               Capture (Root_Value, "large.bin", Session, Snapshot, Status);
               Require
                 (Status = Capture_Succeeded,
                  "failed capture published its owner or aggregate:" & Status'Image);
            end if;
         end;
         Read_Ownership_Counts (After);
         Require_Balanced_Delta (Before, After, "capture fault leaked snapshot ownership");
         Require (Hooks.Snapshot_Failures_Clear, "capture fault left an armed occurrence");
      end Check;

      function Measure_Success
        (Inject     : Boolean;
         Point      : Hooks.Snapshot_Failure_Point := Hooks.Snapshot_Read_Interrupted;
         Occurrence : Positive := 1) return Interfaces.Unsigned_64
      is
         Before, After : Ownership_Counts;
         Total_Work    : Interfaces.Unsigned_64 := 0;
      begin
         Reset_Failures;
         Read_Ownership_Counts (Before);
         declare
            Budget     : aliased Budgets.Budget;
            Session    : Budgets.Session_Tag;
            Root_Value : Root (Budget'Access);
            Snapshot   : File_Snapshot (Budget'Access);
            Root_State : Root_Status := Root_Succeeded;
            Status     : Capture_Status := Capture_Succeeded;
         begin
            Initialize_Budget (Budget);
            Session := Budgets.Current_Session (Budget);
            Open_Root
              (Root_Path, Session, 4_096, 32, Length, Length,
               Root_Value, Root_State);
            Require (Root_State = Root_Succeeded, "successful fault root setup failed");
            if Inject then
               Hooks.Arm_Snapshot_Failure (Point, Occurrence);
            end if;
            Capture (Root_Value, "large.bin", Session, Snapshot, Status);
            Require (Status = Capture_Succeeded, "injected retry did not succeed:" & Status'Image);
            if Inject then
               Require_Consumed (Point, "successful retry occurrence was not consumed");
            end if;
            Total_Work := Work (Budget);
         end;
         Read_Ownership_Counts (After);
         Require_Balanced_Delta (Before, After, "successful retry leaked snapshot ownership");
         Require (Hooks.Snapshot_Failures_Clear, "successful retry left an armed occurrence");
         return Total_Work;
      end Measure_Success;

      procedure Check_One_Less_Denial
        (Point         : Hooks.Snapshot_Failure_Point;
         Occurrence    : Positive;
         Expected_Work : Interfaces.Unsigned_64)
      is
         Before, After : Ownership_Counts;
      begin
         Reset_Failures;
         Read_Ownership_Counts (Before);
         declare
            Budget     : aliased Budgets.Budget;
            Session    : Budgets.Session_Tag;
            Root_Value : Root (Budget'Access);
            Snapshot   : File_Snapshot (Budget'Access);
            Root_State : Root_Status := Root_Succeeded;
            Status     : Capture_Status := Capture_Succeeded;
         begin
            Initialize_Budget (Budget, Expected_Work - 1);
            Session := Budgets.Current_Session (Budget);
            Open_Root
              (Root_Path, Session, 4_096, 32, Length, Length,
               Root_Value, Root_State);
            Require (Root_State = Root_Succeeded, "retry-denial root setup failed");
            Hooks.Arm_Snapshot_Failure (Point, Occurrence);
            Capture (Root_Value, "large.bin", Session, Snapshot, Status);
            Require
              (Status = Capture_Budget_Exhausted,
               "one-less retry budget was accepted:" & Point'Image & Status'Image);
            Require (Work (Budget) = Expected_Work - 1, "retry denial work debit changed");
            Require_Consumed (Point, "retry-denial occurrence was not consumed");
         end;
         Read_Ownership_Counts (After);
         Require_Balanced_Delta (Before, After, "retry denial leaked snapshot ownership");
         Require (Hooks.Snapshot_Failures_Clear, "retry denial left an armed occurrence");
      end Check_One_Less_Denial;

      Baseline       : constant Interfaces.Unsigned_64 := Measure_Success (False);
      Open_First     : constant Interfaces.Unsigned_64 :=
        Measure_Success (True, Hooks.Snapshot_Open_Interrupted, 1);
      Open_Second    : constant Interfaces.Unsigned_64 :=
        Measure_Success (True, Hooks.Snapshot_Open_Interrupted, 2);
      Read_First     : constant Interfaces.Unsigned_64 :=
        Measure_Success (True, Hooks.Snapshot_Read_Interrupted, 1);
      Read_Second    : constant Interfaces.Unsigned_64 :=
        Measure_Success (True, Hooks.Snapshot_Read_Interrupted, 2);
      Short_First    : constant Interfaces.Unsigned_64 :=
        Measure_Success (True, Hooks.Snapshot_Read_Short, 1);
      Short_Second   : constant Interfaces.Unsigned_64 :=
        Measure_Success (True, Hooks.Snapshot_Read_Short, 2);
   begin
      Require
        (Open_First = Baseline + 1 and then Open_Second = Baseline + 1,
         "open EINTR retry charge changed");
      Require
        (Read_First = Baseline + 1 and then Read_Second = Baseline + 1,
         "read EINTR retry charge changed");
      Require
        (Short_First = Baseline + Short_Read_Attempts (1) - Baseline_Read_Attempts
         and then Short_Second = Baseline + Short_Read_Attempts (2) - Baseline_Read_Attempts,
         "genuine short-read attempt charge changed");
      Check_One_Less_Denial (Hooks.Snapshot_Open_Interrupted, 1, Open_First);
      Check_One_Less_Denial (Hooks.Snapshot_Read_Interrupted, 1, Read_First);
      Check_One_Less_Denial (Hooks.Snapshot_Read_Short, 1, Short_First);

      Check (Hooks.Snapshot_Open_Failed, Capture_Open_Failed, 1);
      Check (Hooks.Snapshot_Open_Failed, Capture_Open_Failed, 2);
      for Occurrence in 1 .. 5 loop
         Check (Hooks.Snapshot_Identity_Failed, Capture_Identity_Failed, Occurrence);
      end loop;
      Check (Hooks.Snapshot_Read_Failed, Capture_Read_Failed, 1);
      Check (Hooks.Snapshot_Read_Failed, Capture_Read_Failed, 2);
      Check (Hooks.Snapshot_Premature_EOF, Capture_Changed);
      Check (Hooks.Snapshot_Impossible_Positive_Result, Capture_Read_Failed);
      Check (Hooks.Snapshot_Close_Failed, Capture_Close_Failed, 1, True);
      Check (Hooks.Snapshot_Close_Failed, Capture_Close_Failed, 2, True);
      Check (Hooks.Snapshot_Block_Storage, Capture_Allocation_Failed, Poisoned => True);
      Check (Hooks.Snapshot_Path_Storage, Capture_Allocation_Failed, Poisoned => True);
      Check (Hooks.Snapshot_Payload_Storage, Capture_Allocation_Failed, Poisoned => True);
   end Check_Capture_Faults;

   procedure Check_Independent_Digest (Root_Path : String) is
      Budget       : aliased Budgets.Budget;
      Session      : Budgets.Session_Tag;
      Root_Value   : Root (Budget'Access);
      Snapshot     : File_Snapshot (Budget'Access);
      Root_State   : Root_Status := Root_Succeeded;
      Capture_State : Capture_Status := Capture_Succeeded;
      Query        : Query_Status := Query_Succeeded;
      Buffer       : String (1 .. 64) := [others => '?'];
      Written      : Interfaces.Unsigned_64 := 0;
   begin
      Initialize_Budget (Budget);
      Session := Budgets.Current_Session (Budget);
      Open_Root
        (Root_Path, Session, 4_096, 32, 1_048_576, 2_097_152,
         Root_Value, Root_State);
      Require (Root_State = Root_Succeeded, "known-answer root setup failed");
      Capture (Root_Value, "known.bin", Session, Snapshot, Capture_State);
      Require (Capture_State = Capture_Succeeded, "known-answer capture failed");
      Copy_Digest (Snapshot, Session, Buffer, Written, Query);
      Require
        (Query = Query_Succeeded and then Written = 64
         and then Buffer = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
         "snapshot SHA-256 known answer changed");
   end Check_Independent_Digest;

   procedure Check_Limits (Root_Path : String) is
      Length : constant Interfaces.Unsigned_64 :=
        Interfaces.Unsigned_64 (Read_File (Root_Path & "/large.bin")'Length);

      procedure Capture_With
        (Path_Limit      : Budgets.Limit_Value := 4_096;
         Depth_Limit     : Budgets.Limit_Value := 32;
         Per_File_Limit  : Budgets.Limit_Value := 1_048_576;
         Aggregate_Limit : Budgets.Limit_Value := 2_097_152;
         Input_Limit     : Budgets.Limit_Value := Interfaces.Unsigned_64'Last;
         Work_Limit      : Budgets.Limit_Value := Interfaces.Unsigned_64'Last;
         Path            : String := "large.bin";
         Expected        : Capture_Status)
      is
         Budget       : aliased Budgets.Budget;
         Session      : Budgets.Session_Tag;
         Root_Value   : Root (Budget'Access);
         Snapshot     : File_Snapshot (Budget'Access);
         Root_State   : Root_Status := Root_Succeeded;
         Capture_State : Capture_Status := Capture_Succeeded;
      begin
         Initialize_Budget (Budget, Work_Limit, Input_Limit);
         Session := Budgets.Current_Session (Budget);
         Open_Root
           (Root_Path, Session, Path_Limit, Depth_Limit, Per_File_Limit, Aggregate_Limit,
            Root_Value, Root_State);
         Require (Root_State = Root_Succeeded, "limit root setup failed:" & Root_State'Image);
         Capture (Root_Value, Path, Session, Snapshot, Capture_State);
         Require
           (Capture_State = Expected,
            "capture limit status changed:" & Capture_State'Image & "/" & Expected'Image
            & " aggregate" & Interfaces.Unsigned_64'Image (Aggregate_Limit)
            & " length" & Interfaces.Unsigned_64'Image (Length));
      end Capture_With;

      Read_Attempts : constant Interfaces.Unsigned_64 :=
        (Length + Test_Block_Bytes - 1) / Test_Block_Bytes + 1;
      Exact_Work : constant Interfaces.Unsigned_64 :=
        Interfaces.Unsigned_64 (Root_Path'Length) + 20 + Read_Attempts + Length;
   begin
      Capture_With
        (Path_Limit => Long_Path'Length - 1, Path => Long_Path,
         Expected => Capture_Path_Limit_Exceeded);
      Capture_With
        (Path_Limit => Long_Path'Length, Path => Long_Path,
         Expected => Capture_Succeeded);
      Capture_With
        (Depth_Limit => 1, Path => "directory/x/file.bin",
         Expected => Capture_Directory_Depth_Exceeded);
      Capture_With
        (Depth_Limit => 1, Path => "directory/file.bin", Expected => Capture_Succeeded);
      Capture_With (Per_File_Limit => Length - 1,
                    Expected => Capture_Per_File_Limit_Exceeded);
      Capture_With (Per_File_Limit => Length, Expected => Capture_Succeeded);
      Capture_With (Aggregate_Limit => Length - 1,
                    Expected => Capture_Aggregate_Limit_Exceeded);
      Capture_With (Aggregate_Limit => Length, Expected => Capture_Succeeded);
      Capture_With (Input_Limit => Length - 1, Expected => Capture_Budget_Exhausted);
      Capture_With (Input_Limit => Length, Expected => Capture_Succeeded);
      Capture_With (Work_Limit => Exact_Work - 1, Expected => Capture_Budget_Exhausted);
      Capture_With (Work_Limit => Exact_Work, Expected => Capture_Succeeded);

      declare
         Budget        : aliased Budgets.Budget;
         Session       : Budgets.Session_Tag;
         Root_Value    : Root (Budget'Access);
         Large         : File_Snapshot (Budget'Access);
         Empty         : File_Snapshot (Budget'Access);
         Extra         : File_Snapshot (Budget'Access);
         Root_State    : Root_Status := Root_Succeeded;
         Large_State   : Capture_Status := Capture_Succeeded;
         Empty_State   : Capture_Status := Capture_Succeeded;
         Extra_State   : Capture_Status := Capture_Succeeded;
      begin
         Reset_Failures;
         Initialize_Budget (Budget);
         Session := Budgets.Current_Session (Budget);
         Open_Root
           (Root_Path, Session, 4_096, 32, Length, Length, Root_Value, Root_State);
         Capture (Root_Value, "large.bin", Session, Large, Large_State);
         Capture (Root_Value, "empty.bin", Session, Empty, Empty_State);
         Capture (Root_Value, "known.bin", Session, Extra, Extra_State);
         Require
           (Root_State = Root_Succeeded
            and then Large_State = Capture_Succeeded
            and then Empty_State = Capture_Succeeded
            and then Extra_State = Capture_Aggregate_Limit_Exceeded,
            "aggregate equality/empty-file behavior changed");
      end;
   end Check_Limits;

   procedure Check_Prior_Owner (Root_Path : String) is
      Before, After : Ownership_Counts;
   begin
      Reset_Failures;
      Read_Ownership_Counts (Before);
      declare
         Budget        : aliased Budgets.Budget;
         Session       : Budgets.Session_Tag;
         Root_Value    : Root (Budget'Access);
         Snapshot      : File_Snapshot (Budget'Access);
         Root_State    : Root_Status := Root_Succeeded;
         Capture_State : Capture_Status := Capture_Succeeded;
         Query         : Query_Status := Query_Succeeded;
         Path          : String (11 .. 19) := [others => '?'];
         Written       : Interfaces.Unsigned_64 := 0;
         Before_Work   : Interfaces.Unsigned_64;
      begin
         Initialize_Budget (Budget);
         Session := Budgets.Current_Session (Budget);
         Open_Root
           (Root_Path, Session, 4_096, 32, 1_048_576, 2_097_152,
            Root_Value, Root_State);
         Capture (Root_Value, "known.bin", Session, Snapshot, Capture_State);
         Require
           (Root_State = Root_Succeeded and then Capture_State = Capture_Succeeded,
            "prior-owner setup failed");
         Before_Work := Work (Budget);
         Capture_State := Capture_Succeeded;
         Capture (Root_Value, "large.bin", Session, Snapshot, Capture_State);
         Require
           (Capture_State = Capture_Owner_Not_Empty,
            "capture replacement did not reject its nonempty owner");
         Require (Work (Budget) = Before_Work, "nonempty-owner rejection consumed work");
         Copy_Path (Snapshot, Session, Path, Written, Query);
         Require
           (Query = Query_Succeeded and then Written = 9 and then Path = "known.bin",
            "failed replacement changed the retained snapshot");
      end;
      Read_Ownership_Counts (After);
      Require_Balanced_Delta (Before, After, "prior-owner test leaked snapshot ownership");
   end Check_Prior_Owner;

   procedure Check_Copy_Faults (Root_Path : String) is
      procedure Check
        (Point    : Hooks.Snapshot_Failure_Point;
         Expected : Query_Status;
         Poisoned : Boolean)
      is
         Budget       : aliased Budgets.Budget;
         Session      : Budgets.Session_Tag;
         Root_Value   : Root (Budget'Access);
         Snapshot     : File_Snapshot (Budget'Access);
         Root_State   : Root_Status := Root_Succeeded;
         Capture_State : Capture_Status := Capture_Succeeded;
         Query        : Query_Status := Query_Succeeded;
         Output       : Ada.Streams.Stream_Element_Array (1 .. 10) := [others => 16#5A#];
         Written      : Interfaces.Unsigned_64 := 44;
         Complete     : Boolean := True;
      begin
         Reset_Failures;
         Initialize_Budget (Budget);
         Session := Budgets.Current_Session (Budget);
         Open_Root
           (Root_Path, Session, 4_096, 32, 1_048_576, 2_097_152,
            Root_Value, Root_State);
         Require (Root_State = Root_Succeeded, "copy-fault root setup failed");
         Capture (Root_Value, "large.bin", Session, Snapshot, Capture_State);
         Require (Capture_State = Capture_Succeeded, "copy-fault capture setup failed");
         Hooks.Arm_Snapshot_Failure (Point);
         Copy_Bytes (Snapshot, Session, 0, Output, Written, Complete, Query);
         Require (Query = Expected, "copy fault status changed:" & Query'Image);
         Require_Consumed (Point, "copy fault occurrence was not consumed");
         Require
           (Output = [1 .. 10 => 16#5A#] and then Written = 44 and then Complete,
            "copy fault changed caller outputs");
         Require
           ((Budgets.Current_State (Budget) = Budgets.Failed) = Poisoned,
            "copy fault poison state changed");
         Require (Hooks.Snapshot_Failures_Clear, "copy fault left an armed occurrence");
      end Check;
   begin
      Check (Hooks.Snapshot_Copy_Storage, Query_Allocation_Failed, False);
      Check (Hooks.Snapshot_Copy_Invariant, Query_Internal_Failure, True);
   end Check_Copy_Faults;

   procedure Check_Cleanup (Root_Path : String) is
      procedure Check_Release_Fault (Point : Hooks.Snapshot_Failure_Point) is
         Before, After : Ownership_Counts;
         Budget        : aliased Budgets.Budget;
         Session       : Budgets.Session_Tag;
      begin
         Reset_Failures;
         Read_Ownership_Counts (Before);
         Initialize_Budget (Budget);
         Session := Budgets.Current_Session (Budget);
         declare
            Root_Value   : Root (Budget'Access);
            Snapshot     : File_Snapshot (Budget'Access);
            Root_State   : Root_Status := Root_Succeeded;
            Capture_State : Capture_Status := Capture_Succeeded;
         begin
            Open_Root
              (Root_Path, Session, 4_096, 32, 1_048_576, 2_097_152,
               Root_Value, Root_State);
            Capture (Root_Value, "large.bin", Session, Snapshot, Capture_State);
            Require
              (Root_State = Root_Succeeded and then Capture_State = Capture_Succeeded,
               "cleanup-fault setup failed");
            Hooks.Arm_Snapshot_Failure (Point);
         end;
         Read_Ownership_Counts (After);
         Require_Balanced_Delta
           (Before, After, "cleanup fault stopped before releasing every owned object");
         Require (Budgets.Current_State (Budget) = Budgets.Failed,
                  "matching-session cleanup damage did not poison");
         Require_Consumed (Point, "cleanup fault occurrence was not consumed");
         Require (Hooks.Snapshot_Failures_Clear, "cleanup fault left an armed occurrence");
      end Check_Release_Fault;

      Before, After : Ownership_Counts;
      Budget        : aliased Budgets.Budget;
      Session       : Budgets.Session_Tag;
   begin
      Reset_Failures;
      Read_Ownership_Counts (Before);
      Initialize_Budget (Budget);
      Session := Budgets.Current_Session (Budget);
      declare
         Root_Value   : Root (Budget'Access);
         Snapshot     : File_Snapshot (Budget'Access);
         Root_State   : Root_Status := Root_Succeeded;
         Capture_State : Capture_Status := Capture_Succeeded;
      begin
         Open_Root
           (Root_Path, Session, 4_096, 32, 1_048_576, 2_097_152,
            Root_Value, Root_State);
         Require (Root_State = Root_Succeeded, "cleanup root setup failed");
         Capture (Root_Value, "large.bin", Session, Snapshot, Capture_State);
         Require (Capture_State = Capture_Succeeded, "cleanup capture setup failed");
      end;
      Read_Ownership_Counts (After);
      Require_Balanced_Delta (Before, After, "snapshot cleanup ownership counts diverged");

      Check_Release_Fault (Hooks.Snapshot_Block_Release);
      Check_Release_Fault (Hooks.Snapshot_Path_Release);
      Check_Release_Fault (Hooks.Snapshot_Payload_Release);

      Reset_Failures;
      Read_Ownership_Counts (Before);
      Initialize_Budget (Budget);
      Session := Budgets.Current_Session (Budget);
      declare
         Root_Value   : Root (Budget'Access);
         Snapshot     : File_Snapshot (Budget'Access);
         Root_State   : Root_Status := Root_Succeeded;
         Capture_State : Capture_Status := Capture_Succeeded;
         Reinitialized : Boolean := False;
      begin
         Open_Root
           (Root_Path, Session, 4_096, 32, 1_048_576, 2_097_152,
            Root_Value, Root_State);
         Capture (Root_Value, "large.bin", Session, Snapshot, Capture_State);
         Require
           (Root_State = Root_Succeeded and then Capture_State = Capture_Succeeded,
            "stale-cleanup setup failed");
         Hooks.Arm_Snapshot_Failure (Hooks.Snapshot_Block_Release);
         Budgets.Initialize
           ((Maximum_Input_Bytes => Interfaces.Unsigned_64'Last,
             Maximum_Work_Units  => Interfaces.Unsigned_64'Last),
            Budget, Reinitialized);
         Require (Reinitialized, "stale-cleanup budget reinitialization failed");
      end;
      Read_Ownership_Counts (After);
      Require_Balanced_Delta (Before, After, "stale-session cleanup leaked ownership");
      Require (Budgets.Current_State (Budget) = Budgets.Active,
               "stale cleanup poisoned the replacement session");
      Require_Consumed
        (Hooks.Snapshot_Block_Release, "stale cleanup release occurrence was not consumed");
      Require (Hooks.Snapshot_Failures_Clear, "stale cleanup left an armed occurrence");
   end Check_Cleanup;

   Root_Path : constant String := Ada.Command_Line.Argument (1);
   Budget    : aliased Budgets.Budget;
   Session   : Budgets.Session_Tag;
begin
   Require (Ada.Command_Line.Argument_Count = 1, "snapshot test requires its fixture root");
   Check_Open_Faults (Root_Path);
   Check_Capture_Faults (Root_Path);
   Check_Independent_Digest (Root_Path);
   Check_Limits (Root_Path);
   Check_Prior_Owner (Root_Path);
   Check_Copy_Faults (Root_Path);
   Check_Cleanup (Root_Path);
   Initialize_Budget (Budget);
   Session := Budgets.Current_Session (Budget);
   declare
      Root_Value : Root (Budget'Access);
      Root_State : Root_Status := Root_Succeeded;
      Large      : File_Snapshot (Budget'Access);
      Empty      : File_Snapshot (Budget'Access);
   begin
      Open_Root
        (Root_Path, Session, 4_096, 32, 1_048_576, 2_097_152,
         Root_Value, Root_State);
      Require (Root_State = Root_Succeeded, "snapshot root open failed:" & Root_State'Image);
      Check_Large (Root_Path, Root_Value, Session, Large, Budget);
      Check_Empty (Root_Value, Session, Empty, Budget);
      Check_Rejections (Root_Value, Session, Budget);
      Require (Budgets.Current_State (Budget) = Budgets.Active, "snapshot tests poisoned budget");
   end;

   declare
      Length : constant Interfaces.Unsigned_64 :=
        Interfaces.Unsigned_64 (Read_File (Root_Path & "/large.bin")'Length);
      Read_Attempts : constant Interfaces.Unsigned_64 :=
        (Length + Test_Block_Bytes - 1) / Test_Block_Bytes + 1;
      Setup_Work : constant Interfaces.Unsigned_64 :=
        Interfaces.Unsigned_64 (Root_Path'Length) + 20 + Read_Attempts + Length;
      Probe_And_Visits : constant Interfaces.Unsigned_64 := 3;
      Copy_Count : constant Interfaces.Unsigned_64 := 10;
   begin
      Check_Copy_Denial
        (Root_Path, Setup_Work + 1, Setup_Work + 1,
         Query_Budget_Exhausted, "visit reservation denial");
      Check_Copy_Denial
        (Root_Path, Setup_Work + Probe_And_Visits,
         Setup_Work + Probe_And_Visits,
         Query_Budget_Exhausted, "staging reservation denial");
      Check_Copy_Denial
        (Root_Path, Setup_Work + Probe_And_Visits + Copy_Count,
         Setup_Work + Probe_And_Visits + Copy_Count,
         Query_Budget_Exhausted, "publication reservation denial");
   end;
end Flyology_Serde_Generator.Build_Attestations.Local_Snapshots.Test;
