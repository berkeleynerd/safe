with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Hash;
with System;
with Safe_Frontend.Builtin_Types;
with Safe_Frontend.Interfaces;
with Safe_Frontend.Mir_Model;
package body Safe_Frontend.Check_Resolve is
   package BT renames Safe_Frontend.Builtin_Types;
   package GM renames Safe_Frontend.Mir_Model;
   package SI renames Safe_Frontend.Interfaces;

   use type CM.Expr_Access;
   use type CM.Expr_Kind;
   use type CM.Discrete_Range_Kind;
   use type CM.Package_Item_Kind;
   use type CM.Select_Arm_Kind;
   use type CM.Statement_Kind;
   use type CM.Static_Value_Kind;
   use type CM.Type_Decl_Kind;
   use type CM.Type_Spec_Kind;
   use type GM.Scalar_Value_Kind;
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

   function Equal_Static_Value
     (Left, Right : CM.Static_Value) return Boolean is
   begin
      return Left.Kind = Right.Kind
        and then Left.Int_Value = Right.Int_Value
        and then Left.Bool_Value = Right.Bool_Value
        and then FT.To_String (Left.Text) = FT.To_String (Right.Text);
   end Equal_Static_Value;

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

   package Static_Value_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => CM.Static_Value,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=",
      "="             => Equal_Static_Value);

   type Task_Priority_Info is record
      Priority : Long_Long_Integer := 0;
   end record;

   package Task_Priority_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Task_Priority_Info);

   Resolve_Failure : exception;
   Raised_Diag     : CM.MD.Diagnostic;
   Documented_Default_Task_Priority : constant Long_Long_Integer := 31;

   function UString_Value (Value : FT.UString) return String is
   begin
      return FT.To_String (Value);
   end UString_Value;

   function Canonical_Name (Value : String) return String is
   begin
      return FT.Lowercase (Value);
   end Canonical_Name;

   procedure Put_Type
     (Map  : in out Type_Maps.Map;
      Name : String;
      Info : GM.Type_Descriptor) is
   begin
      Map.Include (Canonical_Name (Name), Info);
   end Put_Type;

   procedure Remove_Type
     (Map  : in out Type_Maps.Map;
      Name : String) is
      Key : constant String := Canonical_Name (Name);
   begin
      if Map.Contains (Key) then
         Map.Delete (Key);
      end if;
   end Remove_Type;

   procedure Update_Constant_Visibility
     (Map         : in out Type_Maps.Map;
      Name        : String;
      Info        : GM.Type_Descriptor;
      Is_Constant : Boolean) is
   begin
      if Is_Constant then
         Put_Type (Map, Name, Info);
      else
         Remove_Type (Map, Name);
      end if;
   end Update_Constant_Visibility;

   function Has_Type
     (Map  : Type_Maps.Map;
      Name : String) return Boolean is
   begin
      return Map.Contains (Canonical_Name (Name));
   end Has_Type;

   function Get_Type
     (Map  : Type_Maps.Map;
      Name : String) return GM.Type_Descriptor is
   begin
      return Map.Element (Canonical_Name (Name));
   end Get_Type;

   procedure Put_Function
     (Map  : in out Function_Maps.Map;
      Name : String;
      Info : Function_Info) is
   begin
      Map.Include (Canonical_Name (Name), Info);
   end Put_Function;

   function Has_Function
     (Map  : Function_Maps.Map;
      Name : String) return Boolean is
   begin
      return Map.Contains (Canonical_Name (Name));
   end Has_Function;

   function Get_Function
     (Map  : Function_Maps.Map;
     Name : String) return Function_Info is
   begin
      return Map.Element (Canonical_Name (Name));
   end Get_Function;

   procedure Put_Static_Value
     (Map   : in out Static_Value_Maps.Map;
      Name  : String;
      Value : CM.Static_Value) is
   begin
      Map.Include (Canonical_Name (Name), Value);
   end Put_Static_Value;

   procedure Remove_Static_Value
     (Map  : in out Static_Value_Maps.Map;
      Name : String) is
      Key : constant String := Canonical_Name (Name);
   begin
      if Map.Contains (Key) then
         Map.Delete (Key);
      end if;
   end Remove_Static_Value;

   function Try_Static_Value
     (Expr      : CM.Expr_Access;
      Const_Env : Static_Value_Maps.Map;
      Result    : out CM.Static_Value) return Boolean;

   procedure Update_Static_Constant_Visibility
     (Map         : in out Static_Value_Maps.Map;
      Name        : String;
      Initializer : CM.Expr_Access;
      Is_Constant : Boolean;
      Const_Env   : Static_Value_Maps.Map) is
      Value : CM.Static_Value;
   begin
      if Is_Constant
        and then Initializer /= null
        and then Try_Static_Value (Initializer, Const_Env, Value)
      then
         Put_Static_Value (Map, Name, Value);
      else
         Remove_Static_Value (Map, Name);
      end if;
   end Update_Static_Constant_Visibility;

   function Has_Static_Value
     (Map  : Static_Value_Maps.Map;
      Name : String) return Boolean is
   begin
      return Map.Contains (Canonical_Name (Name));
   end Has_Static_Value;

   function Get_Static_Value
     (Map  : Static_Value_Maps.Map;
      Name : String) return CM.Static_Value is
   begin
      return Map.Element (Canonical_Name (Name));
   end Get_Static_Value;

   procedure Add_Builtins (Type_Env : in out Type_Maps.Map) is
   begin
      Put_Type (Type_Env, "Integer", BT.Integer_Type);
      Put_Type (Type_Env, "Natural", BT.Natural_Type);
      Put_Type (Type_Env, "Boolean", BT.Boolean_Type);
      Put_Type (Type_Env, "Character", BT.Character_Type);
      Put_Type (Type_Env, "String", BT.String_Type);
      Put_Type (Type_Env, "result", BT.Result_Type);
      Put_Type (Type_Env, "Float", BT.Float_Type);
      Put_Type (Type_Env, "Long_Float", BT.Long_Float_Type);
      Put_Type (Type_Env, "Duration", BT.Duration_Type);
   end Add_Builtins;

   procedure Add_Builtin_Functions (Functions : in out Function_Maps.Map) is
      Info   : Function_Info;
      Symbol : CM.Symbol;
   begin
      Info.Name := FT.To_UString ("ok");
      Info.Kind := FT.To_UString ("function");
      Info.Has_Return_Type := True;
      Info.Return_Type := BT.Result_Type;
      Put_Function (Functions, "ok", Info);

      Info := (others => <>);
      Info.Name := FT.To_UString ("fail");
      Info.Kind := FT.To_UString ("function");
      Info.Has_Return_Type := True;
      Info.Return_Type := BT.Result_Type;
      Symbol.Name := FT.To_UString ("message");
      Symbol.Kind := FT.To_UString ("param");
      Symbol.Mode := FT.To_UString ("in");
      Symbol.Type_Info := BT.String_Type;
      Info.Params.Append (Symbol);
      Put_Function (Functions, "fail", Info);
   end Add_Builtin_Functions;

   procedure Raise_Diag (Item : CM.MD.Diagnostic) is
   begin
      Raised_Diag := Item;
      raise Resolve_Failure;
   end Raise_Diag;

   function Default_Integer return GM.Type_Descriptor is
   begin
      return BT.Integer_Type;
   end Default_Integer;

   function Default_Boolean return GM.Type_Descriptor is
   begin
      return BT.Boolean_Type;
   end Default_Boolean;

   function Default_Character return GM.Type_Descriptor is
   begin
      return BT.Character_Type;
   end Default_Character;

   function Default_String return GM.Type_Descriptor is
   begin
      return BT.String_Type;
   end Default_String;

   function Default_Float return GM.Type_Descriptor is
   begin
      return BT.Long_Float_Type;
   end Default_Float;

   function Default_Duration return GM.Type_Descriptor is
   begin
      return BT.Duration_Type;
   end Default_Duration;

   function Default_Task_Priority return Long_Long_Integer is
   begin
      --  Keep omitted task priorities stable across supported hosts so typed
      --  and MIR artifacts remain deterministic for the same source input.
      return Documented_Default_Task_Priority;
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
   begin
      while Result.Has_Base and then Has_Type (Type_Env, UString_Value (Result.Base)) loop
         Result := Get_Type (Type_Env, UString_Value (Result.Base));
         exit when UString_Value (Result.Name) = "";
      end loop;
      return Result;
   end Base_Type;

   function Is_Integerish
     (Info     : GM.Type_Descriptor;
     Type_Env : Type_Maps.Map) return Boolean;

   function Is_Tuple_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean;

   function Is_Character_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean;

   function Is_String_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean;

   function Is_Discrete_Case_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean;

   function Case_Choice_Compatible
     (Scrutinee : GM.Type_Descriptor;
      Choice    : GM.Type_Descriptor;
      Type_Env  : Type_Maps.Map) return Boolean;

   function Resolve_Type
     (Name     : String;
      Type_Env : Type_Maps.Map;
      Path     : String;
      Span     : FT.Source_Span) return GM.Type_Descriptor;

   function Equivalent_Type
     (Left     : GM.Type_Descriptor;
      Right    : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean
   is
      Left_Base  : constant GM.Type_Descriptor := Base_Type (Left, Type_Env);
      Right_Base : constant GM.Type_Descriptor := Base_Type (Right, Type_Env);
   begin
      if FT.Lowercase (UString_Value (Left_Base.Kind)) = "tuple"
        or else FT.Lowercase (UString_Value (Right_Base.Kind)) = "tuple"
      then
         if FT.Lowercase (UString_Value (Left_Base.Kind)) /= "tuple"
           or else FT.Lowercase (UString_Value (Right_Base.Kind)) /= "tuple"
           or else Natural (Left_Base.Tuple_Element_Types.Length) /=
                    Natural (Right_Base.Tuple_Element_Types.Length)
         then
            return False;
         end if;
         for Index in Left_Base.Tuple_Element_Types.First_Index .. Left_Base.Tuple_Element_Types.Last_Index loop
            if not Equivalent_Type
              (Resolve_Type (UString_Value (Left_Base.Tuple_Element_Types (Index)), Type_Env, "", FT.Null_Span),
               Resolve_Type (UString_Value (Right_Base.Tuple_Element_Types (Index)), Type_Env, "", FT.Null_Span),
               Type_Env)
            then
               return False;
            end if;
         end loop;
         return True;
      end if;
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
        or else (Is_Tuple_Type (Left, Type_Env)
                 and then Is_Tuple_Type (Right, Type_Env)
                 and then Equivalent_Type (Left, Right, Type_Env))
        or else (Is_Integerish (Left, Type_Env) and then Is_Integerish (Right, Type_Env))
        or else (Left_Kind = "float" and then Right_Kind = "float");
   end Compatible_Type;

   function Is_Boolean_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean is
   begin
      return UString_Value (Base_Type (Info, Type_Env).Name) = "Boolean";
   end Is_Boolean_Type;

   function Is_Tuple_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean is
   begin
      return FT.Lowercase (UString_Value (Base_Type (Info, Type_Env).Kind)) = "tuple";
   end Is_Tuple_Type;

   function Is_Character_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean is
   begin
      return UString_Value (Base_Type (Info, Type_Env).Name) = "Character";
   end Is_Character_Type;

   function Is_String_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean is
   begin
      return UString_Value (Base_Type (Info, Type_Env).Name) = "String";
   end Is_String_Type;

   function Is_Tuple_Element_Type_Allowed
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean
   is
      Base : constant GM.Type_Descriptor := Base_Type (Info, Type_Env);
      Kind : constant String := FT.Lowercase (UString_Value (Base.Kind));
   begin
      return Kind /= "access"
        and then Kind /= "tuple"
        and then Kind /= "incomplete";
   end Is_Tuple_Element_Type_Allowed;

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

   function Is_Discrete_Case_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean is
   begin
      return Is_Boolean_Type (Info, Type_Env)
        or else Is_Character_Type (Info, Type_Env)
        or else (Is_Integerish (Info, Type_Env) and then not Is_Boolean_Type (Info, Type_Env));
   end Is_Discrete_Case_Type;

   function Case_Choice_Compatible
     (Scrutinee : GM.Type_Descriptor;
      Choice    : GM.Type_Descriptor;
      Type_Env  : Type_Maps.Map) return Boolean is
   begin
      if Is_Boolean_Type (Scrutinee, Type_Env) then
         return Is_Boolean_Type (Choice, Type_Env);
      elsif Is_Character_Type (Scrutinee, Type_Env) then
         return Is_Character_Type (Choice, Type_Env);
      end if;

      return Is_Integerish (Scrutinee, Type_Env)
        and then not Is_Boolean_Type (Scrutinee, Type_Env)
        and then Is_Integerish (Choice, Type_Env)
        and then not Is_Boolean_Type (Choice, Type_Env)
        and then not Is_Character_Type (Choice, Type_Env);
   end Case_Choice_Compatible;

   function Is_Definite_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean
   is
      Base : constant GM.Type_Descriptor := Base_Type (Info, Type_Env);
      Kind : constant String := FT.Lowercase (UString_Value (Base.Kind));
      Info_Kind : constant String := FT.Lowercase (UString_Value (Info.Kind));
   begin
      if Kind = "incomplete" then
         return False;
      elsif Info_Kind = "subtype" and then not Info.Discriminant_Constraints.Is_Empty then
         return True;
      elsif Kind = "array" then
         return not Base.Unconstrained;
      elsif Kind = "tuple" then
         for Item of Base.Tuple_Element_Types loop
            if not Is_Definite_Type
              (Resolve_Type (UString_Value (Item), Type_Env, "", FT.Null_Span),
               Type_Env)
            then
               return False;
            end if;
         end loop;
         return True;
      elsif Kind = "record" and then not Base.Discriminants.Is_Empty then
         for Disc of Base.Discriminants loop
            if not Disc.Has_Default then
               return False;
            end if;
         end loop;
         return True;
      elsif Kind = "record" and then Base.Has_Discriminant then
         return Base.Has_Discriminant_Default;
      end if;
      return True;
   end Is_Definite_Type;

   function Contains_Channel_Access_Subcomponent
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean
   is
      Base : constant GM.Type_Descriptor := Base_Type (Info, Type_Env);
      Kind : constant String := FT.Lowercase (UString_Value (Base.Kind));

      function Has_Prefix (Text : String; Prefix : String) return Boolean is
      begin
         return Text'Length >= Prefix'Length
           and then Text (Text'First .. Text'First + Prefix'Length - 1) = Prefix;
      end Has_Prefix;

      function Looks_Like_Anonymous_Access_Name (Name : String) return Boolean is
         Lower : constant String := FT.Lowercase (Name);
      begin
         return Has_Prefix (Lower, "access ")
           or else Has_Prefix (Lower, "not null access ")
           or else Has_Prefix (Lower, "access constant ")
           or else Has_Prefix (Lower, "not null access constant ")
           or else Has_Prefix (Lower, "access all ")
           or else Has_Prefix (Lower, "not null access all ")
           or else Has_Prefix (Lower, "access all constant ")
           or else Has_Prefix (Lower, "not null access all constant ");
      end Looks_Like_Anonymous_Access_Name;

      function Named_Type_Contains_Access (Name : String) return Boolean is
      begin
         if Name = "" then
            return False;
         end if;
         if Looks_Like_Anonymous_Access_Name (Name) then
            return True;
         end if;
         if not Has_Type (Type_Env, Name) then
            return False;
         end if;
         return Contains_Channel_Access_Subcomponent (Get_Type (Type_Env, Name), Type_Env);
      end Named_Type_Contains_Access;
   begin
      if Kind = "access" then
         return True;
      end if;

      if Base.Has_Component_Type
        and then Named_Type_Contains_Access (UString_Value (Base.Component_Type))
      then
         return True;
      end if;

      for Item of Base.Tuple_Element_Types loop
         if Named_Type_Contains_Access (UString_Value (Item)) then
            return True;
         end if;
      end loop;

      for Field of Base.Fields loop
         if Named_Type_Contains_Access (UString_Value (Field.Type_Name)) then
            return True;
         end if;
      end loop;

      for Field of Base.Variant_Fields loop
         if Named_Type_Contains_Access (UString_Value (Field.Type_Name)) then
            return True;
         end if;
      end loop;

      return False;
   end Contains_Channel_Access_Subcomponent;

   function Contains_Dot (Name : String) return Boolean is
   begin
      for Ch of Name loop
         if Ch = '.' then
            return True;
         end if;
      end loop;
      return False;
   end Contains_Dot;

   function Is_Builtin_Name (Name : String) return Boolean is
   begin
      return Name in
        "Integer" | "Natural" | "Boolean" | "Character" | "String" | "Float" | "Long_Float" | "Duration" | "result";
   end Is_Builtin_Name;

   function Qualify_Name
     (Package_Name : String;
      Name         : String) return String
   is
      Lowered : constant String := FT.Lowercase (Name);
   begin
      if Name = ""
        or else Is_Builtin_Name (Name)
        or else Contains_Dot (Name)
        or else (Lowered'Length >= 7 and then Lowered (Lowered'First .. Lowered'First + 6) = "access ")
      then
         return Name;
      end if;
      return Package_Name & "." & Name;
   end Qualify_Name;

   function Qualify_Type_Info
     (Info         : GM.Type_Descriptor;
      Package_Name : String) return GM.Type_Descriptor
   is
      Result : GM.Type_Descriptor := Info;
   begin
      Result.Name := FT.To_UString (Qualify_Name (Package_Name, UString_Value (Info.Name)));
      if Result.Has_Base then
         Result.Base := FT.To_UString (Qualify_Name (Package_Name, UString_Value (Result.Base)));
      end if;
      if Result.Has_Component_Type then
         Result.Component_Type :=
           FT.To_UString (Qualify_Name (Package_Name, UString_Value (Result.Component_Type)));
      end if;
      if Result.Has_Target then
         Result.Target := FT.To_UString (Qualify_Name (Package_Name, UString_Value (Result.Target)));
      end if;
      if Result.Has_Discriminant then
         Result.Discriminant_Type :=
           FT.To_UString (Qualify_Name (Package_Name, UString_Value (Result.Discriminant_Type)));
      end if;
      if not Result.Index_Types.Is_Empty then
         for Index in Result.Index_Types.First_Index .. Result.Index_Types.Last_Index loop
            Result.Index_Types.Replace_Element
              (Index,
               FT.To_UString
                 (Qualify_Name (Package_Name, UString_Value (Result.Index_Types (Index)))));
         end loop;
      end if;
      if not Result.Fields.Is_Empty then
         for Index in Result.Fields.First_Index .. Result.Fields.Last_Index loop
            declare
               Item : GM.Type_Field := Result.Fields (Index);
            begin
               Item.Type_Name :=
                 FT.To_UString (Qualify_Name (Package_Name, UString_Value (Item.Type_Name)));
               Result.Fields.Replace_Element (Index, Item);
            end;
         end loop;
      end if;
      if not Result.Variant_Fields.Is_Empty then
         for Index in Result.Variant_Fields.First_Index .. Result.Variant_Fields.Last_Index loop
            declare
               Item : GM.Variant_Field := Result.Variant_Fields (Index);
            begin
               Item.Type_Name :=
                 FT.To_UString (Qualify_Name (Package_Name, UString_Value (Item.Type_Name)));
               Result.Variant_Fields.Replace_Element (Index, Item);
            end;
         end loop;
      end if;
      return Result;
   end Qualify_Type_Info;

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

   function Expr_Text (Expr : CM.Expr_Access) return String;

   function Expr_Text (Expr : CM.Expr_Access) return String is
   begin
      if Expr = null then
         return "";
      end if;

      case Expr.Kind is
         when CM.Expr_Int | CM.Expr_Real | CM.Expr_String | CM.Expr_Char =>
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

   function Root_Name (Expr : CM.Expr_Access) return String is
   begin
      if Expr = null then
         return "";
      elsif Expr.Kind = CM.Expr_Ident then
         return UString_Value (Expr.Name);
      elsif Expr.Kind = CM.Expr_Select then
         return Root_Name (Expr.Prefix);
      elsif Expr.Kind = CM.Expr_Resolved_Index then
         return Root_Name (Expr.Prefix);
      elsif Expr.Kind = CM.Expr_Conversion then
         return Root_Name (Expr.Inner);
      end if;
      return "";
   end Root_Name;

   function Try_Static_Value
     (Expr      : CM.Expr_Access;
      Const_Env : Static_Value_Maps.Map;
      Result    : out CM.Static_Value) return Boolean
   is
   begin
      Result := (others => <>);
      if Expr = null then
         return False;
      end if;

      case Expr.Kind is
         when CM.Expr_Int =>
            Result.Kind := CM.Static_Value_Integer;
            Result.Int_Value := Expr.Int_Value;
            return True;
         when CM.Expr_Char =>
            Result.Kind := CM.Static_Value_Character;
            Result.Text := Expr.Text;
            return True;
         when CM.Expr_Bool =>
            Result.Kind := CM.Static_Value_Boolean;
            Result.Bool_Value := Expr.Bool_Value;
            return True;
         when CM.Expr_Unary =>
            if UString_Value (Expr.Operator) = "-" then
               declare
                  Inner_Value : CM.Static_Value;
               begin
                  if Try_Static_Value (Expr.Inner, Const_Env, Inner_Value)
                    and then Inner_Value.Kind = CM.Static_Value_Integer
                  then
                     Result.Kind := CM.Static_Value_Integer;
                     Result.Int_Value := -Inner_Value.Int_Value;
                     return True;
                  end if;
               end;
            end if;
            return False;
         when CM.Expr_Ident | CM.Expr_Select =>
            declare
               Name : constant String := Flatten_Name (Expr);
            begin
               if Name /= "" and then Has_Static_Value (Const_Env, Name) then
                  Result := Get_Static_Value (Const_Env, Name);
                  return Result.Kind /= CM.Static_Value_None;
               end if;
               return False;
            end;
         when others =>
            return False;
      end case;
   end Try_Static_Value;

   function To_Scalar_Value (Value : CM.Static_Value) return GM.Scalar_Value is
      Result : GM.Scalar_Value;
   begin
      case Value.Kind is
         when CM.Static_Value_Integer =>
            Result.Kind := GM.Scalar_Value_Integer;
            Result.Int_Value := Long_Long_Integer (Value.Int_Value);
         when CM.Static_Value_Boolean =>
            Result.Kind := GM.Scalar_Value_Boolean;
            Result.Bool_Value := Value.Bool_Value;
         when CM.Static_Value_Character =>
            Result.Kind := GM.Scalar_Value_Character;
            Result.Text := Value.Text;
         when others =>
            null;
      end case;
      return Result;
   end To_Scalar_Value;

   function Scalar_Value_Compatible
     (Value    : CM.Static_Value;
      Disc_Type : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean
   is
      Base : constant GM.Type_Descriptor := Base_Type (Disc_Type, Type_Env);
   begin
      if Value.Kind = CM.Static_Value_Boolean then
         return Is_Boolean_Type (Base, Type_Env);
      elsif Value.Kind = CM.Static_Value_Character then
         return Is_Character_Type (Base, Type_Env);
      elsif Value.Kind = CM.Static_Value_Integer then
         return Is_Integerish (Base, Type_Env)
           and then (not Base.Has_Low or else Long_Long_Integer (Value.Int_Value) >= Base.Low)
           and then (not Base.Has_High or else Long_Long_Integer (Value.Int_Value) <= Base.High)
           and then not Is_Boolean_Type (Base, Type_Env)
           and then not Is_Character_Type (Base, Type_Env);
      end if;
      return False;
   end Scalar_Value_Compatible;

   function Bool_Literal_Value
     (Expr      : CM.Expr_Access;
      Const_Env : Static_Value_Maps.Map;
      Path      : String) return Boolean
   is
      Value : CM.Static_Value;
   begin
      if Try_Static_Value (Expr, Const_Env, Value)
        and then Value.Kind = CM.Static_Value_Boolean
      then
         return Value.Bool_Value;
      end if;

      Raise_Diag
        (CM.Source_Frontend_Error
           (Path    => Path,
            Span    => (if Expr = null then FT.Null_Span else Expr.Span),
            Message => "boolean discriminant defaults must be boolean literals or constant references"));
      return False;
   end Bool_Literal_Value;

   function Resolve_Type
     (Name     : String;
      Type_Env : Type_Maps.Map;
      Path     : String;
      Span     : FT.Source_Span) return GM.Type_Descriptor
   is
   begin
      if Has_Type (Type_Env, Name) then
         return Get_Type (Type_Env, Name);
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
     (Expr      : CM.Expr_Access;
      Const_Env : Static_Value_Maps.Map;
      Path      : String;
      Context   : String) return CM.Wide_Integer
   is
      Value : CM.Static_Value;
   begin
      if Try_Static_Value (Expr, Const_Env, Value)
        and then Value.Kind = CM.Static_Value_Integer
      then
         return Value.Int_Value;
      end if;

      Raise_Diag
        (CM.Source_Frontend_Error
           (Path    => Path,
            Span    => (if Expr = null then FT.Null_Span else Expr.Span),
            Message => Context));
      return 0;
   end Literal_Value;

   function Sanitize_Type_Name_Component (Value : String) return String is
      Result : FT.UString := FT.To_UString ("");
      Last_Was_Underscore : Boolean := False;
   begin
      for Ch of Value loop
         if Ch in 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' then
            Result := Result & FT.To_UString ((1 => Ch));
            Last_Was_Underscore := False;
         else
            if not Last_Was_Underscore then
               Result := Result & FT.To_UString ("_");
               Last_Was_Underscore := True;
            end if;
         end if;
      end loop;
      declare
         Text : constant String := UString_Value (Result);
         First : Positive := Text'First;
         Last  : Natural := Text'Last;
      begin
         while First <= Text'Last and then Text (First) = '_' loop
            First := First + 1;
         end loop;
         while Last >= First and then Text (Last) = '_' loop
            Last := Last - 1;
         end loop;
         if Last < First then
            return "value";
         end if;
         return Text (First .. Last);
      end;
   end Sanitize_Type_Name_Component;

   function Tuple_Type_Name
     (Element_Types : FT.UString_Vectors.Vector) return FT.UString
   is
      Result : FT.UString := FT.To_UString ("__tuple");
   begin
      for Item of Element_Types loop
         Result :=
           Result
           & FT.To_UString ("_")
           & FT.To_UString (Sanitize_Type_Name_Component (UString_Value (Item)));
      end loop;
      return Result;
   end Tuple_Type_Name;

   function Static_Value_Name_Component (Value : CM.Static_Value) return String is
   begin
      case Value.Kind is
         when CM.Static_Value_Integer =>
            return Sanitize_Type_Name_Component (CM.Wide_Integer'Image (Value.Int_Value));
         when CM.Static_Value_Boolean =>
            return (if Value.Bool_Value then "true" else "false");
         when CM.Static_Value_Character =>
            return Sanitize_Type_Name_Component (UString_Value (Value.Text));
         when others =>
            return "value";
      end case;
   end Static_Value_Name_Component;

   function Make_Tuple_Type
     (Element_Types : FT.UString_Vectors.Vector) return GM.Type_Descriptor
   is
      Result : GM.Type_Descriptor;
   begin
      Result.Name := Tuple_Type_Name (Element_Types);
      Result.Kind := FT.To_UString ("tuple");
      Result.Tuple_Element_Types := Element_Types;
      return Result;
   end Make_Tuple_Type;

   function Resolve_Type_Spec
     (Spec     : CM.Type_Spec;
      Type_Env : Type_Maps.Map;
      Const_Env : Static_Value_Maps.Map := Static_Value_Maps.Empty_Map;
      Path     : String) return GM.Type_Descriptor
   is
      Result : GM.Type_Descriptor;
      Target : GM.Type_Descriptor;
      Base   : GM.Type_Descriptor;
      Element_Types : FT.UString_Vectors.Vector;
   begin
      case Spec.Kind is
         when CM.Type_Spec_Name | CM.Type_Spec_Subtype_Indication =>
            if not Spec.Constraints.Is_Empty then
               Base := Resolve_Type (UString_Value (Spec.Name), Type_Env, Path, Spec.Span);
               if Base.Discriminants.Is_Empty then
                  Raise_Diag
                    (CM.Source_Frontend_Error
                       (Path    => Path,
                        Span    => Spec.Span,
                        Message => "discriminant constraints require a discriminated record type"));
               end if;
               declare
                  First_Is_Named : constant Boolean := Spec.Constraints (Spec.Constraints.First_Index).Is_Named;
                  Seen_Names     : FT.UString_Vectors.Vector;
                  Disc_Index     : Positive := Base.Discriminants.First_Index;
               begin
                  for Assoc of Spec.Constraints loop
                     declare
                        Disc         : GM.Discriminant_Descriptor;
                        Static_Value : CM.Static_Value;
                        Constraint   : GM.Discriminant_Constraint;
                        Found        : Boolean := False;
                     begin
                        if Assoc.Is_Named /= First_Is_Named then
                           Raise_Diag
                             (CM.Source_Frontend_Error
                                (Path    => Path,
                                 Span    => Assoc.Span,
                                 Message => "do not mix positional and named discriminant constraints"));
                        end if;

                        if Assoc.Is_Named then
                           for Existing of Seen_Names loop
                              if UString_Value (Existing) = UString_Value (Assoc.Name) then
                                 Raise_Diag
                                   (CM.Source_Frontend_Error
                                      (Path    => Path,
                                       Span    => Assoc.Span,
                                       Message => "duplicate named discriminant constraint '" & UString_Value (Assoc.Name) & "'"));
                              end if;
                           end loop;
                           for Item of Base.Discriminants loop
                              if UString_Value (Item.Name) = UString_Value (Assoc.Name) then
                                 Disc := Item;
                                 Found := True;
                                 exit;
                              end if;
                           end loop;
                           if not Found then
                              Raise_Diag
                                (CM.Source_Frontend_Error
                                   (Path    => Path,
                                    Span    => Assoc.Span,
                                    Message => "unknown discriminant name '" & UString_Value (Assoc.Name) & "'"));
                           end if;
                           Seen_Names.Append (Assoc.Name);
                        else
                           if Disc_Index > Base.Discriminants.Last_Index then
                              Raise_Diag
                                (CM.Source_Frontend_Error
                                   (Path    => Path,
                                    Span    => Assoc.Span,
                                    Message => "too many positional discriminant constraints"));
                           end if;
                           Disc := Base.Discriminants (Disc_Index);
                           Disc_Index := Disc_Index + 1;
                        end if;

                        if not Try_Static_Value (Assoc.Value, Const_Env, Static_Value) then
                           Raise_Diag
                             (CM.Source_Frontend_Error
                                (Path    => Path,
                                 Span    => Assoc.Span,
                                 Message => "discriminant constraints must be static scalar values"));
                        elsif not Scalar_Value_Compatible
                          (Static_Value,
                           Resolve_Type (UString_Value (Disc.Type_Name), Type_Env, Path, Assoc.Span),
                           Type_Env)
                        then
                           Raise_Diag
                             (CM.Source_Frontend_Error
                                (Path    => Path,
                                 Span    => Assoc.Span,
                                 Message => "discriminant constraint value does not match discriminant type"));
                        end if;

                        Constraint.Is_Named := Assoc.Is_Named;
                        Constraint.Name := Disc.Name;
                        Constraint.Value := To_Scalar_Value (Static_Value);
                        Result.Discriminant_Constraints.Append (Constraint);
                     end;
                  end loop;

                  if Natural (Result.Discriminant_Constraints.Length) /=
                    Natural (Base.Discriminants.Length)
                  then
                     Raise_Diag
                       (CM.Source_Frontend_Error
                          (Path    => Path,
                           Span    => Spec.Span,
                           Message => "discriminant constraints must cover every discriminant in PR11.3"));
                  end if;
               end;
               Result.Name :=
                 FT.To_UString
                   ("__constraint_"
                    & Sanitize_Type_Name_Component (UString_Value (Base.Name)));
               for Constraint of Result.Discriminant_Constraints loop
                  Result.Name :=
                    Result.Name
                    & FT.To_UString ("_")
                    & FT.To_UString
                        (Sanitize_Type_Name_Component (UString_Value (Constraint.Name)))
                    & FT.To_UString ("_")
                    & FT.To_UString
                        (Sanitize_Type_Name_Component
                           ((case Constraint.Value.Kind is
                                when GM.Scalar_Value_Integer =>
                                   Long_Long_Integer'Image (Constraint.Value.Int_Value),
                                when GM.Scalar_Value_Boolean =>
                                   (if Constraint.Value.Bool_Value then "true" else "false"),
                                when GM.Scalar_Value_Character =>
                                   UString_Value (Constraint.Value.Text),
                                when others =>
                                   "value")));
               end loop;
               Result.Kind := FT.To_UString ("subtype");
               Result.Has_Base := True;
               Result.Base := Base.Name;
               return Result;
            end if;
            return Resolve_Type (UString_Value (Spec.Name), Type_Env, Path, Spec.Span);
         when CM.Type_Spec_Tuple =>
            if Natural (Spec.Tuple_Elements.Length) < 2 then
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path,
                     Span    => Spec.Span,
                     Message => "tuple types require at least two elements"));
            end if;
            for Item of Spec.Tuple_Elements loop
               declare
                  Element_Type : constant GM.Type_Descriptor :=
                    Resolve_Type_Spec (Item.all, Type_Env, Const_Env, Path);
               begin
                  if not Is_Tuple_Element_Type_Allowed (Element_Type, Type_Env) then
                     Raise_Diag
                       (CM.Unsupported_Source_Construct
                          (Path    => Path,
                           Span    => Item.Span,
                           Message => "tuple elements are limited to the current value-type subset in PR11.3"));
                  end if;
                  Element_Types.Append (Element_Type.Name);
               end;
            end loop;
            return Make_Tuple_Type (Element_Types);
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
         for Disc of Info.Discriminants loop
            if UString_Value (Disc.Name) = Field_Name then
               return Resolve_Type (UString_Value (Disc.Type_Name), Type_Env, "", FT.Null_Span);
            end if;
         end loop;
         if Info.Has_Discriminant and then UString_Value (Info.Discriminant_Name) = Field_Name then
            return Resolve_Type (UString_Value (Info.Discriminant_Type), Type_Env, "", FT.Null_Span);
         end if;
         for Field of Info.Fields loop
            if UString_Value (Field.Name) = Field_Name then
               return Resolve_Type (UString_Value (Field.Type_Name), Type_Env, "", FT.Null_Span);
            end if;
         end loop;
      elsif UString_Value (Info.Kind) = "tuple" then
         declare
            Index_Value : Natural := 0;
         begin
            begin
               Index_Value := Natural'Value (Field_Name);
            exception
               when Constraint_Error =>
                  return Default_Integer;
            end;
            if Index_Value in 1 .. Natural (Info.Tuple_Element_Types.Length) then
               return Resolve_Type
                 (UString_Value (Info.Tuple_Element_Types (Positive (Index_Value))),
                  Type_Env,
                  "",
                  FT.Null_Span);
            end if;
         end;
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
         when CM.Expr_String =>
            return Default_String;
         when CM.Expr_Char =>
            return Default_Character;
         when CM.Expr_Tuple =>
            declare
               Elements : FT.UString_Vectors.Vector;
            begin
               for Item of Expr.Elements loop
                  Elements.Append (Expr_Type (Item, Var_Types, Functions, Type_Env).Name);
               end loop;
               return Make_Tuple_Type (Elements);
            end;
         when CM.Expr_Real =>
            if UString_Value (Expr.Type_Name)'Length > 0
              and then Has_Type (Type_Env, UString_Value (Expr.Type_Name))
            then
               return Get_Type (Type_Env, UString_Value (Expr.Type_Name));
            end if;
            return Default_Float;
         when CM.Expr_Ident =>
            Name := Expr.Name;
            if Has_Type (Var_Types, UString_Value (Name)) then
               return Get_Type (Var_Types, UString_Value (Name));
            elsif Has_Function (Functions, UString_Value (Name)) then
               declare
                  Info : constant Function_Info := Get_Function (Functions, UString_Value (Name));
               begin
                  if Info.Has_Return_Type then
                     return Info.Return_Type;
                  end if;
               end;
            end if;
         when CM.Expr_Select =>
            Name := FT.To_UString (Flatten_Name (Expr));
            if Has_Type (Var_Types, UString_Value (Name)) then
               return Get_Type (Var_Types, UString_Value (Name));
            elsif Has_Type (Type_Env, UString_Value (Name)) then
               return Get_Type (Type_Env, UString_Value (Name));
            elsif Has_Function (Functions, UString_Value (Name)) then
               declare
                  Info : constant Function_Info := Get_Function (Functions, UString_Value (Name));
               begin
                  if Info.Has_Return_Type then
                     return Info.Return_Type;
                  end if;
               end;
            end if;

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
            if Has_Function (Functions, UString_Value (Name)) then
               declare
                  Info : constant Function_Info := Get_Function (Functions, UString_Value (Name));
               begin
                  if Info.Has_Return_Type then
                     return Info.Return_Type;
                  end if;
               end;
            elsif UString_Value (Name) = "Long_Float.Copy_Sign" then
               return Resolve_Type ("Long_Float", Type_Env, "", FT.Null_Span);
            elsif Has_Type (Var_Types, UString_Value (Name)) then
               return Get_Type (Var_Types, UString_Value (Name));
            elsif UString_Value (Expr.Type_Name)'Length > 0
              and then Has_Type (Type_Env, UString_Value (Expr.Type_Name))
            then
               return Get_Type (Type_Env, UString_Value (Expr.Type_Name));
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
         if Has_Type (Var_Types, UString_Value (Callee_Name))
           and then UString_Value
             (Get_Type (Var_Types, UString_Value (Callee_Name)).Kind) = "array"
         then
            Result.Kind := CM.Expr_Resolved_Index;
            Result.Prefix := Expr.Callee;
            Result.Args := Expr.Args;
         elsif Has_Function (Functions, UString_Value (Callee_Name)) then
            Result.Kind := CM.Expr_Call;
            Result.Callee := Expr.Callee;
            Result.Args := Expr.Args;
         elsif Has_Type (Var_Types, UString_Value (Callee_Name))
           and then UString_Value
             (Get_Type (Var_Types, UString_Value (Callee_Name)).Kind)
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
         when CM.Expr_Tuple =>
            Result := new CM.Expr_Node'(Expr.all);
            Result.Elements.Clear;
            for Item of Expr.Elements loop
               Result.Elements.Append (Normalize_Expr (Item, Var_Types, Functions, Type_Env));
            end loop;
         when CM.Expr_Annotated =>
            Result := new CM.Expr_Node'(Expr.all);
            Result.Inner := Normalize_Expr (Expr.Inner, Var_Types, Functions, Type_Env);
         when others =>
            Result := new CM.Expr_Node'(Expr.all);
      end case;

      return Set_Type (Result, Expr_Type (Result, Var_Types, Functions, Type_Env));
   end Normalize_Expr;

   procedure Validate_Pr112_Expr_Boundaries
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Path      : String)
   is
      Prefix_Type : GM.Type_Descriptor;
      Left_Type   : GM.Type_Descriptor;
      Right_Type  : GM.Type_Descriptor;
   begin
      if Expr = null then
         return;
      end if;

      case Expr.Kind is
         when CM.Expr_Select =>
            Validate_Pr112_Expr_Boundaries (Expr.Prefix, Var_Types, Functions, Type_Env, Path);
            Prefix_Type := Expr_Type (Expr.Prefix, Var_Types, Functions, Type_Env);
            if UString_Value (Expr.Selector) in "First" | "Last" | "Length" | "Access"
              and then Is_String_Type (Prefix_Type, Type_Env)
            then
               Raise_Diag
                 (CM.Unsupported_Source_Construct
                    (Path    => Path,
                    Span    => Expr.Span,
                     Message => "string attributes are outside the current PR11.2 text subset"));
            elsif Is_Tuple_Type (Prefix_Type, Type_Env) then
               declare
                  Index_Value : Natural := 0;
               begin
                  begin
                     Index_Value := Natural'Value (UString_Value (Expr.Selector));
                  exception
                     when Constraint_Error =>
                        Raise_Diag
                          (CM.Source_Frontend_Error
                             (Path    => Path,
                              Span    => Expr.Span,
                              Message => "tuple field selectors must be positional indexes like `.1` in PR11.3"));
                  end;
                  if Index_Value = 0
                    or else Index_Value > Natural (Base_Type (Prefix_Type, Type_Env).Tuple_Element_Types.Length)
                  then
                     Raise_Diag
                       (CM.Source_Frontend_Error
                          (Path    => Path,
                           Span    => Expr.Span,
                           Message => "tuple field selector is out of bounds for the tuple type"));
                  end if;
               end;
            end if;
         when CM.Expr_Resolved_Index =>
            Validate_Pr112_Expr_Boundaries (Expr.Prefix, Var_Types, Functions, Type_Env, Path);
            if Is_String_Type (Expr_Type (Expr.Prefix, Var_Types, Functions, Type_Env), Type_Env) then
               Raise_Diag
                 (CM.Unsupported_Source_Construct
                    (Path    => Path,
                     Span    => Expr.Span,
                     Message => "string indexing is outside the current PR11.2 text subset"));
            end if;
            for Item of Expr.Args loop
               Validate_Pr112_Expr_Boundaries (Item, Var_Types, Functions, Type_Env, Path);
            end loop;
         when CM.Expr_Call =>
            Validate_Pr112_Expr_Boundaries (Expr.Callee, Var_Types, Functions, Type_Env, Path);
            for Item of Expr.Args loop
               Validate_Pr112_Expr_Boundaries (Item, Var_Types, Functions, Type_Env, Path);
            end loop;
         when CM.Expr_Conversion =>
            Validate_Pr112_Expr_Boundaries (Expr.Inner, Var_Types, Functions, Type_Env, Path);
         when CM.Expr_Allocator =>
            Validate_Pr112_Expr_Boundaries (Expr.Value, Var_Types, Functions, Type_Env, Path);
         when CM.Expr_Aggregate =>
            for Item of Expr.Fields loop
               Validate_Pr112_Expr_Boundaries (Item.Expr, Var_Types, Functions, Type_Env, Path);
            end loop;
         when CM.Expr_Tuple =>
            for Item of Expr.Elements loop
               Validate_Pr112_Expr_Boundaries (Item, Var_Types, Functions, Type_Env, Path);
            end loop;
         when CM.Expr_Annotated =>
            Validate_Pr112_Expr_Boundaries (Expr.Inner, Var_Types, Functions, Type_Env, Path);
         when CM.Expr_Unary =>
            Validate_Pr112_Expr_Boundaries (Expr.Inner, Var_Types, Functions, Type_Env, Path);
            if Is_String_Type (Expr_Type (Expr.Inner, Var_Types, Functions, Type_Env), Type_Env) then
               Raise_Diag
                 (CM.Unsupported_Source_Construct
                    (Path    => Path,
                     Span    => Expr.Span,
                     Message => "string operators are outside the current PR11.2 text subset"));
            end if;
         when CM.Expr_Binary =>
            Validate_Pr112_Expr_Boundaries (Expr.Left, Var_Types, Functions, Type_Env, Path);
            Validate_Pr112_Expr_Boundaries (Expr.Right, Var_Types, Functions, Type_Env, Path);
            Left_Type := Expr_Type (Expr.Left, Var_Types, Functions, Type_Env);
            Right_Type := Expr_Type (Expr.Right, Var_Types, Functions, Type_Env);
            if Is_String_Type (Left_Type, Type_Env) or else Is_String_Type (Right_Type, Type_Env) then
               Raise_Diag
                 (CM.Unsupported_Source_Construct
                    (Path    => Path,
                     Span    => Expr.Span,
                     Message => "string comparison and concatenation are outside the current PR11.2 text subset"));
            end if;
         when others =>
            null;
      end case;
   end Validate_Pr112_Expr_Boundaries;

   function Normalize_Expr_Checked
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Path      : String) return CM.Expr_Access
   is
      Result : constant CM.Expr_Access :=
        Normalize_Expr (Expr, Var_Types, Functions, Type_Env);
   begin
      Validate_Pr112_Expr_Boundaries (Result, Var_Types, Functions, Type_Env, Path);
      return Result;
   end Normalize_Expr_Checked;

   function Is_Assignable_Target (Expr : CM.Expr_Access) return Boolean is
   begin
      if Expr = null then
         return False;
      elsif Expr.Kind = CM.Expr_Ident or else Expr.Kind = CM.Expr_Resolved_Index then
         return True;
      elsif Expr.Kind = CM.Expr_Tuple then
         if Natural (Expr.Elements.Length) < 2 then
            return False;
         end if;
         for Item of Expr.Elements loop
            if not Is_Assignable_Target (Item) then
               return False;
            end if;
         end loop;
         return True;
      elsif Expr.Kind = CM.Expr_Select then
         return UString_Value (Expr.Selector) not in "First" | "Last" | "Length" | "Access";
      end if;
      return False;
   end Is_Assignable_Target;

   function Resolve_Decl_Type
     (Decl      : CM.Object_Decl;
      Type_Env  : Type_Maps.Map;
      Const_Env : Static_Value_Maps.Map;
      Path      : String) return GM.Type_Descriptor is
   begin
      if Decl.Is_Constant and then not Decl.Has_Initializer then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path,
               Span    => Decl.Span,
               Message => "constant declarations require initializers"));
      end if;
      return Resolve_Type_Spec (Decl.Decl_Type, Type_Env, Const_Env, Path);
   end Resolve_Decl_Type;

   procedure Reject_Unsupported_String_Use
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map;
      Path     : String;
      Span     : FT.Source_Span;
      Message  : String) is
   begin
      if Is_String_Type (Info, Type_Env) then
         Raise_Diag
           (CM.Unsupported_Source_Construct
              (Path    => Path,
               Span    => Span,
               Message => Message));
      end if;
   end Reject_Unsupported_String_Use;

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
               Message => "expected assignment or call to a no-result function"));
      elsif Expr.Kind = CM.Expr_Call then
         Name := FT.To_UString (Flatten_Name (Expr.Callee));
         if Has_Function (Functions, UString_Value (Name))
           and then not Get_Function (Functions, UString_Value (Name)).Has_Return_Type
         then
            return Expr;
         end if;
      elsif Expr.Kind = CM.Expr_Ident or else Expr.Kind = CM.Expr_Select then
         Name := FT.To_UString (Flatten_Name (Expr));
         if Has_Function (Functions, UString_Value (Name))
           and then not Get_Function (Functions, UString_Value (Name)).Has_Return_Type
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
            Message => "expected assignment or call to a no-result function"));
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

      if not Has_Type (Channel_Env, Name) then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path,
               Span    => Expr.Span,
               Message => "unknown channel `" & Name & "`"));
      end if;

      return Get_Type (Channel_Env, Name);
   end Channel_Element_Type;

   function Contains_Label_Like_Syntax (Name : String) return Boolean is
   begin
      for Ch of Name loop
         if Ch = '.' or else Ch = '(' then
            return True;
         end if;
      end loop;
      return False;
   end Contains_Label_Like_Syntax;

   function Looks_Like_Unsupported_Statement_Label
     (Decl      : CM.Object_Decl;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map) return Boolean
   is
      Type_Name : constant String := UString_Value (Decl.Decl_Type.Name);
   begin
      if Decl.Decl_Type.Kind /= CM.Type_Spec_Name
        or else Natural (Decl.Names.Length) /= 1
        or else Has_Type (Type_Env, Type_Name)
      then
         return False;
      end if;

      return
        Has_Type (Var_Types, Type_Name)
        or else Has_Function (Functions, Type_Name)
        or else Contains_Label_Like_Syntax (Type_Name);
   end Looks_Like_Unsupported_Statement_Label;

   function Normalize_Object_Decl
     (Decl      : CM.Object_Decl;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Const_Env : Static_Value_Maps.Map;
      Path      : String) return CM.Object_Decl
   is
      Result : CM.Object_Decl := Decl;
   begin
      if Looks_Like_Unsupported_Statement_Label (Decl, Var_Types, Functions, Type_Env) then
         Raise_Diag
           (CM.Unsupported_Source_Construct
              (Path    => Path,
               Span    => Decl.Span,
               Message => "named statement labels are outside the current PR08.1 concurrency subset"));
      end if;

      Result.Type_Info := Resolve_Decl_Type (Decl, Type_Env, Const_Env, Path);
      if Is_String_Type (Result.Type_Info, Type_Env) then
         if not Decl.Is_Constant then
            Raise_Diag
              (CM.Unsupported_Source_Construct
                 (Path    => Path,
                  Span    => Decl.Decl_Type.Span,
                  Message => "mutable objects of type String are outside the current PR11.2 text subset"));
         elsif not Decl.Has_Initializer then
            Raise_Diag
              (CM.Source_Frontend_Error
                 (Path    => Path,
                  Span    => Decl.Span,
                  Message => "constant String declarations require initializers"));
         end if;
      end if;
      Result.Is_Constant := Decl.Is_Constant;
      if Decl.Has_Initializer and then Decl.Initializer /= null then
         Result.Initializer :=
           Normalize_Expr_Checked
             (Decl.Initializer, Var_Types, Functions, Type_Env, Path);
         if Is_String_Type (Result.Type_Info, Type_Env)
           and then not Compatible_Type
             (Expr_Type (Result.Initializer, Var_Types, Functions, Type_Env),
              Result.Type_Info,
              Type_Env)
         then
            Raise_Diag
              (CM.Source_Frontend_Error
                 (Path    => Path,
                  Span    => Result.Initializer.Span,
                  Message => "object initializer type does not match declared type"));
         end if;
      end if;
      return Result;
   end Normalize_Object_Decl;

   function Is_Read_Only_Imported_Target
     (Expr             : CM.Expr_Access;
      Imported_Objects : Type_Maps.Map) return Boolean
   is
      Name : constant String := Flatten_Name (Expr);
   begin
      if Expr = null then
         return False;
      elsif Name /= "" and then Has_Type (Imported_Objects, Name) then
         return True;
      end if;

      case Expr.Kind is
         when CM.Expr_Select | CM.Expr_Resolved_Index =>
            return Is_Read_Only_Imported_Target (Expr.Prefix, Imported_Objects);
         when CM.Expr_Conversion =>
            return Is_Read_Only_Imported_Target (Expr.Inner, Imported_Objects);
         when others =>
            return False;
      end case;
   end Is_Read_Only_Imported_Target;

   function Is_Local_Constant_Target
     (Expr            : CM.Expr_Access;
      Local_Constants : Type_Maps.Map) return Boolean
   is
   begin
      if Expr = null then
         return False;
      end if;

      case Expr.Kind is
         when CM.Expr_Ident =>
            declare
               Name : constant String := Root_Name (Expr);
            begin
               return Name /= "" and then Has_Type (Local_Constants, Name);
            end;
         when CM.Expr_Select =>
            if UString_Value (Expr.Selector) = "all" then
               return False;
            end if;
            return Is_Local_Constant_Target (Expr.Prefix, Local_Constants);
         when CM.Expr_Resolved_Index =>
            return Is_Local_Constant_Target (Expr.Prefix, Local_Constants);
         when CM.Expr_Conversion =>
            return Is_Local_Constant_Target (Expr.Inner, Local_Constants);
         when others =>
            return False;
      end case;
   end Is_Local_Constant_Target;

   procedure Ensure_Writable_Target
     (Expr             : CM.Expr_Access;
      Imported_Objects : Type_Maps.Map;
      Local_Constants  : Type_Maps.Map;
      Path             : String;
      Message          : String) is
      Name : constant String := Root_Name (Expr);
   begin
      if Expr /= null and then Expr.Kind = CM.Expr_Tuple then
         for Item of Expr.Elements loop
            Ensure_Writable_Target
              (Item,
               Imported_Objects,
               Local_Constants,
               Path,
               Message);
         end loop;
      elsif Is_Read_Only_Imported_Target (Expr, Imported_Objects) then
         Raise_Diag
           (CM.Unsupported_Source_Construct
              (Path    => Path,
               Span    => (if Expr = null then FT.Null_Span else Expr.Span),
               Message => Message));
      elsif Is_Local_Constant_Target (Expr, Local_Constants) then
         Raise_Diag
           (CM.Write_To_Constant
              (Path    => Path,
               Span    => (if Expr = null then FT.Null_Span else Expr.Span),
               Message =>
                 "assignment target rooted in constant `"
                 & (if Name'Length = 0 then "<unknown>" else Name)
                 & "` is not writable"));
      end if;
   end Ensure_Writable_Target;

   function Normalize_Statement
     (Stmt        : CM.Statement_Access;
      Var_Types   : Type_Maps.Map;
      Functions   : Function_Maps.Map;
      Type_Env    : Type_Maps.Map;
      Channel_Env : Type_Maps.Map;
      Imported_Objects : Type_Maps.Map;
      Local_Constants : Type_Maps.Map;
      Local_Static_Constants : Static_Value_Maps.Map;
      Path        : String) return CM.Statement_Access;

   function Normalize_Statement_List
     (Statements  : CM.Statement_Access_Vectors.Vector;
      Var_Types   : Type_Maps.Map;
      Functions   : Function_Maps.Map;
      Type_Env    : Type_Maps.Map;
      Channel_Env : Type_Maps.Map;
      Imported_Objects : Type_Maps.Map;
      Local_Constants : Type_Maps.Map;
      Local_Static_Constants : Static_Value_Maps.Map;
      Path        : String) return CM.Statement_Access_Vectors.Vector
   is
      Result      : CM.Statement_Access_Vectors.Vector;
      Local_Types : Type_Maps.Map := Var_Types;
      Current_Constants : Type_Maps.Map := Local_Constants;
      Current_Static_Constants : Static_Value_Maps.Map := Local_Static_Constants;
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
                 Imported_Objects,
                 Current_Constants,
                 Current_Static_Constants,
                 Path);
         begin
            Result.Append (Normalized);
            if Normalized.Kind = CM.Stmt_Object_Decl then
               for Name of Normalized.Decl.Names loop
                  Put_Type (Local_Types, UString_Value (Name), Normalized.Decl.Type_Info);
                  Update_Constant_Visibility
                    (Current_Constants,
                     UString_Value (Name),
                     Normalized.Decl.Type_Info,
                     Normalized.Decl.Is_Constant);
                  Update_Static_Constant_Visibility
                    (Current_Static_Constants,
                     UString_Value (Name),
                     Normalized.Decl.Initializer,
                     Normalized.Decl.Is_Constant,
                     Current_Static_Constants);
               end loop;
            elsif Normalized.Kind = CM.Stmt_Destructure_Decl then
               declare
                  Tuple_Type : constant GM.Type_Descriptor := Base_Type (Normalized.Destructure.Type_Info, Type_Env);
               begin
                  for Index in Normalized.Destructure.Names.First_Index .. Normalized.Destructure.Names.Last_Index loop
                     Put_Type
                       (Local_Types,
                        UString_Value (Normalized.Destructure.Names (Index)),
                        Resolve_Type
                          (UString_Value (Tuple_Type.Tuple_Element_Types (Index)),
                           Type_Env,
                           "",
                           FT.Null_Span));
                     Remove_Type (Current_Constants, UString_Value (Normalized.Destructure.Names (Index)));
                     Remove_Static_Value
                       (Current_Static_Constants,
                        UString_Value (Normalized.Destructure.Names (Index)));
                  end loop;
               end;
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
      Imported_Objects : Type_Maps.Map;
      Local_Constants : Type_Maps.Map;
      Local_Static_Constants : Static_Value_Maps.Map;
      Path        : String) return CM.Statement_Access
   is
      Result         : constant CM.Statement_Access := new CM.Statement'(Stmt.all);
      Local_Types    : Type_Maps.Map := Var_Types;
      Current_Constants : Type_Maps.Map := Local_Constants;
      Current_Static_Constants : Static_Value_Maps.Map := Local_Static_Constants;
      Loop_Type      : GM.Type_Descriptor;
      Decl_Type      : GM.Type_Descriptor;
      Channel_Type   : GM.Type_Descriptor;
      Success_Type   : GM.Type_Descriptor;
      Target_Type    : GM.Type_Descriptor;
   begin
      case Stmt.Kind is
         when CM.Stmt_Object_Decl =>
            Result.Decl :=
              Normalize_Object_Decl
                (Stmt.Decl, Var_Types, Functions, Type_Env, Local_Static_Constants, Path);

         when CM.Stmt_Destructure_Decl =>
            Result.Destructure := Stmt.Destructure;
            Result.Destructure.Type_Info :=
              Resolve_Type_Spec
                (Stmt.Destructure.Decl_Type, Type_Env, Local_Static_Constants, Path);
            if not Is_Tuple_Type (Result.Destructure.Type_Info, Type_Env) then
               Raise_Diag
                 (CM.Unsupported_Source_Construct
                    (Path    => Path,
                     Span    => Stmt.Destructure.Decl_Type.Span,
                     Message => "destructuring declarations currently require a tuple type"));
            end if;
            if not Stmt.Destructure.Has_Initializer or else Stmt.Destructure.Initializer = null then
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path,
                     Span    => Stmt.Destructure.Span,
                     Message => "destructuring declarations require an initializer"));
            end if;
            Result.Destructure.Initializer :=
              Normalize_Expr_Checked
                (Stmt.Destructure.Initializer, Var_Types, Functions, Type_Env, Path);
            if not Compatible_Type
              (Expr_Type (Result.Destructure.Initializer, Var_Types, Functions, Type_Env),
               Result.Destructure.Type_Info,
               Type_Env)
            then
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path,
                     Span    => Result.Destructure.Initializer.Span,
                     Message => "destructuring initializer type does not match declared tuple type"));
            end if;
            declare
               Tuple_Type : constant GM.Type_Descriptor := Base_Type (Result.Destructure.Type_Info, Type_Env);
            begin
               if Natural (Result.Destructure.Names.Length) /=
                 Natural (Tuple_Type.Tuple_Element_Types.Length)
               then
                  Raise_Diag
                    (CM.Source_Frontend_Error
                       (Path    => Path,
                        Span    => Result.Destructure.Span,
                        Message => "destructuring declaration arity does not match tuple type"));
               end if;
            end;

         when CM.Stmt_Assign =>
            Result.Target := Normalize_Expr_Checked (Stmt.Target, Var_Types, Functions, Type_Env, Path);
            if not Is_Assignable_Target (Result.Target) then
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path,
                     Span    => Result.Target.Span,
                     Message => "assignment target must be a writable name"));
            end if;
            Ensure_Writable_Target
              (Result.Target,
               Imported_Objects,
               Local_Constants,
               Path,
               "assignment to imported package-qualified objects is outside the current PR08.3 interface subset");
            Result.Value := Normalize_Expr_Checked (Stmt.Value, Var_Types, Functions, Type_Env, Path);

         when CM.Stmt_Return =>
            if Stmt.Value /= null then
               Result.Value := Normalize_Expr_Checked (Stmt.Value, Var_Types, Functions, Type_Env, Path);
            end if;

         when CM.Stmt_If =>
            Result.Condition :=
              Normalize_Expr_Checked (Stmt.Condition, Var_Types, Functions, Type_Env, Path);
            Result.Then_Stmts :=
              Normalize_Statement_List
                (Stmt.Then_Stmts,
                 Var_Types,
                 Functions,
                 Type_Env,
                 Channel_Env,
                 Imported_Objects,
                 Local_Constants,
                 Local_Static_Constants,
                 Path);
            Result.Elsifs.Clear;
            for Part of Stmt.Elsifs loop
               declare
                  New_Part : CM.Elsif_Part := Part;
               begin
                  New_Part.Condition :=
                    Normalize_Expr_Checked (Part.Condition, Var_Types, Functions, Type_Env, Path);
                  New_Part.Statements :=
                    Normalize_Statement_List
                      (Part.Statements,
                       Var_Types,
                       Functions,
                       Type_Env,
                       Channel_Env,
                       Imported_Objects,
                       Local_Constants,
                       Local_Static_Constants,
                       Path);
                  Result.Elsifs.Append (New_Part);
               end;
            end loop;
            if Stmt.Has_Else then
               Result.Else_Stmts :=
                 Normalize_Statement_List
                   (Stmt.Else_Stmts,
                    Var_Types,
                    Functions,
                    Type_Env,
                    Channel_Env,
                    Imported_Objects,
                    Local_Constants,
                    Local_Static_Constants,
                    Path);
            end if;

         when CM.Stmt_While =>
            Result.Condition :=
              Normalize_Expr_Checked (Stmt.Condition, Var_Types, Functions, Type_Env, Path);
            Result.Body_Stmts :=
              Normalize_Statement_List
                (Stmt.Body_Stmts,
                 Var_Types,
                 Functions,
                 Type_Env,
                 Channel_Env,
                 Imported_Objects,
                 Local_Constants,
                 Local_Static_Constants,
                 Path);

         when CM.Stmt_Loop =>
            Result.Body_Stmts :=
              Normalize_Statement_List
                (Stmt.Body_Stmts,
                 Var_Types,
                 Functions,
                 Type_Env,
                 Channel_Env,
                 Imported_Objects,
                 Local_Constants,
                 Local_Static_Constants,
                 Path);

         when CM.Stmt_Exit =>
            if Stmt.Condition /= null then
               Result.Condition :=
                 Normalize_Expr_Checked (Stmt.Condition, Var_Types, Functions, Type_Env, Path);
            end if;

         when CM.Stmt_For =>
            Result.Loop_Range := Stmt.Loop_Range;
            if Stmt.Loop_Range.Kind = CM.Range_Explicit then
               Result.Loop_Range.Low_Expr :=
                 Normalize_Expr_Checked
                   (Stmt.Loop_Range.Low_Expr, Var_Types, Functions, Type_Env, Path);
               Result.Loop_Range.High_Expr :=
                 Normalize_Expr_Checked
                   (Stmt.Loop_Range.High_Expr, Var_Types, Functions, Type_Env, Path);
               Loop_Type.Name := FT.To_UString ("Integer");
               Loop_Type.Kind := FT.To_UString ("integer");
            else
               Result.Loop_Range.Name_Expr :=
                 Normalize_Expr_Checked
                   (Stmt.Loop_Range.Name_Expr, Var_Types, Functions, Type_Env, Path);
               Loop_Type :=
                 Resolve_Type (Flatten_Name (Stmt.Loop_Range.Name_Expr), Type_Env, Path, Stmt.Span);
            end if;
            Put_Type (Local_Types, UString_Value (Stmt.Loop_Var), Loop_Type);
            Remove_Type (Current_Constants, UString_Value (Stmt.Loop_Var));
            Remove_Static_Value (Current_Static_Constants, UString_Value (Stmt.Loop_Var));
            Result.Body_Stmts :=
              Normalize_Statement_List
                (Stmt.Body_Stmts,
                 Local_Types,
                 Functions,
                 Type_Env,
                 Channel_Env,
                 Imported_Objects,
                 Current_Constants,
                 Current_Static_Constants,
                 Path);

         when CM.Stmt_Block =>
            Result.Declarations.Clear;
            for Decl of Stmt.Declarations loop
               declare
                  New_Decl : constant CM.Object_Decl :=
                    Normalize_Object_Decl
                      (Decl, Local_Types, Functions, Type_Env, Current_Static_Constants, Path);
               begin
                  Result.Declarations.Append (New_Decl);
                  Decl_Type := New_Decl.Type_Info;
                  for Name of Decl.Names loop
                     Put_Type (Local_Types, UString_Value (Name), Decl_Type);
                     Update_Constant_Visibility
                       (Current_Constants,
                        UString_Value (Name),
                        Decl_Type,
                        New_Decl.Is_Constant);
                     Update_Static_Constant_Visibility
                       (Current_Static_Constants,
                        UString_Value (Name),
                        New_Decl.Initializer,
                        New_Decl.Is_Constant,
                        Current_Static_Constants);
                  end loop;
               end;
            end loop;
            Result.Body_Stmts :=
              Normalize_Statement_List
                (Stmt.Body_Stmts,
                 Local_Types,
                 Functions,
                 Type_Env,
                 Channel_Env,
                 Imported_Objects,
                 Current_Constants,
                 Current_Static_Constants,
                 Path);

         when CM.Stmt_Call =>
            Result.Call :=
              Normalize_Procedure_Call
                (Normalize_Expr_Checked (Stmt.Call, Var_Types, Functions, Type_Env, Path),
                 Functions,
                 Path);

         when CM.Stmt_Send | CM.Stmt_Try_Send =>
            Result.Channel_Name :=
              Normalize_Expr_Checked (Stmt.Channel_Name, Var_Types, Functions, Type_Env, Path);
            Result.Value := Normalize_Expr_Checked (Stmt.Value, Var_Types, Functions, Type_Env, Path);
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
                 Normalize_Expr_Checked (Stmt.Success_Var, Var_Types, Functions, Type_Env, Path);
               if not Is_Assignable_Target (Result.Success_Var) then
                  Raise_Diag
                    (CM.Source_Frontend_Error
                       (Path    => Path,
                        Span    => Result.Success_Var.Span,
                        Message => "try_send success variable must be a writable name"));
               end if;
               Ensure_Writable_Target
                 (Result.Success_Var,
                  Imported_Objects,
                  Local_Constants,
                  Path,
                  "assignment to imported package-qualified objects is outside the current PR08.3 interface subset");
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
              Normalize_Expr_Checked (Stmt.Channel_Name, Var_Types, Functions, Type_Env, Path);
            Result.Target := Normalize_Expr_Checked (Stmt.Target, Var_Types, Functions, Type_Env, Path);
            if not Is_Assignable_Target (Result.Target) then
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path,
                     Span    => Result.Target.Span,
                     Message => "receive target must be a writable name"));
            end if;
            Ensure_Writable_Target
              (Result.Target,
               Imported_Objects,
               Local_Constants,
               Path,
               "assignment to imported package-qualified objects is outside the current PR08.3 interface subset");
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
                 Normalize_Expr_Checked (Stmt.Success_Var, Var_Types, Functions, Type_Env, Path);
               if not Is_Assignable_Target (Result.Success_Var) then
                  Raise_Diag
                    (CM.Source_Frontend_Error
                       (Path    => Path,
                        Span    => Result.Success_Var.Span,
                        Message => "try_receive success variable must be a writable name"));
               end if;
               Ensure_Writable_Target
                 (Result.Success_Var,
                  Imported_Objects,
                  Local_Constants,
                  Path,
                  "assignment to imported package-qualified objects is outside the current PR08.3 interface subset");
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
            Result.Value := Normalize_Expr_Checked (Stmt.Value, Var_Types, Functions, Type_Env, Path);
            if not Is_Duration_Compatible
              (Expr_Type (Result.Value, Var_Types, Functions, Type_Env), Type_Env)
            then
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path,
                     Span    => Result.Value.Span,
                     Message => "relative delay expression must be duration-compatible"));
            end if;

         when CM.Stmt_Case =>
            declare
               Scrutinee_Type : GM.Type_Descriptor;
            begin
               Result.Case_Expr :=
                 Normalize_Expr_Checked (Stmt.Case_Expr, Var_Types, Functions, Type_Env, Path);
               Scrutinee_Type :=
                 Expr_Type (Result.Case_Expr, Var_Types, Functions, Type_Env);
               if not Is_Discrete_Case_Type (Scrutinee_Type, Type_Env) then
                  Raise_Diag
                    (CM.Unsupported_Source_Construct
                       (Path    => Path,
                        Span    => Result.Case_Expr.Span,
                        Message =>
                          "PR11.2 case expressions are limited to Boolean, integer, and Character"));
               end if;

               Result.Case_Arms.Clear;
               for Arm of Stmt.Case_Arms loop
                  declare
                     New_Arm     : CM.Case_Arm := Arm;
                     Choice_Type : GM.Type_Descriptor;
                  begin
                     if Arm.Is_Others then
                        New_Arm.Choice := null;
                     else
                        New_Arm.Choice :=
                          Normalize_Expr_Checked (Arm.Choice, Var_Types, Functions, Type_Env, Path);
                        Choice_Type :=
                          Expr_Type (New_Arm.Choice, Var_Types, Functions, Type_Env);
                        if not Case_Choice_Compatible (Scrutinee_Type, Choice_Type, Type_Env) then
                           Raise_Diag
                             (CM.Source_Frontend_Error
                                (Path    => Path,
                                 Span    => New_Arm.Choice.Span,
                                 Message =>
                                   "case arm choice type does not match case expression type"));
                        end if;
                     end if;

                     New_Arm.Statements :=
                       Normalize_Statement_List
                         (Arm.Statements,
                          Var_Types,
                          Functions,
                          Type_Env,
                          Channel_Env,
                          Imported_Objects,
                          Local_Constants,
                          Local_Static_Constants,
                          Path);
                     Result.Case_Arms.Append (New_Arm);
                  end;
               end loop;
            end;

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
                             Normalize_Expr_Checked
                               (Arm.Channel_Data.Channel_Name,
                                Var_Types,
                                Functions,
                                Type_Env,
                                Path);
                           Channel_Type :=
                             Channel_Element_Type
                               (New_Arm.Channel_Data.Channel_Name,
                                Channel_Env,
                                Path);
                           New_Arm.Channel_Data.Type_Info :=
                             Resolve_Type_Spec
                               (Arm.Channel_Data.Subtype_Mark, Type_Env, Local_Static_Constants, Path);
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
                           Remove_Type
                             (Current_Constants,
                              UString_Value (Arm.Channel_Data.Variable_Name));
                           declare
                              Arm_Static_Constants : Static_Value_Maps.Map := Local_Static_Constants;
                           begin
                              Remove_Static_Value
                                (Arm_Static_Constants,
                                 UString_Value (Arm.Channel_Data.Variable_Name));
                              New_Arm.Channel_Data.Statements :=
                                Normalize_Statement_List
                                  (Arm.Channel_Data.Statements,
                                   Arm_Types,
                                   Functions,
                                   Type_Env,
                                   Channel_Env,
                                   Imported_Objects,
                                   Local_Constants,
                                   Arm_Static_Constants,
                                   Path);
                           end;
                        when CM.Select_Arm_Delay =>
                           Delay_Arms := Delay_Arms + 1;
                           New_Arm.Delay_Data.Duration_Expr :=
                             Normalize_Expr_Checked
                               (Arm.Delay_Data.Duration_Expr,
                                Var_Types,
                                Functions,
                                Type_Env,
                                Path);
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
                                Imported_Objects,
                                Local_Constants,
                                Local_Static_Constants,
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
      Const_Env : Static_Value_Maps.Map;
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
            Result.Low :=
              Long_Long_Integer
                (Literal_Value
                   (Decl.Low_Expr,
                    Const_Env,
                    Path,
                    "type bounds must be integer literals or constant references"));
            Result.Has_High := True;
            Result.High :=
              Long_Long_Integer
                (Literal_Value
                   (Decl.High_Expr,
                    Const_Env,
                    Path,
                    "type bounds must be integer literals or constant references"));
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
            declare
               Component_Type : constant GM.Type_Descriptor :=
                 Resolve_Type_Spec (Decl.Component_Type, Type_Env, Const_Env, Path);
            begin
               Reject_Unsupported_String_Use
                 (Component_Type,
                  Type_Env,
                  Path,
                  Decl.Component_Type.Span,
                  "array component types of String are outside the current PR11.2 text subset");
               Result.Component_Type := Component_Type.Name;
            end;
            Result.Unconstrained := Decl.Kind = CM.Type_Decl_Unconstrained_Array;
         when CM.Type_Decl_Record =>
            Result.Kind := FT.To_UString ("record");
            declare
               Decl_Discriminants : CM.Discriminant_Spec_Vectors.Vector := Decl.Discriminants;
            begin
               if Decl_Discriminants.Is_Empty and then Decl.Has_Discriminant then
                  Decl_Discriminants.Append (Decl.Discriminant);
               end if;
               for Disc_Spec of Decl_Discriminants loop
                  declare
                     Disc_Type    : constant GM.Type_Descriptor :=
                       Resolve_Type_Spec (Disc_Spec.Disc_Type, Type_Env, Const_Env, Path);
                     Disc_Desc    : GM.Discriminant_Descriptor;
                     Static_Value : CM.Static_Value;
                  begin
                     if not Is_Discrete_Case_Type (Disc_Type, Type_Env) then
                        Raise_Diag
                          (CM.Unsupported_Source_Construct
                             (Path    => Path,
                              Span    => Disc_Spec.Span,
                              Message => "PR11.3 discriminants currently support only boolean, character, and integer-family types"));
                     end if;
                     Disc_Desc.Name := Disc_Spec.Name;
                     Disc_Desc.Type_Name := Disc_Type.Name;
                     if Disc_Spec.Has_Default then
                        if not Try_Static_Value (Disc_Spec.Default_Expr, Const_Env, Static_Value) then
                           Raise_Diag
                             (CM.Source_Frontend_Error
                                (Path    => Path,
                                 Span    => Disc_Spec.Span,
                                 Message => "discriminant defaults must be static scalar values"));
                        elsif not Scalar_Value_Compatible (Static_Value, Disc_Type, Type_Env) then
                           Raise_Diag
                             (CM.Source_Frontend_Error
                                (Path    => Path,
                                 Span    => Disc_Spec.Span,
                                 Message => "discriminant default value does not match discriminant type"));
                        end if;
                        Disc_Desc.Has_Default := True;
                        Disc_Desc.Default_Value := To_Scalar_Value (Static_Value);
                     end if;
                     Result.Discriminants.Append (Disc_Desc);
                  end;
               end loop;
               if not Result.Discriminants.Is_Empty then
                  Result.Has_Discriminant := True;
                  Result.Discriminant_Name := Result.Discriminants (Result.Discriminants.First_Index).Name;
                  Result.Discriminant_Type := Result.Discriminants (Result.Discriminants.First_Index).Type_Name;
                  if Result.Discriminants (Result.Discriminants.First_Index).Has_Default
                    and then Result.Discriminants (Result.Discriminants.First_Index).Default_Value.Kind =
                      GM.Scalar_Value_Boolean
                  then
                     Result.Has_Discriminant_Default := True;
                     Result.Discriminant_Default_Bool :=
                       Result.Discriminants (Result.Discriminants.First_Index).Default_Value.Bool_Value;
                  end if;
               end if;
            end;
            for Field_Decl of Decl.Components loop
               for Name of Field_Decl.Names loop
                  Item.Name := Name;
                  declare
                     Field_Type : constant GM.Type_Descriptor :=
                       Resolve_Type_Spec (Field_Decl.Field_Type, Type_Env, Const_Env, Path);
                  begin
                     Reject_Unsupported_String_Use
                       (Field_Type,
                        Type_Env,
                        Path,
                        Field_Decl.Field_Type.Span,
                        "record fields of type String are outside the current PR11.2 text subset");
                     Item.Type_Name := Field_Type.Name;
                  end;
                  Result.Fields.Append (Item);
               end loop;
            end loop;
            if not Decl.Variants.Is_Empty then
               declare
                  Control_Type : GM.Type_Descriptor;
                  Found_Control : Boolean := False;
               begin
                  if Result.Discriminants.Is_Empty then
                     Raise_Diag
                       (CM.Source_Frontend_Error
                          (Path    => Path,
                           Span    => Decl.Span,
                           Message => "variant parts require declared discriminants"));
                  end if;
                  Result.Variant_Discriminant_Name := Decl.Variant_Discriminant_Name;
                  for Disc of Result.Discriminants loop
                     if UString_Value (Disc.Name) = UString_Value (Decl.Variant_Discriminant_Name) then
                        Control_Type :=
                          Resolve_Type (UString_Value (Disc.Type_Name), Type_Env, Path, Decl.Span);
                        Found_Control := True;
                        exit;
                     end if;
                  end loop;
                  if not Found_Control then
                     Raise_Diag
                       (CM.Source_Frontend_Error
                          (Path    => Path,
                           Span    => Decl.Span,
                           Message =>
                             "variant part discriminant '" & UString_Value (Decl.Variant_Discriminant_Name)
                             & "' is not declared on the record"));
                  end if;

                  for Alternative of Decl.Variants loop
                     declare
                        Choice_Value : CM.Static_Value := (others => <>);
                        Variant_Choice : GM.Scalar_Value;
                     begin
                        if not Alternative.Is_Others then
                           if not Try_Static_Value (Alternative.Choice_Expr, Const_Env, Choice_Value) then
                              Raise_Diag
                                (CM.Source_Frontend_Error
                                   (Path    => Path,
                                    Span    => Alternative.Span,
                                    Message => "variant choices must be static scalar values"));
                           elsif not Scalar_Value_Compatible (Choice_Value, Control_Type, Type_Env) then
                              Raise_Diag
                                (CM.Source_Frontend_Error
                                   (Path    => Path,
                                    Span    => Alternative.Span,
                                    Message => "variant choice does not match discriminant type"));
                           end if;
                           Variant_Choice := To_Scalar_Value (Choice_Value);
                        end if;

                        for Field_Decl of Alternative.Components loop
                           for Name of Field_Decl.Names loop
                              Item.Name := Name;
                              declare
                                 Field_Type : constant GM.Type_Descriptor :=
                                   Resolve_Type_Spec (Field_Decl.Field_Type, Type_Env, Const_Env, Path);
                              begin
                                 Reject_Unsupported_String_Use
                                   (Field_Type,
                                    Type_Env,
                                    Path,
                                    Field_Decl.Field_Type.Span,
                                    "record fields of type String are outside the current PR11.2 text subset");
                                 Item.Type_Name := Field_Type.Name;
                              end;
                              Result.Fields.Append (Item);
                              declare
                                 Variant_Field : GM.Variant_Field;
                              begin
                                 Variant_Field.Name := Name;
                                 Variant_Field.Type_Name := Item.Type_Name;
                                 Variant_Field.Is_Others := Alternative.Is_Others;
                                 Variant_Field.Choice := Variant_Choice;
                                 if Variant_Choice.Kind = GM.Scalar_Value_Boolean then
                                    Variant_Field.When_True := Variant_Choice.Bool_Value;
                                 end if;
                                 Result.Variant_Fields.Append (Variant_Field);
                              end;
                           end loop;
                        end loop;
                     end;
                  end loop;
               end;
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
      Put_Type (Type_Env, UString_Value (Result.Name), Result);
      return Result;
   end Resolve_Type_Declaration;

   function Register_Function
     (Decl      : CM.Subprogram_Body;
      Type_Env  : Type_Maps.Map;
      Const_Env : Static_Value_Maps.Map;
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
              Resolve_Type_Spec (Param.Param_Type, Type_Env, Const_Env, Path);
         begin
            if Is_String_Type (Param_Type, Type_Env)
              and then UString_Value (Param.Mode) in "out" | "in out"
            then
               Raise_Diag
                 (CM.Unsupported_Source_Construct
                    (Path    => Path,
                     Span    => Param.Param_Type.Span,
                     Message => "string parameters currently support mode `in` only"));
            end if;
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
         Result.Return_Type :=
           Resolve_Type_Spec (Decl.Spec.Return_Type, Type_Env, Const_Env, Path);
      end if;
      return Result;
   end Register_Function;

   function Resolve_Channel_Declaration
     (Decl     : CM.Channel_Decl;
      Type_Env : Type_Maps.Map;
      Const_Env : Static_Value_Maps.Map;
      Path     : String) return CM.Resolved_Channel_Decl
   is
      Result    : CM.Resolved_Channel_Decl;
      Type_Info : constant GM.Type_Descriptor :=
        Resolve_Type_Spec (Decl.Element_Type, Type_Env, Const_Env, Path);
   begin
      Reject_Unsupported_String_Use
        (Type_Info,
         Type_Env,
         Path,
         Decl.Element_Type.Span,
         "channel element types of String are outside the current PR11.2 text subset");

      if not Is_Definite_Type (Type_Info, Type_Env) then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path,
               Span    => Decl.Element_Type.Span,
               Message => "channel element type must be definite"));
      end if;

      if Contains_Channel_Access_Subcomponent (Type_Info, Type_Env) then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path,
               Span    => Decl.Element_Type.Span,
               Message =>
                 "channel element type shall not be an access type or a composite type containing an access-type subcomponent"));
      end if;

      Result.Is_Public := Decl.Is_Public;
      Result.Name := Decl.Name;
      Result.Element_Type := Type_Info;
      Result.Capacity :=
        Long_Long_Integer
          (Literal_Value
             (Decl.Capacity,
              Const_Env,
              Path,
              "channel capacity must be integer literals or constant references"));
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
            when CM.Stmt_Case =>
               for Arm of Stmt.Case_Arms loop
                  Validate_Task_Nontermination
                    (Arm.Statements, Path, Task_Name, Loop_Depth);
               end loop;
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
     (Unit        : CM.Parsed_Unit;
      Search_Dirs : FT.UString_Vectors.Vector := FT.UString_Vectors.Empty_Vector)
      return CM.Resolve_Result
   is
      Type_Env         : Type_Maps.Map;
      Functions        : Function_Maps.Map;
      Package_Vars     : Type_Maps.Map;
      Channel_Env      : Type_Maps.Map;
      Const_Env        : Static_Value_Maps.Map;
      Imported_Objects : Type_Maps.Map;
      Task_Priorities  : Task_Priority_Vectors.Vector;
      Result           : CM.Resolved_Unit;

      procedure Add_Imported_Interface (Item : SI.Loaded_Interface) is
         Package_Name : constant String := UString_Value (Item.Package_Name);
      begin
         for Type_Item of Item.Types loop
            declare
               Info : constant GM.Type_Descriptor :=
                 Qualify_Type_Info (Type_Item, Package_Name);
            begin
               Put_Type (Type_Env, UString_Value (Info.Name), Info);
               Result.Imported_Types.Append (Info);
            end;
         end loop;

         for Type_Item of Item.Subtypes loop
            declare
               Info : constant GM.Type_Descriptor :=
                 Qualify_Type_Info (Type_Item, Package_Name);
            begin
               Put_Type (Type_Env, UString_Value (Info.Name), Info);
               Result.Imported_Types.Append (Info);
            end;
         end loop;

         for Channel_Item of Item.Channels loop
            declare
               Qualified : CM.Resolved_Channel_Decl := Channel_Item;
            begin
               Qualified.Name :=
                 FT.To_UString (Qualify_Name (Package_Name, UString_Value (Channel_Item.Name)));
               Qualified.Element_Type :=
                 Qualify_Type_Info (Channel_Item.Element_Type, Package_Name);
               Put_Type
                 (Channel_Env,
                  UString_Value (Qualified.Name),
                  Qualified.Element_Type);
               Result.Imported_Channels.Append (Qualified);
            end;
         end loop;

         for Object_Item of Item.Objects loop
            declare
               Qualified_Name : constant String :=
                 Qualify_Name (Package_Name, UString_Value (Object_Item.Name));
               Qualified_Type : constant GM.Type_Descriptor :=
                 Qualify_Type_Info (Object_Item.Type_Info, Package_Name);
            begin
               Put_Type (Imported_Objects, Qualified_Name, Qualified_Type);
               if Object_Item.Is_Constant
                 and then Object_Item.Static_Info.Kind /= CM.Static_Value_None
               then
                  Put_Static_Value
                    (Const_Env,
                     Qualified_Name,
                     Object_Item.Static_Info);
               end if;
            end;
         end loop;

         for Subp_Item of Item.Subprograms loop
            declare
               Info : Function_Info;
               External : GM.External_Entry;
            begin
               Info.Name :=
                 FT.To_UString (Qualify_Name (Package_Name, UString_Value (Subp_Item.Name)));
               Info.Kind := Subp_Item.Kind;
               Info.Span := Subp_Item.Span;
               Info.Has_Return_Type := Subp_Item.Has_Return_Type;
               Info.Return_Is_Access_Def := Subp_Item.Return_Is_Access_Def;
               if Subp_Item.Has_Return_Type then
                  Info.Return_Type := Qualify_Type_Info (Subp_Item.Return_Type, Package_Name);
               end if;
               for Param of Subp_Item.Params loop
                  declare
                     Symbol : CM.Symbol := Param;
                     Local  : GM.Local_Entry;
                  begin
                     Symbol.Type_Info := Qualify_Type_Info (Param.Type_Info, Package_Name);
                     Info.Params.Append (Symbol);
                     Local.Name := Symbol.Name;
                     Local.Kind := FT.To_UString ("param");
                     Local.Mode := Symbol.Mode;
                     Local.Type_Info := Symbol.Type_Info;
                     Local.Span := Symbol.Span;
                     External.Params.Append (Local);
                  end;
               end loop;
               External.Name := Info.Name;
               External.Kind := Info.Kind;
               External.Signature := Subp_Item.Signature;
               External.Has_Return_Type := Subp_Item.Has_Return_Type;
               External.Return_Is_Access_Def := Subp_Item.Return_Is_Access_Def;
               External.Span := Subp_Item.Span;
               if Subp_Item.Has_Return_Type then
                  External.Return_Type := Qualify_Type_Info (Subp_Item.Return_Type, Package_Name);
               end if;
               External.Effect_Summary := Subp_Item.Effect_Summary;
               External.Channel_Summary := Subp_Item.Channel_Summary;
               Put_Function (Functions, UString_Value (Info.Name), Info);
               Result.Imported_Subprograms.Append (External);
            end;
         end loop;
      end Add_Imported_Interface;
   begin
      Add_Builtins (Type_Env);
      Add_Builtin_Functions (Functions);
      Result.Path := Unit.Path;
      Result.Package_Name := Unit.Package_Name;

      if not Unit.Withs.Is_Empty then
         declare
            Loaded : constant SI.Load_Result :=
              SI.Load_Dependencies
                (Search_Dirs => Search_Dirs,
                 Withs       => Unit.Withs,
                 Path        => UString_Value (Unit.Path));
         begin
            if not Loaded.Success then
               Raise_Diag (Loaded.Diagnostic);
            end if;
            for Item of Loaded.Interfaces loop
               Add_Imported_Interface (Item);
            end loop;
         end;
      end if;

      Package_Vars := Type_Env;
      if not Imported_Objects.Is_Empty then
         for Cursor in Imported_Objects.Iterate loop
            Put_Type
              (Package_Vars,
               Type_Maps.Key (Cursor),
               Type_Maps.Element (Cursor));
         end loop;
      end if;

      for Item of Unit.Items loop
         case Item.Kind is
            when CM.Item_Type_Decl =>
               declare
                  Info : constant GM.Type_Descriptor :=
                    Resolve_Type_Declaration
                      (Item.Type_Data,
                       Type_Env,
                       Const_Env,
                       UString_Value (Unit.Path));
               begin
                  if not Is_Builtin_Name (UString_Value (Info.Name)) then
                     Result.Types.Append (Info);
                  end if;
                  Put_Type (Package_Vars, UString_Value (Info.Name), Info);
               end;
            when CM.Item_Subtype_Decl =>
               declare
                  Base : constant GM.Type_Descriptor :=
                    Resolve_Type_Spec
                      (Item.Sub_Data.Subtype_Mark,
                       Type_Env,
                       Const_Env,
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
                  Put_Type (Type_Env, UString_Value (Info.Name), Info);
                  Put_Type (Package_Vars, UString_Value (Info.Name), Info);
                  Result.Types.Append (Info);
               end;
            when CM.Item_Channel =>
               declare
                  Channel_Decl : constant CM.Resolved_Channel_Decl :=
                    Resolve_Channel_Declaration
                      (Item.Chan_Data,
                       Type_Env,
                       Const_Env,
                       UString_Value (Unit.Path));
               begin
                  Result.Channels.Append (Channel_Decl);
                  Put_Type
                    (Channel_Env,
                     UString_Value (Channel_Decl.Name),
                     Channel_Decl.Element_Type);
               end;
            when CM.Item_Object_Decl =>
               declare
                  Normalized   : constant CM.Object_Decl :=
                    Normalize_Object_Decl
                      (Item.Obj_Data,
                       Package_Vars,
                       Functions,
                       Type_Env,
                       Const_Env,
                       UString_Value (Unit.Path));
                  Local_Decl   : CM.Resolved_Object_Decl;
                  Static_Value : CM.Static_Value;
               begin
                  Local_Decl.Names := Normalized.Names;
                  Local_Decl.Type_Info := Normalized.Type_Info;
                  Local_Decl.Is_Constant := Normalized.Is_Constant;
                  Local_Decl.Has_Initializer := Normalized.Has_Initializer;
                  Local_Decl.Span := Normalized.Span;
                  Local_Decl.Initializer := Normalized.Initializer;
                  if Local_Decl.Has_Initializer and then Local_Decl.Initializer /= null then
                     if Local_Decl.Is_Constant
                       and then Try_Static_Value (Local_Decl.Initializer, Const_Env, Static_Value)
                     then
                        Local_Decl.Static_Info := Static_Value;
                     end if;
                  end if;
                  Result.Objects.Append (Local_Decl);
                  for Name of Normalized.Names loop
                     Put_Type (Package_Vars, UString_Value (Name), Normalized.Type_Info);
                     if Local_Decl.Is_Constant
                       and then Local_Decl.Static_Info.Kind /= CM.Static_Value_None
                     then
                        Put_Static_Value
                          (Const_Env,
                           UString_Value (Name),
                           Local_Decl.Static_Info);
                     end if;
                  end loop;
               end;
            when CM.Item_Task =>
               declare
                  Priority_Info : Task_Priority_Info;
                  Priority_Expr : CM.Expr_Access := null;
                  Priority_Type : GM.Type_Descriptor;
               begin
                  Priority_Info.Priority := Default_Task_Priority;
                  if Item.Task_Data.Has_Explicit_Priority
                    and then Item.Task_Data.Priority /= null
                  then
                     Priority_Expr :=
                       Normalize_Expr_Checked
                         (Item.Task_Data.Priority,
                          Package_Vars,
                          Functions,
                          Type_Env,
                          UString_Value (Unit.Path));
                     Priority_Type := Expr_Type (Priority_Expr, Package_Vars, Functions, Type_Env);
                     if not Is_Integerish (Priority_Type, Type_Env) then
                        Raise_Diag
                          (CM.Source_Frontend_Error
                             (Path    => UString_Value (Unit.Path),
                              Span    => Priority_Expr.Span,
                              Message => "task priority expression must be integer"));
                     end if;
                     Priority_Info.Priority :=
                       Long_Long_Integer
                         (Literal_Value
                            (Priority_Expr,
                             Const_Env,
                             UString_Value (Unit.Path),
                             "task priority expression must be integer literals or constant references"));
                     if Priority_Info.Priority < Min_Task_Priority
                       or else Priority_Info.Priority > Max_Task_Priority
                     then
                        Raise_Diag
                          (CM.Source_Frontend_Error
                             (Path    => UString_Value (Unit.Path),
                              Span    => Priority_Expr.Span,
                              Message =>
                                "task priority must be within System.Any_Priority"));
                     end if;
                  end if;
                  Task_Priorities.Append (Priority_Info);
               end;
            when CM.Item_Subprogram =>
               declare
                  Info : constant Function_Info :=
                    Register_Function
                      (Item.Subp_Data,
                       Type_Env,
                       Const_Env,
                       UString_Value (Unit.Path));
               begin
                  Put_Function (Functions, UString_Value (Info.Name), Info);
               end;
            when others =>
               null;
         end case;
      end loop;

      for Item of Unit.Items loop
         if Item.Kind = CM.Item_Subprogram then
            declare
               Info         : constant Function_Info :=
                 Get_Function (Functions, UString_Value (Item.Subp_Data.Spec.Name));
               Subprogram   : CM.Resolved_Subprogram;
               Visible      : Type_Maps.Map := Package_Vars;
               Visible_Constants : Type_Maps.Map;
               Visible_Static_Constants : Static_Value_Maps.Map := Const_Env;
               Local_Decl   : CM.Resolved_Object_Decl;
            begin
               Subprogram.Name := Info.Name;
               Subprogram.Kind := Info.Kind;
               Subprogram.Params := Info.Params;
               Subprogram.Has_Return_Type := Info.Has_Return_Type;
               Subprogram.Return_Type := Info.Return_Type;
               Subprogram.Return_Is_Access_Def := Info.Return_Is_Access_Def;
               Subprogram.Span := Info.Span;

               for Object_Decl of Result.Objects loop
                  if Object_Decl.Is_Constant then
                     for Name of Object_Decl.Names loop
                        Put_Type
                          (Visible_Constants,
                           UString_Value (Name),
                           Object_Decl.Type_Info);
                     end loop;
                  end if;
               end loop;

               for Param of Info.Params loop
                  Put_Type (Visible, UString_Value (Param.Name), Param.Type_Info);
                  Remove_Type (Visible_Constants, UString_Value (Param.Name));
                  Remove_Static_Value (Visible_Static_Constants, UString_Value (Param.Name));
               end loop;

               for Decl of Item.Subp_Data.Declarations loop
                  declare
                     Normalized : constant CM.Object_Decl :=
                       Normalize_Object_Decl
                         (Decl,
                          Visible,
                          Functions,
                          Type_Env,
                          Visible_Static_Constants,
                          UString_Value (Unit.Path));
                  begin
                     Local_Decl := (others => <>);
                     Local_Decl.Names := Normalized.Names;
                     Local_Decl.Type_Info := Normalized.Type_Info;
                     Local_Decl.Is_Constant := Normalized.Is_Constant;
                     Local_Decl.Has_Initializer := Normalized.Has_Initializer;
                     Local_Decl.Span := Normalized.Span;
                     Local_Decl.Initializer := Normalized.Initializer;
                     if Local_Decl.Is_Constant
                       and then Local_Decl.Has_Initializer
                       and then Try_Static_Value
                         (Local_Decl.Initializer,
                          Visible_Static_Constants,
                          Local_Decl.Static_Info)
                     then
                        null;
                     end if;
                  end;
                  Subprogram.Declarations.Append (Local_Decl);
                  for Name of Decl.Names loop
                     Put_Type (Visible, UString_Value (Name), Local_Decl.Type_Info);
                     Update_Constant_Visibility
                        (Visible_Constants,
                         UString_Value (Name),
                         Local_Decl.Type_Info,
                         Local_Decl.Is_Constant);
                     Update_Static_Constant_Visibility
                       (Visible_Static_Constants,
                        UString_Value (Name),
                        Local_Decl.Initializer,
                        Local_Decl.Is_Constant,
                        Visible_Static_Constants);
                  end loop;
               end loop;

               Subprogram.Statements :=
                 Normalize_Statement_List
                   (Item.Subp_Data.Statements,
                    Visible,
                    Functions,
                    Type_Env,
                    Channel_Env,
                    Imported_Objects,
                    Visible_Constants,
                    Visible_Static_Constants,
                    UString_Value (Unit.Path));

               Result.Subprograms.Append (Subprogram);
            end;
         elsif Item.Kind = CM.Item_Task then
            declare
               Visible        : Type_Maps.Map := Package_Vars;
               Visible_Constants : Type_Maps.Map;
               Visible_Static_Constants : Static_Value_Maps.Map := Const_Env;
               Task_Item      : CM.Resolved_Task;
               Local_Decl     : CM.Resolved_Object_Decl;
               Task_Index     : Natural := Natural (Result.Tasks.Length) + 1;
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
               if Task_Index in Task_Priorities.First_Index .. Task_Priorities.Last_Index then
                  Task_Item.Priority := Task_Priorities (Task_Index).Priority;
               else
                  Task_Item.Priority := Default_Task_Priority;
               end if;
               Task_Item.Span := Item.Task_Data.Span;

               for Object_Decl of Result.Objects loop
                  if Object_Decl.Is_Constant then
                     for Name of Object_Decl.Names loop
                        Put_Type
                          (Visible_Constants,
                           UString_Value (Name),
                           Object_Decl.Type_Info);
                     end loop;
                  end if;
               end loop;

               for Decl of Item.Task_Data.Declarations loop
                  declare
                     Normalized : constant CM.Object_Decl :=
                       Normalize_Object_Decl
                         (Decl,
                          Visible,
                          Functions,
                          Type_Env,
                          Visible_Static_Constants,
                          UString_Value (Unit.Path));
                  begin
                     Local_Decl := (others => <>);
                     Local_Decl.Names := Normalized.Names;
                     Local_Decl.Type_Info := Normalized.Type_Info;
                     Local_Decl.Is_Constant := Normalized.Is_Constant;
                     Local_Decl.Has_Initializer := Normalized.Has_Initializer;
                     Local_Decl.Span := Normalized.Span;
                     Local_Decl.Initializer := Normalized.Initializer;
                     if Local_Decl.Is_Constant
                       and then Local_Decl.Has_Initializer
                       and then Try_Static_Value
                         (Local_Decl.Initializer,
                          Visible_Static_Constants,
                          Local_Decl.Static_Info)
                     then
                        null;
                     end if;
                  end;
                  Task_Item.Declarations.Append (Local_Decl);
                  for Name of Decl.Names loop
                     Put_Type (Visible, UString_Value (Name), Local_Decl.Type_Info);
                     Update_Constant_Visibility
                        (Visible_Constants,
                         UString_Value (Name),
                         Local_Decl.Type_Info,
                         Local_Decl.Is_Constant);
                     Update_Static_Constant_Visibility
                       (Visible_Static_Constants,
                        UString_Value (Name),
                        Local_Decl.Initializer,
                        Local_Decl.Is_Constant,
                        Visible_Static_Constants);
                  end loop;
               end loop;

               Task_Item.Statements :=
                 Normalize_Statement_List
                   (Item.Task_Data.Statements,
                    Visible,
                    Functions,
                    Type_Env,
                    Channel_Env,
                    Imported_Objects,
                    Visible_Constants,
                    Visible_Static_Constants,
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
