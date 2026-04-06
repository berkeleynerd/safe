with Ada.Containers.Indefinite_Vectors;
with Safe_Frontend.Mir_Diagnostics;
with Safe_Frontend.Mir_Model;
with Safe_Frontend.Types;

package Safe_Frontend.Check_Model is
   package FT renames Safe_Frontend.Types;
   package MD renames Safe_Frontend.Mir_Diagnostics;
   package GM renames Safe_Frontend.Mir_Model;

   subtype Wide_Integer is Long_Long_Long_Integer;

   type Type_Spec;
   type Type_Spec_Access is access all Type_Spec;

   package Type_Spec_Access_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Type_Spec_Access);

   type Expr_Kind is
     (Expr_Unknown,
      Expr_Int,
      Expr_Real,
      Expr_String,
      Expr_Bool,
      Expr_Enum_Literal,
      Expr_Null,
      Expr_Ident,
      Expr_Select,
      Expr_Apply,
      Expr_Resolved_Index,
      Expr_Conversion,
      Expr_Call,
      Expr_Allocator,
      Expr_Aggregate,
      Expr_Array_Literal,
      Expr_Tuple,
      Expr_Annotated,
      Expr_Some,
      Expr_None,
      Expr_Try,
      Expr_Unary,
      Expr_Binary,
      Expr_Subtype_Indication);

   type Expr_Node;
   type Expr_Access is access all Expr_Node;

   package Expr_Access_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Expr_Access);

   type Aggregate_Field is record
      Field_Name : FT.UString := FT.To_UString ("");
      Expr       : Expr_Access := null;
      Span       : FT.Source_Span := FT.Null_Span;
   end record;

   package Aggregate_Field_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Aggregate_Field);

   type Expr_Node is record
      Kind             : Expr_Kind := Expr_Unknown;
      Span             : FT.Source_Span := FT.Null_Span;
      Type_Name        : FT.UString := FT.To_UString ("");
      Text             : FT.UString := FT.To_UString ("");
      Int_Value        : Wide_Integer := 0;
      Bool_Value       : Boolean := False;
      Name             : FT.UString := FT.To_UString ("");
      Selector         : FT.UString := FT.To_UString ("");
      Operator         : FT.UString := FT.To_UString ("");
      Not_Null         : Boolean := False;
      Is_All           : Boolean := False;
      Is_Constant      : Boolean := False;
      Anonymous        : Boolean := False;
      Prefix           : Expr_Access := null;
      Callee           : Expr_Access := null;
      Inner            : Expr_Access := null;
      Left             : Expr_Access := null;
      Right            : Expr_Access := null;
      Value            : Expr_Access := null;
      Target           : Expr_Access := null;
      Args             : Expr_Access_Vectors.Vector;
      Fields           : Aggregate_Field_Vectors.Vector;
      Elements         : Expr_Access_Vectors.Vector;
      Generic_Args     : Type_Spec_Access_Vectors.Vector;
      Subtype_Spec     : Type_Spec_Access := null;
      Has_Call_Span    : Boolean := False;
      Call_Span        : FT.Source_Span := FT.Null_Span;
   end record;

   type Generic_Formal is record
      Name            : FT.UString := FT.To_UString ("");
      Has_Constraint  : Boolean := False;
      Constraint_Name : FT.UString := FT.To_UString ("");
      Span            : FT.Source_Span := FT.Null_Span;
   end record;

   package Generic_Formal_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Generic_Formal);

   type Type_Spec_Kind is
     (Type_Spec_Unknown,
      Type_Spec_Name,
      Type_Spec_Binary,
      Type_Spec_Tuple,
      Type_Spec_List,
      Type_Spec_Map,
      Type_Spec_Growable_Array,
      Type_Spec_Optional,
      Type_Spec_Subtype_Indication,
      Type_Spec_Access_Def);

   type Constraint_Association is record
      Is_Named : Boolean := False;
      Name     : FT.UString := FT.To_UString ("");
      Value    : Expr_Access := null;
      Span     : FT.Source_Span := FT.Null_Span;
   end record;

   package Constraint_Association_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Constraint_Association);

   type Type_Spec is record
      Kind        : Type_Spec_Kind := Type_Spec_Unknown;
      Span        : FT.Source_Span := FT.Null_Span;
      Name        : FT.UString := FT.To_UString ("");
      Not_Null    : Boolean := False;
      Is_All      : Boolean := False;
      Is_Constant : Boolean := False;
      Anonymous   : Boolean := False;
      Target_Name : Expr_Access := null;
      Binary_Width_Expr : Expr_Access := null;
      Element_Type : Type_Spec_Access := null;
      Key_Type : Type_Spec_Access := null;
      Value_Type : Type_Spec_Access := null;
      Tuple_Elements : Type_Spec_Access_Vectors.Vector;
      Generic_Args : Type_Spec_Access_Vectors.Vector;
      Has_Range_Constraint : Boolean := False;
      Range_Low            : Expr_Access := null;
      Range_High           : Expr_Access := null;
      Constraints : Constraint_Association_Vectors.Vector;
   end record;

   type Discrete_Range_Kind is (Range_Unknown, Range_Subtype, Range_Explicit);

   type Discrete_Range is record
      Kind      : Discrete_Range_Kind := Range_Unknown;
      Span      : FT.Source_Span := FT.Null_Span;
      Name_Expr : Expr_Access := null;
      Low_Expr  : Expr_Access := null;
      High_Expr : Expr_Access := null;
   end record;

   type Parameter_Spec is record
      Names      : FT.UString_Vectors.Vector;
      Mode       : FT.UString := FT.To_UString ("in");
      Param_Type : Type_Spec;
      Span       : FT.Source_Span := FT.Null_Span;
   end record;

   package Parameter_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Parameter_Spec);

   type Subprogram_Spec is record
      Kind                  : FT.UString := FT.To_UString ("");
      Name                  : FT.UString := FT.To_UString ("");
      Generic_Formals       : Generic_Formal_Vectors.Vector;
      Has_Receiver          : Boolean := False;
      Receiver              : Parameter_Spec;
      Params                : Parameter_Vectors.Vector;
      Has_Return_Type       : Boolean := False;
      Return_Type           : Type_Spec;
      Return_Is_Access_Def  : Boolean := False;
      Span                  : FT.Source_Span := FT.Null_Span;
   end record;

   package Subprogram_Spec_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Subprogram_Spec);

   type Static_Value_Kind is
     (Static_Value_None,
      Static_Value_Integer,
      Static_Value_Boolean,
      Static_Value_Character,
      Static_Value_Enum);

   type Static_Value is record
      Kind       : Static_Value_Kind := Static_Value_None;
      Int_Value  : Wide_Integer := 0;
      Bool_Value : Boolean := False;
      Text       : FT.UString := FT.To_UString ("");
      Type_Name  : FT.UString := FT.To_UString ("");
   end record;

   type Object_Decl is record
      Names           : FT.UString_Vectors.Vector;
      Decl_Type       : Type_Spec;
      Type_Info       : GM.Type_Descriptor;
      Is_Shared       : Boolean := False;
      Is_Constant     : Boolean := False;
      Has_Initializer : Boolean := False;
      Has_Implicit_Default_Init : Boolean := False;
      Initializer     : Expr_Access := null;
      Span            : FT.Source_Span := FT.Null_Span;
      Is_Public       : Boolean := False;
   end record;

   package Object_Decl_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Object_Decl);

   type Component_Decl is record
      Names      : FT.UString_Vectors.Vector;
      Field_Type : Type_Spec;
      Span       : FT.Source_Span := FT.Null_Span;
   end record;

   package Component_Decl_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Component_Decl);

   type Discriminant_Spec is record
      Name         : FT.UString := FT.To_UString ("");
      Disc_Type    : Type_Spec;
      Has_Default  : Boolean := False;
      Default_Expr : Expr_Access := null;
      Span         : FT.Source_Span := FT.Null_Span;
   end record;

   package Discriminant_Spec_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Discriminant_Spec);

   type Variant_Alternative is record
      When_Value : Boolean := False;
      Is_Others  : Boolean := False;
      Choice_Expr : Expr_Access := null;
      Components : Component_Decl_Vectors.Vector;
      Span       : FT.Source_Span := FT.Null_Span;
   end record;

   package Variant_Alternative_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Variant_Alternative);

   type Sum_Variant_Decl is record
      Name       : FT.UString := FT.To_UString ("");
      Components : Component_Decl_Vectors.Vector;
      Span       : FT.Source_Span := FT.Null_Span;
   end record;

   package Sum_Variant_Decl_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Sum_Variant_Decl);

   type Array_Index_Kind is (Array_Index_Unknown, Array_Index_Subtype, Array_Index_Range);

   type Array_Index is record
      Kind      : Array_Index_Kind := Array_Index_Unknown;
      Span      : FT.Source_Span := FT.Null_Span;
      Name_Expr : Expr_Access := null;
      Low_Expr  : Expr_Access := null;
      High_Expr : Expr_Access := null;
   end record;

   package Array_Index_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Array_Index);

   type Type_Decl_Kind is
     (Type_Decl_Unknown,
      Type_Decl_Incomplete,
      Type_Decl_Interface,
      Type_Decl_Integer,
      Type_Decl_Binary,
      Type_Decl_Float,
      Type_Decl_Enumeration,
      Type_Decl_Constrained_Array,
      Type_Decl_Unconstrained_Array,
      Type_Decl_Growable_Array,
      Type_Decl_Sum,
      Type_Decl_Record,
      Type_Decl_Access);

   type Type_Decl is record
      Is_Public      : Boolean := False;
      Name           : FT.UString := FT.To_UString ("");
      Generic_Formals : Generic_Formal_Vectors.Vector;
      Kind           : Type_Decl_Kind := Type_Decl_Unknown;
      Span           : FT.Source_Span := FT.Null_Span;
      Digits_Expr    : Expr_Access := null;
      Binary_Width_Expr : Expr_Access := null;
      Enum_Literals  : FT.UString_Vectors.Vector;
      Low_Expr       : Expr_Access := null;
      High_Expr      : Expr_Access := null;
      Indexes        : Array_Index_Vectors.Vector;
      Component_Type : Type_Spec;
      Components     : Component_Decl_Vectors.Vector;
      Sum_Variants   : Sum_Variant_Decl_Vectors.Vector;
      Interface_Members : Subprogram_Spec_Vectors.Vector;
      Has_Discriminant : Boolean := False;
      Discriminant     : Discriminant_Spec;
      Discriminants    : Discriminant_Spec_Vectors.Vector;
      Variant_Discriminant_Name : FT.UString := FT.To_UString ("");
      Variants         : Variant_Alternative_Vectors.Vector;
      Access_Type    : Type_Spec;
   end record;

   type Subtype_Decl is record
      Is_Public     : Boolean := False;
      Name          : FT.UString := FT.To_UString ("");
      Subtype_Mark  : Type_Spec;
      Span          : FT.Source_Span := FT.Null_Span;
   end record;

   type Statement;
   type Statement_Access is access all Statement;

   package Statement_Access_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Statement_Access);

   type Elsif_Part is record
      Condition  : Expr_Access := null;
      Statements : Statement_Access_Vectors.Vector;
      Span       : FT.Source_Span := FT.Null_Span;
   end record;

   package Elsif_Part_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Elsif_Part);

   type Case_Arm is record
      Is_Others  : Boolean := False;
      Choice     : Expr_Access := null;
      Statements : Statement_Access_Vectors.Vector;
      Span       : FT.Source_Span := FT.Null_Span;
   end record;

   package Case_Arm_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Case_Arm);

   type Match_Arm_Kind is
     (Match_Arm_Unknown,
      Match_Arm_Ok,
      Match_Arm_Fail,
      Match_Arm_Variant);

   type Match_Arm is record
      Kind         : Match_Arm_Kind := Match_Arm_Unknown;
      Variant_Name : FT.UString := FT.To_UString ("");
      Binders      : FT.UString_Vectors.Vector;
      Statements   : Statement_Access_Vectors.Vector;
      Span         : FT.Source_Span := FT.Null_Span;
   end record;

   package Match_Arm_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Match_Arm);

   type Select_Arm_Kind is
     (Select_Arm_Unknown,
      Select_Arm_Channel,
      Select_Arm_Delay);

   type Channel_Select_Arm is record
      Variable_Name : FT.UString := FT.To_UString ("");
      Subtype_Mark  : Type_Spec;
      Type_Info     : GM.Type_Descriptor;
      Channel_Name  : Expr_Access := null;
      Statements    : Statement_Access_Vectors.Vector;
      Scope_Id      : FT.UString := FT.To_UString ("");
      Local_Id      : FT.UString := FT.To_UString ("");
      Span          : FT.Source_Span := FT.Null_Span;
   end record;

   type Delay_Select_Arm is record
      Duration_Expr : Expr_Access := null;
      Statements    : Statement_Access_Vectors.Vector;
      Scope_Id      : FT.UString := FT.To_UString ("");
      Span          : FT.Source_Span := FT.Null_Span;
   end record;

   type Select_Arm is record
      Kind         : Select_Arm_Kind := Select_Arm_Unknown;
      Channel_Data : Channel_Select_Arm;
      Delay_Data   : Delay_Select_Arm;
      Span         : FT.Source_Span := FT.Null_Span;
   end record;

   package Select_Arm_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Select_Arm);

   type Statement_Kind is
     (Stmt_Unknown,
      Stmt_Object_Decl,
      Stmt_Destructure_Decl,
      Stmt_Assign,
      Stmt_Call,
      Stmt_Return,
      Stmt_If,
      Stmt_Case,
      Stmt_While,
      Stmt_For,
      Stmt_Loop,
      Stmt_Exit,
      Stmt_Send,
      Stmt_Receive,
      Stmt_Try_Send,
      Stmt_Try_Receive,
      Stmt_Match,
      Stmt_Select,
      Stmt_Delay);

   type Destructure_Decl is record
      Names           : FT.UString_Vectors.Vector;
      Decl_Type       : Type_Spec;
      Type_Info       : GM.Type_Descriptor;
      Temp_Name       : FT.UString := FT.To_UString ("");
      Has_Initializer : Boolean := False;
      Initializer     : Expr_Access := null;
      Span            : FT.Source_Span := FT.Null_Span;
   end record;

   type Statement is record
      Kind          : Statement_Kind := Stmt_Unknown;
      Span          : FT.Source_Span := FT.Null_Span;
      Decl          : Object_Decl;
      Destructure   : Destructure_Decl;
      Target        : Expr_Access := null;
      Value         : Expr_Access := null;
      Call          : Expr_Access := null;
      Condition     : Expr_Access := null;
      Case_Expr     : Expr_Access := null;
      Match_Expr    : Expr_Access := null;
      Channel_Name  : Expr_Access := null;
      Success_Var   : Expr_Access := null;
      Then_Stmts    : Statement_Access_Vectors.Vector;
      Elsifs        : Elsif_Part_Vectors.Vector;
      Has_Else      : Boolean := False;
      Else_Stmts    : Statement_Access_Vectors.Vector;
      Case_Arms     : Case_Arm_Vectors.Vector;
      Match_Arms    : Match_Arm_Vectors.Vector;
      Loop_Var      : FT.UString := FT.To_UString ("");
      Loop_Range    : Discrete_Range;
      Loop_Iterable : Expr_Access := null;
      Loop_Snapshot_Name : FT.UString := FT.To_UString ("");
      Loop_Index_Name    : FT.UString := FT.To_UString ("");
      Body_Stmts    : Statement_Access_Vectors.Vector;
      Declarations  : Object_Decl_Vectors.Vector;
      Arms          : Select_Arm_Vectors.Vector;
      Scope_Id      : FT.UString := FT.To_UString ("");
      Is_Synthetic  : Boolean := False;
   end record;

   type Subprogram_Body is record
      Is_Public    : Boolean := False;
      Spec         : Subprogram_Spec;
      Declarations : Object_Decl_Vectors.Vector;
      Statements   : Statement_Access_Vectors.Vector;
      Span         : FT.Source_Span := FT.Null_Span;
   end record;

   type Task_Decl is record
      Name                 : FT.UString := FT.To_UString ("");
      Has_Explicit_Priority : Boolean := False;
      Priority             : Expr_Access := null;
      Has_Send_Contract    : Boolean := False;
      Send_Contracts       : Expr_Access_Vectors.Vector;
      Has_Receive_Contract : Boolean := False;
      Receive_Contracts    : Expr_Access_Vectors.Vector;
      Declarations         : Object_Decl_Vectors.Vector;
      Statements           : Statement_Access_Vectors.Vector;
      End_Name             : FT.UString := FT.To_UString ("");
      Span                 : FT.Source_Span := FT.Null_Span;
   end record;

   type Channel_Decl is record
      Is_Public    : Boolean := False;
      Name         : FT.UString := FT.To_UString ("");
      Element_Type : Type_Spec;
      Capacity     : Expr_Access := null;
      Span         : FT.Source_Span := FT.Null_Span;
   end record;

   type Package_Item_Kind is
     (Item_Unknown,
      Item_Type_Decl,
      Item_Subtype_Decl,
      Item_Object_Decl,
      Item_Subprogram,
      Item_Task,
      Item_Channel);

   type Package_Item is record
      Kind       : Package_Item_Kind := Item_Unknown;
      Type_Data  : Type_Decl;
      Sub_Data   : Subtype_Decl;
      Obj_Data   : Object_Decl;
      Subp_Data  : Subprogram_Body;
      Task_Data  : Task_Decl;
      Chan_Data  : Channel_Decl;
   end record;

   package Package_Item_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Package_Item);

   type With_Clause is record
      Names : FT.UString_Vectors.Vector;
      Span  : FT.Source_Span := FT.Null_Span;
   end record;

   package With_Clause_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => With_Clause);

   type Unit_Kind is (Unit_Package, Unit_Entry);

   type Parsed_Unit is record
      Path         : FT.UString := FT.To_UString ("");
      Kind         : Unit_Kind := Unit_Package;
      Package_Name : FT.UString := FT.To_UString ("");
      Has_End_Name : Boolean := False;
      End_Name     : FT.UString := FT.To_UString ("");
      Withs        : With_Clause_Vectors.Vector;
      Items        : Package_Item_Vectors.Vector;
      Statements   : Statement_Access_Vectors.Vector;
      Span         : FT.Source_Span := FT.Null_Span;
   end record;

   type Symbol is record
      Name      : FT.UString := FT.To_UString ("");
      Kind      : FT.UString := FT.To_UString ("");
      Mode      : FT.UString := FT.To_UString ("");
      Span      : FT.Source_Span := FT.Null_Span;
      Type_Info : GM.Type_Descriptor;
   end record;

   package Symbol_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Symbol);

   type Resolved_Object_Decl is record
      Names           : FT.UString_Vectors.Vector;
      Type_Info       : GM.Type_Descriptor;
      Is_Public       : Boolean := False;
      Is_Shared       : Boolean := False;
      Is_Constant     : Boolean := False;
      Has_Initializer : Boolean := False;
      Has_Implicit_Default_Init : Boolean := False;
      Initializer     : Expr_Access := null;
      Static_Info     : Static_Value;
      Span            : FT.Source_Span := FT.Null_Span;
   end record;

   package Resolved_Object_Decl_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Resolved_Object_Decl);

   type Imported_Object_Decl is record
      Name                 : FT.UString := FT.To_UString ("");
      Type_Info            : GM.Type_Descriptor;
      Is_Shared            : Boolean := False;
      Has_Required_Ceiling : Boolean := False;
      Required_Ceiling     : Long_Long_Integer := 0;
      Is_Constant          : Boolean := False;
      Static_Info          : Static_Value;
      Span                 : FT.Source_Span := FT.Null_Span;
   end record;

   package Imported_Object_Decl_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Imported_Object_Decl);

   type Resolved_Channel_Decl is record
      Is_Public    : Boolean := False;
      Name         : FT.UString := FT.To_UString ("");
      Element_Type : GM.Type_Descriptor;
      Capacity     : Long_Long_Integer := 0;
      Has_Required_Ceiling : Boolean := False;
      Required_Ceiling     : Long_Long_Integer := 0;
      Span         : FT.Source_Span := FT.Null_Span;
   end record;

   package Resolved_Channel_Decl_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Resolved_Channel_Decl);

   type Resolved_Subprogram is record
      Name                 : FT.UString := FT.To_UString ("");
      Kind                 : FT.UString := FT.To_UString ("");
      Is_Synthetic         : Boolean := False;
      Is_Interface_Template : Boolean := False;
      Is_Generic_Template  : Boolean := False;
      Force_Body_Emission  : Boolean := False;
      Generic_Formals      : Generic_Formal_Vectors.Vector;
      Params               : Symbol_Vectors.Vector;
      Has_Return_Type      : Boolean := False;
      Return_Type          : GM.Type_Descriptor;
      Return_Is_Access_Def : Boolean := False;
      Span                 : FT.Source_Span := FT.Null_Span;
      Declarations         : Resolved_Object_Decl_Vectors.Vector;
      Statements           : Statement_Access_Vectors.Vector;
   end record;

   package Resolved_Subprogram_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Resolved_Subprogram);

   type Resolved_Task is record
      Name                  : FT.UString := FT.To_UString ("");
      Has_Explicit_Priority : Boolean := False;
      Priority              : Long_Long_Integer := 0;
      Has_Send_Contract     : Boolean := False;
      Send_Contracts        : FT.UString_Vectors.Vector;
      Has_Receive_Contract  : Boolean := False;
      Receive_Contracts     : FT.UString_Vectors.Vector;
      Span                  : FT.Source_Span := FT.Null_Span;
      Declarations          : Resolved_Object_Decl_Vectors.Vector;
      Statements            : Statement_Access_Vectors.Vector;
   end record;

   package Resolved_Task_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Resolved_Task);

   type Resolved_Unit is record
      Path         : FT.UString := FT.To_UString ("");
      Kind         : Unit_Kind := Unit_Package;
      Target_Bits  : Positive := 64;
      Package_Name : FT.UString := FT.To_UString ("");
      Has_End_Name : Boolean := False;
      End_Name     : FT.UString := FT.To_UString ("");
      Types        : GM.Type_Descriptor_Vectors.Vector;
      Imported_Types : GM.Type_Descriptor_Vectors.Vector;
      Objects      : Resolved_Object_Decl_Vectors.Vector;
      Imported_Objects : Imported_Object_Decl_Vectors.Vector;
      Channels     : Resolved_Channel_Decl_Vectors.Vector;
      Imported_Channels : Resolved_Channel_Decl_Vectors.Vector;
      Subprograms  : Resolved_Subprogram_Vectors.Vector;
      Imported_Subprograms : GM.External_Vectors.Vector;
      Tasks        : Resolved_Task_Vectors.Vector;
      Statements   : Statement_Access_Vectors.Vector;
   end record;

   type Parse_Result (Success : Boolean := False) is record
      case Success is
         when True =>
            Unit : Parsed_Unit;
         when False =>
            Diagnostic : MD.Diagnostic;
      end case;
   end record;

   type Resolve_Result (Success : Boolean := False) is record
      case Success is
         when True =>
            Unit : Resolved_Unit;
         when False =>
            Diagnostic : MD.Diagnostic;
      end case;
   end record;

   function Join
     (Left  : FT.Source_Span;
      Right : FT.Source_Span) return FT.Source_Span;

   function Flatten_Name (Expr : Expr_Access) return String;

   function Make_Diagnostic
     (Reason             : String;
      Path               : String;
      Span               : FT.Source_Span;
      Message            : String;
      Note               : String := "";
      Suggestion         : String := "";
      Has_Highlight_Span : Boolean := False;
      Highlight_Span     : FT.Source_Span := FT.Null_Span)
      return MD.Diagnostic;

   procedure Append_Note
     (Item : in out MD.Diagnostic;
      Note : String);

   procedure Append_Suggestion
     (Item       : in out MD.Diagnostic;
      Suggestion : String);

   function Unsupported_Source_Construct
     (Path    : String;
      Span    : FT.Source_Span;
      Message : String;
      Note    : String := "") return MD.Diagnostic;

   function Source_Frontend_Error
     (Path    : String;
      Span    : FT.Source_Span;
      Message : String;
      Note    : String := "";
      Suggestion : String := "") return MD.Diagnostic;

   function Write_To_Constant
     (Path    : String;
      Span    : FT.Source_Span;
      Message : String) return MD.Diagnostic;
end Safe_Frontend.Check_Model;
