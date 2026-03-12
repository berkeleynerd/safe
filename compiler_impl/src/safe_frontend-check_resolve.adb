with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Strings.Hash;
with System;
with Safe_Frontend.Mir_Model;
with Safe_Frontend.Types;

package body Safe_Frontend.Check_Resolve is
   package FT renames Safe_Frontend.Types;
   package GM renames Safe_Frontend.Mir_Model;

   use type CM.Expr_Access;
   use type CM.Expr_Kind;
   use type CM.Discrete_Range_Kind;
   use type CM.Package_Item_Kind;
   use type CM.Select_Arm_Kind;
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

   function Make_Float_Builtin (Name : String) return GM.Type_Descriptor is
      Result : GM.Type_Descriptor;
   begin
      Result.Name := FT.To_UString (Name);
      Result.Kind := FT.To_UString ("float");
      return Result;
   end Make_Float_Builtin;

   procedure Add_Builtins (Type_Env : in out Type_Maps.Map) is
   begin
      Type_Env.Include ("Integer", Make_Builtin ("Integer", -(2 ** 63), (2 ** 63) - 1));
      Type_Env.Include ("Natural", Make_Builtin ("Natural", 0, (2 ** 63) - 1));
      Type_Env.Include ("Boolean", Make_Builtin ("Boolean", 0, 1));
      Type_Env.Include ("Float", Make_Float_Builtin ("Float"));
      Type_Env.Include ("Long_Float", Make_Float_Builtin ("Long_Float"));
      Type_Env.Include ("Duration", Make_Float_Builtin ("Duration"));
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

   function Default_Float return GM.Type_Descriptor is
   begin
      return Make_Float_Builtin ("Long_Float");
   end Default_Float;

   function Default_Duration return GM.Type_Descriptor is
   begin
      return Make_Float_Builtin ("Duration");
   end Default_Duration;

   function Default_Task_Priority return Long_Long_Integer is
   begin
      return Long_Long_Integer (System.Default_Priority);
   end Default_Task_Priority;

   function Min_Task_Priority return Long_Long_Integer is
   begin
      return Long_Long_Integer (System.Any_Priority'First);
   end Min_Task_Priority;

   function Max_Task_Priority return Long_Long_Integer is
   begin
      return Long_Long_Integer (System.Any_Priority'Last);
   end Max_Task_Priority;

   function Base_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return GM.Type_Descriptor
   is
      Result : GM.Type_Descriptor := Info;
      Name   : String := UString_Value (Result.Name);
   begin
      while Result.Has_Base and then Type_Env.Contains (UString_Value (Result.Base)) loop
         Result := Type_Env.Element (UString_Value (Result.Base));
         Name := UString_Value (Result.Name);
         exit when Name = "";
      end loop;
      return Result;
   end Base_Type;

   function Is_Integerish
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean;

   function Equivalent_Type
     (Left     : GM.Type_Descriptor;
      Right    : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean
   is
      Left_Base  : constant GM.Type_Descriptor := Base_Type (Left, Type_Env);
      Right_Base : constant GM.Type_Descriptor := Base_Type (Right, Type_Env);
   begin
      return UString_Value (Left.Name) = UString_Value (Right.Name)
        or else UString_Value (Left_Base.Name) = UString_Value (Right_Base.Name);
   end Equivalent_Type;

   function Compatible_Type
     (Left     : GM.Type_Descriptor;
      Right    : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean
   is
      Left_Base  : constant GM.Type_Descriptor := Base_Type (Left, Type_Env);
      Right_Base : constant GM.Type_Descriptor := Base_Type (Right, Type_Env);
      Left_Kind  : constant String := FT.Lowercase (UString_Value (Left_Base.Kind));
      Right_Kind : constant String := FT.Lowercase (UString_Value (Right_Base.Kind));
   begin
      return Equivalent_Type (Left, Right, Type_Env)
        or else (Is_Integerish (Left, Type_Env) and then Is_Integerish (Right, Type_Env))
        or else (Left_Kind = "float" and then Right_Kind = "float");
   end Compatible_Type;

   function Is_Boolean_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean is
   begin
      return UString_Value (Base_Type (Info, Type_Env).Name) = "Boolean";
   end Is_Boolean_Type;

   function Is_Duration_Compatible
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean
   is
      Base : constant GM.Type_Descriptor := Base_Type (Info, Type_Env);
      Kind : constant String := FT.Lowercase (UString_Value (Base.Kind));
   begin
      return UString_Value (Base.Name) = "Duration"
        or else Kind in "integer" | "float" | "subtype";
   end Is_Duration_Compatible;

   function Is_Integerish
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean
   is
      Base : constant GM.Type_Descriptor := Base_Type (Info, Type_Env);
      Kind : constant String := FT.Lowercase (UString_Value (Base.Kind));
   begin
      return Kind in "integer" | "subtype";
   end Is_Integerish;

   function Is_Definite_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean
   is
      Base : constant GM.Type_Descriptor := Base_Type (Info, Type_Env);
      Kind : constant String := FT.Lowercase (UString_Value (Base.Kind));
   begin
      if Kind = "incomplete" then
         return False;
      elsif Kind = "array" then
         return not Base.Unconstrained;
      elsif Kind = "record" and then Base.Has_Discriminant then
         return Base.Has_Discriminant_Default;
      end if;
      return True;
   end Is_Definite_Type;

   function Contains_Dot (Name : String) return Boolean is
   begin
      for Ch of Name loop
         if Ch = '.' then
            return True;
         end if;
      end loop;
      return False;
   end Contains_Dot;

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
      return Name in "Integer" | "Natural" | "Boolean" | "Float" | "Long_Float" | "Duration";
   end Is_Builtin_Name;

   function Expr_Text (Expr : CM.Expr_Access) return String;

   function Expr_Text (Expr : CM.Expr_Access) return String is
   begin
      if Expr = null then
         return "";
      end if;

      case Expr.Kind is
         when CM.Expr_Int | CM.Expr_Real =>
            if UString_Value (Expr.Text)'Length > 0 then
               return UString_Value (Expr.Text);
            end if;
         when CM.Expr_Bool =>
            return (if Expr.Bool_Value then "True" else "False");
         when CM.Expr_Ident =>
            return UString_Value (Expr.Name);
         when CM.Expr_Select =>
            return Expr_Text (Expr.Prefix) & "." & UString_Value (Expr.Selector);
         when CM.Expr_Unary =>
            return UString_Value (Expr.Operator) & Expr_Text (Expr.Inner);
         when CM.Expr_Binary =>
            return Expr_Text (Expr.Left) & " " & UString_Value (Expr.Operator) & " " & Expr_Text (Expr.Right);
         when others =>
            null;
      end case;

      return CM.Flatten_Name (Expr);
   end Expr_Text;

   function Bool_Literal_Value
     (Expr : CM.Expr_Access;
      Path : String) return Boolean
   is
   begin
      if Expr /= null and then Expr.Kind = CM.Expr_Bool then
         return Expr.Bool_Value;
      end if;

      Raise_Diag
        (CM.Source_Frontend_Error
           (Path    => Path,
            Span    => (if Expr = null then FT.Null_Span else Expr.Span),
            Message => "boolean discriminant defaults must be boolean literals"));
      return False;
   end Bool_Literal_Value;

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

      if FT.Lowercase (Name) = "exception" then
         Raise_Diag
           (CM.Unsupported_Source_Construct
              (Path    => Path,
               Span    => Span,
               Message =>
                 "exception declarations and handling are outside the current PR05/PR06 check subset"));
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
         if Info.Has_Discriminant and then UString_Value (Info.Discriminant_Name) = Field_Name then
            return Resolve_Type (UString_Value (Info.Discriminant_Type), Type_Env, "", FT.Null_Span);
         end if;
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
         when CM.Expr_Real =>
            if UString_Value (Expr.Type_Name)'Length > 0 and then Type_Env.Contains (UString_Value (Expr.Type_Name)) then
               return Type_Env.Element (UString_Value (Expr.Type_Name));
            end if;
            return Default_Float;
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
            elsif UString_Value (Name) = "Long_Float.Copy_Sign" then
               return Resolve_Type ("Long_Float", Type_Env, "", FT.Null_Span);
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
         when CM.Expr_Unary =>
            if UString_Value (Expr.Operator) = "not" then
               return Default_Boolean;
            end if;
            return Expr_Type (Expr.Inner, Var_Types, Functions, Type_Env);
         when CM.Expr_Binary =>
            if UString_Value (Expr.Operator) in "==" | "!=" | "<" | "<=" | ">" | ">=" | "and then" then
               return Default_Boolean;
            end if;
            declare
               Left_Type  : constant GM.Type_Descriptor := Expr_Type (Expr.Left, Var_Types, Functions, Type_Env);
               Right_Type : constant GM.Type_Descriptor := Expr_Type (Expr.Right, Var_Types, Functions, Type_Env);
            begin
               if UString_Value (Left_Type.Kind) = "float" or else UString_Value (Right_Type.Kind) = "float" then
                  if UString_Value (Left_Type.Kind) = "float" then
                     return Left_Type;
                  end if;
                  return Right_Type;
               end if;
            end;
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
                    in "integer" | "subtype" | "record" | "float"
           and then Natural (Expr.Args.Length) = 1
         then
            Result.Kind := CM.Expr_Conversion;
            Result.Target := Expr.Callee;
            Result.Inner := Expr.Args (Expr.Args.First_Index);
         elsif UString_Value (Callee_Name) in "Integer" | "Natural" | "Float" | "Long_Float"
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

   function Channel_Element_Type
     (Expr        : CM.Expr_Access;
      Channel_Env : Type_Maps.Map;
      Path        : String) return GM.Type_Descriptor
   is
      Name : constant String := Flatten_Name (Expr);
   begin
      if Name = "" then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path,
               Span    => (if Expr = null then FT.Null_Span else Expr.Span),
               Message => "channel reference must be a channel name"));
      end if;

      if Contains_Dot (Name) then
         Raise_Diag
           (CM.Unsupported_Source_Construct
              (Path    => Path,
               Span    => Expr.Span,
               Message =>
                 "package-qualified channel references are outside the current PR08.1 concurrency subset"));
      elsif not Channel_Env.Contains (Name) then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path,
               Span    => Expr.Span,
               Message => "unknown channel `" & Name & "`"));
      end if;

      return Channel_Env.Element (Name);
   end Channel_Element_Type;

   function Normalize_Object_Decl
     (Decl      : CM.Object_Decl;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Path      : String) return CM.Object_Decl
   is
      Result : CM.Object_Decl := Decl;
   begin
      Result.Type_Info := Resolve_Decl_Type (Decl, Var_Types, Path);
      if Decl.Has_Initializer and then Decl.Initializer /= null then
         Result.Initializer := Normalize_Expr (Decl.Initializer, Var_Types, Functions, Type_Env);
      end if;
      return Result;
   end Normalize_Object_Decl;

   function Normalize_Statement
     (Stmt        : CM.Statement_Access;
      Var_Types   : Type_Maps.Map;
      Functions   : Function_Maps.Map;
      Type_Env    : Type_Maps.Map;
      Channel_Env : Type_Maps.Map;
      Path        : String) return CM.Statement_Access;

   function Normalize_Statement_List
     (Statements  : CM.Statement_Access_Vectors.Vector;
      Var_Types   : Type_Maps.Map;
      Functions   : Function_Maps.Map;
      Type_Env    : Type_Maps.Map;
      Channel_Env : Type_Maps.Map;
      Path        : String) return CM.Statement_Access_Vectors.Vector
   is
      Result      : CM.Statement_Access_Vectors.Vector;
      Local_Types : Type_Maps.Map := Var_Types;
   begin
      for Item of Statements loop
         declare
            Normalized : constant CM.Statement_Access :=
              Normalize_Statement
                (Item,
                 Local_Types,
                 Functions,
                 Type_Env,
                 Channel_Env,
                 Path);
         begin
            Result.Append (Normalized);
            if Normalized.Kind = CM.Stmt_Object_Decl then
               for Name of Normalized.Decl.Names loop
                  Local_Types.Include (UString_Value (Name), Normalized.Decl.Type_Info);
               end loop;
            end if;
         end;
      end loop;
      return Result;
   end Normalize_Statement_List;

   function Normalize_Statement
     (Stmt        : CM.Statement_Access;
      Var_Types   : Type_Maps.Map;
      Functions   : Function_Maps.Map;
      Type_Env    : Type_Maps.Map;
      Channel_Env : Type_Maps.Map;
      Path        : String) return CM.Statement_Access
   is
      Result         : constant CM.Statement_Access := new CM.Statement'(Stmt.all);
      Local_Types    : Type_Maps.Map := Var_Types;
      Loop_Type      : GM.Type_Descriptor;
      Decl_Type      : GM.Type_Descriptor;
      Channel_Type   : GM.Type_Descriptor;
      Success_Type   : GM.Type_Descriptor;
      Target_Type    : GM.Type_Descriptor;
   begin
      case Stmt.Kind is
         when CM.Stmt_Object_Decl =>
            Result.Decl := Normalize_Object_Decl (Stmt.Decl, Var_Types, Functions, Type_Env, Path);

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
            Result.Then_Stmts :=
              Normalize_Statement_List
                (Stmt.Then_Stmts, Var_Types, Functions, Type_Env, Channel_Env, Path);
            Result.Elsifs.Clear;
            for Part of Stmt.Elsifs loop
               declare
                  New_Part : CM.Elsif_Part := Part;
               begin
                  New_Part.Condition :=
                    Normalize_Expr (Part.Condition, Var_Types, Functions, Type_Env);
                  New_Part.Statements :=
                    Normalize_Statement_List
                      (Part.Statements, Var_Types, Functions, Type_Env, Channel_Env, Path);
                  Result.Elsifs.Append (New_Part);
               end;
            end loop;
            if Stmt.Has_Else then
               Result.Else_Stmts :=
                 Normalize_Statement_List
                   (Stmt.Else_Stmts, Var_Types, Functions, Type_Env, Channel_Env, Path);
            end if;

         when CM.Stmt_While =>
            Result.Condition := Normalize_Expr (Stmt.Condition, Var_Types, Functions, Type_Env);
            Result.Body_Stmts :=
              Normalize_Statement_List
                (Stmt.Body_Stmts, Var_Types, Functions, Type_Env, Channel_Env, Path);

         when CM.Stmt_Loop =>
            Result.Body_Stmts :=
              Normalize_Statement_List
                (Stmt.Body_Stmts, Var_Types, Functions, Type_Env, Channel_Env, Path);

         when CM.Stmt_Exit =>
            if Stmt.Condition /= null then
               Result.Condition := Normalize_Expr (Stmt.Condition, Var_Types, Functions, Type_Env);
            end if;

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
            Result.Body_Stmts :=
              Normalize_Statement_List
                (Stmt.Body_Stmts, Local_Types, Functions, Type_Env, Channel_Env, Path);

         when CM.Stmt_Block =>
            Result.Declarations.Clear;
            for Decl of Stmt.Declarations loop
               declare
                  New_Decl : constant CM.Object_Decl :=
                    Normalize_Object_Decl (Decl, Local_Types, Functions, Type_Env, Path);
               begin
                  Result.Declarations.Append (New_Decl);
                  Decl_Type := New_Decl.Type_Info;
                  for Name of Decl.Names loop
                     Local_Types.Include (UString_Value (Name), Decl_Type);
                  end loop;
               end;
            end loop;
            Result.Body_Stmts :=
              Normalize_Statement_List
                (Stmt.Body_Stmts, Local_Types, Functions, Type_Env, Channel_Env, Path);

         when CM.Stmt_Call =>
            Result.Call :=
              Normalize_Procedure_Call
                (Normalize_Expr (Stmt.Call, Var_Types, Functions, Type_Env),
                 Functions,
                 Path);

         when CM.Stmt_Send | CM.Stmt_Try_Send =>
            Result.Channel_Name :=
              Normalize_Expr (Stmt.Channel_Name, Var_Types, Functions, Type_Env);
            Result.Value := Normalize_Expr (Stmt.Value, Var_Types, Functions, Type_Env);
            Channel_Type := Channel_Element_Type (Result.Channel_Name, Channel_Env, Path);
            if not Compatible_Type
              (Expr_Type (Result.Value, Var_Types, Functions, Type_Env),
               Channel_Type,
               Type_Env)
            then
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path,
                     Span    => Result.Value.Span,
                     Message => "channel send expression type does not match channel element type"));
            end if;
            if Stmt.Kind = CM.Stmt_Try_Send then
               Result.Success_Var :=
                 Normalize_Expr (Stmt.Success_Var, Var_Types, Functions, Type_Env);
               if not Is_Assignable_Target (Result.Success_Var) then
                  Raise_Diag
                    (CM.Source_Frontend_Error
                       (Path    => Path,
                        Span    => Result.Success_Var.Span,
                        Message => "try_send success variable must be a writable name"));
               end if;
               Success_Type := Expr_Type (Result.Success_Var, Var_Types, Functions, Type_Env);
               if not Is_Boolean_Type (Success_Type, Type_Env) then
                  Raise_Diag
                    (CM.Source_Frontend_Error
                       (Path    => Path,
                        Span    => Result.Success_Var.Span,
                        Message => "try_send success variable must have type Boolean"));
               end if;
            end if;

         when CM.Stmt_Receive | CM.Stmt_Try_Receive =>
            Result.Channel_Name :=
              Normalize_Expr (Stmt.Channel_Name, Var_Types, Functions, Type_Env);
            Result.Target := Normalize_Expr (Stmt.Target, Var_Types, Functions, Type_Env);
            if not Is_Assignable_Target (Result.Target) then
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path,
                     Span    => Result.Target.Span,
                     Message => "receive target must be a writable name"));
            end if;
            Channel_Type := Channel_Element_Type (Result.Channel_Name, Channel_Env, Path);
            Target_Type := Expr_Type (Result.Target, Var_Types, Functions, Type_Env);
            if not Compatible_Type (Target_Type, Channel_Type, Type_Env) then
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path,
                     Span    => Result.Target.Span,
                     Message => "channel receive target type does not match channel element type"));
            end if;
            if Stmt.Kind = CM.Stmt_Try_Receive then
               Result.Success_Var :=
                 Normalize_Expr (Stmt.Success_Var, Var_Types, Functions, Type_Env);
               if not Is_Assignable_Target (Result.Success_Var) then
                  Raise_Diag
                    (CM.Source_Frontend_Error
                       (Path    => Path,
                        Span    => Result.Success_Var.Span,
                        Message => "try_receive success variable must be a writable name"));
               end if;
               Success_Type := Expr_Type (Result.Success_Var, Var_Types, Functions, Type_Env);
               if not Is_Boolean_Type (Success_Type, Type_Env) then
                  Raise_Diag
                    (CM.Source_Frontend_Error
                       (Path    => Path,
                        Span    => Result.Success_Var.Span,
                        Message => "try_receive success variable must have type Boolean"));
               end if;
            end if;

         when CM.Stmt_Delay =>
            Result.Value := Normalize_Expr (Stmt.Value, Var_Types, Functions, Type_Env);
            if not Is_Duration_Compatible
              (Expr_Type (Result.Value, Var_Types, Functions, Type_Env), Type_Env)
            then
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path,
                     Span    => Result.Value.Span,
                     Message => "relative delay expression must be duration-compatible"));
            end if;

         when CM.Stmt_Select =>
            declare
               Channel_Arms : Natural := 0;
               Delay_Arms   : Natural := 0;
            begin
               Result.Arms.Clear;
               for Arm of Stmt.Arms loop
                  declare
                     New_Arm    : CM.Select_Arm := Arm;
                     Arm_Types  : Type_Maps.Map := Var_Types;
                  begin
                     case Arm.Kind is
                        when CM.Select_Arm_Channel =>
                           Channel_Arms := Channel_Arms + 1;
                           New_Arm.Channel_Data.Channel_Name :=
                             Normalize_Expr
                               (Arm.Channel_Data.Channel_Name,
                                Var_Types,
                                Functions,
                                Type_Env);
                           Channel_Type :=
                             Channel_Element_Type
                               (New_Arm.Channel_Data.Channel_Name,
                                Channel_Env,
                                Path);
                           New_Arm.Channel_Data.Type_Info :=
                             Resolve_Type_Spec
                               (Arm.Channel_Data.Subtype_Mark, Type_Env, Path);
                           if not Compatible_Type
                             (New_Arm.Channel_Data.Type_Info,
                              Channel_Type,
                              Type_Env)
                           then
                              Raise_Diag
                                (CM.Source_Frontend_Error
                                   (Path    => Path,
                                    Span    => Arm.Channel_Data.Subtype_Mark.Span,
                                    Message =>
                                      "select arm binding type does not match channel element type"));
                           end if;
                           Arm_Types.Include
                             (UString_Value (Arm.Channel_Data.Variable_Name),
                              New_Arm.Channel_Data.Type_Info);
                           New_Arm.Channel_Data.Statements :=
                             Normalize_Statement_List
                               (Arm.Channel_Data.Statements,
                                Arm_Types,
                                Functions,
                                Type_Env,
                                Channel_Env,
                                Path);
                        when CM.Select_Arm_Delay =>
                           Delay_Arms := Delay_Arms + 1;
                           New_Arm.Delay_Data.Duration_Expr :=
                             Normalize_Expr
                               (Arm.Delay_Data.Duration_Expr,
                                Var_Types,
                                Functions,
                                Type_Env);
                           if not Is_Duration_Compatible
                             (Expr_Type
                                (New_Arm.Delay_Data.Duration_Expr,
                                 Var_Types,
                                 Functions,
                                 Type_Env),
                              Type_Env)
                           then
                              Raise_Diag
                                (CM.Source_Frontend_Error
                                   (Path    => Path,
                                    Span    => New_Arm.Delay_Data.Duration_Expr.Span,
                                    Message => "select delay arm must be duration-compatible"));
                           end if;
                           New_Arm.Delay_Data.Statements :=
                             Normalize_Statement_List
                               (Arm.Delay_Data.Statements,
                                Var_Types,
                                Functions,
                                Type_Env,
                                Channel_Env,
                                Path);
                        when others =>
                           null;
                     end case;
                     Result.Arms.Append (New_Arm);
                  end;
               end loop;

               if Channel_Arms = 0 then
                  Raise_Diag
                    (CM.Source_Frontend_Error
                       (Path    => Path,
                        Span    => Stmt.Span,
                        Message => "select must contain at least one channel arm"));
               elsif Delay_Arms > 1 then
                  Raise_Diag
                    (CM.Source_Frontend_Error
                       (Path    => Path,
                        Span    => Stmt.Span,
                        Message => "select may contain at most one delay arm"));
               end if;
            end;

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
         when CM.Type_Decl_Float =>
            Result.Kind := FT.To_UString ("float");
            Result.Has_Digits_Text := True;
            Result.Digits_Text := FT.To_UString (Expr_Text (Decl.Digits_Expr));
            Result.Has_Float_Low_Text := True;
            Result.Float_Low_Text := FT.To_UString (Expr_Text (Decl.Low_Expr));
            Result.Has_Float_High_Text := True;
            Result.Float_High_Text := FT.To_UString (Expr_Text (Decl.High_Expr));
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
            if Decl.Has_Discriminant then
               Result.Has_Discriminant := True;
               Result.Discriminant_Name := Decl.Discriminant.Name;
               Result.Discriminant_Type :=
                 Resolve_Type_Spec (Decl.Discriminant.Disc_Type, Type_Env, Path).Name;
               if Decl.Discriminant.Has_Default then
                  Result.Has_Discriminant_Default := True;
                  Result.Discriminant_Default_Bool :=
                    Bool_Literal_Value (Decl.Discriminant.Default_Expr, Path);
               end if;
            end if;
            for Field_Decl of Decl.Components loop
               for Name of Field_Decl.Names loop
                  Item.Name := Name;
                  Item.Type_Name := Resolve_Type_Spec (Field_Decl.Field_Type, Type_Env, Path).Name;
                  Result.Fields.Append (Item);
               end loop;
            end loop;
            if not Decl.Variants.Is_Empty then
               for Alternative of Decl.Variants loop
                  for Field_Decl of Alternative.Components loop
                     for Name of Field_Decl.Names loop
                        Item.Name := Name;
                        Item.Type_Name := Resolve_Type_Spec (Field_Decl.Field_Type, Type_Env, Path).Name;
                        Result.Fields.Append (Item);
                        declare
                           Variant_Field : GM.Variant_Field;
                        begin
                           Variant_Field.Name := Name;
                           Variant_Field.Type_Name := Item.Type_Name;
                           Variant_Field.When_True := Alternative.When_Value;
                           Result.Variant_Fields.Append (Variant_Field);
                        end;
                     end loop;
                  end loop;
               end loop;
            end if;
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

   function Resolve_Channel_Declaration
     (Decl     : CM.Channel_Decl;
      Type_Env : Type_Maps.Map;
      Path     : String) return CM.Resolved_Channel_Decl
   is
      Result    : CM.Resolved_Channel_Decl;
      Type_Info : constant GM.Type_Descriptor :=
        Resolve_Type_Spec (Decl.Element_Type, Type_Env, Path);
   begin
      if not Is_Definite_Type (Type_Info, Type_Env) then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path,
               Span    => Decl.Element_Type.Span,
               Message => "channel element type must be definite"));
      end if;

      Result.Is_Public := Decl.Is_Public;
      Result.Name := Decl.Name;
      Result.Element_Type := Type_Info;
      Result.Capacity := Long_Long_Integer (Literal_Value (Decl.Capacity, Path));
      if Result.Capacity <= 0 then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path,
               Span    => Decl.Capacity.Span,
               Message => "channel capacity must be positive"));
      end if;
      Result.Span := Decl.Span;
      return Result;
   end Resolve_Channel_Declaration;

   procedure Validate_Task_Nontermination
     (Statements  : CM.Statement_Access_Vectors.Vector;
      Path        : String;
      Task_Name   : String;
      Loop_Depth  : Natural := 0)
   is
   begin
      for Stmt of Statements loop
         case Stmt.Kind is
            when CM.Stmt_Return =>
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path,
                     Span    => Stmt.Span,
                     Message => "task `" & Task_Name & "` must not contain return statements"));
            when CM.Stmt_Exit =>
               if Loop_Depth <= 1 then
                  Raise_Diag
                    (CM.Source_Frontend_Error
                       (Path    => Path,
                        Span    => Stmt.Span,
                        Message => "task `" & Task_Name & "` must not exit its outer loop"));
               end if;
            when CM.Stmt_If =>
               Validate_Task_Nontermination
                 (Stmt.Then_Stmts, Path, Task_Name, Loop_Depth);
               for Part of Stmt.Elsifs loop
                  Validate_Task_Nontermination
                    (Part.Statements, Path, Task_Name, Loop_Depth);
               end loop;
               if Stmt.Has_Else then
                  Validate_Task_Nontermination
                    (Stmt.Else_Stmts, Path, Task_Name, Loop_Depth);
               end if;
            when CM.Stmt_While | CM.Stmt_For | CM.Stmt_Loop =>
               Validate_Task_Nontermination
                 (Stmt.Body_Stmts, Path, Task_Name, Loop_Depth + 1);
            when CM.Stmt_Block =>
               Validate_Task_Nontermination
                 (Stmt.Body_Stmts, Path, Task_Name, Loop_Depth);
            when CM.Stmt_Select =>
               for Arm of Stmt.Arms loop
                  case Arm.Kind is
                     when CM.Select_Arm_Channel =>
                        Validate_Task_Nontermination
                          (Arm.Channel_Data.Statements, Path, Task_Name, Loop_Depth);
                     when CM.Select_Arm_Delay =>
                        Validate_Task_Nontermination
                          (Arm.Delay_Data.Statements, Path, Task_Name, Loop_Depth);
                     when others =>
                        null;
                  end case;
               end loop;
            when others =>
               null;
         end case;
      end loop;
   end Validate_Task_Nontermination;

   function Resolve
     (Unit : CM.Parsed_Unit) return CM.Resolve_Result
   is
      Type_Env     : Type_Maps.Map;
      Functions    : Function_Maps.Map;
      Package_Vars : Type_Maps.Map;
      Channel_Env  : Type_Maps.Map;
      Result       : CM.Resolved_Unit;
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
         if Item.Kind = CM.Item_Channel then
            declare
               Channel_Decl : constant CM.Resolved_Channel_Decl :=
                 Resolve_Channel_Declaration
                   (Item.Chan_Data,
                    Type_Env,
                    UString_Value (Unit.Path));
            begin
               Result.Channels.Append (Channel_Decl);
               Channel_Env.Include
                 (UString_Value (Channel_Decl.Name), Channel_Decl.Element_Type);
            end;
         end if;
      end loop;

      Package_Vars := Type_Env;
      for Item of Unit.Items loop
         if Item.Kind = CM.Item_Object_Decl then
            declare
               Decl_Type  : constant GM.Type_Descriptor :=
                 Resolve_Decl_Type (Item.Obj_Data, Package_Vars, UString_Value (Unit.Path));
               Local_Decl : CM.Resolved_Object_Decl;
            begin
               Local_Decl.Names := Item.Obj_Data.Names;
               Local_Decl.Type_Info := Decl_Type;
               Local_Decl.Has_Initializer := Item.Obj_Data.Has_Initializer;
               Local_Decl.Span := Item.Obj_Data.Span;
               Local_Decl.Initializer := null;
               if Item.Obj_Data.Has_Initializer and then Item.Obj_Data.Initializer /= null then
                  Local_Decl.Initializer :=
                    Normalize_Expr
                      (Item.Obj_Data.Initializer,
                       Package_Vars,
                       Functions,
                       Type_Env);
               end if;
               Result.Objects.Append (Local_Decl);
               for Name of Item.Obj_Data.Names loop
                  Package_Vars.Include (UString_Value (Name), Decl_Type);
               end loop;
            end;
         end if;
      end loop;

      for Item of Unit.Items loop
         if Item.Kind = CM.Item_Subprogram then
            declare
               Info         : constant Function_Info :=
                 Functions.Element (UString_Value (Item.Subp_Data.Spec.Name));
               Subprogram   : CM.Resolved_Subprogram;
               Visible      : Type_Maps.Map := Package_Vars;
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

               Subprogram.Statements :=
                 Normalize_Statement_List
                   (Item.Subp_Data.Statements,
                    Visible,
                    Functions,
                    Type_Env,
                    Channel_Env,
                    UString_Value (Unit.Path));

               Result.Subprograms.Append (Subprogram);
            end;
         elsif Item.Kind = CM.Item_Task then
            declare
               Visible        : Type_Maps.Map := Package_Vars;
               Task_Item      : CM.Resolved_Task;
               Decl_Type      : GM.Type_Descriptor;
               Local_Decl     : CM.Resolved_Object_Decl;
               Priority_Expr  : CM.Expr_Access := null;
               Priority_Type  : GM.Type_Descriptor;
            begin
               if UString_Value (Item.Task_Data.End_Name) /=
                 UString_Value (Item.Task_Data.Name)
               then
                  Raise_Diag
                    (CM.Source_Frontend_Error
                       (Path    => UString_Value (Unit.Path),
                        Span    => Item.Task_Data.Span,
                        Message =>
                          "task end name `" & UString_Value (Item.Task_Data.End_Name)
                          & "` does not match `" & UString_Value (Item.Task_Data.Name) & "`"));
               end if;

               Task_Item.Name := Item.Task_Data.Name;
               Task_Item.Has_Explicit_Priority := Item.Task_Data.Has_Explicit_Priority;
               Task_Item.Priority := Default_Task_Priority;
               Task_Item.Span := Item.Task_Data.Span;

               if Item.Task_Data.Has_Explicit_Priority and then Item.Task_Data.Priority /= null then
                  Priority_Expr :=
                    Normalize_Expr
                      (Item.Task_Data.Priority,
                       Package_Vars,
                       Functions,
                       Type_Env);
                  Priority_Type := Expr_Type (Priority_Expr, Package_Vars, Functions, Type_Env);
                  if not Is_Integerish (Priority_Type, Type_Env) then
                     Raise_Diag
                       (CM.Source_Frontend_Error
                          (Path    => UString_Value (Unit.Path),
                           Span    => Priority_Expr.Span,
                           Message => "task priority expression must be integer"));
                  end if;
                  Task_Item.Priority := Long_Long_Integer (Literal_Value (Priority_Expr, UString_Value (Unit.Path)));
                  if Task_Item.Priority < Min_Task_Priority
                    or else Task_Item.Priority > Max_Task_Priority
                  then
                     Raise_Diag
                       (CM.Source_Frontend_Error
                          (Path    => UString_Value (Unit.Path),
                           Span    => Priority_Expr.Span,
                           Message =>
                             "task priority must be within System.Any_Priority"));
                  end if;
               end if;

               for Decl of Item.Task_Data.Declarations loop
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
                  Task_Item.Declarations.Append (Local_Decl);
                  for Name of Decl.Names loop
                     Visible.Include (UString_Value (Name), Decl_Type);
                  end loop;
               end loop;

               Task_Item.Statements :=
                 Normalize_Statement_List
                   (Item.Task_Data.Statements,
                    Visible,
                    Functions,
                    Type_Env,
                    Channel_Env,
                    UString_Value (Unit.Path));

               if Natural (Task_Item.Statements.Length) /= 1
                 or else Task_Item.Statements (Task_Item.Statements.First_Index).Kind /= CM.Stmt_Loop
               then
                  Raise_Diag
                    (CM.Source_Frontend_Error
                       (Path    => UString_Value (Unit.Path),
                        Span    => Item.Task_Data.Span,
                        Message => "task body must consist of a single outer loop"));
               end if;

               Validate_Task_Nontermination
                 (Task_Item.Statements,
                  UString_Value (Unit.Path),
                  UString_Value (Task_Item.Name));

               Result.Tasks.Append (Task_Item);
            end;
         end if;
      end loop;

      return (Success => True, Unit => Result);
   exception
      when Resolve_Failure =>
         return (Success => False, Diagnostic => Raised_Diag);
   end Resolve;
end Safe_Frontend.Check_Resolve;
