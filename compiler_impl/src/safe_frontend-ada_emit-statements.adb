with Ada.Containers;
with Ada.Containers.Vectors;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Safe_Frontend.Ada_Emit.Internal;
with Safe_Frontend.Ada_Emit.Types;
with Safe_Frontend.Ada_Emit.Expressions;

package body Safe_Frontend.Ada_Emit.Statements is
   use AI;

   use type Ada.Containers.Count_Type;
   use type CM.Expr_Access;
   use type CM.Expr_Kind;
   use type CM.Statement_Access;
   use type CM.Statement_Kind;
   use type CM.Discrete_Range_Kind;
   use type CM.Select_Arm_Kind;
   use type FT.UString;
   use type GM.Scalar_Value_Kind;

   subtype Cleanup_Action is AI.Cleanup_Action;
   subtype Cleanup_Item is AI.Cleanup_Item;
   subtype Warning_Suppression_Array is AI.Warning_Suppression_Array;
   subtype Warning_Restore_Array is AI.Warning_Restore_Array;

   type Shared_Field_Getter_Info is record
      Found               : Boolean := False;
      Root_Key            : FT.UString := FT.To_UString ("");
      Call_Image          : FT.UString := FT.To_UString ("");
      Snapshot_Type_Image : FT.UString := FT.To_UString ("");
      Snapshot_Init_Image : FT.UString := FT.To_UString ("");
      Field_Ada_Name      : FT.UString := FT.To_UString ("");
   end record;

   type Shared_Condition_Snapshot is record
      Root_Key            : FT.UString := FT.To_UString ("");
      Snapshot_Name       : FT.UString := FT.To_UString ("");
      Snapshot_Type_Image : FT.UString := FT.To_UString ("");
      Snapshot_Init_Image : FT.UString := FT.To_UString ("");
   end record;

   package Shared_Condition_Snapshot_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Shared_Condition_Snapshot);

   type Shared_Condition_Replacement is record
      Call_Image        : FT.UString := FT.To_UString ("");
      Replacement_Image : FT.UString := FT.To_UString ("");
   end record;

   package Shared_Condition_Replacement_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Shared_Condition_Replacement);

   type Shared_Condition_Render is record
      Image        : FT.UString := FT.To_UString ("");
      Snapshots    : Shared_Condition_Snapshot_Vectors.Vector;
      Replacements : Shared_Condition_Replacement_Vectors.Vector;
   end record;

   procedure Raise_Internal (Message : String) renames AI.Raise_Internal;
   procedure Raise_Unsupported
     (State   : in out Emit_State;
      Span    : FT.Source_Span;
      Message : String) renames AI.Raise_Unsupported;

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
     (Buffer    : in out SU.Unbounded_String;
      State     : Emit_State;
      Depth     : Natural;
      Skip_Name : String := "") renames AI.Render_Active_Cleanup;
   procedure Render_Current_Cleanup_Frame
     (Buffer : in out SU.Unbounded_String;
      State  : Emit_State;
      Depth  : Natural) renames AI.Render_Current_Cleanup_Frame;
   function Has_Active_Cleanup_Items (State : Emit_State) return Boolean renames AI.Has_Active_Cleanup_Items;
   procedure Render_Cleanup
     (Buffer       : in out SU.Unbounded_String;
      Declarations : CM.Resolved_Object_Decl_Vectors.Vector;
      Depth        : Natural) renames AI.Render_Cleanup;
   function Statement_Falls_Through (Item : CM.Statement_Access) return Boolean renames AI.Statement_Falls_Through;
   function Statements_Fall_Through (Statements : CM.Statement_Access_Vectors.Vector) return Boolean renames AI.Statements_Fall_Through;
   function Statement_Contains_Exit (Item : CM.Statement_Access) return Boolean renames AI.Statement_Contains_Exit;
   function Statements_Contain_Exit (Statements : CM.Statement_Access_Vectors.Vector) return Boolean renames AI.Statements_Contain_Exit;
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
   procedure Append_Initialization_Warning_Suppression
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) renames AI.Append_Initialization_Warning_Suppression;
   procedure Append_Initialization_Warning_Restore
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) renames AI.Append_Initialization_Warning_Restore;
   procedure Append_Local_Warning_Suppression
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) renames AI.Append_Local_Warning_Suppression;
   procedure Append_Local_Warning_Restore
     (Buffer : in out SU.Unbounded_String;
      Depth  : Natural) renames AI.Append_Local_Warning_Restore;
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

   package AET renames Safe_Frontend.Ada_Emit.Types;
   package AEX renames Safe_Frontend.Ada_Emit.Expressions;
   use AET;
   use AEX;

   function Unit_Runtime_Assigns_Name
     (Unit : CM.Resolved_Unit;
      Name : String) return Boolean;
   function Block_Declarations_Immediately_Overwritten
     (Declarations : CM.Object_Decl_Vectors.Vector;
      Statements   : CM.Statement_Access_Vectors.Vector) return Boolean;
   function Channel_Copy_Helper_Name
     (Channel_Item : CM.Resolved_Channel_Decl) return String;
   function Channel_Free_Helper_Name
     (Channel_Item : CM.Resolved_Channel_Decl) return String;
   function Channel_Uses_Sequential_Scalar_Ghost_Model
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Channel  : CM.Resolved_Channel_Decl) return Boolean;
   function Is_Print_Call (Expr : CM.Expr_Access) return Boolean;
   function Render_Discrete_Range
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Item_Range : CM.Discrete_Range;
      State    : in out Emit_State) return String;
   procedure Append_Assignment
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      State    : in out Emit_State;
      Stmt     : CM.Statement;
      Depth    : Natural;
      In_Loop  : Boolean := False);
   procedure Append_Float_Loop_Invariant
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      State    : in out Emit_State;
      Target   : CM.Expr_Access;
      Depth    : Natural);
   procedure Append_Integer_Loop_Invariant
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      State    : in out Emit_State;
      Target   : CM.Expr_Access;
      Depth    : Natural);
   procedure Append_Return
     (Buffer     : in out SU.Unbounded_String;
      Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      State      : in out Emit_State;
      Value      : CM.Expr_Access;
      Return_Type : String;
      Depth      : Natural);
   procedure Append_Return_With_Cleanup
     (Buffer      : in out SU.Unbounded_String;
      Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      State       : in out Emit_State;
      Value       : CM.Expr_Access;
      Return_Type : String;
      Depth       : Natural);
   function Statements_Assign_Name
     (Statements : CM.Statement_Access_Vectors.Vector;
      Name       : String) return Boolean
   ;
   function Expr_Needs_Shared_Condition_Snapshot
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access) return Boolean
   ;
   function Render_Shared_Condition
     (Unit            : CM.Resolved_Unit;
      Document        : GM.Mir_Document;
      Expr            : CM.Expr_Access;
      State           : in out Emit_State;
      Statement_Index : Positive) return Shared_Condition_Render
   ;
   procedure Append_Shared_Condition_Declarations
     (Buffer   : in out SU.Unbounded_String;
      Rendered : Shared_Condition_Render;
      Depth    : Natural)
   ;
   function Replace_All
     (Text : String;
      From : String;
      To   : String) return String
   ;
   function Is_Explicit_Float_Narrowing
     (Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      Target_Type : String;
      Expr        : CM.Expr_Access) return Boolean
   ;
   function Try_Render_Stable_Float_Interpolation
     (Unit            : CM.Resolved_Unit;
      Document        : GM.Mir_Document;
      Expr            : CM.Expr_Access;
      State           : in out Emit_State;
      Condition_Image : out FT.UString;
      Lower_Image     : out FT.UString;
      Upper_Image     : out FT.UString) return Boolean
   ;
   procedure Mark_Wide_Declaration
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      State     : in out Emit_State;
      Decl      : CM.Resolved_Object_Decl);
   procedure Mark_Wide_Declaration
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      State     : in out Emit_State;
      Decl      : CM.Object_Decl);
   procedure Collect_Wide_Locals_From_Statements
     (Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      State       : in out Emit_State;
      Statements  : CM.Statement_Access_Vectors.Vector);
   procedure Append_Narrowing_Assignment
     (Buffer     : in out SU.Unbounded_String;
      Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      State      : in out Emit_State;
      Target     : CM.Expr_Access;
      Value      : CM.Expr_Access;
      Depth      : Natural)
   ;
   procedure Append_Float_Narrowing_Checks
     (Buffer       : in out SU.Unbounded_String;
      Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      Target_Type  : String;
      Value_Name   : String;
      Depth        : Natural)
   ;
   procedure Append_Float_Narrowing_Assignment
     (Buffer       : in out SU.Unbounded_String;
      Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      Target_Type  : String;
      Target_Image : String;
      Inner_Image  : String;
      Depth        : Natural)
   ;
   procedure Append_Float_Narrowing_Return
     (Buffer      : in out SU.Unbounded_String;
      Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      Target_Type : String;
      Inner_Image : String;
      Depth       : Natural)
   ;
   procedure Append_Move_Null
     (Buffer     : in out SU.Unbounded_String;
      Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      State      : in out Emit_State;
      Value      : CM.Expr_Access;
      Depth      : Natural)
   ;
   function Root_Name (Expr : CM.Expr_Access) return String renames AI.Root_Name;
   function Lookup_Channel
     (Unit : CM.Resolved_Unit;
      Name : String) return CM.Resolved_Channel_Decl renames AI.Lookup_Channel;

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
      Names      : in out FT.UString_Vectors.Vector)
   is
      procedure Visit_Statement (Stmt : CM.Statement_Access) is
         Name_Text : constant String := Select_Dispatcher_Name (Stmt);
      begin
         if Stmt = null or else Stmt.Kind /= CM.Stmt_Select then
            return;
         elsif not Contains_Name (Names, Name_Text) then
            Names.Append (FT.To_UString (Name_Text));
         end if;
      end Visit_Statement;

      procedure Collect_From is new Walk_Statement_Structure
        (Visit_Statement, Ignore_Select_Arm);
   begin
      Collect_From (Statements);
   end Collect_Select_Dispatcher_Names;

   procedure Collect_Select_Rotation_State
     (Statements : CM.Statement_Access_Vectors.Vector;
      Names      : in out FT.UString_Vectors.Vector;
      Counts     : in out FT.UString_Vectors.Vector)
   is
      procedure Visit_Statement (Stmt : CM.Statement_Access) is
         Name_Text         : constant String := Select_Rotation_State_Name (Stmt);
         Channel_Arm_Count : Natural := 0;
      begin
         if Stmt = null or else Stmt.Kind /= CM.Stmt_Select then
            return;
         end if;

         for Arm of Stmt.Arms loop
            if Arm.Kind = CM.Select_Arm_Channel then
               Channel_Arm_Count := Channel_Arm_Count + 1;
            end if;
         end loop;

         if Channel_Arm_Count = 0 or else Contains_Name (Names, Name_Text) then
            return;
         end if;

         Names.Append (FT.To_UString (Name_Text));
         Counts.Append (FT.To_UString (Trim_Image (Long_Long_Integer (Channel_Arm_Count))));
      end Visit_Statement;

      procedure Collect_From is new Walk_Statement_Structure
        (Visit_Statement, Ignore_Select_Arm);
   begin
      Collect_From (Statements);
   end Collect_Select_Rotation_State;

   procedure Collect_Select_Delay_Timer_Names
     (Statements : CM.Statement_Access_Vectors.Vector;
      Names      : in out FT.UString_Vectors.Vector)
   is
      procedure Visit_Statement (Stmt : CM.Statement_Access) is
         Name_Text : constant String := Select_Dispatcher_Timer_Name (Stmt);
      begin
         if Stmt = null or else Stmt.Kind /= CM.Stmt_Select then
            return;
         elsif Select_Has_Delay_Arm (Stmt)
           and then not Contains_Name (Names, Name_Text)
         then
            Names.Append (FT.To_UString (Name_Text));
         end if;
      end Visit_Statement;

      procedure Collect_From is new Walk_Statement_Structure
        (Visit_Statement, Ignore_Select_Arm);
   begin
      Collect_From (Statements);
   end Collect_Select_Delay_Timer_Names;

   procedure Collect_Select_Dispatcher_Names_For_Channel
     (Statements   : CM.Statement_Access_Vectors.Vector;
      Channel_Name : String;
      Names        : in out FT.UString_Vectors.Vector)
   is
      procedure Visit_Statement (Stmt : CM.Statement_Access) is
         Name_Text : constant String := Select_Dispatcher_Name (Stmt);
      begin
         if Stmt = null or else Stmt.Kind /= CM.Stmt_Select then
            return;
         elsif Select_References_Channel (Stmt, Channel_Name)
           and then not Contains_Name (Names, Name_Text)
         then
            Names.Append (FT.To_UString (Name_Text));
         end if;
      end Visit_Statement;

      procedure Collect_From is new Walk_Statement_Structure
        (Visit_Statement, Ignore_Select_Arm);
   begin
      Collect_From (Statements);
   end Collect_Select_Dispatcher_Names_For_Channel;

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

   procedure Collect_Bounded_String_Types
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      State    : in out Emit_State)
   is
      Processed : FT.UString_Vectors.Vector;

      procedure Add_From_Info (Info : GM.Type_Descriptor);

      procedure Add_From_Name (Name : String) is
      begin
         if Name'Length = 0 then
            null;
         elsif Has_Type (Unit, Document, Name) then
            Add_From_Info (Lookup_Type (Unit, Document, Name));
         elsif Starts_With (Name, "__bounded_string_") then
            declare
               Found : Boolean := False;
               Info  : GM.Type_Descriptor := (others => <>);
            begin
               Info := Synthetic_Bounded_String_Type (Name, Found);
               if Found then
                  Add_From_Info (Info);
               end if;
            end;
         end if;
      end Add_From_Name;

      procedure Add_From_Info (Info : GM.Type_Descriptor) is
         Name_Text : constant String := FT.To_String (Info.Name);
      begin
         if Has_Text (Info.Name)
           and then Contains_Name (Processed, Name_Text)
         then
            return;
         elsif Has_Text (Info.Name) then
            Processed.Append (Info.Name);
         end if;

         Register_Bounded_String_Type (State, Info);
         if Info.Has_Base then
            Add_From_Name (FT.To_String (Info.Base));
         end if;
         if Info.Has_Component_Type then
            Add_From_Name (FT.To_String (Info.Component_Type));
         end if;
         if Info.Has_Target then
            Add_From_Name (FT.To_String (Info.Target));
         end if;
         for Item of Info.Tuple_Element_Types loop
            Add_From_Name (FT.To_String (Item));
         end loop;
         for Field of Info.Fields loop
            Add_From_Name (FT.To_String (Field.Type_Name));
         end loop;
         for Field of Info.Variant_Fields loop
            Add_From_Name (FT.To_String (Field.Type_Name));
         end loop;
      end Add_From_Info;

      procedure Add_From_Decls (Decls : CM.Resolved_Object_Decl_Vectors.Vector) is
      begin
         for Decl of Decls loop
            Add_From_Info (Decl.Type_Info);
         end loop;
      end Add_From_Decls;

      procedure Visit_Statement (Item : CM.Statement_Access) is
      begin
         case Item.Kind is
            when CM.Stmt_Object_Decl =>
               Add_From_Info (Item.Decl.Type_Info);
            when CM.Stmt_Destructure_Decl =>
               Add_From_Info (Item.Destructure.Type_Info);
            when CM.Stmt_For =>
               if Item.Loop_Iterable /= null then
                  declare
                     Found : Boolean := False;
                     One_Char_Info : GM.Type_Descriptor := (others => <>);
                  begin
                     One_Char_Info :=
                       Synthetic_Bounded_String_Type ("__bounded_string_1", Found);
                     if Found then
                        Add_From_Info (One_Char_Info);
                     end if;
                  end;
               end if;
            when others =>
               null;
         end case;
      end Visit_Statement;

      procedure Visit_Select_Arm (Arm : CM.Select_Arm) is
      begin
         if Arm.Kind = CM.Select_Arm_Channel then
            Add_From_Info (Arm.Channel_Data.Type_Info);
         end if;
      end Visit_Select_Arm;

      procedure Add_From_Statements is new Walk_Statement_Structure
        (Visit_Statement, Visit_Select_Arm);
   begin
      for Item of Unit.Types loop
         if Item.Generic_Formals.Is_Empty then
            Add_From_Info (Item);
         end if;
      end loop;
      for Item of Unit.Objects loop
         Add_From_Info (Item.Type_Info);
      end loop;
      for Item of Unit.Channels loop
         Add_From_Info (Item.Element_Type);
      end loop;
      for Item of Unit.Subprograms loop
         for Param of Item.Params loop
            Add_From_Info (Param.Type_Info);
         end loop;
         if Item.Has_Return_Type then
            Add_From_Info (Item.Return_Type);
         end if;
         Add_From_Decls (Item.Declarations);
         Add_From_Statements (Item.Statements);
      end loop;
      for Item of Unit.Tasks loop
         Add_From_Decls (Item.Declarations);
         Add_From_Statements (Item.Statements);
      end loop;
      Add_From_Statements (Unit.Statements);
   end Collect_Bounded_String_Types;

   procedure Collect_For_Of_Helper_Types
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Result   : in out GM.Type_Descriptor_Vectors.Vector)
   is
      Seen : FT.UString_Vectors.Vector;

      procedure Add_From_Info (Info : GM.Type_Descriptor);

      procedure Add_From_Info (Info : GM.Type_Descriptor) is
         Name_Text : constant String := Render_Type_Name (Info);
      begin
         if not Needs_Generated_For_Of_Helper (Unit, Document, Info)
           or else Name_Text'Length = 0
         then
            return;
         elsif Contains_Name (Seen, Name_Text) then
            return;
         end if;

         Seen.Append (FT.To_UString (Name_Text));
         Result.Append (Info);
      end Add_From_Info;

      procedure Visit_Statement (Item : CM.Statement_Access) is
      begin
         if Item.Kind = CM.Stmt_For and then Item.Loop_Iterable /= null then
            declare
               Iterable_Info : constant GM.Type_Descriptor :=
                 Base_Type
                   (Unit,
                    Document,
                    Expr_Type_Info (Unit, Document, Item.Loop_Iterable));
               Is_String_Iterable : constant Boolean :=
                 FT.Lowercase (FT.To_String (Iterable_Info.Kind)) = "string";
            begin
               if not Is_String_Iterable
                 and then Iterable_Info.Has_Component_Type
               then
                  Add_From_Info
                    (Resolve_Type_Name
                       (Unit,
                        Document,
                        FT.To_String (Iterable_Info.Component_Type)));
               end if;
            end;
         end if;
      end Visit_Statement;

      procedure Add_From_Statements is new Walk_Statement_Structure
        (Visit_Statement, Ignore_Select_Arm);
   begin
      for Item of Unit.Subprograms loop
         Add_From_Statements (Item.Statements);
      end loop;
      for Item of Unit.Tasks loop
         Add_From_Statements (Item.Statements);
      end loop;
      Add_From_Statements (Unit.Statements);
   end Collect_For_Of_Helper_Types;

   procedure Collect_Owner_Access_Helper_Types
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Result   : in out GM.Type_Descriptor_Vectors.Vector)
   is
      pragma Unreferenced (Document);
      Seen : FT.UString_Vectors.Vector;

      procedure Add_From_Info (Info : GM.Type_Descriptor);
      procedure Add_From_Decls (Decls : CM.Resolved_Object_Decl_Vectors.Vector);
      procedure Add_From_Decls (Decls : CM.Object_Decl_Vectors.Vector);

      procedure Add_From_Info (Info : GM.Type_Descriptor) is
         Name_Text : constant String := FT.To_String (Info.Name);
      begin
         if not AI.Is_Owner_Access (Info) or else Name_Text'Length = 0 then
            null;
         elsif Contains_Name (Seen, Name_Text) then
            return;
         else
            Seen.Append (Info.Name);
            Result.Append (Info);
         end if;
      end Add_From_Info;

      procedure Add_From_Decls (Decls : CM.Resolved_Object_Decl_Vectors.Vector) is
      begin
         for Decl of Decls loop
            Add_From_Info (Decl.Type_Info);
         end loop;
      end Add_From_Decls;

      procedure Add_From_Decls (Decls : CM.Object_Decl_Vectors.Vector) is
      begin
         for Decl of Decls loop
            Add_From_Info (Decl.Type_Info);
         end loop;
      end Add_From_Decls;

      procedure Visit_Statement (Item : CM.Statement_Access) is
      begin
         case Item.Kind is
            when CM.Stmt_Object_Decl =>
               Add_From_Info (Item.Decl.Type_Info);
            when CM.Stmt_Destructure_Decl =>
               Add_From_Info (Item.Destructure.Type_Info);
            when CM.Stmt_While | CM.Stmt_For | CM.Stmt_Loop =>
               Add_From_Decls (Item.Declarations);
            when others =>
               null;
         end case;
      end Visit_Statement;

      procedure Visit_Select_Arm (Arm : CM.Select_Arm) is
      begin
         if Arm.Kind = CM.Select_Arm_Channel then
            Add_From_Info (Arm.Channel_Data.Type_Info);
         end if;
      end Visit_Select_Arm;

      procedure Add_From_Statements is new Walk_Statement_Structure
        (Visit_Statement, Visit_Select_Arm);
   begin
      for Item of Unit.Types loop
         if Item.Generic_Formals.Is_Empty then
            Add_From_Info (Item);
         end if;
      end loop;
      for Item of Unit.Objects loop
         Add_From_Info (Item.Type_Info);
      end loop;
      for Item of Unit.Subprograms loop
         for Param of Item.Params loop
            Add_From_Info (Param.Type_Info);
         end loop;
         if Item.Has_Return_Type then
            Add_From_Info (Item.Return_Type);
         end if;
         Add_From_Decls (Item.Declarations);
         Add_From_Statements (Item.Statements);
      end loop;
      for Item of Unit.Tasks loop
         Add_From_Decls (Item.Declarations);
         Add_From_Statements (Item.Statements);
      end loop;
   end Collect_Owner_Access_Helper_Types;

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
        (if Is_Constant
           and then not Defer_Initializer
           and then not AI.Is_Owner_Access (Type_Info)
         then "constant "
         else "");
      Type_Name : constant String :=
        (if Is_Wide_Integer_Type (Unit, Document, Type_Info)
           and then Names_Use_Wide_Storage (State, Names)
         then "safe_runtime.wide_integer"
         elsif Local_Context
           and then AI.Is_Access_Type (Type_Info)
           and then not AI.Is_Owner_Access (Type_Info)
           and then Has_Text (Type_Info.Target)
         then
           (if Type_Info.Not_Null then "not null " else "")
           & "access "
           & (if Type_Info.Is_Constant then "constant " else "")
           & FT.To_String (Type_Info.Target)
         elsif AI.Is_Owner_Access (Type_Info)
         then Render_Type_Name (Type_Info)
         else Render_Subtype_Indication (Unit, Document, Type_Info));
      function Render_Initializer return String is
      begin
         if Initializer /= null and then AI.Is_Owner_Access (Type_Info) then
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
        and then not AI.Is_Owner_Access (Type_Info)
        and then Has_Heap_Value_Type (Unit, Document, Type_Info);
      Needs_Explicit_Default_Init : constant Boolean :=
        Has_Implicit_Default_Init
        and then Initializer = null
        and then Needs_Explicit_Default_Initializer (Unit, Document, Type_Info);
      Suppress_Explicit_Null_Init : constant Boolean :=
        Initializer /= null
        and then Initializer.Kind = CM.Expr_Null
        and then not Is_Constant
        and then AI.Is_Owner_Access (Type_Info);
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
            elsif Is_Wide_Integer_Type (Unit, Document, Type_Info)
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
      Defer_Initializer : Boolean := False) return String
   is
   begin
      return
        Render_Object_Decl_Text_Common
          (Unit            => Unit,
           Document        => Document,
           State           => State,
           Names           => Decl.Names,
           Type_Info       => Decl.Type_Info,
           Is_Constant     => Decl.Is_Constant,
           Has_Initializer => Decl.Has_Initializer,
           Has_Implicit_Default_Init => Decl.Has_Implicit_Default_Init,
           Initializer     => Decl.Initializer,
           Local_Context   => Local_Context,
           Defer_Initializer => Defer_Initializer);
   end Render_Object_Decl_Text;

   function Render_Object_Decl_Text
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      State    : in out Emit_State;
      Decl     : CM.Object_Decl;
      Local_Context : Boolean := False;
      Defer_Initializer : Boolean := False) return String
   is
   begin
      return
        Render_Object_Decl_Text_Common
          (Unit            => Unit,
           Document        => Document,
           State           => State,
           Names           => Decl.Names,
           Type_Info       => Decl.Type_Info,
           Is_Constant     => Decl.Is_Constant,
           Has_Initializer => Decl.Has_Initializer,
           Has_Implicit_Default_Init => Decl.Has_Implicit_Default_Init,
           Initializer     => Decl.Initializer,
           Local_Context   => Local_Context,
           Defer_Initializer => Defer_Initializer);
   end Render_Object_Decl_Text;

   function Loop_Variant_Image
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Condition : CM.Expr_Access;
      State     : in out Emit_State) return String
   is
      Operator : constant String :=
        (if Condition = null then "" else Map_Operator (FT.To_String (Condition.Operator)));

      function Is_Integer_Ident (Expr : CM.Expr_Access) return Boolean is
      begin
         return
           Expr /= null
           and then Expr.Kind = CM.Expr_Ident
           and then Is_Integer_Type (Unit, Document, FT.To_String (Expr.Type_Name));
      end Is_Integer_Ident;

      function Is_Integer_Bound (Expr : CM.Expr_Access) return Boolean is
      begin
         return
           Expr /= null
           and then
             (Expr.Kind = CM.Expr_Int
              or else
              (Expr.Kind = CM.Expr_Ident
               and then Is_Integer_Type (Unit, Document, FT.To_String (Expr.Type_Name))));
      end Is_Integer_Bound;

      function Is_Length_Select (Expr : CM.Expr_Access) return Boolean is
      begin
         return
           Expr /= null
           and then Expr.Kind = CM.Expr_Select
           and then FT.To_String (Expr.Selector) = "length";
      end Is_Length_Select;

      function Is_Zero (Expr : CM.Expr_Access) return Boolean is
      begin
         return Expr /= null and then Expr.Kind = CM.Expr_Int and then Expr.Int_Value = 0;
      end Is_Zero;

      function Is_One (Expr : CM.Expr_Access) return Boolean is
      begin
         return Expr /= null and then Expr.Kind = CM.Expr_Int and then Expr.Int_Value = 1;
      end Is_One;

      function Is_Positive_Right_Bound
        (Op    : String;
         Bound : CM.Expr_Access) return Boolean is
      begin
         return
           (Op = ">" and then Is_Zero (Bound))
           or else
           (Op = ">=" and then Is_One (Bound));
      end Is_Positive_Right_Bound;

      function Is_Positive_Left_Mirror_Bound
        (Op    : String;
         Bound : CM.Expr_Access) return Boolean is
      begin
         return
           (Op = "<" and then Is_Zero (Bound))
           or else
           (Op = "<=" and then Is_One (Bound));
      end Is_Positive_Left_Mirror_Bound;
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
         if Is_Integer_Ident (Condition.Left)
           and then Is_Integer_Ident (Condition.Right)
         then
            return
              "Increases => "
              & FT.To_String (Condition.Left.Name)
              & ", Decreases => "
              & FT.To_String (Condition.Right.Name);
         elsif Is_Positive_Left_Mirror_Bound (Operator, Condition.Left)
           and then Is_Integer_Ident (Condition.Right)
         then
            return "Decreases => " & FT.To_String (Condition.Right.Name);
         elsif Is_Positive_Left_Mirror_Bound (Operator, Condition.Left)
           and then Is_Length_Select (Condition.Right)
         then
            return
              "Decreases => "
              & Render_Expr (Unit, Document, Condition.Right, State);
         end if;
      elsif Operator in ">" | ">=" then
         --  Downward countdowns intentionally track the moving left side only.
         --  The existing < / <= two-identifier path keeps the bidirectional form.
         if Is_Integer_Ident (Condition.Left)
           and then Is_Integer_Bound (Condition.Right)
         then
            return "Decreases => " & FT.To_String (Condition.Left.Name);
         elsif Is_Length_Select (Condition.Left)
           and then Is_Positive_Right_Bound (Operator, Condition.Right)
         then
            return
              "Decreases => "
              & Render_Expr (Unit, Document, Condition.Left, State);
         end if;
      elsif Operator = "=" then
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
      end if;

      return "";
   end Loop_Variant_Image;

   function Render_Variant_While_Guard_Image
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Condition : CM.Expr_Access;
      Rendered  : Shared_Condition_Render;
      State     : in out Emit_State) return String
   is
      Operator : constant String :=
        (if Condition = null then "" else Map_Operator (FT.To_String (Condition.Operator)));
      Image    : SU.Unbounded_String;
   begin
      if Condition = null
        or else Condition.Kind /= CM.Expr_Binary
        or else Condition.Left = null
        or else Condition.Right = null
        or else Operator'Length = 0
      then
         return "";
      end if;

      --  Keep variant-bearing while guards as runtime checks even when current
      --  static bindings can prove the first iteration enters. Preserve any
      --  shared-condition snapshots so getter calls remain single-evaluated.
      Image :=
        SU.To_Unbounded_String
          (Render_Expr (Unit, Document, Condition.Left, State)
           & " "
           & Operator
           & " "
           & Render_Expr (Unit, Document, Condition.Right, State));

      for Replacement of Rendered.Replacements loop
         Image :=
           SU.To_Unbounded_String
             (Replace_All
                (SU.To_String (Image),
                 FT.To_String (Replacement.Call_Image),
                 FT.To_String (Replacement.Replacement_Image)));
      end loop;

      return SU.To_String (Image);
   end Render_Variant_While_Guard_Image;

   procedure Append_Counted_While_Lower_Bound_Invariant
     (Buffer   : in out SU.Unbounded_String;
      Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      State    : Emit_State;
      Stmt     : CM.Statement;
      Depth    : Natural)
   is
      type Counter_Write_Analysis is record
         Count  : Natural := 0;
         Unsafe : Boolean := False;
      end record;

      function Is_Counter_Ident
        (Expr         : CM.Expr_Access;
         Counter_Name : String) return Boolean is
      begin
         return
           Expr /= null
           and then Expr.Kind = CM.Expr_Ident
           and then FT.To_String (Expr.Name) = Counter_Name;
      end Is_Counter_Ident;

      function Expr_Contains_Call (Expr : CM.Expr_Access) return Boolean is
      begin
         if Expr = null then
            return False;
         end if;

         case Expr.Kind is
            when CM.Expr_Call =>
               return True;
            when CM.Expr_Select =>
               return Expr_Contains_Call (Expr.Prefix);
            when CM.Expr_Resolved_Index =>
               if Expr_Contains_Call (Expr.Prefix) then
                  return True;
               end if;
               for Item of Expr.Args loop
                  if Expr_Contains_Call (Item) then
                     return True;
                  end if;
               end loop;
               return False;
            when CM.Expr_Conversion | CM.Expr_Annotated | CM.Expr_Unary =>
               return
                 Expr_Contains_Call (Expr.Inner)
                 or else Expr_Contains_Call (Expr.Target);
            when CM.Expr_Binary =>
               return
                 Expr_Contains_Call (Expr.Left)
                 or else Expr_Contains_Call (Expr.Right);
            when CM.Expr_Allocator | CM.Expr_Some | CM.Expr_Try =>
               return Expr_Contains_Call (Expr.Value);
            when CM.Expr_Aggregate =>
               for Field of Expr.Fields loop
                  if Expr_Contains_Call (Field.Expr) then
                     return True;
                  end if;
               end loop;
               return False;
            when CM.Expr_Array_Literal | CM.Expr_Tuple =>
               for Item of Expr.Elements loop
                  if Expr_Contains_Call (Item) then
                     return True;
                  end if;
               end loop;
               return False;
            when others =>
               return False;
         end case;
      end Expr_Contains_Call;

      function Is_Positive_Static_Offset
        (Expr         : CM.Expr_Access;
         Counter_Name : String) return Boolean
      is
         Value : Long_Long_Integer := 0;
      begin
         return
           Expr /= null
           and then not Expr_Uses_Name (Expr, Counter_Name)
           and then Try_Tracked_Static_Integer_Value (State, Expr, Value)
           and then Value > 0;
      end Is_Positive_Static_Offset;

      function Is_Positive_Self_Increment
        (Expr         : CM.Expr_Access;
         Counter_Name : String) return Boolean
      is
      begin
         if Expr = null
           or else Expr.Kind /= CM.Expr_Binary
           or else Map_Operator (FT.To_String (Expr.Operator)) /= "+"
         then
            return False;
         end if;

         return
           (Is_Counter_Ident (Expr.Left, Counter_Name)
            and then Is_Positive_Static_Offset (Expr.Right, Counter_Name))
           or else
           (Is_Counter_Ident (Expr.Right, Counter_Name)
            and then Is_Positive_Static_Offset (Expr.Left, Counter_Name));
      end Is_Positive_Self_Increment;

      function Declarations_Contain_Name
        (Declarations : CM.Object_Decl_Vectors.Vector;
         Name         : String) return Boolean
      is
      begin
         for Decl of Declarations loop
            for Decl_Name of Decl.Names loop
               if FT.To_String (Decl_Name) = Name then
                  return True;
               end if;
            end loop;
         end loop;
         return False;
      end Declarations_Contain_Name;

      procedure Analyze_Statements
        (Statements   : CM.Statement_Access_Vectors.Vector;
         Counter_Name : String;
         Analysis     : in out Counter_Write_Analysis);

      procedure Analyze_Statement
        (Item         : CM.Statement_Access;
         Counter_Name : String;
         Analysis     : in out Counter_Write_Analysis)
      is
      begin
         if Item = null then
            return;
         elsif Declarations_Contain_Name (Item.Declarations, Counter_Name) then
            Analysis.Unsafe := True;
            return;
         end if;

         case Item.Kind is
            when CM.Stmt_Assign =>
               if Expr_Contains_Call (Item.Target)
                 or else Expr_Contains_Call (Item.Value)
               then
                  Analysis.Unsafe := True;
               elsif Root_Name (Item.Target) = Counter_Name then
                  Analysis.Count := Analysis.Count + 1;
                  if not Is_Positive_Self_Increment (Item.Value, Counter_Name) then
                     Analysis.Unsafe := True;
                  end if;
               end if;

            when CM.Stmt_Object_Decl =>
               if Expr_Contains_Call (Item.Decl.Initializer) then
                  Analysis.Unsafe := True;
               end if;
               for Decl_Name of Item.Decl.Names loop
                  if FT.To_String (Decl_Name) = Counter_Name then
                     Analysis.Unsafe := True;
                  end if;
               end loop;

            when CM.Stmt_Destructure_Decl =>
               if Expr_Contains_Call (Item.Destructure.Initializer) then
                  Analysis.Unsafe := True;
               end if;
               for Decl_Name of Item.Destructure.Names loop
                  if FT.To_String (Decl_Name) = Counter_Name then
                     Analysis.Unsafe := True;
                  end if;
               end loop;

            when CM.Stmt_Call =>
               Analysis.Unsafe := True;

            when CM.Stmt_If =>
               if Expr_Contains_Call (Item.Condition) then
                  Analysis.Unsafe := True;
                  return;
               end if;
               Analyze_Statements (Item.Then_Stmts, Counter_Name, Analysis);
               for Part of Item.Elsifs loop
                  if Expr_Contains_Call (Part.Condition) then
                     Analysis.Unsafe := True;
                     return;
                  end if;
                  Analyze_Statements (Part.Statements, Counter_Name, Analysis);
               end loop;
               if Item.Has_Else then
                  Analyze_Statements (Item.Else_Stmts, Counter_Name, Analysis);
               end if;

            when CM.Stmt_Case =>
               if Expr_Contains_Call (Item.Case_Expr) then
                  Analysis.Unsafe := True;
                  return;
               end if;
               for Arm of Item.Case_Arms loop
                  if Expr_Contains_Call (Arm.Choice) then
                     Analysis.Unsafe := True;
                     return;
                  end if;
                  Analyze_Statements (Arm.Statements, Counter_Name, Analysis);
               end loop;

            when CM.Stmt_Match =>
               if Expr_Contains_Call (Item.Match_Expr) then
                  Analysis.Unsafe := True;
                  return;
               end if;
               for Arm of Item.Match_Arms loop
                  Analyze_Statements (Arm.Statements, Counter_Name, Analysis);
               end loop;

            when CM.Stmt_Select =>
               for Arm of Item.Arms loop
                  case Arm.Kind is
                     when CM.Select_Arm_Channel =>
                        if FT.To_String (Arm.Channel_Data.Variable_Name) = Counter_Name
                          or else Expr_Uses_Name
                            (Arm.Channel_Data.Channel_Name, Counter_Name)
                          or else Expr_Contains_Call
                            (Arm.Channel_Data.Channel_Name)
                        then
                           Analysis.Unsafe := True;
                           return;
                        end if;
                        Analyze_Statements
                          (Arm.Channel_Data.Statements, Counter_Name, Analysis);
                     when CM.Select_Arm_Delay =>
                        if Expr_Uses_Name
                          (Arm.Delay_Data.Duration_Expr, Counter_Name)
                          or else Expr_Contains_Call
                            (Arm.Delay_Data.Duration_Expr)
                        then
                           Analysis.Unsafe := True;
                           return;
                        end if;
                        Analyze_Statements
                          (Arm.Delay_Data.Statements, Counter_Name, Analysis);
                     when others =>
                        null;
                  end case;
               end loop;

            when CM.Stmt_Send | CM.Stmt_Receive | CM.Stmt_Try_Receive =>
               if Expr_Uses_Name (Item.Channel_Name, Counter_Name)
                 or else Expr_Uses_Name (Item.Value, Counter_Name)
                 or else Expr_Uses_Name (Item.Target, Counter_Name)
                 or else Expr_Uses_Name (Item.Success_Var, Counter_Name)
                 or else Expr_Contains_Call (Item.Channel_Name)
                 or else Expr_Contains_Call (Item.Value)
                 or else Expr_Contains_Call (Item.Target)
                 or else Expr_Contains_Call (Item.Success_Var)
               then
                  Analysis.Unsafe := True;
               end if;

            when CM.Stmt_Try_Send =>
               Analysis.Unsafe := True;

            when CM.Stmt_While | CM.Stmt_Loop =>
               if Expr_Contains_Call (Item.Condition) then
                  Analysis.Unsafe := True;
                  return;
               end if;
               declare
                  Nested : Counter_Write_Analysis;
               begin
                  Analyze_Statements (Item.Body_Stmts, Counter_Name, Nested);
                  if Nested.Count > 0 or else Nested.Unsafe then
                     Analysis.Unsafe := True;
                  end if;
               end;

            when CM.Stmt_For =>
               if FT.To_String (Item.Loop_Var) = Counter_Name then
                  Analysis.Unsafe := True;
               elsif Expr_Contains_Call (Item.Loop_Range.Name_Expr)
                 or else Expr_Contains_Call (Item.Loop_Range.Low_Expr)
                 or else Expr_Contains_Call (Item.Loop_Range.High_Expr)
                 or else Expr_Contains_Call (Item.Loop_Iterable)
               then
                  Analysis.Unsafe := True;
               else
                  declare
                     Nested : Counter_Write_Analysis;
                  begin
                     Analyze_Statements (Item.Body_Stmts, Counter_Name, Nested);
                     if Nested.Count > 0 or else Nested.Unsafe then
                        Analysis.Unsafe := True;
                     end if;
                  end;
               end if;

            when others =>
               if Expr_Contains_Call (Item.Value)
                 or else Expr_Contains_Call (Item.Condition)
               then
                  Analysis.Unsafe := True;
               end if;
         end case;
      end Analyze_Statement;

      procedure Analyze_Statements
        (Statements   : CM.Statement_Access_Vectors.Vector;
         Counter_Name : String;
         Analysis     : in out Counter_Write_Analysis)
      is
      begin
         for Item of Statements loop
            Analyze_Statement (Item, Counter_Name, Analysis);
            exit when Analysis.Unsafe;
         end loop;
      end Analyze_Statements;

      Entry_Value : Long_Long_Integer := 0;
   begin
      if Stmt.Condition = null
        or else Stmt.Condition.Kind /= CM.Expr_Binary
        or else Map_Operator (FT.To_String (Stmt.Condition.Operator)) not in "<" | "<="
        or else Stmt.Condition.Left = null
        or else Stmt.Condition.Left.Kind /= CM.Expr_Ident
        or else Stmt.Condition.Right = null
      then
         return;
      end if;

      declare
         Counter_Name : constant String := FT.To_String (Stmt.Condition.Left.Name);
         Analysis     : Counter_Write_Analysis;
      begin
         if Counter_Name'Length = 0
           or else Expr_Uses_Name (Stmt.Condition.Right, Counter_Name)
           or else Expr_Contains_Call (Stmt.Condition.Right)
           or else not Has_Text (Stmt.Condition.Left.Type_Name)
           or else
             not Is_Integer_Type
               (Unit, Document, FT.To_String (Stmt.Condition.Left.Type_Name))
           or else not Try_Loop_Integer_Binding (State, Counter_Name, Entry_Value)
         then
            return;
         end if;

         Analyze_Statements (Stmt.Body_Stmts, Counter_Name, Analysis);
         if Analysis.Unsafe or else Analysis.Count /= 1 then
            return;
         end if;

         Append_Line
           (Buffer,
            "pragma Loop_Invariant ("
            & Counter_Name
            & " >= "
            & Trim_Image (Entry_Value)
            & ");",
            Depth);
      end;
   end Append_Counted_While_Lower_Bound_Invariant;

   function Shared_Field_Getter_Call_Info
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access) return Shared_Field_Getter_Info
   is
      Callee_Key : constant String :=
        (if Expr = null
          or else Expr.Kind /= CM.Expr_Call
          or else Expr.Callee = null
         then ""
         else FT.Lowercase (CM.Flatten_Name (Expr.Callee)));

      function Info_For
        (Root_Key     : String;
         Call_Image   : String;
         Type_Info    : GM.Type_Descriptor;
         Init_Image   : String;
         Field_Name   : String) return Shared_Field_Getter_Info
      is
      begin
         return
           (Found               => True,
            Root_Key            => FT.To_UString (Root_Key),
            Call_Image          => FT.To_UString (Call_Image),
            Snapshot_Type_Image => FT.To_UString (Render_Type_Name (Type_Info)),
            Snapshot_Init_Image => FT.To_UString (Init_Image),
            Field_Ada_Name      => FT.To_UString (Ada_Safe_Name (Field_Name)));
      end Info_For;

      function Match_Local
        (Decl      : CM.Resolved_Object_Decl;
         Is_Public : Boolean) return Shared_Field_Getter_Info
      is
      begin
         if not Decl.Is_Shared
           or else Decl.Names.Is_Empty
           or else Decl.Is_Public /= Is_Public
         then
            return (others => <>);
         end if;

         declare
            Root_Name : constant String :=
              FT.To_String (Decl.Names (Decl.Names.First_Index));
            Root_Type : constant GM.Type_Descriptor :=
              Base_Type (Unit, Document, Decl.Type_Info);
         begin
            for Field of Root_Type.Fields loop
               declare
                  Field_Name  : constant String := FT.To_String (Field.Name);
                  Getter_Name : constant String := Shared_Field_Getter_Name (Field_Name);
                  Expected_Image : constant String :=
                    (if Is_Public
                     then Shared_Public_Helper_Name (Root_Name, Getter_Name)
                     else Shared_Wrapper_Object_Name (Root_Name) & "." & Getter_Name);
                  Expected       : constant String := FT.Lowercase (Expected_Image);
               begin
                  if Callee_Key = Expected then
                     return
                       Info_For
                         (Root_Key   =>
                            (if Is_Public then "public:" else "private:")
                            & FT.Lowercase (Root_Name),
                          Call_Image => Expected_Image,
                          Type_Info  => Decl.Type_Info,
                          Init_Image =>
                            (if Is_Public
                             then Shared_Public_Helper_Name (Root_Name, Shared_Get_All_Name)
                             else Shared_Wrapper_Object_Name (Root_Name)
                                  & "."
                                  & Shared_Get_All_Name),
                          Field_Name => Field_Name);
                  end if;
               end;
            end loop;
         end;

         return (others => <>);
      end Match_Local;

      function Match_Imported
        (Decl : CM.Imported_Object_Decl) return Shared_Field_Getter_Info
      is
         Full_Name : constant String := FT.To_String (Decl.Name);
         Dot_Index : Natural := 0;
      begin
         if not Decl.Is_Shared or else Full_Name'Length = 0 then
            return (others => <>);
         end if;

         for Index in reverse Full_Name'Range loop
            if Full_Name (Index) = '.' then
               Dot_Index := Index;
               exit;
            end if;
         end loop;

         if Dot_Index = 0
           or else Dot_Index = Full_Name'First
           or else Dot_Index = Full_Name'Last
         then
            return (others => <>);
         end if;

         declare
            Package_Name : constant String :=
              Full_Name (Full_Name'First .. Dot_Index - 1);
            Root_Name    : constant String :=
              Full_Name (Dot_Index + 1 .. Full_Name'Last);
            Root_Type    : constant GM.Type_Descriptor :=
              Base_Type (Unit, Document, Decl.Type_Info);
         begin
            for Field of Root_Type.Fields loop
               declare
                  Field_Name  : constant String := FT.To_String (Field.Name);
                  Getter_Name : constant String := Shared_Field_Getter_Name (Field_Name);
                  Expected_Image : constant String :=
                    Package_Name
                    & "."
                    & Shared_Public_Helper_Name (Root_Name, Getter_Name);
                  Expected       : constant String := FT.Lowercase (Expected_Image);
               begin
                  if Callee_Key = Expected then
                     return
                       Info_For
                         (Root_Key   => "imported:" & FT.Lowercase (Full_Name),
                          Call_Image => Expected_Image,
                          Type_Info  => Decl.Type_Info,
                          Init_Image =>
                            Package_Name
                            & "."
                            & Shared_Public_Helper_Name (Root_Name, Shared_Get_All_Name),
                          Field_Name => Field_Name);
                  end if;
               end;
            end loop;
         end;

         return (others => <>);
      end Match_Imported;
   begin
      if Callee_Key'Length = 0 then
         return (others => <>);
      end if;

      for Decl of Unit.Objects loop
         declare
            Private_Info : constant Shared_Field_Getter_Info :=
              Match_Local (Decl, Is_Public => False);
            Public_Info  : constant Shared_Field_Getter_Info :=
              Match_Local (Decl, Is_Public => True);
         begin
            if Private_Info.Found then
               return Private_Info;
            elsif Public_Info.Found then
               return Public_Info;
            end if;
         end;
      end loop;

      for Decl of Unit.Imported_Objects loop
         declare
            Imported_Info : constant Shared_Field_Getter_Info := Match_Imported (Decl);
         begin
            if Imported_Info.Found then
               return Imported_Info;
            end if;
         end;
      end loop;

      return (others => <>);
   end Shared_Field_Getter_Call_Info;

   function Expr_Needs_Shared_Condition_Snapshot
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access) return Boolean
   is
   begin
      if Expr = null then
         return False;
      elsif Shared_Field_Getter_Call_Info (Unit, Document, Expr).Found then
         return True;
      end if;

      case Expr.Kind is
         when CM.Expr_Call =>
            if Expr_Needs_Shared_Condition_Snapshot (Unit, Document, Expr.Callee) then
               return True;
            end if;
            for Arg of Expr.Args loop
               if Expr_Needs_Shared_Condition_Snapshot (Unit, Document, Arg) then
                  return True;
               end if;
            end loop;
            return False;
         when CM.Expr_Select =>
            return Expr_Needs_Shared_Condition_Snapshot (Unit, Document, Expr.Prefix);
         when CM.Expr_Resolved_Index =>
            if Expr_Needs_Shared_Condition_Snapshot (Unit, Document, Expr.Prefix) then
               return True;
            end if;
            for Arg of Expr.Args loop
               if Expr_Needs_Shared_Condition_Snapshot (Unit, Document, Arg) then
                  return True;
               end if;
            end loop;
            return False;
         when CM.Expr_Conversion | CM.Expr_Annotated =>
            return
              Expr_Needs_Shared_Condition_Snapshot (Unit, Document, Expr.Inner)
              or else Expr_Needs_Shared_Condition_Snapshot (Unit, Document, Expr.Target);
         when CM.Expr_Unary | CM.Expr_Some | CM.Expr_Try =>
            return Expr_Needs_Shared_Condition_Snapshot (Unit, Document, Expr.Inner);
         when CM.Expr_Binary =>
            return
              Expr_Needs_Shared_Condition_Snapshot (Unit, Document, Expr.Left)
              or else Expr_Needs_Shared_Condition_Snapshot (Unit, Document, Expr.Right);
         when CM.Expr_Allocator =>
            return Expr_Needs_Shared_Condition_Snapshot (Unit, Document, Expr.Value);
         when CM.Expr_Aggregate =>
            for Field of Expr.Fields loop
               if Expr_Needs_Shared_Condition_Snapshot (Unit, Document, Field.Expr) then
                  return True;
               end if;
            end loop;
            return False;
         when CM.Expr_Array_Literal | CM.Expr_Tuple =>
            for Item of Expr.Elements loop
               if Expr_Needs_Shared_Condition_Snapshot (Unit, Document, Item) then
                  return True;
               end if;
            end loop;
            return False;
         when others =>
            return False;
      end case;
   end Expr_Needs_Shared_Condition_Snapshot;

   function Shared_Condition_Snapshot_Name
     (Info            : Shared_Field_Getter_Info;
      Statement_Index : Positive;
      Snapshots       : in out Shared_Condition_Snapshot_Vectors.Vector) return String
   is
   begin
      for Snapshot of Snapshots loop
         if Snapshot.Root_Key = Info.Root_Key then
            return FT.To_String (Snapshot.Snapshot_Name);
         end if;
      end loop;

      declare
         Name : constant String :=
           "Safe_Shared_Condition_"
           & Ada.Strings.Fixed.Trim (Positive'Image (Statement_Index), Ada.Strings.Both)
           & "_"
           & Ada.Strings.Fixed.Trim
               (Positive'Image (Positive (Natural (Snapshots.Length) + 1)), Ada.Strings.Both);
      begin
         Snapshots.Append
           ((Root_Key            => Info.Root_Key,
             Snapshot_Name       => FT.To_UString (Name),
             Snapshot_Type_Image => Info.Snapshot_Type_Image,
             Snapshot_Init_Image => Info.Snapshot_Init_Image));
         return Name;
      end;
   end Shared_Condition_Snapshot_Name;

   procedure Collect_Shared_Condition_Snapshots
     (Unit            : CM.Resolved_Unit;
      Document        : GM.Mir_Document;
      Expr            : CM.Expr_Access;
      Statement_Index : Positive;
      Rendered        : in out Shared_Condition_Render)
   is
   begin
      if Expr = null then
         return;
      end if;

      declare
         Info : constant Shared_Field_Getter_Info :=
           Shared_Field_Getter_Call_Info (Unit, Document, Expr);
      begin
         if Info.Found then
            declare
               Snapshot_Name : constant String :=
                 Shared_Condition_Snapshot_Name
                   (Info, Statement_Index, Rendered.Snapshots);
            begin
               Rendered.Replacements.Append
                 ((Call_Image => Info.Call_Image,
                   Replacement_Image =>
                     FT.To_UString
                       (Snapshot_Name & "." & FT.To_String (Info.Field_Ada_Name))));
            end;
         end if;
      end;

      case Expr.Kind is
         when CM.Expr_Call =>
            Collect_Shared_Condition_Snapshots
              (Unit, Document, Expr.Callee, Statement_Index, Rendered);
            for Arg of Expr.Args loop
               Collect_Shared_Condition_Snapshots
                 (Unit, Document, Arg, Statement_Index, Rendered);
            end loop;
         when CM.Expr_Select =>
            Collect_Shared_Condition_Snapshots
              (Unit, Document, Expr.Prefix, Statement_Index, Rendered);
         when CM.Expr_Resolved_Index =>
            Collect_Shared_Condition_Snapshots
              (Unit, Document, Expr.Prefix, Statement_Index, Rendered);
            for Arg of Expr.Args loop
               Collect_Shared_Condition_Snapshots
                 (Unit, Document, Arg, Statement_Index, Rendered);
            end loop;
         when CM.Expr_Conversion | CM.Expr_Annotated =>
            Collect_Shared_Condition_Snapshots
              (Unit, Document, Expr.Inner, Statement_Index, Rendered);
            Collect_Shared_Condition_Snapshots
              (Unit, Document, Expr.Target, Statement_Index, Rendered);
         when CM.Expr_Unary | CM.Expr_Some | CM.Expr_Try =>
            Collect_Shared_Condition_Snapshots
              (Unit, Document, Expr.Inner, Statement_Index, Rendered);
         when CM.Expr_Binary =>
            Collect_Shared_Condition_Snapshots
              (Unit, Document, Expr.Left, Statement_Index, Rendered);
            Collect_Shared_Condition_Snapshots
              (Unit, Document, Expr.Right, Statement_Index, Rendered);
         when CM.Expr_Allocator =>
            Collect_Shared_Condition_Snapshots
              (Unit, Document, Expr.Value, Statement_Index, Rendered);
         when CM.Expr_Aggregate =>
            for Field of Expr.Fields loop
               Collect_Shared_Condition_Snapshots
                 (Unit, Document, Field.Expr, Statement_Index, Rendered);
            end loop;
         when CM.Expr_Array_Literal | CM.Expr_Tuple =>
            for Item of Expr.Elements loop
               Collect_Shared_Condition_Snapshots
                 (Unit, Document, Item, Statement_Index, Rendered);
            end loop;
         when others =>
            null;
      end case;
   end Collect_Shared_Condition_Snapshots;

   function Replace_All
     (Text : String;
      From : String;
      To   : String) return String
   is
      Result : SU.Unbounded_String := SU.Null_Unbounded_String;
      Cursor : Natural := Text'First;

      function Is_Ada_Name_Character (Item : Character) return Boolean is
      begin
         return Item in 'A' .. 'Z'
           or else Item in 'a' .. 'z'
           or else Item in '0' .. '9'
           or else Item = '_';
      end Is_Ada_Name_Character;

      function Has_Name_Boundaries (Position : Positive) return Boolean is
         After : constant Natural := Position + From'Length;
      begin
         return
           (Position = Text'First
            or else
              (Text (Position - 1) /= '.'
               and then not Is_Ada_Name_Character (Text (Position - 1))))
           and then
             (After > Text'Last
              or else not Is_Ada_Name_Character (Text (After)));
      end Has_Name_Boundaries;
   begin
      if From'Length = 0 then
         return Text;
      end if;

      while Cursor <= Text'Last loop
         declare
            Pos : constant Natural :=
              Ada.Strings.Fixed.Index (Text, From, From => Positive (Cursor));
         begin
            if Pos = 0 then
               Result := Result & SU.To_Unbounded_String (Text (Cursor .. Text'Last));
               Cursor := Text'Last + 1;
            elsif Has_Name_Boundaries (Pos) then
               if Pos > Cursor then
                  Result := Result & SU.To_Unbounded_String (Text (Cursor .. Pos - 1));
               end if;
               Result := Result & SU.To_Unbounded_String (To);
               Cursor := Pos + From'Length;
            else
               Result := Result & SU.To_Unbounded_String (Text (Cursor .. Pos));
               Cursor := Pos + 1;
            end if;
         end;
      end loop;

      return SU.To_String (Result);
   end Replace_All;

   function Render_Shared_Condition
     (Unit            : CM.Resolved_Unit;
      Document        : GM.Mir_Document;
      Expr            : CM.Expr_Access;
      State           : in out Emit_State;
      Statement_Index : Positive) return Shared_Condition_Render
   is
      Result : Shared_Condition_Render;
      Image  : SU.Unbounded_String;
   begin
      Collect_Shared_Condition_Snapshots
        (Unit, Document, Expr, Statement_Index, Result);
      Image := SU.To_Unbounded_String (Render_Expr (Unit, Document, Expr, State));

      for Replacement of Result.Replacements loop
         Image :=
           SU.To_Unbounded_String
             (Replace_All
                (SU.To_String (Image),
                 FT.To_String (Replacement.Call_Image),
                 FT.To_String (Replacement.Replacement_Image)));
      end loop;

      Result.Image := FT.To_UString (SU.To_String (Image));
      return Result;
   end Render_Shared_Condition;

   procedure Append_Shared_Condition_Declarations
     (Buffer   : in out SU.Unbounded_String;
      Rendered : Shared_Condition_Render;
      Depth    : Natural)
   is
   begin
      for Snapshot of Rendered.Snapshots loop
         Append_Line
           (Buffer,
            FT.To_String (Snapshot.Snapshot_Name)
            & " : constant "
            & FT.To_String (Snapshot.Snapshot_Type_Image)
            & " := "
            & FT.To_String (Snapshot.Snapshot_Init_Image)
            & ";",
            Depth);
      end loop;
   end Append_Shared_Condition_Declarations;

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
      In_Loop    : Boolean := False)
   is
      function Channel_Item
        (Channel_Expr : CM.Expr_Access) return CM.Resolved_Channel_Decl is
      begin
         if Channel_Expr = null then
            return (others => <>);
         end if;
         return Lookup_Channel (Unit, CM.Flatten_Name (Channel_Expr));
      end Channel_Item;
   begin
      if Statements.Is_Empty then
         return;
      end if;

      for Index in Statements.First_Index .. Statements.Last_Index loop
         declare
            Item : constant CM.Statement_Access := Statements (Index);
         begin
            if Item = null then
               Raise_Unsupported
                 (State,
                  FT.Null_Span,
                  "encountered null statement during Ada emission");
            end if;

            Append_Source_Comment
              (Buffer,
               FT.To_String (Unit.Path),
               Item.Span,
               Depth);

            case Item.Kind is
            when CM.Stmt_Object_Decl =>
               declare
                  Tail                : constant CM.Statement_Access_Vectors.Vector :=
                    Tail_Statements (Statements, Index + 1);
                  Previous_Wide_Count : constant Ada.Containers.Count_Type :=
                    State.Wide_Local_Names.Length;
                  Previous_Loop_Integer_Count : constant Ada.Containers.Count_Type :=
                    State.Loop_Integer_Bindings.Length;
                  Block_Declarations  : CM.Object_Decl_Vectors.Vector;
                  Suppress_Initialization_Warnings : Boolean := False;
                  Static_Value        : Long_Long_Integer := 0;
               begin
                  Block_Declarations.Append (Item.Decl);
                  Suppress_Initialization_Warnings :=
                    State.Task_Body_Depth > 0
                    or else Block_Declarations_Immediately_Overwritten
                      (Block_Declarations, Tail);
                  Collect_Wide_Locals
                    (Unit,
                     Document,
                     State,
                     Block_Declarations,
                     Tail);
                  Push_Type_Binding_Frame (State);
                  Register_Type_Bindings (State, Block_Declarations);
                  Push_Cleanup_Frame (State);
                  Register_Cleanup_Items (State, Block_Declarations);
                  Append_Line (Buffer, "declare", Depth);
                  if Suppress_Initialization_Warnings then
                     Append_Initialization_Warning_Suppression
                       (Buffer, Depth + 1);
                  end if;
                  Append_Line
                    (Buffer,
                     Render_Object_Decl_Text (Unit, Document, State, Item.Decl, Local_Context => True),
                     Depth + 1);
                  if Item.Decl.Has_Initializer
                    and then Item.Decl.Initializer /= null
                    and then Is_Integer_Type (Unit, Document, Item.Decl.Type_Info)
                    and then Try_Tracked_Static_Integer_Value
                      (State, Item.Decl.Initializer, Static_Value)
                  then
                     for Name of Item.Decl.Names loop
                        Bind_Loop_Integer (State, FT.To_String (Name), Static_Value);
                     end loop;
                  end if;
                  if Suppress_Initialization_Warnings then
                     Append_Initialization_Warning_Restore
                       (Buffer, Depth + 1);
                  end if;
                  Append_Line (Buffer, "begin", Depth);
                  Render_Required_Statement_Suite
                    (Buffer,
                     Unit,
                     Document,
                     Tail,
                     State,
                     Depth + 1,
                     Return_Type,
                     In_Loop);
                  if Tail.Is_Empty or else Statements_Fall_Through (Tail) then
                     Render_Cleanup (Buffer, Block_Declarations, Depth + 1);
                  end if;
                  Append_Line (Buffer, "end;", Depth);
                  Pop_Cleanup_Frame (State);
                  Pop_Type_Binding_Frame (State);
                  Restore_Loop_Integer_Bindings (State, Previous_Loop_Integer_Count);
                  Restore_Wide_Names (State, Previous_Wide_Count);
               end;
               return;
            when CM.Stmt_Destructure_Decl =>
               declare
                  Tail                : constant CM.Statement_Access_Vectors.Vector :=
                    Tail_Statements (Statements, Index + 1);
                  Previous_Wide_Count : constant Ada.Containers.Count_Type :=
                    State.Wide_Local_Names.Length;
                  Empty_Declarations  : CM.Object_Decl_Vectors.Vector;
                  Tuple_Type          : constant GM.Type_Descriptor :=
                    Base_Type (Unit, Document, Item.Destructure.Type_Info);
                  Temp_Name           : constant String :=
                    "Safe_Destructure_"
                    & Ada.Strings.Fixed.Trim (Natural'Image (Index), Ada.Strings.Both);
               begin
                  Collect_Wide_Locals
                    (Unit,
                     Document,
                     State,
                     Empty_Declarations,
                     Tail_Statements (Statements, Index));
                  Push_Type_Binding_Frame (State);
                  Push_Cleanup_Frame (State);
                  Append_Line (Buffer, "declare", Depth);
                  Append_Line
                    (Buffer,
                     Temp_Name
                     & " : "
                     & Render_Type_Name (Item.Destructure.Type_Info)
                     & " := "
                     & Render_Expr
                         (Unit,
                          Document,
                          Item.Destructure.Initializer,
                          State)
                     & ";",
                     Depth + 1);
                  for Tuple_Index in Item.Destructure.Names.First_Index .. Item.Destructure.Names.Last_Index loop
                     Append_Line
                        (Buffer,
                         FT.To_String (Item.Destructure.Names (Tuple_Index))
                         & " : "
                         & Render_Type_Name
                             (Unit,
                             Document,
                             FT.To_String (Tuple_Type.Tuple_Element_Types (Tuple_Index)))
                        & " := "
                        & Temp_Name
                             & "."
                             & Tuple_Field_Name (Positive (Tuple_Index))
                             & ";",
                        Depth + 1);
                     declare
                        Element_Type : GM.Type_Descriptor;
                     begin
                        if Type_Info_From_Name
                             (Unit,
                              Document,
                              FT.To_String (Tuple_Type.Tuple_Element_Types (Tuple_Index)),
                              Element_Type)
                        then
                           Add_Type_Binding
                             (State,
                              FT.To_String (Item.Destructure.Names (Tuple_Index)),
                              Element_Type);
                        end if;
                     end;
                  end loop;
                  Append_Line (Buffer, "begin", Depth);
                  Render_Required_Statement_Suite
                    (Buffer,
                     Unit,
                     Document,
                     Tail,
                     State,
                     Depth + 1,
                     Return_Type,
                     In_Loop);
                  Append_Line (Buffer, "end;", Depth);
                  Pop_Cleanup_Frame (State);
                  Pop_Type_Binding_Frame (State);
                  Restore_Wide_Names (State, Previous_Wide_Count);
               end;
               return;
            when CM.Stmt_Assign =>
               if State.Task_Body_Depth > 0 then
                  Append_Task_Assignment_Warning_Suppression (Buffer, Depth);
               end if;
               Append_Assignment (Buffer, Unit, Document, State, Item.all, Depth, In_Loop);
               if In_Loop then
                  Append_Integer_Loop_Invariant
                    (Buffer, Unit, Document, State, Item.Target, Depth);
                  Append_Float_Loop_Invariant
                    (Buffer, Unit, Document, State, Item.Target, Depth);
               end if;
               if State.Task_Body_Depth > 0 then
                  Append_Task_Assignment_Warning_Restore (Buffer, Depth);
               end if;
            when CM.Stmt_Call =>
               if Is_Print_Call (Item.Call) then
                  State.Needs_Safe_IO := True;
                  Append_Line
                    (Buffer,
                     "IO.Put_Line ("
                     & Render_Print_Argument
                         (Unit,
                          Document,
                         Item.Call.Args (Item.Call.Args.First_Index),
                          State)
                     & ");",
                     Depth);
               else
                  Emit_Call_Statement
                    (Buffer, Unit, Document, Item.Call, Index, State, Depth);
               end if;
            when CM.Stmt_Return =>
               if Item.Value /= null and then Has_Active_Cleanup_Items (State) then
                  Append_Return_With_Cleanup
                    (Buffer,
                     Unit,
                     Document,
                     State,
                     Item.Value,
                     Return_Type,
                     Depth);
               else
                  Render_Active_Cleanup (Buffer, State, Depth);
                  Append_Return
                    (Buffer,
                     Unit,
                     Document,
                     State,
                     Item.Value,
                     Return_Type,
                     Depth);
               end if;
            when CM.Stmt_If =>
               declare
                  Previous_Static_Length_Count : constant Ada.Containers.Count_Type :=
                    State.Static_Length_Bindings.Length;
                  Previous_Static_Integer_Count : constant Ada.Containers.Count_Type :=
                    State.Static_Integer_Bindings.Length;
                  Previous_Loop_Integer_Count : constant Ada.Containers.Count_Type :=
                    State.Loop_Integer_Bindings.Length;
                  Previous_Static_String_Count : constant Ada.Containers.Count_Type :=
                    State.Static_String_Bindings.Length;

                  function Needs_Shared_Condition_Snapshot return Boolean is
                  begin
                     if Expr_Needs_Shared_Condition_Snapshot
                          (Unit, Document, Item.Condition)
                     then
                        return True;
                     end if;

                     for Part of Item.Elsifs loop
                        if Expr_Needs_Shared_Condition_Snapshot
                             (Unit, Document, Part.Condition)
                        then
                           return True;
                        end if;
                     end loop;

                     return False;
                  end Needs_Shared_Condition_Snapshot;

                  Arm_Count : constant Positive :=
                    Positive (Natural (Item.Elsifs.Length) + 1);

                  function Arm_Condition
                    (Arm_Number : Positive) return CM.Expr_Access
                  is
                  begin
                     if Arm_Number = 1 then
                        return Item.Condition;
                     end if;

                     return
                       Item.Elsifs
                         (Item.Elsifs.First_Index + Arm_Number - 2).Condition;
                  end Arm_Condition;

                  procedure Render_Arm_Statements
                    (Arm_Number  : Positive;
                     Suite_Depth : Natural)
                  is
                  begin
                     if Arm_Number = 1 then
                        Render_Required_Statement_Suite
                          (Buffer,
                           Unit,
                           Document,
                           Item.Then_Stmts,
                           State,
                           Suite_Depth,
                           Return_Type,
                           In_Loop);
                     else
                        Render_Required_Statement_Suite
                          (Buffer,
                           Unit,
                           Document,
                           Item.Elsifs
                             (Item.Elsifs.First_Index + Arm_Number - 2).Statements,
                           State,
                           Suite_Depth,
                           Return_Type,
                           In_Loop);
                     end if;
                  end Render_Arm_Statements;

                  procedure Restore_Static_Counts is
                  begin
                     Restore_Static_Length_Bindings (State, Previous_Static_Length_Count);
                     Restore_Static_Integer_Bindings (State, Previous_Static_Integer_Count);
                     Restore_Loop_Integer_Bindings (State, Previous_Loop_Integer_Count);
                     Restore_Static_String_Bindings (State, Previous_Static_String_Count);
                  end Restore_Static_Counts;

                  procedure Render_Snapshot_If_Arm
                    (Arm_Number : Positive;
                     Arm_Depth  : Natural)
                  is
                     Rendered : constant Shared_Condition_Render :=
                       Render_Shared_Condition
                         (Unit,
                          Document,
                          Arm_Condition (Arm_Number),
                          State,
                          Index);
                     Wrapped : constant Boolean := not Rendered.Snapshots.Is_Empty;
                     If_Depth : constant Natural :=
                       (if Wrapped then Arm_Depth + 1 else Arm_Depth);
                  begin
                     if Wrapped then
                        Append_Line (Buffer, "declare", Arm_Depth);
                        Append_Shared_Condition_Declarations
                          (Buffer, Rendered, Arm_Depth + 1);
                        Append_Line (Buffer, "begin", Arm_Depth);
                     end if;

                     Append_Line
                       (Buffer,
                        "if " & FT.To_String (Rendered.Image) & " then",
                        If_Depth);
                     Render_Arm_Statements (Arm_Number, If_Depth + 1);
                     Restore_Static_Counts;

                     if Arm_Number < Arm_Count then
                        Append_Line (Buffer, "else", If_Depth);
                        Render_Snapshot_If_Arm (Arm_Number + 1, If_Depth + 1);
                     elsif Item.Has_Else then
                        Append_Line (Buffer, "else", If_Depth);
                        Render_Required_Statement_Suite
                          (Buffer,
                           Unit,
                           Document,
                           Item.Else_Stmts,
                           State,
                           If_Depth + 1,
                           Return_Type,
                           In_Loop);
                        Restore_Static_Counts;
                     end if;

                     Append_Line (Buffer, "end if;", If_Depth);
                     if Wrapped then
                        Append_Line (Buffer, "end;", Arm_Depth);
                     end if;
                  end Render_Snapshot_If_Arm;
               begin
                  if State.Task_Body_Depth > 0 then
                     Append_Task_If_Warning_Suppression (Buffer, Depth);
                  end if;
                  if Item.Suppress_Local_Warnings then
                     Append_Gnatprove_Warning_Suppression
                       (Buffer,
                        "unused assignment",
                        "generated pop_last trim branch is guarded by static length facts",
                        Depth);
                     Append_Gnatprove_Warning_Suppression
                       (Buffer,
                        "statement has no effect",
                        "generated pop_last trim branch is guarded by static length facts",
                        Depth);
                  end if;

                  if Needs_Shared_Condition_Snapshot then
                     Render_Snapshot_If_Arm (1, Depth);
                  else
                     Append_Line
                       (Buffer,
                        "if " & Render_Expr (Unit, Document, Item.Condition, State) & " then",
                        Depth);
                     Render_Required_Statement_Suite
                       (Buffer, Unit, Document, Item.Then_Stmts, State, Depth + 1, Return_Type, In_Loop);
                     Restore_Static_Counts;
                     for Part of Item.Elsifs loop
                        Append_Line
                          (Buffer,
                           "elsif " & Render_Expr (Unit, Document, Part.Condition, State) & " then",
                           Depth);
                        Render_Required_Statement_Suite
                          (Buffer, Unit, Document, Part.Statements, State, Depth + 1, Return_Type, In_Loop);
                        Restore_Static_Counts;
                     end loop;
                     if Item.Has_Else then
                        Append_Line (Buffer, "else", Depth);
                        Render_Required_Statement_Suite
                          (Buffer, Unit, Document, Item.Else_Stmts, State, Depth + 1, Return_Type, In_Loop);
                        Restore_Static_Counts;
                     end if;
                     Append_Line (Buffer, "end if;", Depth);
                  end if;

                  if Item.Suppress_Local_Warnings then
                     Append_Gnatprove_Warning_Restore
                       (Buffer,
                        "statement has no effect",
                        Depth);
                     Append_Gnatprove_Warning_Restore
                       (Buffer,
                        "unused assignment",
                        Depth);
                  end if;
                  if State.Task_Body_Depth > 0 then
                     Append_Task_If_Warning_Restore (Buffer, Depth);
                  end if;
                  Clear_All_Static_Bindings (State);
               end;
            when CM.Stmt_Case =>
               declare
                  Case_Info : constant GM.Type_Descriptor :=
                    Base_Type (Unit, Document, Expr_Type_Info (Unit, Document, Item.Case_Expr));
               begin
                  if FT.Lowercase (FT.To_String (Case_Info.Kind)) = "string" then
                     declare
                        Case_Name : constant String :=
                          "Safe_String_Case_Expr_"
                          & Ada.Strings.Fixed.Trim (Positive'Image (Positive (Index)), Ada.Strings.Both);
                        Static_Case_Image : SU.Unbounded_String := SU.Null_Unbounded_String;
                        Matched_Arm_Index : Natural := 0;

                        procedure Select_Static_String_Case_Arm is
                           Choice_Image : SU.Unbounded_String := SU.Null_Unbounded_String;
                           Others_Index : Natural := 0;
                        begin
                           if not Try_Static_String_Image
                             (State,
                              Item.Case_Expr,
                              Static_Case_Image)
                           then
                              return;
                           end if;

                           for Arm_Index in Item.Case_Arms.First_Index .. Item.Case_Arms.Last_Index loop
                              declare
                                 Arm : constant CM.Case_Arm := Item.Case_Arms (Arm_Index);
                              begin
                                 if Arm.Is_Others then
                                    Others_Index := Natural (Arm_Index);
                                 elsif Try_Static_String_Image (State, Arm.Choice, Choice_Image)
                                   and then SU.To_String (Choice_Image) = SU.To_String (Static_Case_Image)
                                 then
                                    Matched_Arm_Index := Natural (Arm_Index);
                                    return;
                                 end if;
                              end;
                           end loop;

                           Matched_Arm_Index := Others_Index;
                        end Select_Static_String_Case_Arm;

                        First_String_Arm : Boolean := True;
                     begin
                        Select_Static_String_Case_Arm;
                        Append_Line (Buffer, "declare", Depth);
                        Append_Line
                          (Buffer,
                           Case_Name
                           & " : constant String := "
                           & Render_String_Expr (Unit, Document, Item.Case_Expr, State)
                           & ";",
                           Depth + 1);
                        Append_Line (Buffer, "begin", Depth);
                        if Matched_Arm_Index /= 0 then
                           Render_Required_Statement_Suite
                             (Buffer,
                              Unit,
                              Document,
                              Item.Case_Arms (Positive (Matched_Arm_Index)).Statements,
                              State,
                              Depth + 1,
                              Return_Type,
                              In_Loop);
                        else
                           declare
                              Previous_Static_Length_Count : constant Ada.Containers.Count_Type :=
                                State.Static_Length_Bindings.Length;
                              Previous_Static_Integer_Count : constant Ada.Containers.Count_Type :=
                                State.Static_Integer_Bindings.Length;
                              Previous_Loop_Integer_Count : constant Ada.Containers.Count_Type :=
                                State.Loop_Integer_Bindings.Length;
                              Previous_Static_String_Count : constant Ada.Containers.Count_Type :=
                                State.Static_String_Bindings.Length;
                           begin
                              for Arm of Item.Case_Arms loop
                                 if Arm.Is_Others then
                                    if First_String_Arm then
                                       Append_Line (Buffer, "if True then", Depth + 1);
                                       First_String_Arm := False;
                                    else
                                       Append_Line (Buffer, "else", Depth + 1);
                                    end if;
                                 elsif First_String_Arm then
                                    Append_Line
                                      (Buffer,
                                       "if "
                                       & Case_Name
                                       & " = "
                                       & Render_String_Expr (Unit, Document, Arm.Choice, State)
                                       & " then",
                                       Depth + 1);
                                    First_String_Arm := False;
                                 else
                                    Append_Line
                                      (Buffer,
                                       "elsif "
                                       & Case_Name
                                       & " = "
                                       & Render_String_Expr (Unit, Document, Arm.Choice, State)
                                       & " then",
                                       Depth + 1);
                                 end if;
                                 Render_Required_Statement_Suite
                                   (Buffer,
                                    Unit,
                                    Document,
                                    Arm.Statements,
                                    State,
                                    Depth + 2,
                                    Return_Type,
                                    In_Loop);
                                 Restore_Static_Length_Bindings (State, Previous_Static_Length_Count);
                                 Restore_Static_Integer_Bindings (State, Previous_Static_Integer_Count);
                                 Restore_Loop_Integer_Bindings (State, Previous_Loop_Integer_Count);
                                 Restore_Static_String_Bindings (State, Previous_Static_String_Count);
                              end loop;
                              Append_Line (Buffer, "end if;", Depth + 1);
                              Clear_All_Static_Bindings (State);
                           end;
                        end if;
                        Append_Line (Buffer, "end;", Depth);
                     end;
                  else
                     declare
                        Previous_Static_Length_Count : constant Ada.Containers.Count_Type :=
                          State.Static_Length_Bindings.Length;
                        Previous_Static_Integer_Count : constant Ada.Containers.Count_Type :=
                          State.Static_Integer_Bindings.Length;
                        Previous_Loop_Integer_Count : constant Ada.Containers.Count_Type :=
                          State.Loop_Integer_Bindings.Length;
                        Previous_Static_String_Count : constant Ada.Containers.Count_Type :=
                          State.Static_String_Bindings.Length;
                     begin
                        Append_Line
                          (Buffer,
                           "case " & Render_Expr (Unit, Document, Item.Case_Expr, State) & " is",
                           Depth);
                        for Arm of Item.Case_Arms loop
                           Append_Line
                             (Buffer,
                              (if Arm.Is_Others
                               then "when others =>"
                               else "when " & Render_Expr (Unit, Document, Arm.Choice, State) & " =>"),
                              Depth + 1);
                           Render_Required_Statement_Suite
                             (Buffer,
                              Unit,
                              Document,
                              Arm.Statements,
                              State,
                              Depth + 2,
                              Return_Type,
                              In_Loop);
                           Restore_Static_Length_Bindings (State, Previous_Static_Length_Count);
                           Restore_Static_Integer_Bindings (State, Previous_Static_Integer_Count);
                           Restore_Loop_Integer_Bindings (State, Previous_Loop_Integer_Count);
                           Restore_Static_String_Bindings (State, Previous_Static_String_Count);
                        end loop;
                        Append_Line (Buffer, "end case;", Depth);
                        Clear_All_Static_Bindings (State);
                     end;
                  end if;
               end;
            when CM.Stmt_While =>
               declare
                  Rendered : constant Shared_Condition_Render :=
                    Render_Shared_Condition (Unit, Document, Item.Condition, State, Index);
                  Variant_Image : constant String := Loop_Variant_Image (Unit, Document, Item.Condition, State);
                  Variant_Guard_Image : constant String :=
                    (if Variant_Image'Length > 0
                     then Render_Variant_While_Guard_Image
                       (Unit, Document, Item.Condition, Rendered, State)
                     else "");
                  --  Loop_Variant_Image only emits variants for binary guards
                  --  whose operators are also renderable here; otherwise a
                  --  fallback could silently re-open static-folded loop guards.
                  pragma Assert
                    (Variant_Image'Length = 0 or else Variant_Guard_Image'Length > 0);
                  Condition_Image : constant String :=
                    (if Variant_Guard_Image'Length > 0
                     then Variant_Guard_Image
                     else FT.To_String (Rendered.Image));
               begin
                  if Rendered.Snapshots.Is_Empty then
                     Append_Line
                       (Buffer,
                        "while " & Condition_Image & " loop",
                        Depth);
                     if Variant_Image'Length > 0 then
                        Append_Line (Buffer, "pragma Loop_Variant (" & Variant_Image & ");", Depth + 1);
                     end if;
                     Append_Counted_While_Lower_Bound_Invariant
                       (Buffer, Unit, Document, State, Item.all, Depth + 1);
                     Render_Required_Statement_Suite
                       (Buffer, Unit, Document, Item.Body_Stmts, State, Depth + 1, Return_Type, True);
                     Append_Line (Buffer, "end loop;", Depth);
                  else
                     Append_Line (Buffer, "loop", Depth);
                     if Variant_Image'Length > 0 then
                        Append_Line
                          (Buffer,
                           "pragma Loop_Variant (" & Variant_Image & ");",
                           Depth + 1);
                     end if;
                     Append_Counted_While_Lower_Bound_Invariant
                       (Buffer, Unit, Document, State, Item.all, Depth + 1);
                     Append_Line (Buffer, "declare", Depth + 1);
                     Append_Shared_Condition_Declarations
                       (Buffer, Rendered, Depth + 2);
                     Append_Line (Buffer, "begin", Depth + 1);
                     Append_Line
                       (Buffer,
                        "exit when not (" & Condition_Image & ");",
                        Depth + 2);
                     Append_Line (Buffer, "end;", Depth + 1);
                     Render_Required_Statement_Suite
                       (Buffer, Unit, Document, Item.Body_Stmts, State, Depth + 1, Return_Type, True);
                     Append_Line (Buffer, "end loop;", Depth);
                  end if;
               end;
            when CM.Stmt_For =>
               if Item.Loop_Iterable /= null then
                  declare
                     Iterable_Info : constant GM.Type_Descriptor :=
                       Base_Type (Unit, Document, Expr_Type_Info (Unit, Document, Item.Loop_Iterable));
                     Is_String_Iterable : constant Boolean :=
                       FT.Lowercase (FT.To_String (Iterable_Info.Kind)) = "string";
                     Plain_String_Iterable : constant Boolean :=
                       Is_String_Iterable
                       and then Is_Plain_String_Type (Unit, Document, Iterable_Info);
                     function One_Char_String_Info return GM.Type_Descriptor is
                        Found : Boolean := False;
                     begin
                        return Synthetic_Bounded_String_Type ("__bounded_string_1", Found);
                     end One_Char_String_Info;
                     Element_Info  : constant GM.Type_Descriptor :=
                       (if Is_String_Iterable
                        then One_Char_String_Info
                        else Resolve_Type_Name
                               (Unit,
                                Document,
                                FT.To_String (Iterable_Info.Component_Type)));
                     Needs_Composite_Heap_Helper : constant Boolean :=
                       not Is_String_Iterable
                       and then Needs_Generated_For_Of_Helper
                         (Unit, Document, Element_Info);
                     Snapshot_Name : constant String :=
                       "Safe_For_Of_Snapshot_"
                       & Ada.Strings.Fixed.Trim (Positive'Image (Positive (Index)), Ada.Strings.Both);
                     Index_Name    : constant String :=
                       "Safe_For_Of_Index_"
                       & Ada.Strings.Fixed.Trim (Positive'Image (Positive (Index)), Ada.Strings.Both);
                     Snapshot_Init : constant String :=
                       (if Plain_String_Iterable
                        then
                          "Safe_String_RT.To_String ("
                          & Render_Expr (Unit, Document, Item.Loop_Iterable, State)
                          & ")"
                        elsif Is_String_Iterable
                        then
                          Bounded_String_Instance_Name (Iterable_Info)
                          & ".To_String ("
                          & Render_Expr (Unit, Document, Item.Loop_Iterable, State)
                          & ")"
                        elsif Iterable_Info.Growable
                        then
                          Array_Runtime_Instance_Name (Iterable_Info)
                          & ".Clone ("
                          & Render_Expr (Unit, Document, Item.Loop_Iterable, State)
                          & ")"
                        else Render_Expr (Unit, Document, Item.Loop_Iterable, State));
                     Snapshot_Type_Image : constant String :=
                       (if Is_String_Iterable then "String"
                        else Render_Type_Name (Iterable_Info));
                     Element_Type_Image  : constant String :=
                       Render_Type_Name (Element_Info);
                     type Growable_Accumulator_Info is record
                        Name        : FT.UString := FT.To_UString ("");
                        Type_Image  : FT.UString := FT.To_UString ("");
                        Max_Delta   : Long_Long_Integer := 0;
                     end record;
                     package Growable_Accumulator_Vectors is new Ada.Containers.Vectors
                       (Index_Type   => Positive,
                        Element_Type => Growable_Accumulator_Info);
                     Accumulator_Names : FT.UString_Vectors.Vector;
                     Accumulator_Type_Images : FT.UString_Vectors.Vector;
                     Invalidated_Accumulator_Names : FT.UString_Vectors.Vector;
                     Growable_Accumulators : Growable_Accumulator_Vectors.Vector;
                     Has_Top_Level_Loop_Invariant : Boolean := False;

                     function Contains_Name
                       (Items : FT.UString_Vectors.Vector;
                        Name  : String) return Boolean
                     is
                     begin
                        for Item_Name of Items loop
                           if FT.To_String (Item_Name) = Name then
                              return True;
                           end if;
                        end loop;
                        return False;
                     end Contains_Name;

                     procedure Remove_Accumulator (Name : String) is
                     begin
                        if Accumulator_Names.Is_Empty then
                           return;
                        end if;
                        for Index in reverse Accumulator_Names.First_Index .. Accumulator_Names.Last_Index loop
                           if FT.To_String (Accumulator_Names (Index)) = Name then
                              Accumulator_Names.Delete (Index);
                              Accumulator_Type_Images.Delete (Index);
                           end if;
                        end loop;
                     end Remove_Accumulator;

                     procedure Add_Accumulator
                       (Name       : String;
                        Type_Image : String) is
                     begin
                        if Contains_Name (Invalidated_Accumulator_Names, Name)
                          or else Contains_Name (Accumulator_Names, Name)
                        then
                           return;
                        end if;
                        Accumulator_Names.Append (FT.To_UString (Name));
                        Accumulator_Type_Images.Append (FT.To_UString (Type_Image));
                     end Add_Accumulator;

                     procedure Invalidate_Accumulator (Name : String) is
                     begin
                        if Name'Length = 0 or else Contains_Name (Invalidated_Accumulator_Names, Name) then
                           return;
                        end if;
                        Remove_Accumulator (Name);
                        Invalidated_Accumulator_Names.Append (FT.To_UString (Name));
                     end Invalidate_Accumulator;

                     function Expr_Is_One (Expr : CM.Expr_Access) return Boolean is
                     begin
                        return Expr /= null
                          and then Expr.Kind = CM.Expr_Int
                          and then Expr.Int_Value = 1;
                     end Expr_Is_One;

                     function Same_Target_Name
                       (Expr : CM.Expr_Access;
                        Name : String) return Boolean is
                     begin
                        return Expr /= null
                          and then Expr.Kind = CM.Expr_Ident
                          and then FT.To_String (Expr.Name) = Name;
                     end Same_Target_Name;

                     function Target_Ident_Name (Expr : CM.Expr_Access) return String is
                     begin
                        if Expr /= null and then Expr.Kind = CM.Expr_Ident then
                           return FT.To_String (Expr.Name);
                        end if;
                        return "";
                     end Target_Ident_Name;

                     function Accumulator_Value_Expr
                       (Expr : CM.Expr_Access) return CM.Expr_Access is
                     begin
                        if Expr /= null
                          and then Expr.Kind in CM.Expr_Annotated | CM.Expr_Conversion
                          and then Expr.Inner /= null
                        then
                           return Accumulator_Value_Expr (Expr.Inner);
                        end if;

                        return Expr;
                     end Accumulator_Value_Expr;

                     function Try_Nonnegative_Static_Step
                       (Expr       : CM.Expr_Access;
                        Name       : String;
                        Step_Value : out Long_Long_Integer) return Boolean
                     is
                        Value : Long_Long_Integer := 0;
                     begin
                        Step_Value := 0;
                        if Expr = null
                          or else Expr_Uses_Name (Expr, Name)
                          or else not Try_Resolved_Static_Integer_Value
                            (Unit, Document, State, Expr, Value)
                          or else Value < 0
                        then
                           return False;
                        end if;

                        Step_Value := Value;
                        return True;
                     end Try_Nonnegative_Static_Step;

                     function Supported_Accumulator_Assignment
                       (Stmt       : CM.Statement;
                        Name       : String;
                        Step_Value : out Long_Long_Integer) return Boolean
                     is
                     begin
                        Step_Value := 0;
                        declare
                           Value_Expr : constant CM.Expr_Access :=
                             Accumulator_Value_Expr (Stmt.Value);
                        begin
                           if Target_Ident_Name (Stmt.Target) /= Name
                             or else Value_Expr = null
                             or else Value_Expr.Kind /= CM.Expr_Binary
                             or else FT.To_String (Value_Expr.Operator) /= "+"
                           then
                              return False;
                           end if;

                           if Same_Target_Name (Value_Expr.Left, Name) then
                              return Try_Nonnegative_Static_Step
                                (Value_Expr.Right,
                                 Name,
                                 Step_Value);
                           elsif Same_Target_Name (Value_Expr.Right, Name) then
                              return Try_Nonnegative_Static_Step
                                (Value_Expr.Left,
                                 Name,
                                 Step_Value);
                           end if;
                        end;

                        return False;
                     end Supported_Accumulator_Assignment;

                     function Add_Step
                       (Left  : Long_Long_Integer;
                        Right : Long_Long_Integer;
                        Sum   : out Long_Long_Integer) return Boolean
                     is
                        Wide_Sum : constant CM.Wide_Integer :=
                          CM.Wide_Integer (Left) + CM.Wide_Integer (Right);
                     begin
                        Sum := 0;
                        if Wide_Sum > CM.Wide_Integer (Long_Long_Integer'Last) then
                           return False;
                        end if;

                        Sum := Long_Long_Integer (Wide_Sum);
                        return True;
                     end Add_Step;

                     procedure Analyze_Accumulator_Statements
                       (Statements : CM.Statement_Access_Vectors.Vector;
                        Name       : String;
                        Max_Step   : out Long_Long_Integer;
                        Unsafe     : out Boolean);

                     procedure Analyze_Accumulator_Statement
                       (Stmt     : CM.Statement_Access;
                        Name     : String;
                        Max_Step : out Long_Long_Integer;
                        Unsafe   : out Boolean)
                     is
                        procedure Add_Branch
                          (Branch_Statements : CM.Statement_Access_Vectors.Vector;
                           Branch_Max        : in out Long_Long_Integer;
                           Branch_Unsafe     : in out Boolean)
                        is
                           Candidate_Step   : Long_Long_Integer := 0;
                           Candidate_Unsafe : Boolean := False;
                        begin
                           Analyze_Accumulator_Statements
                             (Branch_Statements,
                              Name,
                              Candidate_Step,
                              Candidate_Unsafe);
                           if Candidate_Unsafe then
                              Branch_Unsafe := True;
                           elsif Candidate_Step > Branch_Max then
                              Branch_Max := Candidate_Step;
                           end if;
                        end Add_Branch;

                        Step_Value : Long_Long_Integer := 0;
                     begin
                        Max_Step := 0;
                        Unsafe := False;
                        if Stmt = null then
                           return;
                        end if;

                        case Stmt.Kind is
                           when CM.Stmt_Assign =>
                              if Target_Ident_Name (Stmt.Target) = Name then
                                 if Supported_Accumulator_Assignment
                                   (Stmt.all,
                                    Name,
                                    Step_Value)
                                 then
                                    Max_Step := Step_Value;
                                 else
                                    Unsafe := True;
                                 end if;
                              elsif Expr_Uses_Name (Stmt.Target, Name) then
                                 Unsafe := True;
                              end if;

                           when CM.Stmt_Object_Decl =>
                              for Decl_Name of Stmt.Decl.Names loop
                                 if FT.To_String (Decl_Name) = Name then
                                    Unsafe := True;
                                    return;
                                 end if;
                              end loop;

                           when CM.Stmt_Destructure_Decl =>
                              for Decl_Name of Stmt.Destructure.Names loop
                                 if FT.To_String (Decl_Name) = Name then
                                    Unsafe := True;
                                    return;
                                 end if;
                              end loop;

                           when CM.Stmt_If =>
                              if Expr_Uses_Name (Stmt.Condition, Name) then
                                 --  Guard-dependent increments can be safe, but this
                                 --  optional proof heuristic is only emitted for
                                 --  unconditional accumulator progress.
                                 Unsafe := True;
                                 return;
                              end if;
                              Add_Branch
                                (Stmt.Then_Stmts,
                                 Max_Step,
                                 Unsafe);
                              for Part of Stmt.Elsifs loop
                                 if Expr_Uses_Name (Part.Condition, Name) then
                                    --  Keep guard-dependent accumulator updates
                                    --  fail-closed for this optional invariant.
                                    Unsafe := True;
                                    return;
                                 end if;
                                 Add_Branch
                                   (Part.Statements,
                                    Max_Step,
                                    Unsafe);
                              end loop;
                              if Stmt.Has_Else then
                                 Add_Branch
                                   (Stmt.Else_Stmts,
                                    Max_Step,
                                    Unsafe);
                              end if;

                           when CM.Stmt_Case =>
                              if Expr_Uses_Name (Stmt.Case_Expr, Name) then
                                 Unsafe := True;
                                 return;
                              end if;
                              for Arm of Stmt.Case_Arms loop
                                 if Expr_Uses_Name (Arm.Choice, Name) then
                                    Unsafe := True;
                                    return;
                                 end if;
                                 Add_Branch
                                   (Arm.Statements,
                                    Max_Step,
                                    Unsafe);
                              end loop;

                           when CM.Stmt_Match =>
                              if Expr_Uses_Name (Stmt.Match_Expr, Name) then
                                 Unsafe := True;
                                 return;
                              end if;
                              for Arm of Stmt.Match_Arms loop
                                 for Binder of Arm.Binders loop
                                    if FT.To_String (Binder) = Name then
                                       Unsafe := True;
                                       return;
                                    end if;
                                 end loop;
                                 Add_Branch
                                   (Arm.Statements,
                                    Max_Step,
                                    Unsafe);
                              end loop;

                           when CM.Stmt_Select =>
                              --  Select arms have synchronization semantics; keep this
                              --  proof heuristic fail-closed instead of inferring headroom
                              --  through channel/delay alternatives.
                              Unsafe := True;

                           when others =>
                              if Statements_Use_Name (Stmt.Body_Stmts, Name)
                                or else Expr_Uses_Name (Stmt.Target, Name)
                                or else Expr_Uses_Name (Stmt.Value, Name)
                                or else Expr_Uses_Name (Stmt.Call, Name)
                                or else Expr_Uses_Name (Stmt.Channel_Name, Name)
                                or else Expr_Uses_Name (Stmt.Success_Var, Name)
                              then
                                 Unsafe := True;
                              end if;
                        end case;
                     end Analyze_Accumulator_Statement;

                     procedure Analyze_Accumulator_Statements
                       (Statements : CM.Statement_Access_Vectors.Vector;
                        Name       : String;
                        Max_Step   : out Long_Long_Integer;
                        Unsafe     : out Boolean)
                     is
                        Total : Long_Long_Integer := 0;
                     begin
                        Max_Step := 0;
                        Unsafe := False;
                        for Nested of Statements loop
                           declare
                              Statement_Step   : Long_Long_Integer := 0;
                              Statement_Unsafe : Boolean := False;
                           begin
                              Analyze_Accumulator_Statement
                                (Nested,
                                 Name,
                                 Statement_Step,
                                 Statement_Unsafe);
                              if Statement_Unsafe
                                or else not Add_Step (Total, Statement_Step, Total)
                              then
                                 Unsafe := True;
                                 return;
                              end if;
                           end;
                        end loop;
                        Max_Step := Total;
                     end Analyze_Accumulator_Statements;

                     function Growable_Accumulator_Headroom_OK
                       (Info      : GM.Type_Descriptor;
                        Max_Delta : Long_Long_Integer) return Boolean
                     is
                        Base_Info : constant GM.Type_Descriptor :=
                          Base_Type (Unit, Document, Info);
                        High_Value : constant CM.Wide_Integer :=
                          (if Info.Has_High
                           then CM.Wide_Integer (Info.High)
                           elsif Base_Info.Has_High
                           then CM.Wide_Integer (Base_Info.High)
                           else CM.Wide_Integer (Long_Long_Integer'Last));
                        Low_Value : constant CM.Wide_Integer :=
                          (if Info.Has_Low
                           then CM.Wide_Integer (Info.Low)
                           elsif Base_Info.Has_Low
                           then CM.Wide_Integer (Base_Info.Low)
                           else CM.Wide_Integer (Long_Long_Integer'First));
                        Required_Headroom : constant CM.Wide_Integer :=
                          CM.Wide_Integer (Max_Delta) * CM.Wide_Integer (Natural'Last);
                        Runtime_Wide_Last : constant CM.Wide_Integer :=
                          CM.Wide_Integer (Long_Long_Integer'Last);
                        Range_Width : constant CM.Wide_Integer :=
                          High_Value - Low_Value;
                     begin
                        --  The emitted invariant performs the headroom arithmetic in
                        --  Safe_Runtime.Wide_Integer. Require the conservative
                        --  Natural'Last budget to fit that runtime type as well as
                        --  the accumulator's declared range.
                        return Max_Delta > 0
                          and then Low_Value <= High_Value
                          and then Required_Headroom <= Runtime_Wide_Last
                          and then Required_Headroom <= Range_Width;
                     end Growable_Accumulator_Headroom_OK;

                     function Contains_Growable_Accumulator (Name : String) return Boolean is
                     begin
                        for Info of Growable_Accumulators loop
                           if FT.To_String (Info.Name) = Name then
                              return True;
                           end if;
                        end loop;
                        return False;
                     end Contains_Growable_Accumulator;

                     procedure Add_Growable_Accumulator
                       (Name       : String;
                        Type_Image : String;
                        Max_Delta  : Long_Long_Integer) is
                     begin
                        if Contains_Growable_Accumulator (Name) then
                           return;
                        end if;

                        Growable_Accumulators.Append
                          ((Name       => FT.To_UString (Name),
                            Type_Image => FT.To_UString (Type_Image),
                            Max_Delta  => Max_Delta));
                     end Add_Growable_Accumulator;

                     procedure Collect_Growable_Accumulators
                       (Statements : CM.Statement_Access_Vectors.Vector)
                     is
                        procedure Visit_Assignment (Stmt : CM.Statement) is
                           Name_Image  : constant String := Target_Ident_Name (Stmt.Target);
                           Max_Delta   : Long_Long_Integer := 0;
                           Unsafe      : Boolean := False;
                        begin
                           if Name_Image'Length = 0
                             or else Contains_Growable_Accumulator (Name_Image)
                           then
                              return;
                           end if;

                           declare
                              Target_Info : constant GM.Type_Descriptor :=
                                Expr_Type_Info (Unit, Document, Stmt.Target);
                              Target_Type_Image : constant String :=
                                (if Is_Wide_Name (State, Name_Image)
                                 then "Safe_Runtime.Wide_Integer"
                                 else Render_Subtype_Indication (Unit, Document, Target_Info));
                           begin
                              if not Is_Integer_Type (Unit, Document, Target_Info) then
                                 return;
                              end if;

                              Analyze_Accumulator_Statements
                                (Item.Body_Stmts,
                                 Name_Image,
                                 Max_Delta,
                                 Unsafe);
                              if not Unsafe
                                and then Growable_Accumulator_Headroom_OK
                                  (Target_Info,
                                   Max_Delta)
                              then
                                 Add_Growable_Accumulator
                                   (Name_Image,
                                    Target_Type_Image,
                                    Max_Delta);
                              end if;
                           end;
                        end Visit_Assignment;
                     begin
                        for Nested of Statements loop
                           if Nested = null then
                              null;
                           else
                              case Nested.Kind is
                                 when CM.Stmt_Assign =>
                                    Visit_Assignment (Nested.all);
                                 when CM.Stmt_If =>
                                    Collect_Growable_Accumulators (Nested.Then_Stmts);
                                    for Part of Nested.Elsifs loop
                                       Collect_Growable_Accumulators (Part.Statements);
                                    end loop;
                                    if Nested.Has_Else then
                                       Collect_Growable_Accumulators (Nested.Else_Stmts);
                                    end if;
                                 when CM.Stmt_Case =>
                                    for Arm of Nested.Case_Arms loop
                                       Collect_Growable_Accumulators (Arm.Statements);
                                    end loop;
                                 when CM.Stmt_Match =>
                                    for Arm of Nested.Match_Arms loop
                                       Collect_Growable_Accumulators (Arm.Statements);
                                    end loop;
                                 when others =>
                                    null;
                              end case;
                           end if;
                        end loop;
                     end Collect_Growable_Accumulators;

                     function Growable_Accumulator_Invariant
                       (Info : Growable_Accumulator_Info) return String
                     is
                        Name_Text : constant String := FT.To_String (Info.Name);
                        Type_Image : constant String := FT.To_String (Info.Type_Image);
                        Delta_Image : constant String := Trim_Image (Info.Max_Delta);
                        Length_Image : constant String :=
                          "Safe_Runtime.Wide_Integer (Long_Long_Integer ("
                          & Array_Runtime_Instance_Name (Iterable_Info)
                          & ".Length ("
                          & Snapshot_Name
                          & ")))";
                        Total_Headroom_Image : constant String :=
                          "Safe_Runtime.Wide_Integer ("
                          & Delta_Image
                          & ") * "
                          & Length_Image;
                        Remaining_Image : constant String :=
                          "Safe_Runtime.Wide_Integer ("
                          & Delta_Image
                          & ") * ("
                          & Length_Image
                          & " - Safe_Runtime.Wide_Integer ("
                          & Index_Name
                          & ") + Safe_Runtime.Wide_Integer (1))";
                     begin
                        State.Needs_Safe_Runtime := True;
                        return
                          "pragma Loop_Invariant (Safe_Runtime.Wide_Integer ("
                          & Name_Text
                          & ") >= Safe_Runtime.Wide_Integer ("
                          & Name_Text
                          & "'Loop_Entry) and then Safe_Runtime.Wide_Integer ("
                          & Name_Text
                          & "'Loop_Entry) <= Safe_Runtime.Wide_Integer ("
                          & Type_Image
                          & "'Last) - "
                          & Total_Headroom_Image
                          & " and then Safe_Runtime.Wide_Integer ("
                          & Name_Text
                          & ") <= Safe_Runtime.Wide_Integer ("
                          & Type_Image
                          & "'Last) - "
                          & Remaining_Image
                          & ");";
                     end Growable_Accumulator_Invariant;

                     procedure Collect_String_Accumulators
                       (Statements : CM.Statement_Access_Vectors.Vector)
                     is
                        procedure Visit_Assignment (Stmt : CM.Statement) is
                           Name_Image : constant String :=
                             (if Stmt.Target /= null and then Stmt.Target.Kind = CM.Expr_Ident
                              then FT.To_String (Stmt.Target.Name)
                              else "");
                        begin
                           if Name_Image'Length = 0 then
                              return;
                           end if;

                           declare
                              Target_Info : constant GM.Type_Descriptor :=
                                Expr_Type_Info (Unit, Document, Stmt.Target);
                              Target_Name : constant String := Name_Image;
                              Target_Type_Image : constant String :=
                                (if Is_Wide_Name (State, Target_Name)
                                 then "Safe_Runtime.Wide_Integer"
                                 else Render_Type_Name (Target_Info));
                              Supported : constant Boolean :=
                                Stmt.Value /= null
                                and then Stmt.Value.Kind = CM.Expr_Binary
                                and then FT.To_String (Stmt.Value.Operator) = "+"
                                and then Is_Integer_Type (Unit, Document, Target_Info)
                                and then
                                  ((Same_Target_Name (Stmt.Value.Left, Name_Image)
                                    and then Expr_Is_One (Stmt.Value.Right))
                                   or else
                                     (Same_Target_Name (Stmt.Value.Right, Name_Image)
                                      and then Expr_Is_One (Stmt.Value.Left)));
                           begin
                              if Supported then
                                 Add_Accumulator
                                   (Target_Name,
                                    Target_Type_Image);
                              else
                                 Invalidate_Accumulator (Name_Image);
                              end if;
                           end;
                        end Visit_Assignment;
                     begin
                        for Nested of Statements loop
                           if Nested = null then
                              null;
                           else
                              case Nested.Kind is
                                 when CM.Stmt_Assign =>
                                    Visit_Assignment (Nested.all);
                                 when CM.Stmt_If =>
                                    Collect_String_Accumulators (Nested.Then_Stmts);
                                    for Part of Nested.Elsifs loop
                                       Collect_String_Accumulators (Part.Statements);
                                    end loop;
                                    if Nested.Has_Else then
                                       Collect_String_Accumulators (Nested.Else_Stmts);
                                    end if;
                                 when CM.Stmt_Case =>
                                    for Arm of Nested.Case_Arms loop
                                       Collect_String_Accumulators (Arm.Statements);
                                    end loop;
                                 when others =>
                                    null;
                              end case;
                           end if;
                        end loop;
                     end Collect_String_Accumulators;

                     function Static_Growable_Literal_Expr return CM.Expr_Access is
                     begin
                        if not Iterable_Info.Growable then
                           return null;
                        end if;

                        if Item.Loop_Iterable /= null
                          and then Item.Loop_Iterable.Kind = CM.Expr_Array_Literal
                        then
                           return Item.Loop_Iterable;
                        elsif Item.Loop_Iterable /= null
                          and then Item.Loop_Iterable.Kind = CM.Expr_Ident
                        then
                           declare
                              Iterable_Name : constant String :=
                                FT.To_String (Item.Loop_Iterable.Name);
                           begin
                              if not Unit.Subprograms.Is_Empty
                                or else not Unit.Tasks.Is_Empty
                                or else Unit_Runtime_Assigns_Name (Unit, Iterable_Name)
                              then
                                 return null;
                              end if;

                              for Decl of Unit.Objects loop
                                 if Decl.Has_Initializer
                                   and then Decl.Initializer /= null
                                   and then Decl.Initializer.Kind = CM.Expr_Array_Literal
                                 then
                                    for Name of Decl.Names loop
                                       if FT.To_String (Name) = Iterable_Name then
                                          return Decl.Initializer;
                                       end if;
                                    end loop;
                                 end if;
                              end loop;
                           end;
                        end if;

                        return null;
                     end Static_Growable_Literal_Expr;

                     function Try_Static_String_Iterable
                       (Image  : out SU.Unbounded_String;
                        Length : out Natural) return Boolean
                     is
                     begin
                        Image := SU.Null_Unbounded_String;
                        Length := 0;
                        if not Is_String_Iterable or else Item.Loop_Iterable = null then
                           return False;
                        elsif Try_Static_String_Literal
                          (Item.Loop_Iterable,
                           Image,
                           Length)
                        then
                           return True;
                        elsif Item.Loop_Iterable.Kind = CM.Expr_Ident then
                           declare
                              Iterable_Name : constant String :=
                                FT.To_String (Item.Loop_Iterable.Name);
                           begin
                              if not Unit.Subprograms.Is_Empty
                                or else not Unit.Tasks.Is_Empty
                                or else Unit_Runtime_Assigns_Name (Unit, Iterable_Name)
                              then
                                 return False;
                              end if;

                              return
                                Try_Object_Static_String_Initializer
                                  (Unit,
                                   Iterable_Name,
                                   Image,
                                   Length);
                           end;
                        end if;

                        return False;
                     end Try_Static_String_Iterable;

                     function Static_Growable_Prefix_Sum_Invariant return String is
                        Literal_Expr : CM.Expr_Access := null;

                        function Supported_Body return Boolean is
                        begin
                           if Item.Body_Stmts.Length /= 1 then
                              return False;
                           end if;

                           declare
                              Only_Stmt : constant CM.Statement_Access :=
                                Item.Body_Stmts (Item.Body_Stmts.First_Index);
                           begin
                              return
                                Only_Stmt /= null
                                and then Only_Stmt.Kind = CM.Stmt_Assign
                                and then Only_Stmt.Target /= null
                                and then Only_Stmt.Target.Kind = CM.Expr_Ident
                                and then Has_Text (Only_Stmt.Target.Type_Name)
                                and then Is_Integer_Type
                                  (Unit, Document, FT.To_String (Only_Stmt.Target.Type_Name))
                                and then Only_Stmt.Value /= null
                                and then Only_Stmt.Value.Kind = CM.Expr_Binary
                                and then FT.To_String (Only_Stmt.Value.Operator) = "+"
                                and then
                                  ((Only_Stmt.Value.Left /= null
                                    and then Only_Stmt.Value.Left.Kind = CM.Expr_Ident
                                    and then FT.To_String (Only_Stmt.Value.Left.Name)
                                      = FT.To_String (Only_Stmt.Target.Name)
                                    and then Only_Stmt.Value.Right /= null
                                    and then Only_Stmt.Value.Right.Kind = CM.Expr_Ident
                                    and then FT.To_String (Only_Stmt.Value.Right.Name)
                                      = FT.To_String (Item.Loop_Var))
                                   or else
                                     (Only_Stmt.Value.Right /= null
                                      and then Only_Stmt.Value.Right.Kind = CM.Expr_Ident
                                      and then FT.To_String (Only_Stmt.Value.Right.Name)
                                        = FT.To_String (Only_Stmt.Target.Name)
                                      and then Only_Stmt.Value.Left /= null
                                      and then Only_Stmt.Value.Left.Kind = CM.Expr_Ident
                                      and then FT.To_String (Only_Stmt.Value.Left.Name)
                                        = FT.To_String (Item.Loop_Var)));
                           end;
                        end Supported_Body;
                     begin
                        if not Iterable_Info.Growable or else not Supported_Body then
                           return "";
                        end if;

                        Literal_Expr := Static_Growable_Literal_Expr;

                        if Literal_Expr = null or else Literal_Expr.Elements.Is_Empty then
                           return "";
                        end if;

                        declare
                           Only_Stmt : constant CM.Statement_Access :=
                             Item.Body_Stmts (Item.Body_Stmts.First_Index);
                           Target_Name : constant String := FT.To_String (Only_Stmt.Target.Name);
                           Prefix_Sum  : CM.Wide_Integer := 0;
                           Result      : SU.Unbounded_String :=
                             SU.To_Unbounded_String
                               ("pragma Loop_Invariant (Safe_Runtime.Wide_Integer ("
                                & Target_Name
                                & ") = Safe_Runtime.Wide_Integer ("
                                & Target_Name
                                & "'Loop_Entry) + (if ");
                        begin
                           State.Needs_Safe_Runtime := True;
                           if Literal_Expr.Elements.Length = 1 then
                              Result :=
                                Result
                                & SU.To_Unbounded_String
                                    (Index_Name
                                     & " = 1 then Safe_Runtime.Wide_Integer (0)"
                                     & " else Safe_Runtime.Wide_Integer (0)));");
                              return SU.To_String (Result);
                           end if;

                           for Element_Index in Literal_Expr.Elements.First_Index .. Literal_Expr.Elements.Last_Index - 1 loop
                              declare
                                 Element : constant CM.Expr_Access := Literal_Expr.Elements (Element_Index);
                                 Case_Index : constant Natural :=
                                   Natural (Element_Index - Literal_Expr.Elements.First_Index + 1);
                              begin
                                 if Element = null or else Element.Kind /= CM.Expr_Int then
                                    return "";
                                 end if;

                                 Result :=
                                   Result
                                   & SU.To_Unbounded_String
                                       (Index_Name
                                        & " = "
                                        & Natural'Image (Case_Index)
                                        & " then Safe_Runtime.Wide_Integer ("
                                        & Trim_Wide_Image (Prefix_Sum)
                                        & ")");
                                 Prefix_Sum := Prefix_Sum + Element.Int_Value;
                                 if Element_Index /= Literal_Expr.Elements.Last_Index - 1 then
                                    Result :=
                                      Result
                                      & SU.To_Unbounded_String (" elsif ");
                                 end if;
                              end;
                           end loop;

                           Result :=
                             Result
                             & SU.To_Unbounded_String
                                 (" else Safe_Runtime.Wide_Integer ("
                                  & Trim_Wide_Image (Prefix_Sum)
                                  & ")));");
                           return SU.To_String (Result);
                        end;
                     end Static_Growable_Prefix_Sum_Invariant;

                     function Static_Growable_Post_Sum_Assertion return String is
                        Literal_Expr : CM.Expr_Access := null;
                        Prefix_Sum   : CM.Wide_Integer := 0;
                        Result       : SU.Unbounded_String := SU.Null_Unbounded_String;
                        function Supported_Body return Boolean is
                        begin
                           if Item.Body_Stmts.Length /= 1 then
                              return False;
                           end if;

                           declare
                              Only_Stmt : constant CM.Statement_Access :=
                                Item.Body_Stmts (Item.Body_Stmts.First_Index);
                           begin
                              return
                                Only_Stmt /= null
                                and then Only_Stmt.Kind = CM.Stmt_Assign
                                and then Only_Stmt.Target /= null
                                and then Only_Stmt.Target.Kind = CM.Expr_Ident
                                and then Has_Text (Only_Stmt.Target.Type_Name)
                                and then Is_Integer_Type
                                  (Unit, Document, FT.To_String (Only_Stmt.Target.Type_Name))
                                and then Only_Stmt.Value /= null
                                and then Only_Stmt.Value.Kind = CM.Expr_Binary
                                and then FT.To_String (Only_Stmt.Value.Operator) = "+"
                                and then
                                  ((Only_Stmt.Value.Left /= null
                                    and then Only_Stmt.Value.Left.Kind = CM.Expr_Ident
                                    and then FT.To_String (Only_Stmt.Value.Left.Name)
                                      = FT.To_String (Only_Stmt.Target.Name)
                                    and then Only_Stmt.Value.Right /= null
                                    and then Only_Stmt.Value.Right.Kind = CM.Expr_Ident
                                    and then FT.To_String (Only_Stmt.Value.Right.Name)
                                      = FT.To_String (Item.Loop_Var))
                                   or else
                                     (Only_Stmt.Value.Right /= null
                                      and then Only_Stmt.Value.Right.Kind = CM.Expr_Ident
                                      and then FT.To_String (Only_Stmt.Value.Right.Name)
                                        = FT.To_String (Only_Stmt.Target.Name)
                                      and then Only_Stmt.Value.Left /= null
                                      and then Only_Stmt.Value.Left.Kind = CM.Expr_Ident
                                      and then FT.To_String (Only_Stmt.Value.Left.Name)
                                        = FT.To_String (Item.Loop_Var)));
                           end;
                        end Supported_Body;
                     begin
                        if not Iterable_Info.Growable or else not Supported_Body then
                           return "";
                        end if;

                        Literal_Expr := Static_Growable_Literal_Expr;

                        if Literal_Expr = null or else Literal_Expr.Elements.Is_Empty then
                           return "";
                        end if;

                        declare
                           Target_Name : constant String :=
                             FT.To_String (Item.Body_Stmts (Item.Body_Stmts.First_Index).Target.Name);
                        begin
                           Result :=
                             SU.To_Unbounded_String
                               ("pragma Assert (Safe_Runtime.Wide_Integer ("
                                & Target_Name
                                & ") = Safe_Runtime.Wide_Integer ("
                                & Target_Name
                                & "'Loop_Entry) + (if ");
                        end;

                        State.Needs_Safe_Runtime := True;
                        if Literal_Expr.Elements.Length = 1 then
                           declare
                              Only_Element : constant CM.Expr_Access :=
                                Literal_Expr.Elements (Literal_Expr.Elements.First_Index);
                           begin
                              if Only_Element = null or else Only_Element.Kind /= CM.Expr_Int then
                                 return "";
                              end if;
                              Prefix_Sum := Only_Element.Int_Value;
                              Result :=
                                Result
                                & SU.To_Unbounded_String
                                    (Index_Name
                                     & " = 1 then Safe_Runtime.Wide_Integer ("
                                     & Trim_Wide_Image (Prefix_Sum)
                                     & ") else Safe_Runtime.Wide_Integer ("
                                     & Trim_Wide_Image (Prefix_Sum)
                                     & ")));");
                              return SU.To_String (Result);
                           end;
                        end if;

                        for Element_Index in Literal_Expr.Elements.First_Index .. Literal_Expr.Elements.Last_Index - 1 loop
                           declare
                              Element : constant CM.Expr_Access := Literal_Expr.Elements (Element_Index);
                              Case_Index : constant Natural :=
                                Natural (Element_Index - Literal_Expr.Elements.First_Index + 1);
                           begin
                              if Element = null or else Element.Kind /= CM.Expr_Int then
                                 return "";
                              end if;

                              Prefix_Sum := Prefix_Sum + Element.Int_Value;
                              Result :=
                                Result
                                & SU.To_Unbounded_String
                                    (Index_Name
                                     & " = "
                                     & Natural'Image (Case_Index)
                                     & " then Safe_Runtime.Wide_Integer ("
                                     & Trim_Wide_Image (Prefix_Sum)
                                     & ")");
                              if Element_Index /= Literal_Expr.Elements.Last_Index - 1 then
                                 Result :=
                                   Result
                                   & SU.To_Unbounded_String (" elsif ");
                              end if;
                           end;
                        end loop;

                        declare
                           Last_Element : constant CM.Expr_Access :=
                             Literal_Expr.Elements (Literal_Expr.Elements.Last_Index);
                        begin
                           if Last_Element = null or else Last_Element.Kind /= CM.Expr_Int then
                              return "";
                           end if;
                           Prefix_Sum := Prefix_Sum + Last_Element.Int_Value;
                        end;

                        Result :=
                          Result
                          & SU.To_Unbounded_String
                              (" else Safe_Runtime.Wide_Integer ("
                               & Trim_Wide_Image (Prefix_Sum)
                               & ")));");
                        return SU.To_String (Result);
                     end Static_Growable_Post_Sum_Assertion;
                  begin
                     if Plain_String_Iterable then
                        State.Needs_Safe_String_RT := True;
                     elsif Iterable_Info.Growable then
                        State.Needs_Safe_Array_RT := True;
                     end if;
                     if Is_String_Iterable then
                        Register_Bounded_String_Type (State, Element_Info);
                        if Is_Bounded_String_Type (Iterable_Info) then
                           Register_Bounded_String_Type (State, Iterable_Info);
                        end if;
                     end if;

                     declare
                        Static_Growable_Literal : constant CM.Expr_Access :=
                          Static_Growable_Literal_Expr;
                        Static_String_Image : SU.Unbounded_String :=
                          SU.Null_Unbounded_String;
                        Static_String_Length : Natural := 0;
                        Can_Unroll_Static_String : constant Boolean :=
                          Try_Static_String_Iterable
                            (Static_String_Image,
                             Static_String_Length);
                        Can_Unroll_Static_Growable : constant Boolean :=
                          Iterable_Info.Growable
                          and then Static_Growable_Literal /= null
                          and then not Static_Growable_Literal.Elements.Is_Empty;
                        Can_Unroll_Static_Iterable : constant Boolean :=
                          Can_Unroll_Static_Growable
                          or else Can_Unroll_Static_String;
                     begin
                        if not Can_Unroll_Static_Iterable then
                           Push_Cleanup_Frame (State);
                           if Is_String_Iterable then
                              null;
                           elsif Iterable_Info.Growable then
                              Add_Cleanup_Item
                                (State,
                                 Snapshot_Name,
                                 Snapshot_Type_Image,
                                 Array_Runtime_Instance_Name (Iterable_Info) & ".Free",
                                 Is_Constant => True,
                                 Always_Terminates_Suppression_OK =>
                                   Constant_Cleanup_Uses_Shared_Runtime_Free
                                     (Unit,
                                      Document,
                                      Iterable_Info,
                                      Array_Runtime_Instance_Name (Iterable_Info) & ".Free"));
                           end if;
                        end if;

                        Append_Line (Buffer, "declare", Depth);
                        if not Can_Unroll_Static_Iterable then
                           Append_Line
                             (Buffer,
                              Snapshot_Name & " : constant " & Snapshot_Type_Image & " := " & Snapshot_Init & ";",
                              Depth + 1);
                        end if;
                        Append_Line (Buffer, "begin", Depth);

                        if Can_Unroll_Static_Growable then
                           declare
                              Previous_Static_Integer_Count : constant Ada.Containers.Count_Type :=
                                State.Static_Integer_Bindings.Length;
                              Tracked_Static_Value : Long_Long_Integer := 0;
                           begin
                              if Natural (Item.Body_Stmts.Length) = 1
                                and then Item.Body_Stmts (Item.Body_Stmts.First_Index).Kind = CM.Stmt_Assign
                                and then Item.Body_Stmts (Item.Body_Stmts.First_Index).Target /= null
                                and then Item.Body_Stmts (Item.Body_Stmts.First_Index).Target.Kind = CM.Expr_Ident
                                and then Try_Object_Static_Integer_Initializer
                                  (Unit,
                                   FT.To_String (Item.Body_Stmts (Item.Body_Stmts.First_Index).Target.Name),
                                   Tracked_Static_Value)
                              then
                                 Bind_Static_Integer
                                   (State,
                                    FT.To_String (Item.Body_Stmts (Item.Body_Stmts.First_Index).Target.Name),
                                    Tracked_Static_Value);
                              end if;

                              for Element_Index in
                                Static_Growable_Literal.Elements.First_Index
                                .. Static_Growable_Literal.Elements.Last_Index
                              loop
                                 declare
                                    Element : constant CM.Expr_Access :=
                                      Static_Growable_Literal.Elements (Element_Index);
                                    Loop_Item_Source : constant String :=
                                      Render_Expr_For_Target_Type
                                        (Unit,
                                         Document,
                                         Element,
                                         Element_Info,
                                         State);
                                    Loop_Item_Init : constant String :=
                                      (if Needs_Composite_Heap_Helper
                                       then For_Of_Copy_Helper_Name
                                         (Unit,
                                          Document,
                                          Element_Info)
                                         & " ("
                                         & Loop_Item_Source
                                         & ")"
                                       else Loop_Item_Source);
                                 begin
                                    Push_Cleanup_Frame (State);
                                    if Is_Plain_String_Type (Unit, Document, Element_Info) then
                                       Add_Cleanup_Item
                                         (State,
                                          FT.To_String (Item.Loop_Var),
                                          Element_Type_Image,
                                          "Safe_String_RT.Free",
                                          Is_Constant => True,
                                          Always_Terminates_Suppression_OK =>
                                            Constant_Cleanup_Uses_Shared_Runtime_Free
                                              (Unit,
                                               Document,
                                               Element_Info,
                                               "Safe_String_RT.Free"));
                                    elsif Is_Growable_Array_Type (Unit, Document, Element_Info) then
                                       Add_Cleanup_Item
                                         (State,
                                          FT.To_String (Item.Loop_Var),
                                          Element_Type_Image,
                                          Array_Runtime_Instance_Name (Element_Info) & ".Free",
                                          Is_Constant => True,
                                          Always_Terminates_Suppression_OK =>
                                            Constant_Cleanup_Uses_Shared_Runtime_Free
                                              (Unit,
                                               Document,
                                               Element_Info,
                                               Array_Runtime_Instance_Name (Element_Info) & ".Free"));
                                    elsif Needs_Composite_Heap_Helper then
                                       Add_Cleanup_Item
                                         (State,
                                          FT.To_String (Item.Loop_Var),
                                          Element_Type_Image,
                                          For_Of_Free_Helper_Name
                                            (Unit,
                                             Document,
                                             Element_Info));
                                    end if;

                                    Append_Line (Buffer, "declare", Depth + 1);
                                    Append_Line
                                      (Buffer,
                                       FT.To_String (Item.Loop_Var)
                                       & " : "
                                       & (if Is_Plain_String_Type (Unit, Document, Element_Info)
                                          or else Is_Growable_Array_Type (Unit, Document, Element_Info)
                                          then "constant "
                                          else "")
                                       & Element_Type_Image
                                       & " := "
                                       & Loop_Item_Init
                                       & ";",
                                       Depth + 2);
                                    Append_Line (Buffer, "begin", Depth + 1);
                                    declare
                                       Previous_Static_Length_Count : constant Ada.Containers.Count_Type :=
                                         State.Static_Length_Bindings.Length;
                                       Element_Length : Natural := 0;
                                    begin
                                       if Is_Growable_Array_Type (Unit, Document, Element_Info)
                                         and then Static_Growable_Length (Element, Element_Length)
                                       then
                                          Bind_Static_Length
                                            (State,
                                             FT.To_String (Item.Loop_Var),
                                             Element_Length);
                                          Append_Line
                                            (Buffer,
                                             "pragma Assert ("
                                             & Array_Runtime_Instance_Name (Element_Info)
                                             & ".Length ("
                                             & FT.To_String (Item.Loop_Var)
                                             & ") = "
                                             & Trim_Wide_Image (CM.Wide_Integer (Element_Length))
                                             & ");",
                                             Depth + 2);
                                       end if;
                                       if Element_Index /= Static_Growable_Literal.Elements.Last_Index then
                                          Append_Gnatprove_Warning_Suppression
                                            (Buffer,
                                             "unused assignment",
                                             "static for-of unrolling preserves intermediate source assignments",
                                             Depth + 2);
                                       end if;
                                       Render_Required_Statement_Suite
                                         (Buffer,
                                          Unit,
                                          Document,
                                          Item.Body_Stmts,
                                          State,
                                          Depth + 2,
                                          Return_Type,
                                          True);
                                       if Element_Index /= Static_Growable_Literal.Elements.Last_Index then
                                          Append_Gnatprove_Warning_Restore
                                            (Buffer,
                                             "unused assignment",
                                             Depth + 2);
                                       end if;
                                       if Natural (Item.Body_Stmts.Length) = 1
                                         and then Item.Body_Stmts (Item.Body_Stmts.First_Index).Kind = CM.Stmt_Assign
                                         and then Item.Body_Stmts (Item.Body_Stmts.First_Index).Target /= null
                                         and then Item.Body_Stmts (Item.Body_Stmts.First_Index).Target.Kind = CM.Expr_Ident
                                       then
                                          declare
                                             Target_Name : constant String :=
                                               FT.To_String (Item.Body_Stmts (Item.Body_Stmts.First_Index).Target.Name);
                                             Static_Value : Long_Long_Integer := 0;
                                          begin
                                             if Has_Static_Integer_Tracking (State, Target_Name) then
                                                if Try_Tracked_Static_Integer_Value
                                                  (State,
                                                   Item.Body_Stmts (Item.Body_Stmts.First_Index).Value,
                                                   Static_Value)
                                                then
                                                   Bind_Static_Integer (State, Target_Name, Static_Value);
                                                else
                                                   Invalidate_Static_Integer (State, Target_Name);
                                                end if;
                                             end if;
                                          end;
                                       end if;
                                       Restore_Static_Length_Bindings
                                         (State, Previous_Static_Length_Count);
                                    end;
                                    if Statements_Fall_Through (Item.Body_Stmts) then
                                       if Is_Plain_String_Type (Unit, Document, Element_Info)
                                         or else Is_Growable_Array_Type (Unit, Document, Element_Info)
                                         or else Needs_Composite_Heap_Helper
                                       then
                                          Append_Gnatprove_Warning_Suppression
                                            (Buffer,
                                             "is set by",
                                             "for-of loop item cleanup is intentional",
                                             Depth + 2);
                                          Append_Gnatprove_Warning_Suppression
                                            (Buffer,
                                             "statement has no effect",
                                             "for-of loop item cleanup is intentional",
                                             Depth + 2);
                                       end if;
                                       Render_Current_Cleanup_Frame (Buffer, State, Depth + 2);
                                       if Is_Plain_String_Type (Unit, Document, Element_Info)
                                         or else Is_Growable_Array_Type (Unit, Document, Element_Info)
                                         or else Needs_Composite_Heap_Helper
                                       then
                                          Append_Gnatprove_Warning_Restore
                                            (Buffer,
                                             "is set by",
                                             Depth + 2);
                                          Append_Gnatprove_Warning_Restore
                                            (Buffer,
                                             "statement has no effect",
                                             Depth + 2);
                                       end if;
                                    end if;
                                    Append_Line (Buffer, "end;", Depth + 1);
                                    Pop_Cleanup_Frame (State);
                                 end;
                              end loop;
                              Restore_Static_Integer_Bindings
                                (State, Previous_Static_Integer_Count);
                           end;
                        elsif Can_Unroll_Static_String then
                           declare
                              Loop_Var_Name : constant String := FT.To_String (Item.Loop_Var);

                              function Try_Static_String_Additive_Update
                                (Statements  : CM.Statement_Access_Vectors.Vector;
                                 Target_Name : out SU.Unbounded_String;
                                 Target_Info : out GM.Type_Descriptor;
                                 Delta_Value : out Long_Long_Integer) return Boolean
                              is
                              begin
                                 Target_Name := SU.Null_Unbounded_String;
                                 Target_Info := (others => <>);
                                 Delta_Value := 0;

                                 if Statements.Length /= 1 or else Statements_Use_Name (Statements, Loop_Var_Name) then
                                    return False;
                                 end if;

                                 declare
                                    Only_Stmt : constant CM.Statement_Access :=
                                      Statements (Statements.First_Index);
                                 begin
                                    if Only_Stmt = null
                                      or else Only_Stmt.Kind /= CM.Stmt_Assign
                                      or else Only_Stmt.Target = null
                                      or else Only_Stmt.Target.Kind /= CM.Expr_Ident
                                      or else Only_Stmt.Value = null
                                      or else Only_Stmt.Value.Kind /= CM.Expr_Binary
                                      or else FT.To_String (Only_Stmt.Value.Operator) /= "+"
                                    then
                                       return False;
                                    end if;

                                    declare
                                       This_Target_Name : constant String :=
                                         FT.To_String (Only_Stmt.Target.Name);
                                       This_Target_Info : constant GM.Type_Descriptor :=
                                         Expr_Type_Info (Unit, Document, Only_Stmt.Target);
                                    begin
                                       if not Is_Integer_Type (Unit, Document, This_Target_Info) then
                                          return False;
                                       end if;

                                       if Only_Stmt.Value.Left /= null
                                         and then Only_Stmt.Value.Left.Kind = CM.Expr_Ident
                                         and then FT.To_String (Only_Stmt.Value.Left.Name) = This_Target_Name
                                         and then Only_Stmt.Value.Right /= null
                                         and then Try_Static_Integer_Value (Only_Stmt.Value.Right, Delta_Value)
                                       then
                                          Target_Name := SU.To_Unbounded_String (This_Target_Name);
                                          Target_Info := This_Target_Info;
                                          return True;
                                       end if;

                                       if Only_Stmt.Value.Right /= null
                                         and then Only_Stmt.Value.Right.Kind = CM.Expr_Ident
                                         and then FT.To_String (Only_Stmt.Value.Right.Name) = This_Target_Name
                                         and then Only_Stmt.Value.Left /= null
                                         and then Try_Static_Integer_Value (Only_Stmt.Value.Left, Delta_Value)
                                       then
                                          Target_Name := SU.To_Unbounded_String (This_Target_Name);
                                          Target_Info := This_Target_Info;
                                          return True;
                                       end if;
                                    end;
                                 end;

                                 return False;
                              end Try_Static_String_Additive_Update;

                              Collapsed_Target_Name : SU.Unbounded_String := SU.Null_Unbounded_String;
                              Collapsed_Target_Info : GM.Type_Descriptor := (others => <>);
                              Collapsed_Delta       : Long_Long_Integer := 0;
                              Per_Hit_Delta         : Long_Long_Integer := 0;
                              Initial_Static_Value  : Long_Long_Integer := 0;
                              Initial_Static_Known  : Boolean := False;
                              Can_Collapse_Static_String : Boolean := False;
                           begin
                              if Natural (Item.Body_Stmts.Length) = 1
                                and then Item.Body_Stmts (Item.Body_Stmts.First_Index).Kind = CM.Stmt_If
                                and then Item.Body_Stmts (Item.Body_Stmts.First_Index).Condition /= null
                                and then Item.Body_Stmts (Item.Body_Stmts.First_Index).Elsifs.Is_Empty
                                and then not Item.Body_Stmts (Item.Body_Stmts.First_Index).Has_Else
                                and then Try_Static_String_Additive_Update
                                  (Item.Body_Stmts (Item.Body_Stmts.First_Index).Then_Stmts,
                                   Collapsed_Target_Name,
                                   Collapsed_Target_Info,
                                   Per_Hit_Delta)
                              then
                                 declare
                                    Target_Name : constant String := SU.To_String (Collapsed_Target_Name);
                                 begin
                                    Initial_Static_Known :=
                                      Try_Static_Integer_Binding (State, Target_Name, Initial_Static_Value)
                                      or else Try_Object_Static_Integer_Initializer
                                        (Unit,
                                         Target_Name,
                                         Initial_Static_Value);
                                 end;
                                 Can_Collapse_Static_String := Initial_Static_Known;
                                 if Can_Collapse_Static_String then
                                    for Element_Index in 1 .. Static_String_Length loop
                                       declare
                                          Element_Image : constant String :=
                                            Static_String_Literal_Element_Image
                                              (SU.To_String (Static_String_Image),
                                               Positive (Element_Index));
                                          Previous_Static_String_Count : constant Ada.Containers.Count_Type :=
                                            State.Static_String_Bindings.Length;
                                          Static_Condition : Boolean := False;
                                       begin
                                          Bind_Static_String
                                            (State,
                                             Loop_Var_Name,
                                             Element_Image);
                                          if not Try_Static_Boolean_Value
                                            (State,
                                             Item.Body_Stmts (Item.Body_Stmts.First_Index).Condition,
                                             Static_Condition)
                                          then
                                             Can_Collapse_Static_String := False;
                                          elsif Static_Condition then
                                             Collapsed_Delta := Collapsed_Delta + Per_Hit_Delta;
                                          end if;
                                          Restore_Static_String_Bindings
                                            (State,
                                             Previous_Static_String_Count);
                                          exit when not Can_Collapse_Static_String;
                                       end;
                                    end loop;
                                 end if;
                              end if;

                              if Can_Collapse_Static_String then
                                 if Collapsed_Delta = 0 then
                                    Append_Line (Buffer, "null;", Depth + 1);
                                 else
                                    declare
                                       Target_Name : constant String := SU.To_String (Collapsed_Target_Name);
                                       Target_Subtype : constant String :=
                                         Render_Subtype_Indication (Unit, Document, Collapsed_Target_Info);
                                       Final_Static_Value : constant CM.Wide_Integer :=
                                         CM.Wide_Integer (Initial_Static_Value)
                                         + CM.Wide_Integer (Collapsed_Delta);
                                       Final_Image : constant String :=
                                         Trim_Wide_Image (Final_Static_Value);
                                    begin
                                       State.Needs_Safe_Runtime := True;
                                       Append_Line
                                         (Buffer,
                                          "pragma Assert (Safe_Runtime.Wide_Integer ("
                                          & Final_Image
                                          & ") >= Safe_Runtime.Wide_Integer ("
                                          & Target_Subtype
                                          & "'First) and then Safe_Runtime.Wide_Integer ("
                                          & Final_Image
                                          & ") <= Safe_Runtime.Wide_Integer ("
                                          & Target_Subtype
                                          & "'Last));",
                                          Depth + 1);
                                       Append_Gnatprove_Warning_Suppression
                                         (Buffer,
                                          "unused assignment",
                                          "static for-of unrolling preserves intermediate source assignments",
                                          Depth + 1);
                                       Append_Line
                                         (Buffer,
                                          Target_Name
                                          & " := "
                                          & Target_Subtype
                                          & " (Safe_Runtime.Wide_Integer ("
                                          & Final_Image
                                          & "));",
                                          Depth + 1);
                                       Append_Gnatprove_Warning_Restore
                                         (Buffer,
                                          "unused assignment",
                                          Depth + 1);
                                       Bind_Static_Integer
                                         (State,
                                          Target_Name,
                                          Long_Long_Integer (Final_Static_Value));
                                    end;
                                 end if;
                              else
                                 for Element_Index in 1 .. Static_String_Length loop
                                    declare
                                       Element_Image : constant String :=
                                         Static_String_Literal_Element_Image
                                           (SU.To_String (Static_String_Image),
                                            Positive (Element_Index));
                                       Previous_Static_String_Count : constant Ada.Containers.Count_Type :=
                                         State.Static_String_Bindings.Length;
                                    begin
                                       Bind_Static_String
                                         (State,
                                          Loop_Var_Name,
                                          Element_Image);
                                       declare
                                          Rendered_Static_Body : Boolean := False;
                                          Static_Condition    : Boolean := False;
                                          Need_Loop_Item_Decl : Boolean :=
                                            Statements_Use_Name (Item.Body_Stmts, Loop_Var_Name);
                                          Body_Depth : Natural := Depth + 1;
                                       begin
                                          if Natural (Item.Body_Stmts.Length) = 1
                                            and then Item.Body_Stmts (Item.Body_Stmts.First_Index).Kind = CM.Stmt_If
                                            and then Item.Body_Stmts (Item.Body_Stmts.First_Index).Condition /= null
                                            and then Item.Body_Stmts (Item.Body_Stmts.First_Index).Elsifs.Is_Empty
                                            and then not Item.Body_Stmts (Item.Body_Stmts.First_Index).Has_Else
                                            and then Try_Static_Boolean_Value
                                              (State,
                                               Item.Body_Stmts (Item.Body_Stmts.First_Index).Condition,
                                               Static_Condition)
                                          then
                                             Rendered_Static_Body := True;
                                             Need_Loop_Item_Decl :=
                                               Static_Condition
                                               and then Statements_Use_Name
                                                 (Item.Body_Stmts (Item.Body_Stmts.First_Index).Then_Stmts,
                                                  Loop_Var_Name);
                                          end if;

                                          if Need_Loop_Item_Decl then
                                             Append_Line (Buffer, "declare", Depth + 1);
                                             Append_Line
                                               (Buffer,
                                                Loop_Var_Name
                                                & " : constant "
                                                & Element_Type_Image
                                                & " := "
                                                & Bounded_String_Instance_Name (Element_Info)
                                                & ".To_Bounded ("
                                                & Element_Image
                                                & ");",
                                                Depth + 2);
                                             Append_Line (Buffer, "begin", Depth + 1);
                                             Body_Depth := Depth + 2;
                                          end if;

                                          if Element_Index /= Static_String_Length then
                                             Append_Gnatprove_Warning_Suppression
                                               (Buffer,
                                                "unused assignment",
                                                "static for-of unrolling preserves intermediate source assignments",
                                                Body_Depth);
                                          end if;

                                          if Rendered_Static_Body then
                                             if Static_Condition then
                                                Render_Required_Statement_Suite
                                                  (Buffer,
                                                   Unit,
                                                   Document,
                                                   Item.Body_Stmts (Item.Body_Stmts.First_Index).Then_Stmts,
                                                   State,
                                                   Body_Depth,
                                                   Return_Type,
                                                   True);
                                             else
                                                Append_Line (Buffer, "null;", Body_Depth);
                                             end if;
                                          end if;

                                          if not Rendered_Static_Body then
                                             Append_Gnatprove_Warning_Suppression
                                               (Buffer,
                                                "statement has no effect",
                                                "static for-of string unrolling exposes constant conditions",
                                                Body_Depth);
                                             Render_Required_Statement_Suite
                                               (Buffer,
                                                Unit,
                                                Document,
                                                Item.Body_Stmts,
                                                State,
                                                Body_Depth,
                                                Return_Type,
                                                True);
                                             Append_Gnatprove_Warning_Restore
                                               (Buffer,
                                                "statement has no effect",
                                                Body_Depth);
                                          end if;

                                          if Element_Index /= Static_String_Length then
                                             Append_Gnatprove_Warning_Restore
                                               (Buffer,
                                                "unused assignment",
                                                Body_Depth);
                                          end if;
                                          if Need_Loop_Item_Decl then
                                             Append_Line (Buffer, "end;", Depth + 1);
                                          end if;
                                       end;
                                       Restore_Static_String_Bindings
                                         (State,
                                          Previous_Static_String_Count);
                                    end;
                                 end loop;
                              end if;
                           end;
                        else
                           if Is_String_Iterable then
                              Append_Line
                                (Buffer,
                                 "for " & Index_Name & " in " & Snapshot_Name & "'Range loop",
                                 Depth + 1);
                           elsif Iterable_Info.Growable then
                              Append_Line
                                (Buffer,
                                 "for " & Index_Name & " in 1 .. Long_Long_Integer ("
                                 & Array_Runtime_Instance_Name (Iterable_Info)
                                 & ".Length ("
                                 & Snapshot_Name
                                 & ")) loop",
                                 Depth + 1);
                           else
                              Append_Line
                                (Buffer,
                                 "for " & Index_Name & " in " & Snapshot_Name & "'Range loop",
                                 Depth + 1);
                           end if;

                           if Is_String_Iterable then
                              Collect_String_Accumulators (Item.Body_Stmts);
                              if not Accumulator_Names.Is_Empty then
                                 Has_Top_Level_Loop_Invariant := True;
                                 for Candidate_Index in Accumulator_Names.First_Index .. Accumulator_Names.Last_Index loop
                                    Append_Line
                                      (Buffer,
                                       "pragma Loop_Invariant ("
                                       & FT.To_String (Accumulator_Names (Candidate_Index))
                                       & " >= "
                                       & FT.To_String (Accumulator_Names (Candidate_Index))
                                       & "'Loop_Entry and then "
                                       & FT.To_String (Accumulator_Names (Candidate_Index))
                                       & " <= "
                                       & FT.To_String (Accumulator_Names (Candidate_Index))
                                       & "'Loop_Entry + "
                                       & FT.To_String (Accumulator_Type_Images (Candidate_Index))
                                       & " ("
                                       & Index_Name
                                       & " - "
                                       & Snapshot_Name
                                       & "'First));",
                                       Depth + 2);
                                 end loop;
                              end if;
                           elsif Iterable_Info.Growable then
                              if Needs_Composite_Heap_Helper then
                                 Collect_Growable_Accumulators (Item.Body_Stmts);
                                 if not Growable_Accumulators.Is_Empty then
                                    Has_Top_Level_Loop_Invariant := True;
                                    for Candidate of Growable_Accumulators loop
                                       Append_Line
                                         (Buffer,
                                          Growable_Accumulator_Invariant (Candidate),
                                          Depth + 2);
                                    end loop;
                                 end if;
                              end if;
                              declare
                                 Invariant_Image : constant String := Static_Growable_Prefix_Sum_Invariant;
                              begin
                                 if Invariant_Image'Length > 0 then
                                    Has_Top_Level_Loop_Invariant := True;
                                    Append_Line (Buffer, Invariant_Image, Depth + 2);
                                 end if;
                              end;
                           end if;

                           declare
                              Loop_Item_Init : SU.Unbounded_String := SU.Null_Unbounded_String;
                              Loop_Item_Source : SU.Unbounded_String := SU.Null_Unbounded_String;
                              Static_Growable_Literal : constant CM.Expr_Access :=
                                Static_Growable_Literal_Expr;
                              Fixed_Element_Image : constant String :=
                                Snapshot_Name & " (" & Index_Name & ")";
                           begin
                              if Is_String_Iterable then
                                 Loop_Item_Init :=
                                   SU.To_Unbounded_String
                                     (Bounded_String_Instance_Name (Element_Info)
                                      & ".To_Bounded ("
                                      & Snapshot_Name
                                      & " ("
                                      & Index_Name
                                      & " .. "
                                      & Index_Name
                                      & "))");
                              elsif Needs_Composite_Heap_Helper then
                                 Loop_Item_Source :=
                                   (if Iterable_Info.Growable
                                    then SU.To_Unbounded_String
                                      (Array_Runtime_Instance_Name (Iterable_Info)
                                       & ".Element ("
                                       & Snapshot_Name
                                       & ", Positive ("
                                       & Index_Name
                                       & "))")
                                    else SU.To_Unbounded_String (Fixed_Element_Image));
                                 Loop_Item_Init :=
                                   SU.To_Unbounded_String
                                     (For_Of_Copy_Helper_Name
                                        (Unit,
                                         Document,
                                         Element_Info)
                                      & " ("
                                      & SU.To_String (Loop_Item_Source)
                                      & ")");
                              elsif Iterable_Info.Growable
                                and then Static_Growable_Literal /= null
                                and then not Static_Growable_Literal.Elements.Is_Empty
                                and then not Has_Heap_Value_Type (Unit, Document, Element_Info)
                              then
                                 declare
                                    Static_Item_Image : SU.Unbounded_String :=
                                      SU.Null_Unbounded_String;
                                 begin
                                    if Static_Growable_Literal.Elements.Length = 1 then
                                       Loop_Item_Init :=
                                         SU.To_Unbounded_String
                                           (Render_Expr_For_Target_Type
                                              (Unit,
                                               Document,
                                               Static_Growable_Literal.Elements
                                                 (Static_Growable_Literal.Elements.First_Index),
                                               Element_Info,
                                               State));
                                    else
                                       declare
                                          First_Index : constant Positive :=
                                            Static_Growable_Literal.Elements.First_Index;
                                          Last_Index  : constant Positive :=
                                            Static_Growable_Literal.Elements.Last_Index;
                                          First_Element : constant CM.Expr_Access :=
                                            Static_Growable_Literal.Elements (First_Index);
                                       begin
                                          if First_Element = null then
                                             Loop_Item_Init :=
                                               SU.To_Unbounded_String
                                                 (Array_Runtime_Instance_Name (Iterable_Info)
                                                  & ".Element ("
                                                  & Snapshot_Name
                                                  & ", Positive ("
                                                  & Index_Name
                                                  & "))");
                                          else
                                             Static_Item_Image :=
                                               SU.To_Unbounded_String
                                                 ("(if "
                                                  & Index_Name
                                                  & " = "
                                                  & Natural'Image (1)
                                                  & " then "
                                                  & Render_Expr_For_Target_Type
                                                      (Unit,
                                                       Document,
                                                       First_Element,
                                                       Element_Info,
                                                       State));
                                             for Element_Index in First_Index + 1 .. Last_Index - 1 loop
                                                declare
                                                   Element : constant CM.Expr_Access :=
                                                     Static_Growable_Literal.Elements (Element_Index);
                                                   Case_Index : constant Natural :=
                                                     Natural (Element_Index - First_Index + 1);
                                                begin
                                                   if Element = null then
                                                      Static_Item_Image := SU.Null_Unbounded_String;
                                                      exit;
                                                   end if;

                                                   Static_Item_Image :=
                                                     Static_Item_Image
                                                     & SU.To_Unbounded_String
                                                         (" elsif "
                                                          & Index_Name
                                                          & " = "
                                                          & Natural'Image (Case_Index)
                                                          & " then "
                                                          & Render_Expr_For_Target_Type
                                                              (Unit,
                                                               Document,
                                                               Element,
                                                               Element_Info,
                                                               State));
                                                end;
                                             end loop;

                                             if SU.Length (Static_Item_Image) = 0 then
                                                Loop_Item_Init :=
                                                  SU.To_Unbounded_String
                                                    (Array_Runtime_Instance_Name (Iterable_Info)
                                                     & ".Element ("
                                                     & Snapshot_Name
                                                     & ", Positive ("
                                                     & Index_Name
                                                     & "))");
                                             else
                                                Static_Item_Image :=
                                                  Static_Item_Image
                                                  & SU.To_Unbounded_String
                                                      (" else "
                                                       & Render_Expr_For_Target_Type
                                                           (Unit,
                                                            Document,
                                                            Static_Growable_Literal.Elements (Last_Index),
                                                            Element_Info,
                                                            State)
                                                       & ")");
                                                Loop_Item_Init := Static_Item_Image;
                                             end if;
                                          end if;
                                       end;
                                    end if;
                                 end;
                              elsif Iterable_Info.Growable then
                                 Loop_Item_Init :=
                                   SU.To_Unbounded_String
                                     (Array_Runtime_Instance_Name (Iterable_Info)
                                      & ".Element ("
                                      & Snapshot_Name
                                      & ", Positive ("
                                      & Index_Name
                                      & "))");
                              elsif Is_Plain_String_Type (Unit, Document, Element_Info) then
                                 State.Needs_Safe_String_RT := True;
                                 Loop_Item_Init :=
                                   SU.To_Unbounded_String
                                     ("Safe_String_RT.Clone ("
                                      & Fixed_Element_Image
                                      & ")");
                              elsif Is_Growable_Array_Type (Unit, Document, Element_Info) then
                                 State.Needs_Safe_Array_RT := True;
                                 Loop_Item_Init :=
                                   SU.To_Unbounded_String
                                     (Array_Runtime_Instance_Name (Element_Info)
                                      & ".Clone ("
                                      & Fixed_Element_Image
                                      & ")");
                              else
                                 Loop_Item_Init := SU.To_Unbounded_String (Fixed_Element_Image);
                              end if;

                              Push_Cleanup_Frame (State);
                              if Is_Plain_String_Type (Unit, Document, Element_Info) then
                                 Add_Cleanup_Item
                                   (State,
                                    FT.To_String (Item.Loop_Var),
                                    Element_Type_Image,
                                    "Safe_String_RT.Free");
                              elsif Is_Growable_Array_Type (Unit, Document, Element_Info) then
                                 Add_Cleanup_Item
                                   (State,
                                    FT.To_String (Item.Loop_Var),
                                    Element_Type_Image,
                                    Array_Runtime_Instance_Name (Element_Info) & ".Free");
                              elsif Needs_Composite_Heap_Helper then
                                 Add_Cleanup_Item
                                   (State,
                                    FT.To_String (Item.Loop_Var),
                                    Element_Type_Image,
                                    For_Of_Free_Helper_Name
                                      (Unit,
                                       Document,
                                       Element_Info));
                              end if;

                              Append_Line (Buffer, "declare", Depth + 2);
                              Append_Line
                                (Buffer,
                                 FT.To_String (Item.Loop_Var)
                                 & " : "
                                 & Element_Type_Image
                                 & " := "
                                 & SU.To_String (Loop_Item_Init)
                                 & ";",
                                 Depth + 3);
                              Append_Line (Buffer, "begin", Depth + 2);
                              Render_Required_Statement_Suite
                                (Buffer,
                                 Unit,
                                 Document,
                                 Item.Body_Stmts,
                                 State,
                                 Depth + 3,
                                 Return_Type,
                                 True);
                              if Statements_Fall_Through (Item.Body_Stmts) then
                                 declare
                                    Post_Sum_Assertion : constant String :=
                                      Static_Growable_Post_Sum_Assertion;
                                 begin
                                    if Post_Sum_Assertion'Length > 0 then
                                       Append_Line (Buffer, Post_Sum_Assertion, Depth + 3);
                                    end if;
                                 end;
                                 if Is_Plain_String_Type (Unit, Document, Element_Info)
                                   or else Is_Growable_Array_Type (Unit, Document, Element_Info)
                                   or else Needs_Composite_Heap_Helper
                                 then
                                    Append_Gnatprove_Warning_Suppression
                                      (Buffer,
                                       "is set by",
                                       "for-of loop item cleanup is intentional",
                                       Depth + 3);
                                    Append_Gnatprove_Warning_Suppression
                                      (Buffer,
                                       "statement has no effect",
                                       "for-of loop item cleanup is intentional",
                                       Depth + 3);
                                 end if;
                                 Render_Current_Cleanup_Frame (Buffer, State, Depth + 3);
                                 if Is_Plain_String_Type (Unit, Document, Element_Info)
                                   or else Is_Growable_Array_Type (Unit, Document, Element_Info)
                                   or else Needs_Composite_Heap_Helper
                                 then
                                    Append_Gnatprove_Warning_Restore
                                      (Buffer,
                                       "is set by",
                                       Depth + 3);
                                    Append_Gnatprove_Warning_Restore
                                      (Buffer,
                                       "statement has no effect",
                                       Depth + 3);
                                 end if;
                              end if;
                              Append_Line (Buffer, "end;", Depth + 2);
                              Pop_Cleanup_Frame (State);
                           end;

                           Append_Line (Buffer, "end loop;", Depth + 1);
                        end if;

                        if not Can_Unroll_Static_Iterable then
                           Render_Current_Cleanup_Frame (Buffer, State, Depth + 1);
                           Pop_Cleanup_Frame (State);
                        end if;
                        Append_Line (Buffer, "end;", Depth);
                     end;
                  end;
               else
                  Append_Line
                    (Buffer,
                     "for "
                     & FT.To_String (Item.Loop_Var)
                     & " in "
                     & Render_Discrete_Range (Unit, Document, Item.Loop_Range, State)
                     & " loop",
                     Depth);
                  Render_Required_Statement_Suite
                    (Buffer, Unit, Document, Item.Body_Stmts, State, Depth + 1, Return_Type, True);
                  Append_Line (Buffer, "end loop;", Depth);
               end if;
            when CM.Stmt_Loop =>
               Append_Line (Buffer, "loop", Depth);
               Render_Required_Statement_Suite
                 (Buffer, Unit, Document, Item.Body_Stmts, State, Depth + 1, Return_Type, True);
               Append_Line (Buffer, "end loop;", Depth);
            when CM.Stmt_Exit =>
               if Item.Condition /= null then
                  declare
                     Rendered : constant Shared_Condition_Render :=
                       Render_Shared_Condition
                         (Unit, Document, Item.Condition, State, Index);
                  begin
                     if Rendered.Snapshots.Is_Empty then
                        Append_Line
                          (Buffer,
                           "exit when " & FT.To_String (Rendered.Image) & ";",
                           Depth);
                     else
                        Append_Line (Buffer, "declare", Depth);
                        Append_Shared_Condition_Declarations
                          (Buffer, Rendered, Depth + 1);
                        Append_Line (Buffer, "begin", Depth);
                        Append_Line
                          (Buffer,
                           "exit when " & FT.To_String (Rendered.Image) & ";",
                           Depth + 1);
                        Append_Line (Buffer, "end;", Depth);
                     end if;
                  end;
               else
                  Append_Line (Buffer, "exit;", Depth);
               end if;
            when CM.Stmt_Send =>
               if Item.Success_Var /= null then
                  Emit_Nonblocking_Send_Statement
                    (Buffer, Unit, Document, Item.all, Index, State, Depth);
               else
                  Raise_Internal
                    ("resolved send reached Ada emission without a success variable");
               end if;
            when CM.Stmt_Receive =>
               declare
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
                        Staged_Name  : constant String :=
                          Channel_Staged_Value_Name (Index);
                        Length_Name  : constant String :=
                          Channel_Staged_Length_Name (Index);
                        Element_Type : constant String :=
                          Render_Type_Name (Declared_Channel.Element_Type);
                        Target_Image : constant String :=
                          Render_Expr (Unit, Document, Item.Target, State);
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
                           True);
                        Append_Line (Buffer, "begin", Depth);
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
                              "Receive"),
                           Declared_Channel,
                           Staged_Name,
                           Length_Name,
                           "",
                           Depth + 1,
                           Force_Staged_Warnings => False,
                           Wrap_Task_Call_Warnings => State.Task_Body_Depth > 0);
                        Append_Staged_Channel_Length_Reconcile
                          (Buffer,
                           Unit,
                           Document,
                           State,
                           Declared_Channel,
                           Staged_Name,
                           Length_Name,
                           Depth + 1);
                        Append_Staged_Channel_Target_Adoption
                          (Buffer,
                           Unit,
                           Document,
                           State,
                           Declared_Channel,
                           Target_Image,
                           Staged_Name,
                           Length_Name,
                           Depth + 1);
                        Append_Line (Buffer, "end;", Depth);
                     end;
                  else
                     if State.Task_Body_Depth > 0 then
                        Append_Task_Channel_Call_Warning_Suppression (Buffer, Depth);
                     end if;
                     Append_Line
                       (Buffer,
                        Render_Channel_Operation_Target
                          (Unit,
                           Document,
                           State,
                           Item.Channel_Name,
                           Declared_Channel,
                           "Receive")
                        & " ("
                        & Render_Expr (Unit, Document, Item.Target, State)
                        & ");",
                        Depth);
                     if State.Task_Body_Depth > 0 then
                        Append_Task_Channel_Call_Warning_Restore (Buffer, Depth);
                     end if;
                  end if;
               end;
            when CM.Stmt_Try_Send =>
               Raise_Internal ("unreachable: try_send rejected by resolver");
            when CM.Stmt_Try_Receive =>
               declare
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
                        Staged_Name  : constant String :=
                          Channel_Staged_Value_Name (Index);
                        Length_Name  : constant String :=
                          Channel_Staged_Length_Name (Index);
                        Element_Type : constant String :=
                          Render_Type_Name (Declared_Channel.Element_Type);
                        Target_Image : constant String :=
                          Render_Expr (Unit, Document, Item.Target, State);
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
                           True);
                        Append_Line (Buffer, "begin", Depth);
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
                              "Try_Receive"),
                           Declared_Channel,
                           Staged_Name,
                           Length_Name,
                           Success_Image,
                           Depth + 1,
                           Force_Staged_Warnings => False,
                           Wrap_Task_Call_Warnings => State.Task_Body_Depth > 0);
                        if State.Task_Body_Depth > 0 then
                           Append_Task_If_Warning_Suppression (Buffer, Depth + 1);
                        end if;
                        Append_Line
                          (Buffer,
                           "if " & Success_Image & " then",
                           Depth + 1);
                        Append_Staged_Channel_Length_Reconcile
                          (Buffer,
                           Unit,
                           Document,
                           State,
                           Declared_Channel,
                           Staged_Name,
                           Length_Name,
                           Depth + 2);
                        Append_Staged_Channel_Target_Adoption
                          (Buffer,
                           Unit,
                           Document,
                           State,
                           Declared_Channel,
                           Target_Image,
                           Staged_Name,
                           Length_Name,
                           Depth + 2);
                        Append_Line (Buffer, "end if;", Depth + 1);
                        if State.Task_Body_Depth > 0 then
                           Append_Task_If_Warning_Restore (Buffer, Depth + 1);
                        end if;
                        Append_Line (Buffer, "end;", Depth);
                     end;
                  else
                     if State.Task_Body_Depth > 0 then
                        Append_Task_Channel_Call_Warning_Suppression (Buffer, Depth);
                     end if;
                     Append_Line
                       (Buffer,
                        Render_Channel_Operation_Target
                          (Unit,
                           Document,
                           State,
                           Item.Channel_Name,
                           Declared_Channel,
                           "Try_Receive")
                        & " ("
                        & Render_Expr (Unit, Document, Item.Target, State)
                        & ", "
                        & Render_Expr (Unit, Document, Item.Success_Var, State)
                        & ");",
                        Depth);
                     if State.Task_Body_Depth > 0 then
                        Append_Task_Channel_Call_Warning_Restore (Buffer, Depth);
                     end if;
                  end if;
               end;
            when CM.Stmt_Select =>
               State.Needs_Gnat_Adc := True;
               declare
                  Channel_Arm_Count : Natural := 0;
                  Delay_Arm_Count   : Natural := 0;
                  Dispatcher_Name   : constant String :=
                    Select_Dispatcher_Name (Item);
                  Next_Arm_Name     : constant String :=
                    Select_Rotation_State_Name (Item);

                  function Delay_Expr_Image return String is
                  begin
                     for Arm of Item.Arms loop
                        if Arm.Kind = CM.Select_Arm_Delay then
                           return
                             Render_Expr
                               (Unit,
                                Document,
                                Arm.Delay_Data.Duration_Expr,
                                State);
                        end if;
                     end loop;

                     return "0.0";
                  end Delay_Expr_Image;

                  procedure Render_Channel_Precheck
                    (Arm          : CM.Select_Arm;
                     Arm_Ordinal  : Positive;
                     Select_Depth : Natural)
                  is
                     Declared_Channel : constant CM.Resolved_Channel_Decl :=
                       Channel_Item (Arm.Channel_Data.Channel_Name);
                     Arm_Value_Name   : constant String :=
                       FT.To_String (Arm.Channel_Data.Variable_Name);
                     Arm_Type_Name    : constant String :=
                       Render_Type_Name (Arm.Channel_Data.Type_Info);
                     Arm_Has_Heap_Value : constant Boolean :=
                       Has_Heap_Value_Type
                         (Unit,
                          Document,
                          Declared_Channel.Element_Type);
                     Arm_Needs_Local_Cleanup_Suppression : constant Boolean :=
                       Arm_Has_Heap_Value
                       and then
                         (Is_Plain_String_Type
                            (Unit,
                             Document,
                             Declared_Channel.Element_Type)
                          or else
                          Is_Growable_Array_Type
                            (Unit,
                             Document,
                             Declared_Channel.Element_Type));
                     Arm_Free_Proc : constant String :=
                       (if not Arm_Has_Heap_Value
                        then ""
                        elsif Is_Plain_String_Type
                          (Unit,
                           Document,
                           Declared_Channel.Element_Type)
                        then "Safe_String_RT.Free"
                        elsif Is_Growable_Array_Type
                          (Unit,
                           Document,
                           Declared_Channel.Element_Type)
                        then
                          Array_Runtime_Instance_Name
                            (Base_Type
                               (Unit,
                                Document,
                                Declared_Channel.Element_Type))
                          & ".Free"
                        else Channel_Free_Helper_Name (Declared_Channel));
                     Next_Arm_Ordinal : constant Positive :=
                       (if Arm_Ordinal = Channel_Arm_Count
                        then 1
                        else Arm_Ordinal + 1);
                  begin
                     if Arm_Has_Heap_Value then
                        Push_Cleanup_Frame (State);
                        Add_Cleanup_Item
                          (State,
                           Arm_Value_Name,
                           Arm_Type_Name,
                           Arm_Free_Proc);
                     end if;
                     Append_Line (Buffer, "if not Select_Done then", Select_Depth);
                     Append_Line (Buffer, "declare", Select_Depth + 1);
                     Append_Staged_Channel_Declarations
                       (Buffer,
                        Unit,
                        Document,
                        Declared_Channel,
                        Arm_Value_Name,
                        "Arm_Length",
                        Arm_Type_Name,
                        "Arm_Success",
                        Select_Depth + 2,
                        State.Task_Body_Depth > 0);
                     Append_Line (Buffer, "begin", Select_Depth + 1);
                     Append_Staged_Channel_Call
                       (Buffer,
                        Unit,
                        Document,
                        Render_Expr (Unit, Document, Arm.Channel_Data.Channel_Name, State)
                        & ".Try_Receive",
                        Declared_Channel,
                        Arm_Value_Name,
                        "Arm_Length",
                        "Arm_Success",
                        Select_Depth + 2,
                        Force_Staged_Warnings => False,
                        Wrap_Task_Call_Warnings => State.Task_Body_Depth > 0);
                     if State.Task_Body_Depth > 0 then
                        Append_Task_If_Warning_Suppression (Buffer, Select_Depth + 2);
                     end if;
                     Append_Line (Buffer, "if Arm_Success then", Select_Depth + 2);
                     Append_Line (Buffer, "Select_Done := True;", Select_Depth + 3);
                     Append_Line
                       (Buffer,
                        Next_Arm_Name
                        & " := "
                        & Trim_Image (Long_Long_Integer (Next_Arm_Ordinal))
                        & ";",
                        Select_Depth + 3);
                     if State.Task_Body_Depth > 0
                       and then Delay_Arm_Count > 0
                     then
                        Append_Line
                          (Buffer,
                           "pragma Warnings (GNATprove, Off, ""is set by"", Reason => ""generated timer cancel result is intentionally ignored"");",
                           Select_Depth + 3);
                        Append_Line
                          (Buffer,
                           Select_Dispatcher_Cancel_Helper_Name (Item)
                           & " (Select_Handler_Cancelled);",
                           Select_Depth + 3);
                        Append_Line
                          (Buffer,
                           "pragma Warnings (GNATprove, On, ""is set by"");",
                           Select_Depth + 3);
                        Append_Line
                          (Buffer,
                           Dispatcher_Name & ".Reset;",
                           Select_Depth + 3);
                     end if;
                     Append_Staged_Channel_Length_Reconcile
                       (Buffer,
                        Unit,
                        Document,
                        State,
                        Declared_Channel,
                        Arm_Value_Name,
                        "Arm_Length",
                        Select_Depth + 3);
                     Render_Required_Statement_Suite
                       (Buffer,
                        Unit,
                        Document,
                        Arm.Channel_Data.Statements,
                        State,
                        Select_Depth + 3,
                        Return_Type);
                     if Arm_Has_Heap_Value
                       and then Statements_Fall_Through (Arm.Channel_Data.Statements)
                     then
                        if Arm_Needs_Local_Cleanup_Suppression then
                           Append_Local_Warning_Suppression (Buffer, Select_Depth + 3);
                        end if;
                        Render_Current_Cleanup_Frame (Buffer, State, Select_Depth + 3);
                        if Arm_Needs_Local_Cleanup_Suppression then
                           Append_Local_Warning_Restore (Buffer, Select_Depth + 3);
                        end if;
                     end if;
                     Append_Line (Buffer, "end if;", Select_Depth + 2);
                     if State.Task_Body_Depth > 0 then
                        Append_Task_If_Warning_Restore (Buffer, Select_Depth + 2);
                     end if;
                     Append_Line (Buffer, "end;", Select_Depth + 1);
                     Append_Line (Buffer, "end if;", Select_Depth);
                     if Arm_Has_Heap_Value then
                        Pop_Cleanup_Frame (State);
                     end if;
                  end Render_Channel_Precheck;

                  procedure Render_Channel_Precheck_At_Ordinal
                    (Arm_Ordinal  : Positive;
                     Select_Depth : Natural)
                  is
                     Current_Ordinal : Natural := 0;
                  begin
                     for Arm of Item.Arms loop
                        if Arm.Kind = CM.Select_Arm_Channel then
                           Current_Ordinal := Current_Ordinal + 1;
                           if Current_Ordinal = Arm_Ordinal then
                              Render_Channel_Precheck
                                (Arm,
                                 Arm_Ordinal,
                                 Select_Depth);
                              return;
                           end if;
                        elsif Arm.Kind /= CM.Select_Arm_Delay then
                           Raise_Unsupported
                             (State,
                              Arm.Span,
                              "unsupported select arm in Ada emission");
                        end if;
                     end loop;

                     Raise_Unsupported
                       (State,
                        Item.Span,
                        "missing select channel arm in Ada emission");
                  end Render_Channel_Precheck_At_Ordinal;

                  procedure Render_Select_Precheck
                    (Select_Depth : Natural) is
                  begin
                     if Channel_Arm_Count = 1 then
                        Render_Channel_Precheck_At_Ordinal (1, Select_Depth);
                        return;
                     end if;

                     Append_Line
                       (Buffer,
                        "for Select_Offset in 0 .. "
                        & Trim_Image (Long_Long_Integer (Channel_Arm_Count - 1))
                        & " loop",
                        Select_Depth);
                     Append_Line (Buffer, "exit when Select_Done;", Select_Depth + 1);
                     Append_Line (Buffer, "declare", Select_Depth + 1);
                     Append_Line
                       (Buffer,
                        "Select_Probe_Ordinal : constant Positive range 1 .. "
                        & Trim_Image (Long_Long_Integer (Channel_Arm_Count))
                        & " := Positive ((("
                        & Next_Arm_Name
                        & " - 1 + Select_Offset) mod "
                        & Trim_Image (Long_Long_Integer (Channel_Arm_Count))
                        & ") + 1);",
                        Select_Depth + 2);
                     Append_Line (Buffer, "begin", Select_Depth + 1);
                     Append_Line
                       (Buffer,
                        "case Select_Probe_Ordinal is",
                        Select_Depth + 2);
                     for Arm_Ordinal in 1 .. Channel_Arm_Count loop
                        Append_Line
                          (Buffer,
                           "when "
                           & Trim_Image (Long_Long_Integer (Arm_Ordinal))
                           & " =>",
                           Select_Depth + 3);
                        Render_Channel_Precheck_At_Ordinal
                          (Arm_Ordinal,
                           Select_Depth + 4);
                     end loop;
                     Append_Line (Buffer, "end case;", Select_Depth + 2);
                     Append_Line (Buffer, "end;", Select_Depth + 1);
                     Append_Line (Buffer, "end loop;", Select_Depth);
                  end Render_Select_Precheck;

                  procedure Render_Delay_Arm_Statements
                    (Select_Depth : Natural) is
                  begin
                     for Arm of Item.Arms loop
                        if Arm.Kind = CM.Select_Arm_Delay then
                           Render_Required_Statement_Suite
                             (Buffer,
                              Unit,
                              Document,
                              Arm.Delay_Data.Statements,
                              State,
                              Select_Depth,
                              Return_Type);
                           return;
                        end if;
                     end loop;
                  end Render_Delay_Arm_Statements;
               begin
                  for Arm of Item.Arms loop
                     if Arm.Kind = CM.Select_Arm_Channel then
                        Channel_Arm_Count := Channel_Arm_Count + 1;
                     elsif Arm.Kind = CM.Select_Arm_Delay then
                        Delay_Arm_Count := Delay_Arm_Count + 1;
                     end if;
                  end loop;

                  if Channel_Arm_Count = 0 then
                     Raise_Unsupported
                       (State,
                        Item.Span,
                        "select without channel arms is not supported in Ada emission");
                  end if;

                  if Delay_Arm_Count > 0 then
                     if Delay_Arm_Count /= 1 then
                        Raise_Unsupported
                          (State,
                           Item.Span,
                           "select with delay supports exactly one delay arm in Ada emission");
                     end if;

                     if State.Task_Body_Depth = 0 then
                        Append_Line (Buffer, "declare", Depth);
                        Append_Line (Buffer, "Select_Done : Boolean := False;", Depth + 1);
                        Append_Line (Buffer, "begin", Depth);
                        Render_Select_Precheck (Depth + 1);
                        Append_Line (Buffer, "if not Select_Done then", Depth + 1);
                        Append_Line
                          (Buffer,
                           "delay " & Delay_Expr_Image & ";",
                           Depth + 2);
                        Render_Delay_Arm_Statements (Depth + 2);
                        Append_Line (Buffer, "end if;", Depth + 1);
                        Append_Line (Buffer, "end;", Depth);
                     else
                        State.Needs_Ada_Real_Time := True;
                        Append_Line (Buffer, "declare", Depth);
                        Append_Line (Buffer, "Select_Done : Boolean := False;", Depth + 1);
                        Append_Line (Buffer, "Select_Timed_Out : Boolean;", Depth + 1);
                        Append_Line
                          (Buffer,
                           "Select_Handler_Cancelled : Boolean;",
                           Depth + 1);
                        Append_Line
                          (Buffer,
                           "Select_Delay_Span : constant Ada.Real_Time.Time_Span := "
                           & "Ada.Real_Time.To_Time_Span ("
                          & Delay_Expr_Image
                          & ");",
                           Depth + 1);
                        Append_Line
                          (Buffer,
                           "Select_Start : constant Ada.Real_Time.Time := "
                           & "Ada.Real_Time.Clock;",
                           Depth + 1);
                        Append_Line
                          (Buffer,
                           "Select_Deadline : constant Ada.Real_Time.Time :=",
                           Depth + 1);
                        Append_Line
                          (Buffer,
                           Select_Dispatcher_Name (Item)
                           & "_Compute_Deadline (Select_Start, Select_Delay_Span);",
                           Depth + 2);
                        Append_Line
                          (Buffer,
                           "Select_Timeout_Observed : Boolean;",
                           Depth + 1);
                        Append_Line (Buffer, "begin", Depth);
                        Append_Line
                          (Buffer,
                           Dispatcher_Name & ".Reset;",
                           Depth + 1);
                        Append_Line
                          (Buffer,
                           "Select_Timeout_Observed := Select_Start >= Select_Deadline;",
                           Depth + 1);
                        Append_Line
                          (Buffer,
                           "if not Select_Timeout_Observed then",
                           Depth + 1);
                        Append_Line
                          (Buffer,
                           Select_Dispatcher_Arm_Helper_Name (Item)
                           & " (Select_Deadline);",
                           Depth + 2);
                        Append_Line (Buffer, "end if;", Depth + 1);
                        Append_Line (Buffer, "loop", Depth + 1);
                        Render_Select_Precheck (Depth + 2);
                        Append_Line (Buffer, "exit when Select_Done;", Depth + 2);
                        Append_Line (Buffer, "if Select_Timeout_Observed then", Depth + 2);
                        Render_Delay_Arm_Statements (Depth + 3);
                        Append_Line (Buffer, "exit;", Depth + 3);
                        Append_Line (Buffer, "end if;", Depth + 2);
                        Append_Line
                          (Buffer,
                           Dispatcher_Name & ".Await (Select_Timed_Out);",
                           Depth + 2);
                        Append_Line
                          (Buffer,
                           "Select_Timeout_Observed := Select_Timed_Out;",
                           Depth + 2);
                        Append_Line (Buffer, "end loop;", Depth + 1);
                        Append_Line (Buffer, "end;", Depth);
                     end if;
                  else
                     Append_Line (Buffer, "declare", Depth);
                     Append_Line (Buffer, "Select_Done : Boolean := False;", Depth + 1);
                     Append_Line (Buffer, "Select_Timed_Out : Boolean;", Depth + 1);
                     Append_Line (Buffer, "begin", Depth);
                     Append_Line
                       (Buffer,
                        Dispatcher_Name & ".Reset;",
                        Depth + 1);
                     Append_Line (Buffer, "loop", Depth + 1);
                     Render_Select_Precheck (Depth + 2);
                     Append_Line (Buffer, "exit when Select_Done;", Depth + 2);
                     Append_Line
                       (Buffer,
                        "pragma Warnings (GNATprove, Off, ""is set by"", Reason => ""generated dispatcher wake result is intentionally ignored on no-delay select paths"");",
                        Depth + 2);
                     Append_Line
                       (Buffer,
                        Dispatcher_Name & ".Await (Select_Timed_Out);",
                        Depth + 2);
                     Append_Line
                       (Buffer,
                        "pragma Warnings (GNATprove, On, ""is set by"");",
                        Depth + 2);
                     Append_Line (Buffer, "end loop;", Depth + 1);
                     Append_Line (Buffer, "end;", Depth);
                  end if;
               end;
            when CM.Stmt_Delay =>
               State.Needs_Gnat_Adc := True;
               Append_Line
                 (Buffer,
                  "delay " & Render_Expr (Unit, Document, Item.Value, State) & ";",
                  Depth);
               when others =>
                  Raise_Unsupported
                    (State,
                     Item.Span,
                     "PR09 emitter does not yet support statement kind '"
                     & Item.Kind'Image
                     & "'");
            end case;
         end;
      end loop;
   end Render_Statements;

   procedure Render_Required_Statement_Suite
     (Buffer     : in out SU.Unbounded_String;
      Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Statements : CM.Statement_Access_Vectors.Vector;
      State      : in out Emit_State;
      Depth      : Natural;
      Return_Type : String := "";
      In_Loop    : Boolean := False) is
   begin
      if Statements.Is_Empty then
         Append_Line (Buffer, "null;", Depth);
         return;
      end if;
      Render_Statements (Buffer, Unit, Document, Statements, State, Depth, Return_Type, In_Loop);
   end Render_Required_Statement_Suite;

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

   function Is_Print_Call (Expr : CM.Expr_Access) return Boolean is
   begin
      return
        Expr /= null
        and then Expr.Kind = CM.Expr_Call
        and then FT.Lowercase (CM.Flatten_Name (Expr.Callee)) = "print";
   end Is_Print_Call;

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
            if Is_Wide_Integer_Type (Unit, Document, Target_Type)
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
      elsif Is_Wide_Integer_Type (Unit, Document, Target_Type)
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

      if AI.Is_Owner_Access (Target_Info)
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
            if Is_Integer_Type (Unit, Document, Target_Type)
              and then Has_Loop_Integer_Tracking (State, Tracked_Target_Name)
            then
               if In_Loop then
                  Invalidate_Loop_Integer (State, Tracked_Target_Name);
               elsif Try_Tracked_Static_Integer_Value (State, Stmt.Value, Static_Value) then
                  Bind_Loop_Integer (State, Tracked_Target_Name, Static_Value);
               else
                  Invalidate_Loop_Integer (State, Tracked_Target_Name);
               end if;
            end if;

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
        and then Is_Wide_Integer_Type (Unit, Document, Return_Type)
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
               and then AI.Is_Owner_Access (Return_Info)
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
        and then AI.Is_Owner_Access (Value_Info)
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
      elsif Is_Wide_Integer_Type (Unit, Document, Return_Type)
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
      elsif Is_Wide_Integer_Type (Unit, Document, Return_Type)
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

   procedure Mark_Wide_Declaration
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      State     : in out Emit_State;
      Decl      : CM.Resolved_Object_Decl) is
   begin
      if Is_Wide_Integer_Type (Unit, Document, Decl.Type_Info)
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
      if Is_Wide_Integer_Type (Unit, Document, Decl.Type_Info)
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
        and then AI.Is_Owner_Access (Info)
        and then Value.Kind in CM.Expr_Ident | CM.Expr_Select | CM.Expr_Resolved_Index
      then
         Append_Line
           (Buffer,
            Render_Expr (Unit, Document, Value, State) & " := null;",
            Depth);
      end if;
   end Append_Move_Null;

end Safe_Frontend.Ada_Emit.Statements;
