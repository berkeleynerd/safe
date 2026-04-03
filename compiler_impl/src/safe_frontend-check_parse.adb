with Ada.Directories;
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
   use type CM.Type_Spec_Access;
   use type FL.Token_Kind;
   use type FT.Source_Span;
   use type FT.UString;

   Parse_Failure   : exception;
   Raised_Diag     : CM.MD.Diagnostic;

   type Parser_State is record
      Input                : FS.Source_File;
      Tokens               : FL.Token_Vectors.Vector;
      Index                : Natural := 1;
      Return_Value_Allowed : Boolean := False;
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

   function Previous (State : Parser_State) return FL.Token is
   begin
      if State.Tokens.Is_Empty or else State.Index <= 1 then
         return Eof_Token (State);
      end if;
      return State.Tokens (Positive (State.Index - 1));
   end Previous;

   function Starts_On_Later_Line
     (Before : FT.Source_Span;
      After  : FT.Source_Span) return Boolean is
   begin
      return Before.End_Pos.Line < After.Start_Pos.Line;
   end Starts_On_Later_Line;

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

   function Expect_Statement_Terminator
     (State : in out Parser_State) return FT.Source_Span
   is
      Token : constant FL.Token := Current (State);
      Last  : constant FL.Token := Previous (State);
   begin
      if Match (State, ";") then
         return Token.Span;
      end if;

      if Token.Kind = FL.Dedent or else Token.Kind = FL.End_Of_File then
         return Last.Span;
      end if;

      if Token.Kind /= FL.End_Of_File
        and then Last.Kind /= FL.End_Of_File
        and then Starts_On_Later_Line (Last.Span, Token.Span)
      then
         return Last.Span;
      end if;

      Raise_Diag
        (CM.Source_Frontend_Error
           (Path    => Path_String (State),
            Span    => Token.Span,
            Message => "expected `;`",
            Note    => "saw `" & FT.To_String (Token.Lexeme) & "`"));
      return Token.Span;
   end Expect_Statement_Terminator;

   function Match_Indent (State : in out Parser_State) return Boolean is
   begin
      if Current (State).Kind = FL.Indent then
         Advance (State);
         return True;
      end if;
      return False;
   end Match_Indent;

   function Match_Dedent (State : in out Parser_State) return Boolean is
   begin
      if Current (State).Kind = FL.Dedent then
         Advance (State);
         return True;
      end if;
      return False;
   end Match_Dedent;

   procedure Require_Indent
     (State   : in out Parser_State;
      Context : String) is
   begin
      if Match_Indent (State) then
         return;
      end if;

      Raise_Diag
        (CM.Source_Frontend_Error
           (Path    => Path_String (State),
            Span    => Current (State).Span,
            Message => "expected indented block",
            Note    => Context));
   end Require_Indent;

   procedure Require_Dedent
     (State   : in out Parser_State;
      Context : String) is
   begin
      if Match_Dedent (State) then
         return;
      end if;

      Raise_Diag
        (CM.Source_Frontend_Error
           (Path    => Path_String (State),
            Span    => Current (State).Span,
            Message => "expected block dedent",
            Note    => Context));
   end Require_Dedent;

   function Suite_End_Span
     (Statements : CM.Statement_Access_Vectors.Vector;
      Fallback   : FT.Source_Span) return FT.Source_Span is
   begin
      if Statements.Is_Empty then
         return Fallback;
      end if;
      return Statements (Statements.Last_Index).Span;
   end Suite_End_Span;

   function Item_End_Span
     (Items    : CM.Package_Item_Vectors.Vector;
      Fallback : FT.Source_Span) return FT.Source_Span is
   begin
      if Items.Is_Empty then
         return Fallback;
      end if;

      case Items (Items.Last_Index).Kind is
         when CM.Item_Unknown =>
            return Fallback;
         when CM.Item_Type_Decl =>
            return Items (Items.Last_Index).Type_Data.Span;
         when CM.Item_Subtype_Decl =>
            return Items (Items.Last_Index).Sub_Data.Span;
         when CM.Item_Object_Decl =>
            return Items (Items.Last_Index).Obj_Data.Span;
         when CM.Item_Subprogram =>
            return Items (Items.Last_Index).Subp_Data.Span;
         when CM.Item_Task =>
            return Items (Items.Last_Index).Task_Data.Span;
         when CM.Item_Channel =>
            return Items (Items.Last_Index).Chan_Data.Span;
      end case;
   end Item_End_Span;

   function Unit_End_Span
     (Items       : CM.Package_Item_Vectors.Vector;
      Statements  : CM.Statement_Access_Vectors.Vector;
      Fallback    : FT.Source_Span) return FT.Source_Span is
      Item_Span : constant FT.Source_Span := Item_End_Span (Items, Fallback);
   begin
      if Statements.Is_Empty then
         return Item_Span;
      elsif Items.Is_Empty then
         return Suite_End_Span (Statements, Fallback);
      end if;
      return Suite_End_Span (Statements, Item_Span);
   end Unit_End_Span;

   procedure Reject_Removed_Source_Spelling
     (State   : Parser_State;
      Lexeme  : String;
      Context : String := "") is
      Message : constant String :=
        (if Context'Length = 0
         then "removed source spelling `" & Lexeme & "` is not allowed"
         else "removed source spelling `" & Lexeme & "` is not allowed in " & Context);
   begin
      Raise_Diag
        (CM.Source_Frontend_Error
           (Path    => Path_String (State),
            Span    => Current (State).Span,
            Message => Message));
   end Reject_Removed_Source_Spelling;

   procedure Reject_Removed_Source_Construct
     (State   : Parser_State;
      Name    : String;
      Note    : String := "") is
   begin
      Raise_Diag
        (CM.Source_Frontend_Error
           (Path    => Path_String (State),
            Span    => Current (State).Span,
            Message => "removed source construct `" & Name & "` is not allowed",
            Note    => Note));
   end Reject_Removed_Source_Construct;

   procedure Reject_Statement_Local_Var_Outside_Statements
     (State : Parser_State) is
   begin
      Raise_Diag
        (CM.Source_Frontend_Error
           (Path    => Path_String (State),
            Span    => Current (State).Span,
            Message => "statement-local `var` declarations are only allowed in executable statement sequences"));
   end Reject_Statement_Local_Var_Outside_Statements;

   procedure Require_Returns_Keyword (State : in out Parser_State) is
   begin
      if Match (State, "returns") then
         return;
      elsif Current_Lower (State) = "return" then
         Reject_Removed_Source_Spelling
           (State,
            Lexeme  => "return",
            Context => "subprogram signatures");
      else
         Require (State, "returns");
      end if;
   end Require_Returns_Keyword;

   procedure Require_Range_Keyword (State : in out Parser_State) is
   begin
      if Match (State, "to") then
         return;
      elsif FT.To_String (Current (State).Lexeme) = ".." then
         Reject_Removed_Source_Spelling
           (State,
            Lexeme  => "..",
            Context => "source ranges");
      else
         Require (State, "to");
      end if;
   end Require_Range_Keyword;

   function Expect_Identifier
     (State : in out Parser_State) return FL.Token
   is
      Token : constant FL.Token := Current (State);
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
   function Parse_Type_Target_Expr
     (State : in out Parser_State) return CM.Expr_Access;
   function Parse_Expression
     (State : in out Parser_State) return CM.Expr_Access;
   function Parse_Enumeration_Type
     (State : in out Parser_State;
      Start : FL.Token) return CM.Type_Decl;
   function Parse_Case_Statement
     (State : in out Parser_State) return CM.Statement_Access;
   function Parse_Statement
     (State : in out Parser_State) return CM.Statement_Access;
   function Parse_Package_Item
     (State : in out Parser_State) return CM.Package_Item;
   function Case_Choice_Is_Literal
     (Expr : CM.Expr_Access) return Boolean;
   procedure Parse_Object_Declaration_Tail
     (State          : in out Parser_State;
      Result         : in out CM.Object_Decl;
      Allow_Constant : Boolean := True);

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

   function Source_Stem (State : Parser_State) return String is
      Simple : constant String := Ada.Directories.Simple_Name (Path_String (State));
      Dot    : constant Natural := Ada.Directories.Extension (Simple)'Length;
   begin
      if Dot = 0 then
         return Simple;
      end if;
      return Ada.Directories.Base_Name (Simple);
   end Source_Stem;

   function Is_Lowercase_Identifier (Text : String) return Boolean is
   begin
      if Text'Length = 0 then
         return False;
      elsif Text (Text'First) not in 'a' .. 'z' then
         return False;
      end if;

      for Index in Text'First + 1 .. Text'Last loop
         if Text (Index) not in 'a' .. 'z' | '0' .. '9' | '_' then
            return False;
         end if;
      end loop;
      return True;
   end Is_Lowercase_Identifier;

   function Looks_Like_Object_Declaration (State : Parser_State) return Boolean is
      Probe : Natural := State.Index;
      Token : FL.Token;
   begin
      Token := Current (State);
      if Token.Kind /= FL.Identifier then
         return False;
      end if;

      loop
         Probe := Probe + 1;
         exit when State.Tokens.Is_Empty
           or else Probe > Natural (State.Tokens.Last_Index);
         Token := State.Tokens (Positive (Probe));
         if FT.To_String (Token.Lexeme) = ":" then
            return True;
         elsif Token.Kind = FL.Identifier or else FT.To_String (Token.Lexeme) = "," then
            null;
         else
            return False;
         end if;
      end loop;
      return False;
   end Looks_Like_Object_Declaration;

   function Starts_Package_Item (State : Parser_State) return Boolean is
      Lower : constant String := Current_Lower (State);
   begin
      if Lower = "public" then
         return True;
      elsif Lower in "type" | "subtype" | "function" | "procedure" | "task" | "channel" then
         return True;
      elsif Current (State).Kind = FL.Identifier then
         return Looks_Like_Object_Declaration (State);
      end if;
      return False;
   end Starts_Package_Item;

   procedure Parse_Unit_Suite
     (State      : in out Parser_State;
      Result     : in out CM.Parsed_Unit;
      Terminated : Boolean := False) is
      Parsed_Statements : Boolean := False;
      procedure Validate_Unit_Statement (Stmt : CM.Statement_Access);

      procedure Validate_Unit_Statement (Stmt : CM.Statement_Access) is
      begin
         if Stmt = null then
            return;
         end if;

         case Stmt.Kind is
            when CM.Stmt_Object_Decl | CM.Stmt_Destructure_Decl =>
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path_String (State),
                     Span    => Stmt.Span,
                     Message => "unit-scope statements must not contain local declarations"));
            when CM.Stmt_Return =>
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path_String (State),
                     Span    => Stmt.Span,
                     Message => "unit-scope statements must not contain return statements"));
            when CM.Stmt_Receive | CM.Stmt_Try_Receive =>
               if not Stmt.Decl.Names.Is_Empty then
                  Raise_Diag
                    (CM.Source_Frontend_Error
                       (Path    => Path_String (State),
                        Span    => Stmt.Span,
                        Message => "unit-scope statements must not contain local declarations"));
               end if;
            when CM.Stmt_If =>
               for Nested of Stmt.Then_Stmts loop
                  Validate_Unit_Statement (Nested);
               end loop;
               for Part of Stmt.Elsifs loop
                  for Nested of Part.Statements loop
                     Validate_Unit_Statement (Nested);
                  end loop;
               end loop;
               if Stmt.Has_Else then
                  for Nested of Stmt.Else_Stmts loop
                     Validate_Unit_Statement (Nested);
                  end loop;
               end if;
            when CM.Stmt_Case =>
               for Arm of Stmt.Case_Arms loop
                  for Nested of Arm.Statements loop
                     Validate_Unit_Statement (Nested);
                  end loop;
               end loop;
            when CM.Stmt_Match =>
               for Arm of Stmt.Match_Arms loop
                  for Nested of Arm.Statements loop
                     Validate_Unit_Statement (Nested);
                  end loop;
               end loop;
            when CM.Stmt_While | CM.Stmt_For | CM.Stmt_Loop =>
               for Nested of Stmt.Body_Stmts loop
                  Validate_Unit_Statement (Nested);
               end loop;
            when CM.Stmt_Select =>
               for Arm of Stmt.Arms loop
                  case Arm.Kind is
                     when CM.Select_Arm_Channel =>
                        for Nested of Arm.Channel_Data.Statements loop
                           Validate_Unit_Statement (Nested);
                        end loop;
                     when CM.Select_Arm_Delay =>
                        for Nested of Arm.Delay_Data.Statements loop
                           Validate_Unit_Statement (Nested);
                        end loop;
                     when others =>
                        null;
                  end case;
               end loop;
            when others =>
               null;
         end case;
      end Validate_Unit_Statement;
   begin
      loop
         exit when Current (State).Kind = FL.End_Of_File
           or else (Terminated and then Current (State).Kind = FL.Dedent);

         if not Parsed_Statements and then Starts_Package_Item (State) then
            Result.Items.Append (Parse_Package_Item (State));
         else
            if Parsed_Statements
              and then
                (Starts_Package_Item (State)
                 or else Current_Lower (State) = "var")
            then
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path_String (State),
                     Span    => Current (State).Span,
                     Message => "top-level declarations must appear before top-level statements"));
            end if;
            Parsed_Statements := True;
            declare
               Stmt : constant CM.Statement_Access := Parse_Statement (State);
            begin
               Validate_Unit_Statement (Stmt);
               Result.Statements.Append (Stmt);
            end;
         end if;
      end loop;
   end Parse_Unit_Suite;

   function Starts_Removed_Access_Definition
     (State : Parser_State) return Boolean is
      Lower : constant String := Current_Lower (State);
   begin
      if Lower = "access" then
         return True;
      elsif Lower /= "not" then
         return False;
      elsif FT.Lowercase (FT.To_String (Next (State).Lexeme)) /= "null" then
         return False;
      end if;

      declare
         Third : constant String := FT.Lowercase (FT.To_String (Next (State, 2).Lexeme));
      begin
         return Third = "access";
      end;
   end Starts_Removed_Access_Definition;

   function Parse_Type_Spec_Internal
     (State            : in out Parser_State;
      Allow_Access_Def : Boolean) return CM.Type_Spec;

   function Parse_Growable_Array_Type_Spec
     (State : in out Parser_State) return CM.Type_Spec
   is
      Start  : constant FL.Token := Expect (State, "array");
      Result : CM.Type_Spec;
   begin
      Require (State, "of");
      Result.Kind := CM.Type_Spec_Growable_Array;
      Result.Element_Type :=
        new CM.Type_Spec'
          (Parse_Type_Spec_Internal (State, Allow_Access_Def => True));
      Result.Span := CM.Join (Start.Span, Result.Element_Type.Span);
      return Result;
   end Parse_Growable_Array_Type_Spec;

   function Sanitize_Type_Name_Component (Value : String) return String is
      Result : FT.UString := FT.To_UString ("");
   begin
      for Ch of Value loop
         if Ch in 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' then
            Result := Result & FT.To_UString ((1 => Ch));
         else
            Result := Result & FT.To_UString ("_");
         end if;
      end loop;

      declare
         Text  : constant String := FT.To_String (Result);
         First : Positive := Text'First;
         Last  : Natural := Text'Last;
      begin
         while First <= Text'Last and then Text (First) = '_' loop
            First := First + 1;
         end loop;
         while Last >= First and then Text (Last) = '_' loop
            Last := Last - 1;
         end loop;
         if Last < First then
            return "value";
         end if;
         return Text (First .. Last);
      end;
   end Sanitize_Type_Name_Component;

   function Type_Spec_Internal_Name (Spec : CM.Type_Spec) return FT.UString;

   function Type_Spec_Internal_Name (Spec : CM.Type_Spec) return FT.UString is
      Result        : FT.UString;
      Element_Names : FT.UString_Vectors.Vector;
   begin
      case Spec.Kind is
         when CM.Type_Spec_Name | CM.Type_Spec_Subtype_Indication | CM.Type_Spec_Binary =>
            return Spec.Name;
         when CM.Type_Spec_Growable_Array =>
            if Spec.Element_Type = null then
               return FT.To_UString ("__growable_array_value");
            end if;
            return
              FT.To_UString
                ("__growable_array_"
                 & Sanitize_Type_Name_Component
                     (FT.To_String (Type_Spec_Internal_Name (Spec.Element_Type.all))));
         when CM.Type_Spec_Optional =>
            if Spec.Element_Type = null then
               return FT.To_UString ("__optional_value");
            end if;
            return
              FT.To_UString
                ("__optional_"
                 & Sanitize_Type_Name_Component
                     (FT.To_String (Type_Spec_Internal_Name (Spec.Element_Type.all))));
         when CM.Type_Spec_Tuple =>
            Result := FT.To_UString ("__tuple");
            for Item of Spec.Tuple_Elements loop
               Element_Names.Append
                 (FT.To_UString
                    (Sanitize_Type_Name_Component
                       (FT.To_String (Type_Spec_Internal_Name (Item.all)))));
            end loop;
            for Item of Element_Names loop
               Result := Result & FT.To_UString ("_") & Item;
            end loop;
            return Result;
         when others =>
            return FT.To_UString ("");
      end case;
   end Type_Spec_Internal_Name;

   function Parse_Optional_Type_Spec
     (State            : in out Parser_State;
      Allow_Access_Def : Boolean) return CM.Type_Spec
   is
      Start  : constant FL.Token := Expect (State, "optional");
      Result : CM.Type_Spec;
   begin
      Result.Kind := CM.Type_Spec_Optional;
      Result.Element_Type :=
        new CM.Type_Spec'
          (Parse_Type_Spec_Internal (State, Allow_Access_Def => Allow_Access_Def));
      Result.Name := Type_Spec_Internal_Name (Result);
      Result.Span := CM.Join (Start.Span, Result.Element_Type.Span);
      return Result;
   end Parse_Optional_Type_Spec;

   function Parse_Object_Type_Core
     (State            : in out Parser_State;
      Allow_Access_Def : Boolean := False) return CM.Type_Spec;

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

   function Binary_Internal_Name
     (State     : Parser_State;
      Bit_Width : CM.Wide_Integer) return FT.UString is
   begin
      case Bit_Width is
         when 8 =>
            return FT.To_UString ("__binary_8");
         when 16 =>
            return FT.To_UString ("__binary_16");
         when 32 =>
            return FT.To_UString ("__binary_32");
         when 64 =>
            return FT.To_UString ("__binary_64");
         when others =>
            Raise_Diag
              (CM.Source_Frontend_Error
                 (Path    => Path_String (State),
                  Span    => Current (State).Span,
                  Message => "binary width must be one of 8, 16, 32, or 64"));
            return FT.To_UString ("");
      end case;
   end Binary_Internal_Name;

   function Parse_Binary_Type_Spec
     (State : in out Parser_State) return CM.Type_Spec
   is
      Start       : constant FL.Token := Expect (State, "binary");
      Open_Paren  : constant FL.Token := Expect (State, "(");
      Width_Expr  : constant CM.Expr_Access := Parse_Expression (State);
      Close_Paren : FL.Token;
      Result      : CM.Type_Spec;
   begin
      Result.Kind := CM.Type_Spec_Binary;
      Result.Binary_Width_Expr := Width_Expr;

      if Width_Expr = null or else Width_Expr.Kind /= CM.Expr_Int then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path_String (State),
               Span    => Open_Paren.Span,
               Message => "binary width must be an integer literal",
               Note    => "use one of `binary (8)`, `binary (16)`, `binary (32)`, or `binary (64)`"));
      else
         Result.Name := Binary_Internal_Name (State, Width_Expr.Int_Value);
      end if;

      Close_Paren := Expect (State, ")");
      Result.Span := CM.Join (Start.Span, Close_Paren.Span);
      return Result;
   end Parse_Binary_Type_Spec;

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
            Closed_Constraint : Boolean := False;
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
               if Current_Lower (State) = "to" then
                  if Assoc.Is_Named then
                     Raise_Diag
                       (CM.Source_Frontend_Error
                          (Path    => Path_String (State),
                           Span    => Current (State).Span,
                           Message => "range constraints do not use named associations"));
                  elsif not Result.Constraints.Is_Empty then
                     Raise_Diag
                       (CM.Source_Frontend_Error
                          (Path    => Path_String (State),
                           Span    => Current (State).Span,
                           Message => "range constraints accept exactly one low/high pair"));
                  end if;
                  Result.Has_Range_Constraint := True;
                  Result.Range_Low := Assoc.Value;
                  Require_Range_Keyword (State);
                  Result.Range_High := Parse_Expression (State);
                  Ender := Expect (State, ")");
                  End_Span := Ender.Span;
                  Closed_Constraint := True;
                  exit;
               end if;
               Assoc.Span :=
                 (if Assoc.Value = null then Start_Paren.Span
                  else
                    (if Assoc.Is_Named
                     then CM.Join (Assoc.Span, Assoc.Value.Span)
                     else Assoc.Value.Span));
               Result.Constraints.Append (Assoc);
               exit when not Match (State, ",");
            end loop;
            if not Closed_Constraint then
               Ender := Expect (State, ")");
               End_Span := Ender.Span;
            end if;
         end;
      end if;

      Result.Span := CM.Join (Name_Expr.Span, End_Span);
      return Result;
   end Parse_Named_Type_Spec;

   function Parse_Object_Type_Core
     (State            : in out Parser_State;
      Allow_Access_Def : Boolean := False) return CM.Type_Spec
   is
   begin
      if Current_Lower (State) = "aliased" then
         Reject_Removed_Source_Spelling (State, "aliased");
      end if;
      if Allow_Access_Def and then Starts_Removed_Access_Definition (State) then
         Reject_Removed_Source_Construct
           (State,
            "access_definition",
            "PR11.8e infers references from recursive record types; source `access` is removed");
      elsif Current_Lower (State) = "binary" then
         return Parse_Binary_Type_Spec (State);
      elsif Current_Lower (State) = "optional" then
         return Parse_Optional_Type_Spec (State, Allow_Access_Def);
      elsif Current_Lower (State) = "array"
        and then FT.To_String (Next (State).Lexeme) /= "("
      then
         return Parse_Growable_Array_Type_Spec (State);
      elsif FT.To_String (Current (State).Lexeme) = "(" then
         return Parse_Tuple_Type_Spec (State, Allow_Access_Def);
      end if;
      return Parse_Named_Type_Spec (State, CM.Type_Spec_Name);
   end Parse_Object_Type_Core;

   function Parse_Type_Spec_Internal
     (State            : in out Parser_State;
      Allow_Access_Def : Boolean) return CM.Type_Spec is
   begin
      return Parse_Object_Type_Core (State, Allow_Access_Def);
   end Parse_Type_Spec_Internal;

   function Parse_Object_Type
     (State : in out Parser_State) return CM.Type_Spec
   is
      Start  : constant FT.Source_Span := Current (State).Span;
      Result : CM.Type_Spec;
   begin
      if Match (State, "not") then
         if Current_Lower (State) /= "null" then
            Reject_Removed_Source_Spelling (State, "not");
         end if;
         Require (State, "null");
         if Current_Lower (State) = "access" then
            Reject_Removed_Source_Construct
              (State,
               "access_definition",
               "PR11.8e infers references from recursive record types; source `access` is removed");
         end if;
         Result := Parse_Object_Type_Core (State);
         Result.Not_Null := True;
         Result.Span := CM.Join (Start, Result.Span);
         return Result;
      end if;
      return Parse_Object_Type_Core (State);
   end Parse_Object_Type;

   function Parse_Subtype_Indication
     (State : in out Parser_State) return CM.Type_Spec
   is
      Start  : constant FT.Source_Span := Current (State).Span;
      Result : CM.Type_Spec;
   begin
      if Starts_Removed_Access_Definition (State) then
         Reject_Removed_Source_Construct
           (State,
            "access_definition",
            "PR11.8e infers references from recursive record types; source `access` is removed");
      end if;
      if Match (State, "not") then
         Require (State, "null");
         Result.Not_Null := True;
      end if;
      if Current_Lower (State) = "aliased" then
         Reject_Removed_Source_Spelling (State, "aliased");
      end if;
      if Current_Lower (State) = "binary" then
         Result := Parse_Binary_Type_Spec (State);
         Result.Span := CM.Join (Start, Result.Span);
         return Result;
      elsif Current_Lower (State) = "optional" then
         Result := Parse_Optional_Type_Spec (State, Allow_Access_Def => False);
         Result.Span := CM.Join (Start, Result.Span);
         return Result;
      elsif Current_Lower (State) = "array"
        and then FT.To_String (Next (State).Lexeme) /= "("
      then
         Result := Parse_Growable_Array_Type_Spec (State);
         Result.Span := CM.Join (Start, Result.Span);
         return Result;
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

   function Parse_Growable_Array_Type
     (State : in out Parser_State;
      Start : FL.Token) return CM.Type_Decl
   is
      Result : CM.Type_Decl;
      Semi   : FL.Token;
   begin
      Require (State, "array");
      Require (State, "of");
      Result.Component_Type := Parse_Object_Type (State);
      Semi := Expect (State, ";");
      Result.Kind := CM.Type_Decl_Growable_Array;
      Result.Span := CM.Join (Start.Span, Semi.Span);
      return Result;
   end Parse_Growable_Array_Type;

   function Parse_Enumeration_Type
     (State : in out Parser_State;
      Start : FL.Token) return CM.Type_Decl
   is
      Result : CM.Type_Decl;
   begin
      Require (State, "(");
      loop
         if Current (State).Kind = FL.Character_Literal then
            Raise_Diag
              (CM.Unsupported_Source_Construct
                 (Path    => Path_String (State),
                  Span    => Current (State).Span,
                  Message => "character-literal enum enumerators are deferred past PR11.8i"));
         end if;

         declare
            Literal : constant FL.Token := Expect_Identifier (State);
         begin
            Result.Enum_Literals.Append (Literal.Lexeme);
         end;

         exit when not Match (State, ",");
      end loop;

      declare
         Close_Paren : constant FL.Token := Expect (State, ")");
         Semi        : constant FL.Token := Expect (State, ";");
         pragma Unreferenced (Close_Paren);
      begin
         Result.Kind := CM.Type_Decl_Enumeration;
         Result.Span := CM.Join (Start.Span, Semi.Span);
      end;
      return Result;
   end Parse_Enumeration_Type;

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
      Span_End     : FT.Source_Span := Start.Span;
   begin
      Require_Indent (State, "record fields must be indented under `record`");
      loop
         exit when Current (State).Kind in FL.Dedent | FL.End_Of_File;
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
               Require_Indent (State, "variant alternatives must be indented under `case`");
               loop
                  exit when Current (State).Kind in FL.Dedent | FL.End_Of_File;
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
                           Reject_Removed_Source_Spelling
                             (State,
                              Lexeme  => "..",
                              Context => "source ranges");
                        elsif Current_Lower (State) = "to" then
                           Reject_Unsupported
                             (State,
                              "range variant alternatives are outside the current PR11.3 subset");
                        elsif not Case_Choice_Is_Literal (Alternative.Choice_Expr) then
                           Reject_Unsupported
                             (State,
                              "variant alternatives currently support exactly one static boolean, integer, enum, Character, or converted binary literal choice per arm");
                        elsif Alternative.Choice_Expr.Kind = CM.Expr_Bool
                          and then Alternative.Choice_Expr.Bool_Value
                        then
                           Alternative.When_Value := True;
                        elsif Alternative.Choice_Expr.Kind = CM.Expr_Bool then
                           Alternative.When_Value := False;
                        end if;
                     end if;
                     Require_Indent
                       (State,
                        "variant alternative fields must be indented under `when`");
                     while Current (State).Kind not in FL.Dedent | FL.End_Of_File loop
                        Alternative.Components.Append (Parse_Component_Decl (State));
                     end loop;
                     Require_Dedent
                       (State,
                        "variant alternative fields must align under `when`");
                     Alternative.Span :=
                       (if Alternative.Components.Is_Empty
                        then Variant_Start.Span
                        else CM.Join
                          (Variant_Start.Span,
                           Alternative.Components (Alternative.Components.Last_Index).Span));
                     Result.Variants.Append (Alternative);
                     if Alternative.Is_Others
                       and then Current (State).Kind /= FL.Dedent
                       and then Current (State).Kind /= FL.End_Of_File
                     then
                        Raise_Diag
                          (CM.Source_Frontend_Error
                             (Path    => Path_String (State),
                              Span    => Current (State).Span,
                              Message => "`when others then` must be the final variant alternative"));
                     end if;
                  end;
               end loop;
               Require_Dedent
                 (State,
                  "variant alternatives must align under `case`");
               if Result.Variants.Is_Empty then
                  Reject_Unsupported
                    (State,
                     "variant part must contain at least one alternative");
               end if;
               Span_End :=
                 (if Result.Variants.Is_Empty
                  then Case_Token.Span
                  else Result.Variants (Result.Variants.Last_Index).Span);
            end;
         else
            declare
               Component : constant CM.Component_Decl := Parse_Component_Decl (State);
            begin
               Result.Components.Append (Component);
               Span_End := Component.Span;
            end;
         end if;
      end loop;
      Require_Dedent (State, "record fields must align under `record`");
      Result.Kind := CM.Type_Decl_Record;
      Result.Span := CM.Join (Start.Span, Span_End);
      return Result;
   end Parse_Record_Type;

   function Parse_Type_Declaration
     (State     : in out Parser_State;
      Is_Public : Boolean) return CM.Package_Item
   is
      Start          : constant FL.Token := Expect (State, "type");
      Name           : constant FL.Token := Expect_Identifier (State);
      Result         : CM.Package_Item;
      Item           : CM.Type_Decl;
      Has_Type_Suite : Boolean := False;
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
         if Match_Indent (State) then
            Has_Type_Suite := True;
         end if;
         if Current_Lower (State) = "range" then
            Advance (State);
            Item.Low_Expr := Parse_Expression (State);
            Require_Range_Keyword (State);
            Item.High_Expr := Parse_Expression (State);
            Item.Kind := CM.Type_Decl_Integer;
            Item.Span := CM.Join (Start.Span, Expect (State, ";").Span);
         elsif Current_Lower (State) = "binary" then
            declare
               Binary_Spec : constant CM.Type_Spec := Parse_Binary_Type_Spec (State);
            begin
               Item.Binary_Width_Expr := Binary_Spec.Binary_Width_Expr;
               Item.Kind := CM.Type_Decl_Binary;
               Item.Span := CM.Join (Start.Span, Expect (State, ";").Span);
            end;
         elsif Current_Lower (State) = "digits" then
            Advance (State);
            Item.Digits_Expr := Parse_Expression (State);
            Require (State, "range");
            Item.Low_Expr := Parse_Expression (State);
            Require_Range_Keyword (State);
            Item.High_Expr := Parse_Expression (State);
            Item.Kind := CM.Type_Decl_Float;
            Item.Span := CM.Join (Start.Span, Expect (State, ";").Span);
         elsif FT.To_String (Current (State).Lexeme) = "(" then
            Item := Parse_Enumeration_Type (State, Start);
            Item.Is_Public := Is_Public;
            Item.Name := Name.Lexeme;
            Item.Has_Discriminant := False;
         elsif Current_Lower (State) = "array"
           and then FT.To_String (Next (State).Lexeme) = "("
         then
            Item := Parse_Array_Type (State, Start);
            Item.Is_Public := Is_Public;
            Item.Name := Name.Lexeme;
            Item.Has_Discriminant := False;
         elsif Current_Lower (State) = "array" then
            Item := Parse_Growable_Array_Type (State, Start);
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
         elsif Starts_Removed_Access_Definition (State) then
            Reject_Removed_Source_Construct
              (State,
               "access_type_definition",
               "PR11.8e infers references from recursive record types; named access types are removed");
         else
            Reject_Unsupported
              (State,
               "unsupported type definition in current PR05/PR06 check subset");
         end if;
         if Has_Type_Suite then
            Require_Dedent
              (State,
               "type definitions introduced after `is` must dedent back to the enclosing declaration level");
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
      Result.Mode := FT.To_UString ("borrow");
      if Match (State, "mut") then
         Result.Mode := FT.To_UString ("mut");
      elsif Current_Lower (State) = "in" then
         Reject_Removed_Source_Spelling
           (State,
            "in",
            "parameter declarations");
      elsif Current_Lower (State) = "out" then
         Reject_Removed_Source_Spelling
           (State,
            "out",
            "parameter declarations");
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
         Reject_Removed_Source_Spelling
           (State,
            Lexeme  => "procedure",
            Context => "subprogram declarations");
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

      if Current_Lower (State) = "returns"
        or else
          (Current_Lower (State) = "return"
           and then Current (State).Span.Start_Pos.Line = Close.End_Pos.Line)
      then
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

   procedure Parse_Object_Declaration_Tail
     (State          : in out Parser_State;
      Result         : in out CM.Object_Decl;
      Allow_Constant : Boolean := True) is
   begin
      Require (State, ":");
      if Match (State, "constant") then
         if not Allow_Constant then
            Raise_Diag
              (CM.Source_Frontend_Error
                 (Path    => Path_String (State),
                  Span    => Previous (State).Span,
                  Message => "`var` declarations cannot be constant"));
         end if;
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
   end Parse_Object_Declaration_Tail;

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
      Parse_Object_Declaration_Tail (State, Result);
      if not Result.Is_Constant and then not Result.Has_Initializer then
         Result.Has_Implicit_Default_Init := True;
      end if;
      Semi := Expect (State, ";");
      Result.Span := CM.Join (First.Span, Semi.Span);
      return Result;
   end Parse_Object_Declaration;

   function Parse_Body_Local_Object_Declaration
     (State : in out Parser_State) return CM.Object_Decl
   is
      First  : constant FL.Token := Expect_Identifier (State);
      Result : CM.Object_Decl;
      Semi   : FT.Source_Span;
   begin
      Result.Names.Append (First.Lexeme);
      while Match (State, ",") loop
         Result.Names.Append (Expect_Identifier (State).Lexeme);
      end loop;
      Parse_Object_Declaration_Tail (State, Result);
      Semi := Expect_Statement_Terminator (State);
      Result.Span := CM.Join (First.Span, Semi);
      return Result;
   end Parse_Body_Local_Object_Declaration;

   function Parse_Object_Declaration_Statement
     (State : in out Parser_State) return CM.Statement_Access
   is
      Result : constant CM.Statement_Access := new CM.Statement;
      First  : constant FL.Token := Expect_Identifier (State);
      Semi   : FT.Source_Span;
   begin
      Result.Kind := CM.Stmt_Object_Decl;
      Result.Decl.Names.Append (First.Lexeme);
      while Match (State, ",") loop
         Result.Decl.Names.Append (Expect_Identifier (State).Lexeme);
      end loop;
      Parse_Object_Declaration_Tail (State, Result.Decl);
      Semi := Expect_Statement_Terminator (State);
      Result.Decl.Span := CM.Join (First.Span, Semi);
      Result.Span := Result.Decl.Span;
      return Result;
   end Parse_Object_Declaration_Statement;

   function Parse_Var_Declaration_Statement
     (State : in out Parser_State) return CM.Statement_Access
   is
      Result : constant CM.Statement_Access := new CM.Statement;
      Start  : constant FL.Token := Expect (State, "var");
      First  : constant FL.Token := Expect_Identifier (State);
      Semi   : FT.Source_Span;
   begin
      Result.Kind := CM.Stmt_Object_Decl;
      Result.Decl.Names.Append (First.Lexeme);
      while Match (State, ",") loop
         Result.Decl.Names.Append (Expect_Identifier (State).Lexeme);
      end loop;
      Parse_Object_Declaration_Tail (State, Result.Decl, Allow_Constant => False);
      Semi := Expect_Statement_Terminator (State);
      Result.Decl.Span := CM.Join (Start.Span, Semi);
      Result.Span := Result.Decl.Span;
      return Result;
   end Parse_Var_Declaration_Statement;

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
      Semi   : FT.Source_Span;
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
      Semi := Expect_Statement_Terminator (State);
      Result.Destructure.Span := CM.Join (Start.Span, Semi);
      Result.Span := Result.Destructure.Span;
      return Result;
   end Parse_Destructure_Declaration_Statement;

   function Direct_Name_Expr
     (Name : FT.UString;
      Span : FT.Source_Span) return CM.Expr_Access
   is
      Result : constant CM.Expr_Access := New_Expr;
   begin
      Result.Kind := CM.Expr_Ident;
      Result.Name := Name;
      Result.Span := Span;
      return Result;
   end Direct_Name_Expr;

   procedure Append_Parsed_Statement
     (Statements : in out CM.Statement_Access_Vectors.Vector;
      Item       : CM.Statement_Access)
   is
      Decl_Stmt : CM.Statement_Access;
   begin
      if Item /= null
        and then Item.Kind in CM.Stmt_Receive | CM.Stmt_Try_Receive
        and then not Item.Decl.Names.Is_Empty
      then
         Decl_Stmt := new CM.Statement;
         Decl_Stmt.Kind := CM.Stmt_Object_Decl;
         Decl_Stmt.Decl := Item.Decl;
         Decl_Stmt.Span := Item.Decl.Span;
         Item.Decl := (others => <>);
         Statements.Append (Decl_Stmt);
      end if;
      Statements.Append (Item);
   end Append_Parsed_Statement;

   function Case_Choice_Is_Literal
     (Expr : CM.Expr_Access) return Boolean is
   begin
      if Expr = null then
         return False;
      elsif Expr.Kind in
        CM.Expr_Int
        | CM.Expr_Bool
        | CM.Expr_String
        | CM.Expr_Enum_Literal
        | CM.Expr_Ident
        | CM.Expr_Select
      then
         --  Idents/selects are only provisional here so enum literals and
         --  imported constant names can parse. Resolve rechecks staticness.
         return True;
      elsif Expr.Kind in CM.Expr_Call | CM.Expr_Apply
        and then Natural (Expr.Args.Length) = 1
      then
         return Case_Choice_Is_Literal (Expr.Args (Expr.Args.First_Index));
      elsif Expr.Kind in CM.Expr_Conversion | CM.Expr_Annotated and then Expr.Inner /= null then
         return Case_Choice_Is_Literal (Expr.Inner);
      elsif Expr.Kind = CM.Expr_Unary and then Expr.Inner /= null then
         return (FT.To_String (Expr.Operator) = "+"
                 or else FT.To_String (Expr.Operator) = "-")
           and then Expr.Inner.Kind = CM.Expr_Int;
      end if;
      return False;
   end Case_Choice_Is_Literal;

   function Parse_Indented_Statement_Sequence
     (State    : in out Parser_State;
      Context  : String;
      Anchor   : FT.Source_Span) return CM.Statement_Access_Vectors.Vector
   is
      Result      : CM.Statement_Access_Vectors.Vector;
      Next_Token  : FL.Token;
   begin
      if not Match_Indent (State) then
         Next_Token := Next (State);
         if Current (State).Kind in FL.Dedent | FL.End_Of_File
           or else Starts_On_Later_Line (Anchor, Current (State).Span)
           or else
             (Current (State).Span = Anchor
              and then
                (Next_Token.Kind in FL.Dedent | FL.End_Of_File
                 or else Starts_On_Later_Line (Anchor, Next_Token.Span)))
         then
            return Result;
         end if;
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path_String (State),
               Span    => Current (State).Span,
               Message => "expected indented block",
               Note    => Context));
      end if;
      loop
         exit when Current (State).Kind in FL.Dedent | FL.End_Of_File;
         Append_Parsed_Statement (Result, Parse_Statement (State));
      end loop;
      Require_Dedent (State, Context);
      return Result;
   end Parse_Indented_Statement_Sequence;

   function Empty_Body_Suite
     (State  : Parser_State;
      Anchor : FT.Source_Span) return Boolean
   is
   begin
      return Current (State).Kind = FL.End_Of_File
        or else Starts_On_Later_Line (Anchor, Current (State).Span);
   end Empty_Body_Suite;

   function Parse_Return_Statement
     (State : in out Parser_State) return CM.Statement_Access
   is
      Start  : constant FL.Token := Expect (State, "return");
      Result : constant CM.Statement_Access := new CM.Statement;
      Semi   : FT.Source_Span;
   begin
      Result.Kind := CM.Stmt_Return;
      if State.Return_Value_Allowed and then Match_Indent (State) then
         Result.Value := Parse_Expression (State);
         Semi := Expect_Statement_Terminator (State);
         Require_Dedent
           (State,
            "multiline `return` expressions must dedent back to the enclosing statement level");
         Result.Span := CM.Join (Start.Span, Semi);
         return Result;
      elsif Current (State).Lexeme /= FT.To_UString (";")
        and then (State.Return_Value_Allowed
                  or else Current (State).Kind = FL.End_Of_File
                  or else not Starts_On_Later_Line (Start.Span, Current (State).Span))
      then
         Result.Value := Parse_Expression (State);
      end if;
      Semi := Expect_Statement_Terminator (State);
      Result.Span := CM.Join (Start.Span, Semi);
      return Result;
   end Parse_Return_Statement;

   function Parse_If_Statement
     (State : in out Parser_State) return CM.Statement_Access
   is
      Start       : constant FL.Token := Expect (State, "if");
      Result      : constant CM.Statement_Access := new CM.Statement;
      Elsif_Part  : CM.Elsif_Part;

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
      Result.Then_Stmts :=
        Parse_Indented_Statement_Sequence
          (State,
           "if branches require an indented body",
           Result.Condition.Span);

      if Current_Lower (State) = "elsif" then
         Reject_Removed_Source_Spelling
           (State,
            Lexeme  => "elsif",
            Context => "conditional chains");
      end if;

      while Current_Lower (State) = "else"
        and then FT.Lowercase (FT.To_String (Next (State).Lexeme)) = "if"
        and then Current (State).Span.Start_Pos.Line = Next (State).Span.Start_Pos.Line
      loop
         Advance (State);
         Require (State, "if");
         Elsif_Part.Condition := Parse_Expression (State);
         Elsif_Part.Statements :=
           Parse_Indented_Statement_Sequence
             (State,
              "`else if` branches require an indented body",
              Elsif_Part.Condition.Span);
         Elsif_Part.Span :=
           (if Elsif_Part.Statements.Is_Empty then Elsif_Part.Condition.Span
            else CM.Join
              (Elsif_Part.Condition.Span,
               Elsif_Part.Statements (Elsif_Part.Statements.Last_Index).Span));
         Result.Elsifs.Append (Elsif_Part);
         if Current_Lower (State) = "elsif" then
            Reject_Removed_Source_Spelling
              (State,
               Lexeme  => "elsif",
               Context => "conditional chains");
         end if;
      end loop;

      if Current_Lower (State) = "else" then
         declare
            Else_Token : constant FL.Token := Expect (State, "else");
         begin
            Result.Has_Else := True;
            Result.Else_Stmts :=
              Parse_Indented_Statement_Sequence
                (State,
                 "`else` branches require an indented body",
                 Else_Token.Span);
         end;
         Collapse_Wrapped_Else_If;
      end if;

      Result.Span :=
        CM.Join
          (Start.Span,
           (if Result.Has_Else
            then Suite_End_Span (Result.Else_Stmts, Result.Condition.Span)
            elsif not Result.Elsifs.Is_Empty
            then Result.Elsifs (Result.Elsifs.Last_Index).Span
            else Suite_End_Span (Result.Then_Stmts, Result.Condition.Span)));
      return Result;
   end Parse_If_Statement;

   function Parse_Case_Statement
     (State : in out Parser_State) return CM.Statement_Access
   is
      Start      : constant FL.Token := Expect (State, "case");
      Result     : constant CM.Statement_Access := new CM.Statement;
      Arm        : CM.Case_Arm;
      Arm_Start  : FL.Token;
      Saw_Others : Boolean := False;
   begin
      Result.Kind := CM.Stmt_Case;
      Result.Case_Expr := Parse_Expression (State);
      Require_Indent (State, "case arms must be indented under `case`");

      loop
         exit when Current (State).Kind in FL.Dedent | FL.End_Of_File;
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
               Reject_Removed_Source_Spelling
                 (State,
                  Lexeme  => "..",
                  Context => "source ranges");
            elsif Current_Lower (State) = "to" then
               Reject_Unsupported
                 (State,
                  "range case choices are outside the current PR11.2 parser-completeness subset");
            elsif not Case_Choice_Is_Literal (Arm.Choice) then
               Reject_Unsupported
                 (State,
                  "case arms currently support exactly one static boolean, integer, string, enum, Character, or converted binary literal choice per arm");
            end if;
         end if;

         Arm.Statements :=
           Parse_Indented_Statement_Sequence
             (State,
              "case arms require an indented body",
              (if Arm.Is_Others then Arm_Start.Span else Arm.Choice.Span));
         Arm.Span :=
           CM.Join
             (Arm_Start.Span,
              Suite_End_Span (Arm.Statements, Arm_Start.Span));
         Result.Case_Arms.Append (Arm);

         if Saw_Others and then Current (State).Kind not in FL.Dedent | FL.End_Of_File then
            Raise_Diag
              (CM.Source_Frontend_Error
                 (Path    => Path_String (State),
                  Span    => Current (State).Span,
                  Message => "`when others` must be the final case arm"));
         end if;
      end loop;

      if Result.Case_Arms.Is_Empty
        or else not Result.Case_Arms (Result.Case_Arms.Last_Index).Is_Others
      then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path_String (State),
               Span    => Current (State).Span,
               Message => "case statements currently require a final `when others` arm"));
      end if;

      Require_Dedent (State, "case arms must align under `case`");
      Result.Span :=
        CM.Join
          (Start.Span,
           (if Result.Case_Arms.Is_Empty
            then Result.Case_Expr.Span
            else Result.Case_Arms (Result.Case_Arms.Last_Index).Span));
      return Result;
   end Parse_Case_Statement;

   function Parse_Match_Statement
     (State : in out Parser_State) return CM.Statement_Access
   is
      Start    : constant FL.Token := Expect (State, "match");
      Result   : constant CM.Statement_Access := new CM.Statement;
      Arm      : CM.Match_Arm;
      Arm_Start : FL.Token;
      Binder   : FL.Token;
      Saw_Ok   : Boolean := False;
      Saw_Fail : Boolean := False;
   begin
      Result.Kind := CM.Stmt_Match;
      Result.Match_Expr := Parse_Expression (State);
      Require_Indent (State, "match arms must be indented under `match`");

      loop
         exit when Current (State).Kind in FL.Dedent | FL.End_Of_File;
         Arm := (others => <>);
         Arm_Start := Expect (State, "when");

         if Current_Lower (State) = "ok" then
            if Saw_Ok then
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path_String (State),
                     Span    => Current (State).Span,
                     Message => "match statements require exactly one `when ok (...)` arm"));
            end if;
            Saw_Ok := True;
            Arm.Kind := CM.Match_Arm_Ok;
            Advance (State);
         elsif Current_Lower (State) = "fail" then
            if Saw_Fail then
               Raise_Diag
                 (CM.Source_Frontend_Error
                    (Path    => Path_String (State),
                     Span    => Current (State).Span,
                     Message => "match statements require exactly one `when fail (...)` arm"));
            end if;
            Saw_Fail := True;
            Arm.Kind := CM.Match_Arm_Fail;
            Advance (State);
         else
            Raise_Diag
              (CM.Source_Frontend_Error
                 (Path    => Path_String (State),
                  Span    => Current (State).Span,
                  Message => "expected `ok` or `fail` in match arm"));
         end if;

         Require (State, "(");
         Binder := Expect_Identifier (State);
         Arm.Binder := Binder.Lexeme;
         Require (State, ")");
         Arm.Statements :=
           Parse_Indented_Statement_Sequence
             (State,
              "match arms require an indented body",
              Binder.Span);
         Arm.Span := CM.Join (Arm_Start.Span, Suite_End_Span (Arm.Statements, Binder.Span));
         Result.Match_Arms.Append (Arm);
      end loop;

      if Natural (Result.Match_Arms.Length) /= 2
        or else not Saw_Ok
        or else not Saw_Fail
      then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path_String (State),
               Span    => Current (State).Span,
               Message => "match statements require exactly one `when ok (...)` arm and one `when fail (...)` arm"));
      end if;

      Require_Dedent (State, "match arms must align under `match`");
      Result.Span :=
        CM.Join
          (Start.Span,
           (if Result.Match_Arms.Is_Empty
            then Result.Match_Expr.Span
            else Result.Match_Arms (Result.Match_Arms.Last_Index).Span));
      return Result;
   end Parse_Match_Statement;

   function Parse_While_Statement
     (State : in out Parser_State) return CM.Statement_Access
   is
      Start  : constant FL.Token := Expect (State, "while");
      Result : constant CM.Statement_Access := new CM.Statement;
   begin
      Result.Kind := CM.Stmt_While;
      Result.Condition := Parse_Expression (State);
      Result.Body_Stmts :=
        Parse_Indented_Statement_Sequence
          (State,
           "`while` requires an indented body",
           Result.Condition.Span);
      Result.Span := CM.Join (Start.Span, Suite_End_Span (Result.Body_Stmts, Result.Condition.Span));
      return Result;
   end Parse_While_Statement;

   function Parse_For_Statement
     (State : in out Parser_State) return CM.Statement_Access
   is
      Start  : constant FL.Token := Expect (State, "for");
      Result : constant CM.Statement_Access := new CM.Statement;
   begin
      if Current_Lower (State) = "reverse" then
         Raise_Diag
           (CM.Unsupported_Source_Construct
              (Path    => Path_String (State),
               Span    => Current (State).Span,
               Message => "`reverse for` loops are outside the current PR11.8d subset"));
      end if;

      Result.Kind := CM.Stmt_For;
      Result.Loop_Var := Expect_Identifier (State).Lexeme;
      if Match (State, "of") then
         if Current_Lower (State) = "reverse" then
            Raise_Diag
              (CM.Unsupported_Source_Construct
                 (Path    => Path_String (State),
                  Span    => Current (State).Span,
                  Message => "`reverse for` loops are outside the current PR11.8d subset"));
         end if;
         Result.Loop_Iterable := Parse_Expression (State);
      else
         Require (State, "in");
         if Current_Lower (State) = "reverse" then
            Raise_Diag
              (CM.Unsupported_Source_Construct
                 (Path    => Path_String (State),
                  Span    => Current (State).Span,
                  Message => "`reverse for` loops are outside the current PR11.8d subset"));
         end if;
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
      end if;

      declare
         Anchor_Span : constant FT.Source_Span :=
           (if Result.Loop_Iterable /= null
            then Result.Loop_Iterable.Span
            else Result.Loop_Range.Span);
      begin
         Result.Body_Stmts :=
           Parse_Indented_Statement_Sequence
             (State,
              "`for` requires an indented body",
              Anchor_Span);
         Result.Span :=
           CM.Join
             (Start.Span,
              Suite_End_Span (Result.Body_Stmts, Anchor_Span));
      end;
      return Result;
   end Parse_For_Statement;

   function Parse_Loop_Statement
     (State : in out Parser_State) return CM.Statement_Access
   is
      Start  : constant FL.Token := Expect (State, "loop");
      Result : constant CM.Statement_Access := new CM.Statement;
   begin
      Result.Kind := CM.Stmt_Loop;
      Result.Body_Stmts :=
        Parse_Indented_Statement_Sequence
          (State,
           "`loop` requires an indented body",
           Start.Span);
      Result.Span := CM.Join (Start.Span, Suite_End_Span (Result.Body_Stmts, Start.Span));
      return Result;
   end Parse_Loop_Statement;

   function Parse_Exit_Statement
     (State : in out Parser_State) return CM.Statement_Access
   is
      Start  : constant FL.Token := Expect (State, "exit");
      Result : constant CM.Statement_Access := new CM.Statement;
      Semi   : FT.Source_Span;
   begin
      if Current (State).Kind in FL.Identifier | FL.Keyword
        and then Current_Lower (State) /= "when"
        and then Current (State).Lexeme /= FT.To_UString (";")
      then
         Reject_Removed_Source_Construct (State, "named exit");
      end if;

      Result.Kind := CM.Stmt_Exit;
      if Match (State, "when") then
         Result.Condition := Parse_Expression (State);
      end if;
      Semi := Expect_Statement_Terminator (State);
      Result.Span := CM.Join (Start.Span, Semi);
      return Result;
   end Parse_Exit_Statement;

   function Parse_Send_Statement
     (State : in out Parser_State) return CM.Statement_Access
   is
      Start  : constant FL.Token := Expect (State, "send");
      Result : constant CM.Statement_Access := new CM.Statement;
      Semi   : FT.Source_Span;
   begin
      Result.Kind := CM.Stmt_Send;
      Result.Channel_Name := Parse_Name_Expression (State);
      Require (State, ",");
      Result.Value := Parse_Expression (State);
      if Current (State).Lexeme = FT.To_UString (",") then
         Require (State, ",");
         Result.Success_Var := Parse_Name_Expression (State);
      end if;
      Semi := Expect_Statement_Terminator (State);
      Result.Span := CM.Join (Start.Span, Semi);
      return Result;
   end Parse_Send_Statement;

   function Parse_Receive_Statement
     (State : in out Parser_State) return CM.Statement_Access
   is
      Start  : constant FL.Token := Expect (State, "receive");
      Result : constant CM.Statement_Access := new CM.Statement;
      Name   : FL.Token;
      Semi   : FT.Source_Span;
   begin
      Result.Kind := CM.Stmt_Receive;
      Result.Channel_Name := Parse_Name_Expression (State);
      Require (State, ",");
      if Current (State).Kind in FL.Identifier | FL.Keyword
        and then Next (State).Lexeme = FT.To_UString (":")
      then
         Name := Expect_Identifier (State);
         Require (State, ":");
         Result.Decl.Names.Append (Name.Lexeme);
         Result.Decl.Decl_Type := Parse_Object_Type (State);
         Result.Decl.Span := CM.Join (Name.Span, Result.Decl.Decl_Type.Span);
         Result.Target := Direct_Name_Expr (Name.Lexeme, Name.Span);
      else
         Result.Target := Parse_Expression (State);
      end if;
      Semi := Expect_Statement_Terminator (State);
      Result.Span := CM.Join (Start.Span, Semi);
      return Result;
   end Parse_Receive_Statement;

   function Parse_Try_Send_Statement
     (State : in out Parser_State) return CM.Statement_Access
   is
      Start  : constant FL.Token := Expect (State, "try_send");
      Result : constant CM.Statement_Access := new CM.Statement;
      Semi   : FT.Source_Span;
   begin
      Result.Kind := CM.Stmt_Try_Send;
      Result.Channel_Name := Parse_Name_Expression (State);
      Require (State, ",");
      Result.Value := Parse_Expression (State);
      Require (State, ",");
      Result.Success_Var := Parse_Name_Expression (State);
      Semi := Expect_Statement_Terminator (State);
      Result.Span := CM.Join (Start.Span, Semi);
      return Result;
   end Parse_Try_Send_Statement;

   function Parse_Try_Receive_Statement
     (State : in out Parser_State) return CM.Statement_Access
   is
      Start  : constant FL.Token := Expect (State, "try_receive");
      Result : constant CM.Statement_Access := new CM.Statement;
      Name   : FL.Token;
      Semi   : FT.Source_Span;
   begin
      Result.Kind := CM.Stmt_Try_Receive;
      Result.Channel_Name := Parse_Name_Expression (State);
      Require (State, ",");
      if Current (State).Kind in FL.Identifier | FL.Keyword
        and then Next (State).Lexeme = FT.To_UString (":")
      then
         Name := Expect_Identifier (State);
         Require (State, ":");
         Result.Decl.Names.Append (Name.Lexeme);
         Result.Decl.Decl_Type := Parse_Object_Type (State);
         Result.Decl.Has_Implicit_Default_Init := True;
         Result.Decl.Span := CM.Join (Name.Span, Result.Decl.Decl_Type.Span);
         Result.Target := Direct_Name_Expr (Name.Lexeme, Name.Span);
      else
         Result.Target := Parse_Expression (State);
      end if;
      Require (State, ",");
      Result.Success_Var := Parse_Name_Expression (State);
      Semi := Expect_Statement_Terminator (State);
      Result.Span := CM.Join (Start.Span, Semi);
      return Result;
   end Parse_Try_Receive_Statement;

   function Parse_Delay_Statement
     (State : in out Parser_State) return CM.Statement_Access
   is
      Start  : constant FL.Token := Expect (State, "delay");
      Result : constant CM.Statement_Access := new CM.Statement;
      Semi   : FT.Source_Span;
   begin
      if Current_Lower (State) = "until" then
         Reject_Unsupported
           (State,
            "absolute `delay until` is outside the current PR08.1 concurrency subset");
      end if;
      Result.Kind := CM.Stmt_Delay;
      Result.Value := Parse_Expression (State);
      Semi := Expect_Statement_Terminator (State);
      Result.Span := CM.Join (Start.Span, Semi);
      return Result;
   end Parse_Delay_Statement;

   function Parse_Select_Statement
     (State : in out Parser_State) return CM.Statement_Access
   is
      Start     : constant FL.Token := Expect (State, "select");
      Result    : constant CM.Statement_Access := new CM.Statement;
      New_Arm   : CM.Select_Arm;
   begin
      Result.Kind := CM.Stmt_Select;

      loop
         Require_Indent (State, "select arms must be indented under `select` or `or`");
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
               New_Arm.Channel_Data.Statements :=
                 Parse_Indented_Statement_Sequence
                   (State,
                    "select channel arms require an indented body",
                    New_Arm.Channel_Data.Channel_Name.Span);
               New_Arm.Channel_Data.Span :=
                 CM.Join
                   (Arm_Start.Span,
                    Suite_End_Span
                      (New_Arm.Channel_Data.Statements,
                       New_Arm.Channel_Data.Channel_Name.Span));
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
               New_Arm.Delay_Data.Statements :=
                 Parse_Indented_Statement_Sequence
                   (State,
                    "select delay arms require an indented body",
                    New_Arm.Delay_Data.Duration_Expr.Span);
               New_Arm.Delay_Data.Span :=
                 CM.Join
                   (Arm_Start.Span,
                    Suite_End_Span
                      (New_Arm.Delay_Data.Statements,
                       New_Arm.Delay_Data.Duration_Expr.Span));
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
         Require_Dedent
           (State,
            "select arms must dedent back to the surrounding `select` level");
         exit when not Match (State, "or");
      end loop;

      Result.Span :=
        CM.Join
          (Start.Span,
           (if Result.Arms.Is_Empty then Start.Span else Result.Arms (Result.Arms.Last_Index).Span));
      return Result;
   end Parse_Select_Statement;

   function Parse_Simple_Statement
      (State : in out Parser_State) return CM.Statement_Access
   is
      Start_Expr : constant CM.Expr_Access := Parse_Expression (State);
      Result     : constant CM.Statement_Access := new CM.Statement;
      Semi       : FT.Source_Span;
   begin
      if Match (State, "=") then
         Result.Kind := CM.Stmt_Assign;
         Result.Target := Start_Expr;
         Result.Value := Parse_Expression (State);
         Semi := Expect_Statement_Terminator (State);
         Result.Span := CM.Join (Start_Expr.Span, Semi);
         return Result;
      end if;

      Result.Kind := CM.Stmt_Call;
      Result.Call := Start_Expr;
      Semi := Expect_Statement_Terminator (State);
      Result.Span := CM.Join (Start_Expr.Span, Semi);
      return Result;
   end Parse_Simple_Statement;

   function Parse_Print_Statement
     (State : in out Parser_State) return CM.Statement_Access
   is
      Print_Tok : constant FL.Token := Expect (State, "print");
      Open_Tok  : constant FL.Token := Expect (State, "(");
      Result    : constant CM.Statement_Access := new CM.Statement;
      Call_Expr : constant CM.Expr_Access := New_Expr;
      Ender     : FL.Token;
      Semi      : FT.Source_Span;
   begin
      Result.Kind := CM.Stmt_Call;
      Call_Expr.Kind := CM.Expr_Call;
      Call_Expr.Callee := Direct_Name_Expr (Print_Tok.Lexeme, Print_Tok.Span);
      if FT.To_String (Current (State).Lexeme) /= ")" then
         Call_Expr.Args.Append (Parse_Expression (State));
      end if;
      Ender := Expect (State, ")");
      Call_Expr.Has_Call_Span := True;
      Call_Expr.Call_Span := CM.Join (Open_Tok.Span, Ender.Span);
      Call_Expr.Span := CM.Join (Print_Tok.Span, Ender.Span);
      Result.Call := Call_Expr;
      Semi := Expect_Statement_Terminator (State);
      Result.Span := CM.Join (Print_Tok.Span, Semi);
      return Result;
   end Parse_Print_Statement;

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
         Reject_Removed_Source_Construct
           (State,
            "declare block",
            "use suite-local `var` declarations in the enclosing executable body");
      elsif Lower = "exit" then
         return Parse_Exit_Statement (State);
      elsif Lower = "return" then
         return Parse_Return_Statement (State);
      elsif Lower = "case" then
         return Parse_Case_Statement (State);
      elsif Lower = "match" then
         return Parse_Match_Statement (State);
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
      elsif Lower = "var" then
         return Parse_Var_Declaration_Statement (State);
      elsif Lower = "print" then
         return Parse_Print_Statement (State);
      elsif Lower in "begin" | "end" | "then" then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path_String (State),
               Span    => Current (State).Span,
               Message =>
                 "legacy block delimiter `" & Lower
                 & "` is not allowed; covered blocks are closed by indentation"));
      elsif Lower = "null" then
         Reject_Removed_Source_Construct (State, "null statement");
      elsif Lower in "raise" | "accept" then
         Reject_Unsupported
           (State,
            "statement form `" & Lower & "` is outside the current PR08.1 concurrency subset");
      elsif Lower = "goto" then
         Reject_Removed_Source_Construct (State, "goto");
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
            Reject_Removed_Source_Construct (State, "named loop or statement label");
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
            Subtype_Expr : constant CM.Expr_Access := Parse_Type_Target_Expr (State);
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

   function Parse_Array_Literal
     (State : in out Parser_State) return CM.Expr_Access
   is
      Start  : constant FL.Token := Expect (State, "[");
      Result : constant CM.Expr_Access := New_Expr;
      Ender  : FL.Token;
   begin
      Result.Kind := CM.Expr_Array_Literal;
      if FT.To_String (Current (State).Lexeme) /= "]" then
         loop
            Result.Elements.Append (Parse_Expression (State));
            exit when not Match (State, ",");
         end loop;
      end if;
      Ender := Expect (State, "]");
      Result.Span := CM.Join (Start.Span, Ender.Span);
      return Result;
   end Parse_Array_Literal;

   function Parse_Allocator
     (State : in out Parser_State) return CM.Expr_Access
   is
   begin
      Reject_Removed_Source_Construct
        (State,
         "new",
         "PR11.8e removes explicit allocation from the source surface");
      return null;
   end Parse_Allocator;

   function Parse_Primary
     (State : in out Parser_State) return CM.Expr_Access
   is
      Token  : constant FL.Token := Current (State);
      Result : constant CM.Expr_Access := New_Expr;
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
         Result.Kind := CM.Expr_String;
         declare
            Literal_Text : constant String := FT.To_String (Token.Lexeme);
            Inner_Text   : constant String :=
              Literal_Text (Literal_Text'First + 1 .. Literal_Text'Last - 1);
            Quote        : constant Character := Character'Val (34);
         begin
            if Inner_Text = String'(1 => Quote) then
               Result.Text :=
                 FT.To_UString
                   (Quote
                    & String'(1 => Quote, 2 => Quote)
                    & Quote);
            else
               Result.Text := FT.To_UString (Quote & Inner_Text & Quote);
            end if;
         end;
         Result.Span := Token.Span;
         return Result;
      elsif Lower = "new" then
         return Parse_Allocator (State);
      elsif Lower = "binary" then
         declare
            Target  : constant CM.Expr_Access := Parse_Type_Target_Expr (State);
            Wrapped : constant CM.Expr_Access := New_Expr;
            Ender   : FL.Token;
         begin
            Require (State, "(");
            Wrapped.Kind := CM.Expr_Conversion;
            Wrapped.Target := Target;
            Wrapped.Inner := Parse_Expression (State);
            Ender := Expect (State, ")");
            Wrapped.Span := CM.Join (Token.Span, Ender.Span);
            return Wrapped;
         end;
      elsif Lower = "some" then
         declare
            Ender : FL.Token;
         begin
            Advance (State);
            Require (State, "(");
            Result.Kind := CM.Expr_Some;
            Result.Inner := Parse_Expression (State);
            Ender := Expect (State, ")");
            Result.Span := CM.Join (Token.Span, Ender.Span);
            return Result;
         end;
      elsif Token.Kind = FL.Identifier or else Token.Kind = FL.Keyword then
         if Lower = "declare" then
            Reject_Removed_Source_Construct (State, "declare_expression");
         elsif Lower = "null" then
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
         elsif Lower = "none" then
            Advance (State);
            Result.Kind := CM.Expr_None;
            Result.Name := Token.Lexeme;
            Result.Span := Token.Span;
            return Result;
         end if;
         return Parse_Name_Expression (State);
      elsif FT.To_String (Token.Lexeme) = "(" then
         return Parse_Parenthesized_Like (State);
      elsif FT.To_String (Token.Lexeme) = "[" then
         return Parse_Array_Literal (State);
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
      elsif Current_Lower (State) = "try" then
         Token := Expect (State, "try");
         Result := New_Expr;
         Result.Kind := CM.Expr_Try;
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

   function Parse_Shift_Expr
     (State : in out Parser_State) return CM.Expr_Access
   is
      Result      : CM.Expr_Access := Parse_Simple_Expr (State);
      Right       : CM.Expr_Access;
      Next_Result : CM.Expr_Access;
   begin
      while FT.To_String (Current (State).Lexeme) in "<<" | ">>" loop
         declare
            Op : constant FT.UString := Current (State).Lexeme;
         begin
            Advance (State);
            Right := Parse_Simple_Expr (State);
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
   end Parse_Shift_Expr;

   function Parse_Relation
     (State : in out Parser_State) return CM.Expr_Access
   is
      Result : constant CM.Expr_Access := Parse_Shift_Expr (State);
      Lower  : constant String := FT.To_String (Current (State).Lexeme);
      Right  : CM.Expr_Access;
      Next_Result : CM.Expr_Access;
   begin
      if Lower in "==" | "!=" | "<" | "<=" | ">" | ">=" then
         Advance (State);
         Right := Parse_Shift_Expr (State);
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

   function Match_Logical_Operator
     (State         : in out Parser_State;
      Operator      : out FT.UString;
      Operator_Span : out FT.Source_Span) return Boolean
   is
      Lower : constant String := Current_Lower (State);
   begin
      if Lower = "and"
        and then FT.Lowercase (FT.To_String (Next (State).Lexeme)) = "then"
      then
         Operator_Span := CM.Join (Current (State).Span, Next (State).Span);
         Advance (State);
         Advance (State);
         Operator := FT.To_UString ("and then");
         return True;
      elsif Lower = "or"
        and then FT.Lowercase (FT.To_String (Next (State).Lexeme)) = "else"
      then
         Operator_Span := CM.Join (Current (State).Span, Next (State).Span);
         Advance (State);
         Advance (State);
         Operator := FT.To_UString ("or else");
         return True;
      elsif Lower in "and" | "or" | "xor" then
         Operator_Span := Current (State).Span;
         Operator := FT.To_UString (Lower);
         Advance (State);
         return True;
      end if;
      Operator_Span := FT.Null_Span;
      return False;
   end Match_Logical_Operator;

   function Parse_Logical_Expr
     (State : in out Parser_State) return CM.Expr_Access
   is
      Result         : CM.Expr_Access := Parse_Relation (State);
      Right          : CM.Expr_Access;
      Next_Result    : CM.Expr_Access;
      Operator       : FT.UString;
      Chain_Operator : FT.UString := FT.To_UString ("");
      Operator_Span  : FT.Source_Span := FT.Null_Span;
   begin
      while Match_Logical_Operator (State, Operator, Operator_Span) loop
         if Chain_Operator = FT.To_UString ("") then
            Chain_Operator := Operator;
         elsif Operator /= Chain_Operator then
            Raise_Diag
              (CM.Source_Frontend_Error
                 (Path    => Path_String (State),
                  Span    => Operator_Span,
                  Message => "mixed logical operators require parentheses"));
         end if;
         Right := Parse_Relation (State);
         Next_Result := New_Expr;
         Next_Result.Kind := CM.Expr_Binary;
         Next_Result.Operator := Operator;
         Next_Result.Left := Result;
         Next_Result.Right := Right;
         Next_Result.Span := CM.Join (Result.Span, Right.Span);
         Result := Next_Result;
      end loop;
      return Result;
   end Parse_Logical_Expr;

   function Parse_Expression
     (State : in out Parser_State) return CM.Expr_Access is
   begin
      return Parse_Logical_Expr (State);
   end Parse_Expression;

   function Parse_Type_Target_Expr
     (State : in out Parser_State) return CM.Expr_Access
   is
      Result : constant CM.Expr_Access := New_Expr;
      Spec   : CM.Type_Spec;
   begin
      if Current_Lower (State) = "binary"
        or else Current_Lower (State) = "optional"
        or else (Current_Lower (State) = "array"
                 and then FT.To_String (Next (State).Lexeme) /= "(")
        or else FT.To_String (Current (State).Lexeme) = "("
      then
         Spec := Parse_Object_Type (State);
         Result.Kind := CM.Expr_Subtype_Indication;
         Result.Name := Type_Spec_Internal_Name (Spec);
         Result.Type_Name := Result.Name;
         Result.Subtype_Spec := new CM.Type_Spec'(Spec);
         Result.Span := Spec.Span;
         return Result;
      end if;
      return Parse_Name_Expression (State);
   end Parse_Type_Target_Expr;

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
               if FT.Lowercase (FT.To_String (Selector.Lexeme)) = "all" then
                  Reject_Removed_Source_Spelling
                    (State,
                     ".all",
                     "postfix selectors");
               elsif FT.Lowercase (FT.To_String (Selector.Lexeme)) = "access" then
                  Reject_Removed_Source_Spelling
                    (State,
                     ".access",
                     "postfix selectors");
               end if;
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
                  declare
                     Item : constant CM.Expr_Access := Parse_Expression (State);
                  begin
                     Next_Result.Args.Append (Item);
                     if Current_Lower (State) = "to" then
                        Require_Range_Keyword (State);
                        Next_Result.Args.Append (Parse_Expression (State));
                        exit;
                     end if;
                  end;
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
      Result                   : CM.Package_Item;
      Start                    : constant FT.Source_Span := Current (State).Span;
      Saved_Return_Value_Flag  : constant Boolean := State.Return_Value_Allowed;
      Saw_Statements           : Boolean := False;
      Suite_Already_Indented   : Boolean := False;
   begin
      Result.Kind := CM.Item_Subprogram;
      Result.Subp_Data.Is_Public := Is_Public;
      Result.Subp_Data.Spec := Parse_Subprogram_Spec (State);
      if not Result.Subp_Data.Spec.Has_Return_Type
        and then Current (State).Kind = FL.Indent
        and then Next (State).Kind in FL.Identifier | FL.Keyword
        and then FT.Lowercase (FT.To_String (Next (State).Lexeme)) = "returns"
      then
         Advance (State);
         Require_Returns_Keyword (State);
         Result.Subp_Data.Spec.Has_Return_Type := True;
         Result.Subp_Data.Spec.Return_Type := Parse_Return_Type (State);
         Result.Subp_Data.Spec.Return_Is_Access_Def :=
           Result.Subp_Data.Spec.Return_Type.Kind = CM.Type_Spec_Access_Def;
         Result.Subp_Data.Spec.Span :=
           CM.Join (Result.Subp_Data.Spec.Span, Result.Subp_Data.Spec.Return_Type.Span);
         Suite_Already_Indented := True;
      else
         if Match_Indent (State) then
            Suite_Already_Indented := True;
         elsif Empty_Body_Suite (State, Result.Subp_Data.Spec.Span)
         then
            Suite_Already_Indented := False;
         else
            Raise_Diag
              (CM.Source_Frontend_Error
                 (Path    => Path_String (State),
                  Span    => Current (State).Span,
                  Message => "expected indented block",
                  Note    => "subprogram bodies require an indented suite after the declaration line"));
         end if;
      end if;
      State.Return_Value_Allowed := Result.Subp_Data.Spec.Has_Return_Type;
      if Suite_Already_Indented then
         while Current (State).Kind not in FL.Dedent | FL.End_Of_File loop
            if not Saw_Statements
              and then Current (State).Kind in FL.Identifier | FL.Keyword
              and then Next (State).Lexeme = FT.To_UString (":")
            then
               if Current_Lower (State) = "var" then
                  Reject_Statement_Local_Var_Outside_Statements (State);
               end if;
               Result.Subp_Data.Declarations.Append
                 (Parse_Body_Local_Object_Declaration (State));
            else
               Saw_Statements := True;
                  Append_Parsed_Statement (Result.Subp_Data.Statements, Parse_Statement (State));
            end if;
         end loop;
      end if;
      State.Return_Value_Allowed := Saved_Return_Value_Flag;
      if Suite_Already_Indented then
         Require_Dedent
           (State,
            "subprogram bodies must dedent back to the enclosing declaration level");
      end if;
      Result.Subp_Data.Span :=
        CM.Join
          (Start,
           (if not Result.Subp_Data.Statements.Is_Empty
            then Suite_End_Span
              (Result.Subp_Data.Statements, Result.Subp_Data.Spec.Span)
            elsif not Result.Subp_Data.Declarations.Is_Empty
            then Result.Subp_Data.Declarations (Result.Subp_Data.Declarations.Last_Index).Span
            else Result.Subp_Data.Spec.Span));
      return Result;
   end Parse_Subprogram_Body;

   function Parse_Task_Declaration
     (State     : in out Parser_State;
      Is_Public : Boolean) return CM.Package_Item
   is
      Result                 : CM.Package_Item;
      Start                  : constant FT.Source_Span := Current (State).Span;
      Saw_Statements         : Boolean := False;
      Suite_Already_Indented : Boolean := False;

      procedure Parse_Task_Channel_Clause is
         Clause_Kind : constant String := Current_Lower (State);
      begin
         if Clause_Kind = "sends" then
            Advance (State);
            Result.Task_Data.Has_Send_Contract := True;
            Result.Task_Data.Send_Contracts.Append (Parse_Name_Expression (State));
         elsif Clause_Kind = "receives" then
            Advance (State);
            Result.Task_Data.Has_Receive_Contract := True;
            Result.Task_Data.Receive_Contracts.Append (Parse_Name_Expression (State));
         else
            Raise_Diag
              (CM.Source_Frontend_Error
                 (Path    => Path_String (State),
                  Span    => Current (State).Span,
                  Message => "expected `sends` or `receives` in task direction clauses"));
         end if;

         while Match (State, ",") loop
            if Current_Lower (State) = "sends" or else Current_Lower (State) = "receives" then
               exit;
            elsif Clause_Kind = "sends" then
               Result.Task_Data.Send_Contracts.Append (Parse_Name_Expression (State));
            else
               Result.Task_Data.Receive_Contracts.Append (Parse_Name_Expression (State));
            end if;
         end loop;
      end Parse_Task_Channel_Clause;
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
                  Message => "only `priority` is supported in task aspect clauses"));
         end if;
         Advance (State);
         Require (State, "=");
         Result.Task_Data.Has_Explicit_Priority := True;
         Result.Task_Data.Priority := Parse_Expression (State);
         if Match (State, ",") then
            Parse_Task_Channel_Clause;
            while Current_Lower (State) = "sends" or else Current_Lower (State) = "receives" loop
               Parse_Task_Channel_Clause;
            end loop;
         end if;
      elsif Current_Lower (State) = "sends" or else Current_Lower (State) = "receives" then
         Parse_Task_Channel_Clause;
         while Current_Lower (State) = "sends" or else Current_Lower (State) = "receives" loop
            Parse_Task_Channel_Clause;
         end loop;
      elsif Match (State, ",") then
         Parse_Task_Channel_Clause;
         while Current_Lower (State) = "sends" or else Current_Lower (State) = "receives" loop
            Parse_Task_Channel_Clause;
         end loop;
      end if;
      Result.Task_Data.End_Name := Result.Task_Data.Name;
      if Match_Indent (State) then
         Suite_Already_Indented := True;
      elsif Empty_Body_Suite (State, Start)
      then
         Suite_Already_Indented := False;
      else
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path_String (State),
               Span    => Current (State).Span,
               Message => "expected indented block",
               Note    => "task bodies require an indented suite after the declaration line"));
      end if;
      if Suite_Already_Indented then
         while Current (State).Kind not in FL.Dedent | FL.End_Of_File loop
            declare
               Lower : constant String := Current_Lower (State);
            begin
               if not Saw_Statements
                 and then Current (State).Kind in FL.Identifier | FL.Keyword
                 and then Next (State).Lexeme = FT.To_UString (":")
               then
                  if Lower = "var" then
                     Reject_Statement_Local_Var_Outside_Statements (State);
                  elsif Lower in "type" | "subtype" | "function" | "procedure" then
                     Reject_Unsupported
                       (State,
                        "task declarative parts only support object declarations in the current PR08.1 concurrency subset");
                  elsif Lower in "task" | "channel" then
                     Reject_Unsupported
                       (State,
                        "nested task and channel declarations are outside the current PR08.1 concurrency subset");
                  end if;
                  Result.Task_Data.Declarations.Append
                    (Parse_Body_Local_Object_Declaration (State));
               else
                  Saw_Statements := True;
                  Append_Parsed_Statement (Result.Task_Data.Statements, Parse_Statement (State));
               end if;
            end;
         end loop;
      end if;
      if Suite_Already_Indented then
         Require_Dedent
           (State,
            "task bodies must dedent back to the enclosing declaration level");
      end if;
      Result.Task_Data.Span :=
        CM.Join
          (Start,
           (if not Result.Task_Data.Statements.Is_Empty
            then Suite_End_Span (Result.Task_Data.Statements, Start)
            elsif not Result.Task_Data.Declarations.Is_Empty
            then Result.Task_Data.Declarations (Result.Task_Data.Declarations.Last_Index).Span
            else Start));
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
      elsif Lower = "var" then
         Reject_Statement_Local_Var_Outside_Statements (State);
      elsif Lower = "task" then
         return Parse_Task_Declaration (State, Is_Public);
      elsif Lower = "channel" then
         return Parse_Channel_Declaration (State, Is_Public);
      elsif Lower = "for" then
         Reject_Removed_Source_Construct (State, "representation clause");
      elsif Lower in "generic" | "protected" | "accept" | "entry" then
         Reject_Unsupported
           (State,
            "package item `" & Lower & "` is outside the current PR08.1 concurrency subset");
      elsif Lower in "begin" | "end" | "then" then
         Raise_Diag
           (CM.Source_Frontend_Error
              (Path    => Path_String (State),
               Span    => Current (State).Span,
               Message =>
                 "legacy block delimiter `" & Lower
                 & "` is not allowed in package items; covered blocks are closed by indentation"));
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
      Ends         : FL.Token;
      Package_Name : CM.Expr_Access;
      Clause       : CM.With_Clause;
      Unit_Start   : FT.Source_Span := FT.Null_Span;
      Entry_Name   : constant String := Source_Stem (State);
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

      if Current_Lower (State) = "package" then
         Start_Token := Expect (State, "package");
         Package_Name := Parse_Package_Name (State);
         Result.Kind := CM.Unit_Package;
         Result.Package_Name := FT.To_UString (Name_To_String (Package_Name));
         Result.Has_End_Name := True;
         Result.End_Name := Result.Package_Name;
         Unit_Start := Start_Token.Span;
         Require_Indent
           (State,
            "package bodies require an indented suite after the package declaration");
         Parse_Unit_Suite (State, Result, Terminated => True);
         Require_Dedent
           (State,
            "package items and top-level statements must dedent back to column 1 at the end of the unit");
         if Current (State).Kind /= FL.End_Of_File then
            Raise_Diag
              (CM.Source_Frontend_Error
                 (Path    => Path_String (State),
                  Span    => Current (State).Span,
                  Message => "unexpected trailing tokens after package body",
                  Note    => "covered block syntax no longer uses explicit `end Package_Name;`"));
         end if;
      else
         if not Is_Lowercase_Identifier (Entry_Name) then
            Raise_Diag
              (CM.Source_Frontend_Error
                 (Path    => Path_String (State),
                  Span    => Current (State).Span,
                  Message =>
                    "packageless entry filename must be a lowercase Safe identifier",
                  Note    => "rename the file so its stem matches `[a-z][a-z0-9_]*`"));
         end if;
         Result.Kind := CM.Unit_Entry;
         Result.Package_Name := FT.To_UString (Entry_Name);
         Result.Has_End_Name := False;
         if Current (State).Kind = FL.End_Of_File then
            Unit_Start := Current (State).Span;
         else
            Unit_Start := Current (State).Span;
         end if;
         Parse_Unit_Suite (State, Result);
      end if;

      Result.Span :=
        CM.Join
          (Unit_Start,
           Unit_End_Span
             (Result.Items,
              Result.Statements,
              (if Result.Has_End_Name then Package_Name.Span else Unit_Start)));
      return (Success => True, Unit => Result);
   exception
      when Parse_Failure =>
         return (Success => False, Diagnostic => Raised_Diag);
   end Parse;
end Safe_Frontend.Check_Parse;
