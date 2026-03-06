with Ada.Characters.Latin_1;
with Ada.Strings.Unbounded;
with Safe_Frontend.Json;

package body Safe_Frontend.Semantics is
   package FA renames Safe_Frontend.Ast;
   package FD renames Safe_Frontend.Diagnostics;
   package FL renames Safe_Frontend.Lexer;
   package US renames Ada.Strings.Unbounded;

   use type FL.Token_Kind;

   function Allowed_With (Name : String) return Boolean is
      Lowered : constant String := FT.Lowercase (Name);
      Dot     : Natural := 0;
   begin
      for Index in Lowered'Range loop
         if Lowered (Index) = '.' then
            Dot := Index;
            exit;
         end if;
      end loop;
      declare
         Base_Name : constant String :=
           (if Dot = 0 then Lowered else Lowered (Lowered'First .. Dot - 1));
      begin
         return
           Base_Name = "ada"
           or else Base_Name = "system"
           or else Base_Name = "interfaces";
      end;
   end Allowed_With;

   function Is_Removed_Feature (Token : FL.Token) return Boolean is
      Lowered : constant String := FT.Lowercase (FT.To_String (Token.Lexeme));
   begin
      return
        Token.Kind = FL.Keyword
        and then Lowered in "generic" | "exception" | "raise" | "protected" | "accept" | "entry" | "requeue";
   end Is_Removed_Feature;

   function Analyze
     (Unit        : FA.Compilation_Unit;
      Tokens      : FL.Token_Vectors.Vector;
      Diagnostics : in out FD.Diagnostic_Vectors.Vector)
      return Typed_Unit
   is
      Result : Typed_Unit := (Ast => Unit, others => <>);
   begin
      if FT.To_String (Unit.Package_Name) /= FT.To_String (Unit.End_Name) then
         FD.Add_Error
           (Collection => Diagnostics,
            Path       => "",
            Span       => Unit.Span,
            Code       => "SC3001",
            Message    => "package end name does not match package name",
            Note       => "expected `" & FT.To_String (Unit.Package_Name) & "`");
      end if;

      for Clause of Unit.With_Clauses loop
         if not Clause.Package_Names.Is_Empty then
            declare
               First_Name : constant String := FT.To_String (Clause.Package_Names.First_Element);
            begin
               if not Allowed_With (First_Name) then
                  FD.Add_Error
                    (Collection => Diagnostics,
                     Path       => "",
                     Span       => Clause.Span,
                     Code       => "SC3003",
                     Message    =>
                       "with clause targets a package outside the retained-library subset",
                     Note       => "saw `" & First_Name & "`");
               end if;
            end;
         end if;
      end loop;

      for Token of Tokens loop
         if Is_Removed_Feature (Token) then
            FD.Add_Error
              (Collection => Diagnostics,
               Path       => "",
               Span       => Token.Span,
               Code       => "SC3002",
               Message    => "removed Safe feature is not supported by the early frontend",
               Note       => "token `" & FT.To_String (Token.Lexeme) & "` is outside the PR04 subset");
         end if;
      end loop;

      for Item of Unit.Items loop
         if Item.Is_Public then
            Result.Public_Declarations.Append
              ((Name      => Item.Name,
                Kind      => FT.To_UString (FA.Kind_Name (Item.Kind)),
                Signature => Item.Signature,
                Span      => Item.Span));
         end if;
         if Item.Kind in FA.Subprogram_Declaration | FA.Task_Declaration then
            Result.Executables.Append
              ((Name      => Item.Name,
                Kind      => FT.To_UString (FA.Kind_Name (Item.Kind)),
                Signature => Item.Signature,
                Span      => Item.Span));
         end if;
      end loop;
      return Result;
   end Analyze;

   function To_Json (Unit : Typed_Unit) return String is
      Result : US.Unbounded_String := US.Null_Unbounded_String;
   begin
      US.Append (Result, "{");
      US.Append (Result, """format"":""typed-v0"",");
      US.Append
        (Result,
         """package_name"":" & Safe_Frontend.Json.Quote (Unit.Ast.Package_Name) & ",");
      US.Append
        (Result,
         """package_end_name"":" & Safe_Frontend.Json.Quote (Unit.Ast.End_Name) & ",");
      US.Append (Result, """public_declarations"":[");
      if not Unit.Public_Declarations.Is_Empty then
         for Index in Unit.Public_Declarations.First_Index .. Unit.Public_Declarations.Last_Index loop
            declare
               Decl : constant Declaration_Summary := Unit.Public_Declarations.Element (Index);
            begin
               if Index > Unit.Public_Declarations.First_Index then
                  US.Append (Result, ",");
               end if;
               US.Append
                 (Result,
                  "{""name"":" & Safe_Frontend.Json.Quote (Decl.Name)
                  & ",""kind"":" & Safe_Frontend.Json.Quote (Decl.Kind)
                  & ",""signature"":" & Safe_Frontend.Json.Quote (Decl.Signature)
                  & ",""span"":" & Safe_Frontend.Json.Span_Object (Decl.Span)
                  & "}");
            end;
         end loop;
      end if;
      US.Append (Result, "],");
      US.Append (Result, """executables"":[");
      if not Unit.Executables.Is_Empty then
         for Index in Unit.Executables.First_Index .. Unit.Executables.Last_Index loop
            declare
               Exec : constant Executable_Summary := Unit.Executables.Element (Index);
            begin
               if Index > Unit.Executables.First_Index then
                  US.Append (Result, ",");
               end if;
               US.Append
                 (Result,
                  "{""name"":" & Safe_Frontend.Json.Quote (Exec.Name)
                  & ",""kind"":" & Safe_Frontend.Json.Quote (Exec.Kind)
                  & ",""signature"":" & Safe_Frontend.Json.Quote (Exec.Signature)
                  & ",""span"":" & Safe_Frontend.Json.Span_Object (Exec.Span)
                  & "}");
            end;
         end loop;
      end if;
      US.Append (Result, "],");
      US.Append (Result, """ast"":" & Safe_Frontend.Ast.To_Json (Unit.Ast));
      US.Append (Result, "}");
      return US.To_String (Result);
   end To_Json;

   function Interface_Json (Unit : Typed_Unit) return String is
      Result : US.Unbounded_String := US.Null_Unbounded_String;
   begin
      US.Append (Result, "{");
      US.Append (Result, """format"":""safei-v0"",");
      US.Append (Result, """package_name"":" & Safe_Frontend.Json.Quote (Unit.Ast.Package_Name) & ",");
      US.Append (Result, """public_declarations"":[");
      if not Unit.Public_Declarations.Is_Empty then
         for Index in Unit.Public_Declarations.First_Index .. Unit.Public_Declarations.Last_Index loop
            declare
               Decl : constant Declaration_Summary := Unit.Public_Declarations.Element (Index);
            begin
               if Index > Unit.Public_Declarations.First_Index then
                  US.Append (Result, ",");
               end if;
               US.Append
                 (Result,
                  "{""name"":" & Safe_Frontend.Json.Quote (Decl.Name)
                  & ",""kind"":" & Safe_Frontend.Json.Quote (Decl.Kind)
                  & ",""signature"":" & Safe_Frontend.Json.Quote (Decl.Signature)
                  & ",""span"":" & Safe_Frontend.Json.Span_Object (Decl.Span)
                  & "}");
            end;
         end loop;
      end if;
      US.Append (Result, "],");
      US.Append (Result, """executables"":[");
      if not Unit.Executables.Is_Empty then
         for Index in Unit.Executables.First_Index .. Unit.Executables.Last_Index loop
            declare
               Exec : constant Executable_Summary := Unit.Executables.Element (Index);
            begin
               if Index > Unit.Executables.First_Index then
                  US.Append (Result, ",");
               end if;
               US.Append
                 (Result,
                  "{""name"":" & Safe_Frontend.Json.Quote (Exec.Name)
                  & ",""kind"":" & Safe_Frontend.Json.Quote (Exec.Kind)
                  & ",""signature"":" & Safe_Frontend.Json.Quote (Exec.Signature)
                  & ",""span"":" & Safe_Frontend.Json.Span_Object (Exec.Span)
                  & "}");
            end;
         end loop;
      end if;
      US.Append (Result, "]}");
      return US.To_String (Result) & Ada.Characters.Latin_1.LF;
   end Interface_Json;
end Safe_Frontend.Semantics;
