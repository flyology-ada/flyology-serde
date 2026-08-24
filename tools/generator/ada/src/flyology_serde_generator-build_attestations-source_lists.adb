with Ada.Unchecked_Deallocation;
with System.Soft_Links;

with Flyology_Serde_Generator.Build_Attestation_Test_Hooks;

package body Flyology_Serde_Generator.Build_Attestations.Source_Lists is
   use type Budgets.Budget_State;
   use type Interfaces.Unsigned_64;
   package Test_Hooks renames Flyology_Serde_Generator.Build_Attestation_Test_Hooks;

   type Path_Access is access String;
   type Path_Node is record
      Path : Path_Access;
      Next : Path_Node_Access := null;
   end record;

   procedure Free_Path is new Ada.Unchecked_Deallocation (String, Path_Access);
   procedure Free_Node is new Ada.Unchecked_Deallocation (Path_Node, Path_Node_Access);
   procedure Free_Payload is new Ada.Unchecked_Deallocation (List_Payload, List_Payload_Access);

   procedure Discard_Path (Value : in out Path_Access; Clean : out Boolean) is
      Owned : constant Boolean := Value /= null;
   begin
      Clean := True;
      Free_Path (Value);
      if Test_Hooks.Enabled and then Owned then
         Test_Hooks.Note_Source_Path_Released;
         Test_Hooks.Raise_If_Source_Failure (Test_Hooks.Source_Path_Release);
      end if;
   exception
      when others =>
         Clean := False;
   end Discard_Path;

   procedure Discard_Node (Value : in out Path_Node_Access; Clean : out Boolean) is
      Path_Clean : Boolean := True;
      Saved      : Path_Node_Access := Value;
   begin
      Clean := True;
      Value := null;
      if Saved /= null then
         Discard_Path (Saved.Path, Path_Clean);
         Clean := Path_Clean;
         Free_Node (Saved);
         if Test_Hooks.Enabled then
            Test_Hooks.Note_Source_Node_Released;
            Test_Hooks.Raise_If_Source_Failure (Test_Hooks.Source_Node_Release);
         end if;
      end if;
   exception
      when others =>
         Clean := False;
   end Discard_Node;

   procedure Discard_Chain (Value : in out Path_Node_Access; Clean : out Boolean) is
      Current : Path_Node_Access := Value;
      Next    : Path_Node_Access;
      Node_Clean : Boolean;
   begin
      Clean := True;
      Value := null;
      while Current /= null loop
         Next := Current.Next;
         Current.Next := null;
         Discard_Node (Current, Node_Clean);
         Clean := Clean and then Node_Clean;
         Current := Next;
      end loop;
   exception
      when others =>
         Clean := False;
   end Discard_Chain;

   procedure Discard_Payload (Value : in out List_Payload_Access; Clean : out Boolean) is
      Chain_Clean : Boolean;
      Saved       : List_Payload_Access := Value;
   begin
      Clean := True;
      Value := null;
      if Saved /= null then
         Discard_Chain (Saved.First, Chain_Clean);
         Clean := Chain_Clean;
         Saved.Last := null;
         Free_Payload (Saved);
         if Test_Hooks.Enabled then
            Test_Hooks.Note_Source_Payload_Released;
            Test_Hooks.Raise_If_Source_Failure (Test_Hooks.Source_Payload_Release);
         end if;
      end if;
   exception
      when others =>
         Clean := False;
   end Discard_Payload;

   overriding procedure Finalize (Value : in out List_Holder) is
      Clean : Boolean;
   begin
      Discard_Payload (Value.Value, Clean);
      if not Clean then
         Budgets.Poison (Value.Owner.all);
      end if;
   exception
      when others =>
         Budgets.Poison (Value.Owner.all);
   end Finalize;

   type Path_Candidate (Owner : not null access Budgets.Budget) is
     new Ada.Finalization.Limited_Controlled with record
      Value : Path_Access := null;
   end record;

   overriding procedure Finalize (Value : in out Path_Candidate) is
      Clean : Boolean;
   begin
      Discard_Path (Value.Value, Clean);
      if not Clean then
         Budgets.Poison (Value.Owner.all);
      end if;
   exception
      when others =>
         Budgets.Poison (Value.Owner.all);
   end Finalize;

   type Node_Candidate (Owner : not null access Budgets.Budget) is
     new Ada.Finalization.Limited_Controlled with record
      Value : Path_Node_Access := null;
   end record;

   overriding procedure Finalize (Value : in out Node_Candidate) is
      Clean : Boolean;
   begin
      Discard_Node (Value.Value, Clean);
      if not Clean then
         Budgets.Poison (Value.Owner.all);
      end if;
   exception
      when others =>
         Budgets.Poison (Value.Owner.all);
   end Finalize;

   type Chain_Candidate (Owner : not null access Budgets.Budget) is
     new Ada.Finalization.Limited_Controlled with record
      First : Path_Node_Access := null;
      Last  : Path_Node_Access := null;
      Count : Interfaces.Unsigned_64 := 0;
   end record;

   overriding procedure Finalize (Value : in out Chain_Candidate) is
      Clean : Boolean;
   begin
      Discard_Chain (Value.First, Clean);
      Value.Last := null;
      if not Clean then
         Budgets.Poison (Value.Owner.all);
      end if;
   exception
      when others =>
         Budgets.Poison (Value.Owner.all);
   end Finalize;

   type Payload_Candidate (Owner : not null access Budgets.Budget) is
     new Ada.Finalization.Limited_Controlled with record
      Value : List_Payload_Access := null;
   end record;

   overriding procedure Finalize (Value : in out Payload_Candidate) is
      Clean : Boolean;
   begin
      Discard_Payload (Value.Value, Clean);
      if not Clean then
         Budgets.Poison (Value.Owner.all);
      end if;
   exception
      when others =>
         Budgets.Poison (Value.Owner.all);
   end Finalize;

   procedure Set_Parse_Budget_Status
     (Owner  : in out Budgets.Budget;
      Status : out Parse_Status) is
   begin
      case Budgets.Current_State (Owner) is
         when Budgets.Exhausted =>
            Status := Parse_Budget_Exhausted;
         when Budgets.Failed =>
            Status := Parse_Budget_Failed;
         when Budgets.Active =>
            Status := Parse_Internal_Failure;
            Budgets.Poison (Owner);
      end case;
   end Set_Parse_Budget_Status;

   procedure Reserve_Parse
     (Owner  : in out Budgets.Budget;
      Amount : Budgets.Charge_Amount;
      Status : in out Parse_Status)
   is
      Granted : Boolean;
   begin
      Budgets.Reserve (Owner, Budgets.Work_Units, Amount, Granted);
      if not Granted then
         Set_Parse_Budget_Status (Owner, Status);
      end if;
   end Reserve_Parse;

   procedure Pause (Point : Test_Hooks.Transfer_Point) is
      Released : Boolean;
   begin
      if Test_Hooks.Enabled then
         Test_Hooks.Pause (Point, Released);
         if not Released then
            raise Program_Error with "source-list ownership test pause timed out";
         end if;
      end if;
   end Pause;

   function Less (Left : Path_Access; Right : String) return Boolean is
      Common : constant Natural := Natural'Min (Left.all'Length, Right'Length);
   begin
      for Offset in 0 .. Common - 1 loop
         if Left.all (Left.all'First + Offset) < Right (Right'First + Offset) then
            return True;
         elsif Left.all (Left.all'First + Offset) > Right (Right'First + Offset) then
            return False;
         end if;
      end loop;
      return Left.all'Length < Right'Length;
   end Less;

   function Is_Portable (Value : Character) return Boolean is
     (Value in 'A' .. 'Z'
      or else Value in 'a' .. 'z'
      or else Value in '0' .. '9'
      or else Value = '_'
      or else Value = '-'
      or else Value = '.'
      or else Value = '/');

   type Required_Flags is record
      Alire       : Boolean := False;
      Dependencies : Boolean := False;
      Project     : Boolean := False;
      Self        : Boolean := False;
   end record;

   function All_Required (Value : Required_Flags) return Boolean is
     (Value.Alire
      and then Value.Dependencies
      and then Value.Project
      and then Value.Self);

   procedure Compare_Required
     (Owner    : in out Budgets.Budget;
      Path     : String;
      Required : in out Required_Flags;
      Status   : in out Parse_Status)
   is
      procedure Compare (Name : String; Seen : in out Boolean) is
         Amount : constant Interfaces.Unsigned_64 :=
           Interfaces.Unsigned_64'Min
             (Interfaces.Unsigned_64 (Path'Length), Interfaces.Unsigned_64 (Name'Length)) + 1;
      begin
         if Seen or else Status /= Parse_Succeeded then
            return;
         end if;
         Reserve_Parse (Owner, 1, Status);
         if Status = Parse_Succeeded then
            Reserve_Parse (Owner, Budgets.Charge_Amount (Amount), Status);
         end if;
         if Status = Parse_Succeeded and then Path = Name then
            Seen := True;
         end if;
      end Compare;
   begin
      Compare ("alire.toml", Required.Alire);
      Compare ("dependency-identities-v2.json", Required.Dependencies);
      Compare ("flyology_serde_generator.gpr", Required.Project);
      Compare ("provenance-files-v2.txt", Required.Self);
   end Compare_Required;

   procedure Append
     (Path  : String;
      Chain : in out Chain_Candidate)
   is
      Path_Value : Path_Candidate (Chain.Owner);
      Node_Value : Node_Candidate (Chain.Owner);
   begin
      System.Soft_Links.Abort_Defer.all;
      begin
         if Test_Hooks.Enabled then
            Test_Hooks.Raise_If_Source_Failure (Test_Hooks.Source_Path_Storage);
         end if;
         Path_Value.Value := new String'(Path);
         if Test_Hooks.Enabled then
            Test_Hooks.Note_Source_Path_Allocated;
            Pause (Test_Hooks.Source_Path_Allocation);
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
            Test_Hooks.Raise_If_Source_Failure (Test_Hooks.Source_Node_Storage);
         end if;
         Node_Value.Value := new Path_Node'(Path => null, Next => null);
         if Test_Hooks.Enabled then
            Test_Hooks.Note_Source_Node_Allocated;
            Pause (Test_Hooks.Source_Node_Allocation);
         end if;
      exception
         when others =>
            System.Soft_Links.Abort_Undefer.all;
            raise;
      end;
      System.Soft_Links.Abort_Undefer.all;

      System.Soft_Links.Abort_Defer.all;
      begin
         Pause (Test_Hooks.Source_Node_Publication);
         Node_Value.Value.Path := Path_Value.Value;
         Path_Value.Value := null;
         if Chain.Last = null then
            Chain.First := Node_Value.Value;
         else
            Chain.Last.Next := Node_Value.Value;
         end if;
         Chain.Last := Node_Value.Value;
         Chain.Count := Chain.Count + 1;
         Node_Value.Value := null;
      exception
         when others =>
            System.Soft_Links.Abort_Undefer.all;
            raise;
      end;
      System.Soft_Links.Abort_Undefer.all;
   end Append;

   procedure Parse
     (Bytes                      : String;
      Session                    : Budgets.Session_Tag;
      Maximum_Manifest_Bytes_Per_File : Limit_Value;
      Maximum_Path_Bytes         : Limit_Value;
      Maximum_Source_Files       : Limit_Value;
      Into                       : in out Parsed_List;
      Status                     : in out Parse_Status)
   is
      Chain          : Chain_Candidate (Into.Owner);
      Candidate      : Payload_Candidate (Into.Owner);
      Required       : Required_Flags;
      Path_Length    : Natural := 0;
      Component_Size : Natural := 0;
      Component_Dots : Boolean := True;
      Last_Was_LF    : Boolean := False;
   begin
      if Status /= Parse_Succeeded then
         return;
      elsif not Budgets.Matches (Into.Owner.all, Session) then
         Status := Parse_Session_Foreign;
         return;
      end if;
      case Budgets.Current_State (Into.Owner.all) is
         when Budgets.Active =>
            null;
         when Budgets.Exhausted =>
            Status := Parse_Budget_Exhausted;
            return;
         when Budgets.Failed =>
            Status := Parse_Budget_Failed;
            return;
      end case;
      if Into.Data.Value /= null then
         Status :=
           (if Budgets.Matches (Into.Owner.all, Into.Data.Value.Session)
            then Parse_Owner_Not_Empty
            else Parse_Session_Foreign);
         return;
      elsif Interfaces.Unsigned_64 (Bytes'Length) > Maximum_Manifest_Bytes_Per_File then
         Status := Parse_Limit_Exceeded;
         return;
      end if;

      for Index in Bytes'Range loop
         Reserve_Parse (Into.Owner.all, 1, Status);
         exit when Status /= Parse_Succeeded;
         if Bytes (Index) = Character'Val (10) then
            if Path_Length = 0
              or else Component_Size = 0
              or else (Component_Dots and then Component_Size <= 2)
            then
               Status := Parse_Malformed;
               exit;
            elsif Chain.Count >= Maximum_Source_Files then
               Status := Parse_Limit_Exceeded;
               exit;
            end if;
            declare
               Path : String renames Bytes (Index - Path_Length .. Index - 1);
               Compared : Interfaces.Unsigned_64;
            begin
               if Chain.Last /= null then
                  Reserve_Parse (Into.Owner.all, 1, Status);
                  if Status = Parse_Succeeded then
                     Compared :=
                       Interfaces.Unsigned_64'Min
                         (Interfaces.Unsigned_64 (Chain.Last.Path.all'Length),
                          Interfaces.Unsigned_64 (Path'Length)) + 1;
                     Reserve_Parse (Into.Owner.all, Budgets.Charge_Amount (Compared), Status);
                  end if;
                  if Status = Parse_Succeeded and then not Less (Chain.Last.Path, Path) then
                     Status := Parse_Malformed;
                  end if;
               end if;
               Compare_Required (Into.Owner.all, Path, Required, Status);
               if Status = Parse_Succeeded then
                  Append (Path, Chain);
               end if;
            end;
            exit when Status /= Parse_Succeeded;
            Path_Length := 0;
            Component_Size := 0;
            Component_Dots := True;
            Last_Was_LF := True;
         else
            Last_Was_LF := False;
            if Path_Length = Natural'Last then
               Status := Parse_Limit_Exceeded;
               exit;
            end if;
            Path_Length := Path_Length + 1;
            if Interfaces.Unsigned_64 (Path_Length) > Maximum_Path_Bytes then
               Status := Parse_Limit_Exceeded;
               exit;
            elsif not Is_Portable (Bytes (Index)) then
               Status := Parse_Malformed;
               exit;
            elsif Bytes (Index) = '/' then
               if Component_Size = 0 or else (Component_Dots and then Component_Size <= 2) then
                  Status := Parse_Malformed;
                  exit;
               end if;
               Component_Size := 0;
               Component_Dots := True;
            else
               Component_Size := Component_Size + 1;
               Component_Dots := Component_Dots and then Bytes (Index) = '.';
            end if;
         end if;
      end loop;

      if Status = Parse_Succeeded and then (not Last_Was_LF or else not All_Required (Required)) then
         Status := Parse_Malformed;
      end if;
      if Status /= Parse_Succeeded then
         return;
      end if;

      if Test_Hooks.Enabled then
         Test_Hooks.Raise_If_Source_Failure (Test_Hooks.Source_Internal);
      end if;

      System.Soft_Links.Abort_Defer.all;
      begin
         if Test_Hooks.Enabled then
            Test_Hooks.Raise_If_Source_Failure (Test_Hooks.Source_Payload_Storage);
         end if;
         Candidate.Value :=
           new List_Payload'
             (Session  => Session,
              First    => null,
              Last     => null,
              Count    => 0,
              Visiting => False);
         if Test_Hooks.Enabled then
            Test_Hooks.Note_Source_Payload_Allocated;
            Pause (Test_Hooks.Source_Payload_Allocation);
         end if;
      exception
         when others =>
            System.Soft_Links.Abort_Undefer.all;
            raise;
      end;
      System.Soft_Links.Abort_Undefer.all;

      System.Soft_Links.Abort_Defer.all;
      begin
         Pause (Test_Hooks.Source_Payload_Publication);
         Candidate.Value.First := Chain.First;
         Candidate.Value.Last := Chain.Last;
         Candidate.Value.Count := Chain.Count;
         Chain.First := null;
         Chain.Last := null;
         Chain.Count := 0;
      exception
         when others =>
            System.Soft_Links.Abort_Undefer.all;
            raise;
      end;
      System.Soft_Links.Abort_Undefer.all;

      System.Soft_Links.Abort_Defer.all;
      begin
         Pause (Test_Hooks.Source_Owner_Publication);
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
         Status := Parse_Allocation_Failed;
         Budgets.Poison (Into.Owner.all);
      when others =>
         Status := Parse_Internal_Failure;
         Budgets.Poison (Into.Owner.all);
   end Parse;

   type Visit_Guard (Owner : not null access Budgets.Budget) is
     new Ada.Finalization.Limited_Controlled with record
      Value : List_Payload_Access := null;
   end record;

   overriding procedure Finalize (Value : in out Visit_Guard) is
   begin
      if Value.Value /= null then
         Value.Value.Visiting := False;
         if Test_Hooks.Enabled then
            Test_Hooks.Raise_If_Source_Failure (Test_Hooks.Source_Visit_Release);
         end if;
      end if;
   exception
      when others =>
         Budgets.Poison (Value.Owner.all);
   end Finalize;

   procedure Set_Visit_State
     (Owner  : Budgets.Budget;
      Status : out Visit_Status) is
   begin
      case Budgets.Current_State (Owner) is
         when Budgets.Exhausted =>
            Status := Visit_Budget_Exhausted;
         when Budgets.Failed =>
            Status := Visit_Budget_Failed;
         when Budgets.Active =>
            Status := Visit_Succeeded;
      end case;
   end Set_Visit_State;

   procedure Visit
     (From    : in out Parsed_List;
      Session : Budgets.Session_Tag;
      Process : not null access procedure
        (Session : Budgets.Session_Tag;
         Path    : String;
         Action  : out Visit_Action);
      Status  : in out Visit_Status)
   is
      Guard   : Visit_Guard (From.Owner);
      pragma Unreferenced (Guard);
      Current : Path_Node_Access;
      Action  : Visit_Action;
      Granted : Boolean;
   begin
      if Status /= Visit_Succeeded then
         return;
      elsif not Budgets.Matches (From.Owner.all, Session) then
         Status := Visit_Session_Foreign;
         return;
      end if;
      Set_Visit_State (From.Owner.all, Status);
      if Status /= Visit_Succeeded then
         return;
      elsif From.Data.Value = null then
         Status := Visit_No_List;
         return;
      elsif not Budgets.Matches (From.Owner.all, From.Data.Value.Session) then
         Status := Visit_Session_Foreign;
         return;
      elsif From.Data.Value.Visiting then
         Status := Visit_Reentrant;
         return;
      end if;

      Current := From.Data.Value.First;
      while Current /= null loop
         Budgets.Reserve (From.Owner.all, Budgets.Work_Units, 1, Granted);
         if Granted then
            Budgets.Reserve
              (From.Owner.all, Budgets.Work_Units,
               Budgets.Charge_Amount (Current.Path.all'Length), Granted);
         end if;
         if not Granted then
            Set_Visit_State (From.Owner.all, Status);
            if Status = Visit_Succeeded then
               Status := Visit_Internal_Failure;
               Budgets.Poison (From.Owner.all);
            end if;
            return;
         end if;

         System.Soft_Links.Abort_Defer.all;
         begin
            Pause (Test_Hooks.Source_Visit_Latch);
            Guard.Value := From.Data.Value;
            From.Data.Value.Visiting := True;
         exception
            when others =>
               System.Soft_Links.Abort_Undefer.all;
               raise;
         end;
         System.Soft_Links.Abort_Undefer.all;

         Process (Session, Current.Path.all, Action);

         System.Soft_Links.Abort_Defer.all;
         begin
            From.Data.Value.Visiting := False;
            Guard.Value := null;
         exception
            when others =>
               System.Soft_Links.Abort_Undefer.all;
               raise;
         end;
         System.Soft_Links.Abort_Undefer.all;

         if not Budgets.Matches (From.Owner.all, From.Data.Value.Session) then
            Status := Visit_Session_Foreign;
            return;
         end if;
         Set_Visit_State (From.Owner.all, Status);
         if Status /= Visit_Succeeded then
            return;
         elsif Action = Stop then
            Status := Visit_Stopped;
            return;
         end if;
         Current := Current.Next;
      end loop;
   exception
      when others =>
         if From.Data.Value /= null
           and then not Budgets.Matches (From.Owner.all, From.Data.Value.Session)
         then
            Status := Visit_Session_Foreign;
         else
            Set_Visit_State (From.Owner.all, Status);
            if Status = Visit_Succeeded then
               Status := Visit_Internal_Failure;
               Budgets.Poison (From.Owner.all);
            end if;
         end if;
   end Visit;
end Flyology_Serde_Generator.Build_Attestations.Source_Lists;
