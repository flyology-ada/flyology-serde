with Ada.Real_Time;

package body Flyology_Serde_Generator.Rendering_Test_Hooks is
   use type Ada.Real_Time.Time;
   use type Artifact_Identity;
   use type System.Address;

   type Pause_Array is array (Pause_Point) of Boolean;
   type Failure_Array is array (Failure_Point) of Boolean;
   subtype Registry_Index is Positive range 1 .. 64;
   type Registry_State is (Unused, Active, Releasing, Damaged);
   type Registry_Entry is record
      State    : Registry_State := Unused;
      Address  : System.Address := System.Null_Address;
      Identity : Artifact_Identity := 0;
   end record;
   type Registry_Array is array (Registry_Index) of Registry_Entry;

   protected Control is
      procedure Arm_Pause (Point : Pause_Point);
      procedure Reach (Point : Pause_Point);
      procedure Release_Pause (Point : Pause_Point);
      function Was_Reached (Point : Pause_Point) return Boolean;
      function Was_Released (Point : Pause_Point) return Boolean;
      procedure Attach
        (Address  : System.Address;
         Identity : out Artifact_Identity);
      procedure Begin_Release
        (Address  : System.Address;
         Identity : out Artifact_Identity;
         Found    : out Boolean);
      procedure Finish_Release (Identity : Artifact_Identity);
      procedure Damage_Release (Identity : Artifact_Identity);
      procedure Read_Counts
        (Attached      : out Natural;
         Freed         : out Natural;
         Last_Attached : out Artifact_Identity;
         Last_Freed    : out Artifact_Identity;
         Overflowed    : out Boolean);
      procedure Arm_Error (Point : Failure_Point);
      procedure Take_Error
        (Point : Failure_Point;
         Armed : out Boolean);
      procedure Reset_All;
   private
      Reached        : Pause_Array := [others => False];
      Released       : Pause_Array := [others => True];
      Failures       : Failure_Array := [others => False];
      Registry       : Registry_Array;
      Next_Identity  : Artifact_Identity := 1;
      Attachments    : Natural := 0;
      Releases       : Natural := 0;
      Last_Attachment : Artifact_Identity := 0;
      Last_Release   : Artifact_Identity := 0;
      Did_Overflow   : Boolean := False;
   end Control;

   protected body Control is
      procedure Arm_Pause (Point : Pause_Point) is
      begin
         Reached (Point) := False;
         Released (Point) := False;
      end Arm_Pause;

      procedure Reach (Point : Pause_Point) is
      begin
         Reached (Point) := True;
      end Reach;

      procedure Release_Pause (Point : Pause_Point) is
      begin
         Released (Point) := True;
      end Release_Pause;

      function Was_Reached (Point : Pause_Point) return Boolean is
        (Reached (Point));

      function Was_Released (Point : Pause_Point) return Boolean is
        (Released (Point));

      procedure Attach
        (Address  : System.Address;
         Identity : out Artifact_Identity)
      is
         Slot : Registry_Index := Registry_Index'First;
         Found : Boolean := False;
      begin
         for Index in Registry'Range loop
            if Registry (Index).State = Active
              and then Registry (Index).Address = Address
            then
               Did_Overflow := True;
               Identity := 0;
               return;
            elsif not Found and then Registry (Index).State = Unused then
               Slot := Index;
               Found := True;
            end if;
         end loop;
         if Address = System.Null_Address
           or else not Found
           or else Next_Identity = 0
           or else Next_Identity = Artifact_Identity'Last
         then
            Did_Overflow := True;
            Identity := 0;
         else
            Identity := Next_Identity;
            Next_Identity := Next_Identity + 1;
            Registry (Slot) :=
              (State => Active, Address => Address, Identity => Identity);
         end if;
         if Attachments = Natural'Last then
            Did_Overflow := True;
         else
            Attachments := Attachments + 1;
         end if;
         Last_Attachment := Identity;
      end Attach;

      procedure Begin_Release
        (Address  : System.Address;
         Identity : out Artifact_Identity;
         Found    : out Boolean)
      is
      begin
         Identity := 0;
         Found := False;
         for Index in Registry'Range loop
            if Registry (Index).State = Active
              and then Registry (Index).Address = Address
            then
               Identity := Registry (Index).Identity;
               Registry (Index).State := Releasing;
               Registry (Index).Address := System.Null_Address;
               Found := True;
               exit;
            end if;
         end loop;
         if not Found then
            Did_Overflow := True;
         end if;
      end Begin_Release;

      procedure Finish_Release (Identity : Artifact_Identity) is
         Found : Boolean := False;
      begin
         for Index in Registry'Range loop
            if Registry (Index).State = Releasing
              and then Registry (Index).Identity = Identity
            then
               Registry (Index) :=
                 (State    => Unused,
                  Address  => System.Null_Address,
                  Identity => 0);
               Found := True;
               exit;
            end if;
         end loop;
         if not Found then
            Did_Overflow := True;
         end if;
         if Releases = Natural'Last then
            Did_Overflow := True;
         else
            Releases := Releases + 1;
         end if;
         Last_Release := Identity;
      end Finish_Release;

      procedure Damage_Release (Identity : Artifact_Identity) is
         Found : Boolean := False;
      begin
         for Index in Registry'Range loop
            if Registry (Index).State = Releasing
              and then Registry (Index).Identity = Identity
            then
               Registry (Index).State := Damaged;
               Found := True;
               exit;
            end if;
         end loop;
         if not Found then
            Did_Overflow := True;
         end if;
      end Damage_Release;

      procedure Read_Counts
        (Attached      : out Natural;
         Freed         : out Natural;
         Last_Attached : out Artifact_Identity;
         Last_Freed    : out Artifact_Identity;
         Overflowed    : out Boolean)
      is
      begin
         Attached := Attachments;
         Freed := Releases;
         Last_Attached := Last_Attachment;
         Last_Freed := Last_Release;
         Overflowed := Did_Overflow;
      end Read_Counts;

      procedure Arm_Error (Point : Failure_Point) is
      begin
         Failures (Point) := True;
      end Arm_Error;

      procedure Take_Error
        (Point : Failure_Point;
         Armed : out Boolean)
      is
      begin
         Armed := Failures (Point);
         Failures (Point) := False;
      end Take_Error;

      procedure Reset_All is
      begin
         Reached := [others => False];
         Released := [others => True];
         Failures := [others => False];
         Attachments := 0;
         Releases := 0;
         Last_Attachment := 0;
         Last_Release := 0;
         Did_Overflow := False;
      end Reset_All;
   end Control;

   procedure Arm (Point : Pause_Point) is
   begin
      Control.Arm_Pause (Point);
   end Arm;

   procedure Pause (Point : Pause_Point; Released : out Boolean) is
      Deadline : constant Ada.Real_Time.Time :=
        Ada.Real_Time.Clock + Ada.Real_Time.Seconds (10);
      Force_Timeout   : Boolean := False;
      Force_Exception : Boolean := False;
   begin
      Control.Reach (Point);
      if Point = Cleanup_Detached then
         Control.Take_Error (Cleanup_Pause_Timeout, Force_Timeout);
         Control.Take_Error (Cleanup_Pause_Exception, Force_Exception);
         if Force_Exception then
            raise Program_Error with "injected renderer cleanup pause failure";
         elsif Force_Timeout then
            Released := False;
            return;
         end if;
      end if;
      loop
         Released := Control.Was_Released (Point);
         exit when Released or else Ada.Real_Time.Clock >= Deadline;
         delay 0.001;
      end loop;
   end Pause;

   procedure Wait_For
     (Point   : Pause_Point;
      Timeout : Duration;
      Reached : out Boolean)
   is
      Deadline : constant Ada.Real_Time.Time :=
        Ada.Real_Time.Clock + Ada.Real_Time.To_Time_Span (Timeout);
   begin
      loop
         Reached := Control.Was_Reached (Point);
         exit when Reached or else Ada.Real_Time.Clock >= Deadline;
         delay 0.001;
      end loop;
   end Wait_For;

   procedure Release (Point : Pause_Point) is
   begin
      Control.Release_Pause (Point);
   end Release;

   procedure Note_Attached (Address : System.Address) is
      Identity : Artifact_Identity;
   begin
      Control.Attach (Address, Identity);
   end Note_Attached;

   procedure Begin_Free
     (Address  : System.Address;
      Identity : out Artifact_Identity;
      Found    : out Boolean)
   is
   begin
      Control.Begin_Release (Address, Identity, Found);
   end Begin_Free;

   procedure Note_Freed (Identity : Artifact_Identity) is
   begin
      Control.Finish_Release (Identity);
   end Note_Freed;

   procedure Note_Damaged (Identity : Artifact_Identity) is
   begin
      Control.Damage_Release (Identity);
   end Note_Damaged;

   procedure Counts
     (Attached      : out Natural;
      Freed         : out Natural;
      Last_Attached : out Artifact_Identity;
      Last_Freed    : out Artifact_Identity;
      Overflowed    : out Boolean)
   is
   begin
      Control.Read_Counts
        (Attached, Freed, Last_Attached, Last_Freed, Overflowed);
   end Counts;

   procedure Arm_Failure (Point : Failure_Point) is
   begin
      Control.Arm_Error (Point);
   end Arm_Failure;

   procedure Take_Failure
     (Point : Failure_Point;
      Armed : out Boolean)
   is
   begin
      Control.Take_Error (Point, Armed);
   end Take_Failure;

   procedure Reset is
   begin
      Control.Reset_All;
   end Reset;
end Flyology_Serde_Generator.Rendering_Test_Hooks;
