with Ada.Strings.Unbounded;
with Ada.Unchecked_Deallocation;
with Flyology_Serde_Generator.Build_Attestation_Test_Hooks;
with System.Soft_Links;

package body Flyology_Serde_Generator.Build_Attestations is
   package US renames Ada.Strings.Unbounded;
   package Test_Hooks renames Flyology_Serde_Generator.Build_Attestation_Test_Hooks;

   use type Budgets.Budget_State;
   use type Interfaces.Unsigned_64;
   use type US.Unbounded_String;

   type Dependency_Node;
   type Dependency_Node_Access is access Dependency_Node;
   type Dependency_Node is record
      Crate  : US.Unbounded_String;
      Prefix : US.Unbounded_String;
      Next   : Dependency_Node_Access := null;
   end record;

   type Request_Payload is record
      Session           : Budgets.Session_Tag;
      Limits            : Attestation_Limits;
      Generator_Root    : US.Unbounded_String;
      Git_Executable    : US.Unbounded_String;
      Toolchain_Root    : US.Unbounded_String;
      Staging_Parent    : US.Unbounded_String;
      Active_Lock       : US.Unbounded_String;
      Dependencies      : Dependency_Node_Access := null;
      Last_Dependency   : Dependency_Node_Access := null;
      Dependency_Count  : Interfaces.Unsigned_64 := 0;
      Sealed            : Boolean := False;
   end record;

   type Stage_Payload is record
      Session  : Budgets.Session_Tag;
      Identity : SHA_256.Hex_Digest;
   end record;

   procedure Raw_Free_Node is new Ada.Unchecked_Deallocation
     (Object => Dependency_Node, Name => Dependency_Node_Access);
   procedure Raw_Free_Request is new Ada.Unchecked_Deallocation
     (Object => Request_Payload, Name => Request_Payload_Access);
   procedure Raw_Free_Stage is new Ada.Unchecked_Deallocation
     (Object => Stage_Payload, Name => Stage_Payload_Access);

   procedure Poison_If_Active (Value : in out Budgets.Budget) is
   begin
      if Budgets.Current_State (Value) = Budgets.Active then
         Budgets.Poison (Value);
      end if;
   exception
      when others =>
         null;
   end Poison_If_Active;

   procedure Discard_Node
     (Value : in out Dependency_Node_Access;
      Clean : out Boolean)
   is
      Was_Owned : constant Boolean := Value /= null;
   begin
      Clean := True;
      Raw_Free_Node (Value);
      if Test_Hooks.Enabled and then Was_Owned then
         Test_Hooks.Note_Dependency_Released;
      end if;
   exception
      when others =>
         Value := null;
         Clean := False;
   end Discard_Node;

   procedure Discard_Request
     (Value : in out Request_Payload_Access;
      Clean : out Boolean)
   is
      Node       : Dependency_Node_Access;
      Next       : Dependency_Node_Access;
      Node_Clean : Boolean;
      Was_Owned  : constant Boolean := Value /= null;
   begin
      Clean := True;
      if Value = null then
         return;
      end if;

      Node := Value.Dependencies;
      Value.Dependencies := null;
      Value.Last_Dependency := null;
      while Node /= null loop
         Next := Node.Next;
         Node.Next := null;
         Discard_Node (Node, Node_Clean);
         Clean := Clean and Node_Clean;
         Node := Next;
      end loop;
      Raw_Free_Request (Value);
      if Test_Hooks.Enabled and then Was_Owned then
         Test_Hooks.Note_Request_Released;
         Test_Hooks.Raise_If_Request_Release_Failure;
      end if;
   exception
      when others =>
         Value := null;
         Clean := False;
   end Discard_Request;

   procedure Discard_Stage
     (Value : in out Stage_Payload_Access;
      Clean : out Boolean)
   is
   begin
      Clean := True;
      Raw_Free_Stage (Value);
   exception
      when others =>
         Value := null;
         Clean := False;
   end Discard_Stage;

   overriding procedure Finalize (Value : in out Request_Holder) is
      Clean : Boolean;
   begin
      Discard_Request (Value.Value, Clean);
      if not Clean then
         Poison_If_Active (Value.Owner.all);
      end if;
   exception
      when others =>
         Value.Value := null;
         Poison_If_Active (Value.Owner.all);
   end Finalize;

   overriding procedure Finalize (Value : in out Stage_Holder) is
      Clean : Boolean;
   begin
      Discard_Stage (Value.Value, Clean);
      if not Clean then
         Poison_If_Active (Value.Owner.all);
      end if;
   exception
      when others =>
         Value.Value := null;
         Poison_If_Active (Value.Owner.all);
   end Finalize;

   type Request_Candidate (Owner : not null access Budgets.Budget) is
     new Ada.Finalization.Limited_Controlled with record
      Value : Request_Payload_Access := null;
   end record;

   overriding procedure Finalize (Value : in out Request_Candidate) is
      Clean : Boolean;
   begin
      Discard_Request (Value.Value, Clean);
      if not Clean then
         Poison_If_Active (Value.Owner.all);
      end if;
   exception
      when others =>
         Value.Value := null;
         Poison_If_Active (Value.Owner.all);
   end Finalize;

   type Node_Candidate (Owner : not null access Budgets.Budget) is
     new Ada.Finalization.Limited_Controlled with record
      Value : Dependency_Node_Access := null;
   end record;

   overriding procedure Finalize (Value : in out Node_Candidate) is
      Clean : Boolean;
   begin
      Discard_Node (Value.Value, Clean);
      if not Clean then
         Poison_If_Active (Value.Owner.all);
      end if;
   exception
      when others =>
         Value.Value := null;
         Poison_If_Active (Value.Owner.all);
   end Finalize;

   procedure Reserve_Request
     (Owner   : in out Budgets.Budget;
      Amount  : Budgets.Charge_Amount;
      Status  : in out Request_Status)
   is
      Granted : Boolean;
   begin
      Budgets.Reserve (Owner, Budgets.Work_Units, Amount, Granted);
      if not Granted then
         case Budgets.Current_State (Owner) is
            when Budgets.Exhausted =>
               Status := Request_Budget_Exhausted;
            when Budgets.Failed =>
               Status := Request_Budget_Failed;
            when Budgets.Active =>
               Status := Request_Internal_Failure;
               Budgets.Poison (Owner);
         end case;
      end if;
   exception
      when others =>
         Status := Request_Internal_Failure;
         Poison_If_Active (Owner);
   end Reserve_Request;

   function Request_Is_Active
     (Owner   : aliased in out Budgets.Budget;
      Session : Budgets.Session_Tag;
      Status  : in out Request_Status) return Boolean
   is
   begin
      if Status /= Request_Succeeded then
         return False;
      end if;
      if not Budgets.Matches (Owner, Session) then
         Status := Request_Session_Foreign;
         return False;
      end if;
      case Budgets.Current_State (Owner) is
         when Budgets.Active =>
            return True;
         when Budgets.Exhausted =>
            Status := Request_Budget_Exhausted;
         when Budgets.Failed =>
            Status := Request_Budget_Failed;
      end case;
      return False;
   exception
      when others =>
         Status := Request_Internal_Failure;
         Poison_If_Active (Owner);
         return False;
   end Request_Is_Active;

   function Is_Dot_Component (Value : String; First, Last : Positive) return Boolean is
   begin
      return
        (First = Last and then Value (First) = '.')
        or else
        (Last - First = 1 and then Value (First) = '.' and then Value (Last) = '.');
   end Is_Dot_Component;

   function Is_Normal_Absolute_Path (Value : String) return Boolean is
      Component_First : Positive;
   begin
      if Value'Length = 0 or else Value (Value'First) /= '/' then
         return False;
      end if;
      if Value'Length = 1 then
         return True;
      end if;

      Component_First := Value'First + 1;
      for Index in Component_First .. Value'Last loop
         if Value (Index) = Character'Val (0) then
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

   function Is_Canonical_Crate (Value : String) return Boolean is
   begin
      if Value'Length = 0 or else Value (Value'First) not in 'a' .. 'z' then
         return False;
      end if;
      if Value'Length = 1 then
         return True;
      end if;
      for Index in Value'First + 1 .. Value'Last loop
         if Value (Index) not in 'a' .. 'z'
           and then Value (Index) not in '0' .. '9'
           and then Value (Index) /= '_'
         then
            return False;
         end if;
      end loop;
      return True;
   end Is_Canonical_Crate;

   function Is_Strict_Child (Child, Root : String) return Boolean is
   begin
      if Root = "/" then
         return Child'Length > 1 and then Child (Child'First) = '/';
      end if;
      if Child'Length <= Root'Length then
         return False;
      end if;
      for Offset in 0 .. Root'Length - 1 loop
         if Child (Child'First + Offset) /= Root (Root'First + Offset) then
            return False;
         end if;
      end loop;
      return Child (Child'First + Root'Length) = '/';
   end Is_Strict_Child;

   procedure Observe_Text
     (Owner       : in out Budgets.Budget;
      Value       : String;
      Maximum     : Limit_Value;
      Is_Valid    : not null access function (Item : String) return Boolean;
      Status      : in out Request_Status)
   is
      Length : constant Interfaces.Unsigned_64 := Interfaces.Unsigned_64 (Value'Length);
   begin
      Reserve_Request (Owner, 1, Status);
      if Status /= Request_Succeeded then
         return;
      end if;
      if Value'Length = 0 then
         Status := Request_Invalid;
         return;
      elsif Length > Maximum then
         Status := Request_Limit_Exceeded;
         return;
      end if;
      Reserve_Request (Owner, Budgets.Charge_Amount (Length), Status);
      if Status = Request_Succeeded and then not Is_Valid (Value) then
         Status := Request_Invalid;
      end if;
   end Observe_Text;

   procedure Initialize
     (Into             : in out Request;
      Session          : Budgets.Session_Tag;
      Limits           : Attestation_Limits;
      Generator_Root   : String;
      Git_Executable   : String;
      Toolchain_Root   : String;
      Staging_Parent   : String;
      Active_Lock      : String;
      Status           : in out Request_Status)
   is
      Candidate : Request_Candidate (Into.Owner);
   begin
      if not Request_Is_Active (Into.Owner.all, Session, Status) then
         return;
      end if;
      if Into.Data.Value /= null then
         Status :=
           (if Budgets.Matches (Into.Owner.all, Into.Data.Value.Session)
            then Request_Invalid
            else Request_Session_Foreign);
         return;
      end if;

      Observe_Text
        (Into.Owner.all, Generator_Root, Limits.Maximum_Path_Bytes,
         Is_Normal_Absolute_Path'Access, Status);
      if Status /= Request_Succeeded then
         return;
      end if;
      Observe_Text
        (Into.Owner.all, Git_Executable, Limits.Maximum_Path_Bytes,
         Is_Normal_Absolute_Path'Access, Status);
      if Status /= Request_Succeeded then
         return;
      end if;
      Observe_Text
        (Into.Owner.all, Toolchain_Root, Limits.Maximum_Path_Bytes,
         Is_Normal_Absolute_Path'Access, Status);
      if Status /= Request_Succeeded then
         return;
      end if;
      Observe_Text
        (Into.Owner.all, Staging_Parent, Limits.Maximum_Path_Bytes,
         Is_Normal_Absolute_Path'Access, Status);
      if Status /= Request_Succeeded then
         return;
      end if;
      Observe_Text
        (Into.Owner.all, Active_Lock, Limits.Maximum_Path_Bytes,
         Is_Normal_Absolute_Path'Access, Status);
      if Status /= Request_Succeeded then
         return;
      end if;
      if not Is_Strict_Child (Git_Executable, Toolchain_Root) then
         Status := Request_Invalid;
         return;
      end if;

      System.Soft_Links.Abort_Defer.all;
      begin
         if Test_Hooks.Enabled then
            Test_Hooks.Raise_If_Request_Storage_Failure;
            Test_Hooks.Raise_If_Request_Internal_Failure;
         end if;
         Candidate.Value :=
           new Request_Payload'
             (Session          => Session,
              Limits           => Limits,
              Generator_Root   => US.To_Unbounded_String (Generator_Root),
              Git_Executable   => US.To_Unbounded_String (Git_Executable),
              Toolchain_Root   => US.To_Unbounded_String (Toolchain_Root),
              Staging_Parent   => US.To_Unbounded_String (Staging_Parent),
              Active_Lock      => US.To_Unbounded_String (Active_Lock),
              Dependencies     => null,
              Last_Dependency  => null,
              Dependency_Count => 0,
              Sealed           => False);
         if Test_Hooks.Enabled then
            declare
               Released : Boolean;
            begin
               Test_Hooks.Note_Request_Allocated;
               Test_Hooks.Pause (Test_Hooks.Request_Allocation, Released);
               if not Released then
                  raise Program_Error with "attestation request-allocation test pause timed out";
               end if;
            end;
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
               Test_Hooks.Pause (Test_Hooks.Request_Publication, Released);
               if not Released then
                  raise Program_Error with "attestation request-publication test pause timed out";
               end if;
            end;
         end if;
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
         Status := Request_Allocation_Failed;
         Poison_If_Active (Into.Owner.all);
      when others =>
         Status := Request_Internal_Failure;
         Poison_If_Active (Into.Owner.all);
   end Initialize;

   procedure Add_Dependency
     (Into          : in out Request;
      Session       : Budgets.Session_Tag;
      Crate         : String;
      Active_Prefix : String;
      Status        : in out Request_Status)
   is
      Candidate : Node_Candidate (Into.Owner);
      Current   : Dependency_Node_Access;
      Compared  : Interfaces.Unsigned_64;
   begin
      if not Request_Is_Active (Into.Owner.all, Session, Status) then
         return;
      end if;
      if Into.Data.Value = null then
         Status := Request_Invalid;
         return;
      elsif not Budgets.Matches (Into.Owner.all, Into.Data.Value.Session) then
         Status := Request_Session_Foreign;
         return;
      elsif Into.Data.Value.Sealed then
         Status := Request_Invalid;
         return;
      elsif Into.Data.Value.Dependency_Count >= Into.Data.Value.Limits.Maximum_Dependencies then
         Status := Request_Limit_Exceeded;
         return;
      end if;

      Observe_Text
        (Into.Owner.all, Crate, Into.Data.Value.Limits.Maximum_Dependency_Name_Bytes,
         Is_Canonical_Crate'Access, Status);
      if Status /= Request_Succeeded then
         return;
      end if;
      Observe_Text
        (Into.Owner.all, Active_Prefix, Into.Data.Value.Limits.Maximum_Path_Bytes,
         Is_Normal_Absolute_Path'Access, Status);
      if Status /= Request_Succeeded then
         return;
      end if;

      Current := Into.Data.Value.Dependencies;
      while Current /= null loop
         Reserve_Request (Into.Owner.all, 1, Status);
         exit when Status /= Request_Succeeded;
         Compared :=
           Interfaces.Unsigned_64'Min
             (Interfaces.Unsigned_64 (US.Length (Current.Crate)),
              Interfaces.Unsigned_64 (Crate'Length)) + 1;
         Reserve_Request (Into.Owner.all, Budgets.Charge_Amount (Compared), Status);
         exit when Status /= Request_Succeeded;
         if Current.Crate = Crate then
            Status := Request_Invalid;
            return;
         end if;
         Current := Current.Next;
      end loop;
      if Status /= Request_Succeeded then
         return;
      end if;

      System.Soft_Links.Abort_Defer.all;
      begin
         if Test_Hooks.Enabled then
            Test_Hooks.Raise_If_Dependency_Storage_Failure;
            Test_Hooks.Raise_If_Dependency_Internal_Failure;
         end if;
         Candidate.Value :=
           new Dependency_Node'
             (Crate  => US.To_Unbounded_String (Crate),
              Prefix => US.To_Unbounded_String (Active_Prefix),
              Next   => null);
         if Test_Hooks.Enabled then
            declare
               Released : Boolean;
            begin
               Test_Hooks.Note_Dependency_Allocated;
               Test_Hooks.Pause (Test_Hooks.Dependency_Allocation, Released);
               if not Released then
                  raise Program_Error with "attestation dependency-allocation test pause timed out";
               end if;
            end;
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
               Test_Hooks.Pause (Test_Hooks.Dependency_Publication, Released);
               if not Released then
                  raise Program_Error with "attestation dependency-publication test pause timed out";
               end if;
            end;
         end if;
         if Into.Data.Value.Last_Dependency = null then
            Into.Data.Value.Dependencies := Candidate.Value;
         else
            Into.Data.Value.Last_Dependency.Next := Candidate.Value;
         end if;
         Into.Data.Value.Last_Dependency := Candidate.Value;
         Into.Data.Value.Dependency_Count := Into.Data.Value.Dependency_Count + 1;
         Candidate.Value := null;
      exception
         when others =>
            System.Soft_Links.Abort_Undefer.all;
            raise;
      end;
      System.Soft_Links.Abort_Undefer.all;
   exception
      when Storage_Error =>
         Status := Request_Allocation_Failed;
         Poison_If_Active (Into.Owner.all);
      when others =>
         Status := Request_Internal_Failure;
         Poison_If_Active (Into.Owner.all);
   end Add_Dependency;

   procedure Seal
     (Into    : in out Request;
      Session : Budgets.Session_Tag;
      Status  : in out Request_Status) is
   begin
      if not Request_Is_Active (Into.Owner.all, Session, Status) then
         return;
      end if;
      if Into.Data.Value = null then
         Status := Request_Invalid;
         return;
      elsif not Budgets.Matches (Into.Owner.all, Into.Data.Value.Session) then
         Status := Request_Session_Foreign;
         return;
      elsif Into.Data.Value.Sealed then
         Status := Request_Invalid;
         return;
      end if;
      Reserve_Request (Into.Owner.all, 1, Status);
      if Status = Request_Succeeded then
         Into.Data.Value.Sealed := True;
      end if;
   exception
      when others =>
         Status := Request_Internal_Failure;
         Poison_If_Active (Into.Owner.all);
   end Seal;

   procedure Create_Checked_Stage
     (From    : Request;
      Session : Budgets.Session_Tag;
      Into    : in out Checked_Stage;
      Status  : in out Stage_Status) is
   begin
      if Status /= Stage_Succeeded then
         return;
      end if;
      if From.Owner /= Into.Owner
        or else not Budgets.Matches (From.Owner.all, Session)
        or else not Budgets.Matches (Into.Owner.all, Session)
      then
         Status := Stage_Session_Foreign;
         return;
      end if;
      case Budgets.Current_State (From.Owner.all) is
         when Budgets.Active =>
            null;
         when Budgets.Exhausted =>
            Status := Stage_Budget_Exhausted;
            return;
         when Budgets.Failed =>
            Status := Stage_Budget_Failed;
            return;
      end case;
      if From.Data.Value = null then
         Status := Stage_Invalid_Request;
         return;
      elsif not Budgets.Matches (From.Owner.all, From.Data.Value.Session) then
         Status := Stage_Session_Foreign;
         return;
      elsif Into.Data.Value /= null
        and then not Budgets.Matches (Into.Owner.all, Into.Data.Value.Session)
      then
         Status := Stage_Session_Foreign;
         return;
      elsif not From.Data.Value.Sealed then
         Status := Stage_Invalid_Request;
         return;
      end if;
      Status := Stage_Attestation_Unavailable;
   exception
      when others =>
         Status := Stage_Internal_Failure;
         Poison_If_Active (From.Owner.all);
   end Create_Checked_Stage;

   procedure Read_Generator_Identity
     (From     : Checked_Stage;
      Session  : Budgets.Session_Tag;
      Into     : in out SHA_256.Hex_Digest;
      Status   : in out Query_Status)
   is
      Granted : Boolean;
   begin
      if Status /= Query_Succeeded then
         return;
      end if;
      if not Budgets.Matches (From.Owner.all, Session) then
         Status := Query_Session_Foreign;
         return;
      end if;
      case Budgets.Current_State (From.Owner.all) is
         when Budgets.Active =>
            null;
         when Budgets.Exhausted =>
            Status := Query_Budget_Exhausted;
            return;
         when Budgets.Failed =>
            Status := Query_Budget_Failed;
            return;
      end case;
      if From.Data.Value = null then
         Status := Query_No_Stage;
         return;
      elsif not Budgets.Matches (From.Owner.all, From.Data.Value.Session) then
         Status := Query_Session_Foreign;
         return;
      end if;

      Budgets.Reserve (From.Owner.all, Budgets.Work_Units, 1, Granted);
      if Granted then
         Budgets.Reserve (From.Owner.all, Budgets.Work_Units, 64, Granted);
      end if;
      if not Granted then
         case Budgets.Current_State (From.Owner.all) is
            when Budgets.Exhausted =>
               Status := Query_Budget_Exhausted;
            when Budgets.Failed =>
               Status := Query_Budget_Failed;
            when Budgets.Active =>
               Status := Query_Internal_Failure;
               Budgets.Poison (From.Owner.all);
         end case;
         return;
      end if;
      Into := From.Data.Value.Identity;
   exception
      when others =>
         Status := Query_Internal_Failure;
         Poison_If_Active (From.Owner.all);
   end Read_Generator_Identity;

   procedure Publish_For_Build
     (Into           : in out Checked_Stage;
      Session        : Budgets.Session_Tag;
      Published_Path : String;
      Status         : in out Publish_Status)
   is
      pragma Unreferenced (Published_Path);
   begin
      if Status /= Publish_Succeeded then
         return;
      end if;
      if not Budgets.Matches (Into.Owner.all, Session) then
         Status := Publish_Session_Foreign;
         return;
      end if;
      case Budgets.Current_State (Into.Owner.all) is
         when Budgets.Active =>
            null;
         when Budgets.Exhausted =>
            Status := Publish_Budget_Exhausted;
            return;
         when Budgets.Failed =>
            Status := Publish_Budget_Failed;
            return;
      end case;
      if Into.Data.Value = null then
         Status := Publish_No_Stage;
      elsif not Budgets.Matches (Into.Owner.all, Into.Data.Value.Session) then
         Status := Publish_Session_Foreign;
      else
         Status := Publish_Internal_Failure;
         Budgets.Poison (Into.Owner.all);
      end if;
   exception
      when others =>
         Status := Publish_Internal_Failure;
         Poison_If_Active (Into.Owner.all);
   end Publish_For_Build;
end Flyology_Serde_Generator.Build_Attestations;
