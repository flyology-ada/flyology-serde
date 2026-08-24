with Ada.Streams;
with Interfaces.C;
with Interfaces.C.Strings;

with Flyology_Serde_Generator.Build_Process_ABI;

package body Flyology_Serde_Generator.Build_Process_ABI_Test_Facade is
   package ABI renames Flyology_Serde_Generator.Build_Process_ABI;
   package C renames Interfaces.C;
   package C_Strings renames Interfaces.C.Strings;
   use type C.int;
   use type C.long;
   use type C.size_t;

   Invalid_Descriptor : constant ABI.Descriptor := -1;

   function Deviate_Sigpipe return ABI.C_Int with
     Import, Convention => C, External_Name => "flyology_serde_test_deviate_sigpipe";
   function Restore_Sigpipe return ABI.C_Int with
     Import, Convention => C, External_Name => "flyology_serde_test_restore_sigpipe";
   function Deviate_Sigchld_Ignored return ABI.C_Int with
     Import, Convention => C, External_Name => "flyology_serde_test_deviate_sigchld_ignored";
   function Deviate_Sigchld_No_Child_Wait return ABI.C_Int with
     Import,
     Convention    => C,
     External_Name => "flyology_serde_test_deviate_sigchld_no_child_wait";
   function Restore_Sigchld return ABI.C_Int with
     Import, Convention => C, External_Name => "flyology_serde_test_restore_sigchld";
   function Null_Build_Outputs return ABI.C_Int with
     Import, Convention => C, External_Name => "flyology_serde_test_null_build_outputs";

   procedure Check (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Check;

   procedure Close_Once (Target : in out ABI.Descriptor) is
      Ignored : ABI.C_Int;
   begin
      if Target >= 0 then
         Ignored := ABI.Close (Target);
         Target := Invalid_Descriptor;
      end if;
   end Close_Once;

   type Pipe_Ends is record
      Read_End  : ABI.Descriptor := Invalid_Descriptor;
      Write_End : ABI.Descriptor := Invalid_Descriptor;
   end record;

   procedure Close_Pipe (Item : in out Pipe_Ends) is
   begin
      Close_Once (Item.Read_End);
      Close_Once (Item.Write_End);
   end Close_Pipe;

   procedure Open_Cloexec_Pipe (Into : out Pipe_Ends) is
      Raw         : aliased ABI.Descriptor_Pair := [others => Invalid_Descriptor];
      Read_Copy   : aliased ABI.Descriptor := Invalid_Descriptor;
      Write_Copy  : aliased ABI.Descriptor := Invalid_Descriptor;
      Result      : ABI.C_Int;
   begin
      Into := (others => Invalid_Descriptor);
      Result := ABI.Pipe (Raw'Address);
      Check (Result = 0, "pipe creation failed");

      Result := ABI.Duplicate_Cloexec (Raw (0), 3, Read_Copy'Access);
      if Result = 0 then
         Result := ABI.Duplicate_Cloexec (Raw (1), 3, Write_Copy'Access);
      end if;
      Close_Once (Raw (0));
      Close_Once (Raw (1));
      if Result /= 0 then
         Close_Once (Read_Copy);
         Close_Once (Write_Copy);
         raise Program_Error with "CLOEXEC duplication failed";
      end if;
      Check (Read_Copy > 2 and then Write_Copy > 2 and then Read_Copy /= Write_Copy,
             "CLOEXEC descriptors must be distinct and above stderr");
      Into := (Read_End => Read_Copy, Write_End => Write_Copy);
   exception
      when others =>
         Close_Once (Raw (0));
         Close_Once (Raw (1));
         Close_Once (Read_Copy);
         Close_Once (Write_Copy);
         raise;
   end Open_Cloexec_Pipe;

   type Child_Pipes is record
      Input  : Pipe_Ends;
      Output : Pipe_Ends;
      Error  : Pipe_Ends;
   end record;

   procedure Open_Child_Pipes (Into : out Child_Pipes) is
   begin
      Into := (others => (others => Invalid_Descriptor));
      Open_Cloexec_Pipe (Into.Input);
      Open_Cloexec_Pipe (Into.Output);
      Open_Cloexec_Pipe (Into.Error);
   exception
      when others =>
         Close_Pipe (Into.Input);
         Close_Pipe (Into.Output);
         Close_Pipe (Into.Error);
         raise;
   end Open_Child_Pipes;

   procedure Close_Child_Pipes (Item : in out Child_Pipes) is
   begin
      Close_Pipe (Item.Input);
      Close_Pipe (Item.Output);
      Close_Pipe (Item.Error);
   end Close_Child_Pipes;

   procedure Close_Child_Sides (Item : in out Child_Pipes) is
   begin
      Close_Once (Item.Input.Read_End);
      Close_Once (Item.Output.Write_End);
      Close_Once (Item.Error.Write_End);
      Close_Once (Item.Input.Write_End);
   end Close_Child_Sides;

   procedure Wait_Finite (Child : ABI.Process_ID; Status : aliased out ABI.C_Int) is
      Result : ABI.Process_ID;
      Error  : ABI.C_Int;
   begin
      for Attempt in 1 .. 500 loop
         Result := ABI.Wait_Pid (Child, Status'Access, ABI.Wait_No_Hang);
         if Result = Child then
            return;
         elsif Result < 0 then
            Error := ABI.Current_Errno;
            Check (Error = ABI.Errno_Interrupted, "waitpid failed");
         end if;
         delay 0.01;
      end loop;
      raise Program_Error with "child did not exit before the test deadline";
   end Wait_Finite;

   procedure Kill_And_Reap (Child : ABI.Process_ID) is
      Result : ABI.Process_ID;
      Status : aliased ABI.C_Int := 0;
      Error  : ABI.C_Int;
   begin
      Result := ABI.Kill (-Child, ABI.Signal_Kill);
      if Result < 0 then
         Error := ABI.Current_Errno;
         Check (Error = ABI.Errno_No_Process, "process-group cleanup failed");
      end if;
      loop
         Result := ABI.Wait_Pid (Child, Status'Access, 0);
         exit when Result = Child;
         Check (Result < 0, "unexpected blocking cleanup wait result");
         Error := ABI.Current_Errno;
         exit when Error = ABI.Errno_No_Child;
         Check (Error = ABI.Errno_Interrupted, "blocking cleanup wait failed");
      end loop;
   end Kill_And_Reap;

   procedure Read_To_End
     (From : ABI.Descriptor; Into : out String; Written : out Natural; Reads : out Natural)
   is
      Buffer : aliased String (1 .. 4);
      Count  : ABI.C_Long;
      Error  : ABI.C_Int;
   begin
      Written := 0;
      Reads := 0;
      loop
         Count := ABI.Read (From, Buffer'Address, Buffer'Length);
         if Count > 0 then
            Reads := Reads + 1;
            Check (Written + Natural (Count) <= Into'Length, "captured output overflowed");
            for Offset in 0 .. Natural (Count) - 1 loop
               Into (Into'First + Written + Offset) := Buffer (Buffer'First + Offset);
            end loop;
            Written := Written + Natural (Count);
         elsif Count = 0 then
            return;
         else
            Error := ABI.Current_Errno;
            Check (Error = ABI.Errno_Interrupted, "read failed");
         end if;
      end loop;
   end Read_To_End;

   procedure Spawn
     (Executable : String;
      Arg_1      : String;
      Arg_2      : String;
      Arg_3      : String;
      Environment_Entry : String;
      Pipes      : in out Child_Pipes;
      Child      : aliased in out ABI.Process_ID;
      Result     : out ABI.C_Int;
      Cleanup    : out ABI.C_Int)
   is
      Executable_Pointer : C_Strings.chars_ptr := C_Strings.Null_Ptr;
      A0 : C_Strings.chars_ptr := C_Strings.Null_Ptr;
      A1 : C_Strings.chars_ptr := C_Strings.Null_Ptr;
      A2 : C_Strings.chars_ptr := C_Strings.Null_Ptr;
      A3 : C_Strings.chars_ptr := C_Strings.Null_Ptr;
      E0 : C_Strings.chars_ptr := C_Strings.Null_Ptr;
      Arguments : aliased C_Strings.chars_ptr_array (0 .. 4) :=
        [others => C_Strings.Null_Ptr];
      Environment : aliased C_Strings.chars_ptr_array (0 .. 1) :=
        [others => C_Strings.Null_Ptr];
      Candidate_Cleanup : aliased ABI.C_Int := -1;
      procedure Release (Item : in out C_Strings.chars_ptr) is
      begin
         C_Strings.Free (Item);
      exception
         when others =>
            Item := C_Strings.Null_Ptr;
      end Release;
   begin
      Executable_Pointer := C_Strings.New_String (Executable);
      A0 := C_Strings.New_String (Executable);
      A1 := C_Strings.New_String (Arg_1);
      A2 := C_Strings.New_String (Arg_2);
      A3 := C_Strings.New_String (Arg_3);
      E0 := C_Strings.New_String (Environment_Entry);
      Arguments := [A0, A1, A2, A3, C_Strings.Null_Ptr];
      Environment := [E0, C_Strings.Null_Ptr];
      Result := ABI.Spawn_Exact
        (Child'Access,
         Executable_Pointer,
         Arguments'Address,
         Environment'Address,
         Pipes.Input.Read_End,
         Pipes.Output.Write_End,
         Pipes.Error.Write_End,
         Candidate_Cleanup'Access);
      Cleanup := Candidate_Cleanup;
      Release (Executable_Pointer);
      Release (A0);
      Release (A1);
      Release (A2);
      Release (A3);
      Release (E0);
   exception
      when others =>
         Release (Executable_Pointer);
         Release (A0);
         Release (A1);
         Release (A2);
         Release (A3);
         Release (E0);
         raise;
   end Spawn;

   procedure Test_ABI_Layout is
      type Poll_Descriptor is record
         File_Descriptor : ABI.C_Int;
         Events          : C.short;
         Returned_Events : C.short;
      end record with Convention => C;
      Probe : constant Poll_Descriptor :=
        (File_Descriptor => 0, Events => 0, Returned_Events => 0);
   begin
      Check (Null_Build_Outputs = 0, "native null-output validation failed");
      Check (ABI.Pollfd_Size = Poll_Descriptor'Size / Ada.Streams.Stream_Element'Size,
             "pollfd size mismatch");
      Check (ABI.Pollfd_Alignment = Poll_Descriptor'Alignment, "pollfd alignment mismatch");
      Check (ABI.Pollfd_Fd_Offset = Probe.File_Descriptor'Position, "pollfd fd offset mismatch");
      Check (ABI.Pollfd_Events_Offset = Probe.Events'Position, "pollfd events offset mismatch");
      Check
        (ABI.Pollfd_Returned_Events_Offset = Probe.Returned_Events'Position,
         "pollfd revents offset mismatch");
      Check
        (ABI.Poll_Input /= 0 and then ABI.Poll_Output /= 0 and then ABI.Poll_Error /= 0 and then
           ABI.Poll_Hangup /= 0 and then ABI.Poll_Invalid /= 0,
         "poll constants must be nonzero");
   end Test_ABI_Layout;

   procedure Test_Nonblocking_And_Errno is
      Item   : Pipe_Ends;
      Octet  : aliased C.char;
      Count  : ABI.C_Long;
      Error  : ABI.C_Int;
   begin
      Open_Cloexec_Pipe (Item);
      Check (ABI.Set_Nonblocking (Item.Read_End) = 0, "nonblocking setup failed");
      Count := ABI.Read (Item.Read_End, Octet'Address, 1);
      Check (Count < 0, "empty nonblocking pipe unexpectedly read data");
      Error := ABI.Current_Errno;
      Check (Error = ABI.Errno_Would_Block, "errno was not captured immediately");
      Close_Pipe (Item);
   exception
      when others =>
         Close_Pipe (Item);
         raise;
   end Test_Nonblocking_And_Errno;

   procedure Test_Arguments_Environment_And_Partial_Read is
      Pipes   : Child_Pipes;
      Child   : aliased ABI.Process_ID := -1;
      Result  : ABI.C_Int;
      Cleanup : ABI.C_Int;
      Status  : aliased ABI.C_Int := 0;
      Output  : String (1 .. 64);
      Written : Natural;
      Reads   : Natural;
      Active  : Boolean := False;
   begin
      Open_Child_Pipes (Pipes);
      Spawn
        ("/bin/sh",
         "-c",
         "printf '%s:%s' ""$0"" ""$EXACT_ENV""",
         "arg-zero",
         "EXACT_ENV=value",
         Pipes,
         Child,
         Result,
         Cleanup);
      Active := Result = 0;
      Check (Result = 0 and then Cleanup = 0, "exact spawn failed");
      Close_Child_Sides (Pipes);
      Wait_Finite (Child, Status);
      Active := False;
      Check (ABI.Status_Exited (Status) /= 0, "child did not exit normally");
      Check (ABI.Status_Exit_Code (Status) = 0, "child exit status was not zero");
      Read_To_End (Pipes.Output.Read_End, Output, Written, Reads);
      Check (Output (1 .. Written) = "arg-zero:value", "argv or environment changed");
      Check (Reads > 1, "bounded reads did not exercise partial capture");
      Close_Child_Pipes (Pipes);
   exception
      when others =>
         if Active then
            Kill_And_Reap (Child);
         end if;
         Close_Child_Pipes (Pipes);
         raise;
   end Test_Arguments_Environment_And_Partial_Read;

   procedure Test_Spawn_Failure_Preservation is
      Pipes   : Child_Pipes;
      Child   : aliased ABI.Process_ID := 12_345;
      Result  : ABI.C_Int;
      Cleanup : ABI.C_Int;
      Active  : Boolean := False;
   begin
      Open_Child_Pipes (Pipes);
      Spawn
        ("/flyology-serde/no-such-executable",
         "one",
         "two",
         "three",
         "EXACT_ENV=value",
         Pipes,
         Child,
         Result,
         Cleanup);
      Active := Result = 0;
      Check (Result /= 0, "missing executable unexpectedly spawned");
      Check (Child = 12_345, "failed spawn published a process id");
      Check (Cleanup = 0, "ordinary spawn failure reported cleanup damage");

      Child := 54_321;
      Spawn
        ("bin/sh",
         "one",
         "two",
         "three",
         "EXACT_ENV=value",
         Pipes,
         Child,
         Result,
         Cleanup);
      Active := Result = 0;
      Check (Result = ABI.Errno_Invalid, "relative executable did not fail structural validation");
      Check (Child = 54_321, "relative executable failure published a process id");
      Check (Cleanup = 0, "pre-spawn path rejection reported cleanup damage");
      Close_Child_Pipes (Pipes);
   exception
      when others =>
         if Active then
            Kill_And_Reap (Child);
         end if;
         Close_Child_Pipes (Pipes);
         raise;
   end Test_Spawn_Failure_Preservation;

   procedure Test_Cloexec_No_Leak is
      Pipes   : Child_Pipes;
      Child   : aliased ABI.Process_ID := -1;
      Result  : ABI.C_Int;
      Cleanup : ABI.C_Int;
      Status  : aliased ABI.C_Int := 0;
      Active  : Boolean := False;
   begin
      Open_Child_Pipes (Pipes);
      declare
         Descriptor_List : constant String :=
           ABI.Descriptor'Image (Pipes.Input.Read_End) &
           ABI.Descriptor'Image (Pipes.Input.Write_End) &
           ABI.Descriptor'Image (Pipes.Output.Read_End) &
           ABI.Descriptor'Image (Pipes.Output.Write_End) &
           ABI.Descriptor'Image (Pipes.Error.Read_End) &
           ABI.Descriptor'Image (Pipes.Error.Write_End);
      begin
         Spawn
           ("/bin/sh",
            "-c",
            "for fd in $FD_LIST; do [ ! -e /dev/fd/$fd ] || exit 91; done",
            "fd-test",
            "FD_LIST=" & Descriptor_List,
            Pipes,
            Child,
            Result,
            Cleanup);
      end;
      Active := Result = 0;
      Check (Result = 0 and then Cleanup = 0, "descriptor child did not spawn");
      Close_Child_Sides (Pipes);
      Wait_Finite (Child, Status);
      Active := False;
      Check
        (ABI.Status_Exited (Status) /= 0 and then ABI.Status_Exit_Code (Status) = 0,
         "a CLOEXEC or child source descriptor leaked through exec");
      Close_Child_Pipes (Pipes);
   exception
      when others =>
         if Active then
            Kill_And_Reap (Child);
         end if;
         Close_Child_Pipes (Pipes);
         raise;
   end Test_Cloexec_No_Leak;

   procedure Test_Signal_Reset (Signal_Child_Path : String) is
      Pipes   : Child_Pipes;
      Child   : aliased ABI.Process_ID := -1;
      Result  : ABI.C_Int;
      Cleanup : ABI.C_Int;
      Status  : aliased ABI.C_Int := 0;
      Restored : Boolean := False;
      Deviated : Boolean := False;
      Active   : Boolean := False;
   begin
      Check (Deviate_Sigpipe = 0, "could not establish parent signal state");
      Deviated := True;
      Open_Child_Pipes (Pipes);
      Spawn
        (Signal_Child_Path,
         "unused-1",
         "unused-2",
         "unused-3",
         "EXACT_ENV=value",
         Pipes,
         Child,
         Result,
         Cleanup);
      Active := Result = 0;
      Check
        (Result = 0 and then Cleanup = 0,
         "signal child did not spawn:" & ABI.C_Int'Image (Result));
      Close_Child_Sides (Pipes);
      Wait_Finite (Child, Status);
      Active := False;
      Check
        (ABI.Status_Exited (Status) /= 0 and then ABI.Status_Exit_Code (Status) = 0,
         "child did not receive the reset signal mask and disposition");
      Check (Restore_Sigpipe = 0, "could not restore parent signal state");
      Restored := True;
      Close_Child_Pipes (Pipes);
   exception
      when others =>
         if Active then
            Kill_And_Reap (Child);
         end if;
         if Deviated and then not Restored then
            Check (Restore_Sigpipe = 0, "signal restoration failed during cleanup");
         end if;
         Close_Child_Pipes (Pipes);
         raise;
   end Test_Signal_Reset;

   procedure Test_Parent_Sigchld_Ownership_Facts is
      Result   : ABI.C_Int;
      Ignored  : aliased ABI.C_Int := 0;
      No_Wait  : aliased ABI.C_Int := 0;
      Deviated : Boolean := False;
      Restored : Boolean := False;
   begin
      Check (Deviate_Sigchld_Ignored = 0, "ignored SIGCHLD setup failed");
      Deviated := True;
      Result := ABI.Sigchld_Disposition (Ignored'Access, No_Wait'Access);
      Check
        (Result = 0 and then Ignored = 1,
         "ignored SIGCHLD disposition was not reported");
      Check (Restore_Sigchld = 0, "SIGCHLD restoration failed");
      Restored := True;

      Result := Deviate_Sigchld_No_Child_Wait;
      if Result = 0 then
         Deviated := True;
         Restored := False;
         Ignored := 0;
         No_Wait := 0;
         Result := ABI.Sigchld_Disposition (Ignored'Access, No_Wait'Access);
         Check
           (Result = 0 and then No_Wait = 1,
            "automatic child discard was not reported");
         Check (Restore_Sigchld = 0, "automatic child-discard restoration failed");
         Restored := True;
      else
         Check (Result = -1, "automatic child-discard setup failed unexpectedly");
      end if;
   exception
      when others =>
         if Deviated and then not Restored then
            Check (Restore_Sigchld = 0, "SIGCHLD restoration failed during cleanup");
         end if;
         raise;
   end Test_Parent_Sigchld_Ownership_Facts;

   procedure Test_Nonreaping_Child_Observation is
      Pipes        : Child_Pipes;
      Child        : aliased ABI.Process_ID := -1;
      Result       : ABI.C_Int;
      Cleanup      : ABI.C_Int;
      Ready        : aliased ABI.C_Int := 0;
      Exited       : aliased ABI.C_Int := 0;
      Signaled     : aliased ABI.C_Int := 0;
      Code         : aliased ABI.C_Int := 0;
      Wait_Status  : aliased ABI.C_Int := 0;
      Active       : Boolean := False;
   begin
      Open_Child_Pipes (Pipes);
      Spawn
        ("/bin/sh",
         "-c",
         "exit 7",
         "peek-test",
         "EXACT_ENV=value",
         Pipes,
         Child,
         Result,
         Cleanup);
      Active := Result = 0;
      Check (Result = 0 and then Cleanup = 0, "peek child did not spawn");
      Close_Child_Sides (Pipes);
      for Attempt in 1 .. 500 loop
         Result := ABI.Peek_Child
           (Child, Ready'Access, Exited'Access, Signaled'Access, Code'Access);
         exit when Result = 0 and then Ready = 1;
         Check
           (Result = 0 or else Result = ABI.Errno_Interrupted,
            "nonreaping child observation failed");
         delay 0.01;
      end loop;
      Check
        (Ready = 1 and then Exited = 1 and then Signaled = 0 and then Code = 7,
         "nonreaping child observation changed terminal facts");
      Result := ABI.Wait_Pid (Child, Wait_Status'Access, 0);
      Check
        (Result = Child
         and then ABI.Status_Exited (Wait_Status) /= 0
         and then ABI.Status_Exit_Code (Wait_Status) = 7,
         "nonreaping observation released or changed child ownership");
      Active := False;
      Close_Child_Pipes (Pipes);
   exception
      when others =>
         if Active then
            Kill_And_Reap (Child);
         end if;
         Close_Child_Pipes (Pipes);
         raise;
   end Test_Nonreaping_Child_Observation;

   procedure Test_Process_Group_Cleanup is
      Pipes   : Child_Pipes;
      Child   : aliased ABI.Process_ID := -1;
      Result  : ABI.C_Int;
      Cleanup : ABI.C_Int;
      Status  : aliased ABI.C_Int := 0;
      Buffer  : aliased String (1 .. 16);
      Count   : ABI.C_Long;
      Error   : ABI.C_Int;
      Saw_EOF : Boolean := False;
      Ready   : Natural := 0;
      Active  : Boolean := False;
   begin
      Open_Child_Pipes (Pipes);
      Spawn
        ("/bin/sh",
         "-c",
         "/bin/sleep 30 & child=$!; printf ready; wait ""$child""",
         "group-test",
         "EXACT_ENV=value",
         Pipes,
         Child,
         Result,
         Cleanup);
      Active := Result = 0;
      Check (Result = 0 and then Cleanup = 0, "process-group child did not spawn");
      Close_Child_Sides (Pipes);
      Check (ABI.Set_Nonblocking (Pipes.Output.Read_End) = 0, "readiness probe setup failed");
      for Attempt in 1 .. 500 loop
         Count := ABI.Read
           (Pipes.Output.Read_End,
            Buffer (Buffer'First + Ready)'Address,
            ABI.C_Size (5 - Ready));
         if Count > 0 then
            Ready := Ready + Natural (Count);
            exit when Ready = 5;
         elsif Count < 0 then
            Error := ABI.Current_Errno;
            Check
              (Error = ABI.Errno_Would_Block or else Error = ABI.Errno_Interrupted,
               "group readiness probe failed");
         end if;
         delay 0.01;
      end loop;
      Check (Ready = 5 and then Buffer (1 .. 5) = "ready", "group child was not ready");

      Result := ABI.Kill (-Child, ABI.Signal_Kill);
      Check (Result = 0, "process group could not be killed");
      Wait_Finite (Child, Status);
      Active := False;
      Check
        (ABI.Status_Signaled (Status) /= 0 and then
           ABI.Status_Signal (Status) = ABI.Signal_Kill,
         "process-group leader was not killed");

      for Attempt in 1 .. 500 loop
         Count := ABI.Read (Pipes.Output.Read_End, Buffer'Address, Buffer'Length);
         if Count = 0 then
            Saw_EOF := True;
            exit;
         elsif Count < 0 then
            Error := ABI.Current_Errno;
            Check
              (Error = ABI.Errno_Would_Block or else Error = ABI.Errno_Interrupted,
               "descendant EOF probe failed");
         end if;
         delay 0.01;
      end loop;
      Check (Saw_EOF, "a descendant retained the process-group output descriptor");
      Close_Child_Pipes (Pipes);
   exception
      when others =>
         if Active then
            Kill_And_Reap (Child);
         end if;
         Close_Child_Pipes (Pipes);
         raise;
   end Test_Process_Group_Cleanup;

   procedure Run (Signal_Child_Path : String) is
   begin
      Test_ABI_Layout;
      Test_Nonblocking_And_Errno;
      Test_Arguments_Environment_And_Partial_Read;
      Test_Spawn_Failure_Preservation;
      Test_Cloexec_No_Leak;
      Test_Signal_Reset (Signal_Child_Path);
      Test_Parent_Sigchld_Ownership_Facts;
      Test_Nonreaping_Child_Observation;
      Test_Process_Group_Cleanup;
   end Run;
end Flyology_Serde_Generator.Build_Process_ABI_Test_Facade;
