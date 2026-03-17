with Ada.Characters.Latin_1;
with Ada.Containers.Indefinite_Vectors;
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Safe_Frontend.Json;
with Safe_Frontend.Mir_Bronze;
with Safe_Frontend.Mir_Model;
with Safe_Frontend.Types;

package body Safe_Frontend.Check_Emit is
   package GM renames Safe_Frontend.Mir_Model;
   package FT renames Safe_Frontend.Types;
   package JS renames Safe_Frontend.Json;
   package US renames Ada.Strings.Unbounded;

   package String_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => String);

   use type CM.Expr_Access;
   use type CM.Expr_Kind;
   use type CM.Discrete_Range_Kind;
   use type CM.Statement_Access;
   use type CM.Statement_Kind;
   use type CM.Package_Item_Kind;
   use type CM.Type_Decl_Kind;
   use type CM.Type_Spec_Kind;

   function Package_Item_Node
     (Item             : CM.Package_Item;
      Object_Index     : in out Natural;
      Subprogram_Index : in out Natural;
      Task_Index       : in out Natural;
      Resolved         : CM.Resolved_Unit) return String;

   function Declaration_Node
     (Decl      : CM.Object_Decl;
      Init_Expr : CM.Expr_Access := null) return String;

   function Statement_Node
     (Parsed   : CM.Statement_Access;
      Resolved : CM.Statement_Access) return String;

   function Expression_Node (Expr : CM.Expr_Access) return String;

   function Type_Json (Info : GM.Type_Descriptor) return String;

   function Operator_String (Value : FT.UString) return String is
   begin
      return FT.To_String (Value);
   end Operator_String;

   function Trimmed (Value : CM.Wide_Integer) return String is
   begin
      return Ada.Strings.Fixed.Trim (CM.Wide_Integer'Image (Value), Ada.Strings.Both);
   end Trimmed;

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

   function Quoted_Names (Names : FT.UString_Vectors.Vector) return String is
      Result : String_Vectors.Vector;
   begin
      if not Names.Is_Empty then
         for Name of Names loop
            Result.Append (JS.Quote (Name));
         end loop;
      end if;
      return Json_List (Result);
   end Quoted_Names;

   function Package_Name_Node
     (Name : String;
      Span : FT.Source_Span) return String
   is
      Result : US.Unbounded_String := US.Null_Unbounded_String;
      Start  : Positive := Name'First;
      Count  : Natural := 0;
   begin
      US.Append (Result, "{");
      US.Append (Result, """node_type"":""PackageName"",");
      US.Append (Result, """identifiers"":[");
      if Name'Length > 0 then
         for Index in Name'Range loop
            if Name (Index) = '.' then
               if Index > Start then
                  if Count > 0 then
                     US.Append (Result, ",");
                  end if;
                  Count := Count + 1;
                  US.Append (Result, JS.Quote (Name (Start .. Index - 1)));
               end if;
               Start := Index + 1;
            end if;
         end loop;
         if Start <= Name'Last then
            if Count > 0 then
               US.Append (Result, ",");
            end if;
            US.Append (Result, JS.Quote (Name (Start .. Name'Last)));
         end if;
      end if;
      US.Append (Result, "],");
      US.Append (Result, """span"":" & JS.Span_Object (Span));
      US.Append (Result, "}");
      return US.To_String (Result);
   end Package_Name_Node;

   function Name_From_String
     (Name : String;
      Span : FT.Source_Span) return String
   is
      Parts : String_Vectors.Vector;
      Start : Positive := Name'First;
      Result : US.Unbounded_String := US.Null_Unbounded_String;
   begin
      if Name'Length = 0 then
         return
           "{""node_type"":""DirectName"",""identifier"":"""",""span"":"
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
          ("{""node_type"":""DirectName"",""identifier"":"
           & JS.Quote (Parts (Parts.First_Index))
           & ",""span"":"
           & JS.Span_Object (Span)
           & "}");

      if Natural (Parts.Length) > 1 then
         for Index in Parts.First_Index + 1 .. Parts.Last_Index loop
            Result :=
              US.To_Unbounded_String
                ("{""node_type"":""SelectedComponent"",""prefix"":"
                 & US.To_String (Result)
                 & ",""selector"":"
                 & JS.Quote (Parts (Index))
                 & ",""resolved_kind"":null,""span"":"
                 & JS.Span_Object (Span)
                 & "}");
         end loop;
      end if;
      return US.To_String (Result);
   end Name_From_String;

   function Name_Node (Expr : CM.Expr_Access) return String;

   function Parameter_Associations
     (Args : CM.Expr_Access_Vectors.Vector;
      Span : FT.Source_Span) return String
   is
      Assocs : String_Vectors.Vector;
   begin
      if not Args.Is_Empty then
         for Item of Args loop
            Assocs.Append
              ("{""node_type"":""ParameterAssociation"",""formal_name"":null,""actual"":"
               & Expression_Node (Item)
               & ",""span"":"
               & JS.Span_Object (Item.Span)
               & "}");
         end loop;
      end if;
      return
        "{""node_type"":""ActualParameterPart"",""associations"":"
        & Json_List (Assocs)
        & ",""span"":"
        & JS.Span_Object (Span)
        & "}";
   end Parameter_Associations;

   function Name_Node (Expr : CM.Expr_Access) return String is
      Selector_Kind : constant String :=
        (if Expr /= null
            and then Expr.Kind = CM.Expr_Select
            and then FT.To_String (Expr.Selector) in "First" | "Last" | "Length" | "Access"
         then JS.Quote ("Attribute")
         elsif Expr /= null
           and then Expr.Kind = CM.Expr_Select
           and then FT.To_String (Expr.Selector) = "all"
         then JS.Quote ("ImplicitDereference")
         else "null");
      Call_Span : constant FT.Source_Span :=
        (if Expr /= null and then Expr.Has_Call_Span then Expr.Call_Span else FT.Null_Span);
   begin
      if Expr = null then
         return Name_From_String ("", FT.Null_Span);
      end if;

      case Expr.Kind is
         when CM.Expr_Ident =>
            return
              "{""node_type"":""DirectName"",""identifier"":"
              & JS.Quote (Expr.Name)
              & ",""span"":"
              & JS.Span_Object (Expr.Span)
              & "}";
         when CM.Expr_Select =>
            return
              "{""node_type"":""SelectedComponent"",""prefix"":"
              & Name_Node (Expr.Prefix)
              & ",""selector"":"
              & JS.Quote (Expr.Selector)
              & ",""resolved_kind"":"
              & Selector_Kind
              & ",""span"":"
              & JS.Span_Object (Expr.Span)
              & "}";
         when CM.Expr_Resolved_Index =>
            declare
               Indices : String_Vectors.Vector;
            begin
               for Arg of Expr.Args loop
                  Indices.Append (Expression_Node (Arg));
               end loop;
               return
                 "{""node_type"":""IndexedComponent"",""prefix"":"
                 & Name_Node (Expr.Prefix)
                 & ",""indices"":"
                 & Json_List (Indices)
                 & ",""span"":"
                 & JS.Span_Object (Expr.Span)
                 & "}";
            end;
         when CM.Expr_Call | CM.Expr_Apply =>
            return
              "{""node_type"":""FunctionCall"",""name"":"
              & Name_Node (Expr.Callee)
              & ",""parameters"":"
              & (if Expr.Args.Is_Empty then "null"
                 else Parameter_Associations
                   (Expr.Args,
                    (if Expr.Has_Call_Span then Expr.Call_Span else Expr.Span)))
              & ",""span"":"
              & JS.Span_Object (Expr.Span)
              & "}";
         when CM.Expr_Conversion =>
            return
              "{""node_type"":""TypeConversion"",""target_type"":"
              & Name_Node (Expr.Target)
              & ",""expression"":"
              & Expression_Node (Expr.Inner)
              & ",""span"":"
              & JS.Span_Object (Expr.Span)
              & "}";
         when others =>
            return Name_From_String (CM.Flatten_Name (Expr), Expr.Span);
      end case;
   end Name_Node;

   function Numeric_Literal_Node (Expr : CM.Expr_Access) return String is
      Text : constant String :=
        (if Expr /= null and then FT.To_String (Expr.Text)'Length > 0
         then FT.To_String (Expr.Text)
         else FT.To_String (Expr.Name));
   begin
      return
        "{""node_type"":""NumericLiteral"",""text"":"
        & JS.Quote (Text)
        & ",""is_based"":false,""is_real"":"
        & JS.Bool_Literal (Expr /= null and then Expr.Kind = CM.Expr_Real)
        & ",""resolved_value"":"
        & JS.Quote (Text)
        & ",""span"":"
        & JS.Span_Object (Expr.Span)
        & "}";
   end Numeric_Literal_Node;

   function Enum_Literal_Node
     (Value : String;
      Span  : FT.Source_Span) return String is
   begin
      return
        "{""node_type"":""EnumerationLiteral"",""kind"":""Identifier"",""value"":"
        & JS.Quote (Value)
        & ",""span"":"
        & JS.Span_Object (Span)
        & "}";
   end Enum_Literal_Node;

   function Type_Spec_Name
     (Spec : CM.Type_Spec) return String is
   begin
      if Spec.Kind = CM.Type_Spec_Access_Def then
         return Name_Node (Spec.Target_Name);
      end if;
      return Name_From_String (FT.To_String (Spec.Name), Spec.Span);
   end Type_Spec_Name;

   function Subtype_Indication_Node
     (Spec : CM.Type_Spec) return String is
   begin
      return
        "{""node_type"":""SubtypeIndication"",""is_not_null"":"
        & JS.Bool_Literal (Spec.Not_Null)
        & ",""subtype_mark"":"
        & Type_Spec_Name (Spec)
        & ",""constraint"":null,""span"":"
        & JS.Span_Object (Spec.Span)
        & "}";
   end Subtype_Indication_Node;

   function Access_Definition_Node
     (Spec : CM.Type_Spec) return String is
   begin
      return
        "{""node_type"":""AccessDefinition"",""is_not_null"":"
        & JS.Bool_Literal (Spec.Not_Null)
        & ",""is_all"":"
        & JS.Bool_Literal (Spec.Is_All)
        & ",""is_constant"":"
        & JS.Bool_Literal (Spec.Is_Constant)
        & ",""subtype_mark"":"
        & Name_Node (Spec.Target_Name)
        & ",""span"":"
        & JS.Span_Object (Spec.Span)
        & "}";
   end Access_Definition_Node;

   function Access_To_Object_Node
     (Spec : CM.Type_Spec) return String is
      Subtype_Spec : CM.Type_Spec := Spec;
   begin
      Subtype_Spec.Kind := CM.Type_Spec_Subtype_Indication;
      Subtype_Spec.Name := FT.To_UString (CM.Flatten_Name (Spec.Target_Name));
      return
        "{""node_type"":""AccessToObjectDefinition"",""is_not_null"":"
        & JS.Bool_Literal (Spec.Not_Null)
        & ",""is_all"":"
        & JS.Bool_Literal (Spec.Is_All)
        & ",""is_constant"":"
        & JS.Bool_Literal (Spec.Is_Constant)
        & ",""subtype_indication"":"
        & Subtype_Indication_Node (Subtype_Spec)
        & ",""span"":"
        & JS.Span_Object (Spec.Span)
        & "}";
   end Access_To_Object_Node;

   function Object_Type_Node (Spec : CM.Type_Spec) return String is
   begin
      if Spec.Kind = CM.Type_Spec_Access_Def then
         return Access_Definition_Node (Spec);
      end if;
      return Subtype_Indication_Node (Spec);
   end Object_Type_Node;

   function Primary_Node (Expr : CM.Expr_Access) return String;

   function Factor_Node (Expr : CM.Expr_Access) return String is
   begin
      if Expr /= null
        and then Expr.Kind = CM.Expr_Unary
        and then Operator_String (Expr.Operator) = "not"
      then
         return
           "{""node_type"":""Factor"",""kind"":""Not"",""primary"":"
           & Primary_Node (Expr.Inner)
           & ",""exponent"":null,""span"":"
           & JS.Span_Object (Expr.Span)
           & "}";
      end if;

      return
        "{""node_type"":""Factor"",""kind"":""Primary"",""primary"":"
        & Primary_Node (Expr)
        & ",""exponent"":null,""span"":"
        & JS.Span_Object ((if Expr = null then FT.Null_Span else Expr.Span))
        & "}";
   end Factor_Node;

   function Build_Term (Expr : CM.Expr_Access) return String is
      Factors : String_Vectors.Vector;
      Ops     : String_Vectors.Vector;

      procedure Collect (Item : CM.Expr_Access) is
      begin
         if Item /= null
           and then Item.Kind = CM.Expr_Binary
           and then Operator_String (Item.Operator) in "*" | "/" | "mod" | "rem"
         then
            Collect (Item.Left);
            Ops.Append (JS.Quote (Item.Operator));
            Factors.Append (Factor_Node (Item.Right));
         else
            Factors.Append (Factor_Node (Item));
         end if;
      end Collect;
   begin
      Collect (Expr);
      return
        "{""node_type"":""Term"",""factors"":"
        & Json_List (Factors)
        & ",""operators"":"
        & Json_List (Ops)
        & ",""span"":"
        & JS.Span_Object ((if Expr = null then FT.Null_Span else Expr.Span))
        & "}";
   end Build_Term;

   function Build_Simple_Expression (Expr : CM.Expr_Access) return String is
      Terms  : String_Vectors.Vector;
      Ops    : String_Vectors.Vector;
      Base   : CM.Expr_Access := Expr;
      Unary  : FT.UString := FT.To_UString ("null");

      procedure Collect (Item : CM.Expr_Access) is
      begin
         if Item /= null
           and then Item.Kind = CM.Expr_Binary
           and then Operator_String (Item.Operator) in "+" | "-"
         then
            Collect (Item.Left);
            Ops.Append (JS.Quote (Item.Operator));
            Terms.Append (Build_Term (Item.Right));
         else
            Terms.Append (Build_Term (Item));
         end if;
      end Collect;
   begin
      if Base /= null
        and then Base.Kind = CM.Expr_Unary
        and then Operator_String (Base.Operator) in "+" | "-"
      then
         Unary := FT.To_UString (JS.Quote (Base.Operator));
         Base := Base.Inner;
      end if;

      Collect (Base);
      return
        "{""node_type"":""SimpleExpression"",""unary_operator"":"
        & FT.To_String (Unary)
        & ",""terms"":"
        & Json_List (Terms)
        & ",""binary_operators"":"
        & Json_List (Ops)
        & ",""span"":"
        & JS.Span_Object ((if Expr = null then FT.Null_Span else Expr.Span))
        & "}";
   end Build_Simple_Expression;

   function Relation_Node (Expr : CM.Expr_Access) return String is
      Op : constant String :=
        (if Expr /= null and then Expr.Kind = CM.Expr_Binary
            and then Operator_String (Expr.Operator) in "==" | "!=" | "<" | "<=" | ">" | ">="
         then Operator_String (Expr.Operator)
         else "");
   begin
      if Op'Length > 0 then
         return
           "{""node_type"":""Relation"",""left"":"
           & Build_Simple_Expression (Expr.Left)
           & ",""operator"":"
           & JS.Quote (Op)
           & ",""right"":"
           & Build_Simple_Expression (Expr.Right)
           & ",""membership_test"":null,""span"":"
           & JS.Span_Object (Expr.Span)
           & "}";
      end if;

      return
        "{""node_type"":""Relation"",""left"":"
        & Build_Simple_Expression (Expr)
        & ",""operator"":null,""right"":null,""membership_test"":null,""span"":"
        & JS.Span_Object ((if Expr = null then FT.Null_Span else Expr.Span))
        & "}";
   end Relation_Node;

   function Expression_Node (Expr : CM.Expr_Access) return String is
      Relations : String_Vectors.Vector;
      Logical   : FT.UString := FT.To_UString ("null");

      procedure Collect (Item : CM.Expr_Access) is
      begin
         if Item /= null
           and then Item.Kind = CM.Expr_Binary
           and then Operator_String (Item.Operator) = "and then"
         then
            Logical := FT.To_UString (JS.Quote ("AndThen"));
            Collect (Item.Left);
            Relations.Append (Relation_Node (Item.Right));
         else
            Relations.Append (Relation_Node (Item));
         end if;
      end Collect;
   begin
      Collect (Expr);
      return
        "{""node_type"":""Expression"",""relations"":"
        & Json_List (Relations)
        & ",""logical_operator"":"
        & FT.To_String (Logical)
        & ",""resolved_type"":null,""wide_arithmetic"":null,""span"":"
        & JS.Span_Object ((if Expr = null then FT.Null_Span else Expr.Span))
        & "}";
   end Expression_Node;

   function Allocator_Node (Expr : CM.Expr_Access) return String is
   begin
      if Expr /= null
        and then Expr.Value /= null
        and then Expr.Value.Kind = CM.Expr_Annotated
        and then Expr.Value.Target /= null
      then
         return
           "{""node_type"":""Allocator"",""kind"":""Annotated"",""subtype_indication"":null,""expression"":"
           & Expression_Node (Expr.Value.Inner)
           & ",""subtype_mark"":"
           & Name_Node (Expr.Value.Target)
           & ",""span"":"
           & JS.Span_Object (Expr.Span)
           & "}";
      end if;

      if Expr /= null
        and then Expr.Value /= null
        and then Expr.Value.Kind = CM.Expr_Subtype_Indication
      then
         declare
            Spec : CM.Type_Spec;
         begin
            Spec.Kind := CM.Type_Spec_Subtype_Indication;
            Spec.Name := Expr.Value.Name;
            Spec.Span := Expr.Value.Span;
            return
              "{""node_type"":""Allocator"",""kind"":""SubtypeOnly"",""subtype_indication"":"
              & Subtype_Indication_Node (Spec)
              & ",""expression"":null,""subtype_mark"":null,""span"":"
              & JS.Span_Object (Expr.Span)
              & "}";
         end;
      end if;

      return
        "{""node_type"":""Allocator"",""kind"":""SubtypeOnly"",""subtype_indication"":null,""expression"":null,""subtype_mark"":null,""span"":"
        & JS.Span_Object ((if Expr = null then FT.Null_Span else Expr.Span))
        & "}";
   end Allocator_Node;

   function Record_Aggregate_Node (Expr : CM.Expr_Access) return String is
      Assocs : String_Vectors.Vector;
   begin
      if Expr /= null and then not Expr.Fields.Is_Empty then
         for Field of Expr.Fields loop
            Assocs.Append
              ("{""node_type"":""RecordComponentAssociation"",""choices"":{""node_type"":""ComponentChoiceList"",""is_others"":false,""selectors"":["
               & JS.Quote (Field.Field_Name)
               & "],""span"":"
               & JS.Span_Object (Field.Span)
               & "},""expression"":"
               & Expression_Node (Field.Expr)
               & ",""is_box"":false,""span"":"
               & JS.Span_Object (Field.Span)
               & "}");
         end loop;
      end if;
      return
        "{""node_type"":""RecordAggregate"",""is_null_record"":"
        & JS.Bool_Literal (Expr = null or else Expr.Fields.Is_Empty)
        & ",""associations"":"
        & Json_List (Assocs)
        & ",""span"":"
        & JS.Span_Object ((if Expr = null then FT.Null_Span else Expr.Span))
        & "}";
   end Record_Aggregate_Node;

   function Real_Range_Constraint_Node (Decl : CM.Type_Decl) return String is
   begin
      return
        "{""node_type"":""RealRangeConstraint"",""low_bound"":"
        & Expression_Node (Decl.Low_Expr)
        & ",""high_bound"":"
        & Expression_Node (Decl.High_Expr)
        & ",""span"":"
        & JS.Span_Object (Decl.Span)
        & "}";
   end Real_Range_Constraint_Node;

   function Discriminant_Part_Node (Decl : CM.Type_Decl) return String is
   begin
      if not Decl.Has_Discriminant then
         return "null";
      end if;

      return
        "{""node_type"":""KnownDiscriminantPart"",""discriminants"":[{""node_type"":""DiscriminantSpecification"",""names"":["
        & JS.Quote (Decl.Discriminant.Name)
        & "],""subtype_mark"":"
        & Type_Spec_Name (Decl.Discriminant.Disc_Type)
        & ",""default_expression"":"
        & (if Decl.Discriminant.Has_Default then Expression_Node (Decl.Discriminant.Default_Expr) else "null")
        & ",""span"":"
        & JS.Span_Object (Decl.Discriminant.Span)
        & "}],""span"":"
        & JS.Span_Object (Decl.Discriminant.Span)
        & "}";
   end Discriminant_Part_Node;

   function Bool_Choice_Expression
     (Value : Boolean;
      Span  : FT.Source_Span) return String
   is
      Expr : constant CM.Expr_Access := new CM.Expr_Node'
        (Kind       => CM.Expr_Bool,
         Span       => Span,
         Type_Name  => FT.To_UString ("Boolean"),
         Text       => FT.To_UString (""),
         Int_Value  => 0,
         Bool_Value => Value,
         others     => <>);
   begin
      return Expression_Node (Expr);
   end Bool_Choice_Expression;

   function Variant_Part_Node (Decl : CM.Type_Decl) return String is
      Variants   : String_Vectors.Vector;
      Components : String_Vectors.Vector;
   begin
      if Decl.Variants.Is_Empty then
         return "null";
      end if;

      for Alternative of Decl.Variants loop
         Components.Clear;
         if not Alternative.Components.Is_Empty then
            for Component of Alternative.Components loop
               Components.Append
                 ("{""node_type"":""ComponentItem"",""kind"":""ComponentDeclaration"",""item"":{""node_type"":""ComponentDeclaration"",""names"":"
                  & Quoted_Names (Component.Names)
                  & ",""component_definition"":{""node_type"":""ComponentDefinition"",""is_aliased"":false,""type_spec"":"
                  & Object_Type_Node (Component.Field_Type)
                  & ",""span"":"
                  & JS.Span_Object (Component.Field_Type.Span)
                  & "},""default_expression"":null,""span"":"
                  & JS.Span_Object (Component.Span)
                  & "},""span"":"
                  & JS.Span_Object (Component.Span)
                  & "}");
            end loop;
         end if;

         Variants.Append
           ("{""node_type"":""Variant"",""choices"":{""node_type"":""DiscreteChoiceList"",""choices"":[{""node_type"":""DiscreteChoice"",""kind"":""ChoiceExpression"",""value"":"
            & Bool_Choice_Expression (Alternative.When_Value, Alternative.Span)
            & ",""span"":"
            & JS.Span_Object (Alternative.Span)
            & "}],""span"":"
            & JS.Span_Object (Alternative.Span)
            & "},""component_list"":{""node_type"":""ComponentList"",""components"":"
            & Json_List (Components)
            & ",""variant_part"":null,""is_null"":"
            & JS.Bool_Literal (Components.Is_Empty)
            & ",""span"":"
            & JS.Span_Object (Alternative.Span)
            & "},""span"":"
            & JS.Span_Object (Alternative.Span)
            & "}");
      end loop;

      return
        "{""node_type"":""VariantPart"",""discriminant_name"":"
        & JS.Quote (Decl.Discriminant.Name)
        & ",""variants"":"
        & Json_List (Variants)
        & ",""span"":"
        & JS.Span_Object (Decl.Span)
        & "}";
   end Variant_Part_Node;

   function Component_List_Node (Decl : CM.Type_Decl) return String is
      Components : String_Vectors.Vector;
      Variant    : constant String := Variant_Part_Node (Decl);
   begin
      for Component of Decl.Components loop
         Components.Append
           ("{""node_type"":""ComponentItem"",""kind"":""ComponentDeclaration"",""item"":{""node_type"":""ComponentDeclaration"",""names"":"
            & Quoted_Names (Component.Names)
            & ",""component_definition"":{""node_type"":""ComponentDefinition"",""is_aliased"":false,""type_spec"":"
            & Object_Type_Node (Component.Field_Type)
            & ",""span"":"
            & JS.Span_Object (Component.Field_Type.Span)
            & "},""default_expression"":null,""span"":"
            & JS.Span_Object (Component.Span)
            & "},""span"":"
            & JS.Span_Object (Component.Span)
            & "}");
      end loop;

      if Components.Is_Empty and then Variant = "null" then
         return "null";
      end if;

      return
        "{""node_type"":""ComponentList"",""components"":"
        & Json_List (Components)
        & ",""variant_part"":"
        & Variant
        & ",""is_null"":"
        & JS.Bool_Literal (Components.Is_Empty and then Variant = "null")
        & ",""span"":"
        & JS.Span_Object (Decl.Span)
        & "}";
   end Component_List_Node;

   function Primary_Node (Expr : CM.Expr_Access) return String is
      Null_Span : constant FT.Source_Span :=
        (if Expr = null then FT.Null_Span else Expr.Span);
   begin
      if Expr = null then
         return
           "{""node_type"":""Primary"",""kind"":""ParenExpr"",""value"":"
           & Expression_Node (null)
           & ",""span"":"
           & JS.Span_Object (Null_Span)
           & "}";
      end if;

      case Expr.Kind is
         when CM.Expr_Int | CM.Expr_Real =>
            return
              "{""node_type"":""Primary"",""kind"":""Literal"",""value"":"
              & Numeric_Literal_Node (Expr)
              & ",""span"":"
              & JS.Span_Object (Expr.Span)
              & "}";
         when CM.Expr_Bool =>
            return
              "{""node_type"":""Primary"",""kind"":""Literal"",""value"":"
              & Enum_Literal_Node
                  ((if Expr.Bool_Value then "True" else "False"), Expr.Span)
              & ",""span"":"
              & JS.Span_Object (Expr.Span)
              & "}";
         when CM.Expr_Null =>
            return
              "{""node_type"":""Primary"",""kind"":""Literal"",""value"":"
              & Enum_Literal_Node ("null", Expr.Span)
              & ",""span"":"
              & JS.Span_Object (Expr.Span)
              & "}";
         when CM.Expr_String =>
            return
              "{""node_type"":""Primary"",""kind"":""Literal"",""value"":{""node_type"":""StringLiteral"",""text"":"
              & JS.Quote (Expr.Text)
              & ",""span"":"
              & JS.Span_Object (Expr.Span)
              & "},""span"":"
              & JS.Span_Object (Expr.Span)
              & "}";
         when CM.Expr_Char =>
            return
              "{""node_type"":""Primary"",""kind"":""Literal"",""value"":{""node_type"":""CharacterLiteral"",""text"":"
              & JS.Quote (Expr.Text)
              & ",""span"":"
              & JS.Span_Object (Expr.Span)
              & "},""span"":"
              & JS.Span_Object (Expr.Span)
              & "}";
         when CM.Expr_Allocator =>
            return
              "{""node_type"":""Primary"",""kind"":""Allocator"",""value"":"
              & Allocator_Node (Expr)
              & ",""span"":"
              & JS.Span_Object (Expr.Span)
              & "}";
         when CM.Expr_Aggregate =>
            return
              "{""node_type"":""Primary"",""kind"":""Aggregate"",""value"":"
              & Record_Aggregate_Node (Expr)
              & ",""span"":"
              & JS.Span_Object (Expr.Span)
              & "}";
         when CM.Expr_Annotated =>
            return
              "{""node_type"":""Primary"",""kind"":""AnnotatedExpr"",""value"":{""node_type"":""AnnotatedExpression"",""expression"":"
              & Expression_Node (Expr.Inner)
              & ",""subtype_mark"":"
              & Name_Node (Expr.Target)
              & ",""span"":"
              & JS.Span_Object (Expr.Span)
              & "},""span"":"
              & JS.Span_Object (Expr.Span)
              & "}";
         when CM.Expr_Ident
            | CM.Expr_Select
            | CM.Expr_Resolved_Index
            | CM.Expr_Call
            | CM.Expr_Conversion
            | CM.Expr_Apply =>
            return
              "{""node_type"":""Primary"",""kind"":""Name"",""value"":"
              & Name_Node (Expr)
              & ",""span"":"
              & JS.Span_Object (Expr.Span)
              & "}";
         when others =>
            return
              "{""node_type"":""Primary"",""kind"":""ParenExpr"",""value"":"
              & Expression_Node (Expr)
              & ",""span"":"
              & JS.Span_Object (Expr.Span)
              & "}";
      end case;
   end Primary_Node;

   function Discrete_Subtype_Node
     (Range_Info : CM.Discrete_Range) return String is
   begin
      if Range_Info.Kind = CM.Range_Explicit then
         return
           "{""node_type"":""DiscreteSubtypeDefinition"",""kind"":""Range"",""value"":{""node_type"":""Range"",""kind"":""Explicit"",""low"":"
           & Expression_Node (Range_Info.Low_Expr)
           & ",""high"":"
           & Expression_Node (Range_Info.High_Expr)
           & ",""prefix_name"":null,""dimension"":null,""span"":"
           & JS.Span_Object (Range_Info.Span)
           & "},""span"":"
           & JS.Span_Object (Range_Info.Span)
           & "}";
      end if;

      declare
         Spec : CM.Type_Spec;
      begin
         Spec.Kind := CM.Type_Spec_Subtype_Indication;
         Spec.Name := FT.To_UString (CM.Flatten_Name (Range_Info.Name_Expr));
         Spec.Span := Range_Info.Span;
         return
           "{""node_type"":""DiscreteSubtypeDefinition"",""kind"":""Subtype"",""value"":"
           & Subtype_Indication_Node (Spec)
           & ",""span"":"
           & JS.Span_Object (Range_Info.Span)
           & "}";
      end;
   end Discrete_Subtype_Node;

   function Type_Definition_Node (Decl : CM.Type_Decl) return String is
      Indexes : String_Vectors.Vector;
      Components : String_Vectors.Vector;
   begin
      case Decl.Kind is
         when CM.Type_Decl_Incomplete =>
            return
              "{""node_type"":""IncompleteTypeDeclaration"",""is_public"":"
              & JS.Bool_Literal (Decl.Is_Public)
              & ",""name"":"
              & JS.Quote (Decl.Name)
              & ",""span"":"
              & JS.Span_Object (Decl.Span)
              & "}";
         when CM.Type_Decl_Integer =>
            return
              "{""node_type"":""TypeDeclaration"",""is_public"":"
              & JS.Bool_Literal (Decl.Is_Public)
              & ",""name"":"
              & JS.Quote (Decl.Name)
              & ",""discriminant_part"":"
              & Discriminant_Part_Node (Decl)
              & ",""type_definition"":{""node_type"":""SignedIntegerTypeDefinition"",""low_bound"":"
              & Expression_Node (Decl.Low_Expr)
              & ",""high_bound"":"
              & Expression_Node (Decl.High_Expr)
              & ",""span"":"
              & JS.Span_Object (Decl.Span)
              & "},""span"":"
              & JS.Span_Object (Decl.Span)
              & "}";
         when CM.Type_Decl_Float =>
            return
              "{""node_type"":""TypeDeclaration"",""is_public"":"
              & JS.Bool_Literal (Decl.Is_Public)
              & ",""name"":"
              & JS.Quote (Decl.Name)
              & ",""discriminant_part"":"
              & Discriminant_Part_Node (Decl)
              & ",""type_definition"":{""node_type"":""FloatingPointDefinition"",""digits_expr"":"
              & Expression_Node (Decl.Digits_Expr)
              & ",""range_constraint"":"
              & Real_Range_Constraint_Node (Decl)
              & ",""span"":"
              & JS.Span_Object (Decl.Span)
              & "},""span"":"
              & JS.Span_Object (Decl.Span)
              & "}";
         when CM.Type_Decl_Constrained_Array =>
            for Index_Item of Decl.Indexes loop
               declare
                  Range_Info : CM.Discrete_Range;
               begin
                  Range_Info.Kind := CM.Range_Subtype;
                  Range_Info.Name_Expr := Index_Item.Name_Expr;
                  Range_Info.Span := Index_Item.Span;
                  Indexes.Append (Discrete_Subtype_Node (Range_Info));
               end;
            end loop;
            return
              "{""node_type"":""TypeDeclaration"",""is_public"":"
              & JS.Bool_Literal (Decl.Is_Public)
              & ",""name"":"
              & JS.Quote (Decl.Name)
              & ",""discriminant_part"":"
              & Discriminant_Part_Node (Decl)
              & ",""type_definition"":{""node_type"":""ConstrainedArrayDefinition"",""index_ranges"":"
              & Json_List (Indexes)
              & ",""component_definition"":{""node_type"":""ComponentDefinition"",""is_aliased"":false,""type_spec"":"
              & Object_Type_Node (Decl.Component_Type)
              & ",""span"":"
              & JS.Span_Object (Decl.Component_Type.Span)
              & "},""span"":"
              & JS.Span_Object (Decl.Span)
              & "},""span"":"
              & JS.Span_Object (Decl.Span)
              & "}";
         when CM.Type_Decl_Unconstrained_Array =>
            for Index_Item of Decl.Indexes loop
               Indexes.Append
                 ("{""node_type"":""IndexSubtypeDefinition"",""subtype_mark"":"
                  & Name_Node (Index_Item.Name_Expr)
                  & ",""span"":"
                  & JS.Span_Object (Index_Item.Span)
                  & "}");
            end loop;
            return
              "{""node_type"":""TypeDeclaration"",""is_public"":"
              & JS.Bool_Literal (Decl.Is_Public)
              & ",""name"":"
              & JS.Quote (Decl.Name)
              & ",""discriminant_part"":"
              & Discriminant_Part_Node (Decl)
              & ",""type_definition"":{""node_type"":""UnconstrainedArrayDefinition"",""index_subtypes"":"
              & Json_List (Indexes)
              & ",""component_definition"":{""node_type"":""ComponentDefinition"",""is_aliased"":false,""type_spec"":"
              & Object_Type_Node (Decl.Component_Type)
              & ",""span"":"
              & JS.Span_Object (Decl.Component_Type.Span)
              & "},""span"":"
              & JS.Span_Object (Decl.Span)
              & "},""span"":"
              & JS.Span_Object (Decl.Span)
              & "}";
         when CM.Type_Decl_Record =>
            declare
               Component_List : constant String := Component_List_Node (Decl);
            begin
               return
                 "{""node_type"":""TypeDeclaration"",""is_public"":"
                 & JS.Bool_Literal (Decl.Is_Public)
                 & ",""name"":"
                 & JS.Quote (Decl.Name)
                 & ",""discriminant_part"":"
                 & Discriminant_Part_Node (Decl)
                 & ",""type_definition"":{""node_type"":""RecordTypeDefinition"""
                 & ",""is_limited"":false,""is_private"":false"
                 & ",""record_definition"":{""node_type"":""RecordDefinition"""
                 & ",""is_null_record"":"
                 & JS.Bool_Literal (Component_List = "null")
                 & ",""component_list"":"
                 & Component_List
                 & ",""span"":"
                 & JS.Span_Object (Decl.Span)
                 & "},""span"":"
                 & JS.Span_Object (Decl.Span)
                 & "},""span"":"
                 & JS.Span_Object (Decl.Span)
                 & "}";
            end;
         when CM.Type_Decl_Access =>
            return
              "{""node_type"":""TypeDeclaration"",""is_public"":"
              & JS.Bool_Literal (Decl.Is_Public)
              & ",""name"":"
              & JS.Quote (Decl.Name)
              & ",""discriminant_part"":"
              & Discriminant_Part_Node (Decl)
              & ",""type_definition"":"
              & Access_To_Object_Node (Decl.Access_Type)
              & ",""span"":"
              & JS.Span_Object (Decl.Span)
              & "}";
         when others =>
            return
              "{""node_type"":""TypeDeclaration"",""is_public"":"
              & JS.Bool_Literal (Decl.Is_Public)
              & ",""name"":"
              & JS.Quote (Decl.Name)
              & ",""discriminant_part"":"
              & Discriminant_Part_Node (Decl)
              & ",""type_definition"":{""node_type"":""SignedIntegerTypeDefinition"",""low_bound"":"
              & Expression_Node (Decl.Low_Expr)
              & ",""high_bound"":"
              & Expression_Node (Decl.High_Expr)
              & ",""span"":"
              & JS.Span_Object (Decl.Span)
              & "},""span"":"
              & JS.Span_Object (Decl.Span)
              & "}";
      end case;
   end Type_Definition_Node;

   function Declaration_Node
     (Decl      : CM.Object_Decl;
      Init_Expr : CM.Expr_Access := null) return String
   is
      Names : String_Vectors.Vector;
      Initializer : constant CM.Expr_Access :=
        (if Init_Expr /= null then Init_Expr else Decl.Initializer);
   begin
      for Name of Decl.Names loop
         Names.Append (JS.Quote (Name));
      end loop;
      return
        "{""node_type"":""ObjectDeclaration"",""is_public"":"
        & JS.Bool_Literal (Decl.Is_Public)
        & ",""names"":"
        & Json_List (Names)
        & ",""is_aliased"":false,""is_constant"":"
        & JS.Bool_Literal (Decl.Is_Constant)
        & ",""object_type"":"
        & Object_Type_Node (Decl.Decl_Type)
        & ",""initializer"":"
        & (if Decl.Has_Initializer and then Initializer /= null
           then Expression_Node (Initializer)
           else "null")
        & ",""span"":"
        & JS.Span_Object (Decl.Span)
        & "}";
   end Declaration_Node;

   function Sequence_Node
     (Parsed_Items   : CM.Statement_Access_Vectors.Vector;
      Resolved_Items : CM.Statement_Access_Vectors.Vector;
      Span           : FT.Source_Span) return String
   is
      Items : String_Vectors.Vector;
      Parsed_Stmt : CM.Statement_Access;
      Resolved_Stmt : CM.Statement_Access;
   begin
      if not Parsed_Items.Is_Empty then
         for Index in Parsed_Items.First_Index .. Parsed_Items.Last_Index loop
            Parsed_Stmt := Parsed_Items (Index);
            if not Resolved_Items.Is_Empty
              and then Index in Resolved_Items.First_Index .. Resolved_Items.Last_Index
            then
               Resolved_Stmt := Resolved_Items (Index);
            else
               Resolved_Stmt := Parsed_Stmt;
            end if;
            if Parsed_Stmt.Kind = CM.Stmt_Object_Decl then
               Items.Append
                 ("{""node_type"":""InterleavedItem"",""kind"":""BasicDeclaration"",""item"":"
                  & Declaration_Node
                      (Parsed_Stmt.Decl,
                       (if Resolved_Stmt /= null and then Resolved_Stmt.Kind = CM.Stmt_Object_Decl
                        then Resolved_Stmt.Decl.Initializer
                        else null))
                  & ",""span"":"
                  & JS.Span_Object (Parsed_Stmt.Span)
                  & "}");
            else
               Items.Append
                 ("{""node_type"":""InterleavedItem"",""kind"":""Statement"",""item"":"
                  & Statement_Node (Parsed_Stmt, Resolved_Stmt)
                  & ",""span"":"
                  & JS.Span_Object (Parsed_Stmt.Span)
                  & "}");
            end if;
         end loop;
      end if;
      return
        "{""node_type"":""SequenceOfStatements"",""items"":"
        & Json_List (Items)
        & ",""span"":"
        & JS.Span_Object (Span)
        & "}";
   end Sequence_Node;

   function Select_Arm_Node
     (Parsed   : CM.Select_Arm;
      Resolved : CM.Select_Arm) return String is
   begin
      case Parsed.Kind is
         when CM.Select_Arm_Channel =>
            return
              "{""node_type"":""SelectArm"",""kind"":""Channel"",""arm"":{""node_type"":""ChannelArm"",""variable_name"":"
              & JS.Quote (Parsed.Channel_Data.Variable_Name)
              & ",""subtype_mark"":"
              & Type_Spec_Name (Parsed.Channel_Data.Subtype_Mark)
              & ",""channel_name"":"
              & Name_Node (Resolved.Channel_Data.Channel_Name)
              & ",""statements"":"
              & Sequence_Node
                  (Parsed.Channel_Data.Statements,
                   Resolved.Channel_Data.Statements,
                   Parsed.Channel_Data.Span)
              & ",""span"":"
              & JS.Span_Object (Parsed.Channel_Data.Span)
              & "},""span"":"
              & JS.Span_Object (Parsed.Span)
              & "}";
         when CM.Select_Arm_Delay =>
            return
              "{""node_type"":""SelectArm"",""kind"":""Delay"",""arm"":{""node_type"":""DelayArm"",""duration_expr"":"
              & Expression_Node (Resolved.Delay_Data.Duration_Expr)
              & ",""statements"":"
              & Sequence_Node
                  (Parsed.Delay_Data.Statements,
                   Resolved.Delay_Data.Statements,
                   Parsed.Delay_Data.Span)
              & ",""span"":"
              & JS.Span_Object (Parsed.Delay_Data.Span)
              & "},""span"":"
              & JS.Span_Object (Parsed.Span)
              & "}";
         when others =>
            return
              "{""node_type"":""SelectArm"",""kind"":""Channel"",""arm"":null,""span"":"
              & JS.Span_Object (Parsed.Span)
              & "}";
      end case;
   end Select_Arm_Node;

   function Statement_Node
     (Parsed   : CM.Statement_Access;
      Resolved : CM.Statement_Access) return String
   is
      Resolved_Expr : constant CM.Statement_Access :=
        (if Resolved /= null then Resolved else Parsed);
      Elsifs : String_Vectors.Vector;
      Decls  : String_Vectors.Vector;
      Resolved_Decl : CM.Object_Decl;
   begin
      if Parsed = null then
         return "{""node_type"":""NullStatement"",""span"":"
           & JS.Span_Object (FT.Null_Span)
           & "}";
      end if;

      case Parsed.Kind is
         when CM.Stmt_Null =>
            return
              "{""node_type"":""NullStatement"",""span"":"
              & JS.Span_Object (Parsed.Span)
              & "}";
         when CM.Stmt_Object_Decl =>
            raise Program_Error with "object declarations must be emitted via Sequence_Node";
         when CM.Stmt_Assign =>
            return
              "{""node_type"":""AssignmentStatement"",""target"":"
              & Name_Node (Resolved_Expr.Target)
              & ",""expression"":"
              & Expression_Node (Resolved_Expr.Value)
              & ",""ownership_action"":null,""span"":"
              & JS.Span_Object (Parsed.Span)
              & "}";
         when CM.Stmt_Call =>
            declare
               Call_Expr : constant CM.Expr_Access := Resolved_Expr.Call;
               Name_Value : constant CM.Expr_Access :=
                 (if Call_Expr /= null and then Call_Expr.Kind = CM.Expr_Call then Call_Expr.Callee
                  else Call_Expr);
               Args : constant CM.Expr_Access_Vectors.Vector :=
                 (if Call_Expr /= null and then Call_Expr.Kind = CM.Expr_Call then Call_Expr.Args
                  else CM.Expr_Access_Vectors.Empty_Vector);
            begin
               return
                 "{""node_type"":""ProcedureCallStatement"",""name"":"
                 & Name_Node (Name_Value)
                 & ",""parameters"":"
                 & (if Args.Is_Empty then "null"
                    else Parameter_Associations
                      (Args,
                       (if Call_Expr /= null and then Call_Expr.Has_Call_Span
                        then Call_Expr.Call_Span
                        else Parsed.Span)))
                 & ",""span"":"
                 & JS.Span_Object (Parsed.Span)
                 & "}";
            end;
         when CM.Stmt_Return =>
            return
              "{""node_type"":""SimpleReturnStatement"",""expression"":"
              & (if Resolved_Expr.Value = null then "null"
                 else Expression_Node (Resolved_Expr.Value))
              & ",""span"":"
              & JS.Span_Object (Parsed.Span)
              & "}";
         when CM.Stmt_If =>
            if not Parsed.Elsifs.Is_Empty then
               for Index in Parsed.Elsifs.First_Index .. Parsed.Elsifs.Last_Index loop
                  declare
                     Parsed_Part : constant CM.Elsif_Part := Parsed.Elsifs (Index);
                     Resolved_Part : constant CM.Elsif_Part :=
                       (if not Resolved_Expr.Elsifs.Is_Empty
                           and then Index in Resolved_Expr.Elsifs.First_Index .. Resolved_Expr.Elsifs.Last_Index
                        then Resolved_Expr.Elsifs (Index)
                        else Parsed_Part);
                  begin
                     Elsifs.Append
                       ("{""node_type"":""ElsifPart"",""condition"":"
                        & Expression_Node (Resolved_Part.Condition)
                        & ",""then_stmts"":"
                        & Sequence_Node
                            (Parsed_Part.Statements,
                             Resolved_Part.Statements,
                             Parsed_Part.Span)
                        & ",""span"":"
                        & JS.Span_Object (Parsed_Part.Span)
                        & "}");
                  end;
               end loop;
            end if;
            return
              "{""node_type"":""IfStatement"",""condition"":"
              & Expression_Node (Resolved_Expr.Condition)
              & ",""then_stmts"":"
              & Sequence_Node
                  (Parsed.Then_Stmts,
                   Resolved_Expr.Then_Stmts,
                   Parsed.Span)
              & ",""elsif_parts"":"
              & Json_List (Elsifs)
              & ",""else_stmts"":"
              & (if Parsed.Has_Else
                 then Sequence_Node
                    (Parsed.Else_Stmts,
                     Resolved_Expr.Else_Stmts,
                     Parsed.Span)
                 else "null")
              & ",""span"":"
              & JS.Span_Object (Parsed.Span)
              & "}";
         when CM.Stmt_Case =>
            declare
               Alts : String_Vectors.Vector;
            begin
               if not Parsed.Case_Arms.Is_Empty then
                  for Index in Parsed.Case_Arms.First_Index .. Parsed.Case_Arms.Last_Index loop
                     declare
                        Parsed_Arm : constant CM.Case_Arm := Parsed.Case_Arms (Index);
                        Resolved_Arm : constant CM.Case_Arm :=
                          (if not Resolved_Expr.Case_Arms.Is_Empty
                              and then Index in Resolved_Expr.Case_Arms.First_Index .. Resolved_Expr.Case_Arms.Last_Index
                           then Resolved_Expr.Case_Arms (Index)
                           else Parsed_Arm);
                        Choices : constant String :=
                          (if Parsed_Arm.Is_Others
                           then
                             "{""node_type"":""DiscreteChoiceList"",""choices"":[{""node_type"":""DiscreteChoice"",""kind"":""Others"",""value"":null,""span"":"
                             & JS.Span_Object (Parsed_Arm.Span)
                             & "}],""span"":"
                             & JS.Span_Object (Parsed_Arm.Span)
                             & "}"
                           else
                             "{""node_type"":""DiscreteChoiceList"",""choices"":[{""node_type"":""DiscreteChoice"",""kind"":""ChoiceExpression"",""value"":"
                             & Expression_Node (Resolved_Arm.Choice)
                             & ",""span"":"
                             & JS.Span_Object (Parsed_Arm.Span)
                             & "}],""span"":"
                             & JS.Span_Object (Parsed_Arm.Span)
                             & "}");
                     begin
                        Alts.Append
                          ("{""node_type"":""CaseStatementAlternative"",""choices"":"
                           & Choices
                           & ",""statements"":"
                           & Sequence_Node
                               (Parsed_Arm.Statements,
                                Resolved_Arm.Statements,
                                Parsed_Arm.Span)
                           & ",""span"":"
                           & JS.Span_Object (Parsed_Arm.Span)
                           & "}");
                     end;
                  end loop;
               end if;
               return
                 "{""node_type"":""CaseStatement"",""expression"":"
                 & Expression_Node (Resolved_Expr.Case_Expr)
                 & ",""alternatives"":"
                 & Json_List (Alts)
                 & ",""span"":"
                 & JS.Span_Object (Parsed.Span)
                 & "}";
            end;
         when CM.Stmt_While =>
            return
              "{""node_type"":""LoopStatement"",""loop_name"":null,""iteration_scheme"":{""node_type"":""IterationScheme"",""kind"":""While"",""condition"":"
              & Expression_Node (Resolved_Expr.Condition)
              & ",""loop_variable"":null,""is_reverse"":false,""discrete_range"":null,""iterable_name"":null,""span"":"
              & JS.Span_Object (Parsed.Span)
              & "},""body"":"
              & Sequence_Node
                  (Parsed.Body_Stmts,
                   Resolved_Expr.Body_Stmts,
                   Parsed.Span)
              & ",""end_loop_name"":null,""span"":"
              & JS.Span_Object (Parsed.Span)
              & "}";
         when CM.Stmt_Loop =>
            return
              "{""node_type"":""LoopStatement"",""loop_name"":null,""iteration_scheme"":null,""body"":"
              & Sequence_Node
                  (Parsed.Body_Stmts,
                   Resolved_Expr.Body_Stmts,
                   Parsed.Span)
              & ",""end_loop_name"":null,""span"":"
              & JS.Span_Object (Parsed.Span)
              & "}";
         when CM.Stmt_Exit =>
            return
              "{""node_type"":""ExitStatement"",""loop_name"":null,""condition"":"
              & (if Resolved_Expr.Condition = null
                 then "null"
                 else Expression_Node (Resolved_Expr.Condition))
              & ",""span"":"
              & JS.Span_Object (Parsed.Span)
              & "}";
         when CM.Stmt_For =>
            return
              "{""node_type"":""LoopStatement"",""loop_name"":null,""iteration_scheme"":{""node_type"":""IterationScheme"",""kind"":""ForIn"",""condition"":null,""loop_variable"":"
              & JS.Quote (Parsed.Loop_Var)
              & ",""is_reverse"":false,""discrete_range"":"
              & Discrete_Subtype_Node (Resolved_Expr.Loop_Range)
              & ",""iterable_name"":null,""span"":"
              & JS.Span_Object (Parsed.Span)
              & "},""body"":"
              & Sequence_Node
                  (Parsed.Body_Stmts,
                   Resolved_Expr.Body_Stmts,
                   Parsed.Span)
              & ",""end_loop_name"":null,""span"":"
              & JS.Span_Object (Parsed.Span)
              & "}";
         when CM.Stmt_Block =>
            if not Parsed.Declarations.Is_Empty then
               for Index in Parsed.Declarations.First_Index .. Parsed.Declarations.Last_Index loop
                  if not Resolved_Expr.Declarations.Is_Empty
                    and then Index in Resolved_Expr.Declarations.First_Index .. Resolved_Expr.Declarations.Last_Index
                  then
                     Resolved_Decl := Resolved_Expr.Declarations.Element (Index);
                     Decls.Append
                       (Declaration_Node
                          (Parsed.Declarations (Index),
                           Resolved_Decl.Initializer));
                  else
                     Decls.Append (Declaration_Node (Parsed.Declarations (Index)));
                  end if;
               end loop;
            end if;
            return
              "{""node_type"":""BlockStatement"",""block_name"":null,""declarations"":"
              & Json_List (Decls)
              & ",""body"":"
              & Sequence_Node
                  (Parsed.Body_Stmts,
                   Resolved_Expr.Body_Stmts,
                   Parsed.Span)
              & ",""end_block_name"":null,""span"":"
              & JS.Span_Object (Parsed.Span)
              & "}";
         when CM.Stmt_Send =>
            return
              "{""node_type"":""SendStatement"",""channel_name"":"
              & Name_Node (Resolved_Expr.Channel_Name)
              & ",""expression"":"
              & Expression_Node (Resolved_Expr.Value)
              & ",""span"":"
              & JS.Span_Object (Parsed.Span)
              & "}";
         when CM.Stmt_Receive =>
            return
              "{""node_type"":""ReceiveStatement"",""channel_name"":"
              & Name_Node (Resolved_Expr.Channel_Name)
              & ",""target"":"
              & Name_Node (Resolved_Expr.Target)
              & ",""span"":"
              & JS.Span_Object (Parsed.Span)
              & "}";
         when CM.Stmt_Try_Send =>
            return
              "{""node_type"":""TrySendStatement"",""channel_name"":"
              & Name_Node (Resolved_Expr.Channel_Name)
              & ",""expression"":"
              & Expression_Node (Resolved_Expr.Value)
              & ",""success_var"":"
              & Name_Node (Resolved_Expr.Success_Var)
              & ",""span"":"
              & JS.Span_Object (Parsed.Span)
              & "}";
         when CM.Stmt_Try_Receive =>
            return
              "{""node_type"":""TryReceiveStatement"",""channel_name"":"
              & Name_Node (Resolved_Expr.Channel_Name)
              & ",""target"":"
              & Name_Node (Resolved_Expr.Target)
              & ",""success_var"":"
              & Name_Node (Resolved_Expr.Success_Var)
              & ",""span"":"
              & JS.Span_Object (Parsed.Span)
              & "}";
         when CM.Stmt_Delay =>
            return
              "{""node_type"":""DelayStatement"",""expression"":"
              & Expression_Node (Resolved_Expr.Value)
              & ",""span"":"
              & JS.Span_Object (Parsed.Span)
              & "}";
         when CM.Stmt_Select =>
            declare
               Arms : String_Vectors.Vector;
            begin
               if not Parsed.Arms.Is_Empty then
                  for Index in Parsed.Arms.First_Index .. Parsed.Arms.Last_Index loop
                     Arms.Append
                       (Select_Arm_Node
                          (Parsed.Arms (Index),
                           (if not Resolved_Expr.Arms.Is_Empty
                               and then Index in Resolved_Expr.Arms.First_Index .. Resolved_Expr.Arms.Last_Index
                            then Resolved_Expr.Arms (Index)
                            else Parsed.Arms (Index))));
                  end loop;
               end if;
               return
                 "{""node_type"":""SelectStatement"",""arms"":"
                 & Json_List (Arms)
                 & ",""span"":"
                 & JS.Span_Object (Parsed.Span)
                 & "}";
            end;
         when others =>
            return
              "{""node_type"":""NullStatement"",""span"":"
              & JS.Span_Object (Parsed.Span)
              & "}";
      end case;
   end Statement_Node;

   function Formal_Part_Node
     (Params : CM.Parameter_Vectors.Vector;
      Span   : FT.Source_Span) return String
   is
      Items : String_Vectors.Vector;
      Names : String_Vectors.Vector;
   begin
      if not Params.Is_Empty then
         for Param of Params loop
            Names.Clear;
            for Name of Param.Names loop
               Names.Append (JS.Quote (Name));
            end loop;
            Items.Append
              ("{""node_type"":""ParameterSpecification"",""names"":"
               & Json_List (Names)
               & ",""is_aliased"":false,""mode"":"
               & JS.Quote (FT.To_String (Param.Mode))
               & ",""param_type"":"
               & (if Param.Param_Type.Kind = CM.Type_Spec_Access_Def
                  then Access_Definition_Node (Param.Param_Type)
                  else Type_Spec_Name (Param.Param_Type))
               & ",""is_access_definition"":"
               & JS.Bool_Literal (Param.Param_Type.Kind = CM.Type_Spec_Access_Def)
               & ",""default_expression"":null,""span"":"
               & JS.Span_Object (Param.Span)
               & "}");
         end loop;
      end if;
      return
        "{""node_type"":""FormalPart"",""parameters"":"
        & Json_List (Items)
        & ",""span"":"
        & JS.Span_Object (Span)
        & "}";
   end Formal_Part_Node;

   function Signature_For (Subprogram : CM.Resolved_Subprogram) return String is
      Result : US.Unbounded_String := US.Null_Unbounded_String;
   begin
      US.Append (Result, FT.To_String (Subprogram.Kind));
      US.Append (Result, " ");
      US.Append (Result, FT.To_String (Subprogram.Name));
      US.Append (Result, " (");
      if not Subprogram.Params.Is_Empty then
         for Index in Subprogram.Params.First_Index .. Subprogram.Params.Last_Index loop
            declare
               Param : constant CM.Symbol := Subprogram.Params (Index);
            begin
               if Index > Subprogram.Params.First_Index then
                  US.Append (Result, ", ");
               end if;
               US.Append (Result, FT.To_String (Param.Name));
               US.Append (Result, ": ");
               US.Append (Result, FT.To_String (Param.Type_Info.Name));
            end;
         end loop;
      end if;
      US.Append (Result, ")");
      if FT.Lowercase (FT.To_String (Subprogram.Kind)) = "function"
        and then Subprogram.Has_Return_Type
      then
         US.Append (Result, " return ");
         US.Append (Result, FT.To_String (Subprogram.Return_Type.Name));
      end if;
      return US.To_String (Result);
   end Signature_For;

   function Signature_For (Task_Item : CM.Resolved_Task) return String is
   begin
      return "task " & FT.To_String (Task_Item.Name);
   end Signature_For;

   function Subprogram_Node
     (Parsed   : CM.Subprogram_Body;
      Resolved : CM.Resolved_Subprogram) return String
   is
      Decls : String_Vectors.Vector;
   begin
      if not Parsed.Declarations.Is_Empty then
         for Index in Parsed.Declarations.First_Index .. Parsed.Declarations.Last_Index loop
            if not Resolved.Declarations.Is_Empty
              and then Index in Resolved.Declarations.First_Index .. Resolved.Declarations.Last_Index
            then
               Decls.Append
                 (Declaration_Node
                    (Parsed.Declarations (Index),
                     Resolved.Declarations (Index).Initializer));
            else
               Decls.Append (Declaration_Node (Parsed.Declarations (Index)));
            end if;
         end loop;
      end if;

      if FT.Lowercase (FT.To_String (Parsed.Spec.Kind)) = "function" then
         return
           "{""node_type"":""SubprogramBody"",""is_public"":"
           & JS.Bool_Literal (Parsed.Is_Public)
           & ",""spec"":{""node_type"":""FunctionSpecification"",""name"":"
           & JS.Quote (Parsed.Spec.Name)
           & ",""formal_part"":"
           & (if Parsed.Spec.Params.Is_Empty then "null"
              else Formal_Part_Node (Parsed.Spec.Params, Parsed.Spec.Span))
           & ",""return_type"":"
           & (if Parsed.Spec.Return_Type.Kind = CM.Type_Spec_Access_Def
              then Access_Definition_Node (Parsed.Spec.Return_Type)
              else Type_Spec_Name (Parsed.Spec.Return_Type))
           & ",""returns_access_definition"":"
           & JS.Bool_Literal (Parsed.Spec.Return_Is_Access_Def)
           & ",""span"":"
           & JS.Span_Object (Parsed.Spec.Span)
           & "},""declarative_part"":"
           & Json_List (Decls)
           & ",""body"":"
           & Sequence_Node (Parsed.Statements, Resolved.Statements, Parsed.Span)
           & ",""end_designator"":"
           & JS.Quote (Parsed.Spec.Name)
           & ",""span"":"
           & JS.Span_Object (Parsed.Span)
           & "}";
      end if;

      return
        "{""node_type"":""SubprogramBody"",""is_public"":"
        & JS.Bool_Literal (Parsed.Is_Public)
        & ",""spec"":{""node_type"":""ProcedureSpecification"",""name"":"
        & JS.Quote (Parsed.Spec.Name)
        & ",""formal_part"":"
        & (if Parsed.Spec.Params.Is_Empty then "null"
           else Formal_Part_Node (Parsed.Spec.Params, Parsed.Spec.Span))
        & ",""span"":"
        & JS.Span_Object (Parsed.Spec.Span)
        & "},""declarative_part"":"
        & Json_List (Decls)
        & ",""body"":"
        & Sequence_Node (Parsed.Statements, Resolved.Statements, Parsed.Span)
        & ",""end_designator"":"
        & JS.Quote (Parsed.Spec.Name)
        & ",""span"":"
        & JS.Span_Object (Parsed.Span)
        & "}";
   end Subprogram_Node;

   function Task_Node
     (Parsed   : CM.Task_Decl;
      Resolved : CM.Resolved_Task) return String
   is
      Decls : String_Vectors.Vector;
   begin
      if not Parsed.Declarations.Is_Empty then
         for Index in Parsed.Declarations.First_Index .. Parsed.Declarations.Last_Index loop
            if not Resolved.Declarations.Is_Empty
              and then Index in Resolved.Declarations.First_Index .. Resolved.Declarations.Last_Index
            then
               Decls.Append
                 (Declaration_Node
                    (Parsed.Declarations (Index),
                     Resolved.Declarations (Index).Initializer));
            else
               Decls.Append (Declaration_Node (Parsed.Declarations (Index)));
            end if;
         end loop;
      end if;

      return
        "{""node_type"":""TaskDeclaration"",""name"":"
        & JS.Quote (Parsed.Name)
        & ",""priority"":"
        & (if Parsed.Has_Explicit_Priority and then Parsed.Priority /= null
           then Expression_Node (Parsed.Priority)
           else "null")
        & ",""declarative_part"":"
        & Json_List (Decls)
        & ",""body"":"
        & Sequence_Node (Parsed.Statements, Resolved.Statements, Parsed.Span)
        & ",""end_name"":"
        & JS.Quote (Parsed.End_Name)
        & ",""span"":"
        & JS.Span_Object (Parsed.Span)
        & "}";
   end Task_Node;

   function Channel_Node (Parsed : CM.Channel_Decl) return String is
   begin
      return
        "{""node_type"":""ChannelDeclaration"",""is_public"":"
        & JS.Bool_Literal (Parsed.Is_Public)
        & ",""name"":"
        & JS.Quote (Parsed.Name)
        & ",""element_type"":"
        & Type_Spec_Name (Parsed.Element_Type)
        & ",""capacity"":"
        & Expression_Node (Parsed.Capacity)
        & ",""span"":"
        & JS.Span_Object (Parsed.Span)
        & "}";
   end Channel_Node;

   function Package_Item_Node
     (Item             : CM.Package_Item;
      Object_Index     : in out Natural;
      Subprogram_Index : in out Natural;
      Task_Index       : in out Natural;
      Resolved         : CM.Resolved_Unit) return String
   is
   begin
      case Item.Kind is
         when CM.Item_Type_Decl =>
            return
              "{""node_type"":""PackageItem"",""kind"":""BasicDeclaration"",""item"":"
              & Type_Definition_Node (Item.Type_Data)
              & ",""span"":"
              & JS.Span_Object (Item.Type_Data.Span)
              & "}";
         when CM.Item_Subtype_Decl =>
            return
              "{""node_type"":""PackageItem"",""kind"":""BasicDeclaration"",""item"":{""node_type"":""SubtypeDeclaration"",""is_public"":"
              & JS.Bool_Literal (Item.Sub_Data.Is_Public)
              & ",""name"":"
              & JS.Quote (Item.Sub_Data.Name)
              & ",""subtype_indication"":"
              & Subtype_Indication_Node (Item.Sub_Data.Subtype_Mark)
              & ",""span"":"
              & JS.Span_Object (Item.Sub_Data.Span)
              & "},""span"":"
              & JS.Span_Object (Item.Sub_Data.Span)
              & "}";
         when CM.Item_Object_Decl =>
            Object_Index := Object_Index + 1;
            return
              "{""node_type"":""PackageItem"",""kind"":""BasicDeclaration"",""item"":"
              & (if not Resolved.Objects.Is_Empty
                    and then Object_Index in Resolved.Objects.First_Index .. Resolved.Objects.Last_Index
                 then Declaration_Node
                   (Item.Obj_Data, Resolved.Objects (Object_Index).Initializer)
                 else Declaration_Node (Item.Obj_Data))
              & ",""span"":"
              & JS.Span_Object (Item.Obj_Data.Span)
              & "}";
         when CM.Item_Subprogram =>
            Subprogram_Index := Subprogram_Index + 1;
            return
              "{""node_type"":""PackageItem"",""kind"":""BasicDeclaration"",""item"":"
              & (if not Resolved.Subprograms.Is_Empty
                    and then Subprogram_Index in Resolved.Subprograms.First_Index .. Resolved.Subprograms.Last_Index
                 then Subprogram_Node (Item.Subp_Data, Resolved.Subprograms (Subprogram_Index))
                 else Subprogram_Node
                   (Item.Subp_Data,
                    (Name => Item.Subp_Data.Spec.Name,
                     Kind => Item.Subp_Data.Spec.Kind,
                     Params => <>,
                     Has_Return_Type => False,
                     Return_Type => <>,
                     Return_Is_Access_Def => False,
                     Span => Item.Subp_Data.Span,
                     Declarations => <>,
                    Statements => Item.Subp_Data.Statements)))
              & ",""span"":"
              & JS.Span_Object (Item.Subp_Data.Span)
              & "}";
         when CM.Item_Task =>
            Task_Index := Task_Index + 1;
            return
              "{""node_type"":""PackageItem"",""kind"":""TaskDeclaration"",""item"":"
              & (if not Resolved.Tasks.Is_Empty
                    and then Task_Index in Resolved.Tasks.First_Index .. Resolved.Tasks.Last_Index
                 then Task_Node (Item.Task_Data, Resolved.Tasks (Task_Index))
                 else Task_Node
                   (Item.Task_Data,
                    (Name => Item.Task_Data.Name,
                     Has_Explicit_Priority => Item.Task_Data.Has_Explicit_Priority,
                     Priority => 0,
                     Span => Item.Task_Data.Span,
                     Declarations => <>,
                     Statements => Item.Task_Data.Statements)))
              & ",""span"":"
              & JS.Span_Object (Item.Task_Data.Span)
              & "}";
         when CM.Item_Channel =>
            return
              "{""node_type"":""PackageItem"",""kind"":""ChannelDeclaration"",""item"":"
              & Channel_Node (Item.Chan_Data)
              & ",""span"":"
              & JS.Span_Object (Item.Chan_Data.Span)
              & "}";
         when others =>
            return
              "{""node_type"":""PackageItem"",""kind"":""BasicDeclaration"",""item"":"
              & Declaration_Node (Item.Obj_Data)
              & ",""span"":"
              & JS.Span_Object (Item.Obj_Data.Span)
              & "}";
      end case;
   end Package_Item_Node;

   function Public_Declarations
     (Parsed   : CM.Parsed_Unit;
      Resolved : CM.Resolved_Unit) return String
   is
      Items            : String_Vectors.Vector;
      Subprogram_Index : Natural := 0;
   begin
      for Item of Parsed.Items loop
         case Item.Kind is
            when CM.Item_Type_Decl =>
               if Item.Type_Data.Is_Public then
                  Items.Append
                    ("{""name"":"
                     & JS.Quote (Item.Type_Data.Name)
                     & ",""kind"":""TypeDeclaration"",""signature"":"
                     & JS.Quote (Item.Type_Data.Name)
                     & ",""span"":"
                     & JS.Span_Object (Item.Type_Data.Span)
                     & "}");
               end if;
            when CM.Item_Subtype_Decl =>
               if Item.Sub_Data.Is_Public then
                  Items.Append
                    ("{""name"":"
                     & JS.Quote (Item.Sub_Data.Name)
                     & ",""kind"":""SubtypeDeclaration"",""signature"":"
                     & JS.Quote (Item.Sub_Data.Name)
                     & ",""span"":"
                     & JS.Span_Object (Item.Sub_Data.Span)
                     & "}");
               end if;
            when CM.Item_Object_Decl =>
               if Item.Obj_Data.Is_Public then
                  Items.Append
                    ("{""name"":"
                     & JS.Quote (Item.Obj_Data.Names (Item.Obj_Data.Names.First_Index))
                     & ",""kind"":""ObjectDeclaration"",""signature"":"
                     & JS.Quote (Item.Obj_Data.Names (Item.Obj_Data.Names.First_Index))
                     & ",""span"":"
                     & JS.Span_Object (Item.Obj_Data.Span)
                     & "}");
               end if;
            when CM.Item_Subprogram =>
               Subprogram_Index := Subprogram_Index + 1;
               if Item.Subp_Data.Is_Public
                 and then not Resolved.Subprograms.Is_Empty
                 and then Subprogram_Index in Resolved.Subprograms.First_Index .. Resolved.Subprograms.Last_Index
               then
                  declare
                     Subp : constant CM.Resolved_Subprogram := Resolved.Subprograms (Subprogram_Index);
                  begin
                     Items.Append
                       ("{""name"":"
                        & JS.Quote (Subp.Name)
                        & ",""kind"":""SubprogramBody"",""signature"":"
                        & JS.Quote (Signature_For (Subp))
                        & ",""span"":"
                        & JS.Span_Object (Subp.Span)
                        & "}");
                  end;
               end if;
            when others =>
               null;
         end case;
      end loop;
      return Json_List (Items);
   end Public_Declarations;

   function Executables (Resolved : CM.Resolved_Unit) return String is
      Items : String_Vectors.Vector;
   begin
      if not Resolved.Subprograms.Is_Empty then
         for Subp of Resolved.Subprograms loop
            Items.Append
              ("{""name"":"
               & JS.Quote (Subp.Name)
               & ",""kind"":"
               & JS.Quote (Subp.Kind)
               & ",""signature"":"
               & JS.Quote (Signature_For (Subp))
               & ",""span"":"
               & JS.Span_Object (Subp.Span)
               & "}");
         end loop;
      end if;
      if not Resolved.Tasks.Is_Empty then
         for Task_Item of Resolved.Tasks loop
            Items.Append
              ("{""name"":"
               & JS.Quote (Task_Item.Name)
               & ",""kind"":""task"",""signature"":"
               & JS.Quote (Signature_For (Task_Item))
               & ",""span"":"
               & JS.Span_Object (Task_Item.Span)
               & "}");
         end loop;
      end if;
      return Json_List (Items);
   end Executables;

   function Channels_Json (Resolved : CM.Resolved_Unit) return String is
      Items : String_Vectors.Vector;
   begin
      if not Resolved.Channels.Is_Empty then
         for Channel_Item of Resolved.Channels loop
            Items.Append
              ("{""name"":"
               & JS.Quote (Channel_Item.Name)
               & ",""is_public"":"
               & JS.Bool_Literal (Channel_Item.Is_Public)
               & ",""element_type"":"
               & Type_Json (Channel_Item.Element_Type)
               & ",""capacity"":"
               & Long_Long_Integer'Image (Channel_Item.Capacity)
               & (if Channel_Item.Has_Required_Ceiling
                  then ",""required_ceiling"":" & Long_Long_Integer'Image (Channel_Item.Required_Ceiling)
                  else "")
               & ",""span"":"
               & JS.Span_Object (Channel_Item.Span)
               & "}");
         end loop;
      end if;
      return Json_List (Items);
   end Channels_Json;

   function Tasks_Json (Resolved : CM.Resolved_Unit) return String is
      Items : String_Vectors.Vector;
   begin
      if not Resolved.Tasks.Is_Empty then
         for Task_Item of Resolved.Tasks loop
            Items.Append
              ("{""name"":"
               & JS.Quote (Task_Item.Name)
               & ",""priority"":"
               & Long_Long_Integer'Image (Task_Item.Priority)
               & ",""has_explicit_priority"":"
               & JS.Bool_Literal (Task_Item.Has_Explicit_Priority)
               & ",""span"":"
               & JS.Span_Object (Task_Item.Span)
               & "}");
         end loop;
      end if;
      return Json_List (Items);
   end Tasks_Json;

   function Dependencies_Json (Parsed : CM.Parsed_Unit) return String is
      Items : String_Vectors.Vector;
      Seen  : String_Vectors.Vector;

      function Already_Seen (Name : String) return Boolean is
      begin
         if not Seen.Is_Empty then
            for Item of Seen loop
               if FT.Lowercase (Item) = FT.Lowercase (Name) then
                  return True;
               end if;
            end loop;
         end if;
         return False;
      end Already_Seen;
   begin
      if not Parsed.Withs.Is_Empty then
         for Clause of Parsed.Withs loop
            for Name of Clause.Names loop
               declare
                  Value : constant String := FT.To_String (Name);
               begin
                  if not Already_Seen (Value) then
                     Seen.Append (Value);
                     Items.Append (JS.Quote (Name));
                  end if;
               end;
            end loop;
         end loop;
      end if;
      return Json_List (Items);
   end Dependencies_Json;

   function Public_Types_Json
     (Parsed        : CM.Parsed_Unit;
      Resolved      : CM.Resolved_Unit;
      Subtype_Only  : Boolean) return String
   is
      Items      : String_Vectors.Vector;
      Type_Index : Natural := 0;
   begin
      for Item of Parsed.Items loop
         if Item.Kind in CM.Item_Type_Decl | CM.Item_Subtype_Decl then
            Type_Index := Type_Index + 1;
            if not Resolved.Types.Is_Empty
              and then Type_Index in Resolved.Types.First_Index .. Resolved.Types.Last_Index
            then
               if Item.Kind = CM.Item_Type_Decl
                 and then not Subtype_Only
                 and then Item.Type_Data.Is_Public
               then
                  Items.Append (Type_Json (Resolved.Types (Type_Index)));
               elsif Item.Kind = CM.Item_Subtype_Decl
                 and then Subtype_Only
                 and then Item.Sub_Data.Is_Public
               then
                  Items.Append (Type_Json (Resolved.Types (Type_Index)));
               end if;
            end if;
         end if;
      end loop;
      return Json_List (Items);
   end Public_Types_Json;

   function Channel_Required_Ceiling
     (Bronze : MB.Bronze_Result;
      Name   : FT.UString) return Long_Long_Integer is
   begin
      if not Bronze.Ceilings.Is_Empty then
         for Item of Bronze.Ceilings loop
            if FT.To_String (Item.Channel_Name) = FT.To_String (Name) then
               return Item.Priority;
            end if;
         end loop;
      end if;
      return 0;
   end Channel_Required_Ceiling;

   function Public_Channels_Json
     (Resolved : CM.Resolved_Unit;
      Bronze   : MB.Bronze_Result) return String is
      Items : String_Vectors.Vector;
   begin
      if not Resolved.Channels.Is_Empty then
         for Channel_Item of Resolved.Channels loop
            if Channel_Item.Is_Public then
               declare
                  Ceiling : constant Long_Long_Integer :=
                    Channel_Required_Ceiling (Bronze, Channel_Item.Name);
               begin
               Items.Append
                 ("{""name"":"
                  & JS.Quote (Channel_Item.Name)
                  & ",""is_public"":"
                  & JS.Bool_Literal (Channel_Item.Is_Public)
                  & ",""element_type"":"
                  & Type_Json (Channel_Item.Element_Type)
                  & ",""capacity"":"
                  & Long_Long_Integer'Image (Channel_Item.Capacity)
                  & (if Ceiling > 0
                     then ",""required_ceiling"":" & Long_Long_Integer'Image (Ceiling)
                     else "")
                  & ",""span"":"
                  & JS.Span_Object (Channel_Item.Span)
                  & "}");
               end;
            end if;
         end loop;
      end if;
      return Json_List (Items);
   end Public_Channels_Json;

   function Public_Objects_Json
     (Parsed   : CM.Parsed_Unit;
      Resolved : CM.Resolved_Unit) return String
   is
      Items        : String_Vectors.Vector;
      Object_Index : Natural := 0;
   begin
      for Item of Parsed.Items loop
         if Item.Kind = CM.Item_Object_Decl then
            Object_Index := Object_Index + 1;
            if Item.Obj_Data.Is_Public
              and then not Resolved.Objects.Is_Empty
              and then Object_Index in Resolved.Objects.First_Index .. Resolved.Objects.Last_Index
            then
               for Name of Item.Obj_Data.Names loop
                  declare
                     Fields : String_Vectors.Vector;
                     Info   : constant CM.Resolved_Object_Decl := Resolved.Objects (Object_Index);
                  begin
                     Fields.Append ("""name"":" & JS.Quote (Name));
                     Fields.Append ("""type"":" & Type_Json (Info.Type_Info));
                     Fields.Append ("""is_constant"":" & JS.Bool_Literal (Info.Is_Constant));
                     case Info.Static_Info.Kind is
                        when CM.Static_Value_Integer =>
                           Fields.Append ("""static_value_kind"":""integer""");
                           Fields.Append
                             ("""static_value"":"
                              & Trimmed (Info.Static_Info.Int_Value));
                        when CM.Static_Value_Boolean =>
                           Fields.Append ("""static_value_kind"":""boolean""");
                           Fields.Append
                             ("""static_value"":"
                              & JS.Bool_Literal (Info.Static_Info.Bool_Value));
                        when others =>
                           null;
                     end case;
                     Fields.Append ("""span"":" & JS.Span_Object (Item.Obj_Data.Span));
                     Items.Append ("{" & Join_Object_Fields (Fields) & "}");
                  end;
               end loop;
            end if;
         end if;
      end loop;
      return Json_List (Items);
   end Public_Objects_Json;

   function Param_Json (Param : CM.Symbol) return String is
   begin
      return
        "{""name"":"
        & JS.Quote (Param.Name)
        & ",""mode"":"
        & JS.Quote (Param.Mode)
        & ",""type"":"
        & Type_Json (Param.Type_Info)
        & ",""span"":"
        & JS.Span_Object (Param.Span)
        & "}";
   end Param_Json;

   function Public_Subprograms_Json
     (Parsed   : CM.Parsed_Unit;
      Resolved : CM.Resolved_Unit) return String
   is
      Items            : String_Vectors.Vector;
      Subprogram_Index : Natural := 0;
      Params           : String_Vectors.Vector;
   begin
      for Item of Parsed.Items loop
         if Item.Kind = CM.Item_Subprogram then
            Subprogram_Index := Subprogram_Index + 1;
            if Item.Subp_Data.Is_Public
              and then not Resolved.Subprograms.Is_Empty
              and then Subprogram_Index in Resolved.Subprograms.First_Index .. Resolved.Subprograms.Last_Index
            then
               declare
                  Subp : constant CM.Resolved_Subprogram := Resolved.Subprograms (Subprogram_Index);
               begin
                  Params.Clear;
                  for Param of Subp.Params loop
                     Params.Append (Param_Json (Param));
                  end loop;
                  Items.Append
                    ("{""name"":"
                     & JS.Quote (Subp.Name)
                     & ",""kind"":"
                     & JS.Quote (Subp.Kind)
                     & ",""signature"":"
                     & JS.Quote (Signature_For (Subp))
                     & ",""params"":"
                     & Json_List (Params)
                     & ",""has_return_type"":"
                     & JS.Bool_Literal (Subp.Has_Return_Type)
                     & ",""return_type"":"
                     & (if Subp.Has_Return_Type then Type_Json (Subp.Return_Type) else "null")
                     & ",""return_is_access_def"":"
                     & JS.Bool_Literal (Subp.Return_Is_Access_Def)
                     & ",""span"":"
                     & JS.Span_Object (Subp.Span)
                     & "}");
               end;
            end if;
         end if;
      end loop;
      return Json_List (Items);
   end Public_Subprograms_Json;

   function Graph_Summary_For
     (Bronze : MB.Bronze_Result;
      Name   : FT.UString) return MB.Graph_Summary is
   begin
      if not Bronze.Graphs.Is_Empty then
         for Item of Bronze.Graphs loop
            if FT.To_String (Item.Name) = FT.To_String (Name) then
               return Item;
            end if;
         end loop;
      end if;
      return (others => <>);
   end Graph_Summary_For;

   function Depends_Json (Items : MB.Depends_Vectors.Vector) return String is
      Result : String_Vectors.Vector;
      Inputs : String_Vectors.Vector;
   begin
      if not Items.Is_Empty then
         for Item of Items loop
            Inputs.Clear;
            if not Item.Inputs.Is_Empty then
               for Input of Item.Inputs loop
                  Inputs.Append (JS.Quote (Input));
               end loop;
            end if;
            Result.Append
              ("{""output_name"":"
               & JS.Quote (Item.Output_Name)
               & ",""inputs"":"
               & Json_List (Inputs)
               & "}");
         end loop;
      end if;
      return Json_List (Result);
   end Depends_Json;

   function Effect_Summaries_Json
     (Parsed   : CM.Parsed_Unit;
      Resolved : CM.Resolved_Unit;
      Bronze   : MB.Bronze_Result) return String
   is
      Items            : String_Vectors.Vector;
      Reads            : String_Vectors.Vector;
      Writes           : String_Vectors.Vector;
      Inputs           : String_Vectors.Vector;
      Outputs          : String_Vectors.Vector;
      Subprogram_Index : Natural := 0;
   begin
      for Item of Parsed.Items loop
         if Item.Kind = CM.Item_Subprogram then
            Subprogram_Index := Subprogram_Index + 1;
            if Item.Subp_Data.Is_Public
              and then not Resolved.Subprograms.Is_Empty
              and then Subprogram_Index in Resolved.Subprograms.First_Index .. Resolved.Subprograms.Last_Index
            then
               declare
                  Subp    : constant CM.Resolved_Subprogram := Resolved.Subprograms (Subprogram_Index);
                  Summary : constant MB.Graph_Summary := Graph_Summary_For (Bronze, Subp.Name);
               begin
                  Reads.Clear;
                  Writes.Clear;
                  Inputs.Clear;
                  Outputs.Clear;
                  for Name of Summary.Reads loop
                     Reads.Append (JS.Quote (Name));
                  end loop;
                  for Name of Summary.Writes loop
                     Writes.Append (JS.Quote (Name));
                  end loop;
                  for Name of Summary.Inputs loop
                     Inputs.Append (JS.Quote (Name));
                  end loop;
                  for Name of Summary.Outputs loop
                     Outputs.Append (JS.Quote (Name));
                  end loop;
                  Items.Append
                    ("{""name"":"
                     & JS.Quote (Subp.Name)
                     & ",""signature"":"
                     & JS.Quote (Signature_For (Subp))
                     & ",""reads"":"
                     & Json_List (Reads)
                     & ",""writes"":"
                     & Json_List (Writes)
                     & ",""inputs"":"
                     & Json_List (Inputs)
                     & ",""outputs"":"
                     & Json_List (Outputs)
                     & ",""depends"":"
                     & Depends_Json (Summary.Depends)
                     & "}");
               end;
            end if;
         end if;
      end loop;
      return Json_List (Items);
   end Effect_Summaries_Json;

   function Channel_Access_Summaries_Json
     (Parsed   : CM.Parsed_Unit;
      Resolved : CM.Resolved_Unit;
      Bronze   : MB.Bronze_Result) return String
   is
      Items            : String_Vectors.Vector;
      Channels         : String_Vectors.Vector;
      Subprogram_Index : Natural := 0;
   begin
      for Item of Parsed.Items loop
         if Item.Kind = CM.Item_Subprogram then
            Subprogram_Index := Subprogram_Index + 1;
            if Item.Subp_Data.Is_Public
              and then not Resolved.Subprograms.Is_Empty
              and then Subprogram_Index in Resolved.Subprograms.First_Index .. Resolved.Subprograms.Last_Index
            then
               declare
                  Subp    : constant CM.Resolved_Subprogram := Resolved.Subprograms (Subprogram_Index);
                  Summary : constant MB.Graph_Summary := Graph_Summary_For (Bronze, Subp.Name);
               begin
                  Channels.Clear;
                  for Name of Summary.Channels loop
                     Channels.Append (JS.Quote (Name));
                  end loop;
                  Items.Append
                    ("{""name"":"
                     & JS.Quote (Subp.Name)
                     & ",""signature"":"
                     & JS.Quote (Signature_For (Subp))
                     & ",""channels"":"
                     & Json_List (Channels)
                     & "}");
               end;
            end if;
         end if;
      end loop;
      return Json_List (Items);
   end Channel_Access_Summaries_Json;

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
            Indexes : String_Vectors.Vector;
         begin
            for Item of Info.Index_Types loop
               Indexes.Append (JS.Quote (Item));
            end loop;
            Items.Append ("""index_types"":" & Json_List (Indexes));
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
      return
        "{"
        & Join_Object_Fields (Items)
        & "}";
   end Type_Json;

   function Types_Json (Resolved : CM.Resolved_Unit) return String is
      Items : String_Vectors.Vector;
   begin
      if not Resolved.Types.Is_Empty then
         for Item of Resolved.Types loop
            Items.Append (Type_Json (Item));
         end loop;
      end if;
      if not Resolved.Imported_Types.Is_Empty then
         for Item of Resolved.Imported_Types loop
            Items.Append (Type_Json (Item));
         end loop;
      end if;
      return Json_List (Items);
   end Types_Json;

   function Ast_Json
     (Parsed   : CM.Parsed_Unit;
      Resolved : CM.Resolved_Unit) return String
   is
      Withs            : String_Vectors.Vector;
      Items            : String_Vectors.Vector;
      Object_Index     : Natural := 0;
      Subprogram_Index : Natural := 0;
      Task_Index       : Natural := 0;
   begin
      if not Parsed.Withs.Is_Empty then
         for Clause of Parsed.Withs loop
            declare
               Names : String_Vectors.Vector;
            begin
               for Name of Clause.Names loop
                  Names.Append
                    (Package_Name_Node (FT.To_String (Name), Clause.Span));
               end loop;
               Withs.Append
                 ("{""node_type"":""WithClause"",""package_names"":"
                  & Json_List (Names)
                  & ",""span"":"
                  & JS.Span_Object (Clause.Span)
                  & "}");
            end;
         end loop;
      end if;

      if not Parsed.Items.Is_Empty then
         for Item of Parsed.Items loop
            Items.Append
              (Package_Item_Node
                 (Item,
                  Object_Index,
                  Subprogram_Index,
                  Task_Index,
                  Resolved));
         end loop;
      end if;

      return
        "{"
        & """context_clause"":{""node_type"":""ContextClause"",""with_clauses"":"
        & Json_List (Withs)
        & "},"
        & """node_type"":""CompilationUnit"","
        & """package_unit"":{""node_type"":""PackageUnit"",""name"":"
        & JS.Quote (Parsed.Package_Name)
        & ",""items"":"
        & Json_List (Items)
        & ",""end_name"":"
        & JS.Quote (Parsed.End_Name)
        & ",""span"":"
        & JS.Span_Object (Parsed.Span)
        & "},"
        & """span"":"
        & JS.Span_Object (Parsed.Span)
        & "}"
        & Ada.Characters.Latin_1.LF;
   end Ast_Json;

   function Typed_Json
     (Parsed   : CM.Parsed_Unit;
      Resolved : CM.Resolved_Unit) return String
   is
      Ast_Text : constant String := Ast_Json (Parsed, Resolved);
   begin
      return
        "{"
        & """format"":""typed-v2"","
        & """package_name"":"
        & JS.Quote (Parsed.Package_Name)
        & ","
        & """package_end_name"":"
        & JS.Quote (Parsed.End_Name)
        & ","
        & """types"":"
        & Types_Json (Resolved)
        & ","
        & """channels"":"
        & Channels_Json (Resolved)
        & ","
        & """tasks"":"
        & Tasks_Json (Resolved)
        & ","
        & """executables"":"
        & Executables (Resolved)
        & ","
        & """public_declarations"":"
        & Public_Declarations (Parsed, Resolved)
        & ","
        & """ast"":"
        & Ast_Text (Ast_Text'First .. Ast_Text'Last - 1)
        & "}"
        & Ada.Characters.Latin_1.LF;
   end Typed_Json;

   function Interface_Json
     (Parsed   : CM.Parsed_Unit;
      Resolved : CM.Resolved_Unit;
      Bronze   : MB.Bronze_Result) return String is
   begin
      return
        "{"
        & """format"":""safei-v1"","
        & """package_name"":"
        & JS.Quote (Parsed.Package_Name)
        & ","
        & """dependencies"":"
        & Dependencies_Json (Parsed)
        & ","
        & """executables"":"
        & Executables (Resolved)
        & ","
        & """public_declarations"":"
        & Public_Declarations (Parsed, Resolved)
        & ","
        & """types"":"
        & Public_Types_Json (Parsed, Resolved, False)
        & ","
        & """subtypes"":"
        & Public_Types_Json (Parsed, Resolved, True)
        & ","
        & """channels"":"
        & Public_Channels_Json (Resolved, Bronze)
        & ","
        & """objects"":"
        & Public_Objects_Json (Parsed, Resolved)
        & ","
        & """subprograms"":"
        & Public_Subprograms_Json (Parsed, Resolved)
        & ","
        & """effect_summaries"":"
        & Effect_Summaries_Json (Parsed, Resolved, Bronze)
        & ","
        & """channel_access_summaries"":"
        & Channel_Access_Summaries_Json (Parsed, Resolved, Bronze)
        & "}"
        & Ada.Characters.Latin_1.LF;
   end Interface_Json;
end Safe_Frontend.Check_Emit;
