with Ada.Strings.Unbounded;
with Safe_Frontend.Ada_Emit.Internal;

private package Safe_Frontend.Ada_Emit.Types is
   package SU renames Ada.Strings.Unbounded;
   package AI renames Safe_Frontend.Ada_Emit.Internal;

   subtype Emit_State is AI.Emit_State;
   subtype Heap_Helper_Family_Kind is AI.Heap_Helper_Family_Kind;

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
   procedure Append_Bounded_String_Instantiations
     (Buffer : in out SU.Unbounded_String;
      State  : Emit_State);
   procedure Append_Bounded_String_Uses
     (Buffer : in out SU.Unbounded_String;
      State  : Emit_State;
      Depth  : Natural);
   function Fixed_Array_Cardinality
     (Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      Target_Info : GM.Type_Descriptor;
      Cardinality : out Natural) return Boolean;
   function Has_Heap_Value_Type
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean;
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
   function Ada_Safe_Name (Name : String) return String;
   function Render_Enum_Literal_Name
     (Literal_Name   : String;
      Enum_Type_Name : String) return String;
   function Preferred_Imported_Synthetic_Type
     (Unit : CM.Resolved_Unit;
      Info : GM.Type_Descriptor) return GM.Type_Descriptor;
   function Is_Builtin_Integer_Name (Name : String) return Boolean;
   function Is_Builtin_Float_Name (Name : String) return Boolean;
   function Array_Runtime_Instance_Name (Info : GM.Type_Descriptor) return String;
   function Local_Allocate_Helper_Name (Info : GM.Type_Descriptor) return String;
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
   function Render_Type_Decl
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Type_Item : GM.Type_Descriptor;
      State     : in out Emit_State) return String;
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
   procedure Render_For_Of_Helper_Bodies
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Types    : GM.Type_Descriptor_Vectors.Vector;
      State    : in out Emit_State);
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
   function Sanitize_Type_Name_Component (Value : String) return String;
end Safe_Frontend.Ada_Emit.Types;
