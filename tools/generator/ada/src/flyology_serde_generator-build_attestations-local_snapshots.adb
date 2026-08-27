with Ada.Unchecked_Deallocation;
with Interfaces.C;
with System.Soft_Links;

with Flyology_Serde_Generator.Build_Attestations.File_ABI;
with Flyology_Serde_Generator.Build_Attestation_Test_Hooks;
with Flyology_Serde_Generator.Build_SHA_256;

package body Flyology_Serde_Generator.Build_Attestations.Local_Snapshots is
   package ABI renames Flyology_Serde_Generator.Build_Attestations.File_ABI;
   package C renames Interfaces.C;
   package SHA_256 renames Flyology_Serde_Generator.Build_SHA_256;
   package Test_Hooks renames Flyology_Serde_Generator.Build_Attestation_Test_Hooks;

   use type ABI.C_Int;
   use type ABI.C_Long;
   use type ABI.Object_Kind;
   use type Ada.Streams.Stream_Element_Offset;
   use type Budgets.Budget_State;
   use type Interfaces.Integer_64;
   use type Interfaces.Unsigned_64;

   Block_Bytes : constant Interfaces.Unsigned_64 := 4_096;
   Block_Capacity : constant Ada.Streams.Stream_Element_Offset :=
     Ada.Streams.Stream_Element_Offset (Block_Bytes);

   pragma Compile_Time_Error
     (Ada.Streams.Stream_Element_Offset'Size > Interfaces.Unsigned_64'Size,
      "Stream_Element_Offset is wider than the snapshot query arithmetic");
   pragma Compile_Time_Error
     (Ada.Streams.Stream_Element_Offset'First >= 0,
      "Stream_Element_Offset must have a negative lower bound");
   pragma Compile_Time_Error
     (Ada.Streams.Stream_Element_Offset'Last < 0,
      "Stream_Element_Offset must have a nonnegative upper bound");

   type Identity is record
      Device                  : Interfaces.Unsigned_64 := 0;
      Inode                   : Interfaces.Unsigned_64 := 0;
      Size                    : Interfaces.Integer_64 := 0;
      Modification_Second     : Interfaces.Integer_64 := 0;
      Modification_Nanosecond : Interfaces.Integer_64 := 0;
      Change_Second           : Interfaces.Integer_64 := 0;
      Change_Nanosecond       : Interfaces.Integer_64 := 0;
      Kind                    : ABI.Object_Kind := ABI.Unknown_Object;
   end record;

   type Path_Access is access String;

   type Byte_Block;
   type Byte_Block_Access is access Byte_Block;
   type Byte_Block is record
      Data : Ada.Streams.Stream_Element_Array (1 .. Block_Capacity);
      Used : Ada.Streams.Stream_Element_Offset range 0 .. Block_Capacity := 0;
      Next : Byte_Block_Access := null;
   end record;

   type Root_Payload is record
      Session                       : Budgets.Session_Tag;
      Descriptor                    : aliased ABI.Descriptor := ABI.Invalid_Descriptor;
      Opened                        : Identity;
      Maximum_Path_Bytes            : Limit_Value;
      Maximum_Directory_Depth       : Limit_Value;
      Maximum_Source_Bytes_Per_File : Limit_Value;
      Maximum_Total_Source_Bytes    : Limit_Value;
      Accepted_Source_Bytes         : Interfaces.Unsigned_64 := 0;
   end record;

   type Snapshot_Payload is record
      Session : Budgets.Session_Tag;
      Root    : Identity;
      Path    : Path_Access := null;
      First   : Byte_Block_Access := null;
      Last    : Byte_Block_Access := null;
      Length  : Interfaces.Unsigned_64 := 0;
      Digest  : SHA_256.Hex_Digest := [others => '0'];
   end record;

   procedure Free_Path is new Ada.Unchecked_Deallocation (String, Path_Access);
   procedure Free_Block is new Ada.Unchecked_Deallocation (Byte_Block, Byte_Block_Access);
   procedure Free_Root is new Ada.Unchecked_Deallocation (Root_Payload, Root_Payload_Access);
   procedure Free_Snapshot is new Ada.Unchecked_Deallocation
     (Snapshot_Payload, Snapshot_Payload_Access);

   function Same_Node (Left, Right : Identity) return Boolean is
     (Left.Device = Right.Device
      and then Left.Inode = Right.Inode
      and then Left.Kind = Right.Kind);

   function Same_Identity (Left, Right : Identity) return Boolean is
     (Same_Node (Left, Right)
      and then Left.Size = Right.Size
      and then Left.Modification_Second = Right.Modification_Second
      and then Left.Modification_Nanosecond = Right.Modification_Nanosecond
      and then Left.Change_Second = Right.Change_Second
      and then Left.Change_Nanosecond = Right.Change_Nanosecond);

   procedure Close_Once
     (Target : not null access ABI.Descriptor;
      Clean  : out Boolean)
   is
      Result : ABI.C_Int := 0;
   begin
      Clean := True;
      if Target.all = ABI.Invalid_Descriptor then
         return;
      end if;

      System.Soft_Links.Abort_Defer.all;
      begin
         Result := ABI.Close (Target.all);
         Target.all := ABI.Invalid_Descriptor;
         if Test_Hooks.Enabled then
            Test_Hooks.Note_Snapshot_Descriptor_Released;
            declare
               Inject : Boolean;
            begin
               Test_Hooks.Take_Snapshot_Failure
                 (Test_Hooks.Snapshot_Close_Failed, Inject);
               if Inject then
                  Result := -1;
               end if;
            end;
         end if;
      exception
         when others =>
            Target.all := ABI.Invalid_Descriptor;
            System.Soft_Links.Abort_Undefer.all;
            raise;
      end;
      System.Soft_Links.Abort_Undefer.all;
      Clean := Result = 0;
   exception
      when others =>
         Target.all := ABI.Invalid_Descriptor;
         Clean := False;
   end Close_Once;

   procedure Discard_Blocks
     (First : in out Byte_Block_Access;
      Last  : in out Byte_Block_Access;
      Clean : out Boolean)
   is
      Current      : Byte_Block_Access := First;
      Next         : Byte_Block_Access;
      Node_Clean   : Boolean;
   begin
      Clean := True;
      First := null;
      Last := null;
      while Current /= null loop
         Next := Current.Next;
         Current.Next := null;
         Node_Clean := True;
         begin
            Free_Block (Current);
            if Test_Hooks.Enabled then
               Test_Hooks.Note_Snapshot_Block_Released;
               declare
                  Inject : Boolean;
               begin
                  Test_Hooks.Take_Snapshot_Failure
                    (Test_Hooks.Snapshot_Block_Release, Inject);
                  Node_Clean := not Inject;
               end;
            end if;
         exception
            when others =>
               Node_Clean := False;
         end;
         Clean := Clean and Node_Clean;
         Current := Next;
      end loop;
   exception
      when others =>
         Clean := False;
   end Discard_Blocks;

   procedure Discard_Root
     (Value : in out Root_Payload_Access;
      Clean : out Boolean)
   is
      Saved       : Root_Payload_Access := Value;
      Closed      : Boolean := True;
      Deallocated : Boolean := True;
   begin
      Value := null;
      if Saved /= null then
         Close_Once (Saved.Descriptor'Access, Closed);
         begin
            Free_Root (Saved);
            if Test_Hooks.Enabled then
               Test_Hooks.Note_Snapshot_Payload_Released;
               declare
                  Inject : Boolean;
               begin
                  Test_Hooks.Take_Snapshot_Failure
                    (Test_Hooks.Snapshot_Payload_Release, Inject);
                  Deallocated := not Inject;
               end;
            end if;
         exception
            when others =>
               Deallocated := False;
         end;
      end if;
      Clean := Closed and Deallocated;
   exception
      when others =>
         Clean := False;
   end Discard_Root;

   procedure Discard_Snapshot
     (Value : in out Snapshot_Payload_Access;
      Clean : out Boolean)
   is
      Saved         : Snapshot_Payload_Access := Value;
      Path_Clean    : Boolean := True;
      Blocks_Clean  : Boolean := True;
      Deallocated   : Boolean := True;
   begin
      Value := null;
      if Saved /= null then
         begin
            Free_Path (Saved.Path);
            if Test_Hooks.Enabled then
               Test_Hooks.Note_Snapshot_Path_Released;
               declare
                  Inject : Boolean;
               begin
                  Test_Hooks.Take_Snapshot_Failure
                    (Test_Hooks.Snapshot_Path_Release, Inject);
                  Path_Clean := not Inject;
               end;
            end if;
         exception
            when others =>
               Path_Clean := False;
         end;
         Discard_Blocks (Saved.First, Saved.Last, Blocks_Clean);
         begin
            Free_Snapshot (Saved);
            if Test_Hooks.Enabled then
               Test_Hooks.Note_Snapshot_Payload_Released;
               declare
                  Inject : Boolean;
               begin
                  Test_Hooks.Take_Snapshot_Failure
                    (Test_Hooks.Snapshot_Payload_Release, Inject);
                  Deallocated := not Inject;
               end;
            end if;
         exception
            when others =>
               Deallocated := False;
         end;
      end if;
      Clean := Path_Clean and Blocks_Clean and Deallocated;
   exception
      when others =>
         Clean := False;
   end Discard_Snapshot;

   overriding procedure Finalize (Value : in out Root_Holder) is
      Saved_Session : Budgets.Session_Tag;
      Had_Value     : constant Boolean := Value.Value /= null;
      Clean         : Boolean;
   begin
      if Had_Value then
         Saved_Session := Value.Value.Session;
      end if;
      Discard_Root (Value.Value, Clean);
      if Had_Value
        and then not Clean
        and then Budgets.Matches (Value.Owner.all, Saved_Session)
      then
         Budgets.Poison (Value.Owner.all);
      end if;
   exception
      when others =>
         if Had_Value
           and then Budgets.Matches (Value.Owner.all, Saved_Session)
         then
            Budgets.Poison (Value.Owner.all);
         end if;
   end Finalize;

   overriding procedure Finalize (Value : in out Snapshot_Holder) is
      Saved_Session : Budgets.Session_Tag;
      Had_Value     : constant Boolean := Value.Value /= null;
      Clean         : Boolean;
   begin
      if Had_Value then
         Saved_Session := Value.Value.Session;
      end if;
      Discard_Snapshot (Value.Value, Clean);
      if Had_Value
        and then not Clean
        and then Budgets.Matches (Value.Owner.all, Saved_Session)
      then
         Budgets.Poison (Value.Owner.all);
      end if;
   exception
      when others =>
         if Had_Value
           and then Budgets.Matches (Value.Owner.all, Saved_Session)
         then
            Budgets.Poison (Value.Owner.all);
         end if;
   end Finalize;

   type Descriptor_Guard (Owner : not null access Budgets.Budget) is
     new Ada.Finalization.Limited_Controlled with record
      Value   : aliased ABI.Descriptor := ABI.Invalid_Descriptor;
      Session : Budgets.Session_Tag;
   end record;

   overriding procedure Finalize (Value : in out Descriptor_Guard) is
      Clean : Boolean;
   begin
      Close_Once (Value.Value'Access, Clean);
      if not Clean and then Budgets.Matches (Value.Owner.all, Value.Session) then
         Budgets.Poison (Value.Owner.all);
      end if;
   exception
      when others =>
         if Budgets.Matches (Value.Owner.all, Value.Session) then
            Budgets.Poison (Value.Owner.all);
         end if;
   end Finalize;

   type Block_Chain_Guard (Owner : not null access Budgets.Budget) is
     new Ada.Finalization.Limited_Controlled with record
      Session : Budgets.Session_Tag;
      First   : Byte_Block_Access := null;
      Last    : Byte_Block_Access := null;
   end record;

   overriding procedure Finalize (Value : in out Block_Chain_Guard) is
      Clean : Boolean;
   begin
      Discard_Blocks (Value.First, Value.Last, Clean);
      if not Clean and then Budgets.Matches (Value.Owner.all, Value.Session) then
         Budgets.Poison (Value.Owner.all);
      end if;
   exception
      when others =>
         if Budgets.Matches (Value.Owner.all, Value.Session) then
            Budgets.Poison (Value.Owner.all);
         end if;
   end Finalize;

   type Path_Guard (Owner : not null access Budgets.Budget) is
     new Ada.Finalization.Limited_Controlled with record
      Session : Budgets.Session_Tag;
      Value   : Path_Access := null;
   end record;

   overriding procedure Finalize (Value : in out Path_Guard) is
      Had_Value : constant Boolean := Value.Value /= null;
      Clean     : Boolean := True;
   begin
      Free_Path (Value.Value);
      if Test_Hooks.Enabled and then Had_Value then
         Test_Hooks.Note_Snapshot_Path_Released;
         declare
            Inject : Boolean;
         begin
            Test_Hooks.Take_Snapshot_Failure
              (Test_Hooks.Snapshot_Path_Release, Inject);
            Clean := not Inject;
         end;
      end if;
      if not Clean and then Budgets.Matches (Value.Owner.all, Value.Session) then
         Budgets.Poison (Value.Owner.all);
      end if;
   exception
      when others =>
         if Budgets.Matches (Value.Owner.all, Value.Session) then
            Budgets.Poison (Value.Owner.all);
         end if;
   end Finalize;

   type Snapshot_Guard (Owner : not null access Budgets.Budget) is
     new Ada.Finalization.Limited_Controlled with record
      Session : Budgets.Session_Tag;
      Value   : Snapshot_Payload_Access := null;
   end record;

   overriding procedure Finalize (Value : in out Snapshot_Guard) is
      Clean : Boolean;
   begin
      Discard_Snapshot (Value.Value, Clean);
      if not Clean and then Budgets.Matches (Value.Owner.all, Value.Session) then
         Budgets.Poison (Value.Owner.all);
      end if;
   exception
      when others =>
         if Budgets.Matches (Value.Owner.all, Value.Session) then
            Budgets.Poison (Value.Owner.all);
         end if;
   end Finalize;

   procedure Set_Root_Budget_Status
     (Owner  : in out Budgets.Budget;
      Status : out Root_Status) is
   begin
      case Budgets.Current_State (Owner) is
         when Budgets.Exhausted =>
            Status := Root_Budget_Exhausted;
         when Budgets.Failed =>
            Status := Root_Budget_Failed;
         when Budgets.Active =>
            Status := Root_Internal_Failure;
            Budgets.Poison (Owner);
      end case;
   end Set_Root_Budget_Status;

   procedure Set_Capture_Budget_Status
     (Owner  : in out Budgets.Budget;
      Status : out Capture_Status) is
   begin
      case Budgets.Current_State (Owner) is
         when Budgets.Exhausted =>
            Status := Capture_Budget_Exhausted;
         when Budgets.Failed =>
            Status := Capture_Budget_Failed;
         when Budgets.Active =>
            Status := Capture_Internal_Failure;
            Budgets.Poison (Owner);
      end case;
   end Set_Capture_Budget_Status;

   procedure Set_Query_Budget_Status
     (Owner  : in out Budgets.Budget;
      Status : out Query_Status) is
   begin
      case Budgets.Current_State (Owner) is
         when Budgets.Exhausted =>
            Status := Query_Budget_Exhausted;
         when Budgets.Failed =>
            Status := Query_Budget_Failed;
         when Budgets.Active =>
            Status := Query_Internal_Failure;
            Budgets.Poison (Owner);
      end case;
   end Set_Query_Budget_Status;

   procedure Reserve_Root
     (Owner  : in out Budgets.Budget;
      Amount : Budgets.Charge_Amount;
      Status : in out Root_Status)
   is
      Granted : Boolean;
   begin
      Budgets.Reserve (Owner, Budgets.Work_Units, Amount, Granted);
      if not Granted then
         Set_Root_Budget_Status (Owner, Status);
      end if;
   exception
      when others =>
         Budgets.Poison (Owner);
         Status := Root_Internal_Failure;
   end Reserve_Root;

   procedure Reserve_Capture
     (Owner  : in out Budgets.Budget;
      Kind   : Budgets.Category;
      Amount : Budgets.Charge_Amount;
      Status : in out Capture_Status)
   is
      Granted : Boolean;
   begin
      Budgets.Reserve (Owner, Kind, Amount, Granted);
      if not Granted then
         Set_Capture_Budget_Status (Owner, Status);
      end if;
   exception
      when others =>
         Budgets.Poison (Owner);
         Status := Capture_Internal_Failure;
   end Reserve_Capture;

   procedure Reserve_Query
     (Owner  : in out Budgets.Budget;
      Amount : Budgets.Charge_Amount;
      Status : in out Query_Status)
   is
      Granted : Boolean;
   begin
      Budgets.Reserve (Owner, Budgets.Work_Units, Amount, Granted);
      if not Granted then
         Set_Query_Budget_Status (Owner, Status);
      end if;
   exception
      when others =>
         Budgets.Poison (Owner);
         Status := Query_Internal_Failure;
   end Reserve_Query;

   function Is_Dot_Component (Value : String; First, Last : Positive) return Boolean is
     ((First = Last and then Value (First) = '.')
      or else
      (Last - First = 1 and then Value (First) = '.' and then Value (Last) = '.'));

   function Is_Normal_Absolute_Path (Value : String) return Boolean is
      Component_First : Positive;
   begin
      if Value'Length = 0 or else Value (Value'First) /= '/' then
         return False;
      elsif Value'Length = 1 then
         return True;
      end if;
      Component_First := Value'First + 1;
      for Index in Component_First .. Value'Last loop
         if Value (Index) = Character'Val (0) or else Value (Index) = '\' then
            return False;
         elsif Value (Index) = '/' then
            if Index = Component_First
              or else Is_Dot_Component (Value, Component_First, Index - 1)
              or else Index = Value'Last
            then
               return False;
            end if;
            Component_First := Index + 1;
         end if;
      end loop;
      return not Is_Dot_Component (Value, Component_First, Value'Last);
   end Is_Normal_Absolute_Path;

   function Is_Portable (Value : Character) return Boolean is
     (Value in 'A' .. 'Z'
      or else Value in 'a' .. 'z'
      or else Value in '0' .. '9'
      or else Value = '_'
      or else Value = '-'
      or else Value = '.'
      or else Value = '/');

   procedure Validate_Relative_Path
     (Value           : String;
      Maximum_Depth   : Limit_Value;
      Valid           : out Boolean;
      Depth_Exceeded  : out Boolean)
   is
      Component_First : Positive;
      Depth           : Interfaces.Unsigned_64 := 0;
   begin
      Valid := False;
      Depth_Exceeded := False;
      if Value'Length = 0
        or else Value (Value'First) = '/'
        or else Value (Value'Last) = '/'
      then
         return;
      end if;
      Component_First := Value'First;
      for Index in Value'Range loop
         if not Is_Portable (Value (Index)) then
            return;
         elsif Value (Index) = '/' then
            if Index = Component_First
              or else Is_Dot_Component (Value, Component_First, Index - 1)
            then
               return;
            end if;
            Depth := Depth + 1;
            if Depth > Maximum_Depth then
               Depth_Exceeded := True;
               return;
            end if;
            Component_First := Index + 1;
         end if;
      end loop;
      Valid := not Is_Dot_Component (Value, Component_First, Value'Last);
   exception
      when others =>
         Valid := False;
   end Validate_Relative_Path;

   procedure Decode_Kind
     (Raw     : ABI.C_Int;
      Into    : out ABI.Object_Kind;
      Success : out Boolean) is
   begin
      Success := True;
      case Raw is
         when 0 => Into := ABI.Unknown_Object;
         when 1 => Into := ABI.Directory_Object;
         when 2 => Into := ABI.Regular_Object;
         when 3 => Into := ABI.Other_Object;
         when others =>
            Into := ABI.Unknown_Object;
            Success := False;
      end case;
   end Decode_Kind;

   procedure Read_Root_Identity
     (Owner      : in out Budgets.Budget;
      Descriptor : ABI.Descriptor;
      Into       : out Identity;
      Status     : in out Root_Status)
   is
      Device              : aliased Interfaces.Unsigned_64 := 0;
      Inode               : aliased Interfaces.Unsigned_64 := 0;
      Size                : aliased Interfaces.Integer_64 := 0;
      Modification_Second : aliased Interfaces.Integer_64 := 0;
      Modification_Nsec   : aliased Interfaces.Integer_64 := 0;
      Change_Second       : aliased Interfaces.Integer_64 := 0;
      Change_Nsec         : aliased Interfaces.Integer_64 := 0;
      Raw_Kind            : aliased ABI.C_Int := 0;
      Result              : ABI.C_Int;
      Error               : ABI.C_Int;
      Kind                : ABI.Object_Kind;
      Kind_Valid          : Boolean;
   begin
      loop
         Reserve_Root (Owner, 1, Status);
         exit when Status /= Root_Succeeded;
         if Test_Hooks.Enabled then
            declare
               Inject : Boolean;
            begin
               Test_Hooks.Take_Snapshot_Failure
                 (Test_Hooks.Snapshot_Identity_Failed, Inject);
               if Inject then
                  Status := Root_Identity_Failed;
                  return;
               end if;
            end;
         end if;
         Result :=
           ABI.Read_Identity
             (Descriptor, Device'Access, Inode'Access, Size'Access,
              Modification_Second'Access, Modification_Nsec'Access,
              Change_Second'Access, Change_Nsec'Access, Raw_Kind'Access);
         exit when Result = 0;
         Error := ABI.Current_Errno;
         if Error /= ABI.Errno_Interrupted then
            Status := Root_Identity_Failed;
            return;
         end if;
      end loop;
      if Status /= Root_Succeeded then
         return;
      end if;
      Decode_Kind (Raw_Kind, Kind, Kind_Valid);
      if not Kind_Valid then
         Status := Root_Identity_Failed;
         return;
      end if;
      Into :=
        (Device                  => Device,
         Inode                   => Inode,
         Size                    => Size,
         Modification_Second     => Modification_Second,
         Modification_Nanosecond => Modification_Nsec,
         Change_Second           => Change_Second,
         Change_Nanosecond       => Change_Nsec,
         Kind                    => Kind);
   end Read_Root_Identity;

   procedure Read_Capture_Identity
     (Owner      : in out Budgets.Budget;
      Descriptor : ABI.Descriptor;
      Into       : out Identity;
      Status     : in out Capture_Status)
   is
      Device              : aliased Interfaces.Unsigned_64 := 0;
      Inode               : aliased Interfaces.Unsigned_64 := 0;
      Size                : aliased Interfaces.Integer_64 := 0;
      Modification_Second : aliased Interfaces.Integer_64 := 0;
      Modification_Nsec   : aliased Interfaces.Integer_64 := 0;
      Change_Second       : aliased Interfaces.Integer_64 := 0;
      Change_Nsec         : aliased Interfaces.Integer_64 := 0;
      Raw_Kind            : aliased ABI.C_Int := 0;
      Result              : ABI.C_Int;
      Error               : ABI.C_Int;
      Kind                : ABI.Object_Kind;
      Kind_Valid          : Boolean;
   begin
      loop
         Reserve_Capture (Owner, Budgets.Work_Units, 1, Status);
         exit when Status /= Capture_Succeeded;
         if Test_Hooks.Enabled then
            declare
               Inject : Boolean;
            begin
               Test_Hooks.Take_Snapshot_Failure
                 (Test_Hooks.Snapshot_Identity_Failed, Inject);
               if Inject then
                  Status := Capture_Identity_Failed;
                  return;
               end if;
            end;
         end if;
         Result :=
           ABI.Read_Identity
             (Descriptor, Device'Access, Inode'Access, Size'Access,
              Modification_Second'Access, Modification_Nsec'Access,
              Change_Second'Access, Change_Nsec'Access, Raw_Kind'Access);
         exit when Result = 0;
         Error := ABI.Current_Errno;
         if Error /= ABI.Errno_Interrupted then
            Status := Capture_Identity_Failed;
            return;
         end if;
      end loop;
      if Status /= Capture_Succeeded then
         return;
      end if;
      Decode_Kind (Raw_Kind, Kind, Kind_Valid);
      if not Kind_Valid then
         Status := Capture_Identity_Failed;
         return;
      end if;
      Into :=
        (Device                  => Device,
         Inode                   => Inode,
         Size                    => Size,
         Modification_Second     => Modification_Second,
         Modification_Nanosecond => Modification_Nsec,
         Change_Second           => Change_Second,
         Change_Nanosecond       => Change_Nsec,
         Kind                    => Kind);
   end Read_Capture_Identity;

   procedure Open_Absolute
     (Owner   : in out Budgets.Budget;
      Path    : String;
      Into    : in out Descriptor_Guard;
      Status  : in out Root_Status)
   is
      C_Path : aliased C.char_array := C.To_C (Path);
      Result : ABI.Descriptor;
      Error  : ABI.C_Int;
      Injected_Interrupt : Boolean := False;
   begin
      loop
         Injected_Interrupt := False;
         Reserve_Root (Owner, 1, Status);
         exit when Status /= Root_Succeeded;
         if Test_Hooks.Enabled then
            declare
               Interrupt : Boolean;
               Fail      : Boolean;
            begin
               Test_Hooks.Take_Snapshot_Failure
                 (Test_Hooks.Snapshot_Open_Interrupted, Interrupt);
               Test_Hooks.Take_Snapshot_Failure
                 (Test_Hooks.Snapshot_Open_Failed, Fail);
               if Interrupt then
                  Result := ABI.Invalid_Descriptor;
                  Error := ABI.Errno_Interrupted;
                  Injected_Interrupt := True;
               elsif Fail then
                  Status := Root_Open_Failed;
                  return;
               end if;
               if Interrupt then
                  goto Open_Absolute_Result;
               end if;
            end;
         end if;
         System.Soft_Links.Abort_Defer.all;
         begin
            Result := ABI.Open_Absolute_Directory (C_Path'Address);
            if Result /= ABI.Invalid_Descriptor then
               Into.Value := Result;
               if Test_Hooks.Enabled then
                  Test_Hooks.Note_Snapshot_Descriptor_Attached;
               end if;
            end if;
         exception
            when others =>
               System.Soft_Links.Abort_Undefer.all;
               raise;
         end;
         System.Soft_Links.Abort_Undefer.all;
         <<Open_Absolute_Result>>
         exit when Result /= ABI.Invalid_Descriptor;
         if not Injected_Interrupt then
            Error := ABI.Current_Errno;
         end if;
         if Error /= ABI.Errno_Interrupted then
            Status := Root_Open_Failed;
            return;
         end if;
      end loop;
   end Open_Absolute;

   procedure Open_At
     (Owner     : in out Budgets.Budget;
      Parent    : ABI.Descriptor;
      Name      : String;
      Directory : Boolean;
      Into      : in out Descriptor_Guard;
      Status    : in out Capture_Status)
   is
      C_Name : aliased C.char_array := C.To_C (Name);
      Result : ABI.Descriptor;
      Error  : ABI.C_Int;
      Injected_Interrupt : Boolean := False;
   begin
      loop
         Injected_Interrupt := False;
         Reserve_Capture (Owner, Budgets.Work_Units, 1, Status);
         exit when Status /= Capture_Succeeded;
         if Test_Hooks.Enabled then
            declare
               Interrupt : Boolean;
               Fail      : Boolean;
            begin
               Test_Hooks.Take_Snapshot_Failure
                 (Test_Hooks.Snapshot_Open_Interrupted, Interrupt);
               Test_Hooks.Take_Snapshot_Failure
                 (Test_Hooks.Snapshot_Open_Failed, Fail);
               if Interrupt then
                  Result := ABI.Invalid_Descriptor;
                  Error := ABI.Errno_Interrupted;
                  Injected_Interrupt := True;
               elsif Fail then
                  Status := Capture_Open_Failed;
                  return;
               end if;
               if Interrupt then
                  goto Open_At_Result;
               end if;
            end;
         end if;
         System.Soft_Links.Abort_Defer.all;
         begin
            Result :=
              (if Directory
               then ABI.Open_Child_Directory (Parent, C_Name'Address)
               else ABI.Open_Child_Object (Parent, C_Name'Address));
            if Result /= ABI.Invalid_Descriptor then
               Into.Value := Result;
               if Test_Hooks.Enabled then
                  Test_Hooks.Note_Snapshot_Descriptor_Attached;
               end if;
            end if;
         exception
            when others =>
               System.Soft_Links.Abort_Undefer.all;
               raise;
         end;
         System.Soft_Links.Abort_Undefer.all;
         <<Open_At_Result>>
         exit when Result /= ABI.Invalid_Descriptor;
         if not Injected_Interrupt then
            Error := ABI.Current_Errno;
         end if;
         if Error /= ABI.Errno_Interrupted then
            Status := Capture_Open_Failed;
            return;
         end if;
      end loop;
   end Open_At;

   procedure Close_Capture
     (Value  : in out Descriptor_Guard;
      Status : in out Capture_Status)
   is
      Clean : Boolean;
   begin
      Close_Once (Value.Value'Access, Clean);
      if not Clean then
         if Status = Capture_Succeeded then
            Status := Capture_Close_Failed;
         end if;
         if Budgets.Matches (Value.Owner.all, Value.Session) then
            Budgets.Poison (Value.Owner.all);
         end if;
      end if;
   end Close_Capture;

   procedure Open_Final
     (Owner         : in out Budgets.Budget;
      Root          : ABI.Descriptor;
      Relative_Path : String;
      Parent_Guard  : in out Descriptor_Guard;
      Final_Guard   : in out Descriptor_Guard;
      Status        : in out Capture_Status)
   is
      Current         : ABI.Descriptor := Root;
      Component_First : Positive := Relative_Path'First;
      Next_Guard      : Descriptor_Guard (Parent_Guard.Owner);
   begin
      Next_Guard.Session := Parent_Guard.Session;
      for Index in Relative_Path'Range loop
         if Relative_Path (Index) = '/' then
            Open_At
              (Owner, Current, Relative_Path (Component_First .. Index - 1), True,
               Next_Guard, Status);
            exit when Status /= Capture_Succeeded;
            Close_Capture (Parent_Guard, Status);
            exit when Status /= Capture_Succeeded;
            Parent_Guard.Value := Next_Guard.Value;
            Next_Guard.Value := ABI.Invalid_Descriptor;
            Current := Parent_Guard.Value;
            Component_First := Index + 1;
         end if;
      end loop;
      if Status = Capture_Succeeded then
         Open_At
           (Owner, Current, Relative_Path (Component_First .. Relative_Path'Last), False,
            Final_Guard, Status);
      end if;
   end Open_Final;

   procedure Append
     (Chain  : in out Block_Chain_Guard;
      Data   : Ada.Streams.Stream_Element_Array;
      Status : in out Capture_Status)
   is
      Position : Ada.Streams.Stream_Element_Offset := Data'First;
   begin
      while Status = Capture_Succeeded and then Position <= Data'Last loop
         if Chain.Last = null or else Chain.Last.Used = Block_Capacity then
            declare
               Node : Byte_Block_Access := null;
            begin
               System.Soft_Links.Abort_Defer.all;
               begin
                  if Test_Hooks.Enabled then
                     declare
                        Inject : Boolean;
                     begin
                        Test_Hooks.Take_Snapshot_Failure
                          (Test_Hooks.Snapshot_Block_Storage, Inject);
                        if Inject then
                           raise Storage_Error with "injected snapshot block allocation failure";
                        end if;
                     end;
                  end if;
                  Node := new Byte_Block;
                  if Chain.Last = null then
                     Chain.First := Node;
                  else
                     Chain.Last.Next := Node;
                  end if;
                  Chain.Last := Node;
                  Node := null;
                  if Test_Hooks.Enabled then
                     Test_Hooks.Note_Snapshot_Block_Allocated;
                  end if;
               exception
                  when others =>
                     System.Soft_Links.Abort_Undefer.all;
                     raise;
               end;
               System.Soft_Links.Abort_Undefer.all;
            end;
         end if;
         declare
            Available : constant Ada.Streams.Stream_Element_Offset :=
              Block_Capacity - Chain.Last.Used;
            Remaining : constant Ada.Streams.Stream_Element_Offset := Data'Last - Position + 1;
            Count     : constant Ada.Streams.Stream_Element_Offset :=
              Ada.Streams.Stream_Element_Offset'Min (Available, Remaining);
            Target_First : constant Ada.Streams.Stream_Element_Offset := Chain.Last.Used + 1;
         begin
            Chain.Last.Data (Target_First .. Target_First + Count - 1) :=
              Data (Position .. Position + Count - 1);
            Chain.Last.Used := Chain.Last.Used + Count;
            Position := Position + Count;
         end;
      end loop;
   exception
      when Storage_Error =>
         Status := Capture_Allocation_Failed;
         Budgets.Poison (Chain.Owner.all);
      when others =>
         Status := Capture_Internal_Failure;
         Budgets.Poison (Chain.Owner.all);
   end Append;

   procedure Open_Root
     (Path                          : String;
      Session                       : Budgets.Session_Tag;
      Maximum_Path_Bytes            : Limit_Value;
      Maximum_Directory_Depth       : Limit_Value;
      Maximum_Source_Bytes_Per_File : Limit_Value;
      Maximum_Total_Source_Bytes    : Limit_Value;
      Into                          : in out Root;
      Status                        : in out Root_Status)
   is
      Descriptor : Descriptor_Guard (Into.Owner);
      Opened     : Identity;
      Candidate  : Root_Holder (Into.Owner);
      Length     : Interfaces.Unsigned_64;
      Commit_Started : Boolean := False;
   begin
      Descriptor.Session := Session;
      if Status /= Root_Succeeded then
         return;
      elsif not Budgets.Matches (Into.Owner.all, Session) then
         Status := Root_Session_Foreign;
         return;
      end if;
      case Budgets.Current_State (Into.Owner.all) is
         when Budgets.Active => null;
         when Budgets.Exhausted =>
            Status := Root_Budget_Exhausted;
            return;
         when Budgets.Failed =>
            Status := Root_Budget_Failed;
            return;
      end case;
      if Into.Data.Value /= null then
         Status :=
           (if Budgets.Matches (Into.Owner.all, Into.Data.Value.Session)
            then Root_Owner_Not_Empty
            else Root_Session_Foreign);
         return;
      end if;

      Reserve_Root (Into.Owner.all, 1, Status);
      if Status /= Root_Succeeded then
         return;
      end if;
      Length := Interfaces.Unsigned_64 (Path'Length);
      if Length > Maximum_Path_Bytes then
         Status := Root_Limit_Exceeded;
         return;
      elsif Length = 0 then
         Status := Root_Invalid_Path;
         return;
      end if;
      Reserve_Root (Into.Owner.all, Budgets.Charge_Amount (Length), Status);
      if Status /= Root_Succeeded then
         return;
      elsif not Is_Normal_Absolute_Path (Path) then
         Status := Root_Invalid_Path;
         return;
      end if;

      Open_Absolute (Into.Owner.all, Path, Descriptor, Status);
      if Status /= Root_Succeeded then
         return;
      end if;
      Read_Root_Identity (Into.Owner.all, Descriptor.Value, Opened, Status);
      if Status /= Root_Succeeded then
         return;
      elsif Opened.Kind /= ABI.Directory_Object then
         Status := Root_Identity_Failed;
         return;
      end if;

      System.Soft_Links.Abort_Defer.all;
      begin
         if Test_Hooks.Enabled then
            declare
               Inject : Boolean;
            begin
               Test_Hooks.Take_Snapshot_Failure
                 (Test_Hooks.Snapshot_Payload_Storage, Inject);
               if Inject then
                  raise Storage_Error with "injected snapshot root allocation failure";
               end if;
            end;
         end if;
         Candidate.Value :=
           new Root_Payload'
             (Session                       => Session,
              Descriptor                    => Descriptor.Value,
              Opened                        => Opened,
              Maximum_Path_Bytes            => Maximum_Path_Bytes,
              Maximum_Directory_Depth       => Maximum_Directory_Depth,
              Maximum_Source_Bytes_Per_File => Maximum_Source_Bytes_Per_File,
              Maximum_Total_Source_Bytes    => Maximum_Total_Source_Bytes,
              Accepted_Source_Bytes         => 0);
         Descriptor.Value := ABI.Invalid_Descriptor;
         if Test_Hooks.Enabled then
            Test_Hooks.Note_Snapshot_Payload_Allocated;
         end if;
      exception
         when others =>
            System.Soft_Links.Abort_Undefer.all;
            raise;
      end;
      System.Soft_Links.Abort_Undefer.all;

      System.Soft_Links.Abort_Defer.all;
      begin
         if Test_Hooks.Enabled then
            declare
               Released : Boolean;
            begin
               Test_Hooks.Pause (Test_Hooks.Snapshot_Root_Precommit, Released);
               if not Released then
                  raise Program_Error with "snapshot root precommit hook timed out";
               end if;
            end;
         end if;
         Commit_Started := True;
         Into.Data.Value := Candidate.Value;
         Candidate.Value := null;
      exception
         when others =>
            System.Soft_Links.Abort_Undefer.all;
            raise;
      end;
      System.Soft_Links.Abort_Undefer.all;
   exception
      when Storage_Error =>
         if Commit_Started then
            raise;
         end if;
         Status := Root_Allocation_Failed;
         Budgets.Poison (Into.Owner.all);
      when others =>
         if Commit_Started then
            raise;
         end if;
         Status := Root_Internal_Failure;
         Budgets.Poison (Into.Owner.all);
   end Open_Root;

   procedure Capture
     (From          : in out Root;
      Relative_Path : String;
      Session       : Budgets.Session_Tag;
      Into          : in out File_Snapshot;
      Status        : in out Capture_Status)
   is
      Root_Current    : Identity;
      Root_Final      : Identity;
      Initial         : Identity;
      Final           : Identity;
      Verified        : Identity;
      Original_Parent : Descriptor_Guard (From.Owner);
      Original_File   : Descriptor_Guard (From.Owner);
      Verify_Parent   : Descriptor_Guard (From.Owner);
      Verify_File     : Descriptor_Guard (From.Owner);
      Chain           : Block_Chain_Guard (From.Owner);
      Path_Value      : Path_Guard (From.Owner);
      Candidate       : Snapshot_Guard (From.Owner);
      Hash            : SHA_256.Context;
      Binary_Digest   : SHA_256.Digest := [others => 0];
      Digest_Ready    : Boolean := False;
      Buffer          : aliased Ada.Streams.Stream_Element_Array (1 .. Block_Capacity);
      Result          : ABI.C_Long;
      Error           : ABI.C_Int;
      Request_Length  : Interfaces.Unsigned_64;
      Returned        : Interfaces.Unsigned_64;
      Total           : Interfaces.Unsigned_64 := 0;
      Per_Remaining   : Interfaces.Unsigned_64;
      Aggregate_Remaining : Interfaces.Unsigned_64;
      Remaining       : Interfaces.Unsigned_64;
      Valid_Path      : Boolean;
      Depth_Exceeded  : Boolean;
      Length          : Interfaces.Unsigned_64;
      Published_Total : Interfaces.Unsigned_64;
      Commit_Started  : Boolean := False;
      Perform_Read     : Boolean;
      Injected_Interrupt : Boolean;
   begin
      Original_Parent.Session := Session;
      Original_File.Session := Session;
      Verify_Parent.Session := Session;
      Verify_File.Session := Session;
      Chain.Session := Session;
      Path_Value.Session := Session;
      Candidate.Session := Session;
      if Status /= Capture_Succeeded then
         return;
      elsif From.Owner /= Into.Owner or else not Budgets.Matches (From.Owner.all, Session) then
         Status := Capture_Session_Foreign;
         return;
      end if;
      case Budgets.Current_State (From.Owner.all) is
         when Budgets.Active => null;
         when Budgets.Exhausted =>
            Status := Capture_Budget_Exhausted;
            return;
         when Budgets.Failed =>
            Status := Capture_Budget_Failed;
            return;
      end case;
      if From.Data.Value = null then
         Status := Capture_No_Root;
         return;
      elsif not Budgets.Matches (From.Owner.all, From.Data.Value.Session) then
         Status := Capture_Session_Foreign;
         return;
      elsif Into.Data.Value /= null then
         Status :=
           (if Budgets.Matches (Into.Owner.all, Into.Data.Value.Session)
            then Capture_Owner_Not_Empty
            else Capture_Session_Foreign);
         return;
      end if;

      Reserve_Capture (From.Owner.all, Budgets.Work_Units, 1, Status);
      if Status /= Capture_Succeeded then
         return;
      end if;
      Length := Interfaces.Unsigned_64 (Relative_Path'Length);
      if Length > From.Data.Value.Maximum_Path_Bytes then
         Status := Capture_Path_Limit_Exceeded;
         return;
      elsif Length = 0 then
         Status := Capture_Invalid_Path;
         return;
      end if;
      Reserve_Capture
        (From.Owner.all, Budgets.Work_Units, Budgets.Charge_Amount (Length), Status);
      if Status /= Capture_Succeeded then
         return;
      end if;
      Validate_Relative_Path
        (Relative_Path, From.Data.Value.Maximum_Directory_Depth,
         Valid_Path, Depth_Exceeded);
      if Depth_Exceeded then
         Status := Capture_Directory_Depth_Exceeded;
         return;
      elsif not Valid_Path then
         Status := Capture_Invalid_Path;
         return;
      end if;

      Read_Capture_Identity
        (From.Owner.all, From.Data.Value.Descriptor, Root_Current, Status);
      if Status /= Capture_Succeeded then
         return;
      elsif not Same_Identity (Root_Current, From.Data.Value.Opened)
        or else Root_Current.Kind /= ABI.Directory_Object
      then
         Status := Capture_Changed;
         return;
      end if;

      Open_Final
        (From.Owner.all, From.Data.Value.Descriptor, Relative_Path,
         Original_Parent, Original_File, Status);
      if Status /= Capture_Succeeded then
         return;
      end if;
      Read_Capture_Identity (From.Owner.all, Original_File.Value, Initial, Status);
      if Status /= Capture_Succeeded then
         return;
      elsif Initial.Kind /= ABI.Regular_Object then
         Status := Capture_Not_Regular;
         return;
      elsif Initial.Size < 0 then
         Status := Capture_Identity_Failed;
         return;
      end if;
      if Test_Hooks.Enabled then
         declare
            Released : Boolean;
         begin
            Test_Hooks.Pause (Test_Hooks.Snapshot_After_Initial_Identity, Released);
            if not Released then
               Status := Capture_Internal_Failure;
               Budgets.Poison (From.Owner.all);
               return;
            end if;
         end;
      end if;

      SHA_256.Initialize (Hash);
      loop
         Per_Remaining := From.Data.Value.Maximum_Source_Bytes_Per_File - Total;
         Aggregate_Remaining :=
           From.Data.Value.Maximum_Total_Source_Bytes
           - From.Data.Value.Accepted_Source_Bytes
           - Total;
         Remaining := Interfaces.Unsigned_64'Min (Per_Remaining, Aggregate_Remaining);
         Request_Length :=
           (if Remaining >= Block_Bytes then Block_Bytes else Remaining + 1);
         loop
            Perform_Read := True;
            Injected_Interrupt := False;
            Reserve_Capture (From.Owner.all, Budgets.Work_Units, 1, Status);
            exit when Status /= Capture_Succeeded;
            if Test_Hooks.Enabled then
               declare
                  Interrupt  : Boolean;
                  Fail       : Boolean;
                  Short      : Boolean;
                  Early_EOF  : Boolean;
                  Impossible : Boolean;
               begin
                  Test_Hooks.Take_Snapshot_Failure
                    (Test_Hooks.Snapshot_Read_Interrupted, Interrupt);
                  Test_Hooks.Take_Snapshot_Failure
                    (Test_Hooks.Snapshot_Read_Failed, Fail);
                  Test_Hooks.Take_Snapshot_Failure
                    (Test_Hooks.Snapshot_Read_Short, Short);
                  Test_Hooks.Take_Snapshot_Failure
                    (Test_Hooks.Snapshot_Premature_EOF, Early_EOF);
                  Test_Hooks.Take_Snapshot_Failure
                    (Test_Hooks.Snapshot_Impossible_Positive_Result, Impossible);
                  if Interrupt then
                     Result := -1;
                     Injected_Interrupt := True;
                     Perform_Read := False;
                  elsif Fail then
                     Status := Capture_Read_Failed;
                     Perform_Read := False;
                  elsif Early_EOF then
                     Result := 0;
                     Perform_Read := False;
                  elsif Impossible then
                     Result := ABI.C_Long (Request_Length + 1);
                     Perform_Read := False;
                  elsif Short and then Request_Length > 1 then
                     Request_Length := Interfaces.Unsigned_64'Min (Request_Length, 7);
                  end if;
               end;
            end if;
            exit when Status /= Capture_Succeeded;
            if Perform_Read then
               Result :=
                 ABI.Read
                   (Original_File.Value, Buffer (Buffer'First)'Address,
                    ABI.C_Size (Request_Length));
            end if;
            exit when Result >= 0;
            Error :=
              (if Injected_Interrupt then ABI.Errno_Interrupted else ABI.Current_Errno);
            if Error /= ABI.Errno_Interrupted then
               Status := Capture_Read_Failed;
               exit;
            end if;
         end loop;
         exit when Status /= Capture_Succeeded or else Result = 0;
         if Result < 0 or else Interfaces.Unsigned_64 (Result) > Request_Length then
            Status := Capture_Read_Failed;
            exit;
         end if;
         Returned := Interfaces.Unsigned_64 (Result);
         Reserve_Capture
           (From.Owner.all, Budgets.Input_Bytes, Budgets.Charge_Amount (Returned), Status);
         exit when Status /= Capture_Succeeded;
         if Returned > Per_Remaining then
            Status := Capture_Per_File_Limit_Exceeded;
            exit;
         elsif Returned > Aggregate_Remaining then
            Status := Capture_Aggregate_Limit_Exceeded;
            exit;
         end if;
         Reserve_Capture
           (From.Owner.all, Budgets.Work_Units, Budgets.Charge_Amount (Returned), Status);
         exit when Status /= Capture_Succeeded;
         Append
           (Chain,
            Buffer
              (Buffer'First
               .. Buffer'First + Ada.Streams.Stream_Element_Offset (Returned) - 1),
            Status);
         exit when Status /= Capture_Succeeded;
         SHA_256.Update
           (Hash,
            Buffer
              (Buffer'First
               .. Buffer'First + Ada.Streams.Stream_Element_Offset (Returned) - 1));
         if SHA_256.Is_Failed (Hash) then
            Status := Capture_Internal_Failure;
            Budgets.Poison (From.Owner.all);
            exit;
         end if;
         Total := Total + Returned;
      end loop;

      if Test_Hooks.Enabled and then Status = Capture_Succeeded then
         declare
            Released : Boolean;
         begin
            Test_Hooks.Pause (Test_Hooks.Snapshot_After_Read, Released);
            if not Released then
               Status := Capture_Internal_Failure;
               Budgets.Poison (From.Owner.all);
            end if;
         end;
      end if;

      if Status = Capture_Succeeded then
         Read_Capture_Identity (From.Owner.all, Original_File.Value, Final, Status);
      end if;
      if Status = Capture_Succeeded
        and then (not Same_Identity (Initial, Final)
                  or else Final.Size < 0
                  or else Interfaces.Unsigned_64 (Final.Size) /= Total)
      then
         Status := Capture_Changed;
      end if;
      if Status = Capture_Succeeded then
         Open_Final
           (From.Owner.all, From.Data.Value.Descriptor, Relative_Path,
            Verify_Parent, Verify_File, Status);
      end if;
      if Status = Capture_Succeeded then
         Read_Capture_Identity (From.Owner.all, Verify_File.Value, Verified, Status);
      end if;
      if Status = Capture_Succeeded and then not Same_Identity (Final, Verified) then
         Status := Capture_Changed;
      end if;
      if Status = Capture_Succeeded then
         Read_Capture_Identity
           (From.Owner.all, From.Data.Value.Descriptor, Root_Final, Status);
      end if;
      if Status = Capture_Succeeded
        and then not Same_Identity (Root_Current, Root_Final)
      then
         Status := Capture_Changed;
      end if;
      if Status = Capture_Succeeded then
         SHA_256.Finish (Hash, Binary_Digest, Digest_Ready);
         if not Digest_Ready then
            Status := Capture_Internal_Failure;
            Budgets.Poison (From.Owner.all);
         end if;
      end if;

      Close_Capture (Verify_File, Status);
      Close_Capture (Verify_Parent, Status);
      Close_Capture (Original_File, Status);
      Close_Capture (Original_Parent, Status);
      if Status /= Capture_Succeeded then
         return;
      end if;

      Published_Total := From.Data.Value.Accepted_Source_Bytes + Total;
      System.Soft_Links.Abort_Defer.all;
      begin
         if Test_Hooks.Enabled then
            declare
               Inject : Boolean;
            begin
               Test_Hooks.Take_Snapshot_Failure
                 (Test_Hooks.Snapshot_Path_Storage, Inject);
               if Inject then
                  raise Storage_Error with "injected snapshot path allocation failure";
               end if;
            end;
         end if;
         Path_Value.Value := new String'(Relative_Path);
         if Test_Hooks.Enabled then
            Test_Hooks.Note_Snapshot_Path_Allocated;
            declare
               Inject : Boolean;
            begin
               Test_Hooks.Take_Snapshot_Failure
                 (Test_Hooks.Snapshot_Payload_Storage, Inject);
               if Inject then
                  raise Storage_Error with "injected snapshot payload allocation failure";
               end if;
            end;
         end if;
         Candidate.Value :=
           new Snapshot_Payload'
             (Session => Session,
              Root    => From.Data.Value.Opened,
              Path    => null,
              First   => null,
              Last    => null,
              Length  => Total,
              Digest  => SHA_256.To_Hex (Binary_Digest));
         if Test_Hooks.Enabled then
            Test_Hooks.Note_Snapshot_Payload_Allocated;
         end if;
         Candidate.Value.Path := Path_Value.Value;
         Path_Value.Value := null;
         Candidate.Value.First := Chain.First;
         Candidate.Value.Last := Chain.Last;
         Chain.First := null;
         Chain.Last := null;
      exception
         when others =>
            System.Soft_Links.Abort_Undefer.all;
            raise;
      end;
      System.Soft_Links.Abort_Undefer.all;

      System.Soft_Links.Abort_Defer.all;
      begin
         if Test_Hooks.Enabled then
            declare
               Released : Boolean;
            begin
               Test_Hooks.Pause (Test_Hooks.Snapshot_Capture_Precommit, Released);
               if not Released then
                  raise Program_Error with "snapshot capture precommit hook timed out";
               end if;
            end;
         end if;
         Commit_Started := True;
         From.Data.Value.Accepted_Source_Bytes := Published_Total;
         Into.Data.Value := Candidate.Value;
         Candidate.Value := null;
      exception
         when others =>
            System.Soft_Links.Abort_Undefer.all;
            raise;
      end;
      System.Soft_Links.Abort_Undefer.all;
   exception
      when Storage_Error =>
         if Commit_Started then
            raise;
         end if;
         Status := Capture_Allocation_Failed;
         Budgets.Poison (From.Owner.all);
      when others =>
         if Commit_Started then
            raise;
         end if;
         Status := Capture_Internal_Failure;
         Budgets.Poison (From.Owner.all);
   end Capture;

   function Query_Ready
     (From    : File_Snapshot;
      Session : Budgets.Session_Tag;
      Status  : in out Query_Status) return Boolean
   is
   begin
      if Status /= Query_Succeeded then
         return False;
      elsif not Budgets.Matches (From.Owner.all, Session) then
         Status := Query_Session_Foreign;
         return False;
      end if;
      case Budgets.Current_State (From.Owner.all) is
         when Budgets.Active => null;
         when Budgets.Exhausted =>
            Status := Query_Budget_Exhausted;
            return False;
         when Budgets.Failed =>
            Status := Query_Budget_Failed;
            return False;
      end case;
      if From.Data.Value = null then
         Status := Query_No_Snapshot;
         return False;
      elsif not Budgets.Matches (From.Owner.all, From.Data.Value.Session) then
         Status := Query_Session_Foreign;
         return False;
      end if;
      Reserve_Query (From.Owner.all, 1, Status);
      return Status = Query_Succeeded;
   exception
      when others =>
         Budgets.Poison (From.Owner.all);
         Status := Query_Internal_Failure;
         return False;
   end Query_Ready;

   procedure Read_Path_Length
     (From    : File_Snapshot;
      Session : Budgets.Session_Tag;
      Length  : in out Interfaces.Unsigned_64;
      Status  : in out Query_Status) is
   begin
      if Query_Ready (From, Session, Status) then
         Length := Interfaces.Unsigned_64 (From.Data.Value.Path.all'Length);
      end if;
   end Read_Path_Length;

   procedure Copy_Path
     (From    : File_Snapshot;
      Session : Budgets.Session_Tag;
      Into    : in out String;
      Written : in out Interfaces.Unsigned_64;
      Status  : in out Query_Status)
   is
      Count          : Interfaces.Unsigned_64;
      Target_Last    : Natural;
      Commit_Started : Boolean := False;
   begin
      if not Query_Ready (From, Session, Status) then
         return;
      end if;
      Count := Interfaces.Unsigned_64 (From.Data.Value.Path.all'Length);
      if Interfaces.Unsigned_64 (Into'Length) < Count then
         Status := Query_Output_Too_Small;
         return;
      end if;
      if Count > 0 then
         Reserve_Query (From.Owner.all, Budgets.Charge_Amount (Count), Status);
      end if;
      if Status = Query_Succeeded then
         Target_Last := Into'First + From.Data.Value.Path.all'Length - 1;
         Commit_Started := True;
         System.Soft_Links.Abort_Defer.all;
         begin
            Into (Into'First .. Target_Last) := From.Data.Value.Path.all;
            Written := Count;
         exception
            when others =>
               System.Soft_Links.Abort_Undefer.all;
               raise;
         end;
         System.Soft_Links.Abort_Undefer.all;
      end if;
   exception
      when others =>
         if Commit_Started then
            raise;
         end if;
         Budgets.Poison (From.Owner.all);
         Status := Query_Internal_Failure;
   end Copy_Path;

   procedure Read_Byte_Length
     (From    : File_Snapshot;
      Session : Budgets.Session_Tag;
      Length  : in out Interfaces.Unsigned_64;
      Status  : in out Query_Status) is
   begin
      if Query_Ready (From, Session, Status) then
         Length := From.Data.Value.Length;
      end if;
   end Read_Byte_Length;

   procedure Copy_Bytes
     (From     : File_Snapshot;
      Session  : Budgets.Session_Tag;
      Offset   : Interfaces.Unsigned_64;
      Into     : in out Ada.Streams.Stream_Element_Array;
      Written  : in out Interfaces.Unsigned_64;
      Complete : in out Boolean;
      Status   : in out Query_Status)
   is
      Length             : Interfaces.Unsigned_64;
      Remaining          : Interfaces.Unsigned_64;
      Copy_Count         : Interfaces.Unsigned_64;
      Buffer_Length      : Interfaces.Unsigned_64;
      Negative_Count     : Interfaces.Unsigned_64;
      Nonnegative_Count  : Interfaces.Unsigned_64;
      Last_Byte          : Interfaces.Unsigned_64;
      Visits             : Interfaces.Unsigned_64;
      Target_Last        : Ada.Streams.Stream_Element_Offset;
      Commit_Started     : Boolean := False;

      procedure Stage_And_Commit is
         Current              : Byte_Block_Access;
         Block_Start          : Interfaces.Unsigned_64 := 0;
         Block_End            : Interfaces.Unsigned_64;
         Copy_First           : Interfaces.Unsigned_64;
         Copy_Last            : Interfaces.Unsigned_64;
         Filled               : Interfaces.Unsigned_64 := 0;
         Scratch_Index        : Ada.Streams.Stream_Element_Offset := 0;
         Scratch_Elaborated   : Boolean := False;
      begin
         declare
            Scratch : Ada.Streams.Stream_Element_Array
              (0 .. Ada.Streams.Stream_Element_Offset (Copy_Count - 1));
         begin
            Scratch_Elaborated := True;
            Current := From.Data.Value.First;
            while Current /= null and then Block_Start <= Last_Byte loop
               if Current.Used = 0
                 or else (Current.Next /= null and then Current.Used /= Block_Capacity)
               then
                  Status := Query_Internal_Failure;
                  Budgets.Poison (From.Owner.all);
                  return;
               end if;
               Block_End := Block_Start + Interfaces.Unsigned_64 (Current.Used) - 1;
               if Block_End >= Offset then
                  Copy_First := Interfaces.Unsigned_64'Max (Offset, Block_Start);
                  Copy_Last := Interfaces.Unsigned_64'Min (Last_Byte, Block_End);
                  for Index in Copy_First .. Copy_Last loop
                     Scratch (Scratch_Index) :=
                       Current.Data
                         (Ada.Streams.Stream_Element_Offset (Index - Block_Start) + 1);
                     Filled := Filled + 1;
                     if Filled < Copy_Count then
                        Scratch_Index := Ada.Streams.Stream_Element_Offset'Succ (Scratch_Index);
                     end if;
                  end loop;
               end if;
               Block_Start := Block_Start + Interfaces.Unsigned_64 (Current.Used);
               Current := Current.Next;
            end loop;
            if Filled /= Copy_Count then
               Status := Query_Internal_Failure;
               Budgets.Poison (From.Owner.all);
               return;
            end if;

            if Test_Hooks.Enabled then
               declare
                  Inject : Boolean;
               begin
                  Test_Hooks.Take_Snapshot_Failure
                    (Test_Hooks.Snapshot_Copy_Invariant, Inject);
                  if Inject then
                     Status := Query_Internal_Failure;
                     Budgets.Poison (From.Owner.all);
                     return;
                  end if;
               end;
            end if;

            System.Soft_Links.Abort_Defer.all;
            begin
               if Test_Hooks.Enabled then
                  declare
                     Released : Boolean;
                  begin
                     Test_Hooks.Pause (Test_Hooks.Snapshot_Copy_Precommit, Released);
                     if not Released then
                        raise Program_Error with "snapshot copy precommit hook timed out";
                     end if;
                  end;
               end if;
               Commit_Started := True;
               Into (Into'First .. Target_Last) := Scratch;
               Written := Copy_Count;
               Complete := Offset + Copy_Count = Length;
               Status := Query_Succeeded;
            exception
               when others =>
                  System.Soft_Links.Abort_Undefer.all;
                  raise;
            end;
            System.Soft_Links.Abort_Undefer.all;
         end;
      exception
         when Storage_Error =>
            if Commit_Started then
               raise;
            elsif not Scratch_Elaborated then
               Status := Query_Allocation_Failed;
            else
               Budgets.Poison (From.Owner.all);
               Status := Query_Internal_Failure;
            end if;
         when others =>
            if Commit_Started then
               raise;
            end if;
            Budgets.Poison (From.Owner.all);
            Status := Query_Internal_Failure;
      end Stage_And_Commit;
   begin
      if not Query_Ready (From, Session, Status) then
         return;
      end if;
      Length := From.Data.Value.Length;
      if Offset = Length then
         Status := Query_End_Of_Bytes;
         return;
      elsif Offset > Length then
         Status := Query_Invalid_Offset;
         return;
      elsif Into'Last < Into'First then
         Status := Query_Output_Too_Small;
         return;
      end if;
      Remaining := Length - Offset;
      if Into'First = Ada.Streams.Stream_Element_Offset'First
        and then Into'Last = Ada.Streams.Stream_Element_Offset'Last
      then
         Negative_Count :=
           Interfaces.Unsigned_64
             (-(Ada.Streams.Stream_Element_Offset'First + 1)) + 1;
         Nonnegative_Count :=
           Interfaces.Unsigned_64 (Ada.Streams.Stream_Element_Offset'Last) + 1;
         if Negative_Count > Interfaces.Unsigned_64'Last - Nonnegative_Count then
            Copy_Count := Remaining;
         else
            Buffer_Length := Negative_Count + Nonnegative_Count;
            Copy_Count := Interfaces.Unsigned_64'Min (Buffer_Length, Remaining);
         end if;
      else
         Buffer_Length := Interfaces.Unsigned_64 (Into'Length);
         Copy_Count := Interfaces.Unsigned_64'Min (Buffer_Length, Remaining);
      end if;
      if Copy_Count - 1
        > Interfaces.Unsigned_64 (Ada.Streams.Stream_Element_Offset'Last)
      then
         Status := Query_Allocation_Failed;
         return;
      end if;
      Target_Last :=
        Into'First + Ada.Streams.Stream_Element_Offset (Copy_Count - 1);
      if Target_Last > Into'Last then
         Status := Query_Internal_Failure;
         Budgets.Poison (From.Owner.all);
         return;
      end if;
      Last_Byte := Offset + Copy_Count - 1;
      Visits := 1 + Last_Byte / Block_Bytes;
      Reserve_Query (From.Owner.all, Budgets.Charge_Amount (Visits), Status);
      if Status /= Query_Succeeded then
         return;
      end if;
      Reserve_Query (From.Owner.all, Budgets.Charge_Amount (Copy_Count), Status);
      if Status /= Query_Succeeded then
         return;
      end if;
      Reserve_Query (From.Owner.all, Budgets.Charge_Amount (Copy_Count), Status);
      if Status /= Query_Succeeded then
         return;
      end if;
      if Test_Hooks.Enabled then
         declare
            Inject : Boolean;
         begin
            Test_Hooks.Take_Snapshot_Failure
              (Test_Hooks.Snapshot_Copy_Storage, Inject);
            if Inject then
               Status := Query_Allocation_Failed;
               return;
            end if;
         end;
      end if;
      Stage_And_Commit;
   exception
      when others =>
         if Commit_Started then
            raise;
         end if;
         Budgets.Poison (From.Owner.all);
         Status := Query_Internal_Failure;
   end Copy_Bytes;

   procedure Read_Digest_Length
     (From    : File_Snapshot;
      Session : Budgets.Session_Tag;
      Length  : in out Interfaces.Unsigned_64;
      Status  : in out Query_Status) is
   begin
      if Query_Ready (From, Session, Status) then
         Length := SHA_256.Hex_Digest'Length;
      end if;
   end Read_Digest_Length;

   procedure Copy_Digest
     (From    : File_Snapshot;
      Session : Budgets.Session_Tag;
      Into    : in out String;
      Written : in out Interfaces.Unsigned_64;
      Status  : in out Query_Status)
   is
      Count          : constant Interfaces.Unsigned_64 := SHA_256.Hex_Digest'Length;
      Target_Last    : Natural;
      Commit_Started : Boolean := False;
   begin
      if not Query_Ready (From, Session, Status) then
         return;
      elsif Interfaces.Unsigned_64 (Into'Length) < Count then
         Status := Query_Output_Too_Small;
         return;
      end if;
      Reserve_Query (From.Owner.all, Budgets.Charge_Amount (Count), Status);
      if Status = Query_Succeeded then
         Target_Last := Into'First + SHA_256.Hex_Digest'Length - 1;
         Commit_Started := True;
         System.Soft_Links.Abort_Defer.all;
         begin
            Into (Into'First .. Target_Last) := From.Data.Value.Digest;
            Written := Count;
         exception
            when others =>
               System.Soft_Links.Abort_Undefer.all;
               raise;
         end;
         System.Soft_Links.Abort_Undefer.all;
      end if;
   exception
      when others =>
         if Commit_Started then
            raise;
         end if;
         Budgets.Poison (From.Owner.all);
         Status := Query_Internal_Failure;
   end Copy_Digest;
end Flyology_Serde_Generator.Build_Attestations.Local_Snapshots;
