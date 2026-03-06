with Ada.Strings.Unbounded;
with Safe_Frontend.Types;

package body Safe_Frontend.Parser is
   package FA renames Safe_Frontend.Ast;
   package FD renames Safe_Frontend.Diagnostics;
   package FL renames Safe_Frontend.Lexer;
   package FT renames Safe_Frontend.Types;
   package US renames Ada.Strings.Unbounded;

   use type FL.Token_Kind;

   type Parser_State is record
      Input       : Safe_Frontend.Source.Source_File;
      Tokens      : FL.Token_Vectors.Vector;
      Index       : Positive := 1;
      Diagnostics : access FD.Diagnostic_Vectors.Vector;
   end record;

   function Current (State : Parser_State) return FL.Token is
   begin
      return State.Tokens.Element (State.Index);
   end Current;

   function Next (State : Parser_State; Offset : Natural := 1) return FL.Token is
      Candidate : constant Positive :=
        Positive'Min (State.Index + Positive (Offset), State.Tokens.Last_Index);
   begin
      return State.Tokens.Element (Candidate);
   end Next;

   procedure Advance (State : in out Parser_State) is
   begin
      if State.Index < State.Tokens.Last_Index then
         State.Index := State.Index + 1;
      end if;
   end Advance;

   function Current_Lower (State : Parser_State) return String is
   begin
      return FT.Lowercase (FT.To_String (Current (State).Lexeme));
   end Current_Lower;

   function Match (State : in out Parser_State; Lexeme : String) return Boolean is
   begin
      if Current_Lower (State) = FT.Lowercase (Lexeme) then
         Advance (State);
         return True;
      end if;
      return False;
   end Match;

   procedure Expect (State : in out Parser_State; Lexeme : String; Message : String) is
   begin
      if not Match (State, Lexeme) then
         FD.Add_Error
           (Collection => State.Diagnostics.all,
            Path       => FT.To_String (State.Input.Path),
            Span       => Current (State).Span,
            Code       => "SC2001",
            Message    => Message,
            Note       => "saw token `" & FT.To_String (Current (State).Lexeme) & "`");
      end if;
   end Expect;

   function Span_From
     (State       : Parser_State;
      Start_Index : Positive;
      End_Index   : Positive) return FT.Source_Span is
   begin
      return
        (Start_Pos => State.Tokens.Element (Start_Index).Span.Start_Pos,
         End_Pos   => State.Tokens.Element (End_Index).Span.End_Pos);
   end Span_From;

   function Join_Tokens
     (State       : Parser_State;
      Start_Index : Positive;
      End_Index   : Positive) return FT.UString
   is
      Result : US.Unbounded_String := US.Null_Unbounded_String;
   begin
      for Index in Start_Index .. End_Index loop
         if Index > Start_Index then
            US.Append (Result, " ");
         end if;
         US.Append (Result, FT.To_String (State.Tokens.Element (Index).Lexeme));
      end loop;
      return Result;
   end Join_Tokens;

   function Read_Qualified_Name (State : in out Parser_State) return FT.UString is
      Result : US.Unbounded_String := US.Null_Unbounded_String;
   begin
      while Current (State).Kind = FL.Identifier
        or else Current (State).Kind = FL.Keyword
      loop
         if US.Length (Result) > 0 then
            US.Append (Result, ".");
         end if;
         US.Append (Result, FT.To_String (Current (State).Lexeme));
         Advance (State);
         exit when FT.To_String (Current (State).Lexeme) /= ".";
         Advance (State);
      end loop;
      return Result;
   end Read_Qualified_Name;

   function Consume_Simple_Declaration (State : in out Parser_State) return Positive is
      Paren_Depth : Natural := 0;
      Block_Depth : Natural := 0;
      Last_Index  : Positive := State.Index;
   begin
      loop
         Last_Index := State.Index;
         exit when Current (State).Kind = FL.End_Of_File;

         if FT.To_String (Current (State).Lexeme) = "(" then
            Paren_Depth := Paren_Depth + 1;
         elsif FT.To_String (Current (State).Lexeme) = ")" and then Paren_Depth > 0 then
            Paren_Depth := Paren_Depth - 1;
         elsif Paren_Depth = 0 then
            if Current_Lower (State) in "record" | "case" then
               Block_Depth := Block_Depth + 1;
            elsif Current_Lower (State) = "end"
              and then Block_Depth > 0
              and then FT.Lowercase (FT.To_String (Next (State).Lexeme)) in "record" | "case"
            then
               Block_Depth := Block_Depth - 1;
            elsif FT.To_String (Current (State).Lexeme) = ";" and then Block_Depth = 0 then
               Advance (State);
               return Last_Index;
            end if;
         end if;
         Advance (State);
      end loop;
      return Last_Index;
   end Consume_Simple_Declaration;

   function Consume_Named_Executable_Item
     (State      : in out Parser_State;
      Designator : FT.UString) return Positive
   is
      Last_Index : Positive := State.Index;
      Target     : constant String := FT.Lowercase (FT.To_String (Designator));
   begin
      loop
         Last_Index := State.Index;
         exit when Current (State).Kind = FL.End_Of_File;
         if Current_Lower (State) = "end"
           and then FT.Lowercase (FT.To_String (Next (State).Lexeme)) = Target
         then
            Advance (State);
            Advance (State);
            while Current (State).Kind /= FL.End_Of_File
              and then FT.To_String (Current (State).Lexeme) /= ";"
            loop
               Advance (State);
            end loop;
            if FT.To_String (Current (State).Lexeme) = ";" then
               Last_Index := State.Index;
               Advance (State);
            end if;
            return Last_Index;
         end if;
         Advance (State);
      end loop;
      return Last_Index;
   end Consume_Named_Executable_Item;

   function Parse_Item (State : in out Parser_State) return FA.Package_Item is
      Start_Index : constant Positive := State.Index;
      Item        : FA.Package_Item;
      End_Index   : Positive := State.Index;
   begin
      Item.Is_Public := Match (State, "public");

      if Current_Lower (State) = "type" then
         Item.Kind := FA.Type_Declaration;
         Advance (State);
         if Current (State).Kind = FL.Identifier
           or else Current (State).Kind = FL.Keyword
         then
            Item.Name := Current (State).Lexeme;
         end if;
         End_Index := Consume_Simple_Declaration (State);
      elsif Current_Lower (State) = "subtype" then
         Item.Kind := FA.Subtype_Declaration;
         Advance (State);
         if Current (State).Kind = FL.Identifier
           or else Current (State).Kind = FL.Keyword
         then
            Item.Name := Current (State).Lexeme;
         end if;
         End_Index := Consume_Simple_Declaration (State);
      elsif Current_Lower (State) = "channel" then
         Item.Kind := FA.Channel_Declaration;
         Advance (State);
         if Current (State).Kind = FL.Identifier
           or else Current (State).Kind = FL.Keyword
         then
            Item.Name := Current (State).Lexeme;
            Advance (State);
         end if;
         if Match (State, ":") then
            declare
               Element_Start : constant Positive := State.Index;
            begin
               while Current (State).Kind /= FL.End_Of_File and then Current_Lower (State) /= "capacity" loop
                  Advance (State);
               end loop;
               Item.Element_Type := Join_Tokens (State, Element_Start, State.Index - 1);
            end;
            if Match (State, "capacity") then
               declare
                  Capacity_Start : constant Positive := State.Index;
               begin
                  while Current (State).Kind /= FL.End_Of_File and then FT.To_String (Current (State).Lexeme) /= ";" loop
                     Advance (State);
                  end loop;
                  Item.Capacity_Text := Join_Tokens (State, Capacity_Start, State.Index - 1);
               end;
            end if;
         end if;
         End_Index := Consume_Simple_Declaration (State);
      elsif Current_Lower (State) = "task" then
         Item.Kind := FA.Task_Declaration;
         Item.Has_Body := True;
         Advance (State);
         if Current (State).Kind = FL.Identifier
           or else Current (State).Kind = FL.Keyword
         then
            Item.Name := Current (State).Lexeme;
         end if;
         End_Index := Consume_Named_Executable_Item (State, Item.Name);
      elsif Current_Lower (State) in "function" | "procedure" then
         Item.Kind := FA.Subprogram_Declaration;
         Item.Has_Body := True;
         Advance (State);
         if Current (State).Kind = FL.Identifier
           or else Current (State).Kind = FL.Keyword
         then
            Item.Name := Current (State).Lexeme;
            Advance (State);
         end if;
         declare
            Signature_Start : constant Positive := Start_Index;
         begin
            while Current (State).Kind /= FL.End_Of_File and then Current_Lower (State) /= "begin" loop
               if Current_Lower (State) = "return" then
                  Advance (State);
                  if Current (State).Kind = FL.Identifier
                    or else Current (State).Kind = FL.Keyword
                  then
                     Item.Return_Type := Current (State).Lexeme;
                  end if;
               else
                  Advance (State);
               end if;
            end loop;
            Item.Signature := Join_Tokens (State, Signature_Start, State.Index - 1);
         end;
         End_Index := Consume_Named_Executable_Item (State, Item.Name);
      elsif Current_Lower (State) = "use" and then FT.Lowercase (FT.To_String (Next (State).Lexeme)) = "type" then
         Item.Kind := FA.Use_Type_Clause;
         Advance (State);
         Advance (State);
         Item.Name := Read_Qualified_Name (State);
         End_Index := Consume_Simple_Declaration (State);
      elsif Current_Lower (State) = "pragma" then
         Item.Kind := FA.Pragma_Item;
         Advance (State);
         if Current (State).Kind = FL.Identifier
           or else Current (State).Kind = FL.Keyword
         then
            Item.Name := Current (State).Lexeme;
         end if;
         End_Index := Consume_Simple_Declaration (State);
      elsif Current_Lower (State) = "for" then
         Item.Kind := FA.Representation_Item;
         End_Index := Consume_Simple_Declaration (State);
      elsif Current (State).Kind = FL.Identifier
        or else Current (State).Kind = FL.Keyword
      then
         Item.Kind := FA.Object_Declaration;
         Item.Name := Current (State).Lexeme;
         End_Index := Consume_Simple_Declaration (State);
      else
         Item.Kind := FA.Unknown_Item;
         FD.Add_Error
           (Collection => State.Diagnostics.all,
            Path       => FT.To_String (State.Input.Path),
            Span       => Current (State).Span,
            Code       => "SC2002",
            Message    => "could not classify package item",
            Note       => "parser recovered by skipping to the next declaration boundary");
         End_Index := Consume_Simple_Declaration (State);
      end if;

      Item.Span := Span_From (State, Start_Index, End_Index);
      Item.Header_Text := Join_Tokens (State, Start_Index, End_Index);
      if FT.To_String (Item.Signature)'Length = 0 then
         Item.Signature := Item.Header_Text;
      end if;
      return Item;
   end Parse_Item;

   function Parse
     (Input       : Safe_Frontend.Source.Source_File;
      Tokens      : Safe_Frontend.Lexer.Token_Vectors.Vector;
      Diagnostics :
        aliased in out Safe_Frontend.Diagnostics.Diagnostic_Vectors.Vector)
      return Safe_Frontend.Ast.Compilation_Unit
   is
      State      : Parser_State :=
        (Input       => Input,
         Tokens      => Tokens,
         Index       => Tokens.First_Index,
         Diagnostics => Diagnostics'Unchecked_Access);
      Unit              : FA.Compilation_Unit;
      Start_Token       : constant Positive := Tokens.First_Index;
      Package_End_Start : Natural := 0;
      Package_End_Name  : Natural := 0;
      Package_End_Last  : Natural := 0;
   begin
      while Current_Lower (State) = "with" loop
         declare
            Clause : FA.With_Clause;
            Start  : constant Positive := State.Index;
         begin
            Advance (State);
            loop
               Clause.Package_Names.Append
                 (New_Item => Read_Qualified_Name (State));
               exit when not Match (State, ",");
            end loop;
            Expect (State, ";", "expected ';' after with clause");
            Clause.Span := Span_From (State, Start, State.Index - 1);
            Unit.With_Clauses.Append (Clause);
         end;
      end loop;

      Expect (State, "package", "expected 'package' at compilation-unit start");
      if Current (State).Kind = FL.Identifier
        or else Current (State).Kind = FL.Keyword
      then
         Unit.Package_Name := Current (State).Lexeme;
         Advance (State);
      end if;
      Expect (State, "is", "expected 'is' after package name");

      declare
         Target_Name : constant String := FT.Lowercase (FT.To_String (Unit.Package_Name));
      begin
         for Index in reverse Tokens.First_Index + 2 .. Tokens.Last_Index loop
            if FT.To_String (Tokens.Element (Index).Lexeme) = ";"
              and then FT.Lowercase (FT.To_String (Tokens.Element (Index - 2).Lexeme)) = "end"
              and then FT.Lowercase (FT.To_String (Tokens.Element (Index - 1).Lexeme)) = Target_Name
            then
               Package_End_Start := Index - 2;
               Package_End_Name := Index - 1;
               Package_End_Last := Index;
               exit;
            end if;
         end loop;
      end;

      if Package_End_Start = 0 then
         FD.Add_Error
           (Collection => Diagnostics,
            Path       => FT.To_String (Input.Path),
            Span       => Tokens.Last_Element.Span,
            Code       => "SC2001",
            Message    => "expected final package terminator `end " & FT.To_String (Unit.Package_Name) & ";`");
         return Unit;
      end if;

      while Current (State).Kind /= FL.End_Of_File and then State.Index < Package_End_Start loop
         Unit.Items.Append (Parse_Item (State));
      end loop;

      Unit.End_Name := Tokens.Element (Package_End_Name).Lexeme;
      if State.Index <= Package_End_Last then
         State.Index := Positive (Package_End_Last + 1);
      end if;

      Unit.Span := Span_From (State, Start_Token, State.Index - 1);
      return Unit;
   end Parse;
end Safe_Frontend.Parser;
