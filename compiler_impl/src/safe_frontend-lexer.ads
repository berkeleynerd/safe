with Ada.Containers.Indefinite_Vectors;
with Safe_Frontend.Diagnostics;
with Safe_Frontend.Source;
with Safe_Frontend.Types;

package Safe_Frontend.Lexer is
   package FT renames Safe_Frontend.Types;

   type Token_Kind is
     (Identifier,
      Keyword,
      Integer_Literal,
      Real_Literal,
      String_Literal,
      Character_Literal,
      Indent,
      Dedent,
      Symbol,
      End_Of_File);

   type Token is record
      Kind         : Token_Kind := End_Of_File;
      Lexeme       : FT.UString := FT.To_UString ("");
      Span         : FT.Source_Span := FT.Null_Span;
      Logical_Line : Positive := 1;
   end record;

   package Token_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => Token);

   function Lex
     (Input       : Safe_Frontend.Source.Source_File;
      Diagnostics : in out Safe_Frontend.Diagnostics.Diagnostic_Vectors.Vector)
      return Token_Vectors.Vector;

   function To_Json (Tokens : Token_Vectors.Vector) return String;
end Safe_Frontend.Lexer;
