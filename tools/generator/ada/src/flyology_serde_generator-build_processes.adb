with Ada.Containers.Indefinite_Vectors;
with Ada.Real_Time;
with Ada.Strings.Unbounded;
with Ada.Unchecked_Deallocation;
with Interfaces.C.Strings;
with System.Soft_Links;

with Flyology_Serde_Generator.Build_Process_ABI;
with Flyology_Serde_Generator.Build_Process_Test_Hooks;

package body Flyology_Serde_Generator.Build_Processes is
   package ABI renames Flyology_Serde_Generator.Build_Process_ABI;
   package Test_Hooks renames Flyology_Serde_Generator.Build_Process_Test_Hooks;
   package C renames Interfaces.C;
   package C_Strings renames Interfaces.C.Strings;
   package US renames Ada.Strings.Unbounded;
   package String_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Positive, Element_Type => String);

   use type ABI.C_Int;
   use type ABI.C_Long;
   use type Ada.Real_Time.Time;
   use type Ada.Real_Time.Time_Span;
   use type Budgets.Budget_State;
   use type C_Strings.chars_ptr;
   use type Interfaces.Unsigned_64;

   Invalid_Descriptor : constant ABI.Descriptor := -1;
   Fixed_Setup_Work   : constant Interfaces.Unsigned_64 := 14;

   protected body Runner_Gate is
      entry Acquire (Granted : out Boolean)
        when Damaged or else not Busy
      is
      begin
         Granted := not Damaged;
         if Granted then
            Busy := True;
         end if;
      end Acquire;

      procedure Release (Safe : Boolean) is
      begin
         if not Busy then
            Damaged := True;
         elsif not Safe then
            Damaged := True;
         end if;
         Busy := False;
      end Release;

      procedure Poison is
      begin
         Damaged := True;
      end Poison;

      function Is_Poisoned return Boolean is (Damaged);

      function Waiting_Acquirers return Natural is (Acquire'Count);
   end Runner_Gate;

   Runner_State : Runner_Gate;

   type Gate_Guard is new Ada.Finalization.Limited_Controlled with record
      Held : Boolean := False;
      Safe : Boolean := False;
   end record;

   overriding procedure Finalize (Value : in out Gate_Guard) is
   begin
      if Value.Held then
         Runner_State.Release (Value.Safe);
         Value.Held := False;
      end if;
   exception
      when others =>
         null;
   end Finalize;

   procedure Acquire (Value : in out Gate_Guard; Granted : out Boolean) is
      Released : Boolean := False;
   begin
      if Test_Hooks.Enabled then
         Test_Hooks.Note_Gate_Attempt;
      end if;
      System.Soft_Links.Abort_Defer.all;
      begin
         Runner_State.Acquire (Granted);
         if Test_Hooks.Enabled and then Granted then
            Test_Hooks.Note_Gate_Granted;
            Test_Hooks.Wait_For_Gate_Grant_Release (5.0, Released);
            if not Released then
               Value.Held := True;
               raise Program_Error with "build-process gate-grant test pause timed out";
            end if;
         end if;
         Value.Held := Granted;
         Value.Safe := False;
      exception
         when others =>
            System.Soft_Links.Abort_Undefer.all;
            raise;
      end;
      System.Soft_Links.Abort_Undefer.all;
   exception
      when others =>
         Granted := False;
   end Acquire;

   procedure Release_Safely (Value : in out Gate_Guard) is
   begin
      if Value.Held then
         Value.Safe := True;
         Runner_State.Release (True);
         Value.Held := False;
      end if;
   exception
      when others =>
         Runner_State.Poison;
         Value.Held := False;
   end Release_Safely;

   type Pipe_Ends is record
      Read_End  : aliased ABI.Descriptor := Invalid_Descriptor;
      Write_End : aliased ABI.Descriptor := Invalid_Descriptor;
   end record;

   type Child_Pipes is record
      Input  : aliased Pipe_Ends;
      Output : aliased Pipe_Ends;
      Error  : aliased Pipe_Ends;
   end record;

   procedure Record_Error
     (Candidate : ABI.C_Int;
      Into      : in out ABI.C_Int)
   is
   begin
      if Into = 0 and then Candidate /= 0 then
         Into := Candidate;
      end if;
   end Record_Error;

   procedure Close_Once
     (Target        : not null access ABI.Descriptor;
      Cleanup_Error : in out ABI.C_Int)
   is
      Result : ABI.C_Int;
      Error  : ABI.C_Int;
      Inject : Boolean := False;
      Original : ABI.Descriptor := Invalid_Descriptor;
      Released : Boolean := False;
   begin
      if Target.all < 0 then
         return;
      end if;
      System.Soft_Links.Abort_Defer.all;
      begin
         Original := Target.all;
         Result := ABI.Close (Target.all);
         if Test_Hooks.Enabled and then Result = 0 then
            Test_Hooks.Consume_Close_Failure (Inject);
         end if;
         if Inject then
            Error := ABI.Errno_Invalid;
            Record_Error (Error, Cleanup_Error);
            Runner_State.Poison;
         elsif Result = -1 then
            Error := ABI.Current_Errno;
            Record_Error (Error, Cleanup_Error);
            Runner_State.Poison;
         elsif Result /= 0 then
            Error := ABI.Errno_Invalid;
            Record_Error (Error, Cleanup_Error);
            Runner_State.Poison;
         end if;
         Target.all := Invalid_Descriptor;
         if Test_Hooks.Enabled then
            Test_Hooks.Note_Close_Committed (Integer (Original));
            Test_Hooks.Wait_For_Close_Commit_Release (5.0, Released);
            if not Released then
               raise Program_Error with "build-process close-commit test pause timed out";
            end if;
         end if;
      exception
         when others =>
            Target.all := Invalid_Descriptor;
            Runner_State.Poison;
            if Cleanup_Error = 0 then
               Cleanup_Error := ABI.Errno_Invalid;
            end if;
            System.Soft_Links.Abort_Undefer.all;
            raise;
      end;
      System.Soft_Links.Abort_Undefer.all;
   exception
      when others =>
         Target.all := Invalid_Descriptor;
         Runner_State.Poison;
         if Cleanup_Error = 0 then
            Cleanup_Error := ABI.Errno_Invalid;
         end if;
   end Close_Once;

   procedure Close_Pipe
     (Value         : not null access Pipe_Ends;
      Cleanup_Error : in out ABI.C_Int)
   is
   begin
      Close_Once (Value.Read_End'Access, Cleanup_Error);
      Close_Once (Value.Write_End'Access, Cleanup_Error);
   end Close_Pipe;

   procedure Close_Pipes
     (Value         : not null access Child_Pipes;
      Cleanup_Error : in out ABI.C_Int)
   is
   begin
      Close_Pipe (Value.Input'Access, Cleanup_Error);
      Close_Pipe (Value.Output'Access, Cleanup_Error);
      Close_Pipe (Value.Error'Access, Cleanup_Error);
   end Close_Pipes;

   type Raw_Pipe_Owner is new Ada.Finalization.Limited_Controlled with record
      Raw        : aliased ABI.Descriptor_Pair := [others => Invalid_Descriptor];
      Read_Copy  : aliased ABI.Descriptor := Invalid_Descriptor;
      Write_Copy : aliased ABI.Descriptor := Invalid_Descriptor;
   end record;

   overriding procedure Finalize (Value : in out Raw_Pipe_Owner) is
      Ignored : ABI.C_Int := 0;
   begin
      Close_Once (Value.Raw (0)'Access, Ignored);
      Close_Once (Value.Raw (1)'Access, Ignored);
      Close_Once (Value.Read_Copy'Access, Ignored);
      Close_Once (Value.Write_Copy'Access, Ignored);
   exception
      when others =>
         Runner_State.Poison;
   end Finalize;

   type Pipe_Owner is new Ada.Finalization.Limited_Controlled with record
      Pipes : aliased Child_Pipes;
   end record;

   overriding procedure Finalize (Value : in out Pipe_Owner) is
      Ignored : ABI.C_Int := 0;
   begin
      Close_Pipes (Value.Pipes'Access, Ignored);
   exception
      when others =>
         Runner_State.Poison;
   end Finalize;

   procedure Open_Cloexec_Pipe
     (Into          : not null access Pipe_Ends;
      Status        : in out Run_Status;
      System_Code   : in out ABI.C_Int;
      Cleanup_Error : in out ABI.C_Int)
   is
      Owner      : Raw_Pipe_Owner;
      Result     : ABI.C_Int;
      Released   : Boolean := False;
      Inject     : Boolean := False;
      Transfer_Released : Boolean := False;
      Published  : Boolean := False;
   begin
      Into.all := (others => Invalid_Descriptor);
      Result := ABI.Pipe (Owner.Raw'Address);
      case Classify_Pipe_Result (Result) is
         when Pipe_Opened =>
            null;
         when Pipe_System_Failure =>
            Status := Run_System_Failed;
            System_Code := ABI.Current_Errno;
            return;
         when Pipe_ABI_Failure =>
            Runner_State.Poison;
            Status := Run_Internal_Failure;
            System_Code := 0;
            return;
      end case;
      if Test_Hooks.Enabled then
         Test_Hooks.Note_Raw_Pipe_Open
           (Integer (Owner.Raw (0)), Integer (Owner.Raw (1)));
         Test_Hooks.Wait_For_Raw_Pipe_Release (5.0, Released);
         if not Released then
            raise Program_Error with "build-process raw-pipe test pause timed out";
         end if;
      end if;

      Result := ABI.Duplicate_Cloexec (Owner.Raw (0), 3, Owner.Read_Copy'Access);
      if Result = 0 then
         if Test_Hooks.Enabled then
            Test_Hooks.Consume_Duplicate_Failure (Inject);
         end if;
         if Inject then
            Result := ABI.Errno_Invalid;
         else
            Result := ABI.Duplicate_Cloexec (Owner.Raw (1), 3, Owner.Write_Copy'Access);
         end if;
      end if;
      if Result /= 0 then
         Status := Run_System_Failed;
         System_Code := Result;
      end if;
      Close_Once (Owner.Raw (0)'Access, Cleanup_Error);
      Close_Once (Owner.Raw (1)'Access, Cleanup_Error);
      if Cleanup_Error /= 0 and then Status = Ready_To_Run then
         Status := Run_Cleanup_Failed;
         System_Code := Cleanup_Error;
      end if;
      if Status /= Ready_To_Run then
         Close_Once (Owner.Read_Copy'Access, Cleanup_Error);
         Close_Once (Owner.Write_Copy'Access, Cleanup_Error);
         return;
      end if;
      if Owner.Read_Copy <= 2
        or else Owner.Write_Copy <= 2
        or else Owner.Read_Copy = Owner.Write_Copy
      then
         Status := Run_Internal_Failure;
         System_Code := ABI.Errno_Invalid;
         Runner_State.Poison;
         Close_Once (Owner.Read_Copy'Access, Cleanup_Error);
         Close_Once (Owner.Write_Copy'Access, Cleanup_Error);
         return;
      end if;
      System.Soft_Links.Abort_Defer.all;
      begin
         Into.all := (Read_End => Owner.Read_Copy, Write_End => Owner.Write_Copy);
         Published := True;
         if Test_Hooks.Enabled then
            Test_Hooks.Note_Duplicate_Transferred
              (Integer (Owner.Read_Copy), Integer (Owner.Write_Copy));
            Test_Hooks.Wait_For_Duplicate_Transfer_Release (5.0, Transfer_Released);
            if not Transfer_Released then
               raise Program_Error with "build-process duplicate-transfer test pause timed out";
            end if;
         end if;
         Owner.Read_Copy := Invalid_Descriptor;
         Owner.Write_Copy := Invalid_Descriptor;
      exception
         when others =>
            if Published then
               Owner.Read_Copy := Invalid_Descriptor;
               Owner.Write_Copy := Invalid_Descriptor;
            end if;
            System.Soft_Links.Abort_Undefer.all;
            raise;
      end;
      System.Soft_Links.Abort_Undefer.all;
   exception
      when Storage_Error =>
         Status := Run_Allocation_Failed;
         Close_Once (Owner.Raw (0)'Access, Cleanup_Error);
         Close_Once (Owner.Raw (1)'Access, Cleanup_Error);
         Close_Once (Owner.Read_Copy'Access, Cleanup_Error);
         Close_Once (Owner.Write_Copy'Access, Cleanup_Error);
      when others =>
         Status := Run_Internal_Failure;
         Runner_State.Poison;
         Close_Once (Owner.Raw (0)'Access, Cleanup_Error);
         Close_Once (Owner.Raw (1)'Access, Cleanup_Error);
         Close_Once (Owner.Read_Copy'Access, Cleanup_Error);
         Close_Once (Owner.Write_Copy'Access, Cleanup_Error);
   end Open_Cloexec_Pipe;

   type Command_Payload is record
      Session           : Budgets.Session_Tag;
      Limits            : Process_Limits;
      Executable        : US.Unbounded_String;
      Executable_Bytes  : Interfaces.Unsigned_64 := 0;
      Arguments         : String_Vectors.Vector;
      Environment       : String_Vectors.Vector;
      Argument_Bytes    : Interfaces.Unsigned_64 := 0;
      Environment_Bytes : Interfaces.Unsigned_64 := 0;
      Sealed            : Boolean := False;
   end record;

   type Result_Payload is record
      Session         : Budgets.Session_Tag;
      Kind            : Termination_Kind := Exited;
      Code            : ABI.C_Int := 0;
      Standard_Output : US.Unbounded_String;
      Standard_Error  : US.Unbounded_String;
   end record;

   procedure Raw_Free_Command is new Ada.Unchecked_Deallocation
     (Object => Command_Payload, Name => Command_Payload_Access);
   procedure Raw_Free_Result is new Ada.Unchecked_Deallocation
     (Object => Result_Payload, Name => Result_Payload_Access);

   procedure Poison_If_Active (Value : in out Budgets.Budget);

   procedure Discard_Command
     (Value : in out Command_Payload_Access;
      Clean : out Boolean)
   is
   begin
      Clean := True;
      Raw_Free_Command (Value);
   exception
      when others =>
         Value := null;
         Clean := False;
   end Discard_Command;

   procedure Discard_Result
     (Value : in out Result_Payload_Access;
      Clean : out Boolean)
   is
   begin
      Clean := True;
      Raw_Free_Result (Value);
   exception
      when others =>
         Value := null;
         Clean := False;
   end Discard_Result;

   procedure Discard_Command (Value : in out Command_Payload_Access) is
      Ignored : Boolean;
   begin
      Discard_Command (Value, Ignored);
   end Discard_Command;

   procedure Discard_Result (Value : in out Result_Payload_Access) is
      Ignored : Boolean;
   begin
      Discard_Result (Value, Ignored);
   end Discard_Result;

   procedure Discard_Command
     (Value : in out Command_Payload_Access;
      Owner : in out Budgets.Budget)
   is
      Clean : Boolean;
   begin
      Discard_Command (Value, Clean);
      if not Clean then
         Poison_If_Active (Owner);
      end if;
   end Discard_Command;

   procedure Discard_Result
     (Value : in out Result_Payload_Access;
      Owner : in out Budgets.Budget)
   is
      Clean : Boolean;
   begin
      Discard_Result (Value, Clean);
      if not Clean then
         Poison_If_Active (Owner);
      end if;
   end Discard_Result;

   overriding procedure Finalize (Value : in out Command_Holder) is
   begin
      Discard_Command (Value.Value);
   exception
      when others =>
         Value.Value := null;
   end Finalize;

   overriding procedure Finalize (Value : in out Result_Holder) is
   begin
      Discard_Result (Value.Value);
   exception
      when others =>
         Value.Value := null;
   end Finalize;

   procedure Poison_If_Active (Value : in out Budgets.Budget) is
   begin
      if Budgets.Current_State (Value) = Budgets.Active then
         Budgets.Poison (Value);
      end if;
   exception
      when others =>
         null;
   end Poison_If_Active;

   function Session_Is_Active
     (Owner   : aliased Budgets.Budget;
      Session : Budgets.Session_Tag;
      Status  : in out Build_Status) return Boolean
   is
   begin
      if not Budgets.Matches (Owner, Session) then
         Status := Build_Session_Foreign;
         return False;
      end if;
      case Budgets.Current_State (Owner) is
         when Budgets.Active =>
            return True;
         when Budgets.Exhausted =>
            Status := Build_Budget_Exhausted;
         when Budgets.Failed =>
            Status := Build_Budget_Failed;
      end case;
      return False;
   exception
      when others =>
         Status := Build_Internal_Failure;
         return False;
   end Session_Is_Active;

   function Session_Is_Active
     (Owner   : aliased Budgets.Budget;
      Session : Budgets.Session_Tag;
      Status  : in out Run_Status) return Boolean
   is
   begin
      if not Budgets.Matches (Owner, Session) then
         Status := Run_Session_Foreign;
         return False;
      end if;
      case Budgets.Current_State (Owner) is
         when Budgets.Active =>
            return True;
         when Budgets.Exhausted =>
            Status := Run_Budget_Exhausted;
         when Budgets.Failed =>
            Status := Run_Budget_Failed;
      end case;
      return False;
   exception
      when others =>
         Status := Run_Internal_Failure;
         return False;
   end Session_Is_Active;

   procedure Reserve_Work
     (Owner   : in out Budgets.Budget;
      Amount  : Interfaces.Unsigned_64;
      Status  : in out Build_Status;
      Granted : out Boolean)
   is
   begin
      Granted := True;
      if Amount = 0 then
         return;
      end if;
      Budgets.Reserve (Owner, Budgets.Work_Units, Amount, Granted);
      if not Granted then
         if Budgets.Current_State (Owner) = Budgets.Exhausted then
            Status := Build_Budget_Exhausted;
         else
            Status := Build_Budget_Failed;
         end if;
      end if;
   exception
      when others =>
         Poison_If_Active (Owner);
         Status := Build_Internal_Failure;
         Granted := False;
   end Reserve_Work;

   procedure Reserve_Run
     (Owner   : in out Budgets.Budget;
      Kind    : Budgets.Category;
      Amount  : Interfaces.Unsigned_64;
      Status  : in out Run_Status;
      Granted : out Boolean)
   is
   begin
      Granted := True;
      if Amount = 0 then
         return;
      end if;
      Budgets.Reserve (Owner, Kind, Amount, Granted);
      if not Granted then
         if Budgets.Current_State (Owner) = Budgets.Exhausted then
            Status := Run_Budget_Exhausted;
         else
            Status := Run_Budget_Failed;
         end if;
      end if;
   exception
      when others =>
         Poison_If_Active (Owner);
         Status := Run_Internal_Failure;
         Granted := False;
   end Reserve_Run;

   procedure Validate_Bytes
     (Owner         : in out Budgets.Budget;
      Value         : String;
      Encoded_Bytes : out Interfaces.Unsigned_64;
      Valid         : out Boolean;
      Status        : in out Build_Status)
   is
      Granted : Boolean := False;
      Length  : Interfaces.Unsigned_64;
   begin
      Encoded_Bytes := 0;
      Valid := False;
      Reserve_Work (Owner, 1, Status, Granted);
      if not Granted then
         return;
      end if;
      Length := Interfaces.Unsigned_64 (Value'Length);
      Reserve_Work (Owner, Length, Status, Granted);
      if not Granted then
         return;
      end if;
      if Length = Interfaces.Unsigned_64'Last then
         Status := Build_Limit_Exceeded;
         return;
      end if;
      for Item of Value loop
         if Item = Character'Val (0) then
            Status := Build_Invalid_Command;
            return;
         end if;
      end loop;
      Encoded_Bytes := Length + 1;
      Valid := True;
   exception
      when Storage_Error =>
         Poison_If_Active (Owner);
         Status := Build_Allocation_Failed;
      when others =>
         Poison_If_Active (Owner);
         Status := Build_Internal_Failure;
   end Validate_Bytes;

   procedure Initialize
     (Into       : in out Command;
      Session    : Budgets.Session_Tag;
      Limits     : Process_Limits;
      Executable : String;
      Status     : in out Build_Status)
   is
      Candidate : Command_Payload_Access := null;
      Bytes     : Interfaces.Unsigned_64 := 0;
      Valid     : Boolean := False;
      Old       : Command_Payload_Access := null;
      Released  : Boolean := False;
      Published : Boolean := False;
   begin
      if Status /= Build_Succeeded then
         return;
      end if;
      if not Session_Is_Active (Into.Owner.all, Session, Status) then
         return;
      end if;
      if Runner_State.Is_Poisoned then
         Status := Build_Runner_Poisoned;
         return;
      end if;
      Validate_Bytes (Into.Owner.all, Executable, Bytes, Valid, Status);
      if not Valid then
         return;
      end if;
      if Executable'Length = 0 or else Executable (Executable'First) /= '/' then
         Status := Build_Invalid_Command;
         return;
      end if;
      if Bytes > Limits.Maximum_Argument_Bytes then
         Status := Build_Limit_Exceeded;
         return;
      end if;
      System.Soft_Links.Abort_Defer.all;
      begin
         Candidate := new Command_Payload'
           (Session           => Session,
            Limits            => Limits,
            Executable        => US.To_Unbounded_String (Executable),
            Executable_Bytes  => Bytes,
            Arguments         => String_Vectors.Empty_Vector,
            Environment       => String_Vectors.Empty_Vector,
            Argument_Bytes    => Bytes,
            Environment_Bytes => 0,
            Sealed            => False);
         Old := Into.Data.Value;
         Into.Data.Value := Candidate;
         Published := True;
         if Test_Hooks.Enabled then
            Test_Hooks.Note_Command_Committed;
            Test_Hooks.Wait_For_Command_Commit_Release (5.0, Released);
            if not Released then
               raise Program_Error with "build-process command-commit test pause timed out";
            end if;
         end if;
         Candidate := null;
         Discard_Command (Old, Into.Owner.all);
         Published := False;
      exception
         when others =>
            if Published then
               Into.Data.Value := Old;
               Old := null;
            end if;
            System.Soft_Links.Abort_Undefer.all;
            raise;
      end;
      System.Soft_Links.Abort_Undefer.all;
   exception
      when Storage_Error =>
         Discard_Command (Candidate, Into.Owner.all);
         Poison_If_Active (Into.Owner.all);
         Status := Build_Allocation_Failed;
      when others =>
         Discard_Command (Candidate, Into.Owner.all);
         Poison_If_Active (Into.Owner.all);
         Status := Build_Internal_Failure;
   end Initialize;

   procedure Check_Build_Command
     (Into    : in out Command;
      Session : Budgets.Session_Tag;
      Status  : in out Build_Status;
      Ready   : out Boolean)
   is
   begin
      Ready := False;
      if not Session_Is_Active (Into.Owner.all, Session, Status) then
         return;
      end if;
      if Runner_State.Is_Poisoned then
         Status := Build_Runner_Poisoned;
         return;
      end if;
      if Into.Data.Value = null then
         Status := Build_Invalid_Command;
         return;
      elsif not Budgets.Matches (Into.Owner.all, Into.Data.Value.Session) then
         Status := Build_Session_Foreign;
         return;
      end if;
      if Into.Data.Value.Sealed then
         Status := Build_Invalid_Command;
         return;
      end if;
      Ready := True;
   exception
      when others =>
         Poison_If_Active (Into.Owner.all);
         Status := Build_Internal_Failure;
   end Check_Build_Command;

   procedure Add_Argument
     (Into    : in out Command;
      Session : Budgets.Session_Tag;
      Value   : String;
      Status  : in out Build_Status)
   is
      Ready   : Boolean := False;
      Valid   : Boolean := False;
      Bytes   : Interfaces.Unsigned_64 := 0;
      Count   : Interfaces.Unsigned_64;
   begin
      if Status /= Build_Succeeded then
         return;
      end if;
      Check_Build_Command (Into, Session, Status, Ready);
      if not Ready then
         return;
      end if;
      Validate_Bytes (Into.Owner.all, Value, Bytes, Valid, Status);
      if not Valid then
         return;
      end if;
      Count := Interfaces.Unsigned_64 (Into.Data.Value.Arguments.Length) + 2;
      if Count > Into.Data.Value.Limits.Maximum_Argument_Count
        or else Into.Data.Value.Argument_Bytes >
          Into.Data.Value.Limits.Maximum_Argument_Bytes
        or else Bytes >
          Into.Data.Value.Limits.Maximum_Argument_Bytes - Into.Data.Value.Argument_Bytes
      then
         Status := Build_Limit_Exceeded;
         return;
      end if;
      Into.Data.Value.Arguments.Append (Value);
      Into.Data.Value.Argument_Bytes := Into.Data.Value.Argument_Bytes + Bytes;
   exception
      when Storage_Error =>
         Poison_If_Active (Into.Owner.all);
         Status := Build_Allocation_Failed;
      when others =>
         Poison_If_Active (Into.Owner.all);
         Status := Build_Internal_Failure;
   end Add_Argument;

   function Environment_Name_Length (Value : String) return Natural is
   begin
      for Index in Value'Range loop
         if Value (Index) = '=' then
            return Index - Value'First;
         end if;
      end loop;
      return 0;
   end Environment_Name_Length;

   procedure Add_Environment
     (Into    : in out Command;
      Session : Budgets.Session_Tag;
      Value   : String;
      Status  : in out Build_Status)
   is
      Ready       : Boolean := False;
      Valid       : Boolean := False;
      Granted     : Boolean := False;
      Bytes       : Interfaces.Unsigned_64 := 0;
      Count       : Interfaces.Unsigned_64;
      Name_Length : Natural;
      Duplicate   : Boolean := False;

      procedure Compare_Existing (Existing : String) is
         Existing_Name_Length : Natural;
      begin
         Reserve_Work (Into.Owner.all, 1, Status, Granted);
         if not Granted then
            return;
         end if;
         Reserve_Work
           (Into.Owner.all, Interfaces.Unsigned_64 (Existing'Length), Status, Granted);
         if not Granted then
            return;
         end if;
         Reserve_Work
           (Into.Owner.all, Interfaces.Unsigned_64 (Name_Length), Status, Granted);
         if not Granted then
            return;
         end if;
         Existing_Name_Length := Environment_Name_Length (Existing);
         Duplicate :=
           Existing_Name_Length = Name_Length
           and then Existing (Existing'First .. Existing'First + (Name_Length - 1)) =
             Value (Value'First .. Value'First + (Name_Length - 1));
      end Compare_Existing;
   begin
      if Status /= Build_Succeeded then
         return;
      end if;
      Check_Build_Command (Into, Session, Status, Ready);
      if not Ready then
         return;
      end if;
      Validate_Bytes (Into.Owner.all, Value, Bytes, Valid, Status);
      if not Valid then
         return;
      end if;
      Reserve_Work (Into.Owner.all, Interfaces.Unsigned_64 (Value'Length), Status, Granted);
      if not Granted then
         return;
      end if;
      Name_Length := Environment_Name_Length (Value);
      if Name_Length = 0 then
         Status := Build_Invalid_Command;
         return;
      end if;
      Count := Interfaces.Unsigned_64 (Into.Data.Value.Environment.Length) + 1;
      if Count > Into.Data.Value.Limits.Maximum_Environment_Count
        or else Into.Data.Value.Environment_Bytes >
          Into.Data.Value.Limits.Maximum_Environment_Bytes
        or else Bytes >
          Into.Data.Value.Limits.Maximum_Environment_Bytes - Into.Data.Value.Environment_Bytes
      then
         Status := Build_Limit_Exceeded;
         return;
      end if;
      for Index in
        Into.Data.Value.Environment.First_Index .. Into.Data.Value.Environment.Last_Index
      loop
         Into.Data.Value.Environment.Query_Element (Index, Compare_Existing'Access);
         if Status /= Build_Succeeded then
            return;
         elsif Duplicate then
            Status := Build_Invalid_Command;
            return;
         end if;
      end loop;
      Into.Data.Value.Environment.Append (Value);
      Into.Data.Value.Environment_Bytes := Into.Data.Value.Environment_Bytes + Bytes;
   exception
      when Constraint_Error =>
         Poison_If_Active (Into.Owner.all);
         Status := Build_Internal_Failure;
      when Storage_Error =>
         Poison_If_Active (Into.Owner.all);
         Status := Build_Allocation_Failed;
      when others =>
         Poison_If_Active (Into.Owner.all);
         Status := Build_Internal_Failure;
   end Add_Environment;

   procedure Seal
     (Into    : in out Command;
      Session : Budgets.Session_Tag;
      Status  : in out Build_Status)
   is
      Ready         : Boolean := False;
      Granted       : Boolean := False;
      Argument_Slots : Interfaces.Unsigned_64;
      Environment_Slots : Interfaces.Unsigned_64;
   begin
      if Status /= Build_Succeeded then
         return;
      end if;
      Check_Build_Command (Into, Session, Status, Ready);
      if not Ready then
         return;
      end if;
      if Into.Data.Value.Limits.Maximum_Argument_Count > Interfaces.Unsigned_64 (Natural'Last)
        or else Into.Data.Value.Limits.Maximum_Environment_Count >
          Interfaces.Unsigned_64 (Natural'Last)
        or else Into.Data.Value.Limits.Maximum_Standard_Output_Bytes >
          Interfaces.Unsigned_64 (Natural'Last)
        or else Into.Data.Value.Limits.Maximum_Standard_Error_Bytes >
          Interfaces.Unsigned_64 (Natural'Last)
        or else Into.Data.Value.Limits.Maximum_Read_Chunk_Bytes >
          Interfaces.Unsigned_64 (Positive'Last)
        or else Into.Data.Value.Limits.Timeout_Milliseconds >
          Interfaces.Unsigned_64 (Integer'Last)
        or else Into.Data.Value.Limits.Observation_Interval_Milliseconds >
          Interfaces.Unsigned_64 (Integer'Last)
      then
         Status := Build_Invalid_Command;
         return;
      end if;
      Argument_Slots := Interfaces.Unsigned_64 (Into.Data.Value.Arguments.Length) + 2;
      Environment_Slots := Interfaces.Unsigned_64 (Into.Data.Value.Environment.Length) + 1;
      Reserve_Work (Into.Owner.all, Argument_Slots, Status, Granted);
      if not Granted then
         return;
      end if;
      Reserve_Work (Into.Owner.all, Environment_Slots, Status, Granted);
      if not Granted then
         return;
      end if;
      Into.Data.Value.Sealed := True;
   exception
      when Storage_Error =>
         Poison_If_Active (Into.Owner.all);
         Status := Build_Allocation_Failed;
      when others =>
         Poison_If_Active (Into.Owner.all);
         Status := Build_Internal_Failure;
   end Seal;

   function Classify_Pipe_Result (Result : Interfaces.C.int) return Pipe_Result_Action is
     (if Result = 0 then Pipe_Opened
      elsif Result = -1 then Pipe_System_Failure
      else Pipe_ABI_Failure);

   type Child_Guard is new Ada.Finalization.Limited_Controlled with record
      Child          : aliased ABI.Process_ID := -1;
      Exit_Observed  : Boolean := False;
      Observed_Kind  : Termination_Kind := Exited;
      Observed_Code  : ABI.C_Int := 0;
      Pipes          : aliased Child_Pipes;
   end record;
   overriding procedure Finalize (Value : in out Child_Guard);

   function Positive_Read_Count_Is_Valid
     (Count     : Interfaces.C.long;
      Requested : Interfaces.C.long) return Boolean is
     (Count > 0 and then Requested > 0 and then Count <= Requested);

   function Published_Child_Is_Valid (Child : Interfaces.C.int) return Boolean is (Child > 0);

   function Observations_Match
     (Left_Kind  : Termination_Kind;
      Left_Code  : Interfaces.C.int;
      Right_Kind : Termination_Kind;
      Right_Code : Interfaces.C.int) return Boolean is
     (Left_Kind = Right_Kind and then Left_Code = Right_Code);

   procedure Ownership_Fail_Stop (Location : Positive; Code : ABI.C_Int := 0) is
   begin
      Runner_State.Poison;
      if Test_Hooks.Enabled then
         Test_Hooks.Raise_Fail_Stop (Location, Integer (Code));
      end if;
      loop
         delay 3_600.0;
      end loop;
   end Ownership_Fail_Stop;

   procedure Peek_Without_Charging
     (Child    : ABI.Process_ID;
      Ready    : out Boolean;
      Kind     : out Termination_Kind;
      Code     : out ABI.C_Int)
   is
      Raw_Ready    : aliased ABI.C_Int := 0;
      Raw_Exited   : aliased ABI.C_Int := 0;
      Raw_Signaled : aliased ABI.C_Int := 0;
      Raw_Code     : aliased ABI.C_Int := 0;
      Result       : ABI.C_Int;
   begin
      loop
         Result := ABI.Peek_Child
           (Child,
            Raw_Ready'Access,
            Raw_Exited'Access,
            Raw_Signaled'Access,
            Raw_Code'Access);
         exit when Result /= ABI.Errno_Interrupted;
      end loop;
      if Result /= 0 then
         Ownership_Fail_Stop (20, Result);
      elsif Raw_Ready = 0 then
         if Raw_Exited /= 0 or else Raw_Signaled /= 0 or else Raw_Code /= 0 then
            Ownership_Fail_Stop (21);
         end if;
         Ready := False;
         Kind := Exited;
         Code := 0;
      elsif Raw_Exited = 1 and then Raw_Signaled = 0 then
         Ready := True;
         Kind := Exited;
         Code := Raw_Code;
      elsif Raw_Exited = 0 and then Raw_Signaled = 1 then
         Ready := True;
         Kind := Signaled;
         Code := Raw_Code;
      else
         Ownership_Fail_Stop (22);
      end if;
   end Peek_Without_Charging;

   procedure Resolve_Child (Value : in out Child_Guard) is
      Cleanup_Error : ABI.C_Int := 0;
      Result        : ABI.Process_ID;
      Wait_Status   : aliased ABI.C_Int := 0;
      Error         : ABI.C_Int;
      Group_Target  : ABI.Process_ID;
      Ready         : Boolean := False;
      Kind          : Termination_Kind := Exited;
      Code          : ABI.C_Int := 0;
   begin
      Close_Pipes (Value.Pipes'Access, Cleanup_Error);
      if Value.Child <= 0 then
         if Cleanup_Error /= 0 then
            Ownership_Fail_Stop (15, Cleanup_Error);
         end if;
         return;
      end if;
      Group_Target := -Value.Child;
      Result := ABI.Kill (Group_Target, ABI.Signal_Kill);
      if Result /= 0 and then Result /= -1 then
         Ownership_Fail_Stop (10);
      elsif Result = -1 then
         Error := ABI.Current_Errno;
         if Error = ABI.Errno_No_Process then
            Peek_Without_Charging (Value.Child, Ready, Kind, Code);
            if not Ready then
               Ownership_Fail_Stop (6, Error);
            end if;
         elsif Error = ABI.Errno_Permission then
            loop
               Peek_Without_Charging (Value.Child, Ready, Kind, Code);
               exit when Ready;
               delay 0.001;
            end loop;
         else
            Ownership_Fail_Stop (2, Error);
         end if;
      end if;
      if Ready then
         if Value.Exit_Observed
           and then not Observations_Match
             (Value.Observed_Kind, Value.Observed_Code, Kind, Code)
         then
            Ownership_Fail_Stop (27);
         end if;
         Value.Exit_Observed := True;
         Value.Observed_Kind := Kind;
         Value.Observed_Code := Code;
      end if;
      loop
         Result := ABI.Wait_Pid (Value.Child, Wait_Status'Access, 0);
         exit when Result = Value.Child;
         if Result = -1 then
            Error := ABI.Current_Errno;
            if Error /= ABI.Errno_Interrupted then
               Ownership_Fail_Stop (7, Error);
            end if;
         else
            Ownership_Fail_Stop (12);
         end if;
      end loop;
      if Value.Exit_Observed then
         if Value.Observed_Kind = Exited then
            if ABI.Status_Exited (Wait_Status) = 0
              or else ABI.Status_Exit_Code (Wait_Status) /= Value.Observed_Code
            then
               Ownership_Fail_Stop (13);
            end if;
         elsif ABI.Status_Signaled (Wait_Status) = 0
           or else ABI.Status_Signal (Wait_Status) /= Value.Observed_Code
         then
            Ownership_Fail_Stop (14);
         end if;
      end if;
      Value.Child := -1;
      Value.Exit_Observed := False;
      if Cleanup_Error /= 0 then
         Ownership_Fail_Stop (16, Cleanup_Error);
      end if;
   exception
      when others =>
         Runner_State.Poison;
         if Test_Hooks.Enabled then
            raise;
         end if;
         loop
            delay 3_600.0;
         end loop;
   end Resolve_Child;

   type Cleanup_Scope (Target : not null access Child_Guard) is
     new Ada.Finalization.Limited_Controlled with null record;

   overriding procedure Finalize (Value : in out Cleanup_Scope) is
   begin
      Resolve_Child (Value.Target.all);
   end Finalize;

   procedure Emergency_Cleanup (Value : in out Child_Guard) is
   begin
      declare
         Scope : Cleanup_Scope (Value'Access);
         pragma Unreferenced (Scope);
      begin
         null;
      end;
   end Emergency_Cleanup;

   overriding procedure Finalize (Value : in out Child_Guard) is
   begin
      Resolve_Child (Value);
   exception
      when others =>
         null;
   end Finalize;

   procedure Transfer_Pipes
     (From : in out Pipe_Owner;
      Into : in out Child_Guard)
   is
      Released : Boolean := False;
      Pause_Failed : Boolean := False;
      Published : Boolean := False;
   begin
      System.Soft_Links.Abort_Defer.all;
      begin
         Into.Pipes := From.Pipes;
         Published := True;
         if Test_Hooks.Enabled then
            Test_Hooks.Note_Pipe_Transferred
              (Integer (Into.Pipes.Input.Read_End),
               Integer (Into.Pipes.Input.Write_End),
               Integer (Into.Pipes.Output.Read_End),
               Integer (Into.Pipes.Output.Write_End),
               Integer (Into.Pipes.Error.Read_End),
               Integer (Into.Pipes.Error.Write_End));
            Test_Hooks.Wait_For_Pipe_Transfer_Release (5.0, Released);
            Pause_Failed := not Released;
         end if;
         From.Pipes := (others => (others => Invalid_Descriptor));
         if Pause_Failed then
            raise Program_Error with "build-process pipe-transfer test pause timed out";
         end if;
      exception
         when others =>
            if Published then
               From.Pipes := (others => (others => Invalid_Descriptor));
            end if;
            System.Soft_Links.Abort_Undefer.all;
            raise;
      end;
      System.Soft_Links.Abort_Undefer.all;
   end Transfer_Pipes;

   procedure Release_C_String
     (Value   : in out C_Strings.chars_ptr;
      Damaged : in out Boolean)
   is
      Was_Owned : constant Boolean := Value /= C_Strings.Null_Ptr;
   begin
      C_Strings.Free (Value);
      if Test_Hooks.Enabled and then Was_Owned then
         Test_Hooks.Note_C_String_Released;
         Test_Hooks.Raise_If_Release_Failure;
      end if;
   exception
      when others =>
         Value := C_Strings.Null_Ptr;
         Damaged := True;
   end Release_C_String;

   procedure Spawn_Command
     (What         : Command_Payload;
      Guard        : in out Child_Guard;
      Spawn_Error  : out ABI.C_Int;
      Cleanup_Error : out ABI.C_Int;
      Release_Damaged : out Boolean;
      Spawned_At    : out Ada.Real_Time.Time)
   is
      Argument_Count : constant Natural := Natural (What.Arguments.Length) + 1;
      Environment_Count : constant Natural := Natural (What.Environment.Length);
      Executable : C_Strings.chars_ptr := C_Strings.Null_Ptr;
      Arguments : aliased C_Strings.chars_ptr_array (0 .. C.size_t (Argument_Count)) :=
        [others => C_Strings.Null_Ptr];
      Environment : aliased C_Strings.chars_ptr_array (0 .. C.size_t (Environment_Count)) :=
        [others => C_Strings.Null_Ptr];
      Candidate_Cleanup : aliased ABI.C_Int := 0;
      Sigchld_Ignored : aliased ABI.C_Int := 0;
      No_Child_Wait : aliased ABI.C_Int := 0;
      Abort_Is_Deferred : Boolean := False;
      Released : Boolean := False;
      Inject_Cleanup : Boolean := False;
   begin
      Spawn_Error := ABI.Errno_Invalid;
      Cleanup_Error := 0;
      Release_Damaged := False;
      Spawned_At := Ada.Real_Time.Time_First;
      Spawn_Error := ABI.Sigchld_Disposition
        (Sigchld_Ignored'Access, No_Child_Wait'Access);
      if Spawn_Error /= 0 then
         return;
      elsif Sigchld_Ignored /= 0 or else No_Child_Wait /= 0 then
         Spawn_Error := ABI.Errno_Invalid;
         return;
      end if;
      System.Soft_Links.Abort_Defer.all;
      Abort_Is_Deferred := True;
      Executable := C_Strings.New_String (US.To_String (What.Executable));
      if Test_Hooks.Enabled then
         Test_Hooks.Note_C_String_Allocated;
         Test_Hooks.Note_Materialization;
         Test_Hooks.Wait_For_Materialization_Release (5.0, Released);
         if not Released then
            raise Program_Error with "build-process materialization test pause timed out";
         end if;
         Test_Hooks.Raise_If_Materialization_Failure;
      end if;
      Arguments (0) := C_Strings.New_String (US.To_String (What.Executable));
      if Test_Hooks.Enabled then
         Test_Hooks.Note_C_String_Allocated;
      end if;
      for Index in What.Arguments.First_Index .. What.Arguments.Last_Index loop
         Arguments (C.size_t (Index)) := C_Strings.New_String (What.Arguments.Element (Index));
         if Test_Hooks.Enabled then
            Test_Hooks.Note_C_String_Allocated;
         end if;
      end loop;
      for Index in What.Environment.First_Index .. What.Environment.Last_Index loop
         Environment (C.size_t (Index - What.Environment.First_Index)) :=
           C_Strings.New_String (What.Environment.Element (Index));
         if Test_Hooks.Enabled then
            Test_Hooks.Note_C_String_Allocated;
         end if;
      end loop;
      Spawn_Error := ABI.Spawn_Exact
        (Guard.Child'Access,
         Executable,
         Arguments'Address,
         Environment'Address,
         Guard.Pipes.Input.Read_End,
         Guard.Pipes.Output.Write_End,
         Guard.Pipes.Error.Write_End,
         Candidate_Cleanup'Access);
      if Spawn_Error = 0 and then Guard.Child > 0 then
         Spawned_At := Ada.Real_Time.Clock;
         if Test_Hooks.Enabled then
            Test_Hooks.Note_Spawn_Published (Integer (Guard.Child));
            Test_Hooks.Wait_For_Spawn_Release (5.0, Released);
            if not Released then
               raise Program_Error with "build-process spawn-publication test pause timed out";
            end if;
         end if;
      end if;
      if Test_Hooks.Enabled then
         Test_Hooks.Consume_Spawn_Cleanup_Failure (Inject_Cleanup);
         if Inject_Cleanup then
            Candidate_Cleanup := ABI.Errno_Invalid;
         end if;
      end if;
      Cleanup_Error := Candidate_Cleanup;
      Release_C_String (Executable, Release_Damaged);
      for Item of Arguments loop
         Release_C_String (Item, Release_Damaged);
      end loop;
      for Item of Environment loop
         Release_C_String (Item, Release_Damaged);
      end loop;
      Abort_Is_Deferred := False;
      System.Soft_Links.Abort_Undefer.all;
   exception
      when others =>
         Release_C_String (Executable, Release_Damaged);
         for Item of Arguments loop
            Release_C_String (Item, Release_Damaged);
         end loop;
         for Item of Environment loop
            Release_C_String (Item, Release_Damaged);
         end loop;
         if Release_Damaged then
            Runner_State.Poison;
         end if;
         if Abort_Is_Deferred then
            Abort_Is_Deferred := False;
            System.Soft_Links.Abort_Undefer.all;
         end if;
         raise;
   end Spawn_Command;

   procedure Classify_Spawn_Release
     (Spawn_Error       : Interfaces.C.int;
      Cleanup_Error     : Interfaces.C.int;
      Release_Damaged   : Boolean;
      Status            : out Run_Status;
      System_Code       : out Interfaces.C.int;
      Poison_Later_Use  : out Boolean;
      Cleanup_Child     : out Boolean)
   is
   begin
      System_Code := 0;
      Poison_Later_Use := Release_Damaged or else Cleanup_Error /= 0;
      Cleanup_Child := False;
      if Spawn_Error /= 0 then
         Status := Run_Spawn_Failed;
         System_Code := Spawn_Error;
      elsif Cleanup_Error /= 0 then
         Status := Run_Cleanup_Failed;
         System_Code := Cleanup_Error;
         Cleanup_Child := True;
      elsif Release_Damaged then
         Status := Run_Internal_Failure;
         Cleanup_Child := True;
      else
         Status := Ready_To_Run;
      end if;
   end Classify_Spawn_Release;

   procedure Check_Child
     (Owner       : in out Budgets.Budget;
      Guard       : in out Child_Guard;
      Candidate   : in out Result_Payload;
      Status      : in out Run_Status)
   is
      Granted     : Boolean := False;
      Ready       : aliased ABI.C_Int := 0;
      Did_Exit    : aliased ABI.C_Int := 0;
      Was_Signaled : aliased ABI.C_Int := 0;
      Code        : aliased ABI.C_Int := 0;
      Result      : ABI.C_Int;
   begin
      if Status /= Ready_To_Run or else Guard.Exit_Observed then
         return;
      end if;
      Reserve_Run (Owner, Budgets.Work_Units, 1, Status, Granted);
      if not Granted then
         return;
      end if;
      Result := ABI.Peek_Child
        (Guard.Child, Ready'Access, Did_Exit'Access, Was_Signaled'Access, Code'Access);
      if Result = ABI.Errno_Interrupted then
         return;
      elsif Result /= 0 then
         Ownership_Fail_Stop (23, Result);
      elsif Ready = 0 then
         if Did_Exit /= 0 or else Was_Signaled /= 0 or else Code /= 0 then
            Ownership_Fail_Stop (24);
         end if;
         return;
      elsif Did_Exit = 1 and then Was_Signaled = 0 then
         Candidate.Kind := Exited;
         Candidate.Code := Code;
      elsif Did_Exit = 0 and then Was_Signaled = 1 then
         Candidate.Kind := Signaled;
         Candidate.Code := Code;
      else
         Ownership_Fail_Stop (25);
      end if;
      Guard.Exit_Observed := True;
      Guard.Observed_Kind := Candidate.Kind;
      Guard.Observed_Code := Candidate.Code;
   exception
      when others =>
         Poison_If_Active (Owner);
         Status := Run_Internal_Failure;
   end Check_Child;

   procedure Read_Stream
     (Owner         : in out Budgets.Budget;
      Descriptor    : not null access ABI.Descriptor;
      Buffer        : in out String;
      Content       : in out US.Unbounded_String;
      Captured      : in out Interfaces.Unsigned_64;
      Maximum       : Interfaces.Unsigned_64;
      At_End        : in out Boolean;
      Limit_Status  : Run_Status;
      Cleanup_Error : in out ABI.C_Int;
      Status        : in out Run_Status;
      System_Code   : in out ABI.C_Int)
   is
      Granted   : Boolean := False;
      Remaining : Interfaces.Unsigned_64;
      Request   : Natural;
      Count     : ABI.C_Long;
      Error     : ABI.C_Int;
      Read_Size : Interfaces.Unsigned_64;
   begin
      if Status /= Ready_To_Run or else At_End then
         return;
      end if;
      Reserve_Run (Owner, Budgets.Work_Units, 1, Status, Granted);
      if not Granted then
         return;
      end if;
      Remaining := Maximum - Captured;
      if Remaining >= Interfaces.Unsigned_64 (Buffer'Length) then
         Request := Buffer'Length;
      else
         Request := Natural (Remaining) + 1;
      end if;
      Count := ABI.Read (Descriptor.all, Buffer'Address, ABI.C_Size (Request));
      if Count > 0 then
         if not Positive_Read_Count_Is_Valid (Count, ABI.C_Long (Request)) then
            Runner_State.Poison;
            Status := Run_Internal_Failure;
            return;
         end if;
         Read_Size := Interfaces.Unsigned_64 (Count);
         Reserve_Run (Owner, Budgets.Input_Bytes, Read_Size, Status, Granted);
         if not Granted then
            return;
         end if;
         if Read_Size > Remaining then
            Status := Limit_Status;
            return;
         end if;
         Reserve_Run (Owner, Budgets.Work_Units, Read_Size, Status, Granted);
         if not Granted then
            return;
         end if;
         US.Append
           (Content, Buffer (Buffer'First .. Buffer'First + (Natural (Count) - 1)));
         Captured := Captured + Read_Size;
      elsif Count = 0 then
         At_End := True;
         Close_Once (Descriptor, Cleanup_Error);
         if Cleanup_Error /= 0 then
            Poison_If_Active (Owner);
            Status := Run_Cleanup_Failed;
            System_Code := Cleanup_Error;
         end if;
      elsif Count = -1 then
         Error := ABI.Current_Errno;
         if Error /= ABI.Errno_Interrupted and then Error /= ABI.Errno_Would_Block then
            Status := Run_System_Failed;
            System_Code := Error;
         end if;
      else
         Runner_State.Poison;
         Status := Run_Internal_Failure;
      end if;
   exception
      when Storage_Error =>
         Poison_If_Active (Owner);
         Status := Run_Allocation_Failed;
      when others =>
         Poison_If_Active (Owner);
         Status := Run_Internal_Failure;
   end Read_Stream;

   procedure Reserve_Query
     (Owner   : in out Budgets.Budget;
      Amount  : Interfaces.Unsigned_64;
      Status  : in out Query_Status;
      Granted : out Boolean)
   is
   begin
      Granted := False;
      if Status /= Query_Succeeded then
         return;
      end if;
      Budgets.Reserve (Owner, Budgets.Work_Units, Amount, Granted);
      if not Granted then
         case Budgets.Current_State (Owner) is
            when Budgets.Exhausted =>
               Status := Query_Budget_Exhausted;
            when Budgets.Failed =>
               Status := Query_Budget_Failed;
            when Budgets.Active =>
               Budgets.Poison (Owner);
               Status := Query_Internal_Failure;
         end case;
      end if;
   exception
      when others =>
         Poison_If_Active (Owner);
         Status := Query_Internal_Failure;
         Granted := False;
   end Reserve_Query;

   function Query_Ready
     (From    : Result;
      Session : Budgets.Session_Tag;
      Status  : in out Query_Status) return Boolean
   is
      Granted : Boolean := False;
   begin
      if Status /= Query_Succeeded then
         return False;
      end if;
      if not Budgets.Matches (From.Owner.all, Session) then
         Status := Query_Session_Foreign;
         return False;
      end if;
      case Budgets.Current_State (From.Owner.all) is
         when Budgets.Active =>
            null;
         when Budgets.Exhausted =>
            Status := Query_Budget_Exhausted;
            return False;
         when Budgets.Failed =>
            Status := Query_Budget_Failed;
            return False;
      end case;
      Reserve_Query (From.Owner.all, 1, Status, Granted);
      if not Granted then
         return False;
      end if;
      if From.Data.Value = null then
         Status := Query_No_Result;
         return False;
      elsif not Budgets.Matches (From.Owner.all, From.Data.Value.Session) then
         Status := Query_Session_Foreign;
         return False;
      end if;
      return True;
   exception
      when others =>
         Poison_If_Active (From.Owner.all);
         Status := Query_Internal_Failure;
         return False;
   end Query_Ready;

   procedure Copy_Result_Text
     (From    : Result;
      Session : Budgets.Session_Tag;
      Source  : US.Unbounded_String;
      Into    : in out String;
      Written : in out Natural;
      Status  : in out Query_Status)
   is
      Granted : Boolean := False;
      Length  : Natural := 0;
   begin
      pragma Unreferenced (Session);
      Length := US.Length (Source);
      if Length > Into'Length then
         Status := Query_Output_Too_Small;
         return;
      end if;
      if Length > 0 then
         Reserve_Query
           (From.Owner.all, Interfaces.Unsigned_64 (Length), Status, Granted);
         if not Granted then
            return;
         end if;
         declare
            Text : constant String := US.To_String (Source);
         begin
            Into (Into'First .. Into'First + (Length - 1)) := Text;
         end;
      end if;
      Written := Length;
   exception
      when others =>
         Poison_If_Active (From.Owner.all);
         Status := Query_Internal_Failure;
   end Copy_Result_Text;

   --  Run is implemented below after the shared observation helpers.

   procedure Read_Termination
     (From    : Result;
      Session : Budgets.Session_Tag;
      Kind    : in out Termination_Kind;
      Code    : in out Interfaces.C.int;
      Status  : in out Query_Status)
   is
   begin
      if Status /= Query_Succeeded then
         return;
      end if;
      if not Query_Ready (From, Session, Status) then
         return;
      end if;
      Kind := From.Data.Value.Kind;
      Code := From.Data.Value.Code;
   exception
      when others =>
         Poison_If_Active (From.Owner.all);
         Status := Query_Internal_Failure;
   end Read_Termination;

   procedure Read_Length
     (From   : Result;
      Value  : US.Unbounded_String;
      Length : in out Interfaces.Unsigned_64;
      Status : in out Query_Status)
   is
   begin
      Length := Interfaces.Unsigned_64 (US.Length (Value));
   exception
      when others =>
         Poison_If_Active (From.Owner.all);
         Status := Query_Internal_Failure;
   end Read_Length;

   procedure Standard_Output_Length
     (From    : Result;
      Session : Budgets.Session_Tag;
      Length  : in out Interfaces.Unsigned_64;
      Status  : in out Query_Status)
   is
   begin
      if not Query_Ready (From, Session, Status) then
         return;
      end if;
      Read_Length (From, From.Data.Value.Standard_Output, Length, Status);
   end Standard_Output_Length;

   procedure Standard_Error_Length
     (From    : Result;
      Session : Budgets.Session_Tag;
      Length  : in out Interfaces.Unsigned_64;
      Status  : in out Query_Status)
   is
   begin
      if not Query_Ready (From, Session, Status) then
         return;
      end if;
      Read_Length (From, From.Data.Value.Standard_Error, Length, Status);
   end Standard_Error_Length;

   procedure Copy_Standard_Output
     (From    : Result;
      Session : Budgets.Session_Tag;
      Into    : in out String;
      Written : in out Natural;
      Status  : in out Query_Status)
   is
   begin
      if not Query_Ready (From, Session, Status) then
         return;
      end if;
      Copy_Result_Text
        (From, Session, From.Data.Value.Standard_Output, Into, Written, Status);
   end Copy_Standard_Output;

   procedure Copy_Standard_Error
     (From    : Result;
      Session : Budgets.Session_Tag;
      Into    : in out String;
      Written : in out Natural;
      Status  : in out Query_Status)
   is
   begin
      if not Query_Ready (From, Session, Status) then
         return;
      end if;
      Copy_Result_Text (From, Session, From.Data.Value.Standard_Error, Into, Written, Status);
   end Copy_Standard_Error;

   procedure Run
     (What       : Command;
      Session    : Budgets.Session_Tag;
      Into       : in out Result;
      Status     : in out Run_Status;
      System_Code : in out Interfaces.C.int)
   is
      Candidate       : Result_Holder;
      Old             : Result_Payload_Access := null;
      Gate            : Gate_Guard;
      Guard           : Child_Guard;
      Setup           : Pipe_Owner;
      Granted         : Boolean := False;
      Gate_Granted    : Boolean := False;
      Cleanup_Error   : ABI.C_Int := 0;
      Spawn_Error     : ABI.C_Int := 0;
      String_Release_Damaged : Boolean := False;
      Poison_Later_Use : Boolean := False;
      Cleanup_Child    : Boolean := False;
      Nonblocking_Error : ABI.C_Int := 0;
      Inject_Nonblocking : Boolean := False;
      Output_Count    : Interfaces.Unsigned_64 := 0;
      Error_Count     : Interfaces.Unsigned_64 := 0;
      Output_End      : Boolean := False;
      Error_End       : Boolean := False;
      Output_First    : Boolean := True;
      Start           : Ada.Real_Time.Time;
      Deadline        : Ada.Real_Time.Time;
      Now             : Ada.Real_Time.Time;
      Next            : Ada.Real_Time.Time;
      Timeout         : Ada.Real_Time.Time_Span;
      Interval        : Ada.Real_Time.Time_Span;
      Commit_Released : Boolean := False;
      Result_Published : Boolean := False;

      procedure Fail_Setup is
      begin
         Close_Pipes (Setup.Pipes'Access, Cleanup_Error);
         if Cleanup_Error /= 0 then
            Poison_If_Active (Into.Owner.all);
            if Status = Ready_To_Run then
               Status := Run_Cleanup_Failed;
               System_Code := Cleanup_Error;
            end if;
         end if;
      exception
         when others =>
            Runner_State.Poison;
      end Fail_Setup;
   begin
      if Status /= Ready_To_Run then
         return;
      end if;
      System_Code := 0;
      if What.Owner /= Into.Owner then
         Status := Run_Session_Foreign;
         return;
      end if;
      if not Session_Is_Active (Into.Owner.all, Session, Status) then
         return;
      end if;
      if Runner_State.Is_Poisoned then
         Status := Run_Runner_Poisoned;
         return;
      end if;
      Reserve_Run (Into.Owner.all, Budgets.Work_Units, 1, Status, Granted);
      if not Granted then
         return;
      end if;
      if What.Data.Value = null
        or else not What.Data.Value.Sealed
        or else not Budgets.Matches (What.Owner.all, What.Data.Value.Session)
      then
         Status := Run_Invalid_Command;
         return;
      end if;

      Reserve_Run
        (Into.Owner.all,
         Budgets.Work_Units,
         What.Data.Value.Argument_Bytes,
         Status,
         Granted);
      if not Granted then
         return;
      end if;
      Reserve_Run
        (Into.Owner.all,
         Budgets.Work_Units,
         What.Data.Value.Executable_Bytes,
         Status,
         Granted);
      if not Granted then
         return;
      end if;
      Reserve_Run
        (Into.Owner.all,
         Budgets.Work_Units,
         What.Data.Value.Environment_Bytes,
         Status,
         Granted);
      if not Granted then
         return;
      end if;
      Reserve_Run
        (Into.Owner.all,
         Budgets.Work_Units,
         Interfaces.Unsigned_64 (What.Data.Value.Arguments.Length) + 2,
         Status,
         Granted);
      if not Granted then
         return;
      end if;
      Reserve_Run
        (Into.Owner.all,
         Budgets.Work_Units,
         Interfaces.Unsigned_64 (What.Data.Value.Environment.Length) + 1,
         Status,
         Granted);
      if not Granted then
         return;
      end if;
      Reserve_Run
        (Into.Owner.all, Budgets.Work_Units, Fixed_Setup_Work, Status, Granted);
      if not Granted then
         return;
      end if;

      Timeout := Ada.Real_Time.Milliseconds
        (Integer (What.Data.Value.Limits.Timeout_Milliseconds));
      Interval := Ada.Real_Time.Milliseconds
        (Integer (What.Data.Value.Limits.Observation_Interval_Milliseconds));
      System.Soft_Links.Abort_Defer.all;
      begin
         Candidate.Value := new Result_Payload'
           (Session         => Session,
            Kind            => Exited,
            Code            => 0,
            Standard_Output => US.Null_Unbounded_String,
            Standard_Error  => US.Null_Unbounded_String);
      exception
         when others =>
            System.Soft_Links.Abort_Undefer.all;
            raise;
      end;
      System.Soft_Links.Abort_Undefer.all;

      Acquire (Gate, Gate_Granted);
      if not Gate_Granted then
         Status := Run_Runner_Poisoned;
         Discard_Result (Candidate.Value, Into.Owner.all);
         return;
      end if;
      Open_Cloexec_Pipe (Setup.Pipes.Input'Access, Status, System_Code, Cleanup_Error);
      if Status = Ready_To_Run then
         Open_Cloexec_Pipe (Setup.Pipes.Output'Access, Status, System_Code, Cleanup_Error);
      end if;
      if Status = Ready_To_Run then
         Open_Cloexec_Pipe (Setup.Pipes.Error'Access, Status, System_Code, Cleanup_Error);
      end if;
      if Status = Ready_To_Run then
         Nonblocking_Error := ABI.Set_Nonblocking (Setup.Pipes.Output.Read_End);
         if Test_Hooks.Enabled and then Nonblocking_Error = 0 then
            Test_Hooks.Consume_Nonblocking_Failure (Inject_Nonblocking);
            if Inject_Nonblocking then
               Nonblocking_Error := ABI.Errno_Invalid;
            end if;
         end if;
         if Nonblocking_Error /= 0 then
            Status := Run_System_Failed;
            System_Code := Nonblocking_Error;
         else
            Nonblocking_Error := ABI.Set_Nonblocking (Setup.Pipes.Error.Read_End);
         end if;
         if Status = Ready_To_Run and then Nonblocking_Error /= 0 then
            Status := Run_System_Failed;
            System_Code := Nonblocking_Error;
         end if;
      end if;
      if Status = Ready_To_Run then
         Close_Once (Setup.Pipes.Input.Write_End'Access, Cleanup_Error);
         if Cleanup_Error /= 0 then
            Status := Run_Cleanup_Failed;
            System_Code := Cleanup_Error;
         end if;
      end if;
      if Status /= Ready_To_Run then
         Release_Safely (Gate);
         Fail_Setup;
         Discard_Result (Candidate.Value, Into.Owner.all);
         return;
      end if;

      Transfer_Pipes (Setup, Guard);
      Spawn_Command
        (What.Data.Value.all,
         Guard,
         Spawn_Error,
         Cleanup_Error,
         String_Release_Damaged,
         Start);
      Release_Safely (Gate);
      Classify_Spawn_Release
        (Spawn_Error,
         Cleanup_Error,
         String_Release_Damaged,
         Status,
         System_Code,
         Poison_Later_Use,
         Cleanup_Child);
      if Poison_Later_Use then
         Runner_State.Poison;
         Poison_If_Active (Into.Owner.all);
      end if;
      if Status = Run_Spawn_Failed then
         Fail_Setup;
         Discard_Result (Candidate.Value, Into.Owner.all);
         return;
      end if;
      if Cleanup_Child then
         Emergency_Cleanup (Guard);
         Discard_Result (Candidate.Value, Into.Owner.all);
         return;
      end if;
      if not Published_Child_Is_Valid (Guard.Child) then
         Ownership_Fail_Stop (28);
      end if;
      if Timeout > Ada.Real_Time.Time_Last - Start then
         Status := Run_Invalid_Command;
         Emergency_Cleanup (Guard);
         Discard_Result (Candidate.Value, Into.Owner.all);
         return;
      end if;
      Deadline := Start + Timeout;
      Close_Once (Guard.Pipes.Input.Read_End'Access, Cleanup_Error);
      Close_Once (Guard.Pipes.Output.Write_End'Access, Cleanup_Error);
      Close_Once (Guard.Pipes.Error.Write_End'Access, Cleanup_Error);
      if Cleanup_Error /= 0 then
         Poison_If_Active (Into.Owner.all);
         Status := Run_Cleanup_Failed;
         System_Code := Cleanup_Error;
         Emergency_Cleanup (Guard);
         Discard_Result (Candidate.Value, Into.Owner.all);
         return;
      end if;

      declare
         Buffer : String (1 .. Positive (What.Data.Value.Limits.Maximum_Read_Chunk_Bytes));
      begin
         loop
            Now := Ada.Real_Time.Clock;
            if Now >= Deadline then
               Status := Run_Timed_Out;
               exit;
            end if;
            if Output_First then
               Read_Stream
                 (Into.Owner.all,
                  Guard.Pipes.Output.Read_End'Access,
                  Buffer,
                  Candidate.Value.Standard_Output,
                  Output_Count,
                  What.Data.Value.Limits.Maximum_Standard_Output_Bytes,
                  Output_End,
                  Run_Standard_Output_Limit,
                  Cleanup_Error,
                  Status,
                  System_Code);
               Read_Stream
                 (Into.Owner.all,
                  Guard.Pipes.Error.Read_End'Access,
                  Buffer,
                  Candidate.Value.Standard_Error,
                  Error_Count,
                  What.Data.Value.Limits.Maximum_Standard_Error_Bytes,
                  Error_End,
                  Run_Standard_Error_Limit,
                  Cleanup_Error,
                  Status,
                  System_Code);
            else
               Read_Stream
                 (Into.Owner.all,
                  Guard.Pipes.Error.Read_End'Access,
                  Buffer,
                  Candidate.Value.Standard_Error,
                  Error_Count,
                  What.Data.Value.Limits.Maximum_Standard_Error_Bytes,
                  Error_End,
                  Run_Standard_Error_Limit,
                  Cleanup_Error,
                  Status,
                  System_Code);
               Read_Stream
                 (Into.Owner.all,
                  Guard.Pipes.Output.Read_End'Access,
                  Buffer,
                  Candidate.Value.Standard_Output,
                  Output_Count,
                  What.Data.Value.Limits.Maximum_Standard_Output_Bytes,
                  Output_End,
                  Run_Standard_Output_Limit,
                  Cleanup_Error,
                  Status,
                  System_Code);
            end if;
            Output_First := not Output_First;
            exit when Status /= Ready_To_Run;
            Now := Ada.Real_Time.Clock;
            if Now >= Deadline then
               Status := Run_Timed_Out;
               exit;
            end if;
            if Output_End and then Error_End then
               Check_Child (Into.Owner.all, Guard, Candidate.Value.all, Status);
               exit when Status /= Ready_To_Run or else Guard.Exit_Observed;
            end if;
            if Interval > Deadline - Now then
               Next := Deadline;
            else
               Next := Now + Interval;
            end if;
            delay until Next;
         end loop;
      end;

      if Status /= Ready_To_Run then
         if Test_Hooks.Enabled then
            Test_Hooks.Raise_If_Post_Primary_Failure;
         end if;
         Emergency_Cleanup (Guard);
         Discard_Result (Candidate.Value, Into.Owner.all);
         return;
      end if;
      if Cleanup_Error /= 0 then
         Poison_If_Active (Into.Owner.all);
         Status := Run_Cleanup_Failed;
         System_Code := Cleanup_Error;
         Emergency_Cleanup (Guard);
         Discard_Result (Candidate.Value, Into.Owner.all);
         return;
      end if;
      Emergency_Cleanup (Guard);
      if Guard.Child > 0 then
         Ownership_Fail_Stop (26);
      end if;
      System.Soft_Links.Abort_Defer.all;
      begin
         Old := Into.Data.Value;
         Into.Data.Value := Candidate.Value;
         Result_Published := True;
         if Test_Hooks.Enabled then
            Test_Hooks.Note_Result_Committed;
            Test_Hooks.Wait_For_Result_Commit_Release (5.0, Commit_Released);
            if not Commit_Released then
               raise Program_Error with "build-process result-commit test pause timed out";
            end if;
         end if;
         Candidate.Value := null;
         Discard_Result (Old, Into.Owner.all);
         Status := Run_Completed;
         System_Code := 0;
         Result_Published := False;
      exception
         when others =>
            if Result_Published then
               Into.Data.Value := Old;
               Old := null;
            end if;
            System.Soft_Links.Abort_Undefer.all;
            raise;
      end;
      System.Soft_Links.Abort_Undefer.all;
   exception
      when Storage_Error =>
         Poison_If_Active (Into.Owner.all);
         if Status = Ready_To_Run then
            Status := Run_Allocation_Failed;
            System_Code := 0;
         end if;
         Emergency_Cleanup (Guard);
         Fail_Setup;
         Discard_Result (Candidate.Value, Into.Owner.all);
      when others =>
         if Status = Ready_To_Run then
            if Budgets.Current_State (Into.Owner.all) = Budgets.Exhausted then
               Status := Run_Budget_Exhausted;
            elsif Budgets.Current_State (Into.Owner.all) = Budgets.Failed then
               Status := Run_Budget_Failed;
            else
               Status := Run_Internal_Failure;
            end if;
            System_Code := 0;
         end if;
         Poison_If_Active (Into.Owner.all);
         Emergency_Cleanup (Guard);
         Fail_Setup;
         Discard_Result (Candidate.Value, Into.Owner.all);
   end Run;
end Flyology_Serde_Generator.Build_Processes;
