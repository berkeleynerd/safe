with Ada.Strings.Unbounded;
with Safe_Frontend.Ada_Emit.Internal;

private package Safe_Frontend.Ada_Emit.Statements is
   package SU renames Ada.Strings.Unbounded;
   package AI renames Safe_Frontend.Ada_Emit.Internal;

   subtype Emit_State is AI.Emit_State;
   subtype Heap_Helper_Family_Kind is AI.Heap_Helper_Family_Kind;

   function Expr_Uses_Name
     (Expr : CM.Expr_Access;
      Name : String) return Boolean;
   function Statements_Use_Name
     (Statements : CM.Statement_Access_Vectors.Vector;
      Name       : String) return Boolean;
   function Statements_Immediately_Overwrite_Name
     (Statements : CM.Statement_Access_Vectors.Vector;
      Name       : String) return Boolean;
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
   function Try_Object_Static_String_Initializer
     (Unit   : CM.Resolved_Unit;
      Name   : String;
      Image  : out SU.Unbounded_String;
      Length : out Natural) return Boolean;
   function Try_Object_Static_Integer_Initializer
     (Unit  : CM.Resolved_Unit;
      Name  : String;
      Value : out Long_Long_Integer) return Boolean;
   function Try_Static_Array_Length_From_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      Length   : out Natural) return Boolean;
   procedure Collect_Bounded_String_Types
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      State    : in out Emit_State);
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
   procedure Render_Block_Declarations
     (Buffer       : in out SU.Unbounded_String;
      Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      Declarations : CM.Resolved_Object_Decl_Vectors.Vector;
      State        : in out Emit_State;
      Depth        : Natural);
   procedure Collect_For_Of_Helper_Types
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Result   : in out GM.Type_Descriptor_Vectors.Vector);
   procedure Collect_Owner_Access_Helper_Types
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
   function Statements_Have_Select
     (Statements : CM.Statement_Access_Vectors.Vector) return Boolean;
   function Loop_Variant_Image
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Condition : CM.Expr_Access;
      State     : in out Emit_State) return String;
end Safe_Frontend.Ada_Emit.Statements;
