with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Strings.Hash;
with Safe_Frontend.Mir_Model;
with Safe_Frontend.Types;

package body Safe_Frontend.Check_Resolve is
   package FT renames Safe_Frontend.Types;
   package GM renames Safe_Frontend.Mir_Model;

   use type CM.Expr_Access;
   use type CM.Expr_Kind;
   use type CM.Discrete_Range_Kind;
   use type CM.Package_Item_Kind;
   use type CM.Statement_Kind;
   use type CM.Type_Decl_Kind;
   use type FT.UString;

   type Function_Info is record
      Name                 : FT.UString := FT.To_UString ("");
      Kind                 : FT.UString := FT.To_UString ("");
      Params               : CM.Symbol_Vectors.Vector;
      Has_Return_Type      : Boolean := False;
      Return_Type          : GM.Type_Descriptor;
      Return_Is_Access_Def : Boolean := False;
      Span                 : FT.Source_Span := FT.Null_Span;
   end record;

   package Type_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => GM.Type_Descriptor,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=",
      "="             => GM."=");

   package Function_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Function_Info,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   Resolve_Failure : exception;
   Raised_Diag     : CM.MD.Diagnostic;

   function UString_Value (Value : FT.UString) return String is
   begin
      return FT.To_String (Value);
   end UString_Value;

   function Make_Builtin
     (Name : String;
      Low  : CM.Wide_Integer;
      High : CM.Wide_Integer) return GM.Type_Descriptor
   is
      Result : GM.Type_Descriptor;
   begin
      Result.Name := FT.To_UString (Name);
      Result.Kind := FT.To_UString ("integer");
      Result.Has_Low := True;
      Result.Low := Long_Long_Integer (Low);
      Result.Has_High := True;
      Result.High := Long_Long_Integer (High);
      return Result;
   end Make_Builtin;

   procedure Add_Builtins (Type_Env : in out Type_Maps.Map) is
   begin
      Type_Env.Include ("Integer", Make_Builtin ("Integer", -(2 ** 63), (2 ** 63) - 1));
      Type_Env.Include ("Natural", Make_Builtin ("Natural", 0, (2 ** 63) - 1));
      Type_Env.Include ("Boolean", Make_Builtin ("Boolean", 0, 1));
   end Add_Builtins;

   procedure Raise_Diag (Item : CM.MD.Diagnostic) is
   begin
      Raised_Diag := Item;
      raise Resolve_Failure;
   end Raise_Diag;

   function Default_Integer return GM.Type_Descriptor is
   begin
      return Make_Builtin ("Integer", -(2 ** 63), (2 ** 63) - 1);
   end Default_Integer;

   function Default_Boolean return GM.Type_Descriptor is
   begin
      return Make_Builtin ("Boolean", 0, 1);
   end Default_Boolean;

   function Classify_Access_Role
     (Anonymous   : Boolean;
      Is_Constant : Boolean;
      Is_All      : Boolean) return String is
   begin
      if Anonymous and then Is_Constant then
         return "Observe";
      elsif Anonymous then
         return "Borrow";
      elsif Is_All then
         return "GeneralAccess";
      elsif Is_Constant then
         return "NamedConstant";
      end if;
      return "Owner";
   end Classify_Access_Role;

   function Is_Builtin_Name (Name : String) return Boolean is
   begin
      return Name in "Integer" | "Natural" | "Boolean";
   end Is_Builtin_Name;

   function Flatten_Name (Expr : CM.Expr_Access) return String is
   begin
      if Expr = null then
         return "";
      elsif Expr.Kind = CM.Expr_Ident then
         return UString_Value (Expr.Name);
      elsif Expr.Kind = CM.Expr_Select then
         return Flatten_Name (Expr.Prefix) & "." & UString_Value (Expr.Selector);
      end if;
      return "";
   end Flatten_Name;

   function Resolve_Type
     (Name     : String;
      Type_Env : Type_Maps.Map;
      Path     : String;
      Span     : FT.Source_Span) return GM.Type_Descriptor
   is
   begin
      if Type_Env.Contains (Name) then
         return Type_Env.Element (Name);
      end if;

      Raise_Diag
        (CM.Source_Frontend_Error
           (Path    => Path,
            Span    => Span,
            Message => "unknown type `" & Name & "`"));
      return Default_Integer;
   end Resolve_Type;

   function Literal_Value
     (Expr : CM.Expr_Access;
      Path : String) return CM.Wide_Integer
   is
   begin
      if Expr = null then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path,
               Span    => FT.Null_Span,
               Message => "expected integer literal"));
      elsif Expr.Kind = CM.Expr_Int then
         return Expr.Int_Value;
      elsif Expr.Kind = CM.Expr_Bool then
         return (if Expr.Bool_Value then 1 else 0);
      elsif Expr.Kind = CM.Expr_Unary and then UString_Value (Expr.Operator) = "-" then
         return -Literal_Value (Expr.Inner, Path);
      end if;

      Raise_Diag
        (CM.Source_Frontend_Error
           (Path    => Path,
            Span    => Expr.Span,
            Message => "type bounds must be integer literals"));
      return 0;
   end Literal_Value;

   function Resolve_Type_Spec
     (Spec     : CM.Type_Spec;
      Type_Env : Type_Maps.Map;
      Path     : String) return GM.Type_Descriptor
   is
      Result : GM.Type_Descriptor;
      Target : GM.Type_Descriptor;
   begin
      case Spec.Kind is
         when CM.Type_Spec_Name | CM.Type_Spec_Subtype_Indication =>
            return Resolve_Type (UString_Value (Spec.Name), Type_Env, Path, Spec.Span);
         when CM.Type_Spec_Access_Def =>
            Target := Resolve_Type (Flatten_Name (Spec.Target_Name), Type_Env, Path, Spec.Span);
            Result.Name := FT.To_UString ("access " & UString_Value (Target.Name));
            Result.Kind := FT.To_UString ("access");
            Result.Has_Target := True;
            Result.Target := Target.Name;
            Result.Not_Null := Spec.Not_Null;
            Result.Anonymous := Spec.Anonymous;
            Result.Is_All := Spec.Is_All;
            Result.Is_Constant := Spec.Is_Constant;
            Result.Has_Access_Role := True;
            Result.Access_Role :=
              FT.To_UString
                (Classify_Access_Role (Spec.Anonymous, Spec.Is_Constant, Spec.Is_All));
            return Result;
         when others =>
            Raise_Diag
              (CM.Source_Frontend_Error
                 (Path    => Path,
                  Span    => Spec.Span,
                  Message => "unsupported type specification"));
            return Default_Integer;
      end case;
   end Resolve_Type_Spec;

   function Access_Target_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return GM.Type_Descriptor is
   begin
      if UString_Value (Info.Kind) = "access" and then Info.Has_Target then
         return Resolve_Type (UString_Value (Info.Target), Type_Env, "", FT.Null_Span);
      end if;
      return Info;
   end Access_Target_Type;

   function Field_Type
     (Info       : GM.Type_Descriptor;
      Field_Name : String;
      Type_Env   : Type_Maps.Map) return GM.Type_Descriptor
   is
   begin
      if UString_Value (Info.Kind) = "record" then
         for Field of Info.Fields loop
            if UString_Value (Field.Name) = Field_Name then
               return Resolve_Type (UString_Value (Field.Type_Name), Type_Env, "", FT.Null_Span);
            end if;
         end loop;
      elsif UString_Value (Info.Kind) = "access" and then Info.Has_Target then
         return Field_Type
           (Resolve_Type (UString_Value (Info.Target), Type_Env, "", FT.Null_Span),
            Field_Name,
            Type_Env);
      end if;
      return Default_Integer;
   end Field_Type;

   function Expr_Type
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map) return GM.Type_Descriptor
   is
      Result      : GM.Type_Descriptor;
      Prefix_Type : GM.Type_Descriptor;
      Name        : FT.UString := FT.To_UString ("");
   begin
      if Expr = null then
         return Default_Integer;
      end if;

      case Expr.Kind is
         when CM.Expr_Ident =>
            Name := Expr.Name;
            if Var_Types.Contains (UString_Value (Name)) then
               return Var_Types.Element (UString_Value (Name));
            end if;
         when CM.Expr_Select =>
            if UString_Value (Expr.Selector) = "all" then
               return Access_Target_Type
                 (Expr_Type (Expr.Prefix, Var_Types, Functions, Type_Env),
                  Type_Env);
            elsif UString_Value (Expr.Selector) = "Access" then
               Result.Name :=
                 FT.To_UString
                   ("access constant "
                    & UString_Value
                        (Access_Target_Type
                           (Expr_Type (Expr.Prefix, Var_Types, Functions, Type_Env),
                            Type_Env).Name));
               Result.Kind := FT.To_UString ("access");
               Result.Has_Target := True;
               Result.Target :=
                 Access_Target_Type
                   (Expr_Type (Expr.Prefix, Var_Types, Functions, Type_Env),
                    Type_Env).Name;
               Result.Not_Null := True;
               Result.Anonymous := True;
               Result.Is_Constant := True;
               Result.Has_Access_Role := True;
               Result.Access_Role := FT.To_UString ("Observe");
               return Result;
            elsif UString_Value (Expr.Selector) in "First" | "Last" | "Length" then
               return Default_Integer;
            end if;

            Prefix_Type := Expr_Type (Expr.Prefix, Var_Types, Functions, Type_Env);
            return Field_Type (Prefix_Type, UString_Value (Expr.Selector), Type_Env);
         when CM.Expr_Resolved_Index =>
            Prefix_Type := Expr_Type (Expr.Prefix, Var_Types, Functions, Type_Env);
            if Prefix_Type.Has_Component_Type then
               return Resolve_Type
                 (UString_Value (Prefix_Type.Component_Type),
                  Type_Env,
                  "",
                  FT.Null_Span);
            end if;
         when CM.Expr_Conversion =>
            return Resolve_Type
              (Flatten_Name (Expr.Target), Type_Env, "", FT.Null_Span);
         when CM.Expr_Call =>
            Name := FT.To_UString (Flatten_Name (Expr.Callee));
            if Functions.Contains (UString_Value (Name)) then
               declare
                  Info : constant Function_Info :=
                    Functions.Element (UString_Value (Name));
               begin
                  if Info.Has_Return_Type then
                     return Info.Return_Type;
                  end if;
               end;
            elsif Var_Types.Contains (UString_Value (Name)) then
               return Var_Types.Element (UString_Value (Name));
            end if;
         when CM.Expr_Allocator =>
            if Expr.Value /= null then
               if Expr.Value.Kind = CM.Expr_Annotated and then Expr.Value.Target /= null then
                  Result.Name := FT.To_UString ("access " & Flatten_Name (Expr.Value.Target));
                  Result.Kind := FT.To_UString ("access");
                  Result.Has_Target := True;
                  Result.Target := FT.To_UString (Flatten_Name (Expr.Value.Target));
                  Result.Not_Null := True;
                  Result.Has_Access_Role := True;
                  Result.Access_Role := FT.To_UString ("Owner");
                  return Result;
               elsif Expr.Value.Kind = CM.Expr_Subtype_Indication then
                  Result.Name := FT.To_UString ("access " & UString_Value (Expr.Value.Name));
                  Result.Kind := FT.To_UString ("access");
                  Result.Has_Target := True;
                  Result.Target := Expr.Value.Name;
                  Result.Not_Null := True;
                  Result.Has_Access_Role := True;
                  Result.Access_Role := FT.To_UString ("Owner");
                  return Result;
               end if;
            end if;
         when CM.Expr_Bool =>
            return Default_Boolean;
         when others =>
            null;
      end case;
      return Default_Integer;
   end Expr_Type;

   function Set_Type
     (Expr : CM.Expr_Access;
      Info : GM.Type_Descriptor) return CM.Expr_Access is
   begin
      if Expr /= null then
         Expr.Type_Name := Info.Name;
      end if;
      return Expr;
   end Set_Type;

   function Resolve_Apply
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map) return CM.Expr_Access
   is
      Result      : CM.Expr_Access := new CM.Expr_Node'(Expr.all);
      Callee_Name : FT.UString := FT.To_UString ("");
      Prefix_Type : GM.Type_Descriptor;
   begin
      if Expr = null or else Expr.Kind /= CM.Expr_Apply then
         return Expr;
      end if;

      if Expr.Callee /= null and then Expr.Callee.Kind = CM.Expr_Ident then
         Callee_Name := Expr.Callee.Name;
         if Var_Types.Contains (UString_Value (Callee_Name))
           and then UString_Value
             (Var_Types.Element (UString_Value (Callee_Name)).Kind) = "array"
         then
            Result.Kind := CM.Expr_Resolved_Index;
            Result.Prefix := Expr.Callee;
            Result.Args := Expr.Args;
         elsif Functions.Contains (UString_Value (Callee_Name)) then
            Result.Kind := CM.Expr_Call;
            Result.Callee := Expr.Callee;
            Result.Args := Expr.Args;
         elsif Var_Types.Contains (UString_Value (Callee_Name))
           and then UString_Value
             (Var_Types.Element (UString_Value (Callee_Name)).Kind)
                    in "integer" | "subtype" | "record"
           and then Natural (Expr.Args.Length) = 1
         then
            Result.Kind := CM.Expr_Conversion;
            Result.Target := Expr.Callee;
            Result.Inner := Expr.Args (Expr.Args.First_Index);
         elsif UString_Value (Callee_Name) in "Integer" | "Natural"
           and then Natural (Expr.Args.Length) = 1
         then
            Result.Kind := CM.Expr_Conversion;
            Result.Target := Expr.Callee;
            Result.Inner := Expr.Args (Expr.Args.First_Index);
         else
            Result.Kind := CM.Expr_Call;
            Result.Callee := Expr.Callee;
            Result.Args := Expr.Args;
         end if;
      else
         Prefix_Type := Expr_Type (Expr.Callee, Var_Types, Functions, Type_Env);
         if UString_Value (Prefix_Type.Kind) = "array" then
            Result.Kind := CM.Expr_Resolved_Index;
            Result.Prefix := Expr.Callee;
            Result.Args := Expr.Args;
         else
            Result.Kind := CM.Expr_Call;
            Result.Callee := Expr.Callee;
            Result.Args := Expr.Args;
         end if;
      end if;
      return Result;
   end Resolve_Apply;

   function Normalize_Expr
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map) return CM.Expr_Access
   is
      Result   : CM.Expr_Access;
      Field    : CM.Aggregate_Field;
   begin
      if Expr = null then
         return null;
      end if;

      case Expr.Kind is
         when CM.Expr_Apply =>
            declare
               Resolved : constant CM.Expr_Access :=
                 Resolve_Apply (Expr, Var_Types, Functions, Type_Env);
            begin
               if Resolved.Kind = CM.Expr_Resolved_Index then
                  Result := new CM.Expr_Node'(Resolved.all);
                  Result.Prefix := Normalize_Expr (Resolved.Prefix, Var_Types, Functions, Type_Env);
                  Result.Args.Clear;
                  for Item of Resolved.Args loop
                     Result.Args.Append (Normalize_Expr (Item, Var_Types, Functions, Type_Env));
                  end loop;
               elsif Resolved.Kind = CM.Expr_Call then
                  Result := new CM.Expr_Node'(Resolved.all);
                  Result.Callee := Normalize_Expr (Resolved.Callee, Var_Types, Functions, Type_Env);
                  Result.Args.Clear;
                  for Item of Resolved.Args loop
                     Result.Args.Append (Normalize_Expr (Item, Var_Types, Functions, Type_Env));
                  end loop;
               else
                  Result := new CM.Expr_Node'(Resolved.all);
                  Result.Inner := Normalize_Expr (Resolved.Inner, Var_Types, Functions, Type_Env);
               end if;
            end;
         when CM.Expr_Select =>
            Result := new CM.Expr_Node'(Expr.all);
            Result.Prefix := Normalize_Expr (Expr.Prefix, Var_Types, Functions, Type_Env);
         when CM.Expr_Binary =>
            Result := new CM.Expr_Node'(Expr.all);
            Result.Left := Normalize_Expr (Expr.Left, Var_Types, Functions, Type_Env);
            Result.Right := Normalize_Expr (Expr.Right, Var_Types, Functions, Type_Env);
         when CM.Expr_Unary =>
            Result := new CM.Expr_Node'(Expr.all);
            Result.Inner := Normalize_Expr (Expr.Inner, Var_Types, Functions, Type_Env);
         when CM.Expr_Allocator =>
            Result := new CM.Expr_Node'(Expr.all);
            if Expr.Value /= null and then Expr.Value.Kind = CM.Expr_Annotated then
               Result.Value := new CM.Expr_Node'(Expr.Value.all);
               Result.Value.Inner :=
                 Normalize_Expr (Expr.Value.Inner, Var_Types, Functions, Type_Env);
            end if;
         when CM.Expr_Aggregate =>
            Result := new CM.Expr_Node'(Expr.all);
            Result.Fields.Clear;
            for Item of Expr.Fields loop
               Field := Item;
               Field.Expr := Normalize_Expr (Item.Expr, Var_Types, Functions, Type_Env);
               Result.Fields.Append (Field);
            end loop;
         when CM.Expr_Annotated =>
            Result := new CM.Expr_Node'(Expr.all);
            Result.Inner := Normalize_Expr (Expr.Inner, Var_Types, Functions, Type_Env);
         when others =>
            Result := new CM.Expr_Node'(Expr.all);
      end case;

      return Set_Type (Result, Expr_Type (Result, Var_Types, Functions, Type_Env));
   end Normalize_Expr;

   function Is_Assignable_Target (Expr : CM.Expr_Access) return Boolean is
   begin
      if Expr = null then
         return False;
      elsif Expr.Kind = CM.Expr_Ident or else Expr.Kind = CM.Expr_Resolved_Index then
         return True;
      elsif Expr.Kind = CM.Expr_Select then
         return UString_Value (Expr.Selector) not in "First" | "Last" | "Length" | "Access";
      end if;
      return False;
   end Is_Assignable_Target;

   function Resolve_Decl_Type
     (Decl      : CM.Object_Decl;
      Type_Env  : Type_Maps.Map;
      Path      : String) return GM.Type_Descriptor is
   begin
      return Resolve_Type_Spec (Decl.Decl_Type, Type_Env, Path);
   end Resolve_Decl_Type;

   function Normalize_Procedure_Call
     (Expr      : CM.Expr_Access;
      Functions : Function_Maps.Map;
      Path      : String) return CM.Expr_Access
   is
      Result : CM.Expr_Access := Expr;
      Name   : FT.UString := FT.To_UString ("");
   begin
      if Expr = null then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path,
               Span    => FT.Null_Span,
               Message => "expected assignment or procedure call"));
      elsif Expr.Kind = CM.Expr_Call then
         Name := FT.To_UString (Flatten_Name (Expr.Callee));
         if Functions.Contains (UString_Value (Name))
           and then UString_Value
             (Functions.Element (UString_Value (Name)).Kind) = "procedure"
         then
            return Expr;
         end if;
      elsif Expr.Kind = CM.Expr_Ident or else Expr.Kind = CM.Expr_Select then
         Name := FT.To_UString (Flatten_Name (Expr));
         if Functions.Contains (UString_Value (Name))
           and then UString_Value
             (Functions.Element (UString_Value (Name)).Kind) = "procedure"
         then
            Result := new CM.Expr_Node'(Expr.all);
            Result.Kind := CM.Expr_Call;
            Result.Callee := Expr;
            Result.Has_Call_Span := True;
            Result.Call_Span := Expr.Span;
            return Set_Type (Result, Default_Integer);
         end if;
      end if;

      Raise_Diag
        (CM.Source_Frontend_Error
           (Path    => Path,
            Span    => Expr.Span,
            Message => "expected assignment or procedure call"));
      return Expr;
   end Normalize_Procedure_Call;

   function Normalize_Statement
     (Stmt      : CM.Statement_Access;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Path      : String) return CM.Statement_Access
   is
      Result      : constant CM.Statement_Access := new CM.Statement'(Stmt.all);
      Local_Types : Type_Maps.Map := Var_Types;
      Loop_Type   : GM.Type_Descriptor;
      Decl_Type   : GM.Type_Descriptor;
   begin
      case Stmt.Kind is
         when CM.Stmt_Assign =>
            Result.Target := Normalize_Expr (Stmt.Target, Var_Types, Functions, Type_Env);
            if not Is_Assignable_Target (Result.Target) then
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path,
                     Span    => Result.Target.Span,
                     Message => "assignment target must be a writable name"));
            end if;
            Result.Value := Normalize_Expr (Stmt.Value, Var_Types, Functions, Type_Env);
         when CM.Stmt_Return =>
            if Stmt.Value /= null then
               Result.Value := Normalize_Expr (Stmt.Value, Var_Types, Functions, Type_Env);
            end if;
         when CM.Stmt_If =>
            Result.Condition := Normalize_Expr (Stmt.Condition, Var_Types, Functions, Type_Env);
            Result.Then_Stmts.Clear;
            for Item of Stmt.Then_Stmts loop
               Result.Then_Stmts.Append
                 (Normalize_Statement (Item, Var_Types, Functions, Type_Env, Path));
            end loop;
            Result.Elsifs.Clear;
            for Part of Stmt.Elsifs loop
               declare
                  New_Part : CM.Elsif_Part := Part;
               begin
                  New_Part.Condition :=
                    Normalize_Expr (Part.Condition, Var_Types, Functions, Type_Env);
                  New_Part.Statements.Clear;
                  for Item of Part.Statements loop
                     New_Part.Statements.Append
                       (Normalize_Statement (Item, Var_Types, Functions, Type_Env, Path));
                  end loop;
                  Result.Elsifs.Append (New_Part);
               end;
            end loop;
            if Stmt.Has_Else then
               Result.Else_Stmts.Clear;
               for Item of Stmt.Else_Stmts loop
                  Result.Else_Stmts.Append
                    (Normalize_Statement (Item, Var_Types, Functions, Type_Env, Path));
               end loop;
            end if;
         when CM.Stmt_While =>
            Result.Condition := Normalize_Expr (Stmt.Condition, Var_Types, Functions, Type_Env);
            Result.Body_Stmts.Clear;
            for Item of Stmt.Body_Stmts loop
               Result.Body_Stmts.Append
                 (Normalize_Statement (Item, Var_Types, Functions, Type_Env, Path));
            end loop;
         when CM.Stmt_For =>
            Result.Loop_Range := Stmt.Loop_Range;
            if Stmt.Loop_Range.Kind = CM.Range_Explicit then
               Result.Loop_Range.Low_Expr :=
                 Normalize_Expr (Stmt.Loop_Range.Low_Expr, Var_Types, Functions, Type_Env);
               Result.Loop_Range.High_Expr :=
                 Normalize_Expr (Stmt.Loop_Range.High_Expr, Var_Types, Functions, Type_Env);
               Loop_Type.Name := FT.To_UString ("Integer");
               Loop_Type.Kind := FT.To_UString ("integer");
            else
               Result.Loop_Range.Name_Expr :=
                 Normalize_Expr (Stmt.Loop_Range.Name_Expr, Var_Types, Functions, Type_Env);
               Loop_Type :=
                 Resolve_Type (Flatten_Name (Stmt.Loop_Range.Name_Expr), Type_Env, Path, Stmt.Span);
            end if;
            Local_Types.Include (UString_Value (Stmt.Loop_Var), Loop_Type);
            Result.Body_Stmts.Clear;
            for Item of Stmt.Body_Stmts loop
               Result.Body_Stmts.Append
                 (Normalize_Statement (Item, Local_Types, Functions, Type_Env, Path));
            end loop;
         when CM.Stmt_Block =>
            Result.Declarations.Clear;
            for Decl of Stmt.Declarations loop
               declare
                  New_Decl : CM.Object_Decl := Decl;
               begin
                  New_Decl.Type_Info := Resolve_Decl_Type (Decl, Local_Types, Path);
                  if Decl.Has_Initializer and then Decl.Initializer /= null then
                     New_Decl.Initializer :=
                       Normalize_Expr (Decl.Initializer, Local_Types, Functions, Type_Env);
                  end if;
                  Result.Declarations.Append (New_Decl);
                  Decl_Type := New_Decl.Type_Info;
                  for Name of Decl.Names loop
                     Local_Types.Include (UString_Value (Name), Decl_Type);
                  end loop;
               end;
            end loop;
            Result.Body_Stmts.Clear;
            for Item of Stmt.Body_Stmts loop
               Result.Body_Stmts.Append
                 (Normalize_Statement (Item, Local_Types, Functions, Type_Env, Path));
            end loop;
         when CM.Stmt_Call =>
            Result.Call :=
              Normalize_Procedure_Call
                (Normalize_Expr (Stmt.Call, Var_Types, Functions, Type_Env),
                 Functions,
                 Path);
         when others =>
            null;
      end case;

      return Result;
   end Normalize_Statement;

   function Resolve_Type_Declaration
     (Decl      : CM.Type_Decl;
      Type_Env  : in out Type_Maps.Map;
      Path      : String) return GM.Type_Descriptor
   is
      Result : GM.Type_Descriptor;
      Item   : GM.Type_Field;
   begin
      Result.Name := Decl.Name;
      case Decl.Kind is
         when CM.Type_Decl_Incomplete =>
            Result.Kind := FT.To_UString ("incomplete");
         when CM.Type_Decl_Integer =>
            Result.Kind := FT.To_UString ("integer");
            Result.Has_Low := True;
            Result.Low := Long_Long_Integer (Literal_Value (Decl.Low_Expr, Path));
            Result.Has_High := True;
            Result.High := Long_Long_Integer (Literal_Value (Decl.High_Expr, Path));
         when CM.Type_Decl_Constrained_Array | CM.Type_Decl_Unconstrained_Array =>
            Result.Kind := FT.To_UString ("array");
            for Index_Item of Decl.Indexes loop
               if Index_Item.Name_Expr /= null then
                  Result.Index_Types.Append
                    (FT.To_UString (Flatten_Name (Index_Item.Name_Expr)));
               end if;
            end loop;
            Result.Has_Component_Type := True;
            Result.Component_Type :=
              Resolve_Type_Spec (Decl.Component_Type, Type_Env, Path).Name;
            Result.Unconstrained := Decl.Kind = CM.Type_Decl_Unconstrained_Array;
         when CM.Type_Decl_Record =>
            Result.Kind := FT.To_UString ("record");
            for Field_Decl of Decl.Components loop
               for Name of Field_Decl.Names loop
                  Item.Name := Name;
                  Item.Type_Name := Resolve_Type_Spec (Field_Decl.Field_Type, Type_Env, Path).Name;
                  Result.Fields.Append (Item);
               end loop;
            end loop;
         when CM.Type_Decl_Access =>
            Result.Kind := FT.To_UString ("access");
            Result.Has_Target := True;
            Result.Target :=
              Resolve_Type (Flatten_Name (Decl.Access_Type.Target_Name), Type_Env, Path, Decl.Span).Name;
            Result.Not_Null := Decl.Access_Type.Not_Null;
            Result.Anonymous := False;
            Result.Is_All := Decl.Access_Type.Is_All;
            Result.Is_Constant := Decl.Access_Type.Is_Constant;
            Result.Has_Access_Role := True;
            Result.Access_Role :=
              FT.To_UString
                (Classify_Access_Role (False, Decl.Access_Type.Is_Constant, Decl.Access_Type.Is_All));
         when others =>
            Raise_Diag
              (CM.Unsupported_Source_Construct
                 (Path    => Path,
                  Span    => Decl.Span,
                  Message => "unsupported type definition in current PR05/PR06 check subset"));
      end case;
      Type_Env.Include (UString_Value (Result.Name), Result);
      return Result;
   end Resolve_Type_Declaration;

   function Register_Function
     (Decl      : CM.Subprogram_Body;
      Type_Env  : Type_Maps.Map;
      Path      : String) return Function_Info
   is
      Result : Function_Info;
      Symbol : CM.Symbol;
   begin
      Result.Name := Decl.Spec.Name;
      Result.Kind := Decl.Spec.Kind;
      Result.Span := Decl.Span;
      Result.Return_Is_Access_Def := Decl.Spec.Return_Is_Access_Def;
      for Param of Decl.Spec.Params loop
         declare
            Param_Type : constant GM.Type_Descriptor :=
              Resolve_Type_Spec (Param.Param_Type, Type_Env, Path);
         begin
            for Name of Param.Names loop
               Symbol.Name := Name;
               Symbol.Kind := FT.To_UString ("param");
               Symbol.Mode := Param.Mode;
               Symbol.Span := Param.Span;
               Symbol.Type_Info := Param_Type;
               Result.Params.Append (Symbol);
            end loop;
         end;
      end loop;
      if Decl.Spec.Has_Return_Type then
         Result.Has_Return_Type := True;
         Result.Return_Type := Resolve_Type_Spec (Decl.Spec.Return_Type, Type_Env, Path);
      end if;
      return Result;
   end Register_Function;

   function Resolve
     (Unit : CM.Parsed_Unit) return CM.Resolve_Result
   is
      Type_Env   : Type_Maps.Map;
      Functions  : Function_Maps.Map;
      Result     : CM.Resolved_Unit;
   begin
      Add_Builtins (Type_Env);
      Result.Path := Unit.Path;
      Result.Package_Name := Unit.Package_Name;

      for Item of Unit.Items loop
         case Item.Kind is
            when CM.Item_Type_Decl =>
               declare
                  Info : constant GM.Type_Descriptor :=
                    Resolve_Type_Declaration
                      (Item.Type_Data,
                       Type_Env,
                       UString_Value (Unit.Path));
               begin
                  if not Is_Builtin_Name (UString_Value (Info.Name)) then
                     Result.Types.Append (Info);
                  end if;
               end;
            when CM.Item_Subtype_Decl =>
               declare
                  Base : constant GM.Type_Descriptor :=
                    Resolve_Type_Spec
                      (Item.Sub_Data.Subtype_Mark,
                       Type_Env,
                       UString_Value (Unit.Path));
                  Info : GM.Type_Descriptor;
               begin
                  Info.Name := Item.Sub_Data.Name;
                  Info.Kind := FT.To_UString ("subtype");
                  if Base.Has_Low then
                     Info.Has_Low := True;
                     Info.Low := Base.Low;
                  end if;
                  if Base.Has_High then
                     Info.Has_High := True;
                     Info.High := Base.High;
                  end if;
                  Info.Has_Base := True;
                  Info.Base := Base.Name;
                  Type_Env.Include (UString_Value (Info.Name), Info);
                  Result.Types.Append (Info);
               end;
            when CM.Item_Subprogram =>
               declare
                  Info : constant Function_Info :=
                    Register_Function
                      (Item.Subp_Data,
                       Type_Env,
                       UString_Value (Unit.Path));
               begin
                  Functions.Include (UString_Value (Info.Name), Info);
               end;
            when others =>
               null;
         end case;
      end loop;

      for Item of Unit.Items loop
         if Item.Kind = CM.Item_Subprogram then
            declare
               Info         : constant Function_Info :=
                 Functions.Element (UString_Value (Item.Subp_Data.Spec.Name));
               Subprogram   : CM.Resolved_Subprogram;
               Visible      : Type_Maps.Map := Type_Env;
               Decl_Type    : GM.Type_Descriptor;
               Local_Decl   : CM.Resolved_Object_Decl;
            begin
               Subprogram.Name := Info.Name;
               Subprogram.Kind := Info.Kind;
               Subprogram.Params := Info.Params;
               Subprogram.Has_Return_Type := Info.Has_Return_Type;
               Subprogram.Return_Type := Info.Return_Type;
               Subprogram.Return_Is_Access_Def := Info.Return_Is_Access_Def;
               Subprogram.Span := Info.Span;

               for Param of Info.Params loop
                  Visible.Include (UString_Value (Param.Name), Param.Type_Info);
               end loop;

               for Decl of Item.Subp_Data.Declarations loop
                  Decl_Type := Resolve_Decl_Type (Decl, Visible, UString_Value (Unit.Path));
                  Local_Decl.Names := Decl.Names;
                  Local_Decl.Type_Info := Decl_Type;
                  Local_Decl.Has_Initializer := Decl.Has_Initializer;
                  Local_Decl.Span := Decl.Span;
                  Local_Decl.Initializer := null;
                  if Decl.Has_Initializer and then Decl.Initializer /= null then
                     Local_Decl.Initializer :=
                       Normalize_Expr (Decl.Initializer, Visible, Functions, Type_Env);
                  end if;
                  Subprogram.Declarations.Append (Local_Decl);
                  for Name of Decl.Names loop
                     Visible.Include (UString_Value (Name), Decl_Type);
                  end loop;
               end loop;

               for Stmt of Item.Subp_Data.Statements loop
                  Subprogram.Statements.Append
                    (Normalize_Statement
                       (Stmt,
                        Visible,
                        Functions,
                        Type_Env,
                        UString_Value (Unit.Path)));
               end loop;

               Result.Subprograms.Append (Subprogram);
            end;
         end if;
      end loop;

      return (Success => True, Unit => Result);
   exception
      when Resolve_Failure =>
         return (Success => False, Diagnostic => Raised_Diag);
   end Resolve;
end Safe_Frontend.Check_Resolve;
