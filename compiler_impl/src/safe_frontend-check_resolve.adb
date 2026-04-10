with Ada.Characters.Latin_1;
with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Fixed;
with Ada.Strings.Hash;
with System;
with Safe_Frontend.Builtin_Types;
with Safe_Frontend.Check_Parse;
with Safe_Frontend.Diagnostics;
with Safe_Frontend.Interfaces;
with Safe_Frontend.Lexer;
with Safe_Frontend.Mir_Model;
with Safe_Frontend.Name_Utils;
with Safe_Frontend.Source;
package body Safe_Frontend.Check_Resolve is
   package BT renames Safe_Frontend.Builtin_Types;
   package CP renames Safe_Frontend.Check_Parse;
   package FD renames Safe_Frontend.Diagnostics;
   package FL renames Safe_Frontend.Lexer;
   package GM renames Safe_Frontend.Mir_Model;
   package FNU renames Safe_Frontend.Name_Utils;
   package SI renames Safe_Frontend.Interfaces;

   use type CM.Expr_Access;
   use type CM.Expr_Kind;
   use type CM.Statement_Access;
   use type CM.Match_Arm_Kind;
   use type CM.Discrete_Range_Kind;
   use type CM.Package_Item_Kind;
   use type CM.Select_Arm_Kind;
   use type CM.Statement_Kind;
   use type CM.Static_Value_Kind;
   use type CM.Type_Spec_Access;
   use type CM.Type_Decl_Kind;
   use type CM.Type_Spec_Kind;
   use type CM.Unit_Kind;
   use type GM.Scalar_Value_Kind;
   use type FT.UString;

   type Function_Info is record
      Name                 : FT.UString := FT.To_UString ("");
      Kind                 : FT.UString := FT.To_UString ("");
      Generic_Formals      : CM.Generic_Formal_Vectors.Vector;
      Params               : CM.Symbol_Vectors.Vector;
      Has_Return_Type      : Boolean := False;
      Return_Type          : GM.Type_Descriptor;
      Return_Is_Access_Def : Boolean := False;
      Span                 : FT.Source_Span := FT.Null_Span;
   end record;

   type Interface_Template_Info is record
      Decl : CM.Subprogram_Body;
      Info : Function_Info;
   end record;

   type Generic_Type_Template_Info is record
      Has_Decl : Boolean := False;
      Decl     : CM.Type_Decl;
      Info     : GM.Type_Descriptor;
   end record;

   type Generic_Function_Template_Info is record
      Decl              : CM.Subprogram_Body;
      Info              : Function_Info;
      Origin_Package    : FT.UString := FT.To_UString ("");
      Actual_Type_Names : FT.UString_Vectors.Vector;
   end record;

   package Interface_Template_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Interface_Template_Info,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   package Generic_Type_Template_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Generic_Type_Template_Info,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   package Generic_Function_Template_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Generic_Function_Template_Info,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   package String_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => String,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   type Sum_Constructor_Field_Info is record
      Source_Name : FT.UString := FT.To_UString ("");
      Name      : FT.UString := FT.To_UString ("");
      Type_Name : FT.UString := FT.To_UString ("");
   end record;

   package Sum_Constructor_Field_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Sum_Constructor_Field_Info);

   type Sum_Constructor_Info is record
      Name             : FT.UString := FT.To_UString ("");
      Sum_Type_Name    : FT.UString := FT.To_UString ("");
      Tag_Type_Name    : FT.UString := FT.To_UString ("");
      Tag_Literal_Name : FT.UString := FT.To_UString ("");
      Fields           : Sum_Constructor_Field_Vectors.Vector;
      Span             : FT.Source_Span := FT.Null_Span;
   end record;

   package Sum_Constructor_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Sum_Constructor_Info,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   function Equal_Static_Value
     (Left, Right : CM.Static_Value) return Boolean is
   begin
      return Left.Kind = Right.Kind
        and then Left.Int_Value = Right.Int_Value
        and then Left.Bool_Value = Right.Bool_Value
        and then FT.To_String (Left.Text) = FT.To_String (Right.Text)
        and then FT.To_String (Left.Type_Name) = FT.To_String (Right.Type_Name);
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

   package Exact_Length_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Natural,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   type Task_Priority_Info is record
      Priority : Long_Long_Integer := 0;
   end record;

   package Task_Priority_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Task_Priority_Info);

   package String_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => String);

   package Type_Decl_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => CM.Type_Decl,
      "="          => CM."=");

   package String_Index_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Positive,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   type Recursive_Family_Info is record
      Members                   : String_Vectors.Vector;
      Is_Recursive              : Boolean := False;
      Is_Admitted_Record_Family : Boolean := False;
      Non_Record_Kinds          : String_Vectors.Vector;
   end record;

   package Recursive_Family_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Recursive_Family_Info);

   Resolve_Failure : exception;
   Raised_Diag     : CM.MD.Diagnostic;
   Documented_Default_Task_Priority : constant Long_Long_Integer := 31;

   type Shared_Object_Ref_Kind is
     (Shared_Object_None,
      Shared_Object_Local_Private,
      Shared_Object_Local_Public,
      Shared_Object_Imported_Public);

   type Shared_Object_Ref is record
      Kind         : Shared_Object_Ref_Kind := Shared_Object_None;
      Package_Name : FT.UString := FT.To_UString ("");
      Root_Name    : FT.UString := FT.To_UString ("");
      Type_Info    : GM.Type_Descriptor;
   end record;

   Current_Target_Bits : Positive := 64;
   Current_Public_Channel_Names : String_Vectors.Vector;
   Current_Shared_Object_Types : Type_Maps.Map;
   Current_Public_Shared_Object_Types : Type_Maps.Map;
   Current_Imported_Shared_Object_Types : Type_Maps.Map;
   Current_Imported_Synthetic_Types : Type_Maps.Map;
   Current_Select_In_Subprogram_Body : Boolean := False;
   Current_In_Task_Body : Boolean := False;
   Synthetic_Helper_Types : Type_Maps.Map;
   Synthetic_Helper_Order : String_Vectors.Vector;
   Synthetic_Optional_Types : Type_Maps.Map;
   Synthetic_Optional_Order : String_Vectors.Vector;
   Current_Interface_Templates : Interface_Template_Maps.Map;
   Current_Pending_Interface_Specializations : Interface_Template_Maps.Map;
   Current_Interface_Specialization_Order : String_Vectors.Vector;
   Current_Interface_Specialization_By_Key : String_Maps.Map;
   Current_Generic_Type_Templates : Generic_Type_Template_Maps.Map;
   Current_Generic_Type_Instantiation_Order : String_Vectors.Vector;
   Current_Generic_Type_Instantiation_By_Key : String_Maps.Map;
   Current_Generic_Type_Instantiations : Type_Maps.Map;
   Current_Generic_Type_Instantiation_Stack : String_Vectors.Vector;
   Current_Generic_Function_Templates : Generic_Function_Template_Maps.Map;
   Current_Pending_Generic_Specializations : Generic_Function_Template_Maps.Map;
   Current_Generic_Specialization_Order : String_Vectors.Vector;
   Current_Generic_Specialization_By_Key : String_Maps.Map;
   Current_Synthetic_Functions : Function_Maps.Map;
   Current_Generic_Function_Env : Function_Maps.Map;
   Current_Sum_Constructors : Sum_Constructor_Maps.Map;
   Current_Sum_Tag_Types : Type_Maps.Map;
   Current_Sum_Type_Tag_Names : String_Maps.Map;

   function UString_Value (Value : FT.UString) return String is
   begin
      return FT.To_String (Value);
   end UString_Value;

   function Canonical_Name (Value : String) return String is
   begin
      return FT.Lowercase (Value);
   end Canonical_Name;

   function Synthetic_Type_Tail_Name (Name : String) return String;

   function Has_Resolvable_Type_Name
     (Name     : String;
      Type_Env : Type_Maps.Map) return Boolean
   is
      Bounded_String_Prefix : constant String := "__bounded_string_";
   begin
      return Type_Env.Contains (Canonical_Name (Name))
        or else Synthetic_Helper_Types.Contains (Canonical_Name (Name))
        or else Synthetic_Optional_Types.Contains (Canonical_Name (Name))
        or else Current_Generic_Type_Instantiations.Contains (Canonical_Name (Name))
        or else
          (Name'Length >= Bounded_String_Prefix'Length
           and then
             Name (Name'First .. Name'First + Bounded_String_Prefix'Length - 1) =
               Bounded_String_Prefix);
   end Has_Resolvable_Type_Name;

   function Contains_Public_Local_Channel (Name : String) return Boolean is
   begin
      for Item of Current_Public_Channel_Names loop
         if Canonical_Name (Item) = Canonical_Name (Name) then
            return True;
         end if;
      end loop;
      return False;
   end Contains_Public_Local_Channel;

   function In_Unit_Statement_Context return Boolean is
   begin
      return not Current_Select_In_Subprogram_Body
        and then not Current_In_Task_Body;
   end In_Unit_Statement_Context;

   procedure Append_Unique_String
     (Items : in out String_Vectors.Vector;
      Value : String) is
   begin
      for Item of Items loop
         if Canonical_Name (Item) = Canonical_Name (Value) then
            return;
         end if;
      end loop;
      Items.Append (Value);
   end Append_Unique_String;

   procedure Register_Synthetic_Helper_Type
     (Info : GM.Type_Descriptor) is
      Name_Text : constant String := UString_Value (Info.Name);
   begin
      if Name_Text'Length < 2
        or else Name_Text (Name_Text'First .. Name_Text'First + 1) /= "__"
      then
         return;
      end if;
      if not Synthetic_Helper_Types.Contains (Name_Text) then
         Synthetic_Helper_Types.Include (Name_Text, Info);
         Append_Unique_String (Synthetic_Helper_Order, Name_Text);
      end if;
   end Register_Synthetic_Helper_Type;

   function Join_String_Vector
     (Items     : String_Vectors.Vector;
      Separator : String := ", ") return String
   is
      Result : FT.UString := FT.To_UString ("");
   begin
      if Items.Is_Empty then
         return "";
      end if;
      for Index in Items.First_Index .. Items.Last_Index loop
         if Index /= Items.First_Index then
            Result := Result & FT.To_UString (Separator);
         end if;
         Result := Result & FT.To_UString (Items (Index));
      end loop;
      return UString_Value (Result);
   end Join_String_Vector;

   function Type_Decl_Kind_Label (Kind : CM.Type_Decl_Kind) return String is
   begin
      case Kind is
         when CM.Type_Decl_Sum =>
            return "sum";
         when CM.Type_Decl_Record =>
            return "record";
         when CM.Type_Decl_Interface =>
            return "interface";
         when CM.Type_Decl_Growable_Array =>
            return "growable array";
         when CM.Type_Decl_Constrained_Array | CM.Type_Decl_Unconstrained_Array =>
            return "array";
         when CM.Type_Decl_Integer =>
            return "integer";
         when CM.Type_Decl_Enumeration =>
            return "enumeration";
         when CM.Type_Decl_Binary =>
            return "binary";
         when CM.Type_Decl_Float =>
            return "float";
         when CM.Type_Decl_Access =>
            return "access";
         when CM.Type_Decl_Incomplete =>
            return "incomplete";
         when others =>
            return "type";
      end case;
   end Type_Decl_Kind_Label;

   function Family_Index_Of
     (Name           : String;
      Family_By_Name : String_Index_Maps.Map) return Natural is
      Key : constant String := Canonical_Name (Name);
   begin
      if Family_By_Name.Contains (Key) then
         return Natural (Family_By_Name.Element (Key));
      end if;
      return 0;
   end Family_Index_Of;

   function Is_Admitted_Record_Family_Member
     (Name           : String;
      Family_By_Name : String_Index_Maps.Map;
      Families       : Recursive_Family_Vectors.Vector) return Boolean
   is
      Index : constant Natural := Family_Index_Of (Name, Family_By_Name);
   begin
      return Index /= 0
        and then Families (Positive (Index)).Is_Admitted_Record_Family;
   end Is_Admitted_Record_Family_Member;

   function In_Same_Admitted_Record_Family
     (Left, Right    : String;
      Family_By_Name : String_Index_Maps.Map;
      Families       : Recursive_Family_Vectors.Vector) return Boolean
   is
      Left_Index  : constant Natural := Family_Index_Of (Left, Family_By_Name);
      Right_Index : constant Natural := Family_Index_Of (Right, Family_By_Name);
   begin
      return Left_Index /= 0
        and then Left_Index = Right_Index
        and then Families (Positive (Left_Index)).Is_Admitted_Record_Family;
   end In_Same_Admitted_Record_Family;

   function Recursive_Family_Diagnostic_Message
     (Family : Recursive_Family_Info) return String is
   begin
      return
        "recursive type family ("
        & Join_String_Vector (Family.Members)
        & ") is not admitted in PR11.8e.1; all members must be record types"
        & (if Family.Non_Record_Kinds.Is_Empty
             then ""
             else " (found " & Join_String_Vector (Family.Non_Record_Kinds) & ")");
   end Recursive_Family_Diagnostic_Message;

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

   function Has_Type_Canonical
     (Map  : Type_Maps.Map;
      Name : String) return Boolean is
   begin
      pragma Assert
        (Name = Canonical_Name (Name),
         "Has_Type_Canonical requires a pre-canonicalized name");
      return Map.Contains (Name);
   end Has_Type_Canonical;

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
      return Map.Contains (Canonical_Name (Name))
        or else Current_Synthetic_Functions.Contains (Canonical_Name (Name));
   end Has_Function;

   function Has_Function_Canonical
     (Map  : Function_Maps.Map;
      Name : String) return Boolean is
   begin
      pragma Assert
        (Name = Canonical_Name (Name),
         "Has_Function_Canonical requires a pre-canonicalized name");
      return Map.Contains (Name)
        or else Current_Synthetic_Functions.Contains (Name);
   end Has_Function_Canonical;

   function Get_Function
     (Map  : Function_Maps.Map;
     Name : String) return Function_Info is
   begin
      if Map.Contains (Canonical_Name (Name)) then
         return Map.Element (Canonical_Name (Name));
      end if;
      return Current_Synthetic_Functions.Element (Canonical_Name (Name));
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

   function Is_Enum_Static_Value (Value : CM.Static_Value) return Boolean is
   begin
      return Value.Kind = CM.Static_Value_Enum
        and then UString_Value (Value.Type_Name) /= ""
        and then UString_Value (Value.Text) /= "";
   end Is_Enum_Static_Value;

   function Has_Enum_Literal
     (Map  : Static_Value_Maps.Map;
      Name : String) return Boolean is
   begin
      return Has_Static_Value (Map, Name)
        and then Is_Enum_Static_Value (Get_Static_Value (Map, Name));
   end Has_Enum_Literal;

   procedure Add_Builtins (Type_Env : in out Type_Maps.Map) is
   begin
      Put_Type (Type_Env, "integer", BT.Integer_Type (Current_Target_Bits));
      Put_Type (Type_Env, "boolean", BT.Boolean_Type);
      Put_Type (Type_Env, "string", BT.String_Type);
      Put_Type (Type_Env, "result", BT.Result_Type);
      Put_Type (Type_Env, "__binary_8", BT.Binary_Type (8));
      Put_Type (Type_Env, "__binary_16", BT.Binary_Type (16));
      Put_Type (Type_Env, "__binary_32", BT.Binary_Type (32));
      Put_Type (Type_Env, "__binary_64", BT.Binary_Type (64));
      Put_Type (Type_Env, "float", BT.Float_Type);
      Put_Type (Type_Env, "long_float", BT.Long_Float_Type);
      Put_Type (Type_Env, "duration", BT.Duration_Type);
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
      Symbol.Mode := FT.To_UString ("borrow");
      Symbol.Type_Info := BT.String_Type;
      Info.Params.Append (Symbol);
      Put_Function (Functions, "fail", Info);

      Info := (others => <>);
      Info.Name := FT.To_UString ("print");
      Info.Kind := FT.To_UString ("function");
      Symbol := (others => <>);
      Symbol.Name := FT.To_UString ("value");
      Symbol.Kind := FT.To_UString ("param");
      Symbol.Mode := FT.To_UString ("borrow");
      Symbol.Type_Info := BT.String_Type;
      Info.Params.Append (Symbol);
      Put_Function (Functions, "print", Info);
   end Add_Builtin_Functions;

   procedure Raise_Diag (Item : CM.MD.Diagnostic) is
   begin
      Raised_Diag := Item;
      raise Resolve_Failure;
   end Raise_Diag;

   function Default_Integer return GM.Type_Descriptor is
   begin
      return BT.Integer_Type (Current_Target_Bits);
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

   function Is_Enum_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean;

   function Is_Binary_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean;

   function Binary_Bit_Width
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Positive;

   function Is_Tuple_Type
     (Info     : GM.Type_Descriptor;
     Type_Env : Type_Maps.Map) return Boolean;

   function Is_String_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean;

   function Is_Bounded_String_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean;

   function Bounded_String_Capacity
     (Info      : GM.Type_Descriptor;
      Type_Env  : Type_Maps.Map;
      Capacity  : out Natural) return Boolean;

   function Is_Growable_Array_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean;

   function Is_Optional_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean;

   function Is_Interface_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean;

   function Is_Generic_Formal_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean;

   function Optional_Payload_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return GM.Type_Descriptor;

   function Is_Optional_Element_Type_Allowed
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean;

   function Is_Container_Element_Type_Allowed
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean;

   function Is_Shared_Field_Type_Allowed
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean;

   function Is_Shared_Record_Root_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean;

   function Is_Shared_Container_Root_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean;

   function Is_Shared_Root_Type_Allowed
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean;

   function Shared_Wrapper_Object_Name (Root_Name : String) return String;

   function Shared_Public_Helper_Base_Name (Root_Name : String) return String;

   function Shared_Public_Helper_Name
     (Root_Name  : String;
      Operation  : String) return String;

   function Shared_Get_All_Name return String;

   function Shared_Set_All_Name return String;

   function Shared_Get_Length_Name return String;

   function Shared_Append_Name return String;

   function Shared_Pop_Last_Name return String;

   function Shared_Contains_Name return String;

   function Shared_Get_Name return String;

   function Shared_Set_Name return String;

   function Shared_Remove_Name return String;

   function Shared_Field_Getter_Name (Field_Name : String) return String;

   function Shared_Field_Setter_Name (Field_Name : String) return String;

   function Shared_Nested_Field_Setter_Name
     (Path_Names : FT.UString_Vectors.Vector) return String;

   function Shared_Snapshot_Expr
     (Shared : Shared_Object_Ref;
      Span   : FT.Source_Span) return CM.Expr_Access;

   function Shared_Wrapper_Call_Expr
     (Root_Name : String;
      Selector  : String;
      Span      : FT.Source_Span;
      Type_Name : String := "") return CM.Expr_Access;

   function Shared_Public_Helper_Call_Expr
     (Package_Name : String;
      Root_Name    : String;
      Operation    : String;
      Span         : FT.Source_Span;
      Type_Name    : String := "") return CM.Expr_Access;

   function Shared_Call_Expr
     (Shared    : Shared_Object_Ref;
      Operation : String;
      Span      : FT.Source_Span;
      Type_Name : String := "") return CM.Expr_Access;

   function Is_Shared_Object_Name (Name : String) return Boolean;

   function Try_Shared_Root_Expr
     (Expr   : CM.Expr_Access;
      Shared : out Shared_Object_Ref) return Boolean;

   function Try_Shared_Target_Expr
     (Expr   : CM.Expr_Access;
      Shared : out Shared_Object_Ref) return Boolean;

   function Try_Shared_Wrapper_Root_Name_Expr
     (Expr      : CM.Expr_Access;
      Root_Name : out FT.UString;
      Root_Type : out GM.Type_Descriptor) return Boolean;

   function Try_Shared_Public_Helper_Call
     (Expr      : CM.Expr_Access;
      Operation : String;
      Shared    : out Shared_Object_Ref) return Boolean;

   function Try_Shared_Top_Level_Field_Access
     (Expr       : CM.Expr_Access;
      Type_Env   : Type_Maps.Map;
      Shared     : out Shared_Object_Ref;
      Field_Type : out GM.Type_Descriptor) return Boolean;

   function Try_Shared_Nested_Field_Access
     (Expr       : CM.Expr_Access;
      Type_Env   : Type_Maps.Map;
      Shared     : out Shared_Object_Ref;
      Path_Names : out FT.UString_Vectors.Vector;
      Field_Type : out GM.Type_Descriptor) return Boolean;

   procedure Reject_Bare_Shared_Object_Expr
     (Expr      : CM.Expr_Access;
      Type_Env  : Type_Maps.Map;
      Path      : String);

   function Is_Definite_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean;

   function Contains_Channel_Reference_Subcomponent
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean;

   function Try_Static_String_Length
     (Expr   : CM.Expr_Access;
      Length : out Natural) return Boolean;

   procedure Reject_Static_Bounded_String_Overflow
     (Source_Expr : CM.Expr_Access;
      Target      : GM.Type_Descriptor;
      Type_Env    : Type_Maps.Map;
      Path        : String;
      Span        : FT.Source_Span);

   function Make_Bounded_String_Type
     (Bound : Natural) return GM.Type_Descriptor;

   function Make_Growable_Array_Type
     (Component_Type : GM.Type_Descriptor;
      Type_Env       : Type_Maps.Map) return GM.Type_Descriptor;

   function Make_Tuple_Type
     (Element_Types : FT.UString_Vectors.Vector;
      Type_Env      : Type_Maps.Map) return GM.Type_Descriptor;

   function Make_Optional_Type
     (Element_Type : GM.Type_Descriptor;
      Type_Env     : Type_Maps.Map) return GM.Type_Descriptor;

   function Growable_Array_Element_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return GM.Type_Descriptor;

   function Try_Map_Key_Value_Types
     (Info       : GM.Type_Descriptor;
      Type_Env   : Type_Maps.Map;
      Key_Type   : out GM.Type_Descriptor;
      Value_Type : out GM.Type_Descriptor) return Boolean;

   function Is_Map_Key_Type_Allowed
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean;

   function Register_Function
     (Decl      : CM.Subprogram_Body;
      Type_Env  : Type_Maps.Map;
      Const_Env : Static_Value_Maps.Map;
      Path      : String) return Function_Info;

   function Generic_Formal_Type
     (Formal : CM.Generic_Formal) return GM.Type_Descriptor;

   function Generic_Formal_Descriptor
     (Formal : CM.Generic_Formal) return GM.Generic_Formal_Descriptor;

   procedure Add_Generic_Formals_To_Env
     (Type_Env : in out Type_Maps.Map;
      Formals  : CM.Generic_Formal_Vectors.Vector);

   function Is_Generic_Actual_Type_Allowed
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean;

   procedure Validate_Generic_Actuals
     (Formals      : CM.Generic_Formal_Vectors.Vector;
      Actual_Types : FT.UString_Vectors.Vector;
      Functions    : Function_Maps.Map;
      Type_Env     : Type_Maps.Map;
      Path         : String;
      Span         : FT.Source_Span);

   function Generic_Template_Key
     (Name         : String;
      Actual_Types : FT.UString_Vectors.Vector) return String;

   function Generic_Specialization_Name
     (Prefix       : String;
      Name         : String;
      Actual_Types : FT.UString_Vectors.Vector) return String;

   function Method_Target_Tail_Name (Name : String) return String;

   function Type_Satisfies_Interface
     (Concrete_Type  : GM.Type_Descriptor;
      Interface_Type : GM.Type_Descriptor;
      Functions      : Function_Maps.Map;
      Type_Env       : Type_Maps.Map) return Boolean;

   function Substitute_Generic_Type_Info
     (Template     : GM.Type_Descriptor;
      Formals      : GM.Generic_Formal_Descriptor_Vectors.Vector;
      Actual_Types : FT.UString_Vectors.Vector) return GM.Type_Descriptor;

   function Parse_Imported_Generic_Subprogram
     (Package_Name    : String;
      Qualified_Name  : String;
      Template_Source : String) return CM.Subprogram_Body;

   procedure Add_Imported_Package_Local_Aliases
     (Package_Name         : String;
      Imported_Types       : GM.Type_Descriptor_Vectors.Vector;
      Imported_Subprograms : GM.External_Vectors.Vector;
      Imported_Objects     : Type_Maps.Map;
      Imported_Static      : Static_Value_Maps.Map;
      Generic_Types        : in out Generic_Type_Template_Maps.Map;
      Generic_Functions    : in out Generic_Function_Template_Maps.Map;
      Visible_Types        : in out Type_Maps.Map;
      Visible_Functions    : in out Function_Maps.Map;
      Visible_Objects      : in out Type_Maps.Map;
      Visible_Static       : in out Static_Value_Maps.Map);

   function Instantiate_Generic_Type
     (Template_Name : String;
      Spec          : CM.Type_Spec;
      Type_Env      : Type_Maps.Map;
      Const_Env     : Static_Value_Maps.Map;
      Path          : String) return GM.Type_Descriptor;

   function Specialize_Generic_Call
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Const_Env : Static_Value_Maps.Map;
      Path      : String) return CM.Expr_Access;

   function Specialize_Interface_Call
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Const_Env : Static_Value_Maps.Map;
      Path      : String) return CM.Expr_Access;

   function Interface_Has_Member
     (Info        : GM.Type_Descriptor;
      Member_Name : String) return Boolean;

   procedure Validate_Interface_Method_Syntax
     (Decl     : CM.Subprogram_Body;
      Info     : Function_Info;
      Type_Env : Type_Maps.Map;
      Path     : String);

   function Bool_Expr
     (Value : Boolean;
      Span  : FT.Source_Span) return CM.Expr_Access;

   function Int_Expr
     (Value : CM.Wide_Integer;
      Span  : FT.Source_Span) return CM.Expr_Access;

   function Ident_Expr
     (Name      : String;
      Span      : FT.Source_Span;
      Type_Name : String) return CM.Expr_Access;

   function Selector_Expr
     (Prefix    : CM.Expr_Access;
      Selector  : String;
      Span      : FT.Source_Span;
      Type_Name : String) return CM.Expr_Access;

   function Binary_Expr
     (Left      : CM.Expr_Access;
      Operator  : String;
      Right     : CM.Expr_Access;
      Span      : FT.Source_Span;
      Type_Name : String) return CM.Expr_Access;

   function Resolved_Index_Expr
     (Prefix    : CM.Expr_Access;
      Arg_1     : CM.Expr_Access;
      Span      : FT.Source_Span;
      Type_Name : String;
      Arg_2     : CM.Expr_Access := null) return CM.Expr_Access;

   function Build_Optional_None_Expr
     (Optional_Type : GM.Type_Descriptor;
      Span          : FT.Source_Span) return CM.Expr_Access;

   function Build_Optional_Some_Expr
     (Optional_Type : GM.Type_Descriptor;
      Value_Expr    : CM.Expr_Access;
      Span          : FT.Source_Span) return CM.Expr_Access;

   function Contextualize_Expr_To_Target_Type
     (Expr      : CM.Expr_Access;
      Target    : GM.Type_Descriptor;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Path      : String) return CM.Expr_Access;

   procedure Reject_Uncontextualized_None
     (Expr  : CM.Expr_Access;
      Path  : String);

   type Builtin_Method_Kind is
     (Builtin_None,
      Builtin_Append,
      Builtin_Pop_Last,
      Builtin_Contains,
      Builtin_Get,
      Builtin_Remove,
      Builtin_Set);

   function Builtin_Method_Kind_For_Canonical_Name
     (Name : String) return Builtin_Method_Kind;

   function Builtin_Method_Kind_For_Name (Name : String) return Builtin_Method_Kind;

   function Builtin_Method_Name (Kind : Builtin_Method_Kind) return String;

   function Builtin_Method_Kind_For_Call
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map) return Builtin_Method_Kind;

   function Validate_And_Contextualize_Value
     (Value                 : CM.Expr_Access;
      Target_Type           : GM.Type_Descriptor;
      Var_Types             : Type_Maps.Map;
      Functions             : Function_Maps.Map;
      Type_Env              : Type_Maps.Map;
      Const_Env             : Static_Value_Maps.Map;
      Exact_Length_Facts    : Exact_Length_Maps.Map;
      Path                  : String;
      Mismatch_Message      : String;
      Stamp_String_Literal  : Boolean := True) return CM.Expr_Access;

   function Is_Unshadowed_Builtin_Call
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Name      : String) return Boolean;

   function Is_Append_Builtin_Call
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map) return Boolean;

   function Is_Pop_Last_Builtin_Call
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map) return Boolean;

   function Is_Contains_Builtin_Call
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map) return Boolean;

   function Is_Get_Builtin_Call
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map) return Boolean;

   function Is_Set_Builtin_Call
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map) return Boolean;

   function Is_Remove_Builtin_Call
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map) return Boolean;

   function Sanitize_Type_Name_Component (Value : String) return String;

   function Hidden_Reference_Target_Name (Name : String) return String;

   function Sum_Tag_Type_Name (Sum_Name : String) return String;

   function Sum_Tag_Literal_Name
     (Sum_Name     : String;
      Variant_Name : String) return String;

   function Qualify_Sum_Tag_Literal_Name
     (Package_Name : String;
      Name         : String) return String;

   function Qualify_Static_Value
     (Value        : CM.Static_Value;
      Package_Name : String) return CM.Static_Value;

   function Qualify_Scalar_Value
     (Value        : GM.Scalar_Value;
      Package_Name : String) return GM.Scalar_Value;

   function Has_Sum_Constructor (Name : String) return Boolean;

   function Get_Sum_Constructor (Name : String) return Sum_Constructor_Info;

   function Sum_Discriminant_Name (Sum_Name : String) return String;

   function Sum_Variant_Field_Name
     (Variant_Name : String;
      Field_Name   : String) return String;

   function Is_Discrete_Case_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean;

   function Is_Sum_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean;

   function Case_Choice_Compatible
     (Scrutinee : GM.Type_Descriptor;
      Choice    : GM.Type_Descriptor;
      Type_Env  : Type_Maps.Map) return Boolean;

   function Expr_Type
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map) return GM.Type_Descriptor;

   function Resolve_Target_Type
     (Target   : CM.Expr_Access;
      Type_Env : Type_Maps.Map) return GM.Type_Descriptor;

   function Is_Assignable_Target (Expr : CM.Expr_Access) return Boolean;

   procedure Validate_Mut_Call_Arguments
     (Expr      : CM.Expr_Access;
      Functions : Function_Maps.Map;
      Path      : String);

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
      Left_Tail  : constant String := Synthetic_Type_Tail_Name (UString_Value (Left_Base.Name));
      Right_Tail : constant String := Synthetic_Type_Tail_Name (UString_Value (Right_Base.Name));
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
        or else UString_Value (Left_Base.Name) = UString_Value (Right_Base.Name)
        or else
          (Left_Tail'Length > 2
           and then Right_Tail'Length > 2
           and then Left_Tail (Left_Tail'First .. Left_Tail'First + 1) = "__"
           and then Right_Tail (Right_Tail'First .. Right_Tail'First + 1) = "__"
           and then Left_Tail = Right_Tail);
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
        or else (Left_Kind = "access" and then Right_Kind = "null")
        or else (Left_Kind = "null" and then Right_Kind = "access")
        or else
          (Left_Kind = "access"
           and then Right_Kind = "access"
           and then Left_Base.Has_Target
           and then Right_Base.Has_Target
           and then Equivalent_Type
             (Resolve_Type (UString_Value (Left_Base.Target), Type_Env, "", FT.Null_Span),
              Resolve_Type (UString_Value (Right_Base.Target), Type_Env, "", FT.Null_Span),
              Type_Env))
        or else (Is_String_Type (Left, Type_Env) and then Is_String_Type (Right, Type_Env))
        or else
          (FT.Lowercase (UString_Value (Left_Base.Kind)) = "array"
           and then FT.Lowercase (UString_Value (Right_Base.Kind)) = "array"
           and then Left_Base.Growable
           and then Right_Base.Growable
           and then Left_Base.Has_Component_Type
           and then Right_Base.Has_Component_Type
           and then Compatible_Type
             (Resolve_Type (UString_Value (Left_Base.Component_Type), Type_Env, "", FT.Null_Span),
              Resolve_Type (UString_Value (Right_Base.Component_Type), Type_Env, "", FT.Null_Span),
              Type_Env))
        or else (Is_Tuple_Type (Left, Type_Env)
                 and then Is_Tuple_Type (Right, Type_Env)
                 and then Equivalent_Type (Left, Right, Type_Env))
        or else (Is_Integerish (Left, Type_Env) and then Is_Integerish (Right, Type_Env))
        or else (Is_Binary_Type (Left, Type_Env)
                 and then Is_Binary_Type (Right, Type_Env)
                 and then Binary_Bit_Width (Left, Type_Env) = Binary_Bit_Width (Right, Type_Env))
        or else (Left_Kind = "float" and then Right_Kind = "float");
   end Compatible_Type;

   function Compatible_Source_To_Target_Type
     (Source   : GM.Type_Descriptor;
      Target   : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean;

   function Compatible_Source_Expr_To_Target_Type
     (Source_Expr : CM.Expr_Access;
      Source      : GM.Type_Descriptor;
      Target      : GM.Type_Descriptor;
      Var_Types   : Type_Maps.Map;
      Functions   : Function_Maps.Map;
      Type_Env    : Type_Maps.Map;
      Const_Env   : Static_Value_Maps.Map;
      Exact_Length_Facts : Exact_Length_Maps.Map) return Boolean;

   function Is_Boolean_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean is
   begin
      return UString_Value (Base_Type (Info, Type_Env).Name) = "boolean";
   end Is_Boolean_Type;

   function Is_Tuple_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean is
   begin
      return FT.Lowercase (UString_Value (Base_Type (Info, Type_Env).Kind)) = "tuple";
   end Is_Tuple_Type;

   function Is_String_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean is
   begin
      return FT.Lowercase (UString_Value (Base_Type (Info, Type_Env).Kind)) = "string";
   end Is_String_Type;

   function Is_Array_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean is
   begin
      return FT.Lowercase (UString_Value (Base_Type (Info, Type_Env).Kind)) = "array";
   end Is_Array_Type;

   function Is_Name_Expr (Expr : CM.Expr_Access) return Boolean is
   begin
      return Expr /= null and then Expr.Kind in CM.Expr_Ident | CM.Expr_Select;
   end Is_Name_Expr;

   function Is_Result_Builtin_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean
   is
      Base : constant GM.Type_Descriptor := Base_Type (Info, Type_Env);
   begin
      return Base.Is_Result_Builtin;
   end Is_Result_Builtin_Type;

   function Try_Result_Carrier_Success_Type
     (Info         : GM.Type_Descriptor;
      Type_Env     : Type_Maps.Map;
      Success_Type : out GM.Type_Descriptor) return Boolean
   is
      Base : constant GM.Type_Descriptor := Base_Type (Info, Type_Env);
   begin
      Success_Type := (others => <>);
      if FT.Lowercase (UString_Value (Base.Kind)) /= "tuple"
        or else Natural (Base.Tuple_Element_Types.Length) /= 2
      then
         return False;
      end if;

      declare
         Result_Type : constant GM.Type_Descriptor :=
           Resolve_Type
             (UString_Value (Base.Tuple_Element_Types (Base.Tuple_Element_Types.First_Index)),
              Type_Env,
              "",
              FT.Null_Span);
      begin
         if not Is_Result_Builtin_Type (Result_Type, Type_Env) then
            return False;
         end if;
      end;

      Success_Type :=
        Resolve_Type
          (UString_Value (Base.Tuple_Element_Types (Base.Tuple_Element_Types.First_Index + 1)),
           Type_Env,
           "",
           FT.Null_Span);
      return True;
   end Try_Result_Carrier_Success_Type;

   function Expr_Contains_Try (Expr : CM.Expr_Access) return Boolean is
   begin
      if Expr = null then
         return False;
      elsif Expr.Kind = CM.Expr_Try then
         return True;
      end if;

      case Expr.Kind is
         when CM.Expr_Select | CM.Expr_Conversion | CM.Expr_Annotated | CM.Expr_Unary | CM.Expr_Try | CM.Expr_Some =>
            return Expr_Contains_Try (Expr.Prefix)
              or else Expr_Contains_Try (Expr.Inner);
         when CM.Expr_Resolved_Index | CM.Expr_Call | CM.Expr_Apply =>
            if Expr_Contains_Try (Expr.Prefix)
              or else Expr_Contains_Try (Expr.Callee)
            then
               return True;
            end if;
            for Item of Expr.Args loop
               if Expr_Contains_Try (Item) then
                  return True;
               end if;
            end loop;
            return False;
         when CM.Expr_Binary =>
            return Expr_Contains_Try (Expr.Left)
              or else Expr_Contains_Try (Expr.Right);
         when CM.Expr_Allocator =>
            return Expr_Contains_Try (Expr.Value);
         when CM.Expr_Aggregate =>
            for Item of Expr.Fields loop
               if Expr_Contains_Try (Item.Expr) then
                  return True;
               end if;
            end loop;
            return False;
         when CM.Expr_Array_Literal | CM.Expr_Tuple =>
            for Item of Expr.Elements loop
               if Expr_Contains_Try (Item) then
                  return True;
               end if;
            end loop;
            return False;
         when others =>
            return False;
      end case;
   end Expr_Contains_Try;

   function Is_Bounded_String_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean
   is
      Current : GM.Type_Descriptor := Info;
   begin
      loop
         if FT.Lowercase (UString_Value (Current.Kind)) = "string"
           and then Current.Has_Length_Bound
         then
            return True;
         end if;
         exit when not Current.Has_Base
           or else not Has_Type (Type_Env, UString_Value (Current.Base));
         Current := Get_Type (Type_Env, UString_Value (Current.Base));
      end loop;
      return False;
   end Is_Bounded_String_Type;

   function Bounded_String_Capacity
     (Info      : GM.Type_Descriptor;
      Type_Env  : Type_Maps.Map;
      Capacity  : out Natural) return Boolean
   is
      Current : GM.Type_Descriptor := Info;
   begin
      loop
         if FT.Lowercase (UString_Value (Current.Kind)) = "string"
           and then Current.Has_Length_Bound
         then
            Capacity := Current.Length_Bound;
            return True;
         end if;
         exit when not Current.Has_Base
           or else not Has_Type (Type_Env, UString_Value (Current.Base));
         Current := Get_Type (Type_Env, UString_Value (Current.Base));
      end loop;
      Capacity := 0;
      return False;
   end Bounded_String_Capacity;

   function Is_Growable_Array_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean
   is
      Current : GM.Type_Descriptor := Info;
   begin
      loop
         if FT.Lowercase (UString_Value (Current.Kind)) = "array"
           and then Current.Growable
         then
            return True;
         end if;
         exit when not Current.Has_Base
           or else not Has_Type (Type_Env, UString_Value (Current.Base));
         Current := Get_Type (Type_Env, UString_Value (Current.Base));
      end loop;
      return False;
   end Is_Growable_Array_Type;

   function Is_Optional_Type
     (Info     : GM.Type_Descriptor;
     Type_Env : Type_Maps.Map) return Boolean
   is
      Base : constant GM.Type_Descriptor := Base_Type (Info, Type_Env);
      Name : constant String := FT.Lowercase (UString_Value (Base.Name));
      Dot  : Natural := 0;
   begin
      for Index in reverse Name'Range loop
         if Name (Index) = '.' then
            Dot := Index;
            exit;
         end if;
      end loop;
      declare
         Tail : constant String :=
           (if Dot /= 0 and then Dot < Name'Last
            then Name (Dot + 1 .. Name'Last)
            else Name);
      begin
         return FT.Lowercase (UString_Value (Base.Kind)) = "record"
           and then Tail'Length > 11
           and then Tail (Tail'First .. Tail'First + 10) = "__optional_";
      end;
   end Is_Optional_Type;

   function Is_Sum_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean
   is
      Base : constant GM.Type_Descriptor := Base_Type (Info, Type_Env);
   begin
      return not Base.Sum_Variants.Is_Empty
        or else Current_Sum_Type_Tag_Names.Contains (Canonical_Name (UString_Value (Base.Name)));
   end Is_Sum_Type;

   function Is_Plain_Record_Type
     (Info     : GM.Type_Descriptor;
     Type_Env : Type_Maps.Map) return Boolean
   is
      Base : constant GM.Type_Descriptor := Base_Type (Info, Type_Env);
   begin
      return FT.Lowercase (UString_Value (Base.Kind)) = "record"
        and then not Is_Optional_Type (Base, Type_Env)
        and then not Base.Has_Discriminant
        and then Base.Discriminants.Is_Empty
        and then Base.Variant_Fields.Is_Empty
        and then not Base.Is_Result_Builtin;
   end Is_Plain_Record_Type;

   function Is_Interface_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean
   is
   begin
      return FT.Lowercase (UString_Value (Base_Type (Info, Type_Env).Kind)) = "interface";
   end Is_Interface_Type;

   function Is_Generic_Formal_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean
   is
   begin
      return FT.Lowercase (UString_Value (Base_Type (Info, Type_Env).Kind)) = "generic_formal";
   end Is_Generic_Formal_Type;

   function Optional_Payload_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return GM.Type_Descriptor
   is
      Base : constant GM.Type_Descriptor := Base_Type (Info, Type_Env);
   begin
      for Field of Base.Variant_Fields loop
         if UString_Value (Field.Name) = "value" then
            return Resolve_Type (UString_Value (Field.Type_Name), Type_Env, "", FT.Null_Span);
         end if;
      end loop;
      Raise_Diag
        (CM.Source_Frontend_Error
           (Path    => "",
            Span    => FT.Null_Span,
            Message =>
              "internal error: malformed synthetic optional type `"
              & UString_Value (Base.Name)
              & "` is missing variant field `value`"));
      return Default_Integer;
   end Optional_Payload_Type;

   function Is_Optional_Element_Type_Allowed
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean
   is
   begin
      return Is_Container_Element_Type_Allowed (Info, Type_Env);
   end Is_Optional_Element_Type_Allowed;

   function Is_Container_Element_Type_Allowed
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean
   is
      Base : constant GM.Type_Descriptor := Base_Type (Info, Type_Env);
      Kind : constant String := FT.Lowercase (UString_Value (Base.Kind));
   begin
      if Kind = "generic_formal" then
         return True;
      end if;
      if Kind in "access" | "incomplete" | "null" then
         return False;
      end if;

      return Is_Definite_Type (Info, Type_Env)
        and then not Contains_Channel_Reference_Subcomponent (Info, Type_Env);
   end Is_Container_Element_Type_Allowed;

   function Is_Shared_Field_Type_Allowed
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean
   is
      Base : constant GM.Type_Descriptor := Base_Type (Info, Type_Env);
      Kind : constant String := FT.Lowercase (UString_Value (Base.Kind));
   begin
      if Is_Interface_Type (Base, Type_Env)
        or else Kind in "access" | "incomplete" | "generic_formal" | "null"
        or else Contains_Channel_Reference_Subcomponent (Base, Type_Env)
      then
         return False;
      elsif Is_String_Type (Base, Type_Env) then
         return True;
      elsif Is_Optional_Type (Base, Type_Env) then
         return Is_Shared_Field_Type_Allowed
           (Optional_Payload_Type (Base, Type_Env), Type_Env);
      elsif Kind = "array" then
         return Base.Has_Component_Type
           and then Is_Shared_Field_Type_Allowed
             (Resolve_Type
                (UString_Value (Base.Component_Type),
                 Type_Env,
                 "",
                 FT.Null_Span),
              Type_Env);
      elsif Kind = "tuple" then
         for Item of Base.Tuple_Element_Types loop
            if not Is_Shared_Field_Type_Allowed
              (Resolve_Type (UString_Value (Item), Type_Env, "", FT.Null_Span),
               Type_Env)
            then
               return False;
            end if;
         end loop;
         return True;
      elsif Kind = "record" then
         if Base.Has_Discriminant
           or else not Base.Discriminants.Is_Empty
           or else not Base.Variant_Fields.Is_Empty
           or else Base.Is_Result_Builtin
         then
            return False;
         end if;
         for Field of Base.Fields loop
            if not Is_Shared_Field_Type_Allowed
              (Resolve_Type (UString_Value (Field.Type_Name), Type_Env, "", FT.Null_Span),
               Type_Env)
            then
               return False;
            end if;
         end loop;
         return True;
      end if;

      return Kind in "integer" | "float" | "binary" | "enum" | "subtype"
        or else Is_Boolean_Type (Base, Type_Env);
   end Is_Shared_Field_Type_Allowed;

   function Is_Shared_Record_Root_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean
   is
      Base : constant GM.Type_Descriptor := Base_Type (Info, Type_Env);
      Kind : constant String := FT.Lowercase (UString_Value (Base.Kind));
   begin
      return Kind = "record"
        and then not Is_Optional_Type (Base, Type_Env)
        and then not Base.Has_Discriminant
        and then Base.Discriminants.Is_Empty
        and then Base.Variant_Fields.Is_Empty;
   end Is_Shared_Record_Root_Type;

   function Is_Shared_Container_Root_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean is
   begin
      return Is_Growable_Array_Type (Info, Type_Env);
   end Is_Shared_Container_Root_Type;

   function Is_Shared_Root_Type_Allowed
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean is
   begin
      return
        (Is_Shared_Record_Root_Type (Info, Type_Env)
         or else Is_Shared_Container_Root_Type (Info, Type_Env))
        and then Is_Shared_Field_Type_Allowed (Info, Type_Env);
   end Is_Shared_Root_Type_Allowed;

   function Shared_Wrapper_Object_Name (Root_Name : String) return String is
   begin
      return
        "Safe_Shared_"
        & Sanitize_Type_Name_Component (Canonical_Name (Root_Name));
   end Shared_Wrapper_Object_Name;

   function Shared_Public_Helper_Base_Name (Root_Name : String) return String is
   begin
      return
        "Safe_Public_Shared_"
        & Sanitize_Type_Name_Component (Canonical_Name (Root_Name));
   end Shared_Public_Helper_Base_Name;

   function Shared_Public_Helper_Name
     (Root_Name : String;
      Operation : String) return String
   is
   begin
      return Shared_Public_Helper_Base_Name (Root_Name) & "_" & Operation;
   end Shared_Public_Helper_Name;

   function Shared_Get_All_Name return String is
   begin
      return "Get_All";
   end Shared_Get_All_Name;

   function Shared_Set_All_Name return String is
   begin
      return "Set_All";
   end Shared_Set_All_Name;

   function Shared_Get_Length_Name return String is
   begin
      return "Get_Length";
   end Shared_Get_Length_Name;

   function Shared_Append_Name return String is
   begin
      return "Append";
   end Shared_Append_Name;

   function Shared_Pop_Last_Name return String is
   begin
      return "Pop_Last";
   end Shared_Pop_Last_Name;

   function Shared_Contains_Name return String is
   begin
      return "Contains";
   end Shared_Contains_Name;

   function Shared_Get_Name return String is
   begin
      return "Get";
   end Shared_Get_Name;

   function Shared_Set_Name return String is
   begin
      return "Set";
   end Shared_Set_Name;

   function Shared_Remove_Name return String is
   begin
      return "Remove";
   end Shared_Remove_Name;

   function Shared_Field_Getter_Name (Field_Name : String) return String is
   begin
      return
        "Get_" & Sanitize_Type_Name_Component (Canonical_Name (Field_Name));
   end Shared_Field_Getter_Name;

   function Shared_Field_Setter_Name (Field_Name : String) return String is
   begin
      return
        "Set_" & Sanitize_Type_Name_Component (Canonical_Name (Field_Name));
   end Shared_Field_Setter_Name;

   function Shared_Nested_Field_Setter_Name
     (Path_Names : FT.UString_Vectors.Vector) return String
   is
      Result : FT.UString := FT.To_UString ("Set_Path");
   begin
      for Name of Path_Names loop
         Result :=
           FT.To_UString
             (UString_Value (Result)
              & "_"
              & Sanitize_Type_Name_Component (Canonical_Name (UString_Value (Name))));
      end loop;
      return UString_Value (Result);
   end Shared_Nested_Field_Setter_Name;

   procedure Stamp_Contextual_String_Literal
     (Expr      : CM.Expr_Access;
      Type_Info : GM.Type_Descriptor;
      Type_Env  : Type_Maps.Map) is
   begin
      if Expr /= null
        and then Expr.Kind = CM.Expr_String
        and then UString_Value (Type_Info.Name)'Length > 0
        and then
          (Is_Bounded_String_Type (Type_Info, Type_Env)
           or else Is_String_Type (Type_Info, Type_Env))
      then
         Expr.Type_Name := Type_Info.Name;
      end if;
   end Stamp_Contextual_String_Literal;

   function Shared_Snapshot_Expr
     (Shared : Shared_Object_Ref;
      Span   : FT.Source_Span) return CM.Expr_Access
   is
   begin
      return
        Shared_Call_Expr
          (Shared    => Shared,
           Operation => Shared_Get_All_Name,
           Span      => Span,
           Type_Name => UString_Value (Shared.Type_Info.Name));
   end Shared_Snapshot_Expr;

   function Shared_Wrapper_Call_Expr
     (Root_Name : String;
      Selector  : String;
      Span      : FT.Source_Span;
      Type_Name : String := "") return CM.Expr_Access
   is
      Result : constant CM.Expr_Access := new CM.Expr_Node;
   begin
      Result.Kind := CM.Expr_Call;
      Result.Span := Span;
      Result.Type_Name := FT.To_UString (Type_Name);
      Result.Callee :=
        Selector_Expr
          (Prefix    =>
             Ident_Expr
               (Shared_Wrapper_Object_Name (Root_Name),
                Span,
                ""),
           Selector  => Selector,
           Span      => Span,
           Type_Name => Type_Name);
      return Result;
   end Shared_Wrapper_Call_Expr;

   function Shared_Public_Helper_Call_Expr
     (Package_Name : String;
      Root_Name    : String;
      Operation    : String;
      Span         : FT.Source_Span;
      Type_Name    : String := "") return CM.Expr_Access
   is
      Result      : constant CM.Expr_Access := new CM.Expr_Node;
      Helper_Name : constant String := Shared_Public_Helper_Name (Root_Name, Operation);
   begin
      Result.Kind := CM.Expr_Call;
      Result.Span := Span;
      Result.Type_Name := FT.To_UString (Type_Name);
      if Package_Name'Length = 0 then
         Result.Callee := Ident_Expr (Helper_Name, Span, Type_Name);
      else
         Result.Callee :=
           Selector_Expr
             (Prefix    => Ident_Expr (Package_Name, Span, ""),
              Selector  => Helper_Name,
              Span      => Span,
              Type_Name => Type_Name);
      end if;
      return Result;
   end Shared_Public_Helper_Call_Expr;

   function Shared_Call_Expr
     (Shared    : Shared_Object_Ref;
      Operation : String;
      Span      : FT.Source_Span;
      Type_Name : String := "") return CM.Expr_Access
   is
   begin
      case Shared.Kind is
         when Shared_Object_Local_Private =>
            return
              Shared_Wrapper_Call_Expr
                (Root_Name  => UString_Value (Shared.Root_Name),
                 Selector   => Operation,
                 Span       => Span,
                 Type_Name  => Type_Name);
         when Shared_Object_Local_Public =>
            return
              Shared_Public_Helper_Call_Expr
                (Package_Name => "",
                 Root_Name    => UString_Value (Shared.Root_Name),
                 Operation    => Operation,
                 Span         => Span,
                 Type_Name    => Type_Name);
         when Shared_Object_Imported_Public =>
            return
              Shared_Public_Helper_Call_Expr
                (Package_Name => UString_Value (Shared.Package_Name),
                 Root_Name    => UString_Value (Shared.Root_Name),
                 Operation    => Operation,
                 Span         => Span,
                 Type_Name    => Type_Name);
         when others =>
            return Shared_Wrapper_Call_Expr ("", Operation, Span, Type_Name);
      end case;
   end Shared_Call_Expr;

   function Is_Shared_Object_Name (Name : String) return Boolean is
      Key : constant String := Canonical_Name (Name);
   begin
      return Key'Length > 0 and then Current_Shared_Object_Types.Contains (Key);
   end Is_Shared_Object_Name;

   function Try_Shared_Root_Expr
     (Expr   : CM.Expr_Access;
      Shared : out Shared_Object_Ref) return Boolean
   is
      Flat_Name : constant String := CM.Flatten_Name (Expr);
      Root_Key  : constant String := Canonical_Name (Flat_Name);
      Dot_Index : Natural := 0;
   begin
      Shared := (others => <>);

      if Expr = null then
         return False;
      elsif Root_Key /= ""
        and then Current_Shared_Object_Types.Contains (Root_Key)
      then
         Shared.Kind :=
           (if Current_Public_Shared_Object_Types.Contains (Root_Key)
            then Shared_Object_Local_Public
            else Shared_Object_Local_Private);
         Shared.Root_Name := FT.To_UString (Flat_Name);
         Shared.Type_Info := Current_Shared_Object_Types.Element (Root_Key);
         return True;
      elsif Root_Key /= ""
        and then Current_Imported_Shared_Object_Types.Contains (Root_Key)
      then
         for Index in reverse Flat_Name'Range loop
            if Flat_Name (Index) = '.' then
               Dot_Index := Index;
               exit;
            end if;
         end loop;
         if Dot_Index = 0 then
            return False;
         end if;
         Shared.Kind := Shared_Object_Imported_Public;
         Shared.Package_Name :=
           FT.To_UString (Flat_Name (Flat_Name'First .. Dot_Index - 1));
         Shared.Root_Name :=
           FT.To_UString (Flat_Name (Dot_Index + 1 .. Flat_Name'Last));
         Shared.Type_Info := Current_Imported_Shared_Object_Types.Element (Root_Key);
         return True;
      end if;

      return False;
   end Try_Shared_Root_Expr;

   function Try_Shared_Target_Expr
     (Expr   : CM.Expr_Access;
      Shared : out Shared_Object_Ref) return Boolean
   is
      Current : CM.Expr_Access := Expr;
   begin
      Shared := (others => <>);
      while Current /= null loop
         if Try_Shared_Root_Expr (Current, Shared) then
            return True;
         end if;

         case Current.Kind is
            when CM.Expr_Select | CM.Expr_Resolved_Index =>
               Current := Current.Prefix;
            when CM.Expr_Conversion =>
               Current := Current.Inner;
            when others =>
               Current := null;
         end case;
      end loop;

      return False;
   end Try_Shared_Target_Expr;

   function Try_Shared_Wrapper_Root_Name_Expr
     (Expr      : CM.Expr_Access;
      Root_Name : out FT.UString;
      Root_Type : out GM.Type_Descriptor) return Boolean
   is
   begin
      Root_Name := FT.To_UString ("");
      Root_Type := (others => <>);

      if Expr = null or else Expr.Kind /= CM.Expr_Ident then
         return False;
      end if;

      declare
         Wrapper_Key : constant String := Canonical_Name (UString_Value (Expr.Name));
      begin
         for Cursor in Current_Shared_Object_Types.Iterate loop
            declare
               Candidate_Root : constant String := Type_Maps.Key (Cursor);
            begin
               if Canonical_Name (Shared_Wrapper_Object_Name (Candidate_Root)) = Wrapper_Key then
                  Root_Name := FT.To_UString (Candidate_Root);
                  Root_Type := Type_Maps.Element (Cursor);
                  return True;
               end if;
            end;
         end loop;
      end;

      return False;
   end Try_Shared_Wrapper_Root_Name_Expr;

   function Try_Shared_Public_Helper_Call
     (Expr      : CM.Expr_Access;
      Operation : String;
      Shared    : out Shared_Object_Ref) return Boolean
   is
      Name_Key : constant String := Canonical_Name (CM.Flatten_Name (Expr));
   begin
      Shared := (others => <>);

      if Expr = null or else Name_Key = "" then
         return False;
      end if;

      for Cursor in Current_Public_Shared_Object_Types.Iterate loop
         declare
            Candidate_Root : constant String := Type_Maps.Key (Cursor);
         begin
            if Name_Key = Canonical_Name (Shared_Public_Helper_Name (Candidate_Root, Operation)) then
               Shared.Kind := Shared_Object_Local_Public;
               Shared.Root_Name := FT.To_UString (Candidate_Root);
               Shared.Type_Info := Type_Maps.Element (Cursor);
               return True;
            end if;
         end;
      end loop;

      for Cursor in Current_Imported_Shared_Object_Types.Iterate loop
         declare
            Qualified_Root  : constant String := Type_Maps.Key (Cursor);
            Dot_Index       : Natural := 0;
         begin
            for Index in reverse Qualified_Root'Range loop
               if Qualified_Root (Index) = '.' then
                  Dot_Index := Index;
                  exit;
               end if;
            end loop;

            if Dot_Index > 0 then
               declare
                  Package_Name   : constant String :=
                    Qualified_Root (Qualified_Root'First .. Dot_Index - 1);
                  Root_Name_Text : constant String :=
                    Qualified_Root (Dot_Index + 1 .. Qualified_Root'Last);
               begin
                  if Name_Key =
                    Canonical_Name
                      (Package_Name & "." & Shared_Public_Helper_Name (Root_Name_Text, Operation))
                  then
                     Shared.Kind := Shared_Object_Imported_Public;
                     Shared.Package_Name := FT.To_UString (Package_Name);
                     Shared.Root_Name := FT.To_UString (Root_Name_Text);
                     Shared.Type_Info := Type_Maps.Element (Cursor);
                     return True;
                  end if;
               end;
            end if;
         end;
      end loop;

      return False;
   end Try_Shared_Public_Helper_Call;

   function Try_Shared_Top_Level_Field_Access
     (Expr       : CM.Expr_Access;
      Type_Env   : Type_Maps.Map;
      Shared     : out Shared_Object_Ref;
      Field_Type : out GM.Type_Descriptor) return Boolean
   is
      Shared_Type : GM.Type_Descriptor;
   begin
      Shared := (others => <>);
      Field_Type := (others => <>);

      if Expr = null
        or else Expr.Kind /= CM.Expr_Select
        or else Expr.Prefix = null
      then
         return False;
      end if;

      if not Try_Shared_Root_Expr (Expr.Prefix, Shared) then
         return False;
      end if;

      Shared_Type := Shared.Type_Info;
      for Field of Base_Type (Shared_Type, Type_Env).Fields loop
         if Canonical_Name (UString_Value (Field.Name))
           = Canonical_Name (UString_Value (Expr.Selector))
         then
            Field_Type :=
              Resolve_Type (UString_Value (Field.Type_Name), Type_Env, "", FT.Null_Span);
            return True;
         end if;
      end loop;

      return False;
   end Try_Shared_Top_Level_Field_Access;

   function Try_Shared_Nested_Field_Access
     (Expr       : CM.Expr_Access;
      Type_Env   : Type_Maps.Map;
      Shared     : out Shared_Object_Ref;
      Path_Names : out FT.UString_Vectors.Vector;
      Field_Type : out GM.Type_Descriptor) return Boolean
   is
      Current     : CM.Expr_Access := Expr;
      Shared_Type : GM.Type_Descriptor;
      Leaf_First  : FT.UString_Vectors.Vector;
      Found_Root  : Boolean := False;
   begin
      Shared := (others => <>);
      Path_Names.Clear;
      Field_Type := (others => <>);

      while Current /= null and then Current.Kind = CM.Expr_Select loop
         Leaf_First.Append (Current.Selector);
         Current := Current.Prefix;
         if Try_Shared_Root_Expr (Current, Shared) then
            Found_Root := True;
            exit;
         end if;
      end loop;

      if not Found_Root
        or else Current = null
        or else Natural (Leaf_First.Length) < 2
        or else not Try_Shared_Root_Expr (Current, Shared)
      then
         return False;
      end if;

      Shared_Type := Shared.Type_Info;
      for Index in reverse Leaf_First.First_Index .. Leaf_First.Last_Index loop
         declare
            Base    : constant GM.Type_Descriptor := Base_Type (Shared_Type, Type_Env);
            Matched : Boolean := False;
         begin
            if not Is_Plain_Record_Type (Shared_Type, Type_Env) then
               Path_Names.Clear;
               return False;
            end if;

            for Field of Base.Fields loop
               if Canonical_Name (UString_Value (Field.Name))
                 = Canonical_Name (UString_Value (Leaf_First (Index)))
               then
                  Path_Names.Append (Field.Name);
                  Shared_Type :=
                    Resolve_Type (UString_Value (Field.Type_Name), Type_Env, "", FT.Null_Span);
                  Matched := True;
                  exit;
               end if;
            end loop;

            if not Matched then
               Path_Names.Clear;
               return False;
            end if;
         end;
      end loop;

      Field_Type := Shared_Type;
      return True;
   end Try_Shared_Nested_Field_Access;

   procedure Reject_Bare_Shared_Object_Expr
     (Expr      : CM.Expr_Access;
      Type_Env  : Type_Maps.Map;
      Path      : String) is
      Shared     : Shared_Object_Ref;
      Field_Type : GM.Type_Descriptor;
   begin
      if Expr = null then
         return;
      end if;

      case Expr.Kind is
         when CM.Expr_Ident =>
            null;
         when CM.Expr_Select =>
            if not Try_Shared_Top_Level_Field_Access
                    (Expr       => Expr,
                     Type_Env   => Type_Env,
                     Shared     => Shared,
                     Field_Type => Field_Type)
            then
               Reject_Bare_Shared_Object_Expr (Expr.Prefix, Type_Env, Path);
            end if;
         when CM.Expr_Conversion | CM.Expr_Annotated =>
            Reject_Bare_Shared_Object_Expr (Expr.Inner, Type_Env, Path);
         when CM.Expr_Unary | CM.Expr_Try | CM.Expr_Some =>
            Reject_Bare_Shared_Object_Expr (Expr.Prefix, Type_Env, Path);
            Reject_Bare_Shared_Object_Expr (Expr.Inner, Type_Env, Path);
         when CM.Expr_Binary =>
            Reject_Bare_Shared_Object_Expr (Expr.Left, Type_Env, Path);
            Reject_Bare_Shared_Object_Expr (Expr.Right, Type_Env, Path);
         when CM.Expr_Allocator =>
            Reject_Bare_Shared_Object_Expr (Expr.Value, Type_Env, Path);
            Reject_Bare_Shared_Object_Expr (Expr.Target, Type_Env, Path);
         when CM.Expr_Resolved_Index | CM.Expr_Call | CM.Expr_Apply =>
            Reject_Bare_Shared_Object_Expr (Expr.Prefix, Type_Env, Path);
            Reject_Bare_Shared_Object_Expr (Expr.Callee, Type_Env, Path);
            for Item of Expr.Args loop
               Reject_Bare_Shared_Object_Expr (Item, Type_Env, Path);
            end loop;
         when CM.Expr_Aggregate =>
            for Item of Expr.Fields loop
               Reject_Bare_Shared_Object_Expr (Item.Expr, Type_Env, Path);
            end loop;
         when CM.Expr_Array_Literal | CM.Expr_Tuple =>
            for Item of Expr.Elements loop
               Reject_Bare_Shared_Object_Expr (Item, Type_Env, Path);
            end loop;
         when others =>
            null;
      end case;
   end Reject_Bare_Shared_Object_Expr;

   function Try_Static_String_Length
     (Expr   : CM.Expr_Access;
      Length : out Natural) return Boolean
   is
      Quote : constant Character := Character'Val (34);
   begin
      Length := 0;

      if Expr = null or else Expr.Kind /= CM.Expr_String then
         return False;
      end if;

      declare
         Text : constant String := UString_Value (Expr.Text);
         Last : Natural;
         Pos  : Natural;
      begin
         if Text'Length < 2
           or else Text (Text'First) /= Quote
           or else Text (Text'Last) /= Quote
         then
            return False;
         end if;

         Last := Text'Last - 1;
         Pos := Text'First + 1;

         while Pos <= Last loop
            if Text (Pos) = Quote then
               if Pos < Last and then Text (Pos + 1) = Quote then
                  Length := Length + 1;
                  Pos := Pos + 2;
               else
                  return False;
               end if;
            else
               Length := Length + 1;
               Pos := Pos + 1;
            end if;
         end loop;
      end;

      return True;
   end Try_Static_String_Length;

   procedure Reject_Static_Bounded_String_Overflow
     (Source_Expr : CM.Expr_Access;
      Target      : GM.Type_Descriptor;
      Type_Env    : Type_Maps.Map;
      Path        : String;
      Span        : FT.Source_Span)
   is
      Base_Target   : constant GM.Type_Descriptor := Base_Type (Target, Type_Env);
      Capacity      : Natural := 0;
      Static_Length : Natural := 0;
   begin
      if Bounded_String_Capacity (Target, Type_Env, Capacity) then
         if Try_Static_String_Length (Source_Expr, Static_Length)
           and then Static_Length > Capacity
         then
            Raise_Diag
              (CM.Source_Frontend_Error
                 (Path    => Path,
                  Span    => (if Source_Expr = null then Span else Source_Expr.Span),
                  Message => "string value length exceeds bounded string capacity"));
         end if;
         return;
      end if;

      if Is_Tuple_Type (Target, Type_Env)
        and then Source_Expr /= null
        and then Source_Expr.Kind = CM.Expr_Tuple
      then
         declare
            Tuple_Type : constant GM.Type_Descriptor := Base_Type (Target, Type_Env);
         begin
            if Natural (Source_Expr.Elements.Length) =
              Natural (Tuple_Type.Tuple_Element_Types.Length)
            then
               for Index in Source_Expr.Elements.First_Index .. Source_Expr.Elements.Last_Index loop
                  Reject_Static_Bounded_String_Overflow
                    (Source_Expr.Elements (Index),
                     Resolve_Type
                       (UString_Value (Tuple_Type.Tuple_Element_Types (Index)),
                        Type_Env,
                        "",
                        FT.Null_Span),
                     Type_Env,
                     Path,
                     Source_Expr.Elements (Index).Span);
               end loop;
            end if;
         end;
      elsif FT.Lowercase (UString_Value (Base_Target.Kind)) = "record"
        and then Source_Expr /= null
        and then Source_Expr.Kind = CM.Expr_Aggregate
      then
         for Item of Source_Expr.Fields loop
            declare
               Field_Target : GM.Type_Descriptor := Default_Integer;
               Found        : Boolean := False;
            begin
               for Field of Base_Target.Fields loop
                  if UString_Value (Field.Name) = UString_Value (Item.Field_Name) then
                     Field_Target :=
                       Resolve_Type
                         (UString_Value (Field.Type_Name),
                          Type_Env,
                          "",
                          FT.Null_Span);
                     Found := True;
                     exit;
                  end if;
               end loop;
               if Found then
                  Reject_Static_Bounded_String_Overflow
                    (Item.Expr,
                     Field_Target,
                     Type_Env,
                     Path,
                     Item.Span);
               end if;
            end;
         end loop;
      elsif FT.Lowercase (UString_Value (Base_Target.Kind)) = "array"
        and then Base_Target.Has_Component_Type
        and then Source_Expr /= null
        and then Source_Expr.Kind = CM.Expr_Array_Literal
      then
         declare
            Component_Type : constant GM.Type_Descriptor :=
              Resolve_Type
                (UString_Value (Base_Target.Component_Type),
                 Type_Env,
                 "",
                 FT.Null_Span);
         begin
            for Item of Source_Expr.Elements loop
               Reject_Static_Bounded_String_Overflow
                 (Item,
                  Component_Type,
                  Type_Env,
                  Path,
                  Item.Span);
            end loop;
         end;
      end if;
   end Reject_Static_Bounded_String_Overflow;

   function Make_Bounded_String_Type
     (Bound : Natural) return GM.Type_Descriptor
   is
      Result : GM.Type_Descriptor;
      Bound_Image : constant String :=
        Ada.Strings.Fixed.Trim (Natural'Image (Bound), Ada.Strings.Both);
   begin
      Result.Name := FT.To_UString ("__bounded_string_" & Bound_Image);
      Result.Kind := FT.To_UString ("string");
      Result.Has_Base := True;
      Result.Base := FT.To_UString ("string");
      Result.Has_Length_Bound := True;
      Result.Length_Bound := Bound;
      return Result;
   end Make_Bounded_String_Type;

   function Synthetic_Type_Tail_Name (Name : String) return String is
      Dot_Index : Natural := 0;
   begin
      for Index in reverse Name'Range loop
         if Name (Index) = '.' then
            Dot_Index := Index;
            exit;
         end if;
      end loop;
      if Dot_Index = 0 then
         return Name;
      end if;
      return Name (Dot_Index + 1 .. Name'Last);
   end Synthetic_Type_Tail_Name;

   function Is_Qualified_Synthetic_Name (Name : String) return Boolean is
   begin
      for Ch of Name loop
         if Ch = '.' then
            return True;
         end if;
      end loop;
      return False;
   end Is_Qualified_Synthetic_Name;

   function Synthetic_Type_Identity_Matches
     (Candidate_Name : String;
      Existing_Name  : String) return Boolean is
   begin
      if Canonical_Name (Candidate_Name) = Canonical_Name (Existing_Name) then
         return True;
      end if;

      if Is_Qualified_Synthetic_Name (Candidate_Name)
        and then Is_Qualified_Synthetic_Name (Existing_Name)
      then
         return False;
      end if;

      return Synthetic_Type_Tail_Name (Candidate_Name) =
        Synthetic_Type_Tail_Name (Existing_Name);
   end Synthetic_Type_Identity_Matches;

   function Reuse_Equivalent_Synthetic_Type
     (Candidate : GM.Type_Descriptor;
      Type_Env  : Type_Maps.Map) return GM.Type_Descriptor
   is
      Candidate_Name : constant String := UString_Value (Candidate.Name);
      Candidate_Kind : constant String :=
        FT.Lowercase (UString_Value (Candidate.Kind));
      function Matches (Existing : GM.Type_Descriptor) return Boolean is
         Existing_Name : constant String := UString_Value (Existing.Name);
         Existing_Kind : constant String :=
           FT.Lowercase (UString_Value (Existing.Kind));
      begin
         return
           Synthetic_Type_Identity_Matches (Candidate_Name, Existing_Name)
           and then
             (Candidate_Kind = ""
              or else Existing_Kind = ""
              or else Existing_Kind = Candidate_Kind);
      end Matches;
   begin
      if Has_Type (Type_Env, UString_Value (Candidate.Name)) then
         return Get_Type (Type_Env, UString_Value (Candidate.Name));
      end if;

      for Cursor in Current_Imported_Synthetic_Types.Iterate loop
         declare
            Existing : constant GM.Type_Descriptor := Type_Maps.Element (Cursor);
         begin
            if Matches (Existing) then
               return Existing;
            end if;
         end;
      end loop;

      for Cursor in Type_Env.Iterate loop
         declare
            Existing : constant GM.Type_Descriptor := Type_Maps.Element (Cursor);
         begin
            if Matches (Existing) then
               return Existing;
            end if;
         end;
      end loop;

      return Candidate;
   end Reuse_Equivalent_Synthetic_Type;

   function Canonicalize_Imported_Synthetic_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return GM.Type_Descriptor
   is
      Name_Text : constant String := UString_Value (Info.Name);
      Tail_Text : constant String := Synthetic_Type_Tail_Name (Name_Text);
      Kind_Text : constant String := FT.Lowercase (UString_Value (Info.Kind));
      function Matches (Existing : GM.Type_Descriptor) return Boolean is
         Existing_Name : constant String := UString_Value (Existing.Name);
         Existing_Kind : constant String :=
           FT.Lowercase (UString_Value (Existing.Kind));
      begin
         return
           Synthetic_Type_Identity_Matches (Name_Text, Existing_Name)
           and then
             (Kind_Text = ""
              or else Existing_Kind = ""
              or else Existing_Kind = Kind_Text);
      end Matches;
   begin
      if Tail_Text'Length < 2
        or else Tail_Text (Tail_Text'First .. Tail_Text'First + 1) /= "__"
      then
         return Info;
      end if;

      for Cursor in Current_Imported_Synthetic_Types.Iterate loop
         declare
            Existing : constant GM.Type_Descriptor := Type_Maps.Element (Cursor);
         begin
            if Matches (Existing) then
               return Existing;
            end if;
         end;
      end loop;

      return Reuse_Equivalent_Synthetic_Type (Info, Type_Env);
   end Canonicalize_Imported_Synthetic_Type;

   function Make_Growable_Array_Type
     (Component_Type : GM.Type_Descriptor;
      Type_Env       : Type_Maps.Map) return GM.Type_Descriptor
   is
      Result : GM.Type_Descriptor;
      Sanitized : FT.UString := FT.To_UString ("");
      Text      : constant String := UString_Value (Component_Type.Name);
   begin
      for Ch of Text loop
         if Ch in 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' then
            Sanitized := Sanitized & FT.To_UString ((1 => Ch));
         else
            Sanitized := Sanitized & FT.To_UString ("_");
         end if;
      end loop;
      Result.Name :=
        FT.To_UString
          ("__growable_array_"
           & UString_Value (Sanitized));
      Result.Kind := FT.To_UString ("array");
      Result.Growable := True;
      Result.Has_Component_Type := True;
      Result.Component_Type := Component_Type.Name;
      Result := Reuse_Equivalent_Synthetic_Type (Result, Type_Env);
      Register_Synthetic_Helper_Type (Result);
      return Result;
   end Make_Growable_Array_Type;

   function Make_Optional_Type
     (Element_Type : GM.Type_Descriptor;
      Type_Env     : Type_Maps.Map) return GM.Type_Descriptor
   is
      Result  : GM.Type_Descriptor;
      Disc    : GM.Discriminant_Descriptor;
      Field   : GM.Type_Field;
      Variant : GM.Variant_Field;
   begin
      Result.Name :=
        FT.To_UString
          ("__optional_"
           & Sanitize_Type_Name_Component (UString_Value (Element_Type.Name)));
      if Has_Type (Type_Env, UString_Value (Result.Name)) then
         return Get_Type (Type_Env, UString_Value (Result.Name));
      end if;
      Result.Kind := FT.To_UString ("record");
      Result.Has_Discriminant := True;
      Result.Discriminant_Name := FT.To_UString ("present");
      Result.Discriminant_Type := FT.To_UString ("boolean");
      Result.Has_Discriminant_Default := True;
      Result.Discriminant_Default_Bool := False;

      Disc.Name := FT.To_UString ("present");
      Disc.Type_Name := FT.To_UString ("boolean");
      Disc.Has_Default := True;
      Disc.Default_Value.Kind := GM.Scalar_Value_Boolean;
      Disc.Default_Value.Bool_Value := False;
      Result.Discriminants.Append (Disc);

      Field.Name := FT.To_UString ("value");
      Field.Type_Name := Element_Type.Name;
      Result.Fields.Append (Field);

      Variant.Name := FT.To_UString ("value");
      Variant.Type_Name := Element_Type.Name;
      Variant.Choice.Kind := GM.Scalar_Value_Boolean;
      Variant.Choice.Bool_Value := True;
      Variant.When_True := True;
      Result.Variant_Discriminant_Name := FT.To_UString ("present");
      Result.Variant_Fields.Append (Variant);

      Result := Reuse_Equivalent_Synthetic_Type (Result, Type_Env);
      if not Has_Type (Synthetic_Optional_Types, UString_Value (Result.Name)) then
         Put_Type (Synthetic_Optional_Types, UString_Value (Result.Name), Result);
         Append_Unique_String (Synthetic_Optional_Order, UString_Value (Result.Name));
      end if;
      return Result;
   end Make_Optional_Type;

   function Growable_Array_Element_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return GM.Type_Descriptor
   is
      Current : GM.Type_Descriptor := Info;
   begin
      loop
         if FT.Lowercase (UString_Value (Current.Kind)) = "array"
           and then Current.Has_Component_Type
         then
            return Resolve_Type
              (UString_Value (Current.Component_Type),
               Type_Env,
               "",
               FT.Null_Span);
         end if;
         exit when not Current.Has_Base
           or else not Has_Type (Type_Env, UString_Value (Current.Base));
         Current := Get_Type (Type_Env, UString_Value (Current.Base));
      end loop;

      Raise_Diag
        (CM.Source_Frontend_Error
           (Path    => "",
            Span    => FT.Null_Span,
            Message =>
              "internal error: malformed synthetic growable-array type `"
              & UString_Value (Info.Name)
              & "` is missing component type information"));
      return Default_Integer;
   end Growable_Array_Element_Type;

   function Try_Map_Key_Value_Types
     (Info       : GM.Type_Descriptor;
      Type_Env   : Type_Maps.Map;
      Key_Type   : out GM.Type_Descriptor;
      Value_Type : out GM.Type_Descriptor) return Boolean
   is
      Entry_Type : GM.Type_Descriptor := Default_Integer;
   begin
      Key_Type := Default_Integer;
      Value_Type := Default_Integer;

      if not Is_Growable_Array_Type (Info, Type_Env) then
         return False;
      end if;

      Entry_Type := Base_Type (Growable_Array_Element_Type (Info, Type_Env), Type_Env);
      if FT.Lowercase (UString_Value (Entry_Type.Kind)) /= "tuple"
        or else Natural (Entry_Type.Tuple_Element_Types.Length) /= 2
      then
         return False;
      end if;

      Key_Type :=
        Resolve_Type
          (UString_Value (Entry_Type.Tuple_Element_Types (Entry_Type.Tuple_Element_Types.First_Index)),
           Type_Env,
           "",
           FT.Null_Span);
      Value_Type :=
        Resolve_Type
          (UString_Value (Entry_Type.Tuple_Element_Types (Entry_Type.Tuple_Element_Types.First_Index + 1)),
           Type_Env,
           "",
           FT.Null_Span);
      return True;
   end Try_Map_Key_Value_Types;

   function Is_Map_Key_Type_Allowed
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean is
   begin
      if Is_Generic_Formal_Type (Info, Type_Env) then
         return True;
      end if;
      return Is_Discrete_Case_Type (Info, Type_Env)
        or else Is_String_Type (Info, Type_Env);
   end Is_Map_Key_Type_Allowed;

   function Bool_Expr
     (Value : Boolean;
      Span  : FT.Source_Span) return CM.Expr_Access is
   begin
      return
        new CM.Expr_Node'
          (Kind       => CM.Expr_Bool,
           Span       => Span,
           Type_Name  => FT.To_UString ("boolean"),
           Bool_Value => Value,
           others     => <>);
   end Bool_Expr;

   function Int_Expr
     (Value : CM.Wide_Integer;
      Span  : FT.Source_Span) return CM.Expr_Access is
   begin
      return
        new CM.Expr_Node'
          (Kind      => CM.Expr_Int,
           Span      => Span,
           Type_Name => FT.To_UString ("integer"),
           Int_Value => Value,
           Text      =>
             FT.To_UString
               (Ada.Strings.Fixed.Trim
                  (CM.Wide_Integer'Image (Value),
                   Ada.Strings.Both)),
           others    => <>);
   end Int_Expr;

   function Binary_Expr
     (Left      : CM.Expr_Access;
      Operator  : String;
      Right     : CM.Expr_Access;
      Span      : FT.Source_Span;
      Type_Name : String) return CM.Expr_Access is
   begin
      return
        new CM.Expr_Node'
          (Kind      => CM.Expr_Binary,
           Span      => Span,
           Type_Name => FT.To_UString (Type_Name),
           Operator  => FT.To_UString (Operator),
           Left      => Left,
           Right     => Right,
           others    => <>);
   end Binary_Expr;

   function Resolved_Index_Expr
     (Prefix    : CM.Expr_Access;
      Arg_1     : CM.Expr_Access;
      Span      : FT.Source_Span;
      Type_Name : String;
      Arg_2     : CM.Expr_Access := null) return CM.Expr_Access
   is
      Result : constant CM.Expr_Access := new CM.Expr_Node;
   begin
      Result.Kind := CM.Expr_Resolved_Index;
      Result.Span := Span;
      Result.Type_Name := FT.To_UString (Type_Name);
      Result.Prefix := Prefix;
      Result.Args.Append (Arg_1);
      if Arg_2 /= null then
         Result.Args.Append (Arg_2);
      end if;
      return Result;
   end Resolved_Index_Expr;

   function Build_Optional_None_Expr
     (Optional_Type : GM.Type_Descriptor;
      Span          : FT.Source_Span) return CM.Expr_Access
   is
      Result : constant CM.Expr_Access := new CM.Expr_Node;
      Field  : CM.Aggregate_Field;
   begin
      Result.Kind := CM.Expr_Aggregate;
      Result.Span := Span;
      Result.Type_Name := Optional_Type.Name;

      Field.Field_Name := FT.To_UString ("present");
      Field.Expr := Bool_Expr (False, Span);
      Field.Span := Span;
      Result.Fields.Append (Field);
      return Result;
   end Build_Optional_None_Expr;

   function Build_Optional_Some_Expr
     (Optional_Type : GM.Type_Descriptor;
      Value_Expr    : CM.Expr_Access;
      Span          : FT.Source_Span) return CM.Expr_Access
   is
      Result : constant CM.Expr_Access := new CM.Expr_Node;
      Field  : CM.Aggregate_Field;
   begin
      Result.Kind := CM.Expr_Aggregate;
      Result.Span := Span;
      Result.Type_Name := Optional_Type.Name;

      Field.Field_Name := FT.To_UString ("present");
      Field.Expr := Bool_Expr (True, Span);
      Field.Span := Span;
      Result.Fields.Append (Field);

      Field.Field_Name := FT.To_UString ("value");
      Field.Expr := Value_Expr;
      Field.Span := (if Value_Expr = null then Span else Value_Expr.Span);
      Result.Fields.Append (Field);
      return Result;
   end Build_Optional_Some_Expr;

   function Build_Sum_Constructor_Expr
     (Constructor : Sum_Constructor_Info;
      Args        : CM.Expr_Access_Vectors.Vector;
      Span        : FT.Source_Span) return CM.Expr_Access
   is
      Result : constant CM.Expr_Access := new CM.Expr_Node;
      Field  : CM.Aggregate_Field;
      Tag_Expr : constant CM.Expr_Access := new CM.Expr_Node'
        (Kind      => CM.Expr_Enum_Literal,
         Span      => Span,
         Type_Name => Constructor.Tag_Type_Name,
         Name      => Constructor.Tag_Literal_Name,
         others    => <>);
   begin
      Result.Kind := CM.Expr_Aggregate;
      Result.Span := Span;
      Result.Type_Name := Constructor.Sum_Type_Name;

      Field.Field_Name := FT.To_UString (Sum_Discriminant_Name (UString_Value (Constructor.Sum_Type_Name)));
      Field.Expr := Tag_Expr;
      Field.Span := Span;
      Result.Fields.Append (Field);

      if not Constructor.Fields.Is_Empty then
         for Index in Constructor.Fields.First_Index .. Constructor.Fields.Last_Index loop
            Field.Field_Name := Constructor.Fields (Index).Name;
            Field.Expr := Args (Index);
            Field.Span := (if Args (Index) = null then Span else Args (Index).Span);
            Result.Fields.Append (Field);
         end loop;
      end if;

      return Result;
   end Build_Sum_Constructor_Expr;

   function Hidden_Reference_Target_Name (Name : String) return String is
   begin
      return "safe_ref_target_" & Sanitize_Type_Name_Component (Name);
   end Hidden_Reference_Target_Name;

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
      return UString_Value (Base.Name) = "duration"
        or else Kind in "integer" | "float" | "subtype";
   end Is_Duration_Compatible;

   function Is_Integerish
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean
   is
      Base : constant GM.Type_Descriptor := Base_Type (Info, Type_Env);
      Kind : constant String := FT.Lowercase (UString_Value (Base.Kind));
   begin
      return Kind = "integer";
   end Is_Integerish;

   function Is_Enum_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean
   is
      Base : constant GM.Type_Descriptor := Base_Type (Info, Type_Env);
   begin
      return FT.Lowercase (UString_Value (Base.Kind)) = "enum";
   end Is_Enum_Type;

   function Is_Binary_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean
   is
      Base : constant GM.Type_Descriptor := Base_Type (Info, Type_Env);
   begin
      return FT.Lowercase (UString_Value (Base.Kind)) = "binary"
        and then Base.Has_Bit_Width;
   end Is_Binary_Type;

   function Binary_Bit_Width
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Positive
   is
      Base : constant GM.Type_Descriptor := Base_Type (Info, Type_Env);
   begin
      return Base.Bit_Width;
   end Binary_Bit_Width;

   function Is_Discrete_Case_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean is
   begin
      return Is_Boolean_Type (Info, Type_Env)
        or else Is_Binary_Type (Info, Type_Env)
        or else Is_Enum_Type (Info, Type_Env)
        or else (Is_Integerish (Info, Type_Env) and then not Is_Boolean_Type (Info, Type_Env));
   end Is_Discrete_Case_Type;

   function Case_Choice_Compatible
     (Scrutinee : GM.Type_Descriptor;
      Choice    : GM.Type_Descriptor;
      Type_Env  : Type_Maps.Map) return Boolean is
   begin
      if Is_Boolean_Type (Scrutinee, Type_Env) then
         return Is_Boolean_Type (Choice, Type_Env);
      elsif Is_Enum_Type (Scrutinee, Type_Env) then
         return Equivalent_Type (Scrutinee, Choice, Type_Env);
      elsif Is_String_Type (Scrutinee, Type_Env) then
         return Is_String_Type (Choice, Type_Env);
      elsif Is_Binary_Type (Scrutinee, Type_Env) then
         return Is_Binary_Type (Choice, Type_Env)
           and then Binary_Bit_Width (Scrutinee, Type_Env) = Binary_Bit_Width (Choice, Type_Env);
      end if;

      return Is_Integerish (Scrutinee, Type_Env)
        and then not Is_Boolean_Type (Scrutinee, Type_Env)
        and then not Is_Enum_Type (Scrutinee, Type_Env)
        and then Is_Integerish (Choice, Type_Env)
        and then not Is_Boolean_Type (Choice, Type_Env)
        and then not Is_Enum_Type (Choice, Type_Env)
        and then not Is_String_Type (Choice, Type_Env);
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
      elsif Kind = "generic_formal" then
         return True;
      elsif Kind = "interface" then
         return False;
      elsif Info_Kind = "subtype" and then not Info.Discriminant_Constraints.Is_Empty then
         return True;
      elsif Kind = "array" then
         return Base.Growable or else not Base.Unconstrained;
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

   function Contains_Channel_Reference_Subcomponent
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
         return Contains_Channel_Reference_Subcomponent (Get_Type (Type_Env, Name), Type_Env);
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
   end Contains_Channel_Reference_Subcomponent;

   function Contains_Dot (Name : String) return Boolean is
   begin
      for Ch of Name loop
         if Ch = '.' then
            return True;
         end if;
      end loop;
      return False;
   end Contains_Dot;

   function Is_Imported_Channel_Reference
     (Channel_Expr : CM.Expr_Access) return Boolean
   is
      Name : constant String := CM.Flatten_Name (Channel_Expr);
   begin
      return Contains_Dot (Name);
   end Is_Imported_Channel_Reference;

   function Is_Builtin_Name (Name : String) return Boolean is
   begin
      return Name in
        "integer" | "boolean" | "string" | "float" | "long_float" | "duration" | "result";
   end Is_Builtin_Name;

   function Is_Removed_Integer_Builtin_Name (Name : String) return Boolean is
   begin
      return Name in
        "natural" | "positive" | "short" | "byte" | "long_long_integer" | "long_long_long_integer";
   end Is_Removed_Integer_Builtin_Name;

   function Removed_Integer_Builtin_Message (Name : String) return String is
   begin
      return
        "PR11.8 removed predefined integer-family type `"
        & Name
        & "`; use `integer` or a constrained subtype";
   end Removed_Integer_Builtin_Message;

   function Qualify_Name
     (Package_Name : String;
      Name         : String) return String
   is
      Lowered : constant String := FT.Lowercase (Name);
   begin
      if Name = ""
        or else Is_Builtin_Name (Name)
        or else (Name'Length >= 2 and then Name (Name'First .. Name'First + 1) = "__")
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
      function Is_Local_Generic_Formal_Name (Name : String) return Boolean is
      begin
         if not Result.Generic_Formals.Is_Empty then
            for Formal of Result.Generic_Formals loop
               if UString_Value (Formal.Name) = Name then
                  return True;
               end if;
            end loop;
         end if;
         return False;
      end Is_Local_Generic_Formal_Name;

      function Qualify_Type_Name_Unless_Formal (Name : String) return String is
         Lowered : constant String := FT.Lowercase (Name);
      begin
         if Is_Local_Generic_Formal_Name (Name) then
            return Name;
         elsif Name = ""
           or else Is_Builtin_Name (Name)
           or else Contains_Dot (Name)
           or else
             (Lowered'Length >= 7
              and then Lowered (Lowered'First .. Lowered'First + 6) = "access ")
         then
            return Name;
         end if;
         return Package_Name & "." & Name;
      end Qualify_Type_Name_Unless_Formal;
   begin
      Result.Name :=
        FT.To_UString
          (Qualify_Type_Name_Unless_Formal (UString_Value (Info.Name)));
      if FT.Lowercase (UString_Value (Result.Kind)) = "array"
        and then not Result.Growable
        and then UString_Value (Info.Name)'Length >= 17
        and then UString_Value (Info.Name) (UString_Value (Info.Name)'First .. UString_Value (Info.Name)'First + 16)
          = "__growable_array_"
      then
         Result.Growable := True;
      end if;
      if Result.Has_Base then
         Result.Base :=
           FT.To_UString
             (Qualify_Type_Name_Unless_Formal (UString_Value (Result.Base)));
      end if;
      if Result.Has_Component_Type then
         Result.Component_Type :=
           FT.To_UString
             (Qualify_Type_Name_Unless_Formal
                (UString_Value (Result.Component_Type)));
      end if;
      if Result.Has_Target then
         Result.Target :=
           FT.To_UString
             (Qualify_Type_Name_Unless_Formal (UString_Value (Result.Target)));
      end if;
      if Result.Has_Discriminant then
         Result.Discriminant_Type :=
           FT.To_UString
             (Qualify_Type_Name_Unless_Formal
                (UString_Value (Result.Discriminant_Type)));
      end if;
      if not Result.Discriminants.Is_Empty then
         for Index in Result.Discriminants.First_Index .. Result.Discriminants.Last_Index loop
            declare
               Item : GM.Discriminant_Descriptor := Result.Discriminants (Index);
            begin
               Item.Type_Name :=
                 FT.To_UString
                   (Qualify_Type_Name_Unless_Formal
                      (UString_Value (Item.Type_Name)));
               if Item.Has_Default then
                  Item.Default_Value :=
                    Qualify_Scalar_Value (Item.Default_Value, Package_Name);
               end if;
               Result.Discriminants.Replace_Element (Index, Item);
            end;
         end loop;
      end if;
      if not Result.Discriminant_Constraints.Is_Empty then
         for Index in Result.Discriminant_Constraints.First_Index .. Result.Discriminant_Constraints.Last_Index loop
            declare
               Item : GM.Discriminant_Constraint := Result.Discriminant_Constraints (Index);
            begin
               Item.Value := Qualify_Scalar_Value (Item.Value, Package_Name);
               Result.Discriminant_Constraints.Replace_Element (Index, Item);
            end;
         end loop;
      end if;
      if not Result.Index_Types.Is_Empty then
         for Index in Result.Index_Types.First_Index .. Result.Index_Types.Last_Index loop
            Result.Index_Types.Replace_Element
              (Index,
               FT.To_UString
                 (Qualify_Type_Name_Unless_Formal
                    (UString_Value (Result.Index_Types (Index)))));
         end loop;
      end if;
      if not Result.Fields.Is_Empty then
         for Index in Result.Fields.First_Index .. Result.Fields.Last_Index loop
            declare
               Item : GM.Type_Field := Result.Fields (Index);
            begin
               Item.Type_Name :=
                 FT.To_UString
                   (Qualify_Type_Name_Unless_Formal
                      (UString_Value (Item.Type_Name)));
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
                 FT.To_UString
                   (Qualify_Type_Name_Unless_Formal
                      (UString_Value (Item.Type_Name)));
               if not Item.Is_Others then
                  Item.Choice := Qualify_Scalar_Value (Item.Choice, Package_Name);
               end if;
               Result.Variant_Fields.Replace_Element (Index, Item);
            end;
         end loop;
      end if;
      if not Result.Sum_Variants.Is_Empty then
         for Variant_Index in Result.Sum_Variants.First_Index .. Result.Sum_Variants.Last_Index loop
            declare
               Variant : GM.Sum_Variant_Descriptor := Result.Sum_Variants (Variant_Index);
            begin
               Variant.Tag_Literal_Name :=
                 FT.To_UString
                   (Qualify_Sum_Tag_Literal_Name
                      (Package_Name,
                       UString_Value (Variant.Tag_Literal_Name)));
               if not Variant.Fields.Is_Empty then
                  for Field_Index in Variant.Fields.First_Index .. Variant.Fields.Last_Index loop
                     declare
                        Field : GM.Sum_Variant_Field_Descriptor := Variant.Fields (Field_Index);
                     begin
                        Field.Type_Name :=
                          FT.To_UString
                            (Qualify_Type_Name_Unless_Formal
                               (UString_Value (Field.Type_Name)));
                        Variant.Fields.Replace_Element (Field_Index, Field);
                     end;
                  end loop;
               end if;
               Result.Sum_Variants.Replace_Element (Variant_Index, Variant);
            end;
         end loop;
      end if;
      if not Result.Interface_Members.Is_Empty then
         for Member_Index in Result.Interface_Members.First_Index .. Result.Interface_Members.Last_Index loop
            declare
               Member : GM.Interface_Member := Result.Interface_Members (Member_Index);
            begin
               if not Member.Params.Is_Empty then
                  for Param_Index in Member.Params.First_Index .. Member.Params.Last_Index loop
                     declare
                        Param : GM.Signature_Param := Member.Params (Param_Index);
                     begin
                        Param.Type_Name :=
                          FT.To_UString
                            (Qualify_Type_Name_Unless_Formal
                               (UString_Value (Param.Type_Name)));
                        Member.Params.Replace_Element (Param_Index, Param);
                     end;
                  end loop;
               end if;
               if Member.Has_Return_Type then
                  Member.Return_Type :=
                    FT.To_UString
                      (Qualify_Type_Name_Unless_Formal
                         (UString_Value (Member.Return_Type)));
               end if;
               Result.Interface_Members.Replace_Element (Member_Index, Member);
            end;
         end loop;
      end if;
      if Result.Has_Generic_Origin then
         Result.Generic_Origin :=
           FT.To_UString
             (Qualify_Name (Package_Name, UString_Value (Result.Generic_Origin)));
      end if;
      if not Result.Generic_Actual_Types.Is_Empty then
         for Index in Result.Generic_Actual_Types.First_Index .. Result.Generic_Actual_Types.Last_Index loop
            if not Is_Local_Generic_Formal_Name
              (UString_Value (Result.Generic_Actual_Types (Index)))
            then
               Result.Generic_Actual_Types.Replace_Element
                 (Index,
                  FT.To_UString
                    (Qualify_Name
                       (Package_Name,
                        UString_Value (Result.Generic_Actual_Types (Index)))));
            end if;
         end loop;
      end if;
      return Result;
   end Qualify_Type_Info;

   function Qualify_Static_Value
     (Value        : CM.Static_Value;
      Package_Name : String) return CM.Static_Value
   is
      Result : CM.Static_Value := Value;
      Enum_Type_Name : constant String := UString_Value (Result.Type_Name);
      Literal_Name   : constant String := UString_Value (Result.Text);
   begin
      if Result.Kind = CM.Static_Value_Enum then
         Result.Type_Name :=
           FT.To_UString
             ((if Enum_Type_Name = ""
                  or else Is_Builtin_Name (Enum_Type_Name)
                  or else Contains_Dot (Enum_Type_Name)
                then Enum_Type_Name
                else Package_Name & "." & Enum_Type_Name));
         Result.Text :=
           FT.To_UString
             ((if Literal_Name'Length >= 14
                   and then Literal_Name
                     (Literal_Name'First .. Literal_Name'First + 13) = "__sum_variant_"
                then Qualify_Sum_Tag_Literal_Name (Package_Name, Literal_Name)
                else Literal_Name));
      end if;
      return Result;
   end Qualify_Static_Value;

   function Qualify_Scalar_Value
     (Value        : GM.Scalar_Value;
      Package_Name : String) return GM.Scalar_Value
   is
      Result : GM.Scalar_Value := Value;
      Enum_Type_Name : constant String := UString_Value (Result.Type_Name);
      Literal_Name   : constant String := UString_Value (Result.Text);
   begin
      if Result.Kind = GM.Scalar_Value_Enum then
         Result.Type_Name :=
           FT.To_UString
             ((if Enum_Type_Name = ""
                  or else Is_Builtin_Name (Enum_Type_Name)
                  or else Contains_Dot (Enum_Type_Name)
                then Enum_Type_Name
                else Package_Name & "." & Enum_Type_Name));
         Result.Text :=
           FT.To_UString
             ((if Literal_Name'Length >= 14
                   and then Literal_Name
                     (Literal_Name'First .. Literal_Name'First + 13) = "__sum_variant_"
                then Qualify_Sum_Tag_Literal_Name (Package_Name, Literal_Name)
                else Literal_Name));
      end if;
      return Result;
   end Qualify_Scalar_Value;

   function Generic_Formal_Type
     (Formal : CM.Generic_Formal) return GM.Type_Descriptor
   is
      Result : GM.Type_Descriptor;
   begin
      Result.Name := Formal.Name;
      Result.Kind := FT.To_UString ("generic_formal");
      if Formal.Has_Constraint then
         Result.Has_Base := True;
         Result.Base := Formal.Constraint_Name;
      end if;
      return Result;
   end Generic_Formal_Type;

   function Generic_Formal_Descriptor
     (Formal : CM.Generic_Formal) return GM.Generic_Formal_Descriptor
   is
      Result : GM.Generic_Formal_Descriptor;
   begin
      Result.Name := Formal.Name;
      Result.Has_Constraint := Formal.Has_Constraint;
      Result.Constraint_Name := Formal.Constraint_Name;
      return Result;
   end Generic_Formal_Descriptor;

   procedure Add_Generic_Formals_To_Env
     (Type_Env : in out Type_Maps.Map;
      Formals  : CM.Generic_Formal_Vectors.Vector) is
   begin
      if not Formals.Is_Empty then
         for Formal of Formals loop
            Put_Type (Type_Env, UString_Value (Formal.Name), Generic_Formal_Type (Formal));
         end loop;
      end if;
   end Add_Generic_Formals_To_Env;

   function Is_Generic_Actual_Type_Allowed
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean
   is
      Base : constant GM.Type_Descriptor := Base_Type (Info, Type_Env);
      Kind : constant String := FT.Lowercase (UString_Value (Base.Kind));
   begin
      return Kind /= "interface"
        and then Kind /= "access"
        and then Kind /= "incomplete"
        and then Kind /= "generic_formal"
        and then not Contains_Channel_Reference_Subcomponent (Base, Type_Env);
   end Is_Generic_Actual_Type_Allowed;

   procedure Validate_Generic_Actuals
     (Formals      : CM.Generic_Formal_Vectors.Vector;
      Actual_Types : FT.UString_Vectors.Vector;
      Functions    : Function_Maps.Map;
      Type_Env     : Type_Maps.Map;
      Path         : String;
      Span         : FT.Source_Span) is
   begin
      if Natural (Formals.Length) /= Natural (Actual_Types.Length) then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path,
               Span    => Span,
               Message =>
                 "generic actual count does not match the declaration"));
      end if;

      if not Formals.Is_Empty then
         for Index in Formals.First_Index .. Formals.Last_Index loop
            declare
               Formal : constant CM.Generic_Formal := Formals (Index);
               Actual : constant GM.Type_Descriptor :=
                 Resolve_Type (UString_Value (Actual_Types (Index)), Type_Env, Path, Span);
            begin
               if not Is_Generic_Actual_Type_Allowed (Actual, Type_Env) then
                  Raise_Diag
                    (CM.Unsupported_Source_Construct
                       (Path    => Path,
                        Span    => Span,
                        Message =>
                          "generic actual types are limited to the admitted concrete value-type subset in PR11.11c"));
               elsif Formal.Has_Constraint then
                  declare
                     Constraint_Type : constant GM.Type_Descriptor :=
                       Resolve_Type (UString_Value (Formal.Constraint_Name), Type_Env, Path, Span);
                  begin
                     if not Is_Interface_Type (Constraint_Type, Type_Env) then
                        Raise_Diag
                          (CM.Source_Frontend_Error
                             (Path    => Path,
                              Span    => Span,
                              Message =>
                                "generic constraint `" & UString_Value (Formal.Constraint_Name)
                                & "` must name an interface"));
                     elsif not Type_Satisfies_Interface (Actual, Constraint_Type, Functions, Type_Env) then
                        Raise_Diag
                          (CM.Source_Frontend_Error
                             (Path    => Path,
                              Span    => Span,
                              Message =>
                                "type `" & UString_Value (Base_Type (Actual, Type_Env).Name)
                                & "` does not satisfy interface `"
                                & UString_Value (Base_Type (Constraint_Type, Type_Env).Name)
                                & "`"));
                     end if;
                  end;
               end if;
            end;
         end loop;
      end if;
   end Validate_Generic_Actuals;

   function Generic_Template_Key
     (Name         : String;
      Actual_Types : FT.UString_Vectors.Vector) return String
   is
      Result : FT.UString := FT.To_UString (Canonical_Name (Name));
   begin
      if not Actual_Types.Is_Empty then
         for Item of Actual_Types loop
            Result := Result & FT.To_UString ("|") & FT.To_UString (Canonical_Name (UString_Value (Item)));
         end loop;
      end if;
      return UString_Value (Result);
   end Generic_Template_Key;

   function Generic_Specialization_Name
     (Prefix       : String;
      Name         : String;
      Actual_Types : FT.UString_Vectors.Vector) return String
   is
      Result : FT.UString :=
        FT.To_UString
          (Prefix & Sanitize_Type_Name_Component (Canonical_Name (Name)));
   begin
      if not Actual_Types.Is_Empty then
         for Item of Actual_Types loop
            Result :=
              Result
              & FT.To_UString ("_")
              & FT.To_UString
                  (Sanitize_Type_Name_Component
                     (Canonical_Name (UString_Value (Item))));
         end loop;
      end if;
      return UString_Value (Result);
   end Generic_Specialization_Name;

   function Substitute_Generic_Type_Info
     (Template     : GM.Type_Descriptor;
      Formals      : GM.Generic_Formal_Descriptor_Vectors.Vector;
      Actual_Types : FT.UString_Vectors.Vector) return GM.Type_Descriptor
   is
      Result : GM.Type_Descriptor := Template;

      function Replace_Name (Name : FT.UString) return FT.UString is
      begin
         if not Formals.Is_Empty then
            for Index in Formals.First_Index .. Formals.Last_Index loop
               if Canonical_Name (UString_Value (Name))
                 = Canonical_Name (UString_Value (Formals (Index).Name))
               then
                  return Actual_Types (Index);
               end if;
            end loop;
         end if;
         return Name;
      end Replace_Name;
   begin
      if Result.Has_Base then
         Result.Base := Replace_Name (Result.Base);
      end if;
      if Result.Has_Target then
         Result.Target := Replace_Name (Result.Target);
      end if;
      if Result.Has_Component_Type then
         Result.Component_Type := Replace_Name (Result.Component_Type);
      end if;
      if Result.Has_Discriminant then
         Result.Discriminant_Type := Replace_Name (Result.Discriminant_Type);
      end if;

      if not Result.Index_Types.Is_Empty then
         for Index in Result.Index_Types.First_Index .. Result.Index_Types.Last_Index loop
            Result.Index_Types.Replace_Element
              (Index,
               Replace_Name (Result.Index_Types (Index)));
         end loop;
      end if;

      if not Result.Fields.Is_Empty then
         for Index in Result.Fields.First_Index .. Result.Fields.Last_Index loop
            declare
               Field : GM.Type_Field := Result.Fields (Index);
            begin
               Field.Type_Name := Replace_Name (Field.Type_Name);
               Result.Fields.Replace_Element (Index, Field);
            end;
         end loop;
      end if;

      if not Result.Interface_Members.Is_Empty then
         for Member_Index in Result.Interface_Members.First_Index .. Result.Interface_Members.Last_Index loop
            declare
               Member : GM.Interface_Member := Result.Interface_Members (Member_Index);
            begin
               if not Member.Params.Is_Empty then
                  for Param_Index in Member.Params.First_Index .. Member.Params.Last_Index loop
                     declare
                        Param : GM.Signature_Param := Member.Params (Param_Index);
                     begin
                        Param.Type_Name := Replace_Name (Param.Type_Name);
                        Member.Params.Replace_Element (Param_Index, Param);
                     end;
                  end loop;
               end if;
               if Member.Has_Return_Type then
                  Member.Return_Type := Replace_Name (Member.Return_Type);
               end if;
               Result.Interface_Members.Replace_Element (Member_Index, Member);
            end;
         end loop;
      end if;

      if not Result.Discriminants.Is_Empty then
         for Index in Result.Discriminants.First_Index .. Result.Discriminants.Last_Index loop
            declare
               Disc : GM.Discriminant_Descriptor := Result.Discriminants (Index);
            begin
               Disc.Type_Name := Replace_Name (Disc.Type_Name);
               Result.Discriminants.Replace_Element (Index, Disc);
            end;
         end loop;
      end if;

      if not Result.Variant_Fields.Is_Empty then
         for Index in Result.Variant_Fields.First_Index .. Result.Variant_Fields.Last_Index loop
            declare
               Field : GM.Variant_Field := Result.Variant_Fields (Index);
            begin
               Field.Type_Name := Replace_Name (Field.Type_Name);
               Result.Variant_Fields.Replace_Element (Index, Field);
            end;
         end loop;
      end if;

      if not Result.Sum_Variants.Is_Empty then
         for Variant_Index in Result.Sum_Variants.First_Index .. Result.Sum_Variants.Last_Index loop
            declare
               Variant : GM.Sum_Variant_Descriptor := Result.Sum_Variants (Variant_Index);
            begin
               if not Variant.Fields.Is_Empty then
                  for Field_Index in Variant.Fields.First_Index .. Variant.Fields.Last_Index loop
                     declare
                        Field : GM.Sum_Variant_Field_Descriptor := Variant.Fields (Field_Index);
                     begin
                        Field.Type_Name := Replace_Name (Field.Type_Name);
                        Variant.Fields.Replace_Element (Field_Index, Field);
                     end;
                  end loop;
               end if;
               Result.Sum_Variants.Replace_Element (Variant_Index, Variant);
            end;
         end loop;
      end if;

      if not Result.Tuple_Element_Types.Is_Empty then
         for Index in Result.Tuple_Element_Types.First_Index .. Result.Tuple_Element_Types.Last_Index loop
            Result.Tuple_Element_Types.Replace_Element
              (Index,
               Replace_Name (Result.Tuple_Element_Types (Index)));
         end loop;
      end if;

      Result.Generic_Formals.Clear;
      return Result;
   end Substitute_Generic_Type_Info;

   function Parse_Imported_Generic_Subprogram
     (Package_Name    : String;
      Qualified_Name  : String;
      Template_Source : String) return CM.Subprogram_Body
   is
      Input : constant Safe_Frontend.Source.Source_File :=
        (Path    => FT.To_UString ("<imported-generic:" & Qualified_Name & ">"),
         Content =>
           FT.To_UString
             ("package safeimport" & Ada.Characters.Latin_1.LF
              & "   " & Template_Source));
      Diagnostics : FD.Diagnostic_Vectors.Vector;
      Tokens      : constant FL.Token_Vectors.Vector := FL.Lex (Input, Diagnostics);
      Parsed      : constant CM.Parse_Result := CP.Parse (Input, Tokens);
   begin
      if FD.Has_Errors (Diagnostics) then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => "<imported-generic:" & Qualified_Name & ">",
               Span    => FT.Null_Span,
               Message =>
                 "failed to import generic template from `" & Package_Name
                 & "`: " & FT.To_String (Diagnostics (Diagnostics.First_Index).Message)));
      elsif not Parsed.Success then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => "<imported-generic:" & Qualified_Name & ">",
               Span    => Parsed.Diagnostic.Span,
               Message =>
                 "failed to import generic template from `" & Package_Name
                 & "`: " & FT.To_String (Parsed.Diagnostic.Message)));
      elsif Natural (Parsed.Unit.Items.Length) /= 1
        or else Parsed.Unit.Items (Parsed.Unit.Items.First_Index).Kind /= CM.Item_Subprogram
      then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => "<imported-generic:" & Qualified_Name & ">",
               Span    => FT.Null_Span,
               Message =>
                 "generic template import from `" & Package_Name
                 & "` did not contain exactly one subprogram body"));
      end if;

      return Parsed.Unit.Items (Parsed.Unit.Items.First_Index).Subp_Data;
   end Parse_Imported_Generic_Subprogram;

   procedure Add_Imported_Package_Local_Aliases
     (Package_Name         : String;
      Imported_Types       : GM.Type_Descriptor_Vectors.Vector;
      Imported_Subprograms : GM.External_Vectors.Vector;
      Imported_Objects     : Type_Maps.Map;
      Imported_Static      : Static_Value_Maps.Map;
      Generic_Types        : in out Generic_Type_Template_Maps.Map;
      Generic_Functions    : in out Generic_Function_Template_Maps.Map;
      Visible_Types        : in out Type_Maps.Map;
      Visible_Functions    : in out Function_Maps.Map;
      Visible_Objects      : in out Type_Maps.Map;
      Visible_Static       : in out Static_Value_Maps.Map)
   is
      function From_Package (Name : String) return Boolean is
      begin
         return Name'Length > Package_Name'Length
           and then Name (Name'First .. Name'First + Package_Name'Length - 1) = Package_Name
           and then Name (Name'First + Package_Name'Length) = '.';
      end From_Package;
   begin
      if Package_Name'Length = 0 then
         return;
      end if;

      if not Imported_Types.Is_Empty then
         for Item of Imported_Types loop
            declare
               Qualified_Name : constant String := UString_Value (Item.Name);
               Short_Name     : constant String := Method_Target_Tail_Name (Qualified_Name);
            begin
               if From_Package (Qualified_Name)
                 and then Short_Name /= Qualified_Name
               then
                  if not Has_Type (Visible_Types, Short_Name) then
                     Put_Type (Visible_Types, Short_Name, Item);
                  end if;
                  if not Item.Generic_Formals.Is_Empty
                    and then Generic_Types.Contains (Canonical_Name (Qualified_Name))
                    and then not Generic_Types.Contains (Canonical_Name (Short_Name))
                  then
                     Generic_Types.Include
                       (Canonical_Name (Short_Name),
                        Generic_Types.Element (Canonical_Name (Qualified_Name)));
                  end if;
               end if;
            end;
         end loop;
      end if;

      if not Imported_Subprograms.Is_Empty then
         for Item of Imported_Subprograms loop
            declare
               Qualified_Name : constant String := UString_Value (Item.Name);
               Short_Name     : constant String := Method_Target_Tail_Name (Qualified_Name);
               Info           : Function_Info;
            begin
               if From_Package (Qualified_Name)
                 and then Short_Name /= Qualified_Name
               then
                  if Item.Generic_Formals.Is_Empty then
                     if not Has_Function (Visible_Functions, Short_Name) then
                        Info.Name := FT.To_UString (Short_Name);
                        Info.Kind := Item.Kind;
                        Info.Span := Item.Span;
                        Info.Has_Return_Type := Item.Has_Return_Type;
                        Info.Return_Is_Access_Def := Item.Return_Is_Access_Def;
                        if Item.Has_Return_Type then
                           Info.Return_Type := Item.Return_Type;
                        end if;
                        if not Item.Params.Is_Empty then
                           for Param of Item.Params loop
                              declare
                                 Symbol : CM.Symbol;
                              begin
                                 Symbol.Name := Param.Name;
                                 Symbol.Kind := Param.Kind;
                                 Symbol.Mode := Param.Mode;
                                 Symbol.Type_Info := Param.Type_Info;
                                 Symbol.Span := Param.Span;
                                 Info.Params.Append (Symbol);
                              end;
                           end loop;
                        end if;
                        Put_Function (Visible_Functions, Short_Name, Info);
                     end if;
                  elsif Generic_Functions.Contains (Canonical_Name (Qualified_Name))
                    and then not Generic_Functions.Contains (Canonical_Name (Short_Name))
                  then
                     Generic_Functions.Include
                       (Canonical_Name (Short_Name),
                        Generic_Functions.Element (Canonical_Name (Qualified_Name)));
                  end if;
               end if;
            end;
         end loop;
      end if;

      for Cursor in Imported_Objects.Iterate loop
         declare
            Qualified_Name : constant String := Type_Maps.Key (Cursor);
            Short_Name     : constant String := Method_Target_Tail_Name (Qualified_Name);
         begin
            if From_Package (Qualified_Name)
              and then Short_Name /= Qualified_Name
              and then not Has_Type (Visible_Objects, Short_Name)
            then
               Put_Type
                 (Visible_Objects,
                  Short_Name,
                  Type_Maps.Element (Cursor));
               if Imported_Static.Contains (Qualified_Name)
                 and then not Visible_Static.Contains (Short_Name)
               then
                  Put_Static_Value
                    (Visible_Static,
                     Short_Name,
                     Imported_Static.Element (Qualified_Name));
               end if;
            end if;
         end;
      end loop;
   end Add_Imported_Package_Local_Aliases;

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
         when CM.Expr_Int | CM.Expr_Real | CM.Expr_String =>
            if UString_Value (Expr.Text)'Length > 0 then
               return UString_Value (Expr.Text);
            end if;
         when CM.Expr_Bool =>
            return (if Expr.Bool_Value then "true" else "false");
         when CM.Expr_Enum_Literal =>
            return UString_Value (Expr.Name);
         when CM.Expr_Ident =>
            return UString_Value (Expr.Name);
         when CM.Expr_Select =>
            return Expr_Text (Expr.Prefix) & "." & UString_Value (Expr.Selector);
         when CM.Expr_Try =>
            return "try " & Expr_Text (Expr.Inner);
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
      elsif Expr.Kind = CM.Expr_Enum_Literal then
         return UString_Value (Expr.Name);
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

   function Exact_Length_Fact_Name (Expr : CM.Expr_Access) return String is
   begin
      if Expr = null then
         return "";
      elsif Expr.Kind in CM.Expr_Ident | CM.Expr_Select then
         return Flatten_Name (Expr);
      elsif Expr.Kind in CM.Expr_Annotated | CM.Expr_Conversion then
         return Exact_Length_Fact_Name (Expr.Inner);
      end if;
      return "";
   end Exact_Length_Fact_Name;

   procedure Remove_Exact_Length_Fact
     (Facts : in out Exact_Length_Maps.Map;
      Name  : String) is
      Key : constant String := Canonical_Name (Name);
   begin
      if Key /= "" and then Facts.Contains (Key) then
         Facts.Delete (Key);
      end if;
   end Remove_Exact_Length_Fact;

   function Try_Direct_Growable_Length_Guard
     (Condition  : CM.Expr_Access;
      Var_Types  : Type_Maps.Map;
      Functions  : Function_Maps.Map;
      Type_Env   : Type_Maps.Map;
      Guard_Name : out FT.UString;
      Length     : out Natural) return Boolean
   is
      function Try_Length_Expr
        (Expr : CM.Expr_Access;
         Name : out FT.UString) return Boolean
      is
         Prefix_Type : GM.Type_Descriptor;
      begin
         Name := FT.To_UString ("");
         if Expr = null
           or else Expr.Kind /= CM.Expr_Select
           or else UString_Value (Expr.Selector) /= "length"
         then
            return False;
         end if;

         Name := FT.To_UString (Exact_Length_Fact_Name (Expr.Prefix));
         if UString_Value (Name) = "" then
            return False;
         end if;

         Prefix_Type := Base_Type (Expr_Type (Expr.Prefix, Var_Types, Functions, Type_Env), Type_Env);
         return FT.Lowercase (UString_Value (Prefix_Type.Kind)) = "array"
           and then Prefix_Type.Growable;
      end Try_Length_Expr;

      function Try_Length_Literal
        (Expr : CM.Expr_Access;
         Value : out Natural) return Boolean
      is
      begin
         Value := 0;
         if Expr = null or else Expr.Kind /= CM.Expr_Int or else Expr.Int_Value < 0 then
            return False;
         end if;
         if Expr.Int_Value > CM.Wide_Integer (Natural'Last) then
            return False;
         end if;
         Value := Natural (Expr.Int_Value);
         return True;
      end Try_Length_Literal;

      Left_Name  : FT.UString := FT.To_UString ("");
      Right_Name : FT.UString := FT.To_UString ("");
   begin
      Guard_Name := FT.To_UString ("");
      Length := 0;

      if Condition = null
        or else Condition.Kind /= CM.Expr_Binary
        or else UString_Value (Condition.Operator) /= "=="
      then
         return False;
      end if;

      if Try_Length_Expr (Condition.Left, Left_Name)
        and then Try_Length_Literal (Condition.Right, Length)
      then
         Guard_Name := Left_Name;
         return True;
      elsif Try_Length_Expr (Condition.Right, Right_Name)
        and then Try_Length_Literal (Condition.Left, Length)
      then
         Guard_Name := Right_Name;
         return True;
      end if;

      return False;
   end Try_Direct_Growable_Length_Guard;

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
         when CM.Expr_Bool =>
            Result.Kind := CM.Static_Value_Boolean;
            Result.Bool_Value := Expr.Bool_Value;
            return True;
         when CM.Expr_Enum_Literal =>
            Result.Kind := CM.Static_Value_Enum;
            Result.Text := Expr.Name;
            Result.Type_Name := Expr.Type_Name;
            return UString_Value (Result.Type_Name) /= "";
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

   function Is_Static_Case_Choice
     (Expr      : CM.Expr_Access;
      Const_Env : Static_Value_Maps.Map) return Boolean
   is
      Value : CM.Static_Value := (others => <>);
   begin
      if Expr = null then
         return False;
      end if;

      case Expr.Kind is
         when CM.Expr_Int | CM.Expr_Bool | CM.Expr_String | CM.Expr_Enum_Literal =>
            return True;
         when CM.Expr_Ident | CM.Expr_Select =>
            return Try_Static_Value (Expr, Const_Env, Value);
         when CM.Expr_Call | CM.Expr_Apply =>
            return Natural (Expr.Args.Length) = 1
              and then Is_Static_Case_Choice (Expr.Args (Expr.Args.First_Index), Const_Env);
         when CM.Expr_Conversion | CM.Expr_Annotated =>
            return Expr.Inner /= null
              and then Is_Static_Case_Choice (Expr.Inner, Const_Env);
         when CM.Expr_Unary =>
            return Expr.Inner /= null
              and then UString_Value (Expr.Operator) in "+" | "-"
              and then Expr.Inner.Kind = CM.Expr_Int;
         when others =>
            return False;
      end case;
   end Is_Static_Case_Choice;

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
         when CM.Static_Value_Enum =>
            Result.Kind := GM.Scalar_Value_Enum;
            Result.Text := Value.Text;
            Result.Type_Name := Value.Type_Name;
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
      elsif Value.Kind = CM.Static_Value_Enum then
         return Is_Enum_Type (Disc_Type, Type_Env)
           and then Equivalent_Type
             (Resolve_Type (UString_Value (Value.Type_Name), Type_Env, "", FT.Null_Span),
              Disc_Type,
              Type_Env);
      elsif Value.Kind = CM.Static_Value_Integer then
         if Is_Binary_Type (Disc_Type, Type_Env) then
            return Value.Int_Value >= 0
              and then (not Disc_Type.Has_Low or else Value.Int_Value >= CM.Wide_Integer (Disc_Type.Low))
              and then (not Disc_Type.Has_High or else Value.Int_Value <= CM.Wide_Integer (Disc_Type.High));
         end if;
         return Is_Integerish (Disc_Type, Type_Env)
           and then (not Disc_Type.Has_Low or else Value.Int_Value >= CM.Wide_Integer (Disc_Type.Low))
           and then (not Disc_Type.Has_High or else Value.Int_Value <= CM.Wide_Integer (Disc_Type.High))
           and then not Is_Boolean_Type (Base, Type_Env)
           and then not Is_String_Type (Base, Type_Env);
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
      Bounded_String_Prefix : constant String := "__bounded_string_";
   begin
      if Has_Type (Type_Env, Name) then
         return Get_Type (Type_Env, Name);
      elsif Has_Type (Synthetic_Helper_Types, Name) then
         return Get_Type (Synthetic_Helper_Types, Name);
      elsif Has_Type (Synthetic_Optional_Types, Name) then
         return Get_Type (Synthetic_Optional_Types, Name);
      elsif Has_Type (Current_Generic_Type_Instantiations, Name) then
         return Get_Type (Current_Generic_Type_Instantiations, Name);
      elsif Name'Length >= Bounded_String_Prefix'Length
        and then
          Name (Name'First .. Name'First + Bounded_String_Prefix'Length - 1) = Bounded_String_Prefix
      then
         declare
            Bound_Text : constant String := Name (Name'First + Bounded_String_Prefix'Length .. Name'Last);
         begin
            if Bound_Text'Length > 0 then
               for Ch of Bound_Text loop
                  if Ch not in '0' .. '9' then
                     raise Constraint_Error;
                  end if;
               end loop;
               return Make_Bounded_String_Type (Natural'Value (Bound_Text));
            end if;
         exception
            when Constraint_Error =>
               null;
         end;
      end if;

      if Is_Removed_Integer_Builtin_Name (Name) then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path,
               Span    => Span,
               Message => Removed_Integer_Builtin_Message (Name)));
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

   function Sanitize_Type_Name_Component (Value : String) return String
     renames FNU.Sanitize_Type_Name_Component;

   function Sum_Tag_Type_Name (Sum_Name : String) return String is
   begin
      return "__sum_tag_" & Sanitize_Type_Name_Component (Canonical_Name (Sum_Name));
   end Sum_Tag_Type_Name;

   function Sum_Tag_Literal_Name
     (Sum_Name     : String;
      Variant_Name : String) return String
   is
   begin
      return
        "__sum_variant_"
        & Sanitize_Type_Name_Component (Canonical_Name (Sum_Name))
        & "_"
        & Sanitize_Type_Name_Component (Canonical_Name (Variant_Name));
   end Sum_Tag_Literal_Name;

   function Has_Sum_Constructor (Name : String) return Boolean is
   begin
      return Current_Sum_Constructors.Contains (Canonical_Name (Name));
   end Has_Sum_Constructor;

   function Get_Sum_Constructor (Name : String) return Sum_Constructor_Info is
   begin
      return Current_Sum_Constructors.Element (Canonical_Name (Name));
   end Get_Sum_Constructor;

   function Sum_Discriminant_Name (Sum_Name : String) return String is
      pragma Unreferenced (Sum_Name);
   begin
      return "__sum_tag";
   end Sum_Discriminant_Name;

   function Sum_Variant_Field_Name
     (Variant_Name : String;
      Field_Name   : String) return String
   is
   begin
      return
        "__sum_field_"
        & Sanitize_Type_Name_Component (Canonical_Name (Variant_Name))
        & "_"
        & Sanitize_Type_Name_Component (Canonical_Name (Field_Name));
   end Sum_Variant_Field_Name;

   function Qualify_Sum_Tag_Literal_Name
     (Package_Name : String;
      Name         : String) return String
   is
   begin
      if Name = "" or else Contains_Dot (Name) then
         return Name;
      end if;
      return Package_Name & "." & Name;
   end Qualify_Sum_Tag_Literal_Name;

   function Is_Lowered_Sum_Record (Info : GM.Type_Descriptor) return Boolean is
      Disc_Name : constant String := UString_Value (Info.Discriminant_Name);
      Disc_Type : constant String := UString_Value (Info.Discriminant_Type);
      Variant_Disc : constant String := UString_Value (Info.Variant_Discriminant_Name);
      Dot : Natural := 0;
   begin
      if FT.Lowercase (UString_Value (Info.Kind)) /= "record"
        or else not Info.Has_Discriminant
        or else Variant_Disc /= "__sum_tag"
        or else Disc_Name /= "__sum_tag"
      then
         return False;
      end if;

      for Index in reverse Disc_Type'Range loop
         if Disc_Type (Index) = '.' then
            Dot := Index;
            exit;
         end if;
      end loop;
      declare
         Tail : constant String :=
           (if Dot /= 0 and then Dot < Disc_Type'Last
            then Disc_Type (Dot + 1 .. Disc_Type'Last)
            else Disc_Type);
      begin
         return Tail'Length >= 10
           and then Tail (Tail'First .. Tail'First + 9) = "__sum_tag_";
      end;
   end Is_Lowered_Sum_Record;

   function Is_Sum_Metadata_Type (Info : GM.Type_Descriptor) return Boolean is
   begin
      return not Info.Sum_Variants.Is_Empty or else Is_Lowered_Sum_Record (Info);
   end Is_Sum_Metadata_Type;

   function Constructor_From_Sum_Variant
     (Sum_Type : GM.Type_Descriptor;
      Variant  : GM.Sum_Variant_Descriptor) return Sum_Constructor_Info
   is
      Constructor : Sum_Constructor_Info;
   begin
      Constructor.Name := Variant.Name;
      Constructor.Sum_Type_Name := Sum_Type.Name;
      Constructor.Tag_Type_Name := Sum_Type.Discriminant_Type;
      Constructor.Tag_Literal_Name := Variant.Tag_Literal_Name;
      if not Variant.Fields.Is_Empty then
         for Field of Variant.Fields loop
            Constructor.Fields.Append
              ((Source_Name => Field.Source_Name,
                Name       => Field.Internal_Name,
                Type_Name  => Field.Type_Name));
         end loop;
      end if;
      return Constructor;
   end Constructor_From_Sum_Variant;

   function Try_Find_Sum_Variant_Constructor
     (Sum_Type     : GM.Type_Descriptor;
      Variant_Name : String;
      Constructor  : out Sum_Constructor_Info) return Boolean
   is
      Key  : constant String := Canonical_Name (Variant_Name);
   begin
      Constructor := (others => <>);
      if Sum_Type.Sum_Variants.Is_Empty then
         return False;
      end if;

      for Variant of Sum_Type.Sum_Variants loop
         if Canonical_Name (UString_Value (Variant.Name)) = Key then
            Constructor := Constructor_From_Sum_Variant (Sum_Type, Variant);
            return True;
         end if;
      end loop;
      return False;
   end Try_Find_Sum_Variant_Constructor;

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
         when CM.Static_Value_Enum =>
            return
              Sanitize_Type_Name_Component
                (UString_Value (Value.Type_Name) & "_" & UString_Value (Value.Text));
         when others =>
            return "value";
      end case;
   end Static_Value_Name_Component;

   function Make_Tuple_Type
     (Element_Types : FT.UString_Vectors.Vector;
      Type_Env      : Type_Maps.Map) return GM.Type_Descriptor
   is
      Result : GM.Type_Descriptor;
   begin
      Result.Name := Tuple_Type_Name (Element_Types);
      Result.Kind := FT.To_UString ("tuple");
      Result.Tuple_Element_Types := Element_Types;
      Result := Reuse_Equivalent_Synthetic_Type (Result, Type_Env);
      Register_Synthetic_Helper_Type (Result);
      return Result;
   end Make_Tuple_Type;

   function Resolve_Type_Spec
     (Spec      : CM.Type_Spec;
      Type_Env  : Type_Maps.Map;
      Const_Env : Static_Value_Maps.Map := Static_Value_Maps.Empty_Map;
      Path      : String;
      Current_Record_Name : String := "";
      Family_By_Name      : String_Index_Maps.Map := String_Index_Maps.Empty_Map;
      Families            : Recursive_Family_Vectors.Vector := Recursive_Family_Vectors.Empty_Vector)
      return GM.Type_Descriptor
   is
      Result : GM.Type_Descriptor;
      Target : GM.Type_Descriptor;
      Base   : GM.Type_Descriptor;
      Element_Types : FT.UString_Vectors.Vector;
   begin
      case Spec.Kind is
         when CM.Type_Spec_Name | CM.Type_Spec_Subtype_Indication =>
            if not Spec.Generic_Args.Is_Empty then
               if Current_Generic_Type_Templates.Contains
                 (Canonical_Name (UString_Value (Spec.Name)))
               then
                  return
                    Instantiate_Generic_Type
                      (UString_Value (Spec.Name),
                       Spec,
                       Type_Env,
                       Const_Env,
                       Path);
               end if;

               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path,
                     Span    => Spec.Span,
                     Message => "explicit generic type arguments require a generic type declaration"));
            elsif Current_Generic_Type_Templates.Contains
              (Canonical_Name (UString_Value (Spec.Name)))
            then
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path,
                     Span    => Spec.Span,
                     Message =>
                       "generic type `" & UString_Value (Spec.Name)
                       & "` requires explicit type arguments in PR11.11c"));
            end if;

            if Spec.Has_Range_Constraint then
               Base := Resolve_Type (UString_Value (Spec.Name), Type_Env, Path, Spec.Span);
               if Is_Enum_Type (Base, Type_Env) then
                  Raise_Diag
                    (CM.Unsupported_Source_Construct
                       (Path    => Path,
                        Span    => Spec.Span,
                        Message => "enum range-constrained subtypes are deferred past PR11.8i"));
               end if;
               if not Is_Integerish (Base, Type_Env)
                 or else Is_Boolean_Type (Base, Type_Env)
               then
                  Raise_Diag
                    (CM.Source_Frontend_Error
                       (Path    => Path,
                        Span    => Spec.Span,
                        Message => "range constraints require an integer type"));
               end if;

               Result.Name :=
                 FT.To_UString
                   ("__constraint_"
                    & Sanitize_Type_Name_Component (UString_Value (Base.Name))
                    & "_"
                    & Sanitize_Type_Name_Component (Expr_Text (Spec.Range_Low))
                    & "_"
                    & Sanitize_Type_Name_Component (Expr_Text (Spec.Range_High)));
               Result.Kind := FT.To_UString ("subtype");
               Result.Has_Base := True;
               Result.Base := Base.Name;
               Result.Has_Low := True;
               Result.Low :=
                 Long_Long_Integer
                   (Literal_Value
                      (Spec.Range_Low,
                       Const_Env,
                       Path,
                       "range bounds must be integer literals or constant references"));
               Result.Has_High := True;
               Result.High :=
                 Long_Long_Integer
                   (Literal_Value
                      (Spec.Range_High,
                       Const_Env,
                       Path,
                       "range bounds must be integer literals or constant references"));
               if Result.Low > Result.High then
                  Raise_Diag
                    (CM.Source_Frontend_Error
                       (Path    => Path,
                        Span    => Spec.Span,
                        Message => "range constraint lower bound exceeds upper bound"));
               elsif Base.Has_Low and then Result.Low < Base.Low then
                  Raise_Diag
                    (CM.Source_Frontend_Error
                       (Path    => Path,
                        Span    => Spec.Range_Low.Span,
                        Message => "range constraint lower bound is outside the base type range"));
               elsif Base.Has_High and then Result.High > Base.High then
                  Raise_Diag
                    (CM.Source_Frontend_Error
                       (Path    => Path,
                        Span    => Spec.Range_High.Span,
                        Message => "range constraint upper bound is outside the base type range"));
               end if;
               return Result;
            elsif not Spec.Constraints.Is_Empty
              and then FT.Lowercase (UString_Value (Spec.Name)) = "string"
            then
               if Natural (Spec.Constraints.Length) /= 1
                 or else Spec.Constraints (Spec.Constraints.First_Index).Is_Named
               then
                  Raise_Diag
                    (CM.Source_Frontend_Error
                       (Path    => Path,
                        Span    => Spec.Span,
                        Message => "`string (N)` requires exactly one positional capacity expression"));
               end if;
               declare
                  Bound : constant CM.Wide_Integer :=
                    Literal_Value
                      (Spec.Constraints (Spec.Constraints.First_Index).Value,
                       Const_Env,
                       Path,
                       "string bounds must be integer literals or constant references");
               begin
                  if Bound < 1 then
                     Raise_Diag
                       (CM.Source_Frontend_Error
                          (Path    => Path,
                           Span    => Spec.Span,
                           Message => "string bounds must be at least 1"));
                  end if;
                  declare
                     Result : constant GM.Type_Descriptor :=
                       Make_Bounded_String_Type (Natural (Bound));
                  begin
                     return Result;
                  end;
               end;
            elsif not Spec.Constraints.Is_Empty then
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
            declare
               Resolved : GM.Type_Descriptor :=
                 Resolve_Type (UString_Value (Spec.Name), Type_Env, Path, Spec.Span);
            begin
               if Spec.Not_Null then
                  declare
                     Base_Info : constant GM.Type_Descriptor := Base_Type (Resolved, Type_Env);
                     Base_Kind : constant String :=
                       FT.Lowercase (UString_Value (Base_Info.Kind));
                     Is_Current_Record_Family_Member : constant Boolean :=
                       Base_Kind = "incomplete"
                       and then Current_Record_Name /= ""
                       and then In_Same_Admitted_Record_Family
                         (Current_Record_Name,
                          UString_Value (Base_Info.Name),
                          Family_By_Name,
                          Families);
                  begin
                     if Base_Kind = "incomplete" and then not Is_Current_Record_Family_Member then
                        Raise_Diag
                          (CM.Source_Frontend_Error
                             (Path    => Path,
                              Span    => Spec.Span,
                              Message => "`not null` applies only to inferred reference types in PR11.8e"));
                     elsif Base_Kind /= "access" and then Base_Kind /= "incomplete" then
                        Raise_Diag
                          (CM.Source_Frontend_Error
                             (Path    => Path,
                              Span    => Spec.Span,
                              Message => "`not null` applies only to inferred reference types in PR11.8e"));
                     end if;
                  end;
                  Resolved.Not_Null := True;
               end if;
               return Resolved;
            end;
         when CM.Type_Spec_Binary =>
            declare
               Width : constant CM.Wide_Integer :=
                 Literal_Value
                   (Spec.Binary_Width_Expr,
                    Const_Env,
                    Path,
                    "binary width must be one of 8, 16, 32, or 64");
            begin
               case Width is
                  when 8 =>
                     return BT.Binary_Type (8);
                  when 16 =>
                     return BT.Binary_Type (16);
                  when 32 =>
                     return BT.Binary_Type (32);
                  when 64 =>
                     return BT.Binary_Type (64);
                  when others =>
                     Raise_Diag
                       (CM.Source_Frontend_Error
                          (Path    => Path,
                           Span    => Spec.Span,
                           Message => "binary width must be one of 8, 16, 32, or 64"));
                     return Default_Integer;
               end case;
            end;
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
                    Resolve_Type_Spec
                      (Item.all,
                       Type_Env,
                       Const_Env,
                       Path,
                       Current_Record_Name,
                       Family_By_Name,
                       Families);
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
               return Make_Tuple_Type (Element_Types, Type_Env);
         when CM.Type_Spec_List | CM.Type_Spec_Growable_Array =>
            if Spec.Element_Type = null then
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path,
                     Span    => Spec.Span,
                     Message =>
                       (if Spec.Kind = CM.Type_Spec_List
                        then "list type is missing an element type"
                        else "growable array type is missing an element type")));
            end if;
            declare
               Element_Type : constant GM.Type_Descriptor :=
                 Resolve_Type_Spec
                   (Spec.Element_Type.all,
                    Type_Env,
                    Const_Env,
                    Path,
                    Current_Record_Name,
                    Family_By_Name,
                    Families);
            begin
               if Spec.Kind = CM.Type_Spec_List
                 and then not Is_Container_Element_Type_Allowed
                   (Element_Type, Type_Env)
               then
                  Raise_Diag
                    (CM.Unsupported_Source_Construct
                       (Path    => Path,
                        Span    => Spec.Element_Type.Span,
                        Message =>
                          "`list of T` is limited to the admitted value-type subset in PR11.10b"));
               end if;
               return Make_Growable_Array_Type (Element_Type, Type_Env);
            end;
         when CM.Type_Spec_Map =>
            if Spec.Key_Type = null or else Spec.Value_Type = null then
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path,
                     Span    => Spec.Span,
                     Message => "map type is missing a key or value type"));
            end if;
            declare
               Key_Type : constant GM.Type_Descriptor :=
                 Resolve_Type_Spec
                   (Spec.Key_Type.all,
                    Type_Env,
                    Const_Env,
                    Path,
                    Current_Record_Name,
                    Family_By_Name,
                    Families);
               Value_Type : constant GM.Type_Descriptor :=
                 Resolve_Type_Spec
                   (Spec.Value_Type.all,
                    Type_Env,
                    Const_Env,
                    Path,
                    Current_Record_Name,
                    Family_By_Name,
                    Families);
            begin
               if not Is_Map_Key_Type_Allowed (Key_Type, Type_Env) then
                  Raise_Diag
                    (CM.Unsupported_Source_Construct
                       (Path    => Path,
                        Span    => Spec.Key_Type.Span,
                        Message =>
                          "`map of (K, V)` keys are limited to the admitted discrete/string subset in PR11.10c"));
               elsif not Is_Container_Element_Type_Allowed (Value_Type, Type_Env) then
                  Raise_Diag
                    (CM.Unsupported_Source_Construct
                       (Path    => Path,
                        Span    => Spec.Value_Type.Span,
                        Message =>
                          "`map of (K, V)` values are limited to the admitted value-type subset in PR11.10c"));
               end if;

               Element_Types.Clear;
               Element_Types.Append (Key_Type.Name);
               Element_Types.Append (Value_Type.Name);
               return Make_Growable_Array_Type
                 (Make_Tuple_Type (Element_Types, Type_Env), Type_Env);
            end;
         when CM.Type_Spec_Optional =>
            if Spec.Element_Type = null then
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path,
                     Span    => Spec.Span,
                     Message => "optional type is missing an element type"));
            end if;
            declare
               Element_Type : constant GM.Type_Descriptor :=
                 Resolve_Type_Spec
                   (Spec.Element_Type.all,
                    Type_Env,
                    Const_Env,
                    Path,
                    Current_Record_Name,
                    Family_By_Name,
                    Families);
            begin
               if not Is_Container_Element_Type_Allowed (Element_Type, Type_Env) then
                  Raise_Diag
                    (CM.Unsupported_Source_Construct
                       (Path    => Path,
                        Span    => Spec.Element_Type.Span,
                        Message =>
                          "`optional T` is limited to the admitted value-type subset in PR11.10a"));
               end if;
               return Make_Optional_Type (Element_Type, Type_Env);
            end;
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
            if UString_Value (Expr.Type_Name)'Length > 0 then
               return Resolve_Type (UString_Value (Expr.Type_Name), Type_Env, "", FT.Null_Span);
            end if;
            return Default_String;
         when CM.Expr_Null =>
            Result.Name := FT.To_UString ("null");
            Result.Kind := FT.To_UString ("null");
            return Result;
         when CM.Expr_None =>
            if UString_Value (Expr.Type_Name)'Length > 0 then
               return Resolve_Type (UString_Value (Expr.Type_Name), Type_Env, "", FT.Null_Span);
            end if;
            Result.Name := FT.To_UString ("none");
            Result.Kind := FT.To_UString ("none");
            return Result;
         when CM.Expr_Array_Literal =>
            if UString_Value (Expr.Type_Name)'Length > 0 then
               return Resolve_Type (UString_Value (Expr.Type_Name), Type_Env, "", FT.Null_Span);
            elsif not Expr.Elements.Is_Empty then
               return
                 Make_Growable_Array_Type
                   (Expr_Type
                      (Expr.Elements (Expr.Elements.First_Index),
                       Var_Types,
                       Functions,
                       Type_Env),
                    Type_Env);
            end if;
            return Make_Growable_Array_Type (Default_Integer, Type_Env);
         when CM.Expr_Tuple =>
            if UString_Value (Expr.Type_Name)'Length > 0 then
               return Resolve_Type (UString_Value (Expr.Type_Name), Type_Env, "", FT.Null_Span);
            end if;
            declare
               Elements : FT.UString_Vectors.Vector;
            begin
               for Item of Expr.Elements loop
                  Elements.Append (Expr_Type (Item, Var_Types, Functions, Type_Env).Name);
               end loop;
               return Make_Tuple_Type (Elements, Type_Env);
            end;
         when CM.Expr_Aggregate =>
            if UString_Value (Expr.Type_Name)'Length > 0 then
               return Resolve_Type (UString_Value (Expr.Type_Name), Type_Env, "", FT.Null_Span);
            end if;
         when CM.Expr_Real =>
            if UString_Value (Expr.Type_Name)'Length > 0 then
               return Resolve_Type (UString_Value (Expr.Type_Name), Type_Env, "", FT.Null_Span);
            end if;
            return Default_Float;
         when CM.Expr_Enum_Literal =>
            if UString_Value (Expr.Type_Name)'Length > 0 then
               return Resolve_Type (UString_Value (Expr.Type_Name), Type_Env, "", FT.Null_Span);
            end if;
         when CM.Expr_Ident =>
            if UString_Value (Expr.Type_Name)'Length > 0
              and then Has_Resolvable_Type_Name (UString_Value (Expr.Type_Name), Type_Env)
            then
               return Resolve_Type (UString_Value (Expr.Type_Name), Type_Env, "", FT.Null_Span);
            end if;
            Name := Expr.Name;
            if Has_Sum_Constructor (UString_Value (Name)) then
               return
                 Resolve_Type
                   (UString_Value (Get_Sum_Constructor (UString_Value (Name)).Sum_Type_Name),
                    Type_Env,
                    "",
                    FT.Null_Span);
            elsif Has_Type (Var_Types, UString_Value (Name)) then
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
            if UString_Value (Expr.Type_Name)'Length > 0
              and then Has_Resolvable_Type_Name (UString_Value (Expr.Type_Name), Type_Env)
            then
               return Resolve_Type (UString_Value (Expr.Type_Name), Type_Env, "", FT.Null_Span);
            end if;
            Name := FT.To_UString (Flatten_Name (Expr));
            if Has_Sum_Constructor (UString_Value (Name)) then
               return
                 Resolve_Type
                   (UString_Value (Get_Sum_Constructor (UString_Value (Name)).Sum_Type_Name),
                    Type_Env,
                    "",
                    FT.Null_Span);
            elsif Has_Type (Var_Types, UString_Value (Name)) then
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
            elsif UString_Value (Expr.Selector) = "access" then
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
            elsif UString_Value (Expr.Selector) in "first" | "last" then
               if Expr.Prefix /= null then
                  declare
                     Prefix_Name : constant String := Flatten_Name (Expr.Prefix);
                  begin
                     if Prefix_Name /= ""
                       and then Has_Type (Type_Env, Prefix_Name)
                     then
                        Prefix_Type := Get_Type (Type_Env, Prefix_Name);
                        if Is_Enum_Type (Prefix_Type, Type_Env) then
                           return Prefix_Type;
                        end if;
                     end if;
                  end;
               end if;
               return Default_Integer;
            elsif UString_Value (Expr.Selector) = "length" then
               return Default_Integer;
            end if;

            Prefix_Type := Expr_Type (Expr.Prefix, Var_Types, Functions, Type_Env);
            return Field_Type (Prefix_Type, UString_Value (Expr.Selector), Type_Env);
         when CM.Expr_Resolved_Index =>
            if UString_Value (Expr.Type_Name)'Length > 0 then
               return Resolve_Type (UString_Value (Expr.Type_Name), Type_Env, "", FT.Null_Span);
            end if;
            Prefix_Type := Expr_Type (Expr.Prefix, Var_Types, Functions, Type_Env);
            if Is_String_Type (Prefix_Type, Type_Env) then
               return Default_String;
            end if;
            if Prefix_Type.Has_Component_Type then
               if Natural (Expr.Args.Length) = 2
                 and then
                   (Base_Type (Prefix_Type, Type_Env).Growable
                    or else Natural (Base_Type (Prefix_Type, Type_Env).Index_Types.Length) = 1)
               then
                  return Make_Growable_Array_Type
                    (Resolve_Type
                       (UString_Value (Prefix_Type.Component_Type),
                        Type_Env,
                        "",
                        FT.Null_Span),
                     Type_Env);
               end if;
               return Resolve_Type
                 (UString_Value (Prefix_Type.Component_Type),
                  Type_Env,
                  "",
                  FT.Null_Span);
            end if;
         when CM.Expr_Conversion =>
            return Resolve_Target_Type (Expr.Target, Type_Env);
         when CM.Expr_Annotated =>
            if Expr.Target /= null then
               return Resolve_Target_Type (Expr.Target, Type_Env);
            end if;
            if Expr.Inner /= null then
               return Expr_Type (Expr.Inner, Var_Types, Functions, Type_Env);
            end if;
         when CM.Expr_Call =>
            if UString_Value (Expr.Type_Name)'Length > 0
              and then Has_Resolvable_Type_Name (UString_Value (Expr.Type_Name), Type_Env)
            then
               return Resolve_Type (UString_Value (Expr.Type_Name), Type_Env, "", FT.Null_Span);
            end if;
            Name := FT.To_UString (Flatten_Name (Expr.Callee));
            if Has_Sum_Constructor (UString_Value (Name)) then
               return
                 Resolve_Type
                   (UString_Value (Get_Sum_Constructor (UString_Value (Name)).Sum_Type_Name),
                    Type_Env,
                    "",
                    FT.Null_Span);
            elsif Has_Function (Functions, UString_Value (Name)) then
               declare
                  Info : constant Function_Info := Get_Function (Functions, UString_Value (Name));
               begin
                  if Info.Has_Return_Type then
                     return Info.Return_Type;
                  end if;
               end;
            elsif Is_Pop_Last_Builtin_Call (Expr, Var_Types, Functions, Type_Env)
              and then Natural (Expr.Args.Length) = 1
            then
               declare
                  List_Type : constant GM.Type_Descriptor :=
                    Expr_Type
                      (Expr.Args (Expr.Args.First_Index),
                       Var_Types,
                       Functions,
                       Type_Env);
               begin
                  if Is_Growable_Array_Type (List_Type, Type_Env) then
                     return
                       Make_Optional_Type
                         (Growable_Array_Element_Type (List_Type, Type_Env),
                          Type_Env);
                  end if;
               end;
            elsif Is_Contains_Builtin_Call (Expr, Var_Types, Functions, Type_Env)
              and then Natural (Expr.Args.Length) = 2
            then
               return BT.Boolean_Type;
            elsif Is_Get_Builtin_Call (Expr, Var_Types, Functions, Type_Env)
              and then Natural (Expr.Args.Length) = 2
            then
               declare
                  Map_Type   : constant GM.Type_Descriptor :=
                    Expr_Type
                      (Expr.Args (Expr.Args.First_Index),
                       Var_Types,
                       Functions,
                       Type_Env);
                  Key_Type   : GM.Type_Descriptor;
                  Value_Type : GM.Type_Descriptor;
               begin
                  if Try_Map_Key_Value_Types (Map_Type, Type_Env, Key_Type, Value_Type) then
                     return Make_Optional_Type (Value_Type, Type_Env);
                  end if;
               end;
            elsif Is_Remove_Builtin_Call (Expr, Var_Types, Functions, Type_Env)
              and then Natural (Expr.Args.Length) = 2
            then
               declare
                  Map_Type   : constant GM.Type_Descriptor :=
                    Expr_Type
                      (Expr.Args (Expr.Args.First_Index),
                       Var_Types,
                       Functions,
                       Type_Env);
                  Key_Type   : GM.Type_Descriptor;
                  Value_Type : GM.Type_Descriptor;
               begin
                  if Try_Map_Key_Value_Types (Map_Type, Type_Env, Key_Type, Value_Type) then
                     return Make_Optional_Type (Value_Type, Type_Env);
                  end if;
               end;
            elsif UString_Value (Name) = "long_float.copy_sign" then
               return Resolve_Type ("long_float", Type_Env, "", FT.Null_Span);
            elsif Has_Type (Var_Types, UString_Value (Name)) then
               return Get_Type (Var_Types, UString_Value (Name));
            elsif UString_Value (Expr.Type_Name)'Length > 0
              and then Has_Resolvable_Type_Name (UString_Value (Expr.Type_Name), Type_Env)
            then
               return Resolve_Type (UString_Value (Expr.Type_Name), Type_Env, "", FT.Null_Span);
            end if;
         when CM.Expr_Some =>
            declare
               Payload_Type : constant GM.Type_Descriptor :=
                 Expr_Type (Expr.Inner, Var_Types, Functions, Type_Env);
            begin
               if Is_Optional_Element_Type_Allowed (Payload_Type, Type_Env) then
                  return Make_Optional_Type (Payload_Type, Type_Env);
               end if;
               Raise_Diag
                 (CM.Unsupported_Source_Construct
                    (Path    => "",
                     Span    => Expr.Span,
                     Message =>
                       "`optional T` is limited to the admitted value-type subset in PR11.10a"));
               return Default_Integer;
            end;
         when CM.Expr_Try =>
            declare
               Success_Type : GM.Type_Descriptor;
            begin
               if Try_Result_Carrier_Success_Type
                 (Expr_Type (Expr.Inner, Var_Types, Functions, Type_Env),
                  Type_Env,
                  Success_Type)
               then
                  return Success_Type;
               end if;
            end;
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
               declare
                  Inner_Type : constant GM.Type_Descriptor :=
                    Expr_Type (Expr.Inner, Var_Types, Functions, Type_Env);
               begin
                  if Is_Binary_Type (Inner_Type, Type_Env) then
                     return Inner_Type;
                  end if;
               end;
               return Default_Boolean;
            end if;
            return Expr_Type (Expr.Inner, Var_Types, Functions, Type_Env);
         when CM.Expr_Binary =>
            if UString_Value (Expr.Operator) in "==" | "!=" | "<" | "<=" | ">" | ">=" | "and then" | "or else" then
               return Default_Boolean;
            end if;
            declare
               Left_Type  : constant GM.Type_Descriptor := Expr_Type (Expr.Left, Var_Types, Functions, Type_Env);
               Right_Type : constant GM.Type_Descriptor := Expr_Type (Expr.Right, Var_Types, Functions, Type_Env);
            begin
               if UString_Value (Expr.Operator) = "&" then
                  if Is_String_Type (Left_Type, Type_Env)
                    and then Is_String_Type (Right_Type, Type_Env)
                  then
                     return Default_String;
                  elsif FT.Lowercase (UString_Value (Left_Type.Kind)) = "array"
                    and then FT.Lowercase (UString_Value (Right_Type.Kind)) = "array"
                    and then Left_Type.Has_Component_Type
                  then
                     return Make_Growable_Array_Type
                       (Resolve_Type (UString_Value (Left_Type.Component_Type), Type_Env, "", FT.Null_Span),
                        Type_Env);
                  end if;
               end if;
               if UString_Value (Expr.Operator) in "and" | "or" | "xor" then
                  if Is_Boolean_Type (Left_Type, Type_Env)
                    and then Is_Boolean_Type (Right_Type, Type_Env)
                  then
                     return Default_Boolean;
                  elsif Is_Binary_Type (Left_Type, Type_Env)
                    and then Is_Binary_Type (Right_Type, Type_Env)
                  then
                     return Left_Type;
                  end if;
               elsif UString_Value (Expr.Operator) in "<<" | ">>" then
                  return Left_Type;
               elsif Is_Binary_Type (Left_Type, Type_Env)
                 and then Is_Binary_Type (Right_Type, Type_Env)
               then
                  return Left_Type;
               end if;
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

   function Resolve_Target_Type
     (Target   : CM.Expr_Access;
      Type_Env : Type_Maps.Map) return GM.Type_Descriptor
   is
   begin
      if Target = null then
         return Default_Integer;
      elsif Target.Kind = CM.Expr_Subtype_Indication
        and then Target.Subtype_Spec /= null
      then
         return Resolve_Type_Spec (Target.Subtype_Spec.all, Type_Env, Path => "");
      end if;

      return Resolve_Type (Flatten_Name (Target), Type_Env, "", FT.Null_Span);
   end Resolve_Target_Type;

   function Set_Type
     (Expr : CM.Expr_Access;
      Info : GM.Type_Descriptor) return CM.Expr_Access is
   begin
      if Expr /= null then
         Expr.Type_Name := Info.Name;
      end if;
      return Expr;
   end Set_Type;

   function Is_Print_Call (Expr : CM.Expr_Access) return Boolean is
   begin
      return
        Expr /= null
        and then Expr.Kind = CM.Expr_Call
        and then FT.Lowercase (Flatten_Name (Expr.Callee)) = "print";
   end Is_Print_Call;

   function Is_Print_Designator (Expr : CM.Expr_Access) return Boolean is
   begin
      return
        Expr /= null
        and then
          ((Expr.Kind = CM.Expr_Call
            and then FT.Lowercase (Flatten_Name (Expr.Callee)) = "print")
           or else
           (Expr.Kind in CM.Expr_Ident | CM.Expr_Select
            and then FT.Lowercase (Flatten_Name (Expr)) = "print"));
   end Is_Print_Designator;

   procedure Validate_Print_Call_Context
     (Expr             : CM.Expr_Access;
      Var_Types        : Type_Maps.Map;
      Functions        : Function_Maps.Map;
      Type_Env         : Type_Maps.Map;
      Path             : String;
      Allow_Root_Print : Boolean := False)
   is
      procedure Recurse
        (Item             : CM.Expr_Access;
         Allow_Print_Here : Boolean := False) is
      begin
         Validate_Print_Call_Context
           (Item,
            Var_Types,
            Functions,
            Type_Env,
            Path,
            Allow_Root_Print => Allow_Print_Here);
      end Recurse;
   begin
      if Expr = null then
         return;
      end if;

      if Is_Print_Designator (Expr) and then not Allow_Root_Print then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path,
               Span    => (if Expr.Has_Call_Span then Expr.Call_Span else Expr.Span),
               Message => "`print` is a statement, not an expression"));
      end if;

      case Expr.Kind is
         when CM.Expr_Select =>
            Recurse (Expr.Prefix);
         when CM.Expr_Resolved_Index =>
            Recurse (Expr.Prefix);
            for Item of Expr.Args loop
               Recurse (Item);
            end loop;
         when CM.Expr_Conversion =>
            Recurse (Expr.Inner);
         when CM.Expr_Call =>
            if not Is_Print_Call (Expr) then
               Recurse (Expr.Callee);
            end if;
            for Item of Expr.Args loop
               Recurse (Item);
            end loop;
         when CM.Expr_Allocator =>
            Recurse (Expr.Value);
         when CM.Expr_Try =>
            Recurse (Expr.Inner);
         when CM.Expr_Some =>
            Recurse (Expr.Inner);
         when CM.Expr_Aggregate =>
            for Item of Expr.Fields loop
               Recurse (Item.Expr);
            end loop;
         when CM.Expr_Array_Literal =>
            for Item of Expr.Elements loop
               Recurse (Item);
            end loop;
         when CM.Expr_Tuple =>
            for Item of Expr.Elements loop
               Recurse (Item);
            end loop;
         when CM.Expr_Annotated =>
            Recurse (Expr.Inner);
         when CM.Expr_Unary =>
            Recurse (Expr.Inner);
         when CM.Expr_Binary =>
            Recurse (Expr.Left);
            Recurse (Expr.Right);
         when others =>
            null;
      end case;
   end Validate_Print_Call_Context;

   procedure Validate_Print_Procedure_Call
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Path      : String)
   is
      Argument_Type : GM.Type_Descriptor;
      Base_Argument : GM.Type_Descriptor;
      Base_Kind     : FT.UString;
      Base_Name     : FT.UString;
   begin
      if not Is_Print_Call (Expr) then
         return;
      end if;

      if Natural (Expr.Args.Length) /= 1 then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path,
               Span    => (if Expr.Has_Call_Span then Expr.Call_Span else Expr.Span),
               Message => "`print` expects exactly one argument"));
      end if;

      Argument_Type :=
        Expr_Type
          (Expr.Args (Expr.Args.First_Index),
           Var_Types,
           Functions,
           Type_Env);
      Base_Argument := Base_Type (Argument_Type, Type_Env);
      Base_Kind := FT.To_UString (FT.Lowercase (UString_Value (Base_Argument.Kind)));
      Base_Name := FT.To_UString (FT.Lowercase (UString_Value (Base_Argument.Name)));
      if Base_Kind = FT.To_UString ("integer")
        or else Base_Name = FT.To_UString ("integer")
        or else Base_Kind = FT.To_UString ("string")
        or else Base_Name = FT.To_UString ("string")
        or else Base_Kind = FT.To_UString ("boolean")
        or else Base_Name = FT.To_UString ("boolean")
        or else Base_Kind = FT.To_UString ("enum")
      then
         return;
      end if;

      Raise_Diag
        (CM.Source_Frontend_Error
           (Path    => Path,
            Span    => Expr.Args (Expr.Args.First_Index).Span,
            Message => "`print` supports only integer, string, boolean, or enum arguments"));
   end Validate_Print_Procedure_Call;

   function Method_Target_Tail_Name (Name : String) return String is
      Last_Dot : Natural := 0;
   begin
      for Index in reverse Name'Range loop
         if Name (Index) = '.' then
            Last_Dot := Index;
            exit;
         end if;
      end loop;
      if Last_Dot = 0 then
         return Name;
      end if;
      return Name (Last_Dot + 1 .. Name'Last);
   end Method_Target_Tail_Name;

   function Builtin_Method_Kind_For_Canonical_Name
     (Name : String) return Builtin_Method_Kind
   is
   begin
      pragma Assert (Name = Canonical_Name (Name));

      if Name = "append" then
         return Builtin_Append;
      elsif Name = "pop_last" then
         return Builtin_Pop_Last;
      elsif Name = "contains" then
         return Builtin_Contains;
      elsif Name = "get" then
         return Builtin_Get;
      elsif Name = "remove" then
         return Builtin_Remove;
      elsif Name = "set" then
         return Builtin_Set;
      else
         return Builtin_None;
      end if;
   end Builtin_Method_Kind_For_Canonical_Name;

   function Builtin_Method_Kind_For_Name (Name : String) return Builtin_Method_Kind is
      --  This classifier accepts any case and lowercases internally. Callers
      --  that need exact-case builtin matching must enforce that separately.
   begin
      return Builtin_Method_Kind_For_Canonical_Name (Canonical_Name (Name));
   end Builtin_Method_Kind_For_Name;

   function Builtin_Method_Name (Kind : Builtin_Method_Kind) return String is
   begin
      case Kind is
         when Builtin_Append =>
            return "append";
         when Builtin_Pop_Last =>
            return "pop_last";
         when Builtin_Contains =>
            return "contains";
         when Builtin_Get =>
            return "get";
         when Builtin_Remove =>
            return "remove";
         when Builtin_Set =>
            return "set";
         when Builtin_None =>
            return "";
      end case;
   end Builtin_Method_Name;

   function Has_Synthetic_Tail_Compatibility
     (Source   : GM.Type_Descriptor;
      Target   : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean
   is
      Source_Base : constant GM.Type_Descriptor := Base_Type (Source, Type_Env);
      Target_Base : constant GM.Type_Descriptor := Base_Type (Target, Type_Env);
      Source_Tail : constant String :=
        Method_Target_Tail_Name (UString_Value (Source_Base.Name));
      Target_Tail : constant String :=
        Method_Target_Tail_Name (UString_Value (Target_Base.Name));
   begin
      return Source_Tail'Length > 1
        and then Target_Tail'Length > 1
        and then Source_Tail (Source_Tail'First .. Source_Tail'First + 1) = "__"
        and then Target_Tail (Target_Tail'First .. Target_Tail'First + 1) = "__"
        and then FT.Lowercase (UString_Value (Source_Base.Kind)) =
          FT.Lowercase (UString_Value (Target_Base.Kind))
        and then Source_Tail = Target_Tail;
   end Has_Synthetic_Tail_Compatibility;

   function Method_Source_To_Target_Compatible
     (Source   : GM.Type_Descriptor;
      Target   : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean is
   begin
      return Compatible_Source_To_Target_Type (Source, Target, Type_Env)
        or else Has_Synthetic_Tail_Compatibility (Source, Target, Type_Env);
   end Method_Source_To_Target_Compatible;

   function Interface_Member_Compatible_With_Function
     (Member         : GM.Interface_Member;
      Concrete_Type  : GM.Type_Descriptor;
      Info           : Function_Info;
      Type_Env       : Type_Maps.Map) return Boolean;

   function Builtin_Method_Satisfies_Interface_Member
     (Name          : String;
      Concrete_Type : GM.Type_Descriptor;
      Member        : GM.Interface_Member;
      Functions     : Function_Maps.Map;
      Type_Env      : Type_Maps.Map) return Boolean;

   function Interface_Member_Compatible_With_Function
     (Member         : GM.Interface_Member;
      Concrete_Type  : GM.Type_Descriptor;
      Info           : Function_Info;
      Type_Env       : Type_Maps.Map) return Boolean
   is
   begin
      if Natural (Member.Params.Length) /= Natural (Info.Params.Length)
        or else Member.Params.Is_Empty
      then
         return False;
      end if;

      declare
         Receiver_Param : constant GM.Signature_Param := Member.Params (Member.Params.First_Index);
         Target_Param   : constant CM.Symbol := Info.Params (Info.Params.First_Index);
      begin
         if UString_Value (Receiver_Param.Mode) /= UString_Value (Target_Param.Mode) then
            return False;
         elsif not Method_Source_To_Target_Compatible
           (Concrete_Type,
            Target_Param.Type_Info,
            Type_Env)
         then
            return False;
         end if;
      end;

      if Natural (Member.Params.Length) > 1 then
         for Offset in 1 .. Natural (Member.Params.Length) - 1 loop
            declare
               Member_Param : constant GM.Signature_Param :=
                 Member.Params (Member.Params.First_Index + Offset);
               Target_Param : constant CM.Symbol :=
                 Info.Params (Info.Params.First_Index + Offset);
               Member_Type  : constant GM.Type_Descriptor :=
                 Resolve_Type
                   (UString_Value (Member_Param.Type_Name),
                    Type_Env,
                    "",
                    FT.Null_Span);
            begin
               if UString_Value (Member_Param.Mode) /= UString_Value (Target_Param.Mode)
                 or else not Method_Source_To_Target_Compatible
                   (Member_Type,
                    Target_Param.Type_Info,
                    Type_Env)
               then
                  return False;
               end if;
            end;
         end loop;
      end if;

      if Member.Has_Return_Type /= Info.Has_Return_Type then
         return False;
      elsif Member.Has_Return_Type then
         declare
            Member_Return : constant GM.Type_Descriptor :=
              Resolve_Type
                (UString_Value (Member.Return_Type),
                 Type_Env,
                 "",
                 FT.Null_Span);
         begin
            return Method_Source_To_Target_Compatible
              (Info.Return_Type,
               Member_Return,
               Type_Env);
         end;
      end if;

      return True;
   end Interface_Member_Compatible_With_Function;

   function Builtin_Method_Satisfies_Interface_Member
     (Name          : String;
      Concrete_Type : GM.Type_Descriptor;
      Member        : GM.Interface_Member;
      Functions     : Function_Maps.Map;
      Type_Env      : Type_Maps.Map) return Boolean
   is
      Element_Type : GM.Type_Descriptor;
      Key_Type     : GM.Type_Descriptor;
      Value_Type   : GM.Type_Descriptor;
   begin
      if Has_Function (Functions, Name) or else Has_Type (Type_Env, Name) then
         return False;
      elsif Name /= Canonical_Name (Name) then
         return False;
      end if;

      declare
         Builtin_Kind : constant Builtin_Method_Kind :=
           Builtin_Method_Kind_For_Canonical_Name (Name);
      begin
         case Builtin_Kind is
            when Builtin_None =>
               return False;
            when Builtin_Append =>
               if Natural (Member.Params.Length) /= 2
                 or else Member.Has_Return_Type
                 or else UString_Value (Member.Params (Member.Params.First_Index).Mode) /= "mut"
                 or else not Is_Growable_Array_Type (Concrete_Type, Type_Env)
               then
                  return False;
               end if;
               Element_Type := Growable_Array_Element_Type (Concrete_Type, Type_Env);
               return Method_Source_To_Target_Compatible
                 (Resolve_Type
                    (UString_Value (Member.Params (Member.Params.First_Index + 1).Type_Name),
                     Type_Env,
                     "",
                     FT.Null_Span),
                  Element_Type,
                  Type_Env);
            when Builtin_Pop_Last =>
               if Natural (Member.Params.Length) /= 1
                 or else UString_Value (Member.Params (Member.Params.First_Index).Mode) /= "mut"
                 or else not Is_Growable_Array_Type (Concrete_Type, Type_Env)
                 or else not Member.Has_Return_Type
               then
                  return False;
               end if;
               Element_Type := Growable_Array_Element_Type (Concrete_Type, Type_Env);
               return Method_Source_To_Target_Compatible
                 (Make_Optional_Type (Element_Type, Type_Env),
                  Resolve_Type (UString_Value (Member.Return_Type), Type_Env, "", FT.Null_Span),
                  Type_Env);
            when Builtin_Contains | Builtin_Get | Builtin_Remove | Builtin_Set =>
               if not Try_Map_Key_Value_Types (Concrete_Type, Type_Env, Key_Type, Value_Type) then
                  return False;
               end if;
               case Builtin_Kind is
                  when Builtin_Contains =>
                     return Natural (Member.Params.Length) = 2
                       and then Member.Has_Return_Type
                       and then Method_Source_To_Target_Compatible
                         (Resolve_Type
                            (UString_Value (Member.Params (Member.Params.First_Index + 1).Type_Name),
                             Type_Env,
                             "",
                             FT.Null_Span),
                          Key_Type,
                          Type_Env)
                       and then Method_Source_To_Target_Compatible
                         (BT.Boolean_Type,
                          Resolve_Type (UString_Value (Member.Return_Type), Type_Env, "", FT.Null_Span),
                          Type_Env);
                  when Builtin_Get =>
                     return Natural (Member.Params.Length) = 2
                       and then Member.Has_Return_Type
                       and then Method_Source_To_Target_Compatible
                         (Resolve_Type
                            (UString_Value (Member.Params (Member.Params.First_Index + 1).Type_Name),
                             Type_Env,
                             "",
                             FT.Null_Span),
                          Key_Type,
                          Type_Env)
                       and then Method_Source_To_Target_Compatible
                         (Make_Optional_Type (Value_Type, Type_Env),
                          Resolve_Type (UString_Value (Member.Return_Type), Type_Env, "", FT.Null_Span),
                          Type_Env);
                  when Builtin_Remove =>
                     return Natural (Member.Params.Length) = 2
                       and then UString_Value (Member.Params (Member.Params.First_Index).Mode) = "mut"
                       and then Member.Has_Return_Type
                       and then Method_Source_To_Target_Compatible
                         (Resolve_Type
                            (UString_Value (Member.Params (Member.Params.First_Index + 1).Type_Name),
                             Type_Env,
                             "",
                             FT.Null_Span),
                          Key_Type,
                          Type_Env)
                       and then Method_Source_To_Target_Compatible
                         (Make_Optional_Type (Value_Type, Type_Env),
                          Resolve_Type (UString_Value (Member.Return_Type), Type_Env, "", FT.Null_Span),
                          Type_Env);
                  when Builtin_Set =>
                     return Natural (Member.Params.Length) = 3
                       and then UString_Value (Member.Params (Member.Params.First_Index).Mode) = "mut"
                       and then not Member.Has_Return_Type
                       and then Method_Source_To_Target_Compatible
                         (Resolve_Type
                            (UString_Value (Member.Params (Member.Params.First_Index + 1).Type_Name),
                             Type_Env,
                             "",
                             FT.Null_Span),
                          Key_Type,
                          Type_Env)
                       and then Method_Source_To_Target_Compatible
                         (Resolve_Type
                            (UString_Value (Member.Params (Member.Params.First_Index + 2).Type_Name),
                             Type_Env,
                             "",
                             FT.Null_Span),
                          Value_Type,
                          Type_Env);
                  when Builtin_None | Builtin_Append | Builtin_Pop_Last =>
                     raise Program_Error
                       with "Builtin_Method_Satisfies_Interface_Member: "
                            & "unreachable inner arm";
               end case;
         end case;
      end;
   end Builtin_Method_Satisfies_Interface_Member;

   function Type_Satisfies_Interface
     (Concrete_Type  : GM.Type_Descriptor;
      Interface_Type : GM.Type_Descriptor;
      Functions      : Function_Maps.Map;
      Type_Env       : Type_Maps.Map) return Boolean
   is
      Interface_Info : constant GM.Type_Descriptor := Base_Type (Interface_Type, Type_Env);
      Match_Count    : Natural;
   begin
      if not Is_Interface_Type (Interface_Info, Type_Env) then
         return False;
      end if;

      for Member of Interface_Info.Interface_Members loop
         Match_Count := 0;
         for Cursor in Functions.Iterate loop
            declare
               Candidate_Name : constant String := Function_Maps.Key (Cursor);
               Tail_Name      : constant String := Method_Target_Tail_Name (Candidate_Name);
            begin
               if Tail_Name = UString_Value (Member.Name)
                 and then Interface_Member_Compatible_With_Function
                   (Member,
                    Concrete_Type,
                    Function_Maps.Element (Cursor),
                    Type_Env)
               then
                  Match_Count := Match_Count + 1;
               end if;
            end;
         end loop;

         if Builtin_Method_Satisfies_Interface_Member
           (UString_Value (Member.Name),
            Concrete_Type,
            Member,
            Functions,
            Type_Env)
         then
            Match_Count := Match_Count + 1;
         end if;

         if Match_Count /= 1 then
            return False;
         end if;
      end loop;

      return True;
   end Type_Satisfies_Interface;

   function Name_Expr_From_String
     (Name : String;
      Span : FT.Source_Span) return CM.Expr_Access
   is
      Start  : Positive := Name'First;
      Result : CM.Expr_Access := null;
   begin
      if Name'Length = 0 then
         return null;
      end if;

      for Index in Name'Range loop
         if Name (Index) = '.' then
            declare
               Part : constant String := Name (Start .. Index - 1);
               Node : constant CM.Expr_Access := new CM.Expr_Node;
            begin
               if Result = null then
                  Node.Kind := CM.Expr_Ident;
                  Node.Name := FT.To_UString (Part);
               else
                  Node.Kind := CM.Expr_Select;
                  Node.Prefix := Result;
                  Node.Selector := FT.To_UString (Part);
               end if;
               Node.Span := Span;
               Result := Node;
            end;
            Start := Index + 1;
         end if;
      end loop;

      declare
         Part : constant String := Name (Start .. Name'Last);
         Node : constant CM.Expr_Access := new CM.Expr_Node;
      begin
         if Result = null then
            Node.Kind := CM.Expr_Ident;
            Node.Name := FT.To_UString (Part);
         else
            Node.Kind := CM.Expr_Select;
            Node.Prefix := Result;
            Node.Selector := FT.To_UString (Part);
         end if;
         Node.Span := Span;
         return Node;
      end;
   end Name_Expr_From_String;

   function Is_Method_Builtin_Name (Name : String) return Boolean is
   begin
      --  Callers must pass a pre-canonicalized builtin name here; keep the
      --  guard explicit so future call sites do not silently widen the helper
      --  contract.
      return Name = Canonical_Name (Name)
        and then Builtin_Method_Kind_For_Canonical_Name (Name) /= Builtin_None;
   end Is_Method_Builtin_Name;

   function Function_Method_Call_Compatible
     (Info         : Function_Info;
      Receiver_Arg : CM.Expr_Access;
      Extra_Args   : CM.Expr_Access_Vectors.Vector;
      Var_Types    : Type_Maps.Map;
      Functions    : Function_Maps.Map;
      Type_Env     : Type_Maps.Map;
      Const_Env    : Static_Value_Maps.Map) return Boolean
   is
      Receiver_Type : constant GM.Type_Descriptor :=
        Expr_Type (Receiver_Arg, Var_Types, Functions, Type_Env);
   begin
      if Natural (Info.Params.Length) /= Natural (Extra_Args.Length) + 1 then
         return False;
      end if;

      if UString_Value (Info.Params (Info.Params.First_Index).Mode) = "mut"
        and then not Is_Assignable_Target (Receiver_Arg)
      then
         return False;
      end if;

      if Is_Interface_Type (Info.Params (Info.Params.First_Index).Type_Info, Type_Env) then
         if not Type_Satisfies_Interface
           (Receiver_Type,
            Info.Params (Info.Params.First_Index).Type_Info,
            Functions,
            Type_Env)
         then
            return False;
         end if;
      elsif not Compatible_Source_Expr_To_Target_Type
        (Receiver_Arg,
         Receiver_Type,
         Info.Params (Info.Params.First_Index).Type_Info,
         Var_Types,
         Functions,
         Type_Env,
         Const_Env,
         Exact_Length_Maps.Empty_Map)
        and then not Method_Source_To_Target_Compatible
          (Receiver_Type,
           Info.Params (Info.Params.First_Index).Type_Info,
           Type_Env)
      then
         return False;
      end if;

      if not Extra_Args.Is_Empty then
         for Offset in 0 .. Natural (Extra_Args.Length) - 1 loop
            declare
               Param_Index : constant Positive := Info.Params.First_Index + 1 + Offset;
               Param       : constant CM.Symbol := Info.Params (Param_Index);
               Arg         : CM.Expr_Access := Extra_Args (Extra_Args.First_Index + Offset);
            begin
               if UString_Value (Param.Mode) = "mut"
                 and then not Is_Assignable_Target (Arg)
               then
                  return False;
               end if;

               Arg :=
                 Contextualize_Expr_To_Target_Type
                   (Arg,
                    Param.Type_Info,
                    Var_Types,
                    Functions,
                    Type_Env,
                    "");
               if Is_Interface_Type (Param.Type_Info, Type_Env) then
                  if not Type_Satisfies_Interface
                    (Expr_Type (Arg, Var_Types, Functions, Type_Env),
                     Param.Type_Info,
                     Functions,
                     Type_Env)
                  then
                     return False;
                  end if;
               elsif not Compatible_Source_Expr_To_Target_Type
                 (Arg,
                  Expr_Type (Arg, Var_Types, Functions, Type_Env),
                  Param.Type_Info,
                  Var_Types,
                  Functions,
                  Type_Env,
                  Const_Env,
                  Exact_Length_Maps.Empty_Map)
                 and then not Method_Source_To_Target_Compatible
                   (Expr_Type (Arg, Var_Types, Functions, Type_Env),
                    Param.Type_Info,
                    Type_Env)
               then
                  return False;
               end if;
            end;
         end loop;
      end if;

      return True;
   end Function_Method_Call_Compatible;

   function Builtin_Method_Call_Compatible
     (Name         : String;
      Receiver_Arg : CM.Expr_Access;
      Extra_Args   : CM.Expr_Access_Vectors.Vector;
      Var_Types    : Type_Maps.Map;
      Functions    : Function_Maps.Map;
      Type_Env     : Type_Maps.Map;
      Const_Env    : Static_Value_Maps.Map) return Boolean
   is
      Receiver_Type : constant GM.Type_Descriptor :=
        Expr_Type (Receiver_Arg, Var_Types, Functions, Type_Env);
      Shared_Receiver : Shared_Object_Ref;
      Element_Type  : GM.Type_Descriptor;
      Key_Type      : GM.Type_Descriptor;
      Value_Type    : GM.Type_Descriptor;
      Arg           : CM.Expr_Access;
      Builtin_Kind  : constant Builtin_Method_Kind :=
        Builtin_Method_Kind_For_Name (Name);
   begin
      case Builtin_Kind is
         when Builtin_Append =>
            if Natural (Extra_Args.Length) /= 1
              or else
                (not Is_Assignable_Target (Receiver_Arg)
                 and then not Try_Shared_Root_Expr (Receiver_Arg, Shared_Receiver))
              or else not Is_Growable_Array_Type (Receiver_Type, Type_Env)
            then
               return False;
            end if;
            Element_Type := Growable_Array_Element_Type (Receiver_Type, Type_Env);
            if not Is_Container_Element_Type_Allowed (Element_Type, Type_Env) then
               return False;
            end if;
            Arg :=
              Contextualize_Expr_To_Target_Type
                (Extra_Args (Extra_Args.First_Index),
                 Element_Type,
                 Var_Types,
                 Functions,
                 Type_Env,
                 "");
            return
              Compatible_Source_Expr_To_Target_Type
                (Arg,
                 Expr_Type (Arg, Var_Types, Functions, Type_Env),
                 Element_Type,
                 Var_Types,
                 Functions,
                 Type_Env,
                 Const_Env,
                 Exact_Length_Maps.Empty_Map);
         when Builtin_Pop_Last =>
            if Natural (Extra_Args.Length) /= 0
              or else
                (not Is_Assignable_Target (Receiver_Arg)
                 and then not Try_Shared_Root_Expr (Receiver_Arg, Shared_Receiver))
              or else not Is_Growable_Array_Type (Receiver_Type, Type_Env)
            then
               return False;
            end if;
            Element_Type := Growable_Array_Element_Type (Receiver_Type, Type_Env);
            return Is_Container_Element_Type_Allowed (Element_Type, Type_Env);
         when Builtin_Contains | Builtin_Get | Builtin_Remove =>
            if Natural (Extra_Args.Length) /= 1
              or else not Try_Map_Key_Value_Types (Receiver_Type, Type_Env, Key_Type, Value_Type)
              or else not Is_Map_Key_Type_Allowed (Key_Type, Type_Env)
              or else not Is_Container_Element_Type_Allowed (Value_Type, Type_Env)
              or else
                (Builtin_Kind = Builtin_Remove
                 and then not Is_Assignable_Target (Receiver_Arg)
                 and then not Try_Shared_Root_Expr (Receiver_Arg, Shared_Receiver))
            then
               return False;
            end if;
            Arg :=
              Contextualize_Expr_To_Target_Type
                (Extra_Args (Extra_Args.First_Index),
                 Key_Type,
                 Var_Types,
                 Functions,
                 Type_Env,
                 "");
            return
              Compatible_Source_Expr_To_Target_Type
                (Arg,
                 Expr_Type (Arg, Var_Types, Functions, Type_Env),
                 Key_Type,
                 Var_Types,
                 Functions,
                 Type_Env,
                 Const_Env,
                 Exact_Length_Maps.Empty_Map);
         when Builtin_Set =>
            if Natural (Extra_Args.Length) /= 2
              or else
                (not Is_Assignable_Target (Receiver_Arg)
                 and then not Try_Shared_Root_Expr (Receiver_Arg, Shared_Receiver))
              or else not Try_Map_Key_Value_Types (Receiver_Type, Type_Env, Key_Type, Value_Type)
              or else not Is_Map_Key_Type_Allowed (Key_Type, Type_Env)
              or else not Is_Container_Element_Type_Allowed (Value_Type, Type_Env)
            then
               return False;
            end if;
            Arg :=
              Contextualize_Expr_To_Target_Type
                (Extra_Args (Extra_Args.First_Index),
                 Key_Type,
                 Var_Types,
                 Functions,
                 Type_Env,
                 "");
            if not Compatible_Source_Expr_To_Target_Type
              (Arg,
               Expr_Type (Arg, Var_Types, Functions, Type_Env),
               Key_Type,
               Var_Types,
               Functions,
               Type_Env,
               Const_Env,
               Exact_Length_Maps.Empty_Map)
            then
               return False;
            end if;
            Arg :=
              Contextualize_Expr_To_Target_Type
                (Extra_Args (Extra_Args.First_Index + 1),
                 Value_Type,
                 Var_Types,
                 Functions,
                 Type_Env,
                 "");
            return
              Compatible_Source_Expr_To_Target_Type
                (Arg,
                 Expr_Type (Arg, Var_Types, Functions, Type_Env),
                 Value_Type,
                 Var_Types,
                 Functions,
                 Type_Env,
                 Const_Env,
                 Exact_Length_Maps.Empty_Map);
         when Builtin_None =>
            return False;
      end case;
   end Builtin_Method_Call_Compatible;

   function Rewrite_Method_Apply
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Const_Env : Static_Value_Maps.Map) return CM.Expr_Access
   is
      Receiver_Arg : CM.Expr_Access := null;
      Method_Name  : constant String :=
        (if Expr = null
              or else Expr.Callee = null
              or else Expr.Callee.Kind /= CM.Expr_Select
         then ""
         else FT.Lowercase (UString_Value (Expr.Callee.Selector)));
      Match_Count   : Natural := 0;
      Match_Names   : String_Vectors.Vector;
      Selected_Name : FT.UString := FT.To_UString ("");
      Builtin_Visible : constant Boolean :=
        Is_Method_Builtin_Name (Method_Name)
        and then not Has_Function (Functions, Method_Name)
        and then not Has_Type (Var_Types, Method_Name)
        and then not Has_Type (Type_Env, Method_Name);
      Result : CM.Expr_Access;
   begin
      if Method_Name = "" then
         return null;
      end if;

      Receiver_Arg := Expr.Callee.Prefix;

      if Has_Function (Functions, Method_Name)
        and then Function_Method_Call_Compatible
          (Get_Function (Functions, Method_Name),
           Receiver_Arg,
           Expr.Args,
           Var_Types,
           Functions,
           Type_Env,
           Const_Env)
      then
         Match_Count := Match_Count + 1;
         Append_Unique_String (Match_Names, Method_Name);
         Selected_Name := FT.To_UString (Method_Name);
      end if;

      for Cursor in Functions.Iterate loop
         declare
            Candidate_Name : constant String := Function_Maps.Key (Cursor);
         begin
            if Candidate_Name /= Method_Name
              and then Method_Target_Tail_Name (Candidate_Name) = Method_Name
              and then Function_Method_Call_Compatible
                (Function_Maps.Element (Cursor),
                 Receiver_Arg,
                 Expr.Args,
                 Var_Types,
                 Functions,
                 Type_Env,
                 Const_Env)
            then
               Match_Count := Match_Count + 1;
               Append_Unique_String (Match_Names, Candidate_Name);
               if UString_Value (Selected_Name)'Length = 0 then
                  Selected_Name := FT.To_UString (Candidate_Name);
               end if;
            end if;
         end;
      end loop;

      for Cursor in Current_Generic_Function_Templates.Iterate loop
         declare
            Candidate_Name : constant String :=
              Generic_Function_Template_Maps.Key (Cursor);
            Template : constant Generic_Function_Template_Info :=
              Generic_Function_Template_Maps.Element (Cursor);
         begin
            if (Candidate_Name = Method_Name
                 or else Method_Target_Tail_Name (Candidate_Name) = Method_Name)
              and then Function_Method_Call_Compatible
                (Template.Info,
                 Receiver_Arg,
                 Expr.Args,
                 Var_Types,
                 Functions,
                 Type_Env,
                 Const_Env)
            then
               Match_Count := Match_Count + 1;
               Append_Unique_String (Match_Names, Candidate_Name);
               if UString_Value (Selected_Name)'Length = 0 then
                  Selected_Name := FT.To_UString (Candidate_Name);
               end if;
            end if;
         end;
      end loop;

      if Builtin_Visible
        and then Builtin_Method_Call_Compatible
          (Method_Name,
           Receiver_Arg,
           Expr.Args,
           Var_Types,
           Functions,
           Type_Env,
           Const_Env)
      then
         Match_Count := Match_Count + 1;
         Append_Unique_String (Match_Names, "builtin " & Method_Name);
         if UString_Value (Selected_Name)'Length = 0 then
            Selected_Name := FT.To_UString (Method_Name);
         end if;
      end if;

      if Match_Count = 0 then
         return null;
      elsif Match_Count > 1 then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => "",
               Span    => Expr.Callee.Span,
               Message =>
                 "ambiguous method call `"
                 & Method_Name
                 & "`; compatible candidates: "
                 & Join_String_Vector (Match_Names)));
      end if;

      Result := new CM.Expr_Node'(Expr.all);
      Result.Kind := CM.Expr_Call;
      Result.Callee := Name_Expr_From_String (UString_Value (Selected_Name), Expr.Callee.Span);
      Result.Callee.Generic_Args := Expr.Callee.Generic_Args;
      Result.Args.Clear;
      Result.Args.Append (Receiver_Arg);
      for Arg of Expr.Args loop
         Result.Args.Append (Arg);
      end loop;
      return Result;
   end Rewrite_Method_Apply;

   function Resolve_Apply
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Const_Env : Static_Value_Maps.Map;
      Path      : String := "") return CM.Expr_Access
   is
   begin
      if Expr = null or else Expr.Kind /= CM.Expr_Apply then
         return Expr;
      end if;

      declare
         Result      : constant CM.Expr_Access := new CM.Expr_Node'(Expr.all);
         Callee_Name : FT.UString := FT.To_UString ("");
         Prefix_Type : GM.Type_Descriptor;
      begin
         if Expr.Callee /= null and then Expr.Callee.Kind = CM.Expr_Ident then
            Callee_Name := Expr.Callee.Name;
            if not Expr.Callee.Generic_Args.Is_Empty
              and then Current_Generic_Function_Templates.Contains
                (Canonical_Name (UString_Value (Callee_Name)))
            then
               Result.Kind := CM.Expr_Call;
               Result.Callee := Expr.Callee;
               Result.Args := Expr.Args;
            elsif Expr.Callee.Generic_Args.Is_Empty
              and then Current_Generic_Function_Templates.Contains
                (Canonical_Name (UString_Value (Callee_Name)))
            then
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path,
                     Span    => Expr.Callee.Span,
                     Message =>
                       "generic function `" & UString_Value (Callee_Name)
                       & "` requires explicit type arguments in PR11.11c"));
            elsif Expr.Callee.Generic_Args.Is_Empty
              and then Has_Sum_Constructor (UString_Value (Callee_Name))
            then
               Result.Kind := CM.Expr_Call;
               Result.Callee := Expr.Callee;
               Result.Args := Expr.Args;
            elsif Has_Type (Var_Types, UString_Value (Callee_Name))
              and then
                (UString_Value
                   (Get_Type (Var_Types, UString_Value (Callee_Name)).Kind) = "array"
                 or else Is_String_Type
                   (Get_Type (Var_Types, UString_Value (Callee_Name)), Type_Env))
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
                  in "integer" | "subtype" | "record" | "float" | "binary"
              and then Natural (Expr.Args.Length) = 1
            then
               Result.Kind := CM.Expr_Conversion;
               Result.Target := Expr.Callee;
               Result.Inner := Expr.Args (Expr.Args.First_Index);
            elsif UString_Value (Callee_Name) in "integer" | "float" | "long_float"
              and then Natural (Expr.Args.Length) = 1
            then
               Result.Kind := CM.Expr_Conversion;
               Result.Target := Expr.Callee;
               Result.Inner := Expr.Args (Expr.Args.First_Index);
            elsif Has_Type (Type_Env, UString_Value (Callee_Name))
              and then Is_Binary_Type (Get_Type (Type_Env, UString_Value (Callee_Name)), Type_Env)
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
            if Expr.Callee /= null
              and then Expr.Callee.Kind = CM.Expr_Select
            then
               Prefix_Type := Expr_Type (Expr.Callee.Prefix, Var_Types, Functions, Type_Env);
               if Is_Sum_Type (Prefix_Type, Type_Env) then
                  Raise_Diag
                    (CM.Unsupported_Source_Construct
                       (Path    => Path,
                        Span    => Expr.Callee.Span,
                        Message =>
                          "sum variant inspection and payload access are deferred to PR11.13b `match`"));
               end if;
            end if;
            if Expr.Callee /= null
              and then Expr.Callee.Kind = CM.Expr_Select
              and then
                ((not Expr.Callee.Generic_Args.Is_Empty
                  and then Current_Generic_Function_Templates.Contains
                    (Canonical_Name (Flatten_Name (Expr.Callee))))
                 or else Has_Function (Functions, Flatten_Name (Expr.Callee)))
            then
               Result.Kind := CM.Expr_Call;
               Result.Callee := Expr.Callee;
               Result.Args := Expr.Args;
            else
               if Expr.Callee /= null
                 and then Expr.Callee.Kind = CM.Expr_Select
                 and then Expr.Callee.Generic_Args.Is_Empty
                 and then Current_Generic_Function_Templates.Contains
                   (Canonical_Name (Flatten_Name (Expr.Callee)))
               then
                  Raise_Diag
                    (CM.Source_Frontend_Error
                       (Path    => Path,
                        Span    => Expr.Callee.Span,
                        Message =>
                          "generic function `" & Flatten_Name (Expr.Callee)
                          & "` requires explicit type arguments in PR11.11c"));
               end if;
               declare
                  Rewritten : constant CM.Expr_Access :=
                    Rewrite_Method_Apply (Expr, Var_Types, Functions, Type_Env, Const_Env);
               begin
                  if Rewritten /= null then
                     return Rewritten;
                  end if;
               end;
               Prefix_Type := Expr_Type (Expr.Callee, Var_Types, Functions, Type_Env);
               if UString_Value (Prefix_Type.Kind) = "array"
                 or else Is_String_Type (Prefix_Type, Type_Env)
               then
                  Result.Kind := CM.Expr_Resolved_Index;
                  Result.Prefix := Expr.Callee;
                  Result.Args := Expr.Args;
               else
                  Result.Kind := CM.Expr_Call;
                  Result.Callee := Expr.Callee;
                  Result.Args := Expr.Args;
               end if;
            end if;
         end if;
         return Result;
      end;
   end Resolve_Apply;

   function Rewrite_Static_Enum_Literal
     (Expr      : CM.Expr_Access;
      Const_Env : Static_Value_Maps.Map) return CM.Expr_Access
   is
      Value  : CM.Static_Value := (others => <>);
      Result : CM.Expr_Access;
   begin
      if Expr = null
        or else Expr.Kind not in CM.Expr_Ident | CM.Expr_Select
        or else not Try_Static_Value (Expr, Const_Env, Value)
        or else Value.Kind /= CM.Static_Value_Enum
      then
         return null;
      end if;

      Result := new CM.Expr_Node'(Expr.all);
      Result.Kind := CM.Expr_Enum_Literal;
      Result.Name := Value.Text;
      Result.Type_Name := Value.Type_Name;
      Result.Selector := FT.To_UString ("");
      Result.Operator := FT.To_UString ("");
      Result.Prefix := null;
      Result.Callee := null;
      Result.Inner := null;
      Result.Left := null;
      Result.Right := null;
      Result.Value := null;
      Result.Target := null;
      return Result;
   end Rewrite_Static_Enum_Literal;

   function Normalize_Expr
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Const_Env : Static_Value_Maps.Map;
      Path      : String := "") return CM.Expr_Access
   is
      Result   : CM.Expr_Access;
      Field    : CM.Aggregate_Field;
      Enum_Expr : CM.Expr_Access;

      function Shared_Container_Snapshot_Message return String is
      begin
         return
           "live shared container operations are limited to `.length`, `append`,"
           & " `pop_last`, `contains`, `get`, `set`, and `remove` in PR11.12d;"
           & " snapshot the shared value first for indexing, iteration,"
           & " slicing, or other method calls";
      end Shared_Container_Snapshot_Message;

      function Sum_Inspection_Message return String is
      begin
         return
           "sum variant inspection and payload access are deferred to PR11.13b `match`";
      end Sum_Inspection_Message;

      function Is_Admitted_Shared_Container_Method_Name (Name : String) return Boolean is
      begin
         return Name in "append" | "pop_last" | "contains" | "get" | "set" | "remove";
      end Is_Admitted_Shared_Container_Method_Name;

      function Rewrite_Shared_Container_Expr_Call
        (Call_Expr : CM.Expr_Access) return CM.Expr_Access
      is
         Shared       : Shared_Object_Ref;
         Root_Type    : GM.Type_Descriptor;
         Result_Expr  : CM.Expr_Access := null;
         Element_Type : GM.Type_Descriptor;
         Key_Type     : GM.Type_Descriptor;
         Value_Type   : GM.Type_Descriptor;
         Key_Expr     : CM.Expr_Access := null;
         Builtin_Kind : constant Builtin_Method_Kind :=
           Builtin_Method_Kind_For_Call (Call_Expr, Var_Types, Functions, Type_Env);
         Builtin_Name : constant String := Builtin_Method_Name (Builtin_Kind);
      begin
         if Builtin_Kind not in
           Builtin_Pop_Last | Builtin_Contains | Builtin_Get | Builtin_Remove
           or else Call_Expr = null
           or else Natural (Call_Expr.Args.Length) = 0
           or else not Try_Shared_Root_Expr
             (Call_Expr.Args (Call_Expr.Args.First_Index),
              Shared)
         then
            return null;
         end if;

         Root_Type := Shared.Type_Info;
         if not Is_Shared_Container_Root_Type (Root_Type, Type_Env) then
            return null;
         end if;

         if Builtin_Kind = Builtin_Pop_Last then
            if Natural (Call_Expr.Args.Length) /= 1
              or else not Is_Growable_Array_Type (Root_Type, Type_Env)
              or else Try_Map_Key_Value_Types (Root_Type, Type_Env, Key_Type, Value_Type)
            then
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path,
                     Span    => (if Call_Expr.Has_Call_Span then Call_Expr.Call_Span else Call_Expr.Span),
                     Message => "`pop_last` expects a shared `list of T` or growable `array of T` root"));
            end if;

            Element_Type := Growable_Array_Element_Type (Root_Type, Type_Env);
            Result_Expr :=
              Shared_Call_Expr
                (Shared,
                 Shared_Pop_Last_Name,
                 Call_Expr.Span,
                 UString_Value (Make_Optional_Type (Element_Type, Type_Env).Name));
            return Result_Expr;
         end if;

         if Natural (Call_Expr.Args.Length) /= 2 then
            Raise_Diag
              (CM.Source_Frontend_Error
                 (Path    => Path,
                  Span    => (if Call_Expr.Has_Call_Span then Call_Expr.Call_Span else Call_Expr.Span),
                  Message => "`" & Builtin_Name & "(m, key)` expects exactly two arguments"));
         elsif not Try_Map_Key_Value_Types (Root_Type, Type_Env, Key_Type, Value_Type) then
            Raise_Diag
              (CM.Source_Frontend_Error
                 (Path    => Path,
                  Span    => Call_Expr.Args (Call_Expr.Args.First_Index).Span,
                  Message => "`" & Builtin_Name & "` expects a shared `map of (K, V)` root"));
         elsif not Is_Map_Key_Type_Allowed (Key_Type, Type_Env) then
            Raise_Diag
              (CM.Unsupported_Source_Construct
                 (Path    => Path,
                  Span    => Call_Expr.Args (Call_Expr.Args.First_Index).Span,
                  Message =>
                    "`map of (K, V)` keys are limited to the admitted discrete/string subset in PR11.10c"));
         elsif not Is_Container_Element_Type_Allowed (Value_Type, Type_Env) then
            Raise_Diag
              (CM.Unsupported_Source_Construct
                 (Path    => Path,
                  Span    => Call_Expr.Args (Call_Expr.Args.First_Index).Span,
                  Message =>
                    "`map of (K, V)` values are limited to the admitted value-type subset in PR11.10c"));
         end if;

         Key_Expr :=
           Normalize_Expr
             (Call_Expr.Args (Call_Expr.Args.First_Index + 1),
              Var_Types,
              Functions,
              Type_Env,
              Const_Env,
              Path);
         Key_Expr :=
           Validate_And_Contextualize_Value
             (Key_Expr,
              Key_Type,
              Var_Types,
              Functions,
              Type_Env,
              Const_Env,
              Exact_Length_Maps.Empty_Map,
              Path,
              "`" & Builtin_Name & "` key type does not match the map key type");

         Result_Expr :=
           Shared_Call_Expr
             (Shared,
              (if Builtin_Kind = Builtin_Contains
               then Shared_Contains_Name
               elsif Builtin_Kind = Builtin_Get
               then Shared_Get_Name
               else Shared_Remove_Name),
              Call_Expr.Span,
              (if Builtin_Kind = Builtin_Contains
               then UString_Value (BT.Boolean_Type.Name)
               else UString_Value (Make_Optional_Type (Value_Type, Type_Env).Name)));
         Result_Expr.Args.Append (Key_Expr);
         return Result_Expr;
      end Rewrite_Shared_Container_Expr_Call;
   begin
      if Expr = null then
         return null;
      end if;

      Enum_Expr := Rewrite_Static_Enum_Literal (Expr, Const_Env);
      if Enum_Expr /= null then
         return Set_Type (Enum_Expr, Expr_Type (Enum_Expr, Var_Types, Functions, Type_Env));
      end if;

      case Expr.Kind is
         when CM.Expr_Apply =>
            declare
               Resolved : constant CM.Expr_Access :=
                 Resolve_Apply (Expr, Var_Types, Functions, Type_Env, Const_Env, Path);
               Shared      : Shared_Object_Ref;
               Shared_Type : GM.Type_Descriptor;
            begin
               if Expr.Callee /= null
                 and then Expr.Callee.Kind = CM.Expr_Select
               then
                  if Is_Sum_Type
                    (Expr_Type (Expr.Callee.Prefix, Var_Types, Functions, Type_Env),
                     Type_Env)
                  then
                     Raise_Diag
                       (CM.Unsupported_Source_Construct
                          (Path    => Path,
                           Span    => Expr.Callee.Span,
                           Message => Sum_Inspection_Message));
                  end if;
                  if Try_Shared_Root_Expr
                    (Expr.Callee.Prefix,
                     Shared)
                  then
                     Shared_Type := Shared.Type_Info;
                     if Is_Shared_Container_Root_Type (Shared_Type, Type_Env)
                       and then not Is_Admitted_Shared_Container_Method_Name
                         (Canonical_Name (UString_Value (Expr.Callee.Selector)))
                     then
                        Raise_Diag
                          (CM.Unsupported_Source_Construct
                             (Path    => Path,
                              Span    => Expr.Callee.Span,
                              Message => Shared_Container_Snapshot_Message));
                     end if;
                  end if;
               end if;

               if Resolved.Kind = CM.Expr_Resolved_Index then
                  if Try_Shared_Root_Expr
                    (Resolved.Prefix,
                     Shared)
                  then
                     Shared_Type := Shared.Type_Info;
                     if Is_Shared_Container_Root_Type (Shared_Type, Type_Env) then
                        Raise_Diag
                          (CM.Unsupported_Source_Construct
                             (Path    => Path,
                              Span    => Resolved.Span,
                              Message => Shared_Container_Snapshot_Message));
                     end if;
                  end if;
                  Result := new CM.Expr_Node'(Resolved.all);
                  Result.Prefix :=
                    Normalize_Expr (Resolved.Prefix, Var_Types, Functions, Type_Env, Const_Env, Path);
                  Result.Args.Clear;
                  for Item of Resolved.Args loop
                     Result.Args.Append
                       (Normalize_Expr (Item, Var_Types, Functions, Type_Env, Const_Env, Path));
                  end loop;
               elsif Resolved.Kind = CM.Expr_Call then
                  declare
                     Callee_Name : constant String := Flatten_Name (Resolved.Callee);
                  begin
                     if Has_Sum_Constructor (Callee_Name) then
                        declare
                           Constructor : constant Sum_Constructor_Info :=
                             Get_Sum_Constructor (Callee_Name);
                           Constructor_Args : CM.Expr_Access_Vectors.Vector;
                           Normalized_Arg : CM.Expr_Access;
                           Expected_Type : GM.Type_Descriptor;
                           Expected_Count : constant Natural :=
                             Natural (Constructor.Fields.Length);
                           Actual_Count : constant Natural :=
                             Natural (Resolved.Args.Length);
                        begin
                           if Expected_Count = 0 and then Actual_Count = 0 then
                              Raise_Diag
                                (CM.Unsupported_Source_Construct
                                   (Path    => Path,
                                    Span    => (if Resolved.Has_Call_Span then Resolved.Call_Span else Resolved.Span),
                                    Message =>
                                      "zero-payload sum variants use the bare variant name in PR11.13a"));
                           end if;

                           if Actual_Count /= Expected_Count then
                              Raise_Diag
                                (CM.Source_Frontend_Error
                                   (Path    => Path,
                                    Span    => (if Resolved.Has_Call_Span then Resolved.Call_Span else Resolved.Span),
                                    Message =>
                                      "sum variant constructor `"
                                      & Callee_Name
                                      & "` expects "
                                      & Ada.Strings.Fixed.Trim
                                          (Natural'Image (Expected_Count),
                                           Ada.Strings.Both)
                                      & " argument"
                                      & (if Expected_Count = 1 then "" else "s")));
                           end if;

                           if not Constructor.Fields.Is_Empty then
                              for Index in Constructor.Fields.First_Index .. Constructor.Fields.Last_Index loop
                                 Expected_Type :=
                                   Resolve_Type
                                     (UString_Value (Constructor.Fields (Index).Type_Name),
                                      Type_Env,
                                      Path,
                                      Resolved.Args
                                        (Resolved.Args.First_Index
                                         + (Index - Constructor.Fields.First_Index)).Span);
                                 Normalized_Arg :=
                                   Normalize_Expr
                                     (Resolved.Args
                                        (Resolved.Args.First_Index
                                         + (Index - Constructor.Fields.First_Index)),
                                      Var_Types,
                                      Functions,
                                      Type_Env,
                                      Const_Env,
                                      Path);
                                 Normalized_Arg :=
                                   Contextualize_Expr_To_Target_Type
                                     (Normalized_Arg,
                                      Expected_Type,
                                      Var_Types,
                                      Functions,
                                      Type_Env,
                                      Path);
                                 Stamp_Contextual_String_Literal
                                   (Normalized_Arg,
                                    Expected_Type,
                                    Type_Env);
                                 Reject_Uncontextualized_None (Normalized_Arg, Path);
                                 if not Compatible_Source_Expr_To_Target_Type
                                   (Normalized_Arg,
                                    Expr_Type (Normalized_Arg, Var_Types, Functions, Type_Env),
                                    Expected_Type,
                                    Var_Types,
                                    Functions,
                                    Type_Env,
                                    Const_Env,
                                    Exact_Length_Maps.Empty_Map)
                                 then
                                    Raise_Diag
                                      (CM.Source_Frontend_Error
                                         (Path    => Path,
                                          Span    => Normalized_Arg.Span,
                                          Message =>
                                            "sum variant constructor `"
                                            & Callee_Name
                                            & "` argument does not match the payload type"));
                                 end if;
                                 Constructor_Args.Append (Normalized_Arg);
                              end loop;
                           end if;

                           Result :=
                             Build_Sum_Constructor_Expr
                               (Constructor,
                                Constructor_Args,
                                Resolved.Span);
                        end;
                     else
                        Result := new CM.Expr_Node'(Resolved.all);
                        Result.Callee :=
                          Normalize_Expr (Resolved.Callee, Var_Types, Functions, Type_Env, Const_Env, Path);
                        Result.Args.Clear;
                        for Item of Resolved.Args loop
                           Result.Args.Append
                             (Normalize_Expr (Item, Var_Types, Functions, Type_Env, Const_Env, Path));
                        end loop;
                        declare
                           Shared_Rewrite : constant CM.Expr_Access :=
                             Rewrite_Shared_Container_Expr_Call (Resolved);
                        begin
                           if Shared_Rewrite /= null then
                              return Shared_Rewrite;
                           end if;
                        end;
                        Validate_Mut_Call_Arguments (Result, Functions, Path);
                        declare
                           Builtin_Kind : constant Builtin_Method_Kind :=
                             Builtin_Method_Kind_For_Call
                               (Result,
                                Var_Types,
                                Functions,
                                Type_Env);
                           Builtin_Name : constant String :=
                             Builtin_Method_Name (Builtin_Kind);
                        begin
                           if Builtin_Kind = Builtin_Pop_Last then
                              if Natural (Result.Args.Length) /= 1 then
                                 Raise_Diag
                                   (CM.Source_Frontend_Error
                                      (Path    => Path,
                                       Span    => (if Result.Has_Call_Span then Result.Call_Span else Result.Span),
                                       Message => "`pop_last(items)` expects exactly one argument"));
                              elsif not Is_Assignable_Target (Result.Args (Result.Args.First_Index)) then
                                 Raise_Diag
                                   (CM.Source_Frontend_Error
                                      (Path    => Path,
                                       Span    => Result.Args (Result.Args.First_Index).Span,
                                       Message => "`pop_last` first argument must be a writable list name"));
                              else
                                 declare
                                    List_Type : constant GM.Type_Descriptor :=
                                      Expr_Type
                                        (Result.Args (Result.Args.First_Index),
                                         Var_Types,
                                         Functions,
                                         Type_Env);
                                    Element_Type : GM.Type_Descriptor;
                                 begin
                                    if not Is_Growable_Array_Type (List_Type, Type_Env) then
                                       Raise_Diag
                                         (CM.Source_Frontend_Error
                                            (Path    => Path,
                                             Span    => Result.Args (Result.Args.First_Index).Span,
                                             Message => "`pop_last` expects a `mut list of T` first argument"));
                                    end if;
                                    Element_Type := Growable_Array_Element_Type (List_Type, Type_Env);
                                    if not Is_Container_Element_Type_Allowed (Element_Type, Type_Env) then
                                       Raise_Diag
                                         (CM.Unsupported_Source_Construct
                                            (Path    => Path,
                                             Span    => Result.Args (Result.Args.First_Index).Span,
                                             Message =>
                                               "`list of T` is limited to the admitted value-type subset in PR11.10b"));
                                    end if;
                                    Result.Type_Name :=
                                      Make_Optional_Type (Element_Type, Type_Env).Name;
                                 end;
                              end if;
                           elsif Builtin_Kind in Builtin_Contains | Builtin_Get | Builtin_Remove then
                              if Natural (Result.Args.Length) /= 2 then
                                 Raise_Diag
                                   (CM.Source_Frontend_Error
                                      (Path    => Path,
                                       Span    => (if Result.Has_Call_Span then Result.Call_Span else Result.Span),
                                       Message => "`" & Builtin_Name & "(m, key)` expects exactly two arguments"));
                              end if;

                              declare
                                 Map_Expr    : constant CM.Expr_Access :=
                                   Result.Args (Result.Args.First_Index);
                                 Key_Expr    : CM.Expr_Access :=
                                   Result.Args (Result.Args.First_Index + 1);
                                 Map_Type    : constant GM.Type_Descriptor :=
                                   Expr_Type (Map_Expr, Var_Types, Functions, Type_Env);
                                 Key_Type    : GM.Type_Descriptor;
                                 Value_Type  : GM.Type_Descriptor;
                              begin
                                 if Builtin_Name = "remove"
                                   and then not Is_Assignable_Target (Map_Expr)
                                 then
                                    Raise_Diag
                                      (CM.Source_Frontend_Error
                                         (Path    => Path,
                                          Span    => Map_Expr.Span,
                                          Message => "`remove` first argument must be a writable map name"));
                                 elsif not Try_Map_Key_Value_Types (Map_Type, Type_Env, Key_Type, Value_Type) then
                                    Raise_Diag
                                      (CM.Source_Frontend_Error
                                         (Path    => Path,
                                          Span    => Map_Expr.Span,
                                          Message => "`" & Builtin_Name & "` expects a `map of (K, V)` first argument"));
                                 elsif not Is_Map_Key_Type_Allowed (Key_Type, Type_Env) then
                                    Raise_Diag
                                      (CM.Unsupported_Source_Construct
                                         (Path    => Path,
                                          Span    => Map_Expr.Span,
                                          Message =>
                                            "`map of (K, V)` keys are limited to the admitted discrete/string subset in PR11.10c"));
                                 elsif not Is_Container_Element_Type_Allowed (Value_Type, Type_Env) then
                                    Raise_Diag
                                      (CM.Unsupported_Source_Construct
                                         (Path    => Path,
                                          Span    => Map_Expr.Span,
                                          Message =>
                                            "`map of (K, V)` values are limited to the admitted value-type subset in PR11.10c"));
                                 else
                                    Key_Expr :=
                                      Validate_And_Contextualize_Value
                                        (Key_Expr,
                                         Key_Type,
                                         Var_Types,
                                         Functions,
                                         Type_Env,
                                         Const_Env,
                                         Exact_Length_Maps.Empty_Map,
                                         Path,
                                         "`" & Builtin_Name & "` key type does not match the map key type",
                                         Stamp_String_Literal => False);
                                    Result.Args.Replace_Element (Result.Args.First_Index + 1, Key_Expr);
                                    if Builtin_Kind = Builtin_Contains then
                                       Result.Type_Name := FT.To_UString ("boolean");
                                    else
                                       Result.Type_Name := Make_Optional_Type (Value_Type, Type_Env).Name;
                                    end if;
                                 end if;
                              end;
                           end if;
                        end;
                        Result :=
                          Specialize_Generic_Call
                            (Result,
                             Var_Types,
                             Functions,
                             Type_Env,
                             Const_Env,
                             Path);
                        Result :=
                          Specialize_Interface_Call
                            (Result,
                             Var_Types,
                             Functions,
                             Type_Env,
                             Const_Env,
                             Path);
                     end if;
                  end;
               else
                  Result := new CM.Expr_Node'(Resolved.all);
                  Result.Inner :=
                    Normalize_Expr (Resolved.Inner, Var_Types, Functions, Type_Env, Const_Env, Path);
               end if;
            end;
         when CM.Expr_Ident =>
            if Has_Sum_Constructor (UString_Value (Expr.Name)) then
               declare
                  Constructor : constant Sum_Constructor_Info :=
                    Get_Sum_Constructor (UString_Value (Expr.Name));
                  Empty_Args  : CM.Expr_Access_Vectors.Vector;
               begin
                  if not Constructor.Fields.Is_Empty then
                     Raise_Diag
                       (CM.Source_Frontend_Error
                          (Path    => Path,
                           Span    => Expr.Span,
                           Message =>
                             "sum variant constructor `"
                             & UString_Value (Expr.Name)
                             & "` requires "
                             & Ada.Strings.Fixed.Trim
                                 (Natural'Image (Natural (Constructor.Fields.Length)),
                                  Ada.Strings.Both)
                             & " argument"
                             & (if Natural (Constructor.Fields.Length) = 1 then "" else "s")));
                  end if;
                  Result :=
                    Build_Sum_Constructor_Expr
                      (Constructor,
                       Empty_Args,
                       Expr.Span);
               end;
            elsif Is_Shared_Object_Name (UString_Value (Expr.Name)) then
               declare
                  Shared : Shared_Object_Ref;
               begin
                  if not Try_Shared_Root_Expr (Expr, Shared) then
                     Raise_Diag
                       (CM.Source_Frontend_Error
                          (Path    => Path,
                           Span    => Expr.Span,
                           Message =>
                             "internal error: shared root lookup failed after local shared-object match"));
                  end if;
                  Result :=
                    Shared_Snapshot_Expr (Shared, Expr.Span);
               end;
            else
               Result := new CM.Expr_Node'(Expr.all);
            end if;
         when CM.Expr_Select =>
            declare
               Shared : Shared_Object_Ref;
               Shared_Field_Type : GM.Type_Descriptor;
               Call_Result : CM.Expr_Access;
               Shared_Root_Type : GM.Type_Descriptor;
               Constructor_Name : constant String := Flatten_Name (Expr);
            begin
               if Has_Sum_Constructor (Constructor_Name) then
                  declare
                     Constructor : constant Sum_Constructor_Info :=
                       Get_Sum_Constructor (Constructor_Name);
                     Empty_Args  : CM.Expr_Access_Vectors.Vector;
                  begin
                     if not Constructor.Fields.Is_Empty then
                        Raise_Diag
                          (CM.Source_Frontend_Error
                             (Path    => Path,
                              Span    => Expr.Span,
                              Message =>
                                "sum variant constructor `"
                                & Constructor_Name
                                & "` requires "
                                & Ada.Strings.Fixed.Trim
                                    (Natural'Image (Natural (Constructor.Fields.Length)),
                                     Ada.Strings.Both)
                                & " argument"
                                & (if Natural (Constructor.Fields.Length) = 1 then "" else "s")));
                     end if;
                     Result :=
                       Build_Sum_Constructor_Expr
                         (Constructor,
                          Empty_Args,
                          Expr.Span);
                  end;
               elsif Try_Shared_Root_Expr (Expr, Shared) then
                  Result := Shared_Snapshot_Expr (Shared, Expr.Span);
               elsif UString_Value (Expr.Selector) = "length"
               then
                  if Try_Shared_Root_Expr
                    (Expr.Prefix,
                     Shared)
                  then
                     Shared_Root_Type := Shared.Type_Info;
                     if Is_Shared_Container_Root_Type (Shared_Root_Type, Type_Env) then
                        Result :=
                          Shared_Call_Expr
                            (Shared,
                             Shared_Get_Length_Name,
                             Expr.Span,
                             UString_Value (Default_Integer.Name));
                     end if;
                  end if;
               end if;
               if Result = null and then Try_Shared_Top_Level_Field_Access
                 (Expr,
                  Type_Env,
                  Shared,
                  Shared_Field_Type)
               then
                  Call_Result :=
                    Shared_Call_Expr
                      (Shared,
                      Shared_Field_Getter_Name (UString_Value (Expr.Selector)),
                       Expr.Span,
                       UString_Value (Shared_Field_Type.Name));
                  Result := Call_Result;
               end if;
               if Result = null
                 and then Is_Sum_Type
                   (Expr_Type (Expr.Prefix, Var_Types, Functions, Type_Env), Type_Env)
               then
                  Raise_Diag
                    (CM.Unsupported_Source_Construct
                       (Path    => Path,
                        Span    => Expr.Span,
                        Message => Sum_Inspection_Message));
               end if;
               if Result = null then
                  Result := new CM.Expr_Node'(Expr.all);
                  Result.Prefix :=
                    Normalize_Expr (Expr.Prefix, Var_Types, Functions, Type_Env, Const_Env, Path);
               end if;
            end;
         when CM.Expr_Binary =>
            Result := new CM.Expr_Node'(Expr.all);
            Result.Left := Normalize_Expr (Expr.Left, Var_Types, Functions, Type_Env, Const_Env, Path);
            Result.Right := Normalize_Expr (Expr.Right, Var_Types, Functions, Type_Env, Const_Env, Path);
         when CM.Expr_Unary =>
            Result := new CM.Expr_Node'(Expr.all);
            Result.Inner := Normalize_Expr (Expr.Inner, Var_Types, Functions, Type_Env, Const_Env, Path);
         when CM.Expr_Allocator =>
            Result := new CM.Expr_Node'(Expr.all);
            if Expr.Value /= null and then Expr.Value.Kind = CM.Expr_Annotated then
               Result.Value := new CM.Expr_Node'(Expr.Value.all);
               Result.Value.Inner :=
                 Normalize_Expr (Expr.Value.Inner, Var_Types, Functions, Type_Env, Const_Env, Path);
            end if;
         when CM.Expr_Aggregate =>
            Result := new CM.Expr_Node'(Expr.all);
            Result.Fields.Clear;
            for Item of Expr.Fields loop
               Field := Item;
               Field.Expr := Normalize_Expr (Item.Expr, Var_Types, Functions, Type_Env, Const_Env, Path);
               Result.Fields.Append (Field);
            end loop;
         when CM.Expr_Array_Literal =>
            Result := new CM.Expr_Node'(Expr.all);
            Result.Elements.Clear;
            for Item of Expr.Elements loop
               Result.Elements.Append
                 (Normalize_Expr (Item, Var_Types, Functions, Type_Env, Const_Env, Path));
            end loop;
         when CM.Expr_Tuple =>
            Result := new CM.Expr_Node'(Expr.all);
            Result.Elements.Clear;
            for Item of Expr.Elements loop
               Result.Elements.Append
                 (Normalize_Expr (Item, Var_Types, Functions, Type_Env, Const_Env, Path));
            end loop;
         when CM.Expr_Annotated =>
            declare
               Inner_Result : constant CM.Expr_Access :=
                 Normalize_Expr (Expr.Inner, Var_Types, Functions, Type_Env, Const_Env, Path);
               Target_Type  : constant GM.Type_Descriptor :=
                 Resolve_Target_Type (Expr.Target, Type_Env);
            begin
               if Inner_Result /= null and then Inner_Result.Kind = CM.Expr_None then
                  if not Is_Optional_Type (Target_Type, Type_Env) then
                     Raise_Diag
                       (CM.Source_Frontend_Error
                          (Path    => Path,
                           Span    => Expr.Span,
                           Message => "`none` type ascription requires an `optional T` target"));
                  end if;
                  Result := Build_Optional_None_Expr (Target_Type, Expr.Span);
               else
                  Result := new CM.Expr_Node'(Expr.all);
                  Result.Inner := Inner_Result;
               end if;
            end;
         when CM.Expr_Some =>
            declare
               Inner_Result  : constant CM.Expr_Access :=
                 Normalize_Expr (Expr.Inner, Var_Types, Functions, Type_Env, Const_Env, Path);
               Payload_Type  : constant GM.Type_Descriptor :=
                 Expr_Type (Inner_Result, Var_Types, Functions, Type_Env);
               Optional_Type : GM.Type_Descriptor;
            begin
               if not Is_Optional_Element_Type_Allowed (Payload_Type, Type_Env) then
                  Raise_Diag
                    (CM.Unsupported_Source_Construct
                       (Path    => Path,
                        Span    => Expr.Span,
                        Message =>
                          "`optional T` is limited to the admitted value-type subset in PR11.10a"));
               end if;
               Optional_Type := Make_Optional_Type (Payload_Type, Type_Env);
               Result := Build_Optional_Some_Expr (Optional_Type, Inner_Result, Expr.Span);
            end;
         when CM.Expr_None =>
            Result := new CM.Expr_Node'(Expr.all);
         when CM.Expr_Try =>
            Result := new CM.Expr_Node'(Expr.all);
            Result.Inner := Normalize_Expr (Expr.Inner, Var_Types, Functions, Type_Env, Const_Env, Path);
         when others =>
            Result := new CM.Expr_Node'(Expr.all);
      end case;

      return Set_Type (Result, Expr_Type (Result, Var_Types, Functions, Type_Env));
   end Normalize_Expr;

   function Contextualize_Expr_To_Target_Type
     (Expr      : CM.Expr_Access;
      Target    : GM.Type_Descriptor;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Path      : String) return CM.Expr_Access
   is
      Result     : CM.Expr_Access;
      Field      : CM.Aggregate_Field;
      Target_Base : constant GM.Type_Descriptor := Base_Type (Target, Type_Env);
   begin
      if Expr = null then
         return null;
      end if;

      if Expr.Kind = CM.Expr_None then
         if Is_Optional_Type (Target, Type_Env) then
            return Build_Optional_None_Expr (Target, Expr.Span);
         end if;
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path,
               Span    => Expr.Span,
               Message => "`none` requires an expected `optional T` type"));
      elsif Expr.Kind = CM.Expr_Annotated
        and then Expr.Inner /= null
        and then Expr.Inner.Kind = CM.Expr_None
      then
         declare
            Explicit_Target : constant GM.Type_Descriptor :=
              Resolve_Target_Type (Expr.Target, Type_Env);
         begin
            if not Is_Optional_Type (Explicit_Target, Type_Env) then
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path,
                     Span    => Expr.Span,
                     Message => "`none` type ascription requires an `optional T` target"));
            end if;
            return Build_Optional_None_Expr (Explicit_Target, Expr.Span);
         end;
      end if;

      case Expr.Kind is
         when CM.Expr_Aggregate =>
            Result := new CM.Expr_Node'(Expr.all);
            Result.Fields.Clear;
            for Item of Expr.Fields loop
               Field := Item;
               Field.Expr :=
                 Contextualize_Expr_To_Target_Type
                   (Item.Expr,
                    Field_Type (Target_Base, UString_Value (Item.Field_Name), Type_Env),
                    Var_Types,
                    Functions,
                    Type_Env,
                    Path);
               Result.Fields.Append (Field);
            end loop;
            if UString_Value (Result.Type_Name)'Length = 0 then
               Result.Type_Name := Target.Name;
            end if;
            return Set_Type (Result, Expr_Type (Result, Var_Types, Functions, Type_Env));
         when CM.Expr_Tuple =>
            Result := new CM.Expr_Node'(Expr.all);
            if Is_Tuple_Type (Target_Base, Type_Env)
              and then Natural (Expr.Elements.Length) =
                       Natural (Target_Base.Tuple_Element_Types.Length)
            then
               Result.Elements.Clear;
               for Index in Expr.Elements.First_Index .. Expr.Elements.Last_Index loop
                  Result.Elements.Append
                    (Contextualize_Expr_To_Target_Type
                       (Expr.Elements (Index),
                        Resolve_Type
                          (UString_Value (Target_Base.Tuple_Element_Types (Index)),
                           Type_Env,
                           "",
                           FT.Null_Span),
                        Var_Types,
                        Functions,
                        Type_Env,
                        Path));
               end loop;
               Result.Type_Name := Target.Name;
               return Set_Type (Result, Expr_Type (Result, Var_Types, Functions, Type_Env));
            end if;
            return Expr;
         when CM.Expr_Array_Literal =>
            Result := new CM.Expr_Node'(Expr.all);
            if Target_Base.Has_Component_Type then
               Result.Elements.Clear;
               for Item of Expr.Elements loop
                  Result.Elements.Append
                    (Contextualize_Expr_To_Target_Type
                       (Item,
                        Resolve_Type
                          (UString_Value (Target_Base.Component_Type),
                           Type_Env,
                           "",
                           FT.Null_Span),
                        Var_Types,
                        Functions,
                        Type_Env,
                        Path));
               end loop;
               Result.Type_Name := Target.Name;
               return Set_Type (Result, Expr_Type (Result, Var_Types, Functions, Type_Env));
            end if;
            return Expr;
         when others =>
            return Expr;
      end case;
   end Contextualize_Expr_To_Target_Type;

   procedure Reject_Uncontextualized_None
     (Expr  : CM.Expr_Access;
      Path  : String) is
   begin
      if Expr = null then
         return;
      elsif Expr.Kind = CM.Expr_None then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path,
               Span    => Expr.Span,
               Message => "`none` requires an expected `optional T` type"));
      end if;

      case Expr.Kind is
         when CM.Expr_Select | CM.Expr_Conversion | CM.Expr_Annotated | CM.Expr_Unary | CM.Expr_Try =>
            Reject_Uncontextualized_None (Expr.Prefix, Path);
            Reject_Uncontextualized_None (Expr.Inner, Path);
         when CM.Expr_Resolved_Index | CM.Expr_Call | CM.Expr_Apply =>
            Reject_Uncontextualized_None (Expr.Prefix, Path);
            Reject_Uncontextualized_None (Expr.Callee, Path);
            for Item of Expr.Args loop
               Reject_Uncontextualized_None (Item, Path);
            end loop;
         when CM.Expr_Binary =>
            Reject_Uncontextualized_None (Expr.Left, Path);
            Reject_Uncontextualized_None (Expr.Right, Path);
         when CM.Expr_Allocator =>
            Reject_Uncontextualized_None (Expr.Value, Path);
         when CM.Expr_Aggregate =>
            for Item of Expr.Fields loop
               Reject_Uncontextualized_None (Item.Expr, Path);
            end loop;
         when CM.Expr_Array_Literal | CM.Expr_Tuple =>
            for Item of Expr.Elements loop
               Reject_Uncontextualized_None (Item, Path);
            end loop;
         when CM.Expr_Some =>
            Reject_Uncontextualized_None (Expr.Inner, Path);
         when others =>
            null;
      end case;
   end Reject_Uncontextualized_None;

   function Validate_And_Contextualize_Value
     (Value                 : CM.Expr_Access;
      Target_Type           : GM.Type_Descriptor;
      Var_Types             : Type_Maps.Map;
      Functions             : Function_Maps.Map;
      Type_Env              : Type_Maps.Map;
      Const_Env             : Static_Value_Maps.Map;
      Exact_Length_Facts    : Exact_Length_Maps.Map;
      Path                  : String;
      Mismatch_Message      : String;
      Stamp_String_Literal  : Boolean := True) return CM.Expr_Access
   is
      Result : constant CM.Expr_Access :=
        Contextualize_Expr_To_Target_Type
          (Value,
           Target_Type,
           Var_Types,
           Functions,
           Type_Env,
           Path);
   begin
      if Result = null then
         raise Program_Error
           with "Validate_And_Contextualize_Value: null input";
      end if;

      if Stamp_String_Literal then
         Stamp_Contextual_String_Literal (Result, Target_Type, Type_Env);
      end if;
      Reject_Uncontextualized_None (Result, Path);
      --  Setter paths may still stamp Result.Type_Name after this helper
      --  returns. That deferred stamp is emission-only: compatibility here
      --  relies on Expr_Type (Result, ...) as it stands now, and the
      --  relevant shared-setter literal cases are typed structurally (for
      --  example, string literals read as string types before any later
      --  bounded-string name is attached for emission).
      if not Compatible_Source_Expr_To_Target_Type
        (Result,
         Expr_Type (Result, Var_Types, Functions, Type_Env),
         Target_Type,
         Var_Types,
         Functions,
         Type_Env,
         Const_Env,
         Exact_Length_Facts)
      then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path,
               Span    => Result.Span,
               Message => Mismatch_Message));
      end if;
      return Result;
   end Validate_And_Contextualize_Value;

   function Builtin_Method_Kind_For_Call
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map) return Builtin_Method_Kind
   is
      Name : constant String :=
        (if Expr = null
              or else Expr.Kind /= CM.Expr_Call
              or else Expr.Callee = null
              or else Expr.Callee.Kind /= CM.Expr_Ident
         then ""
         else UString_Value (Expr.Callee.Name));
      Lower_Name : constant String := Canonical_Name (Name);
   begin
      if Name'Length = 0
        or else Has_Function_Canonical (Functions, Lower_Name)
        or else Has_Type_Canonical (Var_Types, Lower_Name)
        or else Has_Type_Canonical (Type_Env, Lower_Name)
      then
         return Builtin_None;
      end if;

      return Builtin_Method_Kind_For_Canonical_Name (Lower_Name);
   end Builtin_Method_Kind_For_Call;

   function Is_Unshadowed_Builtin_Call
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Name      : String) return Boolean is
   begin
      if Name /= Canonical_Name (Name) then
         return False;
      end if;

      declare
         Kind : constant Builtin_Method_Kind :=
           Builtin_Method_Kind_For_Canonical_Name (Name);
      begin
         return
           Kind /= Builtin_None  --  Guard unknown-name callers: otherwise both
                                 --  classifiers could return Builtin_None and
                                 --  this check would incorrectly succeed.
           and then Builtin_Method_Kind_For_Call (Expr, Var_Types, Functions, Type_Env) = Kind;
      end;
   end Is_Unshadowed_Builtin_Call;

   function Is_Append_Builtin_Call
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map) return Boolean is
   begin
      return
        Is_Unshadowed_Builtin_Call (Expr, Var_Types, Functions, Type_Env, "append");
   end Is_Append_Builtin_Call;

   function Is_Pop_Last_Builtin_Call
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map) return Boolean is
   begin
      return
        Is_Unshadowed_Builtin_Call (Expr, Var_Types, Functions, Type_Env, "pop_last");
   end Is_Pop_Last_Builtin_Call;

   function Is_Contains_Builtin_Call
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map) return Boolean is
   begin
      return
        Is_Unshadowed_Builtin_Call (Expr, Var_Types, Functions, Type_Env, "contains");
   end Is_Contains_Builtin_Call;

   function Is_Get_Builtin_Call
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map) return Boolean is
   begin
      return
        Is_Unshadowed_Builtin_Call (Expr, Var_Types, Functions, Type_Env, "get");
   end Is_Get_Builtin_Call;

   function Is_Set_Builtin_Call
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map) return Boolean is
   begin
      return
        Is_Unshadowed_Builtin_Call (Expr, Var_Types, Functions, Type_Env, "set");
   end Is_Set_Builtin_Call;

   function Is_Remove_Builtin_Call
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map) return Boolean is
   begin
      return
        Is_Unshadowed_Builtin_Call (Expr, Var_Types, Functions, Type_Env, "remove");
   end Is_Remove_Builtin_Call;

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
            if Is_Tuple_Type (Prefix_Type, Type_Env) then
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
            for Item of Expr.Args loop
               Validate_Pr112_Expr_Boundaries (Item, Var_Types, Functions, Type_Env, Path);
            end loop;
            Prefix_Type := Expr_Type (Expr.Prefix, Var_Types, Functions, Type_Env);
            if Is_String_Type (Prefix_Type, Type_Env)
              or else Is_Growable_Array_Type (Prefix_Type, Type_Env)
            then
               if Natural (Expr.Args.Length) not in 1 | 2 then
                  Raise_Diag
                    (CM.Source_Frontend_Error
                       (Path    => Path,
                        Span    => Expr.Span,
                        Message => "string and growable-array indexing expects one index or one slice range"));
               end if;
               for Item of Expr.Args loop
                  declare
                     Arg_Type : constant GM.Type_Descriptor :=
                       Expr_Type (Item, Var_Types, Functions, Type_Env);
                  begin
                     if not Is_Integerish (Arg_Type, Type_Env)
                       or else Is_Boolean_Type (Arg_Type, Type_Env)
                     then
                        Raise_Diag
                          (CM.Source_Frontend_Error
                             (Path    => Path,
                              Span    => Item.Span,
                              Message => "index and slice bounds must be integer expressions"));
                     end if;
                  end;
               end loop;
            end if;
         when CM.Expr_Call =>
            Validate_Pr112_Expr_Boundaries (Expr.Callee, Var_Types, Functions, Type_Env, Path);
            for Item of Expr.Args loop
               Validate_Pr112_Expr_Boundaries (Item, Var_Types, Functions, Type_Env, Path);
            end loop;
         when CM.Expr_Conversion =>
            Validate_Pr112_Expr_Boundaries (Expr.Inner, Var_Types, Functions, Type_Env, Path);
         when CM.Expr_Allocator =>
            Validate_Pr112_Expr_Boundaries (Expr.Value, Var_Types, Functions, Type_Env, Path);
         when CM.Expr_Try =>
            Validate_Pr112_Expr_Boundaries (Expr.Inner, Var_Types, Functions, Type_Env, Path);
         when CM.Expr_Aggregate =>
            for Item of Expr.Fields loop
               Validate_Pr112_Expr_Boundaries (Item.Expr, Var_Types, Functions, Type_Env, Path);
            end loop;
         when CM.Expr_Array_Literal =>
            for Item of Expr.Elements loop
               Validate_Pr112_Expr_Boundaries (Item, Var_Types, Functions, Type_Env, Path);
            end loop;
         when CM.Expr_Tuple =>
            for Item of Expr.Elements loop
               Validate_Pr112_Expr_Boundaries (Item, Var_Types, Functions, Type_Env, Path);
            end loop;
         when CM.Expr_Annotated =>
            Validate_Pr112_Expr_Boundaries (Expr.Inner, Var_Types, Functions, Type_Env, Path);
         when CM.Expr_Some =>
            Validate_Pr112_Expr_Boundaries (Expr.Inner, Var_Types, Functions, Type_Env, Path);
         when CM.Expr_Unary =>
            Validate_Pr112_Expr_Boundaries (Expr.Inner, Var_Types, Functions, Type_Env, Path);
         when CM.Expr_Binary =>
            Validate_Pr112_Expr_Boundaries (Expr.Left, Var_Types, Functions, Type_Env, Path);
            Validate_Pr112_Expr_Boundaries (Expr.Right, Var_Types, Functions, Type_Env, Path);
            Left_Type := Expr_Type (Expr.Left, Var_Types, Functions, Type_Env);
            Right_Type := Expr_Type (Expr.Right, Var_Types, Functions, Type_Env);
            declare
               Op : constant String := UString_Value (Expr.Operator);
            begin
               if Op in "and then" | "or else" then
                  if not Is_Boolean_Type (Left_Type, Type_Env)
                    or else not Is_Boolean_Type (Right_Type, Type_Env)
                  then
                     Raise_Diag
                       (CM.Source_Frontend_Error
                          (Path    => Path,
                           Span    => Expr.Span,
                           Message => "`" & Op & "` requires boolean operands"));
                  end if;
               elsif Op in "and" | "or" | "xor" then
                  if Is_Boolean_Type (Left_Type, Type_Env)
                    and then Is_Boolean_Type (Right_Type, Type_Env)
                  then
                     null;
                  elsif Is_Binary_Type (Left_Type, Type_Env)
                    and then Is_Binary_Type (Right_Type, Type_Env)
                    and then Binary_Bit_Width (Left_Type, Type_Env) = Binary_Bit_Width (Right_Type, Type_Env)
                  then
                     null;
                  else
                     Raise_Diag
                       (CM.Source_Frontend_Error
                          (Path    => Path,
                           Span    => Expr.Span,
                           Message => "`" & Op & "` requires boolean operands or same-width binary operands"));
                  end if;
               elsif Op in "<<" | ">>" then
                  if not Is_Binary_Type (Left_Type, Type_Env) then
                     Raise_Diag
                       (CM.Source_Frontend_Error
                          (Path    => Path,
                           Span    => Expr.Left.Span,
                           Message => "`" & Op & "` requires a binary left operand"));
                  elsif not Is_Integerish (Right_Type, Type_Env)
                    or else Is_Boolean_Type (Right_Type, Type_Env)
                    or else Is_Binary_Type (Right_Type, Type_Env)
                  then
                     Raise_Diag
                       (CM.Source_Frontend_Error
                          (Path    => Path,
                           Span    => Expr.Right.Span,
                           Message => "`" & Op & "` requires an integer shift count"));
                  end if;
               elsif Op in "+" | "-" | "*" | "/" | "mod" | "rem" then
                  if Is_Enum_Type (Left_Type, Type_Env)
                    or else Is_Enum_Type (Right_Type, Type_Env)
                  then
                     Raise_Diag
                       (CM.Source_Frontend_Error
                          (Path    => Path,
                           Span    => Expr.Span,
                           Message => "enum values do not support arithmetic"));
                  end if;
                  if Is_Binary_Type (Left_Type, Type_Env)
                    or else Is_Binary_Type (Right_Type, Type_Env)
                  then
                     if not Is_Binary_Type (Left_Type, Type_Env)
                       or else not Is_Binary_Type (Right_Type, Type_Env)
                     then
                        Raise_Diag
                          (CM.Source_Frontend_Error
                             (Path    => Path,
                              Span    => Expr.Span,
                              Message => "binary arithmetic does not mix implicitly with integer"));
                     elsif Binary_Bit_Width (Left_Type, Type_Env) /= Binary_Bit_Width (Right_Type, Type_Env) then
                        Raise_Diag
                          (CM.Source_Frontend_Error
                             (Path    => Path,
                              Span    => Expr.Span,
                              Message => "binary arithmetic requires same-width operands"));
                     end if;
                  end if;
               elsif Op = "&" then
                  if Is_String_Type (Left_Type, Type_Env)
                    or else Is_String_Type (Right_Type, Type_Env)
                  then
                     if not Is_String_Type (Left_Type, Type_Env)
                       or else not Is_String_Type (Right_Type, Type_Env)
                     then
                        Raise_Diag
                          (CM.Source_Frontend_Error
                             (Path    => Path,
                              Span    => Expr.Span,
                              Message => "string concatenation requires string operands"));
                     end if;
                  elsif FT.Lowercase (UString_Value (Left_Type.Kind)) = "array"
                    or else FT.Lowercase (UString_Value (Right_Type.Kind)) = "array"
                  then
                     if FT.Lowercase (UString_Value (Left_Type.Kind)) /= "array"
                       or else FT.Lowercase (UString_Value (Right_Type.Kind)) /= "array"
                       or else not Left_Type.Has_Component_Type
                       or else not Right_Type.Has_Component_Type
                       or else not Compatible_Type
                         (Resolve_Type (UString_Value (Left_Type.Component_Type), Type_Env, "", FT.Null_Span),
                          Resolve_Type (UString_Value (Right_Type.Component_Type), Type_Env, "", FT.Null_Span),
                          Type_Env)
                     then
                        Raise_Diag
                          (CM.Source_Frontend_Error
                             (Path    => Path,
                              Span    => Expr.Span,
                              Message => "growable-array concatenation requires arrays with compatible element types"));
                     end if;
                  end if;
               elsif Op in "==" | "!=" | "<" | "<=" | ">" | ">=" then
                  if Is_Enum_Type (Left_Type, Type_Env)
                    or else Is_Enum_Type (Right_Type, Type_Env)
                  then
                     if not Equivalent_Type (Left_Type, Right_Type, Type_Env) then
                        Raise_Diag
                          (CM.Source_Frontend_Error
                             (Path    => Path,
                              Span    => Expr.Span,
                              Message => "enum comparisons require both operands to have the same enum type"));
                     end if;
                  end if;
                  if Is_Binary_Type (Left_Type, Type_Env)
                    or else Is_Binary_Type (Right_Type, Type_Env)
                  then
                     if not Is_Binary_Type (Left_Type, Type_Env)
                       or else not Is_Binary_Type (Right_Type, Type_Env)
                       or else Binary_Bit_Width (Left_Type, Type_Env) /= Binary_Bit_Width (Right_Type, Type_Env)
                     then
                        Raise_Diag
                          (CM.Source_Frontend_Error
                             (Path    => Path,
                              Span    => Expr.Span,
                              Message => "binary comparisons require same-width binary operands"));
                     end if;
                  end if;
                  if Is_String_Type (Left_Type, Type_Env)
                    or else Is_String_Type (Right_Type, Type_Env)
                  then
                     if not Is_String_Type (Left_Type, Type_Env)
                       or else not Is_String_Type (Right_Type, Type_Env)
                     then
                        Raise_Diag
                          (CM.Source_Frontend_Error
                             (Path    => Path,
                             Span    => Expr.Span,
                             Message => "string comparison requires string operands"));
                     end if;
                  end if;
               end if;
            end;
         when others =>
            null;
      end case;
   end Validate_Pr112_Expr_Boundaries;

   procedure Reject_Non_Executable_Try
     (Expr : CM.Expr_Access;
      Path : String) is
   begin
      if Expr = null then
         return;
      elsif Expr.Kind = CM.Expr_Try then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path,
               Span    => Expr.Span,
               Message => "`try` is allowed only in executable statements inside functions returning `(result, T)`"));
      end if;

      case Expr.Kind is
         when CM.Expr_Select | CM.Expr_Conversion | CM.Expr_Annotated | CM.Expr_Unary | CM.Expr_Some =>
            Reject_Non_Executable_Try (Expr.Prefix, Path);
            Reject_Non_Executable_Try (Expr.Inner, Path);
         when CM.Expr_Resolved_Index | CM.Expr_Call | CM.Expr_Apply =>
            Reject_Non_Executable_Try (Expr.Prefix, Path);
            Reject_Non_Executable_Try (Expr.Callee, Path);
            for Item of Expr.Args loop
               Reject_Non_Executable_Try (Item, Path);
            end loop;
         when CM.Expr_Binary =>
            Reject_Non_Executable_Try (Expr.Left, Path);
            Reject_Non_Executable_Try (Expr.Right, Path);
         when CM.Expr_Allocator =>
            Reject_Non_Executable_Try (Expr.Value, Path);
         when CM.Expr_Aggregate =>
            for Item of Expr.Fields loop
               Reject_Non_Executable_Try (Item.Expr, Path);
            end loop;
         when CM.Expr_Array_Literal | CM.Expr_Tuple =>
            for Item of Expr.Elements loop
               Reject_Non_Executable_Try (Item, Path);
            end loop;
         when others =>
            null;
      end case;
   end Reject_Non_Executable_Try;

   function Normalize_Expr_Checked
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Const_Env : Static_Value_Maps.Map;
      Path      : String;
      Allow_Try : Boolean := False) return CM.Expr_Access
   is
      Result : constant CM.Expr_Access :=
        Normalize_Expr (Expr, Var_Types, Functions, Type_Env, Const_Env, Path);
   begin
      Reject_Bare_Shared_Object_Expr (Result, Type_Env, Path);
      Validate_Pr112_Expr_Boundaries (Result, Var_Types, Functions, Type_Env, Path);
      Validate_Print_Call_Context (Result, Var_Types, Functions, Type_Env, Path);
      if not Allow_Try then
         Reject_Non_Executable_Try (Result, Path);
      end if;
      return Result;
   end Normalize_Expr_Checked;

   function Binary_Modulus (Bit_Width : Positive) return CM.Wide_Integer is
   begin
      case Bit_Width is
         when 8 =>
            return 256;
         when 16 =>
            return 65_536;
         when 32 =>
            return 4_294_967_296;
         when 64 =>
            return 18_446_744_073_709_551_616;
         when others =>
            return 0;
      end case;
   end Binary_Modulus;

   function Wrap_Binary_Static_Value
     (Value     : CM.Wide_Integer;
      Bit_Width : Positive) return CM.Wide_Integer
   is
      Modulus : constant CM.Wide_Integer := Binary_Modulus (Bit_Width);
      Wrapped : CM.Wide_Integer;
   begin
      if Modulus = 0 then
         return Value;
      end if;

      Wrapped := Value rem Modulus;
      if Wrapped < 0 then
         Wrapped := Wrapped + Modulus;
      end if;
      return Wrapped;
   end Wrap_Binary_Static_Value;

   function Try_Static_Integerish_Value
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Const_Env : Static_Value_Maps.Map;
      Result    : out CM.Wide_Integer) return Boolean
   is
      Value      : CM.Static_Value;
      Inner_Value : CM.Wide_Integer := 0;
      Left_Value  : CM.Wide_Integer := 0;
      Right_Value : CM.Wide_Integer := 0;
      Expr_Info   : GM.Type_Descriptor;
      Target_Info : GM.Type_Descriptor;
      Width       : Positive;
   begin
      Result := 0;
      if Expr = null then
         return False;
      end if;

      if Try_Static_Value (Expr, Const_Env, Value)
        and then Value.Kind = CM.Static_Value_Integer
      then
         Result := Value.Int_Value;
         return True;
      end if;

      case Expr.Kind is
         when CM.Expr_Unary =>
            if not Try_Static_Integerish_Value
              (Expr.Inner, Var_Types, Functions, Type_Env, Const_Env, Inner_Value)
            then
               return False;
            end if;

            if UString_Value (Expr.Operator) = "-" then
               Result := -Inner_Value;
               return True;
            end if;
            return False;

         when CM.Expr_Binary =>
            if not Try_Static_Integerish_Value
              (Expr.Left, Var_Types, Functions, Type_Env, Const_Env, Left_Value)
              or else not Try_Static_Integerish_Value
                (Expr.Right, Var_Types, Functions, Type_Env, Const_Env, Right_Value)
            then
               return False;
            end if;

            Expr_Info := Expr_Type (Expr, Var_Types, Functions, Type_Env);
            if Is_Binary_Type (Expr_Info, Type_Env) then
               Width := Binary_Bit_Width (Expr_Info, Type_Env);
               declare
                  Left_Wrapped  : constant CM.Wide_Integer :=
                    Wrap_Binary_Static_Value (Left_Value, Width);
                  Right_Wrapped : constant CM.Wide_Integer :=
                    Wrap_Binary_Static_Value (Right_Value, Width);
               begin
                  if UString_Value (Expr.Operator) = "+" then
                     Result := Wrap_Binary_Static_Value (Left_Wrapped + Right_Wrapped, Width);
                     return True;
                  elsif UString_Value (Expr.Operator) = "-" then
                     Result := Wrap_Binary_Static_Value (Left_Wrapped - Right_Wrapped, Width);
                     return True;
                  elsif UString_Value (Expr.Operator) = "*" then
                     Result := Wrap_Binary_Static_Value (Left_Wrapped * Right_Wrapped, Width);
                     return True;
                  elsif UString_Value (Expr.Operator) = "/" then
                     if Right_Wrapped = 0 then
                        return False;
                     end if;
                     Result := Wrap_Binary_Static_Value (Left_Wrapped / Right_Wrapped, Width);
                     return True;
                  elsif UString_Value (Expr.Operator) = "mod" then
                     if Right_Wrapped = 0 then
                        return False;
                     end if;
                     Result := Wrap_Binary_Static_Value (Left_Wrapped mod Right_Wrapped, Width);
                     return True;
                  elsif UString_Value (Expr.Operator) = "rem" then
                     if Right_Wrapped = 0 then
                        return False;
                     end if;
                     Result := Wrap_Binary_Static_Value (Left_Wrapped rem Right_Wrapped, Width);
                     return True;
                  elsif UString_Value (Expr.Operator) = "<<" then
                     if Right_Value < 0 or else Right_Value >= CM.Wide_Integer (Width) then
                        return False;
                     end if;
                     Result := Wrap_Binary_Static_Value
                       (Left_Wrapped * (CM.Wide_Integer (2) ** Natural (Right_Value)), Width);
                     return True;
                  elsif UString_Value (Expr.Operator) = ">>" then
                     if Right_Value < 0 or else Right_Value >= CM.Wide_Integer (Width) then
                        return False;
                     end if;
                     Result := Left_Wrapped / (CM.Wide_Integer (2) ** Natural (Right_Value));
                     return True;
                  else
                     return False;
                  end if;
               end;
            end if;

            if UString_Value (Expr.Operator) = "+" then
               Result := Left_Value + Right_Value;
               return True;
            elsif UString_Value (Expr.Operator) = "-" then
               Result := Left_Value - Right_Value;
               return True;
            elsif UString_Value (Expr.Operator) = "*" then
               Result := Left_Value * Right_Value;
               return True;
            elsif UString_Value (Expr.Operator) = "/" then
               if Right_Value = 0 then
                  return False;
               end if;
               Result := Left_Value / Right_Value;
               return True;
            elsif UString_Value (Expr.Operator) = "mod" then
               if Right_Value = 0 then
                  return False;
               end if;
               Result := Left_Value mod Right_Value;
               return True;
            elsif UString_Value (Expr.Operator) = "rem" then
               if Right_Value = 0 then
                  return False;
               end if;
               Result := Left_Value rem Right_Value;
               return True;
            else
               return False;
            end if;

         when CM.Expr_Conversion | CM.Expr_Annotated =>
            if not Try_Static_Integerish_Value
              (Expr.Inner, Var_Types, Functions, Type_Env, Const_Env, Inner_Value)
            then
               return False;
            end if;

            if Expr.Target = null then
               return False;
            end if;

            Target_Info := Resolve_Target_Type (Expr.Target, Type_Env);
            if Is_Binary_Type (Target_Info, Type_Env) then
               Result := Wrap_Binary_Static_Value
                 (Inner_Value, Binary_Bit_Width (Target_Info, Type_Env));
               return True;
            elsif Is_Integerish (Target_Info, Type_Env)
              and then not Is_Boolean_Type (Target_Info, Type_Env)
            then
               Result := Inner_Value;
               return True;
            end if;
            return False;

         when others =>
            return False;
      end case;
   end Try_Static_Integerish_Value;

   function Fixed_Array_Cardinality
     (Info      : GM.Type_Descriptor;
      Type_Env  : Type_Maps.Map;
      Cardinality : out Natural) return Boolean
   is
      Base       : constant GM.Type_Descriptor := Base_Type (Info, Type_Env);
      Index_Info : GM.Type_Descriptor;
      Width      : CM.Wide_Integer := 0;
   begin
      Cardinality := 0;
      if FT.Lowercase (UString_Value (Base.Kind)) /= "array"
        or else Base.Growable
        or else Natural (Base.Index_Types.Length) /= 1
      then
         return False;
      end if;

      Index_Info :=
        Resolve_Type
          (UString_Value (Base.Index_Types (Base.Index_Types.First_Index)),
           Type_Env,
           "",
           FT.Null_Span);
      if not Index_Info.Has_Low or else not Index_Info.Has_High then
         Index_Info := Base_Type (Index_Info, Type_Env);
         if not Index_Info.Has_Low or else not Index_Info.Has_High then
            return False;
         end if;
      end if;

      Width :=
        CM.Wide_Integer (Index_Info.High)
        - CM.Wide_Integer (Index_Info.Low)
        + 1;
      if Width < 0 or else Width > CM.Wide_Integer (Natural'Last) then
         return False;
      end if;

      Cardinality := Natural (Width);
      return True;
   end Fixed_Array_Cardinality;

   function Static_Growable_Length
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Const_Env : Static_Value_Maps.Map;
      Length    : out Natural) return Boolean
   is
      Low_Value  : CM.Wide_Integer := 0;
      High_Value : CM.Wide_Integer := 0;
      Width      : CM.Wide_Integer := 0;
   begin
      Length := 0;
      if Expr = null then
         return False;
      elsif Expr.Kind = CM.Expr_Array_Literal then
         Length := Natural (Expr.Elements.Length);
         return True;
      elsif Expr.Kind = CM.Expr_Resolved_Index
        and then Expr.Prefix /= null
        and then Expr.Prefix.Kind in CM.Expr_Ident | CM.Expr_Select
        and then Natural (Expr.Args.Length) = 2
        and then Try_Static_Integerish_Value
          (Expr.Args (Expr.Args.First_Index),
           Var_Types,
           Functions,
           Type_Env,
           Const_Env,
           Low_Value)
        and then Try_Static_Integerish_Value
          (Expr.Args (Expr.Args.First_Index + 1),
           Var_Types,
           Functions,
           Type_Env,
           Const_Env,
           High_Value)
      then
         if High_Value < Low_Value then
            return False;
         end if;
         Width := High_Value - Low_Value + 1;
         if Width < 0 or else Width > CM.Wide_Integer (Natural'Last) then
            return False;
         end if;
         Length := Natural (Width);
         return True;
      elsif Expr.Kind = CM.Expr_Apply
        and then Expr.Callee /= null
        and then Expr.Callee.Kind in CM.Expr_Ident | CM.Expr_Select
        and then Natural (Expr.Args.Length) = 2
        and then Try_Static_Integerish_Value
          (Expr.Args (Expr.Args.First_Index),
           Var_Types,
           Functions,
           Type_Env,
           Const_Env,
           Low_Value)
        and then Try_Static_Integerish_Value
          (Expr.Args (Expr.Args.First_Index + 1),
           Var_Types,
           Functions,
           Type_Env,
           Const_Env,
           High_Value)
      then
         if High_Value < Low_Value then
            return False;
         end if;
         Width := High_Value - Low_Value + 1;
         if Width < 0 or else Width > CM.Wide_Integer (Natural'Last) then
            return False;
         end if;
         Length := Natural (Width);
         return True;
      end if;
      return False;
   end Static_Growable_Length;

   function Static_Growable_To_Fixed_Narrowing_OK
     (Source_Expr : CM.Expr_Access;
      Target      : GM.Type_Descriptor;
      Var_Types   : Type_Maps.Map;
      Functions   : Function_Maps.Map;
      Type_Env    : Type_Maps.Map;
      Const_Env   : Static_Value_Maps.Map;
      Exact_Length_Facts : Exact_Length_Maps.Map) return Boolean
   is
      Target_Base       : constant GM.Type_Descriptor := Base_Type (Target, Type_Env);
      Target_Length     : Natural := 0;
      Source_Length     : Natural := 0;
      Target_Component  : GM.Type_Descriptor;
      Source_Component  : GM.Type_Descriptor;
   begin
      if Source_Expr = null
        or else FT.Lowercase (UString_Value (Target_Base.Kind)) /= "array"
        or else Target_Base.Growable
        or else not Target_Base.Has_Component_Type
        or else not Fixed_Array_Cardinality (Target_Base, Type_Env, Target_Length)
      then
         return False;
      end if;

      Target_Component :=
        Resolve_Type
          (UString_Value (Target_Base.Component_Type),
           Type_Env,
           "",
           FT.Null_Span);

      if Source_Expr.Kind = CM.Expr_Array_Literal then
         if Source_Expr.Elements.Is_Empty then
            return False;
         end if;
         Source_Length := Natural (Source_Expr.Elements.Length);
         Source_Component :=
           Expr_Type
             (Source_Expr.Elements (Source_Expr.Elements.First_Index),
              Var_Types,
              Functions,
              Type_Env);
         return Source_Length = Target_Length
           and then Compatible_Type (Source_Component, Target_Component, Type_Env);
      elsif Source_Expr.Kind in CM.Expr_Resolved_Index | CM.Expr_Apply
        and then
          ((Source_Expr.Kind = CM.Expr_Resolved_Index
            and then Source_Expr.Prefix /= null
            and then Source_Expr.Prefix.Kind in CM.Expr_Ident | CM.Expr_Select)
           or else
           (Source_Expr.Kind = CM.Expr_Apply
            and then Source_Expr.Callee /= null
            and then Source_Expr.Callee.Kind in CM.Expr_Ident | CM.Expr_Select))
        and then Static_Growable_Length
          (Source_Expr,
           Var_Types,
           Functions,
           Type_Env,
           Const_Env,
           Source_Length)
      then
         declare
            Prefix_Expr : constant CM.Expr_Access :=
              (if Source_Expr.Kind = CM.Expr_Resolved_Index
               then Source_Expr.Prefix
               else Source_Expr.Callee);
            Prefix_Base : constant GM.Type_Descriptor :=
              Base_Type
                (Expr_Type
                   (Prefix_Expr,
                    Var_Types,
                    Functions,
                    Type_Env),
                 Type_Env);
         begin
            if FT.Lowercase (UString_Value (Prefix_Base.Kind)) /= "array"
              or else not Prefix_Base.Growable
              or else not Prefix_Base.Has_Component_Type
            then
               return False;
            end if;

            Source_Component :=
              Resolve_Type
                (UString_Value (Prefix_Base.Component_Type),
                 Type_Env,
                 "",
                 FT.Null_Span);
            return Source_Length = Target_Length
              and then Compatible_Type (Source_Component, Target_Component, Type_Env);
         end;
      elsif Source_Expr.Kind in CM.Expr_Ident | CM.Expr_Select then
         declare
            Source_Name : constant String := Exact_Length_Fact_Name (Source_Expr);
         begin
            if Source_Name = ""
              or else not Exact_Length_Facts.Contains (Canonical_Name (Source_Name))
            then
               return False;
            end if;

            declare
               Source_Base : constant GM.Type_Descriptor :=
                 Base_Type
                   (Expr_Type (Source_Expr, Var_Types, Functions, Type_Env),
                    Type_Env);
            begin
               if FT.Lowercase (UString_Value (Source_Base.Kind)) /= "array"
                 or else not Source_Base.Growable
                 or else not Source_Base.Has_Component_Type
               then
                  return False;
               end if;

               Source_Length := Exact_Length_Facts.Element (Canonical_Name (Source_Name));
               Source_Component :=
                 Resolve_Type
                   (UString_Value (Source_Base.Component_Type),
                    Type_Env,
                    "",
                    FT.Null_Span);
               return Source_Length = Target_Length
                 and then Compatible_Type (Source_Component, Target_Component, Type_Env);
            end;
         end;
      end if;

      return False;
   end Static_Growable_To_Fixed_Narrowing_OK;

   function Compatible_Source_To_Target_Type
     (Source   : GM.Type_Descriptor;
      Target   : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return Boolean
   is
      Source_Base : constant GM.Type_Descriptor := Base_Type (Source, Type_Env);
      Target_Base : constant GM.Type_Descriptor := Base_Type (Target, Type_Env);
   begin
      if FT.Lowercase (UString_Value (Source_Base.Kind)) = "array"
        and then FT.Lowercase (UString_Value (Target_Base.Kind)) = "array"
        and then Source_Base.Has_Component_Type
        and then Target_Base.Has_Component_Type
      then
         declare
            Source_Component : constant GM.Type_Descriptor :=
              Resolve_Type
                (UString_Value (Source_Base.Component_Type),
                 Type_Env,
                 "",
                 FT.Null_Span);
            Target_Component : constant GM.Type_Descriptor :=
              Resolve_Type
                (UString_Value (Target_Base.Component_Type),
                 Type_Env,
                 "",
                 FT.Null_Span);
         begin
            if not Compatible_Type (Source_Component, Target_Component, Type_Env) then
               return False;
            end if;

            if not Source_Base.Growable and then not Target_Base.Growable then
               return Equivalent_Type (Source, Target, Type_Env);
            elsif (not Source_Base.Growable) and then Target_Base.Growable then
               return True;
            elsif Source_Base.Growable and then not Target_Base.Growable then
               return False;
            end if;

            return True;
         end;
      elsif Compatible_Type (Source, Target, Type_Env) then
         return True;
      end if;
      return False;
   end Compatible_Source_To_Target_Type;

   function Compatible_Source_Expr_To_Target_Type
     (Source_Expr : CM.Expr_Access;
      Source      : GM.Type_Descriptor;
      Target      : GM.Type_Descriptor;
      Var_Types   : Type_Maps.Map;
      Functions   : Function_Maps.Map;
      Type_Env    : Type_Maps.Map;
      Const_Env   : Static_Value_Maps.Map;
      Exact_Length_Facts : Exact_Length_Maps.Map) return Boolean
   is
   begin
      if Static_Growable_To_Fixed_Narrowing_OK
        (Source_Expr,
         Target,
         Var_Types,
         Functions,
         Type_Env,
         Const_Env,
         Exact_Length_Facts)
      then
         return True;
      end if;

      if Compatible_Source_To_Target_Type (Source, Target, Type_Env) then
         return True;
      end if;
      return False;
   end Compatible_Source_Expr_To_Target_Type;

   procedure Validate_Static_Binary_Boundaries
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Const_Env : Static_Value_Maps.Map;
      Path      : String)
   is
      Left_Type   : GM.Type_Descriptor;
      Target_Type : GM.Type_Descriptor;
      Static_Int  : CM.Wide_Integer := 0;
      Static_Value : CM.Static_Value;
   begin
      if Expr = null then
         return;
      end if;

      case Expr.Kind is
         when CM.Expr_Binary =>
            Validate_Static_Binary_Boundaries
              (Expr.Left, Var_Types, Functions, Type_Env, Const_Env, Path);
            Validate_Static_Binary_Boundaries
              (Expr.Right, Var_Types, Functions, Type_Env, Const_Env, Path);

            if FT.To_String (Expr.Operator) in "<<" | ">>" then
               Left_Type := Expr_Type (Expr.Left, Var_Types, Functions, Type_Env);
               if Is_Binary_Type (Left_Type, Type_Env)
                 and then Try_Static_Integerish_Value
                   (Expr.Right, Var_Types, Functions, Type_Env, Const_Env, Static_Int)
                 and then (Static_Int < 0
                           or else Static_Int >= CM.Wide_Integer (Binary_Bit_Width (Left_Type, Type_Env)))
               then
                  Raise_Diag
                    (CM.Source_Frontend_Error
                       (Path    => Path,
                        Span    => Expr.Right.Span,
                        Message => "shift count is not provably within operand width"));
               end if;
            end if;

         when CM.Expr_Conversion | CM.Expr_Annotated =>
            Validate_Static_Binary_Boundaries
              (Expr.Inner, Var_Types, Functions, Type_Env, Const_Env, Path);

            if Expr.Target /= null then
               Target_Type := Resolve_Target_Type (Expr.Target, Type_Env);
               if Is_Integerish (Target_Type, Type_Env)
                 and then not Is_Binary_Type (Target_Type, Type_Env)
                 and then not Is_Boolean_Type (Target_Type, Type_Env)
                 and then Is_Binary_Type
                   (Expr_Type (Expr.Inner, Var_Types, Functions, Type_Env), Type_Env)
                 and then Try_Static_Integerish_Value
                   (Expr.Inner, Var_Types, Functions, Type_Env, Const_Env, Static_Int)
               then
                  Static_Value.Kind := CM.Static_Value_Integer;
                  Static_Value.Int_Value := Static_Int;
                  if not Scalar_Value_Compatible (Static_Value, Target_Type, Type_Env) then
                     Raise_Diag
                       (CM.Source_Frontend_Error
                          (Path    => Path,
                           Span    => Expr.Span,
                           Message => "explicit conversion is not provably within target range"));
                  end if;
               end if;
            end if;

         when CM.Expr_Unary =>
            Validate_Static_Binary_Boundaries
              (Expr.Inner, Var_Types, Functions, Type_Env, Const_Env, Path);
         when CM.Expr_Select =>
            Validate_Static_Binary_Boundaries
              (Expr.Prefix, Var_Types, Functions, Type_Env, Const_Env, Path);
         when CM.Expr_Resolved_Index =>
            Validate_Static_Binary_Boundaries
              (Expr.Prefix, Var_Types, Functions, Type_Env, Const_Env, Path);
            for Item of Expr.Args loop
               Validate_Static_Binary_Boundaries
                 (Item, Var_Types, Functions, Type_Env, Const_Env, Path);
            end loop;
         when CM.Expr_Call =>
            Validate_Static_Binary_Boundaries
              (Expr.Callee, Var_Types, Functions, Type_Env, Const_Env, Path);
            for Item of Expr.Args loop
               Validate_Static_Binary_Boundaries
                 (Item, Var_Types, Functions, Type_Env, Const_Env, Path);
            end loop;
         when CM.Expr_Allocator =>
            Validate_Static_Binary_Boundaries
              (Expr.Value, Var_Types, Functions, Type_Env, Const_Env, Path);
         when CM.Expr_Aggregate =>
            for Item of Expr.Fields loop
               Validate_Static_Binary_Boundaries
                 (Item.Expr, Var_Types, Functions, Type_Env, Const_Env, Path);
            end loop;
         when CM.Expr_Tuple =>
            for Item of Expr.Elements loop
               Validate_Static_Binary_Boundaries
                 (Item, Var_Types, Functions, Type_Env, Const_Env, Path);
            end loop;
         when others =>
            null;
      end case;
   end Validate_Static_Binary_Boundaries;

   function Is_Assignable_Target
     (Expr : CM.Expr_Access) return Boolean is
      Shared : Shared_Object_Ref;
   begin
      if Expr = null then
         return False;
      elsif Expr.Kind = CM.Expr_Ident then
         return True;
      elsif Expr.Kind = CM.Expr_Resolved_Index then
         return True;
      elsif Expr.Kind = CM.Expr_Enum_Literal then
         return True;
      elsif Expr.Kind = CM.Expr_Subtype_Indication then
         return False;
      elsif Expr.Kind = CM.Expr_Conversion then
         return False;
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
      elsif Try_Shared_Target_Expr (Expr, Shared) then
         return False;
      elsif Expr.Kind = CM.Expr_Select then
         return UString_Value (Expr.Selector) not in "first" | "last" | "length" | "access";
      end if;
      return False;
   end Is_Assignable_Target;

   procedure Validate_Mut_Call_Arguments
     (Expr      : CM.Expr_Access;
      Functions : Function_Maps.Map;
      Path      : String)
   is
      Name     : constant String :=
        (if Expr = null or else Expr.Callee = null then "" else Flatten_Name (Expr.Callee));
      Info     : Function_Info;
      Has_Info : Boolean := False;
   begin
      if Expr = null or else Expr.Kind /= CM.Expr_Call or else Name = "" then
         return;
      end if;

      if Has_Function (Functions, Name) then
         Info := Get_Function (Functions, Name);
         Has_Info := True;
      elsif Current_Generic_Function_Templates.Contains (Canonical_Name (Name)) then
         Info := Current_Generic_Function_Templates.Element (Canonical_Name (Name)).Info;
         Has_Info := True;
      end if;

      if not Has_Info or else Natural (Expr.Args.Length) /= Natural (Info.Params.Length) then
         return;
      end if;

      for Index in Info.Params.First_Index .. Info.Params.Last_Index loop
         if UString_Value (Info.Params (Index).Mode) = "mut"
           and then not Is_Assignable_Target (Expr.Args (Index))
         then
            Raise_Diag
              (CM.Source_Frontend_Error
                 (Path    => Path,
                  Span    => Expr.Args (Index).Span,
                  Message =>
                    "argument for `mut` parameter `"
                    & UString_Value (Info.Params (Index).Name)
                    & "` must be a writable name"));
         end if;
      end loop;
   end Validate_Mut_Call_Arguments;

   function Resolve_Decl_Type
     (Decl      : CM.Object_Decl;
      Type_Env  : Type_Maps.Map;
      Const_Env : Static_Value_Maps.Map;
      Path      : String) return GM.Type_Descriptor
   is
      Result : GM.Type_Descriptor;
   begin
      if Decl.Is_Constant and then not Decl.Has_Initializer then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path,
               Span    => Decl.Span,
               Message => "constant declarations require initializers"));
      end if;
      if Decl.Decl_Type.Kind = CM.Type_Spec_Unknown
        and then UString_Value (Decl.Type_Info.Name)'Length > 0
      then
         Result := Decl.Type_Info;
      else
         Result := Resolve_Type_Spec (Decl.Decl_Type, Type_Env, Const_Env, Path);
      end if;
      if Is_Interface_Type (Result, Type_Env) then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path,
               Span    => Decl.Span,
               Message => "interface types are only admitted in parameter positions in PR11.11b"));
      end if;
      Result := Canonicalize_Imported_Synthetic_Type (Result, Type_Env);
      return Result;
   end Resolve_Decl_Type;

   function Normalize_Procedure_Call
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Const_Env : Static_Value_Maps.Map;
      Path      : String;
      Allow_Try : Boolean := False) return CM.Expr_Access
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
         Result := new CM.Expr_Node'(Expr.all);
         if Expr.Callee /= null then
            Result.Callee :=
              Normalize_Expr
                (Expr.Callee,
                 Var_Types,
                 Functions,
                 Type_Env,
                 Const_Env);
         end if;
         if not Expr.Args.Is_Empty then
            Result.Args.Clear;
            for Arg of Expr.Args loop
               Result.Args.Append
                 (Normalize_Expr_Checked
                    (Arg,
                     Var_Types,
                     Functions,
                     Type_Env,
                     Const_Env,
                     Path,
                     Allow_Try => Allow_Try));
            end loop;
         end if;
         Name := FT.To_UString (Flatten_Name (Result.Callee));
         if Has_Function (Functions, UString_Value (Name))
           and then not Get_Function (Functions, UString_Value (Name)).Has_Return_Type
         then
            Validate_Print_Procedure_Call (Result, Var_Types, Functions, Type_Env, Path);
            return Result;
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
            Validate_Print_Procedure_Call (Result, Var_Types, Functions, Type_Env, Path);
            return Set_Type (Result, Default_Integer);
         end if;
      end if;

      if Expr.Kind = CM.Expr_Call
        and then Expr.Callee /= null
      then
         declare
            Shared_Result   : Shared_Object_Ref;
            Shared_Root     : FT.UString := FT.To_UString ("");
            Shared_Root_Type : GM.Type_Descriptor;
            Selector_Name   : constant String :=
              (if Expr.Callee.Kind = CM.Expr_Select
               then Canonical_Name (UString_Value (Expr.Callee.Selector))
               else Canonical_Name (UString_Value (Expr.Callee.Name)));
            Shared_Operation : FT.UString := FT.To_UString ("");
            Has_Shared_Call : Boolean := False;
         begin
            if Expr.Callee.Kind = CM.Expr_Select
              and then Try_Shared_Wrapper_Root_Name_Expr
                (Expr.Callee.Prefix,
                 Shared_Root,
                 Shared_Root_Type)
            then
               Has_Shared_Call := True;
               if Selector_Name = Canonical_Name (Shared_Pop_Last_Name) then
                  Shared_Operation := FT.To_UString (Shared_Pop_Last_Name);
               elsif Selector_Name = Canonical_Name (Shared_Remove_Name) then
                  Shared_Operation := FT.To_UString (Shared_Remove_Name);
               end if;
            elsif Try_Shared_Public_Helper_Call
              (Expr.Callee,
               Shared_Pop_Last_Name,
               Shared_Result)
            then
               Has_Shared_Call := True;
               Shared_Operation := FT.To_UString (Shared_Pop_Last_Name);
            elsif Try_Shared_Public_Helper_Call
              (Expr.Callee,
               Shared_Remove_Name,
               Shared_Result)
            then
               Has_Shared_Call := True;
               Shared_Operation := FT.To_UString (Shared_Remove_Name);
            end if;

            if Has_Shared_Call
              and then UString_Value (Shared_Operation) /= ""
            then
               return Expr;
            end if;
         end;
      end if;

      Raise_Diag
        (CM.Source_Frontend_Error
           (Path    => Path,
            Span    => Expr.Span,
            Message => "expected assignment or call to a no-result function"));
      return Expr;
   end Normalize_Procedure_Call;

   function Normalize_Procedure_Call_Checked
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Const_Env : Static_Value_Maps.Map;
      Path      : String;
      Allow_Try : Boolean := False) return CM.Expr_Access
   is
      Result : constant CM.Expr_Access :=
        Normalize_Expr (Expr, Var_Types, Functions, Type_Env, Const_Env, Path);
   begin
      Validate_Pr112_Expr_Boundaries (Result, Var_Types, Functions, Type_Env, Path);
      Validate_Print_Call_Context
        (Result,
         Var_Types,
         Functions,
         Type_Env,
         Path,
         Allow_Root_Print => True);
      if not Allow_Try then
         Reject_Non_Executable_Try (Result, Path);
      end if;
      return
        Normalize_Procedure_Call
          (Result,
           Var_Types,
           Functions,
           Type_Env,
           Const_Env,
           Path,
           Allow_Try => Allow_Try);
   end Normalize_Procedure_Call_Checked;

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

   procedure Append_Task_Channel_Contract
     (Contracts   : in out FT.UString_Vectors.Vector;
      Expr        : CM.Expr_Access;
      Channel_Env : Type_Maps.Map;
      Path        : String;
      Direction   : String)
   is
      Name : constant String := Flatten_Name (Expr);
   begin
      if Name = "" then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path,
               Span    => (if Expr = null then FT.Null_Span else Expr.Span),
               Message => "task `" & Direction & "` clauses must name channels"));
      elsif not Has_Type (Channel_Env, Name) then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path,
               Span    => Expr.Span,
               Message => "unknown channel `" & Name & "` in task `" & Direction & "` clause"));
      end if;

      for Existing of Contracts loop
         if UString_Value (Existing) = Name then
            Raise_Diag
              (CM.Source_Frontend_Error
                 (Path    => Path,
                  Span    => Expr.Span,
                  Message => "duplicate channel `" & Name & "` in task `" & Direction & "` clause"));
         end if;
      end loop;

      Contracts.Append (FT.To_UString (Name));
   end Append_Task_Channel_Contract;

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
        or else Has_Function (Functions, Type_Name);
   end Looks_Like_Unsupported_Statement_Label;

   function Normalize_Object_Decl
     (Decl      : CM.Object_Decl;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Const_Env : Static_Value_Maps.Map;
      Exact_Length_Facts : Exact_Length_Maps.Map;
      Path      : String) return CM.Object_Decl
   is
      Result : CM.Object_Decl := Decl;
      Static_Slice_Narrowing_OK : Boolean := False;
   begin
      if Looks_Like_Unsupported_Statement_Label (Decl, Var_Types, Functions, Type_Env) then
         Raise_Diag
           (CM.Unsupported_Source_Construct
              (Path    => Path,
               Span    => Decl.Span,
               Message => "named statement labels are outside the current PR08.1 concurrency subset"));
      end if;

      Result.Type_Info := Resolve_Decl_Type (Decl, Type_Env, Const_Env, Path);
      Result.Is_Public := Decl.Is_Public;
      Result.Is_Shared := Decl.Is_Shared;
      Result.Has_Implicit_Default_Init := Decl.Has_Implicit_Default_Init;
      Result.Is_Constant := Decl.Is_Constant;
      if Result.Is_Shared then
         declare
         begin
            if Natural (Decl.Names.Length) /= 1 then
               Raise_Diag
                 (CM.Unsupported_Source_Construct
                    (Path    => Path,
                     Span    => Decl.Span,
                     Message =>
                       "`shared` declarations are limited to a single name in PR11.12e"));
            elsif Decl.Is_Constant then
               Raise_Diag
                 (CM.Unsupported_Source_Construct
                    (Path    => Path,
                     Span    => Decl.Span,
                     Message =>
                       "`shared` declarations cannot be constant in PR11.12e"));
            elsif not Is_Shared_Root_Type_Allowed (Result.Type_Info, Type_Env)
            then
               Raise_Diag
                (CM.Unsupported_Source_Construct
                   (Path    => Path,
                    Span    => Decl.Span,
                    Message =>
                       "`shared` declarations require plain non-discriminated record types or built-in container roots in PR11.12e"));
            end if;
         end;
      end if;
      if Decl.Has_Initializer and then Decl.Initializer /= null then
         if Decl.Initializer.Kind = CM.Expr_Apply
           and then Decl.Initializer.Callee /= null
           and then Decl.Initializer.Callee.Kind in CM.Expr_Ident | CM.Expr_Select
         then
            declare
               Target_Base   : constant GM.Type_Descriptor :=
                 Base_Type (Result.Type_Info, Type_Env);
               Callee_Name   : constant String := Flatten_Name (Decl.Initializer.Callee);
               Prefix_Base   : constant GM.Type_Descriptor :=
                 (if Has_Type (Var_Types, Callee_Name)
                  then Base_Type (Get_Type (Var_Types, Callee_Name), Type_Env)
                  else (others => <>));
               Target_Length : Natural := 0;
               Source_Length : Natural := 0;
            begin
               if FT.Lowercase (UString_Value (Target_Base.Kind)) = "array"
                 and then not Target_Base.Growable
                 and then FT.Lowercase (UString_Value (Prefix_Base.Kind)) = "array"
                 and then Prefix_Base.Growable
                 and then Fixed_Array_Cardinality (Target_Base, Type_Env, Target_Length)
                 and then Static_Growable_Length
                   (Decl.Initializer,
                    Var_Types,
                    Functions,
                    Type_Env,
                    Const_Env,
                    Source_Length)
                 and then Source_Length = Target_Length
               then
                  Static_Slice_Narrowing_OK := True;
               end if;
            end;
         end if;
         Result.Initializer :=
           Normalize_Expr_Checked
             (Decl.Initializer, Var_Types, Functions, Type_Env, Const_Env, Path);
         Result.Initializer :=
           Contextualize_Expr_To_Target_Type
             (Result.Initializer,
              Result.Type_Info,
              Var_Types,
              Functions,
              Type_Env,
              Path);
         Reject_Uncontextualized_None (Result.Initializer, Path);
         if Result.Initializer.Kind in CM.Expr_Aggregate | CM.Expr_Tuple | CM.Expr_Array_Literal then
            Result.Initializer.Type_Name := Result.Type_Info.Name;
         end if;
         Validate_Static_Binary_Boundaries
           (Result.Initializer, Var_Types, Functions, Type_Env, Const_Env, Path);
         if Result.Initializer.Kind = CM.Expr_Resolved_Index
           and then Result.Initializer.Prefix /= null
         then
            declare
               Target_Base   : constant GM.Type_Descriptor :=
                 Base_Type (Result.Type_Info, Type_Env);
               Prefix_Base   : constant GM.Type_Descriptor :=
                 Base_Type
                   (Expr_Type
                      (Result.Initializer.Prefix,
                       Var_Types,
                       Functions,
                       Type_Env),
                    Type_Env);
               Target_Length : Natural := 0;
               Source_Length : Natural := 0;
            begin
               if FT.Lowercase (UString_Value (Target_Base.Kind)) = "array"
                 and then not Target_Base.Growable
                 and then FT.Lowercase (UString_Value (Prefix_Base.Kind)) = "array"
                 and then Prefix_Base.Growable
                 and then Fixed_Array_Cardinality (Target_Base, Type_Env, Target_Length)
                 and then Static_Growable_Length
                   (Result.Initializer,
                    Var_Types,
                    Functions,
                    Type_Env,
                    Const_Env,
                    Source_Length)
                 and then Source_Length = Target_Length
               then
                  Result.Initializer.Type_Name := Result.Type_Info.Name;
                  Static_Slice_Narrowing_OK := True;
               end if;
            end;
         end if;
         if Static_Growable_To_Fixed_Narrowing_OK
           (Result.Initializer,
            Result.Type_Info,
            Var_Types,
            Functions,
            Type_Env,
            Const_Env,
            Exact_Length_Facts)
         then
            Result.Initializer.Type_Name := Result.Type_Info.Name;
            Static_Slice_Narrowing_OK := True;
         elsif Static_Slice_Narrowing_OK then
            Result.Initializer.Type_Name := Result.Type_Info.Name;
         end if;
         Reject_Static_Bounded_String_Overflow
           (Result.Initializer,
            Result.Type_Info,
            Type_Env,
            Path,
            Result.Initializer.Span);
         if not Static_Slice_Narrowing_OK
           and then not Compatible_Source_Expr_To_Target_Type
             (Result.Initializer,
              Expr_Type (Result.Initializer, Var_Types, Functions, Type_Env),
              Result.Type_Info,
              Var_Types,
              Functions,
              Type_Env,
              Const_Env,
              Exact_Length_Facts)
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
      Const_Env        : Static_Value_Maps.Map;
      Path             : String;
      Message          : String) is
      Name      : constant String := Root_Name (Expr);
      Flat_Name : constant String := Flatten_Name (Expr);
   begin
      if Expr /= null and then Expr.Kind = CM.Expr_Tuple then
         for Item of Expr.Elements loop
            Ensure_Writable_Target
              (Item,
               Imported_Objects,
               Local_Constants,
               Const_Env,
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
      elsif Flat_Name'Length > 0 and then Has_Enum_Literal (Const_Env, Flat_Name) then
         Raise_Diag
           (CM.Write_To_Constant
              (Path    => Path,
               Span    => (if Expr = null then FT.Null_Span else Expr.Span),
               Message =>
                 "assignment target rooted in enum literal `"
                 & Flat_Name
                 & "` is not writable"));
      end if;
   end Ensure_Writable_Target;

   Synthetic_Name_Counter : Natural := 0;

   type Desugared_Expr_Result is record
      Expr     : CM.Expr_Access := null;
      Preludes : CM.Statement_Access_Vectors.Vector;
   end record;

   function Next_Synthetic_Name (Prefix : String) return String is
   begin
      Synthetic_Name_Counter := Synthetic_Name_Counter + 1;
      return Prefix & "_" & Ada.Strings.Fixed.Trim (Natural'Image (Synthetic_Name_Counter), Ada.Strings.Both);
   end Next_Synthetic_Name;

   function Named_Type_Spec
     (Info : GM.Type_Descriptor;
      Span : FT.Source_Span) return CM.Type_Spec
   is
      Result : CM.Type_Spec;
   begin
      Result.Kind := CM.Type_Spec_Name;
      Result.Name := Info.Name;
      Result.Span := Span;
      return Result;
   end Named_Type_Spec;

   function Has_Interface_Params
     (Info     : Function_Info;
      Type_Env : Type_Maps.Map) return Boolean is
   begin
      for Param of Info.Params loop
         if Is_Interface_Type (Param.Type_Info, Type_Env) then
            return True;
         end if;
      end loop;
      return False;
   end Has_Interface_Params;

   function Specialize_Interface_Call
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Const_Env : Static_Value_Maps.Map;
      Path      : String) return CM.Expr_Access
   is
      Callee_Name : constant String :=
        (if Expr = null or else Expr.Callee = null then "" else Flatten_Name (Expr.Callee));
      Template    : Interface_Template_Info;
      Clone       : CM.Subprogram_Body;
      Result      : CM.Expr_Access := Expr;
      Key         : FT.UString := FT.To_UString (Canonical_Name (Callee_Name));
      Arg_Index    : Positive := 1;
      Specialized_Name : FT.UString := FT.To_UString ("");
      Clone_Info   : Function_Info;
      Replacement  : GM.Type_Descriptor;
      Arg          : CM.Expr_Access;
      Arg_Type     : GM.Type_Descriptor;
   begin
      if Callee_Name = ""
        or else not Current_Interface_Templates.Contains (Canonical_Name (Callee_Name))
      then
         return Expr;
      end if;

      Template := Current_Interface_Templates.Element (Canonical_Name (Callee_Name));
      if Natural (Expr.Args.Length) /= Natural (Template.Info.Params.Length) then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path,
               Span    => (if Expr.Has_Call_Span then Expr.Call_Span else Expr.Span),
               Message =>
                 "call to `" & Callee_Name & "` expects "
                 & Ada.Strings.Fixed.Trim (Natural'Image (Natural (Template.Info.Params.Length)), Ada.Strings.Both)
                 & " arguments"));
      end if;

      Clone := Template.Decl;

      if Clone.Spec.Has_Receiver then
         Arg := Expr.Args (Arg_Index);
         Replacement :=
           Resolve_Type_Spec (Clone.Spec.Receiver.Param_Type, Type_Env, Const_Env, Path);
         if Is_Interface_Type (Replacement, Type_Env) then
            Arg_Type := Expr_Type (Arg, Var_Types, Functions, Type_Env);
            if Is_Interface_Type (Arg_Type, Type_Env) then
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path,
                     Span    => Arg.Span,
                     Message => "interface-constrained calls require concrete receiver types"));
            elsif not Type_Satisfies_Interface (Arg_Type, Replacement, Functions, Type_Env) then
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path,
                     Span    => Arg.Span,
                     Message =>
                       "receiver type `" & UString_Value (Base_Type (Arg_Type, Type_Env).Name)
                       & "` does not satisfy interface `"
                       & UString_Value (Base_Type (Replacement, Type_Env).Name) & "`"));
            end if;
            Clone.Spec.Receiver.Param_Type := Named_Type_Spec (Arg_Type, Clone.Spec.Receiver.Param_Type.Span);
            Key := Key & FT.To_UString ("|") & Arg_Type.Name;
         end if;
         Arg_Index := Arg_Index + 1;
      end if;

      if not Clone.Spec.Params.Is_Empty then
         for Index in Clone.Spec.Params.First_Index .. Clone.Spec.Params.Last_Index loop
            declare
               Param_Group : CM.Parameter_Spec := Clone.Spec.Params (Index);
               Param_Type  : constant GM.Type_Descriptor :=
                 Resolve_Type_Spec (Param_Group.Param_Type, Type_Env, Const_Env, Path);
            begin
               if Is_Interface_Type (Param_Type, Type_Env) then
                  if Natural (Param_Group.Names.Length) /= 1 then
                     Raise_Diag
                       (CM.Source_Frontend_Error
                          (Path    => Path,
                           Span    => Param_Group.Span,
                           Message => "interface-typed parameters must declare exactly one name in PR11.11b"));
                  end if;
                  Arg := Expr.Args (Arg_Index);
                  Arg_Type := Expr_Type (Arg, Var_Types, Functions, Type_Env);
                  if Is_Interface_Type (Arg_Type, Type_Env) then
                     Raise_Diag
                       (CM.Source_Frontend_Error
                          (Path    => Path,
                           Span    => Arg.Span,
                           Message => "interface-constrained calls require concrete argument types"));
                  elsif not Type_Satisfies_Interface (Arg_Type, Param_Type, Functions, Type_Env) then
                     Raise_Diag
                       (CM.Source_Frontend_Error
                          (Path    => Path,
                           Span    => Arg.Span,
                           Message =>
                             "argument type `" & UString_Value (Base_Type (Arg_Type, Type_Env).Name)
                             & "` does not satisfy interface `"
                             & UString_Value (Base_Type (Param_Type, Type_Env).Name) & "`"));
                  end if;
                  Param_Group.Param_Type := Named_Type_Spec (Arg_Type, Param_Group.Param_Type.Span);
                  Clone.Spec.Params.Replace_Element (Index, Param_Group);
                  Key := Key & FT.To_UString ("|") & Arg_Type.Name;
               end if;
               Arg_Index := Arg_Index + Natural (Param_Group.Names.Length);
            end;
         end loop;
      end if;

      if Current_Interface_Specialization_By_Key.Contains (UString_Value (Key)) then
         Specialized_Name :=
           FT.To_UString
             (Current_Interface_Specialization_By_Key.Element (UString_Value (Key)));
      else
         Specialized_Name :=
           FT.To_UString
             (Next_Synthetic_Name
                ("Safe_Interface_" & Sanitize_Type_Name_Component (Method_Target_Tail_Name (Callee_Name))));
         Clone.Spec.Name := Specialized_Name;
         Clone.Is_Public := False;
         Clone_Info :=
           Register_Function (Clone, Type_Env, Const_Env, Path);
         Put_Function (Current_Synthetic_Functions, UString_Value (Specialized_Name), Clone_Info);
         Current_Interface_Specialization_By_Key.Include
           (UString_Value (Key), UString_Value (Specialized_Name));
         Current_Pending_Interface_Specializations.Include
           (Canonical_Name (UString_Value (Specialized_Name)),
            (Decl => Clone, Info => Clone_Info));
         Append_Unique_String
           (Current_Interface_Specialization_Order,
            UString_Value (Specialized_Name));
      end if;

      Result := new CM.Expr_Node'(Expr.all);
      Result.Callee :=
        Name_Expr_From_String (UString_Value (Specialized_Name), Expr.Callee.Span);
      return Result;
   end Specialize_Interface_Call;

   function Specialize_Generic_Call
     (Expr      : CM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Const_Env : Static_Value_Maps.Map;
      Path      : String) return CM.Expr_Access
   is
      Callee_Name : constant String :=
        (if Expr = null or else Expr.Callee = null then "" else Flatten_Name (Expr.Callee));
      Generic_Args : constant CM.Type_Spec_Access_Vectors.Vector :=
        (if Expr = null or else Expr.Callee = null
         then CM.Type_Spec_Access_Vectors.Empty_Vector
         else Expr.Callee.Generic_Args);
      Template    : Generic_Function_Template_Info;
      Template_Name : FT.UString := FT.To_UString ("");
      Actual_Type_Names : FT.UString_Vectors.Vector;
      Key         : FT.UString := FT.To_UString ("");
      Specialized_Name : FT.UString := FT.To_UString ("");
      Clone       : CM.Subprogram_Body;
      Clone_Info  : Function_Info;
      Local_Type_Env : Type_Maps.Map := Type_Env;
      Result      : CM.Expr_Access := Expr;
   begin
      if Callee_Name = ""
        or else Generic_Args.Is_Empty
        or else not Current_Generic_Function_Templates.Contains (Canonical_Name (Callee_Name))
      then
         return Expr;
      end if;

      Template := Current_Generic_Function_Templates.Element (Canonical_Name (Callee_Name));
      Template_Name := Template.Info.Name;
      for Arg of Generic_Args loop
         Actual_Type_Names.Append
           (Resolve_Type_Spec (Arg.all, Type_Env, Const_Env, Path).Name);
      end loop;

      Validate_Generic_Actuals
        (Template.Decl.Spec.Generic_Formals,
         Actual_Type_Names,
         Functions,
         Type_Env,
         Path,
         (if Expr.Has_Call_Span then Expr.Call_Span else Expr.Span));

      if Natural (Expr.Args.Length) /= Natural (Template.Info.Params.Length) then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path,
               Span    => (if Expr.Has_Call_Span then Expr.Call_Span else Expr.Span),
               Message =>
                 "call to `" & Callee_Name & "` expects "
                 & Ada.Strings.Fixed.Trim
                     (Natural'Image (Natural (Template.Info.Params.Length)),
                      Ada.Strings.Both)
                 & " arguments"));
      end if;

      Key := FT.To_UString (Generic_Template_Key (UString_Value (Template_Name), Actual_Type_Names));
      if Current_Generic_Specialization_By_Key.Contains (UString_Value (Key)) then
         Specialized_Name :=
           FT.To_UString
             (Current_Generic_Specialization_By_Key.Element (UString_Value (Key)));
      else
         Clone := Template.Decl;
         Clone.Spec.Generic_Formals.Clear;
         Specialized_Name :=
           FT.To_UString
             (Generic_Specialization_Name
                ("Safe_Generic_",
                 UString_Value (Template_Name),
                 Actual_Type_Names));
         Clone.Spec.Name := Specialized_Name;
         Clone.Is_Public := False;

         if not Template.Decl.Spec.Generic_Formals.Is_Empty then
            for Index in Template.Decl.Spec.Generic_Formals.First_Index .. Template.Decl.Spec.Generic_Formals.Last_Index loop
               Put_Type
                 (Local_Type_Env,
                  UString_Value (Template.Decl.Spec.Generic_Formals (Index).Name),
                  Resolve_Type
                    (UString_Value (Actual_Type_Names (Index)),
                     Type_Env,
                     Path,
                     Expr.Span));
            end loop;
         end if;

         Clone_Info := Register_Function (Clone, Local_Type_Env, Const_Env, Path);
         Put_Function
           (Current_Synthetic_Functions,
            UString_Value (Specialized_Name),
            Clone_Info);
         Current_Generic_Specialization_By_Key.Include
           (UString_Value (Key),
            UString_Value (Specialized_Name));
         Current_Pending_Generic_Specializations.Include
           (Canonical_Name (UString_Value (Specialized_Name)),
            (Decl              => Clone,
             Info              => Clone_Info,
             Origin_Package    => Template.Origin_Package,
             Actual_Type_Names => Actual_Type_Names));
         Append_Unique_String
           (Current_Generic_Specialization_Order,
            UString_Value (Specialized_Name));
      end if;

      Result := new CM.Expr_Node'(Expr.all);
      Result.Callee :=
        Name_Expr_From_String (UString_Value (Specialized_Name), Expr.Callee.Span);
      Result.Callee.Generic_Args.Clear;
      return Result;
   end Specialize_Generic_Call;

   procedure Append_Statements
     (Target : in out CM.Statement_Access_Vectors.Vector;
      Items  : CM.Statement_Access_Vectors.Vector) is
   begin
      for Item of Items loop
         Target.Append (Item);
      end loop;
   end Append_Statements;

   function Ident_Expr
     (Name      : String;
      Span      : FT.Source_Span;
      Type_Name : String) return CM.Expr_Access is
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

   function Unary_Expr
     (Operator  : String;
      Inner     : CM.Expr_Access;
      Span      : FT.Source_Span;
      Type_Name : String) return CM.Expr_Access is
   begin
      return
        new CM.Expr_Node'
          (Kind      => CM.Expr_Unary,
           Span      => Span,
           Type_Name => FT.To_UString (Type_Name),
           Operator  => FT.To_UString (Operator),
           Inner     => Inner,
           others    => <>);
   end Unary_Expr;

   function Tuple_Expr
     (First     : CM.Expr_Access;
      Second    : CM.Expr_Access;
      Span      : FT.Source_Span;
      Type_Name : String) return CM.Expr_Access
   is
      Result : constant CM.Expr_Access := new CM.Expr_Node;
   begin
      Result.Kind := CM.Expr_Tuple;
      Result.Span := Span;
      Result.Type_Name := FT.To_UString (Type_Name);
      Result.Elements.Append (First);
      Result.Elements.Append (Second);
      return Result;
   end Tuple_Expr;

   function Default_Initializer_Expr
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map;
      Span     : FT.Source_Span) return CM.Expr_Access
   is
      Kind   : constant String := FT.Lowercase (UString_Value (Info.Kind));
      Name   : constant String := FT.Lowercase (UString_Value (Info.Name));
      Quote  : constant Character := Character'Val (34);
      Result : CM.Expr_Access;
      Field  : CM.Aggregate_Field;
   begin
      if Kind = "subtype"
        and then UString_Value (Info.Base)'Length > 0
        and then not Info.Has_Low
        and then not Info.Has_High
        and then not Info.Has_Float_Low_Text
        and then not Info.Has_Float_High_Text
      then
         return Default_Initializer_Expr
           (Resolve_Type (UString_Value (Info.Base), Type_Env, "", FT.Null_Span),
            Type_Env,
            Span);
      elsif Kind = "access" then
         return
           new CM.Expr_Node'
             (Kind      => CM.Expr_Null,
              Span      => Span,
              Type_Name => FT.To_UString (UString_Value (Info.Name)),
              Text      => FT.To_UString ("null"),
              others    => <>);
      elsif Name = "string" then
         return
           new CM.Expr_Node'
             (Kind      => CM.Expr_String,
              Span      => Span,
              Type_Name => FT.To_UString ("string"),
              Text      => FT.To_UString (String'(1 => Quote, 2 => Quote)),
              others    => <>);
      elsif Info.Is_Result_Builtin then
         Result := new CM.Expr_Node;
         Result.Kind := CM.Expr_Call;
         Result.Type_Name := FT.To_UString (UString_Value (Info.Name));
         Result.Span := Span;
         Result.Callee :=
           Ident_Expr
             (Name      => "ok",
             Span      => Span,
             Type_Name => UString_Value (Info.Name));
         return Result;
      elsif Is_Optional_Type (Info, Type_Env) then
         return Build_Optional_None_Expr (Info, Span);
      elsif Kind = "array" and then Info.Growable then
         Result := new CM.Expr_Node;
         Result.Kind := CM.Expr_Array_Literal;
         Result.Type_Name := Info.Name;
         Result.Span := Span;
         return Result;
      elsif Kind = "record" then
         Result := new CM.Expr_Node;
         Result.Kind := CM.Expr_Aggregate;
         Result.Type_Name := Info.Name;
         Result.Span := Span;
         for Item of Info.Fields loop
            Field.Field_Name := Item.Name;
            Field.Expr := Default_Initializer_Expr
              (Resolve_Type (UString_Value (Item.Type_Name), Type_Env, "", FT.Null_Span),
               Type_Env,
               Span);
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
              (Default_Initializer_Expr
                 (Resolve_Type (UString_Value (Item), Type_Env, "", FT.Null_Span),
                  Type_Env,
                  Span));
         end loop;
         return Result;
      end if;

      return Selector_Expr
        (Prefix    => Ident_Expr (UString_Value (Info.Name), Span, UString_Value (Info.Name)),
         Selector  => "first",
         Span      => Span,
         Type_Name => UString_Value (Info.Name));
   end Default_Initializer_Expr;

   function Synthetic_Object_Decl_Stmt
     (Name        : String;
      Type_Info   : GM.Type_Descriptor;
      Initializer : CM.Expr_Access;
      Span        : FT.Source_Span;
      Is_Constant : Boolean := True) return CM.Statement_Access
   is
      Result : constant CM.Statement_Access := new CM.Statement;
   begin
      Result.Kind := CM.Stmt_Object_Decl;
      Result.Is_Synthetic := True;
      Result.Span := Span;
      Result.Decl.Names.Append (FT.To_UString (Name));
      Result.Decl.Type_Info := Type_Info;
      Result.Decl.Is_Constant := Is_Constant;
      Result.Decl.Has_Initializer := Initializer /= null;
      Result.Decl.Initializer := Initializer;
      Result.Decl.Span := Span;
      return Result;
   end Synthetic_Object_Decl_Stmt;

   function Synthetic_Assign_Stmt
     (Target : CM.Expr_Access;
      Value  : CM.Expr_Access;
      Span   : FT.Source_Span) return CM.Statement_Access
   is
      Result : constant CM.Statement_Access := new CM.Statement;
   begin
      Result.Kind := CM.Stmt_Assign;
      Result.Is_Synthetic := True;
      Result.Span := Span;
      Result.Target := Target;
      Result.Value := Value;
      return Result;
   end Synthetic_Assign_Stmt;

   function Synthetic_Call_Stmt
     (Call : CM.Expr_Access;
      Span : FT.Source_Span) return CM.Statement_Access
   is
      Result : constant CM.Statement_Access := new CM.Statement;
   begin
      Result.Kind := CM.Stmt_Call;
      Result.Is_Synthetic := True;
      Result.Span := Span;
      Result.Call := Call;
      return Result;
   end Synthetic_Call_Stmt;

   function Synthetic_Return_Stmt
     (Value : CM.Expr_Access;
      Span  : FT.Source_Span) return CM.Statement_Access
   is
      Result : constant CM.Statement_Access := new CM.Statement;
   begin
      Result.Kind := CM.Stmt_Return;
      Result.Is_Synthetic := True;
      Result.Span := Span;
      Result.Value := Value;
      return Result;
   end Synthetic_Return_Stmt;

   function Synthetic_If_Stmt
     (Condition  : CM.Expr_Access;
      Then_Stmts : CM.Statement_Access_Vectors.Vector;
      Span       : FT.Source_Span) return CM.Statement_Access
   is
      Result : constant CM.Statement_Access := new CM.Statement;
   begin
      Result.Kind := CM.Stmt_If;
      Result.Is_Synthetic := True;
      Result.Span := Span;
      Result.Condition := Condition;
      Result.Then_Stmts := Then_Stmts;
      return Result;
   end Synthetic_If_Stmt;

   function Synthetic_If_Else_Stmt
     (Condition  : CM.Expr_Access;
      Then_Stmts : CM.Statement_Access_Vectors.Vector;
      Else_Stmts : CM.Statement_Access_Vectors.Vector;
      Span       : FT.Source_Span) return CM.Statement_Access
   is
      Result : constant CM.Statement_Access := new CM.Statement;
   begin
      Result.Kind := CM.Stmt_If;
      Result.Is_Synthetic := True;
      Result.Span := Span;
      Result.Condition := Condition;
      Result.Then_Stmts := Then_Stmts;
      Result.Has_Else := True;
      Result.Else_Stmts := Else_Stmts;
      return Result;
   end Synthetic_If_Else_Stmt;

   function Synthetic_While_Stmt
     (Condition  : CM.Expr_Access;
      Body_Stmts : CM.Statement_Access_Vectors.Vector;
      Span       : FT.Source_Span) return CM.Statement_Access
   is
      Result : constant CM.Statement_Access := new CM.Statement;
   begin
      Result.Kind := CM.Stmt_While;
      Result.Is_Synthetic := True;
      Result.Span := Span;
      Result.Condition := Condition;
      Result.Body_Stmts := Body_Stmts;
      return Result;
   end Synthetic_While_Stmt;

   function Synthetic_For_Stmt
     (Loop_Var  : String;
      Low_Expr  : CM.Expr_Access;
      High_Expr : CM.Expr_Access;
      Body_Stmts : CM.Statement_Access_Vectors.Vector;
      Span      : FT.Source_Span) return CM.Statement_Access
   is
      Result : constant CM.Statement_Access := new CM.Statement;
   begin
      Result.Kind := CM.Stmt_For;
      Result.Is_Synthetic := True;
      Result.Span := Span;
      Result.Loop_Var := FT.To_UString (Loop_Var);
      Result.Loop_Range.Kind := CM.Range_Explicit;
      Result.Loop_Range.Span := Span;
      Result.Loop_Range.Low_Expr := Low_Expr;
      Result.Loop_Range.High_Expr := High_Expr;
      Result.Body_Stmts := Body_Stmts;
      return Result;
   end Synthetic_For_Stmt;

   function Synthetic_For_Of_Stmt
     (Loop_Var      : String;
      Loop_Iterable : CM.Expr_Access;
      Body_Stmts    : CM.Statement_Access_Vectors.Vector;
      Span          : FT.Source_Span) return CM.Statement_Access
   is
      Result : constant CM.Statement_Access := new CM.Statement;
   begin
      Result.Kind := CM.Stmt_For;
      Result.Is_Synthetic := True;
      Result.Span := Span;
      Result.Loop_Var := FT.To_UString (Loop_Var);
      Result.Loop_Iterable := Loop_Iterable;
      Result.Body_Stmts := Body_Stmts;
      return Result;
   end Synthetic_For_Of_Stmt;

   function Synthetic_Exit_Stmt
     (Span       : FT.Source_Span;
      Condition  : CM.Expr_Access := null) return CM.Statement_Access
   is
      Result : constant CM.Statement_Access := new CM.Statement;
   begin
      Result.Kind := CM.Stmt_Exit;
      Result.Is_Synthetic := True;
      Result.Span := Span;
      Result.Condition := Condition;
      return Result;
   end Synthetic_Exit_Stmt;

   function Desugar_Executable_Expr
     (Expr                : CM.Expr_Access;
      Var_Types           : Type_Maps.Map;
      Functions           : Function_Maps.Map;
      Type_Env            : Type_Maps.Map;
      Has_Enclosing_Return : Boolean;
      Enclosing_Return_Type : GM.Type_Descriptor;
      Path                : String;
      Reject_Short_Circuit_Try : Boolean := False) return Desugared_Expr_Result
   is
      Result          : Desugared_Expr_Result;
      Child           : Desugared_Expr_Result;
      Left_Result     : Desugared_Expr_Result;
      Right_Result    : Desugared_Expr_Result;
      Carrier_Type    : GM.Type_Descriptor;
      Success_Type    : GM.Type_Descriptor;
      Return_Success  : GM.Type_Descriptor;
      Temp_Name       : FT.UString := FT.To_UString ("");
      Then_Stmts      : CM.Statement_Access_Vectors.Vector;
      Conditional_Right : Boolean := False;
   begin
      if Expr = null then
         return Result;
      end if;

      case Expr.Kind is
         when CM.Expr_Try =>
            if Reject_Short_Circuit_Try then
               Raise_Diag
                 (CM.Unsupported_Source_Construct
                    (Path    => Path,
                     Span    => Expr.Span,
                     Message => "`try` is not yet supported in the right operand of `and then` or `or else`"));
            end if;

            Child :=
              Desugar_Executable_Expr
                (Expr.Inner,
                 Var_Types,
                 Functions,
                 Type_Env,
                 Has_Enclosing_Return,
                 Enclosing_Return_Type,
                 Path);
            Result.Preludes := Child.Preludes;
            Carrier_Type := Expr_Type (Child.Expr, Var_Types, Functions, Type_Env);
            if not Try_Result_Carrier_Success_Type (Carrier_Type, Type_Env, Success_Type) then
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path,
                     Span    => Expr.Span,
                     Message => "`try` expects an expression of type `(result, T)`"));
            elsif not Has_Enclosing_Return
              or else not Try_Result_Carrier_Success_Type
                (Enclosing_Return_Type, Type_Env, Return_Success)
            then
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path,
                     Span    => Expr.Span,
                     Message => "`try` requires an enclosing function returning `(result, T)`"));
            end if;

            Temp_Name := FT.To_UString (Next_Synthetic_Name ("Safe_Try_Tmp"));
            Result.Preludes.Append
              (Synthetic_Object_Decl_Stmt (UString_Value (Temp_Name), Carrier_Type, Child.Expr, Expr.Span));
            Then_Stmts.Append
              (Synthetic_Return_Stmt
                 (Tuple_Expr
                    (Selector_Expr
                       (Ident_Expr (UString_Value (Temp_Name), Expr.Span, UString_Value (Carrier_Type.Name)),
                        "1",
                        Expr.Span,
                        UString_Value (BT.Result_Type.Name)),
                     Default_Initializer_Expr (Return_Success, Type_Env, Expr.Span),
                     Expr.Span,
                     UString_Value (Enclosing_Return_Type.Name)),
                  Expr.Span));
            Result.Preludes.Append
              (Synthetic_If_Stmt
                 (Unary_Expr
                    ("not",
                     Selector_Expr
                       (Selector_Expr
                          (Ident_Expr (UString_Value (Temp_Name), Expr.Span, UString_Value (Carrier_Type.Name)),
                           "1",
                           Expr.Span,
                           UString_Value (BT.Result_Type.Name)),
                        "ok",
                        Expr.Span,
                        "boolean"),
                     Expr.Span,
                     "boolean"),
                  Then_Stmts,
                  Expr.Span));
            Result.Expr :=
              Selector_Expr
                (Ident_Expr (UString_Value (Temp_Name), Expr.Span, UString_Value (Carrier_Type.Name)),
                 "2",
                 Expr.Span,
                 UString_Value (Success_Type.Name));
            return Result;

         when CM.Expr_Select =>
            Child :=
              Desugar_Executable_Expr
                (Expr.Prefix,
                 Var_Types,
                 Functions,
                 Type_Env,
                 Has_Enclosing_Return,
                 Enclosing_Return_Type,
                 Path,
                 Reject_Short_Circuit_Try);
            Result.Expr := new CM.Expr_Node'(Expr.all);
            Result.Expr.Prefix := Child.Expr;
            Result.Preludes := Child.Preludes;

         when CM.Expr_Resolved_Index =>
            Result.Expr := new CM.Expr_Node'(Expr.all);
            Result.Expr.Args.Clear;
            Child :=
              Desugar_Executable_Expr
                (Expr.Prefix,
                 Var_Types,
                 Functions,
                 Type_Env,
                 Has_Enclosing_Return,
                 Enclosing_Return_Type,
                 Path,
                 Reject_Short_Circuit_Try);
            Result.Expr.Prefix := Child.Expr;
            Result.Preludes := Child.Preludes;
            for Item of Expr.Args loop
               Child :=
                 Desugar_Executable_Expr
                   (Item,
                    Var_Types,
                    Functions,
                    Type_Env,
                    Has_Enclosing_Return,
                    Enclosing_Return_Type,
                    Path,
                    Reject_Short_Circuit_Try);
               Append_Statements (Result.Preludes, Child.Preludes);
               Result.Expr.Args.Append (Child.Expr);
            end loop;

         when CM.Expr_Call | CM.Expr_Apply =>
            if Expr.Kind = CM.Expr_Call
              and then Expr.Callee /= null
            then
               declare
                  Shared_Result    : Shared_Object_Ref;
                  Shared_Root      : FT.UString := FT.To_UString ("");
                  Shared_Root_Type : GM.Type_Descriptor;
                  Selector_Name    : constant String :=
                    (if Expr.Callee.Kind = CM.Expr_Select
                     then Canonical_Name (UString_Value (Expr.Callee.Selector))
                     else Canonical_Name (UString_Value (Expr.Callee.Name)));
                  Has_Shared_Call  : Boolean := False;
                  Shared_Operation : FT.UString := FT.To_UString ("");
               begin
                  if Expr.Callee.Kind = CM.Expr_Select
                    and then Try_Shared_Wrapper_Root_Name_Expr
                      (Expr.Callee.Prefix,
                       Shared_Root,
                       Shared_Root_Type)
                  then
                     Has_Shared_Call := True;
                     if Selector_Name = Canonical_Name (Shared_Pop_Last_Name) then
                        Shared_Operation := FT.To_UString (Shared_Pop_Last_Name);
                     elsif Selector_Name = Canonical_Name (Shared_Remove_Name) then
                        Shared_Operation := FT.To_UString (Shared_Remove_Name);
                     end if;
                  elsif Try_Shared_Public_Helper_Call
                    (Expr.Callee,
                     Shared_Pop_Last_Name,
                     Shared_Result)
                  then
                     Has_Shared_Call := True;
                     Shared_Operation := FT.To_UString (Shared_Pop_Last_Name);
                  elsif Try_Shared_Public_Helper_Call
                    (Expr.Callee,
                     Shared_Remove_Name,
                     Shared_Result)
                  then
                     Has_Shared_Call := True;
                     Shared_Operation := FT.To_UString (Shared_Remove_Name);
                  end if;

                  if Has_Shared_Call then
                     if Shared_Result.Kind /= Shared_Object_None then
                        Shared_Root_Type := Shared_Result.Type_Info;
                     end if;
                     if Is_Shared_Container_Root_Type
                       (Shared_Root_Type,
                        Type_Env)
                       and then UString_Value (Shared_Operation) = Shared_Pop_Last_Name
                       and then Expr.Args.Is_Empty
                     then
                        declare
                           Element_Type : constant GM.Type_Descriptor :=
                             Growable_Array_Element_Type
                               (Shared_Root_Type,
                                Type_Env);
                           Optional_Type : constant GM.Type_Descriptor :=
                             Make_Optional_Type (Element_Type, Type_Env);
                           Result_Name : constant FT.UString :=
                             FT.To_UString (Next_Synthetic_Name ("Safe_Shared_Pop_Last"));
                           Call_Expr   : constant CM.Expr_Access :=
                             new CM.Expr_Node'(Expr.all);
                        begin
                           Result.Preludes.Append
                             (Synthetic_Object_Decl_Stmt
                                (UString_Value (Result_Name),
                                 Optional_Type,
                                 Build_Optional_None_Expr
                                   (Optional_Type,
                                    Expr.Span),
                                 Expr.Span,
                                 Is_Constant => False));
                           Call_Expr.Args.Append
                             (Ident_Expr
                                (UString_Value (Result_Name),
                                 Expr.Span,
                                 UString_Value (Optional_Type.Name)));
                           Result.Preludes.Append
                             (Synthetic_Call_Stmt (Call_Expr, Expr.Span));
                           Result.Expr :=
                             Ident_Expr
                               (UString_Value (Result_Name),
                                Expr.Span,
                                UString_Value (Optional_Type.Name));
                           return Result;
                        end;
                     elsif Is_Shared_Container_Root_Type
                       (Shared_Root_Type,
                        Type_Env)
                       and then UString_Value (Shared_Operation) = Shared_Remove_Name
                       and then Natural (Expr.Args.Length) = 1
                     then
                        declare
                           Key_Child : constant Desugared_Expr_Result :=
                             Desugar_Executable_Expr
                               (Expr.Args (Expr.Args.First_Index),
                                Var_Types,
                                Functions,
                                Type_Env,
                                Has_Enclosing_Return,
                                Enclosing_Return_Type,
                                Path,
                                Reject_Short_Circuit_Try);
                           Key_Type   : GM.Type_Descriptor;
                           Value_Type : GM.Type_Descriptor;
                           Optional_Type : GM.Type_Descriptor := Default_Integer;
                           Result_Name : constant FT.UString :=
                             FT.To_UString (Next_Synthetic_Name ("Safe_Shared_Remove"));
                           Call_Expr   : constant CM.Expr_Access :=
                             new CM.Expr_Node'(Expr.all);
                        begin
                           if not Try_Map_Key_Value_Types
                             (Shared_Root_Type,
                              Type_Env,
                              Key_Type,
                              Value_Type)
                           then
                              Raise_Diag
                                (CM.Source_Frontend_Error
                                   (Path    => Path,
                                    Span    => Expr.Span,
                                    Message => "`remove` expects a shared `map of (K, V)` root"));
                           end if;

                           Optional_Type := Make_Optional_Type (Value_Type, Type_Env);
                           Append_Statements (Result.Preludes, Key_Child.Preludes);
                           Result.Preludes.Append
                             (Synthetic_Object_Decl_Stmt
                                (UString_Value (Result_Name),
                                 Optional_Type,
                                 Build_Optional_None_Expr
                                   (Optional_Type,
                                    Expr.Span),
                                 Expr.Span,
                                 Is_Constant => False));
                           Call_Expr.Args.Clear;
                           Call_Expr.Args.Append (Key_Child.Expr);
                           Call_Expr.Args.Append
                             (Ident_Expr
                                (UString_Value (Result_Name),
                                 Expr.Span,
                                 UString_Value (Optional_Type.Name)));
                           Result.Preludes.Append
                             (Synthetic_Call_Stmt (Call_Expr, Expr.Span));
                           Result.Expr :=
                             Ident_Expr
                               (UString_Value (Result_Name),
                                Expr.Span,
                                UString_Value (Optional_Type.Name));
                           return Result;
                        end;
                     end if;
                  end if;
               end;
            end if;
            if Is_Pop_Last_Builtin_Call (Expr, Var_Types, Functions, Type_Env) then
               declare
                  List_Expr      : constant CM.Expr_Access :=
                    Expr.Args (Expr.Args.First_Index);
                  List_Type      : constant GM.Type_Descriptor :=
                    Expr_Type (List_Expr, Var_Types, Functions, Type_Env);
                  Element_Type   : constant GM.Type_Descriptor :=
                    Growable_Array_Element_Type (List_Type, Type_Env);
                  Optional_Type  : constant GM.Type_Descriptor :=
                    Make_Optional_Type (Element_Type, Type_Env);
                  Length_Name    : constant FT.UString :=
                    FT.To_UString (Next_Synthetic_Name ("Safe_List_Len"));
                  Result_Name    : constant FT.UString :=
                    FT.To_UString (Next_Synthetic_Name ("Safe_List_Pop"));
                  Then_Stmts     : CM.Statement_Access_Vectors.Vector;
                  Trim_Then      : CM.Statement_Access_Vectors.Vector;
                  Slice_Then     : CM.Statement_Access_Vectors.Vector;
                  Length_Expr    : constant CM.Expr_Access :=
                    Selector_Expr
                      (List_Expr,
                       "length",
                       Expr.Span,
                       UString_Value (Default_Integer.Name));
                  Length_Temp    : constant CM.Expr_Access :=
                    Ident_Expr
                      (UString_Value (Length_Name),
                       Expr.Span,
                       UString_Value (Default_Integer.Name));
                  Last_Value_Expr : constant CM.Expr_Access :=
                    Resolved_Index_Expr
                      (List_Expr,
                       Length_Temp,
                       Expr.Span,
                       UString_Value (Element_Type.Name));
                  Empty_List_Expr : constant CM.Expr_Access := new CM.Expr_Node;
               begin
                  Empty_List_Expr.Kind := CM.Expr_Array_Literal;
                  Empty_List_Expr.Span := Expr.Span;
                  Empty_List_Expr.Type_Name := List_Type.Name;

                  Result.Preludes.Append
                    (Synthetic_Object_Decl_Stmt
                       (UString_Value (Length_Name),
                        Default_Integer,
                        Length_Expr,
                        Expr.Span));
                  Result.Preludes.Append
                    (Synthetic_Object_Decl_Stmt
                       (UString_Value (Result_Name),
                        Optional_Type,
                        Build_Optional_None_Expr (Optional_Type, Expr.Span),
                        Expr.Span,
                        Is_Constant => False));

                  Then_Stmts.Append
                    (Synthetic_Assign_Stmt
                       (Ident_Expr
                          (UString_Value (Result_Name),
                           Expr.Span,
                           UString_Value (Optional_Type.Name)),
                        Build_Optional_Some_Expr
                          (Optional_Type,
                           Last_Value_Expr,
                           Expr.Span),
                        Expr.Span));

                  Trim_Then.Append
                    (Synthetic_Assign_Stmt
                       (List_Expr,
                        Empty_List_Expr,
                        Expr.Span));
                  Then_Stmts.Append
                    (Synthetic_If_Stmt
                       (Binary_Expr
                          (Length_Temp,
                           "==",
                           Int_Expr (1, Expr.Span),
                           Expr.Span,
                           "boolean"),
                        Trim_Then,
                        Expr.Span));
                  Slice_Then.Append
                    (Synthetic_Assign_Stmt
                       (List_Expr,
                        Resolved_Index_Expr
                          (List_Expr,
                           Int_Expr (1, Expr.Span),
                           Expr.Span,
                           UString_Value (List_Type.Name),
                           Binary_Expr
                             (Length_Temp,
                              "-",
                              Int_Expr (1, Expr.Span),
                              Expr.Span,
                              UString_Value (Default_Integer.Name))),
                        Expr.Span));
                  Then_Stmts.Append
                    (Synthetic_If_Stmt
                       (Binary_Expr
                          (Length_Temp,
                           ">",
                           Int_Expr (1, Expr.Span),
                           Expr.Span,
                           "boolean"),
                        Slice_Then,
                        Expr.Span));

                  Result.Preludes.Append
                    (Synthetic_If_Stmt
                       (Binary_Expr
                          (Length_Temp,
                           ">",
                           Int_Expr (0, Expr.Span),
                           Expr.Span,
                           "boolean"),
                        Then_Stmts,
                        Expr.Span));
                  Result.Expr :=
                    Ident_Expr
                      (UString_Value (Result_Name),
                       Expr.Span,
                       UString_Value (Optional_Type.Name));
                  return Result;
               end;
            end if;
            if Is_Contains_Builtin_Call (Expr, Var_Types, Functions, Type_Env) then
               declare
                  Map_Child   : constant Desugared_Expr_Result :=
                    Desugar_Executable_Expr
                      (Expr.Args (Expr.Args.First_Index),
                       Var_Types,
                       Functions,
                       Type_Env,
                       Has_Enclosing_Return,
                       Enclosing_Return_Type,
                       Path,
                       Reject_Short_Circuit_Try);
                  Key_Child   : constant Desugared_Expr_Result :=
                    Desugar_Executable_Expr
                      (Expr.Args (Expr.Args.First_Index + 1),
                       Var_Types,
                       Functions,
                       Type_Env,
                       Has_Enclosing_Return,
                       Enclosing_Return_Type,
                       Path,
                       Reject_Short_Circuit_Try);
                  Map_Type    : constant GM.Type_Descriptor :=
                    Expr_Type (Map_Child.Expr, Var_Types, Functions, Type_Env);
                  Key_Type    : GM.Type_Descriptor;
                  Value_Type  : GM.Type_Descriptor;
                  Snapshot_Name : constant FT.UString :=
                    FT.To_UString (Next_Synthetic_Name ("Safe_Map_Value"));
                  Key_Name    : constant FT.UString :=
                    FT.To_UString (Next_Synthetic_Name ("Safe_Map_Key"));
                  Length_Name : constant FT.UString :=
                    FT.To_UString (Next_Synthetic_Name ("Safe_Map_Len"));
                  Index_Name  : constant FT.UString :=
                    FT.To_UString (Next_Synthetic_Name ("Safe_Map_Index"));
                  Result_Name : constant FT.UString :=
                    FT.To_UString (Next_Synthetic_Name ("Safe_Map_Contains"));
                  Entry_Name  : constant FT.UString :=
                    FT.To_UString (Next_Synthetic_Name ("Safe_Map_Entry"));
                  Snapshot_Expr : CM.Expr_Access;
                  Key_Temp    : CM.Expr_Access;
                  Length_Temp : CM.Expr_Access;
                  Index_Temp  : CM.Expr_Access;
                  Result_Temp : CM.Expr_Access;
                  Entry_Expr  : CM.Expr_Access;
                  Match_Then  : CM.Statement_Access_Vectors.Vector;
                  Index_Guard_Then : CM.Statement_Access_Vectors.Vector;
                  Advance_Then : CM.Statement_Access_Vectors.Vector;
                  Advance_Else : CM.Statement_Access_Vectors.Vector;
                  Loop_Body   : CM.Statement_Access_Vectors.Vector;
                  Entry_Type  : GM.Type_Descriptor := Default_Integer;
                  Entry_Elements : FT.UString_Vectors.Vector;
               begin
                  Append_Statements (Result.Preludes, Map_Child.Preludes);
                  Append_Statements (Result.Preludes, Key_Child.Preludes);
                  if not Try_Map_Key_Value_Types (Map_Type, Type_Env, Key_Type, Value_Type) then
                     Raise_Diag
                       (CM.Source_Frontend_Error
                          (Path    => Path,
                           Span    => Expr.Span,
                           Message => "`contains` expects a `map of (K, V)` first argument"));
                  end if;
                  Entry_Elements.Append (Key_Type.Name);
                  Entry_Elements.Append (Value_Type.Name);
                  Entry_Type := Make_Tuple_Type (Entry_Elements, Type_Env);

                  Result.Preludes.Append
                    (Synthetic_Object_Decl_Stmt
                       (UString_Value (Snapshot_Name),
                        Map_Type,
                        Map_Child.Expr,
                        Expr.Span));
                  Result.Preludes.Append
                    (Synthetic_Object_Decl_Stmt
                       (UString_Value (Key_Name),
                        Key_Type,
                        Key_Child.Expr,
                        Expr.Span));
                  Result.Preludes.Append
                    (Synthetic_Object_Decl_Stmt
                       (UString_Value (Length_Name),
                        Default_Integer,
                        Selector_Expr
                          (Ident_Expr
                             (UString_Value (Snapshot_Name),
                              Expr.Span,
                              UString_Value (Map_Type.Name)),
                           "length",
                           Expr.Span,
                           UString_Value (Default_Integer.Name)),
                        Expr.Span));
                  Result.Preludes.Append
                    (Synthetic_Object_Decl_Stmt
                       (UString_Value (Index_Name),
                        Default_Integer,
                        Int_Expr (1, Expr.Span),
                        Expr.Span,
                        Is_Constant => False));
                  Result.Preludes.Append
                    (Synthetic_Object_Decl_Stmt
                       (UString_Value (Result_Name),
                        BT.Boolean_Type,
                        Bool_Expr (False, Expr.Span),
                        Expr.Span,
                        Is_Constant => False));

                  Snapshot_Expr :=
                    Ident_Expr
                      (UString_Value (Snapshot_Name),
                       Expr.Span,
                       UString_Value (Map_Type.Name));
                  Key_Temp :=
                    Ident_Expr
                      (UString_Value (Key_Name),
                       Expr.Span,
                       UString_Value (Key_Type.Name));
                  Length_Temp :=
                    Ident_Expr
                      (UString_Value (Length_Name),
                       Expr.Span,
                       UString_Value (Default_Integer.Name));
                  Index_Temp :=
                    Ident_Expr
                      (UString_Value (Index_Name),
                       Expr.Span,
                       UString_Value (Default_Integer.Name));
                  Result_Temp :=
                    Ident_Expr
                      (UString_Value (Result_Name),
                       Expr.Span,
                       UString_Value (BT.Boolean_Type.Name));
                  Entry_Expr :=
                    Ident_Expr
                      (UString_Value (Entry_Name),
                       Expr.Span,
                       UString_Value (Entry_Type.Name));
                  Index_Guard_Then.Append
                    (Synthetic_Exit_Stmt (Expr.Span));
                  Loop_Body.Append
                    (Synthetic_If_Stmt
                       (Binary_Expr
                          (Index_Temp,
                           "<",
                           Int_Expr (1, Expr.Span),
                           Expr.Span,
                           "boolean"),
                        Index_Guard_Then,
                        Expr.Span));

                  Match_Then.Append
                    (Synthetic_Assign_Stmt
                       (Result_Temp,
                        Bool_Expr (True, Expr.Span),
                        Expr.Span));
                  Match_Then.Append
                    (Synthetic_Exit_Stmt (Expr.Span));
                  Loop_Body.Append
                    (Synthetic_Object_Decl_Stmt
                       (UString_Value (Entry_Name),
                        Entry_Type,
                        Resolved_Index_Expr
                          (Snapshot_Expr,
                           Index_Temp,
                           Expr.Span,
                           UString_Value (Entry_Type.Name)),
                        Expr.Span));
                  Loop_Body.Append
                    (Synthetic_If_Stmt
                       (Binary_Expr
                          (Unary_Expr
                             ("not",
                              Result_Temp,
                              Expr.Span,
                              "boolean"),
                           "and then",
                           Binary_Expr
                             (Selector_Expr
                                (Entry_Expr,
                                 "1",
                                 Expr.Span,
                                 UString_Value (Key_Type.Name)),
                              "==",
                              Key_Temp,
                              Expr.Span,
                              "boolean"),
                           Expr.Span,
                           "boolean"),
                        Match_Then,
                        Expr.Span));
                  Advance_Then.Append
                    (Synthetic_Assign_Stmt
                       (Index_Temp,
                        Binary_Expr
                          (Index_Temp,
                           "+",
                           Int_Expr (1, Expr.Span),
                           Expr.Span,
                           UString_Value (Default_Integer.Name)),
                        Expr.Span));
                  Advance_Else.Append
                    (Synthetic_Exit_Stmt (Expr.Span));
                  Loop_Body.Append
                    (Synthetic_If_Else_Stmt
                       (Binary_Expr
                          (Index_Temp,
                           "<",
                           Length_Temp,
                           Expr.Span,
                           "boolean"),
                        Advance_Then,
                        Advance_Else,
                        Expr.Span));
                  Result.Preludes.Append
                    (Synthetic_While_Stmt
                       (Binary_Expr
                          (Index_Temp,
                           "<=",
                           Length_Temp,
                           Expr.Span,
                           "boolean"),
                        Loop_Body,
                        Expr.Span));
                  Result.Expr := Result_Temp;
                  return Result;
               end;
            end if;
            if Is_Get_Builtin_Call (Expr, Var_Types, Functions, Type_Env) then
               declare
                  Map_Child   : constant Desugared_Expr_Result :=
                    Desugar_Executable_Expr
                      (Expr.Args (Expr.Args.First_Index),
                       Var_Types,
                       Functions,
                       Type_Env,
                       Has_Enclosing_Return,
                       Enclosing_Return_Type,
                       Path,
                       Reject_Short_Circuit_Try);
                  Key_Child   : constant Desugared_Expr_Result :=
                    Desugar_Executable_Expr
                      (Expr.Args (Expr.Args.First_Index + 1),
                       Var_Types,
                       Functions,
                       Type_Env,
                       Has_Enclosing_Return,
                       Enclosing_Return_Type,
                       Path,
                       Reject_Short_Circuit_Try);
                  Map_Type    : constant GM.Type_Descriptor :=
                    Expr_Type (Map_Child.Expr, Var_Types, Functions, Type_Env);
                  Key_Type    : GM.Type_Descriptor;
                  Value_Type  : GM.Type_Descriptor;
                  Snapshot_Name : constant FT.UString :=
                    FT.To_UString (Next_Synthetic_Name ("Safe_Map_Value"));
                  Key_Name    : constant FT.UString :=
                    FT.To_UString (Next_Synthetic_Name ("Safe_Map_Key"));
                  Length_Name : constant FT.UString :=
                    FT.To_UString (Next_Synthetic_Name ("Safe_Map_Len"));
                  Index_Name  : constant FT.UString :=
                    FT.To_UString (Next_Synthetic_Name ("Safe_Map_Index"));
                  Result_Name : constant FT.UString :=
                    FT.To_UString (Next_Synthetic_Name ("Safe_Map_Get"));
                  Entry_Name  : constant FT.UString :=
                    FT.To_UString (Next_Synthetic_Name ("Safe_Map_Entry"));
                  Snapshot_Expr : CM.Expr_Access;
                  Key_Temp    : CM.Expr_Access;
                  Length_Temp : CM.Expr_Access;
                  Index_Temp  : CM.Expr_Access;
                  Result_Temp : CM.Expr_Access;
                  Present_Expr : CM.Expr_Access;
                  Entry_Expr  : CM.Expr_Access;
                  Match_Then  : CM.Statement_Access_Vectors.Vector;
                  Index_Guard_Then : CM.Statement_Access_Vectors.Vector;
                  Advance_Then : CM.Statement_Access_Vectors.Vector;
                  Advance_Else : CM.Statement_Access_Vectors.Vector;
                  Loop_Body   : CM.Statement_Access_Vectors.Vector;
                  Optional_Type : GM.Type_Descriptor := Default_Integer;
                  Entry_Type    : GM.Type_Descriptor := Default_Integer;
                  Entry_Elements : FT.UString_Vectors.Vector;
               begin
                  Append_Statements (Result.Preludes, Map_Child.Preludes);
                  Append_Statements (Result.Preludes, Key_Child.Preludes);
                  if not Try_Map_Key_Value_Types (Map_Type, Type_Env, Key_Type, Value_Type) then
                     Raise_Diag
                       (CM.Source_Frontend_Error
                          (Path    => Path,
                           Span    => Expr.Span,
                           Message => "`get` expects a `map of (K, V)` first argument"));
                  end if;

                  Optional_Type := Make_Optional_Type (Value_Type, Type_Env);
                  Entry_Elements.Append (Key_Type.Name);
                  Entry_Elements.Append (Value_Type.Name);
                  Entry_Type := Make_Tuple_Type (Entry_Elements, Type_Env);
                  Result.Preludes.Append
                    (Synthetic_Object_Decl_Stmt
                       (UString_Value (Snapshot_Name),
                        Map_Type,
                        Map_Child.Expr,
                        Expr.Span));
                  Result.Preludes.Append
                    (Synthetic_Object_Decl_Stmt
                       (UString_Value (Key_Name),
                        Key_Type,
                        Key_Child.Expr,
                        Expr.Span));
                  Result.Preludes.Append
                    (Synthetic_Object_Decl_Stmt
                       (UString_Value (Length_Name),
                        Default_Integer,
                        Selector_Expr
                          (Ident_Expr
                             (UString_Value (Snapshot_Name),
                              Expr.Span,
                              UString_Value (Map_Type.Name)),
                           "length",
                           Expr.Span,
                           UString_Value (Default_Integer.Name)),
                        Expr.Span));
                  Result.Preludes.Append
                    (Synthetic_Object_Decl_Stmt
                       (UString_Value (Index_Name),
                        Default_Integer,
                        Int_Expr (1, Expr.Span),
                        Expr.Span,
                        Is_Constant => False));
                  Result.Preludes.Append
                    (Synthetic_Object_Decl_Stmt
                       (UString_Value (Result_Name),
                        Optional_Type,
                        Build_Optional_None_Expr (Optional_Type, Expr.Span),
                        Expr.Span,
                        Is_Constant => False));

                  Snapshot_Expr :=
                    Ident_Expr
                      (UString_Value (Snapshot_Name),
                       Expr.Span,
                       UString_Value (Map_Type.Name));
                  Key_Temp :=
                    Ident_Expr
                      (UString_Value (Key_Name),
                       Expr.Span,
                       UString_Value (Key_Type.Name));
                  Length_Temp :=
                    Ident_Expr
                      (UString_Value (Length_Name),
                       Expr.Span,
                       UString_Value (Default_Integer.Name));
                  Index_Temp :=
                    Ident_Expr
                      (UString_Value (Index_Name),
                       Expr.Span,
                       UString_Value (Default_Integer.Name));
                  Result_Temp :=
                    Ident_Expr
                      (UString_Value (Result_Name),
                       Expr.Span,
                       UString_Value (Optional_Type.Name));
                  Present_Expr :=
                    Selector_Expr
                      (Result_Temp,
                       "present",
                       Expr.Span,
                       "boolean");
                  Entry_Type := Growable_Array_Element_Type (Map_Type, Type_Env);
                  Entry_Expr :=
                    Ident_Expr
                      (UString_Value (Entry_Name),
                       Expr.Span,
                       UString_Value (Entry_Type.Name));
                  Index_Guard_Then.Append
                    (Synthetic_Exit_Stmt (Expr.Span));
                  Loop_Body.Append
                    (Synthetic_If_Stmt
                       (Binary_Expr
                          (Index_Temp,
                           "<",
                           Int_Expr (1, Expr.Span),
                           Expr.Span,
                           "boolean"),
                        Index_Guard_Then,
                        Expr.Span));

                  Match_Then.Append
                    (Synthetic_Assign_Stmt
                       (Result_Temp,
                        Build_Optional_Some_Expr
                          (Optional_Type,
                           Selector_Expr
                             (Entry_Expr,
                              "2",
                              Expr.Span,
                             UString_Value (Value_Type.Name)),
                           Expr.Span),
                        Expr.Span));
                  Match_Then.Append
                    (Synthetic_Exit_Stmt (Expr.Span));
                  Loop_Body.Append
                    (Synthetic_Object_Decl_Stmt
                       (UString_Value (Entry_Name),
                        Entry_Type,
                        Resolved_Index_Expr
                          (Snapshot_Expr,
                           Index_Temp,
                           Expr.Span,
                           UString_Value (Entry_Type.Name)),
                        Expr.Span));
                  Loop_Body.Append
                    (Synthetic_If_Stmt
                       (Binary_Expr
                          (Unary_Expr
                             ("not",
                              Present_Expr,
                              Expr.Span,
                              "boolean"),
                           "and then",
                           Binary_Expr
                             (Selector_Expr
                                (Entry_Expr,
                                 "1",
                                 Expr.Span,
                                 UString_Value (Key_Type.Name)),
                              "==",
                              Key_Temp,
                              Expr.Span,
                              "boolean"),
                           Expr.Span,
                           "boolean"),
                        Match_Then,
                        Expr.Span));
                  Advance_Then.Append
                    (Synthetic_Assign_Stmt
                       (Index_Temp,
                        Binary_Expr
                          (Index_Temp,
                           "+",
                           Int_Expr (1, Expr.Span),
                           Expr.Span,
                           UString_Value (Default_Integer.Name)),
                        Expr.Span));
                  Advance_Else.Append
                    (Synthetic_Exit_Stmt (Expr.Span));
                  Loop_Body.Append
                    (Synthetic_If_Else_Stmt
                       (Binary_Expr
                          (Index_Temp,
                           "<",
                           Length_Temp,
                           Expr.Span,
                           "boolean"),
                        Advance_Then,
                        Advance_Else,
                        Expr.Span));
                  Result.Preludes.Append
                    (Synthetic_While_Stmt
                       (Binary_Expr
                          (Index_Temp,
                           "<=",
                           Length_Temp,
                           Expr.Span,
                           "boolean"),
                        Loop_Body,
                        Expr.Span));
                  Result.Expr := Result_Temp;
                  return Result;
               end;
            end if;
            if Is_Remove_Builtin_Call (Expr, Var_Types, Functions, Type_Env) then
               declare
                  Map_Child     : constant Desugared_Expr_Result :=
                    Desugar_Executable_Expr
                      (Expr.Args (Expr.Args.First_Index),
                       Var_Types,
                       Functions,
                       Type_Env,
                       Has_Enclosing_Return,
                       Enclosing_Return_Type,
                       Path,
                       Reject_Short_Circuit_Try);
                  Key_Child     : constant Desugared_Expr_Result :=
                    Desugar_Executable_Expr
                      (Expr.Args (Expr.Args.First_Index + 1),
                       Var_Types,
                       Functions,
                       Type_Env,
                       Has_Enclosing_Return,
                       Enclosing_Return_Type,
                       Path,
                       Reject_Short_Circuit_Try);
                  Map_Type      : constant GM.Type_Descriptor :=
                    Expr_Type (Map_Child.Expr, Var_Types, Functions, Type_Env);
                  Key_Type      : GM.Type_Descriptor;
                  Value_Type    : GM.Type_Descriptor;
                  Optional_Type : GM.Type_Descriptor := Default_Integer;
                  Snapshot_Name : constant FT.UString :=
                    FT.To_UString (Next_Synthetic_Name ("Safe_Map_Value"));
                  Key_Name      : constant FT.UString :=
                    FT.To_UString (Next_Synthetic_Name ("Safe_Map_Key"));
                  Length_Name   : constant FT.UString :=
                    FT.To_UString (Next_Synthetic_Name ("Safe_Map_Len"));
                  Index_Name    : constant FT.UString :=
                    FT.To_UString (Next_Synthetic_Name ("Safe_Map_Index"));
                  Result_Name   : constant FT.UString :=
                    FT.To_UString (Next_Synthetic_Name ("Safe_Map_Remove"));
                  Entry_Name    : constant FT.UString :=
                    FT.To_UString (Next_Synthetic_Name ("Safe_Map_Entry"));
                  Snapshot_Expr : CM.Expr_Access;
                  Key_Temp      : CM.Expr_Access;
                  Length_Temp   : CM.Expr_Access;
                  Index_Temp    : CM.Expr_Access;
                  Result_Temp   : CM.Expr_Access;
                  Entry_Expr    : CM.Expr_Access;
                  Last_Entry_Expr : CM.Expr_Access;
                  Match_Then    : CM.Statement_Access_Vectors.Vector;
                  Trim_Then     : CM.Statement_Access_Vectors.Vector;
                  Trim_Else     : CM.Statement_Access_Vectors.Vector;
                  Rebuild_Then  : CM.Statement_Access_Vectors.Vector;
                  Prefix_Then   : CM.Statement_Access_Vectors.Vector;
                  Prefix_Else   : CM.Statement_Access_Vectors.Vector;
                  Suffix_Then   : CM.Statement_Access_Vectors.Vector;
                  Index_Guard_Then : CM.Statement_Access_Vectors.Vector;
                  Loop_Body     : CM.Statement_Access_Vectors.Vector;
                  Advance_Then  : CM.Statement_Access_Vectors.Vector;
                  Advance_Else  : CM.Statement_Access_Vectors.Vector;
                  Empty_Map_Expr : constant CM.Expr_Access := new CM.Expr_Node;
                  Last_Literal_Expr : constant CM.Expr_Access := new CM.Expr_Node;
                  Entry_Type    : GM.Type_Descriptor := Default_Integer;
                  Entry_Elements : FT.UString_Vectors.Vector;
               begin
                  Append_Statements (Result.Preludes, Map_Child.Preludes);
                  Append_Statements (Result.Preludes, Key_Child.Preludes);
                  if not Try_Map_Key_Value_Types (Map_Type, Type_Env, Key_Type, Value_Type) then
                     Raise_Diag
                       (CM.Source_Frontend_Error
                          (Path    => Path,
                           Span    => Expr.Span,
                           Message => "`remove` expects a `map of (K, V)` first argument"));
                  end if;

                  Optional_Type := Make_Optional_Type (Value_Type, Type_Env);
                  Entry_Elements.Append (Key_Type.Name);
                  Entry_Elements.Append (Value_Type.Name);
                  Entry_Type := Make_Tuple_Type (Entry_Elements, Type_Env);
                  Result.Preludes.Append
                    (Synthetic_Object_Decl_Stmt
                       (UString_Value (Snapshot_Name),
                        Map_Type,
                        Map_Child.Expr,
                        Expr.Span));
                  Result.Preludes.Append
                    (Synthetic_Object_Decl_Stmt
                       (UString_Value (Key_Name),
                        Key_Type,
                        Key_Child.Expr,
                        Expr.Span));
                  Result.Preludes.Append
                    (Synthetic_Object_Decl_Stmt
                       (UString_Value (Length_Name),
                        Default_Integer,
                        Selector_Expr
                          (Ident_Expr
                             (UString_Value (Snapshot_Name),
                              Expr.Span,
                              UString_Value (Map_Type.Name)),
                           "length",
                           Expr.Span,
                           UString_Value (Default_Integer.Name)),
                        Expr.Span));
                  Result.Preludes.Append
                    (Synthetic_Object_Decl_Stmt
                       (UString_Value (Index_Name),
                        Default_Integer,
                        Int_Expr (1, Expr.Span),
                        Expr.Span,
                        Is_Constant => False));
                  Result.Preludes.Append
                    (Synthetic_Object_Decl_Stmt
                       (UString_Value (Result_Name),
                        Optional_Type,
                        Build_Optional_None_Expr (Optional_Type, Expr.Span),
                        Expr.Span,
                        Is_Constant => False));
                  Snapshot_Expr :=
                    Ident_Expr
                      (UString_Value (Snapshot_Name),
                       Expr.Span,
                       UString_Value (Map_Type.Name));
                  Key_Temp :=
                    Ident_Expr
                      (UString_Value (Key_Name),
                       Expr.Span,
                       UString_Value (Key_Type.Name));
                  Length_Temp :=
                    Ident_Expr
                      (UString_Value (Length_Name),
                       Expr.Span,
                       UString_Value (Default_Integer.Name));
                  Index_Temp :=
                    Ident_Expr
                      (UString_Value (Index_Name),
                       Expr.Span,
                       UString_Value (Default_Integer.Name));
                  Result_Temp :=
                    Ident_Expr
                      (UString_Value (Result_Name),
                       Expr.Span,
                       UString_Value (Optional_Type.Name));
                  Entry_Expr :=
                    Ident_Expr
                      (UString_Value (Entry_Name),
                       Expr.Span,
                       UString_Value (Entry_Type.Name));
                  Last_Entry_Expr :=
                    Resolved_Index_Expr
                      (Snapshot_Expr,
                       Length_Temp,
                       Expr.Span,
                       UString_Value (Entry_Type.Name));
                  Empty_Map_Expr.Kind := CM.Expr_Array_Literal;
                  Empty_Map_Expr.Span := Expr.Span;
                  Empty_Map_Expr.Type_Name := Map_Type.Name;
                  Last_Literal_Expr.Kind := CM.Expr_Array_Literal;
                  Last_Literal_Expr.Span := Expr.Span;
                  Last_Literal_Expr.Type_Name := Map_Type.Name;
                  Last_Literal_Expr.Elements.Append (Last_Entry_Expr);
                  Index_Guard_Then.Append
                    (Synthetic_Exit_Stmt (Expr.Span));
                  Loop_Body.Append
                    (Synthetic_If_Stmt
                       (Binary_Expr
                          (Index_Temp,
                           "<",
                           Int_Expr (1, Expr.Span),
                           Expr.Span,
                           "boolean"),
                        Index_Guard_Then,
                        Expr.Span));

                  Match_Then.Append
                    (Synthetic_Assign_Stmt
                       (Result_Temp,
                        Build_Optional_Some_Expr
                          (Optional_Type,
                           Selector_Expr
                             (Entry_Expr,
                              "2",
                              Expr.Span,
                              UString_Value (Value_Type.Name)),
                           Expr.Span),
                        Expr.Span));
                  Trim_Then.Append
                    (Synthetic_Assign_Stmt
                       (Map_Child.Expr,
                        Empty_Map_Expr,
                        Expr.Span));
                  Trim_Else.Append
                    (Synthetic_Assign_Stmt
                       (Map_Child.Expr,
                        Resolved_Index_Expr
                          (Map_Child.Expr,
                           Int_Expr (1, Expr.Span),
                           Expr.Span,
                           UString_Value (Map_Type.Name),
                           Binary_Expr
                             (Length_Temp,
                              "-",
                              Int_Expr (1, Expr.Span),
                              Expr.Span,
                              UString_Value (Default_Integer.Name))),
                        Expr.Span));
                  Prefix_Then.Append
                    (Synthetic_Assign_Stmt
                       (Map_Child.Expr,
                        Last_Literal_Expr,
                        Expr.Span));
                  Prefix_Else.Append
                    (Synthetic_Assign_Stmt
                       (Map_Child.Expr,
                        Binary_Expr
                          (Resolved_Index_Expr
                             (Snapshot_Expr,
                              Int_Expr (1, Expr.Span),
                              Expr.Span,
                              UString_Value (Map_Type.Name),
                              Binary_Expr
                                (Index_Temp,
                                 "-",
                                 Int_Expr (1, Expr.Span),
                                 Expr.Span,
                                 UString_Value (Default_Integer.Name))),
                           "&",
                           Last_Literal_Expr,
                           Expr.Span,
                           UString_Value (Map_Type.Name)),
                        Expr.Span));
                  Rebuild_Then.Append
                    (Synthetic_If_Else_Stmt
                       (Binary_Expr
                          (Index_Temp,
                           "==",
                           Int_Expr (1, Expr.Span),
                           Expr.Span,
                           "boolean"),
                        Prefix_Then,
                        Prefix_Else,
                        Expr.Span));
                  Suffix_Then.Append
                    (Synthetic_Assign_Stmt
                       (Map_Child.Expr,
                        Binary_Expr
                          (Map_Child.Expr,
                           "&",
                           Resolved_Index_Expr
                             (Snapshot_Expr,
                              Binary_Expr
                                (Index_Temp,
                                 "+",
                                 Int_Expr (1, Expr.Span),
                                 Expr.Span,
                                 UString_Value (Default_Integer.Name)),
                              Expr.Span,
                              UString_Value (Map_Type.Name),
                              Binary_Expr
                                (Length_Temp,
                                 "-",
                                 Int_Expr (1, Expr.Span),
                                 Expr.Span,
                                 UString_Value (Default_Integer.Name))),
                           Expr.Span,
                           UString_Value (Map_Type.Name)),
                        Expr.Span));
                  Rebuild_Then.Append
                    (Synthetic_If_Stmt
                       (Binary_Expr
                          (Index_Temp,
                           "<",
                           Binary_Expr
                             (Length_Temp,
                              "-",
                              Int_Expr (1, Expr.Span),
                              Expr.Span,
                              UString_Value (Default_Integer.Name)),
                           Expr.Span,
                           "boolean"),
                        Suffix_Then,
                        Expr.Span));
                  Match_Then.Append
                    (Synthetic_If_Stmt
                       (Binary_Expr
                          (Length_Temp,
                           "==",
                           Int_Expr (1, Expr.Span),
                           Expr.Span,
                           "boolean"),
                        Trim_Then,
                        Expr.Span));
                  Match_Then.Append
                    (Synthetic_If_Stmt
                       (Binary_Expr
                          (Binary_Expr
                             (Length_Temp,
                              ">",
                              Int_Expr (1, Expr.Span),
                              Expr.Span,
                              "boolean"),
                           "and then",
                           Binary_Expr
                             (Index_Temp,
                              "==",
                              Length_Temp,
                              Expr.Span,
                              "boolean"),
                           Expr.Span,
                           "boolean"),
                        Trim_Else,
                        Expr.Span));
                  Match_Then.Append
                    (Synthetic_If_Stmt
                       (Binary_Expr
                          (Binary_Expr
                             (Length_Temp,
                              ">",
                              Int_Expr (1, Expr.Span),
                              Expr.Span,
                              "boolean"),
                           "and then",
                           Binary_Expr
                             (Index_Temp,
                              "<",
                              Length_Temp,
                              Expr.Span,
                              "boolean"),
                           Expr.Span,
                           "boolean"),
                        Rebuild_Then,
                        Expr.Span));
                  Match_Then.Append
                    (Synthetic_Exit_Stmt (Expr.Span));
                  Loop_Body.Append
                    (Synthetic_Object_Decl_Stmt
                       (UString_Value (Entry_Name),
                        Entry_Type,
                        Resolved_Index_Expr
                          (Snapshot_Expr,
                           Index_Temp,
                           Expr.Span,
                           UString_Value (Entry_Type.Name)),
                        Expr.Span));
                  Loop_Body.Append
                    (Synthetic_If_Stmt
                       (Binary_Expr
                          (Selector_Expr
                             (Entry_Expr,
                              "1",
                              Expr.Span,
                              UString_Value (Key_Type.Name)),
                           "==",
                           Key_Temp,
                           Expr.Span,
                           "boolean"),
                        Match_Then,
                        Expr.Span));
                  Advance_Then.Append
                    (Synthetic_Assign_Stmt
                       (Index_Temp,
                        Binary_Expr
                          (Index_Temp,
                           "+",
                           Int_Expr (1, Expr.Span),
                           Expr.Span,
                           UString_Value (Default_Integer.Name)),
                        Expr.Span));
                  Advance_Else.Append
                    (Synthetic_Exit_Stmt (Expr.Span));
                  Loop_Body.Append
                    (Synthetic_If_Else_Stmt
                       (Binary_Expr
                          (Index_Temp,
                           "<",
                           Length_Temp,
                           Expr.Span,
                           "boolean"),
                        Advance_Then,
                        Advance_Else,
                        Expr.Span));
                  Result.Preludes.Append
                    (Synthetic_While_Stmt
                       (Binary_Expr
                          (Index_Temp,
                           "<=",
                           Length_Temp,
                           Expr.Span,
                           "boolean"),
                        Loop_Body,
                        Expr.Span));
                  Result.Expr := Result_Temp;
                  return Result;
               end;
            end if;
            if Is_Append_Builtin_Call (Expr, Var_Types, Functions, Type_Env) then
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path,
                     Span    => (if Expr.Has_Call_Span then Expr.Call_Span else Expr.Span),
                     Message => "`append(items, value)` mutates a writable list and must be used as a statement"));
            end if;
            if Is_Set_Builtin_Call (Expr, Var_Types, Functions, Type_Env) then
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path,
                     Span    => (if Expr.Has_Call_Span then Expr.Call_Span else Expr.Span),
                     Message => "`set(m, key, value)` mutates a writable map and must be used as a statement"));
            end if;
            Result.Expr := new CM.Expr_Node'(Expr.all);
            Result.Expr.Args.Clear;
            Child :=
              Desugar_Executable_Expr
                (Expr.Callee,
                 Var_Types,
                 Functions,
                 Type_Env,
                 Has_Enclosing_Return,
                 Enclosing_Return_Type,
                 Path,
                 Reject_Short_Circuit_Try);
            Result.Expr.Callee := Child.Expr;
            Result.Preludes := Child.Preludes;
            for Item of Expr.Args loop
               Child :=
                 Desugar_Executable_Expr
                   (Item,
                    Var_Types,
                    Functions,
                    Type_Env,
                    Has_Enclosing_Return,
                    Enclosing_Return_Type,
                    Path,
                    Reject_Short_Circuit_Try);
               Append_Statements (Result.Preludes, Child.Preludes);
               Result.Expr.Args.Append (Child.Expr);
            end loop;

         when CM.Expr_Conversion | CM.Expr_Annotated | CM.Expr_Unary =>
            Result.Expr := new CM.Expr_Node'(Expr.all);
            Child :=
              Desugar_Executable_Expr
                (Expr.Inner,
                 Var_Types,
                 Functions,
                 Type_Env,
                 Has_Enclosing_Return,
                 Enclosing_Return_Type,
                 Path,
                 Reject_Short_Circuit_Try);
            Result.Expr.Inner := Child.Expr;
            Result.Preludes := Child.Preludes;

         when CM.Expr_Binary =>
            Result.Expr := new CM.Expr_Node'(Expr.all);
            Left_Result :=
              Desugar_Executable_Expr
                (Expr.Left,
                 Var_Types,
                 Functions,
                 Type_Env,
                 Has_Enclosing_Return,
                 Enclosing_Return_Type,
                 Path,
                 Reject_Short_Circuit_Try);
            Conditional_Right := Reject_Short_Circuit_Try
              or else UString_Value (Expr.Operator) in "and then" | "or else";
            Right_Result :=
              Desugar_Executable_Expr
                (Expr.Right,
                 Var_Types,
                 Functions,
                 Type_Env,
                 Has_Enclosing_Return,
                 Enclosing_Return_Type,
                 Path,
                 Conditional_Right);
            Result.Expr.Left := Left_Result.Expr;
            Result.Expr.Right := Right_Result.Expr;
            Result.Preludes := Left_Result.Preludes;
            Append_Statements (Result.Preludes, Right_Result.Preludes);

         when CM.Expr_Aggregate =>
            Result.Expr := new CM.Expr_Node'(Expr.all);
            Result.Expr.Fields.Clear;
            for Item of Expr.Fields loop
               declare
                  New_Field : CM.Aggregate_Field := Item;
               begin
                  Child :=
                    Desugar_Executable_Expr
                      (Item.Expr,
                       Var_Types,
                       Functions,
                       Type_Env,
                       Has_Enclosing_Return,
                       Enclosing_Return_Type,
                       Path,
                       Reject_Short_Circuit_Try);
                  Append_Statements (Result.Preludes, Child.Preludes);
                  New_Field.Expr := Child.Expr;
                  Result.Expr.Fields.Append (New_Field);
               end;
            end loop;

         when CM.Expr_Array_Literal | CM.Expr_Tuple =>
            Result.Expr := new CM.Expr_Node'(Expr.all);
            Result.Expr.Elements.Clear;
            for Item of Expr.Elements loop
               Child :=
                 Desugar_Executable_Expr
                   (Item,
                    Var_Types,
                    Functions,
                    Type_Env,
                    Has_Enclosing_Return,
                    Enclosing_Return_Type,
                    Path,
                    Reject_Short_Circuit_Try);
               Append_Statements (Result.Preludes, Child.Preludes);
               Result.Expr.Elements.Append (Child.Expr);
            end loop;

         when others =>
            Result.Expr := new CM.Expr_Node'(Expr.all);
      end case;

      return Result;
   end Desugar_Executable_Expr;

   function Normalize_Statement
     (Stmt        : CM.Statement_Access;
      Var_Types   : Type_Maps.Map;
      Functions   : Function_Maps.Map;
      Type_Env    : Type_Maps.Map;
      Channel_Env : Type_Maps.Map;
      Imported_Objects : Type_Maps.Map;
      Local_Constants : Type_Maps.Map;
      Local_Static_Constants : Static_Value_Maps.Map;
      Exact_Length_Facts : Exact_Length_Maps.Map;
      Path        : String;
      Has_Enclosing_Return : Boolean := False;
      Enclosing_Return_Type : GM.Type_Descriptor := (others => <>)) return CM.Statement_Access_Vectors.Vector;

   function Normalize_Statement_List
     (Statements  : CM.Statement_Access_Vectors.Vector;
      Var_Types   : Type_Maps.Map;
      Functions   : Function_Maps.Map;
      Type_Env    : Type_Maps.Map;
      Channel_Env : Type_Maps.Map;
      Imported_Objects : Type_Maps.Map;
      Local_Constants : Type_Maps.Map;
      Local_Static_Constants : Static_Value_Maps.Map;
      Exact_Length_Facts : Exact_Length_Maps.Map;
      Path        : String;
      Has_Enclosing_Return : Boolean := False;
      Enclosing_Return_Type : GM.Type_Descriptor := (others => <>)) return CM.Statement_Access_Vectors.Vector
   is
      Result      : CM.Statement_Access_Vectors.Vector;
      Local_Types : Type_Maps.Map := Var_Types;
      Current_Constants : Type_Maps.Map := Local_Constants;
      Current_Static_Constants : Static_Value_Maps.Map := Local_Static_Constants;
      Current_Exact_Length_Facts : Exact_Length_Maps.Map := Exact_Length_Facts;
   begin
      for Item of Statements loop
         declare
            Normalized_Items : constant CM.Statement_Access_Vectors.Vector :=
              Normalize_Statement
                (Item,
                 Local_Types,
                 Functions,
                 Type_Env,
                 Channel_Env,
                 Imported_Objects,
                 Current_Constants,
                 Current_Static_Constants,
                 Current_Exact_Length_Facts,
                 Path,
                 Has_Enclosing_Return,
                 Enclosing_Return_Type);
         begin
            for Normalized of Normalized_Items loop
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
                     Remove_Exact_Length_Fact (Current_Exact_Length_Facts, UString_Value (Name));
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
                        Remove_Exact_Length_Fact
                          (Current_Exact_Length_Facts,
                           UString_Value (Normalized.Destructure.Names (Index)));
                     end loop;
                  end;
               elsif Normalized.Kind = CM.Stmt_Assign then
                  Remove_Exact_Length_Fact
                    (Current_Exact_Length_Facts,
                     Exact_Length_Fact_Name (Normalized.Target));
               elsif Normalized.Kind = CM.Stmt_Call
                 and then Normalized.Call /= null
                 and then Has_Function (Functions, Flatten_Name (Normalized.Call.Callee))
               then
                  declare
                     Info : constant Function_Info :=
                       Get_Function (Functions, Flatten_Name (Normalized.Call.Callee));
                  begin
                     for Index in Info.Params.First_Index .. Info.Params.Last_Index loop
                        exit when Index > Normalized.Call.Args.Last_Index;
                        if UString_Value (Info.Params (Index).Mode) = "mut" then
                           Remove_Exact_Length_Fact
                             (Current_Exact_Length_Facts,
                              Exact_Length_Fact_Name (Normalized.Call.Args (Index)));
                        end if;
                     end loop;
                  end;
               elsif Normalized.Kind in CM.Stmt_Receive | CM.Stmt_Try_Receive then
                  Remove_Exact_Length_Fact
                    (Current_Exact_Length_Facts,
                     Exact_Length_Fact_Name (Normalized.Target));
               end if;
            end loop;
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
      Exact_Length_Facts : Exact_Length_Maps.Map;
      Path        : String;
      Has_Enclosing_Return : Boolean := False;
      Enclosing_Return_Type : GM.Type_Descriptor := (others => <>)) return CM.Statement_Access_Vectors.Vector
   is
      Expanded       : CM.Statement_Access_Vectors.Vector;
      Result         : constant CM.Statement_Access := new CM.Statement'(Stmt.all);
      Local_Types    : Type_Maps.Map := Var_Types;
      Current_Constants : Type_Maps.Map := Local_Constants;
      Current_Static_Constants : Static_Value_Maps.Map := Local_Static_Constants;
      Loop_Type      : GM.Type_Descriptor;
      Decl_Type      : GM.Type_Descriptor;
      Channel_Type   : GM.Type_Descriptor;
      Success_Type   : GM.Type_Descriptor;
      Target_Type    : GM.Type_Descriptor;
      function Normalize_Preludes
        (Preludes : CM.Statement_Access_Vectors.Vector) return CM.Statement_Access_Vectors.Vector
      is
      begin
         if Preludes.Is_Empty then
            return Preludes;
         end if;

         return
           Normalize_Statement_List
             (Preludes,
              Var_Types,
              Functions,
              Type_Env,
              Channel_Env,
              Imported_Objects,
              Local_Constants,
              Local_Static_Constants,
              Exact_Length_Facts,
              Path,
              Has_Enclosing_Return,
              Enclosing_Return_Type);
      end Normalize_Preludes;

      function Desugar_Checked
        (Expr              : CM.Expr_Access;
         Append_To_Expanded : Boolean := True) return Desugared_Expr_Result
      is
         Desugared : constant Desugared_Expr_Result :=
           Desugar_Executable_Expr
             (Normalize_Expr_Checked
                (Expr,
                 Var_Types,
                 Functions,
                 Type_Env,
                 Local_Static_Constants,
                 Path,
                 Allow_Try => True),
              Var_Types,
              Functions,
              Type_Env,
              Has_Enclosing_Return,
              Enclosing_Return_Type,
              Path);
      begin
         if Append_To_Expanded then
            Append_Statements (Expanded, Normalize_Preludes (Desugared.Preludes));
         end if;
         return Desugared;
      end Desugar_Checked;

      procedure Build_Shared_Setter_Call
        (Shared          : Shared_Object_Ref;
         Setter_Name     : String;
         Shared_Field_Type : GM.Type_Descriptor;
         Value_Expr      : CM.Expr_Access)
      is
         Setter_Arg : CM.Expr_Access;
      begin
         Result.Kind := CM.Stmt_Call;
         Result.Target := null;
         Result.Value := null;
         Result.Call :=
           Shared_Call_Expr
             (Shared,
              Setter_Name,
              Stmt.Target.Span);
         Result.Call.Args.Append
           (Validate_And_Contextualize_Value
              (Value_Expr,
               Shared_Field_Type,
               Var_Types,
               Functions,
               Type_Env,
               Local_Static_Constants,
               Exact_Length_Facts,
               Path,
               "assignment value type does not match target type",
               Stamp_String_Literal => False));
         Setter_Arg := Result.Call.Args (Result.Call.Args.First_Index);
         --  Validation intentionally runs before the shared-setter-side
         --  Type_Name stamping below. Shared field setters keep the
         --  pre-refactor behavior: no contextual string stamping during
         --  compatibility checks. The later Type_Name update is
         --  emission-only; it does not affect Reject_Uncontextualized_None.
         if UString_Value (Setter_Arg.Type_Name)'Length = 0
           and then UString_Value (Shared_Field_Type.Name)'Length > 0
         then
            Setter_Arg.Type_Name := Shared_Field_Type.Name;
         elsif Setter_Arg.Kind = CM.Expr_String
           and then
             (Is_Bounded_String_Type (Shared_Field_Type, Type_Env)
              or else Is_String_Type (Shared_Field_Type, Type_Env))
         then
            Setter_Arg.Type_Name := Shared_Field_Type.Name;
         end if;
         Reject_Static_Bounded_String_Overflow
           (Setter_Arg,
            Shared_Field_Type,
            Type_Env,
            Path,
            Setter_Arg.Span);
      end Build_Shared_Setter_Call;

      procedure Reject_Imported_Channel_Elaboration
        (Channel_Expr    : CM.Expr_Access;
         Diagnostic_Span : FT.Source_Span) is
         Effective_Span : FT.Source_Span := Diagnostic_Span;
      begin
         if Channel_Expr /= null then
            Effective_Span := Channel_Expr.Span;
         end if;

         if In_Unit_Statement_Context
           and then Is_Imported_Channel_Reference (Channel_Expr)
         then
            Raise_Diag
              (CM.Source_Frontend_Error
                 (Path    => Path,
                  Span    => Effective_Span,
                  Message =>
                    "unit-scope elaboration must not perform imported channel operations; move this operation into a task body or another non-elaboration call path"));
         end if;
      end Reject_Imported_Channel_Elaboration;
   begin
      case Stmt.Kind is
         when CM.Stmt_Object_Decl =>
            if Stmt.Decl.Has_Initializer and then Stmt.Decl.Initializer /= null then
               declare
                  Temp_Decl : CM.Object_Decl := Stmt.Decl;
                  Desugared : constant Desugared_Expr_Result :=
                    Desugar_Checked (Stmt.Decl.Initializer);
               begin
                  Temp_Decl.Initializer := Desugared.Expr;
                  Result.Decl :=
                    Normalize_Object_Decl
                      (Temp_Decl,
                       Var_Types,
                       Functions,
                       Type_Env,
                       Local_Static_Constants,
                       Exact_Length_Facts,
                       Path);
               end;
            else
               Result.Decl :=
                 Normalize_Object_Decl
                   (Stmt.Decl,
                    Var_Types,
                    Functions,
                    Type_Env,
                    Local_Static_Constants,
                    Exact_Length_Facts,
                    Path);
            end if;

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
            declare
               Desugared : constant Desugared_Expr_Result :=
                 Desugar_Checked (Stmt.Destructure.Initializer);
            begin
               Result.Destructure.Initializer :=
                 Contextualize_Expr_To_Target_Type
                   (Desugared.Expr,
                    Result.Destructure.Type_Info,
                    Var_Types,
                    Functions,
                    Type_Env,
                    Path);
               Reject_Uncontextualized_None (Result.Destructure.Initializer, Path);
            end;
            Reject_Static_Bounded_String_Overflow
              (Result.Destructure.Initializer,
               Result.Destructure.Type_Info,
               Type_Env,
               Path,
               Result.Destructure.Initializer.Span);
            if not Compatible_Source_Expr_To_Target_Type
              (Result.Destructure.Initializer,
               Expr_Type (Result.Destructure.Initializer, Var_Types, Functions, Type_Env),
               Result.Destructure.Type_Info,
               Var_Types,
               Functions,
               Type_Env,
               Local_Static_Constants,
               Exact_Length_Facts)
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
            declare
               Shared            : Shared_Object_Ref;
               Shared_Path       : FT.UString_Vectors.Vector;
               Shared_Field_Type : GM.Type_Descriptor;
               Desugared         : Desugared_Expr_Result;
               Setter_Call       : CM.Expr_Access;
               Target_Info       : GM.Type_Descriptor;
               Shared_Root_Type  : GM.Type_Descriptor;
            begin
               if Try_Shared_Root_Expr
                 (Stmt.Target,
                  Shared)
               then
                  Shared_Root_Type := Shared.Type_Info;
                  Desugared := Desugar_Checked (Stmt.Value);
                  Result.Kind := CM.Stmt_Call;
                  Result.Target := null;
                  Result.Value := null;
                  Setter_Call :=
                    Shared_Call_Expr
                      (Shared,
                       Shared_Set_All_Name,
                       Stmt.Target.Span);
                  Result.Call := Setter_Call;
                  Result.Call.Args.Append
                    (Contextualize_Expr_To_Target_Type
                       (Desugared.Expr,
                        Shared_Root_Type,
                        Var_Types,
                        Functions,
                        Type_Env,
                        Path));
                  if not Result.Call.Args.Is_Empty
                    and then Result.Call.Args (Result.Call.Args.First_Index) /= null
                    and then UString_Value (Shared_Root_Type.Name)'Length > 0
                    and then Result.Call.Args (Result.Call.Args.First_Index).Kind in
                      CM.Expr_Aggregate | CM.Expr_Array_Literal | CM.Expr_Tuple
                  then
                     Result.Call.Args (Result.Call.Args.First_Index).Type_Name :=
                       Shared_Root_Type.Name;
                  end if;
                  Reject_Uncontextualized_None
                    (Result.Call.Args (Result.Call.Args.First_Index), Path);
                  Reject_Static_Bounded_String_Overflow
                    (Result.Call.Args (Result.Call.Args.First_Index),
                     Shared_Root_Type,
                     Type_Env,
                     Path,
                     Result.Call.Args (Result.Call.Args.First_Index).Span);
                  if not Compatible_Source_Expr_To_Target_Type
                    (Result.Call.Args (Result.Call.Args.First_Index),
                     Expr_Type
                       (Result.Call.Args (Result.Call.Args.First_Index),
                        Var_Types,
                        Functions,
                        Type_Env),
                     Shared_Root_Type,
                     Var_Types,
                     Functions,
                     Type_Env,
                     Local_Static_Constants,
                     Exact_Length_Facts)
                  then
                     Raise_Diag
                       (CM.Source_Frontend_Error
                          (Path    => Path,
                           Span    => Result.Call.Args (Result.Call.Args.First_Index).Span,
                           Message => "assignment value type does not match target type"));
                  end if;
               elsif Try_Shared_Top_Level_Field_Access
                 (Stmt.Target,
                  Type_Env,
                  Shared,
                  Shared_Field_Type)
               then
                  Desugared := Desugar_Checked (Stmt.Value);
                  Build_Shared_Setter_Call
                    (Shared,
                     Shared_Field_Setter_Name (UString_Value (Stmt.Target.Selector)),
                     Shared_Field_Type,
                     Desugared.Expr);
               elsif Try_Shared_Nested_Field_Access
                 (Stmt.Target,
                  Type_Env,
                  Shared,
                  Shared_Path,
                  Shared_Field_Type)
               then
                  Desugared := Desugar_Checked (Stmt.Value);
                  Build_Shared_Setter_Call
                    (Shared,
                     Shared_Nested_Field_Setter_Name (Shared_Path),
                     Shared_Field_Type,
                     Desugared.Expr);
               elsif Try_Shared_Target_Expr
                 (Stmt.Target,
                  Shared)
               then
                  declare
                     Shared_Root_Type : constant GM.Type_Descriptor := Shared.Type_Info;
                  begin
                     if Is_Shared_Container_Root_Type (Shared_Root_Type, Type_Env) then
                        Raise_Diag
                          (CM.Unsupported_Source_Construct
                             (Path    => Path,
                              Span    => Stmt.Target.Span,
                              Message =>
                                "live shared container writes are limited to"
                                & " whole-root assignment and admitted builtin"
                                & " operations in PR11.12d; snapshot the shared"
                                & " value first for indexing or slicing"));
                     else
                        Raise_Diag
                          (CM.Unsupported_Source_Construct
                             (Path    => Path,
                              Span    => Stmt.Target.Span,
                              Message =>
                                "nested writes on shared record variables are limited to selector paths in PR11.12b"));
                     end if;
                  end;
               else
                  Result.Target :=
                    Normalize_Expr_Checked
                      (Stmt.Target, Var_Types, Functions, Type_Env, Local_Static_Constants, Path);
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
                     Local_Static_Constants,
                     Path,
                     "assignment to imported package-qualified objects is outside the current PR08.3 interface subset");
                  Target_Info :=
                    Expr_Type (Result.Target, Var_Types, Functions, Type_Env);
                  declare
                     Target_Expr : constant CM.Expr_Access := Result.Target;
                     Normalized_Value : constant CM.Expr_Access :=
                       Normalize_Expr_Checked
                         (Stmt.Value,
                          Var_Types,
                          Functions,
                          Type_Env,
                          Local_Static_Constants,
                          Path,
                          Allow_Try => True);
                     Shared_Root_Type : GM.Type_Descriptor;
                     Shared_Result    : Shared_Object_Ref;
                     Selector_Name    : constant String :=
                       (if Normalized_Value /= null
                           and then Normalized_Value.Kind = CM.Expr_Call
                           and then Normalized_Value.Callee /= null
                        then
                          (if Normalized_Value.Callee.Kind = CM.Expr_Select
                           then Canonical_Name (UString_Value (Normalized_Value.Callee.Selector))
                           else Canonical_Name (UString_Value (Normalized_Value.Callee.Name)))
                        else "");
                     Has_Shared_Call : Boolean := False;
                     Shared_Operation : FT.UString := FT.To_UString ("");
                  begin
                     if Normalized_Value /= null
                       and then Normalized_Value.Kind = CM.Expr_Call
                       and then Normalized_Value.Callee /= null
                     then
                        if Try_Shared_Wrapper_Root_Name_Expr
                          ((if Normalized_Value.Callee.Kind = CM.Expr_Select
                            then Normalized_Value.Callee.Prefix
                            else null),
                           Shared_Result.Root_Name,
                           Shared_Root_Type)
                        then
                           Has_Shared_Call := True;
                           if Selector_Name = Canonical_Name (Shared_Pop_Last_Name) then
                              Shared_Operation := FT.To_UString (Shared_Pop_Last_Name);
                           elsif Selector_Name = Canonical_Name (Shared_Remove_Name) then
                              Shared_Operation := FT.To_UString (Shared_Remove_Name);
                           end if;
                        elsif Try_Shared_Public_Helper_Call
                          (Normalized_Value.Callee,
                           Shared_Pop_Last_Name,
                           Shared_Result)
                        then
                           Has_Shared_Call := True;
                           Shared_Operation := FT.To_UString (Shared_Pop_Last_Name);
                        elsif Try_Shared_Public_Helper_Call
                          (Normalized_Value.Callee,
                           Shared_Remove_Name,
                           Shared_Result)
                        then
                           Has_Shared_Call := True;
                           Shared_Operation := FT.To_UString (Shared_Remove_Name);
                        end if;
                     end if;

                     if Has_Shared_Call
                       and then
                         ((UString_Value (Shared_Operation) = Shared_Pop_Last_Name
                           and then Normalized_Value.Args.Is_Empty)
                          or else
                          (UString_Value (Shared_Operation) = Shared_Remove_Name
                           and then Natural (Normalized_Value.Args.Length) = 1))
                     then
                        if Shared_Result.Kind /= Shared_Object_None then
                           Shared_Root_Type := Shared_Result.Type_Info;
                        end if;
                        if not Compatible_Source_Expr_To_Target_Type
                          (Normalized_Value,
                           Expr_Type (Normalized_Value, Var_Types, Functions, Type_Env),
                           Target_Info,
                           Var_Types,
                           Functions,
                           Type_Env,
                           Local_Static_Constants,
                           Exact_Length_Facts)
                        then
                           Raise_Diag
                             (CM.Source_Frontend_Error
                                (Path    => Path,
                                 Span    => Normalized_Value.Span,
                                 Message => "assignment value type does not match target type"));
                        end if;

                        Result.Kind := CM.Stmt_Call;
                        Result.Target := null;
                        Result.Value := null;
                        Result.Call := new CM.Expr_Node'(Normalized_Value.all);
                        if UString_Value (Shared_Operation) = Shared_Remove_Name then
                           declare
                              Key_Desugared : constant Desugared_Expr_Result :=
                                Desugar_Executable_Expr
                                  (Normalized_Value.Args (Normalized_Value.Args.First_Index),
                                   Var_Types,
                                   Functions,
                                   Type_Env,
                                   Has_Enclosing_Return,
                                   Enclosing_Return_Type,
                                   Path);
                           begin
                              Append_Statements
                                (Expanded,
                                 Normalize_Preludes (Key_Desugared.Preludes));
                              Result.Call.Args.Clear;
                              Result.Call.Args.Append (Key_Desugared.Expr);
                           end;
                        else
                           Result.Call.Args.Clear;
                        end if;
                        Result.Call.Args.Append (Target_Expr);
                        Expanded.Append (Result);
                        return Expanded;
                     end if;

                     Desugared :=
                       Desugar_Executable_Expr
                         (Normalized_Value,
                          Var_Types,
                          Functions,
                          Type_Env,
                          Has_Enclosing_Return,
                          Enclosing_Return_Type,
                          Path);
                     Append_Statements (Expanded, Normalize_Preludes (Desugared.Preludes));
                     Result.Value :=
                       Contextualize_Expr_To_Target_Type
                         (Desugared.Expr,
                          Target_Info,
                          Var_Types,
                          Functions,
                          Type_Env,
                          Path);
                  end;
                  Reject_Uncontextualized_None (Result.Value, Path);
                  if Result.Value.Kind = CM.Expr_Resolved_Index
                    and then Result.Value.Prefix /= null
                  then
                     declare
                        Target_Base   : constant GM.Type_Descriptor :=
                          Base_Type (Target_Info, Type_Env);
                        Prefix_Base   : constant GM.Type_Descriptor :=
                          Base_Type
                            (Expr_Type
                               (Result.Value.Prefix,
                                Var_Types,
                                Functions,
                                Type_Env),
                             Type_Env);
                        Target_Length : Natural := 0;
                        Source_Length : Natural := 0;
                     begin
                        if FT.Lowercase (UString_Value (Target_Base.Kind)) = "array"
                          and then not Target_Base.Growable
                          and then FT.Lowercase (UString_Value (Prefix_Base.Kind)) = "array"
                          and then Prefix_Base.Growable
                          and then Fixed_Array_Cardinality (Target_Base, Type_Env, Target_Length)
                          and then Static_Growable_Length
                            (Result.Value,
                             Var_Types,
                             Functions,
                             Type_Env,
                             Local_Static_Constants,
                             Source_Length)
                          and then Source_Length = Target_Length
                        then
                           Result.Value.Type_Name := Target_Info.Name;
                        end if;
                     end;
                  end if;
                  if Static_Growable_To_Fixed_Narrowing_OK
                    (Result.Value,
                     Target_Info,
                     Var_Types,
                     Functions,
                     Type_Env,
                     Local_Static_Constants,
                     Exact_Length_Facts)
                  then
                     Result.Value.Type_Name := Target_Info.Name;
                  end if;
                  Reject_Static_Bounded_String_Overflow
                    (Result.Value,
                     Expr_Type (Result.Target, Var_Types, Functions, Type_Env),
                     Type_Env,
                     Path,
                     Result.Value.Span);
                  if not Compatible_Source_Expr_To_Target_Type
                    (Result.Value,
                     Expr_Type (Result.Value, Var_Types, Functions, Type_Env),
                     Expr_Type (Result.Target, Var_Types, Functions, Type_Env),
                     Var_Types,
                     Functions,
                     Type_Env,
                     Local_Static_Constants,
                     Exact_Length_Facts)
                  then
                     Raise_Diag
                       (CM.Source_Frontend_Error
                          (Path    => Path,
                           Span    => Result.Value.Span,
                           Message => "assignment value type does not match target type"));
                  end if;
               end if;
            end;

         when CM.Stmt_Return =>
            if Stmt.Value /= null then
               declare
                  Desugared : constant Desugared_Expr_Result :=
                    Desugar_Checked (Stmt.Value);
               begin
                  Result.Value :=
                    Contextualize_Expr_To_Target_Type
                      (Desugared.Expr,
                       Enclosing_Return_Type,
                       Var_Types,
                       Functions,
                       Type_Env,
                       Path);
                  Reject_Uncontextualized_None (Result.Value, Path);
               end;
            end if;

         when CM.Stmt_If =>
            declare
               Desugared : constant Desugared_Expr_Result :=
                 Desugar_Checked (Stmt.Condition);
               Then_Exact_Length_Facts : Exact_Length_Maps.Map := Exact_Length_Facts;
               Guard_Name : FT.UString := FT.To_UString ("");
               Guard_Length : Natural := 0;
            begin
               Result.Condition := Desugared.Expr;
               if Try_Direct_Growable_Length_Guard
                 (Result.Condition,
                  Var_Types,
                  Functions,
                  Type_Env,
                  Guard_Name,
                  Guard_Length)
               then
                  Then_Exact_Length_Facts.Include
                    (Canonical_Name (UString_Value (Guard_Name)), Guard_Length);
               end if;
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
                    Then_Exact_Length_Facts,
                    Path,
                    Has_Enclosing_Return,
                    Enclosing_Return_Type);
            end;
            Result.Elsifs.Clear;
            for Part of Stmt.Elsifs loop
               declare
                  New_Part : CM.Elsif_Part := Part;
                  Elsif_Exact_Length_Facts : Exact_Length_Maps.Map := Exact_Length_Facts;
                  Guard_Name : FT.UString := FT.To_UString ("");
                  Guard_Length : Natural := 0;
               begin
                  declare
                     Desugared : constant Desugared_Expr_Result :=
                       Desugar_Checked (Part.Condition);
                  begin
                     New_Part.Condition := Desugared.Expr;
                  end;
                  if Try_Direct_Growable_Length_Guard
                    (New_Part.Condition,
                     Var_Types,
                     Functions,
                     Type_Env,
                     Guard_Name,
                     Guard_Length)
                  then
                     Elsif_Exact_Length_Facts.Include
                       (Canonical_Name (UString_Value (Guard_Name)), Guard_Length);
                  end if;
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
                       Elsif_Exact_Length_Facts,
                       Path,
                       Has_Enclosing_Return,
                       Enclosing_Return_Type);
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
                    Exact_Length_Facts,
                    Path,
                    Has_Enclosing_Return,
                    Enclosing_Return_Type);
            end if;

         when CM.Stmt_While =>
            declare
               Desugared : constant Desugared_Expr_Result :=
                 Desugar_Checked (Stmt.Condition, Append_To_Expanded => False);
               Body_Exact_Length_Facts : Exact_Length_Maps.Map := Exact_Length_Facts;
               Guard_Name : FT.UString := FT.To_UString ("");
               Guard_Length : Natural := 0;
               Normalized_Body : CM.Statement_Access_Vectors.Vector;
               Exit_Stmt : CM.Statement_Access;
            begin
               if Try_Direct_Growable_Length_Guard
                 (Desugared.Expr,
                  Var_Types,
                  Functions,
                  Type_Env,
                  Guard_Name,
                  Guard_Length)
               then
                  Body_Exact_Length_Facts.Include
                    (Canonical_Name (UString_Value (Guard_Name)), Guard_Length);
               end if;
               Normalized_Body :=
                 Normalize_Statement_List
                   (Stmt.Body_Stmts,
                    Var_Types,
                    Functions,
                    Type_Env,
                    Channel_Env,
                    Imported_Objects,
                    Local_Constants,
                    Local_Static_Constants,
                    Body_Exact_Length_Facts,
                    Path,
                    Has_Enclosing_Return,
                    Enclosing_Return_Type);
               if Desugared.Preludes.Is_Empty then
                  Result.Condition := Desugared.Expr;
                  Result.Body_Stmts := Normalized_Body;
               else
                  Result.Kind := CM.Stmt_Loop;
                  Result.Condition := null;
                  Result.Body_Stmts.Clear;
                  Append_Statements (Result.Body_Stmts, Normalize_Preludes (Desugared.Preludes));
                  Exit_Stmt := new CM.Statement;
                  Exit_Stmt.Kind := CM.Stmt_Exit;
                  Exit_Stmt.Is_Synthetic := True;
                  Exit_Stmt.Span := Stmt.Condition.Span;
                  Exit_Stmt.Condition := Unary_Expr ("not", Desugared.Expr, Stmt.Condition.Span, "boolean");
                  Result.Body_Stmts.Append (Exit_Stmt);
                  Append_Statements (Result.Body_Stmts, Normalized_Body);
               end if;
            end;

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
                 Exact_Length_Facts,
                 Path,
                 Has_Enclosing_Return,
                 Enclosing_Return_Type);

         when CM.Stmt_Exit =>
            if Stmt.Condition /= null then
               declare
                  Desugared : constant Desugared_Expr_Result :=
                    Desugar_Checked (Stmt.Condition);
               begin
                  Result.Condition := Desugared.Expr;
               end;
            end if;

         when CM.Stmt_For =>
            if Stmt.Loop_Iterable /= null then
               declare
                  Iterable_Type : GM.Type_Descriptor;
                  Base_Type_Info : GM.Type_Descriptor;
                  Desugared : constant Desugared_Expr_Result :=
                    Desugar_Checked (Stmt.Loop_Iterable);
               begin
                  Result.Loop_Iterable := Desugared.Expr;
                  if not Is_Name_Expr (Result.Loop_Iterable) then
                     Raise_Diag
                       (CM.Source_Frontend_Error
                          (Path    => Path,
                           Span    => Result.Loop_Iterable.Span,
                           Message => "`for ... of` requires an array or string object name"));
                  end if;

                  declare
                     Shared      : Shared_Object_Ref;
                     Shared_Type : GM.Type_Descriptor;
                  begin
                     if Try_Shared_Root_Expr
                       (Result.Loop_Iterable,
                        Shared)
                     then
                        Shared_Type := Shared.Type_Info;
                        if Is_Shared_Container_Root_Type (Shared_Type, Type_Env) then
                           Raise_Diag
                             (CM.Unsupported_Source_Construct
                                (Path    => Path,
                                 Span    => Result.Loop_Iterable.Span,
                                 Message =>
                                   "live shared container iteration is outside PR11.12d; snapshot the shared value first"));
                        end if;
                     end if;
                  end;

                  Iterable_Type :=
                    Expr_Type (Result.Loop_Iterable, Var_Types, Functions, Type_Env);
                  Base_Type_Info := Base_Type (Iterable_Type, Type_Env);
                  if Is_String_Type (Base_Type_Info, Type_Env) then
                     Loop_Type := Make_Bounded_String_Type (1);
                  elsif not Is_Array_Type (Base_Type_Info, Type_Env) then
                     Raise_Diag
                       (CM.Source_Frontend_Error
                          (Path    => Path,
                           Span    => Result.Loop_Iterable.Span,
                           Message => "`for ... of` expects an array or string object"));
                  elsif not Base_Type_Info.Has_Component_Type then
                     Raise_Diag
                       (CM.Source_Frontend_Error
                          (Path    => Path,
                           Span    => Result.Loop_Iterable.Span,
                           Message => "array iteration requires an element type"));
                  elsif not Base_Type_Info.Growable
                    and then Natural (Base_Type_Info.Index_Types.Length) /= 1
                  then
                     Raise_Diag
                       (CM.Unsupported_Source_Construct
                          (Path    => Path,
                           Span    => Result.Loop_Iterable.Span,
                           Message => "`for ... of` currently supports only one-dimensional arrays"));
                  elsif not Base_Type_Info.Growable
                    and then not Is_Integerish
                      (Resolve_Type
                         (UString_Value (Base_Type_Info.Index_Types (Base_Type_Info.Index_Types.First_Index)),
                          Type_Env,
                          Path,
                          Result.Loop_Iterable.Span),
                       Type_Env)
                  then
                     Raise_Diag
                       (CM.Unsupported_Source_Construct
                          (Path    => Path,
                           Span    => Result.Loop_Iterable.Span,
                           Message => "`for ... of` currently supports only integer-indexed fixed arrays"));
                  else
                     Loop_Type :=
                       Resolve_Type
                         (UString_Value (Base_Type_Info.Component_Type),
                          Type_Env,
                          Path,
                          Result.Loop_Iterable.Span);
                  end if;
               end;
            else
               Result.Loop_Range := Stmt.Loop_Range;
               if Stmt.Loop_Range.Kind = CM.Range_Explicit then
                  declare
                     Low_Desugared : constant Desugared_Expr_Result :=
                       Desugar_Checked (Stmt.Loop_Range.Low_Expr);
                     High_Desugared : constant Desugared_Expr_Result :=
                       Desugar_Checked (Stmt.Loop_Range.High_Expr);
                  begin
                     Result.Loop_Range.Low_Expr := Low_Desugared.Expr;
                     Result.Loop_Range.High_Expr := High_Desugared.Expr;
                  end;
                  Loop_Type.Name := FT.To_UString ("integer");
                  Loop_Type.Kind := FT.To_UString ("integer");
               else
                  declare
                     Desugared : constant Desugared_Expr_Result :=
                       Desugar_Checked (Stmt.Loop_Range.Name_Expr);
                  begin
                     Result.Loop_Range.Name_Expr := Desugared.Expr;
                  end;
                  Loop_Type :=
                    Resolve_Type (Flatten_Name (Result.Loop_Range.Name_Expr), Type_Env, Path, Stmt.Span);
               end if;
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
                 Exact_Length_Facts,
                 Path,
                 Has_Enclosing_Return,
                 Enclosing_Return_Type);

         when CM.Stmt_Call =>
            declare
               Resolved_Call : constant CM.Expr_Access :=
                 (if Stmt.Call /= null and then Stmt.Call.Kind = CM.Expr_Apply
               then Resolve_Apply (Stmt.Call, Var_Types, Functions, Type_Env, Local_Static_Constants, Path)
               else Stmt.Call);
               Normalized_Call : constant CM.Expr_Access :=
                 Normalize_Expr
                   (Stmt.Call,
                    Var_Types,
                    Functions,
                    Type_Env,
                    Local_Static_Constants);
            begin
               if Resolved_Call /= null
                 and then Resolved_Call.Kind = CM.Expr_Call
                 and then not Resolved_Call.Args.Is_Empty
               then
                  declare
                     Shared      : Shared_Object_Ref;
                     Original_First_Arg : constant CM.Expr_Access :=
                       (if Stmt.Call /= null
                             and then Stmt.Call.Kind = CM.Expr_Apply
                             and then Stmt.Call.Callee /= null
                             and then Stmt.Call.Callee.Kind = CM.Expr_Select
                        then Stmt.Call.Callee.Prefix
                        elsif Stmt.Call /= null
                             and then not Stmt.Call.Args.Is_Empty
                        then Stmt.Call.Args (Stmt.Call.Args.First_Index)
                        else Resolved_Call.Args (Resolved_Call.Args.First_Index));
                     Shared_Type : GM.Type_Descriptor;
                  begin
                     if Try_Shared_Root_Expr
                       (Original_First_Arg,
                        Shared)
                     then
                        Shared_Type := Shared.Type_Info;
                        if Is_Shared_Container_Root_Type (Shared_Type, Type_Env) then
                           declare
                              Builtin_Kind : constant Builtin_Method_Kind :=
                                Builtin_Method_Kind_For_Call
                                  (Resolved_Call,
                                   Var_Types,
                                   Functions,
                                   Type_Env);
                           begin
                              if Builtin_Kind = Builtin_Append then
                                 declare
                                    Element_Type : GM.Type_Descriptor;
                                    Key_Type     : GM.Type_Descriptor;
                                    Value_Type   : GM.Type_Descriptor;
                                    Desugared    : Desugared_Expr_Result;
                                 begin
                                    if Natural (Resolved_Call.Args.Length) /= 2 then
                                       Raise_Diag
                                         (CM.Source_Frontend_Error
                                            (Path    => Path,
                                             Span    => (if Resolved_Call.Has_Call_Span
                                                         then Resolved_Call.Call_Span
                                                         else Resolved_Call.Span),
                                             Message => "`append(items, value)` expects exactly two arguments"));
                                    elsif not Is_Growable_Array_Type (Shared_Type, Type_Env)
                                      or else Try_Map_Key_Value_Types (Shared_Type, Type_Env, Key_Type, Value_Type)
                                    then
                                       Raise_Diag
                                         (CM.Source_Frontend_Error
                                            (Path    => Path,
                                             Span    => Resolved_Call.Args (Resolved_Call.Args.First_Index).Span,
                                             Message => "`append` expects a shared `list of T` or growable `array of T` root"));
                                    end if;

                                    Element_Type := Growable_Array_Element_Type (Shared_Type, Type_Env);
                                    if not Is_Container_Element_Type_Allowed (Element_Type, Type_Env) then
                                       Raise_Diag
                                         (CM.Unsupported_Source_Construct
                                            (Path    => Path,
                                             Span    => Resolved_Call.Args (Resolved_Call.Args.First_Index).Span,
                                             Message =>
                                               "`list of T` is limited to the admitted value-type subset in PR11.10b"));
                                    end if;

                                    Desugared :=
                                      Desugar_Checked
                                        (Resolved_Call.Args (Resolved_Call.Args.First_Index + 1));

                                    Result.Kind := CM.Stmt_Call;
                                    Result.Target := null;
                                    Result.Value := null;
                                    Result.Call :=
                                      Shared_Call_Expr
                                        (Shared,
                                         Shared_Append_Name,
                                         Stmt.Span);
                                    Result.Call.Args.Append
                                      (Validate_And_Contextualize_Value
                                         (Desugared.Expr,
                                          Element_Type,
                                          Var_Types,
                                          Functions,
                                          Type_Env,
                                          Local_Static_Constants,
                                          Exact_Length_Facts,
                                          Path,
                                          "`append` value type does not match the list element type"));
                                    Expanded.Append (Result);
                                    return Expanded;
                                 end;
                              elsif Builtin_Kind = Builtin_Set then
                                 declare
                                    Key_Type        : GM.Type_Descriptor;
                                    Value_Type      : GM.Type_Descriptor;
                                    Key_Desugared   : Desugared_Expr_Result;
                                    Value_Desugared : Desugared_Expr_Result;
                                 begin
                                    if Natural (Resolved_Call.Args.Length) /= 3 then
                                       Raise_Diag
                                         (CM.Source_Frontend_Error
                                            (Path    => Path,
                                             Span    => (if Resolved_Call.Has_Call_Span
                                                         then Resolved_Call.Call_Span
                                                         else Resolved_Call.Span),
                                             Message => "`set(m, key, value)` expects exactly three arguments"));
                                    elsif not Try_Map_Key_Value_Types (Shared_Type, Type_Env, Key_Type, Value_Type) then
                                       Raise_Diag
                                         (CM.Source_Frontend_Error
                                            (Path    => Path,
                                             Span    => Resolved_Call.Args (Resolved_Call.Args.First_Index).Span,
                                             Message => "`set` expects a shared `map of (K, V)` root"));
                                    elsif not Is_Map_Key_Type_Allowed (Key_Type, Type_Env) then
                                       Raise_Diag
                                         (CM.Unsupported_Source_Construct
                                            (Path    => Path,
                                             Span    => Resolved_Call.Args (Resolved_Call.Args.First_Index).Span,
                                             Message =>
                                               "`map of (K, V)` keys are limited to the admitted discrete/string subset in PR11.10c"));
                                    elsif not Is_Container_Element_Type_Allowed (Value_Type, Type_Env) then
                                       Raise_Diag
                                         (CM.Unsupported_Source_Construct
                                            (Path    => Path,
                                             Span    => Resolved_Call.Args (Resolved_Call.Args.First_Index).Span,
                                             Message =>
                                               "`map of (K, V)` values are limited to the admitted value-type subset in PR11.10c"));
                                    end if;

                                    Key_Desugared :=
                                      Desugar_Checked
                                        (Resolved_Call.Args (Resolved_Call.Args.First_Index + 1));
                                    Value_Desugared :=
                                      Desugar_Checked
                                        (Resolved_Call.Args (Resolved_Call.Args.First_Index + 2));

                                    Result.Kind := CM.Stmt_Call;
                                    Result.Target := null;
                                    Result.Value := null;
                                    Result.Call :=
                                      Shared_Call_Expr
                                        (Shared,
                                         Shared_Set_Name,
                                         Stmt.Span);
                                    Result.Call.Args.Append
                                      (Validate_And_Contextualize_Value
                                         (Key_Desugared.Expr,
                                          Key_Type,
                                          Var_Types,
                                          Functions,
                                          Type_Env,
                                          Local_Static_Constants,
                                          Exact_Length_Facts,
                                          Path,
                                          "`set` key type does not match the map key type"));
                                    Result.Call.Args.Append
                                      (Validate_And_Contextualize_Value
                                         (Value_Desugared.Expr,
                                          Value_Type,
                                          Var_Types,
                                          Functions,
                                          Type_Env,
                                          Local_Static_Constants,
                                          Exact_Length_Facts,
                                          Path,
                                          "`set` value type does not match the map value type"));
                                    Expanded.Append (Result);
                                    return Expanded;
                                 end;
                              elsif Builtin_Kind = Builtin_Pop_Last then
                                 Raise_Diag
                                   (CM.Source_Frontend_Error
                                      (Path    => Path,
                                       Span    => (if Resolved_Call.Has_Call_Span
                                                   then Resolved_Call.Call_Span
                                                   else Resolved_Call.Span),
                                       Message => "`pop_last(items)` returns an `optional T` value and must be used in an expression"));
                              elsif Builtin_Kind = Builtin_Contains then
                                 Raise_Diag
                                   (CM.Source_Frontend_Error
                                      (Path    => Path,
                                       Span    => (if Resolved_Call.Has_Call_Span
                                                   then Resolved_Call.Call_Span
                                                   else Resolved_Call.Span),
                                       Message => "`contains(m, key)` returns a `boolean` value and must be used in an expression"));
                              elsif Builtin_Kind = Builtin_Get then
                                 Raise_Diag
                                   (CM.Source_Frontend_Error
                                      (Path    => Path,
                                       Span    => (if Resolved_Call.Has_Call_Span
                                                   then Resolved_Call.Call_Span
                                                   else Resolved_Call.Span),
                                       Message => "`get(m, key)` returns an `optional V` value and must be used in an expression"));
                              elsif Builtin_Kind = Builtin_Remove then
                                 Raise_Diag
                                   (CM.Source_Frontend_Error
                                      (Path    => Path,
                                       Span    => (if Resolved_Call.Has_Call_Span
                                                   then Resolved_Call.Call_Span
                                                   else Resolved_Call.Span),
                                       Message => "`remove(m, key)` mutates a map and returns an `optional V` value, so it must be used in an expression"));
                              end if;
                           end;
                        end if;
                     end if;
                  end;
               end if;

               if Is_Append_Builtin_Call
                 (Normalized_Call, Var_Types, Functions, Type_Env)
               then
                  if Natural (Normalized_Call.Args.Length) /= 2 then
                     Raise_Diag
                       (CM.Source_Frontend_Error
                          (Path    => Path,
                           Span    => (if Normalized_Call.Has_Call_Span
                                       then Normalized_Call.Call_Span
                                       else Normalized_Call.Span),
                           Message => "`append(items, value)` expects exactly two arguments"));
                  else
                     declare
                        List_Target : constant CM.Expr_Access :=
                          Normalized_Call.Args (Normalized_Call.Args.First_Index);
                        Original_List_Target : constant CM.Expr_Access :=
                          (if Stmt.Call /= null
                                and then Stmt.Call.Kind = CM.Expr_Apply
                                and then Stmt.Call.Callee /= null
                                and then Stmt.Call.Callee.Kind = CM.Expr_Select
                           then Stmt.Call.Callee.Prefix
                           elsif Stmt.Call /= null
                                and then not Stmt.Call.Args.Is_Empty
                           then Stmt.Call.Args (Stmt.Call.Args.First_Index)
                           else List_Target);
                        Shared      : Shared_Object_Ref;
                        List_Type   : GM.Type_Descriptor :=
                          Expr_Type (List_Target, Var_Types, Functions, Type_Env);
                        Key_Type    : GM.Type_Descriptor := (others => <>);
                        Value_Type  : GM.Type_Descriptor := (others => <>);
                        Element_Type : GM.Type_Descriptor := (others => <>);
                        Appended_Value : CM.Expr_Access :=
                          Normalized_Call.Args (Normalized_Call.Args.First_Index + 1);
                        Literal : constant CM.Expr_Access := new CM.Expr_Node;
                        Rewritten : constant CM.Statement_Access := new CM.Statement;
                     begin
                        if Try_Shared_Root_Expr (Original_List_Target, Shared) then
                           List_Type := Shared.Type_Info;
                           if not Is_Growable_Array_Type (List_Type, Type_Env)
                             or else Try_Map_Key_Value_Types
                               (List_Type,
                                Type_Env,
                                Key_Type,
                                Value_Type)
                           then
                              Raise_Diag
                                (CM.Source_Frontend_Error
                                   (Path    => Path,
                                    Span    => List_Target.Span,
                                    Message =>
                                      "`append` expects a shared `list of T` or growable `array of T` root"));
                           end if;
                           Element_Type := Growable_Array_Element_Type (List_Type, Type_Env);
                           if not Is_Container_Element_Type_Allowed
                             (Element_Type, Type_Env)
                           then
                              Raise_Diag
                                (CM.Unsupported_Source_Construct
                                   (Path    => Path,
                                    Span    => List_Target.Span,
                                    Message =>
                                      "`list of T` is limited to the admitted value-type subset in PR11.10b"));
                           end if;

                           Appended_Value :=
                             Validate_And_Contextualize_Value
                               (Appended_Value,
                                Element_Type,
                                Var_Types,
                                Functions,
                                Type_Env,
                                Local_Static_Constants,
                                Exact_Length_Facts,
                                Path,
                                "`append` value type does not match the list element type");

                           Result.Kind := CM.Stmt_Call;
                           Result.Target := null;
                           Result.Value := null;
                           Result.Call := Shared_Call_Expr (Shared, Shared_Append_Name, Stmt.Span);
                           Result.Call.Args.Append (Appended_Value);
                           Expanded.Append (Result);
                           return Expanded;
                        elsif not Is_Assignable_Target (List_Target) then
                           Raise_Diag
                             (CM.Source_Frontend_Error
                                (Path    => Path,
                                 Span    => List_Target.Span,
                                 Message => "`append` first argument must be a writable list name"));
                        end if;

                        Element_Type := Growable_Array_Element_Type (List_Type, Type_Env);
                        if not Is_Growable_Array_Type (List_Type, Type_Env) then
                           Raise_Diag
                             (CM.Source_Frontend_Error
                                (Path    => Path,
                                 Span    => List_Target.Span,
                                 Message => "`append` expects a `mut list of T` first argument"));
                        elsif not Is_Container_Element_Type_Allowed
                          (Element_Type, Type_Env)
                        then
                           Raise_Diag
                             (CM.Unsupported_Source_Construct
                                (Path    => Path,
                                 Span    => List_Target.Span,
                                 Message =>
                                   "`list of T` is limited to the admitted value-type subset in PR11.10b"));
                        end if;

                        Ensure_Writable_Target
                          (List_Target,
                           Imported_Objects,
                           Local_Constants,
                           Local_Static_Constants,
                           Path,
                           "assignment to imported package-qualified objects is outside the current PR08.3 interface subset");

                        Appended_Value :=
                          Validate_And_Contextualize_Value
                            (Appended_Value,
                             Element_Type,
                             Var_Types,
                             Functions,
                             Type_Env,
                             Local_Static_Constants,
                             Exact_Length_Facts,
                             Path,
                             "`append` value type does not match the list element type");

                        Literal.Kind := CM.Expr_Array_Literal;
                        Literal.Span := Normalized_Call.Args (Normalized_Call.Args.First_Index + 1).Span;
                        Literal.Type_Name := List_Type.Name;
                        Literal.Elements.Append (Appended_Value);

                        Rewritten.Kind := CM.Stmt_Assign;
                        Rewritten.Span := Stmt.Span;
                        Rewritten.Target := List_Target;
                        Rewritten.Value :=
                          Binary_Expr
                            (List_Target,
                             "&",
                             Literal,
                             Stmt.Span,
                             UString_Value (List_Type.Name));
                        return
                          Normalize_Statement
                            (Rewritten,
                             Var_Types,
                             Functions,
                             Type_Env,
                             Channel_Env,
                             Imported_Objects,
                             Local_Constants,
                             Local_Static_Constants,
                             Exact_Length_Facts,
                             Path,
                             Has_Enclosing_Return,
                            Enclosing_Return_Type);
                     end;
                  end if;
               elsif Is_Set_Builtin_Call
                 (Normalized_Call, Var_Types, Functions, Type_Env)
               then
                  if Natural (Normalized_Call.Args.Length) /= 3 then
                     Raise_Diag
                       (CM.Source_Frontend_Error
                          (Path    => Path,
                           Span    => (if Normalized_Call.Has_Call_Span
                                       then Normalized_Call.Call_Span
                                       else Normalized_Call.Span),
                           Message => "`set(m, key, value)` expects exactly three arguments"));
                  else
                     declare
                        Map_Target     : constant CM.Expr_Access :=
                          Normalized_Call.Args (Normalized_Call.Args.First_Index);
                        Original_Map_Target : constant CM.Expr_Access :=
                          (if Stmt.Call /= null
                                and then Stmt.Call.Kind = CM.Expr_Apply
                                and then Stmt.Call.Callee /= null
                                and then Stmt.Call.Callee.Kind = CM.Expr_Select
                           then Stmt.Call.Callee.Prefix
                           elsif Stmt.Call /= null
                                and then not Stmt.Call.Args.Is_Empty
                           then Stmt.Call.Args (Stmt.Call.Args.First_Index)
                           else Map_Target);
                        Shared         : Shared_Object_Ref;
                        Map_Type       : GM.Type_Descriptor :=
                          Expr_Type (Map_Target, Var_Types, Functions, Type_Env);
                        Key_Type       : GM.Type_Descriptor := (others => <>);
                        Value_Type     : GM.Type_Descriptor := (others => <>);
                        Key_Expr       : CM.Expr_Access :=
                          Normalized_Call.Args (Normalized_Call.Args.First_Index + 1);
                        Value_Expr     : CM.Expr_Access :=
                          Normalized_Call.Args (Normalized_Call.Args.First_Index + 2);
                        Entry_Type     : GM.Type_Descriptor := Default_Integer;
                        Key_Name       : constant FT.UString :=
                          FT.To_UString (Next_Synthetic_Name ("Safe_Map_Key"));
                        Value_Name     : constant FT.UString :=
                          FT.To_UString (Next_Synthetic_Name ("Safe_Map_Value"));
                        Length_Name    : constant FT.UString :=
                          FT.To_UString (Next_Synthetic_Name ("Safe_Map_Len"));
                        Index_Name     : constant FT.UString :=
                          FT.To_UString (Next_Synthetic_Name ("Safe_Map_Index"));
                        Found_Name     : constant FT.UString :=
                          FT.To_UString (Next_Synthetic_Name ("Safe_Map_Found"));
                        Key_Temp       : CM.Expr_Access;
                        Value_Temp     : CM.Expr_Access;
                        Length_Temp    : CM.Expr_Access;
                        Index_Temp     : CM.Expr_Access;
                        Found_Temp     : CM.Expr_Access;
                        Entry_Expr     : CM.Expr_Access;
                        Entry_Value    : CM.Expr_Access;
                        Literal        : constant CM.Expr_Access := new CM.Expr_Node;
                        Loop_Body      : CM.Statement_Access_Vectors.Vector;
                        Match_Then     : CM.Statement_Access_Vectors.Vector;
                        Append_Missing_Then : CM.Statement_Access_Vectors.Vector;
                        Rebuild_Then   : CM.Statement_Access_Vectors.Vector;
                        Prefix_Then    : CM.Statement_Access_Vectors.Vector;
                        Prefix_Else    : CM.Statement_Access_Vectors.Vector;
                        Suffix_Then    : CM.Statement_Access_Vectors.Vector;
                        Index_Guard_Then : CM.Statement_Access_Vectors.Vector;
                        Advance_Then   : CM.Statement_Access_Vectors.Vector;
                        Advance_Else   : CM.Statement_Access_Vectors.Vector;
                        Rewritten_Stmts : CM.Statement_Access_Vectors.Vector;
                        Entry_Elements : FT.UString_Vectors.Vector;
                     begin
                        if Try_Shared_Root_Expr (Original_Map_Target, Shared) then
                           Map_Type := Shared.Type_Info;
                           if not Try_Map_Key_Value_Types
                             (Map_Type, Type_Env, Key_Type, Value_Type)
                           then
                              Raise_Diag
                                (CM.Source_Frontend_Error
                                   (Path    => Path,
                                    Span    => Map_Target.Span,
                                    Message =>
                                      "`set` expects a shared `map of (K, V)` root"));
                           elsif not Is_Map_Key_Type_Allowed (Key_Type, Type_Env) then
                              Raise_Diag
                                (CM.Unsupported_Source_Construct
                                   (Path    => Path,
                                    Span    => Map_Target.Span,
                                    Message =>
                                      "`map of (K, V)` keys are limited to the admitted discrete/string subset in PR11.10c"));
                           elsif not Is_Container_Element_Type_Allowed (Value_Type, Type_Env) then
                              Raise_Diag
                                (CM.Unsupported_Source_Construct
                                   (Path    => Path,
                                    Span    => Map_Target.Span,
                                    Message =>
                                      "`map of (K, V)` values are limited to the admitted value-type subset in PR11.10c"));
                           end if;

                           Key_Expr :=
                             Validate_And_Contextualize_Value
                               (Key_Expr,
                                Key_Type,
                                Var_Types,
                                Functions,
                                Type_Env,
                                Local_Static_Constants,
                                Exact_Length_Facts,
                                Path,
                                "`set` key type does not match the map key type");
                           Value_Expr :=
                             Validate_And_Contextualize_Value
                               (Value_Expr,
                                Value_Type,
                                Var_Types,
                                Functions,
                                Type_Env,
                                Local_Static_Constants,
                                Exact_Length_Facts,
                                Path,
                                "`set` value type does not match the map value type");

                           Result.Kind := CM.Stmt_Call;
                           Result.Target := null;
                           Result.Value := null;
                           Result.Call := Shared_Call_Expr (Shared, Shared_Set_Name, Stmt.Span);
                           Result.Call.Args.Append (Key_Expr);
                           Result.Call.Args.Append (Value_Expr);
                           Expanded.Append (Result);
                           return Expanded;
                        elsif not Is_Assignable_Target (Map_Target) then
                           Raise_Diag
                             (CM.Source_Frontend_Error
                                (Path    => Path,
                                 Span    => Map_Target.Span,
                                 Message => "`set` first argument must be a writable map name"));
                        end if;

                        if not Try_Map_Key_Value_Types (Map_Type, Type_Env, Key_Type, Value_Type) then
                           Raise_Diag
                             (CM.Source_Frontend_Error
                                (Path    => Path,
                                 Span    => Map_Target.Span,
                                 Message => "`set` expects a `mut map of (K, V)` first argument"));
                        elsif not Is_Map_Key_Type_Allowed (Key_Type, Type_Env) then
                           Raise_Diag
                             (CM.Unsupported_Source_Construct
                                (Path    => Path,
                                 Span    => Map_Target.Span,
                                 Message =>
                                   "`map of (K, V)` keys are limited to the admitted discrete/string subset in PR11.10c"));
                        elsif not Is_Container_Element_Type_Allowed (Value_Type, Type_Env) then
                           Raise_Diag
                             (CM.Unsupported_Source_Construct
                                (Path    => Path,
                                 Span    => Map_Target.Span,
                                 Message =>
                                   "`map of (K, V)` values are limited to the admitted value-type subset in PR11.10c"));
                        end if;
                        Entry_Elements.Append (Key_Type.Name);
                        Entry_Elements.Append (Value_Type.Name);

                        Ensure_Writable_Target
                          (Map_Target,
                           Imported_Objects,
                           Local_Constants,
                           Local_Static_Constants,
                           Path,
                           "assignment to imported package-qualified objects is outside the current PR08.3 interface subset");

                        Key_Expr :=
                          Validate_And_Contextualize_Value
                            (Key_Expr,
                             Key_Type,
                             Var_Types,
                             Functions,
                             Type_Env,
                             Local_Static_Constants,
                             Exact_Length_Facts,
                             Path,
                             "`set` key type does not match the map key type");
                        Value_Expr :=
                          Validate_And_Contextualize_Value
                            (Value_Expr,
                             Value_Type,
                             Var_Types,
                             Functions,
                             Type_Env,
                             Local_Static_Constants,
                             Exact_Length_Facts,
                             Path,
                             "`set` value type does not match the map value type");

                        declare
                           Snapshot_Name : constant FT.UString :=
                             FT.To_UString (Next_Synthetic_Name ("Safe_Map_Value"));
                           Entry_Name    : constant FT.UString :=
                             FT.To_UString (Next_Synthetic_Name ("Safe_Map_Entry"));
                           Snapshot_Expr : CM.Expr_Access;
                        begin
                           Rewritten_Stmts.Append
                             (Synthetic_Object_Decl_Stmt
                                (UString_Value (Snapshot_Name),
                                 Map_Type,
                                 Map_Target,
                                 Stmt.Span));
                           Rewritten_Stmts.Append
                             (Synthetic_Object_Decl_Stmt
                                (UString_Value (Key_Name),
                                 Key_Type,
                                 Key_Expr,
                                 Stmt.Span));
                           Rewritten_Stmts.Append
                             (Synthetic_Object_Decl_Stmt
                                (UString_Value (Value_Name),
                                 Value_Type,
                                 Value_Expr,
                                 Stmt.Span));
                           Rewritten_Stmts.Append
                             (Synthetic_Object_Decl_Stmt
                                (UString_Value (Length_Name),
                                 Default_Integer,
                                 Selector_Expr
                                   (Ident_Expr
                                      (UString_Value (Snapshot_Name),
                                       Stmt.Span,
                                       UString_Value (Map_Type.Name)),
                                    "length",
                                    Stmt.Span,
                                    UString_Value (Default_Integer.Name)),
                                 Stmt.Span));
                           Rewritten_Stmts.Append
                             (Synthetic_Object_Decl_Stmt
                                (UString_Value (Index_Name),
                                 Default_Integer,
                                 Int_Expr (1, Stmt.Span),
                                 Stmt.Span,
                                 Is_Constant => False));
                           Rewritten_Stmts.Append
                             (Synthetic_Object_Decl_Stmt
                                (UString_Value (Found_Name),
                                 BT.Boolean_Type,
                                 Bool_Expr (False, Stmt.Span),
                                 Stmt.Span,
                                 Is_Constant => False));

                           Entry_Type := Make_Tuple_Type (Entry_Elements, Type_Env);
                           Snapshot_Expr :=
                             Ident_Expr
                               (UString_Value (Snapshot_Name),
                                Stmt.Span,
                                UString_Value (Map_Type.Name));
                           Key_Temp :=
                             Ident_Expr
                               (UString_Value (Key_Name),
                                Stmt.Span,
                                UString_Value (Key_Type.Name));
                           Value_Temp :=
                             Ident_Expr
                               (UString_Value (Value_Name),
                                Stmt.Span,
                                UString_Value (Value_Type.Name));
                           Length_Temp :=
                             Ident_Expr
                               (UString_Value (Length_Name),
                                Stmt.Span,
                                UString_Value (Default_Integer.Name));
                           Index_Temp :=
                             Ident_Expr
                               (UString_Value (Index_Name),
                                Stmt.Span,
                                UString_Value (Default_Integer.Name));
                           Found_Temp :=
                             Ident_Expr
                               (UString_Value (Found_Name),
                                Stmt.Span,
                                UString_Value (BT.Boolean_Type.Name));
                           Entry_Expr :=
                             Ident_Expr
                               (UString_Value (Entry_Name),
                                Stmt.Span,
                                UString_Value (Entry_Type.Name));
                           Entry_Value :=
                             Tuple_Expr
                               (Key_Temp,
                                Value_Temp,
                                Stmt.Span,
                                UString_Value (Entry_Type.Name));
                           Index_Guard_Then.Append
                             (Synthetic_Exit_Stmt (Stmt.Span));

                           Literal.Kind := CM.Expr_Array_Literal;
                           Literal.Span := Stmt.Span;
                           Literal.Type_Name := Map_Type.Name;
                           Literal.Elements.Append (Entry_Value);
                           Append_Missing_Then.Append
                             (Synthetic_Assign_Stmt
                                (Map_Target,
                                 Binary_Expr
                                   (Snapshot_Expr,
                                    "&",
                                    Literal,
                                    Stmt.Span,
                                    UString_Value (Map_Type.Name)),
                                 Stmt.Span));
                           Prefix_Then.Append
                             (Synthetic_Assign_Stmt
                                (Map_Target,
                                 Literal,
                                 Stmt.Span));
                           Prefix_Else.Append
                             (Synthetic_Assign_Stmt
                                (Map_Target,
                                 Binary_Expr
                                   (Resolved_Index_Expr
                                      (Snapshot_Expr,
                                       Int_Expr (1, Stmt.Span),
                                       Stmt.Span,
                                       UString_Value (Map_Type.Name),
                                       Binary_Expr
                                         (Index_Temp,
                                          "-",
                                          Int_Expr (1, Stmt.Span),
                                          Stmt.Span,
                                          UString_Value (Default_Integer.Name))),
                                    "&",
                                    Literal,
                                    Stmt.Span,
                                    UString_Value (Map_Type.Name)),
                                 Stmt.Span));
                           Rebuild_Then.Append
                             (Synthetic_If_Else_Stmt
                                (Binary_Expr
                                   (Index_Temp,
                                    "==",
                                    Int_Expr (1, Stmt.Span),
                                    Stmt.Span,
                                    "boolean"),
                                 Prefix_Then,
                                 Prefix_Else,
                                 Stmt.Span));
                           Suffix_Then.Append
                             (Synthetic_Assign_Stmt
                                (Map_Target,
                                 Binary_Expr
                                   (Map_Target,
                                    "&",
                                    Resolved_Index_Expr
                                      (Snapshot_Expr,
                                       Binary_Expr
                                         (Index_Temp,
                                          "+",
                                          Int_Expr (1, Stmt.Span),
                                          Stmt.Span,
                                          UString_Value (Default_Integer.Name)),
                                       Stmt.Span,
                                       UString_Value (Map_Type.Name),
                                       Length_Temp),
                                    Stmt.Span,
                                    UString_Value (Map_Type.Name)),
                                 Stmt.Span));
                           Rebuild_Then.Append
                             (Synthetic_If_Stmt
                                (Binary_Expr
                                   (Index_Temp,
                                    "<",
                                    Length_Temp,
                                    Stmt.Span,
                                    "boolean"),
                                 Suffix_Then,
                                 Stmt.Span));
                           Match_Then.Append
                             (Synthetic_Assign_Stmt
                                (Found_Temp,
                                 Bool_Expr (True, Stmt.Span),
                                 Stmt.Span));
                           Match_Then.Append
                             (Synthetic_If_Stmt
                                (Found_Temp,
                                 Rebuild_Then,
                                 Stmt.Span));
                           Match_Then.Append
                             (Synthetic_Exit_Stmt (Stmt.Span));

                           Loop_Body.Append
                             (Synthetic_If_Stmt
                                (Binary_Expr
                                   (Index_Temp,
                                    "<",
                                    Int_Expr (1, Stmt.Span),
                                    Stmt.Span,
                                    "boolean"),
                                 Index_Guard_Then,
                                 Stmt.Span));
                           Loop_Body.Append
                             (Synthetic_Object_Decl_Stmt
                                (UString_Value (Entry_Name),
                                 Entry_Type,
                                 Resolved_Index_Expr
                                   (Snapshot_Expr,
                                    Index_Temp,
                                    Stmt.Span,
                                    UString_Value (Entry_Type.Name)),
                                 Stmt.Span));
                           Loop_Body.Append
                             (Synthetic_If_Stmt
                                (Binary_Expr
                                   (Selector_Expr
                                      (Entry_Expr,
                                       "1",
                                       Stmt.Span,
                                       UString_Value (Key_Type.Name)),
                                    "==",
                                    Key_Temp,
                                    Stmt.Span,
                                    "boolean"),
                                 Match_Then,
                                 Stmt.Span));
                           Advance_Then.Append
                             (Synthetic_Assign_Stmt
                                (Index_Temp,
                                 Binary_Expr
                                   (Index_Temp,
                                    "+",
                                    Int_Expr (1, Stmt.Span),
                                    Stmt.Span,
                                    UString_Value (Default_Integer.Name)),
                                 Stmt.Span));
                           Advance_Else.Append
                             (Synthetic_Exit_Stmt (Stmt.Span));
                           Loop_Body.Append
                             (Synthetic_If_Else_Stmt
                                (Binary_Expr
                                   (Index_Temp,
                                    "<",
                                    Length_Temp,
                                    Stmt.Span,
                                    "boolean"),
                                 Advance_Then,
                                 Advance_Else,
                                 Stmt.Span));
                           Rewritten_Stmts.Append
                             (Synthetic_While_Stmt
                                (Binary_Expr
                                   (Index_Temp,
                                    "<=",
                                    Length_Temp,
                                    Stmt.Span,
                                    "boolean"),
                                 Loop_Body,
                                 Stmt.Span));

                           Rewritten_Stmts.Append
                             (Synthetic_If_Stmt
                                (Unary_Expr
                                   ("not",
                                    Found_Temp,
                                    Stmt.Span,
                                    "boolean"),
                                 Append_Missing_Then,
                                 Stmt.Span));
                        end;

                        return
                          Normalize_Statement_List
                            (Rewritten_Stmts,
                             Var_Types,
                             Functions,
                             Type_Env,
                             Channel_Env,
                             Imported_Objects,
                             Local_Constants,
                             Local_Static_Constants,
                             Exact_Length_Facts,
                             Path,
                             Has_Enclosing_Return,
                             Enclosing_Return_Type);
                     end;
                  end if;
               elsif Is_Pop_Last_Builtin_Call
                 (Normalized_Call, Var_Types, Functions, Type_Env)
               then
                  Raise_Diag
                    (CM.Source_Frontend_Error
                       (Path    => Path,
                        Span    => (if Normalized_Call.Has_Call_Span
                                    then Normalized_Call.Call_Span
                                    else Normalized_Call.Span),
                        Message => "`pop_last(items)` returns an `optional T` value and must be used in an expression"));
               elsif Is_Contains_Builtin_Call
                 (Normalized_Call, Var_Types, Functions, Type_Env)
               then
                  Raise_Diag
                    (CM.Source_Frontend_Error
                       (Path    => Path,
                        Span    => (if Normalized_Call.Has_Call_Span
                                    then Normalized_Call.Call_Span
                                    else Normalized_Call.Span),
                        Message => "`contains(m, key)` returns a `boolean` value and must be used in an expression"));
               elsif Is_Get_Builtin_Call
                 (Normalized_Call, Var_Types, Functions, Type_Env)
               then
                  Raise_Diag
                    (CM.Source_Frontend_Error
                       (Path    => Path,
                        Span    => (if Normalized_Call.Has_Call_Span
                                    then Normalized_Call.Call_Span
                                    else Normalized_Call.Span),
                        Message => "`get(m, key)` returns an `optional V` value and must be used in an expression"));
               elsif Is_Remove_Builtin_Call
                 (Normalized_Call, Var_Types, Functions, Type_Env)
               then
                  Raise_Diag
                    (CM.Source_Frontend_Error
                       (Path    => Path,
                        Span    => (if Normalized_Call.Has_Call_Span
                                    then Normalized_Call.Call_Span
                                    else Normalized_Call.Span),
                        Message => "`remove(m, key)` mutates a map and returns an `optional V` value, so it must be used in an expression"));
               end if;
            end;
            declare
               Desugared : constant Desugared_Expr_Result :=
                 Desugar_Executable_Expr
                   (Normalize_Procedure_Call_Checked
                      (Stmt.Call,
                       Var_Types,
                       Functions,
                       Type_Env,
                       Local_Static_Constants,
                       Path,
                       Allow_Try => True),
                    Var_Types,
                    Functions,
                    Type_Env,
                    Has_Enclosing_Return,
                    Enclosing_Return_Type,
                    Path);
            begin
               Append_Statements (Expanded, Normalize_Preludes (Desugared.Preludes));
               Result.Call := Desugared.Expr;
            end;

         when CM.Stmt_Send | CM.Stmt_Try_Send =>
            if Stmt.Kind = CM.Stmt_Try_Send then
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path,
                     Span    => Stmt.Span,
                     Message =>
                       "try_send was renamed to 'send ch, value, success'"));
            end if;
            Result.Channel_Name :=
              Normalize_Expr_Checked
                (Stmt.Channel_Name, Var_Types, Functions, Type_Env, Local_Static_Constants, Path);
            Reject_Imported_Channel_Elaboration (Result.Channel_Name, Stmt.Span);
            declare
               Desugared : constant Desugared_Expr_Result :=
                 Desugar_Checked (Stmt.Value);
            begin
               Result.Value := Desugared.Expr;
            end;
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
            if Stmt.Success_Var = null then
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path,
                     Span    => Stmt.Span,
                     Message =>
                       "blocking two-argument send was removed; use 'send ch, value, success'"));
            end if;
            Result.Success_Var :=
              Normalize_Expr_Checked
                (Stmt.Success_Var, Var_Types, Functions, Type_Env, Local_Static_Constants, Path);
            if not Is_Assignable_Target (Result.Success_Var) then
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path,
                     Span    => Result.Success_Var.Span,
                     Message => "send success variable must be a writable name"));
            end if;
            Ensure_Writable_Target
              (Result.Success_Var,
               Imported_Objects,
               Local_Constants,
               Local_Static_Constants,
               Path,
               "assignment to imported package-qualified objects is outside the current PR08.3 interface subset");
            Success_Type := Expr_Type (Result.Success_Var, Var_Types, Functions, Type_Env);
            if not Is_Boolean_Type (Success_Type, Type_Env) then
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path,
                     Span    => Result.Success_Var.Span,
                     Message => "send success variable must have type Boolean"));
            end if;

         when CM.Stmt_Receive | CM.Stmt_Try_Receive =>
            Result.Channel_Name :=
              Normalize_Expr_Checked
                (Stmt.Channel_Name, Var_Types, Functions, Type_Env, Local_Static_Constants, Path);
            Reject_Imported_Channel_Elaboration (Result.Channel_Name, Stmt.Span);
            Result.Target :=
              Normalize_Expr_Checked
                (Stmt.Target, Var_Types, Functions, Type_Env, Local_Static_Constants, Path);
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
               Local_Static_Constants,
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
                 Normalize_Expr_Checked
                   (Stmt.Success_Var, Var_Types, Functions, Type_Env, Local_Static_Constants, Path);
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
                  Local_Static_Constants,
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
            declare
               Desugared : constant Desugared_Expr_Result :=
                 Desugar_Checked (Stmt.Value);
            begin
               Result.Value := Desugared.Expr;
            end;
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
               Desugared : constant Desugared_Expr_Result :=
                 Desugar_Checked (Stmt.Case_Expr);
            begin
               Result.Case_Expr := Desugared.Expr;
               Scrutinee_Type :=
                 Expr_Type (Result.Case_Expr, Var_Types, Functions, Type_Env);
               if not Is_Discrete_Case_Type (Scrutinee_Type, Type_Env)
                 and then not Is_String_Type (Scrutinee_Type, Type_Env)
               then
                  Raise_Diag
                    (CM.Unsupported_Source_Construct
                       (Path    => Path,
                        Span    => Result.Case_Expr.Span,
                        Message =>
                          "case expressions currently require boolean, integer-family, binary, or string scrutinees"));
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
                          Normalize_Expr_Checked
                            (Arm.Choice, Var_Types, Functions, Type_Env, Local_Static_Constants, Path);
                        if Is_String_Type (Scrutinee_Type, Type_Env)
                          and then New_Arm.Choice.Kind /= CM.Expr_String
                        then
                           Raise_Diag
                             (CM.Unsupported_Source_Construct
                                (Path    => Path,
                                 Span    => New_Arm.Choice.Span,
                                 Message => "string case choices currently require string literals"));
                        elsif not Is_Static_Case_Choice
                          (New_Arm.Choice, Local_Static_Constants)
                        then
                           Raise_Diag
                             (CM.Source_Frontend_Error
                                (Path    => Path,
                                 Span    => New_Arm.Choice.Span,
                                 Message => "case arm choices must be static scalar values"));
                        end if;
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
                          Exact_Length_Facts,
                          Path,
                          Has_Enclosing_Return,
                          Enclosing_Return_Type);
                     Result.Case_Arms.Append (New_Arm);
                  end;
               end loop;
            end;

         when CM.Stmt_Match =>
            declare
               Desugared : constant Desugared_Expr_Result :=
                 Desugar_Checked (Stmt.Match_Expr);
               Carrier_Type : GM.Type_Descriptor;
               Match_Value  : CM.Expr_Access;
               Match_Name   : FT.UString := FT.To_UString ("");
               Arm_Static_Constants : Static_Value_Maps.Map;

               function Enum_Literal_Expr
                 (Name      : FT.UString;
                  Type_Name : FT.UString;
                  Span      : FT.Source_Span) return CM.Expr_Access
               is
               begin
                  return
                    new CM.Expr_Node'
                      (Kind      => CM.Expr_Enum_Literal,
                       Span      => Span,
                       Type_Name => Type_Name,
                       Name      => Name,
                       others    => <>);
               end Enum_Literal_Expr;
            begin
               Carrier_Type := Expr_Type (Desugared.Expr, Var_Types, Functions, Type_Env);

               if Is_Name_Expr (Desugared.Expr) then
                  Match_Value := Desugared.Expr;
               else
                  Match_Name := FT.To_UString (Next_Synthetic_Name ("Safe_Match_Tmp"));
                  Expanded.Append
                    (Synthetic_Object_Decl_Stmt
                       (UString_Value (Match_Name),
                        Carrier_Type,
                        Desugared.Expr,
                        Stmt.Match_Expr.Span));
                  Match_Value :=
                    Ident_Expr
                      (UString_Value (Match_Name),
                       Stmt.Match_Expr.Span,
                       UString_Value (Carrier_Type.Name));
               end if;

               if Try_Result_Carrier_Success_Type
                 (Carrier_Type, Type_Env, Success_Type)
               then
                  declare
                     Result_Cond   : CM.Expr_Access;
                     Ok_Arm        : CM.Match_Arm := (others => <>);
                     Fail_Arm      : CM.Match_Arm := (others => <>);
                     Ok_Count      : Natural := 0;
                     Fail_Count    : Natural := 0;
                     Arm_Vars      : Type_Maps.Map;
                     Arm_Constants : Type_Maps.Map;
                     Binder_Stmt   : CM.Statement_Access;
                  begin
                     for Arm of Stmt.Match_Arms loop
                        case Arm.Kind is
                           when CM.Match_Arm_Ok =>
                              Ok_Arm := Arm;
                              Ok_Count := Ok_Count + 1;
                           when CM.Match_Arm_Fail =>
                              Fail_Arm := Arm;
                              Fail_Count := Fail_Count + 1;
                           when others =>
                              Raise_Diag
                                (CM.Source_Frontend_Error
                                   (Path    => Path,
                                    Span    => Arm.Span,
                                    Message => "result matches admit only `when ok (...)` and `when fail (...)` arms"));
                        end case;
                     end loop;

                     if Ok_Count /= 1 or else Fail_Count /= 1 then
                        Raise_Diag
                          (CM.Source_Frontend_Error
                             (Path    => Path,
                              Span    => Stmt.Span,
                              Message => "match statements require exactly one `when ok (...)` arm and one `when fail (...)` arm"));
                     elsif Natural (Ok_Arm.Binders.Length) /= 1 then
                        Raise_Diag
                          (CM.Source_Frontend_Error
                             (Path    => Path,
                              Span    => Ok_Arm.Span,
                              Message => "`when ok` match arms require exactly one binder"));
                     elsif Natural (Fail_Arm.Binders.Length) /= 1 then
                        Raise_Diag
                          (CM.Source_Frontend_Error
                             (Path    => Path,
                              Span    => Fail_Arm.Span,
                              Message => "`when fail` match arms require exactly one binder"));
                     end if;

                     Result_Cond :=
                       Selector_Expr
                         (Selector_Expr
                            (Match_Value,
                             "1",
                             Stmt.Match_Expr.Span,
                             UString_Value (BT.Result_Type.Name)),
                          "ok",
                          Stmt.Match_Expr.Span,
                          "boolean");

                     Arm_Vars := Var_Types;
                     Arm_Constants := Local_Constants;
                     Arm_Static_Constants := Local_Static_Constants;
                     Put_Type
                       (Arm_Vars,
                        UString_Value (Ok_Arm.Binders (Ok_Arm.Binders.First_Index)),
                        Success_Type);
                     Put_Type
                       (Arm_Constants,
                        UString_Value (Ok_Arm.Binders (Ok_Arm.Binders.First_Index)),
                        Success_Type);
                     Remove_Static_Value
                       (Arm_Static_Constants,
                        UString_Value (Ok_Arm.Binders (Ok_Arm.Binders.First_Index)));
                     Result.Then_Stmts :=
                       Normalize_Statement_List
                         (Ok_Arm.Statements,
                          Arm_Vars,
                          Functions,
                          Type_Env,
                          Channel_Env,
                          Imported_Objects,
                          Arm_Constants,
                          Arm_Static_Constants,
                          Exact_Length_Facts,
                          Path,
                          Has_Enclosing_Return,
                          Enclosing_Return_Type);
                     Binder_Stmt :=
                       Synthetic_Object_Decl_Stmt
                         (UString_Value (Ok_Arm.Binders (Ok_Arm.Binders.First_Index)),
                          Success_Type,
                          Selector_Expr
                            (Match_Value,
                             "2",
                             Ok_Arm.Span,
                             UString_Value (Success_Type.Name)),
                          Ok_Arm.Span);
                     Result.Then_Stmts.Prepend (Binder_Stmt);

                     Arm_Vars := Var_Types;
                     Arm_Constants := Local_Constants;
                     Arm_Static_Constants := Local_Static_Constants;
                     Put_Type
                       (Arm_Vars,
                        UString_Value (Fail_Arm.Binders (Fail_Arm.Binders.First_Index)),
                        BT.Result_Type);
                     Put_Type
                       (Arm_Constants,
                        UString_Value (Fail_Arm.Binders (Fail_Arm.Binders.First_Index)),
                        BT.Result_Type);
                     Remove_Static_Value
                       (Arm_Static_Constants,
                        UString_Value (Fail_Arm.Binders (Fail_Arm.Binders.First_Index)));
                     Result.Else_Stmts :=
                       Normalize_Statement_List
                         (Fail_Arm.Statements,
                          Arm_Vars,
                          Functions,
                          Type_Env,
                          Channel_Env,
                          Imported_Objects,
                          Arm_Constants,
                          Arm_Static_Constants,
                          Exact_Length_Facts,
                          Path,
                          Has_Enclosing_Return,
                          Enclosing_Return_Type);
                     Binder_Stmt :=
                       Synthetic_Object_Decl_Stmt
                         (UString_Value (Fail_Arm.Binders (Fail_Arm.Binders.First_Index)),
                          BT.Result_Type,
                          Selector_Expr
                            (Match_Value,
                             "1",
                             Fail_Arm.Span,
                             UString_Value (BT.Result_Type.Name)),
                          Fail_Arm.Span);
                     Result.Else_Stmts.Prepend (Binder_Stmt);

                     Result.Kind := CM.Stmt_If;
                     Result.Condition := Result_Cond;
                     Result.Has_Else := True;
                  end;
               elsif Is_Sum_Type (Carrier_Type, Type_Env) then
                  declare
                     Sum_Type      : constant GM.Type_Descriptor := Base_Type (Carrier_Type, Type_Env);
                     Tag_Type_Name : constant FT.UString := Sum_Type.Discriminant_Type;
                     Disc_Name     : constant String := UString_Value (Sum_Type.Discriminant_Name);
                     Total_Arms    : constant Natural := Natural (Stmt.Match_Arms.Length);
                     Seen_Variants : String_Index_Maps.Map;
                     Arm_Index     : Natural := 0;

                     function Build_Sum_Arm_Condition
                       (Constructor : Sum_Constructor_Info;
                        Span        : FT.Source_Span) return CM.Expr_Access
                     is
                     begin
                        return
                          Binary_Expr
                            (Selector_Expr
                               (Match_Value,
                                Disc_Name,
                                Span,
                                UString_Value (Tag_Type_Name)),
                             "==",
                             Enum_Literal_Expr
                               (Constructor.Tag_Literal_Name,
                                Tag_Type_Name,
                                Span),
                             Span,
                             "boolean");
                     end Build_Sum_Arm_Condition;

                     function Normalize_Sum_Arm_Statements
                       (Arm         : CM.Match_Arm;
                        Constructor : Sum_Constructor_Info;
                        Payload_Prefix : CM.Expr_Access := Match_Value;
                        Payload_Name   : String := "";
                        Payload_Type   : GM.Type_Descriptor := (others => <>))
                        return CM.Statement_Access_Vectors.Vector
                     is
                        Arm_Vars      : Type_Maps.Map := Var_Types;
                        Arm_Constants : Type_Maps.Map := Local_Constants;
                        Arm_Static    : Static_Value_Maps.Map := Local_Static_Constants;
                        Statements    : CM.Statement_Access_Vectors.Vector;
                     begin
                        if Payload_Name /= ""
                          and then UString_Value (Payload_Type.Name)'Length > 0
                        then
                           Put_Type (Arm_Vars, Payload_Name, Payload_Type);
                           Put_Type (Arm_Constants, Payload_Name, Payload_Type);
                           Remove_Static_Value (Arm_Static, Payload_Name);
                        end if;

                        if not Constructor.Fields.Is_Empty then
                           for Index in Constructor.Fields.First_Index .. Constructor.Fields.Last_Index loop
                              declare
                                 Binder_Name : constant String :=
                                   UString_Value (Arm.Binders (Index));
                                 Binder_Type : constant GM.Type_Descriptor :=
                                   Resolve_Type
                                     (UString_Value (Constructor.Fields (Index).Type_Name),
                                      Type_Env,
                                      Path,
                                      Arm.Span);
                              begin
                                 Put_Type (Arm_Vars, Binder_Name, Binder_Type);
                                 Put_Type (Arm_Constants, Binder_Name, Binder_Type);
                                 Remove_Static_Value (Arm_Static, Binder_Name);
                              end;
                           end loop;
                        end if;

                        if not Constructor.Fields.Is_Empty then
                           for Index in Constructor.Fields.First_Index .. Constructor.Fields.Last_Index loop
                              declare
                                 Binder_Name : constant String :=
                                   UString_Value (Arm.Binders (Index));
                                 Binder_Type : constant GM.Type_Descriptor :=
                                   Resolve_Type
                                     (UString_Value (Constructor.Fields (Index).Type_Name),
                                      Type_Env,
                                      Path,
                                      Arm.Span);
                              begin
                                 Statements.Append
                                   (Synthetic_Object_Decl_Stmt
                                      (Binder_Name,
                                       Binder_Type,
                                       Selector_Expr
                                         (Payload_Prefix,
                                          UString_Value (Constructor.Fields (Index).Name),
                                          Arm.Span,
                                          UString_Value (Binder_Type.Name)),
                                       Arm.Span));
                              end;
                           end loop;
                        end if;

                        Append_Statements
                          (Statements,
                           Normalize_Statement_List
                             (Arm.Statements,
                              Arm_Vars,
                              Functions,
                              Type_Env,
                              Channel_Env,
                              Imported_Objects,
                              Arm_Constants,
                              Arm_Static,
                              Exact_Length_Facts,
                              Path,
                              Has_Enclosing_Return,
                              Enclosing_Return_Type));
                        return Statements;
                     end Normalize_Sum_Arm_Statements;

                     function Sum_Arm_Subtype
                       (Constructor : Sum_Constructor_Info) return GM.Type_Descriptor
                     is
                        Result_Type : GM.Type_Descriptor := Sum_Type;
                        Constraint  : GM.Discriminant_Constraint;
                     begin
                        Result_Type.Kind := FT.To_UString ("subtype");
                        Result_Type.Has_Base := True;
                        Result_Type.Base := Sum_Type.Name;
                        Result_Type.Discriminant_Constraints.Clear;
                        Constraint.Is_Named := True;
                        Constraint.Name := Sum_Type.Discriminant_Name;
                        Constraint.Value.Kind := GM.Scalar_Value_Enum;
                        Constraint.Value.Type_Name := Tag_Type_Name;
                        Constraint.Value.Text := Constructor.Tag_Literal_Name;
                        Result_Type.Discriminant_Constraints.Append (Constraint);
                        return Result_Type;
                     end Sum_Arm_Subtype;

                     function Build_Sum_Arm_Statements
                       (Arm         : CM.Match_Arm;
                        Constructor : Sum_Constructor_Info;
                        Prefix_Name : String)
                        return CM.Statement_Access_Vectors.Vector
                     is
                        Constrained_Type : constant GM.Type_Descriptor :=
                          Sum_Arm_Subtype (Constructor);
                        Payload_Prefix : constant CM.Expr_Access :=
                          Ident_Expr
                            (Prefix_Name,
                             Arm.Span,
                             UString_Value (Constrained_Type.Name));
                        Statements : CM.Statement_Access_Vectors.Vector :=
                          Normalize_Sum_Arm_Statements
                            (Arm,
                             Constructor,
                             Payload_Prefix => Payload_Prefix,
                             Payload_Name   => Prefix_Name,
                             Payload_Type   => Constrained_Type);
                     begin
                        Statements.Prepend
                          (Synthetic_Object_Decl_Stmt
                             (Prefix_Name,
                              Constrained_Type,
                              Match_Value,
                              Arm.Span));
                        return Statements;
                     end Build_Sum_Arm_Statements;
                  begin
                     if Total_Arms = 0 then
                        Raise_Diag
                          (CM.Source_Frontend_Error
                             (Path    => Path,
                              Span    => Stmt.Span,
                              Message => "match statements require at least one arm"));
                     end if;

                     for Arm of Stmt.Match_Arms loop
                        Arm_Index := Arm_Index + 1;
                        if Arm.Kind /= CM.Match_Arm_Variant then
                           Raise_Diag
                             (CM.Source_Frontend_Error
                                (Path    => Path,
                                 Span    => Arm.Span,
                                 Message => "sum matches admit only `when variant` arms in PR11.13b"));
                        end if;

                        declare
                           Variant_Key : constant String :=
                             Canonical_Name (UString_Value (Arm.Variant_Name));
                           Constructor : Sum_Constructor_Info;
                           Sum_Metadata : constant GM.Type_Descriptor :=
                             Base_Type (Sum_Type, Type_Env);
                           Binder_Seen : String_Index_Maps.Map;
                           Branch_Statements : CM.Statement_Access_Vectors.Vector;
                        begin
                           if not Try_Find_Sum_Variant_Constructor
                             (Sum_Metadata,
                              UString_Value (Arm.Variant_Name),
                              Constructor)
                           then
                              Raise_Diag
                                (CM.Source_Frontend_Error
                                   (Path    => Path,
                                    Span    => Arm.Span,
                                    Message =>
                                      "unknown sum variant `"
                                      & UString_Value (Arm.Variant_Name)
                                      & "` in match arm"));
                           end if;
                           if Canonical_Name (UString_Value (Constructor.Sum_Type_Name)) /=
                             Canonical_Name (UString_Value (Sum_Type.Name))
                           then
                              Raise_Diag
                                (CM.Source_Frontend_Error
                                   (Path    => Path,
                                    Span    => Arm.Span,
                                    Message =>
                                      "sum variant `"
                                      & UString_Value (Arm.Variant_Name)
                                      & "` does not belong to `"
                                      & UString_Value (Sum_Type.Name)
                                      & "`"));
                           elsif Seen_Variants.Contains (Variant_Key) then
                              Raise_Diag
                                (CM.Source_Frontend_Error
                                   (Path    => Path,
                                    Span    => Arm.Span,
                                    Message =>
                                      "duplicate sum match arm `"
                                      & UString_Value (Arm.Variant_Name)
                                      & "`"));
                           end if;
                           Seen_Variants.Include (Variant_Key, Arm_Index);

                           if Natural (Arm.Binders.Length) /=
                             Natural (Constructor.Fields.Length)
                           then
                              if Constructor.Fields.Is_Empty then
                                 Raise_Diag
                                   (CM.Source_Frontend_Error
                                      (Path    => Path,
                                       Span    => Arm.Span,
                                       Message =>
                                         "zero-payload sum variant `"
                                         & UString_Value (Arm.Variant_Name)
                                         & "` uses bare `when "
                                         & UString_Value (Arm.Variant_Name)
                                         & "` in PR11.13b"));
                              else
                                 Raise_Diag
                                   (CM.Source_Frontend_Error
                                      (Path    => Path,
                                       Span    => Arm.Span,
                                       Message =>
                                         "sum match arm `"
                                         & UString_Value (Arm.Variant_Name)
                                         & "` must bind exactly "
                                         & Natural'Image (Natural (Constructor.Fields.Length))
                                         & " payload value(s)"));
                              end if;
                           end if;

                           if not Arm.Binders.Is_Empty then
                              for Binder of Arm.Binders loop
                                 declare
                                    Binder_Key : constant String :=
                                      Canonical_Name (UString_Value (Binder));
                                 begin
                                    if Binder_Seen.Contains (Binder_Key) then
                                       Raise_Diag
                                         (CM.Source_Frontend_Error
                                            (Path    => Path,
                                             Span    => Arm.Span,
                                             Message =>
                                               "duplicate binder `"
                                               & UString_Value (Binder)
                                               & "` in match arm"));
                                    end if;
                                    Binder_Seen.Include (Binder_Key, 1);
                                 end;
                              end loop;
                           end if;

                           Branch_Statements := Normalize_Sum_Arm_Statements (Arm, Constructor);

                           if Total_Arms = 1 then
                              Result.Kind := CM.Stmt_If;
                              Result.Condition := Bool_Expr (True, Arm.Span);
                              if Constructor.Fields.Is_Empty then
                                 Result.Then_Stmts := Branch_Statements;
                              else
                                 Result.Then_Stmts :=
                                   Build_Sum_Arm_Statements
                                     (Arm,
                                      Constructor,
                                      "Safe_Match_Only_" &
                                      Ada.Strings.Fixed.Trim
                                        (Natural'Image (Arm_Index),
                                         Ada.Strings.Both));
                              end if;
                           elsif Arm_Index = 1 then
                              Result.Kind := CM.Stmt_If;
                              Result.Condition := Build_Sum_Arm_Condition (Constructor, Arm.Span);
                              if Constructor.Fields.Is_Empty then
                                 Result.Then_Stmts := Branch_Statements;
                              else
                                 Result.Then_Stmts :=
                                   Build_Sum_Arm_Statements
                                     (Arm,
                                      Constructor,
                                      "Safe_Match_Then_" &
                                      Ada.Strings.Fixed.Trim
                                        (Natural'Image (Arm_Index),
                                         Ada.Strings.Both));
                              end if;
                           elsif Arm_Index = Total_Arms then
                              if Constructor.Fields.Is_Empty then
                                 Result.Has_Else := True;
                                 Result.Else_Stmts := Branch_Statements;
                              else
                                 Result.Has_Else := True;
                                 Result.Else_Stmts :=
                                   Build_Sum_Arm_Statements
                                     (Arm,
                                      Constructor,
                                      "Safe_Match_Final_" &
                                      Ada.Strings.Fixed.Trim
                                        (Natural'Image (Arm_Index),
                                         Ada.Strings.Both));
                              end if;
                           else
                              declare
                                 Elsif_Part : CM.Elsif_Part;
                              begin
                                 Elsif_Part.Condition :=
                                   Build_Sum_Arm_Condition (Constructor, Arm.Span);
                                 if Constructor.Fields.Is_Empty then
                                    Elsif_Part.Statements := Branch_Statements;
                                 else
                                    Elsif_Part.Statements :=
                                      Build_Sum_Arm_Statements
                                        (Arm,
                                         Constructor,
                                         "Safe_Match_Elsif_" &
                                         Ada.Strings.Fixed.Trim
                                           (Natural'Image (Arm_Index),
                                            Ada.Strings.Both));
                                 end if;
                                 Elsif_Part.Span := Arm.Span;
                                 Result.Elsifs.Append (Elsif_Part);
                              end;
                           end if;
                        end;
                     end loop;

                     for Variant of Base_Type (Sum_Type, Type_Env).Sum_Variants loop
                        declare
                           Variant_Key : constant String :=
                             Canonical_Name (UString_Value (Variant.Name));
                        begin
                           if not Seen_Variants.Contains (Variant_Key)
                           then
                              Raise_Diag
                                (CM.Source_Frontend_Error
                                   (Path    => Path,
                                    Span    => Stmt.Span,
                                    Message =>
                                      "match on `"
                                      & UString_Value (Sum_Type.Name)
                                      & "` is missing variant `"
                                      & UString_Value (Variant.Name)
                                      & "`"));
                           end if;
                        end;
                     end loop;
                  end;
               else
                  Raise_Diag
                    (CM.Source_Frontend_Error
                       (Path    => Path,
                        Span    => Stmt.Match_Expr.Span,
                        Message => "match requires a `(result, T)` or sum expression"));
               end if;
            end;

         when CM.Stmt_Select =>
            declare
               Channel_Arms : Natural := 0;
               Delay_Arms   : Natural := 0;
            begin
               if Current_Select_In_Subprogram_Body then
                  Raise_Diag
                    (CM.Source_Frontend_Error
                       (Path    => Path,
                        Span    => Stmt.Span,
                        Message =>
                          "PR11.9a temporarily admits select only in direct task bodies and unit-scope statements"));
               end if;
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
                                Local_Static_Constants,
                                Path);
                           declare
                              Channel_Name : constant String :=
                                Flatten_Name (New_Arm.Channel_Data.Channel_Name);
                           begin
                              if Contains_Dot (Channel_Name)
                                or else Contains_Public_Local_Channel (Channel_Name)
                              then
                                 Raise_Diag
                                   (CM.Source_Frontend_Error
                                      (Path    => Path,
                                       Span    => Arm.Channel_Data.Channel_Name.Span,
                                       Message =>
                                         "PR11.9a temporarily admits select arms only on same-unit non-public channels"));
                              end if;
                           end;
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
                                   Exact_Length_Facts,
                                   Path,
                                   Has_Enclosing_Return,
                                   Enclosing_Return_Type);
                           end;
                        when CM.Select_Arm_Delay =>
                           Delay_Arms := Delay_Arms + 1;
                           New_Arm.Delay_Data.Duration_Expr :=
                             Normalize_Expr_Checked
                               (Arm.Delay_Data.Duration_Expr,
                                Var_Types,
                                Functions,
                                Type_Env,
                                Local_Static_Constants,
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
                                Exact_Length_Facts,
                                Path,
                                Has_Enclosing_Return,
                                Enclosing_Return_Type);
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

      Expanded.Append (Result);
      return Expanded;
   end Normalize_Statement;

   function Resolve_Type_Declaration
     (Decl      : CM.Type_Decl;
      Type_Env  : in out Type_Maps.Map;
      Const_Env : Static_Value_Maps.Map;
      Path      : String;
      Family_By_Name : String_Index_Maps.Map := String_Index_Maps.Empty_Map;
      Families       : Recursive_Family_Vectors.Vector := Recursive_Family_Vectors.Empty_Vector)
      return GM.Type_Descriptor
   is
      Result : GM.Type_Descriptor;
      Item   : GM.Type_Field;
   begin
      declare
         Family_Index : constant Natural := Family_Index_Of (UString_Value (Decl.Name), Family_By_Name);
      begin
         if Family_Index /= 0
           and then not Families (Positive (Family_Index)).Is_Admitted_Record_Family
         then
            Raise_Diag
              (CM.Unsupported_Source_Construct
                 (Path    => Path,
                  Span    => Decl.Span,
                  Message =>
                    Recursive_Family_Diagnostic_Message
                      (Families (Positive (Family_Index)))));
         end if;
      end;
      Result.Name := Decl.Name;
      case Decl.Kind is
         when CM.Type_Decl_Incomplete =>
            Result.Kind := FT.To_UString ("incomplete");
         when CM.Type_Decl_Interface =>
            Result.Kind := FT.To_UString ("interface");
            for Member of Decl.Interface_Members loop
               declare
                  Member_Info  : GM.Interface_Member;
                  Param_Info   : GM.Signature_Param;
               begin
                  if not Member.Has_Receiver then
                     Raise_Diag
                       (CM.Source_Frontend_Error
                          (Path    => Path,
                           Span    => Member.Span,
                           Message => "interface members require a receiver parameter"));
                  end if;

                  Member_Info.Name := Member.Name;
                  Param_Info.Name := Member.Receiver.Names (Member.Receiver.Names.First_Index);
                  Param_Info.Mode := Member.Receiver.Mode;
                  Param_Info.Type_Name := Decl.Name;
                  Member_Info.Params.Append (Param_Info);

                  for Param of Member.Params loop
                     declare
                        Param_Type : constant GM.Type_Descriptor :=
                          Resolve_Type_Spec (Param.Param_Type, Type_Env, Const_Env, Path);
                     begin
                        if Is_Interface_Type (Param_Type, Type_Env) then
                           Raise_Diag
                             (CM.Source_Frontend_Error
                                (Path    => Path,
                                 Span    => Param.Span,
                                 Message => "interface member parameters must use concrete non-interface types"));
                        end if;
                        for Param_Name of Param.Names loop
                           Param_Info := (others => <>);
                           Param_Info.Name := Param_Name;
                           Param_Info.Mode := Param.Mode;
                           Param_Info.Type_Name := Param_Type.Name;
                           Member_Info.Params.Append (Param_Info);
                        end loop;
                     end;
                  end loop;

                  if Member.Has_Return_Type then
                     declare
                        Return_Type : constant GM.Type_Descriptor :=
                          Resolve_Type_Spec (Member.Return_Type, Type_Env, Const_Env, Path);
                     begin
                        if Is_Interface_Type (Return_Type, Type_Env) then
                           Raise_Diag
                             (CM.Source_Frontend_Error
                                (Path    => Path,
                                 Span    => Member.Return_Type.Span,
                                 Message => "interface member returns must use concrete non-interface types"));
                        end if;
                        Member_Info.Has_Return_Type := True;
                        Member_Info.Return_Type := Return_Type.Name;
                        Member_Info.Return_Is_Access_Def := Member.Return_Is_Access_Def;
                     end;
                  end if;

                  Result.Interface_Members.Append (Member_Info);
               end;
            end loop;
         when CM.Type_Decl_Integer =>
            Result.Kind := FT.To_UString ("subtype");
            Result.Has_Base := True;
            Result.Base := FT.To_UString ("integer");
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
            if Result.Low > Result.High then
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path,
                     Span    => Decl.Span,
                     Message => "type lower bound exceeds upper bound"));
            end if;
         when CM.Type_Decl_Enumeration =>
            declare
               Seen : String_Index_Maps.Map;
               Ordinal : Long_Long_Integer := 0;
            begin
               if Decl.Enum_Literals.Is_Empty then
                  Raise_Diag
                    (CM.Source_Frontend_Error
                       (Path    => Path,
                        Span    => Decl.Span,
                        Message => "enumeration types require at least one literal"));
               end if;
               Result.Kind := FT.To_UString ("enum");
               Result.Has_Low := True;
               Result.Low := 0;
               Result.Has_High := True;
               Result.High := Long_Long_Integer (Natural (Decl.Enum_Literals.Length) - 1);
               for Literal of Decl.Enum_Literals loop
                  declare
                     Key : constant String := Canonical_Name (UString_Value (Literal));
                  begin
                     if Seen.Contains (Key) then
                        Raise_Diag
                          (CM.Source_Frontend_Error
                             (Path    => Path,
                              Span    => Decl.Span,
                              Message =>
                                "duplicate enum literal '" & UString_Value (Literal) & "'"));
                     end if;
                     Seen.Include (Key, Positive (Ordinal + 1));
                     Result.Enum_Literals.Append (Literal);
                     Ordinal := Ordinal + 1;
                  end;
               end loop;
            end;
         when CM.Type_Decl_Binary =>
            declare
               Width : constant CM.Wide_Integer :=
                 Literal_Value
                   (Decl.Binary_Width_Expr,
                    Const_Env,
                    Path,
                    "binary width must be one of 8, 16, 32, or 64");
            begin
               if Width not in 8 | 16 | 32 | 64 then
                  Raise_Diag
                    (CM.Source_Frontend_Error
                       (Path    => Path,
                        Span    => Decl.Span,
                        Message => "binary width must be one of 8, 16, 32, or 64"));
               end if;
               Result.Kind := FT.To_UString ("binary");
               Result.Has_Bit_Width := True;
               Result.Bit_Width := Positive (Width);
               if Width in 8 | 16 | 32 then
                  Result.Has_Low := True;
                  Result.Low := 0;
                  Result.Has_High := True;
                  Result.High := (2 ** Positive (Width)) - 1;
               end if;
            end;
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
                  declare
                     Index_Type : constant GM.Type_Descriptor :=
                       Resolve_Type
                         (Flatten_Name (Index_Item.Name_Expr),
                          Type_Env,
                          Path,
                          Index_Item.Span);
                     Index_Base : constant GM.Type_Descriptor := Base_Type (Index_Type, Type_Env);
                     Is_Constrained : constant Boolean :=
                       Is_Boolean_Type (Index_Type, Type_Env)
                       or else Is_Binary_Type (Index_Type, Type_Env)
                       or else
                         ((Index_Type.Has_Low and then Index_Type.Has_High)
                          and then not
                            (FT.Lowercase (UString_Value (Index_Type.Kind)) = "integer"
                             and then UString_Value (Index_Type.Name) = "integer"))
                       or else
                         ((Index_Base.Has_Low and then Index_Base.Has_High)
                          and then UString_Value (Index_Base.Name) /= "integer");
                  begin
                     if not Is_Discrete_Case_Type (Index_Type, Type_Env) then
                        Raise_Diag
                          (CM.Source_Frontend_Error
                             (Path    => Path,
                              Span    => Index_Item.Span,
                              Message => "array index type must be discrete"));
                     elsif not Is_Constrained then
                        Raise_Diag
                          (CM.Source_Frontend_Error
                             (Path    => Path,
                              Span    => Index_Item.Span,
                              Message => "array index type must be constrained"));
                     end if;
                  end;
                  Result.Index_Types.Append
                    (FT.To_UString (Flatten_Name (Index_Item.Name_Expr)));
               end if;
            end loop;
            Result.Has_Component_Type := True;
            declare
               Component_Type : constant GM.Type_Descriptor :=
                 Resolve_Type_Spec (Decl.Component_Type, Type_Env, Const_Env, Path);
            begin
               if Is_Interface_Type (Component_Type, Type_Env) then
                  Raise_Diag
                    (CM.Source_Frontend_Error
                       (Path    => Path,
                        Span    => Decl.Component_Type.Span,
                        Message => "interface types are only admitted in parameter positions in PR11.11b"));
               end if;
               Result.Component_Type := Component_Type.Name;
            end;
            Result.Unconstrained := Decl.Kind = CM.Type_Decl_Unconstrained_Array;
         when CM.Type_Decl_Growable_Array =>
            declare
               Component : constant GM.Type_Descriptor :=
                 Resolve_Type_Spec (Decl.Component_Type, Type_Env, Const_Env, Path);
            begin
               if Is_Interface_Type (Component, Type_Env) then
                  Raise_Diag
                    (CM.Source_Frontend_Error
                       (Path    => Path,
                        Span    => Decl.Component_Type.Span,
                        Message => "interface types are only admitted in parameter positions in PR11.11b"));
               end if;
               if FT.Lowercase (UString_Value (Component.Kind)) = "incomplete"
                 and then FT.Lowercase (UString_Value (Component.Name)) =
                          FT.Lowercase (UString_Value (Decl.Name))
               then
                  Raise_Diag
                    (CM.Unsupported_Source_Construct
                       (Path    => Path,
                        Span    => Decl.Span,
                        Message =>
                          "self-recursive array types are not admitted in PR11.8e; "
                          & "use a self-recursive record to form a reference cycle"));
               end if;
               Result := Make_Growable_Array_Type (Component, Type_Env);
               Result.Name := Decl.Name;
            end;
         when CM.Type_Decl_Sum =>
            declare
               Self_Name     : constant String := UString_Value (Decl.Name);
               Tag_Name      : constant String := Sum_Tag_Type_Name (Self_Name);
               Tag_Info      : GM.Type_Descriptor;
               Record_Result : GM.Type_Descriptor;
               Disc_Desc     : GM.Discriminant_Descriptor;
               Item          : GM.Type_Field;
               Seen          : String_Index_Maps.Map;
               Variant_Field : GM.Variant_Field;
               Variant_Ordinal : Long_Long_Integer := 0;
            begin
               if Decl.Sum_Variants.Is_Empty then
                  Raise_Diag
                    (CM.Source_Frontend_Error
                       (Path    => Path,
                        Span    => Decl.Span,
                        Message => "sum types require at least one variant"));
               end if;

               Tag_Info.Name := FT.To_UString (Tag_Name);
               Tag_Info.Kind := FT.To_UString ("enum");
               Tag_Info.Has_Low := True;
               Tag_Info.Low := 0;
               Tag_Info.Has_High := True;
               Tag_Info.High := Long_Long_Integer (Natural (Decl.Sum_Variants.Length) - 1);

               Record_Result.Name := Decl.Name;
               Record_Result.Kind := FT.To_UString ("record");
               Record_Result.Has_Discriminant := True;
               Record_Result.Discriminant_Name :=
                 FT.To_UString (Sum_Discriminant_Name (Self_Name));
               Record_Result.Discriminant_Type := Tag_Info.Name;
               Record_Result.Variant_Discriminant_Name := Record_Result.Discriminant_Name;

               Disc_Desc.Name := Record_Result.Discriminant_Name;
               Disc_Desc.Type_Name := Tag_Info.Name;
               Disc_Desc.Has_Default := True;

               for Variant of Decl.Sum_Variants loop
                  declare
                     Variant_Key     : constant String := Canonical_Name (UString_Value (Variant.Name));
                     Tag_Literal     : constant String :=
                       Sum_Tag_Literal_Name (Self_Name, UString_Value (Variant.Name));
                     Choice          : constant GM.Scalar_Value :=
                       (Kind      => GM.Scalar_Value_Enum,
                        Int_Value => 0,
                        Bool_Value => False,
                        Text      => FT.To_UString (Tag_Literal),
                        Type_Name => Tag_Info.Name);
                     Constructor     : Sum_Constructor_Info;
                     Sum_Variant     : GM.Sum_Variant_Descriptor;
                     Field_Seen      : String_Index_Maps.Map;
                  begin
                     if Seen.Contains (Variant_Key) then
                        Raise_Diag
                          (CM.Source_Frontend_Error
                             (Path    => Path,
                              Span    => Variant.Span,
                              Message =>
                                "duplicate sum variant `" & UString_Value (Variant.Name) & "`"));
                     end if;
                     Seen.Include (Variant_Key, Positive (Variant_Ordinal + 1));
                     Tag_Info.Enum_Literals.Append (FT.To_UString (Tag_Literal));
                     if Variant_Ordinal = 0 then
                        Disc_Desc.Default_Value := Choice;
                     end if;

                     Constructor.Name := Variant.Name;
                     Constructor.Sum_Type_Name := Decl.Name;
                     Constructor.Tag_Type_Name := Tag_Info.Name;
                     Constructor.Tag_Literal_Name := FT.To_UString (Tag_Literal);
                     Constructor.Span := Variant.Span;
                     Sum_Variant.Name := Variant.Name;
                     Sum_Variant.Tag_Literal_Name := FT.To_UString (Tag_Literal);

                     for Field_Decl of Variant.Components loop
                        declare
                           Source_Field_Name : constant String :=
                             UString_Value (Field_Decl.Names (Field_Decl.Names.First_Index));
                           Source_Field_Key : constant String :=
                             Canonical_Name (Source_Field_Name);
                           Field_Type : constant GM.Type_Descriptor :=
                             Resolve_Type_Spec
                               (Field_Decl.Field_Type,
                                Type_Env,
                                Const_Env,
                                Path);
                           Field_Info : Sum_Constructor_Field_Info;
                           Internal_Field_Name : constant FT.UString :=
                             FT.To_UString
                               (Sum_Variant_Field_Name
                                  (UString_Value (Variant.Name), Source_Field_Name));
                        begin
                           if Natural (Field_Decl.Names.Length) /= 1 then
                              Raise_Diag
                                (CM.Unsupported_Source_Construct
                                   (Path    => Path,
                                    Span    => Field_Decl.Span,
                                    Message =>
                                      "sum variant payload fields declare exactly one name in PR11.13a"));
                           elsif Field_Seen.Contains (Source_Field_Key) then
                              Raise_Diag
                                (CM.Source_Frontend_Error
                                   (Path    => Path,
                                    Span    => Field_Decl.Span,
                                    Message =>
                                      "duplicate payload field `"
                                      & Source_Field_Name
                                      & "` in sum variant `"
                                      & UString_Value (Variant.Name)
                                      & "`"));
                           elsif Is_Interface_Type (Field_Type, Type_Env) then
                              Raise_Diag
                                (CM.Source_Frontend_Error
                                   (Path    => Path,
                                    Span    => Field_Decl.Span,
                                    Message => "interface types are only admitted in parameter positions in PR11.11b"));
                           elsif not Is_Container_Element_Type_Allowed (Field_Type, Type_Env) then
                              Raise_Diag
                                (CM.Unsupported_Source_Construct
                                   (Path    => Path,
                                    Span    => Field_Decl.Span,
                                    Message =>
                                      "sum variant payloads are limited to the admitted value-type subset in PR11.13a"));
                           end if;

                           Field_Seen.Include
                             (Source_Field_Key,
                              Positive (Natural (Constructor.Fields.Length) + 1));

                           Item.Name := Internal_Field_Name;
                           Item.Type_Name := Field_Type.Name;
                           Record_Result.Fields.Append (Item);

                           Variant_Field.Name := Internal_Field_Name;
                           Variant_Field.Type_Name := Field_Type.Name;
                           Variant_Field.Is_Others := False;
                           Variant_Field.Choice := Choice;
                           Record_Result.Variant_Fields.Append (Variant_Field);

                           Field_Info.Source_Name := FT.To_UString (Source_Field_Name);
                           Field_Info.Name := Internal_Field_Name;
                           Field_Info.Type_Name := Field_Type.Name;
                           Constructor.Fields.Append (Field_Info);
                           Sum_Variant.Fields.Append
                             ((Source_Name   => FT.To_UString (Source_Field_Name),
                               Internal_Name => Internal_Field_Name,
                               Type_Name     => Field_Type.Name));
                        end;
                     end loop;

                     Record_Result.Sum_Variants.Append (Sum_Variant);
                     if not Current_Sum_Constructors.Contains (Variant_Key) then
                        Current_Sum_Constructors.Include (Variant_Key, Constructor);
                     end if;
                     Variant_Ordinal := Variant_Ordinal + 1;
                  end;
               end loop;

               Record_Result.Discriminants.Append (Disc_Desc);
               Put_Type (Type_Env, Tag_Name, Tag_Info);
               if not Current_Sum_Tag_Types.Contains (Canonical_Name (Tag_Name)) then
                  Current_Sum_Tag_Types.Include (Canonical_Name (Tag_Name), Tag_Info);
               end if;
               Current_Sum_Type_Tag_Names.Include
                 (Canonical_Name (Self_Name), Tag_Name);
               Result := Record_Result;
            end;
         when CM.Type_Decl_Record =>
            declare
               Record_Result          : GM.Type_Descriptor;
               Self_Name              : constant String := UString_Value (Decl.Name);
               Hidden_Target_Name     : constant String := Hidden_Reference_Target_Name (Self_Name);
               Inferred_Reference     : Boolean :=
                 Is_Admitted_Record_Family_Member
                   (Self_Name,
                    Family_By_Name,
                    Families);
               Decl_Discriminants     : CM.Discriminant_Spec_Vectors.Vector := Decl.Discriminants;

               function Normalize_Record_Field_Type
                 (Field_Type : GM.Type_Descriptor;
                  Span       : FT.Source_Span) return GM.Type_Descriptor
               is
                  Base_Field : constant GM.Type_Descriptor := Base_Type (Field_Type, Type_Env);
                  Adjusted   : GM.Type_Descriptor := Field_Type;
               begin
                  if Is_Interface_Type (Field_Type, Type_Env) then
                     Raise_Diag
                       (CM.Source_Frontend_Error
                          (Path    => Path,
                           Span    => Span,
                           Message => "interface types are only admitted in parameter positions in PR11.11b"));
                  end if;
                  if FT.Lowercase (UString_Value (Base_Field.Kind)) = "incomplete" then
                     if In_Same_Admitted_Record_Family
                       (Self_Name,
                        UString_Value (Base_Field.Name),
                        Family_By_Name,
                        Families)
                     then
                        Adjusted.Name := Base_Field.Name;
                        if Adjusted.Has_Base
                          and then Canonical_Name (UString_Value (Adjusted.Base)) =
                            Canonical_Name (UString_Value (Base_Field.Name))
                        then
                           Adjusted.Base := Base_Field.Name;
                        end if;
                        return Adjusted;
                     end if;

                     Raise_Diag
                       (CM.Unsupported_Source_Construct
                          (Path    => Path,
                           Span    => Span,
                           Message =>
                             "record fields may reference unresolved incomplete types only within an admitted recursive record family"));
                  end if;
                  return Field_Type;
               end Normalize_Record_Field_Type;
            begin
               Record_Result.Name := FT.To_UString (Hidden_Target_Name);
               Record_Result.Kind := FT.To_UString ("record");
               if Decl_Discriminants.Is_Empty and then Decl.Has_Discriminant then
                  Decl_Discriminants.Append (Decl.Discriminant);
               end if;
               for Disc_Spec of Decl_Discriminants loop
                  declare
                     Disc_Type    : constant GM.Type_Descriptor :=
                       Resolve_Type_Spec
                         (Disc_Spec.Disc_Type,
                          Type_Env,
                          Const_Env,
                          Path,
                          Current_Record_Name => Self_Name,
                          Family_By_Name      => Family_By_Name,
                          Families            => Families);
                     Disc_Desc    : GM.Discriminant_Descriptor;
                     Static_Value : CM.Static_Value;
                  begin
                     if not Is_Discrete_Case_Type (Disc_Type, Type_Env) then
                        Raise_Diag
                          (CM.Unsupported_Source_Construct
                             (Path    => Path,
                              Span    => Disc_Spec.Span,
                              Message => "record discriminants currently support only boolean, enum, binary, and integer-family types"));
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
                     Record_Result.Discriminants.Append (Disc_Desc);
                  end;
               end loop;
               if not Record_Result.Discriminants.Is_Empty then
                  Record_Result.Has_Discriminant := True;
                  Record_Result.Discriminant_Name := Record_Result.Discriminants (Record_Result.Discriminants.First_Index).Name;
                  Record_Result.Discriminant_Type := Record_Result.Discriminants (Record_Result.Discriminants.First_Index).Type_Name;
                  if Record_Result.Discriminants (Record_Result.Discriminants.First_Index).Has_Default
                    and then Record_Result.Discriminants (Record_Result.Discriminants.First_Index).Default_Value.Kind =
                      GM.Scalar_Value_Boolean
                  then
                     Record_Result.Has_Discriminant_Default := True;
                     Record_Result.Discriminant_Default_Bool :=
                       Record_Result.Discriminants (Record_Result.Discriminants.First_Index).Default_Value.Bool_Value;
                  end if;
               end if;
               for Field_Decl of Decl.Components loop
                  for Name of Field_Decl.Names loop
                     Item.Name := Name;
                     declare
                        Field_Type : constant GM.Type_Descriptor :=
                          Normalize_Record_Field_Type
                            (Resolve_Type_Spec
                               (Field_Decl.Field_Type,
                                Type_Env,
                                Const_Env,
                                Path,
                                Current_Record_Name => Self_Name,
                                Family_By_Name      => Family_By_Name,
                                Families            => Families),
                             Field_Decl.Span);
                     begin
                        Item.Type_Name := Field_Type.Name;
                     end;
                     Record_Result.Fields.Append (Item);
                  end loop;
               end loop;
               if not Decl.Variants.Is_Empty then
                  declare
                     Control_Type : GM.Type_Descriptor;
                     Found_Control : Boolean := False;
                  begin
                     if Record_Result.Discriminants.Is_Empty then
                        Raise_Diag
                          (CM.Source_Frontend_Error
                             (Path    => Path,
                              Span    => Decl.Span,
                              Message => "variant parts require declared discriminants"));
                     end if;
                     Record_Result.Variant_Discriminant_Name := Decl.Variant_Discriminant_Name;
                     for Disc of Record_Result.Discriminants loop
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
                                      Normalize_Record_Field_Type
                                        (Resolve_Type_Spec
                                           (Field_Decl.Field_Type,
                                            Type_Env,
                                            Const_Env,
                                            Path,
                                            Current_Record_Name => Self_Name,
                                            Family_By_Name      => Family_By_Name,
                                            Families            => Families),
                                         Field_Decl.Span);
                                 begin
                                    Item.Type_Name := Field_Type.Name;
                                 end;
                                 Record_Result.Fields.Append (Item);
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
                                    Record_Result.Variant_Fields.Append (Variant_Field);
                                 end;
                              end loop;
                           end loop;
                        end;
                     end loop;
                  end;
               end if;
               if Inferred_Reference then
                  Put_Type (Type_Env, Hidden_Target_Name, Record_Result);
                  Result.Kind := FT.To_UString ("access");
                  Result.Has_Target := True;
                  Result.Target := FT.To_UString (Hidden_Target_Name);
                  Result.Anonymous := False;
                  Result.Is_All := False;
                  Result.Is_Constant := False;
                  Result.Has_Access_Role := True;
                  Result.Access_Role := FT.To_UString ("Owner");
               else
                  Result := Record_Result;
                  Result.Name := Decl.Name;
               end if;
            end;
         when CM.Type_Decl_Access =>
            declare
               Target_Info : constant GM.Type_Descriptor :=
                 Resolve_Type (Flatten_Name (Decl.Access_Type.Target_Name), Type_Env, Path, Decl.Span);
            begin
               if Is_Interface_Type (Target_Info, Type_Env) then
                  Raise_Diag
                    (CM.Source_Frontend_Error
                       (Path    => Path,
                        Span    => Decl.Span,
                        Message => "interface types are only admitted in parameter positions in PR11.11b"));
               end if;
               Result.Kind := FT.To_UString ("access");
               Result.Has_Target := True;
               Result.Target := Target_Info.Name;
            end;
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

   function Instantiate_Generic_Type
     (Template_Name : String;
      Spec          : CM.Type_Spec;
      Type_Env      : Type_Maps.Map;
      Const_Env     : Static_Value_Maps.Map;
      Path          : String) return GM.Type_Descriptor
   is
      Template_Key       : constant String := Canonical_Name (Template_Name);
      Template           : Generic_Type_Template_Info;
      Actual_Type_Names  : FT.UString_Vectors.Vector;
      Template_Formals   : CM.Generic_Formal_Vectors.Vector;
      Instantiation_Key  : FT.UString := FT.To_UString ("");
      Concrete_Name      : FT.UString := FT.To_UString ("");
      Clone              : CM.Type_Decl;
      Local_Type_Env     : Type_Maps.Map := Type_Env;
      Result             : GM.Type_Descriptor;
   begin
      if not Current_Generic_Type_Templates.Contains (Template_Key) then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path,
               Span    => Spec.Span,
               Message => "unknown generic type `" & Template_Name & "`"));
      end if;

      Template := Current_Generic_Type_Templates.Element (Template_Key);

      if Template.Has_Decl then
         Template_Formals := Template.Decl.Generic_Formals;
      elsif not Template.Info.Generic_Formals.Is_Empty then
         for Formal of Template.Info.Generic_Formals loop
            Template_Formals.Append
              ((Name            => Formal.Name,
                Has_Constraint  => Formal.Has_Constraint,
                Constraint_Name => Formal.Constraint_Name,
                Span            => FT.Null_Span));
         end loop;
      end if;

      if not Spec.Generic_Args.Is_Empty then
         for Arg of Spec.Generic_Args loop
            Actual_Type_Names.Append
              (Resolve_Type_Spec (Arg.all, Type_Env, Const_Env, Path).Name);
         end loop;
      end if;

      Validate_Generic_Actuals
        (Template_Formals,
         Actual_Type_Names,
         Current_Generic_Function_Env,
         Type_Env,
         Path,
         Spec.Span);

      Instantiation_Key :=
        FT.To_UString
          (Generic_Template_Key
             (UString_Value (Template.Info.Name),
              Actual_Type_Names));
      if Current_Generic_Type_Instantiation_By_Key.Contains (UString_Value (Instantiation_Key)) then
         Concrete_Name :=
           FT.To_UString
             (Current_Generic_Type_Instantiation_By_Key.Element
                (UString_Value (Instantiation_Key)));
         return Get_Type
           (Current_Generic_Type_Instantiations,
            UString_Value (Concrete_Name));
      end if;

      for Item of Current_Generic_Type_Instantiation_Stack loop
         if Item = UString_Value (Instantiation_Key) then
            Raise_Diag
              (CM.Unsupported_Source_Construct
                 (Path    => Path,
                  Span    => Spec.Span,
                  Message =>
                    "self-referential generic type instantiation is outside PR11.11c"));
         end if;
      end loop;

      Concrete_Name :=
        FT.To_UString
          (Generic_Specialization_Name
             ("__generic_",
              UString_Value (Template.Info.Name),
              Actual_Type_Names));
      if Template.Has_Decl then
         Clone := Template.Decl;
         Clone.Generic_Formals.Clear;
         Clone.Name := Concrete_Name;

         if not Template.Decl.Generic_Formals.Is_Empty then
            for Index in Template.Decl.Generic_Formals.First_Index .. Template.Decl.Generic_Formals.Last_Index loop
               Put_Type
                 (Local_Type_Env,
                  UString_Value (Template.Decl.Generic_Formals (Index).Name),
                  Resolve_Type
                    (UString_Value (Actual_Type_Names (Index)),
                     Type_Env,
                     Path,
                     Spec.Span));
            end loop;
         end if;

         Current_Generic_Type_Instantiation_Stack.Append (UString_Value (Instantiation_Key));
         Result :=
           Resolve_Type_Declaration
             (Clone,
              Local_Type_Env,
              Const_Env,
              Path);
         Current_Generic_Type_Instantiation_Stack.Delete_Last;
      else
         Result :=
           Substitute_Generic_Type_Info
             (Template.Info,
              Template.Info.Generic_Formals,
              Actual_Type_Names);
      end if;

      Result.Name := Concrete_Name;
      Result.Has_Generic_Origin := True;
      Result.Generic_Origin := FT.To_UString (Template_Name);
      Result.Generic_Actual_Types := Actual_Type_Names;

      Put_Type
        (Current_Generic_Type_Instantiations,
         UString_Value (Concrete_Name),
         Result);
      Current_Generic_Type_Instantiation_By_Key.Include
        (UString_Value (Instantiation_Key), UString_Value (Concrete_Name));
      Append_Unique_String
        (Current_Generic_Type_Instantiation_Order,
         UString_Value (Concrete_Name));
      return Result;
   exception
      when others =>
         if not Current_Generic_Type_Instantiation_Stack.Is_Empty
           and then Current_Generic_Type_Instantiation_Stack
             (Current_Generic_Type_Instantiation_Stack.Last_Index)
               = UString_Value (Instantiation_Key)
         then
            Current_Generic_Type_Instantiation_Stack.Delete_Last;
         end if;
         raise;
   end Instantiate_Generic_Type;

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
      Result.Generic_Formals := Decl.Spec.Generic_Formals;
      Result.Span := Decl.Span;
      Result.Return_Is_Access_Def := Decl.Spec.Return_Is_Access_Def;
      if Decl.Spec.Has_Receiver then
         declare
            Param_Type : constant GM.Type_Descriptor :=
              Canonicalize_Imported_Synthetic_Type
                (Resolve_Type_Spec (Decl.Spec.Receiver.Param_Type, Type_Env, Const_Env, Path),
                 Type_Env);
         begin
            Symbol.Name := Decl.Spec.Receiver.Names (Decl.Spec.Receiver.Names.First_Index);
            Symbol.Kind := FT.To_UString ("param");
               Symbol.Mode := Decl.Spec.Receiver.Mode;
               Symbol.Span := Decl.Spec.Receiver.Span;
               Symbol.Type_Info := Param_Type;
               Result.Params.Append (Symbol);
         end;
      end if;
      for Param of Decl.Spec.Params loop
         declare
            Param_Type : constant GM.Type_Descriptor :=
              Canonicalize_Imported_Synthetic_Type
                (Resolve_Type_Spec (Param.Param_Type, Type_Env, Const_Env, Path),
                 Type_Env);
         begin
            if Is_Interface_Type (Param_Type, Type_Env)
              and then Natural (Param.Names.Length) /= 1
            then
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path,
                     Span    => Param.Span,
                     Message => "interface-typed parameters must declare exactly one name in PR11.11b"));
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
           Canonicalize_Imported_Synthetic_Type
             (Resolve_Type_Spec (Decl.Spec.Return_Type, Type_Env, Const_Env, Path),
              Type_Env);
         if Is_Interface_Type (Result.Return_Type, Type_Env) then
            Raise_Diag
              (CM.Source_Frontend_Error
                 (Path    => Path,
                  Span    => Decl.Spec.Return_Type.Span,
                  Message => "interface types are only admitted in parameter positions in PR11.11b"));
         end if;
      end if;
      return Result;
   end Register_Function;

   function Interface_Has_Member
     (Info        : GM.Type_Descriptor;
      Member_Name : String) return Boolean
   is
      Canonical_Member : constant String := Canonical_Name (Member_Name);
   begin
      if not Info.Interface_Members.Is_Empty then
         for Member of Info.Interface_Members loop
            if Canonical_Name (UString_Value (Member.Name)) = Canonical_Member then
               return True;
            end if;
         end loop;
      end if;
      return False;
   end Interface_Has_Member;

   procedure Validate_Interface_Method_Syntax
     (Decl     : CM.Subprogram_Body;
      Info     : Function_Info;
      Type_Env : Type_Maps.Map;
      Path     : String)
   is
      function Param_Interface_Type (Name : String) return GM.Type_Descriptor is
      begin
         if not Info.Params.Is_Empty then
            for Param of Info.Params loop
               if UString_Value (Param.Name) = Name then
                  if Is_Interface_Type (Param.Type_Info, Type_Env) then
                     return Base_Type (Param.Type_Info, Type_Env);
                  elsif Is_Generic_Formal_Type (Param.Type_Info, Type_Env) then
                     declare
                        Generic_Info : constant GM.Type_Descriptor :=
                          Base_Type (Param.Type_Info, Type_Env);
                     begin
                        if Generic_Info.Has_Base then
                           declare
                              Constraint_Info : constant GM.Type_Descriptor :=
                                Resolve_Type
                                  (UString_Value (Generic_Info.Base),
                                   Type_Env,
                                   Path,
                                   Decl.Span);
                           begin
                              if Is_Interface_Type (Constraint_Info, Type_Env) then
                                 return Base_Type (Constraint_Info, Type_Env);
                              end if;
                           end;
                        end if;
                     end;
                  end if;
               end if;
            end loop;
         end if;
         return (others => <>);
      end Param_Interface_Type;

      procedure Validate_Expr (Expr : CM.Expr_Access);

      procedure Validate_Statement_List
        (Statements : CM.Statement_Access_Vectors.Vector);

      procedure Validate_Expr (Expr : CM.Expr_Access) is
         function Is_Interface_Method_Syntax return Boolean is
         begin
            if Expr = null
              or else Expr.Callee = null
              or else Expr.Callee.Kind /= CM.Expr_Select
              or else Expr.Callee.Prefix = null
              or else Expr.Callee.Prefix.Kind /= CM.Expr_Ident
            then
               return False;
            end if;

            declare
               Prefix_Interface_Info : constant GM.Type_Descriptor :=
                 Param_Interface_Type
                   (UString_Value (Expr.Callee.Prefix.Name));
            begin
               return
                 UString_Value (Prefix_Interface_Info.Name)'Length > 0
                 and then Interface_Has_Member
                   (Prefix_Interface_Info,
                    FT.Lowercase (UString_Value (Expr.Callee.Selector)));
            end;
         end Is_Interface_Method_Syntax;
      begin
         if Expr = null then
            return;
         end if;

         case Expr.Kind is
            when CM.Expr_Apply | CM.Expr_Call =>
               if Expr.Callee /= null and then not Expr.Args.Is_Empty then
                  declare
                     Callee_Name : constant String :=
                       Method_Target_Tail_Name (Flatten_Name (Expr.Callee));
                     First_Arg : constant CM.Expr_Access := Expr.Args (Expr.Args.First_Index);
                  begin
                     if not Is_Interface_Method_Syntax
                       and then First_Arg /= null
                       and then First_Arg.Kind = CM.Expr_Ident
                     then
                        declare
                           Interface_Info : constant GM.Type_Descriptor :=
                             Param_Interface_Type (UString_Value (First_Arg.Name));
                        begin
                           if UString_Value (Interface_Info.Name)'Length > 0
                             and then Interface_Has_Member (Interface_Info, Callee_Name)
                           then
                              Raise_Diag
                                (CM.Source_Frontend_Error
                                   (Path    => Path,
                                    Span    => Expr.Span,
                                    Message =>
                                      "interface member calls on interface-typed parameters must use method syntax in PR11.11b"));
                           end if;
                        end;
                     end if;
                  end;
               end if;

               Validate_Expr (Expr.Callee);
               if not Expr.Args.Is_Empty then
                  for Arg of Expr.Args loop
                     Validate_Expr (Arg);
                  end loop;
               end if;
            when CM.Expr_Select =>
               Validate_Expr (Expr.Prefix);
            when CM.Expr_Binary =>
               Validate_Expr (Expr.Left);
               Validate_Expr (Expr.Right);
            when CM.Expr_Unary | CM.Expr_Annotated =>
               Validate_Expr (Expr.Inner);
            when CM.Expr_Conversion =>
               Validate_Expr (Expr.Inner);
            when CM.Expr_Allocator =>
               Validate_Expr (Expr.Value);
            when CM.Expr_Aggregate =>
               if not Expr.Fields.Is_Empty then
                  for Field of Expr.Fields loop
                     Validate_Expr (Field.Expr);
                  end loop;
               end if;
            when CM.Expr_Array_Literal | CM.Expr_Tuple =>
               if not Expr.Elements.Is_Empty then
                  for Item of Expr.Elements loop
                     Validate_Expr (Item);
                  end loop;
               end if;
            when CM.Expr_Resolved_Index =>
               Validate_Expr (Expr.Prefix);
               if not Expr.Args.Is_Empty then
                  for Arg of Expr.Args loop
                     Validate_Expr (Arg);
                  end loop;
               end if;
            when others =>
               null;
         end case;
      end Validate_Expr;

      procedure Validate_Statement_List
        (Statements : CM.Statement_Access_Vectors.Vector)
      is
      begin
         if Statements.Is_Empty then
            return;
         end if;

         for Stmt of Statements loop
            if Stmt = null then
               null;
            else
               case Stmt.Kind is
                  when CM.Stmt_Assign =>
                     Validate_Expr (Stmt.Target);
                     Validate_Expr (Stmt.Value);
                  when CM.Stmt_Call =>
                     Validate_Expr (Stmt.Call);
                  when CM.Stmt_Return | CM.Stmt_Delay =>
                     Validate_Expr (Stmt.Value);
                  when CM.Stmt_Object_Decl =>
                     Validate_Expr (Stmt.Decl.Initializer);
                  when CM.Stmt_Destructure_Decl =>
                     Validate_Expr (Stmt.Decl.Initializer);
                  when CM.Stmt_Receive | CM.Stmt_Try_Receive =>
                     Validate_Expr (Stmt.Channel_Name);
                     Validate_Expr (Stmt.Target);
                  when CM.Stmt_Send | CM.Stmt_Try_Send =>
                     Validate_Expr (Stmt.Channel_Name);
                     Validate_Expr (Stmt.Value);
                     Validate_Expr (Stmt.Success_Var);
                  when CM.Stmt_If =>
                     Validate_Expr (Stmt.Condition);
                     Validate_Statement_List (Stmt.Then_Stmts);
                     for Part of Stmt.Elsifs loop
                        Validate_Expr (Part.Condition);
                        Validate_Statement_List (Part.Statements);
                     end loop;
                     if Stmt.Has_Else then
                        Validate_Statement_List (Stmt.Else_Stmts);
                     end if;
                  when CM.Stmt_Case =>
                     Validate_Expr (Stmt.Case_Expr);
                     for Arm of Stmt.Case_Arms loop
                        Validate_Expr (Arm.Choice);
                        Validate_Statement_List (Arm.Statements);
                     end loop;
                  when CM.Stmt_While =>
                     Validate_Expr (Stmt.Condition);
                     Validate_Statement_List (Stmt.Body_Stmts);
                  when CM.Stmt_For | CM.Stmt_Loop =>
                     Validate_Statement_List (Stmt.Body_Stmts);
                  when CM.Stmt_Select =>
                     for Arm of Stmt.Arms loop
                        case Arm.Kind is
                           when CM.Select_Arm_Channel =>
                              Validate_Expr (Arm.Channel_Data.Channel_Name);
                              Validate_Statement_List (Arm.Channel_Data.Statements);
                           when CM.Select_Arm_Delay =>
                              Validate_Expr (Arm.Delay_Data.Duration_Expr);
                              Validate_Statement_List (Arm.Delay_Data.Statements);
                           when others =>
                              null;
                        end case;
                     end loop;
                  when CM.Stmt_Match =>
                     Validate_Expr (Stmt.Match_Expr);
                     for Arm of Stmt.Match_Arms loop
                        Validate_Statement_List (Arm.Statements);
                     end loop;
                  when others =>
                     null;
               end case;
            end if;
         end loop;
      end Validate_Statement_List;
   begin
      Validate_Statement_List (Decl.Statements);
   end Validate_Interface_Method_Syntax;

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
      if not Is_Definite_Type (Type_Info, Type_Env) then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path,
               Span    => Decl.Element_Type.Span,
               Message => "channel element type must be definite"));
      end if;

      if Contains_Channel_Reference_Subcomponent (Type_Info, Type_Env) then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path,
               Span    => Decl.Element_Type.Span,
               Message =>
                 "channel element type must be a value type; reference-bearing channel elements are not admitted"));
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

   function Item_Is_Public (Item : CM.Package_Item) return Boolean is
   begin
      case Item.Kind is
         when CM.Item_Type_Decl =>
            return Item.Type_Data.Is_Public;
         when CM.Item_Subtype_Decl =>
            return Item.Sub_Data.Is_Public;
         when CM.Item_Object_Decl =>
            return Item.Obj_Data.Is_Public;
         when CM.Item_Subprogram =>
            return Item.Subp_Data.Is_Public;
         when CM.Item_Task =>
            return False;
         when CM.Item_Channel =>
            return Item.Chan_Data.Is_Public;
         when others =>
            return False;
      end case;
   end Item_Is_Public;

   procedure Validate_Unit_Statements
     (Statements : CM.Statement_Access_Vectors.Vector;
      Path       : String) is
   begin
      for Stmt of Statements loop
         case Stmt.Kind is
            when CM.Stmt_Object_Decl | CM.Stmt_Destructure_Decl =>
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path,
                     Span    => Stmt.Span,
                     Message => "unit-scope statements must not contain local declarations"));
            when CM.Stmt_Return =>
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path,
                     Span    => Stmt.Span,
                     Message => "unit-scope statements must not contain return statements"));
            when CM.Stmt_Receive | CM.Stmt_Try_Receive =>
               if not Stmt.Decl.Names.Is_Empty then
                  Raise_Diag
                    (CM.Source_Frontend_Error
                       (Path    => Path,
                        Span    => Stmt.Span,
                        Message => "unit-scope statements must not contain local declarations"));
               end if;
            when CM.Stmt_If =>
               Validate_Unit_Statements (Stmt.Then_Stmts, Path);
               for Part of Stmt.Elsifs loop
                  Validate_Unit_Statements (Part.Statements, Path);
               end loop;
               if Stmt.Has_Else then
                  Validate_Unit_Statements (Stmt.Else_Stmts, Path);
               end if;
            when CM.Stmt_Case =>
               for Arm of Stmt.Case_Arms loop
                  Validate_Unit_Statements (Arm.Statements, Path);
               end loop;
            when CM.Stmt_While | CM.Stmt_For | CM.Stmt_Loop =>
               Validate_Unit_Statements (Stmt.Body_Stmts, Path);
            when CM.Stmt_Select =>
               for Arm of Stmt.Arms loop
                  case Arm.Kind is
                     when CM.Select_Arm_Channel =>
                        Validate_Unit_Statements (Arm.Channel_Data.Statements, Path);
                     when CM.Select_Arm_Delay =>
                        Validate_Unit_Statements (Arm.Delay_Data.Statements, Path);
                     when others =>
                        null;
                  end case;
               end loop;
            when others =>
               null;
         end case;
      end loop;
   end Validate_Unit_Statements;

   function Resolve
     (Unit        : CM.Parsed_Unit;
      Search_Dirs : FT.UString_Vectors.Vector := FT.UString_Vectors.Empty_Vector;
      Target_Bits : Positive := 64)
      return CM.Resolve_Result
   is
      Normalized_Target_Bits : constant Positive := (if BT.Is_Valid_Target_Bits (Target_Bits) then Target_Bits else 64);
      Type_Env         : Type_Maps.Map;
      Functions        : Function_Maps.Map;
      Package_Vars     : Type_Maps.Map;
      Channel_Env      : Type_Maps.Map;
      Const_Env        : Static_Value_Maps.Map;
      Imported_Objects : Type_Maps.Map;
      Task_Priorities  : Task_Priority_Vectors.Vector;
      Result           : CM.Resolved_Unit;
      Completed_Local_Type_Decls   : Type_Decl_Vectors.Vector;
      Completed_Local_Type_Names   : String_Vectors.Vector;
      Completed_Local_Type_Indexes : String_Index_Maps.Map;
      Pending_Hidden_Targets       : String_Vectors.Vector;
      Family_By_Name               : String_Index_Maps.Map;
      Families                     : Recursive_Family_Vectors.Vector;

      function Visible_Value_Name_Exists
        (Name      : String;
         Value_Env : Type_Maps.Map) return Boolean is
      begin
         return Has_Type (Value_Env, Name)
           and then not Has_Type (Type_Env, Name);
      end Visible_Value_Name_Exists;

      procedure Reject_Enum_Literal_Collision
        (Name      : String;
         Value_Env : Type_Maps.Map;
         Span      : FT.Source_Span;
         Path      : String) is
      begin
         if Has_Enum_Literal (Const_Env, Name)
           or else Has_Sum_Constructor (Name)
           or else Visible_Value_Name_Exists (Name, Value_Env)
           or else Has_Function (Functions, Name)
           or else Has_Type (Type_Env, Name)
           or else Has_Type (Channel_Env, Name)
         then
            Raise_Diag
              (CM.Source_Frontend_Error
                 (Path    => Path,
                  Span    => Span,
                  Message =>
                    "enum literal '" & Name
                    & "' conflicts with another visible package-level name"));
         end if;
      end Reject_Enum_Literal_Collision;

      procedure Reject_Sum_Constructor_Collision
        (Name      : String;
         Value_Env : Type_Maps.Map;
         Span      : FT.Source_Span;
         Path      : String) is
      begin
         if Has_Sum_Constructor (Name)
           or else Has_Enum_Literal (Const_Env, Name)
           or else Visible_Value_Name_Exists (Name, Value_Env)
           or else Has_Function (Functions, Name)
           or else Has_Type (Type_Env, Name)
           or else Has_Type (Channel_Env, Name)
         then
            Raise_Diag
              (CM.Source_Frontend_Error
                 (Path    => Path,
                  Span    => Span,
                  Message =>
                    "sum variant constructor '" & Name
                    & "' conflicts with another visible package-level name"));
         end if;
      end Reject_Sum_Constructor_Collision;

      procedure Register_Enum_Literals
        (Info      : GM.Type_Descriptor;
         Value_Env : in out Type_Maps.Map;
         Qualifier : String := "";
         Path      : String := "";
         Span      : FT.Source_Span := FT.Null_Span) is
      begin
         if not Is_Enum_Type (Info, Type_Env) then
            return;
         end if;

         for Literal of Info.Enum_Literals loop
            declare
               Qualified_Name : constant String :=
                 (if Qualifier = ""
                  then UString_Value (Literal)
                  else Qualify_Name (Qualifier, UString_Value (Literal)));
               Static_Info    : CM.Static_Value := (others => <>);
            begin
               Reject_Enum_Literal_Collision (Qualified_Name, Value_Env, Span, Path);
               Put_Type (Value_Env, Qualified_Name, Info);
               Static_Info.Kind := CM.Static_Value_Enum;
               Static_Info.Text := Literal;
               Static_Info.Type_Name := Info.Name;
               Put_Static_Value (Const_Env, Qualified_Name, Static_Info);
            end;
         end loop;
      end Register_Enum_Literals;

      procedure Reject_Package_Level_Enum_Collision
        (Name : String;
         Span : FT.Source_Span;
         Path : String) is
      begin
         if Has_Enum_Literal (Const_Env, Name) then
            Raise_Diag
              (CM.Source_Frontend_Error
                 (Path    => Path,
                  Span    => Span,
                  Message =>
                    "package-level name '" & Name
                    & "' conflicts with an enum literal already visible in this package"));
         end if;
      end Reject_Package_Level_Enum_Collision;

      procedure Reject_Package_Level_Sum_Constructor_Collision
        (Name : String;
         Span : FT.Source_Span;
         Path : String) is
      begin
         if Has_Sum_Constructor (Name) then
            Raise_Diag
              (CM.Source_Frontend_Error
                 (Path    => Path,
                  Span    => Span,
                  Message =>
                    "package-level name '" & Name
                    & "' conflicts with a sum variant constructor already visible in this package"));
         end if;
      end Reject_Package_Level_Sum_Constructor_Collision;

      procedure Reject_Shared_Wrapper_Name_Collisions is
         procedure Reject_If_Collides
           (Name         : String;
            Span         : FT.Source_Span;
            Shared_Root  : String;
            Wrapper_Name : String) is
         begin
            if Canonical_Name (Name) = Canonical_Name (Wrapper_Name) then
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => UString_Value (Unit.Path),
                     Span    => Span,
                     Message =>
                       "package-level name '" & Name
                       & "' conflicts with compiler-generated shared wrapper name '"
                       & Wrapper_Name
                       & "' for shared object '" & Shared_Root & "'"));
            end if;
         end Reject_If_Collides;
      begin
         for Item of Unit.Items loop
            if Item.Kind = CM.Item_Object_Decl
              and then Item.Obj_Data.Is_Shared
              and then not Item.Obj_Data.Names.Is_Empty
            then
               declare
                  Shared_Root  : constant String :=
                    UString_Value (Item.Obj_Data.Names (Item.Obj_Data.Names.First_Index));
                  Wrapper_Name : constant String :=
                    Shared_Wrapper_Object_Name (Shared_Root);
               begin
                  for Other of Unit.Items loop
                     case Other.Kind is
                        when CM.Item_Type_Decl =>
                           Reject_If_Collides
                             (UString_Value (Other.Type_Data.Name),
                              Other.Type_Data.Span,
                              Shared_Root,
                              Wrapper_Name);
                           for Literal of Other.Type_Data.Enum_Literals loop
                              Reject_If_Collides
                                (UString_Value (Literal),
                                 Other.Type_Data.Span,
                                 Shared_Root,
                                 Wrapper_Name);
                           end loop;
                        when CM.Item_Subtype_Decl =>
                           Reject_If_Collides
                             (UString_Value (Other.Sub_Data.Name),
                              Other.Sub_Data.Span,
                              Shared_Root,
                              Wrapper_Name);
                        when CM.Item_Channel =>
                           Reject_If_Collides
                             (UString_Value (Other.Chan_Data.Name),
                              Other.Chan_Data.Span,
                              Shared_Root,
                              Wrapper_Name);
                        when CM.Item_Object_Decl =>
                           for Name of Other.Obj_Data.Names loop
                              Reject_If_Collides
                                (UString_Value (Name),
                                 Other.Obj_Data.Span,
                                 Shared_Root,
                                 Wrapper_Name);
                           end loop;
                        when CM.Item_Task =>
                           Reject_If_Collides
                             (UString_Value (Other.Task_Data.Name),
                              Other.Task_Data.Span,
                              Shared_Root,
                              Wrapper_Name);
                        when CM.Item_Subprogram =>
                           Reject_If_Collides
                             (UString_Value (Other.Subp_Data.Spec.Name),
                              Other.Subp_Data.Span,
                              Shared_Root,
                              Wrapper_Name);
                        when others =>
                           null;
                     end case;
                  end loop;
               end;
            end if;
         end loop;
      end Reject_Shared_Wrapper_Name_Collisions;

      procedure Analyze_Recursive_Type_Families is
         procedure Register_Completed_Local_Type (Decl : CM.Type_Decl) is
            Name : constant String := UString_Value (Decl.Name);
            Key  : constant String := Canonical_Name (Name);
         begin
            if not Completed_Local_Type_Indexes.Contains (Key) then
               Completed_Local_Type_Decls.Append (Decl);
               Completed_Local_Type_Names.Append (Name);
               Completed_Local_Type_Indexes.Include
                 (Key,
                  Positive (Completed_Local_Type_Decls.Last_Index));
            end if;
         end Register_Completed_Local_Type;

         procedure Append_Local_Type_Dependency
           (Deps : in out String_Vectors.Vector;
            Name : String) is
            Key : constant String := Canonical_Name (Name);
         begin
            if Completed_Local_Type_Indexes.Contains (Key) then
               Append_Unique_String (Deps, Name);
            end if;
         end Append_Local_Type_Dependency;

         procedure Collect_Type_Spec_Dependencies
           (Spec : CM.Type_Spec;
            Deps : in out String_Vectors.Vector) is
         begin
            case Spec.Kind is
               when CM.Type_Spec_Name | CM.Type_Spec_Subtype_Indication =>
                  if UString_Value (Spec.Name)'Length > 0 then
                     Append_Local_Type_Dependency (Deps, UString_Value (Spec.Name));
                  end if;
               when CM.Type_Spec_List | CM.Type_Spec_Growable_Array | CM.Type_Spec_Optional =>
                  if Spec.Element_Type /= null then
                     Collect_Type_Spec_Dependencies (Spec.Element_Type.all, Deps);
                  end if;
               when CM.Type_Spec_Map =>
                  if Spec.Key_Type /= null then
                     Collect_Type_Spec_Dependencies (Spec.Key_Type.all, Deps);
                  end if;
                  if Spec.Value_Type /= null then
                     Collect_Type_Spec_Dependencies (Spec.Value_Type.all, Deps);
                  end if;
               when CM.Type_Spec_Tuple =>
                  for Item of Spec.Tuple_Elements loop
                     Collect_Type_Spec_Dependencies (Item.all, Deps);
                  end loop;
               when CM.Type_Spec_Access_Def =>
                  if Spec.Target_Name /= null then
                     Append_Local_Type_Dependency
                       (Deps,
                        Flatten_Name (Spec.Target_Name));
                  end if;
               when others =>
                  null;
            end case;
         end Collect_Type_Spec_Dependencies;

         procedure Collect_Type_Decl_Dependencies
           (Decl : CM.Type_Decl;
            Deps : in out String_Vectors.Vector) is
         begin
            case Decl.Kind is
               when CM.Type_Decl_Sum =>
                  for Variant of Decl.Sum_Variants loop
                     for Field_Decl of Variant.Components loop
                        Collect_Type_Spec_Dependencies (Field_Decl.Field_Type, Deps);
                     end loop;
                  end loop;
               when CM.Type_Decl_Record =>
                  if Decl.Has_Discriminant then
                     Collect_Type_Spec_Dependencies (Decl.Discriminant.Disc_Type, Deps);
                  end if;
                  for Disc of Decl.Discriminants loop
                     Collect_Type_Spec_Dependencies (Disc.Disc_Type, Deps);
                  end loop;
                  for Field_Decl of Decl.Components loop
                     Collect_Type_Spec_Dependencies (Field_Decl.Field_Type, Deps);
                  end loop;
                  for Variant of Decl.Variants loop
                     for Field_Decl of Variant.Components loop
                        Collect_Type_Spec_Dependencies (Field_Decl.Field_Type, Deps);
                     end loop;
                  end loop;
               when CM.Type_Decl_Growable_Array =>
                  Collect_Type_Spec_Dependencies (Decl.Component_Type, Deps);
               when CM.Type_Decl_Constrained_Array | CM.Type_Decl_Unconstrained_Array =>
                  for Index_Item of Decl.Indexes loop
                     if Index_Item.Name_Expr /= null then
                        Append_Local_Type_Dependency
                          (Deps,
                           Flatten_Name (Index_Item.Name_Expr));
                     end if;
                  end loop;
                  Collect_Type_Spec_Dependencies (Decl.Component_Type, Deps);
               when CM.Type_Decl_Access =>
                  if Decl.Access_Type.Target_Name /= null then
                     Append_Local_Type_Dependency
                       (Deps,
                        Flatten_Name (Decl.Access_Type.Target_Name));
                  end if;
               when others =>
                  null;
            end case;
         end Collect_Type_Decl_Dependencies;
      begin
         for Item of Unit.Items loop
            if Item.Kind = CM.Item_Type_Decl
              and then Item.Type_Data.Kind /= CM.Type_Decl_Incomplete
            then
               Register_Completed_Local_Type (Item.Type_Data);
            end if;
         end loop;

         if Completed_Local_Type_Decls.Is_Empty then
            return;
         end if;

         declare
            subtype Local_Type_Index is Positive range
              1 .. Positive (Completed_Local_Type_Decls.Length);
            type Natural_Array is array (Local_Type_Index) of Natural;
            type Boolean_Array is array (Local_Type_Index) of Boolean;
            type Dependency_Array is array (Local_Type_Index) of String_Vectors.Vector;

            Adjacency      : Dependency_Array;
            Has_Self_Edge  : Boolean_Array := (others => False);
            Indexes        : Natural_Array := (others => 0);
            Lowlinks       : Natural_Array := (others => 0);
            On_Stack       : Boolean_Array := (others => False);
            Stack          : String_Vectors.Vector;
            Next_Index     : Natural := 0;

            procedure Strong_Connect (Vertex : Local_Type_Index) is
            begin
               Next_Index := Next_Index + 1;
               Indexes (Vertex) := Next_Index;
               Lowlinks (Vertex) := Next_Index;
               Stack.Append (Completed_Local_Type_Names (Vertex));
               On_Stack (Vertex) := True;

               for Dep of Adjacency (Vertex) loop
                  declare
                     Dep_Index : constant Local_Type_Index :=
                       Local_Type_Index
                         (Completed_Local_Type_Indexes.Element (Canonical_Name (Dep)));
                  begin
                     if Indexes (Dep_Index) = 0 then
                        Strong_Connect (Dep_Index);
                        if Lowlinks (Dep_Index) < Lowlinks (Vertex) then
                           Lowlinks (Vertex) := Lowlinks (Dep_Index);
                        end if;
                     elsif On_Stack (Dep_Index)
                       and then Indexes (Dep_Index) < Lowlinks (Vertex)
                     then
                        Lowlinks (Vertex) := Indexes (Dep_Index);
                     end if;
                  end;
               end loop;

               if Lowlinks (Vertex) = Indexes (Vertex) then
                  declare
                     Family : Recursive_Family_Info;
                  begin
                     loop
                        declare
                           Member_Name : constant String := Stack.Last_Element;
                           Member_Index : constant Local_Type_Index :=
                             Local_Type_Index
                               (Completed_Local_Type_Indexes.Element
                                  (Canonical_Name (Member_Name)));
                           Member_Decl : constant CM.Type_Decl :=
                             Completed_Local_Type_Decls (Member_Index);
                        begin
                           Stack.Delete_Last;
                           On_Stack (Member_Index) := False;
                           Family.Members.Append (Member_Name);
                           if Member_Decl.Kind /= CM.Type_Decl_Record then
                              Append_Unique_String
                                (Family.Non_Record_Kinds,
                                 Type_Decl_Kind_Label (Member_Decl.Kind));
                           end if;
                           exit when Member_Index = Vertex;
                        end;
                     end loop;

                     Family.Is_Recursive :=
                       Natural (Family.Members.Length) > 1
                       or else Has_Self_Edge (Vertex);
                     Family.Is_Admitted_Record_Family :=
                       Family.Is_Recursive and then Family.Non_Record_Kinds.Is_Empty;

                     if Family.Is_Recursive then
                        Families.Append (Family);
                        declare
                           Family_Index : constant Positive := Families.Last_Index;
                        begin
                           for Member_Name of Family.Members loop
                              Family_By_Name.Include
                                (Canonical_Name (Member_Name),
                                 Family_Index);
                           end loop;
                        end;
                     end if;
                  end;
               end if;
            end Strong_Connect;
         begin
            for Index in Local_Type_Index loop
               Collect_Type_Decl_Dependencies
                 (Completed_Local_Type_Decls (Index),
                  Adjacency (Index));
               for Dep of Adjacency (Index) loop
                  if Canonical_Name (Dep) =
                    Canonical_Name (Completed_Local_Type_Names (Index))
                  then
                     Has_Self_Edge (Index) := True;
                     exit;
                  end if;
               end loop;
            end loop;

            for Index in Local_Type_Index loop
               if Indexes (Index) = 0 then
                  Strong_Connect (Index);
               end if;
            end loop;
         end;
      end Analyze_Recursive_Type_Families;

      function With_Clause_Image (Clause : CM.With_Clause) return String is
         Result : FT.UString := FT.To_UString ("");
      begin
         if not Clause.Names.Is_Empty then
            for Index in Clause.Names.First_Index .. Clause.Names.Last_Index loop
               if Index > Clause.Names.First_Index then
                  Result := Result & FT.To_UString (".");
               end if;
               Result := Result & Clause.Names (Index);
            end loop;
         end if;
         return UString_Value (Result);
      end With_Clause_Image;

      function Imported_Interface_Span (Package_Name : String) return FT.Source_Span is
      begin
         for Clause of Unit.Withs loop
            if With_Clause_Image (Clause) = Package_Name then
               return Clause.Span;
            end if;
         end loop;
         return FT.Null_Span;
      end Imported_Interface_Span;

      procedure Add_Imported_Interface (Item : SI.Loaded_Interface) is
         Package_Name : constant String := UString_Value (Item.Package_Name);

         procedure Validate_Imported_Sum_Metadata (Info : GM.Type_Descriptor) is
         begin
            if Is_Lowered_Sum_Record (Info) and then Info.Sum_Variants.Is_Empty then
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => UString_Value (Unit.Path),
                     Span    => Imported_Interface_Span (Package_Name),
                     Message =>
                       "imported sum type `"
                       & UString_Value (Info.Name)
                       & "` is missing sum_variants metadata in safei-v5"));
            end if;
         end Validate_Imported_Sum_Metadata;

         procedure Register_Imported_Sum_Constructors (Info : GM.Type_Descriptor) is
         begin
            if Info.Sum_Variants.Is_Empty then
               return;
            end if;

            for Variant of Info.Sum_Variants loop
               declare
                  Qualified_Name : constant String :=
                    Qualify_Name (Package_Name, UString_Value (Variant.Name));
                  Constructor : Sum_Constructor_Info :=
                    Constructor_From_Sum_Variant (Info, Variant);
               begin
                  Constructor.Name := FT.To_UString (Qualified_Name);
                  Constructor.Span := Imported_Interface_Span (Package_Name);
                  if not Current_Sum_Constructors.Contains (Canonical_Name (Qualified_Name)) then
                     Current_Sum_Constructors.Include
                       (Canonical_Name (Qualified_Name),
                        Constructor);
                  end if;
               end;
            end loop;
         end Register_Imported_Sum_Constructors;

         procedure Register_One_Imported_Type (Type_Item : GM.Type_Descriptor) is
            Info : constant GM.Type_Descriptor :=
              Qualify_Type_Info (Type_Item, Package_Name);
            Tail : constant String := Synthetic_Type_Tail_Name (UString_Value (Info.Name));
         begin
            if Info.Generic_Formals.Is_Empty then
               Put_Type (Type_Env, UString_Value (Info.Name), Info);
            else
               Current_Generic_Type_Templates.Include
                 (Canonical_Name (UString_Value (Info.Name)),
                  (Has_Decl => False,
                   Decl     => (others => <>),
                   Info     => Info));
            end if;
            if Tail'Length > 2
              and then Tail (Tail'First .. Tail'First + 1) = "__"
            then
               Current_Imported_Synthetic_Types.Include
                 (Canonical_Name (UString_Value (Info.Name)),
                  Info);
            end if;
            Validate_Imported_Sum_Metadata (Info);
            Result.Imported_Types.Append (Info);
         end Register_One_Imported_Type;
      begin
         if Item.Target_Bits /= Normalized_Target_Bits then
            Raise_Diag
              (CM.Source_Frontend_Error
                 (Path    => UString_Value (Unit.Path),
                  Span    => Imported_Interface_Span (Package_Name),
                  Message =>
                    "imported interface `"
                    & Package_Name
                    & "` target_bits "
                    & Ada.Strings.Fixed.Trim (Positive'Image (Item.Target_Bits), Ada.Strings.Both)
                    & " does not match current target_bits "
                    & Ada.Strings.Fixed.Trim (Positive'Image (Normalized_Target_Bits), Ada.Strings.Both)));
         end if;
         for Type_Item of Item.Types loop
            Register_One_Imported_Type (Type_Item);
         end loop;

         for Type_Item of Item.Subtypes loop
            Register_One_Imported_Type (Type_Item);
         end loop;

         for Type_Item of Item.Types loop
            Register_Imported_Sum_Constructors
              (Qualify_Type_Info (Type_Item, Package_Name));
         end loop;

         for Type_Item of Item.Subtypes loop
            Register_Imported_Sum_Constructors
              (Qualify_Type_Info (Type_Item, Package_Name));
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
                 Canonicalize_Imported_Synthetic_Type
                   (Qualify_Type_Info (Object_Item.Type_Info, Package_Name),
                    Type_Env);
               Qualified_Static : constant CM.Static_Value :=
                 Qualify_Static_Value (Object_Item.Static_Info, Package_Name);
            begin
               Put_Type (Imported_Objects, Qualified_Name, Qualified_Type);
               Result.Imported_Objects.Append
                 ((Name                 => FT.To_UString (Qualified_Name),
                   Type_Info            => Qualified_Type,
                   Is_Shared            => Object_Item.Is_Shared,
                   Has_Required_Ceiling => Object_Item.Has_Required_Ceiling,
                   Required_Ceiling     => Object_Item.Required_Ceiling,
                   Is_Constant          => Object_Item.Is_Constant,
                   Static_Info          => Qualified_Static,
                   Span                 => Object_Item.Span));
               if Object_Item.Is_Shared then
                  Current_Imported_Shared_Object_Types.Include
                    (Canonical_Name (Qualified_Name),
                     Qualified_Type);
               end if;
               if Object_Item.Is_Constant
                 and then Object_Item.Static_Info.Kind /= CM.Static_Value_None
               then
                  Put_Static_Value
                    (Const_Env,
                     Qualified_Name,
                     Qualified_Static);
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
                  Info.Return_Type :=
                    Canonicalize_Imported_Synthetic_Type
                      (Qualify_Type_Info (Subp_Item.Return_Type, Package_Name),
                       Type_Env);
               end if;
               for Param of Subp_Item.Params loop
                  declare
                     Symbol : CM.Symbol := Param;
                     Local  : GM.Local_Entry;
                  begin
                     Symbol.Type_Info :=
                       Canonicalize_Imported_Synthetic_Type
                         (Qualify_Type_Info (Param.Type_Info, Package_Name),
                          Type_Env);
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
               External.Generic_Formals := Subp_Item.Generic_Formals;
               External.Has_Template_Source := Subp_Item.Has_Template_Source;
               External.Template_Source := Subp_Item.Template_Source;
               if Subp_Item.Has_Return_Type then
                  External.Return_Type :=
                    Canonicalize_Imported_Synthetic_Type
                      (Qualify_Type_Info (Subp_Item.Return_Type, Package_Name),
                       Type_Env);
               end if;
               External.Effect_Summary := Subp_Item.Effect_Summary;
               External.Channel_Summary := Subp_Item.Channel_Summary;
               if Subp_Item.Generic_Formals.Is_Empty then
                  Put_Function (Functions, UString_Value (Info.Name), Info);
                  Put_Function (Current_Generic_Function_Env, UString_Value (Info.Name), Info);
               else
                  declare
                     Template_Decl : CM.Subprogram_Body;
                  begin
                     if not Subp_Item.Has_Template_Source then
                        Raise_Diag
                          (CM.Source_Frontend_Error
                             (Path    => UString_Value (Unit.Path),
                              Span    => Imported_Interface_Span (Package_Name),
                              Message =>
                                "imported generic subprogram `"
                                & UString_Value (Info.Name)
                                & "` is missing template source in safei-v5"));
                     end if;
                     Template_Decl :=
                       Parse_Imported_Generic_Subprogram
                         (Package_Name,
                          UString_Value (Info.Name),
                          UString_Value (Subp_Item.Template_Source));
                     Current_Generic_Function_Templates.Include
                       (Canonical_Name (UString_Value (Info.Name)),
                        (Decl              => Template_Decl,
                         Info              => Info,
                         Origin_Package    => FT.To_UString (Package_Name),
                         Actual_Type_Names => <>));
                  end;
               end if;
               Result.Imported_Subprograms.Append (External);
            end;
         end loop;

         for Type_Item of Item.Types loop
            declare
               Info : constant GM.Type_Descriptor :=
                 Qualify_Type_Info (Type_Item, Package_Name);
            begin
               Register_Enum_Literals
                 (Info,
                  Imported_Objects,
                  Qualifier => Package_Name,
                  Path      => UString_Value (Unit.Path));
            end;
         end loop;

         for Type_Item of Item.Subtypes loop
            declare
               Info : constant GM.Type_Descriptor :=
                 Qualify_Type_Info (Type_Item, Package_Name);
            begin
               Register_Enum_Literals
                 (Info,
                  Imported_Objects,
                  Qualifier => Package_Name,
                  Path      => UString_Value (Unit.Path));
            end;
         end loop;
      end Add_Imported_Interface;
   begin
      Current_Target_Bits := Normalized_Target_Bits;
      Current_Public_Channel_Names.Clear;
      Current_Shared_Object_Types.Clear;
      Current_Public_Shared_Object_Types.Clear;
      Current_Imported_Shared_Object_Types.Clear;
      Current_Imported_Synthetic_Types.Clear;
      Current_Select_In_Subprogram_Body := False;
      Current_In_Task_Body := False;
      Current_Interface_Templates.Clear;
      Current_Pending_Interface_Specializations.Clear;
      Current_Interface_Specialization_Order.Clear;
      Current_Interface_Specialization_By_Key.Clear;
      Current_Generic_Type_Templates.Clear;
      Current_Generic_Type_Instantiation_Order.Clear;
      Current_Generic_Type_Instantiation_By_Key.Clear;
      Current_Generic_Type_Instantiations.Clear;
      Current_Generic_Type_Instantiation_Stack.Clear;
      Current_Generic_Function_Templates.Clear;
      Current_Pending_Generic_Specializations.Clear;
      Current_Generic_Specialization_Order.Clear;
      Current_Generic_Specialization_By_Key.Clear;
      Current_Synthetic_Functions.Clear;
      Current_Generic_Function_Env.Clear;
      Current_Sum_Constructors.Clear;
      Current_Sum_Tag_Types.Clear;
      Current_Sum_Type_Tag_Names.Clear;
      Synthetic_Helper_Types.Clear;
      Synthetic_Helper_Order.Clear;
      Synthetic_Optional_Types.Clear;
      Synthetic_Optional_Order.Clear;
      Add_Builtins (Type_Env);
      Result.Target_Bits := Normalized_Target_Bits;
      Add_Builtin_Functions (Functions);
      Add_Builtin_Functions (Current_Generic_Function_Env);
      Result.Path := Unit.Path;
      Result.Kind := Unit.Kind;
      Result.Package_Name := Unit.Package_Name;
      Result.Has_End_Name := Unit.Has_End_Name;
      Result.End_Name := Unit.End_Name;

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
         if Item.Kind = CM.Item_Type_Decl then
            if Item.Type_Data.Generic_Formals.Is_Empty then
               declare
                  Placeholder : GM.Type_Descriptor;
               begin
                  Placeholder.Name := Item.Type_Data.Name;
                  Placeholder.Kind := FT.To_UString ("incomplete");
                  Put_Type (Type_Env, UString_Value (Placeholder.Name), Placeholder);
               end;
            end if;
         end if;
      end loop;

      Analyze_Recursive_Type_Families;

      for Item of Unit.Items loop
         if Item.Kind = CM.Item_Channel and then Item.Chan_Data.Is_Public then
            Append_Unique_String
              (Current_Public_Channel_Names,
               UString_Value (Item.Chan_Data.Name));
         end if;
      end loop;

      for Item of Unit.Items loop
         if Unit.Kind = CM.Unit_Entry and then Item_Is_Public (Item) then
            Raise_Diag
              (CM.Source_Frontend_Error
                 (Path    => UString_Value (Unit.Path),
                  Span    => (case Item.Kind is
                                when CM.Item_Type_Decl => Item.Type_Data.Span,
                                when CM.Item_Subtype_Decl => Item.Sub_Data.Span,
                                when CM.Item_Object_Decl => Item.Obj_Data.Span,
                                when CM.Item_Subprogram => Item.Subp_Data.Span,
                                when CM.Item_Task => Item.Task_Data.Span,
                                when CM.Item_Channel => Item.Chan_Data.Span,
                                when others => FT.Null_Span),
                  Message => "packageless entry files must not contain public declarations"));
         end if;

         case Item.Kind is
            when CM.Item_Type_Decl =>
               if Item.Type_Data.Kind = CM.Type_Decl_Incomplete
                 and then Completed_Local_Type_Indexes.Contains
                   (Canonical_Name (UString_Value (Item.Type_Data.Name)))
               then
                  null;
               elsif not Item.Type_Data.Generic_Formals.Is_Empty then
                  declare
                     Template_Type_Env : Type_Maps.Map := Type_Env;
                     Info              : GM.Type_Descriptor;
                  begin
                     if Item.Type_Data.Kind /= CM.Type_Decl_Record then
                        Raise_Diag
                          (CM.Unsupported_Source_Construct
                             (Path    => UString_Value (Unit.Path),
                              Span    => Item.Type_Data.Span,
                              Message =>
                                "PR11.11c generic types are currently limited to record and discriminated-record declarations"));
                     end if;
                     Add_Generic_Formals_To_Env
                       (Template_Type_Env,
                        Item.Type_Data.Generic_Formals);
                     Info :=
                       Resolve_Type_Declaration
                         (Item.Type_Data,
                          Template_Type_Env,
                          Const_Env,
                          UString_Value (Unit.Path),
                          Family_By_Name,
                          Families);
                     if not Item.Type_Data.Generic_Formals.Is_Empty then
                        for Formal of Item.Type_Data.Generic_Formals loop
                           Info.Generic_Formals.Append
                             (Generic_Formal_Descriptor (Formal));
                        end loop;
                     end if;
                     Current_Generic_Type_Templates.Include
                       (Canonical_Name (UString_Value (Item.Type_Data.Name)),
                        (Has_Decl => True,
                         Decl     => Item.Type_Data,
                         Info     => Info));
                     Result.Types.Append (Info);
                  end;
               else
                  declare
                     Name : constant String := UString_Value (Item.Type_Data.Name);
                     pragma Unreferenced (Name);
                  begin
                     if Item.Type_Data.Kind = CM.Type_Decl_Sum then
                        for Variant of Item.Type_Data.Sum_Variants loop
                           Reject_Sum_Constructor_Collision
                             (UString_Value (Variant.Name),
                              Package_Vars,
                              Variant.Span,
                              UString_Value (Unit.Path));
                        end loop;
                     end if;
                  end;
                  declare
                     Name : constant String := UString_Value (Item.Type_Data.Name);
                     Info : constant GM.Type_Descriptor :=
                       Resolve_Type_Declaration
                         (Item.Type_Data,
                          Type_Env,
                          Const_Env,
                          UString_Value (Unit.Path),
                          Family_By_Name,
                          Families);
                  begin
                     Reject_Package_Level_Enum_Collision
                       (Name,
                        Item.Type_Data.Span,
                        UString_Value (Unit.Path));
                     Reject_Package_Level_Sum_Constructor_Collision
                       (Name,
                        Item.Type_Data.Span,
                        UString_Value (Unit.Path));
                     if not Is_Builtin_Name (UString_Value (Info.Name)) then
                        declare
                           Hidden_Target : constant String :=
                             (if FT.Lowercase (UString_Value (Info.Kind)) = "access" and then Info.Has_Target
                              then UString_Value (Info.Target)
                              else "");
                           Sum_Tag_Name : constant String :=
                             (if Item.Type_Data.Kind = CM.Type_Decl_Sum
                              then Sum_Tag_Type_Name (UString_Value (Item.Type_Data.Name))
                              else "");
                        begin
                           if Sum_Tag_Name'Length > 0
                             and then Current_Sum_Tag_Types.Contains (Canonical_Name (Sum_Tag_Name))
                           then
                              Result.Types.Append
                                (Current_Sum_Tag_Types.Element (Canonical_Name (Sum_Tag_Name)));
                           end if;
                           Result.Types.Append (Info);
                           if Hidden_Target'Length > 0
                             and then Hidden_Target'Length >= 16
                             and then Hidden_Target (Hidden_Target'First .. Hidden_Target'First + 15) = "safe_ref_target_"
                             and then Has_Type (Type_Env, Hidden_Target)
                           then
                              Append_Unique_String
                                (Pending_Hidden_Targets,
                                 Hidden_Target);
                           end if;
                        end;
                     end if;
                     Put_Type (Package_Vars, UString_Value (Info.Name), Info);
                     Register_Enum_Literals
                       (Info,
                        Package_Vars,
                        Path => UString_Value (Unit.Path),
                        Span => Item.Type_Data.Span);
                  end;
               end if;
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
                  if Is_Interface_Type (Base, Type_Env) then
                     Raise_Diag
                       (CM.Source_Frontend_Error
                          (Path    => UString_Value (Unit.Path),
                           Span    => Item.Sub_Data.Span,
                           Message => "interface types are only admitted in parameter positions in PR11.11b"));
                  end if;
                  Reject_Package_Level_Enum_Collision
                    (UString_Value (Item.Sub_Data.Name),
                     Item.Sub_Data.Span,
                     UString_Value (Unit.Path));
                  Reject_Package_Level_Sum_Constructor_Collision
                    (UString_Value (Item.Sub_Data.Name),
                     Item.Sub_Data.Span,
                     UString_Value (Unit.Path));
                  Info.Name := Item.Sub_Data.Name;
                  Info.Kind := FT.To_UString ("subtype");
                  if Base.Has_Low
                    and then not
                      (FT.Lowercase (UString_Value (Base.Kind)) = "integer"
                       and then UString_Value (Base.Name) = "integer")
                  then
                     Info.Has_Low := True;
                     Info.Low := Base.Low;
                  end if;
                  if Base.Has_High
                    and then not
                      (FT.Lowercase (UString_Value (Base.Kind)) = "integer"
                       and then UString_Value (Base.Name) = "integer")
                  then
                     Info.Has_High := True;
                     Info.High := Base.High;
                  end if;
                  if Base.Has_Bit_Width then
                     Info.Has_Bit_Width := True;
                     Info.Bit_Width := Base.Bit_Width;
                  end if;
                  Info.Discriminant_Constraints := Base.Discriminant_Constraints;
                  Info.Has_Base := True;
                  Info.Base := (if Base.Has_Base then Base.Base else Base.Name);
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
                  Reject_Package_Level_Enum_Collision
                    (UString_Value (Item.Chan_Data.Name),
                     Item.Chan_Data.Span,
                     UString_Value (Unit.Path));
                  Reject_Package_Level_Sum_Constructor_Collision
                    (UString_Value (Item.Chan_Data.Name),
                     Item.Chan_Data.Span,
                     UString_Value (Unit.Path));
                  Result.Channels.Append (Channel_Decl);
                  if Channel_Decl.Is_Public then
                     Append_Unique_String
                       (Current_Public_Channel_Names,
                        UString_Value (Channel_Decl.Name));
                  end if;
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
                       Exact_Length_Maps.Empty_Map,
                       UString_Value (Unit.Path));
                  Local_Decl   : CM.Resolved_Object_Decl;
                  Static_Value : CM.Static_Value;
               begin
                  for Name of Item.Obj_Data.Names loop
                     Reject_Package_Level_Enum_Collision
                       (UString_Value (Name),
                        Item.Obj_Data.Span,
                        UString_Value (Unit.Path));
                     Reject_Package_Level_Sum_Constructor_Collision
                       (UString_Value (Name),
                        Item.Obj_Data.Span,
                        UString_Value (Unit.Path));
                  end loop;
                  Local_Decl.Names := Normalized.Names;
                  Local_Decl.Type_Info := Normalized.Type_Info;
                  Local_Decl.Is_Public := Item.Obj_Data.Is_Public;
                  Local_Decl.Is_Shared := Normalized.Is_Shared;
                  Local_Decl.Is_Constant := Normalized.Is_Constant;
                  Local_Decl.Has_Initializer := Normalized.Has_Initializer;
                  Local_Decl.Has_Implicit_Default_Init := Normalized.Has_Implicit_Default_Init;
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
                     if Local_Decl.Is_Shared then
                        Current_Shared_Object_Types.Include
                          (Canonical_Name (UString_Value (Name)),
                           Normalized.Type_Info);
                        if Local_Decl.Is_Public then
                           Current_Public_Shared_Object_Types.Include
                             (Canonical_Name (UString_Value (Name)),
                              Normalized.Type_Info);
                        end if;
                     end if;
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
                          Const_Env,
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
               if not Item.Subp_Data.Spec.Generic_Formals.Is_Empty then
                  declare
                     Template_Type_Env : Type_Maps.Map := Type_Env;
                     Info              : Function_Info;
                  begin
                     Add_Generic_Formals_To_Env
                       (Template_Type_Env,
                        Item.Subp_Data.Spec.Generic_Formals);
                     Info :=
                       Register_Function
                         (Item.Subp_Data,
                          Template_Type_Env,
                          Const_Env,
                          UString_Value (Unit.Path));
                     Validate_Interface_Method_Syntax
                       (Item.Subp_Data,
                        Info,
                        Template_Type_Env,
                        UString_Value (Unit.Path));
                     Current_Generic_Function_Templates.Include
                       (Canonical_Name (UString_Value (Item.Subp_Data.Spec.Name)),
                        (Decl              => Item.Subp_Data,
                         Info              => Info,
                         Origin_Package    => FT.To_UString (""),
                         Actual_Type_Names => <>));
                  end;
               else
                  declare
                     Info : constant Function_Info :=
                       Register_Function
                         (Item.Subp_Data,
                          Type_Env,
                          Const_Env,
                          UString_Value (Unit.Path));
                  begin
                     if Has_Interface_Params (Info, Type_Env) then
                        if Item.Subp_Data.Is_Public then
                           Raise_Diag
                             (CM.Source_Frontend_Error
                                (Path    => UString_Value (Unit.Path),
                                 Span    => Item.Subp_Data.Span,
                                 Message =>
                                   "PR11.11b does not yet admit public subprogram bodies with interface-typed parameters"));
                        end if;
                        Validate_Interface_Method_Syntax
                          (Item.Subp_Data,
                           Info,
                           Type_Env,
                           UString_Value (Unit.Path));
                        Current_Interface_Templates.Include
                          (Canonical_Name (UString_Value (Info.Name)),
                           (Decl => Item.Subp_Data, Info => Info));
                     end if;
                     Reject_Package_Level_Enum_Collision
                       (UString_Value (Item.Subp_Data.Spec.Name),
                        Item.Subp_Data.Span,
                        UString_Value (Unit.Path));
                     Reject_Package_Level_Sum_Constructor_Collision
                       (UString_Value (Item.Subp_Data.Spec.Name),
                        Item.Subp_Data.Span,
                        UString_Value (Unit.Path));
                     Put_Function (Functions, UString_Value (Info.Name), Info);
                     Put_Function (Current_Generic_Function_Env, UString_Value (Info.Name), Info);
                  end;
               end if;
            when others =>
               null;
         end case;
      end loop;

      Reject_Shared_Wrapper_Name_Collisions;

      declare
         Visible : Type_Maps.Map := Package_Vars;
         Visible_Constants : Type_Maps.Map;
         Visible_Static_Constants : Static_Value_Maps.Map := Const_Env;
      begin
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

         Synthetic_Name_Counter := 0;
         Result.Statements :=
           Normalize_Statement_List
             (Unit.Statements,
              Visible,
              Functions,
              Type_Env,
              Channel_Env,
              Imported_Objects,
              Visible_Constants,
              Visible_Static_Constants,
              Exact_Length_Maps.Empty_Map,
              UString_Value (Unit.Path));
         Validate_Unit_Statements (Result.Statements, UString_Value (Unit.Path));
      end;

      for Item of Unit.Items loop
         if Item.Kind = CM.Item_Subprogram then
            if not Item.Subp_Data.Spec.Generic_Formals.Is_Empty then
               declare
                  Template_Type_Env : Type_Maps.Map := Type_Env;
                  Info              : Function_Info;
                  Subprogram        : CM.Resolved_Subprogram;
               begin
                  Add_Generic_Formals_To_Env
                    (Template_Type_Env,
                     Item.Subp_Data.Spec.Generic_Formals);
                  Info :=
                    Register_Function
                      (Item.Subp_Data,
                       Template_Type_Env,
                       Const_Env,
                       UString_Value (Unit.Path));
                  Subprogram.Name := Info.Name;
                  Subprogram.Kind := Info.Kind;
                  Subprogram.Is_Generic_Template := True;
                  Subprogram.Params := Info.Params;
                  Subprogram.Has_Return_Type := Info.Has_Return_Type;
                  Subprogram.Return_Type := Info.Return_Type;
                  Subprogram.Return_Is_Access_Def := Info.Return_Is_Access_Def;
                  Subprogram.Span := Info.Span;
                  Subprogram.Generic_Formals := Item.Subp_Data.Spec.Generic_Formals;
                  Result.Subprograms.Append (Subprogram);
               end;
               goto Continue_Outer_Second_Pass_Item;
            end if;
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

               if Has_Interface_Params (Info, Type_Env) then
                  Subprogram.Is_Interface_Template := True;
                  Result.Subprograms.Append (Subprogram);
                  goto Continue_Second_Pass_Item;
               end if;

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
                          Exact_Length_Maps.Empty_Map,
                          UString_Value (Unit.Path));
                  begin
                     Local_Decl := (others => <>);
                     Local_Decl.Names := Normalized.Names;
                     Local_Decl.Type_Info := Normalized.Type_Info;
                     Local_Decl.Is_Constant := Normalized.Is_Constant;
                     Local_Decl.Has_Initializer := Normalized.Has_Initializer;
                     Local_Decl.Has_Implicit_Default_Init := Normalized.Has_Implicit_Default_Init;
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

               declare
                  Previous_Select_Context : constant Boolean :=
                    Current_Select_In_Subprogram_Body;
               begin
                  Current_Select_In_Subprogram_Body := True;
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
                       Exact_Length_Maps.Empty_Map,
                       UString_Value (Unit.Path),
                       Has_Enclosing_Return => Info.Has_Return_Type,
                       Enclosing_Return_Type => Info.Return_Type);
                  Current_Select_In_Subprogram_Body := Previous_Select_Context;
               exception
                  when others =>
                     Current_Select_In_Subprogram_Body := Previous_Select_Context;
                     raise;
               end;

               Result.Subprograms.Append (Subprogram);
               <<Continue_Second_Pass_Item>>
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
               Task_Item.Has_Send_Contract := Item.Task_Data.Has_Send_Contract;
               if Item.Task_Data.Has_Send_Contract then
                  for Expr of Item.Task_Data.Send_Contracts loop
                     Append_Task_Channel_Contract
                       (Task_Item.Send_Contracts,
                        Expr,
                        Channel_Env,
                        UString_Value (Unit.Path),
                        "sends");
                  end loop;
               end if;
               Task_Item.Has_Receive_Contract := Item.Task_Data.Has_Receive_Contract;
               if Item.Task_Data.Has_Receive_Contract then
                  for Expr of Item.Task_Data.Receive_Contracts loop
                     Append_Task_Channel_Contract
                       (Task_Item.Receive_Contracts,
                        Expr,
                        Channel_Env,
                        UString_Value (Unit.Path),
                        "receives");
                  end loop;
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
                          Exact_Length_Maps.Empty_Map,
                          UString_Value (Unit.Path));
                  begin
                     Local_Decl := (others => <>);
                     Local_Decl.Names := Normalized.Names;
                     Local_Decl.Type_Info := Normalized.Type_Info;
                     Local_Decl.Is_Constant := Normalized.Is_Constant;
                     Local_Decl.Has_Initializer := Normalized.Has_Initializer;
                     Local_Decl.Has_Implicit_Default_Init := Normalized.Has_Implicit_Default_Init;
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

               declare
                  Previous_Task_Context : constant Boolean := Current_In_Task_Body;
               begin
                  Current_In_Task_Body := True;
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
                       Exact_Length_Maps.Empty_Map,
                       UString_Value (Unit.Path));
                  Current_In_Task_Body := Previous_Task_Context;
               exception
                  when others =>
                     Current_In_Task_Body := Previous_Task_Context;
                     raise;
               end;

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
         <<Continue_Outer_Second_Pass_Item>>
      end loop;

      if not Current_Interface_Specialization_Order.Is_Empty then
         declare
            Specialization_Index : Positive :=
              Current_Interface_Specialization_Order.First_Index;
         begin
            while Specialization_Index in
              Current_Interface_Specialization_Order.First_Index
              .. Current_Interface_Specialization_Order.Last_Index
            loop
               declare
                  Specialized_Name : constant String :=
                    Current_Interface_Specialization_Order (Specialization_Index);
               begin
                  declare
                     Template : constant Interface_Template_Info :=
                       Current_Pending_Interface_Specializations.Element
                         (Canonical_Name (Specialized_Name));
                     Info         : constant Function_Info := Template.Info;
                     Subprogram   : CM.Resolved_Subprogram;
                     Visible      : Type_Maps.Map := Package_Vars;
                     Visible_Constants : Type_Maps.Map;
                     Visible_Static_Constants : Static_Value_Maps.Map := Const_Env;
                     Local_Decl   : CM.Resolved_Object_Decl;
                  begin
                     Subprogram.Name := Info.Name;
                     Subprogram.Kind := Info.Kind;
                     Subprogram.Is_Synthetic := True;
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

                     for Decl of Template.Decl.Declarations loop
                        declare
                           Normalized : constant CM.Object_Decl :=
                             Normalize_Object_Decl
                               (Decl,
                                Visible,
                                Functions,
                                Type_Env,
                                Visible_Static_Constants,
                                Exact_Length_Maps.Empty_Map,
                                UString_Value (Unit.Path));
                        begin
                           Local_Decl := (others => <>);
                           Local_Decl.Names := Normalized.Names;
                           Local_Decl.Type_Info := Normalized.Type_Info;
                           Local_Decl.Is_Constant := Normalized.Is_Constant;
                           Local_Decl.Has_Initializer := Normalized.Has_Initializer;
                           Local_Decl.Has_Implicit_Default_Init := Normalized.Has_Implicit_Default_Init;
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

                     declare
                        Previous_Select_Context : constant Boolean :=
                          Current_Select_In_Subprogram_Body;
                     begin
                        Current_Select_In_Subprogram_Body := True;
                        Subprogram.Statements :=
                          Normalize_Statement_List
                            (Template.Decl.Statements,
                             Visible,
                             Functions,
                             Type_Env,
                             Channel_Env,
                             Imported_Objects,
                             Visible_Constants,
                             Visible_Static_Constants,
                             Exact_Length_Maps.Empty_Map,
                             UString_Value (Unit.Path),
                             Has_Enclosing_Return => Info.Has_Return_Type,
                             Enclosing_Return_Type => Info.Return_Type);
                        Current_Select_In_Subprogram_Body := Previous_Select_Context;
                     exception
                        when others =>
                           Current_Select_In_Subprogram_Body := Previous_Select_Context;
                           raise;
                     end;

                     Result.Subprograms.Append (Subprogram);
                  end;
                  Specialization_Index := Specialization_Index + 1;
               end;
            end loop;
         end;
      end if;

      if not Current_Generic_Specialization_Order.Is_Empty then
         declare
            Specialization_Index : Positive :=
              Current_Generic_Specialization_Order.First_Index;
         begin
            while Specialization_Index in
              Current_Generic_Specialization_Order.First_Index
              .. Current_Generic_Specialization_Order.Last_Index
            loop
               declare
                  Specialized_Name : constant String :=
                    Current_Generic_Specialization_Order (Specialization_Index);
                  Template : constant Generic_Function_Template_Info :=
                    Current_Pending_Generic_Specializations.Element
                      (Canonical_Name (Specialized_Name));
                  Info         : constant Function_Info := Template.Info;
                  Subprogram   : CM.Resolved_Subprogram;
                  Visible      : Type_Maps.Map := Package_Vars;
                  Local_Functions : Function_Maps.Map := Functions;
                  Visible_Constants : Type_Maps.Map;
                  Visible_Static_Constants : Static_Value_Maps.Map := Const_Env;
                  Local_Type_Env : Type_Maps.Map := Type_Env;
                  Local_Imported_Objects : Type_Maps.Map := Imported_Objects;
                  Local_Decl   : CM.Resolved_Object_Decl;
               begin
                  if not Info.Generic_Formals.Is_Empty then
                     for Index in Info.Generic_Formals.First_Index .. Info.Generic_Formals.Last_Index loop
                        Put_Type
                          (Local_Type_Env,
                           UString_Value (Info.Generic_Formals (Index).Name),
                           Resolve_Type
                             (UString_Value (Template.Actual_Type_Names (Index)),
                              Type_Env,
                              UString_Value (Unit.Path),
                             Template.Decl.Spec.Span));
                     end loop;
                  end if;

                  Add_Imported_Package_Local_Aliases
                    (UString_Value (Template.Origin_Package),
                     Result.Imported_Types,
                     Result.Imported_Subprograms,
                     Imported_Objects,
                     Const_Env,
                     Current_Generic_Type_Templates,
                     Current_Generic_Function_Templates,
                     Local_Type_Env,
                     Local_Functions,
                     Local_Imported_Objects,
                     Visible_Static_Constants);

                  Subprogram.Name := Info.Name;
                  Subprogram.Kind := Info.Kind;
                  Subprogram.Is_Synthetic := True;
                  Subprogram.Force_Body_Emission := True;
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

                  for Decl of Template.Decl.Declarations loop
                     declare
                        Normalized : constant CM.Object_Decl :=
                          Normalize_Object_Decl
                            (Decl,
                             Visible,
                             Local_Functions,
                             Local_Type_Env,
                             Visible_Static_Constants,
                             Exact_Length_Maps.Empty_Map,
                             UString_Value (Unit.Path));
                     begin
                        Local_Decl := (others => <>);
                        Local_Decl.Names := Normalized.Names;
                        Local_Decl.Type_Info := Normalized.Type_Info;
                        Local_Decl.Is_Constant := Normalized.Is_Constant;
                        Local_Decl.Has_Initializer := Normalized.Has_Initializer;
                        Local_Decl.Has_Implicit_Default_Init := Normalized.Has_Implicit_Default_Init;
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

                  declare
                     Previous_Select_Context : constant Boolean :=
                       Current_Select_In_Subprogram_Body;
                  begin
                     Current_Select_In_Subprogram_Body := True;
                     Subprogram.Statements :=
                       Normalize_Statement_List
                         (Template.Decl.Statements,
                          Visible,
                          Local_Functions,
                          Local_Type_Env,
                          Channel_Env,
                          Local_Imported_Objects,
                          Visible_Constants,
                          Visible_Static_Constants,
                          Exact_Length_Maps.Empty_Map,
                          UString_Value (Unit.Path),
                          Has_Enclosing_Return => Info.Has_Return_Type,
                          Enclosing_Return_Type => Info.Return_Type);
                     Current_Select_In_Subprogram_Body := Previous_Select_Context;
                  exception
                     when others =>
                        Current_Select_In_Subprogram_Body := Previous_Select_Context;
                        raise;
                  end;

                  Result.Subprograms.Append (Subprogram);
                  Specialization_Index := Specialization_Index + 1;
               end;
            end loop;
         end;
      end if;

      for Concrete_Name of Current_Generic_Type_Instantiation_Order loop
         Result.Types.Append (Get_Type (Current_Generic_Type_Instantiations, Concrete_Name));
      end loop;

      for Hidden_Target of Pending_Hidden_Targets loop
         Result.Types.Append (Get_Type (Type_Env, Hidden_Target));
      end loop;

      for Helper_Name of Synthetic_Helper_Order loop
         Result.Types.Append (Get_Type (Synthetic_Helper_Types, Helper_Name));
      end loop;

      for Optional_Name of Synthetic_Optional_Order loop
         Result.Types.Append (Get_Type (Synthetic_Optional_Types, Optional_Name));
      end loop;

      return (Success => True, Unit => Result);
   exception
      when Resolve_Failure =>
         return (Success => False, Diagnostic => Raised_Diag);
   end Resolve;
end Safe_Frontend.Check_Resolve;
