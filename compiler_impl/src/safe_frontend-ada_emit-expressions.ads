with Ada.Strings.Unbounded;
with Safe_Frontend.Ada_Emit.Internal;

private package Safe_Frontend.Ada_Emit.Expressions is
   package SU renames Ada.Strings.Unbounded;
   package AI renames Safe_Frontend.Ada_Emit.Internal;

   subtype Emit_State is AI.Emit_State;
   subtype Heap_Helper_Family_Kind is AI.Heap_Helper_Family_Kind;

   function Is_Attribute_Selector (Name : String) return Boolean;
   function Expr_Type_Info
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access) return GM.Type_Descriptor;
   function Try_Static_Integer_Value
     (Expr  : CM.Expr_Access;
      Value : out Long_Long_Integer) return Boolean;
   function Try_Static_String_Literal
     (Expr   : CM.Expr_Access;
      Image  : out SU.Unbounded_String;
      Length : out Natural) return Boolean;
   function Static_String_Literal_Element_Image
     (Image    : String;
      Position : Positive) return String;
   function Try_Static_String_Image
     (State : Emit_State;
      Expr  : CM.Expr_Access;
      Image : out SU.Unbounded_String) return Boolean;
   function Try_Static_Boolean_Value
     (State : Emit_State;
      Expr  : CM.Expr_Access;
      Value : out Boolean) return Boolean;
   function Try_Tracked_Static_Integer_Value
     (State : Emit_State;
      Expr  : CM.Expr_Access;
      Value : out Long_Long_Integer) return Boolean;
   function Render_Fixed_Array_As_Growable
     (Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      Expr        : CM.Expr_Access;
      Target_Info : GM.Type_Descriptor;
      State       : in out Emit_State) return String;
   function Render_Growable_As_Fixed
     (Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      Expr        : CM.Expr_Access;
      Target_Info : GM.Type_Descriptor;
      State       : in out Emit_State) return String;
   function Render_Growable_Array_Expr
     (Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      Expr        : CM.Expr_Access;
      Target_Info : GM.Type_Descriptor;
      State       : in out Emit_State) return String;
   function Render_Heap_String_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String;
   function Render_String_Value_Image
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      Info     : GM.Type_Descriptor;
      State    : in out Emit_State) return String;
   function Render_String_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String;
   function Render_Expr_For_Target_Type
     (Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      Expr        : CM.Expr_Access;
      Target_Info : GM.Type_Descriptor;
      State       : in out Emit_State) return String;
   function Tuple_Field_Name (Index : Positive) return String;
   function Render_Positional_Tuple_Aggregate
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String;
   function Render_Scalar_Value (Value : GM.Scalar_Value) return String;
   function Render_Record_Aggregate_For_Type
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Expr      : CM.Expr_Access;
      Type_Info : GM.Type_Descriptor;
      State     : in out Emit_State) return String;
   function Render_String_Length_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String;
   function Render_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String;
   function Render_Select_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String;
   function Render_Resolved_Index_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String;
   function Render_Conversion_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String;
   function Render_Call_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String;
   function Render_Aggregate_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String;
   function Render_Tuple_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String;
   function Render_Annotated_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String;
   function Render_Unary_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String;
   function Render_Binary_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String;
   function Render_Print_Argument
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String;
   function Shared_Call_Formal_Type
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Call_Expr : CM.Expr_Access;
      Position  : Positive;
      Found     : out Boolean) return GM.Type_Descriptor;
   function Static_Element_Binding_Name
     (Name     : String;
      Position : Positive) return String;
   function Try_Static_Integer_Array_Element_Expr
     (Unit     : CM.Resolved_Unit;
      Expr     : CM.Expr_Access;
      Position : Positive;
      Value    : out Long_Long_Integer) return Boolean;
   function Try_Resolved_Static_Integer_Value
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      State    : Emit_State;
      Expr     : CM.Expr_Access;
      Value    : out Long_Long_Integer) return Boolean;
   function Static_Growable_Length
     (Expr   : CM.Expr_Access;
      Length : out Natural) return Boolean;
   function Map_Operator (Operator : String) return String;
   function Render_Float_Convex_Combination
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String;
   function Render_Wide_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String;
   function Uses_Wide_Value
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      State    : Emit_State;
      Expr     : CM.Expr_Access) return Boolean;
   function Render_Channel_Send_Value
     (Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      State        : in out Emit_State;
      Channel_Expr : CM.Expr_Access;
      Value        : CM.Expr_Access) return String;
   function Replace_Identifier_Token
     (Text        : String;
      Name        : String;
      Replacement : String) return String;
   function Exprs_Match
     (Left  : CM.Expr_Access;
      Right : CM.Expr_Access) return Boolean;
   function Expr_Contains_Target
     (Expr   : CM.Expr_Access;
      Target : CM.Expr_Access) return Boolean;
   function Render_Expr_With_Target_Substitution
     (Unit          : CM.Resolved_Unit;
      Document      : GM.Mir_Document;
      Expr          : CM.Expr_Access;
      Target        : CM.Expr_Access;
      Replacement   : String;
      State         : in out Emit_State;
      Supported     : in out Boolean) return String;
   function Render_Expr_With_Old_Substitution
     (Unit          : CM.Resolved_Unit;
      Document      : GM.Mir_Document;
      Expr          : CM.Expr_Access;
      Target        : CM.Expr_Access;
      State         : in out Emit_State;
      Supported     : in out Boolean) return String;
   function Render_Wide_Expr_With_Target_Substitution
     (Unit          : CM.Resolved_Unit;
      Document      : GM.Mir_Document;
      Expr          : CM.Expr_Access;
      Target        : CM.Expr_Access;
      Replacement   : String;
      State         : in out Emit_State;
      Supported     : in out Boolean) return String;
   function Apply_Name_Replacements
     (Text       : String;
      From_Names : FT.UString_Vectors.Vector;
      To_Names   : FT.UString_Vectors.Vector) return String;
end Safe_Frontend.Ada_Emit.Expressions;
