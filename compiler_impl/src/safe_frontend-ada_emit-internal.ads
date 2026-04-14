with Ada.Containers;
with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Unbounded;

private package Safe_Frontend.Ada_Emit.Internal is
   package SU renames Ada.Strings.Unbounded;

   Emitter_Internal : exception;
   Emitter_Unsupported : exception;

   type Cleanup_Action is (Cleanup_Deallocate, Cleanup_Reset_Null);

   type Cleanup_Item is record
      Action    : Cleanup_Action := Cleanup_Deallocate;
      Name      : FT.UString := FT.To_UString ("");
      Type_Name : FT.UString := FT.To_UString ("");
      Free_Proc : FT.UString := FT.To_UString ("");
      Is_Constant : Boolean := False;
      Always_Terminates_Suppression_OK : Boolean := False;
   end record;

   package Cleanup_Item_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Cleanup_Item);

   type Cleanup_Frame is record
      Items : Cleanup_Item_Vectors.Vector;
   end record;

   package Cleanup_Frame_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Cleanup_Frame);

   type Type_Binding is record
      Name      : FT.UString := FT.To_UString ("");
      Type_Info : GM.Type_Descriptor;
   end record;

   package Type_Binding_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Type_Binding);

   type Type_Binding_Frame is record
      Bindings : Type_Binding_Vectors.Vector;
   end record;

   package Type_Binding_Frame_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Type_Binding_Frame);

   type Static_Length_Binding is record
      Name   : FT.UString := FT.To_UString ("");
      Known  : Boolean := False;
      Length : Natural := 0;
   end record;

   package Static_Length_Binding_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Static_Length_Binding);

   type Static_Integer_Binding is record
      Name  : FT.UString := FT.To_UString ("");
      Known : Boolean := False;
      Value : Long_Long_Integer := 0;
   end record;

   package Static_Integer_Binding_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Static_Integer_Binding);

   type Static_String_Binding is record
      Name  : FT.UString := FT.To_UString ("");
      Image : FT.UString := FT.To_UString ("");
   end record;

   package Static_String_Binding_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Static_String_Binding);

   type Emit_State is record
      Needs_Safe_IO : Boolean := False;
      Needs_Safe_Runtime : Boolean := False;
      Needs_Safe_String_RT : Boolean := False;
      Needs_Safe_Array_RT  : Boolean := False;
      Needs_Safe_Bounded_Strings : Boolean := False;
      Needs_Ada_Strings_Unbounded : Boolean := False;
      Needs_Ada_Real_Time : Boolean := False;
      Needs_Unevaluated_Use_Of_Old : Boolean := False;
      Needs_Gnat_Adc     : Boolean := False;
      Needs_Unchecked_Deallocation : Boolean := False;
      Wide_Local_Names   : FT.UString_Vectors.Vector;
      Static_Length_Bindings : Static_Length_Binding_Vectors.Vector;
      Static_Integer_Bindings : Static_Integer_Binding_Vectors.Vector;
      Loop_Integer_Bindings : Static_Integer_Binding_Vectors.Vector;
      Static_String_Bindings : Static_String_Binding_Vectors.Vector;
      Bounded_String_Bounds : FT.UString_Vectors.Vector;
      Type_Binding_Stack : Type_Binding_Frame_Vectors.Vector;
      Unsupported_Span   : FT.Source_Span := FT.Null_Span;
      Unsupported_Message : FT.UString := FT.To_UString ("");
      Cleanup_Stack      : Cleanup_Frame_Vectors.Vector;
      Task_Body_Depth    : Natural := 0;
   end record;

   type Emit_Context is record
      State      : Emit_State;
      Spec_Inner : SU.Unbounded_String;
      Body_Inner : SU.Unbounded_String;
      Spec_Text  : SU.Unbounded_String;
      Body_Text  : SU.Unbounded_String;
      Body_Withs : FT.UString_Vectors.Vector;
      Imported_Use_Types : FT.UString_Vectors.Vector;
      Imported_Enum_Literal_Use_Names : FT.UString_Vectors.Vector;
      Synthetic_Types : GM.Type_Descriptor_Vectors.Vector;
      Owner_Access_Helper_Types : GM.Type_Descriptor_Vectors.Vector;
      For_Of_Helper_Types : GM.Type_Descriptor_Vectors.Vector;
      Deferred_User_Types : GM.Type_Descriptor_Vectors.Vector;
      Deferred_Package_Init_Names : FT.UString_Vectors.Vector;
      Emit_Result_Builtin_First : Boolean := False;
      Emitted_Synthetic_Names : FT.UString_Vectors.Vector;
      Package_Dispatcher_Names : FT.UString_Vectors.Vector;
      Package_Dispatcher_Timer_Names : FT.UString_Vectors.Vector;
      Package_Select_Rotation_Names : FT.UString_Vectors.Vector;
      Package_Select_Rotation_Counts : FT.UString_Vectors.Vector;
      Needs_Spark_Off_Elaboration_Helper : Boolean := False;
      Omit_Initializes_Aspect : Boolean := False;
   end record;

   type Warning_Suppression is record
      Pattern : FT.UString := FT.To_UString ("");
      Reason  : FT.UString := FT.To_UString ("");
   end record;

   type Warning_Suppression_Array is array (Positive range <>) of Warning_Suppression;
   type Warning_Restore_Array is array (Positive range <>) of FT.UString;

   type Heap_Helper_Family_Kind is
     (Heap_Helper_Shared,
      Heap_Helper_For_Of,
      Heap_Helper_Channel);

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
   function Is_Access_Type (Info : GM.Type_Descriptor) return Boolean;
   function Is_Owner_Access (Info : GM.Type_Descriptor) return Boolean;
   function Sanitized_Helper_Name (Name : String) return String;
   function Indentation (Depth : Natural) return String;
   procedure Append_Line
     (Buffer : in out SU.Unbounded_String;
      Text   : String := "";
      Depth  : Natural := 0);
   function Join_Names (Items : FT.UString_Vectors.Vector) return String;
   function Contains_Name
     (Items : FT.UString_Vectors.Vector;
      Name  : String) return Boolean;
   function Starts_With
     (Text   : String;
      Prefix : String) return Boolean;
   function Root_Name (Expr : CM.Expr_Access) return String;
   function Lookup_Channel
     (Unit : CM.Resolved_Unit;
      Name : String) return CM.Resolved_Channel_Decl;
   function Shared_Wrapper_Object_Name
     (Root_Name : String) return String;
   function Shared_Wrapper_Type_Name
     (Root_Name : String) return String;
   function Shared_Public_Helper_Base_Name
     (Root_Name : String) return String;
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
   function Shared_Field_Getter_Name
     (Field_Name : String) return String;
   function Shared_Field_Setter_Name
     (Field_Name : String) return String;
   function Shared_Nested_Field_Setter_Name
     (Path_Names : FT.UString_Vectors.Vector) return String;
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
   procedure Bind_Static_Length
     (State  : in out Emit_State;
      Name   : String;
      Length : Natural);
   function Try_Static_Length
     (State  : Emit_State;
      Name   : String;
      Length : out Natural) return Boolean;
   procedure Restore_Static_Length_Bindings
     (State           : in out Emit_State;
      Previous_Length : Ada.Containers.Count_Type);
   procedure Invalidate_Static_Length
     (State : in out Emit_State;
      Name  : String);
   procedure Bind_Static_Integer
     (State : in out Emit_State;
      Name  : String;
      Value : Long_Long_Integer);
   procedure Invalidate_Static_Integer
     (State : in out Emit_State;
      Name  : String);
   procedure Bind_Loop_Integer
     (State : in out Emit_State;
      Name  : String;
      Value : Long_Long_Integer);
   procedure Invalidate_Loop_Integer
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
   function Has_Loop_Integer_Tracking
     (State : Emit_State;
      Name  : String) return Boolean;
   function Try_Loop_Integer_Binding
     (State : Emit_State;
      Name  : String;
      Value : out Long_Long_Integer) return Boolean;
   function Try_Static_String_Binding
     (State : Emit_State;
      Name  : String;
      Image : out SU.Unbounded_String) return Boolean;
   procedure Restore_Static_Integer_Bindings
     (State           : in out Emit_State;
      Previous_Length : Ada.Containers.Count_Type);
   procedure Restore_Loop_Integer_Bindings
     (State           : in out Emit_State;
      Previous_Length : Ada.Containers.Count_Type);
   procedure Restore_Static_String_Bindings
     (State           : in out Emit_State;
      Previous_Length : Ada.Containers.Count_Type);
   procedure Clear_All_Static_Bindings (State : in out Emit_State);
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
      Params : CM.Symbol_Vectors.Vector);
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
      Action    : Cleanup_Action := Cleanup_Deallocate);
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
     (Buffer    : in out SU.Unbounded_String;
      State     : Emit_State;
      Depth     : Natural;
      Skip_Name : String := "");
   procedure Render_Current_Cleanup_Frame
     (Buffer : in out SU.Unbounded_String;
      State  : Emit_State;
      Depth  : Natural);
   function Has_Active_Cleanup_Items (State : Emit_State) return Boolean;
   procedure Render_Cleanup
     (Buffer       : in out SU.Unbounded_String;
      Declarations : CM.Resolved_Object_Decl_Vectors.Vector;
      Depth        : Natural);
   procedure Render_Cleanup
     (Buffer       : in out SU.Unbounded_String;
      Declarations : CM.Object_Decl_Vectors.Vector;
      Depth        : Natural);
   function Statement_Contains_Exit
     (Item : CM.Statement_Access) return Boolean;
   function Statements_Contain_Exit
     (Statements : CM.Statement_Access_Vectors.Vector) return Boolean;
   function Statement_Falls_Through
     (Item : CM.Statement_Access) return Boolean;
   function Statements_Fall_Through
     (Statements : CM.Statement_Access_Vectors.Vector) return Boolean;
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
   procedure Add_Body_With
     (Context : in out Emit_Context;
      Name    : String);
   procedure Add_Imported_Use_Type
     (Context : in out Emit_Context;
      Name    : String);
   function Package_Select_Refined_State
     (Context : Emit_Context) return String;
end Safe_Frontend.Ada_Emit.Internal;
