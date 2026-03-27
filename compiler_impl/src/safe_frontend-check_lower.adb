with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Strings.Fixed;
with Ada.Strings.Hash;
with Safe_Frontend.Builtin_Types;
with Safe_Frontend.Types;

package body Safe_Frontend.Check_Lower is
   package BT renames Safe_Frontend.Builtin_Types;
   package FT renames Safe_Frontend.Types;

   INT64_LOW  : constant Long_Long_Integer := -(2 ** 63);
   INT64_HIGH : constant Long_Long_Integer := (2 ** 63) - 1;

   use type Ada.Containers.Count_Type;
   use type CM.Discrete_Range_Kind;
   use type CM.Expr_Access;
   use type CM.Expr_Kind;
   use type CM.Select_Arm_Kind;
   use type CM.Unit_Kind;
   use type GM.Select_Arm_Kind;
   use type CM.Statement_Kind;
   use type GM.Terminator_Kind;
   use type FT.UString;

   package Type_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => GM.Type_Descriptor,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=",
      "="             => GM."=");

   package Index_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Positive,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   type Builder is record
      Blocks     : GM.Block_Vectors.Vector;
      Block_Map  : Index_Maps.Map;
      Locals     : GM.Local_Vectors.Vector;
      Scopes     : GM.Scope_Vectors.Vector;
      Scope_Map  : Index_Maps.Map;
      Next_Block : Natural := 0;
   end record;

   function UString_Value (Value : FT.UString) return String is
   begin
      return FT.To_String (Value);
   end UString_Value;

   function Trimmed (Value : Natural) return String is
   begin
      return Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both);
   end Trimmed;

   function Trimmed (Value : Long_Long_Integer) return String is
   begin
      return Ada.Strings.Fixed.Trim (Long_Long_Integer'Image (Value), Ada.Strings.Both);
   end Trimmed;

   function Has_Text (Value : FT.UString) return Boolean is
   begin
      return UString_Value (Value) /= "";
   end Has_Text;

   function Has_Block (Value : FT.UString) return Boolean is
   begin
      return Has_Text (Value);
   end Has_Block;

   function Empty_Block_Id return FT.UString is
   begin
      return FT.To_UString ("");
   end Empty_Block_Id;

   procedure Add_Builtins (Type_Env : in out Type_Maps.Map) is
   begin
      Type_Env.Include ("integer", BT.Integer_Type);
      Type_Env.Include ("boolean", BT.Boolean_Type);
      Type_Env.Include ("character", BT.Character_Type);
      Type_Env.Include ("string", BT.String_Type);
      Type_Env.Include ("result", BT.Result_Type);
      Type_Env.Include ("float", BT.Float_Type);
      Type_Env.Include ("long_float", BT.Long_Float_Type);
      Type_Env.Include ("duration", BT.Duration_Type);
   end Add_Builtins;

   function Resolve_Type
     (Name     : String;
      Type_Env : Type_Maps.Map) return GM.Type_Descriptor is
   begin
      if Name = "" then
         return BT.Integer_Type;
      elsif Type_Env.Contains (Name) then
         return Type_Env.Element (Name);
      end if;
      return BT.Integer_Type;
   end Resolve_Type;

   function Resolve_Type
     (Name      : String;
      Var_Types : Type_Maps.Map;
      Type_Env  : Type_Maps.Map) return GM.Type_Descriptor is
   begin
      if Var_Types.Contains (Name) then
         return Var_Types.Element (Name);
      end if;
      return Resolve_Type (Name, Type_Env);
   end Resolve_Type;

   function Type_Access_Role (Info : GM.Type_Descriptor) return String is
   begin
      if UString_Value (Info.Kind) /= "access" then
         return "";
      elsif Info.Has_Access_Role then
         return UString_Value (Info.Access_Role);
      elsif Info.Anonymous and then Info.Is_Constant then
         return "Observe";
      elsif Info.Anonymous then
         return "Borrow";
      elsif Info.Is_All then
         return "GeneralAccess";
      elsif Info.Is_Constant then
         return "NamedConstant";
      end if;
      return "Owner";
   end Type_Access_Role;

   function Expr_Type
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Type_Env  : Type_Maps.Map) return GM.Type_Descriptor
   is
      Name : constant String :=
        (if Expr /= null then UString_Value (Expr.Type_Name) else "");
   begin
      if Expr = null then
         return BT.Integer_Type;
      elsif Expr.Kind = CM.Expr_String then
         return Resolve_Type ("string", Type_Env);
      elsif Expr.Kind = CM.Expr_Char then
         return Resolve_Type ("character", Type_Env);
      elsif Expr.Kind = CM.Expr_Real then
         if Name'Length > 0 and then Type_Env.Contains (Name) then
            return Type_Env.Element (Name);
         end if;
         return BT.Long_Float_Type;
      elsif Expr.Kind = CM.Expr_Ident then
         return Resolve_Type (UString_Value (Expr.Name), Var_Types, Type_Env);
      elsif Name'Length > 0 and then Type_Env.Contains (Name) then
         return Type_Env.Element (Name);
      elsif Name'Length > 0 and then Var_Types.Contains (Name) then
         return Var_Types.Element (Name);
      end if;
      return BT.Integer_Type;
   end Expr_Type;

   function Mir_Kind (Expr : CM.Expr_Access) return GM.Expr_Kind is
   begin
      if Expr = null then
         return GM.Expr_Unknown;
      end if;

      case Expr.Kind is
         when CM.Expr_Int =>
            return GM.Expr_Int;
         when CM.Expr_Real =>
            return GM.Expr_Real;
         when CM.Expr_String =>
            return GM.Expr_String;
         when CM.Expr_Char =>
            return GM.Expr_Char;
         when CM.Expr_Bool =>
            return GM.Expr_Bool;
         when CM.Expr_Null =>
            return GM.Expr_Null;
         when CM.Expr_Ident =>
            return GM.Expr_Ident;
         when CM.Expr_Select =>
            return GM.Expr_Select;
         when CM.Expr_Resolved_Index =>
            return GM.Expr_Resolved_Index;
         when CM.Expr_Conversion =>
            return GM.Expr_Conversion;
         when CM.Expr_Call =>
            return GM.Expr_Call;
         when CM.Expr_Allocator =>
            return GM.Expr_Allocator;
         when CM.Expr_Aggregate =>
            return GM.Expr_Aggregate;
         when CM.Expr_Tuple =>
            return GM.Expr_Tuple;
         when CM.Expr_Annotated =>
            return GM.Expr_Annotated;
         when CM.Expr_Unary =>
            return GM.Expr_Unary;
         when CM.Expr_Binary =>
            return GM.Expr_Binary;
         when others =>
            return GM.Expr_Unknown;
      end case;
   end Mir_Kind;

   function Lower_Expr
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Type_Env  : Type_Maps.Map) return GM.Expr_Access
   is
      Result : GM.Expr_Access;
      Field  : GM.Aggregate_Field;
   begin
      if Expr = null then
         return null;
      end if;

      Result := new GM.Expr_Node;
      Result.Kind := Mir_Kind (Expr);
      Result.Span := Expr.Span;
      Result.Type_Name := Expr_Type (Expr, Var_Types, Type_Env).Name;

      case Expr.Kind is
         when CM.Expr_Int =>
            Result.Text := Expr.Text;
            if Expr.Int_Value in CM.Wide_Integer (Long_Long_Integer'First) .. CM.Wide_Integer (Long_Long_Integer'Last) then
               Result.Int_Value := Long_Long_Integer (Expr.Int_Value);
            elsif Expr.Int_Value < 0 then
               Result.Int_Value := Long_Long_Integer'First;
            else
               Result.Int_Value := Long_Long_Integer'Last;
            end if;
         when CM.Expr_Real =>
            Result.Text := Expr.Text;
         when CM.Expr_String | CM.Expr_Char =>
            Result.Text := Expr.Text;
         when CM.Expr_Bool =>
            Result.Bool_Value := Expr.Bool_Value;
         when CM.Expr_Ident =>
            Result.Name := Expr.Name;
         when CM.Expr_Select =>
            Result.Prefix := Lower_Expr (Expr.Prefix, Var_Types, Type_Env);
            Result.Selector := Expr.Selector;
         when CM.Expr_Resolved_Index =>
            Result.Prefix := Lower_Expr (Expr.Prefix, Var_Types, Type_Env);
            for Item of Expr.Args loop
               Result.Indices.Append (Lower_Expr (Item, Var_Types, Type_Env));
            end loop;
         when CM.Expr_Conversion =>
            Result.Name := FT.To_UString (CM.Flatten_Name (Expr.Target));
            Result.Inner := Lower_Expr (Expr.Inner, Var_Types, Type_Env);
         when CM.Expr_Call =>
            Result.Callee := Lower_Expr (Expr.Callee, Var_Types, Type_Env);
            for Item of Expr.Args loop
               Result.Args.Append (Lower_Expr (Item, Var_Types, Type_Env));
            end loop;
            Result.Has_Call_Span := Expr.Has_Call_Span;
            Result.Call_Span := Expr.Call_Span;
         when CM.Expr_Allocator =>
            Result.Value := Lower_Expr (Expr.Value, Var_Types, Type_Env);
         when CM.Expr_Aggregate =>
            for Item of Expr.Fields loop
               Field.Field := Item.Field_Name;
               Field.Expr := Lower_Expr (Item.Expr, Var_Types, Type_Env);
               Field.Span := Item.Span;
               Result.Fields.Append (Field);
            end loop;
         when CM.Expr_Tuple =>
            for Item of Expr.Elements loop
               Result.Elements.Append (Lower_Expr (Item, Var_Types, Type_Env));
            end loop;
         when CM.Expr_Annotated =>
            Result.Inner := Lower_Expr (Expr.Inner, Var_Types, Type_Env);
            Result.Subtype_Name := FT.To_UString (CM.Flatten_Name (Expr.Target));
         when CM.Expr_Unary =>
            Result.Operator := Expr.Operator;
            Result.Inner := Lower_Expr (Expr.Inner, Var_Types, Type_Env);
         when CM.Expr_Binary =>
            Result.Operator := Expr.Operator;
            Result.Left := Lower_Expr (Expr.Left, Var_Types, Type_Env);
            Result.Right := Lower_Expr (Expr.Right, Var_Types, Type_Env);
         when CM.Expr_Subtype_Indication =>
            Result.Name := Expr.Name;
         when others =>
            null;
      end case;

      return Result;
   end Lower_Expr;

   function Lower_Target
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Type_Env  : Type_Maps.Map) return GM.Expr_Access is
   begin
      return Lower_Expr (Expr, Var_Types, Type_Env);
   end Lower_Target;

   function Ownership_Assignment_Effect
     (Target    : CM.Expr_Access;
      Value     : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Type_Env  : Type_Maps.Map) return GM.Ownership_Effect_Kind
   is
      Target_Type : constant GM.Type_Descriptor := Expr_Type (Target, Var_Types, Type_Env);
      Target_Role : constant String := Type_Access_Role (Target_Type);
      Value_Type  : GM.Type_Descriptor;
   begin
      if Target_Role = "" then
         return GM.Ownership_None;
      elsif Target_Role = "Observe" then
         return GM.Ownership_Observe;
      elsif Target_Role = "Borrow" then
         return GM.Ownership_Borrow;
      elsif Target_Role = "Owner" then
         if Value /= null and then Value.Kind in CM.Expr_Call | CM.Expr_Allocator then
            return GM.Ownership_Move;
         elsif Value /= null and then Value.Kind in CM.Expr_Ident | CM.Expr_Select then
            Value_Type := Expr_Type (Value, Var_Types, Type_Env);
            if Type_Access_Role (Value_Type) = "Owner" then
               return GM.Ownership_Move;
            end if;
         end if;
      end if;
      return GM.Ownership_None;
   end Ownership_Assignment_Effect;

   function Ownership_Call_Effect
     (Expr      : CM.Expr_Access;
      Functions : CM.Resolved_Subprogram_Vectors.Vector) return GM.Ownership_Effect_Kind
   is
      Name : constant String :=
        (if Expr /= null and then Expr.Callee /= null
         then CM.Flatten_Name (Expr.Callee)
         else "");
   begin
      if Expr = null or else Expr.Kind /= CM.Expr_Call then
         return GM.Ownership_None;
      end if;

      for Subprogram of Functions loop
         if UString_Value (Subprogram.Name) = Name then
            for Param of Subprogram.Params loop
               if Type_Access_Role (Param.Type_Info) = "Borrow" then
                  return GM.Ownership_Borrow;
               elsif Type_Access_Role (Param.Type_Info) = "Observe" then
                  return GM.Ownership_Observe;
               elsif UString_Value (Param.Mode) in "out" | "in out"
                 and then Type_Access_Role (Param.Type_Info) in "Owner" | "GeneralAccess"
               then
                  return GM.Ownership_Move;
               end if;
            end loop;
            exit;
         end if;
      end loop;

      return GM.Ownership_None;
   end Ownership_Call_Effect;

   function Ownership_Return_Effect
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Type_Env  : Type_Maps.Map) return GM.Ownership_Effect_Kind
   is
      Role : constant String := Type_Access_Role (Expr_Type (Expr, Var_Types, Type_Env));
   begin
      if Expr = null then
         return GM.Ownership_None;
      elsif Role = "Borrow" then
         return GM.Ownership_Borrow;
      elsif Role = "Observe" then
         return GM.Ownership_Observe;
      elsif Role = "Owner" then
         return GM.Ownership_Move;
      end if;
      return GM.Ownership_None;
   end Ownership_Return_Effect;

   function Append_Local
     (Locals         : in out GM.Local_Vectors.Vector;
      Name           : String;
      Kind           : String;
      Mode           : String;
      Type_Info      : GM.Type_Descriptor;
      Span           : FT.Source_Span;
      Scope_Id       : String;
      Ownership_Role : String := "";
      Is_Constant    : Boolean := False) return FT.UString
   is
      Local_Item : GM.Local_Entry;
      Role       : constant String :=
        (if Ownership_Role'Length > 0 then Ownership_Role else Type_Access_Role (Type_Info));
   begin
      Local_Item.Id := FT.To_UString ("v" & Trimmed (Natural (Locals.Length)));
      Local_Item.Name := FT.To_UString (Name);
      Local_Item.Kind := FT.To_UString (Kind);
      Local_Item.Mode := FT.To_UString (Mode);
      Local_Item.Is_Constant := Is_Constant;
      Local_Item.Scope_Id := FT.To_UString (Scope_Id);
      Local_Item.Ownership_Role := FT.To_UString (Role);
      Local_Item.Type_Info := Type_Info;
      Local_Item.Span := Span;
      Locals.Append (Local_Item);
      return Local_Item.Id;
   end Append_Local;

   function New_Scope
     (Id        : String;
      Parent_Id : String;
      Kind      : String) return GM.Scope_Entry
   is
      Result : GM.Scope_Entry;
   begin
      Result.Id := FT.To_UString (Id);
      if Parent_Id'Length > 0 then
         Result.Has_Parent_Scope := True;
         Result.Parent_Scope_Id := FT.To_UString (Parent_Id);
      end if;
      Result.Kind := FT.To_UString (Kind);
      return Result;
   end New_Scope;

   procedure Register_Scope
     (Work  : in out Builder;
      Scope : GM.Scope_Entry) is
   begin
      Work.Scopes.Append (Scope);
      Work.Scope_Map.Include (UString_Value (Scope.Id), Work.Scopes.Last_Index);
   end Register_Scope;

   function New_Block
     (Work            : in out Builder;
      Span            : FT.Source_Span;
      Role            : String;
      Active_Scope_Id : String) return FT.UString
   is
      Block : GM.Block_Entry;
      Id    : constant String := "bb" & Trimmed (Work.Next_Block);
   begin
      Work.Next_Block := Work.Next_Block + 1;
      Block.Id := FT.To_UString (Id);
      Block.Active_Scope_Id := FT.To_UString (Active_Scope_Id);
      Block.Role := FT.To_UString (Role);
      Block.Span := Span;
      Work.Blocks.Append (Block);
      Work.Block_Map.Include (Id, Work.Blocks.Last_Index);
      return Block.Id;
   end New_Block;

   function Block_Index
     (Work : Builder;
      Id   : String) return Positive is
   begin
      return Work.Block_Map.Element (Id);
   end Block_Index;

   function Block_Terminated
     (Work : Builder;
      Id   : String) return Boolean is
   begin
      return Work.Blocks (Block_Index (Work, Id)).Terminator.Kind /= GM.Terminator_Unknown;
   end Block_Terminated;

   function Reachable_Block_Ids
     (Work     : Builder;
      Entry_Id : String) return Index_Maps.Map
   is
      Result  : Index_Maps.Map;
      Pending : FT.UString_Vectors.Vector;
      Next    : Positive := 1;

      procedure Enqueue (Id : String) is
      begin
         if Id'Length = 0 or else not Work.Block_Map.Contains (Id) then
            return;
         elsif Result.Contains (Id) then
            return;
         end if;
         Result.Include (Id, 1);
         Pending.Append (FT.To_UString (Id));
      end Enqueue;
   begin
      Enqueue (Entry_Id);
      while not Pending.Is_Empty and then Next <= Pending.Last_Index loop
         declare
            Current_Id : constant String := UString_Value (Pending (Next));
            Block      : constant GM.Block_Entry := Work.Blocks (Block_Index (Work, Current_Id));
         begin
            Next := Next + 1;
            case Block.Terminator.Kind is
               when GM.Terminator_Jump =>
                  Enqueue (UString_Value (Block.Terminator.Target));
               when GM.Terminator_Branch =>
                  Enqueue (UString_Value (Block.Terminator.True_Target));
                  Enqueue (UString_Value (Block.Terminator.False_Target));
               when GM.Terminator_Select =>
                  if not Block.Terminator.Arms.Is_Empty then
                     for Arm of Block.Terminator.Arms loop
                        if Arm.Kind = GM.Select_Arm_Channel then
                           Enqueue (UString_Value (Arm.Channel_Data.Target));
                        elsif Arm.Kind = GM.Select_Arm_Delay then
                           Enqueue (UString_Value (Arm.Delay_Data.Target));
                        end if;
                     end loop;
                  end if;
               when others =>
                  null;
            end case;
         end;
      end loop;
      return Result;
   end Reachable_Block_Ids;

   procedure Finalize_Unknown_Terminators
     (Work     : in out Builder;
      Entry_Id : String) is
      Terminator : GM.Terminator_Entry;
      Reachable  : constant Index_Maps.Map := Reachable_Block_Ids (Work, Entry_Id);
   begin
      if not Work.Blocks.Is_Empty then
         for Index in Work.Blocks.First_Index .. Work.Blocks.Last_Index loop
            if Work.Blocks (Index).Terminator.Kind = GM.Terminator_Unknown then
               if Reachable.Contains (UString_Value (Work.Blocks (Index).Id)) then
                  raise Program_Error with "Unterminated reachable basic block in MIR lowering";
               end if;
               Terminator := (others => <>);
               Terminator.Kind := GM.Terminator_Jump;
               Terminator.Span := Work.Blocks (Index).Span;
               Terminator.Target := Work.Blocks (Index).Id;
               Work.Blocks (Index).Terminator := Terminator;
            end if;
         end loop;
      end if;
   end Finalize_Unknown_Terminators;

   procedure Add_Op
     (Work : in out Builder;
      Id   : String;
      Op   : GM.Op_Entry) is
   begin
      Work.Blocks (Block_Index (Work, Id)).Ops.Append (Op);
   end Add_Op;

   procedure Set_Terminator
     (Work       : in out Builder;
      Id         : String;
      Terminator : GM.Terminator_Entry) is
   begin
      Work.Blocks (Block_Index (Work, Id)).Terminator := Terminator;
   end Set_Terminator;

   procedure Register_Scope_Entry
     (Work     : in out Builder;
      Scope_Id : String;
      Block_Id : String) is
      Index : constant Positive := Work.Scope_Map.Element (Scope_Id);
   begin
      if UString_Value (Work.Scopes (Index).Entry_Block)'Length = 0 then
         Work.Scopes (Index).Entry_Block := FT.To_UString (Block_Id);
      end if;
   end Register_Scope_Entry;

   procedure Register_Scope_Exit
     (Work     : in out Builder;
      Scope_Id : String;
      Block_Id : String) is
      Index : constant Positive := Work.Scope_Map.Element (Scope_Id);
   begin
      for Existing of Work.Scopes (Index).Exit_Blocks loop
         if UString_Value (Existing) = Block_Id then
            return;
         end if;
      end loop;
      Work.Scopes (Index).Exit_Blocks.Append (FT.To_UString (Block_Id));
   end Register_Scope_Exit;

   procedure Register_Scope_Chain_Exits
     (Work           : in out Builder;
      Active_Scope_Id : String;
      Block_Id       : String) is
      Current_Id : FT.UString := FT.To_UString (Active_Scope_Id);
   begin
      while UString_Value (Current_Id)'Length > 0 loop
         Register_Scope_Exit (Work, UString_Value (Current_Id), Block_Id);
         declare
            Scope_Index : constant Positive := Work.Scope_Map.Element (UString_Value (Current_Id));
            Scope_Item  : constant GM.Scope_Entry := Work.Scopes (Scope_Index);
         begin
            if Scope_Item.Has_Parent_Scope then
               Current_Id := Scope_Item.Parent_Scope_Id;
            else
               exit;
            end if;
         end;
      end loop;
   end Register_Scope_Chain_Exits;

   procedure Set_Loop_Info
     (Work          : in out Builder;
      Block_Id      : String;
      Loop_Kind     : String;
      Loop_Var      : String;
      Exit_Target   : String) is
      Index : constant Positive := Block_Index (Work, Block_Id);
   begin
      Work.Blocks (Index).Has_Loop_Info := True;
      Work.Blocks (Index).Loop_Kind := FT.To_UString (Loop_Kind);
      Work.Blocks (Index).Loop_Var := FT.To_UString (Loop_Var);
      Work.Blocks (Index).Loop_Exit_Target := FT.To_UString (Exit_Target);
   end Set_Loop_Info;

   function Local_Names
     (Decls : CM.Resolved_Object_Decl_Vectors.Vector) return FT.UString_Vectors.Vector
   is
      Result : FT.UString_Vectors.Vector;
   begin
      for Decl of Decls loop
         for Name of Decl.Names loop
            Result.Append (Name);
         end loop;
      end loop;
      return Result;
   end Local_Names;

   function Local_Names
     (Decls : CM.Object_Decl_Vectors.Vector) return FT.UString_Vectors.Vector
   is
      Result : FT.UString_Vectors.Vector;
   begin
      for Decl of Decls loop
         for Name of Decl.Names loop
            Result.Append (Name);
         end loop;
      end loop;
      return Result;
   end Local_Names;

   function Local_Names_For_Ids
     (Locals : GM.Local_Vectors.Vector;
      Ids    : FT.UString_Vectors.Vector) return FT.UString_Vectors.Vector
   is
      Result : FT.UString_Vectors.Vector;
   begin
      if Ids.Is_Empty then
         return Result;
      end if;

      for Id of Ids loop
         for Local of Locals loop
            if Local.Id = Id then
               Result.Append (Local.Name);
               exit;
            end if;
         end loop;
      end loop;
      return Result;
   end Local_Names_For_Ids;

   function Is_Integerish (Info : GM.Type_Descriptor) return Boolean is
      Kind : constant String := FT.Lowercase (UString_Value (Info.Kind));
   begin
      return Kind = "integer" or else Kind = "subtype";
   end Is_Integerish;

   function Static_Integer_Value
     (Expr    : CM.Expr_Access;
      Success : out Boolean) return Long_Long_Integer is
   begin
      Success := False;
      if Expr = null then
         return 0;
      elsif Expr.Kind = CM.Expr_Int then
         Success := True;
         return Long_Long_Integer (Expr.Int_Value);
      elsif Expr.Kind = CM.Expr_Unary and then UString_Value (Expr.Operator) = "-" then
         declare
            Inner_Success : Boolean := False;
            Value         : constant Long_Long_Integer :=
              Static_Integer_Value (Expr.Inner, Inner_Success);
         begin
            Success := Inner_Success;
            return -Value;
         end;
      elsif Expr.Kind = CM.Expr_Conversion then
         return Static_Integer_Value (Expr.Inner, Success);
      end if;
      return 0;
   end Static_Integer_Value;

   function Static_Loop_Type
     (Range_Info : CM.Discrete_Range;
      Visible    : Type_Maps.Map;
      Type_Env   : Type_Maps.Map) return GM.Type_Descriptor
   is
      Low_Type     : GM.Type_Descriptor;
      High_Type    : GM.Type_Descriptor;
      Low_Value    : Long_Long_Integer := 0;
      High_Value   : Long_Long_Integer := 0;
      Has_Low      : Boolean := False;
      Has_High     : Boolean := False;
      Result       : GM.Type_Descriptor;
   begin
      if Range_Info.Kind = CM.Range_Subtype and then Range_Info.Name_Expr /= null then
         return Resolve_Type (CM.Flatten_Name (Range_Info.Name_Expr), Type_Env);
      end if;

      Low_Type := Expr_Type (Range_Info.Low_Expr, Visible, Type_Env);
      High_Type := Expr_Type (Range_Info.High_Expr, Visible, Type_Env);
      if Is_Integerish (Low_Type)
        and then Is_Integerish (High_Type)
        and then UString_Value (Low_Type.Name) = UString_Value (High_Type.Name)
        and then Low_Type.Has_Low
        and then Low_Type.Has_High
      then
         return Low_Type;
      end if;

      Low_Value := Static_Integer_Value (Range_Info.Low_Expr, Has_Low);
      High_Value := Static_Integer_Value (Range_Info.High_Expr, Has_High);
      if Has_Low and then Has_High then
         Result.Name := FT.To_UString ("loop_range");
         Result.Kind := FT.To_UString ("integer");
         Result.Has_Low := True;
         Result.Low := Low_Value;
         Result.Has_High := True;
         Result.High := High_Value;
         return Result;
      end if;

      return BT.Integer_Type;
   end Static_Loop_Type;

   procedure Static_Loop_Bounds
     (Range_Info : CM.Discrete_Range;
      Visible    : Type_Maps.Map;
      Type_Env   : Type_Maps.Map;
      Low_Expr   : out CM.Expr_Access;
      High_Expr  : out CM.Expr_Access;
      Loop_Type  : out GM.Type_Descriptor) is
   begin
      Loop_Type := Static_Loop_Type (Range_Info, Visible, Type_Env);
      if Range_Info.Kind = CM.Range_Subtype then
         Low_Expr :=
           new CM.Expr_Node'
             (Kind      => CM.Expr_Int,
              Span      => Range_Info.Span,
              Type_Name => FT.To_UString ("integer"),
              Text      => FT.To_UString (Trimmed ((if Loop_Type.Has_Low then Loop_Type.Low else INT64_LOW))),
              Int_Value => CM.Wide_Integer ((if Loop_Type.Has_Low then Loop_Type.Low else INT64_LOW)),
              others    => <>);
         High_Expr :=
           new CM.Expr_Node'
             (Kind      => CM.Expr_Int,
              Span      => Range_Info.Span,
              Type_Name => FT.To_UString ("integer"),
              Text      => FT.To_UString (Trimmed ((if Loop_Type.Has_High then Loop_Type.High else INT64_HIGH))),
              Int_Value => CM.Wide_Integer ((if Loop_Type.Has_High then Loop_Type.High else INT64_HIGH)),
              others    => <>);
      else
         Low_Expr := Range_Info.Low_Expr;
         High_Expr := Range_Info.High_Expr;
      end if;
   end Static_Loop_Bounds;

   function Literal_Expr
     (Value : Long_Long_Integer;
      Span  : FT.Source_Span) return CM.Expr_Access is
   begin
      return
        new CM.Expr_Node'
          (Kind      => CM.Expr_Int,
           Span      => Span,
           Type_Name => FT.To_UString ("integer"),
           Text      => FT.To_UString (Trimmed (Value)),
           Int_Value => CM.Wide_Integer (Value),
           others    => <>);
   end Literal_Expr;

   function Null_Expr
     (Span      : FT.Source_Span;
      Type_Name : String) return CM.Expr_Access is
   begin
      return
        new CM.Expr_Node'
          (Kind      => CM.Expr_Null,
           Span      => Span,
           Type_Name => FT.To_UString (Type_Name),
           Text      => FT.To_UString ("null"),
           others    => <>);
   end Null_Expr;

   function Ident_Expr
     (Name      : String;
      Span      : FT.Source_Span;
      Type_Name : String := "integer") return CM.Expr_Access is
   begin
      return
        new CM.Expr_Node'
          (Kind      => CM.Expr_Ident,
           Span      => Span,
           Type_Name => FT.To_UString (Type_Name),
           Name      => FT.To_UString (Name),
           others    => <>);
   end Ident_Expr;

   function Selector_Expr
     (Prefix    : CM.Expr_Access;
      Selector  : String;
      Span      : FT.Source_Span;
      Type_Name : String) return CM.Expr_Access is
   begin
      return
        new CM.Expr_Node'
          (Kind      => CM.Expr_Select,
           Span      => Span,
           Type_Name => FT.To_UString (Type_Name),
           Prefix    => Prefix,
           Selector  => FT.To_UString (Selector),
           others    => <>);
   end Selector_Expr;

   function Default_Initializer_Expr
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map;
      Span     : FT.Source_Span) return CM.Expr_Access
   is
      Kind   : constant String := FT.Lowercase (UString_Value (Info.Kind));
      Name   : constant String := FT.Lowercase (UString_Value (Info.Name));
      Result : CM.Expr_Access;
      Field  : CM.Aggregate_Field;
   begin
      if Kind = "subtype"
        and then Has_Text (Info.Base)
        and then not Info.Has_Low
        and then not Info.Has_High
        and then not Info.Has_Float_Low_Text
        and then not Info.Has_Float_High_Text
      then
         return Default_Initializer_Expr (Resolve_Type (UString_Value (Info.Base), Type_Env), Type_Env, Span);
      elsif Kind = "access" then
         return Null_Expr (Span, UString_Value (Info.Name));
      elsif Name = "string" then
         return
           new CM.Expr_Node'
             (Kind      => CM.Expr_String,
              Span      => Span,
              Type_Name => FT.To_UString ("string"),
              Text      => FT.To_UString (""),
              others    => <>);
      elsif Info.Is_Result_Builtin then
         Result := new CM.Expr_Node;
         Result.Kind := CM.Expr_Aggregate;
         Result.Type_Name := FT.To_UString (UString_Value (Info.Name));
         Result.Span := Span;

         Field.Field_Name := FT.To_UString ("ok");
         Field.Expr :=
           new CM.Expr_Node'
             (Kind       => CM.Expr_Bool,
              Span       => Span,
              Type_Name  => FT.To_UString ("boolean"),
              Bool_Value => True,
              others     => <>);
         Field.Span := Span;
         Result.Fields.Append (Field);

         Field.Field_Name := FT.To_UString ("message");
         Field.Expr := Default_Initializer_Expr (BT.String_Type, Type_Env, Span);
         Field.Span := Span;
         Result.Fields.Append (Field);
         return Result;
      elsif Kind = "record" then
         Result := new CM.Expr_Node;
         Result.Kind := CM.Expr_Aggregate;
         Result.Type_Name := Info.Name;
         Result.Span := Span;
         for Item of Info.Fields loop
            Field.Field_Name := Item.Name;
            Field.Expr := Default_Initializer_Expr (Resolve_Type (UString_Value (Item.Type_Name), Type_Env), Type_Env, Span);
            Field.Span := Span;
            Result.Fields.Append (Field);
         end loop;
         return Result;
      elsif Kind = "tuple" then
         Result := new CM.Expr_Node;
         Result.Kind := CM.Expr_Tuple;
         Result.Type_Name := Info.Name;
         Result.Span := Span;
         for Item of Info.Tuple_Element_Types loop
            Result.Elements.Append
              (Default_Initializer_Expr (Resolve_Type (UString_Value (Item), Type_Env), Type_Env, Span));
         end loop;
         return Result;
      end if;

      return
        Selector_Expr
          (Prefix    => Ident_Expr (UString_Value (Info.Name), Span, UString_Value (Info.Name)),
           Selector  => "first",
           Span      => Span,
           Type_Name => UString_Value (Info.Name));
   end Default_Initializer_Expr;

   function Binary_Expr
     (Op    : String;
      Left  : CM.Expr_Access;
      Right : CM.Expr_Access;
      Span  : FT.Source_Span) return CM.Expr_Access
   is
      Result_Type : FT.UString := FT.To_UString ("integer");
   begin
      if Op in "<" | "<=" | ">" | ">=" | "==" | "!=" | "and then" then
         Result_Type := FT.To_UString ("boolean");
      elsif Left /= null and then Has_Text (Left.Type_Name) then
         Result_Type := Left.Type_Name;
      end if;

      return
        new CM.Expr_Node'
          (Kind      => CM.Expr_Binary,
           Span      => Span,
           Type_Name => Result_Type,
           Operator  => FT.To_UString (Op),
           Left      => Left,
           Right     => Right,
           others    => <>);
   end Binary_Expr;

   function Is_Stable_Case_Scrutinee (Expr : CM.Expr_Access) return Boolean is
   begin
      if Expr = null then
         return False;
      end if;

      case Expr.Kind is
         when CM.Expr_Ident | CM.Expr_Select =>
            return True;
         when CM.Expr_Conversion | CM.Expr_Annotated =>
            return Is_Stable_Case_Scrutinee (Expr.Inner);
         when others =>
            return False;
      end case;
   end Is_Stable_Case_Scrutinee;

   procedure Collect_Scopes
     (Statements : CM.Statement_Access_Vectors.Vector;
      Visible    : Type_Maps.Map;
      Parent_Id  : String;
      Work       : in out Builder;
      Locals     : in out GM.Local_Vectors.Vector) is
      Current_Visible : Type_Maps.Map := Visible;
      Parent_Index    : constant Positive := Work.Scope_Map.Element (Parent_Id);
   begin
      for Stmt of Statements loop
         if Stmt.Kind = CM.Stmt_Object_Decl then
            for Name of Stmt.Decl.Names loop
               Work.Scopes (Parent_Index).Local_Ids.Append
                 (Append_Local
                    (Locals,
                     UString_Value (Name),
                     "local",
                     "in",
                     Stmt.Decl.Type_Info,
                     Stmt.Decl.Span,
                     Parent_Id,
                     Is_Constant => Stmt.Decl.Is_Constant));
               Current_Visible.Include (UString_Value (Name), Stmt.Decl.Type_Info);
            end loop;
         elsif Stmt.Kind = CM.Stmt_Destructure_Decl then
            declare
               Tuple_Type : constant GM.Type_Descriptor := Stmt.Destructure.Type_Info;
               Temp_Name  : constant String :=
                 (if Has_Text (Stmt.Destructure.Temp_Name)
                  then UString_Value (Stmt.Destructure.Temp_Name)
                  else "__safe_destructure_" & Trimmed (Natural (Locals.Length)));
            begin
               Stmt.Destructure.Temp_Name := FT.To_UString (Temp_Name);
               Work.Scopes (Parent_Index).Local_Ids.Append
                 (Append_Local
                    (Locals,
                     Temp_Name,
                     "local",
                     "in",
                     Tuple_Type,
                     Stmt.Destructure.Span,
                     Parent_Id,
                     Is_Constant => True));
               Current_Visible.Include (Temp_Name, Tuple_Type);
               for Index in Stmt.Destructure.Names.First_Index .. Stmt.Destructure.Names.Last_Index loop
                  declare
                     Element_Type : constant GM.Type_Descriptor :=
                       Resolve_Type
                         (UString_Value (Tuple_Type.Tuple_Element_Types (Index)),
                          Current_Visible,
                          Visible);
                  begin
                     Work.Scopes (Parent_Index).Local_Ids.Append
                       (Append_Local
                          (Locals,
                           UString_Value (Stmt.Destructure.Names (Index)),
                           "local",
                           "in",
                           Element_Type,
                           Stmt.Destructure.Span,
                           Parent_Id));
                     Current_Visible.Include
                       (UString_Value (Stmt.Destructure.Names (Index)),
                        Element_Type);
                  end;
               end loop;
            end;
         elsif Stmt.Kind = CM.Stmt_For then
            declare
               Scope_Id  : constant String := "scope" & Trimmed (Natural (Work.Scopes.Length));
               Scope     : GM.Scope_Entry := New_Scope (Scope_Id, Parent_Id, "loop");
               Loop_Type : constant GM.Type_Descriptor := Static_Loop_Type (Stmt.Loop_Range, Current_Visible, Visible);
               Child     : Type_Maps.Map := Current_Visible;
            begin
               Stmt.Scope_Id := FT.To_UString (Scope_Id);
               Scope.Local_Ids.Append
                 (Append_Local
                    (Locals,
                     UString_Value (Stmt.Loop_Var),
                     "local",
                     "in",
                     Loop_Type,
                     Stmt.Span,
                     Scope_Id));
               Child.Include (UString_Value (Stmt.Loop_Var), Loop_Type);
               Register_Scope (Work, Scope);
               Collect_Scopes (Stmt.Body_Stmts, Child, Scope_Id, Work, Locals);
            end;
         elsif Stmt.Kind = CM.Stmt_If then
            Collect_Scopes (Stmt.Then_Stmts, Current_Visible, Parent_Id, Work, Locals);
            for Part of Stmt.Elsifs loop
               Collect_Scopes (Part.Statements, Current_Visible, Parent_Id, Work, Locals);
            end loop;
            if Stmt.Has_Else then
               Collect_Scopes (Stmt.Else_Stmts, Current_Visible, Parent_Id, Work, Locals);
            end if;
         elsif Stmt.Kind = CM.Stmt_Case then
            for Arm of Stmt.Case_Arms loop
               Collect_Scopes (Arm.Statements, Current_Visible, Parent_Id, Work, Locals);
            end loop;
         elsif Stmt.Kind in CM.Stmt_While | CM.Stmt_Loop then
            Collect_Scopes (Stmt.Body_Stmts, Current_Visible, Parent_Id, Work, Locals);
         elsif Stmt.Kind = CM.Stmt_Select then
            for Arm of Stmt.Arms loop
               if Arm.Kind = CM.Select_Arm_Channel then
                  declare
                     Scope_Id : constant String := "scope" & Trimmed (Natural (Work.Scopes.Length));
                     Scope    : GM.Scope_Entry := New_Scope (Scope_Id, Parent_Id, "select_arm");
                     Child    : Type_Maps.Map := Current_Visible;
                  begin
                     Arm.Channel_Data.Scope_Id := FT.To_UString (Scope_Id);
                     Arm.Channel_Data.Local_Id :=
                       Append_Local
                         (Locals,
                          UString_Value (Arm.Channel_Data.Variable_Name),
                          "local",
                          "in",
                          Arm.Channel_Data.Type_Info,
                          Arm.Channel_Data.Span,
                          Scope_Id);
                     Scope.Local_Ids.Append (Arm.Channel_Data.Local_Id);
                     Child.Include
                       (UString_Value (Arm.Channel_Data.Variable_Name),
                        Arm.Channel_Data.Type_Info);
                     Register_Scope (Work, Scope);
                     Collect_Scopes
                       (Arm.Channel_Data.Statements, Child, Scope_Id, Work, Locals);
                  end;
               elsif Arm.Kind = CM.Select_Arm_Delay then
                  declare
                     Scope_Id : constant String := "scope" & Trimmed (Natural (Work.Scopes.Length));
                     Scope    : GM.Scope_Entry := New_Scope (Scope_Id, Parent_Id, "select_arm");
                     Child    : Type_Maps.Map := Current_Visible;
                  begin
                     Arm.Delay_Data.Scope_Id := FT.To_UString (Scope_Id);
                     Register_Scope (Work, Scope);
                     Collect_Scopes
                       (Arm.Delay_Data.Statements, Child, Scope_Id, Work, Locals);
                  end;
               end if;
            end loop;
         end if;
      end loop;
   end Collect_Scopes;

   procedure Lower_Branch_Condition
     (Work             : in out Builder;
      Current_Id       : String;
      Condition        : CM.Expr_Access;
      Visible_Types    : Type_Maps.Map;
      Type_Env         : Type_Maps.Map;
      True_Target      : String;
      False_Target     : String;
      Current_Scope_Id : String);

   function Lower_Statement
     (Work             : in out Builder;
      Current_Id       : FT.UString;
      Stmt             : CM.Statement_Access;
      Visible_Types    : Type_Maps.Map;
      Type_Env         : Type_Maps.Map;
      Current_Scope_Id : String;
      Functions        : CM.Resolved_Subprogram_Vectors.Vector;
      Loop_Exit_Target : String := "") return FT.UString;

   function Lower_Statement_List
     (Work             : in out Builder;
      Current_Id       : FT.UString;
      Statements       : CM.Statement_Access_Vectors.Vector;
      Visible_Types    : Type_Maps.Map;
      Type_Env         : Type_Maps.Map;
      Current_Scope_Id : String;
      Functions        : CM.Resolved_Subprogram_Vectors.Vector;
      Loop_Exit_Target : String := "") return FT.UString
   is
      Block_Id     : FT.UString := Current_Id;
      Local_Types  : Type_Maps.Map := Visible_Types;
   begin
      for Stmt of Statements loop
         if not Has_Block (Block_Id) then
            return Empty_Block_Id;
         end if;
         Block_Id :=
           Lower_Statement
             (Work,
              Block_Id,
              Stmt,
              Local_Types,
              Type_Env,
              Current_Scope_Id,
              Functions,
              Loop_Exit_Target);
         if Stmt.Kind = CM.Stmt_Object_Decl then
            for Name of Stmt.Decl.Names loop
               Local_Types.Include (UString_Value (Name), Stmt.Decl.Type_Info);
            end loop;
         elsif Stmt.Kind = CM.Stmt_Destructure_Decl then
            declare
               Tuple_Type : constant GM.Type_Descriptor := Stmt.Destructure.Type_Info;
            begin
               if Has_Text (Stmt.Destructure.Temp_Name) then
                  Local_Types.Include (UString_Value (Stmt.Destructure.Temp_Name), Tuple_Type);
               end if;
               for Index in Stmt.Destructure.Names.First_Index .. Stmt.Destructure.Names.Last_Index loop
                  Local_Types.Include
                    (UString_Value (Stmt.Destructure.Names (Index)),
                     Resolve_Type
                       (UString_Value (Tuple_Type.Tuple_Element_Types (Index)),
                        Local_Types,
                        Type_Env));
               end loop;
            end;
         end if;
      end loop;
      return Block_Id;
   end Lower_Statement_List;

   procedure Lower_Branch_Condition
     (Work             : in out Builder;
      Current_Id       : String;
      Condition        : CM.Expr_Access;
      Visible_Types    : Type_Maps.Map;
      Type_Env         : Type_Maps.Map;
      True_Target      : String;
      False_Target     : String;
      Current_Scope_Id : String)
   is
      Terminator : GM.Terminator_Entry;
   begin
      if Condition /= null
        and then Condition.Kind = CM.Expr_Binary
        and then UString_Value (Condition.Operator) = "and then"
      then
         declare
            Rhs_Id : constant FT.UString :=
              New_Block (Work, Condition.Right.Span, "and_then_rhs", Current_Scope_Id);
         begin
            Terminator.Kind := GM.Terminator_Branch;
            Terminator.Span := Condition.Left.Span;
            Terminator.Condition := Lower_Expr (Condition.Left, Visible_Types, Type_Env);
            Terminator.True_Target := Rhs_Id;
            Terminator.False_Target := FT.To_UString (False_Target);
            Set_Terminator (Work, Current_Id, Terminator);
            Lower_Branch_Condition
              (Work,
               UString_Value (Rhs_Id),
               Condition.Right,
               Visible_Types,
               Type_Env,
               True_Target,
               False_Target,
               Current_Scope_Id);
         end;
         return;
      end if;

      Terminator.Kind := GM.Terminator_Branch;
      Terminator.Span := Condition.Span;
      Terminator.Condition := Lower_Expr (Condition, Visible_Types, Type_Env);
      Terminator.True_Target := FT.To_UString (True_Target);
      Terminator.False_Target := FT.To_UString (False_Target);
      Set_Terminator (Work, Current_Id, Terminator);
   end Lower_Branch_Condition;

   function Lower_Statement
     (Work             : in out Builder;
      Current_Id       : FT.UString;
      Stmt             : CM.Statement_Access;
      Visible_Types    : Type_Maps.Map;
      Type_Env         : Type_Maps.Map;
      Current_Scope_Id : String;
      Functions        : CM.Resolved_Subprogram_Vectors.Vector;
      Loop_Exit_Target : String := "") return FT.UString
   is
      Assign_Op   : GM.Op_Entry;
      Call_Op     : GM.Op_Entry;
      Terminator  : GM.Terminator_Entry;
      Child_Types : Type_Maps.Map;
   begin
      case Stmt.Kind is
         when CM.Stmt_Object_Decl =>
            if Stmt.Decl.Has_Initializer and then Stmt.Decl.Initializer /= null then
               for Name of Stmt.Decl.Names loop
                  Assign_Op := (others => <>);
                  Assign_Op.Kind := GM.Op_Assign;
                  Assign_Op.Span := Stmt.Decl.Span;
                  Assign_Op.Target :=
                    Lower_Target
                      (Ident_Expr
                         (UString_Value (Name),
                          Stmt.Decl.Span,
                          UString_Value (Stmt.Decl.Type_Info.Name)),
                       Visible_Types,
                       Type_Env);
                  Assign_Op.Value := Lower_Expr (Stmt.Decl.Initializer, Visible_Types, Type_Env);
                  Assign_Op.Type_Name := Stmt.Decl.Type_Info.Name;
                  Assign_Op.Ownership_Effect :=
                    Ownership_Assignment_Effect
                      (Ident_Expr
                         (UString_Value (Name),
                          Stmt.Decl.Span,
                          UString_Value (Stmt.Decl.Type_Info.Name)),
                       Stmt.Decl.Initializer,
                       Visible_Types,
                       Type_Env);
                  Assign_Op.Declaration_Init := True;
                  Add_Op (Work, UString_Value (Current_Id), Assign_Op);
               end loop;
            elsif Stmt.Decl.Has_Implicit_Default_Init then
               for Name of Stmt.Decl.Names loop
                  Assign_Op := (others => <>);
                  Assign_Op.Kind := GM.Op_Assign;
                  Assign_Op.Span := Stmt.Decl.Span;
                  Assign_Op.Target :=
                    Lower_Target
                      (Ident_Expr
                         (UString_Value (Name),
                          Stmt.Decl.Span,
                          UString_Value (Stmt.Decl.Type_Info.Name)),
                       Visible_Types,
                       Type_Env);
                  Assign_Op.Value :=
                    Lower_Expr
                      (Default_Initializer_Expr (Stmt.Decl.Type_Info, Type_Env, Stmt.Decl.Span),
                       Visible_Types,
                       Type_Env);
                  Assign_Op.Type_Name := Stmt.Decl.Type_Info.Name;
                  Assign_Op.Ownership_Effect := GM.Ownership_None;
                  Assign_Op.Declaration_Init := True;
                  Add_Op (Work, UString_Value (Current_Id), Assign_Op);
               end loop;
            elsif FT.Lowercase (UString_Value (Stmt.Decl.Type_Info.Kind)) = "access"
              and then not Stmt.Decl.Type_Info.Not_Null
            then
               for Name of Stmt.Decl.Names loop
                  Assign_Op := (others => <>);
                  Assign_Op.Kind := GM.Op_Assign;
                  Assign_Op.Span := Stmt.Decl.Span;
                  Assign_Op.Target :=
                    Lower_Target
                      (Ident_Expr
                         (UString_Value (Name),
                          Stmt.Decl.Span,
                          UString_Value (Stmt.Decl.Type_Info.Name)),
                       Visible_Types,
                       Type_Env);
                  Assign_Op.Value :=
                    Lower_Expr
                      (Null_Expr
                         (Stmt.Decl.Span,
                          UString_Value (Stmt.Decl.Type_Info.Name)),
                       Visible_Types,
                       Type_Env);
                  Assign_Op.Type_Name := Stmt.Decl.Type_Info.Name;
                  Assign_Op.Ownership_Effect := GM.Ownership_None;
                  Assign_Op.Declaration_Init := True;
                  Add_Op (Work, UString_Value (Current_Id), Assign_Op);
               end loop;
            end if;
            return Current_Id;

         when CM.Stmt_Destructure_Decl =>
            declare
               Tuple_Type : constant GM.Type_Descriptor := Stmt.Destructure.Type_Info;
               Temp_Name  : constant String := UString_Value (Stmt.Destructure.Temp_Name);
               Temp_Target : constant CM.Expr_Access :=
                 Ident_Expr
                   (Temp_Name,
                    Stmt.Destructure.Span,
                    UString_Value (Tuple_Type.Name));
               Temp_Visible : Type_Maps.Map := Visible_Types;
            begin
               Temp_Visible.Include (Temp_Name, Tuple_Type);
               for Index in Stmt.Destructure.Names.First_Index .. Stmt.Destructure.Names.Last_Index loop
                  Temp_Visible.Include
                    (UString_Value (Stmt.Destructure.Names (Index)),
                     Resolve_Type
                       (UString_Value (Tuple_Type.Tuple_Element_Types (Index)),
                        Temp_Visible,
                        Type_Env));
               end loop;

               Assign_Op := (others => <>);
               Assign_Op.Kind := GM.Op_Assign;
               Assign_Op.Span := Stmt.Destructure.Span;
               Assign_Op.Target := Lower_Target (Temp_Target, Temp_Visible, Type_Env);
               Assign_Op.Value := Lower_Expr (Stmt.Destructure.Initializer, Visible_Types, Type_Env);
               Assign_Op.Type_Name := Tuple_Type.Name;
               Assign_Op.Ownership_Effect := GM.Ownership_None;
               Assign_Op.Declaration_Init := True;
               Add_Op (Work, UString_Value (Current_Id), Assign_Op);

               for Index in Stmt.Destructure.Names.First_Index .. Stmt.Destructure.Names.Last_Index loop
                  declare
                     Element_Type_Name : constant String :=
                       UString_Value (Tuple_Type.Tuple_Element_Types (Index));
                     Element_Target : constant CM.Expr_Access :=
                       Ident_Expr
                         (UString_Value (Stmt.Destructure.Names (Index)),
                          Stmt.Destructure.Span,
                          Element_Type_Name);
                     Element_Source : constant CM.Expr_Access :=
                       new CM.Expr_Node'
                         (Kind      => CM.Expr_Select,
                          Span      => Stmt.Destructure.Span,
                          Type_Name => FT.To_UString (Element_Type_Name),
                          Prefix    => Temp_Target,
                          Selector  => FT.To_UString (Trimmed (Natural (Index))),
                          others    => <>);
                  begin
                     Assign_Op := (others => <>);
                     Assign_Op.Kind := GM.Op_Assign;
                     Assign_Op.Span := Stmt.Destructure.Span;
                     Assign_Op.Target := Lower_Target (Element_Target, Temp_Visible, Type_Env);
                     Assign_Op.Value := Lower_Expr (Element_Source, Temp_Visible, Type_Env);
                     Assign_Op.Type_Name := FT.To_UString (Element_Type_Name);
                     Assign_Op.Ownership_Effect := GM.Ownership_None;
                     Assign_Op.Declaration_Init := True;
                     Add_Op (Work, UString_Value (Current_Id), Assign_Op);
                  end;
               end loop;
               return Current_Id;
            end;

         when CM.Stmt_Assign =>
            Assign_Op.Kind := GM.Op_Assign;
            Assign_Op.Span := Stmt.Span;
            Assign_Op.Target := Lower_Target (Stmt.Target, Visible_Types, Type_Env);
            Assign_Op.Value := Lower_Expr (Stmt.Value, Visible_Types, Type_Env);
            Assign_Op.Type_Name := Expr_Type (Stmt.Target, Visible_Types, Type_Env).Name;
            Assign_Op.Ownership_Effect :=
              Ownership_Assignment_Effect
                (Stmt.Target, Stmt.Value, Visible_Types, Type_Env);
            Add_Op (Work, UString_Value (Current_Id), Assign_Op);
            return Current_Id;

         when CM.Stmt_Call =>
            Call_Op.Kind := GM.Op_Call;
            Call_Op.Span := Stmt.Span;
            Call_Op.Value := Lower_Expr (Stmt.Call, Visible_Types, Type_Env);
            Call_Op.Type_Name := Expr_Type (Stmt.Call, Visible_Types, Type_Env).Name;
            Call_Op.Ownership_Effect :=
              Ownership_Call_Effect (Stmt.Call, Functions);
            Add_Op (Work, UString_Value (Current_Id), Call_Op);
            return Current_Id;

         when CM.Stmt_Exit =>
            if Stmt.Condition = null then
               Terminator.Kind := GM.Terminator_Jump;
               Terminator.Span := Stmt.Span;
               Terminator.Target := FT.To_UString (Loop_Exit_Target);
               Set_Terminator (Work, UString_Value (Current_Id), Terminator);
               return Empty_Block_Id;
            end if;
            declare
               Continue_Id : constant FT.UString :=
                 New_Block (Work, Stmt.Span, "loop_continue", Current_Scope_Id);
            begin
               Lower_Branch_Condition
                 (Work,
                  UString_Value (Current_Id),
                  Stmt.Condition,
                  Visible_Types,
                  Type_Env,
                  Loop_Exit_Target,
                  UString_Value (Continue_Id),
                  Current_Scope_Id);
               return Continue_Id;
            end;

         when CM.Stmt_Return =>
            Terminator.Kind := GM.Terminator_Return;
            Terminator.Span := Stmt.Span;
            if Stmt.Value /= null then
               Terminator.Has_Value := True;
               Terminator.Value := Lower_Expr (Stmt.Value, Visible_Types, Type_Env);
            end if;
            Terminator.Ownership_Effect :=
              Ownership_Return_Effect (Stmt.Value, Visible_Types, Type_Env);
            Set_Terminator (Work, UString_Value (Current_Id), Terminator);
            Register_Scope_Chain_Exits
              (Work, Current_Scope_Id, UString_Value (Current_Id));
            return Empty_Block_Id;

         when CM.Stmt_If =>
            declare
               Then_Id   : constant FT.UString :=
                 New_Block (Work, Stmt.Span, "if_then", Current_Scope_Id);
               Else_Id   : constant FT.UString :=
                 New_Block (Work, Stmt.Span, "if_else", Current_Scope_Id);
               Join_Id   : constant FT.UString :=
                 New_Block (Work, Stmt.Span, "if_join", Current_Scope_Id);
               Then_End  : FT.UString;
               Else_End  : FT.UString;
               Reached   : Boolean := False;
            begin
               Lower_Branch_Condition
                 (Work,
                  UString_Value (Current_Id),
                  Stmt.Condition,
                  Visible_Types,
                  Type_Env,
                  UString_Value (Then_Id),
                  UString_Value (Else_Id),
                  Current_Scope_Id);

               Then_End :=
                 Lower_Statement_List
                   (Work,
                    Then_Id,
                    Stmt.Then_Stmts,
                    Visible_Types,
                    Type_Env,
                    Current_Scope_Id,
                    Functions,
                    Loop_Exit_Target);

               if not Stmt.Elsifs.Is_Empty then
                  declare
                     First_Index : constant Positive := Stmt.Elsifs.First_Index;
                     Nested      : constant CM.Statement_Access := new CM.Statement;
                  begin
                     Nested.Kind := CM.Stmt_If;
                     Nested.Span := Stmt.Span;
                     Nested.Condition := Stmt.Elsifs (First_Index).Condition;
                     Nested.Then_Stmts := Stmt.Elsifs (First_Index).Statements;
                     if First_Index < Stmt.Elsifs.Last_Index then
                        for Index in First_Index + 1 .. Stmt.Elsifs.Last_Index loop
                           Nested.Elsifs.Append (Stmt.Elsifs (Index));
                        end loop;
                     end if;
                     Nested.Has_Else := Stmt.Has_Else;
                     Nested.Else_Stmts := Stmt.Else_Stmts;
                     Else_End :=
                       Lower_Statement
                         (Work,
                          Else_Id,
                          Nested,
                          Visible_Types,
                          Type_Env,
                          Current_Scope_Id,
                          Functions,
                          Loop_Exit_Target);
                  end;
               elsif Stmt.Has_Else then
                  Else_End :=
                    Lower_Statement_List
                      (Work,
                       Else_Id,
                       Stmt.Else_Stmts,
                       Visible_Types,
                       Type_Env,
                       Current_Scope_Id,
                       Functions,
                       Loop_Exit_Target);
               else
                  Else_End := Else_Id;
               end if;

               if Has_Block (Then_End)
                 and then not Block_Terminated (Work, UString_Value (Then_End))
               then
                  Terminator := (others => <>);
                  Terminator.Kind := GM.Terminator_Jump;
                  Terminator.Span := Stmt.Span;
                  Terminator.Target := Join_Id;
                  Set_Terminator (Work, UString_Value (Then_End), Terminator);
                  Reached := True;
               end if;

               if Has_Block (Else_End)
                 and then not Block_Terminated (Work, UString_Value (Else_End))
               then
                  Terminator := (others => <>);
                  Terminator.Kind := GM.Terminator_Jump;
                  Terminator.Span := Stmt.Span;
                  Terminator.Target := Join_Id;
                  Set_Terminator (Work, UString_Value (Else_End), Terminator);
                  Reached := True;
               end if;

               if Reached then
                  return Join_Id;
               end if;
               return Empty_Block_Id;
            end;

         when CM.Stmt_Case =>
            declare
               Case_Type      : constant GM.Type_Descriptor :=
                 Expr_Type (Stmt.Case_Expr, Visible_Types, Type_Env);
               Scope_Id       : constant String :=
                 "scope" & Trimmed (Natural (Work.Scopes.Length));
               Temp_Name      : constant String :=
                 "__safe_case_expr_" & Trimmed (Natural (Work.Locals.Length));
               Scope          : GM.Scope_Entry := New_Scope (Scope_Id, Current_Scope_Id, "case");
               Temp_Local_Id  : constant FT.UString :=
                 Append_Local
                   (Work.Locals,
                    Temp_Name,
                    "local",
                    "in",
                    Case_Type,
                    Stmt.Case_Expr.Span,
                    Scope_Id,
                    Is_Constant => True);
               Entry_Id       : constant FT.UString :=
                 New_Block (Work, Stmt.Span, "case_entry", Scope_Id);
               Join_Id        : constant FT.UString :=
                 New_Block (Work, Stmt.Span, "case_join", Current_Scope_Id);
               Current_Check  : FT.UString := Entry_Id;
               Arm_End        : FT.UString;
               Reached        : Boolean := False;
               Case_Types     : Type_Maps.Map := Visible_Types;
               Others_Arm     : constant CM.Case_Arm :=
                 Stmt.Case_Arms (Stmt.Case_Arms.Last_Index);
               Scope_Op       : GM.Op_Entry;
               Temp_Target    : constant CM.Expr_Access :=
                 Ident_Expr
                   (Temp_Name,
                    Stmt.Case_Expr.Span,
                    UString_Value (Case_Type.Name));
               Compare_Target : constant CM.Expr_Access :=
                 (if Is_Stable_Case_Scrutinee (Stmt.Case_Expr)
                  then Stmt.Case_Expr
                  else Temp_Target);
               procedure Close_Case_Scope
                 (Block_Id : FT.UString;
                  Span     : FT.Source_Span) is
               begin
                  Scope_Op := (others => <>);
                  Scope_Op.Kind := GM.Op_Scope_Exit;
                  Scope_Op.Span := Span;
                  Scope_Op.Scope_Id := FT.To_UString (Scope_Id);
                  Scope_Op.Locals.Append (FT.To_UString (Temp_Name));
                  Add_Op (Work, UString_Value (Block_Id), Scope_Op);
                  Register_Scope_Exit (Work, Scope_Id, UString_Value (Block_Id));
               end Close_Case_Scope;
            begin
               Scope.Local_Ids.Append (Temp_Local_Id);
               Register_Scope (Work, Scope);
               Register_Scope_Entry (Work, Scope_Id, UString_Value (Entry_Id));

               Terminator := (others => <>);
               Terminator.Kind := GM.Terminator_Jump;
               Terminator.Span := Stmt.Span;
               Terminator.Target := Entry_Id;
               Set_Terminator (Work, UString_Value (Current_Id), Terminator);

               Case_Types.Include (Temp_Name, Case_Type);

               Scope_Op := (others => <>);
               Scope_Op.Kind := GM.Op_Scope_Enter;
               Scope_Op.Span := Stmt.Span;
               Scope_Op.Scope_Id := FT.To_UString (Scope_Id);
               Scope_Op.Locals.Append (FT.To_UString (Temp_Name));
               Add_Op (Work, UString_Value (Entry_Id), Scope_Op);

               Assign_Op := (others => <>);
               Assign_Op.Kind := GM.Op_Assign;
               Assign_Op.Span := Stmt.Case_Expr.Span;
               Assign_Op.Target := Lower_Target (Temp_Target, Case_Types, Type_Env);
               Assign_Op.Value := Lower_Expr (Stmt.Case_Expr, Visible_Types, Type_Env);
               Assign_Op.Type_Name := Case_Type.Name;
               Assign_Op.Ownership_Effect := GM.Ownership_None;
               Assign_Op.Declaration_Init := True;
               Add_Op (Work, UString_Value (Entry_Id), Assign_Op);

               if Stmt.Case_Arms.Length > 1 then
                  for Index in Stmt.Case_Arms.First_Index .. Stmt.Case_Arms.Last_Index - 1 loop
                     declare
                        Arm      : constant CM.Case_Arm := Stmt.Case_Arms (Index);
                        True_Id  : constant FT.UString :=
                          New_Block (Work, Arm.Span, "case_arm", Scope_Id);
                        False_Id : constant FT.UString :=
                          (if Index = Stmt.Case_Arms.Last_Index - 1
                           then New_Block (Work, Others_Arm.Span, "case_others", Scope_Id)
                           else New_Block (Work, Arm.Span, "case_next", Scope_Id));
                        Cond_Expr : constant CM.Expr_Access :=
                          Binary_Expr ("==", Compare_Target, Arm.Choice, Arm.Span);
                     begin
                        Lower_Branch_Condition
                          (Work,
                           UString_Value (Current_Check),
                           Cond_Expr,
                           Case_Types,
                           Type_Env,
                           UString_Value (True_Id),
                           UString_Value (False_Id),
                           Scope_Id);

                        Arm_End :=
                          Lower_Statement_List
                            (Work,
                             True_Id,
                             Arm.Statements,
                             Case_Types,
                             Type_Env,
                             Scope_Id,
                             Functions,
                             Loop_Exit_Target);

                        if Has_Block (Arm_End)
                          and then not Block_Terminated (Work, UString_Value (Arm_End))
                        then
                           Close_Case_Scope (Arm_End, Arm.Span);
                           Terminator := (others => <>);
                           Terminator.Kind := GM.Terminator_Jump;
                           Terminator.Span := Arm.Span;
                           Terminator.Target := Join_Id;
                           Set_Terminator (Work, UString_Value (Arm_End), Terminator);
                           Reached := True;
                        end if;

                        Current_Check := False_Id;
                     end;
                  end loop;
               end if;

               Arm_End :=
                 Lower_Statement_List
                   (Work,
                    Current_Check,
                    Others_Arm.Statements,
                    Case_Types,
                    Type_Env,
                    Scope_Id,
                    Functions,
                    Loop_Exit_Target);

               if Has_Block (Arm_End)
                 and then not Block_Terminated (Work, UString_Value (Arm_End))
               then
                  Close_Case_Scope (Arm_End, Others_Arm.Span);
                  Terminator := (others => <>);
                  Terminator.Kind := GM.Terminator_Jump;
                  Terminator.Span := Others_Arm.Span;
                  Terminator.Target := Join_Id;
                  Set_Terminator (Work, UString_Value (Arm_End), Terminator);
                  Reached := True;
               end if;

               if Reached then
                  return Join_Id;
               end if;
               return Empty_Block_Id;
            end;

         when CM.Stmt_While =>
            declare
               Header_Id : constant FT.UString :=
                 New_Block (Work, Stmt.Span, "while_header", Current_Scope_Id);
               Body_Id   : constant FT.UString :=
                 New_Block (Work, Stmt.Span, "while_body", Current_Scope_Id);
               Exit_Id   : constant FT.UString :=
                 New_Block (Work, Stmt.Span, "while_exit", Current_Scope_Id);
               Body_End  : FT.UString;
            begin
               Terminator.Kind := GM.Terminator_Jump;
               Terminator.Span := Stmt.Span;
               Terminator.Target := Header_Id;
               Set_Terminator (Work, UString_Value (Current_Id), Terminator);

               Lower_Branch_Condition
                 (Work,
                  UString_Value (Header_Id),
                  Stmt.Condition,
                  Visible_Types,
                  Type_Env,
                  UString_Value (Body_Id),
                  UString_Value (Exit_Id),
                  Current_Scope_Id);

               Body_End :=
                 Lower_Statement_List
                   (Work,
                    Body_Id,
                    Stmt.Body_Stmts,
                    Visible_Types,
                    Type_Env,
                    Current_Scope_Id,
                    Functions,
                    UString_Value (Exit_Id));

               if Has_Block (Body_End)
                 and then not Block_Terminated (Work, UString_Value (Body_End))
               then
                  Terminator := (others => <>);
                  Terminator.Kind := GM.Terminator_Jump;
                  Terminator.Span := Stmt.Span;
                  Terminator.Target := Header_Id;
                  Set_Terminator (Work, UString_Value (Body_End), Terminator);
               end if;
               return Exit_Id;
            end;

         when CM.Stmt_Loop =>
            declare
               Header_Id : constant FT.UString :=
                 New_Block (Work, Stmt.Span, "loop_header", Current_Scope_Id);
               Body_Id   : constant FT.UString :=
                 New_Block (Work, Stmt.Span, "loop_body", Current_Scope_Id);
               Exit_Id   : constant FT.UString :=
                 New_Block (Work, Stmt.Span, "loop_exit", Current_Scope_Id);
               Body_End  : FT.UString;
            begin
               Terminator.Kind := GM.Terminator_Jump;
               Terminator.Span := Stmt.Span;
               Terminator.Target := Header_Id;
               Set_Terminator (Work, UString_Value (Current_Id), Terminator);

               Terminator := (others => <>);
               Terminator.Kind := GM.Terminator_Jump;
               Terminator.Span := Stmt.Span;
               Terminator.Target := Body_Id;
               Set_Terminator (Work, UString_Value (Header_Id), Terminator);
               Set_Loop_Info
                 (Work,
                  UString_Value (Header_Id),
                  "loop",
                  "",
                  UString_Value (Exit_Id));

               Body_End :=
                 Lower_Statement_List
                   (Work,
                    Body_Id,
                    Stmt.Body_Stmts,
                    Visible_Types,
                    Type_Env,
                    Current_Scope_Id,
                    Functions,
                    UString_Value (Exit_Id));

               if Has_Block (Body_End)
                 and then not Block_Terminated (Work, UString_Value (Body_End))
               then
                  Terminator := (others => <>);
                  Terminator.Kind := GM.Terminator_Jump;
                  Terminator.Span := Stmt.Span;
                  Terminator.Target := Header_Id;
                  Set_Terminator (Work, UString_Value (Body_End), Terminator);
               end if;
               return Exit_Id;
            end;

         when CM.Stmt_For =>
            declare
               Scope_Id   : constant String := UString_Value (Stmt.Scope_Id);
               Init_Id    : constant FT.UString :=
                 New_Block (Work, Stmt.Span, "for_init", Scope_Id);
               Header_Id  : constant FT.UString :=
                 New_Block (Work, Stmt.Span, "for_header", Scope_Id);
               Body_Id    : constant FT.UString :=
                 New_Block (Work, Stmt.Span, "for_body", Scope_Id);
               Latch_Id   : constant FT.UString :=
                 New_Block (Work, Stmt.Span, "for_latch", Scope_Id);
               Exit_Id    : constant FT.UString :=
                 New_Block (Work, Stmt.Span, "for_exit", Current_Scope_Id);
               Loop_Type  : GM.Type_Descriptor;
               Low_Expr   : CM.Expr_Access;
               High_Expr  : CM.Expr_Access;
               Body_End   : FT.UString;
               Loop_Types : Type_Maps.Map := Visible_Types;
               Scope_Op   : GM.Op_Entry;
               Cond_Expr  : CM.Expr_Access;
               Inc_Expr   : CM.Expr_Access;
            begin
               Register_Scope_Entry (Work, Scope_Id, UString_Value (Init_Id));

               Terminator.Kind := GM.Terminator_Jump;
               Terminator.Span := Stmt.Span;
               Terminator.Target := Init_Id;
               Set_Terminator (Work, UString_Value (Current_Id), Terminator);

               Static_Loop_Bounds
                 (Stmt.Loop_Range, Visible_Types, Type_Env, Low_Expr, High_Expr, Loop_Type);
               Loop_Types.Include (UString_Value (Stmt.Loop_Var), Loop_Type);

               Scope_Op.Kind := GM.Op_Scope_Enter;
               Scope_Op.Span := Stmt.Span;
               Scope_Op.Scope_Id := FT.To_UString (Scope_Id);
               Scope_Op.Locals.Append (Stmt.Loop_Var);
               Add_Op (Work, UString_Value (Init_Id), Scope_Op);

               Assign_Op := (others => <>);
               Assign_Op.Kind := GM.Op_Assign;
               Assign_Op.Span := Stmt.Span;
               Assign_Op.Target :=
                 Lower_Target
                   (Ident_Expr
                      (UString_Value (Stmt.Loop_Var),
                       Stmt.Span,
                       UString_Value (Loop_Type.Name)),
                    Loop_Types,
                    Type_Env);
               Assign_Op.Value := Lower_Expr (Low_Expr, Loop_Types, Type_Env);
               Assign_Op.Type_Name := Loop_Type.Name;
               Assign_Op.Ownership_Effect := GM.Ownership_None;
               Assign_Op.Declaration_Init := True;
               Add_Op (Work, UString_Value (Init_Id), Assign_Op);

               Terminator := (others => <>);
               Terminator.Kind := GM.Terminator_Jump;
               Terminator.Span := Stmt.Span;
               Terminator.Target := Header_Id;
               Set_Terminator (Work, UString_Value (Init_Id), Terminator);

               Cond_Expr :=
                 Binary_Expr
                   ("<=",
                    Ident_Expr
                      (UString_Value (Stmt.Loop_Var),
                       Stmt.Span,
                       UString_Value (Loop_Type.Name)),
                    High_Expr,
                    Stmt.Span);

               Terminator := (others => <>);
               Terminator.Kind := GM.Terminator_Branch;
               Terminator.Span := Stmt.Span;
               Terminator.Condition := Lower_Expr (Cond_Expr, Loop_Types, Type_Env);
               Terminator.True_Target := Body_Id;
               Terminator.False_Target := Exit_Id;
               Set_Terminator (Work, UString_Value (Header_Id), Terminator);
               Set_Loop_Info
                 (Work,
                  UString_Value (Header_Id),
                  "for",
                  UString_Value (Stmt.Loop_Var),
                  UString_Value (Exit_Id));

               Body_End :=
                 Lower_Statement_List
                   (Work,
                    Body_Id,
                    Stmt.Body_Stmts,
                    Loop_Types,
                    Type_Env,
                    Scope_Id,
                    Functions,
                    UString_Value (Exit_Id));

               if Has_Block (Body_End)
                 and then not Block_Terminated (Work, UString_Value (Body_End))
               then
                  Terminator := (others => <>);
                  Terminator.Kind := GM.Terminator_Jump;
                  Terminator.Span := Stmt.Span;
                  Terminator.Target := Latch_Id;
                  Set_Terminator (Work, UString_Value (Body_End), Terminator);
               end if;

               Inc_Expr :=
                 Binary_Expr
                   ("+",
                    Ident_Expr
                      (UString_Value (Stmt.Loop_Var),
                       Stmt.Span,
                       UString_Value (Loop_Type.Name)),
                    Literal_Expr (1, Stmt.Span),
                    Stmt.Span);

               Assign_Op := (others => <>);
               Assign_Op.Kind := GM.Op_Assign;
               Assign_Op.Span := Stmt.Span;
               Assign_Op.Target :=
                 Lower_Target
                   (Ident_Expr
                      (UString_Value (Stmt.Loop_Var),
                       Stmt.Span,
                       UString_Value (Loop_Type.Name)),
                    Loop_Types,
                    Type_Env);
               Assign_Op.Value := Lower_Expr (Inc_Expr, Loop_Types, Type_Env);
               Assign_Op.Type_Name := Loop_Type.Name;
               Assign_Op.Ownership_Effect := GM.Ownership_None;
               Assign_Op.Declaration_Init := False;
               Add_Op (Work, UString_Value (Latch_Id), Assign_Op);

               Terminator := (others => <>);
               Terminator.Kind := GM.Terminator_Jump;
               Terminator.Span := Stmt.Span;
               Terminator.Target := Header_Id;
               Set_Terminator (Work, UString_Value (Latch_Id), Terminator);

               Scope_Op := (others => <>);
               Scope_Op.Kind := GM.Op_Scope_Exit;
               Scope_Op.Span := Stmt.Span;
               Scope_Op.Scope_Id := FT.To_UString (Scope_Id);
               Scope_Op.Locals.Append (Stmt.Loop_Var);
               Add_Op (Work, UString_Value (Exit_Id), Scope_Op);
               Register_Scope_Exit (Work, Scope_Id, UString_Value (Exit_Id));

               return Exit_Id;
            end;

         when CM.Stmt_Send =>
            Call_Op := (others => <>);
            Call_Op.Kind := GM.Op_Channel_Send;
            Call_Op.Span := Stmt.Span;
            Call_Op.Channel := Lower_Expr (Stmt.Channel_Name, Visible_Types, Type_Env);
            Call_Op.Value := Lower_Expr (Stmt.Value, Visible_Types, Type_Env);
            Call_Op.Type_Name := Expr_Type (Stmt.Value, Visible_Types, Type_Env).Name;
            Call_Op.Ownership_Effect := GM.Ownership_None;
            Add_Op (Work, UString_Value (Current_Id), Call_Op);
            return Current_Id;

         when CM.Stmt_Receive =>
            Assign_Op := (others => <>);
            Assign_Op.Kind := GM.Op_Channel_Receive;
            Assign_Op.Span := Stmt.Span;
            Assign_Op.Channel := Lower_Expr (Stmt.Channel_Name, Visible_Types, Type_Env);
            Assign_Op.Target := Lower_Target (Stmt.Target, Visible_Types, Type_Env);
            Assign_Op.Type_Name := Expr_Type (Stmt.Target, Visible_Types, Type_Env).Name;
            Assign_Op.Ownership_Effect := GM.Ownership_None;
            Add_Op (Work, UString_Value (Current_Id), Assign_Op);
            return Current_Id;

         when CM.Stmt_Try_Send =>
            Call_Op := (others => <>);
            Call_Op.Kind := GM.Op_Channel_Try_Send;
            Call_Op.Span := Stmt.Span;
            Call_Op.Channel := Lower_Expr (Stmt.Channel_Name, Visible_Types, Type_Env);
            Call_Op.Value := Lower_Expr (Stmt.Value, Visible_Types, Type_Env);
            Call_Op.Success_Target := Lower_Target (Stmt.Success_Var, Visible_Types, Type_Env);
            Call_Op.Type_Name := Expr_Type (Stmt.Value, Visible_Types, Type_Env).Name;
            Call_Op.Ownership_Effect := GM.Ownership_None;
            Add_Op (Work, UString_Value (Current_Id), Call_Op);
            return Current_Id;

         when CM.Stmt_Try_Receive =>
            Assign_Op := (others => <>);
            Assign_Op.Kind := GM.Op_Channel_Try_Receive;
            Assign_Op.Span := Stmt.Span;
            Assign_Op.Channel := Lower_Expr (Stmt.Channel_Name, Visible_Types, Type_Env);
            Assign_Op.Target := Lower_Target (Stmt.Target, Visible_Types, Type_Env);
            Assign_Op.Success_Target := Lower_Target (Stmt.Success_Var, Visible_Types, Type_Env);
            Assign_Op.Type_Name := Expr_Type (Stmt.Target, Visible_Types, Type_Env).Name;
            Assign_Op.Ownership_Effect := GM.Ownership_None;
            Add_Op (Work, UString_Value (Current_Id), Assign_Op);
            return Current_Id;

         when CM.Stmt_Delay =>
            Call_Op := (others => <>);
            Call_Op.Kind := GM.Op_Delay;
            Call_Op.Span := Stmt.Span;
            Call_Op.Value := Lower_Expr (Stmt.Value, Visible_Types, Type_Env);
            Call_Op.Type_Name := FT.To_UString ("duration");
            Call_Op.Ownership_Effect := GM.Ownership_None;
            Add_Op (Work, UString_Value (Current_Id), Call_Op);
            return Current_Id;

         when CM.Stmt_Select =>
            declare
               Join_Id   : constant FT.UString :=
                 New_Block (Work, Stmt.Span, "select_join", Current_Scope_Id);
               Select_Term : GM.Terminator_Entry := (others => <>);
               Reached   : Boolean := False;
            begin
               Select_Term.Kind := GM.Terminator_Select;
               Select_Term.Span := Stmt.Span;
               for Arm of Stmt.Arms loop
                  if Arm.Kind = CM.Select_Arm_Channel then
                     declare
                        Scope_Id    : constant String := UString_Value (Arm.Channel_Data.Scope_Id);
                        Entry_Id    : constant FT.UString :=
                          New_Block (Work, Arm.Span, "select_channel_arm", Scope_Id);
                        Body_End    : FT.UString;
                        Scope_Op    : GM.Op_Entry;
                        Scope_Index : constant Positive := Work.Scope_Map.Element (Scope_Id);
                        Arm_Info    : GM.Select_Arm_Entry;
                        Arm_Types   : Type_Maps.Map := Visible_Types;
                     begin
                        Register_Scope_Entry (Work, Scope_Id, UString_Value (Entry_Id));
                        Arm_Types.Include
                          (UString_Value (Arm.Channel_Data.Variable_Name),
                           Arm.Channel_Data.Type_Info);
                        Arm_Info.Kind := GM.Select_Arm_Channel;
                        Arm_Info.Channel_Data.Channel_Name :=
                          FT.To_UString (CM.Flatten_Name (Arm.Channel_Data.Channel_Name));
                        Arm_Info.Channel_Data.Variable_Name := Arm.Channel_Data.Variable_Name;
                        Arm_Info.Channel_Data.Scope_Id := Arm.Channel_Data.Scope_Id;
                        Arm_Info.Channel_Data.Local_Id := Arm.Channel_Data.Local_Id;
                        Arm_Info.Channel_Data.Type_Info := Arm.Channel_Data.Type_Info;
                        Arm_Info.Channel_Data.Target := Entry_Id;
                        Arm_Info.Channel_Data.Span := Arm.Channel_Data.Span;
                        Select_Term.Arms.Append (Arm_Info);

                        if not Work.Scopes (Scope_Index).Local_Ids.Is_Empty then
                           Scope_Op.Kind := GM.Op_Scope_Enter;
                           Scope_Op.Span := Arm.Channel_Data.Span;
                           Scope_Op.Scope_Id := FT.To_UString (Scope_Id);
                           Scope_Op.Locals :=
                             Local_Names_For_Ids
                               (Work.Locals,
                                Work.Scopes (Scope_Index).Local_Ids);
                           Add_Op (Work, UString_Value (Entry_Id), Scope_Op);
                        end if;

                        Body_End :=
                          Lower_Statement_List
                            (Work,
                             Entry_Id,
                             Arm.Channel_Data.Statements,
                             Arm_Types,
                             Type_Env,
                             Scope_Id,
                             Functions);

                        if Has_Block (Body_End)
                          and then not Block_Terminated (Work, UString_Value (Body_End))
                        then
                           if not Work.Scopes (Scope_Index).Local_Ids.Is_Empty then
                              Scope_Op := (others => <>);
                              Scope_Op.Kind := GM.Op_Scope_Exit;
                              Scope_Op.Span := Arm.Channel_Data.Span;
                              Scope_Op.Scope_Id := FT.To_UString (Scope_Id);
                              Scope_Op.Locals :=
                                Local_Names_For_Ids
                                  (Work.Locals,
                                   Work.Scopes (Scope_Index).Local_Ids);
                              Add_Op (Work, UString_Value (Body_End), Scope_Op);
                              Register_Scope_Exit (Work, Scope_Id, UString_Value (Body_End));
                           end if;
                           Terminator := (others => <>);
                           Terminator.Kind := GM.Terminator_Jump;
                           Terminator.Span := Arm.Channel_Data.Span;
                           Terminator.Target := Join_Id;
                           Set_Terminator (Work, UString_Value (Body_End), Terminator);
                           Reached := True;
                        end if;
                     end;
                  elsif Arm.Kind = CM.Select_Arm_Delay then
                     declare
                        Scope_Id : constant String := UString_Value (Arm.Delay_Data.Scope_Id);
                        Entry_Id : constant FT.UString :=
                          New_Block (Work, Arm.Span, "select_delay_arm", Scope_Id);
                        Body_End : FT.UString;
                        Arm_Info : GM.Select_Arm_Entry;
                        Scope_Index : constant Positive := Work.Scope_Map.Element (Scope_Id);
                        Scope_Op    : GM.Op_Entry;
                     begin
                        Register_Scope_Entry (Work, Scope_Id, UString_Value (Entry_Id));
                        Arm_Info.Kind := GM.Select_Arm_Delay;
                        Arm_Info.Delay_Data.Duration_Expr :=
                          Lower_Expr (Arm.Delay_Data.Duration_Expr, Visible_Types, Type_Env);
                        Arm_Info.Delay_Data.Target := Entry_Id;
                        Arm_Info.Delay_Data.Span := Arm.Delay_Data.Span;
                        Select_Term.Arms.Append (Arm_Info);

                        if not Work.Scopes (Scope_Index).Local_Ids.Is_Empty then
                           Scope_Op := (others => <>);
                           Scope_Op.Kind := GM.Op_Scope_Enter;
                           Scope_Op.Span := Arm.Delay_Data.Span;
                           Scope_Op.Scope_Id := FT.To_UString (Scope_Id);
                           Scope_Op.Locals :=
                             Local_Names_For_Ids
                               (Work.Locals,
                                Work.Scopes (Scope_Index).Local_Ids);
                           Add_Op (Work, UString_Value (Entry_Id), Scope_Op);
                        end if;

                        Body_End :=
                          Lower_Statement_List
                            (Work,
                             Entry_Id,
                             Arm.Delay_Data.Statements,
                             Visible_Types,
                             Type_Env,
                             Scope_Id,
                             Functions);
                        if Has_Block (Body_End)
                          and then not Block_Terminated (Work, UString_Value (Body_End))
                        then
                           if not Work.Scopes (Scope_Index).Local_Ids.Is_Empty then
                              Scope_Op := (others => <>);
                              Scope_Op.Kind := GM.Op_Scope_Exit;
                              Scope_Op.Span := Arm.Delay_Data.Span;
                              Scope_Op.Scope_Id := FT.To_UString (Scope_Id);
                              Scope_Op.Locals :=
                                Local_Names_For_Ids
                                  (Work.Locals,
                                   Work.Scopes (Scope_Index).Local_Ids);
                              Add_Op (Work, UString_Value (Body_End), Scope_Op);
                              Register_Scope_Exit (Work, Scope_Id, UString_Value (Body_End));
                           end if;
                           Terminator := (others => <>);
                           Terminator.Kind := GM.Terminator_Jump;
                           Terminator.Span := Arm.Delay_Data.Span;
                           Terminator.Target := Join_Id;
                           Set_Terminator (Work, UString_Value (Body_End), Terminator);
                           Reached := True;
                        end if;
                     end;
                  end if;
               end loop;
               Set_Terminator (Work, UString_Value (Current_Id), Select_Term);
               if Reached then
                  return Join_Id;
               end if;
               return Empty_Block_Id;
            end;

         when others =>
            return Current_Id;
      end case;
   end Lower_Statement;

   function Lower_Subprogram
     (Subprogram    : CM.Resolved_Subprogram;
      All_Functions : CM.Resolved_Subprogram_Vectors.Vector;
      Type_Env      : Type_Maps.Map;
      Package_Objects : CM.Resolved_Object_Decl_Vectors.Vector) return GM.Graph_Entry
   is
      Result       : GM.Graph_Entry;
      Visible      : Type_Maps.Map := Type_Env;
      Work         : Builder;
      Root_Locals  : constant FT.UString_Vectors.Vector := Local_Names (Subprogram.Declarations);
      Root_Scope   : constant GM.Scope_Entry := New_Scope ("scope0", "", "subprogram");
      Entry_Id     : FT.UString;
      End_Id       : FT.UString;
      Assign_Op    : GM.Op_Entry;
      Scope_Op     : GM.Op_Entry;
      Terminator   : GM.Terminator_Entry;
   begin
      Result.Name := Subprogram.Name;
      Result.Kind := Subprogram.Kind;
      Result.Has_Span := True;
      Result.Span := Subprogram.Span;
      Result.Has_Return_Type := Subprogram.Has_Return_Type;
      Result.Return_Type := Subprogram.Return_Type;

      Register_Scope (Work, Root_Scope);

      for Decl of Package_Objects loop
         for Name of Decl.Names loop
            Visible.Include (UString_Value (Name), Decl.Type_Info);
            declare
               Global_Local_Id : constant FT.UString :=
                 Append_Local
                   (Result.Locals,
                    UString_Value (Name),
                    "global",
                    "in",
                    Decl.Type_Info,
                    Decl.Span,
                    "scope0",
                    Is_Constant => Decl.Is_Constant);
            begin
               Work.Scopes (Work.Scope_Map.Element ("scope0")).Local_Ids.Append
                 (Global_Local_Id);
            end;
         end loop;
      end loop;

      for Param of Subprogram.Params loop
         declare
            Param_Type : GM.Type_Descriptor := Param.Type_Info;
            Param_Role : FT.UString := FT.To_UString (Type_Access_Role (Param_Type));
         begin
            if UString_Value (Param.Mode) = "in"
              and then UString_Value (Param_Role) = "Owner"
            then
               Param_Type.Has_Access_Role := True;
               Param_Type.Access_Role := FT.To_UString ("GeneralAccess");
               Param_Role := FT.To_UString ("GeneralAccess");
            end if;
            Visible.Include (UString_Value (Param.Name), Param_Type);
            Work.Scopes (Work.Scope_Map.Element ("scope0")).Local_Ids.Append
              (Append_Local
                 (Result.Locals,
                  UString_Value (Param.Name),
                  "param",
                  UString_Value (Param.Mode),
                  Param_Type,
                  Param.Span,
                  "scope0",
                  UString_Value (Param_Role)));
         end;
      end loop;

      for Decl of Subprogram.Declarations loop
         for Name of Decl.Names loop
            Visible.Include (UString_Value (Name), Decl.Type_Info);
            Work.Scopes (Work.Scope_Map.Element ("scope0")).Local_Ids.Append
              (Append_Local
                 (Result.Locals,
                  UString_Value (Name),
                  "local",
                  "in",
                  Decl.Type_Info,
                  Decl.Span,
                  "scope0",
                  Is_Constant => Decl.Is_Constant));
         end loop;
      end loop;

      Collect_Scopes (Subprogram.Statements, Visible, "scope0", Work, Result.Locals);
      Work.Locals := Result.Locals;

      Entry_Id := New_Block (Work, Subprogram.Span, "entry", "scope0");
      Register_Scope_Entry (Work, "scope0", UString_Value (Entry_Id));
      Result.Entry_BB := Entry_Id;

      if not Root_Locals.Is_Empty then
         Scope_Op.Kind := GM.Op_Scope_Enter;
         Scope_Op.Span := Subprogram.Span;
         Scope_Op.Scope_Id := FT.To_UString ("scope0");
         Scope_Op.Locals := Root_Locals;
         Add_Op (Work, UString_Value (Entry_Id), Scope_Op);
      end if;

      for Decl of Package_Objects loop
         for Name of Decl.Names loop
            if Decl.Has_Initializer and then Decl.Initializer /= null then
               Assign_Op := (others => <>);
               Assign_Op.Kind := GM.Op_Assign;
               Assign_Op.Span := Decl.Span;
               Assign_Op.Target :=
                 Lower_Target
                   (Ident_Expr
                      (UString_Value (Name),
                       Decl.Span,
                       UString_Value (Decl.Type_Info.Name)),
                    Visible,
                    Type_Env);
               Assign_Op.Value := Lower_Expr (Decl.Initializer, Visible, Type_Env);
               Assign_Op.Type_Name := Decl.Type_Info.Name;
               Assign_Op.Ownership_Effect :=
                 Ownership_Assignment_Effect
                   (Ident_Expr
                      (UString_Value (Name),
                       Decl.Span,
                       UString_Value (Decl.Type_Info.Name)),
                    Decl.Initializer,
                    Visible,
                    Type_Env);
               Assign_Op.Declaration_Init := True;
               Add_Op (Work, UString_Value (Entry_Id), Assign_Op);
            end if;
         end loop;
      end loop;

      for Decl of Subprogram.Declarations loop
         for Name of Decl.Names loop
            if Decl.Has_Initializer and then Decl.Initializer /= null then
               Assign_Op := (others => <>);
               Assign_Op.Kind := GM.Op_Assign;
               Assign_Op.Span := Decl.Span;
               Assign_Op.Target :=
                 Lower_Target
                   (Ident_Expr
                      (UString_Value (Name),
                       Decl.Span,
                       UString_Value (Decl.Type_Info.Name)),
                    Visible,
                    Type_Env);
               Assign_Op.Value := Lower_Expr (Decl.Initializer, Visible, Type_Env);
               Assign_Op.Type_Name := Decl.Type_Info.Name;
               Assign_Op.Ownership_Effect :=
                 Ownership_Assignment_Effect
                   (Ident_Expr
                      (UString_Value (Name),
                       Decl.Span,
                       UString_Value (Decl.Type_Info.Name)),
                    Decl.Initializer,
                    Visible,
                    Type_Env);
               Assign_Op.Declaration_Init := True;
               Add_Op (Work, UString_Value (Entry_Id), Assign_Op);
            end if;
         end loop;
      end loop;

      End_Id :=
        Lower_Statement_List
          (Work,
           Entry_Id,
           Subprogram.Statements,
           Visible,
           Type_Env,
           "scope0",
           All_Functions);

      if Has_Block (End_Id)
        and then not Block_Terminated (Work, UString_Value (End_Id))
      then
         Terminator.Kind := GM.Terminator_Return;
         Terminator.Span := Subprogram.Span;
         Terminator.Ownership_Effect := GM.Ownership_None;
         Set_Terminator (Work, UString_Value (End_Id), Terminator);
         Register_Scope_Chain_Exits
           (Work,
            UString_Value
              (Work.Blocks (Block_Index (Work, UString_Value (End_Id))).Active_Scope_Id),
            UString_Value (End_Id));
      end if;

      Finalize_Unknown_Terminators (Work, UString_Value (Result.Entry_BB));
      Result.Locals := Work.Locals;
      Result.Scopes := Work.Scopes;
      Result.Blocks := Work.Blocks;
      return Result;
   end Lower_Subprogram;

   function Lower_Unit_Init
     (Unit          : CM.Resolved_Unit;
      All_Functions : CM.Resolved_Subprogram_Vectors.Vector;
      Type_Env      : Type_Maps.Map) return GM.Graph_Entry
   is
      Result      : GM.Graph_Entry;
      Visible     : Type_Maps.Map := Type_Env;
      Work        : Builder;
      Root_Scope  : constant GM.Scope_Entry := New_Scope ("scope0", "", "unit");
      Entry_Id    : FT.UString;
      End_Id      : FT.UString;
      Assign_Op   : GM.Op_Entry;
      Terminator  : GM.Terminator_Entry;
   begin
      Result.Name := FT.To_UString (UString_Value (Unit.Package_Name) & ".__unit_init");
      Result.Kind := FT.To_UString ("unit_init");
      Result.Has_Span := True;
      Result.Span := Unit.Statements (Unit.Statements.First_Index).Span;

      Register_Scope (Work, Root_Scope);

      for Decl of Unit.Objects loop
         for Name of Decl.Names loop
            Visible.Include (UString_Value (Name), Decl.Type_Info);
            declare
               Global_Local_Id : constant FT.UString :=
                 Append_Local
                   (Result.Locals,
                    UString_Value (Name),
                    "global",
                    "in",
                    Decl.Type_Info,
                    Decl.Span,
                    "scope0",
                    Is_Constant => Decl.Is_Constant);
            begin
               Work.Scopes (Work.Scope_Map.Element ("scope0")).Local_Ids.Append
                 (Global_Local_Id);
            end;
         end loop;
      end loop;

      Collect_Scopes (Unit.Statements, Visible, "scope0", Work, Result.Locals);
      Work.Locals := Result.Locals;

      Entry_Id := New_Block (Work, FT.Null_Span, "entry", "scope0");
      Register_Scope_Entry (Work, "scope0", UString_Value (Entry_Id));
      Result.Entry_BB := Entry_Id;

      for Decl of Unit.Objects loop
         for Name of Decl.Names loop
            if Decl.Has_Initializer and then Decl.Initializer /= null then
               Assign_Op := (others => <>);
               Assign_Op.Kind := GM.Op_Assign;
               Assign_Op.Span := Decl.Span;
               Assign_Op.Target :=
                 Lower_Target
                   (Ident_Expr
                      (UString_Value (Name),
                       Decl.Span,
                       UString_Value (Decl.Type_Info.Name)),
                    Visible,
                    Type_Env);
               Assign_Op.Value := Lower_Expr (Decl.Initializer, Visible, Type_Env);
               Assign_Op.Type_Name := Decl.Type_Info.Name;
               Assign_Op.Ownership_Effect :=
                 Ownership_Assignment_Effect
                   (Ident_Expr
                      (UString_Value (Name),
                       Decl.Span,
                       UString_Value (Decl.Type_Info.Name)),
                    Decl.Initializer,
                    Visible,
                    Type_Env);
               Assign_Op.Declaration_Init := True;
               Add_Op (Work, UString_Value (Entry_Id), Assign_Op);
            end if;
         end loop;
      end loop;

      End_Id :=
        Lower_Statement_List
          (Work,
           Entry_Id,
           Unit.Statements,
           Visible,
           Type_Env,
           "scope0",
           All_Functions);

      if Has_Block (End_Id)
        and then not Block_Terminated (Work, UString_Value (End_Id))
      then
         Terminator.Kind := GM.Terminator_Return;
         Terminator.Span := FT.Null_Span;
         Terminator.Ownership_Effect := GM.Ownership_None;
         Set_Terminator (Work, UString_Value (End_Id), Terminator);
         Register_Scope_Chain_Exits
           (Work,
            UString_Value
              (Work.Blocks (Block_Index (Work, UString_Value (End_Id))).Active_Scope_Id),
            UString_Value (End_Id));
      end if;

      Finalize_Unknown_Terminators (Work, UString_Value (Result.Entry_BB));
      Result.Locals := Work.Locals;
      Result.Scopes := Work.Scopes;
      Result.Blocks := Work.Blocks;
      return Result;
   end Lower_Unit_Init;

   function Lower_Task
     (Task_Item       : CM.Resolved_Task;
      All_Functions   : CM.Resolved_Subprogram_Vectors.Vector;
      Type_Env        : Type_Maps.Map;
      Package_Objects : CM.Resolved_Object_Decl_Vectors.Vector) return GM.Graph_Entry
   is
      Result       : GM.Graph_Entry;
      Visible      : Type_Maps.Map := Type_Env;
      Work         : Builder;
      Root_Locals  : constant FT.UString_Vectors.Vector := Local_Names (Task_Item.Declarations);
      Root_Scope   : constant GM.Scope_Entry := New_Scope ("scope0", "", "task");
      Entry_Id     : FT.UString;
      End_Id       : FT.UString;
      Assign_Op    : GM.Op_Entry;
      Scope_Op     : GM.Op_Entry;
      Terminator   : GM.Terminator_Entry;
   begin
      Result.Name := Task_Item.Name;
      Result.Kind := FT.To_UString ("task");
      Result.Has_Span := True;
      Result.Span := Task_Item.Span;
      Result.Has_Priority := True;
      Result.Priority := Task_Item.Priority;
      Result.Has_Explicit_Priority := Task_Item.Has_Explicit_Priority;

      Register_Scope (Work, Root_Scope);

      for Decl of Package_Objects loop
         for Name of Decl.Names loop
            Visible.Include (UString_Value (Name), Decl.Type_Info);
            declare
               Global_Local_Id : constant FT.UString :=
                 Append_Local
                   (Result.Locals,
                    UString_Value (Name),
                    "global",
                    "in",
                    Decl.Type_Info,
                    Decl.Span,
                    "scope0",
                    Is_Constant => Decl.Is_Constant);
            begin
               Work.Scopes (Work.Scope_Map.Element ("scope0")).Local_Ids.Append
                 (Global_Local_Id);
            end;
         end loop;
      end loop;

      for Decl of Task_Item.Declarations loop
         for Name of Decl.Names loop
            Visible.Include (UString_Value (Name), Decl.Type_Info);
            Work.Scopes (Work.Scope_Map.Element ("scope0")).Local_Ids.Append
              (Append_Local
                 (Result.Locals,
                  UString_Value (Name),
                  "local",
                  "in",
                  Decl.Type_Info,
                  Decl.Span,
                  "scope0",
                  Is_Constant => Decl.Is_Constant));
         end loop;
      end loop;

      Collect_Scopes (Task_Item.Statements, Visible, "scope0", Work, Result.Locals);
      Work.Locals := Result.Locals;

      Entry_Id := New_Block (Work, Task_Item.Span, "entry", "scope0");
      Register_Scope_Entry (Work, "scope0", UString_Value (Entry_Id));
      Result.Entry_BB := Entry_Id;

      if not Root_Locals.Is_Empty then
         Scope_Op.Kind := GM.Op_Scope_Enter;
         Scope_Op.Span := Task_Item.Span;
         Scope_Op.Scope_Id := FT.To_UString ("scope0");
         Scope_Op.Locals := Root_Locals;
         Add_Op (Work, UString_Value (Entry_Id), Scope_Op);
      end if;

      for Decl of Package_Objects loop
         for Name of Decl.Names loop
            if Decl.Has_Initializer and then Decl.Initializer /= null then
               Assign_Op := (others => <>);
               Assign_Op.Kind := GM.Op_Assign;
               Assign_Op.Span := Decl.Span;
               Assign_Op.Target :=
                 Lower_Target
                   (Ident_Expr
                      (UString_Value (Name),
                       Decl.Span,
                       UString_Value (Decl.Type_Info.Name)),
                    Visible,
                    Type_Env);
               Assign_Op.Value := Lower_Expr (Decl.Initializer, Visible, Type_Env);
               Assign_Op.Type_Name := Decl.Type_Info.Name;
               Assign_Op.Ownership_Effect :=
                 Ownership_Assignment_Effect
                   (Ident_Expr
                      (UString_Value (Name),
                       Decl.Span,
                       UString_Value (Decl.Type_Info.Name)),
                    Decl.Initializer,
                    Visible,
                    Type_Env);
               Assign_Op.Declaration_Init := True;
               Add_Op (Work, UString_Value (Entry_Id), Assign_Op);
            end if;
         end loop;
      end loop;

      for Decl of Task_Item.Declarations loop
         for Name of Decl.Names loop
            if Decl.Has_Initializer and then Decl.Initializer /= null then
               Assign_Op := (others => <>);
               Assign_Op.Kind := GM.Op_Assign;
               Assign_Op.Span := Decl.Span;
               Assign_Op.Target :=
                 Lower_Target
                   (Ident_Expr
                      (UString_Value (Name),
                       Decl.Span,
                       UString_Value (Decl.Type_Info.Name)),
                    Visible,
                    Type_Env);
               Assign_Op.Value := Lower_Expr (Decl.Initializer, Visible, Type_Env);
               Assign_Op.Type_Name := Decl.Type_Info.Name;
               Assign_Op.Ownership_Effect :=
                 Ownership_Assignment_Effect
                   (Ident_Expr
                      (UString_Value (Name),
                       Decl.Span,
                       UString_Value (Decl.Type_Info.Name)),
                    Decl.Initializer,
                    Visible,
                    Type_Env);
               Assign_Op.Declaration_Init := True;
               Add_Op (Work, UString_Value (Entry_Id), Assign_Op);
            end if;
         end loop;
      end loop;

      End_Id :=
        Lower_Statement_List
          (Work,
           Entry_Id,
           Task_Item.Statements,
           Visible,
           Type_Env,
           "scope0",
           All_Functions);

      if Has_Block (End_Id)
        and then not Block_Terminated (Work, UString_Value (End_Id))
      then
         Terminator.Kind := GM.Terminator_Jump;
         Terminator.Span := Task_Item.Span;
         Terminator.Target := End_Id;
         Set_Terminator (Work, UString_Value (End_Id), Terminator);
      end if;

      Finalize_Unknown_Terminators (Work, UString_Value (Result.Entry_BB));
      Result.Locals := Work.Locals;
      Result.Scopes := Work.Scopes;
      Result.Blocks := Work.Blocks;
      return Result;
   end Lower_Task;

   function Lower (Unit : CM.Resolved_Unit) return GM.Mir_Document is
      Result   : GM.Mir_Document;
      Type_Env : Type_Maps.Map;
   begin
      Add_Builtins (Type_Env);
      for Item of Unit.Types loop
         Type_Env.Include (UString_Value (Item.Name), Item);
         Result.Types.Append (Item);
      end loop;
      for Item of Unit.Imported_Types loop
         Type_Env.Include (UString_Value (Item.Name), Item);
         Result.Types.Append (Item);
      end loop;

      Result.Path := Unit.Path;
      Result.Format := GM.Mir_V2;
      Result.Has_Source_Path := True;
      Result.Source_Path := Unit.Path;
      Result.Unit_Kind := FT.To_UString ((if Unit.Kind = CM.Unit_Entry then "entry" else "package"));
      Result.Package_Name := Unit.Package_Name;

      for Channel_Item of Unit.Channels loop
         Result.Channels.Append
           ((Name => Channel_Item.Name,
             Element_Type => Channel_Item.Element_Type,
             Capacity => Channel_Item.Capacity,
             Has_Required_Ceiling => Channel_Item.Has_Required_Ceiling,
             Required_Ceiling => Channel_Item.Required_Ceiling,
             Span => Channel_Item.Span));
      end loop;

      for Channel_Item of Unit.Imported_Channels loop
         Result.Channels.Append
           ((Name => Channel_Item.Name,
             Element_Type => Channel_Item.Element_Type,
             Capacity => Channel_Item.Capacity,
             Has_Required_Ceiling => Channel_Item.Has_Required_Ceiling,
             Required_Ceiling => Channel_Item.Required_Ceiling,
             Span => Channel_Item.Span));
      end loop;

      for Item of Unit.Imported_Subprograms loop
         Result.Externals.Append (Item);
      end loop;

      if not Unit.Statements.Is_Empty then
         Result.Graphs.Append
           (Lower_Unit_Init
              (Unit,
               Unit.Subprograms,
               Type_Env));
      end if;

      for Subprogram of Unit.Subprograms loop
         Result.Graphs.Append
           (Lower_Subprogram
              (Subprogram,
               Unit.Subprograms,
               Type_Env,
               Unit.Objects));
      end loop;

      for Task_Item of Unit.Tasks loop
         Result.Graphs.Append
           (Lower_Task
              (Task_Item,
               Unit.Subprograms,
               Type_Env,
               Unit.Objects));
      end loop;

      return Result;
   end Lower;
end Safe_Frontend.Check_Lower;
