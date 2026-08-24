with Interfaces.C;
with Interfaces.C.Strings;
with System;

private package Flyology_Serde_Generator.Build_Process_ABI is
   subtype C_Int is Interfaces.C.int;
   subtype C_Long is Interfaces.C.long;
   subtype C_Size is Interfaces.C.size_t;
   subtype Descriptor is C_Int;
   subtype Process_ID is C_Int;

   type Descriptor_Pair is array (0 .. 1) of aliased Descriptor with Convention => C;

   function Pipe (Descriptors : System.Address) return C_Int with
     Import, Convention => C, External_Name => "pipe";
   --  Pipe is one raw syscall and does not atomically add CLOEXEC.  The caller must exclude
   --  concurrent process creation until both ends have been replaced by CLOEXEC descriptors.

   function Read
     (From : Descriptor; Into : System.Address; Length : C_Size) return C_Long with
     Import, Convention => C, External_Name => "read";

   function Close (Target : Descriptor) return C_Int with
     Import, Convention => C, External_Name => "close";
   --  A failed close has platform-defined EINTR ambiguity.  Never retry it blindly.

   function Kill (Target : Process_ID; Signal : C_Int) return C_Int with
     Import, Convention => C, External_Name => "kill";

   function Wait_Pid
     (Target : Process_ID; Status : access C_Int; Options : C_Int) return Process_ID with
     Import, Convention => C, External_Name => "waitpid";

   function Current_Errno return C_Int with
     Import, Convention => C, External_Name => "flyology_serde_build_current_errno";
   --  Call immediately after a failed direct syscall and before any other foreign call.

   function Duplicate_Cloexec
     (Source : Descriptor; Minimum : Descriptor; Into : not null access Descriptor) return C_Int with
     Import, Convention => C, External_Name => "flyology_serde_build_dupfd_cloexec";

   function Set_Nonblocking (Target : Descriptor) return C_Int with
     Import, Convention => C, External_Name => "flyology_serde_build_set_nonblocking";

   function Spawn_Exact
     (Into          : not null access Process_ID;
      Executable    : Interfaces.C.Strings.chars_ptr;
      Arguments     : System.Address;
      Environment   : System.Address;
      Standard_In   : Descriptor;
      Standard_Out  : Descriptor;
      Standard_Error : Descriptor;
      Cleanup_Error : not null access C_Int) return C_Int with
     Import, Convention => C, External_Name => "flyology_serde_build_posix_spawn_exact";
   --  Arguments and Environment are nonnull, null-terminated pointer arrays.  The three
   --  descriptors are distinct and greater than 2.  Every unrelated parent descriptor
   --  must be CLOEXEC.  Executable must begin with '/', which the C leaf validates before
   --  initializing spawn state.  A successful spawn publishes Into even if Cleanup_Error
   --  is nonzero.

   function Signal_Kill return C_Int with
     Import, Convention => C, External_Name => "flyology_serde_build_signal_kill";
   function Signal_Pipe return C_Int with
     Import, Convention => C, External_Name => "flyology_serde_build_signal_pipe";
   function Errno_Interrupted return C_Int with
     Import, Convention => C, External_Name => "flyology_serde_build_errno_interrupted";
   function Errno_Invalid return C_Int with
     Import, Convention => C, External_Name => "flyology_serde_build_errno_invalid";
   function Errno_Would_Block return C_Int with
     Import, Convention => C, External_Name => "flyology_serde_build_errno_would_block";
   function Errno_No_Child return C_Int with
     Import, Convention => C, External_Name => "flyology_serde_build_errno_no_child";
   function Errno_No_Process return C_Int with
     Import, Convention => C, External_Name => "flyology_serde_build_errno_no_process";
   function Errno_Permission return C_Int with
     Import, Convention => C, External_Name => "flyology_serde_build_errno_permission";
   function Wait_No_Hang return C_Int with
     Import, Convention => C, External_Name => "flyology_serde_build_wait_nohang";

   function Status_Exited (Status : C_Int) return C_Int with
     Import, Convention => C, External_Name => "flyology_serde_build_status_exited";
   function Status_Exit_Code (Status : C_Int) return C_Int with
     Import, Convention => C, External_Name => "flyology_serde_build_status_exit_code";
   --  Status_Exit_Code is meaningful only when Status_Exited is nonzero.
   function Status_Signaled (Status : C_Int) return C_Int with
     Import, Convention => C, External_Name => "flyology_serde_build_status_signaled";
   function Status_Signal (Status : C_Int) return C_Int with
     Import, Convention => C, External_Name => "flyology_serde_build_status_signal";
   --  Status_Signal is meaningful only when Status_Signaled is nonzero.

   function Pollfd_Size return C_Size with
     Import, Convention => C, External_Name => "flyology_serde_build_pollfd_size";
   function Pollfd_Alignment return C_Size with
     Import, Convention => C, External_Name => "flyology_serde_build_pollfd_alignment";
   function Pollfd_Fd_Offset return C_Size with
     Import, Convention => C, External_Name => "flyology_serde_build_pollfd_fd_offset";
   function Pollfd_Events_Offset return C_Size with
     Import, Convention => C, External_Name => "flyology_serde_build_pollfd_events_offset";
   function Pollfd_Returned_Events_Offset return C_Size with
     Import, Convention => C, External_Name => "flyology_serde_build_pollfd_revents_offset";
   function Poll_Input return C_Int with
     Import, Convention => C, External_Name => "flyology_serde_build_poll_input";
   function Poll_Output return C_Int with
     Import, Convention => C, External_Name => "flyology_serde_build_poll_output";
   function Poll_Error return C_Int with
     Import, Convention => C, External_Name => "flyology_serde_build_poll_error";
   function Poll_Hangup return C_Int with
     Import, Convention => C, External_Name => "flyology_serde_build_poll_hangup";
   function Poll_Invalid return C_Int with
     Import, Convention => C, External_Name => "flyology_serde_build_poll_invalid";
end Flyology_Serde_Generator.Build_Process_ABI;
