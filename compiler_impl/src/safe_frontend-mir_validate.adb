with Ada.Containers;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Safe_Frontend.Mir_Json;
with Safe_Frontend.Types;

package body Safe_Frontend.Mir_Validate is
   package FT renames Safe_Frontend.Types;
   package GM renames Safe_Frontend.Mir_Model;
   package US renames Ada.Strings.Unbounded;

   use type Ada.Containers.Count_Type;
   use type GM.Expr_Access;
   use type GM.Expr_Kind;
   use type GM.Mir_Format_Kind;
   use type GM.Op_Kind;
   use type GM.Ownership_Effect_Kind;
   use type GM.Select_Arm_Kind;
   use type GM.Terminator_Kind;

   Validation_Error : exception;

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Validation_Error with Message;
      end if;
   end Require;

   function Image (Item : Natural) return String is
   begin
      return Ada.Strings.Fixed.Trim (Natural'Image (Item), Ada.Strings.Both);
   end Image;

   function Text (Item : FT.UString) return String is
   begin
      return FT.To_String (Item);
   end Text;

   function Has_Text (Item : FT.UString) return Boolean is
   begin
      return Text (Item) /= "";
   end Has_Text;

   function Contains
     (Items : FT.UString_Vectors.Vector;
      Value : String) return Boolean
   is
   begin
      for Item of Items loop
         if Text (Item) = Value then
            return True;
         end if;
      end loop;
      return False;
   end Contains;

   function Render (Items : FT.UString_Vectors.Vector) return String is
      Result : US.Unbounded_String := US.To_Unbounded_String ("[");
   begin
      if not Items.Is_Empty then
         for Index in Items.First_Index .. Items.Last_Index loop
            if Index > Items.First_Index then
               US.Append (Result, ", ");
            end if;
            US.Append (Result, Text (Items (Index)));
         end loop;
      end if;
      US.Append (Result, "]");
      return US.To_String (Result);
   end Render;

   function Equal_Vectors
     (Left  : FT.UString_Vectors.Vector;
      Right : FT.UString_Vectors.Vector) return Boolean
   is
   begin
      if Left.Length /= Right.Length then
         return False;
      end if;
      if Left.Is_Empty then
         return True;
      end if;
      for Index in Left.First_Index .. Left.Last_Index loop
         if Text (Left (Index)) /= Text (Right (Index)) then
            return False;
         end if;
      end loop;
      return True;
   end Equal_Vectors;

   procedure Validate_Type_Descriptor
     (Value : GM.Type_Descriptor;
      Where : String);

   procedure Validate_Expr
     (Value : GM.Expr_Access;
      Where : String);

   procedure Validate_Local
     (Value  : GM.Local_Entry;
      Format : GM.Mir_Format_Kind;
      Where  : String);

   procedure Validate_Channel
     (Value : GM.Channel_Entry;
      Where : String);

   procedure Validate_External_Param
     (Value : GM.Local_Entry;
      Where : String);

   procedure Validate_External_Effect_Summary
     (Value : GM.External_Effect_Summary;
      Where : String);

   procedure Validate_External_Channel_Summary
     (Value : GM.External_Channel_Summary;
      Where : String);

   procedure Validate_External
     (Value : GM.External_Entry;
      Where : String);

   procedure Validate_Select_Arm
     (Value           : GM.Select_Arm_Entry;
      Valid_Block_Ids : FT.UString_Vectors.Vector;
      Valid_Scope_Ids : FT.UString_Vectors.Vector;
      Valid_Local_Ids : FT.UString_Vectors.Vector;
      Where           : String);

   procedure Validate_Scope
     (Value           : GM.Scope_Entry;
      Valid_Scope_Ids : FT.UString_Vectors.Vector;
      Valid_Local_Ids : FT.UString_Vectors.Vector;
      Valid_Block_Ids : FT.UString_Vectors.Vector;
      Where           : String);

   procedure Validate_Block
     (Value           : GM.Block_Entry;
      Format          : GM.Mir_Format_Kind;
      Valid_Block_Ids : FT.UString_Vectors.Vector;
      Valid_Scope_Ids : FT.UString_Vectors.Vector;
      Valid_Local_Ids : FT.UString_Vectors.Vector;
      Where           : String);

   procedure Validate_Graph
     (Value       : GM.Graph_Entry;
      Graph_Index : Positive;
      Format      : GM.Mir_Format_Kind);

   procedure Validate_Type_Descriptor
     (Value : GM.Type_Descriptor;
      Where : String)
   is
   begin
      Require (Has_Text (Value.Name), Where & ": missing type name");
      Require (Has_Text (Value.Kind), Where & ": missing type kind");
      if FT.To_String (Value.Kind) = "binary" then
         Require (Value.Has_Bit_Width, Where & ": binary type is missing bit_width");
      end if;

      if not Value.Index_Types.Is_Empty then
         for Index in Value.Index_Types.First_Index .. Value.Index_Types.Last_Index loop
            Require
              (Has_Text (Value.Index_Types (Index)),
               Where & ".index_types[" & Image (Index - 1) & "]: invalid type name");
         end loop;
      end if;

      if not Value.Fields.Is_Empty then
         for Index in Value.Fields.First_Index .. Value.Fields.Last_Index loop
            declare
               Field : constant GM.Type_Field := Value.Fields (Index);
            begin
               Require
                 (Has_Text (Field.Name),
                  Where & ".fields[" & Image (Index - 1) & "]: missing field name");
               Require
                 (Has_Text (Field.Type_Name),
                  Where & ".fields[" & Image (Index - 1) & "]: missing field type");
            end;
         end loop;
      end if;

      if Value.Has_Component_Type then
         Require (Has_Text (Value.Component_Type), Where & ": missing component_type");
      end if;
      if Value.Has_Target then
         Require (Has_Text (Value.Target), Where & ": missing target");
      end if;
      if Value.Has_Base then
         Require (Has_Text (Value.Base), Where & ": missing base");
      end if;
      if Value.Has_Digits_Text then
         Require (Has_Text (Value.Digits_Text), Where & ": missing digits_text");
      end if;
      if Value.Has_Float_Low_Text then
         Require (Has_Text (Value.Float_Low_Text), Where & ": missing float_low_text");
      end if;
      if Value.Has_Float_High_Text then
         Require (Has_Text (Value.Float_High_Text), Where & ": missing float_high_text");
      end if;
      if Value.Has_Discriminant then
         Require (Has_Text (Value.Discriminant_Name), Where & ": missing discriminant_name");
         Require (Has_Text (Value.Discriminant_Type), Where & ": missing discriminant_type");
      end if;
      if not Value.Variant_Fields.Is_Empty then
         for Index in Value.Variant_Fields.First_Index .. Value.Variant_Fields.Last_Index loop
            declare
               Variant_Field : constant GM.Variant_Field := Value.Variant_Fields (Index);
            begin
               Require
                 (Has_Text (Variant_Field.Name),
                  Where & ".variant_fields[" & Image (Index - 1) & "]: missing field name");
               Require
                 (Has_Text (Variant_Field.Type_Name),
                  Where & ".variant_fields[" & Image (Index - 1) & "]: missing field type");
            end;
         end loop;
      end if;
      if Value.Has_Access_Role then
         Require (Has_Text (Value.Access_Role), Where & ": invalid access_role");
      end if;
   end Validate_Type_Descriptor;

   procedure Validate_Expr
     (Value : GM.Expr_Access;
      Where : String)
   is
   begin
      Require (Value /= null, Where & ": expression is missing");
      Require (Value.Kind /= GM.Expr_Unknown, Where & ": unsupported expression");

      case Value.Kind is
         when GM.Expr_Int | GM.Expr_Real | GM.Expr_String
            | GM.Expr_Bool | GM.Expr_Null =>
            null;
         when GM.Expr_Ident =>
            Require (Has_Text (Value.Name), Where & ": missing identifier name");
         when GM.Expr_Select =>
            Validate_Expr (Value.Prefix, Where & ".prefix");
            Require (Has_Text (Value.Selector), Where & ": missing selector");
         when GM.Expr_Resolved_Index =>
            Validate_Expr (Value.Prefix, Where & ".prefix");
            Require (not Value.Indices.Is_Empty, Where & ": indices must be non-empty");
            for Index in Value.Indices.First_Index .. Value.Indices.Last_Index loop
               Validate_Expr
                 (Value.Indices (Index),
                  Where & ".indices[" & Image (Index - 1) & "]");
            end loop;
         when GM.Expr_Conversion =>
            Require (Has_Text (Value.Name), Where & ": missing conversion target");
            Validate_Expr (Value.Inner, Where & ".expr");
         when GM.Expr_Call =>
            Validate_Expr (Value.Callee, Where & ".callee");
            if not Value.Args.Is_Empty then
               for Index in Value.Args.First_Index .. Value.Args.Last_Index loop
                  Validate_Expr
                    (Value.Args (Index),
                     Where & ".args[" & Image (Index - 1) & "]");
               end loop;
            end if;
         when GM.Expr_Allocator =>
            Validate_Expr (Value.Value, Where & ".value");
         when GM.Expr_Aggregate =>
            if not Value.Fields.Is_Empty then
               for Index in Value.Fields.First_Index .. Value.Fields.Last_Index loop
                  declare
                     Field : constant GM.Aggregate_Field := Value.Fields (Index);
                  begin
                     if Has_Text (Field.Field) then
                        null;
                     end if;
                     Validate_Expr
                       (Field.Expr,
                        Where & ".fields[" & Image (Index - 1) & "].expr");
                  end;
               end loop;
            end if;
         when GM.Expr_Array_Literal =>
            if not Value.Elements.Is_Empty then
               for Index in Value.Elements.First_Index .. Value.Elements.Last_Index loop
                  Validate_Expr
                    (Value.Elements (Index),
                     Where & ".elements[" & Image (Index - 1) & "]");
               end loop;
            end if;
         when GM.Expr_Tuple =>
            Require (Natural (Value.Elements.Length) >= 2, Where & ": tuple expressions must have at least two elements");
            for Index in Value.Elements.First_Index .. Value.Elements.Last_Index loop
               Validate_Expr
                 (Value.Elements (Index),
                  Where & ".elements[" & Image (Index - 1) & "]");
            end loop;
         when GM.Expr_Annotated =>
            Validate_Expr (Value.Inner, Where & ".value");
         when GM.Expr_Unary =>
            Require (Has_Text (Value.Operator), Where & ": missing unary operator");
            Validate_Expr (Value.Inner, Where & ".expr");
         when GM.Expr_Binary =>
            Require (Has_Text (Value.Operator), Where & ": missing binary operator");
            Validate_Expr (Value.Left, Where & ".left");
            Validate_Expr (Value.Right, Where & ".right");
         when GM.Expr_Unknown =>
            null;
      end case;
   end Validate_Expr;

   procedure Validate_Channel
     (Value : GM.Channel_Entry;
      Where : String)
   is
   begin
      Require (Has_Text (Value.Name), Where & ": missing channel name");
      Require (Value.Capacity > 0, Where & ": channel capacity must be positive");
      if Value.Has_Required_Ceiling then
         Require
           (Value.Required_Ceiling > 0,
            Where & ": required_ceiling must be positive when present");
      end if;
      Validate_Type_Descriptor (Value.Element_Type, Where & ".element_type");
   end Validate_Channel;

   procedure Validate_External_Param
     (Value : GM.Local_Entry;
      Where : String)
   is
   begin
      Require (Has_Text (Value.Name), Where & ": missing parameter name");
      Require (Has_Text (Value.Mode), Where & ": missing parameter mode");
      Validate_Type_Descriptor (Value.Type_Info, Where & ".type");
   end Validate_External_Param;

   procedure Validate_External_Effect_Summary
     (Value : GM.External_Effect_Summary;
      Where : String)
   is
   begin
      if not Value.Reads.Is_Empty then
         for Index in Value.Reads.First_Index .. Value.Reads.Last_Index loop
            Require
              (Has_Text (Value.Reads (Index)),
               Where & ".reads[" & Image (Index - 1) & "]: invalid name");
         end loop;
      end if;
      if not Value.Writes.Is_Empty then
         for Index in Value.Writes.First_Index .. Value.Writes.Last_Index loop
            Require
              (Has_Text (Value.Writes (Index)),
               Where & ".writes[" & Image (Index - 1) & "]: invalid name");
         end loop;
      end if;
      if not Value.Inputs.Is_Empty then
         for Index in Value.Inputs.First_Index .. Value.Inputs.Last_Index loop
            Require
              (Has_Text (Value.Inputs (Index)),
               Where & ".inputs[" & Image (Index - 1) & "]: invalid name");
         end loop;
      end if;
      if not Value.Outputs.Is_Empty then
         for Index in Value.Outputs.First_Index .. Value.Outputs.Last_Index loop
            Require
              (Has_Text (Value.Outputs (Index)),
               Where & ".outputs[" & Image (Index - 1) & "]: invalid name");
         end loop;
      end if;
      if not Value.Depends.Is_Empty then
         for Index in Value.Depends.First_Index .. Value.Depends.Last_Index loop
            declare
               Dep : constant GM.Summary_Depends_Entry := Value.Depends (Index);
            begin
               Require
                 (Has_Text (Dep.Output_Name),
                  Where & ".depends[" & Image (Index - 1) & "]: missing output_name");
               if not Dep.Inputs.Is_Empty then
                  for Input_Index in Dep.Inputs.First_Index .. Dep.Inputs.Last_Index loop
                     Require
                       (Has_Text (Dep.Inputs (Input_Index)),
                        Where & ".depends[" & Image (Index - 1) & "].inputs[" &
                        Image (Input_Index - 1) & "]: invalid name");
                  end loop;
               end if;
            end;
         end loop;
      end if;
   end Validate_External_Effect_Summary;

   procedure Validate_External_Channel_Summary
     (Value : GM.External_Channel_Summary;
      Where : String)
   is
   begin
      if not Value.Channels.Is_Empty then
         for Index in Value.Channels.First_Index .. Value.Channels.Last_Index loop
            Require
              (Has_Text (Value.Channels (Index)),
               Where & ".channels[" & Image (Index - 1) & "]: invalid channel name");
         end loop;
      end if;
      if not Value.Sends.Is_Empty then
         for Index in Value.Sends.First_Index .. Value.Sends.Last_Index loop
            Require
              (Has_Text (Value.Sends (Index)),
               Where & ".sends[" & Image (Index - 1) & "]: invalid channel name");
         end loop;
      end if;
      if not Value.Receives.Is_Empty then
         for Index in Value.Receives.First_Index .. Value.Receives.Last_Index loop
            Require
              (Has_Text (Value.Receives (Index)),
               Where & ".receives[" & Image (Index - 1) & "]: invalid channel name");
         end loop;
      end if;
   end Validate_External_Channel_Summary;

   procedure Validate_External
     (Value : GM.External_Entry;
      Where : String)
   is
   begin
      Require (Has_Text (Value.Name), Where & ": missing external name");
      Require (Has_Text (Value.Kind), Where & ": missing external kind");
      Require (Has_Text (Value.Signature), Where & ": missing external signature");
      if not Value.Params.Is_Empty then
         for Index in Value.Params.First_Index .. Value.Params.Last_Index loop
            Validate_External_Param
              (Value.Params (Index),
               Where & ".params[" & Image (Index - 1) & "]");
         end loop;
      end if;
      if Value.Has_Return_Type then
         Validate_Type_Descriptor (Value.Return_Type, Where & ".return_type");
      end if;
      Validate_External_Effect_Summary (Value.Effect_Summary, Where & ".effect_summary");
      Validate_External_Channel_Summary
        (Value.Channel_Summary,
         Where & ".channel_access_summary");
   end Validate_External;

   procedure Validate_Select_Arm
     (Value           : GM.Select_Arm_Entry;
      Valid_Block_Ids : FT.UString_Vectors.Vector;
      Valid_Scope_Ids : FT.UString_Vectors.Vector;
      Valid_Local_Ids : FT.UString_Vectors.Vector;
      Where           : String)
   is
   begin
      case Value.Kind is
         when GM.Select_Arm_Channel =>
            Require
              (Has_Text (Value.Channel_Data.Channel_Name),
               Where & ": missing channel_name");
            Require
              (Has_Text (Value.Channel_Data.Variable_Name),
               Where & ": missing variable_name");
            Require
              (Contains (Valid_Scope_Ids, Text (Value.Channel_Data.Scope_Id)),
               Where & ": invalid scope_id");
            Require
              (Contains (Valid_Local_Ids, Text (Value.Channel_Data.Local_Id)),
               Where & ": invalid local_id");
            Require
              (Contains (Valid_Block_Ids, Text (Value.Channel_Data.Target)),
               Where & ": invalid target");
            Validate_Type_Descriptor (Value.Channel_Data.Type_Info, Where & ".type");
         when GM.Select_Arm_Delay =>
            Validate_Expr (Value.Delay_Data.Duration_Expr, Where & ".duration_expr");
            Require
              (Contains (Valid_Block_Ids, Text (Value.Delay_Data.Target)),
               Where & ": invalid target");
         when others =>
            Require (False, Where & ": unsupported select arm kind");
      end case;
   end Validate_Select_Arm;

   procedure Validate_Local
     (Value  : GM.Local_Entry;
      Format : GM.Mir_Format_Kind;
      Where  : String)
   is
   begin
      Require (Has_Text (Value.Id), Where & ": missing local id");
      Require (Has_Text (Value.Name), Where & ": missing local name");
      Validate_Type_Descriptor (Value.Type_Info, Where & ".type");
      if Format = GM.Mir_V2 then
         Require (Has_Text (Value.Scope_Id), Where & ": mir-v2 locals must have scope_id");
      end if;
   end Validate_Local;

   procedure Validate_Scope
     (Value           : GM.Scope_Entry;
      Valid_Scope_Ids : FT.UString_Vectors.Vector;
      Valid_Local_Ids : FT.UString_Vectors.Vector;
      Valid_Block_Ids : FT.UString_Vectors.Vector;
      Where           : String)
   is
   begin
      Require (Has_Text (Value.Id), Where & ": missing scope id");
      Require (Has_Text (Value.Kind), Where & ": missing scope kind");

      if Value.Has_Parent_Scope then
         Require
           (Contains (Valid_Scope_Ids, Text (Value.Parent_Scope_Id)),
            Where & ": invalid parent_scope_id");
      end if;

      if Has_Text (Value.Entry_Block) then
         Require
           (Contains (Valid_Block_Ids, Text (Value.Entry_Block)),
            Where & ": invalid entry_block");
      end if;

      if not Value.Local_Ids.Is_Empty then
         for Index in Value.Local_Ids.First_Index .. Value.Local_Ids.Last_Index loop
            Require
              (Contains (Valid_Local_Ids, Text (Value.Local_Ids (Index))),
               Where & ".local_ids[" & Image (Index - 1) & "]: invalid local id");
         end loop;
      end if;

      if not Value.Exit_Blocks.Is_Empty then
         for Index in Value.Exit_Blocks.First_Index .. Value.Exit_Blocks.Last_Index loop
            Require
              (Contains (Valid_Block_Ids, Text (Value.Exit_Blocks (Index))),
               Where & ".exit_blocks[" & Image (Index - 1) & "]: invalid block id");
         end loop;
      end if;
   end Validate_Scope;

   procedure Validate_Block
     (Value           : GM.Block_Entry;
      Format          : GM.Mir_Format_Kind;
      Valid_Block_Ids : FT.UString_Vectors.Vector;
      Valid_Scope_Ids : FT.UString_Vectors.Vector;
      Valid_Local_Ids : FT.UString_Vectors.Vector;
      Where           : String)
   is
   begin
      Require (Has_Text (Value.Id), Where & ": missing block id");

      if Format = GM.Mir_V2 then
         Require
           (Has_Text (Value.Active_Scope_Id),
            Where & ": mir-v2 blocks must have active_scope_id");
         Require
           (Contains (Valid_Scope_Ids, Text (Value.Active_Scope_Id)),
            Where & ": invalid active_scope_id");
      end if;

      if not Value.Ops.Is_Empty then
         for Index in Value.Ops.First_Index .. Value.Ops.Last_Index loop
            declare
               Op       : constant GM.Op_Entry := Value.Ops (Index);
               Op_Where : constant String := Where & ".ops[" & Image (Index - 1) & "]";
            begin
               Require (Op.Kind /= GM.Op_Unknown, Op_Where & ": unsupported op kind");

               case Op.Kind is
                  when GM.Op_Scope_Enter | GM.Op_Scope_Exit =>
                     Require
                       (Has_Text (Op.Scope_Id),
                        Op_Where & ": " & GM.Image (Op.Kind) & " missing scope_id");
                     if Format = GM.Mir_V2 then
                        Require
                          (Contains (Valid_Scope_Ids, Text (Op.Scope_Id)),
                           Op_Where & ": invalid scope_id");
                     end if;
                  when GM.Op_Assign =>
                     if Format = GM.Mir_V2 then
                        Require
                          (Op.Ownership_Effect /= GM.Ownership_Invalid,
                           Op_Where & ": invalid ownership_effect");
                        Require
                          (Has_Text (Op.Type_Name),
                           Op_Where & ": missing op type");
                        Require
                          (Op.Has_Declaration_Init,
                           Op_Where & ": mir-v2 assign ops must include declaration_init");
                        Require
                          (Op.Declaration_Init_Valid,
                           Op_Where & ": invalid declaration_init");
                     end if;
                     Validate_Expr (Op.Target, Op_Where & ".target");
                     Validate_Expr (Op.Value, Op_Where & ".value");
                  when GM.Op_Call =>
                     if Format = GM.Mir_V2 then
                        Require
                          (Op.Ownership_Effect /= GM.Ownership_Invalid,
                           Op_Where & ": invalid ownership_effect");
                        Require
                          (Has_Text (Op.Type_Name),
                           Op_Where & ": missing op type");
                     end if;
                     Validate_Expr (Op.Value, Op_Where & ".value");
                  when GM.Op_Channel_Send =>
                     Require
                       (Op.Ownership_Effect /= GM.Ownership_Invalid,
                        Op_Where & ": invalid ownership_effect");
                     Require (Has_Text (Op.Type_Name), Op_Where & ": missing op type");
                     Validate_Expr (Op.Channel, Op_Where & ".channel");
                     Validate_Expr (Op.Value, Op_Where & ".value");
                  when GM.Op_Channel_Receive =>
                     Require
                       (Op.Ownership_Effect /= GM.Ownership_Invalid,
                        Op_Where & ": invalid ownership_effect");
                     Require (Has_Text (Op.Type_Name), Op_Where & ": missing op type");
                     Validate_Expr (Op.Channel, Op_Where & ".channel");
                     Validate_Expr (Op.Target, Op_Where & ".target");
                  when GM.Op_Channel_Try_Send =>
                     Require
                       (Op.Ownership_Effect /= GM.Ownership_Invalid,
                        Op_Where & ": invalid ownership_effect");
                     Require (Has_Text (Op.Type_Name), Op_Where & ": missing op type");
                     Validate_Expr (Op.Channel, Op_Where & ".channel");
                     Validate_Expr (Op.Value, Op_Where & ".value");
                     Validate_Expr (Op.Success_Target, Op_Where & ".success_target");
                  when GM.Op_Channel_Try_Receive =>
                     Require
                       (Op.Ownership_Effect /= GM.Ownership_Invalid,
                        Op_Where & ": invalid ownership_effect");
                     Require (Has_Text (Op.Type_Name), Op_Where & ": missing op type");
                     Validate_Expr (Op.Channel, Op_Where & ".channel");
                     Validate_Expr (Op.Target, Op_Where & ".target");
                     Validate_Expr (Op.Success_Target, Op_Where & ".success_target");
                  when GM.Op_Delay =>
                     Require
                       (Op.Ownership_Effect /= GM.Ownership_Invalid,
                        Op_Where & ": invalid ownership_effect");
                     Require (Has_Text (Op.Type_Name), Op_Where & ": missing op type");
                     Validate_Expr (Op.Value, Op_Where & ".value");
                  when GM.Op_Unknown =>
                     null;
               end case;
            end;
         end loop;
      end if;

      Require
        (Value.Terminator.Kind /= GM.Terminator_Unknown,
         Where & ": missing or invalid terminator");

      case Value.Terminator.Kind is
         when GM.Terminator_Jump =>
            Require
              (Contains (Valid_Block_Ids, Text (Value.Terminator.Target)),
               Where & ".terminator: invalid jump target");
         when GM.Terminator_Branch =>
            Require
              (Contains (Valid_Block_Ids, Text (Value.Terminator.True_Target)),
               Where & ".terminator: invalid true_target");
            Require
              (Contains (Valid_Block_Ids, Text (Value.Terminator.False_Target)),
               Where & ".terminator: invalid false_target");
            Validate_Expr (Value.Terminator.Condition, Where & ".terminator.condition");
         when GM.Terminator_Return =>
            if Format = GM.Mir_V2 then
               Require
                 (Value.Terminator.Ownership_Effect /= GM.Ownership_Invalid,
                  Where & ".terminator: invalid ownership_effect");
            end if;
            if Value.Terminator.Has_Value then
               Validate_Expr (Value.Terminator.Value, Where & ".terminator.value");
            end if;
         when GM.Terminator_Select =>
            Require
              (not Value.Terminator.Arms.Is_Empty,
               Where & ".terminator: select terminator must have at least one arm");
            declare
               Delay_Arms : Natural := 0;
            begin
               for Index in Value.Terminator.Arms.First_Index .. Value.Terminator.Arms.Last_Index loop
                  if Value.Terminator.Arms (Index).Kind = GM.Select_Arm_Delay then
                     Delay_Arms := Delay_Arms + 1;
                  end if;
                  Validate_Select_Arm
                    (Value.Terminator.Arms (Index),
                     Valid_Block_Ids,
                     Valid_Scope_Ids,
                     Valid_Local_Ids,
                     Where & ".terminator.arms[" & Image (Index - 1) & "]");
               end loop;
               Require
                 (Delay_Arms <= 1,
                  Where & ".terminator: select terminator may have at most one delay arm");
            end;
         when GM.Terminator_Unknown =>
            null;
      end case;
   end Validate_Block;

   procedure Validate_Graph
     (Value       : GM.Graph_Entry;
      Graph_Index : Positive;
      Format      : GM.Mir_Format_Kind)
   is
      Where           : constant String := "graphs[" & Image (Graph_Index - 1) & "]";
      Actual_Ids      : FT.UString_Vectors.Vector;
      Expected_Ids    : FT.UString_Vectors.Vector;
      Valid_Scope_Ids : FT.UString_Vectors.Vector;
      Valid_Local_Ids : FT.UString_Vectors.Vector;
      Valid_Block_Ids : FT.UString_Vectors.Vector;
   begin
      Require (Has_Text (Value.Name), Where & ": missing graph name");
      Require (not Value.Blocks.Is_Empty, Where & ": blocks must be a non-empty list");
      if Text (Value.Kind) = "task" then
         Require (Value.Has_Priority, Where & ": task graphs must include priority");
         Require (not Value.Has_Return_Type, Where & ": task graphs must not include return_type");
      end if;

      for Index in Value.Blocks.First_Index .. Value.Blocks.Last_Index loop
         declare
            Block : constant GM.Block_Entry := Value.Blocks (Index);
         begin
            if Has_Text (Block.Id) then
               Actual_Ids.Append (Block.Id);
               Valid_Block_Ids.Append (Block.Id);
            else
               Actual_Ids.Append (FT.To_UString ("<missing>"));
            end if;
            Expected_Ids.Append (FT.To_UString ("bb" & Image (Index - 1)));
         end;
      end loop;

      Require
        (Equal_Vectors (Actual_Ids, Expected_Ids),
         Where & ": block ids must be deterministic "
         & Render (Expected_Ids)
         & ", got "
         & Render (Actual_Ids));

      Require
        (Contains (Actual_Ids, Text (Value.Entry_BB)),
         Where & ": entry block id missing or invalid");

      if not Value.Locals.Is_Empty then
         for Index in Value.Locals.First_Index .. Value.Locals.Last_Index loop
            declare
               Local : constant GM.Local_Entry := Value.Locals (Index);
            begin
               Validate_Local
                 (Local,
                  Format,
                  Where & ".locals[" & Image (Index - 1) & "]");
               if Has_Text (Local.Id) then
                  Valid_Local_Ids.Append (Local.Id);
               end if;
            end;
         end loop;
      end if;

      if Format = GM.Mir_V2 and then Value.Has_Return_Type then
         Validate_Type_Descriptor (Value.Return_Type, Where & ".return_type");
      end if;

      if Format = GM.Mir_V2 then
         Require
           (not Value.Scopes.Is_Empty,
            Where & ": mir-v2 graphs must have a non-empty scopes list");

         for Index in Value.Scopes.First_Index .. Value.Scopes.Last_Index loop
            if Has_Text (Value.Scopes (Index).Id) then
               Valid_Scope_Ids.Append (Value.Scopes (Index).Id);
            end if;
         end loop;

         if not Value.Locals.Is_Empty then
            for Index in Value.Locals.First_Index .. Value.Locals.Last_Index loop
               declare
                  Local       : constant GM.Local_Entry := Value.Locals (Index);
                  Local_Where : constant String := Where & ".locals[" & Image (Index - 1) & "]";
               begin
                  Require
                    (Contains (Valid_Scope_Ids, Text (Local.Scope_Id)),
                     Local_Where & ": unknown scope_id");
               end;
            end loop;
         end if;

         for Index in Value.Scopes.First_Index .. Value.Scopes.Last_Index loop
            Validate_Scope
              (Value.Scopes (Index),
               Valid_Scope_Ids,
               Valid_Local_Ids,
               Valid_Block_Ids,
               Where & ".scopes[" & Image (Index - 1) & "]");
         end loop;
      end if;

      for Index in Value.Blocks.First_Index .. Value.Blocks.Last_Index loop
         Validate_Block
           (Value.Blocks (Index),
            Format,
            Valid_Block_Ids,
            Valid_Scope_Ids,
            Valid_Local_Ids,
            Where & ".blocks[" & Image (Index - 1) & "]");
      end loop;
   end Validate_Graph;

   function Validate
     (Document : GM.Mir_Document) return GM.Validation_Result
   is
   begin
      Require
        (not Document.Graphs.Is_Empty,
         "root: graphs must be a non-empty list");

      if Document.Format = GM.Mir_V2 then
         Require
           (Document.Has_Source_Path and then Has_Text (Document.Source_Path),
            "root: mir-v2 payloads must include source_path");
      end if;

      if not Document.Types.Is_Empty then
         for Index in Document.Types.First_Index .. Document.Types.Last_Index loop
            Validate_Type_Descriptor
              (Document.Types (Index),
               "root.types[" & Image (Index - 1) & "]");
         end loop;
      end if;

      if not Document.Channels.Is_Empty then
         for Index in Document.Channels.First_Index .. Document.Channels.Last_Index loop
            Validate_Channel
              (Document.Channels (Index),
               "root.channels[" & Image (Index - 1) & "]");
         end loop;
      end if;

      if not Document.Externals.Is_Empty then
         for Index in Document.Externals.First_Index .. Document.Externals.Last_Index loop
            Validate_External
              (Document.Externals (Index),
               "root.externals[" & Image (Index - 1) & "]");
         end loop;
      end if;

      for Index in Document.Graphs.First_Index .. Document.Graphs.Last_Index loop
         Validate_Graph (Document.Graphs (Index), Index, Document.Format);
      end loop;

      return GM.Ok;
   exception
      when Error : Validation_Error =>
         return GM.Error (Ada.Exceptions.Exception_Message (Error));
   end Validate;

   function Validate_File
     (Path : String) return GM.Validation_Result
   is
      Loaded : constant Safe_Frontend.Mir_Json.Load_Result :=
        Safe_Frontend.Mir_Json.Load_File (Path);
   begin
      if not Loaded.Success then
         return GM.Error (FT.To_String (Loaded.Message));
      end if;
      declare
         Result : constant GM.Validation_Result := Validate (Loaded.Document);
      begin
         if Result.Success then
            return Result;
         end if;
         return GM.Error (Path & ": " & FT.To_String (Result.Message));
      end;
   end Validate_File;
end Safe_Frontend.Mir_Validate;
