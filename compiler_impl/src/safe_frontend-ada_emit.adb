with Ada.Characters.Handling;
with Ada.Containers;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Safe_Frontend.Ada_Emit.Expressions;
with Safe_Frontend.Ada_Emit.Internal;
with Safe_Frontend.Ada_Emit.Statements;
with Safe_Frontend.Ada_Emit.Types;
with Safe_Frontend.Builtin_Types;
with Safe_Frontend.Name_Utils;

package body Safe_Frontend.Ada_Emit is
   package SU renames Ada.Strings.Unbounded;
   package AI renames Safe_Frontend.Ada_Emit.Internal;
   package BT renames Safe_Frontend.Builtin_Types;
   package FNU renames Safe_Frontend.Name_Utils;
   package AET renames Safe_Frontend.Ada_Emit.Types;
   package AEX renames Safe_Frontend.Ada_Emit.Expressions;
   package AES renames Safe_Frontend.Ada_Emit.Statements;

   use type Ada.Containers.Count_Type;
   use type CM.Expr_Access;
   use type CM.Expr_Kind;
   use type CM.Statement_Access;
   use type CM.Statement_Kind;
   use type CM.Discrete_Range_Kind;
   use type CM.Select_Arm_Kind;
   use type FT.UString;
   use type GM.Scalar_Value_Kind;

   Gnat_Adc_Contents : constant String :=
     "pragma Partition_Elaboration_Policy(Sequential);" & ASCII.LF
     & "pragma Profile(Jorvik);" & ASCII.LF;

   subtype Cleanup_Action is AI.Cleanup_Action;
   subtype Cleanup_Item is AI.Cleanup_Item;
   subtype Emit_State is AI.Emit_State;
   subtype Emit_Context is AI.Emit_Context;
   subtype Warning_Suppression_Array is AI.Warning_Suppression_Array;
   subtype Warning_Restore_Array is AI.Warning_Restore_Array;
   subtype Heap_Helper_Family_Kind is AI.Heap_Helper_Family_Kind;

   procedure Raise_Internal (Message : String);
   pragma No_Return (Raise_Internal);
   procedure Raise_Unsupported
     (State   : in out Emit_State;
      Span    : FT.Source_Span;
      Message : String);
   pragma No_Return (Raise_Unsupported);

   function Has_Text (Item : FT.UString) return Boolean;
   function Trim_Image (Value : Long_Long_Integer) return String;
   function Trim_Wide_Image (Value : CM.Wide_Integer) return String;
   function Indentation (Depth : Natural) return String;
   procedure Append_Line
     (Buffer : in out SU.Unbounded_String;
      Text   : String := "";
      Depth  : Natural := 0);
   function Join_Names (Items : FT.UString_Vectors.Vector) return String;
   function Contains_Name
     (Items : FT.UString_Vectors.Vector;
      Name  : String) return Boolean;
   procedure Add_Wide_Name
     (State : in out Emit_State;
      Name  : String);
   function Is_Wide_Name
     (State : Emit_State;
      Name  : String) return Boolean;
   function Names_Use_Wide_Storage
     (State : Emit_State;
      Names : FT.UString_Vectors.Vector) return Boolean;
   procedure Restore_Wide_Names
     (State           : in out Emit_State;
      Previous_Length : Ada.Containers.Count_Type);
   procedure Push_Type_Binding_Frame (State : in out Emit_State);
   procedure Pop_Type_Binding_Frame (State : in out Emit_State);
   procedure Add_Type_Binding
     (State     : in out Emit_State;
      Name      : String;
      Type_Info : GM.Type_Descriptor);
   procedure Register_Type_Bindings
     (State        : in out Emit_State;
      Declarations : CM.Resolved_Object_Decl_Vectors.Vector);
   procedure Register_Type_Bindings
     (State        : in out Emit_State;
      Declarations : CM.Object_Decl_Vectors.Vector);
   procedure Register_Param_Type_Bindings
     (State  : in out Emit_State;
      Params  : CM.Symbol_Vectors.Vector);
   function Lookup_Bound_Type
     (State     : Emit_State;
      Name      : String;
      Type_Info : out GM.Type_Descriptor) return Boolean;
   procedure Push_Cleanup_Frame (State : in out Emit_State);
   procedure Pop_Cleanup_Frame (State : in out Emit_State);
   procedure Add_Cleanup_Item
     (State     : in out Emit_State;
      Name      : String;
      Type_Name : String;
      Free_Proc : String := "";
      Is_Constant : Boolean := False;
      Always_Terminates_Suppression_OK : Boolean := False;
      Action    : Cleanup_Action := AI.Cleanup_Deallocate);
   procedure Register_Cleanup_Items
     (State        : in out Emit_State;
      Declarations : CM.Resolved_Object_Decl_Vectors.Vector);
   procedure Register_Cleanup_Items
     (State        : in out Emit_State;
      Declarations : CM.Object_Decl_Vectors.Vector);
   procedure Render_Cleanup_Item
     (Buffer : in out SU.Unbounded_String;
      Item   : Cleanup_Item;
      Depth  : Natural);
   procedure Render_Active_Cleanup
     (Buffer : in out SU.Unbounded_String;
      State  : Emit_State;
      Depth  : Natural;
      Skip_Name : String := "");
   procedure Render_Current_Cleanup_Frame
     (Buffer : in out SU.Unbounded_String;
      State  : Emit_State;
      Depth  : Natural);
   function Has_Active_Cleanup_Items (State : Emit_State) return Boolean;
   function Starts_With (Text : String; Prefix : String) return Boolean;
   function Ada_Safe_Name (Name : String) return String;
   function Ada_Qualified_Name (Name : String) return String;
   function Render_Enum_Literal_Name
     (Literal_Name   : String;
      Enum_Type_Name : String) return String;
   function Sanitized_Helper_Name (Name : String) return String;
   function Array_Runtime_Instance_Name (Info : GM.Type_Descriptor) return String;
   function Array_Runtime_Free_Element_Name (Info : GM.Type_Descriptor) return String;
   function Normalize_Aspect_Name
     (Subprogram_Name : String;
      Raw_Name        : String) return String;
   function Is_Attribute_Selector (Name : String) return Boolean;
   function Root_Name (Expr : CM.Expr_Access) return String;
   function Expr_Uses_Name
     (Expr : CM.Expr_Access;
      Name : String) return Boolean;
   function Statements_Use_Name
     (Statements : CM.Statement_Access_Vectors.Vector;
      Name       : String) return Boolean;
   function Selector_Is_Record_Field
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Prefix    : CM.Expr_Access;
      Selector  : String) return Boolean;
   function Is_Aspect_State_Name (Name : String) return Boolean;
   function Is_Constant_Object_Name
     (Unit : CM.Resolved_Unit;
      Name : String) return Boolean;

   function Lookup_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Name     : String) return GM.Type_Descriptor;
   function Base_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return GM.Type_Descriptor;
   function Has_Type
     (Unit     : CM.Resolved_Unit;
     Document : GM.Mir_Document;
     Name     : String) return Boolean;
   function Type_Info_From_Name
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Name      : String;
      Type_Info : out GM.Type_Descriptor) return Boolean;
   function Resolve_Type_Name
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Name     : String) return GM.Type_Descriptor;
   function Lookup_Object_Type
     (Unit      : CM.Resolved_Unit;
      Name      : String;
      Type_Info : out GM.Type_Descriptor) return Boolean;
   function Span_Contains
     (Outer : FT.Source_Span;
      Inner : FT.Source_Span) return Boolean;
   function Lookup_Mir_Local_Type
     (Document  : GM.Mir_Document;
      Name      : String;
      Span      : FT.Source_Span;
      Type_Info : out GM.Type_Descriptor) return Boolean;
   function Lookup_Local_Object_Type
     (Unit      : CM.Resolved_Unit;
      Name      : String;
      Span      : FT.Source_Span;
      Type_Info : out GM.Type_Descriptor) return Boolean;
   function Lookup_Selected_Type
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Prefix    : GM.Type_Descriptor;
      Selector  : String;
      Type_Info : out GM.Type_Descriptor) return Boolean;
   function Resolve_Print_Type
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Expr      : CM.Expr_Access;
      State     : Emit_State;
      Type_Info : out GM.Type_Descriptor) return Boolean;
   function Is_Integer_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Name     : String) return Boolean;
   function Is_Integer_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean;
   function Is_Binary_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Name     : String) return Boolean;
   function Is_Binary_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean;
   function Binary_Bit_Width
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Name     : String) return Positive;
   function Binary_Bit_Width
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Positive;
   function Is_Float_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Name     : String) return Boolean;
   function Is_Float_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean;
   function Is_Array_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean;
   function Is_Plain_String_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean;
   function Is_Growable_Array_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean;
   function Try_Map_Key_Value_Types
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Info       : GM.Type_Descriptor;
      Key_Type   : out GM.Type_Descriptor;
      Value_Type : out GM.Type_Descriptor) return Boolean;
   function Constant_Cleanup_Uses_Shared_Runtime_Free
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Info      : GM.Type_Descriptor;
      Free_Proc : String) return Boolean;
   function Is_Tuple_Type (Info : GM.Type_Descriptor) return Boolean;
   function Is_Result_Builtin (Info : GM.Type_Descriptor) return Boolean;
   function Render_Result_Empty_Aggregate return String;
   function Render_Result_Fail_Aggregate (Message_Image : String) return String;
   function Is_Access_Type (Info : GM.Type_Descriptor) return Boolean;
   function Is_Owner_Access (Info : GM.Type_Descriptor) return Boolean;
   function Is_Alias_Access (Info : GM.Type_Descriptor) return Boolean;
   function Owner_Allocate_Post_Field_Is_Trackable
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Field_Info : GM.Type_Descriptor) return Boolean;
   function Needs_Implicit_Dereference
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access) return Boolean;
   function Is_Bounded_String_Type (Info : GM.Type_Descriptor) return Boolean;
   function Bounded_String_Instance_Name (Bound : Natural) return String;
   function Bounded_String_Instance_Name (Info : GM.Type_Descriptor) return String;
   function Bounded_String_Type_Name (Bound : Natural) return String;
   function Bounded_String_Type_Name (Info : GM.Type_Descriptor) return String;
   function Synthetic_Bounded_String_Type
     (Name  : String;
      Found : out Boolean) return GM.Type_Descriptor;
   procedure Register_Bounded_String_Type
     (State : in out Emit_State;
      Info  : GM.Type_Descriptor);
   procedure Collect_Bounded_String_Types
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      State    : in out Emit_State);
   procedure Append_Bounded_String_Instantiations
     (Buffer : in out SU.Unbounded_String;
      State  : Emit_State);
   procedure Append_Bounded_String_Uses
     (Buffer : in out SU.Unbounded_String;
      State  : Emit_State;
      Depth  : Natural);
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
   procedure Bind_Static_Integer
     (State : in out Emit_State;
      Name  : String;
      Value : Long_Long_Integer);
   procedure Invalidate_Static_Integer
     (State : in out Emit_State;
      Name  : String);
   procedure Bind_Static_String
     (State : in out Emit_State;
      Name  : String;
      Image : String);
   function Has_Static_Integer_Tracking
     (State : Emit_State;
      Name  : String) return Boolean;
   function Try_Static_Integer_Binding
     (State : Emit_State;
      Name  : String;
      Value : out Long_Long_Integer) return Boolean;
   function Try_Tracked_Static_Integer_Value
     (State : Emit_State;
      Expr  : CM.Expr_Access;
      Value : out Long_Long_Integer) return Boolean;
   function Try_Static_String_Binding
     (State : Emit_State;
      Name  : String;
      Image : out SU.Unbounded_String) return Boolean;
   procedure Restore_Static_String_Bindings
     (State           : in out Emit_State;
      Previous_Length : Ada.Containers.Count_Type);
   procedure Clear_All_Static_Bindings (State : in out Emit_State);
   function Try_Object_Static_String_Initializer
     (Unit   : CM.Resolved_Unit;
      Name   : String;
      Image  : out SU.Unbounded_String;
      Length : out Natural) return Boolean;
   function Fixed_Array_Cardinality
     (Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      Target_Info : GM.Type_Descriptor;
      Cardinality : out Natural) return Boolean;
   function Static_Growable_Length
     (Expr   : CM.Expr_Access;
      Length : out Natural) return Boolean;
   function Has_Heap_Value_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean;
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
   function Default_Value_Expr (Type_Name : String) return String;
   function Default_Value_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return String;
   function Default_Value_Expr (Info : GM.Type_Descriptor) return String;
   function Needs_Explicit_Default_Initializer
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean;
   function Binary_Ada_Name (Bit_Width : Positive) return String;
   function Render_Type_Name (Info : GM.Type_Descriptor) return String;
   function Render_Type_Name_From_Text
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Name_Text : String;
      State     : in out Emit_State) return String;
   function Render_Subtype_Indication
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return String;
   function Render_Param_Type_Name
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return String;
   function Render_Type_Name
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Name     : String) return String;
   function Render_Object_Decl_Text_Common
     (Unit           : CM.Resolved_Unit;
      Document       : GM.Mir_Document;
      State          : in out Emit_State;
      Names          : FT.UString_Vectors.Vector;
      Type_Info      : GM.Type_Descriptor;
      Is_Constant    : Boolean;
      Has_Initializer : Boolean;
      Has_Implicit_Default_Init : Boolean;
      Initializer    : CM.Expr_Access;
      Local_Context  : Boolean := False;
      Defer_Initializer : Boolean := False) return String;
   function Lookup_Channel
     (Unit : CM.Resolved_Unit;
      Name : String) return CM.Resolved_Channel_Decl;
   function Render_Type_Decl
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Type_Item : GM.Type_Descriptor;
      State     : in out Emit_State) return String;
   function Render_Integer_Type_Decl
     (Type_Item : GM.Type_Descriptor) return String;
   function Render_Enum_Type_Decl
     (Type_Item : GM.Type_Descriptor) return String;
   function Render_Binary_Type_Decl
     (Type_Item : GM.Type_Descriptor) return String;
   function Render_Subtype_Type_Decl
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Type_Item : GM.Type_Descriptor) return String;
   function Render_Array_Type_Decl
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Type_Item : GM.Type_Descriptor;
      State     : in out Emit_State) return String;
   function Render_Tuple_Type_Decl
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Type_Item : GM.Type_Descriptor;
      State     : in out Emit_State) return String;
   function Render_Result_Type_Decl
     (Type_Item : GM.Type_Descriptor;
      State     : in out Emit_State) return String;
   function Render_Record_Type_Decl
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Type_Item : GM.Type_Descriptor;
      State     : in out Emit_State) return String;
   function Render_Access_Type_Decl
     (Type_Item : GM.Type_Descriptor) return String;
   function Render_Float_Type_Decl
     (Type_Item : GM.Type_Descriptor) return String;
   procedure Render_Growable_Array_Helper_Body
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Type_Item : GM.Type_Descriptor;
      State    : in out Emit_State);
   function Needs_Generated_For_Of_Helper
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean;
   procedure Collect_For_Of_Helper_Types
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Result   : in out GM.Type_Descriptor_Vectors.Vector);
   function For_Of_Copy_Helper_Name
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return String;
   function For_Of_Free_Helper_Name
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return String;
   function Needs_Generated_Heap_Helper
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean;
   function Heap_Helper_Base_Name
     (Family    : Heap_Helper_Family_Kind;
      Scope_Name : String;
      Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Info      : GM.Type_Descriptor) return String;
   function Heap_Copy_Helper_Name
     (Family    : Heap_Helper_Family_Kind;
      Scope_Name : String;
      Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Info      : GM.Type_Descriptor) return String;
   function Heap_Free_Helper_Name
     (Family    : Heap_Helper_Family_Kind;
      Scope_Name : String;
      Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Info      : GM.Type_Descriptor) return String;
   function Same_Variant_Choice
     (Left, Right : GM.Variant_Field) return Boolean;
   procedure Mark_Heap_Runtime_Dependencies
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Info      : GM.Type_Descriptor;
      State     : in out Emit_State;
      Seen      : in out FT.UString_Vectors.Vector);
   procedure Append_Heap_Copy_Value
     (Buffer     : in out SU.Unbounded_String;
      Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      State      : in out Emit_State;
      Family     : Heap_Helper_Family_Kind;
      Scope_Name : String;
      Target_Text : String;
      Source_Text : String;
      Info       : GM.Type_Descriptor;
      Depth      : Natural);
   procedure Append_Heap_Free_Value
     (Buffer     : in out SU.Unbounded_String;
      Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      State      : in out Emit_State;
      Family     : Heap_Helper_Family_Kind;
      Scope_Name : String;
      Target_Text : String;
      Info       : GM.Type_Descriptor;
      Depth      : Natural);
   procedure Append_Record_Heap_Copy_Assignments
     (Buffer      : in out SU.Unbounded_String;
      Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      State       : in out Emit_State;
      Family      : Heap_Helper_Family_Kind;
      Scope_Name  : String;
      Base        : GM.Type_Descriptor;
      Target_Prefix : String;
      Source_Prefix : String;
      Depth       : Natural);
   procedure Append_Record_Heap_Free_Statements
     (Buffer      : in out SU.Unbounded_String;
      Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      State       : in out Emit_State;
      Family      : Heap_Helper_Family_Kind;
      Scope_Name  : String;
      Base        : GM.Type_Descriptor;
      Value_Prefix : String;
      Depth       : Natural);
   procedure Append_Generated_Heap_Copy_Body
     (Buffer      : in out SU.Unbounded_String;
      Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      State       : in out Emit_State;
      Family      : Heap_Helper_Family_Kind;
      Scope_Name  : String;
      Info        : GM.Type_Descriptor;
      Depth       : Natural);
   procedure Append_Generated_Heap_Free_Body
     (Buffer      : in out SU.Unbounded_String;
      Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      State       : in out Emit_State;
      Family      : Heap_Helper_Family_Kind;
      Scope_Name  : String;
      Info        : GM.Type_Descriptor;
      Depth       : Natural);
   procedure Render_For_Of_Helper_Bodies
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Types    : GM.Type_Descriptor_Vectors.Vector;
      State    : in out Emit_State);
   procedure Collect_Owner_Access_Helper_Types
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Result   : in out GM.Type_Descriptor_Vectors.Vector);
   procedure Render_Owner_Access_Helper_Spec
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Type_Item : GM.Type_Descriptor);
   procedure Render_Owner_Access_Helper_Body
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Type_Item : GM.Type_Descriptor;
      State    : in out Emit_State);
   procedure Collect_Synthetic_Types
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Result   : in out GM.Type_Descriptor_Vectors.Vector);
   function Render_Object_Decl_Text
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      State    : in out Emit_State;
      Decl     : CM.Resolved_Object_Decl;
      Local_Context : Boolean := False;
      Defer_Initializer : Boolean := False) return String;
   function Render_Object_Decl_Text
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      State    : in out Emit_State;
      Decl     : CM.Object_Decl;
      Local_Context : Boolean := False;
      Defer_Initializer : Boolean := False) return String;

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
   function Channel_Has_Length_Model
     (Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      Channel_Item : CM.Resolved_Channel_Decl) return Boolean;
   function Channel_Has_Scalar_Length_Model
     (Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      Channel_Item : CM.Resolved_Channel_Decl) return Boolean;
   function Channel_Uses_Runtime_Length_Formals
     (Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      Channel_Item : CM.Resolved_Channel_Decl) return Boolean;
   function Render_Channel_Operation_Target
     (Unit           : CM.Resolved_Unit;
      Document       : GM.Mir_Document;
      State          : in out Emit_State;
      Channel_Expr   : CM.Expr_Access;
      Channel_Item   : CM.Resolved_Channel_Decl;
      Operation_Name : String) return String;
   function Channel_Length_Image
     (Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      State        : in out Emit_State;
      Channel_Item : CM.Resolved_Channel_Decl;
      Value_Image  : String) return String;
   procedure Append_Heap_Channel_Free
     (Buffer       : in out SU.Unbounded_String;
      Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      Channel_Item : CM.Resolved_Channel_Decl;
      Target_Image : String;
      Depth        : Natural);
   procedure Append_Channel_Length_Assert
     (Buffer       : in out SU.Unbounded_String;
      Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      State        : in out Emit_State;
      Channel_Item : CM.Resolved_Channel_Decl;
      Value_Image  : String;
      Length_Name  : String;
      Depth        : Natural);
   function Channel_Staged_Value_Name
     (Statement_Index : Positive) return String;
   function Channel_Staged_Length_Name
     (Statement_Index : Positive) return String;
   procedure Append_Staged_Channel_Declarations
     (Buffer                 : in out SU.Unbounded_String;
      Unit                   : CM.Resolved_Unit;
      Document               : GM.Mir_Document;
      Channel_Item           : CM.Resolved_Channel_Decl;
      Value_Name             : String;
      Length_Name            : String;
      Value_Type_Name        : String;
      Success_Name           : String;
      Depth                  : Natural;
      Suppress_Init_Warnings : Boolean);
   procedure Append_Staged_Channel_Call
     (Buffer                  : in out SU.Unbounded_String;
      Unit                    : CM.Resolved_Unit;
      Document                : GM.Mir_Document;
      Operation_Target        : String;
      Channel_Item            : CM.Resolved_Channel_Decl;
      Value_Name              : String;
      Length_Name             : String;
      Success_Image           : String;
      Depth                   : Natural;
      Force_Staged_Warnings   : Boolean;
      Wrap_Task_Call_Warnings : Boolean);
   procedure Append_Staged_Channel_Length_Reconcile
     (Buffer       : in out SU.Unbounded_String;
      Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      State        : in out Emit_State;
      Channel_Item : CM.Resolved_Channel_Decl;
      Value_Name   : String;
      Length_Name  : String;
      Depth        : Natural);
   procedure Append_Staged_Channel_Target_Adoption
     (Buffer       : in out SU.Unbounded_String;
      Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      State        : in out Emit_State;
      Channel_Item : CM.Resolved_Channel_Decl;
      Target_Image : String;
      Value_Name   : String;
      Length_Name  : String;
      Depth        : Natural);
   procedure Collect_Wide_Locals
     (Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      State        : in out Emit_State;
      Declarations : CM.Resolved_Object_Decl_Vectors.Vector;
      Statements   : CM.Statement_Access_Vectors.Vector);
   procedure Collect_Wide_Locals
     (Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      State        : in out Emit_State;
      Declarations : CM.Object_Decl_Vectors.Vector;
      Statements   : CM.Statement_Access_Vectors.Vector);

   procedure Render_Statements
     (Buffer     : in out SU.Unbounded_String;
      Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Statements : CM.Statement_Access_Vectors.Vector;
      State      : in out Emit_State;
      Depth      : Natural;
      Return_Type : String := "";
      In_Loop    : Boolean := False);
   function Tail_Statements
     (Statements : CM.Statement_Access_Vectors.Vector;
      First      : Positive) return CM.Statement_Access_Vectors.Vector;
   procedure Emit_Nonblocking_Send_Statement
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Item     : CM.Statement;
      Index    : Positive;
      State    : in out Emit_State;
      Depth    : Natural);
   procedure Emit_Call_Statement
     (Buffer          : in out SU.Unbounded_String;
      Unit            : CM.Resolved_Unit;
      Document        : GM.Mir_Document;
      Call_Expr       : CM.Expr_Access;
      Statement_Index : Positive;
      State           : in out Emit_State;
      Depth           : Natural);
   procedure Render_Required_Statement_Suite
     (Buffer     : in out SU.Unbounded_String;
      Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Statements : CM.Statement_Access_Vectors.Vector;
      State      : in out Emit_State;
      Depth      : Natural;
      Return_Type : String := "";
      In_Loop    : Boolean := False);
   function Select_Dispatcher_Name
     (Stmt : CM.Statement_Access) return String;
   function Select_Rotation_State_Name
     (Stmt : CM.Statement_Access) return String;
   function Select_Dispatcher_Timer_Name
     (Stmt : CM.Statement_Access) return String;
   function Select_Dispatcher_Arm_Helper_Name
     (Stmt : CM.Statement_Access) return String;
   function Select_Dispatcher_Cancel_Helper_Name
     (Stmt : CM.Statement_Access) return String;
   function Select_Has_Delay_Arm
     (Stmt : CM.Statement_Access) return Boolean;
   function Select_References_Channel
     (Stmt         : CM.Statement_Access;
      Channel_Name : String) return Boolean;
   procedure Ignore_Select_Arm (Arm : CM.Select_Arm);
   generic
      with procedure Visit_Statement (Item : CM.Statement_Access);
      with procedure Visit_Select_Arm (Arm : CM.Select_Arm);
   procedure Walk_Statement_Structure
     (Statements : CM.Statement_Access_Vectors.Vector);
   procedure Collect_Select_Dispatcher_Names
     (Statements : CM.Statement_Access_Vectors.Vector;
      Names      : in out FT.UString_Vectors.Vector);
   procedure Collect_Select_Rotation_State
     (Statements : CM.Statement_Access_Vectors.Vector;
      Names      : in out FT.UString_Vectors.Vector;
      Counts     : in out FT.UString_Vectors.Vector);
   procedure Collect_Select_Delay_Timer_Names
     (Statements : CM.Statement_Access_Vectors.Vector;
      Names      : in out FT.UString_Vectors.Vector);
   procedure Collect_Select_Dispatcher_Names_For_Channel
     (Statements   : CM.Statement_Access_Vectors.Vector;
      Channel_Name : String;
      Names        : in out FT.UString_Vectors.Vector);
   procedure Render_Select_Dispatcher_Spec
     (Buffer : in out SU.Unbounded_String;
      Name   : String);
   procedure Render_Select_Dispatcher_Body
     (Buffer : in out SU.Unbounded_String;
      Name   : String);
   procedure Render_Select_Dispatcher_Delay_Helpers
     (Buffer        : in out SU.Unbounded_String;
      Dispatcher    : String;
      Timer_Name    : String;
      Init_Helper   : String;
      Deadline_Helper : String;
      Arm_Helper    : String;
      Cancel_Helper : String;
      Depth         : Natural := 1);
   procedure Append_Select_Dispatcher_Signals
     (Buffer       : in out SU.Unbounded_String;
      Unit         : CM.Resolved_Unit;
      Channel_Name : String;
      Depth        : Natural);
   function Alias_Declarations
     (Declarations : CM.Resolved_Object_Decl_Vectors.Vector)
      return CM.Resolved_Object_Decl_Vectors.Vector;
   function Non_Alias_Declarations
     (Declarations : CM.Resolved_Object_Decl_Vectors.Vector)
      return CM.Resolved_Object_Decl_Vectors.Vector;
   procedure Render_In_Out_Param_Stabilizers
     (Buffer     : in out SU.Unbounded_String;
      Subprogram : CM.Resolved_Subprogram;
      Depth      : Natural);
   function Statement_Falls_Through
     (Item : CM.Statement_Access) return Boolean;
   function Statements_Fall_Through
     (Statements : CM.Statement_Access_Vectors.Vector) return Boolean;
   function Statement_Contains_Exit
     (Item : CM.Statement_Access) return Boolean;
   function Statements_Contain_Exit
     (Statements : CM.Statement_Access_Vectors.Vector) return Boolean;
   function Loop_Variant_Image
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Condition : CM.Expr_Access;
      State     : in out Emit_State) return String;
   function Uses_Structural_Traversal_Lowering
     (Subprogram : CM.Resolved_Subprogram) return Boolean;
   function Replace_Identifier_Token
     (Text        : String;
      Name        : String;
      Replacement : String) return String;
   procedure Append_Gnatprove_Warning_Suppression
     (Buffer  : in out SU.Unbounded_String;
      Pattern : String;
      Reason  : String;
      Depth   : Natural);
   procedure Append_Gnatprove_Warning_Restore
     (Buffer  : in out SU.Unbounded_String;
      Pattern : String;
      Depth   : Natural);
   procedure Append_Gnatprove_Warning_Suppressions
     (Buffer   : in out SU.Unbounded_String;
      Warnings : Warning_Suppression_Array;
      Depth    : Natural);
   procedure Append_Gnatprove_Warning_Restores
     (Buffer   : in out SU.Unbounded_String;
      Warnings : Warning_Restore_Array;
      Depth    : Natural);
   procedure Append_Initialization_Warning_Suppression
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural);
   procedure Append_Initialization_Warning_Restore
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural);
   procedure Append_Local_Warning_Suppression
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural);
   procedure Append_Local_Warning_Restore
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural);
   procedure Append_Channel_Staged_Call_Warning_Suppression
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural);
   procedure Append_Channel_Staged_Call_Warning_Restore
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural);
   procedure Append_Task_Assignment_Warning_Suppression
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural);
   procedure Append_Task_Assignment_Warning_Restore
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural);
   procedure Append_Task_If_Warning_Suppression
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural);
   procedure Append_Task_If_Warning_Restore
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural);
   procedure Append_Task_Channel_Call_Warning_Suppression
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural);
   procedure Append_Task_Channel_Call_Warning_Restore
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural);
   function Structural_Accumulator_Count_Total_Bound
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram;
      Count_Name : String;
      Total_Name : String;
      State      : in out Emit_State) return String;

   function Render_Subprogram_Params
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Params     : CM.Symbol_Vectors.Vector) return String;
   function Render_Ada_Subprogram_Keyword
     (Subprogram : CM.Resolved_Subprogram) return String;
   function Render_Subprogram_Return
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram) return String;
   function Render_Initializes_Aspect
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Bronze   : MB.Bronze_Result) return String;
   function Render_Access_Param_Precondition
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram;
      State      : in out Emit_State) return String;
   function Render_Access_Param_Postcondition
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram;
      State      : in out Emit_State) return String;
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
   function Render_Subprogram_Aspects
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram;
      Bronze     : MB.Bronze_Result;
      State      : in out Emit_State) return String;
   function Channel_Uses_Environment_Task
     (Bronze : MB.Bronze_Result;
      Name   : String) return Boolean;
   function Channel_Uses_Unspecified_Task_Priority
     (Unit   : CM.Resolved_Unit;
      Bronze : MB.Bronze_Result;
      Name   : String) return Boolean;
   function Canonical_Name (Value : String) return String;
   function Sanitize_Type_Name_Component (Value : String) return String;
   function Shared_Wrapper_Object_Name (Root_Name : String) return String;
   function Shared_Wrapper_Type_Name (Root_Name : String) return String;
   function Shared_Public_Helper_Base_Name (Root_Name : String) return String;
   function Shared_Public_Helper_Name
     (Root_Name : String;
      Operation : String) return String;
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
   function Shared_Call_Formal_Type
     (Unit          : CM.Resolved_Unit;
      Document      : GM.Mir_Document;
      Call_Expr      : CM.Expr_Access;
      Position      : Positive;
      Found         : out Boolean) return GM.Type_Descriptor;
   procedure Render_Shared_Object_Spec
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Decl     : CM.Resolved_Object_Decl;
      Bronze   : MB.Bronze_Result;
      State    : in out Emit_State);
   procedure Render_Shared_Object_Body
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Decl     : CM.Resolved_Object_Decl;
      Bronze   : MB.Bronze_Result;
      State    : in out Emit_State);
   procedure Render_Channel_Spec
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Channel  : CM.Resolved_Channel_Decl;
      Bronze  : MB.Bronze_Result);
   procedure Render_Channel_Body
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Channel  : CM.Resolved_Channel_Decl;
      State    : in out Emit_State);
   procedure Render_Channel_Generated_Value_Helpers
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Channel  : CM.Resolved_Channel_Decl;
      State    : in out Emit_State);
   function Effective_Subprogram_Outer_Declarations
     (Subprogram              : CM.Resolved_Subprogram;
      Raw_Outer_Declarations : CM.Resolved_Object_Decl_Vectors.Vector)
      return CM.Resolved_Object_Decl_Vectors.Vector;
   function Apply_Name_Replacements
     (Text       : String;
      From_Names : FT.UString_Vectors.Vector;
      To_Names   : FT.UString_Vectors.Vector) return String;
   function Render_Structural_Traversal_Subprogram_Body
     (Buffer     : in out SU.Unbounded_String;
      Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram;
      State      : in out Emit_State) return Boolean;
   procedure Render_Subprogram_Body
     (Buffer     : in out SU.Unbounded_String;
      Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram;
      State      : in out Emit_State);
   procedure Render_Task_Body
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Task_Item : CM.Resolved_Task;
      State    : in out Emit_State);
   function Decl_Uses_Deferred_Package_Init_Name
     (Decl  : CM.Resolved_Object_Decl;
      Names : FT.UString_Vectors.Vector) return Boolean;
   function Decl_Uses_Package_Subprogram_Name
     (Unit : CM.Resolved_Unit;
      Decl : CM.Resolved_Object_Decl) return Boolean;
   function Should_Defer_Package_Object_Initializer
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Decl     : CM.Resolved_Object_Decl;
      Names    : FT.UString_Vectors.Vector) return Boolean;
   procedure Register_Deferred_Package_Init_Names
     (Decl  : CM.Resolved_Object_Decl;
      Names : in out FT.UString_Vectors.Vector);
   procedure Add_Body_With
     (Context : in out Emit_Context;
      Name    : String);
   procedure Add_Imported_Enum_Use_Type
     (Context : in out Emit_Context;
      Name    : String);
   function Package_Select_Refined_State
     (Context : Emit_Context) return String;
   function Expr_Uses_Public_Shared_Helper
     (Expr : CM.Expr_Access) return Boolean;
   function Statements_Use_Public_Shared_Helper
     (Statements : CM.Statement_Access_Vectors.Vector) return Boolean;
   procedure Prepare_Emit_Context
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Context  : in out Emit_Context);
   procedure Emit_Package_Spec
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Bronze   : MB.Bronze_Result;
      Context  : in out Emit_Context);
   procedure Emit_Package_Body
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Bronze   : MB.Bronze_Result;
      Context  : in out Emit_Context);
   procedure Finalize_Body_Text
     (Context : in out Emit_Context);
   procedure Finalize_Spec_Text
     (Context : in out Emit_Context);
   function Build_Emit_Result
     (Unit    : CM.Resolved_Unit;
      Context : Emit_Context) return Artifact_Result;

   function Gnat_Adc_Text return String is
     (Gnat_Adc_Contents);

   function Channel_Uses_Environment_Task
     (Bronze : MB.Bronze_Result;
      Name   : String) return Boolean
   is
   begin
      if Bronze.Graphs.Is_Empty then
         return False;
      end if;

      for Graph of Bronze.Graphs loop
         --  Bronze summaries already fold transitive callees into the unit
         --  initializer graph, so restricting this check to unit_init avoids
         --  over-raising ceilings for task-only helper subprograms.
         if FT.To_String (Graph.Kind) = "unit_init" then
            for Channel_Name of Graph.Channels loop
               if FT.To_String (Channel_Name) = Name then
                  return True;
               end if;
            end loop;
         end if;
      end loop;

      return False;
   end Channel_Uses_Environment_Task;

   function Channel_Uses_Unspecified_Task_Priority
     (Unit   : CM.Resolved_Unit;
      Bronze : MB.Bronze_Result;
      Name   : String) return Boolean
   is
   begin
      for Item of Bronze.Ceilings loop
         if FT.To_String (Item.Channel_Name) = Name then
            for Task_Name of Item.Task_Names loop
               for Task_Item of Unit.Tasks loop
                  if FT.To_String (Task_Item.Name) = FT.To_String (Task_Name)
                    and then not Task_Item.Has_Explicit_Priority
                  then
                     return True;
                  end if;
               end loop;
            end loop;
            exit;
         end if;
      end loop;

      return False;
   end Channel_Uses_Unspecified_Task_Priority;

   function Shared_Uses_Environment_Task
     (Bronze : MB.Bronze_Result;
      Name   : String) return Boolean
   is
   begin
      if Bronze.Graphs.Is_Empty then
         return False;
      end if;

      for Graph of Bronze.Graphs loop
         if FT.To_String (Graph.Kind) = "unit_init" then
            for Shared_Name of Graph.Shareds loop
               if FT.To_String (Shared_Name) = Name then
                  return True;
               end if;
            end loop;
         end if;
      end loop;

      return False;
   end Shared_Uses_Environment_Task;

   function Shared_Uses_Unspecified_Task_Priority
     (Unit   : CM.Resolved_Unit;
      Bronze : MB.Bronze_Result;
      Name   : String) return Boolean
   is
   begin
      for Item of Bronze.Shared_Ceilings loop
         if FT.To_String (Item.Shared_Name) = Name then
            for Task_Name of Item.Task_Names loop
               for Task_Item of Unit.Tasks loop
                  if FT.To_String (Task_Item.Name) = FT.To_String (Task_Name)
                    and then not Task_Item.Has_Explicit_Priority
                  then
                     return True;
                  end if;
               end loop;
            end loop;
            exit;
         end if;
      end loop;

      return False;
   end Shared_Uses_Unspecified_Task_Priority;

   function Shared_Required_Ceiling
     (Bronze : MB.Bronze_Result;
      Name   : String) return Long_Long_Integer
   is
   begin
      for Item of Bronze.Shared_Ceilings loop
         if FT.To_String (Item.Shared_Name) = Name then
            return Item.Priority;
         end if;
      end loop;

      return 0;
   end Shared_Required_Ceiling;

   function Canonical_Name (Value : String) return String is
   begin
      return FT.Lowercase (Value);
   end Canonical_Name;

   function Sanitize_Type_Name_Component (Value : String) return String
     renames FNU.Sanitize_Type_Name_Component;

   function Shared_Wrapper_Object_Name (Root_Name : String) return String is
   begin
      return
        "Safe_Shared_"
        & Sanitize_Type_Name_Component (Canonical_Name (Root_Name));
   end Shared_Wrapper_Object_Name;

   function Shared_Wrapper_Type_Name (Root_Name : String) return String is
   begin
      return Shared_Wrapper_Object_Name (Root_Name) & "_Wrapper";
   end Shared_Wrapper_Type_Name;

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
             (FT.To_String (Result)
              & "_"
              & Sanitize_Type_Name_Component (Canonical_Name (FT.To_String (Name))));
      end loop;
      return FT.To_String (Result);
   end Shared_Nested_Field_Setter_Name;

   function Is_Plain_Shared_Nested_Record
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean
   is
      Base      : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
      Name_Text : constant String := FT.Lowercase (FT.To_String (Base.Name));
   begin
      return FT.Lowercase (FT.To_String (Base.Kind)) = "record"
        and then not Base.Has_Discriminant
        and then Base.Discriminants.Is_Empty
        and then Base.Variant_Fields.Is_Empty
        and then not Base.Is_Result_Builtin
        and then not (Name_Text'Length > 11 and then Name_Text (Name_Text'First .. Name_Text'First + 10) = "__optional_");
   end Is_Plain_Shared_Nested_Record;

   function Shared_Call_Formal_Type
     (Unit          : CM.Resolved_Unit;
      Document      : GM.Mir_Document;
      Call_Expr     : CM.Expr_Access;
      Position      : Positive;
      Found         : out Boolean) return GM.Type_Descriptor
   is
      Root_Type        : GM.Type_Descriptor := (others => <>);
      Selector_Name    : FT.UString := FT.To_UString ("");

      function Optional_Type_Info (Info : GM.Type_Descriptor) return GM.Type_Descriptor is
      begin
         return
           Lookup_Type
             (Unit,
              Document,
              "__optional_" & Sanitize_Type_Name_Component (FT.To_String (Info.Name)));
      end Optional_Type_Info;

      function Try_Shared_Call_Target return Boolean is
         Flat_Callee : constant String :=
           (if Call_Expr = null or else Call_Expr.Callee = null
            then ""
            else CM.Flatten_Name (Call_Expr.Callee));
         Dot_Index : Natural := 0;
      begin
         if Call_Expr = null
           or else Call_Expr.Callee = null
         then
            return False;
         end if;

         for Index in reverse Flat_Callee'Range loop
            if Flat_Callee (Index) = '.' then
               Dot_Index := Index;
               exit;
            end if;
         end loop;

         if Dot_Index > 0 then
            declare
               Prefix_Name : constant String :=
                 Flat_Callee (Flat_Callee'First .. Dot_Index - 1);
               Prefix_Key : constant String := FT.Lowercase (Prefix_Name);
               Selector_Text : constant String :=
                  Flat_Callee (Dot_Index + 1 .. Flat_Callee'Last);
            begin
               for Decl of Unit.Objects loop
                  if Decl.Is_Shared and then not Decl.Names.Is_Empty then
                     declare
                        Wrapper_Key : constant String :=
                          FT.Lowercase
                            (Shared_Wrapper_Object_Name
                               (FT.To_String (Decl.Names (Decl.Names.First_Index))));
                     begin
                        if Prefix_Key = Wrapper_Key
                          or else
                            (Prefix_Key'Length > Wrapper_Key'Length
                             and then Prefix_Key
                               (Prefix_Key'Last - Wrapper_Key'Length .. Prefix_Key'Last)
                                 = "." & Wrapper_Key)
                        then
                           Root_Type := Decl.Type_Info;
                           Selector_Name := FT.To_UString (Selector_Text);
                           return True;
                        end if;
                     end;
                  end if;
               end loop;
            end;
         end if;

         if Call_Expr.Callee.Kind = CM.Expr_Select
           and then Call_Expr.Callee.Prefix /= null
           and then Call_Expr.Callee.Prefix.Kind = CM.Expr_Ident
         then
            for Decl of Unit.Objects loop
               if Decl.Is_Shared and then not Decl.Names.Is_Empty then
                  declare
                     Wrapper_Key : constant String :=
                       FT.Lowercase
                         (Shared_Wrapper_Object_Name
                            (FT.To_String (Decl.Names (Decl.Names.First_Index))));
                     Prefix_Key : constant String :=
                       FT.Lowercase (FT.To_String (Call_Expr.Callee.Prefix.Name));
                  begin
                     if Prefix_Key = Wrapper_Key
                       or else
                         (Prefix_Key'Length > Wrapper_Key'Length
                          and then Prefix_Key
                            (Prefix_Key'Last - Wrapper_Key'Length .. Prefix_Key'Last)
                              = "." & Wrapper_Key)
                     then
                        Root_Type := Decl.Type_Info;
                        Selector_Name := Call_Expr.Callee.Selector;
                        return True;
                     end if;
                  end;
               end if;
            end loop;
         end if;

         declare
            Helper_Name : constant String :=
              (if Call_Expr.Callee.Kind = CM.Expr_Ident
               then FT.To_String (Call_Expr.Callee.Name)
               elsif Call_Expr.Callee.Kind = CM.Expr_Select
               then CM.Flatten_Name (Call_Expr.Callee)
               else "");
            Helper_Key : constant String := FT.Lowercase (Helper_Name);
         begin
            for Decl of Unit.Objects loop
               if Decl.Is_Shared
                 and then Decl.Is_Public
                 and then not Decl.Names.Is_Empty
               then
                  declare
                     Root_Name : constant String :=
                       FT.To_String (Decl.Names (Decl.Names.First_Index));
                     Prefix : constant String :=
                       Shared_Public_Helper_Base_Name (Root_Name) & "_";
                     Prefix_Key : constant String := FT.Lowercase (Prefix);
                  begin
                     if Starts_With (Helper_Key, Prefix_Key)
                       and then Helper_Key'Length > Prefix_Key'Length
                     then
                        Root_Type := Decl.Type_Info;
                        Selector_Name :=
                          FT.To_UString (Helper_Name (Prefix'Length + 1 .. Helper_Name'Last));
                        return True;
                     end if;
                  end;
               end if;
            end loop;
         end;

         return False;
      end Try_Shared_Call_Target;

      function Nested_Setter_Type
        (Info       : GM.Type_Descriptor;
         Path_Names : FT.UString_Vectors.Vector) return GM.Type_Descriptor
      is
         Base : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
      begin
         for Field of Base.Fields loop
            declare
               Next_Path       : FT.UString_Vectors.Vector := Path_Names;
               Field_Type_Name : constant String := FT.To_String (Field.Type_Name);
               Field_Info      : constant GM.Type_Descriptor :=
                 Lookup_Type (Unit, Document, Field_Type_Name);
            begin
               Next_Path.Append (Field.Name);
               if Natural (Next_Path.Length) >= 2
                 and then FT.Lowercase (Shared_Nested_Field_Setter_Name (Next_Path))
                   = FT.Lowercase (FT.To_String (Selector_Name))
               then
                  Found := True;
                  return Field_Info;
               end if;

               if Is_Plain_Shared_Nested_Record (Unit, Document, Field_Info) then
                  declare
                     Nested_Info : constant GM.Type_Descriptor :=
                       Nested_Setter_Type (Field_Info, Next_Path);
                  begin
                     if Found then
                        return Nested_Info;
                     end if;
                  end;
               end if;
            end;
         end loop;

         Found := False;
         return (others => <>);
      end Nested_Setter_Type;
   begin
      Found := False;

      if Call_Expr = null
        or else Call_Expr.Kind /= CM.Expr_Call
        or else Call_Expr.Args.Is_Empty
        or else Position > Call_Expr.Args.Last_Index
      then
         return (others => <>);
      end if;

      if not Try_Shared_Call_Target then
         return (others => <>);
      end if;

      declare
         Root_Base     : constant GM.Type_Descriptor := Base_Type (Unit, Document, Root_Type);
         Selector_Text : constant String := FT.To_String (Selector_Name);
         Selector_Key  : constant String := FT.Lowercase (Selector_Text);
         Element_Type  : GM.Type_Descriptor := (others => <>);
         Key_Type      : GM.Type_Descriptor := (others => <>);
         Value_Type    : GM.Type_Descriptor := (others => <>);
      begin
         if Selector_Key in FT.Lowercase ("Initialize") | FT.Lowercase ("Set_All")
           and then Position = 1
         then
            Found := True;
            return Root_Type;
         elsif Is_Growable_Array_Type (Unit, Document, Root_Base)
           and then Try_Map_Key_Value_Types
             (Unit,
              Document,
              Root_Base,
              Key_Type,
              Value_Type)
         then
            if Selector_Key in FT.Lowercase (Shared_Contains_Name) | FT.Lowercase (Shared_Get_Name)
              and then Position = 1
            then
               Found := True;
               return Key_Type;
            elsif Selector_Key = FT.Lowercase (Shared_Set_Name) then
               if Position = 1 then
                  Found := True;
                  return Key_Type;
               elsif Position = 2 then
                  Found := True;
                  return Value_Type;
               end if;
            elsif Selector_Key = FT.Lowercase (Shared_Remove_Name) then
               if Position = 1 then
                  Found := True;
                  return Key_Type;
               elsif Position = 2 then
                  Found := True;
                  return Optional_Type_Info (Value_Type);
               end if;
            end if;
         elsif Is_Growable_Array_Type (Unit, Document, Root_Base)
           and then Root_Base.Has_Component_Type
         then
            Element_Type :=
              Lookup_Type (Unit, Document, FT.To_String (Root_Base.Component_Type));
            if Selector_Key = FT.Lowercase (Shared_Append_Name)
              and then Position = 1
            then
               Found := True;
               return Element_Type;
            elsif Selector_Key = FT.Lowercase (Shared_Pop_Last_Name)
              and then Position = 1
            then
               Found := True;
               return Optional_Type_Info (Element_Type);
            end if;
         elsif Position = 1 then
            for Field of Root_Base.Fields loop
               if FT.Lowercase
                    (Shared_Field_Setter_Name (FT.To_String (Field.Name))) = Selector_Key
               then
                  Found := True;
                  return Lookup_Type (Unit, Document, FT.To_String (Field.Type_Name));
               end if;
            end loop;

            declare
               Empty_Path : FT.UString_Vectors.Vector;
               Nested_Info : constant GM.Type_Descriptor :=
                 Nested_Setter_Type (Root_Type, Empty_Path);
            begin
               if Found then
                  return Nested_Info;
               end if;
            end;
         end if;
      end;

      return (others => <>);
   end Shared_Call_Formal_Type;

   procedure Render_Shared_Object_Spec
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Decl     : CM.Resolved_Object_Decl;
      Bronze   : MB.Bronze_Result;
      State    : in out Emit_State)
   is
      Root_Name     : constant String := FT.To_String (Decl.Names (Decl.Names.First_Index));
      Wrapper_Name  : constant String := Shared_Wrapper_Object_Name (Root_Name);
      Type_Name     : constant String := Shared_Wrapper_Type_Name (Root_Name);
      Record_Type   : constant String := Render_Type_Name (Decl.Type_Info);
      Record_Default : constant String := Default_Value_Expr (Unit, Document, Decl.Type_Info);
      Base_Info     : constant GM.Type_Descriptor := Base_Type (Unit, Document, Decl.Type_Info);
      Integer_Type_Name : constant String :=
        Render_Type_Name (Resolve_Type_Name (Unit, Document, "integer"));
      Is_Public_Shared : constant Boolean := Decl.Is_Public;
      Uses_Environment_Ceiling : constant Boolean :=
        Decl.Is_Public
        or else Shared_Uses_Environment_Task (Bronze, Root_Name)
        or else Shared_Uses_Unspecified_Task_Priority (Unit, Bronze, Root_Name);
      Ceiling : constant Long_Long_Integer :=
        Shared_Required_Ceiling (Bronze, Root_Name);
      Is_Container_Root : constant Boolean :=
        Is_Growable_Array_Type (Unit, Document, Decl.Type_Info);
      Element_Info : constant GM.Type_Descriptor :=
        (if Is_Container_Root
         then Resolve_Type_Name (Unit, Document, FT.To_String (Base_Info.Component_Type))
         else (others => <>));
      Key_Info     : GM.Type_Descriptor := (others => <>);
      Value_Info   : GM.Type_Descriptor := (others => <>);

      function Optional_Type_Name (Info : GM.Type_Descriptor) return String is
      begin
         return
           Render_Type_Name_From_Text
             (Unit,
              Document,
              "__optional_" & Sanitize_Type_Name_Component (FT.To_String (Info.Name)),
              State);
      end Optional_Type_Name;

      function Public_Helper_Name (Operation : String) return String is
      begin
         return Shared_Public_Helper_Name (Root_Name, Operation);
      end Public_Helper_Name;

      function Public_Shared_Function_Suffix return String is
      begin
         return " with Volatile_Function";
      end Public_Shared_Function_Suffix;

      procedure Append_Nested_Setter_Specs
        (Info       : GM.Type_Descriptor;
         Path_Names : FT.UString_Vectors.Vector)
      is
         Base : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
      begin
         for Field of Base.Fields loop
            declare
               Next_Path       : FT.UString_Vectors.Vector := Path_Names;
               Field_Type_Name : constant String := FT.To_String (Field.Type_Name);
               Field_Info      : constant GM.Type_Descriptor :=
                 Resolve_Type_Name (Unit, Document, Field_Type_Name);
            begin
               Next_Path.Append (Field.Name);
               if Natural (Next_Path.Length) >= 2 then
                  Append_Line
                    (Buffer,
                     "procedure "
                     & (if Is_Public_Shared
                        then Public_Helper_Name
                          (Shared_Nested_Field_Setter_Name (Next_Path))
                        else Shared_Nested_Field_Setter_Name (Next_Path))
                     & " (Value : in "
                     & Render_Type_Name_From_Text (Unit, Document, Field_Type_Name, State)
                     & ");",
                     (if Is_Public_Shared then 1 else 2));
                  if Is_Plain_String_Type (Unit, Document, Field_Info) then
                     State.Needs_Safe_String_RT := True;
                     Append_Line
                       (Buffer,
                        "procedure "
                        & (if Is_Public_Shared
                           then Public_Helper_Name
                             (Shared_Nested_Field_Setter_Name (Next_Path))
                           else Shared_Nested_Field_Setter_Name (Next_Path))
                        & " (Value : in String);",
                        (if Is_Public_Shared then 1 else 2));
                  end if;
               end if;

               if Is_Plain_Shared_Nested_Record (Unit, Document, Field_Info) then
                  Append_Nested_Setter_Specs (Field_Info, Next_Path);
               end if;
            end;
         end loop;
      end Append_Nested_Setter_Specs;
   begin
      if Is_Public_Shared then
         Append_Line
           (Buffer,
            "function " & Public_Helper_Name (Shared_Get_All_Name)
            & " return " & Record_Type
            & Public_Shared_Function_Suffix
            & ";",
            1);
         Append_Line
           (Buffer,
            "procedure " & Public_Helper_Name (Shared_Set_All_Name)
            & " (Value : in " & Record_Type & ");",
            1);
         if Is_Container_Root then
            Append_Line
              (Buffer,
               "function " & Public_Helper_Name (Shared_Get_Length_Name)
               & " return " & Integer_Type_Name
               & Public_Shared_Function_Suffix
               & ";",
               1);
            if Try_Map_Key_Value_Types (Unit, Document, Decl.Type_Info, Key_Info, Value_Info) then
               Append_Line
                 (Buffer,
                  "function " & Public_Helper_Name (Shared_Contains_Name)
                  & " (Key : in " & Render_Type_Name (Key_Info)
                  & ") return boolean"
                  & Public_Shared_Function_Suffix
                  & ";",
                  1);
               Append_Line
                 (Buffer,
                  "function " & Public_Helper_Name (Shared_Get_Name)
                  & " (Key : in " & Render_Type_Name (Key_Info)
                  & ") return " & Optional_Type_Name (Value_Info)
                  & Public_Shared_Function_Suffix
                  & ";",
                  1);
               Append_Line
                 (Buffer,
                  "procedure " & Public_Helper_Name (Shared_Set_Name)
                  & " (Key : in " & Render_Type_Name (Key_Info)
                  & "; Value : in " & Render_Type_Name (Value_Info) & ");",
                  1);
               Append_Line
                 (Buffer,
                  "procedure " & Public_Helper_Name (Shared_Remove_Name)
                  & " (Key : in " & Render_Type_Name (Key_Info)
                  & "; Result : out " & Optional_Type_Name (Value_Info) & ");",
                  1);
            else
               Append_Line
                 (Buffer,
                  "procedure " & Public_Helper_Name (Shared_Append_Name)
                  & " (Value : in " & Render_Type_Name (Element_Info) & ");",
                  1);
               Append_Line
                 (Buffer,
                  "procedure " & Public_Helper_Name (Shared_Pop_Last_Name)
                  & " (Result : out " & Optional_Type_Name (Element_Info) & ");",
                  1);
            end if;
         else
            for Field of Base_Info.Fields loop
               declare
                  Field_Info : constant GM.Type_Descriptor :=
                    Resolve_Type_Name (Unit, Document, FT.To_String (Field.Type_Name));
                  Field_Type_Name : constant String :=
                    Render_Type_Name_From_Text
                      (Unit,
                       Document,
                       FT.To_String (Field.Type_Name),
                       State);
               begin
                  Append_Line
                    (Buffer,
                     "function "
                     & Public_Helper_Name
                         (Shared_Field_Getter_Name (FT.To_String (Field.Name)))
                     & " return "
                     & Field_Type_Name
                     & Public_Shared_Function_Suffix
                     & ";",
                     1);
                  Append_Line
                    (Buffer,
                     "procedure "
                     & Public_Helper_Name
                         (Shared_Field_Setter_Name (FT.To_String (Field.Name)))
                     & " (Value : in "
                     & Field_Type_Name
                     & ");",
                     1);
                  if Is_Plain_String_Type (Unit, Document, Field_Info) then
                     State.Needs_Safe_String_RT := True;
                     Append_Line
                       (Buffer,
                        "procedure "
                        & Public_Helper_Name
                            (Shared_Field_Setter_Name (FT.To_String (Field.Name)))
                        & " (Value : in String);",
                        1);
                  end if;
               end;
            end loop;
            declare
               Empty_Path : FT.UString_Vectors.Vector;
            begin
               Append_Nested_Setter_Specs (Decl.Type_Info, Empty_Path);
            end;
         end if;
         Append_Line (Buffer);
         return;
      end if;

      Append_Line
        (Buffer,
         "protected type "
         & Type_Name
         & " with Priority => "
         & (if Uses_Environment_Ceiling or else Ceiling <= 0
            then "System.Any_Priority'Last"
            else Trim_Image (Ceiling))
         & " is",
         1);
      Append_Line
        (Buffer,
         "function " & Shared_Get_All_Name & " return " & Record_Type & ";",
         2);
      Append_Line
        (Buffer,
         "procedure " & Shared_Set_All_Name & " (Value : in " & Record_Type & ");",
         2);
      if Is_Container_Root then
         Append_Line
           (Buffer,
            "function " & Shared_Get_Length_Name & " return " & Integer_Type_Name & ";",
            2);
         if Try_Map_Key_Value_Types (Unit, Document, Decl.Type_Info, Key_Info, Value_Info) then
            Append_Line
              (Buffer,
               "function " & Shared_Contains_Name & " (Key : in "
               & Render_Type_Name (Key_Info) & ") return boolean;",
               2);
            Append_Line
              (Buffer,
               "function " & Shared_Get_Name & " (Key : in "
               & Render_Type_Name (Key_Info) & ") return "
               & Optional_Type_Name (Value_Info) & ";",
               2);
            Append_Line
              (Buffer,
               "procedure " & Shared_Set_Name & " (Key : in "
               & Render_Type_Name (Key_Info) & "; Value : in "
               & Render_Type_Name (Value_Info) & ");",
               2);
            Append_Line
              (Buffer,
               "procedure " & Shared_Remove_Name & " (Key : in "
               & Render_Type_Name (Key_Info) & "; Result : out "
               & Optional_Type_Name (Value_Info) & ");",
               2);
         else
            Append_Line
              (Buffer,
               "procedure " & Shared_Append_Name & " (Value : in "
               & Render_Type_Name (Element_Info) & ");",
               2);
            Append_Line
              (Buffer,
               "procedure " & Shared_Pop_Last_Name & " (Result : out "
               & Optional_Type_Name (Element_Info) & ");",
               2);
         end if;
      else
         for Field of Base_Info.Fields loop
            declare
               Field_Info : constant GM.Type_Descriptor :=
                 Resolve_Type_Name (Unit, Document, FT.To_String (Field.Type_Name));
               Field_Type_Name : constant String :=
                 Render_Type_Name_From_Text
                   (Unit,
                    Document,
                    FT.To_String (Field.Type_Name),
                    State);
            begin
               Append_Line
                 (Buffer,
                  "function "
                  & Shared_Field_Getter_Name (FT.To_String (Field.Name))
                  & " return "
                  & Field_Type_Name
                  & ";",
                  2);
               Append_Line
                 (Buffer,
                  "procedure "
                  & Shared_Field_Setter_Name (FT.To_String (Field.Name))
                  & " (Value : in "
                  & Field_Type_Name
                  & ");",
                  2);
               if Is_Plain_String_Type (Unit, Document, Field_Info) then
                  State.Needs_Safe_String_RT := True;
                  Append_Line
                    (Buffer,
                     "procedure "
                     & Shared_Field_Setter_Name (FT.To_String (Field.Name))
                     & " (Value : in String);",
                     2);
               end if;
            end;
         end loop;
         declare
            Empty_Path : FT.UString_Vectors.Vector;
         begin
            Append_Nested_Setter_Specs (Decl.Type_Info, Empty_Path);
         end;
      end if;
      Append_Line
        (Buffer,
         "procedure Initialize (Value : in " & Record_Type & ");",
         2);
      Append_Line (Buffer, "private", 1);
      Append_Line
        (Buffer,
         "State_Value : " & Record_Type & " := " & Record_Default & ";",
         2);
      Append_Line (Buffer, "end " & Type_Name & ";", 1);
      Append_Line (Buffer, Wrapper_Name & " : " & Type_Name & ";", 1);
      Append_Line (Buffer);
   end Render_Shared_Object_Spec;

   procedure Render_Shared_Object_Body
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Decl     : CM.Resolved_Object_Decl;
      Bronze   : MB.Bronze_Result;
      State    : in out Emit_State)
   is
      Root_Name    : constant String := FT.To_String (Decl.Names (Decl.Names.First_Index));
      Wrapper_Name : constant String := Shared_Wrapper_Object_Name (Root_Name);
      Type_Name    : constant String := Shared_Wrapper_Type_Name (Root_Name);
      Root_Type    : constant String := Render_Type_Name (Decl.Type_Info);
      Base_Info    : constant GM.Type_Descriptor := Base_Type (Unit, Document, Decl.Type_Info);
      Is_Public_Shared : constant Boolean := Decl.Is_Public;
      Heap_Root    : constant Boolean :=
        Has_Heap_Value_Type (Unit, Document, Decl.Type_Info);
      Is_Container_Root : constant Boolean :=
        Is_Growable_Array_Type (Unit, Document, Decl.Type_Info);
      Integer_Type_Name : constant String :=
        Render_Type_Name (Resolve_Type_Name (Unit, Document, "integer"));
      Uses_Environment_Ceiling : constant Boolean :=
        Decl.Is_Public
        or else Shared_Uses_Environment_Task (Bronze, Root_Name)
        or else Shared_Uses_Unspecified_Task_Priority (Unit, Bronze, Root_Name);
      Ceiling : constant Long_Long_Integer :=
        Shared_Required_Ceiling (Bronze, Root_Name);
      Key_Info     : GM.Type_Descriptor := (others => <>);
      Value_Info   : GM.Type_Descriptor := (others => <>);
      Generated_Shared_Helpers : FT.UString_Vectors.Vector;
      Runtime_Dependency_Types  : FT.UString_Vectors.Vector;

      function Optional_Type_Name (Info : GM.Type_Descriptor) return String is
      begin
         return
           Render_Type_Name_From_Text
             (Unit,
              Document,
              "__optional_" & Sanitize_Type_Name_Component (FT.To_String (Info.Name)),
              State);
      end Optional_Type_Name;

      function Optional_Default_Expr (Info : GM.Type_Descriptor) return String is
      begin
         return Optional_Type_Name (Info) & "'(present => False)";
      end Optional_Default_Expr;

      function Public_Helper_Name (Operation : String) return String is
      begin
         return Shared_Public_Helper_Name (Root_Name, Operation);
      end Public_Helper_Name;

      function Shared_Copy_Helper_Name (Info : GM.Type_Descriptor) return String is
      begin
         return
           Heap_Copy_Helper_Name
             (AI.Heap_Helper_Shared, Wrapper_Name, Unit, Document, Info);
      end Shared_Copy_Helper_Name;

      function Shared_Free_Helper_Name (Info : GM.Type_Descriptor) return String is
      begin
         return
           Heap_Free_Helper_Name
             (AI.Heap_Helper_Shared, Wrapper_Name, Unit, Document, Info);
      end Shared_Free_Helper_Name;

      procedure Append_Copy_Value
        (Target_Text : String;
         Source_Text : String;
         Info        : GM.Type_Descriptor;
         Depth       : Natural) is
      begin
         Append_Heap_Copy_Value
           (Buffer,
            Unit,
            Document,
            State,
            AI.Heap_Helper_Shared,
            Wrapper_Name,
            Target_Text,
            Source_Text,
            Info,
            Depth);
      end Append_Copy_Value;

      procedure Append_Free_Value
        (Target_Text : String;
         Info        : GM.Type_Descriptor;
         Depth       : Natural) is
      begin
         Append_Heap_Free_Value
           (Buffer,
            Unit,
            Document,
            State,
            AI.Heap_Helper_Shared,
            Wrapper_Name,
            Target_Text,
            Info,
            Depth);
      end Append_Free_Value;

      procedure Render_Shared_Value_Helpers (Info : GM.Type_Descriptor);

      procedure Render_Shared_Value_Helpers (Info : GM.Type_Descriptor) is
         Base      : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
         Kind      : constant String := FT.Lowercase (FT.To_String (Base.Kind));
         Type_Key  : constant String := Render_Type_Name (Info);
         Type_Name : constant String := Render_Type_Name (Info);

         procedure Ensure_Helper (Name_Text : String) is
         begin
            if Name_Text'Length = 0 then
               return;
            end if;

            Render_Shared_Value_Helpers
              (Resolve_Type_Name (Unit, Document, Name_Text));
         end Ensure_Helper;
      begin
         if Contains_Name (Generated_Shared_Helpers, Type_Key) then
            return;
         end if;

         if not Needs_Generated_Heap_Helper (Unit, Document, Info) then
            if Is_Growable_Array_Type (Unit, Document, Base)
              and then Base.Has_Component_Type
            then
               Ensure_Helper (FT.To_String (Base.Component_Type));
            end if;
            return;
         end if;

         if Starts_With (FT.To_String (Base.Name), "__optional_") then
            declare
               Payload_Info : constant GM.Type_Descriptor :=
                 Resolve_Type_Name
                   (Unit,
                    Document,
                    FT.To_String
                      (Base.Variant_Fields (Base.Variant_Fields.First_Index).Type_Name));
            begin
               Ensure_Helper
                 (FT.To_String
                    (Base.Variant_Fields (Base.Variant_Fields.First_Index).Type_Name));
               Generated_Shared_Helpers.Append (FT.To_UString (Type_Key));

               Append_Line
                 (Buffer,
                  "procedure "
                  & Shared_Copy_Helper_Name (Info)
                  & " (Target : out "
                  & Type_Name
                  & "; Source : "
                  & Type_Name
                  & ");",
                  1);
               Append_Line
                 (Buffer,
                  "procedure "
                  & Shared_Copy_Helper_Name (Info)
                  & " (Target : out "
                  & Type_Name
                  & "; Source : "
                  & Type_Name
                  & ") is",
                  1);
               Append_Line (Buffer, "pragma SPARK_Mode (Off);", 2);
               Append_Line (Buffer, "begin", 1);
               Append_Line (Buffer, "Target := Source;", 2);
               Append_Line (Buffer, "if Source.present then", 2);
               Append_Heap_Copy_Value
                 (Buffer,
                  Unit,
                  Document,
                  State,
                  AI.Heap_Helper_Shared,
                  Wrapper_Name,
                  "Target.value",
                  "Source.value",
                  Payload_Info,
                  3);
               Append_Line (Buffer, "end if;", 2);
               Append_Line (Buffer, "end " & Shared_Copy_Helper_Name (Info) & ";", 1);
               Append_Line (Buffer);

               Append_Line
                 (Buffer,
                  "procedure "
                  & Shared_Free_Helper_Name (Info)
                  & " (Value : in out "
                  & Type_Name
                  & ");",
                  1);
               Append_Line
                 (Buffer,
                  "procedure "
                  & Shared_Free_Helper_Name (Info)
                  & " (Value : in out "
                  & Type_Name
                  & ") is",
                  1);
               Append_Line (Buffer, "pragma SPARK_Mode (Off);", 2);
               Append_Line (Buffer, "begin", 1);
               Append_Line (Buffer, "if Value.present then", 2);
               Append_Heap_Free_Value
                 (Buffer,
                  Unit,
                  Document,
                  State,
                  AI.Heap_Helper_Shared,
                  Wrapper_Name,
                  "Value.value",
                  Payload_Info,
                  3);
               Append_Line (Buffer, "end if;", 2);
               Append_Line
                 (Buffer,
                  "Value := " & Default_Value_Expr (Unit, Document, Info) & ";",
                  2);
               Append_Line (Buffer, "end " & Shared_Free_Helper_Name (Info) & ";", 1);
               Append_Line (Buffer);
               return;
            end;
         end if;

         if Kind = "array" and then Base.Has_Component_Type then
            Ensure_Helper (FT.To_String (Base.Component_Type));
         elsif Kind = "record" then
            for Field of Base.Fields loop
               Ensure_Helper (FT.To_String (Field.Type_Name));
            end loop;
            for Field of Base.Variant_Fields loop
               Ensure_Helper (FT.To_String (Field.Type_Name));
            end loop;
         elsif Is_Tuple_Type (Base) then
            for Item of Base.Tuple_Element_Types loop
               Ensure_Helper (FT.To_String (Item));
            end loop;
         end if;

         Generated_Shared_Helpers.Append (FT.To_UString (Type_Key));

         Append_Line
           (Buffer,
            "procedure "
            & Shared_Copy_Helper_Name (Info)
            & " (Target : out "
            & Type_Name
            & "; Source : "
            & Type_Name
            & ");",
            1);
         Append_Line
           (Buffer,
            "procedure "
            & Shared_Copy_Helper_Name (Info)
            & " (Target : out "
            & Type_Name
            & "; Source : "
            & Type_Name
            & ") is",
            1);
         Append_Line (Buffer, "pragma SPARK_Mode (Off);", 2);
         Append_Line (Buffer, "begin", 1);
         Append_Generated_Heap_Copy_Body
           (Buffer,
            Unit,
            Document,
            State,
            AI.Heap_Helper_Shared,
            Wrapper_Name,
            Info,
            2);
         Append_Line (Buffer, "end " & Shared_Copy_Helper_Name (Info) & ";", 1);
         Append_Line (Buffer);

         Append_Line
           (Buffer,
            "procedure "
            & Shared_Free_Helper_Name (Info)
            & " (Value : in out "
            & Type_Name
            & ");",
            1);
         Append_Line
           (Buffer,
            "procedure "
            & Shared_Free_Helper_Name (Info)
            & " (Value : in out "
            & Type_Name
            & ") is",
            1);
         Append_Line (Buffer, "pragma SPARK_Mode (Off);", 2);
         Append_Line (Buffer, "begin", 1);
         Append_Generated_Heap_Free_Body
           (Buffer,
            Unit,
            Document,
            State,
            AI.Heap_Helper_Shared,
            Wrapper_Name,
            Info,
            2);
         Append_Line
           (Buffer,
            "Value := " & Default_Value_Expr (Unit, Document, Info) & ";",
            2);
         Append_Line (Buffer, "end " & Shared_Free_Helper_Name (Info) & ";", 1);
         Append_Line (Buffer);
      end Render_Shared_Value_Helpers;

      procedure Append_Nested_Setter_Bodies
        (Info       : GM.Type_Descriptor;
         Path_Names : FT.UString_Vectors.Vector)
      is
         Base : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
      begin
         for Field of Base.Fields loop
            declare
               Next_Path       : FT.UString_Vectors.Vector := Path_Names;
               Field_Type_Name : constant String := FT.To_String (Field.Type_Name);
               Field_Info      : constant GM.Type_Descriptor :=
                 Resolve_Type_Name (Unit, Document, Field_Type_Name);
               Field_Path      : SU.Unbounded_String := SU.To_Unbounded_String ("State_Value");
            begin
               Next_Path.Append (Field.Name);
               for Part of Next_Path loop
                  Field_Path := Field_Path & "." & FT.To_String (Part);
               end loop;

               if Natural (Next_Path.Length) >= 2 then
                  Append_Line
                    (Buffer,
                     "procedure "
                     & Shared_Nested_Field_Setter_Name (Next_Path)
                     & " (Value : in "
                     & Render_Type_Name_From_Text (Unit, Document, Field_Type_Name, State)
                     & ") is",
                     2);
                  if Heap_Root then
                     Append_Line (Buffer, "pragma SPARK_Mode (Off);", 3);
                  end if;
                  Append_Line (Buffer, "begin", 2);
                  if Has_Heap_Value_Type (Unit, Document, Field_Info) then
                     Append_Free_Value (SU.To_String (Field_Path), Field_Info, 3);
                     Append_Copy_Value
                       (SU.To_String (Field_Path),
                        "Value",
                        Field_Info,
                        3);
                  else
                     Append_Line (Buffer, SU.To_String (Field_Path) & " := Value;", 3);
                  end if;
                  Append_Line
                    (Buffer,
                     "end " & Shared_Nested_Field_Setter_Name (Next_Path) & ";",
                     2);
                  Append_Line (Buffer);
                  if Is_Plain_String_Type (Unit, Document, Field_Info) then
                     State.Needs_Safe_String_RT := True;
                     Append_Line
                       (Buffer,
                        "procedure "
                        & Shared_Nested_Field_Setter_Name (Next_Path)
                        & " (Value : in String) is",
                        2);
                     Append_Line (Buffer, "pragma SPARK_Mode (Off);", 3);
                     Append_Line (Buffer, "begin", 2);
                     Append_Line
                       (Buffer,
                        Shared_Nested_Field_Setter_Name (Next_Path)
                        & " (Safe_String_RT.From_Literal (Value));",
                        3);
                     Append_Line
                       (Buffer,
                        "end " & Shared_Nested_Field_Setter_Name (Next_Path) & ";",
                        2);
                     Append_Line (Buffer);
                  end if;
               end if;

               if Is_Plain_Shared_Nested_Record (Unit, Document, Field_Info) then
                  Append_Nested_Setter_Bodies (Field_Info, Next_Path);
               end if;
            end;
         end loop;
      end Append_Nested_Setter_Bodies;

      procedure Append_Private_Wrapper_Declarations is
         Record_Default : constant String :=
           Default_Value_Expr (Unit, Document, Decl.Type_Info);

         procedure Append_Nested_Setter_Specs
           (Info       : GM.Type_Descriptor;
            Path_Names : FT.UString_Vectors.Vector)
         is
            Base : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
         begin
            for Field of Base.Fields loop
               declare
                  Next_Path       : FT.UString_Vectors.Vector := Path_Names;
                  Field_Type_Name : constant String := FT.To_String (Field.Type_Name);
                  Field_Info      : constant GM.Type_Descriptor :=
                    (if Has_Type (Unit, Document, Field_Type_Name)
                     then Lookup_Type (Unit, Document, Field_Type_Name)
                     else (others => <>));
               begin
                  Next_Path.Append (Field.Name);
                  if Natural (Next_Path.Length) >= 2 then
                     Append_Line
                       (Buffer,
                        "procedure "
                        & Shared_Nested_Field_Setter_Name (Next_Path)
                        & " (Value : in "
                        & Render_Type_Name_From_Text
                            (Unit,
                             Document,
                             Field_Type_Name,
                             State)
                        & ");",
                        2);
                  end if;

                  if Is_Plain_Shared_Nested_Record (Unit, Document, Field_Info) then
                     Append_Nested_Setter_Specs (Field_Info, Next_Path);
                  end if;
               end;
            end loop;
         end Append_Nested_Setter_Specs;
      begin
         Append_Line
           (Buffer,
            "protected type "
            & Type_Name
            & " with Priority => "
            & (if Uses_Environment_Ceiling or else Ceiling <= 0
               then "System.Any_Priority'Last"
               else Trim_Image (Ceiling))
            & " is",
            1);
         Append_Line
           (Buffer,
            "function " & Shared_Get_All_Name & " return " & Root_Type & ";",
            2);
         Append_Line
           (Buffer,
            "procedure " & Shared_Set_All_Name & " (Value : in " & Root_Type & ");",
            2);
         if Is_Container_Root then
            Append_Line
              (Buffer,
               "function " & Shared_Get_Length_Name & " return "
               & Integer_Type_Name & ";",
               2);
            if Try_Map_Key_Value_Types (Unit, Document, Decl.Type_Info, Key_Info, Value_Info) then
               Append_Line
                 (Buffer,
                  "function " & Shared_Contains_Name & " (Key : in "
                  & Render_Type_Name (Key_Info) & ") return boolean;",
                  2);
               Append_Line
                 (Buffer,
                  "function " & Shared_Get_Name & " (Key : in "
                  & Render_Type_Name (Key_Info) & ") return "
                  & Optional_Type_Name (Value_Info) & ";",
                  2);
               Append_Line
                 (Buffer,
                  "procedure " & Shared_Set_Name & " (Key : in "
                  & Render_Type_Name (Key_Info) & "; Value : in "
                  & Render_Type_Name (Value_Info) & ");",
                  2);
               Append_Line
                 (Buffer,
                  "procedure " & Shared_Remove_Name & " (Key : in "
                  & Render_Type_Name (Key_Info) & "; Result : out "
                  & Optional_Type_Name (Value_Info) & ");",
                  2);
            else
               Append_Line
                 (Buffer,
                  "procedure " & Shared_Append_Name & " (Value : in "
                  & Render_Type_Name (Resolve_Type_Name
                    (Unit,
                     Document,
                     FT.To_String (Base_Info.Component_Type))) & ");",
                  2);
               Append_Line
                 (Buffer,
                  "procedure " & Shared_Pop_Last_Name & " (Result : out "
                  & Optional_Type_Name
                      (Resolve_Type_Name
                         (Unit,
                          Document,
                          FT.To_String (Base_Info.Component_Type)))
                  & ");",
                  2);
            end if;
         else
            for Field of Base_Info.Fields loop
               declare
                  Field_Info : constant GM.Type_Descriptor :=
                    Resolve_Type_Name (Unit, Document, FT.To_String (Field.Type_Name));
                  Field_Type_Name : constant String :=
                    Render_Type_Name_From_Text
                      (Unit,
                       Document,
                       FT.To_String (Field.Type_Name),
                       State);
               begin
                  Append_Line
                    (Buffer,
                     "function "
                     & Shared_Field_Getter_Name (FT.To_String (Field.Name))
                     & " return "
                     & Field_Type_Name
                     & ";",
                     2);
                  Append_Line
                    (Buffer,
                     "procedure "
                     & Shared_Field_Setter_Name (FT.To_String (Field.Name))
                     & " (Value : in "
                     & Field_Type_Name
                     & ");",
                     2);
               end;
            end loop;
            declare
               Empty_Path : FT.UString_Vectors.Vector;
            begin
               Append_Nested_Setter_Specs (Decl.Type_Info, Empty_Path);
            end;
         end if;
         Append_Line
           (Buffer,
            "procedure Initialize (Value : in " & Root_Type & ");",
            2);
         Append_Line (Buffer, "private", 1);
         Append_Line
           (Buffer,
            "State_Value : " & Root_Type & " := " & Record_Default & ";",
            2);
         Append_Line (Buffer, "end " & Type_Name & ";", 1);
         Append_Line (Buffer, Wrapper_Name & " : " & Type_Name & ";", 1);
         Append_Line (Buffer);
      end Append_Private_Wrapper_Declarations;

      procedure Append_Public_Helper_Bodies is
         procedure Append_Public_Nested_Setter_Bodies
           (Info       : GM.Type_Descriptor;
            Path_Names : FT.UString_Vectors.Vector)
         is
            Base : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
         begin
            for Field of Base.Fields loop
               declare
                  Next_Path       : FT.UString_Vectors.Vector := Path_Names;
                  Field_Type_Name : constant String := FT.To_String (Field.Type_Name);
                  Field_Info      : constant GM.Type_Descriptor :=
                    Resolve_Type_Name (Unit, Document, Field_Type_Name);
               begin
                  Next_Path.Append (Field.Name);
                  if Natural (Next_Path.Length) >= 2 then
                     Append_Line
                       (Buffer,
                        "procedure " & Public_Helper_Name
                          (Shared_Nested_Field_Setter_Name (Next_Path))
                        & " (Value : in "
                        & Render_Type_Name_From_Text
                            (Unit,
                             Document,
                             Field_Type_Name,
                             State)
                        & ") is",
                        1);
                     Append_Line (Buffer, "begin", 1);
                     Append_Line
                       (Buffer,
                        Wrapper_Name & "." & Shared_Nested_Field_Setter_Name (Next_Path)
                        & " (Value);",
                        2);
                     Append_Line
                       (Buffer,
                        "end " & Public_Helper_Name
                          (Shared_Nested_Field_Setter_Name (Next_Path)) & ";",
                        1);
                     Append_Line (Buffer);
                     if Is_Plain_String_Type (Unit, Document, Field_Info) then
                        State.Needs_Safe_String_RT := True;
                        Append_Line
                          (Buffer,
                           "procedure " & Public_Helper_Name
                             (Shared_Nested_Field_Setter_Name (Next_Path))
                           & " (Value : in String) is",
                           1);
                        Append_Line (Buffer, "pragma SPARK_Mode (Off);", 2);
                        Append_Line (Buffer, "begin", 1);
                        Append_Line
                          (Buffer,
                           Wrapper_Name & "." & Shared_Nested_Field_Setter_Name (Next_Path)
                           & " (Safe_String_RT.From_Literal (Value));",
                           2);
                        Append_Line
                          (Buffer,
                           "end " & Public_Helper_Name
                             (Shared_Nested_Field_Setter_Name (Next_Path)) & ";",
                           1);
                        Append_Line (Buffer);
                     end if;
                  end if;

                  if Is_Plain_Shared_Nested_Record (Unit, Document, Field_Info) then
                     Append_Public_Nested_Setter_Bodies (Field_Info, Next_Path);
                  end if;
               end;
            end loop;
         end Append_Public_Nested_Setter_Bodies;
      begin
         Append_Line
           (Buffer,
            "function " & Public_Helper_Name (Shared_Get_All_Name)
            & " return " & Root_Type & " is",
            1);
         Append_Line (Buffer, "pragma SPARK_Mode (Off);", 2);
         Append_Line (Buffer, "begin", 1);
         Append_Line
           (Buffer,
            "return " & Wrapper_Name & "." & Shared_Get_All_Name & ";",
            2);
         Append_Line
           (Buffer,
            "end " & Public_Helper_Name (Shared_Get_All_Name) & ";",
            1);
         Append_Line (Buffer);

         Append_Line
           (Buffer,
            "procedure " & Public_Helper_Name (Shared_Set_All_Name)
            & " (Value : in " & Root_Type & ") is",
            1);
         Append_Line (Buffer, "begin", 1);
         Append_Line
           (Buffer,
            Wrapper_Name & "." & Shared_Set_All_Name & " (Value);",
            2);
         Append_Line
           (Buffer,
            "end " & Public_Helper_Name (Shared_Set_All_Name) & ";",
            1);
         Append_Line (Buffer);

         if Is_Container_Root then
            Append_Line
              (Buffer,
               "function " & Public_Helper_Name (Shared_Get_Length_Name)
               & " return " & Integer_Type_Name & " is",
               1);
            Append_Line (Buffer, "pragma SPARK_Mode (Off);", 2);
            Append_Line (Buffer, "begin", 1);
            Append_Line
              (Buffer,
               "return " & Wrapper_Name & "." & Shared_Get_Length_Name & ";",
               2);
            Append_Line
              (Buffer,
               "end " & Public_Helper_Name (Shared_Get_Length_Name) & ";",
               1);
            Append_Line (Buffer);

            if Try_Map_Key_Value_Types (Unit, Document, Decl.Type_Info, Key_Info, Value_Info) then
               Append_Line
                 (Buffer,
                  "function " & Public_Helper_Name (Shared_Contains_Name)
                  & " (Key : in " & Render_Type_Name (Key_Info)
                  & ") return boolean is",
                  1);
               Append_Line (Buffer, "pragma SPARK_Mode (Off);", 2);
               Append_Line (Buffer, "begin", 1);
               Append_Line
                 (Buffer,
                  "return " & Wrapper_Name & "." & Shared_Contains_Name
                  & " (Key);",
                  2);
               Append_Line
                 (Buffer,
                  "end " & Public_Helper_Name (Shared_Contains_Name) & ";",
                  1);
               Append_Line (Buffer);

               Append_Line
                 (Buffer,
                  "function " & Public_Helper_Name (Shared_Get_Name)
                  & " (Key : in " & Render_Type_Name (Key_Info)
                  & ") return " & Optional_Type_Name (Value_Info)
                  & " is",
                  1);
               Append_Line (Buffer, "pragma SPARK_Mode (Off);", 2);
               Append_Line (Buffer, "begin", 1);
               Append_Line
                 (Buffer,
                  "return " & Wrapper_Name & "." & Shared_Get_Name
                  & " (Key);",
                  2);
               Append_Line
                 (Buffer,
                  "end " & Public_Helper_Name (Shared_Get_Name) & ";",
                  1);
               Append_Line (Buffer);

               Append_Line
                 (Buffer,
                  "procedure " & Public_Helper_Name (Shared_Set_Name)
                  & " (Key : in " & Render_Type_Name (Key_Info)
                  & "; Value : in " & Render_Type_Name (Value_Info)
                  & ") is",
                  1);
               Append_Line (Buffer, "begin", 1);
               Append_Line
                 (Buffer,
                  Wrapper_Name & "." & Shared_Set_Name & " (Key, Value);",
                  2);
               Append_Line
                 (Buffer,
                  "end " & Public_Helper_Name (Shared_Set_Name) & ";",
                  1);
               Append_Line (Buffer);

               Append_Line
                 (Buffer,
                  "procedure " & Public_Helper_Name (Shared_Remove_Name)
                  & " (Key : in " & Render_Type_Name (Key_Info)
                  & "; Result : out "
                  & Optional_Type_Name (Value_Info)
                  & ") is",
                  1);
               Append_Line (Buffer, "begin", 1);
               Append_Line
                 (Buffer,
                  Wrapper_Name & "." & Shared_Remove_Name
                  & " (Key, Result);",
                  2);
               Append_Line
                 (Buffer,
                  "end " & Public_Helper_Name (Shared_Remove_Name) & ";",
                  1);
               Append_Line (Buffer);
            else
               declare
                  Element_Info : constant GM.Type_Descriptor :=
                    Resolve_Type_Name (Unit, Document, FT.To_String (Base_Info.Component_Type));
               begin
                  Append_Line
                    (Buffer,
                     "procedure " & Public_Helper_Name (Shared_Append_Name)
                     & " (Value : in " & Render_Type_Name (Element_Info)
                     & ") is",
                     1);
                  Append_Line (Buffer, "begin", 1);
                  Append_Line
                    (Buffer,
                     Wrapper_Name & "." & Shared_Append_Name & " (Value);",
                     2);
                  Append_Line
                    (Buffer,
                     "end " & Public_Helper_Name (Shared_Append_Name) & ";",
                     1);
                  Append_Line (Buffer);

                  Append_Line
                    (Buffer,
                     "procedure " & Public_Helper_Name (Shared_Pop_Last_Name)
                     & " (Result : out "
                     & Optional_Type_Name (Element_Info)
                     & ") is",
                     1);
                  Append_Line (Buffer, "begin", 1);
                  Append_Line
                    (Buffer,
                     Wrapper_Name & "." & Shared_Pop_Last_Name
                     & " (Result);",
                     2);
                  Append_Line
                    (Buffer,
                     "end " & Public_Helper_Name (Shared_Pop_Last_Name) & ";",
                     1);
                  Append_Line (Buffer);
               end;
            end if;
         else
            for Field of Base_Info.Fields loop
               declare
                  Field_Info : constant GM.Type_Descriptor :=
                    Resolve_Type_Name (Unit, Document, FT.To_String (Field.Type_Name));
                  Field_Type_Name : constant String :=
                    Render_Type_Name_From_Text
                      (Unit,
                       Document,
                       FT.To_String (Field.Type_Name),
                       State);
               begin
                  Append_Line
                    (Buffer,
                     "function "
                     & Public_Helper_Name
                         (Shared_Field_Getter_Name (FT.To_String (Field.Name)))
                     & " return "
                     & Field_Type_Name
                     & " is",
                     1);
                  Append_Line (Buffer, "pragma SPARK_Mode (Off);", 2);
                  Append_Line (Buffer, "begin", 1);
                  Append_Line
                    (Buffer,
                     "return " & Wrapper_Name & "."
                     & Shared_Field_Getter_Name (FT.To_String (Field.Name))
                     & ";",
                     2);
                  Append_Line
                    (Buffer,
                     "end "
                     & Public_Helper_Name
                         (Shared_Field_Getter_Name (FT.To_String (Field.Name)))
                     & ";",
                     1);
                  Append_Line (Buffer);

                  Append_Line
                    (Buffer,
                     "procedure "
                     & Public_Helper_Name
                         (Shared_Field_Setter_Name (FT.To_String (Field.Name)))
                     & " (Value : in "
                     & Field_Type_Name
                     & ") is",
                     1);
                  Append_Line (Buffer, "begin", 1);
                  Append_Line
                    (Buffer,
                     Wrapper_Name & "."
                     & Shared_Field_Setter_Name (FT.To_String (Field.Name))
                     & " (Value);",
                     2);
                  Append_Line
                    (Buffer,
                     "end "
                     & Public_Helper_Name
                         (Shared_Field_Setter_Name (FT.To_String (Field.Name)))
                     & ";",
                     1);
                  Append_Line (Buffer);
                  if Is_Plain_String_Type (Unit, Document, Field_Info) then
                     State.Needs_Safe_String_RT := True;
                     Append_Line
                       (Buffer,
                        "procedure "
                        & Public_Helper_Name
                            (Shared_Field_Setter_Name (FT.To_String (Field.Name)))
                        & " (Value : in String) is",
                        1);
                     Append_Line (Buffer, "pragma SPARK_Mode (Off);", 2);
                     Append_Line (Buffer, "begin", 1);
                     Append_Line
                       (Buffer,
                        Wrapper_Name & "."
                        & Shared_Field_Setter_Name (FT.To_String (Field.Name))
                        & " (Safe_String_RT.From_Literal (Value));",
                        2);
                     Append_Line
                       (Buffer,
                        "end "
                        & Public_Helper_Name
                            (Shared_Field_Setter_Name (FT.To_String (Field.Name)))
                        & ";",
                        1);
                     Append_Line (Buffer);
                  end if;
               end;
            end loop;
            declare
               Empty_Path : FT.UString_Vectors.Vector;
            begin
               Append_Public_Nested_Setter_Bodies (Decl.Type_Info, Empty_Path);
            end;
         end if;
      end Append_Public_Helper_Bodies;
   begin
      if Is_Public_Shared then
         Append_Private_Wrapper_Declarations;
      end if;

      if Heap_Root then
         Append_Local_Warning_Suppression (Buffer, 1);
         Mark_Heap_Runtime_Dependencies
           (Unit,
            Document,
            Decl.Type_Info,
            State,
            Runtime_Dependency_Types);
         Render_Shared_Value_Helpers (Decl.Type_Info);
      end if;

      Append_Line (Buffer, "protected body " & Type_Name & " is", 1);
      Append_Line
        (Buffer,
         "function " & Shared_Get_All_Name & " return "
         & Root_Type & " is",
         2);
      if Heap_Root then
         Append_Line (Buffer, "pragma SPARK_Mode (Off);", 3);
      end if;
      if Heap_Root then
         Append_Line
           (Buffer,
            "Result : " & Root_Type & " := "
            & Default_Value_Expr (Unit, Document, Decl.Type_Info)
            & ";",
            2);
      end if;
      Append_Line (Buffer, "begin", 2);
      if Heap_Root then
         if Is_Container_Root then
            Append_Copy_Value ("Result", "State_Value", Decl.Type_Info, 3);
         else
            Append_Line
              (Buffer,
               Shared_Copy_Helper_Name (Decl.Type_Info) & " (Result, State_Value);",
               3);
         end if;
         Append_Line (Buffer, "return Result;", 3);
      else
         Append_Line (Buffer, "return State_Value;", 3);
      end if;
      Append_Line (Buffer, "end " & Shared_Get_All_Name & ";", 2);
      Append_Line (Buffer);
      Append_Line
        (Buffer,
         "procedure " & Shared_Set_All_Name & " (Value : in "
         & Root_Type & ") is",
         2);
      if Heap_Root then
         Append_Line (Buffer, "pragma SPARK_Mode (Off);", 3);
      end if;
      Append_Line (Buffer, "begin", 2);
      if Heap_Root then
         Append_Free_Value ("State_Value", Decl.Type_Info, 3);
         if Is_Container_Root then
            Append_Copy_Value ("State_Value", "Value", Decl.Type_Info, 3);
         else
            Append_Line
              (Buffer,
               Shared_Copy_Helper_Name (Decl.Type_Info) & " (State_Value, Value);",
               3);
         end if;
      else
         Append_Line (Buffer, "State_Value := Value;", 3);
      end if;
      Append_Line (Buffer, "end " & Shared_Set_All_Name & ";", 2);
      Append_Line (Buffer);
      if Is_Container_Root then
         declare
            Runtime_Name : constant String := Array_Runtime_Instance_Name (Base_Info);
            Element_Free_Name : constant String :=
              Array_Runtime_Free_Element_Name (Base_Info);
            Element_Info : constant GM.Type_Descriptor :=
              Resolve_Type_Name (Unit, Document, FT.To_String (Base_Info.Component_Type));
            Key_Info     : GM.Type_Descriptor := (others => <>);
            Value_Info   : GM.Type_Descriptor := (others => <>);
         begin
            Append_Line
              (Buffer,
               "function " & Shared_Get_Length_Name & " return "
               & Integer_Type_Name & " is",
               2);
            Append_Line (Buffer, "pragma SPARK_Mode (Off);", 2);
            Append_Line (Buffer, "begin", 2);
            Append_Line
              (Buffer,
               "return " & Integer_Type_Name & " (" & Runtime_Name & ".Length (State_Value));",
               3);
            Append_Line (Buffer, "end " & Shared_Get_Length_Name & ";", 2);
            Append_Line (Buffer);

            if Try_Map_Key_Value_Types (Unit, Document, Decl.Type_Info, Key_Info, Value_Info) then
               declare
                  Entry_Type_Name     : constant String := Render_Type_Name (Element_Info);
                  Key_Type_Name       : constant String := Render_Type_Name (Key_Info);
                  Value_Type_Name     : constant String := Render_Type_Name (Value_Info);
                  Optional_Value_Name : constant String :=
                    Optional_Type_Name (Value_Info);

                  function Key_Equality_Image
                    (Left_Image  : String;
                     Right_Image : String) return String
                  is
                     Base_Key : constant GM.Type_Descriptor :=
                       Base_Type (Unit, Document, Key_Info);
                     Key_Kind : constant String :=
                       FT.Lowercase (FT.To_String (Base_Key.Kind));
                     Key_Name : constant String :=
                       FT.Lowercase (FT.To_String (Base_Key.Name));
                  begin
                     if Is_Plain_String_Type (Unit, Document, Key_Info) then
                        return
                          "Safe_String_RT.To_String ("
                          & Left_Image
                          & ") = Safe_String_RT.To_String ("
                          & Right_Image
                          & ")";
                     elsif Is_Bounded_String_Type (Key_Info)
                       or else Key_Kind = "string"
                       or else Key_Name = "string"
                     then
                        return Left_Image & " = " & Right_Image;
                     end if;

                     return Left_Image & " = " & Right_Image;
                  end Key_Equality_Image;

                  procedure Ignore_Map_Extra_Decls (Depth : Natural) is
                     pragma Unreferenced (Depth);
                  begin
                     null;
                  end Ignore_Map_Extra_Decls;

                  generic
                     with procedure Append_Extra_Decls (Depth : Natural);
                     with procedure Append_On_Match (Depth : Natural);
                  procedure Append_Map_Search_Loop;

                  procedure Append_Map_Search_Loop is
                  begin
                     Append_Line (Buffer, "if Length_Value > 0 then", 3);
                     Append_Line
                       (Buffer,
                        "for Index in Positive range 1 .. Positive (Length_Value) loop",
                        4);
                     Append_Line (Buffer, "declare", 5);
                     Append_Line
                       (Buffer,
                        "Current_Entry : " & Entry_Type_Name & " := "
                        & Runtime_Name & ".Element (State_Value, Index);",
                        6);
                     Append_Extra_Decls (6);
                     Append_Line (Buffer, "begin", 5);
                     Append_Line
                       (Buffer,
                        "if "
                        & Key_Equality_Image
                          ("Current_Entry." & Tuple_Field_Name (1),
                           "Key")
                        & " then",
                        6);
                     Append_On_Match (7);
                     Append_Line (Buffer, "end if;", 6);
                     Append_Line
                       (Buffer,
                        Element_Free_Name & " (Current_Entry);",
                        6);
                     Append_Line (Buffer, "end;", 5);
                     Append_Line (Buffer, "end loop;", 4);
                     Append_Line (Buffer, "end if;", 3);
                  end Append_Map_Search_Loop;

                  procedure Append_Contains_Match (Depth : Natural) is
                  begin
                     Append_Line
                       (Buffer,
                        Element_Free_Name & " (Current_Entry);",
                        Depth);
                     Append_Line (Buffer, "return True;", Depth);
                  end Append_Contains_Match;

                  procedure Append_Get_Match (Depth : Natural) is
                  begin
                     if Has_Heap_Value_Type (Unit, Document, Value_Info) then
                        Append_Line (Buffer, "Result.present := True;", Depth);
                        Append_Copy_Value
                          ("Result.value",
                           "Current_Entry." & Tuple_Field_Name (2),
                           Value_Info,
                           Depth);
                     else
                        Append_Line
                          (Buffer,
                           "Result := (present => True, value => Current_Entry." & Tuple_Field_Name (2) & ");",
                           Depth);
                     end if;
                     Append_Line
                       (Buffer,
                        Element_Free_Name & " (Current_Entry);",
                        Depth);
                     Append_Line (Buffer, "return Result;", Depth);
                  end Append_Get_Match;

                  procedure Append_Set_Extra_Decls (Depth : Natural) is
                  begin
                     Append_Line
                       (Buffer,
                        "New_Entry : " & Entry_Type_Name & " := (others => <>);",
                        Depth);
                  end Append_Set_Extra_Decls;

                  procedure Append_Set_Match (Depth : Natural) is
                  begin
                     if Has_Heap_Value_Type (Unit, Document, Key_Info) then
                        Append_Copy_Value
                          ("New_Entry." & Tuple_Field_Name (1),
                           "Key",
                           Key_Info,
                           Depth);
                     else
                        Append_Line
                          (Buffer,
                           "New_Entry." & Tuple_Field_Name (1) & " := Key;",
                           Depth);
                     end if;
                     if Has_Heap_Value_Type (Unit, Document, Value_Info) then
                        Append_Copy_Value
                          ("New_Entry." & Tuple_Field_Name (2),
                           "Value",
                           Value_Info,
                           Depth);
                     else
                        Append_Line
                          (Buffer,
                           "New_Entry." & Tuple_Field_Name (2) & " := Value;",
                           Depth);
                     end if;
                     Append_Line
                       (Buffer,
                        Runtime_Name & ".Replace_Element (State_Value, Index, New_Entry);",
                        Depth);
                     Append_Line
                       (Buffer,
                        Element_Free_Name & " (New_Entry);",
                        Depth);
                     Append_Line
                       (Buffer,
                        Element_Free_Name & " (Current_Entry);",
                        Depth);
                     Append_Line (Buffer, "return;", Depth);
                  end Append_Set_Match;

                  procedure Append_Remove_Match (Depth : Natural) is
                  begin
                     if Has_Heap_Value_Type (Unit, Document, Value_Info) then
                        Append_Line (Buffer, "Result.present := True;", Depth);
                        Append_Copy_Value
                          ("Result.value",
                           "Current_Entry." & Tuple_Field_Name (2),
                           Value_Info,
                           Depth);
                     else
                        Append_Line
                          (Buffer,
                           "Result := (present => True, value => Current_Entry." & Tuple_Field_Name (2) & ");",
                           Depth);
                     end if;
                     Append_Line
                       (Buffer,
                        Element_Free_Name & " (Current_Entry);",
                        Depth);
                     Append_Line
                       (Buffer,
                        "if Index < Positive (Length_Value) then",
                        Depth);
                     Append_Line (Buffer, "declare", Depth + 1);
                     Append_Line
                       (Buffer,
                        "Replacement_Entry : " & Entry_Type_Name & " := "
                        & Runtime_Name & ".Element (State_Value, Positive (Length_Value));",
                        Depth + 2);
                     Append_Line (Buffer, "begin", Depth + 1);
                     Append_Line
                       (Buffer,
                        Runtime_Name & ".Replace_Element (State_Value, Index, Replacement_Entry);",
                        Depth + 2);
                     Append_Line
                       (Buffer,
                        Element_Free_Name & " (Replacement_Entry);",
                        Depth + 2);
                     Append_Line (Buffer, "end;", Depth + 1);
                     Append_Line (Buffer, "end if;", Depth);
                     Append_Line (Buffer, "declare", Depth);
                     Append_Line
                       (Buffer,
                        "Updated : constant " & Root_Type & " := "
                        & "(if Length_Value = 1 then " & Runtime_Name & ".Empty else "
                        & Runtime_Name & ".Slice (State_Value, 1, Length_Value - 1));",
                        Depth + 1);
                     Append_Line (Buffer, "begin", Depth);
                     Append_Free_Value ("State_Value", Decl.Type_Info, Depth + 1);
                     Append_Line (Buffer, "State_Value := Updated;", Depth + 1);
                     Append_Line (Buffer, "end;", Depth);
                     Append_Line (Buffer, "return;", Depth);
                  end Append_Remove_Match;

                  procedure Append_Contains_Search_Loop is new Append_Map_Search_Loop
                    (Ignore_Map_Extra_Decls, Append_Contains_Match);
                  procedure Append_Get_Search_Loop is new Append_Map_Search_Loop
                    (Ignore_Map_Extra_Decls, Append_Get_Match);
                  procedure Append_Set_Search_Loop is new Append_Map_Search_Loop
                    (Append_Set_Extra_Decls, Append_Set_Match);
                  procedure Append_Remove_Search_Loop is new Append_Map_Search_Loop
                    (Ignore_Map_Extra_Decls, Append_Remove_Match);
               begin
                  Append_Line
                    (Buffer,
                     "function " & Shared_Contains_Name & " (Key : in "
                     & Key_Type_Name & ") return boolean is",
                     2);
                  if Heap_Root then
                     Append_Line (Buffer, "pragma SPARK_Mode (Off);", 3);
                  end if;
                  Append_Line
                    (Buffer,
                     "Length_Value : constant Natural := " & Runtime_Name & ".Length (State_Value);",
                     2);
                  Append_Line (Buffer, "begin", 2);
                  Append_Contains_Search_Loop;
                  Append_Line (Buffer, "return False;", 3);
                  Append_Line (Buffer, "end " & Shared_Contains_Name & ";", 2);
                  Append_Line (Buffer);

                  Append_Line
                    (Buffer,
                     "function " & Shared_Get_Name & " (Key : in "
                     & Key_Type_Name & ") return " & Optional_Value_Name & " is",
                     2);
                  if Heap_Root then
                     Append_Line (Buffer, "pragma SPARK_Mode (Off);", 3);
                  end if;
                  Append_Line
                    (Buffer,
                     "Length_Value : constant Natural := " & Runtime_Name & ".Length (State_Value);",
                     2);
                  Append_Line
                    (Buffer,
                     "Result : " & Optional_Value_Name & " := "
                     & Optional_Default_Expr (Value_Info) & ";",
                     2);
                  Append_Line (Buffer, "begin", 2);
                  Append_Get_Search_Loop;
                  Append_Line (Buffer, "return Result;", 3);
                  Append_Line (Buffer, "end " & Shared_Get_Name & ";", 2);
                  Append_Line (Buffer);

                  Append_Line
                    (Buffer,
                     "procedure " & Shared_Set_Name & " (Key : in "
                     & Key_Type_Name & "; Value : in " & Value_Type_Name & ") is",
                     2);
                  if Heap_Root then
                     Append_Line (Buffer, "pragma SPARK_Mode (Off);", 3);
                  end if;
                  Append_Line
                    (Buffer,
                     "Length_Value : constant Natural := " & Runtime_Name & ".Length (State_Value);",
                     2);
                  Append_Line (Buffer, "begin", 2);
                  Append_Set_Search_Loop;
                  Append_Line (Buffer, "declare", 3);
                  Append_Line
                    (Buffer,
                     "New_Entry : " & Entry_Type_Name & " := (others => <>);",
                     4);
                  Append_Line (Buffer, "begin", 3);
                  if Has_Heap_Value_Type (Unit, Document, Key_Info) then
                     Append_Copy_Value
                       ("New_Entry." & Tuple_Field_Name (1),
                        "Key",
                        Key_Info,
                        4);
                  else
                     Append_Line
                       (Buffer,
                        "New_Entry." & Tuple_Field_Name (1) & " := Key;",
                        4);
                  end if;
                  if Has_Heap_Value_Type (Unit, Document, Value_Info) then
                     Append_Copy_Value
                       ("New_Entry." & Tuple_Field_Name (2),
                        "Value",
                        Value_Info,
                        4);
                  else
                     Append_Line
                       (Buffer,
                        "New_Entry." & Tuple_Field_Name (2) & " := Value;",
                        4);
                  end if;
                  Append_Line (Buffer, "declare", 4);
                  Append_Line
                    (Buffer,
                     "Tail : " & Root_Type & " := "
                     & Runtime_Name & ".From_Array ((1 => New_Entry));",
                     5);
                  Append_Line
                    (Buffer,
                     "Updated : constant " & Root_Type & " := "
                     & Runtime_Name & ".Concat (State_Value, Tail);",
                     5);
                  Append_Line (Buffer, "begin", 4);
                  Append_Line
                    (Buffer,
                     Element_Free_Name & " (New_Entry);",
                     5);
                  Append_Free_Value ("State_Value", Decl.Type_Info, 5);
                  Append_Free_Value ("Tail", Decl.Type_Info, 5);
                  Append_Line (Buffer, "State_Value := Updated;", 5);
                  Append_Line (Buffer, "end;", 4);
                  Append_Line (Buffer, "end;", 3);
                  Append_Line (Buffer, "end " & Shared_Set_Name & ";", 2);
                  Append_Line (Buffer);

                  Append_Line
                    (Buffer,
                     "procedure " & Shared_Remove_Name & " (Key : in "
                     & Key_Type_Name & "; Result : out "
                     & Optional_Value_Name & ") is",
                     2);
                  if Heap_Root then
                     Append_Line (Buffer, "pragma SPARK_Mode (Off);", 3);
                  end if;
                  Append_Line
                    (Buffer,
                     "Length_Value : constant Natural := " & Runtime_Name & ".Length (State_Value);",
                     2);
                  Append_Line (Buffer, "begin", 2);
                  Append_Line
                    (Buffer,
                     "Result := " & Optional_Default_Expr (Value_Info) & ";",
                     3);
                  Append_Remove_Search_Loop;
                  Append_Line (Buffer, "end " & Shared_Remove_Name & ";", 2);
                  Append_Line (Buffer);
               end;
            else
               declare
                  Element_Type_Name     : constant String := Render_Type_Name (Element_Info);
                  Optional_Element_Name : constant String :=
                    Optional_Type_Name (Element_Info);
               begin
                  Append_Line
                    (Buffer,
                     "procedure " & Shared_Append_Name & " (Value : in "
                     & Element_Type_Name & ") is",
                     2);
                  if Heap_Root then
                     Append_Line (Buffer, "pragma SPARK_Mode (Off);", 3);
                  end if;
                  Append_Line
                    (Buffer,
                     "Tail : " & Root_Type & " := "
                     & Runtime_Name & ".From_Array ((1 => Value));",
                     2);
                  Append_Line
                    (Buffer,
                     "Updated : constant " & Root_Type & " := "
                     & Runtime_Name & ".Concat (State_Value, Tail);",
                     2);
                  Append_Line (Buffer, "begin", 2);
                  Append_Free_Value ("State_Value", Decl.Type_Info, 3);
                  Append_Free_Value ("Tail", Decl.Type_Info, 3);
                  Append_Line (Buffer, "State_Value := Updated;", 3);
                  Append_Line (Buffer, "end " & Shared_Append_Name & ";", 2);
                  Append_Line (Buffer);

                  Append_Line
                    (Buffer,
                     "procedure " & Shared_Pop_Last_Name & " (Result : out "
                     & Optional_Element_Name & ") is",
                     2);
                  if Heap_Root then
                     Append_Line (Buffer, "pragma SPARK_Mode (Off);", 3);
                  end if;
                  Append_Line
                    (Buffer,
                     "Length_Value : constant Natural := "
                     & Runtime_Name & ".Length (State_Value);",
                     2);
                  Append_Line (Buffer, "begin", 2);
                  Append_Line
                    (Buffer,
                     "Result := " & Optional_Default_Expr (Element_Info) & ";",
                     3);
                  Append_Line (Buffer, "if Length_Value = 0 then", 3);
                  Append_Line (Buffer, "return;", 4);
                  Append_Line (Buffer, "end if;", 3);
                  Append_Line (Buffer, "declare", 3);
                  Append_Line
                    (Buffer,
                     "Last_Value : " & Element_Type_Name & " := "
                     & Runtime_Name & ".Element (State_Value, Positive (Length_Value));",
                     4);
                  Append_Line (Buffer, "begin", 3);
                  if Has_Heap_Value_Type (Unit, Document, Element_Info) then
                     Append_Line (Buffer, "Result.present := True;", 4);
                     Append_Copy_Value ("Result.value", "Last_Value", Element_Info, 4);
                  else
                     Append_Line
                       (Buffer,
                        "Result := (present => True, value => Last_Value);",
                        4);
                  end if;
                  Append_Line
                    (Buffer,
                     Element_Free_Name & " (Last_Value);",
                     4);
                  Append_Line (Buffer, "end;", 3);
                  Append_Line (Buffer, "declare", 3);
                  Append_Line
                    (Buffer,
                     "Updated : constant " & Root_Type & " := "
                     & "(if Length_Value = 1 then " & Runtime_Name & ".Empty else "
                     & Runtime_Name & ".Slice (State_Value, 1, Length_Value - 1));",
                     4);
                  Append_Line (Buffer, "begin", 3);
                  Append_Free_Value ("State_Value", Decl.Type_Info, 4);
                  Append_Line (Buffer, "State_Value := Updated;", 4);
                  Append_Line (Buffer, "end;", 3);
                  Append_Line (Buffer, "end " & Shared_Pop_Last_Name & ";", 2);
                  Append_Line (Buffer);
               end;
            end if;
         end;
      else
         for Field of Base_Info.Fields loop
            declare
               Field_Info : constant GM.Type_Descriptor :=
                 Resolve_Type_Name (Unit, Document, FT.To_String (Field.Type_Name));
               Field_Type_Name : constant String :=
                 Render_Type_Name_From_Text
                   (Unit,
                    Document,
                    FT.To_String (Field.Type_Name),
                    State);
               Getter_Name : constant String := Shared_Field_Getter_Name (FT.To_String (Field.Name));
               Setter_Name : constant String := Shared_Field_Setter_Name (FT.To_String (Field.Name));
               Field_Image : constant String := FT.To_String (Field.Name);
            begin
               Append_Line
                 (Buffer,
                  "function " & Getter_Name & " return "
                  & Field_Type_Name & " is",
                  2);
               if Heap_Root then
                  Append_Line (Buffer, "pragma SPARK_Mode (Off);", 3);
               end if;
               if Has_Heap_Value_Type (Unit, Document, Field_Info) then
                  Append_Line
                    (Buffer,
                     "Result : " & Field_Type_Name & " := "
                     & Default_Value_Expr (Unit, Document, Field_Info)
                     & ";",
                     2);
               end if;
               Append_Line (Buffer, "begin", 2);
               if Has_Heap_Value_Type (Unit, Document, Field_Info) then
                  Append_Copy_Value
                    ("Result",
                     "State_Value." & Field_Image,
                     Field_Info,
                     3);
                  Append_Line (Buffer, "return Result;", 3);
               else
                  Append_Line (Buffer, "return State_Value." & Field_Image & ";", 3);
               end if;
               Append_Line (Buffer, "end " & Getter_Name & ";", 2);
               Append_Line (Buffer);
               Append_Line
                 (Buffer,
                  "procedure " & Setter_Name & " (Value : in "
                  & Field_Type_Name & ") is",
                  2);
               if Heap_Root then
                  Append_Line (Buffer, "pragma SPARK_Mode (Off);", 3);
               end if;
               Append_Line (Buffer, "begin", 2);
               if Has_Heap_Value_Type (Unit, Document, Field_Info) then
                  Append_Free_Value ("State_Value." & Field_Image, Field_Info, 3);
                  Append_Copy_Value
                    ("State_Value." & Field_Image,
                     "Value",
                     Field_Info,
                     3);
               else
                  Append_Line (Buffer, "State_Value." & Field_Image & " := Value;", 3);
               end if;
               Append_Line (Buffer, "end " & Setter_Name & ";", 2);
               Append_Line (Buffer);
               if Is_Plain_String_Type (Unit, Document, Field_Info) then
                  State.Needs_Safe_String_RT := True;
                  Append_Line
                    (Buffer,
                     "procedure " & Setter_Name & " (Value : in String) is",
                     2);
                  Append_Line (Buffer, "pragma SPARK_Mode (Off);", 3);
                  Append_Line (Buffer, "begin", 2);
                  Append_Line
                    (Buffer,
                     Setter_Name & " (Safe_String_RT.From_Literal (Value));",
                     3);
                  Append_Line (Buffer, "end " & Setter_Name & ";", 2);
                  Append_Line (Buffer);
               end if;
            end;
         end loop;
         declare
            Empty_Path : FT.UString_Vectors.Vector;
         begin
            Append_Nested_Setter_Bodies (Decl.Type_Info, Empty_Path);
         end;
      end if;
      Append_Line
        (Buffer,
         "procedure Initialize (Value : in " & Root_Type & ") is",
         2);
      if Heap_Root then
         Append_Line (Buffer, "pragma SPARK_Mode (Off);", 3);
      end if;
      Append_Line (Buffer, "begin", 2);
      if Heap_Root then
         Append_Free_Value ("State_Value", Decl.Type_Info, 3);
         if Is_Container_Root then
            Append_Copy_Value ("State_Value", "Value", Decl.Type_Info, 3);
         else
            Append_Line
              (Buffer,
               Shared_Copy_Helper_Name (Decl.Type_Info) & " (State_Value, Value);",
               3);
         end if;
      else
         Append_Line (Buffer, "State_Value := Value;", 3);
      end if;
      Append_Line (Buffer, "end Initialize;", 2);
      Append_Line (Buffer, "end " & Type_Name & ";", 1);
      if Heap_Root then
         Append_Local_Warning_Restore (Buffer, 1);
      end if;
      Append_Line (Buffer);
      if Is_Public_Shared then
         Append_Public_Helper_Bodies;
      end if;
   end Render_Shared_Object_Body;

   procedure Raise_Internal (Message : String) is
   begin
      raise AI.Emitter_Internal with Message;
   end Raise_Internal;

   procedure Raise_Unsupported
     (State   : in out Emit_State;
      Span    : FT.Source_Span;
      Message : String) is
   begin
      State.Unsupported_Span := Span;
      State.Unsupported_Message := FT.To_UString (Message);
      raise AI.Emitter_Unsupported;
   end Raise_Unsupported;

   function Has_Text (Item : FT.UString) return Boolean renames AI.Has_Text;
   function Trim_Image (Value : Long_Long_Integer) return String renames AI.Trim_Image;
   function Trim_Wide_Image (Value : CM.Wide_Integer) return String renames AI.Trim_Wide_Image;

   function Is_Print_Call (Expr : CM.Expr_Access) return Boolean is
   begin
      return
        Expr /= null
        and then Expr.Kind = CM.Expr_Call
        and then FT.Lowercase (CM.Flatten_Name (Expr.Callee)) = "print";
   end Is_Print_Call;

   function Indentation (Depth : Natural) return String renames AI.Indentation;
   procedure Append_Line
     (Buffer : in out SU.Unbounded_String;
      Text   : String := "";
      Depth  : Natural := 0) renames AI.Append_Line;
   function Join_Names (Items : FT.UString_Vectors.Vector) return String renames AI.Join_Names;
   function Contains_Name
     (Items : FT.UString_Vectors.Vector;
      Name  : String) return Boolean renames AI.Contains_Name;
   procedure Add_Wide_Name
     (State : in out Emit_State;
      Name  : String) renames AI.Add_Wide_Name;
   function Is_Wide_Name
     (State : Emit_State;
      Name  : String) return Boolean renames AI.Is_Wide_Name;
   function Names_Use_Wide_Storage
     (State : Emit_State;
      Names : FT.UString_Vectors.Vector) return Boolean renames AI.Names_Use_Wide_Storage;
   procedure Restore_Wide_Names
     (State           : in out Emit_State;
      Previous_Length : Ada.Containers.Count_Type) renames AI.Restore_Wide_Names;
   procedure Bind_Static_Length
     (State  : in out Emit_State;
      Name   : String;
      Length : Natural) renames AI.Bind_Static_Length;
   function Try_Static_Length
     (State  : Emit_State;
      Name   : String;
      Length : out Natural) return Boolean renames AI.Try_Static_Length;
   procedure Restore_Static_Length_Bindings
     (State           : in out Emit_State;
      Previous_Length : Ada.Containers.Count_Type) renames AI.Restore_Static_Length_Bindings;
   procedure Invalidate_Static_Length
     (State : in out Emit_State;
      Name  : String) renames AI.Invalidate_Static_Length;
   procedure Bind_Static_Integer
     (State : in out Emit_State;
      Name  : String;
      Value : Long_Long_Integer) renames AI.Bind_Static_Integer;
   procedure Invalidate_Static_Integer
     (State : in out Emit_State;
      Name  : String) renames AI.Invalidate_Static_Integer;
   procedure Bind_Static_String
     (State : in out Emit_State;
      Name  : String;
      Image : String) renames AI.Bind_Static_String;
   function Has_Static_Integer_Tracking
     (State : Emit_State;
      Name  : String) return Boolean renames AI.Has_Static_Integer_Tracking;
   function Try_Static_Integer_Binding
     (State : Emit_State;
      Name  : String;
      Value : out Long_Long_Integer) return Boolean renames AI.Try_Static_Integer_Binding;
   procedure Restore_Static_Integer_Bindings
     (State           : in out Emit_State;
      Previous_Length : Ada.Containers.Count_Type) renames AI.Restore_Static_Integer_Bindings;
   procedure Push_Type_Binding_Frame (State : in out Emit_State) renames AI.Push_Type_Binding_Frame;
   procedure Pop_Type_Binding_Frame (State : in out Emit_State) renames AI.Pop_Type_Binding_Frame;
   procedure Add_Type_Binding
     (State     : in out Emit_State;
      Name      : String;
      Type_Info : GM.Type_Descriptor) renames AI.Add_Type_Binding;
   procedure Register_Type_Bindings
     (State        : in out Emit_State;
      Declarations : CM.Resolved_Object_Decl_Vectors.Vector) renames AI.Register_Type_Bindings;
   procedure Register_Type_Bindings
     (State        : in out Emit_State;
      Declarations : CM.Object_Decl_Vectors.Vector) renames AI.Register_Type_Bindings;
   procedure Register_Param_Type_Bindings
     (State  : in out Emit_State;
      Params : CM.Symbol_Vectors.Vector) renames AI.Register_Param_Type_Bindings;
   function Lookup_Bound_Type
     (State     : Emit_State;
      Name      : String;
      Type_Info : out GM.Type_Descriptor) return Boolean renames AI.Lookup_Bound_Type;
   procedure Push_Cleanup_Frame (State : in out Emit_State) renames AI.Push_Cleanup_Frame;
   procedure Pop_Cleanup_Frame (State : in out Emit_State) renames AI.Pop_Cleanup_Frame;
   procedure Add_Cleanup_Item
     (State     : in out Emit_State;
      Name      : String;
      Type_Name : String;
      Free_Proc : String := "";
      Is_Constant : Boolean := False;
      Always_Terminates_Suppression_OK : Boolean := False;
      Action    : Cleanup_Action := AI.Cleanup_Deallocate) renames AI.Add_Cleanup_Item;
   procedure Register_Cleanup_Items
     (State        : in out Emit_State;
      Declarations : CM.Resolved_Object_Decl_Vectors.Vector) renames AI.Register_Cleanup_Items;
   procedure Register_Cleanup_Items
     (State        : in out Emit_State;
      Declarations : CM.Object_Decl_Vectors.Vector) renames AI.Register_Cleanup_Items;
   procedure Render_Cleanup_Item
     (Buffer : in out SU.Unbounded_String;
      Item   : Cleanup_Item;
      Depth  : Natural) renames AI.Render_Cleanup_Item;
   procedure Render_Active_Cleanup
     (Buffer : in out SU.Unbounded_String;
      State  : Emit_State;
      Depth  : Natural;
      Skip_Name : String := "") renames AI.Render_Active_Cleanup;
   procedure Render_Current_Cleanup_Frame
     (Buffer : in out SU.Unbounded_String;
      State  : Emit_State;
      Depth  : Natural) renames AI.Render_Current_Cleanup_Frame;
   function Has_Active_Cleanup_Items (State : Emit_State) return Boolean renames AI.Has_Active_Cleanup_Items;

   function Starts_With (Text : String; Prefix : String) return Boolean is
   begin
      return Text'Length >= Prefix'Length
        and then Text (Text'First .. Text'First + Prefix'Length - 1) = Prefix;
   end Starts_With;

   function Binary_Width_From_Name (Name : String) return Natural is
   begin
      if Name = "__binary_8" then
         return 8;
      elsif Name = "__binary_16" then
         return 16;
      elsif Name = "__binary_32" then
         return 32;
      elsif Name = "__binary_64" then
         return 64;
      end if;
      return 0;
   end Binary_Width_From_Name;

   function Binary_Ada_Name (Bit_Width : Positive) return String is
   begin
      return
        "Interfaces.Unsigned_"
        & Ada.Strings.Fixed.Trim (Positive'Image (Bit_Width), Ada.Strings.Both);
   end Binary_Ada_Name;

   function Ada_Safe_Name (Name : String) return String is
      Bit_Width : constant Natural := Binary_Width_From_Name (Name);
      function Collapse_Underscores (Text : String) return String is
         Result          : SU.Unbounded_String;
         Last_Underscore : Boolean := False;
      begin
         for Ch of Text loop
            if Ch = '_' then
               if not Last_Underscore then
                  Result := Result & "_";
               end if;
               Last_Underscore := True;
            else
               Result := Result & Ch;
               Last_Underscore := False;
            end if;
         end loop;
         return SU.To_String (Result);
      end Collapse_Underscores;
   begin
      if Bit_Width /= 0 then
         return Binary_Ada_Name (Positive (Bit_Width));
      elsif Name = "integer" then
         return "Long_Long_Integer";
      elsif Name = "boolean" then
         return "Boolean";
      elsif Name = "character" then
         return "Character";
      elsif Name = "string" then
         return "String";
      elsif Name = "float" then
         return "Float";
      elsif Name = "long_float" then
         return "Long_Float";
      elsif Name = "duration" then
         return "Duration";
      elsif Starts_With (Name, "__") then
         return
           "Safe_"
           & Collapse_Underscores (Name (Name'First + 2 .. Name'Last));
      elsif Name'Length > 0 and then Name (Name'First) = '_' then
         return "Safe" & Name;
      end if;
      return Name;
   end Ada_Safe_Name;

   function Ada_Qualified_Name (Name : String) return String is
      Dot : constant Natural := Ada.Strings.Fixed.Index (Name, ".");
   begin
      if Dot = 0 then
         return Ada_Safe_Name (Name);
      elsif Dot = Name'First then
         return Ada_Qualified_Name (Name (Dot + 1 .. Name'Last));
      elsif Dot = Name'Last then
         return Ada_Qualified_Name (Name (Name'First .. Dot - 1));
      end if;

      return
        Ada_Qualified_Name (Name (Name'First .. Dot - 1))
        & "."
        & Ada_Qualified_Name (Name (Dot + 1 .. Name'Last));
   end Ada_Qualified_Name;

   function Render_Enum_Literal_Name
     (Literal_Name   : String;
      Enum_Type_Name : String) return String
   is
      Literal_Dot : constant Natural := Ada.Strings.Fixed.Index (Literal_Name, ".");
      Type_Dot    : constant Natural :=
        Ada.Strings.Fixed.Index
          (Enum_Type_Name,
           ".",
           Going => Ada.Strings.Backward);
   begin
      if Literal_Dot > 0 then
         return Ada_Qualified_Name (Literal_Name);
      elsif Type_Dot > 0 then
         return
           Ada_Qualified_Name (Enum_Type_Name (Enum_Type_Name'First .. Type_Dot - 1))
           & "."
           & Ada_Safe_Name (Literal_Name);
      end if;

      return Ada_Safe_Name (Literal_Name);
   end Render_Enum_Literal_Name;

   function Normalize_Aspect_Name
     (Subprogram_Name : String;
      Raw_Name        : String) return String is
      Name_Image : constant String :=
        (if Raw_Name = "return"
         then Subprogram_Name & "'Result"
         elsif Starts_With (Raw_Name, "param:")
         then Raw_Name (Raw_Name'First + 6 .. Raw_Name'Last)
         elsif Starts_With (Raw_Name, "global:")
         then Raw_Name (Raw_Name'First + 7 .. Raw_Name'Last)
         else Raw_Name);
      Dot_Pos : Natural := 0;
   begin
      for Index in reverse Name_Image'Range loop
         if Name_Image (Index) = '.' then
            Dot_Pos := Index;
            exit;
         end if;
      end loop;

      if Dot_Pos > 0
        and then Dot_Pos < Name_Image'Last
        and then Is_Attribute_Selector (Name_Image (Dot_Pos + 1 .. Name_Image'Last))
      then
         return
           Name_Image (Name_Image'First .. Dot_Pos - 1)
           & "'"
           & Name_Image (Dot_Pos + 1 .. Name_Image'Last);
      end if;
      return Name_Image;
   end Normalize_Aspect_Name;

   function Is_Attribute_Selector (Name : String) return Boolean is
   begin
      return
        Name = "access"
        or else Name = "address"
        or else Name = "adjacent"
        or else Name = "aft"
        or else Name = "alignment"
        or else Name = "base"
        or else Name = "bit_order"
        or else Name = "ceiling"
        or else Name = "component_size"
        or else Name = "compose"
        or else Name = "constrained"
        or else Name = "copy_sign"
        or else Name = "definite"
        or else Name = "delta"
        or else Name = "denorm"
        or else Name = "digits"
        or else Name = "enum_rep"
        or else Name = "enum_val"
        or else Name = "exponent"
        or else Name = "first"
        or else Name = "first_valid"
        or else Name = "floor"
        or else Name = "fore"
        or else Name = "fraction"
        or else Name = "image"
        or else Name = "last"
        or else Name = "last_valid"
        or else Name = "leading_part"
        or else Name = "length"
        or else Name = "machine"
        or else Name = "machine_emax"
        or else Name = "machine_emin"
        or else Name = "machine_mantissa"
        or else Name = "machine_overflows"
        or else Name = "machine_radix"
        or else Name = "machine_rounds"
        or else Name = "max"
        or else Name = "max_alignment_for_allocation"
        or else Name = "max_size_in_storage_elements"
        or else Name = "min"
        or else Name = "mod"
        or else Name = "model"
        or else Name = "model_emin"
        or else Name = "model_epsilon"
        or else Name = "model_mantissa"
        or else Name = "model_small"
        or else Name = "modulus"
        or else Name = "object_size"
        or else Name = "overlaps_storage"
        or else Name = "pos"
        or else Name = "pred"
        or else Name = "range"
        or else Name = "remainder"
        or else Name = "round"
        or else Name = "rounding"
        or else Name = "safe_first"
        or else Name = "safe_last"
        or else Name = "scale"
        or else Name = "scaling"
        or else Name = "size"
        or else Name = "small"
        or else Name = "storage_size"
        or else Name = "succ"
        or else Name = "truncation"
        or else Name = "unbiased_rounding"
        or else Name = "val"
        or else Name = "valid"
        or else Name = "value"
        or else Name = "wide_image"
        or else Name = "wide_value"
        or else Name = "wide_wide_image"
        or else Name = "wide_wide_value"
        or else Name = "wide_wide_width"
        or else Name = "wide_width"
        or else Name = "width";
   end Is_Attribute_Selector;

   function Root_Name (Expr : CM.Expr_Access) return String is
   begin
      if Expr = null then
         return "";
      end if;

      case Expr.Kind is
         when CM.Expr_Ident =>
            return FT.To_String (Expr.Name);
         when CM.Expr_Select | CM.Expr_Resolved_Index =>
            return Root_Name (Expr.Prefix);
         when others =>
            return "";
      end case;
   end Root_Name;

   function Expr_Uses_Name
     (Expr : CM.Expr_Access;
      Name : String) return Boolean
   is
   begin
      if Expr = null or else Name'Length = 0 then
         return False;
      end if;

      case Expr.Kind is
         when CM.Expr_Ident =>
            return FT.To_String (Expr.Name) = Name;
         when CM.Expr_Select =>
            return Expr_Uses_Name (Expr.Prefix, Name);
         when CM.Expr_Resolved_Index =>
            if Expr_Uses_Name (Expr.Prefix, Name) then
               return True;
            end if;
            for Item of Expr.Args loop
               if Expr_Uses_Name (Item, Name) then
                  return True;
               end if;
            end loop;
            return False;
         when CM.Expr_Call =>
            if Expr_Uses_Name (Expr.Callee, Name) then
               return True;
            end if;
            for Item of Expr.Args loop
               if Expr_Uses_Name (Item, Name) then
                  return True;
               end if;
            end loop;
            return False;
         when CM.Expr_Conversion | CM.Expr_Annotated | CM.Expr_Unary =>
            return
              Expr_Uses_Name (Expr.Inner, Name)
              or else Expr_Uses_Name (Expr.Target, Name);
         when CM.Expr_Binary =>
            return
              Expr_Uses_Name (Expr.Left, Name)
              or else Expr_Uses_Name (Expr.Right, Name);
         when CM.Expr_Allocator =>
            return Expr_Uses_Name (Expr.Value, Name);
         when CM.Expr_Aggregate =>
            for Field of Expr.Fields loop
               if Expr_Uses_Name (Field.Expr, Name) then
                  return True;
               end if;
            end loop;
            return False;
         when CM.Expr_Tuple =>
            for Item of Expr.Elements loop
               if Expr_Uses_Name (Item, Name) then
                  return True;
               end if;
            end loop;
            return False;
         when others =>
            return False;
      end case;
   end Expr_Uses_Name;

   function Statements_Use_Name
     (Statements : CM.Statement_Access_Vectors.Vector;
      Name       : String) return Boolean
   is
   begin
      if Name'Length = 0 then
         return False;
      end if;

      for Item of Statements loop
         if Item = null then
            null;
         else
            case Item.Kind is
               when CM.Stmt_Object_Decl =>
                  if Expr_Uses_Name (Item.Decl.Initializer, Name) then
                     return True;
                  end if;
               when CM.Stmt_Destructure_Decl =>
                  if Expr_Uses_Name (Item.Destructure.Initializer, Name) then
                     return True;
                  end if;
               when CM.Stmt_Assign =>
                  if Expr_Uses_Name (Item.Target, Name)
                    or else Expr_Uses_Name (Item.Value, Name)
                  then
                     return True;
                  end if;
               when CM.Stmt_Call =>
                  if Expr_Uses_Name (Item.Call, Name) then
                     return True;
                  end if;
               when CM.Stmt_Return =>
                  if Expr_Uses_Name (Item.Value, Name) then
                     return True;
                  end if;
               when CM.Stmt_If =>
                  if Expr_Uses_Name (Item.Condition, Name)
                    or else Statements_Use_Name (Item.Then_Stmts, Name)
                  then
                     return True;
                  end if;
                  for Part of Item.Elsifs loop
                     if Expr_Uses_Name (Part.Condition, Name)
                       or else Statements_Use_Name (Part.Statements, Name)
                     then
                        return True;
                     end if;
                  end loop;
                  if Item.Has_Else
                    and then Statements_Use_Name (Item.Else_Stmts, Name)
                  then
                     return True;
                  end if;
               when CM.Stmt_Case =>
                  if Expr_Uses_Name (Item.Case_Expr, Name) then
                     return True;
                  end if;
                  for Arm of Item.Case_Arms loop
                     if Expr_Uses_Name (Arm.Choice, Name)
                       or else Statements_Use_Name (Arm.Statements, Name)
                     then
                        return True;
                     end if;
                  end loop;
               when CM.Stmt_While | CM.Stmt_For | CM.Stmt_Loop =>
                  if Expr_Uses_Name (Item.Condition, Name)
                    or else Expr_Uses_Name (Item.Loop_Range.Name_Expr, Name)
                    or else Expr_Uses_Name (Item.Loop_Range.Low_Expr, Name)
                    or else Expr_Uses_Name (Item.Loop_Range.High_Expr, Name)
                    or else Expr_Uses_Name (Item.Loop_Iterable, Name)
                    or else Statements_Use_Name (Item.Body_Stmts, Name)
                  then
                     return True;
                  end if;
               when CM.Stmt_Exit =>
                  if Expr_Uses_Name (Item.Condition, Name) then
                     return True;
                  end if;
               when CM.Stmt_Send | CM.Stmt_Receive | CM.Stmt_Try_Receive =>
                  if Expr_Uses_Name (Item.Channel_Name, Name)
                    or else Expr_Uses_Name (Item.Value, Name)
                    or else Expr_Uses_Name (Item.Target, Name)
                    or else Expr_Uses_Name (Item.Success_Var, Name)
                  then
                     return True;
                  end if;
               when CM.Stmt_Try_Send =>
                  Raise_Internal ("unreachable: try_send rejected by resolver");
               when CM.Stmt_Select =>
                  for Arm of Item.Arms loop
                     case Arm.Kind is
                        when CM.Select_Arm_Channel =>
                           if Expr_Uses_Name (Arm.Channel_Data.Channel_Name, Name)
                             or else Statements_Use_Name (Arm.Channel_Data.Statements, Name)
                           then
                              return True;
                           end if;
                        when CM.Select_Arm_Delay =>
                           if Expr_Uses_Name (Arm.Delay_Data.Duration_Expr, Name)
                             or else Statements_Use_Name (Arm.Delay_Data.Statements, Name)
                           then
                              return True;
                           end if;
                        when others =>
                           null;
                     end case;
                  end loop;
               when CM.Stmt_Delay =>
                  if Expr_Uses_Name (Item.Value, Name) then
                     return True;
                  end if;
               when others =>
                  null;
            end case;
         end if;
      end loop;

      return False;
   end Statements_Use_Name;

   function Statements_Have_Select
     (Statements : CM.Statement_Access_Vectors.Vector) return Boolean
   is
   begin
      for Item of Statements loop
         if Item = null then
            null;
         else
            case Item.Kind is
               when CM.Stmt_If =>
                  if Statements_Have_Select (Item.Then_Stmts) then
                     return True;
                  end if;
                  for Part of Item.Elsifs loop
                     if Statements_Have_Select (Part.Statements) then
                        return True;
                     end if;
                  end loop;
                  if Item.Has_Else
                    and then Statements_Have_Select (Item.Else_Stmts)
                  then
                     return True;
                  end if;
               when CM.Stmt_Case =>
                  for Arm of Item.Case_Arms loop
                     if Statements_Have_Select (Arm.Statements) then
                        return True;
                     end if;
                  end loop;
               when CM.Stmt_While | CM.Stmt_For | CM.Stmt_Loop =>
                  if Statements_Have_Select (Item.Body_Stmts) then
                     return True;
                  end if;
               when CM.Stmt_Select =>
                  return True;
               when others =>
                  null;
            end case;
         end if;
      end loop;

      return False;
   end Statements_Have_Select;

   function Channel_Model_Has_Value_Name
     (Channel : CM.Resolved_Channel_Decl) return String is
   begin
      return FT.To_String (Channel.Name) & "_Model_Has_Value";
   end Channel_Model_Has_Value_Name;

   function Channel_Model_Length_Name
     (Channel : CM.Resolved_Channel_Decl) return String is
   begin
      return FT.To_String (Channel.Name) & "_Model_Length";
   end Channel_Model_Length_Name;

   function Channel_Uses_Sequential_Scalar_Ghost_Model
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Channel  : CM.Resolved_Channel_Decl) return Boolean
   is
   begin
      return Channel.Capacity = 1
        and then
          (Is_Plain_String_Type (Unit, Document, Channel.Element_Type)
           or else Is_Growable_Array_Type (Unit, Document, Channel.Element_Type))
        and then Unit.Tasks.Is_Empty
        and then Unit.Subprograms.Is_Empty
        and then not Statements_Have_Select (Unit.Statements);
   end Channel_Uses_Sequential_Scalar_Ghost_Model;

   function Select_Dispatcher_Name
     (Stmt : CM.Statement_Access) return String
   is
   begin
      if Stmt = null then
         return "Safe_Select_Dispatcher_L1_C1";
      end if;

      return
        "Safe_Select_Dispatcher_L"
        & Trim_Image (Long_Long_Integer (Stmt.Span.Start_Pos.Line))
        & "_C"
        & Trim_Image (Long_Long_Integer (Stmt.Span.Start_Pos.Column));
   end Select_Dispatcher_Name;

   function Select_Rotation_State_Name
     (Stmt : CM.Statement_Access) return String
   is
   begin
      return Select_Dispatcher_Name (Stmt) & "_Next_Arm";
   end Select_Rotation_State_Name;

   function Select_Dispatcher_Type_Name (Name : String) return String is
   begin
      return Name & "_Type";
   end Select_Dispatcher_Type_Name;

   function Select_Dispatcher_Timer_Name
     (Stmt : CM.Statement_Access) return String is
   begin
      return Select_Dispatcher_Name (Stmt) & "_Timer";
   end Select_Dispatcher_Timer_Name;

   function Select_Dispatcher_Arm_Helper_Name
     (Stmt : CM.Statement_Access) return String is
   begin
      return Select_Dispatcher_Name (Stmt) & "_Arm_Deadline";
   end Select_Dispatcher_Arm_Helper_Name;

   function Select_Dispatcher_Cancel_Helper_Name
     (Stmt : CM.Statement_Access) return String is
   begin
      return Select_Dispatcher_Name (Stmt) & "_Cancel_Deadline";
   end Select_Dispatcher_Cancel_Helper_Name;

   function Select_Has_Delay_Arm
     (Stmt : CM.Statement_Access) return Boolean
   is
   begin
      if Stmt = null or else Stmt.Kind /= CM.Stmt_Select then
         return False;
      end if;

      for Arm of Stmt.Arms loop
         if Arm.Kind = CM.Select_Arm_Delay then
            return True;
         end if;
      end loop;

      return False;
   end Select_Has_Delay_Arm;

   function Select_References_Channel
     (Stmt         : CM.Statement_Access;
      Channel_Name : String) return Boolean
   is
      Canonical_Channel_Name : constant String := FT.Lowercase (Channel_Name);
   begin
      if Stmt = null or else Stmt.Kind /= CM.Stmt_Select then
         return False;
      end if;

      for Arm of Stmt.Arms loop
         if Arm.Kind = CM.Select_Arm_Channel
           and then
             FT.Lowercase (CM.Flatten_Name (Arm.Channel_Data.Channel_Name)) =
               Canonical_Channel_Name
         then
            return True;
         end if;
      end loop;

      return False;
   end Select_References_Channel;

   procedure Ignore_Select_Arm (Arm : CM.Select_Arm) is
      pragma Unreferenced (Arm);
   begin
      null;
   end Ignore_Select_Arm;

   procedure Walk_Statement_Structure
     (Statements : CM.Statement_Access_Vectors.Vector)
   is
      procedure Walk_From
        (Nested_Statements : CM.Statement_Access_Vectors.Vector);

      procedure Walk_From
        (Nested_Statements : CM.Statement_Access_Vectors.Vector)
      is
      begin
         for Item of Nested_Statements loop
            if Item /= null then
               Visit_Statement (Item);
               case Item.Kind is
                  when CM.Stmt_If =>
                     Walk_From (Item.Then_Stmts);
                     for Part of Item.Elsifs loop
                        Walk_From (Part.Statements);
                     end loop;
                     if Item.Has_Else then
                        Walk_From (Item.Else_Stmts);
                     end if;
                  when CM.Stmt_Case =>
                     for Arm of Item.Case_Arms loop
                        Walk_From (Arm.Statements);
                     end loop;
                  when CM.Stmt_Match =>
                     for Arm of Item.Match_Arms loop
                        Walk_From (Arm.Statements);
                     end loop;
                  when CM.Stmt_While | CM.Stmt_For | CM.Stmt_Loop =>
                     Walk_From (Item.Body_Stmts);
                  when CM.Stmt_Select =>
                     for Arm of Item.Arms loop
                        Visit_Select_Arm (Arm);
                        case Arm.Kind is
                           when CM.Select_Arm_Channel =>
                              Walk_From (Arm.Channel_Data.Statements);
                           when CM.Select_Arm_Delay =>
                              Walk_From (Arm.Delay_Data.Statements);
                           when others =>
                              null;
                        end case;
                     end loop;
                  when others =>
                     null;
               end case;
            end if;
         end loop;
      end Walk_From;
   begin
      Walk_From (Statements);
   end Walk_Statement_Structure;

   procedure Collect_Select_Dispatcher_Names
     (Statements : CM.Statement_Access_Vectors.Vector;
      Names      : in out FT.UString_Vectors.Vector) renames AES.Collect_Select_Dispatcher_Names;
   procedure Collect_Select_Rotation_State
     (Statements : CM.Statement_Access_Vectors.Vector;
      Names      : in out FT.UString_Vectors.Vector;
      Counts     : in out FT.UString_Vectors.Vector) renames AES.Collect_Select_Rotation_State;
   procedure Collect_Select_Delay_Timer_Names
     (Statements : CM.Statement_Access_Vectors.Vector;
      Names      : in out FT.UString_Vectors.Vector) renames AES.Collect_Select_Delay_Timer_Names;
   procedure Collect_Select_Dispatcher_Names_For_Channel
     (Statements   : CM.Statement_Access_Vectors.Vector;
      Channel_Name : String;
      Names        : in out FT.UString_Vectors.Vector) renames AES.Collect_Select_Dispatcher_Names_For_Channel;
   procedure Render_Select_Dispatcher_Spec
     (Buffer : in out SU.Unbounded_String;
      Name   : String) is
   begin
      Append_Line
        (Buffer,
         "protected type "
         & Select_Dispatcher_Type_Name (Name)
         & " with Priority => System.Any_Priority'Last is",
         1);
      Append_Line (Buffer, "procedure Reset;", 2);
      Append_Line (Buffer, "procedure Signal;", 2);
      Append_Line
        (Buffer,
         "procedure Signal_Delay (Event : in out Ada.Real_Time.Timing_Events.Timing_Event);",
         2);
      Append_Line (Buffer, "entry Await (Timed_Out : out Boolean);", 2);
      Append_Line (Buffer, "private", 1);
      Append_Line (Buffer, "Signaled : Boolean := False;", 2);
      Append_Line (Buffer, "Delay_Expired : Boolean := False;", 2);
      Append_Line
        (Buffer,
         "end " & Select_Dispatcher_Type_Name (Name) & ";",
         1);
      Append_Line (Buffer);
   end Render_Select_Dispatcher_Spec;

   procedure Render_Select_Dispatcher_Object_Decl
     (Buffer : in out SU.Unbounded_String;
      Name   : String) is
   begin
      Append_Line
        (Buffer,
         Name
         & " : " & Select_Dispatcher_Type_Name (Name)
         & ASCII.LF
         & Indentation (1)
         & "  with Part_Of => Safe_Select_Internal_State;",
         1);
      Append_Line (Buffer);
   end Render_Select_Dispatcher_Object_Decl;

   procedure Render_Select_Dispatcher_Body
     (Buffer : in out SU.Unbounded_String;
      Name   : String) is
   begin
      Append_Line
        (Buffer,
         "protected body " & Select_Dispatcher_Type_Name (Name) & " is",
         1);
      Append_Line (Buffer, "procedure Reset is", 2);
      Append_Line (Buffer, "begin", 2);
      Append_Line (Buffer, "Signaled := False;", 3);
      Append_Line (Buffer, "Delay_Expired := False;", 3);
      Append_Line (Buffer, "end Reset;", 2);
      Append_Line (Buffer);
      Append_Line (Buffer, "procedure Signal is", 2);
      Append_Line (Buffer, "begin", 2);
      Append_Line (Buffer, "Signaled := True;", 3);
      Append_Line (Buffer, "end Signal;", 2);
      Append_Line (Buffer);
      Append_Line
        (Buffer,
         "procedure Signal_Delay (Event : in out Ada.Real_Time.Timing_Events.Timing_Event) is",
         2);
      Append_Line (Buffer, "begin", 2);
      Append_Line (Buffer, "pragma Unreferenced (Event);", 3);
      Append_Line (Buffer, "Delay_Expired := True;", 3);
      Append_Line (Buffer, "end Signal_Delay;", 2);
      Append_Line (Buffer);
      Append_Line (Buffer, "entry Await (Timed_Out : out Boolean) when Signaled or Delay_Expired is", 2);
      Append_Line (Buffer, "begin", 2);
      Append_Line (Buffer, "Timed_Out := Delay_Expired;", 3);
      Append_Line (Buffer, "Signaled := False;", 3);
      Append_Line (Buffer, "Delay_Expired := False;", 3);
      Append_Line (Buffer, "end Await;", 2);
      Append_Line
        (Buffer,
         "end " & Select_Dispatcher_Type_Name (Name) & ";",
         1);
      Append_Line (Buffer);
   end Render_Select_Dispatcher_Body;

   procedure Render_Select_Dispatcher_Delay_Helpers
     (Buffer        : in out SU.Unbounded_String;
      Dispatcher    : String;
      Timer_Name    : String;
      Init_Helper   : String;
      Deadline_Helper : String;
      Arm_Helper    : String;
      Cancel_Helper : String;
      Depth         : Natural := 1)
   is
   begin
      Append_Line
        (Buffer,
         "procedure " & Init_Helper,
         Depth);
      Append_Line
        (Buffer,
         "  with Global => (Output => " & Timer_Name & "),"
         & ASCII.LF
         & Indentation (Depth)
         & "       Always_Terminates;",
         Depth);
      Append_Line
        (Buffer,
         "function " & Deadline_Helper
         & " (Start : in Ada.Real_Time.Time;"
         & " Delay_Span : in Ada.Real_Time.Time_Span)"
         & " return Ada.Real_Time.Time",
         Depth);
      Append_Line (Buffer, "  with Global => null;", Depth);
      Append_Line
        (Buffer,
         "procedure " & Arm_Helper & " (Deadline : in Ada.Real_Time.Time)",
         Depth);
      Append_Line
        (Buffer,
         "  with Global => (In_Out => ("
         & Dispatcher
         & ", "
         & Timer_Name
         & ")),"
         & ASCII.LF
         & Indentation (Depth)
         & "       Always_Terminates;",
         Depth);
      Append_Line
        (Buffer,
         "procedure " & Cancel_Helper & " (Cancelled : out Boolean)",
         Depth);
      Append_Line
        (Buffer,
         "  with Global => (In_Out => ("
         & Dispatcher
         & ", "
         & Timer_Name
         & ")),"
         & ASCII.LF
         & Indentation (Depth)
         & "       Always_Terminates;",
         Depth);
      Append_Line (Buffer);

      Append_Line
        (Buffer,
         "procedure " & Init_Helper,
         Depth);
      Append_Line (Buffer, "  with SPARK_Mode => Off", Depth);
      Append_Line (Buffer, "is", Depth);
      Append_Line (Buffer, "Cancelled : Boolean;", Depth + 1);
      Append_Line (Buffer, "begin", Depth);
      Append_Line
        (Buffer,
         "Ada.Real_Time.Timing_Events.Cancel_Handler"
         & " ("
         & Timer_Name
         & ", Cancelled);",
         Depth + 1);
      Append_Line (Buffer, "end " & Init_Helper & ";", Depth);
      Append_Line (Buffer);

      Append_Line
        (Buffer,
         "function " & Deadline_Helper
         & " (Start : in Ada.Real_Time.Time;"
         & " Delay_Span : in Ada.Real_Time.Time_Span)"
         & " return Ada.Real_Time.Time",
         Depth);
      Append_Line (Buffer, "  with SPARK_Mode => Off", Depth);
      Append_Line (Buffer, "is", Depth);
      Append_Line (Buffer, "begin", Depth);
      Append_Line
        (Buffer,
         "if Ada.Real_Time.""<="" (Delay_Span, Ada.Real_Time.Time_Span_Zero) then",
         Depth + 1);
      Append_Line (Buffer, "return Start;", Depth + 2);
      Append_Line (Buffer, "end if;", Depth + 1);
      Append_Line (Buffer, "begin", Depth + 1);
      Append_Line (Buffer, "return Start + Delay_Span;", Depth + 2);
      Append_Line (Buffer, "exception", Depth + 1);
      Append_Line (Buffer, "when others =>", Depth + 2);
      Append_Line (Buffer, "return Ada.Real_Time.Time_Last;", Depth + 3);
      Append_Line (Buffer, "end;", Depth + 1);
      Append_Line (Buffer, "end " & Deadline_Helper & ";", Depth);
      Append_Line (Buffer);

      Append_Line
        (Buffer,
         "procedure " & Arm_Helper & " (Deadline : in Ada.Real_Time.Time)",
         Depth);
      Append_Line (Buffer, "  with SPARK_Mode => Off", Depth);
      Append_Line (Buffer, "is", Depth);
      Append_Line (Buffer, "begin", Depth);
      Append_Line
        (Buffer,
         "Ada.Real_Time.Timing_Events.Set_Handler"
         & " ("
         & Timer_Name
         & ", Deadline, "
         & Dispatcher
         & ".Signal_Delay'Access);",
         Depth + 1);
      Append_Line (Buffer, "end " & Arm_Helper & ";", Depth);
      Append_Line (Buffer);

      Append_Line
        (Buffer,
         "procedure " & Cancel_Helper & " (Cancelled : out Boolean)",
         Depth);
      Append_Line (Buffer, "  with SPARK_Mode => Off", Depth);
      Append_Line (Buffer, "is", Depth);
      Append_Line (Buffer, "begin", Depth);
      Append_Line
        (Buffer,
         "Ada.Real_Time.Timing_Events.Cancel_Handler"
         & " ("
         & Timer_Name
         & ", Cancelled);",
         Depth + 1);
      Append_Line (Buffer, "end " & Cancel_Helper & ";", Depth);
      Append_Line (Buffer);
   end Render_Select_Dispatcher_Delay_Helpers;

   procedure Append_Select_Dispatcher_Signals
     (Buffer       : in out SU.Unbounded_String;
      Unit         : CM.Resolved_Unit;
      Channel_Name : String;
      Depth        : Natural)
   is
      Dispatcher_Names : FT.UString_Vectors.Vector;
   begin
      Collect_Select_Dispatcher_Names_For_Channel
        (Unit.Statements,
         Channel_Name,
         Dispatcher_Names);
      for Task_Item of Unit.Tasks loop
         Collect_Select_Dispatcher_Names_For_Channel
           (Task_Item.Statements,
            Channel_Name,
            Dispatcher_Names);
      end loop;

      for Name of Dispatcher_Names loop
         Append_Line (Buffer, FT.To_String (Name) & ".Signal;", Depth);
      end loop;
   end Append_Select_Dispatcher_Signals;

   function Statements_Assign_Name
     (Statements : CM.Statement_Access_Vectors.Vector;
      Name       : String) return Boolean
   is
   begin
      if Name'Length = 0 then
         return False;
      end if;

      for Item of Statements loop
         if Item = null then
            null;
         else
            case Item.Kind is
               when CM.Stmt_Assign =>
                  if Root_Name (Item.Target) = Name then
                     return True;
                  end if;
               when CM.Stmt_If =>
                  if Statements_Assign_Name (Item.Then_Stmts, Name) then
                     return True;
                  end if;
                  for Part of Item.Elsifs loop
                     if Statements_Assign_Name (Part.Statements, Name) then
                        return True;
                     end if;
                  end loop;
                  if Item.Has_Else
                    and then Statements_Assign_Name (Item.Else_Stmts, Name)
                  then
                     return True;
                  end if;
               when CM.Stmt_Case =>
                  for Arm of Item.Case_Arms loop
                     if Statements_Assign_Name (Arm.Statements, Name) then
                        return True;
                     end if;
                  end loop;
               when CM.Stmt_While | CM.Stmt_For | CM.Stmt_Loop =>
                  if Statements_Assign_Name (Item.Body_Stmts, Name) then
                     return True;
                  end if;
               when CM.Stmt_Select =>
                  for Arm of Item.Arms loop
                     case Arm.Kind is
                        when CM.Select_Arm_Channel =>
                           if Statements_Assign_Name (Arm.Channel_Data.Statements, Name) then
                              return True;
                           end if;
                        when CM.Select_Arm_Delay =>
                           if Statements_Assign_Name (Arm.Delay_Data.Statements, Name) then
                              return True;
                           end if;
                        when others =>
                           null;
                     end case;
                  end loop;
               when others =>
                  null;
            end case;
         end if;
      end loop;

      return False;
   end Statements_Assign_Name;

   function Unit_Runtime_Assigns_Name
     (Unit : CM.Resolved_Unit;
      Name : String) return Boolean
   is
   begin
      if Name'Length = 0 then
         return False;
      elsif Statements_Assign_Name (Unit.Statements, Name) then
         return True;
      end if;

      for Subprogram of Unit.Subprograms loop
         if Statements_Assign_Name (Subprogram.Statements, Name) then
            return True;
         end if;
      end loop;

      for Task_Item of Unit.Tasks loop
         if Statements_Assign_Name (Task_Item.Statements, Name) then
            return True;
         end if;
      end loop;

      return False;
   end Unit_Runtime_Assigns_Name;

   function Statements_Immediately_Overwrite_Name
     (Statements : CM.Statement_Access_Vectors.Vector;
      Name       : String) return Boolean
   is
      function Statement_Immediately_Overwrites_Name
        (Statement : CM.Statement_Access) return Boolean;

      function Statement_Immediately_Overwrites_Name
        (Statement : CM.Statement_Access) return Boolean
      is
      begin
         if Statement = null or else Name'Length = 0 then
            return False;
         end if;

         case Statement.Kind is
            when CM.Stmt_Assign =>
               return Statement.Target /= null
                 and then Statement.Target.Kind = CM.Expr_Ident
                 and then FT.To_String (Statement.Target.Name) = Name
                 and then not Expr_Uses_Name (Statement.Value, Name);
            when CM.Stmt_If =>
               if not Statements_Immediately_Overwrite_Name (Statement.Then_Stmts, Name) then
                  return False;
               end if;
               for Part of Statement.Elsifs loop
                  if not Statements_Immediately_Overwrite_Name (Part.Statements, Name) then
                     return False;
                  end if;
               end loop;
               return Statement.Has_Else
                 and then Statements_Immediately_Overwrite_Name (Statement.Else_Stmts, Name);
            when CM.Stmt_Case =>
               if Statement.Case_Arms.Is_Empty then
                  return False;
               end if;
               for Arm of Statement.Case_Arms loop
                  if not Statements_Immediately_Overwrite_Name (Arm.Statements, Name) then
                     return False;
                  end if;
               end loop;
               return True;
            when others =>
               return False;
         end case;
      end Statement_Immediately_Overwrites_Name;
   begin
      if Name'Length = 0 or else Statements.Is_Empty then
         return False;
      end if;

      return Statement_Immediately_Overwrites_Name
        (Statements (Statements.First_Index));
   end Statements_Immediately_Overwrite_Name;

   function Block_Declarations_Immediately_Overwritten
     (Declarations : CM.Object_Decl_Vectors.Vector;
      Statements   : CM.Statement_Access_Vectors.Vector) return Boolean
   is
   begin
      if Declarations.Is_Empty or else Statements.Is_Empty then
         return False;
      end if;

      for Decl of Declarations loop
         if Decl.Is_Constant or else Decl.Initializer = null then
            return False;
         end if;
         for Name of Decl.Names loop
            if not Statements_Immediately_Overwrite_Name
              (Statements, FT.To_String (Name))
            then
               return False;
            end if;
         end loop;
      end loop;

      return True;
   end Block_Declarations_Immediately_Overwritten;

   function Selector_Is_Record_Field
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Prefix    : CM.Expr_Access;
      Selector  : String) return Boolean
   is
      Prefix_Type : GM.Type_Descriptor;
   begin
      if Prefix = null or else Selector'Length = 0 then
         return False;
      end if;

      if Prefix.Kind = CM.Expr_Select
        and then FT.To_String (Prefix.Selector) = "all"
        and then Prefix.Prefix /= null
        and then Has_Text (Prefix.Prefix.Type_Name)
      then
         Prefix_Type := Lookup_Type (Unit, Document, FT.To_String (Prefix.Prefix.Type_Name));
      elsif Has_Text (Prefix.Type_Name) then
         Prefix_Type := Lookup_Type (Unit, Document, FT.To_String (Prefix.Type_Name));
      else
         return False;
      end if;

      if not Has_Text (Prefix_Type.Name) then
         return False;
      end if;

      if Is_Access_Type (Prefix_Type) and then Has_Text (Prefix_Type.Target) then
         Prefix_Type := Lookup_Type (Unit, Document, FT.To_String (Prefix_Type.Target));
         if not Has_Text (Prefix_Type.Name) then
            return False;
         end if;
      end if;

      if FT.To_String (Prefix_Type.Kind) /= "record" then
         return False;
      end if;

      if Prefix_Type.Has_Discriminant
        and then FT.To_String (Prefix_Type.Discriminant_Name) = Selector
      then
         return True;
      end if;

      for Field of Prefix_Type.Fields loop
         if FT.To_String (Field.Name) = Selector then
            return True;
         end if;
      end loop;
      return False;
   end Selector_Is_Record_Field;

   function Is_Aspect_State_Name (Name : String) return Boolean is
   begin
      for Ch of Name loop
         if Ch = ''' then
            return False;
         end if;
      end loop;
      return True;
   end Is_Aspect_State_Name;

   function Is_Constant_Object_Name
     (Unit : CM.Resolved_Unit;
      Name : String) return Boolean
   is
   begin
      for Decl of Unit.Objects loop
         if Decl.Is_Constant then
            for Object_Name of Decl.Names loop
               if FT.To_String (Object_Name) = Name then
                  return True;
               end if;
            end loop;
         end if;
      end loop;
      return False;
   end Is_Constant_Object_Name;

   function Lookup_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Name     : String) return GM.Type_Descriptor
   is
   begin
      for Item of Unit.Types loop
         if FT.To_String (Item.Name) = Name
           or else Ada_Safe_Name (FT.To_String (Item.Name)) = Name
         then
            return Item;
         end if;
      end loop;
      for Item of Unit.Imported_Types loop
         if FT.To_String (Item.Name) = Name
           or else Ada_Safe_Name (FT.To_String (Item.Name)) = Name
         then
            return Item;
         end if;
      end loop;
      for Item of Document.Types loop
         if FT.To_String (Item.Name) = Name
           or else Ada_Safe_Name (FT.To_String (Item.Name)) = Name
         then
            return Item;
         end if;
      end loop;
      return (others => <>);
   end Lookup_Type;

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

   function Preferred_Imported_Synthetic_Type
     (Unit : CM.Resolved_Unit;
      Info : GM.Type_Descriptor) return GM.Type_Descriptor
   is
      Name_Text : constant String := FT.To_String (Info.Name);
      Tail_Name : constant String := Synthetic_Type_Tail_Name (Name_Text);
      Kind_Text : constant String := FT.Lowercase (FT.To_String (Info.Kind));
      function Matches
        (Candidate : GM.Type_Descriptor) return Boolean is
         Candidate_Kind : constant String :=
           FT.Lowercase (FT.To_String (Candidate.Kind));
      begin
         return
           Synthetic_Type_Tail_Name (FT.To_String (Candidate.Name)) = Tail_Name
           and then
             (Kind_Text = ""
              or else Candidate_Kind = ""
              or else Candidate_Kind = Kind_Text);
      end Matches;
   begin
      if Tail_Name'Length < 2
        or else Tail_Name (Tail_Name'First .. Tail_Name'First + 1) /= "__"
      then
         return Info;
      end if;

      for Item of Unit.Imported_Types loop
         if Matches (Item) then
            return Item;
         end if;
      end loop;

      for Item of Unit.Imported_Subprograms loop
         if Item.Has_Return_Type and then Matches (Item.Return_Type) then
            return Item.Return_Type;
         end if;
         if not Item.Params.Is_Empty then
            for Param of Item.Params loop
               if Matches (Param.Type_Info) then
                  return Param.Type_Info;
               end if;
            end loop;
         end if;
      end loop;

      return Info;
   end Preferred_Imported_Synthetic_Type;

   function Is_Builtin_Integer_Name (Name : String) return Boolean is
   begin
      return Name in "integer" | "long_long_integer";
   end Is_Builtin_Integer_Name;

   function Is_Builtin_Binary_Name (Name : String) return Boolean is
   begin
      return Binary_Width_From_Name (Name) /= 0;
   end Is_Builtin_Binary_Name;

   function Is_Builtin_Float_Name (Name : String) return Boolean is
   begin
      return Name in "float" | "long_float";
   end Is_Builtin_Float_Name;

   function Base_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return GM.Type_Descriptor
   is
      Result : GM.Type_Descriptor := Preferred_Imported_Synthetic_Type (Unit, Info);
   begin
      while FT.To_String (Result.Kind) = "subtype"
        and then Result.Has_Base
        and then Has_Type (Unit, Document, FT.To_String (Result.Base))
      loop
         Result := Lookup_Type (Unit, Document, FT.To_String (Result.Base));
      end loop;
      return Result;
   end Base_Type;

   function Has_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Name     : String) return Boolean is
      Item : constant GM.Type_Descriptor := Lookup_Type (Unit, Document, Name);
   begin
      return Has_Text (Item.Name);
   end Has_Type;

   function Type_Info_From_Name
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Name      : String;
      Type_Info : out GM.Type_Descriptor) return Boolean
   is
      Lower_Name : constant String := FT.Lowercase (Name);
   begin
      if Name'Length = 0 then
         return False;
      elsif Has_Type (Unit, Document, Name) then
         Type_Info := Lookup_Type (Unit, Document, Name);
         return True;
      elsif Lower_Name = "integer" or else Lower_Name = "long_long_integer" then
         Type_Info := BT.Integer_Type;
         return True;
      elsif Lower_Name = "boolean" then
         Type_Info := BT.Boolean_Type;
         return True;
      elsif Lower_Name = "string" then
         Type_Info := BT.String_Type;
         return True;
      elsif Lower_Name = "result" then
         Type_Info := BT.Result_Type;
         return True;
      elsif Is_Builtin_Binary_Name (Lower_Name) then
         Type_Info := BT.Binary_Type (Positive (Binary_Width_From_Name (Lower_Name)));
         return True;
      end if;

      return False;
   end Type_Info_From_Name;

   function Lookup_Object_Type
     (Unit      : CM.Resolved_Unit;
      Name      : String;
      Type_Info : out GM.Type_Descriptor) return Boolean
   is
   begin
      for Decl of Unit.Objects loop
         for Object_Name of Decl.Names loop
            if FT.To_String (Object_Name) = Name then
               Type_Info := Decl.Type_Info;
               return True;
            end if;
         end loop;
      end loop;
      return False;
   end Lookup_Object_Type;

   function Span_Contains
     (Outer : FT.Source_Span;
      Inner : FT.Source_Span) return Boolean
   is
      function Before
        (Left  : FT.Source_Position;
         Right : FT.Source_Position) return Boolean is
      begin
         return Left.Line < Right.Line
           or else (Left.Line = Right.Line and then Left.Column < Right.Column);
      end Before;
   begin
      if (Outer.Start_Pos.Line = FT.Null_Span.Start_Pos.Line
          and then Outer.Start_Pos.Column = FT.Null_Span.Start_Pos.Column
          and then Outer.End_Pos.Line = FT.Null_Span.End_Pos.Line
          and then Outer.End_Pos.Column = FT.Null_Span.End_Pos.Column)
        or else
         (Inner.Start_Pos.Line = FT.Null_Span.Start_Pos.Line
          and then Inner.Start_Pos.Column = FT.Null_Span.Start_Pos.Column
          and then Inner.End_Pos.Line = FT.Null_Span.End_Pos.Line
          and then Inner.End_Pos.Column = FT.Null_Span.End_Pos.Column)
      then
         return False;
      end if;

      return
        not Before (Inner.Start_Pos, Outer.Start_Pos)
        and then not Before (Outer.End_Pos, Inner.End_Pos);
   end Span_Contains;

   function Lookup_Mir_Local_Type
     (Document  : GM.Mir_Document;
      Name      : String;
      Span      : FT.Source_Span;
      Type_Info : out GM.Type_Descriptor) return Boolean
   is
   begin
      if Name'Length = 0 then
         return False;
      end if;

      for Graph of Document.Graphs loop
         if Graph.Has_Span and then Span_Contains (Graph.Span, Span) then
            for Local of Graph.Locals loop
               if FT.To_String (Local.Name) = Name then
                  Type_Info := Local.Type_Info;
                  return True;
               end if;
            end loop;
         end if;
      end loop;

      return False;
   end Lookup_Mir_Local_Type;

   function Lookup_Local_Object_Type
     (Unit      : CM.Resolved_Unit;
      Name      : String;
      Span      : FT.Source_Span;
      Type_Info : out GM.Type_Descriptor) return Boolean
   is
      function Before
        (Left  : FT.Source_Position;
         Right : FT.Source_Position) return Boolean is
      begin
         return Left.Line < Right.Line
           or else (Left.Line = Right.Line and then Left.Column < Right.Column);
      end Before;

      function Starts_After_Use (Item_Span : FT.Source_Span) return Boolean is
      begin
         return
           not (Item_Span.Start_Pos.Line = FT.Null_Span.Start_Pos.Line
                and then Item_Span.Start_Pos.Column = FT.Null_Span.Start_Pos.Column
                and then Item_Span.End_Pos.Line = FT.Null_Span.End_Pos.Line
                and then Item_Span.End_Pos.Column = FT.Null_Span.End_Pos.Column)
           and then Before (Span.Start_Pos, Item_Span.Start_Pos);
      end Starts_After_Use;

      function Lookup_In_Decls
        (Decls : CM.Resolved_Object_Decl_Vectors.Vector) return Boolean is
      begin
         for Decl of Decls loop
            for Object_Name of Decl.Names loop
               if FT.To_String (Object_Name) = Name then
                  Type_Info := Decl.Type_Info;
                  return True;
               end if;
            end loop;
         end loop;
         return False;
      end Lookup_In_Decls;

      function Lookup_In_Decl
        (Decl : CM.Object_Decl) return Boolean is
      begin
         for Object_Name of Decl.Names loop
            if FT.To_String (Object_Name) = Name then
               Type_Info := Decl.Type_Info;
               return True;
            end if;
         end loop;
         return False;
      end Lookup_In_Decl;

      function Lookup_In_Statements
        (Statements : CM.Statement_Access_Vectors.Vector) return Boolean
      is
      begin
         for Item of Statements loop
            if Item = null then
               null;
            elsif Starts_After_Use (Item.Span) then
               return False;
            else
               if Item.Kind = CM.Stmt_Object_Decl and then Lookup_In_Decl (Item.Decl) then
                  return True;
               end if;

               if not Span_Contains (Item.Span, Span) then
                  null;
               else
                  case Item.Kind is
                     when CM.Stmt_Object_Decl =>
                        return Lookup_In_Decl (Item.Decl);
                     when CM.Stmt_If =>
                        if Lookup_In_Statements (Item.Then_Stmts) then
                           return True;
                        end if;
                        for Part of Item.Elsifs loop
                           if Lookup_In_Statements (Part.Statements) then
                              return True;
                           end if;
                        end loop;
                        if Item.Has_Else
                          and then Lookup_In_Statements (Item.Else_Stmts)
                        then
                           return True;
                        end if;
                        return False;
                     when CM.Stmt_Case =>
                        for Arm of Item.Case_Arms loop
                           if Lookup_In_Statements (Arm.Statements) then
                              return True;
                           end if;
                        end loop;
                        return False;
                     when CM.Stmt_While | CM.Stmt_For | CM.Stmt_Loop =>
                        return Lookup_In_Statements (Item.Body_Stmts);
                     when CM.Stmt_Select =>
                        for Arm of Item.Arms loop
                           case Arm.Kind is
                              when CM.Select_Arm_Channel =>
                                 if Lookup_In_Statements (Arm.Channel_Data.Statements) then
                                    return True;
                                 end if;
                              when CM.Select_Arm_Delay =>
                                 if Lookup_In_Statements (Arm.Delay_Data.Statements) then
                                    return True;
                                 end if;
                              when others =>
                                 null;
                           end case;
                        end loop;
                        return False;
                     when others =>
                        return False;
                  end case;
               end if;
            end if;
         end loop;
         return False;
      end Lookup_In_Statements;
   begin
      if Name'Length = 0 then
         return False;
      end if;

      for Subprogram of Unit.Subprograms loop
         if Span_Contains (Subprogram.Span, Span) then
            return
              Lookup_In_Decls (Subprogram.Declarations)
              or else Lookup_In_Statements (Subprogram.Statements);
         end if;
      end loop;

      for Task_Item of Unit.Tasks loop
         if Span_Contains (Task_Item.Span, Span) then
            return
              Lookup_In_Decls (Task_Item.Declarations)
              or else Lookup_In_Statements (Task_Item.Statements);
         end if;
      end loop;

      return Lookup_In_Statements (Unit.Statements);
   end Lookup_Local_Object_Type;

   function Type_Info_From_Name_Or_Synthetic
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Name      : String;
      Type_Info : out GM.Type_Descriptor) return Boolean
   is
      Found_Synthetic : Boolean := False;
   begin
      if Type_Info_From_Name (Unit, Document, Name, Type_Info) then
         return True;
      end if;

      Type_Info := Synthetic_Bounded_String_Type (Name, Found_Synthetic);
      return Found_Synthetic;
   end Type_Info_From_Name_Or_Synthetic;

   function Lookup_Selected_Type
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Prefix    : GM.Type_Descriptor;
      Selector  : String;
      Type_Info : out GM.Type_Descriptor) return Boolean
   is
      Base : GM.Type_Descriptor := Base_Type (Unit, Document, Prefix);
   begin
      if Selector'Length = 0 or else not Has_Text (Base.Name) then
         return False;
      end if;

      if FT.Lowercase (Selector) = "all"
        and then Is_Access_Type (Base)
        and then Base.Has_Target
      then
         return Type_Info_From_Name_Or_Synthetic
           (Unit, Document, FT.To_String (Base.Target), Type_Info);
      end if;

      if Is_Access_Type (Base) and then Base.Has_Target then
         Base := Lookup_Type (Unit, Document, FT.To_String (Base.Target));
      end if;

      if Is_Result_Builtin (Base) and then FT.Lowercase (Selector) = "message" then
         Type_Info := BT.String_Type;
         return True;
      end if;

      if Is_Tuple_Type (Base)
        and then Selector (Selector'First) in '0' .. '9'
      then
         declare
            Tuple_Index : constant Positive := Positive (Natural'Value (Selector));
         begin
            if Tuple_Index in Base.Tuple_Element_Types.First_Index .. Base.Tuple_Element_Types.Last_Index then
               return
                 Type_Info_From_Name_Or_Synthetic
                   (Unit,
                    Document,
                    FT.To_String (Base.Tuple_Element_Types (Tuple_Index)),
                    Type_Info);
            end if;
         exception
            when Constraint_Error =>
               return False;
         end;
      end if;

      if FT.To_String (Base.Kind) = "record" then
         if Base.Has_Discriminant
           and then FT.To_String (Base.Discriminant_Name) = Selector
         then
            return
              Type_Info_From_Name_Or_Synthetic
                (Unit,
                 Document,
                 FT.To_String (Base.Discriminant_Type),
                 Type_Info);
         end if;

         for Field of Base.Fields loop
            if FT.To_String (Field.Name) = Selector then
               return
                 Type_Info_From_Name_Or_Synthetic
                   (Unit,
                    Document,
                    FT.To_String (Field.Type_Name),
                    Type_Info);
            end if;
         end loop;
      end if;

      return False;
   end Lookup_Selected_Type;

   function Resolve_Print_Type
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Expr      : CM.Expr_Access;
      State     : Emit_State;
      Type_Info : out GM.Type_Descriptor) return Boolean
   is
      Prefix_Info : GM.Type_Descriptor;
      Left_Info   : GM.Type_Descriptor;
      Operator    : constant String :=
        (if Expr /= null and then Has_Text (Expr.Operator) then FT.To_String (Expr.Operator) else "");
   begin
      if Expr = null then
         return False;
      elsif Has_Text (Expr.Type_Name)
        and then Type_Info_From_Name (Unit, Document, FT.To_String (Expr.Type_Name), Type_Info)
      then
         return True;
      end if;

      case Expr.Kind is
         when CM.Expr_String =>
            Type_Info := BT.String_Type;
            return True;
         when CM.Expr_Bool =>
            Type_Info := BT.Boolean_Type;
            return True;
         when CM.Expr_Int =>
            Type_Info := BT.Integer_Type;
            return True;
         when CM.Expr_Ident =>
            return
              Lookup_Bound_Type (State, FT.To_String (Expr.Name), Type_Info)
              or else Lookup_Object_Type (Unit, FT.To_String (Expr.Name), Type_Info)
              or else
                Lookup_Mir_Local_Type
                  (Document,
                   FT.To_String (Expr.Name),
                   Expr.Span,
                   Type_Info)
              or else
                Lookup_Local_Object_Type
                  (Unit,
                   FT.To_String (Expr.Name),
                   Expr.Span,
                   Type_Info);
         when CM.Expr_Select =>
            return
              Expr.Prefix /= null
              and then Resolve_Print_Type (Unit, Document, Expr.Prefix, State, Prefix_Info)
              and then Lookup_Selected_Type
                (Unit,
                 Document,
                 Prefix_Info,
                 FT.To_String (Expr.Selector),
                 Type_Info);
         when CM.Expr_Resolved_Index =>
            if Expr.Prefix /= null
              and then Resolve_Print_Type (Unit, Document, Expr.Prefix, State, Prefix_Info)
            then
               declare
                  Base : constant GM.Type_Descriptor := Base_Type (Unit, Document, Prefix_Info);
               begin
                  if Base.Has_Component_Type then
                     return
                       Type_Info_From_Name_Or_Synthetic
                         (Unit,
                          Document,
                          FT.To_String (Base.Component_Type),
                          Type_Info);
                  end if;
               end;
            end if;
            return False;
         when CM.Expr_Conversion | CM.Expr_Annotated | CM.Expr_Subtype_Indication =>
            return
              (Expr.Target /= null
               and then Resolve_Print_Type (Unit, Document, Expr.Target, State, Type_Info))
              or else
              (Expr.Inner /= null
               and then Resolve_Print_Type (Unit, Document, Expr.Inner, State, Type_Info));
         when CM.Expr_Call =>
            if Expr.Callee /= null
              and then Expr.Callee.Kind in CM.Expr_Ident | CM.Expr_Select
            then
               declare
                  Callee_Name : constant String := FT.To_String (Expr.Callee.Name);
               begin
                  if Callee_Name'Length > 0 then
                     for Subprogram of Unit.Subprograms loop
                        if FT.To_String (Subprogram.Name) = Callee_Name
                          and then Subprogram.Has_Return_Type
                        then
                           Type_Info := Subprogram.Return_Type;
                           return True;
                        end if;
                     end loop;
                  end if;
               end;
            end if;
            return False;
         when CM.Expr_Unary =>
            return
              Expr.Inner /= null
              and then Resolve_Print_Type (Unit, Document, Expr.Inner, State, Type_Info);
         when CM.Expr_Binary =>
            if Operator in "=" | "/=" | "<" | "<=" | ">" | ">=" | "and then" | "or else" then
               Type_Info := BT.Boolean_Type;
               return True;
            elsif Operator in "and" | "or" | "xor" then
               if Expr.Left /= null
                 and then Resolve_Print_Type (Unit, Document, Expr.Left, State, Left_Info)
               then
                  if Is_Binary_Type (Unit, Document, Left_Info) then
                     Type_Info := Left_Info;
                     return True;
                  elsif FT.Lowercase (FT.To_String (Base_Type (Unit, Document, Left_Info).Kind)) = "boolean"
                    or else FT.Lowercase (FT.To_String (Base_Type (Unit, Document, Left_Info).Name)) = "boolean"
                  then
                     Type_Info := BT.Boolean_Type;
                     return True;
                  end if;
               end if;
               return False;
            end if;
            return
              Expr.Left /= null
              and then Resolve_Print_Type (Unit, Document, Expr.Left, State, Type_Info);
         when others =>
            return False;
      end case;
   end Resolve_Print_Type;

   function Is_Integer_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean
   is
      Base            : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
      Kind            : constant String := FT.To_String (Base.Kind);
      Name            : constant String := FT.To_String (Base.Name);
      Unresolved_Base : constant String :=
        (if Kind = "subtype" and then Base.Has_Base then FT.To_String (Base.Base) else "");
   begin
      return Kind = "integer"
        or else Is_Builtin_Integer_Name (Name)
        or else Is_Builtin_Integer_Name (Unresolved_Base);
   end Is_Integer_Type;

   function Is_Binary_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean
   is
      Base            : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
      Kind            : constant String := FT.To_String (Base.Kind);
      Name            : constant String := FT.To_String (Base.Name);
      Unresolved_Base : constant String :=
        (if Kind = "subtype" and then Base.Has_Base then FT.To_String (Base.Base) else "");
   begin
      return (Kind = "binary" and then Base.Has_Bit_Width)
        or else Is_Builtin_Binary_Name (Name)
        or else Is_Builtin_Binary_Name (Unresolved_Base);
   end Is_Binary_Type;

   function Binary_Bit_Width
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Positive
   is
      Base : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
      Width : constant Natural := Binary_Width_From_Name (FT.To_String (Base.Name));
   begin
      if Base.Has_Bit_Width then
         return Base.Bit_Width;
      elsif Width /= 0 then
         return Positive (Width);
      end if;
      Raise_Internal ("binary type missing bit width during Ada emission");
   end Binary_Bit_Width;

   function Is_Float_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean
   is
      Base            : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
      Kind            : constant String := FT.To_String (Base.Kind);
      Name            : constant String := FT.To_String (Base.Name);
      Unresolved_Base : constant String :=
        (if Kind = "subtype" and then Base.Has_Base then FT.To_String (Base.Base) else "");
   begin
      return Kind = "float"
        or else Is_Builtin_Float_Name (Name)
        or else Is_Builtin_Float_Name (Unresolved_Base);
   end Is_Float_Type;

   function Is_Integer_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Name     : String) return Boolean
   is
   begin
      if Is_Builtin_Integer_Name (Name) then
         return True;
      elsif Has_Type (Unit, Document, Name) then
         return Is_Integer_Type (Unit, Document, Lookup_Type (Unit, Document, Name));
      end if;
      return False;
   end Is_Integer_Type;

   function Is_Binary_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Name     : String) return Boolean
   is
   begin
      if Is_Builtin_Binary_Name (Name) then
         return True;
      elsif Has_Type (Unit, Document, Name) then
         return Is_Binary_Type (Unit, Document, Lookup_Type (Unit, Document, Name));
      end if;
      return False;
   end Is_Binary_Type;

   function Binary_Bit_Width
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Name     : String) return Positive
   is
   begin
      if Is_Builtin_Binary_Name (Name) then
         return Positive (Binary_Width_From_Name (Name));
      elsif Has_Type (Unit, Document, Name) then
         return Binary_Bit_Width (Unit, Document, Lookup_Type (Unit, Document, Name));
      end if;
      Raise_Internal ("binary type name missing width during Ada emission");
   end Binary_Bit_Width;

   function Is_Float_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Name     : String) return Boolean
   is
   begin
      if Is_Builtin_Float_Name (Name) then
         return True;
      elsif Has_Type (Unit, Document, Name) then
         return Is_Float_Type (Unit, Document, Lookup_Type (Unit, Document, Name));
      end if;
      return False;
   end Is_Float_Type;

   function Is_Array_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean
   is
      Base : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
   begin
      return FT.Lowercase (FT.To_String (Base.Kind)) = "array";
   end Is_Array_Type;

   function Is_Tuple_Type (Info : GM.Type_Descriptor) return Boolean is
   begin
      return FT.Lowercase (FT.To_String (Info.Kind)) = "tuple";
   end Is_Tuple_Type;

   function Is_Result_Builtin (Info : GM.Type_Descriptor) return Boolean is
   begin
      return Info.Is_Result_Builtin;
   end Is_Result_Builtin;

   function Render_Result_Empty_Aggregate return String is
   begin
      return
        "(Ok => True, Message => Ada.Strings.Unbounded.Null_Unbounded_String)";
   end Render_Result_Empty_Aggregate;

   function Render_Result_Fail_Aggregate (Message_Image : String) return String is
   begin
      return
        "(Ok => False, Message => Ada.Strings.Unbounded.To_Unbounded_String ("
        & Message_Image
        & "))";
   end Render_Result_Fail_Aggregate;

   function Is_Access_Type (Info : GM.Type_Descriptor) return Boolean renames AI.Is_Access_Type;
   function Is_Owner_Access (Info : GM.Type_Descriptor) return Boolean renames AI.Is_Owner_Access;

   function Owner_Allocate_Post_Field_Is_Trackable
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Field_Info : GM.Type_Descriptor) return Boolean
   is
      Base      : constant GM.Type_Descriptor := Base_Type (Unit, Document, Field_Info);
      Base_Kind : constant String := FT.Lowercase (FT.To_String (Base.Kind));
      Base_Name : constant String := FT.Lowercase (FT.To_String (Base.Name));
   begin
      return
        not Is_Access_Type (Field_Info)
        and then not Has_Heap_Value_Type (Unit, Document, Field_Info)
        and then
          (Is_Integer_Type (Unit, Document, Field_Info)
           or else Base_Kind = "boolean"
           or else Base_Name = "boolean"
           or else Base_Kind = "enum"
           or else Base_Kind = "character"
           or else Base_Name = "character");
   end Owner_Allocate_Post_Field_Is_Trackable;

   function Is_Alias_Access (Info : GM.Type_Descriptor) return Boolean is
      Role : constant String := FT.To_String (Info.Access_Role);
   begin
      return Is_Access_Type (Info)
        and then not Is_Owner_Access (Info)
        and then Role in "Borrow" | "Observe";
   end Is_Alias_Access;

   function Needs_Implicit_Dereference
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access) return Boolean
   is
      Prefix_Info : GM.Type_Descriptor := (others => <>);
   begin
      return Expr /= null
        and then Has_Text (Expr.Type_Name)
        and then Type_Info_From_Name
          (Unit,
           Document,
           FT.To_String (Expr.Type_Name),
           Prefix_Info)
        and then Is_Access_Type (Base_Type (Unit, Document, Prefix_Info));
   end Needs_Implicit_Dereference;

   function Is_Bounded_String_Type
     (Info : GM.Type_Descriptor) return Boolean renames AET.Is_Bounded_String_Type;
   function Bounded_String_Instance_Name
     (Bound : Natural) return String renames AET.Bounded_String_Instance_Name;
   function Bounded_String_Instance_Name
     (Info : GM.Type_Descriptor) return String renames AET.Bounded_String_Instance_Name;
   function Bounded_String_Type_Name
     (Bound : Natural) return String renames AET.Bounded_String_Type_Name;
   function Bounded_String_Type_Name
     (Info : GM.Type_Descriptor) return String renames AET.Bounded_String_Type_Name;
   function Synthetic_Bounded_String_Type
     (Name  : String;
      Found : out Boolean) return GM.Type_Descriptor
   is
      Prefix : constant String := "__bounded_string_";
   begin
      Found := False;
      if not Starts_With (Name, Prefix) then
         return (others => <>);
      end if;

      declare
         Bound_Text : constant String :=
           Name (Name'First + Prefix'Length .. Name'Last);
      begin
         if Bound_Text'Length = 0 then
            return (others => <>);
         end if;
         for Ch of Bound_Text loop
            if Ch not in '0' .. '9' then
               return (others => <>);
            end if;
         end loop;
         Found := True;
         declare
            Result : GM.Type_Descriptor := (others => <>);
            Bound  : constant Natural := Natural'Value (Bound_Text);
         begin
            Result.Name := FT.To_UString (Name);
            Result.Kind := FT.To_UString ("string");
            Result.Has_Base := True;
            Result.Base := FT.To_UString ("string");
            Result.Has_Length_Bound := True;
            Result.Length_Bound := Bound;
            return Result;
         end;
      exception
         when Constraint_Error =>
            Found := False;
            return (others => <>);
      end;
   end Synthetic_Bounded_String_Type;

   procedure Register_Bounded_String_Type
     (State : in out Emit_State;
      Info  : GM.Type_Descriptor) renames AET.Register_Bounded_String_Type;
   function Is_Plain_String_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean renames AET.Is_Plain_String_Type;
   function Is_Growable_Array_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean renames AET.Is_Growable_Array_Type;
   function Try_Map_Key_Value_Types
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Info       : GM.Type_Descriptor;
      Key_Type   : out GM.Type_Descriptor;
      Value_Type : out GM.Type_Descriptor) return Boolean
   is
      Base       : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
      Entry_Type : GM.Type_Descriptor := (others => <>);
   begin
      Key_Type := (others => <>);
      Value_Type := (others => <>);

      if not Is_Growable_Array_Type (Unit, Document, Base)
        or else not Base.Has_Component_Type
      then
         return False;
      end if;

      Entry_Type :=
        Base_Type
          (Unit,
           Document,
           Resolve_Type_Name (Unit, Document, FT.To_String (Base.Component_Type)));
      if FT.Lowercase (FT.To_String (Entry_Type.Kind)) /= "tuple"
        or else Natural (Entry_Type.Tuple_Element_Types.Length) /= 2
      then
         return False;
      end if;

      Key_Type :=
        Resolve_Type_Name
          (Unit,
           Document,
           FT.To_String
             (Entry_Type.Tuple_Element_Types (Entry_Type.Tuple_Element_Types.First_Index)));
      Value_Type :=
        Resolve_Type_Name
          (Unit,
           Document,
           FT.To_String
             (Entry_Type.Tuple_Element_Types (Entry_Type.Tuple_Element_Types.First_Index + 1)));
      return True;
   end Try_Map_Key_Value_Types;

   function Constant_Cleanup_Uses_Shared_Runtime_Free
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Info      : GM.Type_Descriptor;
      Free_Proc : String) return Boolean
   is
      Base : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
   begin
      if Is_Plain_String_Type (Unit, Document, Info) then
         return Free_Proc = "Safe_String_RT.Free";
      end if;

      if Is_Growable_Array_Type (Unit, Document, Info) then
         return Free_Proc = Array_Runtime_Instance_Name (Info) & ".Free"
           or else Free_Proc = Array_Runtime_Instance_Name (Base) & ".Free";
      end if;

      return False;
   end Constant_Cleanup_Uses_Shared_Runtime_Free;

   function Sanitized_Helper_Name (Name : String) return String renames AI.Sanitized_Helper_Name;

   function Local_Free_Helper_Name (Info : GM.Type_Descriptor) return String is
   begin
      return "Free_" & Sanitized_Helper_Name (FT.To_String (Info.Name));
   end Local_Free_Helper_Name;

   function Needs_Generated_For_Of_Helper
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean renames AET.Needs_Generated_For_Of_Helper;
   function For_Of_Helper_Base_Name
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return String
   is
   begin
      return "For_Of_" & Sanitized_Helper_Name (Render_Type_Name (Info));
   end For_Of_Helper_Base_Name;

   function For_Of_Copy_Helper_Name
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return String renames AET.For_Of_Copy_Helper_Name;
   function For_Of_Free_Helper_Name
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return String renames AET.For_Of_Free_Helper_Name;
   function Needs_Generated_Heap_Helper
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean renames AET.Needs_Generated_Heap_Helper;
   function Heap_Helper_Base_Name
     (Family    : Heap_Helper_Family_Kind;
      Scope_Name : String;
      Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Info      : GM.Type_Descriptor) return String renames AET.Heap_Helper_Base_Name;
   function Heap_Copy_Helper_Name
     (Family    : Heap_Helper_Family_Kind;
      Scope_Name : String;
      Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Info      : GM.Type_Descriptor) return String renames AET.Heap_Copy_Helper_Name;
   function Heap_Free_Helper_Name
     (Family    : Heap_Helper_Family_Kind;
      Scope_Name : String;
      Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Info      : GM.Type_Descriptor) return String renames AET.Heap_Free_Helper_Name;
   function Same_Variant_Choice
     (Left, Right : GM.Variant_Field) return Boolean is
   begin
      return Left.Is_Others = Right.Is_Others
        and then
          (if Left.Is_Others
           then True
           else Left.Choice.Kind = Right.Choice.Kind
             and then Render_Scalar_Value (Left.Choice) = Render_Scalar_Value (Right.Choice));
   end Same_Variant_Choice;

   procedure Mark_Heap_Runtime_Dependencies
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Info      : GM.Type_Descriptor;
      State     : in out Emit_State;
      Seen      : in out FT.UString_Vectors.Vector)
   is
      Base     : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
      Type_Key : constant String := Render_Type_Name (Info);

      procedure Add_From_Name (Name_Text : String) is
      begin
         if Name_Text'Length = 0 then
            return;
         end if;

         Mark_Heap_Runtime_Dependencies
           (Unit,
            Document,
            Resolve_Type_Name (Unit, Document, Name_Text),
            State,
            Seen);
      end Add_From_Name;
   begin
      if Contains_Name (Seen, Type_Key) then
         return;
      end if;

      Seen.Append (FT.To_UString (Type_Key));

      if Is_Plain_String_Type (Unit, Document, Base) then
         State.Needs_Safe_String_RT := True;
         return;
      elsif Is_Growable_Array_Type (Unit, Document, Base) then
         State.Needs_Safe_Array_RT := True;
         Add_From_Name (FT.To_String (Base.Component_Type));
         return;
      elsif FT.Lowercase (FT.To_String (Base.Kind)) = "array"
        and then Base.Has_Component_Type
      then
         Add_From_Name (FT.To_String (Base.Component_Type));
      elsif FT.Lowercase (FT.To_String (Base.Kind)) = "record" then
         for Field of Base.Fields loop
            Add_From_Name (FT.To_String (Field.Type_Name));
         end loop;
         for Field of Base.Variant_Fields loop
            Add_From_Name (FT.To_String (Field.Type_Name));
         end loop;
      elsif Is_Tuple_Type (Base) then
         for Item of Base.Tuple_Element_Types loop
            Add_From_Name (FT.To_String (Item));
         end loop;
      end if;
   end Mark_Heap_Runtime_Dependencies;

   procedure Append_Heap_Copy_Value
     (Buffer     : in out SU.Unbounded_String;
      Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      State      : in out Emit_State;
      Family     : Heap_Helper_Family_Kind;
      Scope_Name : String;
      Target_Text : String;
      Source_Text : String;
      Info       : GM.Type_Descriptor;
      Depth      : Natural) renames AET.Append_Heap_Copy_Value;
   procedure Append_Heap_Free_Value
     (Buffer     : in out SU.Unbounded_String;
      Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      State      : in out Emit_State;
      Family     : Heap_Helper_Family_Kind;
      Scope_Name : String;
      Target_Text : String;
      Info       : GM.Type_Descriptor;
      Depth      : Natural) renames AET.Append_Heap_Free_Value;
   procedure Append_Record_Heap_Copy_Assignments
     (Buffer      : in out SU.Unbounded_String;
      Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      State       : in out Emit_State;
      Family      : Heap_Helper_Family_Kind;
      Scope_Name  : String;
      Base        : GM.Type_Descriptor;
      Target_Prefix : String;
      Source_Prefix : String;
      Depth       : Natural)
   is
   begin
      for Field of Base.Fields loop
         declare
            Field_Info : constant GM.Type_Descriptor :=
              Resolve_Type_Name (Unit, Document, FT.To_String (Field.Type_Name));
         begin
            if Has_Heap_Value_Type (Unit, Document, Field_Info) then
               Append_Heap_Copy_Value
                 (Buffer,
                  Unit,
                  Document,
                  State,
                  Family,
                  Scope_Name,
                  Target_Prefix & FT.To_String (Field.Name),
                  Source_Prefix & FT.To_String (Field.Name),
                  Field_Info,
                  Depth);
            end if;
         end;
      end loop;

      if not Base.Variant_Fields.Is_Empty then
         declare
            Disc_Name : constant String :=
              FT.To_String
                ((if Has_Text (Base.Variant_Discriminant_Name)
                  then Base.Variant_Discriminant_Name
                  else Base.Discriminant_Name));
            Index : Positive := Base.Variant_Fields.First_Index;
         begin
            if Disc_Name'Length = 0 then
               return;
            end if;

            Append_Line (Buffer, "case " & Source_Prefix & Disc_Name & " is", Depth);
            while Index <= Base.Variant_Fields.Last_Index loop
               declare
                  First_Field : constant GM.Variant_Field :=
                    Base.Variant_Fields (Index);
                  Emitted_Statements : Boolean := False;
               begin
                  Append_Line
                    (Buffer,
                     "when "
                     & (if First_Field.Is_Others
                        then "others"
                        else Render_Scalar_Value (First_Field.Choice))
                     & " =>",
                     Depth + 1);
                  loop
                     declare
                        Variant_Field : constant GM.Variant_Field :=
                          Base.Variant_Fields (Index);
                        Field_Info : constant GM.Type_Descriptor :=
                          Resolve_Type_Name
                            (Unit,
                             Document,
                             FT.To_String (Variant_Field.Type_Name));
                     begin
                        if Has_Heap_Value_Type (Unit, Document, Field_Info) then
                           Append_Heap_Copy_Value
                             (Buffer,
                              Unit,
                              Document,
                              State,
                              Family,
                              Scope_Name,
                              Target_Prefix & FT.To_String (Variant_Field.Name),
                              Source_Prefix & FT.To_String (Variant_Field.Name),
                              Field_Info,
                              Depth + 2);
                           Emitted_Statements := True;
                        end if;
                     end;
                     exit when Index = Base.Variant_Fields.Last_Index;
                     exit when not Same_Variant_Choice
                       (First_Field,
                        Base.Variant_Fields (Index + 1));
                     Index := Index + 1;
                  end loop;
                  if not Emitted_Statements then
                     Append_Line (Buffer, "null;", Depth + 2);
                  end if;
                  Index := Index + 1;
               end;
            end loop;
            Append_Line (Buffer, "end case;", Depth);
         end;
      end if;
   end Append_Record_Heap_Copy_Assignments;

   procedure Append_Record_Heap_Free_Statements
     (Buffer      : in out SU.Unbounded_String;
      Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      State       : in out Emit_State;
      Family      : Heap_Helper_Family_Kind;
      Scope_Name  : String;
      Base        : GM.Type_Descriptor;
      Value_Prefix : String;
      Depth       : Natural)
   is
   begin
      for Field of Base.Fields loop
         declare
            Field_Info : constant GM.Type_Descriptor :=
              Resolve_Type_Name (Unit, Document, FT.To_String (Field.Type_Name));
         begin
            if Has_Heap_Value_Type (Unit, Document, Field_Info) then
               Append_Heap_Free_Value
                 (Buffer,
                  Unit,
                  Document,
                  State,
                  Family,
                  Scope_Name,
                  Value_Prefix & FT.To_String (Field.Name),
                  Field_Info,
                  Depth);
            end if;
         end;
      end loop;

      if not Base.Variant_Fields.Is_Empty then
         declare
            Disc_Name : constant String :=
              FT.To_String
                ((if Has_Text (Base.Variant_Discriminant_Name)
                  then Base.Variant_Discriminant_Name
                  else Base.Discriminant_Name));
            Index : Positive := Base.Variant_Fields.First_Index;
         begin
            if Disc_Name'Length = 0 then
               return;
            end if;

            Append_Line (Buffer, "case " & Value_Prefix & Disc_Name & " is", Depth);
            while Index <= Base.Variant_Fields.Last_Index loop
               declare
                  First_Field : constant GM.Variant_Field :=
                    Base.Variant_Fields (Index);
                  Emitted_Statements : Boolean := False;
               begin
                  Append_Line
                    (Buffer,
                     "when "
                     & (if First_Field.Is_Others
                        then "others"
                        else Render_Scalar_Value (First_Field.Choice))
                     & " =>",
                     Depth + 1);
                  loop
                     declare
                        Variant_Field : constant GM.Variant_Field :=
                          Base.Variant_Fields (Index);
                        Field_Info : constant GM.Type_Descriptor :=
                          Resolve_Type_Name
                            (Unit,
                             Document,
                             FT.To_String (Variant_Field.Type_Name));
                     begin
                        if Has_Heap_Value_Type (Unit, Document, Field_Info) then
                           Append_Heap_Free_Value
                             (Buffer,
                              Unit,
                              Document,
                              State,
                              Family,
                              Scope_Name,
                              Value_Prefix & FT.To_String (Variant_Field.Name),
                              Field_Info,
                              Depth + 2);
                           Emitted_Statements := True;
                        end if;
                     end;
                     exit when Index = Base.Variant_Fields.Last_Index;
                     exit when not Same_Variant_Choice
                       (First_Field,
                        Base.Variant_Fields (Index + 1));
                     Index := Index + 1;
                  end loop;
                  if not Emitted_Statements then
                     Append_Line (Buffer, "null;", Depth + 2);
                  end if;
                  Index := Index + 1;
               end;
            end loop;
            Append_Line (Buffer, "end case;", Depth);
         end;
      end if;
   end Append_Record_Heap_Free_Statements;

   procedure Append_Generated_Heap_Copy_Body
     (Buffer      : in out SU.Unbounded_String;
      Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      State       : in out Emit_State;
      Family      : Heap_Helper_Family_Kind;
      Scope_Name  : String;
      Info        : GM.Type_Descriptor;
      Depth       : Natural)
   is
      Base : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
      Kind : constant String := FT.Lowercase (FT.To_String (Base.Kind));
   begin
      if Kind = "array" and then Base.Has_Component_Type then
         declare
            Component_Info : constant GM.Type_Descriptor :=
              Resolve_Type_Name (Unit, Document, FT.To_String (Base.Component_Type));
         begin
            Append_Line (Buffer, "for Index in Source'Range loop", Depth);
            Append_Heap_Copy_Value
              (Buffer,
               Unit,
               Document,
               State,
               Family,
               Scope_Name,
               "Target (Index)",
               "Source (Index)",
               Component_Info,
               Depth + 1);
            Append_Line (Buffer, "end loop;", Depth);
         end;
      elsif Kind = "record" then
         if not Base.Variant_Fields.Is_Empty
           or else Has_Text (Base.Discriminant_Name)
           or else Has_Text (Base.Variant_Discriminant_Name)
         then
            Append_Line (Buffer, "Target := Source;", Depth);
            Append_Record_Heap_Copy_Assignments
              (Buffer,
               Unit,
               Document,
               State,
               Family,
               Scope_Name,
               Base,
               "Target.",
               "Source.",
               Depth);
         else
            for Field of Base.Fields loop
               declare
                  Field_Info : constant GM.Type_Descriptor :=
                    Resolve_Type_Name (Unit, Document, FT.To_String (Field.Type_Name));
               begin
                  if Has_Heap_Value_Type (Unit, Document, Field_Info) then
                     Append_Heap_Copy_Value
                       (Buffer,
                        Unit,
                        Document,
                        State,
                        Family,
                        Scope_Name,
                        "Target." & FT.To_String (Field.Name),
                        "Source." & FT.To_String (Field.Name),
                        Field_Info,
                        Depth);
                  else
                     Append_Line
                       (Buffer,
                        "Target."
                        & FT.To_String (Field.Name)
                        & " := Source."
                        & FT.To_String (Field.Name)
                        & ";",
                        Depth);
                  end if;
               end;
            end loop;
         end if;
      elsif Is_Tuple_Type (Base) then
         for Index in Base.Tuple_Element_Types.First_Index .. Base.Tuple_Element_Types.Last_Index loop
            declare
               Item_Info : constant GM.Type_Descriptor :=
                 Resolve_Type_Name
                   (Unit,
                    Document,
                    FT.To_String (Base.Tuple_Element_Types (Index)));
            begin
               if Has_Heap_Value_Type (Unit, Document, Item_Info) then
                  Append_Heap_Copy_Value
                    (Buffer,
                     Unit,
                     Document,
                     State,
                     Family,
                     Scope_Name,
                     "Target." & Tuple_Field_Name (Positive (Index)),
                     "Source." & Tuple_Field_Name (Positive (Index)),
                     Item_Info,
                     Depth);
               else
                  Append_Line
                    (Buffer,
                     "Target."
                     & Tuple_Field_Name (Positive (Index))
                     & " := Source."
                     & Tuple_Field_Name (Positive (Index))
                     & ";",
                     Depth);
               end if;
            end;
         end loop;
      end if;
   end Append_Generated_Heap_Copy_Body;

   procedure Append_Generated_Heap_Free_Body
     (Buffer      : in out SU.Unbounded_String;
      Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      State       : in out Emit_State;
      Family      : Heap_Helper_Family_Kind;
      Scope_Name  : String;
      Info        : GM.Type_Descriptor;
      Depth       : Natural)
   is
      Base : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
      Kind : constant String := FT.Lowercase (FT.To_String (Base.Kind));
   begin
      if Kind = "array" and then Base.Has_Component_Type then
         declare
            Component_Info : constant GM.Type_Descriptor :=
              Resolve_Type_Name (Unit, Document, FT.To_String (Base.Component_Type));
         begin
            if Has_Heap_Value_Type (Unit, Document, Component_Info) then
               Append_Line (Buffer, "for Index in Value'Range loop", Depth);
               Append_Heap_Free_Value
                 (Buffer,
                  Unit,
                  Document,
                  State,
                  Family,
                  Scope_Name,
                  "Value (Index)",
                  Component_Info,
                  Depth + 1);
               Append_Line (Buffer, "end loop;", Depth);
            end if;
         end;
      elsif Kind = "record" then
         Append_Record_Heap_Free_Statements
           (Buffer,
            Unit,
            Document,
            State,
            Family,
            Scope_Name,
            Base,
            "Value.",
            Depth);
      elsif Is_Tuple_Type (Base) then
         for Index in Base.Tuple_Element_Types.First_Index .. Base.Tuple_Element_Types.Last_Index loop
            declare
               Item_Info : constant GM.Type_Descriptor :=
                 Resolve_Type_Name
                   (Unit,
                    Document,
                    FT.To_String (Base.Tuple_Element_Types (Index)));
            begin
               if Has_Heap_Value_Type (Unit, Document, Item_Info) then
                  Append_Heap_Free_Value
                    (Buffer,
                     Unit,
                     Document,
                     State,
                     Family,
                     Scope_Name,
                     "Value." & Tuple_Field_Name (Positive (Index)),
                     Item_Info,
                     Depth);
               end if;
            end;
         end loop;
      end if;
   end Append_Generated_Heap_Free_Body;

   function Local_Allocate_Helper_Name (Info : GM.Type_Descriptor) return String is
   begin
      return "Allocate_" & Sanitized_Helper_Name (FT.To_String (Info.Name));
   end Local_Allocate_Helper_Name;

   function Local_Dispose_Helper_Name (Info : GM.Type_Descriptor) return String is
   begin
      return "Dispose_" & Sanitized_Helper_Name (FT.To_String (Info.Name));
   end Local_Dispose_Helper_Name;

   function Local_Ownership_Runtime_Name (Info : GM.Type_Descriptor) return String is
   begin
      return "Ownership_" & Sanitized_Helper_Name (FT.To_String (Info.Name));
   end Local_Ownership_Runtime_Name;

   function Channel_Copy_Helper_Name
     (Channel_Item : CM.Resolved_Channel_Decl) return String is
   begin
      return FT.To_String (Channel_Item.Name) & "_Copy_Value";
   end Channel_Copy_Helper_Name;

   function Channel_Free_Helper_Name
     (Channel_Item : CM.Resolved_Channel_Decl) return String is
   begin
      return FT.To_String (Channel_Item.Name) & "_Free_Value";
   end Channel_Free_Helper_Name;

   function Channel_Has_Length_Model
     (Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      Channel_Item : CM.Resolved_Channel_Decl) return Boolean is
   begin
      return
        Is_Plain_String_Type (Unit, Document, Channel_Item.Element_Type)
        or else
        Is_Growable_Array_Type (Unit, Document, Channel_Item.Element_Type);
   end Channel_Has_Length_Model;

   function Channel_Has_Scalar_Length_Model
     (Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      Channel_Item : CM.Resolved_Channel_Decl) return Boolean is
   begin
      return Channel_Has_Length_Model (Unit, Document, Channel_Item)
        and then Channel_Item.Capacity = 1;
   end Channel_Has_Scalar_Length_Model;

   function Channel_Uses_Runtime_Length_Formals
     (Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      Channel_Item : CM.Resolved_Channel_Decl) return Boolean is
   begin
      return Channel_Has_Length_Model (Unit, Document, Channel_Item);
   end Channel_Uses_Runtime_Length_Formals;

   function Render_Channel_Operation_Target
     (Unit           : CM.Resolved_Unit;
      Document       : GM.Mir_Document;
      State          : in out Emit_State;
      Channel_Expr   : CM.Expr_Access;
      Channel_Item   : CM.Resolved_Channel_Decl;
      Operation_Name : String) return String is
   begin
      if Channel_Uses_Sequential_Scalar_Ghost_Model
        (Unit, Document, Channel_Item)
      then
         return FT.To_String (Channel_Item.Name) & "_" & Operation_Name;
      end if;

      return Render_Expr (Unit, Document, Channel_Expr, State) & "." & Operation_Name;
   end Render_Channel_Operation_Target;

   function Channel_Length_Image
     (Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      State        : in out Emit_State;
      Channel_Item : CM.Resolved_Channel_Decl;
      Value_Image  : String) return String
   is
      Element_Info : constant GM.Type_Descriptor := Channel_Item.Element_Type;
   begin
      if Is_Plain_String_Type (Unit, Document, Element_Info) then
         State.Needs_Safe_String_RT := True;
         return "Safe_String_RT.Length (" & Value_Image & ")";
      end if;

      State.Needs_Safe_Array_RT := True;
      return
        Array_Runtime_Instance_Name (Base_Type (Unit, Document, Element_Info))
        & ".Length ("
        & Value_Image
        & ")";
   end Channel_Length_Image;

   procedure Append_Heap_Channel_Free
     (Buffer       : in out SU.Unbounded_String;
      Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      Channel_Item : CM.Resolved_Channel_Decl;
      Target_Image : String;
      Depth        : Natural)
   is
      Element_Info : constant GM.Type_Descriptor := Channel_Item.Element_Type;
   begin
      if Is_Plain_String_Type (Unit, Document, Element_Info) then
         Append_Line (Buffer, "Safe_String_RT.Free (" & Target_Image & ");", Depth);
      elsif Is_Growable_Array_Type (Unit, Document, Element_Info) then
         Append_Line
           (Buffer,
            Array_Runtime_Instance_Name
              (Base_Type (Unit, Document, Element_Info))
            & ".Free ("
            & Target_Image
            & ");",
            Depth);
      else
         Append_Line
           (Buffer,
            Channel_Free_Helper_Name (Channel_Item)
            & " ("
            & Target_Image
            & ");",
            Depth);
      end if;
   end Append_Heap_Channel_Free;

   procedure Append_Channel_Length_Assert
     (Buffer       : in out SU.Unbounded_String;
      Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      State        : in out Emit_State;
      Channel_Item : CM.Resolved_Channel_Decl;
      Value_Image  : String;
      Length_Name  : String;
      Depth        : Natural) is
   begin
      if Channel_Has_Length_Model (Unit, Document, Channel_Item) then
         Append_Line
           (Buffer,
            "pragma Assert ("
            & Channel_Length_Image
                (Unit, Document, State, Channel_Item, Value_Image)
            & " = "
            & Length_Name
            & ");",
            Depth);
      end if;
   end Append_Channel_Length_Assert;

   function Channel_Staged_Value_Name
     (Statement_Index : Positive) return String is
   begin
      return
        "Safe_Channel_Staged_"
        & Ada.Strings.Fixed.Trim
            (Natural'Image (Natural (Statement_Index)),
             Ada.Strings.Both);
   end Channel_Staged_Value_Name;

   function Channel_Staged_Length_Name
     (Statement_Index : Positive) return String is
   begin
      return
        "Safe_Channel_Length_"
        & Ada.Strings.Fixed.Trim
            (Natural'Image (Natural (Statement_Index)),
             Ada.Strings.Both);
   end Channel_Staged_Length_Name;

   procedure Append_Staged_Channel_Declarations
     (Buffer                 : in out SU.Unbounded_String;
      Unit                   : CM.Resolved_Unit;
      Document               : GM.Mir_Document;
      Channel_Item           : CM.Resolved_Channel_Decl;
      Value_Name             : String;
      Length_Name            : String;
      Value_Type_Name        : String;
      Success_Name           : String;
      Depth                  : Natural;
      Suppress_Init_Warnings : Boolean) is
   begin
      if Suppress_Init_Warnings then
         Append_Initialization_Warning_Suppression (Buffer, Depth);
      end if;
      Append_Line
        (Buffer,
         Value_Name
         & " : "
         & Value_Type_Name
         & " := "
         & Default_Value_Expr
             (Unit,
              Document,
              Channel_Item.Element_Type)
         & ";",
         Depth);
      if Channel_Uses_Runtime_Length_Formals (Unit, Document, Channel_Item) then
         Append_Line
           (Buffer,
            Length_Name & " : Natural := 0;",
            Depth);
      end if;
      if Success_Name'Length > 0 then
         Append_Line
           (Buffer,
            Success_Name & " : Boolean := False;",
            Depth);
      end if;
      if Suppress_Init_Warnings then
         Append_Initialization_Warning_Restore (Buffer, Depth);
      end if;
   end Append_Staged_Channel_Declarations;

   procedure Append_Staged_Channel_Call
     (Buffer                  : in out SU.Unbounded_String;
      Unit                    : CM.Resolved_Unit;
      Document                : GM.Mir_Document;
      Operation_Target        : String;
      Channel_Item            : CM.Resolved_Channel_Decl;
      Value_Name              : String;
      Length_Name             : String;
      Success_Image           : String;
      Depth                   : Natural;
      Force_Staged_Warnings   : Boolean;
      Wrap_Task_Call_Warnings : Boolean) is
   begin
      if Wrap_Task_Call_Warnings then
         Append_Task_Channel_Call_Warning_Suppression (Buffer, Depth);
      end if;
      if Force_Staged_Warnings
        or else Channel_Uses_Runtime_Length_Formals (Unit, Document, Channel_Item)
      then
         Append_Channel_Staged_Call_Warning_Suppression (Buffer, Depth);
      end if;
      Append_Line
        (Buffer,
         Operation_Target
         & " ("
         & Value_Name
         & (if Channel_Uses_Runtime_Length_Formals (Unit, Document, Channel_Item)
            then ", " & Length_Name
            else "")
         & (if Success_Image'Length > 0
            then ", " & Success_Image
            else "")
         & ");",
         Depth);
      if Force_Staged_Warnings
        or else Channel_Uses_Runtime_Length_Formals (Unit, Document, Channel_Item)
      then
         Append_Channel_Staged_Call_Warning_Restore (Buffer, Depth);
      end if;
      if Wrap_Task_Call_Warnings then
         Append_Task_Channel_Call_Warning_Restore (Buffer, Depth);
      end if;
   end Append_Staged_Channel_Call;

   procedure Append_Staged_Channel_Length_Reconcile
     (Buffer       : in out SU.Unbounded_String;
      Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      State        : in out Emit_State;
      Channel_Item : CM.Resolved_Channel_Decl;
      Value_Name   : String;
      Length_Name  : String;
      Depth        : Natural) is
   begin
      if Channel_Uses_Runtime_Length_Formals (Unit, Document, Channel_Item) then
         if Channel_Has_Scalar_Length_Model (Unit, Document, Channel_Item)
           and then not Channel_Uses_Sequential_Scalar_Ghost_Model
             (Unit, Document, Channel_Item)
         then
            Append_Line
              (Buffer,
               "pragma Assume ("
               & Channel_Length_Image
                   (Unit, Document, State, Channel_Item, Value_Name)
               & " = "
               & Length_Name
               & ");",
               Depth);
         elsif not Channel_Uses_Sequential_Scalar_Ghost_Model
           (Unit, Document, Channel_Item)
         then
            Append_Line
              (Buffer,
               Length_Name
               & " := "
               & Channel_Length_Image
                   (Unit, Document, State, Channel_Item, Value_Name)
               & ";",
               Depth);
         end if;
         Append_Channel_Length_Assert
           (Buffer,
            Unit,
            Document,
            State,
            Channel_Item,
            Value_Name,
            Length_Name,
            Depth);
      end if;
   end Append_Staged_Channel_Length_Reconcile;

   procedure Append_Staged_Channel_Target_Adoption
     (Buffer       : in out SU.Unbounded_String;
      Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      State        : in out Emit_State;
      Channel_Item : CM.Resolved_Channel_Decl;
      Target_Image : String;
      Value_Name   : String;
      Length_Name  : String;
      Depth        : Natural) is
   begin
      Append_Local_Warning_Suppression (Buffer, Depth);
      Append_Heap_Channel_Free
        (Buffer,
         Unit,
         Document,
         Channel_Item,
         Target_Image,
         Depth);
      Append_Local_Warning_Restore (Buffer, Depth);
      Append_Line
        (Buffer,
         Target_Image & " := " & Value_Name & ";",
         Depth);
      if Channel_Uses_Runtime_Length_Formals (Unit, Document, Channel_Item) then
         Append_Line
           (Buffer,
            "pragma Assert ("
            & Channel_Length_Image
                (Unit, Document, State, Channel_Item, Target_Image)
            & " = "
            & Length_Name
            & ");",
            Depth);
      end if;
   end Append_Staged_Channel_Target_Adoption;

   function Array_Runtime_Instance_Name (Info : GM.Type_Descriptor) return String is
   begin
      return Ada_Qualified_Name (FT.To_String (Info.Name)) & "_RT";
   end Array_Runtime_Instance_Name;

   function Array_Runtime_Default_Element_Name (Info : GM.Type_Descriptor) return String is
   begin
      return Ada_Qualified_Name (FT.To_String (Info.Name)) & "_Default_Element";
   end Array_Runtime_Default_Element_Name;

   function Array_Runtime_Clone_Element_Name (Info : GM.Type_Descriptor) return String is
   begin
      return Ada_Qualified_Name (FT.To_String (Info.Name)) & "_Clone_Element";
   end Array_Runtime_Clone_Element_Name;

   function Array_Runtime_Free_Element_Name (Info : GM.Type_Descriptor) return String is
   begin
      return Ada_Qualified_Name (FT.To_String (Info.Name)) & "_Free_Element";
   end Array_Runtime_Free_Element_Name;

   function Resolve_Type_Name
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Name     : String) return GM.Type_Descriptor
   is
      Found_Synthetic : Boolean := False;
      Synthetic       : GM.Type_Descriptor := (others => <>);
      Lower_Name      : constant String := FT.Lowercase (Name);
      Result          : GM.Type_Descriptor := (others => <>);
      Not_Null_Access_Constant_Prefix : constant String := "not null access constant ";
      Access_Constant_Prefix          : constant String := "access constant ";
      Not_Null_Access_Prefix          : constant String := "not null access ";
      Access_Prefix                   : constant String := "access ";

      function Find_Local_Synthetic_Type
        (Target_Name : String;
         Found       : out Boolean) return GM.Type_Descriptor
      is
         Match : GM.Type_Descriptor := (others => <>);

         procedure Check_Info (Info : GM.Type_Descriptor);
         procedure Check_Expr (Expr : CM.Expr_Access);
         procedure Check_Decls (Decls : CM.Resolved_Object_Decl_Vectors.Vector);
         procedure Check_Decls (Decls : CM.Object_Decl_Vectors.Vector);
         procedure Check_Statements
           (Statements : CM.Statement_Access_Vectors.Vector);

         procedure Check_Info (Info : GM.Type_Descriptor) is
         begin
            if Found or else not Has_Text (Info.Name) then
               return;
            end if;

            if FT.To_String (Info.Name) = Target_Name then
               if Starts_With (Target_Name, "__tuple")
                 and then Info.Tuple_Element_Types.Is_Empty
               then
                  return;
               end if;
               Match := Info;
               Found := True;
            end if;
         end Check_Info;

         procedure Check_Expr (Expr : CM.Expr_Access) is
         begin
            if Found or else Expr = null then
               return;
            end if;

            if Expr.Kind = CM.Expr_Tuple
              and then Has_Text (Expr.Type_Name)
              and then FT.To_String (Expr.Type_Name) = Target_Name
            then
               Match.Name := Expr.Type_Name;
               Match.Kind := FT.To_UString ("tuple");
               for Element of Expr.Elements loop
                  if Element /= null and then Has_Text (Element.Type_Name) then
                     Match.Tuple_Element_Types.Append (Element.Type_Name);
                  end if;
               end loop;
               Found := True;
               return;
            end if;

            Check_Expr (Expr.Prefix);
            Check_Expr (Expr.Callee);
            Check_Expr (Expr.Inner);
            Check_Expr (Expr.Left);
            Check_Expr (Expr.Right);
            Check_Expr (Expr.Value);
            Check_Expr (Expr.Target);
            for Item of Expr.Args loop
               exit when Found;
               Check_Expr (Item);
            end loop;
            for Item of Expr.Elements loop
               exit when Found;
               Check_Expr (Item);
            end loop;
            for Field of Expr.Fields loop
               exit when Found;
               Check_Expr (Field.Expr);
            end loop;
         end Check_Expr;

         procedure Check_Decls (Decls : CM.Resolved_Object_Decl_Vectors.Vector) is
         begin
            for Decl of Decls loop
               Check_Info (Decl.Type_Info);
               exit when Found;
               Check_Expr (Decl.Initializer);
               exit when Found;
            end loop;
         end Check_Decls;

         procedure Check_Decls (Decls : CM.Object_Decl_Vectors.Vector) is
         begin
            for Decl of Decls loop
               Check_Info (Decl.Type_Info);
               exit when Found;
               Check_Expr (Decl.Initializer);
               exit when Found;
            end loop;
         end Check_Decls;

         procedure Check_Statements
           (Statements : CM.Statement_Access_Vectors.Vector)
         is
         begin
            for Item of Statements loop
               exit when Found;
               if Item = null then
                  null;
               else
                  case Item.Kind is
                     when CM.Stmt_Object_Decl =>
                        Check_Info (Item.Decl.Type_Info);
                        Check_Expr (Item.Decl.Initializer);
                     when CM.Stmt_Destructure_Decl =>
                        Check_Info (Item.Destructure.Type_Info);
                        Check_Expr (Item.Destructure.Initializer);
                     when CM.Stmt_If =>
                        Check_Expr (Item.Condition);
                        Check_Statements (Item.Then_Stmts);
                        for Part of Item.Elsifs loop
                           exit when Found;
                           Check_Expr (Part.Condition);
                           Check_Statements (Part.Statements);
                        end loop;
                        if Item.Has_Else then
                           Check_Statements (Item.Else_Stmts);
                        end if;
                     when CM.Stmt_Case =>
                        Check_Expr (Item.Case_Expr);
                        for Arm of Item.Case_Arms loop
                           exit when Found;
                           Check_Expr (Arm.Choice);
                           Check_Statements (Arm.Statements);
                        end loop;
                     when CM.Stmt_While | CM.Stmt_Loop | CM.Stmt_For =>
                        Check_Expr (Item.Condition);
                        Check_Expr (Item.Loop_Iterable);
                        Check_Expr (Item.Loop_Range.Low_Expr);
                        Check_Expr (Item.Loop_Range.High_Expr);
                        Check_Decls (Item.Declarations);
                        Check_Statements (Item.Body_Stmts);
                     when CM.Stmt_Select =>
                        for Arm of Item.Arms loop
                           exit when Found;
                           case Arm.Kind is
                              when CM.Select_Arm_Channel =>
                                 Check_Info (Arm.Channel_Data.Type_Info);
                                 Check_Expr (Arm.Channel_Data.Channel_Name);
                                 Check_Statements (Arm.Channel_Data.Statements);
                              when CM.Select_Arm_Delay =>
                                 Check_Expr (Arm.Delay_Data.Duration_Expr);
                                 Check_Statements (Arm.Delay_Data.Statements);
                              when others =>
                                 null;
                           end case;
                        end loop;
                     when others =>
                        Check_Expr (Item.Target);
                        Check_Expr (Item.Value);
                        Check_Expr (Item.Call);
                        Check_Expr (Item.Condition);
                        Check_Expr (Item.Case_Expr);
                        Check_Expr (Item.Match_Expr);
                        Check_Expr (Item.Channel_Name);
                        Check_Expr (Item.Success_Var);
                  end case;
               end if;
            end loop;
         end Check_Statements;
      begin
         Found := False;

         for Item of Unit.Types loop
            Check_Info (Item);
            exit when Found;
         end loop;
         for Item of Unit.Objects loop
            exit when Found;
            Check_Info (Item.Type_Info);
         end loop;
         for Item of Unit.Channels loop
            exit when Found;
            Check_Info (Item.Element_Type);
         end loop;
         for Item of Unit.Subprograms loop
            exit when Found;
            for Param of Item.Params loop
               Check_Info (Param.Type_Info);
               exit when Found;
            end loop;
            if not Found and then Item.Has_Return_Type then
               Check_Info (Item.Return_Type);
            end if;
            if not Found then
               Check_Decls (Item.Declarations);
               Check_Statements (Item.Statements);
            end if;
         end loop;
         for Item of Unit.Tasks loop
            exit when Found;
            Check_Decls (Item.Declarations);
            Check_Statements (Item.Statements);
         end loop;
         if not Found then
            Check_Statements (Unit.Statements);
         end if;

         return Match;
      end Find_Local_Synthetic_Type;
   begin
      if Name'Length = 0 then
         return (others => <>);
      end if;

      if Has_Type (Unit, Document, Name) then
         return Lookup_Type (Unit, Document, Name);
      elsif Starts_With (Name, "__tuple") then
         declare
            Found_Local_Synthetic : Boolean := False;
         begin
            Result := Find_Local_Synthetic_Type (Name, Found_Local_Synthetic);
            if Found_Local_Synthetic then
               return Result;
            end if;
         end;
      elsif Starts_With (Lower_Name, "not null access constant ") then
         Result.Kind := FT.To_UString ("access");
         Result.Name := FT.To_UString (Name);
         Result.Has_Target := True;
         Result.Target :=
           FT.To_UString
             (Name (Name'First + Not_Null_Access_Constant_Prefix'Length .. Name'Last));
         Result.Not_Null := True;
         Result.Is_Constant := True;
         return Result;
      elsif Starts_With (Lower_Name, "access constant ") then
         Result.Kind := FT.To_UString ("access");
         Result.Name := FT.To_UString (Name);
         Result.Has_Target := True;
         Result.Target :=
           FT.To_UString (Name (Name'First + Access_Constant_Prefix'Length .. Name'Last));
         Result.Is_Constant := True;
         return Result;
      elsif Starts_With (Lower_Name, "not null access ") then
         Result.Kind := FT.To_UString ("access");
         Result.Name := FT.To_UString (Name);
         Result.Has_Target := True;
         Result.Target :=
           FT.To_UString (Name (Name'First + Not_Null_Access_Prefix'Length .. Name'Last));
         Result.Not_Null := True;
         return Result;
      elsif Starts_With (Lower_Name, "access ") then
         Result.Kind := FT.To_UString ("access");
         Result.Name := FT.To_UString (Name);
         Result.Has_Target := True;
         Result.Target := FT.To_UString (Name (Name'First + Access_Prefix'Length .. Name'Last));
         return Result;
      elsif Lower_Name = "safe_string_rt.safe_string" then
         return BT.String_Type;
      elsif Starts_With (Lower_Name, "safe_tuple_") then
         return
           (Name => FT.To_UString (Name),
            Kind => FT.To_UString ("tuple"),
            others => <>);
      elsif Starts_With (Name, "__growable_array_") then
         declare
            Prefix : constant String := "__growable_array_";
            Suffix : constant String := Name (Name'First + Prefix'Length .. Name'Last);
         begin
            Result.Name := FT.To_UString (Name);
            Result.Kind := FT.To_UString ("array");
            Result.Growable := True;
            Result.Has_Component_Type := True;
            Result.Component_Type :=
              Resolve_Type_Name (Unit, Document, Suffix).Name;
            return Result;
         end;
      elsif Starts_With (Lower_Name, "safe_constraint_")
        or else Starts_With (Name, "__constraint_")
      then
         Result.Name := FT.To_UString (Name);
         Result.Kind := FT.To_UString ("subtype");
         if Ada.Strings.Fixed.Index (Lower_Name, "integer") > 0 then
            Result.Has_Base := True;
            Result.Base := FT.To_UString ("integer");
         elsif Ada.Strings.Fixed.Index (Lower_Name, "string") > 0 then
            Result.Has_Base := True;
            Result.Base := FT.To_UString ("string");
         end if;
         return Result;
      elsif Lower_Name = "string" then
         return BT.String_Type;
      elsif Lower_Name = "boolean" then
         return BT.Boolean_Type;
      elsif Is_Builtin_Integer_Name (Lower_Name) then
         return BT.Integer_Type;
      elsif Is_Builtin_Float_Name (Lower_Name) then
         return
           (if Lower_Name = "long_float"
            then BT.Long_Float_Type
            elsif Lower_Name = "duration"
            then BT.Duration_Type
            else BT.Float_Type);
      elsif Is_Builtin_Binary_Name (Lower_Name) then
         return BT.Binary_Type (Positive (Binary_Width_From_Name (Lower_Name)));
      elsif Lower_Name = "result" then
         return BT.Result_Type;
      end if;

      Synthetic := Synthetic_Bounded_String_Type (Name, Found_Synthetic);
      if Found_Synthetic then
         return Synthetic;
      end if;

      Raise_Internal ("type lookup failed during Ada emission for '" & Name & "'");
   end Resolve_Type_Name;

   function Has_Heap_Value_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean
   is
      Base : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
   begin
      if Is_Plain_String_Type (Unit, Document, Base)
        or else Is_Growable_Array_Type (Unit, Document, Base)
      then
         return True;
      elsif FT.Lowercase (FT.To_String (Base.Kind)) = "array"
        and then Base.Has_Component_Type
      then
         return
           Has_Heap_Value_Type
             (Unit,
              Document,
              Resolve_Type_Name (Unit, Document, FT.To_String (Base.Component_Type)));
      elsif FT.Lowercase (FT.To_String (Base.Kind)) = "record" then
         for Field of Base.Fields loop
            if Has_Heap_Value_Type
                 (Unit,
                  Document,
                  Resolve_Type_Name (Unit, Document, FT.To_String (Field.Type_Name)))
            then
               return True;
            end if;
         end loop;
         for Field of Base.Variant_Fields loop
            if Has_Heap_Value_Type
                 (Unit,
                  Document,
                  Resolve_Type_Name (Unit, Document, FT.To_String (Field.Type_Name)))
            then
               return True;
            end if;
         end loop;
      elsif Is_Tuple_Type (Base) then
         for Item of Base.Tuple_Element_Types loop
            if Has_Heap_Value_Type
                 (Unit,
                  Document,
                  Resolve_Type_Name (Unit, Document, FT.To_String (Item)))
            then
               return True;
            end if;
         end loop;
      end if;

      return False;
   end Has_Heap_Value_Type;

   function Has_Growable_Runtime_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean
   is
      Base : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
   begin
      if Is_Growable_Array_Type (Unit, Document, Base) then
         return True;
      elsif FT.Lowercase (FT.To_String (Base.Kind)) = "array"
        and then Base.Has_Component_Type
      then
         return
           Has_Growable_Runtime_Type
             (Unit,
              Document,
              Resolve_Type_Name (Unit, Document, FT.To_String (Base.Component_Type)));
      elsif FT.Lowercase (FT.To_String (Base.Kind)) = "record" then
         for Field of Base.Fields loop
            if Has_Growable_Runtime_Type
                 (Unit,
                  Document,
                  Resolve_Type_Name (Unit, Document, FT.To_String (Field.Type_Name)))
            then
               return True;
            end if;
         end loop;
         for Field of Base.Variant_Fields loop
            if Has_Growable_Runtime_Type
                 (Unit,
                  Document,
                  Resolve_Type_Name (Unit, Document, FT.To_String (Field.Type_Name)))
            then
               return True;
            end if;
         end loop;
      elsif Is_Tuple_Type (Base) then
         for Item of Base.Tuple_Element_Types loop
            if Has_Growable_Runtime_Type
                 (Unit,
                  Document,
                  Resolve_Type_Name (Unit, Document, FT.To_String (Item)))
            then
               return True;
            end if;
         end loop;
      end if;

      return False;
   end Has_Growable_Runtime_Type;

   function Uses_Identity_Array_Runtime
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean
   is
      Base : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
   begin
      return FT.Lowercase (FT.To_String (Base.Kind)) = "array"
        and then Base.Growable
        and then Base.Has_Component_Type
        and then
          not Has_Heap_Value_Type
            (Unit,
             Document,
             Resolve_Type_Name (Unit, Document, FT.To_String (Base.Component_Type)));
   end Uses_Identity_Array_Runtime;

   function Array_Runtime_Generic_Name
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return String
   is
   begin
      if Uses_Identity_Array_Runtime (Unit, Document, Info) then
         return "Safe_Array_Identity_RT";
      end if;
      return "Safe_Array_RT";
   end Array_Runtime_Generic_Name;

   function Array_Runtime_Identity_Ops_Name
     (Info : GM.Type_Descriptor) return String is
   begin
      return Array_Runtime_Instance_Name (Info) & "_Element_Ops";
   end Array_Runtime_Identity_Ops_Name;

   function Tuple_Field_Name (Index : Positive) return String is
   begin
      return "F" & Ada.Strings.Fixed.Trim (Positive'Image (Index), Ada.Strings.Both);
   end Tuple_Field_Name;

   function Expr_Type_Info
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access) return GM.Type_Descriptor
   is
      Found_Synthetic : Boolean := False;
   begin
      if Expr = null or else not Has_Text (Expr.Type_Name) then
         return (others => <>);
      elsif Has_Type (Unit, Document, FT.To_String (Expr.Type_Name)) then
         return
           Preferred_Imported_Synthetic_Type
             (Unit,
              Lookup_Type (Unit, Document, FT.To_String (Expr.Type_Name)));
      elsif FT.Lowercase (FT.To_String (Expr.Type_Name)) = "string" then
         return BT.String_Type;
      elsif FT.Lowercase (FT.To_String (Expr.Type_Name)) = "boolean" then
         return BT.Boolean_Type;
      elsif FT.Lowercase (FT.To_String (Expr.Type_Name)) = "integer" then
         return BT.Integer_Type;
      else
         return Synthetic_Bounded_String_Type (FT.To_String (Expr.Type_Name), Found_Synthetic);
      end if;
   end Expr_Type_Info;

   function Try_Static_Integer_Value
     (Expr  : CM.Expr_Access;
      Value : out Long_Long_Integer) return Boolean
   is
      Inner_Value : Long_Long_Integer := 0;
   begin
      Value := 0;
      if Expr = null then
         return False;
      end if;

      case Expr.Kind is
         when CM.Expr_Int =>
            Value := Long_Long_Integer (Expr.Int_Value);
            return True;
         when CM.Expr_Unary =>
            if Expr.Inner = null
              or else not Try_Static_Integer_Value (Expr.Inner, Inner_Value)
            then
               return False;
            elsif FT.To_String (Expr.Operator) = "-" then
               Value := -Inner_Value;
               return True;
            elsif FT.To_String (Expr.Operator) = "+" then
               Value := Inner_Value;
               return True;
            end if;
         when others =>
            null;
      end case;

      return False;
   end Try_Static_Integer_Value;

   function Try_Static_String_Literal
     (Expr   : CM.Expr_Access;
      Image  : out SU.Unbounded_String;
      Length : out Natural) return Boolean
   is
      Literal : constant String :=
        (if Expr /= null and then Has_Text (Expr.Text)
         then FT.To_String (Expr.Text)
         else "");
      Index   : Positive;
   begin
      Image := SU.Null_Unbounded_String;
      Length := 0;
      if Expr = null
        or else Expr.Kind /= CM.Expr_String
        or else not Has_Text (Expr.Text)
        or else Literal'Length < 2
        or else Literal (Literal'First) /= '"'
        or else Literal (Literal'Last) /= '"'
      then
         return False;
      end if;

      Image := SU.To_Unbounded_String (Literal);
      Index := Literal'First + 1;
      while Index < Literal'Last loop
         if Literal (Index) = '"' then
            if Index + 1 <= Literal'Last - 1
              and then Literal (Index + 1) = '"'
            then
               Length := Length + 1;
               Index := Index + 2;
            else
               Image := SU.Null_Unbounded_String;
               Length := 0;
               return False;
            end if;
         else
            Length := Length + 1;
            Index := Index + 1;
         end if;
      end loop;

      return True;
   end Try_Static_String_Literal;

   function Static_String_Literal_Element_Image
     (Image    : String;
      Position : Positive) return String
   is
      Cursor        : Positive := Image'First + 1;
      Element_Index : Positive := 1;
   begin
      while Cursor < Image'Last loop
         declare
            Result : SU.Unbounded_String := SU.To_Unbounded_String (String'(1 => '"'));
         begin
            if Image (Cursor) = '"'
              and then Cursor + 1 <= Image'Last - 1
              and then Image (Cursor + 1) = '"'
            then
               Result := Result & SU.To_Unbounded_String (String'(1 => '"', 2 => '"'));
               if Element_Index = Position then
                  return SU.To_String (Result & SU.To_Unbounded_String (String'(1 => '"')));
               end if;
               Cursor := Cursor + 2;
            else
               Result := Result & SU.To_Unbounded_String (String'(1 => Image (Cursor)));
               if Element_Index = Position then
                  return SU.To_String (Result & SU.To_Unbounded_String (String'(1 => '"')));
               end if;
               Cursor := Cursor + 1;
            end if;
            Element_Index := Element_Index + 1;
         end;
      end loop;

      return String'(1 => '"', 2 => '"');
   end Static_String_Literal_Element_Image;

   function Try_Static_String_Image
     (State : Emit_State;
      Expr  : CM.Expr_Access;
      Image : out SU.Unbounded_String) return Boolean
   is
      Length : Natural := 0;
   begin
      Image := SU.Null_Unbounded_String;
      if Expr = null then
         return False;
      elsif Try_Static_String_Literal (Expr, Image, Length) then
         return True;
      elsif Expr.Kind = CM.Expr_Ident then
         return Try_Static_String_Binding (State, FT.To_String (Expr.Name), Image);
      elsif Expr.Kind = CM.Expr_Conversion and then Expr.Inner /= null then
         return Try_Static_String_Image (State, Expr.Inner, Image);
      end if;

      return False;
   end Try_Static_String_Image;

   function Try_Static_Boolean_Value
     (State : Emit_State;
      Expr  : CM.Expr_Access;
      Value : out Boolean) return Boolean
   is
      Left_Bool    : Boolean := False;
      Right_Bool   : Boolean := False;
      Left_Int     : Long_Long_Integer := 0;
      Right_Int    : Long_Long_Integer := 0;
      Left_String  : SU.Unbounded_String := SU.Null_Unbounded_String;
      Right_String : SU.Unbounded_String := SU.Null_Unbounded_String;
      Operator     : constant String :=
        (if Expr = null then ""
         elsif FT.To_String (Expr.Operator) = "==" then "="
         elsif FT.To_String (Expr.Operator) = "!=" then "/="
         else FT.To_String (Expr.Operator));
   begin
      Value := False;
      if Expr = null then
         return False;
      end if;

      case Expr.Kind is
         when CM.Expr_Bool =>
            Value := Expr.Bool_Value;
            return True;
         when CM.Expr_Unary =>
            if Operator = "not"
              and then Expr.Inner /= null
              and then Try_Static_Boolean_Value (State, Expr.Inner, Left_Bool)
            then
               Value := not Left_Bool;
               return True;
            end if;
         when CM.Expr_Binary =>
            if Operator in "and" | "and then" | "or" | "or else"
              and then Expr.Left /= null
              and then Expr.Right /= null
              and then Try_Static_Boolean_Value (State, Expr.Left, Left_Bool)
              and then Try_Static_Boolean_Value (State, Expr.Right, Right_Bool)
            then
               if Operator in "and" | "and then" then
                  Value := Left_Bool and then Right_Bool;
               else
                  Value := Left_Bool or else Right_Bool;
               end if;
               return True;
            elsif Operator in "=" | "/=" | "<" | "<=" | ">" | ">="
              and then Expr.Left /= null
              and then Expr.Right /= null
            then
               if Try_Static_String_Image (State, Expr.Left, Left_String)
                 and then Try_Static_String_Image (State, Expr.Right, Right_String)
               then
                  declare
                     function Normalize_Static_String (Image : String) return String is
                     begin
                        if Image'Length > 8
                          and then Image (Image'First .. Image'First + 7) = "String'("
                          and then Image (Image'Last) = ')'
                        then
                           return Image (Image'First + 7 .. Image'Last - 1);
                        end if;
                        return Image;
                     end Normalize_Static_String;

                     Left_Image  : constant String :=
                       Normalize_Static_String (SU.To_String (Left_String));
                     Right_Image : constant String :=
                       Normalize_Static_String (SU.To_String (Right_String));
                  begin
                     if Operator = "=" then
                        Value := Left_Image = Right_Image;
                     elsif Operator = "/=" then
                        Value := Left_Image /= Right_Image;
                     elsif Operator = "<" then
                        Value := Left_Image < Right_Image;
                     elsif Operator = "<=" then
                        Value := Left_Image <= Right_Image;
                     elsif Operator = ">" then
                        Value := Left_Image > Right_Image;
                     else
                        Value := Left_Image >= Right_Image;
                     end if;
                     return True;
                  end;
               elsif Try_Tracked_Static_Integer_Value (State, Expr.Left, Left_Int)
                 and then Try_Tracked_Static_Integer_Value (State, Expr.Right, Right_Int)
               then
                  if Operator = "=" then
                     Value := Left_Int = Right_Int;
                  elsif Operator = "/=" then
                     Value := Left_Int /= Right_Int;
                  elsif Operator = "<" then
                     Value := Left_Int < Right_Int;
                  elsif Operator = "<=" then
                     Value := Left_Int <= Right_Int;
                  elsif Operator = ">" then
                     Value := Left_Int > Right_Int;
                  else
                     Value := Left_Int >= Right_Int;
                  end if;
                  return True;
               end if;
            end if;
         when others =>
            null;
      end case;

      return False;
   end Try_Static_Boolean_Value;

   function Static_Element_Binding_Name
     (Name     : String;
      Position : Positive) return String is
   begin
      return Name & "(" & Trim_Image (Long_Long_Integer (Position)) & ")";
   end Static_Element_Binding_Name;

   function Try_Tracked_Static_Integer_Value
     (State : Emit_State;
      Expr  : CM.Expr_Access;
      Value : out Long_Long_Integer) return Boolean
   is
      Left_Value   : Long_Long_Integer := 0;
      Right_Value  : Long_Long_Integer := 0;
      Inner_Value  : Long_Long_Integer := 0;
      Static_Length : Natural := 0;
      Callee_Flat  : constant String :=
        (if Expr = null then "" else CM.Flatten_Name (Expr.Callee));
      Lower_Callee : constant String := FT.Lowercase (Callee_Flat);
      Raw_Operator : constant String :=
        (if Expr = null then "" else FT.To_String (Expr.Operator));
      Operator     : constant String :=
        (if Raw_Operator = "!=" then "/="
         elsif Raw_Operator = "==" then "="
         else Raw_Operator);
   begin
      Value := 0;
      if Expr = null then
         return False;
      end if;

      if Try_Static_Integer_Value (Expr, Value) then
         return True;
      end if;

      case Expr.Kind is
         when CM.Expr_Ident =>
            return Try_Static_Integer_Binding (State, FT.To_String (Expr.Name), Value);
         when CM.Expr_Select =>
            if FT.To_String (Expr.Selector) = "length"
              and then Expr.Prefix /= null
              and then Expr.Prefix.Kind = CM.Expr_Ident
              and then Try_Static_Length
                (State,
                 FT.To_String (Expr.Prefix.Name),
                 Static_Length)
            then
               Value := Long_Long_Integer (Static_Length);
               return True;
            end if;
         when CM.Expr_Resolved_Index =>
            if Expr.Prefix /= null
              and then Expr.Prefix.Kind in CM.Expr_Ident | CM.Expr_Select
              and then Natural (Expr.Args.Length) = 1
              and then Try_Tracked_Static_Integer_Value
                (State,
                 Expr.Args (Expr.Args.First_Index),
                 Inner_Value)
              and then Inner_Value >= 1
              and then Inner_Value <= Long_Long_Integer (Natural'Last)
              and then Try_Static_Integer_Binding
                (State,
                 Static_Element_Binding_Name
                   ((if Expr.Prefix.Kind = CM.Expr_Ident
                     then FT.To_String (Expr.Prefix.Name)
                     else CM.Flatten_Name (Expr.Prefix)),
                    Positive (Natural (Inner_Value))),
                 Value)
            then
               return True;
            end if;
         when CM.Expr_Call =>
            if Natural (Expr.Args.Length) = 1
              and then Lower_Callee'Length >= 7
              and then Lower_Callee (Lower_Callee'Last - 6 .. Lower_Callee'Last) = ".length"
              and then Expr.Args (Expr.Args.First_Index) /= null
              and then Expr.Args (Expr.Args.First_Index).Kind = CM.Expr_Ident
              and then Try_Static_Length
                (State,
                 FT.To_String (Expr.Args (Expr.Args.First_Index).Name),
                 Static_Length)
            then
               Value := Long_Long_Integer (Static_Length);
               return True;
            end if;
         when CM.Expr_Unary =>
            if Expr.Inner /= null
              and then Try_Tracked_Static_Integer_Value (State, Expr.Inner, Inner_Value)
            then
               if Operator = "-" then
                  Value := -Inner_Value;
                  return True;
               elsif Operator = "+" then
                  Value := Inner_Value;
                  return True;
               end if;
            end if;
         when CM.Expr_Binary =>
            if Expr.Left /= null
              and then Expr.Right /= null
              and then Try_Tracked_Static_Integer_Value (State, Expr.Left, Left_Value)
              and then Try_Tracked_Static_Integer_Value (State, Expr.Right, Right_Value)
            then
               if Operator = "+" then
                  Value := Left_Value + Right_Value;
                  return True;
               elsif Operator = "-" then
                  Value := Left_Value - Right_Value;
                  return True;
               elsif Operator = "*" then
                  Value := Left_Value * Right_Value;
                  return True;
               end if;
            end if;
         when CM.Expr_Conversion =>
            if Expr.Inner /= null
              and then Try_Tracked_Static_Integer_Value (State, Expr.Inner, Inner_Value)
            then
               Value := Inner_Value;
               return True;
            end if;
         when others =>
            null;
      end case;

      return False;
   end Try_Tracked_Static_Integer_Value;

   function Try_Static_String_Binding
     (State : Emit_State;
      Name  : String;
      Image : out SU.Unbounded_String) return Boolean renames AI.Try_Static_String_Binding;

   procedure Restore_Static_String_Bindings
     (State           : in out Emit_State;
      Previous_Length : Ada.Containers.Count_Type) renames AI.Restore_Static_String_Bindings;

   procedure Clear_All_Static_Bindings (State : in out Emit_State) renames AI.Clear_All_Static_Bindings;

   function Try_Object_Static_String_Initializer
     (Unit   : CM.Resolved_Unit;
      Name   : String;
      Image  : out SU.Unbounded_String;
      Length : out Natural) return Boolean is
   begin
      Image := SU.Null_Unbounded_String;
      Length := 0;
      if Name'Length = 0 or else Unit.Objects.Is_Empty then
         return False;
      end if;

      for Decl of Unit.Objects loop
         if Decl.Has_Initializer and then Decl.Initializer /= null then
            for Decl_Name of Decl.Names loop
               if FT.To_String (Decl_Name) = Name
                 and then Try_Static_String_Literal
                   (Decl.Initializer,
                    Image,
                    Length)
               then
                  return True;
               end if;
            end loop;
         end if;
      end loop;

      return False;
   end Try_Object_Static_String_Initializer;

   function Try_Object_Static_Integer_Initializer
     (Unit  : CM.Resolved_Unit;
      Name  : String;
      Value : out Long_Long_Integer) return Boolean is
   begin
      Value := 0;
      if Name'Length = 0 or else Unit.Objects.Is_Empty then
         return False;
      end if;

      for Decl of Unit.Objects loop
         if Decl.Has_Initializer and then Decl.Initializer /= null then
            for Decl_Name of Decl.Names loop
               if FT.To_String (Decl_Name) = Name
                 and then Try_Static_Integer_Value (Decl.Initializer, Value)
               then
                  return True;
               end if;
            end loop;
         end if;
      end loop;

      return False;
   end Try_Object_Static_Integer_Initializer;

   function Try_Static_Integer_Array_Element_Expr
     (Unit     : CM.Resolved_Unit;
      Expr     : CM.Expr_Access;
      Position : Positive;
      Value    : out Long_Long_Integer) return Boolean
   is
      Name_Text : constant String :=
        (if Expr = null then ""
         elsif Expr.Kind = CM.Expr_Ident then FT.To_String (Expr.Name)
         elsif Expr.Kind = CM.Expr_Select then CM.Flatten_Name (Expr)
         else "");
   begin
      Value := 0;
      if Expr = null then
         return False;
      elsif Expr.Kind in CM.Expr_Array_Literal | CM.Expr_Tuple then
         declare
            Current_Position : Positive := 1;
         begin
            for Element_Index in Expr.Elements.First_Index .. Expr.Elements.Last_Index loop
               if Current_Position = Position then
                  if Expr.Elements (Element_Index) = null then
                     return False;
                  end if;
                  return Try_Static_Integer_Value
                    (Expr.Elements (Element_Index), Value);
               end if;
               if Current_Position < Positive'Last then
                  Current_Position := Current_Position + 1;
               end if;
            end loop;
            return False;
         end;
      elsif Expr.Kind in CM.Expr_Ident | CM.Expr_Select then
         if Name_Text'Length = 0 or else Unit.Objects.Is_Empty then
            return False;
         end if;
         for Decl of Unit.Objects loop
            if Decl.Has_Initializer and then Decl.Initializer /= null then
               for Decl_Name of Decl.Names loop
                  if FT.To_String (Decl_Name) = Name_Text
                    and then Try_Static_Integer_Array_Element_Expr
                      (Unit,
                       Decl.Initializer,
                       Position,
                       Value)
                  then
                     return True;
                  end if;
               end loop;
            end if;
         end loop;
      elsif Expr.Kind = CM.Expr_Call and then Expr.Callee /= null then
         declare
            Called_Name : constant String := FT.Lowercase (CM.Flatten_Name (Expr.Callee));
            Return_Stmt : CM.Statement_Access := null;
         begin
            for Subprogram of Unit.Subprograms loop
               declare
                  Candidate_Name : constant String := FT.Lowercase (FT.To_String (Subprogram.Name));
                  Qualified_Name : constant String :=
                    FT.Lowercase (FT.To_String (Unit.Package_Name) & "." & FT.To_String (Subprogram.Name));
               begin
                  if (Called_Name = Candidate_Name or else Called_Name = Qualified_Name)
                    and then Subprogram.Params.Length = 1
                    and then Expr.Args.Length = 1
                    and then Subprogram.Statements.Length = 1
                  then
                     Return_Stmt := Subprogram.Statements (Subprogram.Statements.First_Index);
                     if Return_Stmt /= null
                       and then Return_Stmt.Kind = CM.Stmt_Return
                       and then Return_Stmt.Value /= null
                       and then Return_Stmt.Value.Kind = CM.Expr_Ident
                       and then FT.To_String (Return_Stmt.Value.Name) = FT.To_String (Subprogram.Params (Subprogram.Params.First_Index).Name)
                     then
                        return Try_Static_Integer_Array_Element_Expr
                          (Unit,
                           Expr.Args (Expr.Args.First_Index),
                           Position,
                           Value);
                     end if;
                  end if;
               end;
            end loop;
         end;
      end if;
      return False;
   end Try_Static_Integer_Array_Element_Expr;

   function Try_Static_Array_Length_From_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      Length   : out Natural) return Boolean
   is
      Name_Text : constant String :=
        (if Expr = null then ""
         elsif Expr.Kind = CM.Expr_Ident then FT.To_String (Expr.Name)
         elsif Expr.Kind = CM.Expr_Select then CM.Flatten_Name (Expr)
         else "");
   begin
      Length := 0;
      if Expr = null then
         return False;
      elsif Static_Growable_Length (Expr, Length) then
         return True;
      elsif Expr.Kind in CM.Expr_Ident | CM.Expr_Select then
         if Name_Text'Length = 0 or else Unit.Objects.Is_Empty then
            return False;
         end if;
         for Decl of Unit.Objects loop
            if Decl.Has_Initializer and then Decl.Initializer /= null then
               for Decl_Name of Decl.Names loop
                  if FT.To_String (Decl_Name) = Name_Text
                    and then Try_Static_Array_Length_From_Expr
                      (Unit,
                       Document,
                       Decl.Initializer,
                       Length)
                  then
                     return True;
                  end if;
               end loop;
            end if;
         end loop;
      elsif Expr.Kind = CM.Expr_Call and then Expr.Callee /= null then
         declare
            Called_Name : constant String := FT.Lowercase (CM.Flatten_Name (Expr.Callee));
            Return_Stmt : CM.Statement_Access := null;
         begin
            for Subprogram of Unit.Subprograms loop
               declare
                  Candidate_Name : constant String := FT.Lowercase (FT.To_String (Subprogram.Name));
                  Qualified_Name : constant String :=
                    FT.Lowercase (FT.To_String (Unit.Package_Name) & "." & FT.To_String (Subprogram.Name));
               begin
                  if (Called_Name = Candidate_Name or else Called_Name = Qualified_Name)
                    and then Subprogram.Params.Length = 1
                    and then Expr.Args.Length = 1
                    and then Subprogram.Statements.Length = 1
                  then
                     Return_Stmt := Subprogram.Statements (Subprogram.Statements.First_Index);
                     if Return_Stmt /= null
                       and then Return_Stmt.Kind = CM.Stmt_Return
                       and then Return_Stmt.Value /= null
                       and then Return_Stmt.Value.Kind = CM.Expr_Ident
                       and then FT.To_String (Return_Stmt.Value.Name) = FT.To_String (Subprogram.Params (Subprogram.Params.First_Index).Name)
                     then
                        return Try_Static_Array_Length_From_Expr
                          (Unit,
                           Document,
                           Expr.Args (Expr.Args.First_Index),
                           Length);
                     end if;
                  end if;
               end;
            end loop;
         end;
      end if;
      return False;
   end Try_Static_Array_Length_From_Expr;

   function Try_Resolved_Static_Integer_Value
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      State    : Emit_State;
      Expr     : CM.Expr_Access;
      Value    : out Long_Long_Integer) return Boolean
   is
      Left_Value  : Long_Long_Integer := 0;
      Right_Value : Long_Long_Integer := 0;
      Inner_Value : Long_Long_Integer := 0;
      Operator    : constant String :=
        (if Expr = null then ""
         elsif FT.To_String (Expr.Operator) = "==" then "="
         elsif FT.To_String (Expr.Operator) = "!=" then "/="
         else FT.To_String (Expr.Operator));

      function Try_Static_Integer_Call_Value
        (Call_Expr : CM.Expr_Access;
         Result    : out Long_Long_Integer) return Boolean
      is
         Called_Name : constant String :=
           (if Call_Expr = null or else Call_Expr.Callee = null
            then ""
            else FT.Lowercase (CM.Flatten_Name (Call_Expr.Callee)));

         function Try_With_Param
           (Return_Expr : CM.Expr_Access;
            Param_Name  : String;
            Arg_Expr    : CM.Expr_Access;
            Static_Result : out Long_Long_Integer) return Boolean
         is
            Left_Param  : Long_Long_Integer := 0;
            Right_Param : Long_Long_Integer := 0;
            Inner_Param : Long_Long_Integer := 0;
            Param_Op    : constant String :=
              (if Return_Expr = null then ""
               elsif FT.To_String (Return_Expr.Operator) = "==" then "="
               elsif FT.To_String (Return_Expr.Operator) = "!=" then "/="
               else FT.To_String (Return_Expr.Operator));
         begin
            Static_Result := 0;
            if Return_Expr = null then
               return False;
            elsif Try_Tracked_Static_Integer_Value (State, Return_Expr, Static_Result) then
               return True;
            end if;

            case Return_Expr.Kind is
               when CM.Expr_Ident =>
                  if FT.To_String (Return_Expr.Name) = Param_Name then
                     return Try_Resolved_Static_Integer_Value
                       (Unit, Document, State, Arg_Expr, Static_Result);
                  end if;
               when CM.Expr_Resolved_Index =>
                  if Return_Expr.Prefix /= null
                    and then Return_Expr.Prefix.Kind = CM.Expr_Ident
                    and then FT.To_String (Return_Expr.Prefix.Name) = Param_Name
                    and then Natural (Return_Expr.Args.Length) = 1
                    and then Try_Resolved_Static_Integer_Value
                      (Unit,
                       Document,
                       State,
                       Return_Expr.Args (Return_Expr.Args.First_Index),
                       Inner_Param)
                    and then Inner_Param >= 1
                    and then Inner_Param <= Long_Long_Integer (Positive'Last)
                  then
                     return Try_Static_Integer_Array_Element_Expr
                       (Unit,
                        Arg_Expr,
                        Positive (Natural (Inner_Param)),
                        Static_Result);
                  end if;
               when CM.Expr_Unary =>
                  if Return_Expr.Inner /= null
                    and then Try_With_Param
                      (Return_Expr.Inner,
                       Param_Name,
                       Arg_Expr,
                       Inner_Param)
                  then
                     if Param_Op = "-" then
                        Static_Result := -Inner_Param;
                        return True;
                     elsif Param_Op = "+" then
                        Static_Result := Inner_Param;
                        return True;
                     end if;
                  end if;
               when CM.Expr_Binary =>
                  if Return_Expr.Left /= null
                    and then Return_Expr.Right /= null
                    and then Try_With_Param
                      (Return_Expr.Left,
                       Param_Name,
                       Arg_Expr,
                       Left_Param)
                    and then Try_With_Param
                      (Return_Expr.Right,
                       Param_Name,
                       Arg_Expr,
                       Right_Param)
                  then
                     if Param_Op = "+" then
                        Static_Result := Left_Param + Right_Param;
                        return True;
                     elsif Param_Op = "-" then
                        Static_Result := Left_Param - Right_Param;
                        return True;
                     elsif Param_Op = "*" then
                        Static_Result := Left_Param * Right_Param;
                        return True;
                     end if;
                  end if;
               when CM.Expr_Conversion =>
                  if Return_Expr.Inner /= null then
                     return Try_With_Param
                       (Return_Expr.Inner,
                        Param_Name,
                        Arg_Expr,
                        Static_Result);
                  end if;
               when others =>
                  null;
            end case;

            return False;
         end Try_With_Param;
      begin
         Result := 0;
         if Call_Expr = null
           or else Call_Expr.Callee = null
           or else Unit.Subprograms.Is_Empty
         then
            return False;
         end if;

         for Subprogram of Unit.Subprograms loop
            declare
               Candidate_Name : constant String := FT.Lowercase (FT.To_String (Subprogram.Name));
               Qualified_Name : constant String :=
                 FT.Lowercase (FT.To_String (Unit.Package_Name) & "." & FT.To_String (Subprogram.Name));
               Return_Stmt : CM.Statement_Access := null;
            begin
               if (Called_Name = Candidate_Name or else Called_Name = Qualified_Name)
                 and then Subprogram.Params.Length = 1
                 and then Call_Expr.Args.Length = 1
                 and then Subprogram.Statements.Length = 1
               then
                  Return_Stmt := Subprogram.Statements (Subprogram.Statements.First_Index);
                  if Return_Stmt /= null
                    and then Return_Stmt.Kind = CM.Stmt_Return
                    and then Return_Stmt.Value /= null
                    and then Try_With_Param
                      (Return_Stmt.Value,
                       FT.To_String (Subprogram.Params (Subprogram.Params.First_Index).Name),
                       Call_Expr.Args (Call_Expr.Args.First_Index),
                       Result)
                  then
                     return True;
                  end if;
               end if;
            end;
         end loop;

         return False;
      end Try_Static_Integer_Call_Value;
   begin
      Value := 0;
      if Expr = null then
         return False;
      elsif Try_Tracked_Static_Integer_Value (State, Expr, Value) then
         return True;
      end if;

      case Expr.Kind is
         when CM.Expr_Resolved_Index =>
            if Expr.Prefix /= null
              and then Natural (Expr.Args.Length) = 1
              and then Try_Resolved_Static_Integer_Value
                (Unit,
                 Document,
                 State,
                 Expr.Args (Expr.Args.First_Index),
                 Inner_Value)
              and then Inner_Value >= 1
              and then Inner_Value <= Long_Long_Integer (Positive'Last)
            then
               declare
                  Position  : constant Positive := Positive (Natural (Inner_Value));
                  Name_Text : constant String :=
                    (if Expr.Prefix.Kind = CM.Expr_Ident
                     then FT.To_String (Expr.Prefix.Name)
                     elsif Expr.Prefix.Kind = CM.Expr_Select
                     then CM.Flatten_Name (Expr.Prefix)
                     else "");
               begin
                  if Name_Text'Length /= 0
                    and then Try_Static_Integer_Binding
                      (State,
                       Static_Element_Binding_Name (Name_Text, Position),
                       Value)
                  then
                     return True;
                  end if;

                  return Try_Static_Integer_Array_Element_Expr
                    (Unit,
                     Expr.Prefix,
                     Position,
                     Value);
               end;
            end if;
         when CM.Expr_Call =>
            return Try_Static_Integer_Call_Value (Expr, Value);
         when CM.Expr_Unary =>
            if Expr.Inner /= null
              and then Try_Resolved_Static_Integer_Value
                (Unit, Document, State, Expr.Inner, Inner_Value)
            then
               if Operator = "-" then
                  Value := -Inner_Value;
                  return True;
               elsif Operator = "+" then
                  Value := Inner_Value;
                  return True;
               end if;
            end if;
         when CM.Expr_Binary =>
            if Expr.Left /= null
              and then Expr.Right /= null
              and then Try_Resolved_Static_Integer_Value
                (Unit, Document, State, Expr.Left, Left_Value)
              and then Try_Resolved_Static_Integer_Value
                (Unit, Document, State, Expr.Right, Right_Value)
            then
               if Operator = "+" then
                  Value := Left_Value + Right_Value;
                  return True;
               elsif Operator = "-" then
                  Value := Left_Value - Right_Value;
                  return True;
               elsif Operator = "*" then
                  Value := Left_Value * Right_Value;
                  return True;
               end if;
            end if;
         when CM.Expr_Conversion =>
            if Expr.Inner /= null then
               return Try_Resolved_Static_Integer_Value
                 (Unit, Document, State, Expr.Inner, Value);
            end if;
         when others =>
            null;
      end case;

      return False;
   end Try_Resolved_Static_Integer_Value;

   function Fixed_Array_Cardinality
     (Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      Target_Info : GM.Type_Descriptor;
      Cardinality : out Natural) return Boolean
   is
      Base       : constant GM.Type_Descriptor := Base_Type (Unit, Document, Target_Info);
      Index_Info : GM.Type_Descriptor := (others => <>);
      Width      : Long_Long_Integer := 0;
   begin
      Cardinality := 0;
      if FT.Lowercase (FT.To_String (Base.Kind)) /= "array"
        or else Base.Growable
        or else Natural (Base.Index_Types.Length) /= 1
      then
         return False;
      end if;

      Index_Info :=
        Resolve_Type_Name
          (Unit,
           Document,
           FT.To_String (Base.Index_Types (Base.Index_Types.First_Index)));
      if not Index_Info.Has_Low or else not Index_Info.Has_High then
         Index_Info := Base_Type (Unit, Document, Index_Info);
         if not Index_Info.Has_Low or else not Index_Info.Has_High then
            return False;
         end if;
      end if;

      Width := Index_Info.High - Index_Info.Low + 1;
      if Width < 0 or else Width > Long_Long_Integer (Natural'Last) then
         return False;
      end if;

      Cardinality := Natural (Width);
      return True;
   end Fixed_Array_Cardinality;

   function Static_Growable_Length
     (Expr   : CM.Expr_Access;
      Length : out Natural) return Boolean
   is
      Low_Value  : Long_Long_Integer := 0;
      High_Value : Long_Long_Integer := 0;
      Width      : Long_Long_Integer := 0;
   begin
      Length := 0;
      if Expr = null then
         return False;
      elsif Expr.Kind in CM.Expr_Array_Literal | CM.Expr_Tuple then
         Length := Natural (Expr.Elements.Length);
         return True;
      elsif Expr.Kind = CM.Expr_Resolved_Index
        and then Expr.Prefix /= null
        and then Expr.Prefix.Kind in CM.Expr_Ident | CM.Expr_Select
        and then Natural (Expr.Args.Length) = 2
        and then Try_Static_Integer_Value
          (Expr.Args (Expr.Args.First_Index),
           Low_Value)
        and then Try_Static_Integer_Value
          (Expr.Args (Expr.Args.First_Index + 1),
           High_Value)
      then
         if High_Value < Low_Value then
            return False;
         end if;
         Width := High_Value - Low_Value + 1;
         if Width < 0 or else Width > Long_Long_Integer (Natural'Last) then
            return False;
         end if;
         Length := Natural (Width);
         return True;
      end if;

      return False;
   end Static_Growable_Length;

   function Render_Fixed_Array_As_Growable
     (Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      Expr        : CM.Expr_Access;
      Target_Info : GM.Type_Descriptor;
      State       : in out Emit_State) return String
   is
      Runtime_Name : constant String := Array_Runtime_Instance_Name (Target_Info);
      Literal_Image : SU.Unbounded_String;
      Component_Info : constant GM.Type_Descriptor :=
        Resolve_Type_Name (Unit, Document, FT.To_String (Target_Info.Component_Type));
   begin
      State.Needs_Safe_Array_RT := True;

      if Expr /= null and then Expr.Kind in CM.Expr_Array_Literal | CM.Expr_Tuple then
         Literal_Image := SU.To_Unbounded_String ("(");
         for Index in Expr.Elements.First_Index .. Expr.Elements.Last_Index loop
            if Index /= Expr.Elements.First_Index then
               Literal_Image := Literal_Image & SU.To_Unbounded_String (", ");
            end if;
            Literal_Image :=
              Literal_Image
              & SU.To_Unbounded_String
                  (Render_Expr_For_Target_Type
                     (Unit,
                      Document,
                      Expr.Elements (Index),
                      Component_Info,
                      State));
         end loop;
         Literal_Image := Literal_Image & SU.To_Unbounded_String (")");
         return
           Runtime_Name
           & ".From_Array ("
           & Runtime_Name
           & ".Element_Array'"
           & SU.To_String (Literal_Image)
           & ")";
      end if;

      return
        Runtime_Name
        & ".From_Array ("
        & Runtime_Name
        & ".Element_Array ("
        & Render_Expr (Unit, Document, Expr, State)
        & "))";
   end Render_Fixed_Array_As_Growable;

   function Render_Growable_As_Fixed
     (Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      Expr        : CM.Expr_Access;
      Target_Info : GM.Type_Descriptor;
      State       : in out Emit_State) return String
   is
      Cardinality    : Natural := 0;
      Element_Count  : Natural := 0;
      Component_Info : constant GM.Type_Descriptor :=
        Resolve_Type_Name (Unit, Document, FT.To_String (Target_Info.Component_Type));
      Slice_Source_Info : GM.Type_Descriptor := (others => <>);
      Result         : SU.Unbounded_String := SU.To_Unbounded_String ("(");
      Low_Value      : Long_Long_Integer := 0;
      High_Value     : Long_Long_Integer := 0;
   begin
      if not Fixed_Array_Cardinality (Unit, Document, Target_Info, Cardinality) then
         Raise_Unsupported
           (State,
            (if Expr = null then FT.Null_Span else Expr.Span),
            "growable-to-fixed conversion requires a statically exact array length");
      end if;

      if Expr.Kind = CM.Expr_Array_Literal then
         if not Static_Growable_Length (Expr, Element_Count)
           or else Cardinality /= Element_Count
         then
            Raise_Unsupported
              (State,
               Expr.Span,
               "growable-to-fixed conversion requires a statically exact array length");
         end if;

         for Index in Expr.Elements.First_Index .. Expr.Elements.Last_Index loop
            if Index /= Expr.Elements.First_Index then
               Result := Result & SU.To_Unbounded_String (", ");
            end if;
            Result :=
              Result
              & SU.To_Unbounded_String
                  (Render_Expr_For_Target_Type
                     (Unit,
                      Document,
                      Expr.Elements (Index),
                      Component_Info,
                      State));
         end loop;
      elsif Expr.Kind in CM.Expr_Ident | CM.Expr_Select then
         Slice_Source_Info :=
           Base_Type
             (Unit,
              Document,
              Expr_Type_Info (Unit, Document, Expr));
         if not Is_Growable_Array_Type (Unit, Document, Slice_Source_Info) then
            declare
               Resolved_Source_Info : GM.Type_Descriptor := (others => <>);
            begin
               if Expr.Kind = CM.Expr_Ident
                 and then Lookup_Mir_Local_Type
                   (Document,
                    FT.To_String (Expr.Name),
                    Expr.Span,
                    Resolved_Source_Info)
               then
                  Slice_Source_Info :=
                    Base_Type (Unit, Document, Resolved_Source_Info);
               elsif Resolve_Print_Type (Unit, Document, Expr, State, Resolved_Source_Info) then
                  Slice_Source_Info :=
                    Base_Type (Unit, Document, Resolved_Source_Info);
               else
                  return Render_Expr (Unit, Document, Expr, State);
               end if;
            end;
         end if;
         if not Is_Growable_Array_Type (Unit, Document, Slice_Source_Info) then
            return Render_Expr (Unit, Document, Expr, State);
         end if;

         for Offset in 0 .. Cardinality - 1 loop
            declare
               Index_Expr  : constant CM.Expr_Access :=
                 new CM.Expr_Node'
                   (Kind      => CM.Expr_Int,
                    Span      => Expr.Span,
                    Type_Name => FT.To_UString ("integer"),
                    Int_Value => CM.Wide_Integer (Offset + 1),
                    others    => <>);
            begin
               if Offset /= 0 then
                  Result := Result & SU.To_Unbounded_String (", ");
               end if;
               Result :=
                 Result
                 & SU.To_Unbounded_String
                     (Array_Runtime_Instance_Name (Slice_Source_Info)
                      & ".Element ("
                      & Render_Expr (Unit, Document, Expr, State)
                      & ", "
                      & Render_Expr (Unit, Document, Index_Expr, State)
                      & ")");
            end;
         end loop;
      elsif Expr.Kind = CM.Expr_Resolved_Index
        and then Expr.Prefix /= null
        and then Expr.Prefix.Kind in CM.Expr_Ident | CM.Expr_Select
        and then Natural (Expr.Args.Length) = 2
        and then Static_Growable_Length (Expr, Element_Count)
        and then Cardinality = Element_Count
        and then Try_Static_Integer_Value
          (Expr.Args (Expr.Args.First_Index),
           Low_Value)
        and then Try_Static_Integer_Value
          (Expr.Args (Expr.Args.First_Index + 1),
           High_Value)
      then
         Slice_Source_Info :=
           Base_Type
             (Unit,
              Document,
              Expr_Type_Info (Unit, Document, Expr.Prefix));
         if not Is_Growable_Array_Type (Unit, Document, Slice_Source_Info) then
            Raise_Unsupported
              (State,
               Expr.Span,
               "static slice conversion requires a growable-array source");
         end if;

         for Offset in 0 .. Cardinality - 1 loop
            declare
               Index_Value : constant Long_Long_Integer := Low_Value + Long_Long_Integer (Offset);
               Index_Expr  : constant CM.Expr_Access :=
                 new CM.Expr_Node'
                   (Kind      => CM.Expr_Int,
                    Span      => Expr.Span,
                    Type_Name => FT.To_UString ("integer"),
                    Int_Value => CM.Wide_Integer (Index_Value),
                    others    => <>);
            begin
               if Offset /= 0 then
                  Result := Result & SU.To_Unbounded_String (", ");
               end if;
               Result :=
                 Result
                 & SU.To_Unbounded_String
                     (Array_Runtime_Instance_Name (Slice_Source_Info)
                      & ".Element ("
                      & Render_Expr (Unit, Document, Expr.Prefix, State)
                      & ", "
                      & Render_Expr (Unit, Document, Index_Expr, State)
                      & ")");
            end;
         end loop;
      else
         Raise_Unsupported
           (State,
            Expr.Span,
            "growable-to-fixed conversion is only supported for bracket literals, guarded object names, and static slices");
      end if;

      Result := Result & SU.To_Unbounded_String (")");
      return SU.To_String (Result);
   end Render_Growable_As_Fixed;

   function Render_Growable_Array_Expr
     (Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      Expr        : CM.Expr_Access;
      Target_Info : GM.Type_Descriptor;
      State       : in out Emit_State) return String
   is
      Array_Info : GM.Type_Descriptor := Base_Type (Unit, Document, Target_Info);
      Source_Info : constant GM.Type_Descriptor :=
        Base_Type (Unit, Document, Expr_Type_Info (Unit, Document, Expr));
      Result     : SU.Unbounded_String;
      function Render_Runtime_Index (Index_Expr : CM.Expr_Access) return String is
      begin
         return "Integer (" & Render_Expr (Unit, Document, Index_Expr, State) & ")";
      end Render_Runtime_Index;
   begin
      if Expr = null then
         Raise_Unsupported
           (State,
            FT.Null_Span,
            "encountered null growable-array expression during Ada emission");
      end if;

      if not Is_Growable_Array_Type (Unit, Document, Array_Info) then
         Array_Info := Base_Type (Unit, Document, Expr_Type_Info (Unit, Document, Expr));
      end if;

      if not Is_Growable_Array_Type (Unit, Document, Array_Info) then
         Raise_Unsupported
           (State,
            Expr.Span,
            "encountered non-growable-array expression in growable-array emission");
      end if;

      State.Needs_Safe_Array_RT := True;

      if Expr.Kind = CM.Expr_Array_Literal then
         if Expr.Elements.Is_Empty then
            return Array_Runtime_Instance_Name (Array_Info) & ".Empty";
         end if;

         Result := SU.To_Unbounded_String ("(");
         for Index in Expr.Elements.First_Index .. Expr.Elements.Last_Index loop
            if Index /= Expr.Elements.First_Index then
               Result := Result & SU.To_Unbounded_String (", ");
            end if;
            if Expr.Elements.Length = 1 then
               Result := Result & SU.To_Unbounded_String ("1 => ");
            end if;
            Result :=
              Result
              & SU.To_Unbounded_String
                  (Render_Expr_For_Target_Type
                     (Unit,
                      Document,
                      Expr.Elements (Index),
                      Resolve_Type_Name
                        (Unit,
                         Document,
                         FT.To_String (Array_Info.Component_Type)),
                      State));
         end loop;
         Result := Result & SU.To_Unbounded_String (")");
         return
           Array_Runtime_Instance_Name (Array_Info)
           & ".From_Array ("
           & SU.To_String (Result)
           & ")";
      elsif Expr.Kind = CM.Expr_Resolved_Index and then Expr.Prefix /= null then
         declare
            Prefix_Info : constant GM.Type_Descriptor :=
              Expr_Type_Info (Unit, Document, Expr.Prefix);
         begin
            if Is_Growable_Array_Type (Unit, Document, Prefix_Info) then
               if Natural (Expr.Args.Length) = 1 then
                  return
                    Array_Runtime_Instance_Name (Prefix_Info)
                    & ".Element ("
                    & Render_Expr (Unit, Document, Expr.Prefix, State)
                    & ", "
                    & Render_Runtime_Index (Expr.Args (Expr.Args.First_Index))
                    & ")";
               elsif Natural (Expr.Args.Length) = 2 then
                  return
                    Array_Runtime_Instance_Name (Prefix_Info)
                    & ".Slice ("
                    & Render_Expr (Unit, Document, Expr.Prefix, State)
                    & ", "
                    & Render_Runtime_Index (Expr.Args (Expr.Args.First_Index))
                    & ", "
                    & Render_Runtime_Index (Expr.Args (Expr.Args.First_Index + 1))
                    & ")";
               end if;
            end if;
         end;
      elsif Expr.Kind = CM.Expr_Binary
        and then FT.To_String (Expr.Operator) = "&"
      then
         return
           Array_Runtime_Instance_Name (Array_Info)
           & ".Concat ("
           & Render_Growable_Array_Expr
               (Unit, Document, Expr.Left, Array_Info, State)
           & ", "
           & Render_Growable_Array_Expr
               (Unit, Document, Expr.Right, Array_Info, State)
           & ")";
      elsif FT.Lowercase (FT.To_String (Source_Info.Kind)) = "array"
        and then not Source_Info.Growable
      then
         return
           Render_Fixed_Array_As_Growable
             (Unit, Document, Expr, Array_Info, State);
      end if;

      return Render_Expr (Unit, Document, Expr, State);
   end Render_Growable_Array_Expr;

   function Render_Heap_String_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String
   is
      Info : GM.Type_Descriptor := Expr_Type_Info (Unit, Document, Expr);
   begin
      State.Needs_Safe_String_RT := True;

      if Expr = null then
         Raise_Unsupported
           (State,
            FT.Null_Span,
            "encountered null heap-string expression during Ada emission");
      elsif Expr.Kind = CM.Expr_String and then Has_Text (Expr.Text) then
         return "Safe_String_RT.From_Literal (" & FT.To_String (Expr.Text) & ")";
      elsif Expr.Kind = CM.Expr_Resolved_Index and then Expr.Prefix /= null then
         declare
            Prefix_Info : constant GM.Type_Descriptor := Expr_Type_Info (Unit, Document, Expr.Prefix);
            Low_Image   : constant String :=
              Render_Expr (Unit, Document, Expr.Args (Expr.Args.First_Index), State);
         begin
            if Is_Plain_String_Type (Unit, Document, Prefix_Info) then
               if Natural (Expr.Args.Length) = 1 then
                  return
                    "Safe_String_RT.Slice ("
                    & Render_Heap_String_Expr (Unit, Document, Expr.Prefix, State)
                    & ", "
                    & Low_Image
                    & ", "
                    & Low_Image
                    & ")";
               end if;
               return
                 "Safe_String_RT.Slice ("
                 & Render_Heap_String_Expr (Unit, Document, Expr.Prefix, State)
                 & ", "
                 & Low_Image
                  & ", "
                  & Render_Expr (Unit, Document, Expr.Args (Expr.Args.First_Index + 1), State)
                  & ")";
            elsif Is_Bounded_String_Type (Prefix_Info) then
               Register_Bounded_String_Type (State, Prefix_Info);
               if Natural (Expr.Args.Length) = 1 then
                  return
                    "Safe_String_RT.From_Literal ("
                    & Bounded_String_Instance_Name (Prefix_Info)
                    & ".Element ("
                    & Render_Expr (Unit, Document, Expr.Prefix, State)
                    & ", "
                    & Low_Image
                    & "))";
               end if;
               return
                 "Safe_String_RT.From_Literal ("
                 & Bounded_String_Instance_Name (Prefix_Info)
                 & ".Slice ("
                 & Render_Expr (Unit, Document, Expr.Prefix, State)
                 & ", "
                 & Low_Image
                 & ", "
                 & Render_Expr (Unit, Document, Expr.Args (Expr.Args.First_Index + 1), State)
                 & "))";
            end if;
         end;
      elsif Expr.Kind = CM.Expr_Binary
        and then FT.To_String (Expr.Operator) = "&"
      then
         return
           "Safe_String_RT.Concat ("
           & Render_Heap_String_Expr (Unit, Document, Expr.Left, State)
           & ", "
           & Render_Heap_String_Expr (Unit, Document, Expr.Right, State)
           & ")";
      end if;

      if not Has_Text (Info.Name) and then not Has_Text (Info.Kind) then
         declare
            Resolved_Info : GM.Type_Descriptor := (others => <>);
         begin
            if Resolve_Print_Type (Unit, Document, Expr, State, Resolved_Info) then
               Info := Resolved_Info;
            end if;
         end;
      end if;

      if Is_Plain_String_Type (Unit, Document, Info) then
         return Render_Expr (Unit, Document, Expr, State);
      elsif Is_Bounded_String_Type (Info) then
         return
           "Safe_String_RT.From_Literal ("
           & Render_String_Expr (Unit, Document, Expr, State)
           & ")";
      end if;

      return
        "Safe_String_RT.From_Literal ("
        & Render_String_Expr (Unit, Document, Expr, State)
        & ")";
   end Render_Heap_String_Expr;

   function Render_Positional_Tuple_Aggregate
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String
   is
      Result         : SU.Unbounded_String := SU.To_Unbounded_String ("(");
      Aggregate_Info : constant GM.Type_Descriptor :=
        Expr_Type_Info (Unit, Document, Expr);
   begin
      if Expr = null then
         return "()";
      end if;

      for Index in Expr.Elements.First_Index .. Expr.Elements.Last_Index loop
         declare
            Target_Info : GM.Type_Descriptor := (others => <>);
            Has_Target  : Boolean := False;
         begin
            if Is_Array_Type (Unit, Document, Aggregate_Info)
              and then Aggregate_Info.Has_Component_Type
            then
               Target_Info :=
                 Resolve_Type_Name
                   (Unit,
                    Document,
                    FT.To_String (Aggregate_Info.Component_Type));
               Has_Target := True;
            elsif Is_Tuple_Type (Aggregate_Info)
              and then Index <= Aggregate_Info.Tuple_Element_Types.Last_Index
            then
               Target_Info :=
                 Resolve_Type_Name
                   (Unit,
                    Document,
                    FT.To_String (Aggregate_Info.Tuple_Element_Types (Index)));
               Has_Target := True;
            elsif Expr.Elements (Index) /= null
              and then Has_Text (Expr.Elements (Index).Type_Name)
            then
               Target_Info :=
                 Resolve_Type_Name
                   (Unit,
                    Document,
                    FT.To_String (Expr.Elements (Index).Type_Name));
               Has_Target := Has_Text (Target_Info.Name);
            end if;

            if Index /= Expr.Elements.First_Index then
               Result := Result & SU.To_Unbounded_String (", ");
            end if;
            Result :=
              Result
              & SU.To_Unbounded_String
                  ((if Has_Target
                    then Render_Expr_For_Target_Type
                      (Unit,
                       Document,
                       Expr.Elements (Index),
                       Target_Info,
                       State)
                    else Render_Expr (Unit, Document, Expr.Elements (Index), State)));
         end;
      end loop;

      Result := Result & SU.To_Unbounded_String (")");
      return SU.To_String (Result);
   end Render_Positional_Tuple_Aggregate;

   function Render_Scalar_Value (Value : GM.Scalar_Value) return String is
   begin
      case Value.Kind is
         when GM.Scalar_Value_Integer =>
            return Trim_Image (Value.Int_Value);
         when GM.Scalar_Value_Boolean =>
            return (if Value.Bool_Value then "true" else "false");
         when GM.Scalar_Value_Character =>
            return FT.To_String (Value.Text);
         when GM.Scalar_Value_Enum =>
            return
              Render_Enum_Literal_Name
                (FT.To_String (Value.Text), FT.To_String (Value.Type_Name));
         when others =>
            return "";
      end case;
   end Render_Scalar_Value;

   function Render_Record_Aggregate_For_Type
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Expr      : CM.Expr_Access;
      Type_Info : GM.Type_Descriptor;
      State     : in out Emit_State) return String
   is
      Result : SU.Unbounded_String := SU.To_Unbounded_String ("(");
      First_Association : Boolean := True;
   begin
      if Expr = null then
         return "()";
      end if;

      if not Type_Info.Discriminant_Constraints.Is_Empty then
         for Constraint of Type_Info.Discriminant_Constraints loop
            if not First_Association then
               Result := Result & SU.To_Unbounded_String (", ");
            end if;
            Result :=
              Result
              & SU.To_Unbounded_String
                  (FT.To_String (Constraint.Name)
                   & " => "
                   & Render_Scalar_Value (Constraint.Value));
            First_Association := False;
         end loop;
      end if;

      for Field of Expr.Fields loop
         declare
            Field_Type : GM.Type_Descriptor := (others => <>);
         begin
            for Item of Type_Info.Fields loop
               if FT.To_String (Item.Name) = FT.To_String (Field.Field_Name) then
                  Field_Type := Resolve_Type_Name (Unit, Document, FT.To_String (Item.Type_Name));
                  exit;
               end if;
            end loop;
            if not First_Association then
               Result := Result & SU.To_Unbounded_String (", ");
            end if;
            Result :=
              Result
              & SU.To_Unbounded_String
                  (FT.To_String (Field.Field_Name)
                   & " => "
                   & (if Has_Text (Field_Type.Name)
                      then Render_Expr_For_Target_Type
                        (Unit, Document, Field.Expr, Field_Type, State)
                      else Render_Expr (Unit, Document, Field.Expr, State)));
            First_Association := False;
         end;
      end loop;

      Result := Result & SU.To_Unbounded_String (")");
      return SU.To_String (Result);
   end Render_Record_Aggregate_For_Type;

   function Render_String_Value_Image
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      Info     : GM.Type_Descriptor;
      State    : in out Emit_State) return String
   is
   begin
      if Is_Plain_String_Type (Unit, Document, Info) then
         State.Needs_Safe_String_RT := True;
         return
           "Safe_String_RT.To_String ("
           & Render_Heap_String_Expr (Unit, Document, Expr, State)
           & ")";
      elsif Is_Bounded_String_Type (Info) then
         Register_Bounded_String_Type (State, Info);
         return
           Bounded_String_Instance_Name (Info)
           & ".To_String ("
           & Render_Expr (Unit, Document, Expr, State)
           & ")";
      end if;

      return Render_Expr (Unit, Document, Expr, State);
   end Render_String_Value_Image;

   function Render_String_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String
   is
      Expr_Type_Info : GM.Type_Descriptor := (others => <>);
      Has_Expr_Type  : Boolean := False;
   begin
      if Expr = null then
         Raise_Unsupported
           (State,
            FT.Null_Span,
            "encountered null string expression during Ada emission");
      end if;

      if Has_Text (Expr.Type_Name) then
         declare
            Type_Name : constant String := FT.To_String (Expr.Type_Name);
            Found_Synthetic : Boolean := False;
         begin
            if Type_Info_From_Name (Unit, Document, Type_Name, Expr_Type_Info) then
               Has_Expr_Type := True;
            else
               Expr_Type_Info := Synthetic_Bounded_String_Type (Type_Name, Found_Synthetic);
               Has_Expr_Type := Found_Synthetic;
            end if;
         end;
      end if;

      if not Has_Expr_Type then
         Has_Expr_Type := Resolve_Print_Type (Unit, Document, Expr, State, Expr_Type_Info);
      end if;

      if Expr.Kind = CM.Expr_Ident then
         declare
            Static_Image : SU.Unbounded_String := SU.Null_Unbounded_String;
         begin
            if Try_Static_String_Binding (State, FT.To_String (Expr.Name), Static_Image) then
               return SU.To_String (Static_Image);
            end if;
         end;
      end if;

      if Expr.Kind = CM.Expr_String and then Has_Text (Expr.Text) then
         return FT.To_String (Expr.Text);
      elsif Expr.Kind = CM.Expr_Resolved_Index and then Expr.Prefix /= null then
         declare
            Prefix_Type : GM.Type_Descriptor := (others => <>);
            Prefix_Has_Type : Boolean := False;
            Prefix_Image : constant String := Render_Expr (Unit, Document, Expr.Prefix, State);
            Low_Image    : constant String := Render_Expr (Unit, Document, Expr.Args (Expr.Args.First_Index), State);
         begin
            if Has_Text (Expr.Prefix.Type_Name) then
               declare
                  Type_Name : constant String := FT.To_String (Expr.Prefix.Type_Name);
                  Found_Synthetic : Boolean := False;
               begin
                  if Type_Info_From_Name (Unit, Document, Type_Name, Prefix_Type) then
                     Prefix_Has_Type := True;
                  else
                     Prefix_Type := Synthetic_Bounded_String_Type (Type_Name, Found_Synthetic);
                     Prefix_Has_Type := Found_Synthetic;
                  end if;
               end;
            end if;

            if Prefix_Has_Type and then Is_Bounded_String_Type (Prefix_Type) then
               Register_Bounded_String_Type (State, Prefix_Type);
               if Natural (Expr.Args.Length) = 1 then
                  return
                    Bounded_String_Instance_Name (Prefix_Type)
                    & ".Element ("
                    & Prefix_Image
                    & ", "
                    & Low_Image
                    & ")";
               end if;
               declare
                  High_Image : constant String :=
                    Render_Expr (Unit, Document, Expr.Args (Expr.Args.First_Index + 1), State);
               begin
                  return
                    Bounded_String_Instance_Name (Prefix_Type)
                    & ".Slice ("
                    & Prefix_Image
                    & ", "
                    & Low_Image
                    & ", "
                    & High_Image
                    & ")";
               end;
            end if;

            if Has_Expr_Type then
               return
                 Render_String_Value_Image
                   (Unit, Document, Expr, Expr_Type_Info, State);
            end if;
         end;
      elsif Has_Expr_Type then
         return
           Render_String_Value_Image
             (Unit, Document, Expr, Expr_Type_Info, State);
      end if;

      return Render_Expr (Unit, Document, Expr, State);
   end Render_String_Expr;

   function Render_String_Length_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String
   is
   begin
      if Expr = null then
         Raise_Unsupported
           (State,
            FT.Null_Span,
            "encountered null string expression during Ada emission");
      elsif Has_Text (Expr.Type_Name) then
         declare
            Expr_Type : GM.Type_Descriptor := (others => <>);
            Has_Expr_Type : Boolean := False;
         begin
            if Type_Info_From_Name
              (Unit, Document, FT.To_String (Expr.Type_Name), Expr_Type)
            then
               Has_Expr_Type := True;
            else
               Expr_Type :=
                 Synthetic_Bounded_String_Type
                   (FT.To_String (Expr.Type_Name), Has_Expr_Type);
            end if;

            if not Has_Expr_Type then
               return "String'(" & Render_String_Expr (Unit, Document, Expr, State) & ")'Length";
            end if;

            if Is_Bounded_String_Type (Expr_Type) then
               Register_Bounded_String_Type (State, Expr_Type);
               return
                 "Long_Long_Integer ("
                 & Bounded_String_Instance_Name (Expr_Type)
                 & ".Length ("
                 & Render_Expr (Unit, Document, Expr, State)
                 & "))";
            elsif Is_Plain_String_Type (Unit, Document, Expr_Type) then
               State.Needs_Safe_String_RT := True;
               return
                 "Long_Long_Integer (Safe_String_RT.Length ("
                 & Render_Heap_String_Expr (Unit, Document, Expr, State)
                 & "))";
            end if;
         end;
      end if;

      return
        "Long_Long_Integer (String'("
        & Render_String_Expr (Unit, Document, Expr, State)
        & ")'Length)";
   end Render_String_Length_Expr;

   function Render_Expr_For_Target_Type
     (Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      Expr        : CM.Expr_Access;
      Target_Info : GM.Type_Descriptor;
      State       : in out Emit_State) return String renames AEX.Render_Expr_For_Target_Type;
   function Render_Type_Name
     (Info : GM.Type_Descriptor) return String renames AET.Render_Type_Name;
   function Render_Type_Name_From_Text
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Name_Text : String;
      State     : in out Emit_State) return String renames AET.Render_Type_Name_From_Text;
   function Render_Subtype_Indication
     (Unit     : CM.Resolved_Unit;
     Document : GM.Mir_Document;
     Info     : GM.Type_Descriptor) return String renames AET.Render_Subtype_Indication;
   function Render_Param_Type_Name
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return String renames AET.Render_Param_Type_Name;
   function Render_Type_Name
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Name     : String) return String renames AET.Render_Type_Name;
   function Default_Value_Expr
     (Type_Name : String) return String renames AET.Default_Value_Expr;
   function Default_Value_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return String renames AET.Default_Value_Expr;
   function Default_Value_Expr
     (Info : GM.Type_Descriptor) return String renames AET.Default_Value_Expr;
   function Needs_Explicit_Default_Initializer
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean renames AET.Needs_Explicit_Default_Initializer;
   function Lookup_Channel
     (Unit : CM.Resolved_Unit;
      Name : String) return CM.Resolved_Channel_Decl
   is
   begin
      for Item of Unit.Channels loop
         if FT.To_String (Item.Name) = Name then
            return Item;
         end if;
      end loop;
      for Item of Unit.Imported_Channels loop
         if FT.To_String (Item.Name) = Name then
            return Item;
         end if;
      end loop;
      return (others => <>);
   end Lookup_Channel;

   procedure Collect_Synthetic_Types
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Result   : in out GM.Type_Descriptor_Vectors.Vector) renames AET.Collect_Synthetic_Types;
   procedure Collect_Bounded_String_Types
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      State    : in out Emit_State) renames AES.Collect_Bounded_String_Types;
   procedure Collect_For_Of_Helper_Types
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Result   : in out GM.Type_Descriptor_Vectors.Vector) renames AES.Collect_For_Of_Helper_Types;
   procedure Render_For_Of_Helper_Bodies
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Types    : GM.Type_Descriptor_Vectors.Vector;
      State    : in out Emit_State) renames AET.Render_For_Of_Helper_Bodies;
   procedure Collect_Owner_Access_Helper_Types
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Result   : in out GM.Type_Descriptor_Vectors.Vector) renames AES.Collect_Owner_Access_Helper_Types;
   procedure Render_Owner_Access_Helper_Spec
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Type_Item : GM.Type_Descriptor) renames AET.Render_Owner_Access_Helper_Spec;
   procedure Render_Owner_Access_Helper_Body
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Type_Item : GM.Type_Descriptor;
      State    : in out Emit_State) renames AET.Render_Owner_Access_Helper_Body;
   procedure Append_Bounded_String_Instantiations
     (Buffer : in out SU.Unbounded_String;
      State  : Emit_State) renames AET.Append_Bounded_String_Instantiations;
   procedure Append_Bounded_String_Uses
     (Buffer : in out SU.Unbounded_String;
      State  : Emit_State;
      Depth  : Natural) renames AET.Append_Bounded_String_Uses;
   function Render_Integer_Type_Decl
     (Type_Item : GM.Type_Descriptor) return String
   is
      Name : constant String := Ada_Safe_Name (FT.To_String (Type_Item.Name));
   begin
      return
        "type "
        & Name
        & " is range "
        & Trim_Image (Type_Item.Low)
        & " .. "
        & Trim_Image (Type_Item.High)
        & ";";
   end Render_Integer_Type_Decl;

   function Render_Enum_Type_Decl
     (Type_Item : GM.Type_Descriptor) return String
   is
      Result : SU.Unbounded_String :=
        SU.To_Unbounded_String ("type " & Ada_Safe_Name (FT.To_String (Type_Item.Name)) & " is (");
   begin
      for Index in Type_Item.Enum_Literals.First_Index .. Type_Item.Enum_Literals.Last_Index loop
         if Index /= Type_Item.Enum_Literals.First_Index then
            Result := Result & SU.To_Unbounded_String (", ");
         end if;
         Result :=
           Result
           & SU.To_Unbounded_String
               (Ada_Safe_Name (FT.To_String (Type_Item.Enum_Literals (Index))));
      end loop;
      Result := Result & SU.To_Unbounded_String (");");
      return SU.To_String (Result);
   end Render_Enum_Type_Decl;

   function Render_Binary_Type_Decl
     (Type_Item : GM.Type_Descriptor) return String
   is
      Name : constant String := Ada_Safe_Name (FT.To_String (Type_Item.Name));
   begin
      return
        "type "
        & Name
        & " is mod 2 ** "
        & Ada.Strings.Fixed.Trim (Positive'Image (Type_Item.Bit_Width), Ada.Strings.Both)
        & ";";
   end Render_Binary_Type_Decl;

   function Render_Subtype_Type_Decl
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Type_Item : GM.Type_Descriptor) return String
   is
      pragma Unreferenced (Unit, Document);
      Name   : constant String := Ada_Safe_Name (FT.To_String (Type_Item.Name));
      Result : SU.Unbounded_String;
   begin
      if not Type_Item.Discriminant_Constraints.Is_Empty then
         Result :=
           SU.To_Unbounded_String
             ("subtype "
              & Name
              & " is "
              & Ada_Safe_Name (FT.To_String (Type_Item.Base))
              & " (");
         for Index in Type_Item.Discriminant_Constraints.First_Index .. Type_Item.Discriminant_Constraints.Last_Index loop
            declare
               Constraint : constant GM.Discriminant_Constraint :=
                 Type_Item.Discriminant_Constraints (Index);
            begin
               if Index /= Type_Item.Discriminant_Constraints.First_Index then
                  Result := Result & SU.To_Unbounded_String (", ");
               end if;
               if Constraint.Is_Named then
                  Result :=
                    Result
                    & SU.To_Unbounded_String
                        (FT.To_String (Constraint.Name) & " => ");
               end if;
               Result :=
                 Result & SU.To_Unbounded_String (Render_Scalar_Value (Constraint.Value));
            end;
         end loop;
         Result := Result & SU.To_Unbounded_String (");");
         return SU.To_String (Result);
      elsif Type_Item.Has_Low and then Type_Item.Has_High then
         return
           "subtype "
           & Name
           & " is "
           & Ada_Safe_Name (FT.To_String (Type_Item.Base))
           & " range "
           & Trim_Image (Type_Item.Low)
           & " .. "
           & Trim_Image (Type_Item.High)
           & ";";
      end if;

      return
        "subtype "
        & Name
        & " is "
        & Ada_Safe_Name (FT.To_String (Type_Item.Base))
        & ";";
   end Render_Subtype_Type_Decl;

   function Render_Array_Type_Decl
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Type_Item : GM.Type_Descriptor;
      State     : in out Emit_State) return String
   is
      Name : constant String := Ada_Safe_Name (FT.To_String (Type_Item.Name));
   begin
      if Type_Item.Growable or else Type_Item.Index_Types.Is_Empty then
         declare
            Identity_Runtime : constant Boolean :=
              Uses_Identity_Array_Runtime (Unit, Document, Type_Item);
            Runtime_Generic_Name : constant String :=
              Array_Runtime_Generic_Name (Unit, Document, Type_Item);
            Component_Info : constant GM.Type_Descriptor :=
              Resolve_Type_Name
                (Unit,
                 Document,
                 FT.To_String (Type_Item.Component_Type));
            Element_Type_Name : constant String :=
              Render_Type_Name_From_Text
                (Unit,
                 Document,
                 FT.To_String (Type_Item.Component_Type),
                 State);
            Default_Image : constant String :=
              Default_Value_Expr (Unit, Document, Component_Info);
            Clone_Post : constant String :=
              (if Identity_Runtime
               then
                 ASCII.LF
                 & Indentation (3)
                 & "Post => "
                 & Array_Runtime_Clone_Element_Name (Type_Item)
                 & "'Result = Source;"
               else
                 ";");
         begin
            if Runtime_Generic_Name = "Safe_Array_RT" then
               State.Needs_Safe_Array_RT := True;
            end if;
            return
              "function "
              & Array_Runtime_Default_Element_Name (Type_Item)
              & " return "
              & Element_Type_Name
              & (if Identity_Runtime then " is (" & Default_Image & ")" else "")
              & ASCII.LF
              & Indentation (2)
              & "with Global => null;"
              & ASCII.LF
              & Indentation (1)
              & "function "
              & Array_Runtime_Clone_Element_Name (Type_Item)
              & " (Source : "
              & Element_Type_Name
              & ") return "
              & Element_Type_Name
              & (if Identity_Runtime then " is (Source)" else "")
              & ASCII.LF
              & Indentation (2)
              & "with Global => null"
              & (if Identity_Runtime then "," & Clone_Post else ";")
              & ASCII.LF
              & Indentation (1)
              & "procedure "
              & Array_Runtime_Free_Element_Name (Type_Item)
              & " (Value : in out "
              & Element_Type_Name
              & ")"
              & (if Identity_Runtime
                 then
                   " is null;"
                 else
                   ASCII.LF
                   & Indentation (2)
                   & "with Global => null,"
                   & ASCII.LF
                   & Indentation (3)
                   & "Always_Terminates;")
              & ASCII.LF
              & (if Identity_Runtime
                 then
                   Indentation (1)
                   & "package "
                   & Array_Runtime_Identity_Ops_Name (Type_Item)
                   & " is new Safe_Array_Identity_Ops"
                   & ASCII.LF
                   & Indentation (2)
                   & "(Element_Type => "
                   & Element_Type_Name
                   & ","
                   & ASCII.LF
                   & Indentation (3)
                   & "Default_Element => "
                   & Array_Runtime_Default_Element_Name (Type_Item)
                   & ","
                   & ASCII.LF
                   & Indentation (3)
                   & "Clone_Element => "
                   & Array_Runtime_Clone_Element_Name (Type_Item)
                   & ","
                   & ASCII.LF
                   & Indentation (3)
                   & "Free_Element => "
                   & Array_Runtime_Free_Element_Name (Type_Item)
                   & ");"
                   & ASCII.LF
                 else
                   "")
              & Indentation (1)
              & "package "
              & Array_Runtime_Instance_Name (Type_Item)
              & " is new "
              & Runtime_Generic_Name
              & ASCII.LF
              & Indentation (2)
              & (if Identity_Runtime
                 then
                   "(Element_Ops => "
                   & Array_Runtime_Identity_Ops_Name (Type_Item)
                   & ");"
                 else
                   "(Element_Type => "
                   & Element_Type_Name
                   & ","
                   & ASCII.LF
                   & Indentation (3)
                   & "Default_Element => "
                   & Array_Runtime_Default_Element_Name (Type_Item)
                   & ","
                   & ASCII.LF
                   & Indentation (3)
                   & "Clone_Element => "
                   & Array_Runtime_Clone_Element_Name (Type_Item)
                   & ","
                   & ASCII.LF
                   & Indentation (3)
                   & "Free_Element => "
                   & Array_Runtime_Free_Element_Name (Type_Item)
                   & ");")
              & ASCII.LF
              & Indentation (1)
              & "subtype "
              & Name
              & " is "
              & Array_Runtime_Instance_Name (Type_Item)
              & ".Safe_Array;";
         end;
      end if;

      return
        "type "
        & Name
        & " is array ("
        & Join_Names (Type_Item.Index_Types)
        & ") of "
        & Render_Type_Name_From_Text
            (Unit,
             Document,
             FT.To_String (Type_Item.Component_Type),
             State)
        & ";";
   end Render_Array_Type_Decl;

   function Render_Tuple_Type_Decl
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Type_Item : GM.Type_Descriptor;
      State     : in out Emit_State) return String
   is
      Result : SU.Unbounded_String :=
        SU.To_Unbounded_String ("type " & Ada_Safe_Name (FT.To_String (Type_Item.Name)));
   begin
      Result := Result & SU.To_Unbounded_String (" is record" & ASCII.LF);
      for Index in Type_Item.Tuple_Element_Types.First_Index .. Type_Item.Tuple_Element_Types.Last_Index loop
         Result :=
           Result
           & SU.To_Unbounded_String
               (Indentation (1)
                & Tuple_Field_Name (Positive (Index))
                & " : "
                & Render_Type_Name_From_Text
                    (Unit,
                     Document,
                     FT.To_String (Type_Item.Tuple_Element_Types (Index)),
                     State)
                & ";"
                & ASCII.LF);
      end loop;
      Result := Result & SU.To_Unbounded_String ("end record;");
      return SU.To_String (Result);
   end Render_Tuple_Type_Decl;

   function Render_Result_Type_Decl
     (Type_Item : GM.Type_Descriptor;
      State     : in out Emit_State) return String
   is
   begin
      State.Needs_Ada_Strings_Unbounded := True;
      return
        "type "
        & Ada_Safe_Name (FT.To_String (Type_Item.Name))
        & " is record"
        & ASCII.LF
        & Indentation (1)
        & "Ok : Boolean := True;"
        & ASCII.LF
        & Indentation (1)
        & "Message : Ada.Strings.Unbounded.Unbounded_String := Ada.Strings.Unbounded.Null_Unbounded_String;"
        & ASCII.LF
        & Indentation (1)
        & "end record;";
   end Render_Result_Type_Decl;

   function Render_Record_Type_Decl
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Type_Item : GM.Type_Descriptor;
      State     : in out Emit_State) return String
   is
      Name   : constant String := Ada_Safe_Name (FT.To_String (Type_Item.Name));
      Result : SU.Unbounded_String;

      function Is_Variant_Field_Name (Field_Name : String) return Boolean is
      begin
         for Field of Type_Item.Variant_Fields loop
            if FT.To_String (Field.Name) = Field_Name then
               return True;
            end if;
         end loop;
         return False;
      end Is_Variant_Field_Name;

      function Same_Choice
        (Left, Right : GM.Variant_Field) return Boolean is
      begin
         return Left.Is_Others = Right.Is_Others
           and then
             (if Left.Is_Others
              then True
              else Left.Choice.Kind = Right.Choice.Kind
                and then Render_Scalar_Value (Left.Choice) = Render_Scalar_Value (Right.Choice));
      end Same_Choice;

      function Has_Others_Choice return Boolean is
      begin
         for Field of Type_Item.Variant_Fields loop
            if Field.Is_Others then
               return True;
            end if;
         end loop;
         return False;
      end Has_Others_Choice;

      function Needs_Null_Others_Branch return Boolean is
         Disc_Type : constant String :=
           FT.Lowercase (FT.To_String (Type_Item.Discriminant_Type));
         Has_True  : Boolean := False;
         Has_False : Boolean := False;
      begin
         if Has_Others_Choice or else Disc_Type /= "boolean" then
            return False;
         end if;

         for Field of Type_Item.Variant_Fields loop
            if Field.Choice.Kind = GM.Scalar_Value_Boolean then
               if Field.Choice.Bool_Value then
                  Has_True := True;
               else
                  Has_False := True;
               end if;
            end if;
         end loop;
         return not (Has_True and Has_False);
      end Needs_Null_Others_Branch;

      procedure Append_Missing_Enum_Null_Branches is
         Disc_Type_Info : GM.Type_Descriptor := (others => <>);
         Has_Disc_Type  : constant Boolean :=
           Has_Text (Type_Item.Discriminant_Type)
           and then Has_Type (Unit, Document, FT.To_String (Type_Item.Discriminant_Type));

         function Has_Explicit_Choice (Choice_Name : String) return Boolean is
         begin
            for Field of Type_Item.Variant_Fields loop
               if not Field.Is_Others
                 and then Render_Scalar_Value (Field.Choice) = Choice_Name
               then
                  return True;
               end if;
            end loop;
            return False;
         end Has_Explicit_Choice;
      begin
         if Has_Others_Choice or else not Has_Disc_Type then
            return;
         end if;

         Disc_Type_Info :=
           Lookup_Type (Unit, Document, FT.To_String (Type_Item.Discriminant_Type));
         if FT.To_String (Disc_Type_Info.Kind) /= "enum" then
            return;
         end if;

         for Literal of Disc_Type_Info.Enum_Literals loop
            declare
               Choice_Name : constant String :=
                 Ada_Safe_Name (FT.To_String (Literal));
            begin
               if not Has_Explicit_Choice (Choice_Name) then
                  Result :=
                    Result
                    & SU.To_Unbounded_String
                        (Indentation (1)
                         & "when "
                         & Choice_Name
                         & " =>"
                         & ASCII.LF
                         & Indentation (2)
                         & "null;"
                         & ASCII.LF);
               end if;
            end;
         end loop;
      end Append_Missing_Enum_Null_Branches;

      procedure Append_Field_Line
        (Field_Name : String;
         Field_Type : String;
         Depth      : Natural) is
      begin
         Result :=
           Result
           & SU.To_Unbounded_String
               (Indentation (Depth)
                & Field_Name
                & " : "
                & Field_Type
                & ";"
                & ASCII.LF);
      end Append_Field_Line;
   begin
      Result := SU.To_Unbounded_String ("type " & Name);
      if not Type_Item.Discriminants.Is_Empty then
         Result := Result & SU.To_Unbounded_String (" (");
         for Index in Type_Item.Discriminants.First_Index .. Type_Item.Discriminants.Last_Index loop
            declare
               Disc : constant GM.Discriminant_Descriptor :=
                 Type_Item.Discriminants (Index);
            begin
               if Index /= Type_Item.Discriminants.First_Index then
                  Result := Result & SU.To_Unbounded_String ("; ");
               end if;
               Result :=
                 Result
                 & SU.To_Unbounded_String
                     (Ada_Safe_Name (FT.To_String (Disc.Name))
                      & " : "
                      & Ada_Safe_Name (FT.To_String (Disc.Type_Name))
                      & (if Disc.Has_Default
                         then " := " & Render_Scalar_Value (Disc.Default_Value)
                         else ""));
            end;
         end loop;
         Result := Result & SU.To_Unbounded_String (")");
      elsif Type_Item.Has_Discriminant then
         Result :=
           Result
           & SU.To_Unbounded_String
               (" ("
                & Ada_Safe_Name (FT.To_String (Type_Item.Discriminant_Name))
                & " : "
                & Ada_Safe_Name (FT.To_String (Type_Item.Discriminant_Type))
                & (if Type_Item.Has_Discriminant_Default
                   then " := " & (if Type_Item.Discriminant_Default_Bool then "true" else "false")
                   else "")
                & ")");
      end if;
      Result := Result & SU.To_Unbounded_String (" is record" & ASCII.LF);
      for Field of Type_Item.Fields loop
         if not Is_Variant_Field_Name (FT.To_String (Field.Name)) then
            Append_Field_Line
              (Ada_Safe_Name (FT.To_String (Field.Name)),
               Render_Type_Name_From_Text
                 (Unit,
                  Document,
                  FT.To_String (Field.Type_Name),
                  State),
               1);
         end if;
      end loop;
      if not Type_Item.Variant_Fields.Is_Empty then
         Result :=
           Result
           & SU.To_Unbounded_String
               (Indentation (1)
                & "case "
                & Ada_Safe_Name
                    (FT.To_String
                       ((if Has_Text (Type_Item.Variant_Discriminant_Name)
                         then Type_Item.Variant_Discriminant_Name
                         else Type_Item.Discriminant_Name)))
                & " is"
                & ASCII.LF);
         declare
            Index : Positive := Type_Item.Variant_Fields.First_Index;
         begin
            while Index <= Type_Item.Variant_Fields.Last_Index loop
               declare
                  First_Field : constant GM.Variant_Field :=
                    Type_Item.Variant_Fields (Index);
               begin
                  Result :=
                    Result
                    & SU.To_Unbounded_String
                        (Indentation (1)
                         & "when "
                         & (if First_Field.Is_Others
                            then "others"
                            else Render_Scalar_Value (First_Field.Choice))
                         & " =>"
                         & ASCII.LF);
                  loop
                     Append_Field_Line
                       (Ada_Safe_Name (FT.To_String (Type_Item.Variant_Fields (Index).Name)),
                        Render_Type_Name_From_Text
                          (Unit,
                           Document,
                           FT.To_String (Type_Item.Variant_Fields (Index).Type_Name),
                           State),
                        2);
                     exit when Index = Type_Item.Variant_Fields.Last_Index;
                     exit when not Same_Choice
                       (First_Field,
                        Type_Item.Variant_Fields (Index + 1));
                     Index := Index + 1;
                  end loop;
                  Index := Index + 1;
               end;
            end loop;
         end;
         if Needs_Null_Others_Branch then
            Result :=
              Result
              & SU.To_Unbounded_String
                  (Indentation (1)
                   & "when others =>"
                   & ASCII.LF
                   & Indentation (2)
                   & "null;"
                   & ASCII.LF);
         end if;
         Append_Missing_Enum_Null_Branches;
         Result :=
           Result
           & SU.To_Unbounded_String
               (Indentation (1) & "end case;" & ASCII.LF);
      end if;
      Result := Result & SU.To_Unbounded_String ("end record;");
      return SU.To_String (Result);
   end Render_Record_Type_Decl;

   function Render_Access_Type_Decl
     (Type_Item : GM.Type_Descriptor) return String
   is
      Name : constant String := Ada_Safe_Name (FT.To_String (Type_Item.Name));
      Target_Name : constant String := FT.To_String (Type_Item.Target);
      Target_Decl : constant String :=
        (if Target_Name'Length > 0
            and then Starts_With (Target_Name, "safe_ref_target_")
         then "type " & Target_Name & ";" & ASCII.LF
         else "");
   begin
      return
        Target_Decl
        & "type "
        & Name
        & " is "
        & (if Type_Item.Not_Null then "not null " else "")
        & "access "
        & (if Type_Item.Is_Constant then "constant " else "")
        & Target_Name
        & ";";
   end Render_Access_Type_Decl;

   function Render_Float_Type_Decl
     (Type_Item : GM.Type_Descriptor) return String
   is
      Name : constant String := Ada_Safe_Name (FT.To_String (Type_Item.Name));
   begin
      if Type_Item.Has_Digits_Text then
         return
           "type "
           & Name
           & " is digits "
           & FT.To_String (Type_Item.Digits_Text)
           & (if Type_Item.Has_Float_Low_Text and then Type_Item.Has_Float_High_Text
               then
                 " range "
                 & FT.To_String (Type_Item.Float_Low_Text)
                 & " .. "
                 & FT.To_String (Type_Item.Float_High_Text)
               else
                 "")
           & ";";
      end if;
      return "type " & Name & " is digits 6;";
   end Render_Float_Type_Decl;

   function Render_Type_Decl
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Type_Item : GM.Type_Descriptor;
      State     : in out Emit_State) return String renames AET.Render_Type_Decl;
   procedure Render_Growable_Array_Helper_Body
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Type_Item : GM.Type_Descriptor;
      State    : in out Emit_State) renames AET.Render_Growable_Array_Helper_Body;
   function Map_Operator (Operator : String) return String is
   begin
      if Operator = "!=" then
         return "/=";
      elsif Operator = "==" then
         return "=";
      end if;
      return Operator;
   end Map_Operator;

   function Binary_Result_Type_Name
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access) return String is
   begin
      if Expr /= null and then Has_Text (Expr.Type_Name) then
         return Render_Type_Name (Unit, Document, FT.To_String (Expr.Type_Name));
      elsif Expr /= null and then Expr.Left /= null and then Has_Text (Expr.Left.Type_Name) then
         return Render_Type_Name (Unit, Document, FT.To_String (Expr.Left.Type_Name));
      end if;
      Raise_Internal ("binary expression missing result type during Ada emission");
   end Binary_Result_Type_Name;

   function Binary_Base_Type_Name
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access) return String is
   begin
      if Expr /= null and then Has_Text (Expr.Type_Name) and then Is_Binary_Type (Unit, Document, FT.To_String (Expr.Type_Name)) then
         return Binary_Ada_Name (Binary_Bit_Width (Unit, Document, FT.To_String (Expr.Type_Name)));
      elsif Expr /= null and then Expr.Left /= null and then Has_Text (Expr.Left.Type_Name) then
         return Binary_Ada_Name (Binary_Bit_Width (Unit, Document, FT.To_String (Expr.Left.Type_Name)));
      end if;
      Raise_Internal ("binary expression missing base type during Ada emission");
   end Binary_Base_Type_Name;

   function Render_Binary_Unary_Image
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Expr       : CM.Expr_Access;
      Inner_Image : String) return String is
      Result_Type : constant String := Binary_Result_Type_Name (Unit, Document, Expr);
      Base_Type   : constant String := Binary_Base_Type_Name (Unit, Document, Expr);
   begin
      return
        Result_Type
        & " (not "
        & Base_Type
        & " ("
        & Inner_Image
        & "))";
   end Render_Binary_Unary_Image;

   function Render_Binary_Operation_Image
     (Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      Expr        : CM.Expr_Access;
      Left_Image  : String;
      Right_Image : String) return String is
      Operator    : constant String := FT.To_String (Expr.Operator);
      Result_Type : constant String := Binary_Result_Type_Name (Unit, Document, Expr);
      Base_Type   : constant String := Binary_Base_Type_Name (Unit, Document, Expr);
   begin
      if Operator = "<<" or else Operator = ">>" then
         return
           Result_Type
           & " (Interfaces."
           & (if Operator = "<<" then "Shift_Left" else "Shift_Right")
           & " ("
           & Base_Type
           & " ("
           & Left_Image
           & "), Natural ("
           & Right_Image
           & ")))";
      elsif Operator in "==" | "!=" | "<" | "<=" | ">" | ">=" then
         return
           "("
           & Base_Type
           & " ("
           & Left_Image
           & ") "
           & Map_Operator (Operator)
           & " "
           & Base_Type
           & " ("
           & Right_Image
           & "))";
      end if;

      return
        Result_Type
        & " ("
        & Base_Type
        & " ("
        & Left_Image
        & ") "
        & Map_Operator (Operator)
        & " "
        & Base_Type
        & " ("
        & Right_Image
        & "))";
   end Render_Binary_Operation_Image;

   function Render_Select_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String
   is
      Prefix_Image    : constant String := Render_Expr (Unit, Document, Expr.Prefix, State);
      Selected_Prefix : constant String :=
        (if Needs_Implicit_Dereference (Unit, Document, Expr.Prefix)
         then Prefix_Image & ".all"
         else Prefix_Image);
      Selector_Name   : constant String := FT.To_String (Expr.Selector);
   begin
      if Selector_Name = "length"
        and then Expr.Prefix /= null
        and then not Selector_Is_Record_Field (Unit, Document, Expr.Prefix, Selector_Name)
      then
         declare
            Prefix_Type : constant GM.Type_Descriptor :=
              Base_Type (Unit, Document, Expr_Type_Info (Unit, Document, Expr.Prefix));
            Static_Length : Natural;
         begin
            if Expr.Prefix.Kind = CM.Expr_Ident
              and then Try_Static_Length
                (State,
                 FT.To_String (Expr.Prefix.Name),
                 Static_Length)
            then
               return "Long_Long_Integer (" & Trim_Wide_Image (CM.Wide_Integer (Static_Length)) & ")";
            end if;

            if Is_Bounded_String_Type (Prefix_Type) then
               Register_Bounded_String_Type (State, Prefix_Type);
               return
                 "Long_Long_Integer ("
                 & Bounded_String_Instance_Name (Prefix_Type)
                 & ".Length ("
                 & Prefix_Image
                 & "))";
            elsif FT.Lowercase (FT.To_String (Prefix_Type.Kind)) = "string" then
               return Render_String_Length_Expr (Unit, Document, Expr.Prefix, State);
            elsif FT.Lowercase (FT.To_String (Prefix_Type.Kind)) = "array" then
               if Is_Growable_Array_Type (Unit, Document, Prefix_Type) then
                  State.Needs_Safe_Array_RT := True;
                  return
                    "Long_Long_Integer ("
                    & Array_Runtime_Instance_Name (Prefix_Type)
                    & ".Length ("
                    & Prefix_Image
                    & "))";
               end if;
               return "Long_Long_Integer (" & Prefix_Image & "'Length)";
            end if;
         end;
      elsif Selector_Name = "access"
        and then Expr.Prefix /= null
        and then Has_Text (Expr.Prefix.Type_Name)
        and then Has_Type (Unit, Document, FT.To_String (Expr.Prefix.Type_Name))
        and then Is_Access_Type (Lookup_Type (Unit, Document, FT.To_String (Expr.Prefix.Type_Name)))
      then
         return Prefix_Image;
      elsif Is_Attribute_Selector (Selector_Name)
        and then not
          (Expr.Prefix /= null
           and then Expr.Prefix.Kind = CM.Expr_Select
           and then FT.To_String (Expr.Prefix.Selector) = "all")
        and then not Selector_Is_Record_Field (Unit, Document, Expr.Prefix, Selector_Name)
      then
         return Prefix_Image & "'" & Selector_Name;
      elsif Selector_Name'Length > 0
        and then Selector_Name (Selector_Name'First) in '0' .. '9'
      then
         return
           Prefix_Image
           & "."
           & Tuple_Field_Name (Positive (Natural'Value (Selector_Name)));
      elsif Expr.Prefix /= null
        and then FT.Lowercase (Selector_Name) = "message"
        and then Has_Text (Expr.Prefix.Type_Name)
        and then Has_Type (Unit, Document, FT.To_String (Expr.Prefix.Type_Name))
        and then Is_Result_Builtin
          (Lookup_Type (Unit, Document, FT.To_String (Expr.Prefix.Type_Name)))
      then
         State.Needs_Ada_Strings_Unbounded := True;
         return "Ada.Strings.Unbounded.To_String (" & Prefix_Image & ".Message)";
      end if;

      return Selected_Prefix & "." & Ada_Safe_Name (Selector_Name);
   end Render_Select_Expr;

   function Render_Resolved_Index_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String
   is
      Result : SU.Unbounded_String;
   begin
      if Expr.Prefix /= null and then Has_Text (Expr.Prefix.Type_Name) then
         declare
            Prefix_Type : GM.Type_Descriptor := (others => <>);
            Has_Prefix_Type : Boolean := False;
         begin
            if Has_Type (Unit, Document, FT.To_String (Expr.Prefix.Type_Name)) then
               Prefix_Type := Lookup_Type (Unit, Document, FT.To_String (Expr.Prefix.Type_Name));
               Has_Prefix_Type := True;
            else
               Prefix_Type :=
                 Synthetic_Bounded_String_Type
                   (FT.To_String (Expr.Prefix.Type_Name), Has_Prefix_Type);
            end if;

            if Has_Prefix_Type
              and then FT.Lowercase (FT.To_String (Prefix_Type.Kind)) = "string"
            then
               return Render_String_Expr (Unit, Document, Expr, State);
            elsif Has_Prefix_Type
              and then Is_Growable_Array_Type (Unit, Document, Prefix_Type)
            then
               return
                 Render_Growable_Array_Expr
                   (Unit, Document, Expr, Prefix_Type, State);
            elsif Has_Prefix_Type
              and then FT.Lowercase (FT.To_String (Prefix_Type.Kind)) = "array"
              and then Natural (Expr.Args.Length) = 2
              and then Natural (Prefix_Type.Index_Types.Length) = 1
            then
               return
                 (if Needs_Implicit_Dereference (Unit, Document, Expr.Prefix)
                  then Render_Expr (Unit, Document, Expr.Prefix, State) & ".all"
                  else Render_Expr (Unit, Document, Expr.Prefix, State))
                 & " ("
                 & Render_Expr (Unit, Document, Expr.Args (Expr.Args.First_Index), State)
                 & " .. "
                 & Render_Expr (Unit, Document, Expr.Args (Expr.Args.First_Index + 1), State)
                 & ")";
            end if;
         end;
      end if;

      Result :=
        SU.To_Unbounded_String
          ((if Needs_Implicit_Dereference (Unit, Document, Expr.Prefix)
            then Render_Expr (Unit, Document, Expr.Prefix, State) & ".all"
            else Render_Expr (Unit, Document, Expr.Prefix, State))
           & " (");
      for Index in Expr.Args.First_Index .. Expr.Args.Last_Index loop
         if Index /= Expr.Args.First_Index then
            Result := Result & SU.To_Unbounded_String (", ");
         end if;
         Result :=
           Result
           & SU.To_Unbounded_String
               (Render_Expr (Unit, Document, Expr.Args (Index), State));
      end loop;
      Result := Result & SU.To_Unbounded_String (")");
      return SU.To_String (Result);
   end Render_Resolved_Index_Expr;

   function Render_Conversion_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String
   is
      Target_Name_Text : constant String :=
        (if Has_Text (Expr.Type_Name)
         then FT.To_String (Expr.Type_Name)
         elsif Expr.Target /= null and then Has_Text (Expr.Target.Type_Name)
         then FT.To_String (Expr.Target.Type_Name)
         else "");
      Target_Image : constant String :=
        (if Has_Text (Expr.Type_Name)
         then Render_Type_Name (Unit, Document, FT.To_String (Expr.Type_Name))
         elsif Expr.Target /= null
         then Render_Expr (Unit, Document, Expr.Target, State)
         else "");
      Inner_Image : constant String :=
        Render_Expr (Unit, Document, Expr.Inner, State);
   begin
      if Target_Name_Text'Length > 0
        and then Is_Binary_Type (Unit, Document, Target_Name_Text)
      then
         return Target_Image & "'Mod (" & Inner_Image & ")";
      end if;
      return Target_Image & " (" & Inner_Image & ")";
   end Render_Conversion_Expr;

   function Render_Call_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String
   is
      Result       : SU.Unbounded_String;
      Callee_Flat  : constant String := CM.Flatten_Name (Expr.Callee);
      Lower_Callee : constant String := FT.Lowercase (Callee_Flat);
      Static_Length : Natural;
      Callee_Image : constant String :=
        (if Expr.Callee /= null
          and then Expr.Callee.Kind = CM.Expr_Select
          and then FT.To_String (Expr.Callee.Selector) = "access"
          and then Expr.Callee.Prefix /= null
          and then Has_Text (Expr.Callee.Prefix.Type_Name)
          and then Has_Type (Unit, Document, FT.To_String (Expr.Callee.Prefix.Type_Name))
          and then Is_Access_Type
            (Lookup_Type (Unit, Document, FT.To_String (Expr.Callee.Prefix.Type_Name)))
         then
           Render_Expr (Unit, Document, Expr.Callee.Prefix, State)
         elsif Expr.Callee /= null
          and then Expr.Callee.Kind = CM.Expr_Select
          and then Is_Attribute_Selector (FT.To_String (Expr.Callee.Selector))
          and then not
            (Expr.Callee.Prefix /= null
             and then Expr.Callee.Prefix.Kind = CM.Expr_Select
             and then FT.To_String (Expr.Callee.Prefix.Selector) = "all")
          and then not
            Selector_Is_Record_Field
              (Unit,
               Document,
               Expr.Callee.Prefix,
               FT.To_String (Expr.Callee.Selector))
         then
           Render_Expr (Unit, Document, Expr.Callee.Prefix, State)
           & "'"
           & FT.To_String (Expr.Callee.Selector)
         else Render_Expr (Unit, Document, Expr.Callee, State));
   begin
      if Natural (Expr.Args.Length) = 1
        and then Lower_Callee'Length >= 7
        and then Lower_Callee (Lower_Callee'Last - 6 .. Lower_Callee'Last) = ".length"
        and then Expr.Args (Expr.Args.First_Index) /= null
        and then Expr.Args (Expr.Args.First_Index).Kind = CM.Expr_Ident
        and then Try_Static_Length
          (State,
           FT.To_String (Expr.Args (Expr.Args.First_Index).Name),
           Static_Length)
      then
         return Trim_Wide_Image (CM.Wide_Integer (Static_Length));
      elsif Lower_Callee = "ok" and then Expr.Args.Is_Empty then
         State.Needs_Ada_Strings_Unbounded := True;
         return Render_Result_Empty_Aggregate;
      elsif Lower_Callee = "fail" and then Natural (Expr.Args.Length) = 1 then
         State.Needs_Ada_Strings_Unbounded := True;
         return
           Render_Result_Fail_Aggregate
             (Render_String_Expr
                (Unit,
                 Document,
                 Expr.Args (Expr.Args.First_Index),
                 State));
      end if;

      if Expr.Args.Is_Empty then
         return Callee_Image;
      end if;

      Result := SU.To_Unbounded_String (Callee_Image & " (");
      for Index in Expr.Args.First_Index .. Expr.Args.Last_Index loop
         declare
            Arg_Image  : SU.Unbounded_String;
            Used_Formal : Boolean := False;
         begin
            if Index /= Expr.Args.First_Index then
               Result := Result & SU.To_Unbounded_String (", ");
            end if;

            for Param of Unit.Subprograms loop
               if FT.Lowercase (FT.To_String (Param.Name)) = Lower_Callee
                 or else
                   FT.Lowercase
                     (FT.To_String (Unit.Package_Name) & "." & FT.To_String (Param.Name)) = Lower_Callee
               then
                  declare
                     Position : Natural := 0;
                  begin
                     for Formal of Param.Params loop
                        Position := Position + 1;
                        exit when Position > Natural (Index);
                        if Position = Natural (Index) then
                           if FT.To_String (Formal.Mode) in "" | "in" | "borrow" then
                              Arg_Image :=
                                SU.To_Unbounded_String
                                  (Render_Expr_For_Target_Type
                                     (Unit,
                                      Document,
                                      Expr.Args (Index),
                                      Formal.Type_Info,
                                      State));
                           else
                              Arg_Image :=
                                SU.To_Unbounded_String
                                  (Render_Expr (Unit, Document, Expr.Args (Index), State));
                           end if;
                           Used_Formal := True;
                           exit;
                        end if;
                     end loop;
                  end;
                  exit when Used_Formal;
               end if;
            end loop;

            if not Used_Formal and then Expr.Callee /= null then
               declare
                  Shared_Formal_Found : Boolean := False;
                  Shared_Formal_Type  : GM.Type_Descriptor :=
                    Shared_Call_Formal_Type
                      (Unit,
                       Document,
                       Expr,
                       Positive (Index),
                       Shared_Formal_Found);
               begin
                  if Shared_Formal_Found then
                     Arg_Image :=
                       SU.To_Unbounded_String
                         (Render_Expr_For_Target_Type
                            (Unit,
                             Document,
                             Expr.Args (Index),
                             Shared_Formal_Type,
                             State));
                     Used_Formal := True;
                  end if;
               end;
            end if;

            if not Used_Formal then
               declare
                  Arg_Type : GM.Type_Descriptor := (others => <>);
                  Maybe_Shared_Call : constant Boolean :=
                    Ada.Strings.Fixed.Index (Lower_Callee, "safe_shared_") > 0
                    or else Ada.Strings.Fixed.Index (Lower_Callee, "safe_public_shared_") > 0;
               begin
                  if Maybe_Shared_Call
                    and then Expr.Args (Index) /= null
                    and then Expr.Args (Index).Kind = CM.Expr_String
                  then
                    Arg_Type := Expr_Type_Info (Unit, Document, Expr.Args (Index));
                  end if;

                  if Has_Text (Arg_Type.Name)
                    and then
                      (Is_Plain_String_Type (Unit, Document, Arg_Type)
                       or else Is_Bounded_String_Type (Arg_Type))
                  then
                     Arg_Image :=
                       SU.To_Unbounded_String
                         (Render_Expr_For_Target_Type
                            (Unit,
                             Document,
                             Expr.Args (Index),
                             Arg_Type,
                             State));
                  else
                     Arg_Image :=
                       SU.To_Unbounded_String
                         (Render_Expr (Unit, Document, Expr.Args (Index), State));
                  end if;
               end;
            end if;

            Result := Result & Arg_Image;
         end;
      end loop;
      Result := Result & SU.To_Unbounded_String (")");
      return SU.To_String (Result);
   end Render_Call_Expr;

   function Render_Aggregate_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String
   is
      Result          : SU.Unbounded_String := SU.To_Unbounded_String ("(");
      Target_Info     : GM.Type_Descriptor := (others => <>);
      Has_Target_Info : constant Boolean :=
        Has_Text (Expr.Type_Name)
        and then Has_Type (Unit, Document, FT.To_String (Expr.Type_Name));

      function Aggregate_Field_Type (Field_Name : String) return GM.Type_Descriptor is
      begin
         if not Has_Target_Info then
            return (others => <>);
         end if;

         for Disc of Target_Info.Discriminants loop
            if FT.To_String (Disc.Name) = Field_Name then
               return Resolve_Type_Name (Unit, Document, FT.To_String (Disc.Type_Name));
            end if;
         end loop;
         if Target_Info.Has_Discriminant
           and then FT.To_String (Target_Info.Discriminant_Name) = Field_Name
         then
            return Resolve_Type_Name (Unit, Document, FT.To_String (Target_Info.Discriminant_Type));
         end if;
         for Record_Field of Target_Info.Fields loop
            if FT.To_String (Record_Field.Name) = Field_Name then
               return Resolve_Type_Name (Unit, Document, FT.To_String (Record_Field.Type_Name));
            end if;
         end loop;
         return (others => <>);
      end Aggregate_Field_Type;
   begin
      if Has_Target_Info then
         Target_Info := Lookup_Type (Unit, Document, FT.To_String (Expr.Type_Name));
      end if;
      for Index in Expr.Fields.First_Index .. Expr.Fields.Last_Index loop
         declare
            Field        : constant CM.Aggregate_Field := Expr.Fields (Index);
            Field_Target : constant GM.Type_Descriptor :=
              Aggregate_Field_Type (FT.To_String (Field.Field_Name));
         begin
            if Index /= Expr.Fields.First_Index then
               Result := Result & SU.To_Unbounded_String (", ");
            end if;
            Result :=
              Result
              & SU.To_Unbounded_String
                  (Ada_Safe_Name (FT.To_String (Field.Field_Name))
                   & " => "
                   & (if Has_Text (Field_Target.Name)
                      then Render_Expr_For_Target_Type
                        (Unit, Document, Field.Expr, Field_Target, State)
                      else Render_Expr (Unit, Document, Field.Expr, State)));
         end;
      end loop;
      Result := Result & SU.To_Unbounded_String (")");
      return SU.To_String (Result);
   end Render_Aggregate_Expr;

   function Render_Tuple_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String
   is
      Result : SU.Unbounded_String := SU.Null_Unbounded_String;
      Is_Array_Target : constant Boolean :=
        Has_Text (Expr.Type_Name)
        and then Has_Type (Unit, Document, FT.To_String (Expr.Type_Name))
        and then Is_Array_Type
          (Unit,
           Document,
           Lookup_Type (Unit, Document, FT.To_String (Expr.Type_Name)));
      First_Association : Boolean := True;
   begin
      if Is_Array_Target then
         return Render_Positional_Tuple_Aggregate (Unit, Document, Expr, State);
      end if;

      Result := SU.To_Unbounded_String ("(");
      for Index in Expr.Elements.First_Index .. Expr.Elements.Last_Index loop
         declare
            Target_Info : GM.Type_Descriptor := (others => <>);
            Has_Target  : Boolean := False;
         begin
            if Has_Text (Expr.Type_Name)
              and then Has_Type (Unit, Document, FT.To_String (Expr.Type_Name))
            then
               declare
                  Tuple_Info : constant GM.Type_Descriptor :=
                    Lookup_Type (Unit, Document, FT.To_String (Expr.Type_Name));
               begin
                  if Is_Tuple_Type (Tuple_Info)
                    and then Index <= Tuple_Info.Tuple_Element_Types.Last_Index
                  then
                     Target_Info :=
                       Resolve_Type_Name
                         (Unit,
                          Document,
                          FT.To_String (Tuple_Info.Tuple_Element_Types (Index)));
                     Has_Target := True;
                  end if;
               end;
            end if;

            if not Has_Target
              and then Expr.Elements (Index) /= null
              and then Has_Text (Expr.Elements (Index).Type_Name)
            then
               Target_Info :=
                 Resolve_Type_Name
                   (Unit,
                    Document,
                    FT.To_String (Expr.Elements (Index).Type_Name));
               Has_Target := Has_Text (Target_Info.Name);
            end if;

            if not First_Association then
               Result := Result & SU.To_Unbounded_String (", ");
            end if;
            Result :=
              Result
              & SU.To_Unbounded_String
                  (Tuple_Field_Name (Positive (Index))
                   & " => "
                   & (if Has_Target
                      then Render_Expr_For_Target_Type
                        (Unit,
                         Document,
                         Expr.Elements (Index),
                         Target_Info,
                         State)
                      else Render_Expr
                        (Unit,
                         Document,
                         Expr.Elements (Index),
                         State)));
            First_Association := False;
         end;
      end loop;
      Result := Result & SU.To_Unbounded_String (")");
      return SU.To_String (Result);
   end Render_Tuple_Expr;

   function Render_Annotated_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String
   is
      Target_Name     : constant String := Root_Name (Expr.Target);
      Is_Array_Target : constant Boolean :=
        Target_Name'Length > 0
        and then Has_Type (Unit, Document, Target_Name)
        and then Is_Array_Type
          (Unit,
           Document,
           Lookup_Type (Unit, Document, Target_Name));
   begin
      if Expr.Inner /= null
        and then Expr.Inner.Kind = CM.Expr_Tuple
        and then Is_Array_Target
      then
         return
           Render_Expr (Unit, Document, Expr.Target, State)
           & "'"
           & Render_Positional_Tuple_Aggregate
               (Unit, Document, Expr.Inner, State);
      end if;

      return
        Render_Expr (Unit, Document, Expr.Target, State)
        & "'"
        & (if Expr.Inner /= null and then Expr.Inner.Kind = CM.Expr_Aggregate
           then Render_Expr (Unit, Document, Expr.Inner, State)
           else "(" & Render_Expr (Unit, Document, Expr.Inner, State) & ")");
   end Render_Annotated_Expr;

   function Render_Unary_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String
   is
   begin
      if FT.To_String (Expr.Operator) = "not"
        and then Has_Text (Expr.Type_Name)
        and then Is_Binary_Type (Unit, Document, FT.To_String (Expr.Type_Name))
      then
         return
           Render_Binary_Unary_Image
             (Unit,
              Document,
              Expr,
              Render_Expr (Unit, Document, Expr.Inner, State));
      end if;
      return
        "("
        & Map_Operator (FT.To_String (Expr.Operator))
        & (if FT.To_String (Expr.Operator) = "not" then " " else "")
        & Render_Expr (Unit, Document, Expr.Inner, State)
        & ")";
   end Render_Unary_Expr;

   function Render_Binary_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String
   is
      Left_Type  : GM.Type_Descriptor := (others => <>);
      Right_Type : GM.Type_Descriptor := (others => <>);

      function Is_Stringish_Expr
        (Item : CM.Expr_Access;
         Info : out GM.Type_Descriptor) return Boolean
      is
      begin
         Info := (others => <>);
         if Item = null then
            return False;
         elsif Item.Kind = CM.Expr_String then
            Info := BT.String_Type;
            return True;
         else
            Info := Expr_Type_Info (Unit, Document, Item);
            if Has_Text (Info.Kind) or else Has_Text (Info.Name) then
               return True;
            end if;
            return Resolve_Print_Type (Unit, Document, Item, State, Info);
         end if;
      end Is_Stringish_Expr;

      function Is_Stringish_Type (Info : GM.Type_Descriptor) return Boolean is
         Base : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
         Kind : constant String := FT.Lowercase (FT.To_String (Base.Kind));
         Name : constant String := FT.Lowercase (FT.To_String (Base.Name));
      begin
         return
           Is_Plain_String_Type (Unit, Document, Info)
           or else Is_Bounded_String_Type (Info)
           or else Kind = "string"
           or else Name = "string";
      end Is_Stringish_Type;

      Has_Left_Type  : constant Boolean := Is_Stringish_Expr (Expr.Left, Left_Type);
      Has_Right_Type : constant Boolean := Is_Stringish_Expr (Expr.Right, Right_Type);
   begin
      if Has_Text (Expr.Type_Name)
        and then Is_Float_Type (Unit, Document, FT.To_String (Expr.Type_Name))
      then
         declare
            Convex_Image : constant String :=
              Render_Float_Convex_Combination (Unit, Document, Expr, State);
         begin
            if Convex_Image'Length > 0 then
               return Convex_Image;
            end if;
         end;
      end if;

      if Expr.Left /= null
        and then Expr.Right /= null
        and then Has_Left_Type
        and then Has_Right_Type
        and then Is_Stringish_Type (Left_Type)
        and then Is_Stringish_Type (Right_Type)
      then
         declare
            Left_Image  : constant String := Render_String_Expr (Unit, Document, Expr.Left, State);
            Right_Image : constant String := Render_String_Expr (Unit, Document, Expr.Right, State);
            Operator    : constant String := FT.To_String (Expr.Operator);
         begin
            if Operator in "==" | "=" | "!=" | "/=" then
               return "(" & Left_Image & " " & Map_Operator (Operator) & " " & Right_Image & ")";
            elsif Operator in "<" | "<=" | ">" | ">=" then
               return "(" & Left_Image & " " & Map_Operator (Operator) & " " & Right_Image & ")";
            elsif Operator = "&" then
               return "(" & Left_Image & " & " & Right_Image & ")";
            end if;
         end;
      end if;

      if Expr.Left /= null
        and then Has_Text (Expr.Left.Type_Name)
        and then Is_Binary_Type (Unit, Document, FT.To_String (Expr.Left.Type_Name))
      then
         return
           Render_Binary_Operation_Image
             (Unit,
              Document,
              Expr,
              Render_Expr (Unit, Document, Expr.Left, State),
              Render_Expr (Unit, Document, Expr.Right, State));
      end if;

      return
        "("
        & Render_Expr (Unit, Document, Expr.Left, State)
        & " "
        & Map_Operator (FT.To_String (Expr.Operator))
        & " "
        & Render_Expr (Unit, Document, Expr.Right, State)
        & ")";
   end Render_Binary_Expr;

   function Render_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String renames AEX.Render_Expr;
   function Render_Print_Argument
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String renames AEX.Render_Print_Argument;
   function Render_Float_Convex_Combination
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String
   is
      function Is_Real_One (Item : CM.Expr_Access) return Boolean is
      begin
         return
           Item /= null
           and then Item.Kind = CM.Expr_Real
           and then Has_Text (Item.Text)
           and then FT.To_String (Item.Text) = "1.0";
      end Is_Real_One;

      function Images_Match (Left, Right : CM.Expr_Access) return Boolean is
      begin
         return Left /= null
           and then Right /= null
           and then Render_Expr (Unit, Document, Left, State) = Render_Expr (Unit, Document, Right, State);
      end Images_Match;

      function Complement_Of
        (Candidate, Weight : CM.Expr_Access) return Boolean is
      begin
         return
           Candidate /= null
           and then Candidate.Kind = CM.Expr_Binary
           and then FT.To_String (Candidate.Operator) = "-"
           and then Is_Real_One (Candidate.Left)
           and then Images_Match (Candidate.Right, Weight);
      end Complement_Of;

      function Extract_Product
        (Term      : CM.Expr_Access;
         Weight    : out CM.Expr_Access;
         Component : out CM.Expr_Access) return Boolean
      is
      begin
         if Term = null or else Term.Kind /= CM.Expr_Binary or else FT.To_String (Term.Operator) /= "*" then
            Weight := null;
            Component := null;
            return False;
         end if;

         Weight := Term.Left;
         Component := Term.Right;
         return True;
      end Extract_Product;

      W1, W2 : CM.Expr_Access := null;
      V1, V2 : CM.Expr_Access := null;
   begin
      if Expr = null
        or else Expr.Kind /= CM.Expr_Binary
        or else FT.To_String (Expr.Operator) /= "+"
      then
         return "";
      end if;

      if not Extract_Product (Expr.Left, W1, V1)
        or else not Extract_Product (Expr.Right, W2, V2)
      then
         return "";
      end if;

      if Complement_Of (W1, W2) then
         return
           "("
           & Render_Expr (Unit, Document, V1, State)
           & " + ("
           & Render_Expr (Unit, Document, W2, State)
           & " * ("
           & Render_Expr (Unit, Document, V2, State)
           & " - "
           & Render_Expr (Unit, Document, V1, State)
           & ")))";
      elsif Complement_Of (W2, W1) then
         return
           "("
           & Render_Expr (Unit, Document, V2, State)
           & " + ("
           & Render_Expr (Unit, Document, W1, State)
           & " * ("
           & Render_Expr (Unit, Document, V1, State)
           & " - "
           & Render_Expr (Unit, Document, V2, State)
           & ")))";
      end if;

      return "";
   end Render_Float_Convex_Combination;

   function Uses_Wide_Value
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      State    : Emit_State;
      Expr     : CM.Expr_Access) return Boolean renames AEX.Uses_Wide_Value;
   function Is_Explicit_Float_Narrowing
     (Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      Target_Type : String;
      Expr        : CM.Expr_Access) return Boolean
   is
   begin
      return Target_Type'Length > 0
        and then Is_Float_Type (Unit, Document, Target_Type)
        and then not Is_Builtin_Float_Name (Target_Type)
        and then Expr /= null
        and then Expr.Kind = CM.Expr_Conversion
        and then Expr.Inner /= null
        and then Has_Text (Expr.Type_Name)
        and then FT.To_String (Expr.Type_Name) = Target_Type;
   end Is_Explicit_Float_Narrowing;

   function Try_Render_Stable_Float_Interpolation
     (Unit            : CM.Resolved_Unit;
      Document        : GM.Mir_Document;
      Expr            : CM.Expr_Access;
      State           : in out Emit_State;
      Condition_Image : out FT.UString;
      Lower_Image     : out FT.UString;
      Upper_Image     : out FT.UString) return Boolean
   is
      function Is_Real_One (Item : CM.Expr_Access) return Boolean is
      begin
         return
           Item /= null
           and then Item.Kind = CM.Expr_Real
           and then Has_Text (Item.Text)
           and then FT.To_String (Item.Text) = "1.0";
      end Is_Real_One;

      function Images_Match (Left, Right : CM.Expr_Access) return Boolean is
      begin
         return Left /= null
           and then Right /= null
           and then Render_Expr (Unit, Document, Left, State) = Render_Expr (Unit, Document, Right, State);
      end Images_Match;

      function Complement_Of
        (Candidate, Weight : CM.Expr_Access) return Boolean is
      begin
         return
           Candidate /= null
           and then Candidate.Kind = CM.Expr_Binary
           and then FT.To_String (Candidate.Operator) = "-"
           and then Is_Real_One (Candidate.Left)
           and then Images_Match (Candidate.Right, Weight);
      end Complement_Of;

      function Extract_Product
        (Term      : CM.Expr_Access;
         Weight    : out CM.Expr_Access;
         Component : out CM.Expr_Access) return Boolean
      is
      begin
         if Term = null or else Term.Kind /= CM.Expr_Binary or else FT.To_String (Term.Operator) /= "*" then
            Weight := null;
            Component := null;
            return False;
         end if;

         Weight := Term.Left;
         Component := Term.Right;
         return True;
      end Extract_Product;

      function Match_Delta_Form
        (Candidate : CM.Expr_Access;
         Anchor    : out CM.Expr_Access;
         Other     : out CM.Expr_Access;
         Weight    : out CM.Expr_Access) return Boolean
      is
         Delta_Term : CM.Expr_Access := null;
      begin
         if Candidate = null
           or else Candidate.Kind /= CM.Expr_Binary
           or else FT.To_String (Candidate.Operator) /= "+"
         then
            Anchor := null;
            Other := null;
            Weight := null;
            return False;
         end if;

         if Extract_Product (Candidate.Right, Weight, Delta_Term)
           and then Delta_Term /= null
           and then Delta_Term.Kind = CM.Expr_Binary
           and then FT.To_String (Delta_Term.Operator) = "-"
           and then Images_Match (Candidate.Left, Delta_Term.Right)
         then
            Anchor := Candidate.Left;
            Other := Delta_Term.Left;
            return True;
         elsif Extract_Product (Candidate.Left, Weight, Delta_Term)
           and then Delta_Term /= null
           and then Delta_Term.Kind = CM.Expr_Binary
           and then FT.To_String (Delta_Term.Operator) = "-"
           and then Images_Match (Candidate.Right, Delta_Term.Right)
         then
            Anchor := Candidate.Right;
            Other := Delta_Term.Left;
            return True;
         end if;

         Anchor := null;
         Other := null;
         Weight := null;
         return False;
      end Match_Delta_Form;

      Weight_1     : CM.Expr_Access := null;
      Weight_2     : CM.Expr_Access := null;
      Value_1      : CM.Expr_Access := null;
      Value_2      : CM.Expr_Access := null;
      Anchor       : CM.Expr_Access := null;
      Other        : CM.Expr_Access := null;
      Weight       : CM.Expr_Access := null;
      Anchor_Image : FT.UString := FT.To_UString ("");
      Other_Image  : FT.UString := FT.To_UString ("");
      Weight_Image : FT.UString := FT.To_UString ("");
   begin
      Condition_Image := FT.To_UString ("");
      Lower_Image := FT.To_UString ("");
      Upper_Image := FT.To_UString ("");

      if Match_Delta_Form (Expr, Anchor, Other, Weight) then
         null;
      elsif Expr /= null
        and then Expr.Kind = CM.Expr_Binary
        and then FT.To_String (Expr.Operator) = "+"
        and then Extract_Product (Expr.Left, Weight_1, Value_1)
        and then Extract_Product (Expr.Right, Weight_2, Value_2)
      then
         if Complement_Of (Weight_1, Weight_2) then
            Anchor := Value_1;
            Other := Value_2;
            Weight := Weight_2;
         elsif Complement_Of (Weight_2, Weight_1) then
            Anchor := Value_2;
            Other := Value_1;
            Weight := Weight_1;
         else
            return False;
         end if;
      else
         return False;
      end if;

      if Anchor = null or else Other = null or else Weight = null then
         return False;
      end if;

      Anchor_Image := FT.To_UString (Render_Expr (Unit, Document, Anchor, State));
      Other_Image := FT.To_UString (Render_Expr (Unit, Document, Other, State));
      Weight_Image := FT.To_UString (Render_Expr (Unit, Document, Weight, State));

      Condition_Image := FT.To_UString (FT.To_String (Weight_Image) & " <= 0.5");
      Lower_Image :=
        FT.To_UString
          ("("
           & FT.To_String (Anchor_Image)
           & " + ("
           & FT.To_String (Weight_Image)
           & " * ("
           & FT.To_String (Other_Image)
           & " - "
           & FT.To_String (Anchor_Image)
           & ")))");
      Upper_Image :=
        FT.To_UString
          ("("
           & FT.To_String (Other_Image)
           & " - ((1.0 - "
           & FT.To_String (Weight_Image)
           & ") * ("
           & FT.To_String (Other_Image)
           & " - "
           & FT.To_String (Anchor_Image)
           & ")))");
      return True;
   end Try_Render_Stable_Float_Interpolation;

   function Render_Channel_Send_Value
     (Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      State        : in out Emit_State;
      Channel_Expr : CM.Expr_Access;
      Value        : CM.Expr_Access) return String renames AEX.Render_Channel_Send_Value;
   procedure Collect_Wide_Locals_From_Statements
     (Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      State       : in out Emit_State;
      Statements  : CM.Statement_Access_Vectors.Vector);

   procedure Mark_Wide_Declaration
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      State     : in out Emit_State;
      Decl      : CM.Resolved_Object_Decl) is
   begin
      if Is_Integer_Type (Unit, Document, Decl.Type_Info)
        and then Decl.Has_Initializer
        and then Uses_Wide_Value (Unit, Document, State, Decl.Initializer)
      then
         for Name of Decl.Names loop
            Add_Wide_Name (State, FT.To_String (Name));
         end loop;
      end if;
   end Mark_Wide_Declaration;

   procedure Mark_Wide_Declaration
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      State     : in out Emit_State;
      Decl      : CM.Object_Decl) is
   begin
      if Is_Integer_Type (Unit, Document, Decl.Type_Info)
        and then Decl.Has_Initializer
        and then Uses_Wide_Value (Unit, Document, State, Decl.Initializer)
      then
         for Name of Decl.Names loop
            Add_Wide_Name (State, FT.To_String (Name));
         end loop;
      end if;
   end Mark_Wide_Declaration;

   procedure Collect_Wide_Locals_From_Statements
     (Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      State       : in out Emit_State;
      Statements  : CM.Statement_Access_Vectors.Vector) is
   begin
      for Item of Statements loop
         if Item = null then
            null;
         else
            case Item.Kind is
               when CM.Stmt_Object_Decl =>
                  Mark_Wide_Declaration (Unit, Document, State, Item.Decl);
               when CM.Stmt_Destructure_Decl =>
                  null;
               when CM.Stmt_Assign =>
                  null;
               when CM.Stmt_If =>
                  Collect_Wide_Locals_From_Statements
                    (Unit, Document, State, Item.Then_Stmts);
                  for Part of Item.Elsifs loop
                     Collect_Wide_Locals_From_Statements
                       (Unit, Document, State, Part.Statements);
                  end loop;
                  if Item.Has_Else then
                     Collect_Wide_Locals_From_Statements
                       (Unit, Document, State, Item.Else_Stmts);
                  end if;
               when CM.Stmt_Case =>
                  for Arm of Item.Case_Arms loop
                     Collect_Wide_Locals_From_Statements
                       (Unit, Document, State, Arm.Statements);
                  end loop;
               when CM.Stmt_While | CM.Stmt_For | CM.Stmt_Loop =>
                  Collect_Wide_Locals_From_Statements
                    (Unit, Document, State, Item.Body_Stmts);
               when CM.Stmt_Select =>
                  for Arm of Item.Arms loop
                     case Arm.Kind is
                        when CM.Select_Arm_Channel =>
                           Collect_Wide_Locals_From_Statements
                             (Unit,
                              Document,
                              State,
                              Arm.Channel_Data.Statements);
                        when CM.Select_Arm_Delay =>
                           Collect_Wide_Locals_From_Statements
                             (Unit,
                              Document,
                              State,
                              Arm.Delay_Data.Statements);
                        when others =>
                           null;
                     end case;
                  end loop;
               when others =>
                  null;
            end case;
         end if;
      end loop;
   end Collect_Wide_Locals_From_Statements;

   procedure Collect_Wide_Locals
     (Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      State        : in out Emit_State;
      Declarations : CM.Resolved_Object_Decl_Vectors.Vector;
      Statements   : CM.Statement_Access_Vectors.Vector) is
   begin
      for Decl of Declarations loop
         Mark_Wide_Declaration (Unit, Document, State, Decl);
      end loop;
      Collect_Wide_Locals_From_Statements
        (Unit, Document, State, Statements);
   end Collect_Wide_Locals;

   procedure Collect_Wide_Locals
     (Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      State        : in out Emit_State;
      Declarations : CM.Object_Decl_Vectors.Vector;
      Statements   : CM.Statement_Access_Vectors.Vector) is
   begin
      for Decl of Declarations loop
         Mark_Wide_Declaration (Unit, Document, State, Decl);
      end loop;
      Collect_Wide_Locals_From_Statements
        (Unit, Document, State, Statements);
   end Collect_Wide_Locals;

   function Render_Wide_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String renames AEX.Render_Wide_Expr;
   function Render_Wide_Expr_With_Target_Substitution
     (Unit          : CM.Resolved_Unit;
      Document      : GM.Mir_Document;
      Expr          : CM.Expr_Access;
      Target        : CM.Expr_Access;
      Replacement   : String;
      State         : in out Emit_State;
      Supported     : in out Boolean) return String renames AEX.Render_Wide_Expr_With_Target_Substitution;
   function Render_Object_Decl_Text_Common
     (Unit           : CM.Resolved_Unit;
      Document       : GM.Mir_Document;
      State          : in out Emit_State;
      Names          : FT.UString_Vectors.Vector;
      Type_Info      : GM.Type_Descriptor;
      Is_Constant    : Boolean;
      Has_Initializer : Boolean;
      Has_Implicit_Default_Init : Boolean;
      Initializer    : CM.Expr_Access;
      Local_Context  : Boolean := False;
      Defer_Initializer : Boolean := False) return String
   is
      Result : SU.Unbounded_String;
      Constant_Qualifier : constant String :=
        (if Is_Constant and then not Is_Owner_Access (Type_Info) then "constant " else "");
      Type_Name : constant String :=
        (if Is_Integer_Type (Unit, Document, Type_Info)
           and then Names_Use_Wide_Storage (State, Names)
         then "safe_runtime.wide_integer"
         elsif Local_Context
           and then Is_Access_Type (Type_Info)
           and then not Is_Owner_Access (Type_Info)
           and then Has_Text (Type_Info.Target)
         then
           (if Type_Info.Not_Null then "not null " else "")
           & "access "
           & (if Type_Info.Is_Constant then "constant " else "")
           & FT.To_String (Type_Info.Target)
         elsif Is_Owner_Access (Type_Info)
         then Render_Type_Name (Type_Info)
         else Render_Subtype_Indication (Unit, Document, Type_Info));
      function Render_Initializer return String is
      begin
         if Initializer /= null and then Is_Owner_Access (Type_Info) then
            return
              Render_Expr_For_Target_Type
                (Unit, Document, Initializer, Type_Info, State);
         elsif Initializer /= null and then Is_Bounded_String_Type (Type_Info) then
            return
              Render_Expr_For_Target_Type
                (Unit, Document, Initializer, Type_Info, State);
         end if;
         if Initializer /= null
           and then Initializer.Kind = CM.Expr_Aggregate
           and then not Type_Info.Discriminant_Constraints.Is_Empty
           and then Type_Name /= "safe_runtime.wide_integer"
         then
            return
              Type_Name
              & "'"
              & Render_Record_Aggregate_For_Type
                 (Unit, Document, Initializer, Type_Info, State);
         elsif Initializer /= null
           and then Initializer.Kind = CM.Expr_Tuple
           and then Is_Array_Type (Unit, Document, Type_Info)
           and then Type_Name /= "safe_runtime.wide_integer"
         then
            return
              Type_Name
              & "'"
              & Render_Positional_Tuple_Aggregate
                  (Unit, Document, Initializer, State);
         elsif Initializer /= null
           and then Initializer.Kind in CM.Expr_Aggregate | CM.Expr_Tuple
           and then Type_Name /= "safe_runtime.wide_integer"
         then
            return Type_Name & "'" & Render_Expr (Unit, Document, Initializer, State);
         end if;
         return Render_Expr_For_Target_Type (Unit, Document, Initializer, Type_Info, State);
      end Render_Initializer;
      Defer_Heap_Init : constant Boolean :=
        Defer_Initializer
        or else
          (not Local_Context
           and then Has_Initializer
           and then not Is_Constant
           and then Has_Heap_Value_Type (Unit, Document, Type_Info));
      Implicit_Heap_Default_Init : constant Boolean :=
        Initializer = null
        and then not Is_Constant
        and then not Is_Owner_Access (Type_Info)
        and then Has_Heap_Value_Type (Unit, Document, Type_Info);
      Needs_Explicit_Default_Init : constant Boolean :=
        Has_Implicit_Default_Init
        and then Initializer = null
        and then Needs_Explicit_Default_Initializer (Unit, Document, Type_Info);
      Suppress_Explicit_Null_Init : constant Boolean :=
        Initializer /= null
        and then Initializer.Kind = CM.Expr_Null
        and then not Is_Constant
        and then Is_Owner_Access (Type_Info);
      Emit_Initializer : constant Boolean :=
        (Has_Initializer and then not Suppress_Explicit_Null_Init)
        or else Needs_Explicit_Default_Init
        or else Implicit_Heap_Default_Init;
   begin
      if Type_Name = "safe_runtime.wide_integer" then
         State.Needs_Safe_Runtime := True;
      end if;
      for Index in Names.First_Index .. Names.Last_Index loop
         if Index /= Names.First_Index then
            Result := Result & SU.To_Unbounded_String ("; ");
         end if;
         Result :=
           Result
           & SU.To_Unbounded_String
                (FT.To_String (Names (Index))
                & " : "
                & Constant_Qualifier
                & Type_Name);
         if Emit_Initializer then
            if Type_Name = "safe_runtime.wide_integer" then
               Result :=
                 Result
                 & SU.To_Unbounded_String
                     (" := " & Render_Wide_Expr (Unit, Document, Initializer, State));
            elsif Defer_Heap_Init then
               Result :=
                 Result
                 & SU.To_Unbounded_String
                     (" := " & Default_Value_Expr (Unit, Document, Type_Info));
            elsif
              (Needs_Explicit_Default_Init or else Implicit_Heap_Default_Init)
              and then Initializer = null
            then
               Result :=
                 Result
                 & SU.To_Unbounded_String
                     (" := " & Default_Value_Expr (Unit, Document, Type_Info));
            elsif Is_Integer_Type (Unit, Document, Type_Info)
              and then Uses_Wide_Value (Unit, Document, State, Initializer)
            then
               Result :=
                 Result
                 & SU.To_Unbounded_String
                     (" := "
                      & Render_Type_Name (Type_Info)
                      & " ("
                      & Render_Wide_Expr (Unit, Document, Initializer, State)
                      & ")");
            else
               Result :=
                 Result
                 & SU.To_Unbounded_String
                     (" := " & Render_Initializer);
            end if;
         end if;
      end loop;
      return SU.To_String (Result) & ";";
   end Render_Object_Decl_Text_Common;

   function Render_Object_Decl_Text
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      State    : in out Emit_State;
      Decl     : CM.Resolved_Object_Decl;
      Local_Context : Boolean := False;
      Defer_Initializer : Boolean := False) return String renames AES.Render_Object_Decl_Text;
   function Render_Object_Decl_Text
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      State    : in out Emit_State;
      Decl     : CM.Object_Decl;
      Local_Context : Boolean := False;
      Defer_Initializer : Boolean := False) return String renames AES.Render_Object_Decl_Text;
   function Render_Subprogram_Params
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Params     : CM.Symbol_Vectors.Vector) return String
   is
      Result : SU.Unbounded_String := SU.To_Unbounded_String ("(");
   begin
      if Params.Is_Empty then
         return "";
      end if;

      for Index in Params.First_Index .. Params.Last_Index loop
         declare
            Param : constant CM.Symbol := Params (Index);
            Mode  : constant String := FT.To_String (Param.Mode);
         begin
            if Index /= Params.First_Index then
               Result := Result & SU.To_Unbounded_String ("; ");
            end if;
            Result :=
              Result
              & SU.To_Unbounded_String
                  (FT.To_String (Param.Name)
                   & " : "
                  & (if Mode = "" or else Mode = "borrow"
                      then "in "
                      elsif Mode = "mut"
                      then "in out "
                      elsif Mode = "in"
                      then "in "
                      else Mode & " ")
                   & Render_Param_Type_Name (Unit, Document, Param.Type_Info));
         end;
      end loop;

      Result := Result & SU.To_Unbounded_String (")");
      return SU.To_String (Result);
   end Render_Subprogram_Params;

   function Render_Subprogram_Return
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram) return String is
   begin
      if Subprogram.Has_Return_Type then
         return
           " return "
           & Render_Subtype_Indication (Unit, Document, Subprogram.Return_Type);
      end if;
      return "";
   end Render_Subprogram_Return;

   function Render_Ada_Subprogram_Keyword
     (Subprogram : CM.Resolved_Subprogram) return String is
   begin
      if Subprogram.Has_Return_Type then
         return "function";
      end if;
      return "procedure";
   end Render_Ada_Subprogram_Keyword;

   function Alias_Declarations
     (Declarations : CM.Resolved_Object_Decl_Vectors.Vector)
      return CM.Resolved_Object_Decl_Vectors.Vector
   is
      Result : CM.Resolved_Object_Decl_Vectors.Vector;
   begin
      for Decl of Declarations loop
         if Is_Alias_Access (Decl.Type_Info) then
            Result.Append (Decl);
         end if;
      end loop;
      return Result;
   end Alias_Declarations;

   function Non_Alias_Declarations
     (Declarations : CM.Resolved_Object_Decl_Vectors.Vector)
      return CM.Resolved_Object_Decl_Vectors.Vector
   is
      Result : CM.Resolved_Object_Decl_Vectors.Vector;
   begin
      for Decl of Declarations loop
         if not Is_Alias_Access (Decl.Type_Info) then
            Result.Append (Decl);
         end if;
      end loop;
      return Result;
   end Non_Alias_Declarations;

   procedure Render_In_Out_Param_Stabilizers
     (Buffer     : in out SU.Unbounded_String;
      Subprogram : CM.Resolved_Subprogram;
      Depth      : Natural)
   is
      pragma Unreferenced (Buffer, Subprogram, Depth);
   begin
      null;
   end Render_In_Out_Param_Stabilizers;

   function Find_Graph_Summary
     (Bronze : MB.Bronze_Result;
      Name   : String) return MB.Graph_Summary
   is
   begin
      for Item of Bronze.Graphs loop
         if FT.To_String (Item.Name) = Name then
            return Item;
         end if;
      end loop;
      return (others => <>);
   end Find_Graph_Summary;

   function Subprogram_Uses_Global_Name
     (Unit       : CM.Resolved_Unit;
      Subprogram : CM.Resolved_Subprogram;
      Name       : String) return Boolean
   is
      Visited_Calls : FT.UString_Vectors.Vector;

      procedure Collect_Call_Names_From_Expr
        (Expr  : CM.Expr_Access;
         Calls : in out FT.UString_Vectors.Vector);

      procedure Collect_Call_Names_From_Statements
        (Statements : CM.Statement_Access_Vectors.Vector;
         Calls      : in out FT.UString_Vectors.Vector);

      function Called_Subprograms_Mention_Name
        (Item_Subprogram : CM.Resolved_Subprogram) return Boolean;

      procedure Add_Call_Name
        (Calls : in out FT.UString_Vectors.Vector;
         Name  : String) is
      begin
         if Name'Length > 0 and then not Contains_Name (Calls, Name) then
            Calls.Append (FT.To_UString (Name));
         end if;
      end Add_Call_Name;

      procedure Collect_Call_Names_From_Expr
        (Expr  : CM.Expr_Access;
         Calls : in out FT.UString_Vectors.Vector)
      is
      begin
         if Expr = null then
            return;
         end if;

         if Expr.Kind = CM.Expr_Call and then Expr.Callee /= null then
            Add_Call_Name (Calls, FT.Lowercase (CM.Flatten_Name (Expr.Callee)));
         end if;

         Collect_Call_Names_From_Expr (Expr.Prefix, Calls);
         Collect_Call_Names_From_Expr (Expr.Callee, Calls);
         Collect_Call_Names_From_Expr (Expr.Inner, Calls);
         Collect_Call_Names_From_Expr (Expr.Left, Calls);
         Collect_Call_Names_From_Expr (Expr.Right, Calls);
         Collect_Call_Names_From_Expr (Expr.Value, Calls);
         Collect_Call_Names_From_Expr (Expr.Target, Calls);
         for Arg of Expr.Args loop
            Collect_Call_Names_From_Expr (Arg, Calls);
         end loop;
         for Field of Expr.Fields loop
            Collect_Call_Names_From_Expr (Field.Expr, Calls);
         end loop;
         for Element of Expr.Elements loop
            Collect_Call_Names_From_Expr (Element, Calls);
         end loop;
      end Collect_Call_Names_From_Expr;

      procedure Collect_Call_Names_From_Statements
        (Statements : CM.Statement_Access_Vectors.Vector;
         Calls      : in out FT.UString_Vectors.Vector)
      is
      begin
         for Item of Statements loop
            if Item = null then
               null;
            else
               case Item.Kind is
                  when CM.Stmt_Object_Decl =>
                     Collect_Call_Names_From_Expr (Item.Decl.Initializer, Calls);
                  when CM.Stmt_Destructure_Decl =>
                     Collect_Call_Names_From_Expr (Item.Destructure.Initializer, Calls);
                  when CM.Stmt_Assign =>
                     Collect_Call_Names_From_Expr (Item.Target, Calls);
                     Collect_Call_Names_From_Expr (Item.Value, Calls);
                  when CM.Stmt_Call =>
                     Collect_Call_Names_From_Expr (Item.Call, Calls);
                  when CM.Stmt_Return =>
                     Collect_Call_Names_From_Expr (Item.Value, Calls);
                  when CM.Stmt_If =>
                     Collect_Call_Names_From_Expr (Item.Condition, Calls);
                     Collect_Call_Names_From_Statements (Item.Then_Stmts, Calls);
                     for Part of Item.Elsifs loop
                        Collect_Call_Names_From_Expr (Part.Condition, Calls);
                        Collect_Call_Names_From_Statements (Part.Statements, Calls);
                     end loop;
                     if Item.Has_Else then
                        Collect_Call_Names_From_Statements (Item.Else_Stmts, Calls);
                     end if;
                  when CM.Stmt_Case =>
                     Collect_Call_Names_From_Expr (Item.Case_Expr, Calls);
                     for Arm of Item.Case_Arms loop
                        Collect_Call_Names_From_Expr (Arm.Choice, Calls);
                        Collect_Call_Names_From_Statements (Arm.Statements, Calls);
                     end loop;
                  when CM.Stmt_While | CM.Stmt_For | CM.Stmt_Loop =>
                     Collect_Call_Names_From_Expr (Item.Condition, Calls);
                     Collect_Call_Names_From_Expr (Item.Loop_Range.Name_Expr, Calls);
                     Collect_Call_Names_From_Expr (Item.Loop_Range.Low_Expr, Calls);
                     Collect_Call_Names_From_Expr (Item.Loop_Range.High_Expr, Calls);
                     Collect_Call_Names_From_Expr (Item.Loop_Iterable, Calls);
                     Collect_Call_Names_From_Statements (Item.Body_Stmts, Calls);
                  when CM.Stmt_Send =>
                     Collect_Call_Names_From_Expr (Item.Channel_Name, Calls);
                     Collect_Call_Names_From_Expr (Item.Value, Calls);
                     Collect_Call_Names_From_Expr (Item.Success_Var, Calls);
                  when CM.Stmt_Receive =>
                     Collect_Call_Names_From_Expr (Item.Channel_Name, Calls);
                     Collect_Call_Names_From_Expr (Item.Target, Calls);
                  when CM.Stmt_Try_Send =>
                     Raise_Internal ("unreachable: try_send rejected by resolver");
                  when CM.Stmt_Try_Receive =>
                     Collect_Call_Names_From_Expr (Item.Channel_Name, Calls);
                     Collect_Call_Names_From_Expr (Item.Target, Calls);
                     Collect_Call_Names_From_Expr (Item.Success_Var, Calls);
                  when CM.Stmt_Select =>
                     for Arm of Item.Arms loop
                        case Arm.Kind is
                           when CM.Select_Arm_Channel =>
                              Collect_Call_Names_From_Expr (Arm.Channel_Data.Channel_Name, Calls);
                              Collect_Call_Names_From_Statements (Arm.Channel_Data.Statements, Calls);
                           when CM.Select_Arm_Delay =>
                              Collect_Call_Names_From_Expr (Arm.Delay_Data.Duration_Expr, Calls);
                              Collect_Call_Names_From_Statements (Arm.Delay_Data.Statements, Calls);
                           when others =>
                              null;
                        end case;
                     end loop;
                  when CM.Stmt_Delay =>
                     Collect_Call_Names_From_Expr (Item.Value, Calls);
                  when others =>
                     null;
               end case;
            end if;
         end loop;
      end Collect_Call_Names_From_Statements;

      function Called_Subprograms_Mention_Name
        (Item_Subprogram : CM.Resolved_Subprogram) return Boolean
      is
         Calls : FT.UString_Vectors.Vector;
      begin
         for Decl of Item_Subprogram.Declarations loop
            Collect_Call_Names_From_Expr (Decl.Initializer, Calls);
         end loop;
         Collect_Call_Names_From_Statements (Item_Subprogram.Statements, Calls);

         for Called of Calls loop
            declare
               Called_Name : constant String := FT.Lowercase (FT.To_String (Called));
            begin
               if Called_Name'Length = 0 then
                  null;
               else
                  for Candidate of Unit.Subprograms loop
                     declare
                        Candidate_Name : constant String := FT.Lowercase (FT.To_String (Candidate.Name));
                        Qualified_Candidate_Name : constant String :=
                          FT.Lowercase (FT.To_String (Unit.Package_Name) & "." & FT.To_String (Candidate.Name));
                     begin
                        if Called_Name = Candidate_Name
                          or else Called_Name = Qualified_Candidate_Name
                        then
                           if not Contains_Name (Visited_Calls, Candidate_Name) then
                              Visited_Calls.Append (FT.To_UString (Candidate_Name));
                              if Subprogram_Uses_Global_Name (Unit, Candidate, Name) then
                                 return True;
                              end if;
                           end if;
                           exit;
                        end if;
                     end;
                  end loop;
               end if;
            end;
         end loop;

         return False;
      end Called_Subprograms_Mention_Name;
   begin
      if Name'Length = 0 then
         return False;
      end if;

      for Decl of Subprogram.Declarations loop
         if Expr_Uses_Name (Decl.Initializer, Name) then
            return True;
         end if;
      end loop;

      return
        Statements_Use_Name (Subprogram.Statements, Name)
        or else Called_Subprograms_Mention_Name (Subprogram);
   end Subprogram_Uses_Global_Name;

   function Render_Initializes_Aspect
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Bronze   : MB.Bronze_Result) return String
   is
      pragma Unreferenced (Document);
      Items : FT.UString_Vectors.Vector;
      Dispatcher_Names : FT.UString_Vectors.Vector;
      Timer_Names : FT.UString_Vectors.Vector;

      procedure Add_Unique (Name : String) is
      begin
         if Name'Length > 0 and then not Contains_Name (Items, Name) then
            Items.Append (FT.To_UString (Name));
         end if;
      end Add_Unique;
   begin
      for Item of Bronze.Initializes loop
         if Is_Aspect_State_Name (FT.To_String (Item))
           and then not Is_Constant_Object_Name (Unit, FT.To_String (Item))
         then
            Add_Unique (FT.To_String (Item));
         end if;
      end loop;

      for Channel of Unit.Channels loop
         Add_Unique (FT.To_String (Channel.Name));
      end loop;

      for Task_Item of Unit.Tasks loop
         Add_Unique (FT.To_String (Task_Item.Name));
      end loop;

      Collect_Select_Dispatcher_Names (Unit.Statements, Dispatcher_Names);
      Collect_Select_Delay_Timer_Names (Unit.Statements, Timer_Names);
      for Task_Item of Unit.Tasks loop
         Collect_Select_Dispatcher_Names
           (Task_Item.Statements,
            Dispatcher_Names);
         Collect_Select_Delay_Timer_Names
           (Task_Item.Statements,
            Timer_Names);
      end loop;

      for Decl of Unit.Objects loop
         if not Decl.Is_Constant and then not Decl.Is_Shared then
            for Name of Decl.Names loop
               Add_Unique (FT.To_String (Name));
            end loop;
         elsif Decl.Is_Shared
           and then not Decl.Is_Public
           and then not Decl.Names.Is_Empty
         then
            Add_Unique
              (Shared_Wrapper_Object_Name
                 (FT.To_String (Decl.Names (Decl.Names.First_Index))));
         end if;
      end loop;

      if Items.Is_Empty then
         return "null";
      elsif Items.Length = 1 then
         return FT.To_String (Items (Items.First_Index));
      end if;
      return "(" & Join_Names (Items) & ")";
   end Render_Initializes_Aspect;

   function Render_Global_Aspect
     (Unit       : CM.Resolved_Unit;
      Subprogram : CM.Resolved_Subprogram;
      Summary    : MB.Graph_Summary;
      Bronze     : MB.Bronze_Result) return String
   is
      pragma Unreferenced (Bronze);
      Inputs  : FT.UString_Vectors.Vector;
      Outputs : FT.UString_Vectors.Vector;
      In_Outs : FT.UString_Vectors.Vector;

      function Contains
        (Items : FT.UString_Vectors.Vector;
         Name  : String) return Boolean is
      begin
         for Item of Items loop
            if FT.To_String (Item) = Name then
               return True;
            end if;
         end loop;
         return False;
      end Contains;

      procedure Add_Unique
        (Items : in out FT.UString_Vectors.Vector;
         Name  : String) is
      begin
         if not Contains (Items, Name) then
            Items.Append (FT.To_UString (Name));
         end if;
      end Add_Unique;

      function Is_Shared_Wrapper_Name (Name : String) return Boolean is
      begin
         for Decl of Unit.Objects loop
            if Decl.Is_Shared and then not Decl.Names.Is_Empty then
               if Shared_Wrapper_Object_Name
                    (FT.To_String (Decl.Names (Decl.Names.First_Index))) = Name
               then
                  return True;
               end if;
            end if;
         end loop;
         return False;
      end Is_Shared_Wrapper_Name;

      function Try_Shared_Public_Helper
        (Name         : String;
         Wrapper_Name : out FT.UString;
         Operation    : out FT.UString) return Boolean is
      begin
         Wrapper_Name := FT.To_UString ("");
         Operation := FT.To_UString ("");
         for Decl of Unit.Objects loop
            if Decl.Is_Shared
              and then Decl.Is_Public
              and then not Decl.Names.Is_Empty
            then
               declare
                  Root_Name    : constant String :=
                    FT.To_String (Decl.Names (Decl.Names.First_Index));
                  Candidate_Wrapper : constant String :=
                    Shared_Wrapper_Object_Name (Root_Name);
                  Prefix      : constant String :=
                    Shared_Public_Helper_Base_Name (Root_Name) & "_";
               begin
                  if Starts_With (Name, Prefix) and then Name'Length > Prefix'Length then
                     Wrapper_Name := FT.To_UString (Candidate_Wrapper);
                     Operation := FT.To_UString (Name (Prefix'Length + 1 .. Name'Last));
                     return True;
                  end if;
               end;
            end if;
         end loop;

         return False;
      end Try_Shared_Public_Helper;

      procedure Mark_Shared_Call
        (Wrapper_Name  : String;
         Selector_Name : String;
         Reads         : in out FT.UString_Vectors.Vector;
         Writes        : in out FT.UString_Vectors.Vector) is
      begin
         if Wrapper_Name'Length = 0 then
            return;
         end if;

         if Selector_Name = Shared_Pop_Last_Name
           or else Selector_Name = Shared_Remove_Name
         then
            Add_Unique (Reads, Wrapper_Name);
            Add_Unique (Writes, Wrapper_Name);
         elsif Selector_Name = Shared_Append_Name
           or else Selector_Name = Shared_Set_Name
           or else Selector_Name = "Initialize"
           or else Starts_With (Selector_Name, "Set_")
         then
            Add_Unique (Writes, Wrapper_Name);
         elsif Selector_Name = Shared_Contains_Name
           or else Starts_With (Selector_Name, "Get_")
         then
            Add_Unique (Reads, Wrapper_Name);
         end if;
      end Mark_Shared_Call;

      procedure Collect_Shared_From_Expr
        (Expr   : CM.Expr_Access;
         Reads  : in out FT.UString_Vectors.Vector;
         Writes : in out FT.UString_Vectors.Vector);
      procedure Collect_Shared_From_Statements
        (Statements : CM.Statement_Access_Vectors.Vector;
         Reads      : in out FT.UString_Vectors.Vector;
         Writes     : in out FT.UString_Vectors.Vector);

      procedure Collect_Shared_From_Expr
        (Expr   : CM.Expr_Access;
         Reads  : in out FT.UString_Vectors.Vector;
         Writes : in out FT.UString_Vectors.Vector)
      is
      begin
         if Expr = null then
            return;
         end if;

         case Expr.Kind is
            when CM.Expr_Ident =>
               declare
                  Name : constant String := FT.To_String (Expr.Name);
               begin
                  if Is_Shared_Wrapper_Name (Name) then
                     Add_Unique (Reads, Name);
                  end if;
               end;
            when CM.Expr_Select =>
               Collect_Shared_From_Expr (Expr.Prefix, Reads, Writes);
            when CM.Expr_Resolved_Index =>
               Collect_Shared_From_Expr (Expr.Prefix, Reads, Writes);
               for Arg of Expr.Args loop
                  Collect_Shared_From_Expr (Arg, Reads, Writes);
               end loop;
            when CM.Expr_Call =>
               if Expr.Callee /= null then
                  declare
                     Wrapper_Name  : FT.UString := FT.To_UString ("");
                     Selector_Name : FT.UString := FT.To_UString ("");
                  begin
                     if Expr.Callee.Kind = CM.Expr_Select
                       and then Expr.Callee.Prefix /= null
                       and then Expr.Callee.Prefix.Kind = CM.Expr_Ident
                       and then Is_Shared_Wrapper_Name
                         (FT.To_String (Expr.Callee.Prefix.Name))
                     then
                        Wrapper_Name := Expr.Callee.Prefix.Name;
                        Selector_Name := Expr.Callee.Selector;
                     elsif Expr.Callee.Kind = CM.Expr_Ident then
                        if Try_Shared_Public_Helper
                          (FT.To_String (Expr.Callee.Name),
                           Wrapper_Name,
                           Selector_Name)
                        then
                           null;
                        end if;
                     elsif Expr.Callee.Kind = CM.Expr_Select then
                        if Try_Shared_Public_Helper
                          (CM.Flatten_Name (Expr.Callee),
                           Wrapper_Name,
                           Selector_Name)
                        then
                           null;
                        end if;
                     end if;

                     if FT.To_String (Wrapper_Name)'Length > 0 then
                        Mark_Shared_Call
                          (FT.To_String (Wrapper_Name),
                           FT.To_String (Selector_Name),
                           Reads,
                           Writes);
                     end if;
                  end;
               end if;
               Collect_Shared_From_Expr (Expr.Prefix, Reads, Writes);
               Collect_Shared_From_Expr (Expr.Callee, Reads, Writes);
               for Arg of Expr.Args loop
                  Collect_Shared_From_Expr (Arg, Reads, Writes);
               end loop;
            when CM.Expr_Conversion | CM.Expr_Annotated | CM.Expr_Unary =>
               Collect_Shared_From_Expr (Expr.Inner, Reads, Writes);
               Collect_Shared_From_Expr (Expr.Target, Reads, Writes);
            when CM.Expr_Binary =>
               Collect_Shared_From_Expr (Expr.Left, Reads, Writes);
               Collect_Shared_From_Expr (Expr.Right, Reads, Writes);
            when CM.Expr_Aggregate =>
               for Field of Expr.Fields loop
                  Collect_Shared_From_Expr (Field.Expr, Reads, Writes);
               end loop;
            when CM.Expr_Tuple | CM.Expr_Array_Literal =>
               for Item of Expr.Elements loop
                  Collect_Shared_From_Expr (Item, Reads, Writes);
               end loop;
            when others =>
               null;
         end case;
      end Collect_Shared_From_Expr;

      procedure Collect_Shared_From_Statements
        (Statements : CM.Statement_Access_Vectors.Vector;
         Reads      : in out FT.UString_Vectors.Vector;
         Writes     : in out FT.UString_Vectors.Vector)
      is
      begin
         for Item of Statements loop
            if Item /= null then
               case Item.Kind is
                  when CM.Stmt_Object_Decl =>
                     Collect_Shared_From_Expr (Item.Decl.Initializer, Reads, Writes);
                  when CM.Stmt_Destructure_Decl =>
                     Collect_Shared_From_Expr (Item.Destructure.Initializer, Reads, Writes);
                  when CM.Stmt_Assign =>
                     Collect_Shared_From_Expr (Item.Target, Reads, Writes);
                     Collect_Shared_From_Expr (Item.Value, Reads, Writes);
                  when CM.Stmt_Call =>
                     Collect_Shared_From_Expr (Item.Call, Reads, Writes);
                  when CM.Stmt_Return | CM.Stmt_Delay =>
                     Collect_Shared_From_Expr (Item.Value, Reads, Writes);
                  when CM.Stmt_If =>
                     Collect_Shared_From_Expr (Item.Condition, Reads, Writes);
                     Collect_Shared_From_Statements (Item.Then_Stmts, Reads, Writes);
                     for Part of Item.Elsifs loop
                        Collect_Shared_From_Expr (Part.Condition, Reads, Writes);
                        Collect_Shared_From_Statements (Part.Statements, Reads, Writes);
                     end loop;
                     if Item.Has_Else then
                        Collect_Shared_From_Statements (Item.Else_Stmts, Reads, Writes);
                     end if;
                  when CM.Stmt_Case =>
                     Collect_Shared_From_Expr (Item.Case_Expr, Reads, Writes);
                     for Arm of Item.Case_Arms loop
                        Collect_Shared_From_Statements (Arm.Statements, Reads, Writes);
                     end loop;
                  when CM.Stmt_While =>
                     Collect_Shared_From_Expr (Item.Condition, Reads, Writes);
                     Collect_Shared_From_Statements (Item.Body_Stmts, Reads, Writes);
                  when CM.Stmt_For | CM.Stmt_Loop =>
                     Collect_Shared_From_Expr (Item.Loop_Range.Name_Expr, Reads, Writes);
                     Collect_Shared_From_Expr (Item.Loop_Range.Low_Expr, Reads, Writes);
                     Collect_Shared_From_Expr (Item.Loop_Range.High_Expr, Reads, Writes);
                     Collect_Shared_From_Expr (Item.Loop_Iterable, Reads, Writes);
                     Collect_Shared_From_Statements (Item.Body_Stmts, Reads, Writes);
                  when CM.Stmt_Send =>
                     Collect_Shared_From_Expr (Item.Channel_Name, Reads, Writes);
                     Collect_Shared_From_Expr (Item.Value, Reads, Writes);
                     Collect_Shared_From_Expr (Item.Success_Var, Reads, Writes);
                  when CM.Stmt_Receive =>
                     Collect_Shared_From_Expr (Item.Channel_Name, Reads, Writes);
                     Collect_Shared_From_Expr (Item.Target, Reads, Writes);
                     Collect_Shared_From_Expr (Item.Success_Var, Reads, Writes);
                  when CM.Stmt_Try_Send =>
                     Raise_Internal ("unreachable: try_send rejected by resolver");
                  when CM.Stmt_Try_Receive =>
                     Collect_Shared_From_Expr (Item.Channel_Name, Reads, Writes);
                     Collect_Shared_From_Expr (Item.Target, Reads, Writes);
                     Collect_Shared_From_Expr (Item.Success_Var, Reads, Writes);
                  when CM.Stmt_Match =>
                     Collect_Shared_From_Expr (Item.Match_Expr, Reads, Writes);
                     for Arm of Item.Match_Arms loop
                        Collect_Shared_From_Statements (Arm.Statements, Reads, Writes);
                     end loop;
                  when CM.Stmt_Select =>
                     for Arm of Item.Arms loop
                        case Arm.Kind is
                           when CM.Select_Arm_Channel =>
                              Collect_Shared_From_Expr (Arm.Channel_Data.Channel_Name, Reads, Writes);
                              Collect_Shared_From_Statements (Arm.Channel_Data.Statements, Reads, Writes);
                           when CM.Select_Arm_Delay =>
                              Collect_Shared_From_Expr (Arm.Delay_Data.Duration_Expr, Reads, Writes);
                              Collect_Shared_From_Statements (Arm.Delay_Data.Statements, Reads, Writes);
                           when others =>
                              null;
                        end case;
                     end loop;
                  when others =>
                     null;
               end case;
            end if;
         end loop;
      end Collect_Shared_From_Statements;

      Result : SU.Unbounded_String := SU.To_Unbounded_String ("");
      First  : Boolean := True;
   begin
      for Item of Summary.Reads loop
         declare
            Name : constant String := Normalize_Aspect_Name ("", FT.To_String (Item));
         begin
            if Starts_With (FT.To_String (Item), "param:")
              or else FT.To_String (Item) = "return"
              or else not Is_Aspect_State_Name (Name)
              or else Is_Constant_Object_Name (Unit, Name)
            then
               null;
            elsif Contains (Summary.Writes, FT.To_String (Item)) then
               Add_Unique (In_Outs, Name);
            elsif not Subprogram_Uses_Global_Name (Unit, Subprogram, Name) then
               null;
            else
               Add_Unique (Inputs, Name);
            end if;
         end;
      end loop;

      for Item of Summary.Writes loop
         declare
            Name : constant String := Normalize_Aspect_Name ("", FT.To_String (Item));
         begin
            if Starts_With (FT.To_String (Item), "param:")
              or else FT.To_String (Item) = "return"
              or else not Is_Aspect_State_Name (Name)
              or else Is_Constant_Object_Name (Unit, Name)
            then
               null;
            elsif not Contains (Summary.Reads, FT.To_String (Item)) then
               Add_Unique (Outputs, Name);
            end if;
         end;
      end loop;

      for Item of Summary.Channels loop
         declare
            Name : constant String := Normalize_Aspect_Name ("", FT.To_String (Item));
         begin
            if Is_Aspect_State_Name (Name) then
               Add_Unique (In_Outs, Name);
            end if;
         end;
      end loop;

      declare
         Shared_Reads  : FT.UString_Vectors.Vector;
         Shared_Writes : FT.UString_Vectors.Vector;
      begin
         for Decl of Subprogram.Declarations loop
            Collect_Shared_From_Expr (Decl.Initializer, Shared_Reads, Shared_Writes);
         end loop;
         Collect_Shared_From_Statements (Subprogram.Statements, Shared_Reads, Shared_Writes);
         for Name of Shared_Reads loop
            if Contains (Shared_Writes, FT.To_String (Name)) then
               Add_Unique (In_Outs, FT.To_String (Name));
            else
               Add_Unique (Inputs, FT.To_String (Name));
            end if;
         end loop;
         for Name of Shared_Writes loop
            if Contains (Shared_Reads, FT.To_String (Name)) then
               Add_Unique (In_Outs, FT.To_String (Name));
            else
               Add_Unique (Outputs, FT.To_String (Name));
            end if;
         end loop;
      end;

      if Inputs.Is_Empty and then Outputs.Is_Empty and then In_Outs.Is_Empty then
         return "null";
      end if;

      if not Inputs.Is_Empty then
         Result :=
           Result
           & SU.To_Unbounded_String
               ((if First then "" else ", ")
                & "Input => "
                & (if Inputs.Length = 1
                   then FT.To_String (Inputs (Inputs.First_Index))
                   else "(" & Join_Names (Inputs) & ")"));
         First := False;
      end if;

      if not Outputs.Is_Empty then
         Result :=
           Result
           & SU.To_Unbounded_String
               ((if First then "" else ", ")
                & "Output => "
                & (if Outputs.Length = 1
                   then FT.To_String (Outputs (Outputs.First_Index))
                   else "(" & Join_Names (Outputs) & ")"));
         First := False;
      end if;

      if not In_Outs.Is_Empty then
         Result :=
           Result
           & SU.To_Unbounded_String
               ((if First then "" else ", ")
                & "In_Out => "
                & (if In_Outs.Length = 1
                   then FT.To_String (In_Outs (In_Outs.First_Index))
                   else "(" & Join_Names (In_Outs) & ")"));
      end if;

      return "(" & SU.To_String (Result) & ")";
   end Render_Global_Aspect;

   function Render_Depends_Aspect
     (Unit       : CM.Resolved_Unit;
      Subprogram : CM.Resolved_Subprogram;
      Summary    : MB.Graph_Summary;
      Bronze     : MB.Bronze_Result) return String
   is
      pragma Unreferenced (Bronze);
      Result : SU.Unbounded_String;
      Allowed_Outputs : FT.UString_Vectors.Vector;
      Allowed_Inputs  : FT.UString_Vectors.Vector;
      Read_Param_Inputs : FT.UString_Vectors.Vector;

      function Contains
        (Items : FT.UString_Vectors.Vector;
         Name  : String) return Boolean is
      begin
         for Item of Items loop
            if FT.To_String (Item) = Name then
               return True;
            end if;
         end loop;
         return False;
      end Contains;

      procedure Add_Unique
        (Items : in out FT.UString_Vectors.Vector;
         Name  : String) is
      begin
         if not Contains (Items, Name) then
            Items.Append (FT.To_UString (Name));
         end if;
      end Add_Unique;

      function Depends_Has_State_Output return Boolean is
      begin
         for Item of Summary.Depends loop
            if not Starts_With (FT.To_String (Item.Output_Name), "param:")
              and then FT.To_String (Item.Output_Name) /= "return"
            then
               return True;
            end if;
         end loop;
         return False;
      end Depends_Has_State_Output;

      function Map_Shared_State_Name (Name : String) return String is
      begin
         for Decl of Unit.Objects loop
            if Decl.Is_Shared and then not Decl.Names.Is_Empty then
               declare
                  Root_Name : constant String :=
                    FT.To_String (Decl.Names (Decl.Names.First_Index));
               begin
                  if Root_Name = Name then
                     return Shared_Wrapper_Object_Name (Root_Name);
                  end if;
               end;
            end if;
         end loop;
         return Name;
      end Map_Shared_State_Name;

      function Is_Shared_Wrapper_State_Name (Name : String) return Boolean is
      begin
         for Decl of Unit.Objects loop
            if Decl.Is_Shared and then not Decl.Names.Is_Empty then
               if Shared_Wrapper_Object_Name
                    (FT.To_String (Decl.Names (Decl.Names.First_Index))) = Name
               then
                  return True;
               end if;
            end if;
         end loop;
         return False;
      end Is_Shared_Wrapper_State_Name;

   begin
      for Param of Subprogram.Params loop
         declare
            Name : constant String := FT.To_String (Param.Name);
            Mode : constant String := FT.To_String (Param.Mode);
         begin
            if Mode = "mut" then
               Add_Unique (Allowed_Outputs, Name);
               Add_Unique (Allowed_Inputs, Name);
            elsif Mode = "out" then
               Add_Unique (Allowed_Outputs, Name);
            elsif Mode = "in out" then
               Add_Unique (Allowed_Outputs, Name);
               Add_Unique (Allowed_Inputs, Name);
            else
               Add_Unique (Allowed_Inputs, Name);
            end if;
         end;
      end loop;

      if Subprogram.Has_Return_Type then
         Add_Unique
           (Allowed_Outputs,
            FT.To_String (Subprogram.Name) & "'Result");
      end if;

      for Item of Summary.Reads loop
         declare
            Name : constant String :=
              Map_Shared_State_Name
                (Normalize_Aspect_Name
                   (FT.To_String (Subprogram.Name), FT.To_String (Item)));
         begin
            if Starts_With (FT.To_String (Item), "param:")
              and then Is_Aspect_State_Name (Name)
            then
               Add_Unique (Read_Param_Inputs, Name);
            end if;
            if not Starts_With (FT.To_String (Item), "param:")
              and then FT.To_String (Item) /= "return"
              and then Is_Aspect_State_Name (Name)
              and then not Is_Constant_Object_Name (Unit, Name)
              and then Subprogram_Uses_Global_Name (Unit, Subprogram, Name)
            then
               Add_Unique (Allowed_Inputs, Name);
            end if;
         end;
      end loop;

      for Item of Summary.Writes loop
         declare
            Name : constant String :=
              Map_Shared_State_Name
                (Normalize_Aspect_Name
                   (FT.To_String (Subprogram.Name), FT.To_String (Item)));
         begin
            if not Starts_With (FT.To_String (Item), "param:")
              and then FT.To_String (Item) /= "return"
              and then Is_Aspect_State_Name (Name)
              and then not Is_Constant_Object_Name (Unit, Name)
            then
               Add_Unique (Allowed_Outputs, Name);
            end if;
         end;
      end loop;

      for Item of Summary.Channels loop
         declare
            Name : constant String :=
              Normalize_Aspect_Name (FT.To_String (Subprogram.Name), FT.To_String (Item));
         begin
            if Is_Aspect_State_Name (Name) then
               Add_Unique (Allowed_Inputs, Name);
            end if;
         end;
      end loop;

      for Item of Summary.Depends loop
         declare
            Output_Name : constant String :=
              Map_Shared_State_Name
                (Normalize_Aspect_Name
                   (FT.To_String (Subprogram.Name), FT.To_String (Item.Output_Name)));
         begin
            if not Starts_With (FT.To_String (Item.Output_Name), "param:")
              and then FT.To_String (Item.Output_Name) /= "return"
              and then Is_Aspect_State_Name (Output_Name)
              and then not Is_Constant_Object_Name (Unit, Output_Name)
            then
               Add_Unique (Allowed_Outputs, Output_Name);
            end if;
            for Input of Item.Inputs loop
               declare
                  Name : constant String :=
                    Map_Shared_State_Name
                      (Normalize_Aspect_Name
                         (FT.To_String (Subprogram.Name), FT.To_String (Input)));
               begin
                  if not Starts_With (FT.To_String (Input), "param:")
                    and then FT.To_String (Input) /= "return"
                    and then Is_Aspect_State_Name (Name)
                    and then not Is_Constant_Object_Name (Unit, Name)
                    and then Subprogram_Uses_Global_Name (Unit, Subprogram, Name)
                  then
                     Add_Unique (Allowed_Inputs, Name);
                  end if;
               end;
            end loop;
         end;
      end loop;

      if not Summary.Channels.Is_Empty then
         return "";
      end if;

      if Summary.Depends.Is_Empty or else not Depends_Has_State_Output then
         return "";
      end if;

      for Index in Summary.Depends.First_Index .. Summary.Depends.Last_Index loop
         declare
            Item : constant MB.Depends_Entry := Summary.Depends (Index);
            Output_Name : constant String :=
              Map_Shared_State_Name
                (Normalize_Aspect_Name
                   (FT.To_String (Subprogram.Name), FT.To_String (Item.Output_Name)));
         begin
            if not Contains (Allowed_Outputs, Output_Name) then
               Raise_Internal
                 ("invalid Depends output `" & Output_Name
                  & "` while emitting `" & FT.To_String (Subprogram.Name) & "`");
            end if;
            if Index /= Summary.Depends.First_Index then
               Result := Result & SU.To_Unbounded_String (", ");
            end if;
            Result := Result & SU.To_Unbounded_String (Output_Name & " => ");
            declare
               Inputs : FT.UString_Vectors.Vector;
            begin
               for Input of Item.Inputs loop
                  declare
                     Input_Text : constant String := FT.To_String (Input);
                     Name : constant String :=
                       Map_Shared_State_Name
                         (Normalize_Aspect_Name
                            (FT.To_String (Subprogram.Name),
                             Input_Text));
                  begin
                     if Starts_With (Input_Text, "param:") then
                        if Contains (Allowed_Inputs, Name) then
                           Add_Unique (Inputs, Name);
                        end if;
                     elsif not Is_Aspect_State_Name (Name)
                       or else Is_Constant_Object_Name (Unit, Name)
                       or else not Subprogram_Uses_Global_Name (Unit, Subprogram, Name)
                     then
                        null;
                     elsif not Contains (Allowed_Inputs, Name) then
                        Raise_Internal
                          ("invalid Depends input `" & Name
                           & "` while emitting `" & FT.To_String (Subprogram.Name) & "`");
                     else
                        Add_Unique (Inputs, Name);
                     end if;
                  end;
               end loop;

               for Channel of Summary.Channels loop
                  declare
                     Name : constant String :=
                       Normalize_Aspect_Name
                         (FT.To_String (Subprogram.Name),
                          FT.To_String (Channel));
                  begin
                     if not Is_Aspect_State_Name (Name) then
                        null;
                     elsif not Contains (Allowed_Inputs, Name) then
                        Raise_Internal
                          ("invalid Depends input `" & Name
                           & "` while emitting `" & FT.To_String (Subprogram.Name) & "`");
                     else
                        Add_Unique (Inputs, Name);
                     end if;
                  end;
               end loop;

               for Input of Read_Param_Inputs loop
                  if Contains (Allowed_Inputs, FT.To_String (Input)) then
                     Add_Unique (Inputs, FT.To_String (Input));
                  end if;
               end loop;

               if Is_Shared_Wrapper_State_Name (Output_Name) then
                  Add_Unique (Inputs, Output_Name);
               end if;

               if Inputs.Is_Empty then
                  Result := Result & SU.To_Unbounded_String ("null");
               elsif Inputs.Length = 1 then
                  Result :=
                    Result
                    & SU.To_Unbounded_String (FT.To_String (Inputs (Inputs.First_Index)));
               else
                  Result :=
                    Result
                    & SU.To_Unbounded_String ("(" & Join_Names (Inputs) & ")");
               end if;
            end;
         end;
      end loop;

      return SU.To_String (Result);
   end Render_Depends_Aspect;

   function Render_Access_Param_Precondition
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram;
      State      : in out Emit_State) return String
   is
      Conditions : FT.UString_Vectors.Vector;
      Bound_Names : FT.UString_Vectors.Vector;

      function Is_Mutable_Param_Name (Name : String) return Boolean is
      begin
         for Param of Subprogram.Params loop
            if FT.To_String (Param.Name) = Name
              and then FT.To_String (Param.Mode) in "mut" | "in out"
            then
               return True;
            end if;
         end loop;
         return False;
      end Is_Mutable_Param_Name;

      function Needs_Non_Null_Param_Check (Name : String) return Boolean is
      begin
         for Param of Subprogram.Params loop
            if FT.To_String (Param.Name) = Name
              and then Is_Owner_Access (Param.Type_Info)
              and then not Param.Type_Info.Not_Null
            then
               return True;
            end if;
         end loop;
         return False;
      end Needs_Non_Null_Param_Check;

      function Is_Param_Name (Name : String) return Boolean is
      begin
         for Param of Subprogram.Params loop
            if FT.To_String (Param.Name) = Name then
               return True;
            end if;
         end loop;
         return False;
      end Is_Param_Name;

      function Expr_Allows_Null
        (Expr       : CM.Expr_Access;
         Param_Name : String) return Boolean
      is
         Operator : constant String :=
           (if Expr = null then "" else Map_Operator (FT.To_String (Expr.Operator)));

         function Is_Direct_Param_Null_Equality return Boolean is
         begin
            return
              ((Expr.Left /= null
                and then Expr.Left.Kind = CM.Expr_Ident
                and then FT.To_String (Expr.Left.Name) = Param_Name
                and then Expr.Right /= null
                and then Expr.Right.Kind = CM.Expr_Null)
               or else
               (Expr.Right /= null
                and then Expr.Right.Kind = CM.Expr_Ident
                and then FT.To_String (Expr.Right.Name) = Param_Name
                and then Expr.Left /= null
                and then Expr.Left.Kind = CM.Expr_Null));
         end Is_Direct_Param_Null_Equality;
      begin
         if Expr = null then
            return False;
         elsif Expr.Kind = CM.Expr_Binary then
            if Operator = "=" then
               return Is_Direct_Param_Null_Equality;
            elsif Operator in "or" | "or else" then
               return
                 Expr_Allows_Null (Expr.Left, Param_Name)
                 or else Expr_Allows_Null (Expr.Right, Param_Name);
            end if;
         end if;
         return False;
      end Expr_Allows_Null;

      function Has_Leading_Null_Return_Guard (Param_Name : String) return Boolean is
      begin
         if Subprogram.Statements.Is_Empty then
            return False;
         end if;

         declare
            First_Stmt : constant CM.Statement_Access := Subprogram.Statements.First_Element;
         begin
            return
              First_Stmt /= null
              and then First_Stmt.Kind = CM.Stmt_If
              and then not First_Stmt.Then_Stmts.Is_Empty
              and then First_Stmt.Then_Stmts.First_Element /= null
              and then First_Stmt.Then_Stmts.First_Element.Kind = CM.Stmt_Return
              and then Expr_Allows_Null (First_Stmt.Condition, Param_Name);
         end;
      end Has_Leading_Null_Return_Guard;

      procedure Add_Unique (Condition : String) is
      begin
         if Condition'Length > 0 and then not Contains_Name (Conditions, Condition) then
            Conditions.Append (FT.To_UString (Condition));
         end if;
      end Add_Unique;

      procedure Add_Bound_Name (Name : String) is
      begin
         if Name'Length > 0 and then not Contains_Name (Bound_Names, Name) then
            Bound_Names.Append (FT.To_UString (Name));
         end if;
      end Add_Bound_Name;

      function Expr_Uses_Bound_Name (Expr : CM.Expr_Access) return Boolean is
      begin
         for Name of Bound_Names loop
            if Expr_Uses_Name (Expr, FT.To_String (Name)) then
               return True;
            end if;
         end loop;
         return False;
      end Expr_Uses_Bound_Name;

      procedure Add_Length_Precondition
        (Prefix     : CM.Expr_Access;
         Min_Length : Long_Long_Integer);

      procedure Collect_Expr (Expr : CM.Expr_Access);
      procedure Collect
        (Statements : CM.Statement_Access_Vectors.Vector);

      procedure Add_Length_Precondition
        (Prefix     : CM.Expr_Access;
         Min_Length : Long_Long_Integer)
      is
         Prefix_Root : constant String := Root_Name (Prefix);
         Prefix_Type : GM.Type_Descriptor := (others => <>);
      begin
         if Prefix = null or else Min_Length <= 0 then
            return;
         elsif Prefix_Root'Length = 0 or else not Is_Param_Name (Prefix_Root) then
            return;
         end if;

         Prefix_Type := Base_Type (Unit, Document, Expr_Type_Info (Unit, Document, Prefix));
         if Is_Growable_Array_Type (Unit, Document, Prefix_Type) then
            State.Needs_Safe_Array_RT := True;
            Add_Unique
              ("("
               & Array_Runtime_Instance_Name (Prefix_Type)
               & ".Length ("
               & Render_Expr (Unit, Document, Prefix, State)
               & ") >= "
               & Trim_Image (Min_Length)
               & ")");
         elsif Is_Bounded_String_Type (Prefix_Type) then
            Register_Bounded_String_Type (State, Prefix_Type);
            Add_Unique
              ("("
               & Bounded_String_Instance_Name (Prefix_Type)
               & ".Length ("
               & Render_Expr (Unit, Document, Prefix, State)
               & ") >= "
               & Trim_Image (Min_Length)
               & ")");
         elsif Is_Plain_String_Type (Unit, Document, Prefix_Type) then
            State.Needs_Safe_String_RT := True;
            Add_Unique
              ("(Safe_String_RT.Length ("
               & Render_Heap_String_Expr (Unit, Document, Prefix, State)
               & ") >= "
               & Trim_Image (Min_Length)
               & ")");
         end if;
      end Add_Length_Precondition;

      procedure Collect_Expr (Expr : CM.Expr_Access) is
         Index_Value : Long_Long_Integer := 0;
         High_Value  : Long_Long_Integer := 0;
      begin
         if Expr = null then
            return;
         end if;

         case Expr.Kind is
            when CM.Expr_Select | CM.Expr_Resolved_Index =>
               if Expr.Prefix /= null
                 and then Needs_Implicit_Dereference (Unit, Document, Expr.Prefix)
               then
                  declare
                     Param_Name : constant String := Root_Name (Expr.Prefix);
                  begin
                     if Param_Name'Length > 0
                       and then Needs_Non_Null_Param_Check (Param_Name)
                       and then not Has_Leading_Null_Return_Guard (Param_Name)
                     then
                        Add_Unique ("(" & Param_Name & " /= null)");
                     end if;
                  end;
               end if;
               if Expr.Kind = CM.Expr_Resolved_Index and then Expr.Prefix /= null then
                  if Natural (Expr.Args.Length) = 1
                    and then Try_Static_Integer_Value
                      (Expr.Args (Expr.Args.First_Index),
                       Index_Value)
                  then
                     Add_Length_Precondition (Expr.Prefix, Index_Value);
                  elsif Natural (Expr.Args.Length) = 2
                    and then Try_Static_Integer_Value
                      (Expr.Args (Expr.Args.First_Index + 1),
                       High_Value)
                  then
                     Add_Length_Precondition (Expr.Prefix, High_Value);
                  end if;
               end if;
            when others =>
               null;
         end case;

         Collect_Expr (Expr.Prefix);
         Collect_Expr (Expr.Callee);
         Collect_Expr (Expr.Inner);
         Collect_Expr (Expr.Left);
         Collect_Expr (Expr.Right);
         Collect_Expr (Expr.Value);
         Collect_Expr (Expr.Target);
         for Arg of Expr.Args loop
            Collect_Expr (Arg);
         end loop;
         for Field of Expr.Fields loop
            Collect_Expr (Field.Expr);
         end loop;
         for Element of Expr.Elements loop
            Collect_Expr (Element);
         end loop;
      end Collect_Expr;

      procedure Collect
        (Statements : CM.Statement_Access_Vectors.Vector) is
      begin
         for Item of Statements loop
            if Item = null then
               null;
            else
               case Item.Kind is
                  when CM.Stmt_Assign =>
                     declare
                        Target_Name : constant String := Root_Name (Item.Target);
                        Target_Info : constant GM.Type_Descriptor :=
                          Base_Type (Unit, Document, Expr_Type_Info (Unit, Document, Item.Target));
                        Target_Type : constant String := Render_Type_Name (Target_Info);
                     begin
                        if Target_Name'Length > 0
                          and then Is_Mutable_Param_Name (Target_Name)
                          and then Is_Integer_Type (Unit, Document, Target_Info)
                          and then not Expr_Uses_Bound_Name (Item.Value)
                        then
                           declare
                              Wide_Image : constant String :=
                                Render_Wide_Expr (Unit, Document, Item.Value, State);
                           begin
                              Add_Unique
                                ("("
                                 & Wide_Image
                                 & " >= Safe_Runtime.Wide_Integer ("
                                 & Target_Type
                                 & "'First) and then "
                                 & Wide_Image
                                 & " <= Safe_Runtime.Wide_Integer ("
                                 & Target_Type
                                 & "'Last))");
                           end;
                        end if;
                        Collect_Expr (Item.Target);
                        Collect_Expr (Item.Value);
                     end;
                  when CM.Stmt_Call =>
                     Collect_Expr (Item.Call);
                  when CM.Stmt_Return =>
                     Collect_Expr (Item.Value);
                  when CM.Stmt_If =>
                     Collect_Expr (Item.Condition);
                     Collect (Item.Then_Stmts);
                     for Part of Item.Elsifs loop
                        Collect_Expr (Part.Condition);
                        Collect (Part.Statements);
                     end loop;
                     if Item.Has_Else then
                        Collect (Item.Else_Stmts);
                     end if;
                  when CM.Stmt_Case =>
                     Collect_Expr (Item.Case_Expr);
                     for Arm of Item.Case_Arms loop
                        Collect_Expr (Arm.Choice);
                        Collect (Arm.Statements);
                     end loop;
                  when CM.Stmt_While | CM.Stmt_For | CM.Stmt_Loop =>
                     declare
                        Bound_Count : constant Ada.Containers.Count_Type :=
                          Bound_Names.Length;
                     begin
                        Collect_Expr (Item.Condition);
                        Collect_Expr (Item.Loop_Range.Name_Expr);
                        Collect_Expr (Item.Loop_Range.Low_Expr);
                        Collect_Expr (Item.Loop_Range.High_Expr);
                        Collect_Expr (Item.Loop_Iterable);
                        if Item.Kind = CM.Stmt_For then
                           Add_Bound_Name (FT.To_String (Item.Loop_Var));
                        end if;
                        Collect (Item.Body_Stmts);
                        Bound_Names.Set_Length (Bound_Count);
                     end;
                  when CM.Stmt_Object_Decl =>
                     Collect_Expr (Item.Decl.Initializer);
                     for Name of Item.Decl.Names loop
                        Add_Bound_Name (FT.To_String (Name));
                     end loop;
                  when CM.Stmt_Destructure_Decl =>
                     Collect_Expr (Item.Destructure.Initializer);
                     for Name of Item.Destructure.Names loop
                        Add_Bound_Name (FT.To_String (Name));
                     end loop;
                  when CM.Stmt_Send | CM.Stmt_Receive | CM.Stmt_Try_Receive =>
                     Collect_Expr (Item.Channel_Name);
                     Collect_Expr (Item.Value);
                     Collect_Expr (Item.Target);
                     Collect_Expr (Item.Success_Var);
                  when CM.Stmt_Try_Send =>
                     Raise_Internal ("unreachable: try_send rejected by resolver");
                  when CM.Stmt_Select =>
                     for Arm of Item.Arms loop
                        case Arm.Kind is
                           when CM.Select_Arm_Channel =>
                              Collect_Expr (Arm.Channel_Data.Channel_Name);
                              Collect (Arm.Channel_Data.Statements);
                           when CM.Select_Arm_Delay =>
                              Collect_Expr (Arm.Delay_Data.Duration_Expr);
                              Collect (Arm.Delay_Data.Statements);
                           when others =>
                              null;
                        end case;
                     end loop;
                  when CM.Stmt_Delay =>
                     Collect_Expr (Item.Value);
                  when others =>
                     null;
               end case;
            end if;
         end loop;
      end Collect;

      Result : SU.Unbounded_String;
   begin
      for Param of Subprogram.Params loop
         if Is_Float_Type (Unit, Document, Param.Type_Info)
           and then Param.Type_Info.Has_Float_Low_Text
           and then Param.Type_Info.Has_Float_High_Text
         then
            Add_Unique
              ("("
               & FT.To_String (Param.Name)
               & " >= "
               & FT.To_String (Param.Type_Info.Float_Low_Text)
               & " and then "
               & FT.To_String (Param.Name)
               & " <= "
               & FT.To_String (Param.Type_Info.Float_High_Text)
               & ")");
         end if;
      end loop;
      for Decl of Subprogram.Declarations loop
         for Name of Decl.Names loop
            Add_Bound_Name (FT.To_String (Name));
         end loop;
      end loop;
      Collect (Subprogram.Statements);
      for Index in Conditions.First_Index .. Conditions.Last_Index loop
         if Index /= Conditions.First_Index then
            Result := Result & SU.To_Unbounded_String (" and then ");
         end if;
         Result := Result & SU.To_Unbounded_String (FT.To_String (Conditions (Index)));
      end loop;
      return SU.To_String (Result);
   end Render_Access_Param_Precondition;

   function Exprs_Match
     (Left  : CM.Expr_Access;
      Right : CM.Expr_Access) return Boolean
   is
   begin
      if Left = null or else Right = null then
         return Left = Right;
      elsif Left.Kind /= Right.Kind then
         return False;
      end if;

      case Left.Kind is
         when CM.Expr_Int =>
            return FT.To_String (Left.Text) = FT.To_String (Right.Text)
              and then Left.Int_Value = Right.Int_Value;
         when CM.Expr_Real =>
            return FT.To_String (Left.Text) = FT.To_String (Right.Text);
         when CM.Expr_String =>
            return FT.To_String (Left.Text) = FT.To_String (Right.Text);
         when CM.Expr_Bool =>
            return Left.Bool_Value = Right.Bool_Value;
         when CM.Expr_Null =>
            return True;
         when CM.Expr_Ident =>
            return FT.To_String (Left.Name) = FT.To_String (Right.Name);
         when CM.Expr_Select =>
            return FT.To_String (Left.Selector) = FT.To_String (Right.Selector)
              and then Exprs_Match (Left.Prefix, Right.Prefix);
         when CM.Expr_Resolved_Index =>
            if not Exprs_Match (Left.Prefix, Right.Prefix)
              or else Left.Args.Length /= Right.Args.Length
            then
               return False;
            end if;
            for Index in Left.Args.First_Index .. Left.Args.Last_Index loop
               if not Exprs_Match (Left.Args (Index), Right.Args (Index)) then
                  return False;
               end if;
            end loop;
            return True;
         when CM.Expr_Conversion | CM.Expr_Annotated =>
            return Exprs_Match (Left.Target, Right.Target)
              and then Exprs_Match (Left.Inner, Right.Inner);
         when CM.Expr_Unary =>
            return FT.To_String (Left.Operator) = FT.To_String (Right.Operator)
              and then Exprs_Match (Left.Inner, Right.Inner);
         when CM.Expr_Binary =>
            return FT.To_String (Left.Operator) = FT.To_String (Right.Operator)
              and then Exprs_Match (Left.Left, Right.Left)
              and then Exprs_Match (Left.Right, Right.Right);
         when others =>
            return False;
      end case;
   end Exprs_Match;

   function Expr_Contains_Target
     (Expr   : CM.Expr_Access;
      Target : CM.Expr_Access) return Boolean
   is
   begin
      if Expr = null or else Target = null then
         return False;
      elsif Exprs_Match (Expr, Target) then
         return True;
      end if;

      case Expr.Kind is
         when CM.Expr_Select =>
            return Expr_Contains_Target (Expr.Prefix, Target);
         when CM.Expr_Resolved_Index | CM.Expr_Call =>
            if Expr_Contains_Target (Expr.Prefix, Target)
              or else Expr_Contains_Target (Expr.Callee, Target)
            then
               return True;
            end if;
            for Item of Expr.Args loop
               if Expr_Contains_Target (Item, Target) then
                  return True;
               end if;
            end loop;
            return False;
         when CM.Expr_Conversion | CM.Expr_Annotated =>
            return
              Expr_Contains_Target (Expr.Target, Target)
              or else Expr_Contains_Target (Expr.Inner, Target);
         when CM.Expr_Unary =>
            return Expr_Contains_Target (Expr.Inner, Target);
         when CM.Expr_Binary =>
            return
              Expr_Contains_Target (Expr.Left, Target)
              or else Expr_Contains_Target (Expr.Right, Target);
         when CM.Expr_Aggregate =>
            for Field of Expr.Fields loop
               if Expr_Contains_Target (Field.Expr, Target) then
                  return True;
               end if;
            end loop;
            return False;
         when others =>
            return False;
      end case;
   end Expr_Contains_Target;

   function Render_Expr_With_Target_Substitution
     (Unit          : CM.Resolved_Unit;
      Document      : GM.Mir_Document;
      Expr          : CM.Expr_Access;
      Target        : CM.Expr_Access;
      Replacement   : String;
      State         : in out Emit_State;
      Supported     : in out Boolean) return String renames AEX.Render_Expr_With_Target_Substitution;
   function Render_Expr_With_Old_Substitution
     (Unit          : CM.Resolved_Unit;
      Document      : GM.Mir_Document;
      Expr          : CM.Expr_Access;
      Target        : CM.Expr_Access;
      State         : in out Emit_State;
      Supported     : in out Boolean) return String renames AEX.Render_Expr_With_Old_Substitution;
   function Render_Access_Param_Postcondition
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram;
      State      : in out Emit_State) return String
   is
      Conditions   : FT.UString_Vectors.Vector;
      Seen_Targets : FT.UString_Vectors.Vector;
      Unsupported  : Boolean := False;

      function Is_Alias_Param_Name (Name : String) return Boolean is
      begin
         for Param of Subprogram.Params loop
            if FT.To_String (Param.Name) = Name
              and then Param.Type_Info.Anonymous
              and then Is_Alias_Access (Param.Type_Info)
              and then not Param.Type_Info.Is_Constant
            then
               return True;
            end if;
         end loop;
         return False;
      end Is_Alias_Param_Name;

      procedure Add_Unique_Equality
        (Target_Expr : CM.Expr_Access;
         Value_Expr  : CM.Expr_Access)
      is
         Target_Image : constant String := Render_Expr (Unit, Document, Target_Expr, State);
         Supported    : Boolean := True;
         Value_Image  : constant String :=
           Render_Expr_With_Old_Substitution
             (Unit, Document, Value_Expr, Target_Expr, State, Supported);
      begin
         if not Supported or else Target_Image'Length = 0 or else Value_Image'Length = 0 then
            Unsupported := True;
            return;
         end if;

         if Contains_Name (Seen_Targets, Target_Image) then
            Unsupported := True;
            return;
         end if;

         Seen_Targets.Append (FT.To_UString (Target_Image));
         Conditions.Append
           (FT.To_UString
              (Target_Image & " = " & Value_Image));
      end Add_Unique_Equality;

      procedure Add_Unique_Condition (Condition : String) is
      begin
         if Condition'Length > 0 and then not Contains_Name (Conditions, Condition) then
            Conditions.Append (FT.To_UString (Condition));
         end if;
      end Add_Unique_Condition;

      Result : SU.Unbounded_String;
   begin
      for Item of Subprogram.Statements loop
         exit when Unsupported;

         if Item = null then
            null;
         else
            case Item.Kind is
               when CM.Stmt_Assign =>
                  declare
                     Target_Name : constant String := Root_Name (Item.Target);
                  begin
                     if Target_Name'Length > 0
                       and then Is_Alias_Param_Name (Target_Name)
                     then
                        Add_Unique_Equality (Item.Target, Item.Value);
                     end if;
                  end;
               when CM.Stmt_If
                  | CM.Stmt_Case
                  | CM.Stmt_While
                  | CM.Stmt_For
                  | CM.Stmt_Loop
                  | CM.Stmt_Select =>
                  Unsupported := True;
               when others =>
                  null;
            end case;
         end if;
      end loop;

      for Param of Subprogram.Params loop
         declare
            Mode : constant String := FT.To_String (Param.Mode);
            Name : constant String := FT.To_String (Param.Name);
         begin
            if Name'Length > 0
              and then Is_Owner_Access (Param.Type_Info)
              and then Mode in "mut" | "in out"
            then
               Add_Unique_Condition (Name & " /= null");
            end if;
         end;
      end loop;

      if Unsupported or else Conditions.Is_Empty then
         return "";
      end if;

      State.Needs_Unevaluated_Use_Of_Old := True;
      for Index in Conditions.First_Index .. Conditions.Last_Index loop
         if Index /= Conditions.First_Index then
            Result := Result & SU.To_Unbounded_String (" and then ");
         end if;
         Result := Result & SU.To_Unbounded_String (FT.To_String (Conditions (Index)));
      end loop;
      return SU.To_String (Result);
   end Render_Access_Param_Postcondition;

   function Render_Subprogram_Aspects
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram;
      Bronze     : MB.Bronze_Result;
      State      : in out Emit_State) return String
     is
      Summary : constant MB.Graph_Summary :=
        Find_Graph_Summary (Bronze, FT.To_String (Subprogram.Name));
      Uses_Structural_Traversal : constant Boolean :=
        Uses_Structural_Traversal_Lowering (Subprogram);
      Global_Image  : constant String :=
        Render_Global_Aspect (Unit, Subprogram, Summary, Bronze);
      Depends_Image : constant String :=
        Render_Depends_Aspect (Unit, Subprogram, Summary, Bronze);
      Pre_Image : constant String :=
        Render_Access_Param_Precondition (Unit, Document, Subprogram, State);
      Post_Image : constant String :=
        Render_Access_Param_Postcondition (Unit, Document, Subprogram, State);
      Structural_Pre_Image : constant String :=
        (if Uses_Structural_Traversal and then Subprogram.Params.Length >= 3
         then
           Structural_Accumulator_Count_Total_Bound
             (Unit,
              Document,
              Subprogram,
              Ada_Safe_Name
                (FT.To_String
                   (Subprogram.Params (Subprogram.Params.First_Index + 1).Name)),
              Ada_Safe_Name
                (FT.To_String
                   (Subprogram.Params (Subprogram.Params.First_Index + 2).Name)),
              State)
         else "");
      Local_Names : FT.UString_Vectors.Vector;
      function Recursive_Variant_Image return String;
      Result : SU.Unbounded_String;
      Has_Aspect : Boolean := False;

      procedure Append_Aspect (Text : String) is
      begin
         if not Has_Aspect then
            Result := Result & SU.To_Unbounded_String (" with " & Text);
            Has_Aspect := True;
         else
            Result :=
              Result
              & SU.To_Unbounded_String
                  ("," & ASCII.LF
                   & Indentation (4)
                   & Text);
         end if;
      end Append_Aspect;

      function Recursive_Variant_Image return String is
         Subprogram_Name : constant String :=
           FT.Lowercase (FT.To_String (Subprogram.Name));

         function Variant_From_Expr (Expr : CM.Expr_Access) return String;
         function Variant_From_Statements
           (Statements : CM.Statement_Access_Vectors.Vector) return String;

         function Variant_From_Expr (Expr : CM.Expr_Access) return String is
            Result : constant String := "";
         begin
            if Expr = null then
               return "";
            end if;

            case Expr.Kind is
               when CM.Expr_Call =>
                  if Expr.Callee /= null
                    and then FT.Lowercase (CM.Flatten_Name (Expr.Callee)) = Subprogram_Name
                  then
                     for Index in Subprogram.Params.First_Index .. Subprogram.Params.Last_Index loop
                        exit when Expr.Args.Is_Empty or else Index > Expr.Args.Last_Index;

                        declare
                           Param      : constant CM.Symbol := Subprogram.Params (Index);
                           Mode       : constant String := FT.Lowercase (FT.To_String (Param.Mode));
                           Param_Name : constant String := FT.To_String (Param.Name);
                           Root       : constant String := Root_Name (Expr.Args (Index));
                        begin
                           if Param_Name'Length > 0
                             and then Root = Param_Name
                             and then Is_Owner_Access (Param.Type_Info)
                             and then Mode /= "mut"
                             and then Mode /= "in out"
                             and then Mode /= "out"
                           then
                              return "Structural => " & Param_Name;
                           end if;
                        end;
                     end loop;
                  end if;

                  declare
                     Callee_Result : constant String := Variant_From_Expr (Expr.Callee);
                  begin
                     if Callee_Result'Length > 0 then
                        return Callee_Result;
                     end if;
                  end;

                  if not Expr.Args.Is_Empty then
                     for Arg of Expr.Args loop
                        declare
                           Arg_Result : constant String := Variant_From_Expr (Arg);
                        begin
                           if Arg_Result'Length > 0 then
                              return Arg_Result;
                           end if;
                        end;
                     end loop;
                  end if;
               when CM.Expr_Select =>
                  return Variant_From_Expr (Expr.Prefix);
               when CM.Expr_Apply
                  | CM.Expr_Resolved_Index
                  | CM.Expr_Tuple
                  | CM.Expr_Array_Literal =>
                  if not Expr.Args.Is_Empty then
                     for Arg of Expr.Args loop
                        declare
                           Arg_Result : constant String := Variant_From_Expr (Arg);
                        begin
                           if Arg_Result'Length > 0 then
                              return Arg_Result;
                           end if;
                        end;
                     end loop;
                  end if;
               when CM.Expr_Conversion
                  | CM.Expr_Annotated
                  | CM.Expr_Unary =>
                  return Variant_From_Expr (Expr.Inner);
               when CM.Expr_Aggregate =>
                  for Field of Expr.Fields loop
                     declare
                        Field_Result : constant String := Variant_From_Expr (Field.Expr);
                     begin
                        if Field_Result'Length > 0 then
                           return Field_Result;
                        end if;
                     end;
                  end loop;
               when CM.Expr_Binary =>
                  declare
                     Left_Result : constant String := Variant_From_Expr (Expr.Left);
                  begin
                     if Left_Result'Length > 0 then
                        return Left_Result;
                     end if;
                  end;
                  return Variant_From_Expr (Expr.Right);
               when others =>
                  null;
            end case;

            return Result;
         end Variant_From_Expr;

         function Variant_From_Statements
           (Statements : CM.Statement_Access_Vectors.Vector) return String
         is
         begin
            for Item of Statements loop
               if Item = null then
                  null;
               else
                  case Item.Kind is
                     when CM.Stmt_Object_Decl =>
                        if Item.Decl.Has_Initializer then
                           declare
                              Initializer_Result : constant String :=
                                Variant_From_Expr (Item.Decl.Initializer);
                           begin
                              if Initializer_Result'Length > 0 then
                                 return Initializer_Result;
                              end if;
                           end;
                        end if;
                     when CM.Stmt_Destructure_Decl =>
                        if Item.Destructure.Has_Initializer then
                           declare
                              Initializer_Result : constant String :=
                                Variant_From_Expr (Item.Destructure.Initializer);
                           begin
                              if Initializer_Result'Length > 0 then
                                 return Initializer_Result;
                              end if;
                           end;
                        end if;
                     when CM.Stmt_Assign =>
                        declare
                           Value_Result : constant String := Variant_From_Expr (Item.Value);
                        begin
                           if Value_Result'Length > 0 then
                              return Value_Result;
                           end if;
                        end;
                     when CM.Stmt_Call | CM.Stmt_Return | CM.Stmt_Send | CM.Stmt_Delay =>
                        declare
                           Call_Result : constant String := Variant_From_Expr (Item.Call);
                           Value_Result : constant String := Variant_From_Expr (Item.Value);
                        begin
                           if Call_Result'Length > 0 then
                              return Call_Result;
                           elsif Value_Result'Length > 0 then
                              return Value_Result;
                           end if;
                        end;
                     when CM.Stmt_Receive | CM.Stmt_Try_Receive =>
                        declare
                           Value_Result : constant String := Variant_From_Expr (Item.Value);
                           Success_Result : constant String := Variant_From_Expr (Item.Success_Var);
                        begin
                           if Value_Result'Length > 0 then
                              return Value_Result;
                           elsif Success_Result'Length > 0 then
                              return Success_Result;
                           end if;
                        end;
                     when CM.Stmt_Try_Send =>
                        Raise_Internal ("unreachable: try_send rejected by resolver");
                     when CM.Stmt_If =>
                        declare
                           Condition_Result : constant String :=
                             Variant_From_Expr (Item.Condition);
                        begin
                           if Condition_Result'Length > 0 then
                              return Condition_Result;
                           end if;
                        end;
                        declare
                           Then_Result : constant String :=
                             Variant_From_Statements (Item.Then_Stmts);
                        begin
                           if Then_Result'Length > 0 then
                              return Then_Result;
                           end if;
                        end;
                        for Part of Item.Elsifs loop
                           declare
                              Condition_Result : constant String :=
                                Variant_From_Expr (Part.Condition);
                           begin
                              if Condition_Result'Length > 0 then
                                 return Condition_Result;
                              end if;
                           end;
                           declare
                              Elsif_Result : constant String :=
                                Variant_From_Statements (Part.Statements);
                           begin
                              if Elsif_Result'Length > 0 then
                                 return Elsif_Result;
                              end if;
                           end;
                        end loop;
                        if Item.Has_Else then
                           declare
                              Else_Result : constant String :=
                                Variant_From_Statements (Item.Else_Stmts);
                           begin
                              if Else_Result'Length > 0 then
                                 return Else_Result;
                              end if;
                           end;
                        end if;
                     when CM.Stmt_Case =>
                        declare
                           Expr_Result : constant String :=
                             Variant_From_Expr (Item.Case_Expr);
                        begin
                           if Expr_Result'Length > 0 then
                              return Expr_Result;
                           end if;
                        end;
                        for Arm of Item.Case_Arms loop
                           declare
                              Arm_Result : constant String :=
                                Variant_From_Statements (Arm.Statements);
                           begin
                              if Arm_Result'Length > 0 then
                                 return Arm_Result;
                              end if;
                           end;
                        end loop;
                     when CM.Stmt_While =>
                        declare
                           Condition_Result : constant String :=
                             Variant_From_Expr (Item.Condition);
                        begin
                           if Condition_Result'Length > 0 then
                              return Condition_Result;
                           end if;
                        end;
                        declare
                           Body_Result : constant String :=
                             Variant_From_Statements (Item.Body_Stmts);
                        begin
                           if Body_Result'Length > 0 then
                              return Body_Result;
                           end if;
                        end;
                     when CM.Stmt_For | CM.Stmt_Loop =>
                        declare
                           Body_Result : constant String :=
                             Variant_From_Statements (Item.Body_Stmts);
                        begin
                           if Body_Result'Length > 0 then
                              return Body_Result;
                           end if;
                        end;
                     when CM.Stmt_Select =>
                        for Arm of Item.Arms loop
                           declare
                              Arm_Result : constant String :=
                                Variant_From_Statements
                                  ((case Arm.Kind is
                                     when CM.Select_Arm_Channel => Arm.Channel_Data.Statements,
                                     when CM.Select_Arm_Delay => Arm.Delay_Data.Statements,
                                     when others => CM.Statement_Access_Vectors.Empty_Vector));
                           begin
                              if Arm_Result'Length > 0 then
                                 return Arm_Result;
                              end if;
                           end;
                        end loop;
                     when others =>
                        null;
                  end case;
               end if;
            end loop;

            return "";
         end Variant_From_Statements;
      begin
         for Decl of Subprogram.Declarations loop
            for Name of Decl.Names loop
               if FT.To_String (Name)'Length > 0 then
                  Local_Names.Append (Name);
               end if;
            end loop;
         end loop;

         return Variant_From_Statements (Subprogram.Statements);
      end Recursive_Variant_Image;
   begin
      if Has_Text (Summary.Name) then
         if not Uses_Structural_Traversal then
            declare
               Variant_Image : constant String := Recursive_Variant_Image;
            begin
               if Variant_Image'Length > 0 then
                  Append_Aspect ("Subprogram_Variant => (" & Variant_Image & ")");
               end if;
            end;
         end if;

         Append_Aspect ("Global => " & Global_Image);

         if Depends_Image'Length > 0 then
            Append_Aspect ("Depends => (" & Depends_Image & ")");
         end if;
         if Pre_Image'Length > 0 or else Structural_Pre_Image'Length > 0 then
            Append_Aspect
              ("Pre => "
               & (if Pre_Image'Length > 0 and then Structural_Pre_Image'Length > 0
                  then Pre_Image & " and then " & Structural_Pre_Image
                  elsif Pre_Image'Length > 0
                  then Pre_Image
                  else Structural_Pre_Image));
         end if;
         if Post_Image'Length > 0 then
            Append_Aspect ("Post => " & Post_Image);
         end if;
      end if;

      return SU.To_String (Result);
   end Render_Subprogram_Aspects;

   function Render_Expression_Function_Image
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram;
      State      : in out Emit_State) return String
   is
      Return_Stmt : CM.Statement_Access := null;
   begin
      if not Subprogram.Has_Return_Type
        or else Uses_Structural_Traversal_Lowering (Subprogram)
        or else not Subprogram.Declarations.Is_Empty
        or else Subprogram.Statements.Length /= 1
      then
         return "";
      end if;

      for Param of Subprogram.Params loop
         declare
            Mode : constant String := FT.Lowercase (FT.To_String (Param.Mode));
         begin
            if Mode = "mut" or else Mode = "in out" or else Mode = "out" then
               return "";
            end if;
         end;
      end loop;

      Return_Stmt := Subprogram.Statements (Subprogram.Statements.First_Index);
      if Return_Stmt = null
        or else Return_Stmt.Kind /= CM.Stmt_Return
        or else Return_Stmt.Value = null
      then
         return "";
      end if;

      return
        Render_Expr_For_Target_Type
          (Unit,
           Document,
           Return_Stmt.Value,
           Subprogram.Return_Type,
           State);
   end Render_Expression_Function_Image;

   function Render_Discrete_Range
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Item_Range : CM.Discrete_Range;
      State    : in out Emit_State) return String
   is
   begin
      case Item_Range.Kind is
         when CM.Range_Subtype =>
            return Render_Expr (Unit, Document, Item_Range.Name_Expr, State);
         when CM.Range_Explicit =>
            return
              Render_Expr (Unit, Document, Item_Range.Low_Expr, State)
              & " .. "
              & Render_Expr (Unit, Document, Item_Range.High_Expr, State);
         when others =>
            Raise_Unsupported
              (State,
               Item_Range.Span,
               "unsupported loop range in Ada emission");
      end case;
   end Render_Discrete_Range;

   function Statement_Contains_Exit
     (Item : CM.Statement_Access) return Boolean renames AI.Statement_Contains_Exit;

   function Statements_Contain_Exit
     (Statements : CM.Statement_Access_Vectors.Vector) return Boolean renames AI.Statements_Contain_Exit;

   function Statement_Falls_Through
     (Item : CM.Statement_Access) return Boolean renames AI.Statement_Falls_Through;

   function Statements_Fall_Through
     (Statements : CM.Statement_Access_Vectors.Vector) return Boolean renames AI.Statements_Fall_Through;

   function Loop_Variant_Image
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Condition : CM.Expr_Access;
      State     : in out Emit_State) return String
   is
      Operator : constant String :=
        (if Condition = null then "" else Map_Operator (FT.To_String (Condition.Operator)));
   begin
      if Condition = null or else Condition.Kind /= CM.Expr_Binary then
         return "";
      end if;

      if Operator = "/=" then
         declare
            Cursor : CM.Expr_Access := null;
         begin
            if Condition.Left /= null and then Condition.Left.Kind /= CM.Expr_Null
              and then Condition.Right /= null and then Condition.Right.Kind = CM.Expr_Null
            then
               Cursor := Condition.Left;
            elsif Condition.Right /= null and then Condition.Right.Kind /= CM.Expr_Null
              and then Condition.Left /= null and then Condition.Left.Kind = CM.Expr_Null
            then
               Cursor := Condition.Right;
            end if;

            if Cursor /= null then
               declare
                  Flattened : constant String := CM.Flatten_Name (Cursor);
               begin
                  if Flattened'Length > 0 then
                     return "Structural => " & Flattened;
                  end if;
               end;
            end if;
         end;
      elsif Operator in "<" | "<=" then
         if Condition.Left /= null
           and then Condition.Right /= null
           and then Condition.Left.Kind = CM.Expr_Ident
           and then Condition.Right.Kind = CM.Expr_Ident
           and then Is_Integer_Type (Unit, Document, FT.To_String (Condition.Left.Type_Name))
           and then Is_Integer_Type (Unit, Document, FT.To_String (Condition.Right.Type_Name))
         then
            return
              "Increases => "
              & FT.To_String (Condition.Left.Name)
              & ", Decreases => "
              & FT.To_String (Condition.Right.Name);
         end if;
      elsif Operator = "=" then
         declare
            function Is_Length_Select (Expr : CM.Expr_Access) return Boolean is
            begin
               return
                 Expr /= null
                 and then Expr.Kind = CM.Expr_Select
                 and then FT.To_String (Expr.Selector) = "length";
            end Is_Length_Select;
         begin
            if (Is_Length_Select (Condition.Left)
                and then Condition.Right /= null
                and then Condition.Right.Kind = CM.Expr_Int)
              or else
              (Is_Length_Select (Condition.Right)
               and then Condition.Left /= null
               and then Condition.Left.Kind = CM.Expr_Int)
            then
               return
                 "Decreases => "
                 & (if Is_Length_Select (Condition.Left)
                    then Render_Expr (Unit, Document, Condition.Left, State)
                    else Render_Expr (Unit, Document, Condition.Right, State));
            end if;
         end;
      end if;

      return "";
   end Loop_Variant_Image;

   function Uses_Structural_Traversal_Lowering
     (Subprogram : CM.Resolved_Subprogram) return Boolean
   is
      Subprogram_Name : constant String :=
        FT.Lowercase (FT.To_String (Subprogram.Name));

      function Is_Direct_Null_Check
        (Expr : CM.Expr_Access;
         Name : String) return Boolean;

      function Is_Single_Return_Block
        (Statements : CM.Statement_Access_Vectors.Vector) return Boolean;

      function Is_Recursive_Tail_Return
        (Statements : CM.Statement_Access_Vectors.Vector;
         Expected_Param_Name : String) return Boolean;

      function Is_Direct_Null_Check
        (Expr : CM.Expr_Access;
         Name : String) return Boolean
      is
         Operator : constant String :=
           (if Expr = null then "" else Map_Operator (FT.To_String (Expr.Operator)));
      begin
         return
           Expr /= null
           and then Expr.Kind = CM.Expr_Binary
           and then Operator = "="
           and then
             ((Expr.Left /= null
               and then Expr.Left.Kind = CM.Expr_Ident
               and then FT.To_String (Expr.Left.Name) = Name
               and then Expr.Right /= null
               and then Expr.Right.Kind = CM.Expr_Null)
              or else
              (Expr.Right /= null
               and then Expr.Right.Kind = CM.Expr_Ident
               and then FT.To_String (Expr.Right.Name) = Name
               and then Expr.Left /= null
               and then Expr.Left.Kind = CM.Expr_Null));
      end Is_Direct_Null_Check;

      function Is_Single_Return_Block
        (Statements : CM.Statement_Access_Vectors.Vector) return Boolean
      is
      begin
         return
           Statements.Length = 1
           and then Statements (Statements.First_Index) /= null
           and then Statements (Statements.First_Index).Kind = CM.Stmt_Return
           and then Statements (Statements.First_Index).Value /= null;
      end Is_Single_Return_Block;

      function Is_Recursive_Tail_Return
        (Statements : CM.Statement_Access_Vectors.Vector;
         Expected_Param_Name : String) return Boolean
      is
         Return_Stmt : CM.Statement_Access := null;
         Call_Expr   : CM.Expr_Access := null;
      begin
         if Statements.Length /= 1 then
            return False;
         end if;

         Return_Stmt := Statements (Statements.First_Index);
         if Return_Stmt = null
           or else Return_Stmt.Kind /= CM.Stmt_Return
           or else Return_Stmt.Value = null
           or else Return_Stmt.Value.Kind /= CM.Expr_Call
         then
            return False;
         end if;

         Call_Expr := Return_Stmt.Value;
         return
           Call_Expr.Callee /= null
           and then FT.Lowercase (CM.Flatten_Name (Call_Expr.Callee)) = Subprogram_Name
           and then Call_Expr.Args.Length = Subprogram.Params.Length
           and then not Call_Expr.Args.Is_Empty
           and then Root_Name (Call_Expr.Args (Call_Expr.Args.First_Index)) = Expected_Param_Name;
      end Is_Recursive_Tail_Return;
   begin
      if Subprogram.Params.Is_Empty or else Subprogram.Statements.Is_Empty then
         return False;
      end if;

      declare
         First_Param_Name : constant String :=
           FT.To_String (Subprogram.Params (Subprogram.Params.First_Index).Name);
      begin
         if First_Param_Name'Length = 0
           or else not Is_Owner_Access
             (Subprogram.Params (Subprogram.Params.First_Index).Type_Info)
         then
            return False;
         end if;

         if Subprogram.Declarations.Is_Empty
           and then Subprogram.Params.Length = 1
           and then Subprogram.Statements.Length = 1
           and then Subprogram.Statements (Subprogram.Statements.First_Index) /= null
           and then Subprogram.Statements (Subprogram.Statements.First_Index).Kind = CM.Stmt_If
         then
            declare
               If_Stmt : constant CM.Statement_Access :=
                 Subprogram.Statements (Subprogram.Statements.First_Index);
            begin
               if Is_Direct_Null_Check (If_Stmt.Condition, First_Param_Name)
                 and then Is_Single_Return_Block (If_Stmt.Then_Stmts)
                 and then If_Stmt.Has_Else
                 and then Is_Recursive_Tail_Return (If_Stmt.Else_Stmts, First_Param_Name)
               then
                  for Part of If_Stmt.Elsifs loop
                     if not Is_Single_Return_Block (Part.Statements) then
                        return False;
                     end if;
                  end loop;
                  return True;
               end if;
            end;
         end if;

         if not Subprogram.Declarations.Is_Empty
           and then Subprogram.Params.Length >= 2
           and then Subprogram.Statements.Length >= 4
         then
            declare
               First_Stmt       : constant CM.Statement_Access :=
                 Subprogram.Statements (Subprogram.Statements.First_Index);
               Recursive_Assign : constant CM.Statement_Access :=
                 Subprogram.Statements (Subprogram.Statements.Last_Index - 1);
               Final_Return     : constant CM.Statement_Access :=
                 Subprogram.Statements (Subprogram.Statements.Last_Index);
            begin
               if First_Stmt /= null
                 and then First_Stmt.Kind = CM.Stmt_If
                 and then Is_Single_Return_Block (First_Stmt.Then_Stmts)
                 and then not First_Stmt.Has_Else
                 and then First_Stmt.Elsifs.Is_Empty
                 and then Recursive_Assign /= null
                 and then Recursive_Assign.Kind = CM.Stmt_Assign
                 and then Recursive_Assign.Value /= null
                 and then Recursive_Assign.Value.Kind = CM.Expr_Call
                 and then Recursive_Assign.Value.Callee /= null
                 and then FT.Lowercase (CM.Flatten_Name (Recursive_Assign.Value.Callee)) = Subprogram_Name
                 and then Recursive_Assign.Value.Args.Length = Subprogram.Params.Length
                 and then Root_Name (Recursive_Assign.Value.Args (Recursive_Assign.Value.Args.First_Index)) = First_Param_Name
                 and then Final_Return /= null
                 and then Final_Return.Kind = CM.Stmt_Return
                 and then Root_Name (Final_Return.Value) = Root_Name (Recursive_Assign.Target)
               then
                  return True;
               end if;
            end;
         end if;
      end;

      return False;
   end Uses_Structural_Traversal_Lowering;

   function Replace_Identifier_Token
     (Text        : String;
      Name        : String;
      Replacement : String) return String
   is
      function Is_Identifier_Char (Item : Character) return Boolean is
      begin
         return
           (Item in 'a' .. 'z')
           or else (Item in 'A' .. 'Z')
           or else (Item in '0' .. '9')
           or else Item = '_';
      end Is_Identifier_Char;

      Result : SU.Unbounded_String;
      Index  : Positive := Text'First;
   begin
      if Text'Length = 0 or else Name'Length = 0 or else Name = Replacement then
         return Text;
      end if;

      while Index <= Text'Last loop
         if Index + Name'Length - 1 <= Text'Last
           and then Text (Index .. Index + Name'Length - 1) = Name
           and then
             (Index = Text'First or else not Is_Identifier_Char (Text (Index - 1)))
           and then
             (Index + Name'Length - 1 = Text'Last
              or else not Is_Identifier_Char (Text (Index + Name'Length)))
         then
            Result := Result & SU.To_Unbounded_String (Replacement);
            Index := Index + Name'Length;
         else
            Result := Result & SU.To_Unbounded_String (String'(1 => Text (Index)));
            Index := Index + 1;
         end if;
      end loop;

      return SU.To_String (Result);
   end Replace_Identifier_Token;

   procedure Append_Gnatprove_Warning_Suppression
     (Buffer  : in out SU.Unbounded_String;
      Pattern : String;
      Reason  : String;
      Depth   : Natural) renames AI.Append_Gnatprove_Warning_Suppression;

   procedure Append_Gnatprove_Warning_Restore
     (Buffer  : in out SU.Unbounded_String;
      Pattern : String;
      Depth   : Natural) renames AI.Append_Gnatprove_Warning_Restore;

   procedure Append_Gnatprove_Warning_Suppressions
     (Buffer   : in out SU.Unbounded_String;
      Warnings : Warning_Suppression_Array;
      Depth    : Natural) renames AI.Append_Gnatprove_Warning_Suppressions;

   procedure Append_Gnatprove_Warning_Restores
     (Buffer   : in out SU.Unbounded_String;
      Warnings : Warning_Restore_Array;
      Depth    : Natural) renames AI.Append_Gnatprove_Warning_Restores;

   procedure Append_Local_Warning_Suppression
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) renames AI.Append_Local_Warning_Suppression;

   procedure Append_Local_Warning_Restore
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) renames AI.Append_Local_Warning_Restore;

   procedure Append_Initialization_Warning_Suppression
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) renames AI.Append_Initialization_Warning_Suppression;

   procedure Append_Initialization_Warning_Restore
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) renames AI.Append_Initialization_Warning_Restore;

   procedure Append_Channel_Staged_Call_Warning_Suppression
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) renames AI.Append_Channel_Staged_Call_Warning_Suppression;

   procedure Append_Channel_Staged_Call_Warning_Restore
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) renames AI.Append_Channel_Staged_Call_Warning_Restore;

   procedure Append_Task_Assignment_Warning_Suppression
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) renames AI.Append_Task_Assignment_Warning_Suppression;

   procedure Append_Task_Assignment_Warning_Restore
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) renames AI.Append_Task_Assignment_Warning_Restore;

   procedure Append_Task_If_Warning_Suppression
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) renames AI.Append_Task_If_Warning_Suppression;

   procedure Append_Task_If_Warning_Restore
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) renames AI.Append_Task_If_Warning_Restore;

   procedure Append_Task_Channel_Call_Warning_Suppression
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) renames AI.Append_Task_Channel_Call_Warning_Suppression;

   procedure Append_Task_Channel_Call_Warning_Restore
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) renames AI.Append_Task_Channel_Call_Warning_Restore;

   function Structural_Accumulator_Count_Total_Bound
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram;
      Count_Name : String;
      Total_Name : String;
      State      : in out Emit_State) return String
   is
      Count_Param  : constant CM.Symbol :=
        Subprogram.Params (Subprogram.Params.First_Index + 1);
      Total_Param  : constant CM.Symbol :=
        Subprogram.Params (Subprogram.Params.First_Index + 2);
      Count_Base   : constant GM.Type_Descriptor :=
        Base_Type (Unit, Document, Count_Param.Type_Info);
      Total_Base   : constant GM.Type_Descriptor :=
        Base_Type (Unit, Document, Total_Param.Type_Info);
      Count_High   : CM.Wide_Integer;
      Total_High   : CM.Wide_Integer;
      Step_Limit   : CM.Wide_Integer;
   begin
      if Subprogram.Params.Length < 3
        or else not Is_Integer_Type (Unit, Document, Count_Param.Type_Info)
        or else not Is_Integer_Type (Unit, Document, Total_Param.Type_Info)
        or else not Count_Base.Has_Low
        or else not Count_Base.Has_High
        or else not Total_Base.Has_Low
        or else not Total_Base.Has_High
        or else Count_Base.Low /= 0
        or else Total_Base.Low /= 0
        or else Count_Base.High <= 0
      then
         return "";
      end if;

      Count_High := CM.Wide_Integer (Count_Base.High);
      Total_High := CM.Wide_Integer (Total_Base.High);
      if Total_High < 0 or else Total_High mod Count_High /= 0 then
         return "";
      end if;

      Step_Limit := Total_High / Count_High;
      State.Needs_Safe_Runtime := True;
      return
        "Safe_Runtime.Wide_Integer ("
        & Total_Name
        & ") <= Safe_Runtime.Wide_Integer ("
        & Count_Name
        & ") * "
        & Trim_Wide_Image (Step_Limit);
   end Structural_Accumulator_Count_Total_Bound;

   procedure Append_Narrowing_Assignment
     (Buffer     : in out SU.Unbounded_String;
      Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      State      : in out Emit_State;
      Target     : CM.Expr_Access;
      Value      : CM.Expr_Access;
      Depth      : Natural)
   is
      Target_Name : constant String := FT.To_String (Target.Type_Name);
      Target_Info : constant GM.Type_Descriptor :=
        Resolve_Type_Name (Unit, Document, Target_Name);
      Target_Subtype : constant String :=
        Render_Subtype_Indication (Unit, Document, Target_Info);
      Target_Image : constant String := Render_Expr (Unit, Document, Target, State);
      Wide_Image   : constant String := Render_Wide_Expr (Unit, Document, Value, State);
   begin
      Append_Line
        (Buffer,
         "pragma Assert ("
         & Wide_Image
         & " >= Safe_Runtime.Wide_Integer ("
         & Target_Subtype
         & "'First) and then "
         & Wide_Image
         & " <= Safe_Runtime.Wide_Integer ("
         & Target_Subtype
         & "'Last));",
         Depth);
      Append_Line
        (Buffer,
         Target_Image & " := " & Target_Subtype & " (" & Wide_Image & ");",
         Depth);

   end Append_Narrowing_Assignment;

   procedure Append_Float_Narrowing_Checks
     (Buffer       : in out SU.Unbounded_String;
      Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      Target_Type  : String;
      Value_Name   : String;
      Depth        : Natural)
   is
      pragma Unreferenced (Unit, Document, Target_Type);
   begin
      Append_Line
        (Buffer,
         "pragma Assert (" & Value_Name & " = " & Value_Name & ");",
         Depth);
      Append_Line
        (Buffer,
         "pragma Assert ("
         & Value_Name
         & " >= Long_Float'First and then "
         & Value_Name
         & " <= Long_Float'Last);",
         Depth);
   end Append_Float_Narrowing_Checks;

   procedure Append_Float_Narrowing_Assignment
     (Buffer       : in out SU.Unbounded_String;
      Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      Target_Type  : String;
      Target_Image : String;
      Inner_Image  : String;
      Depth        : Natural)
   is
   begin
      Append_Line (Buffer, "declare", Depth);
      Append_Line
        (Buffer,
         "Narrowed_Float_Value : constant Long_Float := Long_Float ("
         & Inner_Image
         & ");",
         Depth + 1);
      Append_Line (Buffer, "begin", Depth);
      Append_Float_Narrowing_Checks
        (Buffer,
         Unit => Unit,
         Document => Document,
         Target_Type => Target_Type,
         Value_Name => "Narrowed_Float_Value",
         Depth => Depth + 1);
      Append_Line
        (Buffer,
         Target_Image & " := " & Target_Type & " (Narrowed_Float_Value);",
         Depth + 1);
      Append_Line (Buffer, "end;", Depth);
   end Append_Float_Narrowing_Assignment;

   procedure Append_Float_Narrowing_Return
     (Buffer      : in out SU.Unbounded_String;
      Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      Target_Type : String;
      Inner_Image : String;
      Depth       : Natural)
   is
   begin
      Append_Line (Buffer, "declare", Depth);
      Append_Line
        (Buffer,
         "Narrowed_Float_Value : constant Long_Float := Long_Float ("
         & Inner_Image
         & ");",
         Depth + 1);
      Append_Line (Buffer, "begin", Depth);
      Append_Float_Narrowing_Checks
        (Buffer,
         Unit => Unit,
         Document => Document,
         Target_Type => Target_Type,
         Value_Name => "Narrowed_Float_Value",
         Depth => Depth + 1);
      Append_Line
        (Buffer,
         "return " & Target_Type & " (Narrowed_Float_Value);",
         Depth + 1);
      Append_Line (Buffer, "end;", Depth);
   end Append_Float_Narrowing_Return;

   procedure Append_Move_Null
     (Buffer     : in out SU.Unbounded_String;
      Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      State      : in out Emit_State;
      Value      : CM.Expr_Access;
      Depth      : Natural)
   is
      Type_Name : constant String := FT.To_String (Value.Type_Name);
      Info      : constant GM.Type_Descriptor := Lookup_Type (Unit, Document, Type_Name);
   begin
      if Has_Type (Unit, Document, Type_Name)
        and then Is_Owner_Access (Info)
        and then Value.Kind in CM.Expr_Ident | CM.Expr_Select | CM.Expr_Resolved_Index
      then
         Append_Line
           (Buffer,
            Render_Expr (Unit, Document, Value, State) & " := null;",
            Depth);
      end if;
   end Append_Move_Null;

   procedure Append_Assignment
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      State    : in out Emit_State;
      Stmt     : CM.Statement;
      Depth    : Natural;
      In_Loop  : Boolean := False)
   is
      Target_Type : constant String := FT.To_String (Stmt.Target.Type_Name);
      Target_Info : constant GM.Type_Descriptor :=
        (if Target_Type'Length > 0
         then Resolve_Type_Name (Unit, Document, Target_Type)
         else (others => <>));
      Target_Image : constant String := Render_Expr (Unit, Document, Stmt.Target, State);
      Tracked_Target_Name : constant String :=
        (if Stmt.Target = null
         then ""
         elsif Stmt.Target.Kind = CM.Expr_Ident
         then FT.To_String (Stmt.Target.Name)
         elsif Stmt.Target.Kind = CM.Expr_Select
         then CM.Flatten_Name (Stmt.Target)
         else "");
      Needs_Target_Snapshot : constant Boolean :=
        Stmt.Target /= null
        and then Stmt.Target.Kind = CM.Expr_Select
        and then Target_Image'Length > 0
        and then Expr_Contains_Target (Stmt.Value, Stmt.Target);
      Needs_Pre_Target_Value_Assert : constant Boolean :=
        not In_Loop
        and then Tracked_Target_Name'Length > 0
        and then Is_Integer_Type (Unit, Document, Target_Type)
        and then Expr_Contains_Target (Stmt.Value, Stmt.Target);
      Suppress_Target_Static_Binding : constant Boolean :=
        In_Loop
        and then Tracked_Target_Name'Length > 0
        and then Is_Integer_Type (Unit, Document, Target_Type)
        and then Expr_Contains_Target (Stmt.Value, Stmt.Target)
        and then Has_Static_Integer_Tracking (State, Tracked_Target_Name);
      Previous_Static_Integer_Count : constant Ada.Containers.Count_Type :=
        State.Static_Integer_Bindings.Length;

      function Value_Image return String is
      begin
         return Render_Expr_For_Target_Type (Unit, Document, Stmt.Value, Target_Info, State);
      end Value_Image;

      function Static_Integer_Assignment_Image return String is
         Static_Value : Long_Long_Integer := 0;
      begin
         if not In_Loop
           and then Is_Integer_Type (Unit, Document, Target_Type)
           and then Try_Resolved_Static_Integer_Value
             (Unit, Document, State, Stmt.Value, Static_Value)
         then
            return Render_Subtype_Indication (Unit, Document, Target_Info)
              & " ("
              & Trim_Wide_Image (CM.Wide_Integer (Static_Value))
              & ")";
         end if;

         return "";
      end Static_Integer_Assignment_Image;
   begin
      if Suppress_Target_Static_Binding then
         --  Loop bodies are emitted once and reused at runtime, so do not
         --  fold the target's current static binding into a self-update.
         Invalidate_Static_Integer (State, Tracked_Target_Name);
      end if;

      if Needs_Pre_Target_Value_Assert then
         declare
            Static_Target_Value : Long_Long_Integer := 0;
         begin
            if Try_Static_Integer_Binding (State, Tracked_Target_Name, Static_Target_Value) then
               Append_Line
                 (Buffer,
                  "pragma Assert ("
                  & Target_Image
                  & " = "
                  & Render_Subtype_Indication (Unit, Document, Target_Info)
                  & " ("
                  & Trim_Wide_Image (CM.Wide_Integer (Static_Target_Value))
                  & "));",
                  Depth);
            end if;
         end;
      end if;

      if Needs_Target_Snapshot then
         declare
            Snapshot_Name : constant String :=
              Root_Name (Stmt.Target) & "_" & FT.To_String (Stmt.Target.Selector) & "_Snapshot";
            Snapshot_Type : constant String :=
              Render_Type_Name (Unit, Document, FT.To_String (Stmt.Target.Type_Name));
            Snapshot_Supported   : Boolean := True;
            Snapshot_Value_Image : constant String :=
              Render_Expr_With_Target_Substitution
                (Unit,
                 Document,
                 Stmt.Value,
                 Stmt.Target,
                 Snapshot_Name,
                 State,
                 Snapshot_Supported);
         begin
            if not Snapshot_Supported or else Snapshot_Value_Image'Length = 0 then
               Raise_Unsupported
                 (State,
                  Stmt.Span,
                  "target-snapshot substitution shape is not yet supported in Ada emission");
            end if;

            Append_Line (Buffer, "declare", Depth);
            Append_Line
              (Buffer,
               Snapshot_Name & " : constant " & Snapshot_Type & " := " & Target_Image & ";",
               Depth + 1);
            Append_Line (Buffer, "begin", Depth);
            if Is_Integer_Type (Unit, Document, Target_Type)
              and then Uses_Wide_Value (Unit, Document, State, Stmt.Value)
            then
               declare
                  Snapshot_Wide_Supported : Boolean := True;
                  Snapshot_Wide_Image : constant String :=
                    Render_Wide_Expr_With_Target_Substitution
                      (Unit,
                       Document,
                       Stmt.Value,
                       Stmt.Target,
                       Snapshot_Name,
                       State,
                       Snapshot_Wide_Supported);
               begin
                  if not Snapshot_Wide_Supported or else Snapshot_Wide_Image'Length = 0 then
                     Raise_Unsupported
                       (State,
                        Stmt.Span,
                        "wide target-snapshot substitution shape is not yet supported in Ada emission");
                  end if;

                  Append_Line
                    (Buffer,
                     "pragma Assert ("
                     & Snapshot_Wide_Image
                     & " >= Safe_Runtime.Wide_Integer ("
                     & Render_Subtype_Indication (Unit, Document, Target_Info)
                     & "'First) and then "
                     & Snapshot_Wide_Image
                     & " <= Safe_Runtime.Wide_Integer ("
                     & Render_Subtype_Indication (Unit, Document, Target_Info)
                     & "'Last));",
                     Depth + 1);
                  Append_Line
                    (Buffer,
                     Target_Image
                     & " := "
                     & Render_Subtype_Indication (Unit, Document, Target_Info)
                     & " ("
                     & Snapshot_Wide_Image
                     & ");",
                     Depth + 1);
               end;
            elsif Is_Explicit_Float_Narrowing (Unit, Document, Target_Type, Stmt.Value)
            then
               declare
                  Snapshot_Float_Supported : Boolean := True;
                  Snapshot_Inner_Image : constant String :=
                    Render_Expr_With_Target_Substitution
                      (Unit,
                       Document,
                       Stmt.Value.Inner,
                       Stmt.Target,
                       Snapshot_Name,
                       State,
                       Snapshot_Float_Supported);
               begin
                  if not Snapshot_Float_Supported or else Snapshot_Inner_Image'Length = 0 then
                     Raise_Unsupported
                       (State,
                        Stmt.Span,
                        "float target-snapshot substitution shape is not yet supported in Ada emission");
                  end if;

                  Append_Float_Narrowing_Assignment
                    (Buffer,
                     Unit => Unit,
                     Document => Document,
                     Target_Type => Target_Type,
                     Target_Image => Target_Image,
                     Inner_Image => Snapshot_Inner_Image,
                     Depth => Depth + 1);
               end;
            else
               Append_Line
                 (Buffer,
                  Target_Image & " := " & Snapshot_Value_Image & ";",
                  Depth + 1);
            end if;
            Append_Line (Buffer, "end;", Depth);
         end;
      elsif Stmt.Target.Kind = CM.Expr_Ident
        and then Is_Wide_Name (State, FT.To_String (Stmt.Target.Name))
      then
         if FT.Lowercase (Target_Type) /= "integer" then
            Append_Line
              (Buffer,
               "pragma Assert ("
               & Render_Wide_Expr (Unit, Document, Stmt.Value, State)
               & " >= Safe_Runtime.Wide_Integer ("
               & Target_Type
               & "'First) and then "
               & Render_Wide_Expr (Unit, Document, Stmt.Value, State)
               & " <= Safe_Runtime.Wide_Integer ("
               & Target_Type
               & "'Last));",
               Depth);
         end if;
         Append_Line
           (Buffer,
            Target_Image & " := " & Render_Wide_Expr (Unit, Document, Stmt.Value, State) & ";",
            Depth);
         if FT.Lowercase (Target_Type) /= "integer" then
            Append_Line
              (Buffer,
               "pragma Assert ("
               & Target_Image
               & " >= Safe_Runtime.Wide_Integer ("
               & Target_Type
               & "'First) and then "
               & Target_Image
               & " <= Safe_Runtime.Wide_Integer ("
               & Target_Type
               & "'Last));",
               Depth);
         end if;
      elsif Is_Integer_Type (Unit, Document, Target_Type)
        and then Uses_Wide_Value (Unit, Document, State, Stmt.Value)
      then
         Append_Narrowing_Assignment
           (Buffer, Unit, Document, State, Stmt.Target, Stmt.Value, Depth);
      else
         declare
            Condition_Image : FT.UString;
            Lower_Image     : FT.UString;
            Upper_Image     : FT.UString;
         begin
            if Is_Float_Type (Unit, Document, Target_Type)
              and then Try_Render_Stable_Float_Interpolation
                (Unit,
                 Document,
                 Stmt.Value,
                 State,
                 Condition_Image,
                 Lower_Image,
                 Upper_Image)
            then
               Append_Line
                 (Buffer,
                  "if " & FT.To_String (Condition_Image) & " then",
                  Depth);
               Append_Line
                 (Buffer,
                  Target_Image & " := " & FT.To_String (Lower_Image) & ";",
                  Depth + 1);
               Append_Line (Buffer, "else", Depth);
               Append_Line
                 (Buffer,
                  Target_Image & " := " & FT.To_String (Upper_Image) & ";",
                  Depth + 1);
               Append_Line (Buffer, "end if;", Depth);
            elsif Is_Explicit_Float_Narrowing (Unit, Document, Target_Type, Stmt.Value) then
               Append_Float_Narrowing_Assignment
                 (Buffer,
                  Unit => Unit,
                  Document => Document,
                  Target_Type => Target_Type,
                  Target_Image => Target_Image,
                  Inner_Image => Render_Expr (Unit, Document, Stmt.Value.Inner, State),
                  Depth => Depth);
            else
               Append_Line
                 (Buffer,
                  Target_Image
                  & " := "
                  & (if Static_Integer_Assignment_Image'Length > 0
                     then Static_Integer_Assignment_Image
                     else Value_Image)
                  & ";",
                  Depth);
            end if;
         end;
      end if;

      if Is_Owner_Access (Target_Info)
        and then not
          (Stmt.Target /= null
           and then Stmt.Target.Kind = CM.Expr_Ident
           and then Root_Name (Stmt.Value) = FT.To_String (Stmt.Target.Name))
      then
         Append_Move_Null (Buffer, Unit, Document, State, Stmt.Value, Depth);
      end if;

      if Suppress_Target_Static_Binding then
         Restore_Static_Integer_Bindings (State, Previous_Static_Integer_Count);
      end if;

      if Stmt.Target /= null and then Stmt.Target.Kind in CM.Expr_Ident | CM.Expr_Select then
         declare
            Static_Value     : Long_Long_Integer := 0;
            Static_Length    : Natural := 0;
            Previous_Length  : Natural := 0;
         begin
            if not In_Loop
              and then Is_Integer_Type (Unit, Document, Target_Type)
              and then Has_Static_Integer_Tracking (State, Tracked_Target_Name)
            then
               if Try_Resolved_Static_Integer_Value
                 (Unit, Document, State, Stmt.Value, Static_Value)
               then
                  Bind_Static_Integer (State, Tracked_Target_Name, Static_Value);
                  Append_Line
                    (Buffer,
                     "pragma Assert ("
                     & Target_Image
                     & " = "
                     & Render_Subtype_Indication (Unit, Document, Target_Info)
                     & " ("
                     & Trim_Wide_Image (CM.Wide_Integer (Static_Value))
                     & "));",
                     Depth);
               else
                  Invalidate_Static_Integer (State, Tracked_Target_Name);
               end if;
            end if;

            if Is_Growable_Array_Type (Unit, Document, Target_Info) then
               if Try_Static_Length (State, Tracked_Target_Name, Previous_Length) then
                  for Position in 1 .. Previous_Length loop
                     Invalidate_Static_Integer
                       (State,
                        Static_Element_Binding_Name (Tracked_Target_Name, Position));
                  end loop;
               end if;

               if Try_Static_Array_Length_From_Expr
                 (Unit, Document, Stmt.Value, Static_Length)
               then
                  Bind_Static_Length (State, Tracked_Target_Name, Static_Length);
                  for Position in 1 .. Static_Length loop
                     if Try_Static_Integer_Array_Element_Expr
                       (Unit, Stmt.Value, Position, Static_Value)
                     then
                        Bind_Static_Integer
                          (State,
                           Static_Element_Binding_Name (Tracked_Target_Name, Position),
                           Static_Value);
                     else
                        Invalidate_Static_Integer
                          (State,
                           Static_Element_Binding_Name (Tracked_Target_Name, Position));
                     end if;
                  end loop;
               else
                  Invalidate_Static_Length (State, Tracked_Target_Name);
               end if;
            end if;
         end;
      end if;
   end Append_Assignment;

   procedure Append_Float_Loop_Invariant
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      State    : in out Emit_State;
      Target   : CM.Expr_Access;
      Depth    : Natural)
   is
      pragma Unreferenced (State);
   begin
      if Target = null
        or else Target.Kind /= CM.Expr_Ident
        or else not Has_Text (Target.Type_Name)
        or else not Has_Type (Unit, Document, FT.To_String (Target.Type_Name))
      then
         return;
      end if;

      declare
         Target_Type : constant String := FT.To_String (Target.Type_Name);
         Target_Info : constant GM.Type_Descriptor := Lookup_Type (Unit, Document, Target_Type);
      begin
         if not Is_Float_Type (Unit, Document, Target_Type) then
            return;
         end if;

         Append_Line
           (Buffer,
            "pragma Loop_Invariant ("
            & FT.To_String (Target.Name)
            & " >= "
            & Render_Type_Name (Target_Info)
            & "'First and then "
            & FT.To_String (Target.Name)
            & " <= "
            & Render_Type_Name (Target_Info)
            & "'Last);",
            Depth);
      end;
   end Append_Float_Loop_Invariant;

   procedure Append_Integer_Loop_Invariant
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      State    : in out Emit_State;
      Target   : CM.Expr_Access;
      Depth    : Natural)
   is
   begin
      if Target = null
        or else Target.Kind /= CM.Expr_Ident
        or else not Has_Text (Target.Type_Name)
        or else not Is_Wide_Name (State, FT.To_String (Target.Name))
      then
         return;
      end if;

      declare
         Target_Type : constant String := FT.To_String (Target.Type_Name);
      begin
         if not Is_Integer_Type (Unit, Document, Target_Type)
           or else not Is_Builtin_Integer_Name (Target_Type)
         then
            return;
         end if;

         Append_Line
           (Buffer,
            "pragma Loop_Invariant ("
            & FT.To_String (Target.Name)
            & " >= Safe_Runtime.Wide_Integer'First and then "
            & FT.To_String (Target.Name)
            & " <= Safe_Runtime.Wide_Integer'Last);",
            Depth);
      end;
   end Append_Integer_Loop_Invariant;

   procedure Append_Return
     (Buffer     : in out SU.Unbounded_String;
      Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      State      : in out Emit_State;
      Value      : CM.Expr_Access;
      Return_Type : String;
      Depth      : Natural)
   is
      Return_Info : constant GM.Type_Descriptor :=
        (if Return_Type'Length > 0
         then Resolve_Type_Name (Unit, Document, Return_Type)
         else (others => <>));
   begin
      if Value = null then
         if Return_Type'Length > 0 then
            Raise_Internal ("function return missing value during Ada emission");
         end if;
         Append_Line (Buffer, "return;", Depth);
      elsif Is_Explicit_Float_Narrowing (Unit, Document, Return_Type, Value) then
         Append_Float_Narrowing_Return
           (Buffer,
            Unit => Unit,
            Document => Document,
            Target_Type => Return_Type,
            Inner_Image => Render_Expr (Unit, Document, Value.Inner, State),
            Depth => Depth);
      elsif Return_Type'Length > 0
        and then Is_Integer_Type (Unit, Document, Return_Type)
        and then Uses_Wide_Value (Unit, Document, State, Value)
      then
         declare
            Wide_Image : constant String := Render_Wide_Expr (Unit, Document, Value, State);
         begin
            Append_Line
              (Buffer,
               "pragma Assert ("
               & Wide_Image
               & " >= Safe_Runtime.Wide_Integer ("
               & Return_Type
               & "'First) and then "
               & Wide_Image
               & " <= Safe_Runtime.Wide_Integer ("
               & Return_Type
               & "'Last));",
               Depth);
            Append_Line
              (Buffer,
               "return " & Return_Type & " (" & Wide_Image & ");",
               Depth);
         end;
      else
         Append_Line
           (Buffer,
           "return "
           & (if Return_Type'Length > 0
               and then Is_Owner_Access (Return_Info)
              then
                Render_Expr_For_Target_Type
                  (Unit, Document, Value, Return_Info, State)
              elsif Return_Type'Length > 0
               and then Is_Bounded_String_Type (Return_Info)
              then
                Render_Expr_For_Target_Type
                  (Unit, Document, Value, Return_Info, State)
              elsif Return_Type'Length > 0
                and then Value.Kind = CM.Expr_Aggregate
                and then not Return_Info.Discriminant_Constraints.Is_Empty
              then
                Return_Type
                & "'"
                & Render_Record_Aggregate_For_Type
                    (Unit, Document, Value, Return_Info, State)
              elsif Return_Type'Length > 0
                and then Value.Kind in CM.Expr_Aggregate | CM.Expr_Tuple
              then Return_Type & "'" & Render_Expr (Unit, Document, Value, State)
              elsif Return_Type'Length > 0 and then Has_Text (Return_Info.Name)
              then
                Render_Expr_For_Target_Type
                  (Unit, Document, Value, Return_Info, State)
              else Render_Expr (Unit, Document, Value, State))
           & ";",
           Depth);
      end if;
   end Append_Return;

   procedure Append_Return_With_Cleanup
     (Buffer      : in out SU.Unbounded_String;
      Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      State       : in out Emit_State;
      Value       : CM.Expr_Access;
      Return_Type : String;
      Depth       : Natural)
   is
      Value_Type : constant String := FT.To_String (Value.Type_Name);
      Value_Info : constant GM.Type_Descriptor :=
        (if Value_Type'Length > 0
         then Resolve_Type_Name (Unit, Document, Value_Type)
         else (others => <>));
      Return_Info : constant GM.Type_Descriptor :=
        (if Return_Type'Length > 0
         then Resolve_Type_Name (Unit, Document, Return_Type)
         else (others => <>));
      Needs_Move_Null : constant Boolean :=
        Value_Type'Length > 0
        and then Is_Owner_Access (Value_Info)
        and then Value.Kind in CM.Expr_Ident | CM.Expr_Select | CM.Expr_Resolved_Index;
      Returned_Name : constant String := Root_Name (Value);
      Can_Skip_Cleanup : constant Boolean :=
        Needs_Move_Null
        and then Value.Kind = CM.Expr_Ident
        and then Returned_Name'Length > 0;
   begin
      if Return_Type'Length = 0 then
         Raise_Internal ("cleanup-preserving return requires a function return type");
      end if;

      Append_Line (Buffer, "declare", Depth);
      if Is_Explicit_Float_Narrowing (Unit, Document, Return_Type, Value) then
         Append_Line
           (Buffer,
            "Narrowed_Float_Value : constant Long_Float := Long_Float ("
            & Render_Expr (Unit, Document, Value.Inner, State)
            & ");",
            Depth + 1);
         Append_Line (Buffer, "Return_Value : " & Return_Type & ";", Depth + 1);
      elsif Is_Integer_Type (Unit, Document, Return_Type)
        and then Uses_Wide_Value (Unit, Document, State, Value)
      then
         declare
            Wide_Image : constant String := Render_Wide_Expr (Unit, Document, Value, State);
         begin
            Append_Line
              (Buffer,
               "Wide_Return_Value : constant Safe_Runtime.Wide_Integer := "
               & Wide_Image
               & ";",
               Depth + 1);
            Append_Line (Buffer, "Return_Value : " & Return_Type & ";", Depth + 1);
         end;
      else
         Append_Line
           (Buffer,
            "Return_Value : constant "
            & Return_Type
            & " := "
            & Render_Expr_For_Target_Type (Unit, Document, Value, Return_Info, State)
            & ";",
            Depth + 1);
      end if;
      Append_Line (Buffer, "begin", Depth);
      if Is_Explicit_Float_Narrowing (Unit, Document, Return_Type, Value) then
         Append_Float_Narrowing_Checks
           (Buffer,
            Unit => Unit,
            Document => Document,
            Target_Type => Return_Type,
            Value_Name => "Narrowed_Float_Value",
            Depth => Depth + 1);
         Append_Line
           (Buffer,
            "Return_Value := " & Return_Type & " (Narrowed_Float_Value);",
            Depth + 1);
      elsif Is_Integer_Type (Unit, Document, Return_Type)
        and then Uses_Wide_Value (Unit, Document, State, Value)
      then
         Append_Line
           (Buffer,
            "pragma Assert ("
            & "Wide_Return_Value >= Safe_Runtime.Wide_Integer ("
            & Return_Type
            & "'First) and then "
            & "Wide_Return_Value <= Safe_Runtime.Wide_Integer ("
            & Return_Type
            & "'Last));",
            Depth + 1);
         Append_Line
           (Buffer,
            "Return_Value := " & Return_Type & " (Wide_Return_Value);",
            Depth + 1);
      end if;
      if Needs_Move_Null and then not Can_Skip_Cleanup then
         Append_Move_Null (Buffer, Unit, Document, State, Value, Depth + 1);
      end if;
      Render_Active_Cleanup
        (Buffer,
         State,
         Depth + 1,
         Skip_Name => (if Can_Skip_Cleanup then Returned_Name else ""));
      Append_Line (Buffer, "return Return_Value;", Depth + 1);
      Append_Line (Buffer, "end;", Depth);
   end Append_Return_With_Cleanup;

   procedure Render_Block_Declarations
     (Buffer       : in out SU.Unbounded_String;
      Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      Declarations : CM.Resolved_Object_Decl_Vectors.Vector;
      State        : in out Emit_State;
      Depth        : Natural)
   is
   begin
      for Decl of Declarations loop
         Append_Line
           (Buffer,
            Render_Object_Decl_Text (Unit, Document, State, Decl, Local_Context => True),
            Depth);
      end loop;
   end Render_Block_Declarations;

   procedure Render_Cleanup
     (Buffer       : in out SU.Unbounded_String;
      Declarations : CM.Resolved_Object_Decl_Vectors.Vector;
      Depth        : Natural) renames AI.Render_Cleanup;

   procedure Render_Cleanup
     (Buffer       : in out SU.Unbounded_String;
      Declarations : CM.Object_Decl_Vectors.Vector;
      Depth        : Natural) renames AI.Render_Cleanup;

   function Tail_Statements
     (Statements : CM.Statement_Access_Vectors.Vector;
      First      : Positive) return CM.Statement_Access_Vectors.Vector
   is
      Result : CM.Statement_Access_Vectors.Vector;
   begin
      if Statements.Is_Empty or else First > Statements.Last_Index then
         return Result;
      end if;
      for Index in First .. Statements.Last_Index loop
         Result.Append (Statements (Index));
      end loop;
      return Result;
   end Tail_Statements;

   procedure Emit_Nonblocking_Send_Statement
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Item     : CM.Statement;
      Index    : Positive;
      State    : in out Emit_State;
      Depth    : Natural)
   is
      function Channel_Item
        (Channel_Expr : CM.Expr_Access) return CM.Resolved_Channel_Decl is
      begin
         if Channel_Expr = null then
            return (others => <>);
         end if;
         return Lookup_Channel (Unit, CM.Flatten_Name (Channel_Expr));
      end Channel_Item;

      function Render_Heap_Channel_Copy_Expr
        (Channel_Item : CM.Resolved_Channel_Decl;
         Expr         : CM.Expr_Access) return String
      is
         Element_Info : constant GM.Type_Descriptor := Channel_Item.Element_Type;
      begin
         return
           Render_Expr_For_Target_Type
             (Unit,
              Document,
              Expr,
              Element_Info,
              State);
      end Render_Heap_Channel_Copy_Expr;

      procedure Append_Heap_Channel_Copy
        (Channel_Item : CM.Resolved_Channel_Decl;
         Target_Name  : String;
         Expr         : CM.Expr_Access;
         Depth        : Natural)
      is
         Element_Info : constant GM.Type_Descriptor := Channel_Item.Element_Type;
         Source_Image : constant String :=
           Render_Heap_Channel_Copy_Expr (Channel_Item, Expr);
      begin
         if Is_Plain_String_Type (Unit, Document, Element_Info) then
            Append_Line
              (Buffer,
               Target_Name & " := Safe_String_RT.Clone (" & Source_Image & ");",
               Depth);
         elsif Is_Growable_Array_Type (Unit, Document, Element_Info) then
            Append_Line
              (Buffer,
               Target_Name
               & " := "
               & Array_Runtime_Instance_Name
                   (Base_Type (Unit, Document, Element_Info))
               & ".Clone ("
               & Source_Image
               & ");",
               Depth);
         else
            Append_Line
              (Buffer,
               Channel_Copy_Helper_Name (Channel_Item)
               & " ("
               & Target_Name
               & ", "
               & Source_Image
               & ");",
               Depth);
         end if;
      end Append_Heap_Channel_Copy;

      Declared_Channel : constant CM.Resolved_Channel_Decl :=
        Channel_Item (Item.Channel_Name);
   begin
      State.Needs_Gnat_Adc := True;
      if Has_Text (Declared_Channel.Name)
        and then Has_Heap_Value_Type
          (Unit,
           Document,
           Declared_Channel.Element_Type)
      then
         declare
            Staged_Name   : constant String := Channel_Staged_Value_Name (Index);
            Length_Name   : constant String := Channel_Staged_Length_Name (Index);
            Element_Type : constant String :=
              Render_Type_Name (Declared_Channel.Element_Type);
            Success_Image : constant String :=
              Render_Expr (Unit, Document, Item.Success_Var, State);
         begin
            Append_Line (Buffer, "declare", Depth);
            Append_Staged_Channel_Declarations
              (Buffer,
               Unit,
               Document,
               Declared_Channel,
               Staged_Name,
               Length_Name,
               Element_Type,
               "",
               Depth + 1,
               Suppress_Init_Warnings => True);
            Append_Line (Buffer, "begin", Depth);
            Append_Heap_Channel_Copy
              (Declared_Channel,
               Staged_Name,
               Item.Value,
               Depth + 1);
            if Channel_Has_Length_Model (Unit, Document, Declared_Channel) then
               Append_Line
                 (Buffer,
                  Length_Name
                  & " := "
                  & Channel_Length_Image
                      (Unit,
                       Document,
                       State,
                       Declared_Channel,
                       Staged_Name)
                  & ";",
                  Depth + 1);
            end if;
            Append_Staged_Channel_Call
              (Buffer,
               Unit,
               Document,
               Render_Channel_Operation_Target
                 (Unit,
                  Document,
                  State,
                  Item.Channel_Name,
                  Declared_Channel,
                  "Try_Send"),
               Declared_Channel,
               Staged_Name,
               Length_Name,
               Success_Image,
               Depth + 1,
               Force_Staged_Warnings => True,
               Wrap_Task_Call_Warnings => False);
            if State.Task_Body_Depth > 0 then
               Append_Task_If_Warning_Suppression (Buffer, Depth + 1);
            end if;
            Append_Local_Warning_Suppression (Buffer, Depth + 1);
            Append_Line
              (Buffer,
               "if not " & Success_Image & " then",
               Depth + 1);
            Append_Heap_Channel_Free
              (Buffer,
               Unit,
               Document,
               Declared_Channel,
               Staged_Name,
               Depth + 2);
            Append_Line (Buffer, "end if;", Depth + 1);
            Append_Local_Warning_Restore (Buffer, Depth + 1);
            if State.Task_Body_Depth > 0 then
               Append_Task_If_Warning_Restore (Buffer, Depth + 1);
            end if;
            Append_Line (Buffer, "end;", Depth);
         end;
      else
         Append_Line
           (Buffer,
           Render_Channel_Operation_Target
              (Unit,
               Document,
               State,
               Item.Channel_Name,
               Declared_Channel,
               "Try_Send")
            & " ("
            & Render_Channel_Send_Value
                (Unit, Document, State, Item.Channel_Name, Item.Value)
            & ", "
            & Render_Expr (Unit, Document, Item.Success_Var, State)
            & ");",
            Depth);
      end if;
   end Emit_Nonblocking_Send_Statement;

   procedure Emit_Call_Statement
     (Buffer          : in out SU.Unbounded_String;
      Unit            : CM.Resolved_Unit;
      Document        : GM.Mir_Document;
      Call_Expr       : CM.Expr_Access;
      Statement_Index : Positive;
      State           : in out Emit_State;
      Depth           : Natural)
   is
      function Find_Called_Subprogram
        (Call_Expr   : CM.Expr_Access;
         Subprogram  : out CM.Resolved_Subprogram) return Boolean
      is
         Callee_Flat   : constant String :=
           (if Call_Expr = null or else Call_Expr.Callee = null
            then ""
            else CM.Flatten_Name (Call_Expr.Callee));
         Lower_Callee  : constant String := FT.Lowercase (Callee_Flat);
         Selector_Name : constant String :=
           (if Call_Expr = null or else Call_Expr.Callee = null
            then ""
            elsif Call_Expr.Callee.Kind = CM.Expr_Ident
            then FT.To_String (Call_Expr.Callee.Name)
            elsif Call_Expr.Callee.Kind = CM.Expr_Select
            then FT.To_String (Call_Expr.Callee.Selector)
            else "");
      begin
         Subprogram := (others => <>);
         if Call_Expr = null
           or else Call_Expr.Kind /= CM.Expr_Call
           or else Lower_Callee'Length = 0
         then
            return False;
         end if;

         for Candidate of Unit.Subprograms loop
            if FT.Lowercase (FT.To_String (Candidate.Name)) = Lower_Callee
              or else
                FT.Lowercase
                  (FT.To_String (Unit.Package_Name) & "." & FT.To_String (Candidate.Name)) = Lower_Callee
            then
               Subprogram := Candidate;
               return True;
            end if;
         end loop;

         if Call_Expr.Callee /= null then
            declare
               Formal : CM.Symbol;
            begin
               for Position in 1 .. Natural (Call_Expr.Args.Length) loop
                  declare
                     Shared_Formal_Found : Boolean := False;
                     Shared_Formal_Type  : constant GM.Type_Descriptor :=
                       Shared_Call_Formal_Type
                         (Unit,
                          Document,
                          Call_Expr,
                          Position,
                          Shared_Formal_Found);
                  begin
                     exit when not Shared_Formal_Found;
                     Formal.Name :=
                       FT.To_UString
                         ("Value_" & Ada.Strings.Fixed.Trim (Positive'Image (Position), Ada.Strings.Both));
                     Formal.Kind := FT.To_UString ("param");
                     Formal.Mode :=
                       FT.To_UString
                         ((if Selector_Name = Shared_Pop_Last_Name
                               and then Position = Natural (Call_Expr.Args.Length)
                           then "out"
                           elsif Selector_Name = Shared_Remove_Name
                             and then Position = Natural (Call_Expr.Args.Length)
                           then "out"
                           else "in"));
                     Formal.Type_Info := Shared_Formal_Type;
                     Subprogram.Params.Append (Formal);
                  end;
               end loop;

               if not Subprogram.Params.Is_Empty then
                  Subprogram.Name := FT.To_UString (Selector_Name);
                  Subprogram.Kind := FT.To_UString ("procedure");
                  return True;
               end if;
            end;
         end if;

         return False;
      end Find_Called_Subprogram;

      function Needs_Growable_Indexed_Copy_Back
        (Formal : CM.Symbol;
         Actual : CM.Expr_Access) return Boolean
      is
         Mode : constant String := FT.To_String (Formal.Mode);
      begin
         return
           Actual /= null
           and then Actual.Kind = CM.Expr_Resolved_Index
           and then Actual.Prefix /= null
           and then Actual.Prefix.Kind in CM.Expr_Ident | CM.Expr_Select
           and then Natural (Actual.Args.Length) = 1
           and then Mode in "mut" | "in out" | "out"
           and then Is_Growable_Array_Type
             (Unit,
              Document,
              Base_Type
                (Unit,
                 Document,
                 Expr_Type_Info (Unit, Document, Actual.Prefix)));
      end Needs_Growable_Indexed_Copy_Back;

      function Mutable_Actual_Temp_Name
        (Statement_Index : Positive;
         Arg_Index       : Positive) return String is
      begin
         return
           "Safe_Call_Arg_"
           & Ada.Strings.Fixed.Trim
               (Natural'Image (Natural (Statement_Index)),
                Ada.Strings.Both)
           & "_"
           & Ada.Strings.Fixed.Trim
               (Natural'Image (Natural (Arg_Index)),
                Ada.Strings.Both);
      end Mutable_Actual_Temp_Name;

      procedure Append_Growable_Indexed_Writeback
        (Actual    : CM.Expr_Access;
         Temp_Name : String;
         Depth     : Natural)
      is
         Prefix_Info : constant GM.Type_Descriptor :=
           Base_Type
             (Unit,
              Document,
              Expr_Type_Info (Unit, Document, Actual.Prefix));
      begin
         State.Needs_Safe_Array_RT := True;
         Append_Line
           (Buffer,
            Array_Runtime_Instance_Name (Prefix_Info)
            & ".Replace_Element ("
            & Render_Expr (Unit, Document, Actual.Prefix, State)
            & ", Integer ("
            & Render_Expr
                (Unit,
                 Document,
                 Actual.Args (Actual.Args.First_Index),
                 State)
            & "), "
            & Temp_Name
            & ");",
            Depth);
      end Append_Growable_Indexed_Writeback;

      Target_Subprogram : CM.Resolved_Subprogram;
      Needs_Copy_Back   : Boolean := False;
   begin
      if not Find_Called_Subprogram (Call_Expr, Target_Subprogram)
        or else Call_Expr = null
        or else Call_Expr.Kind /= CM.Expr_Call
        or else Call_Expr.Args.Is_Empty
      then
         Append_Line
           (Buffer,
            Render_Expr (Unit, Document, Call_Expr, State) & ";",
            Depth);
         return;
      end if;

      for Formal_Index in Target_Subprogram.Params.First_Index .. Target_Subprogram.Params.Last_Index loop
         exit when Formal_Index > Call_Expr.Args.Last_Index;
         if Needs_Growable_Indexed_Copy_Back
           (Target_Subprogram.Params (Formal_Index),
            Call_Expr.Args (Formal_Index))
         then
            Needs_Copy_Back := True;
            exit;
         end if;
      end loop;

      if not Needs_Copy_Back then
         declare
            Call_Image : SU.Unbounded_String :=
              SU.To_Unbounded_String
                (Render_Expr (Unit, Document, Call_Expr.Callee, State) & " (");
         begin
            for Arg_Index in Call_Expr.Args.First_Index .. Call_Expr.Args.Last_Index loop
               declare
                  Arg_Image   : SU.Unbounded_String;
                  Used_Formal : Boolean := False;
               begin
                  if Arg_Index /= Call_Expr.Args.First_Index then
                     Call_Image := Call_Image & SU.To_Unbounded_String (", ");
                  end if;

                  if Arg_Index <= Target_Subprogram.Params.Last_Index then
                     declare
                        Formal : constant CM.Symbol := Target_Subprogram.Params (Arg_Index);
                     begin
                        if FT.To_String (Formal.Mode) in "" | "in" | "borrow" then
                           Arg_Image :=
                             SU.To_Unbounded_String
                               (Render_Expr_For_Target_Type
                                  (Unit,
                                   Document,
                                   Call_Expr.Args (Arg_Index),
                                   Formal.Type_Info,
                                   State));
                           Used_Formal := True;
                        end if;
                     end;
                  end if;

                  if not Used_Formal then
                     Arg_Image :=
                       SU.To_Unbounded_String
                         (Render_Expr
                            (Unit,
                             Document,
                             Call_Expr.Args (Arg_Index),
                             State));
                  end if;

                  Call_Image := Call_Image & Arg_Image;
               end;
            end loop;
            Call_Image := Call_Image & SU.To_Unbounded_String (")");
            Append_Line (Buffer, SU.To_String (Call_Image) & ";", Depth);
         end;
         return;
      end if;

      Append_Line (Buffer, "declare", Depth);
      for Formal_Index in Target_Subprogram.Params.First_Index .. Target_Subprogram.Params.Last_Index loop
         exit when Formal_Index > Call_Expr.Args.Last_Index;
         if Needs_Growable_Indexed_Copy_Back
           (Target_Subprogram.Params (Formal_Index),
            Call_Expr.Args (Formal_Index))
         then
            declare
               Formal     : constant CM.Symbol :=
                 Target_Subprogram.Params (Formal_Index);
               Temp_Name  : constant String :=
                 Mutable_Actual_Temp_Name (Statement_Index, Formal_Index);
               Init_Image : constant String :=
                 (if FT.To_String (Formal.Mode) = "out"
                  then
                    Default_Value_Expr
                      (Unit,
                       Document,
                       Formal.Type_Info)
                  else
                    Render_Expr_For_Target_Type
                      (Unit,
                       Document,
                       Call_Expr.Args (Formal_Index),
                       Formal.Type_Info,
                       State));
            begin
               Append_Line
                 (Buffer,
                  Temp_Name
                  & " : "
                  & Render_Type_Name (Formal.Type_Info)
                  & " := "
                  & Init_Image
                  & ";",
                  Depth + 1);
            end;
         end if;
      end loop;
      Append_Line (Buffer, "begin", Depth);
      declare
         Call_Image : SU.Unbounded_String :=
           SU.To_Unbounded_String
             (Render_Expr (Unit, Document, Call_Expr.Callee, State) & " (");
      begin
         for Arg_Index in Call_Expr.Args.First_Index .. Call_Expr.Args.Last_Index loop
            declare
               Arg_Image   : SU.Unbounded_String;
               Used_Formal : Boolean := False;
            begin
               if Arg_Index /= Call_Expr.Args.First_Index then
                  Call_Image := Call_Image & SU.To_Unbounded_String (", ");
               end if;

               if Arg_Index <= Target_Subprogram.Params.Last_Index
                 and then Needs_Growable_Indexed_Copy_Back
                   (Target_Subprogram.Params (Arg_Index),
                    Call_Expr.Args (Arg_Index))
               then
                  Arg_Image :=
                    SU.To_Unbounded_String
                      (Mutable_Actual_Temp_Name (Statement_Index, Arg_Index));
                  Used_Formal := True;
               elsif Arg_Index <= Target_Subprogram.Params.Last_Index then
                  declare
                     Formal : constant CM.Symbol := Target_Subprogram.Params (Arg_Index);
                  begin
                     if FT.To_String (Formal.Mode) in "" | "in" | "borrow" then
                        Arg_Image :=
                          SU.To_Unbounded_String
                            (Render_Expr_For_Target_Type
                               (Unit,
                                Document,
                                Call_Expr.Args (Arg_Index),
                                Formal.Type_Info,
                                State));
                        Used_Formal := True;
                     end if;
                  end;
               end if;

               if not Used_Formal then
                  Arg_Image :=
                    SU.To_Unbounded_String
                      (Render_Expr
                         (Unit,
                          Document,
                          Call_Expr.Args (Arg_Index),
                          State));
               end if;

               Call_Image := Call_Image & Arg_Image;
            end;
         end loop;
         Call_Image := Call_Image & SU.To_Unbounded_String (")");
         Append_Line (Buffer, SU.To_String (Call_Image) & ";", Depth + 1);
      end;

      for Formal_Index in Target_Subprogram.Params.First_Index .. Target_Subprogram.Params.Last_Index loop
         exit when Formal_Index > Call_Expr.Args.Last_Index;
         if Needs_Growable_Indexed_Copy_Back
           (Target_Subprogram.Params (Formal_Index),
            Call_Expr.Args (Formal_Index))
         then
            Append_Growable_Indexed_Writeback
              (Call_Expr.Args (Formal_Index),
               Mutable_Actual_Temp_Name (Statement_Index, Formal_Index),
               Depth + 1);
         end if;
      end loop;
      Append_Line (Buffer, "end;", Depth);
   end Emit_Call_Statement;

   procedure Render_Statements
     (Buffer     : in out SU.Unbounded_String;
      Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Statements : CM.Statement_Access_Vectors.Vector;
      State      : in out Emit_State;
      Depth      : Natural;
      Return_Type : String := "";
      In_Loop    : Boolean := False) renames AES.Render_Statements;
   procedure Render_Required_Statement_Suite
     (Buffer      : in out SU.Unbounded_String;
      Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      Statements  : CM.Statement_Access_Vectors.Vector;
      State       : in out Emit_State;
      Depth       : Natural;
      Return_Type : String := "";
      In_Loop     : Boolean := False) renames AES.Render_Required_Statement_Suite;
   procedure Render_Channel_Spec
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Channel  : CM.Resolved_Channel_Decl;
      Bronze   : MB.Bronze_Result)
   is
      Name          : constant String := FT.To_String (Channel.Name);
      Element_Type  : constant String := Render_Type_Name (Channel.Element_Type);
      Capacity      : constant String := Trim_Image (Channel.Capacity);
      Type_Name     : constant String := Name & "_Channel";
      Length_Helper : constant String := Name & "_Element_Length";
      Well_Formed_Helper : constant String := Name & "_Well_Formed";
      Index_Subtype : constant String := Name & "_Index";
      Count_Subtype : constant String := Name & "_Count";
      Length_Buffer_Type : constant String := Name & "_Length_Buffer";
      Buffer_Type   : constant String := Name & "_Buffer";
      Stored_Length : constant String := "Stored_Length";
      Model_Has_Value : constant String := Channel_Model_Has_Value_Name (Channel);
      Model_Length : constant String := Channel_Model_Length_Name (Channel);
      Heap_Value    : constant Boolean :=
        Has_Heap_Value_Type (Unit, Document, Channel.Element_Type);
      Has_Length_Model : constant Boolean :=
        Is_Plain_String_Type (Unit, Document, Channel.Element_Type)
        or else Is_Growable_Array_Type (Unit, Document, Channel.Element_Type);
      Single_Slot_Length_Model : constant Boolean :=
        Has_Length_Model and then Channel.Capacity = 1;
      Uses_Ghost_Scalar_Model : constant Boolean :=
        Channel_Uses_Sequential_Scalar_Ghost_Model
          (Unit, Document, Channel);
      --  The direct sequential single-slot string/growable path keeps the
      --  Value_Length formals even with the record-backed lowering so callers
      --  can carry the returned length directly through emitted proofs without
      --  relying on the protected-path receive-side equality bridge.
      Uses_Length_Formals : constant Boolean := Has_Length_Model;
      Uses_Runtime_Length_Buffer : constant Boolean :=
        Has_Length_Model and then not Uses_Ghost_Scalar_Model;
      Send_Mode     : constant String :=
        (if Heap_Value then "in out " else "in ");
      Receive_Mode  : constant String := "out ";
      Buffer_Default : constant String :=
        Default_Value_Expr (Unit, Document, Channel.Element_Type);
      Ghost_Send_Post : constant String :=
        Model_Has_Value
        & " and then "
        & Model_Length
        & " = Value_Length";
      Ghost_Model_Unchanged : constant String :=
        Model_Has_Value
        & " = "
        & Model_Has_Value
        & "'Old and then "
        & Model_Length
        & " = "
        & Model_Length
        & "'Old";
      Ghost_Receive_Post : constant String :=
        "Value_Length = "
        & Model_Length
        & "'Old and then (not "
        & Model_Has_Value
        & ") and then "
        & Model_Length
        & " = 0";
      Uses_Environment_Ceiling : constant Boolean :=
        Channel.Is_Public
        or else Channel_Uses_Environment_Task (Bronze, Name)
        or else Channel_Uses_Unspecified_Task_Priority (Unit, Bronze, Name);
      Ceiling       : Long_Long_Integer :=
        (if Channel.Has_Required_Ceiling then Channel.Required_Ceiling else 0);
   begin
      for Item of Bronze.Ceilings loop
         if FT.To_String (Item.Channel_Name) = Name then
            Ceiling := Item.Priority;
            exit;
         end if;
      end loop;
      if Uses_Ghost_Scalar_Model then
         Append_Line
           (Buffer,
            "type " & Type_Name & " is record",
            1);
         Append_Line
           (Buffer,
            "Value : " & Element_Type & " := " & Buffer_Default & ";",
            2);
         Append_Line (Buffer, "Full : Boolean := False;", 2);
         Append_Line (Buffer, "Stored_Length_Value : Natural := 0;", 2);
         Append_Line (Buffer, "end record;", 1);
         Append_Line (Buffer, Name & " : " & Type_Name & ";", 1);
         if Has_Length_Model then
            Append_Line
              (Buffer,
               "function "
               & Length_Helper
               & " (Value : "
               & Element_Type
               & ") return Natural with Global => null;",
               1);
            Append_Line
              (Buffer,
               "function "
               & Well_Formed_Helper
               & " return Boolean is ((if "
               & Name
               & ".Full then "
               & Name
               & ".Stored_Length_Value = "
               & Length_Helper
               & " ("
               & Name
               & ".Value) else "
               & Name
               & ".Stored_Length_Value = 0)) with Global => (Input => "
               & Name
               & ");",
               1);
         end if;
         Append_Line
           (Buffer,
            "procedure "
            & Name
            & "_Send (Value : "
            & Send_Mode
            & Element_Type
            & "; Value_Length : in Natural)"
            & " with Global => (In_Out => "
            & Name
            & "), Pre => "
            & Well_Formed_Helper
            & " and then not "
            & Name
            & ".Full and then Value_Length = "
            & Length_Helper
            & " (Value), Post => "
            & Well_Formed_Helper
            & " and then "
            & Name
            & ".Full and then "
            & Name
            & ".Stored_Length_Value = Value_Length;",
            1);
         Append_Line
           (Buffer,
            "procedure "
            & Name
            & "_Receive (Value : "
            & Receive_Mode
            & Element_Type
            & "; Value_Length : out Natural)"
            & " with Global => (In_Out => "
            & Name
            & "), Pre => "
            & Well_Formed_Helper
            & " and then "
            & Name
            & ".Full, Post => "
            & Well_Formed_Helper
            & " and then Value_Length = "
            & Name
            & ".Stored_Length_Value'Old and then Value_Length = "
            & Length_Helper
            & " (Value) and then not "
            & Name
            & ".Full and then "
            & Name
            & ".Stored_Length_Value = 0;",
            1);
         Append_Line
           (Buffer,
            "procedure "
            & Name
            & "_Try_Send (Value : "
            & Send_Mode
            & Element_Type
            & "; Value_Length : in Natural; Success : out Boolean)"
            & " with Global => (In_Out => "
            & Name
            & "), Pre => "
            & Well_Formed_Helper
            & " and then Value_Length = "
            & Length_Helper
            & " (Value), Post => "
            & Well_Formed_Helper
            & " and then (if Success then "
            & Name
            & ".Full and then "
            & Name
            & ".Stored_Length_Value = Value_Length else "
            & Name
            & ".Full = "
            & Name
            & ".Full'Old and then "
            & Name
            & ".Stored_Length_Value = "
            & Name
            & ".Stored_Length_Value'Old);",
            1);
         Append_Line
           (Buffer,
            "procedure "
            & Name
            & "_Try_Receive (Value : "
            & Receive_Mode
            & Element_Type
            & "; Value_Length : out Natural; Success : out Boolean)"
            & " with Global => (In_Out => "
            & Name
            & "), Pre => "
            & Well_Formed_Helper
            & ", Post => "
            & Well_Formed_Helper
            & " and then (if Success then Value_Length = "
            & Name
            & ".Stored_Length_Value'Old and then Value_Length = "
            & Length_Helper
            & " (Value) and then not "
            & Name
            & ".Full and then "
            & Name
            & ".Stored_Length_Value = 0 else Value_Length = 0 and then "
            & Name
            & ".Full = "
            & Name
            & ".Full'Old and then "
            & Name
            & ".Stored_Length_Value = "
            & Name
            & ".Stored_Length_Value'Old);",
            1);
         Append_Line (Buffer);
         return;
      end if;
      Append_Line
        (Buffer,
         "subtype " & Index_Subtype & " is Positive range 1 .. " & Capacity & ";",
         1);
      Append_Line
        (Buffer,
         "subtype " & Count_Subtype & " is Natural range 0 .. " & Capacity & ";",
         1);
      Append_Line
        (Buffer,
         "type " & Buffer_Type & " is array (" & Index_Subtype & ") of " & Element_Type & ";",
         1);
      if Uses_Runtime_Length_Buffer then
         Append_Line
           (Buffer,
            "type " & Length_Buffer_Type & " is array (" & Index_Subtype & ") of Natural;",
            1);
      end if;
      if Has_Length_Model then
         Append_Line
           (Buffer,
            "function "
            & Length_Helper
            & " (Value : "
            & Element_Type
            & ") return Natural with Global => null;",
            1);
         if Uses_Ghost_Scalar_Model then
            Append_Initialization_Warning_Suppression (Buffer, 1);
            --  These model scalars intentionally remain ordinary runtime
            --  declarations. On the current GNAT/SPARK toolchain, marking
            --  them as Ghost makes the protected send/receive bodies reject
            --  the generated reads/writes as illegal Ghost use in non-Ghost
            --  contexts.
            Append_Line
              (Buffer,
               Model_Has_Value & " : Boolean := False;",
               1);
            Append_Line
              (Buffer,
               Model_Length & " : Natural := 0;",
               1);
            Append_Initialization_Warning_Restore (Buffer, 1);
         end if;
      end if;
      Append_Line
        (Buffer,
        "protected type "
        & Type_Name
        & " with Priority => "
        & (if Uses_Environment_Ceiling
           then "System.Any_Priority'Last"
           else Trim_Image (Ceiling))
        & " is",
        1);
      Append_Line
        (Buffer,
         "entry Send (Value : "
         & Send_Mode
         & Element_Type
         & (if Uses_Length_Formals then "; Value_Length : in Natural" else "")
         & ")"
         & (if Uses_Ghost_Scalar_Model
            then " with Post => " & Ghost_Send_Post
            elsif Single_Slot_Length_Model
            then " with Post => " & Stored_Length & " = Value_Length"
            else "")
         & ";",
         2);
      Append_Line
        (Buffer,
         "entry Receive (Value : "
         & Receive_Mode
         & Element_Type
         & (if Uses_Length_Formals then "; Value_Length : out Natural" else "")
         & ")"
         & (if Uses_Ghost_Scalar_Model
            then " with Post => " & Ghost_Receive_Post
            elsif Single_Slot_Length_Model
            then
              " with Post => Value_Length = "
              & Stored_Length
              & "'Old and then "
              & Stored_Length
              & " = 0"
            else "")
         & ";",
         2);
      Append_Line
        (Buffer,
         "procedure Try_Send (Value : "
         & Send_Mode
         & Element_Type
         & (if Uses_Length_Formals then "; Value_Length : in Natural" else "")
         & "; Success : out Boolean)"
         & (if Uses_Ghost_Scalar_Model
            then
              " with Post => (if Success then "
              & Ghost_Send_Post
              & " else "
              & Ghost_Model_Unchanged
              & ")"
            else "")
         & ";",
         2);
      Append_Line
        (Buffer,
         "procedure Try_Receive (Value : "
         & Receive_Mode
         & Element_Type
         & (if Uses_Length_Formals then "; Value_Length : out Natural" else "")
         & "; Success : out Boolean)"
         & (if Uses_Ghost_Scalar_Model
            then
              " with Post => (if Success then "
              & Ghost_Receive_Post
              & " else "
              & Ghost_Model_Unchanged
              & " and then Value_Length = 0)"
            else "")
         & ";",
         2);
      if Single_Slot_Length_Model and then not Uses_Ghost_Scalar_Model then
         --  Keep the Stored_Length fallback for single-slot channels that do
         --  not qualify for the sequential Ghost-model path, such as the
         --  broader tasking/subprogram channel surface.
         Append_Line (Buffer, "function " & Stored_Length & " return Natural;", 2);
      end if;
      Append_Line (Buffer, "private", 1);
      Append_Line
         (Buffer,
          "Buffer : "
          & Buffer_Type
          & " := (others => "
          & Default_Value_Expr (Unit, Document, Channel.Element_Type)
          & ");",
          2);
      if Uses_Runtime_Length_Buffer then
         Append_Line
           (Buffer,
            "Lengths : " & Length_Buffer_Type & " := (others => 0);",
            2);
      end if;
      Append_Line (Buffer, "Head   : " & Index_Subtype & " := " & Index_Subtype & "'First;", 2);
      Append_Line (Buffer, "Tail   : " & Index_Subtype & " := " & Index_Subtype & "'First;", 2);
      Append_Line (Buffer, "Count  : " & Count_Subtype & " := 0;", 2);
      if Single_Slot_Length_Model and then not Uses_Ghost_Scalar_Model then
         Append_Line (Buffer, "Stored_Length_Value : Natural := 0;", 2);
      end if;
      Append_Line (Buffer, "end " & Type_Name & ";", 1);
      Append_Line (Buffer, Name & " : " & Type_Name & ";", 1);
      Append_Line (Buffer);
   end Render_Channel_Spec;

   procedure Render_Channel_Generated_Value_Helpers
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Channel  : CM.Resolved_Channel_Decl;
      State    : in out Emit_State)
   is
      Name          : constant String := FT.To_String (Channel.Name);
      Element_Type  : constant String := Render_Type_Name (Channel.Element_Type);
      Heap_Value    : constant Boolean :=
        Has_Heap_Value_Type (Unit, Document, Channel.Element_Type);
      Copy_Helper   : constant String := Name & "_Copy_Value";
      Free_Helper   : constant String := Name & "_Free_Value";
      Generated_Channel_Helpers : FT.UString_Vectors.Vector;
      Runtime_Dependency_Types  : FT.UString_Vectors.Vector;

      function Channel_Helper_Base_Name (Info : GM.Type_Descriptor) return String is
      begin
         return
           Heap_Helper_Base_Name
             (AI.Heap_Helper_Channel, Name, Unit, Document, Info);
      end Channel_Helper_Base_Name;

      function Channel_Copy_Helper_Name (Info : GM.Type_Descriptor) return String is
      begin
         return Channel_Helper_Base_Name (Info) & "_Copy";
      end Channel_Copy_Helper_Name;

      function Channel_Free_Helper_Name (Info : GM.Type_Descriptor) return String is
      begin
         return Channel_Helper_Base_Name (Info) & "_Free";
      end Channel_Free_Helper_Name;

      procedure Render_Channel_Value_Helpers (Info : GM.Type_Descriptor);

      procedure Render_Channel_Value_Helpers (Info : GM.Type_Descriptor) is
         Base      : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
         Kind      : constant String := FT.Lowercase (FT.To_String (Base.Kind));
         Type_Key  : constant String := Render_Type_Name (Info);
         Type_Name : constant String := Render_Type_Name (Info);

         procedure Ensure_Helper (Name_Text : String) is
         begin
            if Name_Text'Length = 0 then
               return;
            end if;

            Render_Channel_Value_Helpers
              (Resolve_Type_Name (Unit, Document, Name_Text));
         end Ensure_Helper;
      begin
         if not Needs_Generated_Heap_Helper (Unit, Document, Info)
           or else Contains_Name (Generated_Channel_Helpers, Type_Key)
         then
            return;
         end if;

         if Kind = "array" and then Base.Has_Component_Type then
            Ensure_Helper (FT.To_String (Base.Component_Type));
         elsif Kind = "record" then
            for Field of Base.Fields loop
               Ensure_Helper (FT.To_String (Field.Type_Name));
            end loop;
            for Field of Base.Variant_Fields loop
               Ensure_Helper (FT.To_String (Field.Type_Name));
            end loop;
         elsif Is_Tuple_Type (Base) then
            for Item of Base.Tuple_Element_Types loop
               Ensure_Helper (FT.To_String (Item));
            end loop;
         end if;

         Generated_Channel_Helpers.Append (FT.To_UString (Type_Key));

         Append_Line
           (Buffer,
            "procedure "
            & Channel_Copy_Helper_Name (Info)
            & " (Target : out "
            & Type_Name
            & "; Source : "
            & Type_Name
            & ");",
            1);
         Append_Line
           (Buffer,
            "procedure "
            & Channel_Copy_Helper_Name (Info)
            & " (Target : out "
            & Type_Name
            & "; Source : "
            & Type_Name
            & ") is",
            1);
         Append_Line (Buffer, "begin", 1);
         Append_Generated_Heap_Copy_Body
           (Buffer,
            Unit,
            Document,
            State,
            AI.Heap_Helper_Channel,
            Name,
            Info,
            2);
         Append_Line (Buffer, "end " & Channel_Copy_Helper_Name (Info) & ";", 1);
         Append_Line (Buffer);

         Append_Local_Warning_Suppression (Buffer, 1);
         Append_Line
           (Buffer,
            "procedure "
            & Channel_Free_Helper_Name (Info)
            & " (Value : in out "
            & Type_Name
            & ");",
            1);
         Append_Line
           (Buffer,
            "procedure "
            & Channel_Free_Helper_Name (Info)
            & " (Value : in out "
            & Type_Name
            & ") is",
            1);
         Append_Line (Buffer, "begin", 1);
         Append_Generated_Heap_Free_Body
           (Buffer,
            Unit,
            Document,
            State,
            AI.Heap_Helper_Channel,
            Name,
            Info,
            2);
         Append_Line
           (Buffer,
            "Value := " & Default_Value_Expr (Unit, Document, Info) & ";",
            2);
         Append_Line (Buffer, "end " & Channel_Free_Helper_Name (Info) & ";", 1);
         Append_Local_Warning_Restore (Buffer, 1);
         Append_Line (Buffer);
      end Render_Channel_Value_Helpers;
   begin
      if Heap_Value
        and then not Is_Plain_String_Type (Unit, Document, Channel.Element_Type)
        and then not Is_Growable_Array_Type (Unit, Document, Channel.Element_Type)
      then
         Mark_Heap_Runtime_Dependencies
           (Unit,
            Document,
            Channel.Element_Type,
            State,
            Runtime_Dependency_Types);
         Render_Channel_Value_Helpers (Channel.Element_Type);

         Append_Line
           (Buffer,
            "procedure "
            & Copy_Helper
            & " (Target : out "
            & Element_Type
            & "; Source : "
            & Element_Type
            & ");",
            1);
         Append_Line
           (Buffer,
            "procedure "
            & Copy_Helper
            & " (Target : out "
            & Element_Type
            & "; Source : "
            & Element_Type
            & ") is",
            1);
         Append_Line (Buffer, "begin", 1);
         Append_Line
           (Buffer,
            Channel_Copy_Helper_Name (Channel.Element_Type)
            & " (Target, Source);",
            2);
         Append_Line (Buffer, "end " & Copy_Helper & ";", 1);
         Append_Line (Buffer);

         Append_Local_Warning_Suppression (Buffer, 1);
         Append_Line
           (Buffer,
            "procedure "
            & Free_Helper
            & " (Value : in out "
            & Element_Type
            & ");",
            1);
         Append_Line
           (Buffer,
            "procedure "
            & Free_Helper
            & " (Value : in out "
            & Element_Type
            & ") is",
            1);
         Append_Line (Buffer, "begin", 1);
         Append_Heap_Free_Value
           (Buffer,
            Unit,
            Document,
            State,
            AI.Heap_Helper_Channel,
            Name,
            "Value",
            Channel.Element_Type,
            2);
         Append_Line (Buffer, "end " & Free_Helper & ";", 1);
         Append_Local_Warning_Restore (Buffer, 1);
         Append_Line (Buffer);
      end if;
   end Render_Channel_Generated_Value_Helpers;

   procedure Render_Channel_Body
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Channel  : CM.Resolved_Channel_Decl;
      State    : in out Emit_State)
   is
      Name          : constant String := FT.To_String (Channel.Name);
      Element_Type  : constant String := Render_Type_Name (Channel.Element_Type);
      Capacity      : constant String := Trim_Image (Channel.Capacity);
      Type_Name     : constant String := Name & "_Channel";
      Length_Helper : constant String := Name & "_Element_Length";
      Index_Subtype : constant String := Name & "_Index";
      Stored_Length : constant String := "Stored_Length";
      Model_Has_Value : constant String := Channel_Model_Has_Value_Name (Channel);
      Model_Length : constant String := Channel_Model_Length_Name (Channel);
      Heap_Value    : constant Boolean :=
        Has_Heap_Value_Type (Unit, Document, Channel.Element_Type);
      Has_Length_Model : constant Boolean :=
        Is_Plain_String_Type (Unit, Document, Channel.Element_Type)
        or else Is_Growable_Array_Type (Unit, Document, Channel.Element_Type);
      Single_Slot_Length_Model : constant Boolean :=
        Has_Length_Model and then Channel.Capacity = 1;
      Uses_Ghost_Scalar_Model : constant Boolean :=
        Channel_Uses_Sequential_Scalar_Ghost_Model
          (Unit, Document, Channel);
      --  See the matching note in Render_Channel_Spec: the Ghost-model path
      --  still carries Value_Length until the remaining receive-side bridge
      --  can be removed without reopening the proof lane.
      Uses_Length_Formals : constant Boolean := Has_Length_Model;
      Uses_Runtime_Length_Buffer : constant Boolean :=
        Has_Length_Model and then not Uses_Ghost_Scalar_Model;
      Send_Mode     : constant String :=
        (if Heap_Value then "in out " else "in ");
      Receive_Mode  : constant String := "out ";
      Buffer_Default : constant String :=
        Default_Value_Expr (Unit, Document, Channel.Element_Type);
   begin
      Render_Channel_Generated_Value_Helpers
        (Buffer, Unit, Document, Channel, State);

      if Has_Length_Model then
         Append_Line
           (Buffer,
            "function "
            & Length_Helper
            & " (Value : "
            & Element_Type
            & ") return Natural is ("
            & (if Is_Plain_String_Type (Unit, Document, Channel.Element_Type)
               then "Safe_String_RT.Length (Value)"
               else
                 Array_Runtime_Instance_Name
                   (Base_Type (Unit, Document, Channel.Element_Type))
                 & ".Length (Value)")
            & ");",
            1);
         Append_Line (Buffer);
      end if;

      if Uses_Ghost_Scalar_Model then
         Append_Line
           (Buffer,
            "procedure " & Name & "_Send (Value : " & Send_Mode & Element_Type & "; Value_Length : in Natural) is",
            1);
         Append_Line (Buffer, "begin", 1);
         Append_Line (Buffer, Name & ".Value := Value;", 2);
         Append_Line (Buffer, Name & ".Full := True;", 2);
         Append_Line (Buffer, Name & ".Stored_Length_Value := Value_Length;", 2);
         Append_Select_Dispatcher_Signals (Buffer, Unit, Name, 2);
         if Heap_Value then
            Append_Line (Buffer, "Value := " & Buffer_Default & ";", 2);
         end if;
         Append_Line (Buffer, "end " & Name & "_Send;", 1);
         Append_Line (Buffer);
         Append_Line
           (Buffer,
            "procedure " & Name & "_Receive (Value : " & Receive_Mode & Element_Type & "; Value_Length : out Natural) is",
            1);
         Append_Line (Buffer, "begin", 1);
         Append_Line (Buffer, "Value := " & Name & ".Value;", 2);
         Append_Line (Buffer, "Value_Length := " & Name & ".Stored_Length_Value;", 2);
         Append_Line (Buffer, Name & ".Value := " & Buffer_Default & ";", 2);
         Append_Line (Buffer, Name & ".Full := False;", 2);
         Append_Line (Buffer, Name & ".Stored_Length_Value := 0;", 2);
         Append_Line (Buffer, "end " & Name & "_Receive;", 1);
         Append_Line (Buffer);
         Append_Line
           (Buffer,
            "procedure " & Name & "_Try_Send (Value : " & Send_Mode & Element_Type & "; Value_Length : in Natural; Success : out Boolean) is",
            1);
         Append_Line (Buffer, "begin", 1);
         Append_Line (Buffer, "if not " & Name & ".Full then", 2);
         Append_Line (Buffer, Name & ".Value := Value;", 3);
         Append_Line (Buffer, Name & ".Full := True;", 3);
         Append_Line (Buffer, Name & ".Stored_Length_Value := Value_Length;", 3);
         Append_Select_Dispatcher_Signals (Buffer, Unit, Name, 3);
         if Heap_Value then
            Append_Line (Buffer, "Value := " & Buffer_Default & ";", 3);
         end if;
         Append_Line (Buffer, "Success := True;", 3);
         Append_Line (Buffer, "else", 2);
         Append_Line (Buffer, "Success := False;", 3);
         Append_Line (Buffer, "end if;", 2);
         Append_Line (Buffer, "end " & Name & "_Try_Send;", 1);
         Append_Line (Buffer);
         Append_Line
           (Buffer,
            "procedure " & Name & "_Try_Receive (Value : " & Receive_Mode & Element_Type & "; Value_Length : out Natural; Success : out Boolean) is",
            1);
         Append_Line (Buffer, "begin", 1);
         Append_Line (Buffer, "if " & Name & ".Full then", 2);
         Append_Line (Buffer, "Value := " & Name & ".Value;", 3);
         Append_Line (Buffer, "Value_Length := " & Name & ".Stored_Length_Value;", 3);
         Append_Line (Buffer, Name & ".Value := " & Buffer_Default & ";", 3);
         Append_Line (Buffer, Name & ".Full := False;", 3);
         Append_Line (Buffer, Name & ".Stored_Length_Value := 0;", 3);
         Append_Line (Buffer, "Success := True;", 3);
         Append_Line (Buffer, "else", 2);
         Append_Line (Buffer, "Value := " & Buffer_Default & ";", 3);
         Append_Line (Buffer, "Value_Length := 0;", 3);
         Append_Line (Buffer, "Success := False;", 3);
         Append_Line (Buffer, "end if;", 2);
         Append_Line (Buffer, "end " & Name & "_Try_Receive;", 1);
         Append_Line (Buffer);
         return;
      end if;

      Append_Line (Buffer, "protected body " & Type_Name & " is", 1);
      if Single_Slot_Length_Model and then not Uses_Ghost_Scalar_Model then
         Append_Line
           (Buffer,
            "function " & Stored_Length & " return Natural is (Stored_Length_Value);",
            2);
         Append_Line (Buffer);
      end if;
      Append_Line
        (Buffer,
         "entry Send (Value : "
         & Send_Mode
         & Element_Type
         & (if Uses_Length_Formals then "; Value_Length : in Natural" else "")
         & ")",
         2);
      Append_Line
        (Buffer,
         "when Count < "
         & Capacity
         & " is",
         3);
      Append_Line (Buffer, "begin", 2);
      Append_Line (Buffer, "Buffer (Tail) := Value;", 3);
      if Uses_Ghost_Scalar_Model then
         Append_Line
           (Buffer,
            Model_Has_Value & " := True;",
            3);
         Append_Line
           (Buffer,
            Model_Length & " := Value_Length;",
            3);
      elsif Uses_Runtime_Length_Buffer then
         Append_Line (Buffer, "Lengths (Tail) := Value_Length;", 3);
         if Single_Slot_Length_Model then
            Append_Line (Buffer, "Stored_Length_Value := Value_Length;", 3);
         end if;
      end if;
      if Heap_Value then
         Append_Line (Buffer, "Value := " & Buffer_Default & ";", 3);
      end if;
      Append_Line (Buffer, "if Tail = " & Index_Subtype & "'Last then", 3);
      Append_Line (Buffer, "Tail := " & Index_Subtype & "'First;", 4);
      Append_Line (Buffer, "else", 3);
      Append_Line (Buffer, "Tail := " & Index_Subtype & "'Succ (Tail);", 4);
      Append_Line (Buffer, "end if;", 3);
      Append_Line (Buffer, "Count := Count + 1;", 3);
      Append_Select_Dispatcher_Signals (Buffer, Unit, Name, 3);
      Append_Line (Buffer, "end Send;", 2);
      Append_Line (Buffer);
      Append_Line
        (Buffer,
         "entry Receive (Value : "
         & Receive_Mode
         & Element_Type
         & (if Uses_Length_Formals then "; Value_Length : out Natural" else "")
         & ")",
         2);
      Append_Line
        (Buffer,
         "when Count > 0"
         & " is",
         3);
      Append_Line (Buffer, "begin", 2);
      Append_Line (Buffer, "Value := Buffer (Head);", 3);
      if Uses_Ghost_Scalar_Model then
         Append_Line (Buffer, "Value_Length := " & Model_Length & ";", 3);
         Append_Line (Buffer, Model_Has_Value & " := False;", 3);
         Append_Line (Buffer, Model_Length & " := 0;", 3);
      elsif Uses_Runtime_Length_Buffer then
         if Single_Slot_Length_Model then
            Append_Line (Buffer, "Value_Length := Stored_Length_Value;", 3);
         else
            Append_Line (Buffer, "Value_Length := Lengths (Head);", 3);
         end if;
      end if;
      Append_Line (Buffer, "Buffer (Head) := " & Buffer_Default & ";", 3);
      if Uses_Runtime_Length_Buffer then
         Append_Line (Buffer, "Lengths (Head) := 0;", 3);
         if Single_Slot_Length_Model then
            Append_Line (Buffer, "Stored_Length_Value := 0;", 3);
         end if;
      end if;
      Append_Line (Buffer, "if Head = " & Index_Subtype & "'Last then", 3);
      Append_Line (Buffer, "Head := " & Index_Subtype & "'First;", 4);
      Append_Line (Buffer, "else", 3);
      Append_Line (Buffer, "Head := " & Index_Subtype & "'Succ (Head);", 4);
      Append_Line (Buffer, "end if;", 3);
      Append_Line (Buffer, "Count := Count - 1;", 3);
      Append_Line (Buffer, "end Receive;", 2);
      Append_Line (Buffer);
      Append_Line
        (Buffer,
         "procedure Try_Send (Value : " & Send_Mode
         & Element_Type
         & (if Uses_Length_Formals then "; Value_Length : in Natural" else "")
         & "; Success : out Boolean) is",
         2);
      Append_Line (Buffer, "begin", 2);
      Append_Line
        (Buffer,
        "if Count < "
         & Capacity
         & " then",
         3);
      Append_Line (Buffer, "Buffer (Tail) := Value;", 4);
      if Uses_Ghost_Scalar_Model then
         Append_Line (Buffer, Model_Has_Value & " := True;", 4);
         Append_Line
           (Buffer,
            Model_Length & " := Value_Length;",
            4);
      elsif Uses_Runtime_Length_Buffer then
         Append_Line (Buffer, "Lengths (Tail) := Value_Length;", 4);
         if Single_Slot_Length_Model then
            Append_Line (Buffer, "Stored_Length_Value := Value_Length;", 4);
         end if;
      end if;
      if Heap_Value then
         Append_Line (Buffer, "Value := " & Buffer_Default & ";", 4);
      end if;
      Append_Line (Buffer, "if Tail = " & Index_Subtype & "'Last then", 4);
      Append_Line (Buffer, "Tail := " & Index_Subtype & "'First;", 5);
      Append_Line (Buffer, "else", 4);
      Append_Line (Buffer, "Tail := " & Index_Subtype & "'Succ (Tail);", 5);
      Append_Line (Buffer, "end if;", 4);
      Append_Line (Buffer, "Count := Count + 1;", 4);
      Append_Select_Dispatcher_Signals (Buffer, Unit, Name, 4);
      Append_Line (Buffer, "Success := True;", 4);
      Append_Line (Buffer, "else", 3);
      Append_Line (Buffer, "Success := False;", 4);
      Append_Line (Buffer, "end if;", 3);
      Append_Line (Buffer, "end Try_Send;", 2);
      Append_Line (Buffer);
      Append_Line
        (Buffer,
         "procedure Try_Receive (Value : "
         & Receive_Mode
         & Element_Type
         & (if Uses_Length_Formals then "; Value_Length : out Natural" else "")
         & "; Success : out Boolean) is",
         2);
      Append_Line (Buffer, "begin", 2);
      Append_Line (Buffer, "if Count > 0 then", 3);
      Append_Line (Buffer, "Value := Buffer (Head);", 4);
      if Uses_Ghost_Scalar_Model then
         Append_Line (Buffer, "Value_Length := " & Model_Length & ";", 4);
         Append_Line (Buffer, Model_Has_Value & " := False;", 4);
         Append_Line (Buffer, Model_Length & " := 0;", 4);
      elsif Uses_Runtime_Length_Buffer then
         if Single_Slot_Length_Model then
            Append_Line (Buffer, "Value_Length := Stored_Length_Value;", 4);
         else
            Append_Line (Buffer, "Value_Length := Lengths (Head);", 4);
         end if;
      end if;
      Append_Line (Buffer, "Buffer (Head) := " & Buffer_Default & ";", 4);
      if Uses_Runtime_Length_Buffer then
         Append_Line (Buffer, "Lengths (Head) := 0;", 4);
         if Single_Slot_Length_Model then
            Append_Line (Buffer, "Stored_Length_Value := 0;", 4);
         end if;
      end if;
      Append_Line (Buffer, "if Head = " & Index_Subtype & "'Last then", 4);
      Append_Line (Buffer, "Head := " & Index_Subtype & "'First;", 5);
      Append_Line (Buffer, "else", 4);
      Append_Line (Buffer, "Head := " & Index_Subtype & "'Succ (Head);", 5);
      Append_Line (Buffer, "end if;", 4);
      Append_Line (Buffer, "Count := Count - 1;", 4);
      Append_Line (Buffer, "Success := True;", 4);
      Append_Line (Buffer, "else", 3);
      Append_Line (Buffer, "Value := " & Buffer_Default & ";", 4);
      if Uses_Length_Formals then
         Append_Line (Buffer, "Value_Length := 0;", 4);
      end if;
      Append_Line (Buffer, "Success := False;", 4);
      Append_Line (Buffer, "end if;", 3);
      Append_Line (Buffer, "end Try_Receive;", 2);
      Append_Line (Buffer, "end " & Type_Name & ";", 1);
      Append_Line (Buffer);
   end Render_Channel_Body;
   function Effective_Subprogram_Outer_Declarations
     (Subprogram              : CM.Resolved_Subprogram;
      Raw_Outer_Declarations : CM.Resolved_Object_Decl_Vectors.Vector)
      return CM.Resolved_Object_Decl_Vectors.Vector
   is
      function Later_Outer_Declarations_Use_Name
        (Decl_Index : Positive;
         Name       : String) return Boolean is
      begin
         if Raw_Outer_Declarations.Is_Empty
           or else Decl_Index >= Raw_Outer_Declarations.Last_Index
         then
            return False;
         end if;

         for Later_Index in Decl_Index + 1 .. Raw_Outer_Declarations.Last_Index loop
            declare
               Later_Decl : constant CM.Resolved_Object_Decl :=
                 Raw_Outer_Declarations (Later_Index);
            begin
               if Later_Decl.Initializer /= null
                 and then Expr_Uses_Name (Later_Decl.Initializer, Name)
               then
                  return True;
               end if;
            end;
         end loop;

         return False;
      end Later_Outer_Declarations_Use_Name;

      function Should_Elide_Dead_Owner_Decl
        (Decl_Index : Positive;
         Decl       : CM.Resolved_Object_Decl) return Boolean is
         Decl_Name : constant String :=
           FT.To_String (Decl.Names (Decl.Names.First_Index));
      begin
         return
           not Decl.Is_Constant
           and then Is_Owner_Access (Decl.Type_Info)
           and then Decl.Has_Initializer
           and then Decl.Names.Length = 1
           and then Decl.Initializer /= null
           and then Decl.Initializer.Kind in CM.Expr_Aggregate | CM.Expr_Tuple
           and then not
             Statements_Use_Name (Subprogram.Statements, Decl_Name)
           and then not Later_Outer_Declarations_Use_Name (Decl_Index, Decl_Name);
      end Should_Elide_Dead_Owner_Decl;

      Result : CM.Resolved_Object_Decl_Vectors.Vector;
   begin
      for Decl_Index in Raw_Outer_Declarations.First_Index .. Raw_Outer_Declarations.Last_Index loop
         declare
            Decl : constant CM.Resolved_Object_Decl :=
              Raw_Outer_Declarations (Decl_Index);
         begin
            if not Should_Elide_Dead_Owner_Decl (Decl_Index, Decl) then
               Result.Append (Decl);
            end if;
         end;
      end loop;
      return Result;
   end Effective_Subprogram_Outer_Declarations;

   function Apply_Name_Replacements
     (Text       : String;
      From_Names : FT.UString_Vectors.Vector;
      To_Names   : FT.UString_Vectors.Vector) return String renames AEX.Apply_Name_Replacements;
   function Render_Structural_Traversal_Subprogram_Body
     (Buffer     : in out SU.Unbounded_String;
      Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram;
      State      : in out Emit_State) return Boolean
   is
      Subprogram_Name : constant String :=
        FT.Lowercase (FT.To_String (Subprogram.Name));

      function Is_Direct_Null_Check
        (Expr : CM.Expr_Access;
         Name : String) return Boolean;

      function Single_Return_Expr
        (Statements : CM.Statement_Access_Vectors.Vector) return CM.Expr_Access;

      function Recursive_Call_From_Return
        (Statements : CM.Statement_Access_Vectors.Vector) return CM.Expr_Access;

      function Is_Direct_Null_Check
        (Expr : CM.Expr_Access;
         Name : String) return Boolean
      is
         Operator : constant String :=
           (if Expr = null then "" else Map_Operator (FT.To_String (Expr.Operator)));
      begin
         return
           Expr /= null
           and then Expr.Kind = CM.Expr_Binary
           and then Operator = "="
           and then
             ((Expr.Left /= null
               and then Expr.Left.Kind = CM.Expr_Ident
               and then FT.To_String (Expr.Left.Name) = Name
               and then Expr.Right /= null
               and then Expr.Right.Kind = CM.Expr_Null)
              or else
              (Expr.Right /= null
               and then Expr.Right.Kind = CM.Expr_Ident
               and then FT.To_String (Expr.Right.Name) = Name
               and then Expr.Left /= null
               and then Expr.Left.Kind = CM.Expr_Null));
      end Is_Direct_Null_Check;

      function Single_Return_Expr
        (Statements : CM.Statement_Access_Vectors.Vector) return CM.Expr_Access
      is
      begin
         if Statements.Length /= 1
           or else Statements (Statements.First_Index) = null
           or else Statements (Statements.First_Index).Kind /= CM.Stmt_Return
         then
            return null;
         end if;

         return Statements (Statements.First_Index).Value;
      end Single_Return_Expr;

      function Recursive_Call_From_Return
        (Statements : CM.Statement_Access_Vectors.Vector) return CM.Expr_Access
      is
         Return_Expr : constant CM.Expr_Access := Single_Return_Expr (Statements);
      begin
         if Return_Expr /= null
           and then Return_Expr.Kind = CM.Expr_Call
           and then Return_Expr.Callee /= null
           and then FT.Lowercase (CM.Flatten_Name (Return_Expr.Callee)) = Subprogram_Name
         then
            return Return_Expr;
         end if;
         return null;
      end Recursive_Call_From_Return;

      function Render_Structural_Observer return Boolean is
         Param               : constant CM.Symbol :=
           Subprogram.Params (Subprogram.Params.First_Index);
         Param_Name          : constant String := FT.To_String (Param.Name);
         Param_Image         : constant String := Ada_Safe_Name (Param_Name);
         Cursor_Name         : constant String := "Cursor";
         Cursor_Type_Image   : constant String :=
           (if Has_Text (Param.Type_Info.Target)
            then "access constant " & FT.To_String (Param.Type_Info.Target)
            else "");
         If_Stmt             : CM.Statement_Access := null;
         Recursive_Call      : CM.Expr_Access := null;
         Default_Return_Expr : CM.Expr_Access := null;
         From_Names          : FT.UString_Vectors.Vector;
         To_Names            : FT.UString_Vectors.Vector;
      begin
         if not Subprogram.Declarations.Is_Empty
           or else Subprogram.Params.Length /= 1
           or else Subprogram.Statements.Length /= 1
           or else not Is_Owner_Access (Param.Type_Info)
           or else Cursor_Type_Image'Length = 0
         then
            return False;
         end if;

         If_Stmt := Subprogram.Statements (Subprogram.Statements.First_Index);
         if If_Stmt = null
           or else If_Stmt.Kind /= CM.Stmt_If
           or else not Is_Direct_Null_Check (If_Stmt.Condition, Param_Name)
           or else not If_Stmt.Has_Else
         then
            return False;
         end if;

         Default_Return_Expr := Single_Return_Expr (If_Stmt.Then_Stmts);
         Recursive_Call := Recursive_Call_From_Return (If_Stmt.Else_Stmts);
         if Default_Return_Expr = null
           or else Recursive_Call = null
           or else Recursive_Call.Args.Length /= 1
           or else Root_Name (Recursive_Call.Args (Recursive_Call.Args.First_Index)) /= Param_Name
         then
            return False;
         end if;

         for Part of If_Stmt.Elsifs loop
            if Single_Return_Expr (Part.Statements) = null then
               return False;
            end if;
         end loop;

         From_Names.Append (FT.To_UString (Param_Image));
         To_Names.Append (FT.To_UString (Cursor_Name));

         Append_Line
           (Buffer,
            Cursor_Name & " : " & Cursor_Type_Image & " := " & Param_Image & ";",
            2);
         Append_Line (Buffer, "begin", 1);
         Append_Line (Buffer, "while " & Cursor_Name & " /= null loop", 2);
         Append_Line (Buffer, "pragma Loop_Variant (Structural => " & Cursor_Name & ");", 3);

         for Part of If_Stmt.Elsifs loop
            declare
               Branch_Return : constant CM.Expr_Access := Single_Return_Expr (Part.Statements);
            begin
               Append_Line
                 (Buffer,
                  "if "
                  & Apply_Name_Replacements
                      (Render_Expr (Unit, Document, Part.Condition, State),
                       From_Names,
                       To_Names)
                  & " then",
                  3);
               Append_Line
                 (Buffer,
                  "return "
                  & Apply_Name_Replacements
                      (Render_Expr (Unit, Document, Branch_Return, State),
                       From_Names,
                       To_Names)
                  & ";",
                  4);
               Append_Line (Buffer, "end if;", 3);
            end;
         end loop;

         Append_Line
           (Buffer,
            Cursor_Name
            & " := "
            & Apply_Name_Replacements
                (Render_Expr
                   (Unit,
                    Document,
                    Recursive_Call.Args (Recursive_Call.Args.First_Index),
                    State),
                 From_Names,
                 To_Names)
            & ";",
            3);
         Append_Line (Buffer, "end loop;", 2);
         Append_Line
           (Buffer,
            "return "
            & Apply_Name_Replacements
                (Render_Expr (Unit, Document, Default_Return_Expr, State),
                 From_Names,
                 To_Names)
            & ";",
            2);
         return True;
      end Render_Structural_Observer;

      function Render_Structural_Accumulator return Boolean is
         First_Param        : constant CM.Symbol :=
           Subprogram.Params (Subprogram.Params.First_Index);
         First_Param_Name   : constant String := FT.To_String (First_Param.Name);
         First_Param_Image  : constant String := Ada_Safe_Name (First_Param_Name);
         Cursor_Name        : constant String := "Cursor";
         Cursor_Type_Image  : constant String :=
           (if Has_Text (First_Param.Type_Info.Target)
            then "access constant " & FT.To_String (First_Param.Type_Info.Target)
            else "");
         First_Stmt         : CM.Statement_Access := null;
         Recursive_Assign   : CM.Statement_Access := null;
         Final_Return       : CM.Statement_Access := null;
         Recursive_Call     : CM.Expr_Access := null;
         Entry_Exit_Image   : SU.Unbounded_String := SU.Null_Unbounded_String;
         Final_Return_Image : SU.Unbounded_String := SU.Null_Unbounded_String;
         Bound_Image        : SU.Unbounded_String := SU.Null_Unbounded_String;
         From_Names         : FT.UString_Vectors.Vector;
         To_Names           : FT.UString_Vectors.Vector;
         State_Names        : FT.UString_Vectors.Vector;
      begin
         if Subprogram.Declarations.Is_Empty
           or else Subprogram.Params.Length < 2
           or else Subprogram.Statements.Length < 4
           or else not Is_Owner_Access (First_Param.Type_Info)
           or else Cursor_Type_Image'Length = 0
         then
            return False;
         end if;

         First_Stmt := Subprogram.Statements (Subprogram.Statements.First_Index);
         Recursive_Assign := Subprogram.Statements (Subprogram.Statements.Last_Index - 1);
         Final_Return := Subprogram.Statements (Subprogram.Statements.Last_Index);
         if First_Stmt = null
           or else First_Stmt.Kind /= CM.Stmt_If
           or else Single_Return_Expr (First_Stmt.Then_Stmts) = null
           or else First_Stmt.Has_Else
           or else not First_Stmt.Elsifs.Is_Empty
           or else Recursive_Assign = null
           or else Recursive_Assign.Kind /= CM.Stmt_Assign
           or else Recursive_Assign.Value = null
           or else Recursive_Assign.Value.Kind /= CM.Expr_Call
           or else Recursive_Assign.Value.Callee = null
           or else FT.Lowercase (CM.Flatten_Name (Recursive_Assign.Value.Callee)) /= Subprogram_Name
           or else Final_Return = null
           or else Final_Return.Kind /= CM.Stmt_Return
           or else Root_Name (Final_Return.Value) /= Root_Name (Recursive_Assign.Target)
         then
            return False;
         end if;

         Recursive_Call := Recursive_Assign.Value;
         if Recursive_Call.Args.Length /= Subprogram.Params.Length
           or else Root_Name (Recursive_Call.Args (Recursive_Call.Args.First_Index)) /= First_Param_Name
         then
            return False;
         end if;

         From_Names.Append (FT.To_UString (First_Param_Image));
         To_Names.Append (FT.To_UString (Cursor_Name));

         for Param_Index in Subprogram.Params.First_Index + 1 .. Subprogram.Params.Last_Index loop
            declare
               Param      : constant CM.Symbol := Subprogram.Params (Param_Index);
               Param_Name : constant String := Ada_Safe_Name (FT.To_String (Param.Name));
               State_Name : constant String := Param_Name & "_State";
            begin
               State_Names.Append (FT.To_UString (State_Name));
               From_Names.Append (FT.To_UString (Param_Name));
               To_Names.Append (FT.To_UString (State_Name));
            end;
         end loop;

         for Arg_Index in Recursive_Call.Args.First_Index + 1 .. Recursive_Call.Args.Last_Index loop
            declare
               Root : constant String := Ada_Safe_Name (Root_Name (Recursive_Call.Args (Arg_Index)));
            begin
               if Root'Length > 0 then
                  From_Names.Append (FT.To_UString (Root));
                  To_Names.Append
                    (State_Names
                       (State_Names.First_Index
                        + (Arg_Index - (Recursive_Call.Args.First_Index + 1))));
               end if;
            end;
         end loop;

         declare
            Leading_Condition : constant CM.Expr_Access := First_Stmt.Condition;
            Operator          : constant String :=
              (if Leading_Condition = null then "" else Map_Operator (FT.To_String (Leading_Condition.Operator)));
            Leading_Return    : constant CM.Expr_Access :=
              Single_Return_Expr (First_Stmt.Then_Stmts);
         begin
            if Is_Direct_Null_Check (Leading_Condition, First_Param_Name) then
               null;
            elsif Leading_Condition /= null
              and then Leading_Condition.Kind = CM.Expr_Binary
              and then Operator = "or else"
            then
               if Is_Direct_Null_Check (Leading_Condition.Left, First_Param_Name) then
                  Entry_Exit_Image :=
                    SU.To_Unbounded_String
                      (Apply_Name_Replacements
                         (Render_Expr (Unit, Document, Leading_Condition.Right, State),
                          From_Names,
                          To_Names));
               elsif Is_Direct_Null_Check (Leading_Condition.Right, First_Param_Name) then
                  Entry_Exit_Image :=
                    SU.To_Unbounded_String
                      (Apply_Name_Replacements
                         (Render_Expr (Unit, Document, Leading_Condition.Left, State),
                          From_Names,
                          To_Names));
               else
                  return False;
               end if;
            else
               return False;
            end if;

            Final_Return_Image :=
              SU.To_Unbounded_String
                (Apply_Name_Replacements
                   (Render_Expr (Unit, Document, Leading_Return, State),
                    From_Names,
                    To_Names));
         end;

         Append_Line
           (Buffer,
            Cursor_Name & " : " & Cursor_Type_Image & " := " & First_Param_Image & ";",
            2);
         for Param_Index in Subprogram.Params.First_Index + 1 .. Subprogram.Params.Last_Index loop
            declare
               Param      : constant CM.Symbol := Subprogram.Params (Param_Index);
               State_Name : constant String :=
                 FT.To_String
                   (State_Names
                      (State_Names.First_Index
                       + (Param_Index - (Subprogram.Params.First_Index + 1))));
            begin
               Append_Line
                 (Buffer,
                  State_Name
                  & " : "
                  & Render_Type_Name (Param.Type_Info)
                  & " := "
                  & Ada_Safe_Name (FT.To_String (Param.Name))
                  & ";",
                  2);
            end;
         end loop;

         Append_Line (Buffer, "begin", 1);
         Append_Line (Buffer, "while " & Cursor_Name & " /= null loop", 2);
         Append_Line (Buffer, "pragma Loop_Variant (Structural => " & Cursor_Name & ");", 3);
         for Param_Index in Subprogram.Params.First_Index + 1 .. Subprogram.Params.Last_Index loop
            declare
               Param      : constant CM.Symbol := Subprogram.Params (Param_Index);
               State_Name : constant String :=
                 FT.To_String
                   (State_Names
                      (State_Names.First_Index
                       + (Param_Index - (Subprogram.Params.First_Index + 1))));
            begin
               if not Is_Access_Type (Param.Type_Info) then
                  Append_Line
                    (Buffer,
                     "pragma Loop_Invariant ("
                     & State_Name
                     & " in "
                     & Render_Type_Name (Param.Type_Info)
                     & ");",
                     3);
               end if;
            end;
         end loop;
         if State_Names.Length >= 2 then
            Bound_Image :=
              SU.To_Unbounded_String
                (Structural_Accumulator_Count_Total_Bound
                   (Unit,
                    Document,
                    Subprogram,
                    FT.To_String (State_Names (State_Names.First_Index)),
                    FT.To_String (State_Names (State_Names.First_Index + 1)),
                    State));
            if SU.Length (Bound_Image) > 0 then
               Append_Line
                 (Buffer,
                  "pragma Loop_Invariant (" & SU.To_String (Bound_Image) & ");",
                  3);
            end if;
         end if;

         if SU.Length (Entry_Exit_Image) > 0 then
            Append_Line (Buffer, "exit when " & SU.To_String (Entry_Exit_Image) & ";", 3);
         end if;

         for Statement_Index in Subprogram.Statements.First_Index + 1 .. Subprogram.Statements.Last_Index - 2 loop
            declare
               Item : constant CM.Statement_Access := Subprogram.Statements (Statement_Index);
            begin
               if Item = null then
                  return False;
               end if;

               case Item.Kind is
                  when CM.Stmt_Assign =>
                     declare
                        Target_Name : constant String :=
                          Apply_Name_Replacements
                            (Ada_Safe_Name (Root_Name (Item.Target)),
                             From_Names,
                             To_Names);
                     begin
                        if Target_Name'Length = 0 then
                           return False;
                        end if;

                        Append_Line
                          (Buffer,
                           Target_Name
                           & " := "
                           & Apply_Name_Replacements
                               (Render_Expr (Unit, Document, Item.Value, State),
                                From_Names,
                                To_Names)
                           & ";",
                           3);
                     end;
                  when CM.Stmt_If =>
                     declare
                        Branch_Return : constant CM.Expr_Access :=
                          Single_Return_Expr (Item.Then_Stmts);
                        Branch_Return_Image : constant String :=
                          (if Branch_Return = null
                           then ""
                           else
                             Apply_Name_Replacements
                               (Render_Expr
                                  (Unit,
                                   Document,
                                   Branch_Return,
                                   State),
                                From_Names,
                                To_Names));
                     begin
                        if Branch_Return = null
                          or else Item.Has_Else
                          or else not Item.Elsifs.Is_Empty
                          or else Branch_Return_Image /= SU.To_String (Final_Return_Image)
                        then
                           return False;
                        end if;

                        Append_Line
                          (Buffer,
                           "exit when "
                           & Apply_Name_Replacements
                               (Render_Expr (Unit, Document, Item.Condition, State),
                                From_Names,
                                To_Names)
                           & ";",
                           3);
                     end;
                  when others =>
                     return False;
               end case;
            end;
         end loop;

         Append_Line
           (Buffer,
            Cursor_Name
            & " := "
            & Apply_Name_Replacements
                (Render_Expr
                   (Unit,
                    Document,
                    Recursive_Call.Args (Recursive_Call.Args.First_Index),
                    State),
                 From_Names,
                 To_Names)
            & ";",
            3);
         Append_Line (Buffer, "end loop;", 2);
         Append_Line (Buffer, "return " & SU.To_String (Final_Return_Image) & ";", 2);
         return True;
      end Render_Structural_Accumulator;
   begin
      if Render_Structural_Observer then
         return True;
      end if;

      return Render_Structural_Accumulator;
   end Render_Structural_Traversal_Subprogram_Body;

   procedure Render_Subprogram_Body
     (Buffer     : in out SU.Unbounded_String;
      Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Subprogram : CM.Resolved_Subprogram;
      State      : in out Emit_State)
   is
      Raw_Outer_Declarations : constant CM.Resolved_Object_Decl_Vectors.Vector :=
        Non_Alias_Declarations (Subprogram.Declarations);
      Inner_Alias_Declarations : constant CM.Resolved_Object_Decl_Vectors.Vector :=
        Alias_Declarations (Subprogram.Declarations);
      Structural_Traversal_Lowering : constant Boolean :=
        Uses_Structural_Traversal_Lowering (Subprogram);
      Previous_Wide_Count : constant Ada.Containers.Count_Type :=
        State.Wide_Local_Names.Length;
      Outer_Declarations : constant CM.Resolved_Object_Decl_Vectors.Vector :=
        Effective_Subprogram_Outer_Declarations
          (Subprogram, Raw_Outer_Declarations);
      Return_Type_Image : constant String :=
        (if Subprogram.Has_Return_Type then Render_Type_Name (Subprogram.Return_Type) else "");
      Suppress_Declaration_Warnings : constant Boolean :=
        not Structural_Traversal_Lowering and then not Outer_Declarations.Is_Empty;
   begin
      Collect_Wide_Locals
        (Unit, Document, State, Subprogram.Declarations, Subprogram.Statements);
      Push_Type_Binding_Frame (State);
      Register_Param_Type_Bindings (State, Subprogram.Params);
      Register_Type_Bindings (State, Outer_Declarations);
      Push_Cleanup_Frame (State);
      Register_Cleanup_Items (State, Outer_Declarations);
      Append_Line
        (Buffer,
         Render_Ada_Subprogram_Keyword (Subprogram)
         & " "
         & FT.To_String (Subprogram.Name)
         & Render_Subprogram_Params (Unit, Document, Subprogram.Params)
         & Render_Subprogram_Return (Unit, Document, Subprogram)
         & " is",
         1);
      if Structural_Traversal_Lowering then
         if not Render_Structural_Traversal_Subprogram_Body
           (Buffer, Unit, Document, Subprogram, State)
         then
            Raise_Internal
              ("structural traversal lowering matched a subprogram that could not be rendered");
         end if;
         Append_Line (Buffer, "end " & FT.To_String (Subprogram.Name) & ";", 1);
         Append_Line (Buffer);
         Pop_Cleanup_Frame (State);
         Pop_Type_Binding_Frame (State);
         Restore_Wide_Names (State, Previous_Wide_Count);
         return;
      end if;
      if Suppress_Declaration_Warnings then
         Append_Initialization_Warning_Suppression (Buffer, 2);
      end if;
      for Decl of Outer_Declarations loop
         Append_Line
           (Buffer,
            Render_Object_Decl_Text
              (Unit, Document, State, Decl, Local_Context => True),
            2);
      end loop;
      if Suppress_Declaration_Warnings then
         Append_Initialization_Warning_Restore (Buffer, 2);
      end if;
      Append_Line (Buffer, "begin", 1);
      Render_In_Out_Param_Stabilizers (Buffer, Subprogram, 2);
      if not Inner_Alias_Declarations.Is_Empty then
         Push_Type_Binding_Frame (State);
         Register_Type_Bindings (State, Inner_Alias_Declarations);
         Append_Line (Buffer, "declare", 2);
         Render_Block_Declarations
           (Buffer, Unit, Document, Inner_Alias_Declarations, State, 3);
         Append_Line (Buffer, "begin", 2);
         Render_Required_Statement_Suite
           (Buffer,
            Unit,
            Document,
            Subprogram.Statements,
            State,
            3,
            Return_Type_Image);
         Append_Line (Buffer, "end;", 2);
         Pop_Type_Binding_Frame (State);
      else
         Render_Required_Statement_Suite
           (Buffer,
            Unit,
            Document,
            Subprogram.Statements,
            State,
            2,
            Return_Type_Image);
      end if;
      if Statements_Fall_Through (Subprogram.Statements) then
         Render_Cleanup (Buffer, Outer_Declarations, 2);
      end if;
      Append_Line (Buffer, "end " & FT.To_String (Subprogram.Name) & ";", 1);
      Append_Line (Buffer);
      Pop_Cleanup_Frame (State);
      Pop_Type_Binding_Frame (State);
      Restore_Wide_Names (State, Previous_Wide_Count);
   end Render_Subprogram_Body;

   procedure Render_Task_Body
     (Buffer    : in out SU.Unbounded_String;
      Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Task_Item : CM.Resolved_Task;
      State     : in out Emit_State)
   is
      Previous_Wide_Count : constant Ada.Containers.Count_Type :=
        State.Wide_Local_Names.Length;
      Previous_Task_Body_Depth : constant Natural := State.Task_Body_Depth;
   begin
      Collect_Wide_Locals
        (Unit, Document, State, Task_Item.Declarations, Task_Item.Statements);
      Push_Type_Binding_Frame (State);
      Register_Type_Bindings (State, Task_Item.Declarations);
      Append_Line
        (Buffer,
         "task body "
         & FT.To_String (Task_Item.Name)
         & " is",
         1);
      if not Task_Item.Declarations.Is_Empty then
         Append_Initialization_Warning_Suppression (Buffer, 2);
      end if;
      for Decl of Task_Item.Declarations loop
         Append_Line
           (Buffer,
            Render_Object_Decl_Text (Unit, Document, State, Decl, Local_Context => True),
            2);
      end loop;
      if not Task_Item.Declarations.Is_Empty then
         Append_Initialization_Warning_Restore (Buffer, 2);
      end if;
      Append_Line (Buffer, "begin", 1);
      State.Task_Body_Depth := Previous_Task_Body_Depth + 1;
      Render_Required_Statement_Suite
        (Buffer, Unit, Document, Task_Item.Statements, State, 2, "");
      State.Task_Body_Depth := Previous_Task_Body_Depth;
      if Statements_Fall_Through (Task_Item.Statements) then
         Render_Cleanup (Buffer, Task_Item.Declarations, 2);
      end if;
      Append_Line (Buffer, "end " & FT.To_String (Task_Item.Name) & ";", 1);
      Append_Line (Buffer);
      Pop_Type_Binding_Frame (State);
      State.Task_Body_Depth := Previous_Task_Body_Depth;
      Restore_Wide_Names (State, Previous_Wide_Count);
   end Render_Task_Body;

   function Unit_File_Stem (Unit_Name : String) return String is
      Result : String := Unit_Name;
   begin
      for Index in Result'Range loop
         if Result (Index) = '.' then
            Result (Index) := '-';
         else
            Result (Index) := Ada.Characters.Handling.To_Lower (Result (Index));
         end if;
      end loop;
      return Result;
   end Unit_File_Stem;

   function Decl_Uses_Deferred_Package_Init_Name
     (Decl  : CM.Resolved_Object_Decl;
      Names : FT.UString_Vectors.Vector) return Boolean
   is
   begin
      if Decl.Initializer = null or else Names.Is_Empty then
         return False;
      end if;

      for Name of Names loop
         declare
            Name_Text : constant String := FT.To_String (Name);
         begin
            if Name_Text'Length > 0
              and then Expr_Uses_Name (Decl.Initializer, Name_Text)
            then
               return True;
            end if;
         end;
      end loop;

      return False;
   end Decl_Uses_Deferred_Package_Init_Name;

   function Decl_Uses_Package_Subprogram_Name
     (Unit : CM.Resolved_Unit;
      Decl : CM.Resolved_Object_Decl) return Boolean
   is
   begin
      if Decl.Initializer = null or else Unit.Subprograms.Is_Empty then
         return False;
      end if;

      for Subprogram of Unit.Subprograms loop
         if not Subprogram.Is_Interface_Template
           and then not Subprogram.Is_Generic_Template
         then
            declare
               Name_Text : constant String := FT.To_String (Subprogram.Name);
            begin
               if Name_Text'Length > 0
                 and then Expr_Uses_Name (Decl.Initializer, Name_Text)
               then
                  return True;
               end if;
            end;
         end if;
      end loop;

      return False;
   end Decl_Uses_Package_Subprogram_Name;

   function Should_Defer_Package_Object_Initializer
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Decl     : CM.Resolved_Object_Decl;
      Names    : FT.UString_Vectors.Vector) return Boolean
   is
   begin
      return
        not Decl.Is_Constant
        and then Decl.Has_Initializer
        and then
          (Has_Heap_Value_Type (Unit, Document, Decl.Type_Info)
           or else Is_Owner_Access (Decl.Type_Info)
           or else Decl_Uses_Deferred_Package_Init_Name (Decl, Names)
           or else Decl_Uses_Package_Subprogram_Name (Unit, Decl));
   end Should_Defer_Package_Object_Initializer;

   procedure Register_Deferred_Package_Init_Names
     (Decl  : CM.Resolved_Object_Decl;
      Names : in out FT.UString_Vectors.Vector)
   is
   begin
      for Name of Decl.Names loop
         declare
            Name_Text : constant String := FT.To_String (Name);
         begin
            if Name_Text'Length > 0 and then not Contains_Name (Names, Name_Text) then
               Names.Append (Name);
            end if;
         end;
      end loop;
   end Register_Deferred_Package_Init_Names;

   procedure Add_Body_With
     (Context : in out Emit_Context;
      Name    : String) renames AI.Add_Body_With;

   procedure Add_Imported_Enum_Use_Type
     (Context : in out Emit_Context;
      Name    : String) renames AI.Add_Imported_Enum_Use_Type;

   function Package_Select_Refined_State
     (Context : Emit_Context) return String renames AI.Package_Select_Refined_State;

   function Expr_Uses_Public_Shared_Helper
     (Expr : CM.Expr_Access) return Boolean
   is
      function Call_Name_Uses_Public_Shared_Helper return Boolean is
         Flat_Name : constant String :=
           (if Expr = null or else Expr.Callee = null
            then ""
            else FT.Lowercase (CM.Flatten_Name (Expr.Callee)));
      begin
         return
           Flat_Name'Length > 0
           and then Ada.Strings.Fixed.Index (Flat_Name, "safe_public_shared_") > 0;
      end Call_Name_Uses_Public_Shared_Helper;
   begin
      if Expr = null then
         return False;
      end if;

      case Expr.Kind is
         when CM.Expr_Call =>
            if Call_Name_Uses_Public_Shared_Helper then
               return True;
            end if;
            if Expr_Uses_Public_Shared_Helper (Expr.Callee) then
               return True;
            end if;
            for Arg of Expr.Args loop
               if Expr_Uses_Public_Shared_Helper (Arg) then
                  return True;
               end if;
            end loop;
            return False;
         when CM.Expr_Select =>
            return Expr_Uses_Public_Shared_Helper (Expr.Prefix);
         when CM.Expr_Resolved_Index =>
            if Expr_Uses_Public_Shared_Helper (Expr.Prefix) then
               return True;
            end if;
            for Arg of Expr.Args loop
               if Expr_Uses_Public_Shared_Helper (Arg) then
                  return True;
               end if;
            end loop;
            return False;
         when CM.Expr_Conversion =>
            return Expr_Uses_Public_Shared_Helper (Expr.Inner);
         when CM.Expr_Binary =>
            return
              Expr_Uses_Public_Shared_Helper (Expr.Left)
              or else Expr_Uses_Public_Shared_Helper (Expr.Right);
         when CM.Expr_Unary =>
            return Expr_Uses_Public_Shared_Helper (Expr.Inner);
         when CM.Expr_Aggregate =>
            for Field of Expr.Fields loop
               if Expr_Uses_Public_Shared_Helper (Field.Expr) then
                  return True;
               end if;
            end loop;
            return False;
         when CM.Expr_Tuple =>
            for Item of Expr.Elements loop
               if Expr_Uses_Public_Shared_Helper (Item) then
                  return True;
               end if;
            end loop;
            return False;
         when others =>
            return False;
      end case;
   end Expr_Uses_Public_Shared_Helper;

   function Statements_Use_Public_Shared_Helper
     (Statements : CM.Statement_Access_Vectors.Vector) return Boolean
   is
   begin
      for Item of Statements loop
         if Item = null then
            null;
         else
            case Item.Kind is
               when CM.Stmt_Object_Decl =>
                  if Expr_Uses_Public_Shared_Helper (Item.Decl.Initializer) then
                     return True;
                  end if;
               when CM.Stmt_Assign =>
                  if Expr_Uses_Public_Shared_Helper (Item.Target)
                    or else Expr_Uses_Public_Shared_Helper (Item.Value)
                  then
                     return True;
                  end if;
               when CM.Stmt_Call =>
                  if Expr_Uses_Public_Shared_Helper (Item.Call) then
                     return True;
                  end if;
               when CM.Stmt_Return =>
                  if Expr_Uses_Public_Shared_Helper (Item.Value) then
                     return True;
                  end if;
               when CM.Stmt_If =>
                  if Expr_Uses_Public_Shared_Helper (Item.Condition)
                    or else Statements_Use_Public_Shared_Helper (Item.Then_Stmts)
                  then
                     return True;
                  end if;
                  for Part of Item.Elsifs loop
                     if Expr_Uses_Public_Shared_Helper (Part.Condition)
                       or else Statements_Use_Public_Shared_Helper (Part.Statements)
                     then
                        return True;
                     end if;
                  end loop;
                  if Item.Has_Else
                    and then Statements_Use_Public_Shared_Helper (Item.Else_Stmts)
                  then
                     return True;
                  end if;
               when CM.Stmt_Case =>
                  if Expr_Uses_Public_Shared_Helper (Item.Case_Expr) then
                     return True;
                  end if;
                  for Arm of Item.Case_Arms loop
                     if Statements_Use_Public_Shared_Helper (Arm.Statements) then
                        return True;
                     end if;
                  end loop;
               when CM.Stmt_While =>
                  if Expr_Uses_Public_Shared_Helper (Item.Condition)
                    or else Statements_Use_Public_Shared_Helper (Item.Body_Stmts)
                  then
                     return True;
                  end if;
               when CM.Stmt_For =>
                  if Expr_Uses_Public_Shared_Helper (Item.Loop_Iterable)
                    or else Statements_Use_Public_Shared_Helper (Item.Body_Stmts)
                  then
                     return True;
                  end if;
               when others =>
                  null;
            end case;
         end if;
      end loop;
      return False;
   end Statements_Use_Public_Shared_Helper;

   procedure Prepare_Emit_Context
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Context  : in out Emit_Context)
   is
      function Unit_Defines_Result_Type return Boolean is
      begin
         for Type_Item of Unit.Types loop
            if Is_Result_Builtin (Type_Item)
              or else FT.Lowercase (FT.To_String (Type_Item.Name)) = "result"
            then
               return True;
            end if;
         end loop;
         return False;
      end Unit_Defines_Result_Type;
   begin
      if not Unit.Channels.Is_Empty
        or else not Unit.Tasks.Is_Empty
        or else (for some Decl of Unit.Objects => Decl.Is_Shared)
      then
         Context.State.Needs_Gnat_Adc := True;
      end if;
      Collect_Bounded_String_Types (Unit, Document, Context.State);
      Collect_Wide_Locals (Unit, Document, Context.State, Unit.Objects, Unit.Statements);
      Collect_Select_Dispatcher_Names
        (Unit.Statements,
         Context.Package_Dispatcher_Names);
      Collect_Select_Delay_Timer_Names
        (Unit.Statements,
         Context.Package_Dispatcher_Timer_Names);
      Collect_Select_Rotation_State
        (Unit.Statements,
         Context.Package_Select_Rotation_Names,
         Context.Package_Select_Rotation_Counts);
      for Task_Item of Unit.Tasks loop
         Collect_Select_Dispatcher_Names
           (Task_Item.Statements,
            Context.Package_Dispatcher_Names);
         Collect_Select_Delay_Timer_Names
           (Task_Item.Statements,
            Context.Package_Dispatcher_Timer_Names);
         Collect_Select_Rotation_State
           (Task_Item.Statements,
            Context.Package_Select_Rotation_Names,
            Context.Package_Select_Rotation_Counts);
      end loop;

      for Item of Unit.Imported_Types loop
         if FT.Lowercase (FT.To_String (Item.Kind)) = "enum" then
            Add_Imported_Enum_Use_Type
              (Context,
               Ada_Qualified_Name (FT.To_String (Item.Name)));
         end if;
      end loop;

      Collect_Synthetic_Types (Unit, Document, Context.Synthetic_Types);
      Collect_Owner_Access_Helper_Types
        (Unit, Document, Context.Owner_Access_Helper_Types);
      Collect_For_Of_Helper_Types
        (Unit, Document, Context.For_Of_Helper_Types);

      Context.Emit_Result_Builtin_First :=
        not Unit_Defines_Result_Type
        and then
          (for some Type_Item of Context.Synthetic_Types =>
             Is_Result_Builtin (Type_Item));

      Context.Needs_Spark_Off_Elaboration_Helper :=
        (for some Decl of Unit.Objects =>
            Decl.Is_Shared
            and then Has_Heap_Value_Type (Unit, Document, Decl.Type_Info))
        or else Statements_Use_Public_Shared_Helper (Unit.Statements);
      Context.Omit_Initializes_Aspect :=
        not Unit.Statements.Is_Empty
        or else
        (for some Decl of Unit.Objects => Decl.Is_Shared and then Decl.Is_Public)
        or else Statements_Use_Public_Shared_Helper (Unit.Statements);
   end Prepare_Emit_Context;

   procedure Emit_Package_Spec
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Bronze   : MB.Bronze_Result;
      Context  : in out Emit_Context)
   is
      Package_Select_Abstract_State_Name : constant String :=
        "Safe_Select_Internal_State";

      function Find_Synthetic_Type
        (Name_Text : String;
         Found     : out Boolean) return GM.Type_Descriptor
      is
      begin
         for Type_Item of Context.Synthetic_Types loop
            if FT.To_String (Type_Item.Name) = Name_Text then
               Found := True;
               return Type_Item;
            end if;
         end loop;

         if Starts_With (Name_Text, "__optional_") then
            for Type_Item of Unit.Types loop
               if Type_Item.Generic_Formals.Is_Empty
                 and then FT.To_String (Type_Item.Name) = Name_Text
               then
                  Found := True;
                  return Type_Item;
               end if;
            end loop;
         end if;

         Found := False;
         return (others => <>);
      end Find_Synthetic_Type;

      procedure Emit_Synthetic_Type_Decl (Type_Item : GM.Type_Descriptor);
      procedure Emit_Synthetic_Dependencies (Info : GM.Type_Descriptor);
      procedure Emit_Synthetic_Dependencies_For_Name (Name_Text : String);

      procedure Emit_Synthetic_Type_Decl (Type_Item : GM.Type_Descriptor) is
         Name_Text : constant String := FT.To_String (Type_Item.Name);
         Tail_Name : constant String := Synthetic_Type_Tail_Name (Name_Text);
      begin
         if Name_Text'Length = 0
           or else Contains_Name (Context.Emitted_Synthetic_Names, Name_Text)
           or else
             (Context.Emit_Result_Builtin_First and then Is_Result_Builtin (Type_Item))
           or else
             (Ada.Strings.Fixed.Index (Name_Text, ".") > 0
              and then Tail_Name'Length > 2
              and then Tail_Name (Tail_Name'First .. Tail_Name'First + 1) = "__")
         then
            return;
         end if;

         Emit_Synthetic_Dependencies (Type_Item);
         Append_Line
           (Context.Spec_Inner,
            Render_Type_Decl (Unit, Document, Type_Item, Context.State),
            1);
         Append_Line (Context.Spec_Inner);
         Context.Emitted_Synthetic_Names.Append (Type_Item.Name);
      end Emit_Synthetic_Type_Decl;

      procedure Emit_Synthetic_Dependencies_For_Name (Name_Text : String) is
         Found     : Boolean := False;
         Type_Item : GM.Type_Descriptor := (others => <>);
      begin
         if Name_Text'Length = 0 then
            return;
         end if;

         Type_Item := Find_Synthetic_Type (Name_Text, Found);
         if not Found then
            declare
               Resolved_Info : constant GM.Type_Descriptor :=
                 Resolve_Type_Name (Unit, Document, Name_Text);
               Resolved_Name : constant String := FT.To_String (Resolved_Info.Name);
               Resolved_Kind : constant String := FT.To_String (Resolved_Info.Kind);
            begin
               if Resolved_Name /= Name_Text then
                  Type_Item := Find_Synthetic_Type (Resolved_Name, Found);
               end if;
               if not Found
                 and then Has_Text (Resolved_Info.Name)
                 and then
                   (Starts_With (Resolved_Name, "__optional_")
                    or else (Resolved_Kind = "array" and then Resolved_Info.Growable)
                    or else
                      (Resolved_Kind = "subtype"
                       and then not Resolved_Info.Discriminant_Constraints.Is_Empty)
                    or else
                      (Resolved_Kind = "subtype"
                       and then Starts_With (Resolved_Name, "__constraint")
                       and then Resolved_Info.Has_Base
                       and then Resolved_Info.Has_Low
                       and then Resolved_Info.Has_High)
                    or else Is_Tuple_Type (Resolved_Info)
                    or else Is_Result_Builtin (Resolved_Info))
               then
                  Type_Item := Resolved_Info;
                  Found := True;
               end if;
            exception
               when others =>
                  null;
            end;
         end if;
         if Found then
            Emit_Synthetic_Type_Decl (Type_Item);
         end if;
      end Emit_Synthetic_Dependencies_For_Name;

      procedure Emit_Synthetic_Dependencies (Info : GM.Type_Descriptor) is
         Base_Info : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
      begin
         if Info.Has_Base then
            Emit_Synthetic_Dependencies_For_Name (FT.To_String (Info.Base));
         end if;
         if Base_Info.Has_Component_Type then
            Emit_Synthetic_Dependencies_For_Name
              (FT.To_String (Base_Info.Component_Type));
         end if;
         if Base_Info.Has_Target then
            Emit_Synthetic_Dependencies_For_Name (FT.To_String (Base_Info.Target));
         end if;
         for Item of Base_Info.Tuple_Element_Types loop
            Emit_Synthetic_Dependencies_For_Name (FT.To_String (Item));
         end loop;
         for Field of Base_Info.Fields loop
            Emit_Synthetic_Dependencies_For_Name (FT.To_String (Field.Type_Name));
         end loop;
         for Field of Base_Info.Variant_Fields loop
            Emit_Synthetic_Dependencies_For_Name (FT.To_String (Field.Type_Name));
         end loop;
      end Emit_Synthetic_Dependencies;

      function Has_Unemitted_Growable_Dependency
        (Info : GM.Type_Descriptor) return Boolean
      is
         Root_Name : constant String := FT.To_String (Info.Name);

         function Info_Has_Unemitted_Growable_Dependency
           (Current : GM.Type_Descriptor;
            Seen    : in out FT.UString_Vectors.Vector) return Boolean;

         function Name_Has_Unemitted_Growable_Dependency
           (Name_Text : String;
            Seen      : in out FT.UString_Vectors.Vector) return Boolean
         is
         begin
            if Name_Text'Length = 0 then
               return False;
            end if;

            if Contains_Name (Seen, Name_Text) then
               return False;
            end if;

            declare
               Resolved_Info : constant GM.Type_Descriptor :=
                 Resolve_Type_Name (Unit, Document, Name_Text);
            begin
               Seen.Append (FT.To_UString (Name_Text));
               return Info_Has_Unemitted_Growable_Dependency (Resolved_Info, Seen);
            exception
               when others =>
                  return False;
            end;
         end Name_Has_Unemitted_Growable_Dependency;

         function Info_Has_Unemitted_Growable_Dependency
           (Current : GM.Type_Descriptor;
            Seen    : in out FT.UString_Vectors.Vector) return Boolean
         is
            Base_Info      : constant GM.Type_Descriptor := Base_Type (Unit, Document, Current);
            Base_Name_Text : constant String := FT.To_String (Base_Info.Name);
         begin
            if FT.To_String (Base_Info.Kind) = "array"
              and then Base_Info.Growable
              and then Base_Name_Text /= Root_Name
              and then
                not Contains_Name
                  (Context.Emitted_Synthetic_Names, Base_Name_Text)
            then
               return True;
            end if;

            if Current.Has_Base
              and then
                Name_Has_Unemitted_Growable_Dependency
                  (FT.To_String (Current.Base), Seen)
            then
               return True;
            end if;
            if Base_Info.Has_Component_Type
              and then
                Name_Has_Unemitted_Growable_Dependency
                  (FT.To_String (Base_Info.Component_Type), Seen)
            then
               return True;
            end if;
            if Base_Info.Has_Target
              and then
                Name_Has_Unemitted_Growable_Dependency
                  (FT.To_String (Base_Info.Target), Seen)
            then
               return True;
            end if;
            for Item of Base_Info.Tuple_Element_Types loop
               if Name_Has_Unemitted_Growable_Dependency (FT.To_String (Item), Seen) then
                  return True;
               end if;
            end loop;
            for Field of Base_Info.Fields loop
               if Name_Has_Unemitted_Growable_Dependency
                 (FT.To_String (Field.Type_Name), Seen)
               then
                  return True;
               end if;
            end loop;
            for Field of Base_Info.Variant_Fields loop
               if Name_Has_Unemitted_Growable_Dependency
                 (FT.To_String (Field.Type_Name), Seen)
               then
                  return True;
               end if;
            end loop;

            return False;
         end Info_Has_Unemitted_Growable_Dependency;
      begin
         declare
            Seen : FT.UString_Vectors.Vector;
         begin
            if Root_Name'Length > 0 then
               Seen.Append (FT.To_UString (Root_Name));
            end if;
            if Info_Has_Unemitted_Growable_Dependency (Info, Seen) then
               return True;
            end if;
         end;

         declare
            Probe_State : Emit_State := Context.State;
            Decl_Image  : constant String :=
              Render_Type_Decl (Unit, Document, Info, Probe_State);
         begin
            return
              not Starts_With (FT.To_String (Info.Name), "__growable_array_")
              and then Ada.Strings.Fixed.Index (Decl_Image, "Safe_growable_array_") > 0
              and then
                (for some Type_Item of Context.Synthetic_Types =>
                   FT.To_String (Type_Item.Kind) = "array"
                   and then Type_Item.Growable
                   and then not Contains_Name
                     (Context.Emitted_Synthetic_Names,
                      FT.To_String (Type_Item.Name)));
         end;
      end Has_Unemitted_Growable_Dependency;
   begin
      Append_Line (Context.Spec_Inner, "pragma SPARK_Mode (On);");
      Append_Line (Context.Spec_Inner);
      Append_Line
        (Context.Spec_Inner,
         "package "
         & FT.To_String (Unit.Package_Name)
         & ASCII.LF
         & Indentation (1)
         & "with SPARK_Mode => On"
         & (if not Context.Package_Dispatcher_Names.Is_Empty
               or else not Context.Package_Dispatcher_Timer_Names.Is_Empty
               or else not Context.Package_Select_Rotation_Names.Is_Empty
               or else not Context.Omit_Initializes_Aspect
            then
               ","
            else
               "")
         & ASCII.LF
         & (if not Context.Package_Dispatcher_Names.Is_Empty
               or else not Context.Package_Dispatcher_Timer_Names.Is_Empty
               or else not Context.Package_Select_Rotation_Names.Is_Empty
            then
               Indentation (1)
               & "     Abstract_State => ("
               & Package_Select_Abstract_State_Name
               & " with External)"
               & (if Context.Omit_Initializes_Aspect
                  then
                     ""
                  else
                     ",")
               & ASCII.LF
            else
               "")
         & (if Context.Omit_Initializes_Aspect
            then
               ""
            else
               Indentation (1)
               & "     Initializes => "
               & Render_Initializes_Aspect (Unit, Document, Bronze)
               & ASCII.LF)
         & "is");
      Append_Line (Context.Spec_Inner, "pragma Elaborate_Body;", 1);
      Append_Line (Context.Spec_Inner);
      Append_Bounded_String_Instantiations (Context.Spec_Inner, Context.State);

      if Context.Emit_Result_Builtin_First then
         Append_Line
           (Context.Spec_Inner,
            Render_Type_Decl (Unit, Document, BT.Result_Type, Context.State),
            1);
         Append_Line (Context.Spec_Inner);
         Context.Emitted_Synthetic_Names.Append (BT.Result_Type.Name);
      end if;

      for Type_Item of Unit.Types loop
         declare
            Name_Text : constant String := FT.To_String (Type_Item.Name);
            Tail_Name : constant String := Synthetic_Type_Tail_Name (Name_Text);
            Skip_Imported_Synthetic : constant Boolean :=
              Ada.Strings.Fixed.Index (Name_Text, ".") > 0
              and then Tail_Name'Length > 2
              and then Tail_Name (Tail_Name'First .. Tail_Name'First + 1) = "__";
         begin
            if Type_Item.Generic_Formals.Is_Empty
              and then FT.To_String (Type_Item.Kind) /= "interface"
              and then not Skip_Imported_Synthetic
              and then
                not Contains_Name
                  (Context.Emitted_Synthetic_Names,
                   FT.To_String (Type_Item.Name))
            then
               if Has_Unemitted_Growable_Dependency (Type_Item) then
                  Context.Deferred_User_Types.Append (Type_Item);
               else
                  Emit_Synthetic_Dependencies (Type_Item);
                  Append_Line
                    (Context.Spec_Inner,
                     Render_Type_Decl (Unit, Document, Type_Item, Context.State),
                     1);
                  if FT.To_String (Type_Item.Kind) = "record" then
                     Append_Line (Context.Spec_Inner);
                  end if;
                  if Has_Text (Type_Item.Name) then
                     Context.Emitted_Synthetic_Names.Append (Type_Item.Name);
                  end if;
               end if;
            end if;
         end;
      end loop;

      for Type_Item of Context.Synthetic_Types loop
         Emit_Synthetic_Type_Decl (Type_Item);
      end loop;

      for Type_Item of Context.Deferred_User_Types loop
         declare
            Name_Text : constant String := FT.To_String (Type_Item.Name);
            Tail_Name : constant String := Synthetic_Type_Tail_Name (Name_Text);
            Skip_Imported_Synthetic : constant Boolean :=
              Ada.Strings.Fixed.Index (Name_Text, ".") > 0
              and then Tail_Name'Length > 2
              and then Tail_Name (Tail_Name'First .. Tail_Name'First + 1) = "__";
         begin
            if not Skip_Imported_Synthetic
              and then
                not Contains_Name
                  (Context.Emitted_Synthetic_Names,
                   FT.To_String (Type_Item.Name))
            then
               Emit_Synthetic_Dependencies (Type_Item);
               Append_Line
                 (Context.Spec_Inner,
                  Render_Type_Decl (Unit, Document, Type_Item, Context.State),
                  1);
               if FT.To_String (Type_Item.Kind) = "record" then
                  Append_Line (Context.Spec_Inner);
               end if;
               if Has_Text (Type_Item.Name) then
                  Context.Emitted_Synthetic_Names.Append (Type_Item.Name);
               end if;
            end if;
         end;
      end loop;

      for Type_Item of Context.Owner_Access_Helper_Types loop
         Render_Owner_Access_Helper_Spec
           (Context.Spec_Inner, Unit, Document, Type_Item);
      end loop;

      if not Unit.Objects.Is_Empty then
         for Decl of Unit.Objects loop
            if not Decl.Is_Shared then
               declare
                  Decl_Name : constant String :=
                    (if Decl.Names.Is_Empty
                     then ""
                     else FT.To_String (Decl.Names (Decl.Names.First_Index)));
                  Defer_Package_Initializer : constant Boolean :=
                    Should_Defer_Package_Object_Initializer
                      (Unit, Document, Decl, Context.Deferred_Package_Init_Names);
                  Needs_Decl_Warning_Fence : constant Boolean :=
                    not Decl.Is_Constant
                    and then
                      ((not Decl.Has_Initializer
                        and then Has_Heap_Value_Type (Unit, Document, Decl.Type_Info))
                       or else
                         Defer_Package_Initializer
                       or else
                         (Decl.Has_Initializer
                          and then Decl.Names.Length = 1
                          and then
                            (FT.Lowercase
                               (FT.To_String
                                  (Base_Type (Unit, Document, Decl.Type_Info).Kind))
                             = "boolean"
                             or else
                               FT.Lowercase
                                 (FT.To_String
                                    (Base_Type (Unit, Document, Decl.Type_Info).Name))
                               = "boolean")
                          and then
                            Statements_Use_Name (Unit.Statements, Decl_Name))
                       or else
                         (Decl.Has_Initializer
                          and then Decl.Names.Length = 1
                          and then Is_Integer_Type (Unit, Document, Decl.Type_Info)
                          and then
                            Statements_Use_Name (Unit.Statements, Decl_Name)));
               begin
                  if Needs_Decl_Warning_Fence then
                     Append_Local_Warning_Suppression (Context.Spec_Inner, 1);
                  end if;
                  Append_Line
                    (Context.Spec_Inner,
                     Render_Object_Decl_Text
                       (Unit,
                        Document,
                        Context.State,
                        Decl,
                        Defer_Initializer => Defer_Package_Initializer),
                     1);
                  if Needs_Decl_Warning_Fence then
                     Append_Local_Warning_Restore (Context.Spec_Inner, 1);
                  end if;
                  if Defer_Package_Initializer then
                     Register_Deferred_Package_Init_Names
                       (Decl, Context.Deferred_Package_Init_Names);
                  end if;
               end;
            end if;
         end loop;
         if (for some Decl of Unit.Objects => not Decl.Is_Shared) then
            Append_Line (Context.Spec_Inner);
         end if;
      end if;

      if (for some Decl of Unit.Objects => Decl.Is_Shared) then
         for Decl of Unit.Objects loop
            if Decl.Is_Shared then
               Render_Shared_Object_Spec
                 (Context.Spec_Inner, Unit, Document, Decl, Bronze, Context.State);
            end if;
         end loop;
      end if;

      if not Unit.Channels.Is_Empty then
         for Channel of Unit.Channels loop
            Render_Channel_Spec (Context.Spec_Inner, Unit, Document, Channel, Bronze);
         end loop;
      end if;

      if not Unit.Subprograms.Is_Empty then
         for Subprogram of Unit.Subprograms loop
            if not Subprogram.Is_Interface_Template
              and then not Subprogram.Is_Generic_Template
            then
               declare
                  Expression_Image : constant String :=
                    (if Subprogram.Force_Body_Emission
                     then ""
                     else
                       Render_Expression_Function_Image
                         (Unit, Document, Subprogram, Context.State));
               begin
                  if Expression_Image'Length = 0 then
                     Append_Line
                       (Context.Spec_Inner,
                        Render_Ada_Subprogram_Keyword (Subprogram)
                        & " "
                        & FT.To_String (Subprogram.Name)
                        & Render_Subprogram_Params (Unit, Document, Subprogram.Params)
                        & Render_Subprogram_Return (Unit, Document, Subprogram)
                        & Render_Subprogram_Aspects
                            (Unit, Document, Subprogram, Bronze, Context.State)
                        & ";",
                        1);
                  end if;
               end;
            end if;
         end loop;

         for Subprogram of Unit.Subprograms loop
            if not Subprogram.Is_Interface_Template
              and then not Subprogram.Is_Generic_Template
            then
               declare
                  Expression_Image : constant String :=
                    (if Subprogram.Force_Body_Emission
                     then ""
                     else
                       Render_Expression_Function_Image
                         (Unit, Document, Subprogram, Context.State));
               begin
                  if Expression_Image'Length > 0 then
                     Append_Line
                       (Context.Spec_Inner,
                        Render_Ada_Subprogram_Keyword (Subprogram)
                        & " "
                        & FT.To_String (Subprogram.Name)
                        & Render_Subprogram_Params (Unit, Document, Subprogram.Params)
                        & Render_Subprogram_Return (Unit, Document, Subprogram)
                        & " is (" & Expression_Image & ")"
                        & Render_Subprogram_Aspects
                            (Unit, Document, Subprogram, Bronze, Context.State)
                        & ";",
                        1);
                  end if;
               end;
            end if;
         end loop;
         Append_Line (Context.Spec_Inner);
      end if;

      if not Unit.Tasks.Is_Empty then
         for Task_Item of Unit.Tasks loop
            Append_Line
              (Context.Spec_Inner,
               "task "
               & FT.To_String (Task_Item.Name)
               & (if Task_Item.Has_Explicit_Priority
                  then " with Priority => " & Trim_Image (Task_Item.Priority)
                  else "")
               & ";",
               1);
         end loop;
         Append_Line (Context.Spec_Inner);
      end if;

      if not Context.Package_Dispatcher_Names.Is_Empty
        or else not Context.Package_Dispatcher_Timer_Names.Is_Empty
        or else not Context.Package_Select_Rotation_Names.Is_Empty
      then
         Append_Line (Context.Spec_Inner, "private", 1);
         for Name of Context.Package_Dispatcher_Names loop
            Render_Select_Dispatcher_Spec
              (Context.Spec_Inner,
               FT.To_String (Name));
            Render_Select_Dispatcher_Object_Decl
              (Context.Spec_Inner,
               FT.To_String (Name));
         end loop;
         for Name of Context.Package_Dispatcher_Timer_Names loop
            Append_Line
              (Context.Spec_Inner,
               FT.To_String (Name)
               & " : Ada.Real_Time.Timing_Events.Timing_Event"
               & ASCII.LF
               & Indentation (1)
               & "  with Part_Of => Safe_Select_Internal_State;",
               1);
         end loop;
         if not Context.Package_Select_Rotation_Names.Is_Empty then
            for Index in Context.Package_Select_Rotation_Names.First_Index
              .. Context.Package_Select_Rotation_Names.Last_Index
            loop
               Append_Line
                 (Context.Spec_Inner,
                  FT.To_String (Context.Package_Select_Rotation_Names (Index))
                  & " : Positive range 1 .. "
                  & FT.To_String (Context.Package_Select_Rotation_Counts (Index))
                  & " := 1"
                  & ASCII.LF
                  & Indentation (1)
                  & "  with Part_Of => Safe_Select_Internal_State;",
                  1);
            end loop;
         end if;
         Append_Line (Context.Spec_Inner);
      end if;

      Append_Line
        (Context.Spec_Inner,
         "end " & FT.To_String (Unit.Package_Name) & ";");
   end Emit_Package_Spec;

   procedure Emit_Package_Body
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Bronze   : MB.Bronze_Result;
      Context  : in out Emit_Context)
   is
      Package_Select_Abstract_State_Name : constant String :=
        "Safe_Select_Internal_State";
      Generated_Elaborate_Name : constant String :=
        "Safe_Generated_Elaborate_" & FT.To_String (Unit.Package_Name);
      Package_Body_Spark_Mode : constant String :=
        (if (for some Decl of Unit.Objects => Decl.Is_Shared and then Decl.Is_Public)
         then "Off"
         else "On");

      function Render_Object_String_Length_View
        (Name : String;
         Info : GM.Type_Descriptor) return String
      is
      begin
         if Is_Plain_String_Type (Unit, Document, Info) then
            Context.State.Needs_Safe_String_RT := True;
            return "Safe_String_RT.Length (" & Ada_Safe_Name (Name) & ")";
         elsif Is_Bounded_String_Type (Info) then
            Register_Bounded_String_Type (Context.State, Info);
            return
              Bounded_String_Instance_Name (Info)
              & ".Length ("
              & Ada_Safe_Name (Name)
              & ")";
         end if;

         return "0";
      end Render_Object_String_Length_View;

      function Can_Assert_Static_Array_Initializer
        (Info : GM.Type_Descriptor) return Boolean
      is
         Base : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
      begin
         if FT.Lowercase (FT.To_String (Base.Kind)) /= "array"
           or else Is_Growable_Array_Type (Unit, Document, Base)
           or else not Base.Has_Component_Type
           or else not Has_Text (Base.Component_Type)
         then
            return False;
         end if;

         declare
            Component_Info : GM.Type_Descriptor := (others => <>);
         begin
            if not Type_Info_From_Name
              (Unit,
               Document,
               FT.To_String (Base.Component_Type),
               Component_Info)
            then
               return False;
            end if;

            declare
               Component_Base : constant GM.Type_Descriptor :=
                 Base_Type (Unit, Document, Component_Info);
               Component_Kind : constant String :=
                 FT.Lowercase (FT.To_String (Component_Base.Kind));
            begin
               return
                 Component_Kind = "integer"
                 or else Component_Kind = "boolean"
                 or else Component_Kind = "enum"
                 or else Component_Kind = "binary";
            end;
         end;
      end Can_Assert_Static_Array_Initializer;

      function Static_Object_Fact_Condition
        (Decl : CM.Resolved_Object_Decl;
         Name : String) return String
      is
         Base : constant GM.Type_Descriptor := Base_Type (Unit, Document, Decl.Type_Info);
         Base_Kind : constant String := FT.Lowercase (FT.To_String (Base.Kind));
         Static_Image : SU.Unbounded_String := SU.Null_Unbounded_String;
         Static_Length : Natural := 0;
      begin
         if not Decl.Has_Initializer or else Decl.Initializer = null or else Name'Length = 0 then
            return "";
         end if;

         if Base_Kind = "integer"
           or else Base_Kind = "boolean"
           or else Base_Kind = "enum"
           or else Base_Kind = "binary"
           or else Can_Assert_Static_Array_Initializer (Decl.Type_Info)
         then
            return
              Ada_Safe_Name (Name)
              & " = "
              & Render_Expr_For_Target_Type
                  (Unit,
                   Document,
                   Decl.Initializer,
                   Decl.Type_Info,
                   Context.State);
         elsif (Is_Plain_String_Type (Unit, Document, Decl.Type_Info)
                  or else Is_Bounded_String_Type (Decl.Type_Info))
           and then Try_Static_String_Literal
             (Decl.Initializer,
              Static_Image,
              Static_Length)
         then
            return
              Render_Object_String_Length_View (Name, Decl.Type_Info)
              & " = "
              & Trim_Wide_Image (CM.Wide_Integer (Static_Length));
         end if;

         return "";
      end Static_Object_Fact_Condition;

      function Package_Elaborate_Precondition return String
      is
         Result : SU.Unbounded_String := SU.Null_Unbounded_String;

         procedure Append_Condition (Text : String) is
         begin
            if Text'Length = 0 then
               return;
            end if;

            if SU.Length (Result) > 0 then
               SU.Append (Result, " and then ");
            end if;

            SU.Append (Result, Text);
         end Append_Condition;
      begin
         declare
            Deferred_Names : FT.UString_Vectors.Vector;
         begin
            for Decl of Unit.Objects loop
               if Should_Defer_Package_Object_Initializer
                 (Unit, Document, Decl, Deferred_Names)
               then
                  Register_Deferred_Package_Init_Names (Decl, Deferred_Names);
               else
                  for Name of Decl.Names loop
                     Append_Condition
                       (Static_Object_Fact_Condition (Decl, FT.To_String (Name)));
                  end loop;
               end if;
            end loop;
         end;

         for Channel of Unit.Channels loop
            if Channel_Uses_Sequential_Scalar_Ghost_Model
              (Unit,
               Document,
               Channel)
            then
               Append_Condition
                 ("not "
                  & FT.To_String (Channel.Name)
                  & ".Full and then "
                  & FT.To_String (Channel.Name)
                  & ".Stored_Length_Value = 0");
            end if;
         end loop;

         return SU.To_String (Result);
      end Package_Elaborate_Precondition;

      procedure Seed_Package_Static_Bindings (State : in out Emit_State) is
         Static_Image  : SU.Unbounded_String := SU.Null_Unbounded_String;
         Static_Length : Natural := 0;
         Static_Value  : Long_Long_Integer := 0;
      begin
         for Decl of Unit.Objects loop
            for Name of Decl.Names loop
               declare
                  Name_Text : constant String := FT.To_String (Name);
               begin
                  if Try_Object_Static_String_Initializer
                    (Unit,
                     Name_Text,
                     Static_Image,
                     Static_Length)
                  then
                     Bind_Static_String (State, Name_Text, SU.To_String (Static_Image));
                     Bind_Static_Length (State, Name_Text, Static_Length);
                  elsif Try_Object_Static_Integer_Initializer
                    (Unit,
                     Name_Text,
                     Static_Value)
                  then
                     Bind_Static_Integer (State, Name_Text, Static_Value);
                  end if;

                  if Is_Growable_Array_Type (Unit, Document, Decl.Type_Info)
                    and then Decl.Has_Initializer
                    and then Decl.Initializer /= null
                    and then Try_Static_Array_Length_From_Expr
                      (Unit,
                       Document,
                       Decl.Initializer,
                       Static_Length)
                  then
                     for Position in 1 .. Static_Length loop
                        if Try_Static_Integer_Array_Element_Expr
                          (Unit,
                           Decl.Initializer,
                           Position,
                           Static_Value)
                        then
                           Bind_Static_Integer
                             (State,
                              Static_Element_Binding_Name (Name_Text, Position),
                              Static_Value);
                        end if;
                     end loop;
                  end if;
               end;
            end loop;
         end loop;
      end Seed_Package_Static_Bindings;
   begin
      Append_Line
        (Context.Body_Inner,
         "package body "
         & FT.To_String (Unit.Package_Name)
         & " with SPARK_Mode => " & Package_Body_Spark_Mode
         & (if not Context.Package_Dispatcher_Names.Is_Empty
               or else not Context.Package_Dispatcher_Timer_Names.Is_Empty
               or else not Context.Package_Select_Rotation_Names.Is_Empty
            then
               "," & ASCII.LF
               & Indentation (1)
               & "     Refined_State => ("
               & Package_Select_Abstract_State_Name
               & " => ("
               & Package_Select_Refined_State (Context)
               & "))"
            else
               "")
         & " is");
      Append_Bounded_String_Uses (Context.Body_Inner, Context.State, 1);
      Append_Line (Context.Body_Inner);

      for Type_Item of Unit.Types loop
         if Type_Item.Generic_Formals.Is_Empty
           and then FT.To_String (Type_Item.Kind) /= "interface"
         then
            Render_Growable_Array_Helper_Body
              (Context.Body_Inner, Unit, Document, Type_Item, Context.State);
         end if;
      end loop;

      for Type_Item of Context.Synthetic_Types loop
         Render_Growable_Array_Helper_Body
           (Context.Body_Inner, Unit, Document, Type_Item, Context.State);
      end loop;

      for Type_Item of Context.Owner_Access_Helper_Types loop
         Render_Owner_Access_Helper_Body
           (Context.Body_Inner, Unit, Document, Type_Item, Context.State);
      end loop;
      Render_For_Of_Helper_Bodies
        (Context.Body_Inner,
         Unit,
         Document,
         Context.For_Of_Helper_Types,
         Context.State);

      for Name of Context.Package_Dispatcher_Names loop
         Render_Select_Dispatcher_Body
           (Context.Body_Inner,
            FT.To_String (Name));
      end loop;
      if not Context.Package_Dispatcher_Names.Is_Empty then
         Append_Line (Context.Body_Inner);
      end if;
      for Decl of Unit.Objects loop
         if Decl.Is_Shared then
            Render_Shared_Object_Body
              (Context.Body_Inner, Unit, Document, Decl, Bronze, Context.State);
         end if;
      end loop;
      for Name of Context.Package_Dispatcher_Timer_Names loop
         declare
            Timer_Text : constant String := FT.To_String (Name);
            Dispatcher_Text : constant String :=
              Timer_Text (Timer_Text'First .. Timer_Text'Last - 6);
         begin
            Render_Select_Dispatcher_Delay_Helpers
              (Context.Body_Inner,
               Dispatcher => Dispatcher_Text,
               Timer_Name => Timer_Text,
               Init_Helper => Dispatcher_Text & "_Initialize_Timer",
               Deadline_Helper => Dispatcher_Text & "_Compute_Deadline",
               Arm_Helper => Dispatcher_Text & "_Arm_Deadline",
               Cancel_Helper => Dispatcher_Text & "_Cancel_Deadline");
         end;
      end loop;
      if not Context.Package_Dispatcher_Timer_Names.Is_Empty then
         Append_Line (Context.Body_Inner);
      end if;

      for Channel of Unit.Channels loop
         Render_Channel_Body (Context.Body_Inner, Unit, Document, Channel, Context.State);
      end loop;

      for Subprogram of Unit.Subprograms loop
         if not Subprogram.Is_Interface_Template
           and then not Subprogram.Is_Generic_Template
           and then
             (Subprogram.Force_Body_Emission
              or else
                Render_Expression_Function_Image
                  (Unit, Document, Subprogram, Context.State)'Length = 0)
         then
            Render_Subprogram_Body
              (Context.Body_Inner, Unit, Document, Subprogram, Context.State);
         end if;
      end loop;

      for Task_Item of Unit.Tasks loop
         Render_Task_Body (Context.Body_Inner, Unit, Document, Task_Item, Context.State);
      end loop;

      if not Unit.Statements.Is_Empty
        or else not Context.Deferred_Package_Init_Names.Is_Empty
        or else not Context.Package_Dispatcher_Timer_Names.Is_Empty
        or else
          (for some Decl of Unit.Objects =>
             Decl.Is_Shared and then Decl.Has_Initializer and then Decl.Initializer /= null)
      then
         Append_Gnatprove_Warning_Suppression
           (Context.Body_Inner,
            "has no effect",
            "generated package elaboration helper is intentional",
            1);
         declare
            Elaborate_Precondition : constant String := Package_Elaborate_Precondition;
         begin
            if Context.Needs_Spark_Off_Elaboration_Helper then
               if Elaborate_Precondition'Length > 0 then
                  Append_Line
                    (Context.Body_Inner, "procedure " & Generated_Elaborate_Name, 1);
                  Append_Line
                    (Context.Body_Inner,
                     "  with Pre => " & Elaborate_Precondition & ",",
                     1);
                  Append_Line
                    (Context.Body_Inner,
                     "       Always_Terminates;",
                     1);
               else
                  Append_Line
                    (Context.Body_Inner, "procedure " & Generated_Elaborate_Name, 1);
                  Append_Line (Context.Body_Inner, "  with Always_Terminates;", 1);
               end if;
               Append_Line (Context.Body_Inner);
               Append_Line
                 (Context.Body_Inner,
                  "procedure " & Generated_Elaborate_Name & " is",
                  1);
               Append_Line (Context.Body_Inner, "pragma SPARK_Mode (Off);", 2);
            elsif Elaborate_Precondition'Length > 0 then
               Append_Line
                 (Context.Body_Inner, "procedure " & Generated_Elaborate_Name, 1);
               Append_Line
                 (Context.Body_Inner,
                  "  with Pre => " & Elaborate_Precondition,
                  1);
               Append_Line (Context.Body_Inner, "is", 1);
            else
               Append_Line
                 (Context.Body_Inner,
                  "procedure " & Generated_Elaborate_Name & " is",
                  1);
            end if;
         end;
         Append_Line (Context.Body_Inner, "begin", 1);
         declare
            Deferred_Names : FT.UString_Vectors.Vector;
         begin
            for Name of Context.Package_Dispatcher_Timer_Names loop
               declare
                  Timer_Text : constant String := FT.To_String (Name);
                  Dispatcher_Text : constant String :=
                    Timer_Text (Timer_Text'First .. Timer_Text'Last - 6);
               begin
                  Append_Line
                    (Context.Body_Inner,
                     Dispatcher_Text & "_Initialize_Timer;",
                     2);
               end;
            end loop;
            for Decl of Unit.Objects loop
               if Decl.Is_Shared
                 and then Decl.Has_Initializer
                 and then Decl.Initializer /= null
               then
                  Append_Line
                    (Context.Body_Inner,
                     Shared_Wrapper_Object_Name
                       (FT.To_String (Decl.Names (Decl.Names.First_Index)))
                     & ".Initialize ("
                     & Render_Expr_For_Target_Type
                         (Unit,
                          Document,
                          Decl.Initializer,
                          Decl.Type_Info,
                          Context.State)
                     & ");",
                     2);
               end if;
            end loop;
            for Decl of Unit.Objects loop
               if not Decl.Is_Shared
                 and then Should_Defer_Package_Object_Initializer
                   (Unit, Document, Decl, Deferred_Names)
               then
                  for Name of Decl.Names loop
                     Append_Gnatprove_Warning_Suppression
                       (Context.Body_Inner,
                        "unused assignment",
                        "deferred heap-backed package initialization is intentional",
                        2);
                     Append_Line
                       (Context.Body_Inner,
                        FT.To_String (Name)
                        & " := "
                        & Render_Expr_For_Target_Type
                            (Unit,
                             Document,
                             Decl.Initializer,
                             Decl.Type_Info,
                             Context.State)
                        & ";",
                        2);
                     declare
                        Target_Info : constant GM.Type_Descriptor :=
                          Base_Type (Unit, Document, Decl.Type_Info);
                        Source_Info : constant GM.Type_Descriptor :=
                          Base_Type
                            (Unit,
                             Document,
                             Expr_Type_Info (Unit, Document, Decl.Initializer));
                        Source_Image : constant String :=
                          Render_Expr (Unit, Document, Decl.Initializer, Context.State);
                        Cardinality : Natural := 0;
                     begin
                        if Is_Growable_Array_Type (Unit, Document, Target_Info)
                          and then Uses_Identity_Array_Runtime (Unit, Document, Target_Info)
                          and then FT.Lowercase (FT.To_String (Source_Info.Kind)) = "array"
                          and then not Source_Info.Growable
                          and then Fixed_Array_Cardinality
                            (Unit,
                             Document,
                             Source_Info,
                             Cardinality)
                        then
                           declare
                              Base_Source : constant GM.Type_Descriptor :=
                                Base_Type (Unit, Document, Source_Info);
                              Index_Info : GM.Type_Descriptor :=
                                Resolve_Type_Name
                                  (Unit,
                                   Document,
                                   FT.To_String
                                     (Base_Source.Index_Types
                                        (Base_Source.Index_Types.First_Index)));
                              Source_Low : Long_Long_Integer := 0;
                           begin
                              if not Index_Info.Has_Low or else not Index_Info.Has_High then
                                 Index_Info := Base_Type (Unit, Document, Index_Info);
                              end if;
                              if Index_Info.Has_Low and then Index_Info.Has_High then
                                 Source_Low := Index_Info.Low;
                                 Append_Line
                                   (Context.Body_Inner,
                                    "pragma Assert ("
                                    & Array_Runtime_Instance_Name (Target_Info)
                                    & ".Length ("
                                    & FT.To_String (Name)
                                    & ") = "
                                    & Trim_Image (Long_Long_Integer (Cardinality))
                                    & ");",
                                    2);
                                 for Offset in 0 .. Cardinality - 1 loop
                                    declare
                                       Source_Index : constant Long_Long_Integer :=
                                         Source_Low + Long_Long_Integer (Offset);
                                    begin
                                       Append_Line
                                         (Context.Body_Inner,
                                          "pragma Assert ("
                                          & Array_Runtime_Instance_Name (Target_Info)
                                          & ".Element ("
                                          & FT.To_String (Name)
                                          & ", "
                                          & Trim_Image (Long_Long_Integer (Offset + 1))
                                          & ") = "
                                          & Source_Image
                                          & " ("
                                          & Trim_Image (Source_Index)
                                          & "));",
                                          2);
                                    end;
                                 end loop;
                              end if;
                           end;
                        end if;
                     end;
                     Append_Gnatprove_Warning_Restore
                       (Context.Body_Inner,
                        "unused assignment",
                        2);
                  end loop;
                  Register_Deferred_Package_Init_Names (Decl, Deferred_Names);
               end if;
            end loop;
         end;
         Seed_Package_Static_Bindings (Context.State);
         Render_Required_Statement_Suite
           (Context.Body_Inner, Unit, Document, Unit.Statements, Context.State, 2, "");
         Append_Line
           (Context.Body_Inner,
            "end " & Generated_Elaborate_Name & ";",
            1);
         Append_Gnatprove_Warning_Restore
           (Context.Body_Inner,
            "has no effect",
            1);
         Append_Line (Context.Body_Inner);
         Append_Line (Context.Body_Inner, "begin");
         Append_Line (Context.Body_Inner, Generated_Elaborate_Name & ";", 1);
      end if;

      Append_Line
        (Context.Body_Inner,
         "end " & FT.To_String (Unit.Package_Name) & ";");
   end Emit_Package_Body;

   procedure Finalize_Body_Text
     (Context : in out Emit_Context)
   is
   begin
      if Context.State.Needs_Ada_Strings_Unbounded then
         Add_Body_With (Context, "Ada.Strings.Unbounded");
      end if;
      if Ada.Strings.Fixed.Index (SU.To_String (Context.Body_Inner), "Ada.Strings.Fixed.") > 0 then
         Add_Body_With (Context, "Ada.Strings");
         Add_Body_With (Context, "Ada.Strings.Fixed");
      end if;
      if Ada.Strings.Fixed.Index (SU.To_String (Context.Body_Inner), "Ada.Characters.Handling.") > 0 then
         Add_Body_With (Context, "Ada.Characters");
         Add_Body_With (Context, "Ada.Characters.Handling");
      end if;
      if Ada.Strings.Fixed.Index (SU.To_String (Context.Body_Inner), "Interfaces.") > 0 then
         Add_Body_With (Context, "Interfaces");
      end if;
      if Ada.Strings.Fixed.Index (SU.To_String (Context.Body_Inner), "System.") > 0 then
         Add_Body_With (Context, "System");
      end if;
      if Ada.Strings.Fixed.Index (SU.To_String (Context.Body_Inner), "Ada.Real_Time.Timing_Events.") > 0 then
         Add_Body_With (Context, "Ada.Real_Time");
         Add_Body_With (Context, "Ada.Real_Time.Timing_Events");
      end if;
      if Context.State.Needs_Safe_IO then
         Add_Body_With (Context, "IO");
      end if;
      if Context.State.Needs_Ada_Real_Time then
         Add_Body_With (Context, "Ada.Real_Time");
      end if;
      if Context.State.Needs_Safe_Runtime then
         Add_Body_With (Context, "Safe_Runtime");
      end if;
      if Context.State.Needs_Safe_String_RT then
         Add_Body_With (Context, "Safe_String_RT");
      end if;
      if Context.State.Needs_Safe_Array_RT then
         Add_Body_With (Context, "Safe_Array_RT");
      end if;
      if not Context.Owner_Access_Helper_Types.Is_Empty then
         Add_Body_With (Context, "Safe_Ownership_RT");
      end if;

      for Item of Context.Body_Withs loop
         Append_Line (Context.Body_Text, "with " & FT.To_String (Item) & ";");
      end loop;
      if Context.State.Needs_Safe_Runtime then
         Append_Line (Context.Body_Text, "use type Safe_Runtime.Wide_Integer;");
      end if;
      if Context.State.Needs_Ada_Real_Time then
         Append_Line (Context.Body_Text, "use type Ada.Real_Time.Time;");
      end if;
      if Context.State.Needs_Safe_String_RT then
         Append_Line (Context.Body_Text, "use type Safe_String_RT.Safe_String;");
      end if;
      if Ada.Strings.Fixed.Index (SU.To_String (Context.Body_Inner), "Interfaces.") > 0 then
         Append_Line (Context.Body_Text, "use type Interfaces.Unsigned_8;");
         Append_Line (Context.Body_Text, "use type Interfaces.Unsigned_16;");
         Append_Line (Context.Body_Text, "use type Interfaces.Unsigned_32;");
         Append_Line (Context.Body_Text, "use type Interfaces.Unsigned_64;");
      end if;
      for Item of Context.Imported_Enum_Use_Types loop
         Append_Line (Context.Body_Text, "use type " & FT.To_String (Item) & ";");
      end loop;
      if not Context.Body_Withs.Is_Empty then
         Append_Line (Context.Body_Text);
      end if;
      Context.Body_Text := Context.Body_Text & Context.Body_Inner;
   end Finalize_Body_Text;

   procedure Finalize_Spec_Text
     (Context : in out Emit_Context)
   is
      Original_Spec : constant String := SU.To_String (Context.Spec_Inner);
      Pragma_Block  : constant String :=
        "pragma SPARK_Mode (On);" & ASCII.LF & ASCII.LF;
      Spec_Needs_Safe_Runtime : constant Boolean :=
        Ada.Strings.Fixed.Index (Original_Spec, "Safe_Runtime.") > 0;
      Spec_Needs_Safe_String_RT : constant Boolean :=
        Ada.Strings.Fixed.Index (Original_Spec, "Safe_String_RT.") > 0;
      Spec_Needs_Safe_Array_RT : constant Boolean :=
        Ada.Strings.Fixed.Index (Original_Spec, "Safe_Array_RT") > 0;
      Spec_Needs_Safe_Array_Identity_Ops : constant Boolean :=
        Ada.Strings.Fixed.Index (Original_Spec, "Safe_Array_Identity_Ops") > 0;
      Spec_Needs_Safe_Array_Identity_RT : constant Boolean :=
        Ada.Strings.Fixed.Index (Original_Spec, "Safe_Array_Identity_RT") > 0;
      Spec_Needs_Safe_Bounded_Strings : constant Boolean :=
        Context.State.Needs_Safe_Bounded_Strings;
      Spec_Needs_Ada_Strings_Unbounded : constant Boolean :=
        Context.State.Needs_Ada_Strings_Unbounded;
      Spec_Needs_Ada_Real_Time_Timing_Events : constant Boolean :=
        Ada.Strings.Fixed.Index (Original_Spec, "Ada.Real_Time.Timing_Events.") > 0;
      Spec_Needs_Interfaces : constant Boolean :=
        Ada.Strings.Fixed.Index (Original_Spec, "Interfaces.") > 0;
      Spec_Needs_System : constant Boolean :=
        Ada.Strings.Fixed.Index (Original_Spec, "System.") > 0;
      Spec_Needs_Safe_Ownership_RT : constant Boolean :=
        not Context.Owner_Access_Helper_Types.Is_Empty;
   begin
      if (Spec_Needs_Safe_Runtime
          or else Spec_Needs_Safe_String_RT
          or else Spec_Needs_Safe_Array_RT
          or else Spec_Needs_Safe_Array_Identity_Ops
          or else Spec_Needs_Safe_Array_Identity_RT
          or else Spec_Needs_Safe_Bounded_Strings
          or else Spec_Needs_Ada_Strings_Unbounded
          or else Spec_Needs_Ada_Real_Time_Timing_Events
          or else Spec_Needs_Interfaces
          or else Spec_Needs_System
          or else Spec_Needs_Safe_Ownership_RT
          or else Context.State.Needs_Unevaluated_Use_Of_Old)
        and then Original_Spec'Length >= Pragma_Block'Length
        and then
          Original_Spec
            (Original_Spec'First .. Original_Spec'First + Pragma_Block'Length - 1) =
            Pragma_Block
      then
         Append_Line (Context.Spec_Text, "pragma SPARK_Mode (On);");
         if Context.State.Needs_Unevaluated_Use_Of_Old then
            Append_Line (Context.Spec_Text, "pragma Unevaluated_Use_Of_Old (Allow);");
         end if;
         if Spec_Needs_Ada_Strings_Unbounded then
            Append_Line (Context.Spec_Text, "with Ada.Strings.Unbounded;");
         end if;
         if Spec_Needs_Ada_Real_Time_Timing_Events then
            Append_Line (Context.Spec_Text, "with Ada.Real_Time;");
            Append_Line (Context.Spec_Text, "with Ada.Real_Time.Timing_Events;");
         end if;
         if Spec_Needs_Safe_String_RT then
            Append_Line (Context.Spec_Text, "with Safe_String_RT;");
         end if;
         if Spec_Needs_Safe_Array_RT then
            Append_Line (Context.Spec_Text, "with Safe_Array_RT;");
         end if;
         if Spec_Needs_Safe_Array_Identity_Ops then
            Append_Line (Context.Spec_Text, "with Safe_Array_Identity_Ops;");
         end if;
         if Spec_Needs_Safe_Array_Identity_RT then
            Append_Line (Context.Spec_Text, "with Safe_Array_Identity_RT;");
         end if;
         if Spec_Needs_Safe_Bounded_Strings then
            Append_Line (Context.Spec_Text, "with Safe_Bounded_Strings;");
         end if;
         if Spec_Needs_Interfaces then
            Append_Line (Context.Spec_Text, "with Interfaces;");
            Append_Line (Context.Spec_Text, "use type Interfaces.Unsigned_8;");
            Append_Line (Context.Spec_Text, "use type Interfaces.Unsigned_16;");
            Append_Line (Context.Spec_Text, "use type Interfaces.Unsigned_32;");
            Append_Line (Context.Spec_Text, "use type Interfaces.Unsigned_64;");
         end if;
         if Spec_Needs_System then
            Append_Line (Context.Spec_Text, "with System;");
         end if;
         if Spec_Needs_Safe_Runtime then
            Append_Line (Context.Spec_Text, "with Safe_Runtime;");
            Append_Line (Context.Spec_Text, "use type Safe_Runtime.Wide_Integer;");
         end if;
         for Item of Context.Imported_Enum_Use_Types loop
            Append_Line (Context.Spec_Text, "use type " & FT.To_String (Item) & ";");
         end loop;
         if Spec_Needs_Safe_Ownership_RT then
            Append_Line (Context.Spec_Text, "with Safe_Ownership_RT;");
         end if;
         Append_Line (Context.Spec_Text);
         Context.Spec_Text :=
           Context.Spec_Text
           & SU.To_Unbounded_String
               (Original_Spec
                  (Original_Spec'First + Pragma_Block'Length .. Original_Spec'Last));
      else
         Context.Spec_Text := Context.Spec_Text & Context.Spec_Inner;
      end if;
   end Finalize_Spec_Text;

   function Build_Emit_Result
     (Unit    : CM.Resolved_Unit;
      Context : Emit_Context) return Artifact_Result
   is
   begin
      return
        (Success            => True,
         Unit_Name          => Unit.Package_Name,
         Spec_Text          => FT.To_UString (SU.To_String (Context.Spec_Text)),
         Body_Text          => FT.To_UString (SU.To_String (Context.Body_Text)),
         Needs_Gnat_Adc     => Context.State.Needs_Gnat_Adc);
   end Build_Emit_Result;

   function Emit
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Bronze   : MB.Bronze_Result) return Artifact_Result
   is
      Context : Emit_Context;
   begin
      Prepare_Emit_Context (Unit, Document, Context);
      Emit_Package_Spec (Unit, Document, Bronze, Context);
      Emit_Package_Body (Unit, Document, Bronze, Context);
      Finalize_Body_Text (Context);
      Finalize_Spec_Text (Context);
      return Build_Emit_Result (Unit, Context);
   exception
      when AI.Emitter_Unsupported =>
         return
           (Success    => False,
            Diagnostic =>
              CM.Unsupported_Source_Construct
                (Path    => FT.To_String (Unit.Path),
                 Span    => Context.State.Unsupported_Span,
                 Message => FT.To_String (Context.State.Unsupported_Message)));
   end Emit;
end Safe_Frontend.Ada_Emit;
