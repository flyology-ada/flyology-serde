with Ada.Finalization;
with Ada.Real_Time;
with Ada.Strings.Unbounded;
with Ada.Unchecked_Deallocation;
with Flyology_Serde_Generator.Diagnostics;
with Flyology_Serde_Generator.Lowered_Records;
with Flyology_Serde_Generator.Lowered_Records.Test_Fixtures;
with Flyology_Serde_Generator.Rendering;
with Flyology_Serde_Generator.Rendering_Test_Hooks;
with Flyology_Serde_Generator.Requests;

procedure Flyology_Serde_Generator.Rendering_Abort_Test is
   package Diagnostics renames Flyology_Serde_Generator.Diagnostics;
   package Fixtures renames
     Flyology_Serde_Generator.Lowered_Records.Test_Fixtures;
   package Rendering renames Flyology_Serde_Generator.Rendering;
   package Hooks renames Flyology_Serde_Generator.Rendering_Test_Hooks;
   package Requests renames Flyology_Serde_Generator.Requests;

   use type Ada.Real_Time.Time;
   use type Diagnostics.Error_Code;
   use type Hooks.Artifact_Identity;
   use type Requests.Used_Value;

   Controller_Failure : exception;

   function Limits return Requests.Generation_Limits
   is (Maximum_Path_Bytes              => 4_096,
       Maximum_Input_Bytes_Per_File    => 1_048_576,
       Maximum_Total_Input_Bytes       => 2_097_152,
       Maximum_Decoded_String_Bytes    => 4_096,
       Maximum_Number_Token_Bytes      => 32,
       Maximum_JSON_Nesting            => 8,
       Maximum_Object_Members          => 64,
       Maximum_Array_Elements          => 4_096,
       Maximum_Type_IR_Nodes           => 64,
       Maximum_Overlay_Nodes           => 64,
       Maximum_Rendered_Bytes_Per_File => 65_536,
       Maximum_Total_Rendered_Bytes    => 131_072,
       Maximum_Artifact_Files          => 2,
       Maximum_Diagnostics             => 16,
       Maximum_Diagnostic_Bytes        => 256,
       Maximum_Work_Units              => 262_144);

   function Payload
     (Value : Rendering.Rendered_Artifacts;
      Kind  : Rendering.Artifact_Kind) return String
   is
      Length  : constant Natural := Rendering.Payload_Length (Value, Kind);
      Result  : String (1 .. Length);
      Written : Natural := Natural'Last;
      Copied  : Boolean := False;
   begin
      Rendering.Copy_Payload (Value, Kind, Result, Written, Copied);
      pragma Assert (Copied and then Written = Length);
      return Result;
   end Payload;

   procedure Assert_Matches
     (Value              : Rendering.Rendered_Artifacts;
      Specification_Name : Ada.Strings.Unbounded.Unbounded_String;
      Specification_Text : Ada.Strings.Unbounded.Unbounded_String;
      Body_Name          : Ada.Strings.Unbounded.Unbounded_String;
      Body_Text          : Ada.Strings.Unbounded.Unbounded_String)
   is
      Expected_Spec : constant String :=
        Ada.Strings.Unbounded.To_String (Specification_Text);
      Expected_Body : constant String :=
        Ada.Strings.Unbounded.To_String (Body_Text);
   begin
      pragma Assert (Rendering.Is_Valid (Value));
      pragma Assert (Rendering.Artifact_Count (Value) = 2);
      pragma Assert
        (Rendering.File_Name (Value, Rendering.Specification) =
           Ada.Strings.Unbounded.To_String (Specification_Name));
      pragma Assert
        (Rendering.File_Name (Value, Rendering.Package_Body) =
           Ada.Strings.Unbounded.To_String (Body_Name));
      pragma Assert
        (Rendering.Payload_Length (Value, Rendering.Specification) =
           Expected_Spec'Length);
      pragma Assert
        (Rendering.Payload_Length (Value, Rendering.Package_Body) =
           Expected_Body'Length);
      pragma Assert
        (Payload (Value, Rendering.Specification) = Expected_Spec);
      pragma Assert (Payload (Value, Rendering.Package_Body) = Expected_Body);
   end Assert_Matches;

   procedure Render
     (Value      : Flyology_Serde_Generator.Lowered_Records.Model;
      Into       : in out Rendering.Rendered_Artifacts;
      Budget     : aliased out Requests.Operation_Budget;
      Diagnostic : out Diagnostics.Diagnostic)
   is
   begin
      Requests.Start_Budget (Limits, Budget);
      Rendering.Render_Payload (Value, Budget, Into, Diagnostic);
   end Render;

   procedure Wait_At (Point : Hooks.Pause_Point) is
      Reached : Boolean := False;
   begin
      Hooks.Wait_For (Point, 5.0, Reached);
      if not Reached then
         Hooks.Release (Point);
         raise Program_Error with "renderer worker did not reach test pause";
      end if;
   end Wait_At;

   type Pause_Release_Guard (Point : Hooks.Pause_Point) is
     new Ada.Finalization.Limited_Controlled with
   record
      Armed : Boolean := True;
   end record;

   overriding procedure Finalize (Item : in out Pause_Release_Guard) is
   begin
      if Item.Armed then
         Hooks.Release (Item.Point);
         Item.Armed := False;
      end if;
   exception
      when others =>
         null;
   end Finalize;

   procedure Release_Pause (Item : in out Pause_Release_Guard) is
   begin
      if Item.Armed then
         Hooks.Release (Item.Point);
         Item.Armed := False;
      end if;
   end Release_Pause;

   Model_Budget     : Requests.Operation_Budget;
   Model_Diagnostic : Diagnostics.Diagnostic;
begin
   declare
      Probe         : aliased Integer := 0;
      First         : Hooks.Artifact_Identity;
      Second        : Hooks.Artifact_Identity;
      Found         : Boolean;
      Attached      : Natural;
      Freed         : Natural;
      Last_Attached : Hooks.Artifact_Identity;
      Last_Freed    : Hooks.Artifact_Identity;
      Overflowed    : Boolean;
   begin
      Hooks.Reset;
      Hooks.Note_Attached (Probe'Address);
      Hooks.Counts
        (Attached, Freed, Last_Attached, Last_Freed, Overflowed);
      First := Last_Attached;
      Hooks.Begin_Free (Probe'Address, First, Found);
      pragma Assert (Found and then First /= 0);
      Hooks.Note_Attached (Probe'Address);
      Hooks.Counts
        (Attached, Freed, Last_Attached, Last_Freed, Overflowed);
      Second := Last_Attached;
      pragma Assert
        (not Overflowed and then Attached = 2 and then Freed = 0
         and then Second /= First);
      Hooks.Note_Freed (First);
      Hooks.Begin_Free (Probe'Address, Second, Found);
      pragma Assert (Found);
      Hooks.Note_Freed (Second);
      Hooks.Counts
        (Attached, Freed, Last_Attached, Last_Freed, Overflowed);
      pragma Assert
        (not Overflowed and then Attached = 2 and then Freed = 2
         and then Last_Freed = Second);
      Hooks.Reset;
   end;
   Requests.Start_Budget (Limits, Model_Budget);
   Diagnostics.Clear (Model_Diagnostic);
   declare
      New_Model : aliased constant Flyology_Serde_Generator.Lowered_Records.Model :=
        Fixtures.Production_Shapes (Model_Budget, Model_Diagnostic);
      Old_Model : aliased constant Flyology_Serde_Generator.Lowered_Records.Model :=
        Fixtures.Legacy_Record;
      Target     : aliased Rendering.Rendered_Artifacts;
      Expected   : Rendering.Rendered_Artifacts;
      Budget     : aliased Requests.Operation_Budget;
      Diagnostic : Diagnostics.Diagnostic;

      type Model_Access is
        access constant Flyology_Serde_Generator.Lowered_Records.Model;
      type Rendered_Access is access all Rendering.Rendered_Artifacts;
      type Budget_Access is access all Requests.Operation_Budget;
      type Diagnostic_Access is access all Diagnostics.Diagnostic;

      task type Worker
        (Source     : not null Model_Access;
         Into       : not null Rendered_Access;
         Budget     : not null Budget_Access;
         Diagnostic : not null Diagnostic_Access);

      task body Worker is
      begin
         Render (Source.all, Into.all, Budget.all, Diagnostic.all);
      end Worker;

      type Worker_Access is access Worker;
      procedure Free_Worker is new
        Ada.Unchecked_Deallocation (Worker, Worker_Access);

      procedure Await_Termination (Item : in out Worker) is
         Deadline : constant Ada.Real_Time.Time :=
           Ada.Real_Time.Clock + Ada.Real_Time.Seconds (5);
      begin
         while not Item'Terminated and then Ada.Real_Time.Clock < Deadline loop
            delay 0.001;
         end loop;
         pragma Assert (Item'Terminated);
      end Await_Termination;

      procedure Cleanup_Worker (Item : in out Worker_Access) is
         Deadline : constant Ada.Real_Time.Time :=
           Ada.Real_Time.Clock + Ada.Real_Time.Seconds (5);
      begin
         if Item = null then
            return;
         end if;
         while not Item.all'Terminated
           and then Ada.Real_Time.Clock < Deadline
         loop
            delay 0.001;
         end loop;
         if not Item.all'Terminated then
            abort Item.all;
            declare
               Abort_Deadline : constant Ada.Real_Time.Time :=
                 Ada.Real_Time.Clock + Ada.Real_Time.Seconds (5);
            begin
               while not Item.all'Terminated
                 and then Ada.Real_Time.Clock < Abort_Deadline
               loop
                  delay 0.001;
               end loop;
            end;
         end if;
         if Item.all'Terminated then
            Free_Worker (Item);
         else
            --  Retain the task object rather than deallocating a live task.
            null;
         end if;
      exception
         when others =>
            null;
      end Cleanup_Worker;

      type Worker_Owner is new Ada.Finalization.Limited_Controlled with record
         Value : Worker_Access := null;
      end record;

      overriding procedure Finalize (Item : in out Worker_Owner) is
      begin
         Cleanup_Worker (Item.Value);
      exception
         when others =>
            null;
      end Finalize;

      procedure Assert_Charged
        (Value             : Requests.Operation_Budget;
         Expected_Rendered : Boolean)
      is
         Usage : constant Requests.Budget_Usage := Requests.Current_Usage (Value);
      begin
         pragma Assert (Usage.Artifact_Files = 2);
         pragma Assert (Usage.Work_Units > 0);
         pragma Assert
           ((Expected_Rendered and then Usage.Rendered_Bytes > 0)
              or else (not Expected_Rendered and then Usage.Rendered_Bytes = 0));
      end Assert_Charged;

      procedure Restore_Old is
      begin
         Render (Old_Model, Target, Budget, Diagnostic);
         pragma Assert (Diagnostics.Code (Diagnostic) = Diagnostics.No_Error);
      end Restore_Old;

      Worker_Budget      : aliased Requests.Operation_Budget;
      Worker_Diagnostic  : aliased Diagnostics.Diagnostic;
      Expected_Spec_Name : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Spec      : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Body_Name : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Body      : Ada.Strings.Unbounded.Unbounded_String;
      Old_Spec_Name      : Ada.Strings.Unbounded.Unbounded_String;
      Old_Spec           : Ada.Strings.Unbounded.Unbounded_String;
      Old_Body_Name      : Ada.Strings.Unbounded.Unbounded_String;
      Old_Body           : Ada.Strings.Unbounded.Unbounded_String;
      Old_Identity       : Hooks.Artifact_Identity := 0;
      Current_Identity   : Hooks.Artifact_Identity := 0;
      Attached           : Natural;
      Freed              : Natural;
      Last_Attached      : Hooks.Artifact_Identity;
      Last_Freed         : Hooks.Artifact_Identity;
      Overflowed         : Boolean;
   begin
      pragma Assert (Diagnostics.Code (Model_Diagnostic) = Diagnostics.No_Error);
      Render (New_Model, Expected, Budget, Diagnostic);
      pragma Assert (Diagnostics.Code (Diagnostic) = Diagnostics.No_Error);
      Ada.Strings.Unbounded.Set_Unbounded_String
        (Expected_Spec_Name,
         Rendering.File_Name (Expected, Rendering.Specification));
      Ada.Strings.Unbounded.Set_Unbounded_String
        (Expected_Spec, Payload (Expected, Rendering.Specification));
      Ada.Strings.Unbounded.Set_Unbounded_String
        (Expected_Body_Name,
         Rendering.File_Name (Expected, Rendering.Package_Body));
      Ada.Strings.Unbounded.Set_Unbounded_String
        (Expected_Body, Payload (Expected, Rendering.Package_Body));
      Restore_Old;
      Ada.Strings.Unbounded.Set_Unbounded_String
        (Old_Spec_Name, Rendering.File_Name (Target, Rendering.Specification));
      Ada.Strings.Unbounded.Set_Unbounded_String
        (Old_Spec, Payload (Target, Rendering.Specification));
      Ada.Strings.Unbounded.Set_Unbounded_String
        (Old_Body_Name, Rendering.File_Name (Target, Rendering.Package_Body));
      Ada.Strings.Unbounded.Set_Unbounded_String
        (Old_Body, Payload (Target, Rendering.Package_Body));
      Hooks.Counts
        (Attached, Freed, Last_Attached, Last_Freed, Overflowed);
      Old_Identity := Last_Attached;
      pragma Assert (not Overflowed and then Old_Identity /= 0);
      Hooks.Reset;

      Hooks.Arm (Hooks.After_Attachment);
      declare
         Item : Worker
           (New_Model'Access, Target'Access, Worker_Budget'Access,
            Worker_Diagnostic'Access);
         Guard : Pause_Release_Guard (Hooks.After_Attachment);
      begin
         Wait_At (Hooks.After_Attachment);
         abort Item;
         Release_Pause (Guard);
         Await_Termination (Item);
      end;
      Assert_Matches
        (Target, Old_Spec_Name, Old_Spec, Old_Body_Name, Old_Body);
      Assert_Charged (Worker_Budget, Expected_Rendered => False);
      Hooks.Counts
        (Attached, Freed, Last_Attached, Last_Freed, Overflowed);
      pragma Assert
        (not Overflowed and then Attached = 1 and then Freed = 1
         and then Last_Attached = Last_Freed);

      Hooks.Reset;
      Hooks.Arm (Hooks.Before_Publication);
      declare
         Item : Worker
           (New_Model'Access, Target'Access, Worker_Budget'Access,
            Worker_Diagnostic'Access);
         Guard : Pause_Release_Guard (Hooks.Before_Publication);
      begin
         Wait_At (Hooks.Before_Publication);
         abort Item;
         Release_Pause (Guard);
         Await_Termination (Item);
      end;
      Assert_Matches
        (Target, Old_Spec_Name, Old_Spec, Old_Body_Name, Old_Body);
      Assert_Charged (Worker_Budget, Expected_Rendered => True);
      Hooks.Counts
        (Attached, Freed, Last_Attached, Last_Freed, Overflowed);
      pragma Assert
        (not Overflowed and then Attached = 1 and then Freed = 1
         and then Last_Attached = Last_Freed);

      Hooks.Reset;
      Hooks.Arm (Hooks.After_Attachment);
      declare
         Item : Worker
           (New_Model'Access, Target'Access, Worker_Budget'Access,
            Worker_Diagnostic'Access);
         Guard : Pause_Release_Guard (Hooks.After_Attachment);
      begin
         Wait_At (Hooks.After_Attachment);
         abort Item;
         Hooks.Arm_Failure (Hooks.After_Attachment_Failure);
         Release_Pause (Guard);
         Await_Termination (Item);
      end;
      Assert_Matches
        (Target, Old_Spec_Name, Old_Spec, Old_Body_Name, Old_Body);
      Assert_Charged (Worker_Budget, Expected_Rendered => False);
      Hooks.Counts
        (Attached, Freed, Last_Attached, Last_Freed, Overflowed);
      pragma Assert
        (not Overflowed and then Attached = 1 and then Freed = 1
         and then Last_Attached = Last_Freed);

      Hooks.Reset;
      Hooks.Arm_Failure (Hooks.After_Attachment_Failure);
      Render (New_Model, Target, Budget, Diagnostic);
      pragma Assert (Diagnostics.Code (Diagnostic) = Diagnostics.Internal_Error);
      pragma Assert (Requests.Is_Poisoned (Budget));
      Assert_Charged (Budget, Expected_Rendered => False);
      Assert_Matches
        (Target, Old_Spec_Name, Old_Spec, Old_Body_Name, Old_Body);
      Hooks.Counts
        (Attached, Freed, Last_Attached, Last_Freed, Overflowed);
      pragma Assert
        (not Overflowed and then Attached = 1 and then Freed = 1
         and then Last_Attached = Last_Freed);

      Hooks.Reset;
      Hooks.Arm_Failure (Hooks.Before_Publication_Failure);
      Render (New_Model, Target, Budget, Diagnostic);
      pragma Assert (Diagnostics.Code (Diagnostic) = Diagnostics.Internal_Error);
      pragma Assert (Requests.Is_Poisoned (Budget));
      Assert_Charged (Budget, Expected_Rendered => True);
      Assert_Matches
        (Target, Old_Spec_Name, Old_Spec, Old_Body_Name, Old_Body);
      Hooks.Counts
        (Attached, Freed, Last_Attached, Last_Freed, Overflowed);
      pragma Assert
        (not Overflowed and then Attached = 1 and then Freed = 1
         and then Last_Attached = Last_Freed);

      Hooks.Reset;
      Hooks.Arm_Failure (Hooks.Deferred_Publication_Failure);
      Render (New_Model, Target, Budget, Diagnostic);
      pragma Assert (Diagnostics.Code (Diagnostic) = Diagnostics.Internal_Error);
      pragma Assert (Requests.Is_Poisoned (Budget));
      Assert_Charged (Budget, Expected_Rendered => True);
      Assert_Matches
        (Target, Old_Spec_Name, Old_Spec, Old_Body_Name, Old_Body);
      Hooks.Counts
        (Attached, Freed, Last_Attached, Last_Freed, Overflowed);
      pragma Assert
        (not Overflowed and then Attached = 1 and then Freed = 1
         and then Last_Attached = Last_Freed);

      Hooks.Reset;
      Hooks.Arm (Hooks.Deferred_Publication);
      declare
         Item : Worker
           (New_Model'Access, Target'Access, Worker_Budget'Access,
            Worker_Diagnostic'Access);
         Guard : Pause_Release_Guard (Hooks.Deferred_Publication);
      begin
         Wait_At (Hooks.Deferred_Publication);
         abort Item;
         Hooks.Arm_Failure (Hooks.Deferred_Publication_Failure);
         Release_Pause (Guard);
         Await_Termination (Item);
      end;
      Assert_Matches
        (Target, Old_Spec_Name, Old_Spec, Old_Body_Name, Old_Body);
      Assert_Charged (Worker_Budget, Expected_Rendered => True);
      Hooks.Counts
        (Attached, Freed, Last_Attached, Last_Freed, Overflowed);
      pragma Assert
        (not Overflowed and then Attached = 1 and then Freed = 1
         and then Last_Attached = Last_Freed);

      Hooks.Reset;
      Hooks.Arm (Hooks.Deferred_Publication);
      declare
         Item : Worker
           (New_Model'Access, Target'Access, Worker_Budget'Access,
            Worker_Diagnostic'Access);
         Guard : Pause_Release_Guard (Hooks.Deferred_Publication);
      begin
         Wait_At (Hooks.Deferred_Publication);
         abort Item;
         Release_Pause (Guard);
         Await_Termination (Item);
      end;
      Assert_Matches
        (Target, Expected_Spec_Name, Expected_Spec,
         Expected_Body_Name, Expected_Body);
      Assert_Charged (Worker_Budget, Expected_Rendered => True);
      Hooks.Counts
        (Attached, Freed, Last_Attached, Last_Freed, Overflowed);
      Current_Identity := Last_Attached;
      pragma Assert
        (not Overflowed and then Attached = 1 and then Freed = 1
         and then Last_Freed = Old_Identity
         and then Current_Identity /= Old_Identity);

      Restore_Old;
      Hooks.Counts
        (Attached, Freed, Last_Attached, Last_Freed, Overflowed);
      Old_Identity := Last_Attached;
      Hooks.Reset;
      Hooks.Arm_Failure (Hooks.Cleanup_Pause_Timeout);
      Render (New_Model, Target, Budget, Diagnostic);
      pragma Assert (Diagnostics.Code (Diagnostic) = Diagnostics.Internal_Error);
      pragma Assert (Requests.Is_Poisoned (Budget));
      Assert_Matches
        (Target, Expected_Spec_Name, Expected_Spec,
         Expected_Body_Name, Expected_Body);
      Hooks.Counts
        (Attached, Freed, Last_Attached, Last_Freed, Overflowed);
      Current_Identity := Last_Attached;
      pragma Assert
        (not Overflowed and then Attached = 1 and then Freed = 1
         and then Last_Freed = Old_Identity
         and then Current_Identity /= Old_Identity);

      Restore_Old;
      Hooks.Counts
        (Attached, Freed, Last_Attached, Last_Freed, Overflowed);
      Old_Identity := Last_Attached;
      Hooks.Reset;
      Hooks.Arm_Failure (Hooks.Cleanup_Pause_Exception);
      Render (New_Model, Target, Budget, Diagnostic);
      pragma Assert (Diagnostics.Code (Diagnostic) = Diagnostics.Internal_Error);
      pragma Assert (Requests.Is_Poisoned (Budget));
      Assert_Matches
        (Target, Expected_Spec_Name, Expected_Spec,
         Expected_Body_Name, Expected_Body);
      Hooks.Counts
        (Attached, Freed, Last_Attached, Last_Freed, Overflowed);
      Current_Identity := Last_Attached;
      pragma Assert
        (not Overflowed and then Attached = 1 and then Freed = 1
         and then Last_Freed = Old_Identity
         and then Current_Identity /= Old_Identity);

      Restore_Old;
      Hooks.Counts
        (Attached, Freed, Last_Attached, Last_Freed, Overflowed);
      Old_Identity := Last_Attached;
      pragma Assert (Last_Freed = Current_Identity);
      Hooks.Reset;
      Hooks.Arm (Hooks.Cleanup_Detached);
      declare
         Item : Worker
           (New_Model'Access, Target'Access, Worker_Budget'Access,
            Worker_Diagnostic'Access);
         Guard : Pause_Release_Guard (Hooks.Cleanup_Detached);
      begin
         Wait_At (Hooks.Cleanup_Detached);
         abort Item;
         Release_Pause (Guard);
         Await_Termination (Item);
      end;
      Assert_Matches
        (Target, Expected_Spec_Name, Expected_Spec,
         Expected_Body_Name, Expected_Body);
      Hooks.Counts
        (Attached, Freed, Last_Attached, Last_Freed, Overflowed);
      Current_Identity := Last_Attached;
      pragma Assert
        (not Overflowed and then Attached = 1 and then Freed = 1
         and then Last_Freed = Old_Identity
         and then Current_Identity /= Old_Identity);

      Restore_Old;
      Hooks.Counts
        (Attached, Freed, Last_Attached, Last_Freed, Overflowed);
      Old_Identity := Last_Attached;
      Hooks.Reset;
      Hooks.Arm_Failure (Hooks.Cleanup_Damage);
      Render (New_Model, Target, Budget, Diagnostic);
      pragma Assert (Diagnostics.Code (Diagnostic) = Diagnostics.Internal_Error);
      pragma Assert (Requests.Is_Poisoned (Budget));
      Assert_Matches
        (Target, Expected_Spec_Name, Expected_Spec,
         Expected_Body_Name, Expected_Body);
      Hooks.Counts
        (Attached, Freed, Last_Attached, Last_Freed, Overflowed);
      pragma Assert
        (not Overflowed and then Attached = 1 and then Freed = 1
         and then Last_Freed = Old_Identity
         and then Last_Attached /= Old_Identity);

      Restore_Old;
      Hooks.Reset;
      declare
         Restricted : Requests.Generation_Limits := Limits;
      begin
         Restricted.Maximum_Rendered_Bytes_Per_File := 1;
         Restricted.Maximum_Total_Rendered_Bytes := 1;
         Requests.Start_Budget (Restricted, Budget);
         Hooks.Arm_Failure (Hooks.Cleanup_Damage);
         Rendering.Render_Payload (New_Model, Budget, Target, Diagnostic);
      end;
      pragma Assert
        (Diagnostics.Code (Diagnostic) = Diagnostics.Resource_Exhausted);
      pragma Assert (Requests.Is_Poisoned (Budget));
      Assert_Matches
        (Target, Old_Spec_Name, Old_Spec, Old_Body_Name, Old_Body);
      Hooks.Counts
        (Attached, Freed, Last_Attached, Last_Freed, Overflowed);
      pragma Assert
        (not Overflowed and then Attached = 1 and then Freed = 1
         and then Last_Attached = Last_Freed);

      Restore_Old;
      Hooks.Reset;
      Hooks.Arm (Hooks.Before_Publication);
      declare
         Owner : Worker_Owner;
         pragma Unreferenced (Owner);
      begin
         Owner.Value :=
           new Worker
             (New_Model'Access, Target'Access, Worker_Budget'Access,
              Worker_Diagnostic'Access);
         begin
            declare
               Guard : Pause_Release_Guard (Hooks.Before_Publication);
               pragma Unreferenced (Guard);
            begin
               Wait_At (Hooks.Before_Publication);
               raise Controller_Failure;
            end;
         exception
            when Controller_Failure =>
               null;
         end;
      end;
      Assert_Matches
        (Target, Expected_Spec_Name, Expected_Spec,
         Expected_Body_Name, Expected_Body);
      Hooks.Counts
        (Attached, Freed, Last_Attached, Last_Freed, Overflowed);
      pragma Assert
        (not Overflowed and then Attached = 1 and then Freed = 1);

      Hooks.Reset;
      declare
         Repeated            : Rendering.Rendered_Artifacts;
         Repeated_Budget     : aliased Requests.Operation_Budget;
         Repeated_Diagnostic : Diagnostics.Diagnostic;
      begin
         Render (Old_Model, Repeated, Repeated_Budget, Repeated_Diagnostic);
         pragma Assert
           (Diagnostics.Code (Repeated_Diagnostic) = Diagnostics.No_Error);
         Hooks.Counts
           (Attached, Freed, Last_Attached, Last_Freed, Overflowed);
         Current_Identity := Last_Attached;
         Hooks.Reset;
         for Attempt in 1 .. 3 loop
            Render (New_Model, Repeated, Repeated_Budget, Repeated_Diagnostic);
            pragma Assert
              (Diagnostics.Code (Repeated_Diagnostic) = Diagnostics.No_Error);
            Assert_Matches
              (Repeated, Expected_Spec_Name, Expected_Spec,
               Expected_Body_Name, Expected_Body);
            Hooks.Counts
              (Attached, Freed, Last_Attached, Last_Freed, Overflowed);
            pragma Assert
              (not Overflowed and then Attached = Attempt
               and then Freed = Attempt
               and then Last_Freed = Current_Identity
               and then Last_Attached /= Current_Identity);
            Current_Identity := Last_Attached;
         end loop;
      end;
      Hooks.Counts
        (Attached, Freed, Last_Attached, Last_Freed, Overflowed);
      pragma Assert
        (not Overflowed and then Attached = 3 and then Freed = 4
         and then Last_Freed = Current_Identity);
   end;
end Flyology_Serde_Generator.Rendering_Abort_Test;
