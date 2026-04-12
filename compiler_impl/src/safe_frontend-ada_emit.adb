with Ada.Characters.Handling;
with Ada.Containers;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Safe_Frontend.Ada_Emit.Channels;
with Safe_Frontend.Ada_Emit.Expressions;
with Safe_Frontend.Ada_Emit.Internal;
with Safe_Frontend.Ada_Emit.Proofs;
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
   package AEC renames Safe_Frontend.Ada_Emit.Channels;
   package AEP renames Safe_Frontend.Ada_Emit.Proofs;
   use AI;
   use AET;
   use AEX;
   use AES;
   use AEC;
   use AEP;

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

   function Gnat_Adc_Text return String is
     (Gnat_Adc_Contents);

   function Sanitize_Type_Name_Component (Value : String) return String
     renames FNU.Sanitize_Type_Name_Component;

   function Has_Text (Item : FT.UString) return Boolean renames AI.Has_Text;
   function Trim_Image (Value : Long_Long_Integer) return String renames AI.Trim_Image;
   function Trim_Wide_Image (Value : CM.Wide_Integer) return String renames AI.Trim_Wide_Image;

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

   function Is_Access_Type (Info : GM.Type_Descriptor) return Boolean renames AI.Is_Access_Type;
   function Is_Owner_Access (Info : GM.Type_Descriptor) return Boolean renames AI.Is_Owner_Access;

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

   function Sanitized_Helper_Name (Name : String) return String renames AI.Sanitized_Helper_Name;

   function Needs_Generated_For_Of_Helper
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean renames AET.Needs_Generated_For_Of_Helper;

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

   function Try_Static_String_Binding
     (State : Emit_State;
      Name  : String;
      Image : out SU.Unbounded_String) return Boolean renames AI.Try_Static_String_Binding;

   procedure Restore_Static_String_Bindings
     (State           : in out Emit_State;
      Previous_Length : Ada.Containers.Count_Type) renames AI.Restore_Static_String_Bindings;

   procedure Clear_All_Static_Bindings (State : in out Emit_State) renames AI.Clear_All_Static_Bindings;

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

   function Uses_Wide_Value
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      State    : Emit_State;
      Expr     : CM.Expr_Access) return Boolean renames AEX.Uses_Wide_Value;

   function Render_Channel_Send_Value
     (Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      State        : in out Emit_State;
      Channel_Expr : CM.Expr_Access;
      Value        : CM.Expr_Access) return String renames AEX.Render_Channel_Send_Value;

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

   function Statement_Contains_Exit
     (Item : CM.Statement_Access) return Boolean renames AI.Statement_Contains_Exit;

   function Statements_Contain_Exit
     (Statements : CM.Statement_Access_Vectors.Vector) return Boolean renames AI.Statements_Contain_Exit;

   function Statement_Falls_Through
     (Item : CM.Statement_Access) return Boolean renames AI.Statement_Falls_Through;

   function Statements_Fall_Through
     (Statements : CM.Statement_Access_Vectors.Vector) return Boolean renames AI.Statements_Fall_Through;

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

   procedure Render_Cleanup
     (Buffer       : in out SU.Unbounded_String;
      Declarations : CM.Resolved_Object_Decl_Vectors.Vector;
      Depth        : Natural) renames AI.Render_Cleanup;

   procedure Render_Cleanup
     (Buffer       : in out SU.Unbounded_String;
      Declarations : CM.Object_Decl_Vectors.Vector;
      Depth        : Natural) renames AI.Render_Cleanup;

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

   function Apply_Name_Replacements
     (Text       : String;
      From_Names : FT.UString_Vectors.Vector;
      To_Names   : FT.UString_Vectors.Vector) return String renames AEX.Apply_Name_Replacements;

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

      function Enclosing_Package_Name (Qualified_Type : String) return String is
      begin
         for Index in reverse Qualified_Type'Range loop
            if Qualified_Type (Index) = '.' then
               return Qualified_Type (Qualified_Type'First .. Index - 1);
            end if;
         end loop;
         return "";
      end Enclosing_Package_Name;

      function Spec_Uses_Imported_Enum_Type (Qualified_Type : String) return Boolean is
         Package_Name : constant String := Enclosing_Package_Name (Qualified_Type);
      begin
         return
           Ada.Strings.Fixed.Index (Original_Spec, Qualified_Type) > 0
           or else
             (Package_Name'Length > 0
              and then Ada.Strings.Fixed.Index (Original_Spec, Package_Name & ".") > 0);
      end Spec_Uses_Imported_Enum_Type;

      function Spec_Needs_Imported_Enum_Use_Types return Boolean is
      begin
         for Item of Context.Imported_Enum_Use_Types loop
            if Spec_Uses_Imported_Enum_Type (FT.To_String (Item)) then
               return True;
            end if;
         end loop;
         return False;
      end Spec_Needs_Imported_Enum_Use_Types;

      Spec_Needs_Imported_Enums : constant Boolean :=
        Spec_Needs_Imported_Enum_Use_Types;
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
          or else Spec_Needs_Imported_Enums
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
         declare
            Imported_Enum_Withs : FT.UString_Vectors.Vector;
         begin
            for Item of Context.Imported_Enum_Use_Types loop
               declare
                  Enum_Type_Name : constant String := FT.To_String (Item);
                  Package_Name   : constant String :=
                    Enclosing_Package_Name (Enum_Type_Name);
               begin
                  if Spec_Uses_Imported_Enum_Type (Enum_Type_Name) then
                     if Package_Name'Length > 0
                       and then not Contains_Name (Imported_Enum_Withs, Package_Name)
                     then
                        Append_Line (Context.Spec_Text, "with " & Package_Name & ";");
                        Imported_Enum_Withs.Append (FT.To_UString (Package_Name));
                     end if;
                     Append_Line (Context.Spec_Text, "use type " & Enum_Type_Name & ";");
                  end if;
               end;
            end loop;
         end;
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
