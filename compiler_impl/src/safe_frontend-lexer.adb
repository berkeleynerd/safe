with Ada.Characters.Handling;
with Ada.Characters.Latin_1;
with Ada.Strings.Unbounded;
with Safe_Frontend.Json;

package body Safe_Frontend.Lexer is
   package FD renames Safe_Frontend.Diagnostics;
   package US renames Ada.Strings.Unbounded;

   function Kind_Name (Kind : Token_Kind) return String is
   begin
      case Kind is
         when Identifier =>
            return "identifier";
         when Keyword =>
            return "keyword";
         when Integer_Literal =>
            return "integer_literal";
         when Real_Literal =>
            return "real_literal";
         when String_Literal =>
            return "string_literal";
         when Character_Literal =>
            return "character_literal";
         when Symbol =>
            return "symbol";
         when End_Of_File =>
            return "end_of_file";
      end case;
   end Kind_Name;

   function Is_Identifier_Start (Ch : Character) return Boolean is
   begin
      return Ada.Characters.Handling.Is_Letter (Ch);
   end Is_Identifier_Start;

   function Is_Identifier_Continue (Ch : Character) return Boolean is
   begin
      return Ada.Characters.Handling.Is_Alphanumeric (Ch) or else Ch = '_';
   end Is_Identifier_Continue;

   function Is_Keyword (Item : String) return Boolean is
      Lowered : constant String := FT.Lowercase (Item);
   begin
      return
        Lowered in
          --  Ada 2022 reserved words retained in Safe (spec §8.15)
          "abort" | "abs" | "abstract" | "accept" | "access"
          | "aliased" | "all" | "and" | "array" | "at"
          | "begin" | "body" | "case" | "constant" | "declare"
          | "delay" | "delta" | "digits" | "do" | "else"
          | "elsif" | "end" | "entry" | "exception" | "exit"
          | "for" | "function" | "generic" | "goto" | "if"
          | "in" | "interface" | "is" | "limited" | "loop"
          | "mod" | "new" | "not" | "null" | "of"
          | "or" | "others" | "out" | "overriding" | "package"
          | "parallel" | "pragma" | "private" | "procedure" | "protected"
          | "raise" | "range" | "record" | "rem" | "renames"
          | "requeue" | "return" | "reverse" | "select" | "separate"
          | "some" | "subtype" | "synchronized" | "tagged" | "task"
          | "terminate" | "then" | "type" | "until" | "use"
          | "when" | "while" | "with" | "xor"
          --  Safe additional reserved words (spec §8.15)
          | "public" | "channel" | "send" | "receive"
          | "try_send" | "try_receive" | "capacity" | "from";
   end Is_Keyword;

   function Make_Span
     (Start_Line   : Positive;
      Start_Column : Positive;
      End_Line     : Positive;
      End_Column   : Positive) return FT.Source_Span is
   begin
      return
        (Start_Pos => (Line => Start_Line, Column => Start_Column),
         End_Pos   => (Line => End_Line, Column => End_Column));
   end Make_Span;

   function Lex
     (Input       : Safe_Frontend.Source.Source_File;
      Diagnostics : in out Safe_Frontend.Diagnostics.Diagnostic_Vectors.Vector)
      return Token_Vectors.Vector
   is
      Text   : constant String := FT.To_String (Input.Content);
      Tokens : Token_Vectors.Vector;
      Index  : Natural := 1;
      Line   : Positive := 1;
      Column : Positive := 1;

      procedure Advance is
      begin
         if Index <= Text'Length then
            if Text (Index) = Ada.Characters.Latin_1.LF then
               Line := Line + 1;
               Column := 1;
            else
               Column := Column + 1;
            end if;
            Index := Index + 1;
         end if;
      end Advance;

      function Peek (Offset : Natural := 0) return Character is
      begin
         if Index + Offset <= Text'Length then
            return Text (Index + Offset);
         end if;
         return Character'Val (0);
      end Peek;

      procedure Append_Token
        (Kind         : Token_Kind;
         Lexeme       : String;
         Start_Line   : Positive;
         Start_Column : Positive;
         End_Line     : Positive;
         End_Column   : Positive)
      is
      begin
         Tokens.Append
           ((Kind   => Kind,
             Lexeme => FT.To_UString (Lexeme),
             Span   => Make_Span (Start_Line, Start_Column, End_Line, End_Column)));
      end Append_Token;

      procedure Report_Legacy_Token
        (Lexeme       : String;
         Start_Line   : Positive;
         Start_Column : Positive;
         End_Line     : Positive;
         End_Column   : Positive) is
         Suggestion : constant String :=
           (if Lexeme = ":=" then
               "Use current Safe syntax (`=` for assignment)."
            elsif Lexeme = "/=" then
               "Use current Safe syntax (`!=` for inequality)."
            elsif Lexeme = "=>" then
               "Use current Safe syntax (`=` for named associations/aggregates and `then` for select arms)."
            else
               "Use current Safe syntax.");
      begin
         FD.Add_Error
           (Collection => Diagnostics,
            Path       => FT.To_String (Input.Path),
            Span       => Make_Span (Start_Line, Start_Column, End_Line, End_Column),
            Code       => "SC1001",
            Message    => "legacy token " & Character'Val (34) & Lexeme & Character'Val (34) & " is not allowed",
            Suggestion => Suggestion);
      end Report_Legacy_Token;

   begin
      while Index <= Text'Length loop
         if Peek = ' ' or else Peek = Ada.Characters.Latin_1.HT or else Peek = Ada.Characters.Latin_1.CR then
            Advance;
         elsif Peek = Ada.Characters.Latin_1.LF then
            Advance;
         elsif Peek = '-' and then Peek (1) = '-' then
            while Index <= Text'Length and then Peek /= Ada.Characters.Latin_1.LF loop
               Advance;
            end loop;
         elsif Is_Identifier_Start (Peek) then
            declare
               Start_Line   : constant Positive := Line;
               Start_Column : constant Positive := Column;
               Start_Index  : constant Natural := Index;
            begin
               Advance;
               while Index <= Text'Length and then Is_Identifier_Continue (Peek) loop
                  Advance;
               end loop;
               declare
                  Lexeme : constant String := Text (Start_Index .. Index - 1);
                  Kind   : constant Token_Kind :=
                    (if Is_Keyword (Lexeme) then Keyword else Identifier);
               begin
                  Append_Token
                    (Kind,
                     Lexeme,
                     Start_Line,
                     Start_Column,
                     Line,
                     (if Column = 1 then 1 else Column - 1));
               end;
            end;
         elsif Ada.Characters.Handling.Is_Digit (Peek) then
            declare
               Start_Line   : constant Positive := Line;
               Start_Column : constant Positive := Column;
               Start_Index  : constant Natural := Index;
               Is_Real      : Boolean := False;
            begin
               Advance;
               while Index <= Text'Length and then
                 (Ada.Characters.Handling.Is_Digit (Peek) or else Peek = '_')
               loop
                  Advance;
               end loop;
               if Peek = '.' and then Peek (1) /= '.' then
                  Is_Real := True;
                  Advance;
                  while Index <= Text'Length and then
                    (Ada.Characters.Handling.Is_Digit (Peek) or else Peek = '_')
                  loop
                     Advance;
                  end loop;
               end if;
               if Peek = 'e' or else Peek = 'E' then
                  Is_Real := True;
                  Advance;
                  if Peek = '+' or else Peek = '-' then
                     Advance;
                  end if;
                  while Index <= Text'Length and then
                    (Ada.Characters.Handling.Is_Digit (Peek) or else Peek = '_')
                  loop
                     Advance;
                  end loop;
               end if;
               Append_Token
                 ((if Is_Real then Real_Literal else Integer_Literal),
                  Text (Start_Index .. Index - 1),
                  Start_Line,
                  Start_Column,
                  Line,
                  (if Column = 1 then 1 else Column - 1));
            end;
         elsif Peek = Character'Val (34) then
            declare
               Start_Line   : constant Positive := Line;
               Start_Column : constant Positive := Column;
               Start_Index  : constant Natural := Index;
            begin
               Advance;
               while Index <= Text'Length and then Peek /= Character'Val (34) loop
                  Advance;
               end loop;
               if Index <= Text'Length then
                  Advance;
               end if;
               Append_Token
                 (String_Literal,
                  Text (Start_Index .. Index - 1),
                  Start_Line,
                  Start_Column,
                  Line,
                  (if Column = 1 then 1 else Column - 1));
            end;
         elsif Peek = ''' and then Index + 2 <= Text'Length and then Text (Index + 2) = ''' then
            declare
               Start_Line   : constant Positive := Line;
               Start_Column : constant Positive := Column;
               Start_Index  : constant Natural := Index;
            begin
               Advance;
               Advance;
               Advance;
               Append_Token
                 (Character_Literal,
                  Text (Start_Index .. Index - 1),
                  Start_Line,
                  Start_Column,
                  Line,
                  (if Column = 1 then 1 else Column - 1));
            end;
         else
            declare
               Start_Line   : constant Positive := Line;
               Start_Column : constant Positive := Column;
               Two_Char     : constant String :=
                 (if Index + 1 <= Text'Length then Text (Index .. Index + 1) else "");
            begin
               if Two_Char in ".." | ":=" | "!=" | "<=" | ">=" | "=>" | "/=" | "==" then
                  Advance;
                  Advance;
                  Append_Token
                    (Symbol,
                     Two_Char,
                     Start_Line,
                     Start_Column,
                     Line,
                     (if Column = 1 then 1 else Column - 1));
                  if Two_Char in ":=" | "=>" | "/=" then
                     Report_Legacy_Token
                       (Two_Char,
                        Start_Line,
                        Start_Column,
                        Line,
                        (if Column = 1 then 1 else Column - 1));
                  end if;
               else
                  declare
                     Single : constant String := (1 => Peek);
                  begin
                     Advance;
                     Append_Token
                       (Symbol,
                        Single,
                        Start_Line,
                        Start_Column,
                        Line,
                        (if Column = 1 then 1 else Column - 1));
                  end;
               end if;
            end;
         end if;
      end loop;

      Tokens.Append
        ((Kind   => End_Of_File,
          Lexeme => FT.To_UString ("<eof>"),
          Span   => Make_Span (Line, Column, Line, Column)));
      return Tokens;
   end Lex;

   function To_Json (Tokens : Token_Vectors.Vector) return String is
      Result : US.Unbounded_String := US.Null_Unbounded_String;
      First  : Boolean := True;
   begin
      US.Append (Result, "{""format"":""tokens-v0"",""tokens"":[");
      if not Tokens.Is_Empty then
         for Index in Tokens.First_Index .. Tokens.Last_Index loop
            declare
               Item : constant Token := Tokens.Element (Index);
            begin
               if Item.Kind /= End_Of_File then
                  if not First then
                     US.Append (Result, ",");
                  end if;
                  First := False;
                  US.Append
                    (Result,
                     "{""kind"":"
                     & Safe_Frontend.Json.Quote (Kind_Name (Item.Kind))
                     & ",""lexeme"":"
                     & Safe_Frontend.Json.Quote (Item.Lexeme)
                     & ",""span"":"
                     & Safe_Frontend.Json.Span_Object (Item.Span)
                     & "}");
               end if;
            end;
         end loop;
      end if;
      US.Append (Result, "]}");
      return US.To_String (Result);
   end To_Json;
end Safe_Frontend.Lexer;
