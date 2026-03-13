with Ada.Characters.Latin_1;
with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Unbounded;
with Safe_Frontend.Json;
with Safe_Frontend.Types;

package body Safe_Frontend.Mir_Write is
   package GM renames Safe_Frontend.Mir_Model;
   package FT renames Safe_Frontend.Types;
   package JS renames Safe_Frontend.Json;
   package US renames Ada.Strings.Unbounded;

   package String_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => String);

   use type GM.Expr_Access;
   use type GM.Op_Kind;

   function Json_List (Items : String_Vectors.Vector) return String is
      Result : US.Unbounded_String := US.Null_Unbounded_String;
   begin
      US.Append (Result, "[");
      if not Items.Is_Empty then
         for Index in Items.First_Index .. Items.Last_Index loop
            if Index > Items.First_Index then
               US.Append (Result, ",");
            end if;
            US.Append (Result, Items (Index));
         end loop;
      end if;
      US.Append (Result, "]");
      return US.To_String (Result);
   end Json_List;

   function Join_Object_Fields (Items : String_Vectors.Vector) return String is
      Result : US.Unbounded_String := US.Null_Unbounded_String;
   begin
      if not Items.Is_Empty then
         for Index in Items.First_Index .. Items.Last_Index loop
            if Index > Items.First_Index then
               US.Append (Result, ",");
            end if;
            US.Append (Result, Items (Index));
         end loop;
      end if;
      return US.To_String (Result);
   end Join_Object_Fields;

   function Name_From_String
     (Name : String;
      Span : FT.Source_Span) return String
   is
      Parts  : String_Vectors.Vector;
      Start  : Positive := Name'First;
      Result : US.Unbounded_String := US.Null_Unbounded_String;
   begin
      if Name'Length = 0 then
         return
           "{""tag"":""ident"",""name"":"""",""span"":"
           & JS.Span_Object (Span)
           & "}";
      end if;

      for Index in Name'Range loop
         if Name (Index) = '.' then
            if Index > Start then
               Parts.Append (Name (Start .. Index - 1));
            end if;
            Start := Index + 1;
         end if;
      end loop;
      if Start <= Name'Last then
         Parts.Append (Name (Start .. Name'Last));
      end if;

      Result :=
        US.To_Unbounded_String
          ("{""tag"":""ident"",""name"":"
           & JS.Quote (Parts (Parts.First_Index))
           & ",""span"":"
           & JS.Span_Object (Span)
           & "}");

      if Natural (Parts.Length) > 1 then
         for Index in Parts.First_Index + 1 .. Parts.Last_Index loop
            Result :=
              US.To_Unbounded_String
                ("{""tag"":""select"",""prefix"":"
                 & US.To_String (Result)
                 & ",""selector"":"
                 & JS.Quote (Parts (Index))
                 & ",""span"":"
                 & JS.Span_Object (Span)
                 & "}");
         end loop;
      end if;

      return US.To_String (Result);
   end Name_From_String;

   function Type_Json (Info : GM.Type_Descriptor) return String is
      Items  : String_Vectors.Vector;
      Fields : String_Vectors.Vector;
   begin
      Items.Append ("""name"":" & JS.Quote (Info.Name));
      Items.Append ("""kind"":" & JS.Quote (Info.Kind));
      if Info.Has_Low then
         Items.Append ("""low"":" & Long_Long_Integer'Image (Info.Low));
      end if;
      if Info.Has_High then
         Items.Append ("""high"":" & Long_Long_Integer'Image (Info.High));
      end if;
      if Info.Has_Base then
         Items.Append ("""base"":" & JS.Quote (Info.Base));
      end if;
      if Info.Has_Digits_Text then
         Items.Append ("""digits_text"":" & JS.Quote (Info.Digits_Text));
      end if;
      if Info.Has_Float_Low_Text then
         Items.Append ("""float_low_text"":" & JS.Quote (Info.Float_Low_Text));
      end if;
      if Info.Has_Float_High_Text then
         Items.Append ("""float_high_text"":" & JS.Quote (Info.Float_High_Text));
      end if;
      if not Info.Index_Types.Is_Empty then
         declare
            Values : String_Vectors.Vector;
         begin
            for Item of Info.Index_Types loop
               Values.Append (JS.Quote (Item));
            end loop;
            Items.Append ("""index_types"":" & Json_List (Values));
         end;
      end if;
      if Info.Has_Component_Type then
         Items.Append ("""component_type"":" & JS.Quote (Info.Component_Type));
      end if;
      if Info.Unconstrained then
         Items.Append ("""unconstrained"":true");
      end if;
      if not Info.Fields.Is_Empty then
         for Field of Info.Fields loop
            Fields.Append (JS.Quote (Field.Name) & ":" & JS.Quote (Field.Type_Name));
         end loop;
         Items.Append ("""fields"":{" & Join_Object_Fields (Fields) & "}");
      end if;
      if Info.Has_Target then
         Items.Append ("""target"":" & JS.Quote (Info.Target));
      end if;
      if Info.Has_Discriminant then
         Items.Append ("""discriminant_name"":" & JS.Quote (Info.Discriminant_Name));
         Items.Append ("""discriminant_type"":" & JS.Quote (Info.Discriminant_Type));
         if Info.Has_Discriminant_Default then
            Items.Append
              ("""discriminant_default"":" & JS.Bool_Literal (Info.Discriminant_Default_Bool));
         end if;
      end if;
      if not Info.Variant_Fields.Is_Empty then
         declare
            Variants : String_Vectors.Vector;
         begin
            for Variant_Field of Info.Variant_Fields loop
               Variants.Append
                 ("{""name"":"
                  & JS.Quote (Variant_Field.Name)
                  & ",""type"":"
                  & JS.Quote (Variant_Field.Type_Name)
                  & ",""when"":"
                  & JS.Bool_Literal (Variant_Field.When_True)
                  & "}");
            end loop;
            Items.Append ("""variant_fields"":" & Json_List (Variants));
         end;
      end if;
      if FT.To_String (Info.Kind) = "access" then
         Items.Append ("""not_null"":" & JS.Bool_Literal (Info.Not_Null));
         Items.Append ("""anonymous"":" & JS.Bool_Literal (Info.Anonymous));
         Items.Append ("""is_constant"":" & JS.Bool_Literal (Info.Is_Constant));
         Items.Append ("""is_all"":" & JS.Bool_Literal (Info.Is_All));
         if Info.Has_Access_Role then
            Items.Append ("""access_role"":" & JS.Quote (Info.Access_Role));
         end if;
      end if;
      return "{" & Join_Object_Fields (Items) & "}";
   end Type_Json;

   function Expr_Json (Expr : GM.Expr_Access) return String;

   function Expr_Json (Expr : GM.Expr_Access) return String is
      Items : String_Vectors.Vector;
   begin
      if Expr = null then
         return "null";
      end if;

      Items.Append ("""tag"":" & JS.Quote (GM.Image (Expr.Kind)));
      Items.Append ("""span"":" & JS.Span_Object (Expr.Span));
      if FT.To_String (Expr.Type_Name)'Length > 0 then
         Items.Append ("""type"":" & JS.Quote (Expr.Type_Name));
      end if;

      case Expr.Kind is
         when GM.Expr_Int =>
            if FT.To_String (Expr.Text)'Length > 0 then
               Items.Append ("""text"":" & JS.Quote (Expr.Text));
            end if;
            Items.Append ("""value"":" & Long_Long_Integer'Image (Expr.Int_Value));
         when GM.Expr_Real =>
            Items.Append ("""text"":" & JS.Quote (Expr.Text));
         when GM.Expr_Bool =>
            Items.Append ("""value"":" & JS.Bool_Literal (Expr.Bool_Value));
         when GM.Expr_Null =>
            null;
         when GM.Expr_Ident =>
            Items.Append ("""name"":" & JS.Quote (Expr.Name));
         when GM.Expr_Select =>
            Items.Append ("""prefix"":" & Expr_Json (Expr.Prefix));
            Items.Append ("""selector"":" & JS.Quote (Expr.Selector));
         when GM.Expr_Resolved_Index =>
            declare
               Values : String_Vectors.Vector;
            begin
               for Item of Expr.Indices loop
                  Values.Append (Expr_Json (Item));
               end loop;
               Items.Append ("""prefix"":" & Expr_Json (Expr.Prefix));
               Items.Append ("""indices"":" & Json_List (Values));
            end;
         when GM.Expr_Conversion =>
            Items.Append ("""target"":" & Name_From_String (FT.To_String (Expr.Name), Expr.Span));
            Items.Append ("""expr"":" & Expr_Json (Expr.Inner));
         when GM.Expr_Call =>
            declare
               Values : String_Vectors.Vector;
            begin
               for Item of Expr.Args loop
                  Values.Append (Expr_Json (Item));
               end loop;
               Items.Append ("""callee"":" & Expr_Json (Expr.Callee));
               Items.Append ("""args"":" & Json_List (Values));
               if Expr.Has_Call_Span then
                  Items.Append ("""call_span"":" & JS.Span_Object (Expr.Call_Span));
               end if;
            end;
         when GM.Expr_Allocator =>
            Items.Append ("""value"":" & Expr_Json (Expr.Value));
         when GM.Expr_Aggregate =>
            declare
               Values : String_Vectors.Vector;
            begin
               for Field of Expr.Fields loop
                  Values.Append
                    ("{""field"":"
                     & JS.Quote (Field.Field)
                     & ",""expr"":"
                     & Expr_Json (Field.Expr)
                     & ",""span"":"
                     & JS.Span_Object (Field.Span)
                     & "}");
               end loop;
               Items.Append ("""fields"":" & Json_List (Values));
            end;
         when GM.Expr_Annotated =>
            Items.Append ("""subtype"":" & Name_From_String (FT.To_String (Expr.Subtype_Name), Expr.Span));
            Items.Append ("""expr"":" & Expr_Json (Expr.Inner));
         when GM.Expr_Unary =>
            Items.Append ("""op"":" & JS.Quote (Expr.Operator));
            Items.Append ("""expr"":" & Expr_Json (Expr.Inner));
         when GM.Expr_Binary =>
            Items.Append ("""op"":" & JS.Quote (Expr.Operator));
            Items.Append ("""left"":" & Expr_Json (Expr.Left));
            Items.Append ("""right"":" & Expr_Json (Expr.Right));
         when others =>
            null;
      end case;

      return "{" & Join_Object_Fields (Items) & "}";
   end Expr_Json;

   function Local_Json (Item : GM.Local_Entry) return String is
   begin
      return
        "{""id"":"
        & JS.Quote (Item.Id)
        & ",""kind"":"
        & JS.Quote (Item.Kind)
        & ",""mode"":"
        & JS.Quote (Item.Mode)
        & ",""name"":"
        & JS.Quote (Item.Name)
        & ",""is_constant"":"
        & JS.Bool_Literal (Item.Is_Constant)
        & ",""ownership_role"":"
        & JS.Quote (Item.Ownership_Role)
        & ",""scope_id"":"
        & JS.Quote (Item.Scope_Id)
        & ",""span"":"
        & JS.Span_Object (Item.Span)
        & ",""type"":"
        & Type_Json (Item.Type_Info)
        & "}";
   end Local_Json;

   function Scope_Json (Item : GM.Scope_Entry) return String is
      Local_Ids   : String_Vectors.Vector;
      Exit_Blocks : String_Vectors.Vector;
   begin
      for Value of Item.Local_Ids loop
         Local_Ids.Append (JS.Quote (Value));
      end loop;
      for Value of Item.Exit_Blocks loop
         Exit_Blocks.Append (JS.Quote (Value));
      end loop;
      return
        "{""id"":"
        & JS.Quote (Item.Id)
        & ",""parent_scope_id"":"
        & (if Item.Has_Parent_Scope then JS.Quote (Item.Parent_Scope_Id) else "null")
        & ",""kind"":"
        & JS.Quote (Item.Kind)
        & ",""local_ids"":"
        & Json_List (Local_Ids)
        & ",""entry_block"":"
        & JS.Quote (Item.Entry_Block)
        & ",""exit_blocks"":"
        & Json_List (Exit_Blocks)
        & "}";
   end Scope_Json;

   function Channel_Json (Item : GM.Channel_Entry) return String is
   begin
      return
        "{""name"":"
        & JS.Quote (Item.Name)
        & ",""element_type"":"
        & Type_Json (Item.Element_Type)
        & ",""capacity"":"
        & Long_Long_Integer'Image (Item.Capacity)
        & ",""span"":"
        & JS.Span_Object (Item.Span)
        & "}";
   end Channel_Json;

   function Select_Arm_Json (Item : GM.Select_Arm_Entry) return String is
      Kind : constant String :=
        (case Item.Kind is
            when GM.Select_Arm_Channel => "channel",
            when GM.Select_Arm_Delay => "delay",
            when others => "<unknown>");
   begin
      case Item.Kind is
         when GM.Select_Arm_Channel =>
            return
              "{""kind"":"
              & JS.Quote (Kind)
              & ",""channel_name"":"
              & JS.Quote (Item.Channel_Data.Channel_Name)
              & ",""variable_name"":"
              & JS.Quote (Item.Channel_Data.Variable_Name)
              & ",""scope_id"":"
              & JS.Quote (Item.Channel_Data.Scope_Id)
              & ",""local_id"":"
              & JS.Quote (Item.Channel_Data.Local_Id)
              & ",""type"":"
              & Type_Json (Item.Channel_Data.Type_Info)
              & ",""target"":"
              & JS.Quote (Item.Channel_Data.Target)
              & ",""span"":"
              & JS.Span_Object (Item.Channel_Data.Span)
              & "}";
         when GM.Select_Arm_Delay =>
            return
              "{""kind"":"
              & JS.Quote (Kind)
              & ",""duration_expr"":"
              & Expr_Json (Item.Delay_Data.Duration_Expr)
              & ",""target"":"
              & JS.Quote (Item.Delay_Data.Target)
              & ",""span"":"
              & JS.Span_Object (Item.Delay_Data.Span)
              & "}";
         when others =>
            return
              "{""kind"":"
              & JS.Quote (Kind)
              & ",""span"":"
              & JS.Span_Object (Item.Span)
              & "}";
      end case;
   end Select_Arm_Json;

   function Op_Json (Item : GM.Op_Entry) return String is
      Locals : String_Vectors.Vector;
      Items  : String_Vectors.Vector;
   begin
      Items.Append ("""kind"":" & JS.Quote (GM.Image (Item.Kind)));
      Items.Append ("""span"":" & JS.Span_Object (Item.Span));
      case Item.Kind is
         when GM.Op_Scope_Enter =>
            for Value of Item.Locals loop
               Locals.Append (JS.Quote (Value));
            end loop;
            Items.Append ("""locals"":" & Json_List (Locals));
            Items.Append ("""scope_id"":" & JS.Quote (Item.Scope_Id));
         when GM.Op_Scope_Exit =>
            Items.Append ("""scope_id"":" & JS.Quote (Item.Scope_Id));
         when GM.Op_Assign | GM.Op_Call =>
            Items.Append ("""ownership_effect"":" & JS.Quote (GM.Image (Item.Ownership_Effect)));
            Items.Append ("""target"":" & Expr_Json (Item.Target));
            Items.Append ("""type"":" & JS.Quote (Item.Type_Name));
            Items.Append ("""value"":" & Expr_Json (Item.Value));
            if Item.Kind = GM.Op_Assign then
               Items.Append
                 ("""declaration_init"":" & JS.Bool_Literal (Item.Declaration_Init));
            end if;
         when GM.Op_Channel_Send | GM.Op_Channel_Receive | GM.Op_Channel_Try_Send | GM.Op_Channel_Try_Receive =>
            Items.Append ("""ownership_effect"":" & JS.Quote (GM.Image (Item.Ownership_Effect)));
            Items.Append ("""channel"":" & Expr_Json (Item.Channel));
            Items.Append ("""type"":" & JS.Quote (Item.Type_Name));
            if Item.Target /= null then
               Items.Append ("""target"":" & Expr_Json (Item.Target));
            end if;
            if Item.Value /= null then
               Items.Append ("""value"":" & Expr_Json (Item.Value));
            end if;
            if Item.Success_Target /= null then
               Items.Append ("""success_target"":" & Expr_Json (Item.Success_Target));
            end if;
         when GM.Op_Delay =>
            Items.Append ("""ownership_effect"":" & JS.Quote (GM.Image (Item.Ownership_Effect)));
            Items.Append ("""type"":" & JS.Quote (Item.Type_Name));
            Items.Append ("""value"":" & Expr_Json (Item.Value));
         when others =>
            null;
      end case;
      return "{" & Join_Object_Fields (Items) & "}";
   end Op_Json;

   function Terminator_Json (Item : GM.Terminator_Entry) return String is
      Items : String_Vectors.Vector;
   begin
      Items.Append ("""kind"":" & JS.Quote (GM.Image (Item.Kind)));
      Items.Append ("""span"":" & JS.Span_Object (Item.Span));
      case Item.Kind is
         when GM.Terminator_Jump =>
            Items.Append ("""target"":" & JS.Quote (Item.Target));
         when GM.Terminator_Branch =>
            Items.Append ("""condition"":" & Expr_Json (Item.Condition));
            Items.Append ("""true_target"":" & JS.Quote (Item.True_Target));
            Items.Append ("""false_target"":" & JS.Quote (Item.False_Target));
         when GM.Terminator_Return =>
            Items.Append ("""ownership_effect"":" & JS.Quote (GM.Image (Item.Ownership_Effect)));
            if Item.Has_Value then
               Items.Append ("""value"":" & Expr_Json (Item.Value));
            else
               Items.Append ("""value"":null");
            end if;
         when GM.Terminator_Select =>
            declare
               Arms : String_Vectors.Vector;
            begin
               for Arm of Item.Arms loop
                  Arms.Append (Select_Arm_Json (Arm));
               end loop;
               Items.Append ("""arms"":" & Json_List (Arms));
            end;
         when others =>
            null;
      end case;
      return "{" & Join_Object_Fields (Items) & "}";
   end Terminator_Json;

   function Block_Json (Item : GM.Block_Entry) return String is
      Ops   : String_Vectors.Vector;
      Items : String_Vectors.Vector;
   begin
      for Op of Item.Ops loop
         Ops.Append (Op_Json (Op));
      end loop;
      Items.Append ("""id"":" & JS.Quote (Item.Id));
      Items.Append ("""active_scope_id"":" & JS.Quote (Item.Active_Scope_Id));
      Items.Append ("""role"":" & JS.Quote (Item.Role));
      if Item.Has_Loop_Info then
         declare
            Loop_Items : String_Vectors.Vector;
         begin
            Loop_Items.Append ("""kind"":" & JS.Quote (Item.Loop_Kind));
            if FT.To_String (Item.Loop_Var)'Length > 0 then
               Loop_Items.Append ("""loop_var"":" & JS.Quote (Item.Loop_Var));
            end if;
            if FT.To_String (Item.Loop_Exit_Target)'Length > 0 then
               Loop_Items.Append ("""exit_target"":" & JS.Quote (Item.Loop_Exit_Target));
            end if;
            Items.Append ("""loop"":{" & Join_Object_Fields (Loop_Items) & "}");
         end;
      end if;
      Items.Append ("""span"":" & JS.Span_Object (Item.Span));
      Items.Append ("""ops"":" & Json_List (Ops));
      Items.Append ("""terminator"":" & Terminator_Json (Item.Terminator));
      return "{" & Join_Object_Fields (Items) & "}";
   end Block_Json;

   function Graph_Json (Item : GM.Graph_Entry) return String is
      Locals : String_Vectors.Vector;
      Scopes : String_Vectors.Vector;
      Blocks : String_Vectors.Vector;
      Items  : String_Vectors.Vector;
   begin
      for Local of Item.Locals loop
         Locals.Append (Local_Json (Local));
      end loop;
      for Scope of Item.Scopes loop
         Scopes.Append (Scope_Json (Scope));
      end loop;
      for Block of Item.Blocks loop
         Blocks.Append (Block_Json (Block));
      end loop;
      Items.Append ("""name"":" & JS.Quote (Item.Name));
      Items.Append ("""kind"":" & JS.Quote (Item.Kind));
      Items.Append ("""entry_bb"":" & JS.Quote (Item.Entry_BB));
      if Item.Has_Span then
         Items.Append ("""span"":" & JS.Span_Object (Item.Span));
      end if;
      if Item.Has_Priority then
         Items.Append ("""priority"":" & Long_Long_Integer'Image (Item.Priority));
         Items.Append
           ("""has_explicit_priority"":" & JS.Bool_Literal (Item.Has_Explicit_Priority));
      end if;
      if Item.Has_Return_Type then
         Items.Append ("""return_type"":" & Type_Json (Item.Return_Type));
      else
         Items.Append ("""return_type"":null");
      end if;
      Items.Append ("""locals"":" & Json_List (Locals));
      Items.Append ("""scopes"":" & Json_List (Scopes));
      Items.Append ("""blocks"":" & Json_List (Blocks));
      return "{" & Join_Object_Fields (Items) & "}";
   end Graph_Json;

   function To_Json
     (Document : GM.Mir_Document) return String
   is
      Types  : String_Vectors.Vector;
      Channels : String_Vectors.Vector;
      Graphs : String_Vectors.Vector;
   begin
      for Item of Document.Types loop
         Types.Append (Type_Json (Item));
      end loop;
      for Item of Document.Channels loop
         Channels.Append (Channel_Json (Item));
      end loop;
      for Item of Document.Graphs loop
         Graphs.Append (Graph_Json (Item));
      end loop;
      return
        "{"
        & """format"":"
        & JS.Quote (GM.Image (Document.Format))
        & ","
        & """source_path"":"
        & (if Document.Has_Source_Path then JS.Quote (Document.Source_Path) else "null")
        & ","
        & """package_name"":"
        & JS.Quote (Document.Package_Name)
        & ","
        & """types"":"
        & Json_List (Types)
        & ","
        & """channels"":"
        & Json_List (Channels)
        & ","
        & """graphs"":"
        & Json_List (Graphs)
        & "}"
        & Ada.Characters.Latin_1.LF;
   end To_Json;
end Safe_Frontend.Mir_Write;
