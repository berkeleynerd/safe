with GNATCOLL.JSON;

package body Safe_Frontend.Mir_Json is
   package GM renames Safe_Frontend.Mir_Model;
   use type GM.Scalar_Value_Kind;

   function Field_Or_Null
     (Object_Value : GNATCOLL.JSON.JSON_Value;
      Field        : String) return GNATCOLL.JSON.JSON_Value;

   function Json_Array_Or_Empty
     (Object_Value : GNATCOLL.JSON.JSON_Value;
      Field        : String) return GNATCOLL.JSON.JSON_Array;

   function Parse_Span
     (Value : GNATCOLL.JSON.JSON_Value) return FT.Source_Span;

   function Parse_Type
     (Value : GNATCOLL.JSON.JSON_Value) return GM.Type_Descriptor;

   function Parse_Expr
     (Value : GNATCOLL.JSON.JSON_Value) return GM.Expr_Access;

   function Parse_Local
     (Value : GNATCOLL.JSON.JSON_Value) return GM.Local_Entry;

   function Parse_Scope
     (Value : GNATCOLL.JSON.JSON_Value) return GM.Scope_Entry;

   function Parse_Channel
     (Value : GNATCOLL.JSON.JSON_Value) return GM.Channel_Entry;

   function Parse_Effect_Summary
     (Value : GNATCOLL.JSON.JSON_Value) return GM.External_Effect_Summary;

   function Parse_Channel_Summary
     (Value : GNATCOLL.JSON.JSON_Value) return GM.External_Channel_Summary;

   function Parse_External
     (Value : GNATCOLL.JSON.JSON_Value) return GM.External_Entry;

   function Parse_Op
     (Value : GNATCOLL.JSON.JSON_Value) return GM.Op_Entry;

   function Parse_Select_Arm
     (Value : GNATCOLL.JSON.JSON_Value) return GM.Select_Arm_Entry;

   function Parse_Terminator
     (Value : GNATCOLL.JSON.JSON_Value) return GM.Terminator_Entry;

   function Parse_Block
     (Value : GNATCOLL.JSON.JSON_Value) return GM.Block_Entry;

   function Parse_Graph
     (Value : GNATCOLL.JSON.JSON_Value) return GM.Graph_Entry;

   function Parse_Ownership_Effect
     (Value : GNATCOLL.JSON.JSON_Value) return GM.Ownership_Effect_Kind;

   function Flatten_Name
     (Value : GNATCOLL.JSON.JSON_Value) return String;

   function Field_Or_Null
     (Object_Value : GNATCOLL.JSON.JSON_Value;
      Field        : String) return GNATCOLL.JSON.JSON_Value
   is
      use GNATCOLL.JSON;
   begin
      if Object_Value.Kind = JSON_Object_Type and then Has_Field (Object_Value, Field) then
         return Get (Object_Value, Field);
      end if;
      return Create;
   end Field_Or_Null;

   function Json_Array_Or_Empty
     (Object_Value : GNATCOLL.JSON.JSON_Value;
      Field        : String) return GNATCOLL.JSON.JSON_Array
   is
      use GNATCOLL.JSON;
   begin
      if Object_Value.Kind = JSON_Object_Type
        and then Has_Field (Object_Value, Field)
        and then Get (Object_Value, Field).Kind = JSON_Array_Type
      then
         return Get (Object_Value, Field);
      end if;
      return Empty_Array;
   end Json_Array_Or_Empty;

   function Parse_Span
     (Value : GNATCOLL.JSON.JSON_Value) return FT.Source_Span
   is
      use GNATCOLL.JSON;
      Result : FT.Source_Span := FT.Null_Span;
   begin
      if Value.Kind /= JSON_Object_Type then
         return Result;
      end if;

      if Has_Field (Value, "start_line")
        and then Get (Value, "start_line").Kind = JSON_Int_Type
      then
         Result.Start_Pos.Line :=
           Positive (Long_Long_Integer'Max (1, Get (Get (Value, "start_line"))));
      end if;
      if Has_Field (Value, "start_col")
        and then Get (Value, "start_col").Kind = JSON_Int_Type
      then
         Result.Start_Pos.Column :=
           Positive (Long_Long_Integer'Max (1, Get (Get (Value, "start_col"))));
      end if;
      if Has_Field (Value, "end_line")
        and then Get (Value, "end_line").Kind = JSON_Int_Type
      then
         Result.End_Pos.Line :=
           Positive (Long_Long_Integer'Max (1, Get (Get (Value, "end_line"))));
      else
         Result.End_Pos.Line := Result.Start_Pos.Line;
      end if;
      if Has_Field (Value, "end_col")
        and then Get (Value, "end_col").Kind = JSON_Int_Type
      then
         Result.End_Pos.Column :=
           Positive (Long_Long_Integer'Max (1, Get (Get (Value, "end_col"))));
      else
         Result.End_Pos.Column := Result.Start_Pos.Column;
      end if;
      return Result;
   end Parse_Span;

   function Parse_Type
     (Value : GNATCOLL.JSON.JSON_Value) return GM.Type_Descriptor
   is
      use GNATCOLL.JSON;
      Result : GM.Type_Descriptor;

      function Parse_Scalar_Value (Item : JSON_Value) return GM.Scalar_Value is
         Parsed : GM.Scalar_Value;
      begin
         if Item.Kind /= JSON_Object_Type then
            return Parsed;
         end if;
         if Has_Field (Item, "kind") and then Get (Item, "kind").Kind = JSON_String_Type then
            declare
               Kind_Name : constant String := Get (Item, "kind");
            begin
               if Kind_Name = "integer"
                 and then Has_Field (Item, "value")
                 and then Get (Item, "value").Kind = JSON_Int_Type
               then
                  Parsed.Kind := GM.Scalar_Value_Integer;
                  Parsed.Int_Value := Get (Get (Item, "value"));
               elsif Kind_Name = "boolean"
                 and then Has_Field (Item, "value")
                 and then Get (Item, "value").Kind = JSON_Boolean_Type
               then
                  Parsed.Kind := GM.Scalar_Value_Boolean;
                  Parsed.Bool_Value := Get (Get (Item, "value"));
               elsif Kind_Name = "character"
                 and then Has_Field (Item, "text")
                 and then Get (Item, "text").Kind = JSON_String_Type
               then
                  Parsed.Kind := GM.Scalar_Value_Character;
                  Parsed.Text := FT.To_UString (Get (Item, "text"));
               end if;
            end;
         end if;
         return Parsed;
      end Parse_Scalar_Value;

      procedure Append_Field (Name : UTF8_String; Field_Value : JSON_Value) is
         Field_Entry : GM.Type_Field;
      begin
         Field_Entry.Name := FT.To_UString (Name);
         if Field_Value.Kind = JSON_String_Type then
            Field_Entry.Type_Name := FT.To_UString (Get (Field_Value));
         end if;
         Result.Fields.Append (Field_Entry);
      end Append_Field;
   begin
      if Value.Kind /= JSON_Object_Type then
         return Result;
      end if;

      if Has_Field (Value, "name") and then Get (Value, "name").Kind = JSON_String_Type then
         Result.Name := FT.To_UString (Get (Value, "name"));
      end if;
      if Has_Field (Value, "kind") and then Get (Value, "kind").Kind = JSON_String_Type then
         Result.Kind := FT.To_UString (Get (Value, "kind"));
      end if;
      if Has_Field (Value, "low") and then Get (Value, "low").Kind = JSON_Int_Type then
         Result.Has_Low := True;
         Result.Low := Get (Get (Value, "low"));
      end if;
      if Has_Field (Value, "high") and then Get (Value, "high").Kind = JSON_Int_Type then
         Result.Has_High := True;
         Result.High := Get (Get (Value, "high"));
      end if;
      if Has_Field (Value, "bit_width") and then Get (Value, "bit_width").Kind = JSON_Int_Type then
         declare
            Width_Value : constant Long_Long_Integer :=
              Long_Long_Integer'(Get (Get (Value, "bit_width")));
         begin
            if Width_Value in 8 | 16 | 32 | 64 then
               Result.Has_Bit_Width := True;
               Result.Bit_Width := Positive (Width_Value);
            end if;
         end;
      end if;
      if Has_Field (Value, "base") and then Get (Value, "base").Kind = JSON_String_Type then
         Result.Has_Base := True;
         Result.Base := FT.To_UString (Get (Value, "base"));
      end if;
      if Has_Field (Value, "digits_text")
        and then Get (Value, "digits_text").Kind = JSON_String_Type
      then
         Result.Has_Digits_Text := True;
         Result.Digits_Text := FT.To_UString (Get (Value, "digits_text"));
      end if;
      if Has_Field (Value, "float_low_text")
        and then Get (Value, "float_low_text").Kind = JSON_String_Type
      then
         Result.Has_Float_Low_Text := True;
         Result.Float_Low_Text := FT.To_UString (Get (Value, "float_low_text"));
      end if;
      if Has_Field (Value, "float_high_text")
        and then Get (Value, "float_high_text").Kind = JSON_String_Type
      then
         Result.Has_Float_High_Text := True;
         Result.Float_High_Text := FT.To_UString (Get (Value, "float_high_text"));
      end if;
      if Has_Field (Value, "component_type")
        and then Get (Value, "component_type").Kind = JSON_String_Type
      then
         Result.Has_Component_Type := True;
         Result.Component_Type := FT.To_UString (Get (Value, "component_type"));
      end if;
      if Has_Field (Value, "target")
        and then Get (Value, "target").Kind = JSON_String_Type
      then
         Result.Has_Target := True;
         Result.Target := FT.To_UString (Get (Value, "target"));
      end if;
      if Has_Field (Value, "discriminant_name")
        and then Get (Value, "discriminant_name").Kind = JSON_String_Type
      then
         Result.Has_Discriminant := True;
         Result.Discriminant_Name := FT.To_UString (Get (Value, "discriminant_name"));
      end if;
      if Has_Field (Value, "discriminant_type")
        and then Get (Value, "discriminant_type").Kind = JSON_String_Type
      then
         Result.Has_Discriminant := True;
         Result.Discriminant_Type := FT.To_UString (Get (Value, "discriminant_type"));
      end if;
      if Has_Field (Value, "discriminant_default")
        and then Get (Value, "discriminant_default").Kind = JSON_Boolean_Type
      then
         Result.Has_Discriminant_Default := True;
         Result.Discriminant_Default_Bool := Get (Get (Value, "discriminant_default"));
      end if;
      if Has_Field (Value, "access_role")
        and then Get (Value, "access_role").Kind = JSON_String_Type
      then
         Result.Has_Access_Role := True;
         Result.Access_Role := FT.To_UString (Get (Value, "access_role"));
      end if;
      if Has_Field (Value, "unconstrained")
        and then Get (Value, "unconstrained").Kind = JSON_Boolean_Type
      then
         Result.Unconstrained := Get (Get (Value, "unconstrained"));
      end if;
      if Has_Field (Value, "not_null")
        and then Get (Value, "not_null").Kind = JSON_Boolean_Type
      then
         Result.Not_Null := Get (Get (Value, "not_null"));
      end if;
      if Has_Field (Value, "anonymous")
        and then Get (Value, "anonymous").Kind = JSON_Boolean_Type
      then
         Result.Anonymous := Get (Get (Value, "anonymous"));
      end if;
      if Has_Field (Value, "is_constant")
        and then Get (Value, "is_constant").Kind = JSON_Boolean_Type
      then
         Result.Is_Constant := Get (Get (Value, "is_constant"));
      end if;
      if Has_Field (Value, "is_all")
        and then Get (Value, "is_all").Kind = JSON_Boolean_Type
      then
         Result.Is_All := Get (Get (Value, "is_all"));
      end if;
      if Has_Field (Value, "is_result_builtin")
        and then Get (Value, "is_result_builtin").Kind = JSON_Boolean_Type
      then
         Result.Is_Result_Builtin := Get (Get (Value, "is_result_builtin"));
      end if;

      declare
         Index_Types : constant JSON_Array := Json_Array_Or_Empty (Value, "index_types");
      begin
         for Index in 1 .. Length (Index_Types) loop
            declare
               Item : constant JSON_Value := Get (Index_Types, Index);
            begin
               if Item.Kind = JSON_String_Type then
                  Result.Index_Types.Append (FT.To_UString (Get (Item)));
               end if;
            end;
         end loop;
      end;

      if Has_Field (Value, "fields")
        and then Get (Value, "fields").Kind = JSON_Object_Type
      then
         Map_JSON_Object (Get (Value, "fields"), Append_Field'Access);
      end if;
      declare
         Discriminants : constant JSON_Array := Json_Array_Or_Empty (Value, "discriminants");
      begin
         for Index in 1 .. Length (Discriminants) loop
            declare
               Item : constant JSON_Value := Get (Discriminants, Index);
               Disc : GM.Discriminant_Descriptor;
            begin
               if Item.Kind = JSON_Object_Type then
                  if Has_Field (Item, "name")
                    and then Get (Item, "name").Kind = JSON_String_Type
                  then
                     Disc.Name := FT.To_UString (Get (Item, "name"));
                  end if;
                  if Has_Field (Item, "type")
                    and then Get (Item, "type").Kind = JSON_String_Type
                  then
                     Disc.Type_Name := FT.To_UString (Get (Item, "type"));
                  end if;
                  if Has_Field (Item, "has_default")
                    and then Get (Item, "has_default").Kind = JSON_Boolean_Type
                  then
                     Disc.Has_Default := Get (Get (Item, "has_default"));
                  end if;
                  if Has_Field (Item, "default") then
                     Disc.Default_Value := Parse_Scalar_Value (Get (Item, "default"));
                     Disc.Has_Default := Disc.Default_Value.Kind /= GM.Scalar_Value_None;
                  end if;
                  Result.Discriminants.Append (Disc);
               end if;
            end;
         end loop;
      end;
      declare
         Constraints : constant JSON_Array := Json_Array_Or_Empty (Value, "discriminant_constraints");
      begin
         for Index in 1 .. Length (Constraints) loop
            declare
               Item : constant JSON_Value := Get (Constraints, Index);
               Constraint : GM.Discriminant_Constraint;
            begin
               if Item.Kind = JSON_Object_Type then
                  if Has_Field (Item, "is_named")
                    and then Get (Item, "is_named").Kind = JSON_Boolean_Type
                  then
                     Constraint.Is_Named := Get (Get (Item, "is_named"));
                  end if;
                  if Has_Field (Item, "name")
                    and then Get (Item, "name").Kind = JSON_String_Type
                  then
                     Constraint.Name := FT.To_UString (Get (Item, "name"));
                  end if;
                  if Has_Field (Item, "value") then
                     Constraint.Value := Parse_Scalar_Value (Get (Item, "value"));
                  end if;
                  Result.Discriminant_Constraints.Append (Constraint);
               end if;
            end;
         end loop;
      end;
      if Has_Field (Value, "variant_discriminant_name")
        and then Get (Value, "variant_discriminant_name").Kind = JSON_String_Type
      then
         Result.Variant_Discriminant_Name :=
           FT.To_UString (Get (Value, "variant_discriminant_name"));
      end if;
      declare
         Variants : constant JSON_Array := Json_Array_Or_Empty (Value, "variant_fields");
      begin
         for Index in 1 .. Length (Variants) loop
            declare
               Item : constant JSON_Value := Get (Variants, Index);
               Variant_Field : GM.Variant_Field;
            begin
               if Item.Kind = JSON_Object_Type then
                  if Has_Field (Item, "name")
                    and then Get (Item, "name").Kind = JSON_String_Type
                  then
                     Variant_Field.Name := FT.To_UString (Get (Item, "name"));
                  end if;
                  if Has_Field (Item, "type")
                    and then Get (Item, "type").Kind = JSON_String_Type
                  then
                     Variant_Field.Type_Name := FT.To_UString (Get (Item, "type"));
                  end if;
                  if Has_Field (Item, "when")
                    and then Get (Item, "when").Kind = JSON_Boolean_Type
                  then
                     Variant_Field.When_True := Get (Get (Item, "when"));
                  end if;
                  if Has_Field (Item, "is_others")
                    and then Get (Item, "is_others").Kind = JSON_Boolean_Type
                  then
                     Variant_Field.Is_Others := Get (Get (Item, "is_others"));
                  end if;
                  if Has_Field (Item, "choice") then
                     Variant_Field.Choice := Parse_Scalar_Value (Get (Item, "choice"));
                     if Variant_Field.Choice.Kind = GM.Scalar_Value_Boolean then
                        Variant_Field.When_True := Variant_Field.Choice.Bool_Value;
                     end if;
                  elsif Has_Field (Item, "when")
                    and then Get (Item, "when").Kind = JSON_Boolean_Type
                  then
                     Variant_Field.Choice.Kind := GM.Scalar_Value_Boolean;
                     Variant_Field.Choice.Bool_Value := Variant_Field.When_True;
                  end if;
                  Result.Variant_Fields.Append (Variant_Field);
               end if;
            end;
         end loop;
      end;
      declare
         Tuple_Elements : constant JSON_Array := Json_Array_Or_Empty (Value, "tuple_element_types");
      begin
         for Index in 1 .. Length (Tuple_Elements) loop
            declare
               Item : constant JSON_Value := Get (Tuple_Elements, Index);
            begin
               if Item.Kind = JSON_String_Type then
                  Result.Tuple_Element_Types.Append (FT.To_UString (Get (Item)));
               end if;
            end;
         end loop;
      end;
      if Result.Discriminants.Is_Empty and then Result.Has_Discriminant then
         declare
            Disc : GM.Discriminant_Descriptor;
         begin
            Disc.Name := Result.Discriminant_Name;
            Disc.Type_Name := Result.Discriminant_Type;
            Disc.Has_Default := Result.Has_Discriminant_Default;
            if Result.Has_Discriminant_Default then
               Disc.Default_Value.Kind := GM.Scalar_Value_Boolean;
               Disc.Default_Value.Bool_Value := Result.Discriminant_Default_Bool;
            end if;
            Result.Discriminants.Append (Disc);
         end;
      end if;

      return Result;
   end Parse_Type;

   function Parse_Ownership_Effect
     (Value : GNATCOLL.JSON.JSON_Value) return GM.Ownership_Effect_Kind
   is
      use GNATCOLL.JSON;
   begin
      if Value.Kind /= JSON_String_Type then
         return GM.Ownership_Invalid;
      end if;

      declare
         Name : constant String := Get (Value);
      begin
         if Name = "None" then
            return GM.Ownership_None;
         elsif Name = "Move" then
            return GM.Ownership_Move;
         elsif Name = "Borrow" then
            return GM.Ownership_Borrow;
         elsif Name = "Observe" then
            return GM.Ownership_Observe;
         end if;
      end;
      return GM.Ownership_Invalid;
   end Parse_Ownership_Effect;

   function Flatten_Name
     (Value : GNATCOLL.JSON.JSON_Value) return String
   is
      use GNATCOLL.JSON;
   begin
      if Value.Kind /= JSON_Object_Type then
         return "";
      end if;

      if Has_Field (Value, "tag")
        and then Get (Value, "tag").Kind = JSON_String_Type
      then
         declare
            Tag : constant String := Get (Value, "tag");
         begin
            if Tag = "ident"
              and then Has_Field (Value, "name")
              and then Get (Value, "name").Kind = JSON_String_Type
            then
               return Get (Value, "name");
            elsif Tag = "select"
              and then Has_Field (Value, "selector")
              and then Get (Value, "selector").Kind = JSON_String_Type
            then
               return Flatten_Name (Field_Or_Null (Value, "prefix")) & "." & Get (Value, "selector");
            end if;
         end;
      end if;
      return "";
   end Flatten_Name;

   function Parse_Expr
     (Value : GNATCOLL.JSON.JSON_Value) return GM.Expr_Access
   is
      use GNATCOLL.JSON;
      Result : constant GM.Expr_Access := new GM.Expr_Node;
      Tag       : FT.UString := FT.To_UString ("");
      Kind_Name : FT.UString := FT.To_UString ("");

      procedure Parse_Expr_List
        (Items  : JSON_Array;
         Target : in out GM.Expr_Access_Vectors.Vector) is
      begin
         for Index in 1 .. Length (Items) loop
            Target.Append (Parse_Expr (Get (Items, Index)));
         end loop;
      end Parse_Expr_List;
   begin
      if Value.Kind /= JSON_Object_Type then
         return Result;
      end if;

      Result.Span := Parse_Span (Field_Or_Null (Value, "span"));
      if Has_Field (Value, "type") and then Get (Value, "type").Kind = JSON_String_Type then
         Result.Type_Name := FT.To_UString (Get (Value, "type"));
      end if;
      if Has_Field (Value, "tag") and then Get (Value, "tag").Kind = JSON_String_Type then
         Tag := FT.To_UString (Get (Value, "tag"));
      end if;
      if Has_Field (Value, "kind") and then Get (Value, "kind").Kind = JSON_String_Type then
         Kind_Name := FT.To_UString (Get (Value, "kind"));
      end if;

      if FT.To_String (Tag) = "int"
        or else
          (FT.To_String (Tag) = "literal"
           and then FT.To_String (Kind_Name) = "int_literal")
      then
         Result.Kind := GM.Expr_Int;
         if Has_Field (Value, "text") and then Get (Value, "text").Kind = JSON_String_Type then
            Result.Text := FT.To_UString (Get (Value, "text"));
         end if;
         if Has_Field (Value, "value") and then Get (Value, "value").Kind = JSON_Int_Type then
            Result.Int_Value := Get (Get (Value, "value"));
         end if;
      elsif FT.To_String (Tag) = "real"
        or else
          (FT.To_String (Tag) = "literal"
           and then FT.To_String (Kind_Name) = "real_literal")
      then
         Result.Kind := GM.Expr_Real;
         if Has_Field (Value, "text") and then Get (Value, "text").Kind = JSON_String_Type then
            Result.Text := FT.To_UString (Get (Value, "text"));
         end if;
      elsif FT.To_String (Tag) = "string" then
         Result.Kind := GM.Expr_String;
         if Has_Field (Value, "text") and then Get (Value, "text").Kind = JSON_String_Type then
            Result.Text := FT.To_UString (Get (Value, "text"));
         end if;
      elsif FT.To_String (Tag) = "char" then
         Result.Kind := GM.Expr_Char;
         if Has_Field (Value, "text") and then Get (Value, "text").Kind = JSON_String_Type then
            Result.Text := FT.To_UString (Get (Value, "text"));
         end if;
      elsif FT.To_String (Tag) = "bool"
        or else
          (FT.To_String (Tag) = "literal"
           and then FT.To_String (Kind_Name) = "bool_literal")
      then
         Result.Kind := GM.Expr_Bool;
         if Has_Field (Value, "value") and then Get (Value, "value").Kind = JSON_Boolean_Type then
            Result.Bool_Value := Get (Get (Value, "value"));
         end if;
      elsif FT.To_String (Tag) = "null"
        or else FT.To_String (Kind_Name) = "null_literal"
      then
         Result.Kind := GM.Expr_Null;
      elsif FT.To_String (Tag) = "ident" then
         Result.Kind := GM.Expr_Ident;
         if Has_Field (Value, "name") and then Get (Value, "name").Kind = JSON_String_Type then
            Result.Name := FT.To_UString (Get (Value, "name"));
         end if;
      elsif FT.To_String (Tag) = "select" then
         Result.Kind := GM.Expr_Select;
         Result.Prefix := Parse_Expr (Field_Or_Null (Value, "prefix"));
         if Has_Field (Value, "selector")
           and then Get (Value, "selector").Kind = JSON_String_Type
         then
            Result.Selector := FT.To_UString (Get (Value, "selector"));
         end if;
      elsif FT.To_String (Tag) = "resolved_index" then
         Result.Kind := GM.Expr_Resolved_Index;
         Result.Prefix := Parse_Expr (Field_Or_Null (Value, "prefix"));
         Parse_Expr_List (Json_Array_Or_Empty (Value, "indices"), Result.Indices);
      elsif FT.To_String (Tag) = "conversion" then
         Result.Kind := GM.Expr_Conversion;
         if Has_Field (Value, "target") then
            Result.Name := FT.To_UString (Flatten_Name (Get (Value, "target")));
         end if;
         Result.Inner := Parse_Expr (Field_Or_Null (Value, "expr"));
      elsif FT.To_String (Tag) = "call" then
         Result.Kind := GM.Expr_Call;
         Result.Callee := Parse_Expr (Field_Or_Null (Value, "callee"));
         Parse_Expr_List (Json_Array_Or_Empty (Value, "args"), Result.Args);
         if Has_Field (Value, "call_span")
           and then Get (Value, "call_span").Kind = JSON_Object_Type
         then
            Result.Has_Call_Span := True;
            Result.Call_Span := Parse_Span (Get (Value, "call_span"));
         end if;
      elsif FT.To_String (Tag) = "allocator" then
         Result.Kind := GM.Expr_Allocator;
         Result.Value := Parse_Expr (Field_Or_Null (Value, "value"));
      elsif FT.To_String (Tag) = "aggregate" then
         Result.Kind := GM.Expr_Aggregate;
         declare
            Items : constant JSON_Array := Json_Array_Or_Empty (Value, "fields");
         begin
            for Index in 1 .. Length (Items) loop
               declare
                  Item  : constant JSON_Value := Get (Items, Index);
                  Field : GM.Aggregate_Field;
               begin
                  if Item.Kind = JSON_Object_Type then
                     if Has_Field (Item, "field")
                       and then Get (Item, "field").Kind = JSON_String_Type
                     then
                        Field.Field := FT.To_UString (Get (Item, "field"));
                     end if;
                     Field.Expr :=
                       Parse_Expr
                         (Field_Or_Null (Item, "expr"));
                     Field.Span := Parse_Span (Field_Or_Null (Item, "span"));
                     Result.Fields.Append (Field);
                  end if;
               end;
            end loop;
         end;
      elsif FT.To_String (Tag) = "tuple" then
         Result.Kind := GM.Expr_Tuple;
         Parse_Expr_List (Json_Array_Or_Empty (Value, "elements"), Result.Elements);
      elsif FT.To_String (Tag) = "annotated" then
         Result.Kind := GM.Expr_Annotated;
         if Has_Field (Value, "subtype") then
            declare
               Subtype_Value : constant JSON_Value := Get (Value, "subtype");
            begin
               if Subtype_Value.Kind = JSON_Object_Type then
                  Result.Subtype_Name := FT.To_UString (Flatten_Name (Subtype_Value));
               elsif Subtype_Value.Kind = JSON_String_Type then
                  Result.Subtype_Name := FT.To_UString (Get (Subtype_Value));
               end if;
            end;
         end if;
         if Has_Field (Value, "expr") then
            Result.Inner := Parse_Expr (Get (Value, "expr"));
         else
            Result.Inner := Parse_Expr (Field_Or_Null (Value, "value"));
         end if;
      elsif FT.To_String (Tag) = "unary" then
         Result.Kind := GM.Expr_Unary;
         if Has_Field (Value, "op") and then Get (Value, "op").Kind = JSON_String_Type then
            Result.Operator := FT.To_UString (Get (Value, "op"));
         end if;
         Result.Inner := Parse_Expr (Field_Or_Null (Value, "expr"));
      elsif FT.To_String (Tag) = "binary" then
         Result.Kind := GM.Expr_Binary;
         if Has_Field (Value, "op") and then Get (Value, "op").Kind = JSON_String_Type then
            Result.Operator := FT.To_UString (Get (Value, "op"));
         end if;
         Result.Left := Parse_Expr (Field_Or_Null (Value, "left"));
         Result.Right := Parse_Expr (Field_Or_Null (Value, "right"));
      end if;

      return Result;
   end Parse_Expr;

   function Parse_Local
     (Value : GNATCOLL.JSON.JSON_Value) return GM.Local_Entry
   is
      use GNATCOLL.JSON;
      Result : GM.Local_Entry;
   begin
      if Value.Kind /= JSON_Object_Type then
         return Result;
      end if;

      if Has_Field (Value, "id") and then Get (Value, "id").Kind = JSON_String_Type then
         Result.Id := FT.To_UString (Get (Value, "id"));
      end if;
      if Has_Field (Value, "kind") and then Get (Value, "kind").Kind = JSON_String_Type then
         Result.Kind := FT.To_UString (Get (Value, "kind"));
      end if;
      if Has_Field (Value, "mode") and then Get (Value, "mode").Kind = JSON_String_Type then
         Result.Mode := FT.To_UString (Get (Value, "mode"));
      end if;
      if Has_Field (Value, "name") and then Get (Value, "name").Kind = JSON_String_Type then
         Result.Name := FT.To_UString (Get (Value, "name"));
      end if;
      if Has_Field (Value, "is_constant")
        and then Get (Value, "is_constant").Kind = JSON_Boolean_Type
      then
         Result.Is_Constant := Get (Get (Value, "is_constant"));
      end if;
      if Has_Field (Value, "ownership_role")
        and then Get (Value, "ownership_role").Kind = JSON_String_Type
      then
         Result.Ownership_Role := FT.To_UString (Get (Value, "ownership_role"));
      end if;
      if Has_Field (Value, "scope_id")
        and then Get (Value, "scope_id").Kind = JSON_String_Type
      then
         Result.Scope_Id := FT.To_UString (Get (Value, "scope_id"));
      end if;
      Result.Span := Parse_Span (Field_Or_Null (Value, "span"));
      Result.Type_Info := Parse_Type (Field_Or_Null (Value, "type"));
      return Result;
   end Parse_Local;

   function Parse_Scope
     (Value : GNATCOLL.JSON.JSON_Value) return GM.Scope_Entry
   is
      use GNATCOLL.JSON;
      Result : GM.Scope_Entry;
      Local_Ids    : constant JSON_Array := Json_Array_Or_Empty (Value, "local_ids");
      Exit_Blocks  : constant JSON_Array := Json_Array_Or_Empty (Value, "exit_blocks");
      Parent_Value : constant JSON_Value := Field_Or_Null (Value, "parent_scope_id");
   begin
      if Value.Kind /= JSON_Object_Type then
         return Result;
      end if;

      if Has_Field (Value, "id") and then Get (Value, "id").Kind = JSON_String_Type then
         Result.Id := FT.To_UString (Get (Value, "id"));
      end if;
      if Has_Field (Value, "kind") and then Get (Value, "kind").Kind = JSON_String_Type then
         Result.Kind := FT.To_UString (Get (Value, "kind"));
      end if;
      if Has_Field (Value, "entry_block")
        and then Get (Value, "entry_block").Kind = JSON_String_Type
      then
         Result.Entry_Block := FT.To_UString (Get (Value, "entry_block"));
      end if;
      if Parent_Value.Kind = JSON_String_Type then
         Result.Has_Parent_Scope := True;
         Result.Parent_Scope_Id := FT.To_UString (Get (Parent_Value));
      end if;

      for Index in 1 .. Length (Local_Ids) loop
         declare
            Item : constant JSON_Value := Get (Local_Ids, Index);
         begin
            if Item.Kind = JSON_String_Type then
               Result.Local_Ids.Append (FT.To_UString (Get (Item)));
            end if;
         end;
      end loop;
      for Index in 1 .. Length (Exit_Blocks) loop
         declare
            Item : constant JSON_Value := Get (Exit_Blocks, Index);
         begin
            if Item.Kind = JSON_String_Type then
               Result.Exit_Blocks.Append (FT.To_UString (Get (Item)));
            end if;
         end;
      end loop;
      return Result;
   end Parse_Scope;

   function Parse_Channel
     (Value : GNATCOLL.JSON.JSON_Value) return GM.Channel_Entry
   is
      use GNATCOLL.JSON;
      Result : GM.Channel_Entry;
   begin
      if Value.Kind /= JSON_Object_Type then
         return Result;
      end if;

      if Has_Field (Value, "name") and then Get (Value, "name").Kind = JSON_String_Type then
         Result.Name := FT.To_UString (Get (Value, "name"));
      end if;
      if Has_Field (Value, "element_type") then
         Result.Element_Type := Parse_Type (Get (Value, "element_type"));
      end if;
      if Has_Field (Value, "capacity") and then Get (Value, "capacity").Kind = JSON_Int_Type then
         Result.Capacity := Get (Get (Value, "capacity"));
      end if;
      if Has_Field (Value, "required_ceiling")
        and then Get (Value, "required_ceiling").Kind = JSON_Int_Type
      then
         Result.Has_Required_Ceiling := True;
         Result.Required_Ceiling := Get (Get (Value, "required_ceiling"));
      end if;
      Result.Span := Parse_Span (Field_Or_Null (Value, "span"));
      return Result;
   end Parse_Channel;

   function Parse_Effect_Summary
     (Value : GNATCOLL.JSON.JSON_Value) return GM.External_Effect_Summary
   is
      use GNATCOLL.JSON;
      Result  : GM.External_Effect_Summary;
      Reads   : constant JSON_Array := Json_Array_Or_Empty (Value, "reads");
      Writes  : constant JSON_Array := Json_Array_Or_Empty (Value, "writes");
      Inputs  : constant JSON_Array := Json_Array_Or_Empty (Value, "inputs");
      Outputs : constant JSON_Array := Json_Array_Or_Empty (Value, "outputs");
      Depends : constant JSON_Array := Json_Array_Or_Empty (Value, "depends");
   begin
      for Index in 1 .. Length (Reads) loop
         Result.Reads.Append (FT.To_UString (Get (Get (Reads, Index))));
      end loop;
      for Index in 1 .. Length (Writes) loop
         Result.Writes.Append (FT.To_UString (Get (Get (Writes, Index))));
      end loop;
      for Index in 1 .. Length (Inputs) loop
         Result.Inputs.Append (FT.To_UString (Get (Get (Inputs, Index))));
      end loop;
      for Index in 1 .. Length (Outputs) loop
         Result.Outputs.Append (FT.To_UString (Get (Get (Outputs, Index))));
      end loop;
      for Index in 1 .. Length (Depends) loop
         declare
            Dep_Item   : constant JSON_Value := Get (Depends, Index);
            Dep_Inputs : constant JSON_Array := Json_Array_Or_Empty (Dep_Item, "inputs");
            Dep        : GM.Summary_Depends_Entry;
         begin
            if Has_Field (Dep_Item, "output_name")
              and then Get (Dep_Item, "output_name").Kind = JSON_String_Type
            then
               Dep.Output_Name := FT.To_UString (Get (Dep_Item, "output_name"));
            end if;
            for Input_Index in 1 .. Length (Dep_Inputs) loop
               Dep.Inputs.Append
                 (FT.To_UString (Get (Get (Dep_Inputs, Input_Index))));
            end loop;
            Result.Depends.Append (Dep);
         end;
      end loop;
      return Result;
   end Parse_Effect_Summary;

   function Parse_Channel_Summary
     (Value : GNATCOLL.JSON.JSON_Value) return GM.External_Channel_Summary
   is
      use GNATCOLL.JSON;
      Result   : GM.External_Channel_Summary;
      Channels : constant JSON_Array := Json_Array_Or_Empty (Value, "channels");
      Sends    : constant JSON_Array := Json_Array_Or_Empty (Value, "sends");
      Receives : constant JSON_Array := Json_Array_Or_Empty (Value, "receives");
   begin
      for Index in 1 .. Length (Channels) loop
         Result.Channels.Append (FT.To_UString (Get (Get (Channels, Index))));
      end loop;
      for Index in 1 .. Length (Sends) loop
         Result.Sends.Append (FT.To_UString (Get (Get (Sends, Index))));
      end loop;
      for Index in 1 .. Length (Receives) loop
         Result.Receives.Append (FT.To_UString (Get (Get (Receives, Index))));
      end loop;
      return Result;
   end Parse_Channel_Summary;

   function Parse_External
     (Value : GNATCOLL.JSON.JSON_Value) return GM.External_Entry
   is
      use GNATCOLL.JSON;
      Result : GM.External_Entry;
      Params : constant JSON_Array := Json_Array_Or_Empty (Value, "params");
   begin
      if Value.Kind /= JSON_Object_Type then
         return Result;
      end if;

      if Has_Field (Value, "name") and then Get (Value, "name").Kind = JSON_String_Type then
         Result.Name := FT.To_UString (Get (Value, "name"));
      end if;
      if Has_Field (Value, "kind") and then Get (Value, "kind").Kind = JSON_String_Type then
         Result.Kind := FT.To_UString (Get (Value, "kind"));
      end if;
      if Has_Field (Value, "signature") and then Get (Value, "signature").Kind = JSON_String_Type then
         Result.Signature := FT.To_UString (Get (Value, "signature"));
      end if;
      if Has_Field (Value, "has_return_type")
        and then Get (Value, "has_return_type").Kind = JSON_Boolean_Type
      then
         Result.Has_Return_Type := Get (Get (Value, "has_return_type"));
      end if;
      if Has_Field (Value, "return_is_access_def")
        and then Get (Value, "return_is_access_def").Kind = JSON_Boolean_Type
      then
         Result.Return_Is_Access_Def := Get (Get (Value, "return_is_access_def"));
      end if;
      if Result.Has_Return_Type then
         Result.Return_Type := Parse_Type (Field_Or_Null (Value, "return_type"));
      end if;
      Result.Span := Parse_Span (Field_Or_Null (Value, "span"));
      for Index in 1 .. Length (Params) loop
         declare
            Param_Item : constant JSON_Value := Get (Params, Index);
            Param      : GM.Local_Entry;
         begin
            Param.Kind := FT.To_UString ("param");
            if Has_Field (Param_Item, "name")
              and then Get (Param_Item, "name").Kind = JSON_String_Type
            then
               Param.Name := FT.To_UString (Get (Param_Item, "name"));
            end if;
            if Has_Field (Param_Item, "mode")
              and then Get (Param_Item, "mode").Kind = JSON_String_Type
            then
               Param.Mode := FT.To_UString (Get (Param_Item, "mode"));
            end if;
            Param.Span := Parse_Span (Field_Or_Null (Param_Item, "span"));
            Param.Type_Info := Parse_Type (Field_Or_Null (Param_Item, "type"));
            Result.Params.Append (Param);
         end;
      end loop;
      Result.Effect_Summary := Parse_Effect_Summary (Field_Or_Null (Value, "effect_summary"));
      Result.Channel_Summary := Parse_Channel_Summary (Field_Or_Null (Value, "channel_access_summary"));
      return Result;
   end Parse_External;

   function Parse_Op
     (Value : GNATCOLL.JSON.JSON_Value) return GM.Op_Entry
   is
      use GNATCOLL.JSON;
      Result : GM.Op_Entry;
      Locals : constant JSON_Array := Json_Array_Or_Empty (Value, "locals");
      Name   : FT.UString := FT.To_UString ("");
   begin
      if Value.Kind /= JSON_Object_Type then
         return Result;
      end if;

      if Has_Field (Value, "kind") and then Get (Value, "kind").Kind = JSON_String_Type then
         Name := FT.To_UString (Get (Value, "kind"));
      end if;
      Result.Span := Parse_Span (Field_Or_Null (Value, "span"));
      Result.Ownership_Effect := Parse_Ownership_Effect (Field_Or_Null (Value, "ownership_effect"));

      if FT.To_String (Name) = "scope_enter" then
         Result.Kind := GM.Op_Scope_Enter;
      elsif FT.To_String (Name) = "scope_exit" then
         Result.Kind := GM.Op_Scope_Exit;
      elsif FT.To_String (Name) = "assign" then
         Result.Kind := GM.Op_Assign;
      elsif FT.To_String (Name) = "call" then
         Result.Kind := GM.Op_Call;
      elsif FT.To_String (Name) = "channel_send" then
         Result.Kind := GM.Op_Channel_Send;
      elsif FT.To_String (Name) = "channel_receive" then
         Result.Kind := GM.Op_Channel_Receive;
      elsif FT.To_String (Name) = "channel_try_send" then
         Result.Kind := GM.Op_Channel_Try_Send;
      elsif FT.To_String (Name) = "channel_try_receive" then
         Result.Kind := GM.Op_Channel_Try_Receive;
      elsif FT.To_String (Name) = "delay" then
         Result.Kind := GM.Op_Delay;
      else
         Result.Kind := GM.Op_Unknown;
      end if;

      if Has_Field (Value, "type") and then Get (Value, "type").Kind = JSON_String_Type then
         Result.Type_Name := FT.To_UString (Get (Value, "type"));
      end if;
      if Has_Field (Value, "scope_id")
        and then Get (Value, "scope_id").Kind = JSON_String_Type
      then
         Result.Scope_Id := FT.To_UString (Get (Value, "scope_id"));
      end if;
      if Has_Field (Value, "declaration_init")
        and then Get (Value, "declaration_init").Kind = JSON_Boolean_Type
      then
         Result.Has_Declaration_Init := True;
         Result.Declaration_Init_Valid := True;
         Result.Declaration_Init := Get (Get (Value, "declaration_init"));
      elsif Has_Field (Value, "declaration_init") then
         Result.Has_Declaration_Init := True;
      end if;

      for Index in 1 .. Length (Locals) loop
         declare
            Item : constant JSON_Value := Get (Locals, Index);
         begin
            if Item.Kind = JSON_String_Type then
               Result.Locals.Append (FT.To_UString (Get (Item)));
            end if;
         end;
      end loop;

      Result.Target := Parse_Expr (Field_Or_Null (Value, "target"));
      Result.Value := Parse_Expr (Field_Or_Null (Value, "value"));
      Result.Channel := Parse_Expr (Field_Or_Null (Value, "channel"));
      Result.Success_Target := Parse_Expr (Field_Or_Null (Value, "success_target"));
      return Result;
   end Parse_Op;

   function Parse_Select_Arm
     (Value : GNATCOLL.JSON.JSON_Value) return GM.Select_Arm_Entry
   is
      use GNATCOLL.JSON;
      Result : GM.Select_Arm_Entry;
      Name   : FT.UString := FT.To_UString ("");
   begin
      if Value.Kind /= JSON_Object_Type then
         return Result;
      end if;

      if Has_Field (Value, "kind") and then Get (Value, "kind").Kind = JSON_String_Type then
         Name := FT.To_UString (Get (Value, "kind"));
      end if;
      if FT.To_String (Name) = "channel" then
         Result.Kind := GM.Select_Arm_Channel;
      elsif FT.To_String (Name) = "delay" then
         Result.Kind := GM.Select_Arm_Delay;
      end if;

      case Result.Kind is
         when GM.Select_Arm_Channel =>
            if Has_Field (Value, "channel_name")
              and then Get (Value, "channel_name").Kind = JSON_String_Type
            then
               Result.Channel_Data.Channel_Name := FT.To_UString (Get (Value, "channel_name"));
            end if;
            if Has_Field (Value, "variable_name")
              and then Get (Value, "variable_name").Kind = JSON_String_Type
            then
               Result.Channel_Data.Variable_Name := FT.To_UString (Get (Value, "variable_name"));
            end if;
            if Has_Field (Value, "scope_id")
              and then Get (Value, "scope_id").Kind = JSON_String_Type
            then
               Result.Channel_Data.Scope_Id := FT.To_UString (Get (Value, "scope_id"));
            end if;
            if Has_Field (Value, "local_id")
              and then Get (Value, "local_id").Kind = JSON_String_Type
            then
               Result.Channel_Data.Local_Id := FT.To_UString (Get (Value, "local_id"));
            end if;
            if Has_Field (Value, "type") then
               Result.Channel_Data.Type_Info := Parse_Type (Get (Value, "type"));
            end if;
            if Has_Field (Value, "target")
              and then Get (Value, "target").Kind = JSON_String_Type
            then
               Result.Channel_Data.Target := FT.To_UString (Get (Value, "target"));
            end if;
            Result.Channel_Data.Span := Parse_Span (Field_Or_Null (Value, "span"));
         when GM.Select_Arm_Delay =>
            Result.Delay_Data.Duration_Expr := Parse_Expr (Field_Or_Null (Value, "duration_expr"));
            if Has_Field (Value, "target")
              and then Get (Value, "target").Kind = JSON_String_Type
            then
               Result.Delay_Data.Target := FT.To_UString (Get (Value, "target"));
            end if;
            Result.Delay_Data.Span := Parse_Span (Field_Or_Null (Value, "span"));
         when others =>
            null;
      end case;
      Result.Span := Parse_Span (Field_Or_Null (Value, "span"));
      return Result;
   end Parse_Select_Arm;

   function Parse_Terminator
     (Value : GNATCOLL.JSON.JSON_Value) return GM.Terminator_Entry
   is
      use GNATCOLL.JSON;
      Result : GM.Terminator_Entry;
      Name   : FT.UString := FT.To_UString ("");
      Arms   : constant JSON_Array := Json_Array_Or_Empty (Value, "arms");
   begin
      if Value.Kind /= JSON_Object_Type then
         return Result;
      end if;

      if Has_Field (Value, "kind") and then Get (Value, "kind").Kind = JSON_String_Type then
         Name := FT.To_UString (Get (Value, "kind"));
      end if;
      Result.Span := Parse_Span (Field_Or_Null (Value, "span"));
      Result.Ownership_Effect := Parse_Ownership_Effect (Field_Or_Null (Value, "ownership_effect"));

      if FT.To_String (Name) = "jump" then
         Result.Kind := GM.Terminator_Jump;
      elsif FT.To_String (Name) = "branch" then
         Result.Kind := GM.Terminator_Branch;
      elsif FT.To_String (Name) = "return" then
         Result.Kind := GM.Terminator_Return;
      elsif FT.To_String (Name) = "select" then
         Result.Kind := GM.Terminator_Select;
      else
         Result.Kind := GM.Terminator_Unknown;
      end if;

      if Has_Field (Value, "target") and then Get (Value, "target").Kind = JSON_String_Type then
         Result.Target := FT.To_UString (Get (Value, "target"));
      end if;
      if Has_Field (Value, "true_target")
        and then Get (Value, "true_target").Kind = JSON_String_Type
      then
         Result.True_Target := FT.To_UString (Get (Value, "true_target"));
      end if;
      if Has_Field (Value, "false_target")
        and then Get (Value, "false_target").Kind = JSON_String_Type
      then
         Result.False_Target := FT.To_UString (Get (Value, "false_target"));
      end if;

      Result.Condition := Parse_Expr (Field_Or_Null (Value, "condition"));
      if Has_Field (Value, "value")
        and then Get (Value, "value").Kind /= JSON_Null_Type
      then
         Result.Has_Value := True;
         Result.Value := Parse_Expr (Get (Value, "value"));
      end if;
      for Index in 1 .. Length (Arms) loop
         Result.Arms.Append (Parse_Select_Arm (Get (Arms, Index)));
      end loop;
      return Result;
   end Parse_Terminator;

   function Parse_Block
     (Value : GNATCOLL.JSON.JSON_Value) return GM.Block_Entry
   is
      use GNATCOLL.JSON;
      Result : GM.Block_Entry;
      Ops    : constant JSON_Array := Json_Array_Or_Empty (Value, "ops");
   begin
      if Value.Kind /= JSON_Object_Type then
         return Result;
      end if;

      if Has_Field (Value, "id") and then Get (Value, "id").Kind = JSON_String_Type then
         Result.Id := FT.To_UString (Get (Value, "id"));
      end if;
      if Has_Field (Value, "active_scope_id")
        and then Get (Value, "active_scope_id").Kind = JSON_String_Type
      then
         Result.Active_Scope_Id := FT.To_UString (Get (Value, "active_scope_id"));
      end if;
      if Has_Field (Value, "role") and then Get (Value, "role").Kind = JSON_String_Type then
         Result.Role := FT.To_UString (Get (Value, "role"));
      end if;
      if Has_Field (Value, "loop")
        and then Get (Value, "loop").Kind = JSON_Object_Type
      then
         declare
            Loop_Value : constant JSON_Value := Get (Value, "loop");
         begin
            Result.Has_Loop_Info := True;
            if Has_Field (Loop_Value, "kind")
              and then Get (Loop_Value, "kind").Kind = JSON_String_Type
            then
               Result.Loop_Kind := FT.To_UString (Get (Loop_Value, "kind"));
            end if;
            if Has_Field (Loop_Value, "loop_var")
              and then Get (Loop_Value, "loop_var").Kind = JSON_String_Type
            then
               Result.Loop_Var := FT.To_UString (Get (Loop_Value, "loop_var"));
            end if;
            if Has_Field (Loop_Value, "exit_target")
              and then Get (Loop_Value, "exit_target").Kind = JSON_String_Type
            then
               Result.Loop_Exit_Target := FT.To_UString (Get (Loop_Value, "exit_target"));
            end if;
         end;
      end if;
      Result.Span := Parse_Span (Field_Or_Null (Value, "span"));
      for Index in 1 .. Length (Ops) loop
         Result.Ops.Append (Parse_Op (Get (Ops, Index)));
      end loop;
      Result.Terminator := Parse_Terminator (Field_Or_Null (Value, "terminator"));
      return Result;
   end Parse_Block;

   function Parse_Graph
     (Value : GNATCOLL.JSON.JSON_Value) return GM.Graph_Entry
   is
      use GNATCOLL.JSON;
      Result : GM.Graph_Entry;
      Locals : constant JSON_Array := Json_Array_Or_Empty (Value, "locals");
      Scopes : constant JSON_Array := Json_Array_Or_Empty (Value, "scopes");
      Blocks : constant JSON_Array := Json_Array_Or_Empty (Value, "blocks");
   begin
      if Value.Kind /= JSON_Object_Type then
         return Result;
      end if;

      if Has_Field (Value, "name") and then Get (Value, "name").Kind = JSON_String_Type then
         Result.Name := FT.To_UString (Get (Value, "name"));
      end if;
      if Has_Field (Value, "kind") and then Get (Value, "kind").Kind = JSON_String_Type then
         Result.Kind := FT.To_UString (Get (Value, "kind"));
      end if;
      if Has_Field (Value, "entry_bb")
        and then Get (Value, "entry_bb").Kind = JSON_String_Type
      then
         Result.Entry_BB := FT.To_UString (Get (Value, "entry_bb"));
      end if;
      if Has_Field (Value, "span") and then Get (Value, "span").Kind = JSON_Object_Type then
         Result.Has_Span := True;
         Result.Span := Parse_Span (Get (Value, "span"));
      end if;
      if Has_Field (Value, "priority") and then Get (Value, "priority").Kind = JSON_Int_Type then
         Result.Has_Priority := True;
         Result.Priority := Get (Get (Value, "priority"));
      end if;
      if Has_Field (Value, "has_explicit_priority")
        and then Get (Value, "has_explicit_priority").Kind = JSON_Boolean_Type
      then
         Result.Has_Explicit_Priority := Get (Get (Value, "has_explicit_priority"));
      end if;
      if Has_Field (Value, "return_type") then
         Result.Has_Return_Type := Get (Value, "return_type").Kind /= JSON_Null_Type;
         if Result.Has_Return_Type then
            Result.Return_Type := Parse_Type (Get (Value, "return_type"));
         end if;
      end if;

      for Index in 1 .. Length (Locals) loop
         Result.Locals.Append (Parse_Local (Get (Locals, Index)));
      end loop;
      for Index in 1 .. Length (Scopes) loop
         Result.Scopes.Append (Parse_Scope (Get (Scopes, Index)));
      end loop;
      for Index in 1 .. Length (Blocks) loop
         Result.Blocks.Append (Parse_Block (Get (Blocks, Index)));
      end loop;
      return Result;
   end Parse_Graph;

   function Load_File (Path : String) return Load_Result is
      use GNATCOLL.JSON;

      Parsed : constant Read_Result := Read_File (Path);
      Root   : JSON_Value;
      Format : JSON_Value;
      Kind   : GM.Mir_Format_Kind;
      Result : GM.Mir_Document;
      Types    : JSON_Array;
      Channels : JSON_Array;
      Externals : JSON_Array;
      Graphs   : JSON_Array;
   begin
      if not Parsed.Success then
         return
           (Success => False,
            Message =>
              FT.To_UString
                (Path
                 & ": invalid JSON: "
                 & Format_Parsing_Error (Parsed.Error)));
      end if;

      Root := Parsed.Value;
      if Root.Kind /= JSON_Object_Type then
         return
           (Success => False,
            Message =>
              FT.To_UString (Path & ": top-level payload must be an object"));
      end if;

      if not Has_Field (Root, "format") then
         return
           (Success => False,
            Message =>
              FT.To_UString (Path & ": expected format mir-v1 or mir-v2"));
      end if;

      Format := Get (Root, "format");
      if Format.Kind /= JSON_String_Type then
         return
           (Success => False,
            Message =>
              FT.To_UString (Path & ": expected format mir-v1 or mir-v2"));
      end if;

      declare
         Value : constant String := Get (Format);
      begin
         if Value = "mir-v1" then
            Kind := GM.Mir_V1;
         elsif Value = "mir-v2" then
            Kind := GM.Mir_V2;
         else
            return
              (Success => False,
               Message =>
                 FT.To_UString (Path & ": expected format mir-v1 or mir-v2"));
         end if;
      end;

      Result.Path := FT.To_UString (Path);
      Result.Format := Kind;
      Result.Root := Root;
      if Has_Field (Root, "package_name")
        and then Get (Root, "package_name").Kind = JSON_String_Type
      then
         Result.Package_Name := FT.To_UString (Get (Root, "package_name"));
      end if;
      if Has_Field (Root, "source_path")
        and then Get (Root, "source_path").Kind = JSON_String_Type
      then
         Result.Has_Source_Path := True;
         Result.Source_Path := FT.To_UString (Get (Root, "source_path"));
      end if;

      Types := Json_Array_Or_Empty (Root, "types");
      for Index in 1 .. Length (Types) loop
         Result.Types.Append (Parse_Type (Get (Types, Index)));
      end loop;

      Channels := Json_Array_Or_Empty (Root, "channels");
      for Index in 1 .. Length (Channels) loop
         Result.Channels.Append (Parse_Channel (Get (Channels, Index)));
      end loop;

      Externals := Json_Array_Or_Empty (Root, "externals");
      for Index in 1 .. Length (Externals) loop
         Result.Externals.Append (Parse_External (Get (Externals, Index)));
      end loop;

      Graphs := Json_Array_Or_Empty (Root, "graphs");
      for Index in 1 .. Length (Graphs) loop
         Result.Graphs.Append (Parse_Graph (Get (Graphs, Index)));
      end loop;

      return (Success => True, Document => Result);
   end Load_File;
end Safe_Frontend.Mir_Json;
