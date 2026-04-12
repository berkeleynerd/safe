with Ada.Characters.Handling;
with Ada.Containers;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Safe_Frontend.Ada_Emit.Internal;
with Safe_Frontend.Builtin_Types;
with Safe_Frontend.Ada_Emit.Types;

package body Safe_Frontend.Ada_Emit.Expressions is
   package BT renames Safe_Frontend.Builtin_Types;

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
   use AET;

   function Root_Name (Expr : CM.Expr_Access) return String renames AI.Root_Name;
   function Lookup_Channel
     (Unit : CM.Resolved_Unit;
      Name : String) return CM.Resolved_Channel_Decl renames AI.Lookup_Channel;
   function Render_Binary_Unary_Image
     (Unit       : CM.Resolved_Unit;
      Document   : GM.Mir_Document;
      Expr       : CM.Expr_Access;
      Inner_Image : String) return String;
   function Render_Binary_Operation_Image
     (Unit        : CM.Resolved_Unit;
      Document    : GM.Mir_Document;
      Expr        : CM.Expr_Access;
      Left_Image  : String;
      Right_Image : String) return String;

   function Starts_With (Text : String; Prefix : String) return Boolean renames AI.Starts_With;
   function Shared_Wrapper_Object_Name (Root_Name : String) return String renames AI.Shared_Wrapper_Object_Name;
   function Shared_Public_Helper_Base_Name (Root_Name : String) return String renames AI.Shared_Public_Helper_Base_Name;
   function Shared_Append_Name return String renames AI.Shared_Append_Name;
   function Shared_Pop_Last_Name return String renames AI.Shared_Pop_Last_Name;
   function Shared_Contains_Name return String renames AI.Shared_Contains_Name;
   function Shared_Get_Name return String renames AI.Shared_Get_Name;
   function Shared_Set_Name return String renames AI.Shared_Set_Name;
   function Shared_Remove_Name return String renames AI.Shared_Remove_Name;
   function Shared_Field_Setter_Name (Field_Name : String) return String renames AI.Shared_Field_Setter_Name;
   function Shared_Nested_Field_Setter_Name
     (Path_Names : FT.UString_Vectors.Vector) return String renames AI.Shared_Nested_Field_Setter_Name;
   function Is_Plain_Shared_Nested_Record
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Info     : GM.Type_Descriptor) return Boolean;
   function Binary_Result_Type_Name
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access) return String;
   function Binary_Base_Type_Name
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access) return String;

   function Is_Attribute_Selector (Name : String) return Boolean renames AET.Is_Attribute_Selector;
   function Tuple_Field_Name (Index : Positive) return String renames AET.Tuple_Field_Name;

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

   function Render_Record_Aggregate_For_Type
     (Unit      : CM.Resolved_Unit;
      Document  : GM.Mir_Document;
      Expr      : CM.Expr_Access;
      Type_Info : GM.Type_Descriptor;
      State     : in out Emit_State) return String
   is
      Record_Info : constant GM.Type_Descriptor := Base_Type (Unit, Document, Type_Info);
      Result      : SU.Unbounded_String := SU.To_Unbounded_String ("(");
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
                  (Ada_Safe_Name (FT.To_String (Constraint.Name))
                   & " => "
                   & Render_Scalar_Value (Constraint.Value));
            First_Association := False;
         end loop;
      end if;

      for Field of Expr.Fields loop
         declare
            Field_Type : GM.Type_Descriptor := (others => <>);
         begin
            for Item of Record_Info.Fields loop
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
                  (Ada_Safe_Name (FT.To_String (Field.Field_Name))
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
      State       : in out Emit_State) return String
   is
      Source_Type_Info : GM.Type_Descriptor := (others => <>);
      Target_Is_String : constant Boolean :=
        FT.Lowercase (FT.To_String (Target_Info.Kind)) = "string";
      Target_Base      : GM.Type_Descriptor := (others => <>);
      Has_Expr_Type  : Boolean := False;
   begin
      if Expr = null then
         return "";
      end if;

      Target_Base := Base_Type (Unit, Document, Target_Info);

      if Has_Text (Expr.Type_Name) then
         declare
            Found_Synthetic : Boolean := False;
         begin
            if Type_Info_From_Name
              (Unit, Document, FT.To_String (Expr.Type_Name), Source_Type_Info)
            then
               Has_Expr_Type := True;
            else
               Source_Type_Info :=
                 Synthetic_Bounded_String_Type
                   (FT.To_String (Expr.Type_Name), Found_Synthetic);
               Has_Expr_Type := Found_Synthetic;
            end if;
         end;
      end if;

      if not Has_Expr_Type then
         Has_Expr_Type := Resolve_Print_Type (Unit, Document, Expr, State, Source_Type_Info);
      end if;

      if Is_Bounded_String_Type (Target_Info) then
         Register_Bounded_String_Type (State, Target_Info);
         if Expr.Kind = CM.Expr_Resolved_Index and then Expr.Prefix /= null then
            declare
               Prefix_Type : constant GM.Type_Descriptor :=
                 Expr_Type_Info (Unit, Document, Expr.Prefix);
            begin
               if Is_Bounded_String_Type (Prefix_Type)
                 and then Prefix_Type.Length_Bound = Target_Info.Length_Bound
               then
                  declare
                     Low_Image : constant String :=
                       Render_Expr
                         (Unit,
                          Document,
                          Expr.Args (Expr.Args.First_Index),
                          State);
                     High_Image : constant String :=
                       (if Natural (Expr.Args.Length) = 1
                        then Low_Image
                        else
                          Render_Expr
                            (Unit,
                             Document,
                             Expr.Args (Expr.Args.First_Index + 1),
                             State));
                  begin
                     return
                       Bounded_String_Instance_Name (Target_Info)
                       & ".Slice_Bounded ("
                       & Render_Expr (Unit, Document, Expr.Prefix, State)
                       & ", "
                       & Low_Image
                       & ", "
                       & High_Image
                       & ")";
                  end;
               end if;
            end;
         elsif Has_Expr_Type
           and then Is_Bounded_String_Type (Source_Type_Info)
           and then Source_Type_Info.Length_Bound = Target_Info.Length_Bound
         then
            return Render_Expr (Unit, Document, Expr, State);
         end if;

         return
           Bounded_String_Instance_Name (Target_Info)
           & ".To_Bounded ("
           & Render_String_Expr (Unit, Document, Expr, State)
           & ")";
      elsif Expr.Kind = CM.Expr_Aggregate
        and then FT.Lowercase (FT.To_String (Target_Base.Kind)) = "record"
      then
         return Render_Record_Aggregate_For_Type (Unit, Document, Expr, Target_Info, State);
      elsif AI.Is_Owner_Access (Target_Info)
        and then Target_Info.Has_Target
        and then Expr.Kind in CM.Expr_Aggregate | CM.Expr_Tuple
      then
         declare
            Access_Target : constant GM.Type_Descriptor :=
              Resolve_Type_Name (Unit, Document, FT.To_String (Target_Info.Target));
         begin
            return
              Local_Allocate_Helper_Name (Target_Info)
              & " ("
              & Render_Type_Name (Access_Target)
              & "'"
              & (if Expr.Kind = CM.Expr_Aggregate
                 then
                   Render_Record_Aggregate_For_Type
                     (Unit, Document, Expr, Access_Target, State)
                 else Render_Expr (Unit, Document, Expr, State))
              & ")";
         end;
      elsif Is_Plain_String_Type (Unit, Document, Target_Info) then
         State.Needs_Safe_String_RT := True;
         return Render_Heap_String_Expr (Unit, Document, Expr, State);
      elsif Is_Growable_Array_Type (Unit, Document, Target_Info) then
         return Render_Growable_Array_Expr
           (Unit, Document, Expr, Target_Info, State);
      elsif FT.Lowercase (FT.To_String (Target_Base.Kind)) = "array"
        and then not Target_Base.Growable
        and then
          (Expr.Kind = CM.Expr_Array_Literal
           or else Expr.Kind in CM.Expr_Ident | CM.Expr_Select
           or else
             (Expr.Kind = CM.Expr_Resolved_Index
              and then Expr.Prefix /= null
              and then Is_Growable_Array_Type
                (Unit,
                 Document,
                 Expr_Type_Info
                   (Unit, Document, Expr.Prefix)))
           or else
             (Has_Expr_Type
              and then Is_Growable_Array_Type
                (Unit,
                 Document,
                 Source_Type_Info)))
      then
         return Render_Growable_As_Fixed
           (Unit, Document, Expr, Target_Info, State);
      elsif Target_Is_String
        and then not Is_Bounded_String_Type (Target_Info)
        and then Has_Expr_Type
        and then Is_Bounded_String_Type (Source_Type_Info)
      then
         return Render_String_Expr (Unit, Document, Expr, State);
      end if;

      return Render_Expr (Unit, Document, Expr, State);
   end Render_Expr_For_Target_Type;

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
        and then AI.Is_Access_Type (Lookup_Type (Unit, Document, FT.To_String (Expr.Prefix.Type_Name)))
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
          and then AI.Is_Access_Type
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

            if not Used_Formal then
               for Imported of Unit.Imported_Subprograms loop
                  declare
                     Imported_Name  : constant String :=
                       FT.Lowercase (FT.To_String (Imported.Name));
                     Imported_Short : constant String :=
                       FT.Lowercase (AET.Synthetic_Type_Tail_Name (FT.To_String (Imported.Name)));
                  begin
                     if Imported_Name = Lower_Callee
                       or else Imported_Short = Lower_Callee
                     then
                        declare
                           Position : Natural := 0;
                        begin
                           for Formal of Imported.Params loop
                              Position := Position + 1;
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
                     end if;
                  end;
                  exit when Used_Formal;
               end loop;
            end if;

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
      State    : in out Emit_State) return String
   is
      Result : SU.Unbounded_String;
   begin
      if Expr = null then
         Raise_Unsupported
           (State,
            FT.Null_Span,
            "encountered null expression during Ada emission");
      end if;

      declare
         Static_Boolean : Boolean := False;
      begin
         if Try_Static_Boolean_Value (State, Expr, Static_Boolean) then
            return (if Static_Boolean then "true" else "false");
         end if;
      end;

      case Expr.Kind is
         when CM.Expr_Int =>
            if Has_Text (Expr.Text) then
               return FT.To_String (Expr.Text);
            end if;
            return Trim_Wide_Image (Expr.Int_Value);
         when CM.Expr_Real =>
            if Has_Text (Expr.Text) then
               return FT.To_String (Expr.Text);
            end if;
            Raise_Unsupported
              (State,
               Expr.Span,
               "real literal missing source text");
         when CM.Expr_String =>
            if Has_Text (Expr.Type_Name) then
               declare
                  Literal_Type : GM.Type_Descriptor := (others => <>);
                  Has_Literal_Type : Boolean := False;
               begin
                  if Type_Info_From_Name
                    (Unit, Document, FT.To_String (Expr.Type_Name), Literal_Type)
                  then
                     Has_Literal_Type := True;
                  else
                     Literal_Type :=
                       Synthetic_Bounded_String_Type
                         (FT.To_String (Expr.Type_Name), Has_Literal_Type);
                  end if;

                  if Has_Literal_Type and then Is_Bounded_String_Type (Literal_Type) then
                     Register_Bounded_String_Type (State, Literal_Type);
                     if Has_Text (Expr.Text) then
                        return
                          Bounded_String_Instance_Name (Literal_Type)
                          & ".To_Bounded ("
                          & FT.To_String (Expr.Text)
                          & ")";
                     end if;
                  end if;
               end;
            end if;

            if Has_Text (Expr.Text) then
               return FT.To_String (Expr.Text);
            end if;
            Raise_Unsupported
              (State,
               Expr.Span,
               "text literal missing source text");
         when CM.Expr_Array_Literal =>
            if Has_Text (Expr.Type_Name) then
               declare
                  Literal_Type : constant GM.Type_Descriptor :=
                    Resolve_Type_Name
                      (Unit, Document, FT.To_String (Expr.Type_Name));
               begin
                  if Is_Growable_Array_Type (Unit, Document, Literal_Type) then
                     return
                       Render_Growable_Array_Expr
                         (Unit, Document, Expr, Literal_Type, State);
                  end if;
               end;
            end if;
            Result := SU.To_Unbounded_String ("(");
            for Index in Expr.Elements.First_Index .. Expr.Elements.Last_Index loop
               if Index /= Expr.Elements.First_Index then
                  Result := Result & SU.To_Unbounded_String (", ");
               end if;
               Result :=
                 Result
                 & SU.To_Unbounded_String
                     (Render_Expr
                        (Unit,
                         Document,
                         Expr.Elements (Index),
                         State));
            end loop;
            Result := Result & SU.To_Unbounded_String (")");
            return SU.To_String (Result);
         when CM.Expr_Bool =>
            return (if Expr.Bool_Value then "true" else "false");
         when CM.Expr_Enum_Literal =>
            return
              Render_Enum_Literal_Name
                (FT.To_String (Expr.Name), FT.To_String (Expr.Type_Name));
         when CM.Expr_Null =>
            return "null";
         when CM.Expr_Ident =>
            if FT.Lowercase (FT.To_String (Expr.Name)) = "ok"
              and then FT.Lowercase (FT.To_String (Expr.Type_Name)) = "result"
            then
               State.Needs_Ada_Strings_Unbounded := True;
               return Render_Result_Empty_Aggregate;
            end if;
            return Ada_Safe_Name (FT.To_String (Expr.Name));
         when CM.Expr_Select =>
            return Render_Select_Expr (Unit, Document, Expr, State);
         when CM.Expr_Resolved_Index =>
            return Render_Resolved_Index_Expr (Unit, Document, Expr, State);
         when CM.Expr_Conversion =>
            return Render_Conversion_Expr (Unit, Document, Expr, State);
         when CM.Expr_Call =>
            return Render_Call_Expr (Unit, Document, Expr, State);
         when CM.Expr_Allocator =>
            return "new " & Render_Expr (Unit, Document, Expr.Value, State);
         when CM.Expr_Aggregate =>
            return Render_Aggregate_Expr (Unit, Document, Expr, State);
         when CM.Expr_Tuple =>
            return Render_Tuple_Expr (Unit, Document, Expr, State);
         when CM.Expr_Annotated =>
            return Render_Annotated_Expr (Unit, Document, Expr, State);
         when CM.Expr_Unary =>
            return Render_Unary_Expr (Unit, Document, Expr, State);
         when CM.Expr_Binary =>
            return Render_Binary_Expr (Unit, Document, Expr, State);
         when CM.Expr_Subtype_Indication =>
            if Has_Text (Expr.Type_Name) then
               return Render_Type_Name (Unit, Document, FT.To_String (Expr.Type_Name));
            end if;
            Raise_Unsupported
              (State,
               Expr.Span,
               "subtype indication missing type name");
         when others =>
            Raise_Unsupported
              (State,
               Expr.Span,
               "PR09 emitter does not yet support expression kind '"
               & Expr.Kind'Image
               & "'");
      end case;
   end Render_Expr;

   function Render_Print_Argument
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String
   is
      Value_Image : constant String := Render_Expr (Unit, Document, Expr, State);
      Info        : GM.Type_Descriptor;
   begin
      if Expr.Kind = CM.Expr_String then
         return Render_String_Expr (Unit, Document, Expr, State);
      elsif Expr.Kind = CM.Expr_Bool then
         return "(if " & Value_Image & " then ""true"" else ""false"")";
      elsif Expr.Kind = CM.Expr_Int then
         return
           "Ada.Strings.Fixed.Trim (Long_Long_Integer'Image (Long_Long_Integer ("
           & Value_Image
           & ")), Ada.Strings.Both)";
      elsif Resolve_Print_Type (Unit, Document, Expr, State, Info) then
         declare
            Base_Info : constant GM.Type_Descriptor := Base_Type (Unit, Document, Info);
            Base_Kind : constant String := FT.Lowercase (FT.To_String (Base_Info.Kind));
            Base_Name : constant String := FT.Lowercase (FT.To_String (Base_Info.Name));
         begin
            if Is_Plain_String_Type (Unit, Document, Info)
              or else Is_Bounded_String_Type (Info)
            then
               return Render_String_Value_Image (Unit, Document, Expr, Info, State);
            elsif Base_Kind = "string" or else Base_Name = "string" then
               return Render_String_Expr (Unit, Document, Expr, State);
            elsif Base_Kind = "boolean" or else Base_Name = "boolean" then
               return "(if " & Value_Image & " then ""true"" else ""false"")";
            elsif Base_Kind = "enum" then
               return
                 "Ada.Characters.Handling.To_Lower (Ada.Strings.Fixed.Trim ("
                 & Render_Type_Name (Unit, Document, FT.To_String (Base_Info.Name))
                 & "'Image ("
                 & Value_Image
                 & "), Ada.Strings.Both))";
            elsif Is_Integer_Type (Unit, Document, Info) then
               return
                 "Ada.Strings.Fixed.Trim (Long_Long_Integer'Image (Long_Long_Integer ("
                 & Value_Image
                 & ")), Ada.Strings.Both)";
            end if;
         end;
      end if;

      Raise_Unsupported
        (State,
         Expr.Span,
         "print argument type was not resolved during Ada emission");
   end Render_Print_Argument;

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
      Expr     : CM.Expr_Access) return Boolean
   is
      function Uses_Wide_Arithmetic
        (Unit     : CM.Resolved_Unit;
         Document : GM.Mir_Document;
         Expr     : CM.Expr_Access) return Boolean
      is
         Operator : constant String :=
           (if Expr = null then "" else FT.To_String (Expr.Operator));
      begin
         if Expr = null then
            return False;
         end if;

         case Expr.Kind is
            when CM.Expr_Unary =>
               return
                 Operator = "-"
                 and then Is_Integer_Type (Unit, Document, FT.To_String (Expr.Type_Name));
            when CM.Expr_Binary =>
               if Operator in "+" | "-" | "*" | "/" | "mod" | "rem" then
                  return Is_Integer_Type (Unit, Document, FT.To_String (Expr.Type_Name));
               end if;
               return
                 Uses_Wide_Arithmetic (Unit, Document, Expr.Left)
                 or else Uses_Wide_Arithmetic (Unit, Document, Expr.Right);
            when CM.Expr_Conversion | CM.Expr_Annotated =>
               return Uses_Wide_Arithmetic (Unit, Document, Expr.Inner);
            when CM.Expr_Call | CM.Expr_Resolved_Index =>
               for Item of Expr.Args loop
                  if Uses_Wide_Arithmetic (Unit, Document, Item) then
                     return True;
                  end if;
               end loop;
               return False;
            when others =>
               return False;
         end case;
      end Uses_Wide_Arithmetic;
   begin
      if Expr = null then
         return False;
      elsif Uses_Wide_Arithmetic (Unit, Document, Expr) then
         return True;
      end if;

      case Expr.Kind is
         when CM.Expr_Ident =>
            return Is_Wide_Name (State, FT.To_String (Expr.Name));
         when CM.Expr_Unary | CM.Expr_Conversion | CM.Expr_Annotated =>
            return Uses_Wide_Value (Unit, Document, State, Expr.Inner);
         when CM.Expr_Binary =>
            return
              Uses_Wide_Value (Unit, Document, State, Expr.Left)
              or else Uses_Wide_Value (Unit, Document, State, Expr.Right);
         when CM.Expr_Call | CM.Expr_Resolved_Index =>
            for Item of Expr.Args loop
               if Uses_Wide_Value (Unit, Document, State, Item) then
                  return True;
               end if;
            end loop;
            return False;
         when CM.Expr_Select =>
            return Uses_Wide_Value (Unit, Document, State, Expr.Prefix);
         when others =>
            return False;
      end case;
   end Uses_Wide_Value;

   function Render_Channel_Send_Value
     (Unit         : CM.Resolved_Unit;
      Document     : GM.Mir_Document;
      State        : in out Emit_State;
      Channel_Expr : CM.Expr_Access;
      Value        : CM.Expr_Access) return String
   is
      Channel_Name : constant String :=
        (if Channel_Expr = null then "" else CM.Flatten_Name (Channel_Expr));
      Channel_Item : constant CM.Resolved_Channel_Decl :=
        Lookup_Channel (Unit, Channel_Name);
   begin
      if Has_Text (Channel_Item.Name)
        and then Is_Wide_Integer_Type (Unit, Document, Channel_Item.Element_Type)
        and then Uses_Wide_Value (Unit, Document, State, Value)
      then
         return
           Render_Type_Name (Channel_Item.Element_Type)
           & " ("
           & Render_Wide_Expr (Unit, Document, Value, State)
           & ")";
      end if;
      return Render_Expr (Unit, Document, Value, State);
   end Render_Channel_Send_Value;

   function Render_Wide_Expr
     (Unit     : CM.Resolved_Unit;
      Document : GM.Mir_Document;
      Expr     : CM.Expr_Access;
      State    : in out Emit_State) return String
   is
      Operator : constant String :=
        (if Expr = null then "" else Map_Operator (FT.To_String (Expr.Operator)));
   begin
      State.Needs_Safe_Runtime := True;

      if Expr = null then
         Raise_Unsupported
           (State,
            FT.Null_Span,
            "encountered null wide expression during Ada emission");
      end if;

      declare
         Static_Value : Long_Long_Integer := 0;
      begin
         if Try_Resolved_Static_Integer_Value (Unit, Document, State, Expr, Static_Value) then
            return "Safe_Runtime.Wide_Integer (" & Trim_Wide_Image (CM.Wide_Integer (Static_Value)) & ")";
         end if;
      end;

      case Expr.Kind is
         when CM.Expr_Int =>
            return "Safe_Runtime.Wide_Integer (" & Render_Expr (Unit, Document, Expr, State) & ")";
         when CM.Expr_Resolved_Index =>
            declare
               Result_Info    : constant GM.Type_Descriptor :=
                 Expr_Type_Info (Unit, Document, Expr);
               Static_Index   : Long_Long_Integer := 0;
               Static_Element : Long_Long_Integer := 0;
               Result_Image   : constant String := Render_Expr (Unit, Document, Expr, State);
            begin
               if Expr.Prefix /= null
                 and then Natural (Expr.Args.Length) = 1
                 and then Try_Resolved_Static_Integer_Value
                   (Unit,
                    Document,
                    State,
                    Expr.Args (Expr.Args.First_Index),
                    Static_Index)
                 and then Static_Index >= 1
                 and then Static_Index <= Long_Long_Integer (Positive'Last)
               then
                  declare
                     Position  : constant Positive := Positive (Natural (Static_Index));
                     Name_Text : constant String :=
                       (if Expr.Prefix.Kind = CM.Expr_Ident
                        then FT.To_String (Expr.Prefix.Name)
                        elsif Expr.Prefix.Kind = CM.Expr_Select
                        then CM.Flatten_Name (Expr.Prefix)
                        else "");
                  begin
                     if (Name_Text'Length /= 0
                         and then Try_Static_Integer_Binding
                           (State,
                            Static_Element_Binding_Name (Name_Text, Position),
                            Static_Element))
                       or else Try_Static_Integer_Array_Element_Expr
                         (Unit,
                          Expr.Prefix,
                          Position,
                          Static_Element)
                     then
                        return
                          "Safe_Runtime.Wide_Integer ("
                          & Trim_Wide_Image (CM.Wide_Integer (Static_Element))
                          & ")";
                     end if;
                  end;
               end if;

               if Is_Integer_Type (Unit, Document, Result_Info) then
                  return
                    "Safe_Runtime.Wide_Integer ("
                    & Render_Subtype_Indication (Unit, Document, Result_Info)
                    & "'("
                    & Result_Image
                    & "))";
               end if;
               return "Safe_Runtime.Wide_Integer (" & Result_Image & ")";
            end;
         when CM.Expr_Ident | CM.Expr_Select | CM.Expr_Call =>
            return "Safe_Runtime.Wide_Integer (" & Render_Expr (Unit, Document, Expr, State) & ")";
         when CM.Expr_Conversion =>
            if Has_Text (Expr.Type_Name)
              and then Is_Wide_Integer_Type (Unit, Document, FT.To_String (Expr.Type_Name))
              and then Expr.Inner /= null
            then
               return Render_Wide_Expr (Unit, Document, Expr.Inner, State);
            end if;
            return "Safe_Runtime.Wide_Integer (" & Render_Expr (Unit, Document, Expr, State) & ")";
         when CM.Expr_Unary =>
            return "(" & Operator & Render_Wide_Expr (Unit, Document, Expr.Inner, State) & ")";
         when CM.Expr_Binary =>
            if Operator in "+" | "-" | "*" | "/" | "mod" | "rem" then
               return
                 "("
                 & Render_Wide_Expr (Unit, Document, Expr.Left, State)
                 & " "
                 & Operator
                 & " "
                 & Render_Wide_Expr (Unit, Document, Expr.Right, State)
                 & ")";
            end if;
            return "Safe_Runtime.Wide_Integer (Boolean'Pos" & Render_Expr (Unit, Document, Expr, State) & ")";
         when others =>
            return "Safe_Runtime.Wide_Integer (" & Render_Expr (Unit, Document, Expr, State) & ")";
      end case;
   end Render_Wide_Expr;

   function Render_Wide_Expr_With_Target_Substitution
     (Unit          : CM.Resolved_Unit;
      Document      : GM.Mir_Document;
      Expr          : CM.Expr_Access;
      Target        : CM.Expr_Access;
      Replacement   : String;
      State         : in out Emit_State;
      Supported     : in out Boolean) return String
   is
      Operator : constant String :=
        (if Expr = null then "" else Map_Operator (FT.To_String (Expr.Operator)));
   begin
      State.Needs_Safe_Runtime := True;

      if not Supported then
         return "";
      elsif Expr = null or else Target = null then
         Supported := False;
         return "";
      elsif Exprs_Match (Expr, Target) then
         return "Safe_Runtime.Wide_Integer (" & Replacement & ")";
      end if;

      declare
         Static_Value : Long_Long_Integer := 0;
      begin
         if Try_Resolved_Static_Integer_Value (Unit, Document, State, Expr, Static_Value) then
            return "Safe_Runtime.Wide_Integer (" & Trim_Wide_Image (CM.Wide_Integer (Static_Value)) & ")";
         end if;
      end;

      case Expr.Kind is
         when CM.Expr_Int =>
            return
              "Safe_Runtime.Wide_Integer ("
              & Render_Expr_With_Target_Substitution
                  (Unit, Document, Expr, Target, Replacement, State, Supported)
              & ")";
         when CM.Expr_Ident | CM.Expr_Select | CM.Expr_Resolved_Index | CM.Expr_Call =>
            return
              "Safe_Runtime.Wide_Integer ("
              & Render_Expr_With_Target_Substitution
                  (Unit, Document, Expr, Target, Replacement, State, Supported)
              & ")";
         when CM.Expr_Conversion =>
            if Has_Text (Expr.Type_Name)
              and then Is_Wide_Integer_Type (Unit, Document, FT.To_String (Expr.Type_Name))
              and then Expr.Inner /= null
            then
               return
                 Render_Wide_Expr_With_Target_Substitution
                   (Unit, Document, Expr.Inner, Target, Replacement, State, Supported);
            end if;
            return
              "Safe_Runtime.Wide_Integer ("
              & Render_Expr_With_Target_Substitution
                  (Unit, Document, Expr, Target, Replacement, State, Supported)
              & ")";
         when CM.Expr_Unary =>
            return
              "("
              & Operator
              & Render_Wide_Expr_With_Target_Substitution
                  (Unit, Document, Expr.Inner, Target, Replacement, State, Supported)
              & ")";
         when CM.Expr_Binary =>
            if Operator in "+" | "-" | "*" | "/" | "mod" | "rem" then
               return
                 "("
                 & Render_Wide_Expr_With_Target_Substitution
                     (Unit, Document, Expr.Left, Target, Replacement, State, Supported)
                 & " "
                 & Operator
                 & " "
                 & Render_Wide_Expr_With_Target_Substitution
                     (Unit, Document, Expr.Right, Target, Replacement, State, Supported)
                 & ")";
            end if;
            return
              "Safe_Runtime.Wide_Integer (Boolean'Pos"
              & Render_Expr_With_Target_Substitution
                  (Unit, Document, Expr, Target, Replacement, State, Supported)
              & ")";
         when others =>
            return
              "Safe_Runtime.Wide_Integer ("
              & Render_Expr_With_Target_Substitution
                  (Unit, Document, Expr, Target, Replacement, State, Supported)
              & ")";
      end case;
   end Render_Wide_Expr_With_Target_Substitution;

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
      Supported     : in out Boolean) return String
   is
      Result : SU.Unbounded_String;
   begin
      if not Supported then
         return "";
      elsif Expr = null or else Target = null then
         Supported := False;
         return "";
      elsif Exprs_Match (Expr, Target) then
         return Replacement;
      end if;

      case Expr.Kind is
         when CM.Expr_Int | CM.Expr_Real | CM.Expr_String
            | CM.Expr_Bool | CM.Expr_Null | CM.Expr_Ident =>
            return Render_Expr (Unit, Document, Expr, State);
         when CM.Expr_Select =>
            declare
               Prefix_Image  : constant String :=
                 Render_Expr_With_Target_Substitution
                   (Unit, Document, Expr.Prefix, Target, Replacement, State, Supported);
               Selector_Name : constant String := FT.To_String (Expr.Selector);
            begin
               if not Supported then
                  return "";
               elsif Selector_Name = "access"
                 and then Expr.Prefix /= null
                 and then Has_Text (Expr.Prefix.Type_Name)
                 and then Has_Type (Unit, Document, FT.To_String (Expr.Prefix.Type_Name))
                 and then AI.Is_Access_Type
                   (Lookup_Type (Unit, Document, FT.To_String (Expr.Prefix.Type_Name)))
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
               return Prefix_Image & "." & Ada_Safe_Name (Selector_Name);
            end;
         when CM.Expr_Resolved_Index =>
            Result :=
              SU.To_Unbounded_String
                (Render_Expr_With_Target_Substitution
                   (Unit, Document, Expr.Prefix, Target, Replacement, State, Supported)
                 & " (");
            if not Supported then
               return "";
            end if;
            for Index in Expr.Args.First_Index .. Expr.Args.Last_Index loop
               if Index /= Expr.Args.First_Index then
                  Result := Result & SU.To_Unbounded_String (", ");
               end if;
               Result :=
                 Result
                 & SU.To_Unbounded_String
                     (Render_Expr_With_Target_Substitution
                        (Unit, Document, Expr.Args (Index), Target, Replacement, State, Supported));
               if not Supported then
                  return "";
               end if;
            end loop;
            Result := Result & SU.To_Unbounded_String (")");
            return SU.To_String (Result);
         when CM.Expr_Conversion =>
            declare
               Target_Image : constant String :=
                 (if Has_Text (Expr.Type_Name)
                     then Render_Type_Name (Unit, Document, FT.To_String (Expr.Type_Name))
                  else
                    Render_Expr_With_Target_Substitution
                      (Unit, Document, Expr.Target, Target, Replacement, State, Supported));
            begin
               return
                 Target_Image
                 & " ("
                 & Render_Expr_With_Target_Substitution
                     (Unit, Document, Expr.Inner, Target, Replacement, State, Supported)
                 & ")";
            end;
         when CM.Expr_Subtype_Indication =>
            if Has_Text (Expr.Type_Name) then
               return Render_Type_Name (Unit, Document, FT.To_String (Expr.Type_Name));
            end if;
            Supported := False;
            return "";
         when CM.Expr_Call =>
            declare
               Callee_Flat  : constant String := CM.Flatten_Name (Expr.Callee);
               Lower_Callee : constant String := FT.Lowercase (Callee_Flat);
               Callee_Image : SU.Unbounded_String;
            begin
               if Expr.Callee /= null
                 and then Expr.Callee.Kind = CM.Expr_Select
                 and then FT.To_String (Expr.Callee.Selector) = "access"
                 and then Expr.Callee.Prefix /= null
                 and then Has_Text (Expr.Callee.Prefix.Type_Name)
                 and then Has_Type (Unit, Document, FT.To_String (Expr.Callee.Prefix.Type_Name))
                 and then AI.Is_Access_Type
                   (Lookup_Type (Unit, Document, FT.To_String (Expr.Callee.Prefix.Type_Name)))
               then
                  Callee_Image :=
                    SU.To_Unbounded_String
                      (Render_Expr_With_Target_Substitution
                         (Unit,
                          Document,
                          Expr.Callee.Prefix,
                          Target,
                          Replacement,
                          State,
                          Supported));
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
                  Callee_Image :=
                    SU.To_Unbounded_String
                      (Render_Expr_With_Target_Substitution
                         (Unit,
                          Document,
                          Expr.Callee.Prefix,
                          Target,
                          Replacement,
                          State,
                          Supported)
                       & "'"
                       & FT.To_String (Expr.Callee.Selector));
               else
                  Callee_Image :=
                    SU.To_Unbounded_String
                      (Render_Expr_With_Target_Substitution
                         (Unit,
                          Document,
                          Expr.Callee,
                          Target,
                          Replacement,
                          State,
                          Supported));
               end if;

               if not Supported then
                  return "";
               elsif Lower_Callee = "ok" and then Expr.Args.Is_Empty then
                  State.Needs_Ada_Strings_Unbounded := True;
                  return Render_Result_Empty_Aggregate;
               elsif Lower_Callee = "fail" and then Natural (Expr.Args.Length) = 1 then
                  declare
                     Message_Image : constant String :=
                       Render_Expr_With_Target_Substitution
                         (Unit,
                          Document,
                          Expr.Args (Expr.Args.First_Index),
                          Target,
                          Replacement,
                          State,
                          Supported);
                  begin
                     if not Supported then
                        return "";
                     end if;
                     State.Needs_Ada_Strings_Unbounded := True;
                     return Render_Result_Fail_Aggregate (Message_Image);
                  end;
               elsif Expr.Args.Is_Empty then
                  return SU.To_String (Callee_Image);
               end if;

               Result := Callee_Image & SU.To_Unbounded_String (" (");
            end;
            for Index in Expr.Args.First_Index .. Expr.Args.Last_Index loop
               if Index /= Expr.Args.First_Index then
                  Result := Result & SU.To_Unbounded_String (", ");
               end if;
               Result :=
                 Result
                 & SU.To_Unbounded_String
                     (Render_Expr_With_Target_Substitution
                        (Unit,
                         Document,
                         Expr.Args (Index),
                         Target,
                         Replacement,
                         State,
                         Supported));
               if not Supported then
                  return "";
               end if;
            end loop;
            Result := Result & SU.To_Unbounded_String (")");
            return SU.To_String (Result);
         when CM.Expr_Aggregate =>
            Result := SU.To_Unbounded_String ("(");
            for Index in Expr.Fields.First_Index .. Expr.Fields.Last_Index loop
               declare
                  Field : constant CM.Aggregate_Field := Expr.Fields (Index);
               begin
                  if Index /= Expr.Fields.First_Index then
                     Result := Result & SU.To_Unbounded_String (", ");
                  end if;
                  Result :=
                    Result
                    & SU.To_Unbounded_String
                        (Ada_Safe_Name (FT.To_String (Field.Field_Name))
                         & " => "
                         & Render_Expr_With_Target_Substitution
                             (Unit,
                              Document,
                              Field.Expr,
                              Target,
                              Replacement,
                              State,
                              Supported));
                  if not Supported then
                     return "";
                  end if;
               end;
            end loop;
            Result := Result & SU.To_Unbounded_String (")");
            return SU.To_String (Result);
         when CM.Expr_Annotated =>
            declare
               Target_Image : constant String :=
                 Render_Expr_With_Target_Substitution
                   (Unit, Document, Expr.Target, Target, Replacement, State, Supported);
               Inner_Image  : constant String :=
                 Render_Expr_With_Target_Substitution
                   (Unit, Document, Expr.Inner, Target, Replacement, State, Supported);
            begin
               if not Supported then
                  return "";
               end if;
               return
                 Target_Image
                 & "'"
                 & (if Expr.Inner /= null and then Expr.Inner.Kind = CM.Expr_Aggregate
                    then Inner_Image
                    else "(" & Inner_Image & ")");
            end;
         when CM.Expr_Unary =>
            if FT.To_String (Expr.Operator) = "not"
              and then Has_Text (Expr.Type_Name)
              and then Is_Binary_Type (Unit, Document, FT.To_String (Expr.Type_Name))
            then
               declare
                  Inner_Image : constant String :=
                    Render_Expr_With_Target_Substitution
                      (Unit, Document, Expr.Inner, Target, Replacement, State, Supported);
               begin
                  if not Supported then
                     return "";
                  end if;
                  return Render_Binary_Unary_Image (Unit, Document, Expr, Inner_Image);
               end;
            end if;
            return
               "("
               & Map_Operator (FT.To_String (Expr.Operator))
               & (if FT.To_String (Expr.Operator) = "not" then " " else "")
               & Render_Expr_With_Target_Substitution
                   (Unit, Document, Expr.Inner, Target, Replacement, State, Supported)
               & ")";
         when CM.Expr_Binary =>
            if Expr.Left /= null
              and then Has_Text (Expr.Left.Type_Name)
              and then Is_Binary_Type (Unit, Document, FT.To_String (Expr.Left.Type_Name))
            then
               declare
                  Left_Image : constant String :=
                    Render_Expr_With_Target_Substitution
                      (Unit, Document, Expr.Left, Target, Replacement, State, Supported);
                  Right_Image : constant String :=
                    Render_Expr_With_Target_Substitution
                      (Unit, Document, Expr.Right, Target, Replacement, State, Supported);
               begin
                  if not Supported then
                     return "";
                  end if;
                  return
                    Render_Binary_Operation_Image
                      (Unit, Document, Expr, Left_Image, Right_Image);
               end;
            end if;
            return
              "("
              & Render_Expr_With_Target_Substitution
                  (Unit, Document, Expr.Left, Target, Replacement, State, Supported)
              & " "
              & Map_Operator (FT.To_String (Expr.Operator))
              & " "
              & Render_Expr_With_Target_Substitution
                  (Unit, Document, Expr.Right, Target, Replacement, State, Supported)
              & ")";
         when others =>
            Supported := False;
            return "";
      end case;
   end Render_Expr_With_Target_Substitution;

   function Render_Expr_With_Old_Substitution
     (Unit          : CM.Resolved_Unit;
      Document      : GM.Mir_Document;
      Expr          : CM.Expr_Access;
      Target        : CM.Expr_Access;
      State         : in out Emit_State;
      Supported     : in out Boolean) return String
   is
   begin
      if Target = null then
         Supported := False;
         return "";
      end if;

      return
        Render_Expr_With_Target_Substitution
          (Unit,
           Document,
           Expr,
           Target,
           Render_Expr (Unit, Document, Target, State) & "'Old",
           State,
           Supported);
   end Render_Expr_With_Old_Substitution;

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

   function Apply_Name_Replacements
     (Text       : String;
      From_Names : FT.UString_Vectors.Vector;
      To_Names   : FT.UString_Vectors.Vector) return String
   is
      Result : SU.Unbounded_String := SU.To_Unbounded_String (Text);
   begin
      if From_Names.Length /= To_Names.Length then
         Raise_Internal
           ("structural traversal replacement table length mismatch during Ada emission");
      end if;

      if From_Names.Is_Empty then
         return Text;
      end if;

      for Index in From_Names.First_Index .. From_Names.Last_Index loop
         Result :=
           SU.To_Unbounded_String
             (Replace_Identifier_Token
                (SU.To_String (Result),
                 FT.To_String (From_Names (Index)),
                 FT.To_String (To_Names (Index))));
      end loop;
      return SU.To_String (Result);
   end Apply_Name_Replacements;
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

   function Static_Element_Binding_Name
     (Name     : String;
      Position : Positive) return String is
   begin
      return Name & "(" & Trim_Image (Long_Long_Integer (Position)) & ")";
   end Static_Element_Binding_Name;

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

   function Map_Operator (Operator : String) return String is
   begin
      if Operator = "!=" then
         return "/=";
      elsif Operator = "==" then
         return "=";
      end if;
      return Operator;
   end Map_Operator;

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

end Safe_Frontend.Ada_Emit.Expressions;
