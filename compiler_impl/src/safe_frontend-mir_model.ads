with Ada.Containers.Indefinite_Vectors;
with GNATCOLL.JSON;
with Safe_Frontend.Types;

package Safe_Frontend.Mir_Model is
   package FT renames Safe_Frontend.Types;

   type Mir_Format_Kind is (Mir_V1, Mir_V2, Mir_V3, Mir_V4);
   function Image (Item : Mir_Format_Kind) return String;

   type Ownership_Effect_Kind is
     (Ownership_Invalid,
      Ownership_None,
      Ownership_Move,
      Ownership_Borrow,
      Ownership_Observe);
   function Image (Item : Ownership_Effect_Kind) return String;

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
      Expr_Resolved_Index,
      Expr_Conversion,
      Expr_Call,
      Expr_Allocator,
      Expr_Aggregate,
      Expr_Array_Literal,
      Expr_Tuple,
      Expr_Annotated,
      Expr_Unary,
      Expr_Binary);
   function Image (Item : Expr_Kind) return String;

   type Expr_Node;
   type Expr_Access is access all Expr_Node;

   package Expr_Access_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Expr_Access);

   type Aggregate_Field is record
      Field : FT.UString := FT.To_UString ("");
      Expr  : Expr_Access := null;
      Span  : FT.Source_Span := FT.Null_Span;
   end record;

   package Aggregate_Field_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Aggregate_Field);

   type Expr_Node is record
      Kind          : Expr_Kind := Expr_Unknown;
      Span          : FT.Source_Span := FT.Null_Span;
      Type_Name     : FT.UString := FT.To_UString ("");
      Text          : FT.UString := FT.To_UString ("");
      Int_Value     : Long_Long_Integer := 0;
      Bool_Value    : Boolean := False;
      Name          : FT.UString := FT.To_UString ("");
      Selector      : FT.UString := FT.To_UString ("");
      Operator      : FT.UString := FT.To_UString ("");
      Prefix        : Expr_Access := null;
      Inner         : Expr_Access := null;
      Left          : Expr_Access := null;
      Right         : Expr_Access := null;
      Callee        : Expr_Access := null;
      Value         : Expr_Access := null;
      Subtype_Name  : FT.UString := FT.To_UString ("");
      Indices       : Expr_Access_Vectors.Vector;
      Args          : Expr_Access_Vectors.Vector;
      Fields        : Aggregate_Field_Vectors.Vector;
      Elements      : Expr_Access_Vectors.Vector;
      Has_Call_Span : Boolean := False;
      Call_Span     : FT.Source_Span := FT.Null_Span;
   end record;

   type Type_Field is record
      Name      : FT.UString := FT.To_UString ("");
      Type_Name : FT.UString := FT.To_UString ("");
   end record;

   package Type_Field_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Type_Field);

   type Signature_Param is record
      Name      : FT.UString := FT.To_UString ("");
      Mode      : FT.UString := FT.To_UString ("");
      Type_Name : FT.UString := FT.To_UString ("");
   end record;

   package Signature_Param_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Signature_Param);

   type Interface_Member is record
      Name                 : FT.UString := FT.To_UString ("");
      Params               : Signature_Param_Vectors.Vector;
      Has_Return_Type      : Boolean := False;
      Return_Type          : FT.UString := FT.To_UString ("");
      Return_Is_Access_Def : Boolean := False;
   end record;

   package Interface_Member_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Interface_Member);

   type Generic_Formal_Descriptor is record
      Name            : FT.UString := FT.To_UString ("");
      Has_Constraint  : Boolean := False;
      Constraint_Name : FT.UString := FT.To_UString ("");
   end record;

   package Generic_Formal_Descriptor_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Generic_Formal_Descriptor);

   type Scalar_Value_Kind is
     (Scalar_Value_None,
      Scalar_Value_Integer,
      Scalar_Value_Boolean,
      Scalar_Value_Character,
      Scalar_Value_Enum);

   type Scalar_Value is record
      Kind       : Scalar_Value_Kind := Scalar_Value_None;
      Int_Value  : Long_Long_Integer := 0;
      Bool_Value : Boolean := False;
      Text       : FT.UString := FT.To_UString ("");
      Type_Name  : FT.UString := FT.To_UString ("");
   end record;

   type Discriminant_Descriptor is record
      Name        : FT.UString := FT.To_UString ("");
      Type_Name   : FT.UString := FT.To_UString ("");
      Has_Default : Boolean := False;
      Default_Value : Scalar_Value;
   end record;

   package Discriminant_Descriptor_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Discriminant_Descriptor);

   type Discriminant_Constraint is record
      Is_Named : Boolean := False;
      Name     : FT.UString := FT.To_UString ("");
      Value    : Scalar_Value;
   end record;

   package Discriminant_Constraint_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Discriminant_Constraint);

   type Variant_Field is record
      Name       : FT.UString := FT.To_UString ("");
      Type_Name  : FT.UString := FT.To_UString ("");
      When_True  : Boolean := False;
      Is_Others  : Boolean := False;
      Choice     : Scalar_Value;
   end record;

   package Variant_Field_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Variant_Field);

   type Sum_Variant_Field_Descriptor is record
      Source_Name   : FT.UString := FT.To_UString ("");
      Internal_Name : FT.UString := FT.To_UString ("");
      Type_Name     : FT.UString := FT.To_UString ("");
   end record;

   package Sum_Variant_Field_Descriptor_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Sum_Variant_Field_Descriptor);

   type Sum_Variant_Descriptor is record
      Name             : FT.UString := FT.To_UString ("");
      Tag_Literal_Name : FT.UString := FT.To_UString ("");
      Fields           : Sum_Variant_Field_Descriptor_Vectors.Vector;
   end record;

   package Sum_Variant_Descriptor_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Sum_Variant_Descriptor);

   type Type_Descriptor is record
      Name               : FT.UString := FT.To_UString ("");
      Kind               : FT.UString := FT.To_UString ("");
      Has_Low            : Boolean := False;
      Low                : Long_Long_Integer := 0;
      Has_High           : Boolean := False;
      High               : Long_Long_Integer := 0;
      Enum_Literals      : FT.UString_Vectors.Vector;
      Has_Bit_Width      : Boolean := False;
      Bit_Width          : Positive := 8;
      Index_Types        : FT.UString_Vectors.Vector;
      Has_Component_Type : Boolean := False;
      Component_Type     : FT.UString := FT.To_UString ("");
      Unconstrained      : Boolean := False;
      Growable           : Boolean := False;
      Has_Length_Bound   : Boolean := False;
      Length_Bound       : Natural := 0;
      Fields             : Type_Field_Vectors.Vector;
      Interface_Members  : Interface_Member_Vectors.Vector;
      Generic_Formals    : Generic_Formal_Descriptor_Vectors.Vector;
      Has_Generic_Origin : Boolean := False;
      Generic_Origin     : FT.UString := FT.To_UString ("");
      Generic_Actual_Types : FT.UString_Vectors.Vector;
      Has_Target         : Boolean := False;
      Target             : FT.UString := FT.To_UString ("");
      Has_Base           : Boolean := False;
      Base               : FT.UString := FT.To_UString ("");
      Has_Digits_Text    : Boolean := False;
      Digits_Text        : FT.UString := FT.To_UString ("");
      Has_Float_Low_Text : Boolean := False;
      Float_Low_Text     : FT.UString := FT.To_UString ("");
      Has_Float_High_Text : Boolean := False;
      Float_High_Text     : FT.UString := FT.To_UString ("");
      Has_Discriminant   : Boolean := False;
      Discriminant_Name  : FT.UString := FT.To_UString ("");
      Discriminant_Type  : FT.UString := FT.To_UString ("");
      Has_Discriminant_Default : Boolean := False;
      Discriminant_Default_Bool : Boolean := False;
      Discriminants      : Discriminant_Descriptor_Vectors.Vector;
      Discriminant_Constraints : Discriminant_Constraint_Vectors.Vector;
      Variant_Discriminant_Name : FT.UString := FT.To_UString ("");
      Variant_Fields     : Variant_Field_Vectors.Vector;
      Sum_Variants       : Sum_Variant_Descriptor_Vectors.Vector;
      Tuple_Element_Types : FT.UString_Vectors.Vector;
      Not_Null           : Boolean := False;
      Anonymous          : Boolean := False;
      Is_Constant        : Boolean := False;
      Is_All             : Boolean := False;
      Has_Access_Role    : Boolean := False;
      Access_Role        : FT.UString := FT.To_UString ("");
      Is_Result_Builtin  : Boolean := False;
   end record;

   package Type_Descriptor_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Type_Descriptor);

   type Channel_Entry is record
      Name         : FT.UString := FT.To_UString ("");
      Element_Type : Type_Descriptor;
      Capacity     : Long_Long_Integer := 0;
      Has_Required_Ceiling : Boolean := False;
      Required_Ceiling     : Long_Long_Integer := 0;
      Span         : FT.Source_Span := FT.Null_Span;
   end record;

   package Channel_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Channel_Entry);

   type Local_Entry is record
      Id             : FT.UString := FT.To_UString ("");
      Kind           : FT.UString := FT.To_UString ("");
      Mode           : FT.UString := FT.To_UString ("");
      Name           : FT.UString := FT.To_UString ("");
      Is_Constant    : Boolean := False;
      Ownership_Role : FT.UString := FT.To_UString ("");
      Scope_Id       : FT.UString := FT.To_UString ("");
      Span           : FT.Source_Span := FT.Null_Span;
      Type_Info      : Type_Descriptor;
   end record;

   package Local_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Local_Entry);

   type Scope_Entry is record
      Id               : FT.UString := FT.To_UString ("");
      Has_Parent_Scope : Boolean := False;
      Parent_Scope_Id  : FT.UString := FT.To_UString ("");
      Kind             : FT.UString := FT.To_UString ("");
      Local_Ids        : FT.UString_Vectors.Vector;
      Entry_Block      : FT.UString := FT.To_UString ("");
      Exit_Blocks      : FT.UString_Vectors.Vector;
   end record;

   package Scope_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Scope_Entry);

   type Op_Kind is
     (Op_Unknown,
      Op_Scope_Enter,
      Op_Scope_Exit,
      Op_Assign,
      Op_Call,
      Op_Channel_Send,
      Op_Channel_Receive,
      Op_Channel_Try_Send,
      Op_Channel_Try_Receive,
      Op_Delay);
   function Image (Item : Op_Kind) return String;

   type Op_Entry is record
      Kind             : Op_Kind := Op_Unknown;
      Span             : FT.Source_Span := FT.Null_Span;
      Ownership_Effect : Ownership_Effect_Kind := Ownership_Invalid;
      Type_Name        : FT.UString := FT.To_UString ("");
      Scope_Id         : FT.UString := FT.To_UString ("");
      Locals           : FT.UString_Vectors.Vector;
      Channel          : Expr_Access := null;
      Target           : Expr_Access := null;
      Value            : Expr_Access := null;
      Success_Target   : Expr_Access := null;
      Has_Declaration_Init   : Boolean := False;
      Declaration_Init_Valid : Boolean := False;
      Declaration_Init       : Boolean := False;
   end record;

   package Op_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Op_Entry);

   type Terminator_Kind is
     (Terminator_Unknown,
      Terminator_Jump,
      Terminator_Branch,
      Terminator_Return,
      Terminator_Select);
   function Image (Item : Terminator_Kind) return String;

   type Select_Arm_Kind is
     (Select_Arm_Unknown,
      Select_Arm_Channel,
      Select_Arm_Delay);

   type Select_Channel_Arm_Entry is record
      Channel_Name  : FT.UString := FT.To_UString ("");
      Variable_Name : FT.UString := FT.To_UString ("");
      Scope_Id      : FT.UString := FT.To_UString ("");
      Local_Id      : FT.UString := FT.To_UString ("");
      Type_Info     : Type_Descriptor;
      Target        : FT.UString := FT.To_UString ("");
      Span          : FT.Source_Span := FT.Null_Span;
   end record;

   type Select_Delay_Arm_Entry is record
      Duration_Expr : Expr_Access := null;
      Target        : FT.UString := FT.To_UString ("");
      Span          : FT.Source_Span := FT.Null_Span;
   end record;

   type Select_Arm_Entry is record
      Kind         : Select_Arm_Kind := Select_Arm_Unknown;
      Channel_Data : Select_Channel_Arm_Entry;
      Delay_Data   : Select_Delay_Arm_Entry;
      Span         : FT.Source_Span := FT.Null_Span;
   end record;

   package Select_Arm_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Select_Arm_Entry);

   type Terminator_Entry is record
      Kind             : Terminator_Kind := Terminator_Unknown;
      Span             : FT.Source_Span := FT.Null_Span;
      Ownership_Effect : Ownership_Effect_Kind := Ownership_Invalid;
      Target           : FT.UString := FT.To_UString ("");
      True_Target      : FT.UString := FT.To_UString ("");
      False_Target     : FT.UString := FT.To_UString ("");
      Condition        : Expr_Access := null;
      Has_Value        : Boolean := False;
      Value            : Expr_Access := null;
      Arms             : Select_Arm_Vectors.Vector;
   end record;

   type Block_Entry is record
      Id              : FT.UString := FT.To_UString ("");
      Active_Scope_Id : FT.UString := FT.To_UString ("");
      Role            : FT.UString := FT.To_UString ("");
      Has_Loop_Info   : Boolean := False;
      Loop_Kind       : FT.UString := FT.To_UString ("");
      Loop_Var        : FT.UString := FT.To_UString ("");
      Loop_Exit_Target : FT.UString := FT.To_UString ("");
      Span            : FT.Source_Span := FT.Null_Span;
      Ops             : Op_Vectors.Vector;
      Terminator      : Terminator_Entry;
   end record;

   package Block_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Block_Entry);

   type Summary_Depends_Entry is record
      Output_Name : FT.UString := FT.To_UString ("");
      Inputs      : FT.UString_Vectors.Vector;
   end record;

   package Summary_Depends_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Summary_Depends_Entry);

   type External_Effect_Summary is record
      Reads   : FT.UString_Vectors.Vector;
      Writes  : FT.UString_Vectors.Vector;
      Inputs  : FT.UString_Vectors.Vector;
      Outputs : FT.UString_Vectors.Vector;
      Depends : Summary_Depends_Vectors.Vector;
   end record;

   type External_Channel_Summary is record
      Channels : FT.UString_Vectors.Vector;
      Sends    : FT.UString_Vectors.Vector;
      Receives : FT.UString_Vectors.Vector;
   end record;

   type External_Entry is record
      Name                 : FT.UString := FT.To_UString ("");
      Kind                 : FT.UString := FT.To_UString ("");
      Signature            : FT.UString := FT.To_UString ("");
      Params               : Local_Vectors.Vector;
      Has_Return_Type      : Boolean := False;
      Return_Type          : Type_Descriptor;
      Return_Is_Access_Def : Boolean := False;
      Generic_Formals      : Generic_Formal_Descriptor_Vectors.Vector;
      Has_Template_Source  : Boolean := False;
      Template_Source      : FT.UString := FT.To_UString ("");
      Span                 : FT.Source_Span := FT.Null_Span;
      Effect_Summary       : External_Effect_Summary;
      Channel_Summary      : External_Channel_Summary;
   end record;

   package External_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => External_Entry);

   type Graph_Entry is record
      Name            : FT.UString := FT.To_UString ("");
      Kind            : FT.UString := FT.To_UString ("");
      Entry_BB        : FT.UString := FT.To_UString ("");
      Has_Span        : Boolean := False;
      Span            : FT.Source_Span := FT.Null_Span;
      Has_Priority    : Boolean := False;
      Priority        : Long_Long_Integer := 0;
      Has_Explicit_Priority : Boolean := False;
      Has_Return_Type : Boolean := False;
      Return_Type     : Type_Descriptor;
      Locals          : Local_Vectors.Vector;
      Scopes          : Scope_Vectors.Vector;
      Blocks          : Block_Vectors.Vector;
   end record;

   package Graph_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Graph_Entry);

   type Mir_Document is record
      Path            : FT.UString := FT.To_UString ("");
      Format          : Mir_Format_Kind := Mir_V1;
      Target_Bits     : Positive := 64;
      Has_Source_Path : Boolean := False;
      Source_Path     : FT.UString := FT.To_UString ("");
      Unit_Kind       : FT.UString := FT.To_UString ("package");
      Package_Name    : FT.UString := FT.To_UString ("");
      Types           : Type_Descriptor_Vectors.Vector;
      Channels        : Channel_Vectors.Vector;
      Externals       : External_Vectors.Vector;
      Graphs          : Graph_Vectors.Vector;
      Root            : GNATCOLL.JSON.JSON_Value := GNATCOLL.JSON.Create;
   end record;

   type Validation_Result (Success : Boolean := False) is record
      case Success is
         when True =>
            null;
         when False =>
            Message : FT.UString;
      end case;
   end record;

   function Ok return Validation_Result;
   function Error (Message : String) return Validation_Result;
end Safe_Frontend.Mir_Model;
