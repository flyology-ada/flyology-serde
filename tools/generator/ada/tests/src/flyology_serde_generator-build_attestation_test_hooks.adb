with Ada.Real_Time;

package body Flyology_Serde_Generator.Build_Attestation_Test_Hooks is
   use type Ada.Real_Time.Time;

   type Boolean_Array is array (Transfer_Point) of Boolean;
   type Source_Failure_Array is array (Source_Failure_Point) of Boolean;

   protected Control is
      procedure Arm_Point (Point : Transfer_Point);
      procedure Reach_Point (Point : Transfer_Point);
      procedure Release_Point (Point : Transfer_Point);
      function Reached (Point : Transfer_Point) return Boolean;
      function Released (Point : Transfer_Point) return Boolean;
      procedure Request_Allocated;
      procedure Request_Released;
      procedure Dependency_Allocated;
      procedure Dependency_Released;
      procedure Counts
        (Requests_Allocated     : out Natural;
         Requests_Released      : out Natural;
         Dependencies_Allocated : out Natural;
         Dependencies_Released  : out Natural);
      procedure Source_Path_Allocated;
      procedure Source_Path_Released;
      procedure Source_Node_Allocated;
      procedure Source_Node_Released;
      procedure Source_Payload_Allocated;
      procedure Source_Payload_Released;
      procedure Source_Counts
        (Paths_Allocated    : out Natural;
         Paths_Released     : out Natural;
         Nodes_Allocated    : out Natural;
         Nodes_Released     : out Natural;
         Payloads_Allocated : out Natural;
         Payloads_Released  : out Natural);
      procedure Arm_Source_Failure (Point : Source_Failure_Point);
      procedure Take_Source_Failure (Point : Source_Failure_Point; Armed : out Boolean);
      procedure Arm_Request_Storage_Failure;
      procedure Arm_Request_Internal_Failure;
      procedure Arm_Dependency_Storage_Failure;
      procedure Arm_Dependency_Internal_Failure;
      procedure Arm_Request_Release_Failure;
      procedure Take_Request_Storage_Failure (Armed : out Boolean);
      procedure Take_Request_Internal_Failure (Armed : out Boolean);
      procedure Take_Dependency_Storage_Failure (Armed : out Boolean);
      procedure Take_Dependency_Internal_Failure (Armed : out Boolean);
      procedure Take_Request_Release_Failure (Armed : out Boolean);
   private
      Is_Reached             : Boolean_Array := [others => False];
      Is_Released            : Boolean_Array := [others => True];
      Request_Allocations    : Natural := 0;
      Request_Releases       : Natural := 0;
      Dependency_Allocations : Natural := 0;
      Dependency_Releases    : Natural := 0;
      Source_Path_Allocations : Natural := 0;
      Source_Path_Releases    : Natural := 0;
      Source_Node_Allocations : Natural := 0;
      Source_Node_Releases    : Natural := 0;
      Source_Payload_Allocations : Natural := 0;
      Source_Payload_Releases : Natural := 0;
      Source_Failures         : Source_Failure_Array := [others => False];
      Fail_Request_Storage   : Boolean := False;
      Fail_Request_Internal  : Boolean := False;
      Fail_Dependency_Storage : Boolean := False;
      Fail_Dependency_Internal : Boolean := False;
      Fail_Request_Release   : Boolean := False;
   end Control;

   protected body Control is
      procedure Arm_Point (Point : Transfer_Point) is
      begin
         Is_Reached (Point) := False;
         Is_Released (Point) := False;
      end Arm_Point;

      procedure Reach_Point (Point : Transfer_Point) is
      begin
         Is_Reached (Point) := True;
      end Reach_Point;

      procedure Release_Point (Point : Transfer_Point) is
      begin
         Is_Released (Point) := True;
      end Release_Point;

      function Reached (Point : Transfer_Point) return Boolean is
        (Is_Reached (Point));

      function Released (Point : Transfer_Point) return Boolean is
        (Is_Released (Point));

      procedure Request_Allocated is
      begin
         Request_Allocations := Request_Allocations + 1;
      end Request_Allocated;

      procedure Request_Released is
      begin
         Request_Releases := Request_Releases + 1;
      end Request_Released;

      procedure Dependency_Allocated is
      begin
         Dependency_Allocations := Dependency_Allocations + 1;
      end Dependency_Allocated;

      procedure Dependency_Released is
      begin
         Dependency_Releases := Dependency_Releases + 1;
      end Dependency_Released;

      procedure Counts
        (Requests_Allocated     : out Natural;
         Requests_Released      : out Natural;
         Dependencies_Allocated : out Natural;
         Dependencies_Released  : out Natural) is
      begin
         Requests_Allocated := Request_Allocations;
         Requests_Released := Request_Releases;
         Dependencies_Allocated := Dependency_Allocations;
         Dependencies_Released := Dependency_Releases;
      end Counts;

      procedure Source_Path_Allocated is
      begin
         Source_Path_Allocations := Source_Path_Allocations + 1;
      end Source_Path_Allocated;

      procedure Source_Path_Released is
      begin
         Source_Path_Releases := Source_Path_Releases + 1;
      end Source_Path_Released;

      procedure Source_Node_Allocated is
      begin
         Source_Node_Allocations := Source_Node_Allocations + 1;
      end Source_Node_Allocated;

      procedure Source_Node_Released is
      begin
         Source_Node_Releases := Source_Node_Releases + 1;
      end Source_Node_Released;

      procedure Source_Payload_Allocated is
      begin
         Source_Payload_Allocations := Source_Payload_Allocations + 1;
      end Source_Payload_Allocated;

      procedure Source_Payload_Released is
      begin
         Source_Payload_Releases := Source_Payload_Releases + 1;
      end Source_Payload_Released;

      procedure Source_Counts
        (Paths_Allocated    : out Natural;
         Paths_Released     : out Natural;
         Nodes_Allocated    : out Natural;
         Nodes_Released     : out Natural;
         Payloads_Allocated : out Natural;
         Payloads_Released  : out Natural) is
      begin
         Paths_Allocated := Source_Path_Allocations;
         Paths_Released := Source_Path_Releases;
         Nodes_Allocated := Source_Node_Allocations;
         Nodes_Released := Source_Node_Releases;
         Payloads_Allocated := Source_Payload_Allocations;
         Payloads_Released := Source_Payload_Releases;
      end Source_Counts;

      procedure Arm_Source_Failure (Point : Source_Failure_Point) is
      begin
         Source_Failures (Point) := True;
      end Arm_Source_Failure;

      procedure Take_Source_Failure (Point : Source_Failure_Point; Armed : out Boolean) is
      begin
         Armed := Source_Failures (Point);
         Source_Failures (Point) := False;
      end Take_Source_Failure;

      procedure Arm_Request_Storage_Failure is
      begin
         Fail_Request_Storage := True;
      end Arm_Request_Storage_Failure;

      procedure Arm_Request_Internal_Failure is
      begin
         Fail_Request_Internal := True;
      end Arm_Request_Internal_Failure;

      procedure Arm_Dependency_Storage_Failure is
      begin
         Fail_Dependency_Storage := True;
      end Arm_Dependency_Storage_Failure;

      procedure Arm_Dependency_Internal_Failure is
      begin
         Fail_Dependency_Internal := True;
      end Arm_Dependency_Internal_Failure;

      procedure Arm_Request_Release_Failure is
      begin
         Fail_Request_Release := True;
      end Arm_Request_Release_Failure;

      procedure Take_Request_Storage_Failure (Armed : out Boolean) is
      begin
         Armed := Fail_Request_Storage;
         Fail_Request_Storage := False;
      end Take_Request_Storage_Failure;

      procedure Take_Request_Internal_Failure (Armed : out Boolean) is
      begin
         Armed := Fail_Request_Internal;
         Fail_Request_Internal := False;
      end Take_Request_Internal_Failure;

      procedure Take_Dependency_Storage_Failure (Armed : out Boolean) is
      begin
         Armed := Fail_Dependency_Storage;
         Fail_Dependency_Storage := False;
      end Take_Dependency_Storage_Failure;

      procedure Take_Dependency_Internal_Failure (Armed : out Boolean) is
      begin
         Armed := Fail_Dependency_Internal;
         Fail_Dependency_Internal := False;
      end Take_Dependency_Internal_Failure;

      procedure Take_Request_Release_Failure (Armed : out Boolean) is
      begin
         Armed := Fail_Request_Release;
         Fail_Request_Release := False;
      end Take_Request_Release_Failure;
   end Control;

   procedure Arm (Point : Transfer_Point) is
   begin
      Control.Arm_Point (Point);
   end Arm;

   procedure Pause (Point : Transfer_Point; Released : out Boolean) is
      Deadline : constant Ada.Real_Time.Time :=
        Ada.Real_Time.Clock + Ada.Real_Time.To_Time_Span (5.0);
   begin
      Control.Reach_Point (Point);
      loop
         if Control.Released (Point) then
            Released := True;
            return;
         elsif Ada.Real_Time.Clock >= Deadline then
            Released := False;
            return;
         end if;
         delay 0.001;
      end loop;
   end Pause;

   procedure Wait_For (Point : Transfer_Point; Timeout : Duration; Reached : out Boolean) is
      Deadline : constant Ada.Real_Time.Time :=
        Ada.Real_Time.Clock + Ada.Real_Time.To_Time_Span (Timeout);
   begin
      loop
         if Control.Reached (Point) then
            Reached := True;
            return;
         elsif Ada.Real_Time.Clock >= Deadline then
            Reached := False;
            return;
         end if;
         delay 0.001;
      end loop;
   end Wait_For;

   procedure Release (Point : Transfer_Point) is
   begin
      Control.Release_Point (Point);
   end Release;

   procedure Note_Request_Allocated is
   begin
      Control.Request_Allocated;
   end Note_Request_Allocated;

   procedure Note_Request_Released is
   begin
      Control.Request_Released;
   end Note_Request_Released;

   procedure Note_Dependency_Allocated is
   begin
      Control.Dependency_Allocated;
   end Note_Dependency_Allocated;

   procedure Note_Dependency_Released is
   begin
      Control.Dependency_Released;
   end Note_Dependency_Released;

   procedure Allocation_Counts
     (Requests_Allocated     : out Natural;
      Requests_Released      : out Natural;
      Dependencies_Allocated : out Natural;
      Dependencies_Released  : out Natural) is
   begin
      Control.Counts
        (Requests_Allocated, Requests_Released, Dependencies_Allocated, Dependencies_Released);
   end Allocation_Counts;

   procedure Note_Source_Path_Allocated is
   begin
      Control.Source_Path_Allocated;
   end Note_Source_Path_Allocated;

   procedure Note_Source_Path_Released is
   begin
      Control.Source_Path_Released;
   end Note_Source_Path_Released;

   procedure Note_Source_Node_Allocated is
   begin
      Control.Source_Node_Allocated;
   end Note_Source_Node_Allocated;

   procedure Note_Source_Node_Released is
   begin
      Control.Source_Node_Released;
   end Note_Source_Node_Released;

   procedure Note_Source_Payload_Allocated is
   begin
      Control.Source_Payload_Allocated;
   end Note_Source_Payload_Allocated;

   procedure Note_Source_Payload_Released is
   begin
      Control.Source_Payload_Released;
   end Note_Source_Payload_Released;

   procedure Source_Allocation_Counts
     (Paths_Allocated    : out Natural;
      Paths_Released     : out Natural;
      Nodes_Allocated    : out Natural;
      Nodes_Released     : out Natural;
      Payloads_Allocated : out Natural;
      Payloads_Released  : out Natural) is
   begin
      Control.Source_Counts
        (Paths_Allocated, Paths_Released, Nodes_Allocated, Nodes_Released,
         Payloads_Allocated, Payloads_Released);
   end Source_Allocation_Counts;

   procedure Arm_Source_Failure (Point : Source_Failure_Point) is
   begin
      Control.Arm_Source_Failure (Point);
   end Arm_Source_Failure;

   procedure Raise_If_Source_Failure (Point : Source_Failure_Point) is
      Armed : Boolean;
   begin
      Control.Take_Source_Failure (Point, Armed);
      if Armed then
         case Point is
            when Source_Path_Storage | Source_Node_Storage | Source_Payload_Storage =>
               raise Storage_Error with "injected source-list storage failure";
            when others =>
               raise Program_Error with "injected source-list internal or cleanup failure";
         end case;
      end if;
   end Raise_If_Source_Failure;

   procedure Arm_Request_Storage_Failure is
   begin
      Control.Arm_Request_Storage_Failure;
   end Arm_Request_Storage_Failure;

   procedure Raise_If_Request_Storage_Failure is
      Armed : Boolean;
   begin
      Control.Take_Request_Storage_Failure (Armed);
      if Armed then
         raise Storage_Error with "injected attestation request allocation failure";
      end if;
   end Raise_If_Request_Storage_Failure;

   procedure Arm_Request_Internal_Failure is
   begin
      Control.Arm_Request_Internal_Failure;
   end Arm_Request_Internal_Failure;

   procedure Raise_If_Request_Internal_Failure is
      Armed : Boolean;
   begin
      Control.Take_Request_Internal_Failure (Armed);
      if Armed then
         raise Program_Error with "injected attestation request internal failure";
      end if;
   end Raise_If_Request_Internal_Failure;

   procedure Arm_Request_Release_Failure is
   begin
      Control.Arm_Request_Release_Failure;
   end Arm_Request_Release_Failure;

   procedure Raise_If_Request_Release_Failure is
      Armed : Boolean;
   begin
      Control.Take_Request_Release_Failure (Armed);
      if Armed then
         raise Program_Error with "injected attestation request release failure";
      end if;
   end Raise_If_Request_Release_Failure;

   procedure Arm_Dependency_Storage_Failure is
   begin
      Control.Arm_Dependency_Storage_Failure;
   end Arm_Dependency_Storage_Failure;

   procedure Raise_If_Dependency_Storage_Failure is
      Armed : Boolean;
   begin
      Control.Take_Dependency_Storage_Failure (Armed);
      if Armed then
         raise Storage_Error with "injected attestation dependency allocation failure";
      end if;
   end Raise_If_Dependency_Storage_Failure;

   procedure Arm_Dependency_Internal_Failure is
   begin
      Control.Arm_Dependency_Internal_Failure;
   end Arm_Dependency_Internal_Failure;

   procedure Raise_If_Dependency_Internal_Failure is
      Armed : Boolean;
   begin
      Control.Take_Dependency_Internal_Failure (Armed);
      if Armed then
         raise Program_Error with "injected attestation dependency internal failure";
      end if;
   end Raise_If_Dependency_Internal_Failure;
end Flyology_Serde_Generator.Build_Attestation_Test_Hooks;
