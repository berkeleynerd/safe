with Ada.Characters.Latin_1;
with Ada.Strings.Unbounded;
with Safe_Frontend.Json;

package body Safe_Frontend.Ast is
   package US renames Ada.Strings.Unbounded;

   function Package_Item_Category (Kind : Package_Item_Kind) return String is
   begin
      case Kind is
         when Type_Declaration
            | Subtype_Declaration
            | Object_Declaration
            | Number_Declaration
            | Subprogram_Declaration =>
            return "BasicDeclaration";
         when Task_Declaration =>
            return "TaskDeclaration";
         when Channel_Declaration =>
            return "ChannelDeclaration";
         when Use_Type_Clause =>
            return "UseTypeClause";
         when Pragma_Item =>
            return "Pragma";
         when Representation_Item | Unknown_Item =>
            return "RepresentationItem";
      end case;
   end Package_Item_Category;

   function Kind_Name (Kind : Package_Item_Kind) return String is
   begin
      case Kind is
         when Type_Declaration =>
            return "TypeDeclaration";
         when Subtype_Declaration =>
            return "SubtypeDeclaration";
         when Object_Declaration =>
            return "ObjectDeclaration";
         when Number_Declaration =>
            return "NumberDeclaration";
         when Subprogram_Declaration =>
            return "SubprogramDeclaration";
         when Task_Declaration =>
            return "TaskDeclaration";
         when Channel_Declaration =>
            return "ChannelDeclaration";
         when Use_Type_Clause =>
            return "UseTypeClause";
         when Pragma_Item =>
            return "Pragma";
         when Representation_Item =>
            return "RepresentationItem";
         when Unknown_Item =>
            return "UnknownItem";
      end case;
   end Kind_Name;

   function Package_Name_Object (Name : FT.UString; Span : FT.Source_Span) return String is
      Raw_Name : constant String := FT.To_String (Name);
      Result   : US.Unbounded_String := US.Null_Unbounded_String;
      Start    : Positive := Raw_Name'First;
   begin
      US.Append (Result, "{""node_type"":""PackageName"",""identifiers"":[");
      for Index in Raw_Name'Range loop
         if Raw_Name (Index) = '.' then
            if Index > Start then
               if Start > Raw_Name'First then
                  US.Append (Result, ",");
               end if;
               US.Append (Result, Safe_Frontend.Json.Quote (Raw_Name (Start .. Index - 1)));
            end if;
            Start := Index + 1;
         end if;
      end loop;
      if Start <= Raw_Name'Last then
         if Start > Raw_Name'First then
            US.Append (Result, ",");
         end if;
         US.Append (Result, Safe_Frontend.Json.Quote (Raw_Name (Start .. Raw_Name'Last)));
      end if;
      US.Append
        (Result,
         "],""span"":" & Safe_Frontend.Json.Span_Object (Span) & "}");
      return US.To_String (Result);
   end Package_Name_Object;

   function Join_Names
     (Names : FT.UString_Vectors.Vector;
      Span  : FT.Source_Span) return String
   is
      Result : US.Unbounded_String := US.Null_Unbounded_String;
   begin
      for Index in Names.First_Index .. Names.Last_Index loop
         if Index > Names.First_Index then
            US.Append (Result, ",");
         end if;
         US.Append
           (Result,
           Package_Name_Object
              (Name => Names.Element (Index),
               Span => Span));
      end loop;
      return US.To_String (Result);
   exception
      when Constraint_Error =>
         return "";
   end Join_Names;

   function Item_Object (Item : Package_Item) return String is
      Node_Name : constant String :=
        (if Item.Kind = Subprogram_Declaration and then Item.Has_Body
         then "SubprogramBody"
         elsif Item.Kind = Unknown_Item
         then "RepresentationItem"
         else Kind_Name (Item.Kind));
   begin
      if Node_Name = "TypeDeclaration" then
         return
           "{"
           & """node_type"":""TypeDeclaration"","
           & """is_public"":"
           & Safe_Frontend.Json.Bool_Literal (Item.Is_Public)
           & ","
           & """name"":" & Safe_Frontend.Json.Quote (Item.Name) & ","
           & """discriminant_part"":null,"
           & """type_definition"":{""text"":" & Safe_Frontend.Json.Quote (Item.Header_Text) & "},"
           & """span"":" & Safe_Frontend.Json.Span_Object (Item.Span)
           & "}";
      elsif Node_Name = "SubtypeDeclaration" then
         return
           "{"
           & """node_type"":""SubtypeDeclaration"","
           & """is_public"":"
           & Safe_Frontend.Json.Bool_Literal (Item.Is_Public)
           & ","
           & """name"":" & Safe_Frontend.Json.Quote (Item.Name) & ","
           & """subtype_indication"":{""text"":" & Safe_Frontend.Json.Quote (Item.Header_Text) & "},"
           & """span"":" & Safe_Frontend.Json.Span_Object (Item.Span)
           & "}";
      elsif Node_Name = "ObjectDeclaration" or else Node_Name = "NumberDeclaration" then
         return
           "{"
           & """node_type"":""ObjectDeclaration"","
           & """is_public"":"
           & Safe_Frontend.Json.Bool_Literal (Item.Is_Public)
           & ","
           & """names"":[" & Safe_Frontend.Json.Quote (Item.Name) & "],"
            & """is_aliased"":false,"
            & """is_constant"":false,"
            & """object_type"":{""text"":" & Safe_Frontend.Json.Quote (Item.Header_Text) & "},"
           & """initializer"":null,"
           & """span"":" & Safe_Frontend.Json.Span_Object (Item.Span)
           & "}";
      elsif Node_Name = "ChannelDeclaration" then
         return
           "{"
           & """node_type"":""ChannelDeclaration"","
           & """is_public"":"
           & Safe_Frontend.Json.Bool_Literal (Item.Is_Public)
           & ","
           & """name"":" & Safe_Frontend.Json.Quote (Item.Name) & ","
           & """element_type"":{""text"":" & Safe_Frontend.Json.Quote (Item.Element_Type) & "},"
           & """capacity"":{""text"":" & Safe_Frontend.Json.Quote (Item.Capacity_Text) & "},"
           & """span"":" & Safe_Frontend.Json.Span_Object (Item.Span)
           & "}";
      elsif Node_Name = "TaskDeclaration" then
         return
           "{"
           & """node_type"":""TaskDeclaration"","
           & """name"":" & Safe_Frontend.Json.Quote (Item.Name) & ","
           & """priority"":null,"
           & """declarative_part"":[],"
           & """body"":{""statement_count"":0},"
           & """end_name"":" & Safe_Frontend.Json.Quote (Item.Name) & ","
           & """span"":" & Safe_Frontend.Json.Span_Object (Item.Span)
           & "}";
      elsif Node_Name = "SubprogramBody" then
         return
           "{"
           & """node_type"":""SubprogramBody"","
           & """is_public"":"
           & Safe_Frontend.Json.Bool_Literal (Item.Is_Public)
           & ","
           & """spec"":{""name"":" & Safe_Frontend.Json.Quote (Item.Name)
           & ",""signature"":" & Safe_Frontend.Json.Quote (Item.Signature)
           & ",""return_type"":" & Safe_Frontend.Json.Quote (Item.Return_Type) & "},"
           & """declarative_part"":[],"
           & """body"":{""statement_count"":0},"
           & """end_designator"":" & Safe_Frontend.Json.Quote (Item.Name) & ","
           & """span"":" & Safe_Frontend.Json.Span_Object (Item.Span)
           & "}";
      elsif Node_Name = "SubprogramDeclaration" then
         return
           "{"
           & """node_type"":""SubprogramDeclaration"","
           & """is_public"":"
           & Safe_Frontend.Json.Bool_Literal (Item.Is_Public)
           & ","
           & """spec"":{""name"":" & Safe_Frontend.Json.Quote (Item.Name)
           & ",""signature"":" & Safe_Frontend.Json.Quote (Item.Signature)
           & ",""return_type"":" & Safe_Frontend.Json.Quote (Item.Return_Type) & "},"
           & """span"":" & Safe_Frontend.Json.Span_Object (Item.Span)
           & "}";
      elsif Node_Name = "UseTypeClause" then
         return
           "{"
           & """node_type"":""UseTypeClause"","
           & """subtype_marks"":[" & Safe_Frontend.Json.Quote (Item.Name) & "],"
           & """span"":" & Safe_Frontend.Json.Span_Object (Item.Span)
           & "}";
      elsif Node_Name = "Pragma" then
         return
           "{"
           & """node_type"":""Pragma"","
           & """name"":" & Safe_Frontend.Json.Quote (Item.Name) & ","
           & """arguments"":[],"
           & """span"":" & Safe_Frontend.Json.Span_Object (Item.Span)
           & "}";
      else
         return
           "{"
           & """node_type"":""RepresentationItem"","
           & """kind"":""AspectSpecification"","
           & """item"":{""text"":" & Safe_Frontend.Json.Quote (Item.Header_Text) & "},"
           & """span"":" & Safe_Frontend.Json.Span_Object (Item.Span)
           & "}";
      end if;
   end Item_Object;

   function To_Json (Unit : Compilation_Unit) return String is
      Result : US.Unbounded_String := US.Null_Unbounded_String;
   begin
      US.Append (Result, "{");
      US.Append (Result, """node_type"":""CompilationUnit"",");
      US.Append (Result, """context_clause"":{""node_type"":""ContextClause"",""with_clauses"":[");
      if not Unit.With_Clauses.Is_Empty then
         for Index in Unit.With_Clauses.First_Index .. Unit.With_Clauses.Last_Index loop
            declare
               Clause : constant With_Clause := Unit.With_Clauses.Element (Index);
            begin
               if Index > Unit.With_Clauses.First_Index then
                  US.Append (Result, ",");
               end if;
               US.Append
                 (Result,
                 "{""node_type"":""WithClause"",""package_names"":["
                  & Join_Names (Clause.Package_Names, Clause.Span)
                  & "],""span"":"
                  & Safe_Frontend.Json.Span_Object (Clause.Span)
                  & "}");
            end;
         end loop;
      end if;
      US.Append (Result, "]},");
      US.Append
        (Result,
         """package_unit"":{""node_type"":""PackageUnit"",""name"":"
         & Safe_Frontend.Json.Quote (Unit.Package_Name)
         & ",""items"":[");
      if not Unit.Items.Is_Empty then
         for Index in Unit.Items.First_Index .. Unit.Items.Last_Index loop
            declare
               Item : constant Package_Item := Unit.Items.Element (Index);
            begin
               if Index > Unit.Items.First_Index then
                  US.Append (Result, ",");
               end if;
               US.Append
                 (Result,
                 "{""node_type"":""PackageItem"",""kind"":"""
                  & Package_Item_Category (Item.Kind)
                  & """,""item"":"
                  & Item_Object (Item)
                  & ",""span"":"
                  & Safe_Frontend.Json.Span_Object (Item.Span)
                  & "}");
            end;
         end loop;
      end if;
      US.Append
        (Result,
         "],""end_name"":"
         & Safe_Frontend.Json.Quote (Unit.End_Name)
         & ",""span"":"
         & Safe_Frontend.Json.Span_Object (Unit.Span)
         & "},");
      US.Append
        (Result,
         """span"":"
         & Safe_Frontend.Json.Span_Object (Unit.Span)
         & "}");
      return US.To_String (Result) & Ada.Characters.Latin_1.LF;
   end To_Json;
end Safe_Frontend.Ast;
