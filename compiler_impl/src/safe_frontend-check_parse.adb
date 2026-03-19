with Safe_Frontend.Types;

package body Safe_Frontend.Check_Parse is
   package FL renames Safe_Frontend.Lexer;
   package FS renames Safe_Frontend.Source;
   package FT renames Safe_Frontend.Types;

   use type CM.Expr_Access;
   use type CM.Expr_Kind;
   use type CM.Statement_Access;
   use type CM.Statement_Kind;
   use type CM.Type_Spec_Kind;
   use type FL.Token_Kind;
   use type FT.UString;

   Parse_Failure   : exception;
   Raised_Diag     : CM.MD.Diagnostic;

   type Parser_State is record
      Input  : FS.Source_File;
      Tokens : FL.Token_Vectors.Vector;
      Index  : Natural := 1;
   end record;

   function Eof_Token (State : Parser_State) return FL.Token is
      Span : FT.Source_Span := FT.Null_Span;
   begin
      if not State.Tokens.Is_Empty then
         Span := State.Tokens (State.Tokens.Last_Index).Span;
      end if;
      return
        (Kind   => FL.End_Of_File,
         Lexeme => FT.To_UString ("<eof>"),
         Span   => Span);
   end Eof_Token;

   function Current (State : Parser_State) return FL.Token is
   begin
      if State.Tokens.Is_Empty or else State.Index > Natural (State.Tokens.Last_Index) then
         return Eof_Token (State);
      end if;
      return State.Tokens (Positive (State.Index));
   end Current;

   function Next
     (State  : Parser_State;
      Offset : Natural := 1) return FL.Token
   is
      Candidate : constant Natural := State.Index + Offset;
   begin
      if State.Tokens.Is_Empty or else Candidate > Natural (State.Tokens.Last_Index) then
         return Eof_Token (State);
      end if;
      return State.Tokens (Positive (Candidate));
   end Next;

   function Current_Lower (State : Parser_State) return String is
   begin
      return FT.Lowercase (FT.To_String (Current (State).Lexeme));
   end Current_Lower;

   procedure Advance (State : in out Parser_State) is
   begin
      if not State.Tokens.Is_Empty and then State.Index <= Natural (State.Tokens.Last_Index) then
         State.Index := State.Index + 1;
      end if;
   end Advance;

   procedure Raise_Diag (Item : CM.MD.Diagnostic) is
   begin
      Raised_Diag := Item;
      raise Parse_Failure;
   end Raise_Diag;

   function Path_String (State : Parser_State) return String is
   begin
      return FT.To_String (State.Input.Path);
   end Path_String;

   function New_Expr return CM.Expr_Access is
   begin
      return new CM.Expr_Node;
   end New_Expr;

   function Match
     (State  : in out Parser_State;
      Lexeme : String) return Boolean is
   begin
      if Current_Lower (State) = FT.Lowercase (Lexeme) then
         Advance (State);
         return True;
      end if;
      return False;
   end Match;

   function Expect
     (State   : in out Parser_State;
      Lexeme  : String) return FL.Token
   is
      Token : constant FL.Token := Current (State);
   begin
      if Match (State, Lexeme) then
         return Token;
      end if;

      Raise_Diag
        (CM.Source_Frontend_Error
           (Path    => Path_String (State),
            Span    => Token.Span,
            Message => "expected `" & Lexeme & "`",
            Note    => "saw `" & FT.To_String (Token.Lexeme) & "`"));
      return Token;
   end Expect;

   procedure Require
     (State  : in out Parser_State;
      Lexeme : String) is
      Ignore : FL.Token;
   begin
      Ignore := Expect (State, Lexeme);
   end Require;

   procedure Reject_Legacy_Keyword
     (State       : Parser_State;
      Legacy      : String;
      Replacement : String;
      Context     : String) is
   begin
      Raise_Diag
        (CM.Source_Frontend_Error
           (Path    => Path_String (State),
            Span    => Current (State).Span,
            Message =>
              "legacy `" & Legacy & "` is not allowed in " & Context
              & "; use `" & Replacement & "`"));
   end Reject_Legacy_Keyword;

   procedure Require_Returns_Keyword (State : in out Parser_State) is
   begin
      if Match (State, "returns") then
         return;
      elsif Current_Lower (State) = "return" then
         Reject_Legacy_Keyword
           (State,
            Legacy      => "return",
            Replacement => "returns",
            Context     => "subprogram signatures");
      else
         Require (State, "returns");
      end if;
   end Require_Returns_Keyword;

   procedure Require_Range_Keyword (State : in out Parser_State) is
   begin
      if Match (State, "to") then
         return;
      elsif FT.To_String (Current (State).Lexeme) = ".." then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path_String (State),
               Span    => Current (State).Span,
               Message => "legacy `..` is not allowed in source ranges; use `to`"));
      else
         Require (State, "to");
      end if;
   end Require_Range_Keyword;

   function Expect_Identifier
     (State : in out Parser_State) return FL.Token
   is
      Token : constant FL.Token := Current (State);
      use type FL.Token_Kind;
   begin
      if Token.Kind = FL.Identifier or else Token.Kind = FL.Keyword then
         Advance (State);
         return Token;
      end if;

      Raise_Diag
        (CM.Source_Frontend_Error
           (Path    => Path_String (State),
            Span    => Token.Span,
            Message => "expected identifier",
            Note    => "saw `" & FT.To_String (Token.Lexeme) & "`"));
      return Token;
   end Expect_Identifier;

   procedure Reject_Unsupported
     (State   : Parser_State;
      Message : String;
      Note    : String := "") is
   begin
      Raise_Diag
        (CM.Unsupported_Source_Construct
           (Path    => Path_String (State),
            Span    => Current (State).Span,
            Message => Message,
            Note    => Note));
   end Reject_Unsupported;

   function Parse_Package_Name
     (State : in out Parser_State) return CM.Expr_Access;
   function Parse_Name_Expression
     (State : in out Parser_State) return CM.Expr_Access;
   function Parse_Expression
     (State : in out Parser_State) return CM.Expr_Access;
   function Parse_Case_Statement
     (State : in out Parser_State) return CM.Statement_Access;
   function Case_Choice_Is_Literal
     (Expr : CM.Expr_Access) return Boolean;

   function Parse_Package_Name
     (State : in out Parser_State) return CM.Expr_Access
   is
      First : constant FL.Token := Expect_Identifier (State);
      Expr  : CM.Expr_Access := New_Expr;
   begin
      Expr.Kind := CM.Expr_Ident;
      Expr.Name := First.Lexeme;
      Expr.Span := First.Span;

      while Match (State, ".") loop
         declare
            Selector : constant FL.Token := Expect_Identifier (State);
            Next_Expr : constant CM.Expr_Access := New_Expr;
         begin
            Next_Expr.Kind := CM.Expr_Select;
            Next_Expr.Prefix := Expr;
            Next_Expr.Selector := Selector.Lexeme;
            Next_Expr.Span := CM.Join (Expr.Span, Selector.Span);
            Expr := Next_Expr;
         end;
      end loop;

      return Expr;
   end Parse_Package_Name;

   function Name_To_String (Expr : CM.Expr_Access) return String is
   begin
      if Expr = null then
         return "";
      elsif Expr.Kind = CM.Expr_Ident then
         return FT.To_String (Expr.Name);
      elsif Expr.Kind = CM.Expr_Select then
         return Name_To_String (Expr.Prefix) & "." & FT.To_String (Expr.Selector);
      end if;
      return "";
   end Name_To_String;

   function Parse_Access_Definition
     (State                : in out Parser_State;
      Type_Decl_Context    : Boolean) return CM.Type_Spec
   is
      Start      : constant FT.Source_Span := Current (State).Span;
      Result     : CM.Type_Spec;
      Target_Expr : CM.Expr_Access;
   begin
      if Match (State, "not") then
         Require (State, "null");
         Result.Not_Null := True;
      end if;
      Require (State, "access");
      if Match (State, "all") then
         Result.Is_All := True;
      elsif Match (State, "constant") then
         Result.Is_Constant := True;
      end if;
      Target_Expr := Parse_Name_Expression (State);
      Result.Kind := CM.Type_Spec_Access_Def;
      Result.Target_Name := Target_Expr;
      Result.Anonymous := not Type_Decl_Context;
      Result.Span := CM.Join (Start, Target_Expr.Span);
      return Result;
   end Parse_Access_Definition;

   function Parse_Type_Spec_Internal
     (State            : in out Parser_State;
      Allow_Access_Def : Boolean) return CM.Type_Spec;

   function Parse_Tuple_Type_Spec
     (State            : in out Parser_State;
      Allow_Access_Def : Boolean) return CM.Type_Spec
   is
      Start  : constant FL.Token := Expect (State, "(");
      Result : CM.Type_Spec;
      Ender  : FL.Token;
   begin
      Result.Kind := CM.Type_Spec_Tuple;
      loop
         declare
            Element : constant CM.Type_Spec :=
              Parse_Type_Spec_Internal (State, Allow_Access_Def);
         begin
            Result.Tuple_Elements.Append (new CM.Type_Spec'(Element));
         end;
         exit when not Match (State, ",");
      end loop;
      Ender := Expect (State, ")");
      if Natural (Result.Tuple_Elements.Length) < 2 then
         Reject_Unsupported
           (State,
            "tuple types require at least two element types in the current PR11.3 subset");
      end if;
      Result.Span := CM.Join (Start.Span, Ender.Span);
      return Result;
   end Parse_Tuple_Type_Spec;

   function Parse_Named_Type_Spec
     (State : in out Parser_State;
      Kind  : CM.Type_Spec_Kind) return CM.Type_Spec
   is
      Name_Expr : constant CM.Expr_Access := Parse_Package_Name (State);
      Result    : CM.Type_Spec;
      End_Span  : FT.Source_Span := Name_Expr.Span;
   begin
      Result.Kind := Kind;
      Result.Name := FT.To_UString (Name_To_String (Name_Expr));

      if FT.To_String (Current (State).Lexeme) = "(" then
         declare
            Start_Paren : constant FL.Token := Expect (State, "(");
            Assoc       : CM.Constraint_Association;
            Ender       : FL.Token;
         begin
            loop
               Assoc := (others => <>);
               if Current (State).Kind in FL.Identifier | FL.Keyword
                 and then FT.To_String (Next (State).Lexeme) = "="
               then
                  declare
                     Name_Token : constant FL.Token := Expect_Identifier (State);
                  begin
                     Assoc.Is_Named := True;
                     Assoc.Name := Name_Token.Lexeme;
                     Assoc.Span := Name_Token.Span;
                  end;
                  Require (State, "=");
               end if;
               Assoc.Value := Parse_Expression (State);
               Assoc.Span :=
                 (if Assoc.Value = null then Start_Paren.Span
                  else
                    (if Assoc.Is_Named
                     then CM.Join (Assoc.Span, Assoc.Value.Span)
                     else Assoc.Value.Span));
               Result.Constraints.Append (Assoc);
               exit when not Match (State, ",");
            end loop;
            Ender := Expect (State, ")");
            End_Span := Ender.Span;
         end;
      end if;

      Result.Span := CM.Join (Name_Expr.Span, End_Span);
      return Result;
   end Parse_Named_Type_Spec;

   function Parse_Type_Spec_Internal
     (State            : in out Parser_State;
      Allow_Access_Def : Boolean) return CM.Type_Spec
   is
   begin
      if Allow_Access_Def and then Current_Lower (State) in "access" | "not" then
         return Parse_Access_Definition (State, Type_Decl_Context => False);
      elsif FT.To_String (Current (State).Lexeme) = "(" then
         return Parse_Tuple_Type_Spec (State, Allow_Access_Def);
      end if;
      return Parse_Named_Type_Spec (State, CM.Type_Spec_Name);
   end Parse_Type_Spec_Internal;

   function Parse_Object_Type
     (State : in out Parser_State) return CM.Type_Spec is
   begin
      return Parse_Type_Spec_Internal (State, Allow_Access_Def => True);
   end Parse_Object_Type;

   function Parse_Subtype_Indication
     (State : in out Parser_State) return CM.Type_Spec
   is
      Start  : constant FT.Source_Span := Current (State).Span;
      Result : CM.Type_Spec;
   begin
      if Match (State, "not") then
         Require (State, "null");
         Result.Not_Null := True;
      end if;
      if FT.To_String (Current (State).Lexeme) = "(" then
         Result := Parse_Tuple_Type_Spec (State, Allow_Access_Def => False);
         Result.Kind := CM.Type_Spec_Tuple;
         Result.Span := CM.Join (Start, Result.Span);
         return Result;
      end if;
      Result := Parse_Named_Type_Spec (State, CM.Type_Spec_Subtype_Indication);
      Result.Span := CM.Join (Start, Result.Span);
      return Result;
   end Parse_Subtype_Indication;

   function Parse_Return_Type
     (State : in out Parser_State) return CM.Type_Spec is
   begin
      if Current_Lower (State) in "access" | "not" then
         return Parse_Access_Definition (State, Type_Decl_Context => False);
      end if;
      return Parse_Object_Type (State);
   end Parse_Return_Type;

   function Parse_Array_Type
     (State : in out Parser_State;
      Start : FL.Token) return CM.Type_Decl
   is
      Result        : CM.Type_Decl;
      Unconstrained : Boolean := False;
      Index_Name    : CM.Expr_Access;
      Item          : CM.Array_Index;
      Semi          : FL.Token;
   begin
      Require (State, "array");
      Require (State, "(");
      loop
         Index_Name := Parse_Name_Expression (State);
         if Match (State, "range") then
            Require (State, "<");
            Require (State, ">");
            Unconstrained := True;
            Item.Kind := CM.Array_Index_Subtype;
            Item.Name_Expr := Index_Name;
            Item.Span := Index_Name.Span;
         else
            Item.Kind := CM.Array_Index_Subtype;
            Item.Name_Expr := Index_Name;
            Item.Span := Index_Name.Span;
         end if;
         Result.Indexes.Append (Item);
         exit when not Match (State, ",");
      end loop;
      Require (State, ")");
      Require (State, "of");
      Result.Component_Type := Parse_Object_Type (State);
      Semi := Expect (State, ";");
      Result.Kind :=
        (if Unconstrained then CM.Type_Decl_Unconstrained_Array
         else CM.Type_Decl_Constrained_Array);
      Result.Span := CM.Join (Start.Span, Semi.Span);
      return Result;
   end Parse_Array_Type;

   function Parse_Component_Decl
     (State : in out Parser_State) return CM.Component_Decl
   is
      First : constant FL.Token := Expect_Identifier (State);
      Names : FT.UString_Vectors.Vector;
      Decl  : CM.Component_Decl;
      Semi  : FL.Token;
   begin
      Names.Append (First.Lexeme);
      while Match (State, ",") loop
         Names.Append (Expect_Identifier (State).Lexeme);
      end loop;
      Require (State, ":");
      Decl.Names := Names;
      Decl.Field_Type := Parse_Object_Type (State);
      Semi := Expect (State, ";");
      Decl.Span := CM.Join (First.Span, Semi.Span);
      return Decl;
   end Parse_Component_Decl;

   function Parse_Discriminant_Spec_List
     (State : in out Parser_State) return CM.Discriminant_Spec_Vectors.Vector
   is
      Start  : constant FL.Token := Expect (State, "(");
      Result : CM.Discriminant_Spec_Vectors.Vector;
      Ender  : FL.Token;
   begin
      loop
         declare
            Name : constant FL.Token := Expect_Identifier (State);
            Item : CM.Discriminant_Spec;
         begin
            Item.Name := Name.Lexeme;
            Require (State, ":");
            Item.Disc_Type := Parse_Object_Type (State);
            if Match (State, "=") then
               Item.Has_Default := True;
               Item.Default_Expr := Parse_Expression (State);
            end if;
            Item.Span :=
              (if Item.Has_Default and then Item.Default_Expr /= null
               then CM.Join (Name.Span, Item.Default_Expr.Span)
               else CM.Join (Name.Span, Item.Disc_Type.Span));
            Result.Append (Item);
         end;
         exit when not Match (State, ",");
      end loop;
      Ender := Expect (State, ")");
      if not Result.Is_Empty then
         declare
            First_Item : CM.Discriminant_Spec := Result (Result.First_Index);
         begin
            First_Item.Span := CM.Join (Start.Span, Ender.Span);
            Result.Replace_Element (Result.First_Index, First_Item);
         end;
      end if;
      return Result;
   end Parse_Discriminant_Spec_List;

   function Parse_Record_Type
     (State : in out Parser_State;
      Start : FL.Token;
      Seed  : CM.Type_Decl) return CM.Type_Decl
   is
      Result       : CM.Type_Decl := Seed;
      Semi         : FL.Token;
      Variant_Semi : FL.Token;
   begin
      loop
         exit when Current_Lower (State) = "end";
         if Current_Lower (State) = "case" then
            declare
               Case_Token  : constant FL.Token := Expect (State, "case");
               Name_Expr   : constant CM.Expr_Access := Parse_Name_Expression (State);
            begin
               if not Result.Has_Discriminant then
                  Reject_Unsupported
                    (State,
                     "variant records are outside the current PR07 result-record subset without a matching boolean discriminant");
               end if;
               Result.Variant_Discriminant_Name := FT.To_UString (Name_To_String (Name_Expr));
               Require (State, "is");
               loop
                  declare
                     Variant_Start : constant FL.Token := Expect (State, "when");
                     Alternative   : CM.Variant_Alternative;
                  begin
                     if Current_Lower (State) = "others" then
                        Alternative.Is_Others := True;
                        Advance (State);
                     else
                        Alternative.Choice_Expr := Parse_Expression (State);
                        if FT.To_String (Current (State).Lexeme) = "," then
                           Reject_Unsupported
                             (State,
                              "multi-choice variant alternatives are outside the current PR11.3 subset");
                        elsif FT.To_String (Current (State).Lexeme) = ".." then
                           Raise_Diag
                             (CM.Source_Frontend_Error
                                (Path    => Path_String (State),
                                 Span    => Current (State).Span,
                                 Message => "legacy `..` is not allowed in source ranges; use `to`"));
                        elsif Current_Lower (State) = "to" then
                           Reject_Unsupported
                             (State,
                              "range variant alternatives are outside the current PR11.3 subset");
                        elsif not Case_Choice_Is_Literal (Alternative.Choice_Expr) then
                           Reject_Unsupported
                             (State,
                              "variant alternatives currently support exactly one Boolean, integer, or Character literal choice per arm");
                        elsif Alternative.Choice_Expr.Kind = CM.Expr_Bool
                          and then Alternative.Choice_Expr.Bool_Value
                        then
                           Alternative.When_Value := True;
                        elsif Alternative.Choice_Expr.Kind = CM.Expr_Bool then
                           Alternative.When_Value := False;
                        end if;
                     end if;
                     Require (State, "then");
                     while Current_Lower (State) not in "when" | "end" loop
                        Alternative.Components.Append (Parse_Component_Decl (State));
                     end loop;
                     Alternative.Span := CM.Join (Variant_Start.Span, Current (State).Span);
                     Result.Variants.Append (Alternative);
                     if Alternative.Is_Others and then Current_Lower (State) /= "end" then
                        Raise_Diag
                          (CM.Source_Frontend_Error
                             (Path    => Path_String (State),
                              Span    => Current (State).Span,
                              Message => "`when others then` must be the final variant alternative"));
                     end if;
                     exit when Current_Lower (State) = "end";
                  end;
               end loop;
               Require (State, "end");
               Require (State, "case");
               Variant_Semi := Expect (State, ";");
               if Result.Variants.Is_Empty then
                  Reject_Unsupported
                    (State,
                     "variant part must contain at least one alternative");
               end if;
               Result.Span := CM.Join (Case_Token.Span, Variant_Semi.Span);
            end;
         else
            Result.Components.Append (Parse_Component_Decl (State));
         end if;
      end loop;
      Require (State, "end");
      Require (State, "record");
      Semi := Expect (State, ";");
      Result.Kind := CM.Type_Decl_Record;
      Result.Span := CM.Join (Start.Span, Semi.Span);
      return Result;
   end Parse_Record_Type;

   function Parse_Type_Declaration
     (State     : in out Parser_State;
      Is_Public : Boolean) return CM.Package_Item
   is
      Start  : constant FL.Token := Expect (State, "type");
      Name   : constant FL.Token := Expect_Identifier (State);
      Result : CM.Package_Item;
      Item   : CM.Type_Decl;
   begin
      Item.Is_Public := Is_Public;
      Item.Name := Name.Lexeme;

      if Current (State).Lexeme = FT.To_UString ("(") then
         Item.Discriminants := Parse_Discriminant_Spec_List (State);
         Item.Has_Discriminant := not Item.Discriminants.Is_Empty;
         if Item.Has_Discriminant then
            Item.Discriminant := Item.Discriminants (Item.Discriminants.First_Index);
         end if;
      end if;

      if Match (State, ";") then
         Item.Kind := CM.Type_Decl_Incomplete;
         Item.Span := CM.Join (Start.Span, Name.Span);
      else
         Require (State, "is");
         if Current_Lower (State) = "range" then
            Advance (State);
            Item.Low_Expr := Parse_Expression (State);
            Require_Range_Keyword (State);
            Item.High_Expr := Parse_Expression (State);
            Item.Kind := CM.Type_Decl_Integer;
            Item.Span := CM.Join (Start.Span, Expect (State, ";").Span);
         elsif Current_Lower (State) = "digits" then
            Advance (State);
            Item.Digits_Expr := Parse_Expression (State);
            Require (State, "range");
            Item.Low_Expr := Parse_Expression (State);
            Require_Range_Keyword (State);
            Item.High_Expr := Parse_Expression (State);
            Item.Kind := CM.Type_Decl_Float;
            Item.Span := CM.Join (Start.Span, Expect (State, ";").Span);
         elsif Current_Lower (State) = "array" then
            Item := Parse_Array_Type (State, Start);
            Item.Is_Public := Is_Public;
            Item.Name := Name.Lexeme;
            Item.Has_Discriminant := False;
         elsif Current_Lower (State) = "record" then
            Advance (State);
            declare
               Parsed_Record : CM.Type_Decl := Parse_Record_Type (State, Start, Item);
            begin
               Parsed_Record.Is_Public := Is_Public;
               Parsed_Record.Name := Name.Lexeme;
               Item := Parsed_Record;
            end;
         elsif Current_Lower (State) in "access" | "not" then
            Item.Access_Type := Parse_Access_Definition (State, Type_Decl_Context => True);
            Item.Kind := CM.Type_Decl_Access;
            Item.Span := CM.Join (Start.Span, Expect (State, ";").Span);
         else
            Reject_Unsupported
              (State,
               "unsupported type definition in current PR05/PR06 check subset");
         end if;
      end if;

      Result.Kind := CM.Item_Type_Decl;
      Result.Type_Data := Item;
      return Result;
   end Parse_Type_Declaration;

   function Parse_Subtype_Declaration
     (State     : in out Parser_State;
      Is_Public : Boolean) return CM.Package_Item
   is
      Start  : constant FL.Token := Expect (State, "subtype");
      Name   : constant FL.Token := Expect_Identifier (State);
      Semi   : FL.Token;
      Result : CM.Package_Item;
   begin
      Result.Kind := CM.Item_Subtype_Decl;
      Result.Sub_Data.Is_Public := Is_Public;
      Result.Sub_Data.Name := Name.Lexeme;
      Require (State, "is");
      Result.Sub_Data.Subtype_Mark := Parse_Subtype_Indication (State);
      Semi := Expect (State, ";");
      Result.Sub_Data.Span := CM.Join (Start.Span, Semi.Span);
      return Result;
   end Parse_Subtype_Declaration;

   function Parse_Parameter
     (State : in out Parser_State) return CM.Parameter_Spec
   is
      First  : constant FL.Token := Expect_Identifier (State);
      Result : CM.Parameter_Spec;
      Span_End : FT.Source_Span := First.Span;
   begin
      Result.Names.Append (First.Lexeme);
      while Match (State, ",") loop
         Result.Names.Append (Expect_Identifier (State).Lexeme);
      end loop;
      Require (State, ":");
      if Match (State, "out") then
         Result.Mode := FT.To_UString ("out");
      elsif Match (State, "in") then
         if Match (State, "out") then
            Result.Mode := FT.To_UString ("in out");
         else
            Result.Mode := FT.To_UString ("in");
         end if;
      end if;
      Result.Param_Type := Parse_Return_Type (State);
      Span_End := Result.Param_Type.Span;
      Result.Span := CM.Join (First.Span, Span_End);
      return Result;
   end Parse_Parameter;

   function Parse_Subprogram_Spec
     (State : in out Parser_State) return CM.Subprogram_Spec
   is
      Start : constant FL.Token := Current (State);
      Name  : FL.Token;
      Result : CM.Subprogram_Spec;
      Close  : FT.Source_Span := Start.Span;
   begin
      if Current_Lower (State) = "procedure" then
         Reject_Legacy_Keyword
           (State,
            Legacy      => "procedure",
            Replacement => "function",
            Context     => "subprogram declarations");
      elsif Current_Lower (State) /= "function" then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path_String (State),
               Span    => Current (State).Span,
               Message => "expected subprogram declaration"));
      end if;

      Result.Kind := FT.To_UString ("function");
      Advance (State);
      Name := Expect_Identifier (State);
      Result.Name := Name.Lexeme;

      if Match (State, "(") then
         loop
            Result.Params.Append (Parse_Parameter (State));
            exit when not Match (State, ";");
         end loop;
         Close := Expect (State, ")").Span;
      else
         Close := Name.Span;
      end if;

      if Current_Lower (State) in "returns" | "return" then
         Require_Returns_Keyword (State);
         Result.Has_Return_Type := True;
         Result.Return_Type := Parse_Return_Type (State);
         Result.Return_Is_Access_Def :=
           Result.Return_Type.Kind = CM.Type_Spec_Access_Def;
         Close := Result.Return_Type.Span;
      end if;

      Result.Span := CM.Join (Start.Span, Close);
      return Result;
   end Parse_Subprogram_Spec;

   function Parse_Object_Declaration
     (State        : in out Parser_State;
      Is_Public    : Boolean) return CM.Object_Decl
   is
      First  : constant FL.Token := Expect_Identifier (State);
      Result : CM.Object_Decl;
      Semi   : FL.Token;
   begin
      Result.Is_Public := Is_Public;
      Result.Names.Append (First.Lexeme);
      while Match (State, ",") loop
         Result.Names.Append (Expect_Identifier (State).Lexeme);
      end loop;
      Require (State, ":");
      if Match (State, "constant") then
         Result.Is_Constant := True;
         if Match (State, "=") then
            Reject_Unsupported
              (State,
               "named number declarations are outside the current PR08.3a constant subset");
         end if;
      end if;
      Result.Decl_Type := Parse_Object_Type (State);
      if Match (State, "=") then
         Result.Has_Initializer := True;
         Result.Initializer := Parse_Expression (State);
      end if;
      Semi := Expect (State, ";");
      Result.Span := CM.Join (First.Span, Semi.Span);
      return Result;
   end Parse_Object_Declaration;

   function Parse_Object_Declaration_Statement
     (State : in out Parser_State) return CM.Statement_Access
   is
      Decl   : constant CM.Object_Decl := Parse_Object_Declaration (State, False);
      Result : constant CM.Statement_Access := new CM.Statement;
   begin
      Result.Kind := CM.Stmt_Object_Decl;
      Result.Decl := Decl;
      Result.Span := Decl.Span;
      return Result;
   end Parse_Object_Declaration_Statement;

   function Looks_Like_Destructure_Decl
     (State : Parser_State) return Boolean
   is
      Cursor   : Natural := State.Index;
      Saw_Comma : Boolean := False;
   begin
      if FT.To_String (Current (State).Lexeme) /= "(" then
         return False;
      end if;
      Cursor := Cursor + 1;
      if Cursor > Natural (State.Tokens.Last_Index)
        or else State.Tokens (Positive (Cursor)).Kind not in FL.Identifier | FL.Keyword
      then
         return False;
      end if;

      loop
         Cursor := Cursor + 1;
         exit when Cursor > Natural (State.Tokens.Last_Index);
         if FT.To_String (State.Tokens (Positive (Cursor)).Lexeme) = "," then
            Saw_Comma := True;
            Cursor := Cursor + 1;
            if Cursor > Natural (State.Tokens.Last_Index)
              or else State.Tokens (Positive (Cursor)).Kind not in FL.Identifier | FL.Keyword
            then
               return False;
            end if;
         elsif FT.To_String (State.Tokens (Positive (Cursor)).Lexeme) = ")" then
            exit;
         else
            return False;
         end if;
      end loop;

      if not Saw_Comma then
         return False;
      end if;
      Cursor := Cursor + 1;
      return Cursor <= Natural (State.Tokens.Last_Index)
        and then FT.To_String (State.Tokens (Positive (Cursor)).Lexeme) = ":";
   end Looks_Like_Destructure_Decl;

   function Parse_Destructure_Declaration_Statement
     (State : in out Parser_State) return CM.Statement_Access
   is
      Start  : constant FL.Token := Expect (State, "(");
      Result : constant CM.Statement_Access := new CM.Statement;
      Ender  : FL.Token;
      Semi   : FL.Token;
   begin
      Result.Kind := CM.Stmt_Destructure_Decl;
      Result.Destructure.Names.Append (Expect_Identifier (State).Lexeme);
      while Match (State, ",") loop
         Result.Destructure.Names.Append (Expect_Identifier (State).Lexeme);
      end loop;
      Ender := Expect (State, ")");
      Require (State, ":");
      Result.Destructure.Decl_Type := Parse_Object_Type (State);
      if not Match (State, "=") then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path_String (State),
               Span    => Ender.Span,
               Message => "destructuring declarations require an initializer"));
      end if;
      Result.Destructure.Has_Initializer := True;
      Result.Destructure.Initializer := Parse_Expression (State);
      Semi := Expect (State, ";");
      Result.Destructure.Span := CM.Join (Start.Span, Semi.Span);
      Result.Span := Result.Destructure.Span;
      return Result;
   end Parse_Destructure_Declaration_Statement;

   function Parse_Statement
     (State : in out Parser_State) return CM.Statement_Access;

   function Case_Choice_Is_Literal
     (Expr : CM.Expr_Access) return Boolean is
   begin
      if Expr = null then
         return False;
      elsif Expr.Kind in CM.Expr_Int | CM.Expr_Bool | CM.Expr_Char then
         return True;
      elsif Expr.Kind = CM.Expr_Unary and then Expr.Inner /= null then
         return (FT.To_String (Expr.Operator) = "+"
                 or else FT.To_String (Expr.Operator) = "-")
           and then Expr.Inner.Kind = CM.Expr_Int;
      end if;
      return False;
   end Case_Choice_Is_Literal;

   function Parse_Statement_Sequence
     (State        : in out Parser_State;
      End_Keywords : FT.UString_Vectors.Vector)
      return CM.Statement_Access_Vectors.Vector
   is
      Result    : CM.Statement_Access_Vectors.Vector;
      Match_End : Boolean;
   begin
      loop
         declare
            Lower : constant String := Current_Lower (State);
         begin
         Match_End := False;
         for Keyword of End_Keywords loop
            if Lower = FT.Lowercase (FT.To_String (Keyword)) then
               Match_End := True;
               exit;
            end if;
         end loop;
         exit when Match_End or else Current (State).Kind = FL.End_Of_File;
         Result.Append (Parse_Statement (State));
         end;
      end loop;
      return Result;
   end Parse_Statement_Sequence;

   function Parse_Return_Statement
     (State : in out Parser_State) return CM.Statement_Access
   is
      Start  : constant FL.Token := Expect (State, "return");
      Result : constant CM.Statement_Access := new CM.Statement;
      Semi   : FL.Token;
   begin
      Result.Kind := CM.Stmt_Return;
      if Current (State).Lexeme /= FT.To_UString (";") then
         Result.Value := Parse_Expression (State);
      end if;
      Semi := Expect (State, ";");
      Result.Span := CM.Join (Start.Span, Semi.Span);
      return Result;
   end Parse_Return_Statement;

   function Parse_If_Statement
     (State : in out Parser_State) return CM.Statement_Access
   is
      Ends        : FT.UString_Vectors.Vector;
      Start       : constant FL.Token := Expect (State, "if");
      Result      : constant CM.Statement_Access := new CM.Statement;
      Elsif_Part  : CM.Elsif_Part;
      Semi        : FL.Token;

      procedure Collapse_Wrapped_Else_If is
         Wrapped : constant CM.Statement_Access :=
           (if Result.Else_Stmts.Is_Empty
            then null
            else Result.Else_Stmts (Result.Else_Stmts.First_Index));
      begin
         if not Result.Has_Else
           or else Natural (Result.Else_Stmts.Length) /= 1
           or else Wrapped = null
           or else Wrapped.Kind /= CM.Stmt_If
         then
            return;
         end if;

         Elsif_Part := (others => <>);
         Elsif_Part.Condition := Wrapped.Condition;
         Elsif_Part.Statements := Wrapped.Then_Stmts;
         Elsif_Part.Span := Wrapped.Span;
         Result.Elsifs.Append (Elsif_Part);
         if not Wrapped.Elsifs.Is_Empty then
            for Item of Wrapped.Elsifs loop
               Result.Elsifs.Append (Item);
            end loop;
         end if;

         Result.Has_Else := Wrapped.Has_Else;
         if Wrapped.Has_Else then
            Result.Else_Stmts := Wrapped.Else_Stmts;
         else
            Result.Else_Stmts.Clear;
         end if;
      end Collapse_Wrapped_Else_If;
   begin
      Result.Kind := CM.Stmt_If;
      Result.Condition := Parse_Expression (State);
      Require (State, "then");
      Ends.Append (FT.To_UString ("elsif"));
      Ends.Append (FT.To_UString ("else"));
      Ends.Append (FT.To_UString ("end"));
      Result.Then_Stmts := Parse_Statement_Sequence (State, Ends);

      if Current_Lower (State) = "elsif" then
         Reject_Legacy_Keyword
           (State,
            Legacy      => "elsif",
            Replacement => "else if",
            Context     => "conditional chains");
      end if;

      while Current_Lower (State) = "else"
        and then FT.Lowercase (FT.To_String (Next (State).Lexeme)) = "if"
        and then Current (State).Span.Start_Pos.Line = Next (State).Span.Start_Pos.Line
      loop
         Advance (State);
         Require (State, "if");
         Elsif_Part.Condition := Parse_Expression (State);
         Require (State, "then");
         Elsif_Part.Statements := Parse_Statement_Sequence (State, Ends);
         Elsif_Part.Span :=
           (if Elsif_Part.Statements.Is_Empty then Elsif_Part.Condition.Span
            else CM.Join
              (Elsif_Part.Condition.Span,
               Elsif_Part.Statements (Elsif_Part.Statements.Last_Index).Span));
         Result.Elsifs.Append (Elsif_Part);
         if Current_Lower (State) = "elsif" then
            Reject_Legacy_Keyword
              (State,
               Legacy      => "elsif",
               Replacement => "else if",
               Context     => "conditional chains");
         end if;
      end loop;

      if Current_Lower (State) = "else" then
         Advance (State);
         Result.Has_Else := True;
         Ends.Clear;
         Ends.Append (FT.To_UString ("end"));
         Result.Else_Stmts := Parse_Statement_Sequence (State, Ends);
         Collapse_Wrapped_Else_If;
      end if;

      Require (State, "end");
      Require (State, "if");
      Semi := Expect (State, ";");
      Result.Span := CM.Join (Start.Span, Semi.Span);
      return Result;
   end Parse_If_Statement;

   function Parse_Case_Statement
     (State : in out Parser_State) return CM.Statement_Access
   is
      Arm_Ends   : FT.UString_Vectors.Vector;
      Start      : constant FL.Token := Expect (State, "case");
      Result     : constant CM.Statement_Access := new CM.Statement;
      Arm        : CM.Case_Arm;
      Arm_Start  : FL.Token;
      Arm_End    : FL.Token;
      Final_Semi : FL.Token;
      Saw_Others : Boolean := False;
   begin
      Result.Kind := CM.Stmt_Case;
      Result.Case_Expr := Parse_Expression (State);
      Require (State, "is");

      Arm_Ends.Append (FT.To_UString ("when"));
      Arm_Ends.Append (FT.To_UString ("end"));

      loop
         Arm := (others => <>);
         Arm_Start := Expect (State, "when");

         if Current_Lower (State) = "others" then
            Arm.Is_Others := True;
            Saw_Others := True;
            Advance (State);
         else
            Arm.Choice := Parse_Expression (State);
            if FT.To_String (Current (State).Lexeme) = "," then
               Reject_Unsupported
                 (State,
                  "multi-choice case arms are outside the current PR11.2 parser-completeness subset");
            elsif FT.To_String (Current (State).Lexeme) = ".." then
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path_String (State),
                     Span    => Current (State).Span,
                     Message => "legacy `..` is not allowed in source ranges; use `to`"));
            elsif Current_Lower (State) = "to" then
               Reject_Unsupported
                 (State,
                  "range case choices are outside the current PR11.2 parser-completeness subset");
            elsif not Case_Choice_Is_Literal (Arm.Choice) then
               Reject_Unsupported
                 (State,
                  "case arms currently support exactly one Boolean, integer, or Character literal choice per arm");
            end if;
         end if;

         Require (State, "then");
         Arm.Statements := Parse_Statement_Sequence (State, Arm_Ends);
         Require (State, "end");
         Require (State, "when");
         Arm_End := Expect (State, ";");
         Arm.Span := CM.Join (Arm_Start.Span, Arm_End.Span);
         Result.Case_Arms.Append (Arm);

         exit when Current_Lower (State) = "end";
         if Saw_Others then
            Raise_Diag
              (CM.Source_Frontend_Error
                 (Path    => Path_String (State),
                  Span    => Current (State).Span,
                  Message => "`when others then` must be the final case arm"));
         end if;
      end loop;

      if Result.Case_Arms.Is_Empty
        or else not Result.Case_Arms (Result.Case_Arms.Last_Index).Is_Others
      then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path_String (State),
               Span    => Current (State).Span,
               Message => "case statements currently require a final `when others then` arm"));
      end if;

      Require (State, "end");
      Require (State, "case");
      Final_Semi := Expect (State, ";");
      Result.Span := CM.Join (Start.Span, Final_Semi.Span);
      return Result;
   end Parse_Case_Statement;

   function Parse_While_Statement
     (State : in out Parser_State) return CM.Statement_Access
   is
      Ends   : FT.UString_Vectors.Vector;
      Start  : constant FL.Token := Expect (State, "while");
      Result : constant CM.Statement_Access := new CM.Statement;
      Semi   : FL.Token;
   begin
      Result.Kind := CM.Stmt_While;
      Result.Condition := Parse_Expression (State);
      Require (State, "loop");
      Ends.Append (FT.To_UString ("end"));
      Result.Body_Stmts := Parse_Statement_Sequence (State, Ends);
      Require (State, "end");
      Require (State, "loop");
      Semi := Expect (State, ";");
      Result.Span := CM.Join (Start.Span, Semi.Span);
      return Result;
   end Parse_While_Statement;

   function Parse_For_Statement
     (State : in out Parser_State) return CM.Statement_Access
   is
      Ends   : FT.UString_Vectors.Vector;
      Start  : constant FL.Token := Expect (State, "for");
      Result : constant CM.Statement_Access := new CM.Statement;
      Semi   : FL.Token;
   begin
      Result.Kind := CM.Stmt_For;
      Result.Loop_Var := Expect_Identifier (State).Lexeme;
      Require (State, "in");
      Result.Loop_Range.Span := Current (State).Span;
      Result.Loop_Range.Name_Expr := Parse_Expression (State);
      if Current_Lower (State) = "to" or else FT.To_String (Current (State).Lexeme) = ".." then
         Require_Range_Keyword (State);
         Result.Loop_Range.Kind := CM.Range_Explicit;
         Result.Loop_Range.Low_Expr := Result.Loop_Range.Name_Expr;
         Result.Loop_Range.High_Expr := Parse_Expression (State);
         Result.Loop_Range.Span :=
           CM.Join (Result.Loop_Range.Low_Expr.Span, Result.Loop_Range.High_Expr.Span);
      else
         Result.Loop_Range.Kind := CM.Range_Subtype;
      end if;
      Require (State, "loop");
      Ends.Append (FT.To_UString ("end"));
      Result.Body_Stmts := Parse_Statement_Sequence (State, Ends);
      Require (State, "end");
      Require (State, "loop");
      Semi := Expect (State, ";");
      Result.Span := CM.Join (Start.Span, Semi.Span);
      return Result;
   end Parse_For_Statement;

   function Parse_Block_Statement
     (State : in out Parser_State) return CM.Statement_Access
   is
      Ends   : FT.UString_Vectors.Vector;
      Start  : constant FL.Token := Expect (State, "declare");
      Result : constant CM.Statement_Access := new CM.Statement;
      Semi   : FL.Token;
   begin
      Result.Kind := CM.Stmt_Block;
      while Current_Lower (State) /= "begin" loop
         Result.Declarations.Append (Parse_Object_Declaration (State, False));
      end loop;
      Require (State, "begin");
      Ends.Append (FT.To_UString ("end"));
      Result.Body_Stmts := Parse_Statement_Sequence (State, Ends);
      Require (State, "end");
      Semi := Expect (State, ";");
      Result.Span := CM.Join (Start.Span, Semi.Span);
      return Result;
   end Parse_Block_Statement;

   function Parse_Loop_Statement
     (State : in out Parser_State) return CM.Statement_Access
   is
      Ends   : FT.UString_Vectors.Vector;
      Start  : constant FL.Token := Expect (State, "loop");
      Result : constant CM.Statement_Access := new CM.Statement;
      Semi   : FL.Token;
   begin
      Result.Kind := CM.Stmt_Loop;
      Ends.Append (FT.To_UString ("end"));
      Result.Body_Stmts := Parse_Statement_Sequence (State, Ends);
      Require (State, "end");
      Require (State, "loop");
      Semi := Expect (State, ";");
      Result.Span := CM.Join (Start.Span, Semi.Span);
      return Result;
   end Parse_Loop_Statement;

   function Parse_Exit_Statement
     (State : in out Parser_State) return CM.Statement_Access
   is
      Start  : constant FL.Token := Expect (State, "exit");
      Result : constant CM.Statement_Access := new CM.Statement;
      Semi   : FL.Token;
   begin
      if Current (State).Kind in FL.Identifier | FL.Keyword
        and then Current_Lower (State) /= "when"
        and then Current (State).Lexeme /= FT.To_UString (";")
      then
         Reject_Unsupported
           (State,
            "named loop labels and named exits are outside the current PR08.1 concurrency subset");
      end if;

      Result.Kind := CM.Stmt_Exit;
      if Match (State, "when") then
         Result.Condition := Parse_Expression (State);
      end if;
      Semi := Expect (State, ";");
      Result.Span := CM.Join (Start.Span, Semi.Span);
      return Result;
   end Parse_Exit_Statement;

   function Parse_Send_Statement
     (State : in out Parser_State) return CM.Statement_Access
   is
      Start  : constant FL.Token := Expect (State, "send");
      Result : constant CM.Statement_Access := new CM.Statement;
      Semi   : FL.Token;
   begin
      Result.Kind := CM.Stmt_Send;
      Result.Channel_Name := Parse_Name_Expression (State);
      Require (State, ",");
      Result.Value := Parse_Expression (State);
      Semi := Expect (State, ";");
      Result.Span := CM.Join (Start.Span, Semi.Span);
      return Result;
   end Parse_Send_Statement;

   function Parse_Receive_Statement
     (State : in out Parser_State) return CM.Statement_Access
   is
      Start  : constant FL.Token := Expect (State, "receive");
      Result : constant CM.Statement_Access := new CM.Statement;
      Semi   : FL.Token;
   begin
      Result.Kind := CM.Stmt_Receive;
      Result.Channel_Name := Parse_Name_Expression (State);
      Require (State, ",");
      Result.Target := Parse_Expression (State);
      Semi := Expect (State, ";");
      Result.Span := CM.Join (Start.Span, Semi.Span);
      return Result;
   end Parse_Receive_Statement;

   function Parse_Try_Send_Statement
     (State : in out Parser_State) return CM.Statement_Access
   is
      Start  : constant FL.Token := Expect (State, "try_send");
      Result : constant CM.Statement_Access := new CM.Statement;
      Semi   : FL.Token;
   begin
      Result.Kind := CM.Stmt_Try_Send;
      Result.Channel_Name := Parse_Name_Expression (State);
      Require (State, ",");
      Result.Value := Parse_Expression (State);
      Require (State, ",");
      Result.Success_Var := Parse_Name_Expression (State);
      Semi := Expect (State, ";");
      Result.Span := CM.Join (Start.Span, Semi.Span);
      return Result;
   end Parse_Try_Send_Statement;

   function Parse_Try_Receive_Statement
     (State : in out Parser_State) return CM.Statement_Access
   is
      Start  : constant FL.Token := Expect (State, "try_receive");
      Result : constant CM.Statement_Access := new CM.Statement;
      Semi   : FL.Token;
   begin
      Result.Kind := CM.Stmt_Try_Receive;
      Result.Channel_Name := Parse_Name_Expression (State);
      Require (State, ",");
      Result.Target := Parse_Expression (State);
      Require (State, ",");
      Result.Success_Var := Parse_Name_Expression (State);
      Semi := Expect (State, ";");
      Result.Span := CM.Join (Start.Span, Semi.Span);
      return Result;
   end Parse_Try_Receive_Statement;

   function Parse_Delay_Statement
     (State : in out Parser_State) return CM.Statement_Access
   is
      Start  : constant FL.Token := Expect (State, "delay");
      Result : constant CM.Statement_Access := new CM.Statement;
      Semi   : FL.Token;
   begin
      if Current_Lower (State) = "until" then
         Reject_Unsupported
           (State,
            "absolute `delay until` is outside the current PR08.1 concurrency subset");
      end if;
      Result.Kind := CM.Stmt_Delay;
      Result.Value := Parse_Expression (State);
      Semi := Expect (State, ";");
      Result.Span := CM.Join (Start.Span, Semi.Span);
      return Result;
   end Parse_Delay_Statement;

   function Parse_Select_Statement
     (State : in out Parser_State) return CM.Statement_Access
   is
      Arm_Ends  : FT.UString_Vectors.Vector;
      Start     : constant FL.Token := Expect (State, "select");
      Result    : constant CM.Statement_Access := new CM.Statement;
      Semi      : FL.Token;
      New_Arm   : CM.Select_Arm;
   begin
      Result.Kind := CM.Stmt_Select;
      Arm_Ends.Append (FT.To_UString ("or"));
      Arm_Ends.Append (FT.To_UString ("end"));

      loop
         if Current_Lower (State) = "when" then
            declare
               Arm_Start : constant FL.Token := Expect (State, "when");
            begin
               New_Arm := (others => <>);
               New_Arm.Kind := CM.Select_Arm_Channel;
               New_Arm.Channel_Data.Variable_Name := Expect_Identifier (State).Lexeme;
               Require (State, ":");
               New_Arm.Channel_Data.Subtype_Mark := Parse_Subtype_Indication (State);
               Require (State, "from");
               New_Arm.Channel_Data.Channel_Name := Parse_Name_Expression (State);
               Require (State, "then");
               New_Arm.Channel_Data.Statements := Parse_Statement_Sequence (State, Arm_Ends);
               New_Arm.Channel_Data.Span :=
                 (if New_Arm.Channel_Data.Statements.Is_Empty
                  then CM.Join (Arm_Start.Span, New_Arm.Channel_Data.Channel_Name.Span)
                  else CM.Join
                    (Arm_Start.Span,
                     New_Arm.Channel_Data.Statements
                       (New_Arm.Channel_Data.Statements.Last_Index).Span));
               New_Arm.Span := New_Arm.Channel_Data.Span;
            end;
         elsif Current_Lower (State) = "delay" then
            declare
               Arm_Start : constant FL.Token := Expect (State, "delay");
            begin
               New_Arm := (others => <>);
               New_Arm.Kind := CM.Select_Arm_Delay;
               if Current_Lower (State) = "until" then
                  Reject_Unsupported
                    (State,
                     "absolute `delay until` is outside the current PR08.1 concurrency subset");
               end if;
               New_Arm.Delay_Data.Duration_Expr := Parse_Expression (State);
               Require (State, "then");
               New_Arm.Delay_Data.Statements := Parse_Statement_Sequence (State, Arm_Ends);
               New_Arm.Delay_Data.Span :=
                 (if New_Arm.Delay_Data.Statements.Is_Empty
                  then CM.Join (Arm_Start.Span, New_Arm.Delay_Data.Duration_Expr.Span)
                  else CM.Join
                    (Arm_Start.Span,
                     New_Arm.Delay_Data.Statements
                       (New_Arm.Delay_Data.Statements.Last_Index).Span));
               New_Arm.Span := New_Arm.Delay_Data.Span;
            end;
         else
            Raise_Diag
              (CM.Source_Frontend_Error
                 (Path    => Path_String (State),
                  Span    => Current (State).Span,
                  Message => "expected `when` or `delay` in select arm"));
         end if;

         Result.Arms.Append (New_Arm);
         exit when not Match (State, "or");
      end loop;

      Require (State, "end");
      Require (State, "select");
      Semi := Expect (State, ";");
      Result.Span := CM.Join (Start.Span, Semi.Span);
      return Result;
   end Parse_Select_Statement;

   function Parse_Simple_Statement
     (State : in out Parser_State) return CM.Statement_Access
   is
      Start_Expr : constant CM.Expr_Access := Parse_Expression (State);
      Result     : constant CM.Statement_Access := new CM.Statement;
      Semi       : FL.Token;
   begin
      if Match (State, "=") then
         Result.Kind := CM.Stmt_Assign;
         Result.Target := Start_Expr;
         Result.Value := Parse_Expression (State);
         Semi := Expect (State, ";");
         Result.Span := CM.Join (Start_Expr.Span, Semi.Span);
         return Result;
      end if;

      Result.Kind := CM.Stmt_Call;
      Result.Call := Start_Expr;
      Semi := Expect (State, ";");
      Result.Span := CM.Join (Start_Expr.Span, Semi.Span);
      return Result;
   end Parse_Simple_Statement;

   function Parse_Statement
     (State : in out Parser_State) return CM.Statement_Access
   is
      Lower : constant String := Current_Lower (State);
   begin
      if Lower = "if" then
         return Parse_If_Statement (State);
      elsif Lower = "while" then
         return Parse_While_Statement (State);
      elsif Lower = "for" then
         return Parse_For_Statement (State);
      elsif Lower = "loop" then
         return Parse_Loop_Statement (State);
      elsif Lower = "declare" then
         return Parse_Block_Statement (State);
      elsif Lower = "exit" then
         return Parse_Exit_Statement (State);
      elsif Lower = "return" then
         return Parse_Return_Statement (State);
      elsif Lower = "case" then
         return Parse_Case_Statement (State);
      elsif Lower = "send" then
         return Parse_Send_Statement (State);
      elsif Lower = "receive" then
         return Parse_Receive_Statement (State);
      elsif Lower = "try_send" then
         return Parse_Try_Send_Statement (State);
      elsif Lower = "try_receive" then
         return Parse_Try_Receive_Statement (State);
      elsif Lower = "delay" then
         return Parse_Delay_Statement (State);
      elsif Lower = "select" then
         return Parse_Select_Statement (State);
      elsif Lower = "null" then
         declare
            Start  : constant FL.Token := Expect (State, "null");
            Semi   : constant FL.Token := Expect (State, ";");
            Result : constant CM.Statement_Access := new CM.Statement;
         begin
            Result.Kind := CM.Stmt_Null;
            Result.Span := CM.Join (Start.Span, Semi.Span);
            return Result;
         end;
      elsif Lower in "raise" | "accept" | "goto" then
         Reject_Unsupported
           (State,
            "statement form `" & Lower & "` is outside the current PR08.1 concurrency subset");
      elsif FT.To_String (Current (State).Lexeme) = "("
        and then Looks_Like_Destructure_Decl (State)
      then
         return Parse_Destructure_Declaration_Statement (State);
      elsif Current (State).Kind in FL.Identifier | FL.Keyword
        and then Next (State).Lexeme = FT.To_UString (":")
      then
         if FT.Lowercase (FT.To_String (Next (State, 2).Lexeme))
           in "loop" | "while" | "for" | "declare"
         then
            Reject_Unsupported
              (State,
               "named loop labels and named statement labels are outside the current PR08.1 concurrency subset");
         end if;
         return Parse_Object_Declaration_Statement (State);
      end if;

      return Parse_Simple_Statement (State);
   end Parse_Statement;

   function Parse_Record_Associations
     (State : in out Parser_State) return CM.Aggregate_Field_Vectors.Vector
   is
      Result : CM.Aggregate_Field_Vectors.Vector;
      Choice : FL.Token;
      Field  : CM.Aggregate_Field;
   begin
      loop
         Choice := Expect_Identifier (State);
         Require (State, "=");
         Field.Field_Name := Choice.Lexeme;
         Field.Expr := Parse_Expression (State);
         Field.Span := CM.Join (Choice.Span, Field.Expr.Span);
         Result.Append (Field);
         exit when not Match (State, ",");
      end loop;
      return Result;
   end Parse_Record_Associations;

   function Parse_Parenthesized_Like
     (State : in out Parser_State) return CM.Expr_Access
   is
      Start  : constant FL.Token := Expect (State, "(");
      Result : CM.Expr_Access;
      Tuple_Result : CM.Expr_Access;
      Ender  : FL.Token;
   begin
      if Current (State).Kind in FL.Identifier | FL.Keyword
        and then Next (State).Lexeme = FT.To_UString ("=")
      then
         Result := New_Expr;
         Result.Kind := CM.Expr_Aggregate;
         Result.Fields := Parse_Record_Associations (State);
         Ender := Expect (State, ")");
         Result.Span := CM.Join (Start.Span, Ender.Span);
         return Result;
      end if;

      Result := Parse_Expression (State);
      if Match (State, ",") then
         Tuple_Result := New_Expr;
         Tuple_Result.Kind := CM.Expr_Tuple;
         Tuple_Result.Elements.Append (Result);
         loop
            Tuple_Result.Elements.Append (Parse_Expression (State));
            exit when not Match (State, ",");
         end loop;
         Ender := Expect (State, ")");
         Tuple_Result.Span := CM.Join (Start.Span, Ender.Span);
         return Tuple_Result;
      end if;
      if Match (State, "as") then
         declare
            Subtype_Expr : constant CM.Expr_Access := Parse_Name_Expression (State);
            Wrapped      : constant CM.Expr_Access := New_Expr;
         begin
            Ender := Expect (State, ")");
            Wrapped.Kind := CM.Expr_Annotated;
            Wrapped.Inner := Result;
            Wrapped.Target := Subtype_Expr;
            Wrapped.Span := CM.Join (Start.Span, Ender.Span);
            return Wrapped;
         end;
      end if;

      Ender := Expect (State, ")");
      Result.Span := CM.Join (Start.Span, Ender.Span);
      return Result;
   end Parse_Parenthesized_Like;

   function Parse_Allocator
     (State : in out Parser_State) return CM.Expr_Access
   is
      Start  : constant FL.Token := Expect (State, "new");
      Result : constant CM.Expr_Access := New_Expr;
   begin
      Result.Kind := CM.Expr_Allocator;
      if Current (State).Lexeme = FT.To_UString ("(") then
         Result.Value := Parse_Parenthesized_Like (State);
      else
         declare
            Name_Expr : constant CM.Expr_Access := Parse_Name_Expression (State);
            Inner     : constant CM.Expr_Access := New_Expr;
         begin
            Inner.Kind := CM.Expr_Subtype_Indication;
            Inner.Name := FT.To_UString (Name_To_String (Name_Expr));
            Inner.Target := Name_Expr;
            Inner.Span := Name_Expr.Span;
            Result.Value := Inner;
         end;
      end if;
      Result.Span := CM.Join (Start.Span, Result.Value.Span);
      return Result;
   end Parse_Allocator;

   function Parse_Primary
     (State : in out Parser_State) return CM.Expr_Access
   is
      Token  : constant FL.Token := Current (State);
      Result : constant CM.Expr_Access := New_Expr;
      use type FL.Token_Kind;
      Lower : constant String := FT.Lowercase (FT.To_String (Token.Lexeme));
   begin
      if Token.Kind = FL.Integer_Literal then
         Advance (State);
         Result.Kind := CM.Expr_Int;
         Result.Text := Token.Lexeme;
         begin
            Result.Int_Value :=
              CM.Wide_Integer'Value
                (FT.To_String (Token.Lexeme));
         exception
            when Constraint_Error =>
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path_String (State),
                     Span    => Token.Span,
                     Message => "integer literal is out of range",
                     Note    =>
                       "literal `" & FT.To_String (Token.Lexeme)
                       & "` cannot be represented"));
         end;
         Result.Span := Token.Span;
         return Result;
      elsif Token.Kind = FL.Real_Literal then
         Advance (State);
         Result.Kind := CM.Expr_Real;
         Result.Text := Token.Lexeme;
         Result.Span := Token.Span;
         return Result;
      elsif Token.Kind = FL.String_Literal then
         Advance (State);
         Result.Kind := CM.Expr_String;
         Result.Text := Token.Lexeme;
         Result.Span := Token.Span;
         return Result;
      elsif Token.Kind = FL.Character_Literal then
         Advance (State);
         Result.Kind := CM.Expr_Char;
         Result.Text := Token.Lexeme;
         Result.Span := Token.Span;
         return Result;
      elsif Lower = "new" then
         return Parse_Allocator (State);
      elsif Token.Kind = FL.Identifier or else Token.Kind = FL.Keyword then
         if Lower = "null" then
            Advance (State);
            Result.Kind := CM.Expr_Null;
            Result.Span := Token.Span;
            return Result;
         elsif Lower = "true" or else Lower = "false" then
            Advance (State);
            Result.Kind := CM.Expr_Bool;
            Result.Bool_Value := Lower = "true";
            Result.Span := Token.Span;
            return Result;
         end if;
         return Parse_Name_Expression (State);
      elsif FT.To_String (Token.Lexeme) = "(" then
         return Parse_Parenthesized_Like (State);
      end if;

      Raise_Diag
        (CM.Source_Frontend_Error
           (Path    => Path_String (State),
            Span    => Token.Span,
            Message => "unsupported primary expression",
            Note    => "saw `" & FT.To_String (Token.Lexeme) & "`"));
      return Result;
   end Parse_Primary;

   function Parse_Factor
     (State : in out Parser_State) return CM.Expr_Access
   is
      Token  : FL.Token;
      Result : CM.Expr_Access;
   begin
      if Current_Lower (State) = "not" then
         Token := Expect (State, "not");
         Result := New_Expr;
         Result.Kind := CM.Expr_Unary;
         Result.Operator := FT.To_UString ("not");
         Result.Inner := Parse_Primary (State);
         Result.Span := CM.Join (Token.Span, Result.Inner.Span);
         return Result;
      end if;
      return Parse_Primary (State);
   end Parse_Factor;

   function Parse_Term
     (State : in out Parser_State) return CM.Expr_Access
   is
      Result      : CM.Expr_Access := Parse_Factor (State);
      Op          : FT.UString;
      Right       : CM.Expr_Access;
      Next_Result : CM.Expr_Access;
   begin
      loop
         declare
            Lower : constant String := Current_Lower (State);
         begin
            exit when Lower not in "*" | "/" | "mod" | "rem";
         Op := Current (State).Lexeme;
         Advance (State);
         Right := Parse_Factor (State);
         Next_Result := New_Expr;
         Next_Result.Kind := CM.Expr_Binary;
         Next_Result.Operator := Op;
         Next_Result.Left := Result;
         Next_Result.Right := Right;
         Next_Result.Span := CM.Join (Result.Span, Right.Span);
         Result := Next_Result;
         end;
      end loop;
      return Result;
   end Parse_Term;

   function Parse_Simple_Expr
     (State : in out Parser_State) return CM.Expr_Access
   is
      Unary       : FT.UString := FT.To_UString ("");
      Result      : CM.Expr_Access;
      Right       : CM.Expr_Access;
      Next_Result : CM.Expr_Access;
      Start       : FT.Source_Span := Current (State).Span;
   begin
      if FT.To_String (Current (State).Lexeme) in "+" | "-" then
         Unary := Current (State).Lexeme;
         Start := Current (State).Span;
         Advance (State);
      end if;

      Result := Parse_Term (State);
      if FT.To_String (Unary) = "-" then
         Next_Result := New_Expr;
         Next_Result.Kind := CM.Expr_Unary;
         Next_Result.Operator := Unary;
         Next_Result.Inner := Result;
         Next_Result.Span := CM.Join (Start, Result.Span);
         Result := Next_Result;
      end if;

      loop
         declare
            Lower : constant String := FT.To_String (Current (State).Lexeme);
         begin
            exit when Lower not in "+" | "-";
         declare
            Op : constant FT.UString := Current (State).Lexeme;
         begin
            Advance (State);
            Right := Parse_Term (State);
            Next_Result := New_Expr;
            Next_Result.Kind := CM.Expr_Binary;
            Next_Result.Operator := Op;
            Next_Result.Left := Result;
            Next_Result.Right := Right;
            Next_Result.Span := CM.Join (Result.Span, Right.Span);
            Result := Next_Result;
         end;
         end;
      end loop;

      return Result;
   end Parse_Simple_Expr;

   function Parse_Relation
     (State : in out Parser_State) return CM.Expr_Access
   is
      Result : CM.Expr_Access := Parse_Simple_Expr (State);
      Lower  : constant String := FT.To_String (Current (State).Lexeme);
      Right  : CM.Expr_Access;
      Next_Result : CM.Expr_Access;
   begin
      if Lower in "==" | "!=" | "<" | "<=" | ">" | ">=" then
         Advance (State);
         Right := Parse_Simple_Expr (State);
         Next_Result := New_Expr;
         Next_Result.Kind := CM.Expr_Binary;
         Next_Result.Operator := FT.To_UString (Lower);
         Next_Result.Left := Result;
         Next_Result.Right := Right;
         Next_Result.Span := CM.Join (Result.Span, Right.Span);
         return Next_Result;
      end if;
      return Result;
   end Parse_Relation;

   function Parse_And_Then
     (State : in out Parser_State) return CM.Expr_Access
   is
      Result : CM.Expr_Access := Parse_Relation (State);
      Right  : CM.Expr_Access;
      Next_Result : CM.Expr_Access;
   begin
      while Current_Lower (State) = "and" and then FT.Lowercase (FT.To_String (Next (State).Lexeme)) = "then" loop
         Advance (State);
         Advance (State);
         Right := Parse_Relation (State);
         Next_Result := New_Expr;
         Next_Result.Kind := CM.Expr_Binary;
         Next_Result.Operator := FT.To_UString ("and then");
         Next_Result.Left := Result;
         Next_Result.Right := Right;
         Next_Result.Span := CM.Join (Result.Span, Right.Span);
         Result := Next_Result;
      end loop;
      return Result;
   end Parse_And_Then;

   function Parse_Expression
     (State : in out Parser_State) return CM.Expr_Access is
   begin
      return Parse_And_Then (State);
   end Parse_Expression;

   function Parse_Name_Expression
     (State : in out Parser_State) return CM.Expr_Access
   is
      Base   : constant FL.Token := Expect_Identifier (State);
      Result : CM.Expr_Access := New_Expr;
      Next_Result : CM.Expr_Access;
      Open_Tok : FL.Token;
      Close_Tok : FL.Token;
      Selector : FL.Token;
   begin
      Result.Kind := CM.Expr_Ident;
      Result.Name := Base.Lexeme;
      Result.Span := Base.Span;

      loop
         if Match (State, ".") then
            if Current (State).Kind in FL.Identifier | FL.Keyword | FL.Integer_Literal then
               Selector := Current (State);
               Advance (State);
               Next_Result := New_Expr;
               Next_Result.Kind := CM.Expr_Select;
               Next_Result.Prefix := Result;
               Next_Result.Selector := Selector.Lexeme;
               Next_Result.Span := CM.Join (Result.Span, Selector.Span);
               Result := Next_Result;
            else
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path_String (State),
                     Span    => Current (State).Span,
                     Message => "expected field selector after `.`"));
            end if;
         elsif FT.To_String (Current (State).Lexeme) = "(" then
            Open_Tok := Expect (State, "(");
            Next_Result := New_Expr;
            Next_Result.Kind := CM.Expr_Apply;
            Next_Result.Callee := Result;
            if FT.To_String (Current (State).Lexeme) /= ")" then
               loop
                  Next_Result.Args.Append (Parse_Expression (State));
                  exit when not Match (State, ",");
               end loop;
            end if;
            Close_Tok := Expect (State, ")");
            Next_Result.Has_Call_Span := True;
            Next_Result.Call_Span := CM.Join (Open_Tok.Span, Close_Tok.Span);
            Next_Result.Span := CM.Join (Result.Span, Close_Tok.Span);
            Result := Next_Result;
         else
            exit;
         end if;
      end loop;

      return Result;
   end Parse_Name_Expression;

   function Parse_Subprogram_Body
     (State     : in out Parser_State;
      Is_Public : Boolean) return CM.Package_Item
   is
      Result : CM.Package_Item;
      Ends   : FT.UString_Vectors.Vector;
      Start  : constant FT.Source_Span := Current (State).Span;
      Semi   : FL.Token;
   begin
      Result.Kind := CM.Item_Subprogram;
      Result.Subp_Data.Is_Public := Is_Public;
      Result.Subp_Data.Spec := Parse_Subprogram_Spec (State);
      Require (State, "is");
      while Current_Lower (State) /= "begin" loop
         Result.Subp_Data.Declarations.Append
           (Parse_Object_Declaration (State, False));
      end loop;
      Require (State, "begin");
      Ends.Append (FT.To_UString ("end"));
      Result.Subp_Data.Statements := Parse_Statement_Sequence (State, Ends);
      Require (State, "end");
      if Current (State).Kind in FL.Identifier | FL.Keyword then
         Advance (State);
      end if;
      Semi := Expect (State, ";");
      Result.Subp_Data.Span := CM.Join (Start, Semi.Span);
      return Result;
   end Parse_Subprogram_Body;

   function Parse_Task_Declaration
     (State     : in out Parser_State;
      Is_Public : Boolean) return CM.Package_Item
   is
      Result : CM.Package_Item;
      Ends   : FT.UString_Vectors.Vector;
      Start  : constant FT.Source_Span := Current (State).Span;
      Semi   : FL.Token;
   begin
      if Is_Public then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path_String (State),
               Span    => Current (State).Span,
               Message => "task declarations cannot be public"));
      end if;

      Result.Kind := CM.Item_Task;
      Require (State, "task");
      Result.Task_Data.Name := Expect_Identifier (State).Lexeme;
      if Match (State, "with") then
         if Current_Lower (State) /= "priority" then
            Raise_Diag
              (CM.Source_Frontend_Error
                 (Path    => Path_String (State),
                  Span    => Current (State).Span,
                  Message => "only `Priority` is supported in task aspect clauses"));
         end if;
         Advance (State);
         Require (State, "=");
         Result.Task_Data.Has_Explicit_Priority := True;
         Result.Task_Data.Priority := Parse_Expression (State);
      end if;
      Require (State, "is");
      while Current_Lower (State) /= "begin" loop
         declare
            Lower : constant String := Current_Lower (State);
         begin
            if Lower in "type" | "subtype" | "function" | "procedure" then
               Reject_Unsupported
                 (State,
                  "task declarative parts only support object declarations in the current PR08.1 concurrency subset");
            elsif Lower in "task" | "channel" then
               Reject_Unsupported
                 (State,
                  "nested task and channel declarations are outside the current PR08.1 concurrency subset");
            end if;
         end;
         Result.Task_Data.Declarations.Append
           (Parse_Object_Declaration (State, False));
      end loop;
      Require (State, "begin");
      Ends.Append (FT.To_UString ("end"));
      Result.Task_Data.Statements := Parse_Statement_Sequence (State, Ends);
      Require (State, "end");
      Result.Task_Data.End_Name := Expect_Identifier (State).Lexeme;
      Semi := Expect (State, ";");
      Result.Task_Data.Span := CM.Join (Start, Semi.Span);
      return Result;
   end Parse_Task_Declaration;

   function Parse_Channel_Declaration
     (State     : in out Parser_State;
      Is_Public : Boolean) return CM.Package_Item
   is
      Result : CM.Package_Item;
      Start  : constant FT.Source_Span := Current (State).Span;
      Semi   : FL.Token;
   begin
      Result.Kind := CM.Item_Channel;
      Result.Chan_Data.Is_Public := Is_Public;
      Require (State, "channel");
      Result.Chan_Data.Name := Expect_Identifier (State).Lexeme;
      Require (State, ":");
      Result.Chan_Data.Element_Type := Parse_Subtype_Indication (State);
      Require (State, "capacity");
      Result.Chan_Data.Capacity := Parse_Expression (State);
      Semi := Expect (State, ";");
      Result.Chan_Data.Span := CM.Join (Start, Semi.Span);
      return Result;
   end Parse_Channel_Declaration;

   function Parse_Package_Item
     (State : in out Parser_State) return CM.Package_Item
   is
      Is_Public : constant Boolean := Match (State, "public");
      Lower     : constant String := Current_Lower (State);
      Result    : CM.Package_Item;
   begin
      if Lower = "type" then
         return Parse_Type_Declaration (State, Is_Public);
      elsif Lower = "subtype" then
         return Parse_Subtype_Declaration (State, Is_Public);
      elsif Lower = "function" or else Lower = "procedure" then
         return Parse_Subprogram_Body (State, Is_Public);
      elsif Lower = "task" then
         return Parse_Task_Declaration (State, Is_Public);
      elsif Lower = "channel" then
         return Parse_Channel_Declaration (State, Is_Public);
      elsif Lower in "generic" | "protected" | "accept" | "entry" then
         Reject_Unsupported
           (State,
            "package item `" & Lower & "` is outside the current PR08.1 concurrency subset");
      end if;

      Result.Kind := CM.Item_Object_Decl;
      Result.Obj_Data := Parse_Object_Declaration (State, Is_Public);
      return Result;
   end Parse_Package_Item;

   function Parse
     (Input  : FS.Source_File;
      Tokens : FL.Token_Vectors.Vector) return CM.Parse_Result
   is
      State        : Parser_State := (Input => Input, Tokens => Tokens, others => <>);
      Result       : CM.Parsed_Unit;
      Start_Token  : FL.Token;
      End_Token    : FL.Token;
      Ends         : FL.Token;
      Package_Name : CM.Expr_Access;
      End_Name     : CM.Expr_Access;
      Clause       : CM.With_Clause;
   begin
      Result.Path := Input.Path;
      while Current_Lower (State) = "with" loop
         Start_Token := Expect (State, "with");
         Clause.Names.Clear;
         loop
            Package_Name := Parse_Package_Name (State);
            Clause.Names.Append (FT.To_UString (Name_To_String (Package_Name)));
            exit when not Match (State, ",");
         end loop;
         Ends := Expect (State, ";");
         Clause.Span := CM.Join (Start_Token.Span, Ends.Span);
         Result.Withs.Append (Clause);
      end loop;

      if Current_Lower (State) = "generic" then
         Reject_Unsupported
           (State,
            "generic units are outside the current PR05/PR06 check subset");
      end if;

      Start_Token := Expect (State, "package");
      Package_Name := Parse_Package_Name (State);
      Result.Package_Name := FT.To_UString (Name_To_String (Package_Name));
      Require (State, "is");
      while Current_Lower (State) /= "end" loop
         Result.Items.Append (Parse_Package_Item (State));
      end loop;
      End_Token := Expect (State, "end");
      End_Name := Parse_Package_Name (State);
      Result.End_Name := FT.To_UString (Name_To_String (End_Name));
      if FT.Lowercase (FT.To_String (Result.End_Name)) /=
        FT.Lowercase (FT.To_String (Result.Package_Name))
      then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path_String (State),
               Span    => CM.Join (End_Token.Span, End_Name.Span),
               Message => "package end name must match declared package name",
               Note    =>
                 "declared `" & FT.To_String (Result.Package_Name)
                 & "`, found `" & FT.To_String (Result.End_Name) & "`"));
      end if;
      Ends := Expect (State, ";");
      Result.Span := CM.Join (Start_Token.Span, Ends.Span);
      return (Success => True, Unit => Result);
   exception
      when Parse_Failure =>
         return (Success => False, Diagnostic => Raised_Diag);
   end Parse;
end Safe_Frontend.Check_Parse;
