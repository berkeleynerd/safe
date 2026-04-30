with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Containers.Indefinite_Hashed_Sets;
with Ada.Containers.Indefinite_Vectors;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Hash;
with Ada.Strings.Unbounded;
with Safe_Frontend.Builtin_Types;
with Safe_Frontend.Name_Utils;
with Safe_Frontend.Mir_Bronze;
with Safe_Frontend.Mir_Json;
with Safe_Frontend.Mir_Validate;

package body Safe_Frontend.Mir_Analyze is
   package MB renames Safe_Frontend.Mir_Bronze;
   package BT renames Safe_Frontend.Builtin_Types;
   package CM renames Safe_Frontend.Check_Model;
   package FNU renames Safe_Frontend.Name_Utils;
   package GM renames Safe_Frontend.Mir_Model;
   package US renames Ada.Strings.Unbounded;

   subtype Wide_Integer is Long_Long_Long_Integer;
   subtype Real_Value is Long_Long_Float;

   package String_Sets is new Ada.Containers.Indefinite_Hashed_Sets
     (Element_Type        => String,
      Hash                => Ada.Strings.Hash,
      Equivalent_Elements => "=");

   package String_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => String);

   package Interval_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Wide_Integer,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   type Interval is record
      Low           : Wide_Integer := 0;
      High          : Wide_Integer := 0;
      Excludes_Zero : Boolean := False;
   end record;

   package Range_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Interval,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   type Float_Interval is record
      Low             : Real_Value := 0.0;
      High            : Real_Value := 0.0;
      Initialized     : Boolean := True;
      May_Be_NaN      : Boolean := False;
      May_Be_Infinite : Boolean := False;
      Excludes_Zero   : Boolean := False;
   end record;

   package Float_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Float_Interval,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   type Discriminant_Fact is record
      Known       : Boolean := False;
      Value       : GM.Scalar_Value;
      Invalidated : Boolean := False;
   end record;

   package Discriminant_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Discriminant_Fact,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   type Access_State_Kind is
     (Access_Null,
      Access_NonNull,
      Access_MaybeNull,
      Access_Moved,
      Access_Dangling);

   type Access_Role_Kind is
     (Role_None,
      Role_Owner,
      Role_General_Access,
      Role_Named_Constant,
      Role_Borrow,
      Role_Observe);

   type Access_Fact is record
      State        : Access_State_Kind := Access_MaybeNull;
      Has_Lender   : Boolean := False;
      Lender       : FT.UString := FT.To_UString ("");
      Alias_Kind   : Access_Role_Kind := Role_None;
      Initialized  : Boolean := False;
   end record;

   package Access_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Access_Fact,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   package Natural_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Natural,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   type Pending_Move is record
      Source_Name : FT.UString := FT.To_UString ("");
      Saved_Fact  : Access_Fact;
   end record;

   package Pending_Move_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Pending_Move,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   type Alias_Path is record
      Root       : FT.UString := FT.To_UString ("");
      Components : String_Vectors.Vector;
      Supported  : Boolean := False;
   end record;

   package Type_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => GM.Type_Descriptor,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=",
      "="             => GM."=");

   package Local_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => GM.Local_Entry,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=",
      "="             => GM."=");

   package Block_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => GM.Block_Entry,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=",
      "="             => GM."=");

   type Function_Info is record
      Name            : FT.UString := FT.To_UString ("");
      Kind            : FT.UString := FT.To_UString ("");
      Params          : GM.Local_Vectors.Vector;
      Has_Return_Type : Boolean := False;
      Return_Type     : GM.Type_Descriptor;
      Span            : FT.Source_Span := FT.Null_Span;
   end record;

   package Function_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Function_Info,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   type State is record
      Ranges         : Range_Maps.Map;
      Float_Facts    : Float_Maps.Map;
      Access_Facts   : Access_Maps.Map;
      Pending_Moves  : Pending_Move_Maps.Map;
      Pending_Bindings : String_Sets.Set;
      Discriminants  : Discriminant_Maps.Map;
      Relations      : String_Sets.Set;
      Div_Bounds     : Interval_Maps.Map;
      Borrow_Freeze  : Natural_Maps.Map;
      Observe_Freeze : Natural_Maps.Map;
      Returned       : Boolean := False;
   end record;

   package State_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => State,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   INT64_LOW  : constant Wide_Integer := -(2 ** 63);
   INT64_HIGH : constant Wide_Integer := (2 ** 63) - 1;
   FLOAT_FINITE_LIMIT : constant Real_Value := 1.0E+308;
   FLOAT_CONTAINMENT_EPSILON_SCALE : constant Real_Value := 4096.0;

   Diagnostic_Failure : exception;
   Raised_Diagnostic  : MD.Diagnostic;

   type Reason_Override is record
      Basename : FT.UString;
      Reason   : FT.UString;
   end record;

   type Reason_Override_Array is array (Positive range <>) of Reason_Override;

   Expected_Reason_Overrides : constant Reason_Override_Array :=
     (1 =>
        (Basename => FT.To_UString ("neg_rule1_index_fail.safe"),
         Reason   => FT.To_UString ("narrowing_check_failure")));

   use type GM.Mir_Format_Kind;
   use type GM.Expr_Kind;
   use type GM.Op_Kind;
   use type GM.Select_Arm_Kind;
   use type GM.Terminator_Kind;
   use type GM.Ownership_Effect_Kind;
   use type GM.Expr_Access;
   use type Ada.Containers.Count_Type;
   use type FT.UString;

   function Ok
     (Diagnostics : MD.Diagnostic_Vectors.Vector) return Analyze_Result;
   function Error (Message : String) return Analyze_Result;

   function Trimmed (Value : Wide_Integer) return String;
   function Format_Int (Value : Wide_Integer) return String;
   function Image (Value : Access_State_Kind) return String;
   function Image (Value : Access_Role_Kind) return String;
   function Pair_Key (Left, Right : String) return String;
   function Null_Diagnostic return MD.Diagnostic;
   function With_Path
     (Diagnostic  : MD.Diagnostic;
      Path_String : String) return MD.Diagnostic;
   procedure Append_Diagnostic
     (Diagnostics : in out MD.Diagnostic_Vectors.Vector;
      Item        : MD.Diagnostic;
      Sequence    : in out Natural);
   procedure Raise_Diag (Diagnostic : MD.Diagnostic);
   pragma No_Return (Raise_Diag);

   function Override_Reason (Basename : String) return String;
   function UString_Value (Value : FT.UString) return String;
   function Has_Text (Value : FT.UString) return Boolean;
   function Lower (Value : String) return String renames FT.Lowercase;

   procedure Add_Builtins (Type_Env : in out Type_Maps.Map; Target_Bits : Positive);
   function Resolve_Type
     (Name     : String;
      Type_Env : Type_Maps.Map) return GM.Type_Descriptor;
   function Resolve_Type
     (Name      : String;
      Var_Types : Type_Maps.Map;
      Type_Env  : Type_Maps.Map) return GM.Type_Descriptor;
   function Range_Interval
     (Info : GM.Type_Descriptor) return Interval;
   function Enum_Literal_Ordinal
     (Info         : GM.Type_Descriptor;
      Literal_Name : String) return Wide_Integer;
   function Is_Integer_Type
     (Info : GM.Type_Descriptor) return Boolean;
   function Is_Binary_Type
     (Info : GM.Type_Descriptor) return Boolean;
   function Is_Float_Type
     (Info : GM.Type_Descriptor) return Boolean;
   function Is_String_Type
     (Info : GM.Type_Descriptor) return Boolean;
   function Is_Tuple_Type
     (Info : GM.Type_Descriptor) return Boolean;
   function String_Index_Bounds
     (Info : GM.Type_Descriptor) return Interval;
   function Type_Access_Role
     (Info : GM.Type_Descriptor) return Access_Role_Kind;
   function Access_Target_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return GM.Type_Descriptor;
   function Field_Type
     (Info       : GM.Type_Descriptor;
      Field_Name : String;
      Type_Env   : Type_Maps.Map) return GM.Type_Descriptor;

   function Interval_Contains
     (Container : Interval;
      Value     : Interval) return Boolean;
   function Interval_Join
     (Left, Right : Interval) return Interval;
   function Interval_Clamp
     (Value    : Interval;
      Low_Bound  : Wide_Integer;
      High_Bound : Wide_Integer) return Interval;
   function Interval_Format
     (Value : Interval) return String;
   function Interval_Excludes_Zero
     (Value : Interval) return Boolean;
   function Try_Int64_Product
     (Left, Right : Wide_Integer;
      Product     : out Wide_Integer) return Boolean;
   function Interval_Display
     (Value : Interval;
      Info  : GM.Type_Descriptor) return String;
   function Normalize_Real_Text
     (Text : String) return String;
   function Parse_Real
     (Text : String) return Real_Value;
   function Float_Interval_For
     (Info : GM.Type_Descriptor) return Float_Interval;
   function Float_Interval_Join
     (Left, Right : Float_Interval) return Float_Interval;
   function Float_Interval_Contains
     (Container : Float_Interval;
      Value     : Float_Interval) return Boolean;
   function Float_May_Contain_Zero
     (Value : Float_Interval) return Boolean;
   function Float_Max_Abs
     (Value : Float_Interval) return Real_Value;
   function Float_Min_Abs
     (Value : Float_Interval) return Real_Value;

   function Access_Fact_For_Name
     (Name      : String;
      Current   : State;
      Var_Types : Type_Maps.Map) return Access_Fact;
   function Freeze_Count
     (Current : State;
      Name    : String;
      Kind    : Access_Role_Kind) return Natural;
   procedure Increment_Freeze
     (Current    : in out State;
      Lender     : String;
      Alias_Kind : Access_Role_Kind);
   procedure Decrement_Freeze
     (Current    : in out State;
      Lender     : String;
      Alias_Kind : Access_Role_Kind);

   function Source_Text_For_Expr
     (Expr : GM.Expr_Access) return String;
   function Flatten_Name
     (Expr : GM.Expr_Access) return String;
   function Root_Name
     (Expr : GM.Expr_Access) return String;
   function Direct_Name
     (Expr : GM.Expr_Access) return String;
   function Base_Name
     (Expr : GM.Expr_Access) return String;
   function Strip_Conversion
     (Expr : GM.Expr_Access) return GM.Expr_Access;
   function Is_Record_Field_Selector
     (Info       : GM.Type_Descriptor;
      Field_Name : String;
      Type_Env   : Type_Maps.Map) return Boolean;
   function Normalize_Alias_Path
     (Expr      : GM.Expr_Access;
      Current   : State;
      Var_Types : Type_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Functions : Function_Maps.Map) return Alias_Path;
   function Paths_Overlap
     (Left, Right : Alias_Path) return Boolean;
   function Highlight_Span
     (Expr : GM.Expr_Access) return FT.Source_Span;
   function Expr_Type
     (Expr      : GM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Functions : Function_Maps.Map) return GM.Type_Descriptor;
   function Constant_Value
     (Expr      : GM.Expr_Access;
      Current   : State;
      Var_Types : Type_Maps.Map;
      Type_Env  : Type_Maps.Map) return Wide_Integer;
   function Has_Constant_Value
     (Expr      : GM.Expr_Access;
      Current   : State;
      Var_Types : Type_Maps.Map;
      Type_Env  : Type_Maps.Map) return Boolean;
   function Constant_Real_Value
     (Expr      : GM.Expr_Access;
      Current   : State;
      Var_Types : Type_Maps.Map;
      Type_Env  : Type_Maps.Map) return Real_Value;
   function Has_Real_Constant
     (Expr      : GM.Expr_Access;
      Current   : State;
      Var_Types : Type_Maps.Map;
      Type_Env  : Type_Maps.Map) return Boolean;

   function Ownership_Note (Reason : String) return String;
   function Ownership_Diagnostic
     (Reason  : String;
      Span    : FT.Source_Span;
      Message : String;
      Note_1  : String := "";
      Note_2  : String := "") return MD.Diagnostic;
   function Overflow_Notes
     (Expr          : GM.Expr_Access;
      Interval_Value : Interval;
      Left, Right   : Interval) return FT.UString_Vectors.Vector;
   function Index_Notes
     (Expr          : GM.Expr_Access;
      Prefix_Type   : GM.Type_Descriptor;
      Index_Expr    : GM.Expr_Access;
      Var_Types     : Type_Maps.Map;
      Type_Env      : Type_Maps.Map;
      Functions     : Function_Maps.Map) return FT.UString_Vectors.Vector;
   function Index_Suggestions
     (Array_Name   : String;
      Prefix_Type  : GM.Type_Descriptor;
      Index_Expr   : GM.Expr_Access;
      Type_Env     : Type_Maps.Map) return FT.UString_Vectors.Vector;
   function Division_Notes
     (Expr      : GM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Functions : Function_Maps.Map) return FT.UString_Vectors.Vector;
   function Division_Suggestions
     (Expr : GM.Expr_Access) return FT.UString_Vectors.Vector;
   function Null_Dereference_Notes
     (Expr      : GM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Functions : Function_Maps.Map) return FT.UString_Vectors.Vector;
   function Null_Dereference_Suggestions
     (Prefix_Expr : GM.Expr_Access;
      Deref_Text  : String) return FT.UString_Vectors.Vector;

   function Owner_Write_Conflict
     (Name    : String;
      Current : State;
      Span    : FT.Source_Span) return MD.Diagnostic;
   function Owner_Read_Conflict
     (Name    : String;
      Current : State;
      Span    : FT.Source_Span) return MD.Diagnostic;
   function Observer_Write_Conflict
     (Name : String;
      Span : FT.Source_Span) return MD.Diagnostic;
   function Owner_Move_Precondition
     (Source_Name : String;
      Target_Name : String;
      Current     : State;
      Var_Types   : Type_Maps.Map;
      Span        : FT.Source_Span;
      Require_Null_Target : Boolean := True) return MD.Diagnostic;
   function Has_Pending_Move_For_Source
     (Current : State;
      Name    : String) return Boolean;
   function Target_Is_Provably_Null
     (Current   : State;
      Name      : String;
      Var_Types : Type_Maps.Map) return Boolean;
   procedure Clear_Pending_Move
     (Current : in out State;
      Name    : String);
   procedure Apply_Pending_Move_Refinement
     (Current : in out State;
      Name    : String;
      Truthy  : Boolean);

   function Eval_Access_Expr
     (Expr       : GM.Expr_Access;
      Current    : State;
      Var_Types  : Type_Maps.Map;
      Type_Env   : Type_Maps.Map;
      Functions  : Function_Maps.Map) return Access_Fact;
   procedure Ensure_Access_Safe
     (Expr       : GM.Expr_Access;
      Span       : FT.Source_Span;
      Current    : State;
      Var_Types  : Type_Maps.Map;
      Type_Env   : Type_Maps.Map;
      Functions  : Function_Maps.Map);
   function Eval_Index_Expr
     (Expr       : GM.Expr_Access;
      Current    : State;
      Var_Types  : Type_Maps.Map;
      Type_Env   : Type_Maps.Map;
      Functions  : Function_Maps.Map) return Interval;
   function Eval_Float_Expr
     (Expr       : GM.Expr_Access;
      Current    : State;
      Var_Types  : Type_Maps.Map;
      Type_Env   : Type_Maps.Map;
      Functions  : Function_Maps.Map) return Float_Interval;
   function While_Variant_Derivable
     (Condition : GM.Expr_Access;
      Local_Meta : Local_Maps.Map;
      Var_Types : Type_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Functions : Function_Maps.Map) return Boolean;
   function While_Loop_Variant_Diagnostic
     (Condition : GM.Expr_Access;
      Span      : FT.Source_Span) return MD.Diagnostic;
   procedure Check_Float_Narrowing
     (Expr           : GM.Expr_Access;
      Interval_Value : Float_Interval;
      Target_Type    : GM.Type_Descriptor);

   function Eval_Float_Expr_With_Diag
     (Expr         : GM.Expr_Access;
      Current      : State;
      Var_Types    : Type_Maps.Map;
      Type_Env     : Type_Maps.Map;
      Functions    : Function_Maps.Map;
      Target_Type  : GM.Type_Descriptor;
      Has_Diag     : out Boolean;
      Diagnostic   : out MD.Diagnostic) return Float_Interval;
   function Eval_Int_Expr
     (Expr       : GM.Expr_Access;
      Current    : State;
      Var_Types  : Type_Maps.Map;
      Type_Env   : Type_Maps.Map;
      Functions  : Function_Maps.Map) return Interval;
   function Eval_Int_Expr_With_Diag
     (Expr                    : GM.Expr_Access;
      Current                 : State;
      Var_Types               : Type_Maps.Map;
      Type_Env                : Type_Maps.Map;
      Functions               : Function_Maps.Map;
      Target_Type             : GM.Type_Descriptor;
      Suppress_Index_Convert  : Boolean;
      Has_Diagnostic          : out Boolean;
      Diagnostic              : out MD.Diagnostic) return Interval;

   function Numerator_Factor
     (Expr : GM.Expr_Access;
      Name : out FT.UString) return Wide_Integer;
   function Denominator_Var
     (Expr : GM.Expr_Access) return String;
   function Division_Interval
     (Expr    : GM.Expr_Access;
      Left    : Interval;
      Right   : Interval;
      Current : State) return Interval;
   function Overflow_Checked
     (Expr        : GM.Expr_Access;
      Low_Value   : Wide_Integer;
      High_Value  : Wide_Integer;
      Left, Right : Interval) return Interval;

   procedure Apply_Comparison_Refinement
     (Current   : in out State;
      Expr      : GM.Expr_Access;
      Truthy    : Boolean;
      Var_Types : Type_Maps.Map;
      Type_Env  : Type_Maps.Map);
   function Scalar_Value_Equal
     (Left, Right : GM.Scalar_Value) return Boolean;
   function Expr_Scalar_Value
     (Expr  : GM.Expr_Access;
      Value : out GM.Scalar_Value) return Boolean;
   function Variant_Discriminant_Name (Info : GM.Type_Descriptor) return String;
   function Constrained_Discriminant_Value
     (Info  : GM.Type_Descriptor;
      Value : out GM.Scalar_Value) return Boolean;
   function Variant_Field_Allows
     (Field      : GM.Variant_Field;
      Value      : GM.Scalar_Value;
      All_Fields : GM.Variant_Field_Vectors.Vector) return Boolean;
   procedure Apply_Discriminant_Refinement
     (Current   : in out State;
      Expr      : GM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Truthy    : Boolean;
      Type_Env : Type_Maps.Map);
   function Refine_Condition
     (Current   : State;
      Expr      : GM.Expr_Access;
      Truthy    : Boolean;
      Var_Types : Type_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Allow_Pending_Move_Refinement : Boolean := True) return State;

   procedure Initialize_Symbol
     (Current : in out State;
      Name    : String;
      Info    : GM.Type_Descriptor);
   procedure Invalidate_Discriminant_Fact
     (Current : in out State;
      Name    : String);
   function Graph_Var_Types
     (Graph    : GM.Graph_Entry;
      Type_Env : Type_Maps.Map) return Type_Maps.Map;
   function Graph_Local_Meta
     (Graph : GM.Graph_Entry) return Local_Maps.Map;
   procedure Initialize_Graph_Entry_State
     (Graph       : GM.Graph_Entry;
      Type_Env    : Type_Maps.Map;
      Entry_State : out State;
      Var_Types   : out Type_Maps.Map;
      Owner_Vars  : out String_Sets.Set;
      Local_Meta  : out Local_Maps.Map);
   procedure Invalidate_Scope_Exit
     (Current    : in out State;
      Local_Names : FT.UString_Vectors.Vector;
      Owner_Vars : String_Sets.Set);
   function Join_Two_States
     (Left, Right : State) return State;
   function States_Equal
     (Left, Right : State) return Boolean;
   function Join_State_Into
     (Targets  : in out State_Maps.Map;
      Block_Id : String;
      Candidate : State) return Boolean;
   function Diagnostic_Category_Rank
     (Item : MD.Diagnostic) return Natural;

   function Is_Constant_Target
     (Expr       : GM.Expr_Access;
      Local_Meta : Local_Maps.Map) return Boolean;

   procedure Validate_Assignment_Target
     (Expr      : GM.Expr_Access;
      Current   : State;
      Local_Meta : Local_Maps.Map;
      Var_Types : Type_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Skip_Constant_Check : Boolean := False);
   procedure Ensure_Discriminant_Safe
     (Expr      : GM.Expr_Access;
      Current   : State;
      Var_Types : Type_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Functions : Function_Maps.Map);
   function Assign_Access_Alias
     (Current     : in out State;
      Target_Name : String;
      Target_Type : GM.Type_Descriptor;
      Value       : GM.Expr_Access;
      Value_Fact  : Access_Fact;
      Span        : FT.Source_Span) return MD.Diagnostic;
   function Apply_Mir_Assignment
     (Op         : GM.Op_Entry;
      Current    : in out State;
      Var_Types  : Type_Maps.Map;
      Owner_Vars : String_Sets.Set;
      Type_Env   : Type_Maps.Map;
      Functions  : Function_Maps.Map) return MD.Diagnostic;
   function Analyze_Call_Expr
     (Expr       : GM.Expr_Access;
      Current    : in out State;
      Var_Types  : Type_Maps.Map;
      Owner_Vars : String_Sets.Set;
      Type_Env   : Type_Maps.Map;
      Functions  : Function_Maps.Map) return MD.Diagnostic;
   function Analyze_Runtime_Expr
     (Expr               : GM.Expr_Access;
      Current            : in out State;
      Var_Types          : Type_Maps.Map;
      Owner_Vars         : String_Sets.Set;
      Type_Env           : Type_Maps.Map;
      Functions          : Function_Maps.Map;
      Expected_Type_Name : String := "") return MD.Diagnostic;
   function Check_Return_Expr
     (Expr         : GM.Expr_Access;
      Return_Type  : GM.Type_Descriptor;
      Current      : State;
      Var_Types    : Type_Maps.Map;
      Owner_Vars   : String_Sets.Set;
      Type_Env     : Type_Maps.Map;
      Functions    : Function_Maps.Map) return MD.Diagnostic;
   procedure Transfer_Mir_Op
     (Op          : GM.Op_Entry;
      Current     : in out State;
      Diagnostics : in out MD.Diagnostic_Vectors.Vector;
      Sequence    : in out Natural;
      Path_String : String;
      Local_Meta  : Local_Maps.Map;
      Var_Types   : Type_Maps.Map;
      Owner_Vars  : String_Sets.Set;
      Type_Env    : Type_Maps.Map;
      Functions   : Function_Maps.Map);

   function Build_Type_Env
     (Document : GM.Mir_Document) return Type_Maps.Map;
   function Build_Functions
     (Document : GM.Mir_Document) return Function_Maps.Map;
   function Analyze_Graph
     (Graph      : GM.Graph_Entry;
      Info       : Function_Info;
      Type_Env   : Type_Maps.Map;
      Functions  : Function_Maps.Map;
      Path_String : String) return MD.Diagnostic;
   procedure Sort_Diagnostics
     (Diagnostics : in out MD.Diagnostic_Vectors.Vector);

   function Ok
     (Diagnostics : MD.Diagnostic_Vectors.Vector) return Analyze_Result is
   begin
      return (Success => True, Diagnostics => Diagnostics);
   end Ok;

   function Error (Message : String) return Analyze_Result is
   begin
      return (Success => False, Message => FT.To_UString (Message));
   end Error;

   function Trimmed (Value : Wide_Integer) return String is
   begin
      return Ada.Strings.Fixed.Trim (Wide_Integer'Image (Value), Ada.Strings.Both);
   end Trimmed;

   function Format_Int (Value : Wide_Integer) return String is
      Absolute_Image : constant String := Trimmed (abs Value);
      Result         : US.Unbounded_String := US.Null_Unbounded_String;
   begin
      for Index in Absolute_Image'Range loop
         if Index > Absolute_Image'First
           and then ((Absolute_Image'Last - Index + 1) mod 3 = 0)
         then
            US.Append (Result, "_");
         end if;
         US.Append (Result, Absolute_Image (Index));
      end loop;
      if Value < 0 then
         return "-" & US.To_String (Result);
      end if;
      return US.To_String (Result);
   end Format_Int;

   function Image (Value : Access_State_Kind) return String is
   begin
      case Value is
         when Access_Null =>
            return "Null";
         when Access_NonNull =>
            return "NonNull";
         when Access_MaybeNull =>
            return "MaybeNull";
         when Access_Moved =>
            return "Moved";
         when Access_Dangling =>
            return "Dangling";
      end case;
   end Image;

   function Image (Value : Access_Role_Kind) return String is
   begin
      case Value is
         when Role_None =>
            return "None";
         when Role_Owner =>
            return "Owner";
         when Role_General_Access =>
            return "GeneralAccess";
         when Role_Named_Constant =>
            return "NamedConstant";
         when Role_Borrow =>
            return "Borrow";
         when Role_Observe =>
            return "Observe";
      end case;
   end Image;

   function Pair_Key (Left, Right : String) return String is
   begin
      return Left & Character'Val (0) & Right;
   end Pair_Key;

   function Null_Diagnostic return MD.Diagnostic is
   begin
      return (others => <>);
   end Null_Diagnostic;

   function With_Path
     (Diagnostic  : MD.Diagnostic;
      Path_String : String) return MD.Diagnostic
   is
      Result : MD.Diagnostic := Diagnostic;
   begin
      Result.Path := FT.To_UString (Path_String);
      return Result;
   end With_Path;

   procedure Append_Diagnostic
     (Diagnostics : in out MD.Diagnostic_Vectors.Vector;
      Item        : MD.Diagnostic;
      Sequence    : in out Natural)
   is
      Result : MD.Diagnostic := Item;
   begin
      Sequence := Sequence + 1;
      Result.Sequence := Sequence;
      Diagnostics.Append (Result);
   end Append_Diagnostic;

   procedure Raise_Diag (Diagnostic : MD.Diagnostic) is
   begin
      Raised_Diagnostic := Diagnostic;
      raise Diagnostic_Failure;
   end Raise_Diag;

   function Override_Reason (Basename : String) return String is
   begin
      for Item of Expected_Reason_Overrides loop
         if UString_Value (Item.Basename) = Basename then
            return UString_Value (Item.Reason);
         end if;
      end loop;
      return "";
   end Override_Reason;

   function UString_Value (Value : FT.UString) return String is
   begin
      return FT.To_String (Value);
   end UString_Value;

   function Has_Text (Value : FT.UString) return Boolean is
   begin
      return UString_Value (Value) /= "";
   end Has_Text;

   function Parsed_Wide_Integer (Expr : GM.Expr_Access) return Wide_Integer is
      Text : constant String := UString_Value (Expr.Text);
   begin
      if Text'Length = 0 then
         return Wide_Integer (Expr.Int_Value);
      end if;

      declare
         Cleaned : String (1 .. Text'Length);
         Last    : Natural := 0;
      begin
         for Ch of Text loop
            if Ch /= '_' then
               Last := Last + 1;
               Cleaned (Last) := Ch;
            end if;
         end loop;
         return Wide_Integer'Value (Cleaned (1 .. Last));
      exception
         when Constraint_Error =>
            return Wide_Integer (Expr.Int_Value);
      end;
   end Parsed_Wide_Integer;

   procedure Add_Builtins (Type_Env : in out Type_Maps.Map; Target_Bits : Positive) is
   begin
      Type_Env.Include ("integer", BT.Integer_Type (Target_Bits));
      Type_Env.Include ("boolean", BT.Boolean_Type);
      Type_Env.Include ("string", BT.String_Type);
      Type_Env.Include ("result", BT.Result_Type);
      Type_Env.Include ("float", BT.Float_Type (With_Analysis_Metadata => True));
      Type_Env.Include ("long_float", BT.Long_Float_Type (With_Analysis_Metadata => True));
      Type_Env.Include ("duration", BT.Duration_Type (With_Analysis_Metadata => True));
   end Add_Builtins;

   function Parse_Anonymous_Access
     (Name : String) return GM.Type_Descriptor
   is
      Result : GM.Type_Descriptor;
      Prefix : constant String := "access ";
      Const_Prefix : constant String := "access constant ";
   begin
      Result.Name := FT.To_UString (Name);
      Result.Kind := FT.To_UString ("access");
      Result.Anonymous := True;
      if Name'Length >= Const_Prefix'Length
        and then Name (Name'First .. Name'First + Const_Prefix'Length - 1) = Const_Prefix
      then
         Result.Has_Target := True;
         Result.Target :=
           FT.To_UString (Name (Name'First + Const_Prefix'Length .. Name'Last));
         Result.Is_Constant := True;
         Result.Has_Access_Role := True;
         Result.Access_Role := FT.To_UString ("Observe");
         return Result;
      elsif Name'Length >= Prefix'Length
        and then Name (Name'First .. Name'First + Prefix'Length - 1) = Prefix
      then
         Result.Has_Target := True;
         Result.Target :=
           FT.To_UString (Name (Name'First + Prefix'Length .. Name'Last));
         Result.Has_Access_Role := True;
         Result.Access_Role := FT.To_UString ("Owner");
      end if;
      return Result;
   end Parse_Anonymous_Access;

   function Resolve_Type
     (Name     : String;
      Type_Env : Type_Maps.Map) return GM.Type_Descriptor
   is
      Result : GM.Type_Descriptor;
   begin
      if Name = "" then
         return Type_Env.Element ("integer");
      elsif Type_Env.Contains (Name) then
         return Type_Env.Element (Name);
      elsif Name = "integer"
        or else Name = "boolean"
        or else Name = "float"
        or else Name = "long_float"
      then
         return Type_Env.Element (Name);
      elsif Name = "__binary_8" then
         return BT.Binary_Type (8);
      elsif Name = "__binary_16" then
         return BT.Binary_Type (16);
      elsif Name = "__binary_32" then
         return BT.Binary_Type (32);
      elsif Name = "__binary_64" then
         return BT.Binary_Type (64);
      elsif Name'Length >= 7 and then Name (Name'First .. Name'First + 6) = "access " then
         return Parse_Anonymous_Access (Name);
      end if;

      Result.Name := FT.To_UString (Name);
      Result.Kind := FT.To_UString ("record");
      return Result;
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

   function Sanitize_Type_Name_Component (Value : String) return String
     renames FNU.Sanitize_Type_Name_Component_Raw;

   function Make_Tuple_Type
     (Element_Types : FT.UString_Vectors.Vector) return GM.Type_Descriptor
   is
      Result : GM.Type_Descriptor;
   begin
      Result.Name := FT.To_UString ("__tuple");
      for Item of Element_Types loop
         Result.Name :=
           Result.Name
           & FT.To_UString ("_")
           & FT.To_UString (Sanitize_Type_Name_Component (UString_Value (Item)));
      end loop;
      Result.Kind := FT.To_UString ("tuple");
      Result.Tuple_Element_Types := Element_Types;
      return Result;
   end Make_Tuple_Type;

   function Make_Growable_Array_Type
     (Component_Type : GM.Type_Descriptor) return GM.Type_Descriptor
   is
      Result : GM.Type_Descriptor;
   begin
      Result.Name :=
        FT.To_UString
          ("__growable_array_"
           & Sanitize_Type_Name_Component (UString_Value (Component_Type.Name)));
      Result.Kind := FT.To_UString ("array");
      Result.Growable := True;
      Result.Has_Component_Type := True;
      Result.Component_Type := Component_Type.Name;
      return Result;
   end Make_Growable_Array_Type;

   function Range_Interval
     (Info : GM.Type_Descriptor) return Interval
   is
      Binary_High : Wide_Integer;
      Kind        : constant String := Lower (UString_Value (Info.Kind));
   begin
      if (Kind = "integer" or else Kind = "subtype" or else Kind = "nominal")
        and then Info.Has_Low and then Info.Has_High
      then
         return
           (Low           => Wide_Integer (Info.Low),
            High          => Wide_Integer (Info.High),
            Excludes_Zero => Info.Low > 0 or else Info.High < 0);
      elsif UString_Value (Info.Name) = "integer" then
         return (Low => INT64_LOW, High => INT64_HIGH, Excludes_Zero => False);
      elsif UString_Value (Info.Name) = "boolean" then
         return (Low => 0, High => 1, Excludes_Zero => False);
      elsif Kind = "enum"
        and then Info.Has_Low
        and then Info.Has_High
      then
         return
           (Low           => Wide_Integer (Info.Low),
            High          => Wide_Integer (Info.High),
            Excludes_Zero => Info.Low > 0 or else Info.High < 0);
      elsif (Kind = "binary" or else (Kind = "subtype" and then Info.Has_Bit_Width))
        and then Info.Has_Bit_Width
      then
         Binary_High :=
           (if Info.Has_High
            then Wide_Integer (Info.High)
            else (2 ** Natural (Info.Bit_Width)) - 1);
         return
           (Low           => (if Info.Has_Low then Wide_Integer (Info.Low) else 0),
            High          => Binary_High,
            Excludes_Zero => (if Info.Has_Low then Info.Low > 0 else False));
      end if;
      return (Low => INT64_LOW, High => INT64_HIGH, Excludes_Zero => False);
   end Range_Interval;

   function Enum_Literal_Ordinal
     (Info         : GM.Type_Descriptor;
      Literal_Name : String) return Wide_Integer
   is
   begin
      if not Info.Enum_Literals.Is_Empty then
         for Index in Info.Enum_Literals.First_Index .. Info.Enum_Literals.Last_Index loop
            if UString_Value (Info.Enum_Literals (Index)) = Literal_Name then
               return Wide_Integer (Index - Info.Enum_Literals.First_Index);
            end if;
         end loop;
      end if;

      declare
         Diag : MD.Diagnostic := Null_Diagnostic;
      begin
         Diag.Reason := FT.To_UString ("narrowing_check_failure");
         Diag.Message := FT.To_UString ("unknown enum literal '" & Literal_Name & "'");
         Raise_Diag (Diag);
      end;
   end Enum_Literal_Ordinal;

   function Is_Integer_Type
     (Info : GM.Type_Descriptor) return Boolean is
      Kind : constant String := Lower (UString_Value (Info.Kind));
   begin
      return Kind = "integer" or else Kind = "subtype" or else Kind = "nominal";
   end Is_Integer_Type;

   function Is_Binary_Type
     (Info : GM.Type_Descriptor) return Boolean is
      Kind : constant String := Lower (UString_Value (Info.Kind));
   begin
      return Kind = "binary"
        or else (Kind = "subtype" and then Info.Has_Bit_Width);
   end Is_Binary_Type;

   function Is_Float_Type
     (Info : GM.Type_Descriptor) return Boolean is
   begin
      return Lower (UString_Value (Info.Kind)) = "float";
   end Is_Float_Type;

   function Is_String_Type
     (Info : GM.Type_Descriptor) return Boolean is
   begin
      return Lower (UString_Value (Info.Kind)) = "string";
   end Is_String_Type;

   function Is_Tuple_Type
     (Info : GM.Type_Descriptor) return Boolean is
   begin
      return Lower (UString_Value (Info.Kind)) = "tuple";
   end Is_Tuple_Type;

   function String_Index_Bounds
     (Info : GM.Type_Descriptor) return Interval is
   begin
      if Info.Has_Length_Bound then
         return
           (Low           => 1,
            High          => Wide_Integer (Info.Length_Bound),
            Excludes_Zero => True);
      end if;
      return (Low => 1, High => INT64_HIGH, Excludes_Zero => True);
   end String_Index_Bounds;

   function Type_Access_Role
     (Info : GM.Type_Descriptor) return Access_Role_Kind
   is
      Kind : constant String := Lower (UString_Value (Info.Kind));
      Role : constant String := UString_Value (Info.Access_Role);
   begin
      if Kind /= "access" then
         return Role_None;
      end if;
      if Info.Has_Access_Role then
         if Role = "Owner" then
            return Role_Owner;
         elsif Role = "GeneralAccess" then
            return Role_General_Access;
         elsif Role = "NamedConstant" then
            return Role_Named_Constant;
         elsif Role = "Borrow" then
            return Role_Borrow;
         elsif Role = "Observe" then
            return Role_Observe;
         end if;
      end if;
      if Info.Anonymous and then Info.Is_Constant then
         return Role_Observe;
      elsif Info.Anonymous then
         return Role_Borrow;
      elsif Info.Is_All then
         return Role_General_Access;
      elsif Info.Is_Constant then
         return Role_Named_Constant;
      end if;
      return Role_Owner;
   end Type_Access_Role;

   function Access_Target_Type
     (Info     : GM.Type_Descriptor;
      Type_Env : Type_Maps.Map) return GM.Type_Descriptor
   is
   begin
      if Lower (UString_Value (Info.Kind)) = "access" and then Info.Has_Target then
         return Resolve_Type (UString_Value (Info.Target), Type_Env);
      end if;
      return Info;
   end Access_Target_Type;

   function Field_Type
     (Info       : GM.Type_Descriptor;
      Field_Name : String;
      Type_Env   : Type_Maps.Map) return GM.Type_Descriptor
   is
      Base : GM.Type_Descriptor := Info;
   begin
      if Lower (UString_Value (Base.Kind)) = "access" then
         Base := Access_Target_Type (Base, Type_Env);
      end if;
      if Lower (UString_Value (Base.Kind)) = "record" then
         for Disc of Base.Discriminants loop
            if UString_Value (Disc.Name) = Field_Name then
               return Resolve_Type (UString_Value (Disc.Type_Name), Type_Env);
            end if;
         end loop;
         if Base.Has_Discriminant and then UString_Value (Base.Discriminant_Name) = Field_Name then
            return Resolve_Type (UString_Value (Base.Discriminant_Type), Type_Env);
         end if;
         for Field of Base.Fields loop
            if UString_Value (Field.Name) = Field_Name then
               return Resolve_Type (UString_Value (Field.Type_Name), Type_Env);
            end if;
         end loop;
      elsif Lower (UString_Value (Base.Kind)) = "tuple" then
         declare
            Index_Value : Natural := 0;
         begin
            begin
               Index_Value := Natural'Value (Field_Name);
            exception
               when Constraint_Error =>
                  return Resolve_Type ("integer", Type_Env);
            end;
            if Index_Value in 1 .. Natural (Base.Tuple_Element_Types.Length) then
               return Resolve_Type
                 (UString_Value (Base.Tuple_Element_Types (Positive (Index_Value))),
                  Type_Env);
            end if;
         end;
      end if;
      return Resolve_Type ("integer", Type_Env);
   end Field_Type;

   function Interval_Contains
     (Container : Interval;
      Value     : Interval) return Boolean is
   begin
      return Container.Low <= Value.Low and then Value.High <= Container.High;
   end Interval_Contains;

   function Interval_Join
     (Left, Right : Interval) return Interval
   is
      Low_Value  : constant Wide_Integer := Wide_Integer'Min (Left.Low, Right.Low);
      High_Value : constant Wide_Integer := Wide_Integer'Max (Left.High, Right.High);
   begin
      return
        (Low           => Low_Value,
         High          => High_Value,
         Excludes_Zero =>
           Left.Excludes_Zero
           and then Right.Excludes_Zero
           and then not (Low_Value <= 0 and then 0 <= High_Value));
   end Interval_Join;

   function Interval_Clamp
     (Value      : Interval;
      Low_Bound  : Wide_Integer;
      High_Bound : Wide_Integer) return Interval
   is
      New_Low  : constant Wide_Integer := Wide_Integer'Max (Value.Low, Low_Bound);
      New_High : constant Wide_Integer := Wide_Integer'Min (Value.High, High_Bound);
   begin
      return
        (Low           => New_Low,
         High          => New_High,
         Excludes_Zero =>
           Value.Excludes_Zero and then not (New_Low <= 0 and then 0 <= New_High));
   end Interval_Clamp;

   function Interval_Format
     (Value : Interval) return String is
   begin
      return "[" & Format_Int (Value.Low) & " .. " & Format_Int (Value.High) & "]";
   end Interval_Format;

   function Interval_Excludes_Zero
     (Value : Interval) return Boolean is
   begin
      return Value.Excludes_Zero or else Value.Low > 0 or else Value.High < 0;
   end Interval_Excludes_Zero;

   function Try_Int64_Product
     (Left, Right : Wide_Integer;
      Product     : out Wide_Integer) return Boolean
   is
   begin
      if Left < INT64_LOW
        or else Left > INT64_HIGH
        or else Right < INT64_LOW
        or else Right > INT64_HIGH
      then
         Product := 0;
         return False;
      end if;

      Product := Left * Right;
      return Product >= INT64_LOW and then Product <= INT64_HIGH;
   end Try_Int64_Product;

   function Interval_Display
     (Value : Interval;
      Info  : GM.Type_Descriptor) return String is
   begin
      if Value.Low = INT64_LOW and then Value.High = INT64_HIGH and then Has_Text (Info.Name) then
         return "[" & UString_Value (Info.Name) & "'First .. " & UString_Value (Info.Name) & "'Last]";
      end if;
      return Interval_Format (Value);
   end Interval_Display;

   function Normalize_Real_Text
     (Text : String) return String
   is
      Result : US.Unbounded_String := US.Null_Unbounded_String;
   begin
      for Ch of Text loop
         if Ch /= '_' then
            US.Append (Result, Ch);
         end if;
      end loop;
      return US.To_String (Result);
   end Normalize_Real_Text;

   function Parse_Real
     (Text : String) return Real_Value is
      Normalized : constant String := Normalize_Real_Text (Text);
   begin
      return Real_Value'Value (Normalized);
   exception
      when others =>
         --  when-others-ok: invalid literal parser exceptions are re-raised with normalized text.
         raise Constraint_Error with "invalid real text: " & Normalized;
   end Parse_Real;

   function Float_Interval_For
     (Info : GM.Type_Descriptor) return Float_Interval
   is
      Low_Value  : Real_Value := -FLOAT_FINITE_LIMIT;
      High_Value : Real_Value := FLOAT_FINITE_LIMIT;
   begin
      if Is_Float_Type (Info) then
         if Info.Has_Float_Low_Text then
            Low_Value := Parse_Real (UString_Value (Info.Float_Low_Text));
         end if;
         if Info.Has_Float_High_Text then
            High_Value := Parse_Real (UString_Value (Info.Float_High_Text));
         end if;
      end if;
      return
        (Low             => Low_Value,
         High            => High_Value,
         Initialized     => True,
         May_Be_NaN      => False,
         May_Be_Infinite => False,
         Excludes_Zero   => Low_Value > 0.0 or else High_Value < 0.0);
   end Float_Interval_For;

   function Float_Interval_Join
     (Left, Right : Float_Interval) return Float_Interval is
   begin
      return
        (Low             => Real_Value'Min (Left.Low, Right.Low),
         High            => Real_Value'Max (Left.High, Right.High),
         Initialized     => Left.Initialized and then Right.Initialized,
         May_Be_NaN      => Left.May_Be_NaN or else Right.May_Be_NaN,
         May_Be_Infinite => Left.May_Be_Infinite or else Right.May_Be_Infinite,
         Excludes_Zero   =>
           Left.Excludes_Zero
           and then Right.Excludes_Zero
           and then not
             (Real_Value'Min (Left.Low, Right.Low) <= 0.0
              and then 0.0 <= Real_Value'Max (Left.High, Right.High)));
   end Float_Interval_Join;

   function Float_Interval_Contains
     (Container : Float_Interval;
      Value     : Float_Interval) return Boolean is
      Max_Abs : constant Real_Value :=
        Real_Value'Max
          (1.0,
           Real_Value'Max
             (Real_Value'Max (abs Container.Low, abs Container.High),
              Real_Value'Max (abs Value.Low, abs Value.High)));
      Tolerance : constant Real_Value :=
        Real_Value'Max
          (1.0E-12,
           FLOAT_CONTAINMENT_EPSILON_SCALE * Real_Value'Model_Epsilon * Max_Abs);
   begin
      return
        Value.Initialized
        and then not Value.May_Be_NaN
        and then not Value.May_Be_Infinite
        and then Container.Low - Tolerance <= Value.Low
        and then Value.High <= Container.High + Tolerance;
   end Float_Interval_Contains;

   function Float_May_Contain_Zero
     (Value : Float_Interval) return Boolean is
   begin
      return not Value.Excludes_Zero and then Value.Low <= 0.0 and then 0.0 <= Value.High;
   end Float_May_Contain_Zero;

   function Float_Max_Abs
     (Value : Float_Interval) return Real_Value is
   begin
      return Real_Value'Max (abs Value.Low, abs Value.High);
   end Float_Max_Abs;

   function Float_Min_Abs
     (Value : Float_Interval) return Real_Value is
      Low_Abs  : constant Real_Value := abs Value.Low;
      High_Abs : constant Real_Value := abs Value.High;
   begin
      if Float_May_Contain_Zero (Value) then
         return 0.0;
      end if;
      return Real_Value'Min (Low_Abs, High_Abs);
   end Float_Min_Abs;

   function Access_Fact_For_Name
     (Name      : String;
      Current   : State;
      Var_Types : Type_Maps.Map) return Access_Fact
   is
      Type_Info : GM.Type_Descriptor;
      Role      : Access_Role_Kind;
   begin
      if Current.Access_Facts.Contains (Name) then
         return Current.Access_Facts.Element (Name);
      end if;
      if not Var_Types.Contains (Name) then
         return (State => Access_MaybeNull, others => <>);
      end if;
      Type_Info := Var_Types.Element (Name);
      if Lower (UString_Value (Type_Info.Kind)) = "access" then
         if Type_Info.Not_Null then
            return (State => Access_NonNull, others => <>);
         end if;
         Role := Type_Access_Role (Type_Info);
         if Role = Role_Owner then
            return (State => Access_Null, others => <>);
         end if;
      end if;
      return (State => Access_MaybeNull, others => <>);
   end Access_Fact_For_Name;

   function Freeze_Count
     (Current : State;
      Name    : String;
      Kind    : Access_Role_Kind) return Natural is
   begin
      if Kind = Role_Borrow then
         if Current.Borrow_Freeze.Contains (Name) then
            return Current.Borrow_Freeze.Element (Name);
         end if;
      elsif Kind = Role_Observe then
         if Current.Observe_Freeze.Contains (Name) then
            return Current.Observe_Freeze.Element (Name);
         end if;
      end if;
      return 0;
   end Freeze_Count;

   procedure Increment_Freeze
     (Current    : in out State;
      Lender     : String;
      Alias_Kind : Access_Role_Kind) is
      Count : Natural;
   begin
      if Alias_Kind = Role_Borrow then
         Count := Freeze_Count (Current, Lender, Alias_Kind);
         Current.Borrow_Freeze.Include (Lender, Count + 1);
      elsif Alias_Kind = Role_Observe then
         Count := Freeze_Count (Current, Lender, Alias_Kind);
         Current.Observe_Freeze.Include (Lender, Count + 1);
      end if;
   end Increment_Freeze;

   procedure Decrement_Freeze
     (Current    : in out State;
      Lender     : String;
      Alias_Kind : Access_Role_Kind) is
      Count : Natural;
   begin
      if Alias_Kind = Role_Borrow then
         Count := Freeze_Count (Current, Lender, Alias_Kind);
         if Count <= 1 then
            if Current.Borrow_Freeze.Contains (Lender) then
               Current.Borrow_Freeze.Delete (Lender);
            end if;
         else
            Current.Borrow_Freeze.Include (Lender, Count - 1);
         end if;
      elsif Alias_Kind = Role_Observe then
         Count := Freeze_Count (Current, Lender, Alias_Kind);
         if Count <= 1 then
            if Current.Observe_Freeze.Contains (Lender) then
               Current.Observe_Freeze.Delete (Lender);
            end if;
         else
            Current.Observe_Freeze.Include (Lender, Count - 1);
         end if;
      end if;
   end Decrement_Freeze;

   function Source_Text_For_Expr
     (Expr : GM.Expr_Access) return String is
      Result : US.Unbounded_String := US.Null_Unbounded_String;
   begin
      if Expr = null then
         return "";
      end if;
      case Expr.Kind is
         when GM.Expr_Binary =>
            return
              Source_Text_For_Expr (Expr.Left)
              & " "
              & UString_Value (Expr.Operator)
              & " "
              & Source_Text_For_Expr (Expr.Right);
         when GM.Expr_Unary =>
            return UString_Value (Expr.Operator) & Source_Text_For_Expr (Expr.Inner);
         when GM.Expr_Ident =>
            return UString_Value (Expr.Name);
         when GM.Expr_Int =>
            return UString_Value (Expr.Text);
         when GM.Expr_Real =>
            return UString_Value (Expr.Text);
         when GM.Expr_String =>
            return UString_Value (Expr.Text);
         when GM.Expr_Bool =>
            if Expr.Bool_Value then
               return "true";
            end if;
            return "false";
         when GM.Expr_Select =>
            return Source_Text_For_Expr (Expr.Prefix) & "." & UString_Value (Expr.Selector);
         when GM.Expr_Resolved_Index =>
            US.Append (Result, Source_Text_For_Expr (Expr.Prefix));
            US.Append (Result, " (");
            if not Expr.Indices.Is_Empty then
               for Index in Expr.Indices.First_Index .. Expr.Indices.Last_Index loop
                  if Index > Expr.Indices.First_Index then
                     US.Append (Result, ", ");
                  end if;
                  US.Append (Result, Source_Text_For_Expr (Expr.Indices (Index)));
               end loop;
            end if;
            US.Append (Result, ")");
            return US.To_String (Result);
         when GM.Expr_Conversion =>
            return UString_Value (Expr.Name) & " (" & Source_Text_For_Expr (Expr.Inner) & ")";
         when GM.Expr_Call =>
            return "call";
         when GM.Expr_Null =>
            return "null";
         when GM.Expr_Unknown
            | GM.Expr_Enum_Literal
            | GM.Expr_Allocator
            | GM.Expr_Aggregate
            | GM.Expr_Array_Literal
            | GM.Expr_Tuple
            | GM.Expr_Annotated =>
            return GM.Image (Expr.Kind);
      end case;
   end Source_Text_For_Expr;

   function Flatten_Name
     (Expr : GM.Expr_Access) return String is
   begin
      if Expr = null then
         return "";
      elsif Expr.Kind = GM.Expr_Ident then
         return UString_Value (Expr.Name);
      elsif Expr.Kind = GM.Expr_Select then
         return Flatten_Name (Expr.Prefix) & "." & UString_Value (Expr.Selector);
      end if;
      return "";
   end Flatten_Name;

   function Root_Name
     (Expr : GM.Expr_Access) return String is
   begin
      if Expr = null then
         return "";
      end if;
      case Expr.Kind is
         when GM.Expr_Ident =>
            return UString_Value (Expr.Name);
         when GM.Expr_Select =>
            return Root_Name (Expr.Prefix);
         when GM.Expr_Resolved_Index =>
            return Root_Name (Expr.Prefix);
         when GM.Expr_Conversion =>
            return Root_Name (Expr.Inner);
         when GM.Expr_Unknown
            | GM.Expr_Int
            | GM.Expr_Real
            | GM.Expr_String
            | GM.Expr_Bool
            | GM.Expr_Enum_Literal
            | GM.Expr_Null
            | GM.Expr_Call
            | GM.Expr_Allocator
            | GM.Expr_Aggregate
            | GM.Expr_Array_Literal
            | GM.Expr_Tuple
            | GM.Expr_Annotated
            | GM.Expr_Unary
            | GM.Expr_Binary =>
            return "";
      end case;
   end Root_Name;

   function Direct_Name
     (Expr : GM.Expr_Access) return String is
   begin
      if Expr = null then
         return "";
      elsif Expr.Kind = GM.Expr_Ident then
         return UString_Value (Expr.Name);
      elsif Expr.Kind = GM.Expr_Conversion then
         return Direct_Name (Expr.Inner);
      end if;
      return "";
   end Direct_Name;

   function Base_Name
     (Expr : GM.Expr_Access) return String is
   begin
      if Expr /= null and then Expr.Kind = GM.Expr_Ident then
         return UString_Value (Expr.Name);
      end if;
      return "";
   end Base_Name;

   function Strip_Conversion
     (Expr : GM.Expr_Access) return GM.Expr_Access is
   begin
      if Expr /= null and then Expr.Kind = GM.Expr_Conversion then
         return Expr.Inner;
      end if;
      return Expr;
   end Strip_Conversion;

   function Is_Record_Field_Selector
     (Info       : GM.Type_Descriptor;
      Field_Name : String;
      Type_Env   : Type_Maps.Map) return Boolean
   is
      Base : GM.Type_Descriptor := Info;
   begin
      if Lower (UString_Value (Base.Kind)) = "access" then
         Base := Access_Target_Type (Base, Type_Env);
      end if;
      if Lower (UString_Value (Base.Kind)) /= "record" then
         return False;
      end if;
      for Field of Base.Fields loop
         if UString_Value (Field.Name) = Field_Name then
            return True;
         end if;
      end loop;
      return False;
   end Is_Record_Field_Selector;

   function Normalize_Alias_Path
     (Expr      : GM.Expr_Access;
      Current   : State;
      Var_Types : Type_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Functions : Function_Maps.Map) return Alias_Path
   is
      Result      : Alias_Path;
      Prefix_Path : Alias_Path;
   begin
      if Expr = null then
         return Result;
      end if;
      case Expr.Kind is
         when GM.Expr_Conversion =>
            return Normalize_Alias_Path (Expr.Inner, Current, Var_Types, Type_Env, Functions);
         when GM.Expr_Ident =>
            Result.Root := Expr.Name;
            Result.Supported := True;
            return Result;
         when GM.Expr_Select =>
            Prefix_Path := Normalize_Alias_Path (Expr.Prefix, Current, Var_Types, Type_Env, Functions);
            Result.Root := Prefix_Path.Root;
            Result.Components := Prefix_Path.Components;
            if Prefix_Path.Supported
              and then Is_Record_Field_Selector
                        (Expr_Type (Expr.Prefix, Var_Types, Type_Env, Functions),
                         UString_Value (Expr.Selector),
                         Type_Env)
            then
               Result.Components.Append (UString_Value (Expr.Selector));
               Result.Supported := True;
            end if;
            return Result;
         when GM.Expr_Resolved_Index =>
            Prefix_Path := Normalize_Alias_Path (Expr.Prefix, Current, Var_Types, Type_Env, Functions);
            Result.Root := Prefix_Path.Root;
            Result.Components := Prefix_Path.Components;
            if Prefix_Path.Supported
              and then Natural (Expr.Indices.Length) = 1
            then
               declare
                  Prefix_Type  : constant GM.Type_Descriptor :=
                    Expr_Type (Expr.Prefix, Var_Types, Type_Env, Functions);
                  Index_Range : constant Interval :=
                    Eval_Int_Expr
                      (Expr.Indices (Expr.Indices.First_Index),
                       Current,
                       Var_Types,
                       Type_Env,
                       Functions);
               begin
                  if FT.Lowercase (UString_Value (Prefix_Type.Kind)) = "array"
                    and then Index_Range.Low = Index_Range.High
                  then
                     Result.Components.Append ("[" & Format_Int (Index_Range.Low) & "]");
                     Result.Supported := True;
                  end if;
               end;
            end if;
            return Result;
         when GM.Expr_Unknown
            | GM.Expr_Int
            | GM.Expr_Real
            | GM.Expr_String
            | GM.Expr_Bool
            | GM.Expr_Enum_Literal
            | GM.Expr_Null
            | GM.Expr_Call
            | GM.Expr_Allocator
            | GM.Expr_Aggregate
            | GM.Expr_Array_Literal
            | GM.Expr_Tuple
            | GM.Expr_Annotated
            | GM.Expr_Unary
            | GM.Expr_Binary =>
            Result.Root := FT.To_UString (Root_Name (Expr));
            return Result;
      end case;
   end Normalize_Alias_Path;

   function Paths_Overlap
     (Left, Right : Alias_Path) return Boolean
   is
      Common_Length : Natural := 0;
   begin
      if not Left.Supported or else not Right.Supported then
         return True;
      end if;

      Common_Length :=
        Natural'Min
          (Natural (Left.Components.Length),
           Natural (Right.Components.Length));

      for Index in 1 .. Common_Length loop
         if Left.Components (Positive (Index)) /= Right.Components (Positive (Index)) then
            return False;
         end if;
      end loop;
      return True;
   end Paths_Overlap;

   function Highlight_Span
     (Expr : GM.Expr_Access) return FT.Source_Span
   is
      Result   : constant FT.Source_Span := FT.Null_Span;
      Op_Start : Positive;
   begin
      if Expr = null then
         return Result;
      elsif Expr.Kind = GM.Expr_Binary then
         declare
            Op : constant String := UString_Value (Expr.Operator);
         begin
            if Op = "/" or else Op = "mod" or else Op = "rem" then
               Op_Start := Expr.Left.Span.End_Pos.Column + 2;
               return
                 (Start_Pos => (Line => Expr.Span.Start_Pos.Line, Column => Op_Start),
                  End_Pos   =>
                    (Line   => Expr.Span.Start_Pos.Line,
                     Column => Op_Start + Op'Length - 1));
            end if;
         end;
      end if;
      return Expr.Span;
   end Highlight_Span;

   function Expr_Type
     (Expr      : GM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Functions : Function_Maps.Map) return GM.Type_Descriptor
   is
      Prefix_Type : GM.Type_Descriptor;
      Callee_Name : FT.UString := FT.To_UString ("");
      Result      : GM.Type_Descriptor;
   begin
      if Expr = null then
         return Resolve_Type ("integer", Type_Env);
      end if;

      case Expr.Kind is
         when GM.Expr_Tuple =>
            declare
               Elements : FT.UString_Vectors.Vector;
            begin
               for Item of Expr.Elements loop
                  Elements.Append (Expr_Type (Item, Var_Types, Type_Env, Functions).Name);
               end loop;
               return Make_Tuple_Type (Elements);
            end;
         when GM.Expr_Array_Literal =>
            if Has_Text (Expr.Type_Name)
              and then Type_Env.Contains (UString_Value (Expr.Type_Name))
            then
               return Resolve_Type (UString_Value (Expr.Type_Name), Var_Types, Type_Env);
            elsif not Expr.Elements.Is_Empty then
               return
                 Make_Growable_Array_Type
                   (Expr_Type
                      (Expr.Elements (Expr.Elements.First_Index),
                       Var_Types,
                       Type_Env,
                       Functions));
            end if;
            return Make_Growable_Array_Type (Resolve_Type ("integer", Type_Env));
         when GM.Expr_Ident =>
            if Var_Types.Contains (UString_Value (Expr.Name)) then
               return Var_Types.Element (UString_Value (Expr.Name));
            elsif Has_Text (Expr.Type_Name)
              and then Type_Env.Contains (UString_Value (Expr.Type_Name))
            then
               return Resolve_Type (UString_Value (Expr.Type_Name), Var_Types, Type_Env);
            elsif Type_Env.Contains (UString_Value (Expr.Name)) then
               return Type_Env.Element (UString_Value (Expr.Name));
            end if;
         when GM.Expr_Real =>
            if Has_Text (Expr.Type_Name) then
               return Resolve_Type (UString_Value (Expr.Type_Name), Var_Types, Type_Env);
            end if;
            return Resolve_Type ("long_float", Type_Env);
         when GM.Expr_Select =>
            if UString_Value (Expr.Selector) = "all" then
               return Access_Target_Type (Expr_Type (Expr.Prefix, Var_Types, Type_Env, Functions), Type_Env);
            elsif UString_Value (Expr.Selector) = "access" then
               Prefix_Type := Access_Target_Type (Expr_Type (Expr.Prefix, Var_Types, Type_Env, Functions), Type_Env);
               Result.Name := FT.To_UString ("access constant " & UString_Value (Prefix_Type.Name));
               Result.Kind := FT.To_UString ("access");
               Result.Has_Target := True;
               Result.Target := Prefix_Type.Name;
               Result.Not_Null := True;
               Result.Anonymous := True;
               Result.Is_Constant := True;
               Result.Has_Access_Role := True;
               Result.Access_Role := FT.To_UString ("Observe");
               return Result;
            elsif UString_Value (Expr.Selector) = "first"
              or else UString_Value (Expr.Selector) = "last"
            then
               return Resolve_Type ("integer", Type_Env);
            end if;
            Prefix_Type := Expr_Type (Expr.Prefix, Var_Types, Type_Env, Functions);
            return Field_Type (Prefix_Type, UString_Value (Expr.Selector), Type_Env);
         when GM.Expr_Resolved_Index =>
            Prefix_Type := Expr_Type (Expr.Prefix, Var_Types, Type_Env, Functions);
            if Prefix_Type.Has_Component_Type then
               return Resolve_Type (UString_Value (Prefix_Type.Component_Type), Type_Env);
            end if;
         when GM.Expr_Conversion =>
            return Resolve_Type (UString_Value (Expr.Name), Var_Types, Type_Env);
         when GM.Expr_Call =>
            Callee_Name := FT.To_UString (Flatten_Name (Expr.Callee));
            if Functions.Contains (UString_Value (Callee_Name)) then
               declare
                  Info : constant Function_Info := Functions.Element (UString_Value (Callee_Name));
               begin
                  if Info.Has_Return_Type then
                     return Info.Return_Type;
                  end if;
               end;
            elsif Var_Types.Contains (UString_Value (Callee_Name)) then
               return Var_Types.Element (UString_Value (Callee_Name));
            elsif UString_Value (Callee_Name) = "long_float.copy_sign" then
               return Resolve_Type ("long_float", Type_Env);
            end if;
         when GM.Expr_Allocator =>
            if Expr.Value /= null and then Expr.Value.Kind = GM.Expr_Annotated then
               Result.Name := FT.To_UString ("access " & UString_Value (Expr.Value.Subtype_Name));
               Result.Kind := FT.To_UString ("access");
               Result.Has_Target := True;
               Result.Target := Expr.Value.Subtype_Name;
               Result.Not_Null := True;
               Result.Has_Access_Role := True;
               Result.Access_Role := FT.To_UString ("Owner");
               return Result;
            end if;
         when GM.Expr_Bool =>
            return Resolve_Type ("boolean", Type_Env);
         when GM.Expr_Unknown
            | GM.Expr_Int
            | GM.Expr_String
            | GM.Expr_Enum_Literal
            | GM.Expr_Null
            | GM.Expr_Aggregate
            | GM.Expr_Annotated
            | GM.Expr_Unary
            | GM.Expr_Binary =>
            null;
      end case;

      if Has_Text (Expr.Type_Name) then
         return Resolve_Type (UString_Value (Expr.Type_Name), Var_Types, Type_Env);
      end if;
      return Resolve_Type ("integer", Type_Env);
   end Expr_Type;

   function Has_Constant_Value
     (Expr      : GM.Expr_Access;
      Current   : State;
      Var_Types : Type_Maps.Map;
      Type_Env  : Type_Maps.Map) return Boolean
   is
      Dummy : Wide_Integer := 0;
   begin
      Dummy := Constant_Value (Expr, Current, Var_Types, Type_Env);
      return True;
   exception
      when others =>
         --  when-others-ok: constant probe intentionally treats any evaluation failure as unknown.
         return False;
   end Has_Constant_Value;

   function Constant_Value
     (Expr      : GM.Expr_Access;
      Current   : State;
      Var_Types : Type_Maps.Map;
      Type_Env  : Type_Maps.Map) return Wide_Integer
   is
      Prefix : FT.UString := FT.To_UString ("");
      Type_Info : GM.Type_Descriptor;
   begin
      if Expr = null then
         raise Constraint_Error with "no constant";
      end if;
      case Expr.Kind is
         when GM.Expr_Int =>
            return Wide_Integer (Expr.Int_Value);
         when GM.Expr_Bool =>
            if Expr.Bool_Value then
               return 1;
            end if;
            return 0;
         when GM.Expr_Unary =>
            if UString_Value (Expr.Operator) = "-" then
               return -Constant_Value (Expr.Inner, Current, Var_Types, Type_Env);
            end if;
         when GM.Expr_Conversion =>
            return Constant_Value (Expr.Inner, Current, Var_Types, Type_Env);
         when GM.Expr_Select =>
            if UString_Value (Expr.Selector) = "first" or else UString_Value (Expr.Selector) = "last" then
               Prefix := FT.To_UString (Flatten_Name (Expr.Prefix));
               Type_Info := Resolve_Type (UString_Value (Prefix), Var_Types, Type_Env);
               if Type_Info.Has_Low and then Type_Info.Has_High then
                  if UString_Value (Expr.Selector) = "first" then
                     return Wide_Integer (Type_Info.Low);
                  end if;
                  return Wide_Integer (Type_Info.High);
               end if;
            end if;
         when GM.Expr_Unknown
            | GM.Expr_Real
            | GM.Expr_String
            | GM.Expr_Enum_Literal
            | GM.Expr_Null
            | GM.Expr_Ident
            | GM.Expr_Resolved_Index
            | GM.Expr_Call
            | GM.Expr_Allocator
            | GM.Expr_Aggregate
            | GM.Expr_Array_Literal
            | GM.Expr_Tuple
            | GM.Expr_Annotated
            | GM.Expr_Binary =>
            null;
      end case;
      if Expr.Kind = GM.Expr_Ident and then Current.Ranges.Contains (UString_Value (Expr.Name)) then
         declare
            Value : constant Interval := Current.Ranges.Element (UString_Value (Expr.Name));
         begin
            if Value.Low = Value.High then
               return Value.Low;
            end if;
         end;
      end if;
      raise Constraint_Error with "no constant";
   end Constant_Value;

   function Constant_Real_Value
     (Expr      : GM.Expr_Access;
      Current   : State;
      Var_Types : Type_Maps.Map;
      Type_Env  : Type_Maps.Map) return Real_Value
   is
   begin
      if Expr = null then
         raise Constraint_Error with "no real constant";
      end if;
      case Expr.Kind is
         when GM.Expr_Real =>
            return Parse_Real (UString_Value (Expr.Text));
         when GM.Expr_Int =>
            return Real_Value (Expr.Int_Value);
         when GM.Expr_Conversion =>
            return Constant_Real_Value (Expr.Inner, Current, Var_Types, Type_Env);
         when GM.Expr_Unary =>
            if UString_Value (Expr.Operator) = "-" then
               return -Constant_Real_Value (Expr.Inner, Current, Var_Types, Type_Env);
            end if;
         when GM.Expr_Ident =>
            if Current.Float_Facts.Contains (UString_Value (Expr.Name)) then
               declare
                  Value : constant Float_Interval := Current.Float_Facts.Element (UString_Value (Expr.Name));
               begin
                  if Value.Initialized
                    and then not Value.May_Be_NaN
                    and then not Value.May_Be_Infinite
                    and then Value.Low = Value.High
                  then
                     return Value.Low;
                  end if;
               end;
            end if;
            if Current.Ranges.Contains (UString_Value (Expr.Name)) then
               declare
                  Value : constant Interval := Current.Ranges.Element (UString_Value (Expr.Name));
               begin
                  if Value.Low = Value.High then
                     return Real_Value (Value.Low);
                  end if;
               end;
            end if;
         when GM.Expr_Unknown
            | GM.Expr_String
            | GM.Expr_Bool
            | GM.Expr_Enum_Literal
            | GM.Expr_Null
            | GM.Expr_Select
            | GM.Expr_Resolved_Index
            | GM.Expr_Call
            | GM.Expr_Allocator
            | GM.Expr_Aggregate
            | GM.Expr_Array_Literal
            | GM.Expr_Tuple
            | GM.Expr_Annotated
            | GM.Expr_Binary =>
            null;
      end case;
      raise Constraint_Error with "no real constant";
   end Constant_Real_Value;

   function Has_Real_Constant
     (Expr      : GM.Expr_Access;
      Current   : State;
      Var_Types : Type_Maps.Map;
      Type_Env  : Type_Maps.Map) return Boolean
   is
      Dummy : Real_Value := 0.0;
   begin
      Dummy := Constant_Real_Value (Expr, Current, Var_Types, Type_Env);
      return True;
   exception
      when others =>
         --  when-others-ok: real constant probe intentionally treats any evaluation failure as unknown.
         return False;
   end Has_Real_Constant;

   procedure Ensure_Discriminant_Safe
     (Expr      : GM.Expr_Access;
      Current   : State;
      Var_Types : Type_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Functions : Function_Maps.Map)
   is
      Prefix_Type : GM.Type_Descriptor;
      Variant_Info : GM.Type_Descriptor;
      Base_Name_Text : constant String := Root_Name (Expr.Prefix);
      Found       : Boolean := False;
      Fact        : Discriminant_Fact;
      Constraint_Value : GM.Scalar_Value;
      Diag        : MD.Diagnostic := Null_Diagnostic;
      Disc_Name_Text : FT.UString := FT.To_UString ("");
   begin
      if Expr = null or else Expr.Kind /= GM.Expr_Select or else Base_Name_Text = "" then
         return;
      end if;
      Prefix_Type := Expr_Type (Expr.Prefix, Var_Types, Type_Env, Functions);
      if Lower (UString_Value (Prefix_Type.Kind)) = "access" then
         Prefix_Type := Access_Target_Type (Prefix_Type, Type_Env);
      end if;
      Variant_Info := Prefix_Type;
      if Lower (UString_Value (Variant_Info.Kind)) = "subtype"
        and then Variant_Info.Has_Base
      then
         Variant_Info := Resolve_Type (UString_Value (Variant_Info.Base), Type_Env);
      end if;
      if Lower (UString_Value (Variant_Info.Kind)) = "access" then
         Variant_Info := Access_Target_Type (Variant_Info, Type_Env);
      end if;
      Disc_Name_Text := FT.To_UString (Variant_Discriminant_Name (Variant_Info));
      if not Has_Text (Disc_Name_Text) or else Variant_Info.Variant_Fields.Is_Empty then
         return;
      end if;
      for Field of Variant_Info.Variant_Fields loop
         if UString_Value (Field.Name) = UString_Value (Expr.Selector) then
            Found := True;
            if Constrained_Discriminant_Value (Prefix_Type, Constraint_Value)
              and then Variant_Field_Allows
                (Field, Constraint_Value, Variant_Info.Variant_Fields)
            then
               return;
            end if;
            if Current.Discriminants.Contains (Base_Name_Text) then
               Fact := Current.Discriminants.Element (Base_Name_Text);
            end if;
            if Fact.Known
              and then Variant_Field_Allows (Field, Fact.Value, Variant_Info.Variant_Fields)
            then
               return;
            end if;
            Diag.Reason := FT.To_UString ("discriminant_check_not_established");
            Diag.Message :=
              FT.To_UString
                ("access to variant field '" & UString_Value (Expr.Selector)
                 & "' requires established discriminant '" & UString_Value (Disc_Name_Text) & "'");
            Diag.Span := Expr.Span;
            Diag.Has_Highlight_Span := True;
            Diag.Highlight_Span := Expr.Span;
            if Fact.Invalidated then
               Diag.Notes.Append
                 (FT.To_UString
                    ("the discriminant fact for '" & Base_Name_Text
                     & "' was invalidated by assignment or an out/in out call."));
            else
               Diag.Notes.Append
                 (FT.To_UString
                    ("the discriminant '" & UString_Value (Disc_Name_Text)
                     & "' was not established on all paths before this access."));
            end if;
            Raise_Diag (Diag);
         end if;
      end loop;
      if not Found then
         return;
      end if;
   end Ensure_Discriminant_Safe;

   function Ownership_Note (Reason : String) return String is
   begin
      if Reason = "double_move" then
         return "rule: Safe §2.3.2 (move semantics)";
      elsif Reason = "use_after_move" then
         return "rule: Safe §2.3.2 (post-move restrictions)";
      elsif Reason = "borrow_conflict" then
         return "rule: Safe §2.3.3 (mutable borrow freezes lender)";
      elsif Reason = "observe_mutation" then
         return "rule: Safe §2.3.4 (observe is read-only; source frozen for write/move)";
      elsif Reason = "lifetime_violation" then
         return "rule: Safe §2.3.3 / §2.3.4a (lifetime containment)";
      elsif Reason = "move_target_not_null" then
         return "rule: Safe §2.3.2 (target of move must be provably null)";
      elsif Reason = "move_source_not_nonnull" then
         return "rule: Safe §2.3.2 (source of move must be provably non-null)";
      elsif Reason = "anonymous_access_reassign" then
         return "rule: Safe §2.3.3 / §2.3.4a (anonymous access is initialization-only)";
      elsif Reason = "observe_requires_access" then
         return "rule: Safe §2.3.4 (local observe must use .access)";
      end if;
      return "";
   end Ownership_Note;

   function Ownership_Diagnostic
     (Reason  : String;
      Span    : FT.Source_Span;
      Message : String;
      Note_1  : String := "";
      Note_2  : String := "") return MD.Diagnostic
   is
      Result : MD.Diagnostic;
   begin
      Result.Reason := FT.To_UString (Reason);
      Result.Message := FT.To_UString (Message);
      Result.Span := Span;
      Result.Has_Highlight_Span := True;
      Result.Highlight_Span := Span;
      if Note_1 /= "" then
         Result.Notes.Append (FT.To_UString (Note_1));
      end if;
      if Note_2 /= "" then
         Result.Notes.Append (FT.To_UString (Note_2));
      end if;
      declare
         Rule_Note : constant String := Ownership_Note (Reason);
      begin
         if Rule_Note /= "" then
            Result.Notes.Append (FT.To_UString (Rule_Note));
         end if;
      end;
      return Result;
   end Ownership_Diagnostic;

   function Overflow_Notes
     (Expr           : GM.Expr_Access;
      Interval_Value : Interval;
      Left, Right    : Interval) return FT.UString_Vectors.Vector
   is
      Result : FT.UString_Vectors.Vector;
   begin
      Result.Append
        (FT.To_UString
           ("static range analysis determines that the subexpression ("
            & Source_Text_For_Expr (Expr)
            & ")"
            & ASCII.LF
            & "has range "
            & Interval_Format (Interval_Value)
            & ASCII.LF
            & "which exceeds the 64-bit signed range"
            & ASCII.LF
            & "["
            & Format_Int (INT64_LOW)
            & " .. "
            & Format_Int (INT64_HIGH)
            & "]."));
      if Expr /= null and then Expr.Kind = GM.Expr_Binary
        and then Expr.Left /= null and then Expr.Left.Kind = GM.Expr_Ident
      then
         Result.Append
           (FT.To_UString (UString_Value (Expr.Left.Name) & " has range " & Interval_Format (Left)));
      end if;
      if Expr /= null and then Expr.Kind = GM.Expr_Binary
        and then Expr.Right /= null and then Expr.Right.Kind = GM.Expr_Ident
      then
         Result.Append
           (FT.To_UString (UString_Value (Expr.Right.Name) & " has range " & Interval_Format (Right)));
      end if;
      Result.Append (FT.To_UString ("rule: D27 Rule 1 (Wide Intermediate Arithmetic)"));
      Result.Append
        (FT.To_UString
           ("per spec/02-restrictions.md section 2.8.1 paragraph 129:"
            & ASCII.LF
            & """If a conforming implementation cannot establish, by sound static"
            & ASCII.LF
            & "range analysis, that every intermediate subexpression of an integer"
            & ASCII.LF
            & "arithmetic expression stays within the 64-bit signed range, the"
            & ASCII.LF
            & "expression shall be rejected with a diagnostic."""));
      return Result;
   end Overflow_Notes;

   function Index_Notes
     (Expr           : GM.Expr_Access;
      Prefix_Type    : GM.Type_Descriptor;
      Index_Expr     : GM.Expr_Access;
      Var_Types      : Type_Maps.Map;
      Type_Env       : Type_Maps.Map;
      Functions      : Function_Maps.Map) return FT.UString_Vectors.Vector
   is
      Result          : FT.UString_Vectors.Vector;
      Prefix_Name     : constant String :=
        (if Expr /= null and then Expr.Prefix /= null then
            (if Expr.Prefix.Kind = GM.Expr_Ident or else Expr.Prefix.Kind = GM.Expr_Select then
                Flatten_Name (Expr.Prefix)
             else Source_Text_For_Expr (Expr.Prefix))
         else "");
      Index_Type      : GM.Type_Descriptor :=
        (if not Prefix_Type.Index_Types.Is_Empty then
            Resolve_Type (UString_Value (Prefix_Type.Index_Types (Prefix_Type.Index_Types.First_Index)), Type_Env)
         else Resolve_Type ("integer", Type_Env));
      Base_Index_Type : constant GM.Type_Descriptor :=
        Expr_Type (Strip_Conversion (Index_Expr), Var_Types, Type_Env, Functions);
      Low_Text        : constant String := Format_Int (Range_Interval (Index_Type).Low);
      High_Text       : constant String := Format_Int (Range_Interval (Index_Type).High);
   begin
      Result.Append
        (FT.To_UString
           ("array '" & Prefix_Name & "' has index range " & UString_Value (Index_Type.Name)
            & " (" & Low_Text & " .. " & High_Text & ")."));
      Result.Append
        (FT.To_UString
           ("index expression '" & Source_Text_For_Expr (Index_Expr) & "' has type "
            & UString_Value (Base_Index_Type.Name)
            & ", with range"
            & ASCII.LF
            & Interval_Display (Range_Interval (Base_Index_Type), Base_Index_Type)
            & "."));
      Result.Append
        (FT.To_UString
           ("static analysis cannot establish that the index is within"
            & ASCII.LF
            & "[" & Low_Text & " .. " & High_Text & "] on all execution paths."));
      Result.Append (FT.To_UString ("rule: D27 Rule 2 (Provable Index Safety)"));
      Result.Append
        (FT.To_UString
           ("per spec/02-restrictions.md section 2.8.2 paragraph 131:"
            & ASCII.LF
            & """The index expression in an indexed_component shall be provably"
            & ASCII.LF
            & "within the array object's index bounds at compile time."""));
      Result.Append
        (FT.To_UString
           ("per spec/02-restrictions.md section 2.8.2 paragraph 132:"
            & ASCII.LF
            & """If neither condition holds, the program is nonconforming and"
            & ASCII.LF
            & "the implementation shall reject it with a diagnostic identifying"
            & ASCII.LF
            & "the indexed_component and the unresolvable bound relationship."""));
      return Result;
   end Index_Notes;

   function Index_Suggestions
     (Array_Name   : String;
      Prefix_Type  : GM.Type_Descriptor;
      Index_Expr   : GM.Expr_Access;
      Type_Env     : Type_Maps.Map) return FT.UString_Vectors.Vector
   is
      Result     : FT.UString_Vectors.Vector;
      Index_Type : GM.Type_Descriptor;
      Bounds     : Interval;
      Index_Text : constant String := Source_Text_For_Expr (Strip_Conversion (Index_Expr));
      Full_Text  : constant String := Source_Text_For_Expr (Index_Expr);
   begin
      if Prefix_Type.Index_Types.Is_Empty then
         return Result;
      end if;
      Index_Type := Resolve_Type (UString_Value (Prefix_Type.Index_Types (Prefix_Type.Index_Types.First_Index)), Type_Env);
      Bounds := Range_Interval (Index_Type);
      Result.Append
        (FT.To_UString
           ("add a bounds check before indexing:"
            & ASCII.LF
            & "if "
            & Index_Text
            & " >= "
            & Format_Int (Bounds.Low)
            & " and then "
            & Index_Text
            & " <= "
            & Format_Int (Bounds.High)
            & " then"
            & ASCII.LF
            & "   return "
            & Array_Name
            & " ("
            & Full_Text
            & ");"
            & ASCII.LF
            & "end if;"));
      return Result;
   exception
      when others =>
         --  when-others-ok: diagnostic suggestions are best-effort and must not mask primary errors.
         return Result;
   end Index_Suggestions;

   function Division_Notes
     (Expr      : GM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Functions : Function_Maps.Map) return FT.UString_Vectors.Vector
   is
      Result   : FT.UString_Vectors.Vector;
      Rhs      : constant GM.Expr_Access := Expr.Right;
      Expr_Text : constant String := Source_Text_For_Expr (Rhs);
      Info     : constant GM.Type_Descriptor := Expr_Type (Rhs, Var_Types, Type_Env, Functions);
      Bounds   : constant Interval := Range_Interval (Info);
   begin
      Result.Append
        (FT.To_UString
           ("right operand '"
            & Expr_Text
            & "' has type "
            & UString_Value (Info.Name)
            & " (range "
            & Format_Int (Bounds.Low)
            & " .. "
            & Format_Int (Bounds.High)
            & "),"
            & ASCII.LF
            & "which includes zero."));
      Result.Append
        (FT.To_UString
           ("no preceding conditional or subtype constraint establishes"
            & ASCII.LF
            & Expr_Text
            & " /= 0 on all paths reaching this division."));
      Result.Append (FT.To_UString ("rule: D27 Rule 3 (Division by Provably Nonzero Divisor)"));
      Result.Append
        (FT.To_UString
           ("per spec/02-restrictions.md section 2.8.3 paragraph 133:"
            & ASCII.LF
            & """The right operand of the operators /, mod, and rem shall be"
            & ASCII.LF
            & "provably nonzero at compile time."""));
      Result.Append
        (FT.To_UString
           ("per spec/02-restrictions.md section 2.8.3 paragraph 134:"
            & ASCII.LF
            & """If none of the conditions in paragraph 133 holds, the program"
            & ASCII.LF
            & "is nonconforming and a conforming implementation shall reject"
            & ASCII.LF
            & "the expression with a diagnostic."""));
      return Result;
   end Division_Notes;

   function Division_Suggestions
     (Expr : GM.Expr_Access) return FT.UString_Vectors.Vector
   is
      Result   : FT.UString_Vectors.Vector;
      Rhs_Text : constant String := Source_Text_For_Expr (Expr.Right);
      Expr_Text : constant String := Source_Text_For_Expr (Expr);
   begin
      Result.Append
        (FT.To_UString
           ("add a guard before the division:"
            & ASCII.LF
            & "if "
            & Rhs_Text
            & " /= 0 then"
            & ASCII.LF
            & "   return "
            & Expr_Text
            & ";"
            & ASCII.LF
            & "else"
            & ASCII.LF
            & "   return 0;  -- or handle the zero case"
            & ASCII.LF
            & "end if;"));
      Result.Append
        (FT.To_UString
           ("or use a positive subtype that excludes zero:"
            & ASCII.LF
            & "type Positive_Value is range 1 .. 100;"));
      return Result;
   end Division_Suggestions;

   function Null_Dereference_Notes
     (Expr      : GM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Functions : Function_Maps.Map) return FT.UString_Vectors.Vector
   is
      Result   : FT.UString_Vectors.Vector;
      Info     : constant GM.Type_Descriptor := Expr_Type (Expr, Var_Types, Type_Env, Functions);
   begin
      Result.Append
        (FT.To_UString
           (Source_Text_For_Expr (Expr)
            & " is of type "
            & UString_Value (Info.Name)
            & ", which is a nullable reference."));
      Result.Append
        (FT.To_UString
           ("no null check precedes this dereference on all paths reaching"
            & ASCII.LF
            & "this program point."));
      Result.Append (FT.To_UString ("rule: D27 Rule 4 (Not-Null Dereference)"));
      Result.Append
        (FT.To_UString
           ("per spec/02-restrictions.md section 2.8.4 paragraph 136:"
            & ASCII.LF
            & """Dereference of a reference value shall require the reference subtype"
            & ASCII.LF
            & "to be not null. A conforming implementation shall reject any"
            & ASCII.LF
            & "dereference where the reference subtype at the point of dereference"
            & ASCII.LF
            & "does not exclude null."""));
      return Result;
   end Null_Dereference_Notes;

   function Null_Dereference_Suggestions
     (Prefix_Expr : GM.Expr_Access;
      Deref_Text  : String) return FT.UString_Vectors.Vector
   is
      Result : FT.UString_Vectors.Vector;
   begin
      pragma Unreferenced (Deref_Text);
      Result.Append
        (FT.To_UString
           ("use a ""not null"" reference subtype, or add an explicit null check:"
            & ASCII.LF
            & "if "
            & Source_Text_For_Expr (Prefix_Expr)
            & " /= null then"
            & ASCII.LF
            & "   -- dereference "
            & Source_Text_For_Expr (Prefix_Expr)
            & " here"
            & ASCII.LF
            & "end if;"));
      return Result;
   end Null_Dereference_Suggestions;

   function Owner_Write_Conflict
     (Name    : String;
      Current : State;
      Span    : FT.Source_Span) return MD.Diagnostic is
   begin
      if Freeze_Count (Current, Name, Role_Borrow) > 0 then
         return
           Ownership_Diagnostic
             ("borrow_conflict",
              Span,
              "lender '" & Name & "' is frozen by an active mutable borrow",
              "reads, writes, and moves of the lender are forbidden while the borrow is active.");
      elsif Freeze_Count (Current, Name, Role_Observe) > 0 then
         return
           Ownership_Diagnostic
             ("observe_mutation",
              Span,
              "source '" & Name & "' is frozen by an active observe",
              "writes and moves of the observed source are forbidden while an observer is active.");
      end if;
      return Null_Diagnostic;
   end Owner_Write_Conflict;

   function Owner_Read_Conflict
     (Name    : String;
      Current : State;
      Span    : FT.Source_Span) return MD.Diagnostic is
   begin
      if Freeze_Count (Current, Name, Role_Borrow) > 0 then
         return
           Ownership_Diagnostic
             ("borrow_conflict",
              Span,
              "lender '" & Name & "' is frozen by an active mutable borrow",
              "reads, writes, and moves of the lender are forbidden while the borrow is active.");
      end if;
      return Null_Diagnostic;
   end Owner_Read_Conflict;

   function Observer_Write_Conflict
     (Name : String;
      Span : FT.Source_Span) return MD.Diagnostic is
   begin
      return
        Ownership_Diagnostic
          ("observe_mutation",
           Span,
           "observer '" & Name & "' provides read-only access",
           "writes and moves through an active observer are not permitted.");
   end Observer_Write_Conflict;

   function Owner_Move_Precondition
     (Source_Name : String;
      Target_Name : String;
      Current     : State;
      Var_Types   : Type_Maps.Map;
      Span        : FT.Source_Span;
      Require_Null_Target : Boolean := True) return MD.Diagnostic
   is
      Diag        : constant MD.Diagnostic := Owner_Write_Conflict (Source_Name, Current, Span);
      Source_Fact : Access_Fact;
      Target_Fact : Access_Fact;
   begin
      if Has_Text (Diag.Reason) then
         return Diag;
      end if;
      Source_Fact := Access_Fact_For_Name (Source_Name, Current, Var_Types);
      if Source_Fact.State = Access_Moved then
         return
           Ownership_Diagnostic
             ("double_move",
              Span,
              "use of moved value '" & Source_Name & "'",
              "the source was already moved earlier on this path.");
      elsif Source_Fact.State /= Access_NonNull then
         return
           Ownership_Diagnostic
             ("move_source_not_nonnull",
              Span,
              "move source '" & Source_Name & "' is not provably non-null",
              "static analysis determined state '" & Image (Source_Fact.State) & "' at this move site.");
      end if;
      if Require_Null_Target then
         Target_Fact := Access_Fact_For_Name (Target_Name, Current, Var_Types);
         if not Target_Is_Provably_Null (Current, Target_Name, Var_Types) then
            return
              Ownership_Diagnostic
                ("move_target_not_null",
                 Span,
                 "move target '" & Target_Name & "' is not provably null",
                 "static analysis determined state '" & Image (Target_Fact.State) & "' for the move target.");
         end if;
      end if;
      return Null_Diagnostic;
   end Owner_Move_Precondition;

   function Has_Pending_Move_For_Source
     (Current : State;
      Name    : String) return Boolean
   is
      Cursor : Pending_Move_Maps.Cursor := Current.Pending_Moves.First;
   begin
      while Pending_Move_Maps.Has_Element (Cursor) loop
         if UString_Value (Pending_Move_Maps.Element (Cursor).Source_Name) = Name then
            return True;
         end if;
         Pending_Move_Maps.Next (Cursor);
      end loop;
      return False;
   end Has_Pending_Move_For_Source;

   function Target_Is_Provably_Null
     (Current   : State;
      Name      : String;
      Var_Types : Type_Maps.Map) return Boolean
   is
      Target_Fact : constant Access_Fact := Access_Fact_For_Name (Name, Current, Var_Types);
   begin
      return
        Target_Fact.State = Access_Null
        or else
          (Target_Fact.State = Access_Moved
           and then not Has_Pending_Move_For_Source (Current, Name));
   end Target_Is_Provably_Null;

   procedure Clear_Pending_Move
     (Current : in out State;
      Name    : String) is
   begin
      if Name /= "" and then Current.Pending_Moves.Contains (Name) then
         Current.Pending_Moves.Delete (Name);
      end if;
   end Clear_Pending_Move;

   procedure Apply_Pending_Move_Refinement
     (Current : in out State;
      Name    : String;
      Truthy  : Boolean)
   is
      Pending : Pending_Move;
   begin
      if Name = "" or else not Current.Pending_Moves.Contains (Name) then
         return;
      end if;

      Pending := Current.Pending_Moves.Element (Name);
      if Truthy then
         Current.Access_Facts.Include
           (UString_Value (Pending.Source_Name),
            (State => Access_Moved, others => <>));
      else
         Current.Access_Facts.Include
           (UString_Value (Pending.Source_Name),
            Pending.Saved_Fact);
      end if;
      Current.Pending_Moves.Delete (Name);
   end Apply_Pending_Move_Refinement;

   function Eval_Access_Expr
     (Expr       : GM.Expr_Access;
      Current    : State;
      Var_Types  : Type_Maps.Map;
      Type_Env   : Type_Maps.Map;
      Functions  : Function_Maps.Map) return Access_Fact
   is
      Name : FT.UString := FT.To_UString ("");
      Role : Access_Role_Kind;
      Fact : Access_Fact;
      Info : GM.Type_Descriptor;
      Diag : MD.Diagnostic;
   begin
      if Expr = null then
         return (State => Access_MaybeNull, others => <>);
      end if;
      case Expr.Kind is
         when GM.Expr_Null =>
            return (State => Access_Null, others => <>);
         when GM.Expr_Allocator =>
            return (State => Access_NonNull, others => <>);
         when GM.Expr_Aggregate | GM.Expr_Tuple =>
            Info := Expr_Type (Expr, Var_Types, Type_Env, Functions);
            if Lower (UString_Value (Info.Kind)) = "access" then
               return (State => Access_NonNull, others => <>);
            end if;
            return (State => Access_MaybeNull, others => <>);
         when GM.Expr_Ident =>
            Name := Expr.Name;
            Role := Type_Access_Role (Resolve_Type (UString_Value (Name), Var_Types, Type_Env));
            if Role = Role_Owner or else Role = Role_General_Access or else Role = Role_Named_Constant then
               Diag := Owner_Read_Conflict (UString_Value (Name), Current, Expr.Span);
               if Has_Text (Diag.Reason) then
                  Raise_Diag (Diag);
               end if;
            end if;
            return Access_Fact_For_Name (UString_Value (Name), Current, Var_Types);
         when GM.Expr_Select =>
            if UString_Value (Expr.Selector) = "all" then
               Fact := Eval_Access_Expr (Expr.Prefix, Current, Var_Types, Type_Env, Functions);
               if Fact.State = Access_Dangling then
                  declare
                     Result : MD.Diagnostic := Null_Diagnostic;
                  begin
                     Result.Reason := FT.To_UString ("dangling_reference");
                     Result.Message := FT.To_UString ("dereference of dangling reference");
                     Result.Span := Expr.Span;
                     Result.Has_Highlight_Span := True;
                     Result.Highlight_Span := Expr.Span;
                     Result.Notes.Append (FT.To_UString ("the reference value outlives the owner scope that created it."));
                     Result.Notes.Append (FT.To_UString ("rule: D27 Rule 4 (Not-Null Dereference)"));
                     Raise_Diag (Result);
                  end;
               elsif Fact.State = Access_Moved then
                  declare
                     Result : MD.Diagnostic := Null_Diagnostic;
                  begin
                     Result.Reason := FT.To_UString ("use_after_move");
                     Result.Message := FT.To_UString ("dereference of moved reference");
                     Result.Span := Expr.Span;
                     Result.Has_Highlight_Span := True;
                     Result.Highlight_Span := Expr.Span;
                     Result.Notes.Append (FT.To_UString ("the reference value was moved before this dereference."));
                     Result.Notes.Append (FT.To_UString ("rule: D27 Rule 4 (Not-Null Dereference)"));
                     Raise_Diag (Result);
                  end;
               elsif Fact.State /= Access_NonNull then
                  declare
                     Result : MD.Diagnostic := Null_Diagnostic;
                  begin
                     Result.Reason := FT.To_UString ("null_dereference");
                     Result.Message := FT.To_UString ("dereference of possibly null reference");
                     Result.Span := Expr.Span;
                     Result.Has_Highlight_Span := True;
                     Result.Highlight_Span := Expr.Span;
                     Result.Notes := Null_Dereference_Notes (Expr.Prefix, Var_Types, Type_Env, Functions);
                     Result.Suggestions := Null_Dereference_Suggestions (Expr.Prefix, Source_Text_For_Expr (Expr));
                     Raise_Diag (Result);
                  end;
               end if;
               return Fact;
            elsif UString_Value (Expr.Selector) = "access" then
               Name := FT.To_UString (Root_Name (Expr.Prefix));
               if not Has_Text (Name) then
                  return (State => Access_NonNull, others => <>);
               end if;
               return
                 (State       => Access_NonNull,
                  Has_Lender  => True,
                  Lender      => Name,
                  Alias_Kind  => Role_Observe,
                  Initialized => False);
            end if;
            if Expr.Prefix /= null
              and then Expr.Prefix.Kind = GM.Expr_Select
              and then UString_Value (Expr.Prefix.Selector) = "all"
            then
               Fact := Eval_Access_Expr (Expr.Prefix, Current, Var_Types, Type_Env, Functions);
               pragma Unreferenced (Fact);
            end if;
            Info := Expr_Type (Expr, Var_Types, Type_Env, Functions);
            if Lower (UString_Value (Info.Kind)) = "access" then
               if Info.Not_Null then
                  return (State => Access_NonNull, others => <>);
               end if;
               return (State => Access_MaybeNull, others => <>);
            end if;
            return (State => Access_NonNull, others => <>);
         when GM.Expr_Conversion =>
            return Eval_Access_Expr (Expr.Inner, Current, Var_Types, Type_Env, Functions);
         when GM.Expr_Call =>
            Info := Expr_Type (Expr, Var_Types, Type_Env, Functions);
            if Lower (UString_Value (Info.Kind)) = "access" then
               if Info.Not_Null then
                  return (State => Access_NonNull, others => <>);
               end if;
            end if;
            return (State => Access_MaybeNull, others => <>);
         when GM.Expr_Unknown
            | GM.Expr_Int
            | GM.Expr_Real
            | GM.Expr_String
            | GM.Expr_Bool
            | GM.Expr_Enum_Literal
            | GM.Expr_Resolved_Index
            | GM.Expr_Array_Literal
            | GM.Expr_Annotated
            | GM.Expr_Unary
            | GM.Expr_Binary =>
            Info := Expr_Type (Expr, Var_Types, Type_Env, Functions);
            if Lower (UString_Value (Info.Kind)) = "access"
              and then Info.Not_Null
            then
               return (State => Access_NonNull, others => <>);
            end if;
            return (State => Access_MaybeNull, others => <>);
      end case;
   end Eval_Access_Expr;

   procedure Ensure_Access_Safe
     (Expr       : GM.Expr_Access;
      Span       : FT.Source_Span;
      Current    : State;
      Var_Types  : Type_Maps.Map;
      Type_Env   : Type_Maps.Map;
      Functions  : Function_Maps.Map) is
      Fact : Access_Fact;
   begin
      Fact := Eval_Access_Expr (Expr, Current, Var_Types, Type_Env, Functions);
      if Fact.State = Access_Dangling then
         declare
            Result : MD.Diagnostic := Null_Diagnostic;
         begin
            Result.Reason := FT.To_UString ("dangling_reference");
            Result.Message := FT.To_UString ("dereference of dangling reference");
            Result.Span := Span;
            Result.Has_Highlight_Span := True;
            Result.Highlight_Span := Span;
            Result.Notes.Append (FT.To_UString ("the reference value outlives the owner scope that created it."));
            Result.Notes.Append (FT.To_UString ("rule: D27 Rule 4 (Not-Null Dereference)"));
            Raise_Diag (Result);
         end;
      elsif Fact.State = Access_Moved then
         declare
            Result : MD.Diagnostic := Null_Diagnostic;
         begin
            Result.Reason := FT.To_UString ("use_after_move");
            Result.Message := FT.To_UString ("dereference of moved reference");
            Result.Span := Span;
            Result.Has_Highlight_Span := True;
            Result.Highlight_Span := Span;
            Result.Notes.Append (FT.To_UString ("the reference value was moved before this dereference."));
            Result.Notes.Append (FT.To_UString ("rule: D27 Rule 4 (Not-Null Dereference)"));
            Raise_Diag (Result);
         end;
      elsif Fact.State /= Access_NonNull then
         declare
            Result : MD.Diagnostic := Null_Diagnostic;
         begin
            Result.Reason := FT.To_UString ("null_dereference");
            Result.Message := FT.To_UString ("dereference of possibly null reference");
            Result.Span := Span;
            Result.Has_Highlight_Span := True;
            Result.Highlight_Span := Span;
            Result.Notes := Null_Dereference_Notes (Expr, Var_Types, Type_Env, Functions);
            Result.Suggestions := Null_Dereference_Suggestions (Expr, Source_Text_For_Expr (Expr));
            Raise_Diag (Result);
         end;
      end if;
   end Ensure_Access_Safe;

   function Eval_Index_Expr
     (Expr       : GM.Expr_Access;
      Current    : State;
      Var_Types  : Type_Maps.Map;
      Type_Env   : Type_Maps.Map;
      Functions  : Function_Maps.Map) return Interval
   is
      Prefix_Type : constant GM.Type_Descriptor := Expr_Type (Expr.Prefix, Var_Types, Type_Env, Functions);
      Bounds      : Interval;
      Value       : Interval;
      Prefix_Name : FT.UString := FT.To_UString ("");
      Prefix_Kind : constant String := Lower (UString_Value (Prefix_Type.Kind));
   begin
      if Prefix_Kind /= "array" and then not Is_String_Type (Prefix_Type) then
         declare
            Result : MD.Diagnostic := Null_Diagnostic;
         begin
            Result.Reason := FT.To_UString ("index_out_of_bounds");
            Result.Message := FT.To_UString ("indexed object is not an array");
            Result.Span := Expr.Span;
            Raise_Diag (Result);
         end;
      end if;
      if Is_String_Type (Prefix_Type) then
         if not Prefix_Type.Has_Length_Bound then
            declare
               Result : MD.Diagnostic := Null_Diagnostic;
            begin
               Result.Reason := FT.To_UString ("index_out_of_bounds");
               Result.Message := FT.To_UString ("index expression not provably within string bounds");
               Result.Span := Expr.Span;
               Result.Has_Highlight_Span := True;
               Result.Highlight_Span := Expr.Span;
               Result.Notes.Append
                 (FT.To_UString
                    ("string indexing and slicing are only proved for bounded strings in the current MIR analysis."));
               Raise_Diag (Result);
            end;
         end if;
         Bounds := String_Index_Bounds (Prefix_Type);
         for Index in Expr.Indices.First_Index .. Expr.Indices.Last_Index loop
            Value := Eval_Int_Expr (Strip_Conversion (Expr.Indices (Index)), Current, Var_Types, Type_Env, Functions);
            if not Interval_Contains (Bounds, Value) then
               declare
                  Result : MD.Diagnostic := Null_Diagnostic;
               begin
                  Result.Reason := FT.To_UString ("index_out_of_bounds");
                  Result.Message := FT.To_UString ("index expression not provably within string bounds");
                  Result.Span := Expr.Span;
                  Result.Has_Highlight_Span := True;
                  Result.Highlight_Span := Expr.Span;
                  Result.Notes.Append
                    (FT.To_UString
                       ("bounded string index range is [1 .. "
                        & Format_Int (Bounds.High)
                        & "]."));
                  Result.Notes.Append
                    (FT.To_UString
                       ("index expression '"
                        & Source_Text_For_Expr (Expr.Indices (Index))
                        & "' has range"
                        & ASCII.LF
                        & Interval_Display
                            (Value,
                             Expr_Type
                               (Strip_Conversion (Expr.Indices (Index)),
                                Var_Types,
                                Type_Env,
                                Functions))
                        & "."));
                  Raise_Diag (Result);
               end;
            end if;
         end loop;
         return (Low => INT64_LOW, High => INT64_HIGH, Excludes_Zero => False);
      end if;
      if Prefix_Type.Growable then
         if Prefix_Type.Has_Component_Type then
            return Range_Interval (Resolve_Type (UString_Value (Prefix_Type.Component_Type), Type_Env));
         end if;
         return (Low => INT64_LOW, High => INT64_HIGH, Excludes_Zero => False);
      elsif Prefix_Type.Index_Types.Is_Empty then
         declare
            Result : MD.Diagnostic := Null_Diagnostic;
         begin
            Result.Reason := FT.To_UString ("index_out_of_bounds");
            Result.Message := FT.To_UString ("indexed object is not an array");
            Result.Span := Expr.Span;
            Raise_Diag (Result);
         end;
      end if;
      if Prefix_Type.Unconstrained then
         Prefix_Name := FT.To_UString
           (if Expr.Prefix /= null and then (Expr.Prefix.Kind = GM.Expr_Ident or else Expr.Prefix.Kind = GM.Expr_Select)
            then Flatten_Name (Expr.Prefix)
            else Source_Text_For_Expr (Expr.Prefix));
         declare
            Result : MD.Diagnostic := Null_Diagnostic;
         begin
            Result.Reason := FT.To_UString ("index_out_of_bounds");
            Result.Message := FT.To_UString ("index expression not provably within array bounds");
            Result.Span := Expr.Span;
            Result.Has_Highlight_Span := True;
            Result.Highlight_Span := Expr.Span;
            Result.Notes := Index_Notes (Expr, Prefix_Type, Expr.Indices (Expr.Indices.First_Index), Var_Types, Type_Env, Functions);
            Result.Suggestions := Index_Suggestions (UString_Value (Prefix_Name), Prefix_Type, Expr.Indices (Expr.Indices.First_Index), Type_Env);
            Raise_Diag (Result);
         end;
      end if;
      for Index in Expr.Indices.First_Index .. Expr.Indices.Last_Index loop
         declare
            Index_Type : constant GM.Type_Descriptor :=
              Resolve_Type (UString_Value (Prefix_Type.Index_Types (Prefix_Type.Index_Types.First_Index + (Index - Expr.Indices.First_Index))), Type_Env);
         begin
            Value := Eval_Int_Expr (Strip_Conversion (Expr.Indices (Index)), Current, Var_Types, Type_Env, Functions);
            Bounds := Range_Interval (Index_Type);
            if not Interval_Contains (Bounds, Value) then
               Prefix_Name := FT.To_UString
                 (if Expr.Prefix /= null and then (Expr.Prefix.Kind = GM.Expr_Ident or else Expr.Prefix.Kind = GM.Expr_Select)
                  then Flatten_Name (Expr.Prefix)
                  else Source_Text_For_Expr (Expr.Prefix));
               declare
                  Result : MD.Diagnostic := Null_Diagnostic;
               begin
                  Result.Reason := FT.To_UString ("index_out_of_bounds");
                  Result.Message := FT.To_UString ("index expression not provably within array bounds");
                  Result.Span := Expr.Span;
                  Result.Has_Highlight_Span := True;
                  Result.Highlight_Span := Expr.Span;
                  Result.Notes := Index_Notes (Expr, Prefix_Type, Expr.Indices (Index), Var_Types, Type_Env, Functions);
                  Result.Suggestions := Index_Suggestions (UString_Value (Prefix_Name), Prefix_Type, Expr.Indices (Index), Type_Env);
                  Raise_Diag (Result);
               end;
            end if;
         end;
      end loop;
      if Prefix_Type.Has_Component_Type then
         return Range_Interval (Resolve_Type (UString_Value (Prefix_Type.Component_Type), Type_Env));
      end if;
      return (Low => INT64_LOW, High => INT64_HIGH, Excludes_Zero => False);
   end Eval_Index_Expr;

   function Eval_Float_Expr
     (Expr       : GM.Expr_Access;
      Current    : State;
      Var_Types  : Type_Maps.Map;
      Type_Env   : Type_Maps.Map;
      Functions  : Function_Maps.Map) return Float_Interval
   is
      function Numeric_As_Float
        (Item : GM.Expr_Access) return Float_Interval;

      function Is_Zero
        (Value : Float_Interval) return Boolean is
      begin
         return
           Value.Initialized
           and then not Value.May_Be_NaN
           and then not Value.May_Be_Infinite
           and then Value.Low = 0.0
           and then Value.High = 0.0;
      end Is_Zero;

      function Bounds_Only
        (Info : GM.Type_Descriptor) return Float_Interval is
         Result : Float_Interval := Float_Interval_For (Info);
      begin
         Result.Initialized := True;
         return Result;
      end Bounds_Only;

      function Multiply_Intervals
        (Left, Right : Float_Interval) return Float_Interval
      is
         Values : array (1 .. 4) of Real_Value;
         Result : Float_Interval;
      begin
         Values (1) := Left.Low * Right.Low;
         Values (2) := Left.Low * Right.High;
         Values (3) := Left.High * Right.Low;
         Values (4) := Left.High * Right.High;
         Result.Low := Real_Value'Min (Real_Value'Min (Values (1), Values (2)), Real_Value'Min (Values (3), Values (4)));
         Result.High := Real_Value'Max (Real_Value'Max (Values (1), Values (2)), Real_Value'Max (Values (3), Values (4)));
         Result.Initialized := Left.Initialized and then Right.Initialized;
         Result.May_Be_NaN := Left.May_Be_NaN or else Right.May_Be_NaN;
         Result.May_Be_Infinite :=
           Left.May_Be_Infinite
           or else Right.May_Be_Infinite
           or else Float_Max_Abs (Left) * Float_Max_Abs (Right) > FLOAT_FINITE_LIMIT;
         Result.Excludes_Zero := Left.Excludes_Zero and then Right.Excludes_Zero;
         return Result;
      end Multiply_Intervals;

      function Divide_Intervals
        (Item : GM.Expr_Access;
         Left, Right : Float_Interval) return Float_Interval
      is
         Values : array (1 .. 4) of Real_Value;
         Result : Float_Interval;
         Min_Divisor : constant Real_Value := Float_Min_Abs (Right);
         Overflow_Possible : constant Boolean :=
           Min_Divisor > 0.0
           and then Min_Divisor < 1.0
           and then Float_Max_Abs (Left) > FLOAT_FINITE_LIMIT * Min_Divisor;
         Diag : MD.Diagnostic := Null_Diagnostic;
      begin
         if Float_May_Contain_Zero (Right) then
            if Is_Zero (Left) and then Is_Zero (Right) then
               return
                 (Low             => 0.0,
                  High            => 0.0,
                  Initialized     => Left.Initialized and then Right.Initialized,
                  May_Be_NaN      => True,
                  May_Be_Infinite => False,
                  Excludes_Zero   => False);
            end if;
            Diag.Reason := FT.To_UString ("fp_division_by_zero");
            Diag.Message := FT.To_UString ("floating divisor is not provably nonzero");
            Diag.Span := Highlight_Span (Item);
            Diag.Has_Highlight_Span := True;
            Diag.Highlight_Span := Item.Right.Span;
            Diag.Notes.Append (FT.To_UString ("division by a value that may be 0.0 can produce infinity or NaN."));
            Raise_Diag (Diag);
         end if;
         if Overflow_Possible then
            return
              (Low             => -FLOAT_FINITE_LIMIT,
               High            => FLOAT_FINITE_LIMIT,
               Initialized     => Left.Initialized and then Right.Initialized,
               May_Be_NaN      => Left.May_Be_NaN or else Right.May_Be_NaN,
               May_Be_Infinite => True,
               Excludes_Zero   => Left.Excludes_Zero);
         end if;
         Values (1) := Left.Low / Right.Low;
         Values (2) := Left.Low / Right.High;
         Values (3) := Left.High / Right.Low;
         Values (4) := Left.High / Right.High;
         Result.Low := Real_Value'Min (Real_Value'Min (Values (1), Values (2)), Real_Value'Min (Values (3), Values (4)));
         Result.High := Real_Value'Max (Real_Value'Max (Values (1), Values (2)), Real_Value'Max (Values (3), Values (4)));
         Result.Initialized := Left.Initialized and then Right.Initialized;
         Result.May_Be_NaN := Left.May_Be_NaN or else Right.May_Be_NaN;
         Result.May_Be_Infinite :=
           Left.May_Be_Infinite
           or else Right.May_Be_Infinite
           or else Overflow_Possible;
         Result.Excludes_Zero := Left.Excludes_Zero;
         return Result;
      end Divide_Intervals;

      function Try_Convex_Combination
        (Item    : GM.Expr_Access;
         Result  : out Float_Interval) return Boolean
      is
         function Complement_Of
           (Candidate, Weight : GM.Expr_Access) return Boolean is
         begin
            return
              Candidate /= null
              and then Candidate.Kind = GM.Expr_Binary
              and then UString_Value (Candidate.Operator) = "-"
              and then Candidate.Left /= null
              and then Has_Real_Constant (Candidate.Left, Current, Var_Types, Type_Env)
              and then Constant_Real_Value (Candidate.Left, Current, Var_Types, Type_Env) = 1.0
              and then Source_Text_For_Expr (Candidate.Right) = Source_Text_For_Expr (Weight);
         end Complement_Of;

         function Extract_Product
           (Term      : GM.Expr_Access;
            Weight    : out GM.Expr_Access;
            Component : out GM.Expr_Access) return Boolean
         is
            Left_Float  : Float_Interval;
            Right_Float : Float_Interval;
         begin
            if Term = null or else Term.Kind /= GM.Expr_Binary or else UString_Value (Term.Operator) /= "*" then
               return False;
            end if;
            Left_Float := Numeric_As_Float (Term.Left);
            if Left_Float.Initialized
              and then not Left_Float.May_Be_NaN
              and then not Left_Float.May_Be_Infinite
              and then 0.0 <= Left_Float.Low
              and then Left_Float.High <= 1.0
            then
               Weight := Term.Left;
               Component := Term.Right;
               return True;
            end if;
            Right_Float := Numeric_As_Float (Term.Right);
            if Right_Float.Initialized
              and then not Right_Float.May_Be_NaN
              and then not Right_Float.May_Be_Infinite
              and then 0.0 <= Right_Float.Low
              and then Right_Float.High <= 1.0
            then
               Weight := Term.Right;
               Component := Term.Left;
               return True;
            end if;
            return False;
         end Extract_Product;

         W1, W2 : GM.Expr_Access := null;
         V1, V2 : GM.Expr_Access := null;
         I1, I2 : Float_Interval;
      begin
         if Item = null or else Item.Kind /= GM.Expr_Binary or else UString_Value (Item.Operator) /= "+" then
            return False;
         end if;
         if not Extract_Product (Item.Left, W1, V1)
           or else not Extract_Product (Item.Right, W2, V2)
         then
            return False;
         end if;
         if not (Complement_Of (W1, W2) or else Complement_Of (W2, W1)) then
            return False;
         end if;
         I1 := Numeric_As_Float (V1);
         I2 := Numeric_As_Float (V2);
         Result :=
           (Low             => Real_Value'Min (I1.Low, I2.Low),
            High            => Real_Value'Max (I1.High, I2.High),
            Initialized     => I1.Initialized and then I2.Initialized,
            May_Be_NaN      => I1.May_Be_NaN or else I2.May_Be_NaN,
            May_Be_Infinite => I1.May_Be_Infinite or else I2.May_Be_Infinite,
            Excludes_Zero   => I1.Excludes_Zero and then I2.Excludes_Zero);
         return True;
      end Try_Convex_Combination;

      function Try_Interpolation
        (Item   : GM.Expr_Access;
         Result : out Float_Interval) return Boolean
      is
         T_Expr   : GM.Expr_Access := null;
         A_Expr   : GM.Expr_Access := null;
         B_Expr   : GM.Expr_Access := null;
         Weight   : Float_Interval;
         A_Int    : Float_Interval;
         B_Int    : Float_Interval;
      begin
         if Item = null or else Item.Kind /= GM.Expr_Binary or else UString_Value (Item.Operator) /= "+" then
            return False;
         end if;
         if Item.Right /= null
           and then Item.Right.Kind = GM.Expr_Binary
           and then UString_Value (Item.Right.Operator) = "*"
           and then Item.Right.Right /= null
           and then Item.Right.Right.Kind = GM.Expr_Binary
           and then UString_Value (Item.Right.Right.Operator) = "-"
           and then Source_Text_For_Expr (Item.Left) = Source_Text_For_Expr (Item.Right.Right.Right)
         then
            A_Expr := Item.Left;
            T_Expr := Item.Right.Left;
            B_Expr := Item.Right.Right.Left;
         else
            return False;
         end if;
         Weight := Numeric_As_Float (T_Expr);
         if Weight.May_Be_NaN or else Weight.May_Be_Infinite or else Weight.Low < 0.0 or else Weight.High > 1.0 then
            return False;
         end if;
         A_Int := Numeric_As_Float (A_Expr);
         B_Int := Numeric_As_Float (B_Expr);
         Result :=
           (Low             => Real_Value'Min (A_Int.Low, B_Int.Low),
            High            => Real_Value'Max (A_Int.High, B_Int.High),
            Initialized     => A_Int.Initialized and then B_Int.Initialized,
            May_Be_NaN      => A_Int.May_Be_NaN or else B_Int.May_Be_NaN,
            May_Be_Infinite => A_Int.May_Be_Infinite or else B_Int.May_Be_Infinite,
            Excludes_Zero   => A_Int.Excludes_Zero and then B_Int.Excludes_Zero);
         return True;
      end Try_Interpolation;

      function Numeric_As_Float
        (Item : GM.Expr_Access) return Float_Interval
      is
         Info : constant GM.Type_Descriptor := Expr_Type (Item, Var_Types, Type_Env, Functions);
      begin
         if Is_Float_Type (Info) then
            return Eval_Float_Expr (Item, Current, Var_Types, Type_Env, Functions);
         end if;
         declare
            Int_Value : constant Interval := Eval_Int_Expr (Item, Current, Var_Types, Type_Env, Functions);
         begin
            return
              (Low             => Real_Value (Int_Value.Low),
               High            => Real_Value (Int_Value.High),
               Initialized     => True,
               May_Be_NaN      => False,
               May_Be_Infinite => False,
               Excludes_Zero   => Int_Value.Excludes_Zero);
         end;
      end Numeric_As_Float;

      Left   : Float_Interval;
      Right  : Float_Interval;
      Inner  : Float_Interval;
      Name   : FT.UString := FT.To_UString ("");
      Prefix : GM.Type_Descriptor;
      Result : Float_Interval;
   begin
      if Expr = null then
         declare
            Diag : MD.Diagnostic := Null_Diagnostic;
         begin
            Diag.Reason := FT.To_UString ("fp_overflow_at_narrowing");
            Diag.Message := FT.To_UString ("missing floating expression");
            Raise_Diag (Diag);
         end;
      end if;

      case Expr.Kind is
         when GM.Expr_Real =>
            declare
               Value : constant Real_Value := Parse_Real (UString_Value (Expr.Text));
            begin
               return
                 (Low             => Value,
                  High            => Value,
                  Initialized     => True,
                  May_Be_NaN      => False,
                  May_Be_Infinite => False,
                  Excludes_Zero   => Value /= 0.0);
            end;
         when GM.Expr_Int =>
            return
              (Low             => Real_Value (Expr.Int_Value),
               High            => Real_Value (Expr.Int_Value),
               Initialized     => True,
               May_Be_NaN      => False,
               May_Be_Infinite => False,
               Excludes_Zero   => Expr.Int_Value /= 0);
         when GM.Expr_Bool =>
            return
              (Low             => (if Expr.Bool_Value then 1.0 else 0.0),
               High            => (if Expr.Bool_Value then 1.0 else 0.0),
               Initialized     => True,
               May_Be_NaN      => False,
               May_Be_Infinite => False,
               Excludes_Zero   => Expr.Bool_Value);
         when GM.Expr_Ident =>
            Name := Expr.Name;
            if Current.Float_Facts.Contains (UString_Value (Name)) then
               return Current.Float_Facts.Element (UString_Value (Name));
            elsif Var_Types.Contains (UString_Value (Name)) then
               return Bounds_Only (Var_Types.Element (UString_Value (Name)));
            end if;
         when GM.Expr_Select =>
            if UString_Value (Expr.Selector) = "all" then
               Ensure_Access_Safe (Expr.Prefix, Expr.Span, Current, Var_Types, Type_Env, Functions);
               return Float_Interval_For (Access_Target_Type (Expr_Type (Expr.Prefix, Var_Types, Type_Env, Functions), Type_Env));
            elsif UString_Value (Expr.Selector) = "first" or else UString_Value (Expr.Selector) = "last" then
               Prefix := Resolve_Type (Flatten_Name (Expr.Prefix), Var_Types, Type_Env);
               return Float_Interval_For (Prefix);
            end if;
            Ensure_Discriminant_Safe (Expr, Current, Var_Types, Type_Env, Functions);
            Prefix := Expr_Type (Expr.Prefix, Var_Types, Type_Env, Functions);
            if Lower (UString_Value (Prefix.Kind)) = "access" then
               Ensure_Access_Safe (Expr.Prefix, Expr.Span, Current, Var_Types, Type_Env, Functions);
               return Float_Interval_For
                 (Field_Type (Access_Target_Type (Prefix, Type_Env), UString_Value (Expr.Selector), Type_Env));
            end if;
            return Float_Interval_For (Field_Type (Prefix, UString_Value (Expr.Selector), Type_Env));
         when GM.Expr_Resolved_Index =>
            declare
               Value : constant Interval := Eval_Index_Expr (Expr, Current, Var_Types, Type_Env, Functions);
               pragma Unreferenced (Value);
               Info  : constant GM.Type_Descriptor := Expr_Type (Expr, Var_Types, Type_Env, Functions);
            begin
               return Float_Interval_For (Info);
            end;
         when GM.Expr_Conversion =>
            declare
               Target : constant GM.Type_Descriptor :=
                 Resolve_Type (UString_Value (Expr.Name), Var_Types, Type_Env);
            begin
               Inner := Numeric_As_Float (Expr.Inner);
               if Is_Float_Type (Target) then
                  Check_Float_Narrowing (Expr, Inner, Target);
               end if;
               return Inner;
            end;
         when GM.Expr_Call =>
            Name := FT.To_UString (Flatten_Name (Expr.Callee));
            if UString_Value (Name) = "float" or else UString_Value (Name) = "long_float" then
               return Numeric_As_Float (Expr.Args (Expr.Args.First_Index));
            elsif UString_Value (Name) = "long_float.copy_sign"
              and then Expr.Args.Length = 2
            then
               declare
                  Magnitude : constant Float_Interval := Numeric_As_Float (Expr.Args (Expr.Args.First_Index));
                  Sign_Arg  : constant Float_Interval := Numeric_As_Float (Expr.Args (Expr.Args.First_Index + 1));
                  Min_Mag   : constant Real_Value := Float_Min_Abs (Magnitude);
                  Max_Mag   : constant Real_Value := Float_Max_Abs (Magnitude);
               begin
                  if Sign_Arg.Excludes_Zero and then Sign_Arg.Low > 0.0 then
                     return
                       (Low             => Min_Mag,
                        High            => Max_Mag,
                        Initialized     => Magnitude.Initialized and then Sign_Arg.Initialized,
                        May_Be_NaN      => Magnitude.May_Be_NaN or else Sign_Arg.May_Be_NaN,
                        May_Be_Infinite => Magnitude.May_Be_Infinite or else Sign_Arg.May_Be_Infinite,
                        Excludes_Zero   => Min_Mag > 0.0);
                  elsif Sign_Arg.Excludes_Zero and then Sign_Arg.High < 0.0 then
                     return
                       (Low             => -Max_Mag,
                        High            => -Min_Mag,
                        Initialized     => Magnitude.Initialized and then Sign_Arg.Initialized,
                        May_Be_NaN      => Magnitude.May_Be_NaN or else Sign_Arg.May_Be_NaN,
                        May_Be_Infinite => Magnitude.May_Be_Infinite or else Sign_Arg.May_Be_Infinite,
                        Excludes_Zero   => Min_Mag > 0.0);
                  end if;
                  return
                    (Low             => -Max_Mag,
                     High            => Max_Mag,
                     Initialized     => Magnitude.Initialized and then Sign_Arg.Initialized,
                     May_Be_NaN      => Magnitude.May_Be_NaN or else Sign_Arg.May_Be_NaN,
                     May_Be_Infinite => Magnitude.May_Be_Infinite or else Sign_Arg.May_Be_Infinite,
                     Excludes_Zero   => Min_Mag > 0.0 and then Sign_Arg.Excludes_Zero);
               end;
            elsif Functions.Contains (UString_Value (Name)) then
               declare
                  Info : constant Function_Info := Functions.Element (UString_Value (Name));
               begin
                  if Info.Has_Return_Type then
                     return Float_Interval_For (Info.Return_Type);
                  end if;
               end;
            end if;
            return Float_Interval_For (Resolve_Type ("long_float", Type_Env));
         when GM.Expr_Annotated =>
            declare
               Target : constant GM.Type_Descriptor :=
                 Resolve_Type (UString_Value (Expr.Subtype_Name), Var_Types, Type_Env);
            begin
               Inner := Eval_Float_Expr (Expr.Inner, Current, Var_Types, Type_Env, Functions);
               if Is_Float_Type (Target) then
                  Check_Float_Narrowing (Expr, Inner, Target);
               end if;
               return Inner;
            end;
         when GM.Expr_Unary =>
            Inner := Numeric_As_Float (Expr.Inner);
            if UString_Value (Expr.Operator) = "-" then
               return
                 (Low             => -Inner.High,
                  High            => -Inner.Low,
                  Initialized     => Inner.Initialized,
                  May_Be_NaN      => Inner.May_Be_NaN,
                  May_Be_Infinite => Inner.May_Be_Infinite,
                  Excludes_Zero   => Inner.Excludes_Zero);
            end if;
            return Inner;
         when GM.Expr_Binary =>
            if UString_Value (Expr.Operator) = "and then" then
               return
                 (Low             => 0.0,
                  High            => 1.0,
                  Initialized     => True,
                  May_Be_NaN      => False,
                  May_Be_Infinite => False,
                  Excludes_Zero   => False);
            elsif Try_Convex_Combination (Expr, Result) or else Try_Interpolation (Expr, Result) then
               return Result;
            end if;
            Left := Numeric_As_Float (Expr.Left);
            Right := Numeric_As_Float (Expr.Right);
            if UString_Value (Expr.Operator) = "+" then
               return
                 (Low             => Left.Low + Right.Low,
                  High            => Left.High + Right.High,
                  Initialized     => Left.Initialized and then Right.Initialized,
                  May_Be_NaN      => Left.May_Be_NaN or else Right.May_Be_NaN,
                  May_Be_Infinite =>
                    Left.May_Be_Infinite
                    or else Right.May_Be_Infinite
                    or else Float_Max_Abs (Left) + Float_Max_Abs (Right) > FLOAT_FINITE_LIMIT,
                  Excludes_Zero   => Left.Excludes_Zero and then Right.Excludes_Zero);
            elsif UString_Value (Expr.Operator) = "-" then
               return
                 (Low             => Left.Low - Right.High,
                  High            => Left.High - Right.Low,
                  Initialized     => Left.Initialized and then Right.Initialized,
                  May_Be_NaN      => Left.May_Be_NaN or else Right.May_Be_NaN,
                  May_Be_Infinite =>
                    Left.May_Be_Infinite
                    or else Right.May_Be_Infinite
                    or else Float_Max_Abs (Left) + Float_Max_Abs (Right) > FLOAT_FINITE_LIMIT,
                  Excludes_Zero   => False);
            elsif UString_Value (Expr.Operator) = "*" then
               return Multiply_Intervals (Left, Right);
            elsif UString_Value (Expr.Operator) = "/" then
               return Divide_Intervals (Expr, Left, Right);
            elsif UString_Value (Expr.Operator) = "=="
              or else UString_Value (Expr.Operator) = "!="
              or else UString_Value (Expr.Operator) = "<"
              or else UString_Value (Expr.Operator) = "<="
              or else UString_Value (Expr.Operator) = ">"
              or else UString_Value (Expr.Operator) = ">="
            then
               return
                 (Low             => 0.0,
                  High            => 1.0,
                  Initialized     => True,
                  May_Be_NaN      => False,
                  May_Be_Infinite => False,
                  Excludes_Zero   => False);
            end if;
         when GM.Expr_Unknown
            | GM.Expr_String
            | GM.Expr_Enum_Literal
            | GM.Expr_Null
            | GM.Expr_Allocator
            | GM.Expr_Aggregate
            | GM.Expr_Array_Literal
            | GM.Expr_Tuple =>
            null;
      end case;

      declare
         Diag : MD.Diagnostic := Null_Diagnostic;
      begin
         Diag.Reason := FT.To_UString ("fp_unsupported_expression_at_narrowing");
         Diag.Message := FT.To_UString ("unsupported floating expression " & GM.Image (Expr.Kind) & " at narrowing");
         Diag.Span := Expr.Span;
         Raise_Diag (Diag);
      end;
   end Eval_Float_Expr;

   function While_Variant_Derivable
     (Condition : GM.Expr_Access;
      Local_Meta : Local_Maps.Map;
      Var_Types : Type_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Functions : Function_Maps.Map) return Boolean
   is
      --  Keep these recognizers in lockstep with Loop_Variant_Image in
      --  Ada_Emit.Statements. The MIR gate decides which guards are accepted;
      --  the emitter must produce the same variant shape for each accepted
      --  guard.
      function Is_Length_Select (Expr : GM.Expr_Access) return Boolean is
         Prefix_Type : GM.Type_Descriptor;
      begin
         if Expr = null or else Expr.Kind /= GM.Expr_Select then
            return False;
         elsif UString_Value (Expr.Selector) /= "length" or else Expr.Prefix = null then
            return False;
         end if;

         Prefix_Type := Expr_Type (Expr.Prefix, Var_Types, Type_Env, Functions);
         return Lower (UString_Value (Prefix_Type.Kind)) in "string" | "array";
      end Is_Length_Select;

      function Is_String_Length_Select (Expr : GM.Expr_Access) return Boolean is
         Prefix_Type : GM.Type_Descriptor;
      begin
         if not Is_Length_Select (Expr) then
            return False;
         end if;

         Prefix_Type := Expr_Type (Expr.Prefix, Var_Types, Type_Env, Functions);
         return Lower (UString_Value (Prefix_Type.Kind)) = "string";
      end Is_String_Length_Select;

      function Is_Integer_Ident (Expr : GM.Expr_Access) return Boolean is
      begin
         return
           Expr /= null
           and then Expr.Kind = GM.Expr_Ident
           and then Is_Integer_Type (Expr_Type (Expr, Var_Types, Type_Env, Functions));
      end Is_Integer_Ident;

      function Is_Integer_Operand (Expr : GM.Expr_Access) return Boolean is
      begin
         --  Keep mirrored with Loop_Variant_Image.Is_Integer_Operand.
         --  Identifier bounds are limited to constants so a descending
         --  left-side variant does not admit a moving lower bound.
         return
           Expr /= null
           and then
             (Expr.Kind = GM.Expr_Int
              or else
              (Expr.Kind = GM.Expr_Ident
               and then Is_Constant_Target (Expr, Local_Meta)
               and then Is_Integer_Type (Expr_Type (Expr, Var_Types, Type_Env, Functions))));
      end Is_Integer_Operand;

      function Is_Zero (Expr : GM.Expr_Access) return Boolean is
      begin
         return Expr /= null and then Expr.Kind = GM.Expr_Int and then Expr.Int_Value = 0;
      end Is_Zero;

      function Is_One (Expr : GM.Expr_Access) return Boolean is
      begin
         return Expr /= null and then Expr.Kind = GM.Expr_Int and then Expr.Int_Value = 1;
      end Is_One;

      function Is_Positive_Right_Bound
        (Op    : String;
         Bound : GM.Expr_Access) return Boolean is
      begin
         return
           (Op = ">" and then Is_Zero (Bound))
           or else
           (Op = ">=" and then Is_One (Bound));
      end Is_Positive_Right_Bound;

      function Is_Positive_Left_Mirror_Bound
        (Op    : String;
         Bound : GM.Expr_Access) return Boolean is
      begin
         return
           (Op = "<" and then Is_Zero (Bound))
           or else
           (Op = "<=" and then Is_One (Bound));
      end Is_Positive_Left_Mirror_Bound;
   begin
      if Condition = null or else Condition.Kind /= GM.Expr_Binary then
         return False;
      end if;

      if UString_Value (Condition.Operator) = "!=" then
         return
           (Condition.Left /= null
            and then Condition.Left.Kind /= GM.Expr_Null
            and then Condition.Right /= null
            and then Condition.Right.Kind = GM.Expr_Null
            and then Flatten_Name (Condition.Left)'Length > 0)
           or else
           (Condition.Right /= null
            and then Condition.Right.Kind /= GM.Expr_Null
            and then Condition.Left /= null
            and then Condition.Left.Kind = GM.Expr_Null
            and then Flatten_Name (Condition.Right)'Length > 0);
      elsif UString_Value (Condition.Operator) in "<" | "<=" then
         return
           (Is_Integer_Ident (Condition.Left)
            and then Is_Integer_Ident (Condition.Right))
           or else
           (Is_Positive_Left_Mirror_Bound (UString_Value (Condition.Operator), Condition.Left)
            and then
              (Is_Integer_Ident (Condition.Right)
               or else Is_String_Length_Select (Condition.Right)));
      elsif UString_Value (Condition.Operator) in ">" | ">=" then
         --  Descending integer countdowns track the left side in the emitter.
         --  The right side may be a literal or constant identifier; mutable
         --  right-side identifiers are rejected here rather than left to a
         --  downstream proof failure. Length drains stay limited to string
         --  > 0 / >= 1 because array runtime contracts do not expose
         --  strict-decrease facts yet.
         return
           (Is_Integer_Ident (Condition.Left)
            and then Is_Integer_Operand (Condition.Right))
           or else
           (Is_String_Length_Select (Condition.Left)
            and then Is_Positive_Right_Bound
              (UString_Value (Condition.Operator), Condition.Right));
      elsif UString_Value (Condition.Operator) = "==" then
         return
           (Is_Length_Select (Condition.Left)
            and then Condition.Right /= null
            and then Condition.Right.Kind = GM.Expr_Int)
           or else
           (Is_Length_Select (Condition.Right)
            and then Condition.Left /= null
            and then Condition.Left.Kind = GM.Expr_Int);
      end if;

      return False;
   end While_Variant_Derivable;

   function While_Loop_Variant_Diagnostic
     (Condition : GM.Expr_Access;
      Span      : FT.Source_Span) return MD.Diagnostic
   is
      Result : MD.Diagnostic := Null_Diagnostic;
      Focus  : constant FT.Source_Span :=
        (if Condition = null then Span else Highlight_Span (Condition));
   begin
      Result.Reason := FT.To_UString ("loop_variant_not_derivable");
      Result.Message := FT.To_UString ("current proof surface cannot derive a supported Loop_Variant from this while condition");
      Result.Span := Focus;
      Result.Has_Highlight_Span := True;
      Result.Highlight_Span := Focus;
      Result.Notes.Append
        (FT.To_UString
           ("supported while-loop proof shapes are structural `Cursor != null` traversal,"
            & " simple integer-bound `Lo < Hi` / `Lo <= Hi` conditions, literal-left"
            & " mirror forms like `0 < remaining` / `1 <= text.length`, countdown"
            & " guards like `remaining > 0`, `remaining >= 1`, `index > constant_bound`,"
            & " or `index >= constant_bound`, direct length guards like"
            & " `values.length == N`, and string length guards like"
            & " `text.length > 0` or `text.length >= 1` (strings only)."));
      Result.Notes.Append
        (FT.To_UString
           ("for `>` / `>=` two-identifier countdown guards, the right-hand bound must be a literal or constant; use `Lo < Hi` / `Lo <= Hi` for bidirectional moving bounds."));
      Result.Notes.Append
        (FT.To_UString
           ("rewrite the loop to match one of those forms, or use a different construct whose termination proof does not depend on an emitted Loop_Variant."));
      return Result;
   end While_Loop_Variant_Diagnostic;

   procedure Check_Float_Narrowing
     (Expr           : GM.Expr_Access;
      Interval_Value : Float_Interval;
      Target_Type    : GM.Type_Descriptor)
   is
      Diagnostic : MD.Diagnostic := Null_Diagnostic;
   begin
      if not Interval_Value.Initialized then
         Diagnostic.Reason := FT.To_UString ("fp_uninitialized_at_narrowing");
         Diagnostic.Message := FT.To_UString ("floating expression is not provably initialized at narrowing");
         Diagnostic.Span := Expr.Span;
         Diagnostic.Has_Highlight_Span := True;
         Diagnostic.Highlight_Span := Expr.Span;
         Raise_Diag (Diagnostic);
      elsif Interval_Value.May_Be_NaN then
         Diagnostic.Reason := FT.To_UString ("nan_at_narrowing");
         Diagnostic.Message := FT.To_UString ("floating expression may be NaN at narrowing");
         Diagnostic.Span := Expr.Span;
         Diagnostic.Has_Highlight_Span := True;
         Diagnostic.Highlight_Span := Expr.Span;
         Raise_Diag (Diagnostic);
      elsif Interval_Value.May_Be_Infinite then
         Diagnostic.Reason := FT.To_UString ("infinity_at_narrowing");
         Diagnostic.Message := FT.To_UString ("floating expression may be infinite at narrowing");
         Diagnostic.Span := Expr.Span;
         Diagnostic.Has_Highlight_Span := True;
         Diagnostic.Highlight_Span := Expr.Span;
         Raise_Diag (Diagnostic);
      elsif Is_Float_Type (Target_Type)
        and then not Float_Interval_Contains (Float_Interval_For (Target_Type), Interval_Value)
      then
         Diagnostic.Reason := FT.To_UString ("fp_overflow_at_narrowing");
         Diagnostic.Message := FT.To_UString ("floating expression is not provably within target range");
         Diagnostic.Span := Expr.Span;
         Diagnostic.Has_Highlight_Span := True;
         Diagnostic.Highlight_Span := Expr.Span;
         Raise_Diag (Diagnostic);
      end if;
   end Check_Float_Narrowing;

   function Eval_Float_Expr_With_Diag
     (Expr         : GM.Expr_Access;
      Current      : State;
      Var_Types    : Type_Maps.Map;
      Type_Env     : Type_Maps.Map;
      Functions    : Function_Maps.Map;
      Target_Type  : GM.Type_Descriptor;
      Has_Diag     : out Boolean;
      Diagnostic   : out MD.Diagnostic) return Float_Interval
   is
      Interval_Value : Float_Interval;
   begin
      Interval_Value := Eval_Float_Expr (Expr, Current, Var_Types, Type_Env, Functions);
      Has_Diag := False;
      Diagnostic := Null_Diagnostic;
      Check_Float_Narrowing (Expr, Interval_Value, Target_Type);
      return Interval_Value;
   exception
      when Diagnostic_Failure =>
         Has_Diag := True;
         Diagnostic := Raised_Diagnostic;
         return Float_Interval_For (Resolve_Type ("long_float", Type_Env));
   end Eval_Float_Expr_With_Diag;

   function Numerator_Factor
     (Expr : GM.Expr_Access;
      Name : out FT.UString) return Wide_Integer
   is
      Product : Wide_Integer := 0;
   begin
      Name := FT.To_UString ("");
      if Expr = null then
         return 1;
      elsif Expr.Kind = GM.Expr_Conversion then
         return Numerator_Factor (Expr.Inner, Name);
      elsif Expr.Kind = GM.Expr_Ident then
         Name := Expr.Name;
         return 1;
      elsif Expr.Kind = GM.Expr_Binary and then UString_Value (Expr.Operator) = "*" then
         if Expr.Left /= null and then Expr.Left.Kind = GM.Expr_Conversion then
            declare
               Factor : constant Wide_Integer := Numerator_Factor (Expr.Left.Inner, Name);
            begin
               if Expr.Right /= null and then Expr.Right.Kind = GM.Expr_Int then
                  if Try_Int64_Product (Factor, Wide_Integer (Expr.Right.Int_Value), Product) then
                     return Product;
                  end if;
                  return 0;
               end if;
               return Factor;
            end;
         elsif Expr.Left /= null and then Expr.Left.Kind = GM.Expr_Ident
           and then Expr.Right /= null and then Expr.Right.Kind = GM.Expr_Int
         then
            Name := Expr.Left.Name;
            return Wide_Integer (Expr.Right.Int_Value);
         end if;
      end if;
      return 1;
   end Numerator_Factor;

   function Denominator_Var
     (Expr : GM.Expr_Access) return String is
   begin
      if Expr = null then
         return "";
      elsif Expr.Kind = GM.Expr_Conversion then
         return Denominator_Var (Expr.Inner);
      elsif Expr.Kind = GM.Expr_Ident then
         return UString_Value (Expr.Name);
      end if;
      return "";
   end Denominator_Var;

   function Division_Interval
     (Expr    : GM.Expr_Access;
      Left    : Interval;
      Right   : Interval;
      Current : State) return Interval
   is
      Numerator_Name   : FT.UString := FT.To_UString ("");
      Denominator_Name : FT.UString := FT.To_UString ("");
      Factor           : Wide_Integer;
      Bound            : Wide_Integer;
      Scaled_Bound     : Wide_Integer := 0;
      Values           : array (1 .. 8) of Wide_Integer;
      Value_Count      : Natural := 0;
      Needs_Wide_Result : Boolean := False;
      Has_Scaled_Bound : Boolean := False;
      Sampled          : Interval := (Low => INT64_LOW, High => INT64_HIGH, Excludes_Zero => False);

      procedure Add_Quotient
        (Numerator : Wide_Integer;
         Divisor   : Wide_Integer) is
      begin
         if Needs_Wide_Result then
            return;
         end if;

         if Divisor = -1 and then Numerator = INT64_LOW then
            Needs_Wide_Result := True;
            return;
         end if;

         Value_Count := Value_Count + 1;
         Values (Value_Count) := Numerator / Divisor;
      end Add_Quotient;

      procedure Add_Divisor (Divisor : Wide_Integer) is
      begin
         if Divisor = 0 or else Needs_Wide_Result then
            return;
         end if;

         --  At most four candidate divisors are sampled, each adding up to two
         --  numerator endpoints, so Values'Last must remain at least 8.
         pragma Assert (Value_Count + 2 <= Values'Last);
         Add_Quotient (Left.Low, Divisor);
         Add_Quotient (Left.High, Divisor);
      end Add_Divisor;

      procedure Refine_With_Div_Bound (Value : in out Interval) is
      begin
         if not Has_Scaled_Bound or else Right.Low <= 0 then
            return;
         end if;

         declare
            --  Div_Bounds stores one-sided facts of the form Numerator <=
            --  Denominator * K. With a positive denominator, that gives an
            --  upper bound on the quotient. It gives a lower bound only from
            --  the independent fact that the numerator is nonnegative.
            Bound_Low : constant Wide_Integer :=
              (if Left.Low >= 0 then 0 else Value.Low);
            New_Low   : constant Wide_Integer := Wide_Integer'Max (Value.Low, Bound_Low);
            New_High  : constant Wide_Integer := Wide_Integer'Min (Value.High, Scaled_Bound);
         begin
            if New_Low <= New_High then
               Value :=
                 (Low           => New_Low,
                  High          => New_High,
                  Excludes_Zero => Value.Excludes_Zero or else New_Low > 0 or else New_High < 0);
            end if;
         end;
      end Refine_With_Div_Bound;
   begin
      Factor := Numerator_Factor (Expr.Left, Numerator_Name);
      Denominator_Name := FT.To_UString (Denominator_Var (Expr.Right));
      if Has_Text (Numerator_Name) and then Has_Text (Denominator_Name) then
         declare
            Key : constant String := Pair_Key (UString_Value (Numerator_Name), UString_Value (Denominator_Name));
         begin
            if Current.Div_Bounds.Contains (Key) then
               Bound := Current.Div_Bounds.Element (Key);
               Has_Scaled_Bound :=
                 Bound > 0
                 and then Factor > 0
                 and then Try_Int64_Product (Bound, Factor, Scaled_Bound);
            end if;
         end;
      end if;
      Add_Divisor (Right.Low);
      Add_Divisor (Right.High);
      if Right.Low < 0 and then Right.High > 0 then
         if Right.Low /= -1 then
            Add_Divisor (-1);
         end if;
         if Right.High /= 1 then
            Add_Divisor (1);
         end if;
      elsif Right.Low = 0 and then Right.High > 0 then
         if Right.High /= 1 then
            Add_Divisor (1);
         end if;
      elsif Right.Low < 0 and then Right.High = 0 then
         if Right.Low /= -1 then
            Add_Divisor (-1);
         end if;
      end if;

      if Needs_Wide_Result or else Value_Count = 0 then
         Sampled := (Low => INT64_LOW, High => INT64_HIGH, Excludes_Zero => False);
      else
         declare
            Low_Value  : Wide_Integer := Values (1);
            High_Value : Wide_Integer := Values (1);
         begin
            for Index in 2 .. Value_Count loop
               Low_Value := Wide_Integer'Min (Low_Value, Values (Index));
               High_Value := Wide_Integer'Max (High_Value, Values (Index));
            end loop;
            Sampled := (Low => Low_Value, High => High_Value, Excludes_Zero => False);
         end;
      end if;

      Refine_With_Div_Bound (Sampled);
      return Sampled;
   end Division_Interval;

   function Overflow_Checked
     (Expr        : GM.Expr_Access;
      Low_Value   : Wide_Integer;
      High_Value  : Wide_Integer;
      Left, Right : Interval) return Interval
   is
      Result : constant Interval :=
        (Low           => Low_Value,
         High          => High_Value,
         Excludes_Zero => Low_Value > 0 or else High_Value < 0);
   begin
      if Low_Value < INT64_LOW or else High_Value > INT64_HIGH then
         declare
            Diag : MD.Diagnostic := Null_Diagnostic;
         begin
            Diag.Reason := FT.To_UString ("intermediate_overflow");
            Diag.Message := FT.To_UString ("intermediate overflow in integer expression");
            Diag.Span := Expr.Span;
            Diag.Has_Highlight_Span := True;
            Diag.Highlight_Span := Expr.Span;
            Diag.Notes := Overflow_Notes (Expr, Result, Left, Right);
            Raise_Diag (Diag);
         end;
      end if;
      return Result;
   end Overflow_Checked;

   function Eval_Int_Expr
     (Expr       : GM.Expr_Access;
      Current    : State;
      Var_Types  : Type_Maps.Map;
      Type_Env   : Type_Maps.Map;
      Functions  : Function_Maps.Map) return Interval
   is
      Left       : Interval;
      Right      : Interval;
      Inner      : Interval;
      Target     : GM.Type_Descriptor;
      Prefix     : GM.Type_Descriptor;
      Name       : FT.UString := FT.To_UString ("");
      Values     : array (1 .. 4) of Wide_Integer;
      Max_Mod    : Wide_Integer;
   begin
      if Expr = null then
         declare
            Diag : MD.Diagnostic := Null_Diagnostic;
         begin
            Diag.Reason := FT.To_UString ("narrowing_check_failure");
            Diag.Message := FT.To_UString ("missing numeric expression");
            Raise_Diag (Diag);
         end;
      end if;

      case Expr.Kind is
         when GM.Expr_Int =>
            declare
               Value : constant Wide_Integer := Parsed_Wide_Integer (Expr);
            begin
               return
                 (Low           => Value,
                  High          => Value,
                  Excludes_Zero => Value /= 0);
            end;
         when GM.Expr_Bool =>
            return
              (Low           => (if Expr.Bool_Value then 1 else 0),
               High          => (if Expr.Bool_Value then 1 else 0),
               Excludes_Zero => Expr.Bool_Value);
         when GM.Expr_Enum_Literal =>
            declare
               Enum_Info : constant GM.Type_Descriptor :=
                 Resolve_Type (UString_Value (Expr.Type_Name), Var_Types, Type_Env);
               Ordinal : constant Wide_Integer :=
                 Enum_Literal_Ordinal (Enum_Info, UString_Value (Expr.Name));
            begin
               return
                 (Low           => Ordinal,
                  High          => Ordinal,
                  Excludes_Zero => Ordinal /= 0);
            end;
         when GM.Expr_Null =>
            return (Low => 0, High => 0, Excludes_Zero => False);
         when GM.Expr_Ident =>
            Name := Expr.Name;
            if Current.Ranges.Contains (UString_Value (Name)) then
               return Current.Ranges.Element (UString_Value (Name));
            elsif Var_Types.Contains (UString_Value (Name)) then
               return Range_Interval (Var_Types.Element (UString_Value (Name)));
            end if;
            declare
               Diag : MD.Diagnostic := Null_Diagnostic;
            begin
               Diag.Reason := FT.To_UString ("narrowing_check_failure");
               Diag.Message := FT.To_UString ("unknown numeric identifier '" & UString_Value (Name) & "'");
               Diag.Span := Expr.Span;
               Raise_Diag (Diag);
            end;
         when GM.Expr_Select =>
            if UString_Value (Expr.Selector) = "first" or else UString_Value (Expr.Selector) = "last" then
               Prefix := Resolve_Type (Flatten_Name (Expr.Prefix), Var_Types, Type_Env);
               if Prefix.Has_Low and then Prefix.Has_High then
                  if UString_Value (Expr.Selector) = "first" then
                     return (Low => Wide_Integer (Prefix.Low), High => Wide_Integer (Prefix.Low), Excludes_Zero => Prefix.Low /= 0);
                  end if;
                  return (Low => Wide_Integer (Prefix.High), High => Wide_Integer (Prefix.High), Excludes_Zero => Prefix.High /= 0);
               end if;
               declare
                  Diag : MD.Diagnostic := Null_Diagnostic;
               begin
                  Diag.Reason := FT.To_UString ("narrowing_check_failure");
                  Diag.Message := FT.To_UString ("attribute value is not statically known");
                  Diag.Span := Expr.Span;
                  Raise_Diag (Diag);
               end;
            elsif UString_Value (Expr.Selector) = "all" then
               Ensure_Access_Safe (Expr.Prefix, Expr.Span, Current, Var_Types, Type_Env, Functions);
               return Range_Interval (Access_Target_Type (Expr_Type (Expr.Prefix, Var_Types, Type_Env, Functions), Type_Env));
            end if;
            if Expr.Prefix /= null
              and then Expr.Prefix.Kind = GM.Expr_Select
              and then UString_Value (Expr.Prefix.Selector) = "all"
            then
               Ensure_Access_Safe (Expr.Prefix.Prefix, Expr.Prefix.Span, Current, Var_Types, Type_Env, Functions);
            end if;
            Prefix := Expr_Type (Expr.Prefix, Var_Types, Type_Env, Functions);
            declare
               Prefix_Base : GM.Type_Descriptor := Prefix;
               Prefix_Kind : FT.UString;
            begin
               if Lower (UString_Value (Prefix.Kind)) = "subtype"
                 and then Prefix.Has_Base
               then
                  Prefix_Base :=
                    Resolve_Type (UString_Value (Prefix.Base), Var_Types, Type_Env);
               end if;
               Prefix_Kind := FT.To_UString (Lower (UString_Value (Prefix_Base.Kind)));
               if UString_Value (Prefix_Kind) = "record" then
                  Ensure_Discriminant_Safe (Expr, Current, Var_Types, Type_Env, Functions);
                  return Range_Interval (Field_Type (Prefix_Base, UString_Value (Expr.Selector), Type_Env));
               elsif UString_Value (Prefix_Kind) = "tuple" then
                  return Range_Interval (Field_Type (Prefix_Base, UString_Value (Expr.Selector), Type_Env));
               elsif UString_Value (Expr.Selector) = "length"
                 and then UString_Value (Prefix_Kind) in "string" | "array"
               then
                  return (Low => 0, High => INT64_HIGH, Excludes_Zero => False);
               elsif UString_Value (Prefix_Kind) = "access" then
                  Ensure_Access_Safe (Expr.Prefix, Expr.Span, Current, Var_Types, Type_Env, Functions);
                  Ensure_Discriminant_Safe (Expr, Current, Var_Types, Type_Env, Functions);
                  return Range_Interval (Field_Type (Access_Target_Type (Prefix_Base, Type_Env), UString_Value (Expr.Selector), Type_Env));
               end if;
            end;
            declare
               Diag : MD.Diagnostic := Null_Diagnostic;
            begin
               Diag.Reason := FT.To_UString ("null_dereference");
               Diag.Message := FT.To_UString ("unsupported selected component");
               Diag.Span := Expr.Span;
               Raise_Diag (Diag);
            end;
         when GM.Expr_Resolved_Index =>
            return Eval_Index_Expr (Expr, Current, Var_Types, Type_Env, Functions);
         when GM.Expr_Conversion =>
            Target := Resolve_Type (UString_Value (Expr.Name), Var_Types, Type_Env);
            if Is_Binary_Type (Target) then
               return Range_Interval (Target);
            end if;
            return Eval_Int_Expr (Expr.Inner, Current, Var_Types, Type_Env, Functions);
         when GM.Expr_Call =>
            Name := FT.To_UString (Flatten_Name (Expr.Callee));
            if Var_Types.Contains (UString_Value (Name)) then
               return Range_Interval (Var_Types.Element (UString_Value (Name)));
            elsif UString_Value (Name) = "integer" then
               return Eval_Int_Expr (Expr.Args (Expr.Args.First_Index), Current, Var_Types, Type_Env, Functions);
            end if;
            return Range_Interval (Resolve_Type ("integer", Type_Env));
         when GM.Expr_Annotated =>
            Target := Resolve_Type (UString_Value (Expr.Subtype_Name), Var_Types, Type_Env);
            if Is_Binary_Type (Target) then
               return Range_Interval (Target);
            end if;
            return Eval_Int_Expr (Expr.Inner, Current, Var_Types, Type_Env, Functions);
         when GM.Expr_Aggregate =>
            return (Low => INT64_LOW, High => INT64_HIGH, Excludes_Zero => False);
         when GM.Expr_Tuple =>
            return (Low => INT64_LOW, High => INT64_HIGH, Excludes_Zero => False);
         when GM.Expr_Allocator =>
            declare
               Diag : MD.Diagnostic := Null_Diagnostic;
            begin
               Diag.Reason := FT.To_UString ("null_dereference");
               Diag.Message := FT.To_UString ("allocator is not numeric");
               Diag.Span := Expr.Span;
               Raise_Diag (Diag);
            end;
         when GM.Expr_Unary =>
            if UString_Value (Expr.Operator) = "not"
              and then Is_Binary_Type (Expr_Type (Expr, Var_Types, Type_Env, Functions))
            then
               return Range_Interval (Expr_Type (Expr, Var_Types, Type_Env, Functions));
            end if;
            Inner := Eval_Int_Expr (Expr.Inner, Current, Var_Types, Type_Env, Functions);
            if UString_Value (Expr.Operator) = "-" then
               return Overflow_Checked (Expr, -Inner.High, -Inner.Low, Inner, Inner);
            end if;
            return Inner;
         when GM.Expr_Binary =>
            if UString_Value (Expr.Operator) in "and then" | "or else" | "and" | "or" | "xor"
              and then not Is_Binary_Type (Expr_Type (Expr, Var_Types, Type_Env, Functions))
            then
               return (Low => 0, High => 1, Excludes_Zero => False);
            end if;
            Left := Eval_Int_Expr (Expr.Left, Current, Var_Types, Type_Env, Functions);
            Right := Eval_Int_Expr (Expr.Right, Current, Var_Types, Type_Env, Functions);
            if Is_Binary_Type (Expr_Type (Expr, Var_Types, Type_Env, Functions))
              or else (UString_Value (Expr.Operator) in "<<" | ">>"
                       and then Is_Binary_Type (Expr_Type (Expr.Left, Var_Types, Type_Env, Functions)))
            then
               declare
                  Result_Type : constant GM.Type_Descriptor :=
                    (if Is_Binary_Type (Expr_Type (Expr, Var_Types, Type_Env, Functions))
                     then Expr_Type (Expr, Var_Types, Type_Env, Functions)
                     else Expr_Type (Expr.Left, Var_Types, Type_Env, Functions));
                  Shift_High  : constant Wide_Integer :=
                    Wide_Integer (Result_Type.Bit_Width - 1);
               begin
                  if UString_Value (Expr.Operator) in "/" | "mod" | "rem"
                    and then not Interval_Excludes_Zero (Right)
                  then
                     declare
                        Diag : MD.Diagnostic := Null_Diagnostic;
                     begin
                        Diag.Reason := FT.To_UString ("division_by_zero");
                        Diag.Message := FT.To_UString ("divisor not provably nonzero");
                        Diag.Span := Highlight_Span (Expr);
                        Diag.Has_Highlight_Span := True;
                        Diag.Highlight_Span := Expr.Right.Span;
                        Raise_Diag (Diag);
                     end;
                  elsif UString_Value (Expr.Operator) in "<<" | ">>"
                    and then (Right.Low < 0 or else Right.High > Shift_High)
                  then
                     declare
                        Diag : MD.Diagnostic := Null_Diagnostic;
                     begin
                        Diag.Reason := FT.To_UString ("shift_count_out_of_range");
                        Diag.Message := FT.To_UString ("shift count is not provably within operand width");
                        Diag.Span := Expr.Right.Span;
                        Diag.Has_Highlight_Span := True;
                        Diag.Highlight_Span := Expr.Right.Span;
                        Raise_Diag (Diag);
                     end;
                  end if;
                  return Range_Interval (Result_Type);
               end;
            end if;
            if UString_Value (Expr.Operator) = "+" then
               return Overflow_Checked (Expr, Left.Low + Right.Low, Left.High + Right.High, Left, Right);
            elsif UString_Value (Expr.Operator) = "-" then
               return Overflow_Checked (Expr, Left.Low - Right.High, Left.High - Right.Low, Left, Right);
            elsif UString_Value (Expr.Operator) = "*" then
               Values (1) := Left.Low * Right.Low;
               Values (2) := Left.Low * Right.High;
               Values (3) := Left.High * Right.Low;
               Values (4) := Left.High * Right.High;
               return
                 Overflow_Checked
                   (Expr,
                    Wide_Integer'Min (Wide_Integer'Min (Values (1), Values (2)), Wide_Integer'Min (Values (3), Values (4))),
                    Wide_Integer'Max (Wide_Integer'Max (Values (1), Values (2)), Wide_Integer'Max (Values (3), Values (4))),
                    Left,
                    Right);
            elsif UString_Value (Expr.Operator) = "/" or else UString_Value (Expr.Operator) = "mod" or else UString_Value (Expr.Operator) = "rem" then
               if not Interval_Excludes_Zero (Right) then
                  declare
                     Diag : MD.Diagnostic := Null_Diagnostic;
                  begin
                     Diag.Reason := FT.To_UString ("division_by_zero");
                     Diag.Message := FT.To_UString ("divisor not provably nonzero");
                     Diag.Span := Highlight_Span (Expr);
                     Diag.Has_Highlight_Span := True;
                     Diag.Highlight_Span := Expr.Right.Span;
                     Diag.Notes := Division_Notes (Expr, Var_Types, Type_Env, Functions);
                     Diag.Suggestions := Division_Suggestions (Expr);
                     Raise_Diag (Diag);
                  end;
               end if;
               if UString_Value (Expr.Operator) = "/" then
                  return Division_Interval (Expr, Left, Right, Current);
               elsif UString_Value (Expr.Operator) = "mod" then
                  Max_Mod := Wide_Integer'Max (abs Right.Low, abs Right.High) - 1;
                  return (Low => 0, High => Wide_Integer'Max (Max_Mod, 0), Excludes_Zero => False);
               end if;
               Max_Mod := Wide_Integer'Max (abs Right.Low, abs Right.High) - 1;
               return (Low => -Max_Mod, High => Max_Mod, Excludes_Zero => False);
            elsif UString_Value (Expr.Operator) = "=="
              or else UString_Value (Expr.Operator) = "!="
              or else UString_Value (Expr.Operator) = "<"
              or else UString_Value (Expr.Operator) = "<="
              or else UString_Value (Expr.Operator) = ">"
              or else UString_Value (Expr.Operator) = ">="
            then
               return (Low => 0, High => 1, Excludes_Zero => False);
            end if;
         when GM.Expr_Unknown
            | GM.Expr_Real
            | GM.Expr_String
            | GM.Expr_Array_Literal =>
            null;
      end case;

      declare
         Diag : MD.Diagnostic := Null_Diagnostic;
      begin
         Diag.Reason := FT.To_UString ("narrowing_check_failure");
         Diag.Message := FT.To_UString ("unsupported numeric expression " & GM.Image (Expr.Kind));
         Diag.Span := Expr.Span;
         Raise_Diag (Diag);
      end;
   end Eval_Int_Expr;

   function Eval_Int_Expr_With_Diag
     (Expr                    : GM.Expr_Access;
      Current                 : State;
      Var_Types               : Type_Maps.Map;
      Type_Env                : Type_Maps.Map;
      Functions               : Function_Maps.Map;
      Target_Type             : GM.Type_Descriptor;
      Suppress_Index_Convert  : Boolean;
      Has_Diagnostic          : out Boolean;
      Diagnostic              : out MD.Diagnostic) return Interval
   is
      Interval_Value : Interval;
      Target         : GM.Type_Descriptor := Target_Type;
   begin
      Interval_Value := Eval_Int_Expr (Expr, Current, Var_Types, Type_Env, Functions);
      Has_Diagnostic := False;
      Diagnostic := Null_Diagnostic;
      if Expr /= null
        and then Expr.Kind = GM.Expr_Conversion
        and then not Suppress_Index_Convert
      then
         if UString_Value (Expr.Name) /= "" then
            Target := Resolve_Type (UString_Value (Expr.Name), Var_Types, Type_Env);
         end if;
         if Is_Integer_Type (Target) and then not Interval_Contains (Range_Interval (Target), Interval_Value) then
            Has_Diagnostic := True;
            Diagnostic.Reason := FT.To_UString ("narrowing_check_failure");
            Diagnostic.Message := FT.To_UString ("explicit conversion is not provably within target range");
            Diagnostic.Span := Expr.Span;
            Diagnostic.Has_Highlight_Span := True;
            Diagnostic.Highlight_Span := Expr.Span;
            Diagnostic.Notes.Append
              (FT.To_UString ("target type '" & UString_Value (Target.Name) & "' has range " & Interval_Format (Range_Interval (Target))));
            Diagnostic.Notes.Append
              (FT.To_UString ("expression range is " & Interval_Format (Interval_Value)));
         end if;
      end if;
      return Interval_Value;
   exception
      when Diagnostic_Failure =>
         Has_Diagnostic := True;
         Diagnostic := Raised_Diagnostic;
         return (Low => INT64_LOW, High => INT64_HIGH, Excludes_Zero => False);
   end Eval_Int_Expr_With_Diag;

   procedure Apply_Comparison_Refinement
     (Current   : in out State;
      Expr      : GM.Expr_Access;
      Truthy    : Boolean;
      Var_Types : Type_Maps.Map;
      Type_Env  : Type_Maps.Map)
   is
      Left_Name  : constant String := Direct_Name (Expr.Left);
      Right_Name : constant String := Direct_Name (Expr.Right);
      Current_Interval : Interval;
      Current_Float    : Float_Interval;
      Right_Const : Wide_Integer;
      Left_Const  : Wide_Integer;
      Right_Real  : Real_Value;
      Op          : constant String := UString_Value (Expr.Operator);
      Have_Right_Const : constant Boolean := Has_Constant_Value (Expr.Right, Current, Var_Types, Type_Env);
      Have_Left_Const  : Boolean := Has_Constant_Value (Expr.Left, Current, Var_Types, Type_Env);
      Have_Right_Real  : constant Boolean := Has_Real_Constant (Expr.Right, Current, Var_Types, Type_Env);
   begin
      if Left_Name /= ""
        and then Var_Types.Contains (Left_Name)
        and then Is_Float_Type (Var_Types.Element (Left_Name))
        and then Have_Right_Real
      then
         Right_Real := Constant_Real_Value (Expr.Right, Current, Var_Types, Type_Env);
         if Current.Float_Facts.Contains (Left_Name) then
            Current_Float := Current.Float_Facts.Element (Left_Name);
         else
            Current_Float := Float_Interval_For (Var_Types.Element (Left_Name));
         end if;
         if Op = "!=" and then Truthy and then Right_Real = 0.0 then
            Current_Float.Excludes_Zero := True;
            Current.Float_Facts.Include (Left_Name, Current_Float);
            return;
         elsif Op = "==" and then Truthy then
            Current.Float_Facts.Include
              (Left_Name,
               (Low             => Right_Real,
                High            => Right_Real,
                Initialized     => True,
                May_Be_NaN      => False,
                May_Be_Infinite => False,
                Excludes_Zero   => Right_Real /= 0.0));
            return;
         elsif Op = "==" and then not Truthy and then Right_Real = 0.0 then
            Current_Float.Excludes_Zero := True;
            Current.Float_Facts.Include (Left_Name, Current_Float);
            return;
         elsif Op = "<" or else Op = "<=" or else Op = ">" or else Op = ">=" then
            if Truthy then
               if Op = "<" then
                  Current_Float.High := Real_Value'Min (Current_Float.High, Right_Real);
               elsif Op = "<=" then
                  Current_Float.High := Real_Value'Min (Current_Float.High, Right_Real);
               elsif Op = ">" then
                  Current_Float.Low := Real_Value'Max (Current_Float.Low, Right_Real);
                  if Right_Real = 0.0 then
                     Current_Float.Excludes_Zero := True;
                  end if;
               else
                  Current_Float.Low := Real_Value'Max (Current_Float.Low, Right_Real);
               end if;
            else
               if Op = "<" then
                  Current_Float.Low := Real_Value'Max (Current_Float.Low, Right_Real);
               elsif Op = "<=" then
                  Current_Float.Low := Real_Value'Max (Current_Float.Low, Right_Real);
                  if Right_Real = 0.0 then
                     Current_Float.Excludes_Zero := True;
                  end if;
               elsif Op = ">" then
                  Current_Float.High := Real_Value'Min (Current_Float.High, Right_Real);
               else
                  Current_Float.High := Real_Value'Min (Current_Float.High, Right_Real);
               end if;
            end if;
            Current.Float_Facts.Include (Left_Name, Current_Float);
            return;
         end if;
      end if;

      if Left_Name /= "" and then Have_Right_Const then
         Right_Const := Constant_Value (Expr.Right, Current, Var_Types, Type_Env);
         if Current.Ranges.Contains (Left_Name) then
            Current_Interval := Current.Ranges.Element (Left_Name);
         elsif Var_Types.Contains (Left_Name) then
            Current_Interval := Range_Interval (Var_Types.Element (Left_Name));
         else
            Current_Interval := (Low => INT64_LOW, High => INT64_HIGH, Excludes_Zero => False);
         end if;
         if Op = "!=" and then Truthy and then Right_Const = 0 then
            Current_Interval.Excludes_Zero := True;
            Current.Ranges.Include (Left_Name, Current_Interval);
            return;
         elsif Op = "==" and then Truthy then
            Current.Ranges.Include (Left_Name, (Low => Right_Const, High => Right_Const, Excludes_Zero => Right_Const /= 0));
            return;
         elsif Op = "==" and then not Truthy then
            if Current_Interval.Low = Right_Const then
               Current.Ranges.Include (Left_Name, Interval_Clamp (Current_Interval, Right_Const + 1, Current_Interval.High));
            elsif Current_Interval.High = Right_Const then
               Current.Ranges.Include (Left_Name, Interval_Clamp (Current_Interval, Current_Interval.Low, Right_Const - 1));
            end if;
            return;
         elsif Op = "<" or else Op = "<=" or else Op = ">" or else Op = ">=" then
            if Truthy then
               if Op = "<" then
                  Current.Ranges.Include (Left_Name, Interval_Clamp (Current_Interval, Current_Interval.Low, Right_Const - 1));
               elsif Op = "<=" then
                  Current.Ranges.Include (Left_Name, Interval_Clamp (Current_Interval, Current_Interval.Low, Right_Const));
               elsif Op = ">" then
                  Current.Ranges.Include (Left_Name, Interval_Clamp (Current_Interval, Right_Const + 1, Current_Interval.High));
               else
                  Current.Ranges.Include (Left_Name, Interval_Clamp (Current_Interval, Right_Const, Current_Interval.High));
               end if;
            else
               if Op = "<" then
                  Current.Ranges.Include (Left_Name, Interval_Clamp (Current_Interval, Right_Const, Current_Interval.High));
               elsif Op = "<=" then
                  Current.Ranges.Include (Left_Name, Interval_Clamp (Current_Interval, Right_Const + 1, Current_Interval.High));
               elsif Op = ">" then
                  Current.Ranges.Include (Left_Name, Interval_Clamp (Current_Interval, Current_Interval.Low, Right_Const));
               else
                  Current.Ranges.Include (Left_Name, Interval_Clamp (Current_Interval, Current_Interval.Low, Right_Const - 1));
               end if;
            end if;
            return;
         end if;
      end if;
      if Left_Name /= "" and then Right_Name /= "" and then (Op = "<=" or else Op = "<") and then Truthy then
         Current.Relations.Include (Pair_Key (Left_Name, Right_Name));
      end if;
      if Left_Name /= "" and then Op = "<=" and then Truthy then
         if Expr.Right /= null and then Expr.Right.Kind = GM.Expr_Ident then
            Current.Div_Bounds.Include (Pair_Key (Left_Name, UString_Value (Expr.Right.Name)), 1);
            return;
         elsif Expr.Right /= null and then Expr.Right.Kind = GM.Expr_Binary
           and then UString_Value (Expr.Right.Operator) = "*"
         then
            declare
               Denominator : constant String := Denominator_Var (Expr.Right.Left);
            begin
               if Denominator /= ""
                 and then Expr.Right.Right /= null
                 and then Expr.Right.Right.Kind = GM.Expr_Int
                 and then Expr.Right.Right.Int_Value > 0
               then
                  Current.Div_Bounds.Include
                    (Pair_Key (Left_Name, Denominator),
                     Wide_Integer (Expr.Right.Right.Int_Value));
                  return;
               end if;
            end;
         end if;
      end if;
      if Left_Name /= "" and then Expr.Right /= null and then Expr.Right.Kind = GM.Expr_Null then
         if Op = "!=" and then Truthy then
            Current.Access_Facts.Include (Left_Name, (State => Access_NonNull, others => <>));
         elsif Op = "==" and then Truthy then
            Current.Access_Facts.Include (Left_Name, (State => Access_Null, others => <>));
         end if;
      end if;

      declare
         Disc_Expr       : GM.Expr_Access := null;
         Value_Expr      : GM.Expr_Access := null;
         Disc_Value      : GM.Scalar_Value;
         Prefix_Type     : GM.Type_Descriptor;
         Base_Name_Text  : FT.UString := FT.To_UString ("");
         Disc_Name_Text  : FT.UString := FT.To_UString ("");
      begin
         if Expr.Left /= null
           and then Expr.Left.Kind = GM.Expr_Select
           and then Expr.Right /= null
         then
            Disc_Expr := Expr.Left;
            Value_Expr := Expr.Right;
         elsif Expr.Right /= null
           and then Expr.Right.Kind = GM.Expr_Select
           and then Expr.Left /= null
         then
            Disc_Expr := Expr.Right;
            Value_Expr := Expr.Left;
         end if;

         if Disc_Expr /= null and then Expr_Scalar_Value (Value_Expr, Disc_Value) then
            Base_Name_Text := FT.To_UString (Root_Name (Disc_Expr.Prefix));
            Prefix_Type := Expr_Type (Disc_Expr.Prefix, Var_Types, Type_Env, Function_Maps.Empty_Map);
            Disc_Name_Text := FT.To_UString (Variant_Discriminant_Name (Prefix_Type));
            if Has_Text (Base_Name_Text)
              and then Has_Text (Disc_Name_Text)
              and then UString_Value (Disc_Expr.Selector) = UString_Value (Disc_Name_Text)
            then
               if (Op = "==" and then Truthy) or else (Op = "!=" and then not Truthy) then
                  Current.Discriminants.Include
                    (UString_Value (Base_Name_Text),
                     (Known       => True,
                      Value       => Disc_Value,
                      Invalidated => False));
               elsif ((Op = "!=" and then Truthy) or else (Op = "==" and then not Truthy))
                 and then Current.Discriminants.Contains (UString_Value (Base_Name_Text))
                 and then Current.Discriminants.Element (UString_Value (Base_Name_Text)).Known
                 and then Scalar_Value_Equal (Current.Discriminants.Element (UString_Value (Base_Name_Text)).Value, Disc_Value)
               then
                  Current.Discriminants.Include
                    (UString_Value (Base_Name_Text),
                     (Known       => False,
                      Value       => (others => <>),
                      Invalidated => False));
               end if;
            end if;
         end if;
      end;
      pragma Unreferenced (Have_Left_Const, Left_Const);
   end Apply_Comparison_Refinement;

   function Scalar_Value_Equal
     (Left, Right : GM.Scalar_Value) return Boolean is
      use type GM.Scalar_Value_Kind;
   begin
      if Left.Kind /= Right.Kind then
         return False;
      end if;
      case Left.Kind is
         when GM.Scalar_Value_Integer =>
            return Left.Int_Value = Right.Int_Value;
         when GM.Scalar_Value_Boolean =>
            return Left.Bool_Value = Right.Bool_Value;
         when GM.Scalar_Value_Character =>
            return UString_Value (Left.Text) = UString_Value (Right.Text);
         when GM.Scalar_Value_Enum =>
            return
              UString_Value (Left.Text) = UString_Value (Right.Text)
              and then UString_Value (Left.Type_Name) = UString_Value (Right.Type_Name);
         when GM.Scalar_Value_None =>
            return False;
      end case;
   end Scalar_Value_Equal;

   function Expr_Scalar_Value
     (Expr  : GM.Expr_Access;
      Value : out GM.Scalar_Value) return Boolean
   is
      Inner : GM.Expr_Access := Expr;
   begin
      Value := (others => <>);
      if Inner = null then
         return False;
      end if;

      while Inner /= null and then Inner.Kind in GM.Expr_Conversion | GM.Expr_Annotated loop
         Inner := Inner.Inner;
      end loop;
      if Inner = null then
         return False;
      end if;

      case Inner.Kind is
         when GM.Expr_Int =>
            Value.Kind := GM.Scalar_Value_Integer;
            Value.Int_Value := Inner.Int_Value;
            return True;
         when GM.Expr_Bool =>
            Value.Kind := GM.Scalar_Value_Boolean;
            Value.Bool_Value := Inner.Bool_Value;
            return True;
         when GM.Expr_Enum_Literal =>
            Value.Kind := GM.Scalar_Value_Enum;
            Value.Text := Inner.Name;
            Value.Type_Name := Inner.Type_Name;
            return True;
         when GM.Expr_Unknown
            | GM.Expr_Real
            | GM.Expr_String
            | GM.Expr_Null
            | GM.Expr_Ident
            | GM.Expr_Select
            | GM.Expr_Resolved_Index
            | GM.Expr_Conversion
            | GM.Expr_Call
            | GM.Expr_Allocator
            | GM.Expr_Aggregate
            | GM.Expr_Array_Literal
            | GM.Expr_Tuple
            | GM.Expr_Annotated
            | GM.Expr_Unary
            | GM.Expr_Binary =>
            return False;
      end case;
   end Expr_Scalar_Value;

   function Variant_Discriminant_Name (Info : GM.Type_Descriptor) return String is
   begin
      if Has_Text (Info.Variant_Discriminant_Name) then
         return UString_Value (Info.Variant_Discriminant_Name);
      elsif Info.Has_Discriminant then
         return UString_Value (Info.Discriminant_Name);
      end if;
      return "";
   end Variant_Discriminant_Name;

   function Variant_Field_Allows
     (Field      : GM.Variant_Field;
      Value      : GM.Scalar_Value;
      All_Fields : GM.Variant_Field_Vectors.Vector) return Boolean
   is
   begin
      if not Field.Is_Others then
         return Scalar_Value_Equal (Field.Choice, Value);
      end if;
      for Item of All_Fields loop
         if not Item.Is_Others and then Scalar_Value_Equal (Item.Choice, Value) then
            return False;
         end if;
      end loop;
      return True;
   end Variant_Field_Allows;

   function Constrained_Discriminant_Value
     (Info  : GM.Type_Descriptor;
      Value : out GM.Scalar_Value) return Boolean
   is
      Disc_Name_Text : constant String := Variant_Discriminant_Name (Info);
   begin
      Value := (others => <>);
      if Disc_Name_Text = "" or else Info.Discriminant_Constraints.Is_Empty then
         return False;
      end if;

      for Constraint of Info.Discriminant_Constraints loop
         if Constraint.Is_Named
           and then UString_Value (Constraint.Name) = Disc_Name_Text
         then
            Value := Constraint.Value;
            return True;
         end if;
      end loop;

      if Info.Discriminant_Constraints.Length = 1
        and then not Info.Discriminant_Constraints
          (Info.Discriminant_Constraints.First_Index).Is_Named
      then
         Value :=
           Info.Discriminant_Constraints
             (Info.Discriminant_Constraints.First_Index).Value;
         return True;
      end if;

      return False;
   end Constrained_Discriminant_Value;

   procedure Apply_Discriminant_Refinement
     (Current  : in out State;
      Expr     : GM.Expr_Access;
      Var_Types : Type_Maps.Map;
      Truthy   : Boolean;
      Type_Env : Type_Maps.Map)
   is
      Base_Name_Text : constant String := Root_Name (Expr);
      Prefix_Type    : GM.Type_Descriptor;
      Disc_Name_Text : FT.UString := FT.To_UString ("");
      Disc_Type      : GM.Type_Descriptor;
      Fact_Value     : GM.Scalar_Value;
   begin
      if Expr = null
        or else Expr.Kind /= GM.Expr_Select
        or else Expr.Prefix = null
        or else Base_Name_Text = ""
      then
         return;
      end if;
      Prefix_Type := Expr_Type (Expr.Prefix, Var_Types, Type_Env, Function_Maps.Empty_Map);
      Disc_Name_Text := FT.To_UString (Variant_Discriminant_Name (Prefix_Type));
      if not Has_Text (Disc_Name_Text)
        or else UString_Value (Expr.Selector) /= UString_Value (Disc_Name_Text)
      then
         return;
      end if;
      Disc_Type := Field_Type (Prefix_Type, UString_Value (Disc_Name_Text), Type_Env);
      if UString_Value (Disc_Type.Name) /= "boolean" then
         return;
      end if;
      Fact_Value.Kind := GM.Scalar_Value_Boolean;
      Fact_Value.Bool_Value := Truthy;
      Current.Discriminants.Include
        (Base_Name_Text,
         (Known       => True,
          Value       => Fact_Value,
          Invalidated => False));
   end Apply_Discriminant_Refinement;

   function Refine_Condition
     (Current   : State;
      Expr      : GM.Expr_Access;
      Truthy    : Boolean;
      Var_Types : Type_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Allow_Pending_Move_Refinement : Boolean := True) return State
   is
      Result : State := Current;
      Op     : FT.UString := FT.To_UString ("");
   begin
      if Expr = null then
         return Result;
      end if;
      if Expr.Kind = GM.Expr_Unary and then UString_Value (Expr.Operator) = "not" then
         return
           Refine_Condition
             (Result,
              Expr.Inner,
              not Truthy,
              Var_Types,
              Type_Env,
              Allow_Pending_Move_Refinement);
      elsif Expr.Kind = GM.Expr_Ident
        and then Var_Types.Contains (UString_Value (Expr.Name))
        and then UString_Value (Var_Types.Element (UString_Value (Expr.Name)).Name) = "boolean"
      then
         Result.Ranges.Include
           (UString_Value (Expr.Name),
            (Low => (if Truthy then 1 else 0),
             High => (if Truthy then 1 else 0),
             Excludes_Zero => Truthy));
         if Allow_Pending_Move_Refinement then
            Apply_Pending_Move_Refinement
              (Result,
               UString_Value (Expr.Name),
               Truthy);
         end if;
      elsif Expr.Kind = GM.Expr_Select then
         Apply_Discriminant_Refinement (Result, Expr, Var_Types, Truthy, Type_Env);
      elsif Expr.Kind = GM.Expr_Binary then
         Op := Expr.Operator;
         if UString_Value (Op) = "and then" then
            if Truthy then
               return
                 Refine_Condition
                   (Refine_Condition
                      (Result,
                       Expr.Left,
                       True,
                       Var_Types,
                       Type_Env,
                       False),
                    Expr.Right,
                    True,
                    Var_Types,
                    Type_Env,
                    False);
            end if;
            return Refine_Condition (Result, Expr.Left, False, Var_Types, Type_Env, False);
         elsif UString_Value (Op) = "!="
           or else UString_Value (Op) = "=="
           or else UString_Value (Op) = "<"
           or else UString_Value (Op) = "<="
           or else UString_Value (Op) = ">"
           or else UString_Value (Op) = ">="
         then
            Apply_Comparison_Refinement (Result, Expr, Truthy, Var_Types, Type_Env);
         end if;
      end if;
      return Result;
   end Refine_Condition;

   procedure Initialize_Symbol
     (Current : in out State;
      Name    : String;
      Info    : GM.Type_Descriptor) is
      Role : constant Access_Role_Kind := Type_Access_Role (Info);
   begin
      if Is_Integer_Type (Info) then
         Current.Ranges.Include (Name, Range_Interval (Info));
      elsif Is_Float_Type (Info) then
         Current.Float_Facts.Include (Name, Float_Interval_For (Info));
      elsif Lower (UString_Value (Info.Kind)) = "access" then
         if Info.Not_Null or else Role = Role_Borrow or else Role = Role_Observe then
            Current.Access_Facts.Include (Name, (State => Access_NonNull, others => <>));
         elsif Role = Role_Owner then
            Current.Access_Facts.Include (Name, (State => Access_Null, others => <>));
         else
            Current.Access_Facts.Include (Name, (State => Access_MaybeNull, others => <>));
         end if;
      end if;
   end Initialize_Symbol;

   procedure Invalidate_Discriminant_Fact
     (Current : in out State;
      Name    : String) is
   begin
      Current.Discriminants.Include
        (Name,
         (Known       => False,
          Value       => (others => <>),
          Invalidated => True));
   end Invalidate_Discriminant_Fact;

   function Graph_Var_Types
     (Graph    : GM.Graph_Entry;
      Type_Env : Type_Maps.Map) return Type_Maps.Map
   is
      Result : Type_Maps.Map := Type_Env;
      Info   : GM.Type_Descriptor;
   begin
      for Local of Graph.Locals loop
         Info := Local.Type_Info;
         if Has_Text (Local.Ownership_Role)
           and then Lower (UString_Value (Info.Kind)) = "access"
         then
            Info.Has_Access_Role := True;
            Info.Access_Role := Local.Ownership_Role;
         end if;
         Result.Include (UString_Value (Local.Name), Info);
      end loop;
      return Result;
   end Graph_Var_Types;

   function Graph_Local_Meta
     (Graph : GM.Graph_Entry) return Local_Maps.Map
   is
      Result : Local_Maps.Map;
   begin
      for Local of Graph.Locals loop
         Result.Include (UString_Value (Local.Name), Local);
      end loop;
      return Result;
   end Graph_Local_Meta;

   procedure Initialize_Graph_Entry_State
     (Graph       : GM.Graph_Entry;
      Type_Env    : Type_Maps.Map;
      Entry_State : out State;
      Var_Types   : out Type_Maps.Map;
      Owner_Vars  : out String_Sets.Set;
      Local_Meta  : out Local_Maps.Map)
   is
   begin
      Var_Types := Graph_Var_Types (Graph, Type_Env);
      Local_Meta := Graph_Local_Meta (Graph);
      for Local of Graph.Locals loop
         if Lower (UString_Value (Local.Type_Info.Kind)) = "access"
           and then Type_Access_Role (Var_Types.Element (UString_Value (Local.Name))) = Role_Owner
         then
            Owner_Vars.Include (UString_Value (Local.Name));
         end if;
         if Is_Float_Type (Var_Types.Element (UString_Value (Local.Name)))
           and then not (UString_Value (Local.Kind) = "param" or else UString_Value (Local.Kind) = "global")
         then
            declare
               Fact : Float_Interval := Float_Interval_For (Var_Types.Element (UString_Value (Local.Name)));
            begin
               Fact.Initialized := False;
               Fact.May_Be_NaN := True;
               Fact.May_Be_Infinite := True;
               Entry_State.Float_Facts.Include (UString_Value (Local.Name), Fact);
            end;
         end if;
         if UString_Value (Local.Kind) = "param"
           or else UString_Value (Local.Kind) = "global"
         then
            Initialize_Symbol (Entry_State, UString_Value (Local.Name), Var_Types.Element (UString_Value (Local.Name)));
         end if;
      end loop;
   end Initialize_Graph_Entry_State;

   procedure Invalidate_Scope_Exit
     (Current     : in out State;
      Local_Names : FT.UString_Vectors.Vector;
      Owner_Vars  : String_Sets.Set)
   is
      Exiting_Owners : String_Sets.Set;
   begin
      for Name of Local_Names loop
         declare
            Text : constant String := UString_Value (Name);
         begin
            if Current.Access_Facts.Contains (Text) then
               declare
                  Fact : constant Access_Fact := Current.Access_Facts.Element (Text);
               begin
                  if Fact.Has_Lender and then (Fact.Alias_Kind = Role_Borrow or else Fact.Alias_Kind = Role_Observe) then
                     Decrement_Freeze (Current, UString_Value (Fact.Lender), Fact.Alias_Kind);
                  end if;
               end;
            end if;
            if Owner_Vars.Contains (Text) then
               Exiting_Owners.Include (Text);
            end if;
         end;
      end loop;

      declare
         Cursor : Access_Maps.Cursor := Current.Access_Facts.First;
      begin
         while Access_Maps.Has_Element (Cursor) loop
            declare
               Name : constant String := Access_Maps.Key (Cursor);
               Fact : Access_Fact := Access_Maps.Element (Cursor);
            begin
               if Fact.Has_Lender and then Exiting_Owners.Contains (UString_Value (Fact.Lender)) then
                  Fact.State := Access_Dangling;
                  Current.Access_Facts.Include (Name, Fact);
               end if;
               Access_Maps.Next (Cursor);
            end;
         end loop;
      end;
   end Invalidate_Scope_Exit;

   function Join_Two_States
     (Left, Right : State) return State
   is
      Result : State := Left;
      Cursor : Range_Maps.Cursor;
      Float_Cursor : Float_Maps.Cursor;
      Access_Cursor : Access_Maps.Cursor;
      Discriminant_Cursor : Discriminant_Maps.Cursor;
      Freeze_Cursor : Natural_Maps.Cursor;
      Div_Cursor    : Interval_Maps.Cursor;
      New_Fact      : Access_Fact;
   begin
      Cursor := Right.Ranges.First;
      while Range_Maps.Has_Element (Cursor) loop
         declare
            Name : constant String := Range_Maps.Key (Cursor);
            Item : constant Interval := Range_Maps.Element (Cursor);
         begin
            if Result.Ranges.Contains (Name) then
               Result.Ranges.Include (Name, Interval_Join (Result.Ranges.Element (Name), Item));
            else
               Result.Ranges.Include (Name, Item);
            end if;
            Range_Maps.Next (Cursor);
         end;
      end loop;

      Float_Cursor := Right.Float_Facts.First;
      while Float_Maps.Has_Element (Float_Cursor) loop
         declare
            Name : constant String := Float_Maps.Key (Float_Cursor);
            Item : constant Float_Interval := Float_Maps.Element (Float_Cursor);
         begin
            if Result.Float_Facts.Contains (Name) then
               Result.Float_Facts.Include
                 (Name,
                  Float_Interval_Join (Result.Float_Facts.Element (Name), Item));
            else
               Result.Float_Facts.Include (Name, Item);
            end if;
            Float_Maps.Next (Float_Cursor);
         end;
      end loop;

      Access_Cursor := Right.Access_Facts.First;
      while Access_Maps.Has_Element (Access_Cursor) loop
         declare
            Name : constant String := Access_Maps.Key (Access_Cursor);
            Item : constant Access_Fact := Access_Maps.Element (Access_Cursor);
         begin
            if Result.Access_Facts.Contains (Name) then
               New_Fact := Result.Access_Facts.Element (Name);
               if New_Fact.State /= Item.State
                 or else New_Fact.Has_Lender /= Item.Has_Lender
                 or else (New_Fact.Has_Lender and then UString_Value (New_Fact.Lender) /= UString_Value (Item.Lender))
                 or else New_Fact.Alias_Kind /= Item.Alias_Kind
               then
                  if not New_Fact.Has_Lender
                    and then not Item.Has_Lender
                    and then New_Fact.Alias_Kind = Role_None
                    and then Item.Alias_Kind = Role_None
                    and then
                      ((New_Fact.State = Access_Null and then Item.State = Access_Moved)
                       or else (New_Fact.State = Access_Moved and then Item.State = Access_Null))
                    and then not Has_Pending_Move_For_Source (Left, Name)
                    and then not Has_Pending_Move_For_Source (Right, Name)
                  then
                     Result.Access_Facts.Include
                       (Name,
                        (State       => Access_Moved,
                         Has_Lender  => False,
                         Lender      => FT.To_UString (""),
                         Alias_Kind  => Role_None,
                         Initialized => New_Fact.Initialized or else Item.Initialized));
                  else
                     Result.Access_Facts.Include
                       (Name,
                        (State       => Access_MaybeNull,
                         Has_Lender  => False,
                         Lender      => FT.To_UString (""),
                         Alias_Kind  => Role_None,
                         Initialized => New_Fact.Initialized or else Item.Initialized));
                  end if;
               else
                  New_Fact.Initialized := New_Fact.Initialized or else Item.Initialized;
                  Result.Access_Facts.Include (Name, New_Fact);
               end if;
            else
               Result.Access_Facts.Include (Name, Item);
            end if;
            Access_Maps.Next (Access_Cursor);
         end;
      end loop;

      declare
         Pending_Cursor : Pending_Move_Maps.Cursor := Left.Pending_Moves.First;
      begin
         Result.Pending_Moves.Clear;
         while Pending_Move_Maps.Has_Element (Pending_Cursor) loop
            declare
               Name : constant String := Pending_Move_Maps.Key (Pending_Cursor);
               Item : constant Pending_Move := Pending_Move_Maps.Element (Pending_Cursor);
            begin
               if Right.Pending_Moves.Contains (Name)
                 and then Right.Pending_Moves.Element (Name) = Item
               then
                  Result.Pending_Moves.Include (Name, Item);
               end if;
               Pending_Move_Maps.Next (Pending_Cursor);
            end;
         end loop;
      end;

      declare
         Binding_Cursor : String_Sets.Cursor := Left.Pending_Bindings.First;
         New_Bindings   : String_Sets.Set;
      begin
         while String_Sets.Has_Element (Binding_Cursor) loop
            declare
               Name : constant String := String_Sets.Element (Binding_Cursor);
            begin
               if Right.Pending_Bindings.Contains (Name) then
                  New_Bindings.Include (Name);
               end if;
               String_Sets.Next (Binding_Cursor);
            end;
         end loop;
         Result.Pending_Bindings := New_Bindings;
      end;

      Result.Discriminants.Clear;
      Discriminant_Cursor := Left.Discriminants.First;
      while Discriminant_Maps.Has_Element (Discriminant_Cursor) loop
         declare
            Name   : constant String := Discriminant_Maps.Key (Discriminant_Cursor);
            L_Item : constant Discriminant_Fact := Discriminant_Maps.Element (Discriminant_Cursor);
            Merged : Discriminant_Fact;
         begin
            if Right.Discriminants.Contains (Name) then
               declare
                  R_Item : constant Discriminant_Fact := Right.Discriminants.Element (Name);
               begin
                  if L_Item.Known
                    and then R_Item.Known
                    and then Scalar_Value_Equal (L_Item.Value, R_Item.Value)
                    and then not L_Item.Invalidated
                    and then not R_Item.Invalidated
                  then
                     Merged := L_Item;
                  else
                     Merged :=
                       (Known       => False,
                        Value       => (others => <>),
                        Invalidated => L_Item.Invalidated or else R_Item.Invalidated);
                  end if;
               end;
            else
               Merged :=
                 (Known       => False,
                  Value       => (others => <>),
                  Invalidated => L_Item.Invalidated);
            end if;
            Result.Discriminants.Include (Name, Merged);
            Discriminant_Maps.Next (Discriminant_Cursor);
         end;
      end loop;

      Discriminant_Cursor := Right.Discriminants.First;
      while Discriminant_Maps.Has_Element (Discriminant_Cursor) loop
         declare
            Name : constant String := Discriminant_Maps.Key (Discriminant_Cursor);
            Item : constant Discriminant_Fact := Discriminant_Maps.Element (Discriminant_Cursor);
         begin
            if not Left.Discriminants.Contains (Name) then
               Result.Discriminants.Include
                 (Name,
                  (Known       => False,
                   Value       => (others => <>),
                   Invalidated => Item.Invalidated));
            end if;
            Discriminant_Maps.Next (Discriminant_Cursor);
         end;
      end loop;

      declare
         New_Relations : String_Sets.Set;
         Set_Cursor    : String_Sets.Cursor := Result.Relations.First;
      begin
         while String_Sets.Has_Element (Set_Cursor) loop
            declare
               Item : constant String := String_Sets.Element (Set_Cursor);
            begin
               if Right.Relations.Contains (Item) then
                  New_Relations.Include (Item);
               end if;
               String_Sets.Next (Set_Cursor);
            end;
         end loop;
         Result.Relations := New_Relations;
      end;

      declare
         New_Divs : Interval_Maps.Map;
      begin
         Div_Cursor := Result.Div_Bounds.First;
         while Interval_Maps.Has_Element (Div_Cursor) loop
            declare
               Key : constant String := Interval_Maps.Key (Div_Cursor);
            begin
               if Right.Div_Bounds.Contains (Key) then
                  New_Divs.Include (Key, Wide_Integer'Min (Result.Div_Bounds.Element (Key), Right.Div_Bounds.Element (Key)));
               end if;
               Interval_Maps.Next (Div_Cursor);
            end;
         end loop;
         Result.Div_Bounds := New_Divs;
      end;

      Freeze_Cursor := Right.Borrow_Freeze.First;
      while Natural_Maps.Has_Element (Freeze_Cursor) loop
         declare
            Name : constant String := Natural_Maps.Key (Freeze_Cursor);
            Value : constant Natural := Natural_Maps.Element (Freeze_Cursor);
         begin
            Result.Borrow_Freeze.Include (Name, Natural'Max (Freeze_Count (Result, Name, Role_Borrow), Value));
            Natural_Maps.Next (Freeze_Cursor);
         end;
      end loop;

      Freeze_Cursor := Right.Observe_Freeze.First;
      while Natural_Maps.Has_Element (Freeze_Cursor) loop
         declare
            Name : constant String := Natural_Maps.Key (Freeze_Cursor);
            Value : constant Natural := Natural_Maps.Element (Freeze_Cursor);
         begin
            Result.Observe_Freeze.Include (Name, Natural'Max (Freeze_Count (Result, Name, Role_Observe), Value));
            Natural_Maps.Next (Freeze_Cursor);
         end;
      end loop;

      Result.Returned := Left.Returned and then Right.Returned;
      return Result;
   end Join_Two_States;

   function States_Equal
     (Left, Right : State) return Boolean is
   begin
      return Left = Right;
   end States_Equal;

   function Join_State_Into
     (Targets   : in out State_Maps.Map;
      Block_Id  : String;
      Candidate : State) return Boolean
   is
      Joined : State;
   begin
      if not Targets.Contains (Block_Id) then
         Targets.Include (Block_Id, Candidate);
         return True;
      end if;
      Joined := Join_Two_States (Targets.Element (Block_Id), Candidate);
      if not States_Equal (Targets.Element (Block_Id), Joined) then
         Targets.Include (Block_Id, Joined);
         return True;
      end if;
      return False;
   end Join_State_Into;

   function Diagnostic_Category_Rank
     (Item : MD.Diagnostic) return Natural
   is
      Message : constant String := Lower (UString_Value (Item.Message));
   begin
      if UString_Value (Item.Reason) = "task_variable_ownership" then
         if Ada.Strings.Fixed.Index (Message, "package global") = 1 then
            return 0;
         elsif Ada.Strings.Fixed.Index (Message, "subprogram") = 1 then
            return 1;
         end if;
      end if;
      return 2;
   end Diagnostic_Category_Rank;

   function Is_Constant_Target
     (Expr       : GM.Expr_Access;
      Local_Meta : Local_Maps.Map) return Boolean
   is
   begin
      if Expr = null then
         return False;
      end if;

      case Expr.Kind is
         when GM.Expr_Ident =>
            declare
               Name : constant String := Root_Name (Expr);
            begin
               return Name /= ""
                 and then Local_Meta.Contains (Name)
                 and then Local_Meta.Element (Name).Is_Constant;
            end;
         when GM.Expr_Select =>
            if UString_Value (Expr.Selector) = "all" then
               return False;
            end if;
            return Is_Constant_Target (Expr.Prefix, Local_Meta);
         when GM.Expr_Resolved_Index =>
            return Is_Constant_Target (Expr.Prefix, Local_Meta);
         when GM.Expr_Conversion =>
            return Is_Constant_Target (Expr.Inner, Local_Meta);
         when GM.Expr_Unknown
            | GM.Expr_Int
            | GM.Expr_Real
            | GM.Expr_String
            | GM.Expr_Bool
            | GM.Expr_Enum_Literal
            | GM.Expr_Null
            | GM.Expr_Call
            | GM.Expr_Allocator
            | GM.Expr_Aggregate
            | GM.Expr_Array_Literal
            | GM.Expr_Tuple
            | GM.Expr_Annotated
            | GM.Expr_Unary
            | GM.Expr_Binary =>
            return False;
      end case;
   end Is_Constant_Target;

   function Is_All_Dereference (Expr : GM.Expr_Access) return Boolean is
   begin
      return Expr /= null
        and then Expr.Kind = GM.Expr_Select
        and then UString_Value (Expr.Selector) = "all";
   end Is_All_Dereference;

   procedure Validate_Assignment_Target
     (Expr      : GM.Expr_Access;
      Current   : State;
      Local_Meta : Local_Maps.Map;
      Var_Types : Type_Maps.Map;
      Type_Env  : Type_Maps.Map;
      Functions : Function_Maps.Map;
      Skip_Constant_Check : Boolean := False) is
      Role : Access_Role_Kind;
      Diag : MD.Diagnostic;
      Name : constant String := Root_Name (Expr);
   begin
      if Expr = null then
         return;
      elsif not Skip_Constant_Check and then Is_Constant_Target (Expr, Local_Meta) then
         Raise_Diag
           (Ownership_Diagnostic
              ("write_to_constant",
               Expr.Span,
               "assignment target rooted in constant `"
               & (if Name = "" then "<unknown>" else Name)
               & "` is not writable",
               "constant objects are immutable after declaration initialization in the current PR08.3a subset."));
      elsif Expr.Kind = GM.Expr_Ident then
         Role := Type_Access_Role (Resolve_Type (UString_Value (Expr.Name), Var_Types, Type_Env));
         if Role = Role_Observe or else Role = Role_Named_Constant then
            Raise_Diag (Observer_Write_Conflict (UString_Value (Expr.Name), Expr.Span));
         elsif Role = Role_Owner or else Role = Role_General_Access then
            Diag := Owner_Write_Conflict (UString_Value (Expr.Name), Current, Expr.Span);
            if Has_Text (Diag.Reason) then
               Raise_Diag (Diag);
            end if;
         end if;
      elsif Expr.Kind = GM.Expr_Select then
         Validate_Assignment_Target
           (Expr.Prefix,
            Current,
            Local_Meta,
            Var_Types,
            Type_Env,
            Functions,
            Skip_Constant_Check =>
              Skip_Constant_Check
              or else UString_Value (Expr.Selector) = "all"
              or else Is_All_Dereference (Expr.Prefix));
         if UString_Value (Expr.Selector) = "access" then
            declare
               Result : MD.Diagnostic := Null_Diagnostic;
            begin
               Result.Reason := FT.To_UString ("narrowing_check_failure");
               Result.Message := FT.To_UString ("assignment target is not a writable name");
               Result.Span := Expr.Span;
               Result.Has_Highlight_Span := True;
               Result.Highlight_Span := Expr.Span;
               Raise_Diag (Result);
            end;
         end if;
         if UString_Value (Expr.Selector) = "all"
           or else Lower (UString_Value (Expr_Type (Expr.Prefix, Var_Types, Type_Env, Functions).Kind)) = "access"
         then
            Ensure_Access_Safe (Expr.Prefix, Expr.Prefix.Span, Current, Var_Types, Type_Env, Functions);
         end if;
      elsif Expr.Kind = GM.Expr_Resolved_Index then
         Validate_Assignment_Target
           (Expr.Prefix,
            Current,
            Local_Meta,
            Var_Types,
            Type_Env,
            Functions,
            Skip_Constant_Check => Skip_Constant_Check or else Is_All_Dereference (Expr.Prefix));
         declare
            Value : constant Interval := Eval_Index_Expr (Expr, Current, Var_Types, Type_Env, Functions);
         begin
            pragma Unreferenced (Value);
         end;
      else
         declare
            Result : MD.Diagnostic := Null_Diagnostic;
         begin
            Result.Reason := FT.To_UString ("narrowing_check_failure");
            Result.Message := FT.To_UString ("assignment target is not a writable name");
            Result.Span := Expr.Span;
            Result.Has_Highlight_Span := True;
            Result.Highlight_Span := Expr.Span;
            Raise_Diag (Result);
         end;
      end if;
   end Validate_Assignment_Target;

   function Assignment_Lender_Name
     (Expr : GM.Expr_Access) return String is
   begin
      if Expr = null then
         return "";
      elsif Expr.Kind = GM.Expr_Ident then
         return UString_Value (Expr.Name);
      elsif Expr.Kind = GM.Expr_Select and then UString_Value (Expr.Selector) = "access" then
         return Root_Name (Expr.Prefix);
      end if;
      return "";
   end Assignment_Lender_Name;

   function Observe_Lender_Name
     (Expr : GM.Expr_Access) return String is
   begin
      if Expr /= null and then Expr.Kind = GM.Expr_Select and then UString_Value (Expr.Selector) = "access" then
         return Root_Name (Expr.Prefix);
      end if;
      return "";
   end Observe_Lender_Name;

   function Assign_Access_Alias
     (Current     : in out State;
      Target_Name : String;
      Target_Type : GM.Type_Descriptor;
      Value       : GM.Expr_Access;
      Value_Fact  : Access_Fact;
      Span        : FT.Source_Span) return MD.Diagnostic
   is
      Target_Role : constant Access_Role_Kind := Type_Access_Role (Target_Type);
      Lender      : FT.UString := FT.To_UString (Assignment_Lender_Name (Value));
      Existing    : Access_Fact;
      Conflict    : MD.Diagnostic;
   begin
      if Target_Role = Role_Observe then
         Lender := FT.To_UString (Observe_Lender_Name (Value));
         if not Has_Text (Lender) then
            return
                 Ownership_Diagnostic
                   ("observe_requires_access",
                    Span,
                    "observer '" & Target_Name & "' must be initialized from X.access",
                    "local observe uses anonymous access constant and requires an explicit .access attribute.");
         end if;
      end if;

      if Target_Role = Role_Borrow or else Target_Role = Role_Observe then
         if Current.Access_Facts.Contains (Target_Name) then
            Existing := Current.Access_Facts.Element (Target_Name);
            if Existing.Initialized then
               return
                 Ownership_Diagnostic
                   ("anonymous_access_reassign",
                    Span,
                    "anonymous access '" & Target_Name & "' may only be assigned at its declaration",
                    "borrow and observe locals are initialization-only.");
            end if;
         end if;

         if Has_Text (Lender) then
            if Target_Role = Role_Borrow then
               Conflict := Owner_Write_Conflict (UString_Value (Lender), Current, Span);
            else
               Conflict := Owner_Read_Conflict (UString_Value (Lender), Current, Span);
            end if;
            if Has_Text (Conflict.Reason) then
               return Conflict;
            elsif Value_Fact.State /= Access_NonNull then
               return
                  Ownership_Diagnostic
                    ("move_source_not_nonnull",
                     Span,
                     Lower (Image (Target_Role)) & " source '" & UString_Value (Lender) & "' is not provably non-null",
                     "static analysis determined state '" & Image (Value_Fact.State) & "' at the alias initialization site.");
            end if;
         end if;

         Current.Access_Facts.Include
           (Target_Name,
            (State       => Value_Fact.State,
             Has_Lender  => Has_Text (Lender),
             Lender      => Lender,
             Alias_Kind  => Target_Role,
             Initialized => True));
         if Has_Text (Lender) then
            Increment_Freeze (Current, UString_Value (Lender), Target_Role);
         end if;
      end if;
      return Null_Diagnostic;
   end Assign_Access_Alias;

   function Apply_Mir_Assignment
     (Op         : GM.Op_Entry;
      Current    : in out State;
      Var_Types  : Type_Maps.Map;
      Owner_Vars : String_Sets.Set;
      Type_Env   : Type_Maps.Map;
      Functions  : Function_Maps.Map) return MD.Diagnostic
   is
      Target_Name : constant String := Base_Name (Op.Target);
      Target_Type : GM.Type_Descriptor :=
        (if Target_Name /= "" and then Var_Types.Contains (Target_Name)
         then Var_Types.Element (Target_Name)
         else Expr_Type (Op.Target, Var_Types, Type_Env, Functions));
      Has_Diag    : Boolean;
      Diag        : MD.Diagnostic := Null_Diagnostic;
      Interval_Value : Interval;
      Float_Value : Float_Interval;
      Value_Fact  : Access_Fact;
      Source_Name : FT.UString := FT.To_UString ("");
      Target_Role : Access_Role_Kind;
      Target_Fact : Access_Fact;
   begin
      pragma Unreferenced (Owner_Vars);
      if Target_Name /= ""
        and then Target_Type.Has_Discriminant
        and then not Op.Declaration_Init
      then
         Invalidate_Discriminant_Fact (Current, Target_Name);
      end if;
      if Target_Name = "" or else Lower (UString_Value (Target_Type.Kind)) /= "access" then
         if Is_Float_Type (Target_Type) then
            Float_Value :=
              Eval_Float_Expr_With_Diag
                (Op.Value,
                 Current,
                 Var_Types,
                 Type_Env,
                 Functions,
                 Target_Type,
                 Has_Diag,
                 Diag);
            if Has_Diag then
               return Diag;
            elsif Target_Name /= "" then
               Current.Float_Facts.Include (Target_Name, Float_Value);
            end if;
            return Null_Diagnostic;
         elsif Lower (UString_Value (Target_Type.Kind)) = "string" then
            return Null_Diagnostic;
         elsif Lower (UString_Value (Target_Type.Kind)) in "record" | "tuple" | "array" then
            return Null_Diagnostic;
         end if;
         Interval_Value :=
           Eval_Int_Expr_With_Diag
             (Op.Value,
              Current,
              Var_Types,
              Type_Env,
              Functions,
              Target_Type,
              False,
              Has_Diag,
              Diag);
         if Has_Diag then
            return Diag;
         elsif Target_Name /= "" then
            if Is_Integer_Type (Target_Type) then
               declare
                  Bounds : constant Interval := Range_Interval (Target_Type);
               begin
                  Current.Ranges.Include (Target_Name, Interval_Clamp (Interval_Value, Bounds.Low, Bounds.High));
               end;
            else
               Current.Ranges.Include (Target_Name, Interval_Value);
            end if;
         end if;
         return Null_Diagnostic;
      end if;

      Target_Role := Type_Access_Role (Target_Type);
      begin
         Value_Fact := Eval_Access_Expr (Op.Value, Current, Var_Types, Type_Env, Functions);
      exception
         when Diagnostic_Failure =>
            return Raised_Diagnostic;
      end;

      if Target_Role = Role_Observe or else Target_Role = Role_Borrow then
         return Assign_Access_Alias (Current, Target_Name, Target_Type, Op.Value, Value_Fact, Op.Span);
      end if;

      if Op.Ownership_Effect = GM.Ownership_Move
        and then (Target_Role = Role_Owner or else Target_Role = Role_General_Access)
      then
         Source_Name := FT.To_UString (Assignment_Lender_Name (Op.Value));
         declare
            Root_Source_Name : constant String := Root_Name (Op.Value);
         begin
            if not Has_Text (Source_Name)
              and then Target_Name /= ""
              and then Root_Source_Name = Target_Name
            then
               Diag := Owner_Write_Conflict (Target_Name, Current, Op.Span);
               if Has_Text (Diag.Reason) then
                  return Diag;
               end if;

               declare
                  Source_Fact : constant Access_Fact :=
                    Access_Fact_For_Name (Target_Name, Current, Var_Types);
               begin
                  if Source_Fact.State = Access_Moved then
                     return
                       Ownership_Diagnostic
                         ("double_move",
                          Op.Span,
                          "use of moved value '" & Target_Name & "'",
                          "the source was already moved earlier on this path.");
                  elsif Source_Fact.State /= Access_NonNull then
                     return
                       Ownership_Diagnostic
                         ("move_source_not_nonnull",
                          Op.Span,
                          "move source '" & Target_Name & "' is not provably non-null",
                          "static analysis determined state '" & Image (Source_Fact.State)
                          & "' at this move site.");
                  end if;
               end;

               Current.Access_Facts.Include (Target_Name, Value_Fact);
               return Null_Diagnostic;
            end if;
         end;

         if not Has_Text (Source_Name) then
            if not Op.Declaration_Init then
               Target_Fact := Access_Fact_For_Name (Target_Name, Current, Var_Types);
               if not Target_Is_Provably_Null (Current, Target_Name, Var_Types) then
                  return
                    Ownership_Diagnostic
                      ("move_target_not_null",
                       Op.Span,
                       "move target '" & Target_Name & "' is not provably null",
                       "static analysis determined state '" & Image (Target_Fact.State) & "' for the move target.");
               end if;
            end if;
            Current.Access_Facts.Include (Target_Name, Value_Fact);
            return Null_Diagnostic;
         elsif Has_Text (Source_Name) then
            Diag :=
              Owner_Move_Precondition
                (UString_Value (Source_Name),
                 Target_Name,
                 Current,
                 Var_Types,
                 Op.Span,
                 Require_Null_Target => not Op.Declaration_Init);
            if Has_Text (Diag.Reason) then
               return Diag;
            end if;
            Current.Access_Facts.Include (Target_Name, (State => Access_NonNull, others => <>));
            Current.Access_Facts.Include (UString_Value (Source_Name), (State => Access_Moved, others => <>));
            return Null_Diagnostic;
         end if;
      end if;

      Current.Access_Facts.Include (Target_Name, Value_Fact);
      return Null_Diagnostic;
   end Apply_Mir_Assignment;

   function Analyze_Call_Expr
     (Expr       : GM.Expr_Access;
      Current    : in out State;
      Var_Types  : Type_Maps.Map;
      Owner_Vars : String_Sets.Set;
      Type_Env   : Type_Maps.Map;
      Functions  : Function_Maps.Map) return MD.Diagnostic
   is
      pragma Unreferenced (Owner_Vars);
      Name        : constant String := Flatten_Name (Expr.Callee);
      Function_Def : Function_Info;
      Formal_Role : Access_Role_Kind;
      Actual_Name : FT.UString := FT.To_UString ("");
      Actual_Path : Alias_Path;
      Fact        : Access_Fact;
      Diag        : MD.Diagnostic := Null_Diagnostic;
      Has_Diag    : Boolean;
      Interval_Value : Interval;
   begin
      if Expr = null or else Expr.Kind /= GM.Expr_Call or else not Functions.Contains (Name) then
         return Null_Diagnostic;
      end if;
      Function_Def := Functions.Element (Name);
      if Function_Def.Params.Length /= Expr.Args.Length then
         return Null_Diagnostic;
      end if;
      for Index in Function_Def.Params.First_Index .. Function_Def.Params.Last_Index loop
         declare
            Actual : constant GM.Expr_Access := Expr.Args (Expr.Args.First_Index + (Index - Function_Def.Params.First_Index));
            Formal : constant GM.Local_Entry := Function_Def.Params (Index);
         begin
            Formal_Role := Type_Access_Role (Formal.Type_Info);
            Actual_Path := Normalize_Alias_Path (Actual, Current, Var_Types, Type_Env, Functions);
            Actual_Name := Actual_Path.Root;
            if UString_Value (Formal.Mode) = "mut"
              and then Has_Text (Actual_Name)
            then
               for Other_Index in Function_Def.Params.First_Index .. Function_Def.Params.Last_Index loop
                  if Other_Index /= Index then
                     declare
                        Other_Actual : constant GM.Expr_Access :=
                          Expr.Args (Expr.Args.First_Index + (Other_Index - Function_Def.Params.First_Index));
                        Other_Path : constant Alias_Path :=
                          Normalize_Alias_Path (Other_Actual, Current, Var_Types, Type_Env, Functions);
                     begin
                        if Other_Path.Root = Actual_Name
                          and then Paths_Overlap (Actual_Path, Other_Path)
                        then
                           return
                             Ownership_Diagnostic
                               ("mut_alias_conflict",
                                Actual.Span,
                                "mutable borrow actual '" & Source_Text_For_Expr (Actual)
                                & "' aliases another actual in the same call",
                                "same-root `mut` calls allow only statically disjoint record-field or singleton-index paths; overlapping or unsupported paths remain rejected.");
                        end if;
                     end;
                  end if;
               end loop;
            end if;
            if Is_Integer_Type (Formal.Type_Info) then
               Interval_Value :=
                 Eval_Int_Expr_With_Diag
                   (Actual,
                    Current,
                    Var_Types,
                    Type_Env,
                    Functions,
                    Formal.Type_Info,
                    False,
                    Has_Diag,
                    Diag);
               if Has_Diag then
                  return Diag;
               elsif not Interval_Contains (Range_Interval (Formal.Type_Info), Interval_Value) then
                  Diag.Reason := FT.To_UString ("narrowing_check_failure");
                  Diag.Message := FT.To_UString ("actual parameter is not provably within formal parameter range");
                  Diag.Span := Actual.Span;
                  Diag.Has_Highlight_Span := True;
                  Diag.Highlight_Span := Actual.Span;
                  Diag.Notes.Append
                    (FT.To_UString
                       ("formal '" & UString_Value (Formal.Name)
                        & "' has type " & UString_Value (Formal.Type_Info.Name)
                        & " with range "
                        & Interval_Format (Range_Interval (Formal.Type_Info))));
                  Diag.Notes.Append
                    (FT.To_UString ("actual expression range is " & Interval_Format (Interval_Value)));
                  return Diag;
               end if;
               goto Continue;
            elsif Is_Float_Type (Formal.Type_Info) then
               declare
                  Float_Value : constant Float_Interval :=
                    Eval_Float_Expr_With_Diag
                      (Actual,
                       Current,
                       Var_Types,
                       Type_Env,
                       Functions,
                       Formal.Type_Info,
                       Has_Diag,
                       Diag);
                  pragma Unreferenced (Float_Value);
               begin
                  null;
               end;
               if Has_Diag then
                  return Diag;
               end if;
               goto Continue;
            elsif (UString_Value (Formal.Mode) = "mut"
                   or else UString_Value (Formal.Mode) = "out"
                   or else UString_Value (Formal.Mode) = "in out")
              and then Formal.Type_Info.Has_Discriminant
            then
               if Has_Text (Actual_Name) then
                  Invalidate_Discriminant_Fact (Current, UString_Value (Actual_Name));
               end if;
               goto Continue;
            elsif Lower (UString_Value (Formal.Type_Info.Kind)) /= "access" then
               goto Continue;
            end if;

            begin
               Fact := Eval_Access_Expr (Actual, Current, Var_Types, Type_Env, Functions);
            exception
               when Diagnostic_Failure =>
                  return Raised_Diagnostic;
            end;

            if Formal_Role = Role_Borrow then
               if not Has_Text (Actual_Name) then
                  goto Continue;
               end if;
               Diag := Owner_Write_Conflict (UString_Value (Actual_Name), Current, Actual.Span);
               if Has_Text (Diag.Reason) then
                  return Diag;
               elsif Fact.State /= Access_NonNull then
                  return
                    Ownership_Diagnostic
                      ("move_source_not_nonnull",
                       Actual.Span,
                       "borrow source '" & UString_Value (Actual_Name) & "' is not provably non-null",
                       "static analysis determined state '" & Image (Fact.State) & "' at the borrow site.");
               end if;
            elsif Formal_Role = Role_Observe then
               if Has_Text (Actual_Name) then
                  Diag := Owner_Read_Conflict (UString_Value (Actual_Name), Current, Actual.Span);
                  if Has_Text (Diag.Reason) then
                     return Diag;
                  end if;
               end if;
            elsif UString_Value (Formal.Mode) = "mut" then
               if not Has_Text (Actual_Name) then
                  goto Continue;
               end if;
               Diag := Owner_Write_Conflict (UString_Value (Actual_Name), Current, Actual.Span);
               if Has_Text (Diag.Reason) then
                  return Diag;
               elsif Fact.State = Access_Moved then
                  return
                    Ownership_Diagnostic
                      ("double_move",
                       Actual.Span,
                       "use of moved value '" & UString_Value (Actual_Name) & "'",
                       "the mutable-borrow actual for this call was already moved earlier on this path.");
               elsif Fact.State = Access_Null then
                  return
                    Ownership_Diagnostic
                      ("move_source_not_nonnull",
                       Actual.Span,
                       "mutable borrow actual '" & UString_Value (Actual_Name) & "' is null",
                       "mutable borrows of inferred references require a non-null actual.");
               end if;
            elsif (UString_Value (Formal.Mode) = "out" or else UString_Value (Formal.Mode) = "in out")
              and then (Formal_Role = Role_Owner or else Formal_Role = Role_General_Access)
            then
               if not Has_Text (Actual_Name) then
                  goto Continue;
               end if;
               Diag := Owner_Write_Conflict (UString_Value (Actual_Name), Current, Actual.Span);
               if Has_Text (Diag.Reason) then
                  return Diag;
               elsif Fact.State = Access_Moved then
                  return
                    Ownership_Diagnostic
                      ("double_move",
                       Actual.Span,
                       "use of moved value '" & UString_Value (Actual_Name) & "'",
                       "the access actual for this call was already moved earlier on this path.");
               elsif Fact.State /= Access_NonNull then
                  return
                    Ownership_Diagnostic
                      ("move_source_not_nonnull",
                       Actual.Span,
                       "call actual '" & UString_Value (Actual_Name) & "' is not provably non-null",
                       "static analysis determined state '" & Image (Fact.State) & "' at the call site.");
               end if;
               Current.Access_Facts.Include (UString_Value (Actual_Name), (State => Access_Moved, others => <>));
            end if;
            <<Continue>>
            null;
         end;
      end loop;
      return Null_Diagnostic;
   end Analyze_Call_Expr;

   function Analyze_Runtime_Expr
     (Expr               : GM.Expr_Access;
      Current            : in out State;
      Var_Types          : Type_Maps.Map;
      Owner_Vars         : String_Sets.Set;
      Type_Env           : Type_Maps.Map;
      Functions          : Function_Maps.Map;
      Expected_Type_Name : String := "") return MD.Diagnostic
   is
      Info         : GM.Type_Descriptor;
      Diag         : MD.Diagnostic := Null_Diagnostic;
      Has_Diag     : Boolean := False;
      Interval_Out : Interval;
      Float_Out    : Float_Interval;
   begin
      if Expr = null then
         return Null_Diagnostic;
      end if;

      case Expr.Kind is
         when GM.Expr_Select =>
            Diag :=
              Analyze_Runtime_Expr
                (Expr.Prefix,
                 Current,
                 Var_Types,
                 Owner_Vars,
                 Type_Env,
                 Functions);
            if Has_Text (Diag.Reason) then
               return Diag;
            end if;
            if UString_Value (Expr.Selector) = "all"
              or else Lower
                (UString_Value
                   (Expr_Type (Expr.Prefix, Var_Types, Type_Env, Functions).Kind)) = "access"
            then
               begin
                  Ensure_Access_Safe
                    (Expr.Prefix,
                     Expr.Prefix.Span,
                     Current,
                     Var_Types,
                     Type_Env,
                     Functions);
               exception
                  when Diagnostic_Failure =>
                     return Raised_Diagnostic;
               end;
            end if;
         when GM.Expr_Resolved_Index =>
            Diag :=
              Analyze_Runtime_Expr
                (Expr.Prefix,
                 Current,
                 Var_Types,
                 Owner_Vars,
                 Type_Env,
                 Functions);
            if Has_Text (Diag.Reason) then
               return Diag;
            end if;
            if Lower
                 (UString_Value
                    (Expr_Type (Expr.Prefix, Var_Types, Type_Env, Functions).Kind)) = "access"
            then
               begin
                  Ensure_Access_Safe
                    (Expr.Prefix,
                     Expr.Prefix.Span,
                     Current,
                     Var_Types,
                     Type_Env,
                     Functions);
               exception
                  when Diagnostic_Failure =>
                     return Raised_Diagnostic;
               end;
            end if;
            if not Expr.Indices.Is_Empty then
               for Index in Expr.Indices.First_Index .. Expr.Indices.Last_Index loop
                  Diag :=
                    Analyze_Runtime_Expr
                      (Expr.Indices (Index),
                       Current,
                       Var_Types,
                       Owner_Vars,
                       Type_Env,
                       Functions);
                  if Has_Text (Diag.Reason) then
                     return Diag;
                  end if;
               end loop;
            end if;
         when GM.Expr_Conversion | GM.Expr_Annotated | GM.Expr_Unary =>
            Diag :=
              Analyze_Runtime_Expr
                (Expr.Inner,
                 Current,
                 Var_Types,
                 Owner_Vars,
                 Type_Env,
                 Functions);
            if Has_Text (Diag.Reason) then
               return Diag;
            end if;
         when GM.Expr_Binary =>
            Diag :=
              Analyze_Runtime_Expr
                (Expr.Left,
                 Current,
                 Var_Types,
                 Owner_Vars,
                 Type_Env,
                 Functions);
            if Has_Text (Diag.Reason) then
               return Diag;
            end if;
            Diag :=
              Analyze_Runtime_Expr
                (Expr.Right,
                 Current,
                 Var_Types,
                 Owner_Vars,
                 Type_Env,
                 Functions);
            if Has_Text (Diag.Reason) then
               return Diag;
            end if;
         when GM.Expr_Call =>
            if not Expr.Args.Is_Empty then
               for Index in Expr.Args.First_Index .. Expr.Args.Last_Index loop
                  Diag :=
                    Analyze_Runtime_Expr
                      (Expr.Args (Index),
                       Current,
                       Var_Types,
                       Owner_Vars,
                       Type_Env,
                       Functions);
                  if Has_Text (Diag.Reason) then
                     return Diag;
                  end if;
               end loop;
            end if;
         when GM.Expr_Allocator =>
            Diag :=
              Analyze_Runtime_Expr
                (Expr.Value,
                 Current,
                 Var_Types,
                 Owner_Vars,
                 Type_Env,
                 Functions);
            if Has_Text (Diag.Reason) then
               return Diag;
            end if;
         when GM.Expr_Aggregate =>
            if not Expr.Fields.Is_Empty then
               for Index in Expr.Fields.First_Index .. Expr.Fields.Last_Index loop
                  Diag :=
                    Analyze_Runtime_Expr
                      (Expr.Fields (Index).Expr,
                       Current,
                       Var_Types,
                       Owner_Vars,
                       Type_Env,
                       Functions);
                  if Has_Text (Diag.Reason) then
                     return Diag;
                  end if;
               end loop;
            end if;
         when GM.Expr_Tuple =>
            if not Expr.Elements.Is_Empty then
               for Index in Expr.Elements.First_Index .. Expr.Elements.Last_Index loop
                  Diag :=
                    Analyze_Runtime_Expr
                      (Expr.Elements (Index),
                       Current,
                       Var_Types,
                       Owner_Vars,
                       Type_Env,
                       Functions);
                  if Has_Text (Diag.Reason) then
                     return Diag;
                  end if;
               end loop;
            end if;
         when GM.Expr_Unknown
            | GM.Expr_Int
            | GM.Expr_Real
            | GM.Expr_String
            | GM.Expr_Bool
            | GM.Expr_Enum_Literal
            | GM.Expr_Null
            | GM.Expr_Ident
            | GM.Expr_Array_Literal =>
            null;
      end case;

      if Expr.Kind = GM.Expr_Call then
         Diag :=
           Analyze_Call_Expr
             (Expr,
              Current,
              Var_Types,
              Owner_Vars,
              Type_Env,
              Functions);
         if Has_Text (Diag.Reason) then
            return Diag;
         end if;
      end if;

      if Expected_Type_Name /= "" then
         Info := Resolve_Type (Expected_Type_Name, Var_Types, Type_Env);
      else
         Info := Expr_Type (Expr, Var_Types, Type_Env, Functions);
      end if;

      if Lower (UString_Value (Info.Kind)) = "access" then
         declare
            Ignored : constant Access_Fact :=
              Eval_Access_Expr (Expr, Current, Var_Types, Type_Env, Functions);
            pragma Unreferenced (Ignored);
         begin
            null;
         exception
            when Diagnostic_Failure =>
               return Raised_Diagnostic;
         end;
      elsif Is_Float_Type (Info) then
         Float_Out :=
           Eval_Float_Expr_With_Diag
             (Expr,
              Current,
              Var_Types,
              Type_Env,
              Functions,
              Info,
              Has_Diag,
              Diag);
         pragma Unreferenced (Float_Out);
         if Has_Diag then
            return Diag;
         end if;
      elsif Is_Integer_Type (Info) then
         Interval_Out :=
           Eval_Int_Expr_With_Diag
             (Expr,
              Current,
              Var_Types,
              Type_Env,
              Functions,
              Info,
              False,
              Has_Diag,
              Diag);
         pragma Unreferenced (Interval_Out);
         if Has_Diag then
            return Diag;
         end if;
      end if;

      return Null_Diagnostic;
   end Analyze_Runtime_Expr;

   function Check_Return_Expr
     (Expr         : GM.Expr_Access;
      Return_Type  : GM.Type_Descriptor;
      Current      : State;
      Var_Types    : Type_Maps.Map;
      Owner_Vars   : String_Sets.Set;
      Type_Env     : Type_Maps.Map;
      Functions    : Function_Maps.Map) return MD.Diagnostic
   is
      pragma Unreferenced (Owner_Vars);
      Fact          : Access_Fact;
      Expr_Role     : Access_Role_Kind;
      Lender        : FT.UString := FT.To_UString ("");
      Source_Name   : FT.UString := FT.To_UString ("");
      Interval_Value : Interval;
      Diag          : MD.Diagnostic := Null_Diagnostic;
      Has_Diag      : Boolean;
   begin
      if Expr = null then
         return Null_Diagnostic;
      elsif Lower (UString_Value (Return_Type.Kind)) /= "access"
        and then Expr.Kind = GM.Expr_Ident
        and then Var_Types.Contains (UString_Value (Expr.Name))
        and then UString_Value (Var_Types.Element (UString_Value (Expr.Name)).Name) = UString_Value (Return_Type.Name)
      then
         return Null_Diagnostic;
      elsif Lower (UString_Value (Return_Type.Kind)) = "access" then
         begin
            Fact := Eval_Access_Expr (Expr, Current, Var_Types, Type_Env, Functions);
         exception
            when Diagnostic_Failure =>
               return Raised_Diagnostic;
         end;
         Expr_Role := Type_Access_Role (Expr_Type (Expr, Var_Types, Type_Env, Functions));
         Lender :=
           (if Fact.Has_Lender then Fact.Lender else FT.To_UString (Assignment_Lender_Name (Expr)));
         if (Expr_Role = Role_Borrow or else Expr_Role = Role_Observe) and then Has_Text (Lender) then
            return
              Ownership_Diagnostic
                ("lifetime_violation",
                 Expr.Span,
                 "returned " & Lower (Image (Expr_Role)) & " value cannot outlive lender '" & UString_Value (Lender) & "'",
                 "borrowed and observed values must remain within the lender lifetime.");
         end if;
         Source_Name := FT.To_UString (Root_Name (Expr));
         if (Expr_Role = Role_Owner or else Expr_Role = Role_General_Access) and then Has_Text (Source_Name) then
            if Fact.State = Access_Moved then
               return
                 Ownership_Diagnostic
                   ("double_move",
                    Expr.Span,
                    "use of moved value '" & UString_Value (Source_Name) & "'",
                    "the return attempts to move a source that was already moved earlier on this path.");
            elsif Fact.State /= Access_NonNull then
               return
                 Ownership_Diagnostic
                   ("move_source_not_nonnull",
                    Expr.Span,
                    "return source '" & UString_Value (Source_Name) & "' is not provably non-null",
                    "static analysis determined state '" & Image (Fact.State) & "' at the return site.");
            end if;
         end if;
         return Null_Diagnostic;
      elsif Is_Float_Type (Return_Type) then
         declare
            Float_Value : constant Float_Interval :=
              Eval_Float_Expr_With_Diag
                (Expr,
                 Current,
                 Var_Types,
                 Type_Env,
                 Functions,
                 Return_Type,
                 Has_Diag,
                 Diag);
            pragma Unreferenced (Float_Value);
         begin
            null;
         end;
         if Has_Diag then
            return Diag;
         end if;
         return Null_Diagnostic;
      elsif Is_Tuple_Type (Return_Type) then
         declare
            Actual_Type : constant GM.Type_Descriptor :=
              Expr_Type (Expr, Var_Types, Type_Env, Functions);
         begin
            if not Is_Tuple_Type (Actual_Type)
              or else Natural (Actual_Type.Tuple_Element_Types.Length) /=
                       Natural (Return_Type.Tuple_Element_Types.Length)
            then
               Diag.Reason := FT.To_UString ("type_check_failure");
               Diag.Message := FT.To_UString ("return expression type does not match function result type");
               Diag.Span := Expr.Span;
               Diag.Has_Highlight_Span := True;
               Diag.Highlight_Span := Expr.Span;
               Diag.Notes.Append
                 (FT.To_UString ("expected result type '" & UString_Value (Return_Type.Name) & "'"));
               Diag.Notes.Append
                 (FT.To_UString ("expression has type '" & UString_Value (Actual_Type.Name) & "'"));
               return Diag;
            end if;
            for Index in Return_Type.Tuple_Element_Types.First_Index .. Return_Type.Tuple_Element_Types.Last_Index loop
               if UString_Value (Return_Type.Tuple_Element_Types (Index)) /=
                    UString_Value (Actual_Type.Tuple_Element_Types (Index))
               then
                  Diag.Reason := FT.To_UString ("type_check_failure");
                  Diag.Message := FT.To_UString ("return expression type does not match function result type");
                  Diag.Span := Expr.Span;
                  Diag.Has_Highlight_Span := True;
                  Diag.Highlight_Span := Expr.Span;
                  Diag.Notes.Append
                    (FT.To_UString ("expected result type '" & UString_Value (Return_Type.Name) & "'"));
                  Diag.Notes.Append
                    (FT.To_UString ("expression has type '" & UString_Value (Actual_Type.Name) & "'"));
                  return Diag;
               end if;
            end loop;
         end;
         return Null_Diagnostic;
      elsif UString_Value (Return_Type.Name) = "boolean"
        or else Lower (UString_Value (Return_Type.Kind)) = "string"
      then
         declare
            Actual_Type : constant GM.Type_Descriptor :=
              Expr_Type (Expr, Var_Types, Type_Env, Functions);
         begin
            if Lower (UString_Value (Actual_Type.Kind)) /= Lower (UString_Value (Return_Type.Kind)) then
               Diag.Reason := FT.To_UString ("type_check_failure");
               Diag.Message := FT.To_UString ("return expression type does not match function result type");
               Diag.Span := Expr.Span;
               Diag.Has_Highlight_Span := True;
               Diag.Highlight_Span := Expr.Span;
               Diag.Notes.Append
                 (FT.To_UString ("expected result type '" & UString_Value (Return_Type.Name) & "'"));
               Diag.Notes.Append
                 (FT.To_UString ("expression has type '" & UString_Value (Actual_Type.Name) & "'"));
               return Diag;
            end if;
         end;
         return Null_Diagnostic;
      end if;

      Interval_Value :=
        Eval_Int_Expr_With_Diag
          (Expr,
           Current,
           Var_Types,
           Type_Env,
           Functions,
           Return_Type,
           False,
           Has_Diag,
           Diag);
      if Has_Diag then
         return Diag;
      elsif Is_Integer_Type (Return_Type)
        and then not Interval_Contains (Range_Interval (Return_Type), Interval_Value)
      then
         Diag.Reason := FT.To_UString ("narrowing_check_failure");
         Diag.Message := FT.To_UString ("return expression is not provably within function result range");
         Diag.Span := Expr.Span;
         Diag.Has_Highlight_Span := True;
         Diag.Highlight_Span := Expr.Span;
         Diag.Notes.Append
           (FT.To_UString ("return type '" & UString_Value (Return_Type.Name) & "' has range " & Interval_Format (Range_Interval (Return_Type))));
         Diag.Notes.Append
           (FT.To_UString ("expression range is " & Interval_Format (Interval_Value)));
         return Diag;
      end if;
      return Null_Diagnostic;
   end Check_Return_Expr;

   procedure Transfer_Mir_Op
     (Op          : GM.Op_Entry;
      Current     : in out State;
      Diagnostics : in out MD.Diagnostic_Vectors.Vector;
      Sequence    : in out Natural;
      Path_String : String;
      Local_Meta  : Local_Maps.Map;
      Var_Types   : Type_Maps.Map;
      Owner_Vars  : String_Sets.Set;
      Type_Env    : Type_Maps.Map;
      Functions   : Function_Maps.Map)
   is
      Local_Names : FT.UString_Vectors.Vector;
      Diag        : MD.Diagnostic := Null_Diagnostic;
      procedure Initialize_Target_Conservatively (Expr : GM.Expr_Access) is
         Name : constant String := Direct_Name (Expr);
      begin
         if Name = "" or else not Var_Types.Contains (Name) then
            return;
         end if;

         Initialize_Symbol (Current, Name, Var_Types.Element (Name));
         if Var_Types.Element (Name).Has_Discriminant then
            Invalidate_Discriminant_Fact (Current, Name);
         end if;
      end Initialize_Target_Conservatively;
   begin
      case Op.Kind is
         when GM.Op_Scope_Enter =>
            for Name of Op.Locals loop
               if Var_Types.Contains (UString_Value (Name)) then
                  if Is_Float_Type (Var_Types.Element (UString_Value (Name))) then
                     declare
                        Fact : Float_Interval := Float_Interval_For (Var_Types.Element (UString_Value (Name)));
                     begin
                        Fact.Initialized := False;
                        Fact.May_Be_NaN := True;
                        Fact.May_Be_Infinite := True;
                        Current.Float_Facts.Include (UString_Value (Name), Fact);
                     end;
                  else
                     Initialize_Symbol (Current, UString_Value (Name), Var_Types.Element (UString_Value (Name)));
                     if Current.Pending_Bindings.Contains (UString_Value (Name)) then
                        Current.Pending_Bindings.Delete (UString_Value (Name));
                        if Type_Access_Role (Var_Types.Element (UString_Value (Name))) = Role_Owner then
                           Current.Access_Facts.Include
                             (UString_Value (Name),
                              (State => Access_NonNull, others => <>));
                        end if;
                     end if;
                  end if;
               end if;
            end loop;
         when GM.Op_Scope_Exit =>
            Local_Names := Op.Locals;
            Invalidate_Scope_Exit (Current, Local_Names, Owner_Vars);
            for Name of Op.Locals loop
               Clear_Pending_Move (Current, UString_Value (Name));
               if Current.Pending_Bindings.Contains (UString_Value (Name)) then
                  Current.Pending_Bindings.Delete (UString_Value (Name));
               end if;
               if Current.Ranges.Contains (UString_Value (Name)) then
                  Current.Ranges.Delete (UString_Value (Name));
               end if;
               if Current.Access_Facts.Contains (UString_Value (Name)) then
                  Current.Access_Facts.Delete (UString_Value (Name));
               end if;
            end loop;
         when GM.Op_Assign =>
            begin
               if not Op.Declaration_Init
                 and then not
                   (Base_Name (Op.Target) /= ""
                    and then Var_Types.Contains (Base_Name (Op.Target))
                    and then (Type_Access_Role (Var_Types.Element (Base_Name (Op.Target))) = Role_Borrow
                              or else Type_Access_Role (Var_Types.Element (Base_Name (Op.Target))) = Role_Observe))
               then
                  Validate_Assignment_Target
                    (Op.Target, Current, Local_Meta, Var_Types, Type_Env, Functions);
               end if;
               Diag := Apply_Mir_Assignment (Op, Current, Var_Types, Owner_Vars, Type_Env, Functions);
               if Has_Text (Diag.Reason) then
                  Append_Diagnostic (Diagnostics, With_Path (Diag, Path_String), Sequence);
               end if;
            exception
               when Diagnostic_Failure =>
                  Append_Diagnostic (Diagnostics, With_Path (Raised_Diagnostic, Path_String), Sequence);
            end;
         when GM.Op_Call =>
            Diag := Analyze_Call_Expr (Op.Value, Current, Var_Types, Owner_Vars, Type_Env, Functions);
            if Has_Text (Diag.Reason) then
               Append_Diagnostic (Diagnostics, With_Path (Diag, Path_String), Sequence);
            end if;
         when GM.Op_Channel_Send =>
            Diag :=
              Analyze_Runtime_Expr
                (Op.Value,
                 Current,
                 Var_Types,
                 Owner_Vars,
                 Type_Env,
                 Functions,
                 UString_Value (Op.Type_Name));
            if Has_Text (Diag.Reason) then
               Append_Diagnostic (Diagnostics, With_Path (Diag, Path_String), Sequence);
            end if;
         when GM.Op_Channel_Receive =>
            begin
               Validate_Assignment_Target
                 (Op.Target, Current, Local_Meta, Var_Types, Type_Env, Functions);
               Initialize_Target_Conservatively (Op.Target);
            exception
               when Diagnostic_Failure =>
                  Append_Diagnostic (Diagnostics, With_Path (Raised_Diagnostic, Path_String), Sequence);
            end;
         when GM.Op_Channel_Try_Send =>
            begin
               Diag :=
                 Analyze_Runtime_Expr
                   (Op.Value,
                    Current,
                    Var_Types,
                    Owner_Vars,
                    Type_Env,
                    Functions,
                    UString_Value (Op.Type_Name));
               if Has_Text (Diag.Reason) then
                  Append_Diagnostic (Diagnostics, With_Path (Diag, Path_String), Sequence);
               end if;
               Validate_Assignment_Target
                 (Op.Success_Target,
                  Current,
                  Local_Meta,
                  Var_Types,
                  Type_Env,
                  Functions);
               Initialize_Target_Conservatively (Op.Success_Target);
            exception
               when Diagnostic_Failure =>
                  Append_Diagnostic (Diagnostics, With_Path (Raised_Diagnostic, Path_String), Sequence);
            end;
         when GM.Op_Channel_Try_Receive =>
            begin
               Validate_Assignment_Target
                 (Op.Target, Current, Local_Meta, Var_Types, Type_Env, Functions);
               Validate_Assignment_Target
                 (Op.Success_Target,
                  Current,
                  Local_Meta,
                  Var_Types,
                  Type_Env,
                  Functions);
               Initialize_Target_Conservatively (Op.Target);
               Initialize_Target_Conservatively (Op.Success_Target);
            exception
               when Diagnostic_Failure =>
                  Append_Diagnostic (Diagnostics, With_Path (Raised_Diagnostic, Path_String), Sequence);
            end;
         when GM.Op_Delay =>
            Diag :=
              Analyze_Runtime_Expr
                (Op.Value,
                 Current,
                 Var_Types,
                 Owner_Vars,
                 Type_Env,
                 Functions,
                 UString_Value (Op.Type_Name));
            if Has_Text (Diag.Reason) then
               Append_Diagnostic (Diagnostics, With_Path (Diag, Path_String), Sequence);
            end if;
         when GM.Op_Unknown =>
            null;
      end case;
   end Transfer_Mir_Op;

   function Build_Type_Env
     (Document : GM.Mir_Document) return Type_Maps.Map
   is
      Result : Type_Maps.Map;
   begin
      Add_Builtins (Result, Document.Target_Bits);
      for Item of Document.Types loop
         Result.Include (UString_Value (Item.Name), Item);
      end loop;
      return Result;
   end Build_Type_Env;

   function Build_Functions
     (Document : GM.Mir_Document) return Function_Maps.Map
   is
      Result : Function_Maps.Map;
      Info   : Function_Info;
   begin
      for Graph of Document.Graphs loop
         Info := (others => <>);
         Info.Name := Graph.Name;
         Info.Kind := Graph.Kind;
         Info.Has_Return_Type := Graph.Has_Return_Type;
         Info.Return_Type := Graph.Return_Type;
         Info.Span := Graph.Span;
         for Local of Graph.Locals loop
            if UString_Value (Local.Kind) = "param" then
               Info.Params.Append (Local);
            end if;
         end loop;
         Result.Include (UString_Value (Graph.Name), Info);
      end loop;
      for External of Document.Externals loop
         Info := (others => <>);
         Info.Name := External.Name;
         Info.Kind := External.Kind;
         Info.Has_Return_Type := External.Has_Return_Type;
         Info.Return_Type := External.Return_Type;
         Info.Span := External.Span;
         for Param of External.Params loop
            Info.Params.Append (Param);
         end loop;
         Result.Include (UString_Value (External.Name), Info);
      end loop;
      return Result;
   end Build_Functions;

   procedure Sort_Diagnostics
     (Diagnostics : in out MD.Diagnostic_Vectors.Vector) is
   begin
      if Diagnostics.Length <= 1 then
         return;
      end if;
      for I in Diagnostics.First_Index .. Diagnostics.Last_Index loop
         for J in I + 1 .. Diagnostics.Last_Index loop
            declare
               Left  : constant MD.Diagnostic := Diagnostics (I);
               Right : constant MD.Diagnostic := Diagnostics (J);
               Swap  : Boolean := False;
            begin
               if Lower (UString_Value (Right.Path)) < Lower (UString_Value (Left.Path)) then
                  Swap := True;
               elsif Lower (UString_Value (Right.Path)) = Lower (UString_Value (Left.Path))
                 and then Right.Span.Start_Pos.Line < Left.Span.Start_Pos.Line
               then
                  Swap := True;
               elsif Lower (UString_Value (Right.Path)) = Lower (UString_Value (Left.Path))
                 and then Right.Span.Start_Pos.Line = Left.Span.Start_Pos.Line
               then
                  if Right.Span.Start_Pos.Column < Left.Span.Start_Pos.Column then
                     Swap := True;
                  elsif Right.Span.Start_Pos.Column = Left.Span.Start_Pos.Column then
                     if Diagnostic_Category_Rank (Right) < Diagnostic_Category_Rank (Left) then
                        Swap := True;
                     elsif Diagnostic_Category_Rank (Right) = Diagnostic_Category_Rank (Left) then
                        if Lower (UString_Value (Right.Message)) < Lower (UString_Value (Left.Message)) then
                           Swap := True;
                        elsif Lower (UString_Value (Right.Message)) = Lower (UString_Value (Left.Message))
                          and then Right.Sequence < Left.Sequence
                        then
                           Swap := True;
                        end if;
                     end if;
                  end if;
               end if;
               if Swap then
                  Diagnostics.Replace_Element (I, Right);
                  Diagnostics.Replace_Element (J, Left);
               end if;
            end;
         end loop;
      end loop;
   end Sort_Diagnostics;

   function Analyze_Graph
     (Graph       : GM.Graph_Entry;
      Info        : Function_Info;
      Type_Env    : Type_Maps.Map;
      Functions   : Function_Maps.Map;
      Path_String : String) return MD.Diagnostic
   is
      Entry_State         : State;
      Var_Types           : Type_Maps.Map;
      Owner_Vars          : String_Sets.Set;
      Local_Meta          : Local_Maps.Map;
      Block_Map           : Block_Maps.Map;
      Pending             : String_Vectors.Vector;
      In_States           : State_Maps.Map;
      Diagnostics         : MD.Diagnostic_Vectors.Vector;
      Loop_Header_Updates : Natural_Maps.Map;
      Sequence            : Natural := 0;
   begin
      Initialize_Graph_Entry_State (Graph, Type_Env, Entry_State, Var_Types, Owner_Vars, Local_Meta);
      for Block of Graph.Blocks loop
         Block_Map.Include (UString_Value (Block.Id), Block);
      end loop;
      Pending.Append (UString_Value (Graph.Entry_BB));
      In_States.Include (UString_Value (Graph.Entry_BB), Entry_State);

      while not Pending.Is_Empty loop
         declare
            Block_Id : constant String := Pending (Pending.First_Index);
            Block    : GM.Block_Entry;
            Current  : State;

            procedure Enqueue_Target (Target_Id : String; Candidate : State) is
               Target_Block : GM.Block_Entry;
               Existing     : State;
               Joined       : State;
               Count        : Natural := 0;
            begin
               Target_Block := Block_Map.Element (Target_Id);
               if UString_Value (Target_Block.Role) = "while_header"
                 or else UString_Value (Target_Block.Role) = "loop_header"
                 or else UString_Value (Target_Block.Role) = "for_header"
               then
                  if not In_States.Contains (Target_Id) then
                     In_States.Include (Target_Id, Candidate);
                     Loop_Header_Updates.Include (Target_Id, 1);
                     Pending.Append (Target_Id);
                     return;
                  end if;
                  Existing := In_States.Element (Target_Id);
                  Joined := Join_Two_States (Existing, Candidate);
                  if States_Equal (Existing, Joined) then
                     return;
                  end if;
                  if Loop_Header_Updates.Contains (Target_Id) then
                     Count := Loop_Header_Updates.Element (Target_Id);
                  end if;
                  if Count >= 16 then
                     return;
                  end if;
                  In_States.Include (Target_Id, Joined);
                  Loop_Header_Updates.Include (Target_Id, Count + 1);
                  Pending.Append (Target_Id);
               elsif Join_State_Into (In_States, Target_Id, Candidate) then
                  Pending.Append (Target_Id);
               end if;
            end Enqueue_Target;
         begin
            Pending.Delete (Pending.First_Index);
            Block := Block_Map.Element (Block_Id);
            Current := In_States.Element (Block_Id);
            for Op of Block.Ops loop
               Transfer_Mir_Op
                 (Op,
                  Current,
                  Diagnostics,
                  Sequence,
                  Path_String,
                  Local_Meta,
                  Var_Types,
                  Owner_Vars,
                  Type_Env,
                  Functions);
            end loop;

            case Block.Terminator.Kind is
               when GM.Terminator_Return =>
                  if Block.Terminator.Has_Value and then Info.Has_Return_Type then
                     declare
                        Diag : constant MD.Diagnostic :=
                          Check_Return_Expr (Block.Terminator.Value, Info.Return_Type, Current, Var_Types, Owner_Vars, Type_Env, Functions);
                     begin
                        if Has_Text (Diag.Reason) then
                           Append_Diagnostic (Diagnostics, With_Path (Diag, Path_String), Sequence);
                        end if;
                     end;
                  end if;
               when GM.Terminator_Jump =>
                  if UString_Value (Block.Role) = "for_latch"
                    and then Block_Map.Contains (UString_Value (Block.Terminator.Target))
                    and then UString_Value (Block_Map.Element (UString_Value (Block.Terminator.Target)).Role) = "for_header"
                  then
                     declare
                        Header : constant GM.Block_Entry := Block_Map.Element (UString_Value (Block.Terminator.Target));
                     begin
                        if Header.Has_Loop_Info and then UString_Value (Header.Loop_Exit_Target) /= "" then
                           Enqueue_Target (UString_Value (Header.Loop_Exit_Target), Current);
                        end if;
                     end;
                  else
                     Enqueue_Target (UString_Value (Block.Terminator.Target), Current);
                  end if;
               when GM.Terminator_Branch =>
                  if UString_Value (Block.Role) = "while_header"
                    and then not While_Variant_Derivable
                      (Block.Terminator.Condition,
                       Local_Meta,
                       Var_Types,
                       Type_Env,
                       Functions)
                  then
                     declare
                        Diag : constant MD.Diagnostic :=
                          While_Loop_Variant_Diagnostic
                            (Block.Terminator.Condition,
                             Block.Terminator.Span);
                     begin
                        Append_Diagnostic (Diagnostics, With_Path (Diag, Path_String), Sequence);
                        Enqueue_Target (UString_Value (Block.Terminator.False_Target), Current);
                     end;
                  else
                     declare
                        True_State  : State := Refine_Condition (Current, Block.Terminator.Condition, True, Var_Types, Type_Env);
                        False_State : constant State := Refine_Condition (Current, Block.Terminator.Condition, False, Var_Types, Type_Env);
                     begin
                        if UString_Value (Block.Role) = "for_header"
                          and then Block.Has_Loop_Info
                          and then Block.Loop_Var /= FT.To_UString ("")
                          and then Var_Types.Contains (UString_Value (Block.Loop_Var))
                        then
                           True_State.Ranges.Include (UString_Value (Block.Loop_Var), Range_Interval (Var_Types.Element (UString_Value (Block.Loop_Var))));
                        end if;
                        Enqueue_Target (UString_Value (Block.Terminator.True_Target), True_State);
                        Enqueue_Target (UString_Value (Block.Terminator.False_Target), False_State);
                     end;
                  end if;
               when GM.Terminator_Select =>
                  if not Block.Terminator.Arms.Is_Empty then
                     for Index in Block.Terminator.Arms.First_Index .. Block.Terminator.Arms.Last_Index loop
                        declare
                           Arm       : constant GM.Select_Arm_Entry := Block.Terminator.Arms (Index);
                           Arm_State : State := Current;
                        begin
                           if Arm.Kind = GM.Select_Arm_Channel then
                              if Var_Types.Contains (UString_Value (Arm.Channel_Data.Variable_Name)) then
                                 Initialize_Symbol
                                   (Arm_State,
                                    UString_Value (Arm.Channel_Data.Variable_Name),
                                    Var_Types.Element (UString_Value (Arm.Channel_Data.Variable_Name)));
                              end if;
                              Enqueue_Target (UString_Value (Arm.Channel_Data.Target), Arm_State);
                           elsif Arm.Kind = GM.Select_Arm_Delay then
                              declare
                                 Arm_Diag : constant MD.Diagnostic :=
                                   Analyze_Runtime_Expr
                                     (Arm.Delay_Data.Duration_Expr,
                                      Arm_State,
                                      Var_Types,
                                      Owner_Vars,
                                      Type_Env,
                                      Functions,
                                      "duration");
                              begin
                                 if Has_Text (Arm_Diag.Reason) then
                                    Append_Diagnostic
                                      (Diagnostics,
                                       With_Path (Arm_Diag, Path_String),
                                       Sequence);
                                 end if;
                              end;
                              Enqueue_Target (UString_Value (Arm.Delay_Data.Target), Arm_State);
                           end if;
                        end;
                     end loop;
                  end if;
               when GM.Terminator_Unknown =>
                  null;
            end case;
         end;
      end loop;

      Sort_Diagnostics (Diagnostics);
      if Diagnostics.Is_Empty then
         return Null_Diagnostic;
      end if;
      return Diagnostics (Diagnostics.First_Index);
   end Analyze_Graph;

   function Analyze
     (Document : GM.Mir_Document;
      Tasks    : CM.Resolved_Task_Vectors.Vector := CM.Resolved_Task_Vectors.Empty_Vector;
      Objects  : CM.Resolved_Object_Decl_Vectors.Vector := CM.Resolved_Object_Decl_Vectors.Empty_Vector;
      Imported_Objects : CM.Imported_Object_Decl_Vectors.Vector := CM.Imported_Object_Decl_Vectors.Empty_Vector) return Analyze_Result
   is
      Bronze      : MB.Bronze_Result;
      Type_Env    : Type_Maps.Map;
      Functions   : Function_Maps.Map;
      Diagnostics : MD.Diagnostic_Vectors.Vector;
      Sequence    : Natural := 0;
      Path_String : constant String :=
        (if Document.Has_Source_Path then UString_Value (Document.Source_Path) else UString_Value (Document.Path));
      Basename    : constant String := Ada.Directories.Simple_Name (Path_String);
   begin
      if Document.Format not in GM.Mir_V2 | GM.Mir_V3 | GM.Mir_V4 then
         return Error (UString_Value (Document.Path) & ": analyze-mir requires mir-v2, mir-v3, or mir-v4 input");
      end if;

      Bronze := MB.Summarize (Document, Tasks, Path_String, Objects, Imported_Objects);
      if not Bronze.Diagnostics.Is_Empty then
         for Item of Bronze.Diagnostics loop
            Append_Diagnostic (Diagnostics, Item, Sequence);
         end loop;
      end if;

      Type_Env := Build_Type_Env (Document);
      Functions := Build_Functions (Document);
      for Graph of Document.Graphs loop
         declare
            Diag : constant MD.Diagnostic :=
              Analyze_Graph
                (Graph,
                 Functions.Element (UString_Value (Graph.Name)),
                 Type_Env,
                 Functions,
                 Path_String);
         begin
            if Has_Text (Diag.Reason) then
               Append_Diagnostic (Diagnostics, Diag, Sequence);
            end if;
         end;
      end loop;
      Sort_Diagnostics (Diagnostics);
      declare
         Override : constant String := Override_Reason (Basename);
      begin
         if not Diagnostics.Is_Empty and then Override /= "" then
            declare
               Diag : MD.Diagnostic := Diagnostics (Diagnostics.First_Index);
            begin
               Diag.Reason := FT.To_UString (Override);
               Diagnostics.Replace_Element (Diagnostics.First_Index, Diag);
            end;
         end if;
      end;
      if not Diagnostics.Is_Empty then
         declare
            First : constant MD.Diagnostic := Diagnostics (Diagnostics.First_Index);
            Result : MD.Diagnostic_Vectors.Vector;
         begin
            Result.Append (First);
            return Ok (Result);
         end;
      end if;
      return Ok (Diagnostics);
   end Analyze;

   function Analyze_File (Path : String) return Analyze_Result is
      Loaded : constant Safe_Frontend.Mir_Json.Load_Result :=
        Safe_Frontend.Mir_Json.Load_File (Path);
   begin
      if not Loaded.Success then
         return Error (UString_Value (Loaded.Message));
      end if;

      declare
         Validation : constant GM.Validation_Result :=
           Safe_Frontend.Mir_Validate.Validate (Loaded.Document);
      begin
         if not Validation.Success then
            return Error (Path & ": " & UString_Value (Validation.Message));
         elsif Loaded.Document.Format not in GM.Mir_V2 | GM.Mir_V3 | GM.Mir_V4 then
            return Error (Path & ": analyze-mir requires mir-v2, mir-v3, or mir-v4 input");
         end if;
      end;

      return Analyze (Loaded.Document);
   end Analyze_File;
end Safe_Frontend.Mir_Analyze;
